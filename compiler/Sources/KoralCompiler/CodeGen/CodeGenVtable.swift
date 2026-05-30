// MARK: - Vtable Code Generation
//
// This file contains all vtable-related code generation logic for trait objects:
// - Vtable request processing (resolving method names, orchestrating generation)
// - Vtable struct definition generation
// - Wrapper function generation (for self-by-value methods)
// - Vtable instance generation (static const globals)
// - Trait object conversion (T ref → TraitName ref)
// - Trait method dynamic dispatch calls

// MARK: - Vtable Request Processing

struct CodeGenTraitCallArgument {
  let value: String
  let type: Type
  let ownership: MIROwnershipUse
}

extension CodeGen {

  private func sanitizeTraitMangleToken(_ raw: String) -> String {
    String(raw.map { ch in
      if ch.isLetter || ch.isNumber || ch == "_" {
        return ch
      }
      return "_"
    })
  }

  private func traitImplementationTag(traitName: String, traitTypeArgs: [Type]) -> String {
    let traitPart = sanitizeTraitMangleToken(traitName)
    guard !traitTypeArgs.isEmpty else {
      return traitPart
    }
    let argsPart = traitTypeArgs
      .map { sanitizeTraitMangleToken($0.stableKey) }
      .joined(separator: "_")
    return "\(traitPart)_\(argsPart)"
  }
  
  /// Resolves the actual C function name for a concrete type's trait method implementation.
  ///
  /// Searches through MIR given globals for matching method declarations,
  /// or falls back to the MIR static method lookup table.
  ///
  /// - Parameters:
  ///   - concreteType: The concrete type (e.g., `.structure(defId)`)
  ///   - traitName: The trait name (e.g., "ToString")
  ///   - traitTypeArgs: Concrete trait type arguments for generic traits
  ///   - methodName: The trait method name (e.g., "message")
  /// - Returns: The C identifier for the method implementation, or nil if not found
  private func resolveMethodCName(
    concreteType: Type,
    traitName: String,
    traitTypeArgs: [Type],
    methodName: String
  ) -> String? {
    let typeQualifiedName: String?
    switch concreteType {
    case .structure(let defId):
      typeQualifiedName = context.getQualifiedName(defId) ?? context.getName(defId)
    case .`enum`(let defId):
      typeQualifiedName = context.getQualifiedName(defId) ?? context.getName(defId)
    default:
      typeQualifiedName = nil
    }

    let compositeTraitTag = traitImplementationTag(traitName: traitName, traitTypeArgs: traitTypeArgs)
    let compositeTraitMethodName = typeQualifiedName.map { qualifiedTypeName in
      "\(qualifiedTypeName)_trait_\(compositeTraitTag)_\(methodName)"
    }

    // Strategy 1: Search through MIR given globals for a matching method.
    for node in mirProgram.globals {
      guard case .given(let type, let trait, let methods) = node else { continue }
      guard type == concreteType else { continue }

      if let trait {
        if trait.traitName != traitName {
          continue
        }
        if trait.traitTypeArgs != traitTypeArgs {
          continue
        }
      }
      
      for method in methods {
        let logicalMethodName = mirProgram.receiverMethodDispatch[method.defId]?.methodName
          ?? context.getName(method.defId)
          ?? ""
        if logicalMethodName == methodName {
          return cIdentifier(for: method)
        }

        let emittedMethodSymbolName = context.getName(method.defId) ?? ""
        if let compositeTraitMethodName, emittedMethodSymbolName == compositeTraitMethodName {
          return cIdentifier(for: method)
        }
        if emittedMethodSymbolName == methodName {
          return cIdentifier(for: method)
        }
        if emittedMethodSymbolName.hasSuffix("_\(methodName)") {
          return cIdentifier(for: method)
        }
      }
    }
    
    // Strategy 2: Use staticMethodLookup table
    let typeName: String?
    switch concreteType {
    case .structure(let defId):
      typeName = context.getName(defId)
    case .`enum`(let defId):
      typeName = context.getName(defId)
    default:
      typeName = nil
    }
    
    if let typeName = typeName {
      return lookupStaticMethod(typeName: typeName, methodName: methodName)
    }
    
    return nil
  }

  /// Processes all vtable requests collected during monomorphization.
  ///
  /// For each (concreteType, trait) combination in MIR trait-vtable globals:
  /// 1. Generates the vtable struct definition (once per trait)
  /// 2. For each self-by-value method, generates a wrapper function
  /// 3. Generates the vtable instance (static const global)
  ///
  /// This method should be called from `generateProgram()` after function declarations
  /// but before function implementations, so that wrapper functions and vtable instances
  /// are available when function bodies reference them.
  func processVtableRequests() {
    var requestByKey: [MIRTraitVTableKey: MIRTraitVTable] = [:]
    for global in mirProgram.globals {
      if case .traitVTable(let request) = global {
        requestByKey[request.key] = request
      }
    }
    let requests = Array(requestByKey.values)
    guard !requests.isEmpty else { return }
    
    // Track which trait vtable struct definitions have been generated
    var generatedVtableStructs: Set<String> = []
    
    // Sort requests for deterministic output
    let sortedRequests = requests.sorted { a, b in
      if a.traitName != b.traitName { return a.traitName < b.traitName }
      let aArgs = a.traitTypeArguments.map(\.stableKey).joined(separator: ",")
      let bArgs = b.traitTypeArguments.map(\.stableKey).joined(separator: ",")
      if aArgs != bArgs { return aArgs < bArgs }
      return a.concreteType.stableKey < b.concreteType.stableKey
    }
    
    buffer += "// Vtable definitions\n"
    
    for request in sortedRequests {
      let traitName = request.traitName
      
      // Get the concrete type's C identifier
      guard let concreteTypeCName = concreteTypeCIdentifier(request.concreteType) else {
        continue
      }
      
      let orderedMethods = request.methods
      
      // For generic traits, the vtable struct key includes type args
      let vtableStructKey = vtableStructKeyName(traitName: traitName, traitTypeArgs: request.traitTypeArguments)
      let vtableStructCName = vtableStructCIdentifier(traitName: traitName, traitTypeArgs: request.traitTypeArguments)
      
      // Step 1: Generate vtable struct definition (once per trait specialization)
      if !generatedVtableStructs.contains(vtableStructKey) {
        generatedVtableStructs.insert(vtableStructKey)
        if let structDef = generateVtableStructDefinition(
          methods: orderedMethods,
          vtableStructName: vtableStructCName
        ) {
          buffer += structDef
          buffer += "\n"
        }
      }
      
      // Step 2: Resolve actual method C names and generate wrappers
      var actualMethodCNames: [String: String] = [:]
      
      for method in orderedMethods {
        let methodName = method.name
        // Resolve the actual method C name for this concrete type
        guard let actualCName = resolveMethodCName(
          concreteType: request.concreteType,
          traitName: traitName,
          traitTypeArgs: request.traitTypeArguments,
          methodName: methodName
        ) else {
          continue
        }
        
        actualMethodCNames[methodName] = actualCName
        
        // Generate wrapper function for self-by-value methods
        if let wrapperCode = generateWrapperFunction(
          concreteType: request.concreteType,
          concreteTypeCName: concreteTypeCName,
          traitName: traitName,
          methodName: methodName,
          method: method,
          actualMethodCName: actualCName
        ) {
          buffer += wrapperCode
          buffer += "\n"
        }
      }
      
      // Step 3: Generate vtable instance
      if let instanceCode = generateVtableInstance(
        concreteTypeCName: concreteTypeCName,
        traitName: traitName,
        traitTypeArgs: request.traitTypeArguments,
        methods: orderedMethods,
        actualMethodCNames: actualMethodCNames
      ) {
        buffer += instanceCode
        buffer += "\n"
      }
    }
  }
}

// MARK: - Vtable Struct Generation

extension CodeGen {

  /// Generates the vtable struct type definition for a trait.
  ///
  /// For example, for `trait Error { message(self) String }`, generates:
  /// ```c
  /// struct __koral_vtable_Error {
  ///     struct std_String (*message)(struct Ref);
  /// };
  /// ```
  ///
  /// All function pointers in the vtable take `struct Ref` as the first parameter (the receiver).
  /// Methods are ordered by declaration order, with parent trait methods first.
  ///
  /// - Parameters:
  ///   - methods: Ordered vtable methods lowered into MIR
  ///   - vtableStructName: The C name for the vtable struct
  /// - Returns: The generated C code for the vtable struct definition
  func generateVtableStructDefinition(methods: [MIRTraitVTableMethod], vtableStructName: String) -> String? {
    // Build the vtable struct
    var code = "struct \(vtableStructName) {\n"
    
    for method in methods {
      let returnCType = method.returnType.map { cTypeName($0) } ?? "void"
      
      // Build parameter list: first param is always struct Ref (the receiver)
      var paramTypes = ["struct __koral_Ref"]
      
      // Add non-self parameters
      for param in method.parameters where !param.isSelf {
        if let type = param.type {
          paramTypes.append(cTypeName(type))
        }
      }
      
      let paramsStr = paramTypes.joined(separator: ", ")
      let sanitizedMethodName = sanitizeCIdentifier(method.name)
      code += "    \(returnCType) (*\(sanitizedMethodName))(\(paramsStr));\n"
    }
    
    code += "};\n"
    return code
  }
}

// MARK: - Wrapper Function Generation

extension CodeGen {
  
  /// Returns the C identifier for a concrete type, used in function names like `std_String`.
  ///
  /// For `.structure(defId)` → looks up the C identifier from the defId map
  /// For `.enum(defId)` → same lookup
  /// For primitive types → returns the C type name directly
  func concreteTypeCIdentifier(_ type: Type) -> String? {
    switch type {
    case .structure(let defId):
      return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
    case .`enum`(let defId):
      return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
    default:
      return nil
    }
  }
  
  /// Determines whether a concrete type has a compiler-generated copy function (`__koral_{name}_copy`).
  ///
  /// Structs and enums always have copy functions. Primitive types do not.
  func hasCopyFunction(_ type: Type) -> Bool {
    switch type {
    case .structure, .`enum`:
      return true
    default:
      return false
    }
  }
  
  /// Generates a wrapper function for a `self` by value trait method.
  ///
  /// The wrapper receives `struct Ref` as the first parameter (matching the vtable signature),
  /// reads the concrete type value from `ref.ptr` using the copy function, then calls the actual method.
  ///
  /// For `self ref` methods, returns `nil` — no wrapper is needed since the actual method
  /// already takes `struct Ref`.
  ///
  /// Example output for `String` implementing `Error.message(self) String`:
  /// ```c
  /// static struct std_String __koral_wrapper_std_String_Error_message(struct Ref self_ref) {
  ///     struct std_String self_val = __koral_std_String_copy((struct std_String*)self_ref.ptr);
  ///     return std_String_Error_message(self_val);
  /// }
  /// ```
  func generateWrapperFunction(
    concreteType: Type,
    concreteTypeCName: String,
    traitName: String,
    methodName: String,
    method: MIRTraitVTableMethod,
    actualMethodCName: String
  ) -> String? {
    // self ref methods don't need a wrapper
    guard method.selfByValue else {
      return nil
    }
    
    let sanitizedTraitName = sanitizeCIdentifier(traitName)
    let sanitizedMethodName = sanitizeCIdentifier(methodName)
    let sanitizedConcreteTypeCName = sanitizeCIdentifier(concreteTypeCName)
    let wrapperName = "__koral_wrapper_\(sanitizedConcreteTypeCName)_\(sanitizedTraitName)_\(sanitizedMethodName)"
    
    let returnCType = method.returnType.map { cTypeName($0) } ?? "void"
    
    // Build parameter list: first is always `struct Ref self_ref`
    var paramDecls = ["struct __koral_Ref self_ref"]
    var paramNames: [String] = []
    
    // Add non-self parameters
    for param in method.parameters where !param.isSelf {
      let paramCName = sanitizeCIdentifier(param.name)
      if let type = param.type {
        paramDecls.append("\(cTypeName(type)) \(paramCName)")
        paramNames.append(paramCName)
      }
    }
    
    let paramsStr = paramDecls.joined(separator: ", ")
    
    // Generate the wrapper function body
    var code = "static \(returnCType) \(wrapperName)(\(paramsStr)) {\n"
    
    // Read the concrete value from ref.ptr
    let concreteCType = cTypeName(concreteType)
    if hasCopyFunction(concreteType) {
      // Use copy function to properly retain internal reference fields
      code += "    \(concreteCType) self_val = __koral_\(sanitizedConcreteTypeCName)_copy((\(concreteCType)*)self_ref.ptr);\n"
    } else {
      // Pure value type (primitive) — bitwise copy is sufficient
      code += "    \(concreteCType) self_val = *(\(concreteCType)*)self_ref.ptr;\n"
    }
    
    // Build the actual method call
    var callArgs = ["self_val"]
    callArgs.append(contentsOf: paramNames)
    let callArgsStr = callArgs.joined(separator: ", ")
    
    let isVoidReturn = (returnCType == "void")
    if isVoidReturn {
      code += "    \(actualMethodCName)(\(callArgsStr));\n"
      code += "    __koral_release(self_ref.control);\n"
    } else {
      code += "    \(returnCType) __koral_ret = \(actualMethodCName)(\(callArgsStr));\n"
      code += "    __koral_release(self_ref.control);\n"
      code += "    return __koral_ret;\n"
    }
    
    code += "}\n"
    return code
  }
  
  /// Returns the wrapper function name for a given (concreteType, trait, method) combination.
  ///
  /// Naming convention: `__koral_wrapper_{ConcreteType}_{TraitName}_{methodName}`
  func wrapperFunctionName(
    concreteTypeCName: String,
    traitName: String,
    methodName: String
  ) -> String {
    let sanitizedConcreteTypeCName = sanitizeCIdentifier(concreteTypeCName)
    let sanitizedTraitName = sanitizeCIdentifier(traitName)
    let sanitizedMethodName = sanitizeCIdentifier(methodName)
    return "__koral_wrapper_\(sanitizedConcreteTypeCName)_\(sanitizedTraitName)_\(sanitizedMethodName)"
  }
}

// MARK: - Generic Trait Vtable Naming

extension CodeGen {
  
  /// Returns a deduplication key for a vtable struct definition.
  /// For non-generic traits, this is just the trait name.
  /// For generic traits, this includes the type args to distinguish specializations.
  func vtableStructKeyName(traitName: String, traitTypeArgs: [Type]) -> String {
    if traitTypeArgs.isEmpty {
      return traitName
    }
    let argKeys = traitTypeArgs.map { $0.stableKey }.joined(separator: ",")
    return "\(traitName)<\(argKeys)>"
  }
  
  /// Returns the C identifier for a vtable struct.
  /// For non-generic traits: `__koral_vtable_Error`
  /// For generic traits: `__koral_vtable_Converter_std_String`
  func vtableStructCIdentifier(traitName: String, traitTypeArgs: [Type]) -> String {
    let sanitizedTraitName = sanitizeCIdentifier(traitName)
    if traitTypeArgs.isEmpty {
      return "__koral_vtable_\(sanitizedTraitName)"
    }
    let argSuffix = traitTypeArgs.map { sanitizeCIdentifier(cTypeName($0)) }.joined(separator: "_")
    return "__koral_vtable_\(sanitizedTraitName)_\(argSuffix)"
  }
}

// MARK: - Vtable Instance Generation

extension CodeGen {
  
  /// Returns the vtable instance variable name for a given (concreteType, trait) combination.
  ///
  /// Naming convention: `__koral_vtable_{TraitName}_for_{ConcreteType}`
  /// For generic traits: `__koral_vtable_{TraitName}_{TypeArgs}_for_{ConcreteType}`
  func vtableInstanceName(
    concreteTypeCName: String,
    traitName: String,
    traitTypeArgs: [Type] = []
  ) -> String {
    let sanitizedConcreteTypeCName = sanitizeCIdentifier(concreteTypeCName)
    let vtableStructName = vtableStructCIdentifier(traitName: traitName, traitTypeArgs: traitTypeArgs)
    return "\(vtableStructName)_for_\(sanitizedConcreteTypeCName)"
  }
  
  /// Generates a global `static const` vtable instance for a (concrete type, trait) combination.
  ///
  /// For each method in the trait (ordered by declaration, parent methods first):
  /// - If `self` by value: uses the wrapper function name
  /// - If `self ref`: uses the actual method C name directly (no wrapper needed)
  ///
  /// Returns `nil` if the trait is not found or if this combination has already been generated.
  func generateVtableInstance(
    concreteTypeCName: String,
    traitName: String,
    traitTypeArgs: [Type] = [],
    methods: [MIRTraitVTableMethod],
    actualMethodCNames: [String: String]
  ) -> String? {
    let instanceName = vtableInstanceName(
      concreteTypeCName: concreteTypeCName,
      traitName: traitName,
      traitTypeArgs: traitTypeArgs
    )
    
    // Deduplicate: skip if already generated
    if generatedVtableInstances.contains(instanceName) {
      return nil
    }
    generatedVtableInstances.insert(instanceName)
    
    let vtableStructName = vtableStructCIdentifier(traitName: traitName, traitTypeArgs: traitTypeArgs)
    
    var code = "static const struct \(vtableStructName) \(instanceName) = {\n"
    
    for method in methods {
      let methodName = method.name
      let sanitizedMethodName = sanitizeCIdentifier(methodName)
      
      let functionRef: String
      if method.selfByValue {
        // self by value: vtable entry points to the wrapper function
        functionRef = wrapperFunctionName(
          concreteTypeCName: concreteTypeCName,
          traitName: traitName,
          methodName: methodName
        )
      } else {
        // self ref: vtable entry points directly to the actual method
        guard let actualName = actualMethodCNames[methodName] else {
          continue
        }
        functionRef = actualName
      }
      
      code += "    .\(sanitizedMethodName) = \(functionRef),\n"
    }
    
    code += "};\n"
    return code
  }
}

// MARK: - Trait Object Conversion

extension CodeGen {

  func generateTraitObjectConversionABI(
    innerResult: String,
    innerType: Type,
    sourceOwnership: MIROwnershipUse,
    traitName: String,
    traitTypeArgs: [Type] = [],
    concreteType: Type
  ) -> String {
    let result = nextTempWithDecl(cType: "struct __koral_TraitRef")
    let concreteTypeCName = concreteTypeCIdentifier(concreteType) ?? cTypeName(concreteType)
    let vtableName = vtableInstanceName(
      concreteTypeCName: concreteTypeCName,
      traitName: traitName,
      traitTypeArgs: traitTypeArgs
    )

    switch innerType {
    case .reference, .mutableReference:
      break
    default:
      fatalError("Trait object conversion requires a reference type source, got \(innerType)")
    }

    addIndent()
    appendToBuffer("\(result).ptr = \(innerResult).ptr;\n")
    addIndent()
    appendToBuffer("\(result).control = \(innerResult).control;\n")
    addIndent()
    appendToBuffer("\(result).vtable = &\(vtableName);\n")
    if sourceOwnership == .copy {
      addIndent()
      appendToBuffer("__koral_retain(\(result).control);\n")
    }

    return result
  }
}

// MARK: - Trait Method Call

extension CodeGen {

  func generateTraitMethodCallABI(
    receiverResult: String,
    receiverOwnership: MIROwnershipUse,
    traitName: String,
    traitTypeArgs: [Type] = [],
    methodName: String,
    arguments: [CodeGenTraitCallArgument],
    type: Type
  ) -> String {
    let vtableStructName = vtableStructCIdentifier(traitName: traitName, traitTypeArgs: traitTypeArgs)
    let vtVar = nextTempWithInit(cType: "const struct \(vtableStructName)*", initExpr: "(const struct \(vtableStructName)*)\(receiverResult).vtable")

    // 5. Build argument list: construct struct Ref from TraitRef fields as first arg, then the rest.
    // Receiver follows the same copy/move rule as normal calls:
    // - lvalue receiver: retain copied self
    // - rvalue receiver: move ownership directly
    let sanitizedMethodName = sanitizeCIdentifier(methodName)
    let selfArg = nextTempWithInit(cType: "struct __koral_Ref", initExpr: "(struct __koral_Ref){\(receiverResult).ptr, \(receiverResult).control}")
    if receiverOwnership == .copy {
      addIndent()
      appendToBuffer("__koral_retain(\(selfArg).control);\n")
    }
    var allArgs = [selfArg]
    for argument in arguments {
      if argument.ownership == .copy {
        let copyResult = nextTempWithDecl(cType: cTypeName(argument.type))
        appendCopyAssignment(for: argument.type, source: argument.value, dest: copyResult, indent: indent)
        allArgs.append(copyResult)
      } else {
        allArgs.append(argument.value)
      }
    }
    let argsStr = allArgs.joined(separator: ", ")

    // 6. Generate the function pointer call
    if type == .void || type == .never {
      addIndent()
      appendToBuffer("\(vtVar)->\(sanitizedMethodName)(\(argsStr));\n")
      return ""
    } else {
      let result = nextTempWithInit(cType: cTypeName(type), initExpr: "\(vtVar)->\(sanitizedMethodName)(\(argsStr))")
      return result
    }
  }
}

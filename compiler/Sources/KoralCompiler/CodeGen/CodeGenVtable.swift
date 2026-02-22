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

extension CodeGen {
  
  /// Resolves the actual C function name for a concrete type's trait method implementation.
  ///
  /// Searches through the monomorphized global nodes for matching method declarations
  /// in `givenDeclaration` blocks, or falls back to the `staticMethodLookup` table.
  ///
  /// - Parameters:
  ///   - concreteType: The concrete type (e.g., `.structure(defId)`)
  ///   - methodName: The trait method name (e.g., "message")
  /// - Returns: The C identifier for the method implementation, or nil if not found
  private func resolveMethodCName(concreteType: Type, methodName: String) -> String? {
    // Strategy 1: Search through givenDeclaration nodes for a matching method
    for node in ast.globalNodes {
      guard case .givenDeclaration(let type, let methods) = node else { continue }
      guard type == concreteType else { continue }
      
      for method in methods {
        let mangledName = context.getName(method.identifier.defId) ?? ""
        // The mangled name is "QualifiedTypeName_methodName"
        // Check if it ends with "_methodName"
        if mangledName.hasSuffix("_\(methodName)") {
          return cIdentifier(for: method.identifier)
        }
      }
    }
    
    // Strategy 2: Use staticMethodLookup table
    let typeName: String?
    switch concreteType {
    case .structure(let defId):
      typeName = context.getName(defId)
    case .union(let defId):
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
  /// For each (concreteType, trait) combination in `ast.vtableRequests`:
  /// 1. Generates the vtable struct definition (once per trait)
  /// 2. For each self-by-value method, generates a wrapper function
  /// 3. Generates the vtable instance (static const global)
  ///
  /// This method should be called from `generateProgram()` after function declarations
  /// but before function implementations, so that wrapper functions and vtable instances
  /// are available when function bodies reference them.
  func processVtableRequests() {
    let requests = ast.vtableRequests
    guard !requests.isEmpty else { return }
    
    // Track which trait vtable struct definitions have been generated
    var generatedVtableStructs: Set<String> = []
    
    // Sort requests for deterministic output
    let sortedRequests = requests.sorted { a, b in
      if a.traitName != b.traitName { return a.traitName < b.traitName }
      return a.concreteType.stableKey < b.concreteType.stableKey
    }
    
    buffer += "// Vtable definitions\n"
    
    for request in sortedRequests {
      let traitName = request.traitName
      
      // Get the concrete type's C identifier
      guard let concreteTypeCName = concreteTypeCIdentifier(request.concreteType) else {
        continue
      }
      
      // Get ordered trait methods
      guard let orderedMethods = try? SemaUtils.orderedTraitMethods(
        traitName,
        traits: ast.traits,
        currentLine: nil
      ) else {
        continue
      }
      
      // Build trait type parameter substitution for generic traits
      var traitTypeParamSubstitution: [String: Type] = [:]
      if let traitInfo = ast.traits[traitName], !traitInfo.typeParameters.isEmpty {
        for (i, param) in traitInfo.typeParameters.enumerated() {
          if i < request.traitTypeArgs.count {
            traitTypeParamSubstitution[param.name] = request.traitTypeArgs[i]
          }
        }
      }
      
      // For generic traits, the vtable struct key includes type args
      let vtableStructKey = vtableStructKeyName(traitName: traitName, traitTypeArgs: request.traitTypeArgs)
      let vtableStructCName = vtableStructCIdentifier(traitName: traitName, traitTypeArgs: request.traitTypeArgs)
      
      // Step 1: Generate vtable struct definition (once per trait specialization)
      if !generatedVtableStructs.contains(vtableStructKey) {
        generatedVtableStructs.insert(vtableStructKey)
        if let structDef = generateVtableStructDefinition(
          traitName: traitName,
          traitTypeParamSubstitution: traitTypeParamSubstitution,
          vtableStructName: vtableStructCName
        ) {
          buffer += structDef
          buffer += "\n"
        }
      }
      
      // Step 2: Resolve actual method C names and generate wrappers
      var actualMethodCNames: [String: String] = [:]
      
      for (methodName, signature) in orderedMethods {
        // Resolve the actual method C name for this concrete type
        guard let actualCName = resolveMethodCName(
          concreteType: request.concreteType,
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
          signature: signature,
          actualMethodCName: actualCName,
          traitTypeParamSubstitution: traitTypeParamSubstitution
        ) {
          buffer += wrapperCode
          buffer += "\n"
        }
      }
      
      // Step 3: Generate vtable instance
      if let instanceCode = generateVtableInstance(
        concreteTypeCName: concreteTypeCName,
        traitName: traitName,
        traitTypeArgs: request.traitTypeArgs,
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
  
  /// Resolves a TypeNode from a trait method signature to a semantic Type for vtable generation.
  /// This handles the common cases that appear in object-safe trait methods.
  /// For generic traits, traitTypeParamSubstitution maps type parameter names to concrete types.
  func resolveTypeNodeForVtable(_ node: TypeNode, traitTypeParamSubstitution: [String: Type] = [:]) -> Type? {
    switch node {
    case .identifier(let name):
      // Check trait type parameter substitution first (for generic traits)
      if let substituted = traitTypeParamSubstitution[name] {
        return substituted
      }
      // Try builtin types first
      if let builtinType = SemaUtils.resolveBuiltinType(name) {
        return builtinType
      }
      // Try looking up as a struct or union type in the context (unqualified)
      if let defId = context.lookupDefId(modulePath: [], name: name, sourceFile: nil) {
        if let kind = context.getKind(defId) {
          switch kind {
          case .type(.structure):
            // Verify this defId has a valid C identifier mapping
            if cIdentifierByDefId[defIdKey(defId)] != nil {
              return .structure(defId: defId)
            }
          case .type(.union):
            if cIdentifierByDefId[defIdKey(defId)] != nil {
              return .union(defId: defId)
            }
          default:
            break
          }
        }
      }
      // Fallback: search through cIdentifierByDefId for a matching type
      // This handles cases where the type is in a different module (e.g., std.String)
      for (defIdKey, _) in cIdentifierByDefId {
        let defId = DefId(id: defIdKey)
        guard let kind = context.getKind(defId) else { continue }
        let defName = context.getName(defId) ?? ""
        // Match by simple name (last component)
        let simpleName = defName.components(separatedBy: ".").last ?? defName
        guard simpleName == name else { continue }
        switch kind {
        case .type(.structure):
          return .structure(defId: defId)
        case .type(.union):
          return .union(defId: defId)
        default:
          break
        }
      }
      return nil
      
    case .reference(let inner):
      if let resolved = resolveTypeNodeForVtable(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) {
        return .reference(inner: resolved)
      }
      return nil
      
    case .weakReference(let inner):
      if let resolved = resolveTypeNodeForVtable(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) {
        return .weakReference(inner: resolved)
      }
      return nil
      
    case .pointer(let inner):
      if let resolved = resolveTypeNodeForVtable(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) {
        return .pointer(element: resolved)
      }
      return nil
      
    case .generic(let base, let args):
      // Resolve generic type arguments
      let resolvedArgs = args.compactMap { resolveTypeNodeForVtable($0, traitTypeParamSubstitution: traitTypeParamSubstitution) }
      guard resolvedArgs.count == args.count else { return nil }
      // Look up the base type as a generic struct/union
      if let defId = context.lookupDefId(modulePath: [], name: base, sourceFile: nil) {
        if let kind = context.getKind(defId) {
          switch kind {
          case .type(.structure), .genericTemplate(.structure):
            return .genericStruct(template: base, args: resolvedArgs)
          case .type(.union), .genericTemplate(.union):
            return .genericUnion(template: base, args: resolvedArgs)
          default:
            break
          }
        }
      }
      return nil
      
    case .functionType(let paramTypes, let returnType):
      let resolvedParams = paramTypes.compactMap { resolveTypeNodeForVtable($0, traitTypeParamSubstitution: traitTypeParamSubstitution) }
      guard resolvedParams.count == paramTypes.count else { return nil }
      guard let resolvedReturn = resolveTypeNodeForVtable(returnType, traitTypeParamSubstitution: traitTypeParamSubstitution) else { return nil }
      let params = resolvedParams.map { Parameter(type: $0, kind: .byVal) }
      return .function(parameters: params, returns: resolvedReturn)
      
    case .inferredSelf:
      // Self should not appear in non-receiver positions for object-safe traits
      return nil
      
    case .moduleQualified(let module, let name):
      if let defId = context.lookupDefId(modulePath: [module], name: name, sourceFile: nil) {
        if let kind = context.getKind(defId) {
          switch kind {
          case .type(.structure):
            return .structure(defId: defId)
          case .type(.union):
            return .union(defId: defId)
          default:
            break
          }
        }
      }
      return nil
      
    case .moduleQualifiedGeneric(let module, let base, let args):
      let resolvedArgs = args.compactMap { resolveTypeNodeForVtable($0, traitTypeParamSubstitution: traitTypeParamSubstitution) }
      guard resolvedArgs.count == args.count else { return nil }
      if let defId = context.lookupDefId(modulePath: [module], name: base, sourceFile: nil) {
        if let kind = context.getKind(defId) {
          switch kind {
          case .type(.structure), .genericTemplate(.structure):
            return .genericStruct(template: base, args: resolvedArgs)
          case .type(.union), .genericTemplate(.union):
            return .genericUnion(template: base, args: resolvedArgs)
          default:
            break
          }
        }
      }
      return nil
    }
  }
  
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
  ///   - traitName: The name of the trait to generate a vtable struct for
  ///   - traitTypeParamSubstitution: Substitution map for generic trait type parameters
  ///   - vtableStructName: The C name for the vtable struct (allows customization for generic traits)
  /// - Returns: The generated C code for the vtable struct definition, or nil if the trait is not found
  func generateVtableStructDefinition(traitName: String, traitTypeParamSubstitution: [String: Type] = [:], vtableStructName: String? = nil) -> String? {
    let traits = ast.traits
    
    // Get ordered methods (parent methods first, then own methods)
    guard let orderedMethods = try? SemaUtils.orderedTraitMethods(
      traitName,
      traits: traits,
      currentLine: nil
    ) else {
      return nil
    }
    
    // Build the vtable struct
    let structName = vtableStructName ?? "__koral_vtable_\(sanitizeCIdentifier(traitName))"
    var code = "struct \(structName) {\n"
    
    for (methodName, signature) in orderedMethods {
      // Resolve return type to C type name
      let returnCType: String
      if let resolvedReturn = resolveTypeNodeForVtable(signature.returnType, traitTypeParamSubstitution: traitTypeParamSubstitution) {
        returnCType = cTypeName(resolvedReturn)
      } else {
        returnCType = "void"
      }
      
      // Build parameter list: first param is always struct Ref (the receiver)
      var paramTypes = ["struct __koral_Ref"]
      
      // Add non-self parameters
      for (i, param) in signature.parameters.enumerated() {
        // Skip the self parameter (first parameter named "self")
        if i == 0 && param.name == "self" { continue }
        
        if let resolvedType = resolveTypeNodeForVtable(param.type, traitTypeParamSubstitution: traitTypeParamSubstitution) {
          paramTypes.append(cTypeName(resolvedType))
        }
      }
      
      let paramsStr = paramTypes.joined(separator: ", ")
      let sanitizedMethodName = sanitizeCIdentifier(methodName)
      code += "    \(returnCType) (*\(sanitizedMethodName))(\(paramsStr));\n"
    }
    
    code += "};\n"
    return code
  }
}

// MARK: - Wrapper Function Generation

extension CodeGen {
  
  /// Checks whether a trait method is `self` by value (needs a wrapper) or `self ref` (no wrapper needed).
  ///
  /// - Parameter signature: The trait method signature
  /// - Returns: `true` if the method takes `self` by value, `false` if `self ref`
  func isSelfByValue(_ signature: TraitMethodSignature) -> Bool {
    guard let firstParam = signature.parameters.first,
          firstParam.name == "self" else {
      return false
    }
    // If the self parameter's type is a reference, it's `self ref`
    if case .reference = firstParam.type {
      return false
    }
    return true
  }
  
  /// Returns the C identifier for a concrete type, used in function names like `std_String`.
  ///
  /// For `.structure(defId)` → looks up the C identifier from the defId map
  /// For `.union(defId)` → same lookup
  /// For primitive types → returns the C type name directly
  func concreteTypeCIdentifier(_ type: Type) -> String? {
    switch type {
    case .structure(let defId):
      return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
    case .union(let defId):
      return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
    default:
      return nil
    }
  }
  
  /// Determines whether a concrete type has a compiler-generated copy function (`__koral_{name}_copy`).
  ///
  /// Structs and unions always have copy functions. Primitive types do not.
  func hasCopyFunction(_ type: Type) -> Bool {
    switch type {
    case .structure, .union:
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
    signature: TraitMethodSignature,
    actualMethodCName: String,
    traitTypeParamSubstitution: [String: Type] = [:]
  ) -> String? {
    // self ref methods don't need a wrapper
    guard isSelfByValue(signature) else {
      return nil
    }
    
    let sanitizedTraitName = sanitizeCIdentifier(traitName)
    let sanitizedMethodName = sanitizeCIdentifier(methodName)
    let sanitizedConcreteTypeCName = sanitizeCIdentifier(concreteTypeCName)
    let wrapperName = "__koral_wrapper_\(sanitizedConcreteTypeCName)_\(sanitizedTraitName)_\(sanitizedMethodName)"
    
    // Resolve return type
    let returnCType: String
    if let resolvedReturn = resolveTypeNodeForVtable(signature.returnType, traitTypeParamSubstitution: traitTypeParamSubstitution) {
      returnCType = cTypeName(resolvedReturn)
    } else {
      returnCType = "void"
    }
    
    // Build parameter list: first is always `struct Ref self_ref`
    var paramDecls = ["struct __koral_Ref self_ref"]
    var paramNames: [String] = []
    
    // Add non-self parameters
    for (i, param) in signature.parameters.enumerated() {
      if i == 0 && param.name == "self" { continue }
      let paramCName = sanitizeCIdentifier(param.name)
      if let resolvedType = resolveTypeNodeForVtable(param.type, traitTypeParamSubstitution: traitTypeParamSubstitution) {
        paramDecls.append("\(cTypeName(resolvedType)) \(paramCName)")
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
    
    let traits = ast.traits
    
    // Get ordered methods (parent methods first, then own methods)
    guard let orderedMethods = try? SemaUtils.orderedTraitMethods(
      traitName,
      traits: traits,
      currentLine: nil
    ) else {
      return nil
    }
    
    let vtableStructName = vtableStructCIdentifier(traitName: traitName, traitTypeArgs: traitTypeArgs)
    
    var code = "static const struct \(vtableStructName) \(instanceName) = {\n"
    
    for (methodName, signature) in orderedMethods {
      let sanitizedMethodName = sanitizeCIdentifier(methodName)
      
      let functionRef: String
      if isSelfByValue(signature) {
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

  /// Generates C code for converting a concrete type reference into a trait object reference (TraitRef).
  ///
  /// Trait object conversion: from T ref → TraitName ref (zero allocation).
  /// Copies the Ref into TraitRef and sets the vtable pointer.
  /// Only reference types can be converted to trait objects.
  func generateTraitObjectConversion(
    inner: TypedExpressionNode,
    traitName: String,
    traitTypeArgs: [Type] = [],
    concreteType: Type,
    type: Type
  ) -> String {
    let innerResult = generateExpressionSSA(inner)
    let result = nextTempWithDecl(cType: "struct __koral_TraitRef")

    // Get the C identifier for the concrete type (needed for vtable instance name)
    let concreteTypeCName = concreteTypeCIdentifier(concreteType) ?? cTypeName(concreteType)

    // Get the vtable instance name
    let vtableName = vtableInstanceName(
      concreteTypeCName: concreteTypeCName,
      traitName: traitName,
      traitTypeArgs: traitTypeArgs
    )

    guard case .reference = inner.type else {
      fatalError("Trait object conversion requires a reference type source, got \(inner.type)")
    }

    // From T ref → trait object ref (zero allocation)
    // Copy fields from Ref, set vtable.
    // Retain only for lvalue source (copy semantics); rvalue transfers ownership.
    addIndent()
    appendToBuffer("\(result).ptr = \(innerResult).ptr;\n")
    addIndent()
    appendToBuffer("\(result).control = \(innerResult).control;\n")
    addIndent()
    appendToBuffer("\(result).vtable = &\(vtableName);\n")
    if inner.valueCategory == .lvalue {
      addIndent()
      appendToBuffer("__koral_retain(\(result).control);\n")
    }

    return result
  }
}

// MARK: - Trait Method Call

extension CodeGen {

  /// Generates C code for a dynamic dispatch call through a trait object's vtable.
  ///
  /// The generated code:
  /// 1. Evaluates the receiver expression (a `struct TraitRef`)
  /// 2. Evaluates all argument expressions
  /// 3. Casts the vtable pointer to the correct vtable struct type
  /// 4. Calls the method through the function pointer, passing `receiver.ref` as the first argument
  func generateTraitMethodCall(
    receiver: TypedExpressionNode,
    traitName: String,
    methodName: String,
    methodIndex: Int,
    arguments: [TypedExpressionNode],
    type: Type
  ) -> String {
    // 1. Evaluate receiver (produces a struct TraitRef)
    let receiverResult = generateExpressionSSA(receiver)

    // 2. Evaluate all arguments, copying lvalues as needed
    var argResults: [String] = []
    for arg in arguments {
      let result = generateExpressionSSA(arg)
      if arg.valueCategory == .lvalue {
        let copyResult = nextTempWithDecl(cType: cTypeName(arg.type))
        appendCopyAssignment(for: arg.type, source: result, dest: copyResult, indent: indent)
        argResults.append(copyResult)
      } else {
        argResults.append(result)
      }
    }

    // 3. Extract trait type args from receiver type for generic traits
    var traitTypeArgs: [Type] = []
    if case .reference(let inner) = receiver.type,
       case .traitObject(_, let typeArgs) = inner {
      traitTypeArgs = typeArgs
    }
    
    // 4. Cast vtable pointer to the correct vtable struct type
    let vtableStructName = vtableStructCIdentifier(traitName: traitName, traitTypeArgs: traitTypeArgs)
    let vtVar = nextTempWithInit(cType: "const struct \(vtableStructName)*", initExpr: "(const struct \(vtableStructName)*)\(receiverResult).vtable")

    // 5. Build argument list: construct struct Ref from TraitRef fields as first arg, then the rest.
    // Receiver follows the same copy/move rule as normal calls:
    // - lvalue receiver: retain copied self
    // - rvalue receiver: move ownership directly
    let sanitizedMethodName = sanitizeCIdentifier(methodName)
    let selfArg = nextTempWithInit(cType: "struct __koral_Ref", initExpr: "(struct __koral_Ref){\(receiverResult).ptr, \(receiverResult).control}")
    if receiver.valueCategory == .lvalue {
      addIndent()
      appendToBuffer("__koral_retain(\(selfArg).control);\n")
    }
    var allArgs = [selfArg]
    allArgs.append(contentsOf: argResults)
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

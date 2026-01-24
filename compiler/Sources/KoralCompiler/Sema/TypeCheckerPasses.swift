import Foundation

// MARK: - Multi-pass Type Checking Extension
// This extension contains Pass 1/2/3 logic and module symbol building.

extension TypeChecker {

  /// Performs type checking on the AST and returns the TypeCheckerOutput.
  /// The output contains:
  /// - The typed program with all declarations type-checked
  /// - The collected instantiation requests for deferred monomorphization
  /// - The registry of generic templates for the Monomorphizer
  public func check() throws -> TypeCheckerOutput {
    switch self.ast {
    case .program(let allNodes):
      // 从 GlobalNode 中过滤出非 using 声明的节点
      let declarations = allNodes.filter { node in
        if case .usingDeclaration = node { return false }
        return true
      }
      
      var typedDeclarations: [TypedGlobalNode] = []
      // Clear any previous state
      instantiationRequests.removeAll()

      // === PASS 1: Collect all type definitions ===
      // This pass registers all types, traits, and function signatures
      // so that forward references work correctly
      for (index, decl) in declarations.enumerated() {
        let isStdLib = index < coreGlobalCount
        self.isCurrentDeclStdLib = isStdLib
        // 更新当前源文件和模块路径
        // nodeSourceInfoMap is always populated by Driver using ModuleResolver
        let sourceInfo = nodeSourceInfoMap[index]
        self.currentFileName = sourceInfo?.sourceFile ?? (isStdLib ? coreFileName : userFileName)
        self.currentSourceFile = sourceInfo?.sourceFile ?? self.currentFileName
        self.currentModulePath = sourceInfo?.modulePath ?? []
        self.currentSpan = decl.span
        do {
          try collectTypeDefinition(decl, isStdLib: isStdLib)
        } catch let e as SemanticError {
          throw e
        }
      }
      
      // === PASS 2: Register all given method signatures ===
      // This allows methods in one given block to call methods in another given block
      // regardless of declaration order
      for (index, decl) in declarations.enumerated() {
        let isStdLib = index < coreGlobalCount
        self.isCurrentDeclStdLib = isStdLib
        // 更新当前源文件和模块路径
        let sourceInfo = nodeSourceInfoMap[index]
        self.currentFileName = sourceInfo?.sourceFile ?? (isStdLib ? coreFileName : userFileName)
        self.currentSourceFile = sourceInfo?.sourceFile ?? self.currentFileName
        self.currentModulePath = sourceInfo?.modulePath ?? []
        self.currentSpan = decl.span
        do {
          try collectGivenSignatures(decl)
        } catch let e as SemanticError {
          throw e
        }
      }
      
      // === PASS 2.5: Build module symbols from collected definitions ===
      // This allows `using self.child` to work by creating module symbols
      // that can be accessed via `child.xxx`
      // Must be after Pass 2 because function symbols are registered in Pass 2
      try buildModuleSymbols(from: declarations)
      
      // === PASS 3: Check function bodies and generate typed AST ===
      // Now that all types and method signatures are defined, we can check function bodies
      // which may reference types or methods defined later in the file
      for (index, decl) in declarations.enumerated() {
        let isStdLib = index < coreGlobalCount
        self.isCurrentDeclStdLib = isStdLib
        // 更新当前源文件和模块路径
        let sourceInfo = nodeSourceInfoMap[index]
        self.currentFileName = sourceInfo?.sourceFile ?? (isStdLib ? coreFileName : userFileName)
        self.currentSourceFile = sourceInfo?.sourceFile ?? self.currentFileName
        self.currentModulePath = sourceInfo?.modulePath ?? []
        self.currentSpan = decl.span
        do {
          if let typedDecl = try checkGlobalDeclaration(decl) {
            typedDeclarations.append(typedDecl)
          }
        } catch let e as SemanticError {
          throw e
        }
      }
      
      // Build the typed program
      let program = TypedProgram.program(globalNodes: typedDeclarations)
      
      // Build the generic template registry
      // Separate concrete types into structs and unions
      let allConcreteTypes = currentScope.getAllConcreteTypes()
      var concreteStructs: [String: Type] = [:]
      var concreteUnions: [String: Type] = [:]
      for (name, type) in allConcreteTypes {
        switch type {
        case .structure:
          concreteStructs[name] = type
        case .union:
          concreteUnions[name] = type
        default:
          break
        }
      }
      
      let registry = GenericTemplateRegistry(
        structTemplates: currentScope.getAllGenericStructTemplates(),
        unionTemplates: currentScope.getAllGenericUnionTemplates(),
        functionTemplates: currentScope.getAllGenericFunctionTemplates(),
        extensionMethods: genericExtensionMethods,
        intrinsicExtensionMethods: genericIntrinsicExtensionMethods,
        traits: traits,
        concreteExtensionMethods: extensionMethods,
        intrinsicGenericTypes: intrinsicGenericTypes,
        intrinsicGenericFunctions: intrinsicGenericFunctions,
        concreteStructTypes: concreteStructs,
        concreteUnionTypes: concreteUnions
      )
      
      return TypeCheckerOutput(
        program: program,
        instantiationRequests: instantiationRequests,
        genericTemplates: registry
      )
    }
  }
  
  // MARK: - Pass 1.5: Module Symbol Building
  
  /// Builds module symbols from collected definitions.
  /// This allows `using self.child` to work by creating module symbols
  /// that can be accessed via `child.xxx`.
  private func buildModuleSymbols(from declarations: [GlobalNode]) throws {
    // Step 1: Collect all symbols by module path
    var symbolsByModule: [String: [(name: String, symbol: Symbol, type: Type?)]] = [:]
    
    for (index, decl) in declarations.enumerated() {
      guard let sourceInfo = nodeSourceInfoMap[index] else { continue }
      let modulePath = sourceInfo.modulePath
      
      // Skip root module (empty path) - we only care about submodules
      if modulePath.isEmpty { continue }
      
      let moduleKey = modulePath.joined(separator: ".")
      
      // Extract symbol info from declaration
      if let symbolInfo = extractSymbolInfo(from: decl, sourceInfo: sourceInfo) {
        if symbolsByModule[moduleKey] == nil {
          symbolsByModule[moduleKey] = []
        }
        symbolsByModule[moduleKey]?.append(symbolInfo)
      }
    }
    
    // Step 2: Build ModuleSymbolInfo for each module
    for (moduleKey, symbols) in symbolsByModule {
      var publicSymbols: [String: Symbol] = [:]
      var publicTypes: [String: Type] = [:]
      
      for (name, symbol, type) in symbols {
        // Only include public symbols (for now, include all non-private)
        if symbol.access != .private {
          publicSymbols[name] = symbol
          if let t = type {
            publicTypes[name] = t
          }
        }
      }
      
      let modulePath = moduleKey.split(separator: ".").map(String.init)
      moduleSymbols[moduleKey] = ModuleSymbolInfo(
        modulePath: modulePath,
        publicSymbols: publicSymbols,
        publicTypes: publicTypes
      )
    }
    
    // Step 3: Register module symbols in scope for direct child modules
    // For each unique first-level submodule, create a module symbol
    var registeredModules: Set<String> = []
    for moduleKey in moduleSymbols.keys {
      let parts = moduleKey.split(separator: ".").map(String.init)
      if let firstPart = parts.first, !registeredModules.contains(firstPart) {
        registeredModules.insert(firstPart)
        
        // Get or create module info for this submodule
        if let moduleInfo = moduleSymbols[firstPart] {
          let moduleType = Type.module(info: moduleInfo)
          // Register the module symbol in scope (as private by default)
          currentScope.define(firstPart, moduleType, mutable: false)
        }
      }
    }
  }
  
  /// Extracts symbol information from a global declaration.
  private func extractSymbolInfo(from decl: GlobalNode, sourceInfo: GlobalNodeSourceInfo) -> (name: String, symbol: Symbol, type: Type?)? {
    switch decl {
    case .globalFunctionDeclaration(let name, let typeParameters, let parameters, let returnType, _, let access, _):
      // Skip generic functions for now
      if !typeParameters.isEmpty { return nil }
      
      // Build function type
      let paramTypes = parameters.map { param -> Parameter in
        // We can't fully resolve types here, but we can create a placeholder
        return Parameter(type: .void, kind: .byVal)
      }
      _ = paramTypes
      _ = returnType
      
      // Look up the actual symbol from scope
      if let funcType = currentScope.lookup(name, sourceFile: sourceInfo.sourceFile) {
        let symbol = Symbol(
          name: name,
          type: funcType,
          kind: .function,
          modulePath: sourceInfo.modulePath,
          sourceFile: sourceInfo.sourceFile,
          access: access
        )
        return (name, symbol, nil)
      }
      return nil
      
    case .globalStructDeclaration(let name, let typeParameters, _, let access, _):
      // Skip generic structs for now
      if !typeParameters.isEmpty { return nil }
      
      if let structType = currentScope.lookupType(name, sourceFile: sourceInfo.sourceFile) {
        let symbol = Symbol(
          name: name,
          type: structType,
          kind: .type,
          modulePath: sourceInfo.modulePath,
          sourceFile: sourceInfo.sourceFile,
          access: access
        )
        return (name, symbol, structType)
      }
      return nil
      
    case .globalUnionDeclaration(let name, let typeParameters, _, let access, _):
      // Skip generic unions for now
      if !typeParameters.isEmpty { return nil }
      
      if let unionType = currentScope.lookupType(name, sourceFile: sourceInfo.sourceFile) {
        let symbol = Symbol(
          name: name,
          type: unionType,
          kind: .type,
          modulePath: sourceInfo.modulePath,
          sourceFile: sourceInfo.sourceFile,
          access: access
        )
        return (name, symbol, unionType)
      }
      return nil
      
    case .globalVariableDeclaration(let name, _, _, _, let access, _):
      if let varType = currentScope.lookup(name, sourceFile: sourceInfo.sourceFile) {
        let symbol = Symbol(
          name: name,
          type: varType,
          kind: .variable(.Value),
          modulePath: sourceInfo.modulePath,
          sourceFile: sourceInfo.sourceFile,
          access: access
        )
        return (name, symbol, nil)
      }
      return nil
      
    default:
      return nil
    }
  }
  
  // MARK: - Generic Method Type Parameter Conflict Detection
  
  /// Checks for conflicts between method-level type parameters and outer type parameters.
  /// - Parameters:
  ///   - methods: The trait method signatures to check
  ///   - outerTypeParams: The outer (trait-level or given-level) type parameters
  ///   - contextName: A description of the context for error messages (e.g., "trait 'Functor'")
  private func checkMethodTypeParameterConflicts(
    methods: [TraitMethodSignature],
    outerTypeParams: [TypeParameterDecl],
    contextName: String
  ) throws {
    let outerNames = Set(outerTypeParams.map { $0.name })
    for method in methods {
      for param in method.typeParameters {
        if outerNames.contains(param.name) {
          throw SemanticError(.generic(
            "Method '\(method.name)' type parameter '\(param.name)' conflicts with \(contextName) type parameter"
          ), line: currentLine)
        }
      }
    }
  }
  
  /// Checks for conflicts between method-level type parameters and outer type parameters for MethodDeclaration.
  /// - Parameters:
  ///   - methods: The method declarations to check
  ///   - outerTypeParams: The outer (given-level) type parameters
  ///   - contextName: A description of the context for error messages
  private func checkMethodTypeParameterConflicts(
    methods: [MethodDeclaration],
    outerTypeParams: [TypeParameterDecl],
    contextName: String
  ) throws {
    let outerNames = Set(outerTypeParams.map { $0.name })
    for method in methods {
      for param in method.typeParameters {
        if outerNames.contains(param.name) {
          throw SemanticError(.generic(
            "Method '\(method.name)' type parameter '\(param.name)' conflicts with \(contextName) type parameter"
          ), line: currentLine)
        }
      }
    }
  }
  
  // MARK: - Pass 1: Type Collection
  
  /// Collects type definitions without checking function bodies.
  /// This allows forward references to work correctly.
  /// - Parameter isStdLib: Whether this declaration is from the standard library
  private func collectTypeDefinition(_ decl: GlobalNode, isStdLib: Bool = false) throws {
    switch decl {
    case .usingDeclaration:
      // Using declarations are handled separately, skip here
      return
      
    case .traitDeclaration(let name, let typeParameters, let superTraits, let methods, let access, let span):
      self.currentSpan = span
      if traits[name] != nil {
        throw SemanticError.duplicateDefinition(name, line: span.line)
      }
      
      // Check for method-level type parameter conflicts with trait-level type parameters
      try checkMethodTypeParameterConflicts(
        methods: methods,
        outerTypeParams: typeParameters,
        contextName: "trait '\(name)'"
      )
      
      // Note: We don't validate superTraits here because they might be forward references
      // They will be validated in pass 2
      traits[name] = TraitDeclInfo(
        name: name,
        typeParameters: typeParameters,
        superTraits: superTraits,
        methods: methods,
        access: access,
        line: span.line
      )
      // Track std library traits
      if isStdLib {
        stdLibTypes.insert(name)
      }
      
    case .globalUnionDeclaration(let name, let typeParameters, let cases, let access, let span):
      self.currentSpan = span
      // For private types, allow same name in different files
      let isPrivate = (access == .private)
      if !isPrivate && currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: span.line)
      }
      
      if !typeParameters.isEmpty {
        // Register generic union template
        let template = GenericUnionTemplate(
          name: name, typeParameters: typeParameters, cases: cases, access: access)
        currentScope.defineGenericUnionTemplate(name, template: template)
      } else {
        // Register placeholder for non-generic union (allows recursive references)
        let decl = UnionDecl(
          name: name,
          modulePath: currentModulePath,
          sourceFile: currentSourceFile,
          access: access,
          cases: [],
          isGenericInstantiation: false
        )
        let placeholder = Type.union(decl: decl)
        if isPrivate {
          // For private types, use file-qualified storage
          try currentScope.definePrivateType(name, sourceFile: currentSourceFile, type: placeholder)
        } else {
          try currentScope.defineType(name, type: placeholder)
        }
      }
      // Track std library types
      if isStdLib {
        stdLibTypes.insert(name)
      }
      
    case .globalStructDeclaration(let name, let typeParameters, let parameters, let access, let span):
      self.currentSpan = span
      // For private types, allow same name in different files
      let isPrivate = (access == .private)
      if !isPrivate && currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: span.line)
      }
      
      if !typeParameters.isEmpty {
        // Register generic struct template
        let template = GenericStructTemplate(
          name: name, typeParameters: typeParameters, parameters: parameters)
        currentScope.defineGenericStructTemplate(name, template: template)
      } else {
        // Register placeholder for non-generic struct (allows recursive references)
        let decl = StructDecl(
          name: name,
          modulePath: currentModulePath,
          sourceFile: currentSourceFile,
          access: access,
          members: [],
          isGenericInstantiation: false
        )
        let placeholder = Type.structure(decl: decl)
        if isPrivate {
          // For private types, use file-qualified storage
          try currentScope.definePrivateType(name, sourceFile: currentSourceFile, type: placeholder)
        } else {
          try currentScope.defineType(name, type: placeholder)
        }
      }
      // Track std library types
      if isStdLib {
        stdLibTypes.insert(name)
      }
      
    case .globalFunctionDeclaration(_, let typeParameters, _, _, _, _, let span):
      self.currentSpan = span
      // For generic functions, we just note that they exist
      // The full template will be registered in pass 2
      if !typeParameters.isEmpty {
        // Mark as generic function (will be fully registered in pass 2)
        // We don't need to do anything here since pass 2 handles it
      }
      // For non-generic functions, we also defer to pass 2
      // since we need to resolve parameter types which may reference forward types
      
    case .globalVariableDeclaration:
      // Variables are handled in pass 2
      break
      
    case .givenDeclaration(let typeParams, let typeNode, _, let span):
      self.currentSpan = span
      // For generic given, we just note the base type exists
      // The methods will be registered in pass 2
      if !typeParams.isEmpty {
        // Generic given - base type should already be registered
        if case .generic(let baseName, _) = typeNode {
          // Verify the base type exists (struct or union template)
          if currentScope.lookupGenericStructTemplate(baseName) == nil &&
             currentScope.lookupGenericUnionTemplate(baseName) == nil {
            // It might be an intrinsic type like Pointer, which is OK
          }
        }
      }
      // Non-generic given is handled in pass 2
      
    case .intrinsicTypeDeclaration(let name, let typeParameters, _, let span):
      self.currentSpan = span
      
      // Module rule check: intrinsic declarations are only allowed in standard library
      if !isStdLib {
        throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), line: span.line)
      }
      
      if currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: span.line)
      }
      
      if !typeParameters.isEmpty {
        // Register as intrinsic generic type
        intrinsicGenericTypes.insert(name)
        let template = GenericStructTemplate(
          name: name, typeParameters: typeParameters, parameters: [])
        currentScope.defineGenericStructTemplate(name, template: template)
      } else {
        // Non-generic intrinsic type - register the actual type
        let type: Type
        switch name {
        case "Int": type = .int
        case "Int8": type = .int8
        case "Int16": type = .int16
        case "Int32": type = .int32
        case "Int64": type = .int64
        case "UInt": type = .uint
        case "UInt8": type = .uint8
        case "UInt16": type = .uint16
        case "UInt32": type = .uint32
        case "UInt64": type = .uint64
        case "Float32": type = .float32
        case "Float64": type = .float64
        case "Bool": type = .bool
        case "Void": type = .void
        case "Never": type = .never
        default:
          let decl = StructDecl(
            name: name,
            modulePath: currentModulePath,
            sourceFile: currentSourceFile,
            access: .default,
            members: [],
            isGenericInstantiation: false
          )
          type = .structure(decl: decl)
        }
        try currentScope.defineType(name, type: type)
      }
      // Intrinsic types are always from std library
      if isStdLib {
        stdLibTypes.insert(name)
      }
      
    case .intrinsicFunctionDeclaration(let name, let typeParameters, _, _, _, let span):
      self.currentSpan = span
      
      // Module rule check: intrinsic declarations are only allowed in standard library
      if !isStdLib {
        throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), line: span.line)
      }
      
      if !typeParameters.isEmpty {
        intrinsicGenericFunctions.insert(name)
      }
      // Function signature will be registered in pass 3
      
    case .intrinsicGivenDeclaration(_, _, _, let span):
      // Module rule check: intrinsic declarations are only allowed in standard library
      if !isStdLib {
        self.currentSpan = span
        throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), line: span.line)
      }
      // Handled in pass 2 (signature) and pass 3 (body)
      break
    }
  }
  
  // MARK: - Pass 2: Given Signature Collection
  
  /// Collects given method signatures without checking bodies.
  /// This allows methods in one given block to call methods in another given block.
  /// Also resolves struct and union types so function signatures can reference them.
  private func collectGivenSignatures(_ decl: GlobalNode) throws {
    switch decl {
    case .givenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span
      if !typeParams.isEmpty {
        // Generic Given - register method signatures
        guard case .generic(let baseName, let args) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }

        // Validate that args are exactly the type params
        if args.count != typeParams.count {
          throw SemanticError.typeMismatch(
            expected: "\(typeParams.count) generic params", got: "\(args.count)")
        }
        for (i, arg) in args.enumerated() {
          guard case .identifier(let argName) = arg, argName == typeParams[i].name else {
            throw SemanticError.invalidOperation(
              op: "generic given specialization not supported", type1: String(describing: arg),
              type2: "")
          }
        }
        
        // Check for method-level type parameter conflicts with given-level type parameters
        try checkMethodTypeParameterConflicts(
          methods: methods,
          outerTypeParams: typeParams,
          contextName: "given '\(baseName)'"
        )

        // Initialize extension methods dictionary for this base type
        if genericExtensionMethods[baseName] == nil {
          genericExtensionMethods[baseName] = []
        }
        
        // Create a generic Self type for declaration-time checking
        let genericSelfArgs = typeParams.map { Type.genericParameter(name: $0.name) }
        let genericSelfType: Type
        if baseName == "Pointer" && genericSelfArgs.count == 1 {
          genericSelfType = .pointer(element: genericSelfArgs[0])
        } else if currentScope.lookupGenericStructTemplate(baseName) != nil {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        } else if currentScope.lookupGenericUnionTemplate(baseName) != nil {
          genericSelfType = .genericUnion(template: baseName, args: genericSelfArgs)
        } else {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        }
        
        // Register all method signatures (without checking bodies)
        for method in methods {
          let (checkedParams, checkedReturnType) = try withNewScope {
            for typeParam in typeParams {
              try currentScope.defineType(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(typeParams)
            
            // Register method-level type parameters
            for typeParam in method.typeParameters {
              try currentScope.defineType(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(method.typeParameters)
            
            try currentScope.defineType("Self", type: genericSelfType)
            currentScope.define("self", genericSelfType, mutable: false)
            
            let returnType = try resolveTypeNode(method.returnType)
            let params = try method.parameters.map { param -> Symbol in
              let paramType = try resolveTypeNode(param.type)
              return Symbol(
                name: param.name, type: paramType,
                kind: .variable(param.mutable ? .MutableValue : .Value))
            }
            
            // Validate __drop signature
            if method.name == "__drop" {
              if params.count != 1 || params[0].name != "self" {
                throw SemanticError.invalidOperation(
                  op: "__drop must have exactly one parameter 'self'", type1: "", type2: "")
              }
              if case .reference(_) = params[0].type {
                // OK
              } else {
                throw SemanticError.invalidOperation(
                  op: "__drop 'self' parameter must be a reference",
                  type1: params[0].type.description, type2: "")
              }
              if returnType != .void {
                throw SemanticError.invalidOperation(
                  op: "__drop must return Void", type1: returnType.description, type2: "")
              }
            }
            
            return (params, returnType)
          }
          
          // Register the method template (without checked body)
          genericExtensionMethods[baseName]!.append(GenericExtensionMethodTemplate(
            typeParams: typeParams,
            method: method,
            checkedBody: nil,
            checkedParameters: checkedParams,
            checkedReturnType: checkedReturnType
          ))
        }
      } else {
        // Non-generic given - collect method signatures for forward reference support
        let type = try resolveTypeNode(typeNode)
        let typeName: String
        if case .structure(let decl) = type {
          typeName = decl.name
        } else if case .union(let decl) = type {
          typeName = decl.name
        } else if case .int = type {
          typeName = type.description
        } else if case .int8 = type {
          typeName = type.description
        } else if case .int16 = type {
          typeName = type.description
        } else if case .int32 = type {
          typeName = type.description
        } else if case .int64 = type {
          typeName = type.description
        } else if case .uint = type {
          typeName = type.description
        } else if case .uint8 = type {
          typeName = type.description
        } else if case .uint16 = type {
          typeName = type.description
        } else if case .uint32 = type {
          typeName = type.description
        } else if case .uint64 = type {
          typeName = type.description
        } else if case .float32 = type {
          typeName = type.description
        } else if case .float64 = type {
          typeName = type.description
        } else if case .bool = type {
          typeName = type.description
        } else {
          // Skip unsupported types, will be caught in pass 3
          return
        }
        
        if extensionMethods[typeName] == nil {
          extensionMethods[typeName] = [:]
        }
        
        // Pre-register method signatures (without checking bodies)
        for method in methods {
          let methodType = try withNewScope {
            for typeParam in method.typeParameters {
              try currentScope.defineType(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            
            try currentScope.defineType("Self", type: type)
            currentScope.define("self", type, mutable: false)
            
            let returnType = try resolveTypeNode(method.returnType)
            let params = try method.parameters.map { param -> Parameter in
              let paramType = try resolveTypeNode(param.type)
              let passKind: PassKind = param.mutable ? .byMutRef : .byVal
              return Parameter(type: paramType, kind: passKind)
            }
            
            return Type.function(parameters: params, returns: returnType)
          }
          
          let methodKind = getCompilerMethodKind(method.name)
          let methodSymbol = Symbol(
            name: method.name,
            type: methodType,
            kind: .function,
            methodKind: methodKind
          )
          
          extensionMethods[typeName]![method.name] = methodSymbol
        }
      }
      
    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span
      if !typeParams.isEmpty {
        // Generic intrinsic given - register method signatures
        guard case .generic(let baseName, _) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }

        if genericIntrinsicExtensionMethods[baseName] == nil {
          genericIntrinsicExtensionMethods[baseName] = []
        }

        for m in methods {
          genericIntrinsicExtensionMethods[baseName]!.append((typeParams: typeParams, method: m))
        }
      } else {
        // Non-generic intrinsic given - collect method signatures for forward reference support
        let type = try resolveTypeNode(typeNode)
        
        let typeName: String
        switch type {
        case .structure(let decl):
          typeName = decl.name
        case .union(let decl):
          typeName = decl.name
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64,
             .bool:
          typeName = type.description
        default:
          // Skip unsupported types, will be caught in pass 3
          return
        }
        
        if extensionMethods[typeName] == nil {
          extensionMethods[typeName] = [:]
        }
        
        // Pre-register method signatures (without checking bodies)
        for method in methods {
          let methodType = try withNewScope {
            try currentScope.defineType("Self", type: type)
            
            let returnType = try resolveTypeNode(method.returnType)
            let params = try method.parameters.map { param -> Parameter in
              let paramType = try resolveTypeNode(param.type)
              let passKind: PassKind = param.mutable ? .byMutRef : .byVal
              return Parameter(type: paramType, kind: passKind)
            }
            
            return Type.function(parameters: params, returns: returnType)
          }
          
          let methodKind = getCompilerMethodKind(method.name)
          let methodSymbol = Symbol(
            name: method.name,
            type: methodType,
            kind: .function,
            methodKind: methodKind
          )
          
          extensionMethods[typeName]![method.name] = methodSymbol
        }
      }
      
    case .globalStructDeclaration(let name, let typeParameters, let parameters, let access, let span):
      self.currentSpan = span
      // Resolve non-generic struct types so function signatures can reference them
      if typeParameters.isEmpty {
        // Non-generic struct: resolve member types and finalize the type definition
        let isPrivate = (access == .private)
        let placeholder = isPrivate 
          ? currentScope.lookupType(name, sourceFile: currentSourceFile)!
          : currentScope.lookupType(name)!
        
        let params = try parameters.map { param -> Symbol in
          let paramType = try resolveTypeNode(param.type)
          if paramType == placeholder {
            throw SemanticError.invalidOperation(
              op: "Direct recursion in struct \(name) not allowed (use ref)", type1: param.name,
              type2: "")
          }
          return Symbol(
            name: param.name, type: paramType,
            kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
        }
        
        // Create a new Type with resolved members and overwrite the placeholder
        // (StructDecl is now a struct, so we can't mutate it in place)
        if case .structure(let decl) = placeholder {
          let newDecl = StructDecl(
            id: decl.id,  // Keep the same UUID for identity
            name: decl.name,
            modulePath: decl.modulePath,
            sourceFile: decl.sourceFile,
            access: decl.access,
            members: params.map { (name: $0.name, type: $0.type, mutable: $0.isMutable()) },
            isGenericInstantiation: decl.isGenericInstantiation,
            typeArguments: decl.typeArguments
          )
          let resolvedType = Type.structure(decl: newDecl)
          if isPrivate {
            currentScope.overwritePrivateType(name, sourceFile: currentSourceFile, type: resolvedType)
          } else {
            currentScope.overwriteType(name, type: resolvedType)
          }
        }
      }
      // Generic structs are handled in pass 3
      
    case .globalUnionDeclaration(let name, let typeParameters, let cases, let access, let span):
      self.currentSpan = span
      // Resolve non-generic union types so function signatures can reference them
      if typeParameters.isEmpty {
        // Non-generic union: resolve case types and finalize the type definition
        let isPrivate = (access == .private)
        let placeholder = isPrivate
          ? currentScope.lookupType(name, sourceFile: currentSourceFile)!
          : currentScope.lookupType(name)!
        
        var unionCases: [UnionCase] = []
        for c in cases {
          var params: [(name: String, type: Type)] = []
          for p in c.parameters {
            let resolved = try resolveTypeNode(p.type)
            if resolved == placeholder {
              throw SemanticError.invalidOperation(
                op: "Direct recursion in union \(name) not allowed (use ref)", type1: p.name,
                type2: "")
            }
            params.append((name: p.name, type: resolved))
          }
          unionCases.append(UnionCase(name: c.name, parameters: params))
        }
        
        // Create a new Type with resolved cases and overwrite the placeholder
        // (UnionDecl is now a struct, so we can't mutate it in place)
        if case .union(let decl) = placeholder {
          let newDecl = UnionDecl(
            id: decl.id,  // Keep the same UUID for identity
            name: decl.name,
            modulePath: decl.modulePath,
            sourceFile: decl.sourceFile,
            access: decl.access,
            cases: unionCases,
            isGenericInstantiation: decl.isGenericInstantiation,
            typeArguments: decl.typeArguments
          )
          let resolvedType = Type.union(decl: newDecl)
          if isPrivate {
            currentScope.overwritePrivateType(name, sourceFile: currentSourceFile, type: resolvedType)
          } else {
            currentScope.overwriteType(name, type: resolvedType)
          }
        }
      }
      // Generic unions are handled in pass 3
      
    case .globalFunctionDeclaration(let name, let typeParameters, let parameters, let returnTypeNode, _, let access, let span):
      self.currentSpan = span
      // Register function signature so it can be called from methods defined earlier
      if typeParameters.isEmpty {
        // Non-generic function: register signature now
        let returnType = try resolveTypeNode(returnTypeNode)
        let params = try parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          // In Koral, 'mutable' in parameter means it's a mutable reference (ref)
          let passKind: PassKind = param.mutable ? .byMutRef : .byVal
          return Parameter(type: paramType, kind: passKind)
        }
        let functionType = Type.function(parameters: params, returns: returnType)
        
        // For private functions, use file-isolated registration
        let isPrivate = (access == .private)
        if isPrivate {
          currentScope.definePrivateFunction(name, sourceFile: currentSourceFile, type: functionType, modulePath: currentModulePath)
        } else {
          currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath)
        }
      }
      // Generic functions are handled in pass 3
      
    case .intrinsicFunctionDeclaration(let name, let typeParameters, let parameters, let returnTypeNode, _, let span):
      self.currentSpan = span
      // Register intrinsic function signature so it can be called from methods defined earlier
      if typeParameters.isEmpty {
        let returnType = try resolveTypeNode(returnTypeNode)
        let params = try parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          let passKind: PassKind = param.mutable ? .byMutRef : .byVal
          return Parameter(type: paramType, kind: passKind)
        }
        let functionType = Type.function(parameters: params, returns: returnType)
        currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath)
      }
      // Generic intrinsic functions are handled in pass 3
      
    default:
      // Other declarations are handled in pass 3
      break
    }
  }

  private func checkGlobalDeclaration(_ decl: GlobalNode) throws -> TypedGlobalNode? {
    switch decl {
    case .usingDeclaration:
      // Using declarations are handled separately, skip here
      return nil
      
    case .traitDeclaration(_, _, let superTraits, _, _, let span):
      self.currentSpan = span
      // Trait was registered in pass 1, now validate superTraits
      for parent in superTraits {
        try validateTraitName(parent)
      }
      return nil

    case .globalUnionDeclaration(
      let name, let typeParameters, let cases, let access, let span):
      self.currentSpan = span

      if !typeParameters.isEmpty {
        // Generic union template was registered in pass 1
        // Now validate case parameter types
        try withNewScope {
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)
          
          for c in cases {
            for p in c.parameters {
              _ = try resolveTypeNode(p.type)
            }
          }
        }
        
        return .genericTypeTemplate(name: name)
      }

      // Non-generic union: already resolved in Pass 2
      // Just return the typed declaration
      let isPrivate = (access == .private)
      let type = isPrivate
        ? currentScope.lookupType(name, sourceFile: currentSourceFile)!
        : currentScope.lookupType(name)!
      
      var unionCases: [UnionCase] = []
      if case .union(let decl) = type {
        unionCases = decl.cases
      }
      
      return .globalUnionDeclaration(
        identifier: makeGlobalSymbol(name: name, type: type, kind: .type, access: access), cases: unionCases)

    case .globalVariableDeclaration(let name, let typeNode, let value, let isMut, let access, let span):
      self.currentSpan = span
      // For private variables, allow same name in different files
      let isPrivate = (access == .private)
      
      if isPrivate {
        // Check only in private symbols for this file
        if currentScope.lookup(name, sourceFile: currentSourceFile) != nil {
          throw SemanticError.duplicateDefinition(name, line: span.line)
        }
      } else {
        guard case nil = currentScope.lookup(name) else {
          throw SemanticError.duplicateDefinition(name, line: span.line)
        }
      }
      let type = try resolveTypeNode(typeNode)
      
      // For Lambda expressions, pass the expected type for type inference
      var typedValue: TypedExpressionNode
      if case .lambdaExpression(let parameters, let returnType, let body, _) = value {
        typedValue = try inferLambdaExpression(
          parameters: parameters,
          returnType: returnType,
          body: body,
          expectedType: type
        )
      } else {
        typedValue = try inferTypedExpression(value)
      }
      
      if typedValue.type != .never && typedValue.type != type {
        throw SemanticError.typeMismatch(
          expected: type.description, got: typedValue.type.description)
      }
      if isPrivate {
        currentScope.definePrivateSymbol(name, sourceFile: currentSourceFile, type: type, mutable: isMut, modulePath: currentModulePath)
      } else {
        currentScope.defineWithModulePath(name, type, mutable: isMut, modulePath: currentModulePath)
      }
      
      let symbol = makeGlobalSymbol(name: name, type: type, kind: .variable(isMut ? .MutableValue : .Value), access: access)
      
      return .globalVariable(
        identifier: symbol,
        value: typedValue,
        kind: isMut ? .MutableValue : .Value
      )

    case .globalFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let body, let access,
      let span):
      self.currentSpan = span
      
      // For non-generic functions, skip duplicate check if already defined in Pass 2
      let isPrivate = (access == .private)
      let existingLookup = isPrivate 
        ? currentScope.lookup(name, sourceFile: currentSourceFile) 
        : currentScope.lookup(name)
      
      if typeParameters.isEmpty && existingLookup != nil {
        // Already defined in Pass 2, continue with body checking
      } else if currentScope.hasFunctionDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: span.line)
      }

      if !typeParameters.isEmpty {
        // Define placeholder template for recursion
        let placeholderTemplate = GenericFunctionTemplate(
          name: name,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: ExpressionNode.call(
            callee: .identifier("panic"), arguments: [.stringLiteral("recursion")]),
          access: access
        )
        currentScope.defineGenericFunctionTemplate(name, template: placeholderTemplate)

        // Perform declaration-site checking and store results
        let (checkedBody, checkedParams, checkedReturnType) = try withNewScope {
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)

          let returnType = try resolveTypeNode(returnTypeNode)
          let params = try parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          // Perform declaration-site checking
          let (typedBody, _) = try checkFunctionBody(params, returnType, body)
          return (typedBody, params, returnType)
        }

        // Create template with checked results
        let template = GenericFunctionTemplate(
          name: name,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: body,
          access: access,
          checkedBody: checkedBody,
          checkedParameters: checkedParams,
          checkedReturnType: checkedReturnType
        )
        currentScope.defineGenericFunctionTemplate(name, template: template)
        return .genericFunctionTemplate(name: name)
      }

      // Pre-calculate function type to allow recursion
      let returnType = try resolveTypeNode(returnTypeNode)
      let params = try parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }

      let functionType = Type.function(
        parameters: params.map {
          Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
        },
        returns: returnType
      )

      // Define placeholder for recursion (skip if already defined in Pass 2)
      let existingForRecursion = isPrivate 
        ? currentScope.lookup(name, sourceFile: currentSourceFile) 
        : currentScope.lookup(name)
      if existingForRecursion == nil {
        if isPrivate {
          currentScope.definePrivateFunction(name, sourceFile: currentSourceFile, type: functionType, modulePath: currentModulePath)
        } else {
          currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath)
        }
      }

      let (typedBody, _) = try checkFunctionBody(params, returnType, body)

      return .globalFunction(
        identifier: makeGlobalSymbol(name: name, type: functionType, kind: .function, access: access),
        parameters: params,
        body: typedBody
      )

    case .intrinsicFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let access, let span):
      self.currentSpan = span
      
      // Skip duplicate check for non-generic functions (already defined in Pass 2)
      if typeParameters.isEmpty && currentScope.lookup(name) != nil {
        // Already defined in Pass 2, just return nil
        return nil
      }
      
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name, line: span.line)
      }

      // Create a dummy body for intrinsic representation
      let dummyBody = ExpressionNode.booleanLiteral(false)

      if !typeParameters.isEmpty {
        try withNewScope {
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)
          _ = try resolveTypeNode(returnTypeNode)
          _ = try parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }
        }

        let template = GenericFunctionTemplate(
          name: name,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: dummyBody,
          access: access
        )
        currentScope.defineGenericFunctionTemplate(name, template: template)
        
        // Mark as intrinsic generic function for special handling during monomorphization
        intrinsicGenericFunctions.insert(name)
        
        return .genericFunctionTemplate(name: name)
      }

      let (functionType, _, _) = try withNewScope {
        let returnType = try resolveTypeNode(returnTypeNode)
        let params = try parameters.map { param -> Symbol in
          let paramType = try resolveTypeNode(param.type)
          return Symbol(
            name: param.name, type: paramType,
            kind: .variable(param.mutable ? .MutableValue : .Value))
        }
        let funcType = Type.function(
          parameters: params.map { Parameter(type: $0.type, kind: .byVal) }, returns: returnType)
        // Dummy typed body
        let typedBody = TypedExpressionNode.integerLiteral(value: "0", type: .int)
        return (funcType, typedBody, params)
      }
      currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath)
      return nil

    case .givenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span
      if !typeParams.isEmpty {
        // Generic Given - signatures were registered in Pass 2 (collectGivenSignatures)
        // Now we only need to check method bodies
        guard case .generic(let baseName, _) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }
        
        // Module rule check: Cannot add given declaration for types defined in external modules (std library)
        if stdLibTypes.contains(baseName) && !isCurrentDeclStdLib {
          throw SemanticError(.generic("Cannot add 'given' declaration for type '\(baseName)' defined in standard library"), line: span.line)
        }
        
        // Create a generic Self type for body checking
        let genericSelfArgs = typeParams.map { Type.genericParameter(name: $0.name) }
        let genericSelfType: Type
        if baseName == "Pointer" && genericSelfArgs.count == 1 {
          genericSelfType = .pointer(element: genericSelfArgs[0])
        } else if currentScope.lookupGenericStructTemplate(baseName) != nil {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        } else if currentScope.lookupGenericUnionTemplate(baseName) != nil {
          genericSelfType = .genericUnion(template: baseName, args: genericSelfArgs)
        } else {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        }
        
        // Find the templates registered in Pass 2 and check their bodies
        guard let templates = genericExtensionMethods[baseName] else {
          return nil
        }
        
        // Find the templates for this given block (they were added in order)
        // We need to find templates that match our methods
        for (_, method) in methods.enumerated() {
          // Find the template for this method
          guard let templateIndex = templates.firstIndex(where: { 
            $0.method.name == method.name && 
            $0.typeParams.count == typeParams.count &&
            $0.checkedBody == nil  // Not yet checked
          }) else {
            continue
          }
          
          let template = templates[templateIndex]
          
          // Check method body
          let checkedBody = try withNewScope {
            for typeParam in typeParams {
              try currentScope.defineType(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(typeParams)
            
            // Register method-level type parameters
            for typeParam in method.typeParameters {
              try currentScope.defineType(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(method.typeParameters)
            
            try currentScope.defineType("Self", type: genericSelfType)
            currentScope.define("self", genericSelfType, mutable: false)
            
            let (typedBody, _) = try checkFunctionBody(
              template.checkedParameters ?? [],
              template.checkedReturnType ?? .void,
              method.body
            )
            return typedBody
          }
          
          // Update the template with the checked body
          genericExtensionMethods[baseName]![templateIndex] = GenericExtensionMethodTemplate(
            typeParams: template.typeParams,
            method: template.method,
            checkedBody: checkedBody,
            checkedParameters: template.checkedParameters,
            checkedReturnType: template.checkedReturnType
          )
        }

        // Return nil as we process these lazily upon instantiation
        return nil
      }

      let type = try resolveTypeNode(typeNode)
      let typeName: String
      if case .structure(let decl) = type {
        typeName = decl.name
      } else if case .union(let decl) = type {
        typeName = decl.name
      } else if case .int = type {
        typeName = type.description
      } else if case .int8 = type {
        typeName = type.description
      } else if case .int16 = type {
        typeName = type.description
      } else if case .int32 = type {
        typeName = type.description
      } else if case .int64 = type {
        typeName = type.description
      } else if case .uint = type {
        typeName = type.description
      } else if case .uint8 = type {
        typeName = type.description
      } else if case .uint16 = type {
        typeName = type.description
      } else if case .uint32 = type {
        typeName = type.description
      } else if case .uint64 = type {
        typeName = type.description
      } else if case .float32 = type {
        typeName = type.description
      } else if case .float64 = type {
        typeName = type.description
      } else if case .bool = type {
        typeName = type.description
      } else {
        throw SemanticError.invalidOperation(
          op: "given extends only struct or union", type1: type.description, type2: "")
      }

      // Module rule check: Cannot add given declaration for types defined in external modules (std library)
      // This check ensures that users cannot extend types from the standard library
      if stdLibTypes.contains(typeName) && !isCurrentDeclStdLib {
        throw SemanticError(.generic("Cannot add 'given' declaration for type '\(typeName)' defined in standard library"), line: span.line)
      }

      var typedMethods: [TypedMethodDeclaration] = []

      if extensionMethods[typeName] == nil {
        extensionMethods[typeName] = [:]
      }

      // Pass 1: pre-register all method symbols so methods can call each other regardless
      // of declaration order within the `given` block.
      struct GivenMethodInfo {
        let method: MethodDeclaration
        let symbol: Symbol
        let params: [Symbol]
        let returnType: Type
      }

      var methodInfos: [GivenMethodInfo] = []
      methodInfos.reserveCapacity(methods.count)

      for method in methods {
        let (methodType, params, returnType) = try withNewScope {
          for typeParam in method.typeParameters {
            try currentScope.defineType(
              typeParam.name, type: .genericParameter(name: typeParam.name))
          }

          try currentScope.defineType("Self", type: type)
          currentScope.define("self", type, mutable: false)

          let returnType = try resolveTypeNode(method.returnType)
          let params = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          // Validate __drop signature
          if method.name == "__drop" {
            if params.count != 1 || params[0].name != "self" {
              throw SemanticError.invalidOperation(
                op: "__drop must have exactly one parameter 'self'", type1: "", type2: "")
            }
            if case .reference(_) = params[0].type {
              // OK
            } else {
              throw SemanticError.invalidOperation(
                op: "__drop 'self' parameter must be a reference",
                type1: params[0].type.description, type2: "")
            }
            if returnType != .void {
              throw SemanticError.invalidOperation(
                op: "__drop must return Void", type1: returnType.description, type2: "")
            }
          }

          let functionType = Type.function(
            parameters: params.map {
              Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
          )
          return (functionType, params, returnType)
        }

        let methodKind = getCompilerMethodKind(method.name)
        let methodSymbol = Symbol(
          name: method.name,  // Use original method name, Monomorphizer will mangle it
          type: methodType,
          kind: .function,
          methodKind: methodKind
        )

        extensionMethods[typeName]![method.name] = methodSymbol
        methodInfos.append(
          GivenMethodInfo(
            method: method, symbol: methodSymbol, params: params, returnType: returnType)
        )
      }

      // Pass 2: typecheck bodies with full method set available.
      for info in methodInfos {
        let typedBody = try withNewScope {
          for typeParam in info.method.typeParameters {
            try currentScope.defineType(
              typeParam.name, type: .genericParameter(name: typeParam.name))
          }

          try currentScope.defineType("Self", type: type)
          currentScope.define("self", type, mutable: false)

          let (typedBody, _) = try checkFunctionBody(info.params, info.returnType, info.method.body)
          return typedBody
        }

        typedMethods.append(
          TypedMethodDeclaration(
            identifier: info.symbol,
            parameters: info.params,
            body: typedBody,
            returnType: info.returnType
          )
        )
      }

      return .givenDeclaration(type: type, methods: typedMethods)

    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span
      if !typeParams.isEmpty {
        // Generic Given (Intrinsic)
        guard case .generic(let baseName, let args) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }
        if args.count != typeParams.count {
          throw SemanticError.typeMismatch(
            expected: "\(typeParams.count) generic params", got: "\(args.count)")
        }
        for (i, arg) in args.enumerated() {
          guard case .identifier(let argName) = arg, argName == typeParams[i].name else {
            throw SemanticError.invalidOperation(
              op: "generic given specialization not supported", type1: String(describing: arg),
              type2: "")
          }
        }

        if genericIntrinsicExtensionMethods[baseName] == nil {
          genericIntrinsicExtensionMethods[baseName] = []
        }

        for m in methods {
          genericIntrinsicExtensionMethods[baseName]!.append((typeParams: typeParams, method: m))
        }
        return nil
      }

      let type = try resolveTypeNode(typeNode)

      let typeName: String
      let shouldEmitGiven: Bool
      switch type {
      case .structure(let decl):
        typeName = decl.name
        shouldEmitGiven = true
      case .union(let decl):
        typeName = decl.name
        shouldEmitGiven = true
      case .int, .int8, .int16, .int32, .int64,
        .uint, .uint8, .uint16, .uint32, .uint64,
        .float32, .float64,
        .bool:
        typeName = type.description
        shouldEmitGiven = false
      default:
        throw SemanticError.invalidOperation(
          op: "intrinsic given target not supported", type1: type.description, type2: "")
      }

      var typedMethods: [TypedMethodDeclaration] = []

      for method in methods {
        let (methodType, typedBody, params, returnType) = try withNewScope {
          try currentScope.defineType("Self", type: type)
          let returnType = try resolveTypeNode(method.returnType)
          let params = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          let functionType = Type.function(
            parameters: params.map {
              Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
          )
          // Dummy body for intrinsic
          let typedBody = TypedExpressionNode.integerLiteral(value: "0", type: .int)
          return (functionType, typedBody, params, returnType)
        }

        let methodKind = getCompilerMethodKind(method.name)
        let methodSymbol = Symbol(
          name: method.name,  // Use original method name, Monomorphizer will mangle it
          type: methodType,
          kind: .function,
          methodKind: methodKind
        )

        if shouldEmitGiven {
          typedMethods.append(
            TypedMethodDeclaration(
              identifier: methodSymbol,
              parameters: params,
              body: typedBody,
              returnType: returnType
            ))
        }
        if extensionMethods[typeName] == nil {
          extensionMethods[typeName] = [:]
        }
        extensionMethods[typeName]![method.name] = methodSymbol
      }

      return shouldEmitGiven ? .givenDeclaration(type: type, methods: typedMethods) : nil

    case .globalStructDeclaration(
      let name, let typeParameters, let parameters, let access, let span):
      self.currentSpan = span
      // Note: Type was already registered in Pass 1 (collectTypeDefinition)
      // Non-generic types are resolved in Pass 2 (collectGivenSignatures)

      if !typeParameters.isEmpty {
        // Generic struct template was already registered in Pass 1
        // Now validate field types with type parameters in scope
        try withNewScope {
          // Define type parameters as generic parameter types
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)
          
          // Validate all field types are valid under the type parameters
          for param in parameters {
            _ = try resolveTypeNode(param.type)
          }
        }
        
        return .genericTypeTemplate(name: name)
      }

      // Non-generic struct: already resolved in Pass 2
      // Just return the typed declaration
      let isPrivate = (access == .private)
      let typeType = isPrivate 
        ? currentScope.lookupType(name, sourceFile: currentSourceFile)!
        : currentScope.lookupType(name)!

      let params = try parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
      }

      let symbol = makeGlobalSymbol(name: name, type: typeType, kind: .type, access: access)

      return .globalStructDeclaration(
        identifier: symbol,
        parameters: params
      )

    case .intrinsicTypeDeclaration(let name, let typeParameters, let access, let span):
      self.currentSpan = span
      // Note: Type was already registered in Pass 1 (collectTypeDefinition)
      // Pass 2 just returns the appropriate node

      if typeParameters.isEmpty {
        // Non-generic intrinsic type was already registered in Pass 1
        let type: Type
        if let existingType = currentScope.lookupType(name) {
          type = existingType
        } else {
          let decl = StructDecl(
            name: name,
            modulePath: currentModulePath,
            sourceFile: currentSourceFile,
            access: access,
            members: [],
            isGenericInstantiation: false
          )
          type = .structure(decl: decl)
        }
        let dummySymbol = makeGlobalSymbol(name: name, type: type, kind: .variable(.Value), access: access)
        return .globalStructDeclaration(identifier: dummySymbol, parameters: [])
      } else {
        // Generic intrinsic template was already registered in Pass 1
        // intrinsicGenericTypes was also already populated in Pass 1
        return .genericTypeTemplate(name: name)
      }
    }
  }
}

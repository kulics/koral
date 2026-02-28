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
        if case .foreignUsingDeclaration = node { return false }
        return true
      }
      
      // Clear any previous state
      instantiationRequests.removeAll()

      // Enable diagnostic collection for multi-error reporting
      collectErrors = true
      clearDiagnostics()

      // === PASS 1: Collect all type definitions using NameCollector ===
      // NameCollector collects all types, traits, and function names,
      // allocates DefIds for each definition, and registers module names.
      
      // Run NameCollector
      var nameCollectorOutput: NameCollectorOutput?
      do {
        let output = try runNameCollector(allNodes: allNodes, declarations: declarations)
        nameCollectorOutput = output
        // Store the NameCollector output for potential use by later passes
        self.nameCollectorOutput = output
        self.defIdMap = output.defIdMap
      } catch let error as SemanticError {
        try? handleError(error)
      }
      
      // === PASS 2: Resolve type signatures using TypeResolver ===
      // TypeResolver resolves type members and function signatures,
      // builds complete type information, registers given method signatures,
      // and builds module symbols.
      
      // Run TypeResolver
      var typeResolverOutput: TypeResolverOutput?
      if let nameCollectorOutput {
        do {
          let output = try runTypeResolver(nameCollectorOutput: nameCollectorOutput)
          typeResolverOutput = output
          // Store the TypeResolver output for potential use by later passes
          self.typeResolverOutput = output
        } catch let error as SemanticError {
          try? handleError(error)
        }
      }
      
      // === PASS 3: Check function bodies using BodyChecker ===
      // BodyChecker checks function bodies and expressions,
      // performs type inference, generates typed AST,
      // and collects generic instantiation requests.
      
      // Run BodyChecker
      if let typeResolverOutput {
        do {
          let output = try runBodyChecker(typeResolverOutput: typeResolverOutput)
          // Store the BodyChecker output for potential use by later stages
          self.bodyCheckerOutput = output
        } catch let error as SemanticError {
          try? handleError(error)
        }
      }
      
      guard let bodyCheckerOutput = self.bodyCheckerOutput else {
        if hasCollectedErrors {
          throw diagnosticCollector
        }
        throw SemanticError(.generic("BodyChecker output missing"), span: currentSpan)
      }
      
      // Build the typed program
      let program = bodyCheckerOutput.typedAST
      
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

      if hasCollectedErrors {
        throw diagnosticCollector
      }

      return TypeCheckerOutput(
        program: program,
        instantiationRequests: bodyCheckerOutput.instantiationRequests,
        genericTemplates: registry,
        context: context
      )
    }
  }
  
  // MARK: - Pass 1.5: Register Module Names
  
  /// Registers module names in scope so that module-qualified types can be resolved.
  /// This is called after Pass 1 and before Pass 2.
  /// Only registers the module names, the public symbols will be populated in Pass 2.5.
  func registerModuleNames(from declarations: [GlobalNode]) throws {
    // Collect all unique module paths
    var allModulePaths: Set<String> = []
    
    for (index, _) in declarations.enumerated() {
      guard let sourceInfo = nodeSourceInfoMap[index] else { continue }
      let modulePath = sourceInfo.modulePath
      
      // Skip root module (empty path) - we only care about submodules
      if modulePath.isEmpty { continue }
      
      let moduleKey = modulePath.joined(separator: ".")
      allModulePaths.insert(moduleKey)
    }
    
    // Register module names in scope for direct child modules
    for moduleKey in allModulePaths {
      let parts = moduleKey.split(separator: ".").map(String.init)
      
      // Only register direct child modules (depth 2 from root)
      // Example: ["expr_eval", "frontend"] has 2 parts, so "frontend" is a direct child
      if parts.count == 2 {
        let submoduleName = parts[1]
        
        // Create an empty ModuleSymbolInfo (will be populated in Pass 2.5)
        let moduleInfo = ModuleSymbolInfo(
          modulePath: parts,
          publicSymbols: [:],
          publicTypes: [:]
        )
        moduleSymbols[moduleKey] = moduleInfo
        
        let moduleType = Type.module(info: moduleInfo)
        // Register the submodule name in scope
        currentScope.define(submoduleName, moduleType, mutable: false)
      }
    }
  }
  
  // MARK: - Pass 2.5: Build Module Symbols
  
  /// Builds module symbols from collected definitions.
  /// This allows `using self.child` to work by creating module symbols
  /// that can be accessed via `child.xxx`.
  func buildModuleSymbols(from declarations: [GlobalNode]) throws {
    // Step 1: Collect all unique module paths
    var allModulePaths: Set<String> = []
    
    for (index, _) in declarations.enumerated() {
      guard let sourceInfo = nodeSourceInfoMap[index] else { continue }
      let modulePath = sourceInfo.modulePath
      
      // Skip root module (empty path) - we only care about submodules
      if modulePath.isEmpty { continue }
      
      let moduleKey = modulePath.joined(separator: ".")
      allModulePaths.insert(moduleKey)
    }
    
    // Step 2: Collect all symbols by module path
    var symbolsByModule: [String: [(name: String, symbol: Symbol, type: Type?)]] = [:]
    
    for (index, decl) in declarations.enumerated() {
      guard let sourceInfo = nodeSourceInfoMap[index] else { continue }
      let modulePath = sourceInfo.modulePath
      currentSourceFile = sourceInfo.sourceFile
      currentModulePath = sourceInfo.modulePath
      currentSpan = decl.span
      
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
    
    // Step 3: Build ModuleSymbolInfo for each module (including empty ones)
    for moduleKey in allModulePaths {
      var publicSymbols: [String: Symbol] = [:]
      var publicTypes: [String: Type] = [:]
      
      if let symbols = symbolsByModule[moduleKey] {
        for (name, symbol, type) in symbols {
          // Only include public symbols (for now, include all non-private)
          let access = defIdMap.getAccess(symbol.defId) ?? .protected
          if access != .private {
            publicSymbols[name] = symbol
            if let t = type {
              publicTypes[name] = t
            }
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
    
    // Step 4: Register module symbols in scope for direct child modules
    // For each submodule, register its name as a module symbol in the parent scope
    // Example: for module path ["expr_eval", "frontend"], register "frontend" as a module symbol
    for (moduleKey, moduleInfo) in moduleSymbols {
      let parts = moduleKey.split(separator: ".").map(String.init)
      
      // Only register direct child modules (depth 2 from root)
      // Example: ["expr_eval", "frontend"] has 2 parts, so "frontend" is a direct child
      if parts.count == 2 {
        let submoduleName = parts[1]
        let moduleType = Type.module(info: moduleInfo)
        // Register the submodule name in scope
        currentScope.define(submoduleName, moduleType, mutable: false)
      }
    }
  }
  
  /// Extracts symbol information from a global declaration.
  private func extractSymbolInfo(from decl: GlobalNode, sourceInfo: GlobalNodeSourceInfo) -> (name: String, symbol: Symbol, type: Type?)? {
    switch decl {
    case .globalFunctionDeclaration(let name, let typeParameters, let parameters, let returnType, _, _, _):
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
      if let defId = currentScope.lookup(name, sourceFile: sourceInfo.sourceFile),
         let funcType = defIdMap.getSymbolType(defId) {
        let symbol = Symbol(
          defId: defId,
          type: funcType,
          kind: .function,
          methodKind: defIdMap.getSymbolMethodKind(defId) ?? .normal
        )
        return (name, symbol, nil)
      }
      return nil

    case .foreignFunctionDeclaration(let name, _, _, _, _):
      if let defId = currentScope.lookup(name, sourceFile: sourceInfo.sourceFile),
         let funcType = defIdMap.getSymbolType(defId) {
        let symbol = Symbol(
          defId: defId,
          type: funcType,
          kind: .function,
          methodKind: defIdMap.getSymbolMethodKind(defId) ?? .normal
        )
        return (name, symbol, nil)
      }
      return nil
      
    case .globalStructDeclaration(let name, let typeParameters, _, _, _):
      // Skip generic structs for now
      if !typeParameters.isEmpty { return nil }
      
      if let structType = currentScope.lookupType(name, sourceFile: sourceInfo.sourceFile) {
        let defId: DefId
        switch structType {
        case .structure(let typeDefId), .union(let typeDefId):
          defId = typeDefId
        default:
          return nil
        }
        let symbol = Symbol(
          defId: defId,
          type: structType,
          kind: .type,
          methodKind: .normal
        )
        return (name, symbol, structType)
      }
      return nil
      
    case .globalUnionDeclaration(let name, let typeParameters, _, _, _):
      // Skip generic unions for now
      if !typeParameters.isEmpty { return nil }
      
      if let unionType = currentScope.lookupType(name, sourceFile: sourceInfo.sourceFile) {
        let defId: DefId
        switch unionType {
        case .structure(let typeDefId), .union(let typeDefId):
          defId = typeDefId
        default:
          return nil
        }
        let symbol = Symbol(
          defId: defId,
          type: unionType,
          kind: .type,
          methodKind: .normal
        )
        return (name, symbol, unionType)
      }
      return nil

    case .foreignTypeDeclaration(let name, _, _, let access, _):
      let type = access == .private
        ? currentScope.lookupType(name, sourceFile: sourceInfo.sourceFile)
        : currentScope.lookupType(name)
      if let type {
        let defId: DefId
        switch type {
        case .structure(let typeDefId), .union(let typeDefId), .opaque(let typeDefId):
          defId = typeDefId
        default:
          return nil
        }
        let symbol = Symbol(
          defId: defId,
          type: type,
          kind: .type,
          methodKind: .normal
        )
        return (name, symbol, type)
      }
      return nil
      
    case .globalVariableDeclaration(let name, _, _, _, _, _):
      if let defId = currentScope.lookup(name, sourceFile: sourceInfo.sourceFile),
         let varType = defIdMap.getSymbolType(defId) {
        let symbol = Symbol(
          defId: defId,
          type: varType,
          kind: .variable(.Value),
          methodKind: defIdMap.getSymbolMethodKind(defId) ?? .normal
        )
        return (name, symbol, nil)
      }
      return nil
    case .foreignLetDeclaration(let name, _, _, _, _):
      if let defId = currentScope.lookup(name, sourceFile: sourceInfo.sourceFile),
         let varType = defIdMap.getSymbolType(defId) {
        let symbol = Symbol(
          defId: defId,
          type: varType,
          kind: .variable(.Value),
          methodKind: defIdMap.getSymbolMethodKind(defId) ?? .normal
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
          ), span: currentSpan)
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
          ), span: currentSpan)
        }
      }
    }
  }
  
  // MARK: - Pass 1: Type Collection
  
  /// Collects type definitions without checking function bodies.
  /// This allows forward references to work correctly.
  /// - Parameter isStdLib: Whether this declaration is from the standard library
  func collectTypeDefinition(_ decl: GlobalNode, isStdLib: Bool = false) throws {
    switch decl {
    case .usingDeclaration:
      // Using declarations are handled separately, skip here
      return
    case .foreignUsingDeclaration:
      // Foreign using is handled in CodeGen, skip here
      return
      
    case .traitDeclaration(let name, let typeParameters, let superTraits, let methods, let access, let span):
      self.currentSpan = span
      if traits[name] != nil {
        throw SemanticError.duplicateDefinition(name, span: span)
      }
      
      // Check for method-level type parameter conflicts with trait-level type parameters
      try checkMethodTypeParameterConflicts(
        methods: methods,
        outerTypeParams: typeParameters,
        contextName: "trait '\(name)'"
      )
      
      // Note: We don't validate superTraits here because they might be forward references
      // They will be validated in pass 2
      var resolvedSuperTraits: [TraitConstraint] = []
      for parent in superTraits {
        resolvedSuperTraits.append(try SemaUtils.resolveTraitConstraint(from: parent))
      }
      traits[name] = TraitDeclInfo(
        name: name,
        typeParameters: typeParameters,
        superTraits: resolvedSuperTraits,
        methods: methods,
        access: access,
        modulePath: currentModulePath
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
        throw SemanticError.duplicateDefinition(name, span: span)
      }
      
      if !typeParameters.isEmpty {
        // Register generic union template
        let defId = defIdMap.allocate(
          modulePath: currentModulePath,
          name: name,
          kind: .genericTemplate(.union),
          sourceFile: currentSourceFile,
          access: access,
          span: currentSpan
        )
        let template = GenericUnionTemplate(
          defId: defId, typeParameters: typeParameters, cases: cases)
        currentScope.defineGenericUnionTemplate(name, template: template)
      } else {
        // Register placeholder for non-generic union (allows recursive references)
        let defId = getOrAllocateTypeDefId(
          name: name,
          kind: .union,
          access: access,
          modulePath: currentModulePath,
          sourceFile: currentSourceFile
        )
        let placeholder = Type.union(defId: defId)
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
        throw SemanticError.duplicateDefinition(name, span: span)
      }
      
      if !typeParameters.isEmpty {
        // Register generic struct template
        let defId = defIdMap.allocate(
          modulePath: currentModulePath,
          name: name,
          kind: .genericTemplate(.structure),
          sourceFile: currentSourceFile,
          access: access,
          span: currentSpan
        )
        let template = GenericStructTemplate(
          defId: defId, typeParameters: typeParameters, parameters: parameters)
        currentScope.defineGenericStructTemplate(name, template: template)
      } else {
        // Register placeholder for non-generic struct (allows recursive references)
        let defId = getOrAllocateTypeDefId(
          name: name,
          kind: .structure,
          access: access,
          modulePath: currentModulePath,
          sourceFile: currentSourceFile
        )
        let placeholder = Type.structure(defId: defId)
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
      
    case .foreignTypeDeclaration(let name, _, let fields, let access, let span):
      self.currentSpan = span
      let isPrivate = (access == .private)
      if !isPrivate && currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, span: span)
      }
      let kind: TypeDefKind = fields == nil ? .opaque : .structure
      let defId = getOrAllocateTypeDefId(
        name: name,
        kind: kind,
        access: access,
        modulePath: currentModulePath,
        sourceFile: currentSourceFile
      )
      let placeholder: Type = fields == nil
        ? .opaque(defId: defId)
        : .structure(defId: defId)
      if isPrivate {
        try currentScope.definePrivateType(name, sourceFile: currentSourceFile, type: placeholder)
      } else {
        try currentScope.defineType(name, type: placeholder)
      }
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
      
    case .foreignFunctionDeclaration:
      // Foreign function signatures are handled in pass 2
      break
      
    case .globalVariableDeclaration:
      // Variables are handled in pass 2
      break
    case .foreignLetDeclaration:
      // Foreign global variables are handled in pass 3
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
            // It might be an intrinsic type like Ptr, which is OK
          }
        }
      }
      // Non-generic given is handled in pass 2

    case .givenTraitDeclaration(let typeParams, let typeNode, _, _, let span):
      self.currentSpan = span
      // Trait-conformance given declaration does not define a new type;
      // type/method validation is performed in pass 2/3.
      if !typeParams.isEmpty {
        if case .generic(_, _) = typeNode {
          // validated later
        }
      }
      
    case .intrinsicTypeDeclaration(let name, let typeParameters, _, let span):
      self.currentSpan = span
      
      // Module rule check: intrinsic declarations are only allowed in standard library
      if !isStdLib {
        throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), span: span)
      }
      
      if currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, span: span)
      }
      
      if !typeParameters.isEmpty {
        // Register as intrinsic generic type
        intrinsicGenericTypes.insert(name)
        let defId = defIdMap.allocate(
          modulePath: currentModulePath,
          name: name,
          kind: .genericTemplate(.structure),
          sourceFile: currentSourceFile,
          access: .protected,
          span: currentSpan
        )
        let template = GenericStructTemplate(
          defId: defId, typeParameters: typeParameters, parameters: [])
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
          let defId = getOrAllocateTypeDefId(
            name: name,
            kind: .structure,
            access: .protected,
            modulePath: currentModulePath,
            sourceFile: currentSourceFile
          )
          type = .structure(defId: defId)
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
        throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), span: span)
      }
      
      if !typeParameters.isEmpty {
        intrinsicGenericFunctions.insert(name)
      }
      // Function signature will be registered in pass 3
      
    case .intrinsicGivenDeclaration(_, _, _, let span):
      // Module rule check: intrinsic declarations are only allowed in standard library
      if !isStdLib {
        self.currentSpan = span
        throw SemanticError(.generic("'intrinsic' declarations are only allowed in the standard library"), span: span)
      }
      // Handled in pass 2 (signature) and pass 3 (body)
      break

    case .typeAliasDeclaration(let name, let targetType, let access, let span):
      self.currentSpan = span
      let isPrivate = (access == .private)
      
      // Circular type alias detection
      if resolvingTypeAliases.contains(name) {
        throw SemanticError(.generic("Circular type alias: \(name)"), span: span)
      }
      resolvingTypeAliases.insert(name)
      defer { resolvingTypeAliases.remove(name) }
      
      // Resolve the target type
      let resolvedType = try resolveTypeNode(targetType)
      
      // Register the resolved type in scope
      if isPrivate {
        try currentScope.definePrivateType(name, sourceFile: currentSourceFile, type: resolvedType)
      } else {
        try currentScope.defineType(name, type: resolvedType)
      }
    }
  }
  
  // MARK: - Pass 2: Given Signature Collection
  
  /// Collects given method signatures without checking bodies.
  /// This allows methods in one given block to call methods in another given block.
  /// Also resolves struct and union types so function signatures can reference them.
  func collectGivenSignatures(_ decl: GlobalNode) throws {
    switch decl {
    case .givenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span

      // `given Trait { ... }` tool method declaration (supports generic traits)
      if let traitConstraint = try? SemaUtils.resolveTraitConstraint(from: typeNode),
         traits[traitConstraint.baseName] != nil {
        let traitName = traitConstraint.baseName
        guard let traitInfo = traits[traitName] else {
          throw SemanticError(.generic("Undefined trait: \(traitName)"), span: span)
        }

        let traitArgNodes: [TypeNode]
        switch traitConstraint {
        case .simple:
          traitArgNodes = []
        case .generic(_, let args):
          traitArgNodes = args
        }

        if traitInfo.typeParameters.count != typeParams.count {
          throw SemanticError.typeMismatch(
            expected: "\(traitInfo.typeParameters.count) generic params",
            got: "\(typeParams.count)"
          )
        }

        if !typeParams.isEmpty {
          if traitArgNodes.count != typeParams.count {
            throw SemanticError.typeMismatch(
              expected: "\(typeParams.count) generic params",
              got: "\(traitArgNodes.count)"
            )
          }
          for (i, arg) in traitArgNodes.enumerated() {
            guard case .identifier(let argName) = arg, argName == typeParams[i].name else {
              throw SemanticError.invalidOperation(
                op: "generic given specialization not supported",
                type1: String(describing: arg),
                type2: ""
              )
            }
          }
        }

        // Module boundary rule: same root module subtree only
        let sameRoot: Bool = {
          guard let lhs = traitInfo.modulePath.first,
                let rhs = currentModulePath.first else { return true }
          return lhs == rhs
        }()
        if !sameRoot {
          throw SemanticError(.generic(
            "Cannot declare 'given \(traitName)' outside its root module subtree"
          ), span: span)
        }

        let requirementNames = Set(traitInfo.methods.map { $0.name })
        for method in methods {
          if requirementNames.contains(method.name) {
            throw SemanticError(.generic(
              "Trait entity method '\(method.name)' conflicts with requirement in trait '\(traitName)'"
            ), span: span)
          }
        }

        var existingBlocks = traitToolBlocks[traitName] ?? []
        for block in existingBlocks {
          for existingMethod in block.methods {
            if methods.contains(where: { $0.name == existingMethod.name }) {
              throw SemanticError.duplicateDefinition(existingMethod.name, span: span)
            }
          }
        }
        existingBlocks.append(
          TraitToolBlock(
            traitName: traitName,
            traitTypeParams: typeParams,
            methods: methods
          )
        )
        traitToolBlocks[traitName] = existingBlocks
        return
      }

      if !typeParams.isEmpty {
        // Generic Given - register method signatures
        let baseName: String
        let args: [TypeNode]
        switch typeNode {
        case .generic(let base, let typeArgs):
          baseName = base
          args = typeArgs
        case .pointer(let inner):
          baseName = "Ptr"
          args = [inner]
        default:
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
        if baseName == "Ptr" && genericSelfArgs.count == 1 {
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
              currentScope.defineGenericParameter(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(typeParams)

            // Register method-level type parameters
            for typeParam in method.typeParameters {
              currentScope.defineGenericParameter(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(method.typeParameters)

            try currentScope.defineType("Self", type: genericSelfType)
            currentScope.define("self", genericSelfType, mutable: false)

            let returnType = try resolveTypeNode(method.returnType)
            let params = try method.parameters.map { param -> Symbol in
              let paramType = try resolveTypeNode(param.type)
              return makeLocalSymbol(
                name: param.name, type: paramType,
                kind: .variable(param.mutable ? .MutableValue : .Value))
            }

            // Validate __drop signature
            if method.name == "__drop" {
              let firstParamName = params.first.flatMap { context.getName($0.defId) }
              if params.count != 1 || firstParamName != "self" {
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

          // Check for duplicate method name on this type
          let existsInGeneric = genericExtensionMethods[baseName]!.contains(where: { $0.method.name == method.name })
          let existsInIntrinsic = (genericIntrinsicExtensionMethods[baseName] ?? []).contains(where: { $0.method.name == method.name })
          if existsInGeneric || existsInIntrinsic {
            throw SemanticError.duplicateDefinition(method.name, span: span)
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
        if case .structure(let defId) = type {
          typeName = context.getName(defId) ?? ""
        } else if case .union(let defId) = type {
          typeName = context.getName(defId) ?? ""
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
        if genericExtensionMethods[typeName] == nil {
          genericExtensionMethods[typeName] = []
        }

        // Pre-register method signatures (without checking bodies)
        for method in methods {
          let methodType = try withNewScope {
            for typeParam in method.typeParameters {
              currentScope.defineGenericParameter(
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
          let methodSymbol = makeGlobalSymbol(
            name: method.name,
            type: methodType,
            kind: .function,
            methodKind: methodKind,
            access: .protected
          )
          registerReceiverStyleMethod(methodSymbol, parameters: method.parameters)

          if method.typeParameters.isEmpty {
            // Check for duplicate method name on this type
            if extensionMethods[typeName]![method.name] != nil {
              throw SemanticError.duplicateDefinition(method.name, span: span)
            }

            extensionMethods[typeName]![method.name] = methodSymbol
          } else {
            let existsInGeneric = genericExtensionMethods[typeName]!.contains(where: { $0.method.name == method.name })
            let existsInIntrinsic = (genericIntrinsicExtensionMethods[typeName] ?? []).contains(where: { $0.method.name == method.name })
            if existsInGeneric || existsInIntrinsic {
              throw SemanticError.duplicateDefinition(method.name, span: span)
            }

            genericExtensionMethods[typeName]!.append(GenericExtensionMethodTemplate(
              typeParams: [],
              method: method,
              checkedBody: nil,
              checkedParameters: nil,
              checkedReturnType: nil
            ))
          }
        }
      }

    case .givenTraitDeclaration(let typeParams, let typeNode, let traitNode, let methods, let span):
      self.currentSpan = span
      let traitConstraint = try SemaUtils.resolveTraitConstraint(from: traitNode)
      let traitName = traitConstraint.baseName
      try validateTraitName(traitName)

      let selfType: Type
      if !typeParams.isEmpty {
        let baseName: String
        let args: [TypeNode]
        switch typeNode {
        case .generic(let base, let typeArgs):
          baseName = base
          args = typeArgs
        case .pointer(let inner):
          baseName = "Ptr"
          args = [inner]
        default:
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
              op: "generic given specialization not supported", type1: String(describing: arg), type2: "")
          }
        }
        let genericSelfArgs = typeParams.map { Type.genericParameter(name: $0.name) }
        if baseName == "Ptr" && genericSelfArgs.count == 1 {
          selfType = .pointer(element: genericSelfArgs[0])
        } else if currentScope.lookupGenericStructTemplate(baseName) != nil {
          selfType = .genericStruct(template: baseName, args: genericSelfArgs)
        } else if currentScope.lookupGenericUnionTemplate(baseName) != nil {
          selfType = .genericUnion(template: baseName, args: genericSelfArgs)
        } else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: baseName, type2: "")
        }
      } else {
        selfType = try resolveTypeNode(typeNode)
      }

      let traitArgTypes: [Type] = try withNewScope {
        for typeParam in typeParams {
          currentScope.defineGenericParameter(
            typeParam.name,
            type: .genericParameter(name: typeParam.name)
          )
        }
        try recordGenericTraitBounds(typeParams)
        try currentScope.defineType("Self", type: selfType)
        switch traitConstraint {
        case .simple:
          return []
        case .generic(_, let argNodes):
          return try argNodes.map { try resolveTypeNode($0) }
        }
      }

      let key = ConformanceKey(
        selfType: exactConformanceTypeKey(selfType),
        traitName: traitName,
        traitTypeArgs: traitArgTypes.map { exactConformanceTypeKey($0) }
      )
      if declaredConformances.contains(key) {
        let origin = conformanceDeclOrigins[key]
        let originSuffix: String
        if let origin {
          originSuffix = " already declared at line \(origin.start.line)"
        } else {
          originSuffix = " already declared"
        }
        throw SemanticError(.generic(
          "Conflicting conformance: 'given \(selfType) \(traitName)'\(originSuffix)"
        ), span: span)
      }
      declaredConformances.insert(key)
      conformanceDeclOrigins[key] = span

      if !methods.isEmpty {
        var hasExistingMethodSignature = false

        if !typeParams.isEmpty {
          let baseName: String
          switch typeNode {
          case .generic(let name, _):
            baseName = name
          case .pointer:
            baseName = "Ptr"
          default:
            baseName = ""
          }
          if !baseName.isEmpty {
            let existingGeneric = Set((genericExtensionMethods[baseName] ?? []).map { $0.method.name })
            let existingIntrinsic = Set((genericIntrinsicExtensionMethods[baseName] ?? []).map { $0.method.name })
            hasExistingMethodSignature = methods.contains {
              existingGeneric.contains($0.name) || existingIntrinsic.contains($0.name)
            }
          }
        } else {
          let typeName: String? = {
            switch selfType {
            case .structure(let defId), .union(let defId):
              return context.getName(defId)
            case .int, .int8, .int16, .int32, .int64,
                 .uint, .uint8, .uint16, .uint32, .uint64,
                 .float32, .float64, .bool:
              return selfType.description
            default:
              return nil
            }
          }()
          if let typeName {
            let existingConcrete = Set((extensionMethods[typeName] ?? [:]).keys)
            hasExistingMethodSignature = methods.contains { existingConcrete.contains($0.name) }
          }
        }

        if !hasExistingMethodSignature {
          try collectGivenSignatures(
            .givenDeclaration(typeParams: typeParams, type: typeNode, methods: methods, span: span)
          )
        }
      }
      
    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span
      if !typeParams.isEmpty {
        // Generic intrinsic given - register method signatures
        let baseName: String
        switch typeNode {
        case .generic(let name, _):
          baseName = name
        case .pointer:
          baseName = "Ptr"
        default:
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }

        if genericIntrinsicExtensionMethods[baseName] == nil {
          genericIntrinsicExtensionMethods[baseName] = []
        }

        for m in methods {
          // Check for duplicate method name on this type
          let allExisting = (genericExtensionMethods[baseName] ?? []).map { $0.method.name }
            + genericIntrinsicExtensionMethods[baseName]!.map { $0.method.name }
          if allExisting.contains(m.name) {
            throw SemanticError.duplicateDefinition(m.name, span: span)
          }
          
          genericIntrinsicExtensionMethods[baseName]!.append((typeParams: typeParams, method: m))
        }
      } else {
        // Non-generic intrinsic given - collect method signatures for forward reference support
        let type = try resolveTypeNode(typeNode)
        
        let typeName: String
        switch type {
        case .structure(let defId):
          typeName = context.getName(defId) ?? ""
        case .union(let defId):
          typeName = context.getName(defId) ?? ""
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
          let methodSymbol = makeGlobalSymbol(
            name: method.name,
            type: methodType,
            kind: .function,
            methodKind: methodKind,
            access: .protected
          )
          registerReceiverStyleMethod(methodSymbol, parameters: method.parameters)
          
          // Check for duplicate method name on this type
          if extensionMethods[typeName]![method.name] != nil {
            throw SemanticError.duplicateDefinition(method.name, span: span)
          }
          
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
          return makeLocalSymbol(
            name: param.name, type: paramType,
            kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
        }
        
        // Update typed def info and overwrite the placeholder
        if case .structure(let defId) = placeholder {
          let members = zip(params, parameters).map { (sym, param) in
            let fieldAccess = param.access
            return (name: context.getName(sym.defId) ?? "<unknown>", type: sym.type, mutable: sym.isMutable(), access: fieldAccess)
          }
          context.updateStructInfo(
            defId: defId,
            members: members,
            isGenericInstantiation: false,
            typeArguments: nil
          )
          let resolvedType = Type.structure(defId: defId)
          if isPrivate {
            currentScope.overwritePrivateType(name, sourceFile: currentSourceFile, type: resolvedType)
          } else {
            currentScope.overwriteType(name, type: resolvedType)
          }
        }
      }
      // Generic structs are handled in pass 3

    case .foreignTypeDeclaration(let name, let cname, let fields, let access, let span):
      self.currentSpan = span
      guard let fields else {
        break
      }
      let isPrivate = (access == .private)
      let placeholder = isPrivate
        ? currentScope.lookupType(name, sourceFile: currentSourceFile)!
        : currentScope.lookupType(name)!

      var resolvedFields: [(name: String, type: Type)] = []
      for field in fields {
        let fieldType = try resolveTypeNode(field.type)
        if fieldType == placeholder {
          throw SemanticError.invalidOperation(
            op: "Direct recursion in foreign struct \(name) not allowed (use ptr)",
            type1: field.name,
            type2: ""
          )
        }
        resolvedFields.append((name: field.name, type: fieldType))
      }

      if case .structure(let defId) = placeholder {
        // Store cname if provided
        if let cname = cname {
          context.setCname(defId, cname)
        }
        let members = resolvedFields.map { (name: $0.name, type: $0.type, mutable: true, access: AccessModifier.public) }
        context.updateStructInfo(
          defId: defId,
          members: members,
          isGenericInstantiation: false,
          typeArguments: nil
        )
        context.updateForeignStructFields(defId: defId, fields: resolvedFields)
        let resolvedType = Type.structure(defId: defId)
        if isPrivate {
          currentScope.overwritePrivateType(name, sourceFile: currentSourceFile, type: resolvedType)
        } else {
          currentScope.overwriteType(name, type: resolvedType)
        }
      }
      
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
          var params: [(name: String, type: Type, access: AccessModifier)] = []
          for p in c.parameters {
            let resolved = try resolveTypeNode(p.type)
            if resolved == placeholder {
              throw SemanticError.invalidOperation(
                op: "Direct recursion in union \(name) not allowed (use ref)", type1: p.name,
                type2: "")
            }
            params.append((name: p.name, type: resolved, access: .public))
          }
          unionCases.append(UnionCase(name: c.name, parameters: params))
        }
        
        // Update typed def info and overwrite the placeholder
        if case .union(let defId) = placeholder {
          context.updateUnionInfo(
            defId: defId,
            cases: unionCases,
            isGenericInstantiation: false,
            typeArguments: nil
          )
          let resolvedType = Type.union(defId: defId)
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
        try assertNotOpaqueType(returnType, span: span)
        let params = try parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          try assertNotOpaqueType(paramType, span: span)
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
          currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath, access: access)
        }
      }
      // Generic functions are handled in pass 3

    case .foreignFunctionDeclaration(let name, let parameters, let returnTypeNode, let access, let span):
      self.currentSpan = span
      let isPrivate = (access == .private)
      if isPrivate {
        if currentScope.lookup(name, sourceFile: currentSourceFile) != nil {
          throw SemanticError.duplicateDefinition(name, span: span)
        }
      } else {
        guard case nil = currentScope.lookup(name) else {
          throw SemanticError.duplicateDefinition(name, span: span)
        }
      }

      let returnType = try resolveTypeNode(returnTypeNode)
      try assertNotOpaqueType(returnType, span: span)
      let params = try parameters.map { param -> Parameter in
        let paramType = try resolveTypeNode(param.type)
        try assertNotOpaqueType(paramType, span: span)
        let passKind: PassKind = param.mutable ? .byMutRef : .byVal
        return Parameter(type: paramType, kind: passKind)
      }
      let functionType = Type.function(parameters: params, returns: returnType)
      if isPrivate {
        currentScope.definePrivateFunction(name, sourceFile: currentSourceFile, type: functionType, modulePath: currentModulePath)
      } else {
        currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath, access: access)
      }
      
    case .intrinsicFunctionDeclaration(let name, let typeParameters, let parameters, let returnTypeNode, let access, let span):
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
        currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath, access: access)
      } else {
        // Register generic intrinsic function template in pass 2 so that
        // submodule code processed in pass 3 can find it (submodule nodes
        // are collected before parent module nodes).
        let defId = defIdMap.lookupGenericFunctionTemplateDefId(name)
          ?? defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .genericTemplate(.function),
            sourceFile: currentSourceFile,
            access: access,
            span: span
          )
        let dummyBody = ExpressionNode.booleanLiteral(false)
        let template = GenericFunctionTemplate(
          defId: defId,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: dummyBody
        )
        currentScope.defineGenericFunctionTemplate(name, template: template)
      }
      
    default:
      // Other declarations are handled in pass 3
      break
    }
  }

  func checkGlobalDeclaration(_ decl: GlobalNode) throws -> TypedGlobalNode? {
    switch decl {
    case .usingDeclaration:
      // Using declarations are handled separately, skip here
      return nil
    case .foreignUsingDeclaration(let libraryName, _):
      return .foreignUsing(libraryName: libraryName)
      
    case .traitDeclaration(_, let typeParameters, let superTraits, _, _, let span):
      self.currentSpan = span
      // Trait was registered in pass 1, now validate superTraits
      try withNewScope {
        for param in typeParameters {
          currentScope.defineGenericParameter(
            param.name, type: .genericParameter(name: param.name))
        }
        try recordGenericTraitBounds(typeParameters)

        for parent in superTraits {
          let constraint = try SemaUtils.resolveTraitConstraint(from: parent)
          try validateTraitName(constraint.baseName)
          if case .generic(let base, let args) = constraint {
            let traitInfo = traits[base]
            let expectedCount = traitInfo?.typeParameters.count ?? 0
            if expectedCount != args.count {
              throw SemanticError.typeMismatch(
                expected: "\(expectedCount) generic arguments",
                got: "\(args.count)"
              )
            }
            // Validate each trait type argument resolves
            for arg in args {
              _ = try resolveTypeNode(arg)
            }
          }
        }
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
            currentScope.defineGenericParameter(param.name, type: .genericParameter(name: param.name))
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
      if case .union(let defId) = type {
        unionCases = context.getUnionCases(defId) ?? []
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
          throw SemanticError.duplicateDefinition(name, span: span)
        }
      } else {
        guard case nil = currentScope.lookup(name) else {
          throw SemanticError.duplicateDefinition(name, span: span)
        }
      }
      let type = try resolveTypeNode(typeNode)
      try assertNotOpaqueType(type, span: span)
      
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
        currentScope.defineWithModulePath(name, type, mutable: isMut, modulePath: currentModulePath, access: access)
      }
      
      let symbol = makeGlobalSymbol(name: name, type: type, kind: .variable(isMut ? .MutableValue : .Value), access: access)
      
      return .globalVariable(
        identifier: symbol,
        value: typedValue,
        kind: isMut ? .MutableValue : .Value
      )

    case .foreignTypeDeclaration(let name, _, let fields, let access, let span):
      self.currentSpan = span
      let isPrivate = (access == .private)
      let type: Type
      if let existing = isPrivate
        ? currentScope.lookupType(name, sourceFile: currentSourceFile)
        : currentScope.lookupType(name) {
        type = existing
      } else {
        let kind: TypeDefKind = fields == nil ? .opaque : .structure
        let defId = getOrAllocateTypeDefId(
          name: name,
          kind: kind,
          access: access,
          modulePath: currentModulePath,
          sourceFile: currentSourceFile
        )
        type = fields == nil ? .opaque(defId: defId) : .structure(defId: defId)
        if isPrivate {
          try currentScope.definePrivateType(name, sourceFile: currentSourceFile, type: type)
        } else {
          try currentScope.defineType(name, type: type)
        }
      }
      if fields != nil, case .structure(let defId) = type {
        let resolvedFields = context.getForeignStructFields(defId) ?? []
        return .foreignStruct(
          identifier: makeGlobalSymbol(name: name, type: type, kind: .type, access: access),
          fields: resolvedFields
        )
      }
      return .foreignType(identifier: makeGlobalSymbol(name: name, type: type, kind: .type, access: access))

    case .foreignLetDeclaration(let name, let typeNode, let mutable, let access, let span):
      self.currentSpan = span
      let type = try resolveTypeNode(typeNode)
      try assertNotOpaqueType(type, span: span)

      let isPrivate = (access == .private)
      if isPrivate {
        if currentScope.lookup(name, sourceFile: currentSourceFile) != nil {
          throw SemanticError.duplicateDefinition(name, span: span)
        }
      } else {
        guard case nil = currentScope.lookup(name) else {
          throw SemanticError.duplicateDefinition(name, span: span)
        }
      }

      if isPrivate {
        currentScope.definePrivateSymbol(
          name,
          sourceFile: currentSourceFile,
          type: type,
          mutable: mutable,
          modulePath: currentModulePath
        )
      } else {
        currentScope.defineWithModulePath(name, type, mutable: mutable, modulePath: currentModulePath, access: access)
      }

      let symbol = makeGlobalSymbol(
        name: name,
        type: type,
        kind: .variable(mutable ? .MutableValue : .Value),
        access: access
      )
      return .foreignGlobalVariable(identifier: symbol, mutable: mutable)

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
        throw SemanticError.duplicateDefinition(name, span: span)
      }

      if !typeParameters.isEmpty {
        let defId = defIdMap.lookupGenericFunctionTemplateDefId(name)
          ?? defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .genericTemplate(.function),
            sourceFile: currentSourceFile,
            access: access,
            span: currentSpan
          )

        // Define placeholder template for recursion
        let placeholderTemplate = GenericFunctionTemplate(
          defId: defId,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: ExpressionNode.call(
            callee: .identifier("panic"), arguments: [.stringLiteral("recursion")])
        )
        currentScope.defineGenericFunctionTemplate(name, template: placeholderTemplate)

        // Perform declaration-site checking and store results
        let (checkedBody, checkedParams, checkedReturnType) = try withNewScope {
          for param in typeParameters {
            currentScope.defineGenericParameter(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)

          let returnType = try resolveTypeNode(returnTypeNode)
          let params = try parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return makeLocalSymbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          // Perform declaration-site checking
          let (typedBody, _) = try checkFunctionBody(params, returnType, body)
          return (typedBody, params, returnType)
        }

        // Create template with checked results
        let template = GenericFunctionTemplate(
          defId: defId,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: body,
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
        return makeLocalSymbol(
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
          currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath, access: access)
        }
      }

      let (typedBody, _) = try checkFunctionBody(params, returnType, body)

      return .globalFunction(
        identifier: makeGlobalSymbol(name: name, type: functionType, kind: .function, access: access),
        parameters: params,
        body: typedBody
      )

    case .foreignFunctionDeclaration(
      let name, let parameters, let returnTypeNode, let access, let span):
      self.currentSpan = span

      let returnType = try resolveTypeNode(returnTypeNode)
      if !isFfiCompatibleType(returnType) {
        throw SemanticError(
          .ffiIncompatibleType(type: returnType.description, reason: ffiTypeError(returnType)),
          span: span
        )
      }

      let params = try parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        if !isFfiCompatibleType(paramType) {
          throw SemanticError(
            .ffiIncompatibleType(type: paramType.description, reason: ffiTypeError(paramType)),
            span: span
          )
        }
        return makeLocalSymbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }

      let functionType = Type.function(
        parameters: params.map {
          Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
        },
        returns: returnType
      )

      let symbol = makeGlobalSymbol(name: name, type: functionType, kind: .function, access: access)
      return .foreignFunction(identifier: symbol, parameters: params)

    case .intrinsicFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let access, let span):
      self.currentSpan = span
      
      // Skip duplicate check for non-generic functions (already defined in Pass 2)
      if typeParameters.isEmpty && currentScope.lookup(name) != nil {
        // Already defined in Pass 2, just return nil
        return nil
      }
      
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name, span: span)
      }

      // Create a dummy body for intrinsic representation
      let dummyBody = ExpressionNode.booleanLiteral(false)

      if !typeParameters.isEmpty {
        try withNewScope {
          for param in typeParameters {
            currentScope.defineGenericParameter(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)
          _ = try resolveTypeNode(returnTypeNode)
          _ = try parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return makeLocalSymbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }
        }

        let defId = defIdMap.lookupGenericFunctionTemplateDefId(name)
          ?? defIdMap.allocate(
            modulePath: currentModulePath,
            name: name,
            kind: .genericTemplate(.function),
            sourceFile: currentSourceFile,
            access: access,
            span: currentSpan
          )
        let template = GenericFunctionTemplate(
          defId: defId,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: dummyBody
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
          return makeLocalSymbol(
            name: param.name, type: paramType,
            kind: .variable(param.mutable ? .MutableValue : .Value))
        }
        let funcType = Type.function(
          parameters: params.map { Parameter(type: $0.type, kind: .byVal) }, returns: returnType)
        // Dummy typed body
        let typedBody = TypedExpressionNode.integerLiteral(value: "0", type: .int)
        return (funcType, typedBody, params)
      }
      currentScope.defineFunctionWithModulePath(name, functionType, modulePath: currentModulePath, access: access)
      return nil

    case .givenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span

      // `given Trait { ... }` entity method declaration (supports generic traits)
      if let traitConstraint = try? SemaUtils.resolveTraitConstraint(from: typeNode),
        let traitInfo = traits[traitConstraint.baseName],
        traitInfo.typeParameters.count == typeParams.count {
        return nil
      }

      if !typeParams.isEmpty {
        // Generic Given - signatures were registered in Pass 2 (collectGivenSignatures)
        // Now we only need to check method bodies
        let baseName: String
        switch typeNode {
        case .generic(let base, _):
          baseName = base
        case .pointer:
          baseName = "Ptr"
        default:
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }
        
        // Module rule check: Cannot add given declaration for types defined in external modules (std library)
        if stdLibTypes.contains(baseName) && !isCurrentDeclStdLib {
          throw SemanticError(.generic("Cannot add 'given' declaration for type '\(baseName)' defined in standard library"), span: span)
        }
        
        // Create a generic Self type for body checking
        let genericSelfArgs = typeParams.map { Type.genericParameter(name: $0.name) }
        let genericSelfType: Type
        if baseName == "Ptr" && genericSelfArgs.count == 1 {
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
              currentScope.defineGenericParameter(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(typeParams)
            
            // Register method-level type parameters
            for typeParam in method.typeParameters {
              currentScope.defineGenericParameter(
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
      if case .structure(let defId) = type {
        typeName = context.getName(defId) ?? ""
      } else if case .union(let defId) = type {
        typeName = context.getName(defId) ?? ""
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
        throw SemanticError(.generic("Cannot add 'given' declaration for type '\(typeName)' defined in standard library"), span: span)
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
            currentScope.defineGenericParameter(
              typeParam.name, type: .genericParameter(name: typeParam.name))
          }

          try currentScope.defineType("Self", type: type)
          currentScope.define("self", type, mutable: false)

          let returnType = try resolveTypeNode(method.returnType)
          let params = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return makeLocalSymbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          // Validate __drop signature
          if method.name == "__drop" {
            let firstParamName = params.first.flatMap { context.getName($0.defId) }
            if params.count != 1 || firstParamName != "self" {
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
        let methodSymbol = makeGlobalSymbol(
          name: method.name,  // Use original method name, Monomorphizer will mangle it
          type: methodType,
          kind: .function,
          methodKind: methodKind,
          access: .protected
        )
        registerReceiverStyleMethod(methodSymbol, parameters: method.parameters)

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
            currentScope.defineGenericParameter(
              typeParam.name, type: .genericParameter(name: typeParam.name))
          }
          try recordGenericTraitBounds(info.method.typeParameters)

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
          ))

        if !info.method.typeParameters.isEmpty {
          if genericExtensionMethods[typeName] == nil {
            genericExtensionMethods[typeName] = []
          }

          if let existingIndex = genericExtensionMethods[typeName]!.firstIndex(where: {
            $0.method.name == info.method.name && $0.typeParams.isEmpty
          }) {
            genericExtensionMethods[typeName]![existingIndex] = GenericExtensionMethodTemplate(
              typeParams: [],
              method: info.method,
              checkedBody: typedBody,
              checkedParameters: info.params,
              checkedReturnType: info.returnType
            )
          } else {
            genericExtensionMethods[typeName]!.append(GenericExtensionMethodTemplate(
              typeParams: [],
              method: info.method,
              checkedBody: typedBody,
              checkedParameters: info.params,
              checkedReturnType: info.returnType
            ))
          }
        }
      }

      return .givenDeclaration(type: type, trait: nil, methods: typedMethods)

    case .givenTraitDeclaration(let typeParams, let typeNode, let traitNode, let methods, let span):
      self.currentSpan = span

      let traitConstraint = try SemaUtils.resolveTraitConstraint(from: traitNode)
      let traitName = traitConstraint.baseName
      try validateTraitName(traitName)

      guard let traitInfo = traits[traitName] else {
        throw SemanticError(.generic("Undefined trait: \(traitName)"), span: span)
      }

      let traitArgNodes: [TypeNode] = {
        switch traitConstraint {
        case .simple:
          return []
        case .generic(_, let args):
          return args
        }
      }()
      if traitInfo.typeParameters.count != traitArgNodes.count {
        throw SemanticError.typeMismatch(
          expected: "\(traitInfo.typeParameters.count) generic params",
          got: "\(traitArgNodes.count)"
        )
      }

      let selfType: Type
      let baseNameForGenericStorage: String?
      let typeModulePath: [String]

      if !typeParams.isEmpty {
        let baseName: String
        let args: [TypeNode]
        switch typeNode {
        case .generic(let base, let typeArgs):
          baseName = base
          args = typeArgs
        case .pointer(let inner):
          baseName = "Ptr"
          args = [inner]
        default:
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
              op: "generic given specialization not supported", type1: String(describing: arg), type2: "")
          }
        }

        let genericSelfArgs = typeParams.map { Type.genericParameter(name: $0.name) }
        if baseName == "Ptr" && genericSelfArgs.count == 1 {
          selfType = .pointer(element: genericSelfArgs[0])
        } else if currentScope.lookupGenericStructTemplate(baseName) != nil {
          selfType = .genericStruct(template: baseName, args: genericSelfArgs)
        } else if currentScope.lookupGenericUnionTemplate(baseName) != nil {
          selfType = .genericUnion(template: baseName, args: genericSelfArgs)
        } else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: baseName, type2: "")
        }

        if let template = currentScope.lookupGenericStructTemplate(baseName) {
          typeModulePath = context.getModulePath(template.defId) ?? []
        } else if let template = currentScope.lookupGenericUnionTemplate(baseName) {
          typeModulePath = context.getModulePath(template.defId) ?? []
        } else {
          typeModulePath = currentModulePath
        }
        baseNameForGenericStorage = baseName
      } else {
        selfType = try resolveTypeNode(typeNode)
        switch selfType {
        case .structure(let defId), .union(let defId):
          typeModulePath = context.getModulePath(defId) ?? []
        default:
          typeModulePath = currentModulePath
        }
        baseNameForGenericStorage = nil
      }

      let traitArgTypes = try withNewScope {
        for typeParam in typeParams {
          currentScope.defineGenericParameter(
            typeParam.name, type: .genericParameter(name: typeParam.name))
        }
        try recordGenericTraitBounds(typeParams)
        try currentScope.defineType("Self", type: selfType)
        return try traitArgNodes.map { try resolveTypeNode($0) }
      }

      let makeConformanceKey = { (targetType: Type, targetTrait: String, targetTraitArgs: [Type]) -> ConformanceKey in
        ConformanceKey(
          selfType: self.exactConformanceTypeKey(targetType),
          traitName: targetTrait,
          traitTypeArgs: targetTraitArgs.map { self.exactConformanceTypeKey($0) }
        )
      }

      let conformanceKey = makeConformanceKey(selfType, traitName, traitArgTypes)

      if explicitConformances.contains(conformanceKey) {
        let origin = conformanceDeclOrigins[conformanceKey]
        let originSuffix: String
        if let origin {
          originSuffix = " already declared at line \(origin.start.line)"
        } else {
          originSuffix = " already declared"
        }
        throw SemanticError(.generic(
          "Conflicting conformance: 'given \(selfType) \(traitName)'\(originSuffix)"
        ), span: span)
      }

      // Orphan rule: either type-local or trait-local in current root module.
      let currentRoot = currentModulePath.first
      let typeRoot = typeModulePath.first
      let traitRoot = traitInfo.modulePath.first
      let typeIsLocal = (currentRoot != nil && typeRoot == currentRoot)
      let traitIsLocal = (currentRoot != nil && traitRoot == currentRoot)
      if !typeIsLocal && !traitIsLocal {
        throw SemanticError(.generic(
          "Cannot declare 'given \(selfType) \(traitName)': both type and trait are non-local"
        ), span: span)
      }

      // Require explicit conformance for direct parent traits.
      // Parent conformance can be declared in any file/module/order as long as
      // it exists in the collected environment.
      var traitTypeSubstitution: [String: Type] = [:]
      for (index, traitParam) in traitInfo.typeParameters.enumerated() {
        if index < traitArgTypes.count {
          traitTypeSubstitution[traitParam.name] = traitArgTypes[index]
        }
      }

      for parentConstraint in traitInfo.superTraits {
        let parentTraitName = parentConstraint.baseName
        if SemaUtils.isBuiltinTrait(parentTraitName) {
          continue
        }
        let parentTraitArgTypes: [Type]
        switch parentConstraint {
        case .simple:
          parentTraitArgTypes = []
        case .generic(_, let parentArgNodes):
          parentTraitArgTypes = try parentArgNodes.map {
            try resolveTypeNodeWithSubstitution($0, substitution: traitTypeSubstitution)
          }
        }

        let parentConformanceKey = makeConformanceKey(selfType, parentTraitName, parentTraitArgTypes)
        let hasDeclaredParentConformance = declaredConformances.contains(parentConformanceKey)
        if !hasDeclaredParentConformance {
          throw SemanticError(.generic(
            "Parent trait '\(parentTraitName)' must be explicitly implemented for child trait '\(traitName)'"
          ), span: span)
        }
      }

      // Requirement completeness on this trait's own methods only.
      let ownRequirements = Dictionary(uniqueKeysWithValues: traitInfo.methods.map { ($0.name, $0) })
      for method in methods where ownRequirements[method.name] == nil {
        throw SemanticError(.generic(
          "Implementation 'given \(selfType) \(traitName)' is invalid: extra method \(method.name) is not a requirement"
        ), span: span)
      }
      for (name, requirement) in ownRequirements where !methods.contains(where: { $0.name == name }) {
        let expected = try formatTraitMethodSignature(
          requirement,
          selfType: selfType,
          traitInfo: traitInfo,
          traitTypeArgs: traitArgTypes
        )
        throw SemanticError(.generic(
          "Implementation 'given \(selfType) \(traitName)' is invalid: missing method \(expected)"
        ), span: span)
      }

      struct ImplMethodInfo {
        let method: MethodDeclaration
        let symbol: Symbol
        let parameters: [Symbol]
        let returnType: Type
      }
      var methodInfos: [ImplMethodInfo] = []

      func buildImplMethodInfo(_ method: MethodDeclaration) throws -> (functionType: Type, params: [Symbol], returnType: Type) {
        try withNewScope {
          for outerTypeParam in typeParams {
            currentScope.defineGenericParameter(
              outerTypeParam.name,
              type: .genericParameter(name: outerTypeParam.name)
            )
          }
          try recordGenericTraitBounds(typeParams)

          for (index, traitParam) in traitInfo.typeParameters.enumerated() {
            if index < traitArgTypes.count {
              try currentScope.defineType(traitParam.name, type: traitArgTypes[index])
            }
          }

          for methodTypeParam in method.typeParameters {
            currentScope.defineGenericParameter(
              methodTypeParam.name,
              type: .genericParameter(name: methodTypeParam.name)
            )
          }
          try recordGenericTraitBounds(method.typeParameters)

          try currentScope.defineType("Self", type: selfType)
          currentScope.define("self", selfType, mutable: false)

          let resolvedReturn = try resolveTypeNode(method.returnType)
          let resolvedParams = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return makeLocalSymbol(
              name: param.name,
              type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value)
            )
          }
          let resolvedFunctionType = Type.function(
            parameters: resolvedParams.map { Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind)) },
            returns: resolvedReturn
          )
          return (resolvedFunctionType, resolvedParams, resolvedReturn)
        }
      }

      func buildTraitToolMethodInfo(_ method: MethodDeclaration) throws -> (functionType: Type, params: [Symbol], returnType: Type) {
        try withNewScope {
          for outerTypeParam in typeParams {
            currentScope.defineGenericParameter(
              outerTypeParam.name,
              type: .genericParameter(name: outerTypeParam.name)
            )
          }
          try recordGenericTraitBounds(typeParams)

          for methodTypeParam in method.typeParameters {
            currentScope.defineGenericParameter(
              methodTypeParam.name,
              type: .genericParameter(name: methodTypeParam.name)
            )
          }
          try recordGenericTraitBounds(method.typeParameters)

          try currentScope.defineType("Self", type: selfType)
          currentScope.define("self", selfType, mutable: false)

          var traitTypeSubstitution: [String: Type] = [:]
          for (index, traitParam) in traitInfo.typeParameters.enumerated() {
            if index < traitArgTypes.count {
              traitTypeSubstitution[traitParam.name] = traitArgTypes[index]
            }
          }

          let resolvedReturn = try resolveTypeNodeWithSubstitution(
            method.returnType,
            substitution: traitTypeSubstitution
          )
          let resolvedParams = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNodeWithSubstitution(
              param.type,
              substitution: traitTypeSubstitution
            )
            return makeLocalSymbol(
              name: param.name,
              type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value)
            )
          }
          let resolvedFunctionType = Type.function(
            parameters: resolvedParams.map { Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind)) },
            returns: resolvedReturn
          )
          return (resolvedFunctionType, resolvedParams, resolvedReturn)
        }
      }

      for method in methods {
        guard let requirement = ownRequirements[method.name] else {
          continue
        }

        let (functionType, params, returnType) = try buildImplMethodInfo(method)

        var substitution: [String: Type] = [:]
        for (index, traitParam) in traitInfo.typeParameters.enumerated() {
          if index < traitArgTypes.count {
            substitution[traitParam.name] = traitArgTypes[index]
          }
        }
        let expectedType = try expectedFunctionTypeForGenericTraitMethod(
          requirement,
          selfType: selfType,
          substitution: substitution
        )
        if functionType != expectedType {
          throw SemanticError(.generic(
            "Implementation 'given \(selfType) \(traitName)' is invalid: method \(method.name) has type \(functionType), expected \(expectedType)"
          ), span: span)
        }

        let methodSymbol = makeGlobalSymbol(
          name: method.name,
          type: functionType,
          kind: .function,
          methodKind: getCompilerMethodKind(method.name),
          access: method.access
        )
        registerReceiverStyleMethod(methodSymbol, parameters: method.parameters)

        methodInfos.append(
          ImplMethodInfo(
            method: method,
            symbol: methodSymbol,
            parameters: params,
            returnType: returnType
          )
        )
      }

      // Materialize trait tool methods for this explicit conformance.
      let traitToolMethods = try flattenedTraitToolMethods(traitName)
      for (toolName, toolMethod) in traitToolMethods.sorted(by: { $0.key < $1.key }) {
        // Requirement methods are already handled by implementation methods above.
        if ownRequirements[toolName] != nil {
          continue
        }
        // Respect explicit implementation override if names coincide.
        if methods.contains(where: { $0.name == toolName }) {
          continue
        }
        if methodInfos.contains(where: { $0.method.name == toolName }) {
          continue
        }

        let (functionType, params, returnType) = try buildTraitToolMethodInfo(toolMethod)

        let toolSymbol = makeGlobalSymbol(
          name: toolMethod.name,
          type: functionType,
          kind: .function,
          methodKind: getCompilerMethodKind(toolMethod.name),
          access: toolMethod.access
        )
        registerReceiverStyleMethod(toolSymbol, parameters: toolMethod.parameters)

        methodInfos.append(
          ImplMethodInfo(
            method: toolMethod,
            symbol: toolSymbol,
            parameters: params,
            returnType: returnType
          )
        )
      }

      var typedMethods: [TypedMethodDeclaration] = []
      for info in methodInfos {
        let typedBody = try withNewScope {
          for outerTypeParam in typeParams {
            currentScope.defineGenericParameter(
              outerTypeParam.name,
              type: .genericParameter(name: outerTypeParam.name)
            )
          }
          try recordGenericTraitBounds(typeParams)

          for (index, traitParam) in traitInfo.typeParameters.enumerated() {
            if index < traitArgTypes.count {
              try currentScope.defineType(traitParam.name, type: traitArgTypes[index])
            }
          }
          try currentScope.defineType("Self", type: selfType)

          for methodTypeParam in info.method.typeParameters {
            currentScope.defineGenericParameter(
              methodTypeParam.name,
              type: .genericParameter(name: methodTypeParam.name)
            )
          }
          try recordGenericTraitBounds(info.method.typeParameters)

          for parameter in info.parameters {
            let parameterName = context.getName(parameter.defId) ?? ""
            let mutable: Bool
            switch parameter.kind {
            case .variable(let variableKind):
              mutable = variableKind == .MutableValue
            default:
              mutable = false
            }
            currentScope.define(parameterName, parameter.type, mutable: mutable)
          }

          let (body, _) = try checkFunctionBody(info.parameters, info.returnType, info.method.body)
          return body
        }

        typedMethods.append(
          TypedMethodDeclaration(
            identifier: info.symbol,
            parameters: info.parameters,
            body: typedBody,
            returnType: info.returnType
          )
        )
      }

      explicitConformances.insert(conformanceKey)
      conformanceDeclOrigins[conformanceKey] = span

      if !typeParams.isEmpty {
        guard let baseName = baseNameForGenericStorage else {
          return nil
        }
        if genericExtensionMethods[baseName] == nil {
          genericExtensionMethods[baseName] = []
        }
        for (index, info) in methodInfos.enumerated() {
          genericExtensionMethods[baseName]!.append(
            GenericExtensionMethodTemplate(
              typeParams: typeParams,
              method: info.method,
              checkedBody: typedMethods[index].body,
              checkedParameters: info.parameters,
              checkedReturnType: info.returnType
            )
          )
        }
        return nil
      }

      let concreteTypeName: String
      switch selfType {
      case .structure(let defId), .union(let defId):
        concreteTypeName = context.getName(defId) ?? ""
      case .int, .int8, .int16, .int32, .int64,
           .uint, .uint8, .uint16, .uint32, .uint64,
           .float32, .float64, .bool:
        concreteTypeName = selfType.description
      default:
        throw SemanticError.invalidOperation(
          op: "given Type Trait extends only concrete type",
          type1: selfType.description,
          type2: ""
        )
      }

      if extensionMethods[concreteTypeName] == nil {
        extensionMethods[concreteTypeName] = [:]
      }
      if genericExtensionMethods[concreteTypeName] == nil {
        genericExtensionMethods[concreteTypeName] = []
      }
      for info in methodInfos {
        if !info.method.typeParameters.isEmpty {
          guard let typedMethod = typedMethods.first(where: {
            $0.identifier.defId == info.symbol.defId
          }) else {
            continue
          }

          if let existingIndex = genericExtensionMethods[concreteTypeName]!.firstIndex(where: {
            $0.method.name == info.method.name && $0.typeParams.isEmpty
          }) {
            genericExtensionMethods[concreteTypeName]![existingIndex] = GenericExtensionMethodTemplate(
              typeParams: [],
              method: info.method,
              checkedBody: typedMethod.body,
              checkedParameters: info.parameters,
              checkedReturnType: info.returnType
            )
          } else {
            genericExtensionMethods[concreteTypeName]!.append(
              GenericExtensionMethodTemplate(
                typeParams: [],
                method: info.method,
                checkedBody: typedMethod.body,
                checkedParameters: info.parameters,
                checkedReturnType: info.returnType
              )
            )
          }
          continue
        }

        if let existing = extensionMethods[concreteTypeName]?[info.method.name] {
          if existing.type == info.symbol.type {
            continue
          }
          throw SemanticError(.generic(
            "Duplicate method '\(info.method.name)' in implementation 'given \(selfType) \(traitName)'"
          ), span: span)
        }
        extensionMethods[concreteTypeName]?[info.method.name] = info.symbol
      }

      return .givenDeclaration(
        type: selfType,
        trait: TypedTraitConformance(traitName: traitName, traitTypeArgs: traitArgTypes),
        methods: typedMethods
      )

    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let span):
      self.currentSpan = span
      if !typeParams.isEmpty {
        // Generic Given (Intrinsic)
        let baseName: String
        let args: [TypeNode]
        switch typeNode {
        case .generic(let name, let typeArgs):
          baseName = name
          args = typeArgs
        case .pointer(let inner):
          baseName = "Ptr"
          args = [inner]
        default:
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
      case .structure(let defId):
        typeName = context.getName(defId) ?? ""
        shouldEmitGiven = true
      case .union(let defId):
        typeName = context.getName(defId) ?? ""
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
            return makeLocalSymbol(
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
        let methodSymbol = makeGlobalSymbol(
          name: method.name,  // Use original method name, Monomorphizer will mangle it
          type: methodType,
          kind: .function,
          methodKind: methodKind,
          access: .protected
        )
        registerReceiverStyleMethod(methodSymbol, parameters: method.parameters)

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

      return shouldEmitGiven ? .givenDeclaration(type: type, trait: nil, methods: typedMethods) : nil

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
            currentScope.defineGenericParameter(param.name, type: .genericParameter(name: param.name))
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
        return makeLocalSymbol(
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
          let defId = getOrAllocateTypeDefId(
            name: name,
            kind: .structure,
            access: access,
            modulePath: currentModulePath,
            sourceFile: currentSourceFile
          )
          type = .structure(defId: defId)
        }
        let dummySymbol = makeGlobalSymbol(name: name, type: type, kind: .variable(.Value), access: access)
        return .globalStructDeclaration(identifier: dummySymbol, parameters: [])
      } else {
        // Generic intrinsic template was already registered in Pass 1
        // intrinsicGenericTypes was also already populated in Pass 1
        return .genericTypeTemplate(name: name)
      }

    case .typeAliasDeclaration:
      // Type aliases are fully resolved in pass 2 (collectTypeDefinition)
      // No TypedGlobalNode is generated for them
      return nil
    }
  }
  
  // MARK: - NameCollector Integration
  
  /// Runs the NameCollector (Pass 1) to collect all type and function definitions.
  ///
  /// This method creates the necessary input for NameCollector from the TypeChecker's
  /// current state and runs the pass. The output contains:
  /// - DefIdMap: Unique identifiers for all definitions
  /// - ModuleResolverOutput: Preserved from input
  ///
  /// **Validates: Requirements 2.1, 2.2**
  ///
  /// - Parameters:
  ///   - allNodes: All global nodes including using declarations
  ///   - declarations: Filtered global nodes (excluding using declarations)
  /// - Returns: The NameCollector output
  /// - Throws: SemanticError if duplicate definitions are found
  private func runNameCollector(allNodes: [GlobalNode], declarations: [GlobalNode]) throws -> NameCollectorOutput {
    // Create ModuleResolverOutput from current state
    let moduleResolverOutput = createModuleResolverOutput(allNodes: allNodes)
    
    // Create NameCollector input
    let input = NameCollectorInput(moduleResolverOutput: moduleResolverOutput)
    
    // Create and run NameCollector
    let nameCollector = NameCollector(coreGlobalCount: coreGlobalCount, checker: self)
    let output = try nameCollector.run(input: input)
    
    return output
  }
  
  /// Creates a ModuleResolverOutput from the TypeChecker's current state.
  ///
  /// This method bridges the gap between the existing TypeChecker state and
  /// the new Pass architecture by creating the expected input format for NameCollector.
  ///
  /// - Parameter allNodes: All global nodes
  /// - Returns: A ModuleResolverOutput suitable for NameCollector
  private func createModuleResolverOutput(allNodes: [GlobalNode]) -> ModuleResolverOutput {
    // Create a basic ModuleTree from the nodeSourceInfoMap
    let rootModulePath: [String]
    if let firstUserSourceInfo = nodeSourceInfoMap.values.first(where: { info in
      // Find the first non-stdlib source info
      let index = nodeSourceInfoMap.first(where: { $0.value.sourceFile == info.sourceFile })?.key ?? 0
      return index >= coreGlobalCount
    }) {
      rootModulePath = firstUserSourceInfo.modulePath.isEmpty ? [] : [firstUserSourceInfo.modulePath[0]]
    } else {
      rootModulePath = []
    }
    
    // Create root module info
    let rootModule = ModuleInfo(
      path: rootModulePath,
      entryFile: userFileName
    )
    
    // Collect all loaded modules
    var loadedModules: [String: ModuleInfo] = [:]
    for (_, sourceInfo) in nodeSourceInfoMap {
      let moduleKey = sourceInfo.modulePath.joined(separator: ".")
      if !moduleKey.isEmpty && loadedModules[moduleKey] == nil {
        loadedModules[moduleKey] = ModuleInfo(
          path: sourceInfo.modulePath,
          entryFile: sourceInfo.sourceFile
        )
      }
    }
    
    let moduleTree = ModuleTree(
      rootModule: rootModule,
      loadedModules: loadedModules
    )
    
    // Create node source info list from the map
    var nodeSourceInfoList: [GlobalNodeSourceInfo] = []
    for (index, node) in allNodes.enumerated() {
      if let sourceInfo = nodeSourceInfoMap[index] {
        nodeSourceInfoList.append(sourceInfo)
      } else {
        // Create a default source info for nodes without explicit mapping
        let isStdLib = index < coreGlobalCount
        nodeSourceInfoList.append(GlobalNodeSourceInfo(
          sourceFile: isStdLib ? coreFileName : userFileName,
          modulePath: [],
          node: node
        ))
      }
    }
    
    return ModuleResolverOutput(
      moduleTree: moduleTree,
      importGraph: ImportGraph(),
      astNodes: allNodes,
      nodeSourceInfoList: nodeSourceInfoList
    )
  }
  
  // MARK: - Pass 2: TypeResolver Integration
  
  /// Runs the TypeResolver pass to resolve type signatures.
  ///
  /// TypeResolver is the new Pass 2 implementation that:
  /// - Resolves type members and function signatures
  /// - Builds complete type information
  /// - Registers given method signatures
  /// - Builds module symbols (merged Pass 2.5 functionality)
  ///
  /// The output contains:
  /// - DefIdMap: DefId to type information mappings
  /// - NameCollectorOutput: Preserved from input
  ///
  /// **Validates: Requirements 2.1, 2.2**
  ///
  /// - Parameter nameCollectorOutput: The output from NameCollector (Pass 1)
  /// - Returns: The TypeResolver output
  /// - Throws: SemanticError if type resolution fails
  private func runTypeResolver(nameCollectorOutput: NameCollectorOutput) throws -> TypeResolverOutput {
    // Create TypeResolver input
    let input = TypeResolverInput(nameCollectorOutput: nameCollectorOutput)
    
    // Create and run TypeResolver
    let typeResolver = TypeResolver(coreGlobalCount: coreGlobalCount, checker: self, context: context)
    let output = try typeResolver.run(input: input)
    
    // === Recursive Type Check ===
    // After type resolution, check for indirect recursion in struct/union types
    let recursiveChecker = RecursiveTypeChecker(context: context)
    let cycles = try recursiveChecker.check()
    
    // Report any detected cycles as errors
    for cycle in cycles {
      let pathString = cycle.pathString()
      let error = SemanticError(.indirectRecursion(path: pathString))
      try handleError(error)
    }
    
    return output
  }
  
  // MARK: - Pass 3: BodyChecker Integration
  
  /// Runs the BodyChecker pass to check function bodies and expressions.
  ///
  /// BodyChecker is the new Pass 3 implementation that:
  /// - Checks function bodies and expressions
  /// - Performs type inference
  /// - Generates typed AST
  /// - Collects generic instantiation requests
  ///
  /// The output contains:
  /// - TypedAST: The type-checked AST
  /// - InstantiationRequests: Generic instantiation requests
  /// - TypeResolverOutput: Preserved from input
  ///
  /// **Validates: Requirements 2.1, 2.2**
  ///
  /// - Parameter typeResolverOutput: The output from TypeResolver (Pass 2)
  /// - Returns: The BodyChecker output
  /// - Throws: SemanticError if type checking fails
  private func runBodyChecker(typeResolverOutput: TypeResolverOutput) throws -> BodyCheckerOutput {
    // Create BodyChecker input
    let input = BodyCheckerInput(typeResolverOutput: typeResolverOutput)
    
    // Create and run BodyChecker
    let bodyChecker = BodyChecker(checker: self, coreGlobalCount: coreGlobalCount)
    let output = try bodyChecker.run(input: input)
    
    return output
  }
}

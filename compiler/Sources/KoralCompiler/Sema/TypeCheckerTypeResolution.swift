import Foundation

// MARK: - Type Resolution Extension
// This extension contains methods for resolving TypeNode to Type,
// type coercion, and type checking utilities.

extension TypeChecker {

  private func resolveModuleInfo(for moduleName: String) throws -> ModuleSymbolInfo {
    if let moduleDefId = currentScope.lookup(moduleName, sourceFile: currentSourceFile),
       let moduleType = defIdMap.getSymbolType(moduleDefId),
       case .module(let moduleInfo) = moduleType {
      if !isModuleSymbolImported(moduleInfo.modulePath, symbolName: moduleName) {
        throw SemanticError(.generic("Module '\(moduleName)' is not imported"), span: currentSpan)
      }
      return moduleInfo
    }

    if let importGraph,
       let aliasedModulePath = importGraph.resolveAliasedModule(
        alias: moduleName,
        inModule: currentModulePath,
        inSourceFile: currentSourceFile
       ) {
      let moduleKey = aliasedModulePath.joined(separator: ".")
      if let info = moduleSymbols[moduleKey] {
        return info
      }
      return ModuleSymbolInfo(modulePath: aliasedModulePath, publicSymbols: [:], publicTypes: [:])
    }

    throw SemanticError.undefinedVariable(moduleName)
  }

  private func modulePath(of type: Type) -> [String]? {
    switch type {
    case .structure(let defId), .union(let defId), .opaque(let defId):
      return context.getModulePath(defId)
    default:
      return nil
    }
  }

  private func ensureTypeBelongsToModule(
    _ typeName: String,
    moduleName: String,
    expectedModulePath: [String],
    resolvedType: Type
  ) throws {
    guard let ownerPath = modulePath(of: resolvedType), ownerPath == expectedModulePath else {
      throw SemanticError(
        .generic("Type '\(typeName)' does not belong to module '\(moduleName)'"),
        span: currentSpan
      )
    }
  }

  private func ensureTemplateBelongsToModule(
    _ templateName: String,
    moduleName: String,
    expectedModulePath: [String],
    templateDefId: DefId
  ) throws {
    let ownerPath = defIdMap.getModulePath(templateDefId) ?? []
    guard ownerPath == expectedModulePath else {
      throw SemanticError(
        .generic("Type '\(templateName)' does not belong to module '\(moduleName)'"),
        span: currentSpan
      )
    }

    let access = defIdMap.getAccess(templateDefId) ?? .protected
    if access == .private {
      throw SemanticError(
        .generic("Type '\(templateName)' is not a public type of module '\(moduleName)'"),
        span: currentSpan
      )
    }
  }
  
  // MARK: - Core Type Resolution
  
  /// 将 TypeNode 解析为语义层 Type，支持函数参数/返回位置的一层 reference(T)
  func resolveTypeNode(_ node: TypeNode) throws -> Type {
    switch node {
    case .identifier(let name):
      if let t = currentScope.resolveType(name, sourceFile: currentSourceFile) {
        // 检查类型的模块可见性
        try checkTypeVisibility(type: t, typeName: name)
        return t
      }
      if traits[name] != nil {
        throw SemanticError.invalidOperation(op: "use trait as type", type1: name, type2: "")
      }
      throw SemanticError.undefinedType(name)
    case .inferredSelf:
      guard let t = currentScope.resolveType("Self") else {
        throw SemanticError.undefinedType("Self")
      }
      return t
    case .reference(let inner):
      // Check if inner is a trait name → trait object reference
      if case .identifier(let name) = inner, traits[name] != nil {
        let (safe, reasons) = try checkObjectSafety(name)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(name)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        return .reference(inner: .traitObject(traitName: name, typeArgs: []))
      }
      // Check if inner is a generic trait → [Args]TraitName ref
      if case .generic(let base, let args) = inner, traits[base] != nil {
        let (safe, reasons) = try checkObjectSafety(base)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(base)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        return .reference(inner: .traitObject(traitName: base, typeArgs: resolvedArgs))
      }
      let base = try resolveTypeNode(inner)
      return .reference(inner: base)
    case .pointer(let inner):
      let base = try resolveTypeNode(inner)
      return .pointer(element: base)
    case .generic(let base, let args):
      if let template = currentScope.lookupGenericStructTemplate(base) {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic arguments",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        if !deferGenericConstraintValidation {
          try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        }
        
        // Build recursion detection key
        let recursionKey = "\(base)<\(resolvedArgs.map { $0.description }.joined(separator: ","))>"
        
        // Check for recursion - if we're already resolving this type, return parameterized type
        // This allows recursive types through ref (e.g., type [T]Node(value T, next ref [T]Node))
        if resolvingGenericTypes.contains(recursionKey) {
          return .genericStruct(template: base, args: resolvedArgs)
        }
        
        // Record instantiation request for deferred monomorphization
        // Skip if any argument contains generic parameters (will be recorded when fully resolved)
        if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .structType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Return parameterized type instead of instantiating
        return .genericStruct(template: base, args: resolvedArgs)
      } else if let template = currentScope.lookupGenericUnionTemplate(base) {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic types",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        if !deferGenericConstraintValidation {
          try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        }
        
        // Build recursion detection key
        let recursionKey = "\(base)<\(resolvedArgs.map { $0.description }.joined(separator: ","))>"
        
        // Check for recursion - if we're already resolving this type, return parameterized type
        // This allows recursive types through ref
        if resolvingGenericTypes.contains(recursionKey) {
          return .genericUnion(template: base, args: resolvedArgs)
        }
        
        // Record instantiation request for deferred monomorphization
        // Skip if any argument contains generic parameters (will be recorded when fully resolved)
        if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .unionType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Return parameterized type instead of instantiating
        return .genericUnion(template: base, args: resolvedArgs)
      } else {
        throw SemanticError.undefinedType(base)
      }
    case .functionType(let paramTypes, let returnType):
      // Resolve function type: [ParamType1, ParamType2, ..., ReturnType]Func
      let resolvedParamTypes = try paramTypes.map { try resolveTypeNode($0) }
      let resolvedReturnType = try resolveTypeNode(returnType)
      let parameters = resolvedParamTypes.map { Parameter(type: $0, kind: .byVal) }
      return .function(parameters: parameters, returns: resolvedReturnType)
      
    case .moduleQualified(let moduleName, let typeName):
      // 模块限定类型：module.TypeName
      let moduleInfo = try resolveModuleInfo(for: moduleName)
      
      // 首先尝试从模块的公开类型中查找（Pass 2.5 之后可用）
      if let type = moduleInfo.publicTypes[typeName] {
        return type
      }
      
      // 如果模块的公开类型中没有，尝试从全局 scope 中查找
      // 这是为了支持 Pass 2 中的类型解析（此时模块符号还没有完全构建）
      if let type = currentScope.lookupType(typeName) {
        try ensureTypeBelongsToModule(
          typeName,
          moduleName: moduleName,
          expectedModulePath: moduleInfo.modulePath,
          resolvedType: type
        )
        return type
      }
      
      throw SemanticError(
        .generic("Type '\(typeName)' is not a public type of module '\(moduleName)'"),
        span: currentSpan
      )
      
    case .moduleQualifiedGeneric(let moduleName, let baseName, let args):
      // 模块限定泛型类型：module.[T]List
      let moduleInfo = try resolveModuleInfo(for: moduleName)
      
      // 查找泛型模板（泛型模板是全局注册的）
      if let template = currentScope.lookupGenericStructTemplate(baseName) {
        try ensureTemplateBelongsToModule(
          baseName,
          moduleName: moduleName,
          expectedModulePath: moduleInfo.modulePath,
          templateDefId: template.defId
        )

        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic arguments",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        if !deferGenericConstraintValidation {
          try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        }
        
        // Record instantiation request for deferred monomorphization
        if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .structType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        return .genericStruct(template: baseName, args: resolvedArgs)
      } else if let template = currentScope.lookupGenericUnionTemplate(baseName) {
        try ensureTemplateBelongsToModule(
          baseName,
          moduleName: moduleName,
          expectedModulePath: moduleInfo.modulePath,
          templateDefId: template.defId
        )

        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic types",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        if !deferGenericConstraintValidation {
          try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        }
        
        // Record instantiation request for deferred monomorphization
        if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .unionType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        return .genericUnion(template: baseName, args: resolvedArgs)
      } else {
        throw SemanticError(
          .generic("Type '\(baseName)' is not a public type of module '\(moduleName)'"),
          span: currentSpan
        )
      }
      
    case .weakReference(let inner):
      // Check if inner is a trait name → trait object weakref
      if case .identifier(let name) = inner, traits[name] != nil {
        let (safe, reasons) = try checkObjectSafety(name)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(name)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        return .weakReference(inner: .traitObject(traitName: name, typeArgs: []))
      }
      if case .generic(let base, let args) = inner, traits[base] != nil {
        let (safe, reasons) = try checkObjectSafety(base)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(base)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        return .weakReference(inner: .traitObject(traitName: base, typeArgs: resolvedArgs))
      }
      let base = try resolveTypeNode(inner)
      return .weakReference(inner: base)
    }
  }
  
  /// Resolves a TypeNode to a Type using the given substitution map for type parameters.
  func resolveTypeNodeWithSubstitution(_ node: TypeNode, substitution: [String: Type]) throws -> Type {
    switch node {
    case .identifier(let name):
      // Check if it's a type parameter that should be substituted
      if let substitutedType = substitution[name] {
        return substitutedType
      }
      // Otherwise resolve as a regular type
      return try resolveTypeNode(node)
      
    case .reference(let inner):
      // Check if inner is a trait name → trait object reference
      if case .identifier(let name) = inner, traits[name] != nil {
        let (safe, reasons) = try checkObjectSafety(name)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(name)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        return .reference(inner: .traitObject(traitName: name, typeArgs: []))
      }
      if case .generic(let base, let args) = inner, traits[base] != nil {
        let (safe, reasons) = try checkObjectSafety(base)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(base)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        let resolvedArgs = try args.map { try resolveTypeNodeWithSubstitution($0, substitution: substitution) }
        return .reference(inner: .traitObject(traitName: base, typeArgs: resolvedArgs))
      }
      let base = try resolveTypeNodeWithSubstitution(inner, substitution: substitution)
      return .reference(inner: base)

    case .pointer(let inner):
      let base = try resolveTypeNodeWithSubstitution(inner, substitution: substitution)
      return .pointer(element: base)
      
    case .generic(let base, let args):
      let resolvedArgs = try args.map { try resolveTypeNodeWithSubstitution($0, substitution: substitution) }
      
      if currentScope.lookupGenericStructTemplate(base) != nil {
        return .genericStruct(template: base, args: resolvedArgs)
      }
      if currentScope.lookupGenericUnionTemplate(base) != nil {
        return .genericUnion(template: base, args: resolvedArgs)
      }
      
      // Conservative default to generic struct if template is unresolved (diagnosed later)
      return .genericStruct(template: base, args: resolvedArgs)
      
    case .functionType(let paramTypes, let returnType):
      let resolvedParamTypes = try paramTypes.map { try resolveTypeNodeWithSubstitution($0, substitution: substitution) }
      let resolvedReturnType = try resolveTypeNodeWithSubstitution(returnType, substitution: substitution)
      let parameters = resolvedParamTypes.map { Parameter(type: $0, kind: .byVal) }
      return .function(parameters: parameters, returns: resolvedReturnType)
      
    case .moduleQualified(let moduleName, let typeName):
      _ = moduleName
      // If substitution has an override for the simple name, use it
      if let substitutedType = substitution[typeName] {
        return substitutedType
      }
      return try resolveTypeNode(node)
      
    case .moduleQualifiedGeneric(let moduleName, let baseName, let args):
      _ = moduleName
      let resolvedArgs = try args.map { try resolveTypeNodeWithSubstitution($0, substitution: substitution) }
      
      // Try to resolve against templates (module visibility is checked in resolveTypeNode)
      if currentScope.lookupGenericStructTemplate(baseName) != nil {
        return .genericStruct(template: baseName, args: resolvedArgs)
      }
      if currentScope.lookupGenericUnionTemplate(baseName) != nil {
        return .genericUnion(template: baseName, args: resolvedArgs)
      }
      
      // Defer to regular resolution to surface canonical diagnostics
      return try resolveTypeNode(node)
      
    case .inferredSelf:
      if let substitutedType = substitution["Self"] {
        return substitutedType
      }
      return try resolveTypeNode(node)
      
    case .weakReference(let inner):
      if case .identifier(let name) = inner, traits[name] != nil {
        let (safe, reasons) = try checkObjectSafety(name)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(name)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        return .weakReference(inner: .traitObject(traitName: name, typeArgs: []))
      }
      if case .generic(let base, let args) = inner, traits[base] != nil {
        let (safe, reasons) = try checkObjectSafety(base)
        if !safe {
          throw SemanticError(.generic(
            "Trait '\(base)' is not object-safe: \(reasons.joined(separator: "; "))"
          ), span: currentSpan)
        }
        let resolvedArgs = try args.map { try resolveTypeNodeWithSubstitution($0, substitution: substitution) }
        return .weakReference(inner: .traitObject(traitName: base, typeArgs: resolvedArgs))
      }
      let base = try resolveTypeNodeWithSubstitution(inner, substitution: substitution)
      return .weakReference(inner: base)
    }
  }
  
  // MARK: - Generic Constraint Enforcement
  
  // Cache for validated generic constraint checks: "Template<Arg1,Arg2>" -> passed
  // (Stored in TypeChecker class, accessed from extension)
  
  func enforceGenericConstraints(typeParameters: [TypeParameterDecl], args: [Type]) throws {
    guard typeParameters.count == args.count else { return }
    
    // Skip if all args are generic parameters (constraints checked at instantiation site)
    let allGeneric = args.allSatisfy { if case .genericParameter = $0 { return true }; return false }
    if allGeneric { return }
    
    // Cache check: include full constraint signatures to avoid collisions between
    // templates that share type parameter names but have different trait bounds.
    let paramKey = typeParameters.map { param in
      let constraintsKey = param.constraints.map { $0.description }.joined(separator: "&")
      return "\(param.name):\(constraintsKey)"
    }.joined(separator: ",")
    let argsKey = args.map { $0.description }.joined(separator: ",")
    let cacheKey = "\(paramKey)<\(argsKey)>"
    if genericConstraintCache.contains(cacheKey) { return }
    
    // Build a substitution map from type parameter names to actual types
    var substitution: [String: Type] = [:]
    for (i, param) in typeParameters.enumerated() {
      substitution[param.name] = args[i]
    }
    
    for (i, param) in typeParameters.enumerated() {
      for c in param.constraints {
        let constraint = try SemaUtils.resolveTraitConstraint(from: c)
        
        switch constraint {
        case .simple(let traitName):
          // Simple trait constraint (e.g., T Any, T Equatable)
          // If the argument is a generic parameter, check if it has the required constraint
          // in its bounds rather than checking for concrete method implementations
          if case .genericParameter(let argName) = args[i] {
            // Check if the generic parameter has the required trait bound
            if let bounds = genericTraitBounds[argName] {
              if traitName != "Any" && !bounds.contains(where: { $0.baseName == traitName }) {
                throw SemanticError(.generic(
                  "Generic parameter \(argName) does not have required constraint \(traitName)"
                ), span: currentSpan)
              }
            }
            // If bounds exist and contain the trait (or trait is Any), constraint is satisfied
            continue
          }
          
          let ctx = "checking constraint \(param.name): \(traitName)"
          try enforceTraitConformance(args[i], traitName: traitName, context: ctx)
          
        case .generic(let baseTrait, let traitArgs):
          // Generic trait constraint (e.g., R [T]Iterator)
          // We need to check that the actual type implements the trait with the correct type arguments
          
          // First, substitute type parameters in the trait arguments
          let resolvedTraitArgs = try traitArgs.map { arg -> Type in
            try resolveTypeNodeWithSubstitution(arg, substitution: substitution)
          }
          
          // If the argument is a generic parameter, check if it has a matching generic trait bound
          if case .genericParameter(let argName) = args[i] {
            // For now, check if the generic parameter has the base trait bound
            // A more sophisticated check would verify the type arguments match
            if let bounds = genericTraitBounds[argName] {
              if !bounds.contains(where: { $0.baseName == baseTrait }) {
                throw SemanticError(.generic(
                  "Generic parameter \(argName) does not have required constraint \(constraint)"
                ), span: currentSpan)
              }
            }
            continue
          }
          
          // For concrete types, check trait conformance with the resolved type arguments
          let ctx = "checking constraint \(param.name): \(constraint)"
          try enforceGenericTraitConformance(args[i], traitName: baseTrait, traitTypeArgs: resolvedTraitArgs, context: ctx)
        }
      }
    }
    
    // Cache successful constraint check
    genericConstraintCache.insert(cacheKey)
  }
  
  // MARK: - Trait Conformance
  
  func enforceTraitConformance(
    _ selfType: Type,
    traitName: String,
    context: String? = nil
  ) throws {
    if traitName == "Any" {
      return
    }

    if traitName == "Deref" {
      // trait object does not satisfy Deref
      if case .traitObject = selfType {
        throw SemanticError(.generic(
          "Trait object type '\(selfType)' does not satisfy 'Deref' constraint"
        ), span: currentSpan)
      }
      // opaque type does not satisfy Deref
      if case .opaque = selfType {
        throw SemanticError(.generic(
          "Opaque type '\(selfType)' does not satisfy 'Deref' constraint"
        ), span: currentSpan)
      }
      return  // All other types automatically satisfy Deref
    }

    // trait object self-conformance: traitObject("X") satisfies X bound
    if case .traitObject(let toTraitName, _) = selfType {
      if toTraitName == traitName {
        // traitObject("ToString") satisfies ToString bound
        return
      }
      // Different traits don't satisfy each other (no upcasting in initial version)
      throw SemanticError(.generic(
        "Trait object type '\(selfType)' does not satisfy '\(traitName)' constraint"
      ), span: currentSpan)
    }

    // Check cache: skip redundant conformance checks for the same type/trait pair
    let cacheKey = "\(selfType):\(traitName)"
    if let passed = traitConformanceCache[cacheKey] {
      if passed { return }
      // If previously failed, fall through to generate proper error message
    }

    try validateTraitName(traitName)
    if !hasNominalConformance(selfType: selfType, traitName: traitName, traitTypeArgs: []) {
      traitConformanceCache[cacheKey] = false
      var msg = "Type \(selfType) does not explicitly implement trait \(traitName)"
      if let context {
        msg += " (\(context))"
      }
      throw SemanticError(.generic(msg), span: currentSpan)
    }
    
    // Cache successful conformance check
    traitConformanceCache[cacheKey] = true
  }
  
  /// Checks if a type conforms to a generic trait with specific type arguments.
  /// For example, checking if ListIterator conforms to [Int]Iterator.
  /// - Parameters:
  ///   - selfType: The type to check
  ///   - traitName: The trait name (e.g., "Iterator")
  ///   - traitTypeArgs: The type arguments for the trait (e.g., [Int] for [Int]Iterator)
  ///   - context: Optional context string for error messages
  func enforceGenericTraitConformance(
    _ selfType: Type,
    traitName: String,
    traitTypeArgs: [Type],
    context: String? = nil
  ) throws {
    if traitName == "Any" {
      return
    }

    // Check cache for generic trait conformance
    let argsKey = traitTypeArgs.map { $0.description }.joined(separator: ",")
    let cacheKey = "\(selfType):[\(argsKey)]\(traitName)"
    if let passed = traitConformanceCache[cacheKey] {
      if passed { return }
    }

    try validateTraitName(traitName)
    
    guard let traitInfo = traits[traitName] else {
      throw SemanticError(.generic("Undefined trait: \(traitName)"), span: currentSpan)
    }
    
    // Validate type argument count
    guard traitInfo.typeParameters.count == traitTypeArgs.count else {
      throw SemanticError(.generic(
        "Trait \(traitName) expects \(traitInfo.typeParameters.count) type arguments, got \(traitTypeArgs.count)"
      ), span: currentSpan)
    }
    
    // Create type substitution map from trait type parameters to concrete types
    var substitution: [String: Type] = [:]
    for (i, param) in traitInfo.typeParameters.enumerated() {
      substitution[param.name] = traitTypeArgs[i]
    }
    
    _ = substitution

    if !hasNominalConformance(selfType: selfType, traitName: traitName, traitTypeArgs: traitTypeArgs) {
      let argsStr = traitTypeArgs.map { $0.description }.joined(separator: ", ")
      var msg = "Type \(selfType) does not explicitly implement trait [\(argsStr)]\(traitName)"
      if let context {
        msg += " (\(context))"
      }
      throw SemanticError(.generic(msg), span: currentSpan)
    }
    
    // Cache successful conformance check
    traitConformanceCache[cacheKey] = true
  }

  /// Computes the expected function type for a generic trait method with type substitution.
  func expectedFunctionTypeForGenericTraitMethod(
    _ method: TraitMethodSignature,
    selfType: Type,
    substitution: [String: Type]
  ) throws -> Type {
    return try withNewScope {
      // Bind Self type
      try currentScope.defineType("Self", type: selfType)
      
      // Bind trait type parameters
      for (name, type) in substitution {
        try currentScope.defineType(name, type: type)
      }
      
      // Bind method-level type parameters as generic parameters
      for typeParam in method.typeParameters {
        currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
      }

      let params: [Parameter] = try method.parameters.map { param in
        let t = try resolveTypeNode(param.type)
        return Parameter(type: t, kind: .byVal)
      }
      let ret = try resolveTypeNode(method.returnType)
      return Type.function(parameters: params, returns: ret)
    }
  }

  /// Formats a generic trait method signature with type substitution for error messages.
  func formatGenericTraitMethodSignature(
    _ method: TraitMethodSignature,
    selfType: Type,
    substitution: [String: Type]
  ) throws -> String {
    return try withNewScope {
      try currentScope.defineType("Self", type: selfType)
      
      for (name, type) in substitution {
        try currentScope.defineType(name, type: type)
      }
      
      // Bind method-level type parameters as generic parameters
      for typeParam in method.typeParameters {
        currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
      }

      let paramsDesc = try method.parameters.map { param -> String in
        let resolvedType = try resolveTypeNode(param.type)
        let mutPrefix = param.mutable ? "mut " : ""
        return "\(mutPrefix)\(param.name) \(resolvedType)"
      }.joined(separator: ", ")

      let ret = try resolveTypeNode(method.returnType)
      return "\(method.name)(\(paramsDesc)) \(ret)"
    }
  }
  
  // MARK: - Type Checking Utilities
  
  func isIntegerType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  func isFloatType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64:
      return true
    default:
      return false
    }
  }

  func isStringType(_ type: Type) -> Bool {
    switch type {
    case .structure(let defId):
      return context.getName(defId) == "String"
    default:
      return false
    }
  }
  
  func singleByteASCII(from value: String) -> UInt8? {
    let bytes = Array(value.utf8)
    guard bytes.count == 1 else { return nil }
    guard bytes[0] <= 0x7F else { return nil }
    return bytes[0]
  }
  
  /// Extract a single Unicode code point from a string literal.
  /// Returns nil if the string contains zero or more than one code point.
  func singleRuneCodePoint(from value: String) -> UInt32? {
    var iterator = value.unicodeScalars.makeIterator()
    guard let scalar = iterator.next() else { return nil }
    guard iterator.next() == nil else { return nil }  // Ensure only one code point
    return scalar.value
  }
  
  /// Check if a type is the Rune struct type.
  func isRuneType(_ type: Type) -> Bool {
    if case .structure(let defId) = type {
      return context.getName(defId) == "Rune"
    }
    return false
  }

  // Coerce numeric literals to the expected numeric type for annotations/parameters.
  func coerceLiteral(_ expr: TypedExpressionNode, to expected: Type) throws -> TypedExpressionNode
  {
    if case .pointer = expected,
       case .intrinsicCall(.nullPtr) = expr {
      return .intrinsicCall(.nullPtr(resultType: expected))
    }

    if isIntegerType(expected) {
      if case .integerLiteral(let value, _) = expr {
        return .integerLiteral(value: value, type: expected)
      }

      // Allow "a" / 'a' (post-escape, single-byte ASCII) to coerce to UInt8.
      if expected == .uint8, case .stringLiteral(let value, _) = expr {
        if let b = singleByteASCII(from: value) {
          return .integerLiteral(value: String(b), type: .uint8)
        }
      }
    }
    if isFloatType(expected) {
      if case .floatLiteral(let value, _) = expr {
        return .floatLiteral(value: value, type: expected)
      }
    }
    
    // Allow single-character string literal to coerce to Rune type.
    // e.g., 'A' -> Rune(65), '中' -> Rune(20013)
    if isRuneType(expected), case .stringLiteral(let value, _) = expr {
      if let cp = singleRuneCodePoint(from: value) {
        // Construct Rune(value) using typeConstruction
        // We need to get the Rune type's symbol
        if case .structure(let defId) = expected {
          let name = context.getName(defId) ?? "Rune"
          let runeSymbol = makeLocalSymbol(name: name, type: expected, kind: .type)
          return .typeConstruction(
            identifier: runeSymbol,
            typeArgs: nil,
            arguments: [.integerLiteral(value: String(cp), type: .uint32)],
            type: expected
          )
        }
      }
      // Check if it's a multi-code-point string and provide better error message
      let codePointCount = value.unicodeScalars.count
      if codePointCount > 1 {
        throw SemanticError(.generic("Rune literal must contain exactly one Unicode code point, but '\(value)' contains \(codePointCount)"))
      }
      // Empty string case
      if codePointCount == 0 {
        throw SemanticError(.generic("Rune literal cannot be empty"))
      }
    }
    
    // Try trait object conversion if types still don't match
    if expr.type != expected {
      return try tryTraitObjectConversion(expr, to: expected)
    }
    
    return expr
  }

  /// Attempts to wrap an expression in a traitObjectConversion if the target type is a trait object reference
  /// and the source type is a compatible concrete type.
  /// Returns the original expression unchanged if no conversion is needed.
  func tryTraitObjectConversion(_ expr: TypedExpressionNode, to expected: Type) throws -> TypedExpressionNode {
    // Extract trait object info from expected type
    let traitName: String
    let traitTypeArgs: [Type]
    switch expected {
    case .reference(let inner):
      if case .traitObject(let name, let args) = inner {
        traitName = name
        traitTypeArgs = args
      } else {
        return expr
      }
    case .weakReference(let inner):
      if case .traitObject(let name, let args) = inner {
        traitName = name
        traitTypeArgs = args
      } else {
        return expr
      }
    default:
      return expr
    }

    // Already a matching trait object — no conversion needed
    if expr.type == expected {
      return expr
    }

    // Get the concrete type from the source — only T ref can convert to trait object
    let concreteType: Type
    switch expr.type {
    case .reference(let inner):
      if case .traitObject = inner { return expr } // trait object → trait object: not supported
      concreteType = inner
    default:
      // Value types cannot be directly converted to trait object — must use T ref
      return expr
    }

    // Check trait conformance (with type args if generic trait)
    if traitTypeArgs.isEmpty {
      try enforceTraitConformance(concreteType, traitName: traitName)
    } else {
      try enforceGenericTraitConformance(concreteType, traitName: traitName, traitTypeArgs: traitTypeArgs, context: nil)
    }

    return .traitObjectConversion(
      inner: expr,
      traitName: traitName,
      traitTypeArgs: traitTypeArgs,
      concreteType: concreteType,
      type: expected
    )
  }
}

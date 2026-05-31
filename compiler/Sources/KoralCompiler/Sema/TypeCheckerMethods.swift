import Foundation

// MARK: - Method Lookup and Call Handling Extension
// This extension contains methods for resolving methods and handling intrinsic calls.

extension TypeChecker {
  private func lookupConcreteMethodSymbolDirect(on selfType: Type, name: String) throws -> Symbol? {
    switch selfType {
    case .reference(let inner):
      // New: look up Ref generic extension methods first
      if let extensions = genericExtensionMethods["Ref"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "Ref",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      // If not found on Ref, continue auto-deref to inner type
      return try lookupConcreteMethodSymbolDirect(on: inner, name: name)

    case .mutableReference(let inner):
      if let extensions = genericExtensionMethods["MutRef"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "MutRef",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      if let extensions = genericExtensionMethods["Ref"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "Ref",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      return try lookupConcreteMethodSymbolDirect(on: inner, name: name)

    case .weakReference(let inner):
      if let extensions = genericExtensionMethods["WeakRef"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "WeakRef",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      if let extensions = genericIntrinsicExtensionMethods["WeakRef"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveIntrinsicExtensionMethod(
          baseType: selfType,
          templateName: "WeakRef",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      return nil

    default: break
    }

    switch selfType {
    case .structure(let defId):
      let typeName = context.getName(defId) ?? ""
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      if let extensions = genericExtensionMethods[typeName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: typeName,
          typeArgs: [],
          methodInfo: ext
        )
      }
      if let templateName = context.getTemplateName(defId),
         let typeArgs = context.getTypeArguments(defId),
         let extensions = genericExtensionMethods[templateName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: templateName,
          typeArgs: typeArgs,
          methodInfo: ext
        )
      }
      return nil

    case .`enum`(let defId):
      let typeName = context.getName(defId) ?? ""
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      if let extensions = genericExtensionMethods[typeName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: typeName,
          typeArgs: [],
          methodInfo: ext
        )
      }
      if let templateName = context.getTemplateName(defId),
         let typeArgs = context.getTypeArguments(defId),
         let extensions = genericExtensionMethods[templateName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: templateName,
          typeArgs: typeArgs,
          methodInfo: ext
        )
      }
      return nil

    case .genericStruct(let templateName, let args):
      if let extensions = genericExtensionMethods[templateName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: templateName,
          typeArgs: args,
          methodInfo: ext
        )
      }
      return nil

    case .genericEnum(let templateName, let args):
      if let extensions = genericExtensionMethods[templateName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: templateName,
          typeArgs: args,
          methodInfo: ext
        )
      }
      return nil

    case .pointer(let element):
      if let extensions = genericIntrinsicExtensionMethods["Ptr"],
        let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveIntrinsicExtensionMethod(
          baseType: selfType,
          templateName: "Ptr",
          typeArgs: [element],
          methodInfo: ext
        )
      }

      if let extensions = genericExtensionMethods["Ptr"],
        let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "Ptr",
          typeArgs: [element],
          methodInfo: ext
        )
      }
      return nil
    case .mutableWeakReference(let inner):
      if let extensions = genericIntrinsicExtensionMethods["MutWeakRef"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveIntrinsicExtensionMethod(
          baseType: selfType,
          templateName: "MutWeakRef",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      if let extensions = genericIntrinsicExtensionMethods["WeakRef"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveIntrinsicExtensionMethod(
          baseType: selfType,
          templateName: "WeakRef",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      if let extensions = genericExtensionMethods["MutWeakRef"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "MutWeakRef",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      if let extensions = genericExtensionMethods["WeakRef"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "WeakRef",
          typeArgs: [inner],
          methodInfo: ext
        )
      }
      return nil

    case .mutablePointer(let element):
      if let extensions = genericIntrinsicExtensionMethods["MutPtr"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveIntrinsicExtensionMethod(
          baseType: selfType,
          templateName: "MutPtr",
          typeArgs: [element],
          methodInfo: ext
        )
      }
      if let extensions = genericIntrinsicExtensionMethods["Ptr"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveIntrinsicExtensionMethod(
          baseType: selfType,
          templateName: "Ptr",
          typeArgs: [element],
          methodInfo: ext
        )
      }

      if let extensions = genericExtensionMethods["MutPtr"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "MutPtr",
          typeArgs: [element],
          methodInfo: ext
        )
      }
      if let extensions = genericExtensionMethods["Ptr"],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "Ptr",
          typeArgs: [element],
          methodInfo: ext
        )
      }
      return nil

    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64,
      .bool:
      let typeName = selfType.description
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      if let extensions = genericExtensionMethods[typeName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: typeName,
          typeArgs: [],
          methodInfo: ext
        )
      }
      return nil

    default:
      return nil
    }
  }

  private func unifyGenericTypePattern(
    pattern: Type,
    actual: Type,
    typeParamNames: Set<String>,
    inferred: inout [String: Type]
  ) -> Bool {
    switch pattern {
    case .genericParameter(let name) where typeParamNames.contains(name):
      if let existing = inferred[name] {
        return existing == actual
      }
      inferred[name] = actual
      return true

    case .reference(let pInner):
      switch actual {
      case .reference(let aInner), .mutableReference(let aInner):
        return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
      default:
        return false
      }

    case .mutableReference(let pInner):
      guard case .mutableReference(let aInner) = actual else { return false }
      return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)

    case .weakReference(let pInner):
      switch actual {
      case .weakReference(let aInner), .mutableWeakReference(let aInner):
        return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
      default:
        return false
      }
    case .mutableWeakReference(let pInner):
      guard case .mutableWeakReference(let aInner) = actual else { return false }
      return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)

    case .pointer(let pInner):
      switch actual {
      case .pointer(let aInner), .mutablePointer(let aInner):
        return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
      default:
        return false
      }

    case .mutablePointer(let pInner):
      guard case .mutablePointer(let aInner) = actual else { return false }
      return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)

    case .genericStruct(let pTemplate, let pArgs):
      guard case .genericStruct(let aTemplate, let aArgs) = actual,
            pTemplate == aTemplate,
            pArgs.count == aArgs.count else { return false }
      for (pArg, aArg) in zip(pArgs, aArgs) {
        guard unifyGenericTypePattern(pattern: pArg, actual: aArg, typeParamNames: typeParamNames, inferred: &inferred) else {
          return false
        }
      }
      return true

    case .genericEnum(let pTemplate, let pArgs):
      guard case .genericEnum(let aTemplate, let aArgs) = actual,
            pTemplate == aTemplate,
            pArgs.count == aArgs.count else { return false }
      for (pArg, aArg) in zip(pArgs, aArgs) {
        guard unifyGenericTypePattern(pattern: pArg, actual: aArg, typeParamNames: typeParamNames, inferred: &inferred) else {
          return false
        }
      }
      return true

    case .function(let pParams, let pRet):
      guard case .function(let aParams, let aRet) = actual,
            pParams.count == aParams.count else { return false }
      for (pParam, aParam) in zip(pParams, aParams) {
        guard unifyGenericTypePattern(pattern: pParam.type, actual: aParam.type, typeParamNames: typeParamNames, inferred: &inferred) else {
          return false
        }
      }
      return unifyGenericTypePattern(pattern: pRet, actual: aRet, typeParamNames: typeParamNames, inferred: &inferred)

    default:
      return pattern == actual
    }
  }

  private func inferTraitTypeArgsForReceiver(_ receiverType: Type, traitName: String) throws -> [Type]? {
    guard let traitInfo = traits[traitName] else {
      return nil
    }
    if traitInfo.typeParameters.isEmpty {
      return []
    }

    let traitMethods = try flattenedTraitMethods(traitName)
    let typeParamNames = traitInfo.typeParameters.map { $0.name }
    let typeParamNameSet = Set(typeParamNames)
    var inferred: [String: Type] = [:]

    for (_, sig) in traitMethods {
      guard let concreteMethod = try lookupConcreteMethodSymbolDirect(on: receiverType, name: sig.name),
            case .function(let actualParams, let actualReturn) = concreteMethod.type else {
        continue
      }

      let expected: (params: [Parameter], ret: Type) = try withNewScope {
        try currentScope.defineType("Self", type: receiverType)
        for typeParam in traitInfo.typeParameters {
          let genericType: Type = .genericParameter(name: typeParam.name)
          currentScope.defineGenericParameter(typeParam.name, type: genericType)
          try currentScope.defineType(typeParam.name, type: genericType)
        }
        let params: [Parameter] = try sig.parameters.map { param in
          let t = try resolveTypeNode(param.type)
          return Parameter(type: t, kind: passKindForParameterType(t))
        }
        let ret = try resolveTypeNode(sig.returnType)
        return (params, ret)
      }

      guard expected.params.count == actualParams.count else {
        continue
      }

      var localInferred = inferred
      var ok = true
      for (expectedParam, actualParam) in zip(expected.params, actualParams) {
        if !unifyGenericTypePattern(
          pattern: expectedParam.type,
          actual: actualParam.type,
          typeParamNames: typeParamNameSet,
          inferred: &localInferred
        ) {
          ok = false
          break
        }
      }

      if ok {
        ok = unifyGenericTypePattern(
          pattern: expected.ret,
          actual: actualReturn,
          typeParamNames: typeParamNameSet,
          inferred: &localInferred
        )
      }

      if ok {
        inferred = localInferred
      }
    }

    let ordered = typeParamNames.compactMap { inferred[$0] }
    if ordered.count == typeParamNames.count {
      return ordered
    }
    return nil
  }

  func lookupConcreteMethodSymbol(on selfType: Type, name: String) throws -> Symbol? {
    if let direct = try lookupConcreteMethodSymbolDirect(on: selfType, name: name) {
      return direct
    }

    var traitMatchedSymbols: [Symbol] = []
    for (traitName, templates) in genericExtensionMethods {
      guard traits[traitName] != nil else {
        continue
      }
      guard let methodTemplate = templates.first(where: { $0.method.name == name }) else {
        continue
      }

      let inferredTraitArgs: [Type]? = try {
        if let traitInfo = traits[traitName], traitInfo.typeParameters.isEmpty {
          return []
        }
        return try inferTraitTypeArgsForReceiver(selfType, traitName: traitName)
      }()

      guard let traitArgs = inferredTraitArgs else {
        continue
      }
      guard hasNominalConformance(selfType: selfType, traitName: traitName, traitTypeArgs: traitArgs)
      else {
        continue
      }

      let resolved = try resolveGenericExtensionMethod(
        baseType: selfType,
        templateName: traitName,
        typeArgs: traitArgs,
        methodInfo: methodTemplate
      )
      traitMatchedSymbols.append(resolved)
    }

    if traitMatchedSymbols.count > 1 {
      throw SemanticError(.generic(
        "Ambiguous method '\(name)' for type '\(selfType.description)' via trait extensions"
      ), span: currentSpan)
    }
    if let matched = traitMatchedSymbols.first {
      return matched
    }

    return nil
  }

  private func makeExtensionTemplateMethodSymbol(
    _ method: MethodDeclaration,
    functionType: Type,
    sourceFile: String,
    modulePath: [String],
    packageID: String
  ) -> Symbol {
    if method.access == .private {
      return context.createSymbol(
        name: method.name,
        modulePath: modulePath,
        sourceFile: sourceFile,
        type: functionType,
        kind: .function,
        access: .private,
        span: currentSpan,
        packageID: packageID,
        isMutable: false
      )
    }

    return makeGlobalSymbol(
      name: method.name,
      type: functionType,
      kind: .function,
      access: .protected
    )
  }
  
  /// Resolves a generic extension method without instantiating it.
  /// Returns a symbol with the substituted function type and records an instantiation request.
  func resolveGenericExtensionMethod(
    baseType: Type,
    templateName: String,
    typeArgs: [Type],
    methodInfo: GenericExtensionMethodTemplate
  ) throws -> Symbol {
    let typeParams = methodInfo.typeParams
    let method = methodInfo.method
    
    guard typeParams.count == typeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(typeParams.count) type arguments",
        got: "\(typeArgs.count)"
      )
    }

    try enforceGenericConstraints(typeParameters: typeParams, args: typeArgs)

    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in typeParams.enumerated() {
      substitution[param.name] = typeArgs[i]
    }
    substitution["Self"] = baseType
    
    // Resolve function type with explicit substitution, preferring declaration-time
    // checked types to avoid shadowing/lookup issues on original TypeNode.
    let functionType: Type
    if let checkedReturnType = methodInfo.checkedReturnType,
       let checkedParameters = methodInfo.checkedParameters {
      let returnType = SemaUtils.substituteType(checkedReturnType, substitution: substitution, context: context)
      let params = checkedParameters.map { param in
        let paramType = SemaUtils.substituteType(param.type, substitution: substitution, context: context)
        return Parameter(type: paramType, kind: passKindForParameterType(paramType))
      }
      functionType = Type.function(parameters: params, returns: returnType)
    } else {
      let returnType = try resolveTypeNodeWithSubstitution(method.returnType, substitution: substitution)
      let params = try method.parameters.map { param -> Parameter in
        let paramType = try resolveTypeNodeWithSubstitution(param.type, substitution: substitution)
        return Parameter(type: paramType, kind: passKindForParameterType(paramType))
      }
      functionType = Type.function(parameters: params, returns: returnType)
    }
    
    // Record instantiation request if type args are concrete
    // Skip if method has method-level type parameters (will be recorded when method call is processed)
    if !typeArgs.contains(where: { context.containsGenericParameter($0) }) && method.typeParameters.isEmpty {
      recordInstantiation(InstantiationRequest(
        kind: .extensionMethod(
          templateName: templateName,
          baseType: baseType,
          template: methodInfo,
          typeArgs: typeArgs,
          methodTypeArgs: []
        ),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    let methodSymbol = makeExtensionTemplateMethodSymbol(
      method,
      functionType: functionType,
      sourceFile: methodInfo.sourceFile,
      modulePath: methodInfo.modulePath,
      packageID: methodInfo.packageID
    )
    registerReceiverStyleMethod(
      methodSymbol,
      parameters: method.parameters,
      declaredName: method.name,
      owner: .extensionTemplate(ownerName: templateName)
    )
    return methodSymbol
  }
  
  /// Resolves an intrinsic extension method without instantiating it.
  func resolveIntrinsicExtensionMethod(
    baseType: Type,
    templateName: String,
    typeArgs: [Type],
    methodInfo: (typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)
  ) throws -> Symbol {
    let (typeParams, method) = methodInfo
    
    guard typeParams.count == typeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(typeParams.count) type arguments",
        got: "\(typeArgs.count)"
      )
    }

    try enforceGenericConstraints(typeParameters: typeParams, args: typeArgs)
    
    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in typeParams.enumerated() {
      substitution[param.name] = typeArgs[i]
    }
    substitution["Self"] = baseType
    
    // Resolve function type with explicit substitution to avoid scope shadowing
    // by genericParameters with the same name (e.g., method-level T).
    let returnType = try resolveTypeNodeWithSubstitution(method.returnType, substitution: substitution)
    let params = try method.parameters.map { param -> Parameter in
      let paramType = try resolveTypeNodeWithSubstitution(param.type, substitution: substitution)
      return Parameter(type: paramType, kind: passKindForParameterType(paramType))
    }
    let functionType = Type.function(parameters: params, returns: returnType)
    
    let methodSymbol = makeGlobalSymbol(
      name: method.name,
      type: functionType,
      kind: .function,
      access: .protected
    )
    registerReceiverStyleMethod(
      methodSymbol,
      parameters: method.parameters,
      declaredName: method.name,
      owner: .extensionTemplate(ownerName: templateName)
    )
    return methodSymbol
  }

  /// Result type for resolving a generic method with explicit type arguments
  struct GenericMethodResolutionResult {
    let methodSymbol: Symbol
    let methodType: Type
    let typeArgs: [Type]?
    let methodTypeArgs: [Type]
    /// If non-nil, this is a trait method placeholder that should be resolved at monomorphization time
    let traitName: String?
    
    init(methodSymbol: Symbol, methodType: Type, typeArgs: [Type]?, methodTypeArgs: [Type], traitName: String? = nil) {
      self.methodSymbol = methodSymbol
      self.methodType = methodType
      self.typeArgs = typeArgs
      self.methodTypeArgs = methodTypeArgs
      self.traitName = traitName
    }
  }

  /// Resolves a generic method with explicit method-level type arguments.
  /// This is used for the `obj.[Type]method(args)` syntax.
  func resolveGenericMethodWithExplicitTypeArgs(
    baseType: Type,
    methodName: String,
    methodTypeArgs: [Type]
  ) throws -> GenericMethodResolutionResult {
    // Handle generic parameter case - look up method in trait bounds
    if case .genericParameter(let paramName) = baseType {
      return try resolveGenericMethodOnGenericParameter(
        paramName: paramName,
        baseType: baseType,
        methodName: methodName,
        methodTypeArgs: methodTypeArgs
      )
    }
    
    // Determine the template name and type args from the base type
    let templateName: String
    let typeArgs: [Type]
    
    switch baseType {
    case .genericStruct(let name, let args):
      templateName = name
      typeArgs = args
    case .genericEnum(let name, let args):
      templateName = name
      typeArgs = args
    case .structure(let defId):
      // Non-generic struct - extract base name
      let name = context.getName(defId) ?? ""
      templateName = context.getTemplateName(defId) ?? name
      typeArgs = context.getTypeArguments(defId) ?? []
    case .`enum`(let defId):
      // Non-generic enum - extract base name
      let name = context.getName(defId) ?? ""
      templateName = context.getTemplateName(defId) ?? name
      typeArgs = context.getTypeArguments(defId) ?? []
    case .pointer(let element):
      templateName = "Ptr"
      typeArgs = [element]
    case .mutablePointer(let element):
      templateName = "MutPtr"
      typeArgs = [element]
    case .int:
      templateName = "Int"
      typeArgs = []
    case .int8:
      templateName = "Int8"
      typeArgs = []
    case .int16:
      templateName = "Int16"
      typeArgs = []
    case .int32:
      templateName = "Int32"
      typeArgs = []
    case .int64:
      templateName = "Int64"
      typeArgs = []
    case .uint:
      templateName = "UInt"
      typeArgs = []
    case .uint8:
      templateName = "UInt8"
      typeArgs = []
    case .uint16:
      templateName = "UInt16"
      typeArgs = []
    case .uint32:
      templateName = "UInt32"
      typeArgs = []
    case .uint64:
      templateName = "UInt64"
      typeArgs = []
    case .float32:
      templateName = "Float32"
      typeArgs = []
    case .float64:
      templateName = "Float64"
      typeArgs = []
    case .bool:
      templateName = "Bool"
      typeArgs = []
    default:
      throw SemanticError(.generic("Cannot call generic method on type \(baseType)"), span: currentSpan)
    }

    // Look up the method in generic extension methods
    guard let extensions = genericExtensionMethods[templateName] else {
      throw SemanticError(.generic("No extension methods found for type \(templateName)"), span: currentSpan)
    }
    
    guard let methodInfo = extensions.first(where: { $0.method.name == methodName }) else {
      throw SemanticError(.generic("Method '\(methodName)' not found on type \(templateName)"), span: currentSpan)
    }

    try enforceGenericConstraints(typeParameters: methodInfo.typeParams, args: typeArgs)
    
    let method = methodInfo.method
    let methodTypeParams = method.typeParameters
    
    // Validate method type argument count
    guard methodTypeParams.count == methodTypeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(methodTypeParams.count) method type arguments",
        got: "\(methodTypeArgs.count)"
      )
    }
    
    // Validate method type argument constraints
    try enforceGenericConstraints(typeParameters: methodTypeParams, args: methodTypeArgs)
    
    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in methodInfo.typeParams.enumerated() {
      substitution[param.name] = typeArgs[i]
    }
    for (i, param) in methodTypeParams.enumerated() {
      substitution[param.name] = methodTypeArgs[i]
    }
    substitution["Self"] = baseType
    
    // Resolve function type with substitution
    let functionType = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      
      let returnType = try resolveTypeNode(method.returnType)
      let params = try method.parameters.map { param -> Parameter in
        let paramType = try resolveTypeNode(param.type)
        return Parameter(type: paramType, kind: passKindForParameterType(paramType))
      }
      
      return Type.function(parameters: params, returns: returnType)
    }
    
    // Record instantiation request if all type args are concrete
    let allTypeArgs = typeArgs + methodTypeArgs
    if !allTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
      recordInstantiation(InstantiationRequest(
        kind: .extensionMethod(
          templateName: templateName,
          baseType: baseType,
          template: methodInfo,
          typeArgs: typeArgs,
          methodTypeArgs: methodTypeArgs
        ),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    let methodSymbol = makeExtensionTemplateMethodSymbol(
      method,
      functionType: functionType,
      sourceFile: methodInfo.sourceFile,
      modulePath: methodInfo.modulePath,
      packageID: methodInfo.packageID
    )
    
    return GenericMethodResolutionResult(
      methodSymbol: methodSymbol,
      methodType: functionType,
      typeArgs: typeArgs.isEmpty ? nil : typeArgs,
      methodTypeArgs: methodTypeArgs
    )
  }
  
  /// Resolves a generic method call on a generic parameter type.
  /// This handles the case where we call a generic method on a type parameter
  /// that has trait bounds defining the method.
  private func resolveGenericMethodOnGenericParameter(
    paramName: String,
    baseType: Type,
    methodName: String,
    methodTypeArgs: [Type]
  ) throws -> GenericMethodResolutionResult {
    // Look up trait bounds for this generic parameter
    guard let bounds = genericTraitBounds[paramName] else {
      throw SemanticError(.generic("Type parameter \(paramName) has no trait bounds"), span: currentSpan)
    }
    
    // Search for the method in all trait bounds
    for traitConstraint in bounds {
      let traitName = traitConstraint.baseName
      let methods = try flattenedTraitMethods(traitName)
      if let sig = methods[methodName] {
        // Found the method - check if it has method-level type parameters
        let methodTypeParams = sig.typeParameters
        
        // Validate method type argument count
        guard methodTypeParams.count == methodTypeArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(methodTypeParams.count) method type arguments",
            got: "\(methodTypeArgs.count)"
          )
        }
        
        // Validate method type argument constraints
        try enforceGenericConstraints(typeParameters: methodTypeParams, args: methodTypeArgs)
        
        // Create type substitution map for method type parameters
        var substitution: [String: Type] = [:]
        for (i, param) in methodTypeParams.enumerated() {
          substitution[param.name] = methodTypeArgs[i]
        }
        
        // Resolve function type with substitution
        let functionType = try withNewScope {
          // Bind Self to the generic parameter type
          let normalizedSelfType: Type
          if case .reference(let inner) = baseType {
            normalizedSelfType = inner
          } else {
            normalizedSelfType = baseType
          }
          try currentScope.defineType("Self", type: normalizedSelfType)
          
          // Bind trait type parameters to their actual type arguments
          // For example, for [T]Iterator with constraint [A]Iterator, bind T -> A
          if let traitInfo = traits[traitName] {
            if case .generic(_, let argNodes) = traitConstraint {
              for (i, typeParam) in traitInfo.typeParameters.enumerated() {
                if i < argNodes.count {
                  let argType = try resolveTypeNode(argNodes[i])
                  try currentScope.defineType(typeParam.name, type: argType)
                }
              }
            }
          }
          
          // Bind method type parameters
          for (paramName, paramType) in substitution {
            try currentScope.defineType(paramName, type: paramType)
          }
          
          let returnType = try resolveTypeNode(sig.returnType)
          let params = try sig.parameters.map { param -> Parameter in
            let paramType = try resolveTypeNode(param.type)
            return Parameter(type: paramType, kind: passKindForParameterType(paramType))
          }
          
          return Type.function(parameters: params, returns: returnType)
        }
        
        // Create a placeholder symbol without __trait_ prefix
        // The traitName field in the result indicates this is a trait method placeholder
        let methodSymbol = makeGlobalSymbol(
          name: methodName,
          type: functionType,
          kind: .function,
          access: .protected
        )
        recordTraitPlaceholderInstantiation(
          baseType: baseType,
          methodName: methodName,
          methodTypeArgs: methodTypeArgs
        )
        
        return GenericMethodResolutionResult(
          methodSymbol: methodSymbol,
          methodType: functionType,
          typeArgs: nil,
          methodTypeArgs: methodTypeArgs,
          traitName: traitName
        )
      }
    }
    
    throw SemanticError(.generic("Method '\(methodName)' not found in trait bounds of \(paramName)"), span: currentSpan)
  }

  enum BuiltinSubscriptKind {
    case string
    case list(element: Type)
    case deque(element: Type)
    case pointer(element: Type, mutable: Bool)
  }

  private func builtinSubscriptBaseType(_ type: Type) -> Type {
    switch type {
    case .reference(let inner), .mutableReference(let inner):
      return inner
    default:
      return type
    }
  }

  func resolveBuiltinSubscriptKind(baseType: Type) -> BuiltinSubscriptKind? {
    let unwrapped = builtinSubscriptBaseType(baseType)
    switch unwrapped {
    case .structure(let defId):
      if context.getName(defId) == "String" {
        return .string
      }
      if let template = context.getTemplateName(defId),
         let typeArgs = context.getTypeArguments(defId),
         typeArgs.count == 1
      {
        if template == "List" {
          return .list(element: typeArgs[0])
        }
        if template == "Deque" {
          return .deque(element: typeArgs[0])
        }
      }
      return nil
    case .genericStruct(let template, let args):
      if template == "List", args.count == 1 {
        return .list(element: args[0])
      }
      if template == "Deque", args.count == 1 {
        return .deque(element: args[0])
      }
      return nil
    case .pointer(let element):
      return .pointer(element: element, mutable: false)
    case .mutablePointer(let element):
      return .pointer(element: element, mutable: true)
    default:
      return nil
    }
  }

  func buildBuiltinSubscriptHelperCall(
    base: TypedExpressionNode,
    args: [TypedExpressionNode],
    helperName: String
  ) throws -> TypedExpressionNode {
    let lookupType = builtinSubscriptBaseType(base.type)
    guard let method = try lookupConcreteMethodSymbol(on: lookupType, name: helperName) else {
      throw SemanticError(.generic(
        "Missing builtin subscript helper '\(helperName)' for type '\(lookupType)'"
      ), span: currentSpan)
    }
    guard case .function(let params, let returns) = method.type else {
      fatalError("builtin subscript helper must be a function")
    }

    if args.count != params.count - 1 {
      throw SemanticError.invalidArgumentCount(
        function: helperName,
        expected: params.count - 1,
        got: args.count
      )
    }

    let baseIsRvalue = base.valueCategory == .rvalue
    let tempSym = baseIsRvalue ? nextSynthSymbol(prefix: "temp_sub", type: base.type) : nil
    let resolvedBase: TypedExpressionNode = {
      if let tempSym {
        return .variable(identifier: tempSym)
      }
      return base
    }()

    var finalBase = resolvedBase
    if let firstParam = params.first, firstParam.type != resolvedBase.type {
      if case (.mutableReference(let baseInner), .reference(let paramInner)) = (resolvedBase.type, firstParam.type),
         baseInner == paramInner
      {
        finalBase = resolvedBase
      } else if let implicitRef = try makeImplicitReference(resolvedBase, expectedType: firstParam.type) {
        finalBase = implicitRef
      } else if let implicitDeref = makeImplicitDereference(resolvedBase, expectedType: firstParam.type) {
        finalBase = implicitDeref
      } else if canWidenMutableReference(resolvedBase, expectedType: firstParam.type) {
        finalBase = resolvedBase
      } else {
        throw SemanticError.typeMismatch(
          expected: firstParam.type.description,
          got: resolvedBase.type.description
        )
      }
    }

    var coercedArgs = args
    for i in 0..<coercedArgs.count {
      let param = params[i + 1]
      coercedArgs[i] = try coerceLiteral(coercedArgs[i], to: param.type)
      if coercedArgs[i].type != param.type {
        throw SemanticError.typeMismatch(
          expected: param.type.description,
          got: coercedArgs[i].type.description
        )
      }
    }

    let callee: TypedExpressionNode = .methodReference(
      base: finalBase,
      method: method,
      typeArgs: nil,
      methodTypeArgs: nil,
      type: method.type
    )
    let call: TypedExpressionNode = .call(
      callee: callee,
      arguments: coercedArgs,
      type: returns
    )

    if let tempSym {
      return .makeLetBlock(
        identifier: tempSym,
        value: base,
        body: call,
        type: returns
      )
    }

    return call
  }

  func resolveSubscriptReference(
    base: TypedExpressionNode,
    args: [TypedExpressionNode]
  ) throws -> TypedExpressionNode {
    return try resolveBuiltinSubscriptAsReference(base: base, args: args, mutable: false)
  }

  func resolveBuiltinSubscriptAsReference(
    base: TypedExpressionNode,
    args: [TypedExpressionNode],
    mutable: Bool
  ) throws -> TypedExpressionNode {
    switch resolveBuiltinSubscriptKind(baseType: base.type) {
    case .string:
      throw SemanticError(.generic("String subscript is not addressable"), span: currentSpan)
    case .list, .deque:
      let helperName = mutable ? "__index_mut_ref" : "__index_ref"
      return try buildBuiltinSubscriptHelperCall(base: base, args: args, helperName: helperName)
    case .pointer:
      return try resolveSubscript(base: base, args: args, expectedType: mutable ? .mutableReference(inner: .void) : .reference(inner: .void))
    case .none:
      throw SemanticError(.generic(
        "subscript is only supported for String, List, Deque, and pointer types"
      ), span: currentSpan)
    }
  }

  func resolveSubscript(base: TypedExpressionNode, args: [TypedExpressionNode], expectedType: Type? = nil) throws
    -> TypedExpressionNode
  {
    let type = base.type
    let structType = builtinSubscriptBaseType(type)

    if case .pointer(let element) = structType {
      guard args.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: "pointer subscript", expected: 1, got: args.count)
      }
      var index = args[0]
      index = try coerceLiteral(index, to: .uint)
      if index.type != .uint {
        throw SemanticError.typeMismatch(expected: "UInt", got: index.type.description)
      }
      let ptrExpr: TypedExpressionNode
      switch type {
      case .reference, .mutableReference:
        ptrExpr = .derefExpression(expression: base, type: structType)
      default:
        ptrExpr = base
      }
      let offsetExpr: TypedExpressionNode = .arithmeticExpression(
        left: ptrExpr, op: .plus, right: index, type: structType)
      return .derefExpression(expression: offsetExpr, type: element)
    }
    if case .mutablePointer(let element) = structType {
      guard args.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: "pointer subscript", expected: 1, got: args.count)
      }
      var index = args[0]
      index = try coerceLiteral(index, to: .uint)
      if index.type != .uint {
        throw SemanticError.typeMismatch(expected: "UInt", got: index.type.description)
      }
      let ptrExpr: TypedExpressionNode
      switch type {
      case .reference, .mutableReference:
        ptrExpr = .derefExpression(expression: base, type: structType)
      default:
        ptrExpr = base
      }
      let offsetExpr: TypedExpressionNode = .arithmeticExpression(
        left: ptrExpr, op: .plus, right: index, type: structType)
      return .derefExpression(expression: offsetExpr, type: element)
    }

    guard let builtinKind = resolveBuiltinSubscriptKind(baseType: base.type) else {
      throw SemanticError(.generic(
        "subscript is only supported for String, List, Deque, and pointer types"
      ), span: currentSpan)
    }

    if let expectedType {
      switch expectedType {
      case .reference:
        return try resolveBuiltinSubscriptAsReference(base: base, args: args, mutable: false)
      case .mutableReference:
        return try resolveBuiltinSubscriptAsReference(base: base, args: args, mutable: true)
      default:
        break
      }
    }

    switch builtinKind {
    case .string, .list, .deque:
      return try buildBuiltinSubscriptHelperCall(base: base, args: args, helperName: "__index_get")
    case .pointer:
      fatalError("pointer subscript should have returned above")
    }
  }

  /// Infers a trait object method call (dynamic dispatch through vtable).
  /// The receiver is always the trait object reference; the vtable wrapper handles
  /// self by-value vs self-ref distinction at the C level.
  func inferTraitObjectMethodCall(
    base: TypedExpressionNode,
    traitName: String,
    methodName: String,
    params: [Parameter],
    returns: Type,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    let methodIndex = try vtableMethodIndex(traitName: traitName, methodName: methodName)

    let materializedReceiver: (symbol: Symbol, value: TypedExpressionNode)?
    var finalBase = base
    if let firstParam = params.first {
      let prepared = try prepareReceiverBase(finalBase, expectedType: firstParam.type, methodName: methodName)
      finalBase = prepared.base
      materializedReceiver = prepared.binding
      if finalBase.type != firstParam.type {
        let coercedBase = try coerceLiteral(finalBase, to: firstParam.type)
        if coercedBase.type == firstParam.type {
          finalBase = coercedBase
        } else if let implicitRef = try makeImplicitReference(finalBase, expectedType: firstParam.type) {
          finalBase = implicitRef
        } else if let implicitDeref = makeImplicitDereference(finalBase, expectedType: firstParam.type) {
          finalBase = implicitDeref
        } else if canWidenMutableReference(finalBase, expectedType: firstParam.type) {
          // mut ref -> ref widening
        } else {
          throw SemanticError.typeMismatch(
            expected: firstParam.type.description,
            got: finalBase.type.description
          )
        }
      }
    } else {
      materializedReceiver = nil
    }

    // Type-check arguments (skip self parameter)
    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg = try inferTypedExpression(arg, expectedType: param.type)
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        if let implicitRef = try makeImplicitReference(typedArg, expectedType: param.type) {
          typedArg = implicitRef
        } else if let implicitDeref = makeImplicitDereference(typedArg, expectedType: param.type) {
          typedArg = implicitDeref
        } else if canWidenMutableReference(typedArg, expectedType: param.type) {
          // mut ref → ref widening: pass through unchanged
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }

    let call: TypedExpressionNode = .traitMethodCall(
      receiver: finalBase,
      traitName: traitName,
      methodName: methodName,
      methodIndex: methodIndex,
      arguments: typedArguments,
      type: returns
    )
    return wrapReceiverMaterialization(materializedReceiver, body: call, type: returns)
  }

  func checkIntrinsicCall(name: String, arguments: [ExpressionNode]) throws
    -> TypedExpressionNode?
  {
    switch name {
    case "alloc_memory":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      // Handle generics? [T]alloc_memory
      // The parser doesn't pass generic args here directly in Call expression?
      // Wait, explicit generic call .generic(fn, args) is distinct from call?
      // In AST, Call is (callee, arguments). If callee is .generic(base, args), we catch it in generic instantiation.
      // But for intrinsic alloc_memory, we might need to know T.
      // Let's assume Koral's `[Int]alloc_memory(2)` resolves to `alloc_memory` with a generic instance.
      // If `alloc_memory` is defined as `intrinsic let [T]alloc_memory...`, standard resolution might find it.
      // But we want to bypass that.
      // Strategy: If `callee` is `identifier`, and `currentScope` has `alloc_memory`, it's the generic template.
      // We need to support `[Int]alloc_memory(...)`.
      // If so, `callee` is NOT `identifier`, it is `generic(base, args)`.
      // `inferTypedExpression` handles `.generic` by instantiating.
      // We should intercept `generic` too or let it instantiate and then check the name?
      // If we let it instantiate, we get a function. Then we call it.
      // So `callee` will be a `TypedExpressionNode`? No, `callee` in `checkIntrinsicCall` is `ExpressionNode` (identifier).
      return nil  // handled in generic inst for now or handled after resolution?

    case "init_memory":
      guard arguments.count == 2 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 2, got: arguments.count)
      }
      let ptr = try inferTypedExpression(arguments[0])
      let elementType: Type
      switch ptr.type {
      case .pointer(let resolvedElement), .mutablePointer(let resolvedElement):
        elementType = resolvedElement
      default:
        throw SemanticError(.generic("cannot use .val on non-pointer type"))
      }
      var val = try inferTypedExpression(arguments[1])
      val = try coerceLiteral(val, to: elementType)
      if val.type != elementType {
        throw SemanticError.typeMismatch(
          expected: elementType.description, got: val.type.description)
      }
      return .intrinsicCall(.initMemory(ptr: ptr, val: val))

    case "deinit_memory":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let ptr = try inferTypedExpression(arguments[0])
      guard case .mutablePointer = ptr.type else {
        throw SemanticError(.generic("cannot use .val on non-pointer type"))
      }
      return .intrinsicCall(.deinitMemory(ptr: ptr))

    case "take_memory":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let ptr = try inferTypedExpression(arguments[0])
      guard case .mutablePointer(let elementType) = ptr.type else {
        throw SemanticError(.generic("cannot use .val on non-pointer type"))
      }
      try requireDerefablePointee(elementType, operation: "take_memory", spelledType: "mut ptr")
      return .intrinsicCall(.takeMemory(ptr: ptr))

    case "spawn_thread":
      guard arguments.count == 4 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 4, got: arguments.count)
      }
      let outHandle = try inferTypedExpression(arguments[0])
      let outTid = try inferTypedExpression(arguments[1])
      let closure = try inferTypedExpression(arguments[2])
      let stackSize = try inferTypedExpression(arguments[3])
      // Validate types
      guard case .mutablePointer(.pointer(.uint8)) = outHandle.type else {
        throw SemanticError(.generic("spawn_thread: first argument must be UInt8 ptr mut ptr"))
      }
      guard case .mutablePointer(.uint64) = outTid.type else {
        throw SemanticError(.generic("spawn_thread: second argument must be UInt64 mut ptr"))
      }
      guard case .function(let params, let ret) = closure.type,
            params.isEmpty, ret == .void else {
        throw SemanticError(.generic("spawn_thread: third argument must be [Void]Func"))
      }
      guard stackSize.type == .uint64 else {
        throw SemanticError(.generic("spawn_thread: fourth argument must be UInt64"))
      }
      return .intrinsicCall(.spawnThread(outHandle: outHandle, outTid: outTid, closure: closure, stackSize: stackSize))

    case "is_unique_mutable":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let val = try inferTypedExpression(arguments[0])
      return .intrinsicCall(.isUniqueMutable(val: val))

    case "ref_count":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let refValue = try inferTypedExpression(arguments[0])
      return .intrinsicCall(.refCount(ref: refValue))

    default: return nil
    }
  }

}

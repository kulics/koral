import Foundation

// MARK: - Method Lookup and Call Handling Extension
// This extension contains methods for resolving methods and handling intrinsic calls.

extension TypeChecker {

  /// Materializes a temporary for a regular method call on an rvalue.
  func materializeTemporaryForMethodCall(
    base: TypedExpressionNode,
    method: Symbol,
    methodType: Type,
    params: [Parameter],
    returns: Type,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    // 1. 创建临时变量符号
    let tempSymbol = nextSynthSymbol(prefix: "temp_recv", type: base.type)
    
    // 2. 创建临时变量表达式（这是一个 lvalue）
    let tempVar: TypedExpressionNode = .variable(identifier: tempSymbol)
    
    // 3. 创建引用表达式（对临时变量取引用）
    let refType: Type = .reference(inner: base.type)
    let refExpr: TypedExpressionNode = .referenceExpression(expression: tempVar, type: refType)
    
    // 4. 创建方法引用
    let finalCallee: TypedExpressionNode = .methodReference(
      base: refExpr, method: method, typeArgs: nil, methodTypeArgs: nil, type: methodType)
    
    // 5. 处理方法参数
    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      // Pass expected type for implicit member expression support
      var typedArg = try inferTypedExpression(arg, expectedType: param.type)
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        // Try implicit ref/deref for arguments as well (mirrors self handling).
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }
    
    // 6. 创建方法调用
    let call: TypedExpressionNode = .call(callee: finalCallee, arguments: typedArguments, type: returns)
    
    // 7. 包装在 letExpression 中
    return .letExpression(identifier: tempSymbol, value: base, body: call, type: returns)
  }

  func lookupConcreteMethodSymbol(on selfType: Type, name: String) throws -> Symbol? {
    // Auto-deref: if the type is a reference, unwrap it first
    var actualType = selfType
    if case .reference(let inner) = selfType {
      actualType = inner
    }
    
    switch actualType {
    case .structure(let defId):
      let typeName = context.getName(defId) ?? ""
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      return nil

    case .union(let defId):
      let typeName = context.getName(defId) ?? ""
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      return nil
      
    case .genericStruct(let templateName, let args):
      // Look up method on generic struct template
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
      
    case .genericUnion(let templateName, let args):
      // Look up method on generic union template
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

    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64,
      .bool:
      let typeName = selfType.description
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      return nil

    default:
      return nil
    }
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
    
    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in typeParams.enumerated() {
      substitution[param.name] = typeArgs[i]
    }
    substitution["Self"] = baseType
    
    // Resolve function type with substitution
    let functionType = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      
      // Bind method-level type parameters as generic parameters
      for typeParam in method.typeParameters {
        currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
      }
      
      let returnType = try resolveTypeNode(method.returnType)
      let params = try method.parameters.map { param -> Parameter in
        let paramType = try resolveTypeNode(param.type)
        return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
      }
      
      return Type.function(parameters: params, returns: returnType)
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
    
    let kind = getCompilerMethodKind(method.name)
    return makeGlobalSymbol(
      name: method.name,
      type: functionType,
      kind: .function,
      methodKind: kind,
      access: .default
    )
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
    
    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in typeParams.enumerated() {
      substitution[param.name] = typeArgs[i]
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
        return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
      }
      
      return Type.function(parameters: params, returns: returnType)
    }
    
    let kind = getCompilerMethodKind(method.name)
    return makeGlobalSymbol(
      name: method.name,
      type: functionType,
      kind: .function,
      methodKind: kind,
      access: .default
    )
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
    case .genericUnion(let name, let args):
      templateName = name
      typeArgs = args
    case .structure(let defId):
      // Non-generic struct - extract base name
      let name = context.getName(defId) ?? ""
      templateName = context.getTemplateName(defId) ?? name
      typeArgs = []
    case .union(let defId):
      // Non-generic union - extract base name
      let name = context.getName(defId) ?? ""
      templateName = context.getTemplateName(defId) ?? name
      typeArgs = []
    case .pointer(let element):
      templateName = "Ptr"
      typeArgs = [element]
    default:
      throw SemanticError(.generic("Cannot call generic method on type \(baseType)"), line: currentLine)
    }
    
    // Look up the method in generic extension methods
    guard let extensions = genericExtensionMethods[templateName] else {
      throw SemanticError(.generic("No extension methods found for type \(templateName)"), line: currentLine)
    }
    
    guard let methodInfo = extensions.first(where: { $0.method.name == methodName }) else {
      throw SemanticError(.generic("Method '\(methodName)' not found on type \(templateName)"), line: currentLine)
    }
    
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
        return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
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
    
    let kind = getCompilerMethodKind(method.name)
    let methodSymbol = makeGlobalSymbol(
      name: method.name,
      type: functionType,
      kind: .function,
      methodKind: kind,
      access: .default
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
      throw SemanticError(.generic("Type parameter \(paramName) has no trait bounds"), line: currentLine)
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
            return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
          }
          
          return Type.function(parameters: params, returns: returnType)
        }
        
        let kind = getCompilerMethodKind(methodName)
        // Create a placeholder symbol without __trait_ prefix
        // The traitName field in the result indicates this is a trait method placeholder
        let methodSymbol = makeGlobalSymbol(
          name: methodName,
          type: functionType,
          kind: .function,
          methodKind: kind,
          access: .default
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
    
    throw SemanticError(.generic("Method '\(methodName)' not found in trait bounds of \(paramName)"), line: currentLine)
  }

  /// Materializes a temporary for a generic method call on an rvalue.
  func materializeTemporaryForGenericMethodCall(
    base: TypedExpressionNode,
    method: Symbol,
    methodType: Type,
    methodTypeArgs: [Type],
    typeArgs: [Type]?,
    params: [Parameter],
    returns: Type,
    arguments: [ExpressionNode],
    traitName: String? = nil
  ) throws -> TypedExpressionNode {
    // Create a temporary variable for the rvalue
    let tempSym = nextSynthSymbol(prefix: "temp_recv", type: base.type)
    
    // Create temporary variable expression (this is an lvalue)
    let tempVar: TypedExpressionNode = .variable(identifier: tempSym)
    
    // Create reference expression (take reference of temporary)
    let refType: Type = .reference(inner: base.type)
    let tempRef: TypedExpressionNode = .referenceExpression(expression: tempVar, type: refType)
    
    // Create method reference or trait method placeholder with the temporary as base
    let finalCallee: TypedExpressionNode
    if let traitName = traitName {
      let methodName = context.getName(method.defId) ?? "<unknown>"
      finalCallee = .traitMethodPlaceholder(
        traitName: traitName,
        methodName: methodName,
        base: tempRef,
        methodTypeArgs: methodTypeArgs,
        type: methodType
      )
    } else {
      finalCallee = .methodReference(
        base: tempRef,
        method: method,
        typeArgs: typeArgs,
        methodTypeArgs: methodTypeArgs,
        type: methodType
      )
    }
    
    // Type check arguments
    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg: TypedExpressionNode
      if case .lambdaExpression(let lambdaParams, let returnType, let body, _) = arg {
        typedArg = try inferLambdaExpression(
          parameters: lambdaParams,
          returnType: returnType,
          body: body,
          expectedType: param.type
        )
      } else {
        typedArg = try inferTypedExpression(arg)
      }
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }
    
    // Create the call expression
    let callExpr: TypedExpressionNode = .call(
      callee: finalCallee,
      arguments: typedArguments,
      type: returns
    )
    
    // Wrap in letExpression
    return .letExpression(
      identifier: tempSym,
      value: base,
      body: callExpr,
      type: returns
    )
  }

  func resolveSubscriptUpdateMethod(
    base: TypedExpressionNode,
    args: [TypedExpressionNode]
  ) throws -> (method: Symbol, finalBase: TypedExpressionNode, valueType: Type) {
    let methodName = "set_at"
    let type = base.type

    // Unwrap reference for method lookup
    let structType: Type
    if case .reference(let inner) = type { structType = inner } else { structType = type }

    // Get the type name for error messages
    let typeName: String
    switch structType {
    case .structure(let defId):
      typeName = context.getName(defId) ?? ""
    case .genericStruct(let template, _):
      typeName = template
    default:
      throw SemanticError.invalidOperation(op: "subscript", type1: type.description, type2: "")
    }

    var methodSymbol: Symbol? = nil
    
    // Try to look up method on concrete type first
    if case .structure(let defId) = structType {
      let name = context.getName(defId) ?? ""
      if let extensions = extensionMethods[name], let sym = extensions[methodName] {
        methodSymbol = sym
      }
    }
    
    // If not found, try generic type lookup
    if methodSymbol == nil {
      if case .genericStruct(let templateName, let args) = structType {
        if let extensions = genericExtensionMethods[templateName],
           let ext = extensions.first(where: { $0.method.name == methodName })
        {
          methodSymbol = try resolveGenericExtensionMethod(
            baseType: structType,
            templateName: templateName,
            typeArgs: args,
            methodInfo: ext
          )
        }
      }
    }

    guard let method = methodSymbol else {
      throw SemanticError.undefinedMember(methodName, typeName)
    }
    guard case .function(let params, let returns) = method.type else { fatalError() }

    if returns != .void {
      throw SemanticError.typeMismatch(expected: "Void", got: returns.description)
    }

    let expectedIndexArgCount = params.count - 2  // excluding self + value
    if args.count != expectedIndexArgCount {
      throw SemanticError.invalidArgumentCount(
        function: methodName, expected: expectedIndexArgCount, got: args.count)
    }

    // Adjust base for self param (implicit ref/deref rules)
    var finalBase = base
    if let firstParam = params.first {
      if firstParam.type != base.type {
        if case .reference(let inner) = firstParam.type, inner == base.type {
          // Implicit Ref for self requires an addressable base
          if base.valueCategory == .lvalue {
            finalBase = .referenceExpression(expression: base, type: firstParam.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: base.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = base.type, inner == firstParam.type {
          // Implicit deref: only safe for Copy
          finalBase = .derefExpression(expression: base, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: firstParam.type.description, got: base.type.description)
        }
      }
    }

    // Check index argument types (exclude last param, which is value)
    if params.count >= 2 {
      let indexParams = Array(params.dropFirst().dropLast())
      for i in 0..<args.count {
        var arg = args[i]
        let param = indexParams[i]
        arg = try coerceLiteral(arg, to: param.type)
        if arg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description, got: arg.type.description)
        }
      }
    }

    let valueType = params.last!.type
    return (method: method, finalBase: finalBase, valueType: valueType)
  }

  func resolveSubscript(base: TypedExpressionNode, args: [TypedExpressionNode]) throws
    -> TypedExpressionNode
  {
    let methodName = "at"
    let type = base.type

    // Unwrap reference
    let structType: Type
    if case .reference(let inner) = type { structType = inner } else { structType = type }

    // Get the type name for error messages
    let typeName: String
    switch structType {
    case .structure(let defId):
      typeName = context.getName(defId) ?? ""
    case .genericStruct(let template, _):
      typeName = template
    default:
      throw SemanticError.invalidOperation(op: "subscript", type1: type.description, type2: "")
    }

    var methodSymbol: Symbol? = nil
    
    // Try to look up method on concrete type first
    if case .structure(let defId) = structType {
      let name = context.getName(defId) ?? ""
      if let extensions = extensionMethods[name], let sym = extensions[methodName] {
        methodSymbol = sym
      }
    }
    
    // If not found, try generic type lookup
    if methodSymbol == nil {
      if case .genericStruct(let templateName, let typeArgs) = structType {
        if let extensions = genericExtensionMethods[templateName],
           let ext = extensions.first(where: { $0.method.name == methodName })
        {
          methodSymbol = try resolveGenericExtensionMethod(
            baseType: structType,
            templateName: templateName,
            typeArgs: typeArgs,
            methodInfo: ext
          )
        }
      }
    }

    guard let method = methodSymbol else {
      throw SemanticError.undefinedMember(methodName, typeName)
    }

    guard case .function(let params, let returns) = method.type else { fatalError() }

    let baseIsRvalue = base.valueCategory == .rvalue
    let tempSym = baseIsRvalue ? nextSynthSymbol(prefix: "temp_sub", type: base.type) : nil
    let resolvedBase: TypedExpressionNode = {
      if let tempSym {
        return .variable(identifier: tempSym)
      }
      return base
    }()

    var finalBase = resolvedBase
    if let firstParam = params.first {
      if firstParam.type != resolvedBase.type {
        if case .reference(let inner) = firstParam.type, inner == resolvedBase.type {
          // Implicit Ref for self: method expects `self ref` but base is value type
          finalBase = .referenceExpression(expression: resolvedBase, type: firstParam.type)
        } else if case .reference(let inner) = resolvedBase.type, inner == firstParam.type {
          // Implicit Deref for self: method expects `self` but base is ref type
          finalBase = .derefExpression(expression: resolvedBase, type: firstParam.type)
        }
      }
    }

    if args.count != params.count - 1 {
      throw SemanticError.invalidArgumentCount(
        function: methodName, expected: params.count - 1, got: args.count)
    }

    var coercedArgs = args
    for i in 0..<coercedArgs.count {
      let param = params[i + 1]  // skip self
      coercedArgs[i] = try coerceLiteral(coercedArgs[i], to: param.type)
      if coercedArgs[i].type != param.type {
        throw SemanticError.typeMismatch(
          expected: param.type.description, got: coercedArgs[i].type.description)
      }
    }

    let subscriptExpr: TypedExpressionNode = .subscriptExpression(
      base: finalBase,
      arguments: coercedArgs,
      method: method,
      type: returns
    )

    if let tempSym {
      return .letExpression(
        identifier: tempSym,
        value: base,
        body: subscriptExpr,
        type: returns
      )
    }

    return subscriptExpr
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

    // Type-check arguments (skip self parameter)
    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg = try inferTypedExpression(arg, expectedType: param.type)
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }

    return .traitMethodCall(
      receiver: base,
      traitName: traitName,
      methodName: methodName,
      methodIndex: methodIndex,
      arguments: typedArguments,
      type: returns
    )
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
      guard case .pointer(let elementType) = ptr.type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
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
      guard case .pointer = ptr.type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }
      return .intrinsicCall(.deinitMemory(ptr: ptr))

    case "take_memory":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let ptr = try inferTypedExpression(arguments[0])
      guard case .pointer = ptr.type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }
      return .intrinsicCall(.takeMemory(ptr: ptr))

    default: return nil
    }
  }

}

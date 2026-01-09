public class TypeChecker {
  // Store type information for variables and functions
  private var currentScope: Scope = Scope()
  private let ast: ASTNode
  // TypeName -> MethodName -> MethodSymbol
  private var extensionMethods: [String: [String: Symbol]] = [:]

  // Cache for instantiated types: "TemplateName<Arg1,Arg2>" -> Type
  private var instantiatedTypes: [String: Type] = [:]
  // Cache for instantiated functions: "TemplateName<Arg1,Arg2>" -> (MangledName, Type)
  private var instantiatedFunctions: [String: (String, Type)] = [:]
  // Generated global nodes for instantiated types (canonical versions)
  private var extraGlobalNodes: [TypedGlobalNode] = []
  // Track which layout names have been generated to avoid duplicates
  private var generatedLayouts: Set<String> = []
  // Generic Template Extensions: TemplateName -> [(TypeParams, Method)]
  private var genericExtensionMethods:
    [String: [(typeParams: [(name: String, type: TypeNode?)], method: MethodDeclaration)]] = [:]
  private var genericIntrinsicExtensionMethods:
    [String: [(typeParams: [(name: String, type: TypeNode?)], method: IntrinsicMethodDeclaration)]] =
      [:]

  // Mapping from Layout Name to Template Info (Base Name + Args)
  private var layoutToTemplateInfo: [String: (base: String, args: [Type])] = [:]
  
  private var currentLine: Int?

  public init(ast: ASTNode) {
    self.ast = ast
  }

  private func getCompilerMethodKind(_ name: String) -> CompilerMethodKind {
    switch name {
    case "__drop": return .drop
    case "__at": return .at
    default: return .normal
    }
  }

  // Changed to return TypedProgram
  public func check() throws -> TypedProgram {
    switch self.ast {
    case .program(let declarations):
      var typedDeclarations: [TypedGlobalNode] = []
      for decl in declarations {
        if let typedDecl = try checkGlobalDeclaration(decl) {
          typedDeclarations.append(typedDecl)
        }
      }
      // Append instantiated generic types
      typedDeclarations.append(contentsOf: extraGlobalNodes)
      return .program(globalNodes: typedDeclarations)
    }
  }

  private func checkGlobalDeclaration(_ decl: GlobalNode) throws -> TypedGlobalNode? {
    switch decl {
    case .globalVariableDeclaration(let name, let typeNode, let value, let isMut, _):
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name)
      }
      let type = try resolveTypeNode(typeNode)
      let typedValue = try inferTypedExpression(value)
      if typedValue.type != type {
        throw SemanticError.typeMismatch(
          expected: type.description, got: typedValue.type.description)
      }
      checkMove(typedValue)
      currentScope.define(name, type, mutable: isMut)
      return .globalVariable(
        identifier: Symbol(name: name, type: type, kind: .variable(isMut ? .MutableValue : .Value)),
        value: typedValue,
        kind: isMut ? .MutableValue : .Value
      )

    case .globalFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let body, let access):
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name)
      }

      if !typeParameters.isEmpty {
        // Perform declaration-site checking
        try withNewScope {
          for (typeParam, _) in typeParameters {
            try currentScope.defineType(typeParam, type: .genericParameter(name: typeParam))
          }

          let returnType = try resolveTypeNode(returnTypeNode)
          let params = try parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          _ = try checkFunctionBody(params, returnType, body)
        }

        let template = GenericFunctionTemplate(
          name: name,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: body,
          access: access
        )
        currentScope.defineGenericFunctionTemplate(name, template: template)
        return .genericFunctionTemplate(name: name)
      }

      let (functionType, typedBody, params) = try withNewScope {
        // introduce generic type
        for (typeParam, _) in typeParameters {
          // Define the new type
          let typeType = Type.structure(
            name: typeParam,
            members: [],
            isGenericInstantiation: false,
            isCopy: false
          )
          try currentScope.defineType(typeParam, type: typeType)
        }
        let returnType = try resolveTypeNode(returnTypeNode)
        let params = try parameters.map { param -> Symbol in
          let paramType = try resolveTypeNode(param.type)
          return Symbol(
            name: param.name, type: paramType,
            kind: .variable(param.mutable ? .MutableValue : .Value))
        }

        let (typedBody, funcType) = try checkFunctionBody(params, returnType, body)
        return (funcType, typedBody, params)
      }
      currentScope.define(name, functionType, mutable: false)
      return .globalFunction(
        identifier: Symbol(name: name, type: functionType, kind: .function),
        parameters: params,
        body: typedBody
      )

    case .intrinsicFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let access):
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name)
      }

      // Create a dummy body for intrinsic representation
      let dummyBody = ExpressionNode.booleanLiteral(false)

      if !typeParameters.isEmpty {
        try withNewScope {
          for (typeParam, _) in typeParameters {
            try currentScope.defineType(typeParam, type: .genericParameter(name: typeParam))
          }
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
        let typedBody = TypedExpressionNode.integerLiteral(value: 0, type: .int)
        return (funcType, typedBody, params)
      }
      currentScope.define(name, functionType, mutable: false)
      return nil

    case .givenDeclaration(let typeParams, let typeNode, let methods):
      if !typeParams.isEmpty {
        // Generic Given
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

        // Register methods for the template
        if genericExtensionMethods[baseName] == nil {
          genericExtensionMethods[baseName] = []
        }
        for method in methods {
          genericExtensionMethods[baseName]!.append((typeParams: typeParams, method: method))
        }

        // Return nil as we process these lazily upon instantiation
        return nil
      }

      let type = try resolveTypeNode(typeNode)
      guard case .structure(let typeName, _, _, _) = type else {
        throw SemanticError.invalidOperation(op: "given", type1: type.description, type2: "")
      }

      var typedMethods: [TypedMethodDeclaration] = []

      for method in methods {
        let (methodType, typedBody, params, returnType) = try withNewScope {
          for (typeParam, _) in method.typeParameters {
            let typeType = Type.structure(
              name: typeParam, members: [], isGenericInstantiation: false, isCopy: false)
            try currentScope.defineType(typeParam, type: typeType)
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

          for param in params {
            currentScope.define(param.name, param.type, mutable: param.isMutable())
          }

          let typedBody = try inferTypedExpression(method.body)
          if typedBody.type != returnType {
            throw SemanticError.typeMismatch(
              expected: returnType.description, got: typedBody.type.description)
          }

          // Validate __drop signature
          if method.name == "__drop" {
             if params.count != 1 || params[0].name != "self" {
                 throw SemanticError.invalidOperation(op: "__drop must have exactly one parameter 'self'", type1: "", type2: "")
             }
             if case .reference(_) = params[0].type {
                 // OK
             } else {
                 throw SemanticError.invalidOperation(op: "__drop 'self' parameter must be a reference", type1: params[0].type.description, type2: "")
             }
             if returnType != .void {
                 throw SemanticError.invalidOperation(op: "__drop must return Void", type1: returnType.description, type2: "")
             }
          }

          let functionType = Type.function(
            parameters: params.map {
              Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
          )
          return (functionType, typedBody, params, returnType)
        }

        let mangledName = "\(typeName)_\(method.name)"
        let methodKind = getCompilerMethodKind(method.name)
        let methodSymbol = Symbol(
            name: mangledName,
            type: methodType,
            kind: .function,
            methodKind: methodKind
        )

        typedMethods.append(
          TypedMethodDeclaration(
            identifier: methodSymbol,
            parameters: params,
            body: typedBody,
            returnType: returnType
          ))
        if extensionMethods[typeName] == nil {
          extensionMethods[typeName] = [:]
        }
        extensionMethods[typeName]![method.name] = methodSymbol
      }

      return .givenDeclaration(type: type, methods: typedMethods)

    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods):
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
      guard case .structure(let typeName, _, _, _) = type else {
        throw SemanticError.invalidOperation(op: "given", type1: type.description, type2: "")
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
          let typedBody = TypedExpressionNode.integerLiteral(value: 0, type: .int)
          return (functionType, typedBody, params, returnType)
        }

        let mangledName = "\(typeName)_\(method.name)"
        let methodKind = getCompilerMethodKind(method.name)
        let methodSymbol = Symbol(
            name: mangledName,
            type: methodType,
            kind: .function,
            methodKind: methodKind
        )

        typedMethods.append(
          TypedMethodDeclaration(
            identifier: methodSymbol,
            parameters: params,
            body: typedBody,
            returnType: returnType
          ))
        if extensionMethods[typeName] == nil {
          extensionMethods[typeName] = [:]
        }
        extensionMethods[typeName]![method.name] = methodSymbol
      }

      return .givenDeclaration(type: type, methods: typedMethods)

    case .globalTypeDeclaration(let name, let typeParameters, let parameters, _, let isCopy):
      // Check if type already exists
      if currentScope.lookupType(name) != nil {
        throw SemanticError.duplicateTypeDefinition(name)
      }

      if !typeParameters.isEmpty {
        let template = GenericTemplate(
          name: name, typeParameters: typeParameters, parameters: parameters, isCopy: isCopy)
        currentScope.defineGenericTemplate(name, template: template)
        return .genericTypeTemplate(name: name)
      }

      let params = try parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
      }

      // Define the new type
      let typeType = Type.structure(
        name: name,
        members: params.map { (name: $0.name, type: $0.type, mutable: $0.isMutable()) },
        isGenericInstantiation: false,
        isCopy: isCopy
      )
      try currentScope.defineType(name, type: typeType)

      return .globalTypeDeclaration(
        identifier: Symbol(name: name, type: typeType, kind: .type),
        parameters: params
      )

    case .intrinsicTypeDeclaration(let name, let typeParameters, _):
      if currentScope.lookupType(name) != nil {
        // Allow re-declaration if it matches known intrinsic? No, error duplicate.
        throw SemanticError.duplicateTypeDefinition(name)
      }

      // Intrinsic Type (e.g. Int, Bool, Pointer)
      let type: Type
      switch name {
      case "Int": type = .int
      case "Bool": type = .bool
      case "Void": type = .void
      case "String": type = .string
      case "Pointer":
         // Pointer is generic, handled below
         type = .void // Placeholder
      default:
        // Default to empty structure for other intrinsics
        type = .structure(name: name, members: [], isGenericInstantiation: false, isCopy: true)
      }

      if typeParameters.isEmpty {
        try currentScope.defineType(name, type: type)
        let dummySymbol = Symbol(name: name, type: type, kind: .variable(.Value))
        return .globalTypeDeclaration(identifier: dummySymbol, parameters: [])
      } else {
        // For generic intrinsics (like Pointer<T>), we still need a template definition
        // so the type checker knows it accepts distinct type parameters.
        let template = GenericTemplate(name: name, typeParameters: typeParameters, parameters: [], isCopy: true)
        currentScope.defineGenericTemplate(name, template: template)
        return .genericTypeTemplate(name: name)
      }
    }
  }

  private func checkFunctionBody(
    _ params: [Symbol],
    _ returnType: Type,
    _ body: ExpressionNode
  ) throws -> (TypedExpressionNode, Type) {
    return try withNewScope {
      // Add parameters to new scope
      for param in params {
        currentScope.define(param.name, param.type, mutable: param.isMutable())
      }

      let typedBody = try inferTypedExpression(body)
      if typedBody.type != returnType {
        throw SemanticError.typeMismatch(
          expected: returnType.description, got: typedBody.type.description)
      }
      let functionType = Type.function(
        parameters: params.map {
          Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
        }, returns: returnType)
      return (typedBody, functionType)
    }
  }

  // 新增用于返回带类型的表达式的类型推导函数
  private func inferTypedExpression(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .integerLiteral(let value):
      return .integerLiteral(value: value, type: .int)

    case .floatLiteral(let value):
      return .floatLiteral(value: value, type: .float)

    case .stringLiteral(let value):
      return .stringLiteral(value: value, type: .string)

    case .booleanLiteral(let value):
      return .booleanLiteral(value: value, type: .bool)

    case .identifier(let name):
      if currentScope.isMoved(name) {
        throw SemanticError.variableMoved(name)
      }
      guard let type = currentScope.lookup(name) else {
        throw SemanticError.undefinedVariable(name)
      }
      return .variable(identifier: Symbol(name: name, type: type, kind: .variable(.Value)))

    case .blockExpression(let statements, let finalExpression):
      return try withNewScope {
        var typedStatements: [TypedStatementNode] = []
        for stmt in statements {
          let typedStmt = try checkStatement(stmt)
          typedStatements.append(typedStmt)
        }
        if let finalExpr = finalExpression {
          let typedFinalExpr = try inferTypedExpression(finalExpr)
          return .blockExpression(
            statements: typedStatements, finalExpression: typedFinalExpr,
            type: typedFinalExpr.type)
        }
        return .blockExpression(
          statements: typedStatements, finalExpression: nil, type: .void)
      }

    case .arithmeticExpression(let left, let op, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      let resultType = try checkArithmeticOp(op, typedLeft.type, typedRight.type)
      return .arithmeticExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

    case .comparisonExpression(let left, let op, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      let resultType = try checkComparisonOp(op, typedLeft.type, typedRight.type)
      return .comparisonExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

    case .letExpression(let name, let typeNode, let value, let mutable, let body):
      let typedValue = try inferTypedExpression(value)
      checkMove(typedValue)

      if let typeNode = typeNode {
        let type = try resolveTypeNode(typeNode)
        if typedValue.type != type {
          throw SemanticError.typeMismatch(
            expected: type.description, got: typedValue.type.description)
        }
      }

      return try withNewScope {
        currentScope.define(name, typedValue.type, mutable: mutable)
        let symbol = Symbol(
          name: name, type: typedValue.type, kind: .variable(mutable ? .MutableValue : .Value))

        let typedBody = try inferTypedExpression(body)

        return .letExpression(
          identifier: symbol, value: typedValue, body: typedBody, type: typedBody.type)
      }

    case .ifExpression(let condition, let thenBranch, let elseBranch):
      let typedCondition = try inferTypedExpression(condition)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      let typedThen = try inferTypedExpression(thenBranch)

      if let elseExpr = elseBranch {
        let typedElse = try inferTypedExpression(elseExpr)
        if typedThen.type != typedElse.type {
          throw SemanticError.typeMismatch(
            expected: typedThen.type.description,
            got: typedElse.type.description
          )
        }
        return .ifExpression(
          condition: typedCondition, thenBranch: typedThen, elseBranch: typedElse,
          type: typedThen.type)
      } else {
        return .ifExpression(
          condition: typedCondition, thenBranch: typedThen, elseBranch: nil, type: .void)
      }

    case .whileExpression(let condition, let body):
      let typedCondition = try inferTypedExpression(condition)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      let typedBody = try inferTypedExpression(body)
      return .whileExpression(
        condition: typedCondition,
        body: typedBody,
        type: .void
      )

    case .call(let callee, let arguments):
      // Check for explicit call to __drop
      if case .identifier(let name) = callee, name == "__drop" {
          throw SemanticError.invalidOperation(op: "Explicit call to __drop is not allowed", type1: "", type2: "")
      }
      if case .memberPath(_, let path) = callee, path.last == "__drop" {
           throw SemanticError.invalidOperation(op: "Explicit call to __drop is not allowed", type1: "", type2: "")
      }

      // Check if callee is a generic instantiation (Constructor call or Function call)
      if case .genericInstantiation(let base, let args) = callee {
        if let template = currentScope.lookupGenericTemplate(base) {
          let resolvedArgs = try args.map { try resolveTypeNode($0) }
          let instantiatedType = try instantiate(template: template, args: resolvedArgs)

          guard case .structure(let typeName, let members, _, _) = instantiatedType else {
            fatalError("Instantiated type must be a structure")
          }

          if arguments.count != members.count {
            throw SemanticError.invalidArgumentCount(
              function: typeName,
              expected: members.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, expectedMember) in zip(arguments, members) {
            let typedArg = try inferTypedExpression(arg)
            if typedArg.type != expectedMember.type {
              throw SemanticError.typeMismatch(
                expected: expectedMember.type.description,
                got: typedArg.type.description
              )
            }
            checkMove(typedArg)
            typedArguments.append(typedArg)
          }

          return .typeConstruction(
            identifier: Symbol(name: typeName, type: instantiatedType, kind: .type),
            arguments: typedArguments,
            type: instantiatedType
          )
        } else if let template = currentScope.lookupGenericFunctionTemplate(base) {
          // Special handling for explicit intrinsic template calls (e.g. [Int]alloc_memory)
          if base == "alloc_memory" {
            let resolvedArgs = try args.map { try resolveTypeNode($0) }
            guard resolvedArgs.count == 1 else {
              throw SemanticError.typeMismatch(expected: "1 generic arg", got: "\(resolvedArgs.count)")
            }
            let T = resolvedArgs[0]

            guard arguments.count == 1 else {
              throw SemanticError.invalidArgumentCount(
                function: base, expected: 1, got: arguments.count)
            }
            let countExpr = try inferTypedExpression(arguments[0])
            if countExpr.type != .int {
              throw SemanticError.typeMismatch(expected: "Int", got: countExpr.type.description)
            }

            return .intrinsicCall(
              .allocMemory(count: countExpr, resultType: .pointer(element: T)))
          }

          let resolvedArgs = try args.map { try resolveTypeNode($0) }
          let (instantiatedName, instantiatedType) = try instantiateFunction(
            template: template, args: resolvedArgs)

          guard case .function(let params, let returns) = instantiatedType else {
            fatalError("Instantiated function must have function type")
          }

          if arguments.count != params.count {
            throw SemanticError.invalidArgumentCount(
              function: instantiatedName,
              expected: params.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, expectedParam) in zip(arguments, params) {
            let typedArg = try inferTypedExpression(arg)
            if typedArg.type != expectedParam.type {
              throw SemanticError.typeMismatch(
                expected: expectedParam.type.description,
                got: typedArg.type.description
              )
            }
            checkMove(typedArg)
            typedArguments.append(typedArg)
          }

          return .call(
            callee: .variable(
              identifier: Symbol(name: instantiatedName, type: instantiatedType, kind: .function)),
            arguments: typedArguments,
            type: returns
          )
        } else {
          throw SemanticError.undefinedType(base)
        }
      }

      // Check if it is a constructor call OR implicit generic function call
      if case .identifier(let name) = callee {
        // 1. Try Generic Function Template (Implicit Inference)
        if let template = currentScope.lookupGenericFunctionTemplate(name) {
          var inferred: [String: Type] = [:]

          if arguments.count != template.parameters.count {
            throw SemanticError.invalidArgumentCount(
              function: name,
              expected: template.parameters.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (argExpr, param) in zip(arguments, template.parameters) {
            let typedArg = try inferTypedExpression(argExpr)
            checkMove(typedArg)
            typedArguments.append(typedArg)
            try unify(
              node: param.type, type: typedArg.type, inferred: &inferred,
              typeParams: template.typeParameters.map { $0.name })
          }

          let resolvedArgs = try template.typeParameters.map { param -> Type in
            guard let type = inferred[param.name] else {
              throw SemanticError.typeMismatch(
                expected: "inferred type for \(param.name)", got: "unknown")
            }
            return type
          }

          if template.name == "dealloc_memory" {
            return .intrinsicCall(.deallocMemory(ptr: typedArguments[0]))
          }
          if template.name == "copy_memory" {
            return .intrinsicCall(
              .copyMemory(
                dest: typedArguments[0], source: typedArguments[1], count: typedArguments[2]))
          }
          if template.name == "move_memory" {
            return .intrinsicCall(
              .moveMemory(
                dest: typedArguments[0], source: typedArguments[1], count: typedArguments[2]))
          }
          if template.name == "ref_count" {
            return .intrinsicCall(.refCount(val: typedArguments[0]))
          }

          let (instantiatedName, instantiatedType) = try instantiateFunction(
            template: template, args: resolvedArgs)

          guard case .function(_, let returns) = instantiatedType else { fatalError() }

          return .call(
            callee: .variable(
              identifier: Symbol(name: instantiatedName, type: instantiatedType, kind: .function)),
            arguments: typedArguments,
            type: returns
          )
        }

        if let type = currentScope.lookupType(name) {
          guard case .structure(_, let parameters, _, _) = type else {
            throw SemanticError.invalidOperation(
              op: "construct", type1: type.description, type2: "")
          }

          if arguments.count != parameters.count {
            throw SemanticError.invalidArgumentCount(
              function: name,
              expected: parameters.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, expectedMember) in zip(arguments, parameters) {
            let typedArg = try inferTypedExpression(arg)
            if typedArg.type != expectedMember.type {
              throw SemanticError.typeMismatch(
                expected: expectedMember.type.description,
                got: typedArg.type.description
              )
            }
            checkMove(typedArg)
            typedArguments.append(typedArg)
          }

          return .typeConstruction(
            identifier: Symbol(name: name, type: type, kind: .type),
            arguments: typedArguments,
            type: type
          )
        }
      }

      // Special handling for intrinsic function calls (alloc_memory, etc.)
      if case .identifier(let name) = callee {
        if let intrinsicNode = try checkIntrinsicCall(name: name, arguments: arguments) {
            return intrinsicNode
        }
      }

      let typedCallee = try inferTypedExpression(callee)

      // Method call
      if case .methodReference(let base, let method, let methodType) = typedCallee {
        // Intercept Pointer methods
        if case .pointer(_) = base.type, let node = try checkIntrinsicPointerMethod(base: base, method: method, args: arguments) {
             return node
        }

        if case .function(let params, let returns) = method.type {
          if arguments.count != params.count - 1 {
            throw SemanticError.invalidArgumentCount(
              function: method.name,
              expected: params.count - 1,
              got: arguments.count
            )
          }

          // Check base type against first param
          var finalBase = base
          if let firstParam = params.first {
            if base.type != firstParam.type {
              // 尝试自动取引用：期望 T ref，实际是 T
              if case .reference(let inner) = firstParam.type, inner == base.type {
                if base.valueCategory == .lvalue {
                  finalBase = .referenceExpression(expression: base, type: firstParam.type)
                } else {
                  throw SemanticError.invalidOperation(
                    op: "implicit ref", type1: base.type.description, type2: "rvalue")
                }
              } else {
                throw SemanticError.typeMismatch(
                  expected: firstParam.type.description,
                  got: base.type.description
                )
              }
            }
          }

          let finalCallee: TypedExpressionNode = .methodReference(
            base: finalBase, method: method, type: methodType)
          
          checkMove(finalBase)

          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params.dropFirst()) {
            let typedArg = try inferTypedExpression(arg)
            if typedArg.type != param.type {
              throw SemanticError.typeMismatch(
                expected: param.type.description,
                got: typedArg.type.description
              )
            }
            checkMove(typedArg)
            typedArguments.append(typedArg)
          }

          return .call(callee: finalCallee, arguments: typedArguments, type: returns)
        }
      }

      // Function call
      if case .function(let params, let returns) = typedCallee.type {
        if arguments.count != params.count {
          throw SemanticError.invalidArgumentCount(
            function: "expression",
            expected: params.count,
            got: arguments.count
          )
        }

        var typedArguments: [TypedExpressionNode] = []
        for (arg, param) in zip(arguments, params) {
          let typedArg = try inferTypedExpression(arg)
          if typedArg.type != param.type {
            throw SemanticError.typeMismatch(
              expected: param.type.description,
              got: typedArg.type.description
            )
          }
          checkMove(typedArg)
          typedArguments.append(typedArg)
        }

        return .call(
          callee: typedCallee,
          arguments: typedArguments,
          type: returns
        )
      }

      throw SemanticError.invalidOperation(
        op: "call", type1: typedCallee.type.description, type2: "")

    case .andExpression(let left, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .andExpression(left: typedLeft, right: typedRight, type: .bool)

    case .orExpression(let left, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .orExpression(left: typedLeft, right: typedRight, type: .bool)

    case .notExpression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      if typedExpr.type != .bool {
        throw SemanticError.typeMismatch(expected: "Bool", got: typedExpr.type.description)
      }
      return .notExpression(expression: typedExpr, type: .bool)

    case .bitwiseExpression(let left, let op, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .int || typedRight.type != .int {
        throw SemanticError.typeMismatch(
          expected: "Int", got: "\(typedLeft.type) \(op) \(typedRight.type)")
      }
      return .bitwiseExpression(left: typedLeft, op: op, right: typedRight, type: .int)

    case .bitwiseNotExpression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      if typedExpr.type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: typedExpr.type.description)
      }
      return .bitwiseNotExpression(expression: typedExpr, type: .int)

    case .derefExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      if case .reference(let innerType) = typedInner.type {
        return .derefExpression(expression: typedInner, type: innerType)
      } else {
        throw SemanticError.typeMismatch(
          expected: "Reference type",
          got: typedInner.type.description
        )
      }

    case .refExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      // 禁止对引用再次取引用（仅单层）
      if case .reference(_) = typedInner.type {
        throw SemanticError.invalidOperation(
          op: "ref", type1: typedInner.type.description, type2: "")
      }
      return .referenceExpression(expression: typedInner, type: .reference(inner: typedInner.type))

    case .subscriptExpression(let base, let arguments):
      let typedBase = try inferTypedExpression(base)
      let typedArguments = try arguments.map { try inferTypedExpression($0) }
      return try resolveSubscript(base: typedBase, args: typedArguments, isMut: false)

    case .memberPath(let baseExpr, let path):
      // 1. Check if baseExpr is a Type (Generic Instantiation) for static method access
      if case .genericInstantiation(let baseName, let args) = baseExpr,
         let template = currentScope.lookupGenericTemplate(baseName) {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        let type = try instantiate(template: template, args: resolvedArgs)
        
        if path.count == 1 {
           let memberName = path[0]
           if case .structure(let name, _, let isGen, _) = type, isGen, let info = layoutToTemplateInfo[name] {
               if let extensions = genericExtensionMethods[info.base] {
                   if let ext = extensions.first(where: { $0.method.name == memberName }) {
                       let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
                       if isStatic {
                           let methodSym = try instantiateExtensionMethod(baseType: type, structureName: info.base, genericArgs: info.args, methodInfo: ext)
                           return .variable(identifier: methodSym)
                       }
                   }
               }
           }
        }
      }
      
      // 2. Check if baseExpr is a Type (Identifier) for static method access
      if case .identifier(let name) = baseExpr, let type = currentScope.lookupType(name) {
           if path.count == 1 {
               let memberName = path[0]
               var methodSymbol: Symbol?
               
               if case .structure(let typeName, _, _, _) = type {
                   if let methods = extensionMethods[typeName], let sym = methods[memberName] {
                        methodSymbol = sym
                   }
                   // Also check generic extension methods for non-generic base? (e.g. specialized?)
                   // If 'type' is structure, it is concrete.
                   // If 'extensionMethods' populated, use it.
               }
               
               if let method = methodSymbol {
                   // Return the function symbol directly (static function reference)
                   return .variable(identifier: method)
               }
           }
      }

      let typedBase = try inferTypedExpression(baseExpr)
      var currentType: Type = {
        if case .reference(let inner) = typedBase.type { return inner }
        return typedBase.type
      }()
      var typedPath: [Symbol] = []

      for (index, memberName) in path.enumerated() {
        let isLast = index == path.count - 1

        let typeToLookup = {
          if case .reference(let inner) = currentType { return inner }
          return currentType
        }()

        // Check if it is a structure to access members
        var foundMember = false
        if case .structure(_, let members, _, _) = typeToLookup {
          if let mem = members.first(where: { $0.name == memberName }) {
            let sym = Symbol(
              name: mem.name, type: mem.type, kind: .variable(mem.mutable ? .MutableValue : .Value))
            typedPath.append(sym)
            currentType = mem.type
            foundMember = true
          }
        }

        if !foundMember {
          if isLast {
            let typeName = typeToLookup.description
            if let methods = extensionMethods[typeName], let methodSym = methods[memberName] {
              let base: TypedExpressionNode
              if typedPath.isEmpty {
                base = typedBase
              } else {
                base = .memberPath(source: typedBase, path: typedPath)
              }
              return .methodReference(base: base, method: methodSym, type: methodSym.type)
            }

            if case .pointer(let element) = typeToLookup {
              if let extensions = genericIntrinsicExtensionMethods["Pointer"] {
                for ext in extensions {
                  if ext.method.name == memberName {
                    let methodSym = try instantiateIntrinsicExtensionMethod(
                      baseType: typeToLookup,
                      structureName: "Pointer",
                      genericArgs: [element],
                      methodInfo: ext
                    )
                    let base: TypedExpressionNode
                    if typedPath.isEmpty {
                      base = typedBase
                    } else {
                      base = .memberPath(source: typedBase, path: typedPath)
                    }
                    return .methodReference(base: base, method: methodSym, type: methodSym.type)
                  }
                }
              }
            }

            if case .structure(_, _, let isGen, _) = typeToLookup, isGen,
              let info = layoutToTemplateInfo[typeName]
            {

              if let extensions = genericExtensionMethods[info.base] {
                for ext in extensions {
                  if ext.method.name == memberName {
                    let methodSym = try instantiateExtensionMethod(
                      baseType: typeToLookup,
                      structureName: info.base,
                      genericArgs: info.args,
                      methodInfo: ext
                    )
                    let base: TypedExpressionNode
                    if typedPath.isEmpty {
                      base = typedBase
                    } else {
                      base = .memberPath(source: typedBase, path: typedPath)
                    }
                    return .methodReference(base: base, method: methodSym, type: methodSym.type)
                  }
                }
              }

              if let extensions = genericIntrinsicExtensionMethods[info.base] {
                for ext in extensions {
                  if ext.method.name == memberName {
                    let methodSym = try instantiateIntrinsicExtensionMethod(
                      baseType: typeToLookup,
                      structureName: info.base,
                      genericArgs: info.args,
                      methodInfo: ext
                    )
                    let base: TypedExpressionNode
                    if typedPath.isEmpty {
                      base = typedBase
                    } else {
                      base = .memberPath(source: typedBase, path: typedPath)
                    }
                    return .methodReference(base: base, method: methodSym, type: methodSym.type)
                  }
                }
              }
            }
          }

          if case .structure(let typeName, _, _, _) = typeToLookup {
            throw SemanticError.undefinedMember(memberName, typeName)
          } else {
            throw SemanticError.invalidOperation(
              op: "member access", type1: typeToLookup.description, type2: "")
          }
        }
      }
      return .memberPath(source: typedBase, path: typedPath)

    case .genericInstantiation(let base, _):
      throw SemanticError.invalidOperation(op: "use type as value", type1: base, type2: "")
    }
  }


  private func checkIntrinsicCall(name: String, arguments: [ExpressionNode]) throws -> TypedExpressionNode? {
      switch name {
      case "alloc_memory":
         guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count) }
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
         return nil // handled in generic inst for now or handled after resolution?
         
      // Non-generic intrinsics
      case "print_string":
          guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count) }
          let msg = try inferTypedExpression(arguments[0])
          return .intrinsicCall(.printString(message: msg))
      case "print_int":
           guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count) }
           let val = try inferTypedExpression(arguments[0])
           return .intrinsicCall(.printInt(value: val))
      case "print_bool":
           guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count) }
           let val = try inferTypedExpression(arguments[0])
           return .intrinsicCall(.printBool(value: val))
      case "panic":
           guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count) }
           let msg = try inferTypedExpression(arguments[0])
           return .intrinsicCall(.panic(message: msg))
           
      default: return nil
      }
  }

  private func checkIntrinsicPointerMethod(base: TypedExpressionNode, method: Symbol, args: [ExpressionNode]) throws -> TypedExpressionNode? {
      // method.name is mangled (e.g. Pointer_I_init). Extract the method name.
      var name = method.name
      if name.hasPrefix("Pointer_") {
         if let idx = name.lastIndex(of: "_") {
             name = String(name[name.index(after: idx)...])
         }
      }
      
      guard case .pointer(let elementType) = base.type else { return nil }

      switch name {
      case "init":
           guard args.count == 1 else { throw SemanticError.invalidArgumentCount(function: "init", expected: 1, got: args.count) }
           let val = try inferTypedExpression(args[0])
           if val.type != elementType {
               throw SemanticError.typeMismatch(expected: elementType.description, got: val.type.description)
           }
           return .intrinsicCall(.ptrInit(ptr: base, val: val))
      case "deinit":
           guard args.count == 0 else { throw SemanticError.invalidArgumentCount(function: "deinit", expected: 0, got: args.count) }
           return .intrinsicCall(.ptrDeinit(ptr: base))
      case "peek":
           guard args.count == 0 else { throw SemanticError.invalidArgumentCount(function: "peek", expected: 0, got: args.count) }
           return .intrinsicCall(.ptrPeek(ptr: base))
      case "offset":
           guard args.count == 1 else { throw SemanticError.invalidArgumentCount(function: "offset", expected: 1, got: args.count) }
           let offset = try inferTypedExpression(args[0])
           if offset.type != .int {
               throw SemanticError.typeMismatch(expected: "Int", got: offset.type.description)
           }
           return .intrinsicCall(.ptrOffset(ptr: base, offset: offset))
      case "take":
           guard args.count == 0 else { throw SemanticError.invalidArgumentCount(function: "take", expected: 0, got: args.count) }
           return .intrinsicCall(.ptrTake(ptr: base))
      case "replace":
           guard args.count == 1 else { throw SemanticError.invalidArgumentCount(function: "replace", expected: 1, got: args.count) }
           let val = try inferTypedExpression(args[0])
           if val.type != elementType {
               throw SemanticError.typeMismatch(expected: elementType.description, got: val.type.description)
           }
           return .intrinsicCall(.ptrReplace(ptr: base, val: val))
      default:
           return nil
      }
  }

  // 新增用于返回带类型的语句的检查函数
  private func checkStatement(_ stmt: StatementNode) throws -> TypedStatementNode {
    do {
      return try checkStatementInternal(stmt)
    } catch let e as SemanticError {
       if e.line == nil && self.currentLine != nil {
           throw SemanticError(e.kind, line: self.currentLine)
       }
       throw e
    }
  }

  private func checkStatementInternal(_ stmt: StatementNode) throws -> TypedStatementNode {
    switch stmt {
    case .variableDeclaration(let name, let typeNode, let value, let mutable, let line):
      self.currentLine = line
      let typedValue = try inferTypedExpression(value)
      let type: Type
      
      if let typeNode = typeNode {
        type = try resolveTypeNode(typeNode)
        if typedValue.type != type {
          throw SemanticError.typeMismatch(
            expected: type.description, got: typedValue.type.description)
        }
      } else {
        type = typedValue.type
      }

      checkMove(typedValue)
      currentScope.define(name, type, mutable: mutable)
      return .variableDeclaration(
        identifier: Symbol(
          name: name, type: type, kind: mutable ? .variable(.MutableValue) : .variable(.Value)),
        value: typedValue,
        mutable: mutable
      )

    case .assignment(let target, let value, let line):
      self.currentLine = line
      let typedTarget = try resolveLValue(target)
      let typedValue = try inferTypedExpression(value)
      
      if typedTarget.type != typedValue.type {
          throw SemanticError.typeMismatch(expected: typedTarget.type.description, got: typedValue.type.description)
      }
      
      checkMove(typedValue)
      
      return .assignment(target: typedTarget, value: typedValue)
      
    case .compoundAssignment(let target, let op, let value, let line):
      self.currentLine = line
      let typedTarget = try resolveLValue(target)
      let typedValue = try inferTypedExpression(value)
      // Check arithmetic op validity?
      let _ = try checkArithmeticOp(compoundOpToArithmeticOp(op), typedTarget.type, typedValue.type)
      checkMove(typedValue)
      return .compoundAssignment(target: typedTarget, operator: op, value: typedValue)

    case .expression(let expr, let line):
      self.currentLine = line
      return .expression(try inferTypedExpression(expr))
    }
  }

  private func resolveLValue(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .identifier(let name):
       guard let type = currentScope.lookup(name) else { throw SemanticError.undefinedVariable(name) }
       guard currentScope.isMutable(name) else { throw SemanticError.assignToImmutable(name) }
       return .variable(identifier: Symbol(name: name, type: type, kind: .variable(.MutableValue)))
       
    case .memberPath(let base, let path):
       // Check if base evaluates to a Reference type (RValue allowed)
       // OR if base resolves to an LValue (Mut Value required)
       
       let typedBase: TypedExpressionNode
       // We can't easily peek type without inferring.
       // Infer as generic expression (RValue check)
       let tentativeBase = try inferTypedExpression(base)
       
       var isRef = false
       if case .reference(_) = tentativeBase.type { isRef = true }
       
       typedBase = tentativeBase
       
       // Now resolve path members on typedBase.
       var current = typedBase
       var currentType = typedBase.type
       var resolvedPath: [Symbol] = []
       
       // Wait, memberPath AST implementation is flat? 
       // `case memberPath(base: ExpressionNode, path: [String])`
       // Yes.
       
       for memberName in path {
           // Unwrap reference if needed
           if case .reference(let inner) = currentType { currentType = inner }
           
           guard case .structure(_, let members, _, _) = currentType else {
               throw SemanticError.invalidOperation(op: "member access on non-struct", type1: currentType.description, type2: "")
           }
           
           guard let member = members.first(where: { $0.name == memberName }) else {
               throw SemanticError.undefinedMember(memberName, currentType.description)
           }
           
           if !member.mutable {
              // Can we mutate immutable member? 
              // If struct is mutable (LValue), then immutable fields are still immutable.
              throw SemanticError.assignToImmutable(memberName)
           }
           
           resolvedPath.append(Symbol(name: member.name, type: member.type, kind: .variable(.MutableValue)))
           currentType = member.type
       }
       return .memberPath(source: typedBase, path: resolvedPath)
    
    case .subscriptExpression(let base, let args):
       let typedBase = try resolveLValue(base) // Base must be LValue for `__at_mut` typically?
       // `__at_mut(ref self)` requires `self` to be addressable.
       
       let typedArgs = try args.map { try inferTypedExpression($0) }
       return try resolveSubscript(base: typedBase, args: typedArgs, isMut: true)

    default:
       throw SemanticError.invalidOperation(op: "assignment target", type1: String(describing: expr), type2: "")
    }
  }

  private func resolveSubscript(base: TypedExpressionNode, args: [TypedExpressionNode], isMut: Bool) throws -> TypedExpressionNode {
      let methodName = "__at"
      let type = base.type
      
      // Unwrap reference
      let structType: Type
      if case .reference(let inner) = type { structType = inner } else { structType = type }
      
      guard case .structure(let typeName, _, _, _) = structType else {
          throw SemanticError.invalidOperation(op: "subscript", type1: type.description, type2: "")
      }
      
      var methodSymbol: Symbol? = nil
      if let extensions = extensionMethods[typeName], let sym = extensions[methodName] {
          methodSymbol = sym
      } else if case .structure(_, _, let isGen, _) = structType, isGen, let info = layoutToTemplateInfo[typeName] {
           if let extensions = genericExtensionMethods[info.base] {
               if let ext = extensions.first(where: { $0.method.name == methodName }) {
                    methodSymbol = try instantiateExtensionMethod(baseType: structType, structureName: info.base, genericArgs: info.args, methodInfo: ext)
               }
           }
      }
      
      guard let method = methodSymbol else {
          throw SemanticError.undefinedMember(methodName, typeName)
      }
      
      guard case .function(let params, let returns) = method.type else { fatalError() }
      
      var finalBase = base
      if let firstParam = params.first {
           if firstParam.type != base.type {
               if case .reference(let inner) = firstParam.type, inner == base.type {
                   // Implicit Ref for self
                   finalBase = .referenceExpression(expression: base, type: firstParam.type)
               }
           }
      }
      
      if args.count != params.count - 1 {
           throw SemanticError.invalidArgumentCount(function: methodName, expected: params.count - 1, got: args.count)
      }
      
      for (arg, param) in zip(args, params.dropFirst()) {
          if arg.type != param.type {
              throw SemanticError.typeMismatch(expected: param.type.description, got: arg.type.description)
          }
      }
      
      // Determine return type (auto deref)
      let resultType: Type
      if case .reference(let inner) = returns {
          resultType = inner
      } else {
          resultType = returns
      }
      
      return .subscriptExpression(base: finalBase, arguments: args, method: method, type: resultType)
  }

        



  private func compoundOpToArithmeticOp(_ op: CompoundAssignmentOperator) -> ArithmeticOperator {
    switch op {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .modulo: return .modulo
    }
  }

  // 将 TypeNode 解析为语义层 Type，支持函数参数/返回位置的一层 reference(T)
  private func checkMove(_ node: TypedExpressionNode) {
    // Only check if we are NOT inside a closure/function that hasn't run yet?
    // But TypeChecker visits linearly.
    
    switch node {
    case .variable(let symbol):
      if !symbol.type.isCopy {
        if currentScope.isMoved(symbol.name) {
           // Double check failsafe, though lookup should have caught it if Scope checks moved.
           // Actually scope.lookup SHOULD check moved. But earlier I found it didn't?
           // Wait, inferTypedExpression checked it.
           // So this check is just for marking.
        }
        currentScope.markMoved(symbol.name)
      }
    case .ifExpression(_, let thenExpr, let elseExpr, _):
      checkMove(thenExpr)
      if let elseExpr = elseExpr {
        checkMove(elseExpr)
      }
    case .blockExpression(_, let finalExpr, _):
      if let finalExpr = finalExpr {
        checkMove(finalExpr)
      }
    case .letExpression(_, _, let body, _):
      checkMove(body)
    // Add other structural nodes if necessary
    default:
      break
    }
  }

  private func resolveTypeNode(_ node: TypeNode) throws -> Type {
    switch node {
    case .identifier(let name):
      guard let t = currentScope.resolveType(name) else {
        throw SemanticError.undefinedType(name)
      }
      return t
    case .inferredSelf:
      guard let t = currentScope.resolveType("Self") else {
        throw SemanticError.undefinedType("Self")
      }
      return t
    case .reference(let inner):
      // 仅支持一层，在 parser 已限制；此处直接映射到 Type.reference
      let base = try resolveTypeNode(inner)
      return .reference(inner: base)
    case .generic(let base, let args):
      guard let template = currentScope.lookupGenericTemplate(base) else {
        throw SemanticError.undefinedType(base)
      }
      let resolvedArgs = try args.map { try resolveTypeNode($0) }
      return try instantiate(template: template, args: resolvedArgs)
    }
  }

  private func instantiate(template: GenericTemplate, args: [Type]) throws -> Type {
    guard template.typeParameters.count == args.count else {
      throw SemanticError.typeMismatch(
        expected: "\(template.typeParameters.count) generic arguments",
        got: "\(args.count)"
      )
    }
    
    // Direct Pointer resolution
    if template.name == "Pointer" {
         return .pointer(element: args[0])
    }

    let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
    if let cached = instantiatedTypes[key] {
      return cached
    }

    // 1. Resolve members with specific types
    var resolvedMembers: [(name: String, type: Type, mutable: Bool)] = []
    try withNewScope {
      for (i, paramInfo) in template.typeParameters.enumerated() {
        try currentScope.defineType(paramInfo.name, type: args[i])
      }
      for param in template.parameters {
        let fieldType = try resolveTypeNode(param.type)
        resolvedMembers.append((name: param.name, type: fieldType, mutable: param.mutable))
      }
    }

    // 2. Calculate Layout Key and Layout Name
    // Layout Name = TemplateName + "_" + ArgLayoutKeys
    let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
    let layoutName = "\(template.name)_\(argLayoutKeys)"

    // 3. Create Specific Type
    // We use the layoutName as the struct name so CodeGen uses it.
    // But this means Box<Int> and Box<Float> have different names Box_I and Box_F.
    // And Box<Ref<Int>> and Box<Ref<String>> have SAME name Box_R.
    let specificType = Type.structure(
      name: layoutName, members: resolvedMembers, isGenericInstantiation: true, isCopy: template.isCopy)
    instantiatedTypes[key] = specificType
    layoutToTemplateInfo[layoutName] = (base: template.name, args: args)

    // Force instantiate __drop if it exists for this type
    if let methods = genericExtensionMethods[template.name] {
        for entry in methods {
             if entry.method.name == "__drop" {
                 _ = try instantiateExtensionMethod(
                     baseType: specificType,
                     structureName: template.name,
                     genericArgs: args,
                     methodInfo: entry
                 )
             }
        }
    }

    if specificType.containsGenericParameter {
      return specificType
    }

    // 4. Register Global Type Declaration if not already generated
    if !generatedLayouts.contains(layoutName) {
      generatedLayouts.insert(layoutName)

      // Create Canonical Members for the C struct definition
      // Map T -> Canonical(T)
      var canonicalMembers: [(name: String, type: Type, mutable: Bool)] = []
      try withNewScope {
        for (i, paramInfo) in template.typeParameters.enumerated() {
          try currentScope.defineType(paramInfo.name, type: args[i].canonical)
        }
        for param in template.parameters {
          let fieldType = try resolveTypeNode(param.type)
          canonicalMembers.append((name: param.name, type: fieldType, mutable: param.mutable))
        }
      }

      // Create Canonical Type
      let canonicalType = Type.structure(
        name: layoutName, members: canonicalMembers, isGenericInstantiation: true, isCopy: template.isCopy)

      // Convert to TypedGlobalNode
      let params = canonicalMembers.map { param in
        Symbol(
          name: param.name, type: param.type,
          kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
      }

      // We use a dummy symbol for the type identifier, only name matters for CodeGen
      let typeSymbol = Symbol(name: layoutName, type: canonicalType, kind: .type)
      extraGlobalNodes.append(.globalTypeDeclaration(identifier: typeSymbol, parameters: params))
    }

    return specificType
  }

  private func instantiateFunction(template: GenericFunctionTemplate, args: [Type]) throws -> (
    String, Type
  ) {
    guard template.typeParameters.count == args.count else {
      throw SemanticError.typeMismatch(
        expected: "\(template.typeParameters.count) generic arguments",
        got: "\(args.count)"
      )
    }

    let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
    if let cached = instantiatedFunctions[key] {
      return cached
    }

    // 1. Resolve parameters and return type with specific types
    let (functionType, typedBody, params) = try withNewScope {
      for (i, paramInfo) in template.typeParameters.enumerated() {
        try currentScope.defineType(paramInfo.name, type: args[i])
      }

      let returnType = try resolveTypeNode(template.returnType)
      let params = try template.parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }

      // If intrinsic, we return early in checkIntrinsicCall/checkIntrinsicPointerMethod
      
      let (typedBody, functionType) = try checkFunctionBody(params, returnType, template.body)
      return (functionType, typedBody, params)
    }

    if functionType.containsGenericParameter {
      return ("", functionType)
    }

    // 2. Generate Mangled Name using Layout Keys
    let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
    let mangledName = "\(template.name)_\(argLayoutKeys)"

    // 3. Register Global Function if not already generated
    // Skip if intrinsic
    let intrinsicNames = ["alloc_memory", "dealloc_memory", "copy_memory", "move_memory", "ref_count"]
    if !generatedLayouts.contains(mangledName) && !intrinsicNames.contains(template.name) {
      generatedLayouts.insert(mangledName)

      let functionNode = TypedGlobalNode.globalFunction(
        identifier: Symbol(name: mangledName, type: functionType, kind: .function),
        parameters: params,
        body: typedBody
      )
      extraGlobalNodes.append(functionNode)
    }

    instantiatedFunctions[key] = (mangledName, functionType)
    return (mangledName, functionType)
  }

  private func instantiateExtensionMethod(
    baseType: Type,
    structureName: String,
    genericArgs: [Type],
    methodInfo: (typeParams: [(name: String, type: TypeNode?)], method: MethodDeclaration)
  ) throws -> Symbol {
    let (typeParams, method) = methodInfo

    if typeParams.count != genericArgs.count {
      throw SemanticError.typeMismatch(
        expected: "\(typeParams.count) args", got: "\(genericArgs.count)")
    }

    let argLayoutKeys = genericArgs.map { $0.layoutKey }.joined(separator: "_")
    let mangledName = "\(structureName)_\(argLayoutKeys)_\(method.name)"
    let key = "ext:\(mangledName)"

    if let (cachedName, cachedType) = instantiatedFunctions[key] {
      return Symbol(name: cachedName, type: cachedType, kind: .function)
    }

    let (functionType, typedBody, params) = try withNewScope {
      for (i, paramInfo) in typeParams.enumerated() {
        try currentScope.defineType(paramInfo.name, type: genericArgs[i])
      }

      // Define 'self' variable for instance access
      currentScope.define("self", baseType, mutable: false)
      // Define 'Self' type alias for the concrete type
      try currentScope.defineType("Self", type: baseType)

      let returnType = try resolveTypeNode(method.returnType)
      let params = try method.parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }

      // Use checkFunctionBody to handle body scope
      let (typedBody, funcType) = try checkFunctionBody(params, returnType, method.body)
      return (funcType, typedBody, params)
    }

    if !generatedLayouts.contains(mangledName) {
      generatedLayouts.insert(mangledName)
      let kind = getCompilerMethodKind(method.name)
      let functionNode = TypedGlobalNode.globalFunction(
        identifier: Symbol(name: mangledName, type: functionType, kind: .function, methodKind: kind),
        parameters: params,
        body: typedBody
      )
      extraGlobalNodes.append(functionNode)
    }

    instantiatedFunctions[key] = (mangledName, functionType)
    let kind = getCompilerMethodKind(method.name)
    return Symbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
  }

  private func instantiateIntrinsicExtensionMethod(
    baseType: Type,
    structureName: String,
    genericArgs: [Type],
    methodInfo: (typeParams: [(name: String, type: TypeNode?)], method: IntrinsicMethodDeclaration)
  ) throws -> Symbol {
    let (typeParams, method) = methodInfo

    if typeParams.count != genericArgs.count {
      throw SemanticError.typeMismatch(
        expected: "\(typeParams.count) args", got: "\(genericArgs.count)")
    }

    let argLayoutKeys = genericArgs.map { $0.layoutKey }.joined(separator: "_")
    let mangledName = "\(structureName)_\(argLayoutKeys)_\(method.name)"
    let key = "ext:\(mangledName)"

    if let (cachedName, cachedType) = instantiatedFunctions[key] {
      return Symbol(name: cachedName, type: cachedType, kind: .function)
    }

    let (functionType, _, _) = try withNewScope {
      for (i, paramInfo) in typeParams.enumerated() {
        try currentScope.defineType(paramInfo.name, type: genericArgs[i])
      }

      // Define 'self' variable for instance access
      currentScope.define("self", baseType, mutable: false)
      // Define 'Self' type alias for the concrete type
      try currentScope.defineType("Self", type: baseType)

      let returnType = try resolveTypeNode(method.returnType)
      let params = try method.parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }

      // Intrinsic logic: generate dummy body
      let funcType = Type.function(
        parameters: params.map {
          Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
        },
        returns: returnType
      )
      // Dummy body
      let typedBody = TypedExpressionNode.integerLiteral(value: 0, type: .int)

      return (funcType, typedBody, params)
    }

    instantiatedFunctions[key] = (mangledName, functionType)
    let kind = getCompilerMethodKind(method.name)
    return Symbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
  }

  private func unify(
    node: TypeNode, type: Type, inferred: inout [String: Type], typeParams: [String]
  ) throws {
    // print("Unify node: \(node) with type: \(type) (canonical: \(type.canonical))")
    switch node {
    case .identifier(let name):
      if typeParams.contains(name) {
        if let existing = inferred[name] {
          if existing != type {
            throw SemanticError.typeMismatch(expected: existing.description, got: type.description)
          }
        } else {
          inferred[name] = type
        }
      }
    case .inferredSelf:
      break
    case .reference(let inner):
      if case .reference(let innerType) = type {
        try unify(node: inner, type: innerType, inferred: &inferred, typeParams: typeParams)
      }
    case .generic(let base, let args):
      if case .pointer(let element) = type, base == "Pointer", args.count == 1 {
          try unify(node: args[0], type: element, inferred: &inferred, typeParams: typeParams)
      } else if case .structure(let name, _, _, _) = type {
        if let info = layoutToTemplateInfo[name] {
            if info.base == base && info.args.count == args.count {
                for (argNode, argType) in zip(args, info.args) {
                    try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
                }
            }
        }
      }
    }
  }

  private func withNewScope<R>(_ body: () throws -> R) rethrows -> R {
    let previousScope = currentScope
    currentScope = currentScope.createChild()
    defer { currentScope = previousScope }
    return try body()
  }

  private func checkArithmeticOp(_ op: ArithmeticOperator, _ lhs: Type, _ rhs: Type) throws
    -> Type
  {
    if lhs == .int && rhs == .int {
      return .int
    }
    if lhs == .float && rhs == .float {
      return .float
    }
    throw SemanticError.invalidOperation(
      op: String(describing: op), type1: lhs.description, type2: rhs.description)
  }

  private func checkComparisonOp(_ op: ComparisonOperator, _ lhs: Type, _ rhs: Type) throws
    -> Type
  {
    if lhs == rhs {
      return .bool
    }
    throw SemanticError.invalidOperation(
      op: String(describing: op), type1: lhs.description, type2: rhs.description)
  }
}

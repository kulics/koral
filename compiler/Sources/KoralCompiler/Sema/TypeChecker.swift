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

  public init(ast: ASTNode) {
    self.ast = ast

    // Built-in functions
    // printString(message String) Void
    currentScope.define(
      "printString",
      .function(parameters: [Parameter(type: .string, kind: .byVal)], returns: .void),
      mutable: false
    )
    // printInt(value Int) Void
    currentScope.define(
      "printInt",
      .function(parameters: [Parameter(type: .int, kind: .byVal)], returns: .void),
      mutable: false
    )
    // printBool(value Bool) Void
    currentScope.define(
      "printBool",
      .function(parameters: [Parameter(type: .bool, kind: .byVal)], returns: .void),
      mutable: false
    )
  }

  // Changed to return TypedProgram
  public func check() throws -> TypedProgram {
    switch self.ast {
    case .program(let declarations):
      var typedDeclarations: [TypedGlobalNode] = []
      for decl in declarations {
        let typedDecl = try checkGlobalDeclaration(decl)
        typedDeclarations.append(typedDecl)
      }
      // Append instantiated generic types
      typedDeclarations.append(contentsOf: extraGlobalNodes)
      return .program(globalNodes: typedDeclarations)
    }
  }

  private func checkGlobalDeclaration(_ decl: GlobalNode) throws -> TypedGlobalNode {
    switch decl {
    case .globalVariableDeclaration(let name, let typeNode, let value, let isMut):
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name)
      }
      let type = try resolveTypeNode(typeNode)
      let typedValue = try inferTypedExpression(value)
      if typedValue.type != type {
        throw SemanticError.typeMismatch(
          expected: type.description, got: typedValue.type.description)
      }
      currentScope.define(name, type, mutable: isMut)
      return .globalVariable(
        identifier: Symbol(name: name, type: type, kind: .variable(isMut ? .MutableValue : .Value)),
        value: typedValue,
        kind: isMut ? .MutableValue : .Value
      )

    case .globalFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let body):
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name)
      }

      if !typeParameters.isEmpty {
        // Perform declaration-site checking
        try withNewScope {
          for typeParam in typeParameters {
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
          body: body
        )
        currentScope.defineGenericFunctionTemplate(name, template: template)
        return .genericFunctionTemplate(name: name)
      }

      let (functionType, typedBody, params) = try withNewScope {
        // introduce generic type
        for typeParam in typeParameters {
          // Define the new type
          let typeType = Type.structure(
            name: typeParam,
            members: [],
            isGenericInstantiation: false
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
        let (typedBody, functionType) = try checkFunctionBody(params, returnType, body)
        return (functionType, typedBody, params)
      }
      currentScope.define(name, functionType, mutable: false)
      return .globalFunction(
        identifier: Symbol(name: name, type: functionType, kind: .function),
        parameters: params,
        body: typedBody
      )

    case .givenDeclaration(let typeNode, let methods):
      let type = try resolveTypeNode(typeNode)
      guard case .structure(let typeName, _, _) = type else {
        throw SemanticError.invalidOperation(op: "given", type1: type.description, type2: "")
      }

      var typedMethods: [TypedMethodDeclaration] = []

      for method in methods {
        let (methodType, typedBody, params, returnType) = try withNewScope {
          for typeParam in method.typeParameters {
            let typeType = Type.structure(name: typeParam, members: [], isGenericInstantiation: false)
            try currentScope.defineType(typeParam, type: typeType)
          }

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

          let functionType = Type.function(
            parameters: params.map {
              Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
          )
          return (functionType, typedBody, params, returnType)
        }

        let mangledName = "\(typeName)_\(method.name)"
        let methodSymbol = Symbol(name: mangledName, type: methodType, kind: .function)

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

    case .globalTypeDeclaration(let name, let typeParameters, let parameters):
      // Check if type already exists
      if currentScope.lookupType(name) != nil {
        throw SemanticError.duplicateTypeDefinition(name)
      }
      
      if !typeParameters.isEmpty {
          let template = GenericTemplate(name: name, typeParameters: typeParameters, parameters: parameters)
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
        isGenericInstantiation: false
      )
      try currentScope.defineType(name, type: typeType)

      return .globalTypeDeclaration(
        identifier: Symbol(name: name, type: typeType, kind: .type),
        parameters: params
      )
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
      let typedElse = try inferTypedExpression(elseBranch)
      if typedThen.type != typedElse.type {
        throw SemanticError.typeMismatch(
          expected: typedThen.type.description,
          got: typedElse.type.description
        )
      }
      return .ifExpression(
        condition: typedCondition,
        thenBranch: typedThen,
        elseBranch: typedElse,
        type: typedThen.type
      )

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
      // Check if callee is a generic instantiation (Constructor call or Function call)
      if case .genericInstantiation(let base, let args) = callee {
        if let template = currentScope.lookupGenericTemplate(base) {
          let resolvedArgs = try args.map { try resolveTypeNode($0) }
          let instantiatedType = try instantiate(template: template, args: resolvedArgs)

          guard case .structure(let typeName, let members, _) = instantiatedType else {
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
            typedArguments.append(typedArg)
          }

          return .typeConstruction(
            identifier: Symbol(name: typeName, type: instantiatedType, kind: .type),
            arguments: typedArguments,
            type: instantiatedType
          )
        } else if let template = currentScope.lookupGenericFunctionTemplate(base) {
          let resolvedArgs = try args.map { try resolveTypeNode($0) }
          let (instantiatedName, instantiatedType) = try instantiateFunction(template: template, args: resolvedArgs)

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
            typedArguments.append(typedArg)
          }

          return .call(
            callee: .variable(identifier: Symbol(name: instantiatedName, type: instantiatedType, kind: .function)),
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
            typedArguments.append(typedArg)
            try unify(node: param.type, type: typedArg.type, inferred: &inferred, typeParams: template.typeParameters)
          }

          let resolvedArgs = try template.typeParameters.map { param -> Type in
            guard let type = inferred[param] else {
              throw SemanticError.typeMismatch(expected: "inferred type for \(param)", got: "unknown")
            }
            return type
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
          guard case .structure(_, let parameters, _) = type else {
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
            typedArguments.append(typedArg)
          }

          return .typeConstruction(
            identifier: Symbol(name: name, type: type, kind: .type),
            arguments: typedArguments,
            type: type
          )
        }
      }

      let typedCallee = try inferTypedExpression(callee)

      // Method call
      if case .methodReference(let base, let method, let methodType) = typedCallee {
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

          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params.dropFirst()) {
            let typedArg = try inferTypedExpression(arg)
            if typedArg.type != param.type {
              throw SemanticError.typeMismatch(
                expected: param.type.description,
                got: typedArg.type.description
              )
            }
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

    case .memberPath(let baseExpr, let path):
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
        if case .structure(_, let members, _) = typeToLookup {
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
          }

          if case .structure(let typeName, _, _) = typeToLookup {
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

  // 新增用于返回带类型的语句的检查函数
  private func checkStatement(_ stmt: StatementNode) throws -> TypedStatementNode {
    switch stmt {
    case .variableDeclaration(let name, let typeNode, let value, let mutable):
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

      currentScope.define(name, type, mutable: mutable)
      return .variableDeclaration(
        identifier: Symbol(
          name: name, type: type, kind: mutable ? .variable(.MutableValue) : .variable(.Value)),
        value: typedValue,
        mutable: mutable
      )

    case .assignment(let target, let value):
      switch target {
      case .variable(let name):
        guard let varType = currentScope.lookup(name) else {
          throw SemanticError.undefinedVariable(name)
        }
        guard currentScope.isMutable(name) else {
          throw SemanticError.assignToImmutable(name)
        }
        let typedValue = try inferTypedExpression(value)
        if typedValue.type != varType {
          throw SemanticError.typeMismatch(
            expected: varType.description, got: typedValue.type.description)
        }
        return .assignment(
          target: .variable(
            identifier: Symbol(name: name, type: varType, kind: .variable(.MutableValue))),
          value: typedValue
        )

      case .memberAccess(let base, let memberPath):
        // First check that the base variable exists
        guard let baseType = currentScope.lookup(base) else {
          throw SemanticError.undefinedVariable(base)
        }

        var currentType = baseType
        var typedPath: [Symbol] = []

        // Validate member path: 仅最后一段字段需要可变
        for (idx, memberName) in memberPath.enumerated() {
          let isLast = idx == memberPath.count - 1
          // Check that current type is a user-defined type
          guard case .structure(let typeName, let members, _) = currentType else {
            throw SemanticError.invalidOperation(
              op: "member access",
              type1: currentType.description,
              type2: ""
            )
          }

          // Find the member in the type definition
          guard let member = members.first(where: { $0.name == memberName }) else {
            throw SemanticError.undefinedMember(memberName, typeName)
          }
          // 只有最后一个成员需要是可变字段
          if isLast {
            guard member.mutable else {
              throw SemanticError.immutableFieldAssignment(
                type: typeName, field: memberName)
            }
          }
          let memberIdentifier = Symbol(
            name: memberName, type: member.type,
            kind: .variable(member.mutable ? .MutableValue : .Value))
          typedPath.append((memberIdentifier))

          // Update current type for next iteration
          currentType = member.type
        }

        // Check value type matches final member type
        let finalMemberType = typedPath.last!.type
        let typedValue = try inferTypedExpression(value)
        if typedValue.type != finalMemberType {
          throw SemanticError.typeMismatch(
            expected: finalMemberType.description, got: typedValue.type.description)
        }

        return .assignment(
          target: .memberAccess(
            // 不再要求基变量可变；只根据类型声明的字段可变性做检查
            base: Symbol(name: base, type: baseType, kind: .variable(.Value)),
            memberPath: typedPath
          ),
          value: typedValue
        )
      }

    case .compoundAssignment(let target, let op, let value):
      let typedTarget: TypedAssignmentTarget
      let targetType: Type

      switch target {
      case .variable(let name):
        guard let varType = currentScope.lookup(name) else {
          throw SemanticError.undefinedVariable(name)
        }
        guard currentScope.isMutable(name) else {
          throw SemanticError.assignToImmutable(name)
        }
        typedTarget = .variable(
          identifier: Symbol(name: name, type: varType, kind: .variable(.MutableValue)))
        targetType = varType

      case .memberAccess(let base, let memberPath):
        guard let baseType = currentScope.lookup(base) else {
          throw SemanticError.undefinedVariable(base)
        }

        var currentType = baseType
        var typedPath: [Symbol] = []

        for (idx, memberName) in memberPath.enumerated() {
          let isLast = idx == memberPath.count - 1
          guard case .structure(let typeName, let members, _) = currentType else {
            throw SemanticError.invalidOperation(
              op: "member access",
              type1: currentType.description,
              type2: ""
            )
          }

          guard let member = members.first(where: { $0.name == memberName }) else {
            throw SemanticError.undefinedMember(memberName, typeName)
          }
          if isLast {
            guard member.mutable else {
              throw SemanticError.immutableFieldAssignment(
                type: typeName, field: memberName)
            }
          }
          let memberIdentifier = Symbol(
            name: memberName, type: member.type,
            kind: .variable(member.mutable ? .MutableValue : .Value))
          typedPath.append((memberIdentifier))

          currentType = member.type
        }

        typedTarget = .memberAccess(
          base: Symbol(name: base, type: baseType, kind: .variable(.Value)),
          memberPath: typedPath
        )
        targetType = typedPath.last!.type
      }

      let typedValue = try inferTypedExpression(value)
      let resultType = try checkArithmeticOp(
        compoundOpToArithmeticOp(op), targetType, typedValue.type)

      if resultType != targetType {
        throw SemanticError.typeMismatch(
          expected: targetType.description, got: resultType.description)
      }

      return .compoundAssignment(target: typedTarget, operator: op, value: typedValue)

    case .expression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      return .expression(typedExpr)
    }
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
  private func resolveTypeNode(_ node: TypeNode) throws -> Type {
    switch node {
    case .identifier(let name):
      guard let t = currentScope.resolveType(name) else {
        throw SemanticError.undefinedType(name)
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

    let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
    if let cached = instantiatedTypes[key] {
      return cached
    }

    // 1. Resolve members with specific types
    var resolvedMembers: [(name: String, type: Type, mutable: Bool)] = []
    try withNewScope {
      for (i, paramName) in template.typeParameters.enumerated() {
        try currentScope.defineType(paramName, type: args[i])
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
    let specificType = Type.structure(name: layoutName, members: resolvedMembers, isGenericInstantiation: true)
    instantiatedTypes[key] = specificType

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
        for (i, paramName) in template.typeParameters.enumerated() {
          try currentScope.defineType(paramName, type: args[i].canonical)
        }
        for param in template.parameters {
          let fieldType = try resolveTypeNode(param.type)
          canonicalMembers.append((name: param.name, type: fieldType, mutable: param.mutable))
        }
      }

      // Create Canonical Type
      let canonicalType = Type.structure(name: layoutName, members: canonicalMembers, isGenericInstantiation: true)
      
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

  private func instantiateFunction(template: GenericFunctionTemplate, args: [Type]) throws -> (String, Type) {
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
      for (i, paramName) in template.typeParameters.enumerated() {
        try currentScope.defineType(paramName, type: args[i])
      }
      
      let returnType = try resolveTypeNode(template.returnType)
      let params = try template.parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }
      
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
    if !generatedLayouts.contains(mangledName) {
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

  private func unify(node: TypeNode, type: Type, inferred: inout [String: Type], typeParams: [String]) throws {
    switch node {
    case .identifier(let name):
      if typeParams.contains(name) {
        if let existing = inferred[name] {
          if existing != type {
             // Mismatch
          }
        } else {
          inferred[name] = type
        }
      }
    case .reference(let inner):
      if case .reference(let innerType) = type {
        try unify(node: inner, type: innerType, inferred: &inferred, typeParams: typeParams)
      }
    default:
      break
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

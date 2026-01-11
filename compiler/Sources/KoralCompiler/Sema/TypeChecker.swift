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
  private var currentFunctionReturnType: Type?
  private var loopDepth: Int = 0

  public init(ast: ASTNode) {
    self.ast = ast
  }

  private func getCompilerMethodKind(_ name: String) -> CompilerMethodKind {
    switch name {
    case "__drop": return .drop
    case "__at": return .at
    case "__at_mut": return .atMut
    default: return .normal
    }
  }

  // Changed to return TypedProgram
  public func check() throws -> TypedProgram {
    switch self.ast {
    case .program(let declarations):
      var typedDeclarations: [TypedGlobalNode] = []
      // Clear any previous state
      extraGlobalNodes.removeAll()
      
      for decl in declarations {
        let startIndex = extraGlobalNodes.count
        
        if let typedDecl = try checkGlobalDeclaration(decl) {
          // Append any dependencies generated during this declaration (e.g. instantiated generics)
          // BEFORE the declaration itself to satisfy C definition order.
          if extraGlobalNodes.count > startIndex {
              let newDependencies = extraGlobalNodes[startIndex..<extraGlobalNodes.count]
              typedDeclarations.append(contentsOf: newDependencies)
          }
          typedDeclarations.append(typedDecl)
        } else {
             // Even if decl is nil (e.g. intrinsic decl), we might have generated dependencies
             if extraGlobalNodes.count > startIndex {
                  let newDependencies = extraGlobalNodes[startIndex..<extraGlobalNodes.count]
                  typedDeclarations.append(contentsOf: newDependencies)
             }
        }
      }
      // Do NOT append extraGlobalNodes again
      return .program(globalNodes: typedDeclarations)
    }
  }

  private func checkGlobalDeclaration(_ decl: GlobalNode) throws -> TypedGlobalNode? {
    switch decl {
    case .globalUnionDeclaration(let name, let typeParameters, let cases, let access, let isCopy, let line):
      self.currentLine = line
      if currentScope.hasTypeDefinition(name) {
          throw SemanticError.duplicateDefinition(name, line: line)
      }

      if !typeParameters.isEmpty {
          let template = GenericUnionTemplate(name: name, typeParameters: typeParameters, cases: cases, access: access, isCopy: isCopy)
          currentScope.defineGenericUnionTemplate(name, template: template)
          return .genericTypeTemplate(name: name)
      }

      // Placeholder for recursion
      let placeholder = Type.union(name: name, cases: [], isGenericInstantiation: false, isCopy: isCopy)
      try currentScope.defineType(name, type: placeholder, line: line)

      var unionCases: [UnionCase] = []
      for c in cases {
          var params: [(name: String, type: Type)] = []
          for p in c.parameters {
              let resolved = try resolveTypeNode(p.type)
              if resolved == placeholder {
                   throw SemanticError.invalidOperation(op: "Direct recursion in union \(name) not allowed (use ref)", type1: p.name, type2: "")
              }
              params.append((name: p.name, type: resolved))
          }
          unionCases.append(UnionCase(name: c.name, parameters: params))
      }

      if isCopy {
          for c in unionCases {
              for param in c.parameters {
                  if !param.type.isCopy {
                      throw SemanticError.invalidOperation(op: "Copy union \(name) cannot contain non-Copy field \(param.name) of type \(param.type)", type1: "", type2: "")
                  }
              }
          }
      }

      let type = Type.union(name: name, cases: unionCases, isGenericInstantiation: false, isCopy: isCopy)
      // Replace placeholder with final type
      currentScope.overwriteType(name, type: type)
      return .globalUnionDeclaration(identifier: Symbol(name: name, type: type, kind: .type), cases: unionCases)

    case .globalVariableDeclaration(let name, let typeNode, let value, let isMut, _, let line):
      self.currentLine = line
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name, line: line)
      }
      let type = try resolveTypeNode(typeNode)
      let typedValue = try inferTypedExpression(value)
      if typedValue.type != .never && typedValue.type != type {
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
      let name, let typeParameters, let parameters, let returnTypeNode, let body, let access, let line):
      self.currentLine = line
      if currentScope.hasFunctionDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: line)
      }

      if !typeParameters.isEmpty {
        // Define placeholder template for recursion
        let placeholderTemplate = GenericFunctionTemplate(
            name: name,
            typeParameters: typeParameters,
            parameters: parameters,
            returnType: returnTypeNode,
            body: ExpressionNode.call(callee: .identifier("panic"), arguments: [.stringLiteral("recursion")]),
            access: access
        )
        currentScope.defineGenericFunctionTemplate(name, template: placeholderTemplate)

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

          // Perform declaration-site checking
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
      
      // Define placeholder for recursion
      currentScope.define(name, functionType, mutable: false)

      let (typedBody, _) = try checkFunctionBody(params, returnType, body)
      
      return .globalFunction(
        identifier: Symbol(name: name, type: functionType, kind: .function),
        parameters: params,
        body: typedBody
      )

    case .intrinsicFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let access, let line):
      self.currentLine = line
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name, line: line)
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

    case .givenDeclaration(let typeParams, let typeNode, let methods, let line):
      self.currentLine = line
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
      let typeName: String
      if case .structure(let name, _, _, _) = type {
          typeName = name
      } else if case .union(let name, _, _, _) = type {
          typeName = name
      } else {
        throw SemanticError.invalidOperation(op: "given extends only struct or union", type1: type.description, type2: "")
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
          return (functionType, params, returnType)
        }

        let mangledName = "\(typeName)_\(method.name)"
        let methodKind = getCompilerMethodKind(method.name)
        let methodSymbol = Symbol(
          name: mangledName,
          type: methodType,
          kind: .function,
          methodKind: methodKind
        )

        extensionMethods[typeName]![method.name] = methodSymbol
        methodInfos.append(
          GivenMethodInfo(method: method, symbol: methodSymbol, params: params, returnType: returnType)
        )
      }

      // Pass 2: typecheck bodies with full method set available.
      for info in methodInfos {
        let typedBody = try withNewScope {
          for (typeParam, _) in info.method.typeParameters {
            let typeType = Type.structure(
              name: typeParam, members: [], isGenericInstantiation: false, isCopy: false)
            try currentScope.defineType(typeParam, type: typeType)
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

    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let line):
      self.currentLine = line
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
      if case .structure(let name, _, _, _) = type {
          typeName = name
      } else if case .union(let name, _, _, _) = type {
          typeName = name
      } else {
        throw SemanticError.invalidOperation(op: "given extends only struct or union", type1: type.description, type2: "")
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

    case .globalStructDeclaration(let name, let typeParameters, let parameters, _, let isCopy, let line):
      self.currentLine = line
      // Check if type already exists
      if currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateTypeDefinition(name)
      }

      if !typeParameters.isEmpty {
        let template = GenericStructTemplate(
          name: name, typeParameters: typeParameters, parameters: parameters, isCopy: isCopy)
        currentScope.defineGenericStructTemplate(name, template: template)
        return .genericTypeTemplate(name: name)
      }

      // Placeholder for recursion
      let placeholder = Type.structure(name: name, members: [], isGenericInstantiation: false, isCopy: isCopy)
      try currentScope.defineType(name, type: placeholder, line: line)

      let params = try parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        if paramType == placeholder {
           throw SemanticError.invalidOperation(op: "Direct recursion in struct \(name) not allowed (use ref)", type1: param.name, type2: "")
        }
        return Symbol(
          name: param.name, type: paramType,
          kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
      }

      if isCopy {
        for param in params {
            if !param.type.isCopy {
                throw SemanticError.invalidOperation(op: "Copy type \(name) cannot contain non-Copy field \(param.name) of type \(param.type)", type1: "", type2: "")
            }
        }
      }

      // Define the new type
      let typeType = Type.structure(
        name: name,
        members: params.map { (name: $0.name, type: $0.type, mutable: $0.isMutable()) },
        isGenericInstantiation: false,
        isCopy: isCopy
      )
      currentScope.overwriteType(name, type: typeType)

      return .globalStructDeclaration(
        identifier: Symbol(name: name, type: typeType, kind: .type),
        parameters: params
      )

    case .intrinsicTypeDeclaration(let name, let typeParameters, _, let line):
      self.currentLine = line
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
      case "Never": type = .never
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
        return .globalStructDeclaration(identifier: dummySymbol, parameters: [])
      } else {
        // For generic intrinsics (like Pointer<T>), we still need a template definition
        // so the type checker knows it accepts distinct type parameters.
        let template = GenericStructTemplate(name: name, typeParameters: typeParameters, parameters: [], isCopy: true)
        currentScope.defineGenericStructTemplate(name, template: template)
        return .genericTypeTemplate(name: name)
      }
    }
  }

  private func checkFunctionBody(
    _ params: [Symbol],
    _ returnType: Type,
    _ body: ExpressionNode
  ) throws -> (TypedExpressionNode, Type) {
    let previousReturnType = currentFunctionReturnType
    currentFunctionReturnType = returnType
    defer { currentFunctionReturnType = previousReturnType }

    return try withNewScope {
      // Add parameters to new scope
      for param in params {
        currentScope.define(param.name, param.type, mutable: param.isMutable())
      }

      let typedBody = try inferTypedExpression(body)
      if typedBody.type != .never && typedBody.type != returnType {
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

  private func convertExprToTypeNode(_ expr: ExpressionNode) throws -> TypeNode {
     switch expr {
     case .identifier(let name):
         return .identifier(name)
     case .subscriptExpression(let base, let args):
         if case .identifier(let baseName) = base {
             let typeArgs = try args.map { try convertExprToTypeNode($0) }
             return .generic(base: baseName, args: typeArgs)
         }
         throw SemanticError.invalidOperation(op: "Complex type expression not supported", type1: "", type2: "")
     default:
         throw SemanticError.typeMismatch(expected: "Type Identifier", got: String(describing: expr))
     }
  }

  // 新增用于返回带类型的表达式的类型推导函数
  private func inferTypedExpression(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .integerLiteral(let value):
      return .integerLiteral(value: value, type: .int)

    case .floatLiteral(let value):
      return .floatLiteral(value: value, type: .float64)

    case .stringLiteral(let value):
      if let stringType = currentScope.lookupType("String") {
        return .stringLiteral(value: value, type: stringType)
      }
      return .stringLiteral(value: value, type: .string)

    case .booleanLiteral(let value):
      return .booleanLiteral(value: value, type: .bool)

    case .matchExpression(let subject, let cases, _):
        let typedSubject = try inferTypedExpression(subject)
        // Auto-deref subject type for pattern matching
        var subjectType = typedSubject.type
        if case .reference(let inner) = subjectType {
            subjectType = inner
        }
        
        // Check Move Semantics
        if !typedSubject.type.isCopy {
            checkMove(typedSubject)
        }
        
        var typedCases: [TypedMatchCase] = []
        var resultType: Type?
        
        for c in cases {
            try withNewScope {
              let (pattern, vars) = try checkPattern(c.pattern, subjectType: subjectType)
              for (name, mut, type) in vars {
                currentScope.define(name, type, mutable: mut)
              }
              let typedBody = try inferTypedExpression(c.body)
              if let rt = resultType {
                     if typedBody.type != .never {
                        if rt == .never {
                             // Previous cases were all Never, this is the first concrete type
                             resultType = typedBody.type
                        } else if typedBody.type != rt {
                             throw SemanticError.typeMismatch(expected: rt.description, got: typedBody.type.description)
                        }
                     }
                } else {
                    resultType = typedBody.type
                }
                typedCases.append(TypedMatchCase(pattern: pattern, body: typedBody))
            }
        }
        return .matchExpression(subject: typedSubject, cases: typedCases, type: resultType ?? .void)

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
        var blockType: Type = .void // Default if no final expression
        var foundNever = false
        
        for stmt in statements {
          let typedStmt = try checkStatement(stmt)
          typedStatements.append(typedStmt)
          
          switch typedStmt {
          case .expression(let expr):
            if expr.type == .never {
              blockType = .never
              foundNever = true
            }
          case .return, .break, .continue:
            blockType = .never
            foundNever = true
          default:
            break
          }
        }
        
        if let finalExpr = finalExpression {
          let typedFinalExpr = try inferTypedExpression(finalExpr)
          // If we already found a Never statement, the block is Never regardless of final expr?
          // Actually, if a statement is Never, the final expression is unreachable.
          // For now, let's respect final expression type if reachable, or override if Never.
          if foundNever {
             // Block is forced to Never
             blockType = .never
          } else {
             blockType = typedFinalExpr.type
          }
           return .blockExpression(
            statements: typedStatements, finalExpression: typedFinalExpr,
            type: blockType)
        }
        
        if foundNever { blockType = .never }
        
        return .blockExpression(
          statements: typedStatements, finalExpression: nil, type: blockType)
      }

    case .arithmeticExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) || isFloatType(typedLeft.type) {
          typedRight = coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type,
           isIntegerType(typedRight.type) || isFloatType(typedRight.type) {
          typedLeft = coerceLiteral(typedLeft, to: typedRight.type)
        }
      }
      let resultType = try checkArithmeticOp(op, typedLeft.type, typedRight.type)
      return .arithmeticExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

    case .comparisonExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) || isFloatType(typedLeft.type) {
          typedRight = coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type,
           isIntegerType(typedRight.type) || isFloatType(typedRight.type) {
          typedLeft = coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      let resultType = try checkComparisonOp(op, typedLeft.type, typedRight.type)
      return .comparisonExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

    case .letExpression(let name, let typeNode, let value, let mutable, let body):
      var typedValue = try inferTypedExpression(value)
      checkMove(typedValue)

      if let typeNode = typeNode {
        let type = try resolveTypeNode(typeNode)
        typedValue = coerceLiteral(typedValue, to: type)
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
        
        let resultType: Type
        if typedThen.type == typedElse.type {
            resultType = typedThen.type
        } else if typedThen.type == .never {
             resultType = typedElse.type
        } else if typedElse.type == .never {
             resultType = typedThen.type
        } else {
             throw SemanticError.typeMismatch(
                expected: typedThen.type.description,
                got: typedElse.type.description
             )
        }
        
        return .ifExpression(
          condition: typedCondition, thenBranch: typedThen, elseBranch: typedElse,
          type: resultType)
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
      loopDepth += 1
      defer { loopDepth -= 1 }
      let typedBody = try inferTypedExpression(body)
      return .whileExpression(
        condition: typedCondition,
        body: typedBody,
        type: .void
      )

    case .call(let callee, let arguments):
      // Check if callee is a generic instantiation (Constructor call or Function call)
      if case .genericInstantiation(let base, let args) = callee {
        if let template = currentScope.lookupGenericStructTemplate(base) {
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
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: expectedMember.type)
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

          if base == "dealloc_memory" {
             let resolvedArgs = try args.map { try resolveTypeNode($0) }
             guard resolvedArgs.count == 1 else { throw SemanticError.typeMismatch(expected: "1 generic arg", got: "\(resolvedArgs.count)") }
             // We don't need T, but we checked args count.
             
             guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: base, expected: 1, got: arguments.count) }
             let ptrExpr = try inferTypedExpression(arguments[0])
             // Check pointer type? Sema checks this later for normal calls, but here we do it maybe?
             // Actually, `ptrExpr.type` should match `[T]Pointer`.
             return .intrinsicCall(.deallocMemory(ptr: ptrExpr))
          }

          if base == "ref_count" {
             _ = try args.map { try resolveTypeNode($0) }
             guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: base, expected: 1, got: arguments.count) }
             let val = try inferTypedExpression(arguments[0])
             return .intrinsicCall(.refCount(val: val))
          }
          if base == "copy_memory" {
             _ = try args.map { try resolveTypeNode($0) }
             guard arguments.count == 3 else { throw SemanticError.invalidArgumentCount(function: base, expected: 3, got: arguments.count) }
             let d = try inferTypedExpression(arguments[0])
             let s = try inferTypedExpression(arguments[1])
             let c = try inferTypedExpression(arguments[2])
             return .intrinsicCall(.copyMemory(dest: d, source: s, count: c))
          }
           if base == "move_memory" {
             _ = try args.map { try resolveTypeNode($0) }
             guard arguments.count == 3 else { throw SemanticError.invalidArgumentCount(function: base, expected: 3, got: arguments.count) }
             let d = try inferTypedExpression(arguments[0])
             let s = try inferTypedExpression(arguments[1])
             let c = try inferTypedExpression(arguments[2])
             return .intrinsicCall(.moveMemory(dest: d, source: s, count: c))
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
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: expectedParam.type)
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

      
      // Resolve Callee (Check Union Constructor)
      var preResolvedCallee: TypedExpressionNode? = nil
      do {
          preResolvedCallee = try inferTypedExpression(callee)
      } catch is SemanticError {
          // Fallthrough
          preResolvedCallee = nil
      }

      if let resolved = preResolvedCallee, case .variable(let symbol) = resolved {
         if case .function(_, let returnType) = symbol.type, case .union(let uName, _, _, _) = returnType {
             // Check if symbol name is uName.CaseName
             if symbol.name.starts(with: uName + ".") {
                  let caseName = String(symbol.name.dropFirst(uName.count + 1))
                  let params = symbol.type.functionParameters! 
                  
                  if arguments.count != params.count {
                      throw SemanticError.invalidArgumentCount(function: symbol.name, expected: params.count, got: arguments.count)
                  }
                  
                  var typedArgs: [TypedExpressionNode] = []
                  for (arg, param) in zip(arguments, params) {
                      let typedArg = try inferTypedExpression(arg)
                      if typedArg.type != param.type {
                          throw SemanticError.typeMismatch(expected: param.type.description, got: typedArg.type.description)
                      }
                      checkMove(typedArg)
                      typedArgs.append(typedArg)
                  }
                  
                  return .unionConstruction(type: returnType, caseName: caseName, arguments: typedArgs)
             }
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
            var typedArg = try inferTypedExpression(argExpr)
            do {
              let expectedType = try resolveTypeNode(param.type)
              typedArg = coerceLiteral(typedArg, to: expectedType)
            } catch let error as SemanticError {
              // During implicit generic inference, parameter types may reference template
              // type parameters (e.g. `T`, `[T]Pointer`) which are not in the caller scope.
              // Skip literal coercion in that case; we'll infer `T` via unify().
              if case .undefinedType(let name) = error.kind,
                 template.typeParameters.contains(where: { $0.name == name }) {
                // no-op
              } else {
                throw error
              }
            }
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
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: expectedMember.type)
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

        // Secondary guard: if the resolved callee is a special compiler method, block explicit calls
        if case .variable(let sym) = typedCallee, sym.methodKind != .normal {
          throw SemanticError.invalidOperation(op: "Explicit call to \(sym.name) is not allowed", type1: "", type2: "")
        }

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
              } else if case .reference(let inner) = base.type, inner == firstParam.type {
                // 尝试自动解引用：期望 T，实际是 T ref
                // Only safe for Copy types (otherwise this would implicitly move).
                if inner.isCopy {
                  finalBase = .derefExpression(expression: base, type: inner)
                } else {
                  throw SemanticError.invalidOperation(
                    op: "implicit deref", type1: base.type.description,
                    type2: firstParam.type.description)
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
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: param.type)
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
          var typedArg = try inferTypedExpression(arg)
          typedArg = coerceLiteral(typedArg, to: param.type)
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
      let resolvedSubscript = try resolveSubscript(base: typedBase, args: typedArguments, isMut: false)
      
      // Auto-deref: If subscript returns Ref<T>, convert to T via Deref node
      if case .reference(let inner) = resolvedSubscript.type {
          return .derefExpression(expression: resolvedSubscript, type: inner)
      }
      return resolvedSubscript

    case .memberPath(let baseExpr, let path):
      // 1. Check if baseExpr is a Type (Generic Instantiation) for static method access or Union Constructor
      if case .genericInstantiation(let baseName, let args) = baseExpr {
         if let template = currentScope.lookupGenericStructTemplate(baseName) {
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
         } else if let template = currentScope.lookupGenericUnionTemplate(baseName) {
             let resolvedArgs = try args.map { try resolveTypeNode($0) }
             let type = try instantiateUnion(template: template, args: resolvedArgs)
             
             if path.count == 1 {
                 let memberName = path[0]
                 if case .union(let uName, let cases, _, _) = type {
                     if let c = cases.first(where: { $0.name == memberName }) {
                         let symbolName = "\(uName).\(memberName)"
                         let paramTypes = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
                         let constructorType = Type.function(parameters: paramTypes, returns: type)
                         let symbol = Symbol(name: symbolName, type: constructorType, kind: .variable(.Value))
                         return .variable(identifier: symbol)
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
               }
               
               if let method = methodSymbol {
                   // Return the function symbol directly (static function reference)
                   return .variable(identifier: method)
               }
           }
      }

      // 3. Union Constructor Access via member path (e.g., UnionType.CaseName)
      // This is not a "Function variable" but a direct Constructor node which expects a Call parent.
      // However, we are inside `memberPath`. The parser sees `Option.Some(1)` as Call(MemberPath(Option, Some), [1]).
      // So here we should return a "Function" type that is the constructor.
      if case .identifier(let name) = baseExpr, let type = currentScope.lookupType(name) {
          if path.count == 1 {
              let memberName = path[0]
              if case .union(_, let cases, _, _) = type {
                  if let c = cases.first(where: { $0.name == memberName }) {
                      // Found Union Case. Return a synthetic Function Symbol representing the constructor.
                      let paramTypes = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
                      let funcType = Type.function(parameters: paramTypes, returns: type)
                      let symbol = Symbol(name: "\(name).\(memberName)", type: funcType, kind: .function)
                      // We abuse .variable node to transport this symbol up to the Call handler?
                      // Or creating a specialized Node?
                      // If we return .variable(symbol), the Call handler will see a function variable and try to "call" it.
                      // That works for normal functions. For Union constructor, we need to distinguish it in `checkCall` to emit `unionConstruction`.
                      
                      // We can mark the symbol name specially or check effectively later.
                      // Better: Create a distinct SymbolKind for Constructor? Or check if Symbol name matches Union.Case.
                      
                      // Actually, let's keep it simple. If we return a Variable(Function), checkCall will try to invoke it.
                      // But `checkCall` logic usually handles `variable` node.
                      return .variable(identifier: symbol)
                  }
              }
          }
      }

      
      // infer base
      let inferredBase = try inferTypedExpression(baseExpr)

      // access member optimization: peel auto-deref to access ref directly
      let typedBase: TypedExpressionNode
      if case .derefExpression(let inner, _) = inferredBase {
          typedBase = inner
      } else {
          typedBase = inferredBase
      }

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

            var isGenericInstance = false
            if case .structure(_, _, let isGen, _) = typeToLookup { isGenericInstance = isGen }
            else if case .union(_, _, let isGen, _) = typeToLookup { isGenericInstance = isGen }
            
            if isGenericInstance, let info = layoutToTemplateInfo[typeName] {

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
      case "exit":
           guard arguments.count == 1 else { throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count) }
           let code = try inferTypedExpression(arguments[0])
           if code.type != .int {
               throw SemanticError.typeMismatch(expected: "Int", got: code.type.description)
           }
           return .intrinsicCall(.exit(code: code))
      case "abort":
            guard arguments.count == 0 else { throw SemanticError.invalidArgumentCount(function: name, expected: 0, got: arguments.count) }
            return .intrinsicCall(.abort)

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
           var val = try inferTypedExpression(args[0])
           val = coerceLiteral(val, to: elementType)
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
         var val = try inferTypedExpression(args[0])
         val = coerceLiteral(val, to: elementType)
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
      var typedValue = try inferTypedExpression(value)
      let type: Type
      
      if let typeNode = typeNode {
        type = try resolveTypeNode(typeNode)
        typedValue = coerceLiteral(typedValue, to: type)
        if typedValue.type != .never && typedValue.type != type {
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
        var typedValue = try inferTypedExpression(value)
        typedValue = coerceLiteral(typedValue, to: typedTarget.type)
      
        if typedValue.type != .never && typedTarget.type != typedValue.type {
          throw SemanticError.typeMismatch(expected: typedTarget.type.description, got: typedValue.type.description)
      }
      
      checkMove(typedValue)
      
      return .assignment(target: typedTarget, value: typedValue)
      
    case .compoundAssignment(let target, let op, let value, let line):
      self.currentLine = line
      let typedTarget = try resolveLValue(target)
      let typedValue = coerceLiteral(try inferTypedExpression(value), to: typedTarget.type)
      // Check arithmetic op validity?
      let _ = try checkArithmeticOp(compoundOpToArithmeticOp(op), typedTarget.type, typedValue.type)
      checkMove(typedValue)
      return .compoundAssignment(target: typedTarget, operator: op, value: typedValue)

    case .expression(let expr, let line):
      self.currentLine = line
      return .expression(try inferTypedExpression(expr))

    case .return(let value, let line):
      self.currentLine = line
      guard let returnType = currentFunctionReturnType else {
        throw SemanticError.invalidOperation(op: "return outside of function", type1: "", type2: "")
      }

      if let value = value {
        if returnType == .void {
          throw SemanticError.typeMismatch(expected: "Void", got: "non-Void")
        }

        var typedValue = try inferTypedExpression(value)
        typedValue = coerceLiteral(typedValue, to: returnType)
        if typedValue.type != .never && typedValue.type != returnType {
          throw SemanticError.typeMismatch(expected: returnType.description, got: typedValue.type.description)
        }
        checkMove(typedValue)
        return .return(value: typedValue)
      }

      if returnType != .void {
        throw SemanticError.typeMismatch(expected: returnType.description, got: "Void")
      }
      return .return(value: nil)

    case .break(let line):
      self.currentLine = line
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "break outside of while", type1: "", type2: "")
      }
      return .break

    case .continue(let line):
      self.currentLine = line
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "continue outside of while", type1: "", type2: "")
      }
      return .continue
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
       
       let inferredBase = try inferTypedExpression(base)
       // Optimization: Peel auto-deref for lvalue resolution
       let typedBase: TypedExpressionNode
       if case .derefExpression(let inner, _) = inferredBase {
           typedBase = inner
       } else {
           typedBase = inferredBase
       }
       
       // Now resolve path members on typedBase.
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
       // Relaxed restriction: Base doesn't need to be LValue strictly. 
       // Similar to member access, we infer the base expression.
       // If __at(self ref) requires address, inferTypedExpression usually results in a value that has storage (variable) anyway.
       let typedBase = try inferTypedExpression(base)
       
       let typedArgs = try args.map { try inferTypedExpression($0) }
       let resolved = try resolveSubscript(base: typedBase, args: typedArgs, isMut: true)
       
       // LValue resolution: Subscript returns Ref<T>, so we wrap in Deref to represent the LValue T
       if case .reference(let inner) = resolved.type {
           return .derefExpression(expression: resolved, type: inner)
       }
       return resolved

    case .derefExpression(let inner):
        let typedInner = try inferTypedExpression(inner)
        if case .reference(let innerType) = typedInner.type {
             return .derefExpression(expression: typedInner, type: innerType)
        }
        throw SemanticError.typeMismatch(expected: "Reference", got: typedInner.type.description)

    default:
       throw SemanticError.invalidOperation(op: "assignment target", type1: String(describing: expr), type2: "")
    }
  }

  private func resolveSubscript(base: TypedExpressionNode, args: [TypedExpressionNode], isMut: Bool) throws -> TypedExpressionNode {
      let methodName = isMut ? "__at_mut" : "__at"
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
      
      // Determine return type (auto deref logic REMOVED for clarity, we return what method returns)
      // Actually, standard subscript behavior:
      // If method returns Ref, subscript expression is LValue of inner type.
      // But `type` property of TypedExpressionNode usually reflects the Value type for LValues?
      // Checkout `resolveLValue`...
      
      // If `__at` returns `Int ref`, then the expression has type `Int ref`. 
      // If we strip ref here, we say expression is `Int`.
      // But `CodeGen` needs to know if it's a pointer or value.
      
      // Let's modify behavior strictly:
      // Subscript expression type matches method return type exactly.
      // Then if it is Ref, usage sites decide to deref.
      
      return .subscriptExpression(base: finalBase, arguments: args, method: method, type: returns)
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
      if let template = currentScope.lookupGenericStructTemplate(base) {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        return try instantiate(template: template, args: resolvedArgs)
      } else if let template = currentScope.lookupGenericUnionTemplate(base) {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        return try instantiateUnion(template: template, args: resolvedArgs)
      } else {
        throw SemanticError.undefinedType(base)
      }
    }
  }

  private func instantiate(template: GenericStructTemplate, args: [Type]) throws -> Type {
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

    // 2. Calculate Layout Key and Layout Name EARLY
    let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
    let layoutName = "\(template.name)_\(argLayoutKeys)"

    // Create Placeholder for recursion
    let placeholder = Type.structure(
      name: layoutName, members: [], isGenericInstantiation: true, isCopy: template.isCopy)
    instantiatedTypes[key] = placeholder

    // 1. Resolve members with specific types
    var resolvedMembers: [(name: String, type: Type, mutable: Bool)] = []
    do {
        try withNewScope {
          for (i, paramInfo) in template.typeParameters.enumerated() {
            try currentScope.defineType(paramInfo.name, type: args[i])
          }
          for param in template.parameters {
            let fieldType = try resolveTypeNode(param.type)
            if fieldType == placeholder {
                 throw SemanticError.invalidOperation(op: "Direct recursion in generic struct \(layoutName) not allowed (use ref)", type1: param.name, type2: "")
            }
            resolvedMembers.append((name: param.name, type: fieldType, mutable: param.mutable))
          }
        }
    } catch {
        instantiatedTypes.removeValue(forKey: key)
        throw error
    }

    // 3. Create Specific Type
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
      extraGlobalNodes.append(.globalStructDeclaration(identifier: typeSymbol, parameters: params))
    }

    return specificType
  }

  private func instantiateUnion(template: GenericUnionTemplate, args: [Type]) throws -> Type {
    guard template.typeParameters.count == args.count else {
       throw SemanticError.typeMismatch(expected: "\(template.typeParameters.count) generic types", got: "\(args.count)")
    }
    
    let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
    if let existing = instantiatedTypes[key] {
        return existing
    }
    
    let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
    let layoutName = "\(template.name)_\(argLayoutKeys)"
    
    // Placeholder
    let placeholder = Type.union(
        name: layoutName, cases: [], isGenericInstantiation: true, isCopy: template.isCopy)
    instantiatedTypes[key] = placeholder
    
    var resolvedCases: [UnionCase] = []
    do {
        try withNewScope {
            for (i, paramInfo) in template.typeParameters.enumerated() {
                 try currentScope.defineType(paramInfo.name, type: args[i])
            }
            for c in template.cases {
                 var params: [(name: String, type: Type)] = []
                 for p in c.parameters {
                     let resolved = try resolveTypeNode(p.type)
                     if resolved == placeholder {
                         throw SemanticError.invalidOperation(op: "Direct recursion in generic union \(layoutName) not allowed (use ref)", type1: p.name, type2: "")
                     }
                     params.append((name: p.name, type: resolved))
                 }
                 resolvedCases.append(UnionCase(name: c.name, parameters: params))
            }
        }
    } catch {
        instantiatedTypes.removeValue(forKey: key)
        throw error
    }
    
    if template.isCopy {
        for c in resolvedCases {
            for param in c.parameters {
                if !param.type.isCopy {
                     throw SemanticError.invalidOperation(op: "Copy union instantiation \(layoutName) cannot contain non-Copy field \(param.name) of type \(param.type)", type1: "", type2: "")
                }
            }
        }
    }

    let specificType = Type.union(
        name: layoutName, 
        cases: resolvedCases, 
        isGenericInstantiation: true, 
        isCopy: template.isCopy
    )
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
    
    // Register global declaration for CodeGen
    if !generatedLayouts.contains(layoutName) {
        generatedLayouts.insert(layoutName)
        // Canonical cases (using canonical types for fields)
        var canonicalCases: [UnionCase] = []
        try withNewScope {
             for (i, paramInfo) in template.typeParameters.enumerated() {
                  try currentScope.defineType(paramInfo.name, type: args[i].canonical)
             }
             for c in template.cases {
                  var params: [(name: String, type: Type)] = []
                  for p in c.parameters {
                      params.append((name: p.name, type: try resolveTypeNode(p.type)))
                  }
                  canonicalCases.append(UnionCase(name: c.name, parameters: params))
             }
        }
        
        let canonicalType = Type.union(name: layoutName, cases: canonicalCases, isGenericInstantiation: true, isCopy: true)
        let typeSymbol = Symbol(name: layoutName, type: canonicalType, kind: .type)
        extraGlobalNodes.append(.globalUnionDeclaration(identifier: typeSymbol, cases: canonicalCases))
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
    // We split this into two phases: Header resolution (for caching) and Body check.
    
    // Phase 1: Header Resolution
    let (resolvedParams, resolvedReturnType, mangledName) = try withNewScope {
      for (i, paramInfo) in template.typeParameters.enumerated() {
        try currentScope.defineType(paramInfo.name, type: args[i])
      }

      let returnType = try resolveTypeNode(template.returnType)
      let rParams = try template.parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }
      
      let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
      let name = "\(template.name)_\(argLayoutKeys)"
      return (rParams, returnType, name)
    }

    let functionType = Type.function(
          parameters: resolvedParams.map { Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind)) },
          returns: resolvedReturnType)

    if functionType.containsGenericParameter {
      return ("", functionType)
    }
    
    // Cache EARLY to support recursion
    instantiatedFunctions[key] = (mangledName, functionType)

    // Phase 2: Body Check (in new scope again to have correct context)
    let typedBody: TypedExpressionNode
    do {
       typedBody = try withNewScope {
          for (i, paramInfo) in template.typeParameters.enumerated() {
            try currentScope.defineType(paramInfo.name, type: args[i])
          }
          for param in resolvedParams {
            currentScope.define(param.name, param.type, mutable: param.isMutable())
          }
           // We pass dummy body to checkFunctionBody? No, we call inferTypedExpression directly since we set up scope
          let inferredBody = try inferTypedExpression(template.body)
          if inferredBody.type != .never && inferredBody.type != resolvedReturnType {
            throw SemanticError.typeMismatch(
              expected: resolvedReturnType.description, got: inferredBody.type.description)
          }
          return inferredBody
       }
    } catch {
       // If body check fails, remove from cache to avoid corrupt state? 
       // Or just throw. throw is fine.
       instantiatedFunctions.removeValue(forKey: key)
       throw error
    }

    // 3. Register Global Function if not already generated
    // Skip if intrinsic
    let intrinsicNames = ["alloc_memory", "dealloc_memory", "copy_memory", "move_memory", "ref_count"]
    if !generatedLayouts.contains(mangledName) && !intrinsicNames.contains(template.name) {
      generatedLayouts.insert(mangledName)

      let functionNode = TypedGlobalNode.globalFunction(
        identifier: Symbol(name: mangledName, type: functionType, kind: .function),
        parameters: resolvedParams,
        body: typedBody
      )
      extraGlobalNodes.append(functionNode)
    }
    
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

  private func checkPattern(_ pattern: PatternNode, subjectType: Type) throws -> (TypedPattern, [(String, Bool, Type)]) {
      var bindings: [(String, Bool, Type)] = []
      
      switch pattern {
      case .integerLiteral(let val, _):
          if subjectType != .int {
             throw SemanticError.typeMismatch(expected: "Int", got: subjectType.description)
          }
          return (.integerLiteral(value: val), [])
          
      case .booleanLiteral(let val, _):
          if subjectType != .bool {
             throw SemanticError.typeMismatch(expected: "Bool", got: subjectType.description)
          }
          return (.booleanLiteral(value: val), [])
          
      case .wildcard(_):
          return (.wildcard, [])
          
      case .variable(let name, let mutable, _):
          // Bind variable to the subject
          let symbol = Symbol(name: name, type: subjectType, kind: .variable(mutable ? .MutableValue : .Value))
          return (.variable(symbol: symbol), [(name, mutable, subjectType)])
          
      case .unionCase(let caseName, let subPatterns, _):
          guard case .union(let typeName, let cases, _, _) = subjectType else {
               throw SemanticError.typeMismatch(expected: "Union Type", got: subjectType.description)
          }
          
          guard let caseIndex = cases.firstIndex(where: { $0.name == caseName }) else {
               throw SemanticError(.generic("Union case '\(caseName)' not found in type '\(typeName)'"))
          }
          let caseDef = cases[caseIndex]
           
          if caseDef.parameters.count != subPatterns.count {
               throw SemanticError.invalidArgumentCount(function: caseName, expected: caseDef.parameters.count, got: subPatterns.count)
          }
           
          var typedSubPatterns: [TypedPattern] = []
          for (idx, subPat) in subPatterns.enumerated() {
               let paramType = caseDef.parameters[idx].type
               let (typedSub, subBindings) = try checkPattern(subPat, subjectType: paramType)
               typedSubPatterns.append(typedSub)
               bindings.append(contentsOf: subBindings)
          }
           
          return (.unionCase(caseName: caseName, tagIndex: caseIndex, elements: typedSubPatterns), bindings)
      }
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

  private func isIntegerType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64,
         .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  private func isFloatType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64:
      return true
    default:
      return false
    }
  }

  // Coerce numeric literals to the expected numeric type for annotations/parameters.
  private func coerceLiteral(_ expr: TypedExpressionNode, to expected: Type) -> TypedExpressionNode {
    if isIntegerType(expected) {
      if case .integerLiteral(let value, _) = expr {
        return .integerLiteral(value: value, type: expected)
      }
    }
    if isFloatType(expected) {
      if case .floatLiteral(let value, _) = expr {
        return .floatLiteral(value: value, type: expected)
      }
    }
    return expr
  }

  private func checkArithmeticOp(_ op: ArithmeticOperator, _ lhs: Type, _ rhs: Type) throws
    -> Type
  {
    if lhs == rhs {
      if isIntegerType(lhs) { return lhs }
      if isFloatType(lhs) { return lhs }
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

public class TypeChecker {
    // Store type information for variables and functions
    private var currentScope: Scope = Scope()
    private let ast: ASTNode

    public init(ast: ASTNode) {
        self.ast = ast
    }

    // Changed to return TypedProgram
    public func check() throws -> TypedProgram {
        switch self.ast {
        case let .program(declarations):
            var typedDeclarations: [TypedGlobalNode] = []
            for decl in declarations {
                let typedDecl = try checkGlobalDeclaration(decl)
                typedDeclarations.append(typedDecl)
            }
            return .program(globalNodes: typedDeclarations)
        }
    }

    private func checkGlobalDeclaration(_ decl: GlobalNode) throws -> TypedGlobalNode {
        switch decl {
        case let .globalVariableDeclaration(name, typeNode, value, isMut):
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

    case let .globalFunctionDeclaration(name, typeParameters, parameters, returnTypeNode, body):
                guard case nil = currentScope.lookup(name) else {
                throw SemanticError.duplicateDefinition(name)
            }
            let (functionType, typedBody, params) = try withNewScope {
                // introduce generic type
                for typeParam in typeParameters {
                    // Define the new type
                    let typeType = Type.structure(
                        name: typeParam,
                        members: [],
                        isValue: false
                    )
                    try currentScope.defineType(typeParam, type: typeType)
                }
                let returnType = try resolveTypeNode(returnTypeNode)
                let params = try parameters.map { param -> Symbol in
                    let paramType = try resolveTypeNode(param.type)
                    return Symbol(name: param.name, type: paramType, kind: .variable(param.mutable ? .MutableValue : .Value))
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
        case let .globalTypeDeclaration(name, parameters, isValue):
            // Check if type already exists
            if currentScope.lookupType(name) != nil {
                throw SemanticError.duplicateTypeDefinition(name)
            }

            let params = try parameters.map { param -> Symbol in
                let paramType = try resolveTypeNode(param.type)
                return Symbol(
                    name: param.name, type: paramType, kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
            }

            // For val types, check that all fields are also val types
            if isValue {
                for param in params {
                    if !isValType(param.type) {
                        throw SemanticError.invalidFieldTypeInValueType(
                            type: name,
                            field: param.name,
                            fieldType: param.type.description
                        )
                    } else if param.isMutable() {
                        throw SemanticError.invalidMutableFieldInValueType(
                            type: name,
                            field: param.name
                        )
                    }
                }
            }

            // Define the new type
            let typeType = Type.structure(
                name: name,
                members: params.map { (name: $0.name, type: $0.type, mutable: $0.isMutable()) },
                isValue: isValue
            )
            try currentScope.defineType(name, type: typeType)

            return .globalTypeDeclaration(
                identifier: Symbol(name: name, type: typeType, kind: .type),
                parameters: params,
                isValue: isValue
            )
        }
    }

    // Helper function to check if a type is a val type
    private func isValType(_ type: Type) -> Bool {
        switch type {
        case .int, .float, .bool, .void:
            return true
        case .string:
            return false  // Strings are not val types
        case let .structure(_, _, isValue):
            return isValue
        case .function:
            return true  // Functions are considered val types
        case .reference:
            return false  // References are not val types
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
                parameters: params.map { Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind)) }, returns: returnType)
            return (typedBody, functionType)
        }
    }

    // 新增用于返回带类型的表达式的类型推导函数
    private func inferTypedExpression(_ expr: ExpressionNode) throws -> TypedExpressionNode {
        switch expr {
        case let .integerLiteral(value):
            return .integerLiteral(value: value, type: .int)

        case let .floatLiteral(value):
            return .floatLiteral(value: value, type: .float)

        case let .stringLiteral(value):
            return .stringLiteral(value: value, type: .string)

        case let .booleanLiteral(value):
            return .booleanLiteral(value: value, type: .bool)

        case let .identifier(name):
            guard let type = currentScope.lookup(name) else {
                throw SemanticError.undefinedVariable(name)
            }
            return .variable(identifier: Symbol(name: name, type: type, kind: .variable(.Value)))

        case let .blockExpression(statements, finalExpression):
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

        case let .arithmeticExpression(left, op, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            let resultType = try checkArithmeticOp(op, typedLeft.type, typedRight.type)
            return .arithmeticExpression(
                left: typedLeft, op: op, right: typedRight, type: resultType)

        case let .comparisonExpression(left, op, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            let resultType = try checkComparisonOp(op, typedLeft.type, typedRight.type)
            return .comparisonExpression(
                left: typedLeft, op: op, right: typedRight, type: resultType)

        case let .ifExpression(condition, thenBranch, elseBranch):
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

        case let .whileExpression(condition, body):
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

        case let .functionCall(name, _, arguments):
            // 先检查是否是类型构造
            if let type = currentScope.lookupType(name) {
                guard case let .structure(_, parameters, _) = type else {
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

            // 如果不是类型构造，按原来的函数调用处理
            guard let type = currentScope.lookup(name) else {
                throw SemanticError.functionNotFound(name)
            }

            guard case let .function(params, returns) = type else {
                throw SemanticError.invalidOperation(op: "call", type1: type.description, type2: "")
            }

            if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                    function: name,
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

            return .functionCall(
                identifier: Symbol(name: name, type: type, kind: .function),
                arguments: typedArguments,
                type: returns
            )

        case let .andExpression(left, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            if typedLeft.type != .bool || typedRight.type != .bool {
                throw SemanticError.typeMismatch(
                    expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
            }
            return .andExpression(left: typedLeft, right: typedRight, type: .bool)

        case let .orExpression(left, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            if typedLeft.type != .bool || typedRight.type != .bool {
                throw SemanticError.typeMismatch(
                    expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
            }
            return .orExpression(left: typedLeft, right: typedRight, type: .bool)

        case let .notExpression(expr):
            let typedExpr = try inferTypedExpression(expr)
            if typedExpr.type != .bool {
                throw SemanticError.typeMismatch(expected: "Bool", got: typedExpr.type.description)
            }
            return .notExpression(expression: typedExpr, type: .bool)

        case let .refExpression(inner):
            let typedInner = try inferTypedExpression(inner)
            // 仅允许对左值取引用
            if typedInner.valueCategory != .lvalue {
                throw SemanticError.invalidOperation(op: "ref", type1: typedInner.type.description, type2: "")
            }
            // 禁止对引用再次取引用（仅单层）
            if case .reference(_) = typedInner.type {
                throw SemanticError.invalidOperation(op: "ref", type1: typedInner.type.description, type2: "")
            }
            return .referenceExpression(expression: typedInner, type: .reference(inner: typedInner.type))

        case let .memberPath(baseExpr, path):
            let typedBase = try inferTypedExpression(baseExpr)
            // T ref: 解一层 reference 再查找
            var currentType: Type = {
                if case let .reference(inner) = typedBase.type { return inner }
                return typedBase.type
            }()
            var typedPath: [Symbol] = []
            for memberName in path {
                guard case let .structure(typeName, members, _) = currentType else {
                    throw SemanticError.invalidOperation(op: "member access", type1: currentType.description, type2: "")
                }
                guard let mem = members.first(where: { $0.name == memberName }) else {
                    throw SemanticError.undefinedMember(memberName, typeName)
                }
                typedPath.append(Symbol(name: mem.name, type: mem.type, kind: .variable(mem.mutable ? .MutableValue : .Value)))
                currentType = mem.type
            }
            return .memberPath(source: typedBase, path: typedPath)
        }
    }


    // 新增用于返回带类型的语句的检查函数
    private func checkStatement(_ stmt: StatementNode) throws -> TypedStatementNode {
        switch stmt {
        case let .variableDeclaration(name, typeNode, value, mutable):
            let type = try resolveTypeNode(typeNode)

            let typedValue = try inferTypedExpression(value)
            if typedValue.type != type {
                throw SemanticError.typeMismatch(
                    expected: type.description, got: typedValue.type.description)
            }
            currentScope.define(name, type, mutable: mutable)
            return .variableDeclaration(
                identifier: Symbol(name: name, type: type, kind: mutable ? .variable(.MutableValue) : .variable(.Value)),
                value: typedValue,
                mutable: mutable
            )

        case let .assignment(target, value):
            switch target {
            case let .variable(name):
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

            case let .memberAccess(base, memberPath):
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
                    guard case let .structure(typeName, members, _) = currentType else {
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
                        name: memberName, type: member.type, kind: .variable(member.mutable ? .MutableValue : .Value))
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

        case let .expression(expr):
            let typedExpr = try inferTypedExpression(expr)
            return .expression(typedExpr)
        }
    }

    // 将 TypeNode 解析为语义层 Type，支持函数参数/返回位置的一层 reference(T)
    private func resolveTypeNode(_ node: TypeNode) throws -> Type {
        switch node {
        case let .identifier(name):
            guard let t = currentScope.resolveType(name) else {
                throw SemanticError.undefinedType(name)
            }
            return t
        case let .reference(inner):
            // 仅支持一层，在 parser 已限制；此处直接映射到 Type.reference
            let base = try resolveTypeNode(inner)
            return .reference(inner: base)
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

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
            guard case let .identifier(typeStr) = typeNode else {
                throw SemanticError.invalidNode
            }
            guard let type = currentScope.resolveType(typeStr) else {
                throw SemanticError.undefinedType(typeStr)
            }
            let typedValue = try inferTypedExpression(value)
            if typedValue.type != type {
                throw SemanticError.typeMismatch(
                    expected: type.description, got: typedValue.type.description)
            }
            currentScope.define(name, type, mutable: isMut)
            return .globalVariable(
                identifier: Symbol(name: name, type: type),
                value: typedValue,
                mutable: isMut
            )

        case let .globalFunctionDeclaration(name, typeParameters, parameters, returnTypeNode, body):
            guard case nil = currentScope.lookup(name) else {
                throw SemanticError.duplicateDefinition(name)
            }
            let (functionType, typedBody, params) = try withNewScope {
                // introduce generic type
                for typeParam in typeParameters {
                    // Define the new type
                    let typeType = Type.userDefined(
                        name: typeParam,
                        members: [],
                        isValue: false
                    )
                    try currentScope.defineType(typeParam, type: typeType)
                }
                guard case let .identifier(returnTypeStr) = returnTypeNode else {
                    throw SemanticError.invalidNode
                }
                guard let returnType = currentScope.resolveType(returnTypeStr) else {
                    throw SemanticError.undefinedType(returnTypeStr)
                }
                let params = try parameters.map { param -> Symbol in
                    guard case let .identifier(typeStr) = param.type else {
                        throw SemanticError.invalidNode
                    }
                    guard let paramType = currentScope.resolveType(typeStr) else {
                        throw SemanticError.undefinedType(typeStr)
                    }
                    return Symbol(name: param.name, type: paramType)
                }
                let (typedBody, functionType) = try checkFunctionBody(params, returnType, body)
                return (functionType, typedBody, params)
            }
            currentScope.define(name, functionType)
            return .globalFunction(
                identifier: Symbol(name: name, type: functionType),
                parameters: params,
                body: typedBody
            )
        case let .globalTypeDeclaration(name, parameters, isValue):
            // Check if type already exists
            if currentScope.lookupType(name) != nil {
                throw SemanticError.duplicateTypeDefinition(name)
            }

            let params = try parameters.map { param -> Symbol in
                guard case let .identifier(typeStr) = param.type else {
                    throw SemanticError.invalidNode
                }
                guard let paramType = currentScope.resolveType(typeStr) else {
                    throw SemanticError.undefinedType(typeStr)
                }

                return Symbol(
                    name: param.name, type: paramType, mutable: param.mutable)
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
                    } else if param.mutable {
                        throw SemanticError.invalidMutableFieldInValueType(
                            type: name,
                            field: param.name
                        )
                    }
                }
            }

            // Define the new type
            let typeType = Type.userDefined(
                name: name,
                members: params.map { (name: $0.name, type: $0.type, mutable: $0.mutable) },
                isValue: isValue
            )
            try currentScope.defineType(name, type: typeType)

            return .globalTypeDeclaration(
                identifier: Symbol(name: name, type: typeType),
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
        case let .userDefined(_, _, isValue):
            return isValue
        case .function:
            return true  // Functions are considered val types
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
                currentScope.define(param.name, param.type)
            }

            let typedBody = try inferTypedExpression(body)
            if typedBody.type != returnType {
                throw SemanticError.typeMismatch(
                    expected: returnType.description, got: typedBody.type.description)
            }
            let functionType = Type.function(
                parameters: params.map { $0.type }, returns: returnType)
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
            return .variable(identifier: Symbol(name: name, type: type))

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
                guard case let .userDefined(_, parameters, _) = type else {
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
                    identifier: Symbol(name: name, type: type),
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
            for (arg, expectedType) in zip(arguments, params) {
                let typedArg = try inferTypedExpression(arg)
                if typedArg.type != expectedType {
                    throw SemanticError.typeMismatch(
                        expected: expectedType.description,
                        got: typedArg.type.description
                    )
                }
                typedArguments.append(typedArg)
            }

            return .functionCall(
                identifier: Symbol(name: name, type: type),
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

        case let .memberAccess(expr, member):
            let typedExpr = try inferTypedExpression(expr)

            // 检查基础表达式的类型是否是用户定义的类型
            guard case let .userDefined(typeName, members, _) = typedExpr.type else {
                throw SemanticError.invalidOperation(
                    op: "member access",
                    type1: typedExpr.type.description,
                    type2: ""
                )
            }

            // 从成员列表中查找成员类型
            guard let memberType = members.first(where: { $0.name == member })?.type else {
                throw SemanticError.undefinedMember(member, typeName)
            }

            return .memberAccess(
                source: typedExpr,
                member: Symbol(name: member, type: memberType)
            )
        }
    }

    // 新增用于返回带类型的语句的检查函数
    private func checkStatement(_ stmt: StatementNode) throws -> TypedStatementNode {
        switch stmt {
        case let .variableDeclaration(name, typeNode, value, mutable):
            guard case let .identifier(typeStr) = typeNode else {
                throw SemanticError.invalidNode
            }
            guard let type = currentScope.resolveType(typeStr) else {
                throw SemanticError.undefinedType(typeStr)
            }

            let typedValue = try inferTypedExpression(value)
            if typedValue.type != type {
                throw SemanticError.typeMismatch(
                    expected: type.description, got: typedValue.type.description)
            }
            currentScope.define(name, type, mutable: mutable)
            return .variableDeclaration(
                identifier: Symbol(name: name, type: type),
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
                        identifier: Symbol(name: name, type: varType, mutable: true)),
                    value: typedValue
                )

            case let .memberAccess(base, memberPath):
                // First check that the base variable exists
                guard let baseType = currentScope.lookup(base) else {
                    throw SemanticError.undefinedVariable(base)
                }

                var currentType = baseType
                var typedPath: [Symbol] = []

                // Validate each member in the path
                for (index, memberName) in memberPath.enumerated() {
                    // Check that current type is a user-defined type
                    guard case let .userDefined(typeName, members, _) = currentType else {
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

                    // For final member in path, check if it's mutable
                    if index == memberPath.count - 1 {
                        guard member.mutable else {
                            throw SemanticError.immutableFieldAssignment(
                                type: typeName, field: memberName)
                        }
                    }

                    let memberIdentifier = Symbol(
                        name: memberName, type: member.type, mutable: member.mutable)
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
                        base: Symbol(name: base, type: baseType),
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

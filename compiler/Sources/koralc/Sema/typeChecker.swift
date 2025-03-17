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
            let type = try Type(type: typeStr)
            let typedValue = try inferTypedExpression(value)
            if typedValue.type != type {
                throw SemanticError.typeMismatch(expected: type.description, got: typedValue.type.description)
            }
            currentScope.define(name, type, mutable: isMut)
            return .globalVariable(
                identifier: TypedIdentifierNode(name: name, type: type),
                value: typedValue,
                mutable: isMut
            )

        case let .globalFunctionDeclaration(name, parameters, returnTypeNode, body):
            guard case nil = currentScope.lookup(name) else {
                throw SemanticError.duplicateDefinition(name)
            }
            guard case let .identifier(returnTypeStr) = returnTypeNode else {
                throw SemanticError.invalidNode
            }
            let returnType = try Type(type: returnTypeStr)
            let params = try parameters.map { param -> TypedIdentifierNode in 
                guard case let .identifier(typeStr) = param.type else {
                    throw SemanticError.invalidNode
                }
                let paramType = try Type(type: typeStr)
                return TypedIdentifierNode(name: param.name, type: paramType)
            }
            let (typedBody, functionType) = try checkFunctionBody(params, returnType, body)
            currentScope.define(name, functionType)
            return .globalFunction(
                identifier: TypedIdentifierNode(name: name, type: functionType),
                parameters: params,
                body: typedBody
            )
        case let .globalTypeDeclaration(name, parameters):
            // Check if type already exists
            if currentScope.lookupType(name) != nil {
                throw SemanticError.duplicateTypeDefinition(name)
            }
            
            let params = try parameters.map { param -> TypedIdentifierNode in 
                guard case let .identifier(typeStr) = param.type else {
                    throw SemanticError.invalidNode
                }
                let paramType = try Type(type: typeStr)
                return TypedIdentifierNode(name: param.name, type: paramType)
            }
            
            // Define the new type
            let typeType = Type.userDefined(name, parameters: params.map { $0.type })
            try currentScope.defineType(name, type: typeType)
            
            return .globalTypeDeclaration(
                identifier: TypedIdentifierNode(name: name, type: typeType),
                parameters: params
            )
        }
    }

    private func checkFunctionBody(_ params: [TypedIdentifierNode], 
                                 _ returnType: Type,
                                 _ body: ExpressionNode) throws -> (TypedExpressionNode, Type) {
        return try withNewScope {
            // Add parameters to new scope
            for param in params {
                currentScope.define(param.name, param.type)
            }
            
            let typedBody = try inferTypedExpression(body)
            if typedBody.type != returnType {
                throw SemanticError.typeMismatch(expected: returnType.description, got: typedBody.type.description)
            }
            let functionType = Type.function(parameters: params.map { $0.type }, returns: returnType)
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
            return .variable(identifier: TypedIdentifierNode(name: name, type: type))
            
        case let .blockExpression(statements, finalExpression):
            return try withNewScope {
                var typedStatements: [TypedStatementNode] = []
                for stmt in statements {
                    let typedStmt = try checkStatement(stmt)
                    typedStatements.append(typedStmt)
                }
                if let finalExpr = finalExpression {
                    let typedFinalExpr = try inferTypedExpression(finalExpr)
                    return .blockExpression(statements: typedStatements, finalExpression: typedFinalExpr, type: typedFinalExpr.type)
                }
                return .blockExpression(statements: typedStatements, finalExpression: nil, type: .void)
            }
            
        case let .arithmeticExpression(left, op, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            let resultType = try checkArithmeticOp(op, typedLeft.type, typedRight.type)
            return .arithmeticExpression(left: typedLeft, op: op, right: typedRight, type: resultType)
            
        case let .comparisonExpression(left, op, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            let resultType = try checkComparisonOp(op, typedLeft.type, typedRight.type)
            return .comparisonExpression(left: typedLeft, op: op, right: typedRight, type: resultType)
            
        case let .ifExpression(condition, thenBranch, elseBranch):
            let typedCondition = try inferTypedExpression(condition)
            if typedCondition.type != .bool {
                throw SemanticError.typeMismatch(expected: "Bool", got: typedCondition.type.description)
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
                throw SemanticError.typeMismatch(expected: "Bool", got: typedCondition.type.description)
            }
            let typedBody = try inferTypedExpression(body)
            return .whileExpression(
                condition: typedCondition,
                body: typedBody,
                type: .void
            )
        
        case let .functionCall(name, arguments):
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
                identifier: TypedIdentifierNode(name: name, type: type),
                arguments: typedArguments,
                type: returns
            )
            
        case let .andExpression(left, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            if typedLeft.type != .bool || typedRight.type != .bool {
                throw SemanticError.typeMismatch(expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
            }
            return .andExpression(left: typedLeft, right: typedRight, type: .bool)
            
        case let .orExpression(left, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            if typedLeft.type != .bool || typedRight.type != .bool {
                throw SemanticError.typeMismatch(expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
            }
            return .orExpression(left: typedLeft, right: typedRight, type: .bool)
            
        case let .notExpression(expr):
            let typedExpr = try inferTypedExpression(expr)
            if typedExpr.type != .bool {
                throw SemanticError.typeMismatch(expected: "Bool", got: typedExpr.type.description)
            }
            return .notExpression(expression: typedExpr, type: .bool)
        }
    }

    // 新增用于返回带类型的语句的检查函数
    private func checkStatement(_ stmt: StatementNode) throws -> TypedStatementNode {
        switch stmt {
        case let .variableDeclaration(name, typeNode, value, mutable):
            guard case let .identifier(typeStr) = typeNode else {
                throw SemanticError.invalidNode
            }
            let type = try Type(type: typeStr)
            let typedValue = try inferTypedExpression(value)
            if typedValue.type != type {
                throw SemanticError.typeMismatch(expected: type.description, got: typedValue.type.description)
            }
            currentScope.define(name, type, mutable: mutable)
            return .variableDeclaration(
                identifier: TypedIdentifierNode(name: name, type: type),
                value: typedValue,
                mutable: mutable
            )
            
        case let .assignment(name, value):
            guard let varType = currentScope.lookup(name) else {
                throw SemanticError.undefinedVariable(name)
            }
            guard currentScope.isMutable(name) else {
                throw SemanticError.assignToImmutable(name)
            }
            let typedValue = try inferTypedExpression(value)
            if typedValue.type != varType {
                throw SemanticError.typeMismatch(expected: varType.description, got: typedValue.type.description)
            }
            return .assignment(
                identifier: TypedIdentifierNode(name: name, type: varType),
                value: typedValue
            )
            
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

    private func checkArithmeticOp(_ op: ArithmeticOperator, _ lhs: Type, _ rhs: Type) throws -> Type {
        if lhs == .int && rhs == .int {
            return .int
        }
        if lhs == .float && rhs == .float {
            return .float
        }
        throw SemanticError.invalidOperation(op: String(describing: op), type1: lhs.description, type2: rhs.description)
    }
    
    private func checkComparisonOp(_ op: ComparisonOperator, _ lhs: Type, _ rhs: Type) throws -> Type {
        if lhs == rhs {
            return .bool
        }
        throw SemanticError.invalidOperation(op: String(describing: op), type1: lhs.description, type2: rhs.description)
    }
}

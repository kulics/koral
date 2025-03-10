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
            let functionType = Type.function(params: params.map { $0.type }, returns: returnType)
            return (typedBody, functionType)
        }
    }

    // 新增用于返回带类型的表达式的类型推导函数
    private func inferTypedExpression(_ expr: ExpressionNode) throws -> TypedExpressionNode {
        switch expr {
        case let .integerLiteral(value):
            return .intLiteral(value: value, type: .int)
            
        case let .floatLiteral(value):
            return .floatLiteral(value: value, type: .float)
            
        case let .stringLiteral(value):
            return .stringLiteral(value: value, type: .string)
            
        case let .boolLiteral(value):
            return .boolLiteral(value: value, type: .bool)
            
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
                    return .block(statements: typedStatements, finalExpr: typedFinalExpr, type: typedFinalExpr.type)
                }
                return .block(statements: typedStatements, finalExpr: nil, type: .void)
            }
            
        case let .arithmeticExpression(left, op, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            let resultType = try checkArithmeticOp(op, typedLeft.type, typedRight.type)
            return .arithmeticOp(left: typedLeft, op: op, right: typedRight, type: resultType)
            
        case let .comparisonExpression(left, op, right):
            let typedLeft = try inferTypedExpression(left)
            let typedRight = try inferTypedExpression(right)
            let resultType = try checkComparisonOp(op, typedLeft.type, typedRight.type)
            return .comparisonOp(left: typedLeft, op: op, right: typedRight, type: resultType)
            
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
            return .ifExpr(
                condition: typedCondition,
                thenBranch: typedThen,
                elseBranch: typedElse,
                type: typedThen.type
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
            
        case let .whileExpression(condition, body):
            let typedCondition = try inferTypedExpression(condition)
            if (typedCondition.type != .bool) {
                throw SemanticError.typeMismatch(expected: "Bool", got: typedCondition.type.description)
            }
            let typedBody = try inferTypedExpression(body)
            return .whileExpr(
                condition: typedCondition,
                body: typedBody,
                type: .void
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
            let type = try Type(type: typeStr)
            let typedValue = try inferTypedExpression(value)
            if typedValue.type != type {
                throw SemanticError.typeMismatch(expected: type.description, got: typedValue.type.description)
            }
            currentScope.define(name, type, mutable: mutable)
            return .variableDecl(
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

// Semantic error types
public indirect enum SemanticError: Error {
    case typeMismatch(expected: String, got: String)
    case undefinedVariable(String)
    case invalidOperation(op: String, type1: String, type2: String)
    case invalidNode
    case duplicateDefinition(String)
    case invalidType(String)
    case assignToImmutable(String)
    case functionNotFound(String)
    case invalidArgumentCount(function: String, expected: Int, got: Int)
}

extension SemanticError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .typeMismatch(expected, got):
            return "Type mismatch: expected \(expected), got \(got)"
        case let .undefinedVariable(name):
            return "Undefined variable: \(name)"
        case let .invalidOperation(op, type1, type2):
            return "Invalid operation \(op) between types \(type1) and \(type2)"
        case .invalidNode:
            return "Invalid AST node"
        case let .duplicateDefinition(name):
            return "Duplicate definition: \(name)"
        case .invalidType(let type):
            return "Invalid type: \(type)"
        case let .assignToImmutable(name):
            return "Cannot assign to immutable variable: \(name)"
        case let .functionNotFound(name):
            return "Function not found: \(name)"
        case let .invalidArgumentCount(function, expected, got):
            return "Invalid argument count for function \(function): expected \(expected), got \(got)"
        }
    }
}

public indirect enum Type: Equatable, CustomStringConvertible {
    case int
    case float
    case string
    case bool
    case function(params: [Type], returns: Type)
    case void
    
    public init(type: String) throws {
        switch type {
        case "Int":
            self = .int
        case "Float":
            self = .float
        case "String":
            self = .string
        case "Bool":
            self = .bool
        case "Void":
            self = .void
        default:
            throw SemanticError.invalidType(type)
        }
    }
    
    public static func ==(lhs: Type, rhs: Type) -> Bool {
        switch (lhs, rhs) {
        case (.int, .int),
             (.float, .float),
             (.string, .string),
             (.bool, .bool),
             (.void, .void):
            return true
        case let (.function(params1, returns1), .function(params2, returns2)):
            return params1 == params2 && returns1 == returns2
        default:
            return false
        }
    }

    public var description: String {
        switch self {
        case .int:
            return "Int"
        case .float:
            return "Float"
        case .string:
            return "String"
        case .bool:
            return "Bool"
        case let .function(params, returns):
            let paramsStr = params.map { $0.description }.joined(separator: ", ")
            return "(\(paramsStr)) -> \(returns.description)"
        case .void:
            return "Void"
        }
    }
}
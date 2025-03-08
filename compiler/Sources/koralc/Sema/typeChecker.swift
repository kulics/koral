public class TypeChecker {
    // Store type information for variables and functions
    private var currentScope: Scope = Scope()
    private let ast: ASTNode
    
    public init(ast: ASTNode) {
        self.ast = ast
    }
    
    // Check entire AST
    public func check() throws {
        switch self.ast {
        case let .program(declarations):
            for decl in declarations {
                try checkGlobalDeclaration(decl)
            }
        }
    }

    private func checkGlobalDeclaration(_ decl: GlobalNode) throws {
        switch decl {
        case let .globalVariableDeclaration(name, typeNode, value, isMut):
            guard case nil = currentScope.lookup(name) else {
                throw SemanticError.duplicateDefinition(name)
            }
            guard case let .identifier(typeStr) = typeNode else {
                throw SemanticError.invalidNode
            }
            let type = try Type(type: typeStr)
            let valueType = try inferType(value)
            if valueType != type {
                throw SemanticError.typeMismatch(expected: type.description, got: valueType.description)
            }
            currentScope.define(name, type, mutable: isMut)
        case let .globalFunctionDeclaration(name, parameters, returnTypeNode, body):
            guard case nil = currentScope.lookup(name) else {
                throw SemanticError.duplicateDefinition(name)
            }
            guard case let .identifier(returnTypeStr) = returnTypeNode else {
                throw SemanticError.invalidNode
            }
            let returnType = try Type(type: returnTypeStr)
            let params = try parameters.map { param -> (String, Type) in 
                guard case let .identifier(typeStr) = param.type else {
                    throw SemanticError.invalidNode
                }
                return (param.name, try Type(type: typeStr))
            }
            return try checkFunction(name, params, returnType, body)
        }
    }

    private func checkStatement(_ stmt: StatementNode) throws {
        switch stmt {
        case let .variableDeclaration(name, typeNode, value, mutable):
            guard case let .identifier(typeStr) = typeNode else {
                throw SemanticError.invalidNode
            }
            let initType = try inferType(value)
            let type = try Type(type: typeStr)
            if initType != type {
                throw SemanticError.typeMismatch(expected: type.description, got: initType.description)
            }
            currentScope.define(name, type, mutable: mutable)
            
        case let .assignment(name, value):
            guard let varType = currentScope.lookup(name) else {
                throw SemanticError.undefinedVariable(name)
            }
            guard currentScope.isMutable(name) else {
                throw SemanticError.assignToImmutable(name)
            }
            let valueType = try inferType(value)
            if valueType != varType {
                throw SemanticError.typeMismatch(expected: varType.description, got: valueType.description)
            }
            
        case let .expression(expr):
            _ = try inferType(expr)
        }
    }
    
    private func withNewScope(_ body: () throws -> Type) rethrows -> Type {
        let previousScope = currentScope
        currentScope = currentScope.createChild()
        defer { currentScope = previousScope }
        return try body()
    }

    private func checkFunction(_ name: String, 
                            _ params: [(String, Type)],
                            _ returnType: Type,
                            _ body: ExpressionNode) throws {
        // Add function to current scope
        currentScope.define(name, .function(params: params.map { $0.1 }, returns: returnType))
        
        // Create new scope for function body
        _ = try withNewScope {
            // Add parameters to new scope
            for param in params {
                currentScope.define(param.0, param.1)
            }
            
            // Check function body
            let bodyType = try inferType(body)
            if bodyType != returnType {
                throw SemanticError.typeMismatch(expected: returnType.description, got: bodyType.description)
            }
            return bodyType
        }
    }

    private func inferType(_ expr: ExpressionNode) throws -> Type {
        switch expr {
        case .integerLiteral(_):
            return .int
        case .floatLiteral(_):
            return .float
        case .stringLiteral(_):
            return .string
        case .boolLiteral(_):
            return .bool
        case .identifier(let name):
            guard let type = currentScope.lookup(name) else {
                throw SemanticError.undefinedVariable(name)
            }
            return type
        case let .binaryExpression(left, operatorToken, right):
            let leftType = try inferType(left)
            let rightType = try inferType(right)
            return try checkBinaryOp(operatorToken, leftType, rightType)
        case let .blockExpression(statements, finalExpression):
            return try withNewScope {
                for stmt in statements {
                    try checkStatement(stmt)
                }
                return try inferType(finalExpression)
            }
        }
    }
    
    private func checkBinaryOp(_ op: Token, _ lhs: Type, _ rhs: Type) throws -> Type {
        switch op {
        case .plus, .minus, .multiply, .divide, .modulo:
            // Check numeric operations
            if lhs == .int && rhs == .int {
                return .int
            }
            if lhs == .float && rhs == .float {
                return .float
            }
            throw SemanticError.invalidOperation(op: op.description, type1: lhs.description, type2: rhs.description)
        case .equalEqual, .notEqual, .greater, .less, .greaterEqual, .lessEqual:
            // Check comparison operations
            if lhs == rhs {
                return .bool
            }
            throw SemanticError.invalidOperation(op: op.description, type1: lhs.description, type2: rhs.description)
        default:
            throw SemanticError.invalidOperation(op: op.description, type1: lhs.description, type2: rhs.description)
        }
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
        }
    }
}

public indirect enum Type: Equatable, CustomStringConvertible {
    case int
    case float
    case string
    case bool
    case function(params: [Type], returns: Type)
    
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
        default:
            throw SemanticError.invalidType(type)
        }
    }
    
    public static func ==(lhs: Type, rhs: Type) -> Bool {
        switch (lhs, rhs) {
        case (.int, .int),
             (.float, .float),
             (.string, .string),
             (.bool, .bool):
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
        }
    }
}
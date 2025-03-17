
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
    case duplicateTypeDefinition(String)
    case undefinedType(String)
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
        case let .duplicateTypeDefinition(name):
            return "Duplicate type definition: \(name)"
        case let .undefinedType(name):
            return "Undefined type: \(name)"
        }
    }
}

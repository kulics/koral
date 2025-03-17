
public indirect enum Type: Equatable, CustomStringConvertible {
    case int
    case float
    case string
    case bool
    case function(parameters: [Type], returns: Type)
    case void
    case userDefined(String, parameters: [Type])
    
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
        case let (.userDefined(name1, parameters1), .userDefined(name2, parameters2)):
            return name1 == name2 && parameters1 == parameters2
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
        case let .userDefined(name, parameters):
            let paramsStr = parameters.map { $0.description }.joined(separator: ", ")
            return "\(name)(\(paramsStr))"
        }
    }
}
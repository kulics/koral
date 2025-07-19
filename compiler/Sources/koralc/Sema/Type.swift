public indirect enum Type {
    case int
    case float
    case string
    case bool
    case void
    case function(parameters: [Type], returns: Type)
    case structure(name: String, members: [(name: String, type: Type, mutable: Bool)], isValue: Bool)

    public var description: String {
        switch self {
        case .int: return "Int"
        case .float: return "Float"
        case .string: return "String"
        case .bool: return "Bool"
        case .void: return "Void"
        case let .function(params, returns):
            let paramTypes = params.map { $0.description }.joined(separator: ", ")
            return "(\(paramTypes)) -> \(returns)"
        case let .structure(name, _, _):
            return name
        }
    }
}

extension Type : Equatable {
    public static func == (lhs: Type, rhs: Type) -> Bool {
        switch (lhs, rhs) {
        case (.int, .int),
             (.float, .float),
             (.string, .string),
             (.bool, .bool),
             (.void, .void):
            return true
            
        case let (.function(lParams, lReturns), .function(rParams, rReturns)):
            return lParams == rParams && lReturns == rReturns
            
        case let (.structure(lName, _, _), .structure(rName, _, _)):
            return lName == rName
            
        default:
            return false
        }
    }

    public static func != (lhs: Type, rhs: Type) -> Bool {
        return !(lhs == rhs)
    }
}
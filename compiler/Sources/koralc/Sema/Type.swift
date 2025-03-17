public indirect enum Type: Equatable, CustomStringConvertible {
    case int
    case float
    case string
    case bool
    case function(parameters: [Type], returns: Type)
    case void
    case userDefined(String, parameters: [Type])

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
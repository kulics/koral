public indirect enum Type {
    case int
    case float
    case string
    case bool
    case void
    case function(parameters: [Type], returns: Type)
    case userDefined(name: String, members: [(name: String, type: Type)], mutable: Bool)

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
        case let .userDefined(name, _, _):
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
            
        case let (.userDefined(lName, lMembers, lmutable), .userDefined(rName, rMembers, rmutable)):
            guard lName == rName else { return false }
            guard lmutable == rmutable else { return false }
            guard lMembers.count == rMembers.count else { return false }
            // 检查每个成员的名称和类型是否匹配
            return zip(lMembers, rMembers).allSatisfy { lMember, rMember in
                lMember.name == rMember.name && lMember.type == rMember.type
            }
            
        default:
            return false
        }
    }

    public static func != (lhs: Type, rhs: Type) -> Bool {
        return !(lhs == rhs)
    }
}
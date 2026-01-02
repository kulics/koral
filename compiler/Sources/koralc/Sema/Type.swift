public indirect enum Type {
    case int
    case float
    case string
    case bool
    case void
    case function(parameters: [Parameter], returns: Type)
    case structure(name: String, members: [(name: String, type: Type, mutable: Bool)])
    case reference(inner: Type)

    public var description: String {
        switch self {
        case .int: return "Int"
        case .float: return "Float"
        case .string: return "String"
        case .bool: return "Bool"
        case .void: return "Void"
        case let .function(params, returns):
            let paramTypes = params.map { $0.type.description }.joined(separator: ", ")
            return "(\(paramTypes)) -> \(returns)"
        case let .structure(name, _):
            return name
        case let .reference(inner):
            return "\(inner.description) ref"
        }
    }
}

public struct Parameter: Equatable {
    let type: Type
    let kind: PassKind
}

public enum PassKind: Equatable {
    case byVal
    case byRef
    case byMutRef
}

public func fromSymbolKindToPassKind(_ kind: SymbolKind) -> PassKind {
    switch kind {
    case .variable(let varKind):
        switch varKind {
        case .Value:
            return .byVal
        case .MutableValue:
            return .byVal
        case .Reference:
            return .byRef
        case .MutableReference:
            return .byMutRef
        }
    case .function, .type:
        fatalError("Cannot convert function or type symbol kind to pass kind")
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
            
        case let (.structure(lName, _), .structure(rName, _)):
            return lName == rName
        case let (.reference(l), .reference(r)):
            return l == r
            
        default:
            return false
        }
    }

    public static func != (lhs: Type, rhs: Type) -> Bool {
        return !(lhs == rhs)
    }
}
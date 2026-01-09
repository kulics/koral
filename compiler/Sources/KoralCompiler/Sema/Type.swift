public indirect enum Type: CustomStringConvertible {
  case int
  case float
  case string
  case bool
  case void
  case function(parameters: [Parameter], returns: Type)
  case structure(name: String, members: [(name: String, type: Type, mutable: Bool)], isGenericInstantiation: Bool)
  case reference(inner: Type)
  case pointer(element: Type)
  case genericParameter(name: String)

  public var description: String {
    switch self {
    case .int: return "Int"
    case .float: return "Float"
    case .string: return "String"
    case .bool: return "Bool"
    case .void: return "Void"
    case .function(let params, let returns):
      let paramTypes = params.map { $0.type.description }.joined(separator: ", ")
      return "(\(paramTypes)) -> \(returns)"
    case .structure(let name, _, _):
      return name
    case .reference(let inner):
      return "\(inner.description) ref"
    case .pointer(let element):
      return "\(element.description) ptr"
    case .genericParameter(let name):
      return name
    }
  }

  public var layoutKey: String {
    switch self {
    case .int: return "I"
    case .float: return "F"
    case .string: return "S"
    case .bool: return "B"
    case .void: return "V"
    case .function: return "Fn"
    case .reference: return "R"
    case .pointer(_): return "P"
    case .structure(_, let members, _):
      let memberKeys = members.map { $0.type.layoutKey }.joined(separator: "_")
      return "Struct_\(memberKeys)"
    case .genericParameter(let name):
      return "Param_\(name)"
    }
  }

  public var containsGenericParameter: Bool {
    switch self {
    case .int, .float, .string, .bool, .void:
      return false
    case .function(let params, let returns):
      return returns.containsGenericParameter || params.contains { $0.type.containsGenericParameter }
    case .structure(_, let members, _):
      return members.contains { $0.type.containsGenericParameter }
    case .reference(let inner):
      return inner.containsGenericParameter
    case .pointer(let element):
       return element.containsGenericParameter
    case .genericParameter:
      return true
    }
  }

  public var canonical: Type {
    switch self {
    case .int, .float, .bool, .void, .string: return self
    case .reference(_): return .reference(inner: .void)
    case .pointer(let element): return .pointer(element: element.canonical) 
    case .structure(let name, let members, let isGenericInstantiation):
      if isGenericInstantiation {
        let newMembers = members.map { ($0.name, $0.type.canonical, $0.mutable) }
        return .structure(name: name, members: newMembers, isGenericInstantiation: true)
      } else {
        return self
      }
    case .function: return self
    case .genericParameter: return self
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

extension Type: Equatable {
  public static func == (lhs: Type, rhs: Type) -> Bool {
    switch (lhs, rhs) {
    case (.int, .int),
      (.float, .float),
      (.string, .string),
      (.bool, .bool),
      (.void, .void):
      return true

    case (.function(let lParams, let lReturns), .function(let rParams, let rReturns)):
      return lParams == rParams && lReturns == rReturns

    case (.structure(let lName, _, _), .structure(let rName, _, _)):
      return lName == rName
    case (.reference(let l), .reference(let r)):
      return l == r
    case (.pointer(let l), .pointer(let r)):
       return l == r
    case (.genericParameter(let l), .genericParameter(let r)):
      return l == r

    default:
      return false
    }
  }

  public static func != (lhs: Type, rhs: Type) -> Bool {
    return !(lhs == rhs)
  }
}

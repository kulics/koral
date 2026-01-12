public struct UnionCase {
  public let name: String
  public let parameters: [(name: String, type: Type)]
}

public indirect enum Type: CustomStringConvertible {
  case int
  case int8
  case int16
  case int32
  case int64
  case uint
  case uint8
  case uint16
  case uint32
  case uint64
  case float32
  case float64
  case bool
  case void
  case never
  case function(parameters: [Parameter], returns: Type)
  case structure(name: String, members: [(name: String, type: Type, mutable: Bool)], isGenericInstantiation: Bool)
  case reference(inner: Type)
  case pointer(element: Type)
  case genericParameter(name: String)
  case union(name: String, cases: [UnionCase], isGenericInstantiation: Bool)


  public var description: String {
    switch self {
    case .int: return "Int"
    case .int8: return "Int8"
    case .int16: return "Int16"
    case .int32: return "Int32"
    case .int64: return "Int64"
    case .uint: return "UInt"
    case .uint8: return "UInt8"
    case .uint16: return "UInt16"
    case .uint32: return "UInt32"
    case .uint64: return "UInt64"
    case .float32: return "Float32"
    case .float64: return "Float64"
    case .bool: return "Bool"
    case .void: return "Void"
    case .never: return "Never"
    case .function(let params, let returns):
      let paramTypes = params.map { $0.type.description }.joined(separator: ", ")
      return "(\(paramTypes)) -> \(returns)"
    case .structure(let name, _, _):
      return name
    case .union(let name, _, _):
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
    case .int8: return "I8"
    case .int16: return "I16"
    case .int32: return "I32"
    case .int64: return "I64"
    case .uint: return "U"
    case .uint8: return "U8"
    case .uint16: return "U16"
    case .uint32: return "U32"
    case .uint64: return "U64"
    case .float32: return "F32"
    case .float64: return "F64"
    case .bool: return "B"
    case .void: return "V"
    case .never: return "N"
    case .function: return "Fn"
    case .reference: return "R"
    case .pointer(_): return "P"
    case .structure(_, let members, _):
      let memberKeys = members.map { $0.type.layoutKey }.joined(separator: "_")
      return "Struct_\(memberKeys)"
    case .union(_, let cases, _):
      let caseKeys = cases.map { c in 
          c.name + "_" + c.parameters.map { $0.type.layoutKey }.joined(separator: "_")
      }.joined(separator: "_OR_")
      return "Union_\(caseKeys)"
    case .genericParameter(let name):
      return "Param_\(name)"
    }
  }

  public var containsGenericParameter: Bool {
    switch self {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64, .bool, .void, .never:
      return false
    case .function(let params, let returns):
      return returns.containsGenericParameter || params.contains { $0.type.containsGenericParameter }
    case .structure(_, let members, _):
      return members.contains { $0.type.containsGenericParameter }
    case .union(_, let cases, _):
      return cases.contains { c in c.parameters.contains { $0.type.containsGenericParameter } }
    case .reference(let inner):
      return inner.containsGenericParameter
    case .pointer(let element):
       return element.containsGenericParameter
    case .genericParameter:
      return true
    }
  }
  
  public var functionParameters: [Parameter]? {
      if case .function(let params, _) = self { return params }
      return nil
  }

  public var canonical: Type {
    switch self {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64, .bool, .void, .never: return self
    case .reference(_): return .reference(inner: .void)
    case .pointer(let element): return .pointer(element: element.canonical) 
    case .structure(let name, let members, let isGenericInstantiation):
      if isGenericInstantiation {
        let newMembers = members.map { ($0.name, $0.type.canonical, $0.mutable) }
        return .structure(name: name, members: newMembers, isGenericInstantiation: true)
      } else {
        return self
      }
    case .union(let name, let cases, let isGenericInstantiation):
      if isGenericInstantiation {
        let newCases = cases.map { UnionCase(name: $0.name, parameters: $0.parameters.map { p in (name: p.name, type: p.type.canonical) }) }
        return .union(name: name, cases: newCases, isGenericInstantiation: true)
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
      (.int8, .int8), (.int16, .int16), (.int32, .int32), (.int64, .int64),
      (.uint, .uint), (.uint8, .uint8), (.uint16, .uint16), (.uint32, .uint32), (.uint64, .uint64),
      (.float32, .float32), (.float64, .float64),
      (.bool, .bool),
      (.void, .void),
      (.never, .never):
      return true

    case (.function(let lParams, let lReturns), .function(let rParams, let rReturns)):
      return lParams == rParams && lReturns == rReturns

    case (.structure(let lName, _, _), .structure(let rName, _, _)):
      return lName == rName
    case (.union(let lName, _, _), .union(let rName, _, _)):
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

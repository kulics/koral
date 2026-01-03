public class Scope {
  private var symbols: [String: (Type, Bool)]  // (type, mutability)
  private let parent: Scope?
  private var types: [String: Type] = [:]

  public init(parent: Scope? = nil) {
    self.symbols = [:]
    self.parent = parent
  }

  public func define(_ name: String, _ type: Type, mutable: Bool) {
    symbols[name] = (type, mutable)
  }

  public func lookup(_ name: String) -> Type? {
    if let (type, _) = symbols[name] {
      return type
    }
    return parent?.lookup(name)
  }

  public func isMutable(_ name: String) -> Bool {
    if let (_, mutable) = symbols[name] {
      return mutable
    }
    return parent?.isMutable(name) ?? false
  }

  public func createChild() -> Scope {
    return Scope(parent: self)
  }

  public func defineType(_ name: String, type: Type) throws {
    types[name] = type
  }

  public func lookupType(_ name: String) -> Type? {
    if let type = types[name] {
      return type
    }
    return parent?.lookupType(name)
  }

  public func resolveType(_ name: String) -> Type? {
    return switch name {
    case "Int":
      .int
    case "Float":
      .float
    case "String":
      .string
    case "Bool":
      .bool
    case "Void":
      .void
    default:
      lookupType(name)
    }
  }
}

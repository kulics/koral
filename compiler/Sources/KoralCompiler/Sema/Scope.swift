public struct GenericTemplate {
  public let name: String
  public let typeParameters: [String]
  public let parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)]
}

public struct GenericFunctionTemplate {
  public let name: String
  public let typeParameters: [String]
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let body: ExpressionNode
  public let access: AccessModifier
}

public class Scope {
  private var symbols: [String: (Type, Bool)]  // (type, mutability)
  private let parent: Scope?
  private var types: [String: Type] = [:]
  private var genericTemplates: [String: GenericTemplate] = [:]
  private var genericFunctionTemplates: [String: GenericFunctionTemplate] = [:]

  public init(parent: Scope? = nil) {
    self.symbols = [:]
    self.parent = parent
  }

  public func define(_ name: String, _ type: Type, mutable: Bool) {
    symbols[name] = (type, mutable)
  }

  public func defineGenericTemplate(_ name: String, template: GenericTemplate) {
    genericTemplates[name] = template
  }

  public func lookupGenericTemplate(_ name: String) -> GenericTemplate? {
    if let template = genericTemplates[name] {
      return template
    }
    return parent?.lookupGenericTemplate(name)
  }

  public func defineGenericFunctionTemplate(_ name: String, template: GenericFunctionTemplate) {
    genericFunctionTemplates[name] = template
  }

  public func lookupGenericFunctionTemplate(_ name: String) -> GenericFunctionTemplate? {
    if let template = genericFunctionTemplates[name] {
      return template
    }
    return parent?.lookupGenericFunctionTemplate(name)
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

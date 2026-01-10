public struct GenericStructTemplate {
  public let name: String
  public let typeParameters: [(name: String, type: TypeNode?)]
  public let parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)]
  public let isCopy: Bool
}

public struct GenericUnionTemplate {
  public let name: String
  public let typeParameters: [(name: String, type: TypeNode?)]
  public let cases: [UnionCaseDeclaration]
  public let access: AccessModifier
}

public struct GenericFunctionTemplate {
  public let name: String
  public let typeParameters: [(name: String, type: TypeNode?)]
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let body: ExpressionNode
  public let access: AccessModifier
}

public class Scope {
  private var symbols: [String: (Type, Bool)]  // (type, mutability)
  private let parent: Scope?
  private var types: [String: Type] = [:]
  private var genericStructTemplates: [String: GenericStructTemplate] = [:]
  private var genericUnionTemplates: [String: GenericUnionTemplate] = [:]
  private var genericFunctionTemplates: [String: GenericFunctionTemplate] = [:]
  private var movedVariables: Set<String> = []

  public init(parent: Scope? = nil) {
    self.symbols = [:]
    self.parent = parent
  }

  public func markMoved(_ name: String) {
    if symbols[name] != nil {
      movedVariables.insert(name)
    } else {
      parent?.markMoved(name)
    }
  }

  public func isMoved(_ name: String) -> Bool {
    if symbols[name] != nil {
      return movedVariables.contains(name)
    }
    return parent?.isMoved(name) ?? false
  }

  public func define(_ name: String, _ type: Type, mutable: Bool) {
    symbols[name] = (type, mutable)
  }

  public func defineGenericStructTemplate(_ name: String, template: GenericStructTemplate) {
    genericStructTemplates[name] = template
  }

  public func defineGenericUnionTemplate(_ name: String, template: GenericUnionTemplate) {
    genericUnionTemplates[name] = template
  }

  public func lookupGenericStructTemplate(_ name: String) -> GenericStructTemplate? {
    if let template = genericStructTemplates[name] {
      return template
    }
    return parent?.lookupGenericStructTemplate(name)
  }

  public func lookupGenericUnionTemplate(_ name: String) -> GenericUnionTemplate? {
    if let template = genericUnionTemplates[name] {
      return template
    }
    return parent?.lookupGenericUnionTemplate(name)
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

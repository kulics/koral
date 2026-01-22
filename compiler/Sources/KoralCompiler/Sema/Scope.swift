public struct GenericStructTemplate {
  public let name: String
  public let typeParameters: [TypeParameterDecl]
  public let parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)]
}

public struct GenericUnionTemplate {
  public let name: String
  public let typeParameters: [TypeParameterDecl]
  public let cases: [UnionCaseDeclaration]
  public let access: AccessModifier
}

public struct GenericFunctionTemplate {
  public let name: String
  public let typeParameters: [TypeParameterDecl]
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let body: ExpressionNode
  public let access: AccessModifier
  
  // Declaration-time type checking results (using genericParameter types)
  public var checkedBody: TypedExpressionNode?
  public var checkedParameters: [Symbol]?
  public var checkedReturnType: Type?
  
  public init(
    name: String,
    typeParameters: [TypeParameterDecl],
    parameters: [(name: String, mutable: Bool, type: TypeNode)],
    returnType: TypeNode,
    body: ExpressionNode,
    access: AccessModifier,
    checkedBody: TypedExpressionNode? = nil,
    checkedParameters: [Symbol]? = nil,
    checkedReturnType: Type? = nil
  ) {
    self.name = name
    self.typeParameters = typeParameters
    self.parameters = parameters
    self.returnType = returnType
    self.body = body
    self.access = access
    self.checkedBody = checkedBody
    self.checkedParameters = checkedParameters
    self.checkedReturnType = checkedReturnType
  }
}

public class Scope {
  private var symbols: [String: (Type, Bool)]  // (type, mutability)
  private let parent: Scope?
  private var types: [String: Type] = [:]
  /// Private types indexed by "name@sourceFile"
  private var privateTypes: [String: Type] = [:]
  /// Private symbols indexed by "name@sourceFile" with full info
  private var privateSymbols: [String: (type: Type, mutable: Bool, sourceFile: String)] = [:]
  private var genericStructTemplates: [String: GenericStructTemplate] = [:]
  private var genericUnionTemplates: [String: GenericUnionTemplate] = [:]
  private var genericFunctionTemplates: [String: GenericFunctionTemplate] = [:]
  private var movedVariables: Set<String> = []
  /// Module path for symbols (symbol name -> module path)
  private var symbolModulePaths: [String: [String]] = [:]

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
  
  /// Define a symbol with module path information
  public func defineWithModulePath(_ name: String, _ type: Type, mutable: Bool, modulePath: [String]) {
    symbols[name] = (type, mutable)
    symbolModulePaths[name] = modulePath
  }
  
  /// Define a private symbol with file isolation
  public func definePrivateSymbol(_ name: String, sourceFile: String, type: Type, mutable: Bool) {
    let key = "\(name)@\(sourceFile)"
    privateSymbols[key] = (type: type, mutable: mutable, sourceFile: sourceFile)
  }
  
  /// Lookup a symbol, checking private symbols for the given source file first
  public func lookup(_ name: String, sourceFile: String? = nil) -> Type? {
    // First check private symbols for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let info = privateSymbols[key] {
        return info.type
      }
    }
    // Then check public/protected symbols
    if let (type, _) = symbols[name] {
      return type
    }
    return parent?.lookup(name, sourceFile: sourceFile)
  }
  
  /// Lookup a symbol and return full info including whether it's private
  /// Returns: (type, mutable, isPrivate, sourceFile, modulePath)
  public func lookupWithInfo(_ name: String, sourceFile: String? = nil) -> (type: Type, mutable: Bool, isPrivate: Bool, sourceFile: String?, modulePath: [String])? {
    // First check private symbols for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let info = privateSymbols[key] {
        return (type: info.type, mutable: info.mutable, isPrivate: true, sourceFile: info.sourceFile, modulePath: symbolModulePaths[name] ?? [])
      }
    }
    // Then check public/protected symbols
    if let (type, mutable) = symbols[name] {
      return (type: type, mutable: mutable, isPrivate: false, sourceFile: nil, modulePath: symbolModulePaths[name] ?? [])
    }
    return parent?.lookupWithInfo(name, sourceFile: sourceFile)
  }
  
  /// Check if a symbol is mutable, checking private symbols for the given source file first
  public func isMutable(_ name: String, sourceFile: String? = nil) -> Bool {
    // First check private symbols for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let info = privateSymbols[key] {
        return info.mutable
      }
    }
    // Then check public/protected symbols
    if let (_, mutable) = symbols[name] {
      return mutable
    }
    return parent?.isMutable(name, sourceFile: sourceFile) ?? false
  }

  /// Checks if a type or generic template with the given name is already defined in this scope.
  public func hasTypeDefinition(_ name: String) -> Bool {
    return types[name] != nil || 
           genericStructTemplates[name] != nil || 
           genericUnionTemplates[name] != nil
  }

  /// Checks if a function symbol or generic function template is already defined in this scope.
  public func hasFunctionDefinition(_ name: String) -> Bool {
     return symbols[name] != nil || genericFunctionTemplates[name] != nil
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

  public func createChild() -> Scope {
    return Scope(parent: self)
  }

  public func defineType(_ name: String, type: Type, line: Int? = nil) throws {
    if types[name] != nil {
      throw SemanticError.duplicateDefinition(name, line: line)
    }
    types[name] = type
  }

  // Overwrite existing type entry (used for resolving recursive types placeholders)
  public func overwriteType(_ name: String, type: Type) {
    types[name] = type
  }
  
  /// Define a private type with file isolation
  public func definePrivateType(_ name: String, sourceFile: String, type: Type) throws {
    let key = "\(name)@\(sourceFile)"
    if privateTypes[key] != nil {
      throw SemanticError.duplicateDefinition(name)
    }
    privateTypes[key] = type
  }
  
  /// Overwrite a private type (used for resolving recursive types)
  public func overwritePrivateType(_ name: String, sourceFile: String, type: Type) {
    let key = "\(name)@\(sourceFile)"
    privateTypes[key] = type
  }
  
  /// Lookup a type, checking private types for the given source file first
  public func lookupType(_ name: String, sourceFile: String? = nil) -> Type? {
    // First check private types for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let type = privateTypes[key] {
        return type
      }
    }
    // Then check public/protected types
    if let type = types[name] {
      return type
    }
    return parent?.lookupType(name, sourceFile: sourceFile)
  }

  public func lookupType(_ name: String) -> Type? {
    if let type = types[name] {
      return type
    }
    return parent?.lookupType(name)
  }

  public func resolveType(_ name: String) -> Type? {
    return resolveType(name, sourceFile: nil)
  }
  
  /// Resolve a type name, checking private types for the given source file first
  public func resolveType(_ name: String, sourceFile: String?) -> Type? {
    return switch name {
    case "Int":
      .int
    case "Int8":
      .int8
    case "Int16":
      .int16
    case "Int32":
      .int32
    case "Int64":
      .int64
    case "UInt":
      .uint
    case "UInt8":
      .uint8
    case "UInt16":
      .uint16
    case "UInt32":
      .uint32
    case "UInt64":
      .uint64
    case "Float32":
      .float32
    case "Float64":
      .float64
    case "Bool":
      .bool
    case "Void":
      .void
    default:
      lookupType(name, sourceFile: sourceFile)
    }
  }

  /// Returns all generic struct templates defined in this scope and parent scopes.
  public func getAllGenericStructTemplates() -> [String: GenericStructTemplate] {
    var result = parent?.getAllGenericStructTemplates() ?? [:]
    for (name, template) in genericStructTemplates {
      result[name] = template
    }
    return result
  }

  /// Returns all generic union templates defined in this scope and parent scopes.
  public func getAllGenericUnionTemplates() -> [String: GenericUnionTemplate] {
    var result = parent?.getAllGenericUnionTemplates() ?? [:]
    for (name, template) in genericUnionTemplates {
      result[name] = template
    }
    return result
  }

  /// Returns all generic function templates defined in this scope and parent scopes.
  public func getAllGenericFunctionTemplates() -> [String: GenericFunctionTemplate] {
    var result = parent?.getAllGenericFunctionTemplates() ?? [:]
    for (name, template) in genericFunctionTemplates {
      result[name] = template
    }
    return result
  }
  
  /// Returns all concrete (non-generic) types defined in this scope and parent scopes.
  public func getAllConcreteTypes() -> [String: Type] {
    var result = parent?.getAllConcreteTypes() ?? [:]
    for (name, type) in types {
      // Skip generic parameters and Self
      if case .genericParameter = type { continue }
      if name == "Self" { continue }
      result[name] = type
    }
    return result
  }
}

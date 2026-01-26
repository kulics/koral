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
  /// Set of function symbols (not closure variables)
  private var functionSymbols: Set<String> = []
  /// 直接可用符号集合（local、memberImport、batchImport）
  /// 这些符号可以不带模块前缀直接访问
  private var directlyAccessibleSymbols: Set<String> = []
  /// 直接可用类型集合
  private var directlyAccessibleTypes: Set<String> = []
  /// 泛型参数（名称 -> Type）- 与普通类型分开存储
  /// 泛型参数在查找时具有最高优先级，避免被误判为其他模块的符号
  private var genericParameters: [String: Type] = [:]

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
  
  /// 定义一个直接可用的符号（local、memberImport、batchImport）
  /// 这些符号可以不带模块前缀直接访问
  public func defineAsDirectlyAccessible(_ name: String, _ type: Type, mutable: Bool) {
    symbols[name] = (type, mutable)
    directlyAccessibleSymbols.insert(name)
  }
  
  /// 定义泛型参数
  /// 泛型参数与普通类型分开存储，在查找时具有最高优先级
  /// 这确保泛型参数（如 Map<K, V> 的 V）不会被误判为其他模块的符号（如 types.V）
  public func defineGenericParameter(_ name: String, type: Type) {
    genericParameters[name] = type
  }
  
  /// 检查是否是泛型参数
  /// 递归检查当前作用域和父作用域
  public func isGenericParameter(_ name: String) -> Bool {
    if genericParameters[name] != nil {
      return true
    }
    return parent?.isGenericParameter(name) ?? false
  }
  
  /// 定义一个直接可用的函数符号
  public func defineFunctionAsDirectlyAccessible(_ name: String, _ type: Type, modulePath: [String]) {
    symbols[name] = (type, false)
    functionSymbols.insert(name)
    symbolModulePaths[name] = modulePath
    directlyAccessibleSymbols.insert(name)
  }
  
  /// 检查符号是否可以直接访问（不需要模块前缀）
  public func isDirectlyAccessible(_ name: String) -> Bool {
    if directlyAccessibleSymbols.contains(name) {
      return true
    }
    return parent?.isDirectlyAccessible(name) ?? false
  }
  
  /// 定义一个直接可用的类型
  public func defineTypeAsDirectlyAccessible(_ name: String, type: Type, line: Int? = nil) throws {
    if types[name] != nil {
      throw SemanticError.duplicateDefinition(name, line: line)
    }
    types[name] = type
    directlyAccessibleTypes.insert(name)
  }
  
  /// 检查类型是否可以直接访问（不需要模块前缀）
  public func isTypeDirectlyAccessible(_ name: String) -> Bool {
    if directlyAccessibleTypes.contains(name) {
      return true
    }
    return parent?.isTypeDirectlyAccessible(name) ?? false
  }

  /// 检查类型名是否是当前作用域内的局部绑定（如泛型替换、Self 绑定）
  /// 仅在子作用域中生效，避免影响全局可见性检查
  public func isLocalTypeBinding(_ name: String) -> Bool {
    guard parent != nil else { return false }
    return types[name] != nil
  }
  
  /// Define a function symbol (not a closure variable)
  public func defineFunction(_ name: String, _ type: Type) {
    symbols[name] = (type, false)  // Functions are always immutable
    functionSymbols.insert(name)
  }
  
  /// Define a function symbol with module path information
  public func defineFunctionWithModulePath(_ name: String, _ type: Type, modulePath: [String]) {
    symbols[name] = (type, false)  // Functions are always immutable
    functionSymbols.insert(name)
    symbolModulePaths[name] = modulePath
  }
  
  /// Check if a symbol is a function (not a closure variable)
  public func isFunction(_ name: String, sourceFile: String? = nil) -> Bool {
    // Check private function symbols first
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if privateFunctionSymbols.contains(key) {
        return true
      }
    }
    // Then check public function symbols
    if functionSymbols.contains(name) {
      return true
    }
    return parent?.isFunction(name, sourceFile: sourceFile) ?? false
  }
  
  /// Define a symbol with module path information
  public func defineWithModulePath(_ name: String, _ type: Type, mutable: Bool, modulePath: [String]) {
    symbols[name] = (type, mutable)
    symbolModulePaths[name] = modulePath
  }
  
  /// Define a private symbol with file isolation
  public func definePrivateSymbol(_ name: String, sourceFile: String, type: Type, mutable: Bool, modulePath: [String] = []) {
    let key = "\(name)@\(sourceFile)"
    privateSymbols[key] = (type: type, mutable: mutable, sourceFile: sourceFile)
    symbolModulePaths[name] = modulePath
  }
  
  /// Private function symbols indexed by "name@sourceFile"
  private var privateFunctionSymbols: Set<String> = []
  
  /// Define a private function symbol with file isolation
  public func definePrivateFunction(_ name: String, sourceFile: String, type: Type, modulePath: [String] = []) {
    let key = "\(name)@\(sourceFile)"
    privateSymbols[key] = (type: type, mutable: false, sourceFile: sourceFile)
    privateFunctionSymbols.insert(key)
    symbolModulePaths[name] = modulePath
  }
  
  /// Check if a symbol is a private function
  public func isPrivateFunction(_ name: String, sourceFile: String) -> Bool {
    let key = "\(name)@\(sourceFile)"
    if privateFunctionSymbols.contains(key) {
      return true
    }
    return parent?.isPrivateFunction(name, sourceFile: sourceFile) ?? false
  }
  
  /// Lookup a symbol, checking generic parameters first, then private symbols for the given source file
  public func lookup(_ name: String, sourceFile: String? = nil) -> Type? {
    // 1. 首先检查泛型参数（最高优先级）
    // 这确保泛型参数（如 Map 的 V）不会被误判为其他模块的符号（如 types.V）
    if let genericType = genericParameters[name] {
      return genericType
    }
    // 2. Check private symbols for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let info = privateSymbols[key] {
        return info.type
      }
    }
    // 3. Then check public/protected symbols
    if let (type, _) = symbols[name] {
      return type
    }
    // 4. 递归查找父作用域
    return parent?.lookup(name, sourceFile: sourceFile)
  }
  
  /// Lookup a symbol and return full info including whether it's private
  /// Returns: (type, mutable, isPrivate, sourceFile, modulePath)
  public func lookupWithInfo(_ name: String, sourceFile: String? = nil) -> (type: Type, mutable: Bool, isPrivate: Bool, sourceFile: String?, modulePath: [String])? {
    // 1. 首先检查泛型参数（最高优先级）
    // 泛型参数不可变，不是 private，没有 sourceFile 和 modulePath
    if let genericType = genericParameters[name] {
      return (type: genericType, mutable: false, isPrivate: false, sourceFile: nil, modulePath: [])
    }
    // 2. Check private symbols for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let info = privateSymbols[key] {
        return (type: info.type, mutable: info.mutable, isPrivate: true, sourceFile: info.sourceFile, modulePath: symbolModulePaths[name] ?? [])
      }
    }
    // 3. Then check public/protected symbols
    if let (type, mutable) = symbols[name] {
      return (type: type, mutable: mutable, isPrivate: false, sourceFile: nil, modulePath: symbolModulePaths[name] ?? [])
    }
    // 4. 递归查找父作用域
    return parent?.lookupWithInfo(name, sourceFile: sourceFile)
  }

  /// Lookup a symbol only in the current scope (no parent traversal)
  /// Returns: (type, mutable, isPrivate, sourceFile, modulePath)
  public func lookupWithInfoLocal(_ name: String, sourceFile: String? = nil) -> (type: Type, mutable: Bool, isPrivate: Bool, sourceFile: String?, modulePath: [String])? {
    // Generic parameters in the current scope
    if let genericType = genericParameters[name] {
      return (type: genericType, mutable: false, isPrivate: false, sourceFile: nil, modulePath: [])
    }
    // Private symbols in the current scope for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let info = privateSymbols[key] {
        return (type: info.type, mutable: info.mutable, isPrivate: true, sourceFile: info.sourceFile, modulePath: symbolModulePaths[name] ?? [])
      }
    }
    // Public/protected symbols in the current scope
    if let (type, mutable) = symbols[name] {
      return (type: type, mutable: mutable, isPrivate: false, sourceFile: nil, modulePath: symbolModulePaths[name] ?? [])
    }
    return nil
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
  
  /// Lookup a type, checking generic parameters first, then private types for the given source file
  public func lookupType(_ name: String, sourceFile: String? = nil) -> Type? {
    var visited: Set<ObjectIdentifier> = []
    return lookupTypeInternal(name, sourceFile: sourceFile, visited: &visited)
  }

  public func lookupType(_ name: String) -> Type? {
    var visited: Set<ObjectIdentifier> = []
    return lookupTypeInternal(name, sourceFile: nil, visited: &visited)
  }

  private func lookupTypeInternal(
    _ name: String,
    sourceFile: String?,
    visited: inout Set<ObjectIdentifier>
  ) -> Type? {
    let id = ObjectIdentifier(self)
    if visited.contains(id) {
      return nil
    }
    visited.insert(id)

    // 1. 首先检查泛型参数（最高优先级）
    if let genericType = genericParameters[name] {
      return genericType
    }
    // 2. Check private types for the current file
    if let sourceFile = sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let type = privateTypes[key] {
        return type
      }
    }
    // 3. Then check public/protected types
    if let type = types[name] {
      return type
    }
    // 4. 递归查找父作用域
    return parent?.lookupTypeInternal(name, sourceFile: sourceFile, visited: &visited)
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

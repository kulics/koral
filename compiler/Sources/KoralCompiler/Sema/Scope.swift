public struct GenericStructTemplate {
  public let defId: DefId
  public let typeParameters: [TypeParameterDecl]
  public let parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)]

  public func name(in map: DefIdMap) -> String? {
    return map.getName(defId)
  }
}

public struct GenericUnionTemplate {
  public let defId: DefId
  public let typeParameters: [TypeParameterDecl]
  public let cases: [UnionCaseDeclaration]

  public func name(in map: DefIdMap) -> String? {
    return map.getName(defId)
  }

  public func access(in map: DefIdMap) -> AccessModifier? {
    return map.getAccess(defId)
  }
}

public struct GenericFunctionTemplate {
  public let defId: DefId
  public let typeParameters: [TypeParameterDecl]
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let body: ExpressionNode

  // Declaration-time type checking results (using genericParameter types)
  public var checkedBody: TypedExpressionNode?
  public var checkedParameters: [Symbol]?
  public var checkedReturnType: Type?

  public func name(in map: DefIdMap) -> String? {
    return map.getName(defId)
  }

  public func access(in map: DefIdMap) -> AccessModifier? {
    return map.getAccess(defId)
  }
}

public class UnifiedScope {
  private var names: [String: DefId] = [:]
  private var privateNames: [String: DefId] = [:]
  private var typeNames: [String: DefId] = [:]
  private var privateTypeNames: [String: DefId] = [:]
  private var genericParameters: [String: DefId] = [:]
  private var movedVariables: Set<String> = []
  private var functionSymbols: Set<String> = []
  private var privateFunctionSymbols: Set<String> = []
  private var directlyAccessible: Set<String> = []
  private var directlyAccessibleTypes: Set<String> = []
  private let parent: UnifiedScope?
  private weak var defIdMap: DefIdMap?

  public init(parent: UnifiedScope? = nil, defIdMap: DefIdMap? = nil) {
    self.parent = parent
    self.defIdMap = defIdMap ?? parent?.defIdMap
  }

  public func updateDefIdMap(_ map: DefIdMap) {
    self.defIdMap = map
  }

  public func markMoved(_ name: String) {
    if names[name] != nil {
      movedVariables.insert(name)
    } else {
      parent?.markMoved(name)
    }
  }

  public func isMoved(_ name: String) -> Bool {
    if names[name] != nil {
      return movedVariables.contains(name)
    }
    return parent?.isMoved(name) ?? false
  }

  public func define(_ name: String, defId: DefId) {
    names[name] = defId
  }

  public func define(
    _ name: String,
    _ type: Type,
    mutable: Bool,
    modulePath: [String] = [],
    sourceFile: String = "",
    access: AccessModifier = .default
  ) {
    guard let map = defIdMap else {
      return
    }
    let kind: SymbolKind = .variable(mutable ? .MutableValue : .Value)
    let defId = map.allocate(
      modulePath: modulePath,
      name: name,
      kind: .variable,
      sourceFile: sourceFile,
      access: access,
      span: .unknown
    )
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: kind,
      methodKind: .normal,
      isMutable: mutable
    )
    names[name] = defId
  }

  public func definePrivate(_ name: String, sourceFile: String, defId: DefId) {
    privateNames["\(name)@\(sourceFile)"] = defId
  }

  public func defineGenericParameter(_ name: String, defId: DefId) {
    genericParameters[name] = defId
  }

  public func defineGenericParameter(_ name: String, type: Type) {
    guard let map = defIdMap else {
      return
    }
    let defId = map.allocate(
      modulePath: [],
      name: name,
      kind: .variable,
      sourceFile: "",
      access: .default,
      span: .unknown
    )
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: .type,
      methodKind: .normal,
      isMutable: false
    )
    genericParameters[name] = defId
  }

  public func defineDirectlyAccessible(_ name: String, defId: DefId) {
    names[name] = defId
    directlyAccessible.insert(name)
  }

  public func defineFunction(_ name: String, defId: DefId, directlyAccessible: Bool = false, isPrivate: Bool = false, sourceFile: String? = nil) {
    names[name] = defId
    functionSymbols.insert(name)
    if directlyAccessible {
      self.directlyAccessible.insert(name)
    }
    if isPrivate, let sourceFile {
      privateFunctionSymbols.insert("\(name)@\(sourceFile)")
    }
  }

  public func defineFunctionWithModulePath(_ name: String, _ type: Type, modulePath: [String]) {
    guard let map = defIdMap else {
      return
    }
    let defId = map.allocate(
      modulePath: modulePath,
      name: name,
      kind: .function,
      sourceFile: "",
      access: .default,
      span: .unknown
    )
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: .function,
      methodKind: .normal,
      isMutable: false
    )
    names[name] = defId
    functionSymbols.insert(name)
  }

  public func definePrivateFunction(_ name: String, sourceFile: String, type: Type, modulePath: [String] = []) {
    guard let map = defIdMap else {
      return
    }
    let defId = map.allocate(
      modulePath: modulePath,
      name: name,
      kind: .function,
      sourceFile: sourceFile,
      access: .private,
      span: .unknown
    )
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: .function,
      methodKind: .normal,
      isMutable: false
    )
    privateNames["\(name)@\(sourceFile)"] = defId
    privateFunctionSymbols.insert("\(name)@\(sourceFile)")
    names[name] = defId
    functionSymbols.insert(name)
  }

  public func defineWithModulePath(_ name: String, _ type: Type, mutable: Bool, modulePath: [String]) {
    define(name, type, mutable: mutable, modulePath: modulePath, sourceFile: "", access: .default)
  }

  public func definePrivateSymbol(_ name: String, sourceFile: String, type: Type, mutable: Bool, modulePath: [String] = []) {
    guard let map = defIdMap else {
      return
    }
    let defId = map.allocate(
      modulePath: modulePath,
      name: name,
      kind: .variable,
      sourceFile: sourceFile,
      access: .private,
      span: .unknown
    )
    let kind: SymbolKind = .variable(mutable ? .MutableValue : .Value)
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: kind,
      methodKind: .normal,
      isMutable: mutable
    )
    privateNames["\(name)@\(sourceFile)"] = defId
    names[name] = defId
  }

  public func lookup(_ name: String, sourceFile: String? = nil) -> DefId? {
    if let defId = genericParameters[name] {
      return defId
    }
    if let sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let defId = privateNames[key] {
        return defId
      }
    }
    if let defId = names[name] {
      return defId
    }
    return parent?.lookup(name, sourceFile: sourceFile)
  }

  public func isGenericParameter(_ name: String) -> Bool {
    if genericParameters[name] != nil {
      return true
    }
    return parent?.isGenericParameter(name) ?? false
  }

  public func isFunction(_ name: String, sourceFile: String? = nil) -> Bool {
    if let sourceFile {
      if privateFunctionSymbols.contains("\(name)@\(sourceFile)") {
        return true
      }
    }
    if functionSymbols.contains(name) {
      return true
    }
    return parent?.isFunction(name, sourceFile: sourceFile) ?? false
  }

  public func isDirectlyAccessible(_ name: String) -> Bool {
    if directlyAccessible.contains(name) {
      return true
    }
    return parent?.isDirectlyAccessible(name) ?? false
  }

  public func lookupWithInfo(
    _ name: String,
    sourceFile: String? = nil
  ) -> (type: Type, mutable: Bool, isPrivate: Bool, sourceFile: String?, modulePath: [String])? {
    if let defId = genericParameters[name], let map = defIdMap, let type = map.getSymbolType(defId) {
      return (type: type, mutable: false, isPrivate: false, sourceFile: nil, modulePath: [])
    }

    if let sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let defId = privateNames[key], let map = defIdMap, let type = map.getSymbolType(defId) {
        return (
          type: type,
          mutable: map.isSymbolMutable(defId) ?? false,
          isPrivate: true,
          sourceFile: map.getSourceFile(defId),
          modulePath: map.getModulePath(defId) ?? []
        )
      }
    }

    if let defId = names[name], let map = defIdMap, let type = map.getSymbolType(defId) {
      return (
        type: type,
        mutable: map.isSymbolMutable(defId) ?? false,
        isPrivate: map.getAccess(defId) == .private,
        sourceFile: map.getSourceFile(defId),
        modulePath: map.getModulePath(defId) ?? []
      )
    }

    return parent?.lookupWithInfo(name, sourceFile: sourceFile)
  }

  public func lookupWithInfoLocal(
    _ name: String,
    sourceFile: String? = nil
  ) -> (type: Type, mutable: Bool, isPrivate: Bool, sourceFile: String?, modulePath: [String])? {
    if let defId = genericParameters[name], let map = defIdMap, let type = map.getSymbolType(defId) {
      return (type: type, mutable: false, isPrivate: false, sourceFile: nil, modulePath: [])
    }

    if let sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let defId = privateNames[key], let map = defIdMap, let type = map.getSymbolType(defId) {
        return (
          type: type,
          mutable: map.isSymbolMutable(defId) ?? false,
          isPrivate: true,
          sourceFile: map.getSourceFile(defId),
          modulePath: map.getModulePath(defId) ?? []
        )
      }
    }

    if let defId = names[name], let map = defIdMap, let type = map.getSymbolType(defId) {
      return (
        type: type,
        mutable: map.isSymbolMutable(defId) ?? false,
        isPrivate: map.getAccess(defId) == .private,
        sourceFile: map.getSourceFile(defId),
        modulePath: map.getModulePath(defId) ?? []
      )
    }

    return nil
  }

  public func isMutable(_ name: String, sourceFile: String? = nil) -> Bool {
    if let sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let defId = privateNames[key], let map = defIdMap {
        return map.isSymbolMutable(defId) ?? false
      }
    }
    if let defId = names[name], let map = defIdMap {
      return map.isSymbolMutable(defId) ?? false
    }
    return parent?.isMutable(name, sourceFile: sourceFile) ?? false
  }

  public func hasTypeDefinition(_ name: String) -> Bool {
    return typeNames[name] != nil ||
      defIdMap?.lookupGenericStructTemplateDefId(name) != nil ||
      defIdMap?.lookupGenericUnionTemplateDefId(name) != nil
  }

  public func hasFunctionDefinition(_ name: String) -> Bool {
    return names[name] != nil || defIdMap?.lookupGenericFunctionTemplateDefId(name) != nil
  }

  public func defineType(_ name: String, type: Type, line: Int? = nil) throws {
    if typeNames[name] != nil {
      throw SemanticError.duplicateDefinition(name, line: line)
    }
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .union(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: "",
        access: .default,
        span: .unknown
      )
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, methodKind: .normal, isMutable: false)
    typeNames[name] = defId
  }

  public func overwriteType(_ name: String, type: Type) {
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .union(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: "",
        access: .default,
        span: .unknown
      )
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, methodKind: .normal, isMutable: false)
    typeNames[name] = defId
  }

  public func definePrivateType(_ name: String, sourceFile: String, type: Type) throws {
    let key = "\(name)@\(sourceFile)"
    if privateTypeNames[key] != nil {
      throw SemanticError.duplicateDefinition(name)
    }
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .union(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: sourceFile,
        access: .private,
        span: .unknown
      )
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, methodKind: .normal, isMutable: false)
    privateTypeNames[key] = defId
  }

  public func overwritePrivateType(_ name: String, sourceFile: String, type: Type) {
    let key = "\(name)@\(sourceFile)"
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .union(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: sourceFile,
        access: .private,
        span: .unknown
      )
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, methodKind: .normal, isMutable: false)
    privateTypeNames[key] = defId
  }

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

    if let defId = genericParameters[name], let map = defIdMap {
      return map.getSymbolType(defId)
    }

    if let sourceFile {
      let key = "\(name)@\(sourceFile)"
      if let defId = privateTypeNames[key], let map = defIdMap {
        return map.getSymbolType(defId)
      }
    }

    if let defId = typeNames[name], let map = defIdMap {
      return map.getSymbolType(defId)
    }

    return parent?.lookupTypeInternal(name, sourceFile: sourceFile, visited: &visited)
  }

  public func resolveType(_ name: String) -> Type? {
    return resolveType(name, sourceFile: nil)
  }

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

  public func isLocalTypeBinding(_ name: String) -> Bool {
    guard parent != nil else { return false }
    return typeNames[name] != nil
  }

  public func defineTypeAsDirectlyAccessible(_ name: String, type: Type, line: Int? = nil) throws {
    try defineType(name, type: type, line: line)
    directlyAccessibleTypes.insert(name)
  }

  public func isTypeDirectlyAccessible(_ name: String) -> Bool {
    if directlyAccessibleTypes.contains(name) {
      return true
    }
    return parent?.isTypeDirectlyAccessible(name) ?? false
  }

  public func defineGenericStructTemplate(_ name: String, template: GenericStructTemplate) {
    guard let map = defIdMap else {
      return
    }
    let info = DefIdMap.GenericStructTemplateInfo(
      typeParameters: template.typeParameters,
      parameters: template.parameters
    )
    map.registerGenericStructTemplate(name: name, defId: template.defId, info: info)
  }

  public func defineGenericUnionTemplate(_ name: String, template: GenericUnionTemplate) {
    guard let map = defIdMap else {
      return
    }
    let info = DefIdMap.GenericUnionTemplateInfo(
      typeParameters: template.typeParameters,
      cases: template.cases
    )
    map.registerGenericUnionTemplate(name: name, defId: template.defId, info: info)
  }

  public func defineGenericFunctionTemplate(_ name: String, template: GenericFunctionTemplate) {
    guard let map = defIdMap else {
      return
    }
    let info = DefIdMap.GenericFunctionTemplateInfo(
      typeParameters: template.typeParameters,
      parameters: template.parameters,
      returnType: template.returnType,
      body: template.body,
      checkedBody: template.checkedBody,
      checkedParameters: template.checkedParameters,
      checkedReturnType: template.checkedReturnType
    )
    map.registerGenericFunctionTemplate(name: name, defId: template.defId, info: info)
  }

  public func lookupGenericStructTemplate(_ name: String) -> GenericStructTemplate? {
    guard let map = defIdMap,
          let defId = map.lookupGenericStructTemplateDefId(name),
          let info = map.getGenericStructTemplateInfo(defId) else {
      return parent?.lookupGenericStructTemplate(name)
    }
    return GenericStructTemplate(defId: defId, typeParameters: info.typeParameters, parameters: info.parameters)
  }

  public func lookupGenericUnionTemplate(_ name: String) -> GenericUnionTemplate? {
    guard let map = defIdMap,
          let defId = map.lookupGenericUnionTemplateDefId(name),
          let info = map.getGenericUnionTemplateInfo(defId) else {
      return parent?.lookupGenericUnionTemplate(name)
    }
    return GenericUnionTemplate(defId: defId, typeParameters: info.typeParameters, cases: info.cases)
  }

  public func lookupGenericFunctionTemplate(_ name: String) -> GenericFunctionTemplate? {
    guard let map = defIdMap,
          let defId = map.lookupGenericFunctionTemplateDefId(name),
          let info = map.getGenericFunctionTemplateInfo(defId) else {
      return parent?.lookupGenericFunctionTemplate(name)
    }
    return GenericFunctionTemplate(
      defId: defId,
      typeParameters: info.typeParameters,
      parameters: info.parameters,
      returnType: info.returnType,
      body: info.body,
      checkedBody: info.checkedBody,
      checkedParameters: info.checkedParameters,
      checkedReturnType: info.checkedReturnType
    )
  }

  public func getAllGenericStructTemplates() -> [String: GenericStructTemplate] {
    var result = parent?.getAllGenericStructTemplates() ?? [:]
    if let map = defIdMap {
      for (name, defId) in map.genericStructTemplatesSnapshot() {
        if let info = map.getGenericStructTemplateInfo(defId) {
          result[name] = GenericStructTemplate(defId: defId, typeParameters: info.typeParameters, parameters: info.parameters)
        }
      }
    }
    return result
  }

  public func getAllGenericUnionTemplates() -> [String: GenericUnionTemplate] {
    var result = parent?.getAllGenericUnionTemplates() ?? [:]
    if let map = defIdMap {
      for (name, defId) in map.genericUnionTemplatesSnapshot() {
        if let info = map.getGenericUnionTemplateInfo(defId) {
          result[name] = GenericUnionTemplate(defId: defId, typeParameters: info.typeParameters, cases: info.cases)
        }
      }
    }
    return result
  }

  public func getAllGenericFunctionTemplates() -> [String: GenericFunctionTemplate] {
    var result = parent?.getAllGenericFunctionTemplates() ?? [:]
    if let map = defIdMap {
      for (name, defId) in map.genericFunctionTemplatesSnapshot() {
        if let info = map.getGenericFunctionTemplateInfo(defId) {
          result[name] = GenericFunctionTemplate(
            defId: defId,
            typeParameters: info.typeParameters,
            parameters: info.parameters,
            returnType: info.returnType,
            body: info.body,
            checkedBody: info.checkedBody,
            checkedParameters: info.checkedParameters,
            checkedReturnType: info.checkedReturnType
          )
        }
      }
    }
    return result
  }

  public func getAllConcreteTypes() -> [String: Type] {
    var result = parent?.getAllConcreteTypes() ?? [:]
    if let map = defIdMap {
      for (name, defId) in typeNames {
        if let type = map.getSymbolType(defId) {
          if case .genericParameter = type { continue }
          if name == "Self" { continue }
          result[name] = type
        }
      }
    }
    return result
  }

  public func createChild() -> UnifiedScope {
    return UnifiedScope(parent: self, defIdMap: defIdMap)
  }
}

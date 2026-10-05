public struct GenericStructTemplate {
  public let defId: DefId
  public let typeParameters: [TypeParameterDecl]
  public let parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier, named: Bool)]
  public let isMutable: Bool

  public func name(in map: DefIdMap) -> String? {
    return map.getName(defId)
  }
}

public struct GenericEnumTemplate {
  public let defId: DefId
  public let typeParameters: [TypeParameterDecl]
  public let cases: [EnumCaseDeclaration]

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
  public let parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)]
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

  public func defineLocal(_ name: String, defId: DefId, span: SourceSpan = .unknown) throws {
    if name == "_" {
      // Wildcard bindings are discarded; allow multiple `let _ = ...` in the same scope.
      return
    }
    if names[name] != nil {
      throw SemanticError.duplicateDefinition(name, span: span)
    }
    names[name] = defId
  }

  public func define(
    _ name: String,
    _ type: Type,
    mutable: Bool,
    modulePath: [String] = [],
    sourceFile: String = "",
    access: AccessModifier = .module_private
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
      isMutable: mutable
    )
    defineScoped(name, defId)
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
      access: .module_private,
      span: .unknown
    )
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: .type,
      isMutable: false
    )
    genericParameters[name] = defId
  }

  public func defineDirectlyAccessible(_ name: String, defId: DefId) {
    defineScoped(name, defId)
    directlyAccessible.insert(name)
  }

  public func defineFunction(_ name: String, defId: DefId, directlyAccessible: Bool = false, isPrivate: Bool = false, sourceFile: String? = nil) {
    defineScoped(name, defId)
    functionSymbols.insert(name)
    if directlyAccessible {
      self.directlyAccessible.insert(name)
    }
    if isPrivate, let sourceFile {
      privateFunctionSymbols.insert("\(name)@\(sourceFile)")
    }
  }

  public func defineFunctionWithModulePath(_ name: String, _ type: Type, modulePath: [String], access: AccessModifier = .module_private) {
    guard let map = defIdMap else {
      return
    }
    let defId = map.allocate(
      modulePath: modulePath,
      name: name,
      kind: .function,
      sourceFile: "",
      access: access,
      span: .unknown
    )
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: .function,
      isMutable: false
    )
    defineScoped(name, defId)
    functionSymbols.insert(name)
  }

  /// Binds an imported name (possibly an alias) to the ORIGINAL declaration's
  /// `DefId`, so codegen still emits/calls the declaring symbol's name.
  public func defineImportedFunction(_ name: String, sourceFile: String, defId: DefId) {
    privateNames["\(name)@\(sourceFile)"] = defId
    functionSymbols.insert(name)
  }

  /// Binds an imported value name (possibly an alias) to the ORIGINAL `DefId`.
  public func defineImportedSymbol(_ name: String, sourceFile: String, defId: DefId) {
    privateNames["\(name)@\(sourceFile)"] = defId
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
      access: .file_private,
      span: .unknown
    )
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: .function,
      isMutable: false
    )
    privateNames["\(name)@\(sourceFile)"] = defId
    privateFunctionSymbols.insert("\(name)@\(sourceFile)")
  }

  public func defineWithModulePath(_ name: String, _ type: Type, mutable: Bool, modulePath: [String], access: AccessModifier = .module_private) {
    define(name, type, mutable: mutable, modulePath: modulePath, sourceFile: "", access: access)
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
      access: .file_private,
      span: .unknown
    )
    let kind: SymbolKind = .variable(mutable ? .MutableValue : .Value)
    map.addSymbolInfo(
      defId: defId,
      type: type,
      kind: kind,
      isMutable: mutable
    )
    privateNames["\(name)@\(sourceFile)"] = defId
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
    if let defId = bindingInCurrentModule(name) {
      return defId
    }
    if let defId = bindingViaImport(name, sourceFile: sourceFile) {
      return defId
    }
    if let defId = names[name] {
      return defId
    }
    return parent?.lookup(name, sourceFile: sourceFile)
  }

  /// The binding for `name` declared in the module currently being checked.
  ///
  /// Module-scoped globals are stored under both their bare name and a
  /// module-qualified one. The bare entry keeps whichever module registered
  /// last, so a same-named `public let` in another module would shadow the
  /// local one. Looking the qualified key up first is what makes `alpha`'s
  /// `dup` resolve to `alpha`'s `dup` while checking `alpha`.
  /// The declaration `module_path` itself makes for `name`, if any.
  ///
  /// Distinct from `lookup`: the unqualified index is last-wins across modules,
  /// so it cannot answer "does THIS module declare this name?" -- which is the
  /// question a `using` has to ask before it claims the spelling (§3.3).
  public func lookupDeclared(inModule modulePath: [String], name: String) -> DefId? {
    guard let map = defIdMap, !modulePath.isEmpty else {
      return nil
    }
    return names[map.symbolKey(modulePath: modulePath, name: name)]
  }

  private func bindingInCurrentModule(_ name: String) -> DefId? {
    guard let map = defIdMap, !map.currentModulePath.isEmpty else {
      return nil
    }
    return names[map.symbolKey(modulePath: map.currentModulePath, name: name)]
  }

  /// `bindingViaImport` for TYPE names: the unqualified `typeNames[name]` is
  /// last-wins across modules, so a spelling this module imports must be
  /// resolved through the import before it is consulted.
  private func typeViaImport(_ name: String, sourceFile: String?) -> DefId? {
    guard let map = defIdMap, let graph = map.currentImportGraph, !map.currentModulePath.isEmpty else {
      return nil
    }
    if let (target, original) = graph.resolveAliasedSymbol(
      alias: name,
      inModule: map.currentModulePath,
      inSourceFile: sourceFile
    ), let defId = typeNames[map.symbolKey(modulePath: target, name: original)] {
      return defId
    }
    for edge in graph.edges
    where edge.source == map.currentModulePath
      && (edge.sourceFile == nil || edge.sourceFile == sourceFile) {
      if let defId = typeNames[map.symbolKey(modulePath: edge.target, name: name)] {
        return defId
      }
    }
    return nil
  }

  /// The binding `name` denotes in the module currently being checked, through
  /// ITS IMPORTS.
  ///
  /// Consulted after `bindingInCurrentModule` and before the unqualified
  /// `names[name]`, and that order is the point. The unqualified entry is
  /// last-wins across modules, so it cannot answer "which `Box`?" -- it answers
  /// "whichever module registered it last". A spelling that this module imports
  /// means what the import says.
  ///
  /// (rustc_resolve builds one resolution per module from that module's
  /// imports; there is no global name table to fall back on.)
  private func bindingViaImport(_ name: String, sourceFile: String?) -> DefId? {
    guard let map = defIdMap, let graph = map.currentImportGraph, !map.currentModulePath.isEmpty else {
      return nil
    }
    for e in graph.symbolImports {
    }
    // An import edge is scoped to the file the `using` appears in, so the file
    // is part of the match -- same rule `ImportGraph.getImportKind` applies.
    func visible(edgeSourceFile: String?) -> Bool {
      edgeSourceFile == nil || edgeSourceFile == sourceFile
    }
    // A symbol import binds the spelling used HERE to the name used THERE:
    // `using "m" { x }` both are `x`; `using "m" { x as y }` spells `y`, declares `x`.
    if let (target, original) = graph.resolveAliasedSymbol(
      alias: name,
      inModule: map.currentModulePath,
      inSourceFile: sourceFile
    ), let defId = names[map.symbolKey(modulePath: target, name: original)] {
      return defId
    }
    // A batch/module import (`using "m";`) creates no symbol
    // edge, so the spelling is the same in the imported module.
    for edge in graph.edges where edge.source == map.currentModulePath && visible(edgeSourceFile: edge.sourceFile) {
      if let defId = names[map.symbolKey(modulePath: edge.target, name: name)] {
        return defId
      }
    }
    return nil
  }

  /// Records a module-scoped binding under both its bare and qualified keys.
  private func defineScoped(_ name: String, _ defId: DefId) {
    names[name] = defId
    if let map = defIdMap, let modulePath = map.getModulePath(defId), !modulePath.isEmpty {
      names[map.symbolKey(modulePath: modulePath, name: name)] = defId
    }
  }

  public func isGenericParameter(_ name: String) -> Bool {
    if genericParameters[name] != nil {
      return true
    }
    return parent?.isGenericParameter(name) ?? false
  }

  /// Whether the innermost binding of `name` is a VALUE (parameter, local `let`,
  /// or generic parameter) rather than a function.
  ///
  /// Ordinary lexical scoping decides a call like `f(x)`: if `f` is bound to a
  /// parameter or local, that binding is the callee. A same-named generic
  /// function template lives in the global name space and must not reach over
  /// the local binding -- otherwise a user's `let f[...]` silently hijacks
  /// `f(it)` inside e.g. `std`'s `map`, whose parameter is also called `f`.
  ///
  /// Identity is decided by the binding's `DefKind`, not by its spelling.
  public func isValueBinding(_ name: String, sourceFile: String? = nil) -> Bool {
    guard let defId = lookup(name, sourceFile: sourceFile) else {
      return false
    }
    return defIdMap?.getKind(defId) != .function
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

    if let defId = bindingInCurrentModule(name) ?? bindingViaImport(name, sourceFile: sourceFile) ?? names[name],
       let map = defIdMap, let type = map.getSymbolType(defId) {
      return (
        type: type,
        mutable: map.isSymbolMutable(defId) ?? false,
        isPrivate: map.getAccess(defId) == .file_private,
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

    if let defId = bindingInCurrentModule(name) ?? names[name],
       let map = defIdMap, let type = map.getSymbolType(defId) {
      return (
        type: type,
        mutable: map.isSymbolMutable(defId) ?? false,
        isPrivate: map.getAccess(defId) == .file_private,
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

  public func hasFunctionDefinition(_ name: String) -> Bool {
    return names[name] != nil || defIdMap?.lookupGenericFunctionTemplateDefId(name) != nil
  }

  public func defineType(_ name: String, type: Type, span: SourceSpan = .unknown) throws {
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .`enum`(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: "",
        access: .module_private,
        span: .unknown
      )
    }
    // A top-level type is (module, name).
    let modulePath = map.getModulePath(defId) ?? []
    if typeNames[typeKey(name, modulePath: modulePath)] != nil {
      throw SemanticError.duplicateDefinition(name, span: span)
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, isMutable: false)
    defineScopedType(name, defId, modulePath: modulePath)
  }

  private func typeKey(_ name: String, modulePath: [String]) -> String {
    guard let map = defIdMap, !modulePath.isEmpty else {
      return name
    }
    return map.symbolKey(modulePath: modulePath, name: name)
  }

  private func defineScopedType(_ name: String, _ defId: DefId, modulePath: [String]) {
    typeNames[name] = defId
    if !modulePath.isEmpty {
      typeNames[typeKey(name, modulePath: modulePath)] = defId
    }
  }

  /// The type `module_path` itself declares under `name`, if any.
  ///
  /// The type table has its own module-qualified key (see `defineScopedType`),
  /// so this is the type-side twin of `lookupDeclared`.
  public func lookupDeclaredType(inModule modulePath: [String], name: String) -> DefId? {
    guard !modulePath.isEmpty else {
      return nil
    }
    return typeNames[typeKey(name, modulePath: modulePath)]
  }

  private func typeInCurrentModule(_ name: String) -> DefId? {
    guard let map = defIdMap, !map.currentModulePath.isEmpty else {
      return nil
    }
    return typeNames[map.symbolKey(modulePath: map.currentModulePath, name: name)]
  }

  /// Whether the module being checked already declares this type name.
  /// Every caller is a duplicate-definition check.
  public func hasTypeDefinition(_ name: String) -> Bool {
    guard let map = defIdMap else {
      return typeNames[name] != nil
    }
    let declaredLocally: Bool = map.currentModulePath.isEmpty
      ? typeNames[name] != nil
      : typeNames[map.symbolKey(modulePath: map.currentModulePath, name: name)] != nil
    return declaredLocally ||
      defIdMap?.lookupGenericStructTemplateDefId(name) != nil ||
      defIdMap?.lookupGenericEnumTemplateDefId(name) != nil
  }

  public func overwriteType(_ name: String, type: Type) {
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .`enum`(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: "",
        access: .module_private,
        span: .unknown
      )
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, isMutable: false)
    defineScopedType(name, defId, modulePath: map.getModulePath(defId) ?? [])
  }

  public func definePrivateType(_ name: String, sourceFile: String, type: Type) throws {
    let key = "\(name)@\(sourceFile)"
    if privateTypeNames[key] != nil {
      throw SemanticError.duplicateDefinition(name, span: .unknown)
    }
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .`enum`(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: sourceFile,
        access: .file_private,
        span: .unknown
      )
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, isMutable: false)
    privateTypeNames[key] = defId
  }

  public func overwritePrivateType(_ name: String, sourceFile: String, type: Type) {
    let key = "\(name)@\(sourceFile)"
    guard let map = defIdMap else {
      return
    }
    let defId: DefId
    switch type {
    case .structure(let typeDefId), .`enum`(let typeDefId), .opaque(let typeDefId):
      defId = typeDefId
    default:
      defId = map.allocate(
        modulePath: [],
        name: name,
        kind: .type(.structure),
        sourceFile: sourceFile,
        access: .file_private,
        span: .unknown
      )
    }
    map.addSymbolInfo(defId: defId, type: type, kind: .type, isMutable: false)
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

    if let defId = typeInCurrentModule(name), let map = defIdMap {
      return map.getSymbolType(defId)
    }

    // Whatever this module IMPORTS under this spelling wins over the unqualified
    // `typeNames[name]`, which is last-wins across modules and so cannot answer
    // "which `Box`?". See `bindingViaImport` for the full rationale.
    if let defId = typeViaImport(name, sourceFile: sourceFile), let map = defIdMap {
      return map.getSymbolType(defId)
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

  public func defineTypeAsDirectlyAccessible(_ name: String, type: Type, span: SourceSpan = .unknown) throws {
    try defineType(name, type: type, span: span)
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
      parameters: template.parameters,
      isMutable: template.isMutable
    )
    map.registerGenericStructTemplate(name: name, defId: template.defId, info: info)
  }

  public func defineGenericEnumTemplate(_ name: String, template: GenericEnumTemplate) {
    guard let map = defIdMap else {
      return
    }
    let info = DefIdMap.GenericEnumTemplateInfo(
      typeParameters: template.typeParameters,
      cases: template.cases
    )
    map.registerGenericEnumTemplate(name: name, defId: template.defId, info: info)
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

  /// Resolve a generic template from a SOURCE SPELLING.
  ///
  /// This is the one place a name decides something: it is called from
  /// `resolveTypeNode` on a `TypeNode`, i.e. while reading a path written by the
  /// user. Afterwards the `Type` carries the template's `DefId` and nothing
  /// re-reads the name.
  ///
  /// Equivalent to rustc's path resolution in `rustc_resolve`, which turns a
  /// `Res::Def(DefKind::Struct, DefId)` and hands the `DefId` on; the name never
  /// reaches type checking. Lookup prefers the module being checked and then
  /// falls back to the bare name for cross-module references (`List` from Std).
  public func lookupGenericStructTemplate(_ name: String) -> GenericStructTemplate? {
    guard let map = defIdMap,
          let defId = map.lookupGenericStructTemplateDefId(name),
          let info = map.getGenericStructTemplateInfo(defId) else {
      return parent?.lookupGenericStructTemplate(name)
    }
    return GenericStructTemplate(defId: defId, typeParameters: info.typeParameters, parameters: info.parameters, isMutable: info.isMutable)
  }

  /// The generic struct template with this DECLARATION identity.
  ///
  /// Unlike `lookupGenericStructTemplate(_:)` no name is read: the caller has
  /// already resolved one and is now asking about the declaration itself.
  public func genericStructTemplate(defId: DefId) -> GenericStructTemplate? {
    guard let map = defIdMap, let info = map.getGenericStructTemplateInfo(defId) else {
      return parent?.genericStructTemplate(defId: defId)
    }
    return GenericStructTemplate(defId: defId, typeParameters: info.typeParameters, parameters: info.parameters, isMutable: info.isMutable)
  }

  /// The generic enum template with this DECLARATION identity. See
  /// `genericStructTemplate(defId:)`.
  public func genericEnumTemplate(defId: DefId) -> GenericEnumTemplate? {
    guard let map = defIdMap, let info = map.getGenericEnumTemplateInfo(defId) else {
      return parent?.genericEnumTemplate(defId: defId)
    }
    return GenericEnumTemplate(defId: defId, typeParameters: info.typeParameters, cases: info.cases)
  }

  /// Resolve a generic enum template from a SOURCE SPELLING. See
  /// `lookupGenericStructTemplate`.
  public func lookupGenericEnumTemplate(_ name: String) -> GenericEnumTemplate? {
    guard let map = defIdMap,
          let defId = map.lookupGenericEnumTemplateDefId(name),
          let info = map.getGenericEnumTemplateInfo(defId) else {
      return parent?.lookupGenericEnumTemplate(name)
    }
    return GenericEnumTemplate(defId: defId, typeParameters: info.typeParameters, cases: info.cases)
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
          result[name] = GenericStructTemplate(defId: defId, typeParameters: info.typeParameters, parameters: info.parameters, isMutable: info.isMutable)
        }
      }
    }
    return result
  }

  public func getAllGenericEnumTemplates() -> [String: GenericEnumTemplate] {
    var result = parent?.getAllGenericEnumTemplates() ?? [:]
    if let map = defIdMap {
      for (name, defId) in map.genericEnumTemplatesSnapshot() {
        if let info = map.getGenericEnumTemplateInfo(defId) {
          result[name] = GenericEnumTemplate(defId: defId, typeParameters: info.typeParameters, cases: info.cases)
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

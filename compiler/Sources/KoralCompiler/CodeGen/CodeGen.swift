import Foundation

// MARK: - C Code Generation Extensions for Qualified Names
// 
// 使用 CIdentifierUtils.swift 中的统一工具函数生成 C 标识符。
// 这确保了 CodeGen 和 DefId 系统使用一致的标识符生成逻辑。

public class CodeGen {
  internal let context: CompilerContext
  var indent: String = ""
  var buffer: String = ""
  var tempVarCounter = 0
  private var globalInitializations: [(name: String, initializer: Symbol)] = []
  private(set) var cIdentifierByDefId: [UInt64: String] = [:]
  private var cTypeNameCache: [Type: String] = [:]
  private var callableNameByDefId: [UInt64: String] = [:]
  private var callParametersByDefId: [UInt64: [Parameter]] = [:]
  private var callParametersByQualifiedName: [String: [Parameter]] = [:]
  let mirProgram: MIRProgram
  private var foreignFunctionDefIds: Set<UInt64> = []
  private var foreignGlobalVarDefIds: Set<UInt64> = []
  private var mirFunctionPlanDurationNs: UInt64 = 0
  private var mirFunctionEmitDurationNs: UInt64 = 0
  private var mirFunctionRenderCount: Int = 0
  
  // MARK: - Vtable Instance Tracking
  /// Tracks generated vtable instance names to avoid duplicate generation.
  /// Key format: `__koral_vtable_{TraitName}_for_{ConcreteType}`
  var generatedVtableInstances: Set<String> = []

  // MARK: - Drop Glue Thunk Tracking
  /// 按需物化的 drop thunk 定义，最后 splice 进 `dropThunkMarker` 处。
  private var dropThunkDefs: [(name: String, body: String)] = []
  private var dropThunkNameByTypeKey: [String: String] = [:]
  
  /// 用户定义的 main 函数的限定名（如 "hello_main"）
  /// 如果用户没有定义 main 函数，则为 nil
  private var userMainFunctionName: String? = nil
  /// 用户 main 函数的返回类型（用于决定 C main 的返回值）
  private var userMainReturnType: Type? = nil

  // Lightweight type declaration wrapper used for dependency ordering before emission
  private enum TypeDeclaration {
    case structure(Symbol, [Symbol], String)
    case `enum`(Symbol, [EnumCase], String)
    case foreignStructure(Symbol, [(name: String, type: Type)], String)

    var name: String {
      switch self {
      case .structure(_, _, let cName):
        return cName
      case .`enum`(_, _, let cName):
        return cName
      case .foreignStructure(_, _, let cName):
        return cName
      }
    }
  }

  private func declarationType(_ declaration: TypeDeclaration) -> Type? {
    switch declaration {
    case .structure(let identifier, _, _):
      return identifier.type
    case .`enum`(let identifier, _, _):
      return identifier.type
    case .foreignStructure:
      return nil
    }
  }

  private func generateTypeForwardDeclarations(_ declarations: [TypeDeclaration]) {
    for decl in declarations {
      switch decl {
      case .structure(_, _, let name):
        buffer += "struct \(name);\n"
        buffer += "struct \(name) __koral_\(name)_copy(const struct \(name) *self);\n"
        buffer += "void __koral_\(name)_drop(struct \(name)* self);\n"
      case .`enum`(_, _, let name):
        buffer += "struct \(name);\n"
        buffer += "struct \(name) __koral_\(name)_copy(const struct \(name) *self);\n"
        buffer += "void __koral_\(name)_drop(struct \(name)* self);\n"
      case .foreignStructure(_, _, let name):
        buffer += "struct \(name);\n"
      }
    }
    buffer += "\n"
  }

  private func generateManagedNominalWrapperDeclarations(_ declarations: [TypeDeclaration]) {
    for decl in declarations {
      guard let type = declarationType(decl), usesManagedNominalRepresentation(type) else {
        continue
      }
      buffer += "struct \(decl.name) {\n"
      buffer += "    void* ptr;\n"
      buffer += "};\n\n"
    }
  }

  init(
    mirProgram: MIRProgram,
    context: CompilerContext
  ) {
    self.mirProgram = mirProgram
    self.context = context
    self.foreignFunctionDefIds = Set(mirProgram.globals.compactMap { node in
      if case .foreignFunction(let identifier, _) = node {
        return identifier.defId.id
      }
      return nil
    })
    self.foreignGlobalVarDefIds = Set(mirProgram.globals.compactMap { node in
      if case .foreignGlobalVariable(let identifier, _) = node {
        return identifier.defId.id
      }
      return nil
    })
    buildCIdentifierMap()
    buildCallableIndexes()
    TypeHandlerRegistry.shared.setContext(context)
    TypeHandlerRegistry.shared.setCTypeNameResolver { [weak self] type in
      guard let self else { return nil }
      switch type {
      case .structure(let defId):
        let name = self.cIdentifierByDefId[self.defIdKey(defId)] ?? self.context.getCIdentifier(defId) ?? "T_\(defId.id)"
        return "struct \(name)"
      case .`enum`(let defId):
        let name = self.cIdentifierByDefId[self.defIdKey(defId)] ?? self.context.getCIdentifier(defId) ?? "U_\(defId.id)"
        return "struct \(name)"
      default:
        return nil
      }
    }
    TypeHandlerRegistry.shared.setDropFunctionPointerResolver { [weak self] type in
      guard let self else { return "NULL" }
      return self.dropFunctionPointer(for: type)
    }
  }

  private func phaseTimingEnabled() -> Bool {
    let env = ProcessInfo.processInfo.environment
    guard let value = env["KORAL_PROFILE_PHASES"] else {
      return false
    }
    return value == "1" || value == "true" || value == "TRUE"
  }

  private func profileCodegenPhase(_ message: String, start: DispatchTime) {
    guard phaseTimingEnabled() else {
      return
    }
    let durationMs = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    let payload = "[phase-ms] codegen: \(message) duration_ms=\(durationMs)\n"
    FileHandle.standardError.write(Data(payload.utf8))
  }

  func recordMIRFunctionPlanDuration(_ durationNs: UInt64) {
    mirFunctionPlanDurationNs += durationNs
  }

  func recordMIRFunctionEmitDuration(_ durationNs: UInt64) {
    mirFunctionEmitDurationNs += durationNs
  }

  func recordMIRFunctionRender() {
    mirFunctionRenderCount += 1
  }

  private func emitMIRFunctionTimingSummary() {
    guard phaseTimingEnabled() else {
      return
    }
    let planMs = mirFunctionPlanDurationNs / 1_000_000
    let emitMs = mirFunctionEmitDurationNs / 1_000_000
    let payload = "[phase-ms] codegen: mir-function-render count=\(mirFunctionRenderCount) plan_ms=\(planMs) emit_ms=\(emitMs)\n"
    FileHandle.standardError.write(Data(payload.utf8))
  }

  deinit {
    TypeHandlerRegistry.shared.setContext(nil)
    TypeHandlerRegistry.shared.setCTypeNameResolver(nil)
    TypeHandlerRegistry.shared.setDropFunctionPointerResolver(nil)
  }

  func defIdKey(_ defId: DefId) -> UInt64 {
    return defId.id
  }

  func qualifiedName(for symbol: Symbol) -> String {
    if foreignFunctionDefIds.contains(symbol.defId.id) {
      let name = context.getName(symbol.defId) ?? "<unknown>"
      return context.getCname(symbol.defId) ?? name
    }
    let isGlobalSymbol: Bool
    switch symbol.kind {
    case .function, .type, .module:
      isGlobalSymbol = true
    case .variable:
      let modulePath = context.getModulePath(symbol.defId) ?? []
      let sourceFile = context.getSourceFile(symbol.defId) ?? ""
      let access = context.getAccess(symbol.defId) ?? .module_private
      isGlobalSymbol = !modulePath.isEmpty || !sourceFile.isEmpty || access == .file_private
    }

    if isGlobalSymbol {
      let name = context.getName(symbol.defId) ?? "<unknown>"
      return context.getCIdentifier(symbol.defId) ?? sanitizeCIdentifier(name)
    }

    let base = sanitizeCIdentifier(context.getName(symbol.defId) ?? "<unknown>")
    return "\(base)_\(symbol.defId.id)"
  }

  func callableName(for symbol: Symbol) -> String {
    let key = defIdKey(symbol.defId)
    if let cached = callableNameByDefId[key] {
      return cached
    }
    let resolved = qualifiedName(for: symbol)
    callableNameByDefId[key] = resolved
    return resolved
  }

  func callParameters(for symbol: Symbol) -> [Parameter]? {
    if let exact = callParametersByDefId[defIdKey(symbol.defId)] {
      return exact
    }
    let targetName = callableName(for: symbol)
    return callParametersByQualifiedName[targetName]
  }

  func callParameterTypes(for symbol: Symbol) -> [Type]? {
    callParameters(for: symbol)?.map(\.type)
  }

  private func buildCIdentifierMap() {
    var publicDefIds: [DefId] = []
    var privateDefIds: [DefId] = []
    var foreignDefIds: Set<UInt64> = []

    func register(defId: DefId, access: AccessModifier) {
      if access == .file_private {
        privateDefIds.append(defId)
      } else {
        publicDefIds.append(defId)
      }
    }

    for node in mirProgram.globals {
      switch node {
      case .foreignType(let identifier):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
        foreignDefIds.insert(defIdKey(identifier.defId))
        if case .opaque(let defId) = identifier.type {
          register(defId: defId, access: context.getAccess(defId) ?? .module_private)
          foreignDefIds.insert(defIdKey(defId))
        }
      case .foreignStruct(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
        foreignDefIds.insert(defIdKey(identifier.defId))
        if case .structure(let defId) = identifier.type {
          register(defId: defId, access: context.getAccess(defId) ?? .module_private)
          foreignDefIds.insert(defIdKey(defId))
        }
      case .foreignFunction(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
        foreignDefIds.insert(defIdKey(identifier.defId))
      case .foreignGlobalVariable(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
        foreignDefIds.insert(defIdKey(identifier.defId))
      case .structDeclaration(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
        if case .structure(let defId) = identifier.type {
          let access = context.getAccess(defId) ?? .module_private
          register(defId: defId, access: access)
        }
      case .enumDeclaration(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
        if case .`enum`(let defId) = identifier.type {
          let access = context.getAccess(defId) ?? .module_private
          register(defId: defId, access: access)
        }
      case .function(let identifier, _, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
      case .globalVariable(let identifier, _, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .module_private)
      case .given(let type, _, let methods):
        switch type {
        case .structure(let defId):
          let access = context.getAccess(defId) ?? .module_private
          register(defId: defId, access: access)
        case .`enum`(let defId):
          let access = context.getAccess(defId) ?? .module_private
          register(defId: defId, access: access)
        default:
          break
        }
        for method in methods {
          register(defId: method.defId, access: context.getAccess(method.defId) ?? .module_private)
        }
      case .traitVTable, .templatePlaceholder:
        break
      }
    }

    for defId in publicDefIds {
      let cId: String
      if foreignDefIds.contains(defIdKey(defId)) {
        // For foreign types, prefer cname if set, otherwise use the Koral name
        cId = context.getCname(defId) ?? context.getName(defId) ?? "T_\(defId.id)"
      } else {
        cId = context.getCIdentifier(defId) ?? "T_\(defId.id)"
      }
      cIdentifierByDefId[defIdKey(defId)] = cId
    }
    for defId in privateDefIds {
      let cId: String
      if foreignDefIds.contains(defIdKey(defId)) {
        // For foreign types, prefer cname if set, otherwise use the Koral name
        cId = context.getCname(defId) ?? context.getName(defId) ?? "T_\(defId.id)"
      } else {
        cId = context.getCIdentifier(defId) ?? "T_\(defId.id)"
      }
      cIdentifierByDefId[defIdKey(defId)] = cId
    }
  }

  private func buildCallableIndexes() {
    func makeParameterList(_ parameters: [Symbol]) -> [Parameter] {
      parameters.map { Parameter(type: $0.type, kind: passKindForParameterType($0.type)) }
    }

    func recordCallable(_ identifier: Symbol, parameters: [Symbol]?) {
      let resolvedName = qualifiedName(for: identifier)
      callableNameByDefId[defIdKey(identifier.defId)] = resolvedName
      guard let parameters else { return }
      let parameterList = makeParameterList(parameters)
      callParametersByDefId[defIdKey(identifier.defId)] = parameterList
      if callParametersByQualifiedName[resolvedName] == nil {
        callParametersByQualifiedName[resolvedName] = parameterList
      }
    }

    for function in mirProgram.functions {
      recordCallable(function.identifier, parameters: function.parameters)
    }

    for global in mirProgram.globals {
      switch global {
      case .function(let identifier, let parameters, _):
        if callParametersByDefId[defIdKey(identifier.defId)] == nil {
          recordCallable(identifier, parameters: parameters)
        }
      case .foreignFunction(let identifier, let parameters):
        recordCallable(identifier, parameters: parameters)
      case .globalVariable(_, let initializerFunction, _):
        recordCallable(initializerFunction, parameters: [])
      default:
        continue
      }
    }
  }

  func cIdentifier(for symbol: Symbol) -> String {
    let symName = context.getName(symbol.defId) ?? ""
    if symName == "count" || symName == "fold" {
      let key = defIdKey(symbol.defId)
      let mapped = cIdentifierByDefId[key]
    }
    let isGlobalSymbol: Bool
    switch symbol.kind {
    case .function, .type, .module:
      isGlobalSymbol = true
    case .variable:
      let modulePath = context.getModulePath(symbol.defId) ?? []
      let sourceFile = context.getSourceFile(symbol.defId) ?? ""
      let access = context.getAccess(symbol.defId) ?? .module_private
      isGlobalSymbol = !modulePath.isEmpty || !sourceFile.isEmpty || access == .file_private
    }

    if case .variable = symbol.kind {
      if foreignGlobalVarDefIds.contains(defIdKey(symbol.defId)) {
        if let cName = cIdentifierByDefId[defIdKey(symbol.defId)] {
          return cName
        }
        let name = context.getName(symbol.defId) ?? "<unknown>"
        return context.getCname(symbol.defId) ?? sanitizeCIdentifier(name)
      }
      if isGlobalSymbol {
        if let cName = cIdentifierByDefId[defIdKey(symbol.defId)] {
          return cName
        }
        let name = context.getName(symbol.defId) ?? "<unknown>"
        return context.getCIdentifier(symbol.defId) ?? sanitizeCIdentifier(name)
      }
      let base = sanitizeCIdentifier(context.getName(symbol.defId) ?? "<unknown>")
      return "\(base)_\(symbol.defId.id)"
    }

    if isGlobalSymbol {
      if let cName = cIdentifierByDefId[defIdKey(symbol.defId)] {
        return cName
      }
      let name = context.getName(symbol.defId) ?? "<unknown>"
      return context.getCIdentifier(symbol.defId) ?? sanitizeCIdentifier(name)
    }
    let base = sanitizeCIdentifier(context.getName(symbol.defId) ?? "<unknown>")
    return "\(base)_\(symbol.defId.id)"
  }

  func cIdentifier(for decl: StructDecl) -> String {
    if let cName = cIdentifierByDefId[defIdKey(decl.defId)] {
      return cName
    }
    return context.getCIdentifier(decl.defId) ?? "T_\(decl.defId.id)"
  }

  func cIdentifier(for decl: EnumDecl) -> String {
    if let cName = cIdentifierByDefId[defIdKey(decl.defId)] {
      return cName
    }
    return context.getCIdentifier(decl.defId) ?? "U_\(decl.defId.id)"
  }
  
  // MARK: - Static Method Lookup
  
  /// 查找静态方法的完整限定名
  /// - Parameters:
  ///   - typeName: 类型名（如 "String", "Rune"）
  ///   - methodName: 方法名（如 "empty", "from_utf8_ptr_unchecked"）
  /// - Returns: 完整的 C 标识符
  func lookupStaticMethod(typeName: String, methodName: String) -> String {
    if let defId = mirProgram.lookupStaticMethod(typeName: typeName, methodName: methodName) {
      if let cName = cIdentifierByDefId[defIdKey(defId)] {
        return cName
      }
      return context.getCIdentifier(defId) ?? "std_\(typeName)_\(methodName)"
    }
    return "std_\(typeName)_\(methodName)"
  }
  
  func needsDrop(_ type: Type) -> Bool {
    switch type {
    case .reference, .mutableReference, .borrowedReference, .mutableBorrowedReference, .function, .weakReference, .mutableWeakReference, .traitObject:
      return true
    // 泛型实例化和非泛型名义类型一样有单态化出来的 copy/drop，
    // 漏掉它们会让「是否需要拷贝/析构」的判断静默变成 false。
    case .structure, .`enum`, .genericStruct, .genericEnum:
      return hasNontrivialNominalDrop(type)
    default:
      return false
    }
  }

  func usesManagedNominalRepresentation(_ type: Type) -> Bool {
    switch type {
    case .structure, .`enum`, .genericStruct, .genericEnum:
      return context.nominalLayoutKind(for: type) == .managed
    default:
      return false
    }
  }

  func managedPayloadTypeName(for type: Type) -> String {
    return "__koral_payload_\(nominalTypeCName(type))"
  }

  private func requiresCompleteNominalDefinition(_ type: Type) -> Bool {
    switch type {
    case .structure, .`enum`, .genericStruct, .genericEnum:
      return !usesManagedNominalRepresentation(type)
    default:
      return false
    }
  }

  public func generate() -> String {
    buffer = """
      #include <stdatomic.h>
      #include <stdint.h>
      #include "koral_runtime.h"

      """

    generateProgram()
    emitDropThunkDefinitions()
    emitMIRFunctionTimingSummary()

    return buffer
  }

  private func collectTypeDeclarations(_ nodes: [MIRGlobal]) -> [TypeDeclaration] {
    var resultByName: [String: TypeDeclaration] = [:]
    for node in nodes {
      switch node {
      case .structDeclaration(let identifier, let parameters):
        if case .structure(let defId) = identifier.type {
          let name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          let candidate: TypeDeclaration = .structure(identifier, parameters, name)
          if let existing = resultByName[name] {
            if case .structure(_, let existingParams, _) = existing,
               existingParams.count >= parameters.count {
              continue
            }
          }
          resultByName[name] = candidate
        } else {
          let name = cIdentifier(for: identifier)
          let candidate: TypeDeclaration = .structure(identifier, parameters, name)
          if let existing = resultByName[name] {
            if case .structure(_, let existingParams, _) = existing,
               existingParams.count >= parameters.count {
              continue
            }
          }
          resultByName[name] = candidate
        }
      case .enumDeclaration(let identifier, let cases):
        if case .`enum`(let defId) = identifier.type {
          let name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
          let candidate: TypeDeclaration = .`enum`(identifier, cases, name)
          if let existing = resultByName[name] {
            if case .`enum`(_, let existingCases, _) = existing,
               existingCases.count >= cases.count {
              continue
            }
          }
          resultByName[name] = candidate
        } else {
          let name = cIdentifier(for: identifier)
          let candidate: TypeDeclaration = .`enum`(identifier, cases, name)
          if let existing = resultByName[name] {
            if case .`enum`(_, let existingCases, _) = existing,
               existingCases.count >= cases.count {
              continue
            }
          }
          resultByName[name] = candidate
        }
      case .foreignStruct(let identifier, let fields):
        if case .structure(let defId) = identifier.type {
          let name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          let candidate: TypeDeclaration = .foreignStructure(identifier, fields, name)
          if let existing = resultByName[name] {
            if case .foreignStructure(_, let existingFields, _) = existing,
               existingFields.count >= fields.count {
              continue
            }
          }
          resultByName[name] = candidate
        } else {
          let name = cIdentifier(for: identifier)
          let candidate: TypeDeclaration = .foreignStructure(identifier, fields, name)
          if let existing = resultByName[name] {
            if case .foreignStructure(_, let existingFields, _) = existing,
               existingFields.count >= fields.count {
              continue
            }
          }
          resultByName[name] = candidate
        }
      default:
        continue
      }
    }
    return Array(resultByName.values).sorted { $0.name < $1.name }
  }

  private func dependencies(for declaration: TypeDeclaration, available: Set<String>) -> Set<String> {
    var deps: Set<String> = []

    func recordDirectTypeDependency(_ type: Type, selfName: String) {
      guard requiresCompleteNominalDefinition(type) else {
        return
      }
      switch type {
      case .structure(let defId):
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
      case .`enum`(let defId):
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
      case .genericStruct(let template, let tplDefId, let args):
        let typeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
      case .genericEnum(let template, let tplDefId, let args):
        let typeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
      default:
        break
      }
    }

    func recordDependency(from type: Type, selfName: String) {
      switch type {
      case .structure(let defId):
        guard requiresCompleteNominalDefinition(type) else { break }
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
      case .`enum`(let defId):
        guard requiresCompleteNominalDefinition(type) else { break }
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
      case .genericStruct(let template, let tplDefId, let args):
        guard requiresCompleteNominalDefinition(type) else { break }
        let typeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
        for arg in args {
          switch arg {
          case .structure(let defId):
            let argName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          case .`enum`(let defId):
            let argName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          case .genericStruct(let nestedTemplate, let nestedDefId, let nestedArgs):
            let argName = SemaUtils.makeLayoutName(baseName: nestedTemplate, args: nestedArgs, context: context, templateDefId: nestedDefId)
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          case .genericEnum(let nestedTemplate, let nestedDefId, let nestedArgs):
            let argName = SemaUtils.makeLayoutName(baseName: nestedTemplate, args: nestedArgs, context: context, templateDefId: nestedDefId)
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          default:
            break
          }
        }
      case .genericEnum(let template, let tplDefId, let args):
        guard requiresCompleteNominalDefinition(type) else { break }
        let typeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
        if typeName != selfName && available.contains(typeName) {
          deps.insert(typeName)
        }
        for arg in args {
          switch arg {
          case .structure(let defId):
            let argName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          case .`enum`(let defId):
            let argName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          case .genericStruct(let nestedTemplate, let nestedDefId, let nestedArgs):
            let argName = SemaUtils.makeLayoutName(baseName: nestedTemplate, args: nestedArgs, context: context, templateDefId: nestedDefId)
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          case .genericEnum(let nestedTemplate, let nestedDefId, let nestedArgs):
            let argName = SemaUtils.makeLayoutName(baseName: nestedTemplate, args: nestedArgs, context: context, templateDefId: nestedDefId)
            if argName != selfName && available.contains(argName) {
              deps.insert(argName)
            }
          default:
            break
          }
        }
      case .pointer(let inner), .mutablePointer(let inner):
        guard requiresCompleteNominalDefinition(inner) else { break }
        switch inner {
        case .structure(let defId):
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          if typeName != selfName && available.contains(typeName) {
            deps.insert(typeName)
          }
        case .`enum`(let defId):
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
          if typeName != selfName && available.contains(typeName) {
            deps.insert(typeName)
          }
        case .genericStruct(let template, let tplDefId, let args):
          let typeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
          if typeName != selfName && available.contains(typeName) {
            deps.insert(typeName)
          }
        case .genericEnum(let template, let tplDefId, let args):
          let typeName = SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
          if typeName != selfName && available.contains(typeName) {
            deps.insert(typeName)
          }
        default:
          break
        }
      case .reference, .mutableReference,
           .borrowedReference, .mutableBorrowedReference,
           .weakReference, .mutableWeakReference:
        break
      default:
        break
      }
    }

    switch declaration {
    case .structure(_, let parameters, let selfName):
      for param in parameters {
        recordDependency(from: param.type, selfName: selfName)
      }
      if let selfDefId = declarationIdentifierDefId(declaration) {
        for arg in context.getTypeArguments(selfDefId) ?? [] {
          recordDirectTypeDependency(arg, selfName: selfName)
        }
      }
    case .`enum`(_, let cases, let selfName):
      for c in cases {
        for param in c.parameters {
          recordDependency(from: param.type, selfName: selfName)
        }
      }
      if let selfDefId = declarationIdentifierDefId(declaration) {
        for arg in context.getTypeArguments(selfDefId) ?? [] {
          recordDirectTypeDependency(arg, selfName: selfName)
        }
      }
    case .foreignStructure(_, let fields, let selfName):
      for field in fields {
        recordDependency(from: field.type, selfName: selfName)
      }
    }

    return deps
  }

  private func declarationIdentifierDefId(_ declaration: TypeDeclaration) -> DefId? {
    switch declaration {
    case .structure(let identifier, _, _):
      return identifier.defId
    case .enum(let identifier, _, _):
      return identifier.defId
    case .foreignStructure(let identifier, _, _):
      return identifier.defId
    }
  }

  private func sortTypeDeclarations(_ declarations: [TypeDeclaration]) -> [TypeDeclaration] {
    let available = Set(declarations.map { $0.name })
    var dependencyMap: [String: Set<String>] = [:]
    var dependents: [String: Set<String>] = [:]
    var indegree: [String: Int] = [:]
    var originalIndex: [String: Int] = [:]

    for (index, decl) in declarations.enumerated() {
      originalIndex[decl.name] = index
      let deps = dependencies(for: decl, available: available)
      dependencyMap[decl.name] = deps
      indegree[decl.name] = deps.count
      for dep in deps {
        dependents[dep, default: []].insert(decl.name)
      }
    }

    func enqueueZeroIndegree(_ queue: inout [String], _ name: String) {
      queue.append(name)
      queue.sort { (originalIndex[$0] ?? 0) < (originalIndex[$1] ?? 0) }
    }

    var queue: [String] = []
    for decl in declarations where (indegree[decl.name] ?? 0) == 0 {
      enqueueZeroIndegree(&queue, decl.name)
    }

    var ordered: [TypeDeclaration] = []
    var emitted: Set<String> = []

    while !queue.isEmpty {
      let name = queue.removeFirst()
      guard let decl = declarations.first(where: { $0.name == name }) else { continue }
      ordered.append(decl)
      emitted.insert(name)

      for follower in dependents[name] ?? [] {
        let newDegree = (indegree[follower] ?? 0) - 1
        indegree[follower] = newDegree
        if newDegree == 0 {
          enqueueZeroIndegree(&queue, follower)
        }
      }
    }

    if ordered.count < declarations.count {
      for decl in declarations where !emitted.contains(decl.name) {
        ordered.append(decl)
      }
    }

    return ordered
  }

  private func generateProgram() {
    let totalStart = DispatchTime.now()
    let globals = mirProgram.globals
    let typeDeclStart = DispatchTime.now()
    let declarations = sortTypeDeclarations(collectTypeDeclarations(globals))
    generateTypeForwardDeclarations(declarations)
    generateManagedNominalWrapperDeclarations(declarations)
    profileCodegenPhase("type-declarations", start: typeDeclStart)

    let userMainScanStart = DispatchTime.now()
    for global in globals {
      if case .function(let identifier, _, .global) = global,
         (context.getName(identifier.defId) ?? "") == "main" {
        userMainFunctionName = cIdentifier(for: identifier)
        if case .function(_, let retType) = identifier.type {
          userMainReturnType = retType
        }
      }
    }
    profileCodegenPhase("user-main-scan", start: userMainScanStart)

    let foreignDeclStart = DispatchTime.now()
    let foreignTypes: [Symbol] = globals.compactMap {
      if case .foreignType(let identifier) = $0 { return identifier }
      return nil
    }
    let foreignFunctions: [(Symbol, [Symbol])] = globals.compactMap {
      if case .foreignFunction(let identifier, let params) = $0 {
        return (identifier, params)
      }
      return nil
    }
    let foreignGlobals: [(Symbol, Bool)] = globals.compactMap {
      if case .foreignGlobalVariable(let identifier, let mutable) = $0 {
        return (identifier, mutable)
      }
      return nil
    }

    if !foreignTypes.isEmpty {
      for typeSymbol in foreignTypes {
        generateForeignTypeDeclaration(typeSymbol)
      }
      buffer += "\n"
    }

    for decl in declarations {
      switch decl {
      case .structure(let identifier, let parameters, _):
        generateTypeDeclaration(identifier, parameters)
      case .`enum`(let identifier, let cases, _):
        generateEnumDeclaration(identifier, cases)
      case .foreignStructure(let identifier, let fields, _):
        generateForeignStructDeclaration(identifier, fields)
      }
    }

    // drop thunk 要在使用它的函数体之前定义，先占位，函数体生成完再 splice。
    buffer += Self.dropThunkMarker

    if !foreignFunctions.isEmpty {
      for (identifier, params) in foreignFunctions {
        generateForeignFunctionDeclaration(identifier, params)
      }
      buffer += "\n"
    }
    profileCodegenPhase("foreign-declarations", start: foreignDeclStart)

    let functionDeclStart = DispatchTime.now()
    for function in mirProgram.functions {
      generateFunctionDeclaration(function.identifier, function.parameters)
    }
    buffer += "\n"
    profileCodegenPhase("function-declarations", start: functionDeclStart)

    let globalVarStart = DispatchTime.now()
    if !foreignGlobals.isEmpty {
      for (identifier, mutable) in foreignGlobals {
        let cType = cTypeName(identifier.type)
        let cName = cIdentifier(for: identifier)
        if mutable {
          buffer += "extern \(cType) \(cName);\n"
        } else {
          buffer += "extern const \(cType) \(cName);\n"
        }
      }
    }
    for global in globals {
      if case .globalVariable(let identifier, let initializerFunction, _) = global {
        let cType = cTypeName(identifier.type)
        let cName = cIdentifier(for: identifier)
        buffer += "\(cType) \(cName);\n"
        globalInitializations.append((cName, initializerFunction))
      }
    }
    buffer += "\n"
    profileCodegenPhase("global-variables", start: globalVarStart)

    let vtableStart = DispatchTime.now()
    processVtableRequests()
    profileCodegenPhase("vtables", start: vtableStart)

    let functionImplStart = DispatchTime.now()
    var functionImplementations: [String] = []
    functionImplementations.reserveCapacity(mirProgram.functions.count)
    for function in mirProgram.functions {
      functionImplementations.append(
        generateMIRGlobalFunction(function.identifier, function.parameters, function)
      )
    }
    buffer += functionImplementations.joined()
    profileCodegenPhase("function-implementations", start: functionImplStart)

    let cMainStart = DispatchTime.now()
    if !globalInitializations.isEmpty || userMainFunctionName != nil {
      generateCMainFunction()
    }
    profileCodegenPhase("c-main", start: cMainStart)
    profileCodegenPhase("total", start: totalStart)
  }

  /// 生成 C 的 main 函数入口
  /// 负责初始化全局变量并调用用户定义的 main 函数
  private func generateCMainFunction() {
    buffer += "\nint main(int argc, char** argv) {\n"
    withIndent {
      addIndent()
      buffer += "__koral_set_args((int32_t)argc, (uint8_t**)argv);\n"

      // 生成全局变量初始化
      if !globalInitializations.isEmpty {
        for (name, initializer) in globalInitializations {
          let resultVar = "\(cIdentifier(for: initializer))()"
          addIndent()
          buffer += "\(name) = \(resultVar);\n"
        }
      }
      
      // 调用用户定义的 main 函数
      if let userMain = userMainFunctionName {
        let returnsIntLike: Bool
        if let ret = userMainReturnType {
          switch ret {
          case .int, .int8, .int16, .int32, .int64,
               .uint, .uint8, .uint16, .uint32, .uint64:
            returnsIntLike = true
          default:
            returnsIntLike = false
          }
        } else {
          returnsIntLike = false
        }

        addIndent()
        if returnsIntLike {
          buffer += "return (int)\(userMain)();\n"
          return
        } else {
          buffer += "\(userMain)();\n"
        }
      }
      
      addIndent()
      buffer += "return 0;\n"
    }
    buffer += "}\n"
  }

  private func generateForeignTypeDeclaration(_ identifier: Symbol) {
    let cName = context.getName(identifier.defId) ?? "<unknown>"
    buffer += "typedef struct \(cName) \(cName);\n"
  }

  private func generateForeignFunctionDeclaration(_ identifier: Symbol, _ params: [Symbol]) {
    let cName = context.getName(identifier.defId) ?? "<unknown>"
    let returnType = getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")

    if case .function(_, let ret) = identifier.type, ret == .never {
      buffer += "_Noreturn "
    }

    buffer += "extern \(returnType) \(cName)(\(paramList));\n"
  }


  private func generateFunctionDeclaration(_ identifier: Symbol, _ params: [Symbol]) {
    let cName = cIdentifier(for: identifier)
    let returnType = getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
    buffer += "\(returnType) \(cName)(\(paramList));\n"
  }

  // 生成参数的 C 声明：类型若为 reference(T) 则 getCType 返回 T*
  func getParamCDecl(_ param: Symbol) -> String {
    return "\(cTypeName(param.type)) \(cIdentifier(for: param))"
  }

  func nextTemp() -> String {
    tempVarCounter += 1
    return "_t\(tempVarCounter)"
  }

  // MARK: - Pool-Aware Temp Allocation

  /// Allocate a temp variable and emit its declaration.
  /// Allocates a fresh temp and emits `cType name;` inline.
  /// Returns the variable name.
  func nextTempWithDecl(cType: String) -> String {
    let name = nextTemp()
    addIndent()
    buffer += "\(cType) \(name);\n"
    return name
  }

  /// Allocate a temp and emit `cType name = initExpr;`.
  /// Returns the variable name.
  func nextTempWithInit(cType: String, initExpr: String) -> String {
    let name = nextTemp()
    addIndent()
    buffer += "\(cType) \(name) = \(initExpr);\n"
    return name
  }

  func arithmeticOpToC(_ op: ArithmeticOperator) -> String {
    switch op {
    case .plus: return "+"
    case .minus: return "-"
    case .multiply: return "*"
    case .divide: return "/"
    case .remainder: return "%"
    }
  }

  func comparisonOpToC(_ op: ComparisonOperator) -> String {
    switch op {
    case .equal: return "=="
    case .notEqual: return "!="
    case .greater: return ">"
    case .less: return "<"
    case .greaterEqual: return ">="
    case .lessEqual: return "<="
    }
  }

  func bitwiseOpToC(_ op: BitwiseOperator) -> String {
    switch op {
    case .and: return "&"
    case .or: return "|"
    case .xor: return "^"
    case .shiftLeft: return "<<"
    case .shiftRight: return ">>"
    }
  }

  func compoundOpToC(_ op: CompoundAssignmentOperator) -> String {
    switch op {
    case .plus: return "+="
    case .minus: return "-="
    case .multiply: return "*="
    case .divide: return "/="
    case .remainder: return "%="
    case .bitwiseAnd: return "&="
    case .bitwiseOr: return "|="
    case .bitwiseXor: return "^="
    case .shiftLeft: return "<<="
    case .shiftRight: return ">>="
    }
  }

  func checkedArithmeticFuncName(op: ArithmeticOperator, type: Type) -> String {
    let opName: String
    switch op {
    case .plus: opName = "add"
    case .minus: opName = "sub"
    case .multiply: opName = "mul"
    case .divide: opName = "div"
    case .remainder: opName = "mod"
    }
    return "koral_checked_\(opName)_\(integerRuntimeTypeSuffix(type))"
  }

  func wrappingArithmeticFuncName(op: ArithmeticOperator, type: Type) -> String {
    let opName: String
    switch op {
    case .plus: opName = "add"
    case .minus: opName = "sub"
    case .multiply: opName = "mul"
    case .divide: opName = "div"
    case .remainder: opName = "rem"
    }
    return "koral_wrapping_\(opName)_\(integerRuntimeTypeSuffix(type))"
  }

  func checkedShiftFuncName(op: BitwiseOperator, type: Type) -> String {
    let opName = op == .shiftRight ? "shr" : "shl"
    return "koral_checked_\(opName)_\(integerRuntimeTypeSuffix(type))"
  }

  func wrappingShiftFuncName(op: BitwiseOperator, type: Type) -> String {
    let opName = op == .shiftRight ? "shr" : "shl"
    return "koral_wrapping_\(opName)_\(integerRuntimeTypeSuffix(type))"
  }

  private func integerRuntimeTypeSuffix(_ type: Type) -> String {
    switch type {
    case .int: return "isize"
    case .int8: return "i8"
    case .int16: return "i16"
    case .int32: return "i32"
    case .int64: return "i64"
    case .uint: return "usize"
    case .uint8: return "u8"
    case .uint16: return "u16"
    case .uint32: return "u32"
    case .uint64: return "u64"
    default: return "isize"
    }
  }

  func cTypeName(_ type: Type) -> String {
    if case .traitObject = type {
      return "struct __koral_TraitRef"
    }

    switch type {
    case .genericParameter,
         .typeVariable,
         .module:
      fatalError("Unresolved type \(type) during codegen")
    default:
      break
    }
    if let cached = cTypeNameCache[type] {
      return cached
    }
    let resolved = TypeHandlerRegistry.shared.generateConcreteCTypeName(type)
    cTypeNameCache[type] = resolved
    return resolved
  }

  func nominalTypeCName(_ type: Type) -> String {
    switch type {
    case .structure(let defId):
      return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
    case .`enum`(let defId):
      return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
    case .genericStruct(let template, let tplDefId, let args):
      return SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
    case .genericEnum(let template, let tplDefId, let args):
      return SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
    default:
      return cTypeName(type)
    }
  }

  private func hasNontrivialNominalDrop(_ type: Type) -> Bool {
    if usesManagedNominalRepresentation(type) {
      return true
    }
    let cName = nominalTypeCName(type)
    if getUserDefinedDrop(for: cName) != nil { return true }

    // Recursively check if any field/case-payload has nontrivial drop
    switch type {
    case .structure(let defId):
      if let members = context.getStructMembers(defId) {
        for member in members where needsDrop(member.type) { return true }
      }
    case .genericStruct(let template, _, _):
      if let templateDefId = context.defIdMap.lookupGenericStructTemplateDefId(template),
         let members = context.getStructMembers(templateDefId) {
        for member in members where needsDrop(member.type) { return true }
      }
    case .`enum`(let defId):
      if let cases = context.getEnumCases(defId) {
        for c in cases {
          for param in c.parameters where needsDrop(param.type) { return true }
        }
      }
    case .genericEnum(let template, _, _):
      if let templateDefId = context.defIdMap.lookupGenericEnumTemplateDefId(template),
         let cases = context.getEnumCases(templateDefId) {
        for c in cases {
          for param in c.parameters where needsDrop(param.type) { return true }
        }
      }
    default:
      break
    }
    return false
  }

  func appendIndentedCode(_ code: String, indent: String) {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines {
      appendToBuffer("\(indent)\(line)\n")
    }
  }

  func appendCopyAssignment(for type: Type, source: String, dest: String, indent: String = "    ") {
    switch type {
    case .function:
      appendToBuffer("\(indent)\(dest) = \(source);\n")
      appendToBuffer("\(indent)__koral_closure_retain(\(dest));\n")
    case .structure(let defId):
      if context.isForeignStruct(defId) {
        appendToBuffer("\(indent)\(dest) = \(source);\n")
      } else {
        let fieldTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        appendToBuffer("\(indent)\(dest) = __koral_\(fieldTypeName)_copy(&\(source));\n")
      }
    case .`enum`(let defId):
      let fieldTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      appendToBuffer("\(indent)\(dest) = __koral_\(fieldTypeName)_copy(&\(source));\n")
    default:
      let copyCode = TypeHandlerRegistry.shared.generateCopyCode(type, source: source, dest: dest)
      if copyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        appendToBuffer("\(indent)\(dest) = \(source);\n")
      } else {
        appendIndentedCode(copyCode, indent: indent)
      }
    }
  }

  func generateStringLiteral(_ value: String, type: Type) -> String {
    let bytesVar = nextTemp() + "_bytes"
    let utf8Bytes = Array(value.utf8)
    var byteLiterals = utf8Bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
    if !byteLiterals.isEmpty {
      byteLiterals += ", "
    }
    byteLiterals += "0x00"
    addIndent()
    buffer += "static const uint8_t \(bytesVar)[] = { \(byteLiterals) };\n"

    guard case .structure(let stringDefId) = type,
          let stringMembers = context.getStructMembers(stringDefId) else {
      fatalError("String literal requires flattened String(data, len) layout")
    }
    let hasData = stringMembers.contains(where: { $0.name == "data" })
    let hasLen = stringMembers.contains(where: { $0.name == "len" })
    guard hasData, hasLen else {
      fatalError("String literal requires flattened String(data, len) layout")
    }

    let dataVar = nextTemp() + "_data"
    addIndent()
    buffer += "uint8_t* \(dataVar) = (uint8_t*)malloc(\(utf8Bytes.count + 1));\n"
    addIndent()
    buffer += "memcpy(\(dataVar), \(bytesVar), \(utf8Bytes.count + 1));\n"

    let cType = cTypeName(type)
    if usesManagedNominalRepresentation(type) {
      let resultVar = nextTemp()
      let payloadType = managedPayloadTypeName(for: type)
      addIndent()
      buffer += "\(cType) \(resultVar);\n"
      addIndent()
      buffer += "\(resultVar).ptr = __koral_payload_of(malloc(sizeof(struct __koral_Control) + sizeof(struct \(payloadType))));\n"
      addIndent()
      buffer += "__koral_control_of(\(resultVar).ptr)->strong_count = 1;\n"
      addIndent()
      buffer += "__koral_control_of(\(resultVar).ptr)->weak_count = 0;\n"
      addIndent()
      buffer += "((struct \(payloadType)*)\(resultVar).ptr)->data = \(dataVar);\n"
      addIndent()
      buffer += "((struct \(payloadType)*)\(resultVar).ptr)->len = \(utf8Bytes.count);\n"
      return resultVar
    }
    return nextTempWithInit(cType: cType, initExpr: "(\(cType)){ \(dataVar), \(utf8Bytes.count) }")
  }

  // MARK: - Unified Copy/Move Helpers
  //
  // These helpers eliminate duplicated inline copy logic across CodeGen.
  // Use these instead of manually switching on type for copy/retain patterns.

  /// Emit `dest = source` with proper copy semantics.
  /// If `isLvalue` is true, generates a deep copy (struct/enum _copy, ref retain, closure retain, weak retain).
  /// If `isLvalue` is false, generates a plain move (`dest = source`).
  func emitCopyOrMove(type: Type, source: String, dest: String, isLvalue: Bool) {
    if isLvalue && needsDrop(type) {
      addIndent()
      appendCopyAssignment(for: type, source: source, dest: dest, indent: "")
    } else {
      addIndent()
      buffer += "\(dest) = \(source);\n"
    }
  }

  /// Declare a new variable and assign with proper copy/move semantics.
  /// Emits: `Type dest;` then `dest = source` (with copy if lvalue).
  /// Returns the dest variable name.
  @discardableResult
  func emitDeclareAndCopyOrMove(type: Type, source: String, dest: String, isLvalue: Bool) -> String {
    addIndent()
    buffer += "\(cTypeName(type)) \(dest);\n"
    emitCopyOrMove(type: type, source: source, dest: dest, isLvalue: isLvalue)
    return dest
  }

  /// Declare a new temp variable and assign with proper copy/move semantics.
  /// Returns the temp variable name.
  func emitTempCopyOrMove(type: Type, source: String, isLvalue: Bool) -> String {
    let temp = nextTemp()
    return emitDeclareAndCopyOrMove(type: type, source: source, dest: temp, isLvalue: isLvalue)
  }

  /// Generate copy assignment code as a string (for use in string-based code generation like pattern bindings).
  /// Always copies (equivalent to appendCopyAssignment but returns a string).
  func generateCopyAssignmentCode(for type: Type, source: String, dest: String) -> String {
    switch type {
    case .function:
      return "\(dest) = \(source);\n__koral_closure_retain(\(dest));\n"
    case .structure(let defId):
      if context.isForeignStruct(defId) {
        return "\(dest) = \(source);\n"
      }
      let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
      return "\(dest) = __koral_\(typeName)_copy(&\(source));\n"
    case .`enum`(let defId):
      let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      return "\(dest) = __koral_\(typeName)_copy(&\(source));\n"
    case .borrowedReference, .mutableBorrowedReference:
      // 瘦借用：拷贝就是复制裸指针。
      return "\(dest) = \(source);\n"
    case .reference, .mutableReference, .traitObject:
      return "\(dest) = \(source);\n__koral_retain_value(\(dest).ptr);\n"
    case .weakReference, .mutableWeakReference:
      return "\(dest) = \(source);\n__koral_weak_retain(\(dest).control);\n"
    default:
      return "\(dest) = \(source);\n"
    }
  }

  func appendDropStatement(for type: Type, value: String, indent: String = "    ") {
    switch type {
    case .function:
      appendToBuffer("\(indent)__koral_closure_release(\(value));\n")
    case .structure(let defId):
      if context.isForeignStruct(defId) {
        return
      }
      let fieldTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
      appendToBuffer("\(indent)__koral_\(fieldTypeName)_drop(&(\(value)));\n")
    case .`enum`(let defId):
      let fieldTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      appendToBuffer("\(indent)__koral_\(fieldTypeName)_drop(&(\(value)));\n")
    case .borrowedReference, .mutableBorrowedReference:
      // 借用不拥有目标值，销毁时什么都不做。
      break
    case .reference, .mutableReference, .weakReference, .mutableWeakReference, .traitObject:
      // 引用的析构要传 drop glue，只能在 CodeGen 这边算（TypeHandler 拿不到函数名）。
      appendReleaseHandleStatement(handleType: type, value: value, indent: indent)
    default:
      let dropCode = TypeHandlerRegistry.shared.generateDropCode(type, value: value)
      appendIndentedCode(dropCode, indent: indent)
    }
  }

  // MARK: - Enum niche layout
  //
  // 两 case、其中恰好一个无参数、另一个恰好一个参数且该参数的 C 表示整段就是
  // 一个可空指针字时，枚举可以不带 tag —— 用那个指针的 NULL 位模式表示空 case。
  // 这正是 `Option[T] { None(), Some(value T) }` 的形状。

  /// niche 布局的描述：用「空位模式」而不是 tag 来区分 case。
  struct EnumNicheLayout {
    /// 无参数 case 的序号（tag 布局下的 `switch` 分支号）
    let emptyCaseIndex: Int
    /// 唯一有参数 case 的序号
    let payloadCaseIndex: Int
    /// 有参数 case 的名字（构造 payload 路径用）
    let payloadCaseName: String
    /// 该 case 的唯一字段名
    let payloadFieldName: String
    /// 该字段的类型
    let payloadFieldType: Type
  }

  /// C 表示是否整段就是一个可空指针字 —— NULL 是未使用的位模式。
  ///
  /// 不变量：**活的 owning handle 永不为 NULL**。`__koral_upgrade_ref` 失败时返回的
  /// null ref 是瞬时值，生成代码立刻转成 Option 的 None，从不作为活值流出。
  /// 将来若有「可空句柄」类型，必须先排除出 niche 名单。
  func hasNullNiche(_ type: Type) -> Bool {
    switch type {
    case .structure, .enum, .genericStruct, .genericEnum:
      // managed 名义 wrapper 是 `struct X { void* ptr; }`，单字。
      return usesManagedNominalRepresentation(type)
    case .reference, .mutableReference,
         .borrowedReference, .mutableBorrowedReference,
         .weakReference, .mutableWeakReference:
      return true
    default:
      // Int/Float 全位模式有效；Closure 是三字；TraitRef 是两字；裸指针的 NULL 合法。
      return false
    }
  }

  /// 承载 niche 的那个字段的「置空」语句。`fieldPath` 是该字段的完整 C 路径。
  func nicheNullAssignment(_ type: Type, fieldPath: String) -> String {
    switch type {
    case .weakReference, .mutableWeakReference:
      return "\(fieldPath).control = NULL;\n"
    default:
      return "\(fieldPath).ptr = NULL;\n"
    }
  }

  /// 「值为空」的 C 条件表达式。
  func nicheNullTest(_ type: Type, valueExpr: String) -> String {
    switch type {
    case .weakReference, .mutableWeakReference:
      return "(\(valueExpr).control == NULL)"
    default:
      return "(\(valueExpr).ptr == NULL)"
    }
  }

  /// 由值表达式算出 case 序号（`intptr_t`），供 `switch` 分派使用。
  func nicheTagExpression(layout: EnumNicheLayout, valueExpr: String) -> String {
    return "(\(nicheNullTest(layout.payloadFieldType, valueExpr: valueExpr)) ? \(layout.emptyCaseIndex) : \(layout.payloadCaseIndex))"
  }

  /// 按 case 列表判定 niche 布局；形状不对（或参数类型没有 niche）返回 nil。
  func enumNicheLayout(cases: [EnumCase]) -> EnumNicheLayout? {
    guard cases.count == 2 else { return nil }
    let empty = cases.enumerated().filter { $0.element.parameters.isEmpty }
    let payload = cases.enumerated().filter { !$0.element.parameters.isEmpty }
    guard empty.count == 1, payload.count == 1 else { return nil }
    let (payloadIndex, payloadCase) = payload[0]
    // Void 参数不占存储，先滤掉再数。
    let fields = payloadCase.parameters.filter { param in
      if case .void = param.type { return false }
      return true
    }
    guard fields.count == 1 else { return nil }
    let field = fields[0]
    guard hasNullNiche(field.type) else { return nil }
    return EnumNicheLayout(
      emptyCaseIndex: empty[0].offset,
      payloadCaseIndex: payloadIndex,
      payloadCaseName: payloadCase.name,
      payloadFieldName: field.name,
      payloadFieldType: field.type
    )
  }

  /// 从类型出发判定 niche 布局（泛型实例化会先解析到模板的 case 列表）。
  func enumNicheLayout(for type: Type) -> EnumNicheLayout? {
    guard let cases = enumCases(of: type) else { return nil }
    return enumNicheLayout(cases: cases)
  }

  private func enumCases(of type: Type) -> [EnumCase]? {
    switch type {
    case .enum(let defId):
      return context.getEnumCases(defId)
    case .genericEnum(let template, _, _):
      guard let templateDefId = context.defIdMap.lookupGenericEnumTemplateDefId(template) else { return nil }
      return context.getEnumCases(templateDefId)
    default:
      return nil
    }
  }

  // MARK: - Drop glue as a function pointer
  //
  // 头里不存析构函数之后，`__koral_release_value` 的第二个参数必须在**释放调用点**
  // 就绪。绝大多数类型已有同构的 `__koral_*_drop(void*)`，直接取函数名即可；
  // 剩下的（典型是 `Ref[Y]`，其 drop 依赖内层类型）按需物化一个 thunk。

  private static let dropThunkMarker = "/* __koral_drop_thunks__ */\n"

  /// 「原地销毁一个 `type` 类型 C 值」的 `__koral_Dtor` 表达式。
  /// 没有 drop glue 的类型返回 `NULL`。
  ///
  /// 注意：`.traitObject` 的销毁是**动态**的（具体类型的 glue 在 vtable 里），
  /// 不要对 trait object 句柄用本函数 —— 用 `appendReleaseHandleStatement`。
  func dropFunctionPointer(for type: Type) -> String {
    guard needsDrop(type) else { return "NULL" }
    switch type {
    case .structure(let defId), .enum(let defId):
      let name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
      return "(__koral_Dtor)__koral_\(name)_drop"
    case .genericStruct, .genericEnum:
      // 泛型实例化同样有单态化出的 __koral_<layout>_drop，直接复用，不必物化 thunk。
      return "(__koral_Dtor)__koral_\(nominalTypeCName(type))_drop"
    case .function:
      return "(__koral_Dtor)__koral_closure_drop"
    case .weakReference, .mutableWeakReference:
      return "(__koral_Dtor)__koral_weakref_drop"
    case .traitObject:
      return "(__koral_Dtor)__koral_traitref_drop"
    case .borrowedReference, .mutableBorrowedReference:
      // 借用不拥有目标值，销毁时什么都不做。
      return "NULL"
    default:
      return "(__koral_Dtor)\(materializeDropThunk(for: type))"
    }
  }

  /// 为没有现成 `void (*)(void*)` glue 的类型物化一个 thunk，并返回函数名。
  private func materializeDropThunk(for type: Type) -> String {
    let key = type.cTypeName
    if let existing = dropThunkNameByTypeKey[key] { return existing }
    let name = "__koral_drop_thunk_\(dropThunkDefs.count)"
    dropThunkNameByTypeKey[key] = name

    let savedBuffer = buffer
    let savedIndent = indent
    buffer = ""
    indent = "    "
    appendToBuffer("\(key) __koral_thunk_self = *(\(key)*)raw_value;\n")
    appendDropStatement(for: type, value: "__koral_thunk_self", indent: "    ")
    let body = buffer
    buffer = savedBuffer
    indent = savedIndent

    dropThunkDefs.append((
      name: name,
      body: "static void \(name)(void* raw_value) {\n\(body)}}\n"
    ))
    return name
  }

  /// 释放一个**句柄**。`value` 的静态类型是引用或 managed nominal wrapper。
  ///
  /// - owning reference：`value.ptr` 指向一个 C 值，dtor 是该值的原地 drop glue。
  /// - trait object reference：dtor 是**动态**的（具体类型的 glue 在 `value.vtable` 里）。
  /// - weak reference：只减 weak 计数，不碰 payload（可能已死）。
  /// - 借用：不拥有，什么都不做。
  func appendReleaseHandleStatement(handleType: Type, value: String, indent: String = "    ") {
    switch handleType {
    case .borrowedReference, .mutableBorrowedReference:
      break
    case .weakReference, .mutableWeakReference:
      appendToBuffer("\(indent)__koral_weak_release((\(value)).control);\n")
    case .reference(let inner), .mutableReference(let inner):
      if case .traitObject = inner {
        appendToBuffer(
          "\(indent)__koral_release_value((\(value)).ptr, ((const struct __koral_VTableHeader*)(\(value)).vtable)->destroy);\n"
        )
      } else {
        appendToBuffer("\(indent)__koral_release_value((\(value)).ptr, \(dropFunctionPointer(for: inner)));\n")
      }
    case .traitObject:
      appendToBuffer(
        "\(indent)__koral_release_value((\(value)).ptr, ((const struct __koral_VTableHeader*)(\(value)).vtable)->destroy);\n"
      )
    default:
      fatalError("appendReleaseHandleStatement called with non-reference type: \(handleType)")
    }
  }

  /// 在类型声明之后、函数体之前插入 thunk 定义。
  func emitDropThunkDefinitions() {
    guard !dropThunkDefs.isEmpty else { return }
    var thunkCode = ""
    for thunk in dropThunkDefs {
      thunkCode += thunk.body + "\n"
    }
    buffer = buffer.replacingOccurrences(of: Self.dropThunkMarker, with: thunkCode)
  }

  func emitPointerReadCopy(pointerExpr: String, elementType: Type) -> String {
    let cType = cTypeName(elementType)
    let result = nextTempWithDecl(cType: cType)
    // Always deep copy from pointer (reading from memory always produces an owned value)
    appendCopyAssignment(for: elementType, source: "*(\(cType)*)\(pointerExpr)", dest: result, indent: indent)
    return result
  }

  func isFloatType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64: return true
    default: return false
    }
  }

  func getFunctionReturnType(_ type: Type) -> String {
    switch type {
    case .function(_, let returns):
      return cTypeName(returns)
    default:
      fatalError("Expected function type")
    }
  }
  
  /// 获取函数类型的返回类型（作为 Type）
  func getFunctionReturnTypeAsType(_ type: Type) -> Type? {
    switch type {
    case .function(_, let returns):
      return returns
    default:
      return nil
    }
  }
  
  /// 检查类型是否是引用类型
  func isReferenceType(_ type: Type) -> Bool {
    switch type {
    case .reference, .mutableReference, .borrowedReference, .mutableBorrowedReference:
      return true
    default:
      return false
    }
  }

  func addIndent() {
    buffer += indent
  }

  func withIndent(_ body: () -> Void) {
    let oldIndent = indent
    indent += "    "
    body()
    indent = oldIndent
  }
  
  /// Append text to the buffer (used by extensions)
  func appendToBuffer(_ text: String) {
    buffer += text
  }
  
  /// Get user defined drop function for a type
  func getUserDefinedDrop(for typeName: String) -> String? {
    func isStdDropTraitConformance(_ trait: TypedTraitConformance?) -> Bool {
      guard let trait, trait.traitName == "Drop" else { return false }
      guard let traitInfo = mirProgram.traits[trait.traitName] else { return false }
      return traitInfo.modulePath == ["Std"]
    }

    func isStdDropTraitDefId(_ traitDefId: DefId?) -> Bool {
      guard let traitDefId else { return false }
      guard let traitName = context.getName(traitDefId), traitName == "Drop" else { return false }
      guard let traitInfo = mirProgram.traits[traitName] else { return false }
      return traitInfo.defId == traitDefId && traitInfo.modulePath == ["Std"]
    }

    func dropOwnerTypeName(_ type: Type) -> String? {
      switch type {
      case .structure(let defId):
        return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
      case .`enum`(let defId):
        return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      case .genericStruct(let template, let tplDefId, let args), .genericEnum(let template, let tplDefId, let args):
        return SemaUtils.makeLayoutName(baseName: template, args: args, context: context, templateDefId: tplDefId)
      default:
        return nil
      }
    }

    for node in mirProgram.globals {
      if case .given(let type, let trait, let methods) = node,
         isStdDropTraitConformance(trait),
         dropOwnerTypeName(type) == typeName {
        for method in methods {
          let logicalName = mirProgram.receiverMethodDispatch[method.defId]?.methodName
            ?? context.getName(method.defId)
          if logicalName == "drop" {
            return cIdentifier(for: method)
          }
        }
      }

      if case .function(let identifier, _, _) = node,
         let dispatch = mirProgram.receiverMethodDispatch[identifier.defId],
         dispatch.methodName == "drop",
        isStdDropTraitDefId(dispatch.conformanceTraitDefId),
         case .concreteType(let ownerTypeName) = dispatch.owner {
        let access = context.getAccess(identifier.defId) ?? .module_private
        let sourceFile = context.getSourceFile(identifier.defId)
        let ownerDefId = context.lookupDefId(
          modulePath: [],
          name: ownerTypeName,
          sourceFile: access == .file_private ? sourceFile : nil
        )
        let cTypeName = ownerDefId.flatMap { defId in
          cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId)
        } ?? sanitizeCIdentifier(ownerTypeName)
        if cTypeName == typeName {
          return cIdentifier(for: identifier)
        }
      }
    }

    return nil
  }

}

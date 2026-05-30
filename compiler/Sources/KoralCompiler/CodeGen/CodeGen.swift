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
  let mirProgram: MIRProgram
  private var foreignFunctionDefIds: Set<UInt64> = []
  private var foreignGlobalVarDefIds: Set<UInt64> = []
  
  // MARK: - Vtable Instance Tracking
  /// Tracks generated vtable instance names to avoid duplicate generation.
  /// Key format: `__koral_vtable_{TraitName}_for_{ConcreteType}`
  var generatedVtableInstances: Set<String> = []
  
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
  }

  deinit {
    TypeHandlerRegistry.shared.setContext(nil)
    TypeHandlerRegistry.shared.setCTypeNameResolver(nil)
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
      let access = context.getAccess(symbol.defId) ?? .protected
      isGlobalSymbol = !modulePath.isEmpty || !sourceFile.isEmpty || access == .private
    }

    if isGlobalSymbol {
      let name = context.getName(symbol.defId) ?? "<unknown>"
      return context.getCIdentifier(symbol.defId) ?? sanitizeCIdentifier(name)
    }

    let base = sanitizeCIdentifier(context.getName(symbol.defId) ?? "<unknown>")
    return "\(base)_\(symbol.defId.id)"
  }

  private func buildCIdentifierMap() {
    var publicDefIds: [DefId] = []
    var privateDefIds: [DefId] = []
    var foreignDefIds: Set<UInt64> = []

    func register(defId: DefId, access: AccessModifier) {
      if access == .private {
        privateDefIds.append(defId)
      } else {
        publicDefIds.append(defId)
      }
    }

    for node in mirProgram.globals {
      switch node {
      case .foreignType(let identifier):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
        foreignDefIds.insert(defIdKey(identifier.defId))
        if case .opaque(let defId) = identifier.type {
          register(defId: defId, access: context.getAccess(defId) ?? .protected)
          foreignDefIds.insert(defIdKey(defId))
        }
      case .foreignStruct(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
        foreignDefIds.insert(defIdKey(identifier.defId))
        if case .structure(let defId) = identifier.type {
          register(defId: defId, access: context.getAccess(defId) ?? .protected)
          foreignDefIds.insert(defIdKey(defId))
        }
      case .foreignFunction(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
        foreignDefIds.insert(defIdKey(identifier.defId))
      case .foreignGlobalVariable(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
        foreignDefIds.insert(defIdKey(identifier.defId))
      case .structDeclaration(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
        if case .structure(let defId) = identifier.type {
          let access = context.getAccess(defId) ?? .protected
          register(defId: defId, access: access)
        }
      case .enumDeclaration(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
        if case .`enum`(let defId) = identifier.type {
          let access = context.getAccess(defId) ?? .protected
          register(defId: defId, access: access)
        }
      case .function(let identifier, _, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
      case .globalVariable(let identifier, _, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .protected)
      case .given(let type, _, let methods):
        switch type {
        case .structure(let defId):
          let access = context.getAccess(defId) ?? .protected
          register(defId: defId, access: access)
        case .`enum`(let defId):
          let access = context.getAccess(defId) ?? .protected
          register(defId: defId, access: access)
        default:
          break
        }
        for method in methods {
          register(defId: method.defId, access: context.getAccess(method.defId) ?? .protected)
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

  func cIdentifier(for symbol: Symbol) -> String {
    let isGlobalSymbol: Bool
    switch symbol.kind {
    case .function, .type, .module:
      isGlobalSymbol = true
    case .variable:
      let modulePath = context.getModulePath(symbol.defId) ?? []
      let sourceFile = context.getSourceFile(symbol.defId) ?? ""
      let access = context.getAccess(symbol.defId) ?? .protected
      isGlobalSymbol = !modulePath.isEmpty || !sourceFile.isEmpty || access == .private
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
    case .structure, .`enum`, .reference, .mutableReference, .function, .weakReference, .mutableWeakReference, .traitObject:
      return true
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

    func recordDependency(from type: Type, selfName: String) {
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
      default:
        break
      }
    }

    switch declaration {
    case .structure(_, let parameters, let selfName):
      for param in parameters {
        recordDependency(from: param.type, selfName: selfName)
      }
    case .`enum`(_, let cases, let selfName):
      for c in cases {
        for param in c.parameters {
          recordDependency(from: param.type, selfName: selfName)
        }
      }
    case .foreignStructure(_, let fields, let selfName):
      for field in fields {
        recordDependency(from: field.type, selfName: selfName)
      }
    }

    return deps
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
    let globals = mirProgram.globals

    for global in globals {
      if case .function(let identifier, _, .global) = global,
         (context.getName(identifier.defId) ?? "") == "main" {
        userMainFunctionName = cIdentifier(for: identifier)
        if case .function(_, let retType) = identifier.type {
          userMainReturnType = retType
        }
      }
    }

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

    for decl in sortTypeDeclarations(collectTypeDeclarations(globals)) {
      switch decl {
      case .structure(let identifier, let parameters, _):
        generateTypeDeclaration(identifier, parameters)
      case .`enum`(let identifier, let cases, _):
        generateEnumDeclaration(identifier, cases)
      case .foreignStructure(let identifier, let fields, _):
        generateForeignStructDeclaration(identifier, fields)
      }
    }

    if !foreignFunctions.isEmpty {
      for (identifier, params) in foreignFunctions {
        generateForeignFunctionDeclaration(identifier, params)
      }
      buffer += "\n"
    }

    for function in mirProgram.functions {
      generateFunctionDeclaration(function.identifier, function.parameters)
    }
    buffer += "\n"

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

    processVtableRequests()

    for function in mirProgram.functions {
      generateMIRGlobalFunction(function.identifier, function.parameters, function)
    }

    if !globalInitializations.isEmpty || userMainFunctionName != nil {
      generateCMainFunction()
    }
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
         .genericStruct,
         .genericEnum,
         .typeVariable,
         .module:
      fatalError("Unresolved type \(type) during codegen")
    default:
      break
    }
    return TypeHandlerRegistry.shared.generateConcreteCTypeName(type)
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
    let storageVar = nextTemp() + "_storage"
    let utf8Bytes = Array(value.utf8)
    var byteLiterals = utf8Bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
    if !byteLiterals.isEmpty {
      byteLiterals += ", "
    }
    byteLiterals += "0x00"
    addIndent()
    buffer += "static const uint8_t \(bytesVar)[] = { \(byteLiterals) };\n"

    guard case .structure(let stringDefId) = type,
          let stringMembers = context.getStructMembers(stringDefId),
          let storageMember = stringMembers.first(where: { $0.name == "storage" }) else {
      fatalError("String literal requires String.storage: ref StringStorage")
    }
    let storageType: Type
    switch storageMember.type {
    case .reference(let resolvedStorageType), .mutableReference(let resolvedStorageType):
      storageType = resolvedStorageType
    default:
      fatalError("String literal requires String.storage: ref StringStorage")
    }
    let storageCType = cTypeName(storageType)
    addIndent()
    buffer += "static const \(storageCType) \(storageVar) = { (uint8_t*)\(bytesVar), \(utf8Bytes.count), \(utf8Bytes.count + 1) };\n"

    let cType = cTypeName(type)
    return nextTempWithInit(cType: cType, initExpr: "(\(cType)){ (struct __koral_Ref){ (void*)&\(storageVar), NULL } }")
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
    case .reference, .mutableReference:
      return "\(dest) = \(source);\n__koral_retain(\(dest).control);\n"
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
    default:
      let dropCode = TypeHandlerRegistry.shared.generateDropCode(type, value: value)
      appendIndentedCode(dropCode, indent: indent)
    }
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
    case .reference, .mutableReference:
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

    func isStdDropTraitName(_ traitName: String?) -> Bool {
      guard let traitName, traitName == "Drop" else { return false }
      guard let traitInfo = mirProgram.traits[traitName] else { return false }
      return traitInfo.modulePath == ["Std"]
    }

    func dropOwnerTypeName(_ type: Type) -> String? {
      switch type {
      case .structure(let defId):
        return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
      case .`enum`(let defId):
        return cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      case .genericStruct(let template, let args), .genericEnum(let template, let args):
        return SemaUtils.makeLayoutName(baseName: template, args: args, context: context)
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
         isStdDropTraitName(dispatch.conformanceTraitName),
         case .concreteType(let ownerTypeName) = dispatch.owner {
        let access = context.getAccess(identifier.defId) ?? .protected
        let sourceFile = context.getSourceFile(identifier.defId)
        let ownerDefId = context.lookupDefId(
          modulePath: [],
          name: ownerTypeName,
          sourceFile: access == .private ? sourceFile : nil
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

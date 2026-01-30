import Foundation

// MARK: - C Code Generation Extensions for Qualified Names
// 
// 使用 CIdentifierUtils.swift 中的统一工具函数生成 C 标识符。
// 这确保了 CodeGen 和 DefId 系统使用一致的标识符生成逻辑。

public class CodeGen {
  private let ast: MonomorphizedProgram
  internal let context: CompilerContext
  var indent: String = ""
  var buffer: String = ""
  var tempVarCounter = 0
  private var globalInitializations: [(String, TypedExpressionNode)] = []
  var lifetimeScopeStack: [[(name: String, type: Type)]] = []
  var userDefinedDrops: [String: String] = [:] // TypeName -> Mangled Drop Function Name
  private(set) var cIdentifierByDefId: [UInt64: String] = [:]
  
  /// 用户定义的 main 函数的限定名（如 "hello_main"）
  /// 如果用户没有定义 main 函数，则为 nil
  private var userMainFunctionName: String? = nil

  // MARK: - Lambda Code Generation
  /// Counter for generating unique Lambda function names
  var lambdaCounter = 0
  /// Buffer for Lambda function definitions (generated at the end)
  var lambdaFunctions: String = ""
  /// Buffer for Lambda environment struct definitions
  var lambdaEnvStructs: String = ""
  
  // MARK: - Escape Analysis
  /// 逃逸分析上下文，用于追踪变量作用域和逃逸状态
  var escapeContext: EscapeContext
  
  /// 是否启用逃逸分析报告
  private let escapeAnalysisReportEnabled: Bool

  // Lightweight type declaration wrapper used for dependency ordering before emission
  private enum TypeDeclaration {
    case structure(Symbol, [Symbol], String)
    case union(Symbol, [UnionCase], String)
    case foreignStructure(Symbol, [(name: String, type: Type)], String)

    var name: String {
      switch self {
      case .structure(_, _, let cName):
        return cName
      case .union(_, _, let cName):
        return cName
      case .foreignStructure(_, _, let cName):
        return cName
      }
    }
  }

  struct LoopContext {
    let startLabel: String
    let endLabel: String
    let scopeIndex: Int
  }
  var loopStack: [LoopContext] = []

  public init(
    ast: MonomorphizedProgram,
    context: CompilerContext,
    escapeAnalysisReportEnabled: Bool = false
  ) {
    self.ast = ast
    self.context = context
    self.escapeAnalysisReportEnabled = escapeAnalysisReportEnabled
    self.escapeContext = EscapeContext(reportingEnabled: escapeAnalysisReportEnabled, context: context)
    buildCIdentifierMap()
    TypeHandlerRegistry.shared.setContext(context)
    TypeHandlerRegistry.shared.setCTypeNameResolver { [weak self] type in
      guard let self else { return nil }
      switch type {
      case .structure(let defId):
        let name = self.cIdentifierByDefId[self.defIdKey(defId)] ?? self.context.getCIdentifier(defId) ?? "T_\(defId.id)"
        return "struct \(name)"
      case .union(let defId):
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
    let isGlobalSymbol: Bool
    switch symbol.kind {
    case .function, .type, .module:
      isGlobalSymbol = true
    case .variable:
      let modulePath = context.getModulePath(symbol.defId) ?? []
      let sourceFile = context.getSourceFile(symbol.defId) ?? ""
      let access = context.getAccess(symbol.defId) ?? .default
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

    for node in ast.globalNodes {
      switch node {
      case .foreignType(let identifier):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
        foreignDefIds.insert(defIdKey(identifier.defId))
        if case .opaque(let defId) = identifier.type {
          register(defId: defId, access: context.getAccess(defId) ?? .default)
          foreignDefIds.insert(defIdKey(defId))
        }
      case .foreignStruct(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
        foreignDefIds.insert(defIdKey(identifier.defId))
        if case .structure(let defId) = identifier.type {
          register(defId: defId, access: context.getAccess(defId) ?? .default)
          foreignDefIds.insert(defIdKey(defId))
        }
      case .foreignFunction(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
        foreignDefIds.insert(defIdKey(identifier.defId))
      case .foreignGlobalVariable(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
        foreignDefIds.insert(defIdKey(identifier.defId))
      case .foreignUsing:
        break
      case .globalStructDeclaration(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
        if case .structure(let defId) = identifier.type {
          let access = context.getAccess(defId) ?? .default
          register(defId: defId, access: access)
        }
      case .globalUnionDeclaration(let identifier, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
        if case .union(let defId) = identifier.type {
          let access = context.getAccess(defId) ?? .default
          register(defId: defId, access: access)
        }
      case .globalFunction(let identifier, _, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
      case .globalVariable(let identifier, _, _):
        register(defId: identifier.defId, access: context.getAccess(identifier.defId) ?? .default)
      case .givenDeclaration(let type, let methods):
        switch type {
        case .structure(let defId):
          let access = context.getAccess(defId) ?? .default
          register(defId: defId, access: access)
        case .union(let defId):
          let access = context.getAccess(defId) ?? .default
          register(defId: defId, access: access)
        default:
          break
        }
        for method in methods {
          register(defId: method.identifier.defId, access: context.getAccess(method.identifier.defId) ?? .default)
        }
      case .genericTypeTemplate, .genericFunctionTemplate:
        break
      }
    }

    for defId in publicDefIds {
      let cId: String
      if foreignDefIds.contains(defIdKey(defId)) {
        cId = context.getName(defId) ?? "T_\(defId.id)"
      } else {
        cId = context.getCIdentifier(defId) ?? "T_\(defId.id)"
      }
      cIdentifierByDefId[defIdKey(defId)] = cId
    }
    for defId in privateDefIds {
      let cId: String
      if foreignDefIds.contains(defIdKey(defId)) {
        cId = context.getName(defId) ?? "T_\(defId.id)"
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
      let access = context.getAccess(symbol.defId) ?? .default
      isGlobalSymbol = !modulePath.isEmpty || !sourceFile.isEmpty || access == .private
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

  func cIdentifier(for decl: UnionDecl) -> String {
    if let cName = cIdentifierByDefId[defIdKey(decl.defId)] {
      return cName
    }
    return context.getCIdentifier(decl.defId) ?? "U_\(decl.defId.id)"
  }
  
  // MARK: - Static Method Lookup
  
  /// 查找静态方法的完整限定名
  /// - Parameters:
  ///   - typeName: 类型名（如 "String", "Rune"）
  ///   - methodName: 方法名（如 "empty", "from_bytes_unchecked"）
  /// - Returns: 完整的 C 标识符
  func lookupStaticMethod(typeName: String, methodName: String) -> String {
    if let defId = ast.lookupStaticMethod(typeName: typeName, methodName: methodName) {
      if let cName = cIdentifierByDefId[defIdKey(defId)] {
        return cName
      }
      return context.getCIdentifier(defId) ?? "std_\(typeName)_\(methodName)"
    }
    return "std_\(typeName)_\(methodName)"
  }
  
  func pushScope() {
    lifetimeScopeStack.append([])
    escapeContext.enterScope()
  }

  func popScopeWithoutCleanup() {
    _ = lifetimeScopeStack.popLast()
    escapeContext.leaveScope()
  }

  func popScope() {
    let vars = lifetimeScopeStack.removeLast()
    for (name, type) in vars.reversed() {
      addIndent()
      appendDropStatement(for: type, value: name, indent: "")
    }
    escapeContext.leaveScope()
  }

  func emitCleanup(fromScopeIndex startIndex: Int) {
    guard !lifetimeScopeStack.isEmpty else { return }
    let clampedStart = max(0, min(startIndex, lifetimeScopeStack.count - 1))

    for scopeIndex in stride(from: lifetimeScopeStack.count - 1, through: clampedStart, by: -1) {
      let vars = lifetimeScopeStack[scopeIndex]
      for (name, type) in vars.reversed() {
        addIndent()
        appendDropStatement(for: type, value: name, indent: "")
      }
    }
  }

  func emitCleanupForScope(at scopeIndex: Int) {
    guard scopeIndex >= 0 && scopeIndex < lifetimeScopeStack.count else { return }
    let vars = lifetimeScopeStack[scopeIndex]
    for (name, type) in vars.reversed() {
      addIndent()
      appendDropStatement(for: type, value: name, indent: "")
    }
  }

  func registerVariable(_ name: String, _ type: Type) {
    lifetimeScopeStack[lifetimeScopeStack.count - 1].append((name: name, type: type))
    escapeContext.registerVariable(name)
  }


  public func generate() -> String {
    buffer = """
      #include <stdio.h>
      #include <stdlib.h>
      #include <stdatomic.h>
      #include <string.h>
      #include <stdint.h>
      #include <math.h>

      """

    emitForeignUsingDeclarations(from: ast.globalNodes)

    buffer += """
      // Generic Ref type
      struct Ref { void* ptr; void* control; };

      // Unified Closure type for all function types (16 bytes)
      // fn: function pointer (with env as first param if env != NULL)
      // env: environment pointer (NULL for no-capture lambdas)
      struct __koral_Closure { void* fn; void* env; };

      typedef void (*Koral_Dtor)(void*);

      struct Koral_Control {
        _Atomic int count;
        Koral_Dtor dtor;
        void* ptr;
      };

      void __koral_retain(void* raw_control) {
        if (!raw_control) return;
        struct Koral_Control* control = (struct Koral_Control*)raw_control;
        atomic_fetch_add(&control->count, 1);
      }

      void __koral_release(void* raw_control) {
        if (!raw_control) return;
        struct Koral_Control* control = (struct Koral_Control*)raw_control;
        int prev = atomic_fetch_sub(&control->count, 1);
        if (prev == 1) {
          if (control->dtor) {
            control->dtor(control->ptr);
          }
          free(control->ptr);
          free(control);
        }
      }

      """

    // 生成程序体
    generateProgram(ast)
    
    // Insert Lambda env structs after the runtime definitions
    if !lambdaEnvStructs.isEmpty {
      // Find the position after the runtime definitions (after __koral_release)
      if let insertPos = buffer.range(of: "void __koral_release(void* raw_control)") {
        // Find the end of __koral_release function
        if let funcEnd = buffer.range(of: "}\n\n", range: insertPos.upperBound..<buffer.endIndex) {
          let insertIndex = funcEnd.upperBound
          buffer.insert(contentsOf: lambdaEnvStructs, at: insertIndex)
        }
      }
    }
    
    return buffer
  }

  private func emitForeignUsingDeclarations(from nodes: [TypedGlobalNode]) {
    var seen: Set<String> = []
    var ordered: [String] = []

    for node in nodes {
      if case .foreignUsing(let libraryName) = node {
        if !seen.contains(libraryName) {
          seen.insert(libraryName)
          ordered.append(libraryName)
        }
      }
    }

    guard !ordered.isEmpty else { return }

    for header in ordered {
      generateForeignUsingDeclaration(header)
    }
    buffer += "\n"
  }
  
  /// 获取逃逸分析诊断报告
  /// 
  /// 返回所有在代码生成过程中收集的逃逸分析诊断信息。
  /// 只有在启用逃逸分析报告时才会有内容。
  public func getEscapeAnalysisDiagnostics() -> String {
    return escapeContext.getFormattedDiagnostics()
  }
  
  /// 获取逃逸分析诊断列表
  public func getEscapeDiagnostics() -> [EscapeDiagnostic] {
    return escapeContext.diagnostics
  }

  private func collectTypeDeclarations(_ nodes: [TypedGlobalNode]) -> [TypeDeclaration] {
    var resultByName: [String: TypeDeclaration] = [:]
    for node in nodes {
      switch node {
      case .globalStructDeclaration(let identifier, let parameters):
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
      case .globalUnionDeclaration(let identifier, let cases):
        if case .union(let defId) = identifier.type {
          let name = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
          let candidate: TypeDeclaration = .union(identifier, cases, name)
          if let existing = resultByName[name] {
            if case .union(_, let existingCases, _) = existing,
               existingCases.count >= cases.count {
              continue
            }
          }
          resultByName[name] = candidate
        } else {
          let name = cIdentifier(for: identifier)
          let candidate: TypeDeclaration = .union(identifier, cases, name)
          if let existing = resultByName[name] {
            if case .union(_, let existingCases, _) = existing,
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
    return Array(resultByName.values)
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
      case .union(let defId):
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
    case .union(_, let cases, let selfName):
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

  private func generateProgram(_ program: MonomorphizedProgram) {
    let nodes = program.globalNodes
    
      // Pass -1: Validate all types are resolved (no generic parameters or parameterized types)
      #if DEBUG
      for node in nodes {
        validateGlobalNode(node)
      }
      #endif
    
      // Pass 0: Scan for user-defined drops and main function
      for node in nodes {
        if case .givenDeclaration(let type, let methods) = node {
             var typeName: String?
             if case .structure(let defId) = type {
               typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
             }
             if case .union(let defId) = type {
               typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
             }

             if let name = typeName {
                 for method in methods {
                     if method.identifier.methodKind == .drop {
                         userDefinedDrops[name] = cIdentifier(for: method.identifier)
                     }
                 }
             }
        }
        if case .globalFunction(let identifier, _, _) = node {
          if identifier.methodKind == .drop {
            // Mangled name is TypeName___drop, so we can extract TypeName
            // Note: This relies on the mangling scheme in TypeChecker
            let identifierName = context.getName(identifier.defId) ?? "<unknown>"
            let baseName = String(identifierName.dropLast(7))
            let parts = baseName.split(separator: ".").map(String.init)
            let typeName = parts.last ?? baseName
            let modulePath = parts.dropLast().map { $0 }
            let access = context.getAccess(identifier.defId) ?? .default
            let sourceFile = context.getSourceFile(identifier.defId)
            let typeDefId = context.lookupDefId(
              modulePath: modulePath,
              name: typeName,
              sourceFile: access == .private ? sourceFile : nil
            )
            let cTypeName = typeDefId.flatMap { defId in
              cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId)
            } ?? sanitizeCIdentifier(baseName)
            userDefinedDrops[cTypeName] = cIdentifier(for: identifier)
          }
          // 检测用户定义的 main 函数
          if (context.getName(identifier.defId) ?? "") == "main" {
            userMainFunctionName = cIdentifier(for: identifier)
          }
        }
      }

      let foreignTypes: [Symbol] = nodes.compactMap {
        if case .foreignType(let identifier) = $0 { return identifier }
        return nil
      }
      let foreignFunctions: [(Symbol, [Symbol])] = nodes.compactMap {
        if case .foreignFunction(let identifier, let params) = $0 {
          return (identifier, params)
        }
        return nil
      }
      let foreignGlobals: [(Symbol, Bool)] = nodes.compactMap {
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

      // 先生成所有类型声明，按依赖顺序排序以确保字段类型已定义
      let typeDeclarations = collectTypeDeclarations(nodes)
      
      for decl in sortTypeDeclarations(typeDeclarations) {
        switch decl {
        case .structure(let identifier, let parameters, _):
          generateTypeDeclaration(identifier, parameters)
        case .union(let identifier, let cases, _):
          generateUnionDeclaration(identifier, cases)
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

      // 然后生成所有函数声明
      for node in nodes {
        if case .globalFunction(let identifier, let params, _) = node {
          generateFunctionDeclaration(identifier, params)
        }
        if case .givenDeclaration(let type, let methods) = node {
          if context.containsGenericParameter(type) { continue }
          for method in methods {
            generateFunctionDeclaration(method.identifier, method.parameters)
          }
        }
      }
      buffer += "\n"

      // 生成全局变量声明
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
      for node in nodes {
        if case .globalVariable(let identifier, let value, _) = node {
          let cType = cTypeName(identifier.type)
          let cName = cIdentifier(for: identifier)
          switch value {
          case .integerLiteral(_, _), .floatLiteral(_, _),
            .stringLiteral(_, _), .booleanLiteral(_, _):
            buffer += "\(cType) \(cName) = "
            buffer += generateExpressionSSA(value)
            buffer += ";\n"
          default:
            // 复杂表达式延迟到 main 函数中初始化
            buffer += "\(cType) \(cName);\n"
            globalInitializations.append((cName, value))
          }
        }
      }
      buffer += "\n"

      // 生成函数实现
      for node in nodes {
        if case .globalFunction(let identifier, let params, let body) = node {
          generateGlobalFunction(identifier, params, body)
        }
        if case .givenDeclaration(let type, let methods) = node {
          if context.containsGenericParameter(type) { continue }
          for method in methods {
            generateGlobalFunction(method.identifier, method.parameters, method.body)
          }
        }
      }

      // 生成 C 的 main 函数
      // 如果有全局变量初始化或用户定义了 main 函数，都需要生成
      if !globalInitializations.isEmpty || userMainFunctionName != nil {
        generateCMainFunction()
      }
  }

  /// 生成 C 的 main 函数入口
  /// 负责初始化全局变量并调用用户定义的 main 函数
  private func generateCMainFunction() {
    buffer += "\nint main() {\n"
    withIndent {
      // 生成全局变量初始化
      if !globalInitializations.isEmpty {
        pushScope()
        for (name, value) in globalInitializations {
          let resultVar = generateExpressionSSA(value)
          addIndent()
          buffer += "\(name) = \(resultVar);\n"
        }
        popScope()
      }
      
      // 调用用户定义的 main 函数
      if let userMain = userMainFunctionName {
        addIndent()
        buffer += "\(userMain)();\n"
      }
      
      addIndent()
      buffer += "return 0;\n"
    }
    buffer += "}\n"
  }

  private func generateForeignUsingDeclaration(_ libraryName: String) {
    buffer += "// Link: -l\(libraryName)\n"
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

  private func generateGlobalFunction(
    _ identifier: Symbol,
    _ params: [Symbol],
    _ body: TypedExpressionNode
  ) {
    let cName = cIdentifier(for: identifier)
    
    // 重置逃逸分析上下文，设置当前函数的返回类型和函数名
    let funcReturnType = getFunctionReturnTypeAsType(identifier.type)
    escapeContext.reset(returnType: funcReturnType, functionName: cName)
    
    // 预分析函数体，识别所有可能逃逸的变量
    escapeContext.preAnalyze(body: body, params: params)
    
    // 重置作用域状态（预分析会修改作用域状态）
    escapeContext.variableScopes = [:]
    escapeContext.currentScopeLevel = 0
    // 注意：escapedVariables 保留，因为这是预分析的结果
    
    // Save Lambda state before generating function body
    let savedLambdaFunctions = lambdaFunctions
    lambdaFunctions = ""
    
    let returnType = getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
    
    // Generate function body to a temporary buffer to collect Lambda functions
    let savedBuffer = buffer
    buffer = ""
    buffer += "\(returnType) \(cName)(\(paramList)) {\n"

    withIndent {
      generateFunctionBody(body, params)
    }
    buffer += "}\n"
    
    let functionCode = buffer
    buffer = savedBuffer
    
    // Insert Lambda functions before this function, then the function itself
    if !lambdaFunctions.isEmpty {
      buffer += lambdaFunctions
    }
    buffer += functionCode
    
    // Restore Lambda state
    lambdaFunctions = savedLambdaFunctions
  }

  // 生成参数的 C 声明：类型若为 reference(T) 则 getCType 返回 T*
  private func getParamCDecl(_ param: Symbol) -> String {
    return "\(cTypeName(param.type)) \(cIdentifier(for: param))"
  }

  private func generateFunctionBody(_ body: TypedExpressionNode, _ params: [Symbol]) {
    pushScope()
    for param in params {
      registerVariable(cIdentifier(for: param), param.type)
    }
    let resultVar = generateExpressionSSA(body)

    // `Never` 表达式不返回；不要生成返回临时变量或 return 语句。
    if body.type == .never {
      popScope()
      return
    }

    let result = nextTemp()
    if case .structure(let defId) = body.type {
      let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
      addIndent()
      if body.valueCategory == .lvalue {
        buffer += "\(cTypeName(body.type)) \(result) = __koral_\(typeName)_copy(&\(resultVar));\n"
      } else {
        buffer += "\(cTypeName(body.type)) \(result) = \(resultVar);\n"
      }
    } else if case .reference(_) = body.type {
      addIndent()
      buffer += "\(cTypeName(body.type)) \(result) = \(resultVar);\n"
      if body.valueCategory == .lvalue {
        addIndent()
        buffer += "__koral_retain(\(result).control);\n"
      }
    } else if body.type != .void {
      addIndent()
      buffer += "\(cTypeName(body.type)) \(result) = \(resultVar);\n"
    }
    popScope()

    if body.type != .void {
      addIndent()
      buffer += "return \(result);\n"
    }
  }

  func generateExpressionSSA(_ expr: TypedExpressionNode) -> String {
    switch expr {
    case .integerLiteral(let value, _):
      return String(value)

    case .floatLiteral(let value, _):
      return String(value)

    case .stringLiteral(let value, let type):
      let bytesVar = nextTemp() + "_bytes"
      let utf8Bytes = Array(value.utf8)
      let byteLiterals = utf8Bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
      addIndent()
      buffer += "static const uint8_t \(bytesVar)[] = { \(byteLiterals) };\n"

      let result = nextTemp()
      addIndent()
      // Use qualified name for String.from_bytes_unchecked via lookup
      let fromBytesMethod = lookupStaticMethod(typeName: "String", methodName: "from_bytes_unchecked")
      buffer += "\(cTypeName(type)) \(result) = \(fromBytesMethod)((uint8_t*)\(bytesVar), \(utf8Bytes.count));\n"
      return result

    case .booleanLiteral(let value, _):
      return value ? "1" : "0"

    case .variable(let identifier):
      return cIdentifier(for: identifier)

    case .castExpression(let inner, let type):
      // Cast is only used for scalar and pointer conversions (Sema enforces legality).
      let innerResult = generateExpressionSSA(inner)
      let targetCType = cTypeName(type)

      if inner.type == type {
        return innerResult
      }

      func isFloat(_ t: Type) -> Bool {
        switch t {
        case .float32, .float64: return true
        default: return false
        }
      }

      func isSignedInt(_ t: Type) -> Bool {
        switch t {
        case .int, .int8, .int16, .int32, .int64: return true
        default: return false
        }
      }

      func isUnsignedInt(_ t: Type) -> Bool {
        switch t {
        case .uint, .uint8, .uint16, .uint32, .uint64: return true
        default: return false
        }
      }

      func minMaxMacros(for t: Type) -> (min: String, max: String)? {
        switch t {
        case .int8: return ("INT8_MIN", "INT8_MAX")
        case .int16: return ("INT16_MIN", "INT16_MAX")
        case .int32: return ("INT32_MIN", "INT32_MAX")
        case .int64: return ("INT64_MIN", "INT64_MAX")
        case .int: return ("INTPTR_MIN", "INTPTR_MAX")
        case .uint8: return ("0", "UINT8_MAX")
        case .uint16: return ("0", "UINT16_MAX")
        case .uint32: return ("0", "UINT32_MAX")
        case .uint64: return ("0", "UINT64_MAX")
        case .uint: return ("0", "UINTPTR_MAX")
        default: return nil
        }
      }

      // float -> int/uint: runtime range check, overflow panics.
      if isFloat(inner.type) && (isSignedInt(type) || isUnsignedInt(type)) {
        guard let (minMacro, maxMacro) = minMaxMacros(for: type) else {
          fatalError("Unsupported float->int cast target: \(type)")
        }

        let fVar = nextTemp()
        addIndent()
        buffer += "double \(fVar) = (double)\(innerResult);\n"

        addIndent()
        buffer += "if (!(\(fVar) >= (double)\(minMacro) && \(fVar) <= (double)\(maxMacro))) {\n"
        withIndent {
          addIndent()
          buffer += "fprintf(stderr, \"Panic: float-to-int cast overflow\\n\");\n"
          addIndent()
          buffer += "abort();\n"
        }
        addIndent()
        buffer += "}\n"

        let result = nextTemp()
        addIndent()
        buffer += "\(targetCType) \(result) = (\(targetCType))\(fVar);\n"
        return result
      }

      // Pointer <-> Int/UInt casts: prefer uintptr_t/intptr_t intermediates.
      if case .pointer = type {
        let result = nextTemp()
        addIndent()
        if inner.type == .uint {
          buffer += "\(targetCType) \(result) = (\(targetCType))(uintptr_t)\(innerResult);\n"
        } else if inner.type == .int {
          buffer += "\(targetCType) \(result) = (\(targetCType))(intptr_t)\(innerResult);\n"
        } else {
          buffer += "\(targetCType) \(result) = (\(targetCType))\(innerResult);\n"
        }
        return result
      }

      if case .pointer = inner.type {
        let result = nextTemp()
        addIndent()
        buffer += "\(targetCType) \(result) = (\(targetCType))\(innerResult);\n"
        return result
      }

      // Default scalar cast.
      let result = nextTemp()
      addIndent()
      buffer += "\(targetCType) \(result) = (\(targetCType))\(innerResult);\n"
      return result

    case .blockExpression(let statements, let finalExpr, _):
      return generateBlockScope(statements, finalExpr: finalExpr)

    case .arithmeticExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let result = nextTemp()
      addIndent()
      buffer +=
        "\(cTypeName(type)) \(result) = \(leftResult) \(arithmeticOpToC(op)) \(rightResult);\n"
      return result

    case .comparisonExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let result = nextTemp()
      addIndent()
      buffer +=
        "\(cTypeName(type)) \(result) = \(leftResult) \(comparisonOpToC(op)) \(rightResult);\n"
      return result

    case .letExpression(let identifier, let value, let body, let type):
      let valueVar = generateExpressionSSA(value)

      let resultVar = nextTemp()
      if type != .void {
        addIndent()
        buffer += "\(cTypeName(type)) \(resultVar);\n"
      }

      addIndent()
      buffer += "{\n"
      withIndent {
        addIndent()
        let cType = cTypeName(identifier.type)
        buffer += "\(cType) \(cIdentifier(for: identifier)) = \(valueVar);\n"

        pushScope()
        registerVariable(cIdentifier(for: identifier), identifier.type)

        let bodyResultVar = generateExpressionSSA(body)

        if type != .void {
          if case .structure(let defId) = type {
            let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
            addIndent()
            if body.valueCategory == .lvalue {
              buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(bodyResultVar));\n"
            } else {
              buffer += "\(resultVar) = \(bodyResultVar);\n"
            }
          } else if case .reference(_) = type {
            addIndent()
            buffer += "\(resultVar) = \(bodyResultVar);\n"
            if body.valueCategory == .lvalue {
              addIndent()
              buffer += "__koral_retain(\(resultVar).control);\n"
            }
          } else {
            addIndent()
            buffer += "\(resultVar) = \(bodyResultVar);\n"
          }
        }

        popScope()
      }
      addIndent()
      buffer += "}\n"

      return type == .void ? "" : resultVar

    case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
      let conditionVar = generateExpressionSSA(condition)

      if type == .void || type == .never {
        addIndent()
        buffer += "if (\(conditionVar)) {\n"
        withIndent {
          pushScope()
          _ = generateExpressionSSA(thenBranch)
          popScope()
        }
        if let elseBranch = elseBranch {
          addIndent()
          buffer += "} else {\n"
          withIndent {
            pushScope()
            _ = generateExpressionSSA(elseBranch)
            popScope()
          }
        }
        addIndent()
        buffer += "}\n"
        return ""
      } else {
        guard let elseBranch = elseBranch else {
          fatalError("Non-void if expression must have else branch (Sema should catch this)")
        }
        let resultVar = nextTemp() // Declare resultVar before using it
        if type != .never {
            addIndent()
            buffer += "\(cTypeName(type)) \(resultVar);\n"
        }
        
        addIndent()
        buffer += "if (\(conditionVar)) {\n"
        withIndent {
          pushScope()
          let thenResult = generateExpressionSSA(thenBranch)
          if type != .never && thenBranch.type != .never {
              addIndent()
              if case .structure(let defId) = type {
                let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
                if thenBranch.valueCategory == .lvalue {
                  switch thenBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(thenResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(thenResult);\n"
                }
              } else if case .union(let defId) = type {
                let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
                if thenBranch.valueCategory == .lvalue {
                  switch thenBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(thenResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(thenResult);\n"
                }
              } else if case .reference(_) = type {
                buffer += "\(resultVar) = \(thenResult);\n"
                if thenBranch.valueCategory == .lvalue {
                  addIndent()
                  buffer += "__koral_retain(\(resultVar).control);\n"
                }
              } else {
                buffer += "\(resultVar) = \(thenResult);\n"
              }
          }
          popScope()
        }
        addIndent()
        buffer += "} else {\n"
        withIndent {
          pushScope()
          let elseResult = generateExpressionSSA(elseBranch)
          if type != .never && elseBranch.type != .never {
              addIndent()
              if case .structure(let defId) = type {
                let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
                if elseBranch.valueCategory == .lvalue {
                  switch elseBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(elseResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(elseResult);\n"
                }
              } else if case .union(let defId) = type {
                let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
                if elseBranch.valueCategory == .lvalue {
                  switch elseBranch {
                  default:
                    buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(elseResult));\n"
                  }
                } else {
                  buffer += "\(resultVar) = \(elseResult);\n"
                }
              } else if case .reference(_) = type {
                buffer += "\(resultVar) = \(elseResult);\n"
                if elseBranch.valueCategory == .lvalue {
                  addIndent()
                  buffer += "__koral_retain(\(resultVar).control);\n"
                }
              } else {
                buffer += "\(resultVar) = \(elseResult);\n"
              }
          }
          popScope()
        }
        addIndent()
        buffer += "}\n"
        return resultVar
      }

    case .call(let callee, let arguments, let type):
      return generateCall(callee, arguments, type)
    case .genericCall:
      fatalError("Generic call should have been resolved by monomorphizer before code generation")
    case .methodReference:
      fatalError("Method reference not in call position is not supported yet")
    case .traitMethodPlaceholder(let traitName, let methodName, let base, _, _):
      fatalError("Unresolved trait method placeholder: \(traitName).\(methodName) on \(base.type)")
    case .staticMethodCall:
      fatalError("Static method call should have been resolved by monomorphizer before code generation")
      
    case .unionConstruction(let type, let caseName, let args):
      return generateUnionConstructor(type: type, caseName: caseName, args: args)

    case .derefExpression(let inner, let type):
      let innerResult = generateExpressionSSA(inner)
      let result = nextTemp()
      
      addIndent()
      buffer += "\(cTypeName(type)) \(result);\n"
      
      if case .structure(let defId) = type {
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        // Struct: call copy constructor
        addIndent()
        buffer += "\(result) = __koral_\(typeName)_copy((struct \(typeName)*)\(innerResult).ptr);\n"
      } else if case .reference(_) = type {
        // Reference: copy struct Ref and retain
        addIndent()
        buffer += "\(result) = *(struct Ref*)\(innerResult).ptr;\n"
        addIndent()
        buffer += "__koral_retain(\(result).control);\n"
      } else {
        // Primitive: direct dereference
        let cType = cTypeName(type)
        addIndent()
        buffer += "\(result) = *(\(cType)*)\(innerResult).ptr;\n"
      }
      return result

    case .ptrExpression(let inner, let type):
      let (lvaluePath, _) = buildRefComponents(inner)
      let result = nextTemp()
      addIndent()
      buffer += "\(cTypeName(type)) \(result) = &\(lvaluePath);\n"
      return result

    case .deptrExpression(let inner, let type):
      let ptrValue = generateExpressionSSA(inner)
      return emitPointerReadCopy(pointerExpr: ptrValue, elementType: type)

    case .referenceExpression(let inner, let type):
      // 使用逃逸分析决定分配策略
      let shouldHeapAllocate = escapeContext.shouldUseHeapAllocation(inner)
      
      if inner.valueCategory == .lvalue && !shouldHeapAllocate {
        // 不逃逸的 lvalue：栈分配（取地址）
        let (lvaluePath, controlPath) = buildRefComponents(inner)
        let result = nextTemp()
        addIndent()
        buffer += "\(cTypeName(type)) \(result);\n"
        addIndent()
        buffer += "\(result).ptr = &\(lvaluePath);\n"
        addIndent()
        buffer += "\(result).control = \(controlPath);\n"
        addIndent()
        buffer += "__koral_retain(\(result).control);\n"
        return result
      } else {
        // 逃逸的 lvalue 或 rvalue：堆分配
        let innerResult = generateExpressionSSA(inner)
        let result = nextTemp()
        let innerType = inner.type
        let innerCType = cTypeName(innerType)

        addIndent()
        buffer += "\(cTypeName(type)) \(result);\n"

        // 1. 分配数据内存
        addIndent()
        buffer += "\(result).ptr = malloc(sizeof(\(innerCType)));\n"

        // 2. 初始化数据
        if case .structure(let defId) = innerType {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          addIndent()
          if inner.valueCategory == .lvalue {
            // 对于逃逸的 lvalue，需要复制数据
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(typeName)_copy(&\(innerResult));\n"
          } else {
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(typeName)_copy(&\(innerResult));\n"
          }
        } else if case .union(let defId) = innerType {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
          addIndent()
          if inner.valueCategory == .lvalue {
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(typeName)_copy(&\(innerResult));\n"
          } else {
            buffer += "*(\(innerCType)*)\(result).ptr = __koral_\(typeName)_copy(&\(innerResult));\n"
          }
        } else {
          addIndent()
          buffer += "*(\(innerCType)*)\(result).ptr = \(innerResult);\n"
        }

        // 3. 分配控制块
        addIndent()
        buffer += "\(result).control = malloc(sizeof(struct Koral_Control));\n"
        addIndent()
        buffer += "((struct Koral_Control*)\(result).control)->count = 1;\n"
        addIndent()
        buffer += "((struct Koral_Control*)\(result).control)->ptr = \(result).ptr;\n"

        // 4. 设置析构函数
        if case .structure(let defId) = innerType {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          addIndent()
          buffer += "((struct Koral_Control*)\(result).control)->dtor = (Koral_Dtor)__koral_\(typeName)_drop;\n"
        } else if case .union(let defId) = innerType {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
          addIndent()
          buffer += "((struct Koral_Control*)\(result).control)->dtor = (Koral_Dtor)__koral_\(typeName)_drop;\n"
        } else {
          addIndent()
          buffer += "((struct Koral_Control*)\(result).control)->dtor = NULL;\n"
        }

        return result
      }

    case .matchExpression(let subject, let cases, let type):
      return generateMatchExpression(subject, cases, type)

    case .whileExpression(let condition, let body, _):
      let labelPrefix = nextTemp()
      let startLabel = "\(labelPrefix)_start"
      let endLabel = "\(labelPrefix)_end"
      addIndent()
      buffer += "\(startLabel): {\n"
      withIndent {
        let conditionVar = generateExpressionSSA(condition)
        addIndent()
        buffer += "if (!\(conditionVar)) { goto \(endLabel); }\n"
        pushScope()
        loopStack.append(LoopContext(startLabel: startLabel, endLabel: endLabel, scopeIndex: lifetimeScopeStack.count - 1))
        _ = generateExpressionSSA(body)
        loopStack.removeLast()
        popScope()
        addIndent()
        buffer += "goto \(startLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return ""
      
    case .ifPatternExpression(let subject, let pattern, _, let thenBranch, let elseBranch, let type):
      // Generate subject expression
      let subjectVar = generateExpressionSSA(subject)
      let subjectTemp = nextTemp() + "_subject"
      addIndent()
      buffer += "\(cTypeName(subject.type)) \(subjectTemp) = \(subjectVar);\n"
      
      // Generate pattern matching condition and bindings
      let (prelude, preludeVars, condition, bindingCode, vars) = 
          generatePatternConditionAndBindings(pattern, subjectTemp, subject.type, isMove: false)
      
      // Output prelude
      for p in prelude {
        addIndent()
        buffer += p
      }
      for (name, varType) in preludeVars {
        registerVariable(name, varType)
      }
      
      if type == .void || type == .never {
        addIndent()
        buffer += "if (\(condition)) {\n"
        withIndent {
          pushScope()
          // Generate bindings
          for b in bindingCode {
            addIndent()
            buffer += b
          }
          // Register bound variables in scope
          for (name, varType) in vars {
            registerVariable(name, varType)
          }
          _ = generateExpressionSSA(thenBranch)
          popScope()
        }
        if let elseBranch = elseBranch {
          addIndent()
          buffer += "} else {\n"
          withIndent {
            pushScope()
            _ = generateExpressionSSA(elseBranch)
            popScope()
          }
        }
        addIndent()
        buffer += "}\n"
        return ""
      } else {
        guard let elseBranch = elseBranch else {
          fatalError("Non-void if pattern expression must have else branch")
        }
        let resultVar = nextTemp()
        if type != .never {
          addIndent()
          buffer += "\(cTypeName(type)) \(resultVar);\n"
        }
        
        addIndent()
        buffer += "if (\(condition)) {\n"
        withIndent {
          pushScope()
          // Generate bindings
          for b in bindingCode {
            addIndent()
            buffer += b
          }
          // Register bound variables in scope
          for (name, varType) in vars {
            registerVariable(name, varType)
          }
          let thenResult = generateExpressionSSA(thenBranch)
          if type != .never && thenBranch.type != .never {
            addIndent()
            if case .structure(let defId) = type {
              let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
              if thenBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(thenResult));\n"
              } else {
                buffer += "\(resultVar) = \(thenResult);\n"
              }
            } else if case .union(let defId) = type {
              let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
              if thenBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(thenResult));\n"
              } else {
                buffer += "\(resultVar) = \(thenResult);\n"
              }
            } else if case .reference(_) = type {
              buffer += "\(resultVar) = \(thenResult);\n"
              if thenBranch.valueCategory == .lvalue {
                addIndent()
                buffer += "__koral_retain(\(resultVar).control);\n"
              }
            } else {
              buffer += "\(resultVar) = \(thenResult);\n"
            }
          }
          popScope()
        }
        addIndent()
        buffer += "} else {\n"
        withIndent {
          pushScope()
          let elseResult = generateExpressionSSA(elseBranch)
          if type != .never && elseBranch.type != .never {
            addIndent()
            if case .structure(let defId) = type {
              let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
              if elseBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(elseResult));\n"
              } else {
                buffer += "\(resultVar) = \(elseResult);\n"
              }
            } else if case .union(let defId) = type {
              let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
              if elseBranch.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(elseResult));\n"
              } else {
                buffer += "\(resultVar) = \(elseResult);\n"
              }
            } else if case .reference(_) = type {
              buffer += "\(resultVar) = \(elseResult);\n"
              if elseBranch.valueCategory == .lvalue {
                addIndent()
                buffer += "__koral_retain(\(resultVar).control);\n"
              }
            } else {
              buffer += "\(resultVar) = \(elseResult);\n"
            }
          }
          popScope()
        }
        addIndent()
        buffer += "}\n"
        return resultVar
      }
      
    case .whilePatternExpression(let subject, let pattern, _, let body, _):
      let labelPrefix = nextTemp()
      let startLabel = "\(labelPrefix)_start"
      let endLabel = "\(labelPrefix)_end"
      
      addIndent()
      buffer += "\(startLabel): {\n"
      withIndent {
        // Generate subject expression (evaluated each iteration)
        let subjectVar = generateExpressionSSA(subject)
        let subjectTemp = nextTemp() + "_subject"
        addIndent()
        buffer += "\(cTypeName(subject.type)) \(subjectTemp) = \(subjectVar);\n"
        
        // Generate pattern matching condition and bindings
        let (prelude, preludeVars, condition, bindingCode, vars) = 
            generatePatternConditionAndBindings(pattern, subjectTemp, subject.type, isMove: false)
        
        // Output prelude
        for p in prelude {
          addIndent()
          buffer += p
        }
        for (name, varType) in preludeVars {
          registerVariable(name, varType)
        }
        
        addIndent()
        buffer += "if (!(\(condition))) { goto \(endLabel); }\n"
        
        pushScope()
        // Generate bindings
        for b in bindingCode {
          addIndent()
          buffer += b
        }
        // Register bound variables in scope
        for (name, varType) in vars {
          registerVariable(name, varType)
        }
        
        loopStack.append(LoopContext(startLabel: startLabel, endLabel: endLabel, scopeIndex: lifetimeScopeStack.count - 1))
        _ = generateExpressionSSA(body)
        loopStack.removeLast()
        popScope()
        addIndent()
        buffer += "goto \(startLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return ""

    case .andExpression(let left, let right, _):
      let result = nextTemp()
      let leftResult = generateExpressionSSA(left)
      let endLabel = nextTemp()

      addIndent()
      buffer += "_Bool \(result);\n"
      addIndent()
      buffer += "if (!\(leftResult)) {\n"
      withIndent {
        addIndent()
        buffer += "\(result) = 0;\n"
        addIndent()
        buffer += "goto \(endLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      // 单独处理短路时的临时对象
      pushScope()
      let rightResult = generateExpressionSSA(right)
      addIndent()
      buffer += "\(result) = \(rightResult);\n"
      popScope()
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return result

    case .orExpression(let left, let right, _):
      let result = nextTemp()
      let leftResult = generateExpressionSSA(left)
      let endLabel = nextTemp()

      addIndent()
      buffer += "_Bool \(result);\n"
      addIndent()
      buffer += "if (\(leftResult)) {\n"
      withIndent {
        addIndent()
        buffer += "\(result) = 1;\n"
        addIndent()
        buffer += "goto \(endLabel);\n"
      }
      addIndent()
      buffer += "}\n"
      // 单独处理短路时的临时对象
      pushScope()
      let rightResult = generateExpressionSSA(right)
      addIndent()
      buffer += "\(result) = \(rightResult);\n"
      popScope()
      addIndent()
      buffer += "\(endLabel): {\n"
      addIndent()
      buffer += "}\n"
      return result

    case .notExpression(let expr, _):
      let exprResult = generateExpressionSSA(expr)
      let result = nextTemp()
      addIndent()
      buffer += "_Bool \(result) = !\(exprResult);\n"
      return result

    case .bitwiseExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let result = nextTemp()
      addIndent()
      buffer += "\(cTypeName(type)) \(result) = \(leftResult) \(bitwiseOpToC(op)) \(rightResult);\n"
      return result

    case .bitwiseNotExpression(let expr, let type):
      let exprResult = generateExpressionSSA(expr)
      let result = nextTemp()
      addIndent()
      buffer += "\(cTypeName(type)) \(result) = ~\(exprResult);\n"
      return result

    case .typeConstruction(let identifier, _, let arguments, _):
      let result = nextTemp()
      var argResults: [String] = []
      
      // Get canonical members to check for casts
       let canonicalMembers: [(name: String, type: Type, mutable: Bool)]
      if case .structure(let defId) = identifier.type.canonical {
        canonicalMembers = context.getStructMembers(defId) ?? []
      } else {
        canonicalMembers = []
      }
      
      for (index, arg) in arguments.enumerated() {
        let argResult = generateExpressionSSA(arg)
        var finalArg = argResult

        if case .structure(let defId) = arg.type {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          addIndent()
          let argCopy = nextTemp()
          if arg.valueCategory == .lvalue {
            switch arg {
            default:
              buffer += "\(cTypeName(arg.type)) \(argCopy) = __koral_\(typeName)_copy(&\(argResult));\n"
            }
          } else {
            buffer += "\(cTypeName(arg.type)) \(argCopy) = \(argResult);\n"
          }
          finalArg = argCopy
        } else if case .reference(_) = arg.type {
          addIndent()
          buffer += "__koral_retain(\(argResult).control);\n"
          finalArg = argResult
        }
        
        // Check for cast
        if index < canonicalMembers.count {
            let canonicalType = canonicalMembers[index].type
            if canonicalType != arg.type {
                let targetCType = cTypeName(canonicalType)
                // Cast the value to the canonical type
                // For structs (like Ref_Int -> Ref_Void), we need to cast the value.
                // Since we are initializing a struct member, we can cast the expression.
                // `(struct Ref_Void) { ... }`? No, C doesn't support casting structs easily unless they are pointers.
                // But here we are initializing `struct Box_R { struct Ref_Void val; }`.
                // We are providing `{ arg }`.
                // If `arg` is `struct Ref_Int`, we can't just cast it to `struct Ref_Void`.
                // We need to reinterpret cast? `*(struct Ref_Void*)&arg`.
                
                finalArg = "*(\(targetCType)*)&(\(finalArg))"
            }
        }
        
        argResults.append(finalArg)
      }

      addIndent()
      buffer += "\(cTypeName(identifier.type)) \(result) = {"
      buffer += argResults.joined(separator: ", ")
      buffer += "};\n"
      return result
    case .memberPath(let source, let path):
      return generateMemberPath(source, path)
    case .subscriptExpression(let base, let args, let method, _):
        guard case .function(_, let returns) = method.type else { fatalError() }
        let callNode = TypedExpressionNode.call(
          callee: .methodReference(base: base, method: method, typeArgs: nil, methodTypeArgs: nil, type: method.type),
          arguments: args,
          type: returns)
        return generateExpressionSSA(callNode)

    case .intrinsicCall(let node):
      return generateIntrinsicSSA(node)
      
    case .lambdaExpression(let parameters, let captures, let body, let type):
      return generateLambdaExpression(parameters: parameters, captures: captures, body: body, type: type)
    }
  }
  


  func generateIntrinsicSSA(_ node: TypedIntrinsic) -> String {
    switch node {
    case .allocMemory(let count, let type):
      // malloc
      guard case .pointer(let element) = type else { fatalError("alloc_memory expects Pointer result") }
      let countVal = generateExpressionSSA(count)
      let elemSize = "sizeof(\(cTypeName(element)))"
      let result = nextTemp()
      addIndent()
      buffer += "\(cTypeName(type)) \(result);\n"
      addIndent()
      buffer += "\(result) = malloc(\(countVal) * \(elemSize));\n"
      return result

    case .deallocMemory(let ptr):
      let ptrVal = generateExpressionSSA(ptr)
      addIndent()
      buffer += "free(\(ptrVal));\n"
      return ""

    case .copyMemory(let dest, let src, let count):
      // memcpy
      guard case .pointer(let element) = dest.type else { fatalError() }
      let d = generateExpressionSSA(dest)
      let s = generateExpressionSSA(src)
      let c = generateExpressionSSA(count)
      let elemSize = "sizeof(\(cTypeName(element)))"
      addIndent()
      buffer += "memcpy(\(d), \(s), \(c) * \(elemSize));\n"
      return ""

    case .moveMemory(let dest, let src, let count):
      // memmove
      guard case .pointer(let element) = dest.type else { fatalError() }
      let d = generateExpressionSSA(dest)
      let s = generateExpressionSSA(src)
      let c = generateExpressionSSA(count)
      let elemSize = "sizeof(\(cTypeName(element)))"
      addIndent()
      buffer += "memmove(\(d), \(s), \(c) * \(elemSize));\n"
      return ""

    case .refCount(let val):
      let valRes = generateExpressionSSA(val)
      let result = nextTemp()
      addIndent()
      buffer += "int \(result) = 0;\n"
      addIndent()
      buffer += "if (\(valRes).control) {\n"
      withIndent {
        addIndent()
        buffer += "\(result) = atomic_load(&((struct Koral_Control*)\(valRes).control)->count);\n"
      }
      addIndent()
      buffer += "}\n"
      return result

    case .initMemory(let ptr, let val):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let v = generateExpressionSSA(val)
      let cType = cTypeName(element)
      addIndent()
      if case .reference(_) = element {
        buffer += "*(struct Ref*)\(p) = \(v);\n"
        addIndent()
        buffer += "__koral_retain(((struct Ref*)\(p))->control);\n"
      } else if case .structure(let defId) = element {
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        buffer += "*(\(cType)*)\(p) = __koral_\(typeName)_copy(&\(v));\n"
      } else if case .union(let defId) = element {
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
        buffer += "*(\(cType)*)\(p) = __koral_\(typeName)_copy(&\(v));\n"
      } else {
        buffer += "*(\(cType)*)\(p) = \(v);\n"
      }
      return ""

    case .deinitMemory(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      if case .reference(_) = element {
        addIndent()
        buffer += "__koral_release(((struct Ref*)\(p))->control);\n"
      } else if case .structure(let defId) = element {
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        addIndent()
        buffer += "__koral_\(typeName)_drop(\(p));\n"
      }
      // int/float/bool/void -> noop
      return ""

    case .takeMemory(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let cType = cTypeName(element)
      let result = nextTemp()
      addIndent()
      buffer += "\(cType) \(result) = *(\(cType)*)\(p);\n"
      return result
    case .offsetPtr(let ptr, let offset):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let o = generateExpressionSSA(offset)
      let cType = cTypeName(element)
      let result = nextTemp()
      addIndent()
      buffer += "\(cTypeName(ptr.type)) \(result);\n"
      addIndent()
      buffer += "\(result) = ((\(cType)*)\(p)) + \(o);\n"
      return result

    case .nullPtr(let resultType):
      let result = nextTemp()
      addIndent()
      buffer += "\(cTypeName(resultType)) \(result) = NULL;\n"
      return result

    case .exit(let code):
      let c = generateExpressionSSA(code)
      addIndent()
      buffer += "exit(\(c));\n"
      return ""

    case .abort:
      addIndent()
      buffer += "abort();\n"
      return ""

    case .float32Bits(let value):
      let v = generateExpressionSSA(value)
      let result = nextTemp()
      addIndent()
      buffer += "uint32_t \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(v), sizeof(uint32_t));\n"
      return result

    case .float64Bits(let value):
      let v = generateExpressionSSA(value)
      let result = nextTemp()
      addIndent()
      buffer += "uint64_t \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(v), sizeof(uint64_t));\n"
      return result

    case .float32FromBits(let bits):
      let b = generateExpressionSSA(bits)
      let bitsTemp = nextTemp()
      let result = nextTemp()
      addIndent()
      buffer += "uint32_t \(bitsTemp) = \(b);\n"
      addIndent()
      buffer += "float \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(bitsTemp), sizeof(float));\n"
      return result

    case .float64FromBits(let bits):
      let b = generateExpressionSSA(bits)
      let bitsTemp = nextTemp()
      let result = nextTemp()
      addIndent()
      buffer += "uint64_t \(bitsTemp) = \(b);\n"
      addIndent()
      buffer += "double \(result) = 0;\n"
      addIndent()
      buffer += "memcpy(&\(result), &\(bitsTemp), sizeof(double));\n"
      return result

    // Low-level IO intrinsics (minimal set using file descriptors)
    case .fwrite(let ptr, let len, let fd):
      let p = generateExpressionSSA(ptr)
      let l = generateExpressionSSA(len)
      let f = generateExpressionSSA(fd)
      let result = nextTemp()
      addIndent()
      buffer += "FILE* _fwrite_stream_\(result) = (\(f) == 1) ? stdout : ((\(f) == 2) ? stderr : stdin);\n"
      addIndent()
      buffer += "int64_t \(result) = fwrite((const char*)\(p), 1, \(l), _fwrite_stream_\(result));\n"
      return result

    case .fgetc(let fd):
      let f = generateExpressionSSA(fd)
      let result = nextTemp()
      addIndent()
      buffer += "FILE* _fgetc_stream_\(result) = (\(f) == 0) ? stdin : ((\(f) == 1) ? stdout : stderr);\n"
      addIndent()
      buffer += "int64_t \(result) = fgetc(_fgetc_stream_\(result));\n"
      return result

    case .fflush(let fd):
      let f = generateExpressionSSA(fd)
      addIndent()
      buffer += "FILE* _fflush_stream = (\(f) == 1) ? stdout : ((\(f) == 2) ? stderr : stdin);\n"
      addIndent()
      buffer += "fflush(_fflush_stream);\n"
      return ""
    }
  }


  func nextTemp() -> String {
    tempVarCounter += 1
    return "_t\(tempVarCounter)"
  }

  func generateStatement(_ stmt: TypedStatementNode) {
    switch stmt {
    case .variableDeclaration(let identifier, let value, _):
      let valueResult = generateExpressionSSA(value)
      // void/never 类型的值不能赋给变量
      if value.type != .void && value.type != .never {
        // 如果是可变类型，增加引用计数
        if case .structure(let defId) = identifier.type {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          addIndent()
          buffer += "\(cTypeName(identifier.type)) \(cIdentifier(for: identifier)) = "
          if value.valueCategory == .lvalue {
            buffer += "__koral_\(typeName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(valueResult);\n"
          }
          registerVariable(cIdentifier(for: identifier), identifier.type)
        } else if case .union(let defId) = identifier.type {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
          addIndent()
          buffer += "\(cTypeName(identifier.type)) \(cIdentifier(for: identifier)) = "
          if value.valueCategory == .lvalue {
            buffer += "__koral_\(typeName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(valueResult);\n"
          }
          registerVariable(cIdentifier(for: identifier), identifier.type)
        } else if case .reference(_) = identifier.type {
          addIndent()
          buffer += "\(cTypeName(identifier.type)) \(cIdentifier(for: identifier)) = \(valueResult);\n"
          if value.valueCategory == .lvalue {
            addIndent()
            buffer += "__koral_retain(\(cIdentifier(for: identifier)).control);\n"
          }
          registerVariable(cIdentifier(for: identifier), identifier.type)
        } else {
          addIndent()
          buffer += "\(cTypeName(identifier.type)) \(cIdentifier(for: identifier)) = \(valueResult);\n"
        }
      }
    case .assignment(let target, let op, let value):
      if let op {
        let (lhsPath, _) = buildRefComponents(target)
        let valueResult = generateExpressionSSA(value)
        let opStr = compoundOpToC(op)
        
        addIndent()
        buffer += "\(lhsPath) \(opStr) \(valueResult);\n"
      } else {
        // 检测是否是结构体字段赋值（用于逃逸分析）
        let isFieldAssignment = isStructFieldAssignment(target)
        if isFieldAssignment && isReferenceType(value.type) {
          escapeContext.inFieldAssignmentContext = true
        }
        
        // Use buildRefComponents to get the C LValue path
        let (lhsPath, _) = buildRefComponents(target)
        let valueResult = generateExpressionSSA(value)
        
        escapeContext.inFieldAssignmentContext = false
        
        if value.type == .void || value.type == .never { return }

        if case .structure(let defId) = target.type {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          addIndent()
          if value.valueCategory == .lvalue {
            buffer += "\(lhsPath) = __koral_\(typeName)_copy(&\(valueResult));\n"
          } else {
             buffer += "\(lhsPath) = \(valueResult);\n"
          }
        } else if case .reference(_) = target.type {
           addIndent()
           buffer += "\(lhsPath) = \(valueResult);\n"
           if value.valueCategory == .lvalue {
               addIndent()
               buffer += "__koral_retain(\(lhsPath).control);\n"
           }
        } else {
           addIndent()
           buffer += "\(lhsPath) = \(valueResult);\n"
        }
      }

    case .deptrAssignment(let pointer, let op, let value):
      guard case .pointer(let elementType) = pointer.type else { fatalError() }
      let ptrValue = generateExpressionSSA(pointer)

      if let op {
        let oldValue = emitPointerReadCopy(pointerExpr: ptrValue, elementType: elementType)
        let rhsValue = generateExpressionSSA(value)
        let newValue = nextTemp()
        addIndent()
        buffer += "\(cTypeName(elementType)) \(newValue) = \(oldValue) \(compoundOpToC(op).dropLast()) \(rhsValue);\n"

        appendDropStatement(for: elementType, value: "(*\(ptrValue))")
        appendCopyAssignment(for: elementType, source: newValue, dest: "(*\(ptrValue))")
      } else {
        let valueResult = generateExpressionSSA(value)
        appendDropStatement(for: elementType, value: "(*\(ptrValue))")
        appendCopyAssignment(for: elementType, source: valueResult, dest: "(*\(ptrValue))")
      }
      
    case .expression(let expr):
      _ = generateExpressionSSA(expr)

    case .return(let value):
      if let value = value {
        if value.type == .never {
          _ = generateExpressionSSA(value)
          return
        }
        
        // 设置返回上下文标志，用于逃逸分析
        escapeContext.inReturnContext = true
        let valueResult = generateExpressionSSA(value)
        escapeContext.inReturnContext = false
        
        let retVar = nextTemp()

        if case .structure(let defId) = value.type {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
          addIndent()
          if value.valueCategory == .lvalue {
            buffer += "\(cTypeName(value.type)) \(retVar) = __koral_\(typeName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(cTypeName(value.type)) \(retVar) = \(valueResult);\n"
          }
        } else if case .union(let defId) = value.type {
          let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
          addIndent()
          if value.valueCategory == .lvalue {
            buffer += "\(cTypeName(value.type)) \(retVar) = __koral_\(typeName)_copy(&\(valueResult));\n"
          } else {
            buffer += "\(cTypeName(value.type)) \(retVar) = \(valueResult);\n"
          }
        } else if case .reference(_) = value.type {
          addIndent()
          buffer += "\(cTypeName(value.type)) \(retVar) = \(valueResult);\n"
          if value.valueCategory == .lvalue {
            addIndent()
            buffer += "__koral_retain(\(retVar).control);\n"
          }
        } else {
          addIndent()
          buffer += "\(cTypeName(value.type)) \(retVar) = \(valueResult);\n"
        }

        emitCleanup(fromScopeIndex: 0)
        addIndent()
        buffer += "return \(retVar);\n"
      } else {
        emitCleanup(fromScopeIndex: 0)
        addIndent()
        buffer += "return;\n"
      }

    case .break:
      guard let ctx = loopStack.last else {
        fatalError("break used outside of loop codegen")
      }
      emitCleanup(fromScopeIndex: ctx.scopeIndex)
      addIndent()
      buffer += "goto \(ctx.endLabel);\n"

    case .continue:
      guard let ctx = loopStack.last else {
        fatalError("continue used outside of loop codegen")
      }
      emitCleanup(fromScopeIndex: ctx.scopeIndex)
      addIndent()
      buffer += "goto \(ctx.startLabel);\n"
    }
  }

  func cTypeName(_ type: Type) -> String {
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
    case .structure(let defId):
      if context.isForeignStruct(defId) {
        appendToBuffer("\(indent)\(dest) = \(source);\n")
      } else {
        let fieldTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        appendToBuffer("\(indent)\(dest) = __koral_\(fieldTypeName)_copy(&\(source));\n")
      }
    case .union(let defId):
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

  func appendDropStatement(for type: Type, value: String, indent: String = "    ") {
    switch type {
    case .structure(let defId):
      if context.isForeignStruct(defId) {
        return
      }
      let fieldTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
      appendToBuffer("\(indent)__koral_\(fieldTypeName)_drop(&\(value));\n")
    case .union(let defId):
      let fieldTypeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      appendToBuffer("\(indent)__koral_\(fieldTypeName)_drop(&\(value));\n")
    default:
      let dropCode = TypeHandlerRegistry.shared.generateDropCode(type, value: value)
      appendIndentedCode(dropCode, indent: indent)
    }
  }

  func emitPointerReadCopy(pointerExpr: String, elementType: Type) -> String {
    let result = nextTemp()
    let cType = cTypeName(elementType)
    addIndent()
    buffer += "\(cType) \(result);\n"

    if case .structure(let defId) = elementType {
      if context.isForeignStruct(defId) {
        addIndent()
        buffer += "\(result) = *(\(cType)*)\(pointerExpr);\n"
      } else {
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        addIndent()
        buffer += "\(result) = __koral_\(typeName)_copy((\(cType)*)\(pointerExpr));\n"
      }
    } else if case .union(let defId) = elementType {
      let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      addIndent()
      buffer += "\(result) = __koral_\(typeName)_copy((\(cType)*)\(pointerExpr));\n"
    } else if case .reference(_) = elementType {
      addIndent()
      buffer += "\(result) = *(\(cType)*)\(pointerExpr);\n"
      addIndent()
      buffer += "__koral_retain(\(result).control);\n"
    } else {
      addIndent()
      buffer += "\(result) = *(\(cType)*)\(pointerExpr);\n"
    }

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
  
  // MARK: - 逃逸分析辅助函数
  
  /// 检查表达式是否是结构体字段赋值
  func isStructFieldAssignment(_ target: TypedExpressionNode) -> Bool {
    switch target {
    case .memberPath(let source, let path):
      // 如果路径长度 > 0，说明是字段访问
      if !path.isEmpty {
        // 检查源是否是结构体类型
        if case .structure(_) = source.type {
          return true
        }
        if case .union(_) = source.type {
          return true
        }
      }
      return false
    default:
      return false
    }
  }
  
  /// 检查类型是否是引用类型
  func isReferenceType(_ type: Type) -> Bool {
    if case .reference(_) = type {
      return true
    }
    return false
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
    return userDefinedDrops[typeName]
  }

  func generateMatchExpression(_ subject: TypedExpressionNode, _ cases: [TypedMatchCase], _ type: Type) -> String {
    let subjectVarSSA = generateExpressionSSA(subject)
    let resultVar = nextTemp()
    
    if type != .void && type != .never {
        addIndent()
        buffer += "\(cTypeName(type)) \(resultVar);\n"
    }
    
    // Dereference subject if it acts as a reference but pattern matches against value
    var subjectVar = subjectVarSSA
    var subjectType = subject.type
    if case .reference(let inner) = subject.type {
        let innerCType = cTypeName(inner)
        let derefVar = nextTemp()
        addIndent()
        buffer += "\(innerCType) \(derefVar) = *(\(innerCType)*)\(subjectVarSSA).ptr;\n"
        subjectVar = derefVar
        subjectType = inner
    }
    

    let endLabel = "match_end_\(nextTemp())"
    
    for c in cases {
         addIndent()
         buffer += "{\n"
         withIndent {
         let caseScopeIndex = lifetimeScopeStack.count
         pushScope()

         let isMove = false
         let (prelude, preludeVars, condition, bindings, vars) = generatePatternConditionAndBindings(c.pattern, subjectVar, subjectType, isMove: isMove)

         // Prelude runs regardless of match success (temps used in the condition)
         for p in prelude {
           addIndent()
           buffer += p
         }
         for (name, varType) in preludeVars {
           registerVariable(name, varType)
         }

         addIndent()
         buffer += "if (\(condition)) {\n"
         withIndent {
           // Bindings should only exist on the matched path
           pushScope()

           for b in bindings {
             addIndent()
             buffer += b
           }
           for (name, varType) in vars {
             registerVariable(name, varType)
           }
                 
           let bodyResult = generateExpressionSSA(c.body)
           if type != .void && type != .never && c.body.type != .never {
             addIndent()
             if case .structure(let defId) = type {
              let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
              if c.body.valueCategory == .lvalue {
                buffer += "\(resultVar) = __koral_\(typeName)_copy(&\(bodyResult));\n"
              } else {
                 buffer += "\(resultVar) = \(bodyResult);\n"
              }
             } else if case .reference(_) = type {
              buffer += "\(resultVar) = \(bodyResult);\n"
              if c.body.valueCategory == .lvalue {
                 addIndent()
                 buffer += "__koral_retain(\(resultVar).control);\n"
              }
             } else {
              buffer += "\(resultVar) = \(bodyResult);\n"
             }
           }

           // Cleanup bindings, then cleanup prelude temps (outer case scope), then jump out.
           popScope()
           emitCleanupForScope(at: caseScopeIndex)
           addIndent()
           buffer += "goto \(endLabel);\n"
         }
         addIndent()
         buffer += "}\n"

         // Mismatch path: cleanup prelude temps, then discard the prelude scope.
         emitCleanupForScope(at: caseScopeIndex)
         popScopeWithoutCleanup()
         }
         addIndent()
         buffer += "}\n"
    }
    
    addIndent()
    buffer += "\(endLabel):;\n"
    return (type == .void || type == .never) ? "" : resultVar
  }

    func generatePatternConditionAndBindings(
    _ pattern: TypedPattern,
    _ path: String,
    _ type: Type,
    isMove: Bool = false
    ) -> (prelude: [String], preludeVars: [(String, Type)], condition: String, bindings: [String], vars: [(String, Type)]) {
      switch pattern {
      case .integerLiteral(let val):
        return ([], [], "\(path) == \(val)", [], [])
      case .booleanLiteral(let val):
        return ([], [], "\(path) == \(val ? 1 : 0)", [], [])
      case .stringLiteral(let value):
        let bytesVar = nextTemp() + "_pat_bytes"
        let utf8Bytes = Array(value.utf8)
        let byteLiterals = utf8Bytes.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
        let literalVar = nextTemp() + "_pat_str"
        var prelude = ""
        prelude += "static const uint8_t \(bytesVar)[] = { \(byteLiterals) };\n"
        // Use qualified name for String.from_bytes_unchecked via lookup
        let fromBytesMethod = lookupStaticMethod(typeName: "String", methodName: "from_bytes_unchecked")
        prelude += "\(cTypeName(type)) \(literalVar) = \(fromBytesMethod)((uint8_t*)\(bytesVar), \(utf8Bytes.count));\n"
        // Compare via compiler-protocol `String.__equals(self, other String) Bool`.
        // Value-passing semantics: String___equals consumes its arguments, so we must copy
        // the subject before comparison to allow multiple pattern matches on the same variable.
        guard case .structure(let defId) = type else { fatalError("String literal pattern requires String type") }
        // Use qualified name for String.__equals via lookup
        let equalsMethod = lookupStaticMethod(typeName: "String", methodName: "__equals")
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        return ([prelude], [(literalVar, type)], "\(equalsMethod)(__koral_\(typeName)_copy(&\(path)), \(literalVar))", [], [])
      case .wildcard:
        return ([], [], "1", [], [])
      case .variable(let symbol):
        let name = cIdentifier(for: symbol)
        let varType = symbol.type
        var bindCode = ""
        let cType = cTypeName(varType)
        bindCode += "\(cType) \(name);\n"
          
        if isMove {
          // Move Semantics: Shallow Copy. Source cleanup is suppressed via consumeVariable.
          bindCode += "\(name) = \(path);\n"
        } else {
          // Copy Semantics
           if case .structure(let defId) = varType {
             let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
             bindCode += "\(name) = __koral_\(typeName)_copy(&\(path));\n"
          } else if case .reference(_) = varType {
             bindCode += "\(name) = \(path);\n"
             bindCode += "__koral_retain(\(name).control);\n"
          } else {
             bindCode += "\(name) = \(path);\n"
          }
        }
        return ([], [], "1", [bindCode], [(name, varType)])
          
      case .unionCase(let caseName, let expectedTagIndex, let args):
        guard case .union(let defId) = type else { fatalError("Union pattern on non-union type") }
        let cases = context.getUnionCases(defId) ?? []
          
        var prelude: [String] = []
        var preludeVars: [(String, Type)] = []
        var condition = "(\(path).tag == \(expectedTagIndex))"
        var bindings: [String] = []
        var vars: [(String, Type)] = []
          
        let caseDef = cases[expectedTagIndex]
        let escapedCaseName = sanitizeCIdentifier(caseName)
          
        for (i, subInd) in args.enumerated() {
           let paramName = sanitizeCIdentifier(caseDef.parameters[i].name)
           let paramType = caseDef.parameters[i].type
           let subPath = "\(path).data.\(escapedCaseName).\(paramName)"
               
           let (subPre, subPreVars, subCond, subBind, subVars) = generatePatternConditionAndBindings(subInd, subPath, paramType, isMove: isMove)
               
           if subCond != "1" {
             condition += " && (\(subCond))"
           }
           prelude.append(contentsOf: subPre)
           preludeVars.append(contentsOf: subPreVars)
           bindings.append(contentsOf: subBind)
           vars.append(contentsOf: subVars)
        }
        return (prelude, preludeVars, condition, bindings, vars)
        
      case .comparisonPattern(let op, let value):
        // Comparison pattern generates a simple comparison
        let opStr: String
        switch op {
        case .greater: opStr = ">"
        case .less: opStr = "<"
        case .greaterEqual: opStr = ">="
        case .lessEqual: opStr = "<="
        }
        
        let condition = "(\(path) \(opStr) \(value))"
        return ([], [], condition, [], [])
        
      case .andPattern(let left, let right):
        // And pattern: both sub-patterns must match
        let (leftPre, leftPreVars, leftCond, leftBind, leftVars) = 
            generatePatternConditionAndBindings(left, path, type, isMove: isMove)
        let (rightPre, rightPreVars, rightCond, rightBind, rightVars) = 
            generatePatternConditionAndBindings(right, path, type, isMove: isMove)
        
        let condition = "(\(leftCond)) && (\(rightCond))"
        return (
            leftPre + rightPre,
            leftPreVars + rightPreVars,
            condition,
            leftBind + rightBind,
            leftVars + rightVars
        )
        
      case .orPattern(let left, let right):
        // Or pattern: either sub-pattern must match
        // For bindings, we need to handle them specially since both branches bind the same variables
        let (leftPre, leftPreVars, leftCond, leftBind, leftVars) = 
            generatePatternConditionAndBindings(left, path, type, isMove: isMove)
        let (rightPre, rightPreVars, rightCond, rightBind, rightVars) = 
            generatePatternConditionAndBindings(right, path, type, isMove: isMove)
        
        let condition = "(\(leftCond)) || (\(rightCond))"
        
        // For or patterns with bindings, we need to generate conditional bindings
        // The bindings should be the same in both branches (enforced by type checker)
        // We use the left branch bindings but they will be set by whichever branch matches
        // Since both branches bind the same variables, we can use either set
        // The actual binding code will be generated based on which branch matched
        
        // If there are bindings, we need to generate conditional binding code
        var combinedBind: [String] = []
        if !leftVars.isEmpty {
            // Generate conditional bindings using ternary operator
            // First, we need to evaluate which branch matched
            let matchLeftVar = nextTemp() + "_match_left"
            combinedBind.append("int \(matchLeftVar) = \(leftCond);\n")
            
            // For each variable, generate conditional assignment
            for (i, (name, varType)) in leftVars.enumerated() {
                let cType = cTypeName(varType)
                combinedBind.append("\(cType) \(name);\n")
                
                // Get the binding expressions from left and right
                // This is simplified - in practice we'd need to extract the actual binding expressions
                // For now, we assume the binding is just the path (for simple variable patterns)
                if i < rightVars.count {
                    // Both branches have this variable - use conditional
                    combinedBind.append("if (\(matchLeftVar)) {\n")
                    combinedBind.append(contentsOf: leftBind.filter { $0.contains(name) })
                    combinedBind.append("} else {\n")
                    combinedBind.append(contentsOf: rightBind.filter { $0.contains(name) })
                    combinedBind.append("}\n")
                }
            }
        }
        
        // If no bindings, just use empty bindings
        let finalBind = leftVars.isEmpty ? [] : combinedBind
        
        return (
            leftPre + rightPre,
            leftPreVars + rightPreVars,
            condition,
            finalBind,
            leftVars
        )
        
      case .notPattern(let pattern):
        // Not pattern: negate the sub-pattern condition
        let (pre, preVars, cond, _, _) = 
            generatePatternConditionAndBindings(pattern, path, type, isMove: isMove)
        
        let condition = "!(\(cond))"
        // Not patterns cannot have bindings (enforced by type checker)
        return (pre, preVars, condition, [], [])
      }
    }


}

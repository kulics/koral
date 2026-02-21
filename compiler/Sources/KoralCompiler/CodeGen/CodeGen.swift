import Foundation

// MARK: - C Code Generation Extensions for Qualified Names
// 
// 使用 CIdentifierUtils.swift 中的统一工具函数生成 C 标识符。
// 这确保了 CodeGen 和 DefId 系统使用一致的标识符生成逻辑。

public class CodeGen {
  let ast: MonomorphizedProgram
  internal let context: CompilerContext
  var indent: String = ""
  var buffer: String = ""
  var tempVarCounter = 0
  private var globalInitializations: [(String, TypedExpressionNode)] = []
  var lifetimeScopeStack: [[(name: String, type: Type)]] = []
  var userDefinedDrops: [String: String] = [:] // TypeName -> Mangled Drop Function Name
  private(set) var cIdentifierByDefId: [UInt64: String] = [:]
  private var foreignFunctionDefIds: Set<UInt64> = []
  private var foreignGlobalVarDefIds: Set<UInt64> = []
  
  // MARK: - Vtable Instance Tracking
  /// Tracks generated vtable instance names to avoid duplicate generation.
  /// Key format: `__koral_vtable_{TraitName}_for_{ConcreteType}`
  var generatedVtableInstances: Set<String> = []
  
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
  
  /// Pattern binding aliases: maps a pattern-bound variable's C identifier
  /// to the subject's field path expression. Used for borrow semantics in
  /// match/when, if-is, and while-is pattern matching — bindings are aliases
  /// into the subject rather than copies, analogous to Rust/Swift match semantics.
  var patternBindingAliases: [String: String] = [:]
  
  /// Lambda capture aliases: maps a captured variable's DefId to the expression
  /// used to access it inside the lambda body (e.g., `(*__captured->names_42)`).
  /// This enables by-reference capture semantics — the lambda accesses the
  /// caller's original variable through a pointer stored in the env struct.
  var capturedVarAliases: [UInt64: String] = [:]
  
  // MARK: - Temp Pool for Stack Slot Reuse
  /// Stack of active temp pools. When non-empty, nextTemp() allocates from the top pool.
  /// Each match/if-else expression pushes its own pool; nested expressions get their own.
  var tempPoolStack: [TempPool] = []
  /// Counter for generating unique pool prefixes (monotonically increasing).
  var tempPoolPrefixCounter: Int = 0
  /// Tracks variables acquired from the current pool within the current branch,
  /// so they can be released at branch end.
  var currentBranchPoolVars: [(name: String, cType: String)] = []
  
  /// 是否启用逃逸分析报告
  private let escapeAnalysisReportEnabled: Bool
  
  /// 全局逃逸分析结果
  private var globalEscapeResult: GlobalEscapeResult?

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
    self.foreignFunctionDefIds = Set(ast.globalNodes.compactMap { node in
      if case .foreignFunction(let identifier, _) = node {
        return identifier.defId.id
      }
      return nil
    })
    self.foreignGlobalVarDefIds = Set(ast.globalNodes.compactMap { node in
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
    // Check lambda capture aliases first — captured variables are accessed
    // through pointers in the env struct for by-reference capture semantics.
    if let alias = capturedVarAliases[symbol.defId.id] {
      return alias
    }
    if foreignFunctionDefIds.contains(symbol.defId.id) {
      let name = context.getName(symbol.defId) ?? "<unknown>"
      return sanitizeCIdentifier(name)
    }
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
      let access = context.getAccess(symbol.defId) ?? .default
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

  func needsDrop(_ type: Type) -> Bool {
    switch type {
    case .structure, .union, .reference, .function, .weakReference:
      return true
    default:
      return false
    }
  }


  public func generate() -> String {
    buffer = """
      #include <stdatomic.h>
      #include <stdint.h>
      #include "koral_checked_math.h"

      void koral_panic_float_cast_overflow(void);

      """

    buffer += """
      void koral_set_args(int32_t argc, uint8_t** argv);

      """

    emitForeignUsingDeclarations(from: ast.globalNodes)

    buffer += """
      // Generic Ref type
      struct Ref { void* ptr; void* control; };

      // Unified Closure type for all function types
      // fn: function pointer (with env as first param if env != NULL)
      // env: environment pointer (NULL for no-capture lambdas)
      // drop: environment destructor (NULL for no-capture lambdas)
      struct __koral_Closure { void* fn; void* env; void (*drop)(void*); };

      typedef void (*Koral_Dtor)(void*);

      struct Koral_Control {
        _Atomic int strong_count;
        _Atomic int weak_count;
        Koral_Dtor dtor;
        void* ptr;
      };

      // WeakRef structure for weak references
      struct WeakRef { void* control; };

      // TraitRef: fat pointer for trait object references (ptr + control + vtable)
      struct TraitRef { void* ptr; void* control; const void* vtable; };

      // TraitWeakRef: fat pointer for trait object weak references (control + vtable)
      struct TraitWeakRef { void* control; const void* vtable; };

      void __koral_retain(void* raw_control) {
        if (!raw_control) return;
        struct Koral_Control* control = (struct Koral_Control*)raw_control;
        atomic_fetch_add(&control->strong_count, 1);
      }

      void __koral_release(void* raw_control) {
        if (!raw_control) return;
        struct Koral_Control* control = (struct Koral_Control*)raw_control;
        int prev = atomic_fetch_sub(&control->strong_count, 1);
        if (prev == 1) {
          // Strong count reached zero - destroy object
          if (control->dtor) {
            control->dtor(control->ptr);
          }
          free(control->ptr);
          // Decrement implicit weak count (control block itself)
          int weak_prev = atomic_fetch_sub(&control->weak_count, 1);
          if (weak_prev == 1) {
            // No more weak references, free control block
            free(control);
          }
        }
      }

      void __koral_weak_retain(void* raw_control) {
        if (!raw_control) return;
        struct Koral_Control* control = (struct Koral_Control*)raw_control;
        atomic_fetch_add(&control->weak_count, 1);
      }

      void __koral_weak_release(void* raw_control) {
        if (!raw_control) return;
        struct Koral_Control* control = (struct Koral_Control*)raw_control;
        int prev = atomic_fetch_sub(&control->weak_count, 1);
        if (prev == 1) {
          // No more weak references and strong count is zero
          // (otherwise weak_count would be at least 1 from implicit weak ref)
          free(control);
        }
      }

      struct WeakRef __koral_downgrade_ref(struct Ref r) {
        struct WeakRef w;
        w.control = r.control;
        if (w.control) {
          __koral_weak_retain(w.control);
        }
        return w;
      }

      struct Ref __koral_upgrade_ref(struct WeakRef w, int* success) {
        struct Ref r;
        r.ptr = NULL;
        r.control = NULL;
        *success = 0;
        
        if (!w.control) return r;
        
        struct Koral_Control* control = (struct Koral_Control*)w.control;
        
        // Try to atomically increment strong_count if it's > 0
        int old_count = atomic_load(&control->strong_count);
        while (old_count > 0) {
          if (atomic_compare_exchange_weak(&control->strong_count, &old_count, old_count + 1)) {
            // Successfully upgraded
            r.ptr = control->ptr;
            r.control = w.control;
            *success = 1;
            return r;
          }
          // old_count was updated by compare_exchange_weak, retry
        }
        
        // Strong count is 0, cannot upgrade
        return r;
      }

      void __koral_closure_retain(struct __koral_Closure closure) {
        if (!closure.env) return;
        _Atomic intptr_t* refcount = (_Atomic intptr_t*)closure.env;
        atomic_fetch_add(refcount, 1);
      }

      void __koral_closure_release(struct __koral_Closure closure) {
        if (!closure.env) return;
        _Atomic intptr_t* refcount = (_Atomic intptr_t*)closure.env;
        intptr_t prev = atomic_fetch_sub(refcount, 1);
        if (prev == 1) {
          if (closure.drop) {
            closure.drop(closure.env);
          } else {
            free(closure.env);
          }
        }
      }

      """

    // 生成程序体
    generateProgram(ast)
    
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
          if context.containsGenericParameter(identifier.type) { continue }
          generateFunctionDeclaration(identifier, params)
        }
        if case .givenDeclaration(let type, let methods) = node {
          if context.containsGenericParameter(type) { continue }
          for method in methods {
            if context.containsGenericParameter(method.identifier.type) { continue }
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

      // 生成 vtable 结构体、wrapper 函数和 vtable 实例
      processVtableRequests()

      // 全局逃逸分析：在生成函数实现之前，按调用图逆拓扑序分析所有函数
      let globalAnalyzer = GlobalEscapeAnalyzer(context: context, program: program)
      globalEscapeResult = globalAnalyzer.analyze()

      // 生成函数实现
      for node in nodes {
        if case .globalFunction(let identifier, let params, let body) = node {
          if context.containsGenericParameter(identifier.type) { continue }
          generateGlobalFunction(identifier, params, body)
        }
        if case .givenDeclaration(let type, let methods) = node {
          if context.containsGenericParameter(type) { continue }
          for method in methods {
            if context.containsGenericParameter(method.identifier.type) { continue }
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
    buffer += "\nint main(int argc, char** argv) {\n"
    withIndent {
      addIndent()
      buffer += "koral_set_args((int32_t)argc, (uint8_t**)argv);\n"

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
    
    // 使用全局逃逸分析结果（如果可用），否则回退到 per-function 分析
    if let result = globalEscapeResult,
       let escaped = result.escapedVariablesPerFunction[identifier.defId.id] {
        escapeContext.escapedVariables = escaped
    } else {
        // Fallback: 使用原有的 per-function 分析
        escapeContext.preAnalyze(body: body, params: params)
        escapeContext.variableScopes = [:]
        escapeContext.currentScopeLevel = 0
    }
    
    // Save Lambda state before generating function body
    let savedLambdaFunctions = lambdaFunctions
    lambdaFunctions = ""
    let savedLambdaEnvStructs = lambdaEnvStructs
    lambdaEnvStructs = ""
    
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
    
    let envStructs = lambdaEnvStructs

    // Insert Lambda functions before this function, then the function itself
    if !envStructs.isEmpty {
      buffer += envStructs
    }
    if !lambdaFunctions.isEmpty {
      buffer += lambdaFunctions
    }
    buffer += functionCode
    
    // Restore Lambda state
    lambdaFunctions = savedLambdaFunctions
    lambdaEnvStructs = savedLambdaEnvStructs
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
    if body.type != .void {
      emitDeclareAndCopyOrMove(type: body.type, source: resultVar, dest: result, isLvalue: body.valueCategory == .lvalue)
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

      let cType = cTypeName(type)
      // Use qualified name for String.from_bytes_unchecked via lookup
      let fromBytesMethod = lookupStaticMethod(typeName: "String", methodName: "from_bytes_unchecked")
      let result = nextTempWithInit(cType: cType, initExpr: "\(fromBytesMethod)((uint8_t*)\(bytesVar), \(utf8Bytes.count))")
      return result

    case .interpolatedString:
      fatalError("Interpolated strings must be lowered before code generation")

    case .booleanLiteral(let value, _):
      return value ? "1" : "0"

    case .variable(let identifier):
      if identifier.type == .void {
        return "0"
      }
      // Lambda capture aliases — captured variables accessed through env pointer
      if let alias = capturedVarAliases[identifier.defId.id] {
        return alias
      }
      let cName = cIdentifier(for: identifier)
      // Pattern-bound variables are aliases into the subject — return the path directly
      if let alias = patternBindingAliases[cName] {
        return alias
      }
      return cName

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

        let fVar = nextTempWithInit(cType: "double", initExpr: "(double)\(innerResult)")

        addIndent()
        buffer += "if (!(\(fVar) >= (double)\(minMacro) && \(fVar) <= (double)\(maxMacro))) {\n"
        withIndent {
          addIndent()
          buffer += "koral_panic_float_cast_overflow();\n"
        }
        addIndent()
        buffer += "}\n"

        let result = nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(fVar)")
        return result
      }

      // Pointer <-> Int/UInt casts: prefer uintptr_t/intptr_t intermediates.
      if case .pointer = type {
        if inner.type == .uint {
          let result = nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))(uintptr_t)\(innerResult)")
          return result
        } else if inner.type == .int {
          let result = nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))(intptr_t)\(innerResult)")
          return result
        } else {
          let result = nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(innerResult)")
          return result
        }
      }

      if case .pointer = inner.type {
        let result = nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(innerResult)")
        return result
      }

      // Default scalar cast.
      let result = nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(innerResult)")
      return result

    case .blockExpression(let statements, let finalExpr, _):
      return generateBlockScope(statements, finalExpr: finalExpr)

    case .arithmeticExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let cType = cTypeName(type)
      if type.isIntegerType {
        let funcName = checkedArithmeticFuncName(op: op, type: type)
        let result = nextTempWithInit(cType: cType, initExpr: "\(funcName)(\(leftResult), \(rightResult))")
        return result
      } else {
        let result = nextTempWithInit(cType: cType, initExpr: "\(leftResult) \(arithmeticOpToC(op)) \(rightResult)")
        return result
      }

    case .wrappingArithmeticExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let cType = cTypeName(type)
      let funcName = wrappingArithmeticFuncName(op: op, type: type)
      let result = nextTempWithInit(cType: cType, initExpr: "\(funcName)(\(leftResult), \(rightResult))")
      return result

    case .wrappingShiftExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let cType = cTypeName(type)
      let funcName = wrappingShiftFuncName(op: op, type: type)
      let result = nextTempWithInit(cType: cType, initExpr: "\(funcName)(\(leftResult), \(rightResult))")
      return result

    case .comparisonExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let cType = cTypeName(type)
      let result = nextTempWithInit(cType: cType, initExpr: "\(leftResult) \(comparisonOpToC(op)) \(rightResult)")
      return result

    case .letExpression(let identifier, let value, let body, let type):
      let valueVar = generateExpressionSSA(value)

      if type == .void {
        addIndent()
        buffer += "{\n"
        withIndent {
          pushScope()
          if identifier.type != .void {
            let cType = cTypeName(identifier.type)
            let cIdent = cIdentifier(for: identifier)
            addIndent()
            buffer += "\(cType) \(cIdent) = \(valueVar);\n"
            registerVariable(cIdent, identifier.type)
          }
          _ = generateExpressionSSA(body)
          popScope()
        }
        addIndent()
        buffer += "}\n"
        return ""
      }

      let resultVar = nextTempWithDecl(cType: cTypeName(type))
      addIndent()
      buffer += "{\n"
      withIndent {
        pushScope()
        if identifier.type != .void {
          let cType = cTypeName(identifier.type)
          let cIdent = cIdentifier(for: identifier)
          addIndent()
          buffer += "\(cType) \(cIdent) = \(valueVar);\n"
          registerVariable(cIdent, identifier.type)
        }

        let bodyResultVar = generateExpressionSSA(body)

        emitCopyOrMove(type: type, source: bodyResultVar, dest: resultVar, isLvalue: body.valueCategory == .lvalue)

        popScope()
      }
      addIndent()
      buffer += "}\n"

      return resultVar

    case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
      let conditionVar = generateExpressionSSA(condition)

      if type == .void || type == .never {
        // Push pool for void if/else — branches are mutually exclusive
        let savedBranchPoolVars = currentBranchPoolVars
        currentBranchPoolVars = []
        let poolInsertPos = pushTempPool()

        addIndent()
        buffer += "if (\(conditionVar)) {\n"
        withIndent {
          pushScope()
          _ = generateExpressionSSA(thenBranch)
          popScope()
        }
        if let elseBranch = elseBranch {
          // Release then-branch pool vars before else branch
          releaseBranchPoolVars()
          addIndent()
          buffer += "} else {\n"
          withIndent {
            pushScope()
            _ = generateExpressionSSA(elseBranch)
            popScope()
          }
        }
        releaseBranchPoolVars()
        popTempPool(insertAt: poolInsertPos)
        currentBranchPoolVars = savedBranchPoolVars

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
        
        // Push pool for non-void if/else — branches are mutually exclusive
        let savedBranchPoolVars = currentBranchPoolVars
        currentBranchPoolVars = []
        let poolInsertPos = pushTempPool()

        addIndent()
        buffer += "if (\(conditionVar)) {\n"
        withIndent {
          pushScope()
          let thenResult = generateExpressionSSA(thenBranch)
          if type != .never && thenBranch.type != .never {
              emitCopyOrMove(type: type, source: thenResult, dest: resultVar, isLvalue: thenBranch.valueCategory == .lvalue)
          }
          popScope()
        }
        // Release then-branch pool vars before else branch
        releaseBranchPoolVars()
        addIndent()
        buffer += "} else {\n"
        withIndent {
          pushScope()
          let elseResult = generateExpressionSSA(elseBranch)
          if type != .never && elseBranch.type != .never {
              emitCopyOrMove(type: type, source: elseResult, dest: resultVar, isLvalue: elseBranch.valueCategory == .lvalue)
          }
          popScope()
        }
        releaseBranchPoolVars()
        popTempPool(insertAt: poolInsertPos)
        currentBranchPoolVars = savedBranchPoolVars

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
    case .traitObjectConversion(let inner, let traitName, let traitTypeArgs, let concreteType, let type):
      return generateTraitObjectConversion(inner: inner, traitName: traitName, traitTypeArgs: traitTypeArgs, concreteType: concreteType, type: type)
    case .traitMethodCall(let receiver, let traitName, let methodName, let methodIndex, let arguments, let type):
      return generateTraitMethodCall(receiver: receiver, traitName: traitName, methodName: methodName, methodIndex: methodIndex, arguments: arguments, type: type)
    case .staticMethodCall:
      fatalError("Static method call should have been resolved by monomorphizer before code generation")
      
    case .unionConstruction(let type, let caseName, let args):
      return generateUnionConstructor(type: type, caseName: caseName, args: args)

    case .derefExpression(let inner, let type):
      let innerResult = generateExpressionSSA(inner)
      let cType = cTypeName(type)
      let result = nextTempWithDecl(cType: cType)
      // Always deep copy from the reference's pointee
      appendCopyAssignment(for: type, source: "*(\(cType)*)\(innerResult).ptr", dest: result, indent: indent)
      return result

    case .ptrExpression(let inner, let type):
      let (lvaluePath, _) = buildRefComponents(inner)
      let cType = cTypeName(type)
      let result = nextTempWithInit(cType: cType, initExpr: "&\(lvaluePath)")
      return result

    case .deptrExpression(let inner, let type):
      let ptrValue = generateExpressionSSA(inner)
      return emitPointerReadCopy(pointerExpr: ptrValue, elementType: type)

    case .referenceExpression(let inner, let type):
      // 使用逃逸分析决定分配策略。
      // Pattern 绑定别名（match/if-is/while-is）没有独立可寻址栈槽；
      // 对它们走栈借用路径会构造出错误的 lvalue/control 组件。
      // 因此别名变量的 ref 一律堆分配并按值复制，避免悬垂/非法地址。
      let isPatternAliasRef: Bool = {
        if case .variable(let identifier) = inner {
          let cName = cIdentifier(for: identifier)
          return patternBindingAliases[cName] != nil
        }
        return false
      }()
      // Lambda-captured variables are accessed through stable pointers in the env struct,
      // so they are always addressable and should use stack allocation (take address).
      let isCapturedVar: Bool = {
        if case .variable(let identifier) = inner {
          return capturedVarAliases[identifier.defId.id] != nil
        }
        return false
      }()
      let shouldHeapAllocate = isPatternAliasRef || (!isCapturedVar && escapeContext.shouldUseHeapAllocation(inner))
      
      if inner.valueCategory == .lvalue && !shouldHeapAllocate {
        // 不逃逸的 lvalue：栈分配（取地址）
        let (lvaluePath, controlPath) = buildRefComponents(inner)
        let cType = cTypeName(type)
        let result = nextTempWithDecl(cType: cType)
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
        let innerType = inner.type
        let innerCType = cTypeName(innerType)
        let refCType = cTypeName(type)
        let result = nextTempWithDecl(cType: refCType)

        // 1. 分配数据内存
        addIndent()
        buffer += "\(result).ptr = malloc(sizeof(\(innerCType)));\n"

        // 2. 初始化数据 — always copy into heap (heap allocation takes ownership)
        appendCopyAssignment(for: innerType, source: innerResult, dest: "*(\(innerCType)*)\(result).ptr", indent: indent)

        // 3. 分配控制块
        addIndent()
        buffer += "\(result).control = malloc(sizeof(struct Koral_Control));\n"
        addIndent()
        buffer += "((struct Koral_Control*)\(result).control)->strong_count = 1;\n"
        addIndent()
        buffer += "((struct Koral_Control*)\(result).control)->weak_count = 1;\n"
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
      // Push a dedicated scope for the subject so its lifetime is self-contained.
      // return/break/continue will clean it up via emitCleanup since it's on the stack.
      pushScope()
      
      let subjectVarSSA = generateExpressionSSA(subject)
      if needsDrop(subject.type) && subject.valueCategory == .rvalue {
        registerVariable(subjectVarSSA, subject.type)
      }
      var subjectVar = subjectVarSSA
      var subjectType = subject.type
      if case .reference(let inner) = subject.type {
        let innerCType = cTypeName(inner)
        let derefPtr = nextTemp() + "_deref"
        addIndent()
        buffer += "const \(innerCType)* \(derefPtr) = (const \(innerCType)*)\(subjectVarSSA).ptr;\n"
        subjectVar = "(*\(derefPtr))"
        subjectType = inner
      }
      
      let savedAliases = patternBindingAliases
      
      // Generate pattern matching condition and bindings
      let (prelude, preludeVars, condition, bindingCode, vars) = 
          generatePatternConditionAndBindings(pattern, subjectVar, subjectType)
      
      // Output prelude
      for p in prelude {
        addIndent()
        buffer += p
      }
      for (name, varType) in preludeVars {
        registerVariable(name, varType)
      }
      
      if type == .void || type == .never {
        // Push pool for if-pattern branches
        let savedBranchPoolVars = currentBranchPoolVars
        currentBranchPoolVars = []
        let poolInsertPos = pushTempPool()

        addIndent()
        buffer += "if (\(condition)) {\n"
        withIndent {
          pushScope()
          for b in bindingCode {
            addIndent()
            buffer += b
          }
          for (name, varType) in vars {
            registerVariable(name, varType)
          }
          _ = generateExpressionSSA(thenBranch)
          popScope()
        }
        if let elseBranch = elseBranch {
          releaseBranchPoolVars()
          addIndent()
          buffer += "} else {\n"
          withIndent {
            pushScope()
            _ = generateExpressionSSA(elseBranch)
            popScope()
          }
        }
        releaseBranchPoolVars()
        popTempPool(insertAt: poolInsertPos)
        currentBranchPoolVars = savedBranchPoolVars

        addIndent()
        buffer += "}\n"
        patternBindingAliases = savedAliases
        // Pop the subject scope — drops the subject right after the if-pattern.
        popScope()
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
        
        // Push pool for if-pattern branches
        let savedBranchPoolVars = currentBranchPoolVars
        currentBranchPoolVars = []
        let poolInsertPos = pushTempPool()

        addIndent()
        buffer += "if (\(condition)) {\n"
        withIndent {
          pushScope()
          for b in bindingCode {
            addIndent()
            buffer += b
          }
          for (name, varType) in vars {
            registerVariable(name, varType)
          }
          let thenResult = generateExpressionSSA(thenBranch)
          if type != .never && thenBranch.type != .never {
            emitCopyOrMove(type: type, source: thenResult, dest: resultVar, isLvalue: thenBranch.valueCategory == .lvalue)
          }
          popScope()
        }
        releaseBranchPoolVars()
        addIndent()
        buffer += "} else {\n"
        withIndent {
          pushScope()
          let elseResult = generateExpressionSSA(elseBranch)
          if type != .never && elseBranch.type != .never {
            emitCopyOrMove(type: type, source: elseResult, dest: resultVar, isLvalue: elseBranch.valueCategory == .lvalue)
          }
          popScope()
        }
        releaseBranchPoolVars()
        popTempPool(insertAt: poolInsertPos)
        currentBranchPoolVars = savedBranchPoolVars

        addIndent()
        buffer += "}\n"
        patternBindingAliases = savedAliases
        // Pop the subject scope — drops the subject right after the if-pattern.
        popScope()
        return resultVar
      }
      
    case .whilePatternExpression(let subject, let pattern, _, let body, _):
      let labelPrefix = nextTemp()
      let startLabel = "\(labelPrefix)_start"
      let endLabel = "\(labelPrefix)_end"
      
      addIndent()
      buffer += "\(startLabel): {\n"
      withIndent {
        // Borrow semantics: subject is evaluated each iteration but not deep-copied.
        // Pattern bindings are aliases into the subject's fields.
        
        // Push a scope for the subject so break/continue/return will drop it.
        let subjectScopeIndex = lifetimeScopeStack.count
        pushScope()
        
        let subjectVarSSA = generateExpressionSSA(subject)
        
        if needsDrop(subject.type) && subject.valueCategory == .rvalue {
          registerVariable(subjectVarSSA, subject.type)
        }
        
        var subjectVar = subjectVarSSA
        var subjectType = subject.type
        if case .reference(let inner) = subject.type {
          let innerCType = cTypeName(inner)
          let derefPtr = nextTemp() + "_deref"
          addIndent()
          buffer += "const \(innerCType)* \(derefPtr) = (const \(innerCType)*)\(subjectVarSSA).ptr;\n"
          subjectVar = "(*\(derefPtr))"
          subjectType = inner
        }
        
        let savedAliases = patternBindingAliases
        
        // Generate pattern matching condition and bindings
        let (prelude, preludeVars, condition, bindingCode, vars) = 
            generatePatternConditionAndBindings(pattern, subjectVar, subjectType)
        
        // Output prelude
        for p in prelude {
          addIndent()
          buffer += p
        }
        for (name, varType) in preludeVars {
          registerVariable(name, varType)
        }
        
        // When pattern doesn't match, drop subject and exit loop
        addIndent()
        buffer += "if (!(\(condition))) {\n"
        withIndent {
          emitCleanupForScope(at: subjectScopeIndex)
          addIndent()
          buffer += "goto \(endLabel);\n"
        }
        addIndent()
        buffer += "}\n"
        
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
        
        loopStack.append(LoopContext(startLabel: startLabel, endLabel: endLabel, scopeIndex: subjectScopeIndex))
        _ = generateExpressionSSA(body)
        loopStack.removeLast()
        popScope()
        // Drop subject at end of each iteration
        emitCleanupForScope(at: subjectScopeIndex)
        popScopeWithoutCleanup()
        patternBindingAliases = savedAliases
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
      let result = nextTempWithDecl(cType: "_Bool")
      let leftResult = generateExpressionSSA(left)
      let endLabel = nextTemp()
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
      let result = nextTempWithDecl(cType: "_Bool")
      let leftResult = generateExpressionSSA(left)
      let endLabel = nextTemp()
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
      let result = nextTempWithInit(cType: "_Bool", initExpr: "!\(exprResult)")
      return result

    case .bitwiseExpression(let left, let op, let right, let type):
      let leftResult = generateExpressionSSA(left)
      let rightResult = generateExpressionSSA(right)
      let cType = cTypeName(type)
      if (op == .shiftLeft || op == .shiftRight) && type.isIntegerType {
        let funcName = checkedShiftFuncName(op: op, type: type)
        let result = nextTempWithInit(cType: cType, initExpr: "\(funcName)(\(leftResult), \(rightResult))")
        return result
      } else {
        let result = nextTempWithInit(cType: cType, initExpr: "\(leftResult) \(bitwiseOpToC(op)) \(rightResult)")
        return result
      }

    case .bitwiseNotExpression(let expr, let type):
      let exprResult = generateExpressionSSA(expr)
      let cType = cTypeName(type)
      let result = nextTempWithInit(cType: cType, initExpr: "~\(exprResult)")
      return result

    case .typeConstruction(let identifier, _, let arguments, _):
      var argResults: [String] = []
      
      // Get canonical members to check for casts
      let canonicalMembers: [(name: String, type: Type, mutable: Bool, access: AccessModifier)]
      if case .structure(let defId) = identifier.type.canonical {
        canonicalMembers = context.getStructMembers(defId) ?? []
      } else {
        canonicalMembers = []
      }
      
      for (index, arg) in arguments.enumerated() {
        let argResult = generateExpressionSSA(arg)
        var finalArg = argResult

        if needsDrop(arg.type) {
          // Struct construction takes ownership of all droppable args.
          // For struct/union: create a temp with copy-or-move semantics.
          // For reference: always retain (struct takes ownership).
          // For function/weakReference: retain only if lvalue.
          if case .reference(_) = arg.type {
            // Reference args: retain only if lvalue (lvalue still holds original ref).
            // For rvalue, ownership transfers directly — no retain needed.
            if arg.valueCategory == .lvalue {
              addIndent()
              buffer += "__koral_retain(\(argResult).control);\n"
            }
            finalArg = argResult
          } else {
            let argCopy = emitTempCopyOrMove(type: arg.type, source: argResult, isLvalue: arg.valueCategory == .lvalue)
            finalArg = argCopy
          }
        }
        
        // Check for cast
        if index < canonicalMembers.count {
            let canonicalType = canonicalMembers[index].type
            if canonicalType != arg.type {
                let targetCType = cTypeName(canonicalType)
                finalArg = "*(\(targetCType)*)&(\(finalArg))"
            }
        }
        
        argResults.append(finalArg)
      }

      let cType = cTypeName(identifier.type)
      let result = nextTempWithInit(cType: cType, initExpr: "{\(argResults.joined(separator: ", "))}")
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
      let cType = cTypeName(type)
      let result = nextTempWithDecl(cType: cType)
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
      let result = nextTempWithDecl(cType: "int")
      let controlPath = "\(valRes).control"
      addIndent()
      buffer += "\(result) = 0;\n"
      addIndent()
      buffer += "if (\(controlPath)) {\n"
      withIndent {
        addIndent()
        buffer += "\(result) = atomic_load(&((struct Koral_Control*)\(controlPath))->strong_count);\n"
      }
      addIndent()
      buffer += "}\n"
      return result

    case .downgradeRef(let val, _):
      let valRes = generateExpressionSSA(val)
      // Check if this is a trait object downgrade (TraitRef → TraitWeakRef)
      if case .reference(let inner) = val.type, case .traitObject = inner {
        let result = nextTempWithDecl(cType: "struct TraitWeakRef")
        let tempWeak = nextTempWithDecl(cType: "struct WeakRef")
        addIndent()
        buffer += "\(tempWeak) = __koral_downgrade_ref((struct Ref){\(valRes).ptr, \(valRes).control});\n"
        addIndent()
        buffer += "\(result).control = \(tempWeak).control;\n"
        addIndent()
        buffer += "\(result).vtable = \(valRes).vtable;\n"
        return result
      } else {
        let result = nextTempWithInit(cType: "struct WeakRef", initExpr: "__koral_downgrade_ref(\(valRes))")
        return result
      }

    case .upgradeRef(let val, let resultType):
      let valRes = generateExpressionSSA(val)
      let successVar = nextTempWithDecl(cType: "int")
      // Check if this is a trait object upgrade (TraitWeakRef → Option<TraitRef>)
      if case .weakReference(let inner) = val.type, case .traitObject = inner {
        let upgradedRefVar = nextTempWithInit(cType: "struct Ref", initExpr: "__koral_upgrade_ref((struct WeakRef){\(valRes).control}, &\(successVar))")
        // Generate Option type result
        let cType = cTypeName(resultType)
        let result = nextTempWithDecl(cType: cType)
        addIndent()
        buffer += "if (\(successVar)) {\n"
        withIndent {
          addIndent()
          buffer += "\(result).tag = 1; // Some\n"
          addIndent()
          buffer += "\(result).data.Some.value.ptr = \(upgradedRefVar).ptr;\n"
          addIndent()
          buffer += "\(result).data.Some.value.control = \(upgradedRefVar).control;\n"
          addIndent()
          buffer += "\(result).data.Some.value.vtable = \(valRes).vtable;\n"
        }
        addIndent()
        buffer += "} else {\n"
        withIndent {
          addIndent()
          buffer += "\(result).tag = 0; // None\n"
        }
        addIndent()
        buffer += "}\n"
        return result
      } else {
        let upgradedRefVar = nextTempWithInit(cType: "struct Ref", initExpr: "__koral_upgrade_ref(\(valRes), &\(successVar))")
        // Generate Option type result
        let cType = cTypeName(resultType)
        let result = nextTempWithDecl(cType: cType)
        addIndent()
        buffer += "if (\(successVar)) {\n"
        withIndent {
          addIndent()
          buffer += "\(result).tag = 1; // Some\n"
          addIndent()
          buffer += "\(result).data.Some.value = \(upgradedRefVar);\n"
        }
        addIndent()
        buffer += "} else {\n"
        withIndent {
          addIndent()
          buffer += "\(result).tag = 0; // None\n"
        }
        addIndent()
        buffer += "}\n"
        return result
      }

    case .initMemory(let ptr, let val):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let v = generateExpressionSSA(val)
      let cType = cTypeName(element)
      if case .reference(let inner) = element {
        // Reference types need special handling for TraitObject vs regular Ref
        addIndent()
        if case .traitObject = inner {
          buffer += "*(\(cType)*)\(p) = \(v);\n"
          addIndent()
          buffer += "__koral_retain(((\(cType)*)\(p))->ref.control);\n"
        } else {
          buffer += "*(struct Ref*)\(p) = \(v);\n"
          addIndent()
          buffer += "__koral_retain(((struct Ref*)\(p))->control);\n"
        }
      } else {
        // For all other types, use appendCopyAssignment which handles
        // struct (_copy), union (_copy), function (closure_retain), weakReference (weak_retain), primitives (plain =)
        appendCopyAssignment(for: element, source: v, dest: "*(\(cType)*)\(p)", indent: indent)
      }
      return ""

    case .deinitMemory(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      if case .reference(let inner) = element {
        let cType = cTypeName(element)
        if case .traitObject = inner {
          addIndent()
          buffer += "__koral_release(((\(cType)*)\(p))->ref.control);\n"
        } else {
          addIndent()
          buffer += "__koral_release(((struct Ref*)\(p))->control);\n"
        }
      } else if case .structure(let defId) = element {
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        addIndent()
        buffer += "__koral_\(typeName)_drop(\(p));\n"
      } else if case .union(let defId) = element {
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
        addIndent()
        buffer += "__koral_\(typeName)_drop(\(p));\n"
      } else if case .function = element {
        addIndent()
        buffer += "__koral_closure_release(*(struct __koral_Closure*)\(p));\n"
      } else if case .weakReference(_) = element {
        let cType = cTypeName(element)
        addIndent()
        buffer += "__koral_weak_release(((\(cType)*)\(p))->control);\n"
      }
      // int/float/bool/void -> noop
      return ""

    case .takeMemory(let ptr):
      guard case .pointer(let element) = ptr.type else { fatalError() }
      let p = generateExpressionSSA(ptr)
      let cType = cTypeName(element)
      let result = nextTempWithInit(cType: cType, initExpr: "*(\(cType)*)\(p)")
      return result

    case .nullPtr(let resultType):
      let result = nextTempWithInit(cType: cTypeName(resultType), initExpr: "NULL")
      return result

    }
  }


  func nextTemp() -> String {
    tempVarCounter += 1
    return "_t\(tempVarCounter)"
  }

  // MARK: - Pool-Aware Temp Allocation

  /// Allocate a temporary variable from the active pool (if any) for the given C type.
  /// If no pool is active, falls back to the standard nextTemp().
  /// Pool-allocated variables are tracked in currentBranchPoolVars for branch-end release.
  func nextPoolTemp(cType: String) -> String {
    guard !tempPoolStack.isEmpty else {
      return nextTemp()
    }
    let name = tempPoolStack[tempPoolStack.count - 1].acquire(cType: cType)
    currentBranchPoolVars.append((name: name, cType: cType))
    return name
  }

  /// Allocate a temp variable and emit its declaration.
  /// When a pool is active, allocates from the pool (declaration is deferred to pool scope).
  /// When no pool is active, allocates a fresh temp and emits `cType name;` inline.
  /// Returns the variable name.
  func nextTempWithDecl(cType: String) -> String {
    if !tempPoolStack.isEmpty {
      return nextPoolTemp(cType: cType)
    }
    let name = nextTemp()
    addIndent()
    buffer += "\(cType) \(name);\n"
    return name
  }

  /// Allocate a temp and emit `cType name = initExpr;` (or just `name = initExpr;` if pooled).
  /// Returns the variable name.
  func nextTempWithInit(cType: String, initExpr: String) -> String {
    if !tempPoolStack.isEmpty {
      let name = nextPoolTemp(cType: cType)
      addIndent()
      // Brace-enclosed initializer lists are only valid in declarations in C.
      // For assignment to a pre-declared pool variable, wrap as a compound literal.
      if initExpr.hasPrefix("{") {
        buffer += "\(name) = (\(cType))\(initExpr);\n"
      } else {
        buffer += "\(name) = \(initExpr);\n"
      }
      return name
    }
    let name = nextTemp()
    addIndent()
    buffer += "\(cType) \(name) = \(initExpr);\n"
    return name
  }

  /// Push a new temp pool for a match/if-else expression.
  /// Returns a placeholder position in the buffer where declarations will be inserted.
  func pushTempPool() -> Int {
    tempPoolPrefixCounter += 1
    let pool = TempPool(prefix: "\(tempPoolPrefixCounter)")
    tempPoolStack.append(pool)
    // Return current buffer length as the insertion point for declarations
    return buffer.count
  }

  /// Release all pool variables acquired in the current branch back to the pool.
  func releaseBranchPoolVars() {
    guard !tempPoolStack.isEmpty else { return }
    tempPoolStack[tempPoolStack.count - 1].releaseAll(currentBranchPoolVars)
    currentBranchPoolVars = []
  }

  /// Pop the current temp pool and insert declarations at the given buffer position.
  func popTempPool(insertAt position: Int) {
    guard let pool = tempPoolStack.popLast() else { return }
    guard !pool.declared.isEmpty else { return }
    // Build declaration block
    var decls = ""
    for (cType, name) in pool.declared {
      decls += "\(indent)\(cType) \(name);\n"
    }
    // Insert at the saved position
    let insertIndex = buffer.index(buffer.startIndex, offsetBy: position)
    buffer.insert(contentsOf: decls, at: insertIndex)
  }

  func generateStatement(_ stmt: TypedStatementNode) {
    switch stmt {
    case .variableDeclaration(let identifier, let value, _):
      let valueResult = generateExpressionSSA(value)
      // void/never 类型的值不能赋给变量
      if value.type != .void && value.type != .never {
        let cIdent = cIdentifier(for: identifier)
        emitDeclareAndCopyOrMove(type: identifier.type, source: valueResult, dest: cIdent, isLvalue: value.valueCategory == .lvalue)
        registerVariable(cIdent, identifier.type)
      }
    case .assignment(let target, let op, let value):
      if let op {
        let (lhsPath, _) = buildRefComponents(target)
        let valueResult = generateExpressionSSA(value)

        // For shift compound assignments on integer types, use checked shift functions
        if (op == .shiftLeft || op == .shiftRight) && target.type.isIntegerType {
          let bitwiseOp: BitwiseOperator = op == .shiftLeft ? .shiftLeft : .shiftRight
          let funcName = checkedShiftFuncName(op: bitwiseOp, type: target.type)
          addIndent()
          buffer += "\(lhsPath) = \(funcName)(\(lhsPath), \(valueResult));\n"
        } else {
          let opStr = compoundOpToC(op)
          addIndent()
          buffer += "\(lhsPath) \(opStr) \(valueResult);\n"
        }
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

        emitCopyOrMove(type: target.type, source: valueResult, dest: lhsPath, isLvalue: value.valueCategory == .lvalue)
      }

    case .deptrAssignment(let pointer, let op, let value):
      guard case .pointer(let elementType) = pointer.type else { fatalError() }
      let ptrValue = generateExpressionSSA(pointer)

      if let op {
        let oldValue = emitPointerReadCopy(pointerExpr: ptrValue, elementType: elementType)
        let rhsValue = generateExpressionSSA(value)
        let cType = cTypeName(elementType)
        // For shift compound assignments on integer types, use checked shift functions
        let newValue: String
        if (op == .shiftLeft || op == .shiftRight) && elementType.isIntegerType {
          let bitwiseOp: BitwiseOperator = op == .shiftLeft ? .shiftLeft : .shiftRight
          let funcName = checkedShiftFuncName(op: bitwiseOp, type: elementType)
          newValue = nextTempWithInit(cType: cType, initExpr: "\(funcName)(\(oldValue), \(rhsValue))")
        } else {
          newValue = nextTempWithInit(cType: cType, initExpr: "\(oldValue) \(compoundOpToC(op).dropLast()) \(rhsValue)")
        }

        appendDropStatement(for: elementType, value: "(*\(ptrValue))")
        appendCopyAssignment(for: elementType, source: newValue, dest: "(*\(ptrValue))")
      } else {
        let valueResult = generateExpressionSSA(value)
        appendDropStatement(for: elementType, value: "(*\(ptrValue))")
        appendCopyAssignment(for: elementType, source: valueResult, dest: "(*\(ptrValue))")
      }
      
    case .expression(let expr):
      let result = generateExpressionSSA(expr)
      if expr.valueCategory == .rvalue && needsDrop(expr.type) && !result.isEmpty {
        appendDropStatement(for: expr.type, value: result, indent: indent)
      }

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

        emitDeclareAndCopyOrMove(type: value.type, source: valueResult, dest: retVar, isLvalue: value.valueCategory == .lvalue)

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

  // MARK: - Unified Copy/Move Helpers
  //
  // These helpers eliminate duplicated inline copy logic across CodeGen.
  // Use these instead of manually switching on type for copy/retain patterns.

  /// Emit `dest = source` with proper copy semantics.
  /// If `isLvalue` is true, generates a deep copy (struct/union _copy, ref retain, closure retain, weak retain).
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
  /// Pool-aware: when a pool is active, allocates from the pool (declaration deferred).
  /// Returns the temp variable name.
  func emitTempCopyOrMove(type: Type, source: String, isLvalue: Bool) -> String {
    if !tempPoolStack.isEmpty {
      let cType = cTypeName(type)
      let temp = nextPoolTemp(cType: cType)
      emitCopyOrMove(type: type, source: source, dest: temp, isLvalue: isLvalue)
      return temp
    }
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
    case .union(let defId):
      let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "U_\(defId.id)"
      return "\(dest) = __koral_\(typeName)_copy(&\(source));\n"
    case .reference:
      return "\(dest) = \(source);\n__koral_retain(\(dest).control);\n"
    case .weakReference:
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
  
  // MARK: - 逃逸分析辅助函数
  
  /// 检查表达式是否是结构体字段赋值
  func isStructFieldAssignment(_ target: TypedExpressionNode) -> Bool {
    switch target {
    case .memberPath(let source, let path):
      // 如果路径长度 > 0，说明是字段访问
      if !path.isEmpty {
        let typeToCheck: Type
        switch source.type {
        case .reference(let inner), .pointer(let inner):
          typeToCheck = inner
        default:
          typeToCheck = source.type
        }
        switch typeToCheck {
        case .structure(_), .union(_):
          return true
        default:
          return false
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
    // Push a dedicated scope for the subject so its lifetime is self-contained.
    // return/break/continue will clean it up via emitCleanup since it's on the stack.
    pushScope()
    
    let subjectVarSSA = generateExpressionSSA(subject)
    
    if needsDrop(subject.type) && subject.valueCategory == .rvalue {
      registerVariable(subjectVarSSA, subject.type)
    }
    
    let resultVar = nextTemp()
    
    if type != .void && type != .never {
        addIndent()
        buffer += "\(cTypeName(type)) \(resultVar);\n"
    }
    
    // Borrow semantics: the subject is not copied. Pattern bindings are aliases
    // into the subject's fields. The subject must remain valid for the entire match.
    var subjectVar = subjectVarSSA
    var subjectType = subject.type
    if case .reference(let inner) = subject.type {
        // Dereference: create a pointer to the inner value (no deep copy)
        let innerCType = cTypeName(inner)
        let derefPtr = nextTemp() + "_deref"
        addIndent()
        buffer += "const \(innerCType)* \(derefPtr) = (const \(innerCType)*)\(subjectVarSSA).ptr;\n"
        subjectVar = "(*\(derefPtr))"
        subjectType = inner
    }
    
    let endLabel = "match_end_\(nextTemp())"
    let savedAliases = patternBindingAliases

    // Push a temp pool for stack slot reuse across mutually exclusive branches.
    // Save and clear branch pool vars so nested pools don't interfere.
    let savedBranchPoolVars = currentBranchPoolVars
    currentBranchPoolVars = []
    let poolInsertPos = pushTempPool()
    
    for c in cases {
         patternBindingAliases = savedAliases
         // Reset branch pool vars: release all temps from previous branch back to pool
         releaseBranchPoolVars()

         addIndent()
         buffer += "{\n"
         withIndent {
         let caseScopeIndex = lifetimeScopeStack.count
         pushScope()

         let (prelude, preludeVars, condition, bindings, vars) = generatePatternConditionAndBindings(c.pattern, subjectVar, subjectType)

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
             emitCopyOrMove(type: type, source: bodyResult, dest: resultVar, isLvalue: c.body.valueCategory == .lvalue)
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
    
    // Release any remaining branch pool vars and pop the pool,
    // inserting declarations at the saved position.
    releaseBranchPoolVars()
    popTempPool(insertAt: poolInsertPos)
    currentBranchPoolVars = savedBranchPoolVars

    patternBindingAliases = savedAliases

    addIndent()
    buffer += "\(endLabel):;\n"
    // Pop the subject scope — drops the subject right after the match expression.
    popScope()
    return (type == .void || type == .never) ? "" : resultVar
  }

    /// 生成模式匹配的条件和绑定代码（使用拷贝语义）
    func generatePatternConditionAndBindings(
    _ pattern: TypedPattern,
    _ path: String,
    _ type: Type
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
        // Compare via `String.equals(self, other String) Bool`.
        // Value-passing semantics: String_equals consumes its arguments, so we must copy
        // both the subject and the literal before comparison to avoid double-free.
        guard case .structure(let defId) = type else { fatalError("String literal pattern requires String type") }
        // Use qualified name for String.equals via lookup
        let equalsMethod = lookupStaticMethod(typeName: "String", methodName: "equals")
        let typeName = cIdentifierByDefId[defIdKey(defId)] ?? context.getCIdentifier(defId) ?? "T_\(defId.id)"
        return ([prelude], [(literalVar, type)], "\(equalsMethod)(__koral_\(typeName)_copy(&\(path)), __koral_\(typeName)_copy(&\(literalVar)))", [], [])
      case .wildcard:
        return ([], [], "1", [], [])
      case .variable(let symbol):
        let name = cIdentifier(for: symbol)
        let varType = symbol.type
        if varType == .void {
          return ([], [], "1", [], [])
        }
        // Borrow semantics: register an alias from the bound variable name
        // to the subject's field path. No copy, no local variable declaration.
        // The alias is resolved in generateExpressionSSA(.variable).
        patternBindingAliases[name] = path
        return ([], [], "1", [], [])
          
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
               
           let (subPre, subPreVars, subCond, subBind, subVars) = generatePatternConditionAndBindings(subInd, subPath, paramType)
               
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
            generatePatternConditionAndBindings(left, path, type)
        let (rightPre, rightPreVars, rightCond, rightBind, rightVars) = 
            generatePatternConditionAndBindings(right, path, type)
        
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
            generatePatternConditionAndBindings(left, path, type)
        let (rightPre, rightPreVars, rightCond, rightBind, rightVars) = 
            generatePatternConditionAndBindings(right, path, type)
        
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
            generatePatternConditionAndBindings(pattern, path, type)
        
        let condition = "!(\(cond))"
        // Not patterns cannot have bindings (enforced by type checker)
        return (pre, preVars, condition, [], [])
        
      case .structPattern(_, let elements):
        // Struct pattern: direct field access, no tag check needed
        guard case .structure(let defId) = type else { fatalError("Struct pattern on non-struct type: \(type)") }
        let structMembers = context.getStructMembers(defId) ?? []
        
        var prelude: [String] = []
        var preludeVars: [(String, Type)] = []
        var condition = "1"
        var bindings: [String] = []
        var vars: [(String, Type)] = []
        
        for (i, subPattern) in elements.enumerated() {
          let fieldName = sanitizeCIdentifier(structMembers[i].name)
          let fieldType = structMembers[i].type
          let subPath = "\(path).\(fieldName)"
          
          let (subPre, subPreVars, subCond, subBind, subVars) =
              generatePatternConditionAndBindings(subPattern, subPath, fieldType)
          
          if subCond != "1" {
            condition += " && (\(subCond))"
          }
          prelude.append(contentsOf: subPre)
          preludeVars.append(contentsOf: subPreVars)
          bindings.append(contentsOf: subBind)
          vars.append(contentsOf: subVars)
        }
        
        return (prelude, preludeVars, condition, bindings, vars)
      }
    }


}

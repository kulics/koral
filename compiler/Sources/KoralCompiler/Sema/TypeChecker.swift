import Foundation

/// 全局节点的源信息
public struct GlobalNodeSourceInfo {
  /// 源文件路径（绝对路径）
  public let sourceFile: String
  /// 模块路径
  public let modulePath: [String]
  /// 全局节点
  public let node: GlobalNode
  
  public init(sourceFile: String, modulePath: [String], node: GlobalNode) {
    self.sourceFile = sourceFile
    self.modulePath = modulePath
    self.node = node
  }
}

public class TypeChecker {
  // Store type information for variables and functions
  // Note: internal access for extension methods in TypeCheckerTypeResolution.swift
  var currentScope: UnifiedScope = UnifiedScope()
  let ast: ASTNode
  // TypeName -> MethodName -> MethodSymbol
  var extensionMethods: [String: [String: Symbol]] = [:]

  var traits: [String: TraitDeclInfo] = [:]
  
  // Cache for object safety check results to avoid redundant computation
  var objectSafetyCache: [String: (Bool, [String])] = [:]
  
  // Cache for flattened trait methods to avoid redundant traversal of trait hierarchies
  var flattenedTraitMethodsCache: [String: [String: TraitMethodSignature]] = [:]
  
  // Cache for trait conformance checks: (typeDescription, traitName) -> passed
  // Avoids redundant method lookups for the same type/trait pair
  var traitConformanceCache: [String: Bool] = [:]
  
  // Cache for validated generic constraint checks: "Template<Arg1,Arg2>" -> passed
  var genericConstraintCache: Set<String> = []

  // When true, generic constraints on type nodes are not enforced during signature collection.
  // This avoids order-dependent false negatives across modules/submodules.
  var deferGenericConstraintValidation: Bool = false

  // Generic parameter name -> list of trait constraints currently in scope
  // Stores full TraitConstraint to preserve type arguments for generic traits
  var genericTraitBounds: [String: [TraitConstraint]] = [:]

  // Generic Template Extensions: TemplateName -> [GenericExtensionMethodTemplate]
  var genericExtensionMethods: [String: [GenericExtensionMethodTemplate]] = [:]
  var genericIntrinsicExtensionMethods:
    [String: [(typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)]] =
      [:]

  // Instantiation requests collected during type checking (for deferred monomorphization)
  var instantiationRequests: Set<InstantiationRequest> = []
  
  // Stack of generic types currently being resolved (for recursion detection)
  var resolvingGenericTypes: Set<String> = []
  
  // Set of type aliases currently being resolved (for circular alias detection)
  var resolvingTypeAliases: Set<String> = []
  
  // Sets to track intrinsic generic types and functions for special handling during monomorphization
  var intrinsicGenericTypes: Set<String> = []
  var intrinsicGenericFunctions: Set<String> = []
  
  // Set to track types defined in the standard library (for given declaration module rules)
  var stdLibTypes: Set<String> = []

  // Cache normalized source lines for diagnostic span heuristics.
  // Key: absolute source file path.
  var sourceLinesCache: [String: [String]] = [:]

  // When true, attempt one-time call-site recovery for the next inferred call.
  // This is enabled only in high-risk contexts (e.g. block final expressions)
  // to avoid paying scanning cost on all calls.
  var shouldRecoverCallSiteOnce: Bool = false

  var currentSpan: SourceSpan = .unknown {
    didSet {
      SemanticErrorContext.updateSpan(currentSpan)
    }
  }
  
  // Computed property for accessing line number from currentSpan
  // Note: internal access for extension methods
  var currentLine: Int {
    get { currentSpan.start.line }
    set { currentSpan = SourceSpan(location: SourceLocation(line: newValue, column: 1)) }
  }
  
  var currentFileName: String {
    didSet {
      SemanticErrorContext.currentFileName = currentFileName
    }
  }

  // File mapping for diagnostics (since stdlib globals are prepended)
  let coreGlobalCount: Int
  let coreFileName: String
  let userFileName: String
  var currentFunctionReturnType: Type?
  var loopDepth: Int = 0
  var insideDefer: Bool = false

  var synthesizedTempIndex: Int = 0
  
  // MARK: - Diagnostic Collection
  
  /// 诊断收集器 - 收集所有诊断信息而不是在第一个错误时停止
  /// **Validates: Requirements 9.1, 9.2, 9.4**
  var diagnosticCollector = DiagnosticCollector()
  
  /// 是否启用错误收集模式（而不是立即抛出）
  /// 当为 true 时，错误会被收集到 diagnosticCollector 中
  /// 当为 false 时，保持原有的抛出行为
  var collectErrors: Bool = false
  
  /// 记录错误到诊断收集器
  /// - Parameters:
  ///   - message: 错误消息
  ///   - span: 源代码位置
  ///   - isPrimary: 是否是主要错误
  func recordError(_ message: String, at span: SourceSpan, isPrimary: Bool = true) {
    diagnosticCollector.error(
      message,
      at: span,
      fileName: currentFileName,
      isPrimary: isPrimary
    )
  }
  
  /// 记录错误到诊断收集器（使用当前位置）
  func recordError(_ message: String, isPrimary: Bool = true) {
    recordError(message, at: currentSpan, isPrimary: isPrimary)
  }
  
  /// 记录 SemanticError 到诊断收集器
  func recordSemanticError(_ error: SemanticError, isPrimary: Bool = true) {
    diagnosticCollector.addSemanticError(error, isPrimary: isPrimary)
  }
  
  /// 记录警告到诊断收集器
  func recordWarning(_ message: String, at span: SourceSpan) {
    diagnosticCollector.warning(
      message,
      at: span,
      fileName: currentFileName
    )
  }
  
  /// 记录警告到诊断收集器（使用当前位置）
  func recordWarning(_ message: String) {
    recordWarning(message, at: currentSpan)
  }
  
  /// 记录次要错误（由其他错误引起的）
  /// - Parameters:
  ///   - message: 错误消息
  ///   - span: 源代码位置
  ///   - causedBy: 引起此错误的主要错误描述
  func recordSecondaryError(_ message: String, at span: SourceSpan, causedBy: String? = nil) {
    diagnosticCollector.secondaryError(
      message,
      at: span,
      fileName: currentFileName,
      causedBy: causedBy
    )
  }
  
  /// 记录次要错误（使用当前位置）
  func recordSecondaryError(_ message: String, causedBy: String? = nil) {
    recordSecondaryError(message, at: currentSpan, causedBy: causedBy)
  }
  
  /// 处理错误：根据 collectErrors 设置决定是收集还是抛出
  /// - Parameters:
  ///   - error: 要处理的错误
  ///   - isPrimary: 是否是主要错误
  /// - Throws: 如果 collectErrors 为 false，则抛出错误
  func handleError(_ error: SemanticError, isPrimary: Bool = true) throws {
    if collectErrors {
      recordSemanticError(error, isPrimary: isPrimary)
    } else {
      throw error
    }
  }
  
  /// 处理错误：根据 collectErrors 设置决定是收集还是抛出
  /// - Parameters:
  ///   - message: 错误消息
  ///   - span: 源代码位置
  ///   - isPrimary: 是否是主要错误
  /// - Throws: 如果 collectErrors 为 false，则抛出错误
  func handleError(_ message: String, at span: SourceSpan, isPrimary: Bool = true) throws {
    if collectErrors {
      recordError(message, at: span, isPrimary: isPrimary)
    } else {
      throw SemanticError(.generic(message), span: span)
    }
  }
  
  /// 检查是否有收集到的错误
  var hasCollectedErrors: Bool {
    return diagnosticCollector.hasErrors()
  }
  
  /// 获取所有收集到的诊断信息
  func getCollectedDiagnostics() -> [Diagnostic] {
    return diagnosticCollector.getDiagnostics()
  }
  
  /// 清空收集到的诊断信息
  func clearDiagnostics() {
    diagnosticCollector.clear()
  }
  
  // MARK: - Pass Architecture Support
  
  /// CompilerContext - 统一查询与更新上下文
  /// 包含 DefIdMap 与类型信息，避免依赖全局可变状态
  var context = CompilerContext()

  /// DefIdMap - 管理所有定义的标识符
  /// 用于为所有符号分配唯一的 DefId
  /// **Validates: Requirements 1.1, 8.1**
  var defIdMap: DefIdMap {
    get { context.defIdMap }
    set {
      context.setDefIdMap(newValue)
      currentScope.updateDefIdMap(newValue)
    }
  }

  
  /// NameCollector 的输出（Pass 1 结果）
  /// 包含 DefIdMap，用于后续 Pass 使用
  /// **Validates: Requirements 2.1, 2.2**
  var nameCollectorOutput: NameCollectorOutput?
  
  /// TypeResolver 的输出（Pass 2 结果）
  /// **Validates: Requirements 2.1, 2.2**
  var typeResolverOutput: TypeResolverOutput?
  
  /// BodyChecker 的输出（Pass 3 结果）
  /// 包含 TypedAST 和 InstantiationRequests，用于后续阶段使用
  /// **Validates: Requirements 2.1, 2.2**
  var bodyCheckerOutput: BodyCheckerOutput?
  
  // MARK: - Module System Support
  
  /// 全局节点的源信息映射（用于多文件项目）
  /// 键是节点在 declarations 数组中的索引
  var nodeSourceInfoMap: [Int: GlobalNodeSourceInfo] = [:]
  
  /// 当前正在处理的节点的源文件路径（绝对路径）
  var currentSourceFile: String = ""
  
  /// 当前正在处理的节点的模块路径
  var currentModulePath: [String] = []
  
  /// 模块导入图（用于可见性检查）
  var importGraph: ImportGraph? = nil
  
  /// 模块符号映射：模块路径 -> 模块符号信息
  /// 用于支持 `using self.child` 后通过 `child.xxx` 访问子模块符号
  var moduleSymbols: [String: ModuleSymbolInfo] = [:]
  
  /// 当前正在处理的声明是否来自标准库
  /// 基于声明索引判断：索引小于 coreGlobalCount 的声明来自标准库
  var isCurrentDeclStdLib: Bool = false
  
  /// 检查当前声明是否来自子模块
  /// 子模块的 modulePath 长度大于 1（根模块路径长度为 1，如 ["expr_eval"]）
  /// 子模块路径长度为 2+，如 ["expr_eval", "frontend"]
  var isCurrentDeclFromSubmodule: Bool {
    return currentModulePath.count > 1
  }
  
  /// 检查符号的模块是否可以从当前模块直接访问
  /// 允许访问的情况：
  /// 1. 符号与当前代码在同一模块（modulePath 相同）
  /// 2. 符号来自标准库根模块（modulePath 为 ["std"]）
  func isModuleAccessible(symbolModulePath: [String], currentModulePath: [String]) -> Bool {
    // 空路径总是可访问（局部变量/参数）
    if symbolModulePath.isEmpty {
      return true
    }
    
    // 同一模块
    if symbolModulePath == currentModulePath {
      return true
    }
    
    // 标准库根模块的符号总是可访问
    if symbolModulePath.count == 1 && symbolModulePath[0] == "std" {
      return true
    }
    
    return false
  }

  // MARK: - FFI Type Compatibility

  func isFfiCompatibleType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64,
         .uint, .uint8, .uint16, .uint32, .uint64,
         .float32, .float64, .bool, .void, .never:
      return true
    case .pointer:
      return true
    case .weakReference:
      return false
    case .opaque:
      return true
    case .structure, .union, .reference, .function, .genericParameter:
      return false
    case .genericStruct, .genericUnion, .module, .typeVariable:
      return false
    case .traitObject:
      return false
    }
  }

  func ffiTypeError(_ type: Type) -> String {
    switch type {
    case .structure:
      return "Koral struct types cannot be used in foreign functions"
    case .union:
      return "Koral union types cannot be used in foreign functions"
    case .reference:
      return "Reference types (ref) cannot be used in foreign functions"
    case .function:
      return "Function types cannot be used in foreign functions"
    case .genericParameter, .genericStruct, .genericUnion:
      return "Generic parameters cannot be used in foreign functions"
    default:
      return "Type '\(type)' is not compatible with FFI"
    }
  }
  
  /// 检查符号是否可以从当前位置直接访问（不需要模块前缀）
  /// 
  // MARK: - Visibility Checker
  
  /// 可见性检查器实例
  /// 用于检查符号和类型的模块可见性
  /// **Validates: Requirements 6.1, 6.2, 6.3, 6.5**
  lazy var visibilityChecker = VisibilityChecker(context: context)
  
  /// 检查符号是否可以从当前位置直接访问（不需要模块前缀）
  /// 
  /// 允许直接访问的情况：
  /// 1. 符号与当前代码在同一模块（modulePath 相同）
  /// 2. 符号来自父模块（符号的 modulePath 是当前 modulePath 的前缀）
  /// 3. 符号来自标准库（modulePath 为 ["std"] 或以 "std" 开头）
  /// 4. 符号是局部变量/参数（modulePath 为空）
  /// 
  /// 不允许直接访问的情况：
  /// 1. 符号来自子模块（需要通过 module.symbol 访问）
  /// 2. 符号来自兄弟模块（需要通过 module.symbol 访问）
  /// 3. 符号来自外部模块（需要通过 module.symbol 访问）
  func canAccessSymbolDirectly(symbolModulePath: [String], currentModulePath: [String], symbolName: String? = nil) -> Bool {
    return visibilityChecker.canAccessDirectly(
      symbolModulePath: symbolModulePath,
      currentModulePath: currentModulePath,
      currentSourceFile: currentSourceFile,
      symbolName: symbolName,
      importGraph: importGraph,
      isGenericParameter: false
    )
  }
  
  /// 获取访问符号所需的模块前缀
  /// 
  /// 例如：
  /// - 当前在 ["expr_eval"]，符号在 ["expr_eval", "frontend"]
  ///   返回 "frontend"
  /// - 当前在 ["expr_eval", "backend"]，符号在 ["expr_eval", "frontend"]
  ///   返回 "frontend"（通过 super.frontend 访问）
  /// - 当前在 ["expr_eval"]，符号在 ["other_module"]
  ///   返回 "other_module"
  func getRequiredModulePrefix(symbolModulePath: [String], currentModulePath: [String]) -> String {
    return visibilityChecker.getRequiredPrefix(
      symbolModulePath: symbolModulePath,
      currentModulePath: currentModulePath
    )
  }
  
  /// 检查类型的模块可见性
  /// 如果类型来自子模块或兄弟模块，需要使用模块前缀访问
  func checkTypeVisibility(type: Type, typeName: String) throws {
    // 局部类型绑定（如泛型替换、Self 绑定）不需要检查模块可见性
    let isLocalBinding = currentScope.isLocalTypeBinding(typeName)
    
    // 泛型参数不需要检查模块可见性
    let isGenericParameter = currentScope.isGenericParameter(typeName)
    
    do {
      try visibilityChecker.checkTypeVisibility(
        type: type,
        typeName: typeName,
        currentModulePath: currentModulePath,
        currentSourceFile: currentSourceFile,
        importGraph: importGraph,
        isLocalBinding: isLocalBinding,
        isGenericParameter: isGenericParameter
      )
    } catch let error as VisibilityError {
      // 转换 VisibilityError 为 SemanticError
      throw SemanticError(.generic(error.description), span: currentSpan)
    }
  }

  public init(
    ast: ASTNode,
    coreGlobalCount: Int = 0,
    coreFileName: String = "std/std.koral",
    userFileName: String = "<input>",
    importGraph: ImportGraph? = nil
  ) {
    self.ast = ast
    self.coreGlobalCount = max(0, coreGlobalCount)
    self.coreFileName = coreFileName
    self.userFileName = userFileName
    self.currentFileName = userFileName
    self.importGraph = importGraph
    SemanticErrorContext.currentFileName = userFileName
    
    SemanticErrorContext.currentCompilerContext = context
    self.currentScope = UnifiedScope(defIdMap: context.defIdMap)
  }
  
  /// 使用源信息初始化 TypeChecker（用于多文件项目）
  /// - Parameters:
  ///   - ast: AST 节点
  ///   - nodeSourceInfoList: 全局节点的源信息列表
  ///   - coreGlobalCount: 标准库全局节点数量
  ///   - coreFileName: 标准库文件名
  ///   - userFileName: 用户文件名（用于单文件模式的回退）
  public init(
    ast: ASTNode,
    nodeSourceInfoList: [GlobalNodeSourceInfo],
    coreGlobalCount: Int = 0,
    coreFileName: String = "std/std.koral",
    userFileName: String = "<input>",
    importGraph: ImportGraph? = nil
  ) {
    self.ast = ast
    self.coreGlobalCount = max(0, coreGlobalCount)
    self.coreFileName = coreFileName
    self.userFileName = userFileName
    self.currentFileName = userFileName
    self.importGraph = importGraph
    SemanticErrorContext.currentFileName = userFileName
    
    SemanticErrorContext.currentCompilerContext = context
    self.currentScope = UnifiedScope(defIdMap: context.defIdMap)
    
    // 构建源信息映射
    for (index, info) in nodeSourceInfoList.enumerated() {
      self.nodeSourceInfoMap[index] = info
    }
  }

  func builtinStringType() -> Type {
    if let stringType = currentScope.lookupType("String") {
      return stringType
    }
    // Fallback: std should normally define `type String(...)`.
    let defId = getOrAllocateTypeDefId(
      name: "String",
      kind: .structure,
      access: .protected,
      modulePath: [],
      sourceFile: ""
    )
    return .structure(defId: defId)
  }

  // Wrapper for shared utility function from SemaUtils.swift
  func getCompilerMethodKind(_ name: String) -> CompilerMethodKind {
    return SemaUtils.getCompilerMethodKind(name)
  }

  func isBuiltinEqualityComparable(_ type: Type) -> Bool {
    return SemaUtils.isBuiltinEqualityComparable(type)
  }

  func isBuiltinOrderingComparable(_ type: Type) -> Bool {
    return SemaUtils.isBuiltinOrderingComparable(type)
  }

  func isIntegerScalarType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  private func isFloatScalarType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64:
      return true
    default:
      return false
    }
  }

  func isValidExplicitCast(from: Type, to: Type) -> Bool {
    if from == to { return true }

    // Numeric casts (ints <-> ints/uints/floats and floats <-> ints/uints/floats).
    if (isIntegerScalarType(from) || isFloatScalarType(from)) && (isIntegerScalarType(to) || isFloatScalarType(to)) {
      return true
    }

    // Pointer casts.
    if case .pointer = from {
      if case .pointer = to { return true }
      if to == .int || to == .uint { return true }
    }
    if case .pointer = to {
      if from == .int || from == .uint { return true }
    }

    return false
  }

  func nextSynthSymbol(prefix: String, type: Type) -> Symbol {
    synthesizedTempIndex += 1
    let name = "__koral_\(prefix)_\(synthesizedTempIndex)"
    return makeLocalSymbol(name: name, type: type, kind: .variable(.Value))
  }
  
  // MARK: - Global Symbol Creation
  
  /// 创建带有模块信息的全局符号
  /// - Parameters:
  ///   - name: 符号名称
  ///   - type: 符号类型
  ///   - kind: 符号种类
  ///   - methodKind: 编译器方法种类（默认为 .normal）
  ///   - access: 访问修饰符
  /// - Returns: 带有模块信息和 DefId 的 Symbol
  func makeGlobalSymbol(
    name: String,
    type: Type,
    kind: SymbolKind,
    methodKind: CompilerMethodKind = .normal,
    access: AccessModifier
  ) -> Symbol {
    let isMutable: Bool
    switch kind {
    case .variable(let varKind):
      isMutable = varKind.isMutable
    case .function, .type, .module:
      isMutable = false
    }

    return context.createSymbol(
      name: name,
      modulePath: currentModulePath,
      sourceFile: currentSourceFile,
      type: type,
      kind: kind,
      methodKind: methodKind,
      access: access,
      span: currentSpan,
      isMutable: isMutable
    )
  }

  /// 获取或分配类型定义的 DefId
  /// - Parameters:
  ///   - name: 类型名称
  ///   - kind: 类型种类（struct/union/trait）
  ///   - access: 访问修饰符
  ///   - modulePath: 模块路径
  ///   - sourceFile: 源文件路径
  func getOrAllocateTypeDefId(
    name: String,
    kind: TypeDefKind,
    access: AccessModifier,
    modulePath: [String],
    sourceFile: String
  ) -> DefId {
    let lookupSourceFile = access == .private ? sourceFile : nil
    if let existing = defIdMap.lookup(
      modulePath: modulePath,
      name: name,
      sourceFile: lookupSourceFile
    ) {
      return existing
    }
    return defIdMap.allocate(
      modulePath: modulePath,
      name: name,
      kind: .type(kind),
      sourceFile: sourceFile,
      access: access,
      span: .unknown
    )
  }
  
  /// 创建局部符号（局部变量、参数等）
  /// - Parameters:
  ///   - name: 符号名称
  ///   - type: 符号类型
  ///   - kind: 符号种类
  /// - Returns: 带有 DefId 的 Symbol（局部符号的 modulePath 为空）
  func makeLocalSymbol(
    name: String,
    type: Type,
    kind: SymbolKind
  ) -> Symbol {
    let isMutable: Bool
    switch kind {
    case .variable(let varKind):
      isMutable = varKind.isMutable
    case .function, .type, .module:
      isMutable = false
    }

    let defKind: DefKind
    switch kind {
    case .function:
      defKind = .function
    case .variable:
      defKind = .variable
    case .type:
      if case .opaque = type {
        defKind = .type(.opaque)
      } else {
        defKind = .type(.structure)
      }
    case .module:
      defKind = .module
    }

    let defId = defIdMap.allocate(
      modulePath: [],
      name: name,
      kind: defKind,
      sourceFile: "",
      access: .protected,
      span: .unknown
    )
    defIdMap.addSymbolInfo(
      defId: defId,
      type: type,
      kind: kind,
      methodKind: .normal,
      isMutable: isMutable
    )
    return Symbol(defId: defId, type: type, kind: kind, methodKind: .normal)
  }

  func assertNotOpaqueType(_ type: Type, span: SourceSpan) throws {
    if case .opaque(let defId) = type {
      let typeName = context.getName(defId) ?? type.description
      throw SemanticError(.opaqueTypeCannotBeInstantiated(typeName: typeName), span: span)
    }
  }

  /// 为方法调用创建临时物化
  /// 当 base 是右值且方法期望 `self ref` 时，生成 letExpression 包装临时变量和方法调用
  /// 
  /// 例如：`"hello".count_byte()` 转换为：
  /// ```
  /// letExpression(
  ///   identifier: __koral_temp_recv_1,
  ///   value: "hello",
  ///   body: call(
  ///     callee: methodReference(
  ///       base: referenceExpression(variable(__koral_temp_recv_1)),
  ///       method: count_byte
  ///     ),
  ///     arguments: []
  ///   )
  /// Records an instantiation request for deferred monomorphization.
  /// This method collects all generic instantiation points during type checking
  /// so they can be processed later by the Monomorphizer.
  func recordInstantiation(_ request: InstantiationRequest) {
    instantiationRequests.insert(request)
  }

  /// Records a trait placeholder method instantiation request when the base type is concrete.
  func recordTraitPlaceholderInstantiation(
    baseType: Type,
    methodName: String,
    methodTypeArgs: [Type]
  ) {
    if context.containsGenericParameter(baseType) {
      return
    }
    if methodTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
      return
    }
    recordInstantiation(InstantiationRequest(
      kind: .traitMethod(
        baseType: baseType,
        methodName: methodName,
        methodTypeArgs: methodTypeArgs
      ),
      sourceLine: currentLine,
      sourceFileName: currentFileName
    ))
  }

  func checkFunctionBody(
    _ params: [Symbol],
    _ returnType: Type,
    _ body: ExpressionNode
  ) throws -> (TypedExpressionNode, Type) {
    let previousReturnType = currentFunctionReturnType
    currentFunctionReturnType = returnType
    defer { currentFunctionReturnType = previousReturnType }

    return try withNewScope {
      // Add parameters to new scope
      for param in params {
        if let name = context.getName(param.defId) {
          try currentScope.defineLocal(name, defId: param.defId, line: currentLine)
        }
      }

      var typedBody = try inferTypedExpression(body, expectedType: returnType)
      typedBody = try coerceLiteral(typedBody, to: returnType)
      if typedBody.type != .never && typedBody.type != returnType {
        throw SemanticError.typeMismatch(
          expected: returnType.description, got: typedBody.type.description)
      }
      let functionType = Type.function(
        parameters: params.map {
          Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
        }, returns: returnType)
      return (typedBody, functionType)
    }
  }

  func compoundOpToArithmeticOp(_ op: CompoundAssignmentOperator) -> ArithmeticOperator? {
    switch op {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .remainder: return .remainder
    case .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shiftLeft, .shiftRight:
      return nil  // Bitwise operators are not arithmetic operators
    }
  }

  func compoundOpToBitwiseOp(_ op: CompoundAssignmentOperator) -> BitwiseOperator? {
    switch op {
    case .bitwiseAnd: return .and
    case .bitwiseOr: return .or
    case .bitwiseXor: return .xor
    case .shiftLeft: return .shiftLeft
    case .shiftRight: return .shiftRight
    case .plus, .minus, .multiply, .divide, .remainder:
      return nil  // Arithmetic operators are not bitwise operators
    }
  }

  func withNewScope<R>(_ body: () throws -> R) rethrows -> R {
    let previousScope = currentScope
    let previousTraitBounds = genericTraitBounds
    currentScope = currentScope.createChild()
    defer {
      currentScope = previousScope
      genericTraitBounds = previousTraitBounds
    }
    return try body()
  }

  func checkArithmeticOp(_ op: ArithmeticOperator, _ lhs: Type, _ rhs: Type) throws
    -> Type
  {
    if lhs == rhs {
      if isIntegerType(lhs) { return lhs }
      if isFloatType(lhs) { return lhs }
    }
    throw SemanticError.invalidOperation(
      op: String(describing: op), type1: lhs.description, type2: rhs.description)
  }

  func checkComparisonOp(_ op: ComparisonOperator, _ lhs: Type, _ rhs: Type) throws
    -> Type
  {
    if lhs == rhs {
      return .bool
    }
    throw SemanticError.invalidOperation(
      op: String(describing: op), type1: lhs.description, type2: rhs.description)
  }

  /// Resolve union cases for exhaustiveness checking.
  /// For generic unions, this looks up the template and substitutes type parameters.
  func resolveUnionCasesForExhaustiveness(_ type: Type) -> [UnionCase]? {
    switch type {
    case .union(let defId):
      return context.getUnionCases(defId)
      
    case .genericUnion(let templateName, let typeArgs):
      // Look up the union template and substitute type parameters
      guard let template = currentScope.lookupGenericUnionTemplate(templateName) else {
        return nil
      }
      
      // Create substitution map
      var substitution: [String: Type] = [:]
      for (i, param) in template.typeParameters.enumerated() {
        if i < typeArgs.count {
          substitution[param.name] = typeArgs[i]
        }
      }
      
      // Resolve case parameter types with substitution
      do {
        let resolvedCases: [UnionCase] = try template.cases.map { caseDef in
          let resolvedParams: [(name: String, type: Type, access: AccessModifier)] = try caseDef.parameters.map { param in
            let resolvedType = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try resolveTypeNode(param.type)
            }
            return (name: param.name, type: resolvedType, access: AccessModifier.public)
          }
          return UnionCase(name: caseDef.name, parameters: resolvedParams)
        }
        return resolvedCases
      } catch {
        return nil
      }
      
    default:
      return nil
    }
  }

  /// Unifies two types and extracts generic parameter bindings.
  /// This is used to infer method-level type parameters from argument types.
  /// - Parameters:
  ///   - expected: The expected type (may contain generic parameters)
  ///   - actual: The actual type (should be concrete)
  ///   - bindings: Dictionary to store inferred bindings
  /// - Returns: true if unification succeeded, false otherwise
  func unifyTypes(_ expected: Type, _ actual: Type, bindings: inout [String: Type]) -> Bool {
    switch (expected, actual) {
    case (.genericParameter(let name), _):
      if let existing = bindings[name] {
        return existing == actual
      }
      bindings[name] = actual
      return true
      
    case (.function(let expectedParams, let expectedReturn), .function(let actualParams, let actualReturn)):
      guard expectedParams.count == actualParams.count else { return false }
      for (ep, ap) in zip(expectedParams, actualParams) {
        if !unifyTypes(ep.type, ap.type, bindings: &bindings) {
          return false
        }
      }
      return unifyTypes(expectedReturn, actualReturn, bindings: &bindings)
      
    case (.reference(let expectedInner), .reference(let actualInner)):
      return unifyTypes(expectedInner, actualInner, bindings: &bindings)
      
    case (.pointer(let expectedElem), .pointer(let actualElem)):
      return unifyTypes(expectedElem, actualElem, bindings: &bindings)
      
    case (.genericStruct(let expectedName, let expectedArgs), .genericStruct(let actualName, let actualArgs)):
      guard expectedName == actualName && expectedArgs.count == actualArgs.count else { return false }
      for (ea, aa) in zip(expectedArgs, actualArgs) {
        if !unifyTypes(ea, aa, bindings: &bindings) {
          return false
        }
      }
      return true
      
    case (.genericUnion(let expectedName, let expectedArgs), .genericUnion(let actualName, let actualArgs)):
      guard expectedName == actualName && expectedArgs.count == actualArgs.count else { return false }
      for (ea, aa) in zip(expectedArgs, actualArgs) {
        if !unifyTypes(ea, aa, bindings: &bindings) {
          return false
        }
      }
      return true
      
    default:
      // For non-generic types, they must be equal
      return expected == actual || !context.containsGenericParameter(expected)
    }
  }

  /// Extracts generic parameter names from a type in order of first appearance.
  /// This is used to determine the order of method-level type parameters.
  func extractGenericParameterNames(from type: Type) -> [String] {
    var names: [String] = []
    var seen: Set<String> = []
    extractGenericParameterNamesHelper(from: type, names: &names, seen: &seen)
    return names
  }
  
  private func extractGenericParameterNamesHelper(from type: Type, names: inout [String], seen: inout Set<String>) {
    switch type {
    case .genericParameter(let name):
      if !seen.contains(name) {
        seen.insert(name)
        names.append(name)
      }
    case .function(let params, let returns):
      for param in params {
        extractGenericParameterNamesHelper(from: param.type, names: &names, seen: &seen)
      }
      extractGenericParameterNamesHelper(from: returns, names: &names, seen: &seen)
    case .reference(let inner):
      extractGenericParameterNamesHelper(from: inner, names: &names, seen: &seen)
    case .pointer(let element):
      extractGenericParameterNamesHelper(from: element, names: &names, seen: &seen)
    case .genericStruct(_, let args), .genericUnion(_, let args):
      for arg in args {
        extractGenericParameterNamesHelper(from: arg, names: &names, seen: &seen)
      }
    default:
      break
    }
  }
}

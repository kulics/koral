import Foundation

/// 导入的模块信息
public struct ImportedModuleInfo {
  /// 模块路径
  public let modulePath: [String]
  /// 是否是批量导入（using module.*）
  public let isBatchImport: Bool
  /// 导入的特定符号（using module.Symbol）
  public let importedSymbol: String?
  
  public init(modulePath: [String], isBatchImport: Bool = false, importedSymbol: String? = nil) {
    self.modulePath = modulePath
    self.isBatchImport = isBatchImport
    self.importedSymbol = importedSymbol
  }
}

/// 全局节点的源信息
public struct GlobalNodeSourceInfo {
  /// 源文件路径（绝对路径）
  public let sourceFile: String
  /// 模块路径
  public let modulePath: [String]
  /// 全局节点
  public let node: GlobalNode
  /// 当前模块导入的模块信息列表（通过 using 声明）
  public let importedModules: [ImportedModuleInfo]
  
  public init(sourceFile: String, modulePath: [String], node: GlobalNode, importedModules: [ImportedModuleInfo] = []) {
    self.sourceFile = sourceFile
    self.modulePath = modulePath
    self.node = node
    self.importedModules = importedModules
  }
}

public class TypeChecker {
  // Store type information for variables and functions
  // Note: internal access for extension methods in TypeCheckerTypeResolution.swift
  var currentScope: Scope = Scope()
  let ast: ASTNode
  // TypeName -> MethodName -> MethodSymbol
  var extensionMethods: [String: [String: Symbol]] = [:]

  var traits: [String: TraitDeclInfo] = [:]

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
  
  // Sets to track intrinsic generic types and functions for special handling during monomorphization
  var intrinsicGenericTypes: Set<String> = []
  var intrinsicGenericFunctions: Set<String> = []
  
  // Set to track types defined in the standard library (for given declaration module rules)
  var stdLibTypes: Set<String> = []

  var currentSpan: SourceSpan = .unknown {
    didSet {
      SemanticErrorContext.updateSpan(currentSpan)
    }
  }
  
  // Backward compatibility: currentLine as computed property
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

  var synthesizedTempIndex: Int = 0
  
  // MARK: - Module System Support
  
  /// 全局节点的源信息映射（用于多文件项目）
  /// 键是节点在 declarations 数组中的索引
  var nodeSourceInfoMap: [Int: GlobalNodeSourceInfo] = [:]
  
  /// 当前正在处理的节点的源文件路径（绝对路径）
  var currentSourceFile: String = ""
  
  /// 当前正在处理的节点的模块路径
  var currentModulePath: [String] = []
  
  /// 当前模块导入的模块信息列表（通过 using 声明）
  var currentImportedModules: [ImportedModuleInfo] = []
  
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
  /// 2. 符号来自父模块（符号的 modulePath 是当前 modulePath 的前缀）
  /// 3. 符号来自标准库根模块（modulePath 为 ["std"]）
  /// 4. 符号来自同一编译单元的根模块
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
    
    // 检查符号是否来自父模块（符号的 modulePath 是当前 modulePath 的前缀）
    // 例如：当前在 ["expr_eval", "frontend"]，符号在 ["expr_eval"]
    if symbolModulePath.count < currentModulePath.count {
      let prefix = Array(currentModulePath.prefix(symbolModulePath.count))
      if prefix == symbolModulePath {
        return true
      }
    }
    
    // 检查符号是否来自同一编译单元的根模块
    // 例如：当前在 ["expr_eval"]，符号也在 ["expr_eval"] 的某个文件
    if !currentModulePath.isEmpty && !symbolModulePath.isEmpty {
      // 同一编译单元：根模块名相同
      if currentModulePath[0] == symbolModulePath[0] {
        // 如果符号来自子模块，不允许直接访问
        // 例如：当前在 ["expr_eval"]，符号在 ["expr_eval", "frontend"]
        if symbolModulePath.count > currentModulePath.count {
          return false
        }
      }
    }
    
    return false
  }
  
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
    // 空路径总是可直接访问（局部变量/参数）
    if symbolModulePath.isEmpty {
      return true
    }
    
    // 同一模块可以直接访问
    if symbolModulePath == currentModulePath {
      return true
    }
    
    // 标准库符号总是可以直接访问
    if !symbolModulePath.isEmpty && symbolModulePath[0] == "std" {
      return true
    }
    
    // 检查符号是否来自父模块（符号的 modulePath 是当前 modulePath 的前缀）
    // 例如：当前在 ["expr_eval", "frontend"]，符号在 ["expr_eval"]
    // 父模块的符号可以直接访问
    if symbolModulePath.count < currentModulePath.count {
      let prefix = Array(currentModulePath.prefix(symbolModulePath.count))
      if prefix == symbolModulePath {
        return true
      }
    }
    
    // 检查符号是否来自导入的模块
    for importInfo in currentImportedModules {
      // 批量导入：using module.* -> 模块的所有符号可以直接访问
      if importInfo.isBatchImport && symbolModulePath == importInfo.modulePath {
        return true
      }
      
      // 成员导入：using module.Symbol -> 只有指定的符号可以直接访问
      if let importedSymbol = importInfo.importedSymbol,
         symbolModulePath == importInfo.modulePath,
         let name = symbolName,
         name == importedSymbol {
        return true
      }
      
      // 注意：普通模块导入（using module）不允许直接访问模块内的符号
      // 需要通过 module.Symbol 访问
    }
    
    // 其他情况（子模块、兄弟模块、外部模块）不允许直接访问
    // 需要通过模块前缀访问
    return false
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
    // 空路径不需要前缀
    if symbolModulePath.isEmpty {
      return ""
    }
    
    // 同一模块不需要前缀
    if symbolModulePath == currentModulePath {
      return ""
    }
    
    // 检查是否是子模块
    // 例如：当前在 ["expr_eval"]，符号在 ["expr_eval", "frontend"]
    if symbolModulePath.count > currentModulePath.count {
      let prefix = Array(symbolModulePath.prefix(currentModulePath.count))
      if prefix == currentModulePath {
        // 返回直接子模块名
        return symbolModulePath[currentModulePath.count]
      }
    }
    
    // 检查是否是兄弟模块
    // 例如：当前在 ["expr_eval", "backend"]，符号在 ["expr_eval", "frontend"]
    if symbolModulePath.count >= 2 && currentModulePath.count >= 2 {
      // 找到共同祖先
      var commonPrefixLength = 0
      for i in 0..<min(symbolModulePath.count, currentModulePath.count) {
        if symbolModulePath[i] == currentModulePath[i] {
          commonPrefixLength = i + 1
        } else {
          break
        }
      }
      
      if commonPrefixLength > 0 && commonPrefixLength < symbolModulePath.count {
        // 返回从共同祖先开始的第一个不同部分
        return symbolModulePath[commonPrefixLength]
      }
    }
    
    // 外部模块：返回模块名
    if !symbolModulePath.isEmpty {
      return symbolModulePath.last ?? ""
    }
    
    return ""
  }
  
  /// 检查类型的模块可见性
  /// 如果类型来自子模块或兄弟模块，需要使用模块前缀访问
  func checkTypeVisibility(type: Type, typeName: String) throws {
    // 获取类型的模块路径
    let typeModulePath: [String]
    switch type {
    case .structure(let decl):
      typeModulePath = decl.modulePath
    case .union(let decl):
      typeModulePath = decl.modulePath
    case .genericStruct(let templateName, _):
      // 泛型结构体：查找模板获取模块路径
      if currentScope.lookupGenericStructTemplate(templateName) != nil {
        // 泛型模板目前没有存储模块路径，暂时跳过检查
        // TODO: 为泛型模板添加模块路径支持
        return
      }
      return
    case .genericUnion(let templateName, _):
      // 泛型联合体：查找模板获取模块路径
      if currentScope.lookupGenericUnionTemplate(templateName) != nil {
        // 泛型模板目前没有存储模块路径，暂时跳过检查
        // TODO: 为泛型模板添加模块路径支持
        return
      }
      return
    default:
      // 基本类型、泛型参数等不需要检查
      return
    }
    
    // 空模块路径表示标准库类型或局部类型，总是可访问
    if typeModulePath.isEmpty {
      return
    }
    
    // 标准库类型总是可访问
    if !typeModulePath.isEmpty && typeModulePath[0] == "std" {
      return
    }
    
    // 检查是否可以直接访问（传递类型名用于成员导入检查）
    if !canAccessSymbolDirectly(symbolModulePath: typeModulePath, currentModulePath: currentModulePath, symbolName: typeName) {
      let modulePrefix = getRequiredModulePrefix(symbolModulePath: typeModulePath, currentModulePath: currentModulePath)
      throw SemanticError(.generic("'\(typeName)' is defined in module '\(modulePrefix)'. Use '\(modulePrefix).\(typeName)' to access it."), line: currentLine)
    }
  }

  public init(
    ast: ASTNode,
    coreGlobalCount: Int = 0,
    coreFileName: String = "std/std.koral",
    userFileName: String = "<input>"
  ) {
    self.ast = ast
    self.coreGlobalCount = max(0, coreGlobalCount)
    self.coreFileName = coreFileName
    self.userFileName = userFileName
    self.currentFileName = userFileName
    SemanticErrorContext.currentFileName = userFileName
    SemanticErrorContext.currentLine = 1
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
    userFileName: String = "<input>"
  ) {
    self.ast = ast
    self.coreGlobalCount = max(0, coreGlobalCount)
    self.coreFileName = coreFileName
    self.userFileName = userFileName
    self.currentFileName = userFileName
    SemanticErrorContext.currentFileName = userFileName
    SemanticErrorContext.currentLine = 1
    
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
    let decl = StructDecl(
      name: "String",
      modulePath: [],
      sourceFile: "",
      access: .default,
      members: [],
      isGenericInstantiation: false
    )
    return .structure(decl: decl)
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

  private func isSignedIntegerScalarType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64:
      return true
    default:
      return false
    }
  }

  private func isUnsignedIntegerScalarType(_ type: Type) -> Bool {
    switch type {
    case .uint, .uint8, .uint16, .uint32, .uint64:
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

  private func withTempIfRValue(
    _ expr: TypedExpressionNode,
    prefix: String,
    _ body: (TypedExpressionNode) throws -> TypedExpressionNode
  ) rethrows -> TypedExpressionNode {
    if expr.valueCategory == .lvalue {
      return try body(expr)
    }
    let sym = nextSynthSymbol(prefix: prefix, type: expr.type)
    let varExpr: TypedExpressionNode = .variable(identifier: sym)
    let inner = try body(varExpr)
    return .letExpression(identifier: sym, value: expr, body: inner, type: inner.type)
  }

  private func ensureBorrowed(_ expr: TypedExpressionNode, expected: Type) throws -> TypedExpressionNode {
    if expr.type == expected {
      return expr
    }
    if case .reference(let inner) = expected, expr.type == inner {
      if expr.valueCategory == .lvalue {
        return .referenceExpression(expression: expr, type: expected)
      }
      throw SemanticError.invalidOperation(op: "implicit ref", type1: expr.type.description, type2: "rvalue")
    }
    throw SemanticError.typeMismatch(expected: expected.description, got: expr.type.description)
  }



  func nextSynthSymbol(prefix: String, type: Type) -> Symbol {
    synthesizedTempIndex += 1
    return Symbol(
      name: "__koral_\(prefix)_\(synthesizedTempIndex)",
      type: type,
      kind: .variable(.Value),
      modulePath: currentModulePath,
      sourceFile: currentSourceFile,
      access: .default
    )
  }
  
  /// 创建局部符号（用于参数、局部变量等）
  /// - Parameters:
  ///   - name: 符号名称
  ///   - type: 符号类型
  ///   - kind: 符号种类
  /// - Returns: 带有当前模块信息的 Symbol
  func makeLocalSymbol(
    name: String,
    type: Type,
    kind: SymbolKind
  ) -> Symbol {
    return Symbol(
      name: name,
      type: type,
      kind: kind,
      modulePath: currentModulePath,
      sourceFile: currentSourceFile,
      access: .default
    )
  }
  
  // MARK: - Global Symbol Creation
  
  /// 创建带有模块信息的全局符号
  /// - Parameters:
  ///   - name: 符号名称
  ///   - type: 符号类型
  ///   - kind: 符号种类
  ///   - methodKind: 编译器方法种类（默认为 .normal）
  ///   - access: 访问修饰符
  /// - Returns: 带有模块信息的 Symbol
  func makeGlobalSymbol(
    name: String,
    type: Type,
    kind: SymbolKind,
    methodKind: CompilerMethodKind = .normal,
    access: AccessModifier
  ) -> Symbol {
    return Symbol(
      name: name,
      type: type,
      kind: kind,
      methodKind: methodKind,
      modulePath: currentModulePath,
      sourceFile: currentSourceFile,
      access: access
    )
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
        currentScope.define(param.name, param.type, mutable: param.isMutable())
      }

      let typedBody = try inferTypedExpression(body)
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

  private func convertExprToTypeNode(_ expr: ExpressionNode) throws -> TypeNode {
    switch expr {
    case .identifier(let name):
      return .identifier(name)
    case .subscriptExpression(let base, let args):
      if case .identifier(let baseName) = base {
        let typeArgs = try args.map { try convertExprToTypeNode($0) }
        return .generic(base: baseName, args: typeArgs)
      }
      throw SemanticError.invalidOperation(
        op: "Complex type expression not supported", type1: "", type2: "")
    default:
      throw SemanticError.typeMismatch(expected: "Type Identifier", got: String(describing: expr))
    }
  }


  func compoundOpToArithmeticOp(_ op: CompoundAssignmentOperator) -> ArithmeticOperator? {
    switch op {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .modulo: return .modulo
    case .power: return .power
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
    case .plus, .minus, .multiply, .divide, .modulo, .power:
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
    case .union(let decl):
      return decl.cases
      
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
          let resolvedParams: [(name: String, type: Type)] = try caseDef.parameters.map { param in
            let resolvedType = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try resolveTypeNode(param.type)
            }
            return (name: param.name, type: resolvedType)
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
      return expected == actual || !expected.containsGenericParameter
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

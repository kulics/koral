/// PassInterfaces.swift - 编译器 Pass 接口和数据结构定义
///
/// 本文件定义了编译器多 Pass 架构的核心接口和数据结构。
/// 每个 Pass 有明确的输入、输出和职责，确保编译流程清晰可维护。
///
/// ## Pass 架构概述
/// - Phase 0: ModuleResolver - 解析模块结构和文件依赖
/// - Pass 1: NameCollector - 收集所有类型和函数名称，分配 DefId
/// - Pass 2: TypeResolver - 解析类型成员和函数签名
/// - Pass 3: BodyChecker - 检查函数体和表达式，进行类型推导
///
/// ## 设计参考
/// - Rust 编译器 (rustc): DefId 系统、HIR/MIR 分层
/// - Swift 编译器: DeclContext 层次结构
/// - Go 编译器: 简洁的包系统

import Foundation

// MARK: - Pass 输入输出协议

/// Pass 输入的标记协议
///
/// 所有 Pass 的输入类型都必须遵循此协议。
/// 这是一个标记协议，用于类型约束。
public protocol PassInput {}

/// Pass 输出的标记协议
///
/// 所有 Pass 的输出类型都必须遵循此协议。
/// 这是一个标记协议，用于类型约束。
public protocol PassOutput {}

// MARK: - CompilerPass 协议

/// 编译器 Pass 协议
///
/// 定义了编译器 Pass 的基本接口。每个 Pass 都有：
/// - 明确的输入类型
/// - 明确的输出类型
/// - 唯一的名称标识
/// - 执行方法
///
/// ## 示例
/// ```swift
/// struct MyPass: CompilerPass {
///     typealias Input = SomeInput
///     typealias Output = SomeOutput
///
///     var name: String { "MyPass" }
///
///     func run(input: Input) throws -> Output {
///         // Pass 实现
///     }
/// }
/// ```
public protocol CompilerPass {
    /// Pass 的输入类型
    associatedtype Input: PassInput
    
    /// Pass 的输出类型
    associatedtype Output: PassOutput
    
    /// Pass 名称
    ///
    /// 用于日志、调试和错误报告。
    var name: String { get }
    
    /// 执行 Pass
    ///
    /// - Parameter input: Pass 的输入数据
    /// - Returns: Pass 的输出数据
    /// - Throws: 如果 Pass 执行过程中遇到错误
    func run(input: Input) throws -> Output
}

// MARK: - 占位类型定义

/// 模块树 - 表示模块的层次结构
///
/// 这是一个占位类型，将在后续任务中完善实现。
/// 目前使用 ModuleInfo 作为基础。
///
/// ## 未来扩展
/// - 支持模块查找
/// - 支持模块遍历
/// - 支持模块依赖分析
public struct ModuleTree {
    /// 根模块信息
    public let rootModule: ModuleInfo
    
    /// 所有已加载的模块（路径字符串 -> 模块）
    public let loadedModules: [String: ModuleInfo]
    
    /// 创建模块树
    ///
    /// - Parameters:
    ///   - rootModule: 根模块信息
    ///   - loadedModules: 所有已加载的模块
    public init(rootModule: ModuleInfo, loadedModules: [String: ModuleInfo]) {
        self.rootModule = rootModule
        self.loadedModules = loadedModules
    }
    
    /// 查找模块
    ///
    /// - Parameter path: 模块路径
    /// - Returns: 找到的模块信息，如果不存在则返回 nil
    public func findModule(path: [String]) -> ModuleInfo? {
        let pathString = path.joined(separator: ".")
        return loadedModules[pathString]
    }
}

/// 名称表 - 存储名称到 DefId 的映射
///
/// 这是一个占位类型，将在后续任务中完善实现。
/// 用于在 Pass 1 中收集所有类型和函数名称。
///
/// ## 未来扩展
/// - 支持按模块查询
/// - 支持按类型查询
/// - 支持名称冲突检测
public struct NameTable {
    /// 名称到 DefId 的映射
    private var entries: [String: DefId]
    
    /// 创建空的名称表
    public init() {
        self.entries = [:]
    }
    
    /// 添加名称条目
    ///
    /// - Parameters:
    ///   - name: 完整限定名称
    ///   - defId: 对应的 DefId
    public mutating func add(name: String, defId: DefId) {
        entries[name] = defId
    }
    
    /// 查找名称
    ///
    /// - Parameter name: 完整限定名称
    /// - Returns: 对应的 DefId，如果不存在则返回 nil
    public func lookup(name: String) -> DefId? {
        return entries[name]
    }
    
    /// 获取所有条目
    public var allEntries: [String: DefId] {
        return entries
    }
    
    /// 条目数量
    public var count: Int {
        return entries.count
    }
}

/// 类型化定义映射 - 存储 DefId 到类型信息的映射
///
/// 这是一个占位类型，将在后续任务中完善实现。
/// 用于在 Pass 2 中存储解析后的类型信息。
///
/// ## 未来扩展
/// - 支持类型成员查询
/// - 支持函数签名查询
/// - 支持泛型实例化
public struct TypedDefMap {
    /// DefId 到类型的映射
    private var typeMap: [UInt64: Type]
    
    /// DefId 到函数签名的映射
    private var signatureMap: [UInt64: FunctionSignature]
    
    /// 创建空的类型化定义映射
    public init() {
        self.typeMap = [:]
        self.signatureMap = [:]
    }
    
    /// 添加类型定义
    ///
    /// - Parameters:
    ///   - defId: 定义的 DefId
    ///   - type: 解析后的类型
    public mutating func addType(defId: DefId, type: Type) {
        typeMap[defId.id] = type
    }
    
    /// 添加函数签名
    ///
    /// - Parameters:
    ///   - defId: 函数的 DefId
    ///   - signature: 函数签名
    public mutating func addSignature(defId: DefId, signature: FunctionSignature) {
        signatureMap[defId.id] = signature
    }
    
    /// 查找类型
    ///
    /// - Parameter defId: 定义的 DefId
    /// - Returns: 解析后的类型，如果不存在则返回 nil
    public func lookupType(defId: DefId) -> Type? {
        return typeMap[defId.id]
    }
    
    /// 查找函数签名
    ///
    /// - Parameter defId: 函数的 DefId
    /// - Returns: 函数签名，如果不存在则返回 nil
    public func lookupSignature(defId: DefId) -> FunctionSignature? {
        return signatureMap[defId.id]
    }
}

/// 函数签名 - 描述函数的参数和返回类型
///
/// 用于在 Pass 2 中存储解析后的函数签名信息。
public struct FunctionSignature {
    /// 参数列表
    public let parameters: [FunctionParameter]
    
    /// 返回类型
    public let returnType: Type
    
    /// 泛型参数（如果是泛型函数）
    public let typeParameters: [String]
    
    /// 创建函数签名
    ///
    /// - Parameters:
    ///   - parameters: 参数列表
    ///   - returnType: 返回类型
    ///   - typeParameters: 泛型参数
    public init(
        parameters: [FunctionParameter],
        returnType: Type,
        typeParameters: [String] = []
    ) {
        self.parameters = parameters
        self.returnType = returnType
        self.typeParameters = typeParameters
    }
}

/// 函数参数 - 描述函数的单个参数
public struct FunctionParameter {
    /// 参数名称
    public let name: String
    
    /// 参数类型
    public let type: Type
    
    /// 是否可变
    public let isMutable: Bool
    
    /// 传递方式
    public let passKind: PassKind
    
    /// 创建函数参数
    ///
    /// - Parameters:
    ///   - name: 参数名称
    ///   - type: 参数类型
    ///   - isMutable: 是否可变
    ///   - passKind: 传递方式
    public init(
        name: String,
        type: Type,
        isMutable: Bool = false,
        passKind: PassKind = .byVal
    ) {
        self.name = name
        self.type = type
        self.isMutable = isMutable
        self.passKind = passKind
    }
}

/// 符号表 - 管理符号的注册和查找
///
/// 这是一个占位类型，将在后续任务中完善实现。
/// 与现有的 Scope 类配合使用。
///
/// ## 未来扩展
/// - 支持按模块查询
/// - 支持按文件查询
/// - 支持按作用域查询
public struct SymbolTable {
    /// 符号映射：DefId -> SymbolInfo
    private var symbols: [UInt64: SymbolTableEntry]
    
    /// 创建空的符号表
    public init() {
        self.symbols = [:]
    }
    
    /// 添加符号
    ///
    /// - Parameters:
    ///   - defId: 符号的 DefId
    ///   - entry: 符号信息
    public mutating func add(defId: DefId, entry: SymbolTableEntry) {
        symbols[defId.id] = entry
    }
    
    /// 查找符号
    ///
    /// - Parameter defId: 符号的 DefId
    /// - Returns: 符号信息，如果不存在则返回 nil
    public func lookup(defId: DefId) -> SymbolTableEntry? {
        return symbols[defId.id]
    }
    
    /// 获取所有符号
    public var allSymbols: [UInt64: SymbolTableEntry] {
        return symbols
    }
}

/// 符号表条目 - 存储符号的详细信息
public struct SymbolTableEntry {
    /// 符号的 DefId
    public let defId: DefId
    
    /// 符号名称
    public let name: String
    
    /// 符号类型
    public let type: Type
    
    /// 符号种类
    public let kind: SymbolKind
    
    /// 访问修饰符
    public let access: AccessModifier
    
    /// 源文件路径
    public let sourceFile: String
    
    /// 是否可以直接访问（不需要模块前缀）
    public let isDirectlyAccessible: Bool
    
    /// 创建符号表条目
    ///
    /// - Parameters:
    ///   - defId: 符号的 DefId
    ///   - name: 符号名称
    ///   - type: 符号类型
    ///   - kind: 符号种类
    ///   - access: 访问修饰符
    ///   - sourceFile: 源文件路径
    ///   - isDirectlyAccessible: 是否可以直接访问
    public init(
        defId: DefId,
        name: String,
        type: Type,
        kind: SymbolKind,
        access: AccessModifier,
        sourceFile: String,
        isDirectlyAccessible: Bool = true
    ) {
        self.defId = defId
        self.name = name
        self.type = type
        self.kind = kind
        self.access = access
        self.sourceFile = sourceFile
        self.isDirectlyAccessible = isDirectlyAccessible
    }
}

// 注意：InstantiationRequest 和 InstantiationKind 已在
// Monomorphization/InstantiationRequest.swift 中定义，
// 此处直接使用现有类型，无需重复定义。

// MARK: - Phase 0: ModuleResolver 输出

/// ModuleResolver 的输出
///
/// Phase 0 负责解析模块结构和文件依赖，输出包括：
/// - 模块树：表示模块的层次结构
/// - 导入图：记录模块间的导入关系
/// - AST 节点：所有全局声明节点
///
/// ## 依赖关系
/// - 输入：源文件路径
/// - 输出：供 Pass 1 (NameCollector) 使用
///
/// **Validates: Requirements 2.1, 2.3**
public struct ModuleResolverOutput: PassOutput {
    /// 模块树 - 表示模块的层次结构
    public let moduleTree: ModuleTree
    
    /// 导入图 - 记录模块间的导入关系
    public let importGraph: ImportGraph
    
    /// AST 节点 - 所有全局声明节点
    public let astNodes: [GlobalNode]
    
    /// 节点源信息列表 - 每个节点的源文件和模块路径信息
    public let nodeSourceInfoList: [GlobalNodeSourceInfo]
    
    /// 创建 ModuleResolver 输出
    ///
    /// - Parameters:
    ///   - moduleTree: 模块树
    ///   - importGraph: 导入图
    ///   - astNodes: AST 节点列表
    ///   - nodeSourceInfoList: 节点源信息列表
    public init(
        moduleTree: ModuleTree,
        importGraph: ImportGraph,
        astNodes: [GlobalNode],
        nodeSourceInfoList: [GlobalNodeSourceInfo]
    ) {
        self.moduleTree = moduleTree
        self.importGraph = importGraph
        self.astNodes = astNodes
        self.nodeSourceInfoList = nodeSourceInfoList
    }
}

// MARK: - Pass 1: NameCollector 输出

/// NameCollector 的输出
///
/// Pass 1 负责收集所有类型和函数名称，分配 DefId，输出包括：
/// - DefIdMap：所有定义的标识符映射
/// - NameTable：名称到 DefId 的映射
/// - ModuleResolverOutput：来自 Phase 0 的输出（用于后续 Pass）
///
/// ## 依赖关系
/// - 输入：ModuleResolverOutput
/// - 输出：供 Pass 2 (TypeResolver) 使用
///
/// **Validates: Requirements 2.1, 2.3**
public struct NameCollectorOutput: PassOutput {
    /// DefId 映射表 - 管理所有定义的标识符
    public let defIdMap: DefIdMap
    
    /// 名称表 - 存储名称到 DefId 的映射
    public let nameTable: NameTable
    
    /// ModuleResolver 的输出 - 包含模块树、导入图和 AST 节点
    public let moduleResolverOutput: ModuleResolverOutput
    
    /// 创建 NameCollector 输出
    ///
    /// - Parameters:
    ///   - defIdMap: DefId 映射表
    ///   - nameTable: 名称表
    ///   - moduleResolverOutput: ModuleResolver 的输出
    public init(
        defIdMap: DefIdMap,
        nameTable: NameTable,
        moduleResolverOutput: ModuleResolverOutput
    ) {
        self.defIdMap = defIdMap
        self.nameTable = nameTable
        self.moduleResolverOutput = moduleResolverOutput
    }
}

// MARK: - Pass 2: TypeResolver 输出

/// TypeResolver 的输出
///
/// Pass 2 负责解析类型成员和函数签名，输出包括：
/// - TypedDefMap：DefId 到类型信息的映射
/// - SymbolTable：符号的注册和查找表
/// - NameCollectorOutput：来自 Pass 1 的输出（用于后续 Pass）
///
/// ## 依赖关系
/// - 输入：NameCollectorOutput
/// - 输出：供 Pass 3 (BodyChecker) 使用
///
/// **Validates: Requirements 2.1, 2.3**
public struct TypeResolverOutput: PassOutput {
    /// 类型化定义映射 - 存储 DefId 到类型信息的映射
    public let typedDefMap: TypedDefMap
    
    /// 符号表 - 管理符号的注册和查找
    public let symbolTable: SymbolTable
    
    /// NameCollector 的输出 - 包含 DefIdMap、NameTable 和 ModuleResolverOutput
    public let nameCollectorOutput: NameCollectorOutput
    
    /// 创建 TypeResolver 输出
    ///
    /// - Parameters:
    ///   - typedDefMap: 类型化定义映射
    ///   - symbolTable: 符号表
    ///   - nameCollectorOutput: NameCollector 的输出
    public init(
        typedDefMap: TypedDefMap,
        symbolTable: SymbolTable,
        nameCollectorOutput: NameCollectorOutput
    ) {
        self.typedDefMap = typedDefMap
        self.symbolTable = symbolTable
        self.nameCollectorOutput = nameCollectorOutput
    }
}

// MARK: - Pass 3: BodyChecker 输出

/// BodyChecker 的输出
///
/// Pass 3 负责检查函数体和表达式，进行类型推导，输出包括：
/// - TypedAST：类型化的 AST
/// - InstantiationRequests：泛型实例化请求集合
/// - TypeResolverOutput：来自 Pass 2 的输出（用于后续阶段）
///
/// ## 依赖关系
/// - 输入：TypeResolverOutput
/// - 输出：供 Monomorphizer 使用
///
/// **Validates: Requirements 2.1, 2.3**
public struct BodyCheckerOutput: PassOutput {
    /// 类型化的 AST
    public let typedAST: TypedProgram
    
    /// 泛型实例化请求集合
    public let instantiationRequests: Set<InstantiationRequest>
    
    /// TypeResolver 的输出 - 包含 TypedDefMap、SymbolTable 和 NameCollectorOutput
    public let typeResolverOutput: TypeResolverOutput
    
    /// 创建 BodyChecker 输出
    ///
    /// - Parameters:
    ///   - typedAST: 类型化的 AST
    ///   - instantiationRequests: 泛型实例化请求集合
    ///   - typeResolverOutput: TypeResolver 的输出
    public init(
        typedAST: TypedProgram,
        instantiationRequests: Set<InstantiationRequest>,
        typeResolverOutput: TypeResolverOutput
    ) {
        self.typedAST = typedAST
        self.instantiationRequests = instantiationRequests
        self.typeResolverOutput = typeResolverOutput
    }
}

// MARK: - Pass 输入类型

/// ModuleResolver 的输入
///
/// Phase 0 的输入，包含源文件路径信息。
public struct ModuleResolverInput: PassInput {
    /// 入口文件路径
    public let entryFile: String
    
    /// 标准库路径（可选）
    public let stdLibPath: String?
    
    /// 外部模块搜索路径
    public let externalPaths: [String]
    
    /// 创建 ModuleResolver 输入
    ///
    /// - Parameters:
    ///   - entryFile: 入口文件路径
    ///   - stdLibPath: 标准库路径
    ///   - externalPaths: 外部模块搜索路径
    public init(
        entryFile: String,
        stdLibPath: String? = nil,
        externalPaths: [String] = []
    ) {
        self.entryFile = entryFile
        self.stdLibPath = stdLibPath
        self.externalPaths = externalPaths
    }
}

/// NameCollector 的输入
///
/// Pass 1 的输入，包含 ModuleResolver 的输出。
public struct NameCollectorInput: PassInput {
    /// ModuleResolver 的输出
    public let moduleResolverOutput: ModuleResolverOutput
    
    /// 创建 NameCollector 输入
    ///
    /// - Parameter moduleResolverOutput: ModuleResolver 的输出
    public init(moduleResolverOutput: ModuleResolverOutput) {
        self.moduleResolverOutput = moduleResolverOutput
    }
}

/// TypeResolver 的输入
///
/// Pass 2 的输入，包含 NameCollector 的输出。
public struct TypeResolverInput: PassInput {
    /// NameCollector 的输出
    public let nameCollectorOutput: NameCollectorOutput
    
    /// 创建 TypeResolver 输入
    ///
    /// - Parameter nameCollectorOutput: NameCollector 的输出
    public init(nameCollectorOutput: NameCollectorOutput) {
        self.nameCollectorOutput = nameCollectorOutput
    }
}

/// BodyChecker 的输入
///
/// Pass 3 的输入，包含 TypeResolver 的输出。
public struct BodyCheckerInput: PassInput {
    /// TypeResolver 的输出
    public let typeResolverOutput: TypeResolverOutput
    
    /// 创建 BodyChecker 输入
    ///
    /// - Parameter typeResolverOutput: TypeResolver 的输出
    public init(typeResolverOutput: TypeResolverOutput) {
        self.typeResolverOutput = typeResolverOutput
    }
}

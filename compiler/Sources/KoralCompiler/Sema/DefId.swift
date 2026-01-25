/// DefId.swift - 定义标识符系统
///
/// DefId（Definition Identifier）是唯一标识每个全局定义的核心数据结构，
/// 参考 Rust 编译器的设计。用于解决符号名和模块路径混合导致的问题。

// MARK: - DefKind 枚举

/// 类型定义的具体类型
public enum TypeDefKind: Hashable, Equatable {
    /// 结构体类型
    case structure
    /// 联合类型
    case union
    /// Trait 类型
    case trait
}

/// 泛型模板的具体类型
public enum GenericTemplateKind: Hashable, Equatable {
    /// 泛型结构体模板
    case structure
    /// 泛型联合类型模板
    case union
    /// 泛型函数模板
    case function
}

/// 定义类型 - 描述定义的种类
public enum DefKind: Hashable, Equatable {
    /// 类型定义（struct、union、trait）
    case type(TypeDefKind)
    /// 函数定义
    case function
    /// 变量定义
    case variable
    /// 模块定义
    case module
    /// 泛型模板定义
    case genericTemplate(GenericTemplateKind)
}

// MARK: - DefId 结构体

/// 定义标识符 - 唯一标识每个全局定义
///
/// DefId 是编译器中用于唯一标识类型、函数、变量等定义的核心数据结构。
/// 它包含了定义的完整路径信息，用于：
/// - 符号查找和匹配
/// - 生成唯一的 C 标识符
/// - 支持模块系统和可见性检查
///
/// ## 示例
/// ```
/// // 对于 expr_eval/frontend 模块中的 Parser 类型
/// let defId = DefId(
///     modulePath: ["expr_eval", "frontend"],
///     name: "Parser",
///     kind: .type(.structure),
///     sourceFile: "parser.koral",
///     id: 42
/// )
/// // defId.cIdentifier == "expr_eval_frontend_Parser"
/// ```
public struct DefId: Hashable, Equatable {
    /// 模块路径（如 ["expr_eval", "frontend"]）
    ///
    /// 表示定义所在的模块层次结构。根模块的路径为空数组。
    public let modulePath: [String]
    
    /// 定义名称
    ///
    /// 定义的简单名称，不包含模块路径。
    public let name: String
    
    /// 定义类型
    ///
    /// 描述这个定义是类型、函数、变量还是模块。
    public let kind: DefKind
    
    /// 源文件路径（用于 private 符号隔离）
    ///
    /// 对于 private 符号，需要源文件路径来确保只有同一文件中的代码可以访问。
    public let sourceFile: String
    
    /// 唯一数字 ID（用于快速比较）
    ///
    /// 由 DefIdMap 分配的全局唯一数字标识符，用于高效的相等性比较和哈希。
    public let id: UInt64
    
    /// 创建一个新的 DefId
    ///
    /// - Parameters:
    ///   - modulePath: 模块路径
    ///   - name: 定义名称
    ///   - kind: 定义类型
    ///   - sourceFile: 源文件路径
    ///   - id: 唯一数字 ID
    public init(
        modulePath: [String],
        name: String,
        kind: DefKind,
        sourceFile: String,
        id: UInt64
    ) {
        self.modulePath = modulePath
        self.name = name
        self.kind = kind
        self.sourceFile = sourceFile
        self.id = id
    }
    
    // MARK: - 计算属性
    
    /// 生成唯一的 C 标识符
    ///
    /// 将模块路径和名称组合成一个有效的 C 标识符。
    /// 模块路径中的各部分用下划线连接。
    /// 对于 private 符号，会包含文件标识符以确保唯一性。
    ///
    /// 使用 CIdentifierUtils 中的统一逻辑，确保与 CodeGen 保持一致。
    ///
    /// ## 示例
    /// - `["expr_eval", "frontend"]` + `"Parser"` → `"expr_eval_frontend_Parser"`
    /// - `[]` + `"main"` → `"main"`
    /// - private 符号会包含文件哈希：`"module_f1234_PrivateType"`
    public var cIdentifier: String {
        return generateCIdentifier(
            modulePath: modulePath,
            name: name,
            isPrivate: false,  // 由调用者根据 access modifier 决定
            sourceFile: ""
        )
    }
    
    /// 生成带有文件隔离的 C 标识符（用于 private 符号）
    ///
    /// - Returns: 包含文件哈希的唯一 C 标识符
    public var cIdentifierWithFileIsolation: String {
        return generateCIdentifier(
            modulePath: modulePath,
            name: name,
            isPrivate: true,
            sourceFile: sourceFile
        )
    }
    
    /// 完整的限定名称（用于显示和调试）
    ///
    /// 使用点号分隔的完整路径名称。
    ///
    /// ## 示例
    /// - `["expr_eval", "frontend"]` + `"Parser"` → `"expr_eval.frontend.Parser"`
    /// - `[]` + `"main"` → `"main"`
    public var qualifiedName: String {
        var parts = modulePath
        parts.append(name)
        return parts.joined(separator: ".")
    }
    
    /// 是否是根模块中的定义
    public var isRootLevel: Bool {
        return modulePath.isEmpty
    }
    
    // MARK: - Hashable & Equatable
    
    /// 基于唯一 ID 进行哈希
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// 基于唯一 ID 进行相等性比较
    ///
    /// 由于 ID 是全局唯一的，我们可以只比较 ID 来提高性能。
    public static func == (lhs: DefId, rhs: DefId) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - CustomStringConvertible

extension DefId: CustomStringConvertible {
    public var description: String {
        return "DefId(\(qualifiedName), kind: \(kind), id: \(id))"
    }
}

extension DefKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .type(let typeKind):
            return "type(\(typeKind))"
        case .function:
            return "function"
        case .variable:
            return "variable"
        case .module:
            return "module"
        case .genericTemplate(let templateKind):
            return "genericTemplate(\(templateKind))"
        }
    }
}

extension TypeDefKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .structure:
            return "structure"
        case .union:
            return "union"
        case .trait:
            return "trait"
        }
    }
}

extension GenericTemplateKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .structure:
            return "structure"
        case .union:
            return "union"
        case .function:
            return "function"
        }
    }
}


// MARK: - DefIdMap 管理类

/// DefId 映射表 - 管理所有定义的标识符
///
/// DefIdMap 是 DefId 系统的核心管理类，负责：
/// - 分配唯一的 DefId
/// - 通过名称查找 DefId
/// - 通过数字 ID 反向查找 DefId
///
/// ## 线程安全
/// 当前实现不是线程安全的。如果需要在多线程环境中使用，
/// 调用者需要自行处理同步。
///
/// ## 示例
/// ```swift
/// let defIdMap = DefIdMap()
///
/// // 分配新的 DefId
/// let parserDefId = defIdMap.allocate(
///     modulePath: ["expr_eval", "frontend"],
///     name: "Parser",
///     kind: .type(.structure),
///     sourceFile: "parser.koral"
/// )
///
/// // 查找 DefId
/// if let found = defIdMap.lookup(
///     modulePath: ["expr_eval", "frontend"],
///     name: "Parser"
/// ) {
///     print("Found: \(found)")
/// }
/// ```
public class DefIdMap {
    
    // MARK: - 私有属性
    
    /// 下一个可用的 ID
    private var nextId: UInt64 = 0
    
    /// 名称到 DefId 的映射（用于查找）
    ///
    /// 键的格式为 "modulePath.name" 或 "modulePath.name@sourceFile"
    private var nameToDefId: [String: DefId] = [:]
    
    /// ID 到 DefId 的映射（用于反向查找）
    private var idToDefId: [UInt64: DefId] = [:]
    
    // MARK: - 初始化
    
    /// 创建一个新的空 DefIdMap
    public init() {}
    
    // MARK: - 公共方法
    
    /// 分配新的 DefId
    ///
    /// 为给定的定义分配一个新的唯一 DefId。如果已经存在相同的定义，
    /// 将返回新分配的 DefId（覆盖旧的）。
    ///
    /// - Parameters:
    ///   - modulePath: 模块路径（如 ["expr_eval", "frontend"]）
    ///   - name: 定义名称
    ///   - kind: 定义类型
    ///   - sourceFile: 源文件路径
    /// - Returns: 新分配的 DefId
    ///
    /// ## 示例
    /// ```swift
    /// let defId = defIdMap.allocate(
    ///     modulePath: ["mymodule"],
    ///     name: "MyType",
    ///     kind: .type(.structure),
    ///     sourceFile: "mytype.koral"
    /// )
    /// ```
    public func allocate(
        modulePath: [String],
        name: String,
        kind: DefKind,
        sourceFile: String
    ) -> DefId {
        let id = nextId
        nextId += 1
        
        let defId = DefId(
            modulePath: modulePath,
            name: name,
            kind: kind,
            sourceFile: sourceFile,
            id: id
        )
        
        // Store with sourceFile key for precise lookup (private symbols)
        let keyWithFile = makeKey(modulePath: modulePath, name: name, sourceFile: sourceFile)
        nameToDefId[keyWithFile] = defId
        
        // Also store without sourceFile key for general lookup (public symbols)
        let keyWithoutFile = makeKey(modulePath: modulePath, name: name, sourceFile: nil)
        nameToDefId[keyWithoutFile] = defId
        
        idToDefId[id] = defId
        
        return defId
    }

    /// 注册已有的 DefId
    ///
    /// 用于在不重新分配 ID 的情况下将已有 DefId 纳入冲突检测与查找。
    /// - Parameter defId: 已有的 DefId
    public func register(_ defId: DefId) {
        // Store with sourceFile key for precise lookup (private symbols)
        let keyWithFile = makeKey(modulePath: defId.modulePath, name: defId.name, sourceFile: defId.sourceFile)
        nameToDefId[keyWithFile] = defId

        // Also store without sourceFile key for general lookup (public symbols)
        let keyWithoutFile = makeKey(modulePath: defId.modulePath, name: defId.name, sourceFile: nil)
        nameToDefId[keyWithoutFile] = defId

        idToDefId[defId.id] = defId

        if defId.id >= nextId {
            nextId = defId.id + 1
        }
    }
    
    /// 查找 DefId
    ///
    /// 根据模块路径和名称查找 DefId。如果提供了 sourceFile，
    /// 将使用更精确的键进行查找（用于 private 符号）。
    ///
    /// - Parameters:
    ///   - modulePath: 模块路径
    ///   - name: 定义名称
    ///   - sourceFile: 源文件路径（可选，用于 private 符号查找）
    /// - Returns: 找到的 DefId，如果不存在则返回 nil
    ///
    /// ## 查找策略
    /// 1. 如果提供了 sourceFile，首先尝试使用带文件路径的键查找
    /// 2. 如果未找到或未提供 sourceFile，使用不带文件路径的键查找
    ///
    /// ## 示例
    /// ```swift
    /// // 查找公共符号
    /// let publicDefId = defIdMap.lookup(
    ///     modulePath: ["mymodule"],
    ///     name: "PublicType"
    /// )
    ///
    /// // 查找私有符号
    /// let privateDefId = defIdMap.lookup(
    ///     modulePath: ["mymodule"],
    ///     name: "PrivateType",
    ///     sourceFile: "mytype.koral"
    /// )
    /// ```
    public func lookup(
        modulePath: [String],
        name: String,
        sourceFile: String? = nil
    ) -> DefId? {
        // 如果提供了 sourceFile，首先尝试带文件路径的键
        if let file = sourceFile {
            let keyWithFile = makeKey(modulePath: modulePath, name: name, sourceFile: file)
            if let defId = nameToDefId[keyWithFile] {
                return defId
            }
        }
        
        // 尝试不带文件路径的键（用于公共符号）
        let keyWithoutFile = makeKey(modulePath: modulePath, name: name, sourceFile: nil)
        return nameToDefId[keyWithoutFile]
    }
    
    /// 通过 ID 查找 DefId
    ///
    /// 使用数字 ID 进行反向查找。这是最快的查找方式。
    ///
    /// - Parameter id: DefId 的唯一数字 ID
    /// - Returns: 找到的 DefId，如果不存在则返回 nil
    ///
    /// ## 示例
    /// ```swift
    /// if let defId = defIdMap.lookupById(42) {
    ///     print("Found: \(defId.qualifiedName)")
    /// }
    /// ```
    public func lookupById(_ id: UInt64) -> DefId? {
        return idToDefId[id]
    }
    
    /// 获取所有已分配的 DefId 数量
    public var count: Int {
        return idToDefId.count
    }
    
    /// 获取所有已分配的 DefId
    ///
    /// 返回所有已分配的 DefId 的数组，按 ID 排序。
    public var allDefIds: [DefId] {
        return idToDefId.values.sorted { $0.id < $1.id }
    }
    
    /// 检测 C 标识符冲突
    ///
    /// 检查所有已分配的 DefId 是否存在 C 标识符冲突。
    /// 如果存在冲突，返回冲突的 DefId 对列表。
    ///
    /// - Returns: 冲突的 DefId 对数组，每对包含两个具有相同 C 标识符的 DefId
    public func detectCIdentifierConflicts() -> [(DefId, DefId)] {
        var cIdentifierToDefIds: [String: [DefId]] = [:]
        
        for defId in allDefIds {
            let cId = defId.cIdentifier
            cIdentifierToDefIds[cId, default: []].append(defId)
        }
        
        var conflicts: [(DefId, DefId)] = []
        for (_, defIds) in cIdentifierToDefIds {
            if defIds.count > 1 {
                // Report all pairs of conflicts
                for i in 0..<defIds.count {
                    for j in (i+1)..<defIds.count {
                        conflicts.append((defIds[i], defIds[j]))
                    }
                }
            }
        }
        
        return conflicts
    }
    
    /// 生成唯一的 C 标识符（带冲突解决）
    ///
    /// 如果给定的 DefId 的 C 标识符与其他 DefId 冲突，
    /// 则添加后缀以确保唯一性。
    ///
    /// - Parameter defId: 要生成 C 标识符的 DefId
    /// - Returns: 唯一的 C 标识符
    public func uniqueCIdentifier(for defId: DefId) -> String {
        let baseCId = defId.cIdentifier
        
        // Check if there are other DefIds with the same C identifier
        var conflictCount = 0
        var myIndex = 0
        
        for other in allDefIds {
            if other.cIdentifier == baseCId {
                if other.id < defId.id {
                    conflictCount += 1
                }
                if other.id == defId.id {
                    myIndex = conflictCount
                }
            }
        }
        
        // If no conflicts, return the base identifier
        if myIndex == 0 {
            return baseCId
        }
        
        // Add suffix to resolve conflict
        return "\(baseCId)_\(myIndex)"
    }
    
    /// 检查是否存在指定的定义
    ///
    /// - Parameters:
    ///   - modulePath: 模块路径
    ///   - name: 定义名称
    ///   - sourceFile: 源文件路径（可选）
    /// - Returns: 如果存在则返回 true
    public func contains(
        modulePath: [String],
        name: String,
        sourceFile: String? = nil
    ) -> Bool {
        return lookup(modulePath: modulePath, name: name, sourceFile: sourceFile) != nil
    }
    
    // MARK: - 私有方法
    
    /// 生成查找键
    ///
    /// 将模块路径、名称和可选的源文件路径组合成一个唯一的字符串键。
    ///
    /// - Parameters:
    ///   - modulePath: 模块路径
    ///   - name: 定义名称
    ///   - sourceFile: 源文件路径（可选）
    /// - Returns: 生成的键字符串
    ///
    /// ## 键格式
    /// - 不带 sourceFile: "module1.module2.name"
    /// - 带 sourceFile: "module1.module2.name@filename.koral"
    private func makeKey(modulePath: [String], name: String, sourceFile: String?) -> String {
        var parts = modulePath
        parts.append(name)
        if let file = sourceFile {
            parts.append("@\(file)")
        }
        return parts.joined(separator: ".")
    }
}

// MARK: - CustomStringConvertible

extension DefIdMap: CustomStringConvertible {
    public var description: String {
        let defIds = allDefIds.map { "  \($0)" }.joined(separator: "\n")
        return "DefIdMap(\(count) definitions):\n\(defIds)"
    }
}

import Foundation

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
    /// 不透明类型（foreign type）
    case opaque
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
/// 它是一个纯索引（UInt64），所有元数据由 DefIdMap 统一管理。
public struct DefId: Hashable, Equatable {
    /// 唯一数字 ID（用于快速比较）
    ///
    /// 由 DefIdMap 分配的全局唯一数字标识符，用于高效的相等性比较和哈希。
    public let id: UInt64
    
    /// 创建一个新的 DefId
    ///
    /// - Parameter id: 唯一数字 ID
    public init(id: UInt64) {
        self.id = id
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
    
    // MARK: - Metadata Queries
    
    /// 通过 DefIdMap 查询模块路径
    public func modulePath(in map: DefIdMap) -> [String]? {
        return map.getModulePath(self)
    }
    
    /// 通过 DefIdMap 查询名称
    public func name(in map: DefIdMap) -> String? {
        return map.getName(self)
    }
    
    /// 通过 DefIdMap 查询源文件
    public func sourceFile(in map: DefIdMap) -> String? {
        return map.getSourceFile(self)
    }
    
    /// 通过 DefIdMap 查询定义类型
    public func kind(in map: DefIdMap) -> DefKind? {
        return map.getKind(self)
    }
    
    /// 通过 DefIdMap 查询访问修饰符
    public func access(in map: DefIdMap) -> AccessModifier? {
        return map.getAccess(self)
    }
    
    /// 通过 DefIdMap 查询诊断信息
    public func span(in map: DefIdMap) -> SourceSpan? {
        return map.getSpan(self)
    }
}

// MARK: - CustomStringConvertible

extension DefId: CustomStringConvertible {
    public var description: String {
        return "DefId(id: \(id))"
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
        case .opaque:
            return "opaque"
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
    public struct SymbolInfo {
        public let type: Type
        public let kind: SymbolKind
        public let methodKind: CompilerMethodKind
        public let isMutable: Bool

        public init(
            type: Type,
            kind: SymbolKind,
            methodKind: CompilerMethodKind,
            isMutable: Bool
        ) {
            self.type = type
            self.kind = kind
            self.methodKind = methodKind
            self.isMutable = isMutable
        }
    }

    public struct ImportRecord {
        public let originalDefId: DefId
        public let importKind: ImportKind
        public let fromModule: [String]

        public init(
            originalDefId: DefId,
            importKind: ImportKind,
            fromModule: [String]
        ) {
            self.originalDefId = originalDefId
            self.importKind = importKind
            self.fromModule = fromModule
        }
    }

    public struct GenericStructTemplateInfo {
        public let typeParameters: [TypeParameterDecl]
        public let parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)]

        public init(
            typeParameters: [TypeParameterDecl],
            parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)]
        ) {
            self.typeParameters = typeParameters
            self.parameters = parameters
        }
    }

    public struct GenericUnionTemplateInfo {
        public let typeParameters: [TypeParameterDecl]
        public let cases: [UnionCaseDeclaration]

        public init(
            typeParameters: [TypeParameterDecl],
            cases: [UnionCaseDeclaration]
        ) {
            self.typeParameters = typeParameters
            self.cases = cases
        }
    }

    public struct GenericFunctionTemplateInfo {
        public let typeParameters: [TypeParameterDecl]
        public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
        public let returnType: TypeNode
        public let body: ExpressionNode
        public var checkedBody: TypedExpressionNode?
        public var checkedParameters: [Symbol]?
        public var checkedReturnType: Type?

        public init(
            typeParameters: [TypeParameterDecl],
            parameters: [(name: String, mutable: Bool, type: TypeNode)],
            returnType: TypeNode,
            body: ExpressionNode,
            checkedBody: TypedExpressionNode? = nil,
            checkedParameters: [Symbol]? = nil,
            checkedReturnType: Type? = nil
        ) {
            self.typeParameters = typeParameters
            self.parameters = parameters
            self.returnType = returnType
            self.body = body
            self.checkedBody = checkedBody
            self.checkedParameters = checkedParameters
            self.checkedReturnType = checkedReturnType
        }
    }
    public struct Metadata: Equatable, Hashable {
        public let modulePath: [String]
        public let name: String
        public let kind: DefKind
        public let sourceFile: String
        public let access: AccessModifier
        public let span: SourceSpan
        
        public init(
            modulePath: [String],
            name: String,
            kind: DefKind,
            sourceFile: String,
            access: AccessModifier,
            span: SourceSpan
        ) {
            self.modulePath = modulePath
            self.name = name
            self.kind = kind
            self.sourceFile = sourceFile
            self.access = access
            self.span = span
        }
    }

    public struct StructTypeInfo {
        public let members: [(name: String, type: Type, mutable: Bool, access: AccessModifier)]
        public let isGenericInstantiation: Bool
        public let typeArguments: [Type]?
        public let templateName: String?  // 泛型模板名称

        public init(
            members: [(name: String, type: Type, mutable: Bool, access: AccessModifier)],
            isGenericInstantiation: Bool,
            typeArguments: [Type]?,
            templateName: String? = nil
        ) {
            self.members = members
            self.isGenericInstantiation = isGenericInstantiation
            self.typeArguments = typeArguments
            self.templateName = templateName
        }
    }

    public struct UnionTypeInfo {
        public let cases: [UnionCase]
        public let isGenericInstantiation: Bool
        public let typeArguments: [Type]?
        public let templateName: String?  // 泛型模板名称

        public init(
            cases: [UnionCase],
            isGenericInstantiation: Bool,
            typeArguments: [Type]?,
            templateName: String? = nil
        ) {
            self.cases = cases
            self.isGenericInstantiation = isGenericInstantiation
            self.typeArguments = typeArguments
            self.templateName = templateName
        }
    }
    
    // MARK: - 私有属性
    
    /// 下一个可用的 ID
    private var nextId: UInt64 = 0
    
    /// 名称到 DefId 的映射（用于查找）
    ///
    /// 键的格式为 "modulePath.name" 或 "modulePath.name@sourceFile"
    private var nameToDefId: [String: DefId] = [:]
    
    /// ID 到元数据的映射（用于反向查找）
    private var idToMetadata: [UInt64: Metadata] = [:]

    /// DefId 到类型的映射（用于占位类型或快速查找）
    private var typeMap: [UInt64: Type] = [:]

    /// DefId 到函数签名的映射
    private var signatureMap: [UInt64: FunctionSignature] = [:]

    /// DefId 到结构体信息的映射
    private var structInfoMap: [UInt64: StructTypeInfo] = [:]

    /// DefId 到联合类型信息的映射
    private var unionInfoMap: [UInt64: UnionTypeInfo] = [:]

    /// DefId 到 FFI 结构体字段的映射
    private var foreignStructFields: [UInt64: [(name: String, type: Type)]] = [:]

    /// DefId 到 C 名称的映射（用于 foreign type 的 cname）
    private var cnameMap: [UInt64: String] = [:]

    /// DefId 到符号信息的映射
    private var symbolInfoMap: [UInt64: SymbolInfo] = [:]

    /// 导入记录映射（导入后的 DefId -> ImportRecord）
    private var importRecords: [UInt64: ImportRecord] = [:]

    /// 泛型模板映射（名称 -> DefId）
    private var genericStructTemplates: [String: DefId] = [:]
    private var genericUnionTemplates: [String: DefId] = [:]
    private var genericFunctionTemplates: [String: DefId] = [:]

    /// 泛型模板详细信息
    private var genericStructTemplateInfo: [UInt64: GenericStructTemplateInfo] = [:]
    private var genericUnionTemplateInfo: [UInt64: GenericUnionTemplateInfo] = [:]
    private var genericFunctionTemplateInfo: [UInt64: GenericFunctionTemplateInfo] = [:]
    
    // MARK: - 初始化
    
    /// 创建一个新的空 DefIdMap
    public init() {}

    /// 清理类型相关信息（保留 DefId 元数据）
    public func clearTypeInfo() {
        typeMap.removeAll()
        signatureMap.removeAll()
        structInfoMap.removeAll()
        unionInfoMap.removeAll()
        foreignStructFields.removeAll()
    }
    
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
        sourceFile: String,
        access: AccessModifier = .protected,
        span: SourceSpan = .unknown
    ) -> DefId {
        let isLocalSymbol = modulePath.isEmpty && sourceFile.isEmpty && kind == .variable

        // Reuse existing DefId for non-local symbols when possible
        if access == .private {
            let keyWithFile = makeKey(modulePath: modulePath, name: name, sourceFile: sourceFile)
            if let existing = nameToDefId[keyWithFile],
               let metadata = idToMetadata[existing.id],
               metadata.kind == kind {
                return existing
            }
        }

        let id = nextId
        nextId += 1
        let defId = DefId(id: id)
        let metadata = Metadata(
            modulePath: modulePath,
            name: name,
            kind: kind,
            sourceFile: sourceFile,
            access: access,
            span: span
        )
        
        if !isLocalSymbol {
            // Store with sourceFile key for precise lookup (private symbols)
            let keyWithFile = makeKey(modulePath: modulePath, name: name, sourceFile: sourceFile)
            nameToDefId[keyWithFile] = defId
            
            // Also store without sourceFile key for general lookup (public symbols)
            let keyWithoutFile = makeKey(modulePath: modulePath, name: name, sourceFile: nil)
            nameToDefId[keyWithoutFile] = defId
        }
        
        idToMetadata[id] = metadata
        
        return defId
    }

    /// 注册已有的 DefId
    ///
    /// 用于在不重新分配 ID 的情况下将已有 DefId 纳入冲突检测与查找。
    /// - Parameter defId: 已有的 DefId
    public func register(_ defId: DefId, metadata: Metadata) {
        // Store with sourceFile key for precise lookup (private symbols)
        let keyWithFile = makeKey(modulePath: metadata.modulePath, name: metadata.name, sourceFile: metadata.sourceFile)
        nameToDefId[keyWithFile] = defId

        // Also store without sourceFile key for general lookup (public symbols)
        let keyWithoutFile = makeKey(modulePath: metadata.modulePath, name: metadata.name, sourceFile: nil)
        nameToDefId[keyWithoutFile] = defId

        idToMetadata[defId.id] = metadata

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
        guard idToMetadata[id] != nil else {
            return nil
        }
        return DefId(id: id)
    }
    
    /// 获取所有已分配的 DefId 数量
    public var count: Int {
        return idToMetadata.count
    }
    
    /// 获取所有已分配的 DefId
    ///
    /// 返回所有已分配的 DefId 的数组，按 ID 排序。
    public var allDefIds: [DefId] {
        return idToMetadata.keys.sorted().map { DefId(id: $0) }
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
            guard let cId = getCIdentifier(defId) else {
                continue
            }
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
        let baseCId = getCIdentifier(defId) ?? ""
        
        // Check if there are other DefIds with the same C identifier
        var conflictCount = 0
        var myIndex = 0
        
        for other in allDefIds {
            if getCIdentifier(other) == baseCId {
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

    // MARK: - Metadata Queries
    
    public func metadata(for defId: DefId) -> Metadata? {
        return idToMetadata[defId.id]
    }
    
    public func getModulePath(_ defId: DefId) -> [String]? {
        return idToMetadata[defId.id]?.modulePath
    }
    
    public func getName(_ defId: DefId) -> String? {
        return idToMetadata[defId.id]?.name
    }
    
    public func getSourceFile(_ defId: DefId) -> String? {
        return idToMetadata[defId.id]?.sourceFile
    }
    
    public func getKind(_ defId: DefId) -> DefKind? {
        return idToMetadata[defId.id]?.kind
    }
    
    public func getAccess(_ defId: DefId) -> AccessModifier? {
        return idToMetadata[defId.id]?.access
    }
    
    public func getSpan(_ defId: DefId) -> SourceSpan? {
        return idToMetadata[defId.id]?.span
    }
    
    public func getQualifiedName(_ defId: DefId) -> String? {
        guard let metadata = idToMetadata[defId.id] else {
            return nil
        }
        var parts = metadata.modulePath
        parts.append(metadata.name)
        return parts.joined(separator: ".")
    }
    
    public func getCIdentifier(_ defId: DefId) -> String? {
        guard let metadata = idToMetadata[defId.id] else {
            return nil
        }
        let isPrivate = metadata.access == .private
        return generateCIdentifier(
            modulePath: metadata.modulePath,
            name: metadata.name,
            isPrivate: isPrivate,
            sourceFile: metadata.sourceFile
        )
    }

    // MARK: - Typed Definition Queries/Updates

    public func addType(defId: DefId, type: Type) {
        typeMap[defId.id] = type
    }

    public func addStructInfo(
        defId: DefId,
        members: [(name: String, type: Type, mutable: Bool, access: AccessModifier)],
        isGenericInstantiation: Bool = false,
        typeArguments: [Type]? = nil,
        templateName: String? = nil
    ) {
        structInfoMap[defId.id] = StructTypeInfo(
            members: members,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments,
            templateName: templateName
        )
    }

    public func addUnionInfo(
        defId: DefId,
        cases: [UnionCase],
        isGenericInstantiation: Bool = false,
        typeArguments: [Type]? = nil,
        templateName: String? = nil
    ) {
        unionInfoMap[defId.id] = UnionTypeInfo(
            cases: cases,
            isGenericInstantiation: isGenericInstantiation,
            typeArguments: typeArguments,
            templateName: templateName
        )
    }

    public func addSignature(defId: DefId, signature: FunctionSignature) {
        signatureMap[defId.id] = signature
    }

    public func lookupType(defId: DefId) -> Type? {
        return typeMap[defId.id]
    }

    public func getStructMembers(_ defId: DefId) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier)]? {
        return structInfoMap[defId.id]?.members
    }

    public func getUnionCases(_ defId: DefId) -> [UnionCase]? {
        return unionInfoMap[defId.id]?.cases
    }

    public func setForeignStructFields(_ defId: DefId, _ fields: [(name: String, type: Type)]) {
        foreignStructFields[defId.id] = fields
    }

    public func getForeignStructFields(_ defId: DefId) -> [(name: String, type: Type)]? {
        return foreignStructFields[defId.id]
    }

    public func isForeignStruct(_ defId: DefId) -> Bool {
        return foreignStructFields[defId.id] != nil
    }

    public func setCname(_ defId: DefId, _ cname: String) {
        cnameMap[defId.id] = cname
    }

    public func getCname(_ defId: DefId) -> String? {
        return cnameMap[defId.id]
    }

    public func isGenericInstantiation(_ defId: DefId) -> Bool? {
        if let info = structInfoMap[defId.id] {
            return info.isGenericInstantiation
        }
        if let info = unionInfoMap[defId.id] {
            return info.isGenericInstantiation
        }
        return nil
    }

    public func getTypeArguments(_ defId: DefId) -> [Type]? {
        if let info = structInfoMap[defId.id] {
            return info.typeArguments
        }
        if let info = unionInfoMap[defId.id] {
            return info.typeArguments
        }
        return nil
    }

    /// 获取泛型实例化的模板名称
    ///
    /// 对于泛型类型实例化（如 `List_I`），返回原始模板名称（如 `List`）。
    ///
    /// - Parameter defId: 要查询的 DefId
    /// - Returns: 模板名称，如果不是泛型实例化或未找到则返回 nil
    public func getTemplateName(_ defId: DefId) -> String? {
        if let info = structInfoMap[defId.id] {
            return info.templateName
        }
        if let info = unionInfoMap[defId.id] {
            return info.templateName
        }
        return nil
    }

    public func lookupSignature(defId: DefId) -> FunctionSignature? {
        return signatureMap[defId.id]
    }

    // MARK: - Symbol Info

    public func addSymbolInfo(
        defId: DefId,
        type: Type,
        kind: SymbolKind,
        methodKind: CompilerMethodKind,
        isMutable: Bool
    ) {
        symbolInfoMap[defId.id] = SymbolInfo(
            type: type,
            kind: kind,
            methodKind: methodKind,
            isMutable: isMutable
        )
    }

    public func getSymbolType(_ defId: DefId) -> Type? {
        return symbolInfoMap[defId.id]?.type
    }

    public func getSymbolKind(_ defId: DefId) -> SymbolKind? {
        return symbolInfoMap[defId.id]?.kind
    }

    public func getSymbolMethodKind(_ defId: DefId) -> CompilerMethodKind? {
        return symbolInfoMap[defId.id]?.methodKind
    }

    public func isSymbolMutable(_ defId: DefId) -> Bool? {
        return symbolInfoMap[defId.id]?.isMutable
    }

    // MARK: - Import Records

    public func recordImport(
        importedDefId: DefId,
        originalDefId: DefId,
        importKind: ImportKind,
        fromModule: [String]
    ) {
        importRecords[importedDefId.id] = ImportRecord(
            originalDefId: originalDefId,
            importKind: importKind,
            fromModule: fromModule
        )
    }

    public func getOriginalDefId(_ defId: DefId) -> DefId? {
        return importRecords[defId.id]?.originalDefId
    }

    public func isImported(_ defId: DefId) -> Bool {
        return importRecords[defId.id] != nil
    }

    // MARK: - Generic Template Info

    public func registerGenericStructTemplate(name: String, defId: DefId, info: GenericStructTemplateInfo) {
        genericStructTemplates[name] = defId
        genericStructTemplateInfo[defId.id] = info
    }

    public func registerGenericUnionTemplate(name: String, defId: DefId, info: GenericUnionTemplateInfo) {
        genericUnionTemplates[name] = defId
        genericUnionTemplateInfo[defId.id] = info
    }

    public func registerGenericFunctionTemplate(name: String, defId: DefId, info: GenericFunctionTemplateInfo) {
        genericFunctionTemplates[name] = defId
        genericFunctionTemplateInfo[defId.id] = info
    }

    public func lookupGenericStructTemplateDefId(_ name: String) -> DefId? {
        return genericStructTemplates[name]
    }

    public func lookupGenericUnionTemplateDefId(_ name: String) -> DefId? {
        return genericUnionTemplates[name]
    }

    public func lookupGenericFunctionTemplateDefId(_ name: String) -> DefId? {
        return genericFunctionTemplates[name]
    }

    public func getGenericStructTemplateInfo(_ defId: DefId) -> GenericStructTemplateInfo? {
        return genericStructTemplateInfo[defId.id]
    }

    public func getGenericUnionTemplateInfo(_ defId: DefId) -> GenericUnionTemplateInfo? {
        return genericUnionTemplateInfo[defId.id]
    }

    public func getGenericFunctionTemplateInfo(_ defId: DefId) -> GenericFunctionTemplateInfo? {
        return genericFunctionTemplateInfo[defId.id]
    }

    public func genericStructTemplatesSnapshot() -> [String: DefId] {
        return genericStructTemplates
    }

    public func genericUnionTemplatesSnapshot() -> [String: DefId] {
        return genericUnionTemplates
    }

    public func genericFunctionTemplatesSnapshot() -> [String: DefId] {
        return genericFunctionTemplates
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
        let defIds = allDefIds.map {
            let name = getQualifiedName($0) ?? "<unknown>"
            let kind = getKind($0)?.description ?? "unknown"
            return "  DefId(\(name), kind: \(kind), id: \($0.id))"
        }.joined(separator: "\n")
        return "DefIdMap(\(count) definitions):\n\(defIds)"
    }
}


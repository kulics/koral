import Foundation

/// 导入图 - 记录模块间的导入关系
///
/// 用于在可见性检查阶段判断符号是否可以直接访问。
public struct ImportGraph {
    /// 导入边：(源模块路径, 目标模块路径, 导入类型, 来源文件, `using` 的位置, 过滤)
    ///
    /// `span` is where the `using` is written. A collision between an imported
    /// name and something already in scope is reported there -- that is the
    /// line the reader has to edit (§3.3).
    ///
    /// `filter` narrows a batch (`{ ... }`) edge: `!name` entries drop a member
    /// and `name as alias` entries re-spell it. Empty means the batch comes
    /// whole. It is always empty on non-batch edges (§3.3).
    public private(set) var edges: [(source: [String], target: [String], kind: ImportKind, sourceFile: String?, span: SourceSpan, filter: [UsingModuleItem])]

    /// 符号导入：(导入发生的模块路径, 目标模块路径, 符号名称, 导入类型, 来源文件, `using` 的位置)
    public private(set) var symbolImports: [(module: [String], target: [String], symbol: String, originalSymbol: String, kind: ImportKind, sourceFile: String?, span: SourceSpan)]
    
    /// 创建空的导入图
    public init() {
        self.edges = []
        self.symbolImports = []
    }

    /// 合并另一个 ImportGraph
    public mutating func merge(_ other: ImportGraph) {
        edges.append(contentsOf: other.edges)
        symbolImports.append(contentsOf: other.symbolImports)
    }
    
    /// 添加模块导入
    ///
    /// - Parameters:
    ///   - from: 源模块路径
    ///   - to: 目标模块路径
    ///   - kind: 导入类型
    ///   - sourceFile: 若为 private using，则限定为该文件可见；nil 表示模块级可见
    public mutating func addModuleImport(from: [String], to: [String], kind: ImportKind, sourceFile: String? = nil, span: SourceSpan = .unknown, filter: [UsingModuleItem] = []) {
        edges.append((source: from, target: to, kind: kind, sourceFile: sourceFile, span: span, filter: filter))
    }
    
    /// 添加符号导入（using module::path { Symbol }）
    ///
    /// - Parameters:
    ///   - module: 导入发生的模块路径
    ///   - target: 目标模块路径
    ///   - symbol: 符号名称
    ///   - kind: 导入类型
    ///   - sourceFile: 若为 private using，则限定为该文件可见；nil 表示模块级可见
    public mutating func addSymbolImport(
        module: [String],
        target: [String],
        symbol: String,
        originalSymbol: String? = nil,
        kind: ImportKind,
        sourceFile: String? = nil,
        span: SourceSpan = .unknown
    ) {
        symbolImports.append((
            module: module,
            target: target,
            symbol: symbol,
            originalSymbol: originalSymbol ?? symbol,
            kind: kind,
            sourceFile: sourceFile,
            span: span
        ))
    }

    public func resolveAliasedSymbol(
        alias: String,
        inModule: [String],
        inSourceFile: String? = nil
    ) -> (target: [String], originalSymbol: String)? {
        for entry in symbolImports.reversed() {
            if entry.module == inModule
                && entry.symbol == alias
                && (entry.sourceFile == nil || entry.sourceFile == inSourceFile) {
                return (entry.target, entry.originalSymbol)
            }
        }
        return nil
    }
    
    /// 获取符号的导入类型
    ///
    /// - Parameters:
    ///   - symbolModulePath: 符号所在的模块路径
    ///   - symbolName: 符号名称
    ///   - inModule: 当前模块路径
    ///   - inSourceFile: 当前源文件；用于 private using 的文件级可见性
    /// - Returns: 导入类型
    public func getImportKind(
        symbolModulePath: [String],
        symbolName: String?,
        inModule: [String],
        inSourceFile: String? = nil
    ) -> ImportKind {
        // 本地定义
        if symbolModulePath == inModule {
            return .local
        }
        
        // 成员导入. The LOCAL spelling is what grants access: `a as b` makes
        // `b` nameable and leaves `a` unnamed (§3.3). Matching `originalSymbol`
        // here would hand out the pre-rename spelling too.
        if let name = symbolName {
            for symbolImport in symbolImports {
                if symbolImport.module == inModule &&
                    symbolImport.target == symbolModulePath &&
                    symbolImport.symbol == name &&
                    (symbolImport.sourceFile == nil || symbolImport.sourceFile == inSourceFile) {
                    return symbolImport.kind
                }
            }
        }
        
        // 模块/批量导入
        for edge in edges {
            guard edge.source == inModule,
                  (edge.sourceFile == nil || edge.sourceFile == inSourceFile) else {
                continue
            }

            switch edge.kind {
            case .batchImport:
                // 模块导入边只匹配目标模块本身，
                // 不应通过前缀匹配自动扩散到同名前缀的其它模块。
                if symbolModulePath == edge.target {
                    // `{ !a, ... }` drops a member and `{ a as b, ... }`
                    // re-spells it; either way it does not arrive under its own
                    // name (§3.3).
                    if let name = symbolName, !batchFilterAllows(edge.filter, spelling: name) {
                        continue
                    }
                    return edge.kind
                }
            case .moduleImport:
                if symbolModulePath == edge.target {
                    return edge.kind
                }
            default:
                break
            }
        }
        
        return .moduleImport
    }
}


/// Whether `spelling` lands under its own name from a filtered batch (§3.3).
///
/// A name the filter mentions does not: `!a` drops it and `a as b` re-spells
/// it, and the re-spelling is carried by its own symbol edge so it resolves
/// through the ordinary import layer. Everything the filter is silent about
/// comes whole.
public func batchFilterAllows(_ filter: [UsingModuleItem], spelling: String) -> Bool {
    batchFilterLocalName(filter, name: spelling) == spelling
}

/// The spelling `name` lands under from a filtered batch (§3.3): `nil` when
/// the filter drops it, the alias when it re-spells it, the name unchanged
/// otherwise.
public func batchFilterLocalName(_ filter: [UsingModuleItem], name: String) -> String? {
    for item in filter where item.name == name {
        return item.excluded ? nil : (item.alias ?? name)
    }
    return name
}

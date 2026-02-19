import Foundation

/// 导入图 - 记录模块间的导入关系
///
/// 用于在可见性检查阶段判断符号是否可以直接访问。
public struct ImportGraph {
    /// 导入边：(源模块路径, 目标模块路径, 导入类型)
    public private(set) var edges: [(source: [String], target: [String], kind: ImportKind, sourceFile: String?)]
    
    /// 符号导入：(导入发生的模块路径, 目标模块路径, 符号名称, 导入类型)
    public private(set) var symbolImports: [(module: [String], target: [String], symbol: String, kind: ImportKind, sourceFile: String?)]
    
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
    public mutating func addModuleImport(from: [String], to: [String], kind: ImportKind, sourceFile: String? = nil) {
        edges.append((source: from, target: to, kind: kind, sourceFile: sourceFile))
    }
    
    /// 添加符号导入（using module.Symbol）
    ///
    /// - Parameters:
    ///   - module: 导入发生的模块路径
    ///   - target: 目标模块路径
    ///   - symbol: 符号名称
    ///   - kind: 导入类型
    ///   - sourceFile: 若为 private using，则限定为该文件可见；nil 表示模块级可见
    public mutating func addSymbolImport(module: [String], target: [String], symbol: String, kind: ImportKind, sourceFile: String? = nil) {
        symbolImports.append((module: module, target: target, symbol: symbol, kind: kind, sourceFile: sourceFile))
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
        
        // 成员导入
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
            if edge.source == inModule &&
                symbolModulePath.starts(with: edge.target) &&
                (edge.sourceFile == nil || edge.sourceFile == inSourceFile) {
                return edge.kind
            }
        }
        
        return .moduleImport
    }
}

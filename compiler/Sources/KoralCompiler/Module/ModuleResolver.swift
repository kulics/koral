import Foundation

// MARK: - Module Error Types

/// 模块系统错误类型
public enum ModuleError: Error, CustomStringConvertible {
    case fileNotFound(String, searchPath: String)
    case submoduleNotFound(String, parentPath: String)
    case missingIndexFile(String)
    case superOutOfBounds(span: SourceSpan)
    case externalModuleNotFound(String, searchPaths: [String])
    case circularDependency(path: [String])
    case invalidModulePath(String)
    
    public var description: String {
        switch self {
        case .fileNotFound(let file, let searchPath):
            return "File '\(file).koral' not found in '\(searchPath)'"
        case .submoduleNotFound(let name, let parentPath):
            return "Submodule '\(name)' not found (expected directory '\(parentPath)/\(name)/')"
        case .missingIndexFile(let path):
            return "Submodule at '\(path)' is missing 'index.koral' entry file"
        case .superOutOfBounds(let span):
            return "\(span): 'super' goes beyond the root module of the compilation unit"
        case .externalModuleNotFound(let name, let paths):
            return "External module '\(name)' not found. Searched in: \(paths.joined(separator: ", "))"
        case .circularDependency(let path):
            return "Circular dependency detected: \(path.joined(separator: " -> "))"
        case .invalidModulePath(let path):
            return "Invalid module path: '\(path)'"
        }
    }
}

// MARK: - Module Info

/// 模块信息
public class ModuleInfo {
    /// 模块路径（相对于编译单元根）
    public let path: [String]
    
    /// 入口文件路径（绝对路径）
    public let entryFile: String
    
    /// 模块目录（绝对路径）
    public var directory: String {
        return URL(fileURLWithPath: entryFile).deletingLastPathComponent().path
    }
    
    /// 合并的文件列表（绝对路径）
    public var mergedFiles: [String] = []
    
    /// 子模块
    public var submodules: [String: ModuleInfo] = [:]
    
    /// 父模块（根模块为 nil）
    public weak var parent: ModuleInfo?
    
    /// 是否为外部模块
    public let isExternal: Bool
    
    /// 已解析的 AST 节点（来自所有合并的文件）
    /// 每个元组包含 (节点, 来源文件路径)
    public var globalNodes: [(node: GlobalNode, sourceFile: String)] = []
    
    /// using 声明
    public var usingDeclarations: [UsingDeclaration] = []
    
    /// 符号表
    public var symbolTable: ModuleSymbolTable?
    
    public init(
        path: [String],
        entryFile: String,
        isExternal: Bool = false
    ) {
        self.path = path
        self.entryFile = entryFile
        self.isExternal = isExternal
    }
    
    /// 模块的完整路径字符串
    public var pathString: String {
        return path.isEmpty ? "<root>" : path.joined(separator: ".")
    }
}

// MARK: - Compilation Unit

/// 编译单元
public class CompilationUnit {
    /// 根模块
    public let rootModule: ModuleInfo
    
    /// 所有已加载的模块（路径字符串 -> 模块）
    public var loadedModules: [String: ModuleInfo] = [:]
    
    /// 外部模块缓存（模块名 -> 编译单元）
    public var externalModules: [String: CompilationUnit] = [:]
    
    public init(rootModule: ModuleInfo) {
        self.rootModule = rootModule
        self.loadedModules[rootModule.pathString] = rootModule
    }
    
    /// 获取所有全局节点（按依赖顺序）
    /// 保持原始 AST 名称，名称限定在 CodeGen 阶段处理
    public func getAllGlobalNodes() -> [GlobalNode] {
        var result: [GlobalNode] = []
        collectGlobalNodes(from: rootModule, into: &result)
        return result
    }
    
    /// 获取所有全局节点及其来源文件信息
    /// 用于 CodeGen 阶段生成正确的 C 名称
    public func getAllGlobalNodesWithSourceInfo() -> [(node: GlobalNode, sourceFile: String, modulePath: [String])] {
        var result: [(node: GlobalNode, sourceFile: String, modulePath: [String])] = []
        collectGlobalNodesWithSourceInfo(from: rootModule, into: &result)
        return result
    }
    
    private func collectGlobalNodes(from module: ModuleInfo, into result: inout [GlobalNode]) {
        // 先收集子模块的节点
        for (_, submodule) in module.submodules.sorted(by: { $0.key < $1.key }) {
            collectGlobalNodes(from: submodule, into: &result)
        }
        // 收集当前模块的节点（保持原始名称）
        for (node, _) in module.globalNodes {
            result.append(node)
        }
    }
    
    private func collectGlobalNodesWithSourceInfo(
        from module: ModuleInfo,
        into result: inout [(node: GlobalNode, sourceFile: String, modulePath: [String])]
    ) {
        // 先收集子模块的节点
        for (_, submodule) in module.submodules.sorted(by: { $0.key < $1.key }) {
            collectGlobalNodesWithSourceInfo(from: submodule, into: &result)
        }
        // 收集当前模块的节点（包含来源信息）
        for (node, sourceFile) in module.globalNodes {
            result.append((node: node, sourceFile: sourceFile, modulePath: module.path))
        }
    }
}


// MARK: - Module Resolver

/// 模块解析器
public class ModuleResolver {
    /// 标准库路径
    private var stdLibPath: String?
    
    /// 外部模块搜索路径
    private var externalPaths: [String] = []
    
    /// 当前正在解析的文件路径（用于循环依赖检测）
    private var resolvingFiles: Set<String> = []
    
    /// 文件管理器
    private let fileManager = FileManager.default
    
    public init(stdLibPath: String? = nil, externalPaths: [String] = []) {
        self.stdLibPath = stdLibPath
        self.externalPaths = externalPaths
    }
    
    /// 解析模块入口
    /// - Parameter entryFile: 入口文件路径
    /// - Returns: 编译单元
    public func resolveModule(entryFile: String) throws -> CompilationUnit {
        let absolutePath = URL(fileURLWithPath: entryFile).standardized.path
        
        let rootModule = ModuleInfo(
            path: [],
            entryFile: absolutePath,
            isExternal: false
        )
        
        let unit = CompilationUnit(rootModule: rootModule)
        
        // 解析入口文件
        try resolveFile(file: absolutePath, module: rootModule, unit: unit)
        
        return unit
    }
    
    /// 解析单个文件
    private func resolveFile(
        file: String,
        module: ModuleInfo,
        unit: CompilationUnit
    ) throws {
        // 循环依赖检测
        if resolvingFiles.contains(file) {
            // 同一编译单元内允许循环依赖，直接返回
            return
        }
        
        resolvingFiles.insert(file)
        defer { resolvingFiles.remove(file) }
        
        // 读取并解析文件
        let source = try String(contentsOfFile: file, encoding: .utf8)
        let lexer = Lexer(input: source)
        let parser = Parser(lexer: lexer)
        let ast = try parser.parse()
        
        guard case .program(let globalNodes) = ast else {
            throw ModuleError.invalidModulePath(file)
        }
        
        // 从 GlobalNode 中提取 using 声明并处理
        var nonUsingNodes: [GlobalNode] = []
        for node in globalNodes {
            if case .usingDeclaration(let using) = node {
                // 保存 using 声明
                module.usingDeclarations.append(using)
                // 处理 using 声明
                try resolveUsing(using: using, module: module, unit: unit, currentFile: file)
            } else {
                nonUsingNodes.append(node)
            }
        }
        
        // 将非 using 的全局节点添加到模块（包含来源文件信息）
        for node in nonUsingNodes {
            module.globalNodes.append((node: node, sourceFile: file))
        }
    }
    
    /// 解析 using 声明
    private func resolveUsing(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        switch using.pathKind {
        case .fileMerge:
            try resolveFileMerge(using: using, module: module, unit: unit)
        case .submodule:
            try resolveSubmodule(using: using, module: module, unit: unit)
        case .parent:
            try resolveParent(using: using, module: module, unit: unit)
        case .external:
            try resolveExternal(using: using, module: module, unit: unit)
        }
    }
    
    /// 解析文件合并: using "user"
    private func resolveFileMerge(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit
    ) throws {
        guard !using.pathSegments.isEmpty else {
            throw ModuleError.invalidModulePath("empty file merge path")
        }
        
        let filename = using.pathSegments[0]
        let filePath = module.directory + "/" + filename + ".koral"
        
        guard fileManager.fileExists(atPath: filePath) else {
            throw ModuleError.fileNotFound(filename, searchPath: module.directory)
        }
        
        // 检查是否已合并
        if module.mergedFiles.contains(filePath) {
            return // 已合并，跳过
        }
        
        module.mergedFiles.append(filePath)
        
        // 解析合并的文件（共享符号表）
        try resolveFile(file: filePath, module: module, unit: unit)
    }
    
    /// 解析子模块: using self.utils
    private func resolveSubmodule(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit
    ) throws {
        guard !using.pathSegments.isEmpty else {
            throw ModuleError.invalidModulePath("empty submodule path")
        }
        
        let submodName = using.pathSegments[0]
        let submodPath = module.directory + "/" + submodName
        let indexFile = submodPath + "/index.koral"
        
        guard fileManager.fileExists(atPath: submodPath) else {
            throw ModuleError.submoduleNotFound(submodName, parentPath: module.directory)
        }
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: submodPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ModuleError.submoduleNotFound(submodName, parentPath: module.directory)
        }
        
        guard fileManager.fileExists(atPath: indexFile) else {
            throw ModuleError.missingIndexFile(submodPath)
        }
        
        // 创建或获取子模块
        let submodule: ModuleInfo
        if let existing = module.submodules[submodName] {
            submodule = existing
        } else {
            submodule = ModuleInfo(
                path: module.path + [submodName],
                entryFile: indexFile,
                isExternal: false
            )
            submodule.parent = module
            module.submodules[submodName] = submodule
            unit.loadedModules[submodule.pathString] = submodule
            
            // 解析子模块
            try resolveFile(file: indexFile, module: submodule, unit: unit)
        }
        
        // 将子模块作为符号注册到当前模块的符号表
        // 访问修饰符：默认为 private，除非显式指定 public 或 protected
        let access = using.access == .default ? .private : using.access
        
        // 确保模块有符号表
        if module.symbolTable == nil {
            module.symbolTable = ModuleSymbolTable(module: module)
        }
        
        // 将子模块注册为模块符号
        try module.symbolTable?.addModuleSymbol(
            name: submodName,
            module: submodule,
            access: access,
            span: using.span,
            fromFile: module.entryFile
        )
        
        // 符号导入在 TypeChecker 阶段通过 nodeSourceInfoList 完成
        // 如果是批量导入，后续在符号表阶段处理
    }
    
    /// 解析父模块: using super.sibling
    private func resolveParent(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit
    ) throws {
        var current = module
        var segmentIndex = 0
        
        // 处理 super 链
        while segmentIndex < using.pathSegments.count
              && using.pathSegments[segmentIndex] == "super" {
            guard let parent = current.parent else {
                throw ModuleError.superOutOfBounds(span: using.span)
            }
            current = parent
            segmentIndex += 1
        }
        
        // 处理剩余路径（如果有）
        if segmentIndex < using.pathSegments.count {
            // 从父模块开始查找子模块
            let remainingPath = Array(using.pathSegments[segmentIndex...])
            let accessChecker = AccessChecker()
            
            for segment in remainingPath {
                // 通过符号表查找子模块符号
                // 子模块作为符号存储在父模块的符号表中
                if let symbolTable = current.symbolTable,
                   let symbol = symbolTable.lookupModuleSymbol(segment) {
                    // 使用通用的访问检查
                    try accessChecker.checkAccess(
                        symbol: symbol,
                        from: module,
                        fromFile: module.entryFile
                    )
                }
                
                if let submod = current.submodules[segment] {
                    current = submod
                } else {
                    // 尝试加载子模块
                    let submodPath = current.directory + "/" + segment
                    let indexFile = submodPath + "/index.koral"
                    
                    guard fileManager.fileExists(atPath: indexFile) else {
                        throw ModuleError.submoduleNotFound(segment, parentPath: current.directory)
                    }
                    
                    let submodule = ModuleInfo(
                        path: current.path + [segment],
                        entryFile: indexFile,
                        isExternal: false
                    )
                    submodule.parent = current
                    current.submodules[segment] = submodule
                    unit.loadedModules[submodule.pathString] = submodule
                    
                    try resolveFile(file: indexFile, module: submodule, unit: unit)
                    current = submodule
                }
            }
        }
        
        // 符号导入在 TypeChecker 阶段通过 nodeSourceInfoList 完成
    }
    
    /// 解析外部模块: using std
    private func resolveExternal(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit
    ) throws {
        guard !using.pathSegments.isEmpty else {
            throw ModuleError.invalidModulePath("empty external path")
        }
        
        let moduleName = using.pathSegments[0]
        
        // 检查是否已加载
        if let cached = unit.externalModules[moduleName] {
            // 使用缓存的外部模块
            // 符号导入在 TypeChecker 阶段通过 nodeSourceInfoList 完成
            _ = cached
            return
        }
        
        // 查找外部模块
        let modulePath = try findExternalModule(moduleName)
        
        // 加载外部模块（作为独立编译单元）
        let externalUnit = try resolveModule(entryFile: modulePath + "/index.koral")
        unit.externalModules[moduleName] = externalUnit
        
        // 符号导入在 TypeChecker 阶段通过 nodeSourceInfoList 完成
    }
    
    /// 查找外部模块路径
    private func findExternalModule(_ name: String) throws -> String {
        var searchPaths: [String] = []
        
        // 检查标准库
        if let stdPath = stdLibPath {
            let path = stdPath + "/" + name
            searchPaths.append(path)
            if fileManager.fileExists(atPath: path + "/index.koral") {
                return path
            }
        }
        
        // 检查外部路径
        for basePath in externalPaths {
            let path = basePath + "/" + name
            searchPaths.append(path)
            if fileManager.fileExists(atPath: path + "/index.koral") {
                return path
            }
        }
        
        throw ModuleError.externalModuleNotFound(name, searchPaths: searchPaths)
    }
}

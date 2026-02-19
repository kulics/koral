import Foundation

// MARK: - Module Error Types

/// 模块系统错误类型
public enum ModuleError: Error, CustomStringConvertible {
    case fileNotFound(String, searchPath: String)
    case submoduleNotFound(String, parentPath: String, span: SourceSpan)
    case missingEntryFile(submodName: String, expectedPath: String, span: SourceSpan)
    case superOutOfBounds(span: SourceSpan)
    case externalModuleNotFound(String, searchPaths: [String])
    case circularDependency(path: [String])
    case invalidModulePath(String)
    case duplicateUsing(String, span: SourceSpan)
    case parseError(file: String, underlying: Error)
    case invalidEntryFileName(filename: String, reason: String)
    
    public var description: String {
        switch self {
        case .fileNotFound(let file, let searchPath):
            return "File '\(file).koral' not found in '\(searchPath)'"
        case .submoduleNotFound(let name, let parentPath, let span):
            return "\(span): error: Submodule '\(name)' not found (expected directory '\(parentPath)/\(name)/')"
        case .missingEntryFile(let submodName, let expectedPath, let span):
            return "\(span): error: Submodule '\(submodName)' is missing entry file '\(expectedPath)'"
        case .superOutOfBounds(let span):
            return "\(span): error: 'super' goes beyond the root module of the compilation unit"
        case .externalModuleNotFound(let name, let paths):
            return "External module '\(name)' not found. Searched in: \(paths.joined(separator: ", "))"
        case .circularDependency(let path):
            return "Circular dependency detected: \(path.joined(separator: " -> "))"
        case .invalidModulePath(let path):
            return "Invalid module path: '\(path)'"
        case .duplicateUsing(let name, let span):
            return "\(span): error: Duplicate using declaration for '\(name)'"
        case .parseError(let file, let underlying):
            return "\(file): \(underlying)"
        case .invalidEntryFileName(let filename, let reason):
            return """
                Invalid entry file name '\(filename)': \(reason)
                Module names must be valid identifiers: start with a lowercase letter, \
                contain only lowercase letters, digits, and underscores.
                Examples: main, my_app, tool1
                """
        }
    }
}

// MARK: - Module Access Info

public struct ModuleAccessInfo {
    public let access: AccessModifier
    public let definedInFile: String
    public let span: SourceSpan

    public init(access: AccessModifier, definedInFile: String, span: SourceSpan) {
        self.access = access
        self.definedInFile = definedInFile
        self.span = span
    }
}

// MARK: - Module Name Validation

/// 验证文件名是否为有效的模块名标识符
/// - Parameter filename: 不含扩展名的文件名
/// - Returns: 验证结果，成功返回 nil，失败返回错误原因
public func validateModuleName(_ filename: String) -> String? {
    // 空文件名
    guard !filename.isEmpty else {
        return "Module name cannot be empty"
    }
    
    let chars = Array(filename)
    
    // 必须以小写字母开头
    guard let first = chars.first else {
        return "Module name cannot be empty"
    }
    
    // 检查第一个字符是否为小写 ASCII 字母
    guard first >= "a" && first <= "z" else {
        return "Module name must start with a lowercase letter (a-z)"
    }
    
    // 只能包含小写字母、数字和下划线
    for char in chars {
        let isLowercaseLetter = char >= "a" && char <= "z"
        let isDigit = char >= "0" && char <= "9"
        let isUnderscore = char == "_"
        
        if !isLowercaseLetter && !isDigit && !isUnderscore {
            return "Module name can only contain lowercase letters (a-z), digits (0-9), and underscores (_)"
        }
    }
    
    return nil
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

    /// 子模块访问控制信息
    public var submoduleAccesses: [String: ModuleAccessInfo] = [:]
    
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
        return path.joined(separator: ".")
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
    
    /// 导入图 - 记录模块间的导入关系
    public var importGraph: ImportGraph
    
    public init(rootModule: ModuleInfo) {
        self.rootModule = rootModule
        self.loadedModules[rootModule.pathString] = rootModule
        self.importGraph = ImportGraph()
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
    
    /// 计算子模块入口文件路径
    /// - Parameters:
    ///   - parentDirectory: 父模块目录
    ///   - submodName: 子模块名称
    /// - Returns: 入口文件的完整路径
    private func submoduleEntryPath(parentDirectory: String, submodName: String) -> String {
        return parentDirectory + "/" + submodName + "/" + submodName + ".koral"
    }
    
    /// 解析模块入口
    /// - Parameter entryFile: 入口文件路径
    /// - Returns: 编译单元
    public func resolveModule(entryFile: String) throws -> CompilationUnit {
        let absolutePath = URL(fileURLWithPath: entryFile).standardized.path
        
        // 提取文件名（不含扩展名）
        let filename = URL(fileURLWithPath: absolutePath)
            .deletingPathExtension()
            .lastPathComponent
        
        // 验证文件名
        if let error = validateModuleName(filename) {
            throw ModuleError.invalidEntryFileName(filename: filename, reason: error)
        }
        
        // 创建根模块，path 包含文件名
        let rootModule = ModuleInfo(
            path: [filename],
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
        
        let ast: ASTNode
        do {
            ast = try parser.parse()
        } catch {
            // 包装解析错误，添加文件名信息
            throw ModuleError.parseError(file: file, underlying: error)
        }
        
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
        // 记录导入到 ImportGraph
        recordImportToGraph(using: using, module: module, unit: unit, currentFile: currentFile)
        
        switch using.pathKind {
        case .fileMerge:
            try resolveFileMerge(using: using, module: module, unit: unit, currentFile: currentFile)
        case .submodule:
            try resolveSubmodule(using: using, module: module, unit: unit, currentFile: currentFile)
        case .parent:
            try resolveParent(using: using, module: module, unit: unit, currentFile: currentFile)
        case .external:
            try resolveExternal(using: using, module: module, unit: unit, currentFile: currentFile)
        }
    }
    
    /// 记录导入关系到 ImportGraph
    private func recordImportToGraph(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) {
        let effectiveAccess: AccessModifier = using.access == .default ? .private : using.access
        let importSourceFile: String? = effectiveAccess == .private ? currentFile : nil

        switch using.pathKind {
        case .fileMerge:
            // 文件合并：using "file"
            // 文件合并被视为 local，因为合并的文件成为当前模块的一部分
            // 不需要记录到 ImportGraph，因为符号直接可用
            break
            
        case .submodule:
            // 子模块导入：using self.child 或 using self.child.* 或 using self.child.Symbol
            let segments = using.pathSegments.filter { $0 != "self" }
            guard !segments.isEmpty else { return }
            
            var targetPath = module.path
            
            if using.isBatchImport {
                // 批量导入：using self.child.*
                targetPath.append(contentsOf: segments)
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .batchImport,
                    sourceFile: importSourceFile
                )
            } else if segments.count >= 2,
                      let lastSegment = segments.last,
                      let firstChar = lastSegment.first,
                      firstChar.isUppercase {
                // 成员导入：using self.child.Symbol
                let modulePart = Array(segments.dropLast())
                targetPath.append(contentsOf: modulePart)
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: targetPath,
                    symbol: lastSegment,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
            } else {
                // 普通模块导入：using self.child
                targetPath.append(contentsOf: segments)
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .moduleImport,
                    sourceFile: importSourceFile
                )
            }
            
        case .parent:
            // 父模块导入：using super.sibling 或 using super.sibling.* 或 using super.sibling.Symbol
            var current = module
            var segmentIndex = 0
            
            // 处理 super 链
            while segmentIndex < using.pathSegments.count
                  && using.pathSegments[segmentIndex] == "super" {
                if let parent = current.parent {
                    current = parent
                }
                segmentIndex += 1
            }
            
            // 处理剩余路径
            var targetPath = current.path
            let remainingSegments = segmentIndex < using.pathSegments.count
                ? Array(using.pathSegments[segmentIndex...])
                : []
            
            if using.isBatchImport {
                // 批量导入
                targetPath.append(contentsOf: remainingSegments)
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .batchImport,
                    sourceFile: importSourceFile
                )
            } else if remainingSegments.count >= 2,
                      let lastSegment = remainingSegments.last,
                      let firstChar = lastSegment.first,
                      firstChar.isUppercase {
                // 成员导入
                let modulePart = Array(remainingSegments.dropLast())
                targetPath.append(contentsOf: modulePart)
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: targetPath,
                    symbol: lastSegment,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
            } else {
                // 普通模块导入
                targetPath.append(contentsOf: remainingSegments)
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .moduleImport,
                    sourceFile: importSourceFile
                )
            }
            
        case .external:
            // 外部模块导入：using std 或 using std.* 或 using std.Symbol
            guard !using.pathSegments.isEmpty else { return }
            
            if using.isBatchImport {
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: using.pathSegments,
                    kind: .batchImport,
                    sourceFile: importSourceFile
                )
            } else if using.pathSegments.count >= 2,
                      let lastSegment = using.pathSegments.last,
                      let firstChar = lastSegment.first,
                      firstChar.isUppercase {
                // 成员导入
                let modulePart = Array(using.pathSegments.dropLast())
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: modulePart,
                    symbol: lastSegment,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
            } else {
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: using.pathSegments,
                    kind: .moduleImport,
                    sourceFile: importSourceFile
                )
            }
        }
    }
    
    /// 解析文件合并: using "user"
    private func resolveFileMerge(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        guard !using.pathSegments.isEmpty else {
            throw ModuleError.invalidModulePath("empty file merge path")
        }
        
        let filename = using.pathSegments[0]
        let filePath = module.directory + "/" + filename + ".koral"
        
        guard fileManager.fileExists(atPath: filePath) else {
            throw ModuleError.fileNotFound(filename, searchPath: module.directory)
        }
        
        // 检查是否已合并 - 如果已合并则报错（不允许重复 using）
        if module.mergedFiles.contains(filePath) {
            throw ModuleError.duplicateUsing(filename, span: using.span)
        }
        
        module.mergedFiles.append(filePath)
        
        // 解析合并的文件（共享符号表）
        try resolveFile(file: filePath, module: module, unit: unit)
    }
    
    /// 解析子模块: using self.utils 或符号导入: using self.Symbol
    private func resolveSubmodule(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        guard !using.pathSegments.isEmpty else {
            throw ModuleError.invalidModulePath("empty submodule path")
        }
        
        // pathSegments 不包含 "self"，直接是子模块/符号路径
        // 例如: using self.utils -> pathSegments = ["utils"]
        //       using self.Expr -> pathSegments = ["Expr"]
        let firstSegment = using.pathSegments[0]
        let submodPath = module.directory + "/" + firstSegment
        let entryFile = submoduleEntryPath(parentDirectory: module.directory, submodName: firstSegment)
        
        // 检查是否是子模块目录
        var isDirectory: ObjCBool = false
        let pathExists = fileManager.fileExists(atPath: submodPath, isDirectory: &isDirectory)
        
        // 如果不是目录，说明这是符号导入而不是子模块导入
        // 符号导入的验证在 TypeChecker 阶段完成
        if !pathExists || !isDirectory.boolValue {
            // 这是符号导入 (using self.Symbol)，不需要在模块解析阶段处理
            // 符号导入在 TypeChecker 阶段通过 importedModules 处理
            return
        }
        
        // 检查入口文件是否存在
        guard fileManager.fileExists(atPath: entryFile) else {
            throw ModuleError.missingEntryFile(submodName: firstSegment, expectedPath: entryFile, span: using.span)
        }
        
        // 创建或获取子模块
        let submodule: ModuleInfo
        if let existing = module.submodules[firstSegment] {
            submodule = existing
        } else {
            submodule = ModuleInfo(
                path: module.path + [firstSegment],
                entryFile: entryFile,
                isExternal: false
            )
            submodule.parent = module
            module.submodules[firstSegment] = submodule
            unit.loadedModules[submodule.pathString] = submodule
            
            // 解析子模块
            try resolveFile(file: entryFile, module: submodule, unit: unit)
        }
        
        // 记录子模块访问控制信息
        let access = using.access == .default ? .private : using.access
        if module.submoduleAccesses[firstSegment] != nil {
            throw ModuleError.duplicateUsing(firstSegment, span: using.span)
        }
        module.submoduleAccesses[firstSegment] = ModuleAccessInfo(
            access: access,
            definedInFile: currentFile,
            span: using.span
        )
        
        // 符号导入在 TypeChecker 阶段通过 nodeSourceInfoList 完成
        // 如果是批量导入，后续在符号表阶段处理
    }
    
    /// 解析父模块: using super.sibling
    private func resolveParent(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
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
                // 首先检查是否是子模块
                if let submod = current.submodules[segment] {
                    // 通过记录的访问控制信息检查权限（如果存在）
                    if let accessInfo = current.submoduleAccesses[segment] {
                        try accessChecker.checkModuleAccess(
                            symbolName: segment,
                            access: accessInfo.access,
                            definedIn: current,
                            definedInFile: accessInfo.definedInFile,
                            from: module,
                            fromFile: currentFile,
                            span: accessInfo.span
                        )
                    }
                    current = submod
                } else {
                    // 尝试加载子模块
                    let entryFile = submoduleEntryPath(parentDirectory: current.directory, submodName: segment)
                    
                    // 如果子模块入口文件不存在，说明这个段是符号名而不是模块名
                    // 停止子模块查找，符号导入在 TypeChecker 阶段处理
                    guard fileManager.fileExists(atPath: entryFile) else {
                        // 不是子模块，可能是符号导入，直接返回
                        // 符号导入的验证在 TypeChecker 阶段完成
                        return
                    }
                    
                    let submodule = ModuleInfo(
                        path: current.path + [segment],
                        entryFile: entryFile,
                        isExternal: false
                    )
                    submodule.parent = current
                    current.submodules[segment] = submodule
                    unit.loadedModules[submodule.pathString] = submodule
                    
                    try resolveFile(file: entryFile, module: submodule, unit: unit)
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
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        guard !using.pathSegments.isEmpty else {
            throw ModuleError.invalidModulePath("empty external path")
        }

        // 标准库由 Driver 预加载到同一编译流程中；
        // `using std...` 仅用于可见性/导入图，不走外部模块文件系统解析。
        if using.pathSegments[0] == "std" {
            return
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
        let externalUnit = try resolveModule(entryFile: modulePath + "/" + moduleName + ".koral")
        unit.externalModules[moduleName] = externalUnit
        
        // 符号导入在 TypeChecker 阶段通过 nodeSourceInfoList 完成
    }
    
    /// 查找外部模块路径
    private func findExternalModule(_ name: String) throws -> String {
        var searchPaths: [String] = []
        let entryFileName = name + ".koral"
        
        // 检查标准库
        if let stdPath = stdLibPath {
            let path = stdPath + "/" + name
            searchPaths.append(path)
            if fileManager.fileExists(atPath: path + "/" + entryFileName) {
                return path
            }
        }
        
        // 检查外部路径
        for basePath in externalPaths {
            let path = basePath + "/" + name
            searchPaths.append(path)
            if fileManager.fileExists(atPath: path + "/" + entryFileName) {
                return path
            }
        }
        
        throw ModuleError.externalModuleNotFound(name, searchPaths: searchPaths)
    }
}

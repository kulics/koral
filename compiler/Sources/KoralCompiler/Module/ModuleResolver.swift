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
    case ambiguousModuleEntry(moduleName: String, fileEntry: String, directoryEntry: String)

    /// Preferred file for diagnostics location when available.
    public var locationFile: String? {
        switch self {
        case .parseError(let file, _):
            return file
        default:
            return nil
        }
    }

    /// Source span for diagnostics rendering when available.
    public var span: SourceSpan {
        switch self {
        case .submoduleNotFound(_, _, let span):
            return span
        case .missingEntryFile(_, _, let span):
            return span
        case .superOutOfBounds(let span):
            return span
        case .duplicateUsing(_, let span):
            return span
        case .parseError(_, let underlying as ParserError):
            return underlying.span
        case .parseError(_, let underlying as LexerError):
            return underlying.span
        default:
            return .unknown
        }
    }

    /// Error message without location prefix.
    public var messageWithoutLocation: String {
        switch self {
        case .fileNotFound(let file, let searchPath):
            return "File '\(file).koral' not found in '\(searchPath)'"
        case .submoduleNotFound(let name, let parentPath, _):
            return "Submodule '\(name)' not found (expected directory '\(parentPath)/\(name)/')"
        case .missingEntryFile(let submodName, let expectedPath, _):
            return "Submodule '\(submodName)' is missing entry file '\(expectedPath)'"
        case .superOutOfBounds:
            return "'super' goes beyond the root module of the compilation unit"
        case .externalModuleNotFound(let name, let paths):
            return "External module '\(name)' not found. Searched in: \(paths.joined(separator: ", "))"
        case .circularDependency(let path):
            return "Circular dependency detected: \(path.joined(separator: " -> "))"
        case .invalidModulePath(let path):
            return "Invalid module path: '\(path)'"
        case .duplicateUsing(let name, _):
            return "Duplicate using declaration for '\(name)'"
        case .parseError(_, let underlying as ParserError):
            return underlying.messageWithoutLocation
        case .parseError(_, let underlying as LexerError):
            return underlying.messageWithoutLocation
        case .parseError(_, let underlying):
            return "\(underlying)"
        case .invalidEntryFileName(let filename, let reason):
            return """
                Invalid entry file name '\(filename)': \(reason)
                Module file names must be snake_case: start with a lowercase letter, \
                contain only lowercase letters, digits, and underscores.
                Examples: main, my_app, tool1
                """
        case .ambiguousModuleEntry(let moduleName, let fileEntry, let directoryEntry):
            return "Ambiguous module '\(moduleName)': both file module '\(fileEntry)' and directory module '\(directoryEntry)' exist"
        }
    }
    
    public var description: String {
        switch self {
        case .fileNotFound:
            return messageWithoutLocation
        case .submoduleNotFound(_, _, let span):
            return "\(span): error: \(messageWithoutLocation)"
        case .missingEntryFile(_, _, let span):
            return "\(span): error: \(messageWithoutLocation)"
        case .superOutOfBounds(let span):
            return "\(span): error: \(messageWithoutLocation)"
        case .externalModuleNotFound:
            return messageWithoutLocation
        case .circularDependency:
            return messageWithoutLocation
        case .invalidModulePath:
            return messageWithoutLocation
        case .duplicateUsing(_, let span):
            return "\(span): error: \(messageWithoutLocation)"
        case .parseError(let file, _):
            if span.isKnown {
                return "\(file):\(span.start.line):\(span.start.column): \(messageWithoutLocation)"
            }
            return "\(file): \(messageWithoutLocation)"
        case .invalidEntryFileName:
            return messageWithoutLocation
        case .ambiguousModuleEntry:
            return messageWithoutLocation
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

/// 验证文件系统中的模块文件名是否合法（snake_case）
/// - Parameter filename: 不含扩展名的文件名
/// - Returns: 验证结果，成功返回 nil，失败返回错误原因
public func validateModuleFileName(_ filename: String) -> String? {
    guard !filename.isEmpty else {
        return "Module name cannot be empty"
    }

    let chars = Array(filename)

    guard let first = chars.first else {
        return "Module name cannot be empty"
    }

    guard first >= "a" && first <= "z" else {
        return "Module file name must start with a lowercase letter (a-z)"
    }

    for char in chars {
        let isLowercaseLetter = char >= "a" && char <= "z"
        let isDigit = char >= "0" && char <= "9"
        let isUnderscore = char == "_"

        if !isLowercaseLetter && !isDigit && !isUnderscore {
            return "Module file name can only contain lowercase letters (a-z), digits (0-9), and underscores (_)"
        }
    }

    return nil
}

/// 验证代码中的模块名是否合法（PascalCase）
public func validateModuleIdentifier(_ name: String) -> String? {
    guard !name.isEmpty else {
        return "Module name cannot be empty"
    }

    let chars = Array(name)
    guard let first = chars.first else {
        return "Module name cannot be empty"
    }

    guard first >= "A" && first <= "Z" else {
        return "Module name must start with an uppercase letter (A-Z)"
    }

    for char in chars {
        let isUppercaseLetter = char >= "A" && char <= "Z"
        let isLowercaseLetter = char >= "a" && char <= "z"
        let isDigit = char >= "0" && char <= "9"

        if !isUppercaseLetter && !isLowercaseLetter && !isDigit {
            return "Module name can only contain letters (A-Z, a-z) and digits (0-9)"
        }
    }

    return nil
}

public func moduleFileNameToIdentifier(_ filename: String) -> String {
    filename
        .split(separator: "_")
        .filter { !$0.isEmpty }
        .map { segment in
            guard let first = segment.first else { return "" }
            return String(first).uppercased() + segment.dropFirst()
        }
        .joined()
}

public func moduleIdentifierToFileName(_ identifier: String) -> String {
    guard !identifier.isEmpty else { return identifier }

    var result = ""
    for char in identifier {
        if char.isUppercase {
            if !result.isEmpty {
                result.append("_")
            }
            result.append(char.lowercased())
        } else {
            result.append(char)
        }
    }
    return result
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
    
    /// 已合并子模块列表（以入口文件绝对路径表示）
    public var mergedSubmodules: [String] = []
    
    /// 子模块
    public var submodules: [String: ModuleInfo] = [:]
    
    /// 父模块（根模块为 nil）
    public weak var parent: ModuleInfo?
    
    /// 是否为外部模块
    public let isExternal: Bool
    
    /// 已解析的 AST 节点（来自当前模块和所有已合并子模块）
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
    
    /// 定位子模块入口文件。
    /// 目录模块: <parent>/<name>/<name>.koral
    /// 文件模块: <parent>/<name>.koral
    private func locateChildModuleEntry(parentDirectory: String, childName: String) throws -> String? {
        // 仅合法模块名才参与子模块入口查找。
        // 这可以避免在大小写不敏感文件系统上把成员名（如 Path）误判为模块名（path）。
        guard validateModuleIdentifier(childName) == nil else {
            return nil
        }

        let childFileName = moduleIdentifierToFileName(childName)

        let dirEntry = parentDirectory + "/" + childFileName + "/" + childFileName + ".koral"
        let fileEntry = parentDirectory + "/" + childFileName + ".koral"

        let hasDirEntry = fileManager.fileExists(atPath: dirEntry)
        let hasFileEntry = fileManager.fileExists(atPath: fileEntry)

        if hasDirEntry && hasFileEntry {
            throw ModuleError.ambiguousModuleEntry(
                moduleName: childName,
                fileEntry: fileEntry,
                directoryEntry: dirEntry
            )
        }

        if hasDirEntry {
            return dirEntry
        }

        if hasFileEntry {
            return fileEntry
        }

        return nil
    }

    /// 从给定模块按相对路径定位模块入口。
    /// 支持嵌套目录链，末段同时支持目录模块与文件模块。
    private func locateModuleEntry(from baseModule: ModuleInfo, relativeSegments: [String]) throws -> String? {
        guard !relativeSegments.isEmpty else { return nil }

        // 合并路径中的每一段都必须是合法模块名。
        guard relativeSegments.allSatisfy({ validateModuleIdentifier($0) == nil }) else {
            return nil
        }

        if relativeSegments.count == 1 {
            return try locateChildModuleEntry(parentDirectory: baseModule.directory, childName: relativeSegments[0])
        }

        let prefix = relativeSegments.dropLast().map(moduleIdentifierToFileName).joined(separator: "/")
        let last = relativeSegments.last ?? ""
        let lastFileName = moduleIdentifierToFileName(last)
        let parentDir = baseModule.directory + "/" + prefix

        let fileEntry = parentDir + "/" + lastFileName + ".koral"

        let dirEntry = parentDir + "/" + lastFileName + "/" + lastFileName + ".koral"
        let hasDirEntry = fileManager.fileExists(atPath: dirEntry)
        let hasFileEntry = fileManager.fileExists(atPath: fileEntry)

        if hasDirEntry && hasFileEntry {
            throw ModuleError.ambiguousModuleEntry(
                moduleName: relativeSegments.joined(separator: "."),
                fileEntry: fileEntry,
                directoryEntry: dirEntry
            )
        }

        if hasDirEntry {
            return dirEntry
        }

        if hasFileEntry {
            return fileEntry
        }

        return nil
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
        if let error = validateModuleFileName(filename) {
            throw ModuleError.invalidEntryFileName(filename: filename, reason: error)
        }

        let rootModuleName = moduleFileNameToIdentifier(filename)
        
        // 创建根模块，path 包含文件名
        let rootModule = ModuleInfo(
            path: [rootModuleName],
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
        case .fileUsing:
            if let alias = using.alias {
                // using "file" as Name → submodule export
                try resolveFileSubmodule(using: using, fileName: using.fileName!, moduleName: alias, module: module, unit: unit, currentFile: currentFile)
            } else {
                // using "file" → file merge
                try resolveFileMerge(using: using, fileName: using.fileName!, module: module, unit: unit, currentFile: currentFile)
            }
        case .path:
            try resolvePathUsing(using: using, module: module, unit: unit, currentFile: currentFile)
        case .parent:
            try resolveParent(using: using, module: module, unit: unit, currentFile: currentFile)
        }
    }
    
    /// 记录导入关系到 ImportGraph
    private func recordImportToGraph(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) {
        let effectiveAccess: AccessModifier = using.access
        let importSourceFile: String? = effectiveAccess == .private ? currentFile : nil

        switch using.pathKind {
        case .fileUsing:
            if let alias = using.alias {
                // File submodule: using "file" as Name → record module import
                var targetPath = module.path
                targetPath.append(alias)
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .moduleImport,
                    sourceFile: importSourceFile
                )
                // Also record the last segment as a symbol import so the module name is directly usable
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: module.path,
                    symbol: alias,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
            }
            // File merge (no alias): treated as local, no import graph entry needed
            
        case .parent:
            // 父级导入：模块导入 / 批量导入 / 显式符号导入
            var current = module
            var segmentIndex = 0
            
            // 处理 super 链
            while segmentIndex < using.pathSegments.count
                && using.pathSegments[segmentIndex] == "Super" {
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
            targetPath.append(contentsOf: remainingSegments)

            if let importedSymbol = using.importedSymbol, !importedSymbol.isEmpty {
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: targetPath,
                    symbol: importedSymbol,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
                break
            }
            
            if using.isBatchImport {
                // 批量导入
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .batchImport,
                    sourceFile: importSourceFile
                )
            } else {
                // 非批量导入：只记录模块导入。
                // 成员导入必须由 parser 显式设置 importedSymbol。
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .moduleImport,
                    sourceFile: importSourceFile
                )
            }

            if using.importedSymbol == nil, let alias = using.alias, !alias.isEmpty {
                var aliasTarget = current.path
                aliasTarget.append(contentsOf: remainingSegments)
                unit.importGraph.addModuleAlias(
                    module: module.path,
                    alias: alias,
                    target: aliasTarget,
                    sourceFile: importSourceFile
                )
            }
            
        case .path:
            // 路径导入（外部或本地子模块）
            guard !using.pathSegments.isEmpty else { return }

            if let importedSymbol = using.importedSymbol, !importedSymbol.isEmpty {
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: using.pathSegments,
                    symbol: importedSymbol,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
                break
            }
            
            if using.isBatchImport {
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: using.pathSegments,
                    kind: .batchImport,
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

            if using.importedSymbol == nil, let alias = using.alias, !alias.isEmpty {
                unit.importGraph.addModuleAlias(
                    module: module.path,
                    alias: alias,
                    target: using.pathSegments,
                    sourceFile: importSourceFile
                )
            }
        }
    }
    
    /// 解析文件合并: using "file_name"
    private func resolveFileMerge(
        using: UsingDeclaration,
        fileName: String,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        let currentDir = URL(fileURLWithPath: currentFile).deletingLastPathComponent().path
        let fileEntry = currentDir + "/" + fileName + ".koral"
        let dirEntry = currentDir + "/" + fileName + "/" + fileName + ".koral"
        
        let hasFile = FileManager.default.fileExists(atPath: fileEntry)
        let hasDir = FileManager.default.fileExists(atPath: dirEntry)
        
        if hasFile && hasDir {
            throw ModuleError.ambiguousModuleEntry(
                moduleName: fileName,
                fileEntry: fileEntry,
                directoryEntry: dirEntry
            )
        }
        
        let filePath: String
        if hasFile {
            filePath = fileEntry
        } else if hasDir {
            filePath = dirEntry
        } else {
            throw ModuleError.fileNotFound(fileName, searchPath: currentDir)
        }
        
        if module.mergedSubmodules.contains(filePath) {
            throw ModuleError.duplicateUsing("\"\(fileName)\"", span: using.span)
        }
        
        module.mergedSubmodules.append(filePath)
        try resolveFile(file: filePath, module: module, unit: unit)
    }
    
    /// 解析文件子模块: using "file_name" as Name
    private func resolveFileSubmodule(
        using: UsingDeclaration,
        fileName: String,
        moduleName: String,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        let currentDir = URL(fileURLWithPath: currentFile).deletingLastPathComponent().path
        let dirEntry = currentDir + "/" + fileName + "/" + fileName + ".koral"
        let fileEntry = currentDir + "/" + fileName + ".koral"
        
        let hasDir = FileManager.default.fileExists(atPath: dirEntry)
        let hasFile = FileManager.default.fileExists(atPath: fileEntry)
        
        if hasDir && hasFile {
            throw ModuleError.ambiguousModuleEntry(
                moduleName: moduleName,
                fileEntry: fileEntry,
                directoryEntry: dirEntry
            )
        }
        
        let entryFile: String
        if hasDir {
            entryFile = dirEntry
        } else if hasFile {
            entryFile = fileEntry
        } else {
            throw ModuleError.fileNotFound(fileName, searchPath: currentDir)
        }
        
        // Already loaded as submodule
        if module.submodules[moduleName] != nil {
            // Still need to record access info even if submodule was loaded by another path
            if module.submoduleAccesses[moduleName] == nil {
                module.submoduleAccesses[moduleName] = ModuleAccessInfo(
                    access: using.access,
                    definedInFile: currentFile,
                    span: using.span
                )
            }
            return
        }
        
        // Already merged
        if module.mergedSubmodules.contains(entryFile) {
            return
        }
        
        let submodule = ModuleInfo(
            path: module.path + [moduleName],
            entryFile: entryFile,
            isExternal: false
        )
        submodule.parent = module
        module.submodules[moduleName] = submodule
        unit.loadedModules[submodule.pathString] = submodule
        
        try resolveFile(file: entryFile, module: submodule, unit: unit)
        
        if module.submoduleAccesses[moduleName] == nil {
            module.submoduleAccesses[moduleName] = ModuleAccessInfo(
                access: using.access,
                definedInFile: currentFile,
                span: using.span
            )
        }
    }
    
    /// 解析父级路径导入
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
              && using.pathSegments[segmentIndex] == "Super" {
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
            
            for (index, segment) in remainingPath.enumerated() {
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
                    // 尝试加载子模块（支持目录模块与文件模块）
                    guard let entryFile = try locateChildModuleEntry(parentDirectory: current.directory, childName: segment) else {
                        // 不是子模块，可能是符号导入，直接返回
                        // 符号导入的验证在 TypeChecker 阶段完成
                        return
                    }

                        // 文件合并后的目标不再是可导入子模块；若为末段，视为符号导入候选。
                    if current.mergedSubmodules.contains(entryFile) {
                            if !using.isBatchImport && using.importedSymbol == nil && index == remainingPath.count - 1 {
                                return
                            }
                            throw ModuleError.invalidModulePath(using.pathSegments.joined(separator: "."))
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
    
    /// 解析路径导入: using Std.Io / using Worker.run
    /// 先检查本地子模块，再尝试外部模块
    private func resolvePathUsing(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        guard !using.pathSegments.isEmpty else { return }
        
        let first = using.pathSegments[0]
        
        // If first segment matches a known submodule, handle as local submodule import
        if module.submodules[first] != nil {
            let importSourceFile: String? = using.access == .private ? currentFile : nil
            let segments = using.pathSegments
            
            // Build target path: module.path + segments
            var targetPath = module.path
            targetPath.append(contentsOf: segments)
            
            // If parser already extracted importedSymbol, use it
            if let importedSymbol = using.importedSymbol, !importedSymbol.isEmpty {
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: targetPath,
                    symbol: importedSymbol,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
                return
            }
            
            if using.isBatchImport {
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .batchImport,
                    sourceFile: importSourceFile
                )
            } else if segments.count >= 2 {
                // using Worker.run → member import of 'run' from submodule Worker
                let symbol = segments.last!
                var symbolTarget = module.path
                symbolTarget.append(contentsOf: segments.dropLast())
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: symbolTarget,
                    symbol: symbol,
                    kind: .memberImport,
                    sourceFile: importSourceFile
                )
            } else {
                // using Worker → module import
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: targetPath,
                    kind: .moduleImport,
                    sourceFile: importSourceFile
                )
            }
            
            if let alias = using.alias, !alias.isEmpty {
                unit.importGraph.addModuleAlias(
                    module: module.path,
                    alias: alias,
                    target: targetPath,
                    sourceFile: importSourceFile
                )
            }
            return
        }
        
        // Try external module resolution
        try resolveExternal(using: using, module: module, unit: unit, currentFile: currentFile)
    }
    
    /// 解析外部模块: using std / using std.list
    private func resolveExternal(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        guard !using.pathSegments.isEmpty else {
            throw ModuleError.invalidModulePath("empty external path")
        }

        let moduleName = using.pathSegments[0]

        // 同根模块内的 self-like external 写法仅用于导入图，不在这里做外部解析。
        if module.path.first == moduleName {
            return
        }

        // If the first segment matches a known submodule of the current module,
        // skip external resolution — the submodule was already loaded via
        // using "file" as Name, and the import graph entry is sufficient.
        if module.submodules[moduleName] != nil {
            return
        }

        if moduleName == "Std" {
            if let stdUnit = unit.externalModules[moduleName] {
                try validateExternalModulePath(using.pathSegments, rootModule: stdUnit.rootModule)
                return
            }

            guard let stdLibPath else {
                throw ModuleError.invalidModulePath(using.pathSegments.joined(separator: "."))
            }
            let stdEntry = URL(fileURLWithPath: stdLibPath)
                .appendingPathComponent("std.koral")
                .path

            guard fileManager.fileExists(atPath: stdEntry) else {
                throw ModuleError.invalidModulePath(using.pathSegments.joined(separator: "."))
            }

            let stdUnit = try resolveModule(entryFile: stdEntry)
            unit.externalModules[moduleName] = stdUnit
            try validateExternalModulePath(using.pathSegments, rootModule: stdUnit.rootModule)
            return
        }

        if let cached = unit.externalModules[moduleName] {
            try validateExternalModulePath(using.pathSegments, rootModule: cached.rootModule)
            return
        }

        // 查找外部模块
        let modulePath = try findExternalModule(moduleName)

        // 加载外部模块（作为独立编译单元）
        let moduleFileName = moduleIdentifierToFileName(moduleName)
        let externalUnit = try resolveModule(entryFile: modulePath + "/" + moduleFileName + ".koral")
        unit.externalModules[moduleName] = externalUnit
        try validateExternalModulePath(using.pathSegments, rootModule: externalUnit.rootModule)

        // 符号导入在 TypeChecker 阶段通过 nodeSourceInfoList 完成
        _ = currentFile
    }

    /// 验证外部路径是否指向可导入的 public 子模块。
    private func validateExternalModulePath(_ pathSegments: [String], rootModule: ModuleInfo) throws {
        // `using foo` / `using foo.*` 总是允许。
        guard pathSegments.count > 1 else {
            return
        }

        var current = rootModule
        for segment in pathSegments.dropFirst() {
            guard let submodule = current.submodules[segment],
                  let accessInfo = current.submoduleAccesses[segment],
                  accessInfo.access == .public else {
                throw ModuleError.invalidModulePath(pathSegments.joined(separator: "."))
            }
            current = submodule
        }
    }

    /// 查找外部模块路径
    private func findExternalModule(_ name: String) throws -> String {
        var searchPaths: [String] = []
        let moduleFileName = moduleIdentifierToFileName(name)
        let entryFileName = moduleFileName + ".koral"

        // 检查标准库
        if let stdPath = stdLibPath {
            let path = stdPath + "/" + moduleFileName
            searchPaths.append(path)
            if fileManager.fileExists(atPath: path + "/" + entryFileName) {
                return path
            }
        }

        // 检查外部路径
        for basePath in externalPaths {
            let path = basePath + "/" + moduleFileName
            searchPaths.append(path)
            if fileManager.fileExists(atPath: path + "/" + entryFileName) {
                return path
            }
        }

        throw ModuleError.externalModuleNotFound(name, searchPaths: searchPaths)
    }
}

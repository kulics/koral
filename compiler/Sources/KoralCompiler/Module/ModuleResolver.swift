import Foundation

private func isASCIIUppercaseLetter(_ char: Character) -> Bool {
    guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else {
        return false
    }
    return scalar.value >= 65 && scalar.value <= 90
}

// MARK: - Module Error Types

/// 模块系统错误类型
public enum ModuleError: Error, CustomStringConvertible {
    case fileNotFound(String, searchPath: String)
    case circularDependency(path: [String])
    case invalidModulePath(String)
    case duplicateUsing(String, span: SourceSpan)
    case parseError(file: String, underlying: Error)
    case invalidEntryFileName(filename: String, reason: String)

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
        }
    }
    
    public var description: String {
        switch self {
        case .fileNotFound:
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
        }
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
        if isASCIIUppercaseLetter(char) {
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
    
    /// 是否为外部模块
    public let isExternal: Bool
    
    /// 已解析的 AST 节点（来自当前模块和所有已合并子模块）
    /// 每个元组包含 (节点, 来源文件路径)
    public var globalNodes: [(node: GlobalNode, sourceFile: String)] = []
    
    /// using 声明
    public var usingDeclarations: [UsingDeclaration] = []
    
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
        for (node, _) in module.globalNodes {
            result.append(node)
        }
    }
    
    private func collectGlobalNodesWithSourceInfo(
        from module: ModuleInfo,
        into result: inout [(node: GlobalNode, sourceFile: String, modulePath: [String])]
    ) {
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

    public var manifestModuleAliases: [ResolvedModuleAliasRule] = []
    
    public init(stdLibPath: String? = nil, externalPaths: [String] = []) {
        self.stdLibPath = stdLibPath
        self.externalPaths = externalPaths
    }

    private func resolveManifestAliasedModulePath(_ pathSegments: [String]) -> [String] {
        guard !manifestModuleAliases.isEmpty else {
            return pathSegments
        }

        let sortedRules = manifestModuleAliases.sorted {
            if $0.aliasPathSegments.count == $1.aliasPathSegments.count {
                return $0.aliasFullName < $1.aliasFullName
            }
            return $0.aliasPathSegments.count > $1.aliasPathSegments.count
        }

        for rule in sortedRules {
            guard pathSegments.count >= rule.aliasPathSegments.count else {
                continue
            }
            if Array(pathSegments.prefix(rule.aliasPathSegments.count)) == rule.aliasPathSegments {
                return rule.targetPathSegments + Array(pathSegments.dropFirst(rule.aliasPathSegments.count))
            }
        }
        return pathSegments
    }
    
    /// 解析模块入口
    /// - Parameter entryFile: 入口文件路径
    /// - Returns: 编译单元
    public func resolveModule(
        entryFile: String,
        rootModulePath: [String]? = nil
    ) throws -> CompilationUnit {
        let absolutePath = URL(fileURLWithPath: entryFile).standardized.path
        
        // 提取文件名（不含扩展名）
        let filename = URL(fileURLWithPath: absolutePath)
            .deletingPathExtension()
            .lastPathComponent
        
        // 验证文件名
        if let error = validateModuleFileName(filename) {
            throw ModuleError.invalidEntryFileName(filename: filename, reason: error)
        }

        let rootModulePath = rootModulePath ?? [moduleFileNameToIdentifier(filename)]
        
        // 创建根模块，path 包含文件名
        let rootModule = ModuleInfo(
            path: rootModulePath,
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
        switch using.kind {
        case .fileMerge(let filePath):
            try resolveFileMerge(using: using, fileName: filePath, module: module, unit: unit, currentFile: currentFile)
        case .moduleImport:
            recordImportToGraph(using: using, module: module, unit: unit, currentFile: currentFile)
        }
    }
    
    /// 记录导入关系到 ImportGraph
    private func recordImportToGraph(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) {
        let importSourceFile: String? = currentFile

        switch using.kind {
        case .fileMerge:
            return
        case .moduleImport(let pathSegments, let items):
            let resolvedTargetPath = resolveManifestAliasedModulePath(pathSegments)
            if items.contains(where: { $0.kind == .allPublic }) {
                unit.importGraph.addModuleImport(
                    from: module.path,
                    to: resolvedTargetPath,
                    kind: .batchImport,
                    sourceFile: importSourceFile
                )
            } else {
                for item in items where item.kind == .symbol {
                    guard let symbolName = item.name else { continue }
                    unit.importGraph.addSymbolImport(
                        module: module.path,
                        target: resolvedTargetPath,
                        symbol: item.alias ?? symbolName,
                        originalSymbol: symbolName,
                        kind: .memberImport,
                        sourceFile: importSourceFile
                    )
                }
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
        let mergePath = fileName.hasSuffix(".koral") ? fileName : fileName + ".koral"
        let filePath = URL(fileURLWithPath: currentDir)
            .appendingPathComponent(mergePath)
            .standardized
            .path

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ModuleError.fileNotFound(fileName, searchPath: currentDir)
        }
        
        if module.mergedSubmodules.contains(filePath) {
            throw ModuleError.duplicateUsing("\"\(fileName)\"", span: using.span)
        }
        
        module.mergedSubmodules.append(filePath)
        try resolveFile(file: filePath, module: module, unit: unit)
    }
}

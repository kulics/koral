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
    case circularDependency(path: [String], file: String)
    case invalidModulePath(String)
    case duplicateUsing(String, span: SourceSpan)
    case parseError(file: String, underlying: Error)
    case invalidEntryFileName(filename: String, reason: String)
    case unknownPackageName(name: String, known: [String], span: SourceSpan)
    case unknownModule(name: String, packageName: String, declared: [String], span: SourceSpan)
    case noMainModule(packageName: String, declared: [String], span: SourceSpan)
    case invalidModuleSpecifier(String, span: SourceSpan)
    case fileMergeWithList(String, span: SourceSpan)
    case fileMergeNotKoral(String, span: SourceSpan)
    case crossPackageMerge(String, span: SourceSpan)
    case fileClaimedTwice(file: String, owner: String, claimant: String, entryFile: String)

    /// The phase the failure belongs to.
    ///
    /// A `ModuleError` is a wrapper: the thing that actually failed is the
    /// parser or the lexer underneath. Reporting it as a plain `error` throws
    /// that away, and the two compilers then say the same thing with different
    /// stage labels -- which is a divergence the oracle is right to catch.
    public var stage: DiagnosticError.Stage {
        switch self {
        case .parseError(_, let underlying as LexerError):
            return .lexer
        case .parseError(_, let underlying as ParserError):
            return .parser
        default:
            return .other
        }
    }

    /// Preferred file for diagnostics location when available.
    public var locationFile: String? {
        switch self {
        case .parseError(let file, _):
            return file
        // A cycle is closed by a `using` in some file, and that is the module
        // currently being resolved. Naming the compile target instead would
        // point at a file that may not even mention the modules in the ring.
        case .circularDependency(_, let file):
            return file
        default:
            return nil
        }
    }

    /// Source span for diagnostics rendering when available.
    public var span: SourceSpan {
        switch self {
        case .duplicateUsing(_, let span),
             .unknownPackageName(_, _, let span),
             .unknownModule(_, _, _, let span),
             .noMainModule(_, _, let span),
             .invalidModuleSpecifier(_, let span),
             .fileMergeWithList(_, let span),
             .fileMergeNotKoral(_, let span),
             .crossPackageMerge(_, let span):
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
            return "File '\(file)' not found in '\(searchPath)'"
        case .circularDependency(let path, _):
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
        case .unknownPackageName(let name, let known, _):
            // An empty list reads as "<none>" everywhere else in this message
            // family -- a bare trailing colon just looks truncated.
            let knownList = known.isEmpty ? "<none>" : known.sorted().joined(separator: ", ")
            // The old spelling for merging a file was a bare name. It now reads
            // as a package name that does not exist, so say what each reading
            // would need (§8) instead of leaving the reader to guess.
            var lines = [
                "Unknown package name \"\(name)\"",
                "A name in 'using' is a package name: this package's 'package', one of its 'dependencies' keys, or the reserved \"std\".",
            ]
            if !name.contains("/") {
                lines.append("  to merge a file, write: using \"./\(name).koral\";")
                lines.append("  to import a module, declare the package in koral.json's dependencies first.")
            }
            lines.append("Known package names: \(knownList)")
            return lines.joined(separator: "\n")
        case .unknownModule(let name, let packageName, let declared, _):
            let declaredList = declared.isEmpty ? "<none>" : declared.sorted().joined(separator: ", ")
            return "Module '\(name)' does not exist in package '\(packageName)'; declared modules: \(declaredList)"
        case .noMainModule(let packageName, let declared, _):
            let declaredList = declared.isEmpty ? "<none>" : declared.sorted().joined(separator: ", ")
            return "Package '\(packageName)' has no main module; write a module subpath like 'pkg/name' instead; declared modules: \(declaredList)"
        case .invalidModuleSpecifier(let specifier, _):
            return "Invalid module name '\(specifier)'; a module name is 'package[/subpath]' with lowercase identifier segments"
        case .fileMergeWithList(let specifier, _):
            return "File merge '\(specifier)' takes no import list; it merges the whole file"
        case .fileMergeNotKoral(let specifier, _):
            return "File merge path must end in '.koral'; write '\(specifier).koral'"
        case .crossPackageMerge(let specifier, _):
            return "cannot merge '\(specifier)': merge is limited to the current package; import it with 'using \"\(specifier)\" { ... };'"
        case .fileClaimedTwice(let file, let owner, let claimant, _):
            return "Error: source file '\(file)' is already part of module '\(owner)' and cannot also join '\(claimant)'"
        }
    }

    public var description: String {
        switch self {
        case .fileClaimedTwice:
            // Printed as text, not as a source diagnostic: the message names
            // the file and both modules and carries the `Error: ` envelope the
            // driver gives a module-resolution failure (§7).
            return messageWithoutLocation
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
        case .unknownPackageName(_, _, let span),
             .unknownModule(_, _, _, let span),
             .noMainModule(_, _, let span),
             .invalidModuleSpecifier(_, let span),
             .fileMergeWithList(_, let span),
             .fileMergeNotKoral(_, let span),
             .crossPackageMerge(_, let span):
            return "\(span): error: \(messageWithoutLocation)"
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

/// 模块路径渲染成 `using` 里的说明符拼写：`["Std", "Time"]` -> `std/time`。
/// 诊断要给出用户写得出的那行代码，而不是内部标识符拼接。
public func modulePathToUsingSpecifier(_ modulePath: [String]) -> String {
    modulePath.map { moduleIdentifierToFileName($0) }.joined(separator: "/")
}

// MARK: - Module Info

/// 模块信息
public class ModuleInfo {
    /// 模块的全名段（包名 + 子路径），用于限定顶层符号
    public let path: [String]

    /// The derived C symbol prefix (§5.3.1) -- (package source, entry
    /// position), never the consumer's spelling. Empty for modules whose spec
    /// never carried one; the derivation sites fall back to `path`.
    public let symbolKey: String

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

    /// The module this one was declared as. Absent only for a single-file
    /// compile, where there is no manifest behind the module.
    public var spec: ResolvedModuleSpec?

    /// Owning package -- whose table resolves this module's own `using`
    /// statements. A dependency's source names its own packages, not the
    /// consumer's (§4).
    public var owner: LoadedPackage?

    public init(
        path: [String],
        entryFile: String,
        isExternal: Bool = false,
        symbolKey: String = ""
    ) {
        self.path = path
        self.entryFile = entryFile
        self.isExternal = isExternal
        self.symbolKey = symbolKey
    }

    /// 模块的完整路径字符串
    public var pathString: String {
        return path.joined(separator: ".")
    }
}

// MARK: - Compilation Unit

/// 编译单元
public class CompilationUnit {
    /// 所有已加载的模块（全名 -> 模块）
    public var loadedModules: [String: ModuleInfo] = [:]

    /// 加载顺序。符号表的遍历顺序由此决定，与 `using` 的发现顺序无关。
    public var loadOrder: [String] = []

    /// 导入图 - 记录模块间的导入关系
    public var importGraph: ImportGraph

    public init() {
        self.importGraph = ImportGraph()
    }

    /// 获取所有全局节点（按加载顺序）
    /// 保持原始 AST 名称，名称限定在 CodeGen 阶段处理
    public func getAllGlobalNodes() -> [GlobalNode] {
        var result: [GlobalNode] = []
        for name in loadOrder {
            guard let module = loadedModules[name] else { continue }
            for (node, _) in module.globalNodes {
                result.append(node)
            }
        }
        return result
    }

    /// 获取所有全局节点及其来源文件信息
    /// 用于 CodeGen 阶段生成正确的 C 名称
    public func getAllGlobalNodesWithSourceInfo() -> [(node: GlobalNode, sourceFile: String, modulePath: [String])] {
        var result: [(node: GlobalNode, sourceFile: String, modulePath: [String])] = []
        for name in loadOrder {
            guard let module = loadedModules[name] else { continue }
            for (node, sourceFile) in module.globalNodes {
                result.append((node: node, sourceFile: sourceFile, modulePath: module.path))
            }
        }
        return result
    }

    /// 标准库模块与用户模块的全局节点，按包归属拆开。
    ///
    /// 加载顺序是 `using` 的发现顺序，而符号表希望顺序稳定且与发现顺序无关，
    /// 所以这里按全名排序后输出。标准库在前，与它「被依赖」的角色一致。
    public func splitGlobalNodes() -> (
        std: [(node: GlobalNode, sourceFile: String, modulePath: [String])],
        user: [(node: GlobalNode, sourceFile: String, modulePath: [String])]
    ) {
        var std: [(node: GlobalNode, sourceFile: String, modulePath: [String])] = []
        var user: [(node: GlobalNode, sourceFile: String, modulePath: [String])] = []
        for name in loadOrder.sorted() {
            guard let module = loadedModules[name], let spec = module.spec else { continue }
            let bucket: Bool
            if case .std = spec.packageKind {
                bucket = true
            } else {
                bucket = false
            }
            for (node, sourceFile) in module.globalNodes {
                let item = (node: node, sourceFile: sourceFile, modulePath: module.path)
                if bucket {
                    std.append(item)
                } else {
                    user.append(item)
                }
            }
        }
        return (std: std, user: user)
    }
}

// MARK: - Module Resolver

/// 模块解析器
///
/// The module graph is not declared anywhere -- it is the `using` statements
/// (§5.4). Loading a module therefore means following its imports, which is
/// also what makes a cycle detectable: the cycle is in the load stack.
public class ModuleResolver {
    /// 标准库路径
    private var stdLibPath: String?

    /// 外部模块搜索路径
    private var externalPaths: [String] = []

    /// 当前正在解析的文件路径（用于文件合并的循环检测）。
    /// Ordered: the cycle report has to name the ring in the order it was
    /// entered, and a set does not remember one.
    private var resolvingFiles: [String] = []

    /// 模块加载栈（全名），用于模块导入的环检测
    private var moduleStack: [String] = []

    /// 文件管理器
    private let fileManager = FileManager.default

    /// The packages a `using` name can name. Absent for a single-file compile,
    /// where `using` can only merge files.
    public var registry: PackageRegistry?
    public var rootPackage: LoadedPackage?
    /// Which module's closure already claims each source file (§7). A file is
    /// compiled into exactly one module; a second claim is an error rather than
    /// a second copy of the same declarations under a different identity.
    public var claimedFiles: [String: String] = [:]

    /// Every module reachable by full name, built as modules get loaded.
    public var moduleIndex: [String: ResolvedModuleSpec] = [:]

    public init(stdLibPath: String? = nil, externalPaths: [String] = []) {
        self.stdLibPath = stdLibPath
        self.externalPaths = externalPaths
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
        //
        // A bare entry has no package behind it; its identity source is the
        // fixed `single:` tag and its position is the entry's own name (§5.3.1
        // degenerate case).
        let rootModule = ModuleInfo(
            path: rootModulePath,
            entryFile: absolutePath,
            isExternal: false,
            symbolKey: moduleSymbolKey(
                sourceTag: "single",
                entryFile: absolutePath,
                packageRoot: URL(fileURLWithPath: absolutePath).deletingLastPathComponent().path
            )
        )

        let unit = CompilationUnit()
        unit.loadedModules[rootModule.pathString] = rootModule
        unit.loadOrder.append(rootModule.pathString)

        // 解析入口文件
        try resolveFile(file: absolutePath, module: rootModule, unit: unit)

        return unit
    }

    /// Load a single file's contents into an already-created module.
    ///
    /// A bare file has no package table behind it, so a module import here has
    /// nothing it could name and is reported as an unknown package.
    public func resolveSingleFile(into module: ModuleInfo, unit: CompilationUnit) throws {
        try resolveFile(file: module.entryFile, module: module, unit: unit)
    }

    /// Load a module declared in a manifest, and everything its `using`
    /// statements reach.
    public func resolveModule(spec: ResolvedModuleSpec, unit: CompilationUnit) throws -> ModuleInfo {
        if let existing = unit.loadedModules[spec.fullName] {
            return existing
        }

        let module = ModuleInfo(
            path: spec.pathSegments,
            entryFile: spec.entryFile,
            isExternal: false,
            symbolKey: spec.symbolKey
        )
        module.spec = spec
        module.owner = spec.owner

        // Register before descending so a self-import is a cycle, not a hang.
        unit.loadedModules[spec.fullName] = module
        unit.loadOrder.append(spec.fullName)
        moduleIndex[spec.fullName] = spec
        moduleStack.append(spec.fullName)
        defer { _ = moduleStack.popLast() }

        try resolveFile(file: spec.entryFile, module: module, unit: unit)
        return module
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

        // A source file is compiled into exactly one module's closure (§7).
        // A second claim would give the same declarations two identities.
        let claimKey = module.path.joined(separator: ".")
        if let ownerKey = claimedFiles[file] {
            if ownerKey != claimKey {
                throw PackageManifestError.message(
                    "source file '\(file)' is already part of module '\(ownerKey)' and cannot also join '\(claimKey)'"
                )
            }
        } else {
            claimedFiles[file] = claimKey
        }

        resolvingFiles.append(file)
        defer { _ = resolvingFiles.popLast() }

        // 读取并解析文件
        let source: String
        do {
          source = try String(contentsOfFile: file, encoding: .utf8)
        } catch {
          // A raw read failure must not reach the reader as an NSError dump --
          // the path is the actionable part, and the OS reason is noise.
          throw PackageManifestError.message("Failed to read file: \(file)")
        }
        let lexer = Lexer(input: source)
        let parser = Parser(lexer: lexer)

        let ast: ASTNode
        do {
            ast = try parser.parse()
        } catch {
            // 包装解析错误，添加文件名信息
            throw ModuleError.parseError(file: file, underlying: error)
        }

        Parser.allTraitDeclaredParameterDefaults.formUnion(parser.traitDeclaredParameterDefaults)
        Parser.allImplDeclaredParameterDefaults.formUnion(parser.implDeclaredParameterDefaults)

        guard case .program(let globalNodes) = ast else {
            throw ModuleError.invalidModulePath(file)
        }

        // 从 GlobalNode 中提取 using 声明并处理
        var nonUsingNodes: [GlobalNode] = []
        // A module is imported once per file (§3.3). A second `using` for the
        // same module cannot mean anything the first did not, and two spellings
        // of one import is exactly the ambiguity the rule exists to prevent.
        var importedThisFile = Set<String>()
        for node in globalNodes {
            if case .usingDeclaration(let using) = node {
                // 保存 using 声明
                module.usingDeclarations.append(using)
                // 处理 using 声明
                try resolveUsing(using: using, module: module, unit: unit, currentFile: file, importedThisFile: &importedThisFile)
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
    ///
    /// `importedThisFile` is the set of modules this file has already imported:
    /// one `using` per module per file (§3.3).
    private func resolveUsing(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String,
        importedThisFile: inout Set<String>
    ) throws {
        if using.isFileMerge {
            if using.items != nil {
                // A local path with braces imports from the module rooted at
                // that entry file (§3.1). The entry file is the module's
                // identity; no manifest entry is needed.
                try recordLocalModuleUsing(using: using, module: module, unit: unit, currentFile: currentFile)
                return
            }
            try resolveFileMerge(using: using, fileName: using.specifier, module: module, unit: unit, currentFile: currentFile)
            return
        }

        let isMerge = using.items == nil
        let spec = try resolveModuleImport(using: using, module: module, unit: unit, load: !isMerge)
        if !importedThisFile.insert(spec.fullName).inserted {
            throw ModuleError.duplicateUsing(spec.fullName, span: using.span)
        }
        if isMerge {
            // Bare form is a MERGE (§3.2): the target module joins this one and
            // its boundary is gone. Same operation the `./` path form performs.
            // It is deliberately NOT loaded as its own module first -- that
            // would claim the files twice (§7).
            try mergeModule(into: module, spec: spec, specifier: using.specifier, span: using.span, unit: unit)
            return
        }
        // Import edges are scoped to the FILE the `using` is written in:
        // a `using` in one file of a module does not silently apply to its
        // siblings. That is what makes `file_private`-style isolation of
        // imports meaningful in a multi-file module.
        recordImportToGraph(using: using, module: module, unit: unit, target: spec, sourceFile: currentFile)
    }

    /// Turn the module path written in `using` into a declared module.
    ///
    /// The first segment is a package name; everything after it is the
    /// subpath inside that package (§4). There is no lookup that skips the
    /// package: a bare subpath is not a spelling of anything.
    private func resolveModuleImport(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        load: Bool = true
    ) throws -> ResolvedModuleSpec {
        // The specifier is `package[/subpath]`. The first segment is a package
        // name; the rest is the subpath inside it (§4). There is no lookup that
        // skips the package -- a bare subpath is not a spelling of anything.
        let segments = using.specifier.split(separator: "/").map(String.init)
        guard let headName = segments.first else {
            throw ModuleError.invalidModuleSpecifier(using.specifier, span: using.span)
        }

        guard let registry, let owner = module.owner ?? rootPackage else {
            throw ModuleError.unknownPackageName(name: headName, known: [], span: using.span)
        }

        guard let targetPackage = registry.resolveName(headName, from: owner) else {
            throw ModuleError.unknownPackageName(
                name: headName,
                known: registry.knownNames(for: owner),
                span: using.span
            )
        }

        // The subpath is what the package calls the module: `"."` written as
        // nothing at all, otherwise the segments joined by `/`.
        let tailSegments = Array(segments.dropFirst())
        let key = tailSegments.isEmpty ? "." : tailSegments.joined(separator: "/")
        guard let config = targetPackage.manifest.modules[key] else {
            if tailSegments.isEmpty {
                throw ModuleError.noMainModule(
                    packageName: targetPackage.selfName,
                    declared: Array(targetPackage.manifest.modules.keys),
                    span: using.span
                )
            }
            throw ModuleError.unknownModule(
                name: "\(headName)/\(tailSegments.joined(separator: "/"))",
                packageName: targetPackage.selfName,
                declared: Array(targetPackage.manifest.modules.keys),
                span: using.span
            )
        }

        let rootName = rootViewName(of: targetPackage, registry: registry, root: rootPackage ?? targetPackage)
        let spec = makeResolvedModuleSpec(
            key: key,
            config: config,
            rootName: rootName,
            owner: targetPackage
        )

        if let index = moduleStack.firstIndex(of: spec.fullName) {
            throw ModuleError.circularDependency(
                path: Array(moduleStack[index...]) + [spec.fullName],
                file: module.entryFile
            )
        }

        if load {
            _ = try resolveModule(spec: spec, unit: unit)
        }
        return spec
    }

    /// 记录导入关系到 ImportGraph
    private func recordImportToGraph(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        target: ResolvedModuleSpec,
        sourceFile: String
    ) {
        let importSourceFile: String? = sourceFile
        let targetPath = target.pathSegments

        guard let items = using.items else {
            // Bare form. It still means "every visible member" for a module
            // specifier; §3.2 turns it into a merge once every caller has moved
            // onto `{ ... }`.
            unit.importGraph.addModuleImport(
                from: module.path,
                to: targetPath,
                kind: .batchImport,
                sourceFile: importSourceFile,
                span: using.span
            )
            return
        }

        if using.importAll {
            // `{ ... }`, `{ a as b, ... }`, `{ !a, ... }` -- the whole surface
            // with the listed renames applied and exclusions removed (§3.3).
            // The filter rides on the batch edge and stops a renamed/excluded
            // spelling from landing under its own name; a rename is ALSO a
            // symbol edge so the new spelling resolves through the ordinary
            // import layer.
            unit.importGraph.addModuleImport(
                from: module.path,
                to: targetPath,
                kind: .batchImport,
                sourceFile: importSourceFile,
                span: using.span,
                filter: items
            )
            for item in items where item.alias != nil {
                unit.importGraph.addSymbolImport(
                    module: module.path,
                    target: targetPath,
                    symbol: item.alias ?? item.name,
                    originalSymbol: item.name,
                    kind: .memberImport,
                    sourceFile: importSourceFile,
                    span: using.span
                )
            }
            return
        }

        if items.isEmpty {
            // `{ }` -- a placeholder with no member surface (§3.3). It is a
            // dependency edge and nothing more: no names, no methods.
            unit.importGraph.addModuleImport(
                from: module.path,
                to: targetPath,
                kind: .moduleImport,
                sourceFile: importSourceFile,
                span: using.span
            )
            return
        }

        for item in items {
            unit.importGraph.addSymbolImport(
                module: module.path,
                target: targetPath,
                symbol: item.alias ?? item.name,
                originalSymbol: item.name,
                kind: .memberImport,
                sourceFile: importSourceFile,
                span: using.span
            )
        }
    }

    /// Import from a local module named by its entry file (§3.1). A local path
    /// with braces needs no manifest entry: the entry file IS the module, and
    /// its identity is the entry's position inside its package (§5.3.1) -- the
    /// same derivation a registered module gets, stem included only as one
    /// path segment. Two local modules sharing a stem in different directories
    /// are two modules.
    private func recordLocalModuleUsing(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit,
        currentFile: String
    ) throws {
        let currentDir = URL(fileURLWithPath: currentFile).deletingLastPathComponent().path
        var target = URL(fileURLWithPath: currentDir)
        for segment in using.specifier.split(separator: "/") {
            if segment == "." || segment.isEmpty { continue }
            if segment == ".." {
                target = target.deletingLastPathComponent()
            } else {
                target = target.appendingPathComponent(String(segment))
            }
        }
        let entryAbs = target.standardized.path
        guard FileManager.default.fileExists(atPath: entryAbs) else {
            throw ModuleError.fileNotFound(using.specifier, searchPath: currentDir)
        }

        // Load the target as its own module so its declarations exist under
        // `targetPath` and the boundary stays (§3.1).
        guard let owner = module.owner ?? rootPackage else {
            throw ModuleError.fileNotFound(using.specifier, searchPath: currentDir)
        }
        // Identity = (package source, entry position). The path segments keep
        // the entry's position inside the package, so `util/util.koral` and
        // `helpers/util.koral` never share a unit slot, a name key, or a
        // symbol prefix again.
        let packageRoot = owner.manifest.packageRoot
        let rel = entryRelativePath(entryFile: entryAbs, packageRoot: packageRoot)
        let segments = symbolKeySegments(relativeEntryPath: rel)
        let spec = ResolvedModuleSpec(
            fullName: segments.joined(separator: "/"),
            pathSegments: segments,
            symbolKey: moduleSymbolKey(
                sourceTag: packageSourceTag(for: owner),
                entryFile: entryAbs,
                packageRoot: packageRoot
            ),
            key: rel,
            subpath: rel,
            entryFile: entryAbs,
            links: [],
            packageIdentity: owner.identity,
            packageKind: owner.kind,
            owner: owner
        )
        _ = try resolveModule(spec: spec, unit: unit)

        recordImportToGraph(using: using, module: module, unit: unit, target: spec, sourceFile: currentFile)
    }

    /// The `packageRoot` of the registered package whose source tree contains
    /// `file` -- longest match wins, since a path dependency may sit inside the
    /// root package's tree. `nil` when no package claims the file.
    private func packageRoot(containing file: String) -> String? {
        let entryPath = URL(fileURLWithPath: file).standardized.path
        var candidates: [LoadedPackage] = []
        if let root = rootPackage {
            candidates.append(root)
        }
        if let registry = registry {
            candidates.append(contentsOf: registry.all)
        }
        var best: String? = nil
        var bestLen = 0
        for package in candidates {
            let rootPath = URL(fileURLWithPath: package.manifest.packageRoot).standardized.path
            if entryPath == rootPath || entryPath.hasPrefix(rootPath + "/") {
                if rootPath.count > bestLen {
                    bestLen = rootPath.count
                    best = rootPath
                }
            }
        }
        return best
    }

    /// Merge a whole module into the current one (§3.2). The target's boundary
    /// is gone afterwards: its `module_private` names are this module's own, so
    /// it may be merged into at most one module and, once merged, can no longer
    /// be imported (§7). `resolveFile` walks the target's own merge closure, so
    /// entry plus everything it merges join this module together.
    private func mergeModule(
        into module: ModuleInfo,
        spec: ResolvedModuleSpec,
        specifier: String,
        span: SourceSpan,
        unit: CompilationUnit
    ) throws {
        // Merge dissolves the target's boundary, so it stays inside one package
        // (§3.2): the target's `module_private` names become this module's and
        // its declarations join this package's identity. Another package's
        // module can only be imported, never merged. A bare file has no package
        // of its own, so any registered target is another package's.
        guard let currentOwner = module.owner, spec.owner.identity == currentOwner.identity else {
            throw ModuleError.crossPackageMerge(specifier, span: span)
        }
        let target = URL(fileURLWithPath: spec.entryFile).standardized.path
        if module.mergedSubmodules.contains(target) {
            throw ModuleError.duplicateUsing(specifier, span: span)
        }
        module.mergedSubmodules.append(target)
        try resolveFile(file: target, module: module, unit: unit)
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
        guard fileName.hasSuffix(".koral") else {
            throw ModuleError.fileMergeNotKoral(fileName, span: using.span)
        }
        let filePath = URL(fileURLWithPath: currentDir)
            .appendingPathComponent(fileName)
            .standardized
            .path

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ModuleError.fileNotFound(fileName, searchPath: currentDir)
        }

        // Merge claims ownership, so the target must live inside the current
        // package's source tree (§3.2) -- the same rule the bare form enforces
        // by package identity. With no package claiming the current file there
        // is no boundary to respect.
        if let myRoot = packageRoot(containing: currentFile) {
            guard let targetRoot = packageRoot(containing: filePath), targetRoot == myRoot else {
                throw ModuleError.crossPackageMerge(fileName, span: using.span)
            }
        }

        // A merge cycle means each file is waiting on the other's definitions
        // (§7.22). Check before the duplicate-merge case: in a ring the file is
        // still being assembled, which is the more specific story.
        if resolvingFiles.contains(filePath) {
            throw ModuleError.circularDependency(
                path: resolvingFiles + [filePath],
                file: module.entryFile
            )
        }
        if module.mergedSubmodules.contains(filePath) {
            throw ModuleError.duplicateUsing(fileName, span: using.span)
        }

        module.mergedSubmodules.append(filePath)
        try resolveFile(file: filePath, module: module, unit: unit)
    }
}

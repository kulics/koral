import Foundation

enum DriverCommand: String {
  case build
  case run
  case check
  case emitC = "emit-c"
}

public class Driver {
  /// Source manager for error rendering with code snippets
  private var sourceManager = SourceManager()

  private struct InvocationOptions {
    var packageConfigPath: String?
    var entryFilePath: String?
    var targetModuleName: String?
    var requiresRoot: String?
    var stdConfigPath: String?
    var outputDir: String?
    var noStd = false
    var optimizeArgs: [String] = Driver.defaultOptimizeArgs
  }

  /// Optimization/debug flags handed to clang for the generated C.
  /// `-O1` matches historical behaviour; `--debug` / `--release` select the
  /// conventional debug and release pair.
  private static let defaultOptimizeArgs = ["-O1"]

  /// Active clang flags for this invocation; set by `process` from the options.
  private var optimizeArgs: [String] = Driver.defaultOptimizeArgs

  public init() {}

  private func writeStdout(_ text: String, newline: Bool = true) {
    let payload = newline ? text + "\n" : text
    FileHandle.standardOutput.write(Data(payload.utf8))
  }

  private func writeStderr(_ text: String, newline: Bool = true) {
    let payload = newline ? text + "\n" : text
    FileHandle.standardError.write(Data(payload.utf8))
  }

  private func envFlag(_ name: String) -> Bool {
    guard let value = ProcessInfo.processInfo.environment[name] else {
      return false
    }
    return value == "1" || value == "true" || value == "TRUE"
  }

  private func debugPhase(_ message: String) {
    if envFlag("KORAL_DEBUG_PHASE") {
      writeStderr("[phase] \(message)")
    }
  }

  private func phaseTimingEnabled() -> Bool {
    envFlag("KORAL_PROFILE_PHASES")
  }

  private func profilePhase(_ message: String, start: DispatchTime) {
    guard phaseTimingEnabled() else {
      return
    }
    let durationMs = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    writeStderr("[phase-ms] \(message) duration_ms=\(durationMs)")
  }

  public func run(args: [String]) {
    guard args.count > 1 else {
      printUsage()
      return
    }

    let commandStr = args[1]
    if commandStr == "help" || commandStr == "-h" || commandStr == "--help" {
      printUsage()
      return
    }
    let command = DriverCommand(rawValue: commandStr)
    var mode: DriverCommand
    var remainingArgs: [String] = []

    if let cmd = command {
      mode = cmd
      if args.count > 2 {
        remainingArgs = Array(args[2...])
      }
    } else if commandStr.hasPrefix("-") {
      mode = .build
      remainingArgs = Array(args[1...])
    } else {
      mode = .build
      remainingArgs = Array(args[1...])
    }

    // Parse options
    var options = InvocationOptions()
    var i = 0
    while i < remainingArgs.count {
      let arg = remainingArgs[i]
      if arg == "-h" || arg == "--help" {
        printUsage()
        return
      } else if arg == "-o" || arg == "--output" {
        if i + 1 < remainingArgs.count {
          options.outputDir = remainingArgs[i + 1]
          i += 2
        } else {
          writeStderr("Error: Missing path for -o option")
          exit(1)
        }
      } else if arg == "--package-config" {
        if i + 1 < remainingArgs.count {
          options.packageConfigPath = remainingArgs[i + 1]
          i += 2
        } else {
          writeStderr("Error: Missing path for --package-config option")
          exit(1)
        }
      } else if arg == "--target-module" {
        if i + 1 < remainingArgs.count {
          options.targetModuleName = remainingArgs[i + 1]
          i += 2
        } else {
          writeStderr("Error: Missing value for --target-module option")
          exit(1)
        }
      } else if arg == "--requires-root" {
        if i + 1 < remainingArgs.count {
          options.requiresRoot = remainingArgs[i + 1]
          i += 2
        } else {
          writeStderr("Error: Missing path for --requires-root option")
          exit(1)
        }
      } else if arg == "--std-config" {
        if i + 1 < remainingArgs.count {
          options.stdConfigPath = remainingArgs[i + 1]
          i += 2
        } else {
          writeStderr("Error: Missing path for --std-config option")
          exit(1)
        }
      } else if arg == "--no-std" {
        options.noStd = true
        i += 1
      } else if arg == "--debug" {
        options.optimizeArgs = ["-O0", "-g"]
        i += 1
      } else if arg == "--release" {
        options.optimizeArgs = ["-O2"]
        i += 1
      } else if arg == "--optimize" {
        if i + 1 < remainingArgs.count, !remainingArgs[i + 1].hasPrefix("-") {
          let level = remainingArgs[i + 1]
          guard ["0", "1", "2", "3", "s", "fast"].contains(level) else {
            writeStderr("Error: Invalid value for --optimize (expected 0, 1, 2, 3, s or fast): \(level)")
            exit(1)
          }
          options.optimizeArgs = ["-O\(level)"]
          i += 2
        } else {
          writeStderr("Error: Missing value for --optimize option")
          exit(1)
        }
      } else if arg.hasPrefix("-") {
        writeStderr("Error: Unknown argument: \(arg)")
        printUsage()
        exit(1)
      } else {
        if options.entryFilePath == nil && options.packageConfigPath == nil {
          options.entryFilePath = arg
          i += 1
        } else {
          writeStderr("Error: Unknown positional argument: \(arg)")
          printUsage()
          exit(1)
        }
      }
    }

    if options.packageConfigPath == nil && options.entryFilePath == nil {
      writeStderr("Error: Missing input file or --package-config")
      printUsage()
      exit(1)
    }
    if options.packageConfigPath != nil && options.entryFilePath != nil {
      writeStderr("Error: Cannot combine direct file input with --package-config")
      printUsage()
      exit(1)
    }

    do {
      try process(mode: mode, options: options)
    } catch var error as DiagnosticError {
      // Attach source manager for rendering with code snippets
      error.sourceManager = sourceManager
      writeStderr(error.renderForCLI())
      exit(1)
    } catch let error as DiagnosticCollector {
      writeStderr(error.formatWithSource(sourceManager: sourceManager))
      exit(1)
    } catch let error as ParserError {
      writeStderr("Parser Error: \(error)")
      exit(1)
    } catch let error as LexerError {
      writeStderr("Lexer Error: \(error)")
      exit(1)
    } catch let error as SemanticError {
      // Fallback if semantic errors escape without being wrapped.
      writeStderr("\(error.fileName): Semantic Error: \(error)")
      exit(1)
    } catch let error as ModuleError {
      // A parse failure inside the module pipeline is still a syntax error, and
      // must be reported like one -- same location/stage/message shape as every
      // other parse diagnostic. Only genuine module-resolution problems get the
      // `Module Error` framing.
      if case .parseError(let file, let underlying) = error {
        let stage: DiagnosticError.Stage
        if underlying is LexerError {
          stage = .lexer
        } else if underlying is ParserError {
          stage = .parser
        } else {
          stage = .other
        }
        var diagnostic = DiagnosticError(
          stage: stage, fileName: file, underlying: underlying)
        diagnostic.sourceManager = sourceManager
        writeStderr(diagnostic.renderForCLI())
        exit(1)
      }
      // No `Module Error:` category prefix. A module-resolution failure that
      // carries a span goes through `renderForCLI()` above like every other
      // diagnostic; this branch is the span-less remainder, and it prints its
      // message alone -- the same shape the bootstrap compiler uses.
      writeStderr("\(error)")
      exit(1)
    } catch let error as AccessError {
      writeStderr("Access Error: \(error)")
      exit(1)
    } catch {
      writeStderr("Error: \(error)")
      exit(1)
    }
  }

  private func parseProgram(source: String, fileName: String) throws -> [GlobalNode] {
    // Register source with source manager for error rendering
    sourceManager.loadFile(name: fileName, content: source)
    
    let lexer = Lexer(input: source)
    let parser = Parser(lexer: lexer)
    do {
      let ast = try parser.parse()
      guard case .program(let nodes) = ast else {
        throw DiagnosticError(
          stage: .other,
          fileName: fileName,
          underlying: NSError(
            domain: "Driver", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid program structure"]
          ),
          sourceManager: sourceManager
        )
      }
      return nodes
    } catch let error as LexerError {
      throw DiagnosticError(stage: .lexer, fileName: fileName, underlying: error, sourceManager: sourceManager)
    } catch let error as ParserError {
      throw DiagnosticError(stage: .parser, fileName: fileName, underlying: error, sourceManager: sourceManager)
    }
  }

  private func registerModuleSources(from module: ModuleInfo, displayPrefix: String) {
    if let source = try? String(contentsOfFile: module.entryFile, encoding: .utf8) {
      let displayName = "\(displayPrefix)/" + URL(fileURLWithPath: module.entryFile).lastPathComponent
      sourceManager.loadFile(name: displayName, content: source)
    }
    for mergedSubmodule in module.mergedSubmodules {
      if let source = try? String(contentsOfFile: mergedSubmodule, encoding: .utf8) {
        let displayName = "\(displayPrefix)/" + URL(fileURLWithPath: mergedSubmodule).lastPathComponent
        sourceManager.loadFile(name: displayName, content: source)
      }
    }
  }

  private func sanitizeModuleArtifactName(_ moduleName: String) -> String {
    moduleName
      .replacingOccurrences(of: "::", with: "__")
      .replacingOccurrences(of: "/", with: "__")
  }

  private func packageID(for kind: ResolvedPackageKind, packageName: String) -> String {
    switch kind {
    case .root:
      return "root:\(packageName)"
    case .std:
      return "std:\(packageName)"
    case .dependency(let key):
      return "dependency:\(key)"
    }
  }

  /// The default build target is the main module -- the one declared under the
  /// `modules` key `"."`. A package with no main module has no default (§5.1);
  /// the caller has to say which module it wants.
  private func mainModuleFullName(of package: LoadedPackage) -> String? {
    guard package.manifest.modules["."] != nil else { return nil }
    return package.selfName
  }

  /// Turn a module full name written the way source writes it
  /// (`package[/subpath]`) into the module it names, looked up in `root`'s
  /// table -- a build target is named from the project's own point of view.
  private func resolveTargetSpec(
    named rawName: String,
    root: LoadedPackage,
    registry: PackageRegistry
  ) throws -> ResolvedModuleSpec {
    let parts = rawName.split(separator: "/").map(String.init)
    guard let head = parts.first, isValidPackageOrSegmentName(head) else {
      throw PackageManifestError.missingTargetModule(rawName)
    }
    guard let owner = registry.resolveName(head, from: root) else {
      throw PackageManifestError.unknownPackageName(
        name: head,
        context: "--target-module",
        known: registry.knownNames(for: root)
      )
    }
    let subpath = parts.dropFirst().joined(separator: "/")
    let key = subpath.isEmpty ? "." : subpath
    guard let config = owner.manifest.modules[key] else {
      if subpath.isEmpty {
        // Naming the package root asks for the main module. Say that this
        // package has none and what it does have -- stuffing the reason into
        // the name yields a target name nobody wrote.
        throw PackageManifestError.noMainModule(
          packageName: owner.selfName,
          declared: owner.manifest.modules.keys.sorted()
        )
      }
      throw PackageManifestError.missingTargetModule(rawName)
    }
    let rootName = rootViewName(of: owner, registry: registry, root: root)
    return makeResolvedModuleSpec(key: key, config: config, rootName: rootName, owner: owner)
  }

  /// The standard library's main module is the prelude: it is compiled in and
  /// in scope in every non-std module without being named (see
  /// `VisibilityChecker`, "std root is a compiler-provided prelude"). It is
  /// therefore NOT part of the `using` graph -- it is the base the graph sits
  /// on, which is what §6.4's "主模块是基础层" means.
  private func loadPrelude(
    registry: PackageRegistry,
    resolver: ModuleResolver,
    unit: CompilationUnit
  ) throws {
    guard let stdPackage = registry.stdPackage else { return }
    guard let config = stdPackage.manifest.modules["."] else { return }
    let spec = makeResolvedModuleSpec(key: ".", config: config, rootName: "std", owner: stdPackage)
    guard unit.loadedModules[spec.fullName] == nil else { return }
    do {
      _ = try resolver.resolveModule(spec: spec, unit: unit)
    } catch let error as ModuleError {
      throw DiagnosticError(
        stage: .other,
        fileName: error.locationFile ?? spec.entryFile,
        underlying: error,
        sourceManager: sourceManager
      )
    }
  }

  /// Load the target module and everything its `using` statements reach. The
  /// module graph is exactly those edges (§5.4) -- nothing is loaded that no
  /// `using` asked for, and nothing that IS asked for is skipped.
  private func loadCompilationUnit(
    targetSpec: ResolvedModuleSpec,
    registry: PackageRegistry,
    root: LoadedPackage
  ) throws -> (unit: CompilationUnit, resolver: ModuleResolver) {
    let resolver = initializeModuleResolver()
    resolver.registry = registry
    resolver.rootPackage = root
    let unit = CompilationUnit()
    do {
      try loadPrelude(registry: registry, resolver: resolver, unit: unit)
      _ = try resolver.resolveModule(spec: targetSpec, unit: unit)
    } catch let error as ModuleError {
      throw DiagnosticError(
        stage: error.stage,
        fileName: error.locationFile ?? targetSpec.entryFile,
        underlying: error,
        sourceManager: sourceManager
      )
    }
    return (unit, resolver)
  }

  /// `links` follow the code (§5.4): a module that needs `-lm` says so, and
  /// anything that imports that module inherits the requirement.
  private func linkedLibraries(in unit: CompilationUnit) -> [String] {
    var result: [String] = []
    for name in unit.loadOrder {
      guard let spec = unit.loadedModules[name]?.spec else { continue }
      result.append(contentsOf: spec.links)
    }
    return result
  }

  private func registerLoadedSources(unit: CompilationUnit) {
    for name in unit.loadOrder {
      guard let module = unit.loadedModules[name] else { continue }
      let displayPrefix = module.spec?.fullName ?? module.path.joined(separator: "/")
      registerModuleSources(from: module, displayPrefix: displayPrefix)
    }
  }

  /// Split loaded nodes into standard-library and everything else, and give
  /// each the package identity the later passes key visibility on.
  private func collectNodes(from unit: CompilationUnit) -> (
    stdGlobalNodes: [GlobalNode],
    stdNodeSourceInfoList: [GlobalNodeSourceInfo],
    userGlobalNodes: [GlobalNode],
    userNodeSourceInfoList: [GlobalNodeSourceInfo]
  ) {
    var stdGlobalNodes: [GlobalNode] = []
    var stdNodeSourceInfoList: [GlobalNodeSourceInfo] = []
    var userGlobalNodes: [GlobalNode] = []
    var userNodeSourceInfoList: [GlobalNodeSourceInfo] = []

    // Load order is discovery order. The symbol tables want an order that does
    // not depend on which `using` happened to be seen first, so emit in
    // MODULE-PATH order -- the same key the bootstrap compiler sorts by, since
    // the two must build identical tables from identical input.
    let orderedModules = unit.loadOrder.compactMap { unit.loadedModules[$0] }
      .sorted { $0.pathString < $1.pathString }
    for module in orderedModules {
      // A module with no manifest behind it is a bare-file entry point, which
      // is never part of the standard library.
      let isStd: Bool
      if let spec = module.spec, case .std = spec.packageKind {
        isStd = true
      } else {
        isStd = false
      }
      let packageID = module.spec.map { packageID(for: $0.packageKind, packageName: $0.packageIdentity) }
        ?? "single:unspecified"
      for (node, sourceFile) in module.globalNodes {
        let sourceInfo = GlobalNodeSourceInfo(
          sourceFile: sourceFile,
          modulePath: module.path,
          packageID: packageID,
          node: node
        )
        if isStd {
          stdGlobalNodes.append(node)
          stdNodeSourceInfoList.append(sourceInfo)
        } else {
          userGlobalNodes.append(node)
          userNodeSourceInfoList.append(sourceInfo)
        }
      }
    }
    return (stdGlobalNodes, stdNodeSourceInfoList, userGlobalNodes, userNodeSourceInfoList)
  }

  private func process(mode: DriverCommand, options: InvocationOptions) throws {
    optimizeArgs = options.optimizeArgs
    if let packageConfigPath = options.packageConfigPath {
      try processPackage(
        packageConfigPath: packageConfigPath,
        targetModuleName: options.targetModuleName,
        mode: mode,
        outputDir: options.outputDir,
        noStd: options.noStd,
        requiresRoot: options.requiresRoot,
        stdConfigPath: options.stdConfigPath
      )
      return
    }

    guard let entryFilePath = options.entryFilePath else {
      throw NSError(
        domain: "Driver",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing input file or --package-config"]
      )
    }

    try processSingleFile(
      entryFilePath: entryFilePath,
      mode: mode,
      outputDir: options.outputDir,
      noStd: options.noStd,
      stdConfigPath: options.stdConfigPath
    )
  }

  private func processPackage(
    packageConfigPath: String,
    targetModuleName: String?,
    mode: DriverCommand,
    outputDir: String?,
    noStd: Bool,
    requiresRoot: String?,
    stdConfigPath: String?
  ) throws {
    let packageConfigURL = URL(fileURLWithPath: packageConfigPath).standardized
    let resolvedStdConfigPath = noStd ? nil : (stdConfigPath ?? getStdManifestPath())
    let registry = try loadPackageRegistry(
      rootManifestPath: packageConfigURL.path,
      stdManifestPath: resolvedStdConfigPath,
      fetchRoot: requiresRoot
    )
    guard let root = registry.rootPackage else {
      throw PackageManifestError.fileNotFound(packageConfigURL.path)
    }

    let targetFullName: String
    if let targetModuleName {
      targetFullName = targetModuleName
    } else if let mainName = mainModuleFullName(of: root) {
      targetFullName = mainName
    } else {
      // No main module means there is no default build target (§5.1). Name a
      // placeholder and the reader is told a module called '<unspecified>' is
      // missing; say what is actually missing instead.
      throw PackageManifestError.message("Missing default target module; pass --target-module")
    }
    let targetSpec = try resolveTargetSpec(named: targetFullName, root: root, registry: registry)

    let (unit, _) = try loadCompilationUnit(targetSpec: targetSpec, registry: registry, root: root)

    let packageRootURL = packageConfigURL.deletingLastPathComponent()
    let outputDirectory: URL
    if let outputDir {
      outputDirectory = URL(fileURLWithPath: outputDir).standardized
    } else {
      outputDirectory = packageRootURL
    }

    let baseName = sanitizeModuleArtifactName(targetFullName)
    let parts = collectNodes(from: unit)
    registerLoadedSources(unit: unit)

    try performCompilation(
      baseName: baseName,
      outputDirectory: outputDirectory,
      mode: mode,
      stdDisplayName: resolvedStdConfigPath ?? "std/koral.json",
      userDisplayName: targetFullName,
      stdGlobalNodes: parts.stdGlobalNodes,
      allGlobalNodes: parts.stdGlobalNodes + parts.userGlobalNodes,
      nodeSourceInfoList: parts.stdNodeSourceInfoList + parts.userNodeSourceInfoList,
      importGraph: unit.importGraph,
      extraLinkedLibraries: linkedLibraries(in: unit)
    )
  }

  private func processSingleFile(
    entryFilePath: String,
    mode: DriverCommand,
    outputDir: String?,
    noStd: Bool,
    stdConfigPath: String?
  ) throws {
    let entryURL = URL(fileURLWithPath: entryFilePath).standardized
    let resolver = initializeModuleResolver()
    let unit = CompilationUnit()

    // A bare file has no package of its own. The standard library is still
    // nameable -- `using "std/io";` is a package import even here -- so the
    // registry std brings with it is installed before the file is read.
    if !noStd, let resolvedStdConfigPath = stdConfigPath ?? getStdManifestPath() {
      let stdRegistry = try loadPackageRegistry(
        rootManifestPath: resolvedStdConfigPath,
        stdManifestPath: resolvedStdConfigPath,
        fetchRoot: nil
      )
      if let stdPackage = stdRegistry.stdPackage {
        resolver.registry = stdRegistry
        resolver.rootPackage = stdPackage
      }
    }

    let entryModule = ModuleInfo(
      path: [moduleFileNameToIdentifier(entryURL.deletingPathExtension().lastPathComponent)],
      entryFile: entryURL.path
    )
    if let registry = resolver.registry {
      try loadPrelude(registry: registry, resolver: resolver, unit: unit)
    }
    unit.loadedModules[entryModule.pathString] = entryModule
    unit.loadOrder.append(entryModule.pathString)

    do {
      try resolver.resolveSingleFile(into: entryModule, unit: unit)
    } catch let error as ModuleError {
      throw DiagnosticError(
        stage: error.stage,
        fileName: error.locationFile ?? entryURL.path,
        underlying: error,
        sourceManager: sourceManager
      )
    }

    let parts = collectNodes(from: unit)
    registerLoadedSources(unit: unit)

    let outputDirectory = outputDir.map { URL(fileURLWithPath: $0).standardized }
      ?? entryURL.deletingLastPathComponent()
    let baseName = entryURL.deletingPathExtension().lastPathComponent

    try performCompilation(
      baseName: baseName,
      outputDirectory: outputDirectory,
      mode: mode,
      stdDisplayName: stdConfigPath ?? "std/koral.json",
      userDisplayName: entryURL.path,
      stdGlobalNodes: parts.stdGlobalNodes,
      allGlobalNodes: parts.stdGlobalNodes + parts.userGlobalNodes,
      nodeSourceInfoList: parts.stdNodeSourceInfoList + parts.userNodeSourceInfoList,
      importGraph: unit.importGraph,
      extraLinkedLibraries: linkedLibraries(in: unit)
    )
  }

  private func performCompilation(
    baseName: String,
    outputDirectory: URL,
    mode: DriverCommand,
    stdDisplayName: String,
    userDisplayName: String,
    stdGlobalNodes: [GlobalNode],
    allGlobalNodes: [GlobalNode],
    nodeSourceInfoList: [GlobalNodeSourceInfo],
    importGraph: ImportGraph,
    extraLinkedLibraries: [String]
  ) throws {
    let fileManager = FileManager.default
    // Shared ambient for name resolution: a spelling resolves through the
    // importing module's imports, not through a global name table. Installed
    // here so every pass sees it regardless of which `DefIdMap` instance it
    // holds -- see `DefIdMap.sharedImportGraph`.
    DefIdMap.sharedImportGraph = importGraph
    let combinedAST: ASTNode = .program(globalNodes: allGlobalNodes)
    let phasePrefix = mode.rawValue
    let totalStart = DispatchTime.now()

    debugPhase("\(phasePrefix): type check")
    let typeCheckStart = DispatchTime.now()
    let typeChecker = TypeChecker(
      ast: combinedAST,
      nodeSourceInfoList: nodeSourceInfoList,
      coreGlobalCount: stdGlobalNodes.count,
      coreFileName: stdDisplayName,
      userFileName: userDisplayName,
      importGraph: importGraph
    )
    let typeCheckerOutput: TypeCheckerOutput
    do {
      typeCheckerOutput = try typeChecker.check()
    } catch let error as SemanticError {
      throw DiagnosticError(
        stage: .semantic,
        fileName: error.fileName,
        underlying: error,
        sourceManager: sourceManager
      )
    }
    profilePhase("\(phasePrefix): type check", start: typeCheckStart)

    if mode == .check {
      debugPhase("check: done")
      return
    }

    debugPhase("\(phasePrefix): monomorphize")
    let monoStart = DispatchTime.now()
    let monomorphizer = Monomorphizer(input: typeCheckerOutput)
    let monomorphizedProgram: MonomorphizedProgram
    do {
      monomorphizedProgram = try monomorphizer.monomorphize()
    } catch let error as SemanticError {
      throw DiagnosticError(
        stage: .semantic,
        fileName: error.fileName,
        underlying: error,
        sourceManager: sourceManager
      )
    }
    profilePhase("\(phasePrefix): monomorphize", start: monoStart)

    debugPhase("\(phasePrefix): mir")
    let mirStart = DispatchTime.now()
    let mirProgram = MIRLowerer(
      program: monomorphizedProgram,
      context: monomorphizer.context
    ).lower()
    try MIRVerifier(program: mirProgram).verify()
    let dumpMIR = envFlag("KORAL_DUMP_MIR")
    let dumpMIRStats = envFlag("KORAL_DUMP_MIR_STATS")
    if dumpMIR || dumpMIRStats {
      let mirPrinter = MIRPrinter(program: mirProgram)
      if dumpMIR {
        writeStderr(mirPrinter.render(), newline: false)
      } else {
        writeStderr(mirPrinter.renderSummary(), newline: false)
      }
    }
    profilePhase("\(phasePrefix): mir", start: mirStart)

    debugPhase("\(phasePrefix): codegen")
    let codegenStart = DispatchTime.now()
    let codeGen = CodeGen(
      mirProgram: mirProgram,
      context: monomorphizer.context
    )
    let cSource = codeGen.generate()
    profilePhase("\(phasePrefix): codegen", start: codegenStart)

    if !fileManager.fileExists(atPath: outputDirectory.path) {
      try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    let cFileURL: URL
    var temporaryCFileURL: URL?
    if mode == .emitC {
      cFileURL = outputDirectory.appendingPathComponent("\(baseName).c")
    } else {
      let tempFileName = "koralc_\(baseName)_\(UUID().uuidString).c"
      let tempFileURL = fileManager.temporaryDirectory.appendingPathComponent(tempFileName)
      cFileURL = tempFileURL
      temporaryCFileURL = tempFileURL
    }
    try cSource.write(to: cFileURL, atomically: true, encoding: .utf8)

    defer {
      if let temporaryCFileURL {
        try? fileManager.removeItem(at: temporaryCFileURL)
      }
    }

    if mode == .emitC {
      debugPhase("emit-c: done")
      profilePhase("emit-c: total", start: totalStart)
      return
    }

    #if os(Windows)
    let exeURL = outputDirectory.appendingPathComponent(baseName + ".exe")
    #else
    let exeURL = outputDirectory.appendingPathComponent(baseName)
    #endif

    var clangArgs = [cFileURL.path]
    if let stdPath = getStdLibPath() {
      let runtimeURL = URL(fileURLWithPath: stdPath).appendingPathComponent("koral_runtime.c")
      if FileManager.default.fileExists(atPath: runtimeURL.path) {
        clangArgs.append(runtimeURL.path)
      }
      clangArgs.append(contentsOf: ["-I", stdPath])
    }

    clangArgs.append("-o")
    clangArgs.append(exeURL.path)
    clangArgs.append("-Wno-everything")
    clangArgs.append(contentsOf: optimizeArgs)

    let linkedLibraries = Array(NSOrderedSet(array: extraLinkedLibraries)) as? [String] ?? extraLinkedLibraries
    for lib in linkedLibraries {
      if lib == "c" { continue }
      clangArgs.append("-l\(lib)")
    }

    #if os(Windows)
    if !linkedLibraries.contains("bcrypt") {
      clangArgs.append("-lbcrypt")
    }
    if !linkedLibraries.contains("ws2_32") {
      clangArgs.append("-lws2_32")
    }
    if !linkedLibraries.contains("psapi") {
      clangArgs.append("-lpsapi")
    }
    #endif

    #if os(macOS)
    if let sdkPath = getSDKPath() {
      clangArgs.append(contentsOf: ["-isysroot", sdkPath])
    }
    #endif

    debugPhase("\(phasePrefix): clang")
    let clangStart = DispatchTime.now()
    let clangPath = findExecutable("clang") ?? "/usr/bin/clang"
    let clangResult = try runSubprocess(executable: clangPath, args: clangArgs)
    profilePhase("\(phasePrefix): clang", start: clangStart)
    if clangResult != 0 {
      profilePhase("\(phasePrefix): total", start: totalStart)
      throw NSError(
        domain: "Driver",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Clang compilation failed"]
      )
    }

    if mode == .build {
      debugPhase("build: done")
      profilePhase("build: total", start: totalStart)
      writeStdout("Build successful: \(exeURL.path)")
      return
    }

    if mode == .run {
      let runResult = try runSubprocess(executable: exeURL.path, args: [])
      profilePhase("run: total", start: totalStart)
      if runResult != 0 {
        exit(runResult)
      }
    }
  }

  func getCoreLibPath() -> String {
    if let stdManifestPath = getStdManifestPath() {
      let legacyEntry = URL(fileURLWithPath: stdManifestPath)
        .deletingLastPathComponent()
        .appendingPathComponent("std.koral")
        .path
      if FileManager.default.fileExists(atPath: legacyEntry) {
        return legacyEntry
      }
    }

    // Check KORAL_HOME environment variable first
    if let koralHome = ProcessInfo.processInfo.environment["KORAL_HOME"] {
        let path = URL(fileURLWithPath: koralHome).appendingPathComponent("std/std.koral").path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    // Fallback: Try common relative locations (package root, repo root, build dirs)
    let currentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidatePaths = [
      currentURL.appendingPathComponent("std/std.koral").path,
      currentURL.deletingLastPathComponent().appendingPathComponent("std/std.koral").path,
      currentURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("std/std.koral").path
    ]
    for path in candidatePaths {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    writeStderr("Error: Could not locate std/std.koral. Please set KORAL_HOME environment variable.")
    exit(1)
  }

  func getStdManifestPath() -> String? {
    if let koralHome = ProcessInfo.processInfo.environment["KORAL_HOME"] {
      let path = URL(fileURLWithPath: koralHome).appendingPathComponent("std/koral.json").path
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    let currentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidatePaths = [
      currentURL.appendingPathComponent("std/koral.json").path,
      currentURL.deletingLastPathComponent().appendingPathComponent("std/koral.json").path,
      currentURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("std/koral.json").path
    ]
    for path in candidatePaths {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    return nil
  }
  
  /// Gets the standard library directory path
  func getStdLibPath() -> String? {
    if let stdManifestPath = getStdManifestPath() {
      return URL(fileURLWithPath: stdManifestPath).deletingLastPathComponent().path
    }

    // Check KORAL_HOME environment variable first
    if let koralHome = ProcessInfo.processInfo.environment["KORAL_HOME"] {
        let path = URL(fileURLWithPath: koralHome).appendingPathComponent("std").path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    // Fallback: Try common relative locations (package root, repo root, build dirs)
    let currentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidatePaths = [
      currentURL.appendingPathComponent("std").path,
      currentURL.deletingLastPathComponent().appendingPathComponent("std").path,
      currentURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("std").path
    ]
    for path in candidatePaths {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    return nil
  }
  
  /// Initializes the module resolver with appropriate paths
  private func initializeModuleResolver() -> ModuleResolver {
    let stdLibPath = getStdLibPath()
    return ModuleResolver(stdLibPath: stdLibPath, externalPaths: [])
  }

  func getSDKPath() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--show-sdk-path"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } catch {
        return nil
    }
    return nil
  }

  func runSubprocess(executable: String, args: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args

    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    try process.run()
    process.waitUntilExit()
    
    return process.terminationStatus
  }

  func findExecutable(_ name: String) -> String? {
    #if os(Windows)
    let pathSeparator: Character = ";"
    let extensions = [".exe", ".cmd", ".bat", ""]
    // On Windows, environment variable names are case-insensitive but Swift may be case-sensitive
    let pathEnv = ProcessInfo.processInfo.environment["PATH"] 
                  ?? ProcessInfo.processInfo.environment["Path"]
                  ?? ProcessInfo.processInfo.environment["path"]
                  ?? ""
    #else
    let pathSeparator: Character = ":"
    let extensions = [""]
    let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
    #endif
    
    let paths = pathEnv.split(separator: pathSeparator).map(String.init)
    
    for path in paths {
        let dirURL = URL(fileURLWithPath: path)
        for ext in extensions {
            let exeURL = dirURL.appendingPathComponent(name + ext)
            if FileManager.default.fileExists(atPath: exeURL.path) {
                return exeURL.path
            }
        }
    }
    return nil
  }

  func printUsage() {
    writeStdout(
      """
      Usage: koralc [command] [--package-config <koral.json> | <file.koral>] [--target-module <module>] [options]

      Commands:
        help    Show this help text
        build   Compile to executable (default)
        check   Type-check only (no code generation)
        run     Compile and run
        emit-c  Generate C code only

      Options:
        -h, --help                Show this help text
        -o, --output <path>       Output directory for generated files
        --package-config <path>   Package manifest path for manifest-driven builds
        --target-module <name>    Target module full name, e.g. app::main
        --requires-root <path>        Root directory for resolved requires
        --std-config <path>       Standard library manifest path
        --no-std                  Compile without standard library

      Build mode (selects the clang flags used for the generated C):
        --debug                   -O0 -g   (unoptimized, debuggable)
        --release                 -O2      (optimized)
        --optimize <level>        Explicit clang level: 0, 1, 2, 3, s or fast
                                  Default: -O1
      """
    )
  }
}

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
    var depsRoot: String?
    var stdConfigPath: String?
    var outputDir: String?
    var noStd = false
    var escapeAnalysisReport = false
  }
  
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
    let command = DriverCommand(rawValue: commandStr)
    let mode: DriverCommand
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
      writeStderr("Unknown command or file: \(commandStr)")
      printUsage()
      return
    }

    // Parse options
    var options = InvocationOptions()
    var escapeAnalysisLevel = 0
    var i = 0
    while i < remainingArgs.count {
      let arg = remainingArgs[i]
      if arg == "-o" || arg == "--output" {
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
      } else if arg == "--deps-root" {
        if i + 1 < remainingArgs.count {
          options.depsRoot = remainingArgs[i + 1]
          i += 2
        } else {
          writeStderr("Error: Missing path for --deps-root option")
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
      } else if arg == "-m" {
        // Go-style escape analysis flag.
        // Repeated -m increases verbosity level (currently same output).
        escapeAnalysisLevel += 1
        i += 1
      } else if arg.hasPrefix("-m=") {
        // Go-style explicit level: -m=1, -m=2, ...
        let levelString = String(arg.dropFirst(3))
        if let level = Int(levelString), level > 0 {
          escapeAnalysisLevel = max(escapeAnalysisLevel, level)
          i += 1
        } else {
          writeStderr("Error: Invalid value for -m: \(levelString)")
          exit(1)
        }
      } else if arg.hasPrefix("-") {
        i += 1
      } else {
        if options.entryFilePath == nil && options.packageConfigPath == nil {
          options.entryFilePath = arg
          i += 1
        } else {
          writeStderr("Unknown positional argument: \(arg)")
          printUsage()
          return
        }
      }
    }

    options.escapeAnalysisReport = escapeAnalysisLevel > 0

    if options.packageConfigPath == nil && options.entryFilePath == nil {
      writeStderr("Error: Missing input file or --package-config")
      printUsage()
      return
    }
    if options.packageConfigPath != nil && options.entryFilePath != nil {
      writeStderr("Error: Cannot combine direct file input with --package-config")
      printUsage()
      return
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
      writeStderr("Module Error: \(error)")
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
    moduleName.replacingOccurrences(of: "::", with: "__")
  }

  private func splitModuleName(_ moduleName: String) -> [String] {
    moduleName
      .split(separator: ":")
      .map(String.init)
      .filter { !$0.isEmpty }
      .map(moduleFileNameToIdentifier)
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

  private func defaultTargetModuleName(in manifest: PackageManifest) -> String? {
    if let defaultTargetModuleName = manifest.defaultTargetModuleName {
      if manifest.modules[defaultTargetModuleName] != nil {
        return defaultTargetModuleName
      }
    }
    if manifest.modules.count == 1 {
      return manifest.modules.keys.first
    }
    return nil
  }

  private func loadManifestModules(
    manifest: PackageManifest,
    resolver: ModuleResolver
  ) throws -> (
    globalNodes: [GlobalNode],
    nodeSourceInfoList: [GlobalNodeSourceInfo],
    importGraph: ImportGraph,
    rootModulePath: [String]?,
    loadedModulePaths: [[String]],
    linkedLibraries: [String]
  ) {
    var globalNodes: [GlobalNode] = []
    var nodeSourceInfoList: [GlobalNodeSourceInfo] = []
    var importGraph = ImportGraph()
    var rootModulePath: [String]?
    var loadedModulePaths: [[String]] = []
    var linkedLibraries: [String] = []

    for moduleName in manifest.modules.keys.sorted() {
      guard let spec = manifest.modules[moduleName] else { continue }
      let compilationUnit = try resolver.resolveModule(
        entryFile: spec.entryPath,
        rootModulePath: spec.pathSegments,
      )
      let nodesWithInfo = compilationUnit.getAllGlobalNodesWithSourceInfo()
      for (node, sourceFile, modulePath) in nodesWithInfo {
        globalNodes.append(node)
        nodeSourceInfoList.append(
          GlobalNodeSourceInfo(
            sourceFile: sourceFile,
            modulePath: modulePath,
            packageID: "manifest:\(manifest.name)",
            node: node
          )
        )
      }
      importGraph.merge(compilationUnit.importGraph)
      registerModuleSources(from: compilationUnit.rootModule, displayPrefix: moduleName)
      loadedModulePaths.append(spec.pathSegments)
      linkedLibraries.append(contentsOf: manifest.links)
      linkedLibraries.append(contentsOf: spec.links)
      if rootModulePath == nil && !moduleName.contains("::") {
        rootModulePath = spec.pathSegments
      }
    }

    if rootModulePath == nil {
      rootModulePath = loadedModulePaths.first
    }

    return (
      globalNodes: globalNodes,
      nodeSourceInfoList: nodeSourceInfoList,
      importGraph: importGraph,
      rootModulePath: rootModulePath,
      loadedModulePaths: loadedModulePaths,
      linkedLibraries: linkedLibraries
    )
  }

  private func process(mode: DriverCommand, options: InvocationOptions) throws {
    if let packageConfigPath = options.packageConfigPath {
      try processPackage(
        packageConfigPath: packageConfigPath,
        targetModuleName: options.targetModuleName,
        mode: mode,
        outputDir: options.outputDir,
        noStd: options.noStd,
        escapeAnalysisReport: options.escapeAnalysisReport,
        depsRoot: options.depsRoot,
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
      escapeAnalysisReport: options.escapeAnalysisReport,
      stdConfigPath: options.stdConfigPath
    )
  }

  private func loadAllModules(
    manifest: PackageManifest,
    displayPrefixSelector: (String) -> String,
    resolver: ModuleResolver
  ) throws -> (
    globalNodes: [GlobalNode],
    nodeSourceInfoList: [GlobalNodeSourceInfo],
    importGraph: ImportGraph,
    loadedModulePaths: [[String]],
    linkedLibraries: [String],
    rootModulePath: [String]?
  ) {
    var globalNodes: [GlobalNode] = []
    var nodeSourceInfoList: [GlobalNodeSourceInfo] = []
    var importGraph = ImportGraph()
    var linkedLibraries: [String] = []
    var rootModulePath: [String]?
    var loadedModulePaths: [[String]] = []

    for moduleName in manifest.modules.keys.sorted() {
      guard let spec = manifest.modules[moduleName] else { continue }
      let compilationUnit = try resolver.resolveModule(
        entryFile: spec.entryPath,
        rootModulePath: spec.pathSegments
      )
      let nodesWithInfo = compilationUnit.getAllGlobalNodesWithSourceInfo()
      for (node, sourceFile, modulePath) in nodesWithInfo {
        globalNodes.append(node)
        nodeSourceInfoList.append(
          GlobalNodeSourceInfo(
            sourceFile: sourceFile,
            modulePath: modulePath,
            packageID: "manifest:\(manifest.name)",
            node: node
          )
        )
      }
      importGraph.merge(compilationUnit.importGraph)
      registerModuleSources(from: compilationUnit.rootModule, displayPrefix: displayPrefixSelector(moduleName))
      loadedModulePaths.append(spec.pathSegments)
      linkedLibraries.append(contentsOf: manifest.links)
      linkedLibraries.append(contentsOf: spec.links)
      if rootModulePath == nil && !moduleName.contains("::") {
        rootModulePath = spec.pathSegments
      }
    }

    return (
      globalNodes: globalNodes,
      nodeSourceInfoList: nodeSourceInfoList,
      importGraph: importGraph,
      loadedModulePaths: loadedModulePaths,
      linkedLibraries: linkedLibraries,
      rootModulePath: rootModulePath
    )
  }

  private func processPackage(
    packageConfigPath: String,
    targetModuleName: String?,
    mode: DriverCommand,
    outputDir: String?,
    noStd: Bool,
    escapeAnalysisReport: Bool,
    depsRoot: String?,
    stdConfigPath: String?
  ) throws {
    let packageConfigURL = URL(fileURLWithPath: packageConfigPath).standardized
    let manifest = try loadPackageManifest(at: packageConfigURL.path)
    guard let resolvedTargetModuleName = targetModuleName ?? defaultTargetModuleName(in: manifest) else {
      throw PackageManifestError.missingTargetModule("<unspecified>")
    }
    let resolvedStdConfigPath = noStd ? nil : (stdConfigPath ?? getStdManifestPath())
    let packageGraph = try loadResolvedPackageGraph(
      rootManifestPath: packageConfigURL.path,
      targetModuleName: resolvedTargetModuleName,
      stdManifestPath: resolvedStdConfigPath,
      depsRoot: depsRoot
    )

    let baseName = sanitizeModuleArtifactName(packageGraph.targetModuleName)
    let packageRootURL = packageConfigURL.deletingLastPathComponent()
    let outputDirectory: URL
    if let outputDir {
      outputDirectory = URL(fileURLWithPath: outputDir).standardized
    } else {
      outputDirectory = packageRootURL
    }

    let resolver = initializeModuleResolver()
    var stdGlobalNodes: [GlobalNode] = []
    var stdNodeSourceInfoList: [GlobalNodeSourceInfo] = []
    var userGlobalNodes: [GlobalNode] = []
    var userNodeSourceInfoList: [GlobalNodeSourceInfo] = []
    var mergedImportGraph = ImportGraph()
    var extraLinkedLibraries: [String] = []
    let moduleNamesToLoad = packageGraph.modulesByName.keys.sorted { lhs, rhs in
      let lhsStd = packageGraph.modulesByName[lhs].map {
        if case .std = $0.packageKind { return true }
        return false
      } ?? false
      let rhsStd = packageGraph.modulesByName[rhs].map {
        if case .std = $0.packageKind { return true }
        return false
      } ?? false
      if lhsStd != rhsStd {
        return lhsStd && !rhsStd
      }
      let lhsReachable = packageGraph.reachableModuleNames.contains(lhs)
      let rhsReachable = packageGraph.reachableModuleNames.contains(rhs)
      if lhsReachable != rhsReachable {
        return lhsReachable && !rhsReachable
      }
      return lhs < rhs
    }.filter { moduleName in
      guard let spec = packageGraph.modulesByName[moduleName] else { return false }
      switch spec.packageKind {
      case .std:
        return true
      case .root, .dependency:
        return packageGraph.reachableModuleNames.contains(moduleName)
      }
    }

    for moduleName in moduleNamesToLoad {
      guard let spec = packageGraph.modulesByName[moduleName] else { continue }
      let isStdModule: Bool
      switch spec.packageKind {
      case .std:
        isStdModule = true
      case .root, .dependency:
        isStdModule = false
      }

      do {
        let currentPackageID = packageID(for: spec.packageKind, packageName: spec.packageName)
        resolver.manifestModuleAliases = spec.visibleModuleAliases
        defer { resolver.manifestModuleAliases = [] }
        let compilationUnit = try resolver.resolveModule(
          entryFile: spec.entryFile,
          rootModulePath: spec.pathSegments,
      )
        let nodesWithInfo = compilationUnit.getAllGlobalNodesWithSourceInfo()
        for (node, sourceFile, modulePath) in nodesWithInfo {
          let info = GlobalNodeSourceInfo(
            sourceFile: sourceFile,
            modulePath: modulePath,
            packageID: currentPackageID,
            node: node
          )
          if isStdModule {
            stdGlobalNodes.append(node)
            stdNodeSourceInfoList.append(info)
          } else {
            userGlobalNodes.append(node)
            userNodeSourceInfoList.append(info)
          }
        }
        mergedImportGraph.merge(compilationUnit.importGraph)
        registerModuleSources(from: compilationUnit.rootModule, displayPrefix: moduleName)
      } catch let error as ModuleError {
        throw DiagnosticError(
          stage: .other,
          fileName: spec.entryFile,
          underlying: error,
          sourceManager: sourceManager
        )
      }

      extraLinkedLibraries.append(contentsOf: spec.links)
    }

    let allGlobalNodes = stdGlobalNodes + userGlobalNodes
    let nodeSourceInfoList = stdNodeSourceInfoList + userNodeSourceInfoList

    try performCompilation(
      baseName: baseName,
      outputDirectory: outputDirectory,
      mode: mode,
      escapeAnalysisReport: escapeAnalysisReport,
      stdDisplayName: resolvedStdConfigPath ?? "std/koral.json",
      userDisplayName: packageGraph.targetModuleName,
      stdGlobalNodes: stdGlobalNodes,
      allGlobalNodes: allGlobalNodes,
      nodeSourceInfoList: nodeSourceInfoList,
      importGraph: mergedImportGraph,
      extraLinkedLibraries: extraLinkedLibraries
    )
  }

  private func processSingleFile(
    entryFilePath: String,
    mode: DriverCommand,
    outputDir: String?,
    noStd: Bool,
    escapeAnalysisReport: Bool,
    stdConfigPath: String?
  ) throws {
    let entryURL = URL(fileURLWithPath: entryFilePath).standardized
    let resolver = initializeModuleResolver()

    let userCompilationUnit = try resolver.resolveModule(entryFile: entryURL.path)
    let userNodesWithInfo = userCompilationUnit.getAllGlobalNodesWithSourceInfo()
    var userGlobalNodes: [GlobalNode] = []
    var userNodeSourceInfoList: [GlobalNodeSourceInfo] = []
    for (node, sourceFile, modulePath) in userNodesWithInfo {
      userGlobalNodes.append(node)
      userNodeSourceInfoList.append(
        GlobalNodeSourceInfo(
          sourceFile: sourceFile,
          modulePath: modulePath,
          packageID: "single:\(entryURL.deletingLastPathComponent().path)",
          node: node
        )
      )
    }
    registerModuleSources(
      from: userCompilationUnit.rootModule,
      displayPrefix: userCompilationUnit.rootModule.path.joined(separator: "::")
    )

    var stdGlobalNodes: [GlobalNode] = []
    var stdNodeSourceInfoList: [GlobalNodeSourceInfo] = []
    var mergedImportGraph = userCompilationUnit.importGraph
    var extraLinkedLibraries: [String] = []

    if !noStd, let resolvedStdConfigPath = stdConfigPath ?? getStdManifestPath() {
      let stdManifest = try loadPackageManifest(at: resolvedStdConfigPath)
      let stdModules = try loadAllModules(
        manifest: stdManifest,
        displayPrefixSelector: { $0 },
        resolver: resolver
      )
      stdGlobalNodes = stdModules.globalNodes
      stdNodeSourceInfoList = stdModules.nodeSourceInfoList
      mergedImportGraph.merge(stdModules.importGraph)
      extraLinkedLibraries.append(contentsOf: stdModules.linkedLibraries)
    }

    let allGlobalNodes = stdGlobalNodes + userGlobalNodes
    let nodeSourceInfoList = stdNodeSourceInfoList + userNodeSourceInfoList
    let outputDirectory = outputDir.map { URL(fileURLWithPath: $0).standardized }
      ?? entryURL.deletingLastPathComponent()
    let baseName = entryURL.deletingPathExtension().lastPathComponent

    try performCompilation(
      baseName: baseName,
      outputDirectory: outputDirectory,
      mode: mode,
      escapeAnalysisReport: escapeAnalysisReport,
      stdDisplayName: stdConfigPath ?? "std/koral.json",
      userDisplayName: entryURL.path,
      stdGlobalNodes: stdGlobalNodes,
      allGlobalNodes: allGlobalNodes,
      nodeSourceInfoList: nodeSourceInfoList,
      importGraph: mergedImportGraph,
      extraLinkedLibraries: extraLinkedLibraries
    )
  }

  private func performCompilation(
    baseName: String,
    outputDirectory: URL,
    mode: DriverCommand,
    escapeAnalysisReport: Bool,
    stdDisplayName: String,
    userDisplayName: String,
    stdGlobalNodes: [GlobalNode],
    allGlobalNodes: [GlobalNode],
    nodeSourceInfoList: [GlobalNodeSourceInfo],
    importGraph: ImportGraph,
    extraLinkedLibraries: [String]
  ) throws {
    let fileManager = FileManager.default
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

    debugPhase("\(phasePrefix): codegen")
    let codegenStart = DispatchTime.now()
    let codeGen = CodeGen(
      ast: monomorphizedProgram,
      context: monomorphizer.context,
      escapeAnalysisReportEnabled: escapeAnalysisReport
    )
    let cSource = codeGen.generate()
    profilePhase("\(phasePrefix): codegen", start: codegenStart)

    if escapeAnalysisReport {
      let diagnostics = codeGen.getEscapeAnalysisDiagnostics()
      if !diagnostics.isEmpty {
        writeStdout(diagnostics)
      }
    }

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
    clangArgs.append("-O1")

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
        build   Compile to executable (default)
        check   Type-check only (no code generation)
        run     Compile and run
        emit-c  Generate C code only

      Options:
        -o, --output <path>       Output directory for generated files
        --package-config <path>   Package manifest path for manifest-driven builds
        --target-module <name>    Target module full name, e.g. app::main
        --deps-root <path>        Dependency root directory (default unresolved)
        --std-config <path>       Standard library manifest path
        --no-std                  Compile without standard library
        -m, -m=<N>                Print escape analysis diagnostics (Go-style)
      """
    )
  }
}

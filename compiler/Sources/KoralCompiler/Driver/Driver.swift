import Foundation

enum DriverCommand: String {
  case build
  case run
  case emitC = "emit-c"
}

public class Driver {
  /// Source manager for error rendering with code snippets
  private var sourceManager = SourceManager()
  
  public init() {}

  private func writeStdout(_ text: String, newline: Bool = true) {
    let payload = newline ? text + "\n" : text
    FileHandle.standardOutput.write(Data(payload.utf8))
  }

  private func writeStderr(_ text: String, newline: Bool = true) {
    let payload = newline ? text + "\n" : text
    FileHandle.standardError.write(Data(payload.utf8))
  }

  public func run(args: [String]) {
    guard args.count > 1 else {
      printUsage()
      return
    }

    let commandStr = args[1]
    let command = DriverCommand(rawValue: commandStr)

    let filePath: String
    let mode: DriverCommand
    var remainingArgs: [String] = []

    if let cmd = command {
      // koralc <command> <file> [options]
      guard args.count > 2 else {
        writeStderr("Error: Missing file path for command '\(cmd.rawValue)'")
        return
      }
      mode = cmd
      filePath = args[2]
      if args.count > 3 {
        remainingArgs = Array(args[3...])
      }
    } else {
      // koralc <file> [options] (default to build)
      // Check if the first argument looks like a file
      if commandStr.hasSuffix(".koral") {
        mode = .build
        filePath = commandStr
        if args.count > 2 {
          remainingArgs = Array(args[2...])
        }
      } else {
        writeStderr("Unknown command or file: \(commandStr)")
        printUsage()
        return
      }
    }

    // Parse options
    var outputDir: String?
    var noStd = false
    var escapeAnalysisLevel = 0
    var i = 0
    while i < remainingArgs.count {
      let arg = remainingArgs[i]
      if arg == "-o" || arg == "--output" {
        if i + 1 < remainingArgs.count {
          outputDir = remainingArgs[i + 1]
          i += 2
        } else {
          writeStderr("Error: Missing path for -o option")
          exit(1)
        }
      } else if arg == "--no-std" {
        noStd = true
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
      } else {
        i += 1
      }
    }

    let escapeAnalysisReport = escapeAnalysisLevel > 0

    do {
      try process(file: filePath, mode: mode, outputDir: outputDir, noStd: noStd, escapeAnalysisReport: escapeAnalysisReport)
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

  private func accessModifier(of node: GlobalNode) -> AccessModifier? {
    switch node {
    case .globalVariableDeclaration(_, _, _, _, let access, _):
      return access
    case .globalFunctionDeclaration(_, _, _, _, _, let access, _):
      return access
    case .intrinsicFunctionDeclaration(_, _, _, _, let access, _):
      return access
    case .foreignFunctionDeclaration(_, _, _, let access, _):
      return access
    case .globalStructDeclaration(_, _, _, let access, _):
      return access
    case .globalUnionDeclaration(_, _, _, let access, _):
      return access
    case .intrinsicTypeDeclaration(_, _, let access, _):
      return access
    case .foreignTypeDeclaration(_, _, _, let access, _):
      return access
    case .foreignLetDeclaration(_, _, _, let access, _):
      return access
    case .traitDeclaration(_, _, _, _, let access, _):
      return access
    case .typeAliasDeclaration(_, _, let access, _):
      return access
    default:
      return nil
    }
  }

  private func exportedSymbolName(of node: GlobalNode) -> String? {
    switch node {
    case .globalVariableDeclaration(let name, _, _, _, _, _):
      return name
    case .globalFunctionDeclaration(let name, _, _, _, _, _, _):
      return name
    case .intrinsicFunctionDeclaration(let name, _, _, _, _, _):
      return name
    case .foreignFunctionDeclaration(let name, _, _, _, _):
      return name
    case .globalStructDeclaration(let name, _, _, _, _):
      return name
    case .globalUnionDeclaration(let name, _, _, _, _):
      return name
    case .intrinsicTypeDeclaration(let name, _, _, _):
      return name
    case .foreignTypeDeclaration(let name, _, _, _, _):
      return name
    case .foreignLetDeclaration(let name, _, _, _, _):
      return name
    case .traitDeclaration(let name, _, _, _, _, _):
      return name
    case .typeAliasDeclaration(let name, _, _, _):
      return name
    default:
      return nil
    }
  }

  private func collectStdPreludeSymbolNames(from stdCompilationUnit: CompilationUnit) -> [String] {
    var names: Set<String> = []

    for (node, _) in stdCompilationUnit.rootModule.globalNodes {
      guard let name = exportedSymbolName(of: node),
            let access = accessModifier(of: node),
            access != .private else {
        continue
      }
      names.insert(name)
    }

    return names.sorted()
  }

  private func collectStdRootModuleSymbolNames(from stdCompilationUnit: CompilationUnit) -> [String] {
    var names: Set<String> = []

    for usingDecl in stdCompilationUnit.rootModule.usingDeclarations {
      guard usingDecl.pathKind == .submodule,
            usingDecl.access != .private,
            let firstSegment = usingDecl.pathSegments.first,
            !firstSegment.isEmpty else {
        continue
      }
      names.insert(firstSegment)
    }

    return names.sorted()
  }

  private func collectStdRootSubmodulePaths(from stdCompilationUnit: CompilationUnit) -> [[String]] {
    let paths = stdCompilationUnit.rootModule.submodules.values.map { $0.path }
    let unique = Set(paths.map { $0.joined(separator: ".") })
    return unique.sorted().map { $0.split(separator: ".").map(String.init) }
  }

  private func collectUserModulePaths(from userCompilationUnit: CompilationUnit) -> [[String]] {
    let paths = userCompilationUnit.loadedModules.values.map { $0.path }
    let unique = Set(paths.map { $0.joined(separator: ".") })
    return unique.sorted().map { key in
      key.isEmpty ? [] : key.split(separator: ".").map(String.init)
    }
  }

  private func injectStdPreludeImports(
    stdCompilationUnit: CompilationUnit,
    userCompilationUnit: CompilationUnit,
    importGraph: inout ImportGraph
  ) {
    let preludeSymbols = collectStdPreludeSymbolNames(from: stdCompilationUnit)
    let stdRootModuleSymbols = collectStdRootModuleSymbolNames(from: stdCompilationUnit)
    let stdRootSubmodulePaths = collectStdRootSubmodulePaths(from: stdCompilationUnit)

    if preludeSymbols.isEmpty && stdRootModuleSymbols.isEmpty && stdRootSubmodulePaths.isEmpty {
      return
    }

    let userModulePaths = collectUserModulePaths(from: userCompilationUnit)
    if userModulePaths.isEmpty {
      return
    }

    for modulePath in userModulePaths {
      for symbol in preludeSymbols {
        importGraph.addSymbolImport(
          module: modulePath,
          target: ["std"],
          symbol: symbol,
          kind: .memberImport
        )
      }
    }

    let stdSubmodulePaths = stdCompilationUnit.loadedModules.values
      .map { $0.path }
      .filter { $0.first == "std" && $0.count > 1 }
    let uniqueStdSubmoduleKeys = Set(stdSubmodulePaths.map { $0.joined(separator: ".") })

    for moduleKey in uniqueStdSubmoduleKeys.sorted() {
      let modulePath = moduleKey.split(separator: ".").map(String.init)

      for symbol in preludeSymbols {
        importGraph.addSymbolImport(
          module: modulePath,
          target: ["std"],
          symbol: symbol,
          kind: .memberImport
        )
      }

      for symbol in stdRootModuleSymbols {
        importGraph.addSymbolImport(
          module: modulePath,
          target: ["std"],
          symbol: symbol,
          kind: .memberImport
        )
      }

      for targetPath in stdRootSubmodulePaths {
        importGraph.addModuleImport(
          from: modulePath,
          to: targetPath,
          kind: .moduleImport
        )
      }
    }
  }

  func process(file: String, mode: DriverCommand, outputDir: String? = nil, noStd: Bool = false, escapeAnalysisReport: Bool = false) throws {
    let fileManager = FileManager.default
    let inputURL = URL(fileURLWithPath: file).standardized
    
    let baseName = inputURL.deletingPathExtension().lastPathComponent
    
    let outputDirectory: URL
    if let outDir = outputDir {
        outputDirectory = URL(fileURLWithPath: outDir)
        // Create output directory if it doesn't exist
        if !fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    } else {
        outputDirectory = inputURL.deletingLastPathComponent()
    }

    let userDisplayName = inputURL.lastPathComponent
    let stdDisplayName = "std/std.koral"

    // Initialize module resolver
    let resolver = initializeModuleResolver()
    
    var stdGlobalNodes: [GlobalNode] = []
    var stdNodeSourceInfoList: [GlobalNodeSourceInfo] = []
    var stdCompilationUnit: CompilationUnit? = nil
    
    if !noStd {
        // Load standard library using ModuleResolver (same as user code)
        let stdLibPath = getCoreLibPath()
        do {
            stdCompilationUnit = try resolver.resolveModule(entryFile: stdLibPath)
            
            // Collect std library nodes with source info
            let stdNodesWithInfo = stdCompilationUnit!.getAllGlobalNodesWithSourceInfo()
            for (node, sourceFile, modulePath) in stdNodesWithInfo {
                stdGlobalNodes.append(node)
                stdNodeSourceInfoList.append(GlobalNodeSourceInfo(
                    sourceFile: sourceFile,
                    modulePath: modulePath,
                node: node
                ))
            }
            
            // Register std library source files with source manager
            func registerStdSources(from module: ModuleInfo) {
                if let source = try? String(contentsOfFile: module.entryFile, encoding: .utf8) {
                    let displayName = "std/" + URL(fileURLWithPath: module.entryFile).lastPathComponent
                    sourceManager.loadFile(name: displayName, content: source)
                }
                for mergedFile in module.mergedFiles {
                    if let source = try? String(contentsOfFile: mergedFile, encoding: .utf8) {
                        let displayName = "std/" + URL(fileURLWithPath: mergedFile).lastPathComponent
                        sourceManager.loadFile(name: displayName, content: source)
                    }
                }
                for (_, submodule) in module.submodules {
                    registerStdSources(from: submodule)
                }
            }
            registerStdSources(from: stdCompilationUnit!.rootModule)
            
        } catch let error as ModuleError {
            throw DiagnosticError(
                stage: .other,
                fileName: stdDisplayName,
                underlying: error,
                sourceManager: sourceManager
            )
        }
    }

    // Compile user code
    var allGlobalNodes: [GlobalNode] = stdGlobalNodes
    var nodeSourceInfoList: [GlobalNodeSourceInfo] = stdNodeSourceInfoList
    var userCompilationUnit: CompilationUnit? = nil
    
    do {
      let compilationUnit = try resolver.resolveModule(entryFile: file)
      userCompilationUnit = compilationUnit
      
      // Collect all global nodes from the compilation unit
      allGlobalNodes = stdGlobalNodes + compilationUnit.getAllGlobalNodes()
      
      // Add user code nodes with source info
      let userNodesWithInfo = compilationUnit.getAllGlobalNodesWithSourceInfo()
      for (node, sourceFile, modulePath) in userNodesWithInfo {
        nodeSourceInfoList.append(GlobalNodeSourceInfo(
          sourceFile: sourceFile,
          modulePath: modulePath,
          node: node
        ))
      }
      
      // Register all source files with source manager for error rendering
      func registerSources(from module: ModuleInfo) {
        // Register entry file
        if let source = try? String(contentsOfFile: module.entryFile, encoding: .utf8) {
          let displayName = URL(fileURLWithPath: module.entryFile).lastPathComponent
          sourceManager.loadFile(name: displayName, content: source)
        }
        // Register merged files
        for mergedFile in module.mergedFiles {
          if let source = try? String(contentsOfFile: mergedFile, encoding: .utf8) {
            let displayName = URL(fileURLWithPath: mergedFile).lastPathComponent
            sourceManager.loadFile(name: displayName, content: source)
          }
        }
        // Register submodule files
        for (_, submodule) in module.submodules {
          registerSources(from: submodule)
        }
      }
      registerSources(from: compilationUnit.rootModule)
      
    } catch let error as ModuleError {
      throw DiagnosticError(
        stage: .other,
        fileName: userDisplayName,
        underlying: error,
        sourceManager: sourceManager
      )
    }
    
    let combinedAST: ASTNode = .program(globalNodes: allGlobalNodes)

    var mergedImportGraph = ImportGraph()
    if let stdCompilationUnit {
      mergedImportGraph.merge(stdCompilationUnit.importGraph)
    }
    if let userCompilationUnit {
      mergedImportGraph.merge(userCompilationUnit.importGraph)
    }
    if let stdCompilationUnit, let userCompilationUnit {
      injectStdPreludeImports(
        stdCompilationUnit: stdCompilationUnit,
        userCompilationUnit: userCompilationUnit,
        importGraph: &mergedImportGraph
      )
    }

    // Type checking - always use source info initializer for unified handling
    let typeChecker = TypeChecker(
      ast: combinedAST,
      nodeSourceInfoList: nodeSourceInfoList,
      coreGlobalCount: stdGlobalNodes.count,
      coreFileName: stdDisplayName,
      userFileName: userDisplayName,
      importGraph: mergedImportGraph
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

    // 2. Monomorphization (new phase)
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

    // 3. Code generation
    let codeGen = CodeGen(
      ast: monomorphizedProgram,
      context: monomorphizer.context,
      escapeAnalysisReportEnabled: escapeAnalysisReport
    )
    let cSource = codeGen.generate()
    
    // Output escape analysis report if enabled
    if escapeAnalysisReport {
      let diagnostics = codeGen.getEscapeAnalysisDiagnostics()
      if !diagnostics.isEmpty {
        writeStdout(diagnostics)
      }
    }

    // Ensure output directory exists
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
      return
    }

    // 2. Compile C to Executable using Clang
    #if os(Windows)
    let exeURL = outputDirectory.appendingPathComponent(baseName + ".exe")
    #else
    let exeURL = outputDirectory.appendingPathComponent(baseName)
    #endif
    
    // Suppress warnings to keep output clean
    var clangArgs = [cFileURL.path]

    // If a koral runtime C file exists in the std directory, include it
    if let stdPath = getStdLibPath() {
      let runtimeURL = URL(fileURLWithPath: stdPath).appendingPathComponent("koral_runtime.c")
      if FileManager.default.fileExists(atPath: runtimeURL.path) {
        clangArgs.append(runtimeURL.path)
      }
      // Add std directory to include path for koral_runtime.h and related headers
      clangArgs.append(contentsOf: ["-I", stdPath])
    }

    clangArgs.append("-o")
    clangArgs.append(exeURL.path)
    clangArgs.append("-Wno-everything")

    // Collect linked libraries from foreign using declarations (in order)
    let linkedLibraries: [String] = monomorphizedProgram.globalNodes.compactMap { node in
      if case .foreignUsing(let libraryName) = node {
        return libraryName
      }
      return nil
    }
    for lib in linkedLibraries {
      // libc is implicitly linked; skip -lc on all platforms
      if lib == "c" { continue }
      clangArgs.append("-l\(lib)")
    }

    #if os(Windows)
    // koral_runtime.c uses BCryptGenRandom on Windows.
    // Ensure bcrypt is linked even when not requested by foreign using.
    if !linkedLibraries.contains("bcrypt") {
      clangArgs.append("-lbcrypt")
    }
    // koral_runtime.c uses Winsock2 for socket operations.
    // Ensure ws2_32 is linked even when not requested by foreign using.
    if !linkedLibraries.contains("ws2_32") {
      clangArgs.append("-lws2_32")
    }
    #endif

    #if os(macOS)
    if let sdkPath = getSDKPath() {
        clangArgs.append(contentsOf: ["-isysroot", sdkPath])
    }
    #endif
    
    let clangPath = findExecutable("clang") ?? "/usr/bin/clang"
    let clangResult = try runSubprocess(executable: clangPath, args: clangArgs)
    if clangResult != 0 {
      throw NSError(
        domain: "Driver", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Clang compilation failed"])
    }

    if mode == .build {
      writeStdout("Build successful: \(exeURL.path)")
      return
    }

    // 3. Run Executable
    if mode == .run {
      let runResult = try runSubprocess(executable: exeURL.path, args: [])
      if runResult != 0 {
          exit(runResult)
      }
    }
  }

  func getCoreLibPath() -> String {
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
  
  /// Gets the standard library directory path
  func getStdLibPath() -> String? {
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
      Usage: koralc [command] <file.koral> [options]

      Commands:
        build   Compile to executable (default)
        run     Compile and run
        emit-c  Generate C code only

      Options:
        -o, --output <path>       Output directory for generated files
        --no-std                  Compile without standard library
        -m, -m=<N>                Print escape analysis diagnostics (Go-style)
      """
    )
  }
}

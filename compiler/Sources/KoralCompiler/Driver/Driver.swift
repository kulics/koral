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
        print("Error: Missing file path for command '\(cmd.rawValue)'")
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
        print("Unknown command or file: \(commandStr)")
        printUsage()
        return
      }
    }

    // Parse options
    var outputDir: String?
    var noStd = false
    var escapeAnalysisReport = false
    var i = 0
    while i < remainingArgs.count {
      let arg = remainingArgs[i]
      if arg == "-o" || arg == "--output" {
        if i + 1 < remainingArgs.count {
          outputDir = remainingArgs[i + 1]
          i += 2
        } else {
          print("Error: Missing path for -o option")
          exit(1)
        }
      } else if arg == "--no-std" {
        noStd = true
        i += 1
      } else if arg == "--escape-analysis-report" {
        escapeAnalysisReport = true
        i += 1
      } else {
        i += 1
      }
    }

    do {
      try process(file: filePath, mode: mode, outputDir: outputDir, noStd: noStd, escapeAnalysisReport: escapeAnalysisReport)
    } catch var error as DiagnosticError {
      // Attach source manager for rendering with code snippets
      error.sourceManager = sourceManager
      print(error.renderForCLI())
      exit(1)
    } catch let error as ParserError {
      print("Parser Error: \(error)")
      exit(1)
    } catch let error as LexerError {
      print("Lexer Error: \(error)")
      exit(1)
    } catch let error as SemanticError {
      // Fallback if semantic errors escape without being wrapped.
      print("\(error.fileName): Semantic Error: \(error)")
      exit(1)
    } catch {
      print("Error: \(error)")
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

  func process(file: String, mode: DriverCommand, outputDir: String? = nil, noStd: Bool = false, escapeAnalysisReport: Bool = false) throws {
    let fileManager = FileManager.default
    let inputURL = URL(fileURLWithPath: file)
    
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
    let coreDisplayName = "std/core.koral"

    var coreGlobalNodes: [GlobalNode] = []
    
    if !noStd {
        // 0. Load and Parse Core Library
        let coreLibPath = getCoreLibPath()
        let coreSource = try String(contentsOfFile: coreLibPath, encoding: .utf8)
      coreGlobalNodes = try parseProgram(source: coreSource, fileName: coreDisplayName)
    }

    // 1. Compile Koral to C
    let koralSource = try String(contentsOfFile: file, encoding: .utf8)

    let userGlobalNodes = try parseProgram(source: koralSource, fileName: userDisplayName)
    
    let combinedAST: ASTNode = .program(globalNodes: coreGlobalNodes + userGlobalNodes)

    // 1. Type checking
    let typeChecker = TypeChecker(
      ast: combinedAST,
      coreGlobalCount: coreGlobalNodes.count,
      coreFileName: coreDisplayName,
      userFileName: userDisplayName
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
    let codeGen = CodeGen(ast: monomorphizedProgram, escapeAnalysisReportEnabled: escapeAnalysisReport)
    let cSource = codeGen.generate()
    
    // Output escape analysis report if enabled
    if escapeAnalysisReport {
      let diagnostics = codeGen.getEscapeAnalysisDiagnostics()
      if !diagnostics.isEmpty {
        print(diagnostics)
      }
    }

    let cFileURL = outputDirectory.appendingPathComponent("\(baseName).c")
    try cSource.write(to: cFileURL, atomically: true, encoding: .utf8)


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
    var clangArgs = [cFileURL.path, "-o", exeURL.path, "-Wno-everything"]

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
      print("Build successful: \(exeURL.path)")
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
        let path = URL(fileURLWithPath: koralHome).appendingPathComponent("compiler/Sources/std/core.koral").path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    // Fallback: Assume we are running from .build/debug/ or similar, try to find source root
    // This is a heuristic for development environment
    let currentPath = FileManager.default.currentDirectoryPath
    let devPath = URL(fileURLWithPath: currentPath).appendingPathComponent("Sources/std/core.koral").path
    if FileManager.default.fileExists(atPath: devPath) {
        return devPath
    }
    
    // Fallback for tests running in package root
    let testPath = URL(fileURLWithPath: currentPath).appendingPathComponent("compiler/Sources/std/core.koral").path
    if FileManager.default.fileExists(atPath: testPath) {
         return testPath
    }

    print("Error: Could not locate std/core.koral. Please set KORAL_HOME environment variable.")
    exit(1)
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
    print(
      """
      Usage: koralc [command] <file.koral> [options]

      Commands:
        build   Compile to executable (default)
        run     Compile and run
        emit-c  Generate C code only

      Options:
        -o, --output <path>       Output directory for generated files
        --no-std                  Compile without standard library
        --escape-analysis-report  Print escape analysis diagnostics
      """)
  }
}

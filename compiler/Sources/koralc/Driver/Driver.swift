import Foundation

enum DriverCommand: String {
  case build
  case run
  case emitC = "emit-c"
}

class Driver {
  func run(args: [String]) {
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
      } else {
        i += 1
      }
    }

    do {
      try process(file: filePath, mode: mode, outputDir: outputDir)
    } catch let error as ParserError {
      print("Parser Error: \(error)")
      exit(1)
    } catch let error as LexerError {
      print("Lexer Error: \(error)")
      exit(1)
    } catch let error as SemanticError {
      print("Semantic Error: \(error)")
      exit(1)
    } catch {
      print("Error: \(error)")
      exit(1)
    }
  }

  func process(file: String, mode: DriverCommand, outputDir: String? = nil) throws {
    let fileManager = FileManager.default
    let currentPath = fileManager.currentDirectoryPath
    let inputURL = URL(fileURLWithPath: file, relativeTo: URL(fileURLWithPath: currentPath))
    
    let baseName = inputURL.deletingPathExtension().lastPathComponent
    
    let outputDirectory: URL
    if let outDir = outputDir {
        outputDirectory = URL(fileURLWithPath: outDir, relativeTo: URL(fileURLWithPath: currentPath))
        // Create output directory if it doesn't exist
        if !fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    } else {
        outputDirectory = inputURL.deletingLastPathComponent()
    }

    // 1. Compile Koral to C
    let koralSource = try String(contentsOf: inputURL, encoding: .utf8)

    let lexer = Lexer(input: koralSource)
    let parser = Parser(lexer: lexer)
    let ast = try parser.parse()

    let typeChecker = TypeChecker(ast: ast)
    let typedAST = try typeChecker.check()

    let codeGen = CodeGen(ast: typedAST)
    let cSource = codeGen.generate()

    let cFileURL = outputDirectory.appendingPathComponent("\(baseName).c")
    try cSource.write(to: cFileURL, atomically: true, encoding: .utf8)

    if mode == .emitC {
      return
    }

    // 2. Compile C to Executable using Clang
    let exeURL = outputDirectory.appendingPathComponent(baseName)
    
    // Suppress warnings to keep output clean
    let clangArgs = [cFileURL.path, "-o", exeURL.path, "-Wno-everything"]
    
    // print("Invoking clang...")
    let clangResult = try runSubprocess(executable: "/usr/bin/clang", args: clangArgs)
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

  func runSubprocess(executable: String, args: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args

    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }

  func printUsage() {
    print(
      """
      Usage: koralc [command] <file.koral>

      Commands:
        build   Compile to executable (default)
        run     Compile and run
        emit-c  Generate C code only
      """)
  }
}

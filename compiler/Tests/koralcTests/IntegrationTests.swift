import XCTest
import Foundation

class IntegrationTests: XCTestCase {
    
    func testAllCases() throws {
        // 1. Locate the Tests/Cases directory by finding Package.swift
        let currentFileURL = URL(fileURLWithPath: #file)
        var projectRoot = currentFileURL.deletingLastPathComponent()
        
        while !FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("Package.swift").path) {
            if projectRoot.path == "/" {
                XCTFail("Could not find Package.swift starting from \(currentFileURL.path)")
                return
            }
            projectRoot = projectRoot.deletingLastPathComponent()
        }
        
        let casesDir = projectRoot.appendingPathComponent("Tests/Cases")
        
        print("Debug: #file = \(currentFileURL.path)")
        print("Debug: casesDir = \(casesDir.path)")
        print("Debug: projectRoot = \(projectRoot.path)")
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: casesDir.path) else {
            XCTFail("Tests/Cases directory not found at \(casesDir.path)")
            return
        }
        
        let files = try fileManager.contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "koral" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        print("Found \(files.count) test cases.")
        
        for file in files {
            print("Running test: \(file.lastPathComponent)")
            try runTestCase(file: file, projectRoot: projectRoot)
        }
    }
    
    func runTestCase(file: URL, projectRoot: URL) throws {
        // 1. Parse expectations
        let content = try String(contentsOf: file, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var expectedOutput: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "// EXPECT: ") {
                let expectation = String(trimmed.dropFirst("// EXPECT: ".count))
                expectedOutput.append(expectation)
            }
        }
        
        // 2. Prepare output and cleanup
        // Check environment variable to decide whether to keep generated C files.
        // Set KORAL_TEST_KEEP_C=1 to keep generated artifacts under Tests/CasesOutput.
        let keepCFiles = ProcessInfo.processInfo.environment["KORAL_TEST_KEEP_C"] != nil

        let baseName = file.deletingPathExtension().lastPathComponent
        let casesOutputRoot = projectRoot.appendingPathComponent("Tests/CasesOutput")
        let outputDir: URL
        let cleanup: () -> Void

        if keepCFiles {
            // Stable per-test directory for easier inspection.
            outputDir = casesOutputRoot.appendingPathComponent(baseName)
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)

            // Only remove the executable, keep the .c file and other artifacts.
            let exePath = outputDir.appendingPathComponent(baseName)
            let exePathWindows = outputDir.appendingPathComponent(baseName + ".exe")
            cleanup = {
                try? FileManager.default.removeItem(at: exePath)
                try? FileManager.default.removeItem(at: exePathWindows)
            }
        } else {
            // Use an isolated directory under CasesOutput, but clean it up after.
            let runDir = casesOutputRoot.appendingPathComponent(baseName).appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true, attributes: nil)
            outputDir = runDir

            cleanup = {
                try? FileManager.default.removeItem(at: runDir)
            }
        }
        
        defer {
            cleanup()
        }

        // 3. Run compiler
        // We use the built binary directly to avoid swift run lock
        var koralcBinary = projectRoot.appendingPathComponent(".build/debug/koralc")
        #if os(Windows)
        koralcBinary.appendPathExtension("exe")
        #endif
        
        guard FileManager.default.fileExists(atPath: koralcBinary.path) else {
            XCTFail("koralc binary not found at \(koralcBinary.path). Please build first.")
            return
        }
        
        let process = Process()
        process.executableURL = koralcBinary
        process.arguments = ["run", file.path, "-o", outputDir.path]
        process.currentDirectoryURL = projectRoot
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // Capture stderr too just in case
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: data, encoding: .utf8) ?? ""
        
        // Normalize line endings to \n
        output = output.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.replacingOccurrences(of: "\r", with: "\n")
        
        // 4. Verify output (Robust Line Matching)
        let outputLines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var currentLineIndex = 0
        
        for expected in expectedOutput {
             let cleanExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
             if cleanExpected.isEmpty { continue }

            var found = false
            // Scan forward from current position
            for i in currentLineIndex..<outputLines.count {
                if outputLines[i].contains(cleanExpected) {
                    found = true
                    currentLineIndex = i + 1 // Advance to next line for next expectation
                    break
                }
            }
            
            if !found {
                XCTFail("""
                Test failed: \(file.lastPathComponent)
                Missing expected output: "\(cleanExpected)"
                
                Scanned from line \(currentLineIndex)
                
                Actual Output Lines:
                \(outputLines.joined(separator: "\n"))
                """)
                return
            }
        }
        
        // Check exit code if needed (default expects 0 unless specified otherwise)
        // For now, we assume success if output matches.
        // Note: Our current compiler might return non-zero for valid programs (e.g. returning result of calculation)
        // So we don't strictly check process.terminationStatus == 0 yet, unless we add // EXIT: 0
    }
}

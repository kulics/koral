import Dispatch
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private struct IntegrationTestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

private struct CaseExpectations {
    var expectedOutput: [String] = []
    var expectedErrors: [String] = []
    var expectedExit: Int32?

    var hasAssertions: Bool {
        !expectedOutput.isEmpty || !expectedErrors.isEmpty || expectedExit != nil
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func appendRemaining(from handle: FileHandle) {
        append(handle.readDataToEndOfFile())
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

private final class IntegrationTestProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let totalCases: Int
    private let startTime = Date()
    private let consoleHandle = IntegrationTestProgressReporter.makeConsoleHandle()
    private var completedCases = 0
    private var failedCases = 0
    private var runningCases: Set<String> = []

    init(totalCases: Int) {
        self.totalCases = totalCases
        emit("[swift-test] starting compiler cases: total=\(totalCases)")
    }

    func caseStarted(_ relativePath: String) {
        lock.lock()
        runningCases.insert(relativePath)
        let runningCount = runningCases.count
        let completed = completedCases
        let total = totalCases
        lock.unlock()

        emit("[swift-test] start \(relativePath) | completed=\(completed)/\(total) running=\(runningCount)")
    }

    func caseFinished(_ relativePath: String, failed: Bool) {
        lock.lock()
        runningCases.remove(relativePath)
        completedCases += 1
        if failed {
            failedCases += 1
        }
        let completed = completedCases
        let failures = failedCases
        let runningCount = runningCases.count
        let total = totalCases
        let elapsed = Date().timeIntervalSince(startTime)
        lock.unlock()

        let status = failed ? "FAIL" : "PASS"
        emit(
            "[swift-test] \(status) \(relativePath) | completed=\(completed)/\(total) failed=\(failures) running=\(runningCount) elapsed=\(format(elapsed))"
        )
    }

    func finishRun() {
        lock.lock()
        let completed = completedCases
        let failures = failedCases
        let runningCount = runningCases.count
        let total = totalCases
        let elapsed = Date().timeIntervalSince(startTime)
        lock.unlock()

        emit(
            "[swift-test] finished compiler cases: completed=\(completed)/\(total) failed=\(failures) running=\(runningCount) elapsed=\(format(elapsed))"
        )
    }

    private func emit(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else {
            return
        }

        if let consoleHandle {
            if #available(macOS 10.15.4, *) {
                try? consoleHandle.write(contentsOf: data)
            } else {
                consoleHandle.write(data)
            }
            return
        }

        if #available(macOS 10.15.4, *) {
            try? FileHandle.standardError.write(contentsOf: data)
        } else {
            FileHandle.standardError.write(data)
        }
    }

    private static func makeConsoleHandle() -> FileHandle? {
        #if os(Windows)
        return FileHandle(forWritingAtPath: "CONOUT$")
        #else
        return FileHandle(forWritingAtPath: "/dev/tty")
        #endif
    }

    private func format(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private enum IntegrationTestHarness {
    static let caseTimeoutSeconds: TimeInterval = 90
    static let syncGroupLock = NSLock()
    static let netGroupLock = NSLock()
    static let envGroupLock = NSLock()

    private static let mainPattern = #"\b(?:public\s+)?let\s+main\s*\("#

    static func discoveredCases() throws -> [String] {
        let projectRoot = try projectRootURL()
        let casesDir = projectRoot.appendingPathComponent("Tests/Cases", isDirectory: true)

        guard let enumerator = FileManager.default.enumerator(
            at: casesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw IntegrationTestFailure(message: "Could not enumerate integration cases at \(casesDir.path)")
        }

        var discovered: [String] = []

        for case let file as URL in enumerator {
            guard file.pathExtension == "koral" else {
                continue
            }

            let content = try String(contentsOf: file, encoding: .utf8)
            let relativePath = normalizeRelativePath(file, relativeTo: casesDir)
            let expectations = try parseExpectations(in: content, relativePath: relativePath)
            let hasMain = content.range(of: mainPattern, options: .regularExpression) != nil
            let isTopLevelExpectationOnly = !relativePath.contains("/") && expectations.hasAssertions

            if hasMain || isTopLevelExpectationOnly {
                discovered.append(relativePath)
            }
        }

        return discovered.sorted()
    }

    static func runCase(named relativePath: String) throws {
        try withCaseLockIfNeeded(for: relativePath) {
            let projectRoot = try projectRootURL()
            let file = projectRoot.appendingPathComponent("Tests/Cases", isDirectory: true)
                .appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: file.path) else {
                throw IntegrationTestFailure(message: "Test case not found at \(file.path)")
            }

            try runTestCase(file: file, projectRoot: projectRoot, relativePath: relativePath)
        }
    }

    static func emitCForCase(named relativePath: String) throws -> String {
        let projectRoot = try projectRootURL()
        let file = projectRoot.appendingPathComponent("Tests/Cases", isDirectory: true)
            .appendingPathComponent(relativePath)

        guard FileManager.default.fileExists(atPath: file.path) else {
            throw IntegrationTestFailure(message: "Test case not found at \(file.path)")
        }

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDir)
        }

        let koralcBinary = try koralcBinaryURL(projectRoot: projectRoot)
        let process = Process()
        process.executableURL = koralcBinary
        process.arguments = ["emit-c", file.path, "-o", outputDir.path]
        process.currentDirectoryURL = projectRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: stdoutData + stderrData, as: UTF8.self)

        if process.terminationStatus != 0 {
            throw IntegrationTestFailure(message: "emit-c failed for \(relativePath):\n\(output)")
        }

        let cFile = outputDir.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".c")
        guard FileManager.default.fileExists(atPath: cFile.path) else {
            throw IntegrationTestFailure(message: "Expected generated C file at \(cFile.path)")
        }

        return try String(contentsOf: cFile, encoding: .utf8)
    }

    private static func lockGroup(forCaseNamed relativePath: String) -> String? {
        let baseName = URL(fileURLWithPath: relativePath).lastPathComponent
        if baseName.hasPrefix("sync_") { return "sync" }
        if baseName.hasPrefix("net_") { return "net" }
        if baseName == "os_env_test.koral" { return "env" }
        return nil
    }

    private static func localLock(forGroup group: String) -> NSLock {
        switch group {
        case "sync": return syncGroupLock
        case "net": return netGroupLock
        case "env": return envGroupLock
        default: return syncGroupLock
        }
    }

    private static func withCaseLockIfNeeded<T>(for relativePath: String, _ body: () throws -> T) throws -> T {
        guard let group = lockGroup(forCaseNamed: relativePath) else {
            return try body()
        }

        let localLock = localLock(forGroup: group)
        localLock.lock()
        defer { localLock.unlock() }

        #if !os(Windows)
        let lockPath = "/tmp/koral-integration-\(group).lock"
        let lockFd = open(lockPath, O_CREAT | O_RDWR, 0o666)
        if lockFd < 0 {
            throw IntegrationTestFailure(message: "Failed to open integration lock file: \(lockPath)")
        }
        if flock(lockFd, LOCK_EX) != 0 {
            close(lockFd)
            throw IntegrationTestFailure(message: "Failed to acquire integration lock: \(lockPath)")
        }
        defer {
            _ = flock(lockFd, LOCK_UN)
            _ = close(lockFd)
        }
        #endif

        return try body()
    }

    private static func readDataWithRetry(from fileURL: URL, attempts: Int = 8, delayMs: UInt64 = 25) throws -> Data {
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try Data(contentsOf: fileURL)
            } catch {
                lastError = error
                if attempt < attempts {
                    Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
                }
            }
        }

        throw lastError ?? IntegrationTestFailure(message: "Failed to read output file: \(fileURL.path)")
    }

    private static func normalizeRelativePath(_ file: URL, relativeTo base: URL) -> String {
        let filePath = file.path.replacingOccurrences(of: "\\", with: "/")
        let basePath = base.path.replacingOccurrences(of: "\\", with: "/")

        guard filePath.hasPrefix(basePath) else {
            return file.lastPathComponent
        }

        return String(filePath.dropFirst(basePath.count + 1))
    }

    private static func projectRootURL(from currentFilePath: String = #filePath) throws -> URL {
        var projectRoot = URL(fileURLWithPath: currentFilePath).deletingLastPathComponent()

        while true {
            if FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("Package.swift").path) {
                return projectRoot
            }

            let parent = projectRoot.deletingLastPathComponent()
            if parent.path == projectRoot.path {
                throw IntegrationTestFailure(message: "Could not find Package.swift starting from \(currentFilePath)")
            }
            projectRoot = parent
        }
    }

    private static func koralcBinaryURL(projectRoot: URL) throws -> URL {
        var koralcBinary = projectRoot.appendingPathComponent(".build/debug/koralc")
        #if os(Windows)
        koralcBinary.appendPathExtension("exe")
        #endif

        guard FileManager.default.fileExists(atPath: koralcBinary.path) else {
            throw IntegrationTestFailure(message: "koralc binary not found at \(koralcBinary.path). Please build first.")
        }

        return koralcBinary
    }

    private static func parseExpectations(in content: String, relativePath: String) throws -> CaseExpectations {
        let lines = content.components(separatedBy: .newlines)
        var expectations = CaseExpectations()

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let value = matchExpectation(line, prefixes: ["// EXPECT: "]) {
                expectations.expectedOutput.append(value)
                continue
            }

            if let value = matchExpectation(line, prefixes: ["// EXPECT-ERROR: ", "// EXPECT_ERROR: ", "// EXPECT ERROR: "]) {
                expectations.expectedErrors.append(value)
                continue
            }

            if let value = matchExpectation(line, prefixes: ["// EXIT: "]) {
                let exitText = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsedExit = Int32(exitText) else {
                    throw IntegrationTestFailure(message: "Invalid // EXIT value in \(relativePath): '\(exitText)'")
                }
                expectations.expectedExit = parsedExit
            }
        }

        return expectations
    }

    private static func matchExpectation(_ line: String, prefixes: [String]) -> String? {
        for prefix in prefixes where line.starts(with: prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func runTestCase(file: URL, projectRoot: URL, relativePath: String) throws {
        let content = try String(contentsOf: file, encoding: .utf8)
        let expectations = try parseExpectations(in: content, relativePath: relativePath)

        guard expectations.hasAssertions else {
            throw IntegrationTestFailure(
                message: "Entry case \(relativePath) is missing EXPECT, EXPECT-ERROR, or EXIT declarations."
            )
        }

        let baseName = file.deletingPathExtension().lastPathComponent
        let casesOutputRoot = projectRoot.appendingPathComponent("Tests/CasesOutput")
        let runDir = casesOutputRoot.appendingPathComponent(baseName).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: runDir)
        }

        let koralcBinary = try koralcBinaryURL(projectRoot: projectRoot)
        let process = Process()
        process.executableURL = koralcBinary
        process.arguments = ["run", file.path, "-o", runDir.path]
        process.currentDirectoryURL = projectRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = OutputBuffer()
        let stderrBuffer = OutputBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutBuffer.append(chunk)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        try process.run()

        if exited.wait(timeout: .now() + caseTimeoutSeconds) == .timedOut {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)

            #if !os(Windows)
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
            #endif

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutBuffer.appendRemaining(from: stdoutPipe.fileHandleForReading)
            let partialStdout = String(decoding: stdoutBuffer.snapshot(), as: UTF8.self)
            stderrBuffer.appendRemaining(from: stderrPipe.fileHandleForReading)
            let partialStderr = String(decoding: stderrBuffer.snapshot(), as: UTF8.self)
            let partialOutput = (partialStdout + partialStderr)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")

            throw IntegrationTestFailure(
                message: "Test timed out after \(Int(caseTimeoutSeconds))s: \(relativePath)\n\nPartial Output:\n\(partialOutput)"
            )
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.appendRemaining(from: stdoutPipe.fileHandleForReading)
        let finalStdout = stdoutBuffer.snapshot()
        stderrBuffer.appendRemaining(from: stderrPipe.fileHandleForReading)
        let finalStderr = stderrBuffer.snapshot()

        let combinedData = finalStdout + finalStderr
        let output = String(decoding: combinedData, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        try verify(
            output: output,
            exitCode: process.terminationStatus,
            expectations: expectations,
            relativePath: relativePath
        )
    }

    private static func verify(
        output: String,
        exitCode: Int32,
        expectations: CaseExpectations,
        relativePath: String
    ) throws {
        let outputLines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var currentLineIndex = 0

        if !expectations.expectedErrors.isEmpty {
            if let expectedExit = expectations.expectedExit, exitCode != expectedExit {
                throw IntegrationTestFailure(
                    message: "Test failed: \(relativePath)\nExpected exit code \(expectedExit), got \(exitCode).\n\nActual Output Lines:\n\(outputLines.joined(separator: "\n"))"
                )
            }

            if expectations.expectedExit == nil && exitCode == 0 {
                throw IntegrationTestFailure(
                    message: "Test failed: \(relativePath)\nExpected non-zero exit code, got 0.\n\nActual Output Lines:\n\(outputLines.joined(separator: "\n"))"
                )
            }

            for expected in expectations.expectedErrors {
                let cleanExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanExpected.isEmpty {
                    continue
                }

                guard let foundIndex = outputLines[currentLineIndex...].firstIndex(where: { $0.contains(cleanExpected) }) else {
                    throw IntegrationTestFailure(
                        message: "Test failed: \(relativePath)\nMissing expected error: \"\(cleanExpected)\"\n\nScanned from line \(currentLineIndex)\n\nActual Output Lines:\n\(outputLines.joined(separator: "\n"))"
                    )
                }

                currentLineIndex = foundIndex + 1
            }

            return
        }

        for expected in expectations.expectedOutput {
            let cleanExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanExpected.isEmpty {
                continue
            }

            guard let foundIndex = outputLines[currentLineIndex...].firstIndex(where: { $0.contains(cleanExpected) }) else {
                throw IntegrationTestFailure(
                    message: "Test failed: \(relativePath)\nMissing expected output: \"\(cleanExpected)\"\nExit code: \(exitCode)\n\nScanned from line \(currentLineIndex)\n\nActual Output Lines:\n\(outputLines.joined(separator: "\n"))"
                )
            }

            currentLineIndex = foundIndex + 1
        }

        let requiredExit = expectations.expectedExit ?? 0
        if exitCode != requiredExit {
            throw IntegrationTestFailure(
                message: "Test failed: \(relativePath)\nExpected exit code \(requiredExit), got \(exitCode).\n\nActual Output Lines:\n\(outputLines.joined(separator: "\n"))"
            )
        }
    }
}

@Suite("Koral Integration Tests")
struct IntegrationTests {
    private static let discoveredCaseFiles: [String] = {
        do {
            let allCases = try IntegrationTestHarness.discoveredCases()
            let environment = ProcessInfo.processInfo.environment

            if let rawLimit = environment["KORAL_TEST_LIMIT"], let limit = Int(rawLimit), limit > 0 {
                return Array(allCases.prefix(limit))
            }

            return allCases
        } catch {
            fatalError("Failed to discover integration cases: \(error)")
        }
    }()

    private static let progress = IntegrationTestProgressReporter(totalCases: discoveredCaseFiles.count)

    @Test("Compiler case", arguments: Self.discoveredCaseFiles)
    func compilerCase(relativePath: String) throws {
        Self.progress.caseStarted(relativePath)

        do {
            try IntegrationTestHarness.runCase(named: relativePath)
            Self.progress.caseFinished(relativePath, failed: false)
        } catch {
            Self.progress.caseFinished(relativePath, failed: true)
            throw error
        }
    }

    @Test("emit-c uses switch fast path")
    func whenEmitCUsesSwitchFastPath() throws {
        let source = try IntegrationTestHarness.emitCForCase(named: "when_switch_lowering.koral")

        if !source.contains("case 17:") {
            throw IntegrationTestFailure(message: "Expected scalar when lowering to emit a literal switch case")
        }

        if !source.contains("default:") {
            throw IntegrationTestFailure(message: "Expected simple when lowering to use switch default for catch-all branches")
        }

        let unionSwitchRegex = try NSRegularExpression(pattern: #"switch \([^\n]*\.tag\) \{[\s\S]*?goto match_end_"#)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        if unionSwitchRegex.firstMatch(in: source, options: [], range: fullRange) == nil {
            throw IntegrationTestFailure(message: "Expected union-tag when lowering to emit a switch on .tag")
        }
    }
}
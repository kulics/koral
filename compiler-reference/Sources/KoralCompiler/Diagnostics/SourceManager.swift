// SourceManager.swift
// Manages source file content for diagnostic rendering.

import Foundation

/// Manages source file content, providing access to source lines for error reporting.
/// Note: This class is marked as @unchecked Sendable because the compiler is single-threaded.
public final class SourceManager: @unchecked Sendable {
    /// Represents a loaded source file with pre-split lines for fast access.
    public struct SourceFile {
        /// The file name (used as identifier)
        public let name: String
        
        /// The complete source content
        public let content: String
        
        /// Pre-split lines for fast line access (0-indexed internally)
        public let lines: [Substring]
        
        /// Creates a new source file.
        /// - Parameters:
        ///   - name: The file name
        ///   - content: The complete source content
        public init(name: String, content: String) {
            self.name = name
            self.content = content
            // Split preserving empty lines
            self.lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        }
        
        /// The number of lines in the file.
        public var lineCount: Int {
            lines.count
        }
    }
    
    /// Cached source files by name
    private var files: [String: SourceFile] = [:]
    
    /// Creates a new empty source manager.
    public init() {}
    
    /// Loads and caches a source file.
    /// - Parameters:
    ///   - name: The file name (used as identifier)
    ///   - content: The source content
    public func loadFile(name: String, content: String) {
        files[name] = SourceFile(name: name, content: content)
    }
    
    /// Gets a specific line from a file.
    /// - Parameters:
    ///   - fileName: The file name
    ///   - lineNumber: The line number (1-based)
    /// - Returns: The line content, or nil if not found
    public func getLine(_ fileName: String, lineNumber: Int) -> String? {
        guard let file = files[fileName],
              lineNumber > 0 && lineNumber <= file.lines.count else {
            return nil
        }
        return String(file.lines[lineNumber - 1])
    }
    
    /// Gets a source file by name.
    /// - Parameter fileName: The file name
    /// - Returns: The source file, or nil if not loaded
    public func getFile(_ fileName: String) -> SourceFile? {
        return files[fileName]
    }
    
    /// Gets a source snippet for a given span.
    /// - Parameters:
    ///   - fileName: The file name
    ///   - span: The source span
    /// - Returns: The source line containing the span start, or nil if not found
    public func getSourceSnippet(_ fileName: String, span: SourceSpan) -> String? {
        return getLine(fileName, lineNumber: span.start.line)
    }
    
    /// Gets multiple lines from a file.
    /// - Parameters:
    ///   - fileName: The file name
    ///   - startLine: The starting line number (1-based, inclusive)
    ///   - endLine: The ending line number (1-based, inclusive)
    /// - Returns: An array of lines, or nil if the file is not found
    public func getLines(_ fileName: String, startLine: Int, endLine: Int) -> [String]? {
        guard let file = files[fileName],
              startLine > 0 && endLine >= startLine && endLine <= file.lines.count else {
            return nil
        }
        return (startLine...endLine).map { String(file.lines[$0 - 1]) }
    }
    
    /// Checks if a file is loaded.
    /// - Parameter fileName: The file name
    /// - Returns: true if the file is loaded
    public func hasFile(_ fileName: String) -> Bool {
        return files[fileName] != nil
    }
    
    /// Gets the number of lines in a file.
    /// - Parameter fileName: The file name
    /// - Returns: The line count, or nil if the file is not loaded
    public func lineCount(_ fileName: String) -> Int? {
        return files[fileName]?.lineCount
    }
}

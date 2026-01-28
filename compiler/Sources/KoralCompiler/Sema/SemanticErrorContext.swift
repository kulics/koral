// SemanticErrorContext.swift
// Centralized source context for semantic diagnostics.

/// Context information for semantic error reporting.
/// Provides global state for error context (compiler is single-threaded).
public enum SemanticErrorContext {
    // Global state for error context
    public nonisolated(unsafe) static var currentFileName: String = "<input>"
    public nonisolated(unsafe) static var currentLine: Int = 1
    public nonisolated(unsafe) static var currentSpan: SourceSpan = .unknown
    public nonisolated(unsafe) static var currentCompilerContext: CompilerContext? = nil
    
    /// Update the current span.
    public static func updateSpan(_ span: SourceSpan) {
        currentSpan = span
        currentLine = span.start.line
    }
    
    /// Update the current line.
    public static func updateLine(_ line: Int) {
        currentLine = line
    }
}

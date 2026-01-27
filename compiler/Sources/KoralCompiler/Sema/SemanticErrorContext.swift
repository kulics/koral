// SemanticErrorContext.swift
// Centralized source context for semantic diagnostics.

/// Context information for semantic error reporting.
/// Maintains a stack of contexts to support nested scopes and accurate error locations.
public enum SemanticErrorContext {
    /// A context frame containing file and location information.
    public struct Context: Sendable {
        public let fileName: String
        public let span: SourceSpan
        
        public init(fileName: String, span: SourceSpan) {
            self.fileName = fileName
            self.span = span
        }
        
        public init(fileName: String, line: Int) {
            self.fileName = fileName
            self.span = SourceSpan(location: SourceLocation(line: line, column: 1))
        }
    }
    
    // Thread-local context stack (compiler is single-threaded)
    private nonisolated(unsafe) static var contextStack: [Context] = []
    
    // Legacy global state for backward compatibility
    public nonisolated(unsafe) static var currentFileName: String = "<input>"
    public nonisolated(unsafe) static var currentLine: Int = 1
    public nonisolated(unsafe) static var currentCompilerContext: CompilerContext? = nil
    
    /// The current context, or a default context if the stack is empty.
    public static var current: Context {
        if let top = contextStack.last {
            return top
        }
        return Context(fileName: currentFileName, span: SourceSpan(location: SourceLocation(line: currentLine, column: 1)))
    }
    
    /// The current span from the context stack, or unknown if empty.
    public static var currentSpan: SourceSpan {
        current.span
    }
    
    /// Push a new context onto the stack.
    public static func push(_ context: Context) {
        contextStack.append(context)
    }
    
    /// Push a context with file name and span.
    public static func push(fileName: String, span: SourceSpan) {
        push(Context(fileName: fileName, span: span))
    }
    
    /// Push a context with file name and line number.
    public static func push(fileName: String, line: Int) {
        push(Context(fileName: fileName, line: line))
    }
    
    /// Pop the top context from the stack.
    @discardableResult
    public static func pop() -> Context? {
        contextStack.popLast()
    }
    
    /// Execute a closure with a temporary context pushed onto the stack.
    /// The context is automatically popped when the closure returns or throws.
    public static func withContext<T>(
        fileName: String,
        span: SourceSpan,
        _ body: () throws -> T
    ) rethrows -> T {
        push(Context(fileName: fileName, span: span))
        defer { pop() }
        return try body()
    }
    
    /// Execute a closure with a temporary context (line-based) pushed onto the stack.
    public static func withContext<T>(
        fileName: String,
        line: Int,
        _ body: () throws -> T
    ) rethrows -> T {
        push(Context(fileName: fileName, line: line))
        defer { pop() }
        return try body()
    }
    
    /// Update the current span without pushing a new context.
    /// This is useful for updating location as we traverse the AST.
    public static func updateSpan(_ span: SourceSpan) {
        if !contextStack.isEmpty {
            let current = contextStack.removeLast()
            contextStack.append(Context(fileName: current.fileName, span: span))
        } else {
            currentLine = span.start.line
        }
    }
    
    /// Update the current line without pushing a new context.
    public static func updateLine(_ line: Int) {
        if !contextStack.isEmpty {
            let current = contextStack.removeLast()
            contextStack.append(Context(fileName: current.fileName, line: line))
        } else {
            currentLine = line
        }
    }
    
    /// Clear all contexts (useful for testing or resetting state).
    public static func reset() {
        contextStack.removeAll()
        currentFileName = "<input>"
        currentLine = 1
    }
}

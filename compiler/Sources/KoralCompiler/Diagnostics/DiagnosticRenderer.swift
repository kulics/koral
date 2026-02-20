// DiagnosticRenderer.swift
// Renders diagnostic errors with source code snippets and error pointers.

import Foundation

/// Renders diagnostic errors with source code context.
public struct DiagnosticRenderer {
    private let sourceManager: SourceManager?
    
    /// Creates a new diagnostic renderer.
    /// - Parameter sourceManager: Optional source manager for retrieving source code lines.
    ///   If nil, source snippets will not be rendered.
    public init(sourceManager: SourceManager? = nil) {
        self.sourceManager = sourceManager
    }
    
    /// Renders a diagnostic error to a formatted string.
    /// - Parameter error: The diagnostic error to render.
    /// - Returns: A formatted error message with optional source snippet.
    public func render(_ error: DiagnosticError) -> String {
        var output = ""
        
        // Header: filename:line:column: stage: message
        let location = formatLocation(error)
        let stage = formatStage(error.stage)
        let message = formatMessage(error.underlying)
        
        output += "\(location): \(stage): \(message)\n"
        
        // Source snippet (if available)
        if let snippet = renderSourceSnippet(error) {
            output += snippet
        }
        
        return output
    }
    
    /// Formats the location part of the error message.
    private func formatLocation(_ error: DiagnosticError) -> String {
        if let moduleError = error.underlying as? ModuleError {
            let fileName = moduleError.locationFile ?? error.fileName
            if moduleError.span.isKnown {
                return "\(fileName):\(moduleError.span.start.line):\(moduleError.span.start.column)"
            }
            return fileName
        }

        let span = extractSpan(from: error.underlying)
        if span.isKnown {
            return "\(error.fileName):\(span.start.line):\(span.start.column)"
        }
        return error.fileName
    }
    
    /// Formats the stage part of the error message.
    private func formatStage(_ stage: DiagnosticError.Stage) -> String {
        switch stage {
        case .lexer: return "lexer error"
        case .parser: return "syntax error"
        case .semantic: return "error"
        case .other: return "error"
        }
    }
    
    /// Formats the error message without location information.
    private func formatMessage(_ error: Error) -> String {
        if let moduleError = error as? ModuleError {
            return moduleError.messageWithoutLocation
        }
        if let semantic = error as? SemanticError {
            return semantic.messageWithoutLocation
        }
        if let parser = error as? ParserError {
            return parser.messageWithoutLocation
        }
        return "\(error)"
    }
    
    /// Extracts the source span from an error.
    private func extractSpan(from error: Error) -> SourceSpan {
        if let moduleError = error as? ModuleError {
            return moduleError.span
        }
        if let semantic = error as? SemanticError {
            return semantic.span
        }
        if let parser = error as? ParserError {
            return parser.span
        }
        return .unknown
    }
    
    /// Renders the source code snippet with error pointer.
    private func renderSourceSnippet(_ error: DiagnosticError) -> String? {
        guard let sourceManager = sourceManager else {
            return nil
        }
        
        let span = extractSpan(from: error.underlying)
        guard span.isKnown else {
            return nil
        }
        
        guard let line = sourceManager.getLine(error.fileName, lineNumber: span.start.line) else {
            return nil
        }
        
        var output = ""
        
        // Line number gutter
        let lineNumStr = String(span.start.line)
        let gutterWidth = lineNumStr.count + 1
        
        // Empty gutter line
        output += String(repeating: " ", count: gutterWidth) + " |\n"
        
        // Source line
        output += " \(lineNumStr) | \(line)\n"
        
        // Error pointer line
        let padding = String(repeating: " ", count: gutterWidth) + " | "
        let pointerPadding = String(repeating: " ", count: max(0, span.start.column - 1))
        
        // Calculate pointer length
        let pointerLength: Int
        if span.start.line == span.end.line {
            pointerLength = max(1, span.end.column - span.start.column + 1)
        } else {
            // Multi-line span: just point to the start
            pointerLength = 1
        }
        
        let pointer: String
        if pointerLength == 1 {
            pointer = "^"
        } else {
            pointer = "^" + String(repeating: "~", count: pointerLength - 1)
        }
        
        output += "\(padding)\(pointerPadding)\(pointer)\n"
        
        return output
    }
}

// MARK: - Convenience Extensions

extension DiagnosticError {
    /// Renders this error using the provided source manager.
    public func render(with sourceManager: SourceManager?) -> String {
        let renderer = DiagnosticRenderer(sourceManager: sourceManager)
        return renderer.render(self)
    }
}

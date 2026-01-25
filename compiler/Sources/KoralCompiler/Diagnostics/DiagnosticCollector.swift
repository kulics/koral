// DiagnosticCollector.swift
// Collects all diagnostics during compilation instead of stopping at the first error.

import Foundation

/// 诊断严重级别
public enum DiagnosticSeverity: Sendable {
    case error
    case warning
    case note
}

/// 诊断注释 - 提供额外的上下文信息
public struct DiagnosticNote: Sendable {
    public let message: String
    public let location: SourceLocation?
    
    public init(message: String, location: SourceLocation? = nil) {
        self.message = message
        self.location = location
    }
}

/// 诊断信息 - 表示一个编译错误、警告或注释
public struct Diagnostic: Sendable {
    public let severity: DiagnosticSeverity
    public let message: String
    public let span: SourceSpan
    public let fileName: String
    public let notes: [DiagnosticNote]
    public let fixHint: String?
    public let isPrimary: Bool  // 是否是主要错误（vs 由其他错误引起的次要错误）
    
    public init(
        severity: DiagnosticSeverity,
        message: String,
        span: SourceSpan,
        fileName: String,
        notes: [DiagnosticNote] = [],
        fixHint: String? = nil,
        isPrimary: Bool = true
    ) {
        self.severity = severity
        self.message = message
        self.span = span
        self.fileName = fileName
        self.notes = notes
        self.fixHint = fixHint
        self.isPrimary = isPrimary
    }
    
    /// Convenience accessor for location
    public var location: SourceLocation {
        span.start
    }
}

/// 诊断收集器 - 收集所有诊断信息而不是在第一个错误时停止
public class DiagnosticCollector {
    private var diagnostics: [Diagnostic] = []
    private var errorCount: Int = 0
    private var warningCount: Int = 0
    
    public init() {}
    
    // MARK: - Error Reporting
    
    /// 报告错误
    public func error(
        _ message: String,
        at span: SourceSpan,
        fileName: String,
        notes: [DiagnosticNote] = [],
        fixHint: String? = nil,
        isPrimary: Bool = true
    ) {
        diagnostics.append(Diagnostic(
            severity: .error,
            message: message,
            span: span,
            fileName: fileName,
            notes: notes,
            fixHint: fixHint,
            isPrimary: isPrimary
        ))
        errorCount += 1
    }
    
    /// 报告错误（使用 SourceLocation）
    public func error(
        _ message: String,
        at location: SourceLocation,
        fileName: String,
        notes: [DiagnosticNote] = [],
        fixHint: String? = nil,
        isPrimary: Bool = true
    ) {
        error(
            message,
            at: SourceSpan(location: location),
            fileName: fileName,
            notes: notes,
            fixHint: fixHint,
            isPrimary: isPrimary
        )
    }
    
    /// 报告次要错误（由其他错误引起的）
    public func secondaryError(
        _ message: String,
        at span: SourceSpan,
        fileName: String,
        causedBy primaryError: String? = nil
    ) {
        var notes: [DiagnosticNote] = []
        if let cause = primaryError {
            notes.append(DiagnosticNote(message: "caused by: \(cause)"))
        }
        error(message, at: span, fileName: fileName, notes: notes, isPrimary: false)
    }
    
    // MARK: - Warning Reporting
    
    /// 报告警告
    public func warning(
        _ message: String,
        at span: SourceSpan,
        fileName: String,
        notes: [DiagnosticNote] = [],
        fixHint: String? = nil
    ) {
        diagnostics.append(Diagnostic(
            severity: .warning,
            message: message,
            span: span,
            fileName: fileName,
            notes: notes,
            fixHint: fixHint,
            isPrimary: true
        ))
        warningCount += 1
    }
    
    /// 报告警告（使用 SourceLocation）
    public func warning(
        _ message: String,
        at location: SourceLocation,
        fileName: String,
        notes: [DiagnosticNote] = [],
        fixHint: String? = nil
    ) {
        warning(
            message,
            at: SourceSpan(location: location),
            fileName: fileName,
            notes: notes,
            fixHint: fixHint
        )
    }
    
    // MARK: - Note Reporting
    
    /// 报告注释
    public func note(
        _ message: String,
        at span: SourceSpan,
        fileName: String
    ) {
        diagnostics.append(Diagnostic(
            severity: .note,
            message: message,
            span: span,
            fileName: fileName,
            notes: [],
            fixHint: nil,
            isPrimary: true
        ))
    }
    
    // MARK: - Query Methods
    
    /// 获取所有诊断信息
    public func getDiagnostics() -> [Diagnostic] {
        return diagnostics
    }
    
    /// 获取所有错误
    public func getErrors() -> [Diagnostic] {
        return diagnostics.filter { $0.severity == .error }
    }
    
    /// 获取所有主要错误
    public func getPrimaryErrors() -> [Diagnostic] {
        return diagnostics.filter { $0.severity == .error && $0.isPrimary }
    }
    
    /// 获取所有次要错误
    public func getSecondaryErrors() -> [Diagnostic] {
        return diagnostics.filter { $0.severity == .error && !$0.isPrimary }
    }
    
    /// 获取所有警告
    public func getWarnings() -> [Diagnostic] {
        return diagnostics.filter { $0.severity == .warning }
    }
    
    /// 是否有错误
    public func hasErrors() -> Bool {
        return errorCount > 0
    }
    
    /// 是否有警告
    public func hasWarnings() -> Bool {
        return warningCount > 0
    }
    
    /// 错误数量
    public var errorCountValue: Int {
        return errorCount
    }
    
    /// 警告数量
    public var warningCountValue: Int {
        return warningCount
    }
    
    /// 清空所有诊断信息
    public func clear() {
        diagnostics.removeAll()
        errorCount = 0
        warningCount = 0
    }
    
    /// 合并另一个收集器的诊断信息
    public func merge(_ other: DiagnosticCollector) {
        diagnostics.append(contentsOf: other.diagnostics)
        errorCount += other.errorCount
        warningCount += other.warningCount
    }
    
    // MARK: - Conversion from existing errors
    
    /// 从 SemanticError 添加诊断
    public func addSemanticError(_ error: SemanticError, isPrimary: Bool = true) {
        self.error(
            error.messageWithoutLocation,
            at: error.span,
            fileName: error.fileName,
            isPrimary: isPrimary
        )
    }
    
    /// 从 DiagnosticError 添加诊断
    public func addDiagnosticError(_ error: DiagnosticError, isPrimary: Bool = true) {
        if let semantic = error.underlying as? SemanticError {
            addSemanticError(semantic, isPrimary: isPrimary)
        } else if let parser = error.underlying as? ParserError {
            self.error(
                parser.messageWithoutLocation,
                at: parser.span,
                fileName: error.fileName,
                isPrimary: isPrimary
            )
        } else {
            self.error(
                "\(error.underlying)",
                at: SourceSpan.unknown,
                fileName: error.fileName,
                isPrimary: isPrimary
            )
        }
    }
}

// MARK: - Diagnostic Formatting

extension Diagnostic: CustomStringConvertible {
    public var description: String {
        let severityStr: String
        let severityPrefix: String
        switch severity {
        case .error:
            severityStr = "error"
            severityPrefix = isPrimary ? "error" : "secondary error"
        case .warning:
            severityStr = "warning"
            severityPrefix = "warning"
        case .note:
            severityStr = "note"
            severityPrefix = "note"
        }
        _ = severityStr
        
        let locationStr: String
        if span.isKnown {
            locationStr = "\(fileName):\(span.start.line):\(span.start.column)"
        } else {
            locationStr = fileName
        }
        
        var result = "\(locationStr): \(severityPrefix): \(message)"
        
        // Add fix hint if available
        if let hint = fixHint {
            result += "\n  hint: \(hint)"
        }
        
        // Add notes
        for note in notes {
            if let loc = note.location, loc.isKnown {
                result += "\n  note: \(note.message) at \(loc.line):\(loc.column)"
            } else {
                result += "\n  note: \(note.message)"
            }
        }
        
        return result
    }
    
    /// 格式化为带有源代码片段的诊断消息
    /// - Parameter sourceManager: 源代码管理器（用于获取源代码片段）
    /// - Returns: 格式化后的诊断消息
    public func formatWithSource(sourceManager: SourceManager?) -> String {
        var result = description
        
        // Add source code snippet if available
        if let manager = sourceManager, span.isKnown {
            if let snippet = manager.getSourceSnippet(fileName, span: span) {
                result += "\n  |\n"
                result += "  | \(snippet)\n"
                // Add caret pointing to the error column
                if span.start.column > 0 {
                    let padding = String(repeating: " ", count: span.start.column - 1)
                    result += "  | \(padding)^"
                }
            }
        }
        
        return result
    }
}

extension DiagnosticCollector: CustomStringConvertible {
    public var description: String {
        var lines: [String] = []
        
        for diagnostic in diagnostics {
            lines.append(diagnostic.description)
        }
        
        if errorCount > 0 || warningCount > 0 {
            var summary = ""
            if errorCount > 0 {
                summary += "\(errorCount) error\(errorCount == 1 ? "" : "s")"
            }
            if warningCount > 0 {
                if !summary.isEmpty { summary += ", " }
                summary += "\(warningCount) warning\(warningCount == 1 ? "" : "s")"
            }
            lines.append(summary + " generated.")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// 格式化所有诊断信息（带有源代码片段）
    /// - Parameter sourceManager: 源代码管理器
    /// - Returns: 格式化后的诊断消息
    public func formatWithSource(sourceManager: SourceManager?) -> String {
        var lines: [String] = []
        
        for diagnostic in diagnostics {
            lines.append(diagnostic.formatWithSource(sourceManager: sourceManager))
        }
        
        if errorCount > 0 || warningCount > 0 {
            var summary = ""
            if errorCount > 0 {
                let primaryCount = getPrimaryErrors().count
                let secondaryCount = getSecondaryErrors().count
                if secondaryCount > 0 {
                    summary += "\(primaryCount) error\(primaryCount == 1 ? "" : "s") (\(secondaryCount) secondary)"
                } else {
                    summary += "\(errorCount) error\(errorCount == 1 ? "" : "s")"
                }
            }
            if warningCount > 0 {
                if !summary.isEmpty { summary += ", " }
                summary += "\(warningCount) warning\(warningCount == 1 ? "" : "s")"
            }
            lines.append(summary + " generated.")
        }
        
        return lines.joined(separator: "\n")
    }
}

// Allow DiagnosticCollector to be thrown and caught as an Error
extension DiagnosticCollector: Error, @unchecked Sendable {}

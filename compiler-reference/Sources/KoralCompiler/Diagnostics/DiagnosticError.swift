import Foundation

public struct DiagnosticError: Error, Sendable {
  public enum Stage: Sendable {
    case lexer
    case parser
    case semantic
    case other
  }

  public let stage: Stage
  public let fileName: String
  public let underlying: Error
  public var sourceManager: SourceManager?

  public init(stage: Stage, fileName: String, underlying: Error, sourceManager: SourceManager? = nil) {
    self.stage = stage
    self.underlying = underlying
    self.sourceManager = sourceManager
    // The span knows its own file; the caller's file is only the fallback for
    // spans that were synthesized rather than lexed.
    self.fileName = DiagnosticError.spanFile(of: underlying) ?? fileName
  }

  private static func spanFile(of error: Error) -> String? {
    if let semantic = error as? SemanticError {
      return semantic.fileName
    }
    if let parser = error as? ParserError {
      return parser.span.fileName
    }
    return nil
  }

  /// Renders the error for CLI output with source code snippet if available.
  public func renderForCLI() -> String {
    let renderer = DiagnosticRenderer(sourceManager: sourceManager)
    return renderer.render(self).trimmingCharacters(in: .newlines)
  }
  
  private func extractSpan() -> SourceSpan {
    if let semantic = underlying as? SemanticError {
      return semantic.span
    }
    if let parser = underlying as? ParserError {
      return parser.span
    }
    return .unknown
  }
  
  private func formatMessage() -> String {
    if let semantic = underlying as? SemanticError {
      return semantic.messageWithoutLocation
    }
    if let parser = underlying as? ParserError {
      return parser.messageWithoutLocation
    }
    return "\(underlying)"
  }
}

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
    self.fileName = fileName
    self.underlying = underlying
    self.sourceManager = sourceManager
  }

  /// Renders the error for CLI output with source code snippet if available.
  public func renderForCLI() -> String {
    let renderer = DiagnosticRenderer(sourceManager: sourceManager)
    return renderer.render(self).trimmingCharacters(in: .newlines)
  }
  
  /// Renders the error without source snippet (legacy format).
  public func renderSimple() -> String {
    let span = extractSpan()
    let location: String
    if span.isKnown {
      location = "\(fileName):\(span.start.line):\(span.start.column)"
    } else {
      location = fileName
    }
    
    let stageStr: String
    switch stage {
    case .lexer: stageStr = "Lexer Error"
    case .parser: stageStr = "Parser Error"
    case .semantic: stageStr = "Semantic Error"
    case .other: stageStr = "Error"
    }
    
    let message = formatMessage()
    return "\(location): \(stageStr): \(message)"
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

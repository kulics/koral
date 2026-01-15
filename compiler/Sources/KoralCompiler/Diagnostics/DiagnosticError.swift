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

  public init(stage: Stage, fileName: String, underlying: Error) {
    self.stage = stage
    self.fileName = fileName
    self.underlying = underlying
  }

  public func renderForCLI() -> String {
    switch stage {
    case .lexer:
      return "\(fileName): Lexer Error: \(underlying)"
    case .parser:
      return "\(fileName): Parser Error: \(underlying)"
    case .semantic:
      return "\(fileName): Semantic Error: \(underlying)"
    case .other:
      return "\(fileName): Error: \(underlying)"
    }
  }
}

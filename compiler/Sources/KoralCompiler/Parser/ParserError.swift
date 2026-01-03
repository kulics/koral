// Define lexer error types
public enum LexerError: Error {
  case invalidFloat(line: Int, String)
  case invalidString(line: Int, String)
  case unexpectedCharacter(line: Int, String)
}

extension LexerError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidFloat(let line, let msg):
      "Line \(line): Invalid float number: \(msg)"
    case .invalidString(let line, let msg):
      "Line \(line): Invalid string: \(msg)"
    case .unexpectedCharacter(let line, let msg):
      "Line \(line): Unexpected character: \(msg)"
    }
  }
}

public enum ParserError: Error {
  case unexpectedToken(line: Int, got: String, expected: String? = nil)
  case expectedIdentifier(line: Int, got: String)
  case expectedTypeIdentifier(line: Int, got: String)
  case unexpectedEndOfFile(line: Int)
  case expectedFinalExpression(line: Int)
  case invalidVariableName(line: Int, name: String)
  case invalidFunctionName(line: Int, name: String)
  case invalidTypeName(line: Int, name: String)
}

extension ParserError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .unexpectedToken(let line, let token, let expected):
      if let exp = expected {
        return "Line \(line): Unexpected token: \(token), expected: \(exp)"
      }
      return "Line \(line): Unexpected token: \(token)"
    case .expectedIdentifier(let line, let token):
      return "Line \(line): Expected identifier, got: \(token)"
    case .expectedTypeIdentifier(let line, let token):
      return "Line \(line): Expected type identifier, got: \(token)"
    case .unexpectedEndOfFile(let line):
      return "Line \(line): Unexpected end of file"
    case .expectedFinalExpression(let line):
      return "Line \(line): Expected final expression in block expression"
    case .invalidVariableName(let line, let name):
      return "Line \(line): Variable name '\(name)' must start with a lowercase letter"
    case .invalidFunctionName(let line, let name):
      return "Line \(line): Function name '\(name)' must start with a lowercase letter"
    case .invalidTypeName(let line, let name):
      return "Line \(line): Type name '\(name)' must start with an uppercase letter"
    }
  }
}

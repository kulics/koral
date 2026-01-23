// Define lexer error types
public enum LexerError: Error {
  case invalidFloat(span: SourceSpan, String)
  case invalidInteger(span: SourceSpan, String)
  case invalidString(span: SourceSpan, String)
  case unexpectedCharacter(span: SourceSpan, String)
  case unexpectedEndOfFile(span: SourceSpan)
  
  /// The source span where the error occurred
  public var span: SourceSpan {
    switch self {
    case .invalidFloat(let span, _): return span
    case .invalidInteger(let span, _): return span
    case .invalidString(let span, _): return span
    case .unexpectedCharacter(let span, _): return span
    case .unexpectedEndOfFile(let span): return span
    }
  }
  
  /// The line number (for backward compatibility)
  public var line: Int {
    span.start.line
  }
  
  /// The column number
  public var column: Int {
    span.start.column
  }
  
  /// The error message without location information
  public var messageWithoutLocation: String {
    switch self {
    case .invalidFloat(_, let msg):
      return "Invalid float number: \(msg)"
    case .invalidInteger(_, let msg):
      return "Invalid integer number: \(msg)"
    case .invalidString(_, let msg):
      return "Invalid string: \(msg)"
    case .unexpectedCharacter(_, let msg):
      return "Unexpected character: \(msg)"
    case .unexpectedEndOfFile:
      return "Unexpected end of file"
    }
  }
}

extension LexerError: CustomStringConvertible {
  public var description: String {
    let location = span.isKnown ? "\(span.start.line):\(span.start.column): " : ""
    return "\(location)\(messageWithoutLocation)"
  }
}

public enum ParserError: Error {
  case unexpectedToken(span: SourceSpan, got: String, expected: String? = nil)
  case expectedIdentifier(span: SourceSpan, got: String)
  case expectedTypeIdentifier(span: SourceSpan, got: String)
  case unexpectedEndOfFile(span: SourceSpan)
  case expectedFinalExpression(span: SourceSpan)
  case invalidVariableName(span: SourceSpan, name: String)
  case invalidFunctionName(span: SourceSpan, name: String)
  case invalidTypeName(span: SourceSpan, name: String)
  // Module system errors
  case usingAfterDeclaration(span: SourceSpan)
  case fileMergeNoAccessModifier(span: SourceSpan)
  case expectedDot(span: SourceSpan)
  // Function type errors
  case invalidFunctionType(span: SourceSpan, message: String)
  // Lambda expression errors
  case expectedArrow(span: SourceSpan)
  
  /// The source span where the error occurred
  public var span: SourceSpan {
    switch self {
    case .unexpectedToken(let span, _, _): return span
    case .expectedIdentifier(let span, _): return span
    case .expectedTypeIdentifier(let span, _): return span
    case .unexpectedEndOfFile(let span): return span
    case .expectedFinalExpression(let span): return span
    case .invalidVariableName(let span, _): return span
    case .invalidFunctionName(let span, _): return span
    case .invalidTypeName(let span, _): return span
    case .usingAfterDeclaration(let span): return span
    case .fileMergeNoAccessModifier(let span): return span
    case .expectedDot(let span): return span
    case .invalidFunctionType(let span, _): return span
    case .expectedArrow(let span): return span
    }
  }
  
  /// The line number (for backward compatibility)
  public var line: Int {
    span.start.line
  }
  
  /// The column number
  public var column: Int {
    span.start.column
  }
  
  /// The error message without location information
  public var messageWithoutLocation: String {
    switch self {
    case .unexpectedToken(_, let token, let expected):
      if let exp = expected {
        return "Unexpected token: \(token), expected: \(exp)"
      }
      return "Unexpected token: \(token)"
    case .expectedIdentifier(_, let token):
      return "Expected identifier, got: \(token)"
    case .expectedTypeIdentifier(_, let token):
      return "Expected type identifier, got: \(token)"
    case .unexpectedEndOfFile:
      return "Unexpected end of file"
    case .expectedFinalExpression:
      return "Expected final expression in block expression"
    case .invalidVariableName(_, let name):
      return "Variable name '\(name)' must start with a lowercase letter"
    case .invalidFunctionName(_, let name):
      return "Function name '\(name)' must start with a lowercase letter"
    case .invalidTypeName(_, let name):
      return "Type name '\(name)' must start with an uppercase letter"
    case .usingAfterDeclaration:
      return "Using declarations must appear before other declarations"
    case .fileMergeNoAccessModifier:
      return "File merge (using \"...\") does not support access modifiers"
    case .expectedDot:
      return "Expected '.' after 'self' in using declaration"
    case .invalidFunctionType(_, let message):
      return "Invalid function type: \(message)"
    case .expectedArrow:
      return "Expected '->' in lambda expression"
    }
  }
}

extension ParserError: CustomStringConvertible {
  public var description: String {
    let location = span.isKnown ? "\(span.start.line):\(span.start.column): " : ""
    return "\(location)\(messageWithoutLocation)"
  }
}

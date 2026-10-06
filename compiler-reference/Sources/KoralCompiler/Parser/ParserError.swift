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
  
  /// The column number
  public var column: Int {
    span.start.column
  }
  
  /// The error message without location information.
  ///
  /// No category wrapper (`Invalid integer number: ...`). The specific message
  /// already says what is wrong, and the wrapper made for doubled adjectives
  /// (`Invalid integer number: Invalid digit '2' in ...`).
  public var messageWithoutLocation: String {
    switch self {
    case .invalidFloat(_, let msg):
      return msg
    case .invalidInteger(_, let msg):
      return msg
    case .invalidString(_, let msg):
      return msg
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
  /// An identifier was expected where `context` names the role it would play
  /// ("field name", "parameter", ...). The role is what makes the message
  /// actionable -- "Expected identifier for field name, got: let" tells you both
  /// what was missing and where the parser was.
  case expectedIdentifier(span: SourceSpan, got: String, context: String? = nil)
  case expectedTypeIdentifier(span: SourceSpan, got: String)
  /// A type parameter was declared without any constraint. `[T]` is not a valid
  /// way to write "no constraints" -- the vacuous constraint is spelled `Any`.
  case missingTypeParameterConstraint(span: SourceSpan, name: String)
  case missingReturnType(span: SourceSpan)
  case unexpectedEndOfFile(span: SourceSpan)
  case invalidVariableName(span: SourceSpan, name: String)
  case invalidFunctionName(span: SourceSpan, name: String)
  case invalidTypeName(span: SourceSpan, name: String)
  case invalidFieldName(span: SourceSpan, name: String)
  case invalidParameterName(span: SourceSpan, name: String)
  case invalidEnumCaseName(span: SourceSpan, name: String)
  case invalidModuleName(span: SourceSpan, name: String)
  // Module system errors
  case usingAfterDeclaration(span: SourceSpan)
  case invalidUsingAliasCase(span: SourceSpan, alias: String, referenced: String, expectedUppercase: Bool)
  // Function type errors
  case invalidFunctionType(span: SourceSpan, message: String)
  // Lambda expression errors
  case expectedArrow(span: SourceSpan)
  case invalidReceiverParameterSyntax(span: SourceSpan)
  // Foreign declaration errors
  case foreignAndIntrinsicConflict(span: SourceSpan)
  case duplicateDeclarationModifier(span: SourceSpan, modifier: String)
  case foreignFunctionNoBody(span: SourceSpan)
  case foreignTypeNoBody(span: SourceSpan)
  case foreignFunctionNoGenerics(span: SourceSpan)
  case emptyInterpolationExpression(span: SourceSpan)
  case invalidAccessModifierOrder(span: SourceSpan, message: String)
  case invalidComparisonChain(span: SourceSpan, message: String)
  case defaultValuesRequireNamedParameter(span: SourceSpan)
  /// A construct whose tokens are all valid but whose shape the language
  /// rejects: a removed feature, a modifier in the wrong place, an ordering
  /// rule. `unexpectedToken` reports a wrong *token* and so frames the message
  /// as `Unexpected token: <got>, expected: <want>`. Here the tokens were fine
  /// -- the construct is what is disallowed -- so the message stands alone.
  case rejectedConstruct(span: SourceSpan, message: String)
  
  /// The source span where the error occurred
  public var span: SourceSpan {
    switch self {
    case .unexpectedToken(let span, _, _): return span
    case .expectedIdentifier(let span, _, _): return span
    case .missingTypeParameterConstraint(let span, _): return span
    case .expectedTypeIdentifier(let span, _): return span
    case .missingReturnType(let span): return span
    case .unexpectedEndOfFile(let span): return span
    case .invalidVariableName(let span, _): return span
    case .invalidFunctionName(let span, _): return span
    case .invalidTypeName(let span, _): return span
    case .invalidFieldName(let span, _): return span
    case .invalidParameterName(let span, _): return span
    case .invalidEnumCaseName(let span, _): return span
    case .invalidModuleName(let span, _): return span
    case .usingAfterDeclaration(let span): return span
    case .invalidUsingAliasCase(let span, _, _, _): return span
    case .invalidFunctionType(let span, _): return span
    case .expectedArrow(let span): return span
    case .invalidReceiverParameterSyntax(let span): return span
    case .foreignAndIntrinsicConflict(let span): return span
    case .duplicateDeclarationModifier(let span, _): return span
    case .foreignFunctionNoBody(let span): return span
    case .foreignTypeNoBody(let span): return span
    case .foreignFunctionNoGenerics(let span): return span
    case .emptyInterpolationExpression(let span): return span
    case .invalidAccessModifierOrder(let span, _): return span
    case .invalidComparisonChain(let span, _): return span
    case .defaultValuesRequireNamedParameter(let span): return span
    case .rejectedConstruct(let span, _): return span
    }
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
    case .expectedIdentifier(_, let token, let context):
      if let context {
        return "Expected identifier for \(context), got: \(token)"
      }
      return "Expected identifier, got: \(token)"
    case .missingTypeParameterConstraint(_, let name):
      return "Type parameter '\(name)' requires a constraint"
    case .expectedTypeIdentifier(_, let token):
      return "Expected type identifier, got: \(token)"
    case .missingReturnType:
      return "Missing return type: function and method declarations must explicitly declare a return type"
    case .unexpectedEndOfFile:
      return "Unexpected end of file"
    case .invalidVariableName(_, let name):
      return "Variable name '\(name)' must start with a lowercase letter"
    case .invalidFunctionName(_, let name):
      return "Function name '\(name)' must start with a lowercase letter"
    case .invalidTypeName(_, let name):
      return "Type name '\(name)' must start with an uppercase letter"
    case .invalidFieldName(_, let name):
      return "Field name '\(name)' must start with a lowercase letter"
    case .invalidParameterName(_, let name):
      return "Parameter name '\(name)' must start with a lowercase letter"
    case .invalidEnumCaseName(_, let name):
      return "Enum case name '\(name)' must start with an uppercase letter"
    case .invalidModuleName(_, let name):
      return "Module name '\(name)' must start with a lowercase letter"
    case .usingAfterDeclaration:
      return "Using declarations must appear before other declarations"
    case .invalidUsingAliasCase(_, let alias, let referenced, let expectedUppercase):
      if expectedUppercase {
        return "Using alias '\(alias)' is invalid: alias must start with an uppercase letter because referenced identifier '\(referenced)' starts with uppercase"
      }
      return "Using alias '\(alias)' is invalid: alias must start with a lowercase letter because referenced identifier '\(referenced)' starts with lowercase"
    case .invalidFunctionType(_, let message):
      return "Invalid function type: \(message)"
    case .expectedArrow:
      return "Expected '->' in lambda expression"
    case .invalidReceiverParameterSyntax:
      return "Invalid receiver parameter syntax: use 'self' only"
    case .foreignAndIntrinsicConflict:
      return "foreign and intrinsic cannot be used together"
    case .duplicateDeclarationModifier(_, let modifier):
      return "Duplicate declaration modifier: \(modifier)"
    case .foreignFunctionNoBody:
      return "foreign function cannot have a body"
    case .foreignTypeNoBody:
      return "foreign type cannot be declared without a body"
    case .foreignFunctionNoGenerics:
      return "foreign function does not support generics"
    case .emptyInterpolationExpression:
      return "empty interpolation expression"
    case .invalidAccessModifierOrder(_, let message):
      return message
    case .invalidComparisonChain(_, let message):
      return message
    case .defaultValuesRequireNamedParameter:
      return "Default values are only allowed for named parameters (use 'name: Type = value' syntax)"
    case .rejectedConstruct(_, let message):
      return message
    }
  }
}

extension ParserError: CustomStringConvertible {
  public var description: String {
    let location = span.isKnown ? "\(span.start.line):\(span.start.column): " : ""
    return "\(location)\(messageWithoutLocation)"
  }
}

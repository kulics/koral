// Parser class
public class Parser {
  let lexer: Lexer
  var currentToken: Token

  public init(lexer: Lexer) {
    self.lexer = lexer
    self.currentToken = .bof
  }
  
  /// Get the current token's source span
  var currentSpan: SourceSpan {
    lexer.tokenSpan
  }
  
  /// Get a source span at the current location
  var currentLocation: SourceSpan {
    SourceSpan(location: lexer.currentLocation)
  }

  // Match current token type
  func match(_ expected: Token) throws {
    if currentToken === expected {
      currentToken = try lexer.getNextToken()
    } else {
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description
      )
    }
  }
  
  /// Check if the current position should terminate a statement/declaration.
  /// Returns true if:
  /// 1. Current token is a semicolon
  /// 2. There was a newline before current token AND current token is not a continuation token
  ///    (unless there was a blank line or comment, which blocks continuation)
  /// 3. Current token is EOF or right brace (end of block)
  func shouldTerminateStatement() -> Bool {
    // Explicit termination
    if currentToken === .semicolon {
      return true
    }
    // End of file or block
    if currentToken === .eof || currentToken === .rightBrace {
      return true
    }
    // Newline-based termination
    if lexer.newlineBeforeCurrent {
      // If there was a blank line or comment, always terminate (no continuation allowed)
      if lexer.blankLineOrCommentBeforeCurrent {
        return true
      }
      // Otherwise, check if current token is a continuation token
      if !currentToken.isContinuationToken {
        return true
      }
    }
    return false
  }

  
  /// Consume optional semicolon if present
  func consumeOptionalSemicolon() throws {
    if currentToken === .semicolon {
      try match(.semicolon)
    }
  }

  /// True if a newline before the current token is *blocked* from continuing
  /// the previous expression/statement due to intervening blank lines or comments.
  func isLineContinuationBlocked() -> Bool {
    lexer.newlineBeforeCurrent && lexer.blankLineOrCommentBeforeCurrent
  }

  // Parse program
  public func parse() throws -> ASTNode {
    var globalNodes: [GlobalNode] = []
    var seenNonUsing = false
    
    self.currentToken = try self.lexer.getNextToken()
    while currentToken !== .eof {
      // Check for foreign using declaration
      if isForeignUsingDeclaration() {
        let foreignUsingDecl = try parseForeignUsingDeclaration()
        globalNodes.append(foreignUsingDecl)
        try consumeOptionalSemicolon()
      } else if isUsingDeclaration() {
        if seenNonUsing {
          throw ParserError.usingAfterDeclaration(span: currentSpan)
        }
        let usingDecl = try parseUsingDeclaration()
        globalNodes.append(.usingDeclaration(usingDecl))
        try consumeOptionalSemicolon()
      } else {
        seenNonUsing = true
        let statement = try parseGlobalDeclaration()
        globalNodes.append(statement)
        // Consume optional semicolon after global declaration
        try consumeOptionalSemicolon()
      }
    }
    return .program(globalNodes: globalNodes)
  }
  
  // MARK: - Statement Parsing

  // Parse statement
  func statement() throws -> StatementNode {
    // Record the span at the start of the statement
    let startSpan = currentSpan
    
    switch currentToken {
    case .letKeyword:
      return try variableDeclaration()
    case .returnKeyword:
      try match(.returnKeyword)
      // return; or return <expr>;
      // Also check for automatic statement termination (newline before non-continuation token)
      if currentToken === .semicolon || currentToken === .rightBrace || shouldTerminateStatement() {
        return .return(value: nil, span: startSpan)
      }
      let value = try expression()
      return .return(value: value, span: startSpan)
    case .breakKeyword:
      try match(.breakKeyword)
      return .break(span: startSpan)
    case .continueKeyword:
      try match(.continueKeyword)
      return .continue(span: startSpan)
    case .deferKeyword:
      try match(.deferKeyword)
      let expr = try expression()
      return .`defer`(expression: expr, span: startSpan)
    default:
      let expr = try expression()

      if currentToken === .equal {
        try match(.equal)
        let value = try expression()
        if case .deptrExpression(let pointer) = expr {
          return .deptrAssignment(pointer: pointer, operator: nil, value: value, span: startSpan)
        }
        return .assignment(target: expr, operator: nil, value: value, span: startSpan)
      } else if let op = getCompoundAssignmentOperator(currentToken) {
        try match(currentToken)
        let value = try expression()
        if case .deptrExpression(let pointer) = expr {
          return .deptrAssignment(pointer: pointer, operator: op, value: value, span: startSpan)
        }
        return .assignment(
          target: expr, operator: op, value: value, span: startSpan)
      }
      return .expression(expr, span: startSpan)
    }
  }

  private func getCompoundAssignmentOperator(_ token: Token) -> CompoundAssignmentOperator? {
    switch token {
    case .plusEqual: return .plus
    case .minusEqual: return .minus
    case .multiplyEqual: return .multiply
    case .divideEqual: return .divide
    case .moduloEqual: return .modulo
    case .ampersandEqual: return .bitwiseAnd
    case .pipeEqual: return .bitwiseOr
    case .caretEqual: return .bitwiseXor
    case .leftShiftEqual: return .shiftLeft
    case .rightShiftEqual: return .shiftRight
    default: return nil
    }
  }

  func parseLetContent() throws -> (
    name: String, type: TypeNode?, value: ExpressionNode, mutable: Bool
  ) {
    try match(.letKeyword)
    var mutable = false
    if currentToken === .mutKeyword {
      try match(.mutKeyword)
      mutable = true
    }
    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
    }

    if !isValidVariableName(name) {
      throw ParserError.invalidVariableName(span: currentSpan, name: name)
    }

    try match(.identifier(name))

    var type: TypeNode? = nil
    if currentToken !== .equal {
      type = try parseType()
    }

    try match(.equal)
    let value = try expression()
    return (name, type, value, mutable)
  }

  // Parse variable declaration
  private func variableDeclaration() throws -> StatementNode {
    // Record the span at the start of the declaration (at 'let' keyword)
    let startSpan = currentSpan
    let (name, type, value, mutable) = try parseLetContent()

    if currentToken === .thenKeyword {
      try match(.thenKeyword)
      let body = try expression()
      return .expression(
        .letExpression(name: name, type: type, value: value, mutable: mutable, body: body),
        span: startSpan)
    }

    return .variableDeclaration(
      name: name, type: type, value: value, mutable: mutable, span: startSpan)
  }


  // MARK: - Utility Methods

  func isValidVariableName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    // Allow names starting with lowercase letter or underscore
    return first.isLowercase || first == "_"
  }

  func isValidTypeName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    return first.isUppercase
  }
}

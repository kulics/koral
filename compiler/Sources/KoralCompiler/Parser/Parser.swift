// Parser class
public class Parser {
  let lexer: Lexer
  var currentToken: Token
  private var lineJoinGroupingDepth: Int = 0

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
  
  func withLineJoinGrouping<T>(_ body: () throws -> T) rethrows -> T {
    lineJoinGroupingDepth += 1
    defer { lineJoinGroupingDepth -= 1 }
    return try body()
  }

  func isInsideLineJoinGrouping() -> Bool {
    lineJoinGroupingDepth > 0
  }

  func allowsLineJoinAfterNewline(_ token: Token) -> Bool {
    return token.isLineJoinToken
  }

  func allowsPostfixAfterNewline(_ token: Token) -> Bool {
    token === .dot
  }

  func shouldBreakBinaryAtCurrentToken() -> Bool {
    lexer.newlineBeforeCurrent && !(allowsLineJoinAfterNewline(currentToken) || isInsideLineJoinGrouping())
  }

  func canContinueRangeBoundAfterNewline() -> Bool {
    !lexer.newlineBeforeCurrent || isInsideLineJoinGrouping()
  }

  func requireNoLineBreakBeforeRHS() throws {
    if lexer.newlineBeforeCurrent && !isInsideLineJoinGrouping() {
      throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
    }
  }

  /// Check if the current position should terminate a statement/declaration.
  /// Returns true if:
  /// 1. Current token is a semicolon
  /// 2. There was a newline before current token AND current token is not a permitted line-join token
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
      if !allowsLineJoinAfterNewline(currentToken) {
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

  // Parse program
  public func parse() throws -> ASTNode {
    var globalNodes: [GlobalNode] = []
    var seenNonUsing = false
    
    self.currentToken = try self.lexer.getNextToken()
    while currentToken !== .eof {
      if isUsingDeclaration() {
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
    let startSpan = currentSpan

    switch currentToken {
    case .letKeyword:
      return try variableDeclaration()
    case .returnKeyword:
      try match(.returnKeyword)
      if currentToken === .semicolon || currentToken === .rightBrace || shouldTerminateStatement() {
        return .return(value: nil, span: startSpan)
      }
      let value = try expression()
      return .return(value: value, span: startSpan)
    case .breakKeyword:
      try match(.breakKeyword)
      if currentToken === .semicolon || currentToken === .rightBrace || shouldTerminateStatement() {
        return .break(value: nil, span: startSpan)
      }
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "statement terminator after 'break'"
      )
    case .yieldKeyword:
      try match(.yieldKeyword)
      let value = try expression()
      return .yield(value: value, span: startSpan)
    case .continueKeyword:
      try match(.continueKeyword)
      return .continue(span: startSpan)
    case .deferKeyword:
      try match(.deferKeyword)
      let expr = try expression()
      return .deferStatement(expression: expr, span: startSpan)
    default:
      let expr = try expression()

      if currentToken === .equal {
        try match(.equal)
        let value = try expression()
        return .assignment(target: expr, operator: nil, value: value, span: startSpan)
      } else if let op = getCompoundAssignmentOperator(currentToken) {
        try match(currentToken)
        let value = try expression()
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
    case .remainderEqual: return .remainder
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
    if currentToken === .mutableKeyword {
      try match(.mutableKeyword)
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

  // Parse variable declaration or pair destructuring
  private func variableDeclaration() throws -> StatementNode {
    // Record the span at the start of the declaration (at 'let' keyword)
    let startSpan = currentSpan
    try match(.letKeyword)

    // After 'let', if we see '(' it's pair destructuring: let (a, b) = expr
    if currentToken === .leftParen {
      return try parsePairVariableDeclaration(startSpan: startSpan)
    }

    // Normal variable declaration: let [mutable] name [Type] = expr
    var mutable = false
    if currentToken === .mutableKeyword {
      try match(.mutableKeyword)
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

    return .variableDeclaration(
      name: name, type: type, value: value, mutable: mutable, span: startSpan)
  }

  /// Parse pair destructuring: `let (binding1, binding2) = expr`
  /// Each binding is: `_` | `[mutable] name [Type]`
  private func parsePairVariableDeclaration(startSpan: SourceSpan) throws -> StatementNode {
    try match(.leftParen)

    let first = try parsePairBindingElement()

    try match(.comma)

    let second = try parsePairBindingElement()

    try match(.rightParen)
    try match(.equal)

    let value = try expression()

    return .pairVariableDeclaration(first: first, second: second, value: value, span: startSpan)
  }

  /// Parse a single binding element inside pair destructuring: `_` | `[mutable] name [Type]`
  private func parsePairBindingElement() throws -> PairBindingElement {
    let elemSpan = currentSpan

    // Check for wildcard
    if case .identifier("_") = currentToken {
      try match(.identifier("_"))
      return PairBindingElement(name: "_", type: nil, mutable: false, isDiscard: true, span: elemSpan)
    }

    // Check for mutable
    var mutable = false
    if currentToken === .mutableKeyword {
      try match(.mutableKeyword)
      mutable = true
    }

    // Expect identifier
    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
    }

    if !isValidVariableName(name) {
      throw ParserError.invalidVariableName(span: currentSpan, name: name)
    }

    try match(.identifier(name))

    // Optional type annotation (anything before ',' or ')')
    var type: TypeNode? = nil
    if currentToken !== .comma && currentToken !== .rightParen {
      type = try parseType()
    }

    return PairBindingElement(name: name, type: type, mutable: mutable, isDiscard: false, span: elemSpan)
  }


  // MARK: - Utility Methods

  enum IdentifierStyle {
    case value
    case type
    case underscoreOnly
    case invalid
  }

  func isASCIIUppercase(_ char: Character) -> Bool {
    guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else {
      return false
    }
    return scalar.value >= 65 && scalar.value <= 90
  }

  func isASCIILowercase(_ char: Character) -> Bool {
    guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else {
      return false
    }
    return scalar.value >= 97 && scalar.value <= 122
  }

  func identifierStyle(of name: String) -> IdentifierStyle {
    guard !name.isEmpty else { return .invalid }
    for char in name {
      if char == "_" { continue }
      if isASCIILowercase(char) { return .value }
      if isASCIIUppercase(char) { return .type }
      return .invalid
    }
    return .underscoreOnly
  }

  func canStartTypeSyntax() -> Bool {
    switch currentToken {
    case .selfTypeKeyword, .leftBracket,
         .ampersand, .multiply, .questionMark:
      return true
    case .identifier:
      return true
    default:
      return false
    }
  }

  func isValidVariableName(_ name: String) -> Bool {
    switch identifierStyle(of: name) {
    case .value, .underscoreOnly:
      return true
    case .type, .invalid:
      return false
    }
  }

  func isValidTypeName(_ name: String) -> Bool {
    identifierStyle(of: name) == .type
  }

  func isValidModuleName(_ name: String) -> Bool {
    guard !name.isEmpty, let first = name.first, isASCIILowercase(first) else {
      return false
    }

    for char in name {
      let isDigit = char >= "0" && char <= "9"
      if isASCIILowercase(char) || isDigit || char == "_" {
        continue
      }
      return false
    }
    return true
  }
}

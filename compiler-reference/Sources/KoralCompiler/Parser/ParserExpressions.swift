// ParserExpressions.swift
// Expression parsing methods for the Koral compiler Parser

/// Extension containing all expression parsing methods
extension Parser {

  private enum ComparisonChainDirection {
    case ascending
    case descending
  }

  private func parseBracketedTypeArguments() throws -> [TypeNode] {
    try match(.leftBracket)
    var typeArgs: [TypeNode] = []
    while currentToken !== .rightBracket {
      typeArgs.append(try parseType())
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightBracket)
    return typeArgs
  }

  private func parseCallArgumentsList() throws -> [CallArg] {
    try match(.leftParen)
    var arguments: [CallArg] = []
    if currentToken !== .rightParen {
      repeat {
        arguments.append(try parseCallArgument())
        if currentToken === .comma {
          try match(.comma)
          if currentToken === .rightParen { break }
        } else {
          break
        }
      } while true
    }
    try match(.rightParen)
    return arguments
  }

  private func calleeAllowsConstructorArgumentSyntax(_ callee: ExpressionNode) -> Bool {
    switch callee {
    case .identifier(let name, _):
      return isValidTypeName(name)
    case .genericInstantiation(let base, _, _):
      return isValidTypeName(base)
    case .memberPath(_, let path, _):
        return memberPathAllowsConstructorArgumentSyntax(path)
    default:
      return false
    }
  }

    private func memberPathAllowsConstructorArgumentSyntax(_ path: [String]) -> Bool {
      path.last.map(isValidTypeName) ?? false
    }

  private func rejectNonConstructorCallSyntax(arguments: [CallArg], span: SourceSpan) throws {
    if arguments.contains(where: { $0.isDefaultFill }) {
      throw ParserError.unexpectedToken(
        span: span,
        got: "Default-fill '...' is not supported; use named parameter defaults instead"
      )
    }
    // Named labels are now allowed for all calls (functions, methods, constructors)
  }

  // MARK: - Bounded shape classification
  //
  // Parsing ambiguity is decided by SHAPE, not by "try to parse, fall back and
  // re-parse". A trial parse has to save and restore the lexer, has to invent a
  // failure path per alternative, and the branch that fails swallows the
  // diagnostic the real parse would have produced. These predicates only look
  // at a BOUNDED run of tokens: they build no tree and report nothing. The
  // stream is restored either way -- that is how a streaming lexer gets
  // lookahead -- and the caller then parses the alternative for real.
  //
  // The shapes mirror `parseType` exactly: type prefixes (`?`, `*unsafe`
  // [`mutable`]) plus a type head (`Self`, an upper-first identifier, or
  // `Func(...)` followed by its return type), with an optional
  // `[` `<type-list>` `]` after the head. Bare `*` is NOT a type start: `f(*p)`
  // dereferences, it does not cast.

  /// Non-throwing advance, for the shape scanner only: classification must not
  /// fail on a lexer error, it just runs out of tokens and says "no".
  private func advanceShape() {
    if let next = try? lexer.getNextToken() {
      currentToken = next
    } else {
      currentToken = .eof
    }
  }

  /// Whether a type starts at the cursor.
  private func shapeStartsType() -> Bool {
    switch currentToken {
    case .questionMark, .selfTypeKeyword:
      return true
    case .multiply:
      return lexer.peekNextToken() === .unsafeKeyword
    case .identifier(let name):
      return isValidTypeName(name)
    default:
      return false
    }
  }

  /// Whether the run at the cursor is exactly one type. Restores the stream.
  @discardableResult
  private func scanTypeShape() -> Bool {
    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }
    return scanTypeShapeConsuming()
  }

  /// The same scan, leaving the cursor just past the type it saw. Returns
  /// false (without promising anything about the cursor) when the run is not
  /// a type -- the caller only reaches this after `scanTypeShape` said yes.
  private func scanTypeShapeConsuming() -> Bool {
    // Prefixes: `?T`, `*unsafe T`, `*unsafe mutable T`. They nest.
    var morePrefixes = true
    while morePrefixes {
      switch currentToken {
      case .questionMark:
        advanceShape()
      case .multiply where lexer.peekNextToken() === .unsafeKeyword:
        advanceShape()
        advanceShape()
        if currentToken === .mutableKeyword { advanceShape() }
      default:
        morePrefixes = false
      }
    }

    switch currentToken {
    case .selfTypeKeyword:
      advanceShape()
      return true
    case .identifier(let name):
      advanceShape()
      if name == "Func", currentToken === .leftParen {
        guard scanTypeParamListConsuming() else { return false }
        return scanTypeShapeConsuming()
      }
      guard isValidTypeName(name) else { return false }
      if currentToken === .leftBracket {
        return scanTypeArgListConsuming()
      }
      return true
    default:
      return false
    }
  }

  /// Whether `[` `<type-list>` `]` starts at the cursor. Restores the stream.
  private func scanTypeArgList() -> Bool {
    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }
    return scanTypeArgListConsuming()
  }

  private func scanTypeArgListConsuming() -> Bool {
    guard currentToken === .leftBracket else { return false }
    advanceShape()
    if currentToken === .rightBracket {
      advanceShape()
      return true
    }
    while true {
      guard scanTypeShapeConsuming() else { return false }
      switch currentToken {
      case .comma:
        advanceShape()
        // A trailing comma is allowed: `[A, B,]`.
        if currentToken === .rightBracket {
          advanceShape()
          return true
        }
      case .rightBracket:
        advanceShape()
        return true
      default:
        return false
      }
    }
  }

  private func scanTypeParamListConsuming() -> Bool {
    guard currentToken === .leftParen else { return false }
    advanceShape()
    if currentToken === .rightParen {
      advanceShape()
      return true
    }
    while true {
      guard scanTypeShapeConsuming() else { return false }
      switch currentToken {
      case .comma:
        advanceShape()
        if currentToken === .rightParen {
          advanceShape()
          return true
        }
      case .rightParen:
        advanceShape()
        return true
      default:
        return false
      }
    }
  }

  /// Whether `( <type> )` starts at the cursor -- the shape of both a postfix
  /// cast `expr(Type)` and a Rust-style qualified path `Type(Trait)`. Which of
  /// the two it is depends on the base, not on these tokens. Restores the
  /// stream.
  private func scanParenTypeSuffix() -> Bool {
    guard currentToken === .leftParen else { return false }
    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }
    advanceShape()
    guard scanTypeShapeConsuming() else { return false }
    guard currentToken === .rightParen else { return false }
    return true
  }

  /// Whether `->`, or `<type> ->`, follows a lambda's parameter list.
  /// Restores the stream.
  private func lambdaReturnClauseFollows() -> Bool {
    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }
    if currentToken === .arrow { return true }
    guard scanTypeShapeConsuming() else { return false }
    return currentToken === .arrow
  }

  /// Whether the `(` at the cursor opens a lambda.
  ///
  /// SHAPE, not a trial parse: a lambda is `(params) [Type] -> ...`, so the
  /// tell is a `->` immediately after the parameter list's `)`, or after an
  /// optional return type written there. Nothing is built and nothing is
  /// rolled back. This replaces a full trial parse of the parameters and body
  /// that needed anti-backtracking patches -- it re-threw `rejectedConstruct`
  /// and typed parameters "instead of backtracking into a worse diagnostic" --
  /// which was the trial design telling on itself.
  private func shapeIsLambda() -> Bool {
    guard currentToken === .leftParen else { return false }
    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }
    advanceShape() // `(`
    if currentToken === .rightParen {
      advanceShape()
      return lambdaReturnClauseFollows()
    }
    // Non-empty parameters: the first token is a parameter name.
    guard case .identifier = currentToken else { return false }
    while true {
      guard case .identifier = currentToken else { return false }
      advanceShape()
      // A parameter is `name [Type]`. `name: Type` is a MISTAKEN lambda
      // parameter, and still a lambda: the real parse reports
      // `Lambda parameters use 'name Type', not 'name: Type'`. A classifier
      // that refused it would re-read the construct as a parenthesized
      // expression and blame the `->` instead.
      if currentToken === .colon {
        advanceShape()
        guard scanTypeShapeConsuming() else { return false }
      } else if currentToken !== .comma && currentToken !== .rightParen {
        guard scanTypeShapeConsuming() else { return false }
      }
      if currentToken === .comma {
        advanceShape()
      } else {
        break
      }
    }
    guard currentToken === .rightParen else { return false }
    advanceShape()
    return lambdaReturnClauseFollows()
  }

  /// `m[T](...)` after a `.member`: `[` `<type-list>` `]` `(` is a generic
  /// method call; the same without the `(` is type arguments written on a
  /// method that takes none. Restores the stream. `nil` when the cursor is not
  /// on a bracketed type list at all.
  private func methodTypeArgumentsShape() -> Bool? {
    guard currentToken === .leftBracket else { return nil }
    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }
    guard scanTypeArgListConsuming() else { return nil }
    return currentToken === .leftParen
  }

  /// The left-hand type of a Rust-style qualified path `Type(Trait)`, or nil
  /// when `expr` is not a (possibly generic) type name.
  private func qualifiedPathBaseType(of expr: ExpressionNode) -> TypeNode? {
    switch expr {
    case .identifier(let name, let span):
      return isValidTypeName(name) ? .identifier(name, span: span) : nil
    case .genericInstantiation(let name, let typeArgs, let span):
      return .generic(base: name, args: typeArgs, span: span)
    default:
      return nil
    }
  }

  /// Parses the `(Trait[Args])` qualification of `Type(Trait).method(...)`.
  /// The SHAPE has already been decided by `scanParenTypeSuffix` -- this only
  /// builds the node, so there is nothing to roll back.
  private func parseQualifiedTraitRef() throws -> TypeNode {
    try match(.leftParen)
    let trait = try parseType()
    guard currentToken === .rightParen else {
      throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
    }
    try match(.rightParen)
    return trait
  }

  /// A postfix cast `expr(Type)`. The SHAPE has already been decided by
  /// `scanParenTypeSuffix` -- this only builds the node.
  private func parsePostfixCastSuffix(base: ExpressionNode) throws -> ExpressionNode {
    try match(.leftParen)
    let targetType = try parseType()
    guard currentToken === .rightParen else {
      throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
    }
    try match(.rightParen)
    return .castExpression(type: targetType, expression: base, span: SourceSpan(start: base.span.start, end: currentSpan.end))
  }

  /// A postfix generic application `Name[Types]`. The SHAPE has already been
  /// decided by `scanTypeArgList` -- this only builds the node.
  private func parsePostfixGenericApplication(name: String, base: ExpressionNode) throws -> ExpressionNode {
    let typeArgs = try parseTypeListInBrackets()
    return .genericInstantiation(base: name, args: typeArgs, span: SourceSpan(start: base.span.start, end: currentSpan.end))
  }
  
  // MARK: - Expression Entry Point

  /// Parse expression rule - main entry point for expression parsing
  func expression() throws -> ExpressionNode {
    let operand = try parseLogicalNotExpression()
    return try parseLayeredTail(operand)
  }

  // MARK: - Flow layer / logical layer
  //
  // `and then` / `or else` / `or return` are ONE layer -- value flow -- and
  // `and` / `or` are another -- boolean logic. Precedence inside a layer is
  // unchanged: `and then` binds tighter than `or else` / `or return`, and
  // `and` binds tighter than `or`. The layers do not mix implicitly.
  // Crossing from one to the other takes parentheses, the way `??` refuses to
  // sit beside `||` in the languages that have it:
  //
  //   `a and (b or else c)`            -- fine, and means that
  //   `(a and b) or else c`            -- fine, and means something else
  //   `a and b or else c`              -- refused: it means neither
  //   `opt and then it == 1 and false` -- refused
  //
  // So the operand is parsed first, and the operator that follows it decides
  // which chain continues. Both chains stop at the other layer's operators and
  // refuse them there instead of guessing a grouping.

  /// Continue `operand` in whichever layer its next operator belongs to.
  private func parseLayeredTail(_ operand: ExpressionNode) throws -> ExpressionNode {
    if startsFlowChain {
      let flowed = try parseFlowTail(operand)
      return try rejectLogicalAtFlowLayer(flowed)
    }
    if startsLogicalChain {
      let logical = try parseLogicalTail(operand)
      return try rejectFlowAtLogicalLayer(logical)
    }
    return operand
  }

  /// Whether the operator at the cursor is a flow operator.
  private var startsFlowChain: Bool {
    switch currentToken {
    case .andKeyword: return lexer.peekNextToken() === .thenKeyword
    case .orKeyword:
      return lexer.peekNextToken() === .elseKeyword || lexer.peekNextToken() === .returnKeyword
    default: return false
    }
  }

  /// Whether the operator at the cursor is a logical operator.
  private var startsLogicalChain: Bool {
    switch currentToken {
    case .andKeyword: return lexer.peekNextToken() !== .thenKeyword
    case .orKeyword:
      return lexer.peekNextToken() !== .elseKeyword && lexer.peekNextToken() !== .returnKeyword
    default: return false
    }
  }

  /// `and then` binds tightest of the flow operators.
  private func parseAndThenChain(_ operand: ExpressionNode) throws -> ExpressionNode {
    var left = operand

    while currentToken === .andKeyword && lexer.peekNextToken() === .thenKeyword {
      try match(.andKeyword)
      try match(.thenKeyword)
      let transformExpr = try parseLogicalNotExpression()
      left = .andThenExpression(operand: left, transformExpr: transformExpr,
                                span: SourceSpan(start: left.span.start, end: transformExpr.span.end))
    }
    return left
  }

  /// `or else` / `or return` sit between `and then` and the end of the layer:
  /// `f() and then g(it) or else h()` groups as `(f() and then g(it)) or else h()`.
  private func parseFlowTail(_ operand: ExpressionNode) throws -> ExpressionNode {
    var left = try parseAndThenChain(operand)

    while currentToken === .orKeyword {
      if lexer.peekNextToken() === .elseKeyword {
        try match(.orKeyword)
        try match(.elseKeyword)
        let rhsOperand = try parseLogicalNotExpression()
        let defaultExpr = try parseAndThenChain(rhsOperand)
        left = .orElseExpression(operand: left, defaultExpr: defaultExpr,
                                span: SourceSpan(start: left.span.start, end: defaultExpr.span.end))
        continue
      }

      if lexer.peekNextToken() === .returnKeyword {
        let orSpan = currentSpan
        try match(.orKeyword)
        try match(.returnKeyword)
        left = .orReturnExpression(operand: left, span: SourceSpan(start: left.span.start, end: orSpan.end))
        continue
      }

      break
    }

    return left
  }

  private func parseLogicalAndChain(_ operand: ExpressionNode) throws -> ExpressionNode {
    var left = operand

    while currentToken === .andKeyword && lexer.peekNextToken() !== .thenKeyword {
      try match(.andKeyword)
      let right = try parseLogicalNotExpression()
      left = .andExpression(left: left, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }

  private func parseLogicalTail(_ operand: ExpressionNode) throws -> ExpressionNode {
    var left = try parseLogicalAndChain(operand)

    while currentToken === .orKeyword
      && lexer.peekNextToken() !== .elseKeyword
      && lexer.peekNextToken() !== .returnKeyword
    {
      try match(.orKeyword)
      let right = try parseLogicalAndChain(try parseLogicalNotExpression())
      left = .orExpression(left: left, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }

  /// A logical operator arriving after a flow chain. The span is the operator
  /// itself, so the caret sits on the token to parenthesize around.
  private func rejectLogicalAtFlowLayer(_ expr: ExpressionNode) throws -> ExpressionNode {
    if currentToken === .andKeyword && lexer.peekNextToken() !== .thenKeyword {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "'and' cannot be mixed with the flow operators 'and then' / 'or else' / 'or return' without parentheses"
      )
    }
    if currentToken === .orKeyword
      && lexer.peekNextToken() !== .elseKeyword
      && lexer.peekNextToken() !== .returnKeyword
    {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "'or' cannot be mixed with the flow operators 'and then' / 'or else' / 'or return' without parentheses"
      )
    }
    return expr
  }

  /// A flow operator arriving after a logical chain.
  private func rejectFlowAtLogicalLayer(_ expr: ExpressionNode) throws -> ExpressionNode {
    if currentToken === .andKeyword && lexer.peekNextToken() === .thenKeyword {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "'and then' cannot be mixed with logical 'and' / 'or' without parentheses"
      )
    }
    if currentToken === .orKeyword && lexer.peekNextToken() === .elseKeyword {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "'or else' cannot be mixed with logical 'and' / 'or' without parentheses"
      )
    }
    if currentToken === .orKeyword && lexer.peekNextToken() === .returnKeyword {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "'or return' cannot be mixed with logical 'and' / 'or' without parentheses"
      )
    }
    return expr
  }


  private func parseLogicalNotExpression() throws -> ExpressionNode {
    if currentToken === .notKeyword {
      let startSpan = currentSpan
      try match(.notKeyword)
      let expr = try parseIsExpression()
      return .notExpression(expr, span: SourceSpan(start: startSpan.start, end: expr.span.end))
    }
    return try parseIsExpression()
  }

  // MARK: - Is / Is Not Expressions

  /// Parse `is`/`is not` expression layer.
  /// Precedence: not > is/is not > range
  /// Parses `expr is pattern` as `isExpression` and `expr is not pattern` as `isNotExpression`.
  private func parseIsExpression() throws -> ExpressionNode {
    let left = try parseRangeExpression()

    if currentToken === .isKeyword {
      try match(.isKeyword)

      // Check for `is not`
      if currentToken === .notKeyword {
        try match(.notKeyword)
          let pattern = try parseSinglePattern()
        return .isNotExpression(subject: left, pattern: pattern,
                                span: SourceSpan(start: left.span.start, end: pattern.span.end))
      }

      let pattern = try parseSinglePattern()
      return .isExpression(subject: left, pattern: pattern,
                           span: SourceSpan(start: left.span.start, end: pattern.span.end))
    }

    return left
  }

  // MARK: - Bitwise Expressions
  
  private func parseBitwiseOrExpression() throws -> ExpressionNode {
    var left = try parseBitwiseXorExpression()
    while currentToken === .pipe {
      try match(.pipe)
      let right = try parseBitwiseXorExpression()
      left = .bitwiseExpression(left: left, operator: .or, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }

  private func parseBitwiseXorExpression() throws -> ExpressionNode {
    var left = try parseBitwiseAndExpression()
    while currentToken === .caret {
      try match(.caret)
      let right = try parseBitwiseAndExpression()
      left = .bitwiseExpression(left: left, operator: .xor, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }

  private func parseBitwiseAndExpression() throws -> ExpressionNode {
    var left = try parseShiftExpression()
    while currentToken === .ampersand {
      try match(.ampersand)
      let right = try parseShiftExpression()
      left = .bitwiseExpression(left: left, operator: .and, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }
  
  // MARK: - Range Expressions
  
  /// Range expressions: a..b, a..<b, a<..b, a<..<b, a.., a<.., ..b, ..<b, ..
  private func parseRangeExpression() throws -> ExpressionNode {
    // Handle prefix range operators: ..b, ..<b, ..
    if currentToken === .range {
      let opSpan = currentSpan
      try match(.range)
      if canStartRangeBound() {
        let right = try parseComparisonExpression()
        return .rangeExpression(operator: .to, left: nil, right: right,
                                span: SourceSpan(start: opSpan.start, end: right.span.end))
      }
      return .rangeExpression(operator: .full, left: nil, right: nil,
                              span: SourceSpan(start: opSpan.start, end: opSpan.end))
    }
    if currentToken === .rangeLess {
      let opSpan = currentSpan
      try match(.rangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .toOpen, left: nil, right: right,
                              span: SourceSpan(start: opSpan.start, end: right.span.end))
    }
    
    let left = try parseComparisonExpression()
    
    // Handle infix and postfix range operators
    switch currentToken {
    case .range:  // ..
      try match(.range)
      if canStartRangeBound() {
        let right = try parseComparisonExpression()
        return .rangeExpression(operator: .closed, left: left, right: right,
                                span: SourceSpan(start: left.span.start, end: right.span.end))
      }
      return .rangeExpression(operator: .from, left: left, right: nil,
                              span: SourceSpan(start: left.span.start, end: currentSpan.end))
    case .rangeLess:  // ..<
      try match(.rangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .closedOpen, left: left, right: right,
                              span: SourceSpan(start: left.span.start, end: right.span.end))
    case .lessRange:  // <..
      try match(.lessRange)
      if canStartRangeBound() {
        let right = try parseComparisonExpression()
        return .rangeExpression(operator: .openClosed, left: left, right: right,
                                span: SourceSpan(start: left.span.start, end: right.span.end))
      }
      return .rangeExpression(operator: .fromOpen, left: left, right: nil,
                              span: SourceSpan(start: left.span.start, end: currentSpan.end))
    case .lessRangeLess:  // <..<
      try match(.lessRangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .open, left: left, right: right,
                              span: SourceSpan(start: left.span.start, end: right.span.end))
    default:
      return left
    }
  }

  
  // MARK: - Comparison Expressions

  private func isEqualityComparisonToken(_ token: Token) -> Bool {
    token === .equalEqual || token === .notEqual
  }

  private func isOrderingComparisonToken(_ token: Token) -> Bool {
    token === .greater || token === .less || token === .greaterEqual || token === .lessEqual
  }

  private func isComparisonToken(_ token: Token) -> Bool {
    isEqualityComparisonToken(token) || isOrderingComparisonToken(token)
  }

  private func comparisonChainDirection(for token: Token) -> ComparisonChainDirection? {
    switch token {
    case .less, .lessEqual:
      return .ascending
    case .greater, .greaterEqual:
      return .descending
    default:
      return nil
    }
  }

  private func comparisonChainError(at span: SourceSpan) -> ParserError {
    ParserError.invalidComparisonChain(
      span: span,
      message: "Comparison chains only support same-direction ordering operators (<, <=) or (>, >=). Use 'and' to combine other comparisons explicitly."
    )
  }
  
  /// Fourth level: Comparisons
  private func parseComparisonExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    let left = try parseBitwiseOrExpression()

    guard isComparisonToken(currentToken) else {
      return left
    }

    if isEqualityComparisonToken(currentToken) {
      let op = currentToken
      try match(op)
      let right = try parseBitwiseOrExpression()
      if isComparisonToken(currentToken) {
        throw comparisonChainError(at: currentSpan)
      }
      return .comparisonExpression(
        left: left,
        operator: tokenToComparisonOperator(op),
        right: right,
        span: SourceSpan(start: left.span.start, end: right.span.end)
      )
    }

    let firstToken = currentToken
    let firstDirection = comparisonChainDirection(for: firstToken)
    try match(firstToken)
    let firstRight = try parseBitwiseOrExpression()

    guard let direction = firstDirection else {
      return .comparisonExpression(
        left: left,
        operator: tokenToComparisonOperator(firstToken),
        right: firstRight,
        span: SourceSpan(start: left.span.start, end: firstRight.span.end)
      )
    }

    var operands: [ExpressionNode] = [left, firstRight]
    var operators: [ComparisonOperator] = [tokenToComparisonOperator(firstToken)]

    while isComparisonToken(currentToken) {
      guard isOrderingComparisonToken(currentToken), comparisonChainDirection(for: currentToken) == direction else {
        throw comparisonChainError(at: currentSpan)
      }

      let op = currentToken
      try match(op)
      let right = try parseBitwiseOrExpression()
      operands.append(right)
      operators.append(tokenToComparisonOperator(op))
    }

    if operators.count == 1 {
      return .comparisonExpression(
        left: left,
        operator: operators[0],
        right: firstRight,
        span: SourceSpan(start: left.span.start, end: firstRight.span.end)
      )
    }

    return .comparisonChainExpression(operands: operands, operators: operators, span: startSpan)
  }

  private func parseShiftExpression() throws -> ExpressionNode {
    var left = try parseAdditiveExpression()
    while currentToken === .leftShift || currentToken === .rightShift {
      let op = currentToken
      try match(op)
      let right = try parseAdditiveExpression()
      let bitOp: BitwiseOperator = (op === .leftShift) ? .shiftLeft : .shiftRight
      left = .bitwiseExpression(left: left, operator: bitOp, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }
  
  // MARK: - Arithmetic Expressions
  
  /// Fifth level: Addition and subtraction
  private func parseAdditiveExpression() throws -> ExpressionNode {
    var left = try parseMultiplicativeExpression()

    while currentToken === .plus || currentToken === .minus {
      let op = currentToken
      try match(op)
      let right = try parseMultiplicativeExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right,
        span: SourceSpan(start: left.span.start, end: right.span.end)
      )
    }
    return left
  }

  /// Sixth level: Multiplication, division, and remainder
  private func parseMultiplicativeExpression() throws -> ExpressionNode {
    var left = try parsePrefixExpression()

    while currentToken === .multiply || currentToken === .divide || currentToken === .remainder {
      let op = currentToken
      try match(op)
      let right = try parsePrefixExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right,
        span: SourceSpan(start: left.span.start, end: right.span.end)
      )
    }
    return left
  }

  
  // MARK: - Prefix Expressions
  
  private func parsePrefixExpression() throws -> ExpressionNode {
    if currentToken === .ifKeyword {
      return try ifExpression()
    }
    if currentToken === .whileKeyword {
      return try whileExpression()
    }
    if currentToken === .whenKeyword {
      return try whenExpression()
    }
    if currentToken === .forKeyword {
      return try forExpression()
    }
    if currentToken === .minus {
      // The literal's span covers the leading minus as well.
      let startSpan = currentSpan
      try match(.minus)
      switch currentToken {
      case .integer(let num):
        try match(.integer(num))
        return .integerLiteral("-\(num)", span: startSpan)
      case .float(let num):
        try match(.float(num))
        return .floatLiteral("-\(num)", span: startSpan)
      default:
        let expr = try parsePrefixExpression()
        return .unaryMinusExpression(expr, span: SourceSpan(start: startSpan.start, end: expr.span.end))
      }
    }
    if currentToken === .tilde {
      let startSpan = currentSpan
      try match(.tilde)
      let expr = try parsePrefixExpression()
      return .bitwiseNotExpression(expr, span: SourceSpan(start: startSpan.start, end: expr.span.end))
    }
    if currentToken === .ampersand {
      // Anchored at the `&`, which is where the unsafe reference starts -- the
      // construct a `cannot take &unsafe of ...` diagnostic is about.
      let ampersandSpan = currentSpan
      try match(.ampersand)
      guard currentToken === .unsafeKeyword else {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: currentToken.description,
          expected: "managed '&' and '&mutable' are removed; use '&unsafe' or '&unsafe mutable'"
        )
      }
      try match(.unsafeKeyword)
      let mutable = currentToken === .mutableKeyword
      if mutable {
        try match(.mutableKeyword)
      }
      let expr = try parsePrefixExpression()
      return .ptrExpression(expr, mutable: mutable, span: ampersandSpan)
    }
    if currentToken === .multiply {
      let startSpan = currentSpan
      try match(.multiply)
      let expr = try parsePrefixExpression()
      return .derefExpression(expr, span: SourceSpan(start: startSpan.start, end: expr.span.end))
    }
    return try parsePostfixExpression()
  }

  // MARK: - Postfix Expressions
  
  private func parsePostfixExpression() throws -> ExpressionNode {
    var expr = try term()
    while true {
      if currentToken === .dot {
        try match(.dot)
        
        guard case .identifier(let member) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description, context: "member access")
        }
        try match(.identifier(member))

        // One shape scan answers both: `[` `<type-list>` `]` `(` is a generic
        // method call; the same without the `(` is type arguments on a method
        // that takes none (a diagnostic). Nothing is tried and rolled back.
        let typeArgsShape = methodTypeArgumentsShape()
        let bareMethodTypeArgs = typeArgsShape == false
        let methodTypeArgs: [TypeNode] = typeArgsShape == true ? try parseBracketedTypeArguments() : []

        if case .traitQualificationExpression(let qualifiedType, let traitType, _) = expr {
          guard currentToken === .leftParen else {
            throw ParserError.unexpectedToken(
              span: currentSpan,
              got: currentToken.description,
              expected: "("
            )
          }
          let arguments = try parseCallArgumentsList()
          try rejectNonConstructorCallSyntax(arguments: arguments, span: expr.span)
          if methodTypeArgs.isEmpty {
            expr = .qualifiedMethodCall(
              type: qualifiedType,
              trait: traitType,
              methodName: member,
              arguments: arguments,
              span: SourceSpan(start: expr.span.start, end: currentSpan.end)
            )
          } else {
            expr = .qualifiedGenericMethodCall(
              type: qualifiedType,
              trait: traitType,
              methodTypeArgs: methodTypeArgs,
              methodName: member,
              arguments: arguments,
              span: SourceSpan(start: expr.span.start, end: currentSpan.end)
            )
          }
          continue
        }
        
        // Check if this is a static method call: TypeName.methodName(...)
        // TypeName starts with uppercase, methodName starts with lowercase
        if isValidTypeName(member) == false {
          // member is lowercase - could be a method or field
          // Check if base is a type identifier (uppercase) - this would be a static method call
          if case .identifier(let baseName, _) = expr, isValidTypeName(baseName) {
            // This is TypeName.methodName - check for call
            if currentToken === .leftParen {
              let arguments = try parseCallArgumentsList()
              try rejectNonConstructorCallSyntax(arguments: arguments, span: expr.span)
              if methodTypeArgs.isEmpty {
                expr = .staticMethodCall(typeName: baseName, typeArgs: [], methodName: member, arguments: arguments, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
              } else {
                expr = .genericMethodCall(base: expr, methodTypeArgs: methodTypeArgs, methodName: member, arguments: arguments, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
              }
              continue
            }
          }
          // Check if base is a generic instantiation: TypeName[T].methodName(...)
          if case .genericInstantiation(let baseName, let typeArgs, _) = expr {
            if currentToken === .leftParen {
              let arguments = try parseCallArgumentsList()
              try rejectNonConstructorCallSyntax(arguments: arguments, span: expr.span)
              if methodTypeArgs.isEmpty {
                expr = .staticMethodCall(typeName: baseName, typeArgs: typeArgs, methodName: member, arguments: arguments, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
              } else {
                expr = .genericMethodCall(base: expr, methodTypeArgs: methodTypeArgs, methodName: member, arguments: arguments, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
              }
              continue
            }
          }

          if !methodTypeArgs.isEmpty, currentToken === .leftParen {
            let arguments = try parseCallArgumentsList()
            try rejectNonConstructorCallSyntax(arguments: arguments, span: expr.span)
            expr = .genericMethodCall(base: expr, methodTypeArgs: methodTypeArgs, methodName: member, arguments: arguments, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
            continue
          }

          if !methodTypeArgs.isEmpty {
            throw ParserError.unexpectedToken(
              span: currentSpan,
              got: currentToken.description,
              expected: "("
            )
          }
        } else if !methodTypeArgs.isEmpty {
          throw ParserError.unexpectedToken(
            span: currentSpan,
            got: currentToken.description,
            expected: "("
          )
        }

        if !methodTypeArgs.isEmpty {
          if currentToken === .leftParen {
            let arguments = try parseCallArgumentsList()
            try rejectNonConstructorCallSyntax(arguments: arguments, span: expr.span)
            expr = .genericMethodCall(base: expr, methodTypeArgs: methodTypeArgs, methodName: member, arguments: arguments, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
              continue
          }
        }

        if bareMethodTypeArgs {
          throw ParserError.unexpectedToken(
            span: currentSpan,
            got: currentToken.description,
            expected: "'(' after generic method name"
          )
        }
        
        // Regular member path
        if case .memberPath(let base, let path, let pathSpan) = expr {
          expr = .memberPath(base: base, path: path + [member], span: SourceSpan(start: pathSpan.start, end: currentSpan.end))
        } else {
          expr = .memberPath(base: expr, path: [member], span: SourceSpan(start: expr.span.start, end: currentSpan.end))
        }
      } else if currentToken === .leftParen {
        // One bounded shape scan decides what `(` opens. `( <type> )` is a
        // Rust-style qualified path `Type(Trait)` when the base is a type name,
        // and a postfix cast `expr(Type)` otherwise; anything else is an
        // ordinary call. Trying each in turn and rolling back is what made a
        // failed branch swallow the diagnostic the real parse would give.
        let isTypeSuffix = scanParenTypeSuffix()
        if isTypeSuffix, let qualifiedType = qualifiedPathBaseType(of: expr) {
          let traitRef = try parseQualifiedTraitRef()
          expr = .traitQualificationExpression(type: qualifiedType, trait: traitRef, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
        } else if isTypeSuffix {
          expr = try parsePostfixCastSuffix(base: expr)
        } else {
          expr = try parseCall(expr)
        }
      } else if currentToken === .leftBracket {
        // `[` `<type-list>` `]` is a generic application; anything else is a
        // subscript. One bounded scan decides -- no trial parse, no rollback.
        if case .identifier(let name, _) = expr, scanTypeArgList() {
          expr = try parsePostfixGenericApplication(name: name, base: expr)
        } else {
          try match(.leftBracket)
          var args: [ExpressionNode] = []
          if currentToken !== .rightBracket {
            repeat {
              args.append(try expression())
              if currentToken === .comma {
                try match(.comma)
              } else {
                break
              }
            } while true
          }
          try match(.rightBracket)
          expr = .subscriptExpression(base: expr, arguments: args, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
        }
      } else {
        break
      }
    }
    return expr
  }

  
  // MARK: - Call Expression

  /// Parse a single call argument, which may be a named argument (label: expr) or positional (expr).
  private func parseCallArgument() throws -> CallArg {
    if currentToken === .ellipsis {
      // `...` is a removed language feature, so it is rejected HERE, at the
      // token, as syntax. Letting it through to the type checker moved the
      // complaint to whatever call the argument belonged to and relabelled it
      // a semantic error; the reader was pointed at a callee instead of at the
      // `...` they have to delete.
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "Default-fill '...' is not supported; use named parameter defaults instead")
    }

    // A bounded two-token shape rule decides named vs positional: a lower-first
    // `ident` immediately followed by `:`. Once that matches, the argument IS
    // labeled -- `ident : …` can never be a positional argument (there is no
    // `:` operator in expressions), so a failure inside it is reported as what
    // it is. This used to restore and re-parse positionally, which always
    // produced the wrong diagnostic: `f(a: (1, 2))` said "unexpected `:`" after
    // re-parsing `a`, instead of the pair-literal error the labeled parse had.
    if let name = currentLabeledArgumentName(allowUnderscore: false) {
      // Anchored at the label: an argument-shape diagnostic is about the
      // `label: value` pair as written, and the label is where it starts.
      let labelSpan = currentSpan
      try match(.identifier(name))
      try match(.colon)
      let expr = try expression()
      return CallArg(label: name, expression: expr, span: labelSpan)
    }
    // Parse as positional argument
    let expr = try expression()
    return CallArg(label: nil, expression: expr, span: expr.span)
  }
  
  private func parseCall(_ callee: ExpressionNode) throws -> ExpressionNode {
    try match(.leftParen)
    var arguments: [CallArg] = []

    if currentToken !== .rightParen {
      repeat {
        arguments.append(try parseCallArgument())
        if currentToken === .comma {
          try match(.comma)
          // Allow trailing comma.
          if currentToken === .rightParen { break }
        } else {
          break
        }
      } while true
    }

    try match(.rightParen)

    if !calleeAllowsConstructorArgumentSyntax(callee) {
      try rejectNonConstructorCallSyntax(arguments: arguments, span: callee.span)
    }

    return .call(callee: callee, arguments: arguments, span: SourceSpan(start: callee.span.start, end: currentSpan.end))
  }
  
  // MARK: - Primary Term
  
  /// Parse term - primary expressions
  private func term() throws -> ExpressionNode {
    // The term's own span: `match` advances past it, so `currentSpan` after the
    // match is the NEXT token.
    let startSpan = currentSpan
    switch currentToken {
    case .identifier(let name):
      try match(.identifier(name))
      return .identifier(name, span: startSpan)
    case .selfKeyword:
      try match(.selfKeyword)
      return .identifier("self", span: startSpan)
    case .integer(let num):
      try match(.integer(num))
      return .integerLiteral(num, span: startSpan)
    case .durationLiteral(let value, let unit):
      try match(.durationLiteral(value: value, unit: unit))
      return try buildDurationLiteralExpression(value: value, unit: unit, span: startSpan)
    case .float(let num):
      try match(.float(num))
      return .floatLiteral(num, span: startSpan)
    case .string(let str):
      try match(.string(str))
      return .stringLiteral(str, span: startSpan)
    case .rune(let str):
      try match(.rune(str))
      return .runeLiteral(str, span: startSpan)
    case .interpolatedString(let parts):
      let span = currentSpan
      try match(.interpolatedString(parts: parts))
      return try parseInterpolatedString(parts, span: span)
    case .bool(let value):
      try match(.bool(value))
      return .booleanLiteral(value, span: startSpan)
    case .itKeyword:
      try match(.itKeyword)
      return .identifier("it", span: startSpan)
    case .leftBrace:
      return try blockExpression()
    case .leftParen:
      // Could be: parenthesized expression (expr) or lambda expression (params) -> body
      return try parseParenOrLambda()
    case .leftBracket:
      return try parseCollectionLiteralExpression()
    case .dot:
      // Implicit member expression: .memberName(args)
      return try parseImplicitMemberExpression()
    default:
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "number, identifier, boolean literal, block expression, or collection literal"
      )
    }
  }

  private func parseCollectionLiteralExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.leftBracket)

    if currentToken === .rightBracket {
      try match(.rightBracket)
      return .emptyLiteral(span: startSpan)
    }

    let first = try expression()

    // Dict literal: [key: value, ...]
    if currentToken === .colon {
      var entries: [(key: ExpressionNode, value: ExpressionNode)] = []
      try match(.colon)
      let firstValue = try expression()
      entries.append((key: first, value: firstValue))

      while currentToken === .comma {
        try match(.comma)

        // Allow trailing comma.
        if currentToken === .rightBracket {
          break
        }

        let keyExpr = try expression()
        guard currentToken === .colon else {
          throw ParserError.unexpectedToken(
            span: currentSpan,
            got: currentToken.description,
            expected: "':' in dict literal entry"
          )
        }
        try match(.colon)
        let valueExpr = try expression()
        entries.append((key: keyExpr, value: valueExpr))
      }

      try match(.rightBracket)
      return .dictLiteral(entries: entries, span: startSpan)
    }

    // Collection literal: [e1, e2, ...]
    var elements: [ExpressionNode] = [first]
    while currentToken === .comma {
      try match(.comma)

      // Allow trailing comma.
      if currentToken === .rightBracket {
        break
      }

      let element = try expression()
      if currentToken === .colon {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: currentToken.description,
          expected: "no ':' in collection literal element"
        )
      }
      elements.append(element)
    }

    try match(.rightBracket)
    return .collectionLiteral(elements: elements, span: startSpan)
  }

  /// Parse implicit member expression: .memberName(args)
  /// This is used for enum case construction or static method calls when the expected type is known.
  private func parseImplicitMemberExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.dot)
    
    // Expect an identifier (member name)
    guard case .identifier(let memberName) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "implicit member name")
    }
    try match(.identifier(memberName))
    
    // Must have parentheses for implicit member expression
    guard currentToken === .leftParen else {
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "'(' after implicit member name"
      )
    }
    
    // Parse arguments
    try match(.leftParen)
    var arguments: [CallArg] = []
    if currentToken !== .rightParen {
      repeat {
        arguments.append(try parseCallArgument())
        if currentToken === .comma {
          try match(.comma)
          // Allow trailing comma.
          if currentToken === .rightParen { break }
        } else {
          break
        }
      } while true
    }
    try match(.rightParen)
    
    return .implicitMemberExpression(
      memberName: memberName,
      arguments: arguments,
      span: startSpan
    )
  }

  private func parseInterpolatedString(
    _ parts: [InterpolatedStringPart],
    span: SourceSpan
  ) throws -> ExpressionNode {
    var resultParts: [InterpolatedPart] = []
    var index = 0
    var containsInterpolation = false

    while index < parts.count {
      switch parts[index] {
      case .stringPart(let value):
        resultParts.append(.literal(value))
        index += 1

      case .interpolationStart(let exprStart):
        containsInterpolation = true
        index += 1
        var exprSource = ""
        while index < parts.count {
          switch parts[index] {
          case .interpolationEnd:
            break
          case .stringPart(let value):
            exprSource.append(value)
            index += 1
            continue
          case .interpolationStart:
            throw ParserError.unexpectedToken(span: span, got: "\\(", expected: "expression")
          }
          break
        }

        if index >= parts.count {
          throw ParserError.unexpectedEndOfFile(span: span)
        }

        if exprSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          throw ParserError.emptyInterpolationExpression(span: span)
        }

        let expr = try parseInterpolatedExpression(exprSource, start: exprStart)
        resultParts.append(.expression(expr))

        if case .interpolationEnd = parts[index] {
          index += 1
        }

      case .interpolationEnd:
        throw ParserError.unexpectedToken(span: span, got: ")", expected: "expression")
      }
    }

    if resultParts.count == 1, !containsInterpolation, case .literal(let str) = resultParts[0] {
      return .stringLiteral(str, span: span)
    }

    return .interpolatedString(parts: resultParts, span: span)
  }

  /// `start` is where `source` begins in the file. Without it the nested lexer
  /// places every token at 1:1 and a diagnostic about the expression points at
  /// the first line of the file.
  private func parseInterpolatedExpression(_ source: String, start: SourceLocation) throws -> ExpressionNode {
    let lexer = Lexer(input: source, start: start)
    let parser = Parser(lexer: lexer)
    parser.currentToken = try parser.lexer.getNextToken()
    let expr = try parser.expression()
    if parser.currentToken !== .eof {
      throw ParserError.unexpectedToken(
        span: parser.currentSpan,
        got: parser.currentToken.description,
        expected: "end of interpolation"
      )
    }
    return expr
  }

  
  // MARK: - Parenthesized Expression or Lambda
  
  /// Parse either a parenthesized expression or a lambda expression.
  /// Lambda syntax:
  ///   () -> expr                    // no params
  ///   (x) -> expr                   // single param, type inferred
  ///   (x, y) -> expr                // multiple params, types inferred
  ///   (x Int) -> expr               // single param with type
  ///   (x Int, y Int) -> expr        // multiple params with types
  ///   (x Int, y Int) Int -> expr    // with return type
  private func parseParenOrLambda() throws -> ExpressionNode {
    let startSpan = currentSpan

    // `(` opens either a lambda or a parenthesized expression. The shape
    // classifier decides BEFORE anything is built -- a lambda is
    // `(params) [Type] -> ...`, so the `->` is the tell -- and then the chosen
    // alternative is parsed for real. There is no trial to roll back and no
    // failed branch to swallow the diagnostic the real parse would produce.
    if shapeIsLambda() {
      return try parseLambdaExpression(startSpan: startSpan)
    }

    try match(.leftParen)
    let first = try expression()
    if currentToken === .comma {
      // There is no tuple/pair literal. A `Pair` is built with its own
      // constructor, like any other type. The blame lands on the `,` -- the
      // token that says "literal" here.
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "A pair literal is not an expression: construct a Pair with 'Pair(first, second)'"
      )
    }
    try match(.rightParen)
    return first
  }

  /// Parses a lambda whose SHAPE `shapeIsLambda` has already confirmed.
  private func parseLambdaExpression(startSpan: SourceSpan) throws -> ExpressionNode {
    try match(.leftParen)

    var parameters: [(name: String, type: TypeNode?)] = []
    if currentToken !== .rightParen {
      while true {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        if !isValidVariableName(paramName) {
          throw ParserError.invalidParameterName(span: currentSpan, name: paramName)
        }
        try match(.identifier(paramName))

        // Lambda parameters are `name Type`, not `name: Type`.
        if currentToken === .colon {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Lambda parameters use 'name Type', not 'name: Type'")
        }

        var paramType: TypeNode? = nil
        if currentToken !== .comma && currentToken !== .rightParen {
          paramType = try parseType()
        }
        parameters.append((name: paramName, type: paramType))

        if currentToken === .comma {
          try match(.comma)
        } else {
          break
        }
      }
    }
    try match(.rightParen)

    var returnType: TypeNode? = nil
    if currentToken !== .arrow {
      returnType = try parseType()
    }
    guard currentToken === .arrow else {
      throw ParserError.expectedArrow(span: currentSpan)
    }
    try match(.arrow)
    let body = try expression()
    return .lambdaExpression(parameters: parameters, returnType: returnType, body: body, span: startSpan)
  }

  private func buildDurationLiteralExpression(
    value: String,
    unit: String,
    span: SourceSpan
  ) throws -> ExpressionNode {
    guard let raw = Int64(value) else {
      throw ParserError.unexpectedToken(
        span: span,
        got: "\(value)\(unit)",
        expected: "duration literal within Int64 range"
      )
    }

    let nanosPerSec: Int64 = 1_000_000_000
    let secs: Int64
    let nanos: Int64

    switch unit {
    case "s":
      secs = raw
      nanos = 0
    case "ms":
      secs = raw / 1_000
      nanos = (raw % 1_000) * 1_000_000
    case "us":
      secs = raw / 1_000_000
      nanos = (raw % 1_000_000) * 1_000
    case "ns":
      secs = raw / nanosPerSec
      nanos = raw % nanosPerSec
    default:
      throw ParserError.unexpectedToken(
        span: span,
        got: "\(value)\(unit)",
        expected: "supported duration suffix (s|ms|us|ns)"
      )
    }

    let ctorCall: ExpressionNode = .staticMethodCall(
      typeName: "Duration",
      typeArgs: [],
      methodName: "new",
      arguments: [
        CallArg(label: "seconds", expression: .integerLiteral(String(secs), span: span)),
        CallArg(label: "nanoseconds", expression: .integerLiteral(String(nanos), span: span))
      ],
      span: span
    )

    return .call(
      callee: .memberPath(base: ctorCall, path: ["unwrap"], span: span),
      arguments: [],
      span: span
    )
  }

  
  // MARK: - Block Expression

  private func blockCompoundAssignmentOperator(_ token: Token) -> CompoundAssignmentOperator? {
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
  
  /// Parse block expression
  private func blockExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.leftBrace)
    var statements: [StatementNode] = []
    var tailExpression: ExpressionNode? = nil

    while currentToken !== .rightBrace {
      if currentToken === .eof {
        throw ParserError.unexpectedEndOfFile(span: currentSpan)
      }

      switch currentToken {
      case .letKeyword, .returnKeyword, .breakKeyword, .continueKeyword, .deferKeyword:
        statements.append(try statement())
        continue
      default:
        break
      }

      let startSpan = currentSpan
      let expr = try expression()

      if currentToken === .equal {
        try match(.equal)
        let value = try expression()
        try requireSemicolon()
        statements.append(.assignment(target: expr, operator: nil, value: value, span: startSpan))
        continue
      }

      if let op = blockCompoundAssignmentOperator(currentToken) {
        try match(currentToken)
        let value = try expression()
        try requireSemicolon()
        statements.append(.assignment(target: expr, operator: op, value: value, span: startSpan))
        continue
      }

      if currentToken === .semicolon {
        try requireSemicolon()
        statements.append(.expression(expr, span: startSpan))
        continue
      }

      tailExpression = expr
      break
    }
    
    try match(.rightBrace)
    return .blockExpression(statements: statements, tailExpression: tailExpression, span: SourceSpan(start: startSpan.start, end: currentSpan.end))
  }
  
  // MARK: - Control Flow Expressions

  private func ifExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.ifKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let thenBranch = try expression()
    var elseBranch: ExpressionNode? = nil
    if currentToken === .elseKeyword {
      try match(.elseKeyword)
      elseBranch = try expression()
    }
    return .ifExpression(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch, span: SourceSpan(start: startSpan.start, end: currentSpan.end))
  }

  private func whileExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.whileKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .whileExpression(condition: condition, body: body, span: SourceSpan(start: startSpan.start, end: currentSpan.end))
  }

  /// Parse for expression: for <pattern> in <iterable> then <body>
  private func forExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.forKeyword)
    let pattern = try parseForBindingPattern()
    try match(.inKeyword)
    let iterable = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .forExpression(pattern: pattern, iterable: iterable, body: body, span: SourceSpan(start: startSpan.start, end: currentSpan.end))
  }

  
  // MARK: - When/Match Expression
  
  private func whenExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.whenKeyword)
    let subject = try expression()
    try match(.inKeyword)
    try match(.leftBrace)
    var cases: [MatchCaseNode] = []
    while currentToken !== .rightBrace {
      let pattern = try parsePattern()
      
      try match(.thenKeyword)

      let body: ExpressionNode
      if currentToken === .leftBrace {
        body = try blockExpression()
      } else {
        body = try expression()
      }

      cases.append(MatchCaseNode(pattern: pattern, body: body))

      // Match arms are separated by commas; a trailing comma before '}' is allowed.
      if currentToken === .comma {
        try match(.comma)
      } else if currentToken !== .rightBrace {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: currentToken.description,
          expected: "',' or '}' after when arm"
        )
      }
    }
    try match(.rightBrace)
    return .whenExpression(subject: subject, cases: cases, span: startSpan)
  }
  
  // MARK: - Operator Conversion Helpers
  
  private func tokenToArithmeticOperator(_ token: Token) -> ArithmeticOperator {
    switch token {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .remainder: return .remainder
    default: fatalError("Invalid arithmetic operator token")
    }
  }

  private func tokenToComparisonOperator(_ token: Token) -> ComparisonOperator {
    switch token {
    case .equalEqual: return .equal
    case .notEqual: return .notEqual
    case .greater: return .greater
    case .less: return .less
    case .greaterEqual: return .greaterEqual
    case .lessEqual: return .lessEqual
    default: fatalError("Invalid comparison operator token")
    }
  }
}

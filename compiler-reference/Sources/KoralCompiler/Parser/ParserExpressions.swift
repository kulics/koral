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

  private func tryParseMethodTypeArguments() throws -> [TypeNode]? {
    guard currentToken === .leftBracket else { return nil }

    let savedLexer = lexer.saveState()
    let savedToken = currentToken

    do {
      let typeArgs = try parseBracketedTypeArguments()
      guard currentToken === .leftParen else {
        lexer.restoreState(savedLexer)
        currentToken = savedToken
        return nil
      }
      return typeArgs
    } catch {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
      return nil
    }
  }

  private func hasBareMethodTypeArguments() -> Bool {
    guard currentToken === .leftBracket else { return false }

    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }

    do {
      _ = try parseBracketedTypeArguments()
      return currentToken !== .leftParen
    } catch {
      return false
    }
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
  /// Returns nil (restoring the parser position) when this is not a trait ref.
  private func tryParseQualifiedTraitRef() throws -> TypeNode? {
    guard currentToken === .leftParen else { return nil }

    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    do {
      try match(.leftParen)
      guard case .identifier(let traitName) = currentToken, isValidTypeName(traitName) else {
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
      }
      let trait = try parseType()
      guard currentToken === .rightParen else {
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
      }
      try match(.rightParen)
      return trait
    } catch {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
      return nil
    }
  }

  private func tryParsePostfixCastSuffix(base: ExpressionNode) throws -> ExpressionNode? {
    guard currentToken === .leftParen else { return nil }

    let savedLexer = lexer.saveState()
    let savedToken = currentToken

    do {
      try match(.leftParen)
      let targetType = try parseType()
      guard currentToken === .rightParen else {
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
      }
      try match(.rightParen)
      return .castExpression(type: targetType, expression: base, span: SourceSpan(start: base.span.start, end: currentSpan.end))
    } catch {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
      return nil
    }
  }

  private func tryParsePostfixGenericApplication(base: ExpressionNode) throws -> ExpressionNode? {
    guard currentToken === .leftBracket else { return nil }

    let savedLexer = lexer.saveState()
    let savedToken = currentToken

    do {
      let typeArgs = try parseTypeListInBrackets()
      switch base {
      case .identifier(let name, _):
        return .genericInstantiation(base: name, args: typeArgs, span: SourceSpan(start: base.span.start, end: currentSpan.end))
      default:
        lexer.restoreState(savedLexer)
        currentToken = savedToken
        return nil
      }
    } catch {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
      return nil
    }
  }
  
  // MARK: - Expression Entry Point
  
  /// Parse expression rule - main entry point for expression parsing
  func expression() throws -> ExpressionNode {
    return try parseOrExpression()
  }
  
  // MARK: - Logical Expressions

  private func parseOrExpression() throws -> ExpressionNode {
    var left = try parseAndExpression()

    while currentToken === .orKeyword {
      try match(.orKeyword)
      let right = try parseAndExpression()
      left = .orExpression(left: left, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }

  /// `or else` / `or return` sit between `and then` and logical `and`:
  /// `f() and then g(it) or else h()` groups as `(f() and then g(it)) or else h()`,
  /// and `a and b or else c` groups as `a and (b or else c)`.
  private func parseOptionFlowExpression() throws -> ExpressionNode {
    var left = try parseAndThenExpression()

    while currentToken === .orKeyword {
      if lexer.peekNextToken() === .elseKeyword {
        try match(.orKeyword)
        try match(.elseKeyword)
        let defaultExpr = try parseAndThenExpression()
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

  private func parseAndExpression() throws -> ExpressionNode {
    var left = try parseOptionFlowExpression()

    while currentToken === .andKeyword {
      if lexer.peekNextToken() === .thenKeyword { break }
      try match(.andKeyword)
      let right = try parseOptionFlowExpression()
      left = .andExpression(left: left, right: right, span: SourceSpan(start: left.span.start, end: right.span.end))
    }
    return left
  }

  private func parseAndThenExpression() throws -> ExpressionNode {
    var left = try parseLogicalNotExpression()

    while currentToken === .andKeyword {
      if lexer.peekNextToken() === .thenKeyword {
        try match(.andKeyword)
        try match(.thenKeyword)
        let transformExpr = try parseLogicalNotExpression()
        left = .andThenExpression(operand: left, transformExpr: transformExpr,
                                  span: SourceSpan(start: left.span.start, end: transformExpr.span.end))
      } else {
        break
      }
    }
    return left
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

        let bareMethodTypeArgs = hasBareMethodTypeArguments()
        let methodTypeArgs = try tryParseMethodTypeArguments() ?? []

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
        // Rust-style qualified path `Type(Trait)`: the base must be a type name
        // and the parenthesized part must be a trait reference.
        if let qualifiedType = qualifiedPathBaseType(of: expr),
           let traitRef = try tryParseQualifiedTraitRef() {
          expr = .traitQualificationExpression(type: qualifiedType, trait: traitRef, span: SourceSpan(start: expr.span.start, end: currentSpan.end))
        } else if let castExpr = try tryParsePostfixCastSuffix(base: expr) {
          expr = castExpr
        } else {
          expr = try parseCall(expr)
        }
      } else if currentToken === .leftBracket {
        if let genericExpr = try tryParsePostfixGenericApplication(base: expr) {
          expr = genericExpr
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

    if let name = currentLabeledArgumentName(allowUnderscore: false) {
      let savedState = lexer.saveState()
      let savedToken = currentToken
      // Anchored at the label: an argument-shape diagnostic is about the
      // `label: value` pair as written, and the label is where it starts.
      let labelSpan = currentSpan
      do {
        try match(.identifier(name))
        try match(.colon)
        let expr = try expression()
        return CallArg(label: name, expression: expr, span: labelSpan)
      } catch {
        lexer.restoreState(savedState)
        currentToken = savedToken
      }
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
    try match(.leftParen)
    
    // Empty parens: () -> must be lambda
    if currentToken === .rightParen {
      try match(.rightParen)
      // Check for optional return type before arrow
      var returnType: TypeNode? = nil
      if currentToken !== .arrow {
        if canStartTypeSyntax() {
          returnType = try parseType()
        }
      }
      if currentToken === .arrow {
        try match(.arrow)
        let body = try expression()
        return .lambdaExpression(parameters: [], returnType: returnType, body: body, span: startSpan)
      } else {
        if returnType != nil {
          throw ParserError.expectedArrow(span: currentSpan)
        }
        // Not a lambda, but () is not a valid expression by itself
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description, expected: "'->'")
      }
    }
    
    // Save state to backtrack if this is not a lambda
    let savedState = lexer.saveState()
    let savedToken = currentToken
    
    // Try to parse as lambda parameters
    var parameters: [(name: String, type: TypeNode?)] = []
    var isLambda = false
    var sawExplicitReturnType = false
    
    do {
      while currentToken !== .rightParen {
        guard case .identifier(let paramName) = currentToken else {
          // Not a valid lambda parameter, restore and parse as expression
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        if !isValidVariableName(paramName) {
          throw ParserError.invalidParameterName(span: currentSpan, name: paramName)
        }
        try match(.identifier(paramName))
        
        // Check for named parameter syntax in lambda - not allowed
        if currentToken === .colon {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Lambda parameters use 'name Type', not 'name: Type'")
        }
        
        // Check for optional type annotation
        var paramType: TypeNode? = nil
        if currentToken !== .comma && currentToken !== .rightParen {
          // Could be a type annotation or an operator (if this is an expression)
          if canStartTypeSyntax() {
            paramType = try parseType()
          } else {
            // Not a type, this might be an expression like (a + b)
            throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
          }
        }
        
        parameters.append((name: paramName, type: paramType))
        
        if currentToken === .comma {
          try match(.comma)
        }
      }
      
      try match(.rightParen)
      
      // Check for optional return type before arrow
      var returnType: TypeNode? = nil
      if currentToken !== .arrow {
        // Could be a return type
        if canStartTypeSyntax() {
          returnType = try parseType()
          sawExplicitReturnType = true
        }
      }
      
      // Must have arrow for lambda
      if currentToken === .arrow {
        isLambda = true
        try match(.arrow)
        let body = try expression()
        return .lambdaExpression(parameters: parameters, returnType: returnType, body: body, span: startSpan)
      }
      
      // No arrow - typed params without arrow is an error; untyped multi-params become Pair
      if parameters.contains(where: { $0.type != nil }) {
        throw ParserError.expectedArrow(span: currentSpan)
      }
      
      // Single untyped param without arrow - restore and parse as expression
      // This handles cases like (a) which could be just a parenthesized identifier
    } catch let error as ParserError {
      // A rejected construct is a definite language violation, not evidence
      // that this was never a lambda: re-reading the same tokens as an
      // expression cannot make the construct legal. Propagate it instead of
      // backtracking into a worse diagnostic.
      if case .rejectedConstruct = error {
        throw error
      }
      if parameters.contains(where: { $0.type != nil }) || sawExplicitReturnType {
        throw error
      }
      // Parsing as lambda failed, restore state
      isLambda = false
    } catch {
      // Parsing as lambda failed, restore state
      isLambda = false
    }
    
    if !isLambda {
      // Restore state and parse as parenthesized expression
      lexer.restoreState(savedState)
      currentToken = savedToken
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
    
    // Should not happen - if lambda parsing succeeded, we would have returned above
    // If it failed, isLambda should be false
    fatalError("Internal error: unreachable state in parenthesized expression parsing")
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

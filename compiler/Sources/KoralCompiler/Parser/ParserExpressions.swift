// ParserExpressions.swift
// Expression parsing methods for the Koral compiler Parser

/// Extension containing all expression parsing methods
extension Parser {
  
  // MARK: - Expression Entry Point
  
  /// Parse expression rule - main entry point for expression parsing
  func expression() throws -> ExpressionNode {
    return try parseOrReturnExpression()
  }
  
  // MARK: - Logical Expressions

  /// or return layer: lowest precedence.
  /// Parses `<expr> or return` as early-return propagation sugar.
  private func parseOrReturnExpression() throws -> ExpressionNode {
    var left = try parseOrElseExpression()

    while currentToken === .orKeyword {
      if isLineContinuationBlocked() { break }
      if lexer.peekNextToken() === .returnKeyword {
        let startSpan = currentSpan
        try match(.orKeyword)
        try match(.returnKeyword)
        left = .orReturnExpression(operand: left, span: startSpan)
      } else {
        break
      }
    }

    return left
  }
  
  /// or else layer: above `or return`, below logical `or`.
  /// Parses `<expr> or else <expr>` as value coalescing / early exit.
  private func parseOrElseExpression() throws -> ExpressionNode {
    var left = try parseOrExpression()

    while currentToken === .orKeyword {
      if isLineContinuationBlocked() { break }
      // Peek: if next token is `else`, this is `or else` syntax
      if lexer.peekNextToken() === .elseKeyword {
        let startSpan = currentSpan
        try match(.orKeyword)
        try match(.elseKeyword)
        let defaultExpr = try parseOrExpression()
        left = .orElseExpression(operand: left, defaultExpr: defaultExpr, span: startSpan)
      } else {
        break  // Not `or else`, let parseOrExpression handle logical `or`
      }
    }
    return left
  }

  private func parseOrExpression() throws -> ExpressionNode {
    var left = try parseAndThenExpression()

    while currentToken === .orKeyword {
      if isLineContinuationBlocked() { break }
      // If next token is `else` / `return`, don't consume — handled by higher layers.
      if lexer.peekNextToken() === .elseKeyword || lexer.peekNextToken() === .returnKeyword {
        break
      }
      try match(.orKeyword)
      let right = try parseAndThenExpression()
      left = .orExpression(left: left, right: right)
    }
    return left
  }

  /// and then layer: between logical or and logical and.
  /// Parses `<expr> and then <expr>` as value transformation / optional chaining.
  private func parseAndThenExpression() throws -> ExpressionNode {
    var left = try parseAndExpression()

    while currentToken === .andKeyword {
      if isLineContinuationBlocked() { break }
      // Peek: if next token is `then`, this is `and then` syntax
      if lexer.peekNextToken() === .thenKeyword {
        let startSpan = currentSpan
        try match(.andKeyword)
        try match(.thenKeyword)
        let transformExpr = try parseAndExpression()
        left = .andThenExpression(operand: left, transformExpr: transformExpr, span: startSpan)
      } else {
        break  // Not `and then`, let parseAndExpression handle logical `and`
      }
    }
    return left
  }

  private func parseAndExpression() throws -> ExpressionNode {
    var left = try parseLogicalNotExpression()

    while currentToken === .andKeyword {
      if isLineContinuationBlocked() { break }
      // If next token is `then`, don't consume — let parseAndThenExpression handle it
      if lexer.peekNextToken() === .thenKeyword { break }
      try match(.andKeyword)
      let right = try parseLogicalNotExpression()
      left = .andExpression(left: left, right: right)
    }
    return left
  }


  private func parseLogicalNotExpression() throws -> ExpressionNode {
    if currentToken === .notKeyword {
      try match(.notKeyword)
      let expr = try parseIsExpression()
      return .notExpression(expr)
    }
    return try parseIsExpression()
  }

  // MARK: - Is / Is Not Expressions

  /// Parse `is`/`is not` expression layer.
  /// Precedence: not > is/is not > bitwise or
  /// Parses `expr is pattern` as `isExpression` and `expr is not pattern` as `isNotExpression`.
  private func parseIsExpression() throws -> ExpressionNode {
    let left = try parseBitwiseOrExpression()

    if currentToken === .isKeyword {
      let startSpan = currentSpan
      try match(.isKeyword)

      // Check for `is not`
      if currentToken === .notKeyword {
        try match(.notKeyword)
        let pattern = try parseSinglePattern()
        return .isNotExpression(subject: left, pattern: pattern, span: startSpan)
      }

      let pattern = try parseSinglePattern()
      return .isExpression(subject: left, pattern: pattern, span: startSpan)
    }

    return left
  }

  // MARK: - Bitwise Expressions
  
  private func parseBitwiseOrExpression() throws -> ExpressionNode {
    var left = try parseBitwiseXorExpression()
    while currentToken === .pipe {
      if isLineContinuationBlocked() { break }
      try match(.pipe)
      let right = try parseBitwiseXorExpression()
      left = .bitwiseExpression(left: left, operator: .or, right: right)
    }
    return left
  }

  private func parseBitwiseXorExpression() throws -> ExpressionNode {
    var left = try parseBitwiseAndExpression()
    while currentToken === .caret {
      if isLineContinuationBlocked() { break }
      try match(.caret)
      let right = try parseBitwiseAndExpression()
      left = .bitwiseExpression(left: left, operator: .xor, right: right)
    }
    return left
  }

  private func parseBitwiseAndExpression() throws -> ExpressionNode {
    var left = try parseRangeExpression()
    while currentToken === .ampersand {
      if isLineContinuationBlocked() { break }
      try match(.ampersand)
      let right = try parseRangeExpression()
      left = .bitwiseExpression(left: left, operator: .and, right: right)
    }
    return left
  }
  
  // MARK: - Range Expressions
  
  /// Range expressions: a..b, a..<b, a<..b, a<..<b, a..., a<..., ...b, ...<b, ....
  private func parseRangeExpression() throws -> ExpressionNode {
    // Handle prefix range operators: ...b, ...<b, ....
    if currentToken === .fullRange {
      try match(.fullRange)
      return .rangeExpression(operator: .full, left: nil, right: nil)
    }
    if currentToken === .unboundedRange {
      try match(.unboundedRange)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .to, left: nil, right: right)
    }
    if currentToken === .unboundedRangeLess {
      try match(.unboundedRangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .toOpen, left: nil, right: right)
    }
    
    let left = try parseComparisonExpression()
    
    // Handle infix and postfix range operators
    if isLineContinuationBlocked() { return left }
    
    switch currentToken {
    case .range:  // ..
      try match(.range)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .closed, left: left, right: right)
    case .rangeLess:  // ..<
      try match(.rangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .closedOpen, left: left, right: right)
    case .lessRange:  // <..
      try match(.lessRange)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .openClosed, left: left, right: right)
    case .lessRangeLess:  // <..<
      try match(.lessRangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .open, left: left, right: right)
    case .unboundedRange:  // ...
      try match(.unboundedRange)
      return .rangeExpression(operator: .from, left: left, right: nil)
    case .lessUnboundedRange:  // <...
      try match(.lessUnboundedRange)
      return .rangeExpression(operator: .fromOpen, left: left, right: nil)
    default:
      return left
    }
  }

  
  // MARK: - Comparison Expressions
  
  /// Fourth level: Comparisons
  private func parseComparisonExpression() throws -> ExpressionNode {
    var left = try parseShiftExpression()

    while currentToken === .equalEqual || currentToken === .notEqual || currentToken === .greater
      || currentToken === .less || currentToken === .greaterEqual || currentToken === .lessEqual
    {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parseShiftExpression()
      left = .comparisonExpression(
        left: left,
        operator: tokenToComparisonOperator(op),
        right: right
      )
    }
    return left
  }

  private func parseShiftExpression() throws -> ExpressionNode {
    var left = try parseAdditiveExpression()
    while currentToken === .leftShift || currentToken === .rightShift {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parseAdditiveExpression()
      let bitOp: BitwiseOperator = (op === .leftShift) ? .shiftLeft : .shiftRight
      left = .bitwiseExpression(left: left, operator: bitOp, right: right)
    }
    return left
  }
  
  // MARK: - Arithmetic Expressions
  
  /// Fifth level: Addition and subtraction
  private func parseAdditiveExpression() throws -> ExpressionNode {
    var left = try parseMultiplicativeExpression()

    while currentToken === .plus || currentToken === .minus {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parseMultiplicativeExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right
      )
    }
    return left
  }

  /// Sixth level: Multiplication, division, and remainder
  private func parseMultiplicativeExpression() throws -> ExpressionNode {
    var left = try parsePrefixExpression()

    while currentToken === .multiply || currentToken === .divide || currentToken === .remainder {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parsePrefixExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right
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
    if let cast = try tryParseCastExpression() {
      return cast
    }
    if currentToken === .minus {
      let _ = currentSpan
      try match(.minus)
      switch currentToken {
      case .integer(let num):
        try match(.integer(num))
        return .integerLiteral("-\(num)")
      case .float(let num):
        try match(.float(num))
        return .floatLiteral("-\(num)")
      default:
        let expr = try parsePrefixExpression()
        return .unaryMinusExpression(expr)
      }
    }
    if currentToken === .refKeyword {
      try match(.refKeyword)
      let expr = try parsePrefixExpression()
      return .refExpression(expr)
    } else if currentToken === .ptrKeyword {
      try match(.ptrKeyword)
      let expr = try parsePrefixExpression()
      return .ptrExpression(expr)
    } else if currentToken === .derefKeyword {
      try match(.derefKeyword)
      let expr = try parsePrefixExpression()
      return .derefExpression(expr)
    } else if currentToken === .tilde {
      try match(.tilde)
      let expr = try parsePrefixExpression()
      return .bitwiseNotExpression(expr)
    }
    return try parsePostfixExpression()
  }

  /// Attempt to parse a C-style cast expression: `(Type)expr`.
  /// Uses lexer state save/restore to disambiguate from parenthesized expressions.
  private func tryParseCastExpression() throws -> ExpressionNode? {
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
      let expr = try parsePrefixExpression()
      return .castExpression(type: targetType, expression: expr)
    } catch {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
      return nil
    }
  }
  
  // MARK: - Postfix Expressions
  
  private func parsePostfixExpression() throws -> ExpressionNode {
    var expr = try term()
    while true {
      // If a newline was crossed and it included blank lines/comments, do not allow continuation.
      if isLineContinuationBlocked() {
        break
      }
      // Check for automatic statement termination before parsing postfix operators
      // If there's a newline before the current token and it's not a continuation token,
      // we should stop parsing postfix expressions
      if lexer.newlineBeforeCurrent && !currentToken.isContinuationToken {
        // Special case: dot is a continuation token, so we continue
        // But [ and ( and { are not continuation tokens, so we stop
        if currentToken === .leftBracket || currentToken === .leftParen || currentToken === .leftBrace {
          break
        }
      }
      
      if currentToken === .dot {
        try match(.dot)

        // Qualified disambiguation call: base.(TraitName)method(...) or base.(TraitName)[T]method(...)
        if currentToken === .leftParen {
          try match(.leftParen)
          guard case .identifier(let traitName) = currentToken else {
            throw ParserError.expectedIdentifier(
              span: currentSpan,
              got: currentToken.description
            )
          }
          try match(.identifier(traitName))
          try match(.rightParen)

          var methodTypeArgs: [TypeNode] = []
          if currentToken === .leftBracket {
            try match(.leftBracket)
            while currentToken !== .rightBracket {
              methodTypeArgs.append(try parseType())
              if currentToken === .comma {
                try match(.comma)
              }
            }
            try match(.rightBracket)
          }

          guard case .identifier(let methodName) = currentToken else {
            throw ParserError.expectedIdentifier(
              span: currentSpan,
              got: currentToken.description
            )
          }
          try match(.identifier(methodName))

          guard currentToken === .leftParen else {
            throw ParserError.unexpectedToken(
              span: currentSpan,
              got: currentToken.description,
              expected: "("
            )
          }

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

          if methodTypeArgs.isEmpty {
            expr = .qualifiedMethodCall(
              base: expr,
              traitName: traitName,
              methodName: methodName,
              arguments: arguments
            )
          } else {
            expr = .qualifiedGenericMethodCall(
              base: expr,
              traitName: traitName,
              methodTypeArgs: methodTypeArgs,
              methodName: methodName,
              arguments: arguments
            )
          }
          continue
        }
        
        // Check for generic method call: obj.[Type]method(args)
        if currentToken === .leftBracket {
          try match(.leftBracket)
          var methodTypeArgs: [TypeNode] = []
          while currentToken !== .rightBracket {
            methodTypeArgs.append(try parseType())
            if currentToken === .comma {
              try match(.comma)
            }
          }
          try match(.rightBracket)
          
          guard case .identifier(let methodName) = currentToken else {
            throw ParserError.expectedIdentifier(
              span: currentSpan, got: currentToken.description)
          }
          try match(.identifier(methodName))
          
          // Must be followed by a call
          guard currentToken === .leftParen else {
            throw ParserError.unexpectedToken(
              span: currentSpan,
              got: currentToken.description,
              expected: "("
            )
          }
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
          expr = .genericMethodCall(base: expr, methodTypeArgs: methodTypeArgs, methodName: methodName, arguments: arguments)
          continue
        }
        
        guard case .identifier(let member) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(member))
        
        // Check if this is a static method call: TypeName.methodName(...)
        // TypeName starts with uppercase, methodName starts with lowercase
        if isValidTypeName(member) == false {
          // member is lowercase - could be a method or field
          // Check if base is a type identifier (uppercase) - this would be a static method call
          if case .identifier(let baseName) = expr, isValidTypeName(baseName) {
            // This is TypeName.methodName - check for call
            if currentToken === .leftParen {
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
              expr = .staticMethodCall(typeName: baseName, typeArgs: [], methodName: member, arguments: arguments)
              continue
            }
          }
          // Check if base is a generic instantiation: [T]TypeName.methodName(...)
          if case .genericInstantiation(let baseName, let typeArgs) = expr {
            if currentToken === .leftParen {
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
              expr = .staticMethodCall(typeName: baseName, typeArgs: typeArgs, methodName: member, arguments: arguments)
              continue
            }
          }
        }
        
        // Regular member path
        if case .memberPath(let base, let path) = expr {
          expr = .memberPath(base: base, path: path + [member])
        } else {
          expr = .memberPath(base: expr, path: [member])
        }
      } else if currentToken === .leftParen {
        expr = try parseCall(expr)
      } else if currentToken === .leftBracket {
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
        expr = .subscriptExpression(base: expr, arguments: args)
      } else {
        break
      }
    }
    return expr
  }

  
  // MARK: - Call Expression

  /// Parse a single call argument, which may be a named argument (label: expr) or positional (expr).
  private func parseCallArgument() throws -> CallArg {
    // Try to parse as named argument: identifier followed by colon
    if case .identifier(let name) = currentToken, !name.first!.isUppercase {
      let savedState = lexer.saveState()
      let savedToken = currentToken
      do {
        try match(.identifier(name))
        if currentToken === .colon {
          try match(.colon)
          let expr = try expression()
          return CallArg(label: name, expression: expr)
        } else {
          // Not a named argument, restore
          lexer.restoreState(savedState)
          currentToken = savedToken
        }
      } catch {
        lexer.restoreState(savedState)
        currentToken = savedToken
      }
    }
    // Parse as positional argument
    let expr = try expression()
    return CallArg(label: nil, expression: expr)
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
    return .call(callee: callee, arguments: arguments)
  }
  
  // MARK: - Primary Term
  
  /// Parse term - primary expressions
  private func term() throws -> ExpressionNode {
    switch currentToken {
    case .identifier(let name):
      try match(.identifier(name))
      return .identifier(name)
    case .selfKeyword:
      try match(.selfKeyword)
      return .identifier("self")
    case .integer(let num):
      try match(.integer(num))
      return .integerLiteral(num)
    case .durationLiteral(let value, let unit):
      try match(.durationLiteral(value: value, unit: unit))
      return try buildDurationLiteralExpression(value: value, unit: unit, span: currentSpan)
    case .float(let num):
      try match(.float(num))
      return .floatLiteral(num)
    case .string(let str):
      try match(.string(str))
      return .stringLiteral(str)
    case .rune(let str):
      try match(.rune(str))
      return .runeLiteral(str)
    case .interpolatedString(let parts):
      let span = currentSpan
      try match(.interpolatedString(parts: parts))
      return try parseInterpolatedString(parts, span: span)
    case .bool(let value):
      try match(.bool(value))
      return .booleanLiteral(value)
    case .leftBrace:
      return try blockExpression()
    case .leftParen:
      // Could be: parenthesized expression (expr) or lambda expression (params) -> body
      return try parseParenOrLambda()
    case .leftBracket:
      return try parseBracketStartedExpression()
    case .dot:
      // Implicit member expression: .memberName(args)
      return try parseImplicitMemberExpression()
    default:
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "number, identifier, boolean literal, block expression, or generic instantiation"
      )
    }
  }

  /// Parse an expression that starts with '['.
  /// This can be either a generic instantiation (`[T]List`) or a collection literal.
  private func parseBracketStartedExpression() throws -> ExpressionNode {
    let savedLexer = lexer.saveState()
    let savedToken = currentToken

    do {
      return try parseGenericInstantiationExpression()
    } catch {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
      return try parseCollectionLiteralExpression()
    }
  }

  private func parseGenericInstantiationExpression() throws -> ExpressionNode {
    try match(.leftBracket)
    var args: [TypeNode] = []
    while currentToken !== .rightBracket {
      args.append(try parseType())
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightBracket)

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedIdentifier(
        span: currentSpan, got: currentToken.description)
    }
    try match(.identifier(name))

    // Check if it's a call
    if currentToken === .leftParen {
      let callee = ExpressionNode.genericInstantiation(base: name, args: args)
      return try parseCall(callee)
    }

    return .genericInstantiation(base: name, args: args)
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
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
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

      case .interpolationStart:
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

        let expr = try parseInterpolatedExpression(exprSource)
        resultParts.append(.expression(expr))

        if case .interpolationEnd = parts[index] {
          index += 1
        }

      case .interpolationEnd:
        throw ParserError.unexpectedToken(span: span, got: ")", expected: "expression")
      }
    }

    if resultParts.count == 1, !containsInterpolation, case .literal(let str) = resultParts[0] {
      return .stringLiteral(str)
    }

    return .interpolatedString(parts: resultParts, span: span)
  }

  private func parseInterpolatedExpression(_ source: String) throws -> ExpressionNode {
    let lexer = Lexer(input: source)
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
        // Could be a return type
        if case .identifier(_) = currentToken {
          returnType = try parseType()
        } else if currentToken === .leftBracket {
          returnType = try parseType()
        }
      }
      if currentToken === .arrow {
        try match(.arrow)
        let body = try expression()
        return .lambdaExpression(parameters: [], returnType: returnType, body: body, span: startSpan)
      } else {
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
    
    do {
      while currentToken !== .rightParen {
        guard case .identifier(let paramName) = currentToken else {
          // Not a valid lambda parameter, restore and parse as expression
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(paramName))
        
        // Check for named parameter syntax in lambda - not allowed
        if currentToken === .colon {
          throw ParserError.unexpectedToken(span: currentSpan, got: "Named parameters are not supported in lambda expressions")
        }
        
        // Check for optional type annotation
        var paramType: TypeNode? = nil
        if currentToken !== .comma && currentToken !== .rightParen {
          // Could be a type annotation or an operator (if this is an expression)
          // Types start with uppercase identifier or [
          if case .identifier(let typeName) = currentToken, typeName.first?.isUppercase == true {
            paramType = try parseType()
          } else if currentToken === .leftBracket {
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
        if case .identifier(let typeName) = currentToken, typeName.first?.isUppercase == true {
          returnType = try parseType()
        } else if currentToken === .leftBracket {
          returnType = try parseType()
        }
      }
      
      // Must have arrow for lambda
      if currentToken === .arrow {
        isLambda = true
        try match(.arrow)
        let body = try expression()
        return .lambdaExpression(parameters: parameters, returnType: returnType, body: body, span: startSpan)
      }
      
      // No arrow - if we have multiple params or typed params, it's an error
      if parameters.count > 1 || parameters.contains(where: { $0.type != nil }) {
        throw ParserError.expectedArrow(span: currentSpan)
      }
      
      // Single untyped param without arrow - restore and parse as expression
      // This handles cases like (a) which could be just a parenthesized identifier
    } catch {
      // Parsing as lambda failed, restore state
    }
    
    if !isLambda {
      // Restore state and parse as parenthesized expression
      lexer.restoreState(savedState)
      currentToken = savedToken
      let first = try expression()
      if currentToken === .comma {
        try match(.comma)
        let second = try expression()
        try match(.rightParen)
        return .call(callee: .identifier("Pair"), arguments: [CallArg(label: nil, expression: first), CallArg(label: nil, expression: second)])
      }
      try match(.rightParen)
      return first
    }
    
    // Should not reach here
    fatalError("Unreachable")
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
    case "h":
      secs = raw * 3600
      nanos = 0
    case "min":
      secs = raw * 60
      nanos = 0
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
        expected: "supported duration suffix (h|min|s|ms|us|ns)"
      )
    }

    let ctorCall: ExpressionNode = .staticMethodCall(
      typeName: "Duration",
      typeArgs: [],
      methodName: "from_secs_and_nanos",
      arguments: [
        CallArg(label: nil, expression: .integerLiteral(String(secs))),
        CallArg(label: nil, expression: .integerLiteral(String(nanos)))
      ]
    )

    return .call(
      callee: .memberPath(base: ctorCall, path: ["unwrap"]),
      arguments: []
    )
  }

  
  // MARK: - Block Expression
  
  /// Parse block expression
  private func blockExpression() throws -> ExpressionNode {
    try match(.leftBrace)
    var statements: [StatementNode] = []

    // Parse statements until right brace
    while currentToken !== .rightBrace {
      if currentToken === .eof {
        throw ParserError.unexpectedEndOfFile(span: currentSpan)
      }

      let stmt = try statement()
      statements.append(stmt)

      // Check for explicit semicolon
      if currentToken === .semicolon {
        try match(.semicolon)
        continue
      }

      // Check for automatic statement termination (newline before non-continuation token)
      if shouldTerminateStatement() {
        continue
      }
    }
    
    try match(.rightBrace)
    return .blockExpression(statements: statements)
  }
  
  // MARK: - Control Flow Expressions

  private func ifExpression() throws -> ExpressionNode {
    try match(.ifKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let thenBranch = try expression()
    var elseBranch: ExpressionNode? = nil
    if currentToken === .elseKeyword {
      try match(.elseKeyword)
      elseBranch = try expression()
    }
    return .ifExpression(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch)
  }

  private func whileExpression() throws -> ExpressionNode {
    try match(.whileKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .whileExpression(condition: condition, body: body)
  }

  /// Parse for expression: for <pattern> in <iterable> then <body>
  private func forExpression() throws -> ExpressionNode {
    try match(.forKeyword)
    let pattern = try parsePattern()
    try match(.inKeyword)
    let iterable = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .forExpression(pattern: pattern, iterable: iterable, body: body)
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
      
      // Use comma as separator between match arms (optional trailing comma)
      if currentToken === .comma {
        try match(.comma)
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

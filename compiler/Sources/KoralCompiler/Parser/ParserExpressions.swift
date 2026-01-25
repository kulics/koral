// ParserExpressions.swift
// Expression parsing methods for the Koral compiler Parser

/// Extension containing all expression parsing methods
extension Parser {
  
  // MARK: - Expression Entry Point
  
  /// Parse expression rule - main entry point for expression parsing
  func expression() throws -> ExpressionNode {
    if currentToken === .letKeyword {
      return try letExpression()
    } else if currentToken === .ifKeyword {
      return try ifExpression()
    } else if currentToken === .whileKeyword {
      return try whileExpression()
    } else if currentToken === .whenKeyword {
      return try parseWhenExpression()
    } else if currentToken === .forKeyword {
      return try forExpression()
    } else {
      return try parseOrExpression()
    }
  }
  
  // MARK: - Let Expression
  
  private func letExpression() throws -> ExpressionNode {
    let (name, type, value, mutable) = try parseLetContent()
    try match(.thenKeyword)
    let body = try expression()
    return .letExpression(name: name, type: type, value: value, mutable: mutable, body: body)
  }
  
  // MARK: - Logical Expressions
  
  private func parseOrExpression() throws -> ExpressionNode {
    var left = try parseAndExpression()

    while currentToken === .orKeyword {
      if isLineContinuationBlocked() { break }
      try match(.orKeyword)
      let right = try parseAndExpression()
      left = .orExpression(left: left, right: right)
    }
    return left
  }

  private func parseAndExpression() throws -> ExpressionNode {
    var left = try parseLogicalNotExpression()

    while currentToken === .andKeyword {
      if isLineContinuationBlocked() { break }
      try match(.andKeyword)
      let right = try parseLogicalNotExpression()
      left = .andExpression(left: left, right: right)
    }
    return left
  }


  private func parseLogicalNotExpression() throws -> ExpressionNode {
    if currentToken === .notKeyword {
      try match(.notKeyword)
      let expr = try parseBitwiseOrExpression()
      return .notExpression(expr)
    }
    return try parseBitwiseOrExpression()
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

  /// Sixth level: Multiplication, division, and modulo
  private func parseMultiplicativeExpression() throws -> ExpressionNode {
    var left = try parsePowerExpression()

    while currentToken === .multiply || currentToken === .divide || currentToken === .modulo {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parsePowerExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right
      )
    }
    return left
  }

  /// Seventh level: Power (right-associative)
  private func parsePowerExpression() throws -> ExpressionNode {
    let left = try parsePrefixExpression()
    // Power is right-associative, so we use recursion instead of a loop
    if currentToken === .doubleStar {
      if isLineContinuationBlocked() { return left }
      try match(.doubleStar)
      let right = try parsePowerExpression()  // Recursive for right-associativity
      return .arithmeticExpression(left: left, operator: .power, right: right)
    }
    return left
  }

  
  // MARK: - Prefix Expressions
  
  private func parsePrefixExpression() throws -> ExpressionNode {
    if let cast = try tryParseCastExpression() {
      return cast
    }
    if currentToken === .refKeyword {
      try match(.refKeyword)
      let expr = try parsePrefixExpression()
      return .refExpression(expr)
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
          var arguments: [ExpressionNode] = []
          if currentToken !== .rightParen {
            repeat {
              arguments.append(try expression())
              if currentToken === .comma {
                try match(.comma)
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
              var arguments: [ExpressionNode] = []
              if currentToken !== .rightParen {
                repeat {
                  arguments.append(try expression())
                  if currentToken === .comma {
                    try match(.comma)
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
              var arguments: [ExpressionNode] = []
              if currentToken !== .rightParen {
                repeat {
                  arguments.append(try expression())
                  if currentToken === .comma {
                    try match(.comma)
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
  
  private func parseCall(_ callee: ExpressionNode) throws -> ExpressionNode {
    try match(.leftParen)
    var arguments: [ExpressionNode] = []

    if currentToken !== .rightParen {
      func getNextComma() throws -> Bool {
        if currentToken === .comma {
          try match(.comma)
          return true
        }
        return false
      }
      repeat {
        let arg = try expression()
        arguments.append(arg)
      } while try getNextComma()
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
    case .integer(let num, let suffix):
      try match(.integer(num, suffix))
      return .integerLiteral(num, suffix)
    case .float(let num, let suffix):
      try match(.float(num, suffix))
      return .floatLiteral(num, suffix)
    case .string(let str):
      try match(.string(str))
      return .stringLiteral(str)
    case .bool(let value):
      try match(.bool(value))
      return .booleanLiteral(value)
    case .leftBrace:
      return try blockExpression()
    case .leftParen:
      // Could be: parenthesized expression (expr) or lambda expression (params) -> body
      return try parseParenOrLambda()
    case .leftBracket:
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
    default:
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "number, identifier, boolean literal, block expression, or generic instantiation"
      )
    }
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
      let inner = try expression()
      try match(.rightParen)
      return inner
    }
    
    // Should not reach here
    fatalError("Unreachable")
  }

  
  // MARK: - Block Expression
  
  /// Parse block expression
  private func blockExpression() throws -> ExpressionNode {
    try match(.leftBrace)
    var statements: [StatementNode] = []

    // Process empty block
    if currentToken === .rightBrace {
      try match(.rightBrace)
      return .blockExpression(statements: [], finalExpression: nil)
    }

    // Parse statements
    while currentToken !== .rightBrace {
      if currentToken === .eof {
        throw ParserError.unexpectedEndOfFile(span: currentSpan)
      }

      let stmt = try statement()
      statements.append(stmt)

      // Check if this is the final expression (no explicit semicolon and next is right brace)
      if case .expression(let expr, _) = stmt {
        if currentToken === .rightBrace {
          // This expression is the final expression (return value of block)
          try match(.rightBrace)
          return .blockExpression(
            statements: Array(statements.dropLast()),
            finalExpression: expr
          )
        }
      }

      // Check for explicit semicolon - if present, this statement is terminated
      if currentToken === .semicolon {
        try match(.semicolon)
        // After semicolon, if next is right brace, block has no final expression
        if currentToken === .rightBrace {
          try match(.rightBrace)
          return .blockExpression(statements: statements, finalExpression: nil)
        }
        continue
      }

      // Check for automatic statement termination (newline before non-continuation token)
      if shouldTerminateStatement() {
        // If next is right brace, block has no final expression
        if currentToken === .rightBrace {
          try match(.rightBrace)
          return .blockExpression(statements: statements, finalExpression: nil)
        }
        continue
      }

      // If we reach here, the statement continues (e.g., continuation token on next line)
      // This shouldn't normally happen as statement() should consume the full statement
    }
    
    try match(.rightBrace)
    return .blockExpression(statements: statements, finalExpression: nil)
  }
  
  // MARK: - Control Flow Expressions
  
  private func ifExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.ifKeyword)
    let subject = try expression()
    
    // Check if this is pattern matching syntax: if expr is pattern then body
    if currentToken === .isKeyword {
      try match(.isKeyword)
      let pattern = try parsePattern()
      try match(.thenKeyword)
      let thenBranch = try expression()
      
      var elseBranch: ExpressionNode? = nil
      if currentToken === .elseKeyword {
        try match(.elseKeyword)
        elseBranch = try expression()
      }
      
      return .ifPatternExpression(
        subject: subject,
        pattern: pattern,
        thenBranch: thenBranch,
        elseBranch: elseBranch,
        span: startSpan
      )
    }
    
    // Original boolean condition syntax: if condition then body
    try match(.thenKeyword)
    let thenBranch = try expression()

    var elseBranch: ExpressionNode? = nil
    if currentToken === .elseKeyword {
      try match(.elseKeyword)
      elseBranch = try expression()
    }
    return .ifExpression(condition: subject, thenBranch: thenBranch, elseBranch: elseBranch)
  }

  private func whileExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.whileKeyword)
    let subject = try expression()
    
    // Check if this is pattern matching syntax: while expr is pattern then body
    if currentToken === .isKeyword {
      try match(.isKeyword)
      let pattern = try parsePattern()
      try match(.thenKeyword)
      let body = try expression()
      
      return .whilePatternExpression(
        subject: subject,
        pattern: pattern,
        body: body,
        span: startSpan
      )
    }
    
    // Original boolean condition syntax: while condition then body
    try match(.thenKeyword)
    let body = try expression()
    return .whileExpression(condition: subject, body: body)
  }

  /// Parse for expression: for <pattern> = <iterable> then <body>
  private func forExpression() throws -> ExpressionNode {
    try match(.forKeyword)
    let pattern = try parsePattern()
    try match(.equal)
    let iterable = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .forExpression(pattern: pattern, iterable: iterable, body: body)
  }

  
  // MARK: - When/Match Expression
  
  private func parseWhenExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.whenKeyword)
    let subject = try expression()
    try match(.isKeyword)
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
    return .matchExpression(subject: subject, cases: cases, span: startSpan)
  }
  
  // MARK: - Operator Conversion Helpers
  
  private func tokenToArithmeticOperator(_ token: Token) -> ArithmeticOperator {
    switch token {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .modulo: return .modulo
    case .doubleStar: return .power
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

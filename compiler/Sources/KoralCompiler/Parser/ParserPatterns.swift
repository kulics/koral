// ParserPatterns.swift
// Pattern parsing methods for the Koral compiler Parser

/// Extension containing all pattern parsing methods
extension Parser {
  
  // MARK: - Pattern Parsing

  /// Parse pattern (entry point) - supports combinators with precedence: not > and > or
  func parsePattern() throws -> PatternNode {
    return try parseOrPattern()
  }
  
  /// Parse or pattern (lowest precedence)
  private func parseOrPattern() throws -> PatternNode {
    let startSpan = currentSpan
    var left = try parseAndPattern()
    
    while currentToken === .orKeyword {
      try match(.orKeyword)
      let right = try parseAndPattern()
      left = .orPattern(left: left, right: right, span: startSpan)
    }
    
    return left
  }
  
  /// Parse and pattern
  private func parseAndPattern() throws -> PatternNode {
    let startSpan = currentSpan
    var left = try parseNotPattern()
    
    while currentToken === .andKeyword {
      try match(.andKeyword)
      let right = try parseNotPattern()
      left = .andPattern(left: left, right: right, span: startSpan)
    }
    
    return left
  }
  
  /// Parse not pattern (highest precedence among combinators)
  private func parseNotPattern() throws -> PatternNode {
    let startSpan = currentSpan
    
    if currentToken === .notKeyword {
      try match(.notKeyword)
      let pattern = try parseNotPattern()  // Right-associative
      return .notPattern(pattern: pattern, span: startSpan)
    }
    
    return try parsePrimaryPattern()
  }
  
  /// Parse primary pattern (literals, wildcards, variables, union cases, comparison patterns)
  private func parsePrimaryPattern() throws -> PatternNode {
    let startSpan = currentSpan
    
    // Comparison patterns: > n, < n, >= n, <= n
    if currentToken === .greater || currentToken === .less ||
       currentToken === .greaterEqual || currentToken === .lessEqual {
      let op: ComparisonPatternOperator
      switch currentToken {
      case .greater:
        op = .greater
        try match(.greater)
      case .less:
        op = .less
        try match(.less)
      case .greaterEqual:
        op = .greaterEqual
        try match(.greaterEqual)
      case .lessEqual:
        op = .lessEqual
        try match(.lessEqual)
      default:
        fatalError("Unreachable")
      }
      
      // Parse integer operand (may be negative)
      var isNegative = false
      if currentToken === .minus {
        try match(.minus)
        isNegative = true
      }
      
      guard case .integer(let v, let suffix) = currentToken else {
        throw ParserError.unexpectedToken(span: currentSpan, got: "Comparison pattern requires integer literal")
      }
      try match(.integer(v, suffix))
      
      let value = isNegative ? "-\(v)" : v
      return .comparisonPattern(operator: op, value: value, suffix: suffix, span: startSpan)
    }
    
    // Negative integer literal pattern: -n
    if currentToken === .minus {
      try match(.minus)
      guard case .integer(let v, let suffix) = currentToken else {
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
      }
      try match(.integer(v, suffix))
      return .negativeIntegerLiteral(value: v, suffix: suffix, span: startSpan)
    }
    
    // Range pattern error - no longer supported
    if currentToken === .fullRange || currentToken === .unboundedRange || 
       currentToken === .unboundedRangeLess {
      throw ParserError.unexpectedToken(
        span: currentSpan, 
        got: "Range patterns are no longer supported. Use comparison patterns instead (e.g., > 5 and < 10)."
      )
    }
    
    // Integer literal pattern
    if case .integer(let v, let suffix) = currentToken {
      try match(.integer(v, suffix))
      
      // Check for range operator - error if found
      if currentToken === .range || currentToken === .rangeLess ||
         currentToken === .lessRange || currentToken === .lessRangeLess ||
         currentToken === .unboundedRange || currentToken === .lessUnboundedRange {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: "Range patterns are no longer supported. Use comparison patterns instead (e.g., >= \(v) and < end)."
        )
      }
      
      return .integerLiteral(value: v, suffix: suffix, span: startSpan)
    }
    
    // Boolean literal pattern
    if case .bool(let v) = currentToken {
      try match(.bool(v))
      return .booleanLiteral(value: v, span: currentSpan)
    }
    
    // Identifier pattern (wildcard or variable binding)
    if case .identifier(let name) = currentToken {
      if name == "_" {
        try match(.identifier(name))
        return .wildcard(span: currentSpan)
      }
      try match(.identifier(name))
      return .variable(name: name, mutable: false, span: currentSpan)
    }
    
    // String literal pattern
    if case .string(let str) = currentToken {
      try match(.string(str))
      return .stringLiteral(value: str, span: currentSpan)
    }
    
    // Mutable variable binding pattern
    if currentToken === .mutKeyword {
      try match(.mutKeyword)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))
      return .variable(name: name, mutable: true, span: currentSpan)
    }
    
    // Union case pattern
    if currentToken === .dot {
      try match(.dot)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))
      var args: [PatternNode] = []
      if currentToken === .leftParen {
        try match(.leftParen)
        while currentToken !== .rightParen {
          args.append(try parsePattern())
          if currentToken === .comma { try match(.comma) }
        }
        try match(.rightParen)
      }
      return .unionCase(caseName: name, elements: args, span: currentSpan)
    }
    
    // Parenthesized pattern for grouping
    if currentToken === .leftParen {
      try match(.leftParen)
      let inner = try parsePattern()
      try match(.rightParen)
      return inner
    }
    
    throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
  }
}

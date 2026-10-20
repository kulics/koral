// ParserPatterns.swift
// Pattern parsing methods for the Koral compiler Parser

/// Extension containing all pattern parsing methods
extension Parser {
  
  // MARK: - Pattern Parsing

  /// Parse pattern (entry point) - supports combinators with precedence: not > and > or
  func parsePattern() throws -> PatternNode {
    return try parseOrPattern()
  }

  /// Parse a single primary pattern without `and`/`or`/`not` combinators.
  /// Used by `is`/`is not` expressions where `and`/`or`/`not` should be treated
  /// as expression-level logical operators, not pattern combinators.
  func parseSinglePattern() throws -> PatternNode {
    return try parsePrimaryPattern()
  }

  /// Parse a single pattern argument, which may be a named pattern (label: pattern) or positional (pattern).
  private func parsePatternArgument() throws -> PatternArg {
    // The rest marker is a slot of its own: it is never labeled (there is no
    // field for the swallowed slots to land on) and never a full pattern.
    if currentToken === .ellipsis {
      return PatternArg(label: nil, pattern: try parseRestPatternSlot())
    }
    if let name = currentLabeledArgumentName(allowUnderscore: false) {
      // `label: ...` has no meaning -- the rest marker swallows unnamed slots.
      // The labelled path below treats every failure as a failed lookahead and
      // falls through, so reject this one before entering it.
      let probeState = lexer.saveState()
      let probeToken = currentToken
      try match(.identifier(name))
      try match(.colon)
      let labeledRest = currentToken === .ellipsis
      lexer.restoreState(probeState)
      currentToken = probeToken
      if labeledRest {
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Rest pattern cannot be labeled"
        )
      }

      let savedState = lexer.saveState()
      let savedToken = currentToken
      do {
        try match(.identifier(name))
        try match(.colon)
        let pattern = try parsePattern()
        return PatternArg(label: name, pattern: pattern)
      } catch {
        lexer.restoreState(savedState)
        currentToken = savedToken
      }
    }
    // Parse as positional pattern
    let pattern = try parsePattern()
    return PatternArg(label: nil, pattern: pattern)
  }

  /// Parse the rest marker `...` as one slot of an element list. It swallows
  /// zero or more of the remaining slots and never binds, so anything that
  /// looks like a name after it is a mistake worth naming.
  private func parseRestPatternSlot() throws -> PatternNode {
    let startSpan = currentSpan
    try match(.ellipsis)
    if case .identifier = currentToken {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "Rest pattern cannot bind a name"
      )
    }
    return .restPattern(span: startSpan)
  }
  
  /// Parse or pattern (lowest precedence)
  private func parseOrPattern() throws -> PatternNode {
    let startSpan = currentSpan
    var left = try parseAndPattern()

    if currentToken === .pipe {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "Pattern separator '|' is not supported; use 'or'"
      )
    }
    
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
  
  /// Parse primary pattern (literals, wildcards, variables, enum cases, comparison patterns)
  private func parsePrimaryPattern() throws -> PatternNode {
    let startSpan = currentSpan

    // The rest marker is only ever a slot of a list / enum-case / struct /
    // tuple element list, where it swallows the slots that were not written.
    // Everywhere else -- a whole arm, an `is` subject, `not ...`, a lone
    // `( ... )` -- there is no element list to swallow, so it is a mistake.
    if currentToken === .ellipsis {
      throw ParserError.rejectedConstruct(
        span: currentSpan,
        message: "Rest pattern must be inside a list, enum, struct, or tuple pattern"
      )
    }

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
      
      // Comparison operand: an integer, float, or rune literal. A sign folds
      // into a numeric value; a rune is never negative.
      var isNegative = false
      if currentToken === .minus {
        try match(.minus)
        isNegative = true
      }

      switch currentToken {
      case .integer(let v):
        try match(.integer(v))
        return .comparisonPattern(
          operator: op,
          value: isNegative ? "-\(v)" : v,
          valueKind: .integer,
          span: startSpan
        )
      case .float(let v):
        try match(.float(v))
        return .comparisonPattern(
          operator: op,
          value: isNegative ? "-\(v)" : v,
          valueKind: .float,
          span: startSpan
        )
      case .rune(let v):
        if isNegative {
          throw ParserError.rejectedConstruct(
            span: currentSpan,
            message: "Expected integer or float literal after '-'"
          )
        }
        try match(.rune(v))
        return .comparisonPattern(operator: op, value: v, valueKind: .rune, span: startSpan)
      default:
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Expected integer, float, or rune literal in comparison pattern"
        )
      }
    }

    // Negative numeric literal pattern: -n, -1.5
    if currentToken === .minus {
      try match(.minus)
      if case .float(let v) = currentToken {
        try match(.float(v))
        return .floatLiteral(value: "-\(v)", span: startSpan)
      }
      guard case .integer(let v) = currentToken else {
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Expected integer or float literal after '-'"
        )
      }
      try match(.integer(v))
      return .negativeIntegerLiteral(value: v, span: startSpan)
    }
    
    // Range pattern error - no longer supported
    if currentToken === .range || currentToken === .rangeLess {
      throw ParserError.unexpectedToken(
        span: currentSpan, 
        got: "Range patterns are no longer supported. Use comparison patterns instead (e.g., > 5 and < 10)."
      )
    }
    
    // Integer literal pattern
    if case .integer(let v) = currentToken {
      try match(.integer(v))
      
      // Check for range operator - error if found
      if currentToken === .range || currentToken === .rangeLess ||
        currentToken === .lessRange || currentToken === .lessRangeLess {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: "Range patterns are no longer supported. Use comparison patterns instead (e.g., >= \(v) and < end)."
        )
      }
      
      return .integerLiteral(value: v, span: startSpan)
    }

    // Float literal pattern: 1.5, 1e-3
    if case .float(let v) = currentToken {
      try match(.float(v))
      return .floatLiteral(value: v, span: startSpan)
    }
    
    // Boolean literal pattern
    if case .bool(let v) = currentToken {
      try match(.bool(v))
      return .booleanLiteral(value: v, span: startSpan)
    }

    // Identifier pattern (wildcard, variable binding, or struct destructuring)
    if case .identifier(let name) = currentToken {
      if name == "_" {
        try match(.identifier(name))
        return .wildcard(span: startSpan)
      }
      try match(.identifier(name))

      // Type pattern binding without *: name TypeName (new syntax)
      // Check if next token is a type identifier (starts with uppercase)
      if case .identifier(let typeName) = currentToken, isValidTypeName(typeName) {
        let typeNameSpan = currentSpan
        try match(.identifier(typeName))
        let targetNode = TypeNode.identifier(typeName, span: typeNameSpan)
        let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
        return .traitObjectTypeBinding(name: name, mutable: false, targetType: targetNode, span: span)
      }
      
      // Struct destructuring pattern: TypeName(pattern1, pattern2, ...)
      if currentToken === .leftParen, isValidTypeName(name) {
        var args: [PatternArg] = []
        try match(.leftParen)
        while currentToken !== .rightParen {
          args.append(try parsePatternArgument())
          if currentToken === .comma { try match(.comma) }
        }
        try match(.rightParen)
        try checkRestSlots(args.map { $0.pattern })
        return .structPattern(typeName: name, elements: args, span: startSpan)
      }

      // Bare type name pattern (no binding): e.g., `err is ProbeIoError`
      if isValidTypeName(name) {
        let targetNode = TypeNode.identifier(name, span: startSpan)
        let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
        return .traitObjectTypeBinding(name: "_", mutable: false, targetType: targetNode, span: span)
      }

      if !isValidVariableName(name) {
        throw ParserError.invalidVariableName(span: startSpan, name: name)
      }

      return .variable(name: name, mutable: false, span: startSpan)
    }
    
    // String literal pattern
    if case .string(let str) = currentToken {
      try match(.string(str))
      return .stringLiteral(value: str, span: startSpan)
    }
    
    // Rune literal pattern
    if case .rune(let str) = currentToken {
      try match(.rune(str))
      return .runeLiteral(value: str, span: startSpan)
    }
    
    // Mutable variable binding pattern
    if currentToken === .mutableKeyword {
      try match(.mutableKeyword)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "mutable pattern variable")
      }
      if !isValidVariableName(name) {
        throw ParserError.invalidVariableName(span: currentSpan, name: name)
      }
      try match(.identifier(name))

      // Type pattern binding without `*`: `mutable name TypeName`.
      // (`guide/grammar.bnf` <trait-object-type-binding-pattern>.)
      if case .identifier(let typeName) = currentToken, isValidTypeName(typeName) {
        let typeNameSpan = currentSpan
        try match(.identifier(typeName))
        let targetNode = TypeNode.identifier(typeName, span: typeNameSpan)
        let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
        return .traitObjectTypeBinding(name: name, mutable: true, targetType: targetNode, span: span)
      }

      return .variable(name: name, mutable: true, span: startSpan)
    }
    
    // Enum case pattern
    if currentToken === .dot {
      try match(.dot)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "enum case pattern")
      }
      if !isValidTypeName(name) {
        throw ParserError.invalidEnumCaseName(span: currentSpan, name: name)
      }
      try match(.identifier(name))
      var args: [PatternArg] = []
      try match(.leftParen)
      while currentToken !== .rightParen {
        args.append(try parsePatternArgument())
        if currentToken === .comma { try match(.comma) }
      }
      try match(.rightParen)
      try checkRestSlots(args.map { $0.pattern })
      return .enumCase(caseName: name, elements: args, span: startSpan)
    }
    // List destructuring pattern: `[a, b]` against a `List[T]`. A rest slot
    // turns the exact length into a lower bound.
    if currentToken === .leftBracket {
      try match(.leftBracket)
      var elements: [PatternNode] = []
      while currentToken !== .rightBracket {
        elements.append(try parsePatternSlot())
        if currentToken === .comma { try match(.comma) }
      }
      try match(.rightBracket)
      try checkRestSlots(elements)
      return .listPattern(elements: elements, span: startSpan)
    }

    // `(p, q, ...)` is a TUPLE pattern: positional destructuring of a struct
    // with exactly that many fields, in declaration order. There must be at
    // least two slots -- `(` never groups a single pattern. `Pair` is
    // destructured this way too -- it is simply a two-field struct.
    if currentToken === .leftParen {
      try match(.leftParen)
      let first = try parsePatternSlot()
      if currentToken === .comma {
        var elements: [PatternNode] = [first]
        while currentToken === .comma {
          try match(.comma)
          elements.append(try parsePatternSlot())
        }
        try match(.rightParen)
        try checkRestSlots(elements)
        return .tuplePattern(elements: elements.map { PatternArg(label: nil, pattern: $0) }, span: startSpan)
      }
      // `(` in pattern position opens a tuple, which needs at least two slots.
      // A single parenthesized pattern groups nothing to group: a `when` arm is
      // already a full pattern, and under `is` the combinators are the
      // connectors `or is` / `and is`, which live outside the slot.
      throw ParserError.rejectedConstruct(
        span: startSpan,
        message: "A parenthesized pattern groups nothing; `(` starts a tuple pattern with at least two slots. Under 'is', combine tests with 'or is' / 'and is'"
      )
    }

    throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
  }

  /// Parse one slot of an element list: a sub-pattern, or the rest marker `...`.
  private func parsePatternSlot() throws -> PatternNode {
    if currentToken === .ellipsis {
      return try parseRestPatternSlot()
    }
    return try parsePattern()
  }

  /// A rest slot swallows the unwritten remainder of one element list, so a
  /// second one in the same list has nothing left to say.
  private func checkRestSlots(_ elements: [PatternNode]) throws {
    var seen = false
    for element in elements {
      if case .restPattern = element {
        if seen {
          throw ParserError.rejectedConstruct(
            span: element.span,
            message: "Only one rest pattern is allowed per element list"
          )
        }
        seen = true
      }
    }
  }
}

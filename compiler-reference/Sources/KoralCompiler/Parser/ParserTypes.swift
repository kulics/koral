// ParserTypes.swift
// Type parsing methods for the Koral compiler Parser

/// Extension containing all type parsing methods
extension Parser {

  private enum TypeModifierPrefix {
    case pointer(mutable: Bool)
    case weakReference
  }


  func isTypeStart(_ token: Token) -> Bool {
    switch token {
    case .selfTypeKeyword, .multiply, .questionMark, .identifier, .leftParen:
      return true
    default:
      return false
    }
  }
  private func wrapType(_ base: TypeNode, with prefix: TypeModifierPrefix, span: SourceSpan) -> TypeNode {
    switch prefix {
    case .pointer(let mutable):
      return .pointer(base, mutable: mutable, span: span)
    case .weakReference:
      return .weakReference(base, mutable: false, span: span)
    }
  }

  private func parseTypePrefixModifiers() throws -> [TypeModifierPrefix] {
    var prefixes: [TypeModifierPrefix] = []

    while true {
      if currentToken === .questionMark {
        try match(.questionMark)
        prefixes.append(.weakReference)
        continue
      }
      if currentToken === .multiply {
        try match(.multiply)
        let mutable = currentToken === .mutableKeyword
        if mutable {
          try match(.mutableKeyword)
        }
        prefixes.append(.pointer(mutable: mutable))
        continue
      }
      break
    }

    return prefixes
  }

  func parseTypeListInBrackets() throws -> [TypeNode] {
    try match(.leftBracket)
    var args: [TypeNode] = []
    while currentToken !== .rightBracket {
      args.append(try parseType())
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightBracket)
    return args
  }

  private func parseTypeListInParens() throws -> [TypeNode] {
    try match(.leftParen)
    var args: [TypeNode] = []
    while currentToken !== .rightParen {
      args.append(try parseType())
      if currentToken === .comma {
        try match(.comma)
      } else if currentToken !== .rightParen {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: currentToken.description,
          expected: "',' or ')'"
        )
      }
    }
    try match(.rightParen)
    return args
  }

  /// `(T1, T2) -> R` -- the parameter list is a type list and the arrow is
  /// mandatory. `startSpan` is the `(`.
  private func parseFunctionType(startSpan: SourceSpan) throws -> TypeNode {
    let paramTypes = try parseTypeListInParens()
    guard currentToken === .arrow else {
      throw ParserError.invalidFunctionType(
        span: currentSpan,
        message: "Expected '->' between parameter types and return type"
      )
    }
    try match(.arrow)
    guard isTypeStart(currentToken) else {
      throw ParserError.invalidFunctionType(
        span: currentSpan,
        message: "Function type must include a return type, e.g. (Int) -> String"
      )
    }
    let returnType = try parseType()
    return .functionType(paramTypes: paramTypes, returnType: returnType,
                         span: SourceSpan(start: startSpan.start, end: returnType.span.end))
  }

  private func parseTypeAtom() throws -> TypeNode {
    // The name is the type. `match` moves past it, so remember where it was.
    let startSpan = currentSpan

    if currentToken === .selfTypeKeyword {
      try match(.selfTypeKeyword)
      return .inferredSelf(span: startSpan)
    }

    if currentToken === .leftParen {
      return try parseFunctionType(startSpan: startSpan)
    }

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(
        span: currentSpan, got: currentToken.description)
    }
    try match(.identifier(name))

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }

    if currentToken === .leftBracket {
      let args = try parseTypeListInBrackets()
      return .generic(base: name, args: args,
                      span: SourceSpan(start: startSpan.start, end: currentSpan.end))
    }

    return .identifier(name, span: startSpan)
  }

  // MARK: - Type Parsing

  /// Parse type identifier
  /// Supports:
  /// - Simple types: Int, String, Bool
  /// - Generic types: List[T], Dict[K, V]
  /// - Function types: (ParamType1, ParamType2) -> ReturnType
  /// - Raw pointer types: *T, *mutable T
  /// - Self type: Self
  /// - Module-qualified types: module.TypeName, module.List[T]
  func parseType() throws -> TypeNode {
    // A prefixed type (`*T`, `?T`) starts at the prefix, not at `T`.
    let startSpan = currentSpan
    let prefixes = try parseTypePrefixModifiers()
    var type = try parseTypeAtom()

    for prefix in prefixes.reversed() {
      type = wrapType(type, with: prefix,
                      span: SourceSpan(start: startSpan.start, end: type.span.end))
    }

    return type
  }
}

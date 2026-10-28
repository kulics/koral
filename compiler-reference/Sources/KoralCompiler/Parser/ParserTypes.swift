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
        // `?*T` is the removed weak-of-pointer spelling. A weak referent is a
        // managed value, never a raw pointer -- koralc rejects this at the same
        // point with the same text.
        if currentToken === .multiply {
          throw ParserError.rejectedConstruct(
            span: currentSpan,
            message: "Weak reference syntax is '?T', not legacy '?*T'")
        }
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

  /// The same type node with its span replaced: a transparent `(...)` group
  /// keeps the inner type's identity and widens where it is written.
  func typeNodeWithSpan(_ type: TypeNode, _ span: SourceSpan) -> TypeNode {
    switch type {
    case .identifier(let name, _):
      return .identifier(name, span: span)
    case .reference(let inner, let mutable, _):
      return .reference(inner, mutable: mutable, span: span)
    case .pointer(let inner, let mutable, _):
      return .pointer(inner, mutable: mutable, span: span)
    case .weakReference(let inner, let mutable, _):
      return .weakReference(inner, mutable: mutable, span: span)
    case .generic(let base, let args, _):
      return .generic(base: base, args: args, span: span)
    case .inferredSelf:
      return .inferredSelf(span: span)
    case .functionType(let paramTypes, let returnType, _):
      return .functionType(paramTypes: paramTypes, returnType: returnType, span: span)
    }
  }

  /// `( <type-list> ) -> <type>` -- a function type -- or a transparent
  /// grouping `( <type> )` around exactly one type. `startSpan` is the `(`.
  private func parseParenthesizedType(startSpan: SourceSpan) throws -> TypeNode {
    try match(.leftParen)
    var types: [TypeNode] = []
    var hadTrailingComma = false
    while currentToken !== .rightParen {
      types.append(try parseType())
      if currentToken === .comma {
        try match(.comma)
        hadTrailingComma = currentToken === .rightParen
      } else if currentToken !== .rightParen {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: currentToken.description,
          expected: "',' or ')'"
        )
      }
    }
    let closeSpan = currentSpan
    try match(.rightParen)

    if currentToken === .arrow {
      try match(.arrow)
      guard isTypeStart(currentToken) else {
        throw ParserError.invalidFunctionType(
          span: currentSpan,
          message: "Function type must include a return type, e.g. (Int) -> String"
        )
      }
      let returnType = try parseType()
      return .functionType(paramTypes: types, returnType: returnType,
                           span: SourceSpan(start: startSpan.start, end: returnType.span.end))
    }

    // Grouping: exactly one type ending at the `)`. Parentheses are
    // transparent -- `(*Int)` IS `*Int`.
    if types.count == 1, !hadTrailingComma, let inner = types.first {
      return typeNodeWithSpan(inner, SourceSpan(start: startSpan.start, end: closeSpan.end))
    }
    throw ParserError.rejectedConstruct(
      span: SourceSpan(start: startSpan.start, end: closeSpan.end),
      message: "A parenthesized type holds exactly one type: write '(T)', or a function type '(A, B) -> R'"
    )
  }

  private func parseTypeAtom() throws -> TypeNode {
    // The name is the type. `match` moves past it, so remember where it was.
    let startSpan = currentSpan

    if currentToken === .selfTypeKeyword {
      try match(.selfTypeKeyword)
      return .inferredSelf(span: startSpan)
    }

    if currentToken === .leftParen {
      return try parseParenthesizedType(startSpan: startSpan)
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

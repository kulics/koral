// ParserTypes.swift
// Type parsing methods for the Koral compiler Parser

/// Extension containing all type parsing methods
extension Parser {

  private enum TypeModifierPrefix {
    case pointer(mutable: Bool)
    case weakReference
  }


  private func isTypeStart(_ token: Token) -> Bool {
    switch token {
    case .selfTypeKeyword, .multiply, .questionMark, .identifier:
      return true
    default:
      return false
    }
  }
  private func wrapType(_ base: TypeNode, with prefix: TypeModifierPrefix) -> TypeNode {
    switch prefix {
    case .pointer(let mutable):
      return .pointer(base, mutable: mutable)
    case .weakReference:
      return .weakReference(base, mutable: false)
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
        guard currentToken === .unsafeKeyword else {
          throw ParserError.unexpectedToken(
            span: currentSpan,
            got: "*",
            expected: "managed refs are removed; raw pointers must be '*unsafe T' or '*unsafe mutable T'"
          )
        }
        try match(.unsafeKeyword)
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

  private func parseFunctionTypeAfterFuncKeyword() throws -> TypeNode {
    let paramTypes = try parseTypeListInParens()
    guard isTypeStart(currentToken) else {
      throw ParserError.invalidFunctionType(
        span: currentSpan,
        message: "Function type must include a return type, e.g. Func(Int) String"
      )
    }
    let returnType = try parseType()
    return .functionType(paramTypes: paramTypes, returnType: returnType)
  }

  private func parseTypeAtom() throws -> TypeNode {
    if currentToken === .selfTypeKeyword {
      try match(.selfTypeKeyword)
      return .inferredSelf
    }

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(
        span: currentSpan, got: currentToken.description)
    }
    try match(.identifier(name))

    if name == "Func" {
      if currentToken === .leftParen {
        return try parseFunctionTypeAfterFuncKeyword()
      }
      if currentToken === .leftBracket {
        throw ParserError.invalidFunctionType(
          span: currentSpan,
          message: "Use Func(T1, T2) ReturnType instead of legacy Func[T1, T2, ReturnType]"
        )
      }
    }

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }

    if currentToken === .leftBracket {
      let args = try parseTypeListInBrackets()
      return .generic(base: name, args: args)
    }

    return .identifier(name)
  }

  // MARK: - Type Parsing

  /// Parse type identifier
  /// Supports:
  /// - Simple types: Int, String, Bool
  /// - Generic types: List[T], Dict[K, V]
  /// - Function types: Func(ParamType1, ParamType2) ReturnType
  /// - Raw pointer types: *unsafe T, *unsafe mutable T
  /// - Self type: Self
  /// - Module-qualified types: module.TypeName, module.List[T]
  func parseType() throws -> TypeNode {
    let prefixes = try parseTypePrefixModifiers()
    var type = try parseTypeAtom()

    for prefix in prefixes.reversed() {
      type = wrapType(type, with: prefix)
    }

    return type
  }
}

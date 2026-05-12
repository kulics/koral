// ParserTypes.swift
// Type parsing methods for the Koral compiler Parser

/// Extension containing all type parsing methods
extension Parser {

  private enum TypeModifierPrefix {
    case reference(mutable: Bool)
    case pointer(mutable: Bool)
    case weakReference(mutable: Bool)
  }

  private func wrapType(_ base: TypeNode, with prefix: TypeModifierPrefix) -> TypeNode {
    switch prefix {
    case .reference(let mutable):
      return .reference(base, mutable: mutable)
    case .pointer(let mutable):
      return .pointer(base, mutable: mutable)
    case .weakReference(let mutable):
      return .weakReference(base, mutable: mutable)
    }
  }

  private func parseTypePrefixModifiers() throws -> [TypeModifierPrefix] {
    var prefixes: [TypeModifierPrefix] = []

    while true {
      if currentToken === .mutKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .refKeyword {
          try match(.mutKeyword)
          try match(.refKeyword)
          prefixes.append(.reference(mutable: true))
          continue
        }
        if nextToken === .ptrKeyword {
          try match(.mutKeyword)
          try match(.ptrKeyword)
          prefixes.append(.pointer(mutable: true))
          continue
        }
        if nextToken === .weakrefKeyword {
          try match(.mutKeyword)
          try match(.weakrefKeyword)
          prefixes.append(.weakReference(mutable: true))
          continue
        }
        break
      }

      if currentToken === .refKeyword {
        try match(.refKeyword)
        prefixes.append(.reference(mutable: false))
        continue
      }
      if currentToken === .ptrKeyword {
        try match(.ptrKeyword)
        prefixes.append(.pointer(mutable: false))
        continue
      }
      if currentToken === .weakrefKeyword {
        try match(.weakrefKeyword)
        prefixes.append(.weakReference(mutable: false))
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

    if name == "Func", currentToken === .leftBracket {
      let args = try parseTypeListInBrackets()
      guard !args.isEmpty else {
        throw ParserError.invalidFunctionType(
          span: currentSpan, message: "Function type must have at least a return type")
      }
      let returnType = args.last!
      let paramTypes = Array(args.dropLast())
      return .functionType(paramTypes: paramTypes, returnType: returnType)
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
  /// - Function types: Func[ParamType1, ParamType2, ReturnType]
  /// - Reference types: ref Int, ref List[T]
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

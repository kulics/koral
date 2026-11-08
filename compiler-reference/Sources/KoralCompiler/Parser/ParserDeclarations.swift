// ParserDeclarations.swift
// Declaration parsing methods for the Koral compiler Parser

/// C reserved words (C89 through C23, plus the standard-spelling
/// alternatives): none of them can name a C identifier.
private let cReservedWords: Set<String> = [
  "auto", "break", "case", "char", "const", "constexpr", "consteval",
  "continue", "default", "do", "double", "else", "enum", "extern", "float",
  "for", "goto", "if", "inline", "int", "long", "register", "restrict",
  "return", "short", "signed", "sizeof", "static", "struct", "switch",
  "typedef", "union", "unsigned", "void", "volatile", "while", "_Alignas",
  "_Alignof", "_Atomic", "_BitInt", "_Bool", "_Complex", "_Decimal128",
  "_Decimal32", "_Decimal64", "_Generic", "_Imaginary", "_Noreturn",
  "_Static_assert", "_Thread_local", "alignas", "alignof", "bool", "complex",
  "decimal32", "decimal64", "decimal128", "false", "imaginary", "nullptr",
  "static_assert", "thread_local", "true", "typeof", "typeof_unqual",
]

/// A declared C name is spelled verbatim in `extern` prototypes and export
/// headers, so it must be a legal C identifier: the C identifier shape, and
/// no C reserved word.
private func isValidCName(_ s: String) -> Bool {
  let bytes = Array(s.utf8)
  guard let first = bytes.first else { return false }
  let isHead = (first >= UInt8(ascii: "A") && first <= UInt8(ascii: "Z"))
    || (first >= UInt8(ascii: "a") && first <= UInt8(ascii: "z"))
    || first == UInt8(ascii: "_")
  guard isHead else { return false }
  for b in bytes.dropFirst() {
    let isTail = (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
      || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
      || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
      || b == UInt8(ascii: "_")
    guard isTail else { return false }
  }
  return !cReservedWords.contains(s)
}

/// Extension containing all declaration parsing methods
extension Parser {

  private struct TopLevelDeclFlags {
    let access: AccessModifier
    let explicitAccess: AccessModifier?
  }

  private func parseSelfReceiverType() throws -> TypeNode {
    if currentToken === .multiply {
      throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
    }

    guard currentToken === .selfKeyword else {
      throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
    }

    let selfSpan = currentSpan
    try match(.selfKeyword)
    if currentToken === .colon {
      throw ParserError.unexpectedToken(span: currentSpan, got: "'self' parameter cannot use named parameter syntax")
    }

    if currentToken !== .comma && currentToken !== .rightParen {
      throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
    }
    return .inferredSelf(span: selfSpan)
  }
  
  // MARK: - Global Declaration Parsing
  
  /// Parse global declaration
  /// Whether the `(` at the cursor opens a TYPE written as a binding's
  /// annotation, rather than a declaration's parameter list. Two tells, in
  /// order: a function type's parameter list `(T1, T2) -> R` is decided by the
  /// `->` after the closing `)` -- a signature never writes its result type
  /// with one -- and a parenthesized type group is decided by its contents: a
  /// non-empty type list ending exactly at `)`. An empty `()` is decided by
  /// `->` alone, so `let f () Int = ...` stays a signature. Restores the
  /// stream.
  private func parenOpensTypeAnnotation() -> Bool {
    let savedLexer = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
    }
    guard currentToken === .leftParen else { return false }

    // Shape: the contents scan as a non-empty type list ending exactly at `)`.
    // A parameter list (`(x Int)`) does not, and falls to the `->` rule below.
    // This scan runs on its own saved stream: the balanced scan below counts
    // from the `(` and must not start mid-run.
    do {
      let shapeLexer = lexer.saveState()
      let shapeToken = currentToken
      advanceShape()
      if currentToken !== .rightParen {
        var sawType = false
        var wellFormed = true
        while true {
          guard scanTypeShapeConsuming() else {
            wellFormed = false
            break
          }
          sawType = true
          if currentToken === .comma {
            advanceShape()
            if currentToken === .rightParen { break }
            continue
          }
          break
        }
        if wellFormed, sawType, currentToken === .rightParen {
          return true
        }
      }
      lexer.restoreState(shapeLexer)
      currentToken = shapeToken
    }

    // The `(` at the cursor is already out of the lexer; count it here.
    var depth = 1
    while true {
      if let next = try? lexer.getNextToken() {
        currentToken = next
      } else {
        return false
      }
      switch currentToken {
      case .leftParen:
        depth += 1
      case .rightParen:
        depth -= 1
        if depth == 0 {
          if let after = try? lexer.getNextToken() {
            currentToken = after
          } else {
            return false
          }
          return currentToken === .arrow
        }
      case .eof:
        return false
      default:
        break
      }
    }
  }

  func parseGlobalDeclaration() throws -> GlobalNode {
    let flags = try parseTopLevelDeclFlags()
    let explicitAccess = flags.explicitAccess
    let access = flags.access
    // The declaration's span starts at its keyword (`let` / `type` / ...), not
    // at the access prefix -- koralc's `span_from_start` starts after
    // `parse_access_modifier` has consumed the prefixes, and a diagnostic
    // anchored at the declaration has to land on the same column on both.
    let startSpan = currentSpan

    if currentToken === .letKeyword {
      let keywordSpan = currentSpan
      try match(.letKeyword)
      let quals = try parseDeclQualifiers(keywordSpan: keywordSpan)
      let isIntrinsic = quals.isIntrinsic
      let isForeign = quals.isForeign

      // C 名槽位：`let foreign "CreateFileA" create_file(…)`。外来词汇是字符串，
      // 紧跟 `foreign`（docs/design/cffi-design.md §C）；不写即 Koral 名逐字。
      var cname: String? = nil
      if isForeign, case .string(let text) = currentToken {
        // The name reaches the generated TU verbatim (extern prototypes,
        // export headers): it must spell one.
        guard isValidCName(text) else {
          throw ParserError.invalidCName(span: currentSpan, name: text)
        }
        cname = text
        try match(.string(text))
      }

      // Check for mutable keyword first
      var mutable = false
      if currentToken === .mutableKeyword {
        try match(.mutableKeyword)
        mutable = true
      }

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "let declaration")
      }
      // The name's own span: a case check written after `match` would report at
      // whatever follows the name (`(`, `=`, ...), one token too far right.
      let nameSpan = currentSpan
      try match(.identifier(name))

      // koralc checks the name's shape here -- flavored by the raw `(` peek,
      // exactly as `parse_let_decl` does -- then the derived C name, all
      // before type parameters: name errors come first, in that order.
      if currentToken === .leftParen {
        if !isValidVariableName(name) {
          throw ParserError.invalidFunctionName(span: nameSpan, name: name)
        }
      } else if !isValidVariableName(name) {
        throw ParserError.invalidVariableName(span: nameSpan, name: name)
      }

      // A `let foreign` declaration's name in the C world is the C-name slot --
      // or, spelled nowhere, the Koral name verbatim. Either way it must be a
      // legal C identifier: it reaches the generated TU and the export headers
      // as a C symbol spelling.
      if isForeign, cname == nil, !isValidCName(name) {
        throw ParserError.invalidDerivedCName(span: nameSpan, name: name)
      }

      let typePrams = try parseTypeParameters()

      if isForeign && !typePrams.isEmpty {
        throw ParserError.foreignFunctionNoGenerics(span: currentSpan)
      }

      // If mutable keyword was detected, it must be a variable declaration
      if mutable {
        if isForeign {
          if currentToken === .leftParen && !parenOpensTypeAnnotation() {
            throw ParserError.unexpectedToken(span: currentSpan, got: "foreign let mutable cannot declare a function")
          }
          return try foreignLetDeclaration(name: name, mutable: true, cname: cname, access: access, span: startSpan, nameSpan: nameSpan)
        }
        if currentToken === .leftParen && !parenOpensTypeAnnotation() {
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        return try globalVariableDeclaration(
          name: name, mutable: true, access: access, span: startSpan, nameSpan: nameSpan)
      }

      // Otherwise check for left paren to determine if it's a function or variable.
      // A `(` that opens a TYPE (`let f (Int) -> Int = value`, `let p (Int) =
      // 1`) is an annotation, not a signature: the contents scan as a type, or
      // a `->` follows the closing `)`.
      if currentToken === .leftParen && !parenOpensTypeAnnotation() {
        if isForeign {
          return try foreignFunctionDeclaration(name: name, cname: cname, access: access, span: startSpan, nameSpan: nameSpan)
        }
        return try globalFunctionDeclaration(
          name: name, typeParams: typePrams, access: access, isIntrinsic: isIntrinsic,
          span: startSpan, nameSpan: nameSpan)
      } else {
        if isForeign {
          return try foreignLetDeclaration(name: name, mutable: false, cname: cname, access: access, span: startSpan, nameSpan: nameSpan)
        }
        if isIntrinsic {
          throw ParserError.unexpectedToken(
            span: currentSpan, got: "intrinsic variable not supported")
        }
        return try globalVariableDeclaration(
          name: name, mutable: false, access: access, span: startSpan, nameSpan: nameSpan)
      }
    } else if currentToken === .typeKeyword {
      let keywordSpan = currentSpan
      try match(.typeKeyword)
      let quals = try parseDeclQualifiers(keywordSpan: keywordSpan)
      let isIntrinsic = quals.isIntrinsic
      let isForeign = quals.isForeign

      // C 名槽位：`type foreign "timespec" KoralTimespec(…)`。与 `let foreign`
      // 同一拼写、同一规则——外来词汇是字符串，紧跟 `foreign`；不写即 Koral 名
      // 逐字。它是这条声明在 C 世界的名字（结构体 = C 的 struct tag）。
      var cname: String? = nil
      if isForeign, case .string(let text) = currentToken {
        guard isValidCName(text) else {
          throw ParserError.invalidCName(span: currentSpan, name: text)
        }
        cname = text
        try match(.string(text))
      }

      // `unsafe`? `sendable`? sit before `mutable`: `type unsafe sendable mutable
      // X`. `unsafe` must be accompanied by `sendable`; `type foreign` accepts both
      // (crosses by value), while `type intrinsic` and aliases reject them (each
      // checked below / in the alias arm).
      var sendability: TypeSendability = .unmarked
      var sendabilitySpan = currentSpan
      if currentToken === .unsafeKeyword {
        sendabilitySpan = currentSpan
        try match(.unsafeKeyword)
        guard currentToken === .sendableKeyword else {
          throw ParserError.rejectedConstruct(
            span: sendabilitySpan,
            message: "'unsafe' must be accompanied by 'sendable'"
          )
        }
        try match(.sendableKeyword)
        sendability = .unsafeSendable
      } else if currentToken === .sendableKeyword {
        sendabilitySpan = currentSpan
        try match(.sendableKeyword)
        sendability = .sendable
      }
      if isIntrinsic && sendability != .unmarked {
        throw ParserError.rejectedConstruct(
          span: sendabilitySpan,
          message: "intrinsic type cannot be marked \(sendability.modifierLabel)"
        )
      }

      // New declaration-site mutability: type mutable Name { ... }
      // Only nominal types are mutable; enums and aliases remain non-mutable.
      var isNominalMutable = false
      if currentToken === .mutableKeyword {
        try match(.mutableKeyword)
        isNominalMutable = true
      }

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "type declaration")
      }
      let nameSpan = currentSpan

      if !isValidTypeName(name) {
        throw ParserError.invalidTypeName(span: nameSpan, name: name)
      }

      // 同 `let foreign`：省略 C 名时，Koral 名就是 C 名，必须是合法 C 标识符。
      if isForeign, cname == nil, !isValidCName(name) {
        throw ParserError.invalidDerivedCName(span: nameSpan, name: name)
      }

      try match(.identifier(name))

      let typeParams = try parseTypeParameters()

      // `type foreign` takes no generic parameters: its layout is C's, not a
      // Koral instantiation. Both parsers used to accept `[...]` and drop it.
      if isForeign && !typeParams.isEmpty {
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Foreign type does not support generics"
        )
      }

      // `type foreign` and `type mutable` are mutually exclusive: mutability is
      // a property of Koral's own nominal declarations, and an external type's
      // layout is C's, not ours. Anchored where koralc anchors it.
      if isNominalMutable && isForeign {
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Foreign type cannot be marked mutable"
        )
      }
      // Check for type alias: type Name = TargetType
      if currentToken === .equal {
        if sendability != .unmarked {
          throw ParserError.rejectedConstruct(
            span: sendabilitySpan,
            message: "Type alias cannot be marked \(sendability.modifierLabel)"
          )
        }
        if isNominalMutable {
          throw ParserError.rejectedConstruct(
            span: currentSpan,
            message: "Type alias cannot be marked mutable"
          )
        }
        if isIntrinsic {
          throw ParserError.unexpectedToken(span: currentSpan, got: "Intrinsic type alias is not supported")
        }
        if isForeign {
          throw ParserError.unexpectedToken(span: currentSpan, got: "Foreign type alias is not supported")
        }
        try match(.equal)
        let targetType = try parseType()
        return .typeAliasDeclaration(
          name: name,
          typeParams: typeParams,
          targetType: targetType,
          access: access,
          span: startSpan,
          nameSpan: nameSpan
        )
      }

      if isNominalMutable && isIntrinsic {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: "Intrinsic type cannot be marked mutable"
        )
      }
      if isForeign {
        return try foreignTypeDeclaration(name: name, cname: cname, sendability: sendability, access: access, span: startSpan, nameSpan: nameSpan)
      }
      return try parseStructDeclaration(
        name,
        typeParams: typeParams,
        access: access,
        isIntrinsic: isIntrinsic,
        isMutable: isNominalMutable,
        sendability: sendability,
        span: startSpan,
        nameSpan: nameSpan
      )
    } else if currentToken === .givenKeyword {
      if explicitAccess != nil {
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Access modifier on given declaration is not supported")
      }
      let keywordSpan = currentSpan
      try match(.givenKeyword)
      let quals = try parseDeclQualifiers(keywordSpan: keywordSpan)
      if quals.isIntrinsic {
        return try parseIntrinsicGivenDeclaration(span: startSpan)
      }
      return try parseGivenDeclaration(span: startSpan)
    } else if currentToken === .traitKeyword {
      // The trait declaration's span starts at the `trait` keyword, not at the
      // access modifier -- the same head koralc's `span_from_start` covers.
      return try parseTraitDeclaration(access: access, span: currentSpan)
    } else {
      throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
    }
  }

  // MARK: - Trait Declaration
  
  private func parseTraitDeclaration(access: AccessModifier, span: SourceSpan) throws -> GlobalNode {
    try match(.traitKeyword)

    // `sendable` sits right after `trait`: `trait sendable Name`. The trait
    // objects of a `sendable` trait are always sendable and every impl type
    // must itself be sendable (concurrency-design.md). There is no `unsafe`
    // form: impl types carry their own safe/unsafe distinction.
    var isSendable = false
    if currentToken === .unsafeKeyword {
      let unsafeSpan = currentSpan
      try match(.unsafeKeyword)
      if currentToken === .sendableKeyword {
        try match(.sendableKeyword)
        throw ParserError.rejectedConstruct(
          span: unsafeSpan,
          message: "trait cannot be marked 'unsafe sendable'"
        )
      }
      throw ParserError.rejectedConstruct(
        span: unsafeSpan,
        message: "'unsafe' must be accompanied by 'sendable'"
      )
    }
    if currentToken === .sendableKeyword {
      try match(.sendableKeyword)
      isSendable = true
    }

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "trait declaration")
    }
    let nameSpan = currentSpan

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: nameSpan, name: name)
    }
    try match(.identifier(name))

    // Parse optional postfix type parameters for generic traits: Iterator[T Any]
    let typeParams = try parseTypeParameters()

    // Optional inheritance list: trait Child: ParentA and ParentB { ... }
    var superTraits: [TypeNode] = []

    // Parse first parent constraint if present
    if currentToken === .colon {
      try match(.colon)
      let firstParent = try parseType()
      superTraits.append(firstParent)
      
      // Parse subsequent constraints separated by 'and'
      while currentToken === .andKeyword {
        try match(.andKeyword)
        let nextParent = try parseType()
        superTraits.append(nextParent)
      }
    }

    try match(.leftBrace)

    var methods: [TraitMethodSignature] = []
    while currentToken !== .rightBrace {
      // A trait requirement has no access modifier slot: its visibility IS the
      // trait declaration's, stamped onto every signature below. A legacy
      // spelling in this slot still gets the migration hint.
      try rejectLegacyAccessSpellingIfNeeded()
      if isCurrentAccessModifierToken() {
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Access modifier on trait method is not supported")
      }
      let methodAccess = access

      guard case .identifier(let methodName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "trait member")
      }
      if !isValidVariableName(methodName) {
        throw ParserError.invalidFunctionName(span: currentSpan, name: methodName)
      }
      try match(.identifier(methodName))

      let methodTypeParams = try parseTypeParameters()

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)] = []
      var seenNamedParam = false

      if currentToken === .mutableKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .selfKeyword || nextToken === .multiply {
          throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
        }
      }

      if currentToken === .selfKeyword || currentToken === .multiply {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: false, type: selfType, named: false, defaultValue: nil))
        if currentToken === .comma {
          try match(.comma)
        }
      }

      while currentToken !== .rightParen {
        var isMut = false
        if currentToken === .mutableKeyword {
          isMut = true
          try match(.mutableKeyword)
        }
        guard case .identifier(let pname) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description, context: "parameter")
        }
        if !isValidVariableName(pname) {
          throw ParserError.invalidParameterName(span: currentSpan, name: pname)
        }
        try match(.identifier(pname))
        // Every parameter is spelled `name: Type`; a following `=` marks a
        // named parameter (`name: Type =` required, `name: Type = value`).
        guard currentToken === .colon else {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after parameter name '\(pname)'")
        }
        try match(.colon)
        let paramType = try parseType()
        var isNamed = false
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          isNamed = true
          seenNamedParam = true
          try match(.equal)
          if currentToken !== .comma && currentToken !== .rightParen {
            defaultExpr = try parseDefaultValueLiteral()
            traitDeclaredParameterDefaults.insert("\(name)#\(methodName)#\(pname)")
          }
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      // Return type: `): Type`
      guard currentToken === .colon else {
        throw ParserError.missingReturnType(span: currentSpan)
      }
      try match(.colon)
      let returnType = try parseType()

      if currentToken === .equal {
        throw ParserError.unexpectedToken(span: currentSpan, got: "Trait method should not have body")
      }
      
      try requireSemicolon()

      methods.append(
        TraitMethodSignature(
          name: methodName,
          typeParameters: methodTypeParams,
          parameters: parameters,
          returnType: returnType,
          access: methodAccess
        )
      )
    }

    try match(.rightBrace)
    return .traitDeclaration(
      name: name,
      isSendable: isSendable,
      typeParameters: typeParams,
      superTraits: superTraits,
      methods: methods,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  // MARK: - Given Declarations
  
  private func parseIntrinsicGivenDeclaration(span: SourceSpan) throws -> GlobalNode {
    // The `given` keyword and its `intrinsic` qualifier were already consumed
    // by `parseGlobalDeclaration`, which routes here on that qualifier.
    let typeParams = try parseTypeParameters()
    let type = try parseType()
    try match(.leftBrace)

    var methods: [IntrinsicMethodDeclaration] = []

    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier(default: .internal)

      // Intrinsic methods inside intrinsic given are implicitly intrinsic, so no need for keyword check?
      // Or do we disallow nested modifiers?
      // For simplicity, skip specific 'intrinsic' keyword check on methods since the whole block is intrinsic.
      // But verify no body.

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "given member")
      }
      if !isValidVariableName(name) {
        throw ParserError.invalidFunctionName(span: currentSpan, name: name)
      }
      try match(.identifier(name))

      let methodTypeParams = try parseTypeParameters()

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)] = []
      var seenNamedParam = false

      if currentToken === .mutableKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .selfKeyword || nextToken === .multiply {
          throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
        }
      }

      if currentToken === .selfKeyword || currentToken === .multiply {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: false, type: selfType, named: false, defaultValue: nil))
        if currentToken === .comma {
          try match(.comma)
        }
      }

      while currentToken !== .rightParen {
        var isMut = false
        if currentToken === .mutableKeyword {
          isMut = true
          try match(.mutableKeyword)
        }
        guard case .identifier(let pname) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description, context: "parameter")
        }
        if !isValidVariableName(pname) {
          throw ParserError.invalidParameterName(span: currentSpan, name: pname)
        }
        try match(.identifier(pname))
        // Every parameter is spelled `name: Type`; a following `=` marks a
        // named parameter (`name: Type =` required, `name: Type = value`).
        guard currentToken === .colon else {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after parameter name '\(pname)'")
        }
        try match(.colon)
        let paramType = try parseType()
        var isNamed = false
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          isNamed = true
          seenNamedParam = true
          try match(.equal)
          if currentToken !== .comma && currentToken !== .rightParen {
            defaultExpr = try parseDefaultValueLiteral()
            implDeclaredParameterDefaults.insert("\(name)#\(pname)")
          }
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      // Return type: `): Type`
      guard currentToken === .colon else {
        throw ParserError.missingReturnType(span: currentSpan)
      }
      try match(.colon)
      let returnType = try parseType()

      // Must not have body
      if currentToken === .equal {
        throw ParserError.unexpectedToken(
          span: currentSpan, got: "Intrinsic given method should not have body")
      }
      
      try requireSemicolon()

      methods.append(
        IntrinsicMethodDeclaration(
          name: name,
          typeParameters: methodTypeParams,
          parameters: parameters,
          returnType: returnType,
          access: methodAccess
        ))
    }

    try match(.rightBrace)
    return .intrinsicGivenDeclaration(
      typeParams: typeParams, type: type, methods: methods, span: span)
  }

  private func parseGivenDeclaration(span: SourceSpan) throws -> GlobalNode {
    // The `given` keyword (and any qualifier) was already consumed by
    // `parseGlobalDeclaration`.
    let typeParams = try parseTypeParameters()
    let type = try parseType()
    var trait: TypeNode? = nil
    // Conformance: `given Target: Trait { ... }` -- the colon separates the
    // target type from the trait it satisfies.
    if currentToken === .colon {
      try match(.colon)
      trait = try parseType()
    }
    try match(.leftBrace)
    var methods: [MethodDeclaration] = []
    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier(default: .internal)

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "given member")
      }
      if !isValidVariableName(name) {
        throw ParserError.invalidFunctionName(span: currentSpan, name: name)
      }
      try match(.identifier(name))

      let typeParams = try parseTypeParameters()

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)] = []
      var seenNamedParam = false

      if currentToken === .mutableKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .selfKeyword || nextToken === .multiply {
          throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
        }
      }

      if currentToken === .selfKeyword || currentToken === .multiply {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: false, type: selfType, named: false, defaultValue: nil))
        if currentToken === .comma {
          try match(.comma)
        }
      }

      while currentToken !== .rightParen {
        var isMut = false
        if currentToken === .mutableKeyword {
          isMut = true
          try match(.mutableKeyword)
        }
        guard case .identifier(let pname) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description, context: "parameter")
        }
        if !isValidVariableName(pname) {
          throw ParserError.invalidParameterName(span: currentSpan, name: pname)
        }
        try match(.identifier(pname))
        // Every parameter is spelled `name: Type`; a following `=` marks a
        // named parameter (`name: Type =` required, `name: Type = value`).
        guard currentToken === .colon else {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after parameter name '\(pname)'")
        }
        try match(.colon)
        let paramType = try parseType()
        var isNamed = false
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          isNamed = true
          seenNamedParam = true
          try match(.equal)
          if currentToken !== .comma && currentToken !== .rightParen {
            defaultExpr = try parseDefaultValueLiteral()
            implDeclaredParameterDefaults.insert("\(name)#\(pname)")
          }
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      guard currentToken === .colon else {
        throw ParserError.missingReturnType(span: currentSpan)
      }
      try match(.colon)
      let returnType = try parseType()

      try match(.equal)
      let body = try expression()
      try requireSemicolon()

      methods.append(
        MethodDeclaration(
          name: name,
          typeParameters: typeParams,
          parameters: parameters,
          returnType: returnType,
          body: body,
          access: methodAccess
        ))
    }
    try match(.rightBrace)
    if let trait {
      return .givenTraitDeclaration(
        typeParams: typeParams,
        type: type,
        trait: trait,
        methods: methods,
        span: span
      )
    }
    return .givenDeclaration(typeParams: typeParams, type: type, methods: methods, span: span)
  }

  // MARK: - Access Modifier
  
  func parseAccessModifier(default defaultAccess: AccessModifier) throws -> AccessModifier {
    return try parseExplicitAccessModifier() ?? defaultAccess
  }

  private func isCurrentAccessModifierToken() -> Bool {
    currentToken === .publicKeyword || currentToken === .privateKeyword || currentToken === .internalKeyword || currentToken === .protectedKeyword
  }

  /// Reads the leading access modifier only. `foreign` / `intrinsic` are NOT
  /// prefix modifiers: they qualify the thing being declared and sit in the
  /// slot right after the declaration keyword -- the slot `type mutable` and
  /// `let mutable` established -- where `parseDeclQualifiers` reads them.
  private func parseTopLevelDeclFlags() throws -> TopLevelDeclFlags {
    var explicitAccess: AccessModifier? = nil
    var access: AccessModifier = .internal

    while true {
      // An identifier in this slot is never a name -- a global declaration
      // opens with `let`/`type`/`given`/`trait` -- so a legacy spelling here is
      // an attempted modifier and gets the migration hint (the follower test
      // inside the check decides, matching the bootstrap parser). This must run
      // before the keyword gate below, which would otherwise fall through.
      try rejectLegacyAccessSpellingIfNeeded()
      if isCurrentAccessModifierToken() {
        if let existingAccess = explicitAccess {
          throw ParserError.invalidAccessModifierOrder(
            span: currentSpan,
            message: "Invalid access modifier order: '\(existingAccess.description) \(currentToken.description)'."
          )
        }
        explicitAccess = try parseExplicitAccessModifier()
        access = explicitAccess ?? .internal
        continue
      }

      break
    }

    return TopLevelDeclFlags(
      access: access,
      explicitAccess: explicitAccess
    )
  }

  /// Read the `foreign` / `intrinsic` qualifiers written immediately after a
  /// declaration's keyword. They qualify the thing being declared -- where its
  /// definition lives -- so they sit in the slot right after the keyword, the
  /// slot `type mutable` and `let mutable` established. Access modifiers stay
  /// in the prefix slot: they say who can see the declaration, not what kind of
  /// thing it is. The two are mutually exclusive and may not repeat.
  ///
  /// The pinned diagnostics anchor on the declaration keyword (`keywordSpan`),
  /// which is where the reference parser reports them.
  private func parseDeclQualifiers(keywordSpan: SourceSpan) throws -> (isIntrinsic: Bool, isForeign: Bool) {
    var isIntrinsic = false
    var isForeign = false
    while true {
      if currentToken === .foreignKeyword {
        if isForeign {
          throw ParserError.duplicateDeclarationModifier(span: keywordSpan, modifier: "foreign")
        }
        if isIntrinsic {
          throw ParserError.foreignAndIntrinsicConflict(span: keywordSpan)
        }
        try match(.foreignKeyword)
        isForeign = true
      } else if currentToken === .intrinsicKeyword {
        if isIntrinsic {
          throw ParserError.duplicateDeclarationModifier(span: keywordSpan, modifier: "intrinsic")
        }
        if isForeign {
          throw ParserError.foreignAndIntrinsicConflict(span: keywordSpan)
        }
        try match(.intrinsicKeyword)
        isIntrinsic = true
      } else {
        break
      }
    }
    return (isIntrinsic: isIntrinsic, isForeign: isForeign)
  }

  private func ensureNoTrailingAccessModifier(after accessText: String) throws {
    if currentToken === .publicKeyword || currentToken === .privateKeyword || currentToken === .internalKeyword || currentToken === .protectedKeyword {
      let next = currentToken.description
      throw ParserError.invalidAccessModifierOrder(
        span: currentSpan,
        message: "Invalid access modifier order: '\(accessText) \(next)'"
      )
    }
  }

  /// The removed access spellings are ordinary identifiers now, so written in
  /// a modifier slot they read as a name and the user gets a bare "Unexpected
  /// token". Recognise the three legacy words here -- only where an access
  /// modifier is read -- and point at the current spelling. A name slot is
  /// protected by the follower test below: `let file_private = 1` and
  /// `type T(file_private Int)` name their declarations and keep working.
  private func rejectLegacyAccessSpellingIfNeeded() throws {
    guard case .identifier(let text) = currentToken else { return }
    let message: String
    switch text {
    case "file_private":
      message = "Access modifier is 'private', not legacy 'file_private'"
    case "module_private":
      message = "Access modifier is 'internal', not legacy 'module_private'"
    case "package_private":
      message = "Access modifier is 'protected', not legacy 'package_private'"
    default:
      return
    }
    guard nextTokenOpensDeclarationItem() else { return }
    throw ParserError.rejectedConstruct(span: currentSpan, message: message)
  }

  /// The next token starts what a modifier slot modifies: another modifier, a
  /// declaration keyword, or the declared NAME. When the next token instead
  /// completes the current identifier AS a name (`:`, `(`, `[`, a type after a
  /// positional field name, ...) the identifier is a name, not a modifier.
  /// Mirrors the bootstrap parser's `next_token_opens_declaration_item`.
  private func nextTokenOpensDeclarationItem() -> Bool {
    switch lexer.peekNextToken() {
    case .letKeyword, .mutableKeyword, .typeKeyword, .usingKeyword, .traitKeyword,
         .givenKeyword, .foreignKeyword, .intrinsicKeyword,
         .privateKeyword, .internalKeyword, .protectedKeyword, .publicKeyword:
      return true
    case .identifier(let name):
      if !name.isEmpty, name.allSatisfy({ $0 == "_" }) { return true }
      if let first = name.first, first.isLowercase { return true }
      return false
    default:
      return false
    }
  }

  func parseExplicitAccessModifier() throws -> AccessModifier? {
    try rejectLegacyAccessSpellingIfNeeded()
    if currentToken === .privateKeyword {
      try match(.privateKeyword)
      return .private
    } else if currentToken === .internalKeyword {
      try match(.internalKeyword)
      return .internal
    } else if currentToken === .protectedKeyword {
      try match(.protectedKeyword)
      return .protected
    } else if currentToken === .publicKeyword {
      try match(.publicKeyword)
      return .public
    }
    return nil
  }

  // MARK: - Variable Declaration
  
  /// Parse global variable declaration
  private func globalVariableDeclaration(
    name: String, mutable: Bool, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    var type: TypeNode? = nil
    if currentToken === .colon {
      try match(.colon)
      type = try parseType()
    }

    try match(.equal)
    let value = try expression()
    return .globalVariableDeclaration(
      name: name, type: type, value: value, mutable: mutable, access: access, span: span, nameSpan: nameSpan)
  }

  // MARK: - Type Parameters
  
  func parseTypeParameters() throws -> [TypeParameterDecl] {
    var parameters: [TypeParameterDecl] = []
    if currentToken === .leftBracket {
      try match(.leftBracket)
      while currentToken !== .rightBracket {
        let paramName: String
        switch currentToken {
        case .identifier(let name):
          paramName = name
          try match(.identifier(name))
        case .rune:
          throw ParserError.unexpectedToken(
            span: currentSpan,
            got: currentToken.description,
            expected: "Lifetime parameters are not supported in generic parameter lists."
          )
        default:
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description, context: "type parameter")
        }

        // Constraints are spelled `name: C1 and C2`; the colon separates the
        // type parameter from its bounds.
        guard currentToken === .colon else {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after generic parameter name '\(paramName)'")
        }
        try match(.colon)

        // A type parameter must carry at least one constraint. `Any` is the
        // vacuous one, so `[T]` is not accepted in its place -- say that, rather
        // than letting the constraint parser fail on the closing bracket.
        if currentToken !== .mutableKeyword && currentToken !== .foreignKeyword && !isTypeStart(currentToken) {
          throw ParserError.missingTypeParameterConstraint(
            span: currentSpan, name: paramName)
        }

        var constraints: [Bound] = []
        let firstNode = try parseTraitConstraint()
        if let firstBound = try boundFromTypeNode(firstNode) {
          constraints.append(firstBound)
        }
        while currentToken === .andKeyword {
          try match(.andKeyword)
          let nextNode = try parseTraitConstraint()
          if let nextBound = try boundFromTypeNode(nextNode) {
            constraints.append(nextBound)
          }
        }

        parameters.append((name: paramName, constraints: constraints))

        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightBracket)
    }
    return parameters
  }

  private func parseTraitConstraint() throws -> TypeNode {
    if currentToken === .mutableKeyword {
      let keywordSpan = currentSpan
      try match(.mutableKeyword)
      return .identifier("mutable", span: keywordSpan)
    }
    if currentToken === .foreignKeyword {
      let keywordSpan = currentSpan
      try match(.foreignKeyword)
      return .identifier("foreign", span: keywordSpan)
    }
    // `sendable` joins the shape-bound slot (`T Reader and sendable`); it must
    // be caught before the type fallback, which would read it as the `sendable`
    // type qualifier.
    if currentToken === .sendableKeyword {
      let keywordSpan = currentSpan
      try match(.sendableKeyword)
      return .identifier("sendable", span: keywordSpan)
    }
    // Trait constraints now share the full type surface, including postfix generics.
    if canStartTypeSyntax() {
      return try parseType()
    }
    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(span: currentSpan, got: currentToken.description)
    }
    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }
    let nameSpan = currentSpan
    try match(.identifier(name))
    return .identifier(name, span: nameSpan)
  }

  // MARK: - Function Declaration
  
  /// Parse global function declaration with optional 'own'/'ref' modifiers for params and return type
  private func globalFunctionDeclaration(
    name: String, typeParams: [TypeParameterDecl], access: AccessModifier,
    isIntrinsic: Bool, span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    try match(.leftParen)
    var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)] = []
    var seenNamedParam = false
    while currentToken !== .rightParen {
      // 仅支持可选的前缀 mutable；不再支持 own/ref
      var isMut = false
      if currentToken === .mutableKeyword {
        isMut = true
        try match(.mutableKeyword)
      }
      guard case .identifier(let pname) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "parameter")
      }
      if !isValidVariableName(pname) {
        throw ParserError.invalidParameterName(span: currentSpan, name: pname)
      }
      try match(.identifier(pname))
      // Every parameter is spelled `name: Type`; a following `=` marks a
      // named parameter (`name: Type =` required, `name: Type = value`).
      guard currentToken === .colon else {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after parameter name '\(pname)'")
      }
      try match(.colon)
      let paramType = try parseType()
      var isNamed = false
      var defaultExpr: ExpressionNode? = nil
      if currentToken === .equal {
        isNamed = true
        seenNamedParam = true
        try match(.equal)
        if currentToken !== .comma && currentToken !== .rightParen {
          defaultExpr = try parseDefaultValueLiteral()
        }
      } else if seenNamedParam {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
      }
      parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

    guard currentToken === .colon else {
      throw ParserError.missingReturnType(span: currentSpan)
    }
    try match(.colon)
    let returnType = try parseType()

    if isIntrinsic {
      if currentToken === .equal {
        throw ParserError.unexpectedToken(
          span: currentSpan, got: "Intrinsic function should not have body")
      }
      return .intrinsicFunctionDeclaration(
        name: name,
        typeParameters: typeParams,
        parameters: parameters,
        returnType: returnType,
        access: access,
        span: span,
        nameSpan: nameSpan
      )
    } else {
      try match(.equal)
      let body = try expression()
      return .globalFunctionDeclaration(
        name: name,
        typeParameters: typeParams,
        parameters: parameters,
        returnType: returnType,
        body: body,
        access: access,
        span: span,
        nameSpan: nameSpan
      )
    }
  }

  // MARK: - Foreign Declarations

  private func foreignFunctionDeclaration(
    name: String, cname: String?, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    try match(.leftParen)
    var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)] = []
    var seenNamedParam = false
    while currentToken !== .rightParen {
      var isMut = false
      if currentToken === .mutableKeyword {
        isMut = true
        try match(.mutableKeyword)
      }
      guard case .identifier(let pname) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "parameter")
      }
      if !isValidVariableName(pname) {
        throw ParserError.invalidParameterName(span: currentSpan, name: pname)
      }
      // The `=` is what makes `name: Type =` a NAMED parameter. The
      // rejection has to remember where the name was -- reporting at
      // `currentSpan` points at the type instead.
      let nameSpan = currentSpan
      try match(.identifier(pname))
      guard currentToken === .colon else {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after parameter name '\(pname)'")
      }
      try match(.colon)
      let paramType = try parseType()
      if currentToken === .equal {
        throw ParserError.rejectedConstruct(span: nameSpan, message: "Named parameters are not supported in foreign declarations")
      }
      parameters.append((name: pname, mutable: isMut, type: paramType, named: false, defaultValue: nil))
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

    guard currentToken === .colon else {
      throw ParserError.missingReturnType(span: currentSpan)
    }
    try match(.colon)
    let returnType = try parseType()

    // 体的存在性定方向：无体是引用（extern），有体是 C ABI 导出定义
    // （docs/design/cffi-design.md §B）。
    var body: ExpressionNode? = nil
    if currentToken === .equal {
      try match(.equal)
      body = try expression()
    }

    return .foreignFunctionDeclaration(
      name: name,
      parameters: parameters,
      returnType: returnType,
      body: body,
      cname: cname,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  private func foreignTypeDeclaration(
    name: String, cname: String?, sendability: TypeSendability, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    var fields: [(name: String, type: TypeNode)]? = nil
    if currentToken === .leftBrace {
      try match(.leftBrace)
      try match(.rightBrace)
    } else if currentToken === .leftParen {
      try match(.leftParen)
      fields = []
      while currentToken !== .rightParen {
        guard case .identifier(let fieldName) = currentToken else {
          throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "field name")
        }
        try match(.identifier(fieldName))
        guard currentToken === .colon else {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after field name '\(fieldName)'")
        }
        try match(.colon)
        let fieldType = try parseType()
        fields?.append((name: fieldName, type: fieldType))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)
    } else {
      throw ParserError.foreignTypeNoBody(span: currentSpan)
    }

    return .foreignTypeDeclaration(
      name: name,
      fields: fields,
      cname: cname,
      sendability: sendability,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  private func foreignLetDeclaration(
    name: String, mutable: Bool, cname: String?, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    guard currentToken === .colon else {
      throw ParserError.rejectedConstruct(span: currentSpan, message: "foreign let declaration requires explicit type")
    }
    try match(.colon)
    let type = try parseType()
    // 初值的存在性 + `mutable` 定形态（docs/design/cffi-design.md §B）：无初值是
    // extern 引用；有初值 + `mutable` 是 C 变量定义；有初值 + 无 `mutable` 是
    // C 宏常量的值绑定（无存储、无符号）。
    var initializer: ExpressionNode? = nil
    if currentToken === .equal {
      try match(.equal)
      let valueStart = currentSpan
      let value = try expression()
      if !isForeignConstantInitializer(value) {
        throw ParserError.rejectedConstruct(
          span: valueStart,
          message: "foreign variable initializer must be a constant literal (C static initializers are constant expressions)")
      }
      initializer = value
    }
    return .foreignLetDeclaration(
      name: name,
      type: type,
      mutable: mutable,
      initializer: initializer,
      cname: cname,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  /// foreign 变量的初值只收常量字面量（可带负号 / null）：C 的静态初始化器必须是
  /// 常量表达式（docs/design/cffi-design.md §B）。
  private func isForeignConstantInitializer(_ expr: ExpressionNode) -> Bool {
    switch expr {
    // A rune literal is not a C constant of any foreign type: `Rune` is not
    // in the foreign set, and nothing else the set holds takes one.
    case .integerLiteral, .floatLiteral, .booleanLiteral, .nullLiteral:
      return true
    case .unaryMinusExpression(let inner, _):
      switch inner {
      case .integerLiteral, .floatLiteral:
        return true
      default:
        return false
      }
    default:
      return false
    }
  }

  // MARK: - Struct Declaration
  
  /// Parse type declaration
  private func parseStructDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier,
    isIntrinsic: Bool, isMutable: Bool = false, sendability: TypeSendability,
    span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    if isIntrinsic {
      if currentToken === .leftParen {
        throw ParserError.unexpectedToken(
          span: currentSpan, got: "Intrinsic type should not have body")
      }
      return .intrinsicTypeDeclaration(
        name: name, typeParameters: typeParams, access: access, span: span, nameSpan: nameSpan)
    }

    if currentToken === .leftBrace {
      if isMutable {
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "Enum type cannot be marked mutable"
        )
      }
      return try parseEnumDeclaration(name, typeParams: typeParams, sendability: sendability, access: access, span: span, nameSpan: nameSpan)
    }

    try match(.leftParen)
    var parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)] = []
    var seenNamedField = false

    while currentToken !== .rightParen {
      let fieldAccess = try parseAccessModifier(default: .internal)

      // Check for mutable keyword for the field
      var fieldMutable = false
      if currentToken === .mutableKeyword {
        try match(.mutableKeyword)
        fieldMutable = true
      }

      guard case .identifier(let paramName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "field name")
      }
      if !isValidVariableName(paramName) {
        throw ParserError.invalidFieldName(span: currentSpan, name: paramName)
      }
      try match(.identifier(paramName))
      // `name: Type` separates the field name from its type; a following `=`
      // marks a named field (`name: Type =` required, `name: Type = value`).
      guard currentToken === .colon else {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after field name '\(paramName)'")
      }
      try match(.colon)
      let paramType = try parseType()
      var isNamed = false
      var defaultExpr: ExpressionNode? = nil
      if currentToken === .equal {
        isNamed = true
        seenNamedField = true
        try match(.equal)
        if currentToken !== .comma && currentToken !== .rightParen {
          defaultExpr = try parseDefaultValueLiteral()
        }
      } else if seenNamedField {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional field '\(paramName)' cannot appear after named fields")
      }

      parameters.append(
        (name: paramName, type: paramType, mutable: fieldMutable, access: fieldAccess, named: isNamed, defaultValue: defaultExpr))

      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)


    return .globalStructDeclaration(
      name: name,
      typeParameters: typeParams,
      parameters: parameters,
      isMutable: isMutable,
      sendability: sendability,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  // MARK: - Enum Declaration
  
  /// Parse enum declaration (sum type)
  private func parseEnumDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], sendability: TypeSendability, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    try match(.leftBrace)
    var cases: [EnumCaseDeclaration] = []

    while currentToken !== .rightBrace {
      guard case .identifier(let caseName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "enum case")
      }
      if !isValidTypeName(caseName) {
        throw ParserError.invalidEnumCaseName(span: currentSpan, name: caseName)
      }
      try match(.identifier(caseName))

      var parameters: [(name: String, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)] = []
      try match(.leftParen)

      var seenNamedParam = false
      while currentToken !== .rightParen {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description, context: "enum payload name")
        }
        if !isValidVariableName(paramName) {
          throw ParserError.invalidParameterName(span: currentSpan, name: paramName)
        }
        try match(.identifier(paramName))
        // `name: Type` separates the field name from its type; a following `=`
        // marks a named field (`name: Type =` required, `name: Type = value`).
        guard currentToken === .colon else {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "expected ':' after field name '\(paramName)'")
        }
        try match(.colon)
        let paramType = try parseType()
        var isNamed = false
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          isNamed = true
          seenNamedParam = true
          try match(.equal)
          if currentToken !== .comma && currentToken !== .rightParen {
            defaultExpr = try parseDefaultValueLiteral()
          }
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional field '\(paramName)' cannot appear after named fields")
        }
        parameters.append((name: paramName, type: paramType, named: isNamed, defaultValue: defaultExpr))

        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)
      
      cases.append(EnumCaseDeclaration(name: caseName, parameters: parameters))
      
      // Use comma as separator between variants (optional trailing comma)
      if currentToken === .comma {
        try match(.comma)
      }
    }

    try match(.rightBrace)


    return .globalEnumDeclaration(
      name: name,
      typeParameters: typeParams,
      cases: cases,
      sendability: sendability,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  // MARK: - Using Declarations

  /// Check if current position is a using declaration
  func isUsingDeclaration() -> Bool {
    currentToken === .usingKeyword
  }

  /// Parse `using "<specifier>" ("{" items "}")?;`
  ///
  /// One form (§3). The specifier is a string; what it means is decided by its
  /// shape: `./` or `../` is a file to merge, anything else is a module's full
  /// name, `package[/subpath]`. The parser settles that here because every
  /// rule about the specifier is a rule about its spelling.
  func parseUsingDeclaration() throws -> UsingDeclaration {
    let startSpan = currentSpan
    try match(.usingKeyword)

    guard case .string(let specifier) = currentToken else {
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "a string literal: \"./file.koral\" to merge a file, or \"package[/subpath]\" to import a module"
      )
    }
    let specifierSpan = currentSpan
    try match(currentToken)

    if currentToken === .asKeyword {
      // `using "x" as Y;` was "merge this file and rename it". There is no
      // whole-module alias any more (§3.3: a module name is not a namespace),
      // so say where an alias does belong rather than just "unexpected as".
      throw ParserError.rejectedConstruct(
        span: specifierSpan,
        message: "a module is not renamed; alias the names you import: using \"\(specifier)\" { Name as Alias }"
      )
    }

    let isFileMerge = specifier.hasPrefix("./") || specifier.hasPrefix("../")
      || specifier.hasPrefix(".\\") || specifier.hasPrefix("..\\")

    var items: [UsingModuleItem]? = nil
    var importAll = false
    if currentToken === .leftBrace {
      let parsed = try parseUsingImportList(isFileMerge: isFileMerge, specifier: specifier)
      items = parsed.items
      importAll = parsed.importAll
    }

    if isFileMerge {
      // A local path may be merged (bare) or imported (braces). Either way it
      // names the module rooted at that entry file (§3.1); the braces decide
      // only whether the boundary survives.
      if !specifier.hasSuffix(".koral") {
        throw ParserError.rejectedConstruct(
          span: specifierSpan,
          message: "File merge path must end in '.koral'; write '\(specifier).koral'"
        )
      }
    } else {
      try validateModuleSpecifier(specifier, span: specifierSpan)
    }

    let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
    return UsingDeclaration(specifier: specifier, items: items, importAll: importAll, span: span)
  }

  /// A module's full name is `package[/subpath]`, lowercase identifier
  /// segments (§2.1). `.` is not a spelling of anything in source -- it is
  /// only how a manifest names a package's main module (§5.2).
  private func validateModuleSpecifier(_ specifier: String, span: SourceSpan) throws {
    if specifier == "." {
      throw ParserError.rejectedConstruct(
        span: span,
        message: "write the package name itself for its main module; \".\" is only manifest notation"
      )
    }
    // `split` drops empty segments, so `a//b` would look like `a/b`. Ask for
    // the parts without losing them (§7.5 lists empty segments explicitly).
    var segments: [String] = []
    var current = ""
    for ch in specifier {
      if ch == "/" {
        segments.append(current)
        current = ""
      } else {
        current.append(ch)
      }
    }
    segments.append(current)
    guard !segments.isEmpty else {
      throw ParserError.rejectedConstruct(span: span, message: "module name must be 'package[/subpath]'")
    }
    for segment in segments {
      guard let first = segment.first, first.isASCII, first.isLowercase else {
        throw ParserError.rejectedConstruct(
          span: span,
          message: "module name must be 'package[/subpath]' with lowercase identifier segments"
        )
      }
      for ch in segment {
        guard ch.isASCII else {
          throw ParserError.rejectedConstruct(
            span: span,
            message: "module name must be 'package[/subpath]' with lowercase identifier segments"
          )
        }
        if ch.isLowercase || ch.isNumber || ch == "_" { continue }
        throw ParserError.rejectedConstruct(
          span: span,
          message: "module name must be 'package[/subpath]' with lowercase identifier segments"
        )
      }
    }
  }

  /// `{ ... }` -- the filter on an import (§3.3).
  ///
  /// Omitting the braces is a merge (§3.2); writing them is an import, and the
  /// list says which members come along. Six forms:
  ///
  ///     { }                  nothing at all (a placeholder while editing)
  ///     { a, b }             exactly these
  ///     { a as b }           exactly these, one renamed
  ///     { ... }              every visible member
  ///     { a as b, ... }      every member, `a` spelled `b`
  ///     { !a, !b, ... }      every member but `a` and `b`
  ///
  /// `...` is the base set. Items alongside it are renames (positive) or
  /// exclusions (`!`), never both; a positive item without `as` next to `...`
  /// is redundant and rejected.
  private func parseUsingImportList(isFileMerge: Bool, specifier: String) throws -> UsingImportList {
    let braceSpan = currentSpan
    try match(.leftBrace)
    var items: [UsingModuleItem] = []
    var importAll = false
    var sawExclude = false
    var sawPositive = false

    while currentToken !== .rightBrace {
      if currentToken === .range {
        // `{ .. }` used to mean "everything" and `...` means it now (§3.3).
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "\"..\" is not an import item; write \"...\" to import every visible member of \"\(specifier)\""
        )
      }
      if currentToken === .ellipsis {
        // `...` is the base set and closes the list: renames and exclusions
        // come before it, nothing comes after (§3.3).
        try match(.ellipsis)
        importAll = true
        if currentToken === .comma {
          try match(.comma)
        }
        if currentToken !== .rightBrace {
          throw ParserError.rejectedConstruct(
            span: currentSpan,
            message: "\"...\" closes the import list; put renames or exclusions before it, or write \"{ ... }\""
          )
        }
        try match(.rightBrace)
        return try finishUsingImportList(
          specifier: specifier, items: items, importAll: true,
          sawExclude: sawExclude, sawPositive: sawPositive,
          braceSpan: braceSpan, isFileMerge: isFileMerge)
      }

      // Point at the item's first token -- `!` or the name -- so an `!`+`as`
      // pair blames the exclusion marker rather than the name it marks.
      let nameSpan = currentSpan
      var excluded = false
      if currentToken === .bang {
        try match(.bang)
        excluded = true
        sawExclude = true
      } else {
        sawPositive = true
      }
      guard case .identifier(let symbolName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "import item")
      }
      try match(currentToken)

      var alias: String? = nil
      if currentToken === .asKeyword {
        if excluded {
          throw ParserError.rejectedConstruct(
            span: nameSpan,
            message: "'!\(symbolName)' is an exclusion and cannot be renamed; drop the '!' or drop the 'as'"
          )
        }
        try match(.asKeyword)
        guard case .identifier(let aliasName) = currentToken else {
          throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "using alias")
        }
        try match(currentToken)
        if isValidTypeName(symbolName) && !isValidTypeName(aliasName) {
          throw ParserError.invalidUsingAliasCase(
            span: nameSpan,
            alias: aliasName,
            referenced: symbolName,
            expectedUppercase: true
          )
        }
        if isValidVariableName(symbolName) && !isValidVariableName(aliasName) {
          throw ParserError.invalidUsingAliasCase(
            span: nameSpan,
            alias: aliasName,
            referenced: symbolName,
            expectedUppercase: false
          )
        }
        alias = aliasName
      }

      items.append(UsingModuleItem(name: symbolName, alias: alias, excluded: excluded))

      if currentToken === .comma {
        try match(.comma)
      } else {
        break
      }
    }

    try match(.rightBrace)
    return try finishUsingImportList(
      specifier: specifier, items: items, importAll: importAll,
      sawExclude: sawExclude, sawPositive: sawPositive,
      braceSpan: braceSpan, isFileMerge: isFileMerge)
  }

  /// Validate one import list's shape once its items and base set are known
  /// (§3.3). Kept separate from the token loop so both exits share one set of
  /// rules and one wording.
  private func finishUsingImportList(
    specifier: String,
    items: [UsingModuleItem],
    importAll: Bool,
    sawExclude: Bool,
    sawPositive: Bool,
    braceSpan: SourceSpan,
    isFileMerge: Bool
  ) throws -> UsingImportList {
    _ = isFileMerge
    if sawExclude && sawPositive {
      throw ParserError.rejectedConstruct(
        span: braceSpan,
        message: "an import list is either all-positive or all-exclusions; '{ !a, ... }' and '{ a as b, ... }' do not mix"
      )
    }
    if sawExclude && !importAll {
      throw ParserError.rejectedConstruct(
        span: braceSpan,
        message: "'!' excludes from the whole module surface and needs '...'; write '{ !name, ... }'"
      )
    }
    if importAll && sawPositive {
      // A positive item beside `...` is only meaningful as a rename --
      // without `as` it is the whole surface renamed to itself.
      for item in items where !item.excluded && item.alias == nil {
        throw ParserError.rejectedConstruct(
          span: braceSpan,
          message: "'\(item.name)' next to '...' is redundant; either drop it, rename it with 'as', or exclude it with '!'"
        )
      }
    }
    return UsingImportList(items: items, importAll: importAll)
  }

}
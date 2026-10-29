// ParserDeclarations.swift
// Declaration parsing methods for the Koral compiler Parser

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
    let startSpan = currentSpan
    let flags = try parseTopLevelDeclFlags()
    let explicitAccess = flags.explicitAccess
    let access = flags.access

    if currentToken === .letKeyword {
      let keywordSpan = currentSpan
      try match(.letKeyword)
      let quals = try parseDeclQualifiers(keywordSpan: keywordSpan)
      let isIntrinsic = quals.isIntrinsic
      let isForeign = quals.isForeign

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

      let typePrams = try parseTypeParameters()

      if isForeign && !typePrams.isEmpty {
        throw ParserError.foreignFunctionNoGenerics(span: currentSpan)
      }

      // If mutable keyword was detected, it must be a variable declaration
      if mutable {
        if !isValidVariableName(name) {
          throw ParserError.invalidVariableName(span: nameSpan, name: name)
        }
        if isForeign {
          if currentToken === .leftParen && !parenOpensTypeAnnotation() {
            throw ParserError.unexpectedToken(span: currentSpan, got: "foreign let mutable cannot declare a function")
          }
          return try foreignLetDeclaration(name: name, mutable: true, access: access, span: startSpan, nameSpan: nameSpan)
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
        if !isValidVariableName(name) {
          throw ParserError.invalidFunctionName(span: nameSpan, name: name)
        }
        if isForeign {
          return try foreignFunctionDeclaration(name: name, access: access, span: startSpan, nameSpan: nameSpan)
        }
        return try globalFunctionDeclaration(
          name: name, typeParams: typePrams, access: access, isIntrinsic: isIntrinsic,
          span: startSpan, nameSpan: nameSpan)
      } else {
        if !isValidVariableName(name) {
          throw ParserError.invalidVariableName(span: nameSpan, name: name)
        }
        if isForeign {
          return try foreignLetDeclaration(name: name, mutable: false, access: access, span: startSpan, nameSpan: nameSpan)
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

      try match(.identifier(name))

      let typeParams = try parseTypeParameters()

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
        if !typeParams.isEmpty {
          throw ParserError.unexpectedToken(span: currentSpan, got: "Generic type aliases are not supported")
        }
        try match(.equal)
        let targetType = try parseType()
        return .typeAliasDeclaration(
          name: name,
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
        return try foreignTypeDeclaration(name: name, access: access, span: startSpan, nameSpan: nameSpan)
      }
      return try parseStructDeclaration(
        name,
        typeParams: typeParams,
        access: access,
        isIntrinsic: isIntrinsic,
        isMutable: isNominalMutable,
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

    // Optional inheritance list: trait Child ParentA and ParentB { ... }
    var superTraits: [TypeNode] = []
    
    // Parse first parent constraint if present
    if currentToken !== .leftBrace {
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
        var isNamed = false
        if currentToken === .colon {
          isNamed = true
          seenNamedParam = true
          try match(.colon)
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
        }
        let paramType = try parseType()
        // Parse optional default value for named parameters
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
          }
          try match(.equal)
          defaultExpr = try parseDefaultValueLiteral()
          traitDeclaredParameterDefaults.insert("\(name)#\(methodName)#\(pname)")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      // A missing return type is synthesised, not written -- no location.
      var returnType: TypeNode = .identifier("Void", span: .unknown)
      if currentToken !== .semicolon {
        returnType = try parseType()
      }

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
        var isNamed = false
        if currentToken === .colon {
          isNamed = true
          seenNamedParam = true
          try match(.colon)
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
        }
        let paramType = try parseType()
        // Parse optional default value for named parameters
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
          }
          try match(.equal)
          defaultExpr = try parseDefaultValueLiteral()
          implDeclaredParameterDefaults.insert("\(name)#\(pname)")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      // A missing return type is synthesised, not written -- no location.
      var returnType: TypeNode = .identifier("Void", span: .unknown)
      if currentToken !== .semicolon {
        returnType = try parseType()
      }

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
    if currentToken === .asKeyword {
      try match(.asKeyword)
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
        var isNamed = false
        if currentToken === .colon {
          isNamed = true
          seenNamedParam = true
          try match(.colon)
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
        }
        let paramType = try parseType()
        // Parse optional default value for named parameters
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
          }
          try match(.equal)
          defaultExpr = try parseDefaultValueLiteral()
          implDeclaredParameterDefaults.insert("\(name)#\(pname)")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      if currentToken === .equal {
        throw ParserError.missingReturnType(span: currentSpan)
      }
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
    if currentToken !== .equal {
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
      var isNamed = false
      if currentToken === .colon {
        isNamed = true
        seenNamedParam = true
        try match(.colon)
      } else if seenNamedParam {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
      }
      let paramType = try parseType()
      // Parse optional default value for named parameters
      var defaultExpr: ExpressionNode? = nil
      if currentToken === .equal {
        guard isNamed else {
          throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
        }
        try match(.equal)
        defaultExpr = try parseDefaultValueLiteral()
      }
      parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed, defaultValue: defaultExpr))
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

    if currentToken === .equal {
      throw ParserError.missingReturnType(span: currentSpan)
    }
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
    name: String, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
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
      // The name is what makes `name: Type` a NAMED parameter. Both `match`
      // calls below move past it, so the rejection has to remember where it
      // was -- reporting at `currentSpan` points at the type instead.
      let nameSpan = currentSpan
      try match(.identifier(pname))
      var isNamed = false
      if currentToken === .colon {
        isNamed = true
        seenNamedParam = true
        try match(.colon)
      } else if seenNamedParam {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional parameter '\(pname)' cannot appear after named parameters")
      }
      if isNamed {
        throw ParserError.rejectedConstruct(span: nameSpan, message: "Named parameters are not supported in foreign declarations")
      }
      let paramType = try parseType()
      parameters.append((name: pname, mutable: isMut, type: paramType, named: false, defaultValue: nil))
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

    if currentToken === .semicolon {
      throw ParserError.missingReturnType(span: currentSpan)
    }
    let returnType = try parseType()

    if currentToken === .equal {
      throw ParserError.foreignFunctionNoBody(span: currentSpan)
    }

    return .foreignFunctionDeclaration(
      name: name,
      parameters: parameters,
      returnType: returnType,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  private func foreignTypeDeclaration(
    name: String, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
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
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  private func foreignLetDeclaration(
    name: String, mutable: Bool, access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
  ) throws -> GlobalNode {
    let type = try parseType()
    return .foreignLetDeclaration(
      name: name,
      type: type,
      mutable: mutable,
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  // MARK: - Struct Declaration
  
  /// Parse type declaration
  private func parseStructDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier,
    isIntrinsic: Bool, isMutable: Bool = false, span: SourceSpan, nameSpan: SourceSpan
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
      return try parseEnumDeclaration(name, typeParams: typeParams, access: access, span: span, nameSpan: nameSpan)
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
      var isNamed = false
      if currentToken === .colon {
        isNamed = true
        seenNamedField = true
        try match(.colon)
      } else if seenNamedField {
        throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional field '\(paramName)' cannot appear after named fields")
      }
      let paramType = try parseType()
      // Parse optional default value for named fields
      var defaultExpr: ExpressionNode? = nil
      if currentToken === .equal {
        guard isNamed else {
          throw ParserError.unexpectedToken(span: currentSpan, got: "Only named fields can have default values")
        }
        try match(.equal)
        defaultExpr = try parseDefaultValueLiteral()
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
      access: access,
      span: span,
      nameSpan: nameSpan
    )
  }

  // MARK: - Enum Declaration
  
  /// Parse enum declaration (sum type)
  private func parseEnumDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier, span: SourceSpan, nameSpan: SourceSpan
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
        var isNamed = false
        if currentToken === .colon {
          isNamed = true
          seenNamedParam = true
          try match(.colon)
        } else if seenNamedParam {
          throw ParserError.rejectedConstruct(span: currentSpan, message: "Positional field '\(paramName)' cannot appear after named fields")
        }
        let paramType = try parseType()
        // Parse optional default value for named fields
        var defaultExpr: ExpressionNode? = nil
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.unexpectedToken(span: currentSpan, got: "Only named fields can have default values")
          }
          try match(.equal)
          defaultExpr = try parseDefaultValueLiteral()
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
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
          if currentToken === .leftParen {
            throw ParserError.unexpectedToken(span: currentSpan, got: "foreign let mutable cannot declare a function")
          }
          return try foreignLetDeclaration(name: name, mutable: true, access: access, span: startSpan, nameSpan: nameSpan)
        }
        if currentToken === .leftParen {
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        return try globalVariableDeclaration(
          name: name, mutable: true, access: access, span: startSpan, nameSpan: nameSpan)
      }

      // Otherwise check for left paren to determine if it's a function or variable
      if currentToken === .leftParen {
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
        throw ParserError.unexpectedToken(
          span: currentSpan, got: "Access modifier on given declaration")
      }
      let keywordSpan = currentSpan
      try match(.givenKeyword)
      let quals = try parseDeclQualifiers(keywordSpan: keywordSpan)
      if quals.isIntrinsic {
        return try parseIntrinsicGivenDeclaration(span: startSpan)
      }
      return try parseGivenDeclaration(span: startSpan)
    } else if currentToken === .traitKeyword {
      return try parseTraitDeclaration(access: access, span: startSpan)
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
      let methodAccess = try parseAccessModifier(default: .public)

      guard case .identifier(let methodName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "trait member")
      }
      if !isValidVariableName(methodName) {
        throw ParserError.invalidFunctionName(span: currentSpan, name: methodName)
      }
      try match(.identifier(methodName))

      let methodTypeParams = try parseTypeParameters()

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []
      var seenNamedParam = false

      var selfMutable = false
      if currentToken === .mutableKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .selfKeyword || nextToken === .multiply {
          selfMutable = true
          try match(.mutableKeyword)
        }
      }

      if currentToken === .selfKeyword || currentToken === .multiply {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: selfMutable, type: selfType, named: false))
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
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
          }
          try match(.equal)
          let defaultExpr = try parseDefaultValueLiteral()
          parsedParameterDefaults["\(methodName).\(pname)"] = defaultExpr
          traitDeclaredParameterDefaults.insert("\(name)#\(methodName)#\(pname)")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
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
      let methodAccess = try parseAccessModifier(default: .module_private)

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
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []
      var seenNamedParam = false

      var selfMutable = false
      if currentToken === .mutableKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .selfKeyword || nextToken === .multiply {
          selfMutable = true
          try match(.mutableKeyword)
        }
      }

      if currentToken === .selfKeyword || currentToken === .multiply {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: selfMutable, type: selfType, named: false))
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
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
          }
          try match(.equal)
          let defaultExpr = try parseDefaultValueLiteral()
          parsedParameterDefaults["\(name).\(pname)"] = defaultExpr
          implDeclaredParameterDefaults.insert("\(name)#\(pname)")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
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
      let methodAccess = try parseAccessModifier(default: .module_private)

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "given member")
      }
      if !isValidVariableName(name) {
        throw ParserError.invalidFunctionName(span: currentSpan, name: name)
      }
      try match(.identifier(name))

      let typeParams = try parseTypeParameters()

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []
      var seenNamedParam = false

      var selfMutable = false
      if currentToken === .mutableKeyword {
        let nextToken = lexer.peekNextToken()
        if nextToken === .selfKeyword || nextToken === .multiply {
          selfMutable = true
          try match(.mutableKeyword)
        }
      }

      if currentToken === .selfKeyword || currentToken === .multiply {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: selfMutable, type: selfType, named: false))
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
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
          }
          try match(.equal)
          let defaultExpr = try parseDefaultValueLiteral()
          parsedParameterDefaults["\(name).\(pname)"] = defaultExpr
          implDeclaredParameterDefaults.insert("\(name)#\(pname)")
        }
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
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
    currentToken === .publicKeyword || currentToken === .filePrivateKeyword || currentToken === .modulePrivateKeyword || currentToken === .packagePrivateKeyword
  }

  /// Reads the leading access modifier only. `foreign` / `intrinsic` are NOT
  /// prefix modifiers: they qualify the thing being declared and sit in the
  /// slot right after the declaration keyword -- the slot `type mutable` and
  /// `let mutable` established -- where `parseDeclQualifiers` reads them.
  private func parseTopLevelDeclFlags() throws -> TopLevelDeclFlags {
    var explicitAccess: AccessModifier? = nil
    var access: AccessModifier = .module_private

    while true {
      if isCurrentAccessModifierToken() {
        if let existingAccess = explicitAccess {
          throw ParserError.invalidAccessModifierOrder(
            span: currentSpan,
            message: "Invalid access modifier order: '\(existingAccess.description) \(currentToken.description)'."
          )
        }
        explicitAccess = try parseExplicitAccessModifier()
        access = explicitAccess ?? .module_private
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
    if currentToken === .publicKeyword || currentToken === .filePrivateKeyword || currentToken === .modulePrivateKeyword || currentToken === .packagePrivateKeyword {
      let next = currentToken.description
      throw ParserError.invalidAccessModifierOrder(
        span: currentSpan,
        message: "Invalid access modifier order: '\(accessText) \(next)'"
      )
    }
  }

  func parseExplicitAccessModifier() throws -> AccessModifier? {
    if currentToken === .filePrivateKeyword {
      try match(.filePrivateKeyword)
      return .file_private
    } else if currentToken === .modulePrivateKeyword {
      try match(.modulePrivateKeyword)
      return .module_private
    } else if currentToken === .packagePrivateKeyword {
      try match(.packagePrivateKeyword)
      return .package_private
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
    var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []
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
      if currentToken === .equal {
        guard isNamed else {
          throw ParserError.defaultValuesRequireNamedParameter(span: currentSpan)
        }
        try match(.equal)
        let defaultExpr = try parseDefaultValueLiteral()
        parsedParameterDefaults["\(name).\(pname)"] = defaultExpr
      }
      parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
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
    var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []
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
      parameters.append((name: pname, mutable: isMut, type: paramType, named: false))
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
    var parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier, named: Bool)] = []
    var seenNamedField = false

    while currentToken !== .rightParen {
      let fieldAccess = try parseAccessModifier(default: .public)

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
      if currentToken === .equal {
        guard isNamed else {
          throw ParserError.unexpectedToken(span: currentSpan, got: "Only named fields can have default values")
        }
        try match(.equal)
        let defaultExpr = try parseDefaultValueLiteral()
        parsedParameterDefaults["\(name).\(paramName)"] = defaultExpr
      }

      parameters.append(
        (name: paramName, type: paramType, mutable: fieldMutable, access: fieldAccess, named: isNamed))

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

      var parameters: [(name: String, type: TypeNode, named: Bool)] = []
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
        if currentToken === .equal {
          guard isNamed else {
            throw ParserError.unexpectedToken(span: currentSpan, got: "Only named fields can have default values")
          }
          try match(.equal)
          let defaultExpr = try parseDefaultValueLiteral()
          parsedParameterDefaults["\(caseName).\(paramName)"] = defaultExpr
        }
        parameters.append((name: paramName, type: paramType, named: isNamed))

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

    var items: [UsingModuleItem]? = nil
    if currentToken === .leftBrace {
      let parsed = try parseUsingImportList(isFileMerge: isFileMerge, specifier: specifier)
      items = parsed
    }

    if isFileMerge {
      if items != nil {
        throw ParserError.rejectedConstruct(
          span: specifierSpan,
          message: "File merge '\(specifier)' takes no import list; it merges the whole file"
        )
      }
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
    return UsingDeclaration(specifier: specifier, items: items, span: span)
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

  /// `{ Name, Other as Alias }` -- the filter on an import (§3.3).
  /// Omitting the braces means "everything"; writing them empty means nothing,
  /// which is not a thing to ask for (§7.4).
  private func parseUsingImportList(isFileMerge: Bool, specifier: String) throws -> [UsingModuleItem] {
    let braceSpan = currentSpan
    try match(.leftBrace)
    var items: [UsingModuleItem] = []

    while currentToken !== .rightBrace {
      if currentToken === .range {
        // `{ .. }` used to mean "everything". Omitting the list means that now
        // (§3), so `..` is not a name anyone could import -- point at it and
        // say what replaces it (§8).
        throw ParserError.rejectedConstruct(
          span: currentSpan,
          message: "\"..\" is not an import item; omit the list to import every visible member of \"\(specifier)\""
        )
      }
      guard case .identifier(let symbolName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description, context: "import item")
      }
      let nameSpan = currentSpan
      try match(currentToken)

      var alias: String? = nil
      if currentToken === .asKeyword {
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

      items.append(UsingModuleItem(name: symbolName, alias: alias))

      if currentToken === .comma {
        try match(.comma)
      } else {
        break
      }
    }

    try match(.rightBrace)
    if items.isEmpty {
      if isFileMerge {
        throw ParserError.rejectedConstruct(
          span: braceSpan,
          message: "File merge '\(specifier)' takes no import list; it merges the whole file"
        )
      }
      throw ParserError.rejectedConstruct(
        span: braceSpan,
        message: "import list cannot be empty; omit it to import every visible member of \"\(specifier)\""
      )
    }
    return items
  }

}
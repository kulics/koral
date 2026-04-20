// ParserDeclarations.swift
// Declaration parsing methods for the Koral compiler Parser

/// Extension containing all declaration parsing methods
extension Parser {

  private func parseSelfReceiverType() throws -> TypeNode {
    try match(.selfKeyword)
    if currentToken === .colon {
      throw ParserError.unexpectedToken(span: currentSpan, got: "'self' parameter cannot use named parameter syntax")
    }

    var selfType: TypeNode = .inferredSelf
    if currentToken === .mutKeyword {
      try match(.mutKeyword)
      if currentToken !== .refKeyword {
        throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
      }
      try match(.refKeyword)
      selfType = .reference(selfType, mutable: true)
    } else if currentToken === .refKeyword {
      try match(.refKeyword)
      selfType = .reference(selfType, mutable: false)
    }

    if currentToken !== .comma && currentToken !== .rightParen {
      throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
    }
    return selfType
  }
  
  // MARK: - Global Declaration Parsing
  
  /// Parse global declaration
  func parseGlobalDeclaration() throws -> GlobalNode {
    let startSpan = currentSpan
    let explicitAccess = try parseExplicitAccessModifier()
    let access = explicitAccess ?? .protected

    var isIntrinsic = false
    var isForeign = false
    if currentToken === .intrinsicKeyword {
      try match(.intrinsicKeyword)
      isIntrinsic = true
    }

    if currentToken === .foreignKeyword {
      try match(.foreignKeyword)
      if isIntrinsic {
        throw ParserError.foreignAndIntrinsicConflict(span: currentSpan)
      }
      isForeign = true
    }

    if currentToken === .letKeyword {
      try match(.letKeyword)

      // Check for mut keyword first
      var mutable = false
      if currentToken === .mutKeyword {
        try match(.mutKeyword)
        mutable = true
      }

      let typePrams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }

      if !isValidVariableName(name) {
        throw ParserError.invalidVariableName(span: currentSpan, name: name)
      }

      try match(.identifier(name))

      if isForeign && !typePrams.isEmpty {
        throw ParserError.foreignFunctionNoGenerics(span: currentSpan)
      }

      // If mut keyword was detected, it must be a variable declaration
      if mutable {
        if isForeign {
          if currentToken === .leftParen {
            throw ParserError.unexpectedToken(span: currentSpan, got: "foreign let mut cannot declare a function")
          }
          return try foreignLetDeclaration(name: name, mutable: true, access: access, span: startSpan)
        }
        if currentToken === .leftParen {
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        return try globalVariableDeclaration(
          name: name, mutable: true, access: access, span: startSpan)
      }

      // Otherwise check for left paren to determine if it's a function or variable
      if currentToken === .leftParen {
        if isForeign {
          return try foreignFunctionDeclaration(name: name, access: access, span: startSpan)
        }
        return try globalFunctionDeclaration(
          name: name, typeParams: typePrams, access: access, isIntrinsic: isIntrinsic,
          span: startSpan)
      } else {
        if isForeign {
          return try foreignLetDeclaration(name: name, mutable: false, access: access, span: startSpan)
        }
        if isIntrinsic {
          throw ParserError.unexpectedToken(
            span: currentSpan, got: "intrinsic variable not supported")
        }
        return try globalVariableDeclaration(
          name: name, mutable: false, access: access, span: startSpan)
      }
    } else if currentToken === .typeKeyword {
      try match(.typeKeyword)

      // Check for optional C name: foreign type "cname" Name(...)
      var cname: String? = nil
      if isForeign, case .string(let cnameValue) = currentToken {
        cname = cnameValue
        try match(.string(cnameValue))
      }

      let typeParams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }

      if !isValidTypeName(name) {
        throw ParserError.invalidTypeName(span: currentSpan, name: name)
      }

      try match(.identifier(name))

      // Check for type alias: type Name = TargetType
      if currentToken === .equal {
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
          span: startSpan
        )
      }

      if isForeign {
        return try foreignTypeDeclaration(name: name, cname: cname, access: access, span: startSpan)
      }
      return try parseStructDeclaration(
        name, typeParams: typeParams, access: access, isIntrinsic: isIntrinsic, span: startSpan)
    } else if currentToken === .givenKeyword {
      if explicitAccess != nil {
        throw ParserError.unexpectedToken(
          span: currentSpan, got: "Access modifier on given declaration")
      }
      if isIntrinsic {
        return try parseIntrinsicGivenDeclaration(span: startSpan)
      }
      return try parseGivenDeclaration(span: startSpan)
    } else if currentToken === .traitKeyword {
      if isIntrinsic {
        throw ParserError.unexpectedToken(span: currentSpan, got: "intrinsic trait not supported")
      }
      return try parseTraitDeclaration(access: access, span: startSpan)
    } else {
      throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
    }
  }

  // MARK: - Trait Declaration
  
  private func parseTraitDeclaration(access: AccessModifier, span: SourceSpan) throws -> GlobalNode {
    try match(.traitKeyword)

    // Parse optional type parameters for generic traits: [T Any]Iterator
    let typeParams = try parseTypeParameters()

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
    }

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }
    try match(.identifier(name))

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
      let methodTypeParams = try parseTypeParameters()

      guard case .identifier(let methodName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(methodName))

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []

      if currentToken === .selfKeyword {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: false, type: selfType, named: false))
        if currentToken === .comma {
          try match(.comma)
        }
      }

      while currentToken !== .rightParen {
        var isMut = false
        if currentToken === .mutKeyword {
          isMut = true
          try match(.mutKeyword)
        }
        guard case .identifier(let pname) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(pname))
        var isNamed = false
        if currentToken === .colon {
          try match(.colon)
          isNamed = true
        }
        let paramType = try parseType()
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      var returnType: TypeNode = .identifier("Void")
      if currentToken !== .semicolon {
        returnType = try parseType()
      }

      if currentToken === .equal {
        throw ParserError.unexpectedToken(span: currentSpan, got: "Trait method should not have body")
      }
      
      // Use newline-based termination for trait method declarations
      try consumeOptionalSemicolon()

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
      span: span
    )
  }

  // MARK: - Given Declarations
  
  private func parseIntrinsicGivenDeclaration(span: SourceSpan) throws -> GlobalNode {
    try match(.givenKeyword)
    let typeParams = try parseTypeParameters()
    let type = try parseType()
    try match(.leftBrace)

    var methods: [IntrinsicMethodDeclaration] = []

    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier(default: .protected)

      // Intrinsic methods inside intrinsic given are implicitly intrinsic, so no need for keyword check?
      // Or do we disallow nested modifiers?
      // For simplicity, skip specific 'intrinsic' keyword check on methods since the whole block is intrinsic.
      // But verify no body.

      let methodTypeParams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []

      if currentToken === .selfKeyword {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: false, type: selfType, named: false))
        if currentToken === .comma {
          try match(.comma)
        }
      }

      while currentToken !== .rightParen {
        var isMut = false
        if currentToken === .mutKeyword {
          isMut = true
          try match(.mutKeyword)
        }
        guard case .identifier(let pname) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(pname))
        var isNamed = false
        if currentToken === .colon {
          try match(.colon)
          isNamed = true
        }
        let paramType = try parseType()
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      var returnType: TypeNode = .identifier("Void")
      if currentToken !== .semicolon {
        returnType = try parseType()
      }

      // Must not have body
      if currentToken === .equal {
        throw ParserError.unexpectedToken(
          span: currentSpan, got: "Intrinsic given method should not have body")
      }
      
      // Use newline-based termination for intrinsic method declarations
      try consumeOptionalSemicolon()

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
    try match(.givenKeyword)
    let typeParams = try parseTypeParameters()
    let type = try parseType()
    if currentToken === .notKeyword {
      try match(.notKeyword)
      guard case .identifier(let traitName) = currentToken else {
        throw ParserError.expectedTypeIdentifier(span: currentSpan, got: currentToken.description)
      }
      if !isValidTypeName(traitName) {
        throw ParserError.invalidTypeName(span: currentSpan, name: traitName)
      }
      try match(.identifier(traitName))
      return .givenNotTraitDeclaration(typeParams: typeParams, type: type, traitName: traitName, span: span)
    }

    var trait: TypeNode? = nil
    if currentToken !== .leftBrace {
      trait = try parseType()
    }
    try match(.leftBrace)
    var methods: [MethodDeclaration] = []
    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier(default: .protected)

      let typeParams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []

      if currentToken === .selfKeyword {
        let selfType = try parseSelfReceiverType()
        parameters.append((name: "self", mutable: false, type: selfType, named: false))
        if currentToken === .comma {
          try match(.comma)
        }
      }

      while currentToken !== .rightParen {
        var isMut = false
        if currentToken === .mutKeyword {
          isMut = true
          try match(.mutKeyword)
        }
        guard case .identifier(let pname) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(pname))
        var isNamed = false
        if currentToken === .colon {
          try match(.colon)
          isNamed = true
        }
        let paramType = try parseType()
        parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)

      var returnType: TypeNode = .identifier("Void")
      if currentToken !== .equal {
        returnType = try parseType()
      }

      try match(.equal)
      let body = try expression()
      try consumeOptionalSemicolon()

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

  func parseExplicitAccessModifier() throws -> AccessModifier? {
    if currentToken === .privateKeyword {
      try match(.privateKeyword)
      return .private
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
    name: String, mutable: Bool, access: AccessModifier, span: SourceSpan
  ) throws -> GlobalNode {
    var type: TypeNode = .identifier("Int")
    if currentToken !== .equal {
      type = try parseType()
    }

    try match(.equal)
    let value = try expression()
    return .globalVariableDeclaration(
      name: name, type: type, value: value, mutable: mutable, access: access, span: span)
  }

  // MARK: - Type Parameters
  
  func parseTypeParameters() throws -> [TypeParameterDecl] {
    var parameters: [TypeParameterDecl] = []
    if currentToken === .leftBracket {
      try match(.leftBracket)
      while currentToken !== .rightBracket {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(paramName))

        var constraints: [TypeNode] = []
        constraints.append(try parseTraitConstraint())
        while currentToken === .andKeyword {
          try match(.andKeyword)
          constraints.append(try parseTraitConstraint())
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
    // Support both simple identifiers (e.g., Any, Equatable) and generic types (e.g., [T]Iterator)
    if currentToken === .leftBracket {
      // Generic type constraint like [T]Iterator
      return try parseType()
    }
    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(span: currentSpan, got: currentToken.description)
    }
    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }
    try match(.identifier(name))
    return .identifier(name)
  }

  // MARK: - Function Declaration
  
  /// Parse global function declaration with optional 'own'/'ref' modifiers for params and return type
  private func globalFunctionDeclaration(
    name: String, typeParams: [TypeParameterDecl], access: AccessModifier,
    isIntrinsic: Bool, span: SourceSpan
  ) throws -> GlobalNode {
    try match(.leftParen)
    var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []
    while currentToken !== .rightParen {
      // 仅支持可选的前缀 mut；不再支持 own/ref
      var isMut = false
      if currentToken === .mutKeyword {
        isMut = true
        try match(.mutKeyword)
      }
      guard case .identifier(let pname) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(pname))
      var isNamed = false
      if currentToken === .colon {
        try match(.colon)
        isNamed = true
      }
      let paramType = try parseType()
      parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

    var returnType: TypeNode = .identifier("Void")
    if currentToken !== .equal {
      returnType = try parseType()
    }

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
        span: span
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
        span: span
      )
    }
  }

  // MARK: - Foreign Declarations

  private func foreignFunctionDeclaration(
    name: String, access: AccessModifier, span: SourceSpan
  ) throws -> GlobalNode {
    try match(.leftParen)
    var parameters: [(name: String, mutable: Bool, type: TypeNode, named: Bool)] = []
    while currentToken !== .rightParen {
      var isMut = false
      if currentToken === .mutKeyword {
        isMut = true
        try match(.mutKeyword)
      }
      guard case .identifier(let pname) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(pname))
      var isNamed = false
      if currentToken === .colon {
        try match(.colon)
        isNamed = true
      }
      let paramType = try parseType()
      parameters.append((name: pname, mutable: isMut, type: paramType, named: isNamed))
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

    // Named parameters are not supported in foreign declarations
    for param in parameters {
      if param.named {
        throw ParserError.unexpectedToken(span: currentSpan, got: "Named parameters are not supported in foreign declarations")
      }
    }

    var returnType: TypeNode = .identifier("Void")
    if currentToken !== .semicolon && !shouldTerminateStatement() {
      returnType = try parseType()
    }

    if currentToken === .equal {
      throw ParserError.foreignFunctionNoBody(span: currentSpan)
    }

    return .foreignFunctionDeclaration(
      name: name,
      parameters: parameters,
      returnType: returnType,
      access: access,
      span: span
    )
  }

  private func foreignTypeDeclaration(
    name: String, cname: String?, access: AccessModifier, span: SourceSpan
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
          throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
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
      cname: cname,
      fields: fields,
      access: access,
      span: span
    )
  }

  private func foreignLetDeclaration(
    name: String, mutable: Bool, access: AccessModifier, span: SourceSpan
  ) throws -> GlobalNode {
    let type = try parseType()
    return .foreignLetDeclaration(
      name: name,
      type: type,
      mutable: mutable,
      access: access,
      span: span
    )
  }

  // MARK: - Struct Declaration
  
  /// Parse type declaration
  private func parseStructDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier,
    isIntrinsic: Bool, span: SourceSpan
  ) throws -> GlobalNode {
    if isIntrinsic {
      if currentToken === .leftParen {
        throw ParserError.unexpectedToken(
          span: currentSpan, got: "Intrinsic type should not have body")
      }
      return .intrinsicTypeDeclaration(
        name: name, typeParameters: typeParams, access: access, span: span)
    }

    if currentToken === .leftBrace {
      return try parseEnumDeclaration(name, typeParams: typeParams, access: access, span: span)
    }

    try match(.leftParen)
    var parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier, named: Bool)] = []

    while currentToken !== .rightParen {
      let fieldAccess = try parseAccessModifier(default: .public)

      // Check for mut keyword for the field
      var fieldMutable = false
      if currentToken === .mutKeyword {
        try match(.mutKeyword)
        fieldMutable = true
      }

      guard case .identifier(let paramName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(paramName))
      var isNamed = false
      if currentToken === .colon {
        try match(.colon)
        isNamed = true
      }
      let paramType = try parseType()

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
      access: access,
      span: span
    )
  }

  // MARK: - Enum Declaration
  
  /// Parse enum declaration (sum type)
  private func parseEnumDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier, span: SourceSpan
  ) throws -> GlobalNode {
    try match(.leftBrace)
    var cases: [EnumCaseDeclaration] = []

    while currentToken !== .rightBrace {
      guard case .identifier(let caseName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(caseName))

      var parameters: [(name: String, type: TypeNode, named: Bool)] = []
      try match(.leftParen)

      while currentToken !== .rightParen {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(paramName))
        var isNamed = false
        if currentToken === .colon {
          try match(.colon)
          isNamed = true
        }
        let paramType = try parseType()
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
      span: span
    )
  }

  // MARK: - Using Declarations

  /// Check if current position is a foreign using declaration
  func isForeignUsingDeclaration() -> Bool {
    if currentToken === .foreignKeyword {
      let state = lexer.saveState()
      let savedToken = currentToken
      do {
        let nextToken = try lexer.getNextToken()
        lexer.restoreState(state)
        currentToken = savedToken
        return nextToken === .usingKeyword
      } catch {
        lexer.restoreState(state)
        currentToken = savedToken
        return false
      }
    }
    return false
  }

  /// Parse foreign using declaration
  func parseForeignUsingDeclaration() throws -> GlobalNode {
    let startSpan = currentSpan
    try match(.foreignKeyword)
    try match(.usingKeyword)

    let libraryName: String
    if case .string(let name) = currentToken {
      libraryName = name
      try match(currentToken)
    } else if case .identifier(let name) = currentToken {
      // Legacy support: foreign using m → foreign using "m"
      libraryName = name
      try match(currentToken)
    } else {
      throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description, expected: "string literal")
    }

    let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
    return .foreignUsingDeclaration(libraryName: libraryName, span: span)
  }
  
  /// Check if current position is a using declaration
  func isUsingDeclaration() -> Bool {
    // using ...
    if currentToken === .usingKeyword {
      return true
    }
    // public/protected/private using ...
    if currentToken === .publicKeyword || currentToken === .protectedKeyword || currentToken === .privateKeyword {
      let state = lexer.saveState()
      let savedToken = currentToken
      do {
        // Get the token after the access modifier
        let nextToken = try lexer.getNextToken()
        lexer.restoreState(state)
        currentToken = savedToken
        return nextToken === .usingKeyword
      } catch {
        lexer.restoreState(state)
        currentToken = savedToken
        return false
      }
    }
    return false
  }
  
  /// Parse using declaration
  func parseUsingDeclaration() throws -> UsingDeclaration {
    let startSpan = currentSpan
    let explicitAccess = try parseExplicitAccessModifier()
    let access = explicitAccess ?? .private
    
    try match(.usingKeyword)
    
    // Check if next token is a string literal → file-based using
    if case .string(let fileName) = currentToken {
      try match(currentToken)
      
      // Parse optional alias: using "file" as Name
      let alias = try parseUsingAliasIfPresent()
      
      // Validate: alias must start with uppercase
      if let alias, let first = alias.first, !first.isUppercase {
        throw ParserError.invalidUsingAliasCase(
          span: startSpan,
          alias: alias,
          referenced: fileName,
          expectedUppercase: true
        )
      }
      
      // Validate: merge (no alias) cannot have explicit access modifier
      if alias == nil && explicitAccess != nil {
        throw ParserError.submoduleMergeNoAccessModifier(span: startSpan)
      }
      
      let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
      return UsingDeclaration(
        pathKind: .fileUsing,
        fileName: fileName,
        alias: alias,
        access: access,
        span: span
      )
    }
    
    // Otherwise, parse identifier-based using (external / parent)
    let (pathKind, pathSegments, importedSymbol, isBatchImport) = try parseUsingIdentifierPath()

    if isBatchImport && currentToken === .asKeyword {
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "';' or end of declaration"
      )
    }

    let alias = try parseUsingAliasIfPresent()
    try validateUsingAliasCase(
      alias: alias,
      pathKind: pathKind,
      pathSegments: pathSegments,
      span: startSpan
    )
    let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
    return UsingDeclaration(
      pathKind: pathKind,
      pathSegments: pathSegments,
      alias: alias,
      importedSymbol: importedSymbol,
      isBatchImport: isBatchImport,
      access: access,
      span: span
    )
  }

  private func parseUsingIdentifierPath() throws -> (
    kind: UsingPathKind,
    segments: [String],
    importedSymbol: String?,
    isBatchImport: Bool
  ) {
    var kind: UsingPathKind
    var segments: [String] = []
    var isBatchImport = false
    var inLeadingSuperChain = false

    switch currentToken {
    case .selfKeyword, .selfTypeKeyword:
      throw ParserError.invalidUsingPath(
        span: currentSpan,
        path: "Self",
        reason: "'Self' is not allowed in using declarations. Use string syntax: using \"file_name\" or using \"file_name\" as Name"
      )
    case .superKeyword:
      kind = .parent
      segments.append("Super")
      inLeadingSuperChain = true
      try match(.superKeyword)
    case .identifier(let name):
      kind = .path
      segments.append(name)
      try match(currentToken)
    default:
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "Super, module name, or string literal"
      )
    }

    while currentToken === .dot {
      try match(.dot)

      if currentToken === .multiply {
        try match(.multiply)
        isBatchImport = true
        break
      }

      switch currentToken {
      case .identifier(let segment):
        segments.append(segment)
        inLeadingSuperChain = false
        try match(currentToken)
      case .superKeyword:
        guard kind == .parent && inLeadingSuperChain else {
          throw ParserError.invalidUsingPath(
            span: currentSpan,
            path: "Super",
            reason: "'Super' can only appear as leading segments"
          )
        }
        segments.append("Super")
        try match(.superKeyword)
      default:
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: currentToken.description,
          expected: "identifier or '*'"
        )
      }
    }

    if inLeadingSuperChain {
      let hasConcreteItem = segments.contains { $0 != "Super" }
      if !hasConcreteItem {
        throw ParserError.usingRequiresConcreteItem(span: currentSpan, base: "Super")
      }
    }

    // Explicit member import normalization
    var importedSymbol: String? = nil
    if !isBatchImport {
      if inLeadingSuperChain {
        // Super paths: using Super.Mod.Symbol -> importedSymbol=Symbol
        let concreteCount = segments.filter { $0 != "Super" }.count
        if concreteCount >= 2 {
          importedSymbol = segments.removeLast()
        }
      } else {
        // Non-Super paths: using Std.Io.Reader -> importedSymbol=Reader
        if segments.count >= 3 {
          importedSymbol = segments.removeLast()
        }
      }
    }

    return (kind, segments, importedSymbol, isBatchImport)
  }

  private func parseUsingAliasIfPresent() throws -> String? {
    guard currentToken === .asKeyword else {
      return nil
    }
    try match(.asKeyword)
    guard case .identifier(let alias) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
    }
    try match(currentToken)
    return alias
  }

  private func validateUsingAliasCase(
    alias: String?,
    pathKind: UsingPathKind,
    pathSegments: [String],
    span: SourceSpan
  ) throws {
    guard let alias, !alias.isEmpty else {
      return
    }

    let referencedIdentifier: String? = {
      switch pathKind {
      case .path:
        return pathSegments.last
      case .parent:
        return pathSegments.last(where: { $0 != "Super" })
      case .fileUsing:
        return nil
      }
    }()

    guard let referencedIdentifier, let referencedFirst = referencedIdentifier.first, let aliasFirst = alias.first else {
      return
    }

    if referencedFirst.isUppercase && !aliasFirst.isUppercase {
      throw ParserError.invalidUsingAliasCase(
        span: span,
        alias: alias,
        referenced: referencedIdentifier,
        expectedUppercase: true
      )
    }

    if referencedFirst.isLowercase && !aliasFirst.isLowercase {
      throw ParserError.invalidUsingAliasCase(
        span: span,
        alias: alias,
        referenced: referencedIdentifier,
        expectedUppercase: false
      )
    }
  }

}

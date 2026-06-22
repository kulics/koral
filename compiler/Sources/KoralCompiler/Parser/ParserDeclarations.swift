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
    if currentToken === .refKeyword {
      try match(.refKeyword)
      let mutable = currentToken === .mutKeyword
      if mutable {
        try match(.mutKeyword)
      }
      selfType = .reference(selfType, mutable: mutable)
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

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }

      if !isValidVariableName(name) {
        throw ParserError.invalidVariableName(span: currentSpan, name: name)
      }

      try match(.identifier(name))

      let typePrams = try parseTypeParameters()

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

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }

      if !isValidTypeName(name) {
        throw ParserError.invalidTypeName(span: currentSpan, name: name)
      }

      try match(.identifier(name))

      let typeParams = try parseTypeParameters()

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

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
    }

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
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
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(methodName))

      let methodTypeParams = try parseTypeParameters()

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

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))

      let methodTypeParams = try parseTypeParameters()

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
    if currentToken === .asKeyword {
      try match(.asKeyword)
      trait = try parseType()
    }
    try match(.leftBrace)
    var methods: [MethodDeclaration] = []
    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier(default: .protected)

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))

      let typeParams = try parseTypeParameters()

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

      if currentToken === .equal {
        throw ParserError.missingReturnType(span: currentSpan)
      }
      let returnType = try parseType()

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
      if currentToken === .publicKeyword {
        try match(.publicKeyword)
        return .protectedPublic
      }
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

    if currentToken === .semicolon || shouldTerminateStatement() {
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

  /// Check if current position is a using declaration
  func isUsingDeclaration() -> Bool {
    currentToken === .usingKeyword
  }
  
  /// Parse using declaration
  func parseUsingDeclaration() throws -> UsingDeclaration {
    let startSpan = currentSpan
    try match(.usingKeyword)
    
    // Check if next token is a string literal → file-based using
    if case .string(let fileName) = currentToken {
      try match(currentToken)

      if currentToken === .asKeyword {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: currentToken.description,
          expected: "file merge syntax no longer supports aliases; declare a module in koral.json instead"
        )
      }

      let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
      return UsingDeclaration(
        kind: .fileMerge(path: fileName),
        span: span
      )
    }

    if case .identifier = currentToken, isModuleUsingDeclarationStart() {
      let (modulePath, moduleItems) = try parseExplicitModuleUsing()
      let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
      return UsingDeclaration(
        kind: .moduleImport(pathSegments: modulePath, items: moduleItems),
        span: span
      )
    }

    throw ParserError.unexpectedToken(
      span: currentSpan,
      got: currentToken.description,
      expected: "string literal for file merge, or module import like 'std::io { Reader }'"
    )
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

  private func isModuleUsingDeclarationStart() -> Bool {
    let state = lexer.saveState()
    let savedToken = currentToken
    defer {
      lexer.restoreState(state)
      currentToken = savedToken
    }

    guard case .identifier = currentToken else {
      return false
    }

    do {
      let nextToken = try lexer.getNextToken()
      return nextToken === .doubleColon || nextToken === .leftBrace
    } catch {
      return false
    }
  }

  private func parseExplicitModuleUsing() throws -> ([String], [UsingModuleItem]) {
    var pathSegments: [String] = []

    guard case .identifier(let firstSegment) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
    }
    pathSegments.append(moduleFileNameToIdentifier(firstSegment))
    try match(currentToken)

    while currentToken === .doubleColon {
      try match(.doubleColon)
      guard case .identifier(let segment) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      pathSegments.append(moduleFileNameToIdentifier(segment))
      try match(currentToken)
    }

    try match(.leftBrace)
    var items: [UsingModuleItem] = []
    var sawAllPublic = false

    while currentToken !== .rightBrace {
      if currentToken === .range {
        if !items.isEmpty {
          throw ParserError.unexpectedToken(
            span: currentSpan,
            got: currentToken.description,
            expected: "'..' must be the only item in a module import list"
          )
        }
        try match(.range)
        items.append(UsingModuleItem(kind: .allPublic))
        sawAllPublic = true
      } else {
        guard case .identifier(let symbolName) = currentToken else {
          throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
        }
        try match(currentToken)
        let alias = try parseUsingAliasIfPresent()
        if let alias {
          if isValidTypeName(symbolName) && !isValidTypeName(alias) {
            throw ParserError.invalidUsingAliasCase(
              span: currentSpan,
              alias: alias,
              referenced: symbolName,
              expectedUppercase: true
            )
          }
          if isValidVariableName(symbolName) && !isValidVariableName(alias) {
            throw ParserError.invalidUsingAliasCase(
              span: currentSpan,
              alias: alias,
              referenced: symbolName,
              expectedUppercase: false
            )
          }
        }
        items.append(UsingModuleItem(kind: .symbol, name: symbolName, alias: alias))
      }

      if currentToken === .comma {
        if sawAllPublic {
          throw ParserError.unexpectedToken(
            span: currentSpan,
            got: currentToken.description,
            expected: "'..' must not be combined with other imports"
          )
        }
        try match(.comma)
      } else {
        break
      }
    }

    try match(.rightBrace)
    if items.isEmpty {
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "at least one import item"
      )
    }
    return (pathSegments, items)
  }

}

// ParserDeclarations.swift
// Declaration parsing methods for the Koral compiler Parser

/// Extension containing all declaration parsing methods
extension Parser {
  
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
      var parameters: [(name: String, mutable: Bool, type: TypeNode)] = []

      if currentToken === .selfKeyword {
        try match(.selfKeyword)
        var selfType: TypeNode = .inferredSelf
        if currentToken === .refKeyword {
          try match(.refKeyword)
          selfType = .reference(selfType)
        }
        if currentToken !== .comma && currentToken !== .rightParen {
          throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
        }
        parameters.append((name: "self", mutable: false, type: selfType))
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
        let paramType = try parseType()
        parameters.append((name: pname, mutable: isMut, type: paramType))
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
      var parameters: [(name: String, mutable: Bool, type: TypeNode)] = []

      if currentToken === .selfKeyword {
        try match(.selfKeyword)
        var selfType: TypeNode = .inferredSelf
        if currentToken === .refKeyword {
          try match(.refKeyword)
          selfType = .reference(selfType)
        }
        if currentToken !== .comma && currentToken !== .rightParen {
          throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
        }
        parameters.append((name: "self", mutable: false, type: selfType))
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
        let paramType = try parseType()
        parameters.append((name: pname, mutable: isMut, type: paramType))
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
      var parameters: [(name: String, mutable: Bool, type: TypeNode)] = []

      if currentToken === .selfKeyword {
        try match(.selfKeyword)
        var selfType: TypeNode = .inferredSelf
        if currentToken === .refKeyword {
          try match(.refKeyword)
          selfType = .reference(selfType)
        }
        if currentToken !== .comma && currentToken !== .rightParen {
          throw ParserError.invalidReceiverParameterSyntax(span: currentSpan)
        }
        parameters.append((name: "self", mutable: false, type: selfType))
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
        let paramType = try parseType()
        parameters.append((name: pname, mutable: isMut, type: paramType))
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
    var parameters: [(name: String, mutable: Bool, type: TypeNode)] = []
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
      let paramType = try parseType()
      parameters.append((name: pname, mutable: isMut, type: paramType))
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
    var parameters: [(name: String, mutable: Bool, type: TypeNode)] = []
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
      let paramType = try parseType()
      parameters.append((name: pname, mutable: isMut, type: paramType))
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

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
    if currentToken === .leftBrace {
      throw ParserError.foreignTypeNoBody(span: currentSpan)
    }

    var fields: [(name: String, type: TypeNode)]? = nil
    if currentToken === .leftParen {
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
      return try parseUnionDeclaration(name, typeParams: typeParams, access: access, span: span)
    }

    try match(.leftParen)
    var parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)] = []

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
      let paramType = try parseType()

      parameters.append(
        (name: paramName, type: paramType, mutable: fieldMutable, access: fieldAccess))

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

  // MARK: - Union Declaration
  
  /// Parse union declaration (sum type)
  private func parseUnionDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier, span: SourceSpan
  ) throws -> GlobalNode {
    try match(.leftBrace)
    var cases: [UnionCaseDeclaration] = []

    while currentToken !== .rightBrace {
      guard case .identifier(let caseName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(caseName))

      var parameters: [(name: String, type: TypeNode)] = []
      try match(.leftParen)

      while currentToken !== .rightParen {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(paramName))
        let paramType = try parseType()
        parameters.append((name: paramName, type: paramType))

        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)
      
      cases.append(UnionCaseDeclaration(name: caseName, parameters: parameters))
      
      // Use comma as separator between variants (optional trailing comma)
      if currentToken === .comma {
        try match(.comma)
      }
    }

    try match(.rightBrace)


    return .globalUnionDeclaration(
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

    guard case .string(let libraryName) = currentToken else {
      throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description, expected: "string literal")
    }
    try match(currentToken)

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
    
    // Determine path type based on first token
    if case .string(let filename) = currentToken {
      // using "filename" - 文件合并
      let fileMergeSpan = currentSpan
      try match(currentToken)

      if filename.contains("/") || filename.contains("\\") {
        throw ParserError.fileMergePathNotAllowed(span: fileMergeSpan, path: filename)
      }
      
      // 文件合并不允许访问修饰符
      if explicitAccess != nil {
        throw ParserError.fileMergeNoAccessModifier(span: startSpan)
      }
      
      let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
      return UsingDeclaration(
        pathKind: .fileMerge,
        pathSegments: [filename],
        alias: nil,
        isBatchImport: false,
        access: .private,
        span: span
      )
    } else if currentToken === .selfKeyword {
      let selfSpan = currentSpan
      try match(.selfKeyword)
      
      if currentToken === .dot {
        // using self.submod - 子模块
        return try parseSubmodulePath(access: access, startSpan: startSpan)
      } else {
        throw ParserError.usingRequiresConcreteItem(span: selfSpan, base: "self")
      }
    } else if currentToken === .superKeyword {
      // using super.sibling - 父模块
      return try parseParentPath(access: access, startSpan: startSpan)
    } else {
      // using std - 外部模块
      return try parseExternalPath(access: access, startSpan: startSpan)
    }
  }
  
  /// Parse submodule path: self.utils or self.utils.SomeType or self.utils.*
  private func parseSubmodulePath(access: AccessModifier, startSpan: SourceSpan) throws -> UsingDeclaration {
    var segments: [String] = []
    var isBatchImport = false
    let alias: String? = nil
    
    while currentToken === .dot {
      try match(.dot)
      
      if currentToken === .multiply {
        try match(.multiply)
        isBatchImport = true
        break
      }
      
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      segments.append(name)
      try match(currentToken)
    }
    
    // Parse optional alias: using alias = self.submod
    if currentToken === .equal {
      // Actually alias comes before the path, so we need to handle this differently
      // For now, skip alias support in this direction
    }

    if segments.isEmpty {
      throw ParserError.usingRequiresConcreteItem(span: startSpan, base: "self")
    }
    
    let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
    return UsingDeclaration(
      pathKind: .submodule,
      pathSegments: segments,
      alias: alias,
      isBatchImport: isBatchImport,
      access: access,
      span: span
    )
  }
  
  /// Parse parent path: super.sibling or super.super.uncle
  private func parseParentPath(access: AccessModifier, startSpan: SourceSpan) throws -> UsingDeclaration {
    var segments: [String] = ["super"]
    var hasConcreteItem = false
    try match(.superKeyword)
    
    while currentToken === .dot {
      try match(.dot)
      
      if currentToken === .superKeyword {
        segments.append("super")
        try match(.superKeyword)
      } else if currentToken === .multiply {
        throw ParserError.usingRequiresConcreteItem(span: startSpan, base: "super")
      } else {
        guard case .identifier(let name) = currentToken else {
          throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
        }
        hasConcreteItem = true
        segments.append(name)
        try match(currentToken)
        
        // Continue parsing remaining path
        while currentToken === .dot {
          try match(.dot)
          if currentToken === .multiply {
            try match(.multiply)
            let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
            return UsingDeclaration(
              pathKind: .parent,
              pathSegments: segments,
              alias: nil,
              isBatchImport: true,
              access: access,
              span: span
            )
          }
          guard case .identifier(let nextName) = currentToken else {
            throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
          }
          hasConcreteItem = true
          segments.append(nextName)
          try match(currentToken)
        }
        break
      }
    }

    if !hasConcreteItem {
      throw ParserError.usingRequiresConcreteItem(span: startSpan, base: "super")
    }
    
    let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
    return UsingDeclaration(
      pathKind: .parent,
      pathSegments: segments,
      alias: nil,
      isBatchImport: false,
      access: access,
      span: span
    )
  }
  
  /// Parse external path: std or std.text or std.text.*
  private func parseExternalPath(access: AccessModifier, startSpan: SourceSpan) throws -> UsingDeclaration {
    var segments: [String] = []
    var isBatchImport = false
    var alias: String? = nil
    
    // Check for alias syntax: using alias = path
    guard case .identifier(let firstName) = currentToken else {
      throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
    }
    try match(currentToken)
    
    if currentToken === .equal {
      // This is an alias: using txt = std.text
      alias = firstName
      try match(.equal)
      
      guard case .identifier(let moduleName) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      segments.append(moduleName)
      try match(currentToken)
    } else {
      segments.append(firstName)
    }
    
    while currentToken === .dot {
      try match(.dot)
      
      if currentToken === .multiply {
        try match(.multiply)
        isBatchImport = true
        break
      }
      
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      segments.append(name)
      try match(currentToken)
    }
    
    let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
    return UsingDeclaration(
      pathKind: .external,
      pathSegments: segments,
      alias: alias,
      isBatchImport: isBatchImport,
      access: access,
      span: span
    )
  }
}

// Parser class
public class Parser {
  private let lexer: Lexer
  private var currentToken: Token

  public init(lexer: Lexer) {
    self.lexer = lexer
    self.currentToken = .bof
  }
  
  /// Get the current token's source span
  private var currentSpan: SourceSpan {
    lexer.tokenSpan
  }
  
  /// Get a source span at the current location
  private var currentLocation: SourceSpan {
    SourceSpan(location: lexer.currentLocation)
  }

  // Match current token type
  private func match(_ expected: Token) throws {
    if currentToken === expected {
      currentToken = try lexer.getNextToken()
    } else {
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description
      )
    }
  }
  
  /// Check if the current position should terminate a statement/declaration.
  /// Returns true if:
  /// 1. Current token is a semicolon
  /// 2. There was a newline before current token AND current token is not a continuation token
  ///    (unless there was a blank line or comment, which blocks continuation)
  /// 3. Current token is EOF or right brace (end of block)
  private func shouldTerminateStatement() -> Bool {
    // Explicit termination
    if currentToken === .semicolon {
      return true
    }
    // End of file or block
    if currentToken === .eof || currentToken === .rightBrace {
      return true
    }
    // Newline-based termination
    if lexer.newlineBeforeCurrent {
      // If there was a blank line or comment, always terminate (no continuation allowed)
      if lexer.blankLineOrCommentBeforeCurrent {
        return true
      }
      // Otherwise, check if current token is a continuation token
      if !currentToken.isContinuationToken {
        return true
      }
    }
    return false
  }
  
  /// Consume optional semicolon if present
  private func consumeOptionalSemicolon() throws {
    if currentToken === .semicolon {
      try match(.semicolon)
    }
  }

  /// True if a newline before the current token is *blocked* from continuing
  /// the previous expression/statement due to intervening blank lines or comments.
  private func isLineContinuationBlocked() -> Bool {
    lexer.newlineBeforeCurrent && lexer.blankLineOrCommentBeforeCurrent
  }

  // Parse program
  public func parse() throws -> ASTNode {
    var globalNodes: [GlobalNode] = []
    var seenNonUsing = false
    
    self.currentToken = try self.lexer.getNextToken()
    while currentToken !== .eof {
      // Check for using declaration
      if isUsingDeclaration() {
        if seenNonUsing {
          throw ParserError.usingAfterDeclaration(span: currentSpan)
        }
        let usingDecl = try parseUsingDeclaration()
        globalNodes.append(.usingDeclaration(usingDecl))
        try consumeOptionalSemicolon()
      } else {
        seenNonUsing = true
        let statement = try parseGlobalDeclaration()
        globalNodes.append(statement)
        // Consume optional semicolon after global declaration
        try consumeOptionalSemicolon()
      }
    }
    return .program(globalNodes: globalNodes)
  }
  
  /// Check if current position is a using declaration
  private func isUsingDeclaration() -> Bool {
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
  private func parseUsingDeclaration() throws -> UsingDeclaration {
    let startSpan = currentSpan
    
    // Parse optional access modifier
    var access: AccessModifier = .default
    if currentToken === .publicKeyword {
      try match(.publicKeyword)
      access = .public
    } else if currentToken === .protectedKeyword {
      try match(.protectedKeyword)
      access = .protected
    } else if currentToken === .privateKeyword {
      try match(.privateKeyword)
      access = .private
    }
    
    try match(.usingKeyword)
    
    // Determine path type based on first token
    if case .string(let filename) = currentToken {
      // using "filename" - 文件合并
      try match(currentToken)
      
      // 文件合并不允许访问修饰符
      if access != .default {
        throw ParserError.fileMergeNoAccessModifier(span: startSpan)
      }
      
      let span = SourceSpan(start: startSpan.start, end: currentSpan.end)
      return UsingDeclaration(
        pathKind: .fileMerge,
        pathSegments: [filename],
        alias: nil,
        isBatchImport: false,
        access: .default,
        span: span
      )
    } else if currentToken === .selfKeyword {
      try match(.selfKeyword)
      
      if currentToken === .dot {
        // using self.submod - 子模块
        return try parseSubmodulePath(access: access, startSpan: startSpan)
      } else {
        throw ParserError.expectedDot(span: currentSpan)
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
    try match(.superKeyword)
    
    while currentToken === .dot {
      try match(.dot)
      
      if currentToken === .superKeyword {
        segments.append("super")
        try match(.superKeyword)
      } else if currentToken === .multiply {
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
      } else {
        guard case .identifier(let name) = currentToken else {
          throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
        }
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
          segments.append(nextName)
          try match(currentToken)
        }
        break
      }
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

  // Parse global declaration
  private func parseGlobalDeclaration() throws -> GlobalNode {
    let startSpan = currentSpan
    let access = try parseAccessModifier()

    var isIntrinsic = false
    if currentToken === .intrinsicKeyword {
      try match(.intrinsicKeyword)
      isIntrinsic = true
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

      // If mut keyword was detected, it must be a variable declaration
      if mutable {
        if currentToken === .leftParen {
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        return try globalVariableDeclaration(
          name: name, mutable: true, access: access, span: startSpan)
      }

      // Otherwise check for left paren to determine if it's a function or variable
      if currentToken === .leftParen {
        return try globalFunctionDeclaration(
          name: name, typeParams: typePrams, access: access, isIntrinsic: isIntrinsic,
          span: startSpan)
      } else {
        if isIntrinsic {
          throw ParserError.unexpectedToken(
            span: currentSpan, got: "intrinsic variable not supported")
        }
        return try globalVariableDeclaration(
          name: name, mutable: false, access: access, span: startSpan)
      }
    } else if currentToken === .typeKeyword {
      try match(.typeKeyword)

      let typeParams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }

      if !isValidTypeName(name) {
        throw ParserError.invalidTypeName(span: currentSpan, name: name)
      }

      try match(.identifier(name))
      return try parseStructDeclaration(
        name, typeParams: typeParams, access: access, isIntrinsic: isIntrinsic, span: startSpan)
    } else if currentToken === .givenKeyword {
      if access != .default {
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
    var superTraits: [String] = []
    
    // Parse first parent constraint if present
    if currentToken !== .leftBrace {
      guard case .identifier(let parentName) = currentToken else {
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
      }
      if !isValidTypeName(parentName) {
        throw ParserError.invalidTypeName(span: currentSpan, name: parentName)
      }
      try match(.identifier(parentName))
      superTraits.append(parentName)
      
      // Parse subsequent constraints separated by 'and'
      while currentToken === .andKeyword {
        try match(.andKeyword)
        
        guard case .identifier(let nextParent) = currentToken else {
           throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
        }
        if !isValidTypeName(nextParent) {
            throw ParserError.invalidTypeName(span: currentSpan, name: nextParent)
        }
        try match(.identifier(nextParent))
        superTraits.append(nextParent)
      }
    }

    try match(.leftBrace)

    var methods: [TraitMethodSignature] = []
    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier()
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

  private func parseIntrinsicGivenDeclaration(span: SourceSpan) throws -> GlobalNode {
    try match(.givenKeyword)
    let typeParams = try parseTypeParameters()
    let type = try parseType()
    try match(.leftBrace)

    var methods: [IntrinsicMethodDeclaration] = []

    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier()

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
    try match(.leftBrace)
    var methods: [MethodDeclaration] = []
    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier()

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
    return .givenDeclaration(typeParams: typeParams, type: type, methods: methods, span: span)
  }

  private func parseAccessModifier() throws -> AccessModifier {
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
    return .default
  }

  // Parse type identifier
  private func parseType() throws -> TypeNode {
    if currentToken === .selfTypeKeyword {
      try match(.selfTypeKeyword)
      var type: TypeNode = .inferredSelf
      if currentToken === .refKeyword {
        try match(.refKeyword)
        type = .reference(type)
      }
      return type
    }
    if currentToken === .leftBracket {
      try match(.leftBracket)
      var args: [TypeNode] = []
      while currentToken !== .rightBracket {
        args.append(try parseType())
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightBracket)

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedTypeIdentifier(
          span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))

      // Check if this is a function type: [...]Func
      if name == "Func" {
        // Function type: [ParamType1, ParamType2, ..., ReturnType]Func
        // The last type is the return type, all others are parameter types
        guard !args.isEmpty else {
          throw ParserError.invalidFunctionType(
            span: currentSpan, message: "Function type must have at least a return type")
        }
        let returnType = args.last!
        let paramTypes = Array(args.dropLast())
        var type: TypeNode = .functionType(paramTypes: paramTypes, returnType: returnType)
        if currentToken === .refKeyword {
          try match(.refKeyword)
          type = .reference(type)
        }
        return type
      }

      var type = TypeNode.generic(base: name, args: args)
      if currentToken === .refKeyword {
        try match(.refKeyword)
        type = .reference(type)
      }
      return type
    }

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(
        span: currentSpan, got: currentToken.description)
    }

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(span: currentSpan, name: name)
    }

    try match(.identifier(name))
    var type: TypeNode = .identifier(name)

    if currentToken === .refKeyword {
      try match(.refKeyword)
      type = .reference(type)
    }

    return type
  }

  // Parse global variable declaration
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

  private func parseTypeParameters() throws -> [TypeParameterDecl] {
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

  // Parse global function declaration with optional 'own'/'ref' modifiers for params and return type
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

  // Parse type declaration
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
      let fieldAccess = try parseAccessModifier()

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

  // Parse union declaration (sum type)
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

  // Parse statement
  private func statement() throws -> StatementNode {
    switch currentToken {
    case .letKeyword:
      return try variableDeclaration()
    case .returnKeyword:
      try match(.returnKeyword)
      // return; or return <expr>;
      // Also check for automatic statement termination (newline before non-continuation token)
      if currentToken === .semicolon || currentToken === .rightBrace || shouldTerminateStatement() {
        return .return(value: nil, span: currentSpan)
      }
      let value = try expression()
      return .return(value: value, span: currentSpan)
    case .breakKeyword:
      try match(.breakKeyword)
      return .break(span: currentSpan)
    case .continueKeyword:
      try match(.continueKeyword)
      return .continue(span: currentSpan)
    default:
      let expr = try expression()

      if currentToken === .equal {
        try match(.equal)
        let value = try expression()
        return .assignment(target: expr, value: value, span: currentSpan)
      } else if let op = getCompoundAssignmentOperator(currentToken) {
        try match(currentToken)
        let value = try expression()
        return .compoundAssignment(
          target: expr, operator: op, value: value, span: currentSpan)
      }
      return .expression(expr, span: currentSpan)
    }
  }

  private func getCompoundAssignmentOperator(_ token: Token) -> CompoundAssignmentOperator? {
    switch token {
    case .plusEqual: return .plus
    case .minusEqual: return .minus
    case .multiplyEqual: return .multiply
    case .divideEqual: return .divide
    case .moduloEqual: return .modulo
    case .doubleStarEqual: return .power
    case .ampersandEqual: return .bitwiseAnd
    case .pipeEqual: return .bitwiseOr
    case .caretEqual: return .bitwiseXor
    case .leftShiftEqual: return .shiftLeft
    case .rightShiftEqual: return .shiftRight
    default: return nil
    }
  }

  private func parseLetContent() throws -> (
    name: String, type: TypeNode?, value: ExpressionNode, mutable: Bool
  ) {
    try match(.letKeyword)
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

    var type: TypeNode? = nil
    if currentToken !== .equal {
      type = try parseType()
    }

    try match(.equal)
    let value = try expression()
    return (name, type, value, mutable)
  }

  // Parse variable declaration
  private func variableDeclaration() throws -> StatementNode {
    let (name, type, value, mutable) = try parseLetContent()

    if currentToken === .thenKeyword {
      try match(.thenKeyword)
      let body = try expression()
      return .expression(
        .letExpression(name: name, type: type, value: value, mutable: mutable, body: body),
        span: currentSpan)
    }

    return .variableDeclaration(
      name: name, type: type, value: value, mutable: mutable, span: currentSpan)
  }

  private func letExpression() throws -> ExpressionNode {
    let (name, type, value, mutable) = try parseLetContent()
    try match(.thenKeyword)
    let body = try expression()
    return .letExpression(name: name, type: type, value: value, mutable: mutable, body: body)
  }

  private func parsePostfixExpression() throws -> ExpressionNode {
    var expr = try term()
    while true {
      // If a newline was crossed and it included blank lines/comments, do not allow continuation.
      if isLineContinuationBlocked() {
        break
      }
      // Check for automatic statement termination before parsing postfix operators
      // If there's a newline before the current token and it's not a continuation token,
      // we should stop parsing postfix expressions
      if lexer.newlineBeforeCurrent && !currentToken.isContinuationToken {
        // Special case: dot is a continuation token, so we continue
        // But [ and ( and { are not continuation tokens, so we stop
        if currentToken === .leftBracket || currentToken === .leftParen || currentToken === .leftBrace {
          break
        }
      }
      
      if currentToken === .dot {
        try match(.dot)
        
        // Check for generic method call: obj.[Type]method(args)
        if currentToken === .leftBracket {
          try match(.leftBracket)
          var methodTypeArgs: [TypeNode] = []
          while currentToken !== .rightBracket {
            methodTypeArgs.append(try parseType())
            if currentToken === .comma {
              try match(.comma)
            }
          }
          try match(.rightBracket)
          
          guard case .identifier(let methodName) = currentToken else {
            throw ParserError.expectedIdentifier(
              span: currentSpan, got: currentToken.description)
          }
          try match(.identifier(methodName))
          
          // Must be followed by a call
          guard currentToken === .leftParen else {
            throw ParserError.unexpectedToken(
              span: currentSpan,
              got: currentToken.description,
              expected: "("
            )
          }
          try match(.leftParen)
          var arguments: [ExpressionNode] = []
          if currentToken !== .rightParen {
            repeat {
              arguments.append(try expression())
              if currentToken === .comma {
                try match(.comma)
              } else {
                break
              }
            } while true
          }
          try match(.rightParen)
          expr = .genericMethodCall(base: expr, methodTypeArgs: methodTypeArgs, methodName: methodName, arguments: arguments)
          continue
        }
        
        guard case .identifier(let member) = currentToken else {
          throw ParserError.expectedIdentifier(
            span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(member))
        
        // Check if this is a static method call: TypeName.methodName(...)
        // TypeName starts with uppercase, methodName starts with lowercase
        if isValidTypeName(member) == false {
          // member is lowercase - could be a method or field
          // Check if base is a type identifier (uppercase) - this would be a static method call
          if case .identifier(let baseName) = expr, isValidTypeName(baseName) {
            // This is TypeName.methodName - check for call
            if currentToken === .leftParen {
              try match(.leftParen)
              var arguments: [ExpressionNode] = []
              if currentToken !== .rightParen {
                repeat {
                  arguments.append(try expression())
                  if currentToken === .comma {
                    try match(.comma)
                  } else {
                    break
                  }
                } while true
              }
              try match(.rightParen)
              expr = .staticMethodCall(typeName: baseName, typeArgs: [], methodName: member, arguments: arguments)
              continue
            }
          }
          // Check if base is a generic instantiation: [T]TypeName.methodName(...)
          if case .genericInstantiation(let baseName, let typeArgs) = expr {
            if currentToken === .leftParen {
              try match(.leftParen)
              var arguments: [ExpressionNode] = []
              if currentToken !== .rightParen {
                repeat {
                  arguments.append(try expression())
                  if currentToken === .comma {
                    try match(.comma)
                  } else {
                    break
                  }
                } while true
              }
              try match(.rightParen)
              expr = .staticMethodCall(typeName: baseName, typeArgs: typeArgs, methodName: member, arguments: arguments)
              continue
            }
          }
        }
        
        // Regular member path
        if case .memberPath(let base, let path) = expr {
          expr = .memberPath(base: base, path: path + [member])
        } else {
          expr = .memberPath(base: expr, path: [member])
        }
      } else if currentToken === .leftParen {
        expr = try parseCall(expr)
      } else if currentToken === .leftBracket {
        try match(.leftBracket)
        var args: [ExpressionNode] = []
        if currentToken !== .rightBracket {
          repeat {
            args.append(try expression())
            if currentToken === .comma {
              try match(.comma)
            } else {
              break
            }
          } while true
        }
        try match(.rightBracket)
        expr = .subscriptExpression(base: expr, arguments: args)
      } else {
        break
      }
    }
    return expr
  }

  /// Parse pattern (entry point) - supports combinators with precedence: not > and > or
  private func parsePattern() throws -> PatternNode {
    return try parseOrPattern()
  }
  
  /// Parse or pattern (lowest precedence)
  private func parseOrPattern() throws -> PatternNode {
    let startSpan = currentSpan
    var left = try parseAndPattern()
    
    while currentToken === .orKeyword {
      try match(.orKeyword)
      let right = try parseAndPattern()
      left = .orPattern(left: left, right: right, span: startSpan)
    }
    
    return left
  }
  
  /// Parse and pattern
  private func parseAndPattern() throws -> PatternNode {
    let startSpan = currentSpan
    var left = try parseNotPattern()
    
    while currentToken === .andKeyword {
      try match(.andKeyword)
      let right = try parseNotPattern()
      left = .andPattern(left: left, right: right, span: startSpan)
    }
    
    return left
  }
  
  /// Parse not pattern (highest precedence among combinators)
  private func parseNotPattern() throws -> PatternNode {
    let startSpan = currentSpan
    
    if currentToken === .notKeyword {
      try match(.notKeyword)
      let pattern = try parseNotPattern()  // Right-associative
      return .notPattern(pattern: pattern, span: startSpan)
    }
    
    return try parsePrimaryPattern()
  }
  
  /// Parse primary pattern (literals, wildcards, variables, union cases, comparison patterns)
  private func parsePrimaryPattern() throws -> PatternNode {
    let startSpan = currentSpan
    
    // Comparison patterns: > n, < n, >= n, <= n
    if currentToken === .greater || currentToken === .less ||
       currentToken === .greaterEqual || currentToken === .lessEqual {
      let op: ComparisonPatternOperator
      switch currentToken {
      case .greater:
        op = .greater
        try match(.greater)
      case .less:
        op = .less
        try match(.less)
      case .greaterEqual:
        op = .greaterEqual
        try match(.greaterEqual)
      case .lessEqual:
        op = .lessEqual
        try match(.lessEqual)
      default:
        fatalError("Unreachable")
      }
      
      // Parse integer operand (may be negative)
      var isNegative = false
      if currentToken === .minus {
        try match(.minus)
        isNegative = true
      }
      
      guard case .integer(let v, let suffix) = currentToken else {
        throw ParserError.unexpectedToken(span: currentSpan, got: "Comparison pattern requires integer literal")
      }
      try match(.integer(v, suffix))
      
      let value = isNegative ? "-\(v)" : v
      return .comparisonPattern(operator: op, value: value, suffix: suffix, span: startSpan)
    }
    
    // Negative integer literal pattern: -n
    if currentToken === .minus {
      try match(.minus)
      guard case .integer(let v, let suffix) = currentToken else {
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
      }
      try match(.integer(v, suffix))
      return .negativeIntegerLiteral(value: v, suffix: suffix, span: startSpan)
    }
    
    // Range pattern error - no longer supported
    if currentToken === .fullRange || currentToken === .unboundedRange || 
       currentToken === .unboundedRangeLess {
      throw ParserError.unexpectedToken(
        span: currentSpan, 
        got: "Range patterns are no longer supported. Use comparison patterns instead (e.g., > 5 and < 10)."
      )
    }
    
    // Integer literal pattern
    if case .integer(let v, let suffix) = currentToken {
      try match(.integer(v, suffix))
      
      // Check for range operator - error if found
      if currentToken === .range || currentToken === .rangeLess ||
         currentToken === .lessRange || currentToken === .lessRangeLess ||
         currentToken === .unboundedRange || currentToken === .lessUnboundedRange {
        throw ParserError.unexpectedToken(
          span: currentSpan,
          got: "Range patterns are no longer supported. Use comparison patterns instead (e.g., >= \(v) and < end)."
        )
      }
      
      return .integerLiteral(value: v, suffix: suffix, span: startSpan)
    }
    
    // Boolean literal pattern
    if case .bool(let v) = currentToken {
      try match(.bool(v))
      return .booleanLiteral(value: v, span: currentSpan)
    }
    
    // Identifier pattern (wildcard or variable binding)
    if case .identifier(let name) = currentToken {
      if name == "_" {
        try match(.identifier(name))
        return .wildcard(span: currentSpan)
      }
      try match(.identifier(name))
      return .variable(name: name, mutable: false, span: currentSpan)
    }
    
    // String literal pattern
    if case .string(let str) = currentToken {
      try match(.string(str))
      return .stringLiteral(value: str, span: currentSpan)
    }
    
    // Mutable variable binding pattern
    if currentToken === .mutKeyword {
      try match(.mutKeyword)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))
      return .variable(name: name, mutable: true, span: currentSpan)
    }
    
    // Union case pattern
    if currentToken === .dot {
      try match(.dot)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))
      var args: [PatternNode] = []
      if currentToken === .leftParen {
        try match(.leftParen)
        while currentToken !== .rightParen {
          args.append(try parsePattern())
          if currentToken === .comma { try match(.comma) }
        }
        try match(.rightParen)
      }
      return .unionCase(caseName: name, elements: args, span: currentSpan)
    }
    
    // Parenthesized pattern for grouping
    if currentToken === .leftParen {
      try match(.leftParen)
      let inner = try parsePattern()
      try match(.rightParen)
      return inner
    }
    
    throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
  }

  private func parseCall(_ callee: ExpressionNode) throws -> ExpressionNode {
    try match(.leftParen)
    var arguments: [ExpressionNode] = []

    if currentToken !== .rightParen {
      func getNextComma() throws -> Bool {
        if currentToken === .comma {
          try match(.comma)
          return true
        }
        return false
      }
      repeat {
        let arg = try expression()
        arguments.append(arg)
      } while try getNextComma()
    }

    try match(.rightParen)
    return .call(callee: callee, arguments: arguments)
  }

  // Parse expression rule
  private func expression() throws -> ExpressionNode {
    if currentToken === .letKeyword {
      return try letExpression()
    } else if currentToken === .ifKeyword {
      return try ifExpression()
    } else if currentToken === .whileKeyword {
      return try whileExpression()
    } else if currentToken === .whenKeyword {
      return try parseWhenExpression()
    } else if currentToken === .forKeyword {
      return try forExpression()
    } else {
      return try parseOrExpression()
    }
  }

  private func parseOrExpression() throws -> ExpressionNode {
    var left = try parseAndExpression()

    while currentToken === .orKeyword {
      if isLineContinuationBlocked() { break }
      try match(.orKeyword)
      let right = try parseAndExpression()
      left = .orExpression(left: left, right: right)
    }
    return left
  }

  private func parseAndExpression() throws -> ExpressionNode {
    var left = try parseLogicalNotExpression()

    while currentToken === .andKeyword {
      if isLineContinuationBlocked() { break }
      try match(.andKeyword)
      let right = try parseLogicalNotExpression()
      left = .andExpression(left: left, right: right)
    }
    return left
  }

  private func parseLogicalNotExpression() throws -> ExpressionNode {
    if currentToken === .notKeyword {
      try match(.notKeyword)
      let expr = try parseBitwiseOrExpression()
      return .notExpression(expr)
    }
    return try parseBitwiseOrExpression()
  }

  private func parseBitwiseOrExpression() throws -> ExpressionNode {
    var left = try parseBitwiseXorExpression()
    while currentToken === .pipe {
      if isLineContinuationBlocked() { break }
      try match(.pipe)
      let right = try parseBitwiseXorExpression()
      left = .bitwiseExpression(left: left, operator: .or, right: right)
    }
    return left
  }

  private func parseBitwiseXorExpression() throws -> ExpressionNode {
    var left = try parseBitwiseAndExpression()
    while currentToken === .caret {
      if isLineContinuationBlocked() { break }
      try match(.caret)
      let right = try parseBitwiseAndExpression()
      left = .bitwiseExpression(left: left, operator: .xor, right: right)
    }
    return left
  }

  private func parseBitwiseAndExpression() throws -> ExpressionNode {
    var left = try parseRangeExpression()
    while currentToken === .ampersand {
      if isLineContinuationBlocked() { break }
      try match(.ampersand)
      let right = try parseRangeExpression()
      left = .bitwiseExpression(left: left, operator: .and, right: right)
    }
    return left
  }

  // Range expressions: a..b, a..<b, a<..b, a<..<b, a..., a<..., ...b, ...<b, ....
  private func parseRangeExpression() throws -> ExpressionNode {
    // Handle prefix range operators: ...b, ...<b, ....
    if currentToken === .fullRange {
      try match(.fullRange)
      return .rangeExpression(operator: .full, left: nil, right: nil)
    }
    if currentToken === .unboundedRange {
      try match(.unboundedRange)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .to, left: nil, right: right)
    }
    if currentToken === .unboundedRangeLess {
      try match(.unboundedRangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .toOpen, left: nil, right: right)
    }
    
    let left = try parseComparisonExpression()
    
    // Handle infix and postfix range operators
    if isLineContinuationBlocked() { return left }
    
    switch currentToken {
    case .range:  // ..
      try match(.range)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .closed, left: left, right: right)
    case .rangeLess:  // ..<
      try match(.rangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .closedOpen, left: left, right: right)
    case .lessRange:  // <..
      try match(.lessRange)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .openClosed, left: left, right: right)
    case .lessRangeLess:  // <..<
      try match(.lessRangeLess)
      let right = try parseComparisonExpression()
      return .rangeExpression(operator: .open, left: left, right: right)
    case .unboundedRange:  // ...
      try match(.unboundedRange)
      return .rangeExpression(operator: .from, left: left, right: nil)
    case .lessUnboundedRange:  // <...
      try match(.lessUnboundedRange)
      return .rangeExpression(operator: .fromOpen, left: left, right: nil)
    default:
      return left
    }
  }

  // Fourth level: Comparisons
  private func parseComparisonExpression() throws -> ExpressionNode {
    var left = try parseShiftExpression()

    while currentToken === .equalEqual || currentToken === .notEqual || currentToken === .greater
      || currentToken === .less || currentToken === .greaterEqual || currentToken === .lessEqual
    {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parseShiftExpression()
      left = .comparisonExpression(
        left: left,
        operator: tokenToComparisonOperator(op),
        right: right
      )
    }
    return left
  }

  private func parseShiftExpression() throws -> ExpressionNode {
    var left = try parseAdditiveExpression()
    while currentToken === .leftShift || currentToken === .rightShift {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parseAdditiveExpression()
      let bitOp: BitwiseOperator = (op === .leftShift) ? .shiftLeft : .shiftRight
      left = .bitwiseExpression(left: left, operator: bitOp, right: right)
    }
    return left
  }

  // Fifth level: Addition and subtraction
  private func parseAdditiveExpression() throws -> ExpressionNode {
    var left = try parseMultiplicativeExpression()

    while currentToken === .plus || currentToken === .minus {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parseMultiplicativeExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right
      )
    }
    return left
  }

  // Sixth level: Multiplication, division, and modulo
  private func parseMultiplicativeExpression() throws -> ExpressionNode {
    var left = try parsePowerExpression()

    while currentToken === .multiply || currentToken === .divide || currentToken === .modulo {
      if isLineContinuationBlocked() { break }
      let op = currentToken
      try match(op)
      let right = try parsePowerExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right
      )
    }
    return left
  }

  // Seventh level: Power (right-associative)
  private func parsePowerExpression() throws -> ExpressionNode {
    let left = try parsePrefixExpression()
    // Power is right-associative, so we use recursion instead of a loop
    if currentToken === .doubleStar {
      if isLineContinuationBlocked() { return left }
      try match(.doubleStar)
      let right = try parsePowerExpression()  // Recursive for right-associativity
      return .arithmeticExpression(left: left, operator: .power, right: right)
    }
    return left
  }

  private func parsePrefixExpression() throws -> ExpressionNode {
    if let cast = try tryParseCastExpression() {
      return cast
    }
    if currentToken === .refKeyword {
      try match(.refKeyword)
      let expr = try parsePrefixExpression()
      return .refExpression(expr)
    } else if currentToken === .derefKeyword {
      try match(.derefKeyword)
      let expr = try parsePrefixExpression()
      return .derefExpression(expr)
    } else if currentToken === .tilde {
      try match(.tilde)
      let expr = try parsePrefixExpression()
      return .bitwiseNotExpression(expr)
    }
    return try parsePostfixExpression()
  }

  // Attempt to parse a C-style cast expression: `(Type)expr`.
  // Uses lexer state save/restore to disambiguate from parenthesized expressions.
  private func tryParseCastExpression() throws -> ExpressionNode? {
    guard currentToken === .leftParen else { return nil }

    let savedLexer = lexer.saveState()
    let savedToken = currentToken

    do {
      try match(.leftParen)
      let targetType = try parseType()
      guard currentToken === .rightParen else {
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
      }
      try match(.rightParen)
      let expr = try parsePrefixExpression()
      return .castExpression(type: targetType, expression: expr)
    } catch {
      lexer.restoreState(savedLexer)
      currentToken = savedToken
      return nil
    }
  }

  private func ifExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.ifKeyword)
    let subject = try expression()
    
    // Check if this is pattern matching syntax: if expr is pattern then body
    if currentToken === .isKeyword {
      try match(.isKeyword)
      let pattern = try parsePattern()
      try match(.thenKeyword)
      let thenBranch = try expression()
      
      var elseBranch: ExpressionNode? = nil
      if currentToken === .elseKeyword {
        try match(.elseKeyword)
        elseBranch = try expression()
      }
      
      return .ifPatternExpression(
        subject: subject,
        pattern: pattern,
        thenBranch: thenBranch,
        elseBranch: elseBranch,
        span: startSpan
      )
    }
    
    // Original boolean condition syntax: if condition then body
    try match(.thenKeyword)
    let thenBranch = try expression()

    var elseBranch: ExpressionNode? = nil
    if currentToken === .elseKeyword {
      try match(.elseKeyword)
      elseBranch = try expression()
    }
    return .ifExpression(condition: subject, thenBranch: thenBranch, elseBranch: elseBranch)
  }

  private func whileExpression() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.whileKeyword)
    let subject = try expression()
    
    // Check if this is pattern matching syntax: while expr is pattern then body
    if currentToken === .isKeyword {
      try match(.isKeyword)
      let pattern = try parsePattern()
      try match(.thenKeyword)
      let body = try expression()
      
      return .whilePatternExpression(
        subject: subject,
        pattern: pattern,
        body: body,
        span: startSpan
      )
    }
    
    // Original boolean condition syntax: while condition then body
    try match(.thenKeyword)
    let body = try expression()
    return .whileExpression(condition: subject, body: body)
  }

  /// Parse for expression: for <pattern> = <iterable> then <body>
  private func forExpression() throws -> ExpressionNode {
    try match(.forKeyword)
    let pattern = try parsePattern()
    try match(.equal)
    let iterable = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .forExpression(pattern: pattern, iterable: iterable, body: body)
  }

  private func parseWhenExpression() throws -> ExpressionNode {
    try match(.whenKeyword)
    let subject = try expression()
    try match(.isKeyword)
    try match(.leftBrace)
    var cases: [MatchCaseNode] = []
    while currentToken !== .rightBrace {
      let pattern = try parsePattern()
      
      try match(.thenKeyword)

      let body: ExpressionNode
      if currentToken === .leftBrace {
        body = try blockExpression()
      } else {
        body = try expression()
      }

      cases.append(MatchCaseNode(pattern: pattern, body: body))
      
      // Use comma as separator between match arms (optional trailing comma)
      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightBrace)
    return .matchExpression(subject: subject, cases: cases, span: currentSpan)
  }

  private func tokenToArithmeticOperator(_ token: Token) -> ArithmeticOperator {
    switch token {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .modulo: return .modulo
    case .doubleStar: return .power
    default: fatalError("Invalid arithmetic operator token")
    }
  }

  private func tokenToComparisonOperator(_ token: Token) -> ComparisonOperator {
    switch token {
    case .equalEqual: return .equal
    case .notEqual: return .notEqual
    case .greater: return .greater
    case .less: return .less
    case .greaterEqual: return .greaterEqual
    case .lessEqual: return .lessEqual
    default: fatalError("Invalid comparison operator token")
    }
  }

  // Parse term
  private func term() throws -> ExpressionNode {
    switch currentToken {
    case .identifier(let name):
      try match(.identifier(name))
      return .identifier(name)
    case .selfKeyword:
      try match(.selfKeyword)
      return .identifier("self")
    case .integer(let num, let suffix):
      try match(.integer(num, suffix))
      return .integerLiteral(num, suffix)
    case .float(let num, let suffix):
      try match(.float(num, suffix))
      return .floatLiteral(num, suffix)
    case .string(let str):
      try match(.string(str))
      return .stringLiteral(str)
    case .bool(let value):
      try match(.bool(value))
      return .booleanLiteral(value)
    case .leftBrace:
      return try blockExpression()
    case .leftParen:
      // Could be: parenthesized expression (expr) or lambda expression (params) -> body
      return try parseParenOrLambda()
    case .leftBracket:
      try match(.leftBracket)
      var args: [TypeNode] = []
      while currentToken !== .rightBracket {
        args.append(try parseType())
        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightBracket)

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(
          span: currentSpan, got: currentToken.description)
      }
      try match(.identifier(name))

      // Check if it's a call
      if currentToken === .leftParen {
        let callee = ExpressionNode.genericInstantiation(base: name, args: args)
        return try parseCall(callee)
      }

      return .genericInstantiation(base: name, args: args)
    default:
      throw ParserError.unexpectedToken(
        span: currentSpan,
        got: currentToken.description,
        expected: "number, identifier, boolean literal, block expression, or generic instantiation"
      )
    }
  }
  
  /// Parse either a parenthesized expression or a lambda expression.
  /// Lambda syntax:
  ///   () -> expr                    // no params
  ///   (x) -> expr                   // single param, type inferred
  ///   (x, y) -> expr                // multiple params, types inferred
  ///   (x Int) -> expr               // single param with type
  ///   (x Int, y Int) -> expr        // multiple params with types
  ///   (x Int, y Int) Int -> expr    // with return type
  private func parseParenOrLambda() throws -> ExpressionNode {
    let startSpan = currentSpan
    try match(.leftParen)
    
    // Empty parens: () -> must be lambda
    if currentToken === .rightParen {
      try match(.rightParen)
      // Check for optional return type before arrow
      var returnType: TypeNode? = nil
      if currentToken !== .arrow {
        // Could be a return type
        if case .identifier(_) = currentToken {
          returnType = try parseType()
        } else if currentToken === .leftBracket {
          returnType = try parseType()
        }
      }
      if currentToken === .arrow {
        try match(.arrow)
        let body = try expression()
        return .lambdaExpression(parameters: [], returnType: returnType, body: body, span: startSpan)
      } else {
        // Not a lambda, but () is not a valid expression by itself
        throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description, expected: "'->'")
      }
    }
    
    // Save state to backtrack if this is not a lambda
    let savedState = lexer.saveState()
    let savedToken = currentToken
    
    // Try to parse as lambda parameters
    var parameters: [(name: String, type: TypeNode?)] = []
    var isLambda = false
    
    do {
      while currentToken !== .rightParen {
        guard case .identifier(let paramName) = currentToken else {
          // Not a valid lambda parameter, restore and parse as expression
          throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
        }
        try match(.identifier(paramName))
        
        // Check for optional type annotation
        var paramType: TypeNode? = nil
        if currentToken !== .comma && currentToken !== .rightParen {
          // Could be a type annotation or an operator (if this is an expression)
          // Types start with uppercase identifier or [
          if case .identifier(let typeName) = currentToken, typeName.first?.isUppercase == true {
            paramType = try parseType()
          } else if currentToken === .leftBracket {
            paramType = try parseType()
          } else {
            // Not a type, this might be an expression like (a + b)
            throw ParserError.unexpectedToken(span: currentSpan, got: currentToken.description)
          }
        }
        
        parameters.append((name: paramName, type: paramType))
        
        if currentToken === .comma {
          try match(.comma)
        }
      }
      
      try match(.rightParen)
      
      // Check for optional return type before arrow
      var returnType: TypeNode? = nil
      if currentToken !== .arrow {
        // Could be a return type
        if case .identifier(let typeName) = currentToken, typeName.first?.isUppercase == true {
          returnType = try parseType()
        } else if currentToken === .leftBracket {
          returnType = try parseType()
        }
      }
      
      // Must have arrow for lambda
      if currentToken === .arrow {
        isLambda = true
        try match(.arrow)
        let body = try expression()
        return .lambdaExpression(parameters: parameters, returnType: returnType, body: body, span: startSpan)
      }
      
      // No arrow - if we have multiple params or typed params, it's an error
      if parameters.count > 1 || parameters.contains(where: { $0.type != nil }) {
        throw ParserError.expectedArrow(span: currentSpan)
      }
      
      // Single untyped param without arrow - restore and parse as expression
      // This handles cases like (a) which could be just a parenthesized identifier
    } catch {
      // Parsing as lambda failed, restore state
    }
    
    if !isLambda {
      // Restore state and parse as parenthesized expression
      lexer.restoreState(savedState)
      currentToken = savedToken
      let inner = try expression()
      try match(.rightParen)
      return inner
    }
    
    // Should not reach here
    fatalError("Unreachable")
  }

  // Parse block expression
  private func blockExpression() throws -> ExpressionNode {
    try match(.leftBrace)
    var statements: [StatementNode] = []

    // Process empty block
    if currentToken === .rightBrace {
      try match(.rightBrace)
      return .blockExpression(statements: [], finalExpression: nil)
    }

    // Parse statements
    while currentToken !== .rightBrace {
      if currentToken === .eof {
        throw ParserError.unexpectedEndOfFile(span: currentSpan)
      }

      let stmt = try statement()
      statements.append(stmt)

      // Check if this is the final expression (no explicit semicolon and next is right brace)
      if case .expression(let expr, _) = stmt {
        if currentToken === .rightBrace {
          // This expression is the final expression (return value of block)
          try match(.rightBrace)
          return .blockExpression(
            statements: Array(statements.dropLast()),
            finalExpression: expr
          )
        }
      }

      // Check for explicit semicolon - if present, this statement is terminated
      if currentToken === .semicolon {
        try match(.semicolon)
        // After semicolon, if next is right brace, block has no final expression
        if currentToken === .rightBrace {
          try match(.rightBrace)
          return .blockExpression(statements: statements, finalExpression: nil)
        }
        continue
      }

      // Check for automatic statement termination (newline before non-continuation token)
      if shouldTerminateStatement() {
        // If next is right brace, block has no final expression
        if currentToken === .rightBrace {
          try match(.rightBrace)
          return .blockExpression(statements: statements, finalExpression: nil)
        }
        continue
      }

      // If we reach here, the statement continues (e.g., continuation token on next line)
      // This shouldn't normally happen as statement() should consume the full statement
    }
    
    try match(.rightBrace)
    return .blockExpression(statements: statements, finalExpression: nil)
  }

  private func isValidVariableName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    // Allow names starting with lowercase letter or underscore
    return first.isLowercase || first == "_"
  }

  private func isValidTypeName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    return first.isUppercase
  }
}

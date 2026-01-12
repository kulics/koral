// Parser class
public class Parser {
  private let lexer: Lexer
  private var currentToken: Token

  public init(lexer: Lexer) {
    self.lexer = lexer
    self.currentToken = .bof
  }

  // Match current token type
  private func match(_ expected: Token) throws {
    if currentToken === expected {
      currentToken = try lexer.getNextToken()
    } else {
      throw ParserError.unexpectedToken(
        line: lexer.currentLine,
        got: currentToken.description
      )
    }
  }

  // Parse program
  public func parse() throws -> ASTNode {
    var statements: [GlobalNode] = []
    self.currentToken = try self.lexer.getNextToken()
    while currentToken !== .eof {
      let statement = try parseGlobalDeclaration()
      statements.append(statement)
      if currentToken !== .eof {
        try match(.semicolon)
      }
    }
    return .program(globalNodes: statements)
  }

  // Parse global declaration
  private func parseGlobalDeclaration() throws -> GlobalNode {
    let startLine = lexer.currentLine
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
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
      }

      if !isValidVariableName(name) {
        throw ParserError.invalidVariableName(line: lexer.currentLine, name: name)
      }

      try match(.identifier(name))

      // If mut keyword was detected, it must be a variable declaration
      if mutable {
        if currentToken === .leftParen {
          throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
        }
        return try globalVariableDeclaration(
          name: name, mutable: true, access: access, line: startLine)
      }

      // Otherwise check for left paren to determine if it's a function or variable
      if currentToken === .leftParen {
        return try globalFunctionDeclaration(
          name: name, typeParams: typePrams, access: access, isIntrinsic: isIntrinsic,
          line: startLine)
      } else {
        if isIntrinsic {
          throw ParserError.unexpectedToken(
            line: lexer.currentLine, got: "intrinsic variable not supported")
        }
        return try globalVariableDeclaration(
          name: name, mutable: false, access: access, line: startLine)
      }
    } else if currentToken === .typeKeyword {
      try match(.typeKeyword)

      let typeParams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
      }

      if !isValidTypeName(name) {
        throw ParserError.invalidTypeName(line: lexer.currentLine, name: name)
      }

      try match(.identifier(name))
      return try parseStructDeclaration(
        name, typeParams: typeParams, access: access, isIntrinsic: isIntrinsic, line: startLine)
    } else if currentToken === .givenKeyword {
      if access != .default {
        throw ParserError.unexpectedToken(
          line: lexer.currentLine, got: "Access modifier on given declaration")
      }
      if isIntrinsic {
        return try parseIntrinsicGivenDeclaration(line: startLine)
      }
      return try parseGivenDeclaration(line: startLine)
    } else if currentToken === .traitKeyword {
      if isIntrinsic {
        throw ParserError.unexpectedToken(line: lexer.currentLine, got: "intrinsic trait not supported")
      }
      return try parseTraitDeclaration(access: access, line: startLine)
    } else {
      throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
    }
  }

  private func parseTraitDeclaration(access: AccessModifier, line: Int) throws -> GlobalNode {
    try match(.traitKeyword)

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
    }

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(line: lexer.currentLine, name: name)
    }
    try match(.identifier(name))

    // Optional inheritance list: trait Child ParentA and ParentB { ... }
    var superTraits: [String] = []
    
    // Parse first parent constraint if present
    if currentToken !== .leftBrace {
      guard case .identifier(let parentName) = currentToken else {
        throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
      }
      if !isValidTypeName(parentName) {
        throw ParserError.invalidTypeName(line: lexer.currentLine, name: parentName)
      }
      try match(.identifier(parentName))
      superTraits.append(parentName)
      
      // Parse subsequent constraints separated by 'and'
      while currentToken === .andKeyword {
        try match(.andKeyword)
        
        guard case .identifier(let nextParent) = currentToken else {
           throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
        }
        if !isValidTypeName(nextParent) {
            throw ParserError.invalidTypeName(line: lexer.currentLine, name: nextParent)
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
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
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
            line: lexer.currentLine, got: currentToken.description)
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
        throw ParserError.unexpectedToken(line: lexer.currentLine, got: "Trait method should not have body")
      }
      try match(.semicolon)

      if !methodTypeParams.isEmpty {
        throw ParserError.unexpectedToken(line: lexer.currentLine, got: "Trait method generics not supported yet")
      }

      methods.append(
        TraitMethodSignature(
          name: methodName,
          parameters: parameters,
          returnType: returnType,
          access: methodAccess
        )
      )
    }

    try match(.rightBrace)
    return .traitDeclaration(
      name: name,
      superTraits: superTraits,
      methods: methods,
      access: access,
      line: line
    )
  }

  private func parseIntrinsicGivenDeclaration(line: Int) throws -> GlobalNode {
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
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
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
            line: lexer.currentLine, got: currentToken.description)
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

      // Must end with semicolon, no body
      if currentToken === .equal {
        throw ParserError.unexpectedToken(
          line: lexer.currentLine, got: "Intrinsic given method should not have body")
      }
      try match(.semicolon)

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
      typeParams: typeParams, type: type, methods: methods, line: line)
  }

  private func parseGivenDeclaration(line: Int) throws -> GlobalNode {
    try match(.givenKeyword)
    let typeParams = try parseTypeParameters()
    let type = try parseType()
    try match(.leftBrace)
    var methods: [MethodDeclaration] = []
    while currentToken !== .rightBrace {
      let methodAccess = try parseAccessModifier()

      let typeParams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
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
            line: lexer.currentLine, got: currentToken.description)
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
      if currentToken === .semicolon {
        try match(.semicolon)
      }

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
    return .givenDeclaration(typeParams: typeParams, type: type, methods: methods, line: line)
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
          line: lexer.currentLine, got: currentToken.description)
      }
      try match(.identifier(name))

      var type = TypeNode.generic(base: name, args: args)
      if currentToken === .refKeyword {
        try match(.refKeyword)
        type = .reference(type)
      }
      return type
    }

    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(
        line: lexer.currentLine, got: currentToken.description)
    }

    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(line: lexer.currentLine, name: name)
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
    name: String, mutable: Bool, access: AccessModifier, line: Int
  ) throws -> GlobalNode {
    var type: TypeNode = .identifier("Int")
    if currentToken !== .equal {
      type = try parseType()
    }

    try match(.equal)
    let value = try expression()
    return .globalVariableDeclaration(
      name: name, type: type, value: value, mutable: mutable, access: access, line: line)
  }

  private func parseTypeParameters() throws -> [TypeParameterDecl] {
    var parameters: [TypeParameterDecl] = []
    if currentToken === .leftBracket {
      try match(.leftBracket)
      while currentToken !== .rightBracket {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.expectedIdentifier(
            line: lexer.currentLine, got: currentToken.description)
        }
        try match(.identifier(paramName))

        var constraints: [TypeNode] = []
        if currentToken !== .comma && currentToken !== .rightBracket {
          constraints.append(try parseTraitConstraint())
          while currentToken === .andKeyword {
            try match(.andKeyword)
            constraints.append(try parseTraitConstraint())
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
    guard case .identifier(let name) = currentToken else {
      throw ParserError.expectedTypeIdentifier(line: lexer.currentLine, got: currentToken.description)
    }
    if !isValidTypeName(name) {
      throw ParserError.invalidTypeName(line: lexer.currentLine, name: name)
    }
    try match(.identifier(name))
    return .identifier(name)
  }

  // Parse global function declaration with optional 'own'/'ref' modifiers for params and return type
  private func globalFunctionDeclaration(
    name: String, typeParams: [TypeParameterDecl], access: AccessModifier,
    isIntrinsic: Bool, line: Int
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
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
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
          line: lexer.currentLine, got: "Intrinsic function should not have body")
      }
      return .intrinsicFunctionDeclaration(
        name: name,
        typeParameters: typeParams,
        parameters: parameters,
        returnType: returnType,
        access: access,
        line: line
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
        line: line
      )
    }
  }

  // Parse type declaration
  private func parseStructDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier,
    isIntrinsic: Bool, line: Int
  ) throws -> GlobalNode {
    if isIntrinsic {
      if currentToken === .leftParen {
        throw ParserError.unexpectedToken(
          line: lexer.currentLine, got: "Intrinsic type should not have body")
      }
      return .intrinsicTypeDeclaration(
        name: name, typeParameters: typeParams, access: access, line: line)
    }

    if currentToken === .leftBrace {
      return try parseUnionDeclaration(name, typeParams: typeParams, access: access, line: line)
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
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
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

    var isCopy = false
    if case .identifier("Copy") = currentToken {
      try match(.identifier("Copy"))
      isCopy = true
    }

    return .globalStructDeclaration(
      name: name,
      typeParameters: typeParams,
      parameters: parameters,
      access: access,
      isCopy: isCopy,
      line: line
    )
  }

  // Parse union declaration (sum type)
  private func parseUnionDeclaration(
    _ name: String, typeParams: [TypeParameterDecl], access: AccessModifier, line: Int
  ) throws -> GlobalNode {
    try match(.leftBrace)
    var cases: [UnionCaseDeclaration] = []

    while currentToken !== .rightBrace {
      guard case .identifier(let caseName) = currentToken else {
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
      }
      try match(.identifier(caseName))

      var parameters: [(name: String, type: TypeNode)] = []
      try match(.leftParen)

      while currentToken !== .rightParen {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.expectedIdentifier(
            line: lexer.currentLine, got: currentToken.description)
        }
        try match(.identifier(paramName))
        let paramType = try parseType()
        parameters.append((name: paramName, type: paramType))

        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightParen)
      try match(.semicolon)
      cases.append(UnionCaseDeclaration(name: caseName, parameters: parameters))
    }

    try match(.rightBrace)

    var isCopy = false
    if case .identifier("Copy") = currentToken {
      try match(.identifier("Copy"))
      isCopy = true
    }

    return .globalUnionDeclaration(
      name: name,
      typeParameters: typeParams,
      cases: cases,
      access: access,
      isCopy: isCopy,
      line: line
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
      if currentToken === .semicolon || currentToken === .rightBrace {
        return .return(value: nil, line: lexer.currentLine)
      }
      let value = try expression()
      return .return(value: value, line: lexer.currentLine)
    case .breakKeyword:
      try match(.breakKeyword)
      return .break(line: lexer.currentLine)
    case .continueKeyword:
      try match(.continueKeyword)
      return .continue(line: lexer.currentLine)
    default:
      let expr = try expression()

      if currentToken === .equal {
        try match(.equal)
        let value = try expression()
        return .assignment(target: expr, value: value, line: lexer.currentLine)
      } else if let op = getCompoundAssignmentOperator(currentToken) {
        try match(currentToken)
        let value = try expression()
        return .compoundAssignment(
          target: expr, operator: op, value: value, line: lexer.currentLine)
      }
      return .expression(expr, line: lexer.currentLine)
    }
  }

  private func getCompoundAssignmentOperator(_ token: Token) -> CompoundAssignmentOperator? {
    switch token {
    case .plusEqual: return .plus
    case .minusEqual: return .minus
    case .multiplyEqual: return .multiply
    case .divideEqual: return .divide
    case .moduloEqual: return .modulo
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
      throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
    }

    if !isValidVariableName(name) {
      throw ParserError.invalidVariableName(line: lexer.currentLine, name: name)
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
        line: lexer.currentLine)
    }

    return .variableDeclaration(
      name: name, type: type, value: value, mutable: mutable, line: lexer.currentLine)
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
      if currentToken === .dot {
        try match(.dot)
        guard case .identifier(let member) = currentToken else {
          throw ParserError.expectedIdentifier(
            line: lexer.currentLine, got: currentToken.description)
        }
        try match(.identifier(member))
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

  private func parsePattern() throws -> PatternNode {
    // Literal Patterns
    if case .integer(let v) = currentToken {
      try match(.integer(v))
      return .integerLiteral(value: v, line: lexer.currentLine)
    }
    if case .bool(let v) = currentToken {
      try match(.bool(v))
      return .booleanLiteral(value: v, line: lexer.currentLine)
    }
    if case .identifier(let name) = currentToken {
      if name == "_" {
        try match(.identifier(name))
        return .wildcard(line: lexer.currentLine)
      }
      // Variable binding or Enum Case? Koral uses .Case for Enum
      try match(.identifier(name))
      return .variable(name: name, mutable: false, line: lexer.currentLine)
    }
    if case .string(let str) = currentToken {
      try match(.string(str))
      return .stringLiteral(value: str, line: lexer.currentLine)
    }
    if currentToken === .mutKeyword {
      try match(.mutKeyword)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
      }
      try match(.identifier(name))
      return .variable(name: name, mutable: true, line: lexer.currentLine)
    }
    if currentToken === .dot {
      try match(.dot)
      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
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
      return .unionCase(caseName: name, elements: args, line: lexer.currentLine)
    }
    throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
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
    } else {
      return try parseOrExpression()
    }
  }

  private func parseOrExpression() throws -> ExpressionNode {
    var left = try parseAndExpression()

    while currentToken === .orKeyword {
      try match(.orKeyword)
      let right = try parseAndExpression()
      left = .orExpression(left: left, right: right)
    }
    return left
  }

  private func parseAndExpression() throws -> ExpressionNode {
    var left = try parseLogicalNotExpression()

    while currentToken === .andKeyword {
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
    while currentToken === .bitorKeyword {
      try match(.bitorKeyword)
      let right = try parseBitwiseXorExpression()
      left = .bitwiseExpression(left: left, operator: .or, right: right)
    }
    return left
  }

  private func parseBitwiseXorExpression() throws -> ExpressionNode {
    var left = try parseBitwiseAndExpression()
    while currentToken === .bitxorKeyword {
      try match(.bitxorKeyword)
      let right = try parseBitwiseAndExpression()
      left = .bitwiseExpression(left: left, operator: .xor, right: right)
    }
    return left
  }

  private func parseBitwiseAndExpression() throws -> ExpressionNode {
    var left = try parseComparisonExpression()
    while currentToken === .bitandKeyword {
      try match(.bitandKeyword)
      let right = try parseComparisonExpression()
      left = .bitwiseExpression(left: left, operator: .and, right: right)
    }
    return left
  }

  // Fourth level: Comparisons
  private func parseComparisonExpression() throws -> ExpressionNode {
    var left = try parseShiftExpression()

    while currentToken === .equalEqual || currentToken === .notEqual || currentToken === .greater
      || currentToken === .less || currentToken === .greaterEqual || currentToken === .lessEqual
    {
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
    while currentToken === .bitshlKeyword || currentToken === .bitshrKeyword {
      let op = currentToken
      try match(op)
      let right = try parseAdditiveExpression()
      let bitOp: BitwiseOperator = (op === .bitshlKeyword) ? .shiftLeft : .shiftRight
      left = .bitwiseExpression(left: left, operator: bitOp, right: right)
    }
    return left
  }

  // Fifth level: Addition and subtraction
  private func parseAdditiveExpression() throws -> ExpressionNode {
    var left = try parseMultiplicativeExpression()

    while currentToken === .plus || currentToken === .minus {
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
    var left = try parsePrefixExpression()

    while currentToken === .multiply || currentToken === .divide || currentToken === .modulo {
      let op = currentToken
      try match(op)
      let right = try parsePrefixExpression()
      left = .arithmeticExpression(
        left: left,
        operator: tokenToArithmeticOperator(op),
        right: right
      )
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
    } else if currentToken === .bitnotKeyword {
      try match(.bitnotKeyword)
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
        throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
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
    try match(.ifKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let thenBranch = try expression()

    var elseBranch: ExpressionNode? = nil
    if currentToken === .elseKeyword {
      try match(.elseKeyword)
      elseBranch = try expression()
    }
    return .ifExpression(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch)
  }

  private func whileExpression() throws -> ExpressionNode {
    try match(.whileKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .whileExpression(condition: condition, body: body)
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

      // Optional semicolon between cases (required unless next token is `}`)
      if currentToken === .semicolon { try match(.semicolon) }
      cases.append(MatchCaseNode(pattern: pattern, body: body))
    }
    try match(.rightBrace)
    return .matchExpression(subject: subject, cases: cases, line: lexer.currentLine)
  }

  private func tokenToArithmeticOperator(_ token: Token) -> ArithmeticOperator {
    switch token {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .modulo: return .modulo
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
    case .integer(let num):
      try match(.integer(num))
      return .integerLiteral(num)
    case .float(let num):
      try match(.float(num))
      return .floatLiteral(num)
    case .string(let str):
      try match(.string(str))
      return .stringLiteral(str)
    case .bool(let value):
      try match(.bool(value))
      return .booleanLiteral(value)
    case .leftBrace:
      return try blockExpression()
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
          line: lexer.currentLine, got: currentToken.description)
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
        line: lexer.currentLine,
        got: currentToken.description,
        expected: "number, identifier, boolean literal, block expression, or generic instantiation"
      )
    }
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
        throw ParserError.unexpectedEndOfFile(line: lexer.currentLine)
      }

      let stmt = try statement()
      statements.append(stmt)

      // If current statement is an expression and next token is right brace,
      // this is the final expression
      if case .expression(let expr, _) = stmt {
        if currentToken === .rightBrace {
          try match(.rightBrace)
          return .blockExpression(
            statements: Array(statements.dropLast()),
            finalExpression: expr
          )
        }
      }

      try match(.semicolon)

      // if next token is right brace, return block expression
      if currentToken === .rightBrace {
        try match(.rightBrace)
        return .blockExpression(statements: statements, finalExpression: nil)
      }
    }
    throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
  }

  private func isValidVariableName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    return first.isLowercase
  }

  private func isValidTypeName(_ name: String) -> Bool {
    guard let first = name.first else { return false }
    return first.isUppercase
  }
}

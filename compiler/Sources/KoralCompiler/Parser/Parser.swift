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
        return try globalVariableDeclaration(name: name, mutable: true)
      }

      // Otherwise check for left paren to determine if it's a function or variable
      if currentToken === .leftParen {
        return try globalFunctionDeclaration(name: name, typeParams: typePrams)
      } else {
        return try globalVariableDeclaration(name: name, mutable: false)
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
      return try parseTypeDeclaration(name, typeParams: typeParams)
    } else if currentToken === .givenKeyword {
      return try parseGivenDeclaration()
    } else {
      throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
    }
  }

  private func parseGivenDeclaration() throws -> GlobalNode {
    try match(.givenKeyword)
    let type = try parseType()
    try match(.leftBrace)
    var methods: [MethodDeclaration] = []
    while currentToken !== .rightBrace {
      let typeParams = try parseTypeParameters()

      guard case .identifier(let name) = currentToken else {
        throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
      }
      try match(.identifier(name))

      try match(.leftParen)
      var parameters: [(name: String, mutable: Bool, type: TypeNode)] = []
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
          body: body
        ))
    }
    try match(.rightBrace)
    return .givenDeclaration(type: type, methods: methods)
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
  private func globalVariableDeclaration(name: String, mutable: Bool) throws -> GlobalNode {
    let type = try parseType()
    try match(.equal)
    let value = try expression()
    return .globalVariableDeclaration(name: name, type: type, value: value, mutable: mutable)
  }

  private func parseTypeParameters() throws -> [String] {
    var parameters: [String] = []
    if currentToken === .leftBracket {
      try match(.leftBracket)
      while currentToken !== .rightBracket {
        guard case .identifier(let paramName) = currentToken else {
          throw ParserError.expectedIdentifier(
            line: lexer.currentLine, got: currentToken.description)
        }
        try match(.identifier(paramName))

        parameters.append(paramName)

        if currentToken === .comma {
          try match(.comma)
        }
      }
      try match(.rightBracket)
    }
    return parameters
  }

  // Parse global function declaration with optional 'own'/'ref' modifiers for params and return type
  private func globalFunctionDeclaration(name: String, typeParams: [String]) throws -> GlobalNode {
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
    try match(.equal)
    let body = try expression()
    return .globalFunctionDeclaration(
      name: name,
      typeParameters: typeParams,
      parameters: parameters,
      returnType: returnType,
      body: body
    )
  }
    
  // Parse type declaration
  private func parseTypeDeclaration(_ name: String, typeParams: [String]) throws -> GlobalNode {
    try match(.leftParen)
    var parameters: [(name: String, type: TypeNode, mutable: Bool)] = []
    while currentToken !== .rightParen {
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

      parameters.append((name: paramName, type: paramType, mutable: fieldMutable))

      if currentToken === .comma {
        try match(.comma)
      }
    }
    try match(.rightParen)

    return .globalTypeDeclaration(
      name: name,
      typeParameters: typeParams,
      parameters: parameters
    )
  }

  // Parse statement
  private func statement() throws -> StatementNode {
    switch currentToken {
    case .letKeyword:
      return try variableDeclaration()
    case .identifier(_):
      let expr = try expression()

      if currentToken === .equal {
        try match(.equal)
        let target: AssignmentTarget
        switch expr {
        case .identifier(let name):
          target = .variable(name: name)
        case .memberPath(let base, let path):
          if case .identifier(let baseName) = base {
            target = .memberAccess(base: baseName, memberPath: path)
          } else {
            throw ParserError.unexpectedToken(
              line: lexer.currentLine, got: "invalid assignment target")
          }
        default:
          throw ParserError.unexpectedToken(
            line: lexer.currentLine, got: "invalid assignment target")
        }

        let value = try expression()
        return .assignment(target: target, value: value)
      } else if let op = getCompoundAssignmentOperator(currentToken) {
        try match(currentToken)
        let target: AssignmentTarget
        switch expr {
        case .identifier(let name):
          target = .variable(name: name)
        case .memberPath(let base, let path):
          if case .identifier(let baseName) = base {
            target = .memberAccess(base: baseName, memberPath: path)
          } else {
            throw ParserError.unexpectedToken(
              line: lexer.currentLine, got: "invalid assignment target")
          }
        default:
          throw ParserError.unexpectedToken(
            line: lexer.currentLine, got: "invalid assignment target")
        }
        let value = try expression()
        return .compoundAssignment(target: target, operator: op, value: value)
      }
      return .expression(expr)
    default:
      return .expression(try expression())
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
        .letExpression(name: name, type: type, value: value, mutable: mutable, body: body))
    }

    return .variableDeclaration(name: name, type: type, value: value, mutable: mutable)
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
      } else {
        break
      }
    }
    return expr
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

  private func ifExpression() throws -> ExpressionNode {
    try match(.ifKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let thenBranch = try expression()
    try match(.elseKeyword)
    let elseBranch = try expression()
    return .ifExpression(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch)
  }

  private func whileExpression() throws -> ExpressionNode {
    try match(.whileKeyword)
    let condition = try expression()
    try match(.thenKeyword)
    let body = try expression()
    return .whileExpression(condition: condition, body: body)
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
    case .leftParen:
      try match(.leftParen)
      let expr = try expression()
      try match(.rightParen)
      return expr
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
        expected: "number, identifier, or boolean literal"
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
      if case .expression(let expr) = stmt {
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

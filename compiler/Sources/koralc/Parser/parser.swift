

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
            
            guard case let .identifier(name) = currentToken else {
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
                return try globalFunctionDeclaration(name: name)
            } else {
                return try globalVariableDeclaration(name: name, mutable: false)
            }
        } else if currentToken === .typeKeyword {
            try match(.typeKeyword)
            guard case let .identifier(name) = currentToken else {
                throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
            }
            
            if !isValidTypeName(name) {
                throw ParserError.invalidTypeName(line: lexer.currentLine, name: name)
            }
            
            try match(.identifier(name))
            return try parseTypeDeclaration(name)
        } else {
            throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
        }
    }

    // Parse type identifier
    private func parseType() throws -> TypeNode {
        guard case let .identifier(name) = currentToken else {
            throw ParserError.expectedTypeIdentifier(line: lexer.currentLine, got: currentToken.description)
        }
        
        if !isValidTypeName(name) {
            throw ParserError.invalidTypeName(line: lexer.currentLine, name: name)
        }
        
        try match(.identifier(name))
        return .identifier(name)
    }

    // Parse global variable declaration
    private func globalVariableDeclaration(name: String, mutable: Bool) throws -> GlobalNode {
        try match(.colon)
        let type = try parseType()
        try match(.equal)
        let value = try expression()
        return .globalVariableDeclaration(name: name, type: type, value: value, mutable: mutable)
    }

    // Parse global function declaration
    private func globalFunctionDeclaration(name: String) throws -> GlobalNode {
        try match(.leftParen)
        
        var parameters: [(name: String, type: TypeNode)] = []
        while currentToken !== .rightParen {
            guard case let .identifier(paramName) = currentToken else {
                throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
            }
            try match(.identifier(paramName))
            try match(.colon)
            let paramType = try parseType()
            
            parameters.append((name: paramName, type: paramType))
            
            if currentToken === .comma {
                try match(.comma)
            }
        }
        try match(.rightParen)
        
        try match(.colon)
        let returnType = try parseType()
        
        try match(.equal)
        let body = try expression()
        
        return .globalFunctionDeclaration(
            name: name,
            parameters: parameters,
            returnType: returnType,
            body: body
        )
    }

    // Parse type declaration
    private func parseTypeDeclaration(_ name: String) throws -> GlobalNode {
        try match(.leftParen)
        
        var parameters: [(name: String, type: TypeNode)] = []
        while currentToken !== .rightParen {
            guard case let .identifier(paramName) = currentToken else {
                throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
            }
            try match(.identifier(paramName))
            try match(.colon)
            let paramType = try parseType()
            
            parameters.append((name: paramName, type: paramType))
            
            if currentToken === .comma {
                try match(.comma)
            }
        }
        try match(.rightParen)
        
        return .globalTypeDeclaration(name: name, parameters: parameters)
    }

    // Parse statement
    private func statement() throws -> StatementNode {
        if currentToken === .letKeyword {
            return try variableDeclaration()
        } else if case let .identifier(name) = currentToken {
            // Check if it's an assignment statement
            try match(.identifier(name))
            if currentToken === .equal {
                try match(.equal)
                let value = try expression()
                return .assignment(name: name, value: value)
            }
            // If not assignment, treat as expression or function call
            // check if it's a function call
            if currentToken === .leftParen {
                return .expression(try parseFunctionCall(name))
            }
            return .expression(.identifier(name))
        } else {
            return .expression(try expression())
        }
    }

    // Parse variable declaration
    private func variableDeclaration() throws -> StatementNode {
        try match(.letKeyword)
        var mutable = false
        if currentToken === .mutKeyword {
            try match(.mutKeyword)
            mutable = true
        }
        guard case let .identifier(name) = currentToken else {
            throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
        }
        
        if !isValidVariableName(name) {
            throw ParserError.invalidVariableName(line: lexer.currentLine, name: name)
        }
        
        try match(.identifier(name))
        try match(.colon)
        let type = try parseType()
        try match(.equal)
        let value = try expression()
        return .variableDeclaration(name: name, type: type, value: value, mutable: mutable)
    }

    // Parse expression rule
    private func expression() throws -> ExpressionNode {
        return if currentToken === .leftBrace {
            try blockExpression()
        } else if currentToken === .ifKeyword {
            try ifExpression()
        } else if currentToken === .whileKeyword {
            try whileExpression()
        } else {
            try parseOrExpression()
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
        var left = try parseNotExpression()
        
        while currentToken === .andKeyword {
            try match(.andKeyword)
            let right = try parseNotExpression()
            left = .andExpression(left: left, right: right)
        }
        return left
    }

    private func parseNotExpression() throws -> ExpressionNode {
        if currentToken === .notKeyword {
            try match(.notKeyword)
            let expr = try parseComparisonExpression()
            return .notExpression(expr)
        }
        return try parseComparisonExpression()
    }

    // Fourth level: Comparisons
    private func parseComparisonExpression() throws -> ExpressionNode {
        var left = try parseAdditiveExpression()
        
        while currentToken === .equalEqual || currentToken === .notEqual ||
            currentToken === .greater || currentToken === .less ||
            currentToken === .greaterEqual || currentToken === .lessEqual {
            let op = currentToken
            try match(op)
            let right = try parseAdditiveExpression()
            left = .comparisonExpression(
                left: left,
                operator: tokenToComparisonOperator(op),
                right: right
            )
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
        var left = try parseMemberAccess()
        
        while currentToken === .multiply || currentToken === .divide || currentToken === .modulo {
            let op = currentToken
            try match(op)
            let right = try parseMemberAccess()
            left = .arithmeticExpression(
                left: left,
                operator: tokenToArithmeticOperator(op),
                right: right
            )
        }
        return left
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
        case let .identifier(name):
            try match(.identifier(name))
            // check if it's a function call
            if currentToken === .leftParen {
                return try parseFunctionCall(name)
            }
            return .identifier(name)
        case let .integer(num):
            try match(.integer(num))
            return .integerLiteral(num)
        case let .float(num):
            try match(.float(num))
            return .floatLiteral(num)
        case let .string(str):
            try match(.string(str))
            return .stringLiteral(str)
        case let .bool(value):
            try match(.bool(value))
            return .booleanLiteral(value)
        default:
            throw ParserError.unexpectedToken(
                line: lexer.currentLine, 
                got: currentToken.description, 
                expected: "number, identifier, or boolean literal"
            )
        }
    }

    // 新增parseMemberAccess作为最高优先级
    private func parseMemberAccess() throws -> ExpressionNode {
        var expr = try term()
        
        while currentToken === .dot {
            try match(.dot)
            guard case let .identifier(member) = currentToken else {
                throw ParserError.expectedIdentifier(line: lexer.currentLine, got: currentToken.description)
            }
            try match(.identifier(member))
            expr = .memberAccess(expr: expr, member: member)
        }
        
        return expr
    }

    // Parse function call
    private func parseFunctionCall(_ name: String) throws -> ExpressionNode {
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
        return .functionCall(name: name, arguments: arguments)
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
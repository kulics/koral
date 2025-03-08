// Define AST node types using enums
public indirect enum ASTNode {
    case program(globalNodes: [GlobalNode])
}

public indirect enum TypeNode {
    case identifier(String)
}

public indirect enum GlobalNode {
    case globalVariableDeclaration(name: String, type: TypeNode, value: ExpressionNode, mutable: Bool)
    case globalFunctionDeclaration(
        name: String, 
        parameters: [(name: String, type: TypeNode)], 
        returnType: TypeNode, 
        body: ExpressionNode
    )
}

public indirect enum StatementNode {
    case variableDeclaration(name: String, type: TypeNode, value: ExpressionNode, mutable: Bool)
    case assignment(name: String, value: ExpressionNode)
    case expression(ExpressionNode)
}

public indirect enum ExpressionNode {
    case integerLiteral(Int)
    case floatLiteral(Double)
    case stringLiteral(String)
    case boolLiteral(Bool)
    case binaryExpression(left: ExpressionNode, operatorToken: Token, right: ExpressionNode)
    case identifier(String)
    case blockExpression(statements: [StatementNode], finalExpression: ExpressionNode)
}

public enum ParserError: Error {
    case unexpectedToken(line: Int, got: String, expected: String? = nil)
    case expectedIdentifier(line: Int, got: String)
    case expectedTypeIdentifier(line: Int, got: String)
    case unexpectedEndOfFile(line: Int)
    case expectedFinalExpression(line: Int)
}

extension ParserError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unexpectedToken(line, token, expected):
            if let exp = expected {
                return "Line \(line): Unexpected token: \(token), expected: \(exp)"
            }
            return "Line \(line): Unexpected token: \(token)"
        case let .expectedIdentifier(line, token):
            return "Line \(line): Expected identifier, got: \(token)"
        case let .expectedTypeIdentifier(line, token):
            return "Line \(line): Expected type identifier, got: \(token)"
        case let .unexpectedEndOfFile(line):
            return "Line \(line): Unexpected end of file"
        case let .expectedFinalExpression(line):
            return "Line \(line): Expected final expression in block expression"
        }
    }
}

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
        } else {
            throw ParserError.unexpectedToken(line: lexer.currentLine, got: currentToken.description)
        }
    }

    // Parse type identifier
    private func parseType() throws -> TypeNode {
        guard case let .identifier(name) = currentToken else {
            throw ParserError.expectedTypeIdentifier(line: lexer.currentLine, got: currentToken.description)
        }
        try match(.identifier(name))
        return .identifier(name)
    }

    // Parse global variable declaration
    private func globalVariableDeclaration(name: String, mutable: Bool) throws -> GlobalNode {
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
            
            let paramType = try parseType()
            
            parameters.append((name: paramName, type: paramType))
            
            if currentToken === .comma {
                try match(.comma)
            }
        }
        try match(.rightParen)
        
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
            // If not assignment, treat as expression
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
        try match(.identifier(name))

        let type = try parseType()
        try match(.equal)
        let value = try expression()
        return .variableDeclaration(name: name, type: type, value: value, mutable: mutable)
    }

    // Parse expression rule
    private func expression() throws -> ExpressionNode {
        if currentToken === .leftBrace {
            return try blockExpression()
        }
        var left = try term()
        while currentToken === .plus ||
         currentToken === .minus ||
          currentToken === .multiply ||
           currentToken === .divide ||
            currentToken === .modulo ||
             currentToken === .equalEqual ||
              currentToken === .notEqual ||
               currentToken === .greater ||
                currentToken === .less ||
                 currentToken === .greaterEqual ||
                  currentToken === .lessEqual {
            let op = currentToken
            try match(op)
            let right = try term()
            left = .binaryExpression(left: left, operatorToken: op, right: right)
        }
        return left
    }

    // Parse term
    private func term() throws -> ExpressionNode {
        switch currentToken {
        case let .integer(num):
            try match(.integer(num))
            return .integerLiteral(num)
        case let .float(num):
            try match(.float(num))
            return .floatLiteral(num)
        case let .string(str):
            try match(.string(str))
            return .stringLiteral(str)
        case let .identifier(name):
            try match(.identifier(name))
            return .identifier(name)
        case let .bool(value):
            try match(.bool(value))
            return .boolLiteral(value)
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
        // Parse statements until we find the final expression
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
                    return .blockExpression(statements: Array(statements.dropLast()), 
                                        finalExpression: expr)
                }
            }
            
            // Statements must be followed by semicolons
            try match(.semicolon)
        }
        throw ParserError.expectedFinalExpression(line: lexer.currentLine)
    }
}

// Helper functions: Print AST
func printAST(_ node: ASTNode, indent: String = "") {
    switch node {
    case let .program(statements):
        print("\(indent)Program:")
        for statement in statements {
            printGlobalNode(statement, indent: indent + "  ")
        }
    }
}

func printGlobalNode(_ node: GlobalNode, indent: String = "") {
    switch node {
    case let .globalVariableDeclaration(name, type, value, mutable):
        print("\(indent)GlobalVariableDeclaration:")
        print("\(indent)  Name: \(name)")
        print("\(indent)  Type: \(type)")
        print("\(indent)  Mutable: \(mutable)")
        printExpression(value, indent: indent + "  ")
    case let .globalFunctionDeclaration(name, parameters, returnType, body):
        print("\(indent)GlobalFunctionDeclaration:")
        print("\(indent)  Name: \(name)")
        print("\(indent)  Parameters:")
        for param in parameters {
            print("\(indent)    \(param.name): \(param.type)")
        }
        print("\(indent)  ReturnType: \(returnType)")
        print("\(indent)  Body:")
        printExpression(body, indent: indent + "    ")
    }
}

func printStatement(_ node: StatementNode, indent: String = "") {
    switch node {
    case let .variableDeclaration(name, type, value, mutable):
        print("\(indent)VariableDeclaration:")
        print("\(indent)  Name: \(name)")
        print("\(indent)  Type: \(type)")
        print("\(indent)  Mutable: \(mutable)")
        printExpression(value, indent: indent + "  ")
    case let .assignment(name, value):
        print("\(indent)Assignment:")
        print("\(indent)  Name: \(name)")
        print("\(indent)  Value:")
        printExpression(value, indent: indent + "    ")
    case let .expression(expr):
        printExpression(expr, indent: indent)
    }
}

func printExpression(_ node: ExpressionNode, indent: String = "") {
    switch node {
    case let .integerLiteral(value):
        print("\(indent)IntegerLiteral: \(value)")
    case let .floatLiteral(value):
        print("\(indent)FloatLiteral: \(value)")
    case let .stringLiteral(str):
        print("\(indent)StringLiteral: \(str)")
    case let .boolLiteral(value):
        print("\(indent)BoolLiteral: \(value)")
    case let .binaryExpression(left, operatorToken, right):
        print("\(indent)BinaryExpression:")
        printExpression(left, indent: indent + "  ")
        switch operatorToken {
        case .plus:
            print("\(indent)  Operator: +")
        case .minus:
            print("\(indent)  Operator: -")
        case .multiply:
            print("\(indent)  Operator: *")
        case .divide:
            print("\(indent)  Operator: /")
        case .modulo:
            print("\(indent)  Operator: %")
        case .equalEqual:
            print("\(indent)  Operator: ==")
        case .notEqual:
            print("\(indent)  Operator: !=")
        case .greater:
            print("\(indent)  Operator: >")
        case .less:
            print("\(indent)  Operator: <")
        case .greaterEqual:
            print("\(indent)  Operator: >=")
        case .lessEqual:
            print("\(indent)  Operator: <=")
        default:
            fatalError("Unexpected operator token in BinaryExpression.")
        }
        printExpression(right, indent: indent + "  ")
    case let .identifier(name):
        print("\(indent)Identifier: \(name)")
    case let .blockExpression(statements, finalExpression):
        print("\(indent)BlockExpression:")
        for statement in statements {
            printStatement(statement, indent: indent + "  ")
        }
        print("\(indent)  FinalExpression:")
        printExpression(finalExpression, indent: indent + "    ")
    }
}
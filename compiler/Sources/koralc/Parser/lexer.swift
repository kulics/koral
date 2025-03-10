// Define token types for lexical analysis
public enum Token: CustomStringConvertible {
    case bof             // Beginning of file marker
    case eof             // End of file marker
    case integer(Int)    // Integer literal, e.g.: 42
    case float(Double)   // Float literal, e.g.: 3.14
    case string(String)  // String literal, e.g.: "hello"
    case plus           // Plus operator '+'
    case minus          // Minus operator '-'
    case multiply       // Multiply operator '*'
    case divide         // Divide operator '/'
    case modulo         // Modulo operator '%'
    case equal          // Equal sign '='
    case equalEqual     // Equals operator '=='
    case notEqual       // Not equals operator '!='
    case greater        // Greater than operator '>'
    case less           // Less than operator '<'
    case greaterEqual   // Greater than or equal operator '>='
    case lessEqual      // Less than or equal operator '<='
    case identifier(String) // Identifier, e.g.: variableName, Int, Float, String
    case letKeyword     // 'let' keyword
    case mutKeyword     // 'mut' keyword
    case semicolon      // Semicolon ';'
    case leftParen      // Left parenthesis '('
    case rightParen     // Right parenthesis ')'
    case comma          // Comma ','
    case leftBrace      // Left brace '{'
    case rightBrace     // Right brace '}'
    case bool(Bool)     // Boolean literal, e.g.: true, false
    case ifKeyword      // 'if' keyword
    case thenKeyword    // 'then' keyword
    case elseKeyword    // 'else' keyword
    case whileKeyword   // 'while' keyword

    // Add static operator function to compare if the same item
    public static func ===(lhs: Token, rhs: Token) -> Bool {
        switch (lhs, rhs) {
        case (.integer, .integer),
             (.float, .float),
             (.string, .string),
             (.plus, .plus),
             (.minus, .minus),
             (.multiply, .multiply),
             (.divide, .divide),
             (.modulo, .modulo),
             (.equal, .equal),
             (.equalEqual, .equalEqual),
             (.notEqual, .notEqual),
             (.greater, .greater),
             (.less, .less),
             (.greaterEqual, .greaterEqual),
             (.lessEqual, .lessEqual),
             (.identifier, .identifier),
             (.letKeyword, .letKeyword),
             (.mutKeyword, .mutKeyword),
             (.semicolon, .semicolon),
             (.leftParen, .leftParen),
             (.rightParen, .rightParen),
             (.comma, .comma),
             (.leftBrace, .leftBrace),
             (.rightBrace, .rightBrace),
             (.eof, .eof),
             (.bool, .bool),
             (.ifKeyword, .ifKeyword),
             (.thenKeyword, .thenKeyword),
             (.elseKeyword, .elseKeyword),
             (.whileKeyword, .whileKeyword):
            return true
        default:
            return false
        }
    }

    public static func !==(lhs: Token, rhs: Token) -> Bool {
        return !(lhs === rhs)
    }

    public var description: String {
        switch self {
        case .integer(let value):
            return "Integer(\(value))"
        case .float(let value):
            return "Float(\(value))"
        case .string(let value):
            return "String(\(value))"
        case .plus:
            return "+"
        case .minus:
            return "-"
        case .multiply:
            return "*"
        case .divide:
            return "/"
        case .modulo:
            return "%"
        case .equal:
            return "="
        case .equalEqual:
            return "=="
        case .notEqual:
            return "!="
        case .greater:
            return ">"
        case .less:
            return "<"
        case .greaterEqual:
            return ">="
        case .lessEqual:
            return "<="
        case .identifier(let value):
            return "Identifier(\(value))"
        case .letKeyword:
            return "let"
        case .mutKeyword:
            return "mut"
        case .semicolon:
            return ";"
        case .leftParen:
            return "("
        case .rightParen:
            return ")"
        case .comma:
            return ","
        case .leftBrace:
            return "{"
        case .rightBrace:
            return "}"
        case .eof:
            return "EOF"
        case .bof:
            return "BOF"
        case .bool(let value):
            return "Bool(\(value))"
        case .ifKeyword:
            return "if"
        case .thenKeyword:
            return "then"
        case .elseKeyword:
            return "else"
        case .whileKeyword:
            return "while"
        }
    }
}

// Enumeration for number literal return values
private enum NumberLiteral {
    case integer(Int)
    case float(Double)
}

// Define lexer error types
public enum LexerError: Error {
    case invalidFloat(line: Int, String)
    case invalidString(line: Int, String)
    case unexpectedCharacter(line: Int, String)
}

extension LexerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidFloat(line, msg):
            return "Line \(line): Invalid float number: \(msg)"
        case let .invalidString(line, msg):
            return "Line \(line): Invalid string: \(msg)"
        case let .unexpectedCharacter(line, msg):
            return "Line \(line): Unexpected character: \(msg)"
        }
    }
}

// Lexical analyzer class
public class Lexer {
    private let input: String
    private var position: String.Index
    private var _line: Int = 1
    
    // Current line number property
    public var currentLine: Int {
        return _line
    }

    public init(input: String) {
        self.input = input
        self.position = input.startIndex
    }

    // Get next character
    private func getNextChar() -> Character? {
        guard position < input.endIndex else { return nil }
        let char = input[position]
        position = input.index(after: position)
        if char.isNewline {
            _line += 1
        }
        return char
    }

    // Skip whitespace characters
    private func skipWhitespace() {
        while let char = getNextChar() {
            if (!char.isWhitespace) {
                position = input.index(before: position)
                break
            }
        }
    }
    
    // Skip line comments
    private func skipLineComment() {
        while let char = getNextChar() {
            if char.isNewline {
                break
            }
        }
    }

    // Read a number, handling both integers and floats
    private func readNumber() throws -> NumberLiteral {
        var numStr = ""
        var hasDot = false
        while let char = getNextChar() {
            if char.isNumber {
                numStr.append(char)
            } else if char == "." {
                if hasDot {
                    throw LexerError.invalidFloat(line: _line, "consecutive dots are not allowed")
                }
                hasDot = true
                numStr.append(char)
            } else {
                position = input.index(before: position)
                break
            }
        }

        if hasDot {
            return .float(Double(numStr)!)
        } else {
            return .integer(Int(numStr)!)
        }
    }

    // Read a string literal
    private func readString() throws -> String {
        var str = ""
        guard let startChar = getNextChar(), startChar == "\"" else {
            throw LexerError.invalidString(line: _line, "expected string start with \"")
        }
        while let char = getNextChar() {
            if char == "\"" {
                break
            }
            str.append(char)
        }
        return str
    }

    // Read an identifier
    private func readIdentifier() -> String {
        var idStr = ""
        while let char = getNextChar() {
            if char.isLetter || char.isNumber || char == "_" {
                idStr.append(char)
            } else {
                position = input.index(before: position)
                break
            }
        }
        return idStr
    }

    // Get next token
    public func getNextToken() throws -> Token {
        skipWhitespace()
        guard let char = getNextChar() else {
            return .eof
        }
        switch char {
        case "+":
            return .plus
        case "-":
            return .minus
        case "*":
            return .multiply
        case "/":
            if let nextChar = getNextChar(), nextChar == "/" {
                skipLineComment()
                return try getNextToken()
            } else {
                position = input.index(before: position)
                return .divide
            }
        case "%":
            return .modulo
        case "=":
            if let nextChar = getNextChar(), nextChar == "=" {
                return .equalEqual
            } else {
                position = input.index(before: position)
                return .equal
            }
        case "!":
            if let nextChar = getNextChar(), nextChar == "=" {
                return .notEqual
            } else {
                throw LexerError.unexpectedCharacter(line: _line, "!")
            }
        case ">":
            if let nextChar = getNextChar(), nextChar == "=" {
                return .greaterEqual
            } else {
                position = input.index(before: position)
                return .greater
            }
        case "<":
            if let nextChar = getNextChar(), nextChar == "=" {
                return .lessEqual
            } else {
                position = input.index(before: position)
                return .less
            }
        case ";":
            return .semicolon
        case "(":
            return .leftParen
        case ")":
            return .rightParen
        case ",":
            return .comma
        case "{":
            return .leftBrace
        case "}":
            return .rightBrace
        case "\"":
            position = input.index(before: position)
            let str = try readString()
            return .string(str)
        case let c where c.isNumber:
            position = input.index(before: position)
            let numberLiteral = try readNumber()
            switch numberLiteral {
            case let .integer(num):
                return .integer(num)
            case let .float(num):
                return .float(num)
            }
        case let c where c.isLetter:
            position = input.index(before: position)
            let id = readIdentifier()
            if id == "let" {
                return .letKeyword
            } else if id == "mut" {
                return .mutKeyword
            } else if id == "true" {
                return .bool(true)
            } else if id == "false" {
                return .bool(false)
            } else if id == "if" {
                return .ifKeyword
            } else if id == "then" {
                return .thenKeyword
            } else if id == "else" {
                return .elseKeyword
            } else if id == "while" {
                return .whileKeyword
            }
            return .identifier(id)
        default:
            throw LexerError.unexpectedCharacter(line: _line, String(char))
        }
    }
}
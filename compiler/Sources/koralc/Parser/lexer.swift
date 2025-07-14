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
    case notEqual       // Not equals operator '<>'
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
    case leftBracket    // Left bracket '['
    case rightBracket   // Right bracket ']'
    case bool(Bool)     // Boolean literal, e.g.: true, false
    case ifKeyword      // 'if' keyword
    case thenKeyword    // 'then' keyword
    case elseKeyword    // 'else' keyword
    case whileKeyword   // 'while' keyword
    case andKeyword     // 'and' keyword
    case orKeyword      // 'or' keyword
    case notKeyword     // 'not' keyword
    case colon          // Colon ':'
    case typeKeyword    // 'type' keyword
    case dot            // Dot operator '.'
    case valKeyword     // 'val' keyword

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
             (.leftBracket, .leftBracket),
             (.rightBracket, .rightBracket),
             (.eof, .eof),
             (.bool, .bool),
             (.ifKeyword, .ifKeyword),
             (.thenKeyword, .thenKeyword),
             (.elseKeyword, .elseKeyword),
             (.whileKeyword, .whileKeyword),
             (.andKeyword, .andKeyword),
             (.orKeyword, .orKeyword),
             (.notKeyword, .notKeyword),
             (.colon, .colon),
             (.typeKeyword, .typeKeyword),
             (.dot, .dot),
             (.valKeyword, .valKeyword):
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
        case .leftBracket:
            return "["
        case .rightBracket:
            return "]"
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
        case .andKeyword:
            return "and"
        case .orKeyword:
            return "or"
        case .notKeyword:
            return "not"
        case .colon:
            return ":"
        case .typeKeyword:
            return "type"
        case .dot:
            return "."
        case .valKeyword:
            return "val"
        }
    }
}

// Enumeration for number literal return values
private enum NumberLiteral {
    case integer(Int)
    case float(Double)
}

// Lexical analyzer class
public class Lexer {
    private let input: String
    private var position: String.Index
    private var _line: Int = 1
    
    // Current line number property
    public var currentLine: Int {
        self._line
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

        return if hasDot {
            .float(Double(numStr)!)
        } else {
            .integer(Int(numStr)!)
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
        case ">":
            if let nextChar = getNextChar(), nextChar == "=" {
                return .greaterEqual
            } else {
                position = input.index(before: position)
                return .greater
            }
        case "<":
            if let nextChar = getNextChar(), nextChar == ">" {
                return .notEqual
            } else if let nextChar = getNextChar(), nextChar == "=" {
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
        case "[":
            return .leftBracket
        case "]":
            return .rightBracket
        case ":":
            return .colon
        case ".":
            return .dot
        case "\"":
            position = input.index(before: position)
            let str = try readString()
            return .string(str)
        case let c where c.isNumber:
            position = input.index(before: position)
            let numberLiteral = try readNumber()
            return switch numberLiteral {
            case let .integer(num):
                .integer(num)
            case let .float(num):
                .float(num)
            }
        case let c where c.isLetter:
            position = input.index(before: position)
            let id = readIdentifier()
            return switch id {
                case "let": .letKeyword
                case "mut": .mutKeyword
                case "true": .bool(true)
                case "false": .bool(false)
                case "if": .ifKeyword
                case "then": .thenKeyword
                case "else": .elseKeyword
                case "while": .whileKeyword
                case "and": .andKeyword
                case "or": .orKeyword
                case "not": .notKeyword
                case "type": .typeKeyword
                case "val": .valKeyword
                default:  .identifier(id)
            }
        default:
            throw LexerError.unexpectedCharacter(line: _line, String(char))
        }
    }
}
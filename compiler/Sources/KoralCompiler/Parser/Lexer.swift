// Define token types for lexical analysis
public enum Token: CustomStringConvertible {
  case bof  // Beginning of file marker
  case eof  // End of file marker
  case integer(Int)  // Integer literal, e.g.: 42
  case float(Double)  // Float64 literal, e.g.: 3.14
  case string(String)  // String literal, e.g.: "hello"
  case plus  // Plus operator '+'
  case minus  // Minus operator '-'
  case multiply  // Multiply operator '*'
  case divide  // Divide operator '/'
  case modulo  // Modulo operator '%'
  case equal  // Equal sign '='
  case equalEqual  // Equals operator '=='
  case notEqual  // Not equals operator '<>'
  case greater  // Greater than operator '>'
  case less  // Less than operator '<'
  case greaterEqual  // Greater than or equal operator '>='
  case lessEqual  // Less than or equal operator '<='
  case identifier(String)  // Identifier, e.g.: variableName, Int, Float64, String
  case letKeyword  // 'let' keyword
  case mutKeyword  // 'mut' keyword
  case semicolon  // Semicolon ';'
  case leftParen  // Left parenthesis '('
  case rightParen  // Right parenthesis ')'
  case comma  // Comma ','
  case leftBrace  // Left brace '{'
  case rightBrace  // Right brace '}'
  case leftBracket  // Left bracket '['
  case rightBracket  // Right bracket ']'
  case bool(Bool)  // Boolean literal, e.g.: true, false
  case ifKeyword  // 'if' keyword
  case thenKeyword  // 'then' keyword
  case elseKeyword  // 'else' keyword
  case whileKeyword  // 'while' keyword
  case andKeyword  // 'and' keyword
  case orKeyword  // 'or' keyword
  case notKeyword  // 'not' keyword
  case colon  // Colon ':'
  case typeKeyword  // 'type' keyword
  case dot  // Dot operator '.'
  case isKeyword  // 'is' keyword
  case refKeyword  // 'ref' keyword
  case givenKeyword  // 'given' keyword
  case traitKeyword  // 'trait' keyword
  case whenKeyword  // 'when' keyword
  case intrinsicKeyword  // 'intrinsic' keyword
  case bitandKeyword  // 'bitand' keyword
  case bitorKeyword  // 'bitor' keyword
  case bitxorKeyword  // 'bitxor' keyword
  case bitnotKeyword  // 'bitnot' keyword
  case derefKeyword   // 'deref' keyword
  case privateKeyword // 'private' keyword
  case protectedKeyword // 'protected' keyword
  case publicKeyword  // 'public' keyword
  case bitshlKeyword  // 'bitshl' keyword
  case bitshrKeyword  // 'bitshr' keyword
  case arrow  // '->'
  case power  // '^'
  case plusEqual  // '+='
  case minusEqual  // '-='
  case multiplyEqual  // '*='
  case divideEqual  // '/='
  case moduloEqual  // '%='
  case powerEqual  // '^='
  case range  // '..'
  case rangeLess  // '..<'
  case lessRange  // '<..'
  case lessRangeLess  // '<..<'
  case unboundedRange  // '...'
  case lessUnboundedRange  // '<...'
  case unboundedRangeLess  // '...<'
  case fullRange  // '....'
  case selfKeyword // 'self' keyword
  case returnKeyword // 'return' keyword
  case breakKeyword // 'break' keyword
  case continueKeyword // 'continue' keyword

  /// Whether this token is a continuation token (triggers line continuation when at start of line)
  /// Continuation tokens include: infix operators, dot, and arrow
  public var isContinuationToken: Bool {
    switch self {
    // Arithmetic infix operators
    case .plus, .minus, .multiply, .divide, .modulo, .power:
      return true
    // Logical infix operators
    case .andKeyword, .orKeyword:
      return true
    // Bitwise infix operators
    case .bitandKeyword, .bitorKeyword, .bitxorKeyword, .bitshlKeyword, .bitshrKeyword:
      return true
    // Comparison operators
    case .equalEqual, .notEqual, .greater, .less, .greaterEqual, .lessEqual:
      return true
    // Dot for member access and chaining
    case .dot:
      return true
    // Arrow for lambda expressions
    case .arrow:
      return true
    // Range operators
    case .range, .rangeLess, .lessRange, .lessRangeLess:
      return true
    default:
      return false
    }
  }

  // Add static operator function to compare if the same item
  public static func === (lhs: Token, rhs: Token) -> Bool {
    switch (lhs, rhs) {
    case (.integer(_), .integer(_)):
      return true
    case (.float(_), .float(_)):
      return true
    case (.string(_), .string(_)):
      return true
    case (.bool(_), .bool(_)):
      return true
    case (.identifier(_), .identifier(_)):
      return true
    case (.plus, .plus), (.minus, .minus), (.multiply, .multiply), (.divide, .divide), (.modulo, .modulo):
      return true
    case (.equal, .equal), (.equalEqual, .equalEqual), (.notEqual, .notEqual):
      return true
    case (.greater, .greater), (.less, .less), (.greaterEqual, .greaterEqual), (.lessEqual, .lessEqual):
      return true
    case (.letKeyword, .letKeyword), (.mutKeyword, .mutKeyword):
      return true
    case (.semicolon, .semicolon), (.comma, .comma), (.colon, .colon), (.dot, .dot), (.arrow, .arrow):
      return true
    case (.leftParen, .leftParen), (.rightParen, .rightParen):
      return true
    case (.leftBrace, .leftBrace), (.rightBrace, .rightBrace):
      return true
    case (.leftBracket, .leftBracket), (.rightBracket, .rightBracket):
      return true
    case (.ifKeyword, .ifKeyword), (.thenKeyword, .thenKeyword), (.elseKeyword, .elseKeyword), (.whileKeyword, .whileKeyword):
      return true
    case (.andKeyword, .andKeyword), (.orKeyword, .orKeyword), (.notKeyword, .notKeyword):
      return true
    case (.typeKeyword, .typeKeyword), (.isKeyword, .isKeyword), (.refKeyword, .refKeyword):
      return true
    case (.givenKeyword, .givenKeyword), (.traitKeyword, .traitKeyword), (.whenKeyword, .whenKeyword), (.intrinsicKeyword, .intrinsicKeyword):
      return true
    case (.bitandKeyword, .bitandKeyword), (.bitorKeyword, .bitorKeyword), (.bitxorKeyword, .bitxorKeyword), (.bitnotKeyword, .bitnotKeyword):
      return true
    case (.bitshlKeyword, .bitshlKeyword), (.bitshrKeyword, .bitshrKeyword):
      return true
    case (.derefKeyword, .derefKeyword):
      return true
    case (.privateKeyword, .privateKeyword), (.protectedKeyword, .protectedKeyword), (.publicKeyword, .publicKeyword):
      return true
    case (.power, .power):
      return true
    case (.plusEqual, .plusEqual), (.minusEqual, .minusEqual), (.multiplyEqual, .multiplyEqual), (.divideEqual, .divideEqual), (.moduloEqual, .moduloEqual), (.powerEqual, .powerEqual):
      return true
    case (.range, .range), (.rangeLess, .rangeLess), (.lessRange, .lessRange), (.lessRangeLess, .lessRangeLess), (.unboundedRange, .unboundedRange), (.lessUnboundedRange, .lessUnboundedRange), (.unboundedRangeLess, .unboundedRangeLess), (.fullRange, .fullRange):
      return true
    case (.selfKeyword, .selfKeyword):
      return true
    case (.returnKeyword, .returnKeyword), (.breakKeyword, .breakKeyword), (.continueKeyword, .continueKeyword):
      return true
    case (.bof, .bof), (.eof, .eof):
      return true
    default:
      return false
    }
  }

  public static func !== (lhs: Token, rhs: Token) -> Bool {
    return !(lhs === rhs)
  }

  public var description: String {
    switch self {
    case .integer(let value):
      return "Integer(\(value))"
    case .float(let value):
      return "Float64(\(value))"
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
      return "<>"
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
    case .selfKeyword: return "self"
    case .returnKeyword: return "return"
    case .breakKeyword: return "break"
    case .continueKeyword: return "continue"
      case .isKeyword:
      return "is"
    case .refKeyword:
      return "ref"
    case .givenKeyword:
      return "given"
    case .traitKeyword:
      return "trait"
    case .whenKeyword:
      return "when"
    case .intrinsicKeyword:
      return "intrinsic"
    case .bitandKeyword:
      return "bitand"
    case .bitorKeyword:
      return "bitor"
    case .bitxorKeyword:
      return "bitxor"
    case .bitnotKeyword:
      return "bitnot"
    case .derefKeyword:
      return "deref"
    case .privateKeyword:
      return "private"
    case .protectedKeyword:
      return "protected"
    case .publicKeyword:
      return "public"
    case .bitshlKeyword:
      return "bitshl"
    case .bitshrKeyword:
      return "bitshr"
    case .arrow:
      return "->"
    case .power:
      return "^"
    case .plusEqual:
      return "+="
    case .minusEqual:
      return "-="
    case .multiplyEqual:
      return "*="
    case .divideEqual:
      return "/="
    case .moduloEqual:
      return "%="
    case .powerEqual:
      return "^="
    case .range:
      return ".."
    case .rangeLess:
      return "..<"
    case .lessRange:
      return "<.."
    case .lessRangeLess:
      return "<..<"
    case .unboundedRange:
      return "..."
    case .lessUnboundedRange:
      return "<..."
    case .unboundedRangeLess:
      return "...<"
    case .fullRange:
      return "...."
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
  
  // Newline tracking for automatic statement termination
  private var _hasNewlineBeforeCurrentToken: Bool = false
  private var _hasBlankLineOrCommentBeforeCurrentToken: Bool = false

  public struct State {
    fileprivate let position: String.Index
    fileprivate let line: Int
    fileprivate let hasNewlineBeforeCurrentToken: Bool
    fileprivate let hasBlankLineOrCommentBeforeCurrentToken: Bool
  }

  // Current line number property
  public var currentLine: Int {
    self._line
  }
  
  // Whether there was a newline before the current token
  public var newlineBeforeCurrent: Bool {
    self._hasNewlineBeforeCurrentToken
  }
  
  // Whether there was a blank line or comment before the current token
  public var blankLineOrCommentBeforeCurrent: Bool {
    self._hasBlankLineOrCommentBeforeCurrentToken
  }

  public init(input: String) {
    self.input = input
    self.position = input.startIndex
  }

  public func saveState() -> State {
    State(
      position: position,
      line: _line,
      hasNewlineBeforeCurrentToken: _hasNewlineBeforeCurrentToken,
      hasBlankLineOrCommentBeforeCurrentToken: _hasBlankLineOrCommentBeforeCurrentToken
    )
  }

  public func restoreState(_ state: State) {
    position = state.position
    _line = state.line
    _hasNewlineBeforeCurrentToken = state.hasNewlineBeforeCurrentToken
    _hasBlankLineOrCommentBeforeCurrentToken = state.hasBlankLineOrCommentBeforeCurrentToken
  }

  // Step back one character, fixing line counter if we rewound over a newline
  private func unreadChar(_ char: Character) {
    position = input.index(before: position)
    if char.isNewline {
      _line -= 1
    }
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

  // Skip whitespace characters and track newlines
  // Returns (sawNewline, sawBlankLineOrComment)
  private func skipWhitespaceOnly() -> (sawNewline: Bool, sawBlankLineOrComment: Bool) {
    var sawNewline = false
    var sawBlankLineOrComment = false
    var consecutiveNewlines = 0
    
    while let char = getNextChar() {
      if char.isNewline {
        sawNewline = true
        consecutiveNewlines += 1
        if consecutiveNewlines > 1 {
          sawBlankLineOrComment = true  // Empty line detected
        }
      } else if char.isWhitespace {
        // Regular whitespace, don't reset newline count
        continue
      } else {
        unreadChar(char)
        break
      }
    }
    return (sawNewline, sawBlankLineOrComment)
  }
  
  // Skip whitespace and comments, tracking newlines and blank lines/comments
  private func skipWhitespaceAndComments() throws -> (sawNewline: Bool, sawBlankLineOrComment: Bool) {
    var sawNewline = false
    var sawBlankLineOrComment = false
    var consecutiveNewlines = 0
    
    while true {
      // First skip any whitespace
      while let char = getNextChar() {
        if char.isNewline {
          sawNewline = true
          consecutiveNewlines += 1
          if consecutiveNewlines > 1 {
            sawBlankLineOrComment = true
          }
        } else if char.isWhitespace {
          continue
        } else {
          unreadChar(char)
          break
        }
      }
      
      // Check for comments
      guard let char = getNextChar() else { break }
      
      if char == "/" {
        if let nextChar = getNextChar() {
          if nextChar == "/" {
            // Line comment
            skipLineComment()
            sawBlankLineOrComment = true
            consecutiveNewlines = 0
            continue
          } else if nextChar == "*" {
            // Block comment
            try skipBlockComment()
            sawBlankLineOrComment = true
            consecutiveNewlines = 0
            continue
          }
          unreadChar(nextChar)
        }
        unreadChar(char)
        break
      } else {
        unreadChar(char)
        break
      }
    }
    
    return (sawNewline, sawBlankLineOrComment)
  }

  // Skip whitespace characters (legacy method for compatibility)
  private func skipWhitespace() {
    while let char = getNextChar() {
      if !char.isWhitespace {
        unreadChar(char)
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

  // Skip block comments /* ... */
  private func skipBlockComment() throws {
    while let char = getNextChar() {
        if char == "*" {
            if let nextChar = getNextChar() {
                if nextChar == "/" {
                    return
                }
                unreadChar(nextChar)
            }
        }
    }
    // If we reach here, it means we hit EOF before closing */
    throw LexerError.unexpectedEndOfFile
  }

  // Read a number, handling both integers and floats
  private func readNumber() throws -> NumberLiteral {
    var numStr = ""
    var hasDot = false
    while let char = getNextChar() {
      if char.isNumber {
        numStr.append(char)
      } else if char == "_" {
        // Digit separator (e.g. 1_000_000)
        continue
      } else if char == "." {
        if hasDot {
          throw LexerError.invalidFloat(line: _line, "consecutive dots are not allowed")
        }
        hasDot = true
        numStr.append(char)
      } else {
        unreadChar(char)
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
    guard let startChar = getNextChar(), (startChar == "\"" || startChar == "'") else {
      throw LexerError.invalidString(line: _line, "expected string start with \" or '")
    }
    let quote = startChar

    while let char = getNextChar() {
      if char == quote {
        return str
      }

      if char == "\\" {
        guard let escaped = getNextChar() else {
          throw LexerError.invalidString(line: _line, "unterminated escape sequence")
        }
        switch escaped {
        case "n": str.append("\n")
        case "t": str.append("\t")
        case "r": str.append("\r")
        case "v": str.append("\u{000B}")
        case "f": str.append("\u{000C}")
        case "0": str.append("\0")
        case "\\": str.append("\\")
        case "\"": str.append("\"")
        case "'": str.append("'")
        default:
          throw LexerError.invalidString(line: _line, "unknown escape: \\\(escaped)")
        }
        continue
      }

      str.append(char)
    }

    throw LexerError.invalidString(line: _line, "unterminated string literal")
  }

  // Read an identifier
  private func readIdentifier() -> String {
    var idStr = ""
    while let char = getNextChar() {
      if char.isLetter || char.isNumber || char == "_" {
        idStr.append(char)
      } else {
        unreadChar(char)
        break
      }
    }
    return idStr
  }

  // Get next token
  public func getNextToken() throws -> Token {
    // Track newlines and blank lines/comments before this token
    let (sawNewline, sawBlankLineOrComment) = try skipWhitespaceAndComments()
    _hasNewlineBeforeCurrentToken = sawNewline
    _hasBlankLineOrCommentBeforeCurrentToken = sawBlankLineOrComment
    
    guard let char = getNextChar() else {
      return .eof
    }
    switch char {
    case "+":
      if let nextChar = getNextChar() {
        if nextChar == "=" { return .plusEqual }
        unreadChar(nextChar)
      }
      return .plus
    case "-":
      if let nextChar = getNextChar() {
        if nextChar == "=" { return .minusEqual }
        if nextChar == ">" { return .arrow }
        unreadChar(nextChar)
      }
      return .minus
    case "*":
      if let nextChar = getNextChar() {
        if nextChar == "=" { return .multiplyEqual }
        unreadChar(nextChar)
      }
      return .multiply
    case "/":
      if let nextChar = getNextChar() {
        if nextChar == "/" {
          skipLineComment()
          // Re-track newlines after comment
          let (sawNewline, _) = try skipWhitespaceAndComments()
          _hasNewlineBeforeCurrentToken = _hasNewlineBeforeCurrentToken || sawNewline
          _hasBlankLineOrCommentBeforeCurrentToken = true
          return try getNextToken()
        } else if nextChar == "*" {
          try skipBlockComment()
          // Re-track newlines after comment
          let (sawNewline, _) = try skipWhitespaceAndComments()
          _hasNewlineBeforeCurrentToken = _hasNewlineBeforeCurrentToken || sawNewline
          _hasBlankLineOrCommentBeforeCurrentToken = true
          return try getNextToken()
        } else if nextChar == "=" {
          return .divideEqual
        } else {
          unreadChar(nextChar)
        }
      }
      return .divide
    case "%":
      if let nextChar = getNextChar() {
        if nextChar == "=" { return .moduloEqual }
        unreadChar(nextChar)
      }
      return .modulo
    case "^":
      if let nextChar = getNextChar() {
        if nextChar == "=" { return .powerEqual }
        unreadChar(nextChar)
      }
      return .power
    case "=":
      if let nextChar = getNextChar() {
        if nextChar == "=" {
          return .equalEqual
        }
        unreadChar(nextChar)
      }
      return .equal
    case "!":
      // Koral does not use '!' (use `not expr`) and does not use '!=' (use '<>').
      throw LexerError.unexpectedCharacter(line: currentLine, "!")
    case ">":
      if let nextChar = getNextChar() {
        if nextChar == "=" {
          return .greaterEqual
        }
        unreadChar(nextChar)
      }
      return .greater
    case "<":
      if let nextChar = getNextChar() {
        if nextChar == ">" {
          return .notEqual
        }
        if nextChar == "=" {
          return .lessEqual
        }
        if nextChar == "." {
          if let nextNextChar = getNextChar() {
            if nextNextChar == "." {
              if let nextNextNextChar = getNextChar() {
                if nextNextNextChar == "." {
                  return .lessUnboundedRange
                } else if nextNextNextChar == "<" {
                  return .lessRangeLess
                }
                unreadChar(nextNextNextChar)
              }
              return .lessRange
            }
            unreadChar(nextNextChar)
          }
          unreadChar(nextChar)
        }
        unreadChar(nextChar)
      }
      return .less
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
      if let nextChar = getNextChar() {
        if nextChar == "." {
          if let nextNextChar = getNextChar() {
            if nextNextChar == "." {
              if let nextNextNextChar = getNextChar() {
                if nextNextNextChar == "." {
                  return .fullRange
                } else if nextNextNextChar == "<" {
                  return .unboundedRangeLess
                }
                unreadChar(nextNextNextChar)
              }
              return .unboundedRange
            } else if nextNextChar == "<" {
              return .rangeLess
            }
            unreadChar(nextNextChar)
          }
          return .range
        }
        unreadChar(nextChar)
      }
      return .dot
    case "\"", "'":
      unreadChar(char)
      let str = try readString()
      return .string(str)
    case let c where c.isNumber:
      unreadChar(c)
      let numberLiteral = try readNumber()
      return switch numberLiteral {
      case .integer(let num):
        .integer(num)
      case .float(let num):
        .float(num)
      }
    case let c where c.isLetter || c == "_":
      unreadChar(c)
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
      case "is": .isKeyword
      case "ref": .refKeyword
      case "given": .givenKeyword
      case "trait": .traitKeyword
      case "when": .whenKeyword
      case "intrinsic": .intrinsicKeyword
      case "bitand": .bitandKeyword
      case "bitor": .bitorKeyword
      case "bitxor": .bitxorKeyword
      case "bitnot": .bitnotKeyword
      case "deref": .derefKeyword
      case "private": .privateKeyword
      case "protected": .protectedKeyword
      case "public": .publicKeyword
      case "bitshl": .bitshlKeyword
      case "bitshr": .bitshrKeyword
      case "self": .selfKeyword
      case "return": .returnKeyword
      case "break": .breakKeyword
      case "continue": .continueKeyword
      default: .identifier(id)
      }
    default:
      throw LexerError.unexpectedCharacter(line: _line, String(char))
    }
  }
}

// Semantic error types
public struct SemanticError: Error, CustomStringConvertible, Sendable {
    public enum Kind: Sendable {
        case typeMismatch(expected: String, got: String)
        case undefinedVariable(String)
        case invalidOperation(op: String, type1: String, type2: String)
        case invalidNode
        case duplicateDefinition(String)
        case invalidType(String)
        case assignToImmutable(String)
        case functionNotFound(String)
        case invalidArgumentCount(function: String, expected: Int, got: Int)
        case duplicateTypeDefinition(String)
        case undefinedType(String)
        case undefinedMember(String, String)
        case invalidFieldTypeInValueType(type: String, field: String, fieldType: String)
        case invalidMutableFieldInValueType(type: String, field: String)
        case immutableFieldAssignment(type: String, field: String)
        case variableMoved(String)
        case generic(String)
    }
    
    public let kind: Kind
    public let fileName: String
    public let line: Int
    
    public init(_ kind: Kind, fileName: String, line: Int) {
        self.kind = kind
        self.fileName = fileName
        self.line = line
    }

    /// Convenience initializer that uses the current semantic context.
    /// This keeps call sites lightweight while still guaranteeing non-optional file/line.
    public init(_ kind: Kind, line: Int? = nil) {
        self.init(
            kind,
            fileName: SemanticErrorContext.currentFileName,
            line: line ?? SemanticErrorContext.currentLine
        )
    }
    
    // Compatibility initializers
    public static func typeMismatch(expected: String, got: String) -> SemanticError {
        return SemanticError(.typeMismatch(expected: expected, got: got))
    }
    public static func undefinedVariable(_ name: String) -> SemanticError {
        return SemanticError(.undefinedVariable(name))
    }
    public static func invalidOperation(op: String, type1: String, type2: String) -> SemanticError {
        return SemanticError(.invalidOperation(op: op, type1: type1, type2: type2))
    }
    public static func duplicateDefinition(_ name: String, line: Int? = nil) -> SemanticError {
        return SemanticError(.duplicateDefinition(name), line: line)
    }
    public static func undefinedType(_ name: String) -> SemanticError {
        return SemanticError(.undefinedType(name))
    }
    public static func functionNotFound(_ name: String) -> SemanticError {
        return SemanticError(.functionNotFound(name))
    }
    public static func invalidArgumentCount(function: String, expected: Int, got: Int) -> SemanticError {
        return SemanticError(.invalidArgumentCount(function: function, expected: expected, got: got))
    }
    public static func duplicateTypeDefinition(_ name: String) -> SemanticError {
        return SemanticError(.duplicateTypeDefinition(name))
    }
    public static func undefinedMember(_ member: String, _ type: String) -> SemanticError {
        return SemanticError(.undefinedMember(member, type))
    }
    public static func invalidType(_ type: String) -> SemanticError {
        return SemanticError(.invalidType(type))
    }
    public static func assignToImmutable(_ name: String) -> SemanticError {
        return SemanticError(.assignToImmutable(name))
    }
    public static func immutableFieldAssignment(type: String, field: String) -> SemanticError {
        return SemanticError(.immutableFieldAssignment(type: type, field: field))
    }
    public static func variableMoved(_ name: String) -> SemanticError {
        return SemanticError(.variableMoved(name))
    }
    // Accessor for the old enum-like matching if necessary, though direct matching on `kind` is preferred
    
    public var description: String {
        let location = "Line \(line): "
        switch kind {
        case .typeMismatch(let expected, let got):
            return "\(location)Type mismatch: expected \(expected), got \(got)"
        case .undefinedVariable(let name):
            return "\(location)Undefined variable: \(name)"
        case .invalidOperation(let op, let type1, let type2):
            return "\(location)Invalid operation \(op) between types \(type1) and \(type2)"
        case .invalidNode:
            return "\(location)Invalid AST node"
        case .duplicateDefinition(let name):
            return "\(location)Duplicate definition: \(name)"
        case .invalidType(let type):
            return "\(location)Invalid type: \(type)"
        case .assignToImmutable(let name):
            return "\(location)Cannot assign to immutable variable: \(name)"
        case .functionNotFound(let name):
            return "\(location)Function not found: \(name)"
        case .invalidArgumentCount(let function, let expected, let got):
            return "\(location)Invalid argument count for function \(function): expected \(expected), got \(got)"
        case .duplicateTypeDefinition(let name):
            return "\(location)Duplicate type definition: \(name)"
        case .undefinedType(let name):
            return "\(location)Undefined type: \(name)"
        case .undefinedMember(let member, let type):
            return "\(location)Member '\(member)' not found in type '\(type)'"
        case .invalidFieldTypeInValueType(let type, let field, let fieldType):
            return "\(location)Value type '\(type)' cannot have field '\(field)' of reference type '\(fieldType)'"
        case .invalidMutableFieldInValueType(let type, let field):
            return "\(location)Value type '\(type)' cannot have mutable field '\(field)'"
        case .immutableFieldAssignment(let type, let field):
            return "\(location)Cannot assign to immutable field '\(field)' of type '\(type)'"
        case .variableMoved(let name):
            return "\(location)Use of moved variable: '\(name)'"
        case .generic(let msg):
            return "\(location)\(msg)"
        }
    }
}

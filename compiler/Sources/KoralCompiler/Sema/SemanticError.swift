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
        case ffiIncompatibleType(type: String, reason: String)
        case opaqueTypeConstruction(type: String)
        case opaqueTypeCannotBeInstantiated(typeName: String)
        case pointerMemberAccessOnNonStruct(field: String, type: String)
        case unknownForeignField(type: String, field: String)
        case foreignGlobalNotFound(name: String)
        case foreignGlobalImmutable(name: String)
        
        // Exhaustiveness checking errors
        case nonExhaustiveMatch(type: String, missing: [String])
        case unreachablePattern(pattern: String, reason: String)
        case missingCatchallPattern(type: String)
    }
    
    public let kind: Kind
    public let fileName: String
    public let span: SourceSpan
    
    public init(_ kind: Kind, fileName: String, span: SourceSpan) {
        self.kind = kind
        self.fileName = fileName
        self.span = span
    }
    
    /// Convenience initializer that uses line number
    public init(_ kind: Kind, fileName: String, line: Int) {
        self.init(kind, fileName: fileName, span: SourceSpan(location: SourceLocation(line: line, column: 1)))
    }

    /// Convenience initializer that uses the current semantic context.
    /// This keeps call sites lightweight while still guaranteeing non-optional file/line.
    public init(_ kind: Kind, line: Int? = nil) {
        self.init(
            kind,
            fileName: SemanticErrorContext.currentFileName,
            span: SourceSpan(location: SourceLocation(line: line ?? SemanticErrorContext.currentLine, column: 1))
        )
    }
    
    /// Convenience initializer with span from context
    public init(_ kind: Kind, span: SourceSpan) {
        self.init(kind, fileName: SemanticErrorContext.currentFileName, span: span)
    }
    
    // Column number
    public var column: Int { span.start.column }
    
    // Static factory methods for common error types
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
    
    /// The error message without location information
    public var messageWithoutLocation: String {
        switch kind {
        case .typeMismatch(let expected, let got):
            return "Type mismatch: expected \(expected), got \(got)"
        case .undefinedVariable(let name):
            return "Undefined variable: \(name)"
        case .invalidOperation(let op, let type1, let type2):
            return "Invalid operation \(op) between types \(type1) and \(type2)"
        case .invalidNode:
            return "Invalid AST node"
        case .duplicateDefinition(let name):
            return "Duplicate definition: \(name)"
        case .invalidType(let type):
            return "Invalid type: \(type)"
        case .assignToImmutable(let name):
            return "Cannot assign to immutable variable: \(name)"
        case .functionNotFound(let name):
            return "Function not found: \(name)"
        case .invalidArgumentCount(let function, let expected, let got):
            return "Invalid argument count for function \(function): expected \(expected), got \(got)"
        case .duplicateTypeDefinition(let name):
            return "Duplicate type definition: \(name)"
        case .undefinedType(let name):
            return "Undefined type: \(name)"
        case .undefinedMember(let member, let type):
            return "Member '\(member)' not found in type '\(type)'"
        case .invalidFieldTypeInValueType(let type, let field, let fieldType):
            return "Value type '\(type)' cannot have field '\(field)' of reference type '\(fieldType)'"
        case .invalidMutableFieldInValueType(let type, let field):
            return "Value type '\(type)' cannot have mutable field '\(field)'"
        case .immutableFieldAssignment(let type, let field):
            return "Cannot assign to immutable field '\(field)' of type '\(type)'"
        case .variableMoved(let name):
            return "Use of moved variable: '\(name)'"
        case .generic(let msg):
            return msg
        case .ffiIncompatibleType(let type, let reason):
            return "FFI incompatible type '\(type)': \(reason)"
        case .opaqueTypeConstruction(let type):
            return "Opaque type '\(type)' cannot be constructed directly"
        case .opaqueTypeCannotBeInstantiated(let typeName):
            return "opaque type '\(typeName)' cannot be instantiated directly, use '\(typeName) ptr' instead"
        case .pointerMemberAccessOnNonStruct(let field, let type):
            return "cannot access member '\(field)' on pointer to non-struct type '\(type)'"
        case .unknownForeignField(let type, let field):
            return "foreign struct '\(type)' has no field '\(field)'"
        case .foreignGlobalNotFound(let name):
            return "foreign global variable '\(name)' not declared"
        case .foreignGlobalImmutable(let name):
            return "cannot assign to immutable foreign global '\(name)'"
        case .nonExhaustiveMatch(let type, let missing):
            let casesStr = missing.joined(separator: ", ")
            return "Non-exhaustive match on type '\(type)': missing cases \(casesStr)"
        case .unreachablePattern(let pattern, let reason):
            return "Unreachable pattern '\(pattern)': \(reason)"
        case .missingCatchallPattern(let type):
            return "Match on type '\(type)' requires a wildcard or variable binding pattern"
        }
    }
    
    public var description: String {
        let location = span.isKnown ? "\(span.start.line):\(span.start.column): " : ""
        return "\(location)\(messageWithoutLocation)"
    }
}

// Semantic error types
public indirect enum SemanticError: Error {
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
}

extension SemanticError: CustomStringConvertible {
  public var description: String {
    switch self {
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
    }
  }
}

// Typed AST node definitions for semantic analysis phase

public enum ValueCategory {
  case lvalue
  case rvalue
}
public enum SymbolKind {
  case variable(VariableKind)
  case function
  case type
}
public enum VariableKind {
  case Value
  case MutableValue
  case Reference
  case MutableReference

  public var isMutable: Bool {
    switch self {
    case .MutableValue, .MutableReference:
      return true
    case .Value, .Reference:
      return false
    }
  }
}
public struct Symbol {
  public let name: String
  public let type: Type
  public let kind: SymbolKind

  public init(name: String, type: Type, kind: SymbolKind) {
    self.name = name
    self.type = type
    self.kind = kind
  }

  public func isMutable() -> Bool {
    switch kind {
    case .variable(let varKind):
      switch varKind {
      case .MutableValue, .MutableReference:
        return true
      case .Value, .Reference:
        return false
      }
    case .function, .type:
      return false
    }
  }
}
public indirect enum TypedProgram {
  case program(globalNodes: [TypedGlobalNode])
}
public indirect enum TypedGlobalNode {
  case globalVariable(identifier: Symbol, value: TypedExpressionNode, kind: VariableKind)
  case globalFunction(
    identifier: Symbol,
    parameters: [Symbol],
    body: TypedExpressionNode
  )
  case globalTypeDeclaration(
    identifier: Symbol,
    parameters: [Symbol]
  )
  case genericTypeTemplate(name: String)
  case givenDeclaration(type: Type, methods: [TypedMethodDeclaration])
}
public struct TypedMethodDeclaration {
  public let identifier: Symbol
  public let parameters: [Symbol]
  public let body: TypedExpressionNode
  public let returnType: Type
}
public indirect enum TypedStatementNode {
  case variableDeclaration(identifier: Symbol, value: TypedExpressionNode, mutable: Bool)
  case assignment(target: TypedAssignmentTarget, value: TypedExpressionNode)
  case compoundAssignment(
    target: TypedAssignmentTarget, operator: CompoundAssignmentOperator, value: TypedExpressionNode)
  case expression(TypedExpressionNode)
}
public enum TypedAssignmentTarget {
  case variable(identifier: Symbol)
  case memberAccess(base: Symbol, memberPath: [Symbol])
}
public indirect enum TypedExpressionNode {
  case integerLiteral(value: Int, type: Type)
  case floatLiteral(value: Double, type: Type)
  case stringLiteral(value: String, type: Type)
  case booleanLiteral(value: Bool, type: Type)
  case arithmeticExpression(
    left: TypedExpressionNode, op: ArithmeticOperator, right: TypedExpressionNode, type: Type)
  case comparisonExpression(
    left: TypedExpressionNode, op: ComparisonOperator, right: TypedExpressionNode, type: Type)
  case letExpression(
    identifier: Symbol, value: TypedExpressionNode, body: TypedExpressionNode, type: Type)
  case andExpression(left: TypedExpressionNode, right: TypedExpressionNode, type: Type)
  case orExpression(left: TypedExpressionNode, right: TypedExpressionNode, type: Type)
  case notExpression(expression: TypedExpressionNode, type: Type)
  case bitwiseExpression(
    left: TypedExpressionNode, op: BitwiseOperator, right: TypedExpressionNode, type: Type)
  case bitwiseNotExpression(expression: TypedExpressionNode, type: Type)
  case referenceExpression(expression: TypedExpressionNode, type: Type)
  case variable(identifier: Symbol)
  case blockExpression(
    statements: [TypedStatementNode], finalExpression: TypedExpressionNode?, type: Type)
  case ifExpression(
    condition: TypedExpressionNode, thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode, type: Type)
  case call(callee: TypedExpressionNode, arguments: [TypedExpressionNode], type: Type)
  case methodReference(base: TypedExpressionNode, method: Symbol, type: Type)
  case whileExpression(condition: TypedExpressionNode, body: TypedExpressionNode, type: Type)
  case typeConstruction(identifier: Symbol, arguments: [TypedExpressionNode], type: Type)
  case memberPath(source: TypedExpressionNode, path: [Symbol])
}
extension TypedExpressionNode {
  var type: Type {
    switch self {
    case .integerLiteral(_, let type),
      .floatLiteral(_, let type),
      .stringLiteral(_, let type),
      .booleanLiteral(_, let type),
      .arithmeticExpression(_, _, _, let type),
      .comparisonExpression(_, _, _, let type),
      .andExpression(_, _, let type),
      .orExpression(_, _, let type),
      .notExpression(_, let type),
      .bitwiseExpression(_, _, _, let type),
      .bitwiseNotExpression(_, let type),
      .referenceExpression(_, let type),
      .blockExpression(_, _, let type),
      .ifExpression(_, _, _, let type),
      .call(_, _, let type),
      .methodReference(_, _, let type),
      .whileExpression(_, _, let type),
      .typeConstruction(_, _, let type),
      .letExpression(_, _, _, let type):
      return type
    case .variable(let identifier):
      return identifier.type
    case .memberPath(_, let path):
      return path.last?.type ?? .void
    }
  }

  var valueCategory: ValueCategory {
    switch self {
    case .variable:
      return .lvalue
    case .memberPath(let source, _):
      // member access is lvalue if the source is lvalue
      return source.valueCategory
    case .referenceExpression:
      // &expr 是一个临时值（指针）
      return .rvalue
    default:
      return .rvalue
    }
  }
}

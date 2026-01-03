// Define AST node types using enums
public indirect enum ASTNode {
  case program(globalNodes: [GlobalNode])
}

public indirect enum TypeNode {
  case identifier(String)
  case reference(TypeNode)
}

public indirect enum GlobalNode {
  case globalVariableDeclaration(name: String, type: TypeNode, value: ExpressionNode, mutable: Bool)
  case globalFunctionDeclaration(
    name: String,
    typeParameters: [String],
    parameters: [(name: String, mutable: Bool, type: TypeNode)],
    returnType: TypeNode,
    body: ExpressionNode
  )
  case globalTypeDeclaration(
    name: String,
    parameters: [(name: String, type: TypeNode, mutable: Bool)]
  )
  // given Type { ...methods... }
  case givenDeclaration(type: TypeNode, methods: [MethodDeclaration])
}

// Method declaration used inside given blocks; same shape as a global function
public struct MethodDeclaration {
  public let name: String
  public let typeParameters: [String]
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let body: ExpressionNode

  public init(
    name: String,
    typeParameters: [String],
    parameters: [(name: String, mutable: Bool, type: TypeNode)],
    returnType: TypeNode,
    body: ExpressionNode
  ) {
    self.name = name
    self.typeParameters = typeParameters
    self.parameters = parameters
    self.returnType = returnType
    self.body = body
  }
}

public indirect enum StatementNode {
  case variableDeclaration(name: String, type: TypeNode?, value: ExpressionNode, mutable: Bool)
  case assignment(target: AssignmentTarget, value: ExpressionNode)
  case compoundAssignment(target: AssignmentTarget, operator: CompoundAssignmentOperator, value: ExpressionNode)
  case expression(ExpressionNode)
}

public enum CompoundAssignmentOperator {
  case plus
  case minus
  case multiply
  case divide
  case modulo
}

public enum AssignmentTarget {
  case variable(name: String)
  case memberAccess(base: String, memberPath: [String])
}

public enum ArithmeticOperator {
  case plus
  case minus
  case multiply
  case divide
  case modulo
}

public enum ComparisonOperator {
  case equal
  case notEqual
  case greater
  case less
  case greaterEqual
  case lessEqual
}

public enum BitwiseOperator {
  case and
  case or
  case xor
  case shiftLeft
  case shiftRight
}

public indirect enum ExpressionNode {
  case integerLiteral(Int)
  case floatLiteral(Double)
  case stringLiteral(String)
  case booleanLiteral(Bool)
  case arithmeticExpression(
    left: ExpressionNode, operator: ArithmeticOperator, right: ExpressionNode)
  case comparisonExpression(
    left: ExpressionNode, operator: ComparisonOperator, right: ExpressionNode)
  case bitwiseExpression(
    left: ExpressionNode, operator: BitwiseOperator, right: ExpressionNode)
  case andExpression(left: ExpressionNode, right: ExpressionNode)
  case orExpression(left: ExpressionNode, right: ExpressionNode)
  case notExpression(ExpressionNode)
  case bitwiseNotExpression(ExpressionNode)
  case refExpression(ExpressionNode)
  case identifier(String)
  case blockExpression(statements: [StatementNode], finalExpression: ExpressionNode?)
  case ifExpression(
    condition: ExpressionNode, thenBranch: ExpressionNode, elseBranch: ExpressionNode)
  case call(callee: ExpressionNode, arguments: [ExpressionNode])
  case whileExpression(condition: ExpressionNode, body: ExpressionNode)
  // 连续成员访问聚合为路径
  case memberPath(base: ExpressionNode, path: [String])
}

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
    case globalTypeDeclaration(
        name: String,
        parameters: [(name: String, type: TypeNode)]
    )
}

public indirect enum StatementNode {
    case variableDeclaration(name: String, type: TypeNode, value: ExpressionNode, mutable: Bool)
    case assignment(name: String, value: ExpressionNode)
    case expression(ExpressionNode)
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

public indirect enum ExpressionNode {
    case integerLiteral(Int)
    case floatLiteral(Double)
    case stringLiteral(String)
    case booleanLiteral(Bool)
    case arithmeticExpression(left: ExpressionNode, operator: ArithmeticOperator, right: ExpressionNode)
    case comparisonExpression(left: ExpressionNode, operator: ComparisonOperator, right: ExpressionNode)
    case andExpression(left: ExpressionNode, right: ExpressionNode)
    case orExpression(left: ExpressionNode, right: ExpressionNode)
    case notExpression(ExpressionNode)
    case identifier(String)
    case blockExpression(statements: [StatementNode], finalExpression: ExpressionNode?)
    case ifExpression(condition: ExpressionNode, thenBranch: ExpressionNode, elseBranch: ExpressionNode)
    case functionCall(name: String, arguments: [ExpressionNode])
    case whileExpression(condition: ExpressionNode, body: ExpressionNode)
}
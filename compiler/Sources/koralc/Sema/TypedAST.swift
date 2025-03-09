// Typed AST node definitions for semantic analysis phase
public indirect enum TypedProgram {
    case program(globalNodes: [TypedGlobalNode])
}

public indirect enum TypedGlobalNode {
    case globalVariable(name: String, type: Type, value: TypedExpressionNode, mutable: Bool)
    case globalFunction(
        name: String,
        parameters: [(name: String, type: Type)],
        returnType: Type,
        body: TypedExpressionNode
    )
}

public indirect enum TypedStatementNode {
    case variableDecl(name: String, type: Type, value: TypedExpressionNode, mutable: Bool)
    case assignment(name: String, value: TypedExpressionNode, type: Type)
    case expression(TypedExpressionNode)
}

public indirect enum TypedExpressionNode {
    case intLiteral(value: Int, type: Type)
    case floatLiteral(value: Double, type: Type)
    case stringLiteral(value: String, type: Type)
    case boolLiteral(value: Bool, type: Type)
    case arithmeticOp(left: TypedExpressionNode, op: ArithmeticOperator, right: TypedExpressionNode, type: Type)
    case comparisonOp(left: TypedExpressionNode, op: ComparisonOperator, right: TypedExpressionNode, type: Type)
    case variable(name: String, type: Type)
    case block(statements: [TypedStatementNode], finalExpr: TypedExpressionNode, type: Type)
    case ifExpr(condition: TypedExpressionNode, thenBranch: TypedExpressionNode, elseBranch: TypedExpressionNode, type: Type)
    case functionCall(name: String, arguments: [TypedExpressionNode], type: Type)
}

extension TypedExpressionNode {
    var type: Type {
        switch self {
        case .intLiteral(_, let type),
             .floatLiteral(_, let type),
             .stringLiteral(_, let type),
             .boolLiteral(_, let type),
             .arithmeticOp(_, _, _, let type),
             .comparisonOp(_, _, _, let type),
             .variable(_, let type),
             .block(_, _, let type),
             .ifExpr(_, _, _, let type),
             .functionCall(_, _, let type):
            return type
        }
    }
}

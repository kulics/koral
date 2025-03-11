public struct TypedIdentifierNode {
    public let name: String
    public let type: Type
}

// Typed AST node definitions for semantic analysis phase
public indirect enum TypedProgram {
    case program(globalNodes: [TypedGlobalNode])
}

public indirect enum TypedGlobalNode {
    case globalVariable(identifier: TypedIdentifierNode, value: TypedExpressionNode, mutable: Bool)
    case globalFunction(
        identifier: TypedIdentifierNode,
        parameters: [TypedIdentifierNode],
        body: TypedExpressionNode
    )
}

public indirect enum TypedStatementNode {
    case variableDecl(identifier: TypedIdentifierNode, value: TypedExpressionNode, mutable: Bool)
    case assignment(identifier: TypedIdentifierNode, value: TypedExpressionNode)
    case expression(TypedExpressionNode)
}

public indirect enum TypedExpressionNode {
    case intLiteral(value: Int, type: Type)
    case floatLiteral(value: Double, type: Type)
    case stringLiteral(value: String, type: Type)
    case boolLiteral(value: Bool, type: Type)
    case arithmeticOp(left: TypedExpressionNode, op: ArithmeticOperator, right: TypedExpressionNode, type: Type)
    case comparisonOp(left: TypedExpressionNode, op: ComparisonOperator, right: TypedExpressionNode, type: Type)
    case andOp(left: TypedExpressionNode, right: TypedExpressionNode, type: Type) 
    case orOp(left: TypedExpressionNode, right: TypedExpressionNode, type: Type)
    case notOp(expr: TypedExpressionNode, type: Type)
    case variable(identifier: TypedIdentifierNode)
    case block(statements: [TypedStatementNode], finalExpr: TypedExpressionNode?, type: Type)
    case ifExpr(condition: TypedExpressionNode, thenBranch: TypedExpressionNode, elseBranch: TypedExpressionNode, type: Type)
    case functionCall(identifier: TypedIdentifierNode, arguments: [TypedExpressionNode], type: Type)
    case whileExpr(condition: TypedExpressionNode, body: TypedExpressionNode, type: Type)
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
             .andOp(_, _, let type),
             .orOp(_, _, let type),
             .notOp(_, let type),
             .block(_, _, let type),
             .ifExpr(_, _, _, let type),
             .functionCall(_, _, let type),
             .whileExpr(_, _, let type):
            return type
        case .variable(let identifier):
            return identifier.type
        }
    }
}

public struct TypedIdentifierNode {
    public let name: String
    public let type: Type
    public let mutable: Bool
    
    public init(name: String, type: Type, mutable: Bool = false) {
        self.name = name
        self.type = type
        self.mutable = mutable
    }
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
    case globalTypeDeclaration(
        identifier: TypedIdentifierNode,
        parameters: [TypedIdentifierNode],
        isValue: Bool
    )
}

public indirect enum TypedStatementNode {
    case variableDeclaration(identifier: TypedIdentifierNode, value: TypedExpressionNode, mutable: Bool)
    case assignment(target: TypedAssignmentTarget, value: TypedExpressionNode)
    case expression(TypedExpressionNode)
}

public enum TypedAssignmentTarget {
    case variable(identifier: TypedIdentifierNode)
    case memberAccess(base: TypedIdentifierNode, memberPath: [TypedIdentifierNode])
}

public indirect enum TypedExpressionNode {
    case integerLiteral(value: Int, type: Type)
    case floatLiteral(value: Double, type: Type)
    case stringLiteral(value: String, type: Type)
    case booleanLiteral(value: Bool, type: Type)
    case arithmeticExpression(left: TypedExpressionNode, op: ArithmeticOperator, right: TypedExpressionNode, type: Type)
    case comparisonExpression(left: TypedExpressionNode, op: ComparisonOperator, right: TypedExpressionNode, type: Type)
    case andExpression(left: TypedExpressionNode, right: TypedExpressionNode, type: Type) 
    case orExpression(left: TypedExpressionNode, right: TypedExpressionNode, type: Type)
    case notExpression(expression: TypedExpressionNode, type: Type)
    case variable(identifier: TypedIdentifierNode)
    case blockExpression(statements: [TypedStatementNode], finalExpression: TypedExpressionNode?, type: Type)
    case ifExpression(condition: TypedExpressionNode, thenBranch: TypedExpressionNode, elseBranch: TypedExpressionNode, type: Type)
    case functionCall(identifier: TypedIdentifierNode, arguments: [TypedExpressionNode], type: Type)
    case whileExpression(condition: TypedExpressionNode, body: TypedExpressionNode, type: Type)
    case typeConstruction(identifier: TypedIdentifierNode, arguments: [TypedExpressionNode], type: Type)
    case memberAccess(source: TypedExpressionNode, member: TypedIdentifierNode)
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
             .blockExpression(_, _, let type),
             .ifExpression(_, _, _, let type),
             .functionCall(_, _, let type),
             .whileExpression(_, _, let type),
             .typeConstruction(_, _, let type):
            return type
        case .variable(let identifier):
            return identifier.type
        case .memberAccess(_, let member):
            return member.type
        }
    }
}

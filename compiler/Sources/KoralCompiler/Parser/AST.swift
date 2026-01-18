// Define AST node types using enums

// Method declaration used inside given blocks; same shape as a global function

public enum AccessModifier: String {
  case `public`
  case `private`
  case `protected`
  case `default`
}

// Re-export SourceSpan for AST nodes
public typealias ASTSpan = SourceSpan
public indirect enum ASTNode {
  case program(globalNodes: [GlobalNode])
}

public typealias TypeParameterDecl = (name: String, constraints: [TypeNode])

public indirect enum TypeNode {
  case identifier(String)
  case reference(TypeNode)
  case generic(base: String, args: [TypeNode])
  case inferredSelf
}

public struct TraitMethodSignature {
  public let name: String
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let access: AccessModifier
}

public struct UnionCaseDeclaration {
  public let name: String
  public let parameters: [(name: String, type: TypeNode)]
}
public indirect enum GlobalNode {
  case globalVariableDeclaration(
    name: String, type: TypeNode, value: ExpressionNode, mutable: Bool, access: AccessModifier,
    span: SourceSpan)
  case globalFunctionDeclaration(
    name: String,
    typeParameters: [TypeParameterDecl],
    parameters: [(name: String, mutable: Bool, type: TypeNode)],
    returnType: TypeNode,
    body: ExpressionNode,
    access: AccessModifier,
    span: SourceSpan
  )
  case intrinsicFunctionDeclaration(
    name: String,
    typeParameters: [TypeParameterDecl],
    parameters: [(name: String, mutable: Bool, type: TypeNode)],
    returnType: TypeNode,
    access: AccessModifier,
    span: SourceSpan
  )
  case globalStructDeclaration(
    name: String,
    typeParameters: [TypeParameterDecl],
    parameters: [(name: String, type: TypeNode, mutable: Bool, access: AccessModifier)],
    access: AccessModifier,
    span: SourceSpan
  )
  case globalUnionDeclaration(
    name: String,
    typeParameters: [TypeParameterDecl],
    cases: [UnionCaseDeclaration],
    access: AccessModifier,
    span: SourceSpan
  )
  case intrinsicTypeDeclaration(
    name: String,
    typeParameters: [TypeParameterDecl],
    access: AccessModifier,
    span: SourceSpan
  )

  // trait Name [SuperTrait ...] { methodSignatures... }
  case traitDeclaration(
    name: String,
    typeParameters: [TypeParameterDecl],
    superTraits: [String],
    methods: [TraitMethodSignature],
    access: AccessModifier,
    span: SourceSpan
  )

  // given [T] Type { ...methods... }
  case givenDeclaration(
    typeParams: [TypeParameterDecl] = [], type: TypeNode,
    methods: [MethodDeclaration], span: SourceSpan)
  case intrinsicGivenDeclaration(
    typeParams: [TypeParameterDecl] = [], type: TypeNode,
    methods: [IntrinsicMethodDeclaration], span: SourceSpan)
}

extension GlobalNode {
  public var span: SourceSpan {
    switch self {
    case .globalVariableDeclaration(_, _, _, _, _, let span):
      return span
    case .globalFunctionDeclaration(_, _, _, _, _, _, let span):
      return span
    case .intrinsicFunctionDeclaration(_, _, _, _, _, let span):
      return span
    case .globalStructDeclaration(_, _, _, _, let span):
      return span
    case .globalUnionDeclaration(_, _, _, _, let span):
      return span
    case .intrinsicTypeDeclaration(_, _, _, let span):
      return span
    case .traitDeclaration(_, _, _, _, _, let span):
      return span
    case .givenDeclaration(_, _, _, let span):
      return span
    case .intrinsicGivenDeclaration(_, _, _, let span):
      return span
    }
  }
  
  /// Line number for backward compatibility
  public var line: Int {
    span.start.line
  }
}
public struct IntrinsicMethodDeclaration {
  public let name: String
  public let typeParameters: [TypeParameterDecl]
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let access: AccessModifier

  public init(
    name: String,
    typeParameters: [TypeParameterDecl],
    parameters: [(name: String, mutable: Bool, type: TypeNode)],
    returnType: TypeNode,
    access: AccessModifier
  ) {
    self.name = name
    self.typeParameters = typeParameters
    self.parameters = parameters
    self.returnType = returnType
    self.access = access
  }
}
public struct MethodDeclaration {
  public let name: String
  public let typeParameters: [TypeParameterDecl]
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let body: ExpressionNode
  public let access: AccessModifier

  public init(
    name: String,
    typeParameters: [TypeParameterDecl],
    parameters: [(name: String, mutable: Bool, type: TypeNode)],
    returnType: TypeNode,
    body: ExpressionNode,
    access: AccessModifier
  ) {
    self.name = name
    self.typeParameters = typeParameters
    self.parameters = parameters
    self.returnType = returnType
    self.body = body
    self.access = access
  }
}
public indirect enum StatementNode {
  case variableDeclaration(
    name: String, type: TypeNode?, value: ExpressionNode, mutable: Bool, span: SourceSpan)
  case assignment(target: ExpressionNode, value: ExpressionNode, span: SourceSpan)
  case compoundAssignment(
    target: ExpressionNode, operator: CompoundAssignmentOperator, value: ExpressionNode, span: SourceSpan)
  case expression(ExpressionNode, span: SourceSpan)
  case `return`(value: ExpressionNode?, span: SourceSpan)
  case `break`(span: SourceSpan)
  case `continue`(span: SourceSpan)
}

extension StatementNode {
  /// The source span of this statement
  public var span: SourceSpan {
    switch self {
    case .variableDeclaration(_, _, _, _, let span): return span
    case .assignment(_, _, let span): return span
    case .compoundAssignment(_, _, _, let span): return span
    case .expression(_, let span): return span
    case .return(_, let span): return span
    case .break(let span): return span
    case .continue(let span): return span
    }
  }
  
  /// Line number for backward compatibility
  public var line: Int {
    span.start.line
  }
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
  case integerLiteral(String, NumericSuffix?)  // Store as string with optional suffix
  case floatLiteral(String, NumericSuffix?)    // Store as string with optional suffix
  case stringLiteral(String)
  case booleanLiteral(Bool)
  case castExpression(type: TypeNode, expression: ExpressionNode)
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
  case derefExpression(ExpressionNode)
  case refExpression(ExpressionNode)
  case identifier(String)
  case blockExpression(statements: [StatementNode], finalExpression: ExpressionNode?)
  case ifExpression(
    condition: ExpressionNode, thenBranch: ExpressionNode, elseBranch: ExpressionNode?)
  case call(callee: ExpressionNode, arguments: [ExpressionNode])
  case whileExpression(condition: ExpressionNode, body: ExpressionNode)
  case letExpression(
    name: String, type: TypeNode?, value: ExpressionNode, mutable: Bool, body: ExpressionNode)
  // 连续成员访问聚合为路径
  case memberPath(base: ExpressionNode, path: [String])
  case genericInstantiation(base: String, args: [TypeNode])
  case subscriptExpression(base: ExpressionNode, arguments: [ExpressionNode])
  case matchExpression(subject: ExpressionNode, cases: [MatchCaseNode], span: SourceSpan)
  /// Static method call on a type: TypeName.methodName(args) or [T]TypeName.methodName(args)
  /// - typeName: The type name (e.g., "String", "List")
  /// - typeArgs: Optional type arguments for generic types (e.g., [Int] for List)
  /// - methodName: The method name (e.g., "empty", "new")
  /// - arguments: The method arguments
  case staticMethodCall(typeName: String, typeArgs: [TypeNode], methodName: String, arguments: [ExpressionNode])
  /// For loop expression: for <pattern> = <iterable> then <body>
  case forExpression(pattern: PatternNode, iterable: ExpressionNode, body: ExpressionNode)
}
public indirect enum PatternNode: CustomStringConvertible {
  case booleanLiteral(value: Bool, span: SourceSpan)
  case integerLiteral(value: String, suffix: NumericSuffix?, span: SourceSpan)  // Store as string with optional suffix
  case stringLiteral(value: String, span: SourceSpan)
  case wildcard(span: SourceSpan)
  case variable(name: String, mutable: Bool, span: SourceSpan)
  case unionCase(caseName: String, elements: [PatternNode], span: SourceSpan)

  public var description: String {
    switch self {
    case .booleanLiteral(let value, _): return "\(value)"
    case .integerLiteral(let value, let suffix, _): 
      if let suffix = suffix {
        return "\(value)\(suffix)"
      }
      return "\(value)"
    case .stringLiteral(let value, _): return "\"\(value)\""
    case .wildcard: return "_"
    case .variable(let name, let mutable, _): return mutable ? "mut \(name)" : name
    case .unionCase(let name, let elements, _):
      let args = elements.map { $0.description }.joined(separator: ", ")
      return ".\(name)(\(args))"
    }
  }
  
  /// The source span of this pattern
  public var span: SourceSpan {
    switch self {
    case .booleanLiteral(_, let span): return span
    case .integerLiteral(_, _, let span): return span
    case .stringLiteral(_, let span): return span
    case .wildcard(let span): return span
    case .variable(_, _, let span): return span
    case .unionCase(_, _, let span): return span
    }
  }
  
  /// Line number for backward compatibility
  public var line: Int {
    span.start.line
  }
}
public struct MatchCaseNode {
  public let pattern: PatternNode
  public let body: ExpressionNode
}

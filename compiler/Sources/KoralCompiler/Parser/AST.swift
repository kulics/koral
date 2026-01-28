// Define AST node types using enums

// Method declaration used inside given blocks; same shape as a global function

public enum AccessModifier: String, Sendable {
  case `public`
  case `private`
  case `protected`
  case `default`
}

// MARK: - Module System Types

/// Using 声明的路径类型
public enum UsingPathKind {
  case external    // 外部模块: using std
  case fileMerge   // 文件合并: using "user"
  case submodule   // 子模块: using self.utils
  case parent      // 父模块: using super.sibling
}

/// Using 声明 AST 节点
public struct UsingDeclaration {
  /// 路径类型
  public let pathKind: UsingPathKind
  
  /// 模块路径段
  /// - external: ["std", "text"]
  /// - fileMerge: ["user"] (文件名)
  /// - submodule: ["utils", "SomeType"]
  /// - parent: ["super", "sibling"] 或 ["super", "super", "uncle"]
  public let pathSegments: [String]
  
  /// 可选别名: using txt = std.text
  public let alias: String?
  
  /// 是否批量导入: using std.text.*
  public let isBatchImport: Bool
  
  /// 访问修饰符
  public let access: AccessModifier
  
  /// 源码位置
  public let span: SourceSpan
  
  public init(
    pathKind: UsingPathKind,
    pathSegments: [String],
    alias: String? = nil,
    isBatchImport: Bool = false,
    access: AccessModifier = .default,
    span: SourceSpan
  ) {
    self.pathKind = pathKind
    self.pathSegments = pathSegments
    self.alias = alias
    self.isBatchImport = isBatchImport
    self.access = access
    self.span = span
  }
}

// Re-export SourceSpan for AST nodes
public typealias ASTSpan = SourceSpan
public indirect enum ASTNode {
  case program(globalNodes: [GlobalNode])
}

public typealias TypeParameterDecl = (name: String, constraints: [TypeNode])

public indirect enum TypeNode: CustomStringConvertible {
  case identifier(String)
  case reference(TypeNode)
  case generic(base: String, args: [TypeNode])
  case inferredSelf
  /// Function type: [ParamType1, ParamType2, ..., ReturnType]Func
  /// The last type in args is the return type, all others are parameter types
  case functionType(paramTypes: [TypeNode], returnType: TypeNode)
  /// Module-qualified type: module.TypeName
  case moduleQualified(module: String, name: String)
  /// Module-qualified generic type: module.[T]List
  case moduleQualifiedGeneric(module: String, base: String, args: [TypeNode])
  
  public var description: String {
    switch self {
    case .identifier(let name):
      return name
    case .reference(let inner):
      return "\(inner) ref"
    case .generic(let base, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "[\(argsStr)]\(base)"
    case .inferredSelf:
      return "Self"
    case .functionType(let paramTypes, let returnType):
      let allTypes = paramTypes + [returnType]
      let typesStr = allTypes.map { $0.description }.joined(separator: ", ")
      return "[\(typesStr)]Func"
    case .moduleQualified(let module, let name):
      return "\(module).\(name)"
    case .moduleQualifiedGeneric(let module, let base, let args):
      let argsStr = args.map { $0.description }.joined(separator: ", ")
      return "\(module).[\(argsStr)]\(base)"
    }
  }
}

public struct TraitMethodSignature {
  public let name: String
  public let typeParameters: [TypeParameterDecl]  // 方法级泛型参数
  public let parameters: [(name: String, mutable: Bool, type: TypeNode)]
  public let returnType: TypeNode
  public let access: AccessModifier
  
  public init(
    name: String,
    typeParameters: [TypeParameterDecl] = [],
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

public struct UnionCaseDeclaration {
  public let name: String
  public let parameters: [(name: String, type: TypeNode)]
}
public indirect enum GlobalNode {
  // Using declaration (must appear at the beginning of a file)
  case usingDeclaration(UsingDeclaration)
  
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
    case .usingDeclaration(let decl):
      return decl.span
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
}

public enum CompoundAssignmentOperator {
  case plus
  case minus
  case multiply
  case divide
  case modulo
  case power
  case bitwiseAnd
  case bitwiseOr
  case bitwiseXor
  case shiftLeft
  case shiftRight
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
  case power
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

/// Range operator types for range expressions
public enum RangeOperator {
  case closed        // ..    a..b   : start <= x <= end
  case closedOpen    // ..<   a..<b  : start <= x < end
  case openClosed    // <..   a<..b  : start < x <= end
  case open          // <..<  a<..<b : start < x < end
  case from          // ...   a...   : start <= x <= max
  case fromOpen      // <...  a<...  : start < x <= max
  case to            // ...   ...b   : min <= x <= end
  case toOpen        // ...<  ...<b  : min <= x < end
  case full          // ....  ....   : min <= x <= max
}

/// Comparison pattern operator types for comparison patterns
public enum ComparisonPatternOperator {
  case greater       // >
  case less          // <
  case greaterEqual  // >=
  case lessEqual     // <=
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
  /// Conditional pattern matching expression: if expr is pattern then body [else elseBranch]
  case ifPatternExpression(
    subject: ExpressionNode,
    pattern: PatternNode,
    thenBranch: ExpressionNode,
    elseBranch: ExpressionNode?,
    span: SourceSpan
  )
  case call(callee: ExpressionNode, arguments: [ExpressionNode])
  case whileExpression(condition: ExpressionNode, body: ExpressionNode)
  /// While pattern matching expression: while expr is pattern then body
  case whilePatternExpression(
    subject: ExpressionNode,
    pattern: PatternNode,
    body: ExpressionNode,
    span: SourceSpan
  )
  case letExpression(
    name: String, type: TypeNode?, value: ExpressionNode, mutable: Bool, body: ExpressionNode)
  // 连续成员访问聚合为路径
  case memberPath(base: ExpressionNode, path: [String])
  /// Generic method call with explicit type arguments: obj.[Type]method(args)
  /// - base: The object expression
  /// - methodTypeArgs: The explicit type arguments for the method
  /// - methodName: The method name
  /// - arguments: The method arguments
  case genericMethodCall(base: ExpressionNode, methodTypeArgs: [TypeNode], methodName: String, arguments: [ExpressionNode])
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
  /// Range expression with operator and operands
  /// - operator: The range operator type
  /// - left: Left operand (nil for ToRange, ToOpenRange, FullRange)
  /// - right: Right operand (nil for FromRange, FromOpenRange, FullRange)
  case rangeExpression(operator: RangeOperator, left: ExpressionNode?, right: ExpressionNode?)
  /// Lambda expression: (params) [ReturnType] -> body
  /// - parameters: Parameter list with optional type annotations
  /// - returnType: Optional return type annotation
  /// - body: Lambda body expression
  /// - span: Source location
  case lambdaExpression(
    parameters: [(name: String, type: TypeNode?)],
    returnType: TypeNode?,
    body: ExpressionNode,
    span: SourceSpan
  )
}
public indirect enum PatternNode: CustomStringConvertible {
  case booleanLiteral(value: Bool, span: SourceSpan)
  case integerLiteral(value: String, suffix: NumericSuffix?, span: SourceSpan)  // Store as string with optional suffix
  /// Negative integer literal pattern for matching negative integers (e.g., -5)
  case negativeIntegerLiteral(value: String, suffix: NumericSuffix?, span: SourceSpan)
  case stringLiteral(value: String, span: SourceSpan)
  case wildcard(span: SourceSpan)
  case variable(name: String, mutable: Bool, span: SourceSpan)
  case unionCase(caseName: String, elements: [PatternNode], span: SourceSpan)
  /// Comparison pattern for matching values using comparison operators (e.g., > 5, <= 10)
  /// - operator: The comparison operator (>, <, >=, <=)
  /// - value: The integer literal value to compare against (stored as string)
  /// - suffix: Optional numeric suffix for the integer literal
  case comparisonPattern(operator: ComparisonPatternOperator, value: String, suffix: NumericSuffix?, span: SourceSpan)
  /// And pattern for combining two patterns with logical AND
  case andPattern(left: PatternNode, right: PatternNode, span: SourceSpan)
  /// Or pattern for combining two patterns with logical OR
  case orPattern(left: PatternNode, right: PatternNode, span: SourceSpan)
  /// Not pattern for negating a pattern
  case notPattern(pattern: PatternNode, span: SourceSpan)

  public var description: String {
    switch self {
    case .booleanLiteral(let value, _): return "\(value)"
    case .integerLiteral(let value, let suffix, _): 
      if let suffix = suffix {
        return "\(value)\(suffix)"
      }
      return "\(value)"
    case .negativeIntegerLiteral(let value, let suffix, _):
      if let suffix = suffix {
        return "-\(value)\(suffix)"
      }
      return "-\(value)"
    case .stringLiteral(let value, _): return "\"\(value)\""
    case .wildcard: return "_"
    case .variable(let name, let mutable, _): return mutable ? "mut \(name)" : name
    case .unionCase(let name, let elements, _):
      let args = elements.map { $0.description }.joined(separator: ", ")
      return ".\(name)(\(args))"
    case .comparisonPattern(let op, let value, let suffix, _):
      let opStr: String
      switch op {
      case .greater: opStr = ">"
      case .less: opStr = "<"
      case .greaterEqual: opStr = ">="
      case .lessEqual: opStr = "<="
      }
      if let suffix = suffix {
        return "\(opStr) \(value)\(suffix)"
      }
      return "\(opStr) \(value)"
    case .andPattern(let left, let right, _):
      return "(\(left.description) and \(right.description))"
    case .orPattern(let left, let right, _):
      return "(\(left.description) or \(right.description))"
    case .notPattern(let pattern, _):
      return "not \(pattern.description)"
    }
  }
  
  /// The source span of this pattern
  public var span: SourceSpan {
    switch self {
    case .booleanLiteral(_, let span): return span
    case .integerLiteral(_, _, let span): return span
    case .negativeIntegerLiteral(_, _, let span): return span
    case .stringLiteral(_, let span): return span
    case .wildcard(let span): return span
    case .variable(_, _, let span): return span
    case .unionCase(_, _, let span): return span
    case .comparisonPattern(_, _, _, let span): return span
    case .andPattern(_, _, let span): return span
    case .orPattern(_, _, let span): return span
    case .notPattern(_, let span): return span
    }
  }
}

public struct MatchCaseNode {
  public let pattern: PatternNode
  public let body: ExpressionNode
}

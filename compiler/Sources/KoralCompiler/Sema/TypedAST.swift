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
public enum CompilerMethodKind {
  case normal
  case drop
  case at
  case updateAt
}
public struct Symbol {
  public let name: String
  public let type: Type
  public let kind: SymbolKind
  public let methodKind: CompilerMethodKind

  public init(name: String, type: Type, kind: SymbolKind, methodKind: CompilerMethodKind = .normal)
  {
    self.name = name
    self.type = type
    self.kind = kind
    self.methodKind = methodKind
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
  case globalStructDeclaration(
    identifier: Symbol,
    parameters: [Symbol]
  )
  case globalUnionDeclaration(identifier: Symbol, cases: [UnionCase])
  case genericTypeTemplate(name: String)
  case givenDeclaration(type: Type, methods: [TypedMethodDeclaration])
  case genericFunctionTemplate(name: String)
}
public struct TypedMethodDeclaration {
  public let identifier: Symbol
  public let parameters: [Symbol]
  public let body: TypedExpressionNode
  public let returnType: Type
}
public indirect enum TypedStatementNode {
  case variableDeclaration(identifier: Symbol, value: TypedExpressionNode, mutable: Bool)
  case assignment(target: TypedExpressionNode, value: TypedExpressionNode)
  case compoundAssignment(
    target: TypedExpressionNode, operator: CompoundAssignmentOperator, value: TypedExpressionNode)
  case expression(TypedExpressionNode)
  case `return`(value: TypedExpressionNode?)
  case `break`
  case `continue`
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
  case derefExpression(expression: TypedExpressionNode, type: Type)
  case referenceExpression(expression: TypedExpressionNode, type: Type)
  case variable(identifier: Symbol)
  case blockExpression(
    statements: [TypedStatementNode], finalExpression: TypedExpressionNode?, type: Type)
  case ifExpression(
    condition: TypedExpressionNode, thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?, type: Type)
  case call(callee: TypedExpressionNode, arguments: [TypedExpressionNode], type: Type)
  case methodReference(base: TypedExpressionNode, method: Symbol, type: Type)
  case whileExpression(condition: TypedExpressionNode, body: TypedExpressionNode, type: Type)
  case typeConstruction(identifier: Symbol, arguments: [TypedExpressionNode], type: Type)
  case memberPath(source: TypedExpressionNode, path: [Symbol])
  case subscriptExpression(
    base: TypedExpressionNode, arguments: [TypedExpressionNode], method: Symbol, type: Type)
  case unionConstruction(type: Type, caseName: String, arguments: [TypedExpressionNode])
  case intrinsicCall(TypedIntrinsic)
  case matchExpression(subject: TypedExpressionNode, cases: [TypedMatchCase], type: Type)
}
public indirect enum TypedIntrinsic {
  // Memory Management
  case allocMemory(count: TypedExpressionNode, resultType: Type)
  case deallocMemory(ptr: TypedExpressionNode)
  case copyMemory(
    dest: TypedExpressionNode, source: TypedExpressionNode, count: TypedExpressionNode)
  case moveMemory(
    dest: TypedExpressionNode, source: TypedExpressionNode, count: TypedExpressionNode)
  case refCount(val: TypedExpressionNode)

  // Pointer Operations
  case ptrInit(ptr: TypedExpressionNode, val: TypedExpressionNode)
  case ptrDeinit(ptr: TypedExpressionNode)
  case ptrPeek(ptr: TypedExpressionNode)
  case ptrOffset(ptr: TypedExpressionNode, offset: TypedExpressionNode)
  case ptrTake(ptr: TypedExpressionNode)
  case ptrReplace(ptr: TypedExpressionNode, val: TypedExpressionNode)

  // Primitive IO
  case printString(message: TypedExpressionNode)
  case printInt(value: TypedExpressionNode)
  case printBool(value: TypedExpressionNode)
  case panic(message: TypedExpressionNode)
  case exit(code: TypedExpressionNode)
  case abort

  public var type: Type {
    switch self {
    case .allocMemory(_, let resultType): return resultType
    case .deallocMemory: return .void
    case .copyMemory: return .void
    case .moveMemory: return .void
    case .refCount: return .int
    case .ptrInit: return .void
    case .ptrDeinit: return .void
    case .ptrPeek(let ptr):
      // return T ref
      if case .pointer(let element) = ptr.type {
        return .reference(inner: element)
      }
      fatalError("ptrPeek on non-pointer")
    case .ptrOffset(let ptr, _): return ptr.type
    case .ptrTake(let ptr):
      if case .pointer(let element) = ptr.type { return element }
      fatalError("ptrTake on non-pointer")
    case .ptrReplace(let ptr, _):
      if case .pointer(let element) = ptr.type { return element }
      fatalError("ptrReplace on non-pointer")
    case .printString: return .void
    case .printInt: return .void
    case .printBool: return .void
    case .panic: return .never
    case .exit: return .never
    case .abort: return .never
    }
  }
}
public indirect enum TypedPattern: CustomStringConvertible {
  case booleanLiteral(value: Bool)
  case integerLiteral(value: Int)
  case stringLiteral(value: String)
  case wildcard
  case variable(symbol: Symbol)
  case unionCase(caseName: String, tagIndex: Int, elements: [TypedPattern])

  public var description: String {
    switch self {
    case .booleanLiteral(let v): return "\(v)"
    case .integerLiteral(let v): return "\(v)"
    case .stringLiteral(let v): return "\"\(v)\""
    case .wildcard: return "_"
    case .variable(let s): return s.name
    case .unionCase(let name, _, let elements):
      let args = elements.map { $0.description }.joined(separator: ", ")
      return ".\(name)(\(args))"
    }
  }
}
public struct TypedMatchCase {
  public let pattern: TypedPattern
  public let body: TypedExpressionNode
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
      .derefExpression(_, let type),
      .referenceExpression(_, let type),
      .blockExpression(_, _, let type),
      .ifExpression(_, _, _, let type),
      .call(_, _, let type),
      .methodReference(_, _, let type),
      .whileExpression(_, _, let type),
      .typeConstruction(_, _, let type),
      .unionConstruction(let type, _, _),
      .letExpression(_, _, _, let type):
      return type
    case .variable(let identifier):
      return identifier.type
    case .memberPath(_, let path):
      return path.last?.type ?? .void
    case .subscriptExpression(_, _, _, let type):
      return type
    case .intrinsicCall(let node):
      return node.type
    case .matchExpression(_, _, let type):
      return type
    }
  }

  var valueCategory: ValueCategory {
    switch self {
    case .variable:
      return .lvalue
    case .memberPath(let source, _):
      // member access is lvalue if the source is lvalue
      return source.valueCategory
    case .subscriptExpression(let base, _, _, _):
      // Subscript result acts as LValue (can be assigned to if mutable)
      return base.valueCategory
    case .referenceExpression:

      // &expr 是一个临时值（指针）
      return .rvalue
    default:
      return .rvalue
    }
  }
}

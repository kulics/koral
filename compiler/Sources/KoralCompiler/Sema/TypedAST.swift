// Typed AST node definitions for semantic analysis phase

import Foundation

public enum ValueCategory {
  case lvalue
  case rvalue
}
public enum SymbolKind {
  case variable(VariableKind)
  case function
  case type
  case module(ModuleSymbolInfo)
}

/// 符号的导入方式
/// 用于决定符号是否可以直接访问（不需要模块前缀）
public enum ImportKind {
  /// 当前模块定义的符号（包括文件合并）
  case local
  /// 成员导入：using self.module.symbol
  case memberImport
  /// 批量导入：using self.module.*
  case batchImport
  /// 模块导入：using self.module（符号不直接可用，需要通过模块前缀访问）
  case moduleImport
  
  /// 是否可以直接访问（不需要模块前缀）
  public var isDirectlyAccessible: Bool {
    switch self {
    case .local, .memberImport, .batchImport:
      return true
    case .moduleImport:
      return false
    }
  }
}

/// 模块符号信息
public struct ModuleSymbolInfo {
  /// 模块路径
  public let modulePath: [String]
  /// 模块中的公开符号（函数、类型等）
  public var publicSymbols: [String: Symbol]
  /// 模块中的公开类型
  public var publicTypes: [String: Type]
  
  public init(modulePath: [String], publicSymbols: [String: Symbol] = [:], publicTypes: [String: Type] = [:]) {
    self.modulePath = modulePath
    self.publicSymbols = publicSymbols
    self.publicTypes = publicTypes
  }
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

/// Capture kind for lambda closures
public enum CaptureKind {
  /// Value capture: copy the variable's value
  case byValue
  /// Reference capture: capture reference type, increment reference count
  case byReference
}

/// Captured variable information for lambda closures
public struct CapturedVariable {
  /// The captured variable symbol
  public let symbol: Symbol
  /// How the variable is captured
  public let captureKind: CaptureKind
  
  public init(symbol: Symbol, captureKind: CaptureKind) {
    self.symbol = symbol
    self.captureKind = captureKind
  }
}
public enum CompilerMethodKind {
  case normal
  case drop
}
public struct Symbol {
  public let defId: DefId
  public let type: Type
  public let kind: SymbolKind
  public let methodKind: CompilerMethodKind

  public init(
    defId: DefId,
    type: Type,
    kind: SymbolKind,
    methodKind: CompilerMethodKind = .normal
  ) {
    self.defId = defId
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
    case .function, .type, .module:
      return false
    }
  }
}
public indirect enum TypedProgram {
  case program(globalNodes: [TypedGlobalNode])
}
public indirect enum TypedGlobalNode {
  case foreignUsing(libraryName: String)
  case foreignFunction(identifier: Symbol, parameters: [Symbol])
  case foreignType(identifier: Symbol)
  case foreignStruct(identifier: Symbol, fields: [(name: String, type: Type)])
  case foreignGlobalVariable(identifier: Symbol, mutable: Bool)
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
  case assignment(
    target: TypedExpressionNode, operator: CompoundAssignmentOperator?, value: TypedExpressionNode)
  case deptrAssignment(
    pointer: TypedExpressionNode, operator: CompoundAssignmentOperator?, value: TypedExpressionNode)
  case expression(TypedExpressionNode)
  case `return`(value: TypedExpressionNode?)
  case `break`
  case `continue`
}
public indirect enum TypedExpressionNode {
  case integerLiteral(value: String, type: Type)  // Store as string to support arbitrary precision
  case floatLiteral(value: String, type: Type)    // Store as string to support arbitrary precision
  case stringLiteral(value: String, type: Type)
  case interpolatedString(parts: [TypedInterpolatedPart], type: Type)
  case booleanLiteral(value: Bool, type: Type)
  case castExpression(expression: TypedExpressionNode, type: Type)
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
  case ptrExpression(expression: TypedExpressionNode, type: Type)
  case deptrExpression(expression: TypedExpressionNode, type: Type)
  case variable(identifier: Symbol)
  case blockExpression(
    statements: [TypedStatementNode], finalExpression: TypedExpressionNode?, type: Type)
  case ifExpression(
    condition: TypedExpressionNode, thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?, type: Type)
  /// Conditional pattern matching expression (if expr is pattern then body else ...)
  /// - subject: The expression being matched against
  /// - pattern: The pattern to match
  /// - bindings: Variable bindings introduced by the pattern (name, isMutable, type)
  /// - thenBranch: Expression to evaluate when pattern matches
  /// - elseBranch: Optional expression to evaluate when pattern doesn't match
  /// - type: The result type of the expression
  case ifPatternExpression(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    bindings: [(String, Bool, Type)],
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    type: Type)
  case call(callee: TypedExpressionNode, arguments: [TypedExpressionNode], type: Type)
  case genericCall(functionName: String, typeArgs: [Type], arguments: [TypedExpressionNode], type: Type)
  case methodReference(base: TypedExpressionNode, method: Symbol, typeArgs: [Type]?, methodTypeArgs: [Type]?, type: Type)
  /// Static method call on a type (e.g., `[Int]List.new()`, `Pair.new(1, 2)`)
  /// - baseType: The type on which the static method is called
  /// - methodName: The original method name (not mangled)
  /// - typeArgs: Type arguments for generic types (e.g., [Int] for [Int]List)
  /// - arguments: Method arguments
  /// - type: Return type
  case staticMethodCall(baseType: Type, methodName: String, typeArgs: [Type], arguments: [TypedExpressionNode], type: Type)
  case whileExpression(condition: TypedExpressionNode, body: TypedExpressionNode, type: Type)
  /// Loop pattern matching expression (while expr is pattern then body)
  /// - subject: The expression being matched against in each iteration
  /// - pattern: The pattern to match
  /// - bindings: Variable bindings introduced by the pattern (name, isMutable, type)
  /// - body: Expression to evaluate when pattern matches
  /// - type: The result type of the expression (always Void)
  case whilePatternExpression(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    bindings: [(String, Bool, Type)],
    body: TypedExpressionNode,
    type: Type)
  case typeConstruction(identifier: Symbol, typeArgs: [Type]?, arguments: [TypedExpressionNode], type: Type)
  case memberPath(source: TypedExpressionNode, path: [Symbol])
  case subscriptExpression(
    base: TypedExpressionNode, arguments: [TypedExpressionNode], method: Symbol, type: Type)
  case unionConstruction(type: Type, caseName: String, arguments: [TypedExpressionNode])
  case intrinsicCall(TypedIntrinsic)
  case matchExpression(subject: TypedExpressionNode, cases: [TypedMatchCase], type: Type)
  /// Lambda expression (closure)
  /// - parameters: Typed parameter symbols
  /// - captures: Captured variables from outer scope
  /// - body: Lambda body expression
  /// - type: Function type of the lambda
  case lambdaExpression(
    parameters: [Symbol],
    captures: [CapturedVariable],
    body: TypedExpressionNode,
    type: Type
  )
  /// Trait method placeholder for generic parameter method calls
  /// - traitName: The name of the trait (e.g., "Iterator", "Equatable")
  /// - methodName: The name of the method (e.g., "next", "equals")
  /// - base: The base expression (generic parameter reference)
  /// - methodTypeArgs: Method-level type arguments (for generic methods)
  /// - type: The expected function type of the method
  case traitMethodPlaceholder(
    traitName: String,
    methodName: String,
    base: TypedExpressionNode,
    methodTypeArgs: [Type],
    type: Type
  )
}

public enum TypedInterpolatedPart {
  case literal(String)
  case expression(TypedExpressionNode)
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

  // Weak Reference Operations
  case downgradeRef(val: TypedExpressionNode, resultType: Type)
  case upgradeRef(val: TypedExpressionNode, resultType: Type)

  // Pointer Operations
  case initMemory(ptr: TypedExpressionNode, val: TypedExpressionNode)
  case deinitMemory(ptr: TypedExpressionNode)
  case offsetPtr(ptr: TypedExpressionNode, offset: TypedExpressionNode)
  case takeMemory(ptr: TypedExpressionNode)
  case nullPtr(resultType: Type)



  public var type: Type {
    switch self {
    case .allocMemory(_, let resultType): return resultType
    case .deallocMemory: return .void
    case .copyMemory: return .void
    case .moveMemory: return .void
    case .refCount: return .int
    case .downgradeRef(_, let resultType): return resultType
    case .upgradeRef(_, let resultType): return resultType
    case .initMemory: return .void
    case .deinitMemory: return .void
    case .offsetPtr(let ptr, _): return ptr.type
    case .takeMemory(let ptr):
      if case .pointer(let element) = ptr.type { return element }
      fatalError("takeMemory on non-pointer")
    case .nullPtr(let resultType): return resultType


    }
  }
}
public indirect enum TypedPattern: CustomStringConvertible {
  case booleanLiteral(value: Bool)
  case integerLiteral(value: String)  // Store as string to support arbitrary precision
  case stringLiteral(value: String)
  case wildcard
  case variable(symbol: Symbol)
  case unionCase(caseName: String, tagIndex: Int, elements: [TypedPattern])
  
  // Comparison pattern - matches values based on comparison operators
  // - operator: The comparison operator (>, <, >=, <=)
  // - value: The integer value to compare against
  case comparisonPattern(operator: ComparisonPatternOperator, value: Int64)
  
  // Combination patterns for logical composition of patterns
  case andPattern(left: TypedPattern, right: TypedPattern)
  case orPattern(left: TypedPattern, right: TypedPattern)
  case notPattern(pattern: TypedPattern)

  public var description: String {
    switch self {
    case .booleanLiteral(let v): return "\(v)"
    case .integerLiteral(let v): return "\(v)"
    case .stringLiteral(let v): return "\"\(v)\""
    case .wildcard: return "_"
    case .variable(let s): return "def#\(s.defId.id)"
    case .unionCase(let name, _, let elements):
      let args = elements.map { $0.description }.joined(separator: ", ")
      return ".\(name)(\(args))"
    case .comparisonPattern(let op, let value):
      let opStr: String
      switch op {
      case .greater: opStr = ">"
      case .less: opStr = "<"
      case .greaterEqual: opStr = ">="
      case .lessEqual: opStr = "<="
      }
      return "\(opStr) \(value)"
    case .andPattern(let left, let right):
      return "(\(left) and \(right))"
    case .orPattern(let left, let right):
      return "(\(left) or \(right))"
    case .notPattern(let pattern):
      return "not \(pattern)"
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
      .interpolatedString(_, let type),
      .booleanLiteral(_, let type),
      .castExpression(_, let type),
      .arithmeticExpression(_, _, _, let type),
      .comparisonExpression(_, _, _, let type),
      .andExpression(_, _, let type),
      .orExpression(_, _, let type),
      .notExpression(_, let type),
      .bitwiseExpression(_, _, _, let type),
      .bitwiseNotExpression(_, let type),
      .derefExpression(_, let type),
      .referenceExpression(_, let type),
      .ptrExpression(_, let type),
      .deptrExpression(_, let type),
      .blockExpression(_, _, let type),
      .ifExpression(_, _, _, let type),
      .ifPatternExpression(_, _, _, _, _, let type),
      .call(_, _, let type),
      .genericCall(_, _, _, let type),
      .methodReference(_, _, _, _, let type),
      .staticMethodCall(_, _, _, _, let type),
      .whileExpression(_, _, let type),
      .whilePatternExpression(_, _, _, _, let type),
      .typeConstruction(_, _, _, let type),
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
    case .lambdaExpression(_, _, _, let type):
      return type
    case .traitMethodPlaceholder(_, _, _, _, let type):
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
    case .ptrExpression, .deptrExpression:
      return .rvalue
    case .castExpression:
      return .rvalue
    default:
      return .rvalue
    }
  }
}

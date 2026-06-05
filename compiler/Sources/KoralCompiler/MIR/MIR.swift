import Foundation

struct MIRBlockID: Hashable, CustomStringConvertible {
  let rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  var description: String { "bb\(rawValue)" }
}

struct MIRLocalID: Hashable, CustomStringConvertible {
  let rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  var description: String { "%\(rawValue)" }
}

struct MIRScopeID: Hashable, CustomStringConvertible {
  let rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  var description: String { "scope\(rawValue)" }
}

struct MIRProgram {
  let globals: [MIRGlobal]
  let functions: [MIRFunction]
  let context: CompilerContext
  let staticMethodLookup: [String: DefId]
  let traits: [String: TraitDeclInfo]
  let receiverMethodDispatch: [DefId: ReceiverMethodDispatchInfo]

  func lookupStaticMethod(typeName: String, methodName: String) -> DefId? {
    staticMethodLookup["\(typeName).\(methodName)"]
  }
}

enum MIRGlobal {
  case foreignFunction(identifier: Symbol, parameters: [Symbol])
  case foreignType(identifier: Symbol)
  case foreignStruct(identifier: Symbol, fields: [(name: String, type: Type)])
  case foreignGlobalVariable(identifier: Symbol, mutable: Bool)
  case globalVariable(identifier: Symbol, initializerFunction: Symbol, kind: VariableKind)
  case structDeclaration(identifier: Symbol, parameters: [Symbol])
  case enumDeclaration(identifier: Symbol, cases: [EnumCase])
  case function(identifier: Symbol, parameters: [Symbol], kind: MIRFunctionKind)
  case given(type: Type, trait: TypedTraitConformance?, methods: [Symbol])
  case traitVTable(MIRTraitVTable)
  case templatePlaceholder(name: String)
}

struct MIRTraitVTable {
  let concreteType: Type
  let traitName: String
  let traitTypeArguments: [Type]
  let methods: [MIRTraitVTableMethod]

  var key: MIRTraitVTableKey {
    MIRTraitVTableKey(
      concreteType: concreteType,
      traitName: traitName,
      traitTypeArguments: traitTypeArguments
    )
  }
}

struct MIRTraitVTableMethod {
  let name: String
  let returnType: Type?
  let parameters: [MIRTraitVTableParameter]
  let selfByValue: Bool
}

struct MIRTraitVTableParameter {
  let name: String
  let type: Type?
  let isSelf: Bool
}

struct MIRTraitVTableKey: Hashable {
  let concreteType: Type
  let traitName: String
  let traitTypeArguments: [Type]
}

enum MIRFunctionKind {
  case global
  case given(type: Type, trait: TypedTraitConformance?)
}

struct MIRFunction {
  let identifier: Symbol
  let parameters: [Symbol]
  let returnType: Type
  let kind: MIRFunctionKind
  let entryBlock: MIRBlockID
  var locals: [MIRLocal]
  var blocks: [MIRBasicBlock]
}

struct MIRLocal {
  let id: MIRLocalID
  let name: String
  let type: Type
  let mutability: MIRMutability
  let storage: MIRStorage
  let symbol: Symbol?
}

enum MIRMutability {
  case immutable
  case mutable
}

enum MIRStorage {
  case parameter
  case capture
  case local
  case temporary
}

struct MIRBasicBlock {
  let id: MIRBlockID
  var statements: [MIRStatement]
  var terminator: MIRTerminator
}

enum MIRStatement {
  case declare(MIRLocalID)
  case assign(MIRPlace, MIRValue)
  case compoundAssign(MIRCompoundAssignment)
  case drop(MIRPlace)
  case retain(MIRValue)
  case release(MIRValue)
  case evaluate(MIRValue)
  case scopeEnter(MIRScopeID)
  case scopeExit(MIRScopeID)
  case debugSource(SourceSpan)
}

enum MIRTerminator {
  case goto(MIRBlockID)
  case branch(condition: MIROperand, thenBlock: MIRBlockID, elseBlock: MIRBlockID)
  case switchValue(MIROperand, cases: [MIRSwitchCase], defaultBlock: MIRBlockID?)
  case returnValue(MIROperand?)
  case unreachable
}

indirect enum MIRPlace {
  case local(MIRLocalID)
  case global(DefId)
  case field(base: MIRPlace, field: Symbol)
  case enumPayload(base: MIRPlace, caseName: String, fieldName: String, fieldIndex: Int, fieldType: Type)
  case deref(base: MIRValue, pointee: Type)
  case pointerElement(base: MIRValue, element: Type)
}

indirect enum MIRValue {
  case operand(MIROperand)
  case placeRead(MIRPlace, ownership: MIROwnershipUse)
  case binary(MIRBinaryOperation)
  case unary(MIRUnaryOperation)
  case call(MIRCall)
  case aggregate(MIRAggregate)
  case enumCase(MIREnumConstruction)
  case enumTag(MIREnumTag)
  case traitObjectConversion(MIRTraitObjectConversion)
  case traitMethodCall(MIRTraitMethodCall)
  case ref(MIRPlace, kind: MIRReferenceKind, allocation: MIRReferenceAllocation)
  case pointer(MIRPlace)
  case cast(MIROperand, to: Type)
  case intrinsic(MIRIntrinsic)
  case lambda(MIRLambda)
}

enum MIROperand {
  case local(MIRLocalID)
  case constant(MIRConstant)
  case function(Symbol)
}

enum MIRConstant {
  case integer(String, Type)
  case float(String, Type)
  case string(String, Type)
  case boolean(Bool)
  case void
}

enum MIROwnershipUse {
  case copy
  case move
  case borrow
  case take
}

struct MIRBinaryOperation {
  let left: MIROperand
  let operatorKind: MIRBinaryOperator
  let right: MIROperand
  let type: Type
}

enum MIRBinaryOperator {
  case arithmetic(ArithmeticOperator, checked: Bool)
  case wrappingArithmetic(ArithmeticOperator)
  case comparison(ComparisonOperator)
  case logicalAnd
  case logicalOr
  case bitwise(BitwiseOperator, checkedShift: Bool)
  case wrappingShift(BitwiseOperator)
}

struct MIRUnaryOperation {
  let operatorKind: MIRUnaryOperator
  let operand: MIROperand
  let type: Type
}

enum MIRUnaryOperator {
  case logicalNot
  case bitwiseNot
}

enum MIRReferenceKind {
  case shared
  case mutable
  case weak
  case mutableWeak
}

enum MIRReferenceAllocation {
  case stackBorrow
  case heapOwned
}

struct MIRCompoundAssignment {
  let target: MIRPlace
  let operatorKind: CompoundAssignmentOperator
  let value: MIRValue
}

struct MIRCall {
  let callee: MIROperand
  let arguments: [MIRValue]
  let argumentOwnerships: [MIROwnershipUse]
  let type: Type
}

struct MIRAggregate {
  let type: Type
  let fields: [MIRValue]
}

struct MIREnumConstruction {
  let type: Type
  let caseName: String
  let arguments: [MIRValue]
}

struct MIREnumTag {
  let subject: MIRValue
  let enumType: Type
}

struct MIRTraitObjectConversion {
  let inner: MIRValue
  let sourceOwnership: MIROwnershipUse
  let traitName: String
  let traitTypeArguments: [Type]
  let concreteType: Type
  let type: Type

  var vtableKey: MIRTraitVTableKey {
    MIRTraitVTableKey(
      concreteType: concreteType,
      traitName: traitName,
      traitTypeArguments: traitTypeArguments
    )
  }
}

struct MIRTraitMethodCall {
  let receiver: MIRValue
  let receiverOwnership: MIROwnershipUse
  let traitName: String
  let traitTypeArguments: [Type]
  let methodName: String
  let methodIndex: Int
  let arguments: [MIRValue]
  let argumentOwnerships: [MIROwnershipUse]
  let type: Type
}

struct MIRLambda {
  let parameters: [Symbol]
  let captures: [CapturedVariable]
  let captureSources: [MIRPlace]
  let function: MIRFunction
  let type: Type
}

indirect enum MIRIntrinsic {
  case allocMemory(count: MIRValue, resultType: Type)
  case deallocMemory(ptr: MIRValue)
  case copyMemory(dest: MIRValue, source: MIRValue, count: MIRValue)
  case moveMemory(dest: MIRValue, source: MIRValue, count: MIRValue)
  case isUniqueMutable(value: MIRValue)
  case makeRef(ptr: MIRValue, owner: MIRValue, resultType: Type)
  case makeMutRef(ptr: MIRValue, owner: MIRValue, resultType: Type)
  case refCount(ref: MIRValue)
  case downgradeRef(value: MIRValue, resultType: Type)
  case downgradeMutRef(value: MIRValue, resultType: Type)
  case upgradeRef(value: MIRValue, resultType: Type)
  case upgradeMutRef(value: MIRValue, resultType: Type)
  case initMemory(ptr: MIRValue, value: MIRValue)
  case deinitMemory(ptr: MIRValue)
  case takeMemory(ptr: MIRValue, resultType: Type)
  case nullPtr(resultType: Type)
  case spawnThread(outHandle: MIRValue, outTid: MIRValue, closure: MIRValue, stackSize: MIRValue)
}

struct MIRSwitchCase {
  let value: MIRConstant
  let target: MIRBlockID
}

struct MIRExprResult {
  let type: Type
  let category: ValueCategory
  let operand: MIROperand?
  let place: MIRPlace?
}

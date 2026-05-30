import Foundation

struct MIRTypeResolver {
  private let function: MIRFunction
  private let context: CompilerContext
  private let localTypeByID: [MIRLocalID: Type]

  init(function: MIRFunction, context: CompilerContext) {
    self.function = function
    self.context = context
    self.localTypeByID = Dictionary(uniqueKeysWithValues: function.locals.map { ($0.id, $0.type) })
  }

  func type(of operand: MIROperand) -> Type? {
    switch operand {
    case .local(let local):
      return localTypeByID[local]
    case .constant(let constant):
      return type(of: constant)
    case .function(let symbol):
      return symbol.type
    }
  }

  func type(of constant: MIRConstant) -> Type {
    switch constant {
    case .integer(_, let type),
         .float(_, let type),
         .string(_, let type):
      return type
    case .boolean:
      return .bool
    case .void:
      return .void
    }
  }

  func type(of place: MIRPlace) -> Type? {
    switch place {
    case .local(let local):
      return localTypeByID[local]
    case .global(let defId):
      return context.getSymbolType(defId)
    case .field(let base, let field):
      return resolvedFieldType(base: base, field: field) ?? field.type
    case .enumPayload(let base, let caseName, let fieldName, let fieldIndex, let fieldType):
      return resolvedEnumPayloadType(base: base, caseName: caseName, fieldName: fieldName, fieldIndex: fieldIndex) ?? fieldType
    case .deref(_, let pointee),
         .pointerElement(_, let pointee):
      return pointee
    }
  }

  private func resolvedFieldType(base: MIRPlace, field: Symbol) -> Type? {
    guard let aggregateType = aggregateType(of: base) else { return nil }
    guard let fieldName = context.getName(field.defId) else { return nil }

    switch aggregateType {
    case .structure(let defId):
      return context.getStructMembers(defId)?.first(where: { $0.name == fieldName })?.type
    case .opaque(let defId):
      return context.getForeignStructFields(defId)?.first(where: { $0.name == fieldName })?.type
    default:
      return nil
    }
  }

  private func resolvedEnumPayloadType(
    base: MIRPlace,
    caseName: String,
    fieldName: String,
    fieldIndex: Int
  ) -> Type? {
    guard let aggregateType = aggregateType(of: base) else { return nil }
    guard case .enum(let defId) = aggregateType else { return nil }
    guard let enumCase = context.getEnumCases(defId)?.first(where: { $0.name == caseName }) else { return nil }

    if fieldIndex >= 0, fieldIndex < enumCase.parameters.count {
      let parameter = enumCase.parameters[fieldIndex]
      if parameter.name == fieldName || fieldName.isEmpty {
        return parameter.type
      }
    }

    return enumCase.parameters.first(where: { $0.name == fieldName })?.type
  }

  private func aggregateType(of place: MIRPlace) -> Type? {
    guard let placeType = type(of: place) else { return nil }
    return unwrapAggregateType(placeType)
  }

  private func unwrapAggregateType(_ type: Type) -> Type {
    switch type {
    case .reference(let inner),
         .mutableReference(let inner),
         .weakReference(let inner),
         .mutableWeakReference(let inner),
         .pointer(let inner),
         .mutablePointer(let inner):
      return unwrapAggregateType(inner)
    default:
      return type
    }
  }

  func type(of value: MIRValue) -> Type? {
    switch value {
    case .operand(let operand):
      return type(of: operand)
    case .placeRead(let place, _):
      return type(of: place)
    case .binary(let operation):
      return operation.type
    case .unary(let operation):
      return operation.type
    case .call(let call):
      return call.type
    case .aggregate(let aggregate):
      return aggregate.type
    case .enumCase(let construction):
      return construction.type
    case .enumTag:
      return .int
    case .traitObjectConversion(let conversion):
      return conversion.type
    case .traitMethodCall(let call):
      return call.type
    case .ref(let place, let kind, _):
      guard let pointee = type(of: place) else { return nil }
      switch kind {
      case .shared:
        return .reference(inner: pointee)
      case .mutable:
        return .mutableReference(inner: pointee)
      case .weak:
        return .weakReference(inner: pointee)
      case .mutableWeak:
        return .mutableWeakReference(inner: pointee)
      }
    case .pointer(let place):
      guard let element = type(of: place) else { return nil }
      return .pointer(element: element)
    case .cast(_, let type):
      return type
    case .intrinsic(let intrinsic):
      return type(of: intrinsic)
    case .lambda(let lambda):
      return lambda.type
    }
  }

  func type(of intrinsic: MIRIntrinsic) -> Type? {
    switch intrinsic {
    case .allocMemory(_, let resultType),
         .makeRef(_, _, let resultType),
         .makeMutRef(_, _, let resultType),
         .downgradeRef(_, let resultType),
         .downgradeMutRef(_, let resultType),
         .upgradeRef(_, let resultType),
         .upgradeMutRef(_, let resultType),
         .takeMemory(_, let resultType),
         .nullPtr(let resultType):
      return resultType
    case .isUniqueMutable:
      return .bool
    case .spawnThread:
      return .int32
    case .deallocMemory,
         .copyMemory,
         .moveMemory,
         .initMemory,
         .deinitMemory:
      return .void
    }
  }

}
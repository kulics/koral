import Foundation

struct MIRVerificationError: Error, CustomStringConvertible, LocalizedError {
  let message: String

  var description: String { message }
  var errorDescription: String? { message }
}

final class MIRVerifier {
  private let program: MIRProgram
  private var context: CompilerContext { program.context }
  private lazy var traitVTableKeys: Set<MIRTraitVTableKey> = Set(
    program.globals.compactMap { global in
      guard case .traitVTable(let vtable) = global else { return nil }
      return vtable.key
    }
  )

  init(program: MIRProgram) {
    self.program = program
  }

  func verify() throws {
    try verifyTraitVTableInventory()
    for global in program.globals {
      try verify(global)
    }
    for function in program.functions {
      try verify(function)
    }
  }

  private func verifyTraitVTableInventory() throws {
    let keys: [MIRTraitVTableKey] = program.globals.compactMap { global in
      guard case .traitVTable(let vtable) = global else { return nil }
      return vtable.key
    }
    if Set(keys).count != keys.count {
      throw MIRVerificationError(message: "MIR verification failed in trait vtable inventory: duplicate vtable key")
    }
  }

  private func verify(_ global: MIRGlobal) throws {
    switch global {
    case .traitVTable(let vtable):
      if vtable.traitName.isEmpty {
        throw MIRVerificationError(message: "MIR verification failed in trait vtable: empty trait name")
      }
      if context.containsGenericParameter(vtable.concreteType) {
        throw MIRVerificationError(message: "MIR verification failed in trait vtable \(vtable.traitName): unresolved concrete type")
      }
      for argument in vtable.traitTypeArguments where context.containsGenericParameter(argument) {
        throw MIRVerificationError(message: "MIR verification failed in trait vtable \(vtable.traitName): unresolved trait type argument")
      }
    default:
      break
    }
  }

  private func verify(_ function: MIRFunction) throws {
    guard !function.blocks.isEmpty else {
      try fail(function, "function has no basic blocks")
    }

    let blockIDs = Set(function.blocks.map(\.id))
    guard blockIDs.count == function.blocks.count else {
      try fail(function, "function has duplicate basic block IDs")
    }
    guard blockIDs.contains(function.entryBlock) else {
      try fail(function, "entry block \(function.entryBlock) is missing")
    }

    let localIDs = Set(function.locals.map(\.id))
    guard localIDs.count == function.locals.count else {
      try fail(function, "function has duplicate local IDs")
    }

    let parameterLocals = function.locals.filter { $0.storage == .parameter }
    guard parameterLocals.count == function.parameters.count else {
      try fail(function, "parameter local count does not match parameter count")
    }

    for (index, parameter) in function.parameters.enumerated() {
      guard index < parameterLocals.count else { break }
      if parameterLocals[index].type != parameter.type {
        try fail(function, "parameter local \(index) type does not match parameter type")
      }
    }

    if context.containsGenericParameter(function.identifier.type) {
      try fail(function, "generic function type reached MIR lowering")
    }

    for local in function.locals where context.containsGenericParameter(local.type) {
      try fail(function, "local \(local.id) \(local.name) has unresolved generic type \(context.getDebugName(local.type))")
    }

    for block in function.blocks {
      for statement in block.statements {
        try verifyStatement(statement, in: function, localIDs: localIDs)
      }
      try verifyTerminator(block.terminator, in: function, blockIDs: blockIDs, localIDs: localIDs)
    }
  }

  private func verifyStatement(
    _ statement: MIRStatement,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    switch statement {
    case .declare(let local):
      try verifyLocal(local, in: function, localIDs: localIDs)
    case .assign(let place, let value):
      try verifyPlace(place, in: function, localIDs: localIDs)
      try verifyValue(value, in: function, localIDs: localIDs)
    case .compoundAssign(let assignment):
      try verifyPlace(assignment.target, in: function, localIDs: localIDs)
      try verifyValue(assignment.value, in: function, localIDs: localIDs)
    case .drop(let place):
      try verifyPlace(place, in: function, localIDs: localIDs)
    case .retain(let value),
         .release(let value),
          .evaluate(let value):
      try verifyValue(value, in: function, localIDs: localIDs)
    case .scopeEnter, .scopeExit, .debugSource:
      break
    }
  }

  private func verifyTerminator(
    _ terminator: MIRTerminator,
    in function: MIRFunction,
    blockIDs: Set<MIRBlockID>,
    localIDs: Set<MIRLocalID>
  ) throws {
    switch terminator {
    case .goto(let target):
      try verifyTarget(target, in: function, blockIDs: blockIDs)
    case .branch(let condition, let thenBlock, let elseBlock):
      try verifyOperand(condition, in: function, localIDs: localIDs)
      try verifyTarget(thenBlock, in: function, blockIDs: blockIDs)
      try verifyTarget(elseBlock, in: function, blockIDs: blockIDs)
    case .switchValue(let operand, let cases, let defaultBlock):
      try verifyOperand(operand, in: function, localIDs: localIDs)
      for switchCase in cases {
        try verifyConstant(switchCase.value, in: function)
        try verifyTarget(switchCase.target, in: function, blockIDs: blockIDs)
      }
      if let defaultBlock {
        try verifyTarget(defaultBlock, in: function, blockIDs: blockIDs)
      }
    case .returnValue(let operand):
      if let operand {
        try verifyOperand(operand, in: function, localIDs: localIDs)
      }
    case .unreachable:
      break
    }
  }

  private func verifyPlace(
    _ place: MIRPlace,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    switch place {
    case .local(let local):
      try verifyLocal(local, in: function, localIDs: localIDs)
    case .global:
      break
    case .field(let base, let field):
      try verifyPlace(base, in: function, localIDs: localIDs)
      try verifyConcrete(field.type, in: function, description: "field place has unresolved generic type")
    case .enumPayload(let base, _, _, _, let fieldType):
      try verifyPlace(base, in: function, localIDs: localIDs)
      try verifyConcrete(fieldType, in: function, description: "enum payload place has unresolved generic type")
    case .deref(let base, let pointee),
         .pointerElement(let base, let pointee):
      try verifyValue(base, in: function, localIDs: localIDs)
      try verifyConcrete(pointee, in: function, description: "place projection has unresolved generic type")
    }
  }

  private func verifyValue(
    _ value: MIRValue,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    switch value {
    case .operand(let operand):
      try verifyOperand(operand, in: function, localIDs: localIDs)
    case .placeRead(let place, _):
      try verifyPlace(place, in: function, localIDs: localIDs)
    case .binary(let operation):
      try verifyOperand(operation.left, in: function, localIDs: localIDs)
      try verifyOperand(operation.right, in: function, localIDs: localIDs)
      try verifyConcrete(operation.type, in: function, description: "binary operation has unresolved generic type")
    case .unary(let operation):
      try verifyOperand(operation.operand, in: function, localIDs: localIDs)
      try verifyConcrete(operation.type, in: function, description: "unary operation has unresolved generic type")
    case .call(let call):
      try verifyOperand(call.callee, in: function, localIDs: localIDs)
      try verifyConcrete(call.type, in: function, description: "call result has unresolved generic type")
      if call.argumentOwnerships.count != call.arguments.count {
        try fail(function, "call argument ownership count does not match argument count")
      }
      for argument in call.arguments {
        try verifyValue(argument, in: function, localIDs: localIDs)
      }
    case .aggregate(let aggregate):
      try verifyConcrete(aggregate.type, in: function, description: "aggregate has unresolved generic type")
      for field in aggregate.fields {
        try verifyValue(field, in: function, localIDs: localIDs)
      }
    case .enumCase(let construction):
      try verifyConcrete(construction.type, in: function, description: "enum construction has unresolved generic type")
      for argument in construction.arguments {
        try verifyValue(argument, in: function, localIDs: localIDs)
      }
    case .enumTag(let tag):
      try verifyConcrete(tag.enumType, in: function, description: "enum tag has unresolved generic type")
      try verifyValue(tag.subject, in: function, localIDs: localIDs)
    case .traitObjectConversion(let conversion):
      try verifyTraitObjectConversion(conversion, in: function, localIDs: localIDs)
    case .traitMethodCall(let call):
      try verifyTraitMethodCall(call, in: function, localIDs: localIDs)
    case .ref(let place, _, _),
         .pointer(let place):
      try verifyPlace(place, in: function, localIDs: localIDs)
    case .cast(let operand, let type):
      try verifyOperand(operand, in: function, localIDs: localIDs)
      try verifyConcrete(type, in: function, description: "cast target has unresolved generic type")
    case .intrinsic(let intrinsic):
      try verifyIntrinsic(intrinsic, in: function)
    case .lambda(let lambda):
      try verifyLambda(lambda, in: function, localIDs: localIDs)
    }
  }

  private func verifyOperand(
    _ operand: MIROperand,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    switch operand {
    case .local(let local):
      try verifyLocal(local, in: function, localIDs: localIDs)
    case .constant(let constant):
      try verifyConstant(constant, in: function)
    case .function(let symbol):
      try verifyConcrete(symbol.type, in: function, description: "function operand has unresolved generic type")
    }
  }

  private func verifyConstant(_ constant: MIRConstant, in function: MIRFunction) throws {
    switch constant {
    case .integer(_, let type),
         .float(_, let type),
         .string(_, let type):
      try verifyConcrete(type, in: function, description: "constant has unresolved generic type")
    case .boolean, .void:
      break
    }
  }

  private func verifyIntrinsic(_ intrinsic: MIRIntrinsic, in function: MIRFunction) throws {
    switch intrinsic {
    case .allocMemory(let count, let resultType):
      try verifyValue(count, in: function, localIDs: Set(function.locals.map(\.id)))
      try verifyConcrete(resultType, in: function, description: "intrinsic has unresolved generic type")
    case .deallocMemory(let ptr),
         .deinitMemory(let ptr),
         .takeMemory(let ptr, _):
      try verifyValue(ptr, in: function, localIDs: Set(function.locals.map(\.id)))
    case .copyMemory(let dest, let source, let count),
         .moveMemory(let dest, let source, let count):
      let localIDs = Set(function.locals.map(\.id))
      try verifyValue(dest, in: function, localIDs: localIDs)
      try verifyValue(source, in: function, localIDs: localIDs)
      try verifyValue(count, in: function, localIDs: localIDs)
    case .isUniqueMutable(let value),
          .refCount(let value),
         .downgradeRef(let value, _),
         .downgradeMutRef(let value, _),
         .upgradeRef(let value, _),
         .upgradeMutRef(let value, _):
      try verifyValue(value, in: function, localIDs: Set(function.locals.map(\.id)))
    case .makeRef(let ptr, let owner, _),
         .makeMutRef(let ptr, let owner, _),
         .initMemory(let ptr, let owner):
      let localIDs = Set(function.locals.map(\.id))
      try verifyValue(ptr, in: function, localIDs: localIDs)
      try verifyValue(owner, in: function, localIDs: localIDs)
    case .nullPtr(let resultType):
      try verifyConcrete(resultType, in: function, description: "intrinsic has unresolved generic type")
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      let localIDs = Set(function.locals.map(\.id))
      try verifyValue(outHandle, in: function, localIDs: localIDs)
      try verifyValue(outTid, in: function, localIDs: localIDs)
      try verifyValue(closure, in: function, localIDs: localIDs)
      try verifyValue(stackSize, in: function, localIDs: localIDs)
    }
  }

  private func verifyLambda(
    _ lambda: MIRLambda,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    try verifyConcrete(lambda.type, in: function, description: "lambda has unresolved generic type")
    guard lambda.captureSources.count == lambda.captures.count else {
      try fail(function, "lambda capture source count mismatch")
    }
    for source in lambda.captureSources {
      try verifyPlace(source, in: function, localIDs: localIDs)
    }
    try verify(lambda.function)
  }

  private func verifyLocal(
    _ local: MIRLocalID,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    guard localIDs.contains(local) else {
      try fail(function, "use of unknown local \(local)")
    }
  }

  private func verifyConcrete(_ type: Type, in function: MIRFunction, description: String) throws {
    if context.containsGenericParameter(type) {
      try fail(function, description)
    }
  }

  private func verifyTraitObjectConversion(
    _ conversion: MIRTraitObjectConversion,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    let typeResolver = MIRTypeResolver(function: function, context: context)
    if conversion.traitName.isEmpty {
      try fail(function, "trait object conversion has empty trait name")
    }
    try verifyConcrete(conversion.type, in: function, description: "trait object conversion has unresolved generic type")
    try verifyConcrete(conversion.concreteType, in: function, description: "trait object conversion concrete type has unresolved generic type")
    for argument in conversion.traitTypeArguments where context.containsGenericParameter(argument) {
      try fail(function, "trait object conversion has unresolved trait type argument \(context.getDebugName(argument))")
    }
    guard traitVTableKeys.contains(conversion.vtableKey) else {
      try fail(function, "trait object conversion has no matching vtable \(render(conversion.vtableKey))")
    }
    guard let innerType = typeResolver.type(of: conversion.inner) else {
      try fail(function, "trait object conversion inner value has unknown type")
    }
    guard let referencedConcreteType = referencedType(innerType) else {
      try fail(function, "trait object conversion inner value is not a reference type: \(context.getDebugName(innerType))")
    }
    if referencedConcreteType != conversion.concreteType {
      try fail(
        function,
        "trait object conversion concrete type \(context.getDebugName(conversion.concreteType)) does not match inner reference type \(context.getDebugName(referencedConcreteType))"
      )
    }
    guard let target = traitObjectReferenceInfo(conversion.type) else {
      try fail(function, "trait object conversion result is not a trait object reference: \(context.getDebugName(conversion.type))")
    }
    if target.traitName != conversion.traitName || target.typeArguments != conversion.traitTypeArguments {
      try fail(function, "trait object conversion result type does not match conversion trait metadata")
    }
    try verifyValue(conversion.inner, in: function, localIDs: localIDs)
  }

  private func verifyTraitMethodCall(
    _ call: MIRTraitMethodCall,
    in function: MIRFunction,
    localIDs: Set<MIRLocalID>
  ) throws {
    let typeResolver = MIRTypeResolver(function: function, context: context)
    if call.traitName.isEmpty {
      try fail(function, "trait method call has empty trait name")
    }
    if call.methodName.isEmpty {
      try fail(function, "trait method call has empty method name")
    }
    if call.methodIndex < 0 {
      try fail(function, "trait method call has negative method index")
    }
    if call.argumentOwnerships.count != call.arguments.count {
      try fail(function, "trait method call argument ownership count does not match argument count")
    }
    try verifyConcrete(call.type, in: function, description: "trait method call has unresolved generic type")
    for argument in call.traitTypeArguments where context.containsGenericParameter(argument) {
      try fail(function, "trait method call has unresolved trait type argument \(context.getDebugName(argument))")
    }
    guard let receiverType = typeResolver.type(of: call.receiver) else {
      try fail(function, "trait method call receiver has unknown type")
    }
    guard let receiver = traitObjectReferenceInfo(receiverType) else {
      try fail(function, "trait method call receiver is not a trait object reference: \(context.getDebugName(receiverType))")
    }
    if receiver.traitName != call.traitName || receiver.typeArguments != call.traitTypeArguments {
      try fail(function, "trait method call receiver type does not match call trait metadata")
    }
    for (index, argument) in call.arguments.enumerated() {
      if typeResolver.type(of: argument) == nil {
        try fail(function, "trait method call argument \(index) has unknown type")
      }
    }
    try verifyValue(call.receiver, in: function, localIDs: localIDs)
    for argument in call.arguments { try verifyValue(argument, in: function, localIDs: localIDs) }
  }

  private func referencedType(_ type: Type) -> Type? {
    switch type {
    case .reference(let inner),
         .mutableReference(let inner):
      return inner
    default:
      return nil
    }
  }

  private func traitObjectReferenceInfo(_ type: Type) -> (traitName: String, typeArguments: [Type])? {
    switch type {
    case .traitObject(let traitName, let typeArguments):
      return (traitName, typeArguments)
    case .reference(let inner),
         .mutableReference(let inner):
      if case .traitObject(let traitName, let typeArguments) = inner {
        return (traitName, typeArguments)
      }
      return nil
    default:
      return nil
    }
  }

  private func render(_ key: MIRTraitVTableKey) -> String {
    let renderedArguments = key.traitTypeArguments.map { context.getDebugName($0) }.joined(separator: ", ")
    let renderedTrait = renderedArguments.isEmpty ? key.traitName : "\(key.traitName)<\(renderedArguments)>"
    return "\(renderedTrait) for \(context.getDebugName(key.concreteType))"
  }

  private func verifyTarget(
    _ target: MIRBlockID,
    in function: MIRFunction,
    blockIDs: Set<MIRBlockID>
  ) throws {
    guard blockIDs.contains(target) else {
      try fail(function, "terminator targets missing block \(target)")
    }
  }

  private func fail(_ function: MIRFunction, _ message: String) throws -> Never {
    let name = context.getQualifiedName(function.identifier.defId)
      ?? context.getName(function.identifier.defId)
      ?? "def#\(function.identifier.defId.id)"
    throw MIRVerificationError(message: "MIR verification failed in \(name): \(message)")
  }
}

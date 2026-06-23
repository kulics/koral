import Foundation

final class MIRReferenceAllocationPromoter {
  private let program: MIRProgram
  private let context: CompilerContext
  private let functionParameterTypesByDefId: [DefId: [Type]]
  private let functionParameterTypesByName: [String: [Type]]

  init(program: MIRProgram) {
    self.program = program
    self.context = program.context
    self.functionParameterTypesByDefId = Dictionary(
      uniqueKeysWithValues: program.functions.map { function in
        (function.identifier.defId, function.parameters.map(\.type))
      }
    )
    var parameterTypesByName: [String: [Type]] = [:]
    for function in program.functions {
      let parameterTypes = function.parameters.map(\.type)
      if let qualifiedName = context.getQualifiedName(function.identifier.defId) {
        parameterTypesByName[qualifiedName] = parameterTypes
      }
      if let name = context.getName(function.identifier.defId) {
        parameterTypesByName[name] = parameterTypes
      }
    }
    self.functionParameterTypesByName = parameterTypesByName
  }

  func promote() -> MIRProgram {
    let functions = program.functions.map { function in
      return MIRReferenceAllocationFunctionPromoter(
        function: function,
        globals: program.globals,
        functionParameterTypesByDefId: functionParameterTypesByDefId,
        functionParameterTypesByName: functionParameterTypesByName,
        context: context
      ).promote()
    }

    return MIRProgram(
      globals: program.globals,
      functions: functions,
      context: context,
      staticMethodLookup: program.staticMethodLookup,
      traits: program.traits,
      receiverMethodDispatch: program.receiverMethodDispatch
    )
  }
}

private final class MIRReferenceAllocationFunctionPromoter {
  private let function: MIRFunction
  private let globals: [MIRGlobal]
  private let functionParameterTypesByDefId: [DefId: [Type]]
  private let functionParameterTypesByName: [String: [Type]]
  private let context: CompilerContext
  private let resolver: MIRTypeResolver

  init(
    function: MIRFunction,
    globals: [MIRGlobal],
    functionParameterTypesByDefId: [DefId: [Type]],
    functionParameterTypesByName: [String: [Type]],
    context: CompilerContext
  ) {
    self.function = function
    self.globals = globals
    self.functionParameterTypesByDefId = functionParameterTypesByDefId
    self.functionParameterTypesByName = functionParameterTypesByName
    self.context = context
    self.resolver = MIRTypeResolver(function: function, context: context)
  }

  func promote() -> MIRFunction {
    var updated = function
    updated.blocks = function.blocks.map { block in
      var newBlock = block
      newBlock.statements = block.statements.map(promoteStatement)
      newBlock.terminator = promoteTerminator(block.terminator)
      return newBlock
    }
    return updated
  }

  private func promoteStatement(_ statement: MIRStatement) -> MIRStatement {
    switch statement {
    case .assign(let place, let value):
      return .assign(place, promoteValue(value, destinationType: resolver.type(of: place)))
    case .compoundAssign(let assignment):
      return .compoundAssign(
        MIRCompoundAssignment(
          target: assignment.target,
          operatorKind: assignment.operatorKind,
          value: promoteValue(assignment.value, destinationType: resolver.type(of: assignment.target))
        )
      )
    case .evaluate(let value):
      return .evaluate(promoteValue(value, destinationType: nil))
    case .retain(let value):
      return .retain(promoteValue(value, destinationType: nil))
    case .release(let value):
      return .release(promoteValue(value, destinationType: nil))
    case .declare, .drop, .scopeEnter, .scopeExit, .debugSource:
      return statement
    }
  }

  private func promoteTerminator(_ terminator: MIRTerminator) -> MIRTerminator {
    switch terminator {
    case .returnValue(let operand):
      return .returnValue(operand)
    case .goto(let block):
      return .goto(block)
    case .branch(let condition, let thenBlock, let elseBlock):
      return .branch(condition: condition, thenBlock: thenBlock, elseBlock: elseBlock)
    case .switchValue(let operand, let cases, let defaultBlock):
      return .switchValue(operand, cases: cases, defaultBlock: defaultBlock)
    case .unreachable:
      return .unreachable
    }
  }

  private func promoteValue(_ value: MIRValue, destinationType: Type?) -> MIRValue {
    let recursivelyPromoted: MIRValue

    switch value {
    case .call(let call):
      recursivelyPromoted = .call(
        MIRCall(
          callee: call.callee,
          arguments: promoteCallArguments(call.arguments, callee: call.callee),
          argumentOwnerships: call.argumentOwnerships,
          type: call.type
        )
      )
    case .intrinsic(let intrinsic):
      recursivelyPromoted = .intrinsic(promoteIntrinsic(intrinsic))
    case .aggregate(let aggregate):
      recursivelyPromoted = .aggregate(
        MIRAggregate(
          type: aggregate.type,
          fields: aggregate.fields.map { promoteValue($0, destinationType: nil) }
        )
      )
    case .enumCase(let construction):
      recursivelyPromoted = .enumCase(
        MIREnumConstruction(
          type: construction.type,
          caseName: construction.caseName,
          arguments: construction.arguments.map { promoteValue($0, destinationType: nil) }
        )
      )
    case .traitObjectConversion(let conversion):
      recursivelyPromoted = .traitObjectConversion(
        MIRTraitObjectConversion(
          inner: promoteValue(conversion.inner, destinationType: nil),
          sourceOwnership: conversion.sourceOwnership,
          traitName: conversion.traitName,
          traitTypeArguments: conversion.traitTypeArguments,
          concreteType: conversion.concreteType,
          type: conversion.type
        )
      )
    case .traitMethodCall(let call):
      recursivelyPromoted = .traitMethodCall(
        MIRTraitMethodCall(
          receiver: promoteValue(call.receiver, destinationType: nil),
          receiverOwnership: call.receiverOwnership,
          traitName: call.traitName,
          traitTypeArguments: call.traitTypeArguments,
          methodName: call.methodName,
          methodIndex: call.methodIndex,
          arguments: call.arguments.map { promoteValue($0, destinationType: nil) },
          argumentOwnerships: call.argumentOwnerships,
          type: call.type
        )
      )
    case .enumTag(let tag):
      recursivelyPromoted = .enumTag(
        MIREnumTag(
          subject: promoteValue(tag.subject, destinationType: nil),
          enumType: tag.enumType
        )
      )
    case .lambda, .binary, .unary, .operand, .placeRead, .ref, .pointer, .cast:
      recursivelyPromoted = value
    }

    guard let destinationType, typeRequiresOwnedReferenceStorage(destinationType) else {
      return recursivelyPromoted
    }
    return promoteDirectReferences(in: recursivelyPromoted)
  }

  private func promoteCallArguments(_ arguments: [MIRValue], callee: MIROperand) -> [MIRValue] {
    let parameterTypes: [Type]
    switch callee {
    case .function(let symbol):
      if let exactParameterTypes = globalFunctionParameterTypes(for: symbol) {
        parameterTypes = exactParameterTypes
      } else if case .function(let parameters, _) = symbol.type {
        parameterTypes = parameters.map(\.type)
      } else {
        parameterTypes = []
      }
    default:
      parameterTypes = []
    }

    return arguments.enumerated().map { index, argument in
      let destinationType = index < parameterTypes.count ? parameterTypes[index] : nil
      return promoteValue(argument, destinationType: destinationType)
    }
  }

  private func globalFunctionParameterTypes(for symbol: Symbol) -> [Type]? {
    if let exactParameterTypes = functionParameterTypesByDefId[symbol.defId] {
      return exactParameterTypes
    }
    if let qualifiedName = context.getQualifiedName(symbol.defId),
       let exactParameterTypes = functionParameterTypesByName[qualifiedName] {
      return exactParameterTypes
    }
    if let name = context.getName(symbol.defId),
       let exactParameterTypes = functionParameterTypesByName[name] {
      return exactParameterTypes
    }
    for global in globals {
      switch global {
      case .function(let identifier, let parameters, _)
      where identifier.defId == symbol.defId:
        return parameters.map { $0.type }
      case .foreignFunction(let identifier, let parameters)
      where identifier.defId == symbol.defId:
        return parameters.map { $0.type }
      default:
        continue
      }
    }
    return nil
  }

  private func promoteIntrinsic(_ intrinsic: MIRIntrinsic) -> MIRIntrinsic {
    switch intrinsic {
    case .allocMemory(let count, let resultType):
      return .allocMemory(count: promoteValue(count, destinationType: nil), resultType: resultType)
    case .deallocMemory(let ptr):
      return .deallocMemory(ptr: promoteValue(ptr, destinationType: nil))
    case .copyMemory(let dest, let source, let count):
      return .copyMemory(
        dest: promoteValue(dest, destinationType: nil),
        source: promoteValue(source, destinationType: nil),
        count: promoteValue(count, destinationType: nil)
      )
    case .moveMemory(let dest, let source, let count):
      return .moveMemory(
        dest: promoteValue(dest, destinationType: nil),
        source: promoteValue(source, destinationType: nil),
        count: promoteValue(count, destinationType: nil)
      )
    case .isUniqueMutable(let value):
      return .isUniqueMutable(value: promoteValue(value, destinationType: nil))
    case .refCount(let value):
      return .refCount(ref: promoteValue(value, destinationType: nil))
    case .makeRef(let ptr, let owner, let resultType):
      return .makeRef(
        ptr: promoteValue(ptr, destinationType: nil),
        owner: promoteValue(owner, destinationType: resultType),
        resultType: resultType
      )
    case .makeMutRef(let ptr, let owner, let resultType):
      return .makeMutRef(
        ptr: promoteValue(ptr, destinationType: nil),
        owner: promoteValue(owner, destinationType: resultType),
        resultType: resultType
      )
    case .downgradeRef(let value, let resultType):
      return .downgradeRef(value: promoteValue(value, destinationType: nil), resultType: resultType)
    case .downgradeMutRef(let value, let resultType):
      return .downgradeMutRef(value: promoteValue(value, destinationType: nil), resultType: resultType)
    case .upgradeRef(let value, let resultType):
      return .upgradeRef(value: promoteValue(value, destinationType: nil), resultType: resultType)
    case .upgradeMutRef(let value, let resultType):
      return .upgradeMutRef(value: promoteValue(value, destinationType: nil), resultType: resultType)
    case .initMemory(let ptr, let value):
      return .initMemory(
        ptr: promoteValue(ptr, destinationType: nil),
        value: promoteValue(value, destinationType: resolver.type(of: value))
      )
    case .deinitMemory(let ptr):
      return .deinitMemory(ptr: promoteValue(ptr, destinationType: nil))
    case .takeMemory(let ptr, let resultType):
      return .takeMemory(ptr: promoteValue(ptr, destinationType: nil), resultType: resultType)
    case .nullPtr(let resultType):
      return .nullPtr(resultType: resultType)
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      return .spawnThread(
        outHandle: promoteValue(outHandle, destinationType: nil),
        outTid: promoteValue(outTid, destinationType: nil),
        closure: promoteValue(closure, destinationType: resolver.type(of: closure)),
        stackSize: promoteValue(stackSize, destinationType: nil)
      )
    }
  }

  private func promoteDirectReferences(in value: MIRValue) -> MIRValue {
    switch value {
    case .ref(let place, let kind, .stackBorrow):
      return .ref(place, kind: kind, allocation: .heapOwned)
    case .call(let call):
      return .call(
        MIRCall(
          callee: call.callee,
          arguments: call.arguments.map(promoteDirectReferences),
          argumentOwnerships: call.argumentOwnerships,
          type: call.type
        )
      )
    case .aggregate(let aggregate):
      return .aggregate(
        MIRAggregate(
          type: aggregate.type,
          fields: aggregate.fields.map(promoteDirectReferences)
        )
      )
    case .enumCase(let construction):
      return .enumCase(
        MIREnumConstruction(
          type: construction.type,
          caseName: construction.caseName,
          arguments: construction.arguments.map(promoteDirectReferences)
        )
      )
    case .traitObjectConversion(let conversion):
      return .traitObjectConversion(
        MIRTraitObjectConversion(
          inner: promoteDirectReferences(in: conversion.inner),
          sourceOwnership: conversion.sourceOwnership,
          traitName: conversion.traitName,
          traitTypeArguments: conversion.traitTypeArguments,
          concreteType: conversion.concreteType,
          type: conversion.type
        )
      )
    case .traitMethodCall(let call):
      return .traitMethodCall(
        MIRTraitMethodCall(
          receiver: promoteDirectReferences(in: call.receiver),
          receiverOwnership: call.receiverOwnership,
          traitName: call.traitName,
          traitTypeArguments: call.traitTypeArguments,
          methodName: call.methodName,
          methodIndex: call.methodIndex,
          arguments: call.arguments.map(promoteDirectReferences),
          argumentOwnerships: call.argumentOwnerships,
          type: call.type
        )
      )
    case .enumTag(let tag):
      return .enumTag(
        MIREnumTag(
          subject: promoteDirectReferences(in: tag.subject),
          enumType: tag.enumType
        )
      )
    case .intrinsic(let intrinsic):
      return .intrinsic(promoteDirectReferences(in: intrinsic))
    case .lambda, .binary, .unary, .operand, .placeRead, .ref, .pointer, .cast:
      return value
    }
  }

  private func promoteDirectReferences(in intrinsic: MIRIntrinsic) -> MIRIntrinsic {
    switch intrinsic {
    case .allocMemory(let count, let resultType):
      return .allocMemory(count: promoteDirectReferences(in: count), resultType: resultType)
    case .deallocMemory(let ptr):
      return .deallocMemory(ptr: promoteDirectReferences(in: ptr))
    case .copyMemory(let dest, let source, let count):
      return .copyMemory(
        dest: promoteDirectReferences(in: dest),
        source: promoteDirectReferences(in: source),
        count: promoteDirectReferences(in: count)
      )
    case .moveMemory(let dest, let source, let count):
      return .moveMemory(
        dest: promoteDirectReferences(in: dest),
        source: promoteDirectReferences(in: source),
        count: promoteDirectReferences(in: count)
      )
    case .isUniqueMutable(let value):
      return .isUniqueMutable(value: promoteDirectReferences(in: value))
    case .refCount(let value):
      return .refCount(ref: promoteDirectReferences(in: value))
    case .makeRef(let ptr, let owner, let resultType):
      return .makeRef(
        ptr: promoteDirectReferences(in: ptr),
        owner: promoteDirectReferences(in: owner),
        resultType: resultType
      )
    case .makeMutRef(let ptr, let owner, let resultType):
      return .makeMutRef(
        ptr: promoteDirectReferences(in: ptr),
        owner: promoteDirectReferences(in: owner),
        resultType: resultType
      )
    case .downgradeRef(let value, let resultType):
      return .downgradeRef(value: promoteDirectReferences(in: value), resultType: resultType)
    case .downgradeMutRef(let value, let resultType):
      return .downgradeMutRef(value: promoteDirectReferences(in: value), resultType: resultType)
    case .upgradeRef(let value, let resultType):
      return .upgradeRef(value: promoteDirectReferences(in: value), resultType: resultType)
    case .upgradeMutRef(let value, let resultType):
      return .upgradeMutRef(value: promoteDirectReferences(in: value), resultType: resultType)
    case .initMemory(let ptr, let value):
      return .initMemory(
        ptr: promoteDirectReferences(in: ptr),
        value: promoteDirectReferences(in: value)
      )
    case .deinitMemory(let ptr):
      return .deinitMemory(ptr: promoteDirectReferences(in: ptr))
    case .takeMemory(let ptr, let resultType):
      return .takeMemory(ptr: promoteDirectReferences(in: ptr), resultType: resultType)
    case .nullPtr(let resultType):
      return .nullPtr(resultType: resultType)
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      return .spawnThread(
        outHandle: promoteDirectReferences(in: outHandle),
        outTid: promoteDirectReferences(in: outTid),
        closure: promoteDirectReferences(in: closure),
        stackSize: promoteDirectReferences(in: stackSize)
      )
    }
  }

  private func typeRequiresOwnedReferenceStorage(_ type: Type) -> Bool {
    switch type {
    case .reference, .mutableReference, .weakReference, .mutableWeakReference, .function, .traitObject:
      return true
    case .borrowedReference, .mutableBorrowedReference:
      return false
    case .structure(let defId):
      return context.getStructMembers(defId)?.contains { typeRequiresOwnedReferenceStorage($0.type) } ?? false
    case .enum(let defId):
      return context.getEnumCases(defId)?.contains { enumCase in
        enumCase.parameters.contains { typeRequiresOwnedReferenceStorage($0.type) }
      } ?? false
    case .genericStruct(_, let args), .genericEnum(_, let args):
      return args.contains(where: typeRequiresOwnedReferenceStorage)
    default:
      return false
    }
  }
}

import Foundation

final class MIRReferenceAllocationPromoter {
  private let program: MIRProgram
  private let context: CompilerContext

  init(program: MIRProgram) {
    self.program = program
    self.context = program.context
  }

  func promote() -> MIRProgram {
    var summaries: [UInt64: MIRReferenceParameterSummary] = [:]
    var changed = true

    while changed {
      changed = false
      for function in program.functions {
        let analysis = MIRReferenceEscapeAnalyzer(
          function: function,
          context: context,
          escapingParameterSummaries: summaries
        ).analyze()
        let key = function.identifier.defId.id
        if summaries[key] != analysis.parameterSummary {
          summaries[key] = analysis.parameterSummary
          changed = true
        }
      }
    }

    let functions = program.functions.map { function in
      let analysis = MIRReferenceEscapeAnalyzer(
        function: function,
        context: context,
        escapingParameterSummaries: summaries
      ).analyze()
      return MIRReferenceAllocationFunctionPromoter(
        function: function,
        escapingLocals: analysis.escapingLocals,
        context: context,
        escapingParameterSummaries: summaries
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

private struct MIRReferenceEscapeAnalysis {
  let escapingLocals: Set<MIRLocalID>
  let parameterSummary: MIRReferenceParameterSummary
}

private struct MIRReferenceParameterSummary: Equatable {
  var storedParameterIndices: Set<Int> = []
  var returnParameterIndices: Set<Int> = []
}

private final class MIRReferenceEscapeAnalyzer {
  private let function: MIRFunction
  private let context: CompilerContext
  private let escapingParameterSummaries: [UInt64: MIRReferenceParameterSummary]
  private let resolver: MIRTypeResolver
  private let localTypeByID: [MIRLocalID: Type]
  private let parameterIndexByLocalID: [MIRLocalID: Int]
  private var dependenciesByLocalID: [MIRLocalID: Set<MIRLocalID>] = [:]
  private var storedEscapingLocals: Set<MIRLocalID> = []
  private var returnEscapingLocals: Set<MIRLocalID> = []

  init(
    function: MIRFunction,
    context: CompilerContext,
    escapingParameterSummaries: [UInt64: MIRReferenceParameterSummary]
  ) {
    self.function = function
    self.context = context
    self.escapingParameterSummaries = escapingParameterSummaries
    self.resolver = MIRTypeResolver(function: function, context: context)
    self.localTypeByID = Dictionary(uniqueKeysWithValues: function.locals.map { ($0.id, $0.type) })

    var parameterMap: [MIRLocalID: Int] = [:]
    var parameterIndex = 0
    for local in function.locals where local.storage == .parameter {
      parameterMap[local.id] = parameterIndex
      parameterIndex += 1
    }
    self.parameterIndexByLocalID = parameterMap
  }

  func analyze() -> MIRReferenceEscapeAnalysis {
    collectDependenciesAndEscapes()
    propagateEscapesThroughDependencies()

    var storedParameters: Set<Int> = []
    for local in storedEscapingLocals {
      if let parameterIndex = parameterIndexByLocalID[local] {
        storedParameters.insert(parameterIndex)
      }
    }

    var returnParameters: Set<Int> = []
    for local in returnEscapingLocals {
      if let parameterIndex = parameterIndexByLocalID[local] {
        returnParameters.insert(parameterIndex)
      }
    }

    return MIRReferenceEscapeAnalysis(
      escapingLocals: storedEscapingLocals.union(returnEscapingLocals),
      parameterSummary: MIRReferenceParameterSummary(
        storedParameterIndices: storedParameters,
        returnParameterIndices: returnParameters
      )
    )
  }

  private func collectDependenciesAndEscapes() {
    for block in function.blocks {
      for statement in block.statements {
        switch statement {
        case .assign(let place, let value):
          if case .local(let local) = place {
            if typeContainsEscapingReferences(localTypeByID[local] ?? .void) {
              dependenciesByLocalID[local, default: []].formUnion(referenceDependencies(in: value))
            }
          } else {
            markStoredEscapingReferences(in: value)
          }
          markStoredCallArguments(in: value)
        case .compoundAssign(let assignment):
          if !isLocalPlace(assignment.target) {
            markStoredEscapingReferences(in: assignment.value)
          }
          markStoredCallArguments(in: assignment.value)
        case .evaluate(let value), .retain(let value), .release(let value):
          markStoredCallArguments(in: value)
        case .declare, .drop, .scopeEnter, .scopeExit, .debugSource:
          break
        }
      }

      switch block.terminator {
      case .returnValue(let operand):
        if let operand, typeContainsEscapingReferences(function.returnType) {
          markReturnEscapingReferences(in: .operand(operand))
        }
      case .goto, .branch, .switchValue, .unreachable:
        break
      }
    }
  }

  private func propagateEscapesThroughDependencies() {
    var changed = true
    while changed {
      changed = false
      for local in Array(storedEscapingLocals) {
        for dependency in dependenciesByLocalID[local] ?? [] {
          if storedEscapingLocals.insert(dependency).inserted {
            changed = true
          }
        }
      }
      for local in Array(returnEscapingLocals) {
        for dependency in dependenciesByLocalID[local] ?? [] {
          if returnEscapingLocals.insert(dependency).inserted {
            changed = true
          }
        }
      }
    }
  }

  private func markStoredEscapingReferences(in value: MIRValue) {
    storedEscapingLocals.formUnion(referenceDependencies(in: value))
  }

  private func markReturnEscapingReferences(in value: MIRValue) {
    returnEscapingLocals.formUnion(referenceDependencies(in: value))
  }

  private func markStoredCallArguments(in value: MIRValue) {
    switch value {
    case .call(let call):
      markStoredArguments(for: call.callee, arguments: call.arguments)
      for argument in call.arguments {
        markStoredCallArguments(in: argument)
      }
    case .intrinsic(let intrinsic):
      markStoredIntrinsicArguments(intrinsic)
      for nested in intrinsicValues(intrinsic) {
        markStoredCallArguments(in: nested)
      }
    case .aggregate(let aggregate):
      for field in aggregate.fields { markStoredCallArguments(in: field) }
    case .enumCase(let construction):
      for argument in construction.arguments { markStoredCallArguments(in: argument) }
    case .traitObjectConversion(let conversion):
      markStoredCallArguments(in: conversion.inner)
    case .traitMethodCall(let call):
      markStoredCallArguments(in: call.receiver)
      for argument in call.arguments { markStoredCallArguments(in: argument) }
    case .enumTag(let tag):
      markStoredCallArguments(in: tag.subject)
    case .lambda:
      break
    case .binary, .unary, .operand, .placeRead, .ref, .pointer, .cast:
      break
    }
  }

  private func markStoredArguments(for callee: MIROperand, arguments: [MIRValue]) {
    guard case .function(let symbol) = callee else { return }
    let storedParameters = escapingParameterSummaries[symbol.defId.id]?.storedParameterIndices ?? []
    guard !storedParameters.isEmpty else { return }

    for parameterIndex in storedParameters where parameterIndex < arguments.count {
      markStoredEscapingReferences(in: arguments[parameterIndex])
    }
  }

  private func markStoredIntrinsicArguments(_ intrinsic: MIRIntrinsic) {
    switch intrinsic {
    case .initMemory(_, let value):
      markStoredEscapingReferences(in: value)
    case .spawnThread(_, _, let closure, _):
      markStoredEscapingReferences(in: closure)
    case .allocMemory,
         .deallocMemory,
         .copyMemory,
         .moveMemory,
         .isUniqueMutable,
          .refCount,
         .makeRef,
         .makeMutRef,
         .downgradeRef,
         .downgradeMutRef,
         .upgradeRef,
         .upgradeMutRef,
         .deinitMemory,
         .takeMemory,
         .nullPtr:
      break
    }
  }

  private func referenceDependencies(in value: MIRValue) -> Set<MIRLocalID> {
    guard typeContainsEscapingReferences(resolver.type(of: value) ?? .void) else {
      if case .lambda(let lambda) = value {
        return lambdaCaptureDependencies(lambda)
      }
      return []
    }

    switch value {
    case .operand(.local(let local)):
      return [local]
    case .operand:
      return []
    case .placeRead(let place, _):
      return rootLocal(of: place).map { [$0] } ?? []
    case .aggregate(let aggregate):
      return aggregate.fields.reduce(into: Set<MIRLocalID>()) { result, field in
        result.formUnion(referenceDependencies(in: field))
      }
    case .enumCase(let construction):
      return construction.arguments.reduce(into: Set<MIRLocalID>()) { result, argument in
        result.formUnion(referenceDependencies(in: argument))
      }
    case .traitObjectConversion(let conversion):
      return referenceDependencies(in: conversion.inner)
    case .traitMethodCall(let call):
      var result = referenceDependencies(in: call.receiver)
      for argument in call.arguments { result.formUnion(referenceDependencies(in: argument)) }
      return result
    case .lambda(let lambda):
      return lambdaCaptureDependencies(lambda)
    case .cast(let operand, _):
      return referenceDependencies(in: .operand(operand))
    case .intrinsic(let intrinsic):
      return intrinsicValues(intrinsic).reduce(into: Set<MIRLocalID>()) { result, nested in
        result.formUnion(referenceDependencies(in: nested))
      }
    case .enumTag(let tag):
      return referenceDependencies(in: tag.subject)
    case .call(let call):
      return returnParameterDependencies(for: call)
    case .binary, .unary, .ref, .pointer:
      return []
    }
  }

  private func returnParameterDependencies(for call: MIRCall) -> Set<MIRLocalID> {
    guard case .function(let symbol) = call.callee else { return [] }
    let returnParameters = escapingParameterSummaries[symbol.defId.id]?.returnParameterIndices ?? []
    guard !returnParameters.isEmpty else { return [] }
    return returnParameters.reduce(into: Set<MIRLocalID>()) { result, parameterIndex in
      guard parameterIndex < call.arguments.count else { return }
      result.formUnion(referenceDependencies(in: call.arguments[parameterIndex]))
    }
  }

  private func lambdaCaptureDependencies(_ lambda: MIRLambda) -> Set<MIRLocalID> {
    lambda.captureSources.reduce(into: Set<MIRLocalID>()) { result, place in
      if let local = rootLocal(of: place), typeContainsEscapingReferences(localTypeByID[local] ?? .void) {
        result.insert(local)
      }
    }
  }

  private func typeContainsEscapingReferences(_ type: Type) -> Bool {
    switch type {
    case .reference, .mutableReference, .weakReference, .mutableWeakReference, .function, .traitObject:
      return true
    case .structure(let defId):
      return context.getStructMembers(defId)?.contains { typeContainsEscapingReferences($0.type) } ?? false
    case .enum(let defId):
      return context.getEnumCases(defId)?.contains { enumCase in
        enumCase.parameters.contains { typeContainsEscapingReferences($0.type) }
      } ?? false
    case .genericStruct(_, let args), .genericEnum(_, let args):
      return args.contains(where: typeContainsEscapingReferences)
    default:
      return false
    }
  }

  private func rootLocal(of place: MIRPlace) -> MIRLocalID? {
    switch place {
    case .local(let local):
      return local
    case .field(let base, _), .enumPayload(let base, _, _, _, _):
      return rootLocal(of: base)
    case .deref, .pointerElement:
      return nil
    case .global:
      return nil
    }
  }

  private func isLocalPlace(_ place: MIRPlace) -> Bool {
    if case .local = place { return true }
    return false
  }

  private func intrinsicValues(_ intrinsic: MIRIntrinsic) -> [MIRValue] {
    switch intrinsic {
    case .allocMemory(let count, _):
      return [count]
    case .deallocMemory(let ptr):
      return [ptr]
    case .copyMemory(let dest, let source, let count), .moveMemory(let dest, let source, let count):
      return [dest, source, count]
    case .isUniqueMutable(let value):
      return [value]
    case .refCount(let value):
      return [value]
    case .makeRef(let ptr, let owner, _), .makeMutRef(let ptr, let owner, _):
      return [ptr, owner]
    case .downgradeRef(let value, _), .downgradeMutRef(let value, _), .upgradeRef(let value, _), .upgradeMutRef(let value, _):
      return [value]
    case .initMemory(let ptr, let value):
      return [ptr, value]
    case .deinitMemory(let ptr):
      return [ptr]
    case .takeMemory(let ptr, _):
      return [ptr]
    case .nullPtr:
      return []
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      return [outHandle, outTid, closure, stackSize]
    }
  }
}

private final class MIRReferenceAllocationFunctionPromoter {
  private let function: MIRFunction
  private let escapingLocals: Set<MIRLocalID>
  private let context: CompilerContext
  private let escapingParameterSummaries: [UInt64: MIRReferenceParameterSummary]

  init(
    function: MIRFunction,
    escapingLocals: Set<MIRLocalID>,
    context: CompilerContext,
    escapingParameterSummaries: [UInt64: MIRReferenceParameterSummary]
  ) {
    self.function = function
    self.escapingLocals = escapingLocals
    self.context = context
    self.escapingParameterSummaries = escapingParameterSummaries
  }

  func promote() -> MIRFunction {
    var updated = function
    updated.blocks = function.blocks.map { block in
      var newBlock = block
      newBlock.statements = block.statements.map(promoteStatement)
      return newBlock
    }
    return updated
  }

  private func promoteStatement(_ statement: MIRStatement) -> MIRStatement {
    switch statement {
    case .assign(let place, let value):
      if case .local(let local) = place, escapingLocals.contains(local) {
        return .assign(place, promoteDirectReferences(in: value))
      }
      if !isLocalPlace(place) {
        return .assign(place, promoteDirectReferences(in: value))
      }
      return .assign(place, promoteEscapingCallArguments(in: value))
    case .compoundAssign(let assignment):
      return .compoundAssign(
        MIRCompoundAssignment(
          target: assignment.target,
          operatorKind: assignment.operatorKind,
          value: !isLocalPlace(assignment.target)
            ? promoteDirectReferences(in: assignment.value)
            : promoteEscapingCallArguments(in: assignment.value)
        )
      )
    case .evaluate(let value):
      return .evaluate(promoteEscapingCallArguments(in: value))
    case .retain(let value):
      return .retain(promoteEscapingCallArguments(in: value))
    case .release(let value):
      return .release(promoteEscapingCallArguments(in: value))
    case .declare, .drop, .scopeEnter, .scopeExit, .debugSource:
      return statement
    }
  }

  private func promoteEscapingCallArguments(in value: MIRValue) -> MIRValue {
    switch value {
    case .call(let call):
      return .call(
        MIRCall(
          callee: call.callee,
          arguments: promoteArguments(call.arguments, for: call.callee),
          argumentOwnerships: call.argumentOwnerships,
          type: call.type
        )
      )
    case .intrinsic(let intrinsic):
      return .intrinsic(promoteIntrinsic(intrinsic))
    default:
      return value
    }
  }

  private func promoteArguments(_ arguments: [MIRValue], for callee: MIROperand) -> [MIRValue] {
    guard case .function(let symbol) = callee else { return arguments }
    let storedParameters = escapingParameterSummaries[symbol.defId.id]?.storedParameterIndices ?? []
    guard !storedParameters.isEmpty else { return arguments }
    return arguments.enumerated().map { index, argument in
      storedParameters.contains(index) ? promoteDirectReferences(in: argument) : argument
    }
  }

  private func promoteIntrinsic(_ intrinsic: MIRIntrinsic) -> MIRIntrinsic {
    switch intrinsic {
    case .initMemory(let ptr, let value):
      return .initMemory(ptr: ptr, value: promoteDirectReferences(in: value))
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      return .spawnThread(outHandle: outHandle, outTid: outTid, closure: promoteDirectReferences(in: closure), stackSize: stackSize)
    default:
      return intrinsic
    }
  }

  private func promoteDirectReferences(in value: MIRValue) -> MIRValue {
    switch value {
    case .ref(let place, let kind, .stackBorrow):
      return .ref(place, kind: kind, allocation: .heapOwned)
    case .aggregate(let aggregate):
      return .aggregate(MIRAggregate(type: aggregate.type, fields: aggregate.fields.map(promoteDirectReferences)))
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
      return .enumTag(MIREnumTag(subject: promoteDirectReferences(in: tag.subject), enumType: tag.enumType))
    case .intrinsic(let intrinsic):
      return .intrinsic(promoteIntrinsic(intrinsic))
    case .call(let call):
      return .call(
        MIRCall(
          callee: call.callee,
          arguments: promoteArguments(call.arguments, for: call.callee),
          argumentOwnerships: call.argumentOwnerships,
          type: call.type
        )
      )
    default:
      return value
    }
  }

  private func isLocalPlace(_ place: MIRPlace) -> Bool {
    if case .local = place { return true }
    return false
  }
}

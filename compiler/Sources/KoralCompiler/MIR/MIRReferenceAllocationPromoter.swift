import Foundation

final class MIRReferenceAllocationPromoter {
  private let program: MIRProgram
  private let context: CompilerContext
  private let functionParameterTypesByDefId: [DefId: [Type]]
  private let functionParameterTypesByName: [String: [Type]]
  private let escapeSummariesByDefId: [DefId: MIREscapeSummary]

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
    self.escapeSummariesByDefId = Self.computeEscapeSummaries(program: program, context: context)
  }

  func promote() -> MIRProgram {
    let functions = program.functions.map { function in
      return MIRReferenceAllocationFunctionPromoter(
        function: function,
        globals: program.globals,
        functionParameterTypesByDefId: functionParameterTypesByDefId,
        functionParameterTypesByName: functionParameterTypesByName,
        escapeSummariesByDefId: escapeSummariesByDefId,
        context: context
      ).promote()
    }

    return MIRProgram(
      globals: program.globals,
      functions: functions,
      context: context,
      staticMethodLookup: program.staticMethodLookup,
      traits: program.traits,
      receiverMethodDispatch: program.receiverMethodDispatch,
      escapeSummaries: escapeSummariesByDefId
    )
  }

  private static func computeEscapeSummaries(program: MIRProgram, context: CompilerContext) -> [DefId: MIREscapeSummary] {
    func localParameterIndexMap(for function: MIRFunction) -> [MIRLocalID: Int] {
      var result: [MIRLocalID: Int] = [:]
      for (index, parameter) in function.parameters.enumerated() {
        if let local = function.locals.first(where: { $0.storage == .parameter && $0.symbol?.defId == parameter.defId }) {
          result[local.id] = index
        }
      }
      return result
    }

    var summaries: [DefId: MIREscapeSummary] = Dictionary(
      uniqueKeysWithValues: program.functions.map { ($0.identifier.defId, MIREscapeSummary(returningParameterIndices: [], directReferenceEscapingParameterIndices: [])) }
    )

    func visitValue(
      _ value: MIRValue,
      parameterLocals: [MIRLocalID: Int],
      summaries: [DefId: MIREscapeSummary],
      returning: inout Set<Int>,
      directEscaping: inout Set<Int>
    ) {
      func baseLocalID(of place: MIRPlace) -> MIRLocalID? {
        switch place {
        case .local(let id): return id
        case .global: return nil
        case .field(let base, _): return baseLocalID(of: base)
        case .enumPayload(let base, _, _, _, _): return baseLocalID(of: base)
        case .deref(let base, _):
          if case .operand(.local(let id)) = base { return id }
          return nil
        case .pointerElement(let base, _):
          if case .operand(.local(let id)) = base { return id }
          return nil
        }
      }

      func markEscaping(_ value: MIRValue) {
        switch value {
        case .operand(.local(let localID)):
          if let index = parameterLocals[localID] {
            directEscaping.insert(index)
          }
        case .placeRead(let place, _):
          if let id = baseLocalID(of: place), let index = parameterLocals[id] {
            directEscaping.insert(index)
          }
        case .ref(let place, _, _):
          if let id = baseLocalID(of: place), let index = parameterLocals[id] {
            directEscaping.insert(index)
          }
        default:
          break
        }
      }

      switch value {
      case .call(let call):
        if case .function(let callee) = call.callee,
           let calleeSummary = summaries[callee.defId] {
          for index in calleeSummary.escapingParameterIndices where index < call.arguments.count {
            markEscaping(call.arguments[index])
          }
        } else {
          for argument in call.arguments {
            markEscaping(argument)
          }
        }
        for argument in call.arguments {
          visitValue(argument, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
      case .traitMethodCall(let call):
        visitValue(call.receiver, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        for argument in call.arguments {
          visitValue(argument, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
        // Conservatively mark receiver and arguments as escaping.
        // Trait method dispatch cannot resolve to a concrete callee summary
        // at this stage, so we must assume all passed references escape.
        markEscaping(call.receiver)
        for argument in call.arguments {
          markEscaping(argument)
        }
      case .aggregate(let aggregate):
        for field in aggregate.fields {
          markEscaping(field)
          visitValue(field, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
      case .enumCase(let construction):
        for argument in construction.arguments {
          markEscaping(argument)
          visitValue(argument, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
      case .traitObjectConversion(let conversion):
        markEscaping(conversion.inner)
        visitValue(conversion.inner, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
      case .enumTag(let tag):
        visitValue(tag.subject, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
      case .intrinsic(let intrinsic):
        switch intrinsic {
        case .makeRef(_, let owner, _), .makeMutRef(_, let owner, _):
          markEscaping(owner)
          visitValue(owner, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .downgradeRef(let value, _), .downgradeMutRef(let value, _):
          visitValue(value, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .upgradeRef(let value, _), .upgradeMutRef(let value, _),
             .isUniqueMutable(let value), .refCount(let value):
          visitValue(value, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .copyMemory(let dest, let source, let count), .moveMemory(let dest, let source, let count):
          visitValue(dest, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitValue(source, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitValue(count, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .initMemory(let ptr, let value):
          visitValue(ptr, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitValue(value, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .deallocMemory(let ptr), .deinitMemory(let ptr), .takeMemory(let ptr, _):
          visitValue(ptr, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
          visitValue(outHandle, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitValue(outTid, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitValue(closure, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitValue(stackSize, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .allocMemory, .nullPtr:
          break
        }
      case .binary, .unary, .lambda, .operand, .placeRead, .ref, .pointer, .cast:
        if case .lambda(let lambda) = value {
          for source in lambda.captureSources {
            if case .local(let localID) = source, let index = parameterLocals[localID] {
              directEscaping.insert(index)
            }
          }
        }
      }
    }

    var changed = true
    let parameterLocalMaps: [DefId: [MIRLocalID: Int]] = Dictionary(
      uniqueKeysWithValues: program.functions.map { ($0.identifier.defId, localParameterIndexMap(for: $0)) }
    )
    while changed {
      changed = false
      for function in program.functions {
        let parameterLocals = parameterLocalMaps[function.identifier.defId] ?? [:]
        var returning: Set<Int> = []
        var directEscaping: Set<Int> = []
        for block in function.blocks {
          for statement in block.statements {
            switch statement {
            case .assign(_, let value), .evaluate(let value), .retain(let value), .release(let value):
              visitValue(value, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
            case .compoundAssign(let assignment):
              visitValue(assignment.value, parameterLocals: parameterLocals, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
            case .declare, .drop, .scopeEnter, .scopeExit, .debugSource:
              break
            }
          }
          if case .returnValue(let operand) = block.terminator {
            switch operand {
            case .some(.local(let localID)):
              if let index = parameterLocals[localID] {
                returning.insert(index)
              }
            default:
              break
            }
          }
        }

        let next = MIREscapeSummary(
          returningParameterIndices: returning,
          directReferenceEscapingParameterIndices: directEscaping
        )
        let current = summaries[function.identifier.defId] ?? MIREscapeSummary(returningParameterIndices: [], directReferenceEscapingParameterIndices: [])
        if current != next {
          summaries[function.identifier.defId] = next
          changed = true
        }
      }
    }

    return summaries
  }
}

private final class MIRReferenceAllocationFunctionPromoter {
  private let function: MIRFunction
  private let globals: [MIRGlobal]
  private let functionParameterTypesByDefId: [DefId: [Type]]
  private let functionParameterTypesByName: [String: [Type]]
  private let escapeSummariesByDefId: [DefId: MIREscapeSummary]
  private let context: CompilerContext
  private let resolver: MIRTypeResolver
  private let escapingLocals: Set<MIRLocalID>
  private let temporaryLocalIds: Set<MIRLocalID>

  init(
    function: MIRFunction,
    globals: [MIRGlobal],
    functionParameterTypesByDefId: [DefId: [Type]],
    functionParameterTypesByName: [String: [Type]],
    escapeSummariesByDefId: [DefId: MIREscapeSummary],
    context: CompilerContext
  ) {
    self.function = function
    self.globals = globals
    self.functionParameterTypesByDefId = functionParameterTypesByDefId
    self.functionParameterTypesByName = functionParameterTypesByName
    self.escapeSummariesByDefId = escapeSummariesByDefId
    self.context = context
    self.resolver = MIRTypeResolver(function: function, context: context)
    self.escapingLocals = Self.computeLocalsFlowingToLambdaCaptures(function: function)
    self.temporaryLocalIds = Set(function.locals.filter({ $0.storage == .temporary }).map(\.id))
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

  /// Computes the set of local IDs whose values transitively flow into lambda
  /// captures.  When a temporary ref flows into one of these locals, it must be
  /// promoted to heapOwned so the captured pointer does not dangle.
  private static func computeLocalsFlowingToLambdaCaptures(function: MIRFunction) -> Set<MIRLocalID> {
    var escaping: Set<MIRLocalID> = []
    // Seed: locals directly captured by lambdas.
    for block in function.blocks {
      for statement in block.statements {
        if case .assign(_, let value) = statement, case .lambda(let lambda) = value {
          for source in lambda.captureSources {
            if case .local(let id) = source {
              escaping.insert(id)
            }
          }
        }
      }
    }
    // Backward propagation: if A = B and A is escaping, then B is escaping too.
    var changed = true
    while changed {
      changed = false
      for block in function.blocks {
        for statement in block.statements {
          guard case .assign(let dest, let value) = statement,
                case .local(let destID) = dest,
                escaping.contains(destID) else { continue }
          switch value {
          case .operand(.local(let src)):
            if escaping.insert(src).inserted { changed = true }
          case .placeRead(.local(let src), _):
            if escaping.insert(src).inserted { changed = true }
          default:
            break
          }
        }
      }
    }
    return escaping
  }


  /// Returns true if the place is a member-path access (contains deref or field projections).
  /// Simple local references return false.
  private func isMemberPathPlace(_ place: MIRPlace) -> Bool {
    switch place {
    case .local:
      return false
    case .global:
      return false
    case .field:
      return true
    case .enumPayload:
      return true
    case .deref:
      return true
    case .pointerElement:
      return true
    }
  }

  private func isTemporaryLocal(_ place: MIRPlace) -> Bool {
    guard case .local(let localID) = place else { return false }
    return temporaryLocalIds.contains(localID)
  }
  private func promoteStatement(_ statement: MIRStatement) -> MIRStatement {
    switch statement {
    case .assign(let place, let value):
      return .assign(place, promoteValue(value, destinationType: resolver.type(of: place), destinationPlace: place))
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

  private func promoteValue(_ value: MIRValue, destinationType: Type?, destinationPlace: MIRPlace? = nil) -> MIRValue {
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
    case .lambda, .binary, .unary, .operand, .placeRead, .pointer, .cast:
      recursivelyPromoted = value
    case .ref(let place, let kind, .stackBorrow):
      let destIsTemp = destinationPlace.map { isTemporaryLocal($0) } ?? false
      let destEscapesViaLambda = destinationPlace.map {
        if case .local(let id) = $0 { return self.escapingLocals.contains(id) }
        return false
      } ?? false
      let keepStackBorrow = isMemberPathPlace(place)
        || (kind == .mutable && destIsTemp && !destEscapesViaLambda)
      if keepStackBorrow {
        return .ref(place, kind: kind, allocation: .stackBorrow)
      }
      recursivelyPromoted = .ref(place, kind: kind, allocation: .stackBorrow)
    case .ref(let place, let kind, let allocation):
      recursivelyPromoted = .ref(place, kind: kind, allocation: allocation)
    }

    guard let destinationType, typeRequiresOwnedReferenceStorage(destinationType) else {
      return recursivelyPromoted
    }
    return promoteDirectReferences(in: recursivelyPromoted)
  }

  private func promoteCallArguments(_ arguments: [MIRValue], callee: MIROperand) -> [MIRValue] {
    let parameterTypes: [Type]
    let directRefEscapingIndices: Set<Int>
    switch callee {
    case .function(let symbol):
      if let exactParameterTypes = globalFunctionParameterTypes(for: symbol) {
        parameterTypes = exactParameterTypes
      } else if case .function(let parameters, _) = symbol.type {
        parameterTypes = parameters.map(\.type)
      } else {
        parameterTypes = []
      }
      if let summary = escapeSummariesByDefId[symbol.defId] {
        directRefEscapingIndices = summary.directReferenceEscapingParameterIndices
      } else {
        directRefEscapingIndices = Set(0..<parameterTypes.count)
      }
    default:
      parameterTypes = []
      directRefEscapingIndices = Set(0..<arguments.count)
    }

    return arguments.enumerated().map { index, argument in
      let destinationType = index < parameterTypes.count ? parameterTypes[index] : nil
      let promoted = promoteValue(argument, destinationType: destinationType)
      guard directRefEscapingIndices.contains(index) else {
        return promoted
      }
      return promoteDirectReferences(in: promoted)
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
    case .reference, .mutableReference, .weakReference, .mutableWeakReference, .pointer, .mutablePointer, .function, .traitObject:
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

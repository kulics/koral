import Foundation

fileprivate func buildEscapeSummaryDefIdByName(
  functions: [MIRFunction],
  context: CompilerContext
) -> [String: DefId] {
  var result: [String: DefId] = [:]
  for function in functions {
    if let qualifiedName = context.getQualifiedName(function.identifier.defId) {
      result[qualifiedName] = function.identifier.defId
    }
    if let name = context.getName(function.identifier.defId) {
      result[name] = function.identifier.defId
    }
  }
  return result
}

fileprivate func lookupEscapeSummary(
  for symbol: Symbol,
  summariesByDefId: [DefId: MIREscapeSummary],
  summaryDefIdByName: [String: DefId],
  context: CompilerContext
) -> MIREscapeSummary? {
  if let summary = summariesByDefId[symbol.defId] {
    return summary
  }
  if let qualifiedName = context.getQualifiedName(symbol.defId),
     let defId = summaryDefIdByName[qualifiedName],
     let summary = summariesByDefId[defId] {
    return summary
  }
  if let name = context.getName(symbol.defId),
     let defId = summaryDefIdByName[name],
     let summary = summariesByDefId[defId] {
    return summary
  }
  return nil
}

final class MIRReferenceAllocationPromoter {
  private let program: MIRProgram
  private let context: CompilerContext
  private let functionParametersByDefId: [DefId: [Parameter]]
  private let functionParametersByName: [String: [Parameter]]
  private let escapeSummariesByDefId: [DefId: MIREscapeSummary]
  private let escapeSummaryDefIdByName: [String: DefId]

  init(program: MIRProgram) {
    self.program = program
    self.context = program.context
    self.functionParametersByDefId = Dictionary(
      uniqueKeysWithValues: program.functions.map { function in
        let parameters: [Parameter]
        if case .function(let functionParameters, _) = function.identifier.type {
          parameters = functionParameters
        } else {
          parameters = function.parameters.map { Parameter(type: $0.type, kind: passKindForParameterType($0.type)) }
        }
        return (function.identifier.defId, parameters)
      }
    )
    var parametersByName: [String: [Parameter]] = [:]
    for function in program.functions {
      let parameters: [Parameter]
      if case .function(let functionParameters, _) = function.identifier.type {
        parameters = functionParameters
      } else {
        parameters = function.parameters.map { Parameter(type: $0.type, kind: passKindForParameterType($0.type)) }
      }
      if let qualifiedName = context.getQualifiedName(function.identifier.defId) {
        parametersByName[qualifiedName] = parameters
      }
      if let name = context.getName(function.identifier.defId) {
        parametersByName[name] = parameters
      }
    }
    self.functionParametersByName = parametersByName
    self.escapeSummaryDefIdByName = buildEscapeSummaryDefIdByName(functions: program.functions, context: context)
    self.escapeSummariesByDefId = Self.computeEscapeSummaries(program: program, context: context)
  }

  func promote() -> MIRProgram {
    let functions = program.functions.map { function in
      return MIRReferenceAllocationFunctionPromoter(
        function: function,
        globals: program.globals,
        functionParametersByDefId: functionParametersByDefId,
        functionParametersByName: functionParametersByName,
        escapeSummariesByDefId: escapeSummariesByDefId,
        escapeSummaryDefIdByName: escapeSummaryDefIdByName,
        context: context
      ).promote()
    }

    return MIRProgram(
      globals: program.globals,
      functions: functions,
      context: context,
      staticMethodLookup: program.staticMethodLookup,
      traits: program.traits,
      conformanceWitnesses: program.conformanceWitnesses,
      receiverMethodDispatch: program.receiverMethodDispatch,
      escapeSummaries: escapeSummariesByDefId
    )
  }

  private static func computeEscapeSummaries(program: MIRProgram, context: CompilerContext) -> [DefId: MIREscapeSummary] {
    let summaryDefIdByName = buildEscapeSummaryDefIdByName(functions: program.functions, context: context)

    func localParameterIndexMap(for function: MIRFunction) -> [MIRLocalID: Int] {
      var result: [MIRLocalID: Int] = [:]
      for (index, parameter) in function.parameters.enumerated() {
        if let local = function.locals.first(where: { $0.storage == .parameter && $0.symbol?.defId == parameter.defId }) {
          result[local.id] = index
        }
      }
      return result
    }

    func baseLocalID(of place: MIRPlace) -> MIRLocalID? {
      switch place {
      case .local(let localID):
        return localID
      case .global:
        return nil
      case .field(let base, _):
        return baseLocalID(of: base)
      case .enumPayload(let base, _, _, _, _):
        return baseLocalID(of: base)
      case .deref(let base, _):
        if case .operand(.local(let localID)) = base {
          return localID
        }
        return nil
      case .pointerElement(let base, _):
        if case .operand(.local(let localID)) = base {
          return localID
        }
        return nil
      }
    }

    func collectParameterSources(
      _ value: MIRValue,
      parameterLocals: [MIRLocalID: Int],
      localSources: [MIRLocalID: Set<Int>],
      out: inout Set<Int>
    ) {
      let maybeLocalID: MIRLocalID?
      switch value {
      case .operand(.local(let localID)):
        maybeLocalID = localID
      case .placeRead(let place, _):
        maybeLocalID = baseLocalID(of: place)
      case .ref(let place, _, _):
        maybeLocalID = baseLocalID(of: place)
      default:
        maybeLocalID = nil
      }

      guard let localID = maybeLocalID else {
        return
      }
      if let parameterIndex = parameterLocals[localID] {
        out.insert(parameterIndex)
        return
      }
      for parameterIndex in localSources[localID] ?? [] {
        out.insert(parameterIndex)
      }
    }

    func mergeValueParameterSources(
      targetLocal: MIRLocalID,
      value: MIRValue,
      parameterLocals: [MIRLocalID: Int],
      localSources: inout [MIRLocalID: Set<Int>]
    ) {
      var collected: Set<Int> = []
      collectParameterSources(value, parameterLocals: parameterLocals, localSources: localSources, out: &collected)
      var merged = localSources[targetLocal] ?? []
      merged.formUnion(collected)
      if !merged.isEmpty {
        localSources[targetLocal] = merged
      }
    }

    func visitEscapeValue(
      _ value: MIRValue,
      parameterLocals: [MIRLocalID: Int],
      localSources: [MIRLocalID: Set<Int>],
      summaries: [DefId: MIREscapeSummary],
      returning: inout Set<Int>,
      directEscaping: inout Set<Int>
    ) {
      func markDirectEscape(_ value: MIRValue) {
        collectParameterSources(value, parameterLocals: parameterLocals, localSources: localSources, out: &directEscaping)
      }

      func markReturning(_ value: MIRValue) {
        collectParameterSources(value, parameterLocals: parameterLocals, localSources: localSources, out: &returning)
      }

      switch value {
      case .call(let call):
        if case .function(let callee) = call.callee,
           let calleeSummary = lookupEscapeSummary(
             for: callee,
             summariesByDefId: summaries,
             summaryDefIdByName: summaryDefIdByName,
             context: context
           ) {
          for (index, argument) in call.arguments.enumerated() {
            if calleeSummary.directReferenceEscapingParameterIndices.contains(index) {
              markDirectEscape(argument)
            }
            if calleeSummary.returningParameterIndices.contains(index) {
              markReturning(argument)
            }
          }
        } else {
          for argument in call.arguments {
            markDirectEscape(argument)
          }
        }
        for argument in call.arguments {
          visitEscapeValue(argument, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
      case .traitMethodCall(let call):
        visitEscapeValue(call.receiver, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        for argument in call.arguments {
          visitEscapeValue(argument, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
        markDirectEscape(call.receiver)
        for argument in call.arguments {
          markDirectEscape(argument)
        }
      case .aggregate(let aggregate):
        for field in aggregate.fields {
          markDirectEscape(field)
          visitEscapeValue(field, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
      case .enumCase(let construction):
        for argument in construction.arguments {
          markDirectEscape(argument)
          visitEscapeValue(argument, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        }
      case .traitObjectConversion(let conversion):
        markDirectEscape(conversion.inner)
        visitEscapeValue(conversion.inner, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
      case .enumTag(let tag):
        visitEscapeValue(tag.subject, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
      case .intrinsic(let intrinsic):
        switch intrinsic {
        case .makeRef(_, let owner, _), .makeMutRef(_, let owner, _):
          markDirectEscape(owner)
          visitEscapeValue(owner, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .downgradeRef(let value, _),
             .downgradeMutRef(let value, _),
             .upgradeRef(let value, _),
             .upgradeMutRef(let value, _),
             .isUniqueMutable(let value),
             .refCount(let value),
             .traitObjectMatches(let value, _, _, _),
             .traitObjectDowncast(let value, _):
          visitEscapeValue(value, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .copyMemory(let dest, let source, let count),
             .moveMemory(let dest, let source, let count):
          visitEscapeValue(dest, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitEscapeValue(source, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitEscapeValue(count, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .initMemory(let ptr, let value):
          visitEscapeValue(ptr, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitEscapeValue(value, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .deallocMemory(let ptr),
             .deinitMemory(let ptr),
             .takeMemory(let ptr, _):
          visitEscapeValue(ptr, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
          visitEscapeValue(outHandle, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitEscapeValue(outTid, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitEscapeValue(closure, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
          visitEscapeValue(stackSize, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
        case .allocMemory, .nullPtr:
          break
        }
      case .lambda(let lambda):
        for source in lambda.captureSources {
          if case .local(let localID) = source,
             let parameterIndex = parameterLocals[localID] {
            directEscaping.insert(parameterIndex)
          }
        }
      case .binary, .unary, .operand, .placeRead, .ref, .pointer, .cast:
        break
      }
    }

    var summaries: [DefId: MIREscapeSummary] = Dictionary(
      uniqueKeysWithValues: program.functions.map { ($0.identifier.defId, MIREscapeSummary(returningParameterIndices: [], directReferenceEscapingParameterIndices: [])) }
    )
    let parameterLocalMaps: [DefId: [MIRLocalID: Int]] = Dictionary(
      uniqueKeysWithValues: program.functions.map { ($0.identifier.defId, localParameterIndexMap(for: $0)) }
    )

    var changed = true
    while changed {
      changed = false
      for function in program.functions {
        let parameterLocals = parameterLocalMaps[function.identifier.defId] ?? [:]
        var returning: Set<Int> = []
        var directEscaping: Set<Int> = []
        var localSources: [MIRLocalID: Set<Int>] = [:]

        for block in function.blocks {
          for statement in block.statements {
            switch statement {
            case .assign(let place, let value):
              visitEscapeValue(value, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
              if case .local(let localID) = place {
                mergeValueParameterSources(targetLocal: localID, value: value, parameterLocals: parameterLocals, localSources: &localSources)
              }
            case .compoundAssign(let assignment):
              visitEscapeValue(assignment.value, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
            case .evaluate(let value), .retain(let value), .release(let value):
              visitEscapeValue(value, parameterLocals: parameterLocals, localSources: localSources, summaries: summaries, returning: &returning, directEscaping: &directEscaping)
            case .declare, .drop, .scopeEnter, .scopeExit, .debugSource:
              break
            }
          }

          if case .returnValue(let operand?) = block.terminator {
            collectParameterSources(.operand(operand), parameterLocals: parameterLocals, localSources: localSources, out: &returning)
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
  private let functionParametersByDefId: [DefId: [Parameter]]
  private let functionParametersByName: [String: [Parameter]]
  private let escapeSummariesByDefId: [DefId: MIREscapeSummary]
  private let escapeSummaryDefIdByName: [String: DefId]
  private let context: CompilerContext
  private let resolver: MIRTypeResolver
  private let escapeAnalysis: MIRFunctionEscapeAnalysis
  private let temporaryLocalIds: Set<MIRLocalID>
  private let temporaryValueSourcesByLocal: [MIRLocalID: MIRValue]

  init(
    function: MIRFunction,
    globals: [MIRGlobal],
    functionParametersByDefId: [DefId: [Parameter]],
    functionParametersByName: [String: [Parameter]],
    escapeSummariesByDefId: [DefId: MIREscapeSummary],
    escapeSummaryDefIdByName: [String: DefId],
    context: CompilerContext
  ) {
    self.function = function
    self.globals = globals
    self.functionParametersByDefId = functionParametersByDefId
    self.functionParametersByName = functionParametersByName
    self.escapeSummariesByDefId = escapeSummariesByDefId
    self.escapeSummaryDefIdByName = escapeSummaryDefIdByName
    self.context = context
    self.resolver = MIRTypeResolver(function: function, context: context)
    self.temporaryLocalIds = Set(function.locals.filter({ $0.storage == .temporary }).map(\.id))
    self.escapeAnalysis = Self.computeFunctionEscapeAnalysis(
      function: function,
      summaries: escapeSummariesByDefId,
      summaryDefIdByName: escapeSummaryDefIdByName,
      context: context
    )
    self.temporaryValueSourcesByLocal = Self.buildTemporaryValueSources(function: function, temporaryLocalIds: temporaryLocalIds)
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

  private static func baseLocalID(of place: MIRPlace) -> MIRLocalID? {
    switch place {
    case .local(let localID):
      return localID
    case .global:
      return nil
    case .field(let base, _):
      return baseLocalID(of: base)
    case .enumPayload(let base, _, _, _, _):
      return baseLocalID(of: base)
    case .deref(let base, _):
      if case .operand(.local(let localID)) = base {
        return localID
      }
      return nil
    case .pointerElement(let base, _):
      if case .operand(.local(let localID)) = base {
        return localID
      }
      return nil
    }
  }

  private static func markLocalEscape(_ value: MIRValue, escaping: inout Set<MIRLocalID>) {
    switch value {
    case .operand(.local(let localID)):
      escaping.insert(localID)
    case .placeRead(let place, _):
      if let localID = baseLocalID(of: place) {
        escaping.insert(localID)
      }
    case .ref(let place, _, _):
      if let localID = baseLocalID(of: place) {
        escaping.insert(localID)
      }
    default:
      break
    }
  }

  private static func visitLocalEscapeValue(
    _ value: MIRValue,
    summaries: [DefId: MIREscapeSummary],
    summaryDefIdByName: [String: DefId],
    context: CompilerContext,
    escaping: inout Set<MIRLocalID>
  ) {
    switch value {
    case .call(let call):
      if case .function(let callee) = call.callee,
         let calleeSummary = lookupEscapeSummary(
           for: callee,
           summariesByDefId: summaries,
           summaryDefIdByName: summaryDefIdByName,
           context: context
         ) {
        for (index, argument) in call.arguments.enumerated() {
          if calleeSummary.directReferenceEscapingParameterIndices.contains(index) {
            markLocalEscape(argument, escaping: &escaping)
          }
        }
      } else {
        for argument in call.arguments {
          markLocalEscape(argument, escaping: &escaping)
        }
      }
      for argument in call.arguments {
        visitLocalEscapeValue(argument, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      }
    case .traitMethodCall(let call):
      markLocalEscape(call.receiver, escaping: &escaping)
      visitLocalEscapeValue(call.receiver, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      for argument in call.arguments {
        markLocalEscape(argument, escaping: &escaping)
        visitLocalEscapeValue(argument, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      }
    case .aggregate(let aggregate):
      for field in aggregate.fields {
        markLocalEscape(field, escaping: &escaping)
        visitLocalEscapeValue(field, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      }
    case .enumCase(let construction):
      for argument in construction.arguments {
        markLocalEscape(argument, escaping: &escaping)
        visitLocalEscapeValue(argument, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      }
    case .traitObjectConversion(let conversion):
      markLocalEscape(conversion.inner, escaping: &escaping)
      visitLocalEscapeValue(conversion.inner, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
    case .enumTag(let tag):
      visitLocalEscapeValue(tag.subject, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
    case .intrinsic(let intrinsic):
      switch intrinsic {
      case .makeRef(_, let owner, _), .makeMutRef(_, let owner, _):
        markLocalEscape(owner, escaping: &escaping)
        visitLocalEscapeValue(owner, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      case .downgradeRef(let value, _),
           .downgradeMutRef(let value, _),
           .upgradeRef(let value, _),
           .upgradeMutRef(let value, _),
           .isUniqueMutable(let value),
           .refCount(let value),
           .traitObjectMatches(let value, _, _, _),
           .traitObjectDowncast(let value, _):
        visitLocalEscapeValue(value, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      case .copyMemory(let dest, let source, let count),
           .moveMemory(let dest, let source, let count):
        visitLocalEscapeValue(dest, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        visitLocalEscapeValue(source, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        visitLocalEscapeValue(count, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      case .initMemory(let ptr, let value):
        visitLocalEscapeValue(ptr, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        markLocalEscape(value, escaping: &escaping)
        visitLocalEscapeValue(value, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      case .deallocMemory(let ptr), .deinitMemory(let ptr), .takeMemory(let ptr, _):
        visitLocalEscapeValue(ptr, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
        visitLocalEscapeValue(outHandle, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        visitLocalEscapeValue(outTid, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        markLocalEscape(closure, escaping: &escaping)
        visitLocalEscapeValue(closure, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        visitLocalEscapeValue(stackSize, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
      case .allocMemory, .nullPtr:
        break
      }
    case .lambda(let lambda):
      for source in lambda.captureSources {
        if case .local(let localID) = source {
          escaping.insert(localID)
        }
      }
    case .binary, .unary, .operand, .placeRead, .ref, .pointer, .cast:
      break
    }
  }

  private static func computeEscapingLocals(
    function: MIRFunction,
    summaries: [DefId: MIREscapeSummary],
    summaryDefIdByName: [String: DefId],
    context: CompilerContext
  ) -> Set<MIRLocalID> {
    var escaping: Set<MIRLocalID> = []
    for block in function.blocks {
      for statement in block.statements {
        switch statement {
        case .assign(_, let value), .evaluate(let value), .retain(let value), .release(let value):
          visitLocalEscapeValue(value, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        case .compoundAssign(let assignment):
          visitLocalEscapeValue(assignment.value, summaries: summaries, summaryDefIdByName: summaryDefIdByName, context: context, escaping: &escaping)
        case .declare, .drop, .scopeEnter, .scopeExit, .debugSource:
          break
        }
      }
      if case .returnValue(let operand?) = block.terminator,
         case .local(let localID) = operand {
        escaping.insert(localID)
      }
    }

    var changed = true
    while changed {
      changed = false
      for block in function.blocks {
        for statement in block.statements {
          guard case .assign(let dest, let value) = statement,
                case .local(let destID) = dest,
                escaping.contains(destID) else {
            continue
          }
          switch value {
          case .operand(.local(let sourceID)):
            if escaping.insert(sourceID).inserted {
              changed = true
            }
          case .placeRead(let place, _):
            if let sourceID = baseLocalID(of: place), escaping.insert(sourceID).inserted {
              changed = true
            }
          case .ref(let place, _, _):
            if let sourceID = baseLocalID(of: place), escaping.insert(sourceID).inserted {
              changed = true
            }
          default:
            break
          }
        }
      }
    }
    return escaping
  }

  private static func computeEscapingValueLocals(function: MIRFunction) -> Set<MIRLocalID> {
    var escaping: Set<MIRLocalID> = []
    for block in function.blocks {
      if case .returnValue(let operand?) = block.terminator,
         case .local(let localID) = operand {
        escaping.insert(localID)
      }
    }

    var changed = true
    while changed {
      changed = false
      for block in function.blocks {
        for statement in block.statements {
          guard case .assign(let dest, let value) = statement,
                case .local(let destID) = dest,
                escaping.contains(destID) else {
            continue
          }
          switch value {
          case .operand(.local(let sourceID)):
            if escaping.insert(sourceID).inserted {
              changed = true
            }
          case .placeRead(let place, _):
            if let sourceID = baseLocalID(of: place), escaping.insert(sourceID).inserted {
              changed = true
            }
          case .ref(let place, _, _):
            if let sourceID = baseLocalID(of: place), escaping.insert(sourceID).inserted {
              changed = true
            }
          default:
            break
          }
        }
      }
    }
    return escaping
  }

  private static func computeFunctionEscapeAnalysis(
    function: MIRFunction,
    summaries: [DefId: MIREscapeSummary],
    summaryDefIdByName: [String: DefId],
    context: CompilerContext
  ) -> MIRFunctionEscapeAnalysis {
    MIRFunctionEscapeAnalysis(
      escapingLocals: computeEscapingLocals(
        function: function,
        summaries: summaries,
        summaryDefIdByName: summaryDefIdByName,
        context: context
      ),
      escapingValueLocals: computeEscapingValueLocals(function: function)
    )
  }

  private static func buildTemporaryValueSources(
    function: MIRFunction,
    temporaryLocalIds: Set<MIRLocalID>
  ) -> [MIRLocalID: MIRValue] {
    var sources: [MIRLocalID: MIRValue] = [:]
    var ambiguous: Set<MIRLocalID> = []
    for block in function.blocks {
      for statement in block.statements {
        guard case .assign(let place, let value) = statement,
              case .local(let localID) = place,
              temporaryLocalIds.contains(localID),
              !ambiguous.contains(localID) else {
          continue
        }
        if sources[localID] != nil {
          sources.removeValue(forKey: localID)
          ambiguous.insert(localID)
        } else {
          sources[localID] = value
        }
      }
    }
    return sources
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
    case .lambda(let lambda):
      if let destinationPlace,
         case .local(let localID) = destinationPlace,
         escapeAnalysis.escapingValueLocals.contains(localID),
         lambda.captures.contains(where: { $0.captureKind == .byMutReference }) {
        recursivelyPromoted = .lambda(rewriteEscapingMutableCaptures(in: lambda))
      } else {
        recursivelyPromoted = value
      }
    case .binary, .unary, .operand, .placeRead, .pointer, .cast:
      recursivelyPromoted = value
    case .ref(let place, let kind, .stackBorrow):
      let keepStackBorrow = destinationPlace.map {
        if case .local(let localID) = $0 {
          return !escapeAnalysis.escapingLocals.contains(localID)
        }
        return false
      } ?? false
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
    if let destinationPlace,
       case .local(let localID) = destinationPlace,
       !escapeAnalysis.escapingLocals.contains(localID) {
      return recursivelyPromoted
    }
    switch recursivelyPromoted {
    case .call, .traitMethodCall:
      return recursivelyPromoted
    default:
      break
    }
    return promoteDirectReferences(in: recursivelyPromoted)
  }

  private func rewriteEscapingMutableCaptures(in lambda: MIRLambda) -> MIRLambda {
    let rewrittenCaptures = lambda.captures.map { capture -> CapturedVariable in
      guard capture.captureKind == .byMutReference else {
        return capture
      }
      return CapturedVariable(symbol: capture.symbol, captureKind: .byValue)
    }
    return MIRLambda(
      parameters: lambda.parameters,
      captures: rewrittenCaptures,
      captureSources: lambda.captureSources,
      function: lambda.function,
      type: lambda.type
    )
  }

  private func promoteCallArguments(_ arguments: [MIRValue], callee: MIROperand) -> [MIRValue] {
    let parameters: [Parameter]
    let directRefEscapingIndices: Set<Int>
    let returningParameterIndices: Set<Int>
    switch callee {
    case .function(let symbol):
      if let exactParameters = globalFunctionParameters(for: symbol) {
        parameters = exactParameters
      } else if case .function(let functionParameters, _) = symbol.type {
        parameters = functionParameters
      } else {
        parameters = []
      }
      if let summary = lookupEscapeSummary(
        for: symbol,
        summariesByDefId: escapeSummariesByDefId,
        summaryDefIdByName: escapeSummaryDefIdByName,
        context: context
      ) {
        directRefEscapingIndices = summary.directReferenceEscapingParameterIndices
        returningParameterIndices = summary.returningParameterIndices
      } else {
        directRefEscapingIndices = Set(0..<arguments.count)
        returningParameterIndices = []
      }
    default:
      parameters = []
      directRefEscapingIndices = Set(0..<arguments.count)
      returningParameterIndices = []
    }

    return arguments.enumerated().map { index, argument in
      var destinationType = index < parameters.count ? promotionDestinationType(for: parameters[index]) : nil
      let preserveReturnedStackBorrow = returningParameterIndices.contains(index)
        && !directRefEscapingIndices.contains(index)
        && {
          switch resolveTemporaryRefSource(argument) {
          case .ref(_, _, .stackBorrow):
            if let destinationType {
              return typeRequiresOwnedReferenceStorage(destinationType)
            }
            return false
          default:
            return false
          }
        }()
      if preserveReturnedStackBorrow {
        destinationType = nil
      }
      var promoted = promoteValue(argument, destinationType: destinationType)
      if directRefEscapingIndices.contains(index) {
        promoted = promoteDirectReferences(in: promoted)
      }
      return promoted
    }
  }

  private func promotionDestinationType(for parameter: Parameter) -> Type {
    switch parameter.kind {
    case .byRef:
      switch parameter.type {
      case .reference(let inner):
        return .borrowedReference(inner: inner)
      case .borrowedReference:
        return parameter.type
      default:
        return .borrowedReference(inner: parameter.type)
      }
    case .byMutRef:
      switch parameter.type {
      case .mutableReference(let inner):
        return .mutableBorrowedReference(inner: inner)
      case .mutableBorrowedReference:
        return parameter.type
      default:
        return .mutableBorrowedReference(inner: parameter.type)
      }
    case .byVal:
      return parameter.type
    }
  }

  private func globalFunctionParameters(for symbol: Symbol) -> [Parameter]? {
    if let exactParameters = functionParametersByDefId[symbol.defId] {
      return exactParameters
    }
    if let qualifiedName = context.getQualifiedName(symbol.defId),
       let exactParameters = functionParametersByName[qualifiedName] {
      return exactParameters
    }
    if let name = context.getName(symbol.defId),
       let exactParameters = functionParametersByName[name] {
      return exactParameters
    }
    for global in globals {
      switch global {
      case .function(let identifier, let parameters, _)
      where identifier.defId == symbol.defId:
        if case .function(let functionParameters, _) = identifier.type {
          return functionParameters
        }
        return parameters.map { Parameter(type: $0.type, kind: passKindForParameterType($0.type)) }
      case .foreignFunction(let identifier, let parameters)
      where identifier.defId == symbol.defId:
        if case .function(let functionParameters, _) = identifier.type {
          return functionParameters
        }
        return parameters.map { Parameter(type: $0.type, kind: passKindForParameterType($0.type)) }
      default:
        continue
      }
    }
    return nil
  }

  private func resolveTemporaryRefSource(_ value: MIRValue) -> MIRValue {
    var seen: Set<MIRLocalID> = []
    return resolveTemporaryRefSource(value, seen: &seen)
  }

  private func resolveTemporaryRefSource(_ value: MIRValue, seen: inout Set<MIRLocalID>) -> MIRValue {
    switch value {
    case .ref:
      return value
    case .operand(.local(let localID)):
      return resolveTemporaryRefLocal(localID, original: value, seen: &seen)
    case .placeRead(.local(let localID), _):
      return resolveTemporaryRefLocal(localID, original: value, seen: &seen)
    default:
      return value
    }
  }

  private func resolveTemporaryRefLocal(_ localID: MIRLocalID, original: MIRValue, seen: inout Set<MIRLocalID>) -> MIRValue {
    guard !seen.contains(localID),
          let source = temporaryValueSourcesByLocal[localID] else {
      return original
    }
    seen.insert(localID)
    let resolved = resolveTemporaryRefSource(source, seen: &seen)
    seen.remove(localID)
    if case .ref = resolved {
      return resolved
    }
    return original
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
    case .traitObjectMatches(let value, let traitName, let traitTypeArguments, let concreteType):
      return .traitObjectMatches(
        value: promoteValue(value, destinationType: nil),
        traitName: traitName,
        traitTypeArguments: traitTypeArguments,
        concreteType: concreteType
      )
    case .traitObjectDowncast(let value, let resultType):
      return .traitObjectDowncast(value: promoteValue(value, destinationType: resultType), resultType: resultType)
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
    let resolved = resolveTemporaryRefSource(value)
    switch resolved {
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
      return resolved
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
    case .traitObjectMatches(let value, let traitName, let traitTypeArguments, let concreteType):
      return .traitObjectMatches(
        value: promoteDirectReferences(in: value),
        traitName: traitName,
        traitTypeArguments: traitTypeArguments,
        concreteType: concreteType
      )
    case .traitObjectDowncast(let value, let resultType):
      return .traitObjectDowncast(value: promoteDirectReferences(in: value), resultType: resultType)
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

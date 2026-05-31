import Foundation

struct MIRProgramStats {
  let globalCount: Int
  let traitVTableCount: Int
  let functionStats: [MIRFunctionStats]

  var functionCount: Int { functionStats.count }
  var fullyStructuredFunctionCount: Int { functionCount }
  var localCount: Int { functionStats.reduce(0) { $0 + $1.localCount } }
  var blockCount: Int { functionStats.reduce(0) { $0 + $1.blockCount } }
  var statementCount: Int { functionStats.reduce(0) { $0 + $1.statementCount } }
  var terminatorCount: Int { functionStats.reduce(0) { $0 + $1.terminatorCount } }
  var valueCount: Int { functionStats.reduce(0) { $0 + $1.valueCount } }
  var callCount: Int { functionStats.reduce(0) { $0 + $1.callCount } }
  var aggregateCount: Int { functionStats.reduce(0) { $0 + $1.aggregateCount } }
  var enumConstructionCount: Int { functionStats.reduce(0) { $0 + $1.enumConstructionCount } }
  var branchTerminatorCount: Int { functionStats.reduce(0) { $0 + $1.branchTerminatorCount } }
  var switchTerminatorCount: Int { functionStats.reduce(0) { $0 + $1.switchTerminatorCount } }
  var mirCodeGenCandidateFunctionCount: Int { functionStats.filter(\.isMIRCodeGenCandidate).count }
  var mirCodeGenBlockerCount: Int { functionStats.reduce(0) { $0 + $1.mirCodeGenBlockerCount } }
  var mirCodeGenBlockerKinds: [String: Int] { mergeCounts(functionStats.map(\.mirCodeGenBlockerKinds)) }
}

struct MIRFunctionStats {
  let localCount: Int
  let blockCount: Int
  let statementCount: Int
  let terminatorCount: Int
  let valueCount: Int
  let callCount: Int
  let aggregateCount: Int
  let enumConstructionCount: Int
  let branchTerminatorCount: Int
  let switchTerminatorCount: Int
  let mirCodeGenBlockerCount: Int
  let mirCodeGenBlockerKinds: [String: Int]

  var isMIRCodeGenCandidate: Bool { mirCodeGenBlockerCount == 0 }
}

private func mergeCounts(_ counts: [[String: Int]]) -> [String: Int] {
  var result: [String: Int] = [:]
  for dict in counts {
    for (key, value) in dict {
      result[key, default: 0] += value
    }
  }
  return result
}

struct MIRStatsCollector {
  static func collect(_ program: MIRProgram) -> MIRProgramStats {
    MIRProgramStats(
      globalCount: program.globals.count,
      traitVTableCount: program.globals.filter {
        if case .traitVTable = $0 { return true }
        return false
      }.count,
      functionStats: program.functions.map { collect($0) }
    )
  }

  private static func collect(_ function: MIRFunction) -> MIRFunctionStats {
    let counter = MIRStatsCounter()
    counter.localCount = function.locals.count
    counter.blockCount = function.blocks.count

    for block in function.blocks {
      counter.statementCount += block.statements.count
      counter.terminatorCount += 1
      for statement in block.statements {
        counter.count(statement)
      }
      counter.count(block.terminator)
    }

    return MIRFunctionStats(
      localCount: counter.localCount,
      blockCount: counter.blockCount,
      statementCount: counter.statementCount,
      terminatorCount: counter.terminatorCount,
      valueCount: counter.valueCount,
      callCount: counter.callCount,
      aggregateCount: counter.aggregateCount,
      enumConstructionCount: counter.enumConstructionCount,
      branchTerminatorCount: counter.branchTerminatorCount,
      switchTerminatorCount: counter.switchTerminatorCount,
      mirCodeGenBlockerCount: counter.mirCodeGenBlockerCount,
      mirCodeGenBlockerKinds: counter.mirCodeGenBlockerKinds
    )
  }
}

private final class MIRStatsCounter {
  var localCount = 0
  var blockCount = 0
  var statementCount = 0
  var terminatorCount = 0
  var valueCount = 0
  var callCount = 0
  var aggregateCount = 0
  var enumConstructionCount = 0
  var branchTerminatorCount = 0
  var switchTerminatorCount = 0
  var mirCodeGenBlockerKinds: [String: Int] = [:]

  var mirCodeGenBlockerCount: Int {
    mirCodeGenBlockerKinds.values.reduce(0, +)
  }

  func count(_ statement: MIRStatement) {
    switch statement {
    case .declare, .scopeEnter, .scopeExit, .debugSource:
      break
    case .assign(let place, let value):
      count(place)
      count(value)
    case .compoundAssign(let assignment):
      count(assignment.target)
      count(assignment.value)
    case .drop(let place):
      count(place)
    case .retain(let value),
         .release(let value),
         .evaluate(let value):
      count(value)
    }
  }

  func count(_ terminator: MIRTerminator) {
    switch terminator {
    case .goto, .unreachable:
      break
    case .branch:
      branchTerminatorCount += 1
    case .switchValue:
      switchTerminatorCount += 1
    case .returnValue:
      break
    }
  }

  private func count(_ place: MIRPlace) {
    switch place {
    case .local, .global:
      break
    case .field(let base, _):
      count(base)
    case .enumPayload(let base, _, _, _, _):
      count(base)
    case .deref(let base, _),
         .pointerElement(let base, _):
      count(base)
    }
  }

  private func count(_ value: MIRValue) {
    valueCount += 1
    switch value {
    case .operand:
      break
    case .placeRead(let place, _):
      count(place)
    case .binary, .unary, .cast:
      break
    case .intrinsic(let intrinsic):
      count(intrinsic)
    case .call(let call):
      callCount += 1
      for argument in call.arguments {
        count(argument)
      }
    case .aggregate(let aggregate):
      aggregateCount += 1
      for field in aggregate.fields {
        count(field)
      }
    case .enumCase(let construction):
      enumConstructionCount += 1
      for argument in construction.arguments {
        count(argument)
      }
    case .enumTag(let tag):
      count(tag.subject)
    case .traitObjectConversion(let conversion):
      count(conversion.inner)
    case .traitMethodCall(let call):
      count(call.receiver)
      for argument in call.arguments {
        count(argument)
      }
    case .ref(let place, _, _),
         .pointer(let place):
      count(place)
    case .lambda(let lambda):
      for source in lambda.captureSources {
        count(source)
      }
    }
  }

  private func count(_ intrinsic: MIRIntrinsic) {
    switch intrinsic {
    case .allocMemory(let count, _):
      self.count(count)
    case .deallocMemory(let ptr),
         .deinitMemory(let ptr),
         .takeMemory(let ptr, _):
      count(ptr)
    case .copyMemory(let dest, let source, let count),
         .moveMemory(let dest, let source, let count):
      self.count(dest)
      self.count(source)
      self.count(count)
    case .isUniqueMutable(let value),
          .refCount(let value),
         .downgradeRef(let value, _),
         .downgradeMutRef(let value, _),
         .upgradeRef(let value, _),
         .upgradeMutRef(let value, _):
      count(value)
    case .makeRef(let ptr, let owner, _),
         .makeMutRef(let ptr, let owner, _),
         .initMemory(let ptr, let owner):
      count(ptr)
      count(owner)
    case .nullPtr:
      break
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      count(outHandle)
      count(outTid)
      count(closure)
      count(stackSize)
    }
  }
}
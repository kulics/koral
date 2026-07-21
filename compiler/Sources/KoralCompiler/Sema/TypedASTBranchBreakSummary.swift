import Foundation

struct TypedBranchBreakSummary {
  var allTargets: Set<BranchBreakTargetId>
  var ownedTargets: Set<BranchBreakTargetId>

  static var empty: TypedBranchBreakSummary {
    TypedBranchBreakSummary(allTargets: [], ownedTargets: [])
  }

  var containsBranchBreak: Bool {
    !allTargets.isEmpty
  }

  mutating func formUnion(_ other: TypedBranchBreakSummary) {
    allTargets.formUnion(other.allTargets)
    ownedTargets.formUnion(other.ownedTargets)
  }

  func union(_ other: TypedBranchBreakSummary) -> TypedBranchBreakSummary {
    var result = self
    result.formUnion(other)
    return result
  }

  static func merged(_ summaries: [TypedBranchBreakSummary]) -> TypedBranchBreakSummary {
    summaries.reduce(into: .empty) { result, summary in
      result.formUnion(summary)
    }
  }
}

extension TypedExpressionNode {
  var branchBreakSummary: TypedBranchBreakSummary {
    switch self {
    case .blockExpression(let statements, _):
      return TypedBranchBreakSummary.merged(statements.map(\.branchBreakSummary))
    case .ifExpression(let condition, let thenBranch, let elseBranch, _):
      let branchSummary = thenBranch.branchBreakSummary.union(elseBranch?.branchBreakSummary ?? .empty)
      return TypedBranchBreakSummary(
        allTargets: condition.branchBreakSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .ifPatternExpression(let subject, _, _, let thenBranch, let elseBranch, _):
      let branchSummary = thenBranch.branchBreakSummary.union(elseBranch?.branchBreakSummary ?? .empty)
      return TypedBranchBreakSummary(
        allTargets: subject.branchBreakSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .whenExpression(let subject, let cases, _):
      let casesSummary = TypedBranchBreakSummary.merged(cases.map { $0.body.branchBreakSummary })
      return TypedBranchBreakSummary(
        allTargets: subject.branchBreakSummary.allTargets.union(casesSummary.allTargets),
        ownedTargets: casesSummary.ownedTargets
      )
    case .andExpression(let left, let right, _),
         .orExpression(let left, let right, _),
         .arithmeticExpression(let left, _, let right, _),
         .wrappingArithmeticExpression(let left, _, let right, _),
         .wrappingShiftExpression(let left, _, let right, _),
         .comparisonExpression(let left, _, let right, _),
         .bitwiseExpression(let left, _, let right, _):
      let allTargets = left.branchBreakSummary.allTargets.union(right.branchBreakSummary.allTargets)
      return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [])
    case .notExpression(let inner, _),
         .bitwiseNotExpression(let inner, _),
         .castExpression(let inner, _),
         .derefExpression(let inner, _),
         .referenceExpression(let inner, _),
         .ptrExpression(let inner, _),
         .memberPath(let inner, _),
         .traitObjectConversion(let inner, _, _, _, _),
         .isExpression(let inner, _, _),
         .isNotExpression(let inner, _, _):
      return TypedBranchBreakSummary(allTargets: inner.branchBreakSummary.allTargets, ownedTargets: [])
    case .call(let callee, let arguments, _):
      let allTargets = ([callee] + arguments).reduce(into: Set<BranchBreakTargetId>()) { result, expression in
        result.formUnion(expression.branchBreakSummary.allTargets)
      }
      return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [])
    case .genericCall(_, _, let arguments, _),
         .staticMethodCall(_, _, _, _, let arguments, _),
         .typeConstruction(_, _, let arguments, _),
         .enumConstruction(_, _, let arguments):
      let allTargets = arguments.reduce(into: Set<BranchBreakTargetId>()) { result, expression in
        result.formUnion(expression.branchBreakSummary.allTargets)
      }
      return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [])
    case .methodReference(let base, _, _, _, _),
         .traitMethodPlaceholder(_, _, let base, _, _):
      return TypedBranchBreakSummary(allTargets: base.branchBreakSummary.allTargets, ownedTargets: [])
    case .traitMethodCall(let receiver, _, _, _, let arguments, _):
      let allTargets = ([receiver] + arguments).reduce(into: Set<BranchBreakTargetId>()) { result, expression in
        result.formUnion(expression.branchBreakSummary.allTargets)
      }
      return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [])
    case .intrinsicCall(let intrinsic):
      return TypedBranchBreakSummary(allTargets: intrinsic.branchBreakSummary.allTargets, ownedTargets: [])
    case .interpolatedString(let parts, _):
      let allTargets = parts.reduce(into: Set<BranchBreakTargetId>()) { result, part in
        if case .expression(let expression) = part {
          result.formUnion(expression.branchBreakSummary.allTargets)
        }
      }
      return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [])
    case .lambdaExpression:
      return .empty
    case .integerLiteral,
         .floatLiteral,
         .stringLiteral,
         .booleanLiteral,
         .variable:
      return .empty
    }
  }

  var containsBranchBreak: Bool {
    branchBreakSummary.containsBranchBreak
  }

  var branchBreakTargetIDs: Set<BranchBreakTargetId> {
    branchBreakSummary.allTargets
  }

  var ownedBranchBreakTargetIDs: Set<BranchBreakTargetId> {
    branchBreakSummary.ownedTargets
  }
}

extension TypedStatementNode {
  var branchBreakSummary: TypedBranchBreakSummary {
    switch self {
    case .branchBreak(let target, let value):
      var allTargets: Set<BranchBreakTargetId> = [target]
      allTargets.formUnion(value.branchBreakSummary.allTargets)
      return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [target])
    case .variableDeclaration(_, let value, _):
      return TypedBranchBreakSummary(allTargets: value.branchBreakSummary.allTargets, ownedTargets: [])
    case .pairVariableDeclaration(_, let pairValue, _, _, _, _, _, _):
      return TypedBranchBreakSummary(allTargets: pairValue.branchBreakSummary.allTargets, ownedTargets: [])
    case .assignment(let target, _, let value):
      let allTargets = target.branchBreakSummary.allTargets.union(value.branchBreakSummary.allTargets)
      return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [])
    case .expression(let expression),
         .finally(let expression):
      return TypedBranchBreakSummary(allTargets: expression.branchBreakSummary.allTargets, ownedTargets: [])
    case .ifStatement(let condition, let thenBranch, let elseBranch):
      let branchSummary = thenBranch.branchBreakSummary.union(elseBranch?.branchBreakSummary ?? .empty)
      return TypedBranchBreakSummary(
        allTargets: condition.branchBreakSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .ifPatternStatement(let subject, _, _, let thenBranch, let elseBranch):
      let branchSummary = thenBranch.branchBreakSummary.union(elseBranch?.branchBreakSummary ?? .empty)
      return TypedBranchBreakSummary(
        allTargets: subject.branchBreakSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .whileStatement(let condition, let body):
      return TypedBranchBreakSummary(
        allTargets: condition.branchBreakSummary.allTargets.union(body.branchBreakSummary.allTargets),
        ownedTargets: body.branchBreakSummary.ownedTargets
      )
    case .whilePatternStatement(let subject, _, _, let body):
      return TypedBranchBreakSummary(
        allTargets: subject.branchBreakSummary.allTargets.union(body.branchBreakSummary.allTargets),
        ownedTargets: body.branchBreakSummary.ownedTargets
      )
    case .whenStatement(let subject, let cases):
      let casesSummary = TypedBranchBreakSummary.merged(cases.map { $0.body.branchBreakSummary })
      return TypedBranchBreakSummary(
        allTargets: subject.branchBreakSummary.allTargets.union(casesSummary.allTargets),
        ownedTargets: casesSummary.ownedTargets
      )
    case .return(let value):
      return TypedBranchBreakSummary(allTargets: value?.branchBreakSummary.allTargets ?? [], ownedTargets: [])
    case .break,
         .continue:
      return .empty
    }
  }

  var containsBranchBreak: Bool {
    branchBreakSummary.containsBranchBreak
  }

  var branchBreakTargetIDs: Set<BranchBreakTargetId> {
    branchBreakSummary.allTargets
  }

  var ownedBranchBreakTargetIDs: Set<BranchBreakTargetId> {
    branchBreakSummary.ownedTargets
  }
}

extension TypedIntrinsic {
  var branchBreakSummary: TypedBranchBreakSummary {
    let expressions: [TypedExpressionNode]
    switch self {
    case .allocMemory(let count, _):
      expressions = [count]
    case .deallocMemory(let ptr),
         .deinitMemory(let ptr),
         .takeMemory(let ptr):
      expressions = [ptr]
    case .copyMemory(let dest, let source, let count),
         .moveMemory(let dest, let source, let count):
      expressions = [dest, source, count]
    case .isUniqueMutable(let value),
          .refCount(let value),
         .downgradeRef(let value, _),
         .downgradeMutRef(let value, _),
         .upgradeRef(let value, _),
         .upgradeMutRef(let value, _):
      expressions = [value]
    case .makeRef(let ptr, let owner, _),
         .makeMutRef(let ptr, let owner, _),
         .initMemory(let ptr, let owner):
      expressions = [ptr, owner]
    case .nullPtr:
      expressions = []
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      expressions = [outHandle, outTid, closure, stackSize]
    }

    let allTargets = expressions.reduce(into: Set<BranchBreakTargetId>()) { result, expression in
      result.formUnion(expression.branchBreakSummary.allTargets)
    }
    return TypedBranchBreakSummary(allTargets: allTargets, ownedTargets: [])
  }
}
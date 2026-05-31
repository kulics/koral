import Foundation

struct TypedYieldSummary {
  var allTargets: Set<YieldTargetId>
  var ownedTargets: Set<YieldTargetId>

  static var empty: TypedYieldSummary {
    TypedYieldSummary(allTargets: [], ownedTargets: [])
  }

  var containsYield: Bool {
    !allTargets.isEmpty
  }

  mutating func formUnion(_ other: TypedYieldSummary) {
    allTargets.formUnion(other.allTargets)
    ownedTargets.formUnion(other.ownedTargets)
  }

  func union(_ other: TypedYieldSummary) -> TypedYieldSummary {
    var result = self
    result.formUnion(other)
    return result
  }

  static func merged(_ summaries: [TypedYieldSummary]) -> TypedYieldSummary {
    summaries.reduce(into: .empty) { result, summary in
      result.formUnion(summary)
    }
  }
}

extension TypedExpressionNode {
  var yieldSummary: TypedYieldSummary {
    switch self {
    case .blockExpression(let statements, _):
      return TypedYieldSummary.merged(statements.map(\.yieldSummary))
    case .ifExpression(let condition, let thenBranch, let elseBranch, _):
      let branchSummary = thenBranch.yieldSummary.union(elseBranch?.yieldSummary ?? .empty)
      return TypedYieldSummary(
        allTargets: condition.yieldSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .ifPatternExpression(let subject, _, _, let thenBranch, let elseBranch, _):
      let branchSummary = thenBranch.yieldSummary.union(elseBranch?.yieldSummary ?? .empty)
      return TypedYieldSummary(
        allTargets: subject.yieldSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .whenExpression(let subject, let cases, _):
      let casesSummary = TypedYieldSummary.merged(cases.map { $0.body.yieldSummary })
      return TypedYieldSummary(
        allTargets: subject.yieldSummary.allTargets.union(casesSummary.allTargets),
        ownedTargets: casesSummary.ownedTargets
      )
    case .andExpression(let left, let right, _),
         .orExpression(let left, let right, _),
         .arithmeticExpression(let left, _, let right, _),
         .wrappingArithmeticExpression(let left, _, let right, _),
         .wrappingShiftExpression(let left, _, let right, _),
         .comparisonExpression(let left, _, let right, _),
         .bitwiseExpression(let left, _, let right, _):
      let allTargets = left.yieldSummary.allTargets.union(right.yieldSummary.allTargets)
      return TypedYieldSummary(allTargets: allTargets, ownedTargets: [])
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
      return TypedYieldSummary(allTargets: inner.yieldSummary.allTargets, ownedTargets: [])
    case .call(let callee, let arguments, _):
      let allTargets = ([callee] + arguments).reduce(into: Set<YieldTargetId>()) { result, expression in
        result.formUnion(expression.yieldSummary.allTargets)
      }
      return TypedYieldSummary(allTargets: allTargets, ownedTargets: [])
    case .genericCall(_, _, let arguments, _),
         .staticMethodCall(_, _, _, _, let arguments, _),
         .typeConstruction(_, _, let arguments, _),
         .enumConstruction(_, _, let arguments):
      let allTargets = arguments.reduce(into: Set<YieldTargetId>()) { result, expression in
        result.formUnion(expression.yieldSummary.allTargets)
      }
      return TypedYieldSummary(allTargets: allTargets, ownedTargets: [])
    case .methodReference(let base, _, _, _, _),
         .traitMethodPlaceholder(_, _, let base, _, _):
      return TypedYieldSummary(allTargets: base.yieldSummary.allTargets, ownedTargets: [])
    case .traitMethodCall(let receiver, _, _, _, let arguments, _):
      let allTargets = ([receiver] + arguments).reduce(into: Set<YieldTargetId>()) { result, expression in
        result.formUnion(expression.yieldSummary.allTargets)
      }
      return TypedYieldSummary(allTargets: allTargets, ownedTargets: [])
    case .intrinsicCall(let intrinsic):
      return TypedYieldSummary(allTargets: intrinsic.yieldSummary.allTargets, ownedTargets: [])
    case .interpolatedString(let parts, _):
      let allTargets = parts.reduce(into: Set<YieldTargetId>()) { result, part in
        if case .expression(let expression) = part {
          result.formUnion(expression.yieldSummary.allTargets)
        }
      }
      return TypedYieldSummary(allTargets: allTargets, ownedTargets: [])
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

  var containsYield: Bool {
    yieldSummary.containsYield
  }

  var yieldTargetIDs: Set<YieldTargetId> {
    yieldSummary.allTargets
  }

  var ownedYieldTargetIDs: Set<YieldTargetId> {
    yieldSummary.ownedTargets
  }
}

extension TypedStatementNode {
  var yieldSummary: TypedYieldSummary {
    switch self {
    case .yield(let target, let value):
      var allTargets: Set<YieldTargetId> = [target]
      allTargets.formUnion(value.yieldSummary.allTargets)
      return TypedYieldSummary(allTargets: allTargets, ownedTargets: [target])
    case .variableDeclaration(_, let value, _):
      return TypedYieldSummary(allTargets: value.yieldSummary.allTargets, ownedTargets: [])
    case .pairVariableDeclaration(_, let pairValue, _, _, _, _, _, _):
      return TypedYieldSummary(allTargets: pairValue.yieldSummary.allTargets, ownedTargets: [])
    case .assignment(let target, _, let value):
      let allTargets = target.yieldSummary.allTargets.union(value.yieldSummary.allTargets)
      return TypedYieldSummary(allTargets: allTargets, ownedTargets: [])
    case .expression(let expression),
         .finally(let expression):
      return TypedYieldSummary(allTargets: expression.yieldSummary.allTargets, ownedTargets: [])
    case .ifStatement(let condition, let thenBranch, let elseBranch):
      let branchSummary = thenBranch.yieldSummary.union(elseBranch?.yieldSummary ?? .empty)
      return TypedYieldSummary(
        allTargets: condition.yieldSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .ifPatternStatement(let subject, _, _, let thenBranch, let elseBranch):
      let branchSummary = thenBranch.yieldSummary.union(elseBranch?.yieldSummary ?? .empty)
      return TypedYieldSummary(
        allTargets: subject.yieldSummary.allTargets.union(branchSummary.allTargets),
        ownedTargets: branchSummary.ownedTargets
      )
    case .whileStatement(let condition, let body):
      return TypedYieldSummary(
        allTargets: condition.yieldSummary.allTargets.union(body.yieldSummary.allTargets),
        ownedTargets: body.yieldSummary.ownedTargets
      )
    case .whilePatternStatement(let subject, _, _, let body):
      return TypedYieldSummary(
        allTargets: subject.yieldSummary.allTargets.union(body.yieldSummary.allTargets),
        ownedTargets: body.yieldSummary.ownedTargets
      )
    case .whenStatement(let subject, let cases):
      let casesSummary = TypedYieldSummary.merged(cases.map { $0.body.yieldSummary })
      return TypedYieldSummary(
        allTargets: subject.yieldSummary.allTargets.union(casesSummary.allTargets),
        ownedTargets: casesSummary.ownedTargets
      )
    case .return(let value):
      return TypedYieldSummary(allTargets: value?.yieldSummary.allTargets ?? [], ownedTargets: [])
    case .break,
         .continue:
      return .empty
    }
  }

  var containsYield: Bool {
    yieldSummary.containsYield
  }

  var yieldTargetIDs: Set<YieldTargetId> {
    yieldSummary.allTargets
  }

  var ownedYieldTargetIDs: Set<YieldTargetId> {
    yieldSummary.ownedTargets
  }
}

extension TypedIntrinsic {
  var yieldSummary: TypedYieldSummary {
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

    let allTargets = expressions.reduce(into: Set<YieldTargetId>()) { result, expression in
      result.formUnion(expression.yieldSummary.allTargets)
    }
    return TypedYieldSummary(allTargets: allTargets, ownedTargets: [])
  }
}
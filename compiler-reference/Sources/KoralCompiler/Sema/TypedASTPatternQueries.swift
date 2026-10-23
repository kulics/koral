import Foundation

extension TypedPattern {
  var bindingSymbols: [Symbol] {
    var symbols: [Symbol] = []
    var seenDefIds: Set<UInt64> = []
    collectBindingSymbols(into: &symbols, seenDefIds: &seenDefIds)
    return symbols
  }

  /// Whether this pattern matches every value of its type. A list matches
  /// everything only as the bare rest marker `[...]`: a fixed slot -- even an
  /// irrefutable one -- still constrains the length, so `[_, ...]` misses `[]`.
  var isIrrefutable: Bool {
    switch self {
    case .wildcard, .variable, .restPattern:
      return true
    case .listPattern(let elements, _):
      return elements.count == 1 && elements[0].isRestSlot
    case .structPattern(_, let elements):
      return elements.allSatisfy { $0.isIrrefutable }
    case .andPattern(let left, let right):
      return left.isIrrefutable && right.isIrrefutable
    case .orPattern(let left, let right):
      return left.isIrrefutable || right.isIrrefutable
    case .traitObjectType,
         .traitObjectTypeBinding,
         .weakBinding,
         .booleanLiteral,
         .integerLiteral,
         .floatLiteral,
         .stringLiteral,
         .comparisonPattern,
         .notPattern,
         .enumCase:
      return false
    }
  }

  /// Whether this pattern is the rest marker `...`.
  var isRestSlot: Bool {
    if case .restPattern = self { return true }
    return false
  }

  var introducesBinding: Bool {
    switch self {
    case .variable,
         .traitObjectTypeBinding,
         .weakBinding:
      return true
    case .traitObjectType:
      return false
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements),
         .listPattern(let elements, _):
      return elements.contains { $0.introducesBinding }
    case .andPattern(let left, let right),
         .orPattern(let left, let right):
      return left.introducesBinding || right.introducesBinding
    case .notPattern(let pattern):
      return pattern.introducesBinding
    case .wildcard,
         .booleanLiteral,
         .integerLiteral,
         .floatLiteral,
         .stringLiteral,
         .comparisonPattern,
         .restPattern:
      return false
    }
  }

  var isWildcardOnly: Bool {
    switch self {
    case .wildcard, .restPattern:
      // A rest slot is a wildcard for the slots it swallows: it needs no test.
      return true
    case .listPattern:
      // Only the bare rest marker needs no test; every other list shape has a
      // length to check.
      return isIrrefutable
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements):
      return elements.allSatisfy { $0.isWildcardOnly }
    case .booleanLiteral,
         .integerLiteral,
         .floatLiteral,
         .stringLiteral,
         .variable,
          .traitObjectType,
          .traitObjectTypeBinding,
          .weakBinding,
         .comparisonPattern,
         .andPattern,
         .orPattern,
         .notPattern:
      return false
    }
  }

  var isConditionlessPayloadPattern: Bool {
    switch self {
    case .wildcard,
         .variable,
         .restPattern:
      return true
    case .traitObjectType,
         .traitObjectTypeBinding:
      return false
    case .structPattern(_, let elements):
      return elements.allSatisfy { $0.isConditionlessPayloadPattern }
    case .listPattern:
      return isIrrefutable
    default:
      return false
    }
  }

  private func collectBindingSymbols(into symbols: inout [Symbol], seenDefIds: inout Set<UInt64>) {
    switch self {
    case .variable(let symbol),
         .weakBinding(let symbol):
      if seenDefIds.insert(symbol.defId.id).inserted {
        symbols.append(symbol)
      }
    case .traitObjectTypeBinding(let symbol, _):
      if seenDefIds.insert(symbol.defId.id).inserted {
        symbols.append(symbol)
      }
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements),
         .listPattern(let elements, _):
      for element in elements {
        element.collectBindingSymbols(into: &symbols, seenDefIds: &seenDefIds)
      }
    case .andPattern(let left, let right),
         .orPattern(let left, let right):
      left.collectBindingSymbols(into: &symbols, seenDefIds: &seenDefIds)
      right.collectBindingSymbols(into: &symbols, seenDefIds: &seenDefIds)
    case .notPattern(let inner):
      inner.collectBindingSymbols(into: &symbols, seenDefIds: &seenDefIds)
    case .wildcard,
         .booleanLiteral,
         .integerLiteral,
         .floatLiteral,
         .stringLiteral,
         .traitObjectType,
         .comparisonPattern,
         .restPattern:
      break
    }
  }
}
extension TypedPattern {
  /// Whether `pattern` contains an `or` that offers more than one reading.
  ///
  /// `not` is not a choice point -- a negation has no bindings to disagree
  /// on -- so nothing under it counts.
  var containsOr: Bool {
    switch self {
    case .orPattern:
      return true
    case .andPattern(let left, let right):
      return left.containsOr || right.containsOr
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements),
         .listPattern(let elements, _):
      return elements.contains { $0.containsOr }
    default:
      return false
    }
  }

  /// The or-free readings of `pattern`, in backtracking order.
  ///
  /// Every `or` is a choice point and one alternative fixes each choice to
  /// one side. Nested choices multiply (cartesian product, the leftmost
  /// choice varying slowest), so `Pair(p or q, r or s)` reads as the sequence
  /// `(p, r) (p, s) (q, r) (q, s)` -- an arm with a guard tries the leftmost
  /// reading first and falls through to the next reading when the guard
  /// refuses. A pattern with no `or` returns itself: the common case never
  /// rebuilds.
  var orAlternatives: [TypedPattern] {
    if !containsOr {
      return [self]
    }
    var out: [TypedPattern] = []
    collectOrAlternatives(into: &out)
    return out
  }

  private func collectOrAlternatives(into out: inout [TypedPattern]) {
    switch self {
    case .orPattern(let left, let right):
      left.collectOrAlternatives(into: &out)
      right.collectOrAlternatives(into: &out)
    case .andPattern(let left, let right):
      for leftAlt in left.orAlternatives {
        for rightAlt in right.orAlternatives {
          out.append(.andPattern(left: leftAlt, right: rightAlt))
        }
      }
    case .enumCase(let caseName, let tagIndex, let elements):
      for combo in combinationProduct(of: elements) {
        out.append(.enumCase(caseName: caseName, tagIndex: tagIndex, elements: combo))
      }
    case .structPattern(let typeName, let elements):
      for combo in combinationProduct(of: elements) {
        out.append(.structPattern(typeName: typeName, elements: combo))
      }
    case .listPattern(let elements, let ops):
      for combo in combinationProduct(of: elements) {
        out.append(.listPattern(elements: combo, ops: ops))
      }
    default:
      out.append(self)
    }
  }

  /// Every reading of an element list: the first element's choices vary
  /// slowest, so combinations come out in source order.
  private func combinationProduct(of elements: [TypedPattern]) -> [[TypedPattern]] {
    var combos: [[TypedPattern]] = [[]]
    for element in elements {
      var next: [[TypedPattern]] = []
      for combo in combos {
        for alt in element.orAlternatives {
          next.append(combo + [alt])
        }
      }
      combos = next
    }
    return combos
  }
}

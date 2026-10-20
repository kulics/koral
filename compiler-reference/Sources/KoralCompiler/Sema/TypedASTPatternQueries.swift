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
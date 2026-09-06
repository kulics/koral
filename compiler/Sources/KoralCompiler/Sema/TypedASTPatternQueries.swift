import Foundation

extension TypedPattern {
  var bindingSymbols: [Symbol] {
    var symbols: [Symbol] = []
    var seenDefIds: Set<UInt64> = []
    collectBindingSymbols(into: &symbols, seenDefIds: &seenDefIds)
    return symbols
  }

  var introducesBinding: Bool {
    switch self {
    case .variable,
         .traitObjectTypeBinding:
      return true
    case .traitObjectType:
      return false
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements):
      return elements.contains { $0.introducesBinding }
    case .andPattern(let left, let right),
         .orPattern(let left, let right):
      return left.introducesBinding || right.introducesBinding
    case .notPattern(let pattern):
      return pattern.introducesBinding
    case .wildcard,
         .booleanLiteral,
         .integerLiteral,
         .stringLiteral,
         .comparisonPattern:
      return false
    }
  }

  var isWildcardOnly: Bool {
    switch self {
    case .wildcard:
      return true
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements):
      return elements.allSatisfy { $0.isWildcardOnly }
    case .booleanLiteral,
         .integerLiteral,
         .stringLiteral,
         .variable,
          .traitObjectType,
          .traitObjectTypeBinding,
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
         .variable:
      return true
    case .traitObjectType,
         .traitObjectTypeBinding:
      return false
    case .structPattern(_, let elements):
      return elements.allSatisfy { $0.isConditionlessPayloadPattern }
    default:
      return false
    }
  }

  private func collectBindingSymbols(into symbols: inout [Symbol], seenDefIds: inout Set<UInt64>) {
    switch self {
    case .variable(let symbol):
      if seenDefIds.insert(symbol.defId.id).inserted {
        symbols.append(symbol)
      }
    case .traitObjectTypeBinding(let symbol, _):
      if seenDefIds.insert(symbol.defId.id).inserted {
        symbols.append(symbol)
      }
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements):
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
         .stringLiteral,
         .traitObjectType,
         .comparisonPattern:
      break
    }
  }
}
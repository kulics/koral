/// PatternSpace represents the set of values that have not yet been covered by patterns.
/// Used for exhaustiveness checking in pattern matching.
public indirect enum PatternSpace {
    /// Full space - all possible values of a type
    case full(Type)
    
    /// Empty space - no values remaining
    case empty
    
    /// Union type partial space - only specified cases remain uncovered
    /// Key is case name, value is list of field spaces for that case
    case unionCases(typeName: String, cases: [String: [PatternSpace]])
    
    /// Bool type partial space - remaining boolean values
    case boolValues(remaining: Set<Bool>)
    
    /// Constructor space - a single union case with field spaces
    case constructor(caseName: String, fields: [PatternSpace])
    
    /// Check if the space is empty (all values covered)
    public var isEmpty: Bool {
        switch self {
        case .empty:
            return true
        case .full:
            return false
        case .unionCases(_, let cases):
            return cases.isEmpty
        case .boolValues(let remaining):
            return remaining.isEmpty
        case .constructor(_, let fields):
            return fields.allSatisfy { $0.isEmpty }
        }
    }
    
    /// Get descriptions of missing cases for error messages
    public func missingCases() -> [String] {
        switch self {
        case .empty:
            return []
        case .full(let type):
            return [type.description]
        case .unionCases(_, let cases):
            return cases.keys.sorted().map { ".\($0)" }
        case .boolValues(let remaining):
            return remaining.map { String($0) }.sorted()
        case .constructor(let caseName, let fields):
            let fieldDescs = fields.flatMap { $0.missingCases() }
            if fieldDescs.isEmpty {
                return [".\(caseName)"]
            }
            return [".\(caseName)(\(fieldDescs.joined(separator: ", ")))"]
        }
    }
}


extension PatternSpace {
    /// Subtract the space covered by a pattern from this space.
    /// Returns the remaining uncovered space.
    public func subtract(_ pattern: TypedPattern, type: Type) -> PatternSpace {
        switch pattern {
        case .wildcard, .variable:
            // Wildcard and variable patterns cover everything
            return .empty
            
        case .booleanLiteral(let value):
            return subtractBoolLiteral(value, type: type)
            
        case .integerLiteral, .stringLiteral:
            // Literals on infinite types don't reduce the space meaningfully
            // (we still need a catchall for exhaustiveness)
            return self
            
        case .unionCase(let caseName, _, let elements):
            return subtractUnionCase(caseName: caseName, elements: elements, type: type)
            
        case .rangePattern:
            // Range patterns don't reduce the space meaningfully for exhaustiveness
            // (we still need a catchall for exhaustiveness on numeric types)
            return self
        }
    }
    
    private func subtractBoolLiteral(_ value: Bool, type: Type) -> PatternSpace {
        switch self {
        case .full(let t) where t == .bool:
            // Remove this value from full bool space
            var remaining: Set<Bool> = [true, false]
            remaining.remove(value)
            if remaining.isEmpty {
                return .empty
            }
            return .boolValues(remaining: remaining)
            
        case .boolValues(var remaining):
            remaining.remove(value)
            if remaining.isEmpty {
                return .empty
            }
            return .boolValues(remaining: remaining)
            
        default:
            return self
        }
    }
    
    private func subtractUnionCase(caseName: String, elements: [TypedPattern], type: Type) -> PatternSpace {
        switch self {
        case .full(let t):
            // Get all cases from the union type
            guard let allCases = getUnionCases(from: t) else {
                return self
            }
            
            // Check if all element patterns are wildcards/variables (cover entire case)
            let coversEntireCase = elements.allSatisfy { isWildcardOrVariable($0) }
            
            if coversEntireCase {
                // Remove this case entirely
                var remainingCases = allCases
                remainingCases.removeValue(forKey: caseName)
                if remainingCases.isEmpty {
                    return .empty
                }
                return .unionCases(typeName: t.description, cases: remainingCases)
            } else {
                // Partial coverage - need to track field spaces
                var remainingCases = allCases
                if let caseFields = remainingCases[caseName] {
                    let newFields = subtractFromFields(caseFields, patterns: elements)
                    if newFields.allSatisfy({ $0.isEmpty }) {
                        remainingCases.removeValue(forKey: caseName)
                    } else {
                        remainingCases[caseName] = newFields
                    }
                }
                if remainingCases.isEmpty {
                    return .empty
                }
                return .unionCases(typeName: t.description, cases: remainingCases)
            }
            
        case .unionCases(let typeName, var cases):
            guard cases[caseName] != nil else {
                return self // Case already covered
            }
            
            let coversEntireCase = elements.allSatisfy { isWildcardOrVariable($0) }
            
            if coversEntireCase {
                cases.removeValue(forKey: caseName)
            } else if let caseFields = cases[caseName] {
                let newFields = subtractFromFields(caseFields, patterns: elements)
                if newFields.allSatisfy({ $0.isEmpty }) {
                    cases.removeValue(forKey: caseName)
                } else {
                    cases[caseName] = newFields
                }
            }
            
            if cases.isEmpty {
                return .empty
            }
            return .unionCases(typeName: typeName, cases: cases)
            
        default:
            return self
        }
    }
    
    private func subtractFromFields(_ fields: [PatternSpace], patterns: [TypedPattern]) -> [PatternSpace] {
        guard fields.count == patterns.count else {
            return fields
        }
        
        var result: [PatternSpace] = []
        for (field, pattern) in zip(fields, patterns) {
            let fieldType: Type = extractTypeFromSpace(field)
            result.append(field.subtract(pattern, type: fieldType))
        }
        return result
    }
    
    private func extractTypeFromSpace(_ space: PatternSpace) -> Type {
        switch space {
        case .full(let t): return t
        case .boolValues: return .bool
        default: return .void // Fallback
        }
    }
    
    private func isWildcardOrVariable(_ pattern: TypedPattern) -> Bool {
        switch pattern {
        case .wildcard, .variable:
            return true
        default:
            return false
        }
    }
    
    private func getUnionCases(from type: Type) -> [String: [PatternSpace]]? {
        switch type {
        case .union(_, let cases, _):
            var result: [String: [PatternSpace]] = [:]
            for c in cases {
                result[c.name] = c.parameters.map { PatternSpace.full($0.type) }
            }
            return result
            
        case .genericUnion(_, _):
            // For generic unions, we need the resolved cases
            // This will be handled by the checker which has access to scope
            return nil
            
        default:
            return nil
        }
    }
    
    /// Create a full pattern space for a given type
    public static func fullSpace(for type: Type) -> PatternSpace {
        switch type {
        case .bool:
            return .boolValues(remaining: [true, false])
        case .union(_, let cases, _):
            var caseSpaces: [String: [PatternSpace]] = [:]
            for c in cases {
                caseSpaces[c.name] = c.parameters.map { PatternSpace.full($0.type) }
            }
            return .unionCases(typeName: type.description, cases: caseSpaces)
        default:
            return .full(type)
        }
    }
    
    /// Check if this space is covered by a pattern
    public func isCoveredBy(_ pattern: TypedPattern) -> Bool {
        switch pattern {
        case .wildcard, .variable:
            return true
        case .booleanLiteral(let value):
            if case .boolValues(let remaining) = self {
                return remaining == [value]
            }
            return false
        case .unionCase(let caseName, _, let elements):
            if case .unionCases(_, let cases) = self {
                if cases.count == 1, let fields = cases[caseName] {
                    return zip(fields, elements).allSatisfy { $0.isCoveredBy($1) }
                }
            }
            return false
        default:
            return false
        }
    }
}

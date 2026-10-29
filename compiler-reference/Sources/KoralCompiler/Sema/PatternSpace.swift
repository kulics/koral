/// PatternSpace represents the set of values that have not yet been covered by patterns.
/// Used for exhaustiveness checking in pattern matching.
public indirect enum PatternSpace {
    /// Full space - all possible values of a type
    case full(Type)
    
    /// Empty space - no values remaining
    case empty
    
    /// Enum type partial space - only specified cases remain uncovered
    /// Key is case name, value is list of field spaces for that case
    case enumCases(typeName: String, cases: [String: [PatternSpace]])
    
    /// Bool type partial space - remaining boolean values
    case boolValues(remaining: Set<Bool>)
    
    /// Constructor space - a single enum case with field spaces
    case constructor(caseName: String, fields: [PatternSpace])

    /// List space - which lengths are still fully uncovered.
    ///
    /// A length counts as covered only when EVERY list of that length matches
    /// a pattern already seen. Partial element coverage (`[1, ...]`) is not
    /// represented: such a length stays uncovered. That under-claims
    /// exhaustiveness, never over-claims it.
    case listLengths(type: Type, coveredExact: Set<Int>, coveredTailFrom: Int?)

    /// Check if the space is empty (all values covered)
    public var isEmpty: Bool {
        switch self {
        case .empty:
            return true
        case .full:
            return false
        case .enumCases(_, let cases):
            return cases.isEmpty
        case .boolValues(let remaining):
            return remaining.isEmpty
        case .constructor(_, let fields):
            return fields.allSatisfy { $0.isEmpty }
        case .listLengths(_, let coveredExact, let coveredTailFrom):
            guard let tail = coveredTailFrom else {
                // Without a rest pattern reaching to the end, some length
                // beyond the largest exact one stays uncovered.
                return false
            }
            for length in 0..<tail where !coveredExact.contains(length) {
                return false
            }
            return true
        }
    }

    public func structurallyEquals(_ other: PatternSpace) -> Bool {
        switch (self, other) {
        case (.empty, .empty):
            return true
        case (.full(let lhs), .full(let rhs)):
            return lhs == rhs
        case (.boolValues(let lhs), .boolValues(let rhs)):
            return lhs == rhs
        case (.constructor(let lhsName, let lhsFields), .constructor(let rhsName, let rhsFields)):
            guard lhsName == rhsName, lhsFields.count == rhsFields.count else {
                return false
            }
            return zip(lhsFields, rhsFields).allSatisfy { $0.structurallyEquals($1) }
        case (.enumCases(let lhsTypeName, let lhsCases), .enumCases(let rhsTypeName, let rhsCases)):
            guard lhsTypeName == rhsTypeName,
                  Set(lhsCases.keys) == Set(rhsCases.keys) else {
                return false
            }
            for key in lhsCases.keys {
                guard let lhsFields = lhsCases[key],
                      let rhsFields = rhsCases[key],
                      lhsFields.count == rhsFields.count else {
                    return false
                }
                if !zip(lhsFields, rhsFields).allSatisfy({ $0.structurallyEquals($1) }) {
                    return false
                }
            }
            return true
        case (.listLengths(let lhsType, let lhsExact, let lhsTail),
              .listLengths(let rhsType, let rhsExact, let rhsTail)):
            return lhsType == rhsType && lhsExact == rhsExact && lhsTail == rhsTail
        default:
            return false
        }
    }

    /// Get descriptions of missing cases for error messages
    public func missingCases() -> [String] {
        switch self {
        case .empty:
            return []
        case .full(let type):
            return [type.description]
        case .enumCases:
            return missingPatternFragments()
        case .boolValues(let remaining):
            return remaining.map { String($0) }.sorted()
        case .constructor(let caseName, let fields):
            return Self.renderConstructorMissing(caseName: caseName, fields: fields)
        case .listLengths(let type, let coveredExact, let coveredTailFrom):
            return Self.renderMissingListLengths(type: type, coveredExact: coveredExact, coveredTailFrom: coveredTailFrom)
        }
    }

    /// The uncovered list shapes, as the patterns that would cover them: one
    /// exact-length pattern per uncovered length below the tail, and one
    /// rest pattern for whatever runs past it.
    private static func renderMissingListLengths(
        type: Type,
        coveredExact: Set<Int>,
        coveredTailFrom: Int?
    ) -> [String] {
        if coveredExact.isEmpty && coveredTailFrom == nil {
            return [type.description]
        }
        let tailStart = coveredTailFrom ?? ((coveredExact.max() ?? -1) + 1)
        var result: [String] = []
        for length in 0..<tailStart where !coveredExact.contains(length) {
            result.append(Self.renderListShape(slots: length, rest: false))
        }
        if coveredTailFrom == nil {
            result.append(Self.renderListShape(slots: tailStart, rest: true))
        }
        return result
    }

    private static func renderListShape(slots: Int, rest: Bool) -> String {
        var parts = Array(repeating: "_", count: slots)
        if rest {
            parts.append("...")
        }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    private func missingPatternFragments() -> [String] {
        switch self {
        case .empty:
            return []
        case .full:
            return ["_"]
        case .boolValues(let remaining):
            if remaining == Set([true, false]) {
                return ["_"]
            }
            return remaining.map { String($0) }.sorted()
        case .constructor(let caseName, let fields):
            return Self.renderConstructorMissing(caseName: caseName, fields: fields)
        case .enumCases(_, let cases):
            return cases.keys.sorted().flatMap { caseName in
                Self.renderConstructorMissing(caseName: caseName, fields: cases[caseName] ?? [])
            }
        case .listLengths(let type, let coveredExact, let coveredTailFrom):
            return Self.renderMissingListLengths(type: type, coveredExact: coveredExact, coveredTailFrom: coveredTailFrom)
        }
    }

    private static func renderConstructorMissing(caseName: String, fields: [PatternSpace]) -> [String] {
        let combinations = combineFieldMissingCases(fields.map { $0.missingPatternFragments() })
        if combinations.isEmpty {
            return [".\(caseName)"]
        }
        return combinations.map { ".\(caseName)(\($0.joined(separator: ", ")))" }
    }

    private static func combineFieldMissingCases(_ fieldFragments: [[String]]) -> [[String]] {
        guard !fieldFragments.isEmpty else {
            return []
        }

        var result: [[String]] = [[]]
        for fragments in fieldFragments {
            guard !fragments.isEmpty else {
                return []
            }
            var next: [[String]] = []
            for prefix in result {
                for fragment in fragments {
                    next.append(prefix + [fragment])
                }
            }
            result = next
        }
        return result
    }
}


extension PatternSpace {
    /// Subtract the space covered by a pattern from this space.
    /// Returns the remaining uncovered space.
    public func subtract(_ pattern: TypedPattern, type: Type, context: CompilerContext) -> PatternSpace {
        switch pattern {
        case .wildcard, .variable:
            // Wildcard and variable patterns cover everything
            return .empty
        case .weakBinding:
            // `?name` is refutable: it covers the alive case but not the dead
            // case. Subtracting it leaves the dead case uncovered.
            return self
        case .traitObjectType, .traitObjectTypeBinding:
            return self
            
        case .booleanLiteral(let value):
            return subtractBoolLiteral(value, type: type)
            
        case .integerLiteral, .floatLiteral, .stringLiteral, .nullLiteral:
            // Literals on infinite types don't reduce the space meaningfully
            // (we still need a catchall for exhaustiveness)
            return self
            
        case .enumCase(let caseName, _, let elements):
            return subtractEnumCase(caseName: caseName, elements: elements, type: type, context: context)
            
        case .comparisonPattern:
            // Comparison patterns don't reduce the space meaningfully for exhaustiveness
            // (we still need a catchall for exhaustiveness on numeric types)
            return self
            
        case .andPattern(let left, let right):
            // `and` covers the INTERSECTION of its sides, never the union.
            // Subtracting both over-claims: `.A(x) and y` would eat the whole
            // enum and make the next arm look unreachable. Only a side that is
            // itself total pins the coverage down to the other side; otherwise
            // claim nothing.
            if left.isIrrefutable {
                return subtract(right, type: type, context: context)
            } else if right.isIrrefutable {
                return subtract(left, type: type, context: context)
            }
            return self
            
        case .orPattern(let left, let right):
            // Or pattern: subtract both sub-patterns (enum of covered spaces)
            let afterLeft = self.subtract(left, type: type, context: context)
            return afterLeft.subtract(right, type: type, context: context)
            
        case .notPattern:
            // Not patterns don't reduce the space meaningfully for exhaustiveness
            // (they exclude values rather than covering them)
            return self
            
        case .structPattern(_, let elements):
            // Struct pattern: if all sub-patterns are wildcards/variables, covers everything
            if elements.allSatisfy({ isWildcardOrVariable($0) }) {
                return .empty
            }
            // Otherwise, doesn't reduce the space meaningfully
            return self

        case .listPattern(let elements, _):
            return subtractListPattern(elements, type: type)

        case .restPattern:
            // A rest slot is expanded away by its enclosing element list before
            // any space is subtracted; standing alone it covers nothing.
            return self
        }
    }

    /// Subtract the lists matched by `[p1, ..., pk]` / `[p1, ..., pk, ...]`.
    ///
    /// Only lengths whose slots are ALL irrefutable are claimed: a refutable
    /// slot (`[1, ...]`) may match nothing at a length, so claiming it would
    /// both close the space early and make a later arm look unreachable.
    private func subtractListPattern(_ elements: [TypedPattern], type: Type) -> PatternSpace {
        let fixed = elements.filter { !$0.isRestSlot }
        guard fixed.allSatisfy({ $0.isIrrefutable }) else {
            return self
        }
        let hasRest = elements.contains { $0.isRestSlot }

        var coveredExact: Set<Int> = []
        var coveredTailFrom: Int? = nil
        switch self {
        case .full:
            break
        case .listLengths(_, let exact, let tail):
            coveredExact = exact
            coveredTailFrom = tail
        default:
            return self
        }

        if hasRest {
            let threshold = fixed.count
            if let existing = coveredTailFrom {
                coveredTailFrom = min(existing, threshold)
            } else {
                coveredTailFrom = threshold
            }
        } else {
            coveredExact.insert(fixed.count)
        }

        let next = PatternSpace.listLengths(type: type, coveredExact: coveredExact, coveredTailFrom: coveredTailFrom)
        return next.isEmpty ? .empty : next
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
    
    private func subtractEnumCase(
        caseName: String,
        elements: [TypedPattern],
        type: Type,
        context: CompilerContext
    ) -> PatternSpace {
        switch self {
        case .full(let t):
            // Get all cases from the enum type
            guard let allCases = getEnumCases(from: t, context: context) else {
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
                return .enumCases(typeName: t.description, cases: remainingCases)
            } else {
                // Partial coverage - need to track field spaces
                var remainingCases = allCases
                if let caseFields = remainingCases[caseName] {
                    let newFields = subtractFromFields(caseFields, patterns: elements, context: context)
                    if newFields.allSatisfy({ $0.isEmpty }) {
                        remainingCases.removeValue(forKey: caseName)
                    } else {
                        remainingCases[caseName] = newFields
                    }
                }
                if remainingCases.isEmpty {
                    return .empty
                }
                return .enumCases(typeName: t.description, cases: remainingCases)
            }
            
        case .enumCases(let typeName, var cases):
            guard cases[caseName] != nil else {
                return self // Case already covered
            }
            
            let coversEntireCase = elements.allSatisfy { isWildcardOrVariable($0) }
            
            if coversEntireCase {
                cases.removeValue(forKey: caseName)
            } else if let caseFields = cases[caseName] {
                let newFields = subtractFromFields(caseFields, patterns: elements, context: context)
                if newFields.allSatisfy({ $0.isEmpty }) {
                    cases.removeValue(forKey: caseName)
                } else {
                    cases[caseName] = newFields
                }
            }
            
            if cases.isEmpty {
                return .empty
            }
            return .enumCases(typeName: typeName, cases: cases)
            
        default:
            return self
        }
    }
    
    private func subtractFromFields(
        _ fields: [PatternSpace],
        patterns: [TypedPattern],
        context: CompilerContext
    ) -> [PatternSpace] {
        guard fields.count == patterns.count else {
            return fields
        }
        
        var result: [PatternSpace] = []
        for (field, pattern) in zip(fields, patterns) {
            let fieldType: Type = extractTypeFromSpace(field)
            result.append(field.subtract(pattern, type: fieldType, context: context))
        }
        return result
    }
    
    private func extractTypeFromSpace(_ space: PatternSpace) -> Type {
        switch space {
        case .full(let t): return t
        case .listLengths(let t, _, _): return t
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
    
    private func getEnumCases(from type: Type, context: CompilerContext) -> [String: [PatternSpace]]? {
        switch type {
        case .`enum`(let defId):
            var result: [String: [PatternSpace]] = [:]
            for c in context.getEnumCases(defId) ?? [] {
                result[c.name] = c.parameters.map { PatternSpace.full($0.type) }
            }
            return result

        case .genericEnum(let templateDefId, let typeArgs):
            // The type carries the template's DECLARATION; the instance's type
            // arguments substitute into the payload field types, so `Wrap(v T)`
            // in `G2[Bool]` is `Wrap(v Bool)` -- the same reading the
            // generic-enum SUBJECT path gives its cases. Reading the
            // declaration's unsubstituted fields here made a nested
            // generic-enum payload subtract nothing and the next arm look
            // unreachable.
            guard templateDefId.isValid, let defId = Optional(templateDefId) else {
                return nil
            }
            let paramNames: [String]
            if let info = context.defIdMap.getGenericEnumTemplateInfo(templateDefId) {
                paramNames = info.typeParameters.map { $0.name }
            } else {
                paramNames = []
            }
            var result: [String: [PatternSpace]] = [:]
            for c in context.getEnumCases(defId) ?? [] {
                result[c.name] = c.parameters.map {
                    PatternSpace.full(
                        PatternSpace.substituteInstanceTypeArgs($0.type, paramNames: paramNames, args: typeArgs))
                }
            }
            return result

        default:
            return nil
        }
    }

    /// Substitute a generic instance's type arguments for its parameter names
    /// inside a declared payload type: `T` becomes `Bool` in `G2[Bool]`'s
    /// `Wrap(v T)`.
    private static func substituteInstanceTypeArgs(
        _ type: Type,
        paramNames: [String],
        args: [Type]
    ) -> Type {
        switch type {
        case .genericParameter(let name):
            if let index = paramNames.firstIndex(of: name), index < args.count {
                return args[index]
            }
            return type
        case .genericStruct(let templateDefId, let innerArgs):
            return .genericStruct(
                templateDefId: templateDefId,
                args: innerArgs.map { substituteInstanceTypeArgs($0, paramNames: paramNames, args: args) })
        case .genericEnum(let templateDefId, let innerArgs):
            return .genericEnum(
                templateDefId: templateDefId,
                args: innerArgs.map { substituteInstanceTypeArgs($0, paramNames: paramNames, args: args) })
        case .pointer(let inner):
            return .pointer(element: substituteInstanceTypeArgs(inner, paramNames: paramNames, args: args))
        case .mutablePointer(let inner):
            return .mutablePointer(element: substituteInstanceTypeArgs(inner, paramNames: paramNames, args: args))
        case .reference(let inner):
            return .reference(inner: substituteInstanceTypeArgs(inner, paramNames: paramNames, args: args))
        case .mutableReference(let inner):
            return .mutableReference(inner: substituteInstanceTypeArgs(inner, paramNames: paramNames, args: args))
        default:
            return type
        }
    }

    /// The declared field spaces of one case -- the lookup `subtract` performs
    /// -- so the unreachable scan can ask the same question before it trusts a
    /// subtraction.
    func caseFieldSpaces(
        for caseName: String,
        type: Type,
        context: CompilerContext
    ) -> [PatternSpace]? {
        switch self {
        case .full(let t):
            return getEnumCases(from: t, context: context)?[caseName]
        case .enumCases(_, let cases):
            return cases[caseName]
        default:
            return nil
        }
    }
    
    /// Create a full pattern space for a given type
    public static func fullSpace(for type: Type, context: CompilerContext) -> PatternSpace {
        switch type {
        case .bool:
            return .boolValues(remaining: [true, false])
        case .`enum`(let defId):
            var caseSpaces: [String: [PatternSpace]] = [:]
            for c in context.getEnumCases(defId) ?? [] {
                caseSpaces[c.name] = c.parameters.map { PatternSpace.full($0.type) }
            }
            return .enumCases(typeName: type.description, cases: caseSpaces)
        default:
            return .full(type)
        }
    }
    
    /// Check if this space is covered by a pattern
    public func isCoveredBy(_ pattern: TypedPattern) -> Bool {
        switch pattern {
        case .wildcard, .variable:
            return true
        case .weakBinding:
            // Refutable: does not cover the dead case.
            return false
        case .traitObjectType, .traitObjectTypeBinding:
            return false
        case .booleanLiteral(let value):
            if case .boolValues(let remaining) = self {
                return remaining == [value]
            }
            return false
        case .integerLiteral, .floatLiteral, .stringLiteral, .nullLiteral:
            // Literals don't cover the entire space
            return false
        case .enumCase(let caseName, _, let elements):
            if case .enumCases(_, let cases) = self {
                if cases.count == 1, let fields = cases[caseName] {
                    return zip(fields, elements).allSatisfy { $0.isCoveredBy($1) }
                }
            }
            return false
        case .comparisonPattern:
            // Comparison patterns don't cover the entire space
            return false
        case .andPattern(let left, let right):
            // And pattern covers if both sub-patterns cover
            return self.isCoveredBy(left) && self.isCoveredBy(right)
        case .orPattern(let left, let right):
            // Or pattern covers if either sub-pattern covers
            return self.isCoveredBy(left) || self.isCoveredBy(right)
        case .notPattern:
            // Not patterns don't cover the entire space
            return false
        case .structPattern(_, let elements):
            // Struct pattern covers if all sub-patterns are wildcards/variables
            return elements.allSatisfy { isCoveredBy($0) }
        case .restPattern:
            // A rest slot constrains nothing: it swallows whatever was not
            // written, exactly like a wildcard.
            return true
        case .listPattern(let elements, _):
            // Only the bare rest marker `[...]` covers every list; a fixed slot
            // still constrains the length.
            return elements.count == 1 && elements[0].isRestSlot
        }
    }
}

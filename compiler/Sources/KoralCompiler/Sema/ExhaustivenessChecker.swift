/// ExhaustivenessChecker verifies that pattern matching in `when` expressions
/// covers all possible values and detects unreachable patterns.
public struct ExhaustivenessChecker {
    private let subjectType: Type
    private let patterns: [TypedPattern]
    private let currentLine: Int
    private let context: CompilerContext
    private var currentSpan: SourceSpan {
        SourceSpan(location: SourceLocation(line: currentLine, column: 1))
    }
    
    /// Resolved enum cases for generic enum types
    private let resolvedEnumCases: [EnumCase]?
    
    public init(
        subjectType: Type,
        patterns: [TypedPattern],
        currentLine: Int,
        resolvedEnumCases: [EnumCase]? = nil,
        context: CompilerContext
    ) {
        self.subjectType = subjectType
        self.patterns = patterns
        self.currentLine = currentLine
        self.resolvedEnumCases = resolvedEnumCases
        self.context = context
    }
    
    /// Perform exhaustiveness checking
    /// - Throws: SemanticError if patterns are not exhaustive or contain unreachable patterns
    public func check() throws {
        // First check for unreachable patterns
        try checkUnreachablePatterns()
        
        // Then check for exhaustiveness
        try checkExhaustiveness()
    }
}


// MARK: - Unreachable Pattern Detection

extension ExhaustivenessChecker {
    private func initialFinitePatternSpace() -> PatternSpace? {
        switch subjectType {
        case .`enum`:
            return .fullSpace(for: subjectType, context: context)
        case .genericEnum(let templateName, _):
            guard let resolved = resolvedEnumCases else {
                return nil
            }
            var cases: [String: [PatternSpace]] = [:]
            for enumCase in resolved {
                cases[enumCase.name] = enumCase.parameters.map { PatternSpace.fullSpace(for: $0.type, context: context) }
            }
            return .enumCases(typeName: templateName, cases: cases)
        case .bool:
            return .fullSpace(for: .bool, context: context)
        default:
            return nil
        }
    }

    /// Check for unreachable patterns (patterns that can never match)
    private func checkUnreachablePatterns() throws {
        var catchallIndex: Int? = nil
        var catchallPattern: String? = nil
        var coveredTraitObjectTypes: Set<String> = []
        var remainingFiniteSpace = initialFinitePatternSpace()
        
        for (index, pattern) in patterns.enumerated() {
            // Check if we already have a catchall pattern
            if let catchallIdx = catchallIndex {
                throw SemanticError(
                    .unreachablePattern(
                        pattern: pattern.description,
                        reason: "already covered by '\(catchallPattern ?? "_")' at position \(catchallIdx + 1)"
                    ),
                    span: currentSpan
                )
            }

            if let finiteSpace = remainingFiniteSpace {
                let reduced = finiteSpace.subtract(pattern, type: subjectType, context: context)
                if reduced.structurallyEquals(finiteSpace) {
                    throw SemanticError(
                        .unreachablePattern(
                            pattern: pattern.description,
                            reason: "already covered by previous patterns"
                        ),
                        span: currentSpan
                    )
                }
                remainingFiniteSpace = reduced
            }
            
            // Check if this is a catchall pattern
            if isCatchallPattern(pattern) {
                catchallIndex = index
                catchallPattern = pattern.description
                continue
            }

            let traitObjectTypesInPattern = collectTraitObjectTypeKeys(pattern)
            if !traitObjectTypesInPattern.isEmpty {
                let alreadyCovered = traitObjectTypesInPattern.intersection(coveredTraitObjectTypes)
                if let repeated = alreadyCovered.first {
                    throw SemanticError(
                        .unreachablePattern(
                            pattern: pattern.description,
                            reason: "implementation type pattern '\(repeated)' is already covered"
                        ),
                        span: currentSpan
                    )
                }
                coveredTraitObjectTypes.formUnion(traitObjectTypesInPattern)
            }
        }
    }

    private func collectTraitObjectTypeKeys(_ pattern: TypedPattern) -> Set<String> {
        var keys: Set<String> = []
        collectTraitObjectTypeKeys(pattern, into: &keys)
        return keys
    }
    
    private func isCatchallPattern(_ pattern: TypedPattern) -> Bool {
        switch pattern {
        case .wildcard, .variable:
            return true
        case .traitObjectType, .traitObjectTypeBinding:
            return false
        case .comparisonPattern:
            // Comparison patterns are not catchall - they only match values within the comparison
            return false
        case .andPattern(let left, let right):
            // And pattern is catchall only if both sub-patterns are catchall
            return isCatchallPattern(left) && isCatchallPattern(right)
        case .orPattern(let left, let right):
            // Or pattern is catchall if either sub-pattern is catchall
            return isCatchallPattern(left) || isCatchallPattern(right)
        case .notPattern:
            // Not patterns are never catchall (they exclude values)
            return false
        case .structPattern(_, let elements):
            // Struct pattern is catchall if all sub-patterns are catchall
            return elements.allSatisfy { isCatchallPattern($0) }
        default:
            return false
        }
    }
    
}


// MARK: - Exhaustiveness Checking

extension ExhaustivenessChecker {
    /// Check that all possible values are covered by the patterns
    private func checkExhaustiveness() throws {
        if var remaining = initialFinitePatternSpace() {
            for pattern in patterns {
                remaining = remaining.subtract(pattern, type: subjectType, context: context)
            }
            if !remaining.isEmpty {
                let typeName: String = {
                    switch subjectType {
                    case .`enum`(let defId):
                        return context.getName(defId) ?? subjectType.description
                    case .genericEnum(let templateName, _):
                        return templateName
                    case .bool:
                        return "Bool"
                    default:
                        return subjectType.description
                    }
                }()
                throw SemanticError(
                    .nonExhaustiveMatch(type: typeName, missing: remaining.missingCases()),
                    span: currentSpan
                )
            }
            return
        }

        // Check if we have a catchall pattern (wildcard or variable binding)
        let hasCatchall = patterns.contains { isCatchallPattern($0) }
        
        // Handle different types
        switch subjectType {
        case .`enum`(let defId):
            let typeName = context.getName(defId) ?? subjectType.description
            let cases = context.getEnumCases(defId) ?? []
            try checkEnumExhaustiveness(typeName: typeName, cases: cases, hasCatchall: hasCatchall)
            
        case .genericEnum(let templateName, _):
            // Use resolved cases if available
            if let resolved = resolvedEnumCases {
                try checkEnumExhaustiveness(typeName: templateName, cases: resolved, hasCatchall: hasCatchall)
            } else if hasCatchall {
                // If we have a catchall, it's exhaustive
                return
            } else {
                // Can't check without resolved cases, require catchall
                throw SemanticError(
                    .missingCatchallPattern(type: subjectType.description),
                    span: currentSpan
                )
            }
            
        case .bool:
            try checkBoolExhaustiveness(hasCatchall: hasCatchall)
            
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64:
            // Numeric types have infinite domain - require catchall
            if !hasCatchall {
                throw SemanticError(
                    .missingCatchallPattern(type: subjectType.description),
                    span: currentSpan
                )
            }
            
        case .structure(let defId):
            // Struct types require catchall (can't enumerate all values)
            if !hasCatchall {
                let name = context.getName(defId) ?? subjectType.description
                throw SemanticError(
                    .missingCatchallPattern(type: name),
                    span: currentSpan
                )
            }
            
        default:
            // For other types (String, etc.), require catchall
            if !hasCatchall && !isStringType(subjectType) {
                throw SemanticError(
                    .missingCatchallPattern(type: subjectType.description),
                    span: currentSpan
                )
            } else if isStringType(subjectType) && !hasCatchall {
                throw SemanticError(
                    .missingCatchallPattern(type: "String"),
                    span: currentSpan
                )
            }
        }
    }
    
    private func checkEnumExhaustiveness(typeName: String, cases: [EnumCase], hasCatchall: Bool) throws {
        if hasCatchall {
            return // Catchall covers everything
        }
        
        // Collect all covered case names (including from or patterns)
        var coveredCases: Set<String> = []
        for pattern in patterns {
            collectEnumCasesFromPattern(pattern, into: &coveredCases)
        }
        
        // Find missing cases
        let allCaseNames = Set(cases.map { $0.name })
        let missingCases = allCaseNames.subtracting(coveredCases)
        
        if !missingCases.isEmpty {
            let sortedMissing = missingCases.sorted().map { ".\($0)" }
            throw SemanticError(
                .nonExhaustiveMatch(type: typeName, missing: sortedMissing),
                span: currentSpan
            )
        }
    }
    
    /// Recursively collect enum case names from a pattern, handling or patterns
    private func collectEnumCasesFromPattern(_ pattern: TypedPattern, into coveredCases: inout Set<String>) {
        switch pattern {
        case .enumCase(let caseName, _, _):
            coveredCases.insert(caseName)
        case .orPattern(let left, let right):
            // Recursively collect from both sides of or pattern
            collectEnumCasesFromPattern(left, into: &coveredCases)
            collectEnumCasesFromPattern(right, into: &coveredCases)
        default:
            break
        }
    }

    private func collectTraitObjectTypeKeys(_ pattern: TypedPattern, into keys: inout Set<String>) {
        switch pattern {
        case .traitObjectType(let targetType):
            keys.insert(targetType.description)
        case .traitObjectTypeBinding(_, let targetType):
            keys.insert(targetType.description)
        case .orPattern(let left, let right):
            collectTraitObjectTypeKeys(left, into: &keys)
            collectTraitObjectTypeKeys(right, into: &keys)
        default:
            break
        }
    }
    
    private func checkBoolExhaustiveness(hasCatchall: Bool) throws {
        if hasCatchall {
            return
        }
        
        // Collect covered boolean values
        var coveredValues: Set<Bool> = []
        for pattern in patterns {
            if case .booleanLiteral(let value) = pattern {
                coveredValues.insert(value)
            }
        }
        
        // Check if both true and false are covered
        let missingValues = Set([true, false]).subtracting(coveredValues)
        
        if !missingValues.isEmpty {
            let sortedMissing = missingValues.map { String($0) }.sorted()
            throw SemanticError(
                .nonExhaustiveMatch(type: "Bool", missing: sortedMissing),
                span: currentSpan
            )
        }
    }
    
    private func isStringType(_ type: Type) -> Bool {
        if case .structure(let defId) = type {
            return context.getName(defId) == "String"
        }
        return false
    }
}

/// ExhaustivenessChecker verifies that pattern matching in `when` expressions
/// covers all possible values and detects unreachable patterns.
public struct ExhaustivenessChecker {
    private let subjectType: Type
    private let patterns: [TypedPattern]
    private let currentLine: Int
    private let context: CompilerContext
    
    /// Resolved union cases for generic union types
    private let resolvedUnionCases: [UnionCase]?
    
    public init(
        subjectType: Type,
        patterns: [TypedPattern],
        currentLine: Int,
        resolvedUnionCases: [UnionCase]? = nil,
        context: CompilerContext
    ) {
        self.subjectType = subjectType
        self.patterns = patterns
        self.currentLine = currentLine
        self.resolvedUnionCases = resolvedUnionCases
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
    /// Check for unreachable patterns (patterns that can never match)
    private func checkUnreachablePatterns() throws {
        var coveredSpace = PatternSpace.empty
        var catchallIndex: Int? = nil
        var catchallPattern: String? = nil
        var coveredUnionCases: Set<String> = []
        
        for (index, pattern) in patterns.enumerated() {
            // Check if we already have a catchall pattern
            if let catchallIdx = catchallIndex {
                throw SemanticError(
                    .unreachablePattern(
                        pattern: pattern.description,
                        reason: "already covered by '\(catchallPattern ?? "_")' at position \(catchallIdx + 1)"
                    ),
                    line: currentLine
                )
            }
            
            // Check if this is a catchall pattern
            if isCatchallPattern(pattern) {
                catchallIndex = index
                catchallPattern = pattern.description
                continue
            }
            
            // For union types, check if all cases are already covered
            // Handle both direct union cases and or patterns containing union cases
            let casesInPattern = collectUnionCasesFromPatternSet(pattern)
            
            if !casesInPattern.isEmpty {
                // Check if any case in this pattern was already covered
                let alreadyCovered = casesInPattern.intersection(coveredUnionCases)
                if !alreadyCovered.isEmpty {
                    throw SemanticError(
                        .unreachablePattern(
                            pattern: pattern.description,
                            reason: "case '\(alreadyCovered.first!)' is already covered"
                        ),
                        line: currentLine
                    )
                }
                
                // Check if all union cases are covered (making this unreachable)
                if isUnionFullyCovered(coveredCases: coveredUnionCases) {
                    throw SemanticError(
                        .unreachablePattern(
                            pattern: pattern.description,
                            reason: "all union cases are already covered"
                        ),
                        line: currentLine
                    )
                }
                
                coveredUnionCases.formUnion(casesInPattern)
            }
            
            // Update covered space
            coveredSpace = updateCoveredSpace(coveredSpace, with: pattern)
        }
    }
    
    /// Collect union case names from a pattern into a Set (for unreachable pattern detection)
    private func collectUnionCasesFromPatternSet(_ pattern: TypedPattern) -> Set<String> {
        var cases: Set<String> = []
        collectUnionCasesFromPattern(pattern, into: &cases)
        return cases
    }
    
    private func isCatchallPattern(_ pattern: TypedPattern) -> Bool {
        switch pattern {
        case .wildcard, .variable:
            return true
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
        default:
            return false
        }
    }
    
    private func isUnionFullyCovered(coveredCases: Set<String>) -> Bool {
        let allCases = getAllUnionCaseNames()
        guard !allCases.isEmpty else { return false }
        return allCases.isSubset(of: coveredCases)
    }
    
    private func getAllUnionCaseNames() -> Set<String> {
        // Use resolved cases if available (for generic unions)
        if let resolved = resolvedUnionCases {
            return Set(resolved.map { $0.name })
        }
        
        switch subjectType {
        case .union(let defId):
            return Set((context.getUnionCases(defId) ?? []).map { $0.name })
        default:
            return []
        }
    }
    
    private func updateCoveredSpace(_ space: PatternSpace, with pattern: TypedPattern) -> PatternSpace {
        // For now, just track that we've seen this pattern
        // The actual space tracking is done in checkExhaustiveness
        return space
    }
}


// MARK: - Exhaustiveness Checking

extension ExhaustivenessChecker {
    /// Check that all possible values are covered by the patterns
    private func checkExhaustiveness() throws {
        // Check if we have a catchall pattern (wildcard or variable binding)
        let hasCatchall = patterns.contains { isCatchallPattern($0) }
        
        // Handle different types
        switch subjectType {
        case .union(let defId):
            let typeName = context.getName(defId) ?? subjectType.description
            let cases = context.getUnionCases(defId) ?? []
            try checkUnionExhaustiveness(typeName: typeName, cases: cases, hasCatchall: hasCatchall)
            
        case .genericUnion(let templateName, _):
            // Use resolved cases if available
            if let resolved = resolvedUnionCases {
                try checkUnionExhaustiveness(typeName: templateName, cases: resolved, hasCatchall: hasCatchall)
            } else if hasCatchall {
                // If we have a catchall, it's exhaustive
                return
            } else {
                // Can't check without resolved cases, require catchall
                throw SemanticError(
                    .missingCatchallPattern(type: subjectType.description),
                    line: currentLine
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
                    line: currentLine
                )
            }
            
        case .structure(let defId):
            // Struct types require catchall (can't enumerate all values)
            if !hasCatchall {
                let name = context.getName(defId) ?? subjectType.description
                throw SemanticError(
                    .missingCatchallPattern(type: name),
                    line: currentLine
                )
            }
            
        default:
            // For other types (String, etc.), require catchall
            if !hasCatchall && !isStringType(subjectType) {
                throw SemanticError(
                    .missingCatchallPattern(type: subjectType.description),
                    line: currentLine
                )
            } else if isStringType(subjectType) && !hasCatchall {
                throw SemanticError(
                    .missingCatchallPattern(type: "String"),
                    line: currentLine
                )
            }
        }
    }
    
    private func checkUnionExhaustiveness(typeName: String, cases: [UnionCase], hasCatchall: Bool) throws {
        if hasCatchall {
            return // Catchall covers everything
        }
        
        // Collect all covered case names (including from or patterns)
        var coveredCases: Set<String> = []
        for pattern in patterns {
            collectUnionCasesFromPattern(pattern, into: &coveredCases)
        }
        
        // Find missing cases
        let allCaseNames = Set(cases.map { $0.name })
        let missingCases = allCaseNames.subtracting(coveredCases)
        
        if !missingCases.isEmpty {
            let sortedMissing = missingCases.sorted().map { ".\($0)" }
            throw SemanticError(
                .nonExhaustiveMatch(type: typeName, missing: sortedMissing),
                line: currentLine
            )
        }
    }
    
    /// Recursively collect union case names from a pattern, handling or patterns
    private func collectUnionCasesFromPattern(_ pattern: TypedPattern, into coveredCases: inout Set<String>) {
        switch pattern {
        case .unionCase(let caseName, _, _):
            coveredCases.insert(caseName)
        case .orPattern(let left, let right):
            // Recursively collect from both sides of or pattern
            collectUnionCasesFromPattern(left, into: &coveredCases)
            collectUnionCasesFromPattern(right, into: &coveredCases)
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
                line: currentLine
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

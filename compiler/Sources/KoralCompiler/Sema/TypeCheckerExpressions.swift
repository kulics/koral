import Foundation

// MARK: - Expression Type Inference Extension
// This extension contains methods for inferring types of expressions,
// including the main inferTypedExpression method and its helper methods.

extension TypeChecker {

  private func isStdDropTraitConformance(_ conformance: TypedTraitConformance?) -> Bool {
    guard let conformance, conformance.traitName == "Drop" else {
      return false
    }
    guard let traitInfo = traits[conformance.traitName] else {
      return false
    }
    return traitInfo.modulePath == ["Std"]
  }

  private func isStdDropMethodSymbol(_ method: Symbol) -> Bool {
    let logicalMethodName = receiverMethodDispatchByDefId[method.defId]?.methodName
      ?? context.getName(method.defId)
    guard logicalMethodName == "drop" else {
      return false
    }
    if isStdDropTraitConformance(methodTraitConformanceByDefId[method.defId]) {
      return true
    }
    if let dispatch = receiverMethodDispatchByDefId[method.defId],
       case .extensionTemplate(let ownerName) = dispatch.owner,
       ownerName == "Drop",
       isStdDropTraitConformance(TypedTraitConformance(traitName: ownerName, traitTypeArgs: [])) {
      return true
    }
    return false
  }

  private func cachedSourceLinesForCurrentFile() -> [String]? {
    guard !currentSourceFile.isEmpty else { return nil }
    if let cached = sourceLinesCache[currentSourceFile] {
      return cached
    }
    guard let source = try? String(contentsOfFile: currentSourceFile, encoding: .utf8) else {
      return nil
    }
    let normalizedSource = source
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalizedSource.components(separatedBy: "\n")
    sourceLinesCache[currentSourceFile] = lines
    return lines
  }

  private func bestEffortFinalExpressionSpan(_ expr: ExpressionNode, anchorLine: Int) -> SourceSpan {
    switch expr {
    case .interpolatedString(_, let span),
      .whenExpression(_, _, let span),
      .lambdaExpression(_, _, _, let span),
      .implicitMemberExpression(_, _, let span),
      .orElseExpression(_, _, let span),
      .andThenExpression(_, _, let span),
      .orReturnExpression(_, let span):
      return span
    default:
      break
    }

    guard let lines = cachedSourceLinesForCurrentFile() else {
      return SourceSpan(location: SourceLocation(line: anchorLine, column: currentSpan.start.column))
    }

    var lineIndex = max(0, anchorLine)

    while lineIndex < lines.count {
      let line = lines[lineIndex]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty,
        !trimmed.hasPrefix("//"),
        trimmed != "{",
        trimmed != "}",
        trimmed != "},"
      {
        let column = (line.firstIndex { !$0.isWhitespace }.map { line.distance(from: line.startIndex, to: $0) + 1 }) ?? 1
        return SourceSpan(location: SourceLocation(line: lineIndex + 1, column: column))
      }
      lineIndex += 1
    }

    return SourceSpan(location: SourceLocation(line: anchorLine, column: currentSpan.start.column))
  }

  private func bestEffortIdentifierCallSpan(_ name: String, startLine: Int) -> SourceSpan? {
    guard let lines = cachedSourceLinesForCurrentFile() else {
      return nil
    }

    let center = max(0, startLine - 1)
    let from = max(0, center - 80)
    let to = min(lines.count - 1, center + 80)
    let needle = "\(name)("

    guard from <= to else { return nil }

    var bestMatch: (lineIndex: Int, column: Int, distance: Int)? = nil

    for lineIndex in from...to {
      let line = lines[lineIndex]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("//") { continue }

      if let range = line.range(of: needle) {
        let column = line.distance(from: line.startIndex, to: range.lowerBound) + 1
        let distance = abs(lineIndex - center)
        if let currentBest = bestMatch {
          if distance < currentBest.distance {
            bestMatch = (lineIndex: lineIndex, column: column, distance: distance)
          }
        } else {
          bestMatch = (lineIndex: lineIndex, column: column, distance: distance)
        }
      }
    }

    if let bestMatch {
      return SourceSpan(location: SourceLocation(line: bestMatch.lineIndex + 1, column: bestMatch.column))
    }

    return nil
  }

  private func isUnsignedIntegerType(_ type: Type) -> Bool {
    switch type {
    case .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  private func isRefLikeTypeForMutability(_ type: Type) -> Bool {
    switch type {
    case .reference(_), .pointer(_):
      return true
    default:
      return false
    }
  }

  private func allowsImplicitMutableSelfReference(_ expr: TypedExpressionNode) -> Bool {
    switch expr {
    case .variable(let identifier):
      if isRefLikeTypeForMutability(identifier.type) {
        return true
      }
      return identifier.isMutable()
    case .memberPath(let source, let members):
      var allowed = allowsImplicitMutableSelfReference(source)
      for member in members {
        if isRefLikeTypeForMutability(member.type) {
          allowed = true
        }
      }
      return allowed
    case .derefExpression:
      return true
    default:
      return false
    }
  }

  private func implicitSelfRefViolationName(_ expr: TypedExpressionNode) -> String? {
    switch expr {
    case .variable(let identifier):
      return context.getName(identifier.defId)
    case .memberPath(_, let members):
      return members.last.flatMap { context.getName($0.defId) }
    default:
      return nil
    }
  }

  private func tryOptimizeLiteralCast(
    _ expr: ExpressionNode,
    targetType: Type
  ) throws -> TypedExpressionNode? {
    switch expr {
    case .integerLiteral(let value):
      if isUnsignedIntegerType(targetType), value.hasPrefix("-") {
        throw SemanticError(.generic("Cannot cast negative integer literal to unsigned type \(targetType.description)"), span: currentSpan)
      }
      if isIntegerType(targetType) {
        return .integerLiteral(value: value, type: targetType)
      }
      if isFloatType(targetType) {
        return .floatLiteral(value: value, type: targetType)
      }
      return nil
    case .floatLiteral(let value):
      if isFloatType(targetType) {
        return .floatLiteral(value: value, type: targetType)
      }
      return nil
    default:
      return nil
    }
  }

  private func makeBreakBlock(span: SourceSpan) -> ExpressionNode {
    .blockExpression(statements: [.break(span: span)])
  }

  private func mergeConditionalBranches(
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    expectedType: Type?
  ) throws -> (TypedExpressionNode, TypedExpressionNode?, Type) {
    guard var typedElse = elseBranch else {
      return (thenBranch, nil, .void)
    }

    var typedThen = thenBranch
    var resultType: Type
    if typedThen.type == typedElse.type {
      resultType = typedThen.type
    } else if typedThen.type == .never {
      resultType = typedElse.type
    } else if typedElse.type == .never {
      resultType = typedThen.type
    } else {
      typedThen = try coerceLiteral(typedThen, to: typedElse.type)
      typedElse = try coerceLiteral(typedElse, to: typedThen.type)
      if typedThen.type == typedElse.type {
        resultType = typedThen.type
      } else {
        throw SemanticError.typeMismatch(
          expected: typedThen.type.description,
          got: typedElse.type.description
        )
      }
    }

    if let expected = expectedType, resultType != expected {
      let coercedThen = try coerceLiteral(typedThen, to: expected)
      let coercedElse = try coerceLiteral(typedElse, to: expected)
      if coercedThen.type == expected && coercedElse.type == expected {
        typedThen = coercedThen
        typedElse = coercedElse
        resultType = expected
      }
    }

    return (typedThen, typedElse, resultType)
  }

  private func buildTypedIfExpression(
    condition: TypedExpressionNode,
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    let (mergedThen, mergedElse, resultType) = try mergeConditionalBranches(
      thenBranch: thenBranch,
      elseBranch: elseBranch,
      expectedType: expectedType
    )
    return .ifExpression(
      condition: condition,
      thenBranch: mergedThen,
      elseBranch: mergedElse,
      type: resultType
    )
  }

  private func inferTypedIfPatternExpression(
    subject: ExpressionNode,
    pattern: PatternNode,
    thenBuilder: () throws -> TypedExpressionNode,
    elseBranch: ExpressionNode?,
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    let typedSubject = try inferTypedExpression(subject)

    var subjectType = typedSubject.type
    if case .reference(let inner) = subjectType {
      subjectType = inner
    }

    let (typedPattern, bindings) = try checkPattern(pattern, subjectType: subjectType)
    let typedThen = try withNewScope {
      for symbol in extractPatternSymbols(from: typedPattern) {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
        }
      }
      return try thenBuilder()
    }

    let elseExpectedType = expectedType ?? (typedThen.type == .never ? nil : typedThen.type)
    let typedElse = try elseBranch.map { try inferTypedExpression($0, expectedType: elseExpectedType) }
    let (mergedThen, mergedElse, resultType) = try mergeConditionalBranches(
      thenBranch: typedThen,
      elseBranch: typedElse,
      expectedType: elseExpectedType
    )

    return .ifPatternExpression(
      subject: typedSubject,
      pattern: typedPattern,
      bindings: bindings,
      thenBranch: mergedThen,
      elseBranch: mergedElse,
      type: resultType
    )
  }

  private func inferTypedWhilePatternExpression(
    subject: ExpressionNode,
    pattern: PatternNode,
    bodyBuilder: () throws -> TypedExpressionNode
  ) throws -> TypedExpressionNode {
    let typedSubject = try inferTypedExpression(subject)

    var subjectType = typedSubject.type
    if case .reference(let inner) = subjectType {
      subjectType = inner
    }

    let (typedPattern, bindings) = try checkPattern(pattern, subjectType: subjectType)

    loopDepth += 1
    defer { loopDepth -= 1 }

    let typedBody = try withNewScope {
      for symbol in extractPatternSymbols(from: typedPattern) {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
        }
      }
      return try bodyBuilder()
    }

    return .whilePatternExpression(
      subject: typedSubject,
      pattern: typedPattern,
      bindings: bindings,
      body: typedBody,
      type: .void
    )
  }

  // MARK: - Condition Context Lowering for `is` Expressions

  /// Check whether an untyped PatternNode contains variable bindings.
  private func untypedPatternContainsBindings(_ pattern: PatternNode) -> Bool {
    switch pattern {
    case .variable:
      return true
    case .wildcard, .booleanLiteral, .integerLiteral, .negativeIntegerLiteral,
         .stringLiteral, .runeLiteral, .comparisonPattern:
      return false
    case .enumCase(_, let elements, _):
      return elements.contains { untypedPatternContainsBindings($0.pattern) }
    case .structPattern(_, let elements, _):
      return elements.contains { untypedPatternContainsBindings($0.pattern) }
    case .andPattern(let left, let right, _):
      return untypedPatternContainsBindings(left) || untypedPatternContainsBindings(right)
    case .orPattern(let left, let right, _):
      return untypedPatternContainsBindings(left) || untypedPatternContainsBindings(right)
    case .notPattern(let inner, _):
      return untypedPatternContainsBindings(inner)
    }
  }

  /// Check whether an untyped expression contains an `isExpression` with variable bindings.
  /// This is used to decide whether condition context lowering is needed.
  private func conditionContainsIsWithBindings(_ expr: ExpressionNode) -> Bool {
    switch expr {
    case .isExpression(_, let pattern, _):
      return untypedPatternContainsBindings(pattern)
    case .andExpression(let left, let right):
      return conditionContainsIsWithBindings(left) || conditionContainsIsWithBindings(right)
    case .orExpression(let left, let right):
      return conditionContainsIsWithBindings(left) || conditionContainsIsWithBindings(right)
    case .notExpression(let inner):
      return conditionContainsIsWithBindings(inner)
    default:
      return false
    }
  }

  /// Check whether an untyped expression contains any `isExpression`.
  /// Used to decide whether condition-context lowering should preserve subject lifetimes.
  private func conditionContainsIsExpression(_ expr: ExpressionNode) -> Bool {
    switch expr {
    case .isExpression:
      return true
    case .andExpression(let left, let right), .orExpression(let left, let right):
      return conditionContainsIsExpression(left) || conditionContainsIsExpression(right)
    case .notExpression(let inner):
      return conditionContainsIsExpression(inner)
    default:
      return false
    }
  }

  /// Validate that `or` branches do not contain `isExpression` with bindings.
  /// Reports a diagnostic error if found.
  private func checkOrBranchesForBindings(_ expr: ExpressionNode) throws {
    switch expr {
    case .orExpression(let left, let right):
      // Check if either side of `or` contains `is` with bindings
      if conditionContainsIsWithBindings(left) || conditionContainsIsWithBindings(right) {
        throw SemanticError(
          .generic("Variable bindings in 'is' expression are not allowed in 'or' branches"),
          span: currentSpan
        )
      }
    case .andExpression(let left, let right):
      // Recurse into `and` branches to find nested `or`
      try checkOrBranchesForBindings(left)
      try checkOrBranchesForBindings(right)
    case .notExpression(let inner):
      // Check if `not` wraps an `is` with bindings
      if conditionContainsIsWithBindings(inner) {
        throw SemanticError(
          .generic("Variable bindings in 'is' expression are not allowed under 'not'"),
          span: currentSpan
        )
      }
    default:
      break
    }
  }

  /// Flatten an `and` chain into a list of sub-expressions.
  /// e.g. `a and b and c` → `[a, b, c]`
  private func flattenAndChain(_ expr: ExpressionNode) -> [ExpressionNode] {
    switch expr {
    case .andExpression(let left, let right):
      return flattenAndChain(left) + flattenAndChain(right)
    default:
      return [expr]
    }
  }

  /// Lower an `if` condition that contains `isExpression` with bindings.
  /// Returns the lowered typed expression, or nil if no lowering is needed.
  private func lowerIfConditionWithBindings(
    condition: ExpressionNode,
    thenBranch: ExpressionNode,
    elseBranch: ExpressionNode?,
    expectedType: Type?
  ) throws -> TypedExpressionNode? {
    // First check for illegal uses in `or` and `not`
    try checkOrBranchesForBindings(condition)

    // Check if lowering is needed. Even unbound `is` in condition context should
    // preserve the subject until the branch completes.
    guard conditionContainsIsExpression(condition) else {
      return nil
    }

    // Case 1: Direct `isExpression` with bindings
    if case .isExpression(let subject, let pattern, _) = condition {
      return try inferTypedIfPatternExpression(
        subject: subject,
        pattern: pattern,
        thenBuilder: {
          try self.inferTypedExpression(thenBranch, expectedType: expectedType)
        },
        elseBranch: elseBranch,
        expectedType: expectedType
      )
    }

    // Case 2: `and` chain containing `isExpression` with bindings
    let clauses = flattenAndChain(condition)

    func buildClauseChain(from index: Int) throws -> TypedExpressionNode {
      if index == clauses.count {
        return try inferTypedExpression(thenBranch, expectedType: expectedType)
      }

      let clause = clauses[index]

      if case .isExpression(let subject, let pattern, _) = clause {
        return try inferTypedIfPatternExpression(
          subject: subject,
          pattern: pattern,
          thenBuilder: { try buildClauseChain(from: index + 1) },
          elseBranch: elseBranch,
          expectedType: expectedType
        )
      }

      let typedCondition = try inferTypedExpression(clause)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      let typedThen = try buildClauseChain(from: index + 1)
      let branchExpectedType = expectedType ?? (typedThen.type == .never ? nil : typedThen.type)
      let typedElse = try elseBranch.map { try inferTypedExpression($0, expectedType: branchExpectedType) }
      return try buildTypedIfExpression(
        condition: typedCondition,
        thenBranch: typedThen,
        elseBranch: typedElse,
        expectedType: branchExpectedType
      )
    }

    return try buildClauseChain(from: 0)
  }

  /// Lower a `while` condition that contains `isExpression` with bindings.
  /// Returns the lowered typed expression, or nil if no lowering is needed.
  private func lowerWhileConditionWithBindings(
    condition: ExpressionNode,
    body: ExpressionNode
  ) throws -> TypedExpressionNode? {
    // First check for illegal uses in `or` and `not`
    try checkOrBranchesForBindings(condition)

    // Check if lowering is needed. Even unbound `is` in condition context should
    // preserve the subject until the loop branch decision completes.
    guard conditionContainsIsExpression(condition) else {
      return nil
    }

    // Case 1: Direct `isExpression` with bindings
    if case .isExpression(let subject, let pattern, _) = condition {
      return try inferTypedWhilePatternExpression(
        subject: subject,
        pattern: pattern,
        bodyBuilder: {
          try self.inferTypedExpression(body)
        }
      )
    }

    // Case 2: `and` chain containing `isExpression` with bindings
    let clauses = flattenAndChain(condition)

    // For while loops with `and` chains containing `is` with bindings:
    // - The first `is` with bindings becomes the whilePatternExpression
    // - Clauses BEFORE it become guards that break before the pattern match
    // - Clauses AFTER it become guards inside the pattern match body
    //
    // For `while a > 0 and x is .Some(v) and v > 0 then body`:
    // → `while x is .Some(v) then { if not(a > 0) then break; if v > 0 then body else break }`
    //
    // Wait - that's wrong. `a > 0` should be checked BEFORE the pattern match.
    // Since whilePatternExpression evaluates the subject each iteration,
    // we need conditions before the `is` to be checked first.
    //
    // Correct lowering: all non-first-is clauses become nested if guards inside the body,
    // processed in order. Clauses before the first `is` break if false (checked first in body).
    // The first `is` with bindings is the while pattern.
    // Clauses after the first `is` are checked after bindings are available.

    // Find the first `is` with bindings
    guard let firstIsIndex = clauses.firstIndex(where: {
      if case .isExpression(_, let pattern, _) = $0 {
        return untypedPatternContainsBindings(pattern)
      }
      return false
    }) else {
      return nil
    }

    // The first `is` with bindings becomes the whilePatternExpression
    if case .isExpression(let subject, let pattern, _) = clauses[firstIsIndex] {
      return try inferTypedWhilePatternExpression(
        subject: subject,
        pattern: pattern,
        bodyBuilder: {
          let remainingClauses = Array(clauses[..<firstIsIndex]) + Array(clauses[(firstIsIndex + 1)...])

          func buildGuardChain(from index: Int) throws -> TypedExpressionNode {
            if index == remainingClauses.count {
              return try self.inferTypedExpression(body)
            }

            let clause = remainingClauses[index]
            let breakExpr = self.makeBreakBlock(span: clause.span)

            if case .isExpression(let nextSubject, let nextPattern, _) = clause {
              return try self.inferTypedIfPatternExpression(
                subject: nextSubject,
                pattern: nextPattern,
                thenBuilder: { try buildGuardChain(from: index + 1) },
                elseBranch: breakExpr,
                expectedType: nil
              )
            }

            let typedCondition = try self.inferTypedExpression(clause)
            if typedCondition.type != .bool {
              throw SemanticError.typeMismatch(
                expected: "Bool", got: typedCondition.type.description)
            }
            let typedThen = try buildGuardChain(from: index + 1)
            let typedBreak = try self.inferTypedExpression(
              breakExpr,
              expectedType: typedThen.type == .never ? nil : typedThen.type
            )
            return try self.buildTypedIfExpression(
              condition: typedCondition,
              thenBranch: typedThen,
              elseBranch: typedBreak,
              expectedType: typedThen.type == .never ? nil : typedThen.type
            )
          }

          return try buildGuardChain(from: 0)
        }
      )
    }

    return nil
  }

  // MARK: - Main Expression Type Inference
  
  /// 新增用于返回带类型的表达式的类型推导函数
  /// - Parameters:
  ///   - expr: 要推导类型的表达式节点
  ///   - expectedType: 可选的期望类型，用于隐式成员表达式等需要上下文类型的场景
  /// - Returns: 带类型信息的表达式节点
  func inferTypedExpression(_ expr: ExpressionNode, expectedType: Type? = nil) throws -> TypedExpressionNode {
    switch expr {
    case .castExpression(let typeNode, let innerExpr):
      let targetType = try resolveTypeNode(typeNode)

      if let optimized = try tryOptimizeLiteralCast(innerExpr, targetType: targetType) {
        return optimized
      }

      let typedInner = try inferTypedExpression(innerExpr)

      if !isValidExplicitCast(from: typedInner.type, to: targetType) {
        throw SemanticError.invalidOperation(
          op: "cast",
          type1: typedInner.type.description,
          type2: targetType.description
        )
      }

      // Cast always produces an rvalue.
      return .castExpression(expression: typedInner, type: targetType)

    case .integerLiteral(let value):
      return .integerLiteral(value: value, type: .int)

    case .floatLiteral(let value):
      return .floatLiteral(value: value, type: .float64)

    case .stringLiteral(let value):
      return .stringLiteral(value: value, type: builtinStringType())

    case .runeLiteral(let value):
      // Default inference: Rune. If expected type is UInt8 (byte), infer as byte directly.
      if let expected = expectedType, expected == .uint8 {
        guard let cp = singleRuneCodePoint(from: value), cp <= 127 else {
          throw SemanticError(.generic("Rune literal must be a single ASCII character when used as UInt8"), span: currentSpan)
        }
        return .integerLiteral(value: String(cp), type: .uint8)
      }
      return try inferRuneLiteral(value: value)

    case .interpolatedString(let parts, let span):
      let typedParts = try typeCheckInterpolatedParts(parts, span: span)
      return try lowerInterpolatedString(parts: typedParts, span: span)

    case .booleanLiteral(let value):
      return .booleanLiteral(value: value, type: .bool)

    case .emptyLiteral(let span):
      return try inferEmptyLiteral(span: span, expectedType: expectedType)

    case .collectionLiteral(let elements, let span):
      return try inferCollectionLiteral(elements: elements, span: span, expectedType: expectedType)

    case .dictLiteral(let entries, let span):
      return try inferDictLiteral(entries: entries, span: span, expectedType: expectedType)

    case .whenExpression(let subject, let cases, _):
      let typedSubject = try inferTypedExpression(subject)
      // Auto-deref subject type for pattern matching
      var subjectType = typedSubject.type
      if case .reference(let inner) = subjectType {
        subjectType = inner
      }

      var typedCases: [TypedMatchCase] = []
      var resultType: Type?

      for c in cases {
        try withNewScope {
          let (pattern, _) = try checkPattern(c.pattern, subjectType: subjectType)
          for symbol in extractPatternSymbols(from: pattern) {
            if let name = context.getName(symbol.defId) {
              try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
            }
          }
          // Pass expected type for implicit member expression support
          // Use already-determined resultType as expectedType for subsequent arms
          let armExpectedType = expectedType ?? (resultType.flatMap { $0 == .never ? nil : $0 })
          var typedBody = try inferTypedExpression(c.body, expectedType: armExpectedType)
          if let rt = resultType {
            if typedBody.type != .never {
              if rt == .never {
                // Previous cases were all Never, this is the first concrete type
                resultType = typedBody.type
              } else if typedBody.type != rt {
                // Try literal coercion before reporting mismatch
                typedBody = try coerceLiteral(typedBody, to: rt)
                if typedBody.type != rt {
                  throw SemanticError.typeMismatch(
                    expected: rt.description, got: typedBody.type.description)
                }
              }
            }
          } else {
            resultType = typedBody.type
          }
          typedCases.append(TypedMatchCase(pattern: pattern, body: typedBody))
        }
      }
      
      // Exhaustiveness checking
      let patterns = typedCases.map { $0.pattern }
      let resolvedCases = resolveEnumCasesForExhaustiveness(subjectType)
      let checker = ExhaustivenessChecker(
        subjectType: subjectType,
        patterns: patterns,
        currentLine: currentLine,
        resolvedEnumCases: resolvedCases,
        context: context
      )
      try checker.check()
      
      return .whenExpression(subject: typedSubject, cases: typedCases, type: resultType ?? .void)

    case .identifier(let name):
      if currentScope.isMoved(name) {
        throw SemanticError.variableMoved(name)
      }
      guard let info = currentScope.lookupWithInfo(name, sourceFile: currentSourceFile) else {
        throw SemanticError.undefinedVariable(name)
      }

      let hasLocal = currentScope.lookupWithInfoLocal(name, sourceFile: currentSourceFile) != nil
      
      // 判断是否是全局符号（需要模块路径前缀）
      // 局部变量和参数：modulePath 为空且 sourceFile 为空
      // 全局符号：有 modulePath 或有 sourceFile（private 符号）
      let isGlobalSymbol = !info.modulePath.isEmpty || info.isPrivate || info.sourceFile != nil
      let symbolModulePath = isGlobalSymbol ? (info.modulePath.isEmpty ? currentModulePath : info.modulePath) : []
      let symbolSourceFile = info.isPrivate ? (info.sourceFile ?? currentSourceFile) : ""
      
      // 模块可见性检查：
      // 只有同一模块或父模块的符号可以直接访问
      // 子模块或兄弟模块的符号需要通过模块前缀访问
      if !symbolModulePath.isEmpty && !currentModulePath.isEmpty {
        // 检查符号是否可以从当前模块直接访问（传递符号名用于成员导入检查）
        if !canAccessSymbolDirectly(symbolModulePath: symbolModulePath, currentModulePath: currentModulePath, symbolName: name) {
          // 找到需要使用的模块前缀
          let modulePrefix = getRequiredModulePrefix(symbolModulePath: symbolModulePath, currentModulePath: currentModulePath)
          throw SemanticError(.generic("'\(name)' is defined in module '\(modulePrefix)'. Use '\(modulePrefix).\(name)' to access it."), span: currentSpan)
        }
      }
      
      let fallbackDefKind: DefKind = (!hasLocal && currentScope.isFunction(name, sourceFile: currentSourceFile)) ? .function : .variable
      let defId = currentScope.lookup(name, sourceFile: currentSourceFile) ?? defIdMap.allocate(
        modulePath: symbolModulePath,
        name: name,
        kind: fallbackDefKind,
        sourceFile: symbolSourceFile,
        access: info.isPrivate ? .private : .protected,
        span: currentSpan
      )

      let resolvedDefKind = defIdMap.getKind(defId) ?? fallbackDefKind
      let symbolKind: SymbolKind
      if resolvedDefKind == .function {
        symbolKind = .function
      } else {
        symbolKind = .variable(info.mutable ? .MutableValue : .Value)
      }

      if defIdMap.getSymbolType(defId) == nil {
        defIdMap.addSymbolInfo(
          defId: defId,
          type: info.type,
          kind: symbolKind,
          isMutable: info.mutable
        )
      }

      let symbol = Symbol(
        defId: defId,
        type: info.type,
        kind: symbolKind
      )
      
      return .variable(identifier: symbol)

    case .blockExpression(let statements):
      return try withNewScope {
        var typedStatements: [TypedStatementNode] = []
        var blockType: Type = .void
        var foundNever = false

        for (index, stmt) in statements.enumerated() {
          // yield position check: only allowed as last statement
          if case .yield = stmt, index != statements.count - 1 {
            throw SemanticError(
              .generic("yield must be the last statement in a block expression"),
              span: stmt.span
            )
          }

          let typedStmt = try checkStatement(stmt, expectedYieldType: expectedType)
          typedStatements.append(typedStmt)

          switch typedStmt {
          case .yield(let typedExpr):
            blockType = typedExpr.type
          case .expression(let expr):
            if expr.type == .never {
              foundNever = true
            }
          case .return, .break, .continue:
            foundNever = true
          default:
            break
          }
        }

        if foundNever && blockType == .void { blockType = .never }

        return .blockExpression(
          statements: typedStatements, type: blockType)
      }

    case .arithmeticExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type only for numeric ops.
      let leftIsNumeric = isIntegerType(typedLeft.type) || isFloatType(typedLeft.type)
      let rightIsNumeric = isIntegerType(typedRight.type) || isFloatType(typedRight.type)
      if leftIsNumeric && rightIsNumeric, typedLeft.type != typedRight.type {
        typedRight = try coerceLiteral(typedRight, to: typedLeft.type)
        if typedLeft.type != typedRight.type {
          typedLeft = try coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      return try buildArithmeticExpression(op: op, lhs: typedLeft, rhs: typedRight)

    case .comparisonExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) || isFloatType(typedLeft.type) {
          typedRight = try coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type,
          isIntegerType(typedRight.type) || isFloatType(typedRight.type)
        {
          typedLeft = try coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      // Allow rune literals to coerce to UInt8 in comparisons when needed.
      if typedLeft.type != typedRight.type {
        if typedLeft.type == .uint8 {
          typedRight = try coerceLiteral(typedRight, to: .uint8)
        }
        if typedRight.type == .uint8 {
          typedLeft = try coerceLiteral(typedLeft, to: .uint8)
        }
      }
      
      // Allow rune literals to coerce to Rune in comparisons.
      if typedLeft.type != typedRight.type {
        if isRuneType(typedLeft.type) {
          typedRight = try coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type, isRuneType(typedRight.type) {
          typedLeft = try coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      // Allow null_ptr() to infer pointer element type from the other operand.
      if typedLeft.type != typedRight.type {
        if case .pointer = typedLeft.type,
           case .intrinsicCall(.nullPtr) = typedRight {
          typedRight = try coerceLiteral(typedRight, to: typedLeft.type)
        } else if case .pointer = typedRight.type,
          case .intrinsicCall(.nullPtr) = typedLeft {
          typedLeft = try coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      // Operator sugar for Eq: lower `==`/`<>` to `equals(self, other)`
      // for non-builtin scalar types (struct/enum/String/generic parameters).
      if (op == .equal || op == .notEqual), typedLeft.type == typedRight.type,
        !isBuiltinEqualityComparable(typedLeft.type)
      {
        let eq = try buildEqualsCall(lhs: typedLeft, rhs: typedRight)
        if op == .notEqual {
          return .notExpression(expression: eq, type: .bool)
        }
        return eq
      }

      // Operator sugar for Ord: lower `<`/`<=`/`>`/`>=` to
      // `compare(self, other) Int` for non-builtin scalar types
      // (struct/enum/String/generic parameters).
      if (op == .greater || op == .less || op == .greaterEqual || op == .lessEqual),
        typedLeft.type == typedRight.type,
        !isBuiltinOrderingComparable(typedLeft.type)
      {
        let cmp = try buildCompareCall(lhs: typedLeft, rhs: typedRight)
        let zero: TypedExpressionNode = .integerLiteral(value: "0", type: .int)
        return .comparisonExpression(left: cmp, op: op, right: zero, type: .bool)
      }

      let resultType = try checkComparisonOp(op, typedLeft.type, typedRight.type)
      return .comparisonExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

    case .ifExpression(let condition, let thenBranch, let elseBranch):
      // Check if condition contains `isExpression` with bindings → lower to ifPatternExpression
      if let lowered = try lowerIfConditionWithBindings(
        condition: condition,
        thenBranch: thenBranch,
        elseBranch: elseBranch,
        expectedType: expectedType
      ) {
        return lowered
      }

      let typedCondition = try inferTypedExpression(condition)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      // Pass expected type to branches for implicit member expression support
      let typedThen = try inferTypedExpression(thenBranch, expectedType: expectedType)

      let typedElse = try elseBranch.map { try inferTypedExpression($0, expectedType: expectedType) }
      return try buildTypedIfExpression(
        condition: typedCondition,
        thenBranch: typedThen,
        elseBranch: typedElse,
        expectedType: expectedType
      )

    case .whileExpression(let condition, let body):
      // Check if condition contains `isExpression` with bindings → lower to whilePatternExpression
      if let lowered = try lowerWhileConditionWithBindings(
        condition: condition,
        body: body
      ) {
        return lowered
      }

      let typedCondition = try inferTypedExpression(condition)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      loopDepth += 1
      defer { loopDepth -= 1 }
      let typedBody = try inferTypedExpression(body)
      return .whileExpression(
        condition: typedCondition,
        body: typedBody,
        type: .void
      )

    case .call(let callee, let arguments):
      return try inferCallExpression(callee: callee, arguments: arguments, expectedType: expectedType)

    case .andExpression(let left, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .andExpression(left: typedLeft, right: typedRight, type: .bool)

    case .orExpression(let left, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .orExpression(left: typedLeft, right: typedRight, type: .bool)

    case .unaryMinusExpression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      if isIntegerType(typedExpr.type) {
        let zero: TypedExpressionNode = .integerLiteral(value: "0", type: typedExpr.type)
        return .arithmeticExpression(left: zero, op: .minus, right: typedExpr, type: typedExpr.type)
      }
      if isFloatType(typedExpr.type) {
        let zero: TypedExpressionNode = .floatLiteral(value: "0", type: typedExpr.type)
        return .arithmeticExpression(left: zero, op: .minus, right: typedExpr, type: typedExpr.type)
      }
      if let call = try buildOperatorMethodCall(
        base: typedExpr,
        methodName: "neg",
        traitName: "Neg",
        requiredTraitArgs: nil,
        arguments: []
      ) {
        return call
      }
      throw SemanticError.undefinedMember("neg", typedExpr.type.description)

    case .notExpression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      if typedExpr.type != .bool {
        throw SemanticError.typeMismatch(expected: "Bool", got: typedExpr.type.description)
      }
      return .notExpression(expression: typedExpr, type: .bool)

    case .bitwiseExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) {
          typedRight = try coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type, isIntegerType(typedRight.type) {
          typedLeft = try coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      if !isIntegerScalarType(typedLeft.type) || typedLeft.type != typedRight.type {
        throw SemanticError.typeMismatch(
          expected: "Matching Integer Types", got: "\(typedLeft.type) \(op) \(typedRight.type)")
      }
      return .bitwiseExpression(left: typedLeft, op: op, right: typedRight, type: typedLeft.type)

    case .bitwiseNotExpression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      if !isIntegerScalarType(typedExpr.type) {
        throw SemanticError.typeMismatch(expected: "Integer Type", got: typedExpr.type.description)
      }
      return .bitwiseNotExpression(expression: typedExpr, type: typedExpr.type)

    case .derefExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      if case .reference(let innerType) = typedInner.type {
        // Disallow deref of trait object references
        if case .traitObject = innerType {
          throw SemanticError(.generic(
            "Cannot dereference a trait object reference: concrete type is unknown at compile time"
          ), span: currentSpan)
        }
        // Disallow deref of opaque type references
        if case .opaque = innerType {
          throw SemanticError(.generic(
            "Cannot dereference an opaque type reference: type layout is unknown at compile time"
          ), span: currentSpan)
        }
        // Generic parameters require Deref bound
        if case .genericParameter(let paramName) = innerType {
          guard hasTraitBound(paramName, "Deref") else {
            throw SemanticError(.generic(
              "Cannot dereference '\(paramName) ref': type parameter '\(paramName)' does not have 'Deref' bound. " +
              "Add 'Deref' constraint: [\(paramName) Deref]"
            ), span: currentSpan)
          }
        }
        return .derefExpression(expression: typedInner, type: innerType)
      } else if case .pointer(let elementType) = typedInner.type {
        return .derefExpression(expression: typedInner, type: elementType)
      } else {
        throw SemanticError.typeMismatch(
          expected: "Reference or pointer type",
          got: typedInner.type.description
        )
      }

    case .refExpression(let inner):
      // Unwrap expected reference type for inner expression
      var innerExpected: Type? = nil
      if let expected = expectedType, case .reference(let innerType) = expected {
        innerExpected = innerType
      }
      let typedInner: TypedExpressionNode
      do {
        typedInner = try resolveLValue(inner)
      } catch let error as SemanticError {
        if case .assignToImmutable(let name) = error.kind {
          throw SemanticError(.cannotTakeRefOfImmutable(name), span: currentSpan)
        }
        throw error
      }
      if let innerExpected, typedInner.type != innerExpected {
        throw SemanticError.typeMismatch(expected: innerExpected.description, got: typedInner.type.description)
      }
      return .referenceExpression(expression: typedInner, type: .reference(inner: typedInner.type))

    case .ptrExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      let isAddressable = typedInner.valueCategory == .lvalue || isDerefExpression(inner)
      if !isAddressable {
        if isLiteralExpression(inner) {
          throw SemanticError(.generic("cannot take address of literal"))
        }
        throw SemanticError(.generic("cannot take address of temporary value"))
      }
      return .ptrExpression(expression: typedInner, type: .pointer(element: typedInner.type))

    case .subscriptExpression(let base, let arguments):
      let typedBase = try inferTypedExpression(base)
      let typedArguments = try arguments.map { try inferTypedExpression($0) }
      let resolvedSubscript = try resolveSubscript(base: typedBase, args: typedArguments)

      return resolvedSubscript

    case .genericMethodCall(let baseExpr, let methodTypeArgs, let methodName, let arguments):
      return try inferGenericMethodCallExpression(
        baseExpr: baseExpr,
        methodTypeArgs: methodTypeArgs,
        methodName: methodName,
        arguments: arguments.map { $0.expression }
      )

    case .qualifiedMethodCall(let baseExpr, let traitName, let methodName, let arguments):
      return try inferQualifiedMethodCallExpression(
        baseExpr: baseExpr,
        traitName: traitName,
        methodName: methodName,
        methodTypeArgs: nil,
        arguments: arguments.map { $0.expression }
      )

    case .qualifiedGenericMethodCall(let baseExpr, let traitName, let methodTypeArgs, let methodName, let arguments):
      return try inferQualifiedMethodCallExpression(
        baseExpr: baseExpr,
        traitName: traitName,
        methodName: methodName,
        methodTypeArgs: methodTypeArgs,
        arguments: arguments.map { $0.expression }
      )

    case .memberPath(let baseExpr, let path):
      return try inferMemberPathExpression(baseExpr: baseExpr, path: path)

    case .staticMethodCall(let typeName, let typeArgs, let methodName, let arguments):
      return try inferStaticMethodCallExpression(
        typeName: typeName,
        typeArgs: typeArgs,
        methodName: methodName,
        arguments: arguments.map { $0.expression }
      )

    case .forExpression(let pattern, let iterable, let body):
      return try inferForExpression(pattern: pattern, iterable: iterable, body: body)

    case .rangeExpression(let op, let left, let right):
      return try inferRangeExpression(
        operator: op,
        left: left,
        right: right,
        expectedType: expectedType
      )

    case .genericInstantiation(let base, _):
      throw SemanticError.invalidOperation(op: "use type as value", type1: base, type2: "")
      
    case .lambdaExpression(let parameters, let returnType, let body, _):
      return try inferLambdaExpression(parameters: parameters, returnType: returnType, body: body, expectedType: expectedType)
      
    case .implicitMemberExpression(let memberName, let arguments, let span):
      // Implicit member expression requires an expected type from context.
      return try inferImplicitMemberExpression(
        memberName: memberName,
        callArgs: arguments,
        expectedType: expectedType,
        span: span
      )

    case .orElseExpression(let operand, let defaultExpr, let span):
      return try lowerOrElseExpression(operand: operand, defaultExpr: defaultExpr, span: span)

    case .andThenExpression(let operand, let transformExpr, let span):
      return try lowerAndThenExpression(operand: operand, transformExpr: transformExpr, span: span, expectedType: expectedType)

    case .orReturnExpression(let operand, let span):
      return try lowerOrReturnExpression(operand: operand, span: span)

    case .isExpression(let subject, let pattern, _):
      // Type check the subject expression
      let typedSubject = try inferTypedExpression(subject)

      // Auto-deref subject type for pattern matching (consistent with `when`)
      var subjectType = typedSubject.type
      if case .reference(let inner) = subjectType {
        subjectType = inner
      }

      // Check the pattern against the subject type
      let (typedPattern, _) = try checkPattern(pattern, subjectType: subjectType)

      // In non-condition context, variable bindings are not allowed
      if patternContainsBindings(typedPattern) {
        throw SemanticError(
          .generic("Variable bindings in 'is' expression are only allowed in if/while conditions"),
          span: currentSpan
        )
      }

      return .isExpression(subject: typedSubject, pattern: typedPattern, type: .bool)

    case .isNotExpression(let subject, let pattern, _):
      // Type check the subject expression
      let typedSubject = try inferTypedExpression(subject)

      // Auto-deref subject type for pattern matching (consistent with `when`)
      var subjectType = typedSubject.type
      if case .reference(let inner) = subjectType {
        subjectType = inner
      }

      // Check the pattern against the subject type
      let (typedPattern, _) = try checkPattern(pattern, subjectType: subjectType)

      // is not always forbids variable bindings (negated match cannot safely bind)
      if patternContainsBindings(typedPattern) {
        throw SemanticError(
          .generic("Variable bindings are not allowed in 'is not' expression"),
          span: currentSpan
        )
      }

      return .isNotExpression(subject: typedSubject, pattern: typedPattern, type: .bool)
    }
  }

  private enum CollectionTargetKind {
    case list(element: Type)
    case set(element: Type)
    case map(key: Type, value: Type)
  }

  private func inferEmptyLiteral(span: SourceSpan, expectedType: Type?) throws -> TypedExpressionNode {
    guard let expectedType else {
      throw SemanticError(
        .generic("Cannot infer type for empty collection literal '[]'. Add an explicit type annotation."),
        span: span
      )
    }

    let target = try classifyCollectionTarget(expectedType, span: span)
    switch target {
    case .list, .set, .map:
      return try buildWithCapacityCall(targetType: expectedType, count: 0)
    }
  }

  private func inferCollectionLiteral(
    elements: [ExpressionNode],
    span: SourceSpan,
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    let target: CollectionTargetKind

    if let expectedType {
      target = try classifyCollectionTarget(expectedType, span: span)
    } else {
      let inferredElementType = try inferCommonElementType(elements: elements, span: span)
      target = .list(element: inferredElementType)
    }

    switch target {
    case .list(let elementType):
      let listType = Type.genericStruct(template: "List", args: [elementType])
      return try lowerCollectionLiteral(
        targetType: listType,
        methodName: "push",
        elements: elements,
        argumentTypes: [elementType],
        duplicateWarningKind: nil,
        span: span
      )

    case .set(let elementType):
      let setType = Type.genericStruct(template: "Set", args: [elementType])
      return try lowerCollectionLiteral(
        targetType: setType,
        methodName: "insert",
        elements: elements,
        argumentTypes: [elementType],
        duplicateWarningKind: .setElement,
        span: span
      )

    case .map:
      throw SemanticError(
        .generic("Collection literal without ':' cannot be inferred as Dict"),
        span: span
      )
    }
  }

  private func inferDictLiteral(
    entries: [(key: ExpressionNode, value: ExpressionNode)],
    span: SourceSpan,
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    let keyType: Type
    let valueType: Type

    if let expectedType {
      let target = try classifyCollectionTarget(expectedType, span: span)
      switch target {
      case .map(let k, let v):
        keyType = k
        valueType = v
      case .list, .set:
        throw SemanticError(
          .generic("Dict literal can only be assigned to [K, V]Dict"),
          span: span
        )
      }
    } else {
      keyType = try inferCommonElementType(elements: entries.map { $0.key }, span: span)
      valueType = try inferCommonElementType(elements: entries.map { $0.value }, span: span)
    }

    let dictType = Type.genericStruct(template: "Dict", args: [keyType, valueType])
    return try lowerDictLiteral(
      targetType: dictType,
      entries: entries,
      keyType: keyType,
      valueType: valueType,
      span: span
    )
  }

  private func classifyCollectionTarget(_ type: Type, span: SourceSpan) throws -> CollectionTargetKind {
    switch type {
    case .genericStruct(let template, let args):
      switch template {
      case "List":
        guard args.count == 1 else {
          throw SemanticError(.generic("[T]List requires exactly one type argument"), span: span)
        }
        return .list(element: args[0])
      case "Set":
        guard args.count == 1 else {
          throw SemanticError(.generic("[T]Set requires exactly one type argument"), span: span)
        }
        return .set(element: args[0])
      case "Dict":
        guard args.count == 2 else {
          throw SemanticError(.generic("[K, V]Dict requires exactly two type arguments"), span: span)
        }
        return .map(key: args[0], value: args[1])
      default:
        throw SemanticError(
          .generic("Collection literals only support built-in [T]List, [T]Set, and [K, V]Dict"),
          span: span
        )
      }

    default:
      throw SemanticError(
        .generic("Collection literals only support built-in [T]List, [T]Set, and [K, V]Dict"),
        span: span
      )
    }
  }

  private func inferCommonElementType(elements: [ExpressionNode], span: SourceSpan) throws -> Type {
    guard let first = elements.first else {
      throw SemanticError(
        .generic("Cannot infer element type from empty collection literal"),
        span: span
      )
    }

    var current = try inferTypedExpression(first).type
    for element in elements.dropFirst() {
      let typed = try inferTypedExpression(element, expectedType: current)
      if typed.type == current {
        continue
      }
      let coercedToCurrent = try coerceLiteral(typed, to: current)
      if coercedToCurrent.type == current {
        continue
      }
      let currentAsExpr = expressionFromTypeOnlyLiteral(current)
      if let currentAsExpr {
        let currentTyped = try inferTypedExpression(currentAsExpr, expectedType: typed.type)
        let coercedCurrent = try coerceLiteral(currentTyped, to: typed.type)
        if coercedCurrent.type == typed.type {
          current = typed.type
          continue
        }
      }
      throw SemanticError.typeMismatch(expected: current.description, got: typed.type.description)
    }
    return current
  }

  private func expressionFromTypeOnlyLiteral(_ type: Type) -> ExpressionNode? {
    // This helper intentionally only covers primitive defaults used in literal type reconciliation.
    switch type {
    case .int, .int8, .int16, .int32, .int64, .uint, .uint8, .uint16, .uint32, .uint64:
      return .integerLiteral("0")
    case .float32, .float64:
      return .floatLiteral("0.0")
    default:
      return nil
    }
  }

  private enum DuplicateWarningKind {
    case setElement
    case dictKey
  }

  private func lowerCollectionLiteral(
    targetType: Type,
    methodName: String,
    elements: [ExpressionNode],
    argumentTypes: [Type],
    duplicateWarningKind: DuplicateWarningKind?,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    let initializer = try buildWithCapacityCall(targetType: targetType, count: elements.count)

    let temp = makeLocalSymbol(
      name: "__collection_literal_\(synthesizedTempIndex)",
      type: targetType,
      kind: .variable(.MutableValue)
    )
    synthesizedTempIndex += 1

    var statements: [TypedStatementNode] = [
      .variableDeclaration(identifier: temp, value: initializer, mutable: true)
    ]

    var seenConstants: Set<String> = []

    guard let methodSym = try lookupConcreteMethodSymbol(on: targetType, name: methodName) else {
      throw SemanticError(
        .generic("Missing method '\(methodName)' for type '\(targetType.description)'"),
        span: span
      )
    }

    for element in elements {
      if let duplicateWarningKind,
         let constantKey = extractCompileTimeConstantKey(from: element) {
        if seenConstants.contains(constantKey) {
          switch duplicateWarningKind {
          case .setElement:
            recordWarning("Duplicate set element literal: \(constantKey)", at: element.span)
          case .dictKey:
            recordWarning("Duplicate dict key literal: \(constantKey)", at: element.span)
          }
        } else {
          seenConstants.insert(constantKey)
        }
      }

      let typedCall = try inferMethodCall(
        base: .variable(identifier: temp),
        method: methodSym,
        methodType: methodSym.type,
        arguments: [element]
      )
      statements.append(.expression(typedCall))
    }

    statements.append(.yield(value: .variable(identifier: temp)))
    return .blockExpression(statements: statements, type: targetType)
  }

  private func lowerDictLiteral(
    targetType: Type,
    entries: [(key: ExpressionNode, value: ExpressionNode)],
    keyType: Type,
    valueType: Type,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    _ = keyType
    _ = valueType

    let initializer = try buildWithCapacityCall(targetType: targetType, count: entries.count)
    let temp = makeLocalSymbol(
      name: "__collection_literal_\(synthesizedTempIndex)",
      type: targetType,
      kind: .variable(.MutableValue)
    )
    synthesizedTempIndex += 1

    var statements: [TypedStatementNode] = [
      .variableDeclaration(identifier: temp, value: initializer, mutable: true)
    ]

    guard let methodSym = try lookupConcreteMethodSymbol(on: targetType, name: "insert") else {
      throw SemanticError(
        .generic("Missing method 'insert' for type '\(targetType.description)'"),
        span: span
      )
    }

    var seenKeys: Set<String> = []
    for entry in entries {
      if let keyConstant = extractCompileTimeConstantKey(from: entry.key) {
        if seenKeys.contains(keyConstant) {
          recordWarning("Duplicate dict key literal: \(keyConstant)", at: entry.key.span)
        } else {
          seenKeys.insert(keyConstant)
        }
      }

      let typedCall = try inferMethodCall(
        base: .variable(identifier: temp),
        method: methodSym,
        methodType: methodSym.type,
        arguments: [entry.key, entry.value]
      )
      statements.append(.expression(typedCall))
    }

    statements.append(.yield(value: .variable(identifier: temp)))
    return .blockExpression(statements: statements, type: targetType)
  }

  private func buildWithCapacityCall(targetType: Type, count: Int) throws -> TypedExpressionNode {
    let (typeName, typeArgs) = try staticTypeCallParts(for: targetType)
    return try inferStaticMethodCallExpression(
      typeName: typeName,
      typeArgs: typeArgs,
      methodName: "with_capacity",
      arguments: [.integerLiteral("\(count)")]
    )
  }

  private func staticTypeCallParts(for type: Type) throws -> (name: String, args: [TypeNode]) {
    switch type {
    case .genericStruct(let template, let args):
      return (template, try args.map { try toTypeNode($0) })
    case .genericEnum(let template, let args):
      return (template, try args.map { try toTypeNode($0) })
    case .structure(let defId), .`enum`(let defId), .opaque(let defId):
      guard let name = context.getName(defId) else {
        throw SemanticError(.generic("Unable to resolve type name for static call"), span: currentSpan)
      }
      return (name, [])
    default:
      throw SemanticError(.generic("Type '\(type.description)' does not support static method calls"), span: currentSpan)
    }
  }

  private func toTypeNode(_ type: Type) throws -> TypeNode {
    switch type {
    case .int: return .identifier("Int")
    case .int8: return .identifier("Int8")
    case .int16: return .identifier("Int16")
    case .int32: return .identifier("Int32")
    case .int64: return .identifier("Int64")
    case .uint: return .identifier("UInt")
    case .uint8: return .identifier("UInt8")
    case .uint16: return .identifier("UInt16")
    case .uint32: return .identifier("UInt32")
    case .uint64: return .identifier("UInt64")
    case .float32: return .identifier("Float32")
    case .float64: return .identifier("Float64")
    case .bool: return .identifier("Bool")
    case .void: return .identifier("Void")
    case .never: return .identifier("Never")
    case .reference(let inner): return .reference(try toTypeNode(inner))
    case .pointer(let inner): return .pointer(try toTypeNode(inner))
    case .weakReference(let inner): return .weakReference(try toTypeNode(inner))
    case .genericParameter(let name): return .identifier(name)
    case .genericStruct(let template, let args):
      return .generic(base: template, args: try args.map { try toTypeNode($0) })
    case .genericEnum(let template, let args):
      return .generic(base: template, args: try args.map { try toTypeNode($0) })
    case .structure(let defId), .`enum`(let defId), .opaque(let defId):
      guard let name = context.getName(defId) else {
        throw SemanticError(.generic("Unable to resolve type node name"), span: currentSpan)
      }
      return .identifier(name)
    case .function(let params, let returns):
      let paramNodes = try params.map { try toTypeNode($0.type) }
      return .functionType(paramTypes: paramNodes, returnType: try toTypeNode(returns))
    case .module, .typeVariable, .traitObject:
      throw SemanticError(.generic("Unsupported type in collection literal lowering: \(type.description)"), span: currentSpan)
    }
  }

  private func extractCompileTimeConstantKey(from expr: ExpressionNode) -> String? {
    switch expr {
    case .integerLiteral(let value):
      return "int:\(value)"
    case .floatLiteral(let value):
      return "float:\(value)"
    case .stringLiteral(let value):
      return "string:\(value)"
    case .runeLiteral(let value):
      return "rune:\(value)"
    case .booleanLiteral(let value):
      return "bool:\(value)"
    default:
      return nil
    }
  }
  
  // MARK: - Implicit Member Expression Inference
  
  /// Infers the type of an implicit member expression (e.g., `.Some(42)`, `.new()`)
  /// - Parameters:
  ///   - memberName: The member name (enum case or static method)
  ///   - arguments: The arguments to the member
  ///   - expectedType: The expected type from context (required)
  ///   - span: Source location for error reporting
  /// - Returns: A typed expression node (enumConstruction or staticMethodCall)
  private func inferImplicitMemberExpression(
    memberName: String,
    callArgs: [CallArg],
    expectedType: Type?,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    let arguments = callArgs.map { $0.expression }
    // 1. Check if we have an expected type
    guard let expected = expectedType else {
      throw SemanticError(
        .generic("Cannot use implicit member expression '.\(memberName)' without a known type context"),
        span: span
      )
    }
    
    // 2. Try to resolve as enum case first
    if let result = try resolveImplicitEnumCase(
      memberName: memberName,
      callArgs: callArgs,
      arguments: arguments,
      expectedType: expected,
      span: span
    ) {
      return result
    }
    
    // 3. Try to resolve as static method
    if let result = try resolveImplicitStaticMethod(
      memberName: memberName,
      arguments: arguments,
      expectedType: expected,
      span: span
    ) {
      return result
    }
    
    // 4. Neither worked - report error
    throw SemanticError(
      .generic("Member '\(memberName)' not found on type '\(expected.description)'"),
      span: span
    )
  }
  
  /// Resolves an implicit member expression as a enum case construction
  private func resolveImplicitEnumCase(
    memberName: String,
    callArgs: [CallArg],
    arguments: [ExpressionNode],
    expectedType: Type,
    span: SourceSpan
  ) throws -> TypedExpressionNode? {
    // Get enum cases based on the expected type
    let cases: [EnumCase]?
    
    switch expectedType {
    case .`enum`(let defId):
      cases = context.getEnumCases(defId)
      
    case .genericEnum(let templateName, let typeArgs):
      // Look up the enum template and substitute type parameters
      guard let template = currentScope.lookupGenericEnumTemplate(templateName) else {
        return nil
      }
      
      // Create substitution map
      var substitution: [String: Type] = [:]
      for (i, param) in template.typeParameters.enumerated() {
        if i < typeArgs.count {
          substitution[param.name] = typeArgs[i]
        }
      }
      
      // Resolve case parameter types with substitution
      let resolvedCases: [EnumCase] = try template.cases.map { caseDef in
        let resolvedParams: [(name: String, type: Type, access: AccessModifier, named: Bool)] = try caseDef.parameters.map { param in
          let resolvedType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(param.type)
          }
          return (name: param.name, type: resolvedType, access: AccessModifier.public, named: param.named)
        }
        return EnumCase(name: caseDef.name, parameters: resolvedParams)
      }
      cases = resolvedCases
      
    default:
      return nil
    }
    
    guard let enumCases = cases else {
      return nil
    }
    
    // Find the matching case
    guard let caseInfo = enumCases.first(where: { $0.name == memberName }) else {
      return nil
    }
    
    // Check argument count
    if arguments.count != caseInfo.parameters.count {
      throw SemanticError(
        .generic("Enum case '\(memberName)' expects \(caseInfo.parameters.count) argument(s), got \(arguments.count)"),
        span: span
      )
    }
    
    // Type check arguments
    var typedArgs: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, caseInfo.parameters) {
      var typedArg = try inferTypedExpression(arg, expectedType: param.type)
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        throw SemanticError.typeMismatch(
          expected: param.type.description, got: typedArg.type.description)
      }
      typedArgs.append(typedArg)
    }
    
    // Validate named argument labels for enum case construction
    try validateNamedArguments(
      callArgs: callArgs,
      parameters: caseInfo.parameters.map { (name: $0.name, named: $0.named) },
      callDescription: ".\(memberName)"
    )
    
    // Generate enum construction
    return .enumConstruction(type: expectedType, caseName: memberName, arguments: typedArgs)
  }
  
  /// Resolves an implicit member expression as a static method call
  private func resolveImplicitStaticMethod(
    memberName: String,
    arguments: [ExpressionNode],
    expectedType: Type,
    span: SourceSpan
  ) throws -> TypedExpressionNode? {
    // Look up static method based on the expected type
    switch expectedType {
    case .structure(let defId):
      let typeName = context.getName(defId) ?? ""
      guard let methods = extensionMethods[typeName],
            let methodSym = methods[memberName] else {
        return nil
      }
      
      // Check if it's a static method
      guard case .function(let params, let returnType) = methodSym.type else {
        return nil
      }
      let isStatic = !isReceiverStyleMethod(methodSym)
      guard isStatic else { return nil }
      
      // Check if return type matches expected type
      guard returnType == expectedType else {
        return nil
      }
      
      // Type check arguments
      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: memberName,
          expected: params.count,
          got: arguments.count
        )
      }
      
      var typedArgs: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        var typedArg = try inferTypedExpression(arg, expectedType: param.type)
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description, got: typedArg.type.description)
        }
        typedArgs.append(typedArg)
      }
      
      return .staticMethodCall(
        baseType: expectedType,
        methodName: memberName,
        typeArgs: [],
        methodTypeArgs: [],
        arguments: typedArgs,
        type: returnType
      )
      
    case .`enum`(let defId):
      let typeName = context.getName(defId) ?? ""
      guard let methods = extensionMethods[typeName],
            let methodSym = methods[memberName] else {
        return nil
      }
      
      // Check if it's a static method
      guard case .function(let params, let returnType) = methodSym.type else {
        return nil
      }
      let isStatic = !isReceiverStyleMethod(methodSym)
      guard isStatic else { return nil }
      
      // Check if return type matches expected type
      guard returnType == expectedType else {
        return nil
      }
      
      // Type check arguments
      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: memberName,
          expected: params.count,
          got: arguments.count
        )
      }
      
      var typedArgs: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        var typedArg = try inferTypedExpression(arg, expectedType: param.type)
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description, got: typedArg.type.description)
        }
        typedArgs.append(typedArg)
      }
      
      return .staticMethodCall(
        baseType: expectedType,
        methodName: memberName,
        typeArgs: [],
        methodTypeArgs: [],
        arguments: typedArgs,
        type: returnType
      )
      
    case .genericStruct(let templateName, let typeArgs):
      guard let extensions = genericExtensionMethods[templateName],
            let ext = extensions.first(where: { $0.method.name == memberName }) else {
        return nil
      }
      
      // Check if it's a static method
      let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
      guard isStatic else { return nil }
      
      // Resolve the method with type arguments
      let methodSym = try resolveGenericExtensionMethod(
        baseType: expectedType,
        templateName: templateName,
        typeArgs: typeArgs,
        methodInfo: ext
      )
      
      guard case .function(let params, let returnType) = methodSym.type else {
        return nil
      }
      
      // Check if return type matches expected type (allowing Self substitution)
      guard returnType == expectedType else {
        return nil
      }
      
      // Type check arguments
      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: memberName,
          expected: params.count,
          got: arguments.count
        )
      }
      
      var typedArgs: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        var typedArg = try inferTypedExpression(arg, expectedType: param.type)
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description, got: typedArg.type.description)
        }
        typedArgs.append(typedArg)
      }
      
      return .staticMethodCall(
        baseType: expectedType,
        methodName: memberName,
        typeArgs: typeArgs,
        methodTypeArgs: [],
        arguments: typedArgs,
        type: returnType
      )
      
    case .genericEnum(let templateName, let typeArgs):
      guard let extensions = genericExtensionMethods[templateName],
            let ext = extensions.first(where: { $0.method.name == memberName }) else {
        return nil
      }
      
      // Check if it's a static method
      let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
      guard isStatic else { return nil }
      
      // Resolve the method with type arguments
      let methodSym = try resolveGenericExtensionMethod(
        baseType: expectedType,
        templateName: templateName,
        typeArgs: typeArgs,
        methodInfo: ext
      )
      
      guard case .function(let params, let returnType) = methodSym.type else {
        return nil
      }
      
      // Check if return type matches expected type (allowing Self substitution)
      guard returnType == expectedType else {
        return nil
      }
      
      // Type check arguments
      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: memberName,
          expected: params.count,
          got: arguments.count
        )
      }
      
      var typedArgs: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        var typedArg = try inferTypedExpression(arg, expectedType: param.type)
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description, got: typedArg.type.description)
        }
        typedArgs.append(typedArg)
      }
      
      return .staticMethodCall(
        baseType: expectedType,
        methodName: memberName,
        typeArgs: typeArgs,
        methodTypeArgs: [],
        arguments: typedArgs,
        type: returnType
      )
      
    default:
      return nil
    }
  }
}


// MARK: - Call Expression Inference

extension TypeChecker {

  func inferQualifiedMethodCallExpression(
    baseExpr: ExpressionNode,
    traitName: String,
    methodName: String,
    methodTypeArgs: [TypeNode]?,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    // Generic qualified call delegates to existing generic method-call pipeline.
    // Trait qualification is primarily a disambiguation syntax.
    if let methodTypeArgs, !methodTypeArgs.isEmpty {
      return try inferGenericMethodCallExpression(
        baseExpr: baseExpr,
        methodTypeArgs: methodTypeArgs,
        methodName: methodName,
        arguments: arguments
      )
    }

    // Static qualified call: T.(Trait)method(...)
    if case .identifier(let baseName) = baseExpr,
       let baseType = currentScope.lookupType(baseName),
       let methodSym = extensionMethods[baseName]?[methodName] {
      guard case .function(let params, let returnType) = methodSym.type else {
        throw SemanticError(.generic("Expected function type for static qualified method"), span: currentSpan)
      }
      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: methodName,
          expected: params.count,
          got: arguments.count
        )
      }
      var typedArguments: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        var typedArg = try inferTypedExpression(arg)
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
      }
      return .staticMethodCall(
        baseType: baseType,
        methodName: methodName,
        typeArgs: [],
        methodTypeArgs: [],
        arguments: typedArguments,
        type: returnType
      )
    }

    let typedBase = try inferTypedExpression(baseExpr)

    // Qualified call on generic parameter via trait bound.
    if case .genericParameter(let paramName) = typedBase.type {
      guard hasTraitBound(paramName, traitName) else {
        throw SemanticError(.generic(
          "Type parameter '\(paramName)' does not have trait bound '\(traitName)'"
        ), span: currentSpan)
      }
      let methods = try flattenedTraitToolMethods(traitName)
      guard let method = methods[methodName], method.parameters.first?.name == "self" else {
        throw SemanticError(.generic(
          "Qualified method '\(methodName)' not found in trait tool methods of '\(traitName)'"
        ), span: currentSpan)
      }
      let expectedType = try expectedFunctionTypeForToolMethod(method, selfType: typedBase.type)
      guard case .function(let params, let returns) = expectedType else {
        throw SemanticError(.generic("Expected function type for qualified method"), span: currentSpan)
      }
      if arguments.count != params.count - 1 {
        throw SemanticError.invalidArgumentCount(
          function: methodName,
          expected: params.count - 1,
          got: arguments.count
        )
      }
      var typedArguments: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params.dropFirst()) {
        var typedArg = try inferTypedExpression(arg)
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(expected: param.type.description, got: typedArg.type.description)
        }
        typedArguments.append(typedArg)
      }
      recordTraitPlaceholderInstantiation(baseType: typedBase.type, methodName: methodName, methodTypeArgs: [])
      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: traitName,
        methodName: methodName,
        base: typedBase,
        methodTypeArgs: [],
        type: expectedType
      )
      return .call(callee: callee, arguments: typedArguments, type: returns)
    }

    // Instance qualified call on concrete methods.
    let concreteTypeName: String? = {
      switch typedBase.type {
      case .structure(let defId), .`enum`(let defId):
        return context.getName(defId)
      case .int, .int8, .int16, .int32, .int64,
           .uint, .uint8, .uint16, .uint32, .uint64,
           .float32, .float64, .bool:
        return typedBase.type.description
      default:
        return nil
      }
    }()

    if let concreteTypeName,
       let methodSym = extensionMethods[concreteTypeName]?[methodName] {
      return try inferMethodCall(
        base: typedBase,
        method: methodSym,
        methodType: methodSym.type,
        arguments: arguments
      )
    }

    if let methodSym = try lookupConcreteMethodSymbol(on: typedBase.type, name: methodName) {
      return try inferMethodCall(
        base: typedBase,
        method: methodSym,
        methodType: methodSym.type,
        arguments: arguments
      )
    }

    throw SemanticError(.generic(
      "Qualified method '\(methodName)' from trait '\(traitName)' is not available on receiver"
    ), span: currentSpan)
  }

  // MARK: - Named Argument Validation

  /// Validates named argument labels against parameter definitions.
  /// Called after arguments are type-checked to verify label correctness.
  /// - Parameters:
  ///   - callArgs: The call arguments with optional labels from the call site
  ///   - parameters: The parameter definitions with name and named flag
  ///   - callDescription: Description of the call for error messages
  private func validateNamedArguments(
    callArgs: [CallArg],
    parameters: [(name: String, named: Bool)],
    callDescription: String
  ) throws {
    let paramCount = min(callArgs.count, parameters.count)
    for i in 0..<paramCount {
      let arg = callArgs[i]
      let param = parameters[i]
      if param.named {
        // Parameter requires a label
        guard let label = arg.label else {
          throw SemanticError(.generic("Missing named argument label: expected '\(param.name)' at position \(i + 1)"), span: currentSpan)
        }
        if label != param.name {
          throw SemanticError(.generic("Named argument mismatch: expected '\(param.name)', got '\(label)' at position \(i + 1)"), span: currentSpan)
        }
      } else {
        // Parameter is positional - should not have a label
        if let label = arg.label {
          throw SemanticError(.generic("Unexpected named argument label '\(label)' at position \(i + 1): this parameter is positional"), span: currentSpan)
        }
      }
    }
  }

  /// Validates named argument labels for pattern matching against parameter definitions.
  /// - Parameters:
  ///   - patternArgs: The pattern arguments with optional labels
  ///   - parameters: The parameter definitions with name and named flag
  ///   - patternDescription: Description of the pattern for error messages
  func validateNamedPatternArguments(
    patternArgs: [PatternArg],
    parameters: [(name: String, named: Bool)],
    patternDescription: String
  ) throws {
    let paramCount = min(patternArgs.count, parameters.count)
    for i in 0..<paramCount {
      let arg = patternArgs[i]
      let param = parameters[i]
      if param.named {
        guard let label = arg.label else {
          throw SemanticError(.generic("Missing named argument label in pattern: expected '\(param.name)' at position \(i + 1)"), span: currentSpan)
        }
        if label != param.name {
          throw SemanticError(.generic("Named argument mismatch in pattern: expected '\(param.name)', got '\(label)' at position \(i + 1)"), span: currentSpan)
        }
      } else {
        if let label = arg.label {
          throw SemanticError(.generic("Unexpected named argument label '\(label)' in pattern at position \(i + 1): this parameter is positional"), span: currentSpan)
        }
      }
    }
  }
  
  /// Infers the type of a call expression
  func inferCallExpression(callee: ExpressionNode, arguments callArgs: [CallArg], expectedType: Type? = nil) throws -> TypedExpressionNode {
    // Extract bare expressions for internal use; labels are used for named argument validation
    let arguments = callArgs.map { $0.expression }
    
    if shouldRecoverCallSiteOnce {
      shouldRecoverCallSiteOnce = false
      if case .identifier(let name) = callee,
        let callSpan = bestEffortIdentifierCallSpan(name, startLine: currentSpan.start.line)
      {
        currentSpan = callSpan
      }
    }

    // Compiler protocol methods are blocked after concrete method resolution,
    // based on structural method kind metadata rather than name checks.
    // Check if callee is a module-qualified static method call (e.g., module.Type.method())
    if case .memberPath(let baseExpr, let path) = callee,
       case .identifier(let moduleName) = baseExpr,
       path.count >= 2 {
      // Check if the base identifier is a module symbol
      if let moduleDefId = currentScope.lookup(moduleName, sourceFile: currentSourceFile),
        let moduleType = defIdMap.getSymbolType(moduleDefId),
        case .module(let moduleInfo) = moduleType {
        if !isModuleSymbolImported(moduleInfo.modulePath, symbolName: moduleName) {
          throw SemanticError(.generic("Module '\(moduleName)' is not imported"), span: currentSpan)
        }
        let typeName = path[0]
        let methodName = path[1]
        
        // Look up the type in the module's public types
        if let type = moduleInfo.publicTypes[typeName] {
          if case .structure(let defId) = type {
            let access = context.getAccess(defId) ?? .protected
            if !isSymbolAccessibleForModuleAccess(symbolAccess: access, defId: defId) {
              let accessLabel = access == .private ? "private" : "protected"
              throw SemanticError(.generic(
                "Cannot access \(accessLabel) symbol '\(typeName)' of module '\(moduleName)'"
              ), span: currentSpan)
            }
          }
          // Handle concrete struct types
          if case .structure(let defId) = type {
            let typeName = context.getName(defId) ?? ""
            // Look up static method on the struct using simple name (how extensionMethods is keyed)
            if let methods = extensionMethods[typeName], let methodSym = methods[methodName] {
              // Check if it's a static method (no self parameter or first param is not self)
              let isStatic: Bool
              if case .function(let params, _) = methodSym.type {
                _ = params
                isStatic = !isReceiverStyleMethod(methodSym)
              } else {
                isStatic = true
              }
              
              if isStatic {
                
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
                }
                
                if arguments.count != params.count {
                  throw SemanticError.invalidArgumentCount(
                    function: methodName,
                    expected: params.count,
                    got: arguments.count
                  )
                }
                
                var typedArguments: [TypedExpressionNode] = []
                for (arg, param) in zip(arguments, params) {
                  var typedArg = try inferTypedExpression(arg)
                  typedArg = try coerceLiteral(typedArg, to: param.type)
                  if typedArg.type != param.type {
                    throw SemanticError.typeMismatch(
                      expected: param.type.description,
                      got: typedArg.type.description
                    )
                  }
                  typedArguments.append(typedArg)
                }
                
                return .staticMethodCall(
                  baseType: type,
                  methodName: methodName,
                  typeArgs: [],
                  methodTypeArgs: [],
                  arguments: typedArguments,
                  type: returnType
                )
              }
            }
          }
          
          // Handle concrete enum types
          if case .`enum`(let defId) = type {
            let enumCases = context.getEnumCases(defId) ?? []
            // Check if it's a enum case constructor
            if let c = enumCases.first(where: { $0.name == methodName }) {
              let params = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
              
              if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                  function: "\(typeName).\(methodName)",
                  expected: params.count,
                  got: arguments.count
                )
              }
              
              // Validate named argument labels for enum case construction
              try validateNamedArguments(
                callArgs: callArgs,
                parameters: c.parameters.map { (name: $0.name, named: $0.named) },
                callDescription: "\(typeName).\(methodName)"
              )
              
              var typedArgs: [TypedExpressionNode] = []
              for (arg, param) in zip(arguments, params) {
                var typedArg = try inferTypedExpression(arg)
                typedArg = try coerceLiteral(typedArg, to: param.type)
                if typedArg.type != param.type {
                  throw SemanticError.typeMismatch(
                    expected: param.type.description, got: typedArg.type.description)
                }
                typedArgs.append(typedArg)
              }
              
              return .enumConstruction(type: type, caseName: methodName, arguments: typedArgs)
            }
            
            // Look up static method on the enum using simple name
            let enumName = context.getName(defId) ?? ""
            if let methods = extensionMethods[enumName], let methodSym = methods[methodName] {
              let isStatic: Bool
              if case .function(let params, _) = methodSym.type {
                _ = params
                isStatic = !isReceiverStyleMethod(methodSym)
              } else {
                isStatic = true
              }
              
              if isStatic {
                
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
                }
                
                if arguments.count != params.count {
                  throw SemanticError.invalidArgumentCount(
                    function: methodName,
                    expected: params.count,
                    got: arguments.count
                  )
                }
                
                var typedArguments: [TypedExpressionNode] = []
                for (arg, param) in zip(arguments, params) {
                  var typedArg = try inferTypedExpression(arg)
                  typedArg = try coerceLiteral(typedArg, to: param.type)
                  if typedArg.type != param.type {
                    throw SemanticError.typeMismatch(
                      expected: param.type.description,
                      got: typedArg.type.description
                    )
                  }
                  typedArguments.append(typedArg)
                }
                
                return .staticMethodCall(
                  baseType: type,
                  methodName: methodName,
                  typeArgs: [],
                  methodTypeArgs: [],
                  arguments: typedArguments,
                  type: returnType
                )
              }
            }
          }
        }
        
        // Also try looking up the type from global scope (for types not yet in module's publicTypes)
        if let type = currentScope.lookupType(typeName) {
          try checkTypeVisibility(type: type, typeName: typeName)
          if case .structure(let defId) = type {
            let name = context.getName(defId) ?? ""
            if let methods = extensionMethods[name], let methodSym = methods[methodName] {
              let isStatic: Bool
              if case .function(let params, _) = methodSym.type {
                _ = params
                isStatic = !isReceiverStyleMethod(methodSym)
              } else {
                isStatic = true
              }
              
              if isStatic {
                
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
                }
                
                if arguments.count != params.count {
                  throw SemanticError.invalidArgumentCount(
                    function: methodName,
                    expected: params.count,
                    got: arguments.count
                  )
                }
                
                var typedArguments: [TypedExpressionNode] = []
                for (arg, param) in zip(arguments, params) {
                  var typedArg = try inferTypedExpression(arg)
                  typedArg = try coerceLiteral(typedArg, to: param.type)
                  if typedArg.type != param.type {
                    throw SemanticError.typeMismatch(
                      expected: param.type.description,
                      got: typedArg.type.description
                    )
                  }
                  typedArguments.append(typedArg)
                }
                
                return .staticMethodCall(
                  baseType: type,
                  methodName: methodName,
                  typeArgs: [],
                  methodTypeArgs: [],
                  arguments: typedArguments,
                  type: returnType
                )
              }
            }
          }
        }
      }
    }
    
    // Static trait method calls on generic parameter types (e.g., T.method())
    if case .memberPath(let baseExpr, let path) = callee,
       case .identifier(let baseName) = baseExpr,
       path.count == 1,
       let baseType = currentScope.lookupType(baseName),
       case .genericParameter(let paramName) = baseType
    {
      let methodName = path[0]
      if let bounds = genericTraitBounds[paramName] {
        for traitConstraint in bounds {
          let traitName = traitConstraint.baseName
          let methods = try flattenedTraitMethods(traitName)
          if let sig = methods[methodName], sig.parameters.first?.name != "self" {
            let traitInfo = traits[traitName]
            var traitTypeArgs: [Type] = []
            if case .generic(_, let argNodes) = traitConstraint {
              for argNode in argNodes {
                let argType = try resolveTypeNode(argNode)
                traitTypeArgs.append(argType)
              }
            }

            let expectedType = try expectedFunctionTypeForTraitMethod(
              sig,
              selfType: baseType,
              traitInfo: traitInfo,
              traitTypeArgs: traitTypeArgs
            )

            guard case .function(let params, let returnType) = expectedType else {
              throw SemanticError(.generic("Expected function type for static trait method"), span: currentSpan)
            }

            if arguments.count != params.count {
              throw SemanticError.invalidArgumentCount(
                function: methodName,
                expected: params.count,
                got: arguments.count
              )
            }

            var typedArguments: [TypedExpressionNode] = []
            for (arg, param) in zip(arguments, params) {
              var typedArg = try inferTypedExpression(arg)
              typedArg = try coerceLiteral(typedArg, to: param.type)
              if typedArg.type != param.type {
                throw SemanticError.typeMismatch(
                  expected: param.type.description,
                  got: typedArg.type.description
                )
              }
              typedArguments.append(typedArg)
            }

            return .staticMethodCall(
              baseType: baseType,
              methodName: methodName,
              typeArgs: [],
              methodTypeArgs: [],
              arguments: typedArguments,
              type: returnType
            )
          }

          let toolMethods = try flattenedTraitToolMethods(traitName)
          if let entityMethod = toolMethods[methodName],
             entityMethod.parameters.first?.name != "self" {
            let expectedType = try expectedFunctionTypeForToolMethod(entityMethod, selfType: baseType)
            guard case .function(let params, let returnType) = expectedType else {
              throw SemanticError(.generic("Expected function type for static trait entity method"), span: currentSpan)
            }

            if arguments.count != params.count {
              throw SemanticError.invalidArgumentCount(
                function: methodName,
                expected: params.count,
                got: arguments.count
              )
            }

            var typedArguments: [TypedExpressionNode] = []
            for (arg, param) in zip(arguments, params) {
              var typedArg = try inferTypedExpression(arg)
              typedArg = try coerceLiteral(typedArg, to: param.type)
              if typedArg.type != param.type {
                throw SemanticError.typeMismatch(
                  expected: param.type.description,
                  got: typedArg.type.description
                )
              }
              typedArguments.append(typedArg)
            }

            return .staticMethodCall(
              baseType: baseType,
              methodName: methodName,
              typeArgs: [],
              methodTypeArgs: [],
              arguments: typedArguments,
              type: returnType
            )
          }
        }
      }
    }

    // Check if callee is a static method call on a generic type (e.g., [Int]List.new())
    if case .memberPath(let baseExpr, let path) = callee,
       case .genericInstantiation(let baseName, let args) = baseExpr,
       path.count == 1 {
      let memberName = path[0]
      let resolvedArgs = try args.map { try resolveTypeNode($0) }
      
      // Check if it's a generic struct with a static method
      if let template = currentScope.lookupGenericStructTemplate(baseName) {
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic arguments",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        
        // Record instantiation request for deferred monomorphization
        if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .structType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Create parameterized type
        let baseType = Type.genericStruct(template: baseName, args: resolvedArgs)
        
        // Look up static method on generic struct
        if let extensions = genericExtensionMethods[baseName] {
          if let ext = extensions.first(where: { $0.method.name == memberName }) {
            let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
            if isStatic {
              let methodSym = try resolveGenericExtensionMethod(
                baseType: baseType, templateName: baseName, typeArgs: resolvedArgs,
                methodInfo: ext)
              
              // Get function parameters and return type
              guard case .function(let params, let returnType) = methodSym.type else {
                throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
              }
              
              // Check argument count
              if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                  function: memberName,
                  expected: params.count,
                  got: arguments.count
                )
              }
              
              // Type check arguments
              var typedArguments: [TypedExpressionNode] = []
              for (arg, param) in zip(arguments, params) {
                var typedArg = try inferTypedExpression(arg)
                typedArg = try coerceLiteral(typedArg, to: param.type)
                if typedArg.type != param.type {
                  throw SemanticError.typeMismatch(
                    expected: param.type.description,
                    got: typedArg.type.description
                  )
                }
                typedArguments.append(typedArg)
              }
              
              // Return staticMethodCall node
              return .staticMethodCall(
                baseType: baseType,
                methodName: memberName,
                typeArgs: resolvedArgs,
                methodTypeArgs: [],
                arguments: typedArguments,
                type: returnType
              )
            }
          }
        }
      }
      
      // Check if it's a generic enum with a case constructor or static method
      if let template = currentScope.lookupGenericEnumTemplate(baseName) {
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic arguments",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        
        // Record instantiation request for deferred monomorphization
        if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .enumType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Create parameterized type
        let baseType = Type.genericEnum(template: baseName, args: resolvedArgs)
        
        // Check if it's a enum case constructor
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = resolvedArgs[i]
        }
        
        if let c = template.cases.first(where: { $0.name == memberName }) {
          let resolvedParams = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try c.parameters.map { param -> Parameter in
              let paramType = try resolveTypeNode(param.type)
              return Parameter(type: paramType, kind: .byVal)
            }
          }
          
          if arguments.count != resolvedParams.count {
            throw SemanticError.invalidArgumentCount(
              function: "\(baseName).\(memberName)",
              expected: resolvedParams.count,
              got: arguments.count
            )
          }
          
          // Validate named argument labels for generic enum case construction
          try validateNamedArguments(
            callArgs: callArgs,
            parameters: c.parameters.map { (name: $0.name, named: $0.named) },
            callDescription: "\(baseName).\(memberName)"
          )
          
          var typedArgs: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, resolvedParams) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = try coerceLiteral(typedArg, to: param.type)
            if typedArg.type != param.type {
              throw SemanticError.typeMismatch(
                expected: param.type.description, got: typedArg.type.description)
            }
            typedArgs.append(typedArg)
          }
          
          return .enumConstruction(type: baseType, caseName: memberName, arguments: typedArgs)
        }
        
        // Look up static method on generic enum
        if let extensions = genericExtensionMethods[baseName] {
          if let ext = extensions.first(where: { $0.method.name == memberName }) {
            let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
            if isStatic {
              let methodSym = try resolveGenericExtensionMethod(
                baseType: baseType, templateName: baseName, typeArgs: resolvedArgs,
                methodInfo: ext)
              
              guard case .function(let params, let returnType) = methodSym.type else {
                throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
              }
              
              if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                  function: memberName,
                  expected: params.count,
                  got: arguments.count
                )
              }
              
              var typedArguments: [TypedExpressionNode] = []
              for (arg, param) in zip(arguments, params) {
                var typedArg = try inferTypedExpression(arg)
                typedArg = try coerceLiteral(typedArg, to: param.type)
                if typedArg.type != param.type {
                  throw SemanticError.typeMismatch(
                    expected: param.type.description,
                    got: typedArg.type.description
                  )
                }
                typedArguments.append(typedArg)
              }
              
              return .staticMethodCall(
                baseType: baseType,
                methodName: memberName,
                typeArgs: resolvedArgs,
                methodTypeArgs: [],
                arguments: typedArguments,
                type: returnType
              )
            }
          }
        }
      }
    }
    
    // Check if callee is a generic instantiation (Constructor call or Function call)
    if case .genericInstantiation(let base, let args) = callee {
      return try inferGenericInstantiationCall(base: base, args: args, arguments: arguments, callArgs: callArgs)
    }

    // Resolve Callee (Check Enum Constructor)
    var preResolvedCallee: TypedExpressionNode? = nil
    do {
      preResolvedCallee = try inferTypedExpression(callee)
    } catch is SemanticError {
      // Fallthrough
      preResolvedCallee = nil
    }

    if let resolved = preResolvedCallee, case .variable(let symbol) = resolved {
      if case .function(_, let returnType) = symbol.type {
        // Check for enum constructor (both concrete and generic)
        var enumName: String? = nil
        if case .`enum`(let defId) = returnType {
          enumName = context.getName(defId)
        } else if case .genericEnum(let templateName, _) = returnType {
          enumName = templateName
        }
        
        if let uName = enumName {
          // Check if symbol name is uName.CaseName
          let symbolName = context.getName(symbol.defId) ?? ""
          if symbolName.starts(with: uName + ".") {
            let caseName = String(symbolName.dropFirst(uName.count + 1))
            let params = symbol.type.functionParameters!

            if arguments.count != params.count {
              throw SemanticError.invalidArgumentCount(
                function: symbolName, expected: params.count, got: arguments.count)
            }

            // Validate named argument labels for enum case construction
            if let namedParams = functionNamedParams[symbol.defId] {
              try validateNamedArguments(
                callArgs: callArgs,
                parameters: namedParams,
                callDescription: symbolName
              )
            }

            var typedArgs: [TypedExpressionNode] = []
            for (arg, param) in zip(arguments, params) {
              var typedArg = try inferTypedExpression(arg, expectedType: param.type)
              typedArg = try coerceLiteral(typedArg, to: param.type)
              if typedArg.type != param.type {
                throw SemanticError.typeMismatch(
                  expected: param.type.description, got: typedArg.type.description)
              }
              typedArgs.append(typedArg)
            }

            return .enumConstruction(type: returnType, caseName: caseName, arguments: typedArgs)
          }
        }
      }
    }

    // Check if it is a constructor call OR implicit generic function call
    if case .identifier(let name) = callee {
      // 1. Try Generic Function Template (Implicit Inference)
      if let template = currentScope.lookupGenericFunctionTemplate(name) {
        return try inferImplicitGenericFunctionCall(
          template: template,
          name: name,
          arguments: arguments,
          expectedReturnType: expectedType
        )
      }

      if let type = currentScope.lookupType(name, sourceFile: currentSourceFile) {
        if case .opaque = type {
          throw SemanticError(.opaqueTypeCannotBeInstantiated(typeName: type.description), span: currentSpan)
        }
        guard case .structure(let defId) = type else {
          throw SemanticError.invalidOperation(
            op: "construct", type1: type.description, type2: "")
        }
        let parameters = context.getStructMembers(defId) ?? []

        try ensureStructConstructionAccess(
          typeName: name,
          defId: defId,
          members: parameters,
          span: currentSpan
        )

        if arguments.count != parameters.count {
          throw SemanticError.invalidArgumentCount(
            function: name,
            expected: parameters.count,
            got: arguments.count
          )
        }

        // Validate named argument labels for struct construction
        try validateNamedArguments(
          callArgs: callArgs,
          parameters: parameters.map { (name: $0.name, named: $0.named) },
          callDescription: name
        )

        var typedArguments: [TypedExpressionNode] = []
        for (arg, expectedMember) in zip(arguments, parameters) {
          var typedArg = try inferTypedExpression(arg, expectedType: expectedMember.type)
          typedArg = try coerceLiteral(typedArg, to: expectedMember.type)
          if typedArg.type != expectedMember.type {
            throw SemanticError.typeMismatch(
              expected: expectedMember.type.description,
              got: typedArg.type.description
            )
          }
          typedArguments.append(typedArg)
        }

        return .typeConstruction(
          identifier: makeLocalSymbol(name: name, type: type, kind: .type),
          typeArgs: nil,
          arguments: typedArguments,
          type: type
        )
      }
      
      // 2. Try Generic Struct/Enum Template (Implicit Type Inference)
      // Only for identifiers starting with uppercase (type naming convention)
      // This allows writing Stream(iter) instead of [T, R]Stream(iter)
      if let firstChar = name.first, firstChar.isUppercase {
        // Try generic struct template
        if let template = currentScope.lookupGenericStructTemplate(name) {
          // Validate named argument labels for generic struct construction
          try validateNamedArguments(
            callArgs: callArgs,
            parameters: template.parameters.map { (name: $0.name, named: $0.named) },
            callDescription: name
          )
          return try inferGenericStructConstruction(template: template, name: name, arguments: arguments)
        }
        
        // Try generic enum template (for enum case constructors without dot notation)
        // Note: This is less common since enum cases are usually accessed via .CaseName
      }
    }

    // Special handling for intrinsic function calls (alloc_memory, etc.)
    if case .identifier(let name) = callee {
      if let intrinsicNode = try checkIntrinsicCall(name: name, arguments: arguments) {
        return intrinsicNode
      }
    }

    let typedCallee = try inferTypedExpression(callee)

    // Secondary guard: if the resolved callee is a special compiler method, block explicit calls.
    if case .traitMethodPlaceholder(let traitName, let methodName, _, _, _) = typedCallee,
       traitName == "Drop" && methodName == "drop" {
      throw SemanticError(
        .generic("compiler protocol method drop cannot be called explicitly"),
        span: currentSpan)
    }

    // Method call
    if case .methodReference(let base, let method, _, _, let methodType) = typedCallee {
      if isStdDropMethodSymbol(method) {
        throw SemanticError(
          .generic("compiler protocol method drop cannot be called explicitly"),
          span: currentSpan)
      }
      // Validate named argument labels for method calls (including trait object method calls)
      if let namedParams = functionNamedParams[method.defId], namedParams.count > 0 {
        // Skip self parameter for method calls if the first param is self
        let callSiteParams: [(name: String, named: Bool)]
        if namedParams.first?.name == "self" {
          callSiteParams = Array(namedParams.dropFirst())
        } else {
          callSiteParams = namedParams
        }
        if !callSiteParams.isEmpty {
          try validateNamedArguments(
            callArgs: callArgs,
            parameters: callSiteParams,
            callDescription: context.getName(method.defId) ?? "method"
          )
        }
      }
      return try inferMethodCall(
        base: base,
        method: method,
        methodType: methodType,
        arguments: arguments,
        expectedReturnType: expectedType
      )
    }

    // Trait method placeholder call (for trait methods on generic parameters)
    if case .traitMethodPlaceholder(let traitName, let methodName, let base, let methodTypeArgs, let methodType) = typedCallee {
      // For trait method placeholders, we need to handle the call similarly to method calls
      // The base is already included in the placeholder, so we just need to type-check the arguments
      guard case .function(let params, let returns) = methodType else {
        throw SemanticError.invalidOperation(op: "call", type1: methodType.description, type2: "")
      }
      
      // Validate named argument labels using the trait method signature
      if traits[traitName] != nil {
        let allMethods = try flattenedTraitMethods(traitName)
        if let sig = allMethods[methodName] {
          // Build named param info from trait method signature, skipping self
          let namedParams = sig.parameters.dropFirst().map { (name: $0.name, named: $0.named) }
          try validateNamedArguments(
            callArgs: callArgs,
            parameters: namedParams,
            callDescription: "\(traitName).\(methodName)"
          )
        }
      }
      
      // The first parameter is 'self' (the base), so we check remaining arguments
      let expectedArgCount = params.count - 1
      if arguments.count != expectedArgCount {
        throw SemanticError.invalidArgumentCount(
          function: "trait method",
          expected: expectedArgCount,
          got: arguments.count
        )
      }
      
      // Adjust base to match expected self parameter type
      var adjustedBase = base
      if let firstParam = params.first, adjustedBase.type != firstParam.type {
        if case .reference(let inner) = firstParam.type, inner == adjustedBase.type {
          if adjustedBase.valueCategory == .rvalue {
            throw SemanticError(.generic("Cannot call 'self ref' method '\(methodName)' on an rvalue; store the value in a 'let mut' variable first"), span: currentSpan)
          }
          guard allowsImplicitMutableSelfReference(adjustedBase) else {
            let name = implicitSelfRefViolationName(adjustedBase) ?? "<value>"
            throw SemanticError(.cannotTakeRefOfImmutable(name), span: currentSpan)
          }
          adjustedBase = .referenceExpression(expression: adjustedBase, type: firstParam.type)
        } else if case .reference(let inner) = adjustedBase.type, inner == firstParam.type {
          adjustedBase = .derefExpression(expression: adjustedBase, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: firstParam.type.description,
            got: adjustedBase.type.description
          )
        }
      }

      var typedArguments: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params.dropFirst()) {
        var typedArg: TypedExpressionNode
        if case .lambdaExpression(let lambdaParams, let returnType, let body, _) = arg {
          typedArg = try inferLambdaExpression(
            parameters: lambdaParams,
            returnType: returnType,
            body: body,
            expectedType: param.type
          )
        } else if case .rangeExpression(let op, let left, let right) = arg {
          typedArg = try inferRangeExpression(
            operator: op,
            left: left,
            right: right,
            expectedType: param.type
          )
        } else {
          typedArg = try inferTypedExpression(arg, expectedType: param.type)
        }
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
      }
      
      let adjustedCallee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: traitName,
        methodName: methodName,
        base: adjustedBase,
        methodTypeArgs: methodTypeArgs,
        type: methodType
      )
      return .call(
        callee: adjustedCallee,
        arguments: typedArguments,
        type: returns
      )
    }

    // Function call
    if case .function(let params, let returns) = typedCallee.type {
      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: "expression",
          expected: params.count,
          got: arguments.count
        )
      }

      // Validate named argument labels if the callee is a known function (not a function type variable)
      if case .variable(let symbol) = typedCallee,
         let namedParams = functionNamedParams[symbol.defId] {
        try validateNamedArguments(
          callArgs: callArgs,
          parameters: namedParams,
          callDescription: context.getName(symbol.defId) ?? "function"
        )
      }

      var typedArguments: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        var typedArg: TypedExpressionNode
        // For Lambda expressions, pass the expected type for type inference
        if case .lambdaExpression(let lambdaParams, let returnType, let body, _) = arg {
          typedArg = try inferLambdaExpression(
            parameters: lambdaParams,
            returnType: returnType,
            body: body,
            expectedType: param.type
          )
        } else {
          // Pass expected type for implicit member expression support
          typedArg = try inferTypedExpression(arg, expectedType: param.type)
        }
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
      }

      return .call(
        callee: typedCallee,
        arguments: typedArguments,
        type: returns
      )
    }

    throw SemanticError.invalidOperation(
      op: "call", type1: typedCallee.type.description, type2: "")
  }
}


// MARK: - Generic Instantiation Call Inference

extension TypeChecker {
  
  /// Infers the type of a generic instantiation call (e.g., [Int]List(...) or [T]func(...))
  func inferGenericInstantiationCall(base: String, args: [TypeNode], arguments: [ExpressionNode], callArgs: [CallArg]? = nil) throws -> TypedExpressionNode {
    if let template = currentScope.lookupGenericStructTemplate(base) {
      try ensureStructConstructionAccess(
        typeName: base,
        defId: template.defId,
        members: template.parameters.map { param in
          (name: param.name, type: .void, mutable: param.mutable, access: param.access, named: param.named)
        },
        span: currentSpan
      )

      let resolvedArgs = try args.map { try resolveTypeNode($0) }
      
      // Validate type argument count
      guard template.typeParameters.count == resolvedArgs.count else {
        throw SemanticError.typeMismatch(
          expected: "\(template.typeParameters.count) generic arguments",
          got: "\(resolvedArgs.count)"
        )
      }
      
      // Validate generic constraints
      try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
      
      // Record instantiation request for deferred monomorphization
      // Skip if any argument contains generic parameters (will be recorded when fully resolved)
      if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
        recordInstantiation(InstantiationRequest(
          kind: .structType(template: template, args: resolvedArgs),
          sourceLine: currentLine,
          sourceFileName: currentFileName
        ))
      }
      
      // Create type substitution map
      var substitution: [String: Type] = [:]
      for (i, param) in template.typeParameters.enumerated() {
        substitution[param.name] = resolvedArgs[i]
      }
      
      // Resolve member types with substitution
      let memberTypes = try withNewScope {
        for (paramName, paramType) in substitution {
          try currentScope.defineType(paramName, type: paramType)
        }
        return try template.parameters.map { param -> (name: String, type: Type, mutable: Bool) in
          let fieldType = try resolveTypeNode(param.type)
          return (name: param.name, type: fieldType, mutable: param.mutable)
        }
      }

      if arguments.count != memberTypes.count {
        throw SemanticError.invalidArgumentCount(
          function: base,
          expected: memberTypes.count,
          got: arguments.count
        )
      }

      // Validate named argument labels for generic struct construction
      if let callArgs = callArgs {
        try validateNamedArguments(
          callArgs: callArgs,
          parameters: template.parameters.map { (name: $0.name, named: $0.named) },
          callDescription: base
        )
      }

      var typedArguments: [TypedExpressionNode] = []
      for (arg, expectedMember) in zip(arguments, memberTypes) {
        var typedArg = try inferTypedExpression(arg)
        typedArg = try coerceLiteral(typedArg, to: expectedMember.type)
        if typedArg.type != expectedMember.type {
          throw SemanticError.typeMismatch(
            expected: expectedMember.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
      }
      
      // Return parameterized type
      let genericType = Type.genericStruct(template: base, args: resolvedArgs)

      return .typeConstruction(
        identifier: makeLocalSymbol(name: base, type: genericType, kind: .type),
        typeArgs: resolvedArgs,
        arguments: typedArguments,
        type: genericType
      )
    } else if let template = currentScope.lookupGenericFunctionTemplate(base) {
      // Special handling for explicit intrinsic template calls (e.g. [Int]alloc_memory)
      if base == "alloc_memory" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        let T = resolvedArgs[0]

        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        var countExpr = try inferTypedExpression(arguments[0])
        countExpr = try coerceLiteral(countExpr, to: .uint)
        if countExpr.type != .uint {
          throw SemanticError.typeMismatch(expected: "UInt", got: countExpr.type.description)
        }

        return .intrinsicCall(
          .allocMemory(count: countExpr, resultType: .pointer(element: T)))
      }

      if base == "dealloc_memory" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        // We don't need T, but we checked args count.

        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let ptrExpr = try inferTypedExpression(arguments[0])
        // Check pointer type? Sema checks this later for normal calls, but here we do it maybe?
        // Actually, `ptrExpr.type` should match `[T]Ptr`.
        return .intrinsicCall(.deallocMemory(ptr: ptrExpr))
      }
      if base == "init_memory" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.count == 2 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 2, got: arguments.count)
        }
        let ptrExpr = try inferTypedExpression(arguments[0])
        guard case .pointer(let elementType) = ptrExpr.type else {
          throw SemanticError(.generic("cannot dereference non-pointer type"))
        }
        var valExpr = try inferTypedExpression(arguments[1])
        valExpr = try coerceLiteral(valExpr, to: elementType)
        if valExpr.type != elementType {
          throw SemanticError.typeMismatch(
            expected: elementType.description, got: valExpr.type.description)
        }
        return .intrinsicCall(.initMemory(ptr: ptrExpr, val: valExpr))
      }

      if base == "deinit_memory" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let ptrExpr = try inferTypedExpression(arguments[0])
        guard case .pointer = ptrExpr.type else {
          throw SemanticError(.generic("cannot dereference non-pointer type"))
        }
        return .intrinsicCall(.deinitMemory(ptr: ptrExpr))
      }

      if base == "take_memory" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let ptrExpr = try inferTypedExpression(arguments[0])
        guard case .pointer = ptrExpr.type else {
          throw SemanticError(.generic("cannot dereference non-pointer type"))
        }
        return .intrinsicCall(.takeMemory(ptr: ptrExpr))
      }

      if base == "null_ptr" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.isEmpty else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 0, got: arguments.count)
        }
        let resultType = Type.pointer(element: resolvedArgs[0])
        return .intrinsicCall(.nullPtr(resultType: resultType))
      }

      if base == "ref_count" {
        _ = try args.map { try resolveTypeNode($0) }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let val = try inferTypedExpression(arguments[0])
        return .intrinsicCall(.refCount(val: val))
      }
      if base == "ref_is_borrow" {
        _ = try args.map { try resolveTypeNode($0) }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let val = try inferTypedExpression(arguments[0])
        return .intrinsicCall(.refIsBorrow(val: val))
      }
      if base == "downgrade_ref" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let val = try inferTypedExpression(arguments[0])
        // Verify argument is a reference type
        guard case .reference(let inner) = val.type else {
          throw SemanticError.typeMismatch(
            expected: "\(resolvedArgs[0]) ref", got: val.type.description)
        }
        let resultType = Type.weakReference(inner: inner)
        return .intrinsicCall(.downgradeRef(val: val, resultType: resultType))
      }
      if base == "upgrade_ref" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let val = try inferTypedExpression(arguments[0])
        // Verify argument is a weak reference type
        guard case .weakReference(let inner) = val.type else {
          throw SemanticError.typeMismatch(
            expected: "\(resolvedArgs[0]) weakref", got: val.type.description)
        }
        // Return type is Option[T ref]
        let refType = Type.reference(inner: inner)
        let optionType = Type.genericEnum(template: "Option", args: [refType])
        
        // Record instantiation request for Option type
        if let optionTemplate = currentScope.lookupGenericEnumTemplate("Option") {
          recordInstantiation(InstantiationRequest(
            kind: .enumType(template: optionTemplate, args: [refType]),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        return .intrinsicCall(.upgradeRef(val: val, resultType: optionType))
      }
      if base == "copy_memory" {
        _ = try args.map { try resolveTypeNode($0) }
        guard arguments.count == 3 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 3, got: arguments.count)
        }
        let d = try inferTypedExpression(arguments[0])
        let s = try inferTypedExpression(arguments[1])
        let c = try inferTypedExpression(arguments[2])
        return .intrinsicCall(.copyMemory(dest: d, source: s, count: c))
      }
      if base == "move_memory" {
        _ = try args.map { try resolveTypeNode($0) }
        guard arguments.count == 3 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 3, got: arguments.count)
        }
        let d = try inferTypedExpression(arguments[0])
        let s = try inferTypedExpression(arguments[1])
        let c = try inferTypedExpression(arguments[2])
        return .intrinsicCall(.moveMemory(dest: d, source: s, count: c))
      }

      let resolvedArgs = try args.map { try resolveTypeNode($0) }
      
      // Validate type argument count
      guard template.typeParameters.count == resolvedArgs.count else {
        throw SemanticError.typeMismatch(
          expected: "\(template.typeParameters.count) generic arguments",
          got: "\(resolvedArgs.count)"
        )
      }
      
      // Validate generic constraints
      try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
      
      // Record instantiation request for deferred monomorphization
      // Skip if any argument contains generic parameters (will be recorded when fully resolved)
      if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
        recordInstantiation(InstantiationRequest(
          kind: .function(template: template, args: resolvedArgs),
          sourceLine: currentLine,
          sourceFileName: currentFileName
        ))
      }
      
      // Create type substitution map
      var substitution: [String: Type] = [:]
      for (i, param) in template.typeParameters.enumerated() {
        substitution[param.name] = resolvedArgs[i]
      }
      
      // Resolve parameter and return types with substitution
      let (params, returnType) = try withNewScope {
        for (paramName, paramType) in substitution {
          try currentScope.defineType(paramName, type: paramType)
        }
        let resolvedParams = try template.parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
        }
        let resolvedReturn = try resolveTypeNode(template.returnType)
        return (resolvedParams, resolvedReturn)
      }

      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: base,
          expected: params.count,
          got: arguments.count
        )
      }

      var typedArguments: [TypedExpressionNode] = []
      for (arg, expectedParam) in zip(arguments, params) {
        var typedArg = try inferTypedExpression(arg)
        typedArg = try coerceLiteral(typedArg, to: expectedParam.type)
        if typedArg.type != expectedParam.type {
          throw SemanticError.typeMismatch(
            expected: expectedParam.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
      }

      // Return genericCall node instead of instantiated call
      return .genericCall(
        functionName: base,
        typeArgs: resolvedArgs,
        arguments: typedArguments,
        type: returnType
      )
    } else {
      throw SemanticError.functionNotFound(base)
    }
  }
  
  /// Infers the type of an implicit generic function call (type arguments inferred from arguments)
  func inferImplicitGenericFunctionCall(
    template: GenericFunctionTemplate,
    name: String,
    arguments: [ExpressionNode],
    expectedReturnType: Type? = nil
  ) throws -> TypedExpressionNode {
    if name == "null_ptr" && arguments.isEmpty {
      return .intrinsicCall(.nullPtr(resultType: .pointer(element: .void)))
    }

    var inferred: [String: Type] = [:]

    func resolveTemplateTypeNode(_ typeNode: TypeNode, inferredBindings: [String: Type]) throws -> Type {
      try withNewScope {
        for typeParam in template.typeParameters {
          let bound = inferredBindings[typeParam.name] ?? .genericParameter(name: typeParam.name)
          try currentScope.defineType(typeParam.name, type: bound)
        }
        return try resolveTypeNode(typeNode)
      }
    }

    let hasImplicitMemberArgument = arguments.contains { arg in
      if case .implicitMemberExpression = arg {
        return true
      }
      return false
    }

    if let expectedReturnType, hasImplicitMemberArgument {
      let unresolvedReturnType = try resolveTemplateTypeNode(template.returnType, inferredBindings: inferred)
      _ = unifyTypes(unresolvedReturnType, expectedReturnType, bindings: &inferred)
    }

    if arguments.count != template.parameters.count {
      throw SemanticError.invalidArgumentCount(
        function: name,
        expected: template.parameters.count,
        got: arguments.count
      )
    }

    var typedArguments: [TypedExpressionNode] = []
    for (argExpr, param) in zip(arguments, template.parameters) {
      let expectedType = try resolveTemplateTypeNode(param.type, inferredBindings: inferred)
      var typedArg = try inferTypedExpression(argExpr, expectedType: expectedType)
      typedArg = try coerceLiteral(typedArg, to: expectedType)
      typedArguments.append(typedArg)
    }
    
    // Use enhanced unification with trait-based inference
    try unifyWithTraitInference(template: template, arguments: typedArguments, inferred: &inferred)

    let resolvedArgs = try template.typeParameters.map { param -> Type in
      guard let type = inferred[param.name] else {
        throw SemanticError.typeMismatch(
          expected: "inferred type for \(param.name)", got: "unknown")
      }
      return type
    }

    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in template.typeParameters.enumerated() {
      substitution[param.name] = resolvedArgs[i]
    }

    // Re-check arguments with resolved types and apply literal coercion.
    let resolvedParams = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      return try template.parameters.map { param -> Type in
        try resolveTypeNode(param.type)
      }
    }
    var finalTypedArguments: [TypedExpressionNode] = []
    for (argExpr, expectedType) in zip(arguments, resolvedParams) {
      var typedArg = try inferTypedExpression(argExpr, expectedType: expectedType)
      typedArg = try coerceLiteral(typedArg, to: expectedType)
      let coerced = typedArg
      if coerced.type != .never && coerced.type != expectedType {
        throw SemanticError.typeMismatch(
          expected: expectedType.description, got: coerced.type.description)
      }
      finalTypedArguments.append(coerced)
    }
    typedArguments = finalTypedArguments

    let templateName = template.name(in: defIdMap) ?? ""
    if templateName == "init_memory" {
      guard case .pointer(let elementType) = typedArguments[0].type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }
      let val = typedArguments[1]
      if val.type != elementType {
        throw SemanticError.typeMismatch(
          expected: elementType.description, got: val.type.description)
      }
      return .intrinsicCall(.initMemory(ptr: typedArguments[0], val: val))
    }
    if templateName == "deinit_memory" {
      guard case .pointer = typedArguments[0].type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }
      return .intrinsicCall(.deinitMemory(ptr: typedArguments[0]))
    }
    if templateName == "take_memory" {
      guard case .pointer = typedArguments[0].type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }
      return .intrinsicCall(.takeMemory(ptr: typedArguments[0]))
    }
    if templateName == "null_ptr" {
      guard typedArguments.isEmpty else {
        throw SemanticError.invalidArgumentCount(
          function: templateName, expected: 0, got: typedArguments.count)
      }
      let resultType = Type.pointer(element: resolvedArgs[0])
      return .intrinsicCall(.nullPtr(resultType: resultType))
    }
    if templateName == "dealloc_memory" {
      return .intrinsicCall(.deallocMemory(ptr: typedArguments[0]))
    }
    if templateName == "copy_memory" {
      return .intrinsicCall(
        .copyMemory(
          dest: typedArguments[0], source: typedArguments[1], count: typedArguments[2]))
    }
    if templateName == "move_memory" {
      return .intrinsicCall(
        .moveMemory(
          dest: typedArguments[0], source: typedArguments[1], count: typedArguments[2]))
    }
    if templateName == "ref_count" {
      return .intrinsicCall(.refCount(val: typedArguments[0]))
    }
    if templateName == "ref_is_borrow" {
      return .intrinsicCall(.refIsBorrow(val: typedArguments[0]))
    }
    if templateName == "downgrade_ref" {
      let val = typedArguments[0]
      // Verify argument is a reference type
      guard case .reference(let inner) = val.type else {
        throw SemanticError.typeMismatch(
          expected: "T ref", got: val.type.description)
      }
      let resultType = Type.weakReference(inner: inner)
      return .intrinsicCall(.downgradeRef(val: val, resultType: resultType))
    }
    if templateName == "upgrade_ref" {
      let val = typedArguments[0]
      // Verify argument is a weak reference type
      guard case .weakReference(let inner) = val.type else {
        throw SemanticError.typeMismatch(
          expected: "T weakref", got: val.type.description)
      }
      // Return type is Option[T ref]
      let refType = Type.reference(inner: inner)
      let optionType = Type.genericEnum(template: "Option", args: [refType])
      
      // Record instantiation request for Option type
      if let optionTemplate = currentScope.lookupGenericEnumTemplate("Option") {
        recordInstantiation(InstantiationRequest(
          kind: .enumType(template: optionTemplate, args: [refType]),
          sourceLine: currentLine,
          sourceFileName: currentFileName
        ))
      }
      
      return .intrinsicCall(.upgradeRef(val: val, resultType: optionType))
    }

    // Record instantiation request for deferred monomorphization
    // Skip if any argument contains generic parameters (will be recorded when fully resolved)
    if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
      recordInstantiation(InstantiationRequest(
        kind: .function(template: template, args: resolvedArgs),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    // Validate generic constraints
    try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
    
    // Resolve return type with substitution
    let returnType = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      return try resolveTypeNode(template.returnType)
    }

    // Return genericCall node instead of instantiated call
    return .genericCall(
      functionName: name,
      typeArgs: resolvedArgs,
      arguments: typedArguments,
      type: returnType
    )
  }
}


// MARK: - Method Call Inference

extension TypeChecker {
  
  /// Infers the type of a method call expression
  func inferMethodCall(
    base: TypedExpressionNode,
    method: Symbol,
    methodType: Type,
    arguments: [ExpressionNode],
    expectedReturnType: Type? = nil
  ) throws -> TypedExpressionNode {
    let methodName = context.getName(method.defId) ?? "<unknown>"
    if case .function(let params, let returns) = method.type {
      if arguments.count != params.count - 1 {
        throw SemanticError.invalidArgumentCount(
          function: methodName,
          expected: params.count - 1,
          got: arguments.count
        )
      }

      // Check if this is a trait object method call (dynamic dispatch).
      // The base type is a reference to a trait object — handle before auto-ref/deref.
      if case .reference(let inner) = base.type,
         case .traitObject(let traitName, _) = inner {
        return try inferTraitObjectMethodCall(
          base: base,
          traitName: traitName,
          methodName: methodName,
          params: params,
          returns: returns,
          arguments: arguments
        )
      }

      // Check base type against first param
      // 禁止对 rvalue 调用 self ref 方法
      if let firstParam = params.first,
         case .reference(let inner) = firstParam.type,
         inner == base.type,
         base.valueCategory == .rvalue {
        let methodName = context.getName(method.defId) ?? "<unknown>"
        throw SemanticError(.generic("Cannot call 'self ref' method '\(methodName)' on an rvalue; store the value in a 'let mut' variable first"), span: currentSpan)
      }
      
      var finalBase = base
      if let firstParam = params.first {
        if base.type != firstParam.type {
          // 尝试自动取引用：期望 T ref，实际是 T
          if case .reference(let inner) = firstParam.type, inner == base.type {
            if base.valueCategory == .rvalue {
              // 这个分支不应该被执行，因为上面已经处理了 rvalue 的情况
              throw SemanticError.invalidOperation(
                op: "implicit ref", type1: base.type.description, type2: "rvalue")
            }
            guard allowsImplicitMutableSelfReference(base) else {
              let name = implicitSelfRefViolationName(base) ?? "<value>"
              throw SemanticError(.cannotTakeRefOfImmutable(name), span: currentSpan)
            }
            finalBase = .referenceExpression(expression: base, type: firstParam.type)
          } else if case .reference(let inner) = base.type, inner == firstParam.type {
            // 尝试自动解引用：期望 T，实际是 T ref
            // Only safe for Copy types (otherwise this would implicitly move).
            finalBase = .derefExpression(expression: base, type: inner)
          } else {
            throw SemanticError.typeMismatch(
              expected: firstParam.type.description,
              got: base.type.description
            )
          }
        }
      }

      // Check if method has unresolved type parameters (method-level generics)
      let hasMethodLevelGenerics = context.containsGenericParameter(returns) || 
        params.dropFirst().contains { context.containsGenericParameter($0.type) }

      var typedArguments: [TypedExpressionNode] = []
      var methodTypeParamBindings: [String: Type] = [:]
      
      // Two-pass inference for method-level generics:
      // Pass 1: Infer non-lambda arguments first to get initial type parameter bindings
      if hasMethodLevelGenerics {
        for (arg, param) in zip(arguments, params.dropFirst()) {
          if case .lambdaExpression(_, _, _, _) = arg {
            // Skip lambdas in first pass
            continue
          }
          let typedArg = try inferTypedExpression(arg)
          let coercedArg = try coerceLiteral(typedArg, to: param.type)
          if context.containsGenericParameter(param.type) {
            _ = unifyTypes(param.type, coercedArg.type, bindings: &methodTypeParamBindings)
          }
        }
      }
      
      // Pass 2: Infer all arguments, using substituted expected types for lambdas and ranges
      for (arg, param) in zip(arguments, params.dropFirst()) {
        var typedArg: TypedExpressionNode
        // For Lambda expressions, pass the expected type for type inference
        if case .lambdaExpression(let lambdaParams, let returnType, let body, _) = arg {
          // Substitute known type parameters into expected type for lambda inference
          var expectedType = param.type
          if hasMethodLevelGenerics && !methodTypeParamBindings.isEmpty {
            expectedType = SemaUtils.substituteType(param.type, substitution: methodTypeParamBindings, context: context)
          }
          typedArg = try inferLambdaExpression(
            parameters: lambdaParams,
            returnType: returnType,
            body: body,
            expectedType: expectedType
          )
          // After inferring lambda, unify to get any remaining type parameters
          if context.containsGenericParameter(param.type) {
            _ = unifyTypes(param.type, typedArg.type, bindings: &methodTypeParamBindings)
          }
        } else if case .rangeExpression(let op, let left, let right) = arg {
          // For Range expressions (especially Full), pass the expected type for type inference
          var expectedType = param.type
          if hasMethodLevelGenerics && !methodTypeParamBindings.isEmpty {
            expectedType = SemaUtils.substituteType(param.type, substitution: methodTypeParamBindings, context: context)
          }
          typedArg = try inferRangeExpression(
            operator: op,
            left: left,
            right: right,
            expectedType: expectedType
          )
          // After inferring range, unify to get any remaining type parameters
          if context.containsGenericParameter(param.type) {
            _ = unifyTypes(param.type, typedArg.type, bindings: &methodTypeParamBindings)
          }
        } else {
          typedArg = try inferTypedExpression(arg, expectedType: param.type)
          typedArg = try coerceLiteral(typedArg, to: param.type)

          // First, infer any generic method type parameters from this argument.
          if context.containsGenericParameter(param.type) {
            _ = unifyTypes(param.type, typedArg.type, bindings: &methodTypeParamBindings)
          }

          let effectiveParamType: Type = {
            if hasMethodLevelGenerics && !methodTypeParamBindings.isEmpty {
              return SemaUtils.substituteType(param.type, substitution: methodTypeParamBindings, context: context)
            }
            return param.type
          }()

          if typedArg.type != effectiveParamType {
            var didAdjust = false

            // Generic-aware implicit ref conversion.
            if case .reference(let inner) = effectiveParamType {
              var trialBindings = methodTypeParamBindings
              let innerMatches: Bool = {
                if inner == typedArg.type { return true }
                if hasMethodLevelGenerics && context.containsGenericParameter(inner) {
                  return unifyTypes(inner, typedArg.type, bindings: &trialBindings)
                }
                return false
              }()
              if innerMatches {
                if typedArg.valueCategory == .lvalue {
                  methodTypeParamBindings = trialBindings
                  typedArg = .referenceExpression(expression: typedArg, type: effectiveParamType)
                  didAdjust = true
                } else {
                  throw SemanticError.invalidOperation(
                    op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
                }
              }
            }

            // Generic-aware implicit deref conversion.
            if !didAdjust,
               case .reference(let inner) = typedArg.type {
              var trialBindings = methodTypeParamBindings
              let paramMatches: Bool = {
                if inner == effectiveParamType { return true }
                if hasMethodLevelGenerics && context.containsGenericParameter(effectiveParamType) {
                  return unifyTypes(effectiveParamType, inner, bindings: &trialBindings)
                }
                return false
              }()
              if paramMatches {
                methodTypeParamBindings = trialBindings
                typedArg = .derefExpression(expression: typedArg, type: inner)
                didAdjust = true
              }
            }

            if !didAdjust {
              throw SemanticError.typeMismatch(
                expected: effectiveParamType.description,
                got: typedArg.type.description
              )
            }
          }
        }
        typedArguments.append(typedArg)
      }

      // Substitute inferred method-level type parameters into return type
      var finalReturns = returns
      // Convert bindings to array of types in order (for methodTypeArgs)
      var inferredMethodTypeArgs: [Type]? = nil
      if hasMethodLevelGenerics {
        if !methodTypeParamBindings.isEmpty {
          finalReturns = SemaUtils.substituteType(returns, substitution: methodTypeParamBindings, context: context)
        }

        if methodTypeParamBindings.isEmpty,
           let expectedReturnType,
           context.containsGenericParameter(returns)
        {
          _ = unifyTypes(returns, expectedReturnType, bindings: &methodTypeParamBindings)
          if !methodTypeParamBindings.isEmpty {
            finalReturns = SemaUtils.substituteType(returns, substitution: methodTypeParamBindings, context: context)
          }
        }

        // Extract method type args in order from the function type
        // The order is determined by the order of first appearance in the function type
        let paramNames = extractGenericParameterNames(from: method.type)
        let baseTypeParamNames = extractGenericParameterNames(from: finalBase.type)
        // Filter out type parameters that belong to the base type (type-level parameters)
        let methodLevelParamNames = paramNames.filter { !baseTypeParamNames.contains($0) }
        let collectedMethodTypeArgs = methodLevelParamNames.compactMap { methodTypeParamBindings[$0] }
        if !methodLevelParamNames.isEmpty
            && collectedMethodTypeArgs.count == methodLevelParamNames.count
            && !collectedMethodTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
          inferredMethodTypeArgs = collectedMethodTypeArgs
        } else {
          inferredMethodTypeArgs = nil
        }
      }
      
      // Create final callee with inferred method type args
      let finalCallee: TypedExpressionNode = .methodReference(
        base: finalBase, method: method, typeArgs: nil, methodTypeArgs: inferredMethodTypeArgs, type: methodType)

      return .call(callee: finalCallee, arguments: typedArguments, type: finalReturns)
    }
    
    throw SemanticError.invalidOperation(
      op: "call", type1: methodType.description, type2: "")
  }
}


// MARK: - Generic Method Call Expression Inference

extension TypeChecker {
  
  /// Infers the type of a generic method call expression (e.g., obj.[Type]method(args))
  func inferGenericMethodCallExpression(
    baseExpr: ExpressionNode,
    methodTypeArgs: [TypeNode],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    if case .identifier(let typeName) = baseExpr,
       currentScope.lookup(typeName, sourceFile: currentSourceFile) == nil,
       let baseType = currentScope.lookupType(typeName) {
      if case .genericParameter = baseType {
        // Keep existing generic-parameter method path below.
      } else {
        let resolvedMethodTypeArgs = try methodTypeArgs.map { try resolveTypeNode($0) }
        return try inferStaticGenericMethodCallOnConcreteType(
          baseType: baseType,
          methodName: methodName,
          arguments: arguments,
          explicitMethodTypeArgs: resolvedMethodTypeArgs
        )
      }
    }

    // Handle explicit generic method call: obj.[Type]method(args)
    let typedBase = try inferTypedExpression(baseExpr)
    let resolvedMethodTypeArgs = try methodTypeArgs.map { try resolveTypeNode($0) }
    
    // Look up the method on the base type
    let baseType = typedBase.type
    
    // Find the method template with method-level type parameters
    let methodResult = try resolveGenericMethodWithExplicitTypeArgs(
      baseType: baseType,
      methodName: methodName,
      methodTypeArgs: resolvedMethodTypeArgs
    )

    var resolvedMethodType = methodResult.methodType
    if !methodResult.methodTypeArgs.isEmpty {
      let allParamNames = extractGenericParameterNames(from: methodResult.methodType)
      let baseTypeParamNames = extractGenericParameterNames(from: typedBase.type)
      let methodParamNames = allParamNames.filter { !baseTypeParamNames.contains($0) }
      if methodParamNames.count == methodResult.methodTypeArgs.count {
        var explicitSubstitution: [String: Type] = [:]
        for (name, argType) in zip(methodParamNames, methodResult.methodTypeArgs) {
          explicitSubstitution[name] = argType
        }
        resolvedMethodType = SemaUtils.substituteType(
          methodResult.methodType,
          substitution: explicitSubstitution,
          context: context
        )
      }
    }

    guard case .function(let params, let returns) = resolvedMethodType else {
      throw SemanticError(.generic("Expected function type for method \(methodName)"), span: currentSpan)
    }
    
    // Check argument count (excluding self)
    let expectedArgCount = params.count - 1
    if arguments.count != expectedArgCount {
      throw SemanticError.invalidArgumentCount(
        function: methodName,
        expected: expectedArgCount,
        got: arguments.count
      )
    }
    
    // Handle self parameter
    var finalBase = typedBase
    if let firstParam = params.first {
      if typedBase.type != firstParam.type {
        if case .reference(let inner) = firstParam.type, inner == typedBase.type {
          if typedBase.valueCategory == .rvalue {
            // 禁止对 rvalue 调用 self ref 方法
            let methodName = context.getName(methodResult.methodSymbol.defId) ?? "<unknown>"
            throw SemanticError(.generic("Cannot call 'self ref' method '\(methodName)' on an rvalue; store the value in a 'let mut' variable first"), span: currentSpan)
          }
          guard allowsImplicitMutableSelfReference(typedBase) else {
            let name = implicitSelfRefViolationName(typedBase) ?? "<value>"
            throw SemanticError(.cannotTakeRefOfImmutable(name), span: currentSpan)
          }
          finalBase = .referenceExpression(expression: typedBase, type: firstParam.type)
        } else if case .reference(let inner) = typedBase.type, inner == firstParam.type {
          finalBase = .derefExpression(expression: typedBase, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: firstParam.type.description,
            got: typedBase.type.description
          )
        }
      }
    }
    
    // Type check arguments
    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg: TypedExpressionNode
      if case .lambdaExpression(let lambdaParams, let returnType, let body, _) = arg {
        typedArg = try inferLambdaExpression(
          parameters: lambdaParams,
          returnType: returnType,
          body: body,
          expectedType: param.type
        )
      } else {
        typedArg = try inferTypedExpression(arg)
      }
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }
    
    // Check if this is a trait method placeholder (for generic parameter types)
    let finalCallee: TypedExpressionNode
    if let traitName = methodResult.traitName {
      // Create a traitMethodPlaceholder instead of methodReference
      finalCallee = .traitMethodPlaceholder(
        traitName: traitName,
        methodName: methodName,
        base: finalBase,
        methodTypeArgs: resolvedMethodTypeArgs,
        type: resolvedMethodType
      )
    } else {
      finalCallee = .methodReference(
        base: finalBase,
        method: methodResult.methodSymbol,
        typeArgs: methodResult.typeArgs,
        methodTypeArgs: resolvedMethodTypeArgs,
        type: resolvedMethodType
      )
    }
    
    return .call(callee: finalCallee, arguments: typedArguments, type: returns)
  }
}


// MARK: - Member Path Expression Inference

extension TypeChecker {
  
  /// Infers the type of a member path expression (e.g., obj.field or Type.method)
  func inferMemberPathExpression(baseExpr: ExpressionNode, path: [String]) throws -> TypedExpressionNode {
    // 1. Check if baseExpr is a Type (Generic Instantiation) for static method access or Enum Constructor
    if case .genericInstantiation(let baseName, let args) = baseExpr {
      if let result = try inferGenericInstantiationMemberPath(baseName: baseName, args: args, path: path) {
        return result
      }
    }

    // 2. Check if baseExpr is a module symbol for member access (e.g., child.child_value() or module.Type.method())
    if case .identifier(let name) = baseExpr {
      // Check if it's a module symbol
      if let moduleDefId = currentScope.lookup(name, sourceFile: currentSourceFile),
        let moduleType = defIdMap.getSymbolType(moduleDefId),
        case .module(let moduleInfo) = moduleType {
        if !isModuleSymbolImported(moduleInfo.modulePath, symbolName: name) {
          throw SemanticError(.generic("Module '\(name)' is not imported"), span: currentSpan)
        }
        if path.count == 1 {
          let memberName = path[0]
          // Look up the member in the module's public symbols
          if let memberSymbol = moduleInfo.publicSymbols[memberName] {
            let access = context.getAccess(memberSymbol.defId) ?? .protected
            if !isSymbolAccessibleForModuleAccess(symbolAccess: access, defId: memberSymbol.defId) {
              let accessLabel = access == .private ? "private" : "protected"
              throw SemanticError(.generic(
                "Cannot access \(accessLabel) symbol '\(memberName)' of module '\(name)'"
              ), span: currentSpan)
            }
            return .variable(identifier: memberSymbol)
          }
          // Look up the member in the module's public types
          if let memberType = moduleInfo.publicTypes[memberName] {
            // Return a type symbol
            let defId = defIdMap.lookup(
              modulePath: moduleInfo.modulePath,
              name: memberName,
              sourceFile: nil
            ) ?? defIdMap.allocate(
              modulePath: moduleInfo.modulePath,
              name: memberName,
              kind: .type(.structure),
              sourceFile: ""
            )
            if defIdMap.getSymbolType(defId) == nil {
              defIdMap.addSymbolInfo(
                defId: defId,
                type: memberType,
                kind: .type,
                isMutable: false
              )
            }
            let typeSymbol = Symbol(
              defId: defId,
              type: memberType,
              kind: .type
            )
            let access = context.getAccess(typeSymbol.defId) ?? .protected
            if !isSymbolAccessibleForModuleAccess(symbolAccess: access, defId: typeSymbol.defId) {
              let accessLabel = access == .private ? "private" : "protected"
              throw SemanticError(.generic(
                "Cannot access \(accessLabel) symbol '\(memberName)' of module '\(name)'"
              ), span: currentSpan)
            }
            return .variable(identifier: typeSymbol)
          }
          throw SemanticError.undefinedMember(memberName, name)
        } else if path.count >= 2 {
          // Handle module.Type.method() or module.Type.field
          let typeName = path[0]
          let remainingPath = Array(path.dropFirst())
          
          // First, try to find the type in the module's public types
          if let memberType = moduleInfo.publicTypes[typeName] {
            if case .structure(let defId) = memberType {
              let access = context.getAccess(defId) ?? .protected
              if !isSymbolAccessibleForModuleAccess(symbolAccess: access, defId: defId) {
                let accessLabel = access == .private ? "private" : "protected"
                throw SemanticError(.generic(
                  "Cannot access \(accessLabel) symbol '\(typeName)' of module '\(name)'"
                ), span: currentSpan)
              }
            }
            // Now handle the remaining path as a type member access
            if let result = try inferTypeMemberPath(type: memberType, typeName: typeName, path: remainingPath) {
              return result
            }
          }
          
          // If not found in module's public types, try global scope
          // (for types that haven't been fully registered in the module yet)
          if let type = currentScope.lookupType(typeName) {
            if let result = try inferTypeMemberPath(type: type, typeName: typeName, path: remainingPath) {
              return result
            }
          }
          
          // Try generic struct template
          if currentScope.lookupGenericStructTemplate(typeName) != nil {
            // For generic types, we need type arguments
            // This case handles module.GenericType.method() without explicit type args
            // which is typically an error, but we'll let inferTypeMemberPath handle it
            throw SemanticError.undefinedType("\(name).\(typeName)")
          }
          
          throw SemanticError.undefinedMember(typeName, name)
        }
      }
    }
    
    // 3. Check if baseExpr is a Type (Identifier) for static method access
    if case .identifier(let name) = baseExpr, let type = currentScope.lookupType(name) {
      if let result = try inferTypeMemberPath(type: type, typeName: name, path: path) {
        return result
      }
    }

    // 4. Enum Constructor Access via member path (e.g., EnumType.CaseName)
    if case .identifier(let name) = baseExpr, let type = currentScope.lookupType(name) {
      if path.count == 1 {
        let memberName = path[0]
        if case .`enum`(let defId) = type {
          if let c = context.getEnumCases(defId)?.first(where: { $0.name == memberName }) {
            let paramTypes = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
            let funcType = Type.function(parameters: paramTypes, returns: type)
            let symbol = makeLocalSymbol(name: "\(name).\(memberName)", type: funcType, kind: .function)
            return .variable(identifier: symbol)
          }
        }
      }
    }
    
    // 5. Generic Enum Constructor Access with type inference from return type context
    // e.g., Result.Ok(x) when return type is [T, E]Result
    if case .identifier(let name) = baseExpr,
       let template = currentScope.lookupGenericEnumTemplate(name),
       path.count == 1 {
      let memberName = path[0]
      
      // Try to infer type arguments from currentFunctionReturnType
      if let returnType = currentFunctionReturnType,
         case .genericEnum(let templateName, let typeArgs) = returnType,
         templateName == name {
        // We have a matching return type context, use its type arguments
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: typeArgs)
        
        // Record instantiation request for deferred monomorphization
        if !typeArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .enumType(template: template, args: typeArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        let type = Type.genericEnum(template: name, args: typeArgs)
        
        // Create type substitution map
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = typeArgs[i]
        }
        
        // Check if it's a enum case constructor
        if let c = template.cases.first(where: { $0.name == memberName }) {
          let resolvedParams = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try c.parameters.map { param -> Parameter in
              let paramType = try resolveTypeNode(param.type)
              return Parameter(type: paramType, kind: .byVal)
            }
          }
          
          let symbolName = "\(name).\(memberName)"
          let constructorType = Type.function(parameters: resolvedParams, returns: type)
          let symbol = makeLocalSymbol(name: symbolName, type: constructorType, kind: .variable(.Value))
          return .variable(identifier: symbol)
        }
      }
    }

    // infer base
    let inferredBase = try inferTypedExpression(baseExpr)

    // access member optimization: peel auto-deref to access ref directly
    let typedBase: TypedExpressionNode
    if case .derefExpression(let inner, _) = inferredBase {
      typedBase = inner
    } else {
      typedBase = inferredBase
    }

    var currentType: Type = typedBase.type
    var typedPath: [Symbol] = []

    for (index, memberName) in path.enumerated() {
      let isLast = index == path.count - 1

      let (typeToLookup, isPointerAccess) = {
        if case .reference(let inner) = currentType { return (inner, false) }
        if case .pointer(let inner) = currentType { return (inner, true) }
        return (currentType, false)
      }()

      // Check if it is a structure to access members
      var foundMember = false
      var isForeignStruct = false
      if case .structure(let defId) = typeToLookup {
        isForeignStruct = context.isForeignStruct(defId)
        if isForeignStruct {
          if let field = context.getForeignStructFields(defId)?.first(where: { $0.name == memberName }) {
            let sym = makeLocalSymbol(
              name: field.name, type: field.type, kind: .variable(.MutableValue))
            typedPath.append(sym)
            currentType = field.type
            foundMember = true
          }
        } else if let mem = context.getStructMembers(defId)?.first(where: { $0.name == memberName }) {
          // Check field visibility
          if !isFieldAccessibleForMemberAccess(fieldAccess: mem.access, defId: defId) {
            let structName = context.getName(defId) ?? typeToLookup.description
            let accessLabel = mem.access == .private ? "private" : "protected"
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(memberName)' of type '\(structName)'"
            ), span: currentSpan)
          }
          let sym = makeLocalSymbol(
            name: mem.name, type: mem.type, kind: .variable(mem.mutable ? .MutableValue : .Value))
          typedPath.append(sym)
          currentType = mem.type
          foundMember = true
        }
      }
      
      // Handle genericStruct types - look up member from template
      if !foundMember, case .genericStruct(let templateName, let typeArgs) = typeToLookup {
        if let template = currentScope.lookupGenericStructTemplate(templateName) {
          // Create type substitution map
          var substitution: [String: Type] = [:]
          for (i, param) in template.typeParameters.enumerated() {
            if i < typeArgs.count {
              substitution[param.name] = typeArgs[i]
            }
          }
          
          // Look up member in template and substitute types
          if let param = template.parameters.first(where: { $0.name == memberName }) {
            // Check field visibility
            if !isFieldAccessibleForMemberAccess(fieldAccess: param.access, defId: template.defId) {
              let fieldAccess = param.access
              let accessLabel = fieldAccess == .private ? "private" : "protected"
              throw SemanticError(.generic(
                "Cannot access \(accessLabel) field '\(memberName)' of type '\(templateName)'"
              ), span: currentSpan)
            }
            let memberType = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try resolveTypeNode(param.type)
            }
            let sym = makeLocalSymbol(
              name: param.name, type: memberType, kind: .variable(param.mutable ? .MutableValue : .Value))
            typedPath.append(sym)
            currentType = memberType
            foundMember = true
          }
        }
      }

      if !foundMember {
        if isLast {
          // Try to find method on the type
          if isPointerAccess {
            if let methodResult = try inferMethodOnType(typeToLookup: currentType, memberName: memberName, typedBase: typedBase, typedPath: typedPath) {
              return methodResult
            }
          }
          if let methodResult = try inferMethodOnType(typeToLookup: typeToLookup, memberName: memberName, typedBase: typedBase, typedPath: typedPath) {
            return methodResult
          }
        }

        if isPointerAccess {
          throw SemanticError(
            .pointerMemberAccessOnNonStruct(field: memberName, type: typeToLookup.description),
            span: currentSpan
          )
        }
        if case .structure(let defId) = typeToLookup {
          let name = context.getName(defId) ?? ""
          if isForeignStruct {
            throw SemanticError(.unknownForeignField(type: name, field: memberName), span: currentSpan)
          }
          throw SemanticError.undefinedMember(memberName, name)
        } else {
          throw SemanticError.invalidOperation(
            op: "member access", type1: typeToLookup.description, type2: "")
        }
      }
    }
    let memberAccess: TypedExpressionNode = .memberPath(source: typedBase, path: typedPath)

    // Materialize rvalue base to ensure proper drop after member access.
    // This mirrors temporary materialization for rvalue method calls.
    if typedBase.valueCategory == .rvalue {
      let tempSymbol = nextSynthSymbol(prefix: "temp_base", type: typedBase.type)
      let tempVar: TypedExpressionNode = .variable(identifier: tempSymbol)
      let tempMemberAccess: TypedExpressionNode = .memberPath(source: tempVar, path: typedPath)
      return .makeLetBlock(
        identifier: tempSymbol,
        value: typedBase,
        body: tempMemberAccess,
        type: tempMemberAccess.type
      )
    }

    return memberAccess
  }
  
  /// Check if a field is accessible from the current source file/module for member access.
  /// - Parameters:
  ///   - fieldAccess: The access modifier of the field
  ///   - defId: The DefId of the type that defines the field
  /// - Returns: true if the field is accessible
  private func isFieldAccessibleForMemberAccess(fieldAccess: AccessModifier, defId: DefId) -> Bool {
    switch fieldAccess {
    case .public:
      return true
    case .private:
      // Private: only accessible from the same file
      let defSourceFile = context.getSourceFile(defId) ?? ""
      return defSourceFile == currentSourceFile
    case .protected:
      // Protected: accessible from the same module or submodule
      let defModulePath = context.getModulePath(defId) ?? []
      // Same module
      if defModulePath == currentModulePath {
        return true
      }
      // Current module is a submodule of the definition's module
      if currentModulePath.count > defModulePath.count {
        let prefix = Array(currentModulePath.prefix(defModulePath.count))
        if prefix == defModulePath {
          return true
        }
      }
      return false
    }
  }

  private func isSymbolAccessibleForModuleAccess(symbolAccess: AccessModifier, defId: DefId) -> Bool {
    switch symbolAccess {
    case .public:
      return true
    case .private:
      let defSourceFile = context.getSourceFile(defId) ?? ""
      return defSourceFile == currentSourceFile
    case .protected:
      let defModulePath = context.getModulePath(defId) ?? []
      if defModulePath == currentModulePath {
        return true
      }
      if currentModulePath.count > defModulePath.count {
        let prefix = Array(currentModulePath.prefix(defModulePath.count))
        if prefix == defModulePath {
          return true
        }
      }
      return false
    }
  }

  func isModuleSymbolImported(_ modulePath: [String], symbolName: String) -> Bool {
    if modulePath == currentModulePath {
      return true
    }

    guard let importGraph else {
      return false
    }

    if let aliasedModulePath = importGraph.resolveAliasedModule(
      alias: symbolName,
      inModule: currentModulePath,
      inSourceFile: currentSourceFile
    ), aliasedModulePath == modulePath {
      return true
    }

    let hasMemberImport = importGraph.symbolImports.contains { symbolImport in
      symbolImport.module == currentModulePath
        && symbolImport.target == modulePath
        && symbolImport.symbol == symbolName
        && (symbolImport.sourceFile == nil || symbolImport.sourceFile == currentSourceFile)
        && (symbolImport.kind == .memberImport || symbolImport.kind == .batchImport)
    }

    let hasModuleImport = importGraph.edges.contains { edge in
      edge.source == currentModulePath
        && edge.target == modulePath
        && (edge.sourceFile == nil || edge.sourceFile == currentSourceFile)
        && (edge.kind == .moduleImport || edge.kind == .batchImport)
    }

    return hasModuleImport || hasMemberImport
  }
  
  /// Helper to infer generic instantiation member path
  private func inferGenericInstantiationMemberPath(baseName: String, args: [TypeNode], path: [String]) throws -> TypedExpressionNode? {
    if let template = currentScope.lookupGenericStructTemplate(baseName) {
      let resolvedArgs = try args.map { try resolveTypeNode($0) }
      
      guard template.typeParameters.count == resolvedArgs.count else {
        throw SemanticError.typeMismatch(
          expected: "\(template.typeParameters.count) generic arguments",
          got: "\(resolvedArgs.count)"
        )
      }
      
      try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
      
      if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
        recordInstantiation(InstantiationRequest(
          kind: .structType(template: template, args: resolvedArgs),
          sourceLine: currentLine,
          sourceFileName: currentFileName
        ))
      }
      
      let type = Type.genericStruct(template: baseName, args: resolvedArgs)

      if path.count == 1 {
        let memberName = path[0]
        if let extensions = genericExtensionMethods[baseName] {
          if let ext = extensions.first(where: { $0.method.name == memberName }) {
            let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
            if isStatic {
              let methodSym = try resolveGenericExtensionMethod(
                baseType: type, templateName: baseName, typeArgs: resolvedArgs,
                methodInfo: ext)
              return .variable(identifier: methodSym)
            }
          }
        }
      }
    } else if let template = currentScope.lookupGenericEnumTemplate(baseName) {
      let resolvedArgs = try args.map { try resolveTypeNode($0) }
      
      guard template.typeParameters.count == resolvedArgs.count else {
        throw SemanticError.typeMismatch(
          expected: "\(template.typeParameters.count) generic arguments",
          got: "\(resolvedArgs.count)"
        )
      }
      
      try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
      
      if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
        recordInstantiation(InstantiationRequest(
          kind: .enumType(template: template, args: resolvedArgs),
          sourceLine: currentLine,
          sourceFileName: currentFileName
        ))
      }
      
      let type = Type.genericEnum(template: baseName, args: resolvedArgs)

      if path.count == 1 {
        let memberName = path[0]
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = resolvedArgs[i]
        }
        
        if let c = template.cases.first(where: { $0.name == memberName }) {
          let resolvedParams = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try c.parameters.map { param -> Parameter in
              let paramType = try resolveTypeNode(param.type)
              return Parameter(type: paramType, kind: .byVal)
            }
          }
          
          let symbolName = "\(baseName).\(memberName)"
          let constructorType = Type.function(parameters: resolvedParams, returns: type)
          let symbol = makeLocalSymbol(name: symbolName, type: constructorType, kind: .variable(.Value))
          return .variable(identifier: symbol)
        }
      }
    }
    return nil
  }
  
  /// Helper to infer type member path (static methods, trait methods)
  private func inferTypeMemberPath(type: Type, typeName: String, path: [String]) throws -> TypedExpressionNode? {
    if path.count == 1 {
      let memberName = path[0]
      var methodSymbol: Symbol?

      // Static trait methods on generic parameters (no `self` parameter)
      // are resolved during call expression inference.

      if case .structure(let defId) = type {
        let name = context.getName(defId) ?? ""
        if let methods = extensionMethods[name], let sym = methods[memberName] {
          methodSymbol = sym
        }
      }

      if let method = methodSymbol {
        return .variable(identifier: method)
      }
    }
    return nil
  }
  
  /// Helper to infer method on a type during member path resolution
  private func inferMethodOnType(typeToLookup: Type, memberName: String, typedBase: TypedExpressionNode, typedPath: [Symbol]) throws -> TypedExpressionNode? {
    let typeName: String
    switch typeToLookup {
    case .structure(let defId):
      typeName = context.getName(defId) ?? typeToLookup.description
    case .`enum`(let defId):
      typeName = context.getName(defId) ?? typeToLookup.description
    default:
      typeName = typeToLookup.description
    }
    if let methods = extensionMethods[typeName], let methodSym = methods[memberName] {
      guard isReceiverStyleMethod(methodSym) else {
        return nil
      }
      let base: TypedExpressionNode
      if typedPath.isEmpty {
        base = typedBase
      } else {
        base = .memberPath(source: typedBase, path: typedPath)
      }
      return .methodReference(base: base, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: methodSym.type)
    }

    if let methodSym = try lookupConcreteMethodSymbol(on: typeToLookup, name: memberName) {
      let base: TypedExpressionNode
      if typedPath.isEmpty {
        base = typedBase
      } else {
        base = .memberPath(source: typedBase, path: typedPath)
      }
      return .methodReference(base: base, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: methodSym.type)
    }

    if case .pointer(let element) = typeToLookup {
      if let extensions = genericIntrinsicExtensionMethods["Ptr"] {
        for ext in extensions {
          if ext.method.name == memberName {
            guard ext.method.parameters.first?.name == "self" else {
              continue
            }
            let methodSym = try resolveIntrinsicExtensionMethod(
              baseType: typeToLookup,
              templateName: "Ptr",
              typeArgs: [element],
              methodInfo: ext
            )
            let base: TypedExpressionNode
            if typedPath.isEmpty {
              base = typedBase
            } else {
              base = .memberPath(source: typedBase, path: typedPath)
            }
            return .methodReference(base: base, method: methodSym, typeArgs: [element], methodTypeArgs: nil, type: methodSym.type)
          }
        }
      }

      if let extensions = genericExtensionMethods["Ptr"] {
        for ext in extensions {
          if ext.method.name == memberName {
            guard ext.method.parameters.first?.name == "self" else {
              continue
            }
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: "Ptr",
              typeArgs: [element],
              methodInfo: ext
            )
            let base: TypedExpressionNode
            if typedPath.isEmpty {
              base = typedBase
            } else {
              base = .memberPath(source: typedBase, path: typedPath)
            }
            return .methodReference(base: base, method: methodSym, typeArgs: [element], methodTypeArgs: nil, type: methodSym.type)
          }
        }
      }
    }
    
    // Handle genericStruct types
    if case .genericStruct(let templateName, let typeArgs) = typeToLookup {
      if let extensions = genericExtensionMethods[templateName] {
        for ext in extensions {
          if ext.method.name == memberName {
            guard ext.method.parameters.first?.name == "self" else {
              continue
            }
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: templateName,
              typeArgs: typeArgs,
              methodInfo: ext
            )
            let base: TypedExpressionNode
            if typedPath.isEmpty {
              base = typedBase
            } else {
              base = .memberPath(source: typedBase, path: typedPath)
            }
            return .methodReference(base: base, method: methodSym, typeArgs: typeArgs, methodTypeArgs: nil, type: methodSym.type)
          }
        }
      }
    }
    
    // Handle genericEnum types
    if case .genericEnum(let templateName, let typeArgs) = typeToLookup {
      if let extensions = genericExtensionMethods[templateName] {
        for ext in extensions {
          if ext.method.name == memberName {
            guard ext.method.parameters.first?.name == "self" else {
              continue
            }
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: templateName,
              typeArgs: typeArgs,
              methodInfo: ext
            )
            let base: TypedExpressionNode
            if typedPath.isEmpty {
              base = typedBase
            } else {
              base = .memberPath(source: typedBase, path: typedPath)
            }
            return .methodReference(base: base, method: methodSym, typeArgs: typeArgs, methodTypeArgs: nil, type: methodSym.type)
          }
        }
      }
    }

    // Trait-bounded instance methods on generic parameters
    if case .genericParameter(let paramName) = typeToLookup,
      let bounds = genericTraitBounds[paramName]
    {
      for traitConstraint in bounds {
        let traitName = traitConstraint.baseName
        let methods = try flattenedTraitMethods(traitName)
        if let sig = methods[memberName] {
          if sig.parameters.first?.name != "self" {
            continue
          }
          
          let traitInfo = traits[traitName]
          var traitTypeArgs: [Type] = []
          if case .generic(_, let argNodes) = traitConstraint {
            for argNode in argNodes {
              let argType = try resolveTypeNode(argNode)
              traitTypeArgs.append(argType)
            }
          }
          
          let expectedType = try expectedFunctionTypeForTraitMethod(
            sig, 
            selfType: typeToLookup,
            traitInfo: traitInfo,
            traitTypeArgs: traitTypeArgs
          )
          
          let base: TypedExpressionNode
          if typedPath.isEmpty {
            base = typedBase
          } else {
            base = .memberPath(source: typedBase, path: typedPath)
          }
          recordTraitPlaceholderInstantiation(
            baseType: base.type,
            methodName: memberName,
            methodTypeArgs: []
          )
          return .traitMethodPlaceholder(
            traitName: traitName,
            methodName: memberName,
            base: base,
            methodTypeArgs: [],
            type: expectedType
          )
        }

        let toolMethods = try flattenedTraitToolMethods(traitName)
        if let entityMethod = toolMethods[memberName], entityMethod.parameters.first?.name == "self" {
          let expectedType = try expectedFunctionTypeForToolMethod(entityMethod, selfType: typeToLookup)
          let base: TypedExpressionNode
          if typedPath.isEmpty {
            base = typedBase
          } else {
            base = .memberPath(source: typedBase, path: typedPath)
          }
          recordTraitPlaceholderInstantiation(
            baseType: base.type,
            methodName: memberName,
            methodTypeArgs: []
          )
          return .traitMethodPlaceholder(
            traitName: traitName,
            methodName: memberName,
            base: base,
            methodTypeArgs: [],
            type: expectedType
          )
        }
      }
    }

    // Trait object method lookup: when the type is a trait object, look up the method
    // in the trait's method signatures and return a methodReference with Self replaced
    if case .traitObject(let traitName, let traitTypeArgs) = typeToLookup {
      let methods = try flattenedTraitMethods(traitName)
      if let sig = methods[memberName] {
        // Only instance methods (with self parameter)
        if sig.parameters.first?.name != "self" {
          return nil
        }

        let traitInfo = traits[traitName]
        let traitObjType: Type = .traitObject(traitName: traitName, typeArgs: traitTypeArgs)

        // Resolve the method type with Self replaced by the trait object type
        let expectedType = try expectedFunctionTypeForTraitMethod(
          sig,
          selfType: traitObjType,
          traitInfo: traitInfo,
          traitTypeArgs: traitTypeArgs
        )

        let methodSym = makeGlobalSymbol(
          name: memberName,
          type: expectedType,
          kind: .function,
          access: .protected
        )

        // Register named parameter info from the trait method signature
        // so that call-site validation uses the trait's named parameter requirements
        functionNamedParams[methodSym.defId] = sig.parameters.map { (name: $0.name, named: $0.named) }

        let base: TypedExpressionNode
        if typedPath.isEmpty {
          base = typedBase
        } else {
          base = .memberPath(source: typedBase, path: typedPath)
        }
        return .methodReference(base: base, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: expectedType)
      }
    }
    
    return nil
  }
}


// MARK: - Static Method Call Expression Inference

extension TypeChecker {
  
  /// Infers the type of a static method call expression
  func inferStaticMethodCallExpression(
    typeName: String,
    typeArgs: [TypeNode],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    let resolvedTypeArgs = try typeArgs.map { try resolveTypeNode($0) }
    
    // Check if it's a generic struct
    if let template = currentScope.lookupGenericStructTemplate(typeName) {
      // 检查泛型模板的可见性（通过已实例化的类型检查）
      // 泛型模板本身没有模块路径，需要在实例化时检查
      return try inferGenericStructStaticMethodCall(
        template: template,
        typeName: typeName,
        resolvedTypeArgs: resolvedTypeArgs,
        methodName: methodName,
        arguments: arguments
      )
    }
    
    // Check if it's a generic enum
    if let template = currentScope.lookupGenericEnumTemplate(typeName) {
      return try inferGenericEnumStaticMethodCall(
        template: template,
        typeName: typeName,
        resolvedTypeArgs: resolvedTypeArgs,
        methodName: methodName,
        arguments: arguments
      )
    }
    
    // Check if it's a non-generic type (e.g., String.empty())
    if let type = currentScope.lookupType(typeName) {
      // 检查类型的模块可见性
      try checkTypeVisibility(type: type, typeName: typeName)
      
      return try inferConcreteTypeStaticMethodCall(
        type: type,
        typeName: typeName,
        resolvedTypeArgs: resolvedTypeArgs,
        methodName: methodName,
        arguments: arguments
      )
    }
    
    throw SemanticError.undefinedType(typeName)
  }
  
  private func inferGenericStructStaticMethodCall(
    template: GenericStructTemplate,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    var effectiveTypeArgs = resolvedTypeArgs
    if effectiveTypeArgs.isEmpty, !template.typeParameters.isEmpty,
       let inferred = try inferGenericTypeArgsForStaticMethodCall(
        templateName: typeName,
        typeParameters: template.typeParameters,
        methodName: methodName,
        arguments: arguments
       ) {
      effectiveTypeArgs = inferred
    }

    guard template.typeParameters.count == effectiveTypeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(template.typeParameters.count) generic arguments",
        got: "\(effectiveTypeArgs.count)"
      )
    }
    
    try enforceGenericConstraints(typeParameters: template.typeParameters, args: effectiveTypeArgs)
    
    if !effectiveTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
      recordInstantiation(InstantiationRequest(
        kind: .structType(template: template, args: effectiveTypeArgs),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    let baseType = Type.genericStruct(template: typeName, args: effectiveTypeArgs)
    
    if let extensions = genericExtensionMethods[typeName] {
      if let ext = extensions.first(where: { $0.method.name == methodName }) {
        let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
        if isStatic {
          let methodSym = try resolveGenericExtensionMethod(
            baseType: baseType, templateName: typeName, typeArgs: effectiveTypeArgs,
            methodInfo: ext)
          
          guard case .function(let params, let returnType) = methodSym.type else {
            throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
          }
          
          if arguments.count != params.count {
            throw SemanticError.invalidArgumentCount(
              function: methodName,
              expected: params.count,
              got: arguments.count
            )
          }
          
          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = try coerceLiteral(typedArg, to: param.type)
            if typedArg.type != param.type {
              throw SemanticError.typeMismatch(
                expected: param.type.description,
                got: typedArg.type.description
              )
            }
            typedArguments.append(typedArg)
          }
          
          return .staticMethodCall(
            baseType: baseType,
            methodName: methodName,
            typeArgs: effectiveTypeArgs,
            methodTypeArgs: [],
            arguments: typedArguments,
            type: returnType
          )
        }
      }
    }
    
    throw SemanticError.undefinedMember(methodName, typeName)
  }
  
  private func inferGenericEnumStaticMethodCall(
    template: GenericEnumTemplate,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    var effectiveTypeArgs = resolvedTypeArgs
    if effectiveTypeArgs.isEmpty, !template.typeParameters.isEmpty,
       let inferred = try inferGenericTypeArgsForStaticMethodCall(
        templateName: typeName,
        typeParameters: template.typeParameters,
        methodName: methodName,
        arguments: arguments
       ) {
      effectiveTypeArgs = inferred
    }

    guard template.typeParameters.count == effectiveTypeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(template.typeParameters.count) generic arguments",
        got: "\(effectiveTypeArgs.count)"
      )
    }
    
    try enforceGenericConstraints(typeParameters: template.typeParameters, args: effectiveTypeArgs)
    
    if !effectiveTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
      recordInstantiation(InstantiationRequest(
        kind: .enumType(template: template, args: effectiveTypeArgs),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    let baseType = Type.genericEnum(template: typeName, args: effectiveTypeArgs)
    
    if let extensions = genericExtensionMethods[typeName] {
      if let ext = extensions.first(where: { $0.method.name == methodName }) {
        let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
        if isStatic {
          let methodSym = try resolveGenericExtensionMethod(
            baseType: baseType, templateName: typeName, typeArgs: effectiveTypeArgs,
            methodInfo: ext)
          
          guard case .function(let params, let returnType) = methodSym.type else {
            throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
          }
          
          if arguments.count != params.count {
            throw SemanticError.invalidArgumentCount(
              function: methodName,
              expected: params.count,
              got: arguments.count
            )
          }
          
          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = try coerceLiteral(typedArg, to: param.type)
            if typedArg.type != param.type {
              throw SemanticError.typeMismatch(
                expected: param.type.description,
                got: typedArg.type.description
              )
            }
            typedArguments.append(typedArg)
          }
          
          return .staticMethodCall(
            baseType: baseType,
            methodName: methodName,
            typeArgs: effectiveTypeArgs,
            methodTypeArgs: [],
            arguments: typedArguments,
            type: returnType
          )
        }
      }
    }
    
    throw SemanticError.undefinedMember(methodName, typeName)
  }

  private func inferGenericTypeArgsForStaticMethodCall(
    templateName: String,
    typeParameters: [TypeParameterDecl],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> [Type]? {
    guard let extensions = genericExtensionMethods[templateName],
          let ext = extensions.first(where: { $0.method.name == methodName }) else {
      return nil
    }

    let unresolvedParamTypes: [Type] = try withNewScope {
      for typeParam in ext.typeParams {
        currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
      }
      for methodTypeParam in ext.method.typeParameters {
        currentScope.defineGenericParameter(methodTypeParam.name, type: .genericParameter(name: methodTypeParam.name))
      }

      let selfArgs = ext.typeParams.map { Type.genericParameter(name: $0.name) }
      try currentScope.defineType("Self", type: .genericStruct(template: templateName, args: selfArgs))

      return try ext.method.parameters.map { param in
        try resolveTypeNode(param.type)
      }
    }

    if unresolvedParamTypes.count != arguments.count {
      return nil
    }

    var bindings: [String: Type] = [:]
    for (argExpr, expectedType) in zip(arguments, unresolvedParamTypes) {
      let typedArg = try inferTypedExpression(argExpr)
      _ = unifyTypes(expectedType, typedArg.type, bindings: &bindings)
    }

    // Generic trait-constraint-based completion.
    // If we infer a concrete type for parameter P and P has a generic trait bound
    // like [A, B]Trait, infer concrete trait arguments from P's conformance and
    // unify them back into A/B without hardcoding specific trait names.
    var inferred = bindings
    var madeProgress = true
    var iterations = 0
    let maxIterations = max(1, typeParameters.count * 2)
    while madeProgress && iterations < maxIterations {
      madeProgress = false
      iterations += 1

      for typeParam in typeParameters {
        for constraint in typeParam.constraints {
          let traitConstraint = try SemaUtils.resolveTraitConstraint(from: constraint)
          switch traitConstraint {
          case .generic(let traitName, let traitArgs):
            guard let concreteSelfType = inferred[typeParam.name],
                  let concreteTraitArgs = try inferTraitTypeArgumentsFromConformance(
                    selfType: concreteSelfType,
                    traitName: traitName
                  ),
                  concreteTraitArgs.count == traitArgs.count else {
              continue
            }

            let unresolvedTraitArgs: [Type] = try withNewScope {
              for genericParam in typeParameters {
                currentScope.defineGenericParameter(genericParam.name, type: .genericParameter(name: genericParam.name))
              }
              return try traitArgs.map { try resolveTypeNode($0) }
            }

            for (expectedTraitArg, actualTraitArg) in zip(unresolvedTraitArgs, concreteTraitArgs) {
              let before = inferred
              _ = unifyTypes(expectedTraitArg, actualTraitArg, bindings: &inferred)
              if before != inferred {
                madeProgress = true
              }
            }
          case .simple:
            continue
          }
        }
      }
    }

    var inferredArgs: [Type] = []
    for typeParam in typeParameters {
      guard let boundType = inferred[typeParam.name] else {
        return nil
      }
      inferredArgs.append(boundType)
    }

    return inferredArgs
  }

  private func inferTraitTypeArgumentsFromConformance(
    selfType: Type,
    traitName: String
  ) throws -> [Type]? {
    guard let traitInfo = traits[traitName] else {
      return nil
    }

    if traitInfo.typeParameters.isEmpty {
      return []
    }

    let requiredMethods = try flattenedTraitMethods(traitName)
    var traitParamBindings: [String: Type] = [:]

    for methodSignature in requiredMethods.values {
      guard let actualMethod = try lookupConcreteMethodSymbol(on: selfType, name: methodSignature.name) else {
        return nil
      }

      let expectedMethodType: Type = try withNewScope {
        try currentScope.defineType("Self", type: selfType)

        for traitTypeParam in traitInfo.typeParameters {
          currentScope.defineGenericParameter(traitTypeParam.name, type: .genericParameter(name: traitTypeParam.name))
        }

        for methodTypeParam in methodSignature.typeParameters {
          currentScope.defineGenericParameter(methodTypeParam.name, type: .genericParameter(name: methodTypeParam.name))
        }

        let params: [Parameter] = try methodSignature.parameters.map { param in
          let resolvedType = try resolveTypeNode(param.type)
          return Parameter(type: resolvedType, kind: .byVal)
        }
        let returnType = try resolveTypeNode(methodSignature.returnType)
        return .function(parameters: params, returns: returnType)
      }

      _ = unifyTypes(expectedMethodType, actualMethod.type, bindings: &traitParamBindings)
    }

    var resolvedArgs: [Type] = []
    for traitTypeParam in traitInfo.typeParameters {
      guard let bound = traitParamBindings[traitTypeParam.name] else {
        return nil
      }
      resolvedArgs.append(bound)
    }

    return resolvedArgs
  }
  
  private func inferConcreteTypeStaticMethodCall(
    type: Type,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    if !resolvedTypeArgs.isEmpty {
      throw SemanticError(.generic("Type \(typeName) is not generic"), span: currentSpan)
    }
    
    let lookupTypeName: String
    switch type {
    case .structure(let defId):
      lookupTypeName = context.getName(defId) ?? ""
    case .`enum`(let defId):
      lookupTypeName = context.getName(defId) ?? ""
    default:
      lookupTypeName = type.description
    }
    
    if let methods = extensionMethods[lookupTypeName], let methodSym = methods[methodName] {
      if context.containsGenericParameter(methodSym.type) {
        return try inferStaticGenericMethodCallOnConcreteType(
          baseType: type,
          methodName: methodName,
          arguments: arguments,
          explicitMethodTypeArgs: nil
        )
      }
      
      guard case .function(let params, let returnType) = methodSym.type else {
        throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
      }
      
      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: methodName,
          expected: params.count,
          got: arguments.count
        )
      }
      
      var typedArguments: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        var typedArg = try inferTypedExpression(arg)
        typedArg = try coerceLiteral(typedArg, to: param.type)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
      }
      
      return .staticMethodCall(
        baseType: type,
        methodName: methodName,
        typeArgs: [],
        methodTypeArgs: [],
        arguments: typedArguments,
        type: returnType
      )
    }

    if let genericMethods = genericExtensionMethods[lookupTypeName],
       genericMethods.contains(where: { $0.method.name == methodName }) {
      return try inferStaticGenericMethodCallOnConcreteType(
        baseType: type,
        methodName: methodName,
        arguments: arguments,
        explicitMethodTypeArgs: nil
      )
    }
    
    // Check if it's a generic parameter with trait bounds
    if case .genericParameter(let paramName) = type {
      if let bounds = genericTraitBounds[paramName] {
        for traitConstraint in bounds {
          let traitName = traitConstraint.baseName
          let methods = try flattenedTraitMethods(traitName)
          if let sig = methods[methodName] {
            if sig.parameters.first?.name == "self" {
              continue
            }
            
            let traitInfo = traits[traitName]
            var traitTypeArgs: [Type] = []
            if case .generic(_, let argNodes) = traitConstraint {
              for argNode in argNodes {
                let argType = try resolveTypeNode(argNode)
                traitTypeArgs.append(argType)
              }
            }
            
            let expectedType = try expectedFunctionTypeForTraitMethod(
              sig, 
              selfType: type,
              traitInfo: traitInfo,
              traitTypeArgs: traitTypeArgs
            )
            
            guard case .function(let params, let returnType) = expectedType else {
              throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
            }
            
            if arguments.count != params.count {
              throw SemanticError.invalidArgumentCount(
                function: methodName,
                expected: params.count,
                got: arguments.count
              )
            }
            
            var typedArguments: [TypedExpressionNode] = []
            var methodTypeParamBindings: [String: Type] = [:]
            for (arg, param) in zip(arguments, params) {
              var typedArg = try inferTypedExpression(arg)
              typedArg = try coerceLiteral(typedArg, to: param.type)
              if context.containsGenericParameter(param.type) {
                _ = unifyTypes(param.type, typedArg.type, bindings: &methodTypeParamBindings)
              }
              if typedArg.type != param.type {
                throw SemanticError.typeMismatch(
                  expected: param.type.description,
                  got: typedArg.type.description
                )
              }
              typedArguments.append(typedArg)
            }

            let inferredMethodTypeArgs: [Type] = sig.typeParameters.compactMap { typeParam in
              if let bound = methodTypeParamBindings[typeParam.name] {
                return bound
              }
              if let existingType = currentScope.lookupType(typeParam.name),
                 case .genericParameter(let existingName) = existingType,
                 existingName == typeParam.name {
                return existingType
              }
              return nil
            }
            
            return .staticMethodCall(
              baseType: type,
              methodName: methodName,
              typeArgs: [],
              methodTypeArgs: inferredMethodTypeArgs,
              arguments: typedArguments,
              type: returnType
            )
          }
        }
      }
    }
    
    throw SemanticError.undefinedMember(methodName, typeName)
  }

  private func inferStaticGenericMethodCallOnConcreteType(
    baseType: Type,
    methodName: String,
    arguments: [ExpressionNode],
    explicitMethodTypeArgs: [Type]?
  ) throws -> TypedExpressionNode {
    let methodTypeArgs: [Type]
    if let explicitMethodTypeArgs {
      methodTypeArgs = explicitMethodTypeArgs
    } else {
      methodTypeArgs = try inferStaticGenericMethodTypeArguments(
        baseType: baseType,
        methodName: methodName,
        arguments: arguments
      )
    }

    let methodResult = try resolveGenericMethodWithExplicitTypeArgs(
      baseType: baseType,
      methodName: methodName,
      methodTypeArgs: methodTypeArgs
    )

    guard case .function(let params, let returnType) = methodResult.methodType else {
      throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
    }

    if arguments.count != params.count {
      throw SemanticError.invalidArgumentCount(
        function: methodName,
        expected: params.count,
        got: arguments.count
      )
    }

    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params) {
      var typedArg: TypedExpressionNode
      if case .lambdaExpression(let lambdaParams, let returnType, let body, _) = arg {
        typedArg = try inferLambdaExpression(
          parameters: lambdaParams,
          returnType: returnType,
          body: body,
          expectedType: param.type
        )
      } else {
        typedArg = try inferTypedExpression(arg, expectedType: param.type)
      }

      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }

    return .staticMethodCall(
      baseType: baseType,
      methodName: methodName,
      typeArgs: [],
      methodTypeArgs: methodTypeArgs,
      arguments: typedArguments,
      type: returnType
    )
  }

  private func inferStaticGenericMethodTypeArguments(
    baseType: Type,
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> [Type] {
    let templateName: String
    switch baseType {
    case .genericStruct(let name, _):
      templateName = name
    case .genericEnum(let name, _):
      templateName = name
    case .structure(let defId):
      templateName = context.getName(defId) ?? ""
    case .`enum`(let defId):
      templateName = context.getName(defId) ?? ""
    default:
      templateName = baseType.description
    }

    let methodTypeParamNames: [String]
    let unresolvedFunctionType: Type

    if let extensions = genericExtensionMethods[templateName],
       let methodInfo = extensions.first(where: { $0.method.name == methodName }) {
      let methodTypeParams = methodInfo.method.typeParameters
      if methodTypeParams.isEmpty {
        return []
      }

      methodTypeParamNames = methodTypeParams.map { $0.name }
      unresolvedFunctionType = try withNewScope {
        try currentScope.defineType("Self", type: baseType)
        for typeParam in methodTypeParams {
          currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
        }

        let params = try methodInfo.method.parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
        }
        let returns = try resolveTypeNode(methodInfo.method.returnType)
        return Type.function(parameters: params, returns: returns)
      }
    } else if let methods = extensionMethods[templateName],
              let methodSym = methods[methodName] {
      methodTypeParamNames = extractGenericParameterNames(from: methodSym.type)
      if methodTypeParamNames.isEmpty {
        return []
      }
      unresolvedFunctionType = methodSym.type
    } else {
      throw SemanticError.undefinedMember(methodName, templateName)
    }

    guard case .function(let params, _) = unresolvedFunctionType else {
      throw SemanticError(.generic("Expected function type for generic static method"), span: currentSpan)
    }

    if arguments.count != params.count {
      throw SemanticError.invalidArgumentCount(
        function: methodName,
        expected: params.count,
        got: arguments.count
      )
    }

    var methodTypeParamBindings: [String: Type] = [:]
    for (arg, param) in zip(arguments, params) {
      var typedArg = try inferTypedExpression(arg)
      typedArg = try coerceLiteral(typedArg, to: param.type)
      _ = unifyTypes(param.type, typedArg.type, bindings: &methodTypeParamBindings)
    }

    var resolvedMethodTypeArgs: [Type] = []
    for paramName in methodTypeParamNames {
      guard let boundType = methodTypeParamBindings[paramName] else {
        throw SemanticError(
          .generic("Cannot infer generic argument '\(paramName)' for static method '\(methodName)'"),
          span: currentSpan
        )
      }
      resolvedMethodTypeArgs.append(boundType)
    }

    return resolvedMethodTypeArgs
  }
}


// MARK: - Expression Helper Methods (moved from TypeChecker.swift)

extension TypeChecker {
  
  /// Builds an equality comparison call for types implementing Eq
  func buildEqualsCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    let methodName = "equals"
    let receiverType = lhs.type

    // Handle generic parameter case - create trait method placeholder
    if case .genericParameter(let paramName) = receiverType {
      guard hasTraitBound(paramName, "Eq") else {
        throw SemanticError(.generic("Type \(receiverType) is not constrained by trait Eq"), span: currentSpan)
      }
      let methods = try flattenedTraitMethods("Eq")
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait Eq is missing required method \(methodName)"), span: currentSpan)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)
      
      recordTraitPlaceholderInstantiation(
        baseType: receiverType,
        methodName: methodName,
        methodTypeArgs: []
      )
      
      // Create trait method placeholder instead of methodReference with __trait_ prefix
      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: "Eq",
        methodName: methodName,
        base: lhs,
        methodTypeArgs: [],
        type: expectedType
      )
      return .call(callee: callee, arguments: [rhs], type: .bool)
    }

    try enforceTraitConformance(
      receiverType,
      traitName: "Eq",
      context: "operator 'equals'"
    )
    
    // Concrete type case - look up the actual method
    guard let methodSym = try lookupConcreteMethodSymbol(on: receiverType, name: methodName) else {
      throw SemanticError.undefinedMember(methodName, receiverType.description)
    }

    guard case .function(let params, let returns) = methodSym.type else {
      throw SemanticError.invalidOperation(op: "call", type1: methodSym.type.description, type2: "")
    }
    if params.count != 2 {
      throw SemanticError.invalidArgumentCount(function: methodName, expected: max(0, params.count - 1), got: 1)
    }
    if returns != .bool {
      throw SemanticError.typeMismatch(expected: "Bool", got: returns.description)
    }

    // Value-passing semantics: pass lhs and rhs directly
    let callee: TypedExpressionNode = .methodReference(base: lhs, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: methodSym.type)
    return .call(callee: callee, arguments: [rhs], type: .bool)
  }

  /// Builds a comparison call for types implementing Ord
  func buildCompareCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    let methodName = "compare"
    let receiverType = lhs.type

    // Handle generic parameter case - create trait method placeholder
    if case .genericParameter(let paramName) = receiverType {
      guard hasTraitBound(paramName, "Ord") else {
        throw SemanticError(.generic("Type \(receiverType) is not constrained by trait Ord"), span: currentSpan)
      }
      let methods = try flattenedTraitMethods("Ord")
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait Ord is missing required method \(methodName)"), span: currentSpan)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)
      
      recordTraitPlaceholderInstantiation(
        baseType: receiverType,
        methodName: methodName,
        methodTypeArgs: []
      )
      
      // Create trait method placeholder instead of methodReference with __trait_ prefix
      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: "Ord",
        methodName: methodName,
        base: lhs,
        methodTypeArgs: [],
        type: expectedType
      )
      return .call(callee: callee, arguments: [rhs], type: .int)
    }

    try enforceTraitConformance(
      receiverType,
      traitName: "Ord",
      context: "operator 'compare'"
    )
    
    // Concrete type case - look up the actual method
    guard let methodSym = try lookupConcreteMethodSymbol(on: receiverType, name: methodName) else {
      throw SemanticError.undefinedMember(methodName, receiverType.description)
    }

    guard case .function(let params, let returns) = methodSym.type else {
      throw SemanticError.invalidOperation(op: "call", type1: methodSym.type.description, type2: "")
    }
    if params.count != 2 {
      throw SemanticError.invalidArgumentCount(function: methodName, expected: max(0, params.count - 1), got: 1)
    }
    if returns != .int {
      throw SemanticError.typeMismatch(expected: "Int", got: returns.description)
    }

    // Value-passing semantics: pass lhs and rhs directly
    let callee: TypedExpressionNode = .methodReference(base: lhs, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: methodSym.type)
    return .call(callee: callee, arguments: [rhs], type: .int)
  }

  // MARK: - Arithmetic Operator Lowering

  func buildArithmeticExpression(
    op: ArithmeticOperator,
    lhs: TypedExpressionNode,
    rhs: TypedExpressionNode
  ) throws -> TypedExpressionNode {
    var left = lhs
    var right = rhs

    var leftIsNumeric = isIntegerType(left.type) || isFloatType(left.type)
    var rightIsNumeric = isIntegerType(right.type) || isFloatType(right.type)

    if leftIsNumeric && !rightIsNumeric {
      if case .typeConstruction(_, _, _, let srcType) = right, isRuneType(srcType) {
        right = try coerceLiteral(right, to: left.type)
        rightIsNumeric = isIntegerType(right.type) || isFloatType(right.type)
      }
    } else if rightIsNumeric && !leftIsNumeric {
      if case .typeConstruction(_, _, _, let srcType) = left, isRuneType(srcType) {
        left = try coerceLiteral(left, to: right.type)
        leftIsNumeric = isIntegerType(left.type) || isFloatType(left.type)
      }
    }

    if leftIsNumeric && rightIsNumeric {
      if left.type != right.type {
        right = try coerceLiteral(right, to: left.type)
        if left.type != right.type {
          left = try coerceLiteral(left, to: right.type)
        }
      }

      if left.type == right.type {
        return .arithmeticExpression(left: left, op: op, right: right, type: left.type)
      }

      let opName: String
      switch op {
      case .plus: opName = "plus"
      case .minus: opName = "minus"
      case .multiply: opName = "multiply"
      case .divide: opName = "divide"
      case .remainder: opName = "remainder"
      }
      throw SemanticError.invalidOperation(op: opName, type1: left.type.description, type2: right.type.description)
    }

    // Pointer arithmetic: ptr + UInt or ptr - UInt
    if case .pointer = left.type, (op == .plus || op == .minus) {
      var offset = right
      offset = try coerceLiteral(offset, to: .uint)
      if offset.type == .uint {
        return .arithmeticExpression(left: left, op: op, right: offset, type: left.type)
      }
      throw SemanticError.invalidOperation(
        op: op == .plus ? "plus" : "minus",
        type1: left.type.description, type2: right.type.description)
    }

    return try buildNonNumericArithmeticExpression(op: op, lhs: left, rhs: right)
  }

  private func buildNonNumericArithmeticExpression(
    op: ArithmeticOperator,
    lhs: TypedExpressionNode,
    rhs: TypedExpressionNode
  ) throws -> TypedExpressionNode {
    let sameType = lhs.type == rhs.type

    switch op {
    case .plus:
      if sameType {
        if let call = try buildOperatorMethodCall(
          base: lhs,
          methodName: "add",
          traitName: "Add",
          requiredTraitArgs: nil,
          arguments: [rhs]
        ) {
          return call
        }
        throw SemanticError.undefinedMember("add", lhs.type.description)
      }
      if let call = try buildOperatorMethodCall(
        base: lhs,
        methodName: "add_vector",
        traitName: "Affine",
        requiredTraitArgs: [rhs.type],
        arguments: [rhs]
      ) {
        return call
      }
      throw SemanticError.undefinedMember("add_vector", lhs.type.description)

    case .minus:
      if sameType {
        if let call = try buildOperatorMethodCall(
          base: lhs,
          methodName: "sub_point",
          traitName: "Affine",
          requiredTraitArgs: nil,
          arguments: [rhs],
          allowMissingTrait: true
        ) {
          return call
        }

        if let call = try buildOperatorMethodCall(
          base: lhs,
          methodName: "sub",
          traitName: "Sub",
          requiredTraitArgs: nil,
          arguments: [rhs]
        ) {
          return call
        }

        throw SemanticError.undefinedMember("sub", lhs.type.description)
      }

      if let call = try buildOperatorMethodCall(
        base: lhs,
        methodName: "sub_vector",
        traitName: "Affine",
        requiredTraitArgs: [rhs.type],
        arguments: [rhs]
      ) {
        return call
      }
      throw SemanticError.undefinedMember("sub_vector", lhs.type.description)

    case .multiply:
      if sameType {
        if let call = try buildOperatorMethodCall(
          base: lhs,
          methodName: "mul",
          traitName: "Mul",
          requiredTraitArgs: nil,
          arguments: [rhs]
        ) {
          return call
        }
        throw SemanticError.undefinedMember("mul", lhs.type.description)
      }

      if let call = try buildOperatorMethodCall(
        base: lhs,
        methodName: "scale",
        traitName: "Scale",
        requiredTraitArgs: [rhs.type],
        arguments: [rhs]
      ) {
        return call
      }
      throw SemanticError.undefinedMember("scale", lhs.type.description)

    case .divide:
      if sameType {
        if let call = try buildOperatorMethodCall(
          base: lhs,
          methodName: "div",
          traitName: "Div",
          requiredTraitArgs: nil,
          arguments: [rhs]
        ) {
          return call
        }
        throw SemanticError.undefinedMember("div", lhs.type.description)
      }

      if let call = try buildOperatorMethodCall(
        base: lhs,
        methodName: "inv_scale",
        traitName: "InvScale",
        requiredTraitArgs: [rhs.type],
        arguments: [rhs]
      ) {
        return call
      }
      throw SemanticError.undefinedMember("inv_scale", lhs.type.description)

    case .remainder:
      if sameType {
        if let call = try buildOperatorMethodCall(
          base: lhs,
          methodName: "rem",
          traitName: "Rem",
          requiredTraitArgs: nil,
          arguments: [rhs]
        ) {
          return call
        }
        throw SemanticError.undefinedMember("rem", lhs.type.description)
      }
      throw SemanticError.invalidOperation(op: "%", type1: lhs.type.description, type2: rhs.type.description)
    }
  }

  private func buildOperatorMethodCall(
    base: TypedExpressionNode,
    methodName: String,
    traitName: String,
    requiredTraitArgs: [Type]?,
    arguments: [TypedExpressionNode],
    allowMissingTrait: Bool = false
  ) throws -> TypedExpressionNode? {
    if case .genericParameter(let paramName) = base.type {
      return try buildTraitMethodCall(
        paramName: paramName,
        base: base,
        traitName: traitName,
        requiredTraitArgs: requiredTraitArgs,
        methodName: methodName,
        arguments: arguments,
        allowMissingTrait: allowMissingTrait
      )
    }

    if allowMissingTrait,
       let methodSym = try lookupConcreteMethodSymbol(on: base.type, name: methodName) {
      return try buildConcreteMethodCall(base: base, method: methodSym, arguments: arguments)
    }

    let nominalTraitSatisfied: Bool = {
      do {
        if let requiredTraitArgs {
          try enforceGenericTraitConformance(
            base.type,
            traitName: traitName,
            traitTypeArgs: requiredTraitArgs,
            context: "operator '\(methodName)'"
          )
        } else {
          try enforceTraitConformance(
            base.type,
            traitName: traitName,
            context: "operator '\(methodName)'"
          )
        }
        return true
      } catch {
        return false
      }
    }()

    if !nominalTraitSatisfied {
      if allowMissingTrait {
        return nil
      }
      if let requiredTraitArgs {
        throw SemanticError(.generic(
          "Type \(base.type) does not explicitly implement trait [\(requiredTraitArgs.map { $0.description }.joined(separator: ", "))]\(traitName)"
        ), span: currentSpan)
      }
      throw SemanticError(.generic(
        "Type \(base.type) does not explicitly implement trait \(traitName)"
      ), span: currentSpan)
    }

    if let methodSym = try lookupConcreteMethodSymbol(on: base.type, name: methodName) {
      return try buildConcreteMethodCall(base: base, method: methodSym, arguments: arguments)
    }

    return nil
  }

  private func buildTraitMethodCall(
    paramName: String,
    base: TypedExpressionNode,
    traitName: String,
    requiredTraitArgs: [Type]?,
    methodName: String,
    arguments: [TypedExpressionNode],
    allowMissingTrait: Bool
  ) throws -> TypedExpressionNode? {
    guard let constraint = findTraitConstraint(paramName, traitName) else {
      if allowMissingTrait { return nil }
      let opName: String
      switch methodName {
      case "add": opName = "plus"
      case "sub": opName = "minus"
      case "mul": opName = "multiply"
      case "div": opName = "divide"
      case "rem": opName = "remainder"
      default: opName = "operation"
      }
      throw SemanticError(
        .generic("Invalid operation \(opName) between types \(base.type) and \(base.type)"),
        span: currentSpan)
    }

    let traitInfo = traits[traitName]
    var traitTypeArgs: [Type] = []
    if case .generic(_, let argNodes) = constraint {
      for argNode in argNodes {
        let argType = try resolveTypeNode(argNode)
        traitTypeArgs.append(argType)
      }
    }

    if let required = requiredTraitArgs {
      if traitTypeArgs.count != required.count || !zip(traitTypeArgs, required).allSatisfy({ $0 == $1 }) {
        if allowMissingTrait { return nil }
        throw SemanticError.typeMismatch(
          expected: "[\(required.map { $0.description }.joined(separator: ", "))]\(traitName)",
          got: "[\(traitTypeArgs.map { $0.description }.joined(separator: ", "))]\(traitName)"
        )
      }
    }

    let methods = try flattenedTraitMethods(traitName)
    guard let sig = methods[methodName] else {
      throw SemanticError(.generic("Trait \(traitName) is missing required method \(methodName)"), span: currentSpan)
    }

    let expectedType = try expectedFunctionTypeForTraitMethod(
      sig,
      selfType: base.type,
      traitInfo: traitInfo,
      traitTypeArgs: traitTypeArgs
    )

    recordTraitPlaceholderInstantiation(
      baseType: base.type,
      methodName: methodName,
      methodTypeArgs: []
    )

    let callee: TypedExpressionNode = .traitMethodPlaceholder(
      traitName: traitName,
      methodName: methodName,
      base: base,
      methodTypeArgs: [],
      type: expectedType
    )

    guard case .function(let params, let returns) = expectedType else {
      throw SemanticError.invalidOperation(op: "call", type1: expectedType.description, type2: "")
    }

    if arguments.count != params.count - 1 {
      throw SemanticError.invalidArgumentCount(
        function: methodName,
        expected: params.count - 1,
        got: arguments.count
      )
    }

    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg = arg
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }

    return .call(callee: callee, arguments: typedArguments, type: returns)
  }

  private func buildConcreteMethodCall(
    base: TypedExpressionNode,
    method: Symbol,
    arguments: [TypedExpressionNode]
  ) throws -> TypedExpressionNode {
    guard case .function(let params, let returns) = method.type else {
      throw SemanticError.invalidOperation(op: "call", type1: method.type.description, type2: "")
    }

    if arguments.count != params.count - 1 {
      let name = context.getName(method.defId) ?? "<unknown>"
      throw SemanticError.invalidArgumentCount(
        function: name,
        expected: params.count - 1,
        got: arguments.count
      )
    }

    // Handle self parameter
    var finalBase = base
    if let firstParam = params.first {
      if case .reference(let inner) = firstParam.type,
         inner == base.type,
         base.valueCategory == .rvalue {
        // 禁止对 rvalue 调用 self ref 方法
        let methodName = context.getName(method.defId) ?? "<unknown>"
        throw SemanticError(.generic("Cannot call 'self ref' method '\(methodName)' on an rvalue; store the value in a 'let mut' variable first"), span: currentSpan)
      }

      if base.type != firstParam.type {
        if case .reference(let inner) = firstParam.type, inner == base.type {
          if base.valueCategory == .lvalue {
            finalBase = .referenceExpression(expression: base, type: firstParam.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: base.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = base.type, inner == firstParam.type {
          finalBase = .derefExpression(expression: base, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: firstParam.type.description,
            got: base.type.description
          )
        }
      }
    }

    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg = arg
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }

    let callee: TypedExpressionNode = .methodReference(
      base: finalBase, method: method, typeArgs: nil, methodTypeArgs: nil, type: method.type
    )
    return .call(callee: callee, arguments: typedArguments, type: returns)
  }
  
  /// Resolves an lvalue expression for assignment
  func resolveLValue(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .identifier(let name):
      guard let defId = currentScope.lookup(name, sourceFile: currentSourceFile),
            let type = defIdMap.getSymbolType(defId) else {
        throw SemanticError.undefinedVariable(name)
      }
      guard currentScope.isMutable(name, sourceFile: currentSourceFile) else { throw SemanticError.assignToImmutable(name) }
      let kind = defIdMap.getSymbolKind(defId) ?? .variable(.MutableValue)
      let symbol = Symbol(defId: defId, type: type, kind: kind)
      return .variable(identifier: symbol)

    case .memberPath(let base, let path):
      // Check if base evaluates to a Reference type (RValue allowed)
      // OR if base resolves to an LValue (Mut Value required)

      let inferredBase = try inferTypedExpression(base)
      // Optimization: Peel auto-deref for lvalue resolution
      let typedBase: TypedExpressionNode
      if case .derefExpression(let inner, _) = inferredBase {
        typedBase = inner
      } else {
        typedBase = inferredBase
      }

      func isRefLikeType(_ type: Type) -> Bool {
        switch type {
        case .reference(_), .pointer(_):
          return true
        default:
          return false
        }
      }

      func isAddressableValueBase(_ expr: TypedExpressionNode) -> Bool {
        switch expr {
        case .variable:
          return true
        case .memberPath(let source, _):
          return isAddressableValueBase(source)
        case .derefExpression:
          return true
        default:
          return false
        }
      }

      func baseAllowsValueMutation(_ expr: TypedExpressionNode) -> Bool {
        switch expr {
        case .variable(let identifier):
          if isRefLikeType(identifier.type) { return true }
          return identifier.isMutable()
        case .memberPath(let source, let members):
          var allowed = baseAllowsValueMutation(source)
          for member in members {
            if isRefLikeType(member.type) {
              allowed = true
            }
          }
          return allowed
        case .derefExpression:
          return true
        default:
          return false
        }
      }

      let baseIsRefLike = isRefLikeType(typedBase.type)
      if !baseIsRefLike && !isAddressableValueBase(typedBase) {
        throw SemanticError.invalidOperation(
          op: "assignment target",
          type1: "temporary member path",
          type2: ""
        )
      }

      var valueMutationAllowed = baseIsRefLike || baseAllowsValueMutation(typedBase)

      // Now resolve path members on typedBase.
      var currentType = typedBase.type
      var resolvedPath: [Symbol] = []

      func canTraverseImmutableIntermediate(_ memberType: Type, isLastMember: Bool) -> Bool {
        guard !isLastMember else { return false }
        return isRefLikeType(memberType)
      }

      for (memberIndex, memberName) in path.enumerated() {
        let isLastMember = memberIndex == path.count - 1
        let (typeToLookup, isPointerAccess) = {
          if case .reference(let inner) = currentType { return (inner, false) }
          if case .pointer(let inner) = currentType { return (inner, true) }
          return (currentType, false)
        }()

        // Handle concrete structure types
        if case .structure(let defId) = typeToLookup {
          if context.isForeignStruct(defId) {
            guard let field = context.getForeignStructFields(defId)?.first(where: { $0.name == memberName }) else {
              let typeName = context.getName(defId) ?? typeToLookup.description
              throw SemanticError(.unknownForeignField(type: typeName, field: memberName), span: currentSpan)
            }

            resolvedPath.append(
              makeLocalSymbol(name: field.name, type: field.type, kind: .variable(.MutableValue)))
            currentType = field.type
            continue
          }

          guard let member = context.getStructMembers(defId)?.first(where: { $0.name == memberName }) else {
            throw SemanticError.undefinedMember(memberName, typeToLookup.description)
          }

          // Check field visibility
          if !isFieldAccessibleForMemberAccess(fieldAccess: member.access, defId: defId) {
            let structName = context.getName(defId) ?? typeToLookup.description
            let accessLabel = member.access == .private ? "private" : "protected"
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(memberName)' of type '\(structName)'"
            ), span: currentSpan)
          }

          if !member.mutable && !canTraverseImmutableIntermediate(member.type, isLastMember: isLastMember) {
            throw SemanticError.assignToImmutable(memberName)
          }
          if isLastMember && member.mutable && !valueMutationAllowed {
            throw SemanticError.assignToImmutable(memberName)
          }

          resolvedPath.append(
            makeLocalSymbol(name: member.name, type: member.type, kind: .variable(.MutableValue)))
          if isRefLikeType(member.type) {
            valueMutationAllowed = true
          }
          currentType = member.type
          continue
        }
        
        // Handle genericStruct types - look up member from template
        if case .genericStruct(let templateName, let typeArgs) = typeToLookup {
          guard let template = currentScope.lookupGenericStructTemplate(templateName) else {
            throw SemanticError.undefinedType(templateName)
          }
          
          // Create type substitution map
          var substitution: [String: Type] = [:]
          for (i, param) in template.typeParameters.enumerated() {
            if i < typeArgs.count {
              substitution[param.name] = typeArgs[i]
            }
          }
          
          // Look up member in template
          guard let param = template.parameters.first(where: { $0.name == memberName }) else {
            throw SemanticError.undefinedMember(memberName, typeToLookup.description)
          }
          
          // Check field visibility
          let fieldAccess = param.access
          if !isFieldAccessibleForMemberAccess(fieldAccess: fieldAccess, defId: template.defId) {
            let accessLabel = fieldAccess == .private ? "private" : "protected"
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(memberName)' of type '\(templateName)'"
            ), span: currentSpan)
          }
          
          // Resolve member type with substitution
          let memberType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(param.type)
          }

          if !param.mutable && !canTraverseImmutableIntermediate(memberType, isLastMember: isLastMember) {
            throw SemanticError.assignToImmutable(memberName)
          }
          if isLastMember && param.mutable && !valueMutationAllowed {
            throw SemanticError.assignToImmutable(memberName)
          }
          
          resolvedPath.append(
            makeLocalSymbol(name: param.name, type: memberType, kind: .variable(.MutableValue)))
          if isRefLikeType(memberType) {
            valueMutationAllowed = true
          }
          currentType = memberType
          continue
        }

        if isPointerAccess {
          throw SemanticError(
            .pointerMemberAccessOnNonStruct(field: memberName, type: typeToLookup.description),
            span: currentSpan
          )
        }
        throw SemanticError.invalidOperation(
          op: "member access on non-struct", type1: typeToLookup.description, type2: "")
      }
      return .memberPath(source: typedBase, path: resolvedPath)

    case .subscriptExpression(_, _):
      // Direct assignment to `x[i]` is lowered to `set_at` in statement checking.
      // Treat subscript as an invalid assignment target here.
      throw SemanticError.invalidOperation(op: "assignment target", type1: "subscript", type2: "")

    case .derefExpression(let inner):
      // Allow `deref x = expr` only for pointer-typed expressions.
      // Deref assignment on `T ref` is not allowed — managed references do not support whole-value write-back.
      let typedInner = try inferTypedExpression(inner)
      if case .reference = typedInner.type {
        throw SemanticError(.generic(
          "Cannot use deref assignment on a reference type. Managed references (T ref) do not support whole-value write-back through deref; deref assignment is only allowed on pointer types (T ptr)."
        ), span: currentSpan)
      }
      guard case .pointer(let elementType) = typedInner.type else {
        throw SemanticError.typeMismatch(
          expected: "Pointer type",
          got: typedInner.type.description
        )
      }

      return .derefExpression(expression: typedInner, type: elementType)

    default:
      throw SemanticError.invalidOperation(
        op: "assignment target", type1: String(describing: expr), type2: "")
    }
  }

  private func isLiteralExpression(_ expr: ExpressionNode) -> Bool {
    switch expr {
    case .integerLiteral, .floatLiteral, .stringLiteral, .booleanLiteral:
      return true
    default:
      return false
    }
  }

  private func isDerefExpression(_ expr: ExpressionNode) -> Bool {
    if case .derefExpression = expr {
      return true
    }
    return false
  }

  private func typeCheckInterpolatedParts(
    _ parts: [InterpolatedPart],
    span: SourceSpan
  ) throws -> [TypedInterpolatedPart] {
    var typedParts: [TypedInterpolatedPart] = []

    for part in parts {
      switch part {
      case .literal(let value):
        typedParts.append(.literal(value))
      case .expression(let expr):
        let typedExpr = try inferTypedExpression(expr)
        if !isStringType(typedExpr.type) {
          _ = try buildToStringExpression(typedExpr, span: span)
        }
        typedParts.append(.expression(typedExpr))
      }
    }

    return typedParts
  }

  private func lowerInterpolatedString(
    parts: [TypedInterpolatedPart],
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    guard !parts.isEmpty else {
      return .stringLiteral(value: "", type: builtinStringType())
    }

    var result = try convertInterpolatedPartToString(parts[0], span: span)

    for part in parts.dropFirst() {
      let rhs = try convertInterpolatedPartToString(part, span: span)
      result = try buildArithmeticExpression(op: .plus, lhs: result, rhs: rhs)
    }

    return result
  }

  private func convertInterpolatedPartToString(
    _ part: TypedInterpolatedPart,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    switch part {
    case .literal(let value):
      return .stringLiteral(value: value, type: builtinStringType())
    case .expression(let expr):
      return try buildToStringExpression(expr, span: span)
    }
  }

  private func buildToStringExpression(
    _ expr: TypedExpressionNode,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    if isStringType(expr.type) {
      return expr
    }

    if let call = try buildOperatorMethodCall(
      base: expr,
      methodName: "to_string",
      traitName: "ToString",
      requiredTraitArgs: nil,
      arguments: []
    ) {
      return call
    }

    throw SemanticError(
      .generic("Type '\(expr.type)' does not implement ToString trait"),
      span: span
    )
  }
}


// MARK: - Range Expression Type Checking

extension TypeChecker {
  
  /// Type checks a range expression and desugars it to Range enum construction.
  /// Range expressions like `a..b` are desugared to `[T]Range.Closed(a, b)`
  func inferRangeExpression(
    operator op: RangeOperator,
    left: ExpressionNode?,
    right: ExpressionNode?,
    expectedType: Type? = nil
  ) throws -> TypedExpressionNode {
    // Extract expected element type from expectedType (e.g. [UInt]Range -> UInt)
    let expectedElementType: Type?
    if let expected = expectedType,
       case .genericEnum(let template, let args) = expected,
       template == "Range",
       args.count == 1 {
      expectedElementType = args[0]
    } else {
      expectedElementType = nil
    }

    // 1. Type check operands (with expected type for literal coercion)
    var typedLeft: TypedExpressionNode? = nil
    var typedRight: TypedExpressionNode? = nil
    if let l = left {
      typedLeft = try inferTypedExpression(l, expectedType: expectedElementType)
      if let eet = expectedElementType {
        typedLeft = try coerceLiteral(typedLeft!, to: eet)
      }
    }
    if let r = right {
      typedRight = try inferTypedExpression(r, expectedType: expectedElementType)
      if let eet = expectedElementType {
        typedRight = try coerceLiteral(typedRight!, to: eet)
      }
    }
    
    // 2. Determine element type T
    let elementType: Type
    if let l = typedLeft {
      elementType = l.type
      // If both operands exist, verify they have the same type
      if let r = typedRight {
        if l.type != r.type {
          throw SemanticError(.typeMismatch(expected: l.type.description, got: r.type.description), span: currentSpan)
        }
      }
    } else if let r = typedRight {
      elementType = r.type
    } else {
      // Full with no operands - try to infer from expected type
      if let eet = expectedElementType {
        elementType = eet
      } else {
        throw SemanticError(.generic("FullRange requires type annotation or context type"), span: currentSpan)
      }
    }
    
    // 3. Verify T implements Ord
    try enforceTraitConformance(elementType, traitName: "Ord")
    
    // 4. Construct Range type
    let rangeType = Type.genericEnum(template: "Range", args: [elementType])
    
    // 5. Determine case name and arguments
    let caseName: String
    let args: [TypedExpressionNode]
    
    switch op {
    case .closed:
      caseName = "Closed"
      args = [typedLeft!, typedRight!]
    case .closedOpen:
      caseName = "ClosedOpen"
      args = [typedLeft!, typedRight!]
    case .openClosed:
      caseName = "OpenClosed"
      args = [typedLeft!, typedRight!]
    case .open:
      caseName = "Open"
      args = [typedLeft!, typedRight!]
    case .from:
      caseName = "From"
      args = [typedLeft!]
    case .fromOpen:
      caseName = "After"
      args = [typedLeft!]
    case .to:
      caseName = "To"
      args = [typedRight!]
    case .toOpen:
      caseName = "Until"
      args = [typedRight!]
    case .full:
      caseName = "Full"
      args = []
    }
    
    // 6. Return enum construction expression
    return .enumConstruction(type: rangeType, caseName: caseName, arguments: args)
  }
}


// MARK: - For Loop Type Checking and Desugaring

extension TypeChecker {
  
  /// Type checks a for expression and desugars it to let + while + match.
  /// for <pattern> = <iterable> then <body>
  /// becomes:
  /// let mut __koral_iter_N = <iterable>.iterator() then  // or just <iterable> if it's already an iterator
  ///   while true then
  ///     when __koral_iter_N.next() is {
  ///       .Some(<pattern>) then <body>,
  ///       .None then break
  ///     }
  func inferForExpression(
    pattern: PatternNode,
    iterable: ExpressionNode,
    body: ExpressionNode
  ) throws -> TypedExpressionNode {
    // 1. Type check the iterable expression
    let typedIterable = try inferTypedExpression(iterable)
    var iterableType = typedIterable.type
    
    // Auto-deref: if the iterable is a reference type, unwrap it
    if case .reference(let inner) = iterableType {
      iterableType = inner
    }
    
    // 2. First check if the expression type itself is an iterator
    //    (has a next(self ref) [T]Option method)
    if let elementType = try? extractIteratorElementType(iterableType) {
      try enforceGenericTraitConformance(
        iterableType,
        traitName: "Iterator",
        traitTypeArgs: [elementType],
        context: "for-in iterator check"
      )
      // The expression itself is an iterator, use it directly
      try checkForLoopPatternExhaustiveness(pattern: pattern, elementType: elementType)
      return try desugarForLoop(
        pattern: pattern,
        typedIterable: typedIterable,
        iteratorType: iterableType,
        elementType: elementType,
        body: body,
        needsIteratorCall: false  // Don't call iterator(), use expression directly
      )
    }
    
    // 3. Look up the iterator() method on the iterable type
    guard let iteratorMethod = try lookupConcreteMethodSymbol(on: iterableType, name: "iterator") else {
      throw SemanticError(.generic(
        "Type \(iterableType) is not iterable: missing iterator() method and does not implement Iterator"
      ), span: currentSpan)
    }
    
    // 4. Get the iterator type from the method's return type
    guard case .function(_, let iteratorType) = iteratorMethod.type else {
      throw SemanticError(.generic("iterator() must be a function"), span: currentSpan)
    }
    
    // 5. Extract the element type from the iterator
    let elementType = try extractIteratorElementType(iteratorType)

    try enforceGenericTraitConformance(
      iteratorType,
      traitName: "Iterator",
      traitTypeArgs: [elementType],
      context: "for-in iterator result check"
    )

    try enforceGenericTraitConformance(
      iterableType,
      traitName: "Iterable",
      traitTypeArgs: [elementType, iteratorType],
      context: "for-in iterable check"
    )
    
    // 6. Check pattern exhaustiveness against element type
    try checkForLoopPatternExhaustiveness(pattern: pattern, elementType: elementType)
    
    // 7. Desugar the for loop
    return try desugarForLoop(
      pattern: pattern,
      typedIterable: typedIterable,
      iteratorType: iteratorType,
      elementType: elementType,
      body: body,
      needsIteratorCall: true  // Need to call iterator()
    )
  }

  /// Extracts the element type T from an iterator type.
  /// The iterator must have a next(self ref) [T]Option method.
  private func extractIteratorElementType(_ iteratorType: Type) throws -> Type {
    // Look up the next method on the iterator type
    guard let nextMethod = try lookupConcreteMethodSymbol(on: iteratorType, name: "next") else {
      throw SemanticError(.generic(
        "Iterator type \(iteratorType) missing next() method"
      ), span: currentSpan)
    }
    
    // Verify the return type is [T]Option
    guard case .function(_, let returnType) = nextMethod.type else {
      throw SemanticError(.generic("Iterator.next() must be a function"), span: currentSpan)
    }
    
    // Check if return type is Option<T>
    switch returnType {
    case .genericEnum(let template, let args) where template == "Option" && args.count == 1:
      return args[0]
    default:
      throw SemanticError(.generic(
        "Iterator.next() must return [T]Option, got \(returnType)"
      ), span: currentSpan)
    }
  }

  /// Checks that the for loop pattern is exhaustive for the element type.
  private func checkForLoopPatternExhaustiveness(pattern: PatternNode, elementType: Type) throws {
    // For simple variable bindings and wildcards, they are always exhaustive
    switch pattern {
    case .variable, .wildcard:
      return
    case .enumCase:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive for element type \(elementType). Use a simple variable binding."
      ), span: currentSpan)
    case .booleanLiteral, .integerLiteral, .stringLiteral, .runeLiteral, .negativeIntegerLiteral:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Literal patterns are not exhaustive."
      ), span: currentSpan)
    case .comparisonPattern:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Comparison patterns are not exhaustive."
      ), span: currentSpan)
    case .andPattern, .orPattern, .notPattern:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Pattern combinators are not exhaustive."
      ), span: currentSpan)
    case .structPattern:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Struct destructuring patterns are not exhaustive."
      ), span: currentSpan)
    }
  }

  /// Desugars a for loop into let + while + match.
  func desugarForLoop(
    pattern: PatternNode,
    typedIterable: TypedExpressionNode,
    iteratorType: Type,
    elementType: Type,
    body: ExpressionNode,
    needsIteratorCall: Bool
  ) throws -> TypedExpressionNode {
    // Generate unique iterator variable name
    let iterVarName = "__koral_iter_\(synthesizedTempIndex)"
    synthesizedTempIndex += 1
    
    // Create iterator symbol (mutable)
    let iterSymbol = makeLocalSymbol(name: iterVarName, type: iteratorType, kind: .variable(.MutableValue))
    
    // Build the iterator initialization expression
    let iteratorInit: TypedExpressionNode
    if needsIteratorCall {
      // Build: iterable.iterator()
      iteratorInit = try buildIteratorCall(typedIterable: typedIterable, iteratorType: iteratorType)
    } else {
      // Use the expression directly as the iterator
      iteratorInit = typedIterable
    }
    
    // Enter a new scope for the let expression
    return try withNewScope {
      // Define the iterator variable in scope
      currentScope.define(iterVarName, defId: iterSymbol.defId)
      
      // Build: __koral_iter_N.next()
      let iterVarExpr = TypedExpressionNode.variable(identifier: iterSymbol)
      let iterRefExpr = TypedExpressionNode.referenceExpression(
        expression: iterVarExpr,
        type: .reference(inner: iteratorType)
      )
      let nextCall = try buildNextCall(iterRef: iterRefExpr, elementType: elementType)
      
      // Build the match expression body
      let whenExpr = try buildForLoopWhenExpression(
        nextCall: nextCall,
        pattern: pattern,
        elementType: elementType,
        body: body
      )
      
      // Build: while true then match
      loopDepth += 1
      let whileExpr = TypedExpressionNode.whileExpression(
        condition: .booleanLiteral(value: true, type: .bool),
        body: whenExpr,
        type: .void
      )
      loopDepth -= 1
      
      // Build: let mut __iter = iterator() then while ...
      return .makeLetBlock(
        identifier: iterSymbol,
        value: iteratorInit,
        body: whileExpr,
        type: .void
      )
    }
  }

  /// Builds the iterator() method call on the iterable.
  func buildIteratorCall(
    typedIterable: TypedExpressionNode,
    iteratorType: Type
  ) throws -> TypedExpressionNode {
    // Auto-deref: if the iterable is a reference, we need to deref it first
    var actualIterable = typedIterable
    var actualIterableType = typedIterable.type
    if case .reference(let inner) = typedIterable.type {
      actualIterable = .derefExpression(expression: typedIterable, type: inner)
      actualIterableType = inner
    }
    
    // Look up the iterator method
    guard let iteratorMethod = try lookupConcreteMethodSymbol(on: actualIterableType, name: "iterator") else {
      throw SemanticError(.generic("iterator() method not found"), span: currentSpan)
    }
    
    // Build method reference
    let methodRef = TypedExpressionNode.methodReference(
      base: actualIterable,
      method: iteratorMethod,
      typeArgs: nil,
      methodTypeArgs: nil,
      type: iteratorMethod.type
    )
    
    // Build call
    return .call(callee: methodRef, arguments: [], type: iteratorType)
  }

  /// Builds the next() method call on the iterator reference.
  func buildNextCall(
    iterRef: TypedExpressionNode,
    elementType: Type
  ) throws -> TypedExpressionNode {
    // Get the iterator type from the reference
    guard case .reference(let iteratorType) = iterRef.type else {
      throw SemanticError(.generic("Expected reference to iterator"), span: currentSpan)
    }
    
    // Look up the next method
    guard let nextMethod = try lookupConcreteMethodSymbol(on: iteratorType, name: "next") else {
      throw SemanticError(.generic("next() method not found"), span: currentSpan)
    }
    
    // Build method reference
    let methodRef = TypedExpressionNode.methodReference(
      base: iterRef,
      method: nextMethod,
      typeArgs: nil,
      methodTypeArgs: nil,
      type: nextMethod.type
    )
    
    // The return type is [T]Option
    let optionType = Type.genericEnum(template: "Option", args: [elementType])
    
    // Build call
    return .call(callee: methodRef, arguments: [], type: optionType)
  }

  /// Builds the match expression for the for loop body.
  func buildForLoopWhenExpression(
    nextCall: TypedExpressionNode,
    pattern: PatternNode,
    elementType: Type,
    body: ExpressionNode
  ) throws -> TypedExpressionNode {
    // Build Some case pattern with the user's pattern
    let somePattern = try buildSomePattern(userPattern: pattern, elementType: elementType)
    
    // Type check the body in a new scope with pattern bindings
    let typedBody = try withNewScope {
      // Bind pattern variables using the typed pattern symbols
      for symbol in extractPatternSymbols(from: somePattern) {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
        }
      }

      // Type check body
      loopDepth += 1
      let result = try inferTypedExpression(body)
      loopDepth -= 1
      return result
    }
    
    // Build None case with break
    let nonePattern = TypedPattern.enumCase(caseName: "None", tagIndex: 0, elements: [])
    let breakExpr = TypedExpressionNode.blockExpression(
      statements: [.break],
      type: .void
    )
    
    // Build match cases
    let someCase = TypedMatchCase(pattern: somePattern, body: typedBody)
    let noneCase = TypedMatchCase(pattern: nonePattern, body: breakExpr)
    
    return .whenExpression(
      subject: nextCall,
      cases: [someCase, noneCase],
      type: .void
    )
  }

  /// Builds the Some pattern wrapping the user's pattern.
  func buildSomePattern(userPattern: PatternNode, elementType: Type) throws -> TypedPattern {
    let innerPattern = try convertPatternToTypedPattern(userPattern, expectedType: elementType)
    // Some has tag index 1 (None is 0, Some is 1 in Option)
    return .enumCase(caseName: "Some", tagIndex: 1, elements: [innerPattern])
  }

  /// Converts an AST pattern to a typed pattern.
  func convertPatternToTypedPattern(_ pattern: PatternNode, expectedType: Type) throws -> TypedPattern {
    switch pattern {
    case .variable(let name, let mutable, _):
      let varKind: VariableKind = mutable ? .MutableValue : .Value
      let symbol = makeLocalSymbol(name: name, type: expectedType, kind: .variable(varKind))
      return .variable(symbol: symbol)
    case .wildcard:
      return .wildcard
    case .booleanLiteral(let value, _):
      return .booleanLiteral(value: value)
    case .integerLiteral(let value, _):
      return .integerLiteral(value: value)
    case .negativeIntegerLiteral(let value, _):
      return .integerLiteral(value: "-\(value)")
    case .stringLiteral(let value, _):
      return .stringLiteral(value: value)
    case .runeLiteral(let value, _):
      guard let cp = singleRuneCodePoint(from: value) else {
        let count = value.unicodeScalars.count
        if count == 0 {
          throw SemanticError(.generic("Rune literal cannot be empty"), span: currentSpan)
        }
        throw SemanticError(.generic("Rune literal must contain exactly one Unicode code point, but '\(value)' contains \(count)"), span: currentSpan)
      }
      return .integerLiteral(value: String(cp))
    case .enumCase(let caseName, let elements, _):
      let typedElements = try elements.map { elem -> TypedPattern in
        try convertPatternToTypedPattern(elem.pattern, expectedType: .void)
      }
      return .enumCase(caseName: caseName, tagIndex: 0, elements: typedElements)
    case .comparisonPattern(let op, let value, _):
      let intValue: Int64
      if value.hasPrefix("-") {
        let positiveValue = String(value.dropFirst())
        intValue = -(Int64(positiveValue) ?? 0)
      } else {
        intValue = Int64(value) ?? 0
      }
      return .comparisonPattern(operator: op, value: intValue)
    case .andPattern(let left, let right, _):
      return .andPattern(
        left: try convertPatternToTypedPattern(left, expectedType: expectedType),
        right: try convertPatternToTypedPattern(right, expectedType: expectedType)
      )
    case .orPattern(let left, let right, _):
      return .orPattern(
        left: try convertPatternToTypedPattern(left, expectedType: expectedType),
        right: try convertPatternToTypedPattern(right, expectedType: expectedType)
      )
    case .notPattern(let inner, _):
      return .notPattern(pattern: try convertPatternToTypedPattern(inner, expectedType: expectedType))
    case .structPattern(let typeName, let elements, _):
      let typedElements = try elements.map { elem -> TypedPattern in
        try convertPatternToTypedPattern(elem.pattern, expectedType: .void)
      }
      return .structPattern(typeName: typeName, elements: typedElements)
    }
  }

  /// Binds pattern variables in the current scope.
  func bindPatternVariables(pattern: PatternNode, type: Type) throws {
    switch pattern {
    case .variable(let name, let mutable, _):
      let symbol = makeLocalSymbol(
        name: name,
        type: type,
        kind: mutable ? .variable(.MutableValue) : .variable(.Value)
      )
      try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
    case .wildcard, .booleanLiteral, .integerLiteral, .stringLiteral, .runeLiteral, .negativeIntegerLiteral:
      break
    case .enumCase(_, let elements, _):
      for elem in elements {
        try bindPatternVariables(pattern: elem.pattern, type: .void)
      }
    case .structPattern(_, let elements, _):
      for elem in elements {
        try bindPatternVariables(pattern: elem.pattern, type: .void)
      }
    case .comparisonPattern:
      break
    case .andPattern(let left, let right, _):
      try bindPatternVariables(pattern: left, type: type)
      try bindPatternVariables(pattern: right, type: type)
    case .orPattern(let left, _, _):
      try bindPatternVariables(pattern: left, type: type)
    case .notPattern:
      break
    }
  }

  // MARK: - or else / and then Lowering

  /// Identifies whether a type is Option or Result and extracts inner types.
  private enum OptionResultKind {
    case option(innerType: Type)
    case result(okType: Type, errType: Type)

    var innerType: Type {
      switch self {
      case .option(let t): return t
      case .result(let t, _): return t
      }
    }
  }

  /// The fixed error type for Result: `Error ref` (trait object)
  private nonisolated(unsafe) static let resultErrorType: Type = .reference(inner: .traitObject(traitName: "Error", typeArgs: []))

  /// Extracts Option/Result kind from a type, or throws a diagnostic.
  private func extractOptionResultKind(
    _ type: Type, span: SourceSpan, operation: String
  ) throws -> OptionResultKind {
    if case .genericEnum(let template, let args) = type {
      if template == "Option", args.count == 1 {
        return .option(innerType: args[0])
      }
      if template == "Result", args.count == 1 {
        return .result(okType: args[0], errType: Self.resultErrorType)
      }
    }
    throw SemanticError(
      .generic("'\(operation)' can only be used with Option or Result types, got '\(type)'"),
      span: span
    )
  }

  /// Lowers `operand or else defaultExpr` into a whenExpression.
  private func lowerOrElseExpressionCore(
    typedOperand: TypedExpressionNode,
    kind: OptionResultKind,
    defaultExpr: ExpressionNode,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    let innerType = kind.innerType

    // Type-check defaultExpr, injecting `_` for Result's error value.
    let typedDefault: TypedExpressionNode
    let underscoreSymbol: Symbol?  // non-nil only for Result

    switch kind {
    case .result(_, let errType):
      let sym = makeLocalSymbol(name: "_", type: errType, kind: .variable(.Value))
      underscoreSymbol = sym
      typedDefault = try withNewScope {
        currentScope.define("_", defId: sym.defId)
        return try inferTypedExpression(defaultExpr, expectedType: innerType)
      }
    case .option:
      underscoreSymbol = nil
      typedDefault = try inferTypedExpression(defaultExpr, expectedType: innerType)
    }

    // Verify type compatibility: defaultExpr must be T or Never.
    if typedDefault.type != innerType && typedDefault.type != .never {
      throw SemanticError(
        .typeMismatch(expected: innerType.description, got: typedDefault.type.description),
        span: span
      )
    }

    // Build the lowered whenExpression.
    switch kind {
    case .option:
      let valSym = makeLocalSymbol(name: "__val", type: innerType, kind: .variable(.Value))
      let somePattern = TypedPattern.enumCase(caseName: "Some", tagIndex: 1,
                                                elements: [.variable(symbol: valSym)])
      let nonePattern = TypedPattern.enumCase(caseName: "None", tagIndex: 0, elements: [])
      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: somePattern, body: .variable(identifier: valSym)),
          TypedMatchCase(pattern: nonePattern, body: typedDefault),
        ],
        type: innerType
      )

    case .result(let okType, _):
      let valSym = makeLocalSymbol(name: "__val", type: okType, kind: .variable(.Value))
      // Reuse the DefId from the `_` injection so references in defaultExpr resolve correctly.
      let errSym = underscoreSymbol!
      let okPattern = TypedPattern.enumCase(caseName: "Ok", tagIndex: 0,
                                             elements: [.variable(symbol: valSym)])
      let errPattern = TypedPattern.enumCase(caseName: "Error", tagIndex: 1,
                                              elements: [.variable(symbol: errSym)])
      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: okPattern, body: .variable(identifier: valSym)),
          TypedMatchCase(pattern: errPattern, body: typedDefault),
        ],
        type: innerType
      )
    }
  }

  /// Lowers `operand or else defaultExpr` into a whenExpression.
  private func lowerOrElseExpression(
    operand: ExpressionNode,
    defaultExpr: ExpressionNode,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    let typedOperand = try inferTypedExpression(operand)
    let kind = try extractOptionResultKind(typedOperand.type, span: span, operation: "or else")
    return try lowerOrElseExpressionCore(
      typedOperand: typedOperand,
      kind: kind,
      defaultExpr: defaultExpr,
      span: span
    )
  }

  /// Lowers `operand or return` by desugaring to `operand or else { return ... }`.
  private func lowerOrReturnExpression(
    operand: ExpressionNode,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    guard currentFunctionReturnType != nil else {
      throw SemanticError(.generic("'or return' can only be used inside a function"), span: span)
    }
    if insideFinally {
      throw SemanticError(
        .generic("control flow statement 'return' is not allowed in finally expression"),
        span: span
      )
    }

    let typedOperand = try inferTypedExpression(operand)
    let kind = try extractOptionResultKind(typedOperand.type, span: span, operation: "or return")

    let returnValue: ExpressionNode
    switch kind {
    case .option:
      returnValue = .implicitMemberExpression(memberName: "None", arguments: [], span: span)
    case .result:
      returnValue = .implicitMemberExpression(
        memberName: "Error",
        arguments: [CallArg(label: nil, expression: .identifier("_"))],
        span: span
      )
    }

    let defaultExpr: ExpressionNode = .blockExpression(
      statements: [.return(value: returnValue, span: span)]
    )

    return try lowerOrElseExpressionCore(
      typedOperand: typedOperand,
      kind: kind,
      defaultExpr: defaultExpr,
      span: span
    )
  }

  // MARK: - and then Lowering

  /// Computes the result type of `and then`, with smart flattening.
  /// Returns (finalType, isFlattened).
  private func computeAndThenResultType(
    operandKind: OptionResultKind,
    transformResultType: Type
  ) -> (Type, Bool) {
    switch operandKind {
    case .option:
      // If transform already returns Option, flatten
      if case .genericEnum(let template, _) = transformResultType, template == "Option" {
        return (transformResultType, true)
      }
      // Otherwise wrap in Option
      return (.genericEnum(template: "Option", args: [transformResultType]), false)

    case .result:
      // If transform already returns Result (1 type param), flatten
      if case .genericEnum(let template, let args) = transformResultType,
         template == "Result", args.count == 1 {
        return (transformResultType, true)
      }
      // Otherwise wrap in Result
      return (.genericEnum(template: "Result", args: [transformResultType]), false)
    }
  }

  /// Lowers `operand and then transformExpr` into a whenExpression.
  private func lowerAndThenExpression(
    operand: ExpressionNode,
    transformExpr: ExpressionNode,
    span: SourceSpan,
    expectedType: Type? = nil
  ) throws -> TypedExpressionNode {
    let typedOperand = try inferTypedExpression(operand)
    let kind = try extractOptionResultKind(typedOperand.type, span: span, operation: "and then")
    let innerType = kind.innerType

    // Derive an expected type for the transform expression from the outer expectedType.
    // e.g. if expectedType is [U]Option, the transform should produce U or [U]Option.
    let transformExpectedType: Type? = expectedType.flatMap { outer in
      switch outer {
      case .genericEnum(let template, let args) where args.count == 1:
        switch kind {
        case .option where template == "Option":
          return args[0]
        case .result where template == "Result":
          return args[0]
        default:
          return nil
        }
      default:
        return nil
      }
    }

    // Create _ symbol, type-check transformExpr in child scope with _ injected.
    let underscoreSymbol = makeLocalSymbol(name: "_", type: innerType, kind: .variable(.Value))
    let typedTransform = try withNewScope {
      currentScope.define("_", defId: underscoreSymbol.defId)
      return try inferTypedExpression(transformExpr, expectedType: transformExpectedType)
    }

    let (finalType, flattened) = computeAndThenResultType(
      operandKind: kind, transformResultType: typedTransform.type)

    // Build the lowered whenExpression.
    switch kind {
    case .option:
      // Reuse underscoreSymbol as the Some pattern variable (DefId sharing).
      let somePattern = TypedPattern.enumCase(caseName: "Some", tagIndex: 1,
                                                elements: [.variable(symbol: underscoreSymbol)])
      let nonePattern = TypedPattern.enumCase(caseName: "None", tagIndex: 0, elements: [])

      let someBody: TypedExpressionNode
      if flattened {
        someBody = typedTransform
      } else {
        someBody = .enumConstruction(type: finalType, caseName: "Some",
                                      arguments: [typedTransform])
      }
      let noneBody = TypedExpressionNode.enumConstruction(
        type: finalType, caseName: "None", arguments: [])

      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: somePattern, body: someBody),
          TypedMatchCase(pattern: nonePattern, body: noneBody),
        ],
        type: finalType
      )

    case .result(_, let errType):
      // Reuse underscoreSymbol as the Ok pattern variable (DefId sharing).
      let errSym = makeLocalSymbol(name: "__err", type: errType, kind: .variable(.Value))
      let okPattern = TypedPattern.enumCase(caseName: "Ok", tagIndex: 0,
                                             elements: [.variable(symbol: underscoreSymbol)])
      let errPattern = TypedPattern.enumCase(caseName: "Error", tagIndex: 1,
                                              elements: [.variable(symbol: errSym)])

      let okBody: TypedExpressionNode
      if flattened {
        okBody = typedTransform
      } else {
        okBody = .enumConstruction(type: finalType, caseName: "Ok",
                                    arguments: [typedTransform])
      }
      let errBody = TypedExpressionNode.enumConstruction(
        type: finalType, caseName: "Error",
        arguments: [.variable(identifier: errSym)])

      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: okPattern, body: okBody),
          TypedMatchCase(pattern: errPattern, body: errBody),
        ],
        type: finalType
      )
    }
  }
}

import Foundation

// MARK: - Lambda Expression Type Checking Extension
// This extension contains methods for type checking lambda expressions and capture analysis.

extension TypeChecker {

  /// Type checks a lambda expression and returns a typed lambda expression.
  /// - Parameters:
  ///   - parameters: Lambda parameters with optional type annotations
  ///   - returnType: Optional return type annotation
  ///   - body: Lambda body expression
  ///   - expectedType: Expected function type for type inference (optional)
  /// - Returns: Typed lambda expression
  func inferLambdaExpression(
    parameters: [(name: String, type: TypeNode?)],
    returnType: TypeNode?,
    body: ExpressionNode,
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    // Extract expected parameter types and return type from expectedType
    var expectedParamTypes: [Type]? = nil
    var expectedReturnType: Type? = nil
    
    if case .function(let funcParams, let funcReturn) = expectedType {
      expectedParamTypes = funcParams.map { $0.type }
      expectedReturnType = funcReturn
    }
    
    // Resolve parameter types
    var typedParams: [(name: String, type: Type)] = []
    for (i, param) in parameters.enumerated() {
      let paramType: Type
      
      if let explicitType = param.type {
        // Use explicit type annotation
        paramType = try resolveTypeNode(explicitType)
      } else if let expected = expectedParamTypes, i < expected.count {
        // Infer from expected type
        paramType = expected[i]
      } else {
        throw SemanticError(.generic("Cannot infer type for parameter '\(param.name)'"), span: currentSpan)
      }
      
      typedParams.append((name: param.name, type: paramType))
    }
    
    // Enter new scope and add parameters
    return try withNewScope {
      // Build typed parameter symbols
      let paramSymbols = typedParams.map { param in
        makeLocalSymbol(
          name: param.name,
          type: param.type,
          kind: .variable(.Value)
        )
      }

      for symbol in paramSymbols {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
        }
      }

      // Analyze captured variables
      let captures = try analyzeCapturedVariables(body: body, params: typedParams)

      // Type check lambda body with lambda-local return type context.
      // This prevents `return` inside lambda from being checked against
      // outer function return types.
      let savedFunctionReturnType = currentFunctionReturnType
      let savedInferredFunctionReturnType = inferredFunctionReturnType
      let savedIsInferringFunctionReturnType = isInferringFunctionReturnType
      defer { currentFunctionReturnType = savedFunctionReturnType }
      defer { inferredFunctionReturnType = savedInferredFunctionReturnType }
      defer { isInferringFunctionReturnType = savedIsInferringFunctionReturnType }
      let savedBranchBreakTargets = branchBreakTargets
      defer { branchBreakTargets = savedBranchBreakTargets }
      branchBreakTargets = []

      // Lambda has its own scope, so reset insideDefer.
      // This allows return/break/continue/defer inside a lambda that
      // appears within a defer expression.
      let savedInsideDefer = insideDefer
      insideDefer = false
      defer { insideDefer = savedInsideDefer }

      let resolvedExplicitReturnType = try returnType.map { try resolveTypeNode($0) }
      let inferReturnTypeFromBlockReturns =
        resolvedExplicitReturnType == nil &&
        expectedReturnType == nil &&
        {
          if case .blockExpression = body {
            return true
          }
          return false
        }()

      if inferReturnTypeFromBlockReturns {
        currentFunctionReturnType = nil
        inferredFunctionReturnType = nil
        isInferringFunctionReturnType = true
      } else {
        let lambdaReturnTypeForBodyCheck: Type = resolvedExplicitReturnType ?? expectedReturnType ?? .void
        currentFunctionReturnType = lambdaReturnTypeForBodyCheck
        inferredFunctionReturnType = nil
        isInferringFunctionReturnType = false
      }

      let bodyUsage: ExpressionUsage
      let bodyExpectedType: Type?
      if case .blockExpression = body {
        bodyUsage = .statement
        bodyExpectedType = nil
      } else {
        bodyUsage = .value
        bodyExpectedType = resolvedExplicitReturnType ?? expectedReturnType
      }

      let typedBody = try inferTypedExpression(body, expectedType: bodyExpectedType, usage: bodyUsage)
      
      // Determine return type
      let actualReturnType: Type
      if let explicitReturnType = resolvedExplicitReturnType {
        actualReturnType = explicitReturnType
        // Verify body type matches declared return type
        if typedBody.type != actualReturnType && typedBody.type != .never {
          throw SemanticError(.typeMismatch(expected: actualReturnType.description, got: typedBody.type.description), span: currentSpan)
        }
      } else if let expected = expectedReturnType {
        // If expected return type is a generic parameter, infer from body instead
        // This allows method-level type parameters to be inferred from lambda return types
        if case .genericParameter(_) = expected {
          actualReturnType = typedBody.type
        } else {
          actualReturnType = expected
          // Verify body type matches expected return type
          if typedBody.type != actualReturnType && typedBody.type != .never {
            throw SemanticError(.typeMismatch(expected: actualReturnType.description, got: typedBody.type.description), span: currentSpan)
          }
        }
      } else {
        if inferReturnTypeFromBlockReturns {
          actualReturnType = inferredFunctionReturnType ?? .void
        } else {
          // Infer return type from body
          actualReturnType = typedBody.type
        }
      }
      if actualReturnType.containsBorrowedReference {
        throw SemanticError(.generic("lambda return type cannot contain borrowed reference types: '\(actualReturnType)'"), span: currentSpan)
      }
      
      // Build function type
      let funcParams = typedParams.map { Parameter(type: $0.type, kind: .byVal) }
      let funcType = Type.function(parameters: funcParams, returns: actualReturnType)
      
      return .lambdaExpression(
        parameters: paramSymbols,
        captures: captures,
        body: typedBody,
        type: funcType
      )
    }
  }
  
  /// Analyzes captured variables in a lambda body.
  /// Only immutable variables can be captured.
  private func analyzeCapturedVariables(
    body: ExpressionNode,
    params: [(name: String, type: Type)]
  ) throws -> [CapturedVariable] {
    var captures: [CapturedVariable] = []
    let localNames = Set(params.map { $0.name })
    
    // Collect all variable references in the body
    try collectCapturedVariables(expr: body, localNames: localNames, captures: &captures)
    
    return captures
  }
  
  /// Recursively collects captured variables from an expression.
  private func collectCapturedVariables(
    expr: ExpressionNode,
    localNames: Set<String>,
    captures: inout [CapturedVariable]
  ) throws {
    switch expr {
    case .integerLiteral, .floatLiteral, .stringLiteral, .runeLiteral, .booleanLiteral, .genericInstantiation:
      return
    case .interpolatedString(let parts, _):
      for part in parts {
        if case .expression(let inner) = part {
          try collectCapturedVariables(expr: inner, localNames: localNames, captures: &captures)
        }
      }
      return
    case .identifier(let name):
      if localNames.contains(name) { return }
      
      // Look up the variable in scope with full info
      if let defId = currentScope.lookup(name, sourceFile: currentSourceFile),
         let info = currentScope.lookupWithInfo(name, sourceFile: currentSourceFile) {
        let kind = defIdMap.getSymbolKind(defId) ?? .variable(.Value)

        // Only variables should be captured.
        // Global functions/foreign declarations are referenced directly by name
        // and must not be materialized as closure environment fields.
        guard case .variable(_) = kind else { return }

        if info.type.containsBorrowedReference {
          throw SemanticError(.generic("Cannot capture borrowed reference value '\(name)'"), span: currentSpan)
        }

        // Avoid duplicates
        if !captures.contains(where: { $0.symbol.defId == defId }) {
          let captureKind: CaptureKind
          if info.mutable {
            // let mutable variables are captured by pointer so mutations are visible outside
            captureKind = .byMutReference
          } else if case .reference(_) = info.type {
            captureKind = .byReference
          } else {
            captureKind = .byValue
          }
          let symbol = Symbol(defId: defId, type: info.type, kind: kind)
          captures.append(CapturedVariable(symbol: symbol, captureKind: captureKind))
        }
      }
      
    case .blockExpression(let statements):
      var blockLocalNames = localNames
      for stmt in statements {
        switch stmt {
        case .variableDeclaration(let name, _, let value, _, _):
          try collectCapturedVariables(expr: value, localNames: blockLocalNames, captures: &captures)
          blockLocalNames.insert(name)
        case .pairVariableDeclaration(let first, let second, let value, _):
          try collectCapturedVariables(expr: value, localNames: blockLocalNames, captures: &captures)
          collectBindingElementName(first, into: &blockLocalNames)
          collectBindingElementName(second, into: &blockLocalNames)
        default:
          try collectCapturedVariablesFromStatement(stmt: stmt, localNames: blockLocalNames, captures: &captures)
        }
      }
      
    case .call(let callee, let arguments):
      try collectCapturedVariables(expr: callee, localNames: localNames, captures: &captures)
      for arg in arguments {
        if let expr = arg.expression {
          try collectCapturedVariables(expr: expr, localNames: localNames, captures: &captures)
        }
      }
      
    case .arithmeticExpression(let left, _, let right),
         .comparisonExpression(let left, _, let right),
         .bitwiseExpression(let left, _, let right),
         .andExpression(let left, let right),
         .orExpression(let left, let right):
      try collectCapturedVariables(expr: left, localNames: localNames, captures: &captures)
      try collectCapturedVariables(expr: right, localNames: localNames, captures: &captures)

    case .comparisonChainExpression(let operands, _, _):
      for operand in operands {
        try collectCapturedVariables(expr: operand, localNames: localNames, captures: &captures)
      }
      
    case .notExpression(let inner),
       .bitwiseNotExpression(let inner),
       .unaryMinusExpression(let inner),
       .addressOfExpression(let inner, _),
       .derefExpression(let inner),
       .unsafeDerefExpression(let inner),
        .ptrExpression(let inner, _):
      try collectCapturedVariables(expr: inner, localNames: localNames, captures: &captures)
      
    case .ifExpression(let condition, let thenBranch, let elseBranch):
      try collectCapturedVariables(expr: condition, localNames: localNames, captures: &captures)
      try collectCapturedVariables(expr: thenBranch, localNames: localNames, captures: &captures)
      if let elseBranch = elseBranch {
        try collectCapturedVariables(expr: elseBranch, localNames: localNames, captures: &captures)
      }
      
    case .whileExpression(let condition, let body):
      try collectCapturedVariables(expr: condition, localNames: localNames, captures: &captures)
      try collectCapturedVariables(expr: body, localNames: localNames, captures: &captures)
      
    case .memberPath(let base, _):
      try collectCapturedVariables(expr: base, localNames: localNames, captures: &captures)

    case .traitQualificationExpression(let base, _):
      try collectCapturedVariables(expr: base, localNames: localNames, captures: &captures)
      
    case .subscriptExpression(let base, let arguments):
      try collectCapturedVariables(expr: base, localNames: localNames, captures: &captures)
      for arg in arguments {
        try collectCapturedVariables(expr: arg, localNames: localNames, captures: &captures)
      }

    case .collectionLiteral(let elements, _):
      for element in elements {
        try collectCapturedVariables(expr: element, localNames: localNames, captures: &captures)
      }

    case .dictLiteral(let entries, _):
      for entry in entries {
        try collectCapturedVariables(expr: entry.key, localNames: localNames, captures: &captures)
        try collectCapturedVariables(expr: entry.value, localNames: localNames, captures: &captures)
      }

    case .emptyLiteral:
      break
      
    case .whenExpression(let subject, let cases, _):
      try collectCapturedVariables(expr: subject, localNames: localNames, captures: &captures)
      for c in cases {
        var caseLocalNames = localNames
        collectPatternBindingNames(c.pattern, into: &caseLocalNames)
        try collectCapturedVariables(expr: c.body, localNames: caseLocalNames, captures: &captures)
      }
      
    case .castExpression(_, let inner):
      try collectCapturedVariables(expr: inner, localNames: localNames, captures: &captures)
      
    case .staticMethodCall(_, _, _, let arguments):
      for arg in arguments {
        if let expr = arg.expression {
          try collectCapturedVariables(expr: expr, localNames: localNames, captures: &captures)
        }
      }
      
    case .forExpression(let pattern, let iterable, let body):
      try collectCapturedVariables(expr: iterable, localNames: localNames, captures: &captures)
      var bodyLocalNames = localNames
      collectBindingPatternNames(pattern, into: &bodyLocalNames)
      try collectCapturedVariables(expr: body, localNames: bodyLocalNames, captures: &captures)
      
    case .rangeExpression(_, let left, let right):
      if let left = left {
        try collectCapturedVariables(expr: left, localNames: localNames, captures: &captures)
      }
      if let right = right {
        try collectCapturedVariables(expr: right, localNames: localNames, captures: &captures)
      }
      
    case .isExpression(let subject, _, _):
      // Only collect captures from the subject expression.
      // Pattern variables are bindings, not captures.
      try collectCapturedVariables(expr: subject, localNames: localNames, captures: &captures)

    case .isNotExpression(let subject, _, _):
      // Only collect captures from the subject expression.
      // Pattern variables are bindings, not captures.
      try collectCapturedVariables(expr: subject, localNames: localNames, captures: &captures)
      
    case .lambdaExpression(let parameters, _, let body, _):
      var nestedLocalNames = localNames
      for parameter in parameters {
        nestedLocalNames.insert(parameter.name)
      }
      try collectCapturedVariables(expr: body, localNames: nestedLocalNames, captures: &captures)
      
    case .genericMethodCall(let base, _, _, let arguments):
      // Generic method call - collect from base and arguments
      try collectCapturedVariables(expr: base, localNames: localNames, captures: &captures)
      for arg in arguments {
        if let expr = arg.expression {
          try collectCapturedVariables(expr: expr, localNames: localNames, captures: &captures)
        }
      }

    case .qualifiedMethodCall(let base, _, _, let arguments):
      try collectCapturedVariables(expr: base, localNames: localNames, captures: &captures)
      for arg in arguments {
        if let expr = arg.expression {
          try collectCapturedVariables(expr: expr, localNames: localNames, captures: &captures)
        }
      }

    case .qualifiedGenericMethodCall(let base, _, _, _, let arguments):
      try collectCapturedVariables(expr: base, localNames: localNames, captures: &captures)
      for arg in arguments {
        if let expr = arg.expression {
          try collectCapturedVariables(expr: expr, localNames: localNames, captures: &captures)
        }
      }
      
    case .implicitMemberExpression(_, let arguments, _):
      // Implicit member expression - collect from arguments
      for arg in arguments {
        if let expr = arg.expression {
          try collectCapturedVariables(expr: expr, localNames: localNames, captures: &captures)
        }
      }

    case .orElseExpression(let operand, let defaultExpr, _):
      try collectCapturedVariables(expr: operand, localNames: localNames, captures: &captures)
      try collectCapturedVariables(expr: defaultExpr, localNames: localNames, captures: &captures)

    case .andThenExpression(let operand, let transformExpr, _):
      try collectCapturedVariables(expr: operand, localNames: localNames, captures: &captures)
      try collectCapturedVariables(expr: transformExpr, localNames: localNames, captures: &captures)

    case .orReturnExpression(let operand, _):
      try collectCapturedVariables(expr: operand, localNames: localNames, captures: &captures)
      
    }
  }

  private func collectBindingElementName(_ binding: PairBindingElement, into names: inout Set<String>) {
    guard !binding.isDiscard, binding.name != "_" else { return }
    names.insert(binding.name)
  }

  private func collectBindingPatternNames(_ pattern: BindingPatternNode, into names: inout Set<String>) {
    switch pattern {
    case .binding(let binding):
      collectBindingElementName(binding, into: &names)
    case .pair(let first, let second, _):
      collectBindingElementName(first, into: &names)
      collectBindingElementName(second, into: &names)
    }
  }

  private func collectPatternBindingNames(_ pattern: PatternNode, into names: inout Set<String>) {
    switch pattern {
    case .variable(let name, _, _):
      guard name != "_" else { return }
      names.insert(name)
    case .traitObjectTypeBinding(let name, _, _, _):
      guard name != "_" else { return }
      names.insert(name)
    case .enumCase(_, let elements, _), .structPattern(_, let elements, _):
      for element in elements {
        collectPatternBindingNames(element.pattern, into: &names)
      }
    case .andPattern(let left, let right, _), .orPattern(let left, let right, _):
      collectPatternBindingNames(left, into: &names)
      collectPatternBindingNames(right, into: &names)
    case .notPattern(let inner, _):
      collectPatternBindingNames(inner, into: &names)
    case .booleanLiteral, .integerLiteral, .negativeIntegerLiteral, .stringLiteral, .runeLiteral, .wildcard, .comparisonPattern, .traitObjectType:
      break
    }
  }
  
  /// Helper to collect captured variables from a statement.
  private func collectCapturedVariablesFromStatement(
    stmt: StatementNode,
    localNames: Set<String>,
    captures: inout [CapturedVariable]
  ) throws {
    switch stmt {
    case .variableDeclaration(_, _, let value, _, _):
      try collectCapturedVariables(expr: value, localNames: localNames, captures: &captures)
    case .pairVariableDeclaration(_, _, let value, _):
      try collectCapturedVariables(expr: value, localNames: localNames, captures: &captures)
    case .assignment(let target, _, let value, _):
      try collectCapturedVariables(expr: target, localNames: localNames, captures: &captures)
      try collectCapturedVariables(expr: value, localNames: localNames, captures: &captures)
    case .expression(let expr, _):
      try collectCapturedVariables(expr: expr, localNames: localNames, captures: &captures)
    case .return(let value, _):
      if let value = value {
        try collectCapturedVariables(expr: value, localNames: localNames, captures: &captures)
      }
    case .break:
      break
    case .yield(let value, _):
      try collectCapturedVariables(expr: value, localNames: localNames, captures: &captures)
    case .continue:
      break
    case .deferStatement(let expression, _):
      try collectCapturedVariables(expr: expression, localNames: localNames, captures: &captures)
    }
  }
}

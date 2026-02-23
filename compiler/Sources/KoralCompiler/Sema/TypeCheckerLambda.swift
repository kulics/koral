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
      defer { currentFunctionReturnType = savedFunctionReturnType }

      // Lambda has its own scope, so reset insideDefer flag.
      // This allows return/break/continue/defer inside a lambda that
      // appears within a defer expression.
      let savedInsideDefer = insideDefer
      insideDefer = false
      defer { insideDefer = savedInsideDefer }

      let resolvedExplicitReturnType = try returnType.map { try resolveTypeNode($0) }
      let lambdaReturnTypeForBodyCheck: Type = resolvedExplicitReturnType ?? expectedReturnType ?? .void
      currentFunctionReturnType = lambdaReturnTypeForBodyCheck

      let typedBody = try inferTypedExpression(body)
      
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
        // Infer return type from body
        actualReturnType = typedBody.type
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
    let paramNames = Set(params.map { $0.name })
    
    // Collect all variable references in the body
    try collectCapturedVariables(expr: body, paramNames: paramNames, captures: &captures)
    
    return captures
  }
  
  /// Recursively collects captured variables from an expression.
  private func collectCapturedVariables(
    expr: ExpressionNode,
    paramNames: Set<String>,
    captures: inout [CapturedVariable]
  ) throws {
    switch expr {
    case .integerLiteral, .floatLiteral, .stringLiteral, .booleanLiteral, .genericInstantiation:
      return
    case .interpolatedString(let parts, _):
      for part in parts {
        if case .expression(let inner) = part {
          try collectCapturedVariables(expr: inner, paramNames: paramNames, captures: &captures)
        }
      }
      return
    case .identifier(let name):
      // Skip if it's a parameter
      if paramNames.contains(name) { return }
      
      // Look up the variable in scope with full info
      if let defId = currentScope.lookup(name, sourceFile: currentSourceFile),
         let info = currentScope.lookupWithInfo(name, sourceFile: currentSourceFile) {
        let kind = defIdMap.getSymbolKind(defId) ?? .variable(.Value)

        // Only variables should be captured.
        // Global functions/foreign declarations are referenced directly by name
        // and must not be materialized as closure environment fields.
        guard case .variable(_) = kind else { return }

        // Check if it's mutable - only immutable variables can be captured
        if info.mutable {
          throw SemanticError(.generic("Cannot capture mutable variable '\(name)'"), span: currentSpan)
        }
        
        // Avoid duplicates
        if !captures.contains(where: { $0.symbol.defId == defId }) {
          let captureKind: CaptureKind
          if case .reference(_) = info.type {
            captureKind = .byReference
          } else {
            captureKind = .byValue
          }

          let methodKind = defIdMap.getSymbolMethodKind(defId) ?? .normal
          let symbol = Symbol(defId: defId, type: info.type, kind: kind, methodKind: methodKind)
          captures.append(CapturedVariable(symbol: symbol, captureKind: captureKind))
        }
      }
      
    case .blockExpression(let statements):
      for stmt in statements {
        try collectCapturedVariablesFromStatement(stmt: stmt, paramNames: paramNames, captures: &captures)
      }
      
    case .call(let callee, let arguments):
      try collectCapturedVariables(expr: callee, paramNames: paramNames, captures: &captures)
      for arg in arguments {
        try collectCapturedVariables(expr: arg, paramNames: paramNames, captures: &captures)
      }
      
    case .arithmeticExpression(let left, _, let right),
         .comparisonExpression(let left, _, let right),
         .bitwiseExpression(let left, _, let right),
         .andExpression(let left, let right),
         .orExpression(let left, let right):
      try collectCapturedVariables(expr: left, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: right, paramNames: paramNames, captures: &captures)
      
    case .notExpression(let inner),
       .bitwiseNotExpression(let inner),
       .unaryMinusExpression(let inner),
       .derefExpression(let inner),
        .refExpression(let inner),
        .ptrExpression(let inner),
        .deptrExpression(let inner):
      try collectCapturedVariables(expr: inner, paramNames: paramNames, captures: &captures)
      
    case .ifExpression(let condition, let thenBranch, let elseBranch):
      try collectCapturedVariables(expr: condition, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: thenBranch, paramNames: paramNames, captures: &captures)
      if let elseBranch = elseBranch {
        try collectCapturedVariables(expr: elseBranch, paramNames: paramNames, captures: &captures)
      }
      
    case .whileExpression(let condition, let body):
      try collectCapturedVariables(expr: condition, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: body, paramNames: paramNames, captures: &captures)
      
    case .letExpression(_, _, let value, _, let body):
      try collectCapturedVariables(expr: value, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: body, paramNames: paramNames, captures: &captures)
      
    case .memberPath(let base, _):
      try collectCapturedVariables(expr: base, paramNames: paramNames, captures: &captures)
      
    case .subscriptExpression(let base, let arguments):
      try collectCapturedVariables(expr: base, paramNames: paramNames, captures: &captures)
      for arg in arguments {
        try collectCapturedVariables(expr: arg, paramNames: paramNames, captures: &captures)
      }
      
    case .matchExpression(let subject, let cases, _):
      try collectCapturedVariables(expr: subject, paramNames: paramNames, captures: &captures)
      for c in cases {
        try collectCapturedVariables(expr: c.body, paramNames: paramNames, captures: &captures)
      }
      
    case .castExpression(_, let inner):
      try collectCapturedVariables(expr: inner, paramNames: paramNames, captures: &captures)
      
    case .staticMethodCall(_, _, _, let arguments):
      for arg in arguments {
        try collectCapturedVariables(expr: arg, paramNames: paramNames, captures: &captures)
      }
      
    case .forExpression(_, let iterable, let body):
      try collectCapturedVariables(expr: iterable, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: body, paramNames: paramNames, captures: &captures)
      
    case .rangeExpression(_, let left, let right):
      if let left = left {
        try collectCapturedVariables(expr: left, paramNames: paramNames, captures: &captures)
      }
      if let right = right {
        try collectCapturedVariables(expr: right, paramNames: paramNames, captures: &captures)
      }
      
    case .ifPatternExpression(let subject, _, let thenBranch, let elseBranch, _):
      try collectCapturedVariables(expr: subject, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: thenBranch, paramNames: paramNames, captures: &captures)
      if let elseBranch = elseBranch {
        try collectCapturedVariables(expr: elseBranch, paramNames: paramNames, captures: &captures)
      }
      
    case .whilePatternExpression(let subject, _, let body, _):
      try collectCapturedVariables(expr: subject, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: body, paramNames: paramNames, captures: &captures)
      
    case .lambdaExpression(_, _, let body, _):
      // Nested lambda - recursively collect captures
      try collectCapturedVariables(expr: body, paramNames: paramNames, captures: &captures)
      
    case .genericMethodCall(let base, _, _, let arguments):
      // Generic method call - collect from base and arguments
      try collectCapturedVariables(expr: base, paramNames: paramNames, captures: &captures)
      for arg in arguments {
        try collectCapturedVariables(expr: arg, paramNames: paramNames, captures: &captures)
      }
      
    case .implicitMemberExpression(_, let arguments, _):
      // Implicit member expression - collect from arguments
      for arg in arguments {
        try collectCapturedVariables(expr: arg, paramNames: paramNames, captures: &captures)
      }

    case .orElseExpression(let operand, let defaultExpr, _):
      try collectCapturedVariables(expr: operand, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: defaultExpr, paramNames: paramNames, captures: &captures)

    case .andThenExpression(let operand, let transformExpr, _):
      try collectCapturedVariables(expr: operand, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: transformExpr, paramNames: paramNames, captures: &captures)
      
    }
  }
  
  /// Helper to collect captured variables from a statement.
  private func collectCapturedVariablesFromStatement(
    stmt: StatementNode,
    paramNames: Set<String>,
    captures: inout [CapturedVariable]
  ) throws {
    switch stmt {
    case .variableDeclaration(_, _, let value, _, _):
      try collectCapturedVariables(expr: value, paramNames: paramNames, captures: &captures)
    case .assignment(let target, _, let value, _):
      try collectCapturedVariables(expr: target, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: value, paramNames: paramNames, captures: &captures)
    case .deptrAssignment(let pointer, _, let value, _):
      try collectCapturedVariables(expr: pointer, paramNames: paramNames, captures: &captures)
      try collectCapturedVariables(expr: value, paramNames: paramNames, captures: &captures)
    case .expression(let expr, _):
      try collectCapturedVariables(expr: expr, paramNames: paramNames, captures: &captures)
    case .return(let value, _):
      if let value = value {
        try collectCapturedVariables(expr: value, paramNames: paramNames, captures: &captures)
      }
    case .break, .continue:
      break
    case .`defer`(let expression, _):
      try collectCapturedVariables(expr: expression, paramNames: paramNames, captures: &captures)
    case .yield(let value, _):
      try collectCapturedVariables(expr: value, paramNames: paramNames, captures: &captures)
    }
  }
}

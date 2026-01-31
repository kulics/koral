import Foundation

// MARK: - Expression Type Inference Extension
// This extension contains methods for inferring types of expressions,
// including the main inferTypedExpression method and its helper methods.

extension TypeChecker {

  // MARK: - Duration Literal Helpers

  private func checkedMultiply(_ lhs: Int64, _ rhs: Int64, span: SourceSpan) throws -> Int64 {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    if overflow {
      throw SemanticError(.generic("Duration value too large"), line: span.start.line)
    }
    return result
  }

  private func normalizeDurationNanos(_ totalNanos: Int64) -> (secs: Int64, nanos: Int64) {
    let secs = totalNanos / 1_000_000_000
    let nanos = totalNanos % 1_000_000_000
    return (secs, nanos)
  }

  private func convertDurationLiteral(
    value: String,
    unit: DurationUnit,
    span: SourceSpan
  ) throws -> (secs: Int64, nanos: Int64) {
    guard let numValue = Int64(value) else {
      throw SemanticError(.generic("Invalid duration value: \(value)"), line: span.start.line)
    }
    if numValue < 0 {
      throw SemanticError(.generic("Duration cannot be negative"), line: span.start.line)
    }

    switch unit {
    case .nanoseconds:
      return normalizeDurationNanos(numValue)
    case .microseconds:
      let total = try checkedMultiply(numValue, 1_000, span: span)
      return normalizeDurationNanos(total)
    case .milliseconds:
      let total = try checkedMultiply(numValue, 1_000_000, span: span)
      return normalizeDurationNanos(total)
    case .seconds:
      return (numValue, 0)
    case .minutes:
      let secs = try checkedMultiply(numValue, 60, span: span)
      return (secs, 0)
    case .hours:
      let secs = try checkedMultiply(numValue, 3_600, span: span)
      return (secs, 0)
    case .days:
      let secs = try checkedMultiply(numValue, 86_400, span: span)
      return (secs, 0)
    }
  }

  private func checkDurationLiteral(
    value: String,
    unit: DurationUnit,
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    let (secs, nanos) = try convertDurationLiteral(value: value, unit: unit, span: span)

    guard let durationType = currentScope.lookupType("Duration")
      ?? currentScope.lookupType("Duration", sourceFile: currentSourceFile) else {
      throw SemanticError(.generic("Duration type not found. Import std.time or std.os."), line: span.start.line)
    }

    return .durationLiteral(secs: secs, nanos: nanos, type: durationType)
  }
  
  // MARK: - Main Expression Type Inference
  
  /// 新增用于返回带类型的表达式的类型推导函数
  func inferTypedExpression(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .castExpression(let typeNode, let innerExpr):
      let targetType = try resolveTypeNode(typeNode)
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

    case .integerLiteral(let value, let suffix):
      let type: Type
      if let suffix = suffix {
        if value.hasPrefix("-") {
          switch suffix {
          case .u, .u8, .u16, .u32, .u64:
            throw SemanticError(.generic("Negative integer literal cannot have unsigned suffix"), line: currentLine)
          default:
            break
          }
        }
        switch suffix {
        case .i: type = .int
        case .i8: type = .int8
        case .i16: type = .int16
        case .i32: type = .int32
        case .i64: type = .int64
        case .u: type = .uint
        case .u8: type = .uint8
        case .u16: type = .uint16
        case .u32: type = .uint32
        case .u64: type = .uint64
        case .f32, .f64:
          throw SemanticError.typeMismatch(expected: "integer suffix", got: suffix.rawValue)
        }
      } else {
        type = .int
      }
      return .integerLiteral(value: value, type: type)

    case .floatLiteral(let value, let suffix):
      let type: Type
      if let suffix = suffix {
        switch suffix {
        case .f32: type = .float32
        case .f64: type = .float64
        case .i, .i8, .i16, .i32, .i64, .u, .u8, .u16, .u32, .u64:
          throw SemanticError.typeMismatch(expected: "float suffix", got: suffix.rawValue)
        }
      } else {
        type = .float64
      }
      return .floatLiteral(value: value, type: type)

    case .durationLiteral(let value, let unit, let span):
      return try checkDurationLiteral(value: value, unit: unit, span: span)

    case .stringLiteral(let value):
      return .stringLiteral(value: value, type: builtinStringType())

    case .booleanLiteral(let value):
      return .booleanLiteral(value: value, type: .bool)

    case .matchExpression(let subject, let cases, _):
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
          let typedBody = try inferTypedExpression(c.body)
          if let rt = resultType {
            if typedBody.type != .never {
              if rt == .never {
                // Previous cases were all Never, this is the first concrete type
                resultType = typedBody.type
              } else if typedBody.type != rt {
                throw SemanticError.typeMismatch(
                  expected: rt.description, got: typedBody.type.description)
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
      let resolvedCases = resolveUnionCasesForExhaustiveness(subjectType)
      let checker = ExhaustivenessChecker(
        subjectType: subjectType,
        patterns: patterns,
        currentLine: currentLine,
        resolvedUnionCases: resolvedCases,
        context: context
      )
      try checker.check()
      
      return .matchExpression(subject: typedSubject, cases: typedCases, type: resultType ?? .void)

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
          throw SemanticError(.generic("'\(name)' is defined in module '\(modulePrefix)'. Use '\(modulePrefix).\(name)' to access it."), line: currentLine)
        }
      }
      
      let fallbackDefKind: DefKind = (!hasLocal && currentScope.isFunction(name, sourceFile: currentSourceFile)) ? .function : .variable
      let defId = currentScope.lookup(name, sourceFile: currentSourceFile) ?? defIdMap.allocate(
        modulePath: symbolModulePath,
        name: name,
        kind: fallbackDefKind,
        sourceFile: symbolSourceFile,
        access: info.isPrivate ? .private : .default,
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
          methodKind: .normal,
          isMutable: info.mutable
        )
      }

      let symbol = Symbol(
        defId: defId,
        type: info.type,
        kind: symbolKind,
        methodKind: .normal
      )
      
      return .variable(identifier: symbol)

    case .blockExpression(let statements, let finalExpression):
      return try withNewScope {
        var typedStatements: [TypedStatementNode] = []
        var blockType: Type = .void  // Default if no final expression
        var foundNever = false

        for stmt in statements {
          let typedStmt = try checkStatement(stmt)
          typedStatements.append(typedStmt)

          switch typedStmt {
          case .expression(let expr):
            if expr.type == .never {
              blockType = .never
              foundNever = true
            }
          case .return, .break, .continue:
            blockType = .never
            foundNever = true
          default:
            break
          }
        }

        if let finalExpr = finalExpression {
          let typedFinalExpr = try inferTypedExpression(finalExpr)
          // If we already found a Never statement, the block is Never regardless of final expr?
          // Actually, if a statement is Never, the final expression is unreachable.
          // For now, let's respect final expression type if reachable, or override if Never.
          if foundNever {
            // Block is forced to Never
            blockType = .never
          } else {
            blockType = typedFinalExpr.type
          }
          return .blockExpression(
            statements: typedStatements, finalExpression: typedFinalExpr,
            type: blockType)
        }

        if foundNever { blockType = .never }

        return .blockExpression(
          statements: typedStatements, finalExpression: nil, type: blockType)
      }

    case .arithmeticExpression(let left, let op, let right):
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

      let resultType = try checkArithmeticOp(op, typedLeft.type, typedRight.type)
      return .arithmeticExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

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

      // Allow single-byte ASCII string literals to coerce to UInt8 in comparisons.
      if typedLeft.type != typedRight.type {
        if typedLeft.type == .uint8 {
          typedRight = try coerceLiteral(typedRight, to: .uint8)
        }
        if typedRight.type == .uint8 {
          typedLeft = try coerceLiteral(typedLeft, to: .uint8)
        }
      }
      
      // Allow single-character string literals to coerce to Rune in comparisons.
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

      // Operator sugar for Equatable: lower `==`/`<>` to `__equals(self ref, other ref)`
      // for non-builtin scalar types (struct/union/String/generic parameters).
      if (op == .equal || op == .notEqual), typedLeft.type == typedRight.type,
        !isBuiltinEqualityComparable(typedLeft.type)
      {
        let eq = try buildEqualsCall(lhs: typedLeft, rhs: typedRight)
        if op == .notEqual {
          return .notExpression(expression: eq, type: .bool)
        }
        return eq
      }

      // Operator sugar for Comparable: lower `<`/`<=`/`>`/`>=` to
      // `__compare(self ref, other ref) Int` for non-builtin scalar types
      // (struct/union/String/generic parameters).
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

    case .letExpression(let name, let typeNode, let value, let mutable, let body):
      var typedValue = try inferTypedExpression(value)

      if let typeNode = typeNode {
        let type = try resolveTypeNode(typeNode)
        typedValue = try coerceLiteral(typedValue, to: type)
        if typedValue.type != type {
          throw SemanticError.typeMismatch(
            expected: type.description, got: typedValue.type.description)
        }
      }

      return try withNewScope {
        let symbol = makeLocalSymbol(
          name: name, type: typedValue.type, kind: .variable(mutable ? .MutableValue : .Value))
        try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)

        let typedBody = try inferTypedExpression(body)

        return .letExpression(
          identifier: symbol, value: typedValue, body: typedBody, type: typedBody.type)
      }

    case .ifExpression(let condition, let thenBranch, let elseBranch):
      let typedCondition = try inferTypedExpression(condition)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      let typedThen = try inferTypedExpression(thenBranch)

      if let elseExpr = elseBranch {
        let typedElse = try inferTypedExpression(elseExpr)

        let resultType: Type
        if typedThen.type == typedElse.type {
          resultType = typedThen.type
        } else if typedThen.type == .never {
          resultType = typedElse.type
        } else if typedElse.type == .never {
          resultType = typedThen.type
        } else {
          throw SemanticError.typeMismatch(
            expected: typedThen.type.description,
            got: typedElse.type.description
          )
        }

        return .ifExpression(
          condition: typedCondition, thenBranch: typedThen, elseBranch: typedElse,
          type: resultType)
      } else {
        return .ifExpression(
          condition: typedCondition, thenBranch: typedThen, elseBranch: nil, type: .void)
      }
      
    case .ifPatternExpression(let subject, let pattern, let thenBranch, let elseBranch, _):
      // Type check the subject expression
      let typedSubject = try inferTypedExpression(subject)
      
      // Check the pattern and collect variable bindings
      let (typedPattern, bindings) = try checkPattern(pattern, subjectType: typedSubject.type)
      
      // Type check the then branch with bindings in scope
      let typedThen = try withNewScope {
        for symbol in extractPatternSymbols(from: typedPattern) {
          if let name = context.getName(symbol.defId) {
            try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
          }
        }
        return try inferTypedExpression(thenBranch)
      }
      
      // Type check the else branch (without bindings)
      if let elseExpr = elseBranch {
        let typedElse = try inferTypedExpression(elseExpr)
        
        let resultType: Type
        if typedThen.type == typedElse.type {
          resultType = typedThen.type
        } else if typedThen.type == .never {
          resultType = typedElse.type
        } else if typedElse.type == .never {
          resultType = typedThen.type
        } else {
          throw SemanticError.typeMismatch(
            expected: typedThen.type.description,
            got: typedElse.type.description
          )
        }
        
        return .ifPatternExpression(
          subject: typedSubject,
          pattern: typedPattern,
          bindings: bindings,
          thenBranch: typedThen,
          elseBranch: typedElse,
          type: resultType
        )
      } else {
        return .ifPatternExpression(
          subject: typedSubject,
          pattern: typedPattern,
          bindings: bindings,
          thenBranch: typedThen,
          elseBranch: nil,
          type: .void
        )
      }

    case .whileExpression(let condition, let body):
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
      
    case .whilePatternExpression(let subject, let pattern, let body, _):
      // Type check the subject expression
      let typedSubject = try inferTypedExpression(subject)
      
      // Check the pattern and collect variable bindings
      let (typedPattern, bindings) = try checkPattern(pattern, subjectType: typedSubject.type)
      
      // Type check the body with bindings in scope
      loopDepth += 1
      defer { loopDepth -= 1 }
      
      let typedBody = try withNewScope {
        for symbol in extractPatternSymbols(from: typedPattern) {
          if let name = context.getName(symbol.defId) {
            try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
          }
        }
        return try inferTypedExpression(body)
      }
      
      return .whilePatternExpression(
        subject: typedSubject,
        pattern: typedPattern,
        bindings: bindings,
        body: typedBody,
        type: .void
      )

    case .call(let callee, let arguments):
      return try inferCallExpression(callee: callee, arguments: arguments)

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
        return .derefExpression(expression: typedInner, type: innerType)
      } else {
        throw SemanticError.typeMismatch(
          expected: "Reference type",
          got: typedInner.type.description
        )
      }

    case .refExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      // 禁止对引用再次取引用（仅单层）
      if case .reference(_) = typedInner.type {
        throw SemanticError.invalidOperation(
          op: "ref", type1: typedInner.type.description, type2: "")
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

    case .deptrExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      guard case .pointer(let element) = typedInner.type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }
      return .deptrExpression(expression: typedInner, type: element)

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
        arguments: arguments
      )

    case .memberPath(let baseExpr, let path):
      return try inferMemberPathExpression(baseExpr: baseExpr, path: path)

    case .staticMethodCall(let typeName, let typeArgs, let methodName, let arguments):
      return try inferStaticMethodCallExpression(
        typeName: typeName,
        typeArgs: typeArgs,
        methodName: methodName,
        arguments: arguments
      )

    case .forExpression(let pattern, let iterable, let body):
      return try inferForExpression(pattern: pattern, iterable: iterable, body: body)

    case .rangeExpression(let op, let left, let right):
      return try inferRangeExpression(operator: op, left: left, right: right)

    case .genericInstantiation(let base, _):
      throw SemanticError.invalidOperation(op: "use type as value", type1: base, type2: "")
      
    case .lambdaExpression(let parameters, let returnType, let body, _):
      return try inferLambdaExpression(parameters: parameters, returnType: returnType, body: body, expectedType: nil)
    }
  }
}


// MARK: - Call Expression Inference

extension TypeChecker {
  
  /// Infers the type of a call expression
  func inferCallExpression(callee: ExpressionNode, arguments: [ExpressionNode]) throws -> TypedExpressionNode {
    // Check if callee is a module-qualified static method call (e.g., module.Type.method())
    if case .memberPath(let baseExpr, let path) = callee,
       case .identifier(let moduleName) = baseExpr,
       path.count >= 2 {
      // Check if the base identifier is a module symbol
      if let moduleDefId = currentScope.lookup(moduleName, sourceFile: currentSourceFile),
        let moduleType = defIdMap.getSymbolType(moduleDefId),
        case .module(let moduleInfo) = moduleType {
        let typeName = path[0]
        let methodName = path[1]
        
        // Look up the type in the module's public types
        if let type = moduleInfo.publicTypes[typeName] {
          // Handle concrete struct types
          if case .structure(let defId) = type {
            let typeName = context.getName(defId) ?? ""
            // Look up static method on the struct using simple name (how extensionMethods is keyed)
            if let methods = extensionMethods[typeName], let methodSym = methods[methodName] {
              // Check if it's a static method (no self parameter or first param is not self)
              let isStatic: Bool
              if case .function(let params, _) = methodSym.type {
                isStatic = params.isEmpty || params[0].kind != PassKind.byRef
              } else {
                isStatic = true
              }
              
              if isStatic {
                if methodSym.methodKind != CompilerMethodKind.normal {
                  throw SemanticError(
                    .generic("compiler protocol method \(methodName) cannot be called explicitly"),
                    line: currentLine)
                }
                
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
                  arguments: typedArguments,
                  type: returnType
                )
              }
            }
          }
          
          // Handle concrete union types
          if case .union(let defId) = type {
            let unionCases = context.getUnionCases(defId) ?? []
            // Check if it's a union case constructor
            if let c = unionCases.first(where: { $0.name == methodName }) {
              let params = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
              
              if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                  function: "\(typeName).\(methodName)",
                  expected: params.count,
                  got: arguments.count
                )
              }
              
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
              
              return .unionConstruction(type: type, caseName: methodName, arguments: typedArgs)
            }
            
            // Look up static method on the union using simple name
            let unionName = context.getName(defId) ?? ""
            if let methods = extensionMethods[unionName], let methodSym = methods[methodName] {
              let isStatic: Bool
              if case .function(let params, _) = methodSym.type {
                isStatic = params.isEmpty || params[0].kind != PassKind.byRef
              } else {
                isStatic = true
              }
              
              if isStatic {
                if methodSym.methodKind != CompilerMethodKind.normal {
                  throw SemanticError(
                    .generic("compiler protocol method \(methodName) cannot be called explicitly"),
                    line: currentLine)
                }
                
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
                  arguments: typedArguments,
                  type: returnType
                )
              }
            }
          }
        }
        
        // Also try looking up the type from global scope (for types not yet in module's publicTypes)
        if let type = currentScope.lookupType(typeName) {
          if case .structure(let defId) = type {
            let name = context.getName(defId) ?? ""
            if let methods = extensionMethods[name], let methodSym = methods[methodName] {
              let isStatic: Bool
              if case .function(let params, _) = methodSym.type {
                isStatic = params.isEmpty || params[0].kind != PassKind.byRef
              } else {
                isStatic = true
              }
              
              if isStatic {
                if methodSym.methodKind != CompilerMethodKind.normal {
                  throw SemanticError(
                    .generic("compiler protocol method \(methodName) cannot be called explicitly"),
                    line: currentLine)
                }
                
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
              throw SemanticError(.generic("Expected function type for static trait method"), line: currentLine)
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
              if methodSym.methodKind != .normal {
                throw SemanticError(
                  .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                  line: currentLine)
              }
              
              // Get function parameters and return type
              guard case .function(let params, let returnType) = methodSym.type else {
                throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
                arguments: typedArguments,
                type: returnType
              )
            }
          }
        }
      }
      
      // Check if it's a generic union with a case constructor or static method
      if let template = currentScope.lookupGenericUnionTemplate(baseName) {
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
            kind: .unionType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Create parameterized type
        let baseType = Type.genericUnion(template: baseName, args: resolvedArgs)
        
        // Check if it's a union case constructor
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
          
          return .unionConstruction(type: baseType, caseName: memberName, arguments: typedArgs)
        }
        
        // Look up static method on generic union
        if let extensions = genericExtensionMethods[baseName] {
          if let ext = extensions.first(where: { $0.method.name == memberName }) {
            let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
            if isStatic {
              let methodSym = try resolveGenericExtensionMethod(
                baseType: baseType, templateName: baseName, typeArgs: resolvedArgs,
                methodInfo: ext)
              if methodSym.methodKind != .normal {
                throw SemanticError(
                  .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                  line: currentLine)
              }
              
              guard case .function(let params, let returnType) = methodSym.type else {
                throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
      return try inferGenericInstantiationCall(base: base, args: args, arguments: arguments)
    }

    // Resolve Callee (Check Union Constructor)
    var preResolvedCallee: TypedExpressionNode? = nil
    do {
      preResolvedCallee = try inferTypedExpression(callee)
    } catch is SemanticError {
      // Fallthrough
      preResolvedCallee = nil
    }

    if let resolved = preResolvedCallee, case .variable(let symbol) = resolved {
      if case .function(_, let returnType) = symbol.type {
        // Check for union constructor (both concrete and generic)
        var unionName: String? = nil
        if case .union(let defId) = returnType {
          unionName = context.getName(defId)
        } else if case .genericUnion(let templateName, _) = returnType {
          unionName = templateName
        }
        
        if let uName = unionName {
          // Check if symbol name is uName.CaseName
          let symbolName = context.getName(symbol.defId) ?? ""
          if symbolName.starts(with: uName + ".") {
            let caseName = String(symbolName.dropFirst(uName.count + 1))
            let params = symbol.type.functionParameters!

            if arguments.count != params.count {
              throw SemanticError.invalidArgumentCount(
                function: symbolName, expected: params.count, got: arguments.count)
            }

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

            return .unionConstruction(type: returnType, caseName: caseName, arguments: typedArgs)
          }
        }
      }
    }

    // Check if it is a constructor call OR implicit generic function call
    if case .identifier(let name) = callee {
      // 1. Try Generic Function Template (Implicit Inference)
      if let template = currentScope.lookupGenericFunctionTemplate(name) {
        return try inferImplicitGenericFunctionCall(template: template, name: name, arguments: arguments)
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

        if arguments.count != parameters.count {
          throw SemanticError.invalidArgumentCount(
            function: name,
            expected: parameters.count,
            got: arguments.count
          )
        }

        var typedArguments: [TypedExpressionNode] = []
        for (arg, expectedMember) in zip(arguments, parameters) {
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

        return .typeConstruction(
          identifier: makeLocalSymbol(name: name, type: type, kind: .type),
          typeArgs: nil,
          arguments: typedArguments,
          type: type
        )
      }
      
      // 2. Try Generic Struct/Union Template (Implicit Type Inference)
      // Only for identifiers starting with uppercase (type naming convention)
      // This allows writing Stream(iter) instead of [T, R]Stream(iter)
      if let firstChar = name.first, firstChar.isUppercase {
        // Try generic struct template
        if let template = currentScope.lookupGenericStructTemplate(name) {
          return try inferGenericStructConstruction(template: template, name: name, arguments: arguments)
        }
        
        // Try generic union template (for union case constructors without dot notation)
        // Note: This is less common since union cases are usually accessed via .CaseName
      }
    }

    // Special handling for intrinsic function calls (alloc_memory, etc.)
    if case .identifier(let name) = callee {
      if let intrinsicNode = try checkIntrinsicCall(name: name, arguments: arguments) {
        return intrinsicNode
      }
    }

    let typedCallee = try inferTypedExpression(callee)

    // Secondary guard: if the resolved callee is a special compiler method, block explicit calls
    if case .variable(let sym) = typedCallee, sym.methodKind != CompilerMethodKind.normal {
      let symName = context.getName(sym.defId) ?? "<unknown>"
      throw SemanticError.invalidOperation(
        op: "Explicit call to \(symName) is not allowed", type1: "", type2: "")
    }

    // Method call
    if case .methodReference(let base, let method, _, _, let methodType) = typedCallee {
      return try inferMethodCall(base: base, method: method, methodType: methodType, arguments: arguments)
    }

    // Trait method placeholder call (for trait methods on generic parameters)
    if case .traitMethodPlaceholder(let traitName, let methodName, let base, let methodTypeArgs, let methodType) = typedCallee {
      // For trait method placeholders, we need to handle the call similarly to method calls
      // The base is already included in the placeholder, so we just need to type-check the arguments
      guard case .function(let params, let returns) = methodType else {
        throw SemanticError.invalidOperation(op: "call", type1: methodType.description, type2: "")
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
        } else {
          typedArg = try inferTypedExpression(arg)
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
          typedArg = try inferTypedExpression(arg)
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
  func inferGenericInstantiationCall(base: String, args: [TypeNode], arguments: [ExpressionNode]) throws -> TypedExpressionNode {
    if let template = currentScope.lookupGenericStructTemplate(base) {
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
        let countExpr = try inferTypedExpression(arguments[0])
        if countExpr.type != .int {
          throw SemanticError.typeMismatch(expected: "Int", got: countExpr.type.description)
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

      if base == "offset_ptr" {
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
        guard case .pointer = ptrExpr.type else {
          throw SemanticError(.generic("cannot dereference non-pointer type"))
        }
        let offsetExpr = try inferTypedExpression(arguments[1])
        if offsetExpr.type != .int {
          throw SemanticError.typeMismatch(expected: "Int", got: offsetExpr.type.description)
        }
        return .intrinsicCall(.offsetPtr(ptr: ptrExpr, offset: offsetExpr))
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
      throw SemanticError.undefinedType(base)
    }
  }
  
  /// Infers the type of an implicit generic function call (type arguments inferred from arguments)
  func inferImplicitGenericFunctionCall(template: GenericFunctionTemplate, name: String, arguments: [ExpressionNode]) throws -> TypedExpressionNode {
    if name == "null_ptr" && arguments.isEmpty {
      return .intrinsicCall(.nullPtr(resultType: .pointer(element: .void)))
    }

    var inferred: [String: Type] = [:]

    if arguments.count != template.parameters.count {
      throw SemanticError.invalidArgumentCount(
        function: name,
        expected: template.parameters.count,
        got: arguments.count
      )
    }

    var typedArguments: [TypedExpressionNode] = []
    for (argExpr, param) in zip(arguments, template.parameters) {
      var typedArg = try inferTypedExpression(argExpr)
      do {
        let expectedType = try resolveTypeNode(param.type)
        typedArg = try coerceLiteral(typedArg, to: expectedType)
      } catch let error as SemanticError {
        // During implicit generic inference, parameter types may reference template
        // type parameters (e.g. `T`, `[T]Pointer`) which are not in the caller scope.
        // Skip literal coercion in that case; we'll infer `T` via unify().
        if case .undefinedType(let name) = error.kind,
          template.typeParameters.contains(where: { $0.name == name })
        {
          // no-op
        } else {
          throw error
        }
      }
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
    for (typedArg, expectedType) in zip(typedArguments, resolvedParams) {
      let coerced = try coerceLiteral(typedArg, to: expectedType)
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
    if templateName == "offset_ptr" {
      guard case .pointer = typedArguments[0].type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }
      if typedArguments[1].type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: typedArguments[1].type.description)
      }
      return .intrinsicCall(.offsetPtr(ptr: typedArguments[0], offset: typedArguments[1]))
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
  func inferMethodCall(base: TypedExpressionNode, method: Symbol, methodType: Type, arguments: [ExpressionNode]) throws -> TypedExpressionNode {
    let methodName = context.getName(method.defId) ?? "<unknown>"
    if case .function(let params, let returns) = method.type {
      if arguments.count != params.count - 1 {
        throw SemanticError.invalidArgumentCount(
          function: methodName,
          expected: params.count - 1,
          got: arguments.count
        )
      }

      // Check base type against first param
      // 如果 base 是 rvalue 且方法期望 self ref，使用临时物化
      if let firstParam = params.first,
         case .reference(let inner) = firstParam.type,
         inner == base.type,
         base.valueCategory == .rvalue {
        // 右值临时物化：将方法调用包装在 letExpression 中
        return try materializeTemporaryForMethodCall(
          base: base,
          method: method,
          methodType: methodType,
          params: params,
          returns: returns,
          arguments: arguments
        )
      }
      
      var finalBase = base
      if let firstParam = params.first {
        if base.type != firstParam.type {
          // 尝试自动取引用：期望 T ref，实际是 T
          if case .reference(let inner) = firstParam.type, inner == base.type {
            if base.valueCategory == .lvalue {
              finalBase = .referenceExpression(expression: base, type: firstParam.type)
            } else {
              // 这个分支不应该被执行，因为上面已经处理了 rvalue 的情况
              throw SemanticError.invalidOperation(
                op: "implicit ref", type1: base.type.description, type2: "rvalue")
            }
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
          // For Range expressions (especially FullRange), pass the expected type for type inference
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
          typedArg = try inferTypedExpression(arg)
          typedArg = try coerceLiteral(typedArg, to: param.type)
          
          // If param type contains generic parameters, unify to infer them
          if context.containsGenericParameter(param.type) {
            _ = unifyTypes(param.type, typedArg.type, bindings: &methodTypeParamBindings)
          } else if typedArg.type != param.type {
            // Try implicit ref/deref for arguments as well (mirrors self handling).
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
        // Extract method type args in order from the function type
        // The order is determined by the order of first appearance in the function type
        let paramNames = extractGenericParameterNames(from: method.type)
        let baseTypeParamNames = extractGenericParameterNames(from: finalBase.type)
        // Filter out type parameters that belong to the base type (type-level parameters)
        let methodLevelParamNames = paramNames.filter { !baseTypeParamNames.contains($0) }
        let collectedMethodTypeArgs = methodLevelParamNames.compactMap { name -> Type? in
          if let bound = methodTypeParamBindings[name] {
            return bound
          }
          if let existingType = currentScope.lookupType(name),
             case .genericParameter(let existingName) = existingType,
             existingName == name {
            return existingType
          }
          return nil
        }
        if !methodLevelParamNames.isEmpty && collectedMethodTypeArgs.count == methodLevelParamNames.count {
          inferredMethodTypeArgs = collectedMethodTypeArgs
        } else {
          inferredMethodTypeArgs = nil
        }
      }
      
      // Create final callee with inferred method type args
      let finalCallee: TypedExpressionNode = .methodReference(
        base: finalBase, method: method, typeArgs: nil, methodTypeArgs: inferredMethodTypeArgs, type: methodType)

      // Lower primitive `__equals(self, other)` to direct scalar comparison.
      if method.methodKind == .equals,
        returns == .bool,
        params.count == 2,
        params[0].type == params[1].type,
        isBuiltinEqualityComparable(params[0].type)
      {
        return .comparisonExpression(left: finalBase, op: .equal, right: typedArguments[0], type: .bool)
      }

      // Lower primitive `__compare(self, other) Int` to scalar comparisons.
      if method.methodKind == .compare,
        returns == .int,
        params.count == 2,
        params[0].type == params[1].type,
        isBuiltinOrderingComparable(params[0].type)
      {
        let lhsVal = finalBase
        let rhsVal = typedArguments[0]

        let less: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .less, right: rhsVal, type: .bool)
        let greater: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .greater, right: rhsVal, type: .bool)
        let minusOne: TypedExpressionNode = .integerLiteral(value: "-1", type: .int)
        let plusOne: TypedExpressionNode = .integerLiteral(value: "1", type: .int)
        let zero: TypedExpressionNode = .integerLiteral(value: "0", type: .int)

        let gtBranch: TypedExpressionNode = .ifExpression(condition: greater, thenBranch: plusOne, elseBranch: zero, type: .int)
        return .ifExpression(condition: less, thenBranch: minusOne, elseBranch: gtBranch, type: .int)
      }

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
    
    guard case .function(let params, let returns) = methodResult.methodType else {
      throw SemanticError(.generic("Expected function type for method \(methodName)"), line: currentLine)
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
          if typedBase.valueCategory == .lvalue {
            finalBase = .referenceExpression(expression: typedBase, type: firstParam.type)
          } else {
            // Rvalue temporary materialization
            return try materializeTemporaryForGenericMethodCall(
              base: typedBase,
              method: methodResult.methodSymbol,
              methodType: methodResult.methodType,
              methodTypeArgs: resolvedMethodTypeArgs,
              typeArgs: methodResult.typeArgs,
              params: params,
              returns: returns,
              arguments: arguments,
              traitName: methodResult.traitName
            )
          }
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
      let methodName = context.getName(methodResult.methodSymbol.defId) ?? "<unknown>"
      finalCallee = .traitMethodPlaceholder(
        traitName: traitName,
        methodName: methodName,
        base: finalBase,
        methodTypeArgs: resolvedMethodTypeArgs,
        type: methodResult.methodType
      )
    } else {
      finalCallee = .methodReference(
        base: finalBase,
        method: methodResult.methodSymbol,
        typeArgs: methodResult.typeArgs,
        methodTypeArgs: resolvedMethodTypeArgs,
        type: methodResult.methodType
      )
    }
    
    return .call(callee: finalCallee, arguments: typedArguments, type: returns)
  }
}


// MARK: - Member Path Expression Inference

extension TypeChecker {
  
  /// Infers the type of a member path expression (e.g., obj.field or Type.method)
  func inferMemberPathExpression(baseExpr: ExpressionNode, path: [String]) throws -> TypedExpressionNode {
    // 1. Check if baseExpr is a Type (Generic Instantiation) for static method access or Union Constructor
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
        if path.count == 1 {
          let memberName = path[0]
          // Look up the member in the module's public symbols
          if let memberSymbol = moduleInfo.publicSymbols[memberName] {
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
                methodKind: .normal,
                isMutable: false
              )
            }
            let typeSymbol = Symbol(
              defId: defId,
              type: memberType,
              kind: .type,
              methodKind: .normal
            )
            return .variable(identifier: typeSymbol)
          }
          throw SemanticError.undefinedMember(memberName, name)
        } else if path.count >= 2 {
          // Handle module.Type.method() or module.Type.field
          let typeName = path[0]
          let remainingPath = Array(path.dropFirst())
          
          // First, try to find the type in the module's public types
          if let memberType = moduleInfo.publicTypes[typeName] {
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

    // 4. Union Constructor Access via member path (e.g., UnionType.CaseName)
    if case .identifier(let name) = baseExpr, let type = currentScope.lookupType(name) {
      if path.count == 1 {
        let memberName = path[0]
        if case .union(let defId) = type {
          if let c = context.getUnionCases(defId)?.first(where: { $0.name == memberName }) {
            let paramTypes = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
            let funcType = Type.function(parameters: paramTypes, returns: type)
            let symbol = makeLocalSymbol(name: "\(name).\(memberName)", type: funcType, kind: .function)
            return .variable(identifier: symbol)
          }
        }
      }
    }
    
    // 5. Generic Union Constructor Access with type inference from return type context
    // e.g., Result.Ok(x) when return type is [T, E]Result
    if case .identifier(let name) = baseExpr,
       let template = currentScope.lookupGenericUnionTemplate(name),
       path.count == 1 {
      let memberName = path[0]
      
      // Try to infer type arguments from currentFunctionReturnType
      if let returnType = currentFunctionReturnType,
         case .genericUnion(let templateName, let typeArgs) = returnType,
         templateName == name {
        // We have a matching return type context, use its type arguments
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: typeArgs)
        
        // Record instantiation request for deferred monomorphization
        if !typeArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .unionType(template: template, args: typeArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        let type = Type.genericUnion(template: name, args: typeArgs)
        
        // Create type substitution map
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = typeArgs[i]
        }
        
        // Check if it's a union case constructor
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
    return .memberPath(source: typedBase, path: typedPath)
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
              if methodSym.methodKind != .normal {
                throw SemanticError(
                  .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                  line: currentLine)
              }
              return .variable(identifier: methodSym)
            }
          }
        }
      }
    } else if let template = currentScope.lookupGenericUnionTemplate(baseName) {
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
          kind: .unionType(template: template, args: resolvedArgs),
          sourceLine: currentLine,
          sourceFileName: currentFileName
        ))
      }
      
      let type = Type.genericUnion(template: baseName, args: resolvedArgs)

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
        if method.methodKind != .normal {
          throw SemanticError(
            .generic("compiler protocol method \(memberName) cannot be called explicitly"),
            line: currentLine)
        }
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
    case .union(let defId):
      typeName = context.getName(defId) ?? typeToLookup.description
    default:
      typeName = typeToLookup.description
    }
    if let methods = extensionMethods[typeName], let methodSym = methods[memberName] {
      if methodSym.methodKind != .normal {
        throw SemanticError(
          .generic("compiler protocol method \(memberName) cannot be called explicitly"),
          line: currentLine)
      }
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
            let methodSym = try resolveIntrinsicExtensionMethod(
              baseType: typeToLookup,
              templateName: "Ptr",
              typeArgs: [element],
              methodInfo: ext
            )
            if methodSym.methodKind != .normal {
              throw SemanticError(
                .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                line: currentLine)
            }
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
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: "Ptr",
              typeArgs: [element],
              methodInfo: ext
            )
            if methodSym.methodKind != .normal {
              throw SemanticError(
                .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                line: currentLine)
            }
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
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: templateName,
              typeArgs: typeArgs,
              methodInfo: ext
            )
            if methodSym.methodKind != .normal {
              throw SemanticError(
                .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                line: currentLine)
            }
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
    
    // Handle genericUnion types
    if case .genericUnion(let templateName, let typeArgs) = typeToLookup {
      if let extensions = genericExtensionMethods[templateName] {
        for ext in extensions {
          if ext.method.name == memberName {
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: templateName,
              typeArgs: typeArgs,
              methodInfo: ext
            )
            if methodSym.methodKind != .normal {
              throw SemanticError(
                .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                line: currentLine)
            }
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
          
          // Check if this is a compiler protocol method that cannot be called explicitly
          let methodKind = getCompilerMethodKind(memberName)
          if methodKind != .normal {
            throw SemanticError(
              .generic("compiler protocol method \(memberName) cannot be called explicitly"),
              line: currentLine)
          }

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
    
    // Check if it's a generic union
    if let template = currentScope.lookupGenericUnionTemplate(typeName) {
      return try inferGenericUnionStaticMethodCall(
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
    guard template.typeParameters.count == resolvedTypeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(template.typeParameters.count) generic arguments",
        got: "\(resolvedTypeArgs.count)"
      )
    }
    
    try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedTypeArgs)
    
    if !resolvedTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
      recordInstantiation(InstantiationRequest(
        kind: .structType(template: template, args: resolvedTypeArgs),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    let baseType = Type.genericStruct(template: typeName, args: resolvedTypeArgs)
    
    if let extensions = genericExtensionMethods[typeName] {
      if let ext = extensions.first(where: { $0.method.name == methodName }) {
        let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
        if isStatic {
          let methodSym = try resolveGenericExtensionMethod(
            baseType: baseType, templateName: typeName, typeArgs: resolvedTypeArgs,
            methodInfo: ext)
          if methodSym.methodKind != .normal {
            throw SemanticError(
              .generic("compiler protocol method \(methodName) cannot be called explicitly"),
              line: currentLine)
          }
          
          guard case .function(let params, let returnType) = methodSym.type else {
            throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
            typeArgs: resolvedTypeArgs,
            arguments: typedArguments,
            type: returnType
          )
        }
      }
    }
    
    throw SemanticError.undefinedMember(methodName, typeName)
  }
  
  private func inferGenericUnionStaticMethodCall(
    template: GenericUnionTemplate,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    guard template.typeParameters.count == resolvedTypeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(template.typeParameters.count) generic arguments",
        got: "\(resolvedTypeArgs.count)"
      )
    }
    
    try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedTypeArgs)
    
    if !resolvedTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
      recordInstantiation(InstantiationRequest(
        kind: .unionType(template: template, args: resolvedTypeArgs),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    let baseType = Type.genericUnion(template: typeName, args: resolvedTypeArgs)
    
    if let extensions = genericExtensionMethods[typeName] {
      if let ext = extensions.first(where: { $0.method.name == methodName }) {
        let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
        if isStatic {
          let methodSym = try resolveGenericExtensionMethod(
            baseType: baseType, templateName: typeName, typeArgs: resolvedTypeArgs,
            methodInfo: ext)
          if methodSym.methodKind != .normal {
            throw SemanticError(
              .generic("compiler protocol method \(methodName) cannot be called explicitly"),
              line: currentLine)
          }
          
          guard case .function(let params, let returnType) = methodSym.type else {
            throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
            typeArgs: resolvedTypeArgs,
            arguments: typedArguments,
            type: returnType
          )
        }
      }
    }
    
    throw SemanticError.undefinedMember(methodName, typeName)
  }
  
  private func inferConcreteTypeStaticMethodCall(
    type: Type,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    if !resolvedTypeArgs.isEmpty {
      throw SemanticError(.generic("Type \(typeName) is not generic"), line: currentLine)
    }
    
    let lookupTypeName: String
    switch type {
    case .structure(let defId):
      lookupTypeName = context.getName(defId) ?? ""
    case .union(let defId):
      lookupTypeName = context.getName(defId) ?? ""
    default:
      lookupTypeName = type.description
    }
    
    if let methods = extensionMethods[lookupTypeName], let methodSym = methods[methodName] {
      if methodSym.methodKind != .normal {
        throw SemanticError(
          .generic("compiler protocol method \(methodName) cannot be called explicitly"),
          line: currentLine)
      }
      
      guard case .function(let params, let returnType) = methodSym.type else {
        throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
        arguments: typedArguments,
        type: returnType
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
              throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
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
              arguments: typedArguments,
              type: returnType
            )
          }
        }
      }
    }
    
    throw SemanticError.undefinedMember(methodName, typeName)
  }
}


// MARK: - Expression Helper Methods (moved from TypeChecker.swift)

extension TypeChecker {
  
  /// Builds an equality comparison call for types implementing Equatable
  func buildEqualsCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    let methodName = "__equals"
    let receiverType = lhs.type

    // Handle generic parameter case - create trait method placeholder
    if case .genericParameter(let paramName) = receiverType {
      guard hasTraitBound(paramName, "Equatable") else {
        throw SemanticError(.generic("Type \(receiverType) is not constrained by trait Equatable"), line: currentLine)
      }
      let methods = try flattenedTraitMethods("Equatable")
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait Equatable is missing required method \(methodName)"), line: currentLine)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)
      
      recordTraitPlaceholderInstantiation(
        baseType: receiverType,
        methodName: methodName,
        methodTypeArgs: []
      )
      
      // Create trait method placeholder instead of methodReference with __trait_ prefix
      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: "Equatable",
        methodName: methodName,
        base: lhs,
        methodTypeArgs: [],
        type: expectedType
      )
      return .call(callee: callee, arguments: [rhs], type: .bool)
    }
    
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

  /// Builds a comparison call for types implementing Comparable
  func buildCompareCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    let methodName = "__compare"
    let receiverType = lhs.type

    // Handle generic parameter case - create trait method placeholder
    if case .genericParameter(let paramName) = receiverType {
      guard hasTraitBound(paramName, "Comparable") else {
        throw SemanticError(.generic("Type \(receiverType) is not constrained by trait Comparable"), line: currentLine)
      }
      let methods = try flattenedTraitMethods("Comparable")
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait Comparable is missing required method \(methodName)"), line: currentLine)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)
      
      recordTraitPlaceholderInstantiation(
        baseType: receiverType,
        methodName: methodName,
        methodTypeArgs: []
      )
      
      // Create trait method placeholder instead of methodReference with __trait_ prefix
      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: "Comparable",
        methodName: methodName,
        base: lhs,
        methodTypeArgs: [],
        type: expectedType
      )
      return .call(callee: callee, arguments: [rhs], type: .int)
    }
    
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
      let methodKind = defIdMap.getSymbolMethodKind(defId) ?? .normal
      let symbol = Symbol(defId: defId, type: type, kind: kind, methodKind: methodKind)
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

      // Now resolve path members on typedBase.
      var currentType = typedBase.type
      var resolvedPath: [Symbol] = []

      for memberName in path {
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

          if !member.mutable {
            throw SemanticError.assignToImmutable(memberName)
          }

          resolvedPath.append(
            makeLocalSymbol(name: member.name, type: member.type, kind: .variable(.MutableValue)))
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
          
          if !param.mutable {
            throw SemanticError.assignToImmutable(memberName)
          }
          
          // Resolve member type with substitution
          let memberType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(param.type)
          }
          
          resolvedPath.append(
            makeLocalSymbol(name: param.name, type: memberType, kind: .variable(.MutableValue)))
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
      // Direct assignment to `x[i]` is lowered to `__update_at` in statement checking.
      // Treat subscript as an invalid assignment target here.
      throw SemanticError.invalidOperation(op: "assignment target", type1: "subscript", type2: "")

    case .derefExpression(_):
      // `deref r = ...` is intentionally disallowed.
      // Writes must go through explicit setters like `__update_at` (for subscripts).
      throw SemanticError.invalidOperation(op: "assignment target", type1: "deref", type2: "")

    default:
      throw SemanticError.invalidOperation(
        op: "assignment target", type1: String(describing: expr), type2: "")
    }
  }

  private func isLiteralExpression(_ expr: ExpressionNode) -> Bool {
    switch expr {
    case .integerLiteral, .floatLiteral, .durationLiteral, .stringLiteral, .booleanLiteral:
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
}


// MARK: - Range Expression Type Checking

extension TypeChecker {
  
  /// Type checks a range expression and desugars it to Range union construction.
  /// Range expressions like `a..b` are desugared to `[T]Range.ClosedRange(a, b)`
  func inferRangeExpression(
    operator op: RangeOperator,
    left: ExpressionNode?,
    right: ExpressionNode?,
    expectedType: Type? = nil
  ) throws -> TypedExpressionNode {
    // 1. Type check operands
    let typedLeft = left != nil ? try inferTypedExpression(left!) : nil
    let typedRight = right != nil ? try inferTypedExpression(right!) : nil
    
    // 2. Determine element type T
    let elementType: Type
    if let l = typedLeft {
      elementType = l.type
      // If both operands exist, verify they have the same type
      if let r = typedRight {
        if l.type != r.type {
          throw SemanticError(.typeMismatch(expected: l.type.description, got: r.type.description), line: currentLine)
        }
      }
    } else if let r = typedRight {
      elementType = r.type
    } else {
      // FullRange with no operands - try to infer from expected type
      if let expected = expectedType,
         case .genericUnion(let template, let args) = expected,
         template == "Range",
         args.count == 1 {
        elementType = args[0]
      } else {
        throw SemanticError(.generic("FullRange requires type annotation or context type"), line: currentLine)
      }
    }
    
    // 3. Verify T implements Comparable
    try enforceTraitConformance(elementType, traitName: "Comparable")
    
    // 4. Construct Range type
    let rangeType = Type.genericUnion(template: "Range", args: [elementType])
    
    // 5. Determine case name and arguments
    let caseName: String
    let args: [TypedExpressionNode]
    
    switch op {
    case .closed:
      caseName = "ClosedRange"
      args = [typedLeft!, typedRight!]
    case .closedOpen:
      caseName = "ClosedOpenRange"
      args = [typedLeft!, typedRight!]
    case .openClosed:
      caseName = "OpenClosedRange"
      args = [typedLeft!, typedRight!]
    case .open:
      caseName = "OpenRange"
      args = [typedLeft!, typedRight!]
    case .from:
      caseName = "FromRange"
      args = [typedLeft!]
    case .fromOpen:
      caseName = "FromOpenRange"
      args = [typedLeft!]
    case .to:
      caseName = "ToRange"
      args = [typedRight!]
    case .toOpen:
      caseName = "ToOpenRange"
      args = [typedRight!]
    case .full:
      caseName = "FullRange"
      args = []
    }
    
    // 6. Return union construction expression
    return .unionConstruction(type: rangeType, caseName: caseName, arguments: args)
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
      ), line: currentLine)
    }
    
    // 4. Get the iterator type from the method's return type
    guard case .function(_, let iteratorType) = iteratorMethod.type else {
      throw SemanticError(.generic("iterator() must be a function"), line: currentLine)
    }
    
    // 5. Extract the element type from the iterator
    let elementType = try extractIteratorElementType(iteratorType)
    
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
      ), line: currentLine)
    }
    
    // Verify the return type is [T]Option
    guard case .function(_, let returnType) = nextMethod.type else {
      throw SemanticError(.generic("Iterator.next() must be a function"), line: currentLine)
    }
    
    // Check if return type is Option<T>
    switch returnType {
    case .genericUnion(let template, let args) where template == "Option" && args.count == 1:
      return args[0]
    default:
      throw SemanticError(.generic(
        "Iterator.next() must return [T]Option, got \(returnType)"
      ), line: currentLine)
    }
  }

  /// Checks that the for loop pattern is exhaustive for the element type.
  private func checkForLoopPatternExhaustiveness(pattern: PatternNode, elementType: Type) throws {
    // For simple variable bindings and wildcards, they are always exhaustive
    switch pattern {
    case .variable, .wildcard:
      return
    case .unionCase:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive for element type \(elementType). Use a simple variable binding."
      ), line: currentLine)
    case .booleanLiteral, .integerLiteral, .stringLiteral, .negativeIntegerLiteral:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Literal patterns are not exhaustive."
      ), line: currentLine)
    case .comparisonPattern:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Comparison patterns are not exhaustive."
      ), line: currentLine)
    case .andPattern, .orPattern, .notPattern:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Pattern combinators are not exhaustive."
      ), line: currentLine)
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
      let matchExpr = try buildForLoopMatchExpression(
        nextCall: nextCall,
        pattern: pattern,
        elementType: elementType,
        body: body
      )
      
      // Build: while true then match
      loopDepth += 1
      let whileExpr = TypedExpressionNode.whileExpression(
        condition: .booleanLiteral(value: true, type: .bool),
        body: matchExpr,
        type: .void
      )
      loopDepth -= 1
      
      // Build: let mut __iter = iterator() then while ...
      return .letExpression(
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
      throw SemanticError(.generic("iterator() method not found"), line: currentLine)
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
      throw SemanticError(.generic("Expected reference to iterator"), line: currentLine)
    }
    
    // Look up the next method
    guard let nextMethod = try lookupConcreteMethodSymbol(on: iteratorType, name: "next") else {
      throw SemanticError(.generic("next() method not found"), line: currentLine)
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
    let optionType = Type.genericUnion(template: "Option", args: [elementType])
    
    // Build call
    return .call(callee: methodRef, arguments: [], type: optionType)
  }

  /// Builds the match expression for the for loop body.
  func buildForLoopMatchExpression(
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
    let nonePattern = TypedPattern.unionCase(caseName: "None", tagIndex: 0, elements: [])
    let breakExpr = TypedExpressionNode.blockExpression(
      statements: [.break],
      finalExpression: nil,
      type: .void
    )
    
    // Build match cases
    let someCase = TypedMatchCase(pattern: somePattern, body: typedBody)
    let noneCase = TypedMatchCase(pattern: nonePattern, body: breakExpr)
    
    return .matchExpression(
      subject: nextCall,
      cases: [someCase, noneCase],
      type: .void
    )
  }

  /// Builds the Some pattern wrapping the user's pattern.
  func buildSomePattern(userPattern: PatternNode, elementType: Type) throws -> TypedPattern {
    let innerPattern = try convertPatternToTypedPattern(userPattern, expectedType: elementType)
    // Some has tag index 1 (None is 0, Some is 1 in Option)
    return .unionCase(caseName: "Some", tagIndex: 1, elements: [innerPattern])
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
    case .integerLiteral(let value, _, _):
      return .integerLiteral(value: value)
    case .negativeIntegerLiteral(let value, _, _):
      return .integerLiteral(value: "-\(value)")
    case .stringLiteral(let value, _):
      return .stringLiteral(value: value)
    case .unionCase(let caseName, let elements, _):
      let typedElements = try elements.map { elem -> TypedPattern in
        try convertPatternToTypedPattern(elem, expectedType: .void)
      }
      return .unionCase(caseName: caseName, tagIndex: 0, elements: typedElements)
    case .comparisonPattern(let op, let value, _, _):
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
    case .wildcard, .booleanLiteral, .integerLiteral, .stringLiteral, .negativeIntegerLiteral:
      break
    case .unionCase(_, let elements, _):
      for elem in elements {
        try bindPatternVariables(pattern: elem, type: .void)
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
}

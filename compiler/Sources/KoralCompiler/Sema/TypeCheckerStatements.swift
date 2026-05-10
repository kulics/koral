import Foundation

// MARK: - Statement Type Checking Extension
// This extension contains methods for checking statements and producing typed statements.

extension TypeChecker {

  func statementCanFallThrough(_ stmt: TypedStatementNode) -> Bool {
    switch stmt {
    case .return, .break, .continue, .yield:
      return false
    case .expression(let expr):
      return expr.type != .never
    case .ifStatement(_, let thenBranch, let elseBranch):
      guard let elseBranch else { return true }
      return thenBranch.type != .never || elseBranch.type != .never
    case .ifPatternStatement(_, _, _, let thenBranch, let elseBranch):
      guard let elseBranch else { return true }
      return thenBranch.type != .never || elseBranch.type != .never
    case .whenStatement(_, let cases):
      return cases.contains { $0.body.type != .never }
    case .whileStatement, .whilePatternStatement:
      return true
    case .variableDeclaration, .pairVariableDeclaration, .assignment, .finally:
      return true
    }
  }

  func statementTerminatorName(_ stmt: TypedStatementNode) -> String? {
    switch stmt {
    case .return:
      return "return"
    case .break:
      return "break"
    case .continue:
      return "continue"
    case .yield:
      return "yield"
    case .expression(let expr):
      return expr.type == .never ? "control flow terminator" : nil
    case .ifStatement, .ifPatternStatement, .whenStatement:
      return statementCanFallThrough(stmt) ? nil : "control flow terminator"
    default:
      return nil
    }
  }

  private func inferStatementBodyExpression(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .ifExpression, .whenExpression, .whileExpression, .forExpression:
      let stmt = try inferStatementExpression(expr)
      let blockType: Type = statementCanFallThrough(stmt) ? .void : .never
      return .blockExpression(statements: [stmt], type: blockType)
    default:
      return try inferTypedExpression(expr, usage: .statement)
    }
  }

  func inferStatementExpression(_ expr: ExpressionNode) throws -> TypedStatementNode {
    switch expr {
    case .ifExpression(let condition, let thenBranch, let elseBranch):
      if let lowered = try lowerIfConditionWithBindings(
        condition: condition,
        thenBranch: thenBranch,
        elseBranch: elseBranch,
        expectedType: nil,
        usage: .statement
      ) {
        return .expression(lowered)
      }

      let typedCondition = autoDereferenceValueContext(try inferTypedExpression(condition))
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      let typedThen = try inferStatementBodyExpression(thenBranch)
      let typedElse = try elseBranch.map { try inferStatementBodyExpression($0) }
      return .ifStatement(condition: typedCondition, thenBranch: typedThen, elseBranch: typedElse)

    case .whenExpression(let subject, let cases, _):
      let typedSubject = try inferTypedExpression(subject)
      var subjectType = typedSubject.type
      if case .reference(let inner) = subjectType {
        subjectType = inner
      }

      var typedCases: [TypedStatementMatchCase] = []
      for c in cases {
        let (pattern, _) = try withNewScope {
          try checkPattern(c.pattern, subjectType: subjectType)
        }

        let typedBody = try withNewScope {
          for symbol in extractPatternSymbols(from: pattern) {
            if let name = context.getName(symbol.defId) {
              try currentScope.defineLocal(name, defId: symbol.defId, line: currentLine)
            }
          }
          return try inferStatementBodyExpression(c.body)
        }
        typedCases.append(TypedStatementMatchCase(pattern: pattern, body: typedBody))
      }

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
      return .whenStatement(subject: typedSubject, cases: typedCases)

    case .whileExpression(let condition, let body):
      if let lowered = try lowerWhileConditionWithBindings(
        condition: condition,
        body: body
      ) {
        return lowered
      }

      let typedCondition = autoDereferenceValueContext(try inferTypedExpression(condition))
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      loopDepth += 1
      defer { loopDepth -= 1 }
      let typedBody = try inferStatementBodyExpression(body)
      return .whileStatement(condition: typedCondition, body: typedBody)

    case .forExpression:
      return .expression(try inferTypedExpression(expr, usage: .statement))

    default:
      return .expression(try inferTypedExpression(expr, usage: .statement))
    }
  }

  /// For subscript assignment targets, recursively infer base expressions in writable context.
  ///
  /// If the base itself is a subscript expression, lower it through `mut_ref_at` and keep
  /// the result as `T mut ref` so chained writes like `a[i][j] = v` remain writable.
  private func inferWritableSubscriptBase(_ baseExpr: ExpressionNode) throws -> TypedExpressionNode {
    if case .subscriptExpression(let outerBaseExpr, let outerArgExprs) = baseExpr {
      let typedOuterBase = try inferWritableSubscriptBase(outerBaseExpr)
      var typedOuterArgs = try outerArgExprs.map { try inferTypedExpression($0) }

      let (resolvedMethod, _, _) = try resolveSubscriptUpdateMethod(
        base: typedOuterBase, args: typedOuterArgs)

      if case .function(let params, _) = resolvedMethod.type {
        let indexParams = Array(params.dropFirst())
        for i in 0..<typedOuterArgs.count {
          typedOuterArgs[i] = try coerceLiteral(typedOuterArgs[i], to: indexParams[i].type)
        }
      }

      let (updateMethod, finalBase, valueType) = try resolveSubscriptUpdateMethod(
        base: typedOuterBase, args: typedOuterArgs)

      let callee: TypedExpressionNode = .methodReference(
        base: finalBase,
        method: updateMethod,
        typeArgs: nil,
        methodTypeArgs: nil,
        type: updateMethod.type
      )

      return .call(
        callee: callee,
        arguments: typedOuterArgs,
        type: .mutableReference(inner: valueType)
      )
    }

    return try inferTypedExpression(baseExpr)
  }

  // 新增用于返回带类型的语句的检查函数
  func checkStatement(_ stmt: StatementNode) throws -> TypedStatementNode {
    do {
      return try checkStatementInternal(stmt)
    } catch let e as SemanticError {
      throw e
    }
  }

  private func checkStatementInternal(_ stmt: StatementNode) throws -> TypedStatementNode {
    switch stmt {
    case .variableDeclaration(let name, let typeNode, let value, let mutable, let span):
      self.currentSpan = span
      
      // For Lambda expressions, pass the expected type for type inference
      var typedValue: TypedExpressionNode
      var expectedType: Type? = nil
      
      if let typeNode = typeNode {
        expectedType = try resolveTypeNode(typeNode)
      }
      
      // Check if value is a Lambda expression and pass expected type
      if case .lambdaExpression(let parameters, let returnType, let body, _) = value {
        typedValue = try inferLambdaExpression(
          parameters: parameters,
          returnType: returnType,
          body: body,
          expectedType: expectedType
        )
      } else {
        // Pass expected type for implicit member expression support
        typedValue = try inferTypedExpression(value, expectedType: expectedType)
      }

      if expectedType == nil, case .identifier("self") = value {
        typedValue = autoDereferenceValueContext(typedValue)
      }
      
      let type: Type
      if let expectedType = expectedType {
        type = expectedType
        typedValue = try coerceLiteral(typedValue, to: type)
        if typedValue.type != .never && typedValue.type != type {
          throw SemanticError.typeMismatch(
            expected: type.description, got: typedValue.type.description)
        }
      } else {
        type = typedValue.type
      }

      try assertNotOpaqueType(type, span: span)

      let symbol = makeLocalSymbol(
        name: name,
        type: type,
        kind: mutable ? .variable(.MutableValue) : .variable(.Value)
      )
      try currentScope.defineLocal(name, defId: symbol.defId, line: currentSpan.line)
      return .variableDeclaration(
        identifier: symbol,
        value: typedValue,
        mutable: mutable
      )

    case .pairVariableDeclaration(let first, let second, let value, let span):
      self.currentSpan = span

      // Type-check the value expression
      let typedValue = try inferTypedExpression(value)
      let valueType = typedValue.type

      // Verify the value is a Pair type
      guard case .genericStruct(let templateName, let typeArgs) = valueType,
            templateName == "Pair",
            typeArgs.count == 2 else {
        throw SemanticError(.typeMismatch(
          expected: "Pair", got: valueType.description))
      }

      let firstType = typeArgs[0]
      let secondType = typeArgs[1]

      // Create a synthetic symbol for the temporary pair variable
      let pairSymbol = nextSynthSymbol(prefix: "pair_tmp", type: valueType)

      // Create member symbols for .first and .second field access
      let firstMemberSym = makeLocalSymbol(
        name: "first", type: firstType, kind: .variable(.Value))
      let secondMemberSym = makeLocalSymbol(
        name: "second", type: secondType, kind: .variable(.Value))

      // Create symbols for the user-visible bindings (if not discarded)
      var firstSymbol: Symbol? = nil
      if !first.isDiscard {
        // Validate type annotation if present
        if let typeNode = first.type {
          let annotatedType = try resolveTypeNode(typeNode)
          if annotatedType != firstType {
            throw SemanticError(.typeMismatch(
              expected: annotatedType.description, got: firstType.description))
          }
        }
        let sym = makeLocalSymbol(
          name: first.name,
          type: firstType,
          kind: first.mutable ? .variable(.MutableValue) : .variable(.Value)
        )
        try currentScope.defineLocal(first.name, defId: sym.defId, line: span.line)
        firstSymbol = sym
      }

      var secondSymbol: Symbol? = nil
      if !second.isDiscard {
        // Validate type annotation if present
        if let typeNode = second.type {
          let annotatedType = try resolveTypeNode(typeNode)
          if annotatedType != secondType {
            throw SemanticError(.typeMismatch(
              expected: annotatedType.description, got: secondType.description))
          }
        }
        let sym = makeLocalSymbol(
          name: second.name,
          type: secondType,
          kind: second.mutable ? .variable(.MutableValue) : .variable(.Value)
        )
        try currentScope.defineLocal(second.name, defId: sym.defId, line: span.line)
        secondSymbol = sym
      }

      return .pairVariableDeclaration(
        pairSymbol: pairSymbol, pairValue: typedValue,
        firstSymbol: firstSymbol, firstMember: firstMemberSym, firstMutable: first.mutable,
        secondSymbol: secondSymbol, secondMember: secondMemberSym, secondMutable: second.mutable
      )

    case .assignment(let target, let op, let value, let span):
      self.currentSpan = span
      if let op {
        // Lower `x[i] op= v` into a write through `x.mut_ref_at(i)`.
        if case .subscriptExpression(let baseExpr, let argExprs) = target {
          let typedBase = try inferWritableSubscriptBase(baseExpr)
          let typedArgs = try argExprs.map { try inferTypedExpression($0) }

          // Built-in pointer subscript compound assignment: ptr[i] op= v → deref (ptr + i) = deref (ptr + i) op v
          let baseStructType: Type
          if case .reference(let inner) = typedBase.type {
            baseStructType = inner
          } else if case .mutableReference(let inner) = typedBase.type {
            baseStructType = inner
          } else {
            baseStructType = typedBase.type
          }
          if case .pointer = baseStructType {
            throw SemanticError(.generic(
              "Cannot assign through read-only pointer of type '\(baseStructType)'"
            ), span: span)
          }
          if case .mutablePointer(let element) = baseStructType {
            guard typedArgs.count == 1 else {
              throw SemanticError.invalidArgumentCount(function: "pointer subscript", expected: 1, got: typedArgs.count)
            }
            var index = typedArgs[0]
            index = try coerceLiteral(index, to: .uint)
            if index.type != .uint {
              throw SemanticError.typeMismatch(expected: "UInt", got: index.type.description)
            }
            let ptrExpr: TypedExpressionNode
            if case .reference = typedBase.type {
              ptrExpr = .derefExpression(expression: typedBase, type: baseStructType)
            } else if case .mutableReference = typedBase.type {
              ptrExpr = .derefExpression(expression: typedBase, type: baseStructType)
            } else {
              ptrExpr = typedBase
            }
            let offsetExpr: TypedExpressionNode = .arithmeticExpression(
              left: ptrExpr, op: .plus, right: index, type: baseStructType)
            let derefTarget: TypedExpressionNode = .derefExpression(expression: offsetExpr, type: element)

            var typedRhs = try inferTypedExpression(value)
            typedRhs = try coerceLiteral(typedRhs, to: element)
            if typedRhs.type != .never && typedRhs.type != element {
              throw SemanticError.typeMismatch(expected: element.description, got: typedRhs.type.description)
            }

            if let arithmeticOp = compoundOpToArithmeticOp(op) {
              let newValue = try buildArithmeticExpression(op: arithmeticOp, lhs: derefTarget, rhs: typedRhs)
              return .assignment(target: derefTarget, operator: nil, value: newValue)
            } else if let _ = compoundOpToBitwiseOp(op) {
              if !isIntegerScalarType(element) || element != typedRhs.type {
                throw SemanticError.typeMismatch(
                  expected: "Matching Integer Types", got: "\(element) \(op) \(typedRhs.type)")
              }
              return .assignment(target: derefTarget, operator: op, value: typedRhs)
            } else {
              fatalError("Unknown compound assignment operator")
            }
          }

          // Evaluate base (by reference), args once.
          let baseStoredExpr: TypedExpressionNode
          let baseStoredType: Type
          switch typedBase.type {
          case .reference, .mutableReference:
            baseStoredExpr = typedBase
            baseStoredType = typedBase.type
          default:
            if typedBase.valueCategory != .lvalue {
              throw SemanticError.invalidOperation(
                op: "implicit ref", type1: typedBase.type.description, type2: "rvalue")
            }
            let baseRefType: Type = canTakeMutableReference(to: typedBase)
              ? .mutableReference(inner: typedBase.type)
              : .reference(inner: typedBase.type)
            baseStoredExpr = .referenceExpression(expression: typedBase, type: baseRefType)
            baseStoredType = baseRefType
          }
          let baseSym = nextSynthSymbol(prefix: "sub_base", type: baseStoredType)
          var stmts: [TypedStatementNode] = [
            .variableDeclaration(identifier: baseSym, value: baseStoredExpr, mutable: false)
          ]

          var argSyms: [Symbol] = []
          for a in typedArgs {
            let s = nextSynthSymbol(prefix: "sub_idx", type: a.type)
            argSyms.append(s)
            stmts.append(.variableDeclaration(identifier: s, value: a, mutable: false))
          }

          let baseVar: TypedExpressionNode = .variable(identifier: baseSym)
          let argVars: [TypedExpressionNode] = argSyms.map { .variable(identifier: $0) }
          let readRef = try resolveSubscriptReference(base: baseVar, args: argVars)

          let elementType: Type
          let oldValueExpr: TypedExpressionNode
          if case .reference(let inner) = readRef.type {
            elementType = inner
            oldValueExpr = .derefExpression(expression: readRef, type: inner)
          } else {
            elementType = readRef.type
            oldValueExpr = readRef
          }
          let oldSym = nextSynthSymbol(prefix: "sub_old", type: elementType)
          stmts.append(.variableDeclaration(identifier: oldSym, value: oldValueExpr, mutable: false))

          var typedRhs = try inferTypedExpression(value)
          typedRhs = try coerceLiteral(typedRhs, to: elementType)
          if typedRhs.type != .never && typedRhs.type != elementType {
            throw SemanticError.typeMismatch(
              expected: elementType.description, got: typedRhs.type.description)
          }

          let rhsSym = nextSynthSymbol(prefix: "sub_rhs", type: typedRhs.type)
          stmts.append(.variableDeclaration(identifier: rhsSym, value: typedRhs, mutable: false))

          let newValueExpr: TypedExpressionNode
          if let arithmeticOp = compoundOpToArithmeticOp(op) {
            newValueExpr = try buildArithmeticExpression(
              op: arithmeticOp,
              lhs: .variable(identifier: oldSym),
              rhs: .variable(identifier: rhsSym)
            )
            if newValueExpr.type != elementType {
              throw SemanticError.typeMismatch(
                expected: elementType.description, got: newValueExpr.type.description)
            }
          } else if let bitwiseOp = compoundOpToBitwiseOp(op) {
            if !isIntegerScalarType(elementType) || elementType != typedRhs.type {
              throw SemanticError.typeMismatch(
                expected: "Matching Integer Types", got: "\(elementType) \(op) \(typedRhs.type)")
            }
            newValueExpr = .bitwiseExpression(
              left: .variable(identifier: oldSym),
              op: bitwiseOp,
              right: .variable(identifier: rhsSym),
              type: elementType
            )
          } else {
            fatalError("Unknown compound assignment operator")
          }

          let (updateMethod, finalBase, expectedValueType) = try resolveSubscriptUpdateMethod(
            base: baseVar, args: argVars)
          if expectedValueType != elementType {
            throw SemanticError.typeMismatch(
              expected: expectedValueType.description, got: elementType.description)
          }
          let callee: TypedExpressionNode = .methodReference(
            base: finalBase, method: updateMethod, typeArgs: nil, methodTypeArgs: nil, type: updateMethod.type)
          let callExpr: TypedExpressionNode = .call(
            callee: callee,
            arguments: argVars,
            type: .mutableReference(inner: expectedValueType)
          )
          let writeTarget: TypedExpressionNode = .derefExpression(
            expression: callExpr,
            type: expectedValueType
          )
          stmts.append(.assignment(target: writeTarget, operator: nil, value: newValueExpr))

          return .expression(.blockExpression(statements: stmts, type: .void))
        }

        let typedTarget = try resolveLValue(target)
        // Pass expected type for implicit member expression support
        var typedValue = try inferTypedExpression(value, expectedType: typedTarget.type)
        typedValue = try coerceLiteral(typedValue, to: typedTarget.type)

        if typedValue.type != .never && typedTarget.type != typedValue.type {
          throw SemanticError.typeMismatch(
            expected: typedTarget.type.description, got: typedValue.type.description)
        }

        if let arithmeticOp = compoundOpToArithmeticOp(op) {
          let newValueExpr = try buildArithmeticExpression(
            op: arithmeticOp,
            lhs: typedTarget,
            rhs: typedValue
          )
          if newValueExpr.type != typedTarget.type {
            throw SemanticError.typeMismatch(
              expected: typedTarget.type.description, got: newValueExpr.type.description)
          }
          return .assignment(target: typedTarget, operator: nil, value: newValueExpr)
        } else if let _ = compoundOpToBitwiseOp(op) {
          if !isIntegerScalarType(typedTarget.type) || typedTarget.type != typedValue.type {
            throw SemanticError.typeMismatch(
              expected: "Matching Integer Types", got: "\(typedTarget.type) \(op) \(typedValue.type)")
          }
        } else {
          fatalError("Unknown compound assignment operator")
        }

        return .assignment(target: typedTarget, operator: op, value: typedValue)
      }

      // Simple assignment
      // Lower `x[i] = v` into a write through `x.mut_ref_at(i)`.
      if case .subscriptExpression(let baseExpr, let argExprs) = target {
        let typedBase = try inferWritableSubscriptBase(baseExpr)
        let typedArgs = try argExprs.map { try inferTypedExpression($0) }

        // Built-in pointer subscript assignment: ptr[i] = v → deref (ptr + i) = v
        let baseStructType: Type
        if case .reference(let inner) = typedBase.type {
          baseStructType = inner
        } else if case .mutableReference(let inner) = typedBase.type {
          baseStructType = inner
        } else {
          baseStructType = typedBase.type
        }
        if case .pointer = baseStructType {
          throw SemanticError(.generic(
            "Cannot assign through read-only pointer of type '\(baseStructType)'"
          ), span: span)
        }
          if case .mutablePointer(let element) = baseStructType {
            guard typedArgs.count == 1 else {
              throw SemanticError.invalidArgumentCount(function: "pointer subscript", expected: 1, got: typedArgs.count)
            }
          var index = typedArgs[0]
          index = try coerceLiteral(index, to: .uint)
          if index.type != .uint {
            throw SemanticError.typeMismatch(expected: "UInt", got: index.type.description)
          }
          let ptrExpr: TypedExpressionNode
          if case .reference = typedBase.type {
            ptrExpr = .derefExpression(expression: typedBase, type: baseStructType)
          } else if case .mutableReference = typedBase.type {
            ptrExpr = .derefExpression(expression: typedBase, type: baseStructType)
          } else {
            ptrExpr = typedBase
          }
          let offsetExpr: TypedExpressionNode = .arithmeticExpression(
            left: ptrExpr, op: .plus, right: index, type: baseStructType)
          let derefTarget: TypedExpressionNode = .derefExpression(expression: offsetExpr, type: element)

          var typedValue = try inferTypedExpression(value)
          typedValue = try coerceLiteral(typedValue, to: element)
          if typedValue.type != .never && typedValue.type != element {
            throw SemanticError.typeMismatch(expected: element.description, got: typedValue.type.description)
          }
          return .assignment(target: derefTarget, operator: nil, value: typedValue)
        }

        // Resolve expected value type from `mut_ref_at`.
        let (resolvedMethod, _, expectedValueType) = try resolveSubscriptUpdateMethod(
          base: typedBase, args: typedArgs)

        // Coerce index arguments to match mut_ref_at parameter types
        var coercedArgs = typedArgs
        if case .function(let params, _) = resolvedMethod.type {
          let indexParams = Array(params.dropFirst())
          for i in 0..<coercedArgs.count {
            coercedArgs[i] = try coerceLiteral(coercedArgs[i], to: indexParams[i].type)
          }
        }

        // Evaluate base (by reference), args, rhs once.
        let baseStoredExpr: TypedExpressionNode
        let baseStoredType: Type
        switch typedBase.type {
        case .reference, .mutableReference:
          baseStoredExpr = typedBase
          baseStoredType = typedBase.type
        default:
          if typedBase.valueCategory != .lvalue {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedBase.type.description, type2: "rvalue")
          }
          let baseRefType: Type = canTakeMutableReference(to: typedBase)
            ? .mutableReference(inner: typedBase.type)
            : .reference(inner: typedBase.type)
          baseStoredExpr = .referenceExpression(expression: typedBase, type: baseRefType)
          baseStoredType = baseRefType
        }
        let baseSym = nextSynthSymbol(prefix: "sub_base", type: baseStoredType)
        var stmts: [TypedStatementNode] = [
          .variableDeclaration(identifier: baseSym, value: baseStoredExpr, mutable: false)
        ]

        var argSyms: [Symbol] = []
        for a in coercedArgs {
          let s = nextSynthSymbol(prefix: "sub_idx", type: a.type)
          argSyms.append(s)
          stmts.append(.variableDeclaration(identifier: s, value: a, mutable: false))
        }

        var typedValue = try inferTypedExpression(value)
        typedValue = try coerceLiteral(typedValue, to: expectedValueType)
        if typedValue.type != .never && typedValue.type != expectedValueType {
          throw SemanticError.typeMismatch(
            expected: expectedValueType.description, got: typedValue.type.description)
        }
        let valSym = nextSynthSymbol(prefix: "sub_val", type: typedValue.type)
        stmts.append(.variableDeclaration(identifier: valSym, value: typedValue, mutable: false))

        let baseVar: TypedExpressionNode = .variable(identifier: baseSym)
        let argVars: [TypedExpressionNode] = argSyms.map { .variable(identifier: $0) }
        let (updateMethod, finalBase, _) = try resolveSubscriptUpdateMethod(
          base: baseVar, args: argVars)

        let callee: TypedExpressionNode = .methodReference(
          base: finalBase,
          method: updateMethod,
          typeArgs: nil,
          methodTypeArgs: nil,
          type: updateMethod.type
        )
        let callExpr: TypedExpressionNode = .call(
          callee: callee,
          arguments: argVars,
          type: .mutableReference(inner: expectedValueType)
        )
        let writeTarget: TypedExpressionNode = .derefExpression(
          expression: callExpr,
          type: expectedValueType
        )
        stmts.append(.assignment(target: writeTarget, operator: nil, value: .variable(identifier: valSym)))

        return .expression(.blockExpression(statements: stmts, type: .void))
      }

      let typedTarget = try resolveLValue(target)
      // Pass expected type for implicit member expression support
      var typedValue = try inferTypedExpression(value, expectedType: typedTarget.type)
      typedValue = try coerceLiteral(typedValue, to: typedTarget.type)

      if typedValue.type != .never && typedTarget.type != typedValue.type {
        throw SemanticError.typeMismatch(
          expected: typedTarget.type.description, got: typedValue.type.description)
      }

      return .assignment(target: typedTarget, operator: nil, value: typedValue)

    case .expression(let expr, let span):
      self.currentSpan = span
      return try inferStatementExpression(expr)

    case .return(let value, let span):
      self.currentSpan = span
      if insideFinally {
        throw SemanticError(.generic(
          "control flow statement 'return' is not allowed in finally expression"))
      }
      guard let returnType = currentFunctionReturnType else {
        if isInferringFunctionReturnType {
          if let value = value {
            let expectedType = inferredFunctionReturnType
            var typedValue = try inferTypedExpression(value, expectedType: expectedType)
            if let expectedType {
              typedValue = try coerceLiteral(typedValue, to: expectedType)
              if typedValue.type != .never && typedValue.type != expectedType {
                throw SemanticError.typeMismatch(
                  expected: expectedType.description, got: typedValue.type.description)
              }
            } else if typedValue.type != .never {
              inferredFunctionReturnType = typedValue.type
            }
            return .return(value: typedValue)
          }

          if let inferredFunctionReturnType, inferredFunctionReturnType != .void {
            throw SemanticError.typeMismatch(
              expected: inferredFunctionReturnType.description, got: "Void")
          }
          inferredFunctionReturnType = .void
          return .return(value: nil)
        }
        throw SemanticError.invalidOperation(op: "return outside of function", type1: "", type2: "")
      }

      if let value = value {
        if returnType == .void {
          throw SemanticError.typeMismatch(expected: "Void", got: "non-Void")
        }

        // Pass expected type for implicit member expression support
        var typedValue = try inferTypedExpression(value, expectedType: returnType)
        typedValue = try coerceLiteral(typedValue, to: returnType)
        if typedValue.type != .never && typedValue.type != returnType {
          throw SemanticError.typeMismatch(
            expected: returnType.description, got: typedValue.type.description)
        }
        return .return(value: typedValue)
      }

      if returnType != .void {
        throw SemanticError.typeMismatch(expected: returnType.description, got: "Void")
      }
      return .return(value: nil)

    case .break(let span):
      self.currentSpan = span
      if insideFinally {
        throw SemanticError(.generic(
          "control flow statement 'break' is not allowed in finally expression"))
      }
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "break outside of while", type1: "", type2: "")
      }
      return .break

    case .continue(let span):
      self.currentSpan = span
      if insideFinally {
        throw SemanticError(.generic(
          "control flow statement 'continue' is not allowed in finally expression"))
      }
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "continue outside of while", type1: "", type2: "")
      }
      return .continue

    case .finally(let expression, let span):
      self.currentSpan = span
      if insideFinally {
        throw SemanticError(.generic(
          "finally statement is not allowed inside finally expression"))
      }
      let previousInsideFinally = insideFinally
      insideFinally = true
      defer { insideFinally = previousInsideFinally }
      let typedExpr = try inferTypedExpression(expression, usage: .statement)
      return .finally(expression: typedExpr)

    case .yield(let value, let span):
      self.currentSpan = span
      if insideFinally {
        throw SemanticError(.generic(
          "control flow statement 'yield' is not allowed in finally expression"))
      }
      if let currentTarget = yieldTargets.last {
        let candidateExpectedTypes = [currentTarget.preferredType, currentTarget.resultType].compactMap { $0 }
        var typedValueOpt: TypedExpressionNode?
        for expectedType in candidateExpectedTypes {
          do {
            typedValueOpt = try normalizeBranchExpression(
              try inferTypedExpression(value, expectedType: expectedType),
              expectedType: expectedType
            )
            break
          } catch {
            continue
          }
        }
        let typedValue: TypedExpressionNode
        if let inferredValue = typedValueOpt {
          typedValue = inferredValue
        } else {
          typedValue = try inferTypedExpression(value)
        }
        markExplicitYield(on: currentTarget.id)
        try mergeYieldTargetResult(type: typedValue.type, span: span)
        return .yield(target: currentTarget.id, value: typedValue)
      }

      throw SemanticError(.generic("yield outside of branch expression body"), span: span)
    }
  }
}

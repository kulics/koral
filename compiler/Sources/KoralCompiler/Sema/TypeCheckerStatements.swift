import Foundation

// MARK: - Statement Type Checking Extension
// This extension contains methods for checking statements and producing typed statements.

extension TypeChecker {

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
        typedValue = try inferTypedExpression(value)
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

    case .assignment(let target, let op, let value, let span):
      self.currentSpan = span
      if let op {
        // Lower `x[i] op= v` into a call to `x.set_at(i, deref x[i] op v)`.
        if case .subscriptExpression(let baseExpr, let argExprs) = target {
          let typedBase = try inferTypedExpression(baseExpr)
          let typedArgs = try argExprs.map { try inferTypedExpression($0) }

          // Evaluate base (by reference), args once.
          if typedBase.valueCategory != .lvalue {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedBase.type.description, type2: "rvalue")
          }
          let baseRefType: Type = .reference(inner: typedBase.type)
          let baseRefExpr: TypedExpressionNode = .referenceExpression(
            expression: typedBase, type: baseRefType)
          let baseSym = nextSynthSymbol(prefix: "sub_base", type: baseRefType)
          var stmts: [TypedStatementNode] = [
            .variableDeclaration(identifier: baseSym, value: baseRefExpr, mutable: false)
          ]

          var argSyms: [Symbol] = []
          for a in typedArgs {
            let s = nextSynthSymbol(prefix: "sub_idx", type: a.type)
            argSyms.append(s)
            stmts.append(.variableDeclaration(identifier: s, value: a, mutable: false))
          }

          let baseVar: TypedExpressionNode = .variable(identifier: baseSym)
          let argVars: [TypedExpressionNode] = argSyms.map { .variable(identifier: $0) }
          let readRef = try resolveSubscript(base: baseVar, args: argVars)

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
            arguments: argVars + [newValueExpr],
            type: .void
          )
          stmts.append(.expression(callExpr))

          return .expression(.blockExpression(statements: stmts, finalExpression: nil, type: .void))
        }

        let typedTarget = try resolveLValue(target)
        var typedValue = try inferTypedExpression(value)
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
      // Lower `x[i] = v` into a call to `x.set_at(i, v)`.
      if case .subscriptExpression(let baseExpr, let argExprs) = target {
        let typedBase = try inferTypedExpression(baseExpr)
        let typedArgs = try argExprs.map { try inferTypedExpression($0) }

        // Resolve expected value type from `set_at`.
        let (_, _, expectedValueType) = try resolveSubscriptUpdateMethod(
          base: typedBase, args: typedArgs)

        // Evaluate base (by reference), args, rhs once.
        if typedBase.valueCategory != .lvalue {
          throw SemanticError.invalidOperation(
            op: "implicit ref", type1: typedBase.type.description, type2: "rvalue")
        }
        let baseRefType: Type = .reference(inner: typedBase.type)
        let baseRefExpr: TypedExpressionNode = .referenceExpression(
          expression: typedBase, type: baseRefType)
        let baseSym = nextSynthSymbol(prefix: "sub_base", type: baseRefType)
        var stmts: [TypedStatementNode] = [
          .variableDeclaration(identifier: baseSym, value: baseRefExpr, mutable: false)
        ]

        var argSyms: [Symbol] = []
        for a in typedArgs {
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
          arguments: argVars + [.variable(identifier: valSym)],
          type: .void
        )
        stmts.append(.expression(callExpr))

        return .expression(.blockExpression(statements: stmts, finalExpression: nil, type: .void))
      }

      let typedTarget = try resolveLValue(target)
      var typedValue = try inferTypedExpression(value)
      typedValue = try coerceLiteral(typedValue, to: typedTarget.type)

      if typedValue.type != .never && typedTarget.type != typedValue.type {
        throw SemanticError.typeMismatch(
          expected: typedTarget.type.description, got: typedValue.type.description)
      }

      return .assignment(target: typedTarget, operator: nil, value: typedValue)

    case .deptrAssignment(let pointer, let op, let value, let span):
      self.currentSpan = span
      let typedPointer = try inferTypedExpression(pointer)
      guard case .pointer(let elementType) = typedPointer.type else {
        throw SemanticError(.generic("cannot dereference non-pointer type"))
      }

      var typedValue = try inferTypedExpression(value)
      typedValue = try coerceLiteral(typedValue, to: elementType)
      if typedValue.type != .never && typedValue.type != elementType {
        throw SemanticError.typeMismatch(
          expected: elementType.description, got: typedValue.type.description)
      }

      if let op {
        if let arithmeticOp = compoundOpToArithmeticOp(op) {
          let _ = try checkArithmeticOp(arithmeticOp, elementType, typedValue.type)
        } else if let _ = compoundOpToBitwiseOp(op) {
          if !isIntegerScalarType(elementType) || elementType != typedValue.type {
            throw SemanticError.typeMismatch(
              expected: "Matching Integer Types", got: "\(elementType) \(op) \(typedValue.type)")
          }
        }
      }

      return .deptrAssignment(pointer: typedPointer, operator: op, value: typedValue)

    case .expression(let expr, let span):
      self.currentSpan = span
      return .expression(try inferTypedExpression(expr))

    case .return(let value, let span):
      self.currentSpan = span
      guard let returnType = currentFunctionReturnType else {
        throw SemanticError.invalidOperation(op: "return outside of function", type1: "", type2: "")
      }

      if let value = value {
        if returnType == .void {
          throw SemanticError.typeMismatch(expected: "Void", got: "non-Void")
        }

        var typedValue = try inferTypedExpression(value)
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
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "break outside of while", type1: "", type2: "")
      }
      return .break

    case .continue(let span):
      self.currentSpan = span
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "continue outside of while", type1: "", type2: "")
      }
      return .continue
    }
  }
}

// DropSelfEscape.swift
//
// `self` must not escape a `drop` body.
//
// `drop(self)` runs while the object is being destroyed. Letting `self` out --
// returning it, storing it, passing it on, capturing it in a closure -- either
// resurrects a dying value or moves fields out from under the destructor. So
// inside a `drop` body `self` may appear ONLY as the receiver of a member
// access (`self.x`, `self.x = v`) or a method call (`self.close()`). Every
// other occurrence is an escape.
//
// "Escape" is structural, decided by the shape of the AST and never by a name
// lookup: `self` is legal as the base of a `memberPath`, illegal as a bare
// identifier. A lambda body is a special case -- anything the lambda mentions
// it captures, so ANY `self` there escapes.
//
// `Type(Trait).method(recv, ...)` puts the receiver in the argument list, so
// every part of it is an ordinary use: only `self.m(...)` makes `self` a
// receiver. This mirrors `drop_self_escape_span` in the bootstrap compiler.

/// The span of the first `self` in `expr` that escapes the destructor, if any.
func dropSelfEscapeSpan(_ expr: ExpressionNode) -> SourceSpan? {
  return dropSelfEscapeSpanIn(expr, inLambda: false)
}

/// Whether `base` is a legal receiver use of `self`.
private func dropSelfReceiverSpan(_ base: ExpressionNode, inLambda: Bool) -> SourceSpan? {
  if inLambda {
    return dropSelfEscapeSpanIn(base, inLambda: inLambda)
  }
  if case .identifier(let name, let span) = base, name == "self" {
    return nil
  }
  return dropSelfEscapeSpanIn(base, inLambda: inLambda)
}

private func dropSelfEscapeSpanIn(_ expr: ExpressionNode, inLambda: Bool) -> SourceSpan? {
  switch expr {
  case .identifier(let name, let span):
    return name == "self" ? span : nil

  // `self.x` / `self.x.y` -- the whole path is one receiver use.
  case .memberPath(let base, _, _):
    return dropSelfReceiverSpan(base, inLambda: inLambda)

  // The callee of a call is a value use -- `self()` escapes -- but the base of
  // `self.m(...)` is a receiver.
  case .call(let callee, let arguments, _):
    if let span = dropSelfEscapeSpanIn(callee, inLambda: inLambda) {
      return span
    }
    return dropSelfEscapeInArgs(arguments, inLambda: inLambda)

  case .genericMethodCall(let base, _, _, let arguments, _):
    if let span = dropSelfReceiverSpan(base, inLambda: inLambda) {
      return span
    }
    return dropSelfEscapeInArgs(arguments, inLambda: inLambda)

  // `Type(Trait).method(recv, ...)` -- the base is the TYPE name and the
  // receiver travels in the argument list.
  case .qualifiedMethodCall(_, _, _, let arguments, _):
    return dropSelfEscapeInArgs(arguments, inLambda: inLambda)

  case .qualifiedGenericMethodCall(_, _, _, _, let arguments, _):
    return dropSelfEscapeInArgs(arguments, inLambda: inLambda)

  // A closure captures whatever it mentions; `self` may not be captured.
  case .lambdaExpression(_, _, let body, _):
    return dropSelfEscapeSpanIn(body, inLambda: true)

  case .castExpression(_, let inner, _),
       .unaryMinusExpression(let inner, _),
       .notExpression(let inner, _),
       .bitwiseNotExpression(let inner, _),
       .addressOfExpression(let inner, _, _),
       .derefExpression(let inner, _),
       .unsafeDerefExpression(let inner, _),
       .ptrExpression(let inner, _, _):
    return dropSelfEscapeSpanIn(inner, inLambda: inLambda)

  case .orReturnExpression(let operand, _):
    return dropSelfEscapeSpanIn(operand, inLambda: inLambda)

  case .isExpression(let subject, _, _),
       .isNotExpression(let subject, _, _):
    return dropSelfEscapeSpanIn(subject, inLambda: inLambda)

  case .traitQualificationExpression:
    return nil

  case .staticMethodCall(_, _, _, let arguments, _),
       .implicitMemberExpression(_, let arguments, _):
    return dropSelfEscapeInArgs(arguments, inLambda: inLambda)

  case .collectionLiteral(let elements, _):
    return dropSelfEscapeSpanInList(elements, inLambda: inLambda)

  case .comparisonChainExpression(let operands, _, _):
    return dropSelfEscapeSpanInList(operands, inLambda: inLambda)

  case .dictLiteral(let entries, _):
    for entry in entries {
      if let span = dropSelfEscapeSpanIn(entry.key, inLambda: inLambda) {
        return span
      }
      if let span = dropSelfEscapeSpanIn(entry.value, inLambda: inLambda) {
        return span
      }
    }
    return nil

  case .interpolatedString(let parts, _):
    for part in parts {
      if case .expression(let inner) = part,
         let span = dropSelfEscapeSpanIn(inner, inLambda: inLambda) {
        return span
      }
    }
    return nil

  case .blockExpression(let statements, let tailExpression, _):
    if let span = dropSelfEscapeInStatements(statements, inLambda: inLambda) {
      return span
    }
    if let tail = tailExpression {
      return dropSelfEscapeSpanIn(tail, inLambda: inLambda)
    }
    return nil

  case .subscriptExpression(let base, let arguments, _):
    if let span = dropSelfEscapeSpanIn(base, inLambda: inLambda) {
      return span
    }
    return dropSelfEscapeSpanInList(arguments, inLambda: inLambda)

  case .orElseExpression(let operand, let defaultExpr, _),
       .andThenExpression(let operand, let defaultExpr, _):
    if let span = dropSelfEscapeSpanIn(operand, inLambda: inLambda) {
      return span
    }
    return dropSelfEscapeSpanIn(defaultExpr, inLambda: inLambda)

  case .arithmeticExpression(let left, _, let right, _),
       .comparisonExpression(let left, _, let right, _),
       .bitwiseExpression(let left, _, let right, _),
       .andExpression(let left, let right, _),
       .orExpression(let left, let right, _):
    if let span = dropSelfEscapeSpanIn(left, inLambda: inLambda) {
      return span
    }
    return dropSelfEscapeSpanIn(right, inLambda: inLambda)

  case .rangeExpression(_, let left, let right, _):
    if let left = left, let span = dropSelfEscapeSpanIn(left, inLambda: inLambda) {
      return span
    }
    if let right = right {
      return dropSelfEscapeSpanIn(right, inLambda: inLambda)
    }
    return nil

  case .ifExpression(let condition, let thenBranch, let elseBranch, _):
    if let span = dropSelfEscapeSpanIn(condition, inLambda: inLambda) {
      return span
    }
    if let span = dropSelfEscapeSpanIn(thenBranch, inLambda: inLambda) {
      return span
    }
    if let elseBranch = elseBranch {
      return dropSelfEscapeSpanIn(elseBranch, inLambda: inLambda)
    }
    return nil

  case .whileExpression(let condition, let body, _):
    if let span = dropSelfEscapeSpanIn(condition, inLambda: inLambda) {
      return span
    }
    return dropSelfEscapeSpanIn(body, inLambda: inLambda)

  case .forExpression(_, let iterable, let body, _):
    if let span = dropSelfEscapeSpanIn(iterable, inLambda: inLambda) {
      return span
    }
    return dropSelfEscapeSpanIn(body, inLambda: inLambda)

  case .whenExpression(let subject, let cases, _):
    if let span = dropSelfEscapeSpanIn(subject, inLambda: inLambda) {
      return span
    }
    for matchCase in cases {
      if let span = dropSelfEscapeSpanIn(matchCase.body, inLambda: inLambda) {
        return span
      }
    }
    return nil

  // Literals, the empty literal and generic instantiations carry no
  // expression that could name `self`.
  case .integerLiteral, .floatLiteral, .stringLiteral, .runeLiteral,
       .booleanLiteral, .emptyLiteral, .genericInstantiation:
    return nil
  }
}

private func dropSelfEscapeSpanInList(_ exprs: [ExpressionNode], inLambda: Bool) -> SourceSpan? {
  for expr in exprs {
    if let span = dropSelfEscapeSpanIn(expr, inLambda: inLambda) {
      return span
    }
  }
  return nil
}

private func dropSelfEscapeInArgs(_ args: [CallArg], inLambda: Bool) -> SourceSpan? {
  for arg in args {
    if let inner = arg.expression, let span = dropSelfEscapeSpanIn(inner, inLambda: inLambda) {
      return span
    }
  }
  return nil
}

private func dropSelfEscapeInStatements(_ statements: [StatementNode], inLambda: Bool) -> SourceSpan? {
  for statement in statements {
    let found: SourceSpan?
    switch statement {
    case .variableDeclaration(_, _, let value, _, _):
      found = dropSelfEscapeSpanIn(value, inLambda: inLambda)
    case .tupleVariableDeclaration(_, let value, _):
      found = dropSelfEscapeSpanIn(value, inLambda: inLambda)
    // `self.x = v` is a receiver write; anything else in the target position is
    // a use like any other.
    case .assignment(let target, _, let value, _):
      if case .memberPath(let base, _, _) = target {
        if let span = dropSelfReceiverSpan(base, inLambda: inLambda) {
          found = span
        } else {
          found = dropSelfEscapeSpanIn(value, inLambda: inLambda)
        }
      } else if let span = dropSelfEscapeSpanIn(target, inLambda: inLambda) {
        found = span
      } else {
        found = dropSelfEscapeSpanIn(value, inLambda: inLambda)
      }
    case .expression(let expr, _):
      found = dropSelfEscapeSpanIn(expr, inLambda: inLambda)
    case .return(let value, _):
      found = value.flatMap { dropSelfEscapeSpanIn($0, inLambda: inLambda) }
    case .break, .continue:
      found = nil
    case .deferStatement(let expression, _):
      found = dropSelfEscapeSpanIn(expression, inLambda: inLambda)
    }
    if let found = found {
      return found
    }
  }
  return nil
}

import Foundation

// MARK: - Expression Type Inference Extension
// This extension contains methods for inferring types of expressions,
// including the main inferTypedExpression method and its helper methods.

extension TypeChecker {

  private func visibleGenericFunctionTemplate(_ name: String) -> GenericFunctionTemplate? {
    func template(for defId: DefId) -> GenericFunctionTemplate? {
      guard case .genericTemplate(.function)? = defIdMap.getKind(defId),
            let info = defIdMap.getGenericFunctionTemplateInfo(defId) else {
        return nil
      }
      return GenericFunctionTemplate(
        defId: defId,
        typeParameters: info.typeParameters,
        parameters: info.parameters,
        returnType: info.returnType,
        body: info.body,
        checkedBody: info.checkedBody,
        checkedParameters: info.checkedParameters,
        checkedReturnType: info.checkedReturnType
      )
    }

    if let fileScopedDefId = defIdMap.lookup(modulePath: currentModulePath, name: name, sourceFile: currentSourceFile),
       let template = template(for: fileScopedDefId) {
      return template
    }

    if let moduleScopedDefId = defIdMap.lookup(modulePath: currentModulePath, name: name, sourceFile: nil),
       let template = template(for: moduleScopedDefId) {
      return template
    }

    return currentScope.lookupGenericFunctionTemplate(name)
  }

  private func isASCIITypeStyleIdentifier(_ name: String) -> Bool {
    guard !name.isEmpty else { return false }
    for scalar in name.unicodeScalars {
      if scalar == "_" { continue }
      return scalar.value >= 65 && scalar.value <= 90
    }
    return false
  }

  private func isKnownModuleIdentifier(_ name: String) -> Bool {
    for moduleInfo in moduleSymbols.values {
      guard let lastSegment = moduleInfo.modulePath.last else { continue }
      if moduleFileNameToIdentifier(lastSegment) == name {
        return true
      }
    }
    return false
  }

  private func isModulePrefixedMemberPath(baseExpr: ExpressionNode, path: [String]) -> Bool {
    guard case .identifier(let baseName, _) = baseExpr,
          !path.isEmpty,
          isASCIITypeStyleIdentifier(baseName),
          currentScope.lookup(baseName, sourceFile: currentSourceFile) == nil,
          currentScope.lookupType(baseName, sourceFile: currentSourceFile) == nil else {
      return false
    }

    return true
  }

  /// Enforce that a type satisfies the 'mutable' constraint at a call site.
  /// Used by downgrade/upgrade name-matching paths that bypass normal constraint enforcement.
  private func enforceMutableConstraintForCall(_ type: Type, function: String, span: SourceSpan) throws {
    let satisfied: Bool
    switch type {
    case .structure(let defId):
      satisfied = context.isTypeMutable(defId)
    case .genericStruct(let templateDefId, _):
      if templateDefId.isValid {
        satisfied =
          context.isTypeMutable(templateDefId) || context.isGenericStructTemplateMutable(templateDefId)
      } else {
        satisfied = false
      }
    default:
      satisfied = false
    }
    if !satisfied {
      throw SemanticError(.generic(
        "'\(function)' requires a 'type mutable' argument, but '\(type)' is not declared as 'type mutable'"
      ), span: span)
    }
  }

  private func enforceGenericFunctionCallConstraints(
    typeParameters: [TypeParameterDecl],
    args: [Type]
  ) throws {
    guard typeParameters.count == args.count else { return }

    for (param, arg) in zip(typeParameters, args) {
      guard case .genericParameter(let argName) = arg else {
        continue
      }

      for constraint in param.constraints {
        switch constraint {
        case .mutable, .foreign:
          // A shape requirement is checked at the generic parameter's own
          // declaration.
          continue

        case .trait(_, let traitName, _):
          let requiredDefId = resolveBound(constraint).defId ?? .invalid
          let hasRequiredBound =
            (genericTraitBounds[argName] ?? []).contains { boundRequires($0, requiredDefId) }
          if !hasRequiredBound {
            let ctx = "checking constraint \(param.name): \(constraint)"
            throw SemanticError(.generic(
              "Type \(argName) does not explicitly implement trait \(traitName) (\(ctx))"
            ), span: currentSpan)
          }
        }
      }
    }
  }

  private func isStdDropTraitConformance(_ conformance: TypedTraitConformance?) -> Bool {
    guard let conformance else { return false }
    return isStdDropTrait(conformance.traitDefId)
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
       isStdDropTrait(dispatch.conformanceTraitDefId) {
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
    case .uint, .uint8, .uint16, .uint32, .uint64,
         .wrappingUInt, .wrappingUInt8, .wrappingUInt16, .wrappingUInt32, .wrappingUInt64:
      return true
    default:
      return false
    }
  }

  func isRefLikeTypeForMutability(_ type: Type) -> Bool {
    type.indirectionCompatibilityInfo != nil
  }

  func isMutableRefLikeType(_ type: Type) -> Bool {
    type.indirectionCompatibilityInfo?.mutable == true
  }

  func isReadOnlyRefLikeType(_ type: Type) -> Bool {
    guard let info = type.indirectionCompatibilityInfo else {
      return false
    }
    return !info.mutable
  }

  func dereferenceTargetType(of type: Type) -> Type? {
    type.indirectionCompatibilityInfo?.inner
  }

  func nominalDefId(for type: Type) -> DefId? {
    switch type {
    case .structure(let defId), .`enum`(let defId), .opaque(let defId):
      return defId
    // The type already carries its template's DECLARATION; re-reading the name
    // would only round-trip an identity back through a table.
    case .genericStruct(let tplDefId, _):
      return tplDefId
    case .genericEnum(let tplDefId, _):
      return tplDefId
    default:
      return nil
    }
  }

  func canonicalizedTypeForStaticMemberLookup(_ type: Type) -> Type {
    switch type {
    case .structure(let defId), .`enum`(let defId), .opaque(let defId):
      if let mapped = context.defIdMap.lookupType(defId: defId), mapped != type {
        return canonicalizedTypeForStaticMemberLookup(mapped)
      }
      return type
    default:
      return type
    }
  }

  func canonicalizedTypeForComparison(_ type: Type) -> Type {
    switch type {
    case .structure, .`enum`, .opaque:
      return canonicalizedTypeForStaticMemberLookup(type)
    case .reference(let inner):
      return .reference(inner: canonicalizedTypeForComparison(inner))
    case .mutableReference(let inner):
      return .mutableReference(inner: canonicalizedTypeForComparison(inner))
    case .borrowedReference(let inner):
      return .borrowedReference(inner: canonicalizedTypeForComparison(inner))
    case .mutableBorrowedReference(let inner):
      return .mutableBorrowedReference(inner: canonicalizedTypeForComparison(inner))
    case .pointer(let element):
      return .pointer(element: canonicalizedTypeForComparison(element))
    case .mutablePointer(let element):
      return .mutablePointer(element: canonicalizedTypeForComparison(element))
    case .weakReference(let inner):
      return .weakReference(inner: canonicalizedTypeForComparison(inner))
    case .mutableWeakReference(let inner):
      return .mutableWeakReference(inner: canonicalizedTypeForComparison(inner))
    case .function(let parameters, let returns):
      return .function(
        parameters: parameters.map { Parameter(type: canonicalizedTypeForComparison($0.type), kind: $0.kind) },
        returns: canonicalizedTypeForComparison(returns)
      )
    case .genericStruct(let defId, let args):
      return .genericStruct(templateDefId: defId, args: args.map { canonicalizedTypeForComparison($0) })
    case .genericEnum(let defId, let args):
      return .genericEnum(templateDefId: defId, args: args.map { canonicalizedTypeForComparison($0) })
    case .traitObject(let defId, let typeArgs):
      return .traitObject(traitDefId: defId, typeArgs: typeArgs.map { canonicalizedTypeForComparison($0) })
    default:
      return type
    }
  }

  func nominalInstantiationMatchesGeneric(_ nominal: Type, genericCandidate: Type) -> Bool {
    switch (canonicalizedTypeForComparison(nominal), canonicalizedTypeForComparison(genericCandidate)) {
    case (.structure(let defId), .genericStruct(let tplDefId, let typeArgs)):
      // Identity: the template the nominal was instantiated from.
      guard context.getTemplateDefId(defId) == tplDefId,
            let actualArgs = context.getTypeArguments(defId),
            actualArgs.count == typeArgs.count else {
        return false
      }
      return zip(actualArgs, typeArgs).allSatisfy { typesEquivalentForComparison($0, $1) }
    case (.`enum`(let defId), .genericEnum(let tplDefId, let typeArgs)):
      guard context.getTemplateDefId(defId) == tplDefId,
            let actualArgs = context.getTypeArguments(defId),
            actualArgs.count == typeArgs.count else {
        return false
      }
      return zip(actualArgs, typeArgs).allSatisfy { typesEquivalentForComparison($0, $1) }
    default:
      return false
    }
  }

  func typesEquivalentForComparison(_ lhs: Type, _ rhs: Type) -> Bool {
    let left = canonicalizedTypeForComparison(lhs)
    let right = canonicalizedTypeForComparison(rhs)
    if left == right {
      return true
    }

    if let (expectedInner, actualInner) = left.compatibleIndirectionInners(with: right) {
      return typesEquivalentForComparison(expectedInner, actualInner)
    }

    return nominalInstantiationMatchesGeneric(left, genericCandidate: right)
      || nominalInstantiationMatchesGeneric(right, genericCandidate: left)
  }

  func requireDerefablePointee(
    _ innerType: Type,
    operation: String,
    spelledType: String
  ) throws {
    if case .traitObject = innerType {
      throw SemanticError(.generic(
        "Cannot use \(operation) on a trait object \(spelledType): concrete type is unknown at compile time"
      ), span: currentSpan)
    }
    if case .opaque = innerType {
      throw SemanticError(.generic(
        "Cannot use \(operation) on an opaque type \(spelledType): type layout is unknown at compile time"
      ), span: currentSpan)
    }
    if case .genericParameter = innerType {
      // The old `Deref` trait constraint is removed from the language model.
      // Generic pointees are allowed to be dereferenced based on their concrete
      // target type/indirection semantics rather than a legacy trait bound.
    }
  }

  func canTakeMutableReference(to expr: TypedExpressionNode) -> Bool {
    switch expr {
    case .variable(let identifier):
      if isMutableRefLikeType(identifier.type) {
        return true
      }
      return identifier.isMutable()

    case .memberPath(let source, let members):
      var currentType = source.type
      var mutablePath = canTakeMutableReference(to: source)

      for (index, member) in members.enumerated() {
        let isLast = index == members.count - 1

        if isMutableRefLikeType(currentType) {
          mutablePath = true
          if isLast {
            return member.isMutable() || isMutableRefLikeType(member.type)
          }
        } else if isReadOnlyRefLikeType(currentType) {
          mutablePath = false
          if isLast {
            return false
          }
        } else if isLast {
          return mutablePath && member.isMutable()
        } else if !member.isMutable() && !isMutableRefLikeType(member.type) {
          mutablePath = false
        }

        currentType = member.type
      }

      return false

        case .derefExpression(let inner, _),
          .unsafeDerefExpression(let inner, _):
      return isMutableRefLikeType(inner.type)

    default:
      return false
    }
  }

  func allowsImplicitMutableSelfReference(_ expr: TypedExpressionNode) -> Bool {
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
    case .derefExpression, .unsafeDerefExpression:
      return true
    default:
      return false
    }
  }

  func implicitSelfRefViolationName(_ expr: TypedExpressionNode) -> String? {
    switch expr {
    case .variable(let identifier):
      return context.getName(identifier.defId)
    case .memberPath(_, let members):
      return members.last.flatMap { context.getName($0.defId) }
    default:
      return nil
    }
  }

  func referenceTypeComponents(_ type: Type) -> (inner: Type, mutable: Bool)? {
    switch type {
    case .reference(let inner):
      return (inner, false)
    case .mutableReference(let inner):
      return (inner, true)
    case .borrowedReference(let inner):
      return (inner, false)
    case .mutableBorrowedReference(let inner):
      return (inner, true)
    default:
      return nil
    }
  }

  func borrowedReferenceTypeComponents(_ type: Type) -> (inner: Type, mutable: Bool)? {
    switch type {
    case .borrowedReference(let inner):
      return (inner, false)
    case .mutableBorrowedReference(let inner):
      return (inner, true)
    default:
      return nil
    }
  }

  func canTakeImplicitReference(to expr: TypedExpressionNode, mutable: Bool) -> Bool {
    guard isAddressableForReference(expr) else {
      return false
    }
    return mutable ? canTakeMutableReference(to: expr) : true
  }

  func isAddressableForReference(_ expr: TypedExpressionNode) -> Bool {
    if expr.valueCategory == .lvalue {
      return true
    }
    if case .derefExpression = expr {
      return true
    }
    if case .unsafeDerefExpression = expr {
      return true
    }
    return false
  }

  func implicitReferenceInnerMatches(_ expectedInner: Type, actualType: Type) -> Bool {
    typesEquivalentForComparison(expectedInner, actualType)
  }

  func makeImplicitReference(_ expr: TypedExpressionNode, expectedType: Type) throws -> TypedExpressionNode? {
    guard let (inner, mutable) = referenceTypeComponents(expectedType),
      implicitReferenceInnerMatches(inner, actualType: expr.type) else {
      return nil
    }
    guard isAddressableForReference(expr) else {
      throw SemanticError.invalidOperation(
        op: "implicit ref", type1: expr.type.description, type2: "rvalue")
    }
    if mutable && !canTakeMutableReference(to: expr) {
      let name = implicitSelfRefViolationName(expr) ?? "<value>"
      throw SemanticError(.cannotTakeRefOfImmutable(name), span: currentSpan)
    }
    return .referenceExpression(expression: expr, type: expectedType)
  }

  // NOTE: This function handles compiler-internal .reference/.mutableReference types
  // produced by managed nominal layout, NOT user-written *T syntax (which is removed).
  func prepareReceiverBase(
    _ base: TypedExpressionNode,
    expectedType: Type,
    methodName: String
  ) throws -> (base: TypedExpressionNode, binding: (symbol: Symbol, value: TypedExpressionNode)?) {
    guard base.valueCategory == .rvalue else {
      return (base, nil)
    }

    if let expectedInfo = expectedType.indirectionCompatibilityInfo,
       !expectedInfo.mutable,
       expectedInfo.family == .managedReference,
       implicitReferenceInnerMatches(expectedInfo.inner, actualType: base.type) {
      let tempSymbol = nextSynthSymbol(prefix: "temp_recv", type: base.type)
      return (
        .variable(identifier: tempSymbol),
        (symbol: tempSymbol, value: base)
      )
    }

    if let expectedInfo = expectedType.indirectionCompatibilityInfo,
       expectedInfo.mutable,
       expectedInfo.family == .managedReference,
       implicitReferenceInnerMatches(expectedInfo.inner, actualType: base.type) {
      if canTakeImplicitReference(to: base, mutable: true) {
        return (base, nil)
      }
      if isMutableNominalReceiverType(base.type) {
        let tempSymbol = nextSynthSymbol(prefix: "temp_recv_mut", type: base.type)
        return (
          .variable(identifier: tempSymbol),
          (symbol: tempSymbol, value: base)
        )
      }
      throw SemanticError(
        .generic("Cannot call 'mutable self' method '\(methodName)' on an rvalue; store the value in a 'let mutable' variable first"),
        span: currentSpan
      )
    }

    return (base, nil)
  }

  func wrapReceiverMaterialization(
    _ binding: (symbol: Symbol, value: TypedExpressionNode)?,
    body: TypedExpressionNode,
    type: Type
  ) -> TypedExpressionNode {
    guard let binding else {
      return body
    }

    return .makeLetBlock(
      identifier: binding.symbol,
      value: binding.value,
      body: body,
      type: type
    )
  }

  // NOTE: This handles compiler-internal .reference/.mutableReference types
  // produced by managed nominal layout, NOT user-written *T syntax (which is removed).
  func makeImplicitDereference(_ expr: TypedExpressionNode, expectedType: Type) -> TypedExpressionNode? {
    guard let info = expr.type.indirectionCompatibilityInfo,
          info.family == .managedReference,
          implicitReferenceInnerMatches(info.inner, actualType: expectedType) else {
      return nil
    }
    return .derefExpression(expression: expr, type: info.inner)
  }

  func autoDereferenceValueContext(_ expr: TypedExpressionNode) -> TypedExpressionNode {
    guard let info = expr.type.indirectionCompatibilityInfo,
          info.family == .managedReference else {
      return expr
    }
    return .derefExpression(expression: expr, type: info.inner)
  }

  /// Checks whether `expr` has a mutable reference type that can be widened
  /// to the expected (read-only) reference type.  Returns `true` when
  /// `expr.type` is `T ref mutable` and `expectedType` is `T ref` with the same
  /// inner type.  Also handles `T ptr mutable → T ptr` and
  /// `T weakref mutable → T weakref`.
  func canWidenMutableReference(_ expr: TypedExpressionNode, expectedType: Type) -> Bool {
    guard let (expectedInner, actualInner) = expectedType.compatibleIndirectionInners(with: expr.type) else {
      return false
    }
    guard let expectedInfo = expectedType.indirectionCompatibilityInfo,
          let actualInfo = expr.type.indirectionCompatibilityInfo,
          !expectedInfo.mutable,
          actualInfo.mutable else {
      return false
    }
    return implicitReferenceInnerMatches(expectedInner, actualType: actualInner)
  }

  func makeReferenceFlavorConversion(_ expr: TypedExpressionNode, expectedType: Type) -> TypedExpressionNode? {
    guard let (expectedInner, actualInner) = expectedType.compatibleIndirectionInners(with: expr.type) else {
      return nil
    }
    guard let expectedInfo = expectedType.indirectionCompatibilityInfo,
          let actualInfo = expr.type.indirectionCompatibilityInfo,
          expectedInfo.family == actualInfo.family,
          expectedInfo.mutable == actualInfo.mutable || actualInfo.mutable else {
      return nil
    }
    guard implicitReferenceInnerMatches(expectedInner, actualType: actualInner) else {
      return nil
    }
    if expr.type == expectedType {
      return expr
    }
    return .castExpression(expression: expr, type: expectedType)
  }

  /// Applies the standard coercion chain to a typed argument that doesn't match the expected type.
  /// Supports: reference flavor conversion and mutable reference widening.
  /// No implicit ref promotion (T → ref T) or auto-deref (ref T → T) for function arguments.
  /// Use explicit .ref / .val at the call site instead.
  func coerceArgumentType(_ typedArg: TypedExpressionNode, expectedType: Type) throws -> TypedExpressionNode {
    // A value that already failed -- on either side -- agrees with nothing,
    // including the parameter it is passed to. The complaint about the
    // failure has been made; this one would be about its consequence.
    if expectedType == .error || typedArg.type == .error {
      return typedArg
    }
    if let flavorConversion = makeReferenceFlavorConversion(typedArg, expectedType: expectedType) {
      return flavorConversion
    }
    if canWidenMutableReference(typedArg, expectedType: expectedType) {
      return typedArg
    }
    throw SemanticError.typeMismatch(
      expected: expectedType.description,
      got: typedArg.type.description
    )
  }

  /// Applies coercion chain for method receivers.
  /// Auto-ref is allowed for receiver reference forms.
  /// Auto-deref (ref T → T) is allowed for self receivers (following Go's pointer receiver behavior).
  ///
  /// NOTE: This handles compiler-internal .reference/.mutableReference types
  /// produced by managed nominal layout, NOT user-written *T syntax (which is removed).
  func coerceReceiverType(_ base: TypedExpressionNode, expectedType: Type) throws -> TypedExpressionNode {
    // Same rule as coerceArgumentType: a failed value or a failed parameter
    // type draws no second complaint at the receiver.
    if expectedType == .error || base.type == .error {
      return base
    }
    if let flavorConversion = makeReferenceFlavorConversion(base, expectedType: expectedType) {
      return flavorConversion
    }
    if let expectedInfo = expectedType.indirectionCompatibilityInfo,
       let actualInfo = base.type.indirectionCompatibilityInfo,
       expectedInfo.family == .managedReference,
       actualInfo.family == .managedReference,
       expectedInfo.mutable,
       !actualInfo.mutable,
       implicitReferenceInnerMatches(expectedInfo.inner, actualType: actualInfo.inner) {
      throw SemanticError(
        .generic("Cannot call mutating method through read-only reference of type '\(base.type.description)'"),
        span: currentSpan
      )
    }
    if let (inner, mutable) = referenceTypeComponents(expectedType),
       implicitReferenceInnerMatches(inner, actualType: base.type),
       isAddressableForReference(base) {
      if mutable && !canTakeMutableReference(to: base) && !isMutableNominalReceiverType(base.type) {
        let name = implicitSelfRefViolationName(base) ?? "<value>"
        throw SemanticError(.cannotTakeRefOfImmutable(name), span: currentSpan)
      }
      if let (borrowedInner, borrowedMutable) = borrowedReferenceTypeComponents(expectedType) {
        let refType: Type = borrowedMutable
          ? .mutableBorrowedReference(inner: borrowedInner)
          : .borrowedReference(inner: borrowedInner)
        return .referenceExpression(expression: base, type: refType)
      }
      let refType: Type = mutable
        ? .mutableReference(inner: base.type)
        : .reference(inner: base.type)
      return .referenceExpression(expression: base, type: refType)
    }
    if let implicitDeref = makeImplicitDereference(base, expectedType: expectedType) {
      return implicitDeref
    }
    if canWidenMutableReference(base, expectedType: expectedType) {
      return base
    }
    throw SemanticError.typeMismatch(
      expected: expectedType.description,
      got: base.type.description
    )
  }

  func inferArgumentExpression(
    _ arg: ExpressionNode,
    expectedType: Type
  ) throws -> TypedExpressionNode {
    var typedArg: TypedExpressionNode
    if case .lambdaExpression(let lambdaParams, let returnType, let body, _) = arg {
      typedArg = try inferLambdaExpression(
        parameters: lambdaParams,
        returnType: returnType,
        body: body,
        expectedType: expectedType
      )
    } else if case .rangeExpression(let op, let left, let right, _) = arg {
      typedArg = try inferRangeExpression(
        operator: op,
        left: left,
        right: right,
        expectedType: expectedType
      )
    } else {
      typedArg = try inferTypedExpression(arg, expectedType: expectedType)
    }

    typedArg = try coerceLiteral(typedArg, to: expectedType, span: arg.span)
    if typedArg.type == .never {
      return typedArg
    }
    if typedArg.type != expectedType {
      typedArg = try coerceArgumentType(typedArg, expectedType: expectedType)
    }

    return typedArg
  }

  private func tryOptimizeLiteralCast(
    _ expr: ExpressionNode,
    targetType: Type
  ) throws -> TypedExpressionNode? {
    switch expr {
    case .integerLiteral(let value, let literalSpan):
      if isIntegerType(targetType) {
        try checkIntegerLiteralRange(value: value, targetType: targetType, span: literalSpan)
        return .integerLiteral(value: value, type: targetType)
      }
      if isFloatType(targetType) {
        return .floatLiteral(value: value, type: targetType)
      }
      return nil
    case .floatLiteral(let value, _):
      if isFloatType(targetType) {
        return .floatLiteral(value: value, type: targetType)
      }
      return nil
    default:
      return nil
    }
  }

  // MARK: - `expr as Type` reinterpretation casts

  /// `expr as Type` -- a new type view on the same value. The RESOLVED target
  /// type (aliases expanded) decides which cast this is: weak construction
  /// (`?U`) or pointer reinterpretation (`*U`, and `Int`/`UInt` in both
  /// directions). Numeric conversion, nominal construction and the
  /// trait-object upcast are `Type(expr)` and are refused here with a pointer
  /// at that spelling.
  private func inferAsCast(typeNode: TypeNode, innerExpr: ExpressionNode) throws -> TypedExpressionNode {
    let targetType = try resolveTypeNode(typeNode)

    // A `null` source is a pointer literal aimed at the cast target. It joins
    // a pointer target directly, takes the pointer→integer reinterpretation
    // row (reading as 0) for `Int`/`UInt`, and meets the weak path's referent
    // check for `?U` -- which reports the REFERENT, spelled `null` on the
    // got-side. Every other target refuses the cast the way the rows below do
    // for a `*void` source.
    if case .nullLiteral(let literalSpan) = innerExpr {
      switch targetType {
      case .pointer, .mutablePointer:
        return .intrinsicCall(.nullPtr(resultType: targetType))
      case .weakReference(let referent), .mutableWeakReference(let referent):
        try handleError(
          SemanticError(
            .typeMismatch(expected: referent.description, got: "null"),
            span: literalSpan))
        return failedExpression()
      case .int, .uint:
        return .castExpression(
          expression: .intrinsicCall(.nullPtr(resultType: .pointer(element: .void))),
          type: targetType)
      default:
        if isTraitObjectCastTarget(targetType) {
          throw SemanticError(.generic(
            "Construction is written 'Type(args)', not 'expr as Type'"
          ), span: currentSpan)
        }
        if isIntegerScalarType(targetType) || isFloatScalarType(targetType) {
          throw SemanticError.invalidOperation(
            op: "cast",
            type1: Type.pointer(element: .void).description,
            type2: targetType.description
          )
        }
        if isNominalCastTarget(targetType) {
          throw SemanticError(.generic(
            "Construction is written 'Type(args)', not 'expr as Type'"
          ), span: currentSpan)
        }
        throw SemanticError(.generic(
          "'as' casts to pointer or weak types"
        ), span: currentSpan)
      }
    }

    // Weak construction (?U): a handle wrap, not a bit reinterpretation. The
    // same checks and the same `downgrade` intrinsic the `?U(expr)` spelling
    // used. `?Trait` is not a weak cast: a trait referent never satisfies the
    // 'type mutable' constraint, and `resolveTypeNode` already says so.
    if case .weakReference(let innerType) = targetType {
      let typedInner = autoDereferenceValueContext(try inferTypedExpression(innerExpr))
      try enforceMutableConstraintForCall(typedInner.type, function: "downgrade", span: innerExpr.span)
      // The referent is `T`, so the argument has to be a `T`. Mutability
      // alone would let `?B(a)` build a `?B` out of an `A`.
      if typedInner.type != innerType {
        throw SemanticError.typeMismatch(
          expected: innerType.description, got: typedInner.type.description)
      }
      return .intrinsicCall(.downgradeRef(val: typedInner, resultType: targetType))
    }
    if case .mutableWeakReference(let innerType) = targetType {
      let typedInner = autoDereferenceValueContext(try inferTypedExpression(innerExpr))
      try enforceMutableConstraintForCall(typedInner.type, function: "downgrade", span: innerExpr.span)
      if typedInner.type != innerType {
        throw SemanticError.typeMismatch(
          expected: innerType.description, got: typedInner.type.description)
      }
      return .intrinsicCall(.downgradeRef(val: typedInner, resultType: targetType))
    }

    // The trait-object upcast moved to the call form `Trait(expr)`. The `as`
    // spelling for it joins nominal construction in being refused here -- and
    // it must not fall through to the wrong-target message below.
    if isTraitObjectCastTarget(targetType) {
      throw SemanticError(.generic(
        "Construction is written 'Type(args)', not 'expr as Type'"
      ), span: currentSpan)
    }

    // Pointer reinterpretation: any pointer flavor/pointee in either
    // direction, or `Int`/`UInt` as an address.
    if isPointerCastType(targetType) {
      if let optimized = try tryOptimizeLiteralCast(innerExpr, targetType: targetType) {
        return optimized
      }
      let typedInner = autoDereferenceValueContext(try inferTypedExpression(innerExpr))
      if isValidAsCast(from: typedInner.type, to: targetType) {
        // Cast always produces an rvalue.
        return .castExpression(expression: typedInner, type: targetType)
      }
      throw SemanticError.invalidOperation(
        op: "cast",
        type1: typedInner.type.description,
        type2: targetType.description
      )
    }

    // `Int`/`UInt` (and the other numeric spellings): pointer bits read as an
    // integer for `Int`/`UInt`, a pointer at `Type(expr)` for anything
    // numeric, and no numeric conversion through `as` at all.
    if isIntegerScalarType(targetType) || isFloatScalarType(targetType) {
      let typedInner = autoDereferenceValueContext(try inferTypedExpression(innerExpr))
      if isPointerCastType(typedInner.type) {
        if targetType == .int || targetType == .uint {
          return .castExpression(expression: typedInner, type: targetType)
        }
      } else if isIntegerScalarType(typedInner.type) || isFloatScalarType(typedInner.type) {
        throw SemanticError(.generic(
          "Numeric conversion is written 'Type(expr)', not 'expr as Type'"
        ), span: currentSpan)
      }
      throw SemanticError.invalidOperation(
        op: "cast",
        type1: typedInner.type.description,
        type2: targetType.description
      )
    }

    // Nominals are built, not cast. Std's String is nominal in the type
    // system but reads as a builtin (literal syntax), so it takes the
    // wrong-target message rather than a construction hint.
    if isNominalCastTarget(targetType) {
      throw SemanticError(.generic(
        "Construction is written 'Type(args)', not 'expr as Type'"
      ), span: currentSpan)
    }
    throw SemanticError(.generic(
      "'as' casts to pointer or weak types"
    ), span: currentSpan)
  }

  /// The trait-object upcast on a typed value: identity when the source
  /// already is that trait object, `Cannot cast a trait object to another
  /// trait object` when it is a different one, and a cast error when the
  /// conversion machinery declines. The conversion machinery carries the
  /// object-safety and conformance checks. This is the decline-checking
  /// wrapper the `as` spelling used to inline; its only caller is the call
  /// form `Trait(expr)` now.
  private func performTraitObjectUpcast(
    _ typedInner: TypedExpressionNode, target targetType: Type
  ) throws -> TypedExpressionNode {
    // Identity: the source already IS that trait object.
    if typedInner.type == targetType {
      return typedInner
    }
    if case .traitObject = peelReferenceWrappers(typedInner.type) {
      throw SemanticError(.generic(
        "Cannot cast a trait object to another trait object"
      ), span: currentSpan)
    }
    let converted = try tryTraitObjectConversion(typedInner, to: targetType)
    if converted.type != targetType {
      throw SemanticError.invalidOperation(
        op: "cast",
        type1: typedInner.type.description,
        type2: targetType.description
      )
    }
    return converted
  }

  /// `Trait(expr)` / `(Trait)(expr)` / `Trait[Args](expr)` -- the explicit
  /// trait-object upcast, keyed on the resolved target. Exactly one positional
  /// argument; the result type is the resolved target (a trait-object
  /// reference), same as the implicit coercion.
  private func inferTraitObjectUpcastCall(
    targetType: Type, callArgs: [CallArg], span: SourceSpan
  ) throws -> TypedExpressionNode {
    guard callArgs.count == 1,
          let arg = callArgs.first,
          arg.label == nil,
          let innerExpr = arg.expression else {
      throw SemanticError(.generic(
        "A cast takes exactly one positional argument: write 'Type(expr)'"
      ), span: span)
    }
    let typedInner = try inferTypedExpression(innerExpr)
    return try performTraitObjectUpcast(typedInner, target: targetType)
  }

  /// The trait-object row: a resolved trait-object reference target.
  private func isTraitObjectCastTarget(_ type: Type) -> Bool {
    switch type {
    case .traitObject:
      return true
    case .reference(let inner), .mutableReference(let inner):
      if case .traitObject = inner { return true }
      return false
    default:
      return false
    }
  }

  /// Strips managed-reference wrappers to find the value underneath.
  private func peelReferenceWrappers(_ type: Type) -> Type {
    switch type {
    case .reference(let inner), .mutableReference(let inner),
         .borrowedReference(let inner), .mutableBorrowedReference(let inner):
      return peelReferenceWrappers(inner)
    default:
      return type
    }
  }

  private func isPointerCastType(_ type: Type) -> Bool {
    switch type {
    case .pointer, .mutablePointer:
      return true
    default:
      return false
    }
  }

  /// Whether `type` is one of the reinterpretation families -- pointer, weak,
  /// or trait-object -- that `as` casts to and `Type(expr)` must refuse.
  private func isPointerWeakOrTraitCastTarget(_ type: Type) -> Bool {
    switch type {
    case .pointer, .mutablePointer, .weakReference, .mutableWeakReference:
      return true
    case .traitObject:
      return true
    case .reference(let inner), .mutableReference(let inner):
      if case .traitObject = inner { return true }
      return false
    default:
      return false
    }
  }

  /// The `as` construction-error row: struct/enum targets (aliases included,
  /// having resolved already). Std's String is excluded -- it reads as a
  /// builtin, not a constructor.
  private func isNominalCastTarget(_ type: Type) -> Bool {
    switch type {
    case .structure, .`enum`, .genericStruct, .genericEnum:
      return !context.isStdNominalType(type, context.stdStringDefId)
    default:
      return false
    }
  }

  private func makeBreakBlock(span: SourceSpan) -> ExpressionNode {
    .blockExpression(statements: [.break(span: span)], tailExpression: nil, span: span)
  }

  func mergeBranchResultTypes(_ current: Type?, _ incoming: Type, span: SourceSpan) throws -> Type {
    if incoming == .never {
      return current ?? .never
    }
    guard let current else { return incoming }
    if current == .never {
      return incoming
    }
    if current == incoming {
      return current
    }
    if let mergedType = commonBranchSupertype(current, incoming) {
      return mergedType
    }
    // A branch that already failed has no type to disagree about.
    if current == .error || incoming == .error {
      return .error
    }
    throw SemanticError.typeMismatch(expected: current.description, got: incoming.description)
  }

  func branchNeedsExpectedTypeForImplicitMember(_ expr: ExpressionNode) -> Bool {
    if case .implicitMemberExpression = expr {
      return true
    }
    return false
  }

  func isImplicitMemberContextType(_ type: Type) -> Bool {
    switch type {
    case .structure, .`enum`, .genericStruct, .genericEnum:
      return true
    default:
      return false
    }
  }

  func normalizeBranchExpression(
    _ expr: TypedExpressionNode,
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    guard let expectedType else { return expr }
    if expr.type == .never {
      return expr
    }

    var normalized = expr
    if normalized.type != expectedType,
       let flavorConversion = makeReferenceFlavorConversion(normalized, expectedType: expectedType) {
      normalized = flavorConversion
    }
    if normalized.type != expectedType,
       let implicitDeref = makeImplicitDereference(normalized, expectedType: expectedType) {
      normalized = implicitDeref
    }
    normalized = try coerceLiteral(normalized, to: expectedType)

    if normalized.type == expectedType || canWidenMutableReference(normalized, expectedType: expectedType) {
      return normalized
    }

    // When the branch is being checked against an unresolved generic context
    // (for example a lambda return type flowing into a method-level generic),
    // keep the concrete branch type and let outer unification bind the generic.
    if context.containsGenericParameter(expectedType) {
      return normalized
    }

    if normalized.type == .error {
      return normalized
    }
    try handleError(SemanticError.typeMismatch(expected: expectedType.description, got: normalized.type.description))
    return normalized
  }

  // Pick a read-only common supertype when branches differ only by mutability.
  private func commonBranchSupertype(_ lhs: Type, _ rhs: Type) -> Type? {
    if typesEquivalentForComparison(lhs, rhs) { return lhs }
    switch (lhs, rhs) {
    case (.reference(let leftInner), .mutableReference(let rightInner)),
         (.mutableReference(let leftInner), .reference(let rightInner)):
      return typesEquivalentForComparison(leftInner, rightInner) ? .reference(inner: leftInner) : nil
    case (.pointer(let leftElem), .mutablePointer(let rightElem)),
         (.mutablePointer(let leftElem), .pointer(let rightElem)):
      return typesEquivalentForComparison(leftElem, rightElem) ? .pointer(element: leftElem) : nil
    case (.weakReference(let leftInner), .mutableWeakReference(let rightInner)),
         (.mutableWeakReference(let leftInner), .weakReference(let rightInner)):
      return typesEquivalentForComparison(leftInner, rightInner) ? .weakReference(inner: leftInner) : nil
    default:
      return nil
    }
  }

  private func mergeConditionalBranches(
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    expectedType: Type?
  ) throws -> (TypedExpressionNode, TypedExpressionNode?, Type) {
    guard var typedElse = elseBranch else {
      // Single-branch if must have Void or Never type in the then branch.
      // Without an else branch, the overall if-expression cannot carry a
      // value-producing tail expression.
      if thenBranch.type != .void && thenBranch.type != .never && thenBranch.type != .error {
        try handleError(SemanticError(.generic(
          "Single-branch 'if' must have Void or Never type in then branch, got '\(thenBranch.type.description)'"
        )))
      }
      return (thenBranch, nil, .void)
    }

    var typedThen = thenBranch
    var resultType: Type

    // A branch that already failed has no type to reconcile with the other.
    if typedThen.type == .error || typedElse.type == .error {
      return (typedThen, typedElse, .error)
    }
    if let implicitDeref = makeImplicitDereference(typedThen, expectedType: typedElse.type) {
      typedThen = implicitDeref
    }
    if let implicitDeref = makeImplicitDereference(typedElse, expectedType: typedThen.type) {
      typedElse = implicitDeref
    }
    if typesEquivalentForComparison(typedThen.type, typedElse.type) {
      resultType = typedThen.type
    } else if typedThen.type == .never {
      resultType = typedElse.type
    } else if typedElse.type == .never {
      resultType = typedThen.type
    } else if let mergedType = commonBranchSupertype(typedThen.type, typedElse.type) {
      typedThen = try coerceLiteral(typedThen, to: mergedType)
      typedElse = try coerceLiteral(typedElse, to: mergedType)
      if typedThen.type != mergedType || typedElse.type != mergedType {
        throw SemanticError.typeMismatch(
          expected: typedThen.type.description,
          got: typedElse.type.description
        )
      }
      resultType = mergedType
    } else {
      typedThen = try coerceLiteral(typedThen, to: typedElse.type)
      typedElse = try coerceLiteral(typedElse, to: typedThen.type)
      if typedThen.type == typedElse.type {
        resultType = typedThen.type
      } else if expectedType != nil {
        // The conditional is being checked against a declared type, and that
        // check is the one to act on: "expected Int, got Void" names the
        // problem the reader has to fix. Saying the branches disagree as well
        // is the same mistake from a second angle.
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

  private func mergeWhenCaseBodies(
    _ typedCases: [TypedMatchCase],
    sourceCases: [MatchCaseNode],
    expectedType: Type?
  ) throws -> ([TypedMatchCase], Type) {
    guard !typedCases.isEmpty else { return (typedCases, .void) }

    var normalizedCases = typedCases
    var mergedType: Type? = nil
    for index in normalizedCases.indices {
      let body = normalizedCases[index].body
      if body.type == .never {
        mergedType = mergedType ?? .never
        continue
      }

      guard let currentType = mergedType else {
        mergedType = body.type
        continue
      }

      if currentType == .never || currentType == body.type {
        mergedType = currentType == .never ? body.type : currentType
        continue
      }

      do {
        let bodyAsCurrent = try normalizeBranchExpression(body, expectedType: currentType)
        if bodyAsCurrent.type == currentType || canWidenMutableReference(bodyAsCurrent, expectedType: currentType) {
          normalizedCases[index] = TypedMatchCase(pattern: normalizedCases[index].pattern, guardExpr: normalizedCases[index].guardExpr, body: bodyAsCurrent)
          continue
        }
      } catch {
        // Fall through to common-supertype and reverse-coercion checks below.
      }

      if let supertype = commonBranchSupertype(currentType, body.type) {
        for previousIndex in normalizedCases.indices where previousIndex <= index {
          let previousBody = normalizedCases[previousIndex].body
          if previousBody.type == .never { continue }
          let coerced = try normalizeBranchExpression(previousBody, expectedType: supertype)
          normalizedCases[previousIndex] = TypedMatchCase(
            pattern: normalizedCases[previousIndex].pattern,
            guardExpr: normalizedCases[previousIndex].guardExpr,
            body: coerced
          )
        }
        mergedType = supertype
        continue
      }

      let candidateType = body.type
      var candidateCases = normalizedCases
      var canUseCandidateType = true
      for previousIndex in normalizedCases.indices where previousIndex < index {
        let previousBody = normalizedCases[previousIndex].body
        if previousBody.type == .never { continue }
        do {
          let coerced = try normalizeBranchExpression(previousBody, expectedType: candidateType)
          if coerced.type == candidateType || canWidenMutableReference(coerced, expectedType: candidateType) {
            candidateCases[previousIndex] = TypedMatchCase(
              pattern: candidateCases[previousIndex].pattern,
              guardExpr: candidateCases[previousIndex].guardExpr,
              body: coerced
            )
          } else {
            canUseCandidateType = false
            break
          }
        } catch {
          canUseCandidateType = false
          break
        }
      }
      if canUseCandidateType {
        normalizedCases = candidateCases
        mergedType = candidateType
        continue
      }

      // A branch that already failed has no type to disagree about.
      if currentType == .error || body.type == .error {
        mergedType = .error
        continue
      }
      throw SemanticError.typeMismatch(expected: currentType.description, got: body.type.description)
    }

    let resultType = mergedType ?? .void
    normalizedCases = try zip(normalizedCases, sourceCases).map { typedCase, sourceCase in
      let branchExpectedType = expectedType ?? resultType
      let normalizedBody = try normalizeBranchExpression(
        typedCase.body,
        expectedType: branchExpectedType
      )
      if normalizedBody.type != .never,
         normalizedBody.type != resultType,
         !canWidenMutableReference(normalizedBody, expectedType: resultType) {
        throw SemanticError.typeMismatch(
          expected: resultType.description,
          got: normalizedBody.type.description
        )
      }
      _ = sourceCase
      return TypedMatchCase(pattern: typedCase.pattern, guardExpr: typedCase.guardExpr, body: normalizedBody)
    }

    return (normalizedCases, resultType)
  }

  private func inferTypedIfPatternExpression(
    subject: ExpressionNode,
    pattern: PatternNode,
    thenBuilder: (ExpressionUsage) throws -> TypedExpressionNode,
    elseBranch: ExpressionNode?,
    expectedType: Type?,
    usage: ExpressionUsage
  ) throws -> TypedExpressionNode {
    var typedSubject = try inferTypedExpression(subject)

    var subjectType = typedSubject.type
    try rejectWeakPatternSubject(subjectType, pattern: pattern, span: pattern.span)
    if !untypedPatternRequiresRawSubject(pattern),
       let inner = dereferenceTargetType(of: subjectType) {
      subjectType = inner
    }

    // `?name` / `?TypeName(name)` unpacks a weak handle. The typed subject is
    // the upgrade intrinsic (so `Option[T]` gets instantiated); the pattern
    // stays `weakBinding` so MIR can extract the Some payload.
    if case .weakBinding(let bindName, _, let span) = pattern {
      guard let strongType = weakReferenceInnerType(typedSubject.type) else {
        throw SemanticError(.generic(
          "Weak binding pattern '?\(bindName)' requires a weak reference subject"
        ), span: span)
      }
      let upgradeType = genericEnumType(template: "Option", args: [strongType])
      let upgradeCall = TypedExpressionNode.intrinsicCall(
        .upgradeRef(val: typedSubject, resultType: upgradeType))
      let symbol = makeLocalSymbol(name: bindName, type: strongType, kind: .variable(.Value))
      let typedPattern = TypedPattern.weakBinding(symbol: symbol)
      typedSubject = upgradeCall
      let branchUsage: ExpressionUsage = usage == .statement ? .statement : .value
      let typedThen = try withNewScope {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
        }
        return try normalizeBranchExpression(try thenBuilder(branchUsage), expectedType: expectedType)
      }
      let typedElse: TypedExpressionNode?
      if let elseBranch {
        let elseUsage: ExpressionUsage = usage == .statement ? .statement : .value
        let rawElse: TypedExpressionNode
        if elseUsage == .statement {
          rawElse = try inferCheckedStatementBodyExpression(elseBranch)
        } else {
          rawElse = try inferTypedExpression(elseBranch, expectedType: expectedType)
        }
        typedElse = try normalizeBranchExpression(rawElse, expectedType: expectedType)
      } else {
        typedElse = nil
      }
      return .ifPatternExpression(
        subject: typedSubject,
        pattern: typedPattern,
        bindings: [(bindName, false, strongType)],
        thenBranch: typedThen,
        elseBranch: typedElse,
        type: typedThen.type
      )
    }

    let (typedPattern, bindings) = try checkPattern(pattern, subjectType: subjectType)
    let branchUsage: ExpressionUsage = usage == .statement ? .statement : .value
    let typedThen = try withNewScope {
      for symbol in extractPatternSymbols(from: typedPattern) {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
        }
      }
      return try normalizeBranchExpression(
        try thenBuilder(branchUsage),
        expectedType: expectedType
      )
    }

    let typedElse: TypedExpressionNode?
    if let elseBranch {
      var elseExpectedType = expectedType
      if elseExpectedType == nil,
         typedThen.type != .never,
         isImplicitMemberContextType(typedThen.type),
         branchNeedsExpectedTypeForImplicitMember(elseBranch) {
        elseExpectedType = typedThen.type
      }
      let elseUsage: ExpressionUsage = usage == .statement ? .statement : .value
      let rawElse: TypedExpressionNode
      if elseUsage == .statement {
        rawElse = try inferCheckedStatementBodyExpression(elseBranch)
      } else {
        rawElse = try inferTypedExpression(elseBranch, expectedType: elseExpectedType, usage: elseUsage)
      }
      typedElse = try normalizeBranchExpression(
        rawElse,
        expectedType: elseExpectedType
      )
    } else {
      typedElse = nil
    }

    let (mergedThen, mergedElse, mergedType) = try mergeConditionalBranches(
      thenBranch: typedThen,
      elseBranch: typedElse,
      expectedType: usage == .statement ? nil : expectedType
    )

    return .ifPatternExpression(
      subject: typedSubject,
      pattern: typedPattern,
      bindings: bindings,
      thenBranch: mergedThen,
      elseBranch: mergedElse,
      type: mergedType
    )
  }

  private func inferTypedWhilePatternStatement(
    subject: ExpressionNode,
    pattern: PatternNode,
    bodyBuilder: () throws -> TypedExpressionNode
  ) throws -> TypedStatementNode {
    let typedSubject = try inferTypedExpression(subject)

    var subjectType = typedSubject.type
    try rejectWeakPatternSubject(subjectType, span: pattern.span)
    if let inner = dereferenceTargetType(of: subjectType) {
      subjectType = inner
    }

    let (typedPattern, bindings) = try checkPattern(pattern, subjectType: subjectType)

    let savedInLoop = inLoop
    inLoop = true
    defer { inLoop = savedInLoop }

    let typedBody = try withNewScope {
      for symbol in extractPatternSymbols(from: typedPattern) {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
        }
      }
      return try bodyBuilder()
    }

    return .whilePatternStatement(
      subject: typedSubject,
      pattern: typedPattern,
      bindings: bindings,
      body: typedBody
    )
  }

  // MARK: - Condition Context Lowering for `is` Expressions

  /// Check whether an untyped PatternNode contains variable bindings.
  private func untypedPatternContainsBindings(_ pattern: PatternNode) -> Bool {
    switch pattern {
    case .variable,
         .weakBinding,
         .traitObjectTypeBinding:
      return true
    case .wildcard, .booleanLiteral, .integerLiteral, .negativeIntegerLiteral,
         .floatLiteral, .stringLiteral, .runeLiteral, .comparisonPattern, .traitObjectType,
         .nullLiteral:
      return false
    case .enumCase(_, let elements, _):
      return elements.contains { untypedPatternContainsBindings($0.pattern) }
    case .structPattern(_, let elements, _),
         .tuplePattern(let elements, _):
      return elements.contains { untypedPatternContainsBindings($0.pattern) }
    case .listPattern(let elements, _):
      return elements.contains { untypedPatternContainsBindings($0) }
    case .andPattern(let left, let right, _):
      return untypedPatternContainsBindings(left) || untypedPatternContainsBindings(right)
    case .orPattern(let left, let right, _):
      return untypedPatternContainsBindings(left) || untypedPatternContainsBindings(right)
    case .notPattern(let inner, _):
      return untypedPatternContainsBindings(inner)
    case .restPattern:
      return false
    }
  }

  // Not `private`: the when-statement path in TypeCheckerStatements gates its
  // subject auto-deref on the same predicate.
  func untypedPatternRequiresRawSubject(_ pattern: PatternNode) -> Bool {
    switch pattern {
    case .traitObjectType, .traitObjectTypeBinding:
      return true
    case .nullLiteral:
      // The pattern tests the POINTER itself; auto-deref would hand it the
      // pointee instead.
      return true
    case .enumCase(_, let elements, _),
         .structPattern(_, let elements, _),
         .tuplePattern(let elements, _):
      return elements.contains { untypedPatternRequiresRawSubject($0.pattern) }
    case .listPattern(let elements, _):
      return elements.contains { untypedPatternRequiresRawSubject($0) }
    case .andPattern(let left, let right, _),
         .orPattern(let left, let right, _):
      return untypedPatternRequiresRawSubject(left) || untypedPatternRequiresRawSubject(right)
    case .notPattern(let inner, _):
      return untypedPatternRequiresRawSubject(inner)
    case .variable,
         .weakBinding,
         .wildcard,
         .booleanLiteral,
         .integerLiteral,
         .negativeIntegerLiteral,
         .floatLiteral,
         .stringLiteral,
         .runeLiteral,
         .comparisonPattern,
         .restPattern:
      return false
    }
  }

  /// Check whether an untyped expression contains an `isExpression` with variable bindings.
  /// This is used to decide whether condition context lowering is needed.
  private func conditionContainsIsWithBindings(_ expr: ExpressionNode) -> Bool {
    switch expr {
    case .isExpression(_, let pattern, _):
      return untypedPatternContainsBindings(pattern)
    case .andExpression(let left, let right, _):
      return conditionContainsIsWithBindings(left) || conditionContainsIsWithBindings(right)
    case .orExpression(let left, let right, _):
      return conditionContainsIsWithBindings(left) || conditionContainsIsWithBindings(right)
    case .notExpression(let inner, _):
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
    case .andExpression(let left, let right, _), .orExpression(let left, let right, _):
      return conditionContainsIsExpression(left) || conditionContainsIsExpression(right)
    case .notExpression(let inner, _):
      return conditionContainsIsExpression(inner)
    default:
      return false
    }
  }

  /// The first `is` with variable bindings inside `expr`, if any.
  ///
  /// The rule is about a binding written in a pattern, so the violation is
  /// reported ON THAT `is` -- not on the `or` / `not` that happens to wrap it.
  private func firstIsWithBindings(_ expr: ExpressionNode) -> ExpressionNode? {
    switch expr {
    case .isExpression(_, let pattern, _):
      return untypedPatternContainsBindings(pattern) ? expr : nil
    case .andExpression(let left, let right, _), .orExpression(let left, let right, _):
      return firstIsWithBindings(left) ?? firstIsWithBindings(right)
    case .notExpression(let inner, _):
      return firstIsWithBindings(inner)
    default:
      return nil
    }
  }

  /// Validate that `or` branches do not contain `isExpression` with bindings.
  /// Reports a diagnostic error if found.
  private func checkOrBranchesForBindings(_ expr: ExpressionNode) throws {
    switch expr {
    case .orExpression(let left, let right, _):
      // Report on the `is` that carries the binding, not on the wrapping `or`.
      if let offending = firstIsWithBindings(left) ?? firstIsWithBindings(right) {
        throw SemanticError(
          .generic("Variable bindings in 'is' expression are not allowed in 'or' branches"),
          span: offending.span
        )
      }
    case .andExpression(let left, let right, _):
      // Recurse into `and` branches to find nested `or`
      try checkOrBranchesForBindings(left)
      try checkOrBranchesForBindings(right)
    case .notExpression(let inner, _):
      // Report on the `is` that carries the binding, not on the wrapping `not`.
      if let offending = firstIsWithBindings(inner) {
        throw SemanticError(
          .generic("Variable bindings in 'is' expression are not allowed under 'not'"),
          span: offending.span
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
    case .andExpression(let left, let right, _):
      return flattenAndChain(left) + flattenAndChain(right)
    default:
      return [expr]
    }
  }

  /// Type-check a `where` guard the way an if/while condition is checked:
  /// `is` conjuncts may bind, and the names stay visible to the rest of the
  /// guard and to the arm/loop body. The result is a typed `and`-spine of
  /// steps -- `isExpression` nodes and plain Bool exprs -- that MIR walks in
  /// order. Only the and-spine is walked; `or` / `not` keep their ordinary
  /// expression semantics, so an `is` buried in one of those is checked by the
  /// generic path and rejected there if it binds.
  func checkGuardExpression(_ guardExpr: ExpressionNode) throws -> TypedExpressionNode {
    // Same rule as if/while: bindings under expression `or` / `not` are
    // refused with the same two diagnostics.
    try checkOrBranchesForBindings(guardExpr)
    if !conditionContainsIsExpression(guardExpr) {
      let rawGuard = autoDereferenceValueContext(try inferTypedExpression(guardExpr))
      if rawGuard.type != .bool {
        throw SemanticError(
          .typeMismatch(expected: "Bool", got: rawGuard.type.description),
          span: guardExpr.span)
      }
      return rawGuard
    }

    let clauses = flattenAndChain(guardExpr)
    var folded: TypedExpressionNode?
    for clause in clauses {
      let step = try checkGuardStep(clause, guardExpr: guardExpr)
      if let acc = folded {
        folded = .andExpression(left: acc, right: step, type: .bool)
      } else {
        folded = step
      }
    }
    return folded ?? .booleanLiteral(value: false, type: .bool)
  }

  /// One conjunct of a guard's and-spine. `is` / `is not` become typed
  /// pattern tests that also bind; everything else is an ordinary Bool check.
  private func checkGuardStep(
    _ clause: ExpressionNode,
    guardExpr: ExpressionNode
  ) throws -> TypedExpressionNode {
    switch clause {
    case .isExpression(let subject, let pattern, _):
      return try checkGuardIsStep(subject: subject, pattern: pattern, negated: false)
    case .isNotExpression(let subject, let pattern, _):
      return try checkGuardIsStep(subject: subject, pattern: pattern, negated: true)
    default:
      let raw = autoDereferenceValueContext(try inferTypedExpression(clause))
      if raw.type != .bool {
        throw SemanticError(
          .typeMismatch(expected: "Bool", got: raw.type.description),
          span: guardExpr.span)
      }
      return raw
    }
  }

  /// A guard's `is` step: the subject is checked, the pattern binds its names
  /// into the guard's scope (visible to the rest of the guard and to the
  /// body), and the step is a typed pattern test. `is not` never binds.
  private func checkGuardIsStep(
    subject: ExpressionNode,
    pattern: PatternNode,
    negated: Bool
  ) throws -> TypedExpressionNode {
    var typedSubject = try inferTypedExpression(subject)

    // `?name` unpacks a weak handle: wrap the subject in the upgrade
    // intrinsic so `Option[T]` gets instantiated and the pattern matches on
    // the upgraded value.
    if case .weakBinding(let bindName, _, let span) = pattern {
      guard let strongType = weakReferenceInnerType(typedSubject.type) else {
        throw SemanticError(.generic(
          "Weak binding pattern '?\(bindName)' requires a weak reference subject"
        ), span: span)
      }
      let upgradeType = genericEnumType(template: "Option", args: [strongType])
      let upgradeCall = TypedExpressionNode.intrinsicCall(
        .upgradeRef(val: typedSubject, resultType: upgradeType))
      let symbol = makeLocalSymbol(name: bindName, type: strongType, kind: .variable(.Value))
      let weakPattern = TypedPattern.weakBinding(symbol: symbol)
      if negated {
        // `is not ?name` is allowed: the binding is unused (the pattern only
        // tests whether the object is dead).
        return .isNotExpression(subject: upgradeCall, pattern: weakPattern, type: .bool)
      }
      if let name = context.getName(symbol.defId) {
        try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
      }
      return .isExpression(subject: upgradeCall, pattern: weakPattern, type: .bool)
    }

    var subjectType = typedSubject.type
    try rejectWeakPatternSubject(subjectType, pattern: pattern, span: pattern.span)
    if !untypedPatternRequiresRawSubject(pattern),
       let inner = dereferenceTargetType(of: subjectType) {
      subjectType = inner
    }

    let (typedPattern, _) = try checkPattern(pattern, subjectType: subjectType)

    if negated {
      // is not always forbids variable bindings (negated match cannot safely bind)
      if patternContainsBindings(typedPattern) {
        throw SemanticError(
          .generic("Variable bindings are not allowed in 'is not' expression"),
          span: pattern.span)
      }
      return .isNotExpression(subject: typedSubject, pattern: typedPattern, type: .bool)
    }

    // Bind before the rest of the guard and the body are checked so the names
    // resolve, the same order the arm pattern takes.
    for symbol in extractPatternSymbols(from: typedPattern) {
      if let name = context.getName(symbol.defId) {
        try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
      }
    }
    return .isExpression(subject: typedSubject, pattern: typedPattern, type: .bool)
  }

  /// Lower an `if` condition that contains `isExpression` with bindings.
  /// Returns the lowered typed expression, or nil if no lowering is needed.
  func lowerIfConditionWithBindings(
    condition: ExpressionNode,
    thenBranch: ExpressionNode,
    elseBranch: ExpressionNode?,
    expectedType: Type?,
    usage: ExpressionUsage
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
        thenBuilder: { branchUsage in
          if branchUsage == .statement {
            return try self.inferCheckedStatementBodyExpression(thenBranch)
          }
          return try self.inferTypedExpression(thenBranch, expectedType: expectedType, usage: branchUsage)
        },
        elseBranch: elseBranch,
        expectedType: expectedType,
        usage: usage
      )
    }

    // Case 2: `and` chain containing `isExpression` with bindings
    let clauses = flattenAndChain(condition)

    func buildClauseChain(from index: Int) throws -> TypedExpressionNode {
      if index == clauses.count {
        if usage == .statement {
          return try inferCheckedStatementBodyExpression(thenBranch)
        }
        return try inferTypedExpression(thenBranch, expectedType: expectedType, usage: usage)
      }

      let clause = clauses[index]

      if case .isExpression(let subject, let pattern, _) = clause {
        return try inferTypedIfPatternExpression(
          subject: subject,
          pattern: pattern,
          thenBuilder: { _ in try buildClauseChain(from: index + 1) },
          elseBranch: elseBranch,
          expectedType: expectedType,
          usage: usage
        )
      }

      let typedCondition = try inferTypedExpression(clause)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      let typedThen = try buildClauseChain(from: index + 1)
      let branchExpectedType = expectedType ?? (typedThen.type == .never ? nil : typedThen.type)
      let typedElse = try elseBranch.map {
        if usage == .statement {
          return try inferCheckedStatementBodyExpression($0)
        }
        return try inferTypedExpression($0, expectedType: branchExpectedType, usage: .value)
      }
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
  func lowerWhileConditionWithBindings(
    condition: ExpressionNode,
    body: ExpressionNode
  ) throws -> TypedStatementNode? {
    guard conditionContainsIsExpression(condition) else {
      return nil
    }

    let savedInLoop = inLoop
    inLoop = true
    defer { inLoop = savedInLoop }

    let breakExpr = makeBreakBlock(span: condition.span)
    guard let loweredBody = try lowerIfConditionWithBindings(
      condition: condition,
      thenBranch: body,
      elseBranch: breakExpr,
      expectedType: nil,
      usage: .statement
    ) else {
      return nil
    }

    return .whileStatement(
      condition: .booleanLiteral(value: true, type: .bool),
      body: loweredBody
    )
  }

  // MARK: - Main Expression Type Inference
  
  /// 新增用于返回带类型的表达式的类型推导函数
  /// - Parameters:
  ///   - expr: 要推导类型的表达式节点
  ///   - expectedType: 可选的期望类型，用于隐式成员表达式等需要上下文类型的场景
  /// - Returns: 带类型信息的表达式节点
  func inferTypedExpression(
    _ expr: ExpressionNode,
    expectedType: Type? = nil,
    usage: ExpressionUsage = .value
  ) throws -> TypedExpressionNode {
    // Point span-less errors at the expression being checked, not at the
    // enclosing statement. An error inherits `currentSpan`, which the statement
    // checker set to the whole statement -- so `let _ = &1;` used to
    // blame `let ...` instead of the `&1` that is actually wrong.
    //
    // Restored on the way out, which is what keeps the call-argument case
    // intact: `takes_bytes_1(payload)` reports the CALLEE, because the argument
    // is checked and its span popped before the coercion that finds the
    // mismatch runs. Three tests pin that exact column.
    let outerSpan = currentSpan
    let exprSpan = expr.span
    if exprSpan.isKnown {
      currentSpan = exprSpan
    }
    defer { currentSpan = outerSpan }

    switch expr {
    case .castExpression(let typeNode, let innerExpr, _):
      return try inferAsCast(typeNode: typeNode, innerExpr: innerExpr)

    case .integerLiteral(let value, let literalSpan):
      // Synthesis has no expected type to aim at, so the literal defaults to
      // Int -- and is range-checked against that default. Skipping the check
      // here leaves an un-annotated literal unexamined until it reaches the C
      // compiler, which reports it far from the source line. When there IS an
      // expected type, the coerce path checks against that type instead; do not
      // check here too or the same literal is reported twice.
      if expectedType == nil {
        try checkIntegerLiteralRange(value: value, targetType: .int, span: literalSpan)
      }
      return .integerLiteral(value: value, type: .int)

    case .floatLiteral(let value, _):
      return .floatLiteral(value: value, type: .float64)

    case .stringLiteral(let value, _):
      return .stringLiteral(value: value, type: builtinStringType())

    case .runeLiteral(let value, _):
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

    case .booleanLiteral(let value, _):
      return .booleanLiteral(value: value, type: .bool)

    case .nullLiteral(let literalSpan):
      return try inferNullLiteral(span: literalSpan, expectedType: expectedType)

    case .emptyLiteral(let span):
      return try inferEmptyLiteral(span: span, expectedType: expectedType)

    case .collectionLiteral(let elements, let span):
      return try inferCollectionLiteral(elements: elements, span: span, expectedType: expectedType)

    case .dictLiteral(let entries, let span):
      return try inferDictLiteral(entries: entries, span: span, expectedType: expectedType)

    case .whenExpression(let subject, let cases, let span):
      if usage == .statement {
        let stmt = try inferStatementExpression(expr)
        let blockType: Type = statementCanFallThrough(stmt) ? .void : .never
        return .blockExpression(statements: [stmt], tailExpression: nil, type: blockType)
      }

      var typedSubject = try inferTypedExpression(subject)
      // Auto-deref subject type for pattern matching
      var subjectType = typedSubject.type
      // `?name` patterns on a weak reference: wrap the subject in the upgrade
      // intrinsic so `Option[T]` gets instantiated. The `weakBinding` typed
      // pattern then reads the Some payload from the upgrade result.
      if !cases.contains(where: { untypedPatternRequiresRawSubject($0.pattern) }) {
        switch subjectType {
        case .reference(let inner),
             .mutableReference(let inner),
             .borrowedReference(let inner),
             .mutableBorrowedReference(let inner):
          subjectType = inner
        default:
          break
        }
      }
      let hasWeakBinding = cases.contains { c in
        if case .weakBinding = c.pattern { return true }
        return false
      }
      if hasWeakBinding, let strongType = weakReferenceInnerType(typedSubject.type) {
        let upgradeType = genericEnumType(template: "Option", args: [strongType])
        typedSubject = TypedExpressionNode.intrinsicCall(
          .upgradeRef(val: typedSubject, resultType: upgradeType))
        subjectType = typedSubject.type
      }

      var typedCases: [TypedMatchCase] = []
      var sawFallthrough = false
      var allNever = true
      var runningExpectedType = expectedType

      for c in cases {
        let typedCase = try withNewScope {
          let (pattern, _) = try checkPattern(c.pattern, subjectType: subjectType)
          for symbol in extractPatternSymbols(from: pattern) {
            if let name = context.getName(symbol.defId) {
              try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
            }
          }
          // Arm guard: bindings are in scope; a false guard falls through.
          // Checked the way an if/while condition is: `is` conjuncts may bind,
          // and the names stay visible to the rest of the guard and to the
          // arm body.
          var typedGuard: TypedExpressionNode? = nil
          if let guardExpr = c.guardExpr {
            typedGuard = try checkGuardExpression(guardExpr)
          }
          // Use the current target's evolving type, if any, for subsequent arms.
          var branchExpectedType = expectedType
          if branchExpectedType == nil,
             branchNeedsExpectedTypeForImplicitMember(c.body) {
            branchExpectedType = runningExpectedType
          }
          let branchUsage: ExpressionUsage = usage == .statement ? .statement : .value
          let typedBody: TypedExpressionNode
          if let branchExpectedType {
            do {
              typedBody = try normalizeBranchExpression(
                try inferTypedExpression(c.body, expectedType: branchExpectedType, usage: branchUsage),
                expectedType: branchExpectedType
              )
            } catch {
              typedBody = try inferTypedExpression(c.body, usage: branchUsage)
            }
          } else {
            typedBody = try inferTypedExpression(c.body, usage: branchUsage)
          }
          return TypedMatchCase(pattern: pattern, guardExpr: typedGuard, body: typedBody)
        }
        if typedCase.body.type == .void {
          sawFallthrough = true
        }
        if typedCase.body.type != .never {
          allNever = false
        }
        if typedCase.body.type != .never,
           isImplicitMemberContextType(typedCase.body.type),
           usage != .statement {
          runningExpectedType = try mergeBranchResultTypes(runningExpectedType, typedCase.body.type, span: c.body.span)
        }
        typedCases.append(typedCase)
      }
      
      // Exhaustiveness checking. A guarded arm covers nothing: only
      // unguarded arms feed the coverage check.
      let patterns = typedCases.filter { $0.guardExpr == nil }.map { $0.pattern }
      let resolvedCases = resolveEnumCasesForExhaustiveness(subjectType)
      let checker = ExhaustivenessChecker(
        subjectType: subjectType,
        patterns: patterns,
        span: span,
        resolvedEnumCases: resolvedCases,
        context: context
      )
      try checker.check()
      
      let resultType: Type
      if usage == .statement {
        resultType = allNever ? .never : .void
      } else {
        let (mergedCases, mergedType) = try mergeWhenCaseBodies(
          typedCases,
          sourceCases: cases,
          expectedType: expectedType
        )
        typedCases = mergedCases
        resultType = mergedType
      }

      return .whenExpression(subject: typedSubject, cases: typedCases, type: resultType)

    case .identifier(let name, let nameSpan):
      if currentScope.isMoved(name) {
        throw SemanticError.variableMoved(name)
      }
      guard let resolvedInfo = currentScope.lookupWithInfo(name, sourceFile: currentSourceFile) else {
        // A name that does not exist is one problem among several a body may
        // have. Recording it and standing in for the value keeps the rest of
        // the body in view: the statements after this one, and the mistakes in
        // the statement this one sits in. A speculative query never gets here --
        // it re-throws instead of reporting.
        if currentScope.resolveType(name, sourceFile: currentSourceFile) != nil {
          try handleError(SemanticError(.generic(
            "Type '\(name)' cannot be used as an expression: types have no value"
          ), span: nameSpan))
        } else {
          // `it` names nothing now. Point at the form that does, rather than
          // leave a reader guessing where the implicit binding went.
          if name == "it" {
            try handleError(SemanticError(.generic(
              "Undefined variable: it (there is no implicit flow binding; name the payload with 'as name in ...')"
            ), span: nameSpan))
          } else {
            try handleError(SemanticError.undefinedVariable(name))
          }
        }
        return failedExpression()
      }

      let info = resolvedInfo

      let hasLocal = currentScope.lookupWithInfoLocal(name, sourceFile: currentSourceFile) != nil
      
      // 判断是否是全局符号（需要模块可见性检查）
      // 局部变量和参数：modulePath 为空且 sourceFile 为空
      // 全局符号：有 modulePath 或有 sourceFile（private 符号）
      let isGlobalSymbol = !info.modulePath.isEmpty || info.isPrivate || info.sourceFile != nil
      let symbolModulePath = isGlobalSymbol ? (info.modulePath.isEmpty ? currentModulePath : info.modulePath) : []
      
      // 模块可见性检查：其它模块的符号必须在当前文件通过 using 显式导入。
      if !symbolModulePath.isEmpty && !currentModulePath.isEmpty {
        // 检查符号是否可以从当前模块直接访问（传递符号名用于成员导入检查）
        if !canAccessSymbolDirectly(symbolModulePath: symbolModulePath, currentModulePath: currentModulePath, symbolName: name) {
          let spec = modulePathToUsingSpecifier(symbolModulePath)
          // The name is used more than once in a file; each unimported use is
          // a place the reader has to look at.
          try handleError(SemanticError(.generic("'\(name)' is defined in module '\(spec)'. Import it explicitly with using \"\(spec)\" { \(name) };"), span: nameSpan))
        }
      }
      
      let fallbackDefKind: DefKind = (!hasLocal && currentScope.isFunction(name, sourceFile: currentSourceFile)) ? .function : .variable
      // The identity of the use is the identity of the binding `lookupWithInfo`
      // just resolved. It used to fall back to `defIdMap.allocate(...)`, which
      // MINTED a fresh DefId for a global whose name `lookup` could not reach
      // (a cross-module name visible through the unqualified index): every use
      // of `exit` became a new declaration, and a foreign callee's call sites
      // stopped matching the one `.foreignFunction` global that carries the
      // bare C name. The allocate is gone; a resolved binding always has a
      // DefId, so no use can re-mint one.
      let defId = currentScope.lookup(name, sourceFile: currentSourceFile) ?? info.defId

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

    case .blockExpression(let statements, let tailExpression, _):
      currentBlockExpressionDepth += 1
      defer { currentBlockExpressionDepth -= 1 }
      return try withNewScope {
        let diagnosticsBeforeBlock = diagnosticCollector.errorCountValue

        // The trailing expression of a tail-less block in value position is the
        // block's PURPOSE, not a pointless statement -- the effect rule does
        // not speak for it. The block's void type is then free to disagree
        // with the expectation through the normal mismatch channels.
        var suppressTrailingEffect = false
        if tailExpression == nil, usage == .value, let expectedType,
          expectedType != .void, expectedType != .never, expectedType != .error,
          !statements.isEmpty
        {
          suppressTrailingEffect = true
        }
        let trailingIndex = statements.count - 1

        var typedStatements: [TypedStatementNode] = []
        var blockType: Type = .void
        var controlFlowTerminator: String? = nil

        for (index, stmt) in statements.enumerated() {
          if let controlFlowTerminator {
            throw SemanticError(
              .generic("unreachable statement after \(controlFlowTerminator)"),
              span: stmt.span
            )
          }

          var typedStmt: TypedStatementNode
          if suppressTrailingEffect, index == trailingIndex,
            case .expression(let lastValue, _) = stmt,
            !sourceExpressionIsControlForm(lastValue)
          {
            typedStmt = .expression(try inferTypedExpression(lastValue, usage: .statement))
          } else {
            typedStmt = try checkStatement(stmt)
          }
          typedStatements.append(typedStmt)

          if let terminator = statementTerminatorName(typedStmt) {
            controlFlowTerminator = terminator
          }
        }

        var typedTailExpression: TypedExpressionNode? = nil
        if let tailExpression {
          if let controlFlowTerminator {
            throw SemanticError(
              .generic("unreachable expression after \(controlFlowTerminator)"),
              span: tailExpression.span
            )
          }
          typedTailExpression = try inferTypedExpression(
            tailExpression,
            expectedType: usage == .value ? expectedType : nil,
            usage: .value
          )
          if usage == .value, let inferredTailExpression = typedTailExpression {
            typedTailExpression = try normalizeBranchExpression(
              inferredTailExpression,
              expectedType: expectedType
            )
          }
          blockType = typedTailExpression?.type ?? .void
        } else if controlFlowTerminator != nil {
          blockType = .never
        }

        // A block that already complained has no reliable type. `let x Int =
        // { 1; }` is ONE mistake -- the `;` turned the value into a statement
        // -- and the `expected Int, got Void` that would follow is that same
        // mistake said again at the binding.
        if diagnosticCollector.errorCountValue > diagnosticsBeforeBlock {
          blockType = .error
        }

        return .blockExpression(
          statements: typedStatements,
          tailExpression: typedTailExpression,
          type: blockType)
      }

    case .arithmeticExpression(let left, let op, let right, _):
      var (typedLeft, typedRight) = try inferJoinedBinaryOperands(
        left, right, expectedType: expectedType)

      // Allow numeric literals to coerce to the other operand type only for numeric ops.
      let leftIsNumeric = isIntegerType(typedLeft.type) || isFloatType(typedLeft.type)
      let rightIsNumeric = isIntegerType(typedRight.type) || isFloatType(typedRight.type)
      if leftIsNumeric && rightIsNumeric, typedLeft.type != typedRight.type {
        typedRight = try coerceLiteral(typedRight, to: typedLeft.type, span: right.span)
        if typedLeft.type != typedRight.type {
          typedLeft = try coerceLiteral(typedLeft, to: typedRight.type, span: left.span)
        }
      }

      return try buildArithmeticExpression(op: op, lhs: typedLeft, rhs: typedRight)

    case .comparisonExpression(let left, let op, let right, _):
      let (typedLeft, typedRight) = try inferJoinedBinaryOperands(
        left, right, expectedType: nil)
      return try buildTypedComparisonExpression(
        lhs: typedLeft, op: op, rhs: typedRight,
        leftSpan: left.span, rightSpan: right.span)

    case .comparisonChainExpression(let operands, let operators, let span):
      return try inferComparisonChainExpression(operands: operands, operators: operators, span: span)

    case .ifExpression(let condition, let thenBranch, let elseBranch, _):
      if usage == .statement {
        let stmt = try inferStatementExpression(expr)
        let blockType: Type = statementCanFallThrough(stmt) ? .void : .never
        return .blockExpression(statements: [stmt], tailExpression: nil, type: blockType)
      }

      // Check if condition contains `isExpression` with bindings → lower to ifPatternExpression
      if let lowered = try lowerIfConditionWithBindings(
        condition: condition,
        thenBranch: thenBranch,
        elseBranch: elseBranch,
        expectedType: expectedType,
        usage: usage
      ) {
        return lowered
      }

      let typedCondition = autoDereferenceValueContext(try inferTypedExpression(condition))
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      guard let elseBranch else {
        let typedThen = try inferCheckedStatementBodyExpression(thenBranch)
        return try buildTypedIfExpression(
          condition: typedCondition,
          thenBranch: typedThen,
          elseBranch: nil,
          expectedType: nil
        )
      }

      // Both branches are checked before either is reconciled against the
      // expected type. Normalising the `then` first would report the
      // conditional's type mismatch and never look inside the `else`, so a
      // pure statement sitting there went unmentioned.
      let branchExpectedType = expectedType
      let rawThen = try inferTypedExpression(
        thenBranch, expectedType: branchExpectedType, usage: .value)

      var nextExpectedType = expectedType
      if nextExpectedType == nil,
         rawThen.type != .never,
         isImplicitMemberContextType(rawThen.type),
         branchNeedsExpectedTypeForImplicitMember(elseBranch) {
        nextExpectedType = rawThen.type
      }
      let rawElse = try inferTypedExpression(
        elseBranch, expectedType: nextExpectedType, usage: .value)

      let typedThen = try normalizeBranchExpression(rawThen, expectedType: branchExpectedType)
      let typedElse = try normalizeBranchExpression(rawElse, expectedType: nextExpectedType)
      return try buildTypedIfExpression(
        condition: typedCondition,
        thenBranch: typedThen,
        elseBranch: typedElse,
        expectedType: expectedType
      )

    case .whileExpression:
      let stmt = try inferStatementExpression(expr)
      let blockType: Type = statementCanFallThrough(stmt) ? .void : .never
      return .blockExpression(statements: [stmt], tailExpression: nil, type: blockType)

    case .call(let callee, let arguments, _):
      return try inferCallExpression(callee: callee, arguments: arguments, expectedType: expectedType)

    case .andExpression(let left, let right, _):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .andExpression(left: typedLeft, right: typedRight, type: .bool)

    case .orExpression(let left, let right, _):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .orExpression(left: typedLeft, right: typedRight, type: .bool)

    case .unaryMinusExpression(let expr, _):
      let typedExpr = autoDereferenceValueContext(try inferTypedExpression(expr))
      if typedExpr.type.isPlainIntegerType {
        let zero: TypedExpressionNode = .integerLiteral(value: "0", type: typedExpr.type)
        return .arithmeticExpression(left: zero, op: .minus, right: typedExpr, type: typedExpr.type)
      }
      if typedExpr.type.isWrappingIntegerType {
        // Negation wraps like every other wrapping subtraction: MIN negates to
        // MIN, never a panic.
        let zero: TypedExpressionNode = .integerLiteral(value: "0", type: typedExpr.type)
        return .wrappingArithmeticExpression(left: zero, op: .minus, right: typedExpr, type: typedExpr.type)
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

    case .notExpression(let expr, _):
      let typedExpr = autoDereferenceValueContext(try inferTypedExpression(expr))
      if typedExpr.type != .bool {
        throw SemanticError.typeMismatch(expected: "Bool", got: typedExpr.type.description)
      }
      return .notExpression(expression: typedExpr, type: .bool)

    case .bitwiseExpression(let left, let op, let right, _):
      var (typedLeft, typedRight) = try inferJoinedBinaryOperands(
        left, right, expectedType: expectedType)

      // An operand that already failed has no type to compute with: stay
      // silent rather than pile a second complaint on the first.
      if typedLeft.type == .error || typedRight.type == .error {
        return failedExpression()
      }

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) {
          typedRight = try coerceLiteral(typedRight, to: typedLeft.type, span: right.span)
        }
        if typedLeft.type != typedRight.type, isIntegerType(typedRight.type) {
          typedLeft = try coerceLiteral(typedLeft, to: typedRight.type, span: left.span)
        }
      }

      if !typedLeft.type.isIntegerType || typedLeft.type != typedRight.type {
        throw SemanticError.typeMismatch(
          expected: "Matching Integer Types", got: "\(typedLeft.type) \(op) \(typedRight.type)")
      }
      return .bitwiseExpression(left: typedLeft, op: op, right: typedRight, type: typedLeft.type)

    case .bitwiseNotExpression(let expr, _):
      let typedExpr = try inferTypedExpression(expr)
      if !isIntegerScalarType(typedExpr.type) {
        throw SemanticError.typeMismatch(expected: "Integer Type", got: typedExpr.type.description)
      }
      return .bitwiseNotExpression(expression: typedExpr, type: typedExpr.type)

    case .derefExpression(let inner, _):
      let typedInner = try inferTypedExpression(inner)
      // The operand already objected about itself; a dereference of the
      // failure is a consequence, not a second mistake.
      if typedInner.type == .error {
        return failedExpression()
      }
      if let info = typedInner.type.indirectionCompatibilityInfo,
         let targetType = dereferenceTargetType(of: typedInner.type) {
        let spelledType: String
        switch (info.family, info.mutable) {
        case (.managedReference, false):
          spelledType = typedInner.type.containsBorrowedReference ? "borrowed ref" : "ref"
        case (.managedReference, true):
          spelledType = typedInner.type.containsBorrowedReference ? "borrowed mutable ref" : "mutable ref"
        case (.rawPointer, false):
          spelledType = "*"
        case (.rawPointer, true):
          spelledType = "*mutable"
        case (.weakReference, false):
          spelledType = "?"
        case (.weakReference, true):
          spelledType = "?mutable"
        }
        try requireDerefablePointee(targetType, operation: "*", spelledType: spelledType)
        if info.family == .rawPointer {
          return .unsafeDerefExpression(expression: typedInner, type: targetType)
        }
        return .derefExpression(expression: typedInner, type: targetType)
      } else {
        throw SemanticError.typeMismatch(
          expected: "Reference type",
          got: typedInner.type.description
        )
      }

    case .unsafeDerefExpression(let inner, _):
      let typedInner = try inferTypedExpression(inner)
      guard let info = typedInner.type.indirectionCompatibilityInfo,
            info.family == .rawPointer,
            let targetType = dereferenceTargetType(of: typedInner.type) else {
        throw SemanticError.typeMismatch(
          expected: "Pointer type",
          got: typedInner.type.description
        )
      }
      let spelledType = info.mutable ? "*mutable" : "*"
      try requireDerefablePointee(targetType, operation: "*", spelledType: spelledType)
      return .unsafeDerefExpression(expression: typedInner, type: targetType)

    case .addressOfExpression(let inner, let mutable, _):
      let typedInner = try inferTypedExpression(inner)

      if mutable && !canTakeMutableReference(to: typedInner) {
        let name = implicitSelfRefViolationName(typedInner) ?? String(describing: inner)
        throw SemanticError(.generic("Cannot take '&mutable' from immutable binding '\(name)'"), span: currentSpan)
      }

      let refType: Type = mutable ? .mutableReference(inner: typedInner.type) : .reference(inner: typedInner.type)
      return .referenceExpression(expression: typedInner, type: refType)

    case .ptrExpression(let inner, let mutable, _):
      let typedInner = try inferTypedExpression(inner)
      let isAddressable = typedInner.valueCategory == .lvalue || isDerefExpression(inner)
      if !isAddressable {
        if isLiteralExpression(inner) {
          throw SemanticError(.generic("cannot take & of literal"))
        }
        throw SemanticError(.generic("cannot take & of temporary value"))
      }
      if mutable && !canTakeMutableReference(to: typedInner) {
        let name = implicitSelfRefViolationName(typedInner) ?? String(describing: inner)
        throw SemanticError(.generic("Cannot take '&mutable' from immutable binding '\(name)'"), span: currentSpan)
      }
      let ptrType: Type = mutable
        ? .mutablePointer(element: typedInner.type)
        : .pointer(element: typedInner.type)
      return .ptrExpression(expression: typedInner, type: ptrType)

    case .upgradeExpr(let inner, _):
      // `?expr` upgrades a weak reference to `Option[T]`.
      let typedInner = try inferTypedExpression(inner)
      // The operand already objected about itself; the upgrade of the failure
      // is a consequence, not a second mistake.
      if typedInner.type == .error {
        return failedExpression()
      }
      let strongType: Type
      switch typedInner.type {
      case .weakReference(let innerType):
        strongType = innerType
      case .mutableWeakReference(let innerType):
        strongType = innerType
      default:
        throw SemanticError(.generic(
          "'?' expects a weak reference (?T), got \(typedInner.type.description)"
        ), span: currentSpan)
      }
      let resultType = genericEnumType(template: "Option", args: [strongType])
      return .intrinsicCall(.upgradeRef(val: typedInner, resultType: resultType))

    case .subscriptExpression(let base, let arguments, let span):
      let typedBase = try inferTypedExpression(base)
      let typedArguments = try arguments.map { try inferTypedExpression($0) }
      let resolvedSubscript = try resolveSubscript(
        base: typedBase,
        args: typedArguments,
        expectedType: expectedType,
        span: span
      )

      return resolvedSubscript

    case .genericMethodCall(let baseExpr, let methodTypeArgs, let methodName, let arguments, _):
      return try inferGenericMethodCallExpression(
        baseExpr: baseExpr,
        methodTypeArgs: methodTypeArgs,
        methodName: methodName,
        callArgs: arguments,
        expectedType: expectedType
      )

    case .qualifiedMethodCall(let base, let traitType, let methodName, let arguments, _):
      return try inferQualifiedMethodCallExpression(
        base: base,
        traitType: traitType,
        methodName: methodName,
        methodTypeArgs: nil,
        callArgs: arguments
      )

    case .qualifiedGenericMethodCall(let base, let traitType, let methodTypeArgs, let methodName, let arguments, _):
      return try inferQualifiedMethodCallExpression(
        base: base,
        traitType: traitType,
        methodName: methodName,
        methodTypeArgs: methodTypeArgs,
        callArgs: arguments
      )

    case .memberPath(let baseExpr, let path, _):
      return try inferMemberPathExpression(baseExpr: baseExpr, path: path)

    case .staticMethodCall(let typeName, let typeArgs, let methodName, let arguments, _):
      return try inferStaticMethodCallExpression(
        typeName: typeName,
        typeArgs: typeArgs,
        methodName: methodName,
        callArgs: arguments,
        expectedType: expectedType
      )

    case .typeReference(let typeNode, let span):
      // A bare parenthesized type head: `(*Int)`, `(?Box)`, `((T) -> R)`.
      // A type has no value -- the same objection the bare spelling gets.
      try handleError(SemanticError(.generic(
        "Type '\(typeNode)' cannot be used as an expression: types have no value"
      ), span: span))
      return failedExpression()

    case .typedStaticMethodCall(let typeNode, let methodName, let methodTypeArgs, let arguments, _):
      return try inferTypeStaticMethodCallExpression(
        typeNode: typeNode,
        methodName: methodName,
        methodTypeArgs: methodTypeArgs,
        callArgs: arguments,
        expectedType: expectedType
      )

    case .forExpression(let pattern, let iterable, let body, let guardExpr, _):
      return try inferForExpression(
        pattern: pattern, iterable: iterable, body: body, guardExpr: guardExpr)

    case .rangeExpression(let op, let left, let right, _):
      return try inferRangeExpression(
        operator: op,
        left: left,
        right: right,
        expectedType: expectedType
      )

    case .genericInstantiation(let base, let typeArgs, let span):
      // A generic instantiation standing alone is a type used as a value:
      // `let x = List[Foo];`. Types have no value -- the same objection the
      // bare spelling gets -- and the message names the resolved type. A
      // generic FUNCTION instantiation (`let f = wrap[String];`) is not a
      // type standing in for a value and keeps its own objection.
      if currentScope.lookupGenericStructTemplate(base) != nil
        || currentScope.lookupGenericEnumTemplate(base) != nil
        || visibleTraitInfo(base) != nil {
        let resolvedType = try resolveTypeNode(.generic(base: base, args: typeArgs, span: span))
        throw SemanticError(.generic(
          "Type '\(resolvedType)' cannot be used as an expression: types have no value"
        ), span: span)
      }
      throw SemanticError.invalidOperation(op: "use type as value", type1: base, type2: "")
      
    case .lambdaExpression(let parameters, let returnType, let body, let span):
      return try inferLambdaExpression(parameters: parameters, returnType: returnType, body: body, expectedType: expectedType, span: span)
      
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

    // The elided receiver of an `and then .member()` chain. It is only ever the
    // base of that chain, where the flow payload symbol is in scope under the
    // reserved name.
    case .flowReceiver(let span):
      return try inferTypedExpression(
        .identifier(TypeChecker.flowPayloadName, span: span),
        expectedType: expectedType,
        usage: usage
      )

    // Unwrapped by `and then` before checking; reaching here means the chain was
    // written somewhere else.
    case .flowChainExpression(_, let span):
      try handleError(SemanticError(
        .generic("an 'and then .member()' chain can only be the operand of 'and then'"),
        span: span
      ))
      return failedExpression()

    // `as name in body` is an operand of `and then` / `or else`, which unwrap it
    // and bind the name themselves. Reaching here means it was written elsewhere.
    case .flowBindExpression(_, _, let span):
      try handleError(SemanticError(
        .generic("'as ... in' can only be the operand of 'and then' or 'or else'"),
        span: span
      ))
      return failedExpression()

    case .isExpression(let subject, let pattern, _):
      // Type check the subject expression
      let typedSubject = try inferTypedExpression(subject)

      // Auto-deref subject type for pattern matching (consistent with `when`)
      var subjectType = typedSubject.type
      try rejectWeakPatternSubject(subjectType, pattern: pattern, span: pattern.span)
      if !untypedPatternRequiresRawSubject(pattern),
         let inner = dereferenceTargetType(of: subjectType) {
        subjectType = inner
      }

      // Check the pattern against the subject type
      let (typedPattern, _) = try checkPattern(pattern, subjectType: subjectType)

      // In non-condition context, variable bindings are not allowed
      if patternContainsBindings(typedPattern) {
        throw SemanticError(
          .generic("Variable bindings in 'is' expression are only allowed in if/while conditions and where guards"),
          span: currentSpan
        )
      }

      return .isExpression(subject: typedSubject, pattern: typedPattern, type: .bool)

    case .isNotExpression(let subject, let pattern, _):
      // Type check the subject expression
      var typedSubject = try inferTypedExpression(subject)

      // `w is not ?v` means the object is dead. Keep `weakBinding` with the
      // negation so MIR tests liveness directly (no Option enum resolution).
      if case .weakBinding(let bindName, _, let span) = pattern {
        guard let strongType = weakReferenceInnerType(typedSubject.type) else {
          throw SemanticError(.generic(
            "Weak binding pattern '?\(bindName)' requires a weak reference subject"
          ), span: span)
        }
        let upgradeType = genericEnumType(template: "Option", args: [strongType])
        let upgradeCall = TypedExpressionNode.intrinsicCall(
          .upgradeRef(val: typedSubject, resultType: upgradeType))
        let symbol = makeLocalSymbol(name: bindName, type: strongType, kind: .variable(.Value))
        let weakPattern = TypedPattern.weakBinding(symbol: symbol)
        return .isNotExpression(subject: upgradeCall, pattern: weakPattern, type: .bool)
      }

      // Auto-deref subject type for pattern matching (consistent with `when`)
      var subjectType = typedSubject.type
      try rejectWeakPatternSubject(subjectType, pattern: pattern, span: pattern.span)
      if !untypedPatternRequiresRawSubject(pattern),
         let inner = dereferenceTargetType(of: subjectType) {
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

  private func freshComparisonChainTempName() -> String {
    synthesizedTempIndex += 1
    return "__KORAL_cmp_chain_\(synthesizedTempIndex)"
  }

  /// Whether an expression is an integer literal in either spelling. These
  /// are the operands that join another operand's integer width before they
  /// are range-checked.
  private func isIntegerLiteralExpression(_ expr: ExpressionNode) -> Bool {
    if case .integerLiteral = expr { return true }
    return false
  }

  private func isNullLiteralExpression(_ expr: ExpressionNode) -> Bool {
    if case .nullLiteral = expr { return true }
    return false
  }

  /// Type a binary operator's operands so an integer literal is range-checked
  /// against the width it JOINS, not against its Int default.
  ///
  /// - Exactly one literal operand: the other operand types first and the
  ///   literal is checked against the other side's integer type (either
  ///   position: `x + big` and `big + x` alike).
  /// - Two literal operands with an integer expected type: both join that
  ///   width, which is what makes `let y UInt8 = 5 + 3` narrow.
  /// - A null literal joins the other operand's pointer type the same way.
  /// - Anything else keeps the source order and the Int default check.
  private func inferJoinedBinaryOperands(
    _ left: ExpressionNode,
    _ right: ExpressionNode,
    expectedType: Type?
  ) throws -> (TypedExpressionNode, TypedExpressionNode) {
    // A null literal is aimed at the other operand's type: a pointer joins
    // it; a non-pointer is the mismatch row with `null` on the got-side. With
    // no other operand to aim at (`null == null`) it stays unaimable.
    let leftIsNull = isNullLiteralExpression(left)
    let rightIsNull = isNullLiteralExpression(right)
    if leftIsNull != rightIsNull {
      let literal = leftIsNull ? left : right
      let other = leftIsNull ? right : left
      let typedOther = autoDereferenceValueContext(try inferTypedExpression(other))
      let typedLiteral = autoDereferenceValueContext(
        try inferTypedExpression(literal, expectedType: typedOther.type))
      return leftIsNull ? (typedLiteral, typedOther) : (typedOther, typedLiteral)
    }
    let leftIsLiteral = isIntegerLiteralExpression(left)
    let rightIsLiteral = isIntegerLiteralExpression(right)
    if leftIsLiteral != rightIsLiteral {
      let literal = leftIsLiteral ? left : right
      let other = leftIsLiteral ? right : left
      let typedOther = autoDereferenceValueContext(try inferTypedExpression(other))
      // An integer literal joins an INTEGER type only: a float other side is
      // no join at all, and the literal keeps its default check.
      let joinType: Type? = isIntegerType(typedOther.type) ? typedOther.type : nil
      let typedLiteral = autoDereferenceValueContext(
        try inferTypedExpression(literal, expectedType: joinType))
      return leftIsLiteral ? (typedLiteral, typedOther) : (typedOther, typedLiteral)
    }
    if leftIsLiteral, rightIsLiteral, let expectedType, isIntegerType(expectedType) {
      let typedLeft = try coerceLiteral(
        autoDereferenceValueContext(
          try inferTypedExpression(left, expectedType: expectedType)),
        to: expectedType, span: left.span)
      let typedRight = try coerceLiteral(
        autoDereferenceValueContext(
          try inferTypedExpression(right, expectedType: expectedType)),
        to: expectedType, span: right.span)
      return (typedLeft, typedRight)
    }
    let typedLeft = autoDereferenceValueContext(try inferTypedExpression(left))
    let typedRight = autoDereferenceValueContext(try inferTypedExpression(right))
    return (typedLeft, typedRight)
  }

  private func normalizeComparisonOperands(
    lhs initialLeft: TypedExpressionNode,
    rhs initialRight: TypedExpressionNode,
    leftSpan: SourceSpan? = nil,
    rightSpan: SourceSpan? = nil
  ) throws -> (TypedExpressionNode, TypedExpressionNode) {
    var typedLeft = initialLeft
    var typedRight = initialRight

    // Allow numeric literals to coerce to the other operand type.
    if typedLeft.type != typedRight.type {
      if isIntegerType(typedLeft.type) || isFloatType(typedLeft.type) {
        typedRight = try coerceLiteral(typedRight, to: typedLeft.type, span: rightSpan)
      }
      if typedLeft.type != typedRight.type,
        isIntegerType(typedRight.type) || isFloatType(typedRight.type)
      {
        typedLeft = try coerceLiteral(typedLeft, to: typedRight.type, span: leftSpan)
      }
    }

    // Allow rune literals to coerce to UInt8 in comparisons when needed.
    if typedLeft.type != typedRight.type {
      if typedLeft.type == .uint8 {
        typedRight = try coerceLiteral(typedRight, to: .uint8, span: rightSpan)
      }
      if typedRight.type == .uint8 {
        typedLeft = try coerceLiteral(typedLeft, to: .uint8, span: leftSpan)
      }
    }

    // Allow rune literals to coerce to Rune in comparisons.
    if typedLeft.type != typedRight.type {
      if isRuneType(typedLeft.type) {
        typedRight = try coerceLiteral(typedRight, to: typedLeft.type, span: rightSpan)
      }
      if typedLeft.type != typedRight.type, isRuneType(typedRight.type) {
        typedLeft = try coerceLiteral(typedLeft, to: typedRight.type, span: leftSpan)
      }
    }

    // Allow a typed null pointer to take the other operand's pointer type.
    if typedLeft.type != typedRight.type {
      let leftIsPointerLike: Bool = {
        switch typedLeft.type {
        case .pointer, .mutablePointer:
          return true
        default:
          return false
        }
      }()
      let rightIsPointerLike: Bool = {
        switch typedRight.type {
        case .pointer, .mutablePointer:
          return true
        default:
          return false
        }
      }()
      if leftIsPointerLike, case .intrinsicCall(.nullPtr) = typedRight {
        typedRight = try coerceLiteral(typedRight, to: typedLeft.type)
      } else if rightIsPointerLike, case .intrinsicCall(.nullPtr) = typedLeft {
        typedLeft = try coerceLiteral(typedLeft, to: typedRight.type)
      }
    }

    return (typedLeft, typedRight)
  }

  private func buildTypedComparisonExpression(
    lhs initialLeft: TypedExpressionNode,
    op: ComparisonOperator,
    rhs initialRight: TypedExpressionNode,
    leftSpan: SourceSpan? = nil,
    rightSpan: SourceSpan? = nil
  ) throws -> TypedExpressionNode {
    // An operand that already failed has no type to compare: stay silent
    // rather than pile a second complaint on the first.
    if initialLeft.type == .error || initialRight.type == .error {
      return failedExpression()
    }
    let (typedLeft, typedRight) = try normalizeComparisonOperands(
      lhs: initialLeft, rhs: initialRight,
      leftSpan: leftSpan, rightSpan: rightSpan)

    // Operator sugar for Eq: lower `==`/`!=` to `equals(self, other)`
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
    return .comparisonExpression(left: typedLeft, op: op, right: typedRight, type: resultType)
  }

  private func inferComparisonChainExpression(
    operands: [ExpressionNode],
    operators: [ComparisonOperator],
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    guard operands.count == operators.count + 1, operators.count >= 2 else {
      throw SemanticError(.generic("Invalid comparison chain"), span: span)
    }

    func buildChain(
      from index: Int,
      leftExpr: TypedExpressionNode,
      preTypedRight: TypedExpressionNode?,
      in typeChecker: TypeChecker
    ) throws -> TypedExpressionNode {
      let rawRight: TypedExpressionNode
      if let preTypedRight {
        rawRight = preTypedRight
      } else {
        // A literal operand joins the width of the value it is compared
        // against, so hand it that width instead of letting it default to
        // Int and be range-checked against the default. A null literal joins
        // the other side's pointer type the same way.
        let nextExpr = operands[index + 1]
        let joinType: Type? =
          typeChecker.isIntegerLiteralExpression(nextExpr) && typeChecker.isIntegerType(leftExpr.type)
          ? leftExpr.type
          : (typeChecker.isNullLiteralExpression(nextExpr)
             && {
               switch leftExpr.type {
               case .pointer, .mutablePointer: return true
               default: return false
               }
             }()
             ? leftExpr.type : nil)
        rawRight = typeChecker.autoDereferenceValueContext(
          try typeChecker.inferTypedExpression(nextExpr, expectedType: joinType)
        )
      }

      if index == operators.count - 1 {
        return try typeChecker.buildTypedComparisonExpression(
          lhs: leftExpr,
          op: operators[index],
          rhs: rawRight,
          leftSpan: operands[index].span,
          rightSpan: operands[index + 1].span
        )
      }

      let (normalizedLeft, normalizedRight) = try typeChecker.normalizeComparisonOperands(
        lhs: leftExpr,
        rhs: rawRight,
        leftSpan: operands[index].span,
        rightSpan: operands[index + 1].span
      )
      let tempSymbol = typeChecker.makeLocalSymbol(
        name: typeChecker.freshComparisonChainTempName(),
        type: normalizedRight.type,
        kind: .variable(.Value)
      )
      let tempRef: TypedExpressionNode = .variable(identifier: tempSymbol)
      let condition = try typeChecker.buildTypedComparisonExpression(
        lhs: normalizedLeft,
        op: operators[index],
        rhs: tempRef,
        leftSpan: operands[index].span,
        rightSpan: operands[index + 1].span
      )
      let next = try buildChain(
        from: index + 1, leftExpr: tempRef, preTypedRight: nil, in: typeChecker)
      let elseExpr: TypedExpressionNode = .booleanLiteral(value: false, type: .bool)

      return .blockExpression(
        statements: [
          .variableDeclaration(identifier: tempSymbol, value: normalizedRight, mutable: false),
        ],
        tailExpression: .ifExpression(
          condition: condition,
          thenBranch: next,
          elseBranch: elseExpr,
          type: .bool
        ),
        type: .bool
      )
    }

    // A leading integer literal joins the width of the operand it is compared
    // against, so that neighbour types first and its width is handed to the
    // literal. The neighbour is typed once and passed along as the first
    // step's right operand.
    var firstRight: TypedExpressionNode? = nil
    var firstLeft: TypedExpressionNode
    if isIntegerLiteralExpression(operands[0]), !isIntegerLiteralExpression(operands[1]) {
      let typedOther = autoDereferenceValueContext(try inferTypedExpression(operands[1]))
      let joinType: Type? = isIntegerType(typedOther.type) ? typedOther.type : nil
      firstLeft = autoDereferenceValueContext(
        try inferTypedExpression(operands[0], expectedType: joinType))
      firstRight = typedOther
    } else {
      firstLeft = autoDereferenceValueContext(try inferTypedExpression(operands[0]))
    }
    return try buildChain(
      from: 0, leftExpr: firstLeft, preTypedRight: firstRight, in: self)
  }

  private enum CollectionTargetKind {
    case list(element: Type)
    case set(element: Type)
    case map(key: Type, value: Type)
    case range(element: Type)
  }

  /// `null` -- a pointer literal. It has no type of its own: it JOINS the
  /// expected pointer type (`*T` or `*mutable T`, any pointee including a type
  /// parameter). With no expected type it cannot be aimed, and with a
  /// non-pointer expected type it is the ordinary mismatch row with the
  /// literal's spelling as the got-side.
  private func inferNullLiteral(span: SourceSpan, expectedType: Type?) throws -> TypedExpressionNode {
    guard let expectedType else {
      try handleError(
        SemanticError(
          .generic("Cannot infer a pointer type for 'null': add a type annotation"),
          span: span
        ))
      return failedExpression()
    }
    // An already-failed expected type disagrees with nothing: stay silent.
    if expectedType == .error {
      return failedExpression()
    }
    switch expectedType {
    case .pointer, .mutablePointer:
      return .intrinsicCall(.nullPtr(resultType: expectedType))
    default:
      try handleError(
        SemanticError(
          .typeMismatch(expected: expectedType.description, got: "null"),
          span: span
        ))
      return failedExpression()
    }
  }

  private func inferEmptyLiteral(span: SourceSpan, expectedType: Type?) throws -> TypedExpressionNode {
    guard let expectedType else {
      // One problem among several: record it and let the rest of the file be
      // checked.
      try handleError(
        SemanticError(
          .generic("Cannot infer type for empty collection literal '[]'. Add an explicit type annotation."),
          span: span
        ))
      return failedExpression()
    }

    guard let target = try classifyCollectionTarget(expectedType, span: span) else {
      return failedExpression()
    }
    switch target {
    case .list, .set, .map:
      return try buildWithCapacityCall(targetType: expectedType, count: 0)
    case .range(let elementType):
      // Generate Range[T].Full() enum construction
      let rangeType = genericEnumType(template: "Range", args: [elementType])
      return .enumConstruction(type: rangeType, caseName: "Full", arguments: [])
    }
  }

  private func inferCollectionLiteral(
    elements: [ExpressionNode],
    span: SourceSpan,
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    let target: CollectionTargetKind

    if let expectedType {
      guard let classified = try classifyCollectionTarget(expectedType, span: span) else {
        return failedExpression()
      }
      target = classified
    } else {
      let inferredElementType = try inferCommonElementType(elements: elements, span: span)
      target = .list(element: inferredElementType)
    }

    switch target {
    case .list(let elementType):
      let listType = genericStructType(template: "List", args: [elementType])
      return try lowerCollectionLiteral(
        targetType: listType,
        methodName: "push",
        elements: elements,
        argumentTypes: [elementType],
        duplicateWarningKind: nil,
        span: span
      )

    case .set(let elementType):
      let setType = genericStructType(template: "Set", args: [elementType])
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
    case .range:
      throw SemanticError(
        .generic("Range literal '...' cannot be used as a collection literal"),
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
      guard let target = try classifyCollectionTarget(expectedType, span: span) else {
        return failedExpression()
      }
      switch target {
      case .map(let k, let v):
        keyType = k
        valueType = v
      case .list, .set, .range:
        throw SemanticError(
          .generic("Dict literal can only be assigned to [K, V]Dict"),
          span: span
        )
      }
    } else {
      keyType = try inferCommonElementType(elements: entries.map { $0.key }, span: span)
      valueType = try inferCommonElementType(elements: entries.map { $0.value }, span: span)
    }

    let dictType = genericStructType(template: "Dict", args: [keyType, valueType])
    return try lowerDictLiteral(
      targetType: dictType,
      entries: entries,
      keyType: keyType,
      valueType: valueType,
      span: span
    )
  }

  private func classifyCollectionTarget(_ type: Type, span: SourceSpan) throws -> CollectionTargetKind? {
    switch type {
    case .genericStruct(let defId, let args):
      switch Type.spelling(defId) {
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
        try handleError(
          SemanticError(
            .generic("Collection literals only support built-in [T]List, [T]Set, [K, V]Dict, and [T]Range"),
            span: span
          ))
        return nil
      }

    case .genericEnum(let defId, let args):
      switch Type.spelling(defId) {
      case "Range":
        guard args.count == 1 else {
          throw SemanticError(.generic("[T]Range requires exactly one type argument"), span: span)
        }
        return .range(element: args[0])
      default:
        try handleError(
          SemanticError(
            .generic("Collection literals only support built-in [T]List, [T]Set, [K, V]Dict, and [T]Range"),
            span: span
          ))
        return nil
      }

    default:
      try handleError(
        SemanticError(
          .generic("Collection literals only support built-in [T]List, [T]Set, [K, V]Dict, and [T]Range"),
          span: span
        ))
      return nil
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
    case .int, .int8, .int16, .int32, .int64, .uint, .uint8, .uint16, .uint32, .uint64,
         .wrappingInt, .wrappingInt8, .wrappingInt16, .wrappingInt32, .wrappingInt64,
         .wrappingUInt, .wrappingUInt8, .wrappingUInt16, .wrappingUInt32, .wrappingUInt64:
      return .integerLiteral("0", span: .unknown)
    case .float32, .float64:
      return .floatLiteral("0.0", span: .unknown)
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

    guard let methodSym = try lookupDeclaredMethod(on: targetType, name: methodName) else {
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
        callArgs: [CallArg(expression: element)]
      )
      statements.append(.expression(typedCall))
    }

    let tailExpression = TypedExpressionNode.variable(identifier: temp)
    return .blockExpression(statements: statements, tailExpression: tailExpression, type: targetType)
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

    guard let methodSym = try lookupDeclaredMethod(on: targetType, name: "insert") else {
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
        callArgs: [CallArg(expression: entry.key), CallArg(expression: entry.value)]
      )
      statements.append(.expression(typedCall))
    }

    let tailExpression = TypedExpressionNode.variable(identifier: temp)
    return .blockExpression(statements: statements, tailExpression: tailExpression, type: targetType)
  }

  private func buildWithCapacityCall(targetType: Type, count: Int) throws -> TypedExpressionNode {
    let (typeName, typeArgs) = try staticTypeCallParts(for: targetType)
    return try inferStaticMethodCallExpression(
      typeName: typeName,
      typeArgs: typeArgs,
      methodName: "with_capacity",
      callArgs: [CallArg(expression: .integerLiteral("\(count)", span: .unknown))]
    )
  }

  private func staticTypeCallParts(for type: Type) throws -> (name: String, args: [TypeNode]) {
    switch type {
    case .genericStruct(let defId, let args):
      return (Type.spelling(defId), try args.map { try toTypeNode($0) })
    case .genericEnum(let defId, let args):
      return (Type.spelling(defId), try args.map { try toTypeNode($0) })
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
    case .int: return .identifier("Int", span: .unknown)
    case .int8: return .identifier("Int8", span: .unknown)
    case .int16: return .identifier("Int16", span: .unknown)
    case .int32: return .identifier("Int32", span: .unknown)
    case .int64: return .identifier("Int64", span: .unknown)
    case .uint: return .identifier("UInt", span: .unknown)
    case .uint8: return .identifier("UInt8", span: .unknown)
    case .uint16: return .identifier("UInt16", span: .unknown)
    case .uint32: return .identifier("UInt32", span: .unknown)
    case .uint64: return .identifier("UInt64", span: .unknown)
    case .wrappingInt: return .identifier("WrappingInt", span: .unknown)
    case .wrappingInt8: return .identifier("WrappingInt8", span: .unknown)
    case .wrappingInt16: return .identifier("WrappingInt16", span: .unknown)
    case .wrappingInt32: return .identifier("WrappingInt32", span: .unknown)
    case .wrappingInt64: return .identifier("WrappingInt64", span: .unknown)
    case .wrappingUInt: return .identifier("WrappingUInt", span: .unknown)
    case .wrappingUInt8: return .identifier("WrappingUInt8", span: .unknown)
    case .wrappingUInt16: return .identifier("WrappingUInt16", span: .unknown)
    case .wrappingUInt32: return .identifier("WrappingUInt32", span: .unknown)
    case .wrappingUInt64: return .identifier("WrappingUInt64", span: .unknown)
    case .float32: return .identifier("Float32", span: .unknown)
    case .float64: return .identifier("Float64", span: .unknown)
    case .bool: return .identifier("Bool", span: .unknown)
    case .void: return .identifier("Void", span: .unknown)
    case .never: return .identifier("Never", span: .unknown)
    case .reference(let inner): return .reference(try toTypeNode(inner), mutable: false, span: .unknown)
    case .mutableReference(let inner): return .reference(try toTypeNode(inner), mutable: true, span: .unknown)
    case .borrowedReference(let inner): return .reference(try toTypeNode(inner), mutable: false, span: .unknown)
    case .mutableBorrowedReference(let inner): return .reference(try toTypeNode(inner), mutable: true, span: .unknown)
    case .pointer(let inner): return .pointer(try toTypeNode(inner), mutable: false, span: .unknown)
    case .mutablePointer(let inner): return .pointer(try toTypeNode(inner), mutable: true, span: .unknown)
    case .weakReference(let inner): return .weakReference(try toTypeNode(inner), mutable: false, span: .unknown)
    case .mutableWeakReference(let inner): return .weakReference(try toTypeNode(inner), mutable: true, span: .unknown)
    case .genericParameter(let name): return .identifier(name, span: .unknown)
    case .genericStruct(let defId, let args):
      return .generic(base: Type.spelling(defId), args: try args.map { try toTypeNode($0) }, span: .unknown)
    case .genericEnum(let defId, let args):
      return .generic(base: Type.spelling(defId), args: try args.map { try toTypeNode($0) }, span: .unknown)
    case .structure(let defId), .`enum`(let defId), .opaque(let defId):
      guard let name = context.getName(defId) else {
        throw SemanticError(.generic("Unable to resolve type node name"), span: currentSpan)
      }
      return .identifier(name, span: .unknown)
    case .function(let params, let returns):
      let paramNodes = try params.map { try toTypeNode($0.type) }
      return .functionType(paramTypes: paramNodes, returnType: try toTypeNode(returns), span: .unknown)
    case .module, .typeVariable, .traitObject:
      throw SemanticError(.generic("Unsupported type in collection literal lowering: \(type.description)"), span: currentSpan)
    case .error:
      throw SemanticError(.generic("Unsupported type in collection literal lowering: \(type.description)"), span: currentSpan)
    }
  }

  private func extractCompileTimeConstantKey(from expr: ExpressionNode) -> String? {
    switch expr {
    case .integerLiteral(let value, _):
      return "int:\(value)"
    case .floatLiteral(let value, _):
      return "float:\(value)"
    case .stringLiteral(let value, _):
      return "string:\(value)"
    case .runeLiteral(let value, _):
      return "rune:\(value)"
    case .booleanLiteral(let value, _):
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
    let arguments = callArgs.compactMap { $0.expression }
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

    switch expected {
    case .enum, .genericEnum:
      if !isASCIITypeStyleIdentifier(memberName) {
        throw SemanticError(
          .generic("Enum case name '\(memberName)' must start with an uppercase letter"),
          span: span
        )
      }
    default:
      break
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
      
    case .genericEnum(let tplDefId, let typeArgs):
      // Look up the enum template and substitute type parameters
      guard let template = currentScope.genericEnumTemplate(defId: tplDefId) else {
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
        let resolvedParams: [(name: String, type: Type, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)] = try caseDef.parameters.map { param in
          let resolvedType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(param.type)
          }
          return (name: param.name, type: resolvedType, access: AccessModifier.public, named: param.named, defaultValue: param.defaultValue)
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
    let plan = try planConstructorArguments(
      callArgs,
      fieldNames: caseInfo.parameters.map { $0.name },
      fieldIsNamed: caseInfo.parameters.map { $0.named },
      fieldDefaults: caseInfo.parameters.map { $0.defaultValue },
      constructorDescription: ".\(memberName)",
      parentName: ""
    )
    let typedArgs = try typeCheckConstructorArguments(
      plan: plan,
      members: caseInfo.parameters.map { (name: $0.name, type: $0.type, named: $0.named, defaultValue: $0.defaultValue) },
      constructorDescription: ".\(memberName)",
      parentName: ""
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
      guard let methods = extensionMethods[context.methodOwner(of: expectedType)],
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
      guard typesEquivalentForComparison(returnType, expectedType) else {
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
        typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
      guard let methods = extensionMethods[context.methodOwner(of: expectedType)],
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
      guard typesEquivalentForComparison(returnType, expectedType) else {
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
        typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
      
    case .genericStruct(let tplDefId, let typeArgs):
      guard let extensions = genericExtensionMethods[context.methodOwner(of: expectedType)],
            let ext = extensions.first(where: { $0.method.name == memberName }) else {
        return nil
      }
      
      // Check if it's a static method
      let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
      guard isStatic else { return nil }
      
      // Resolve the method with type arguments
      let methodSym = try resolveGenericExtensionMethod(
        baseType: expectedType,
        templateName: Type.spelling(tplDefId),
        typeArgs: typeArgs,
        methodInfo: ext
      )
      
      guard case .function(let params, let returnType) = methodSym.type else {
        return nil
      }
      
      // Check if return type matches expected type (allowing Self substitution)
      guard typesEquivalentForComparison(returnType, expectedType) else {
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
        typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
      
    case .genericEnum(let tplDefId, let typeArgs):
      guard let extensions = genericExtensionMethods[context.methodOwner(of: expectedType)],
            let ext = extensions.first(where: { $0.method.name == memberName }) else {
        return nil
      }
      
      // Check if it's a static method
      let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
      guard isStatic else { return nil }
      
      // Resolve the method with type arguments
      let methodSym = try resolveGenericExtensionMethod(
        baseType: expectedType,
        templateName: Type.spelling(tplDefId),
        typeArgs: typeArgs,
        methodInfo: ext
      )
      
      guard case .function(let params, let returnType) = methodSym.type else {
        return nil
      }
      
      // Check if return type matches expected type (allowing Self substitution)
      guard typesEquivalentForComparison(returnType, expectedType) else {
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
        typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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

  private func resolveQualifiedTraitInvocation(
    _ traitType: TypeNode
  ) throws -> (traitName: String, traitDefId: DefId, traitTypeArgs: [Type]) {
    let traitConstraint = try SemaUtils.resolveTraitConstraint(from: traitType)
    let traitName = traitConstraint.baseName
    // Identity from the bound, not from a second lookup of its spelling.
    let traitDefId = resolveBound(traitConstraint).defId ?? .invalid

    guard let traitInfo = traits[traitName] else {
      throw SemanticError.undefinedType(traitName)
    }

    let traitTypeArgs: [Type]
    switch traitConstraint {
    case .mutable, .foreign:
      traitTypeArgs = []
    case .trait(_, _, let args):
      traitTypeArgs = try args.map { try resolveTypeNode($0) }
    }

    if traitInfo.typeParameters.count != traitTypeArgs.count {
      throw SemanticError.typeMismatch(
        expected: "\(traitInfo.typeParameters.count) generic arguments",
        got: "\(traitTypeArgs.count)"
      )
    }

    if !deferGenericConstraintValidation {
      try enforceGenericConstraints(typeParameters: traitInfo.typeParameters, args: traitTypeArgs)
    }

    return (traitName, traitDefId, traitTypeArgs)
  }

  /// The trait's method signature for `Self = selfType`, resolving the method
  /// from the trait's tool methods first and then its declared methods.
  private func qualifiedTraitMethodType(
    traitName: String,
    traitTypeArgs: [Type],
    methodName: String,
    selfType: Type,
    methodTypeArgs: [Type]?
  ) throws -> (parameters: [(name: String, named: Bool, defaultValue: ExpressionNode?)], functionType: Type) {
    // Bind the trait's own type parameters (e.g. `T` in `MyEq[T]`) so method
    // signatures mentioning them resolve against the invocation's trait args.
    return try withNewScope {
      if let info = traitInfo(traitName, modulePath: currentModulePath) {
        for (index, typeParam) in info.typeParameters.enumerated() where index < traitTypeArgs.count {
          try currentScope.defineType(typeParam.name, type: traitTypeArgs[index])
        }
      }
      return try resolveQualifiedTraitMethodType(
        traitName: traitName,
        traitTypeArgs: traitTypeArgs,
        methodName: methodName,
        selfType: selfType,
        methodTypeArgs: methodTypeArgs
      )
    }
  }

  private func resolveQualifiedTraitMethodType(
    traitName: String,
    traitTypeArgs: [Type],
    methodName: String,
    selfType: Type,
    methodTypeArgs: [Type]?
  ) throws -> (parameters: [(name: String, named: Bool, defaultValue: ExpressionNode?)], functionType: Type) {
    func substitute(_ functionType: Type, typeParams: [TypeParameterDecl]) throws -> Type {
      guard let methodTypeArgs, !methodTypeArgs.isEmpty else { return functionType }
      var substitution: [String: Type] = [:]
      for (typeParam, arg) in zip(typeParams, methodTypeArgs) {
        substitution[typeParam.name] = arg
      }
      return SemaUtils.substituteType(functionType, substitution: substitution, context: context)
    }

    if let tool = try flattenedTraitToolMethods(traitName)[methodName] {
      let functionType = try substitute(
        expectedFunctionTypeForToolMethod(tool, selfType: selfType),
        typeParams: tool.typeParameters
      )
      return (tool.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) }, functionType)
    }

    // `given[T] Trait[T] { ... }` tool methods register as generic extension
    // templates on the trait rather than as trait tool blocks.
    // The trait's spelling resolves to its declaration once here; the bucket is
    // keyed by that declaration.
    let traitOwner: MethodOwner =
      visibleTraitInfo(traitName).map { MethodOwner.decl($0.defId) } ?? methodOwnerForName(traitName)
        ?? .builtin(traitName)
    if let ext = genericExtensionMethods[traitOwner]?.first(where: { $0.method.name == methodName }) {
      let functionType = try substitute(
        expectedFunctionTypeForToolMethod(ext.method, selfType: selfType),
        typeParams: ext.method.typeParameters
      )
      return (ext.method.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) }, functionType)
    }

    let methods = try flattenedTraitMethods(traitName)
    guard let sig = methods[methodName] else {
      throw SemanticError(.generic(
        "Qualified method '\(methodName)' is not provided by trait '\(traitName)'"
      ), span: currentSpan)
    }
    let functionType = try substitute(
      expectedFunctionTypeForTraitMethod(
        sig,
        selfType: selfType,
        traitInfo: traitInfo(traitName, modulePath: currentModulePath),
        traitTypeArgs: traitTypeArgs
      ),
      typeParams: sig.typeParameters
    )
    return (sig.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) }, functionType)
  }

  /// Fully qualified call `Type(Trait).method(args...)`, conceptually Rust's
  /// `<Type as Trait>::method(args...)`.
  /// The type node a qualified-call base names, or nil when the base is an
  /// ordinary expression (the receiver-qualified form `expr(Trait).method`).
  private func qualifiedBaseTypeNode(_ expr: ExpressionNode) -> TypeNode? {
    switch expr {
    case .identifier(let name, let span):
      return isASCIITypeStyleIdentifier(name) ? .identifier(name, span: span) : nil
    case .genericInstantiation(let name, let typeArgs, let span):
      return .generic(base: name, args: typeArgs, span: span)
    default:
      return nil
    }
  }

  /// `Type(expr)` -- the explicit cast form of a type application. The parser
  /// leaves `Type(...)` as a call; the type checker routes builtin scalar
  /// targets here and structural targets to the constructor path. Only
  /// numeric conversion survives here: pointer reinterpretation and
  /// weak/trait casts are `expr as Type` now.
  private func inferTypeApplicationCast(
    targetType: Type,
    callArgs: [CallArg],
    span: SourceSpan
  ) throws -> TypedExpressionNode {
    guard callArgs.count == 1,
          let arg = callArgs.first,
          arg.label == nil,
          let innerExpr = arg.expression else {
      throw SemanticError(.generic(
        "A cast takes exactly one positional argument: write 'Type(expr)'"
      ), span: span)
    }
    if let optimized = try tryOptimizeLiteralCast(innerExpr, targetType: targetType) {
      return optimized
    }
    let typedInner = autoDereferenceValueContext(try inferTypedExpression(innerExpr))
    // A pointer source is reinterpretation, not numeric conversion: `UInt(p)`
    // is the retired spelling for `p as UInt`.
    if isPointerCastType(typedInner.type) {
      throw SemanticError(.generic(
        "Pointer and integer casts are written 'expr as Type', not 'Type(expr)'"
      ), span: span)
    }
    if !isValidExplicitCast(from: typedInner.type, to: targetType) {
      throw SemanticError.invalidOperation(
        op: "cast",
        type1: typedInner.type.description,
        type2: targetType.description
      )
    }
    // Cast always produces an rvalue.
    return .castExpression(expression: typedInner, type: targetType)
  }

  /// `(T)(args)` -- the call family keyed on the RESOLVED target type (aliases
  /// expanded), the parenthesized spelling of the bare `T(args)` dispatch.
  /// Nameable heads never reach here (they parse as the bare spelling's own
  /// nodes), so the rows left are pointer/weak (the retired cast spelling),
  /// the trait-object upcast, numeric conversion, and the wrong-target family.
  private func inferTypeReferenceCall(
    typeNode: TypeNode, callArgs: [CallArg], span: SourceSpan
  ) throws -> TypedExpressionNode {
    // `Self` has no cast meaning even where it resolves to a nominal.
    if case .inferredSelf = typeNode {
      throw SemanticError(.generic(
        "Type '\(typeNode)' does not support cast: only numeric and pointer types can be cast"
      ), span: span)
    }
    let targetType = try resolveTypeNode(typeNode)
    if isTraitObjectCastTarget(targetType) {
      return try inferTraitObjectUpcastCall(targetType: targetType, callArgs: callArgs, span: span)
    }
    if isPointerWeakOrTraitCastTarget(targetType) {
      throw SemanticError(.generic(
        "Pointer and weak casts are written 'expr as Type', not 'Type(expr)'"
      ), span: span)
    }
    if isIntegerScalarType(targetType) || isFloatScalarType(targetType) {
      return try inferTypeApplicationCast(targetType: targetType, callArgs: callArgs, span: span)
    }
    throw SemanticError(.generic(
      "Type '\(typeNode)' does not support cast: only numeric and pointer types can be cast"
    ), span: span)
  }

  /// `(*Foo).f(args)` -- a static call on a parenthesized type head with no
  /// nameable spelling. The resolved type decides, exactly as the nameable
  /// spellings do; a type with no such member reports the ordinary member
  /// error.
  private func inferTypeStaticMethodCallExpression(
    typeNode: TypeNode,
    methodName: String,
    methodTypeArgs: [TypeNode],
    callArgs: [CallArg],
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    let targetType = try resolveTypeNode(typeNode)
    if !methodTypeArgs.isEmpty {
      let resolvedMethodTypeArgs = try methodTypeArgs.map { try resolveTypeNode($0) }
      return try inferStaticGenericMethodCallOnConcreteType(
        baseType: targetType,
        methodName: methodName,
        callArgs: callArgs,
        explicitMethodTypeArgs: resolvedMethodTypeArgs,
        expectedType: expectedType
      )
    }
    return try inferConcreteTypeStaticMethodCall(
      type: targetType,
      typeName: typeNode.description,
      resolvedTypeArgs: [],
      methodName: methodName,
      callArgs: callArgs,
      expectedType: expectedType
    )
  }

  ///
  /// Two spellings share this composite node:
  ///   Type(Trait).method(args)  -- base names the self type; an instance
  ///     method's receiver is the first call argument, a static trait method
  ///     takes no receiver.
  ///   expr(Trait).method(args)  -- base IS the receiver; its type gives the
  ///     self type and it is not repeated in the arguments.
  func inferQualifiedMethodCallExpression(
    base: ExpressionNode,
    traitType: TypeNode,
    methodName: String,
    methodTypeArgs: [TypeNode]?,
    callArgs: [CallArg]
  ) throws -> TypedExpressionNode {
    let (traitName, resolvedTraitDefId, traitTypeArgs) = try resolveQualifiedTraitInvocation(traitType)

    // `Type(Trait).method(...)` names the self type on the left;
    // `expr(Trait).method(...)` IS the receiver, so its type is the self type
    // and it becomes the first argument.
    var preTypedReceiver: TypedExpressionNode? = nil
    let selfType: Type
    var effectiveArgs = callArgs
    if let typeNode = qualifiedBaseTypeNode(base) {
      selfType = try resolveTypeNode(typeNode)
    } else {
      let typedReceiver = try inferTypedExpression(base)
      preTypedReceiver = typedReceiver
      selfType = typedReceiver.type
      effectiveArgs.insert(CallArg(expression: base, span: base.span), at: 0)
    }
    let resolvedMethodTypeArgs = try methodTypeArgs.map { try $0.map { try resolveTypeNode($0) } }

    let declared = try qualifiedTraitMethodType(
      traitName: traitName,
      traitTypeArgs: traitTypeArgs,
      methodName: methodName,
      selfType: selfType,
      methodTypeArgs: resolvedMethodTypeArgs
    )
    guard case .function(let params, let returns) = declared.functionType else {
      throw SemanticError(.generic(
        "Expected function type for qualified method '\(methodName)'"
      ), span: currentSpan)
    }
    let hasSelf = declared.parameters.first?.name == "self"

    // Plan every argument — the receiver of an instance method is just the
    // method's first parameter.
    let paramMeta = callParamMeta(from: declared.parameters, argumentCount: params.count)
    let paramTypeKeys = params.map { $0.type.description }
    let arguments = try planCallArgumentExpressions(
      effectiveArgs,
      paramNames: paramMeta.names,
      paramIsNamed: paramMeta.isNamed,
      paramDefaults: paramMeta.defaults,
      callDescription: methodName,
      paramTypeKeys: paramTypeKeys
    )
    if arguments.count != params.count {
      throw SemanticError.invalidArgumentCount(
        function: methodName,
        expected: params.count,
        got: arguments.count
      )
    }

    var typedArguments: [TypedExpressionNode] = []
    for (index, (arg, param)) in zip(arguments, params).enumerated() {
      // The receiver-qualified form already type-checked its receiver to learn
      // the self type; do not check it a second time (it may move).
      var typedArg: TypedExpressionNode
      if index == 0, let receiver = preTypedReceiver {
        typedArg = receiver
      } else {
        typedArg = try inferTypedExpression(arg)
      }
      typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
      if typedArg.type != param.type {
        throw SemanticError.typeMismatch(
          expected: param.type.description,
          got: typedArg.type.description
        )
      }
      typedArguments.append(typedArg)
    }

    // A generic parameter receiver dispatches through the trait's vtable.
    if case .genericParameter(let paramName) = selfType {
      let hasBound = traitTypeArgs.isEmpty
        ? hasTraitBound(paramName, traitName)
        : hasTraitBound(paramName, traitName: traitName, traitTypeArgs: traitTypeArgs)
      guard hasBound else {
        let requiredTrait = canonicalTraitRef(traitName: traitName, traitTypeArgs: traitTypeArgs)
        throw SemanticError(.generic(
          "Type parameter '\(paramName)' does not have trait bound '\(requiredTrait)'"
        ), span: currentSpan)
      }
      guard hasSelf, let receiver = typedArguments.first else {
        throw SemanticError(.generic(
          "Qualified method '\(methodName)' on type parameter '\(paramName)' requires a receiver argument"
        ), span: currentSpan)
      }
      recordTraitPlaceholderInstantiation(
        baseType: selfType, methodName: methodName, methodTypeArgs: resolvedMethodTypeArgs ?? [])
      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: traitName,
        traitDefId: resolvedTraitDefId,
        traitMethodDefId: traitMethodDefId(traitDefId: resolvedTraitDefId, methodName: methodName) ?? .invalid,
        methodName: methodName,
        base: receiver,
        methodTypeArgs: resolvedMethodTypeArgs ?? [],
        type: declared.functionType
      )
      return .call(callee: callee, arguments: Array(typedArguments.dropFirst()), type: returns)
    }

    // Concrete type: a direct call to `Type`'s implementation of `Trait.method`.
    return .staticMethodCall(
      baseType: selfType,
      methodName: methodName,
      typeArgs: [],
      methodTypeArgs: resolvedMethodTypeArgs ?? [],
      arguments: typedArguments,
      type: returns
    )
  }

  
  /// Infers the type of a call expression
  func inferCallExpression(callee: ExpressionNode, arguments callArgs: [CallArg], expectedType: Type? = nil) throws -> TypedExpressionNode {
    if let chain = flattenDeepFluentMemberCallChain(callee: callee, callArgs: callArgs),
       let typedChain = try inferDeepFluentMemberCallChain(
        baseExpr: chain.baseExpr,
        segments: chain.segments,
        expectedType: expectedType
       ) {
      return typedChain
    }
    let arguments = callArgs.compactMap { $0.expression }
    
    if shouldRecoverCallSiteOnce {
      shouldRecoverCallSiteOnce = false
      if case .identifier(let name, _) = callee,
        let callSpan = bestEffortIdentifierCallSpan(name, startLine: currentSpan.start.line)
      {
        currentSpan = callSpan
      }
    }

    // Compiler protocol methods are blocked after concrete method resolution,
    // based on structural method kind metadata rather than name checks.
    // Static trait method calls on generic parameter types (e.g., T.method())
    if case .memberPath(let baseExpr, let path, _) = callee,
       case .identifier(let baseName, _) = baseExpr,
       path.count == 1,
       let baseType = currentScope.lookupType(baseName, sourceFile: currentSourceFile),
       case .genericParameter(let paramName) = baseType
    {
      let methodName = path[0]
      if let bounds = genericTraitBounds[paramName] {
        for traitConstraint in bounds {
          let traitName = traitConstraint.baseName
          let methods = try flattenedTraitMethods(traitName)
          if let sig = methods[methodName], sig.parameters.first?.name != "self" {
            let traitInfo = visibleTraitInfo(traitName)
            var traitTypeArgs: [Type] = []
            if case .trait(_, _, let argNodes) = traitConstraint {
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

            let traitStaticMeta = callParamMeta(
              from: sig.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) },
              argumentCount: params.count
            )
            let arguments = try planCallArgumentExpressions(
              callArgs,
              paramNames: traitStaticMeta.names,
              paramIsNamed: traitStaticMeta.isNamed,
              paramDefaults: traitStaticMeta.defaults,
              callDescription: methodName
            )

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
              typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
              typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
    if case .memberPath(let baseExpr, let path, _) = callee,
       case .genericInstantiation(let baseName, let args, _) = baseExpr,
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
        let baseType = genericStructType(template: baseName, args: resolvedArgs)
        
        // Look up static method on generic struct
        if let extensions = genericExtensionMethods[context.methodOwner(of: baseType)] {
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
                typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
        let baseType = genericEnumType(template: baseName, args: resolvedArgs)
        
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
          
          let plan = try planConstructorArguments(
            callArgs,
            fieldNames: c.parameters.map { $0.name },
            fieldIsNamed: c.parameters.map { $0.named },
            fieldDefaults: c.parameters.map { $0.defaultValue },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )
          let typedArgs = try typeCheckConstructorArguments(
            plan: plan,
            members: zip(c.parameters, resolvedParams).map { source, resolved in
              (name: source.name, type: resolved.type, named: source.named, defaultValue: source.defaultValue)
            },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )
          
          return .enumConstruction(type: baseType, caseName: memberName, arguments: typedArgs)
        }
        
        // Look up static method on generic enum
        if let extensions = genericExtensionMethods[context.methodOwner(of: baseType)] {
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
                typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
    if case .genericInstantiation(let base, let args, _) = callee {
      return try inferGenericInstantiationCall(base: base, args: args, arguments: arguments, callArgs: callArgs, span: callee.span)
    }

    // `(T)(args)` -- a parenthesized type head in call position goes through
    // the same resolved-target dispatch as the bare spellings.
    if case .typeReference(let typeNode, _) = callee {
      return try inferTypeReferenceCall(typeNode: typeNode, callArgs: callArgs, span: callee.span)
    }

    if case .memberPath(let baseExpr, let path, _) = callee,
       case .identifier(let baseName, _) = baseExpr,
       path.count == 1,
       let rawBaseType = currentScope.lookupType(baseName, sourceFile: currentSourceFile) {
      let memberName = path[0]
      let baseType = canonicalizedTypeForStaticMemberLookup(rawBaseType)

      switch baseType {
      case .`enum`(let defId):
        if let c = context.getEnumCases(defId)?.first(where: { $0.name == memberName }) {
          let resolvedParams = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
          let plan = try planConstructorArguments(
            callArgs,
            fieldNames: c.parameters.map { $0.name },
            fieldIsNamed: c.parameters.map { $0.named },
            fieldDefaults: c.parameters.map { $0.defaultValue },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )
          let typedArgs = try typeCheckConstructorArguments(
            plan: plan,
            members: zip(c.parameters, resolvedParams).map { source, resolved in
              (name: source.name, type: resolved.type, named: source.named, defaultValue: source.defaultValue)
            },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )
          return .enumConstruction(type: baseType, caseName: memberName, arguments: typedArgs)
        }
      case .genericEnum(let tplDefId, let typeArgs):
        if let template = currentScope.genericEnumTemplate(defId: tplDefId),
           let c = template.cases.first(where: { $0.name == memberName }) {
          var substitution: [String: Type] = [:]
          for (index, param) in template.typeParameters.enumerated() {
            substitution[param.name] = typeArgs[index]
          }

          let resolvedParams = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try c.parameters.map { param -> Parameter in
              let paramType = try resolveTypeNode(param.type)
              return Parameter(type: paramType, kind: .byVal)
            }
          }

          let plan = try planConstructorArguments(
            callArgs,
            fieldNames: c.parameters.map { $0.name },
            fieldIsNamed: c.parameters.map { $0.named },
            fieldDefaults: c.parameters.map { $0.defaultValue },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )
          let typedArgs = try typeCheckConstructorArguments(
            plan: plan,
            members: zip(c.parameters, resolvedParams).map { source, resolved in
              (name: source.name, type: resolved.type, named: source.named, defaultValue: source.defaultValue)
            },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )
          return .enumConstruction(type: baseType, caseName: memberName, arguments: typedArgs)
        }
      default:
        break
      }
    }

    // Check if callee is a generic enum constructor with type inference from expected type
    // e.g., Option.Some(42) when expected type is Option[Int]
    if case .memberPath(let baseExpr, let path, _) = callee,
       case .identifier(let baseName, _) = baseExpr,
       path.count == 1,
       let template = currentScope.lookupGenericEnumTemplate(baseName) {
      let memberName = path[0]

      if let expectedType = expectedType,
         case .genericEnum(let tplDefId, let expectedTypeArgs) = expectedType,
         tplDefId == template.defId {
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: expectedTypeArgs)
        
        if !expectedTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
          recordInstantiation(InstantiationRequest(
            kind: .enumType(template: template, args: expectedTypeArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }

        let type = genericEnumType(template: baseName, args: expectedTypeArgs)
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = expectedTypeArgs[i]
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

          let plan = try planConstructorArguments(
            callArgs,
            fieldNames: c.parameters.map { $0.name },
            fieldIsNamed: c.parameters.map { $0.named },
            fieldDefaults: c.parameters.map { $0.defaultValue },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )
          let typedArgs = try typeCheckConstructorArguments(
            plan: plan,
            members: zip(c.parameters, resolvedParams).map { source, resolved in
              (name: source.name, type: resolved.type, named: source.named, defaultValue: source.defaultValue)
            },
            constructorDescription: "\(baseName).\(memberName)",
            parentName: memberName
          )

          return .enumConstruction(type: type, caseName: memberName, arguments: typedArgs)
        }
      }
    }
    // Resolve Callee (Check Enum Constructor). This is a QUERY, not an
    // assertion: a name that fails it is still resolved below -- by a template,
    // a type, or an intrinsic -- so it must stay silent.
    var preResolvedCallee: TypedExpressionNode? = nil
    do {
      beginSpeculativeQuery()
      defer { endSpeculativeQuery() }
      do {
        preResolvedCallee = try inferTypedExpression(callee)
      } catch is SemanticError {
        // Fallthrough
        preResolvedCallee = nil
      }
    }

    if let resolved = preResolvedCallee, case .variable(let symbol) = resolved {
      if case .function(_, let returnType) = symbol.type {
        // Check for enum constructor (both concrete and generic)
        var enumName: String? = nil
        if case .`enum`(let defId) = returnType {
          enumName = context.getName(defId)
        } else if case .genericEnum(let tplDefId, _) = returnType {
          enumName = Type.spelling(tplDefId)
        }
        
        if let uName = enumName {
          // Check if symbol name is uName.CaseName
          let symbolName = context.getName(symbol.defId) ?? ""
          if symbolName.starts(with: uName + ".") {
            let caseName = String(symbolName.dropFirst(uName.count + 1))
            let params = symbol.type.functionParameters!
            let paramNames = try enumCaseFieldNames(enumType: returnType, caseName: caseName)
              ?? functionNamedParams[symbol.defId]?.map { $0.name }
              ?? params.enumerated().map { index, _ in "arg\(index)" }
            let paramIsNamed2 = try enumCaseFieldIsNamed(enumType: returnType, caseName: caseName)
              ?? functionNamedParams[symbol.defId]?.map { $0.named }
              ?? params.enumerated().map { _, _ in false }
            let paramDefaults2: [ExpressionNode?] = try enumCaseFieldDefaults(enumType: returnType, caseName: caseName)
              ?? functionNamedParams[symbol.defId]?.map { $0.defaultValue }
              ?? params.enumerated().map { _, _ in nil as ExpressionNode? }
            let plan = try planConstructorArguments(
              callArgs,
              fieldNames: paramNames,
              fieldIsNamed: paramIsNamed2,
              fieldDefaults: paramDefaults2,
              constructorDescription: symbolName,
              parentName: ""
            )
            let typedArgs = try typeCheckConstructorArguments(
              plan: plan,
              members: zip(paramNames, zip(paramIsNamed2, zip(paramDefaults2, params))).map { name, rest in
                (name: name, type: rest.1.1.type, named: rest.0, defaultValue: rest.1.0)
              },
              constructorDescription: symbolName,
              parentName: ""
            )

            return .enumConstruction(type: returnType, caseName: caseName, arguments: typedArgs)
          }
        }
      }
    }

    // Check if it is a constructor call OR implicit generic function call
    if case .identifier(let name, _) = callee {
      // 1. Try Generic Function Template (Implicit Inference)
      // A local binding of the same name shadows the template: `f(x)` where `f`
      // is a parameter or local `let` calls that value. Consulting the global
      // template table first would let any user declaration named `f` hijack
      // e.g. std's `map(self, f Func(T) U)`, whose parameter is called `f`.
      if !currentScope.isValueBinding(name, sourceFile: currentSourceFile),
         let template = visibleGenericFunctionTemplate(name) {
        try validateCallArgumentOrder(callArgs, functionName: name)
        return try inferImplicitGenericFunctionCall(
          template: template,
          name: name,
          callArgs: callArgs,
          expectedReturnType: expectedType
        )
      }

      if let type = currentScope.lookupType(name, sourceFile: currentSourceFile) {
        // `Type(expr)` on a builtin scalar is the explicit cast form. Cast and
        // construction share `Type(...)`; the type's kind decides which it is.
        if let resolvedType = currentScope.resolveType(name, sourceFile: currentSourceFile),
           isIntegerScalarType(resolvedType) || isFloatScalarType(resolvedType) {
          return try inferTypeApplicationCast(targetType: resolvedType, callArgs: callArgs, span: callee.span)
        }
        // A resolved pointer/weak/trait target is keyed on the RESOLVED type,
        // even when it arrives through an alias (`MyPtr(x)`). Pointer and weak
        // are the retired cast spelling; a trait is the explicit trait-object
        // upcast. Neither may fall into the construction path or the generic
        // message below.
        if let resolvedType = currentScope.resolveType(name, sourceFile: currentSourceFile),
           isPointerWeakOrTraitCastTarget(resolvedType) {
          if isTraitObjectCastTarget(resolvedType) {
            return try inferTraitObjectUpcastCall(
              targetType: resolvedType, callArgs: callArgs, span: callee.span)
          }
          throw SemanticError(.generic(
            "Pointer and weak casts are written 'expr as Type', not 'Type(expr)'"
          ), span: callee.span)
        }
        if case .opaque = type {
          throw SemanticError(.opaqueTypeCannotBeInstantiated(typeName: type.description), span: currentSpan)
        }
        guard case .structure(let defId) = type else {
          throw SemanticError(.generic(
            "Type '\(name)' does not support cast: only numeric and pointer types can be cast"
          ), span: callee.span)
        }
        let parameters = context.getStructMembers(defId) ?? []

        try ensureStructConstructionAccess(
          typeName: name,
          defId: defId,
          members: parameters,
          span: callee.span
        )
        let plan = try planConstructorArguments(
          callArgs,
          fieldNames: parameters.map { $0.name },
          fieldIsNamed: parameters.map { $0.named },
          fieldDefaults: parameters.map { $0.defaultValue },
          constructorDescription: name,
          parentName: name
        )
        let typedArguments = try typeCheckConstructorArguments(
          plan: plan,
          members: parameters.map { (name: $0.name, type: $0.type, named: $0.named, defaultValue: $0.defaultValue) },
          constructorDescription: name,
          parentName: name
        )

        return .typeConstruction(
          identifier: makeLocalSymbol(name: name, type: type, kind: .type),
          typeArgs: nil,
          arguments: typedArguments,
          type: type
        )
      }

      // A bare trait name in call position is the explicit trait-object
      // upcast: `Drawable(c)`.
      if visibleTraitInfo(name) != nil {
        let targetType = try resolveTypeNode(.identifier(name, span: callee.span))
        return try inferTraitObjectUpcastCall(
          targetType: targetType, callArgs: callArgs, span: callee.span)
      }

      // 2. Try Generic Struct/Enum Template (Implicit Type Inference)
      // Only for identifiers starting with uppercase (type naming convention)
      // This allows writing Stream(iter) instead of [T, R]Stream(iter)
      if isASCIITypeStyleIdentifier(name) {
        // Try generic struct template
        if let template = currentScope.lookupGenericStructTemplate(name) {
          return try inferGenericStructConstruction(template: template, name: name, callArgs: callArgs, span: callee.span)
        }
        
        // Try generic enum template (for enum case constructors without dot notation)
        // Note: This is less common since enum cases are usually accessed via .CaseName
      }
    }

    // Special handling for intrinsic function calls (alloc_memory, etc.)
    if case .identifier(let name, _) = callee {
      if let intrinsicNode = try checkIntrinsicCall(name: name, arguments: arguments) {
        return intrinsicNode
      }
    }

    // Nothing resolved the callee -- no constructor, no template, no intrinsic,
    // and no ordinary binding. That is one problem among several the body may
    // have, so it is recorded and the call stands in for its result: a
    // statement after this one may have a mistake of its own, and the one in
    // this call does not excuse it.
    var typedCallee: TypedExpressionNode
    do {
      typedCallee = try inferTypedExpression(callee)
    } catch let error as SemanticError {
      try handleError(error)
      return failedExpression()
    }
    if typedCallee.type == .error {
      // The callee has already objected about itself. The call stands in for
      // its result rather than complaining that a failed value is not
      // callable.
      return failedExpression()
    }

    // Secondary guard: if the resolved callee is a special compiler method, block explicit calls.
    if case .traitMethodPlaceholder(let traitName, let traitDefId, _, let methodName, _, _, _) = typedCallee,
       isStdDropTrait(traitDefId) && methodName == "drop" {
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
      try validateCallArgumentOrder(callArgs, functionName: "")
      return try inferMethodCall(
        base: base,
        method: method,
        methodType: methodType,
        callArgs: callArgs,
        expectedReturnType: expectedType
      )
    }

    // Trait method placeholder call (for trait methods on generic parameters)
    if case .traitMethodPlaceholder(let traitName, let traitDefId, let traitMethodDefId, let methodName, let base, let methodTypeArgs, let methodType) = typedCallee {
      // For trait method placeholders, we need to handle the call similarly to method calls
      // The base is already included in the placeholder, so we just need to type-check the arguments
      guard case .function(let params, let returns) = methodType else {
        throw SemanticError.invalidOperation(op: "call", type1: methodType.description, type2: "")
      }

      // The first parameter is 'self' (the base), so we check remaining arguments
      let expectedArgCount = params.count - 1
      let placeholderMethods = (try? flattenedTraitMethods(traitName)) ?? [:]
      var placeholderParams = placeholderMethods[methodName]?.parameters
      if placeholderParams == nil {
        // Tool (extension) methods are not in the trait DECLARATION's table;
        // their parameters carry the labels and defaults the planner needs.
        let toolMethods = (try? flattenedTraitToolMethods(traitName)) ?? [:]
        placeholderParams = toolMethods[methodName]?.parameters
      }
      let placeholderMeta = callParamMeta(
        from: placeholderParams?.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) } ?? [],
        argumentCount: expectedArgCount
      )
      let arguments = try planCallArgumentExpressions(
        callArgs,
        paramNames: placeholderMeta.names,
        paramIsNamed: placeholderMeta.isNamed,
        paramDefaults: placeholderMeta.defaults,
        callDescription: methodName
      )

      if arguments.count != expectedArgCount {
        throw SemanticError.invalidArgumentCount(
          function: "trait method",
          expected: expectedArgCount,
          got: arguments.count
        )
      }
      
      // Adjust base to match expected self parameter type
      let materializedReceiver: (symbol: Symbol, value: TypedExpressionNode)?
      var adjustedBase = base
      if let firstParam = params.first {
        let prepared = try prepareReceiverBase(adjustedBase, expectedType: firstParam.type, methodName: methodName)
        adjustedBase = prepared.base
        materializedReceiver = prepared.binding
      } else {
        materializedReceiver = nil
      }
      if let firstParam = params.first, adjustedBase.type != firstParam.type {
        adjustedBase = try coerceReceiverType(adjustedBase, expectedType: firstParam.type)
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
        } else if case .rangeExpression(let op, let left, let right, _) = arg {
          typedArg = try inferRangeExpression(
            operator: op,
            left: left,
            right: right,
            expectedType: param.type
          )
        } else {
          typedArg = try inferTypedExpression(arg, expectedType: param.type)
        }
        typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
        if typedArg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
      }
      
      // Keep the placeholder's OWN identity. Re-deriving `traitDefId` from
      // `traitName` here is what threw away the declaration and looked up
      // whichever trait of that spelling is registered first.
      let adjustedCallee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: traitName,
        traitDefId: traitDefId,
        traitMethodDefId: traitMethodDefId,
        methodName: methodName,
        base: adjustedBase,
        methodTypeArgs: methodTypeArgs,
        type: methodType
      )
      let call: TypedExpressionNode = .call(
        callee: adjustedCallee,
        arguments: typedArguments,
        type: returns
      )
      return wrapReceiverMaterialization(materializedReceiver, body: call, type: returns)
    }

    // Function call
    if case .function(let params, let returns) = typedCallee.type {
      // Free function / function value: plan labels + defaults through the
      // unified planner using the callee's declared parameter labels.
      let calleeDefId: DefId? = {
        if case .variable(let symbol) = typedCallee { return symbol.defId }
        return nil
      }()
      let calleeName = calleeDefId.flatMap { context.getName($0) } ?? "expression"
      let functionMeta: (names: [String], isNamed: [Bool], defaults: [ExpressionNode?]) = {
        if let calleeDefId {
          return callArgumentParamMeta(defId: calleeDefId, argumentCount: params.count)
        }
        return callParamMeta(from: [], argumentCount: params.count)
      }()
      let paramTypeKeys = params.map { $0.type.description }
      let arguments = try planCallArgumentExpressions(
        callArgs,
        paramNames: functionMeta.names,
        paramIsNamed: functionMeta.isNamed,
        paramDefaults: functionMeta.defaults,
        callDescription: calleeName,
        paramTypeKeys: paramTypeKeys
      )

      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: calleeName,
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
          } else if case .rangeExpression(let op, let left, let right, _) = arg {
            typedArg = try inferRangeExpression(
              operator: op,
              left: left,
              right: right,
              expectedType: param.type
            )
        } else {
          // Pass expected type for implicit member expression support
          typedArg = try inferTypedExpression(arg, expectedType: param.type)
        }
        typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
        if typedArg.type != param.type {
          typedArg = try coerceArgumentType(typedArg, expectedType: param.type)
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
  func inferGenericInstantiationCall(base: String, args: [TypeNode], arguments: [ExpressionNode], callArgs: [CallArg]? = nil, span: SourceSpan = .unknown) throws -> TypedExpressionNode {
    if let template = currentScope.lookupGenericStructTemplate(base) {
      try ensureStructConstructionAccess(
        typeName: base,
        defId: template.defId,
        members: template.parameters.map { param in
          (name: param.name, type: .void, mutable: param.mutable, access: param.access, named: param.named, defaultValue: param.defaultValue)
        },
        span: span
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
      try enforceGenericFunctionCallConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
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

      let plan = try planConstructorArguments(
        callArgs ?? arguments.map { CallArg(expression: $0) },
        fieldNames: template.parameters.map { $0.name },
        fieldIsNamed: template.parameters.map { $0.named },
        fieldDefaults: template.parameters.map { $0.defaultValue },
        constructorDescription: base,
        parentName: base
      )
      let typedArguments = try typeCheckConstructorArguments(
        plan: plan,
        members: zip(memberTypes, template.parameters).map { member, param in
          (name: member.name, type: member.type, named: false, defaultValue: param.defaultValue)
        },
        constructorDescription: base,
        parentName: base
      )
      
      // Return parameterized type
      let genericType = genericStructType(template: base, args: resolvedArgs)

      return .typeConstruction(
        identifier: makeLocalSymbol(name: base, type: genericType, kind: .type),
        typeArgs: resolvedArgs,
        arguments: typedArguments,
        type: genericType
      )
    } else if !currentScope.isValueBinding(base, sourceFile: currentSourceFile),
              let template = visibleGenericFunctionTemplate(base) {
      if let callArgs {
        try validateCallArgumentOrder(callArgs, functionName: "function call")
      }
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
          .allocMemory(count: countExpr, resultType: .mutablePointer(element: T)))
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
        guard case .mutablePointer(let elementType) = ptrExpr.type else {
          throw SemanticError(.generic("cannot use * on non-pointer type"))
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
        guard case .mutablePointer = ptrExpr.type else {
          throw SemanticError(.generic("cannot use * on non-pointer type"))
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
        guard case .mutablePointer(let elementType) = ptrExpr.type else {
          throw SemanticError(.generic("cannot use * on non-pointer type"))
        }
        try requireDerefablePointee(elementType, operation: "take_memory", spelledType: "*mutable")
        return .intrinsicCall(.takeMemory(ptr: ptrExpr))
      }

      if base == "downgrade" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        try enforceMutableConstraintForCall(resolvedArgs[0], function: "downgrade", span: arguments[0].span)
        let refArg = try inferArgumentExpression(arguments[0], expectedType: resolvedArgs[0])
        let resultType: Type = .weakReference(inner: refArg.type)
        return .intrinsicCall(.downgradeRef(val: refArg, resultType: resultType))
      }

      if base == "upgrade" {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        guard resolvedArgs.count == 1 else {
          throw SemanticError.typeMismatch(
            expected: "1 generic arg", got: "\(resolvedArgs.count)")
        }
        guard arguments.count == 1 else {
          throw SemanticError.invalidArgumentCount(
            function: base, expected: 1, got: arguments.count)
        }
        let weakArg = try inferArgumentExpression(arguments[0], expectedType: .weakReference(inner: resolvedArgs[0]))
        guard case .weakReference(let innerType) = weakArg.type else {
          throw SemanticError(.generic("'upgrade' expects a weak reference (?T), got \(weakArg.type)"), span: arguments[0].span)
        }
        let resultType: Type = genericEnumType(template: "Option", args: [innerType])
        return .intrinsicCall(.upgradeRef(val: weakArg, resultType: resultType))
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
      
      // Resolve parameter and return types with substitution. These names are
      // spelled in the callee's signature, not by the caller -- instantiating
      // `make_channel` must not demand `using "std/sync" { SendChannel }`.
      let (params, returnType) = try withNewScope {
        for (paramName, paramType) in substitution {
          try currentScope.defineType(paramName, type: paramType)
        }
        let outerSkipImport = skipImportVisibility
        skipImportVisibility = true
        defer { skipImportVisibility = outerSkipImport }
        let resolvedParams = try template.parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          return Parameter(type: paramType, kind: passKindForParameterType(paramType))
        }
        let resolvedReturn = try resolveTypeNode(template.returnType)
        return (resolvedParams, resolvedReturn)
      }

      let explicitGenericMeta = callParamMeta(
        from: template.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) },
        argumentCount: params.count
      )
      let arguments = try planCallArgumentExpressions(
        callArgs ?? arguments.map { CallArg(expression: $0) },
        paramNames: explicitGenericMeta.names,
        paramIsNamed: explicitGenericMeta.isNamed,
        paramDefaults: explicitGenericMeta.defaults,
        callDescription: base
      )

      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: base,
          expected: params.count,
          got: arguments.count
        )
      }

      var typedArguments: [TypedExpressionNode] = []
      for (arg, expectedParam) in zip(arguments, params) {
        // The resolved parameter type is the argument's aim: literal joins
        // (`null` at a `*T` parameter) need it before the coercion below.
        var typedArg = try inferTypedExpression(arg, expectedType: expectedParam.type)
        typedArg = try coerceLiteral(typedArg, to: expectedParam.type, span: arg.span)
        if typedArg.type != expectedParam.type && typedArg.type != .error && expectedParam.type != .error {
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
      // `Trait[Args](c)` -- the generic form of the explicit trait-object
      // upcast, keyed on the resolved target like every call-family row.
      if visibleTraitInfo(base) != nil {
        let targetType = try resolveTypeNode(.generic(base: base, args: args, span: span))
        return try inferTraitObjectUpcastCall(
          targetType: targetType,
          callArgs: callArgs ?? arguments.map { CallArg(expression: $0) },
          span: span)
      }
      throw SemanticError.functionNotFound(base)
    }
  }
  
  /// Infers the type of an implicit generic function call (type arguments inferred from arguments)
  func inferImplicitGenericFunctionCall(
    template: GenericFunctionTemplate,
    name: String,
    callArgs: [CallArg],
    expectedReturnType: Type? = nil
  ) throws -> TypedExpressionNode {
    // Plan call arguments through the unified planner (labels + defaults).
    let genericMeta = callParamMeta(
      from: template.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) },
      argumentCount: template.parameters.count
    )
    let paramTypeKeys = template.parameters.map { $0.type.description }
    let arguments = try planCallArgumentExpressions(
      callArgs,
      paramNames: genericMeta.names,
      paramIsNamed: genericMeta.isNamed,
      paramDefaults: genericMeta.defaults,
      callDescription: name,
      paramTypeKeys: paramTypeKeys
    )

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

    // The weak intrinsics read their single argument's type directly. Only
    // they get this early look: inferring the argument speculatively, before
    // the per-parameter pass below hands it its expected type, would aim a
    // pointer literal at nothing.
    if arguments.count == 1, name == "downgrade" || name == "upgrade" {
      let typedArgument = try inferTypedExpression(arguments[0])

      if name == "downgrade" {
        // downgrade takes a managed value T (must satisfy 'mutable' constraint) and produces ?T
        try enforceMutableConstraintForCall(typedArgument.type, function: "downgrade", span: arguments[0].span)
        let resultType: Type = .weakReference(inner: typedArgument.type)
        return .intrinsicCall(.downgradeRef(val: typedArgument, resultType: resultType))
      }

      if name == "upgrade" {
        switch typedArgument.type {
        case .weakReference(let innerType):
          let resultType: Type = genericEnumType(template: "Option", args: [innerType])
          return .intrinsicCall(.upgradeRef(val: typedArgument, resultType: resultType))
        default:
          throw SemanticError(.generic("'upgrade' expects a weak reference (?T), got \(typedArgument.type)"), span: arguments[0].span)
        }
      }

    }

    var typedArguments: [TypedExpressionNode] = []
    for (argExpr, param) in zip(arguments, template.parameters) {
      let expectedType = try resolveTemplateTypeNode(param.type, inferredBindings: inferred)
      var typedArg: TypedExpressionNode
      if case .genericParameter = expectedType {
        typedArg = try inferTypedExpression(argExpr)
      } else {
        typedArg = try inferTypedExpression(argExpr, expectedType: expectedType)
      }
      typedArg = try coerceLiteral(typedArg, to: expectedType, span: argExpr.span)
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
      let typedArg = try inferArgumentExpression(argExpr, expectedType: expectedType)
      finalTypedArguments.append(typedArg)
    }
    typedArguments = finalTypedArguments

    let templateName = template.name(in: defIdMap) ?? ""
    if templateName == "init_memory" {
      guard case .mutablePointer(let elementType) = typedArguments[0].type else {
        throw SemanticError(.generic("cannot use * on non-pointer type"))
      }
      let val = typedArguments[1]
      if val.type != elementType {
        throw SemanticError.typeMismatch(
          expected: elementType.description, got: val.type.description)
      }
      return .intrinsicCall(.initMemory(ptr: typedArguments[0], val: val))
    }
    if templateName == "deinit_memory" {
      guard case .mutablePointer = typedArguments[0].type else {
        throw SemanticError(.generic("cannot use * on non-pointer type"))
      }
      return .intrinsicCall(.deinitMemory(ptr: typedArguments[0]))
    }
    if templateName == "take_memory" {
      guard case .mutablePointer(let elementType) = typedArguments[0].type else {
        throw SemanticError(.generic("cannot use * on non-pointer type"))
      }
      try requireDerefablePointee(elementType, operation: "take_memory", spelledType: "*mutable")
      return .intrinsicCall(.takeMemory(ptr: typedArguments[0]))
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
    if templateName == "downgrade" {
      // downgrade takes a managed value T (must satisfy 'mutable' constraint) and produces ?T
      let refValue = typedArguments[0]
      try enforceMutableConstraintForCall(refValue.type, function: "downgrade", span: arguments[0].span)
      let resultType: Type = .weakReference(inner: refValue.type)
      return .intrinsicCall(.downgradeRef(val: refValue, resultType: resultType))
    }

    if templateName == "upgrade" {
      let weakValue = typedArguments[0]
      guard case .weakReference(let innerType) = weakValue.type else {
        throw SemanticError(.generic("'upgrade' expects a weak reference (?T), got \(weakValue.type)"), span: arguments[0].span)
      }
      let resultType: Type = genericEnumType(template: "Option", args: [innerType])
      return .intrinsicCall(.upgradeRef(val: weakValue, resultType: resultType))
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
    try enforceGenericFunctionCallConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
    try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
    
    // Resolve return type with substitution -- again a name from the callee's
    // signature, so the caller need not have imported it.
    let returnType = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      let outerSkipImport = skipImportVisibility
      skipImportVisibility = true
      defer { skipImportVisibility = outerSkipImport }
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
    callArgs: [CallArg],
    expectedReturnType: Type? = nil
  ) throws -> TypedExpressionNode {
    let methodName = context.getName(method.defId) ?? "<unknown>"
    if case .function(let params, let returns) = method.type {
      // Plan call arguments through the unified planner so that labels are
      // matched against the declared parameter labels and omitted named
      // parameters are filled from their declared defaults.
      let argumentCount = params.count - 1
      let paramMeta = methodCallParamMeta(
        ownerTypeName: methodLabelKey(base.type),
        methodName: methodName,
        fallbackDefId: method.defId,
        argumentCount: argumentCount
      )
      let paramTypeKeys = params.map { $0.type.description }
      let ownerKey: String = {
        switch base.type {
        case .structure(let defId): return context.getName(defId) ?? ""
        case .enum(let defId): return context.getName(defId) ?? ""
        case .traitObject(let defId, _): return context.getName(defId) ?? ""
        default: return ""
        }
      }()
      let arguments = try planCallArgumentExpressions(
        callArgs,
        paramNames: paramMeta.names,
        paramIsNamed: paramMeta.isNamed,
        paramDefaults: paramMeta.defaults,
        callDescription: methodName,
        paramTypeKeys: paramTypeKeys
      )

      if arguments.count != params.count - 1 {
        throw SemanticError.invalidArgumentCount(
          function: methodName,
          expected: params.count - 1,
          got: arguments.count
        )
      }

      // Check if this is a trait object method call (dynamic dispatch).
      // The base type is a trait object (or reference to one) — handle before auto-ref/deref.
      // Check if this is a trait object method call (dynamic dispatch).
      // The base type is a trait object (or reference to one) — handle before auto-ref/deref.
      switch base.type {
      case .reference(let inner), .mutableReference(let inner):
        if case .traitObject(let tplDefId, _) = inner {
          return try inferTraitObjectMethodCall(
            base: base,
            traitName: Type.spelling(tplDefId),
            methodName: methodName,
            params: params,
            returns: returns,
            arguments: arguments
          )
        }
      case .traitObject(let tplDefId, _):
        return try inferTraitObjectMethodCall(
          base: base,
          traitName: Type.spelling(tplDefId),
          methodName: methodName,
          params: params,
          returns: returns,
          arguments: arguments
        )
      default:
        break
      }

      let materializedReceiver: (symbol: Symbol, value: TypedExpressionNode)?
      var finalBase = base
      if let firstParam = params.first {
        let prepared = try prepareReceiverBase(finalBase, expectedType: firstParam.type, methodName: methodName)
        finalBase = prepared.base
        materializedReceiver = prepared.binding
        if finalBase.type != firstParam.type {
          // Allow passing mutable refs to readonly ref receivers.
          let coercedBase = try coerceLiteral(finalBase, to: firstParam.type)
          if coercedBase.type == firstParam.type {
            finalBase = coercedBase
          }
          else {
            finalBase = try coerceReceiverType(finalBase, expectedType: firstParam.type)
          }
        }
      } else {
        materializedReceiver = nil
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
          let typedArg: TypedExpressionNode
          if case .rangeExpression(let op, let left, let right, _) = arg {
            typedArg = try inferRangeExpression(
              operator: op,
              left: left,
              right: right,
              expectedType: param.type
            )
          } else {
            typedArg = try inferTypedExpression(arg, expectedType: param.type)
          }
          let coercedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
        } else if case .rangeExpression(let op, let left, let right, _) = arg {
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
          typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)

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
            // Only allow reference flavor conversion and mutable ref widening.
            // No implicit ref promotion (T → ref T) or auto-deref (ref T → T).
            if let flavorConversion = makeReferenceFlavorConversion(typedArg, expectedType: effectiveParamType) {
              typedArg = flavorConversion
            } else if canWidenMutableReference(typedArg, expectedType: effectiveParamType) {
              // ref mutable → ref widening: pass through unchanged
            } else {
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
      var finalMethodType = methodType
      // Convert bindings to array of types in order (for methodTypeArgs)
      var inferredMethodTypeArgs: [Type]? = nil
      if hasMethodLevelGenerics {
        if !methodTypeParamBindings.isEmpty {
          finalReturns = SemaUtils.substituteType(returns, substitution: methodTypeParamBindings, context: context)
          finalMethodType = SemaUtils.substituteType(methodType, substitution: methodTypeParamBindings, context: context)
        }

        if methodTypeParamBindings.isEmpty,
           let expectedReturnType,
           context.containsGenericParameter(returns)
        {
          _ = unifyTypes(returns, expectedReturnType, bindings: &methodTypeParamBindings)
          if !methodTypeParamBindings.isEmpty {
            finalReturns = SemaUtils.substituteType(returns, substitution: methodTypeParamBindings, context: context)
            finalMethodType = SemaUtils.substituteType(methodType, substitution: methodTypeParamBindings, context: context)
          }
        }

        // Enforce the method's OWN type-parameter bounds against what the call
        // site bound them to. Same gate a free function's call site runs
        // (`enforceGenericConstraints`) and the same one the explicit
        // `obj.[T]method(args)` path runs at `resolveGenericMethodWithExplicitTypeArgs`;
        // inferred type arguments must not skip it. The parameters are paired
        // with their arguments by name within the method's own binder, in
        // declaration order -- the argument list `inferMethodCall` later
        // extracts is in first-appearance order and must not be zipped against
        // the declarations.
        let ownTypeParams = methodTypeParamsByDefId[method.defId] ?? []
        if !ownTypeParams.isEmpty {
          var orderedArgs: [Type] = []
          var allBound = true
          for param in ownTypeParams {
            if let bound = methodTypeParamBindings[param.name] {
              orderedArgs.append(bound)
            } else {
              allBound = false
              break
            }
          }
          if allBound {
            try enforceGenericConstraints(typeParameters: ownTypeParams, args: orderedArgs)
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
            && collectedMethodTypeArgs.count == methodLevelParamNames.count {
          inferredMethodTypeArgs = collectedMethodTypeArgs
        } else {
          inferredMethodTypeArgs = nil
        }
      }
      
      // The callee's function type must not still spell the method's own
      // parameters: MIR lowering cannot call a generic function. The
      // substitution above is conditional on `hasMethodLevelGenerics`, and a
      // call can reach here with bindings but an unsubstituted type.
      if !methodTypeParamBindings.isEmpty {
        finalMethodType = SemaUtils.substituteType(finalMethodType, substitution: methodTypeParamBindings, context: context)
        finalReturns = SemaUtils.substituteType(finalReturns, substitution: methodTypeParamBindings, context: context)
      }

      // A method-generic extension method is instantiated HERE: the template
      // registration cannot see the call site's inferred arguments, so without
      // this the call lowers to a monomorphic symbol nothing ever emits.
      if let mta = inferredMethodTypeArgs, !mta.isEmpty {
        // Trait extensions are keyed by the TRAIT's declaration, not by the
        // receiver's owner -- `List`'s own `given List[T] { }` methods and
        // `Iterable`'s tools live in different buckets.
        let dispatch = receiverMethodDispatchByDefId[method.defId]
        let traitName = dispatch?.conformanceTraitName ?? methodName
        var found: GenericExtensionMethodTemplate? = nil
        if let traitDefId = dispatch?.conformanceTraitDefId {
          for (bucketOwner, templates) in genericExtensionMethods {
            guard case .decl(let bucketDefId) = bucketOwner, bucketDefId == traitDefId else { continue }
            found = templates.first(where: { $0.method.name == methodName && !$0.method.typeParameters.isEmpty })
            break
          }
        }
        if let template = found {
          // `typeArgs` is the TRAIT's arguments -- `Iterable`'s `[T, R]` -- the
          // same shape `resolveGenericExtensionMethod` records, so the request
          // keys match the one the template registration would have made.
          let traitArgs = (try? inferTraitTypeArgsForReceiver(finalBase.type, traitName: traitName)) ?? []
          if traitArgs.count == template.typeParams.count {
            recordInstantiation(InstantiationRequest(
              kind: .extensionMethod(
                templateName: traitName,
                baseType: finalBase.type,
                template: template,
                typeArgs: traitArgs,
                methodTypeArgs: mta
              ),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
        }
      }

      // Create final callee with inferred method type args
      let finalCallee: TypedExpressionNode = .methodReference(
        base: finalBase, method: method, typeArgs: nil, methodTypeArgs: inferredMethodTypeArgs, type: finalMethodType)

      let call: TypedExpressionNode = .call(callee: finalCallee, arguments: typedArguments, type: finalReturns)
      return wrapReceiverMaterialization(materializedReceiver, body: call, type: finalReturns)
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
    callArgs: [CallArg],
    expectedType: Type? = nil
  ) throws -> TypedExpressionNode {
    if case .identifier(let typeName, _) = baseExpr,
       currentScope.lookup(typeName, sourceFile: currentSourceFile) == nil,
       let baseType = currentScope.lookupType(typeName, sourceFile: currentSourceFile) {
      if case .genericParameter = baseType {
        // Keep existing generic-parameter method path below.
      } else {
        let resolvedMethodTypeArgs = try methodTypeArgs.map { try resolveTypeNode($0) }
        return try inferStaticGenericMethodCallOnConcreteType(
          baseType: baseType,
          methodName: methodName,
          callArgs: callArgs,
          explicitMethodTypeArgs: resolvedMethodTypeArgs,
          expectedType: expectedType
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
    try ensureMethodAccessibleForMemberAccess(methodResult.methodSymbol, memberName: methodName)

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

    // Plan call arguments through the unified planner (labels + defaults).
    let expectedArgCount = params.count - 1
    let paramMeta = callArgumentParamMeta(
      defId: methodResult.methodSymbol.defId,
      argumentCount: expectedArgCount
    )
    let arguments = try planCallArgumentExpressions(
      callArgs,
      paramNames: paramMeta.names,
      paramIsNamed: paramMeta.isNamed,
      paramDefaults: paramMeta.defaults,
      callDescription: methodName
    )

    // Check argument count (excluding self)
    if arguments.count != expectedArgCount {
      throw SemanticError.invalidArgumentCount(
        function: methodName,
        expected: expectedArgCount,
        got: arguments.count
      )
    }
    
    // Handle self parameter
    let materializedReceiver: (symbol: Symbol, value: TypedExpressionNode)?
    var finalBase = typedBase
    if let firstParam = params.first {
      let prepared = try prepareReceiverBase(finalBase, expectedType: firstParam.type, methodName: methodName)
      finalBase = prepared.base
      materializedReceiver = prepared.binding
      if finalBase.type != firstParam.type {
        finalBase = try coerceReceiverType(finalBase, expectedType: firstParam.type)
      }
    } else {
      materializedReceiver = nil
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
      } else if case .rangeExpression(let op, let left, let right, _) = arg {
        typedArg = try inferRangeExpression(
          operator: op,
          left: left,
          right: right,
          expectedType: param.type
        )
      } else {
        typedArg = try inferTypedExpression(arg, expectedType: param.type)
      }
      typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
      if typedArg.type != param.type {
        typedArg = try coerceArgumentType(typedArg, expectedType: param.type)
      }
      typedArguments.append(typedArg)
    }
    
    // Check if this is a trait method placeholder (for generic parameter types)
    let finalCallee: TypedExpressionNode
    if let traitName = methodResult.traitName {
      // Create a traitMethodPlaceholder instead of methodReference.
      // Identity comes from the bound that supplied the method, not from a
      // second lookup of its spelling.
      finalCallee = .traitMethodPlaceholder(
        traitName: traitName,
        traitDefId: methodResult.traitDefId ?? .invalid,
        traitMethodDefId: methodResult.traitDefId.flatMap {
          traitMethodDefId(traitDefId: $0, methodName: methodName)
        } ?? methodResult.methodSymbol.defId,
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
    
    let call: TypedExpressionNode = .call(callee: finalCallee, arguments: typedArguments, type: returns)
    return wrapReceiverMaterialization(materializedReceiver, body: call, type: returns)
  }
}


// MARK: - Member Path Expression Inference

extension TypeChecker {
  
  /// Infers the type of a member path expression (e.g., obj.field or Type.method)
  func inferMemberPathExpression(baseExpr: ExpressionNode, path: [String]) throws -> TypedExpressionNode {
    if isModulePrefixedMemberPath(baseExpr: baseExpr, path: path) {
      throw SemanticError(
        .generic("Module-prefixed access is not supported; import the symbol explicitly with using \"package/subpath\" { Symbol }"),
        span: currentSpan
      )
    }

    // 1. Check if baseExpr is a Type (Generic Instantiation) for static method access or Enum Constructor
    if case .genericInstantiation(let baseName, let args, _) = baseExpr {
      if let result = try inferGenericInstantiationMemberPath(baseName: baseName, args: args, path: path) {
        return result
      }
    }

    // 2. Check if baseExpr is a Type (Identifier) for static method access
    if case .identifier(let name, _) = baseExpr, let rawType = currentScope.lookupType(name, sourceFile: currentSourceFile) {
      let type = canonicalizedTypeForStaticMemberLookup(rawType)
      switch type {
      case .genericStruct(let tplDefId, let typeArgs):
        let argNodes = try typeArgs.map { try toTypeNode($0) }
        if let result = try inferGenericInstantiationMemberPath(baseName: Type.spelling(tplDefId), args: argNodes, path: path) {
          return result
        }
      case .genericEnum(let tplDefId, let typeArgs):
        let argNodes = try typeArgs.map { try toTypeNode($0) }
        if let result = try inferGenericInstantiationMemberPath(baseName: Type.spelling(tplDefId), args: argNodes, path: path) {
          return result
        }
      default:
        break
      }

      if let result = try inferTypeMemberPath(type: type, typeName: name, path: path) {
        return result
      }
    }

    // 3. Enum Constructor Access via member path (e.g., EnumType.CaseName)
    if case .identifier(let name, _) = baseExpr, let rawType = currentScope.lookupType(name, sourceFile: currentSourceFile) {
      let type = canonicalizedTypeForStaticMemberLookup(rawType)
      if path.count == 1 {
        let memberName = path[0]
        if case .`enum`(let defId) = type {
          if let c = context.getEnumCases(defId)?.first(where: { $0.name == memberName }) {
            throw SemanticError(.generic("Enum constructor '\(name).\(memberName)' cannot be used as a function value"), span: currentSpan)
          }
        }
      }
    }
    
    // 4. Generic Enum Constructor Access with type inference from return type context
    // e.g., Result.Ok(x) when return type is [T, E]Result
    if case .identifier(let name, _) = baseExpr,
       let template = currentScope.lookupGenericEnumTemplate(name),
       path.count == 1 {
      let memberName = path[0]
      
      // Try to infer type arguments from currentFunctionReturnType
      if let returnType = currentFunctionReturnType,
         case .genericEnum(let tplDefId, let typeArgs) = returnType,
         tplDefId == template.defId {
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
        
        let type = genericEnumType(template: name, args: typeArgs)
        
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

          throw SemanticError(.generic("Enum constructor '\(type).\(memberName)' cannot be used as a function value"), span: currentSpan)
        }
      }
    }

    if case .identifier(let name, _) = baseExpr,
       isASCIITypeStyleIdentifier(name),
       let importError = explicitImportErrorForUnresolvedType(name) {
      throw importError
    }

    // infer base
    let inferredBase = try inferTypedExpression(baseExpr)

    let typedBase = inferredBase

    // The base has already objected about itself. What it does or does not
    // contain is a consequence of that failure, not a second problem.
    if typedBase.type == .error {
      return failedExpression()
    }

    var currentType: Type = typedBase.type
    var typedPath: [Symbol] = []

    for (index, memberName) in path.enumerated() {
      let isLast = index == path.count - 1

      let (typeToLookup, isPointerAccess) = {
        if let (inner, _) = referenceTypeComponents(currentType) { return (inner, false) }
        if case .pointer(let inner) = currentType { return (inner, true) }
        if case .mutablePointer(let inner) = currentType { return (inner, true) }
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
            let accessLabel = mem.access.description
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
      
      // Handle genericStruct types - look up member from template.
      // The template's DECLARATION comes from the type's own `templateDefId`;
      // re-deriving it from the spelling picks whichever module registered last
      // when two modules declare the same name.
      if !foundMember,
        case .genericStruct(let tplDefId, let typeArgs) = typeToLookup
      {
        if tplDefId.isValid, let templateDefId = Optional(tplDefId),
          let info = context.defIdMap.getGenericStructTemplateInfo(templateDefId)
        {
          // Create type substitution map
          var substitution: [String: Type] = [:]
          for (i, param) in info.typeParameters.enumerated() {
            if i < typeArgs.count {
              substitution[param.name] = typeArgs[i]
            }
          }

          // Look up member in template and substitute types
          if let param = info.parameters.first(where: { $0.name == memberName }) {
            // Check field visibility
            if !isFieldAccessibleForMemberAccess(fieldAccess: param.access, defId: templateDefId) {
              let fieldAccess = param.access
              let accessLabel = fieldAccess.description
              throw SemanticError(.generic(
                "Cannot access \(accessLabel) field '\(memberName)' of type '\(Type.spelling(tplDefId))'"
              ), span: currentSpan)
            }
            let memberType = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try resolveTypeNode(param.type)
            }
            let sym = makeLocalSymbol(
              name: param.name, type: memberType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
            typedPath.append(sym)
            currentType = memberType
            foundMember = true
          }
        }
      }

      if !foundMember {
        if isLast {
         // Raw pointers may use direct field access sugar. They may also use
         // methods defined on the pointer type itself (for example Ptr/MutPtr
         // extensions), but they do not support implicit pointee method lookup.
         if isPointerAccess,
           let pointerMethodResult = try inferMethodOnType(typeToLookup: currentType, memberName: memberName, typedBase: typedBase, typedPath: typedPath) {
          return pointerMethodResult
         }

         if !isPointerAccess,
           let methodResult = try inferMethodOnType(typeToLookup: typeToLookup, memberName: memberName, typedBase: typedBase, typedPath: typedPath) {
            return methodResult
          }

          if isPointerAccess,
             case .structure = typeToLookup {
            throw SemanticError(.generic(
              "cannot call method '\(memberName)' on pointer type '\(currentType.description)'; pointers support direct field access only"
            ), span: currentSpan)
          }
        }

        if isPointerAccess {
          throw SemanticError(
            .pointerMemberAccessOnNonStruct(field: memberName, type: currentType.description),
            span: currentSpan
          )
        }
        if case .structure(let defId) = typeToLookup {
          let name = context.getName(defId) ?? ""
          if isForeignStruct {
            throw SemanticError(.unknownForeignField(type: name, field: memberName), span: currentSpan)
          }
          throw SemanticError(
            .generic(missingMemberMessage(memberName: memberName, typeName: name, owner: context.methodOwner(of: typeToLookup))),
            span: currentSpan)
        } else {
          // Every receiver kind reports the same missing-member diagnostic.
          // This used to fall through to
          // `.invalidOperation(op: "member access", type1: typeToLookup.description, type2: "")`,
          // which renders as `Invalid operation member access between types Box[Int] and `
          // -- `type2` is spelled as an empty string, so the message ends mid-clause.
          throw SemanticError(
            .generic(missingMemberMessage(
              memberName: memberName, typeName: typeToLookup.description,
              owner: context.methodOwner(of: typeToLookup))),
            span: currentSpan)
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
      // private: only accessible from the same file
      let defSourceFile = context.getSourceFile(defId) ?? ""
      return defSourceFile == currentSourceFile
    case .internal:
      // internal: accessible from the same logical module only.
      let defModulePath = context.getModulePath(defId) ?? []
      return defModulePath == currentModulePath
    case .protected:
      guard !currentPackageID.isEmpty else { return false }
      return context.getPackageID(defId) == currentPackageID
    }
  }

  private func effectiveMethodAccessForMemberAccess(_ method: Symbol, memberName: String) -> AccessModifier? {
    if let conformance = methodTraitConformanceByDefId[method.defId],
       let traitMethod = try? flattenedTraitMethods(conformance.traitName)[memberName] {
      return traitMethod.access
    }
    return context.getAccess(method.defId)
  }

  private func isMethodAccessibleForMemberAccess(_ method: Symbol, memberName: String) -> Bool {
    let logicalMethodName = receiverMethodDispatchByDefId[method.defId]?.methodName
      ?? context.getName(method.defId)
      ?? memberName
    guard let methodAccess = effectiveMethodAccessForMemberAccess(method, memberName: logicalMethodName) else {
      return true
    }
    switch methodAccess {
    case .public:
      return true
    case .private:
      let defSourceFile = context.getSourceFile(method.defId) ?? ""
      return isSameSourceFile(defSourceFile, currentSourceFile)
    case .internal:
      let defModulePath = context.getModulePath(method.defId) ?? []
      return defModulePath == currentModulePath
    case .protected:
      guard !currentPackageID.isEmpty else { return false }
      return context.getPackageID(method.defId) == currentPackageID
    }
  }

  private func ensureMethodAccessibleForMemberAccess(_ method: Symbol, memberName: String) throws {
    guard let methodAccess = effectiveMethodAccessForMemberAccess(method, memberName: memberName),
          !isMethodAccessibleForMemberAccess(method, memberName: memberName) else {
      return
    }

    throw SemanticError(.generic("Cannot access \(methodAccess.description) method '\(memberName)'"), span: currentSpan)
  }

  private func makeCallableValueLambda(
    parameters: [Parameter],
    returnType: Type,
    body: ([TypedExpressionNode]) -> TypedExpressionNode
  ) -> TypedExpressionNode {
    let parameterSymbols = parameters.enumerated().map { index, parameter in
      nextSynthSymbol(prefix: "callable_arg_\(index)", type: parameter.type)
    }
    let arguments = parameterSymbols.map { TypedExpressionNode.variable(identifier: $0) }
    return .lambdaExpression(
      parameters: parameterSymbols,
      captures: [],
      body: body(arguments),
      type: .function(parameters: parameters, returns: returnType)
    )
  }

  private func makeEnumConstructorValueLambda(
    enumType: Type,
    caseName: String,
    parameters: [Parameter]
  ) -> TypedExpressionNode {
    makeCallableValueLambda(parameters: parameters, returnType: enumType) { arguments in
      .enumConstruction(type: enumType, caseName: caseName, arguments: arguments)
    }
  }

  private func makeStaticMethodValueLambda(
    baseType: Type,
    methodName: String,
    typeArgs: [Type],
    methodTypeArgs: [Type],
    parameters: [Parameter],
    returnType: Type
  ) -> TypedExpressionNode {
    makeCallableValueLambda(parameters: parameters, returnType: returnType) { arguments in
      .staticMethodCall(
        baseType: baseType,
        methodName: methodName,
        typeArgs: typeArgs,
        methodTypeArgs: methodTypeArgs,
        arguments: arguments,
        type: returnType
      )
    }
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
      
      let type = genericStructType(template: baseName, args: resolvedArgs)

      if path.count == 1 {
        let memberName = path[0]
        if let extensions = genericExtensionMethods[context.methodOwner(of: type)] {
          if let ext = extensions.first(where: { $0.method.name == memberName }) {
            let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
            if isStatic {
              let methodSym = try resolveGenericExtensionMethod(
                baseType: type, templateName: baseName, typeArgs: resolvedArgs,
                methodInfo: ext)
              try ensureMethodAccessibleForMemberAccess(methodSym, memberName: memberName)
              guard case .function(let parameters, let returnType) = methodSym.type else {
                throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
              }
              return makeStaticMethodValueLambda(
                baseType: type,
                methodName: memberName,
                typeArgs: resolvedArgs,
                methodTypeArgs: [],
                parameters: parameters,
                returnType: returnType
              )
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
      
      let type = genericEnumType(template: baseName, args: resolvedArgs)

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

          throw SemanticError(.generic("Enum constructor '\(type).\(memberName)' cannot be used as a function value"), span: currentSpan)
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
        if let methods = extensionMethods[context.methodOwner(of: type)], let sym = methods[memberName] {
          methodSymbol = sym
        }
      }

      if let method = methodSymbol {
        try ensureMethodAccessibleForMemberAccess(method, memberName: memberName)
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
    func makeMethodReference(_ methodSym: Symbol, typeArgs: [Type]? = nil) throws -> TypedExpressionNode {
      try ensureMethodAccessibleForMemberAccess(methodSym, memberName: memberName)
      let base: TypedExpressionNode = typedPath.isEmpty
        ? typedBase
        : .memberPath(source: typedBase, path: typedPath)
      return .methodReference(
        base: base,
        method: methodSym,
        typeArgs: typeArgs,
        methodTypeArgs: nil,
        type: methodSym.type
      )
    }
    // METHOD FACE (§3.4): the instance-method read goes through the face gate.
    if let methodSym = visibleDeclaredMethod(on: typeToLookup, name: memberName) {
      guard isReceiverStyleMethod(methodSym) else {
        return nil
      }
      return try makeMethodReference(methodSym)
    }

    if let methodSym = try lookupDeclaredMethod(on: typeToLookup, name: memberName) {
      return try makeMethodReference(methodSym)
    }

    if case .pointer(let element) = typeToLookup {
      if let extensions = genericIntrinsicExtensionMethods[.builtin("Ptr")] {
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
            return try makeMethodReference(methodSym, typeArgs: [element])
          }
        }
      }

      if let extensions = genericExtensionMethods[.builtin("Ptr")] {
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
            return try makeMethodReference(methodSym, typeArgs: [element])
          }
        }
      }
    }
    
    // Handle genericStruct types
    if case .genericStruct(let tplDefId, let typeArgs) = typeToLookup {
      if let extensions = genericExtensionMethods[context.methodOwner(of: typeToLookup)] {
        for ext in extensions {
          // METHOD FACE (§3.4): a template with a conformance trait is that
          // trait's method -- invisible unless the trait is in scope here.
          if ext.method.name == memberName && extensionTemplateFaceAllows(ext) {
            guard ext.method.parameters.first?.name == "self" else {
              continue
            }
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: Type.spelling(tplDefId),
              typeArgs: typeArgs,
              methodInfo: ext
            )
            return try makeMethodReference(methodSym, typeArgs: typeArgs)
          }
        }
      }
    }

    // Handle genericEnum types
    if case .genericEnum(let tplDefId, let typeArgs) = typeToLookup {
      if let extensions = genericExtensionMethods[context.methodOwner(of: typeToLookup)] {
        for ext in extensions {
          if ext.method.name == memberName && extensionTemplateFaceAllows(ext) {
            guard ext.method.parameters.first?.name == "self" else {
              continue
            }
            let methodSym = try resolveGenericExtensionMethod(
              baseType: typeToLookup,
              templateName: Type.spelling(tplDefId),
              typeArgs: typeArgs,
              methodInfo: ext
            )
            return try makeMethodReference(methodSym, typeArgs: typeArgs)
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
        // Identity from the bound that supplied the method. A second lookup of
        // the spelling picks whichever trait of that name is registered first.
        let traitDefId = resolveBound(traitConstraint).defId ?? .invalid
        let methods = try flattenedTraitMethods(traitName)
        if let sig = methods[memberName] {
          if sig.parameters.first?.name != "self" {
            continue
          }
          
          let traitInfo = visibleTraitInfo(traitName)
          var traitTypeArgs: [Type] = []
          if case .trait(_, _, let argNodes) = traitConstraint {
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
            traitDefId: traitDefId,
            traitMethodDefId: traitMethodDefId(traitDefId: traitDefId, methodName: memberName) ?? .invalid,
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
            traitDefId: traitDefId,
            traitMethodDefId: traitMethodDefId(traitDefId: traitDefId, methodName: memberName) ?? entityMethod.defId,
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
    if case .traitObject(let tplDefId, let traitTypeArgs) = typeToLookup {
      let methods = try flattenedTraitMethods(forDefId: tplDefId)
      if let sig = methods[memberName] {
        // Only instance methods (with self parameter)
        if sig.parameters.first?.name != "self" {
          return nil
        }

        let traitInfo = traitDeclsByDefId[tplDefId]
        let traitObjType: Type = traitObjectType(traitName: Type.spelling(tplDefId), typeArgs: traitTypeArgs)

        // Resolve the method type with Self replaced by the trait object type
        let expectedType = try expectedFunctionTypeForTraitMethod(
          sig,
          selfType: traitObjType,
          traitInfo: traitInfo,
          traitTypeArgs: traitTypeArgs
        )

        let methodSym = makeMethodSymbol(
          name: memberName,
          type: expectedType,
          access: .internal,
          ownerKey: methodLabelKey(traitObjType)
        )

        // Register named parameter info from the trait method signature
        // so that call-site validation uses the trait's named parameter requirements
        functionNamedParams[methodSym.defId] = sig.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) }

        let base: TypedExpressionNode
        if typedPath.isEmpty {
          base = typedBase
        } else {
          base = .memberPath(source: typedBase, path: typedPath)
        }
        return .methodReference(base: base, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: methodSym.type)
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
    callArgs: [CallArg],
    expectedType: Type? = nil
  ) throws -> TypedExpressionNode {
    if typeName.contains(".") {
      throw SemanticError(
        .generic("Module-prefixed access is not supported; import the symbol explicitly with using \"package/subpath\" { Symbol }"),
        span: currentSpan
      )
    }

    let resolvedTypeArgs = try typeArgs.map { try resolveTypeNode($0) }

    if let rawType = currentScope.lookupType(typeName, sourceFile: currentSourceFile) {
      let canonicalType = canonicalizedTypeForStaticMemberLookup(rawType)
      switch canonicalType {
      case .genericStruct(let tplDefId, let aliasArgs):
        if !resolvedTypeArgs.isEmpty {
          throw SemanticError(.generic("Type \(typeName) is not generic"), span: currentSpan)
        }
        guard let template = currentScope.genericStructTemplate(defId: tplDefId) else {
          throw SemanticError.undefinedType(Type.spelling(tplDefId))
        }
        return try inferGenericStructStaticMethodCall(
          template: template,
          typeName: Type.spelling(tplDefId),
          resolvedTypeArgs: aliasArgs,
          methodName: methodName,
          callArgs: callArgs
        )
      case .genericEnum(let tplDefId, let aliasArgs):
        if !resolvedTypeArgs.isEmpty {
          throw SemanticError(.generic("Type \(typeName) is not generic"), span: currentSpan)
        }
        guard let template = currentScope.genericEnumTemplate(defId: tplDefId) else {
          throw SemanticError.undefinedType(Type.spelling(tplDefId))
        }
        return try inferGenericEnumStaticMethodCall(
          template: template,
          typeName: Type.spelling(tplDefId),
          resolvedTypeArgs: aliasArgs,
          methodName: methodName,
          callArgs: callArgs
        )
      default:
        break
      }
    }
    
    // Check if it's a generic struct
    if let template = currentScope.lookupGenericStructTemplate(typeName) {
      // 检查泛型模板的可见性（通过已实例化的类型检查）
      // 泛型模板本身没有模块路径，需要在实例化时检查
      return try inferGenericStructStaticMethodCall(
        template: template,
        typeName: typeName,
        resolvedTypeArgs: resolvedTypeArgs,
        methodName: methodName,
        callArgs: callArgs
      )
    }
    
    // Check if it's a generic enum
    if let template = currentScope.lookupGenericEnumTemplate(typeName) {
      return try inferGenericEnumStaticMethodCall(
        template: template,
        typeName: typeName,
        resolvedTypeArgs: resolvedTypeArgs,
        methodName: methodName,
        callArgs: callArgs
      )
    }
    
    // Check if it's a non-generic type (e.g., String.empty())
    if let type = currentScope.lookupType(typeName, sourceFile: currentSourceFile) {
      // 检查类型的模块可见性
      try checkTypeVisibility(type: type, typeName: typeName)
      
      return try inferConcreteTypeStaticMethodCall(
        type: type,
        typeName: typeName,
        resolvedTypeArgs: resolvedTypeArgs,
        methodName: methodName,
        callArgs: callArgs,
        expectedType: expectedType
      )
    }

    if let importError = explicitImportErrorForUnresolvedType(typeName) {
      throw importError
    }

    throw SemanticError.undefinedType(typeName)
  }
  
  func inferGenericStructStaticMethodCall(
    template: GenericStructTemplate,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    callArgs: [CallArg]
  ) throws -> TypedExpressionNode {
    var effectiveTypeArgs = resolvedTypeArgs
    if effectiveTypeArgs.isEmpty, !template.typeParameters.isEmpty,
       let inferred = try inferGenericTypeArgsForStaticMethodCall(
        templateName: typeName,
        typeParameters: template.typeParameters,
        methodName: methodName,
        arguments: callArgs.compactMap { $0.expression }
       ) {
      effectiveTypeArgs = inferred
    }

    try enforceGenericConstraints(typeParameters: template.typeParameters, args: effectiveTypeArgs)

    if !effectiveTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
      recordInstantiation(InstantiationRequest(
        kind: .structType(template: template, args: effectiveTypeArgs),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }

    let baseType = genericStructType(template: typeName, args: effectiveTypeArgs)

    if let extensions = genericExtensionMethods[context.methodOwner(of: baseType)] {
      if let ext = extensions.first(where: { $0.method.name == methodName }) {
        let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
        if isStatic {
          let methodSym = try resolveGenericExtensionMethod(
            baseType: baseType, templateName: typeName, typeArgs: effectiveTypeArgs,
            methodInfo: ext)

          guard case .function(let params, let returnType) = methodSym.type else {
            throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
          }

          let extMeta = callParamMeta(
            from: ext.method.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) },
            argumentCount: params.count
          )
          let arguments = try planCallArgumentExpressions(
            callArgs,
            paramNames: extMeta.names,
            paramIsNamed: extMeta.isNamed,
            paramDefaults: extMeta.defaults,
            callDescription: methodName
          )

          if arguments.count != params.count {
            throw SemanticError.invalidArgumentCount(
              function: methodName,
              expected: params.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params) {
            let typedArg = try inferArgumentExpression(arg, expectedType: param.type)
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
  
  func inferGenericEnumStaticMethodCall(
    template: GenericEnumTemplate,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    callArgs: [CallArg]
  ) throws -> TypedExpressionNode {
    var effectiveTypeArgs = resolvedTypeArgs
    if effectiveTypeArgs.isEmpty, !template.typeParameters.isEmpty,
       let inferred = try inferGenericTypeArgsForStaticMethodCall(
        templateName: typeName,
        typeParameters: template.typeParameters,
        methodName: methodName,
        arguments: callArgs.compactMap { $0.expression }
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
    
    let baseType = genericEnumType(template: typeName, args: effectiveTypeArgs)
    
    if let extensions = genericExtensionMethods[context.methodOwner(of: baseType)] {
      if let ext = extensions.first(where: { $0.method.name == methodName }) {
        let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
        if isStatic {
          let methodSym = try resolveGenericExtensionMethod(
            baseType: baseType, templateName: typeName, typeArgs: effectiveTypeArgs,
            methodInfo: ext)
          
          guard case .function(let params, let returnType) = methodSym.type else {
            throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
          }

          let enumExtMeta = callParamMeta(
            from: ext.method.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) },
            argumentCount: params.count
          )
          let arguments = try planCallArgumentExpressions(
            callArgs,
            paramNames: enumExtMeta.names,
            paramIsNamed: enumExtMeta.isNamed,
            paramDefaults: enumExtMeta.defaults,
            callDescription: methodName
          )

          if arguments.count != params.count {
            throw SemanticError.invalidArgumentCount(
              function: methodName,
              expected: params.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params) {
            let typedArg = try inferArgumentExpression(arg, expectedType: param.type)
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
    // Only the template's SPELLING is in scope here; resolve it once.
    let templateOwner = methodOwnerForName(templateName) ?? .builtin(templateName)
    guard let extensions = genericExtensionMethods[templateOwner],
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
      try currentScope.defineType("Self", type: genericStructType(template: templateName, args: selfArgs))

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
          switch constraint {
          case .trait(_, let traitName, let traitArgs):
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
          case .mutable, .foreign:
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

  /// Solve a concrete type's trait arguments for `traitName` by unifying the
  /// trait's required method signatures against the type's own methods.
  ///
  /// Generic: it names no trait. Used to read `A...` out of a bound `[A...]Trait`
  /// once the bounded parameter's type is known.
  func inferTraitTypeArgumentsFromConformance(
    selfType: Type,
    traitName: String
  ) throws -> [Type]? {
    guard let traitInfo = visibleTraitInfo(traitName) else {
      return nil
    }

    if traitInfo.typeParameters.isEmpty {
      return []
    }

    let requiredMethods = try flattenedTraitMethods(traitName)
    var traitParamBindings: [String: Type] = [:]

    for methodSignature in requiredMethods.values {
      guard let actualMethod = try lookupDeclaredMethod(on: selfType, name: methodSignature.name) else {
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
  
  func inferConcreteTypeStaticMethodCall(
    type: Type,
    typeName: String,
    resolvedTypeArgs: [Type],
    methodName: String,
    callArgs: [CallArg],
    expectedType: Type? = nil
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

    if let methods = extensionMethods[context.methodOwner(of: type)], let methodSym = methods[methodName] {
      try ensureMethodAccessibleForMemberAccess(methodSym, memberName: methodName)
      if context.containsGenericParameter(methodSym.type) {
        return try inferStaticGenericMethodCallOnConcreteType(
          baseType: type,
          methodName: methodName,
          callArgs: callArgs,
          explicitMethodTypeArgs: nil,
          expectedType: expectedType
        )
      }

      guard case .function(let params, let returnType) = methodSym.type else {
        throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
      }

      let staticMeta = methodCallParamMeta(
        ownerTypeName: methodLabelKey(type),
        methodName: methodName,
        fallbackDefId: methodSym.defId,
        argumentCount: params.count
      )
      let arguments = try planCallArgumentExpressions(
        callArgs,
        paramNames: staticMeta.names,
        paramIsNamed: staticMeta.isNamed,
        paramDefaults: staticMeta.defaults,
        callDescription: methodName
      )

      if arguments.count != params.count {
        throw SemanticError.invalidArgumentCount(
          function: methodName,
          expected: params.count,
          got: arguments.count
        )
      }

      var typedArguments: [TypedExpressionNode] = []
      for (arg, param) in zip(arguments, params) {
        let typedArg = try inferArgumentExpression(arg, expectedType: param.type)
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

    if let genericMethods = genericExtensionMethods[context.methodOwner(of: type)],
       genericMethods.contains(where: { $0.method.name == methodName }) {
      return try inferStaticGenericMethodCallOnConcreteType(
        baseType: type,
        methodName: methodName,
        callArgs: callArgs,
        explicitMethodTypeArgs: nil,
        expectedType: expectedType
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
            
            let traitInfo = visibleTraitInfo(traitName)
            var traitTypeArgs: [Type] = []
            if case .trait(_, _, let argNodes) = traitConstraint {
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

            let sigMeta = callParamMeta(
              from: sig.parameters.map { (name: $0.name, named: $0.named, defaultValue: $0.defaultValue) },
              argumentCount: params.count
            )
            let arguments = try planCallArgumentExpressions(
              callArgs,
              paramNames: sigMeta.names,
              paramIsNamed: sigMeta.isNamed,
              paramDefaults: sigMeta.defaults,
              callDescription: methodName
            )

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
              typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
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
    callArgs: [CallArg],
    explicitMethodTypeArgs: [Type]?,
    expectedType: Type? = nil
  ) throws -> TypedExpressionNode {
    let methodTypeArgs: [Type]
    if let explicitMethodTypeArgs {
      methodTypeArgs = explicitMethodTypeArgs
    } else {
      methodTypeArgs = try inferStaticGenericMethodTypeArguments(
        baseType: baseType,
        methodName: methodName,
        arguments: callArgs.compactMap { $0.expression },
        expectedType: expectedType
      )
    }

    let methodResult = try resolveGenericMethodWithExplicitTypeArgs(
      baseType: baseType,
      methodName: methodName,
      methodTypeArgs: methodTypeArgs
    )
    try ensureMethodAccessibleForMemberAccess(methodResult.methodSymbol, memberName: methodName)

    guard case .function(let params, let returnType) = methodResult.methodType else {
      throw SemanticError(.generic("Expected function type for static method"), span: currentSpan)
    }

    let paramMeta = methodCallParamMeta(
      ownerTypeName: methodLabelKey(baseType),
      methodName: methodName,
      fallbackDefId: methodResult.methodSymbol.defId,
      argumentCount: params.count
    )
    let arguments = try planCallArgumentExpressions(
      callArgs,
      paramNames: paramMeta.names,
      paramIsNamed: paramMeta.isNamed,
      paramDefaults: paramMeta.defaults,
      callDescription: methodName
    )

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

      typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
      if typedArg.type != param.type {
        typedArg = try coerceArgumentType(typedArg, expectedType: param.type)
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
    arguments: [ExpressionNode],
    expectedType: Type? = nil
  ) throws -> [Type] {
    let templateName: String
    switch baseType {
    case .genericStruct(let tplDefId, _):
      templateName = Type.spelling(tplDefId)
    case .genericEnum(let tplDefId, _):
      templateName = Type.spelling(tplDefId)
    case .structure(let defId):
      templateName = context.getName(defId) ?? ""
    case .`enum`(let defId):
      templateName = context.getName(defId) ?? ""
    default:
      templateName = baseType.description
    }

    let methodTypeParamNames: [String]
    let unresolvedFunctionType: Type

    if let extensions = genericExtensionMethods[context.methodOwner(of: baseType)],
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

        let receiverMutable = isMutableNominalReceiverType(baseType)
        let selfBindingType = adjustReceiverParameterType(
          paramName: "self",
          resolvedType: baseType,
          receiverMutable: receiverMutable
        )
        currentScope.define("self", selfBindingType, mutable: receiverMutable)

        let params = try methodInfo.method.parameters.map { param -> Parameter in
          let resolvedParamType = try resolveTypeNode(param.type)
          let paramType = adjustReceiverParameterType(
            paramName: param.name,
            resolvedType: resolvedParamType,
            receiverMutable: receiverMutable
          )
          return Parameter(
            type: paramType,
            kind: passKindForResolvedParameter(
              paramName: param.name,
              type: paramType,
              receiverMutable: receiverMutable)
          )
        }
        let returns = try resolveTypeNode(methodInfo.method.returnType)
        return Type.function(parameters: params, returns: returns)
      }
    } else if let methods = extensionMethods[context.methodOwner(of: baseType)],
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
      typedArg = try coerceLiteral(typedArg, to: param.type, span: arg.span)
      _ = unifyTypes(param.type, typedArg.type, bindings: &methodTypeParamBindings)
    }
    // A method type parameter that appears only in the return position
    // (`f[T Any](self) T`) is bound by the expected type, exactly
    // as the instance form binds it.
    if let expectedType, case .function(_, let returns) = unresolvedFunctionType {
      _ = unifyTypes(returns, expectedType, bindings: &methodTypeParamBindings)
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

  private func flattenDeepFluentMemberCallChain(
    callee: ExpressionNode,
    callArgs: [CallArg]
  ) -> (baseExpr: ExpressionNode, segments: [(memberName: String, callArgs: [CallArg])])? {
    var segments: [(memberName: String, callArgs: [CallArg])] = []
    var currentCallee = callee
    var currentArgs = callArgs

    while case .memberPath(let baseExpr, let path, _) = currentCallee, path.count == 1 {
      segments.append((memberName: path[0], callArgs: currentArgs))
      guard case .call(let nestedCallee, let nestedArgs, _) = baseExpr else {
        if segments.count >= 8 {
          return (baseExpr, segments.reversed())
        }
        return nil
      }
      currentCallee = nestedCallee
      currentArgs = nestedArgs
    }

    return nil
  }

  private func inferDeepFluentMemberCallChain(
    baseExpr: ExpressionNode,
    segments: [(memberName: String, callArgs: [CallArg])],
    expectedType: Type?
  ) throws -> TypedExpressionNode? {
    var current = try inferTypedExpression(baseExpr)

    for (index, segment) in segments.enumerated() {
      guard let typedCallee = try inferSingleMemberReference(base: current, memberName: segment.memberName) else {
        return nil
      }

      let segmentExpectedType = index == segments.count - 1 ? expectedType : nil
      current = try inferResolvedMethodReferenceCall(
        typedCallee: typedCallee,
        callArgs: segment.callArgs,
        expectedType: segmentExpectedType
      )
    }

    return current
  }

  private func inferSingleMemberReference(
    base: TypedExpressionNode,
    memberName: String
  ) throws -> TypedExpressionNode? {
    let (typeToLookup, isPointerAccess): (Type, Bool)
    switch base.type {
    case .reference(let inner), .mutableReference(let inner):
      (typeToLookup, isPointerAccess) = (inner, false)
    case .pointer(let inner), .mutablePointer(let inner):
      (typeToLookup, isPointerAccess) = (inner, true)
    default:
      (typeToLookup, isPointerAccess) = (base.type, false)
    }

    if isPointerAccess,
       let methodResult = try inferMethodOnType(
        typeToLookup: base.type,
        memberName: memberName,
        typedBase: base,
        typedPath: []
       ) {
      return methodResult
    }

    return try inferMethodOnType(
      typeToLookup: typeToLookup,
      memberName: memberName,
      typedBase: base,
      typedPath: []
    )
  }

  private func inferResolvedMethodReferenceCall(
    typedCallee: TypedExpressionNode,
    callArgs: [CallArg],
    expectedType: Type?
  ) throws -> TypedExpressionNode {
    guard case .methodReference(let base, let method, _, _, let methodType) = typedCallee else {
      throw SemanticError.invalidOperation(
        op: "call",
        type1: typedCallee.type.description,
        type2: ""
      )
    }
    try validateCallArgumentOrder(callArgs, functionName: "")

    return try inferMethodCall(
      base: base,
      method: method,
      methodType: methodType,
      callArgs: callArgs,
      expectedReturnType: expectedType
    )
  }
}


// MARK: - Expression Helper Methods (moved from TypeChecker.swift)

extension TypeChecker {
  
  /// Builds an equality comparison call for types implementing Eq
  func buildEqualsCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    // Identity of the trait `==` dispatches through: the receiver's own `Eq`
    // bound when it has one, otherwise std's `Eq` -- a LANG ITEM reached by the
    // unique `(Std, name)` pair. A bare name lookup would find whichever trait
    // spelled `Eq` is registered first.
    let traitName = "Eq"
    let receiverType = lhs.type
    let boundDefId: DefId? = {
      if case .genericParameter(let paramName) = receiverType {
        return resolvedTraitBound(paramName, traitName: traitName)?.traitDefId
      }
      return nil
    }()
    let traitDefId = boundDefId ?? context.stdTraitDefId("Eq") ?? .invalid
    let methodName = "equals"
    let shouldUseTraitPlaceholder: Bool = {
      switch receiverType {
      case .genericParameter, .reference, .mutableReference, .weakReference, .mutableWeakReference:
        return true
      default:
        return false
      }
    }()
    if shouldUseTraitPlaceholder {
      if case .genericParameter(let paramName) = receiverType {
        guard hasTraitBound(paramName, traitName) else {
          throw SemanticError(.generic("Type \(receiverType) is not constrained by trait \(traitName)"), span: currentSpan)
        }
      } else {
        try enforceTraitConformance(
          receiverType,
          traitName: traitName,
          context: "operator 'equals'"
        )
      }

      let methods = try flattenedTraitMethods(traitName)
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait \(traitName) is missing required method \(methodName)"), span: currentSpan)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)

      recordTraitPlaceholderInstantiation(
        baseType: receiverType,
        methodName: methodName,
        methodTypeArgs: []
      )

      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: traitName,
        traitDefId: traitDefId,
        traitMethodDefId: traitMethodDefId(traitDefId: traitDefId, methodName: methodName) ?? .invalid,
        methodName: methodName,
        base: lhs,
        methodTypeArgs: [],
        type: expectedType
      )
      return .call(callee: callee, arguments: [rhs], type: .bool)
    }

    try enforceTraitConformance(
      receiverType,
      traitName: traitName,
      context: "operator 'equals'"
    )

    guard let methodSym = try lookupDeclaredMethod(on: receiverType, name: methodName) else {
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

    let callee: TypedExpressionNode = .methodReference(base: lhs, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: methodSym.type)
    return .call(callee: callee, arguments: [rhs], type: .bool)
  }

  /// Builds a comparison call for types implementing Ord
  func buildCompareCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    // Identity of the trait `<=>`/`compare` dispatches through -- see `Eq` in
    // `buildEqualsCall`.
    let traitName = "Ord"
    let receiverType = lhs.type
    let boundDefId: DefId? = {
      if case .genericParameter(let paramName) = receiverType {
        return resolvedTraitBound(paramName, traitName: traitName)?.traitDefId
      }
      return nil
    }()
    let traitDefId = boundDefId ?? context.stdTraitDefId("Ord") ?? .invalid
    let methodName = "compare"
    let shouldUseTraitPlaceholder: Bool = {
      switch receiverType {
      case .genericParameter, .reference, .mutableReference, .weakReference, .mutableWeakReference:
        return true
      default:
        return false
      }
    }()
    if shouldUseTraitPlaceholder {
      if case .genericParameter(let paramName) = receiverType {
        guard hasTraitBound(paramName, traitName) else {
          throw SemanticError(.generic("Type \(receiverType) is not constrained by trait \(traitName)"), span: currentSpan)
        }
      } else {
        try enforceTraitConformance(
          receiverType,
          traitName: traitName,
          context: "operator 'compare'"
        )
      }

      let methods = try flattenedTraitMethods(traitName)
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait \(traitName) is missing required method \(methodName)"), span: currentSpan)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)

      recordTraitPlaceholderInstantiation(
        baseType: receiverType,
        methodName: methodName,
        methodTypeArgs: []
      )

      let callee: TypedExpressionNode = .traitMethodPlaceholder(
        traitName: traitName,
        traitDefId: traitDefId,
        traitMethodDefId: traitMethodDefId(traitDefId: traitDefId, methodName: methodName) ?? .invalid,
        methodName: methodName,
        base: lhs,
        methodTypeArgs: [],
        type: expectedType
      )
      return .call(callee: callee, arguments: [rhs], type: .int)
    }

    try enforceTraitConformance(
      receiverType,
      traitName: traitName,
      context: "operator 'compare'"
    )

    guard let methodSym = try lookupDeclaredMethod(on: receiverType, name: methodName) else {
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

    let callee: TypedExpressionNode = .methodReference(base: lhs, method: methodSym, typeArgs: nil, methodTypeArgs: nil, type: methodSym.type)
    return .call(callee: callee, arguments: [rhs], type: .int)
  }

  // MARK: - Arithmetic Operator Lowering

  func buildArithmeticExpression(
    op: ArithmeticOperator,
    lhs: TypedExpressionNode,
    rhs: TypedExpressionNode
  ) throws -> TypedExpressionNode {
    // An operand that already failed has no type to compute with: stay silent
    // rather than pile a second complaint on the first.
    if lhs.type == .error || rhs.type == .error {
      return failedExpression()
    }
    var left = lhs
    var right = rhs

    // Both integer families have an arithmetic surface: the plain family is
    // checked and panics on overflow, the wrapping family wraps modulo 2^N.
    // A Wrapping operand only ever combines with its own width -- the family
    // is isolated from the plain types and from the other widths.
    var leftIsNumeric = left.type.isIntegerType || isFloatType(left.type)
    var rightIsNumeric = right.type.isIntegerType || isFloatType(right.type)

    if leftIsNumeric && !rightIsNumeric {
      if case .typeConstruction(_, _, _, let srcType) = right, isRuneType(srcType) {
        right = try coerceLiteral(right, to: left.type)
        rightIsNumeric = right.type.isIntegerType || isFloatType(right.type)
      }
    } else if rightIsNumeric && !leftIsNumeric {
      if case .typeConstruction(_, _, _, let srcType) = left, isRuneType(srcType) {
        left = try coerceLiteral(left, to: right.type)
        leftIsNumeric = left.type.isIntegerType || isFloatType(left.type)
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
        if left.type.isWrappingIntegerType {
          return .wrappingArithmeticExpression(left: left, op: op, right: right, type: left.type)
        }
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

    // A Wrapping operand paired with anything else is the same invalid
    // operation a mismatched numeric pair gets.
    if left.type.isWrappingIntegerType || right.type.isWrappingIntegerType {
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

    if case .mutablePointer = left.type, (op == .plus || op == .minus) {
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
    let traitArgs: [Type] = sameType ? [lhs.type] : [rhs.type]

    let traitName: String
    let methodName: String
    switch op {
    case .plus:      traitName = "Add"; methodName = "add"
    case .minus:     traitName = "Sub"; methodName = "sub"
    case .multiply:  traitName = "Mul"; methodName = "mul"
    case .divide:    traitName = "Div"; methodName = "div"
    case .remainder: traitName = "Rem"; methodName = "rem"
    }
    // Identity of the trait the operator dispatches through: the receiver's own
    // bound when it has one, otherwise std's operator trait -- a LANG ITEM
    // reached by the unique `(Std, name)` pair. A bare name lookup would find
    // whichever trait spelled `Add` is registered first.
    let boundDefId: DefId? = {
      if case .genericParameter(let paramName) = lhs.type {
        return resolvedTraitBound(paramName, traitName: traitName)?.traitDefId
      }
      return nil
    }()
    let traitDefId = boundDefId ?? context.stdTraitDefId(traitName) ?? .invalid

    if let call = try buildOperatorMethodCall(
      base: lhs,
      methodName: methodName,
      traitName: traitName,
      requiredTraitArgs: traitArgs,
      arguments: [rhs]
    ) {
      return call
    }
    throw SemanticError.undefinedMember(methodName, lhs.type.description)
  }

  /// `span` names the construct that needs the trait -- the operator, the
  /// interpolated value. Left unset the diagnostic falls back to `currentSpan`,
  /// which is the enclosing expression and is usually the wrong one.
  private func buildOperatorMethodCall(
    base: TypedExpressionNode,
    methodName: String,
    traitName: String,
    requiredTraitArgs: [Type]?,
    arguments: [TypedExpressionNode],
    allowMissingTrait: Bool = false,
    span: SourceSpan = .unknown
  ) throws -> TypedExpressionNode? {
    let blame = span.isKnown ? span : currentSpan
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
       let methodSym = try lookupDeclaredMethod(on: base.type, name: methodName) {
      return try buildConcreteMethodCall(base: base, method: methodSym, arguments: arguments)
    }

    // The complaint belongs to the construct that demanded the trait -- the
    // operator, the interpolated value -- not to whatever statement the check
    // happens to run under. `enforceTraitConformance` blames `currentSpan`, so
    // aim it before calling.
    let outerSpan = currentSpan
    currentSpan = blame
    defer { currentSpan = outerSpan }
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
      // The note the enforcement above computed is not decoration: it is what
      // tells the reader which operator demanded the trait. It was being
      // thrown away with the caught error and this message rebuilt without it.
      let note = " (operator '\(methodName)')"
      if let requiredTraitArgs {
        throw SemanticError(.generic(
          "Type \(base.type) does not explicitly implement trait [\(requiredTraitArgs.map { $0.description }.joined(separator: ", "))]\(traitName)\(note)"
        ), span: blame)
      }
      throw SemanticError(.generic(
        "Type \(base.type) does not explicitly implement trait \(traitName)\(note)"
      ), span: blame)
    }

    if let methodSym = try lookupDeclaredMethod(on: base.type, name: methodName) {
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
    let matchedTraitRef = resolvedTraitBound(
      paramName,
      traitName: traitName,
      traitTypeArgs: requiredTraitArgs
    )
    guard let matchedTraitRef else {
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

    // Identity from the matched bound -- a name lookup here would find
    // whichever trait of that spelling is registered first.
    let traitDefId = matchedTraitRef.traitDefId
    let traitInfo = traitDeclsByDefId[traitDefId]
    let traitTypeArgs = matchedTraitRef.traitTypeArgs

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
      traitDefId: traitDefId,
      traitMethodDefId: traitMethodDefId(traitDefId: traitDefId, methodName: methodName) ?? .invalid,
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
        typedArg = try coerceArgumentType(typedArg, expectedType: param.type)
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
    let materializedReceiver: (symbol: Symbol, value: TypedExpressionNode)?
    var finalBase = base
    if let firstParam = params.first {
      let methodName = context.getName(method.defId) ?? "<unknown>"
      let prepared = try prepareReceiverBase(finalBase, expectedType: firstParam.type, methodName: methodName)
      finalBase = prepared.base
      materializedReceiver = prepared.binding
      if finalBase.type != firstParam.type {
        finalBase = try coerceReceiverType(finalBase, expectedType: firstParam.type)
      }
    } else {
      materializedReceiver = nil
    }

    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg = arg
      typedArg = try coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        typedArg = try coerceArgumentType(typedArg, expectedType: param.type)
      }
      typedArguments.append(typedArg)
    }

    let callee: TypedExpressionNode = .methodReference(
      base: finalBase, method: method, typeArgs: nil, methodTypeArgs: nil, type: method.type
    )
    let call: TypedExpressionNode = .call(callee: callee, arguments: typedArguments, type: returns)
    return wrapReceiverMaterialization(materializedReceiver, body: call, type: returns)
  }
  
  /// Resolves an lvalue expression for assignment
  func resolveLValue(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .identifier(let name, _):
      guard let defId = currentScope.lookup(name, sourceFile: currentSourceFile),
            let type = defIdMap.getSymbolType(defId) else {
        throw SemanticError.undefinedVariable(name)
      }
      guard currentScope.isMutable(name, sourceFile: currentSourceFile) else { throw SemanticError.assignToImmutable(name) }
      let kind = defIdMap.getSymbolKind(defId) ?? .variable(.MutableValue)
      let symbol = Symbol(defId: defId, type: type, kind: kind)
      return .variable(identifier: symbol)

    case .memberPath(let base, let path, _):
      // Check if base evaluates to a Reference type (RValue allowed)
      // OR if base resolves to an LValue (Mut Value required)

      func inferWritableMemberBase(_ baseExpr: ExpressionNode) throws -> TypedExpressionNode {
        if case .subscriptExpression(let outerBaseExpr, let outerArgExprs, _) = baseExpr {
          let typedOuterBase = try inferWritableMemberBase(outerBaseExpr)
          let typedOuterArgs = try outerArgExprs.map { try inferTypedExpression($0) }

          switch resolveBuiltinSubscriptKind(baseType: typedOuterBase.type) {
          case .string:
            throw SemanticError(.generic("String subscript is not addressable"), span: outerBaseExpr.span)
          case .dict, .list, .deque:
            let subscriptValue = try resolveSubscript(base: typedOuterBase, args: typedOuterArgs, span: outerBaseExpr.span)
            if isMutableNominalReceiverType(subscriptValue.type) {
              return subscriptValue
            }
            throw SemanticError(.generic(
              "Collection subscript results are values and cannot be used as writable base addresses"
            ), span: outerBaseExpr.span)
          case .pointer:
            return try resolveSubscript(base: typedOuterBase, args: typedOuterArgs, span: outerBaseExpr.span)
          case .none:
            throw SemanticError(.generic(
              "subscript is only supported for String, List, Deque, Dict, and pointer types"
            ), span: outerBaseExpr.span)
          }
        }

        return try inferTypedExpression(baseExpr)
      }

      let inferredBase = try inferWritableMemberBase(base)
      // Optimization: Peel auto-deref for lvalue resolution
      let typedBase: TypedExpressionNode
      if case .derefExpression(let inner, _) = inferredBase {
        typedBase = inner
      } else if case .unsafeDerefExpression(let inner, _) = inferredBase {
        typedBase = inner
      } else {
        typedBase = inferredBase
      }

      func isRefLikeType(_ type: Type) -> Bool {
        switch type {
        case .reference(_), .mutableReference(_),
             .borrowedReference(_), .mutableBorrowedReference(_),
             .pointer(_), .mutablePointer(_):
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
          if isMutableRefLikeType(identifier.type) { return true }
          if identifier.isMutable() { return true }
          if case .structure(let defId) = identifier.type {
            return context.isTypeMutable(defId)
          }
          if case .genericStruct(let tplDefId, _) = identifier.type {
            return currentScope.genericStructTemplate(defId: tplDefId)?.isMutable == true
          }
          return false
        case .memberPath(let source, let members):
          var allowed = baseAllowsValueMutation(source)
          for member in members {
            if isMutableRefLikeType(member.type) {
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
      let baseIsMutableNominal = isMutableNominalReceiverType(typedBase.type)
      if !baseIsRefLike && !isAddressableValueBase(typedBase) && !baseIsMutableNominal {
        throw SemanticError.invalidOperation(
          op: "assignment target",
          type1: "temporary member path",
          type2: ""
        )
      }

      var valueMutationAllowed = baseAllowsValueMutation(typedBase) || baseIsMutableNominal

      // Now resolve path members on typedBase.
      var currentType = typedBase.type
      var resolvedPath: [Symbol] = []

      func canTraverseImmutableIntermediate(_ memberType: Type, isLastMember: Bool) -> Bool {
        guard !isLastMember else { return false }
        // Allow traversal through reference types (internal managed refs)
        if isRefLikeType(memberType) { return true }
        // Allow traversal through 'type mutable' types — their mutable fields are always writable
        // (Java/Kotlin-like semantics: mutability is a property of the object, not the binding)
        return memberType.isTypeMutable(in: context)
      }

      for (memberIndex, memberName) in path.enumerated() {
        let isLastMember = memberIndex == path.count - 1
        let (typeToLookup, isPointerAccess) = {
          if let (inner, _) = referenceTypeComponents(currentType) { return (inner, false) }
          if case .pointer(let inner) = currentType { return (inner, true) }
          if case .mutablePointer(let inner) = currentType { return (inner, true) }
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
            let accessLabel = member.access.description
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(memberName)' of type '\(structName)'"
            ), span: currentSpan)
          }

          let currentAllowsMutation = isMutableRefLikeType(currentType)
            || valueMutationAllowed
            || (isLastMember && currentType.isTypeMutable(in: context))
          if !member.mutable && !canTraverseImmutableIntermediate(member.type, isLastMember: isLastMember) {
            throw SemanticError.assignToImmutable(memberName)
          }
          if isLastMember && member.mutable && !currentAllowsMutation {
            throw SemanticError.assignToImmutable(memberName)
          }

          resolvedPath.append(
            makeLocalSymbol(
              name: member.name,
              type: member.type,
              kind: .variable(member.mutable ? .MutableValue : .Value)
            ))
          if isMutableRefLikeType(member.type) {
            valueMutationAllowed = true
          } else if isReadOnlyRefLikeType(member.type) {
            valueMutationAllowed = false
          }
          currentType = member.type
          continue
        }
        
        // Handle genericStruct types - look up member from template
        if case .genericStruct(let tplDefId, let typeArgs) = typeToLookup {
          guard let template = currentScope.genericStructTemplate(defId: tplDefId) else {
            throw SemanticError.undefinedType(Type.spelling(tplDefId))
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
            let accessLabel = fieldAccess.description
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(memberName)' of type '\(Type.spelling(tplDefId))'"
            ), span: currentSpan)
          }
          
          // Resolve member type with substitution
          let memberType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(param.type)
          }

          let currentAllowsMutation = isMutableRefLikeType(currentType)
            || valueMutationAllowed
            || (isLastMember && currentType.isTypeMutable(in: context))
          if !param.mutable && !canTraverseImmutableIntermediate(memberType, isLastMember: isLastMember) {
            throw SemanticError.assignToImmutable(memberName)
          }
          if isLastMember && param.mutable && !currentAllowsMutation {
            throw SemanticError.assignToImmutable(memberName)
          }
          
          resolvedPath.append(
            makeLocalSymbol(
              name: param.name,
              type: memberType,
              kind: .variable(param.mutable ? .MutableValue : .Value)
            ))
          if isMutableRefLikeType(memberType) {
            valueMutationAllowed = true
          } else if isReadOnlyRefLikeType(memberType) {
            valueMutationAllowed = false
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
        // Same missing-member text a READ reports. This used to be
        // `.invalidOperation(op: "member access on non-struct", type1: ..., type2: "")`,
        // rendering as `Invalid operation member access on non-struct between
        // types ?Box and ` -- `type2` is spelled empty, so the sentence stops
        // mid-clause -- and it blamed a mutability rule for a member that does
        // not exist. `w.value = 3` and `println(w.value)` now agree.
        throw SemanticError.undefinedMember(memberName, typeToLookup.description)
      }
      return .memberPath(source: typedBase, path: resolvedPath)

    case .subscriptExpression(_, _, _):
      // Direct assignment to `x[i]` is lowered to `set_at` in statement checking.
      // Treat subscript as an invalid assignment target here.
      throw SemanticError.invalidOperation(op: "assignment target", type1: "subscript", type2: "")

    case .derefExpression(let inner, _):
      let typedInner = try inferTypedExpression(inner)
      switch typedInner.type {
      case .reference:
        throw SemanticError(.generic(
          "Cannot assign through read-only reference of type '\(typedInner.type)'"
        ), span: currentSpan)
      case .borrowedReference:
        throw SemanticError(.generic(
          "Cannot assign through read-only reference of type '\(typedInner.type)'"
        ), span: currentSpan)
      case .pointer:
        throw SemanticError(.generic(
          "Cannot assign through read-only pointer of type '\(typedInner.type)'"
        ), span: currentSpan)
      case .mutablePointer(let elementType):
        try requireDerefablePointee(elementType, operation: "*", spelledType: "*mutable")
        return .unsafeDerefExpression(expression: typedInner, type: elementType)
      case .mutableReference(let innerType):
        try requireDerefablePointee(innerType, operation: "*", spelledType: "mutable ref")
        return .derefExpression(expression: typedInner, type: innerType)
      case .mutableBorrowedReference(let innerType):
        try requireDerefablePointee(innerType, operation: "*", spelledType: "borrowed mutable ref")
        return .derefExpression(expression: typedInner, type: innerType)
      default:
        throw SemanticError.typeMismatch(
          expected: "Mutable reference or pointer type",
          got: typedInner.type.description
        )
      }

    case .unsafeDerefExpression(let inner, _):
      let typedInner = try inferTypedExpression(inner)
      switch typedInner.type {
      case .pointer:
        throw SemanticError(.generic(
          "Cannot assign through read-only pointer of type '\(typedInner.type)'"
        ), span: currentSpan)
      case .mutablePointer(let elementType):
        try requireDerefablePointee(elementType, operation: "*", spelledType: "*mutable")
        return .unsafeDerefExpression(expression: typedInner, type: elementType)
      default:
        throw SemanticError.typeMismatch(
          expected: "Mutable pointer type",
          got: typedInner.type.description
        )
      }

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
          _ = try buildToStringExpression(typedExpr, span: expr.span)
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
    if parts.count == 1 {
      return try convertInterpolatedPartToString(parts[0], span: span)
    }

    let stringType = builtinStringType()
    let uintType: Type = .uint
    let mutBytePtrType: Type = .mutablePointer(element: .uint8)

    func nextInterpSymbol(_ prefix: String, type: Type, mutable: Bool = false) -> Symbol {
      let symbol = makeLocalSymbol(
        name: "__interp_\(prefix)_\(synthesizedTempIndex)",
        type: type,
        kind: .variable(mutable ? .MutableValue : .Value)
      )
      synthesizedTempIndex += 1
      return symbol
    }

    guard let countMethod = try lookupDeclaredMethod(on: stringType, name: "count") else {
      throw SemanticError(.generic("Missing method 'count' for type 'String'"), span: span)
    }
    guard let borrowPtrMethod = try lookupDeclaredMethod(on: stringType, name: "borrow_ptr") else {
      throw SemanticError(.generic("Missing method 'borrow_ptr' for type 'String'"), span: span)
    }

    var statements: [TypedStatementNode] = []
    var partSymbols: [Symbol] = []

    for part in parts {
      if case .literal(let value) = part, value.isEmpty {
        continue
      }

      let stringPart = try convertInterpolatedPartToString(part, span: span)
      let partSymbol = nextInterpSymbol("part", type: stringPart.type)
      statements.append(
        .variableDeclaration(identifier: partSymbol, value: stringPart, mutable: false)
      )
      partSymbols.append(partSymbol)
    }

    guard !partSymbols.isEmpty else {
      return .stringLiteral(value: "", type: stringType)
    }

    let firstPartExpr = TypedExpressionNode.variable(identifier: partSymbols[0])
    var totalExpr = try buildConcreteMethodCall(
      base: firstPartExpr,
      method: countMethod,
      arguments: []
    )

    for partSymbol in partSymbols.dropFirst() {
      let partExpr = TypedExpressionNode.variable(identifier: partSymbol)
      let partCount = try buildConcreteMethodCall(
        base: partExpr,
        method: countMethod,
        arguments: []
      )
      totalExpr = .arithmeticExpression(
        left: totalExpr,
        op: .plus,
        right: partCount,
        type: uintType
      )
    }

    let totalSymbol = nextInterpSymbol("total", type: uintType)
    statements.append(
      .variableDeclaration(identifier: totalSymbol, value: totalExpr, mutable: false)
    )

    let totalVar = TypedExpressionNode.variable(identifier: totalSymbol)
    let oneUInt = TypedExpressionNode.integerLiteral(value: "1", type: uintType)
    let capExpr = TypedExpressionNode.arithmeticExpression(
      left: totalVar,
      op: .plus,
      right: oneUInt,
      type: uintType
    )
    let dataAlloc = TypedExpressionNode.intrinsicCall(
      .allocMemory(count: capExpr, resultType: mutBytePtrType)
    )
    let dataSymbol = nextInterpSymbol("data", type: mutBytePtrType)
    statements.append(
      .variableDeclaration(identifier: dataSymbol, value: dataAlloc, mutable: false)
    )

    let zeroUInt = TypedExpressionNode.integerLiteral(value: "0", type: uintType)
    let offsetSymbol = nextInterpSymbol("offset", type: uintType, mutable: true)
    statements.append(
      .variableDeclaration(identifier: offsetSymbol, value: zeroUInt, mutable: true)
    )

    for partSymbol in partSymbols {
      let partExpr = TypedExpressionNode.variable(identifier: partSymbol)
      let partLenExpr = try buildConcreteMethodCall(
        base: partExpr,
        method: countMethod,
        arguments: []
      )
      let partLenSymbol = nextInterpSymbol("len", type: uintType)
      statements.append(
        .variableDeclaration(identifier: partLenSymbol, value: partLenExpr, mutable: false)
      )

      let dataVar = TypedExpressionNode.variable(identifier: dataSymbol)
      let offsetVar = TypedExpressionNode.variable(identifier: offsetSymbol)
      let partLenVar = TypedExpressionNode.variable(identifier: partLenSymbol)
      let destExpr = TypedExpressionNode.arithmeticExpression(
        left: dataVar,
        op: .plus,
        right: offsetVar,
        type: mutBytePtrType
      )
      let sourceExpr = try buildConcreteMethodCall(
        base: partExpr,
        method: borrowPtrMethod,
        arguments: []
      )
      let copyExpr = TypedExpressionNode.intrinsicCall(
        .copyMemory(dest: destExpr, source: sourceExpr, count: partLenVar)
      )
      statements.append(.expression(copyExpr))

      let newOffset = TypedExpressionNode.arithmeticExpression(
        left: offsetVar,
        op: .plus,
        right: partLenVar,
        type: uintType
      )
      statements.append(
        .assignment(
          target: .variable(identifier: offsetSymbol),
          operator: nil,
          value: newOffset
        )
      )
    }

    let finalData = TypedExpressionNode.variable(identifier: dataSymbol)
    let finalTotal = TypedExpressionNode.variable(identifier: totalSymbol)
    let endPtrExpr = TypedExpressionNode.arithmeticExpression(
      left: finalData,
      op: .plus,
      right: finalTotal,
      type: mutBytePtrType
    )
    let zeroByte = TypedExpressionNode.integerLiteral(value: "0", type: .uint8)
    let initExpr = TypedExpressionNode.intrinsicCall(
      .initMemory(ptr: endPtrExpr, val: zeroByte)
    )
    statements.append(.expression(initExpr))

    let builtString = TypedExpressionNode.staticMethodCall(
      baseType: stringType,
      methodName: "from_owned_utf8_ptr_unchecked",
      typeArgs: [],
      methodTypeArgs: [],
      arguments: [
        TypedExpressionNode.variable(identifier: dataSymbol),
        TypedExpressionNode.variable(identifier: totalSymbol),
      ],
      type: stringType
    )

    return .blockExpression(statements: statements, tailExpression: builtString, type: stringType)
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

    // `.error` is the type of an expression that already failed to check.
    // Asking it for `ToString` on top adds `Type '?' does not implement ToString
    // trait` under a message that already explains the failure -- a cascade,
    // not a second mistake. koralc has never done this.
    if expr.type == .error {
      return .stringLiteral(value: "", type: builtinStringType())
    }

    if let call = try buildOperatorMethodCall(
      base: expr,
      methodName: "to_string",
      traitName: "ToString",
      requiredTraitArgs: nil,
      arguments: [],
      span: span
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
       case .genericEnum(let templateDefId, let args) = expected,
       context.isStdNominal(templateDefId, context.stdRangeTemplateDefId),
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

    if typedLeft != nil, typedRight != nil, typedLeft!.type != typedRight!.type {
      typedRight = try coerceLiteral(typedRight!, to: typedLeft!.type)
      if typedLeft!.type != typedRight!.type {
        typedLeft = try coerceLiteral(typedLeft!, to: typedRight!.type)
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
        throw SemanticError(.generic("Full range '...' requires type annotation or context type"), span: currentSpan)
      }
    }
    
    // 3. Verify T implements Ord
    try enforceTraitConformance(elementType, traitName: "Ord")
    
    // 4. Construct Range type
    let rangeType = genericEnumType(template: "Range", args: [elementType])
    
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
  /// for <binding-pattern> in <iterable> then <body>
  /// becomes:
  /// let mutable __koral_iter_N = <iterable>.iterator() then  // or just <iterable> if it's already an iterator
  ///   while true then
  ///     when __koral_iter_N.next() is {
  ///       .Some(<pattern>) then <body>,
  ///       .None then break
  ///     }
  func inferForExpression(
    pattern: PatternNode,
    iterable: ExpressionNode,
    body: ExpressionNode,
    guardExpr: ExpressionNode?
  ) throws -> TypedExpressionNode {
    // 1. Type check the iterable expression
    let typedIterable = try inferTypedExpression(iterable)

    // ── 区间循环专用降低 ────────────────────────────────────────────────────
    // `for x in a..<b` 走这里，不经过迭代器协议。
    if let rangeLoop = try maybeDesugarRangeForLoop(
      pattern: pattern, typedIterable: typedIterable, body: body, guardExpr: guardExpr) {
      return rangeLoop
    }

    var iterableType = typedIterable.type

    // Auto-deref: if the iterable is a reference type, unwrap it
    if let (inner, _) = referenceTypeComponents(iterableType) {
      iterableType = inner
    }

    // 2. First check if the expression type itself is an iterator
    //    (has a next(mutable self) -> [T]Option method)
    if let elementType = try? extractIteratorElementType(iterableType) {
      try enforceGenericTraitConformance(
        iterableType,
        traitName: "Iterator",
        traitTypeArgs: [elementType],
        context: "for-in iterator check"
      )
      let typedPattern = try typeCheckForBinding(pattern, elementType: elementType)
      return try desugarForLoop(
        pattern: typedPattern,
        typedIterable: typedIterable,
        iteratorType: iterableType,
        elementType: elementType,
        body: body,
        guardExpr: guardExpr,
        needsIteratorCall: false  // Don't call iterator(), use expression directly
      )
    }

    // 3. Look up the iterator() method on the iterable type
    guard let iteratorMethod = try lookupDeclaredMethod(on: iterableType, name: "iterator") else {
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
    let typedPattern = try typeCheckForBinding(pattern, elementType: elementType)

    // 7. Desugar the for loop
    return try desugarForLoop(
      pattern: typedPattern,
      typedIterable: typedIterable,
      iteratorType: iteratorType,
      elementType: elementType,
      body: body,
      guardExpr: guardExpr,
      needsIteratorCall: true  // Need to call iterator()
    )
  }

  /// `for x in a..<b` 的专用降低：把迭代状态摊平成本地计数器，完全不走迭代器协议。
  ///
  /// 通用的 for-in 降低要 `iterable.iterator()` 拿到一个 `RangeIterator[T]`——它是
  /// `type mutable`，因而是装箱的托管值，每个循环付一次堆分配；每一步还要经
  /// `next()` 返回 `Option[T]`。对区间循环这些都是纯开销：起点、终点、步进在
  /// 降低时就是已知的，没有任何需要动态决策的东西。
  ///
  /// 生成：
  /// ```
  /// let mutable i = a;
  /// let end = b;
  /// while i < end then {
  ///   let x = i;
  ///   i = i.succ().unwrap();   // 先自增
  ///   <body>                   // 再跑 body
  /// }
  /// ```
  /// 先自增再跑 body，这样 `continue` 直接回到条件判断，不需要额外的收尾逻辑；
  /// `break` 也自然生效。`succ()` 在 `i < end` 时不可能返回 `None`（`end` 本身是
  /// 一个 `T`，故 `end <= max_value`，于是 `i <= max_value - 1`），所以 `unwrap()` 不会触发。
  ///
  /// 只处理**有界闭开区间 `a..<b`**（`for i in 0..<n` 是压倒性的常见写法）和**简单绑定**
  /// （`x` / `mutable x` / `_`）。其余区间形态（`a..=b` 的末元自增会碰到 `max_value`、半开区间、
  /// 无界区间）与解构绑定、非区间可迭代对象仍走通用迭代器路径，语义不变。
  private func maybeDesugarRangeForLoop(
    pattern: PatternNode,
    typedIterable: TypedExpressionNode,
    body: ExpressionNode,
    guardExpr: ExpressionNode?
  ) throws -> TypedExpressionNode? {
    // 只做 `a..<b`：类型检查阶段产出的是 Range 的 ClosedOpen 枚举构造。
    guard case .enumConstruction(_, let caseName, let boundArgs) = typedIterable,
          caseName == "ClosedOpen", boundArgs.count == 2 else {
      return nil
    }
    // 只做简单绑定；`(a, b)` 解构仍走通用路径。
    let bindName: String
    let bindMutable: Bool
    switch pattern {
    case .variable(let name, let isMutable, _):
      bindName = name
      bindMutable = isMutable
    case .wildcard:
      bindName = "_"
      bindMutable = false
    default:
      return nil
    }
    let typedLeft = boundArgs[0]
    let typedRight = boundArgs[1]
    let elementType = typedLeft.type
    if typedRight.type != elementType {
      return nil
    }
    // 计数器需要 succ() 才能前进。
    guard try lookupDeclaredMethod(on: elementType, name: "succ") != nil else {
      return nil
    }

    let suffix = synthesizedTempIndex
    synthesizedTempIndex += 1
    let iterName = "__koral_range_i_\(suffix)"
    let endName = "__koral_range_end_\(suffix)"

    // 计数器本身始终可变（循环要自增），与绑定模式的 mutability 无关；
    // 模式绑定的是每轮的取值副本。
    let iterMutSymbol = makeLocalSymbol(
      name: iterName, type: elementType, kind: .variable(.MutableValue))
    let endSymbol = makeLocalSymbol(name: endName, type: elementType, kind: .variable(.Value))

    let iterVarExpr = TypedExpressionNode.variable(identifier: iterMutSymbol)
    let endVarExpr = TypedExpressionNode.variable(identifier: endSymbol)

    let condition = TypedExpressionNode.comparisonExpression(
      left: iterVarExpr, op: .less, right: endVarExpr, type: .bool)

    // i.succ().unwrap()
    let succCall = try buildNullaryMethodCall(
      on: iterVarExpr,
      methodName: "succ",
      returnType: genericEnumType(template: "Option", args: [elementType]))
    let advanceValue = try buildNullaryMethodCall(
      on: succCall, methodName: "unwrap", returnType: elementType)
    let advance = TypedStatementNode.assignment(
      target: iterVarExpr, operator: nil, value: advanceValue)

    let typedPattern = try typeCheckForBinding(pattern, elementType: elementType)

    return try withNewScope {
      currentScope.define(iterName, defId: iterMutSymbol.defId)
      currentScope.define(endName, defId: endSymbol.defId)

      var bodyStatements: [TypedStatementNode] = []
      if case .variable(let bindSymbol) = typedPattern {
        bodyStatements.append(.variableDeclaration(
          identifier: bindSymbol, value: iterVarExpr, mutable: bindMutable))
      }
      // 自增先于 body，`continue` 才会正确前进。
      bodyStatements.append(advance)

      let typedBody = try withNewScope {
        for symbol in extractPatternSymbols(from: typedPattern) {
          if let name = context.getName(symbol.defId) {
            try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
          }
        }
        let savedInLoop = inLoop
        inLoop = true
        defer { inLoop = savedInLoop }
        // The guard is checked first: its `is` bindings (and the pattern's,
        // already in scope) must be visible to the body.
        let typedGuard = try checkForGuard(guardExpr)
        let checkedBody = try inferCheckedStatementBodyExpression(body)
        return underForGuard(checkedBody, typedGuard: typedGuard)
      }
      bodyStatements.append(.expression(typedBody))

      return .blockExpression(
        statements: [
          .variableDeclaration(identifier: iterMutSymbol, value: typedLeft, mutable: true),
          .variableDeclaration(identifier: endSymbol, value: typedRight, mutable: false),
          .whileStatement(
            condition: condition,
            body: .blockExpression(
              statements: bodyStatements, tailExpression: nil, type: .void)),
        ],
        tailExpression: nil,
        type: .void
      )
    }
  }

  /// 构造 `base.<methodName>()` 这样的无参方法调用。
  private func buildNullaryMethodCall(
    on base: TypedExpressionNode,
    methodName: String,
    returnType: Type
  ) throws -> TypedExpressionNode {
    guard let method = try lookupDeclaredMethod(on: base.type, name: methodName) else {
      throw SemanticError(.generic("\(methodName)() method not found"), span: currentSpan)
    }
    let methodRef = TypedExpressionNode.methodReference(
      base: base, method: method, typeArgs: nil, methodTypeArgs: nil, type: method.type)
    return .call(callee: methodRef, arguments: [], type: returnType)
  }

  /// Extracts the element type T from an iterator type.
  /// The iterator must have a next(mutable self) -> [T]Option method.
  private func extractIteratorElementType(_ iteratorType: Type) throws -> Type {
    // Look up the next method on the iterator type
    guard let nextMethod = try lookupDeclaredMethod(on: iteratorType, name: "next") else {
      throw SemanticError(.generic(
        "Iterator type \(iteratorType) missing next() method"
      ), span: currentSpan)
    }
    
    // Verify the return type is [T]Option
    guard case .function(_, let returnType) = nextMethod.type else {
      throw SemanticError(.generic("Iterator.next() must be a function"), span: currentSpan)
    }
    
    // Check if return type is Option<T>
    if let inner = stdOptionInner(returnType) {
      return inner
    }
    throw SemanticError(.generic(
      "Iterator.next() must return [T]Option, got \(returnType)"
    ), span: currentSpan)
  }

  /// The `for` binding is a full match pattern, and a loop cannot skip an
  /// element the pattern refuses: it must cover every element value. Judged
  /// on the lowered pattern -- a tuple pattern only becomes total once the
  /// subject's arity is known. The syntactic irrefutability shortcut keeps its
  /// old answers; the exhaustiveness checker is what knows a single-case enum
  /// destructure or a full `or` of cases is total.
  private func typeCheckForBinding(
    _ pattern: PatternNode,
    elementType: Type
  ) throws -> TypedPattern {
    let (typed, _) = try checkPattern(pattern, subjectType: elementType)
    if !typed.isIrrefutable && !patternCoversFullSpace(typed, subjectType: elementType, span: pattern.span) {
      throw SemanticError(
        .generic("For binding cannot fail; use 'when' to match"),
        span: pattern.span
      )
    }
    return typed
  }

  /// Whether one lowered pattern covers every value of its subject type --
  /// the `for`-binding question, judged by the exhaustiveness checker's own
  /// coverage machinery rather than the syntactic irrefutability shortcut.
  private func patternCoversFullSpace(
    _ pattern: TypedPattern,
    subjectType: Type,
    span: SourceSpan
  ) -> Bool {
    let checker = ExhaustivenessChecker(
      subjectType: subjectType,
      patterns: [pattern],
      span: span,
      resolvedEnumCases: resolveEnumCasesForExhaustiveness(subjectType),
      context: context
    )
    return checker.coversFullSpace()
  }

  /// The optional `for` guard, checked with the pattern's bindings already in
  /// scope and required to be `Bool` -- the same rule a `when` arm guard gets.
  /// On the iterator path this becomes the arm guard of the loop's desugared
  /// match, where a false guard falls through to the skip-element arm and,
  /// on a pattern with several readings, is re-evaluated per reading.
  private func checkForGuard(_ guardExpr: ExpressionNode?) throws -> TypedExpressionNode? {
    guard let guardExpr else { return nil }
    return try checkGuardExpression(guardExpr)
  }

  /// A range loop has no match to hang a guard on, so its guard stays an
  /// `if` around the body: false skips the element and moves on, which is
  /// exactly what the body under an `if` does.
  /// A range loop has no match to hang a guard on, so its guard stays an
  /// `if` around the body: false skips the element and moves on, which is
  /// exactly what the body under an `if` does.
  private func underForGuard(
    _ typedBody: TypedExpressionNode,
    typedGuard: TypedExpressionNode?
  ) -> TypedExpressionNode {
    guard let typedGuard else { return typedBody }
    return .ifExpression(
      condition: typedGuard, thenBranch: typedBody, elseBranch: nil, type: .void)
  }

  /// Desugars a for loop into let + while + match.
  func desugarForLoop(
    pattern: TypedPattern,
    typedIterable: TypedExpressionNode,
    iteratorType: Type,
    elementType: Type,
    body: ExpressionNode,
    guardExpr: ExpressionNode?,
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
      // for 循环持有迭代器的**非拥有借用**：只需要「可变读写下一次 next()」，
      // 不接管所有权，也不参与引用计数。用瘦借用类型，而不是 owning 的 `*mutable T`。
      let iterRefExpr = TypedExpressionNode.referenceExpression(
        expression: iterVarExpr,
        type: .mutableBorrowedReference(inner: iteratorType)
      )
      let nextCall = try buildNextCall(iterRef: iterRefExpr, elementType: elementType)
      
      // Build the match expression body
      let whenExpr = try buildForLoopWhenExpression(
        nextCall: nextCall,
        pattern: pattern,
        body: body,
        guardExpr: guardExpr
      )
      
      let whileStmt = TypedStatementNode.whileStatement(
        condition: .booleanLiteral(value: true, type: .bool),
        body: whenExpr
      )

      return .blockExpression(
        statements: [
          .variableDeclaration(identifier: iterSymbol, value: iteratorInit, mutable: true),
          whileStmt,
        ],
        tailExpression: nil,
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
    if let (inner, _) = referenceTypeComponents(typedIterable.type) {
      actualIterable = .derefExpression(expression: typedIterable, type: inner)
      actualIterableType = inner
    }
    
    // Look up the iterator method
    guard let iteratorMethod = try lookupDeclaredMethod(on: actualIterableType, name: "iterator") else {
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
    // Get the iterator type from the reference (ref or ref mutable)
    let iteratorType: Type
    switch iterRef.type {
    case .reference(let inner),
         .mutableReference(let inner),
         .borrowedReference(let inner),
         .mutableBorrowedReference(let inner):
      iteratorType = inner
    default:
      throw SemanticError(.generic("Expected managed reference to iterator"), span: currentSpan)
    }
    
    // Look up the next method
    guard let nextMethod = try lookupDeclaredMethod(on: iteratorType, name: "next") else {
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
    let optionType = genericEnumType(template: "Option", args: [elementType])
    
    // Build call
    return .call(callee: methodRef, arguments: [], type: optionType)
  }

  /// Builds the match expression for the for loop body.
  /// The loop's per-element match: `while true { when iter.next() in { ... } }`.
  ///
  /// Without a guard the match has two arms -- the binding arm and the
  /// end-of-iteration arm that breaks. With a guard a third arm sits between
  /// them: the binding arm carries the guard as a real `when` arm guard (so
  /// on a pattern with several readings the guard is re-evaluated per
  /// reading), and a refused guard falls through to the middle arm, which
  /// matches the same wrapper and skips the element. The end arm stays last
  /// so a `None` still breaks instead of looping forever.
  func buildForLoopWhenExpression(
    nextCall: TypedExpressionNode,
    pattern: TypedPattern,
    body: ExpressionNode,
    guardExpr: ExpressionNode?
  ) throws -> TypedExpressionNode {
    // Build Some case pattern with the user's pattern
    let somePattern = buildSomePattern(userPattern: pattern)

    // Type check the guard and body in a new scope with pattern bindings. The
    // guard is checked first: its `is` bindings (and the pattern's, already in
    // scope) must be visible to the body.
    let (typedGuard, typedBody): (TypedExpressionNode?, TypedExpressionNode) = try withNewScope {
      // Bind pattern variables using the typed pattern symbols
      for symbol in extractPatternSymbols(from: somePattern) {
        if let name = context.getName(symbol.defId) {
          try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
        }
      }

      // Type check guard, then body
      let savedInLoop = inLoop
      inLoop = true
      defer { inLoop = savedInLoop }
      let checkedGuard = try checkForGuard(guardExpr)
      let checkedBody = try inferCheckedStatementBodyExpression(body)
      return (checkedGuard, checkedBody)
    }

    // Build match cases
    var cases: [TypedMatchCase] = []
    cases.append(TypedMatchCase(pattern: somePattern, guardExpr: typedGuard, body: typedBody))

    if typedGuard != nil {
      // The skip arm: the wrapper matched but the guard refused every reading
      // of the user's pattern. It mirrors the wrapper shape and never sees
      // the end-of-iteration value, which the break arm below owns.
      let emptyExpr = TypedExpressionNode.blockExpression(
        statements: [],
        tailExpression: nil,
        type: .void
      )
      cases.append(
        TypedMatchCase(pattern: buildSomePattern(userPattern: .wildcard), guardExpr: nil, body: emptyExpr))
    }

    // Build None case with break
    let nonePattern = TypedPattern.enumCase(caseName: "None", tagIndex: 0, elements: [])
    let breakExpr = TypedExpressionNode.blockExpression(
      statements: [.break],
      tailExpression: nil,
      type: .void
    )
    cases.append(TypedMatchCase(pattern: nonePattern, guardExpr: nil, body: breakExpr))

    return .whenExpression(
      subject: nextCall,
      cases: cases,
      type: .void
    )
  }

  /// Builds the Some pattern wrapping the user's pattern.
  func buildSomePattern(userPattern: TypedPattern) -> TypedPattern {
    // Some has tag index 1 (None is 0, Some is 1 in Option)
    return .enumCase(caseName: "Some", tagIndex: 1, elements: [userPattern])
  }

  /// Converts an AST pattern to a typed pattern.
  func convertPatternToTypedPattern(_ pattern: PatternNode, expectedType: Type) throws -> TypedPattern {
    switch pattern {
    case .weakBinding(let name, _, _):
      let symbol = makeLocalSymbol(name: name, type: expectedType, kind: .variable(.Value))
      return .weakBinding(symbol: symbol)
    case .variable(let name, let mutable, _):
      let varKind: VariableKind = mutable ? .MutableValue : .Value
      let symbol = makeLocalSymbol(name: name, type: expectedType, kind: .variable(varKind))
      return .variable(symbol: symbol)
    case .wildcard:
      return .wildcard
    case .booleanLiteral(let value, _):
      return .booleanLiteral(value: value)
    case .nullLiteral:
      return .nullLiteral(resultType: expectedType)
    case .integerLiteral(let value, _):
      return .integerLiteral(value: value)
    case .negativeIntegerLiteral(let value, _):
      return .integerLiteral(value: "-\(value)")
    case .floatLiteral(let value, _):
      return .floatLiteral(value: value)
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
    case .comparisonPattern(let op, let value, let valueKind, _):
      switch valueKind {
      case .integer, .float:
        return .comparisonPattern(operator: op, value: value)
      case .rune:
        let cp = singleRuneCodePoint(from: value).map { String($0) } ?? value
        return .comparisonPattern(operator: op, value: cp)
      }
    case .traitObjectType, .traitObjectTypeBinding:
      let (typedPattern, _) = try checkPattern(pattern, subjectType: expectedType)
      return typedPattern
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
    case .tuplePattern(let elements, _):
      let typedElements = try elements.map { elem -> TypedPattern in
        try convertPatternToTypedPattern(elem.pattern, expectedType: .void)
      }
      // The SUBJECT decides which struct this is; the name here is display-only.
      return .structPattern(typeName: expectedType.description, elements: typedElements)
    case .listPattern:
      // Carries resolved std method symbols, so it goes through the full
      // pattern check rather than this shallow conversion.
      let (typedPattern, _) = try checkPattern(pattern, subjectType: expectedType)
      return typedPattern
    case .restPattern:
      return .restPattern
    }
  }

  /// Binds pattern variables in the current scope.
  func bindPatternVariables(pattern: PatternNode, type: Type) throws {
    switch pattern {
    case .weakBinding(let name, _, _):
      let symbol = makeLocalSymbol(name: name, type: type, kind: .variable(.Value))
      try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
    case .variable(let name, let mutable, _):
      let symbol = makeLocalSymbol(
        name: name,
        type: type,
        kind: mutable ? .variable(.MutableValue) : .variable(.Value)
      )
      try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
    case .wildcard, .booleanLiteral, .integerLiteral, .floatLiteral, .stringLiteral, .runeLiteral, .negativeIntegerLiteral, .traitObjectType, .nullLiteral:
      break
    case .traitObjectTypeBinding(let name, let mutable, let targetType, let span):
      let boundType = try resolveTraitObjectPatternTargetType(targetType, subjectType: type, span: span)
      let symbol = makeLocalSymbol(
        name: name,
        type: boundType,
        kind: mutable ? .variable(.MutableValue) : .variable(.Value)
      )
      try currentScope.defineLocal(name, defId: symbol.defId, span: currentSpan)
    case .enumCase(_, let elements, _):
      for elem in elements {
        try bindPatternVariables(pattern: elem.pattern, type: .void)
      }
    case .structPattern(_, let elements, _),
         .tuplePattern(let elements, _):
      for elem in elements {
        try bindPatternVariables(pattern: elem.pattern, type: .void)
      }
    case .listPattern(let elements, _):
      // Slots bind elements of the subject's element type, not the list itself.
      let elementType: Type
      if case .list(let element) = resolveBuiltinSubscriptKind(baseType: type) {
        elementType = element
      } else {
        elementType = .void
      }
      for element in elements {
        try bindPatternVariables(pattern: element, type: elementType)
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
    case .restPattern:
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

  /// The fixed error type for Result: `Error ref` (trait object), where `Error`
  /// is std's trait -- identified by declaration, not spelling.
  private var resultErrorType: Type {
    .reference(inner: .traitObject(
      traitDefId: stdErrorTraitDefId ?? .invalid,
      typeArgs: []))
  }

  /// Extracts Option/Result kind from a type, or throws a diagnostic.
  private func extractOptionResultKind(
    _ type: Type, span: SourceSpan, operation: String
  ) throws -> OptionResultKind {
    if let inner = stdOptionInner(type) {
      return .option(innerType: inner)
    }
    if let ok = stdResultInner(type) {
      return .result(okType: ok, errType: resultErrorType)
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

    // `as e in body` names the payload; a plain default binds nothing -- the
    // payload has no implicit name. Only a Result carries an error to name --
    // `None` has no payload, so the binder form on Option is refused rather
    // than bound to something meaningless. Each `or else` opens its own payload
    // scope so an enclosing `and then` / `or else` binding never leaks in.
    let payloadName: String
    let defaultBody: ExpressionNode
    switch defaultExpr {
    case .flowBindExpression(let name, let body, let bindSpan):
      payloadName = name
      defaultBody = body
      if case .option = kind {
        // Recorded, not thrown: the body still type-checks so the reader sees
        // one complaint about the binder rather than a cascade from dropping it.
        try handleError(SemanticError(
          .generic("Option's 'None' has no payload to bind; use 'or else' without 'as ... in'"),
          span: bindSpan
        ))
      }
    default:
      // A plain default binds NOTHING -- the payload has no implicit name. The
      // lowered `when` still needs a variable to carry the payload from the
      // matching arm to the result; it stays unreferenced.
      payloadName = TypeChecker.flowPayloadName
      defaultBody = defaultExpr
    }
    let hasBind: Bool
    if case .flowBindExpression = defaultExpr {
      hasBind = true
    } else {
      hasBind = false
    }

    let boundType: Type
    switch kind {
    case .result(_, let errType):
      boundType = errType
    case .option:
      boundType = innerType
    }

    let underscoreSymbol = makeLocalSymbol(
      name: payloadName, type: boundType, kind: .variable(.Value))
    let typedDefault: TypedExpressionNode = try withNewScope {
      if hasBind {
        currentScope.define(payloadName, defId: underscoreSymbol.defId)
      }
      return try normalizeBranchExpression(
        try inferTypedExpression(defaultBody, expectedType: innerType, usage: .value),
        expectedType: innerType
      )
    }

    let resultType = innerType
    switch kind {
    case .option:
      // `it` is the unwrapped value: bound by the Some pattern so references in
      // the default expression resolve to the same DefId.
      let itSym = underscoreSymbol
      let somePattern = TypedPattern.enumCase(caseName: "Some", tagIndex: 1,
                                                elements: [.variable(symbol: itSym)])
      let nonePattern = TypedPattern.enumCase(caseName: "None", tagIndex: 0, elements: [])
      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: somePattern, guardExpr: nil, body: .variable(identifier: itSym)),
          TypedMatchCase(pattern: nonePattern, guardExpr: nil, body: typedDefault),
        ],
        type: resultType
      )

    case .result(let okType, _):
      let valSym = makeLocalSymbol(name: "__val", type: okType, kind: .variable(.Value))
      // Reuse the DefId from the `_` injection so references in defaultExpr resolve correctly.
      let errSym = underscoreSymbol
      let okPattern = TypedPattern.enumCase(caseName: "Ok", tagIndex: 0,
                                             elements: [.variable(symbol: valSym)])
      let errPattern = TypedPattern.enumCase(caseName: "Error", tagIndex: 1,
                                              elements: [.variable(symbol: errSym)])
      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: okPattern, guardExpr: nil, body: .variable(identifier: valSym)),
          TypedMatchCase(pattern: errPattern, guardExpr: nil, body: typedDefault),
        ],
        type: resultType
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
    // Where the construct stands decides whether it may exist at all, and that
    // is said BEFORE its operand is looked at: `or return` inside a `defer` is
    // wrong whatever it is applied to. Recording it and then looking inside
    // keeps the operand's own complaints visible without putting them ahead of
    // the complaint about the whole.
    var misplaced = false
    if insideDefer {
      try handleError(SemanticError(
        .generic("control flow statement 'return' is not allowed in defer expression"),
        span: span
      ))
      misplaced = true
    }

    let typedOperand = try inferTypedExpression(operand)
    if misplaced {
      // The construct has objected to its own placement. Desugaring it would
      // put a `return` in the same place and say the same thing again.
      return typedOperand
    }
    let kind = try extractOptionResultKind(typedOperand.type, span: span, operation: "or return")

    // `or return` desugars to `or else` with a fixed fallback. The Result case
    // names the error through a binder, so the sugar never depends on a magic
    // identifier.
    let defaultExpr: ExpressionNode
    switch kind {
    case .option:
      let noneReturn = ExpressionNode.implicitMemberExpression(
        memberName: "None", arguments: [], span: span)
      defaultExpr = .blockExpression(
        statements: [.return(value: noneReturn, span: span)],
        tailExpression: nil,
        span: span
      )
    case .result:
      let errName = "err"
      let errReturn = ExpressionNode.implicitMemberExpression(
        memberName: "Error",
        arguments: [CallArg(label: nil, expression: .identifier(errName, span: span))],
        span: span
      )
      let body: ExpressionNode = .blockExpression(
        statements: [.return(value: errReturn, span: span)],
        tailExpression: nil,
        span: span
      )
      defaultExpr = .flowBindExpression(name: errName, body: body, span: span)
    }

    return try lowerOrElseExpressionCore(
      typedOperand: typedOperand,
      kind: kind,
      defaultExpr: defaultExpr,
      span: span
    )
  }

  // MARK: - and then Lowering

  /// Result type of `operand and then transform`.
  ///
  /// The transform's value is always wrapped in the operand's own flow enum:
  /// `Option[U]` for an `Option` operand, `Result[U]` for a `Result` one, where
  /// `U` is whatever the transform returns. There is NO flattening -- a
  /// transform that itself returns `Option[V]` yields `Option[Option[V]]` --
  /// because flattening makes the result type depend on the SHAPE of the
  /// transform's type, which a generic transform does not have yet.
  /// Whether `operand and then transform` adopts the transform's value as the
  /// result instead of wrapping it.
  ///
  /// The transform's DECLARED return type decides, never its shape after
  /// substitution: a generic parameter is opaque and always wraps. Deciding
  /// again at instantiation would fold `map[U Any](f (T) -> U) Option[U]` down
  /// to `Option[V]` for `U = Option[V]` and break its signature.
  private func andThenCollapses(
    operandKind: OptionResultKind,
    transformResultType: Type
  ) -> Bool {
    switch operandKind {
    case .option:
      return stdOptionInner(transformResultType) != nil
    case .result:
      return stdResultInner(transformResultType) != nil
    }
  }

  /// Result type of `operand and then transform`.
  ///
  /// Always the operand's own flow enum -- `Option` stays `Option`, `Result`
  /// stays `Result`. The inner type is the transform's own when its DECLARED
  /// return type is already that same flow enum (`andThenCollapses`), and the
  /// transform's type wrapped in one level otherwise. So `x and then f(it)` with
  /// `f: (T) -> U` is `Option[U]` for every `U`, including `U = Option[V]`.
  /// See `docs/design/flow-operator-forms.md`.
  private func computeAndThenResultType(
    operandKind: OptionResultKind,
    transformResultType: Type
  ) -> Type {
    if andThenCollapses(operandKind: operandKind, transformResultType: transformResultType) {
      return transformResultType
    }
    switch operandKind {
    case .option:
      guard let optionDefId = stdOptionEnumDefId else {
        return transformResultType
      }
      return genericEnumType(template: "Option", templateDefId: optionDefId, args: [transformResultType])

    case .result:
      guard let resultDefId = stdResultEnumDefId else {
        return transformResultType
      }
      return genericEnumType(template: "Result", templateDefId: resultDefId, args: [transformResultType])
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
    let transformExpectedType: Type? = nil

    // Two operand shapes, two payload names:
    //   `as v in body` -- the user's own name
    //   `.f(x)` chain  -- the reserved name `flowReceiver` resolves to
    //   plain expr     -- not a form; the parser rejects it
    let payloadName: String
    let transformBody: ExpressionNode
    switch transformExpr {
    case .flowBindExpression(let name, let body, _):
      payloadName = name
      transformBody = body
    case .flowChainExpression(let chain, _):
      payloadName = TypeChecker.flowPayloadName
      transformBody = chain
    default:
      payloadName = TypeChecker.flowPayloadName
      transformBody = transformExpr
    }

    // Create the payload symbol, type-check the body in a child scope with it injected.
    let underscoreSymbol = makeLocalSymbol(name: payloadName, type: innerType, kind: .variable(.Value))
    let typedTransform = try withNewScope {
      currentScope.define(payloadName, defId: underscoreSymbol.defId)
      return try normalizeBranchExpression(
        try inferTypedExpression(transformBody, expectedType: transformExpectedType, usage: .value),
        expectedType: transformExpectedType
      )
    }
    let transformType = typedTransform.type

    let finalType = computeAndThenResultType(
      operandKind: kind, transformResultType: transformType)

    // Collapsing adopts the transform's value as the arm body; wrapping builds
    // `Some(v)` / `Ok(v)` around it. The empty side always re-wraps its own
    // `None` / `Error`.
    let collapses = andThenCollapses(
      operandKind: kind, transformResultType: transformType)

    // Build the lowered whenExpression.
    switch kind {
    case .option:
      // Reuse underscoreSymbol as the Some pattern variable (DefId sharing).
      let somePattern = TypedPattern.enumCase(caseName: "Some", tagIndex: 1,
                                                elements: [.variable(symbol: underscoreSymbol)])
      let nonePattern = TypedPattern.enumCase(caseName: "None", tagIndex: 0, elements: [])

      let someBody = collapses ? typedTransform : TypedExpressionNode.enumConstruction(
        type: finalType, caseName: "Some", arguments: [typedTransform])
      let noneBody = TypedExpressionNode.enumConstruction(
        type: finalType, caseName: "None", arguments: [])

      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: somePattern, guardExpr: nil, body: someBody),
          TypedMatchCase(pattern: nonePattern, guardExpr: nil, body: noneBody),
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

      let okBody = collapses ? typedTransform : TypedExpressionNode.enumConstruction(
        type: finalType, caseName: "Ok", arguments: [typedTransform])
      let errBody = TypedExpressionNode.enumConstruction(
        type: finalType, caseName: "Error",
        arguments: [.variable(identifier: errSym)])

      return .whenExpression(
        subject: typedOperand,
        cases: [
          TypedMatchCase(pattern: okPattern, guardExpr: nil, body: okBody),
          TypedMatchCase(pattern: errPattern, guardExpr: nil, body: errBody),
        ],
        type: finalType
      )
    }
  }

}

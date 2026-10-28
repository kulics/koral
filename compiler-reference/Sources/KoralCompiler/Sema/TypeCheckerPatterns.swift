import Foundation

// MARK: - Pattern Type Checking Extension
// This extension contains methods for pattern matching type checking.

extension TypeChecker {

  func resolveTraitObjectPatternTargetType(
    _ targetTypeNode: TypeNode,
    subjectType: Type,
    span: SourceSpan
  ) throws -> Type {
    guard let subjectIsMutable = traitObjectPatternSubjectMutability(subjectType) else {
      throw SemanticError(.generic(
        "Trait object type patterns require a trait object subject, got '\(subjectType)'"
      ), span: span)
    }

    let resolvedTarget = try resolveTypeNode(targetTypeNode)
    switch resolvedTarget {
    case .reference(let inner):
      try validateTraitObjectPatternConcreteType(inner, span: span)
      return .reference(inner: inner)
    case .mutableReference(let inner):
      guard subjectIsMutable else {
        throw SemanticError(.generic(
          "Trait object type pattern '\(resolvedTarget)' requires a mutable trait object subject"
        ), span: span)
      }
      try validateTraitObjectPatternConcreteType(inner, span: span)
      return .mutableReference(inner: inner)
    // New syntax: bare concrete type (no * prefix)
    case .structure, .enum, .genericStruct, .genericEnum:
      try validateTraitObjectPatternConcreteType(resolvedTarget, span: span)
      return resolvedTarget
    default:
      throw SemanticError(.generic(
        "Trait object type pattern must be a concrete type name or a trait name, got '\(resolvedTarget)'"
      ), span: span)
    }
  }

  private func traitObjectPatternSubjectMutability(_ type: Type) -> Bool? {
    switch type {
    case .reference(let inner):
      if case .traitObject = inner { return false }
      return nil
    case .mutableReference(let inner):
      if case .traitObject = inner { return true }
      return nil
    default:
      return nil
    }
  }

  private func validateTraitObjectPatternConcreteType(_ type: Type, span: SourceSpan) throws {
    switch type {
    case .structure,
         .enum,
         .opaque,
         .genericStruct,
         .genericEnum:
      return
    default:
      throw SemanticError(.generic(
        "Trait object type pattern target must be a concrete nominal type, got '\(type)'"
      ), span: span)
    }
  }

  /// Check if a field is accessible from the current source file/module.
  /// - Parameters:
  ///   - fieldAccess: The access modifier of the field
  ///   - defId: The DefId of the type that defines the field
  /// - Returns: true if the field is accessible
  private func isFieldAccessible(fieldAccess: AccessModifier, defId: DefId) -> Bool {
    switch fieldAccess {
    case .public:
      return true
    case .file_private:
      // Private: only accessible from the same file
      let defSourceFile = context.getSourceFile(defId) ?? ""
      return isSameSourceFile(defSourceFile, currentSourceFile)
    case .module_private:
      // Protected: accessible from the same logical module only.
      let defModulePath = context.getModulePath(defId) ?? []
      return defModulePath == currentModulePath
    case .package_private:
      guard !currentPackageID.isEmpty else { return false }
      return context.getPackageID(defId) == currentPackageID
    }
  }

  /// Whether a pattern TESTS the shape of its subject, as opposed to simply
  /// binding whatever is there.
  private func patternTestsSubjectShape(_ pattern: PatternNode) -> Bool {
    switch pattern {
    case .variable, .wildcard:
      return false
    case .weakBinding:
      // `?name` is the one pattern allowed to test a weak handle; it probes
      // liveness, not the shape hiding behind the handle.
      return false
    default:
      return true
    }
  }

  private func isWeakReferenceType(_ type: Type) -> Bool {
    switch type {
    case .weakReference, .mutableWeakReference:
      return true
    default:
      return false
    }
  }

  /// The strong type a weak reference wraps, or nil if `type` is not weak.
  func weakReferenceInnerType(_ type: Type) -> Type? {
    switch type {
    case .weakReference(let inner), .mutableWeakReference(let inner):
      return inner
    default:
      return nil
    }
  }


  /// A weak reference is opaque until `upgrade`d. Reject it as a pattern
  /// subject before anything peels it, so the diagnostic names the weak
  /// reference the user wrote and not the type hiding behind it. The `?name`
  /// unpacking pattern is the one pattern that legitimately tests a weak handle.
  func rejectWeakPatternSubject(_ type: Type, pattern: PatternNode? = nil, span: SourceSpan) throws {
    if case .weakBinding = pattern { return }
    if isWeakReferenceType(type) {
      throw SemanticError(
        .generic("Cannot match a pattern against a weak reference: upgrade it first"),
        span: span
      )
    }
  }

  func checkPattern(_ pattern: PatternNode, subjectType: Type) throws -> (
    TypedPattern, [(String, Bool, Type)]
  ) {
    var bindings: [(String, Bool, Type)] = []

    // `?name` / `?TypeName(name)` unpacks a weak reference. It is the only
    // pattern that tests a weak handle; everything else that probes shape is
    // rejected below. The subject may be the weak handle `?T` or the already
    // upgraded `Option[T]` (the `when` desugaring wraps it).
    if case .weakBinding(let name, let targetType, let span) = pattern {
      let strongType: Type
      if let inner = weakReferenceInnerType(subjectType) {
        strongType = inner
      } else if case .genericEnum(let tplDefId, let args) = subjectType, args.count == 1,
                tplDefId == currentScope.lookupGenericEnumTemplate("Option")?.defId {
        strongType = args[0]
      } else {
        throw SemanticError(.generic(
          "Weak binding pattern '?\(name)' requires a weak reference subject"
        ), span: span)
      }
      var bindingType = strongType
      if let targetType {
        let resolvedTarget = try resolveTypeNode(targetType)
        guard resolvedTarget == strongType else {
          throw SemanticError.typeMismatch(
            expected: resolvedTarget.description,
            got: strongType.description
          )
        }
        bindingType = resolvedTarget
      }
      let symbol = makeLocalSymbol(name: name, type: bindingType, kind: .variable(.Value))
      return (.weakBinding(symbol: symbol), [(name, false, bindingType)])
    }

    // A weak reference is opaque until `upgrade`d -- it carries no fields, no
    // cases and no payload -- so testing one's shape is not meaningful. Binding
    // the handle whole is fine.
    if patternTestsSubjectShape(pattern), isWeakReferenceType(subjectType) {
      throw SemanticError(
        .generic("Cannot match a pattern against a weak reference: upgrade it first"),
        span: pattern.span
      )
    }

    switch pattern {
    case .weakBinding(let name, _, let span):
      // Handled above; unreachable here.
      throw SemanticError(.generic("Weak binding '?\(name)' is not valid here"), span: span)

    case .traitObjectType(let targetType, let span):
      let resolvedTarget = try resolveTraitObjectPatternTargetType(targetType, subjectType: subjectType, span: span)
      return (.traitObjectType(targetType: resolvedTarget), [])

    case .traitObjectTypeBinding(let name, let mutable, let targetType, let span):
      let resolvedTarget = try resolveTraitObjectPatternTargetType(targetType, subjectType: subjectType, span: span)
      let symbol = makeLocalSymbol(
        name: name,
        type: resolvedTarget,
        kind: .variable(mutable ? .MutableValue : .Value)
      )
      return (.traitObjectTypeBinding(symbol: symbol, targetType: resolvedTarget), [(name, mutable, resolvedTarget)])

    case .integerLiteral(let val, let span):
      if !subjectType.isIntegerType {
        throw SemanticError(.typeMismatch(expected: "integer type", got: subjectType.description), span: span)
      }
      return (.integerLiteral(value: val), [])

    case .floatLiteral(let val, let span):
      if !isFloatType(subjectType) {
        throw SemanticError(.typeMismatch(expected: "Float32 or Float64", got: subjectType.description), span: span)
      }
      return (.floatLiteral(value: val), [])

    case .negativeIntegerLiteral(let val, let span):
      // Negative integer literal pattern - verify subject is integer type
      if !subjectType.isIntegerType {
        throw SemanticError(.typeMismatch(expected: "integer type", got: subjectType.description), span: span)
      }
      switch subjectType {
      case .uint, .uint8, .uint16, .uint32, .uint64,
           .wrappingUInt, .wrappingUInt8, .wrappingUInt16, .wrappingUInt32, .wrappingUInt64:
        throw SemanticError(.generic("Negative integer literal cannot match unsigned type"), span: span)
      default:
        break
      }
      // Store as negative value string
      return (.integerLiteral(value: "-\(val)"), [])

    case .booleanLiteral(let val, let span):
      if subjectType != .bool {
        throw SemanticError(.typeMismatch(expected: "Bool", got: subjectType.description), span: span)
      }
      return (.booleanLiteral(value: val), [])

    case .nullLiteral(let span):
      // A pointer literal pattern joins the SUBJECT's pointer type; any other
      // subject is the mismatch row with the literal's spelling on the
      // got-side. Managed-reference wrappers peel to the pointer underneath;
      // a pointer itself is the value being tested and never peels further.
      var subject = subjectType
      switch subject {
      case .reference(let inner), .mutableReference(let inner),
           .borrowedReference(let inner), .mutableBorrowedReference(let inner):
        subject = inner
      default:
        break
      }
      switch subject {
      case .pointer, .mutablePointer:
        return (.nullLiteral(resultType: subject), [])
      default:
        throw SemanticError(
          .typeMismatch(expected: subjectType.description, got: "null"), span: span)
      }

    case .stringLiteral(let value, let span):
      if isStringType(subjectType) {
        return (.stringLiteral(value: value), [])
      }
      throw SemanticError(.typeMismatch(expected: "String", got: subjectType.description), span: span)

    case .runeLiteral(let value, let span):
      if isRuneType(subjectType) {
        guard let cp = singleRuneCodePoint(from: value) else {
          let count = value.unicodeScalars.count
          if count == 0 {
            throw SemanticError(.generic("Rune literal cannot be empty"), span: span)
          }
          throw SemanticError(.generic("Rune literal must contain exactly one Unicode code point, but '\(value)' contains \(count)"), span: span)
        }
        return (.integerLiteral(value: String(cp)), [])
      }
      if subjectType == .uint8 {
        guard let cp = singleRuneCodePoint(from: value), cp <= 127 else {
          throw SemanticError(
            .generic("Rune literal pattern must be a single ASCII character when matching UInt8"),
            span: span)
        }
        return (.integerLiteral(value: String(cp)), [])
      }
      throw SemanticError(.typeMismatch(expected: "Rune or UInt8", got: subjectType.description), span: span)

    case .wildcard(_):
      return (.wildcard, [])

    case .variable(let name, let mutable, _):
      // Bind variable to the subject
      let symbol = makeLocalSymbol(
        name: name,
        type: subjectType,
        kind: .variable(mutable ? .MutableValue : .Value)
      )
      return (.variable(symbol: symbol), [(name, mutable, subjectType)])

    case .enumCase(let caseName, let subPatternArgs, let span):
      switch subjectType {
      case .structure, .genericStruct:
        return try checkPattern(.structPattern(typeName: caseName, elements: subPatternArgs, span: span), subjectType: subjectType)
      default:
        break
      }

      // Handle both concrete enum and genericEnum types
      let typeName: String
      let cases: [EnumCase]
      let enumDefId: DefId?
      
      switch subjectType {
      case .`enum`(let defId):
        typeName = context.getName(defId) ?? ""
        cases = context.getEnumCases(defId) ?? []
        enumDefId = defId
        
      case .genericEnum(let tplDefId, let typeArgs):
        // Look up the enum template and substitute type parameters
        guard let template = currentScope.genericEnumTemplate(defId: tplDefId) else {
          throw SemanticError.undefinedType(Type.spelling(tplDefId))
        }
        
        typeName = Type.spelling(tplDefId)
        enumDefId = template.defId
        
        // Create substitution map
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = typeArgs[i]
        }
        
        // Resolve case parameter types with substitution
        cases = try template.cases.map { caseDef in
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
        
      default:
        throw SemanticError.typeMismatch(expected: "Enum Type", got: subjectType.description)
      }

      guard let caseIndex = cases.firstIndex(where: { $0.name == caseName }) else {
        throw SemanticError(.generic("Enum case '\(caseName)' not found in type '\(typeName)'"))
      }
      let caseDef = cases[caseIndex]

      let orderedPatternArgs = try reorderPatternArguments(
        expandRestSlots(
          subPatternArgs,
          fieldNames: caseDef.parameters.map { $0.name },
          fieldIsNamed: caseDef.parameters.map { $0.named },
          patternSpan: span
        ),
        fieldNames: caseDef.parameters.map { $0.name },
        fieldIsNamed: caseDef.parameters.map { $0.named },
        patternDescription: ".\(caseName)",
        patternSpan: span
      )
      let subPatterns = orderedPatternArgs.map { $0.pattern }

      var typedSubPatterns: [TypedPattern] = []
      for (idx, subPat) in subPatterns.enumerated() {
        let fieldAccess = caseDef.parameters[idx].access
        
        // Check field visibility - if not accessible, only wildcard is allowed
        if let defId = enumDefId, !isFieldAccessible(fieldAccess: fieldAccess, defId: defId) {
          if case .wildcard = subPat {
            // Wildcard doesn't access the field value, allowed
          } else {
            let fieldName = caseDef.parameters[idx].name
            let accessLabel = fieldAccess.description
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(fieldName)' of type '\(typeName)' in destructuring pattern"
            ), span: subPat.span)
          }
        }
        
        let paramType = caseDef.parameters[idx].type
        let (typedSub, subBindings) = try checkPattern(subPat, subjectType: paramType)
        typedSubPatterns.append(typedSub)
        bindings.append(contentsOf: subBindings)
      }

      return (
        .enumCase(caseName: caseName, tagIndex: caseIndex, elements: typedSubPatterns), bindings
      )
      
    case .comparisonPattern(let op, let value, let valueKind, let span):
      // The value's kind must match the subject's kind -- the same rule a
      // literal equality pattern follows. A comparison bound may sit outside
      // the subject's domain (`>= -1` on `UInt8` is true of everything), so
      // unlike a negative equality pattern there is no signedness check here.
      switch valueKind {
      case .integer:
        if !subjectType.isIntegerType {
          throw SemanticError(.typeMismatch(expected: "integer type", got: subjectType.description), span: span)
        }
        return (.comparisonPattern(operator: op, value: value), [])
      case .float:
        if !isFloatType(subjectType) {
          throw SemanticError(.typeMismatch(expected: "Float32 or Float64", got: subjectType.description), span: span)
        }
        return (.comparisonPattern(operator: op, value: value), [])
      case .rune:
        // Desugar to the code point, the way a rune equality pattern does.
        guard let cp = singleRuneCodePoint(from: value) else {
          let count = value.unicodeScalars.count
          if count == 0 {
            throw SemanticError(.generic("Rune literal cannot be empty"), span: span)
          }
          throw SemanticError(.generic("Rune literal must contain exactly one Unicode code point, but '\(value)' contains \(count)"), span: span)
        }
        if isRuneType(subjectType) {
          return (.comparisonPattern(operator: op, value: String(cp)), [])
        }
        if subjectType == .uint8 {
          guard cp <= 127 else {
            throw SemanticError(
              .generic("Rune literal pattern must be a single ASCII character when matching UInt8"),
              span: span)
          }
          return (.comparisonPattern(operator: op, value: String(cp)), [])
        }
        throw SemanticError(.typeMismatch(expected: "Rune or UInt8", got: subjectType.description), span: span)
      }
      
    case .andPattern(let left, let right, let span):
      let (typedLeft, leftBindings) = try checkPattern(left, subjectType: subjectType)
      let (typedRight, rightBindings) = try checkPattern(right, subjectType: subjectType)
      
      // and pattern cannot bind the same variable name in both branches
      let leftNames = Set(leftBindings.map { $0.0 })
      let rightNames = Set(rightBindings.map { $0.0 })
      let overlap = leftNames.intersection(rightNames)
      
      if !overlap.isEmpty {
        throw SemanticError(.generic(
          "And pattern cannot bind the same variable in both branches: \(overlap.sorted().joined(separator: ", "))"
        ), span: span)
      }
      
      return (.andPattern(left: typedLeft, right: typedRight), leftBindings + rightBindings)
      
    case .orPattern(let left, let right, let span):
      let (typedLeft, leftBindings) = try checkPattern(left, subjectType: subjectType)
      let (typedRight, rightBindings) = try checkPattern(right, subjectType: subjectType)
      
      // or pattern branches must bind the same variables
      let leftNames = Set(leftBindings.map { $0.0 })
      let rightNames = Set(rightBindings.map { $0.0 })
      
      if leftNames != rightNames {
        throw SemanticError(.generic(
          "Or pattern branches must bind the same variables. Left binds: {\(leftNames.sorted().joined(separator: ", "))}, Right binds: {\(rightNames.sorted().joined(separator: ", "))}"
        ), span: span)
      }
      
      // Check type consistency for bindings
      for (name, _, leftType) in leftBindings {
        if let (_, _, rightType) = rightBindings.first(where: { $0.0 == name }) {
          if leftType != rightType {
            throw SemanticError(.typeMismatch(
              expected: leftType.description,
              got: rightType.description
            ), span: span)
          }
        }
      }

      let canonicalSymbolsByName = patternSymbolsByName(in: typedLeft)
      let canonicalRight = canonicalizePatternBindings(typedRight, canonicalSymbolsByName: canonicalSymbolsByName)
      return (.orPattern(left: typedLeft, right: canonicalRight), leftBindings)
      
    case .notPattern(let innerPattern, let span):
      let (typedPattern, innerBindings) = try checkPattern(innerPattern, subjectType: subjectType)
      
      // not pattern cannot contain variable bindings
      if !innerBindings.isEmpty {
        throw SemanticError(.generic(
          "Not pattern cannot contain variable bindings"
        ), span: span)
      }
      
      return (.notPattern(pattern: typedPattern), [])
      
    case .structPattern(let typeName, let subPatternArgs, let span):
      // Get struct member info based on subject type
      let members: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)]
      let structDefId: DefId?
      // The pattern's name is resolved ONCE, here, and everything below
      // compares the declaration it denotes. A non-generic nominal lives in the
      // type table and a generic one in the template table, so the one lookup
      // consults whichever answers. `typeName` survives only to print.
      let patternDefId = currentScope.lookupType(typeName).flatMap { nominalDefId(for: $0) }
        ?? currentScope.lookupGenericStructTemplate(typeName)?.defId
      
      switch subjectType {
      case .structure(let defId):
        guard patternDefId == defId else {
          throw SemanticError(.typeMismatch(
            expected: typeName, got: subjectType.description), span: span)
        }
        members = context.getStructMembers(defId) ?? []
        structDefId = defId
        
      case .genericStruct(let tplDefId, let typeArgs):
        guard patternDefId == tplDefId else {
          throw SemanticError(.typeMismatch(
            expected: typeName, got: subjectType.description), span: span)
        }
        // The subject's own DECLARATION is the template; no name is re-read.
        guard let template = currentScope.genericStructTemplate(defId: tplDefId) else {
          throw SemanticError.undefinedType(typeName)
        }
        
        // Create substitution map
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = typeArgs[i]
        }
        
        // Resolve member types with substitution
        members = try template.parameters.map { param in
          let resolvedType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(param.type)
          }
          let fieldAccess = param.access
          return (name: param.name, type: resolvedType, mutable: param.mutable, access: fieldAccess, named: param.named, defaultValue: param.defaultValue)
        }
        structDefId = template.defId
        
      default:
        throw SemanticError(.typeMismatch(
          expected: "Struct Type", got: subjectType.description), span: span)
      }
      
      let orderedPatternArgs = try reorderPatternArguments(
        expandRestSlots(
          subPatternArgs,
          fieldNames: members.map { $0.name },
          fieldIsNamed: members.map { $0.named },
          patternSpan: span
        ),
        fieldNames: members.map { $0.name },
        fieldIsNamed: members.map { $0.named },
        patternDescription: typeName,
        patternSpan: span
      )
      let subPatterns = orderedPatternArgs.map { $0.pattern }
      
      // Recursively check each sub-pattern with visibility check
      var typedSubPatterns: [TypedPattern] = []
      for (idx, subPat) in subPatterns.enumerated() {
        let fieldAccess = members[idx].access
        
        // Check field visibility - if not accessible, only wildcard is allowed
        if let defId = structDefId, !isFieldAccessible(fieldAccess: fieldAccess, defId: defId) {
          if case .wildcard = subPat {
            // Wildcard doesn't access the field value, allowed
          } else {
            let fieldName = members[idx].name
            let accessLabel = fieldAccess.description
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(fieldName)' of type '\(typeName)' in destructuring pattern"
            ), span: subPat.span)
          }
        }
        
        let fieldType = members[idx].type
        let (typedSub, subBindings) = try checkPattern(subPat, subjectType: fieldType)
        typedSubPatterns.append(typedSub)
        bindings.append(contentsOf: subBindings)
      }
      
      return (.structPattern(typeName: typeName, elements: typedSubPatterns), bindings)

    case .tuplePattern(let elements, let span):
      // `(a, b, c)` -- positional destructuring of a struct with exactly that
      // many fields, in declaration order. The SUBJECT decides which struct
      // this is, so no name is written and none is looked up: identity comes
      // from the type being matched, never from a spelling.
      let innerType = unwrapTupleSubjectType(subjectType)
      guard let members = try tupleDestructuringMembers(of: innerType) else {
        throw SemanticError(
          .typeMismatch(expected: "a struct", got: innerType.description),
          span: span
        )
      }
      // Tuple destructuring is positional throughout and takes no rest slot:
      // the parser rejects one here (a whole-list elision is written
      // `Point(...)`, not `(...)`), so the element list arrives already final.
      guard elements.count == members.count else {
        throw SemanticError(
          .typeMismatch(
            expected: "\(members.count) pattern elements",
            got: "\(elements.count)"
          ),
          span: span
        )
      }
      for arg in elements {
        if let label = arg.label {
          throw SemanticError(
            .generic(
              "Type mismatch: tuple destructuring is positional, got a named element '\(label)'"
            ),
            span: span
          )
        }
      }
      var binds: [Bool] = []
      var slotSpans: [SourceSpan] = []
      for arg in elements {
        if case .wildcard = arg.pattern {
          binds.append(false)
        } else {
          binds.append(true)
        }
        slotSpans.append(arg.pattern.span)
      }
      try checkPositionalDestructuring(
        members: members,
        owner: tupleDestructuringOwner(of: innerType),
        typeName: innerType.description,
        binds: binds,
        slotSpans: slotSpans,
        span: span
      )
      var typedSubPatterns: [TypedPattern] = []
      for (idx, arg) in elements.enumerated() {
        let fieldType = members[idx].type
        let (typedSub, subBindings) = try checkPattern(arg.pattern, subjectType: fieldType)
        typedSubPatterns.append(typedSub)
        bindings.append(contentsOf: subBindings)
      }
      // The name here is display-only (exhaustiveness messages); the match
      // itself is against the subject's declaration identity.
      return (.structPattern(typeName: innerType.description, elements: typedSubPatterns), bindings)

    case .listPattern(let elements, let span):
      // A list pattern destructures a `List[T]` by length; each slot is checked
      // against `T`. Which std type `List` is is a question of DECLARATION
      // identity -- a user type also spelled `List` is not one.
      guard case .list(let elementType) = resolveBuiltinSubscriptKind(baseType: subjectType) else {
        throw SemanticError(.generic(
          "List pattern requires a List subject, got '\(subjectType.description)'"
        ), span: span)
      }
      // The length and element reads are ordinary std method calls, resolved
      // here the way `xs.count()` / `xs[i]` resolve them. MIR only knows how to
      // call a Symbol, so the pattern carries them down.
      guard let countSymbol = try lookupDeclaredMethod(on: subjectType, name: "count"),
            let indexSymbol = try lookupDeclaredMethod(on: subjectType, name: "__index_get") else {
        throw SemanticError(.generic(
          "List pattern requires 'count' and '__index_get' on '\(subjectType.description)'"
        ), span: span)
      }
      var typedElements: [TypedPattern] = []
      for element in elements {
        if case .restPattern = element {
          typedElements.append(.restPattern)
          continue
        }
        let (typedSub, subBindings) = try checkPattern(element, subjectType: elementType)
        typedElements.append(typedSub)
        bindings.append(contentsOf: subBindings)
      }
      return (.listPattern(
        elements: typedElements,
        ops: ListPatternOps(
          listType: subjectType,
          elementType: elementType,
          countSymbol: countSymbol,
          indexSymbol: indexSymbol
        )
      ), bindings)

    case .restPattern:
      // Only ever reached as a slot of an enclosing element list, which
      // expands or forwards it before any field type is consulted. It swallows
      // slots rather than matching one, so there is nothing to check.
      return (.restPattern, [])
    }
  }

  /// Rewrite a whole-list elision into one wildcard per field.
  ///
  /// In a fixed-arity element list the parser only lets `...` stand alone, and
  /// it means "ignore every field" -- named or not. Each field gets a wildcard
  /// matched the way the declaration demands: a positional field is an
  /// unlabeled slot, a named field is its own label. The unlabeled ones go
  /// first, because a pattern argument list may not place a positional
  /// argument after a named one; `reorderPatternArguments` then restores
  /// declaration order.
  ///
  /// Without a rest slot the element list is returned unchanged.
  func expandRestSlots(
    _ args: [PatternArg],
    fieldNames: [String],
    fieldIsNamed: [Bool],
    patternSpan: SourceSpan
  ) -> [PatternArg] {
    var hasRest = false
    for arg in args {
      if case .restPattern = arg.pattern {
        hasRest = true
        break
      }
    }
    guard hasRest else { return args }

    var expanded: [PatternArg] = []
    for (index, _) in fieldNames.enumerated() where !fieldIsNamed[index] {
      expanded.append(PatternArg(label: nil, pattern: .wildcard(span: patternSpan)))
    }
    for (index, name) in fieldNames.enumerated() where fieldIsNamed[index] {
      expanded.append(PatternArg(label: name, pattern: .wildcard(span: patternSpan)))
    }
    return expanded
  }

  /// The matched value behind a positional destructuring: a reference subject
  /// is destructured at its pointee, exactly like the named struct pattern.
  /// A reference is an alias of the referent, so it peels. A weak handle is
  /// NOT: it is a HANDLE, opaque until `upgrade`d, with no fields. Peeling it
  /// here is what let `let (a, b) = <a ?Pair>` destructure the referent behind
  /// the handle.
  func unwrapTupleSubjectType(_ subjectType: Type) -> Type {
    switch subjectType {
    case .reference(let inner),
         .mutableReference(let inner),
         .borrowedReference(let inner),
         .mutableBorrowedReference(let inner):
      return inner
    default:
      return subjectType
    }
  }

  /// The ordered fields of a struct subject, for positional destructuring.
  /// The SUBJECT's own DECLARATION decides which struct this is. A
  /// `GenericStruct` subject's field types come from the template's fields with
  /// the type arguments substituted. `nil` when the subject is not a struct at
  /// all; `[]` when it is a struct whose fields are not registered.
  func tupleDestructuringMembers(of subjectType: Type) throws ->
    [(name: String, type: Type, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)]? {
    switch subjectType {
    case .structure(let defId):
      guard let members = context.getStructMembers(defId) else {
        return []
      }
      return members.map {
        (name: $0.name, type: $0.type, access: $0.access, named: $0.named, defaultValue: $0.defaultValue)
      }

    case .genericStruct(let tplDefId, let typeArgs):
      // Identity: the template's DECLARATION, carried on the type.
      guard let template = currentScope.genericStructTemplate(defId: tplDefId) else {
        return []
      }
      var substitution: [String: Type] = [:]
      for (index, param) in template.typeParameters.enumerated() where index < typeArgs.count {
        substitution[param.name] = typeArgs[index]
      }
      var resolved: [(name: String, type: Type, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)] = []
      resolved.reserveCapacity(template.parameters.count)
      for param in template.parameters {
        let resolvedType = try withNewScope {
          for (paramName, paramType) in substitution {
            try currentScope.defineType(paramName, type: paramType)
          }
          return try resolveTypeNode(param.type)
        }
        resolved.append((name: param.name, type: resolvedType, access: param.access, named: param.named, defaultValue: param.defaultValue))
      }
      return resolved

    default:
      return nil
    }
  }

  /// The declaration that owns the fields a positional destructuring reads,
  /// for the visibility rule. `nil` when the subject is not a nominal struct.
  func tupleDestructuringOwner(of subjectType: Type) -> DefId? {
    switch subjectType {
    case .structure(let defId):
      return defId
    case .genericStruct(let tplDefId, _):
      return currentScope.genericStructTemplate(defId: tplDefId)?.defId
    default:
      return nil
    }
  }

  /// `(a, b, c)` binds fields in DECLARATION ORDER, so it can only reach a
  /// field declared POSITIONAL. Two rules, both already owed to the named
  /// struct pattern:
  ///
  ///   - a NAMED field has to be matched by label, which a positional slot
  ///     cannot do;
  ///   - a field this file may not read may only be ignored, never bound.
  ///
  /// `binds[i]` says whether slot i reads field i -- `_` does not -- and
  /// `slotSpans[i]` is where that slot is written.
  func checkPositionalDestructuring(
    members: [(name: String, type: Type, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)],
    owner: DefId?,
    typeName: String,
    binds: [Bool],
    slotSpans: [SourceSpan],
    span: SourceSpan
  ) throws {
    if let namedField = members.first(where: { $0.named }) {
      throw SemanticError(.generic(
        "Named pattern field '\(namedField.name)' must be matched by label"
      ), span: span)
    }
    guard let owner else { return }
    for (index, member) in members.enumerated() {
      guard index < binds.count, index < slotSpans.count, binds[index] else { continue }
      if !isFieldAccessible(fieldAccess: member.access, defId: owner) {
        let accessLabel = member.access.description
        throw SemanticError(.generic(
          "Cannot access \(accessLabel) field '\(member.name)' of type '\(typeName)' in destructuring pattern"
        ), span: slotSpans[index])
      }
    }
  }

  /// Check whether a typed pattern contains any variable bindings.
  func patternContainsBindings(_ pattern: TypedPattern) -> Bool {
    switch pattern {
    case .variable,
         .weakBinding,
         .traitObjectTypeBinding:
      return true
    case .enumCase(_, _, let elements):
      return elements.contains { patternContainsBindings($0) }
    case .structPattern(_, let elements):
      return elements.contains { patternContainsBindings($0) }
    case .listPattern(let elements, _):
      return elements.contains { patternContainsBindings($0) }
    case .andPattern(let left, let right), .orPattern(let left, let right):
      return patternContainsBindings(left) || patternContainsBindings(right)
    case .notPattern(let inner):
      return patternContainsBindings(inner)
    case .booleanLiteral, .integerLiteral, .floatLiteral, .stringLiteral, .wildcard, .comparisonPattern, .traitObjectType, .restPattern:
      return false
    case .nullLiteral:
      return false
    }
  }

  func extractPatternSymbols(from pattern: TypedPattern) -> [Symbol] {
    var symbols: [Symbol] = []
    var seenDefIds: Set<UInt64> = []
    collectPatternSymbols(pattern, into: &symbols, seenDefIds: &seenDefIds)
    return symbols
  }

  private func collectPatternSymbols(
    _ pattern: TypedPattern,
    into symbols: inout [Symbol],
    seenDefIds: inout Set<UInt64>
  ) {
    switch pattern {
    case .variable(let symbol):
      if seenDefIds.insert(symbol.defId.id).inserted {
        symbols.append(symbol)
      }
    case .weakBinding(let symbol):
      if seenDefIds.insert(symbol.defId.id).inserted {
        symbols.append(symbol)
      }
    case .traitObjectTypeBinding(let symbol, _):
      if seenDefIds.insert(symbol.defId.id).inserted {
        symbols.append(symbol)
      }
    case .enumCase(_, _, let elements):
      for element in elements {
        collectPatternSymbols(element, into: &symbols, seenDefIds: &seenDefIds)
      }
    case .structPattern(_, let elements):
      for element in elements {
        collectPatternSymbols(element, into: &symbols, seenDefIds: &seenDefIds)
      }
    case .listPattern(let elements, _):
      for element in elements {
        collectPatternSymbols(element, into: &symbols, seenDefIds: &seenDefIds)
      }
    case .andPattern(let left, let right), .orPattern(let left, let right):
      collectPatternSymbols(left, into: &symbols, seenDefIds: &seenDefIds)
      collectPatternSymbols(right, into: &symbols, seenDefIds: &seenDefIds)
    case .notPattern(let pattern):
      collectPatternSymbols(pattern, into: &symbols, seenDefIds: &seenDefIds)
    case .booleanLiteral, .integerLiteral, .floatLiteral, .stringLiteral, .wildcard, .comparisonPattern, .traitObjectType, .restPattern:
      break
    case .nullLiteral:
      break
    }
  }

  private func patternSymbolsByName(in pattern: TypedPattern) -> [String: Symbol] {
    var symbolsByName: [String: Symbol] = [:]
    for symbol in extractPatternSymbols(from: pattern) {
      guard let name = context.getName(symbol.defId) else { continue }
      symbolsByName[name] = symbol
    }
    return symbolsByName
  }

  private func canonicalizePatternBindings(
    _ pattern: TypedPattern,
    canonicalSymbolsByName: [String: Symbol]
  ) -> TypedPattern {
    switch pattern {
    case .variable(let symbol):
      guard let name = context.getName(symbol.defId),
            let canonical = canonicalSymbolsByName[name] else {
        return pattern
      }
      return .variable(symbol: canonical)
    case .weakBinding(let symbol):
      guard let name = context.getName(symbol.defId),
            let canonical = canonicalSymbolsByName[name] else {
        return pattern
      }
      return .weakBinding(symbol: canonical)
    case .traitObjectTypeBinding(let symbol, let targetType):
      guard let name = context.getName(symbol.defId),
            let canonical = canonicalSymbolsByName[name] else {
        return pattern
      }
      return .traitObjectTypeBinding(symbol: canonical, targetType: targetType)
    case .enumCase(let caseName, let tagIndex, let elements):
      return .enumCase(
        caseName: caseName,
        tagIndex: tagIndex,
        elements: elements.map { canonicalizePatternBindings($0, canonicalSymbolsByName: canonicalSymbolsByName) }
      )
    case .structPattern(let typeName, let elements):
      return .structPattern(
        typeName: typeName,
        elements: elements.map { canonicalizePatternBindings($0, canonicalSymbolsByName: canonicalSymbolsByName) }
      )
    case .listPattern(let elements, let ops):
      return .listPattern(
        elements: elements.map { canonicalizePatternBindings($0, canonicalSymbolsByName: canonicalSymbolsByName) },
        ops: ops
      )
    case .andPattern(let left, let right):
      return .andPattern(
        left: canonicalizePatternBindings(left, canonicalSymbolsByName: canonicalSymbolsByName),
        right: canonicalizePatternBindings(right, canonicalSymbolsByName: canonicalSymbolsByName)
      )
    case .orPattern(let left, let right):
      return .orPattern(
        left: canonicalizePatternBindings(left, canonicalSymbolsByName: canonicalSymbolsByName),
        right: canonicalizePatternBindings(right, canonicalSymbolsByName: canonicalSymbolsByName)
      )
    case .notPattern(let inner):
      return .notPattern(pattern: canonicalizePatternBindings(inner, canonicalSymbolsByName: canonicalSymbolsByName))
    case .booleanLiteral, .integerLiteral, .floatLiteral, .stringLiteral, .wildcard, .comparisonPattern, .traitObjectType, .restPattern:
      return pattern
    case .nullLiteral:
      return pattern
    }
  }
}

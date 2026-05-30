import Foundation

// MARK: - Pattern Type Checking Extension
// This extension contains methods for pattern matching type checking.

extension TypeChecker {

  /// Check if a field is accessible from the current source file/module.
  /// - Parameters:
  ///   - fieldAccess: The access modifier of the field
  ///   - defId: The DefId of the type that defines the field
  /// - Returns: true if the field is accessible
  private func isFieldAccessible(fieldAccess: AccessModifier, defId: DefId) -> Bool {
    switch fieldAccess {
    case .public:
      return true
    case .private:
      // Private: only accessible from the same file
      let defSourceFile = context.getSourceFile(defId) ?? ""
      return isSameSourceFile(defSourceFile, currentSourceFile)
    case .protected:
      // Protected: accessible from the same logical module only.
      let defModulePath = context.getModulePath(defId) ?? []
      return defModulePath == currentModulePath
    case .protectedPublic:
      guard !currentPackageID.isEmpty else { return false }
      return context.getPackageID(defId) == currentPackageID
    }
  }

  func checkPattern(_ pattern: PatternNode, subjectType: Type) throws -> (
    TypedPattern, [(String, Bool, Type)]
  ) {
    var bindings: [(String, Bool, Type)] = []

    switch pattern {
    case .integerLiteral(let val, _):
      if !subjectType.isIntegerType {
        throw SemanticError.typeMismatch(expected: "integer type", got: subjectType.description)
      }
      return (.integerLiteral(value: val), [])
      
    case .negativeIntegerLiteral(let val, let span):
      // Negative integer literal pattern - verify subject is integer type
      if !subjectType.isIntegerType {
        throw SemanticError.typeMismatch(expected: "integer type", got: subjectType.description)
      }
      switch subjectType {
      case .uint, .uint8, .uint16, .uint32, .uint64:
        throw SemanticError(.generic("Negative integer literal cannot match unsigned type"), span: span)
      default:
        break
      }
      // Store as negative value string
      return (.integerLiteral(value: "-\(val)"), [])

    case .booleanLiteral(let val, _):
      if subjectType != .bool {
        throw SemanticError.typeMismatch(expected: "Bool", got: subjectType.description)
      }
      return (.booleanLiteral(value: val), [])

    case .stringLiteral(let value, _):
      if isStringType(subjectType) {
        return (.stringLiteral(value: value), [])
      }
      throw SemanticError.typeMismatch(expected: "String", got: subjectType.description)

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
      throw SemanticError.typeMismatch(expected: "Rune or UInt8", got: subjectType.description)

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
      // Handle both concrete enum and genericEnum types
      let typeName: String
      let cases: [EnumCase]
      let enumDefId: DefId?
      
      switch subjectType {
      case .`enum`(let defId):
        typeName = context.getName(defId) ?? ""
        cases = context.getEnumCases(defId) ?? []
        enumDefId = defId
        
      case .genericEnum(let templateName, let typeArgs):
        // Look up the enum template and substitute type parameters
        guard let template = currentScope.lookupGenericEnumTemplate(templateName) else {
          throw SemanticError.undefinedType(templateName)
        }
        
        typeName = templateName
        enumDefId = template.defId
        
        // Create substitution map
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = typeArgs[i]
        }
        
        // Resolve case parameter types with substitution
        cases = try template.cases.map { caseDef in
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
        
      default:
        throw SemanticError.typeMismatch(expected: "Enum Type", got: subjectType.description)
      }

      guard let caseIndex = cases.firstIndex(where: { $0.name == caseName }) else {
        throw SemanticError(.generic("Enum case '\(caseName)' not found in type '\(typeName)'"))
      }
      let caseDef = cases[caseIndex]

      let subPatterns = subPatternArgs.map { $0.pattern }
      if caseDef.parameters.count != subPatterns.count {
        throw SemanticError.invalidArgumentCount(
          function: caseName, expected: caseDef.parameters.count, got: subPatterns.count)
      }

      // Validate named argument labels in pattern
      try validateNamedPatternArguments(
        patternArgs: subPatternArgs,
        parameters: caseDef.parameters.map { (name: $0.name, named: $0.named) },
        patternDescription: ".\(caseName)"
      )

      var typedSubPatterns: [TypedPattern] = []
      for (idx, subPat) in subPatterns.enumerated() {
        let fieldAccess = caseDef.parameters[idx].access
        
        // Check field visibility - if not accessible, only wildcard is allowed
        if let defId = enumDefId, !isFieldAccessible(fieldAccess: fieldAccess, defId: defId) {
          if case .wildcard = subPat {
            // Wildcard doesn't access the field value, allowed
          } else {
            let fieldName = caseDef.parameters[idx].name
            let accessLabel = fieldAccess == .private ? "private" : "protected"
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(fieldName)' of type '\(typeName)' in destructuring pattern"
            ), span: span)
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
      
    case .comparisonPattern(let op, let value, let span):
      // Comparison patterns only support integer types
      if !subjectType.isIntegerType {
        throw SemanticError(.generic(
          "Comparison patterns only support integer types, got '\(subjectType)'"
        ), span: span)
      }
      
      // Parse the integer value
      let intValue: Int64
      if value.hasPrefix("-") {
        let positiveValue = String(value.dropFirst())
        guard let parsed = Int64(positiveValue) else {
          throw SemanticError(.generic("Invalid integer literal in comparison pattern: \(value)"), span: span)
        }
        intValue = -parsed
      } else {
        guard let parsed = Int64(value) else {
          throw SemanticError(.generic("Invalid integer literal in comparison pattern: \(value)"), span: span)
        }
        intValue = parsed
      }
      
      return (.comparisonPattern(operator: op, value: intValue), [])
      
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
      let members: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool)]
      let structDefId: DefId?
      
      switch subjectType {
      case .structure(let defId):
        guard let name = context.getName(defId), name == typeName else {
          throw SemanticError(.typeMismatch(
            expected: typeName, got: subjectType.description), span: span)
        }
        members = context.getStructMembers(defId) ?? []
        structDefId = defId
        
      case .genericStruct(let templateName, let typeArgs):
        guard templateName == typeName else {
          throw SemanticError(.typeMismatch(
            expected: typeName, got: subjectType.description), span: span)
        }
        // Look up the generic struct template and substitute type parameters
        guard let template = currentScope.lookupGenericStructTemplate(templateName) else {
          throw SemanticError.undefinedType(templateName)
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
          return (name: param.name, type: resolvedType, mutable: param.mutable, access: fieldAccess, named: param.named)
        }
        structDefId = template.defId
        
      default:
        throw SemanticError(.typeMismatch(
          expected: "Struct Type", got: subjectType.description), span: span)
      }
      
      // Verify sub-pattern count matches field count
      let subPatterns = subPatternArgs.map { $0.pattern }
      if subPatterns.count != members.count {
        throw SemanticError.invalidArgumentCount(
          function: typeName, expected: members.count, got: subPatterns.count)
      }
      
      // Validate named argument labels in struct pattern
      try validateNamedPatternArguments(
        patternArgs: subPatternArgs,
        parameters: members.map { (name: $0.name, named: $0.named) },
        patternDescription: typeName
      )
      
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
            let accessLabel = fieldAccess == .private ? "private" : "protected"
            throw SemanticError(.generic(
              "Cannot access \(accessLabel) field '\(fieldName)' of type '\(typeName)' in destructuring pattern"
            ), span: span)
          }
        }
        
        let fieldType = members[idx].type
        let (typedSub, subBindings) = try checkPattern(subPat, subjectType: fieldType)
        typedSubPatterns.append(typedSub)
        bindings.append(contentsOf: subBindings)
      }
      
      return (.structPattern(typeName: typeName, elements: typedSubPatterns), bindings)
    }
  }

  /// Check whether a typed pattern contains any variable bindings.
  func patternContainsBindings(_ pattern: TypedPattern) -> Bool {
    switch pattern {
    case .variable:
      return true
    case .enumCase(_, _, let elements):
      return elements.contains { patternContainsBindings($0) }
    case .structPattern(_, let elements):
      return elements.contains { patternContainsBindings($0) }
    case .andPattern(let left, let right), .orPattern(let left, let right):
      return patternContainsBindings(left) || patternContainsBindings(right)
    case .notPattern(let inner):
      return patternContainsBindings(inner)
    case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard, .comparisonPattern:
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
    case .enumCase(_, _, let elements):
      for element in elements {
        collectPatternSymbols(element, into: &symbols, seenDefIds: &seenDefIds)
      }
    case .structPattern(_, let elements):
      for element in elements {
        collectPatternSymbols(element, into: &symbols, seenDefIds: &seenDefIds)
      }
    case .andPattern(let left, let right), .orPattern(let left, let right):
      collectPatternSymbols(left, into: &symbols, seenDefIds: &seenDefIds)
      collectPatternSymbols(right, into: &symbols, seenDefIds: &seenDefIds)
    case .notPattern(let pattern):
      collectPatternSymbols(pattern, into: &symbols, seenDefIds: &seenDefIds)
    case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard, .comparisonPattern:
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
    case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard, .comparisonPattern:
      return pattern
    }
  }
}

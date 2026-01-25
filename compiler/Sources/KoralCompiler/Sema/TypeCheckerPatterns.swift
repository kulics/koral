import Foundation

// MARK: - Pattern Type Checking Extension
// This extension contains methods for pattern matching type checking.

extension TypeChecker {

  func checkPattern(_ pattern: PatternNode, subjectType: Type) throws -> (
    TypedPattern, [(String, Bool, Type)]
  ) {
    var bindings: [(String, Bool, Type)] = []

    switch pattern {
    case .integerLiteral(let val, let suffix, _):
      // Determine expected type from suffix or default to Int
      let expectedType: Type
      if let suffix = suffix {
        switch suffix {
        case .i: expectedType = .int
        case .i8: expectedType = .int8
        case .i16: expectedType = .int16
        case .i32: expectedType = .int32
        case .i64: expectedType = .int64
        case .u: expectedType = .uint
        case .u8: expectedType = .uint8
        case .u16: expectedType = .uint16
        case .u32: expectedType = .uint32
        case .u64: expectedType = .uint64
        case .f32, .f64:
          throw SemanticError.typeMismatch(expected: "integer type", got: suffix.rawValue)
        }
      } else {
        expectedType = .int
      }
      if subjectType != expectedType {
        throw SemanticError.typeMismatch(expected: expectedType.description, got: subjectType.description)
      }
      return (.integerLiteral(value: val), [])
      
    case .negativeIntegerLiteral(let val, let suffix, let span):
      // Negative integer literal pattern - verify subject is integer type
      let expectedType: Type
      if let suffix = suffix {
        switch suffix {
        case .i: expectedType = .int
        case .i8: expectedType = .int8
        case .i16: expectedType = .int16
        case .i32: expectedType = .int32
        case .i64: expectedType = .int64
        case .u, .u8, .u16, .u32, .u64:
          throw SemanticError(.generic("Negative integer literal cannot have unsigned suffix"), span: span)
        case .f32, .f64:
          throw SemanticError.typeMismatch(expected: "integer type", got: suffix.rawValue)
        }
      } else {
        expectedType = .int
      }
      if subjectType != expectedType {
        throw SemanticError.typeMismatch(expected: expectedType.description, got: subjectType.description)
      }
      // Store as negative value string
      return (.integerLiteral(value: "-\(val)"), [])

    case .booleanLiteral(let val, _):
      if subjectType != .bool {
        throw SemanticError.typeMismatch(expected: "Bool", got: subjectType.description)
      }
      return (.booleanLiteral(value: val), [])

    case .stringLiteral(let value, let span):
      if isStringType(subjectType) {
        return (.stringLiteral(value: value), [])
      }
      if subjectType == .uint8 {
        guard let byte = singleByteASCII(from: value) else {
          throw SemanticError(
            .generic("String literal pattern must be exactly one ASCII byte when matching UInt8"),
            span: span)
        }
        return (.integerLiteral(value: String(byte)), [])
      }
      throw SemanticError.typeMismatch(expected: "String or UInt8", got: subjectType.description)

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

    case .unionCase(let caseName, let subPatterns, _):
      // Handle both concrete union and genericUnion types
      let typeName: String
      let cases: [UnionCase]
      
      switch subjectType {
      case .union(let decl):
        typeName = decl.name
        cases = decl.cases
        
      case .genericUnion(let templateName, let typeArgs):
        // Look up the union template and substitute type parameters
        guard let template = currentScope.lookupGenericUnionTemplate(templateName) else {
          throw SemanticError.undefinedType(templateName)
        }
        
        typeName = templateName
        
        // Create substitution map
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = typeArgs[i]
        }
        
        // Resolve case parameter types with substitution
        cases = try template.cases.map { caseDef in
          let resolvedParams: [(name: String, type: Type)] = try caseDef.parameters.map { param in
            let resolvedType = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try resolveTypeNode(param.type)
            }
            return (name: param.name, type: resolvedType)
          }
          return UnionCase(name: caseDef.name, parameters: resolvedParams)
        }
        
      default:
        throw SemanticError.typeMismatch(expected: "Union Type", got: subjectType.description)
      }

      guard let caseIndex = cases.firstIndex(where: { $0.name == caseName }) else {
        throw SemanticError(.generic("Union case '\(caseName)' not found in type '\(typeName)'"))
      }
      let caseDef = cases[caseIndex]

      if caseDef.parameters.count != subPatterns.count {
        throw SemanticError.invalidArgumentCount(
          function: caseName, expected: caseDef.parameters.count, got: subPatterns.count)
      }

      var typedSubPatterns: [TypedPattern] = []
      for (idx, subPat) in subPatterns.enumerated() {
        let paramType = caseDef.parameters[idx].type
        let (typedSub, subBindings) = try checkPattern(subPat, subjectType: paramType)
        typedSubPatterns.append(typedSub)
        bindings.append(contentsOf: subBindings)
      }

      return (
        .unionCase(caseName: caseName, tagIndex: caseIndex, elements: typedSubPatterns), bindings
      )
      
    case .comparisonPattern(let op, let value, let suffix, let span):
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
      
      // Verify suffix matches subject type if provided
      if let suffix = suffix {
        let expectedType: Type
        switch suffix {
        case .i: expectedType = .int
        case .i8: expectedType = .int8
        case .i16: expectedType = .int16
        case .i32: expectedType = .int32
        case .i64: expectedType = .int64
        case .u: expectedType = .uint
        case .u8: expectedType = .uint8
        case .u16: expectedType = .uint16
        case .u32: expectedType = .uint32
        case .u64: expectedType = .uint64
        case .f32, .f64:
          throw SemanticError(.generic("Comparison patterns do not support float types"), span: span)
        }
        if subjectType != expectedType {
          throw SemanticError.typeMismatch(expected: expectedType.description, got: subjectType.description)
        }
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
      
      return (.orPattern(left: typedLeft, right: typedRight), leftBindings)
      
    case .notPattern(let innerPattern, let span):
      let (typedPattern, innerBindings) = try checkPattern(innerPattern, subjectType: subjectType)
      
      // not pattern cannot contain variable bindings
      if !innerBindings.isEmpty {
        throw SemanticError(.generic(
          "Not pattern cannot contain variable bindings"
        ), span: span)
      }
      
      return (.notPattern(pattern: typedPattern), [])
    }
  }
}

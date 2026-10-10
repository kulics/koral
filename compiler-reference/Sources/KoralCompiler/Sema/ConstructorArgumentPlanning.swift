import Foundation

struct ConstructorArgumentPlan {
  let orderedCallArgs: [CallArg?]
  let usesDefaults: Bool
}

extension TypeChecker {
  /// Validate call argument order: positional args first, named args after.
  /// Also validates that positional params can't use labels and named params must use labels.
  func validateCallArgumentOrder(_ callArgs: [CallArg], functionName: String, paramNames: [String]? = nil, paramIsNamed: [Bool]? = nil) throws {
    if callArgs.contains(where: { $0.isDefaultFill }) {
      throw SemanticError(.generic("Default-fill '...' is not supported; use named parameter defaults instead"), span: currentSpan)
    }
    var seenNamed = false
    for arg in callArgs {
      if arg.label != nil {
        seenNamed = true
      } else if seenNamed {
        throw SemanticError(.generic("Positional argument cannot appear after named argument in call to '\(functionName)'"), span: arg.span)
      }
    }
    // Validate labels match param named status
    if let names = paramNames, let isNamed = paramIsNamed {
      var positionalIndex = 0
      for arg in callArgs {
        if let label = arg.label {
          // Named arg - check that the param is named
          guard let fieldIndex = names.firstIndex(of: label) else {
            throw SemanticError(.generic("Unknown named argument '\(label)' for '\(functionName)'"), span: arg.span)
          }
          guard isNamed[fieldIndex] else {
            throw SemanticError(.generic("Positional parameter cannot be passed by label '\(label)'"), span: arg.span)
          }
        } else {
          // Positional arg - check that the param is positional
          while positionalIndex < names.count && isNamed[positionalIndex] {
            positionalIndex += 1
          }
          guard positionalIndex < names.count else {
            throw SemanticError(.generic("Too many positional arguments in call to '\(functionName)'"), span: arg.span)
          }
          guard !isNamed[positionalIndex] else {
            throw SemanticError(.generic("Named parameter '\(names[positionalIndex])' must be passed by label"), span: arg.span)
          }
          positionalIndex += 1
        }
      }
    }
  }

  /// Unified call-argument planner.
  ///
  /// Every call form — free function, instance method, static method, generic
  /// method, trait method and constructor/enum-case construction — must plan
  /// its `CallArg`s through this entry point. It matches labels against the
  /// declared parameter labels, reorders arguments into declaration order,
  /// reports label errors and reports missing parameters without a default.
  func planCallArguments(
    _ callArgs: [CallArg],
    paramNames: [String],
    paramIsNamed: [Bool],
    callDescription: String,
    defaultsKeyPrefix: String
  ) throws -> ConstructorArgumentPlan {
    // Reject spread syntax
    if callArgs.contains(where: { $0.isDefaultFill }) {
      throw SemanticError(.generic("Default-fill '...' is not supported; use named parameter defaults instead"), span: currentSpan)
    }

    var orderedCallArgs: [CallArg?] = Array(repeating: nil, count: paramNames.count)
    var positionalIndex = 0
    var seenNamed = false

    for arg in callArgs {
      if let label = arg.label {
        // Named argument
        seenNamed = true
        guard let fieldIndex = paramNames.firstIndex(of: label) else {
          throw SemanticError(.generic("Unknown named argument '\(label)' for '\(callDescription)'"), span: arg.span)
        }
        guard paramIsNamed[fieldIndex] else {
          throw SemanticError(.generic("Parameter '\(label)' is positional and cannot be passed by label"), span: arg.span)
        }
        if orderedCallArgs[fieldIndex] != nil {
          throw SemanticError(.generic("Duplicate argument '\(label)'"), span: arg.span)
        }
        orderedCallArgs[fieldIndex] = arg
      } else {
        // Positional argument
        if seenNamed {
          throw SemanticError(.generic("Positional argument cannot appear after named argument in call to '\(callDescription)'"), span: arg.span)
        }
        // Find next positional parameter
        while positionalIndex < paramNames.count && paramIsNamed[positionalIndex] {
          positionalIndex += 1
        }
        guard positionalIndex < paramNames.count else {
          // Every remaining parameter is named-only, so this argument can only
          // have been meant for one of them.
          if let required = paramNames.indices.firstIndex(where: { paramIsNamed[$0] && orderedCallArgs[$0] == nil }) {
            throw SemanticError(.generic("Named parameter '\(paramNames[required])' must be passed by label"), span: arg.span)
          }
          throw SemanticError(.generic("Too many positional arguments in call to '\(callDescription)'"), span: arg.span)
        }
        orderedCallArgs[positionalIndex] = arg
        positionalIndex += 1
      }
    }

    // Check for missing parameters that don't have defaults
    var usesDefaults = false
    for (index, param) in paramNames.enumerated() {
      if orderedCallArgs[index] == nil {
        let key = "\(defaultsKeyPrefix).\(param)"
        if self.parsedParameterDefaults[key] != nil {
          usesDefaults = true
        } else if paramIsNamed[index] {
          throw SemanticError(.generic("Missing named argument '\(param)' for '\(callDescription)'; provide '\(param):' or declare a default value"), span: callArgs.first?.span ?? currentSpan)
        } else {
          throw SemanticError(.generic("Missing positional argument '\(param)' for '\(callDescription)'"), span: callArgs.first?.span ?? currentSpan)
        }
      }
    }

    return ConstructorArgumentPlan(
      orderedCallArgs: orderedCallArgs,
      usesDefaults: usesDefaults
    )
  }

  /// Plan call arguments and materialize exactly one expression per parameter
  /// slot, in declaration order. Slots left open at the call site are filled
  /// from the declared default value expression.
  func planCallArgumentExpressions(
    _ callArgs: [CallArg],
    paramNames: [String],
    paramIsNamed: [Bool],
    callDescription: String,
    defaultsKeyPrefix: String
  ) throws -> [ExpressionNode] {
    let plan = try planCallArguments(
      callArgs,
      paramNames: paramNames,
      paramIsNamed: paramIsNamed,
      callDescription: callDescription,
      defaultsKeyPrefix: defaultsKeyPrefix
    )

    var expressions: [ExpressionNode] = []
    for (index, param) in paramNames.enumerated() {
      if let callArg = plan.orderedCallArgs[index], let expression = callArg.expression {
        expressions.append(expression)
        continue
      }
      let key = "\(defaultsKeyPrefix).\(param)"
      guard let defaultExpr = self.parsedParameterDefaults[key] else {
        if paramIsNamed[index] {
          throw SemanticError(.generic("Missing named argument '\(param)' for '\(callDescription)'; provide '\(param):' or declare a default value"), span: callArgs.first?.span ?? currentSpan)
        } else {
          throw SemanticError(.generic("Missing positional argument '\(param)' for '\(callDescription)'"), span: callArgs.first?.span ?? currentSpan)
        }
      }
      expressions.append(defaultExpr)
    }
    return expressions
  }

  /// Plan constructor arguments with support for mixed positional/named params and defaults.
  func planConstructorArguments(
    _ callArgs: [CallArg],
    fieldNames: [String],
    fieldIsNamed: [Bool],
    constructorDescription: String,
    parentName: String = ""
  ) throws -> ConstructorArgumentPlan {
    return try planCallArguments(
      callArgs,
      paramNames: fieldNames,
      paramIsNamed: fieldIsNamed,
      callDescription: constructorDescription,
      defaultsKeyPrefix: parentName
    )
  }

  /// Call-site parameter labels for a method, resolved by owner IDENTITY and
  /// method name (method `DefId`s are shared across same-named methods).
  func methodCallParamMeta(
    ownerTypeName: String?,
    methodName: String,
    fallbackDefId: DefId?,
    argumentCount: Int
  ) -> (names: [String], isNamed: [Bool]) {
    if let ownerTypeName, let labels = methodParamLabels[ownerTypeName]?[methodName] {
      return callParamMeta(from: labels, argumentCount: argumentCount)
    }
    if let fallbackDefId {
      return callArgumentParamMeta(defId: fallbackDefId, argumentCount: argumentCount)
    }
    return callParamMeta(from: [], argumentCount: argumentCount)
  }

  /// Owning nominal type name for a receiver/instance type, unwrapping
  /// reference wrappers.
  func ownerTypeName(for type: Type) -> String? {
    var current = type
    for _ in 0..<4 {
      switch current {
      case .structure(let defId), .enum(let defId):
        return context.getName(defId)
      case .genericStruct(let tplDefId, _), .genericEnum(let tplDefId, _):
        return Type.spelling(tplDefId)
      case .reference(let inner), .mutableReference(let inner),
           .borrowedReference(let inner), .mutableBorrowedReference(let inner),
           .weakReference(let inner), .mutableWeakReference(let inner):
        current = inner
      default:
        return nil
      }
    }
    return nil
  }

  /// Call-site parameter labels for a callee, excluding the implicit `self`
  /// slot of a receiver-style method signature.
  ///
  /// Falls back to positional-only placeholders when no label metadata was
  /// registered, so that label errors are still reported instead of labels
  /// being silently dropped.
  func callArgumentParamMeta(
    defId: DefId,
    argumentCount: Int
  ) -> (names: [String], isNamed: [Bool]) {
    return callParamMeta(from: functionNamedParams[defId] ?? [], argumentCount: argumentCount)
  }

  /// Same as `callArgumentParamMeta(defId:argumentCount:)` but built from a
  /// declaration's parameter list directly (used for extension-method
  /// templates that are not registered by `DefId`).
  func callParamMeta(
    from raw: [(name: String, named: Bool)],
    argumentCount: Int
  ) -> (names: [String], isNamed: [Bool]) {
    var meta: [(name: String, named: Bool)] = raw
    if meta.count == argumentCount + 1 && meta.first?.name == "self" {
      meta = Array(meta.dropFirst())
    }
    if meta.count != argumentCount {
      meta = (0..<argumentCount).map { (name: "arg\($0)", named: false) }
    }
    return (meta.map { $0.name }, meta.map { $0.named })
  }

  /// Pattern arguments follow the call rules exactly -- same shape, same
  /// reason: the DECLARATION decides whether a name is written at the use
  /// site, and the use site does not get to disagree.
  ///
  ///   - a labeled argument names a field, which must be declared NAMED, and
  ///     may do so at most once;
  ///   - an unlabeled argument fills the next field NOT declared named, in
  ///     declaration order, and may not appear after a labeled one;
  ///   - every field is matched exactly once -- a pattern has no defaults.
  ///
  /// The result is one argument per field, in DECLARATION ORDER. An error
  /// points at the offending argument, or at the pattern as a whole when the
  /// pattern itself is the fault (a field left unmatched).
  func reorderPatternArguments(
    _ patternArgs: [PatternArg],
    fieldNames: [String],
    fieldIsNamed: [Bool],
    patternDescription: String,
    patternSpan: SourceSpan
  ) throws -> [PatternArg] {
    // No registered fields means the subject is not the constructor this
    // pattern names. That is a type error, reported by the type check --
    // saying anything about the arguments here would name the wrong fault.
    if fieldNames.isEmpty {
      return patternArgs
    }

    var orderedArgs: [PatternArg?] = Array(repeating: nil, count: fieldNames.count)
    var positionalIndex = 0
    var seenNamed = false

    for arg in patternArgs {
      let argSpan = arg.pattern.span
      if let label = arg.label {
        // Named pattern
        seenNamed = true
        guard let fieldIndex = fieldNames.firstIndex(of: label) else {
          throw SemanticError(.generic("Unknown pattern label '\(label)' for '\(patternDescription)'"), span: argSpan)
        }
        guard fieldIsNamed[fieldIndex] else {
          throw SemanticError(.generic("Field '\(label)' is positional and cannot be matched by label"), span: argSpan)
        }
        if orderedArgs[fieldIndex] != nil {
          throw SemanticError(.generic("Duplicate pattern label '\(label)'"), span: argSpan)
        }
        orderedArgs[fieldIndex] = arg
      } else {
        // Positional pattern
        if seenNamed {
          throw SemanticError(.generic("Positional pattern cannot appear after named pattern in '\(patternDescription)'"), span: argSpan)
        }
        while positionalIndex < fieldNames.count && fieldIsNamed[positionalIndex] {
          positionalIndex += 1
        }
        guard positionalIndex < fieldNames.count else {
          if let required = fieldNames.indices.firstIndex(where: { fieldIsNamed[$0] && orderedArgs[$0] == nil }) {
            throw SemanticError(.generic("Named pattern field '\(fieldNames[required])' must be matched by label"), span: patternSpan)
          }
          throw SemanticError(.generic("Too many positional pattern arguments for '\(patternDescription)'"), span: argSpan)
        }
        orderedArgs[positionalIndex] = arg
        positionalIndex += 1
      }
    }

    // Patterns don't support defaults - all fields must be provided
    for (index, name) in fieldNames.enumerated() {
      if orderedArgs[index] == nil {
        throw SemanticError(.generic("Missing pattern field '\(name)' in '\(patternDescription)'"), span: patternSpan)
      }
    }

    return orderedArgs.compactMap { $0 }
  }

  func defaultFactoryTypeName(for type: Type) -> String {
    switch type {
    case .structure(let defId), .enum(let defId):
      return context.getName(defId) ?? type.description
    case .genericStruct(let tplDefId, _), .genericEnum(let tplDefId, _):
      return Type.spelling(tplDefId)
    default:
      return type.description
    }
  }

  func buildDefaultValueExpression(for type: Type) throws -> TypedExpressionNode {
    switch type {
    case .genericStruct(let tplDefId, let args):
      guard let template = currentScope.genericStructTemplate(defId: tplDefId) else {
        throw SemanticError.undefinedType(Type.spelling(tplDefId))
      }
      return try inferGenericStructStaticMethodCall(
        template: template,
        typeName: Type.spelling(tplDefId),
        resolvedTypeArgs: args,
        methodName: "default",
        callArgs: []
      )
    case .genericEnum(let tplDefId, let args):
      guard let template = currentScope.genericEnumTemplate(defId: tplDefId) else {
        throw SemanticError.undefinedType(Type.spelling(tplDefId))
      }
      return try inferGenericEnumStaticMethodCall(
        template: template,
        typeName: Type.spelling(tplDefId),
        resolvedTypeArgs: args,
        methodName: "default",
        callArgs: []
      )
    default:
      return try inferConcreteTypeStaticMethodCall(
        type: type,
        typeName: defaultFactoryTypeName(for: type),
        resolvedTypeArgs: [],
        methodName: "default",
        callArgs: []
      )
    }
  }

  func enumCaseFieldNames(enumType: Type, caseName: String) throws -> [String]? {
    switch enumType {
    case .enum(let defId):
      guard let enumCase = context.getEnumCases(defId)?.first(where: { $0.name == caseName }) else {
        return nil
      }
      return enumCase.parameters.map { $0.name }
    case .genericEnum(let tplDefId, _):
      guard let template = currentScope.genericEnumTemplate(defId: tplDefId),
            let enumCase = template.cases.first(where: { $0.name == caseName }) else {
        return nil
      }
      return enumCase.parameters.map { $0.name }
    default:
      return nil
    }
  }

  func enumCaseFieldIsNamed(enumType: Type, caseName: String) throws -> [Bool]? {
    switch enumType {
    case .enum(let defId):
      guard let enumCase = context.getEnumCases(defId)?.first(where: { $0.name == caseName }) else {
        return nil
      }
      return enumCase.parameters.map { $0.named }
    case .genericEnum(let tplDefId, _):
      guard let template = currentScope.genericEnumTemplate(defId: tplDefId),
            let enumCase = template.cases.first(where: { $0.name == caseName }) else {
        return nil
      }
      return enumCase.parameters.map { $0.named }
    default:
      return nil
    }
  }

  func typeCheckConstructorArguments(
    plan: ConstructorArgumentPlan,
    members: [(name: String, type: Type, named: Bool)],
    constructorDescription: String,
    parentName: String = ""
  ) throws -> [TypedExpressionNode] {
    var typedArguments: [TypedExpressionNode] = []

    for (index, member) in members.enumerated() {
      if let callArg = plan.orderedCallArgs[index], let expression = callArg.expression {
        var typedArg = try inferTypedExpression(expression, expectedType: member.type)
        typedArg = try coerceLiteral(typedArg, to: member.type)
        // An argument that already failed disagrees with nothing.
        if typedArg.type != .error && typedArg.type != member.type {
          throw SemanticError.typeMismatch(
            expected: member.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
        continue
      }

      // Try to use parsed default value
      let key = "\(parentName).\(member.name)"

      if let defaultExpr = self.parsedParameterDefaults[key] {
        var typedArg = try inferTypedExpression(defaultExpr, expectedType: member.type)
        typedArg = try coerceLiteral(typedArg, to: member.type)
        if typedArg.type != .error && typedArg.type != member.type {
          throw SemanticError.typeMismatch(
            expected: member.type.description,
            got: typedArg.type.description
          )
        }
        typedArguments.append(typedArg)
        continue
      }

      // No default available
      if member.named {
        throw SemanticError(.generic("Missing named argument '\(member.name)' for '\(constructorDescription)'; provide '\(member.name):' or declare a default value"), span: plan.orderedCallArgs.compactMap { $0 }.first?.span ?? currentSpan)
      } else {
        throw SemanticError(.generic("Missing positional argument '\(member.name)' for '\(constructorDescription)'"), span: plan.orderedCallArgs.compactMap { $0 }.first?.span ?? currentSpan)
      }
    }

    return typedArguments
  }
}

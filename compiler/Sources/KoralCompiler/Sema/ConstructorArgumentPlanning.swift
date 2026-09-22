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
        throw SemanticError(.generic("Positional argument cannot appear after named argument in call to '\(functionName)'"), span: currentSpan)
      }
    }
    // Validate labels match param named status
    if let names = paramNames, let isNamed = paramIsNamed {
      var positionalIndex = 0
      for arg in callArgs {
        if let label = arg.label {
          // Named arg - check that the param is named
          guard let fieldIndex = names.firstIndex(of: label) else {
            throw SemanticError(.generic("Unknown named argument '\(label)' for '\(functionName)'"), span: currentSpan)
          }
          guard isNamed[fieldIndex] else {
            throw SemanticError(.generic("Positional parameter cannot be passed by label '\(label)'"), span: currentSpan)
          }
        } else {
          // Positional arg - check that the param is positional
          while positionalIndex < names.count && isNamed[positionalIndex] {
            positionalIndex += 1
          }
          guard positionalIndex < names.count else {
            throw SemanticError(.generic("Too many positional arguments in call to '\(functionName)'"), span: currentSpan)
          }
          guard !isNamed[positionalIndex] else {
            throw SemanticError(.generic("Named parameter '\(names[positionalIndex])' must be passed by label"), span: currentSpan)
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
          throw SemanticError(.generic("Unknown named argument '\(label)' for '\(callDescription)'"), span: currentSpan)
        }
        guard paramIsNamed[fieldIndex] else {
          throw SemanticError(.generic("Parameter '\(label)' is positional and cannot be passed by label"), span: currentSpan)
        }
        if orderedCallArgs[fieldIndex] != nil {
          throw SemanticError(.generic("Duplicate argument '\(label)'"), span: currentSpan)
        }
        orderedCallArgs[fieldIndex] = arg
      } else {
        // Positional argument
        if seenNamed {
          throw SemanticError(.generic("Positional argument cannot appear after named argument in call to '\(callDescription)'"), span: currentSpan)
        }
        // Find next positional parameter
        while positionalIndex < paramNames.count && paramIsNamed[positionalIndex] {
          positionalIndex += 1
        }
        guard positionalIndex < paramNames.count else {
          // Every remaining parameter is named-only, so this argument can only
          // have been meant for one of them.
          if let required = paramNames.indices.firstIndex(where: { paramIsNamed[$0] && orderedCallArgs[$0] == nil }) {
            throw SemanticError(.generic("Named parameter '\(paramNames[required])' must be passed by label"), span: currentSpan)
          }
          throw SemanticError(.generic("Too many positional arguments in call to '\(callDescription)'"), span: currentSpan)
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
          throw SemanticError(.generic("Missing named argument '\(param)' for '\(callDescription)'; provide '\(param):' or declare a default value"), span: currentSpan)
        } else {
          throw SemanticError(.generic("Missing positional argument '\(param)' for '\(callDescription)'"), span: currentSpan)
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
          throw SemanticError(.generic("Missing named argument '\(param)' for '\(callDescription)'; provide '\(param):' or declare a default value"), span: currentSpan)
        } else {
          throw SemanticError(.generic("Missing positional argument '\(param)' for '\(callDescription)'"), span: currentSpan)
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

  /// Call-site parameter labels for a method, resolved by owner type name and
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
      case .genericStruct(let name, _, _), .genericEnum(let name, _, _):
        return name
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

  func reorderPatternArguments(
    _ patternArgs: [PatternArg],
    fieldNames: [String],
    fieldIsNamed: [Bool],
    patternDescription: String
  ) throws -> [PatternArg] {
    var orderedArgs: [PatternArg?] = Array(repeating: nil, count: fieldNames.count)
    var positionalIndex = 0
    var seenNamed = false

    for arg in patternArgs {
      if let label = arg.label {
        // Named pattern
        seenNamed = true
        guard let fieldIndex = fieldNames.firstIndex(of: label) else {
          throw SemanticError(.generic("Unknown pattern label '\(label)' for '\(patternDescription)'"), span: currentSpan)
        }
        guard fieldIsNamed[fieldIndex] else {
          throw SemanticError(.generic("Field '\(label)' is positional and cannot be matched by label"), span: currentSpan)
        }
        if orderedArgs[fieldIndex] != nil {
          throw SemanticError(.generic("Duplicate pattern label '\(label)'"), span: currentSpan)
        }
        orderedArgs[fieldIndex] = arg
      } else {
        // Positional pattern
        if seenNamed {
          throw SemanticError(.generic("Positional pattern cannot appear after named pattern in '\(patternDescription)'"), span: currentSpan)
        }
        while positionalIndex < fieldNames.count && fieldIsNamed[positionalIndex] {
          positionalIndex += 1
        }
        guard positionalIndex < fieldNames.count else {
          if let required = fieldNames.indices.firstIndex(where: { fieldIsNamed[$0] && orderedArgs[$0] == nil }) {
            throw SemanticError(.generic("Named pattern field '\(fieldNames[required])' must be matched by label"), span: currentSpan)
          }
          throw SemanticError(.generic("Too many positional pattern arguments for '\(patternDescription)'"), span: currentSpan)
        }
        orderedArgs[positionalIndex] = arg
        positionalIndex += 1
      }
    }

    // Patterns don't support defaults - all fields must be provided
    for (index, name) in fieldNames.enumerated() {
      if orderedArgs[index] == nil {
        throw SemanticError(.generic("Missing pattern field '\(name)' in '\(patternDescription)'"), span: currentSpan)
      }
    }

    return orderedArgs.compactMap { $0 }
  }

  func defaultFactoryTypeName(for type: Type) -> String {
    switch type {
    case .structure(let defId), .enum(let defId):
      return context.getName(defId) ?? type.description
    case .genericStruct(let templateName, _, _), .genericEnum(let templateName, _, _):
      return templateName
    default:
      return type.description
    }
  }

  func buildDefaultValueExpression(for type: Type) throws -> TypedExpressionNode {
    switch type {
    case .genericStruct(let templateName, _, let args):
      guard let template = currentScope.lookupGenericStructTemplate(templateName) else {
        throw SemanticError.undefinedType(templateName)
      }
      return try inferGenericStructStaticMethodCall(
        template: template,
        typeName: templateName,
        resolvedTypeArgs: args,
        methodName: "default",
        callArgs: []
      )
    case .genericEnum(let templateName, _, let args):
      guard let template = currentScope.lookupGenericEnumTemplate(templateName) else {
        throw SemanticError.undefinedType(templateName)
      }
      return try inferGenericEnumStaticMethodCall(
        template: template,
        typeName: templateName,
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
    case .genericEnum(let templateName, _, _):
      guard let template = currentScope.lookupGenericEnumTemplate(templateName),
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
    case .genericEnum(let templateName, _, _):
      guard let template = currentScope.lookupGenericEnumTemplate(templateName),
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
        if typedArg.type != member.type {
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
        if typedArg.type != member.type {
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
        throw SemanticError(.generic("Missing named argument '\(member.name)' for '\(constructorDescription)'; provide '\(member.name):' or declare a default value"), span: currentSpan)
      } else {
        throw SemanticError(.generic("Missing positional argument '\(member.name)' for '\(constructorDescription)'"), span: currentSpan)
      }
    }

    return typedArguments
  }
}

import Foundation

struct ConstructorArgumentPlan {
  let orderedCallArgs: [CallArg?]
  let usesDefaultFill: Bool
  let usesLabels: Bool
}

extension TypeChecker {
  func rejectNonConstructorCallArguments(_ callArgs: [CallArg]) throws {
    if callArgs.contains(where: { $0.isDefaultFill }) {
      throw SemanticError(.generic("Default-fill '...' is only valid in constructor calls"), span: currentSpan)
    }
    if callArgs.contains(where: { $0.label != nil }) {
      throw SemanticError(.generic("Named labels are only allowed on struct and enum constructors; use positional arguments"), span: currentSpan)
    }
  }

  func planConstructorArguments(
    _ callArgs: [CallArg],
    fieldNames: [String],
    constructorDescription: String
  ) throws -> ConstructorArgumentPlan {
    let defaultFillIndices = callArgs.enumerated().compactMap { index, arg in
      arg.isDefaultFill ? index : nil
    }

    if defaultFillIndices.count > 1 {
      throw SemanticError(.generic("Default-fill '...' may appear at most once in constructor call '\(constructorDescription)'"), span: currentSpan)
    }

    let usesDefaultFill = !defaultFillIndices.isEmpty
    if let defaultFillIndex = defaultFillIndices.first, defaultFillIndex != callArgs.count - 1 {
      throw SemanticError(.generic("Default-fill '...' must be the last constructor argument"), span: currentSpan)
    }

    let valueArgs = callArgs.filter { !$0.isDefaultFill }
    let hasLabels = valueArgs.contains { $0.label != nil }
    let hasPositional = valueArgs.contains { $0.label == nil }

    if hasLabels && hasPositional {
      throw SemanticError(.generic("Constructor call cannot mix positional and labeled arguments"), span: currentSpan)
    }

    if !hasLabels {
      if usesDefaultFill {
        if !valueArgs.isEmpty {
          throw SemanticError(.generic("Default-fill '...' requires labeled constructor arguments or no preceding arguments"), span: currentSpan)
        }
        return ConstructorArgumentPlan(
          orderedCallArgs: Array(repeating: nil, count: fieldNames.count),
          usesDefaultFill: true,
          usesLabels: true
        )
      }

      if valueArgs.count != fieldNames.count {
        throw SemanticError.invalidArgumentCount(
          function: constructorDescription,
          expected: fieldNames.count,
          got: valueArgs.count
        )
      }

      return ConstructorArgumentPlan(
        orderedCallArgs: valueArgs.map(Optional.some),
        usesDefaultFill: false,
        usesLabels: false
      )
    }

    var orderedCallArgs: [CallArg?] = Array(repeating: nil, count: fieldNames.count)
    var seenLabels: Set<String> = []

    for arg in valueArgs {
      guard let label = arg.label else { continue }
      guard let fieldIndex = fieldNames.firstIndex(of: label) else {
        throw SemanticError(.generic("Unknown constructor label '\(label)' for type '\(constructorDescription)'"), span: currentSpan)
      }
      if seenLabels.contains(label) {
        throw SemanticError(.generic("Duplicate constructor label '\(label)'"), span: currentSpan)
      }
      seenLabels.insert(label)
      orderedCallArgs[fieldIndex] = arg
    }

    let missingIndices = orderedCallArgs.indices.filter { orderedCallArgs[$0] == nil }
    if missingIndices.isEmpty {
      if usesDefaultFill {
        throw SemanticError(.generic("Trailing '...' is redundant because all constructor fields are already provided"), span: currentSpan)
      }
    } else if !usesDefaultFill {
      let missingField = fieldNames[missingIndices[0]]
      throw SemanticError(.generic("Missing constructor field '\(missingField)'; provide '\(missingField):' or use '...'"), span: currentSpan)
    }

    return ConstructorArgumentPlan(
      orderedCallArgs: orderedCallArgs,
      usesDefaultFill: usesDefaultFill,
      usesLabels: true
    )
  }

  func reorderPatternArguments(
    _ patternArgs: [PatternArg],
    fieldNames: [String],
    patternDescription: String
  ) throws -> [PatternArg] {
    let hasLabels = patternArgs.contains { $0.label != nil }
    let hasPositional = patternArgs.contains { $0.label == nil }

    if hasLabels && hasPositional {
      throw SemanticError(.generic("Pattern '\(patternDescription)' cannot mix positional and labeled arguments"), span: currentSpan)
    }

    if !hasLabels {
      if patternArgs.count != fieldNames.count {
        throw SemanticError.invalidArgumentCount(
          function: patternDescription,
          expected: fieldNames.count,
          got: patternArgs.count
        )
      }
      return patternArgs
    }

    var orderedArgs: [PatternArg?] = Array(repeating: nil, count: fieldNames.count)
    var seenLabels: Set<String> = []
    for arg in patternArgs {
      guard let label = arg.label else { continue }
      guard let fieldIndex = fieldNames.firstIndex(of: label) else {
        throw SemanticError(.generic("Unknown constructor label '\(label)' for type '\(patternDescription)'"), span: currentSpan)
      }
      if seenLabels.contains(label) {
        throw SemanticError(.generic("Duplicate constructor label '\(label)'"), span: currentSpan)
      }
      seenLabels.insert(label)
      orderedArgs[fieldIndex] = arg
    }

    let missingIndices = orderedArgs.indices.filter { orderedArgs[$0] == nil }
    if !missingIndices.isEmpty {
      let missingField = fieldNames[missingIndices[0]]
      throw SemanticError(.generic("Missing constructor field '\(missingField)' in pattern '\(patternDescription)'"), span: currentSpan)
    }

    return orderedArgs.compactMap { $0 }
  }

  func defaultFactoryTypeName(for type: Type) -> String {
    switch type {
    case .structure(let defId), .enum(let defId):
      return context.getName(defId) ?? type.description
    case .genericStruct(let templateName, _), .genericEnum(let templateName, _):
      return templateName
    default:
      return type.description
    }
  }

  func buildDefaultValueExpression(for type: Type) throws -> TypedExpressionNode {
    switch type {
    case .genericStruct(let templateName, let args):
      guard let template = currentScope.lookupGenericStructTemplate(templateName) else {
        throw SemanticError.undefinedType(templateName)
      }
      return try inferGenericStructStaticMethodCall(
        template: template,
        typeName: templateName,
        resolvedTypeArgs: args,
        methodName: "default",
        arguments: []
      )
    case .genericEnum(let templateName, let args):
      guard let template = currentScope.lookupGenericEnumTemplate(templateName) else {
        throw SemanticError.undefinedType(templateName)
      }
      return try inferGenericEnumStaticMethodCall(
        template: template,
        typeName: templateName,
        resolvedTypeArgs: args,
        methodName: "default",
        arguments: []
      )
    default:
      return try inferConcreteTypeStaticMethodCall(
        type: type,
        typeName: defaultFactoryTypeName(for: type),
        resolvedTypeArgs: [],
        methodName: "default",
        arguments: []
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
    case .genericEnum(let templateName, _):
      guard let template = currentScope.lookupGenericEnumTemplate(templateName),
            let enumCase = template.cases.first(where: { $0.name == caseName }) else {
        return nil
      }
      return enumCase.parameters.map { $0.name }
    default:
      return nil
    }
  }

  func typeCheckConstructorArguments(
    plan: ConstructorArgumentPlan,
    members: [(name: String, type: Type)],
    constructorDescription: String
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

      guard plan.usesDefaultFill else {
        throw SemanticError(.generic("Missing constructor field '\(member.name)'; provide '\(member.name):' or use '...'"), span: currentSpan)
      }

      do {
        let defaultExpr = try buildDefaultValueExpression(for: member.type)
        if defaultExpr.type != member.type {
          throw SemanticError.typeMismatch(
            expected: member.type.description,
            got: defaultExpr.type.description
          )
        }
        typedArguments.append(defaultExpr)
      } catch is SemanticError {
        throw SemanticError(.generic("Field '\(member.name)' omitted by '...', but type '\(member.type.description)' does not implement Default"), span: currentSpan)
      }
    }

    return typedArguments
  }
}
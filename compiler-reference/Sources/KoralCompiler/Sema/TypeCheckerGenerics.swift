import Foundation

// MARK: - Generics and Type Parameter Inference Extension
// This extension contains methods for handling generic trait bounds and type inference.

extension TypeChecker {

  func recordGenericTraitBounds(_ typeParameters: [TypeParameterDecl]) throws {
    for param in typeParameters {
      var bounds: [Bound] = []
      for bound in param.constraints {
        // `mutable` is a shape requirement, not a trait, so it has no trait
        // declaration to validate. Real trait bounds are resolved to their
        // declaration identity here -- the one boundary where a bound's
        // spelling becomes a declaration -- and every later comparison is on
        // that identity.
        if case .mutable = bound {
          bounds.append(bound)
          continue
        }
        if case .foreign = bound {
          bounds.append(bound)
          continue
        }
        try validateTraitName(bound.baseName)
        bounds.append(resolveBound(bound))
      }
      genericTraitBounds[param.name] = bounds
    }
  }

  func unifyWithTraitInference(
    template: GenericFunctionTemplate,
    arguments: [TypedExpressionNode],
    inferred: inout [String: Type]
  ) throws {
    let typeParams = template.typeParameters.map { $0.name }
    
    // First, do basic unification from argument types
    for (typedArg, param) in zip(arguments, template.parameters) {
      if case .identifier(let name, _) = param.type,
         typeParams.contains(name),
         let existing = inferred[name],
         typedArg.type != existing {
        switch typedArg {
        case .integerLiteral:
          if isIntegerType(existing) { continue }
        case .floatLiteral:
          if isFloatType(existing) { continue }
        case .typeConstruction(_, _, _, let srcType):
          // Rune literal (typeConstruction with Rune type) can coerce to Rune or UInt8
          if isRuneType(srcType) && (isRuneType(existing) || existing == .uint8) { continue }
        default:
          break
        }
      }
      try unify(node: param.type, type: typedArg.type, inferred: &inferred, typeParams: typeParams)
    }
    
    // Now try to infer remaining type parameters from trait bounds
    // We need to iterate multiple times because some inferences depend on others
    var madeProgress = true
    var iterations = 0
    let maxIterations = template.typeParameters.count * 2
    
    while madeProgress && iterations < maxIterations {
      madeProgress = false
      iterations += 1
      
      for typeParam in template.typeParameters {
        for constraint in typeParam.constraints {
          switch constraint {
          case .trait(_, let traitName, let traitArgs):
            // A bound `[A...]Trait` on a parameter whose type is already known
            // gives us the trait arguments of that conformance, and therefore
            // `A...`.
            //
            // Nothing here names a particular trait. The arguments are read off
            // the conformance itself, by unifying the trait's required method
            // signatures against the concrete type's. Chains resolve because
            // this loop repeats: `[T, R]Iterable` yields `R` first, and `R`'s
            // own `[T]Iterator` bound then yields `T` on the next pass.
            guard !traitArgs.isEmpty,
                  let concreteSelfType = inferred[typeParam.name],
                  let concreteTraitArgs = try? inferTraitTypeArgumentsFromConformance(
                    selfType: concreteSelfType, traitName: traitName),
                  concreteTraitArgs.count == traitArgs.count else {
              continue
            }

            let unresolvedTraitArgs: [Type] = try withNewScope {
              for genericParam in template.typeParameters {
                currentScope.defineGenericParameter(
                  genericParam.name, type: .genericParameter(name: genericParam.name))
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
  }

  private func unify(
    node: TypeNode, type: Type, inferred: inout [String: Type], typeParams: [String]
  ) throws {
    // print("Unify node: \(node) with type: \(type) (canonical: \(type.canonical))")
    switch node {
    case .identifier(let name, _):
      if typeParams.contains(name) {
        if let existing = inferred[name] {
          if existing != type {
            throw SemanticError.typeMismatch(expected: existing.description, got: type.description)
          }
        } else {
          inferred[name] = type
        }
      }
    case .inferredSelf:
      break
    case .reference(let inner, mutable: let mutable, span: _):
      if let actual = Type.reference(inner: .void).compatibleIndirectionInners(with: type)?.actualInner,
         (!mutable || type.indirectionCompatibilityInfo?.mutable == true),
         type.indirectionCompatibilityInfo?.family == .managedReference {
        try unify(node: inner, type: actual, inferred: &inferred, typeParams: typeParams)
      } else {
        try unify(node: inner, type: type, inferred: &inferred, typeParams: typeParams)
      }
    case .pointer(let inner, mutable: let mutable, span: _):
      if mutable, case .mutablePointer(let elementType) = type {
        try unify(node: inner, type: elementType, inferred: &inferred, typeParams: typeParams)
      } else if !mutable {
        switch type {
        case .pointer(let elementType), .mutablePointer(let elementType):
          try unify(node: inner, type: elementType, inferred: &inferred, typeParams: typeParams)
        default:
          break
        }
      }
    case .generic(let base, let args, _):
      // `base` is a SOURCE SPELLING: resolve it to its declaration once here,
      // then the two sides compare as identities.
      if case .genericStruct(let tplDefId, let typeArgs) = type {
        if currentScope.lookupGenericStructTemplate(base)?.defId == tplDefId, typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      } else if case .genericEnum(let tplDefId, let typeArgs) = type {
        if currentScope.lookupGenericEnumTemplate(base)?.defId == tplDefId, typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      }
    case .functionType(let paramTypes, let returnType, _):
      // Match against function type
      if case .function(let params, let returns) = type {
        if params.count == paramTypes.count {
          for (paramNode, param) in zip(paramTypes, params) {
            try unify(node: paramNode, type: param.type, inferred: &inferred, typeParams: typeParams)
          }
          try unify(node: returnType, type: returns, inferred: &inferred, typeParams: typeParams)
        }
      }
    case .weakReference(let inner, let mutable, _):
      if mutable, case .mutableWeakReference(let innerType) = type {
        try unify(node: inner, type: innerType, inferred: &inferred, typeParams: typeParams)
      } else if !mutable {
        switch type {
        case .weakReference(let innerType), .mutableWeakReference(let innerType):
          try unify(node: inner, type: innerType, inferred: &inferred, typeParams: typeParams)
        default:
          break
        }
      }
    }
  }

  /// Infer type arguments for a generic struct constructor call
  /// e.g., Stream(iter) -> [T, R]Stream(iter) where T and R are inferred from iter's type
  func inferGenericStructConstruction(
    template: GenericStructTemplate,
    name: String,
    callArgs: [CallArg],
    span: SourceSpan = .unknown
  ) throws -> TypedExpressionNode {
    try ensureStructConstructionAccess(
      typeName: name,
      defId: template.defId,
      members: template.parameters.map { param in
        (name: param.name, type: .void, mutable: param.mutable, access: param.access, named: param.named)
      },
      span: span
    )

    let plan = try planConstructorArguments(
      callArgs,
      fieldNames: template.parameters.map { $0.name },
      fieldIsNamed: template.parameters.map { $0.named },
      constructorDescription: name,
      parentName: name
    )
    
    var typedArguments: [TypedExpressionNode] = []
    for callArg in plan.orderedCallArgs {
      guard let expression = callArg?.expression else {
        continue
      }
      let typedArg = try inferTypedExpression(expression)
      typedArguments.append(typedArg)
    }
    
    // Infer type arguments from constructor arguments
    var inferred: [String: Type] = [:]
    let typeParamNames = template.typeParameters.map { $0.name }
    var explicitArgIndex = 0
    for (paramIndex, param) in template.parameters.enumerated() {
      guard let callArg = plan.orderedCallArgs[paramIndex], callArg.expression != nil else {
        continue
      }
      let typedArg = typedArguments[explicitArgIndex]
      explicitArgIndex += 1
      try unify(node: param.type, type: typedArg.type, inferred: &inferred, typeParams: typeParamNames)
    }
    
    // Try to infer remaining type parameters from trait bounds (similar to unifyWithTraitInference)
    var madeProgress = true
    var iterations = 0
    let maxIterations = template.typeParameters.count * 2
    
    while madeProgress && iterations < maxIterations {
      madeProgress = false
      iterations += 1
      
      for typeParam in template.typeParameters {
        for constraint in typeParam.constraints {
          switch constraint {
          case .trait(_, let traitName, let traitArgs):
            // A bound `[A...]Trait` on a parameter whose type is already known
            // gives us the trait arguments of that conformance, and therefore
            // `A...`.
            //
            // Nothing here names a particular trait. The arguments are read off
            // the conformance itself, by unifying the trait's required method
            // signatures against the concrete type's. Chains resolve because
            // this loop repeats: `[T, R]Iterable` yields `R` first, and `R`'s
            // own `[T]Iterator` bound then yields `T` on the next pass.
            guard !traitArgs.isEmpty,
                  let concreteSelfType = inferred[typeParam.name],
                  let concreteTraitArgs = try? inferTraitTypeArgumentsFromConformance(
                    selfType: concreteSelfType, traitName: traitName),
                  concreteTraitArgs.count == traitArgs.count else {
              continue
            }

            let unresolvedTraitArgs: [Type] = try withNewScope {
              for genericParam in template.typeParameters {
                currentScope.defineGenericParameter(
                  genericParam.name, type: .genericParameter(name: genericParam.name))
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

    // Build resolved type arguments
    let resolvedArgs = try template.typeParameters.map { param -> Type in
      guard let type = inferred[param.name] else {
        if false {
          throw SemanticError(.generic(
            "Cannot infer type parameter '\(param.name)' from default-filled constructor fields; specify type arguments or an expected type"
          ), span: currentSpan)
        }
        throw SemanticError.typeMismatch(
          expected: "inferred type for \(param.name)", got: "unknown")
      }
      return type
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
    
    // Create type substitution map and resolve member types
    var substitution: [String: Type] = [:]
    for (i, param) in template.typeParameters.enumerated() {
      substitution[param.name] = resolvedArgs[i]
    }
    
    let memberTypes = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      return try template.parameters.map { param -> (name: String, type: Type, mutable: Bool) in
        let fieldType = try resolveTypeNode(param.type)
        return (name: param.name, type: fieldType, mutable: param.mutable)
      }
    }
    
    let finalTypedArguments = try typeCheckConstructorArguments(
      plan: plan,
      members: memberTypes.map { (name: $0.name, type: $0.type, named: false) },
      constructorDescription: name
    )
    
    let genericType = genericStructType(template: name, args: resolvedArgs)
    
    return .typeConstruction(
      identifier: makeLocalSymbol(name: name, type: genericType, kind: .type),
      typeArgs: resolvedArgs,
      arguments: finalTypedArguments,
      type: genericType
    )
  }
}

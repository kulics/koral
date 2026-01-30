import Foundation

// MARK: - Generics and Type Parameter Inference Extension
// This extension contains methods for handling generic trait bounds and type inference.

extension TypeChecker {

  func recordGenericTraitBounds(_ typeParameters: [TypeParameterDecl]) throws {
    for param in typeParameters {
      var bounds: [TraitConstraint] = []
      for c in param.constraints {
        let constraint = try SemaUtils.resolveTraitConstraint(from: c)
        let traitName = constraint.baseName
        try validateTraitName(traitName)
        bounds.append(constraint)
      }
      genericTraitBounds[param.name] = bounds
    }
  }

  /// Infers type parameters from trait bounds.
  /// For example, if we have `C [T, R]Iterable` and `C = [Int]List`,
  /// this function will look up the `iterator()` method on `[Int]List`
  /// and infer `T = Int` and `R = [Int]ListIterator`.
  func inferFromTraitBounds(
    typeParameters: [TypeParameterDecl],
    inferred: inout [String: Type]
  ) throws {
    // Build a substitution map from already-inferred type parameters
    let substitution: [String: Type] = inferred
    
    // Iterate until no more progress is made
    var madeProgress = true
    while madeProgress {
      madeProgress = false
      
      for param in typeParameters {
        // Skip if already inferred
        if inferred[param.name] != nil { continue }
        
        for constraint in param.constraints {
          let traitConstraint = try SemaUtils.resolveTraitConstraint(from: constraint)
          
          switch traitConstraint {
          case .generic(let traitName, let traitArgs):
            // Generic trait constraint like `R [T]Iterator` or `C [T, R]Iterable`
            // Try to infer from the trait method signatures
            
            // First, check if all type arguments in the trait constraint are known
            var allArgsKnown = true
            var resolvedTraitArgs: [Type] = []
            for arg in traitArgs {
              if case .identifier(let argName) = arg {
                if let inferredType = inferred[argName] {
                  resolvedTraitArgs.append(inferredType)
                } else {
                  allArgsKnown = false
                  break
                }
              } else {
                // Try to resolve the type node
                do {
                  let resolved = try resolveTypeNodeWithSubstitution(arg, substitution: substitution)
                  resolvedTraitArgs.append(resolved)
                } catch {
                  allArgsKnown = false
                  break
                }
              }
            }
            
            if !allArgsKnown { continue }
            
            // Now we have all trait args resolved, try to find a type that satisfies the constraint
            // For Iterator trait, look for a type with a `next` method returning `[T]Option`
            if traitName == "Iterator" && resolvedTraitArgs.count == 1 {
              _ = resolvedTraitArgs[0]
              // The type parameter should be an iterator type
              // We can't directly infer it without more context
              // This case is handled by looking at method return types
            }
            
            // For Iterable trait, look for a type with an `iterator` method
            if traitName == "Iterable" && resolvedTraitArgs.count == 2 {
              // We need to find a type that has an iterator() method
              // This is typically inferred from the argument type
            }
            
          case .simple(_):
            // Simple trait constraint like `T Any` or `T Equatable`
            // These don't help with inference
            continue
          }
        }
      }
    }
  }
  
  /// Infers type parameters from trait bounds by examining method signatures.
  /// For example, if `C = [Int]List` and `C` has constraint `[T, R]Iterable`,
  /// this looks up `iterator()` on `[Int]List` and infers `R` from its return type,
  /// then infers `T` from `R`'s `Iterator` constraint.
  func inferTypeParamsFromTraitMethods(
    typeParameters: [TypeParameterDecl],
    inferred: inout [String: Type]
  ) throws {
    // Build dependency graph: which type params depend on which
    var madeProgress = true
    var iterations = 0
    let maxIterations = typeParameters.count * 2  // Prevent infinite loops
    
    while madeProgress && iterations < maxIterations {
      madeProgress = false
      iterations += 1
      
      for param in typeParameters {
        // Skip if already inferred
        if inferred[param.name] != nil { continue }
        
        for constraint in param.constraints {
          let traitConstraint = try SemaUtils.resolveTraitConstraint(from: constraint)
          
          switch traitConstraint {
          case .generic(let traitName, let traitArgs):
            // For Iterable[T, R], if we know the concrete type C,
            // we can look up its iterator() method to get R
            if traitName == "Iterable" && traitArgs.count == 2 {
              // Check if we have a concrete type for this parameter from another source
              // This is typically the case when the parameter is a function argument
              continue
            }
            
            // For Iterator[T], if we know R, we can look up its next() method to get T
            if traitName == "Iterator" && traitArgs.count == 1 {
              if case .identifier(let elementParamName) = traitArgs[0] {
                // The element type parameter
                if inferred[elementParamName] == nil {
                  // Try to infer from the iterator type if we know it
                  // This requires knowing the concrete iterator type
                }
              }
            }
            
          case .simple:
            continue
          }
        }
      }
    }
  }
  
  /// Infers type parameters from Iterable trait bounds.
  /// Given a concrete collection type, looks up its iterator() method
  /// and extracts the iterator type and element type.
  /// 
  /// For example, if `concreteType = [Int]List`:
  /// - Looks up `iterator()` method on `[Int]List`
  /// - Gets return type `[Int]ListIterator`
  /// - Looks up `next()` method on `[Int]ListIterator`
  /// - Gets return type `[Int]Option`
  /// - Extracts element type `Int`
  /// 
  /// Returns: (elementType: T, iteratorType: R) or nil if inference fails
  private func inferIterableTypeParams(from concreteType: Type) -> (elementType: Type, iteratorType: Type)? {
    // Look up the iterator() method on the concrete type
    guard let iteratorMethod = try? lookupConcreteMethodSymbol(on: concreteType, name: "iterator") else {
      return nil
    }
    
    // Get the return type of iterator()
    guard case .function(_, let iteratorType) = iteratorMethod.type else {
      return nil
    }
    
    // Now look up the next() method on the iterator type to get the element type
    guard let nextMethod = try? lookupConcreteMethodSymbol(on: iteratorType, name: "next") else {
      return nil
    }
    
    // Get the return type of next() which should be [T]Option
    guard case .function(_, let optionType) = nextMethod.type else {
      return nil
    }
    
    // Extract T from [T]Option
    guard case .genericUnion(let templateName, let typeArgs) = optionType,
          templateName == "Option",
          typeArgs.count == 1 else {
      return nil
    }
    
    let elementType = typeArgs[0]
    return (elementType: elementType, iteratorType: iteratorType)
  }
  
  /// Enhanced unify that also handles trait-based inference.
  /// After basic unification, tries to infer remaining type parameters
  /// from trait bounds.
  func unifyWithTraitInference(
    template: GenericFunctionTemplate,
    arguments: [TypedExpressionNode],
    inferred: inout [String: Type]
  ) throws {
    let typeParams = template.typeParameters.map { $0.name }
    
    // First, do basic unification from argument types
    for (typedArg, param) in zip(arguments, template.parameters) {
      if case .identifier(let name) = param.type,
         typeParams.contains(name),
         let existing = inferred[name],
         typedArg.type != existing {
        switch typedArg {
        case .integerLiteral:
          if isIntegerType(existing) { continue }
        case .floatLiteral:
          if isFloatType(existing) { continue }
        case .stringLiteral(let value, _):
          if existing == .uint8, singleByteASCII(from: value) != nil { continue }
          if isRuneType(existing), singleRuneCodePoint(from: value) != nil { continue }
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
          let traitConstraint = try SemaUtils.resolveTraitConstraint(from: constraint)
          
          switch traitConstraint {
          case .generic(let traitName, let traitArgs):
            // Handle Iterable trait: [T, R]Iterable
            // If C has constraint [T, R]Iterable and C is inferred, we can infer T and R
            if traitName == "Iterable" && traitArgs.count == 2 {
              // Get the type parameter names from the trait args
              guard case .identifier(let tParamName) = traitArgs[0],
                    case .identifier(let rParamName) = traitArgs[1] else {
                continue
              }
              
              // The current type parameter (with Iterable constraint) should be the collection type
              // Check if it's already inferred
              if let concreteCollectionType = inferred[typeParam.name] {
                // Infer T and R from the concrete collection type
                if let (elementType, iteratorType) = inferIterableTypeParams(from: concreteCollectionType) {
                  if inferred[tParamName] == nil {
                    inferred[tParamName] = elementType
                    madeProgress = true
                  }
                  if inferred[rParamName] == nil {
                    inferred[rParamName] = iteratorType
                    madeProgress = true
                  }
                }
              }
            }
            
            // Handle Iterator trait: [T]Iterator
            // If R has constraint [T]Iterator and R is inferred, we can infer T
            if traitName == "Iterator" && traitArgs.count == 1 {
              guard case .identifier(let tParamName) = traitArgs[0] else {
                continue
              }
              
              // If we know the iterator type, extract the element type
              if let concreteIteratorType = inferred[typeParam.name] {
                if inferred[tParamName] == nil {
                  if let nextMethod = try? lookupConcreteMethodSymbol(on: concreteIteratorType, name: "next"),
                     case .function(_, let optionType) = nextMethod.type,
                     case .genericUnion(let templateName, let typeArgs) = optionType,
                     templateName == "Option",
                     typeArgs.count == 1 {
                    inferred[tParamName] = typeArgs[0]
                    madeProgress = true
                  }
                }
              }
            }
            
          case .simple:
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
    case .identifier(let name):
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
    case .reference(let inner):
      if case .reference(let innerType) = type {
        try unify(node: inner, type: innerType, inferred: &inferred, typeParams: typeParams)
      }
    case .pointer(let inner):
      if case .pointer(let elementType) = type {
        try unify(node: inner, type: elementType, inferred: &inferred, typeParams: typeParams)
      }
    case .generic(let base, let args):
      if case .genericStruct(let templateName, let typeArgs) = type {
        // Match against genericStruct type
        if templateName == base && typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      } else if case .genericUnion(let templateName, let typeArgs) = type {
        // Match against genericUnion type
        if templateName == base && typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      }
    case .functionType(let paramTypes, let returnType):
      // Match against function type
      if case .function(let params, let returns) = type {
        if params.count == paramTypes.count {
          for (paramNode, param) in zip(paramTypes, params) {
            try unify(node: paramNode, type: param.type, inferred: &inferred, typeParams: typeParams)
          }
          try unify(node: returnType, type: returns, inferred: &inferred, typeParams: typeParams)
        }
      }
    case .moduleQualified(_, let name):
      // 模块限定类型：检查类型名是否是类型参数
      if typeParams.contains(name) {
        if let existing = inferred[name] {
          if existing != type {
            throw SemanticError.typeMismatch(expected: existing.description, got: type.description)
          }
        } else {
          inferred[name] = type
        }
      }
    case .moduleQualifiedGeneric(_, let base, let args):
      // 模块限定泛型类型
      if case .genericStruct(let templateName, let typeArgs) = type {
        if templateName == base && typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      } else if case .genericUnion(let templateName, let typeArgs) = type {
        if templateName == base && typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      }
    }
  }

  /// Infer type arguments for a generic struct constructor call
  /// e.g., Stream(iter) -> [T, R]Stream(iter) where T and R are inferred from iter's type
  func inferGenericStructConstruction(
    template: GenericStructTemplate,
    name: String,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    // Type check arguments first
    if arguments.count != template.parameters.count {
      throw SemanticError.invalidArgumentCount(
        function: name,
        expected: template.parameters.count,
        got: arguments.count
      )
    }
    
    var typedArguments: [TypedExpressionNode] = []
    for argExpr in arguments {
      let typedArg = try inferTypedExpression(argExpr)
      typedArguments.append(typedArg)
    }
    
    // Infer type arguments from constructor arguments
    var inferred: [String: Type] = [:]
    let typeParamNames = template.typeParameters.map { $0.name }
    for (typedArg, param) in zip(typedArguments, template.parameters) {
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
          let traitConstraint = try SemaUtils.resolveTraitConstraint(from: constraint)
          
          switch traitConstraint {
          case .generic(let traitName, let traitArgs):
            // Handle Iterator trait: [T]Iterator
            // If R has constraint [T]Iterator and R is inferred, we can infer T
            if traitName == "Iterator" && traitArgs.count == 1 {
              guard case .identifier(let tParamName) = traitArgs[0] else {
                continue
              }
              
              // If we know the iterator type, extract the element type
              if let concreteIteratorType = inferred[typeParam.name] {
                if inferred[tParamName] == nil {
                  if let nextMethod = try? lookupConcreteMethodSymbol(on: concreteIteratorType, name: "next"),
                     case .function(_, let optionType) = nextMethod.type,
                     case .genericUnion(let templateName, let typeArgs) = optionType,
                     templateName == "Option",
                     typeArgs.count == 1 {
                    inferred[tParamName] = typeArgs[0]
                    madeProgress = true
                  }
                }
              }
            }
            
            // Handle Iterable trait: [T, R]Iterable
            if traitName == "Iterable" && traitArgs.count == 2 {
              guard case .identifier(let tParamName) = traitArgs[0],
                    case .identifier(let rParamName) = traitArgs[1] else {
                continue
              }
              
              if let concreteCollectionType = inferred[typeParam.name] {
                if let (elementType, iteratorType) = inferIterableTypeParams(from: concreteCollectionType) {
                  if inferred[tParamName] == nil {
                    inferred[tParamName] = elementType
                    madeProgress = true
                  }
                  if inferred[rParamName] == nil {
                    inferred[rParamName] = iteratorType
                    madeProgress = true
                  }
                }
              }
            }
            
          case .simple:
            continue
          }
        }
      }
    }
    
    // Build resolved type arguments
    let resolvedArgs = try template.typeParameters.map { param -> Type in
      guard let type = inferred[param.name] else {
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
    
    // Re-check arguments with resolved types and apply coercion
    var finalTypedArguments: [TypedExpressionNode] = []
    for (typedArg, expectedMember) in zip(typedArguments, memberTypes) {
      let finalArg = try coerceLiteral(typedArg, to: expectedMember.type)
      if finalArg.type != expectedMember.type {
        throw SemanticError.typeMismatch(
          expected: expectedMember.type.description,
          got: finalArg.type.description
        )
      }
      finalTypedArguments.append(finalArg)
    }
    
    let genericType = Type.genericStruct(template: name, args: resolvedArgs)
    
    return .typeConstruction(
      identifier: makeLocalSymbol(name: name, type: genericType, kind: .type),
      typeArgs: resolvedArgs,
      arguments: finalTypedArguments,
      type: genericType
    )
  }
}

import Foundation

// MARK: - Trait Handling Extension
// This extension contains methods for trait validation, lookup, and trait method signatures.

extension TypeChecker {

  // Wrapper for shared utility function from SemaUtils.swift
  private func resolveTraitName(from node: TypeNode) throws -> String {
    return try SemaUtils.resolveTraitName(from: node)
  }

  func validateTraitName(_ name: String) throws {
    try SemaUtils.validateTraitName(name, traits: traits, currentLine: currentLine)

    let traitModulePath = traits[name]?.modulePath ?? []
    if traitModulePath.isEmpty || traitModulePath == currentModulePath {
      return
    }

    do {
      try visibilityChecker.checkSymbolVisibility(
        symbolModulePath: traitModulePath,
        symbolName: name,
        currentModulePath: currentModulePath,
        currentSourceFile: currentSourceFile,
        importGraph: importGraph
      )
    } catch let error as VisibilityError {
      throw SemanticError(.generic(error.description), span: currentSpan)
    }
  }

  func flattenedTraitMethods(_ traitName: String) throws -> [String: TraitMethodSignature] {
    if let cached = flattenedTraitMethodsCache[traitName] {
      return cached
    }
    let result = try SemaUtils.flattenedTraitMethods(traitName, traits: traits, currentLine: currentLine)
    flattenedTraitMethodsCache[traitName] = result
    return result
  }

  /// Checks if a type parameter has a trait bound, including inherited traits.
  /// For example, if K has bound HashKey and HashKey extends Equatable,
  /// then hasTraitBound("K", "Equatable") returns true.
  func hasTraitBound(_ paramName: String, _ traitName: String) -> Bool {
    guard let bounds = genericTraitBounds[paramName] else {
      return false
    }
    
    // Check direct bounds
    if bounds.contains(where: { $0.baseName == traitName }) {
      return true
    }
    
    // Check inherited traits
    for bound in bounds {
      let boundName = bound.baseName
      if let traitInfo = traits[boundName] {
        // Check if this trait inherits from the target trait
        if traitInfo.superTraits.contains(where: { $0.baseName == traitName }) {
          return true
        }
        // Recursively check super traits
        for superTrait in traitInfo.superTraits {
          if hasTraitInheritance(superTrait.baseName, traitName) {
            return true
          }
        }
      }
    }
    
    return false
  }
  
  /// Finds the trait constraint for a given type parameter and trait name.
  /// Returns the full TraitConstraint including type arguments.
  func findTraitConstraint(_ paramName: String, _ traitName: String) -> TraitConstraint? {
    guard let bounds = genericTraitBounds[paramName] else {
      return nil
    }
    return bounds.first(where: { $0.baseName == traitName })
  }
  
  /// Checks if a trait inherits from another trait (directly or transitively).
  private func hasTraitInheritance(_ traitName: String, _ targetTrait: String) -> Bool {
    if traitName == targetTrait {
      return true
    }
    
    guard let traitInfo = traits[traitName] else {
      return false
    }
    
    if traitInfo.superTraits.contains(where: { $0.baseName == targetTrait }) {
      return true
    }
    
    for superTrait in traitInfo.superTraits {
      if hasTraitInheritance(superTrait.baseName, targetTrait) {
        return true
      }
    }
    
    return false
  }

  func expectedFunctionTypeForTraitMethod(
    _ method: TraitMethodSignature,
    selfType: Type,
    traitInfo: TraitDeclInfo? = nil,
    traitTypeArgs: [Type] = []
  ) throws -> Type {
    return try withNewScope {
      // Bind both `Self` and inferred self placeholder.
      let normalizedSelfType: Type
      if case .reference(let inner) = selfType {
        normalizedSelfType = inner
      } else {
        normalizedSelfType = selfType
      }
      try currentScope.defineType("Self", type: normalizedSelfType)

      // Bind trait-level type parameters to their actual type arguments
      // For example, for [T]Iterator with constraint [A]Iterator, bind T -> A
      if let traitInfo = traitInfo {
        for (i, typeParam) in traitInfo.typeParameters.enumerated() {
          if i < traitTypeArgs.count {
            try currentScope.defineType(typeParam.name, type: traitTypeArgs[i])
          }
        }
      }

      // Bind method-level type parameters as generic parameters
      for typeParam in method.typeParameters {
        currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
      }

      let params: [Parameter] = try method.parameters.map { param in
        let t = try resolveTypeNode(param.type)
        return Parameter(type: t, kind: .byVal)
      }
      let ret = try resolveTypeNode(method.returnType)
      return Type.function(parameters: params, returns: ret)
    }
  }

  func formatTraitMethodSignature(
    _ method: TraitMethodSignature,
    selfType: Type,
    traitInfo: TraitDeclInfo? = nil,
    traitTypeArgs: [Type] = []
  ) throws -> String {
    return try withNewScope {
      try currentScope.defineType("Self", type: selfType)
      
      // Bind trait-level type parameters to their actual type arguments
      if let traitInfo = traitInfo {
        for (i, typeParam) in traitInfo.typeParameters.enumerated() {
          if i < traitTypeArgs.count {
            try currentScope.defineType(typeParam.name, type: traitTypeArgs[i])
          }
        }
      }
      
      // Bind method-level type parameters as generic parameters
      for typeParam in method.typeParameters {
        currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
      }

      let paramsDesc = try method.parameters.map { param -> String in
        let resolvedType = try resolveTypeNode(param.type)
        let mutPrefix = param.mutable ? "mut " : ""
        return "\(mutPrefix)\(param.name) \(resolvedType)"
      }.joined(separator: ", ")

      let ret = try resolveTypeNode(method.returnType)
      return "\(method.name)(\(paramsDesc)) \(ret)"
    }
  }

  // MARK: - Object Safety Check

  /// Checks whether a trait is object-safe (can be used as a trait object).
  /// Returns (isObjectSafe, reasons) where reasons lists why it's not safe.
  /// Uses objectSafetyCache for memoization and visited set for cycle detection.
  func checkObjectSafety(_ traitName: String) throws -> (Bool, [String]) {
    if let cached = objectSafetyCache[traitName] {
      return cached
    }
    var visited: Set<String> = []
    let result = try checkObjectSafetyHelper(traitName, visited: &visited)
    objectSafetyCache[traitName] = result
    return result
  }

  private func checkObjectSafetyHelper(
    _ traitName: String,
    visited: inout Set<String>
  ) throws -> (Bool, [String]) {
    // Cycle detection: if already in the check chain, treat as safe to avoid infinite recursion
    if visited.contains(traitName) {
      return (true, [])
    }
    visited.insert(traitName)

    // Cache hit
    if let cached = objectSafetyCache[traitName] {
      return cached
    }

    guard let traitInfo = traits[traitName] else {
      throw SemanticError(.generic("Undefined trait: \(traitName)"), span: currentSpan)
    }

    var reasons: [String] = []

    // Check all methods (including inherited)
    let allMethods = try flattenedTraitMethods(traitName)

    for (name, method) in allMethods {
      // Rule 1: method must not have generic type parameters
      if !method.typeParameters.isEmpty {
        reasons.append("method '\(name)' has generic type parameters")
      }

      // Rule 2: Self must not appear in parameter types (except receiver) or return type
      for (i, param) in method.parameters.enumerated() {
        if i == 0 && param.name == "self" { continue }
        if containsSelfType(param.type) {
          reasons.append("method '\(name)' uses Self in parameter '\(param.name)'")
        }
      }
      if containsSelfType(method.returnType) {
        reasons.append("method '\(name)' uses Self in return type")
      }
    }

    // Check parent traits' object safety (using visited to prevent cycles)
    for superTrait in traitInfo.superTraits {
      let (parentSafe, parentReasons) = try checkObjectSafetyHelper(superTrait.baseName, visited: &visited)
      if !parentSafe {
        reasons.append(contentsOf: parentReasons.map { "inherited from \(superTrait.baseName): \($0)" })
      }
    }

    let result = (reasons.isEmpty, reasons)
    objectSafetyCache[traitName] = result
    return result
  }

  /// Recursively checks if a TypeNode contains Self type (excluding receiver position).
  private func containsSelfType(_ node: TypeNode) -> Bool {
    switch node {
    case .inferredSelf:
      return true
    case .identifier(let name):
      return name == "Self"
    case .reference(let inner):
      return containsSelfType(inner)
    case .pointer(let inner):
      return containsSelfType(inner)
    case .weakReference(let inner):
      return containsSelfType(inner)
    case .generic(_, let args):
      return args.contains { containsSelfType($0) }
    case .functionType(let paramTypes, let returnType):
      return paramTypes.contains { containsSelfType($0) } || containsSelfType(returnType)
    case .moduleQualified:
      return false
    case .moduleQualifiedGeneric(_, _, let args):
      return args.contains { containsSelfType($0) }
    }
  }

  // MARK: - Vtable Method Index

  /// Returns an ordered list of trait methods for vtable layout.
  /// Parent trait methods come first (in declaration order), then the trait's own methods.
  func orderedTraitMethods(_ traitName: String) throws -> [(name: String, signature: TraitMethodSignature)] {
    var visited: Set<String> = []
    return try orderedTraitMethodsHelper(traitName, visited: &visited)
  }

  private func orderedTraitMethodsHelper(
    _ traitName: String,
    visited: inout Set<String>
  ) throws -> [(name: String, signature: TraitMethodSignature)] {
    if visited.contains(traitName) { return [] }
    visited.insert(traitName)

    if SemaUtils.isBuiltinTrait(traitName) { return [] }

    guard let decl = traits[traitName] else {
      throw SemanticError(.generic("Undefined trait: \(traitName)"), span: currentSpan)
    }

    var result: [(name: String, signature: TraitMethodSignature)] = []
    var seen: Set<String> = []

    // Parent trait methods first
    for parent in decl.superTraits {
      let parentMethods = try orderedTraitMethodsHelper(parent.baseName, visited: &visited)
      for entry in parentMethods where !seen.contains(entry.name) {
        result.append(entry)
        seen.insert(entry.name)
      }
    }

    // Then this trait's own methods
    for m in decl.methods where !seen.contains(m.name) {
      result.append((name: m.name, signature: m))
      seen.insert(m.name)
    }

    return result
  }

  /// Computes the vtable index for a method in a trait.
  /// Methods are ordered by declaration order, with parent trait methods first.
  func vtableMethodIndex(traitName: String, methodName: String) throws -> Int {
    let ordered = try orderedTraitMethods(traitName)
    guard let index = ordered.firstIndex(where: { $0.name == methodName }) else {
      throw SemanticError(
        .generic("Method '\(methodName)' not found in trait '\(traitName)'"),
        span: currentSpan
      )
    }
    return index
  }

  // MARK: - Trait Tool Methods

  func flattenedTraitToolMethods(_ traitName: String) throws -> [String: MethodDeclaration] {
    var visited: Set<String> = []
    return try flattenedTraitToolMethodsHelper(traitName, visited: &visited)
  }

  private func flattenedTraitToolMethodsHelper(
    _ traitName: String,
    visited: inout Set<String>
  ) throws -> [String: MethodDeclaration] {
    if visited.contains(traitName) {
      return [:]
    }
    visited.insert(traitName)

    guard let traitInfo = traits[traitName] else {
      throw SemanticError(.generic("Undefined trait: \(traitName)"), span: currentSpan)
    }

    var result: [String: MethodDeclaration] = [:]

    for parent in traitInfo.superTraits {
      let parentMethods = try flattenedTraitToolMethodsHelper(parent.baseName, visited: &visited)
      for (name, method) in parentMethods {
        if result[name] != nil {
          throw SemanticError(.generic("Ambiguous tool method '\(name)' inherited in trait '\(traitName)'"), span: currentSpan)
        }
        result[name] = method
      }
    }

    if let blocks = traitToolBlocks[traitName] {
      for block in blocks {
        for method in block.methods {
          if result[method.name] != nil {
            throw SemanticError(.generic("Trait tool method conflict '\(method.name)' in trait '\(traitName)'"), span: currentSpan)
          }
          result[method.name] = method
        }
      }
    }

    return result
  }

  func expectedFunctionTypeForToolMethod(
    _ method: MethodDeclaration,
    selfType: Type
  ) throws -> Type {
    return try withNewScope {
      try currentScope.defineType("Self", type: selfType)

      for typeParam in method.typeParameters {
        currentScope.defineGenericParameter(typeParam.name, type: .genericParameter(name: typeParam.name))
      }

      let params: [Parameter] = try method.parameters.map { param in
        let t = try resolveTypeNode(param.type)
        return Parameter(type: t, kind: param.mutable ? .byMutRef : .byVal)
      }
      let ret = try resolveTypeNode(method.returnType)
      return Type.function(parameters: params, returns: ret)
    }
  }
}

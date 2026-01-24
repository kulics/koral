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
  }

  func flattenedTraitMethods(_ traitName: String) throws -> [String: TraitMethodSignature] {
    return try SemaUtils.flattenedTraitMethods(traitName, traits: traits, currentLine: currentLine)
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
        if traitInfo.superTraits.contains(traitName) {
          return true
        }
        // Recursively check super traits
        for superTrait in traitInfo.superTraits {
          if hasTraitInheritance(superTrait, traitName) {
            return true
          }
        }
      }
    }
    
    return false
  }
  
  /// Finds the trait constraint for a given type parameter and trait name.
  /// Returns the full TraitConstraint including type arguments.
  private func findTraitConstraint(_ paramName: String, _ traitName: String) -> TraitConstraint? {
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
    
    if traitInfo.superTraits.contains(targetTrait) {
      return true
    }
    
    for superTrait in traitInfo.superTraits {
      if hasTraitInheritance(superTrait, targetTrait) {
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
      try currentScope.defineType("Self", type: selfType)

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
        try currentScope.defineType(typeParam.name, type: .genericParameter(name: typeParam.name))
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
        try currentScope.defineType(typeParam.name, type: .genericParameter(name: typeParam.name))
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
}

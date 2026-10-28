import Foundation

extension TypeChecker {
  enum GivenOwnerKind {
    case type
    case trait
  }

  struct GivenOwner {
    let kind: GivenOwnerKind
    let displayName: String
    let modulePath: [String]
  }

  func formatModulePath(_ modulePath: [String]) -> String {
    modulePath.isEmpty ? "<root>" : modulePath.joined(separator: ".")
  }

  func givenTraitOwner(named traitName: String) -> GivenOwner? {
    guard let traitInfo = traits[traitName] else { return nil }
    return GivenOwner(kind: .trait, displayName: traitName, modulePath: traitInfo.modulePath)
  }

  func givenGenericBaseOwner(named baseName: String) -> GivenOwner? {
    if let traitOwner = givenTraitOwner(named: baseName) {
      return traitOwner
    }
    if isTypeModifierBaseName(baseName) {
      // Every type modifier -- `*T`, `*mutable T`, `T ref`, `?T` and their
      // mutable forms -- is declared in Std whatever it points at. Missing
      // `MutPtr`/`MutRef`/`MutWeakRef` here is what let `given[T] *mutable T`
      // slip past rule 1 while `given[T] *T` did not.
      return GivenOwner(kind: .type, displayName: baseName, modulePath: ["Std"])
    }
    if let template = currentScope.lookupGenericStructTemplate(baseName) {
      return GivenOwner(
        kind: .type,
        displayName: baseName,
        modulePath: context.getModulePath(template.defId) ?? []
      )
    }
    if let template = currentScope.lookupGenericEnumTemplate(baseName) {
      return GivenOwner(
        kind: .type,
        displayName: baseName,
        modulePath: context.getModulePath(template.defId) ?? []
      )
    }
    return nil
  }

  func givenConcreteTypeInfo(from type: Type) -> (name: String, owner: GivenOwner?)? {
    switch type {
    case .structure(let defId), .`enum`(let defId):
      let name = context.getName(defId) ?? type.description
      let modulePath = context.getModulePath(defId) ?? []
      return (
        name,
        GivenOwner(kind: .type, displayName: name, modulePath: modulePath)
      )
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .wrappingInt, .wrappingInt8, .wrappingInt16, .wrappingInt32, .wrappingInt64,
      .wrappingUInt, .wrappingUInt8, .wrappingUInt16, .wrappingUInt32, .wrappingUInt64,
      .float32, .float64, .bool:
      return (type.description, nil)
    default:
      return nil
    }
  }

  /// Rule 2's self-type owner for `given Self as Trait`, for every shape of
  /// self type. Type modifiers are Std's whatever they point at; a nominal
  /// carries its declaration's module; a primitive has no owner and therefore
  /// no locality to enforce. Mirrors bootstrap's
  /// `GivenLocalityChecker.resolve_type_owner`.
  func givenConformanceTypeOwner(baseName: String?, selfType: Type) -> GivenOwner? {
    if let baseName, isTypeModifierBaseName(baseName) {
      return GivenOwner(kind: .type, displayName: baseName, modulePath: ["Std"])
    }
    if let baseName {
      if let template = currentScope.lookupGenericStructTemplate(baseName) {
        return GivenOwner(
          kind: .type,
          displayName: baseName,
          modulePath: context.getModulePath(template.defId) ?? []
        )
      }
      if let template = currentScope.lookupGenericEnumTemplate(baseName) {
        return GivenOwner(
          kind: .type,
          displayName: baseName,
          modulePath: context.getModulePath(template.defId) ?? []
        )
      }
    }
    return givenConcreteTypeInfo(from: selfType)?.owner
  }

  func enforceGivenOwnerLocality(_ owner: GivenOwner, span: SourceSpan) throws {
    guard owner.modulePath == currentModulePath else {
      let kindLabel = owner.kind == .trait ? "trait" : "type"
      throw SemanticError(
        .generic(
          "Cannot declare 'given \(owner.displayName)' in module '\(formatModulePath(currentModulePath))': \(kindLabel) is declared in '\(formatModulePath(owner.modulePath))'"
        ),
        span: span
      )
    }
  }

  func enforceGivenConformanceLocality(
    selfType: Type,
    traitName: String,
    typeOwner: GivenOwner,
    traitOwner: GivenOwner,
    span: SourceSpan
  ) throws {
    let typeIsLocal = (typeOwner.modulePath == currentModulePath)
    let traitIsLocal = (traitOwner.modulePath == currentModulePath)
    guard typeIsLocal || traitIsLocal else {
      throw SemanticError(
        .generic(
          "Cannot declare 'given \(selfType) as \(traitName)' in module '\(formatModulePath(currentModulePath))': declaration must be in type module '\(formatModulePath(typeOwner.modulePath))' or trait module '\(formatModulePath(traitOwner.modulePath))'"
        ),
        span: span
      )
    }
  }
}

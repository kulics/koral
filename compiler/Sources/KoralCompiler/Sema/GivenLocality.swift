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
    if baseName == "Ptr" {
      return GivenOwner(kind: .type, displayName: baseName, modulePath: ["std"])
    }
    if let template = currentScope.lookupGenericStructTemplate(baseName) {
      return GivenOwner(
        kind: .type,
        displayName: baseName,
        modulePath: context.getModulePath(template.defId) ?? []
      )
    }
    if let template = currentScope.lookupGenericUnionTemplate(baseName) {
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
    case .structure(let defId), .union(let defId):
      let name = context.getName(defId) ?? type.description
      let modulePath = context.getModulePath(defId) ?? []
      return (
        name,
        GivenOwner(kind: .type, displayName: name, modulePath: modulePath)
      )
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64, .bool:
      return (type.description, nil)
    default:
      return nil
    }
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
          "Cannot declare 'given \(selfType) \(traitName)' in module '\(formatModulePath(currentModulePath))': declaration must be in type module '\(formatModulePath(typeOwner.modulePath))' or trait module '\(formatModulePath(traitOwner.modulePath))'"
        ),
        span: span
      )
    }
  }
}

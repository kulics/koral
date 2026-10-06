// MethodIdentity.swift
//
// Identity of the type a method or conformance registry is keyed by.
//
// Mirrors bootstrap/koralc/typed/types.koral's `MethodOwner` / `MethodInstanceKey`.
// A method belongs to a TYPE, not to a type NAME. Names are for RESOLUTION, for
// display and for C mangling; once a type is resolved, only identity is compared.

/// Identity of the type a method or conformance registry is keyed by.
///
/// For anything that has a declaration -- a nominal, a generic template, a trait
/// -- the identity is that declaration's `DefId`, and `DefId` already carries the
/// module: two modules' `Plain` are two keys, so `mod_a`'s `given Plain { tag }`
/// can never answer for `mod_b`'s `Plain`.
///
/// Built-in scalars and type modifiers (`ref`/`ptr`/`weakref`) have no
/// declaration to identify them by. They share one closed key space instead --
/// the same split rustc makes between `inherent_impls: FxIndexMap<LocalDefId,
/// Vec<DefId>>` and `incoherent_impls: FxIndexMap<SimplifiedType, Vec<DefId>>`.
public enum MethodOwner: Hashable, Equatable {
  /// A type with a declaration. An instance resolves to its TEMPLATE.
  case decl(DefId)
  /// A type with no declaration: a built-in scalar or a type modifier.
  case builtin(String)

  /// Printable form, for diagnostics only. Never decides identity.
  public var display: String {
    switch self {
    case .decl(let defId): return "decl#\(defId.id)"
    case .builtin(let name): return name
    }
  }
}

/// Key of one INSTANTIATED method: which declaration, which instantiation of it,
/// which method, and which method-level type arguments.
///
/// `ownerArgs` is the owner's INSTANTIATION: `List[String]` and `List[Rune]`
/// share the owner `List` and differ here, exactly as rustc's `Instance` is
/// `(DefId, GenericArgs)` and not `DefId` alone. Keying an instance table by the
/// owner alone makes those two one entry.
public struct MethodInstanceKey: Hashable, Equatable {
  public let owner: MethodOwner
  public let ownerArgs: [Type]
  public let methodName: String
  public let methodTypeArgs: [Type]

  public init(owner: MethodOwner, ownerArgs: [Type], methodName: String, methodTypeArgs: [Type]) {
    self.owner = owner
    self.ownerArgs = ownerArgs
    self.methodName = methodName
    self.methodTypeArgs = methodTypeArgs
  }
}

extension TypeChecker {
  /// Owner identity of a target known only by its SPELLING.
  ///
  /// RESOLUTION is the one place a name decides something; the identity then
  /// comes from the declaration. This covers the generic `given` target, which
  /// is known syntactically as a base name (`given [T] List`).
  public func methodOwnerForName(_ name: String) -> MethodOwner? {
    // The closed built-in space: a modifier or scalar has no declaration to
    // resolve to, and its spelling IS its identity.
    let builtins = [
      "Ref": "Ref", "MutRef": "MutRef", "BorrowRef": "Ref", "BorrowMutRef": "MutRef",
      "Ptr": "Ptr", "MutPtr": "MutPtr", "WeakRef": "WeakRef", "MutWeakRef": "MutWeakRef",
      "Int": "Int", "Int8": "Int8", "Int16": "Int16", "Int32": "Int32", "Int64": "Int64",
      "UInt": "UInt", "UInt8": "UInt8", "UInt16": "UInt16", "UInt32": "UInt32", "UInt64": "UInt64",
      "Float32": "Float32", "Float64": "Float64", "Bool": "Bool",
    ]
    if let builtin = builtins[name] {
      return .builtin(builtin)
    }
    // A generic template is a declaration too: `given [T] List` extends the
    // `List` template, and `List[T].new` keys on that template's DefId. Resolving
    // only through the type table would miss it and fall back to `.builtin("List")`,
    // which then never matches the lookup side.
    // Generic templates: resolve in the module being checked and do NOT fall
    // back to the bare name. See `lookupGenericStructTemplateDefIdStrict`.
    let modulePath = context.defIdMap.currentModulePath
    if let defId = context.defIdMap.lookupGenericStructTemplateDefIdStrict(
      modulePath: modulePath, name: name)
    {
      return context.methodOwnerDecl(defId)
    }
    if let defId = context.defIdMap.lookupGenericEnumTemplateDefIdStrict(
      modulePath: modulePath, name: name)
    {
      return context.methodOwnerDecl(defId)
    }
    if let owner = context.methodOwnerForName(name) {
      return owner
    }
    if let t = currentScope.lookupGenericStructTemplate(name) {
      return context.methodOwnerDecl(t.defId)
    }
    if let t = currentScope.lookupGenericEnumTemplate(name) {
      return context.methodOwnerDecl(t.defId)
    }
    if let t = currentScope.lookupType(name) {
      return context.methodOwner(of: t)
    }
    if let traitInfo = traits[name] {
      return context.methodOwnerDecl(traitInfo.defId)
    }
    return nil
  }
}

extension CompilerContext {
  /// `defId`, or its template when the declaration is a monomorphized instance.
  /// A declaration with no template is its own owner.
  public func methodOwnerDecl(_ defId: DefId) -> MethodOwner {
    if let templateId = defIdMap.getTemplateDefId(defId), templateId.isValid {
      return .decl(templateId)
    }
    return .decl(defId)
  }

  /// The spelling of a declaration -- for DISPLAY and C mangling ONLY.
  ///
  /// `Type` carries a declaration's `DefId`, never its path (rustc's
  /// `Ty::Adt(&AdtDef, _)`). When output needs a name it is read from the
  /// declaration here; nothing decides identity from it.
  public func spelling(_ defId: DefId) -> String {
    return defIdMap.getName(defId) ?? "d\(defId.id)"
  }

  /// The declaration a method registry keys `t` by.
  ///
  /// A monomorphized instance resolves to its TEMPLATE's declaration, because
  /// methods are declared on the template and not on each instantiation.
  /// Built-in scalars and type modifiers have no declaration, so they are keyed
  /// in the closed `builtin` space -- the only place a name decides a key, and
  /// only for types that have no declaration to decide it instead.
  /// The declaration a method registry keys `t` by.
  ///
  /// A monomorphized instance resolves to its TEMPLATE's declaration, because
  /// methods are declared on the template and not on each instantiation.
  ///
  /// Built-in scalars and type modifiers (`ref`/`ptr`/`weakref`) have NO
  /// declaration, so they are keyed in the closed `builtin` space by their kind
  /// name. This is the only place a name decides a key, and only for types that
  /// have no declaration to decide it instead -- the same split rustc makes
  /// between `inherent_impls: FxIndexMap<LocalDefId, Vec<DefId>>` and
  /// `incoherent_impls: FxIndexMap<SimplifiedType, Vec<DefId>>`
  /// (`rustc_middle::ty::fast_reject::SimplifyType`).
  public func methodOwner(of t: Type) -> MethodOwner {
    switch t {
    case .traitObject(let traitDefId, _):
      return methodOwnerDecl(traitDefId)
    case .structure(let defId), .enum(let defId), .opaque(let defId):
      return methodOwnerDecl(defId)
    case .genericStruct(let templateDefId, _):
      return genericTemplateOwner(templateDefId)
    case .genericEnum(let templateDefId, _):
      return genericTemplateOwner(templateDefId)

    case .reference, .borrowedReference:
      return .builtin("Ref")
    case .mutableReference, .mutableBorrowedReference:
      return .builtin("MutRef")
    case .pointer:
      return .builtin("Ptr")
    case .mutablePointer:
      return .builtin("MutPtr")
    case .weakReference:
      return .builtin("WeakRef")
    case .mutableWeakReference:
      return .builtin("MutWeakRef")

    case .int: return .builtin("Int")
    case .int8: return .builtin("Int8")
    case .int16: return .builtin("Int16")
    case .int32: return .builtin("Int32")
    case .int64: return .builtin("Int64")
    case .uint: return .builtin("UInt")
    case .uint8: return .builtin("UInt8")
    case .uint16: return .builtin("UInt16")
    case .uint32: return .builtin("UInt32")
    case .uint64: return .builtin("UInt64")
    case .float32: return .builtin("Float32")
    case .float64: return .builtin("Float64")
    case .bool: return .builtin("Bool")
    case .void: return .builtin("Void")
    case .never: return .builtin("Never")

    case .function: return .builtin("Function")
    case .genericParameter(let name): return .builtin("TypeParam.\(name)")
    case .module: return .builtin("Module")
    case .error: return .builtin("Error")
    case .typeVariable: return .builtin("TypeVar")
    }
  }

  /// The (owner, type arguments) pair identifying a type's INSTANTIATION.
  ///
  /// Both spellings of an instantiation (`structure` of a monomorphized instance
  /// and `genericStruct` of the template) land on the same pair.
  public func methodOwnerAndArgs(of t: Type) -> (owner: MethodOwner, args: [Type]) {
    switch t {
    case .genericStruct(let templateDefId, let args):
      return (genericTemplateOwner(templateDefId), args)
    case .genericEnum(let templateDefId, let args):
      return (genericTemplateOwner(templateDefId), args)
    case .structure(let defId), .enum(let defId), .opaque(let defId):
      return (methodOwnerDecl(defId), getTypeArguments(defId) ?? [])
    case .traitObject(let traitDefId, let typeArgs):
      return (methodOwnerDecl(traitDefId), typeArgs)

    case .reference(let inner), .borrowedReference(let inner):
      return (.builtin("Ref"), [inner])
    case .mutableReference(let inner), .mutableBorrowedReference(let inner):
      return (.builtin("MutRef"), [inner])
    case .pointer(let inner):
      return (.builtin("Ptr"), [inner])
    case .mutablePointer(let inner):
      return (.builtin("MutPtr"), [inner])
    case .weakReference(let inner):
      return (.builtin("WeakRef"), [inner])
    case .mutableWeakReference(let inner):
      return (.builtin("MutWeakRef"), [inner])

    default:
      return (methodOwner(of: t), [])
    }
  }

  /// Owner of a generic template.
  ///
  /// The `Type` carries the template's DECLARATION and there is no name lookup
  /// here: rustc's `Ty::Adt` holds `&AdtDef`, never a path, so two same-named
  /// templates from different modules cannot alias.
  private func genericTemplateOwner(_ templateDefId: DefId) -> MethodOwner {
    return methodOwnerDecl(templateDefId)
  }

  /// Owner identity of a spelling, resolved through the declaration tables only.
  /// See `TypeChecker.methodOwnerForName` for the full resolver.
  public func methodOwnerForName(_ name: String) -> MethodOwner? {
    let modulePath = defIdMap.currentModulePath
    if let defId = defIdMap.lookupGenericStructTemplateDefIdStrict(modulePath: modulePath, name: name) {
      return methodOwnerDecl(defId)
    }
    if let defId = defIdMap.lookupGenericEnumTemplateDefIdStrict(modulePath: modulePath, name: name) {
      return methodOwnerDecl(defId)
    }
    return nil
  }

  /// The declaration identity of `t`'s owner, when it has one.
  /// Built-in scalars and modifiers have no declaration and return `nil`.
  public func ownerDefId(of t: Type) -> DefId? {
    if case .decl(let defId) = methodOwner(of: t) {
      return defId
    }
    return nil
  }

  /// Key of a method instantiated for a concrete receiver: the receiver's owner
  /// identity AND its instantiation arguments, so `List[String].new` and
  /// `List[Rune].new` are two entries.
  public func receiverMethodKey(_ receiverType: Type, _ methodName: String, methodTypeArgs: [Type] = [])
    -> MethodInstanceKey
  {
    let pair = methodOwnerAndArgs(of: receiverType)
    return MethodInstanceKey(
      owner: pair.owner, ownerArgs: pair.args, methodName: methodName, methodTypeArgs: methodTypeArgs)
  }
}

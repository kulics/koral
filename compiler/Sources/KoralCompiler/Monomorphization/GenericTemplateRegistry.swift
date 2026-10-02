// GenericTemplateRegistry.swift
// Defines the registry for storing generic templates collected during type checking.
// This registry is passed to the Monomorphizer for processing instantiation requests.

/// Information about a trait declaration, used for trait conformance checking.
public struct TraitDeclInfo {
    /// Stable definition identity for this trait.
    public let defId: DefId

    /// The name of the trait
    public let name: String
    
    /// Type parameters for generic traits (e.g., [T Any] for Iterator)
    public let typeParameters: [TypeParameterDecl]
    
    /// Trait constraints that this trait inherits from
    public let superTraits: [TraitConstraint]
    
    /// Method signatures required by this trait
    public let methods: [TraitMethodSignature]
    
    /// Access modifier for the trait
    public let access: AccessModifier

    /// Module path where this trait is defined.
    public let modulePath: [String]
    
    /// Creates a new trait declaration info.
    public init(
        defId: DefId,
        name: String,
        typeParameters: [TypeParameterDecl] = [],
        superTraits: [TraitConstraint],
        methods: [TraitMethodSignature],
        access: AccessModifier,
        modulePath: [String] = []
    ) {
        self.defId = defId
        self.name = name
        self.typeParameters = typeParameters
        self.superTraits = superTraits
        self.methods = methods
        self.access = access
        self.modulePath = modulePath
    }
}

/// A registry containing all generic templates collected during type checking.
/// This is used by the Monomorphizer to look up templates when processing instantiation requests.
public struct GenericExtensionMethodTemplate {
    public let typeParams: [TypeParameterDecl]
    public let method: MethodDeclaration
    public let conformanceTraitName: String?
    public let conformanceTraitDefId: DefId?
    public let sourceFile: String
    public let modulePath: [String]
    public let packageID: String

    // Declaration-time type checking results (with genericParameter types and generic Self)
    public var checkedBody: TypedExpressionNode?
    public var checkedParameters: [Symbol]?
    public var checkedReturnType: Type?

    public init(
        typeParams: [TypeParameterDecl],
        method: MethodDeclaration,
        conformanceTraitName: String? = nil,
        conformanceTraitDefId: DefId? = nil,
        sourceFile: String = "",
        modulePath: [String] = [],
        packageID: String = "",
        checkedBody: TypedExpressionNode? = nil,
        checkedParameters: [Symbol]? = nil,
        checkedReturnType: Type? = nil
    ) {
        self.typeParams = typeParams
        self.method = method
        self.conformanceTraitName = conformanceTraitName
        self.conformanceTraitDefId = conformanceTraitDefId
        self.sourceFile = sourceFile
        self.modulePath = modulePath
        self.packageID = packageID
        self.checkedBody = checkedBody
        self.checkedParameters = checkedParameters
        self.checkedReturnType = checkedReturnType
    }
}

/// Identifies the owner of a receiver-dispatched method.
///
/// Carries DECLARATIONS, never spellings: `concreteType` holds the owner's
/// `Type` and `extensionTemplate` the template's `DefId`. Deriving identity from
/// a stored name is how two same-named types from different modules got
/// conflated -- rustc's `Ty::Adt(&AdtDef, _)` has no name to reach for.
public enum ReceiverMethodOwner: Hashable {
    case extensionTemplate(ownerDefId: DefId)
    case concreteType(ownerType: Type)
}

public struct ReceiverMethodDispatchInfo: Hashable {
    public let methodDefId: DefId
    public let methodName: String
    public let owner: ReceiverMethodOwner?
    public let conformanceTraitName: String?
    public let conformanceTraitDefId: DefId?

    public init(
        methodDefId: DefId,
        methodName: String,
        owner: ReceiverMethodOwner?,
        conformanceTraitName: String? = nil,
        conformanceTraitDefId: DefId? = nil
    ) {
        self.methodDefId = methodDefId
        self.methodName = methodName
        self.owner = owner
        self.conformanceTraitName = conformanceTraitName
        self.conformanceTraitDefId = conformanceTraitDefId
    }
}

public struct GenericTemplateRegistry {
    /// Generic struct templates indexed by name
    public var structTemplates: [String: GenericStructTemplate]

    /// The same templates indexed by DECLARATION. `structTemplates` is keyed by
    /// spelling (bare and module-qualified), so identity must not depend on
    /// scanning it -- two modules may each declare `Box`.
    public var structTemplatesByDefId: [DefId: GenericStructTemplate]

    /// Generic enum templates indexed by name
    public var enumTemplates: [String: GenericEnumTemplate]

    /// The same templates indexed by DECLARATION. Same reason.
    public var enumTemplatesByDefId: [DefId: GenericEnumTemplate]
    
    /// Generic function templates indexed by name
    public var functionTemplates: [String: GenericFunctionTemplate]
    
    /// Generic extension methods indexed by owner IDENTITY.
    /// These store declaration-time checked bodies so Monomorphizer can substitute types.
    public var extensionMethods: [MethodOwner: [GenericExtensionMethodTemplate]]
    
    /// Intrinsic extension methods indexed by owner IDENTITY.
    /// These are built-in methods like Ptr.init, Ptr.peek, etc.
    public var intrinsicExtensionMethods: [MethodOwner: [(typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)]]
    
    /// Trait declarations indexed by trait name
    public var traits: [String: TraitDeclInfo]

    /// Traits indexed by DECLARATION. `traits` is keyed by spelling and is
    /// last-wins when two modules declare the same name, so it answers name
    /// resolution only; every test of the form "which trait is this?" must come
    /// from here. rustc: `Res::Def(DefKind::Trait, DefId)` leaves rustc_resolve
    /// and nothing downstream re-reads the name.
    public var traitDeclsByDefId: [DefId: TraitDeclInfo]
    
    /// Concrete extension methods indexed by owner IDENTITY.
    /// Maps owner -> method name -> method symbol.
    /// These are methods defined on non-generic types.
    public var concreteExtensionMethods: [MethodOwner: [String: Symbol]]
    
    /// Set of intrinsic generic type names (e.g., "Ptr")
    /// These types don't have Koral source implementations and need special handling during monomorphization.
    public var intrinsicGenericTypes: Set<String>
    
    /// Set of intrinsic generic function names (e.g., "alloc_memory", "dealloc_memory")
    /// These functions don't have Koral source implementations and need special handling during monomorphization.
    public var intrinsicGenericFunctions: Set<String>
    
    /// Concrete (non-generic) struct types indexed by name
    public var concreteStructTypes: [String: Type]
    
    /// Concrete (non-generic) enum types indexed by name
    public var concreteEnumTypes: [String: Type]

    /// Receiver-style method dispatch metadata, keyed by method DefId.
    /// This keeps method lookup structural and avoids name parsing in monomorphization.
    public var receiverMethodDispatch: [DefId: ReceiverMethodDispatchInfo]
    
    /// Creates an empty generic template registry.
    public init() {
        self.structTemplates = [:]
        self.structTemplatesByDefId = [:]
        self.enumTemplates = [:]
        self.enumTemplatesByDefId = [:]
        self.functionTemplates = [:]
        self.extensionMethods = [:]
        self.intrinsicExtensionMethods = [:]
        self.traits = [:]
        self.traitDeclsByDefId = [:]
        self.concreteExtensionMethods = [:]
        self.intrinsicGenericTypes = []
        self.intrinsicGenericFunctions = []
        self.concreteStructTypes = [:]
        self.concreteEnumTypes = [:]
        self.receiverMethodDispatch = [:]
    }
    
    /// Creates a generic template registry with the given templates.
    public init(
        structTemplates: [String: GenericStructTemplate],
        enumTemplates: [String: GenericEnumTemplate],
        functionTemplates: [String: GenericFunctionTemplate],
        extensionMethods: [MethodOwner: [GenericExtensionMethodTemplate]],
        intrinsicExtensionMethods: [MethodOwner: [(typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)]],
        traits: [String: TraitDeclInfo],
        traitDeclsByDefId: [DefId: TraitDeclInfo]? = nil,
        concreteExtensionMethods: [MethodOwner: [String: Symbol]] = [:],
        intrinsicGenericTypes: Set<String> = [],
        intrinsicGenericFunctions: Set<String> = [],
        concreteStructTypes: [String: Type] = [:],
        concreteEnumTypes: [String: Type] = [:],
        receiverMethodDispatch: [DefId: ReceiverMethodDispatchInfo] = [:]
    ) {
        self.structTemplates = structTemplates
        // Indexed by DECLARATION. The name maps keep both a bare and a
        // module-qualified key per template, so their values are lossless --
        // this index is a view of the same declarations, not a second source.
        var structsByDefId: [DefId: GenericStructTemplate] = [:]
        for template in structTemplates.values { structsByDefId[template.defId] = template }
        self.structTemplatesByDefId = structsByDefId
        self.enumTemplates = enumTemplates
        var enumsByDefId: [DefId: GenericEnumTemplate] = [:]
        for template in enumTemplates.values { enumsByDefId[template.defId] = template }
        self.enumTemplatesByDefId = enumsByDefId
        self.functionTemplates = functionTemplates
        self.extensionMethods = extensionMethods
        self.intrinsicExtensionMethods = intrinsicExtensionMethods
        self.traits = traits
        // Prefer the index the checker built at registration time: deriving it
        // from `traits` would inherit that map's last-wins loss under a shared
        // name. The derivation below only serves callers with no index of their
        // own, and is a snapshot of whatever the name map retained.
        if let traitDeclsByDefId {
            self.traitDeclsByDefId = traitDeclsByDefId
        } else {
            var byDefId: [DefId: TraitDeclInfo] = [:]
            for info in traits.values { byDefId[info.defId] = info }
            self.traitDeclsByDefId = byDefId
        }
        self.concreteExtensionMethods = concreteExtensionMethods
        self.intrinsicGenericTypes = intrinsicGenericTypes
        self.intrinsicGenericFunctions = intrinsicGenericFunctions
        self.concreteStructTypes = concreteStructTypes
        self.concreteEnumTypes = concreteEnumTypes
        self.receiverMethodDispatch = receiverMethodDispatch
    }

    /// The generic struct template with this DECLARATION.
    ///
    /// Reached by `DefId`, never by name: two modules may each declare `Box`, and
    /// a name lookup answers for whichever registered last. rustc's `Ty::Adt`
    /// carries `&AdtDef`, so the definition comes from the type itself.
    /// (`rustc_middle::ty::TyKind::Adt(DefId, GenericArgs)`.)
    public func structTemplate(forDefId defId: DefId) -> GenericStructTemplate? {
        guard defId.isValid else { return nil }
        return structTemplatesByDefId[defId]
    }

    /// The generic enum template with this DECLARATION. Same reason.
    public func enumTemplate(forDefId defId: DefId) -> GenericEnumTemplate? {
        guard defId.isValid else { return nil }
        return enumTemplatesByDefId[defId]
    }

    /// The trait declared at `def_id`. Identity in, declaration out -- the
    /// spelling-keyed `traits` is not consulted (rustc: `tcx.trait_def`).
    public func traitDecl(forDefId defId: DefId) -> TraitDeclInfo? {
        guard defId.isValid else { return nil }
        return traitDeclsByDefId[defId]
    }

    /// Is `def_id` the declaration of a trait?
    public func isTraitDefId(_ defId: DefId) -> Bool {
        guard defId.isValid else { return false }
        return traitDeclsByDefId[defId] != nil
    }
}

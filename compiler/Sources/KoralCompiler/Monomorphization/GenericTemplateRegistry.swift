// GenericTemplateRegistry.swift
// Defines the registry for storing generic templates collected during type checking.
// This registry is passed to the Monomorphizer for processing instantiation requests.

/// Information about a trait declaration, used for trait conformance checking.
public struct TraitDeclInfo {
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
        name: String,
        typeParameters: [TypeParameterDecl] = [],
        superTraits: [TraitConstraint],
        methods: [TraitMethodSignature],
        access: AccessModifier,
        modulePath: [String] = []
    ) {
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

    // Declaration-time type checking results (with genericParameter types and generic Self)
    public var checkedBody: TypedExpressionNode?
    public var checkedParameters: [Symbol]?
    public var checkedReturnType: Type?

    public init(
        typeParams: [TypeParameterDecl],
        method: MethodDeclaration,
        checkedBody: TypedExpressionNode? = nil,
        checkedParameters: [Symbol]? = nil,
        checkedReturnType: Type? = nil
    ) {
        self.typeParams = typeParams
        self.method = method
        self.checkedBody = checkedBody
        self.checkedParameters = checkedParameters
        self.checkedReturnType = checkedReturnType
    }
}

public struct GenericTemplateRegistry {
    /// Generic struct templates indexed by name
    public var structTemplates: [String: GenericStructTemplate]
    
    /// Generic union templates indexed by name
    public var unionTemplates: [String: GenericUnionTemplate]
    
    /// Generic function templates indexed by name
    public var functionTemplates: [String: GenericFunctionTemplate]
    
    /// Generic extension methods indexed by type name.
    /// These store declaration-time checked bodies so Monomorphizer can substitute types.
    public var extensionMethods: [String: [GenericExtensionMethodTemplate]]
    
    /// Intrinsic extension methods indexed by type name.
    /// These are built-in methods like Ptr.init, Ptr.peek, etc.
    public var intrinsicExtensionMethods: [String: [(typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)]]
    
    /// Trait declarations indexed by trait name
    public var traits: [String: TraitDeclInfo]
    
    /// Concrete extension methods indexed by type name.
    /// Maps type name -> method name -> method symbol.
    /// These are methods defined on non-generic types.
    public var concreteExtensionMethods: [String: [String: Symbol]]
    
    /// Set of intrinsic generic type names (e.g., "Ptr")
    /// These types don't have Koral source implementations and need special handling during monomorphization.
    public var intrinsicGenericTypes: Set<String>
    
    /// Set of intrinsic generic function names (e.g., "alloc_memory", "dealloc_memory")
    /// These functions don't have Koral source implementations and need special handling during monomorphization.
    public var intrinsicGenericFunctions: Set<String>
    
    /// Concrete (non-generic) struct types indexed by name
    public var concreteStructTypes: [String: Type]
    
    /// Concrete (non-generic) union types indexed by name
    public var concreteUnionTypes: [String: Type]
    
    /// Creates an empty generic template registry.
    public init() {
        self.structTemplates = [:]
        self.unionTemplates = [:]
        self.functionTemplates = [:]
        self.extensionMethods = [:]
        self.intrinsicExtensionMethods = [:]
        self.traits = [:]
        self.concreteExtensionMethods = [:]
        self.intrinsicGenericTypes = []
        self.intrinsicGenericFunctions = []
        self.concreteStructTypes = [:]
        self.concreteUnionTypes = [:]
    }
    
    /// Creates a generic template registry with the given templates.
    public init(
        structTemplates: [String: GenericStructTemplate],
        unionTemplates: [String: GenericUnionTemplate],
        functionTemplates: [String: GenericFunctionTemplate],
        extensionMethods: [String: [GenericExtensionMethodTemplate]],
        intrinsicExtensionMethods: [String: [(typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)]],
        traits: [String: TraitDeclInfo],
        concreteExtensionMethods: [String: [String: Symbol]] = [:],
        intrinsicGenericTypes: Set<String> = [],
        intrinsicGenericFunctions: Set<String> = [],
        concreteStructTypes: [String: Type] = [:],
        concreteUnionTypes: [String: Type] = [:]
    ) {
        self.structTemplates = structTemplates
        self.unionTemplates = unionTemplates
        self.functionTemplates = functionTemplates
        self.extensionMethods = extensionMethods
        self.intrinsicExtensionMethods = intrinsicExtensionMethods
        self.traits = traits
        self.concreteExtensionMethods = concreteExtensionMethods
        self.intrinsicGenericTypes = intrinsicGenericTypes
        self.intrinsicGenericFunctions = intrinsicGenericFunctions
        self.concreteStructTypes = concreteStructTypes
        self.concreteUnionTypes = concreteUnionTypes
    }
}

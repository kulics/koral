// TypeCheckerOutput.swift
// Defines the output structure from the TypeChecker phase.
// This output contains the typed program, instantiation requests, and generic templates.

/// Information about a typed extension method, including its body.
public struct TypedExtensionMethodInfo {
    /// The emitted specialized symbol name of the method
    public let mangledName: String
    
    /// The function type
    public let functionType: Type
    
    /// The typed parameters
    public let parameters: [Symbol]
    
    /// The typed body
    public let body: TypedExpressionNode
    
    /// Creates a new TypedExtensionMethodInfo.
    public init(
        mangledName: String,
        functionType: Type,
        parameters: [Symbol],
        body: TypedExpressionNode
    ) {
        self.mangledName = mangledName
        self.functionType = functionType
        self.parameters = parameters
        self.body = body
    }
}

public struct RequirementSlotParameter {
    public let name: String
    public let mutable: Bool
    public let type: Type
    public let named: Bool

    public init(name: String, mutable: Bool, type: Type, named: Bool) {
        self.name = name
        self.mutable = mutable
        self.type = type
        self.named = named
    }
}

public struct RequirementSlot {
    public let declaringTraitRef: CanonicalTraitRef
    public let methodName: String
    public let parameters: [RequirementSlotParameter]
    public let returnType: Type
    public let index: Int

    public init(
        declaringTraitRef: CanonicalTraitRef,
        methodName: String,
        parameters: [RequirementSlotParameter],
        returnType: Type,
        index: Int
    ) {
        self.declaringTraitRef = declaringTraitRef
        self.methodName = methodName
        self.parameters = parameters
        self.returnType = returnType
        self.index = index
    }
}

public struct ConformanceWitness {
    public let selfType: Type
    public let traitRef: CanonicalTraitRef
    public let directParentTraitRefs: [CanonicalTraitRef]
    public let requirementSlots: [RequirementSlot]
    public let localImplementationDefIdsByMethodName: [String: DefId]

    public init(
        selfType: Type,
        traitRef: CanonicalTraitRef,
        directParentTraitRefs: [CanonicalTraitRef],
        requirementSlots: [RequirementSlot],
        localImplementationDefIdsByMethodName: [String: DefId]
    ) {
        self.selfType = selfType
        self.traitRef = traitRef
        self.directParentTraitRefs = directParentTraitRefs
        self.requirementSlots = requirementSlots
        self.localImplementationDefIdsByMethodName = localImplementationDefIdsByMethodName
    }

    public static func key(selfType: Type, traitRef: CanonicalTraitRef) -> String {
        "\(selfType):\(traitRef.cacheKey)"
    }

    public var key: String {
        Self.key(selfType: selfType, traitRef: traitRef)
    }
}

/// The output from the TypeChecker phase.
/// Contains all information needed by the Monomorphizer to generate concrete code.
public struct TypeCheckerOutput {
    /// The type-checked program containing typed AST nodes.
    /// This includes both concrete declarations and generic template placeholders.
    public let program: TypedProgram
    
    /// The set of instantiation requests collected during type checking.
    /// Each request represents a point where a generic was used with concrete type arguments.
    /// Using a Set ensures automatic deduplication of identical requests.
    public let instantiationRequests: Set<InstantiationRequest>
    
    /// The registry of generic templates collected during type checking.
    /// Contains all generic structs, enums, functions, and extension methods.
    public let genericTemplates: GenericTemplateRegistry

    /// Explicit conformance witnesses collected during type checking.
    /// Keyed by `ConformanceWitness.key(selfType:traitRef:)`.
    public let conformanceWitnesses: [String: ConformanceWitness]

    /// Unified compiler context containing definition metadata and type information.
    public let context: CompilerContext

    /// DefIdMap containing metadata for all definitions.
    public var defIdMap: DefIdMap { context.defIdMap }
    
    /// Creates a new TypeCheckerOutput.
    /// - Parameters:
    ///   - program: The type-checked program
    ///   - instantiationRequests: The collected instantiation requests
    ///   - genericTemplates: The registry of generic templates
    public init(
        program: TypedProgram,
        instantiationRequests: Set<InstantiationRequest>,
        genericTemplates: GenericTemplateRegistry,
        conformanceWitnesses: [String: ConformanceWitness],
        context: CompilerContext
    ) {
        self.program = program
        self.instantiationRequests = instantiationRequests
        self.genericTemplates = genericTemplates
        self.conformanceWitnesses = conformanceWitnesses
        self.context = context
    }
}

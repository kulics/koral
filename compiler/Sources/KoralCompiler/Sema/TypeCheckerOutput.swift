// TypeCheckerOutput.swift
// Defines the output structure from the TypeChecker phase.
// This output contains the typed program, instantiation requests, and generic templates.

/// Information about a typed extension method, including its body.
public struct TypedExtensionMethodInfo {
    /// The mangled name of the method
    public let mangledName: String
    
    /// The function type
    public let functionType: Type
    
    /// The typed parameters
    public let parameters: [Symbol]
    
    /// The typed body
    public let body: TypedExpressionNode
    
    /// The compiler method kind (drop, at, updateAt, equals, compare, or none)
    public let methodKind: CompilerMethodKind
    
    /// Creates a new TypedExtensionMethodInfo.
    public init(
        mangledName: String,
        functionType: Type,
        parameters: [Symbol],
        body: TypedExpressionNode,
        methodKind: CompilerMethodKind
    ) {
        self.mangledName = mangledName
        self.functionType = functionType
        self.parameters = parameters
        self.body = body
        self.methodKind = methodKind
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
    /// Contains all generic structs, unions, functions, and extension methods.
    public let genericTemplates: GenericTemplateRegistry
    
    /// Creates a new TypeCheckerOutput.
    /// - Parameters:
    ///   - program: The type-checked program
    ///   - instantiationRequests: The collected instantiation requests
    ///   - genericTemplates: The registry of generic templates
    public init(
        program: TypedProgram,
        instantiationRequests: Set<InstantiationRequest>,
        genericTemplates: GenericTemplateRegistry
    ) {
        self.program = program
        self.instantiationRequests = instantiationRequests
        self.genericTemplates = genericTemplates
    }
}

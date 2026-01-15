// Monomorphizer.swift
// Implements the monomorphization phase that processes instantiation requests
// and generates concrete types and functions from generic templates.

/// The output from the Monomorphizer phase.
/// Contains only concrete (non-generic) declarations ready for code generation.
public struct MonomorphizedProgram {
    /// The global nodes containing all concrete declarations.
    public let globalNodes: [TypedGlobalNode]
    
    /// Creates a new MonomorphizedProgram.
    public init(globalNodes: [TypedGlobalNode]) {
        self.globalNodes = globalNodes
    }
}

/// The Monomorphizer processes instantiation requests collected during type checking
/// and generates concrete types and functions from generic templates.
public class Monomorphizer {
    // MARK: - Input
    
    /// The output from the TypeChecker phase
    private let input: TypeCheckerOutput
    
    // MARK: - Caches
    
    /// Cache for instantiated types: "TemplateName<Arg1,Arg2>" -> Type
    private var instantiatedTypes: [String: Type] = [:]
    
    /// Cache for instantiated functions: "TemplateName<Arg1,Arg2>" -> (MangledName, Type)
    private var instantiatedFunctions: [String: (String, Type)] = [:]
    
    /// Track which layout names have been generated to avoid duplicates
    private var generatedLayouts: Set<String> = []
    
    // MARK: - Output
    
    /// Generated global nodes for instantiated types and functions
    private var generatedNodes: [TypedGlobalNode] = []
    
    // MARK: - State
    
    /// Mapping from Layout Name to Template Info (Base Name + Args)
    private var layoutToTemplateInfo: [String: (base: String, args: [Type])] = [:]
    
    /// Extension methods indexed by type name (from registry)
    private var extensionMethods: [String: [String: Symbol]] = [:]
    
    /// Current source line for error reporting
    private var currentLine: Int = 1 {
        didSet {
            SemanticErrorContext.currentLine = currentLine
        }
    }

    /// Current source file for error reporting
    private var currentFileName: String = "<input>" {
        didSet {
            SemanticErrorContext.currentFileName = currentFileName
        }
    }
    
    /// Pending instantiation requests (work queue for transitive instantiation)
    private var pendingRequests: [InstantiationRequest] = []
    
    /// Processed request keys to avoid duplicate processing
    private var processedRequestKeys: Set<String> = []
    
    // MARK: - Initialization
    
    /// Creates a new Monomorphizer with the given TypeChecker output.
    /// - Parameter input: The output from the TypeChecker phase
    public init(input: TypeCheckerOutput) {
        self.input = input
        // Initialize concrete extension methods from the registry
        self.extensionMethods = input.genericTemplates.concreteExtensionMethods
    }
    
    // MARK: - Main Entry Point
    
    /// Performs monomorphization on all collected instantiation requests.
    /// - Returns: A MonomorphizedProgram containing only concrete declarations
    /// - Throws: SemanticError if monomorphization fails
    public func monomorphize() throws -> MonomorphizedProgram {
        // Start with the original program's global nodes
        var resultNodes: [TypedGlobalNode] = []
        
        // Extract non-template nodes from the typed program
        // Also pre-populate caches to avoid duplicating work that TypeChecker already did
        if case .program(let nodes) = input.program {
            for node in nodes {
                switch node {
                case .genericTypeTemplate, .genericFunctionTemplate:
                    // Skip template placeholders - they will be instantiated on demand
                    break
                case .globalStructDeclaration(let identifier, _):
                    // Track already-generated struct layouts
                    generatedLayouts.insert(identifier.name)
                    // Also cache the type if it's a generic instantiation
                    if case .structure(_, _, let isGenericInstantiation) = identifier.type,
                       isGenericInstantiation {
                        // Extract the cache key from the type
                        // The TypeChecker uses "TemplateName<Arg1,Arg2>" as the key
                        // We need to reconstruct this from the layout name
                        // For now, just cache by layout name to prevent duplicate generation
                        instantiatedTypes[identifier.name] = identifier.type
                    }
                    resultNodes.append(node)
                case .globalUnionDeclaration(let identifier, _):
                    // Track already-generated union layouts
                    generatedLayouts.insert(identifier.name)
                    if case .union(_, _, let isGenericInstantiation) = identifier.type,
                       isGenericInstantiation {
                        instantiatedTypes[identifier.name] = identifier.type
                    }
                    resultNodes.append(node)
                case .globalFunction(let identifier, _, _):
                    // Track already-generated functions
                    generatedLayouts.insert(identifier.name)
                    // Cache the function type
                    instantiatedFunctions[identifier.name] = (identifier.name, identifier.type)
                    resultNodes.append(node)
                case .givenDeclaration(_, let methods):
                    // Track already-generated extension methods
                    for method in methods {
                        generatedLayouts.insert(method.identifier.name)
                        instantiatedFunctions[method.identifier.name] = (method.identifier.name, method.identifier.type)
                    }
                    resultNodes.append(node)
                default:
                    resultNodes.append(node)
                }
            }
        }
        
        // Initialize pending requests with all collected instantiation requests
        pendingRequests = input.instantiationRequests
        
        // Process all instantiation requests (including transitive ones)
        while !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            try processRequest(request)
        }
        
        // Insert generated nodes before the result nodes (for C definition order)
        // Types and functions must be declared before they are used
        return MonomorphizedProgram(globalNodes: generatedNodes + resultNodes)
    }
    
    // MARK: - Request Processing
    
    /// Processes a single instantiation request.
    /// - Parameter request: The instantiation request to process
    private func processRequest(_ request: InstantiationRequest) throws {
        currentLine = request.sourceLine
        currentFileName = request.sourceFileName

        // Ensure any SemanticError factories in monomorphization have correct context.
        SemanticErrorContext.currentLine = currentLine
        SemanticErrorContext.currentFileName = currentFileName
        
        // Generate a key for this request to avoid duplicate processing
        let key = requestKey(for: request)
        guard !processedRequestKeys.contains(key) else {
            return
        }
        processedRequestKeys.insert(key)
        
        do {
            switch request.kind {
            case .structType(let template, let args):
                _ = try instantiateStruct(template: template, args: args)
                
            case .unionType(let template, let args):
                _ = try instantiateUnion(template: template, args: args)
                
            case .function(let template, let args):
                _ = try instantiateFunction(template: template, args: args)
                
            case .extensionMethod(let baseType, let templateName, let typeArgs, let methodName):
                _ = try instantiateExtensionMethod(
                    baseType: baseType,
                    templateName: templateName,
                    typeArgs: typeArgs,
                    methodName: methodName
                )
            }
        } catch let e as SemanticError {
            throw e
        }
    }
    
    /// Generates a unique key for an instantiation request.
    private func requestKey(for request: InstantiationRequest) -> String {
        switch request.kind {
        case .structType(let template, let args):
            return "struct:\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
            
        case .unionType(let template, let args):
            return "union:\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
            
        case .function(let template, let args):
            return "func:\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
            
        case .extensionMethod(let baseType, let templateName, let typeArgs, let methodName):
            return "ext:\(templateName)<\(typeArgs.map { $0.description }.joined(separator: ","))>.\(methodName)@\(baseType)"
        }
    }

    
    // MARK: - Struct Instantiation
    
    /// Instantiates a generic struct template with concrete type arguments.
    /// - Parameters:
    ///   - template: The generic struct template
    ///   - args: The concrete type arguments
    /// - Returns: The instantiated concrete type
    private func instantiateStruct(template: GenericStructTemplate, args: [Type]) throws -> Type {
        guard template.typeParameters.count == args.count else {
            throw SemanticError.typeMismatch(
                expected: "\(template.typeParameters.count) generic arguments",
                got: "\(args.count)"
            )
        }
        
        // Enforce trait constraints on type arguments
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: args)
        
        // Special case: Pointer<T> maps directly to .pointer(element: T)
        if template.name == "Pointer" {
            return .pointer(element: args[0])
        }
        
        // Check cache
        let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
        if let cached = instantiatedTypes[key] {
            return cached
        }
        
        // Calculate layout name
        let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
        let layoutName = "\(template.name)_\(argLayoutKeys)"
        
        // Create placeholder for recursion detection
        let placeholder = Type.structure(
            name: layoutName, members: [], isGenericInstantiation: true)
        instantiatedTypes[key] = placeholder
        
        // Resolve members with concrete types
        var resolvedMembers: [(name: String, type: Type, mutable: Bool)] = []
        do {
            // Create type substitution map
            var typeSubstitution: [String: Type] = [:]
            for (i, paramInfo) in template.typeParameters.enumerated() {
                typeSubstitution[paramInfo.name] = args[i]
            }
            
            for param in template.parameters {
                let fieldType = try resolveTypeNode(param.type, substitution: typeSubstitution)
                if fieldType == placeholder {
                    throw SemanticError.invalidOperation(
                        op: "Direct recursion in generic struct \(layoutName) not allowed (use ref)",
                        type1: param.name, type2: "")
                }
                resolvedMembers.append((name: param.name, type: fieldType, mutable: param.mutable))
            }
        } catch {
            instantiatedTypes.removeValue(forKey: key)
            throw error
        }
        
        // Create the concrete type
        let specificType = Type.structure(
            name: layoutName, members: resolvedMembers, isGenericInstantiation: true)
        instantiatedTypes[key] = specificType
        layoutToTemplateInfo[layoutName] = (base: template.name, args: args)
        
        // Force instantiate __drop if it exists for this type
        if let methods = input.genericTemplates.extensionMethods[template.name] {
            for entry in methods {
                if entry.method.name == "__drop" {
                    _ = try instantiateExtensionMethodFromEntry(
                        baseType: specificType,
                        structureName: template.name,
                        genericArgs: args,
                        methodInfo: entry
                    )
                }
            }
        }
        
        // Skip code generation if type still contains generic parameters
        if specificType.containsGenericParameter {
            return specificType
        }
        
        // Generate global type declaration if not already generated
        if !generatedLayouts.contains(layoutName) {
            generatedLayouts.insert(layoutName)
            
            // Create canonical members for the C struct definition
            var canonicalMembers: [(name: String, type: Type, mutable: Bool)] = []
            var typeSubstitution: [String: Type] = [:]
            for (i, paramInfo) in template.typeParameters.enumerated() {
                typeSubstitution[paramInfo.name] = args[i].canonical
            }
            
            for param in template.parameters {
                let fieldType = try resolveTypeNode(param.type, substitution: typeSubstitution)
                canonicalMembers.append((name: param.name, type: fieldType, mutable: param.mutable))
            }
            
            // Create canonical type
            let canonicalType = Type.structure(
                name: layoutName, members: canonicalMembers, isGenericInstantiation: true)
            
            // Convert to TypedGlobalNode
            let params = canonicalMembers.map { param in
                Symbol(
                    name: param.name, type: param.type,
                    kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
            }
            
            let typeSymbol = Symbol(name: layoutName, type: canonicalType, kind: .type)
            generatedNodes.append(.globalStructDeclaration(identifier: typeSymbol, parameters: params))
        }
        
        return specificType
    }
    
    // MARK: - Union Instantiation
    
    /// Instantiates a generic union template with concrete type arguments.
    /// - Parameters:
    ///   - template: The generic union template
    ///   - args: The concrete type arguments
    /// - Returns: The instantiated concrete type
    private func instantiateUnion(template: GenericUnionTemplate, args: [Type]) throws -> Type {
        guard template.typeParameters.count == args.count else {
            throw SemanticError.typeMismatch(
                expected: "\(template.typeParameters.count) generic types", got: "\(args.count)")
        }
        
        // Enforce trait constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: args)
        
        // Check cache
        let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
        if let existing = instantiatedTypes[key] {
            return existing
        }
        
        // Calculate layout name
        let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
        let layoutName = "\(template.name)_\(argLayoutKeys)"
        
        // Create placeholder for recursion
        let placeholder = Type.union(
            name: layoutName, cases: [], isGenericInstantiation: true)
        instantiatedTypes[key] = placeholder
        
        // Resolve cases with concrete types
        var resolvedCases: [UnionCase] = []
        do {
            var typeSubstitution: [String: Type] = [:]
            for (i, paramInfo) in template.typeParameters.enumerated() {
                typeSubstitution[paramInfo.name] = args[i]
            }
            
            for c in template.cases {
                var params: [(name: String, type: Type)] = []
                for p in c.parameters {
                    let resolved = try resolveTypeNode(p.type, substitution: typeSubstitution)
                    if resolved == placeholder {
                        throw SemanticError.invalidOperation(
                            op: "Direct recursion in generic union \(layoutName) not allowed (use ref)",
                            type1: p.name, type2: "")
                    }
                    params.append((name: p.name, type: resolved))
                }
                resolvedCases.append(UnionCase(name: c.name, parameters: params))
            }
        } catch {
            instantiatedTypes.removeValue(forKey: key)
            throw error
        }
        
        // Create the concrete type
        let specificType = Type.union(
            name: layoutName,
            cases: resolvedCases,
            isGenericInstantiation: true
        )
        instantiatedTypes[key] = specificType
        layoutToTemplateInfo[layoutName] = (base: template.name, args: args)
        
        // Force instantiate __drop if it exists
        if let methods = input.genericTemplates.extensionMethods[template.name] {
            for entry in methods {
                if entry.method.name == "__drop" {
                    _ = try instantiateExtensionMethodFromEntry(
                        baseType: specificType,
                        structureName: template.name,
                        genericArgs: args,
                        methodInfo: entry
                    )
                }
            }
        }
        
        // Skip code generation if type still contains generic parameters
        if specificType.containsGenericParameter {
            return specificType
        }
        
        // Generate global declaration for CodeGen
        if !generatedLayouts.contains(layoutName) {
            generatedLayouts.insert(layoutName)
            
            // Canonical cases (using canonical types for fields)
            var canonicalCases: [UnionCase] = []
            var typeSubstitution: [String: Type] = [:]
            for (i, paramInfo) in template.typeParameters.enumerated() {
                typeSubstitution[paramInfo.name] = args[i].canonical
            }
            
            for c in template.cases {
                var params: [(name: String, type: Type)] = []
                for p in c.parameters {
                    params.append((name: p.name, type: try resolveTypeNode(p.type, substitution: typeSubstitution)))
                }
                canonicalCases.append(UnionCase(name: c.name, parameters: params))
            }
            
            let canonicalType = Type.union(
                name: layoutName, cases: canonicalCases, isGenericInstantiation: true)
            let typeSymbol = Symbol(name: layoutName, type: canonicalType, kind: .type)
            generatedNodes.append(
                .globalUnionDeclaration(identifier: typeSymbol, cases: canonicalCases))
        }
        
        return specificType
    }

    
    // MARK: - Function Instantiation
    
    /// Instantiates a generic function template with concrete type arguments.
    /// - Parameters:
    ///   - template: The generic function template
    ///   - args: The concrete type arguments
    /// - Returns: A tuple of (mangled name, function type)
    private func instantiateFunction(template: GenericFunctionTemplate, args: [Type]) throws -> (String, Type) {
        guard template.typeParameters.count == args.count else {
            throw SemanticError.typeMismatch(
                expected: "\(template.typeParameters.count) generic arguments",
                got: "\(args.count)"
            )
        }
        
        // Enforce trait constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: args)
        
        // Check cache
        let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
        if let cached = instantiatedFunctions[key] {
            return cached
        }
        
        // Create type substitution map
        var typeSubstitution: [String: Type] = [:]
        for (i, paramInfo) in template.typeParameters.enumerated() {
            typeSubstitution[paramInfo.name] = args[i]
        }
        
        // Resolve parameters and return type
        let resolvedReturnType = try resolveTypeNode(template.returnType, substitution: typeSubstitution)
        let resolvedParams = try template.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type, substitution: typeSubstitution)
            return Symbol(
                name: param.name, type: paramType,
                kind: .variable(param.mutable ? .MutableValue : .Value))
        }
        
        // Calculate mangled name
        let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
        let mangledName = "\(template.name)_\(argLayoutKeys)"
        
        // Create function type
        let functionType = Type.function(
            parameters: resolvedParams.map {
                Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: resolvedReturnType)
        
        // Skip code generation if function type still contains generic parameters
        if functionType.containsGenericParameter {
            return ("", functionType)
        }
        
        // Cache early to support recursion
        instantiatedFunctions[key] = (mangledName, functionType)
        
        // Type-check the body with substituted types
        // Note: In the current implementation, we use the pre-checked body from declaration-time
        // and substitute types. For full correctness, we would need to re-check with concrete types.
        let typedBody: TypedExpressionNode
        if let checkedBody = template.checkedBody {
            // Use the declaration-time checked body and substitute types
            typedBody = substituteTypesInExpression(checkedBody, substitution: typeSubstitution)
        } else {
            // Fallback: create a panic call (this shouldn't happen in normal operation)
            typedBody = .intrinsicCall(.panic(message: .stringLiteral(value: "unimplemented", type: builtinStringType())))
        }
        
        // Skip intrinsic functions
        let intrinsicNames = [
            "alloc_memory", "dealloc_memory", "copy_memory", "move_memory", "ref_count",
        ]
        
        // Generate global function if not already generated
        if !generatedLayouts.contains(mangledName) && !intrinsicNames.contains(template.name) {
            generatedLayouts.insert(mangledName)
            
            let functionNode = TypedGlobalNode.globalFunction(
                identifier: Symbol(name: mangledName, type: functionType, kind: .function),
                parameters: resolvedParams,
                body: typedBody
            )
            generatedNodes.append(functionNode)
        }
        
        return (mangledName, functionType)
    }
    
    // MARK: - Extension Method Instantiation
    
    /// Instantiates an extension method on a generic type.
    /// - Parameters:
    ///   - baseType: The concrete type on which the method is called
    ///   - templateName: The name of the generic type template
    ///   - typeArgs: The type arguments used to instantiate the base type
    ///   - methodName: The name of the method to instantiate
    /// - Returns: The symbol for the instantiated method
    private func instantiateExtensionMethod(
        baseType: Type,
        templateName: String,
        typeArgs: [Type],
        methodName: String
    ) throws -> Symbol {
        // Look up the method in the extension methods registry
        guard let methods = input.genericTemplates.extensionMethods[templateName] else {
            throw SemanticError.undefinedMember(methodName, templateName)
        }
        
        guard let methodInfo = methods.first(where: { $0.method.name == methodName }) else {
            throw SemanticError.undefinedMember(methodName, templateName)
        }
        
        return try instantiateExtensionMethodFromEntry(
            baseType: baseType,
            structureName: templateName,
            genericArgs: typeArgs,
            methodInfo: methodInfo
        )
    }
    
    /// Instantiates an extension method from a method entry.
    private func instantiateExtensionMethodFromEntry(
        baseType: Type,
        structureName: String,
        genericArgs: [Type],
        methodInfo: GenericExtensionMethodTemplate
    ) throws -> Symbol {
        let typeParams = methodInfo.typeParams
        let method = methodInfo.method
        
        if typeParams.count != genericArgs.count {
            throw SemanticError.typeMismatch(
                expected: "\(typeParams.count) args", got: "\(genericArgs.count)")
        }
        
        // Calculate mangled name
        let argLayoutKeys = genericArgs.map { $0.layoutKey }.joined(separator: "_")
        let mangledName = "\(structureName)_\(argLayoutKeys)_\(method.name)"
        let key = "ext:\(mangledName)"
        
        // Check cache
        if let (cachedName, cachedType) = instantiatedFunctions[key] {
            let kind = getCompilerMethodKind(method.name)
            return Symbol(name: cachedName, type: cachedType, kind: .function, methodKind: kind)
        }
        
        // Create type substitution map
        var typeSubstitution: [String: Type] = [:]
        for (i, paramInfo) in typeParams.enumerated() {
            typeSubstitution[paramInfo.name] = genericArgs[i]
        }
        // Also substitute Self with the base type
        typeSubstitution["Self"] = baseType
        
        // Resolve return type and parameters
        let returnType = try resolveTypeNode(method.returnType, substitution: typeSubstitution)
        let params = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type, substitution: typeSubstitution)
            return Symbol(
                name: param.name, type: paramType,
                kind: .variable(param.mutable ? .MutableValue : .Value))
        }
        
        // Create function type
        let functionType = Type.function(
            parameters: params.map {
                Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
        )
        
        // Skip code generation if function type still contains generic parameters
        if functionType.containsGenericParameter {
            let kind = getCompilerMethodKind(method.name)
            return Symbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
        }
        
        // Get the typed body from the TypeChecker's cache
        let typedBody: TypedExpressionNode
        if let cachedInfo = input.typedExtensionMethods[mangledName] {
            // Use the pre-checked body from the TypeChecker
            typedBody = cachedInfo.body
        } else if let checkedBody = methodInfo.checkedBody {
            // Use the declaration-time checked body and substitute types
            typedBody = substituteTypesInExpression(checkedBody, substitution: typeSubstitution)
        } else {
            // Fallback: create a placeholder body (this shouldn't happen in normal operation)
            typedBody = createPlaceholderBody(returnType: returnType)
        }
        
        // Generate global function if not already generated
        if !generatedLayouts.contains(mangledName) {
            generatedLayouts.insert(mangledName)
            let kind = getCompilerMethodKind(method.name)
            let functionNode = TypedGlobalNode.globalFunction(
                identifier: Symbol(
                    name: mangledName, type: functionType, kind: .function, methodKind: kind),
                parameters: params,
                body: typedBody
            )
            generatedNodes.append(functionNode)
        }
        
        instantiatedFunctions[key] = (mangledName, functionType)
        let kind = getCompilerMethodKind(method.name)
        return Symbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
    }
    
    /// Creates a placeholder body for methods that need re-checking.
    private func createPlaceholderBody(returnType: Type) -> TypedExpressionNode {
        switch returnType {
        case .void:
            return .blockExpression(statements: [], finalExpression: nil, type: .void)
        case .int:
            return .integerLiteral(value: 0, type: .int)
        case .bool:
            return .booleanLiteral(value: false, type: .bool)
        default:
            return .intrinsicCall(.panic(message: .stringLiteral(value: "unimplemented", type: builtinStringType())))
        }
    }

    
    // MARK: - Trait Constraint Validation
    
    /// Enforces trait constraints on type arguments.
    /// - Parameters:
    ///   - typeParameters: The type parameter declarations with constraints
    ///   - args: The concrete type arguments
    private func enforceGenericConstraints(typeParameters: [TypeParameterDecl], args: [Type]) throws {
        guard typeParameters.count == args.count else { return }
        
        for (i, param) in typeParameters.enumerated() {
            for constraint in param.constraints {
                let traitName = try resolveTraitName(from: constraint)
                
                // If the argument is a generic parameter, skip concrete conformance check
                // (it will be checked when fully instantiated)
                if case .genericParameter = args[i] {
                    continue
                }
                
                let ctx = "checking constraint \(param.name): \(traitName)"
                try enforceTraitConformance(args[i], traitName: traitName, context: ctx)
            }
        }
    }
    
    /// Enforces that a type conforms to a trait.
    /// - Parameters:
    ///   - selfType: The type to check
    ///   - traitName: The trait name
    ///   - context: Context for error messages
    private func enforceTraitConformance(
        _ selfType: Type,
        traitName: String,
        context: String? = nil
    ) throws {
        // Any trait is satisfied by all types
        if traitName == "Any" {
            return
        }
        
        // Validate trait exists
        try validateTraitName(traitName)
        
        // Get required methods from trait
        let required = try flattenedTraitMethods(traitName)
        
        var missing: [String] = []
        var mismatched: [String] = []
        
        for name in required.keys.sorted() {
            guard let sig = required[name] else { continue }
            let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: selfType)
            let expectedSig = try formatTraitMethodSignature(sig, selfType: selfType)
            
            guard let actualSym = try lookupConcreteMethodSymbol(on: selfType, name: sig.name) else {
                missing.append("missing method \(sig.name): expected \(expectedSig)")
                continue
            }
            if actualSym.type != expectedType {
                mismatched.append(
                    "method \(sig.name) has type \(actualSym.type), expected \(expectedType) (expected \(expectedSig))"
                )
            }
        }
        
        if !missing.isEmpty || !mismatched.isEmpty {
            var msg = "Type \(selfType) does not conform to trait \(traitName)"
            if let context {
                msg += " (\(context))"
            }
            if !missing.isEmpty {
                msg += "\n" + missing.joined(separator: "\n")
            }
            if !mismatched.isEmpty {
                msg += "\n" + mismatched.joined(separator: "\n")
            }
            throw SemanticError(.generic(msg), line: currentLine)
        }
    }
    
    /// Validates that a trait name is defined.
    private func validateTraitName(_ name: String) throws {
        try SemaUtils.validateTraitName(name, traits: input.genericTemplates.traits, currentLine: currentLine)
    }
    
    /// Returns all methods required by a trait, including inherited methods.
    private func flattenedTraitMethods(_ traitName: String) throws -> [String: TraitMethodSignature] {
        return try SemaUtils.flattenedTraitMethods(traitName, traits: input.genericTemplates.traits, currentLine: currentLine)
    }
    
    /// Computes the expected function type for a trait method.
    private func expectedFunctionTypeForTraitMethod(
        _ method: TraitMethodSignature,
        selfType: Type
    ) throws -> Type {
        let substitution: [String: Type] = ["Self": selfType]
        
        let params: [Parameter] = try method.parameters.map { param in
            let t = try resolveTypeNode(param.type, substitution: substitution)
            return Parameter(type: t, kind: .byVal)
        }
        let ret = try resolveTypeNode(method.returnType, substitution: substitution)
        return Type.function(parameters: params, returns: ret)
    }
    
    /// Formats a trait method signature for error messages.
    private func formatTraitMethodSignature(
        _ method: TraitMethodSignature,
        selfType: Type
    ) throws -> String {
        let substitution: [String: Type] = ["Self": selfType]
        
        let paramsDesc = try method.parameters.map { param -> String in
            let resolvedType = try resolveTypeNode(param.type, substitution: substitution)
            let mutPrefix = param.mutable ? "mut " : ""
            return "\(mutPrefix)\(param.name) \(resolvedType)"
        }.joined(separator: ", ")
        
        let ret = try resolveTypeNode(method.returnType, substitution: substitution)
        return "\(method.name)(\(paramsDesc)) \(ret)"
    }
    
    /// Checks if a type supports builtin equality comparison.
    private func isBuiltinEqualityComparable(_ type: Type) -> Bool {
        return SemaUtils.isBuiltinEqualityComparable(type)
    }
    
    /// Checks if a type supports builtin ordering comparison.
    private func isBuiltinOrderingComparable(_ type: Type) -> Bool {
        return SemaUtils.isBuiltinOrderingComparable(type)
    }
    
    /// Looks up a concrete method symbol on a type.
    private func lookupConcreteMethodSymbol(on selfType: Type, name: String) throws -> Symbol? {
        switch selfType {
        case .reference(let inner):
            // For reference types, look up the method on the inner type
            return try lookupConcreteMethodSymbol(on: inner, name: name)
            
        case .structure(let typeName, _, let isGen):
            if let methods = extensionMethods[typeName], let sym = methods[name] {
                return sym
            }
            if isGen, let info = layoutToTemplateInfo[typeName] {
                if let extensions = input.genericTemplates.extensionMethods[info.base],
                   let ext = extensions.first(where: { $0.method.name == name })
                {
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: info.args,
                        methodInfo: ext
                    )
                }
            }
            return nil
            
        case .union(let typeName, _, let isGen):
            if let methods = extensionMethods[typeName], let sym = methods[name] {
                return sym
            }
            if isGen, let info = layoutToTemplateInfo[typeName] {
                if let extensions = input.genericTemplates.extensionMethods[info.base],
                   let ext = extensions.first(where: { $0.method.name == name })
                {
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: info.args,
                        methodInfo: ext
                    )
                }
            }
            return nil
            
        case .pointer(let element):
            // Check intrinsic extension methods first
            if let extensions = input.genericTemplates.intrinsicExtensionMethods["Pointer"],
               let ext = extensions.first(where: { $0.method.name == name })
            {
                return try instantiateIntrinsicExtensionMethod(
                    baseType: selfType,
                    structureName: "Pointer",
                    genericArgs: [element],
                    methodInfo: ext
                )
            }
            
            // Then check regular extension methods
            if let extensions = input.genericTemplates.extensionMethods["Pointer"],
               let ext = extensions.first(where: { $0.method.name == name })
            {
                return try instantiateExtensionMethodFromEntry(
                    baseType: selfType,
                    structureName: "Pointer",
                    genericArgs: [element],
                    methodInfo: ext
                )
            }
            return nil
            
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64,
             .bool:
            let typeName = selfType.description
            if let methods = extensionMethods[typeName], let sym = methods[name] {
                return sym
            }
            // Check intrinsic extension methods for primitive types
            if let extensions = input.genericTemplates.intrinsicExtensionMethods[typeName],
               let ext = extensions.first(where: { $0.method.name == name })
            {
                return try instantiateIntrinsicExtensionMethod(
                    baseType: selfType,
                    structureName: typeName,
                    genericArgs: [],
                    methodInfo: ext
                )
            }
            return nil
            
        default:
            return nil
        }
    }
    
    /// Instantiates an intrinsic extension method.
    private func instantiateIntrinsicExtensionMethod(
        baseType: Type,
        structureName: String,
        genericArgs: [Type],
        methodInfo: (typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)
    ) throws -> Symbol {
        let (typeParams, method) = methodInfo
        
        if typeParams.count != genericArgs.count {
            throw SemanticError.typeMismatch(
                expected: "\(typeParams.count) args", got: "\(genericArgs.count)")
        }
        
        let argLayoutKeys = genericArgs.map { $0.layoutKey }.joined(separator: "_")
        let mangledName = "\(structureName)_\(argLayoutKeys)_\(method.name)"
        let key = "ext:\(mangledName)"
        
        if let (cachedName, cachedType) = instantiatedFunctions[key] {
            let kind = getCompilerMethodKind(method.name)
            return Symbol(name: cachedName, type: cachedType, kind: .function, methodKind: kind)
        }
        
        // Create type substitution
        var typeSubstitution: [String: Type] = [:]
        for (i, paramInfo) in typeParams.enumerated() {
            typeSubstitution[paramInfo.name] = genericArgs[i]
        }
        typeSubstitution["Self"] = baseType
        
        let returnType = try resolveTypeNode(method.returnType, substitution: typeSubstitution)
        let params = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type, substitution: typeSubstitution)
            return Symbol(
                name: param.name, type: paramType,
                kind: .variable(param.mutable ? .MutableValue : .Value))
        }
        
        let funcType = Type.function(
            parameters: params.map {
                Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
        )
        
        instantiatedFunctions[key] = (mangledName, funcType)
        let kind = getCompilerMethodKind(method.name)
        return Symbol(name: mangledName, type: funcType, kind: .function, methodKind: kind)
    }

    
    // MARK: - Type Resolution Helpers
    
    /// Resolves a TypeNode to a concrete Type using the given substitution map.
    /// - Parameters:
    ///   - node: The type node to resolve
    ///   - substitution: Map from type parameter names to concrete types
    /// - Returns: The resolved concrete type
    private func resolveTypeNode(_ node: TypeNode, substitution: [String: Type]) throws -> Type {
        switch node {
        case .identifier(let name):
            // Check substitution map first
            if let substituted = substitution[name] {
                return substituted
            }
            // Then check built-in types
            return resolveBuiltinType(name) ?? .genericParameter(name: name)
            
        case .reference(let inner):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return .reference(inner: innerType)
            
        case .generic(let base, let args):
            // Special case: Pointer<T>
            if base == "Pointer" && args.count == 1 {
                let elementType = try resolveTypeNode(args[0], substitution: substitution)
                return .pointer(element: elementType)
            }
            
            // Look up generic template
            let resolvedArgs = try args.map { try resolveTypeNode($0, substitution: substitution) }
            
            // Check if it's a struct template
            if let template = input.genericTemplates.structTemplates[base] {
                // Directly instantiate - no need to add to pendingRequests since we're handling it now
                // The instantiateStruct method has its own caching to avoid duplicate work
                return try instantiateStruct(template: template, args: resolvedArgs)
            }
            
            // Check if it's a union template
            if let template = input.genericTemplates.unionTemplates[base] {
                // Directly instantiate - no need to add to pendingRequests since we're handling it now
                return try instantiateUnion(template: template, args: resolvedArgs)
            }
            
            throw SemanticError(.generic("Unknown generic type: \(base)"), line: currentLine)
            
        case .inferredSelf:
            if let selfType = substitution["Self"] {
                return selfType
            }
            throw SemanticError(.generic("Self type not available in this context"), line: currentLine)
        }
    }
    
    /// Resolves a built-in type name to its Type.
    private func resolveBuiltinType(_ name: String) -> Type? {
        return SemaUtils.resolveBuiltinType(name)
    }
    
    // Wrapper for shared utility function from SemaUtils.swift
    private func getCompilerMethodKind(_ name: String) -> CompilerMethodKind {
        return SemaUtils.getCompilerMethodKind(name)
    }
    
    // Wrapper for shared utility function from SemaUtils.swift
    private func resolveTraitName(from node: TypeNode) throws -> String {
        return try SemaUtils.resolveTraitName(from: node)
    }
    
    /// Returns the built-in String type.
    private func builtinStringType() -> Type {
        return .structure(name: "String", members: [], isGenericInstantiation: false)
    }
    
    // MARK: - Type Substitution in Expressions
    
    /// Substitutes type parameters in a typed expression with concrete types.
    /// - Parameters:
    ///   - expr: The expression to transform
    ///   - substitution: Map from type parameter names to concrete types
    /// - Returns: The expression with substituted types
    private func substituteTypesInExpression(
        _ expr: TypedExpressionNode,
        substitution: [String: Type]
    ) -> TypedExpressionNode {
        switch expr {
        case .integerLiteral(let value, let type):
            return .integerLiteral(value: value, type: substituteType(type, substitution: substitution))
            
        case .floatLiteral(let value, let type):
            return .floatLiteral(value: value, type: substituteType(type, substitution: substitution))
            
        case .stringLiteral(let value, let type):
            return .stringLiteral(value: value, type: substituteType(type, substitution: substitution))
            
        case .booleanLiteral(let value, let type):
            return .booleanLiteral(value: value, type: substituteType(type, substitution: substitution))
            
        case .castExpression(let expression, let type):
            return .castExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .arithmeticExpression(let left, let op, let right, let type):
            return .arithmeticExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .comparisonExpression(let left, let op, let right, let type):
            return .comparisonExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .letExpression(let identifier, let value, let body, let type):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: substituteType(identifier.type, substitution: substitution),
                kind: identifier.kind,
                methodKind: identifier.methodKind
            )
            return .letExpression(
                identifier: newIdentifier,
                value: substituteTypesInExpression(value, substitution: substitution),
                body: substituteTypesInExpression(body, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .andExpression(let left, let right, let type):
            return .andExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .orExpression(let left, let right, let type):
            return .orExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .notExpression(let expression, let type):
            return .notExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .bitwiseExpression(let left, let op, let right, let type):
            return .bitwiseExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .bitwiseNotExpression(let expression, let type):
            return .bitwiseNotExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .derefExpression(let expression, let type):
            return .derefExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .referenceExpression(let expression, let type):
            return .referenceExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .variable(let identifier):
            var newName = identifier.name
            let newType = substituteType(identifier.type, substitution: substitution)
            
            // Check if this is a generic function that needs its name updated to the mangled name
            let isFunction: Bool
            if case .function = identifier.kind {
                isFunction = true
            } else {
                isFunction = false
            }
            
            if isFunction,
               case .function(_, _) = identifier.type,
               !substitution.isEmpty {
                // Check if this is a generic function template
                if let template = input.genericTemplates.functionTemplates[identifier.name] {
                    // Calculate the mangled name using the substituted type arguments
                    let typeArgs = template.typeParameters.compactMap { param -> Type? in
                        substitution[param.name]
                    }
                    if typeArgs.count == template.typeParameters.count {
                        let argLayoutKeys = typeArgs.map { $0.layoutKey }.joined(separator: "_")
                        newName = "\(identifier.name)_\(argLayoutKeys)"
                        
                        // Ensure the function is instantiated
                        if !generatedLayouts.contains(newName) && !typeArgs.contains(where: { $0.containsGenericParameter }) {
                            pendingRequests.append(InstantiationRequest(
                                kind: .function(template: template, args: typeArgs),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            }
            
            let newIdentifier = Symbol(
                name: newName,
                type: newType,
                kind: identifier.kind,
                methodKind: identifier.methodKind
            )
            return .variable(identifier: newIdentifier)
            
        case .blockExpression(let statements, let finalExpression, let type):
            let newStatements = statements.map { substituteTypesInStatement($0, substitution: substitution) }
            let newFinal = finalExpression.map { substituteTypesInExpression($0, substitution: substitution) }
            return .blockExpression(
                statements: newStatements,
                finalExpression: newFinal,
                type: substituteType(type, substitution: substitution)
            )
            
        case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
            return .ifExpression(
                condition: substituteTypesInExpression(condition, substitution: substitution),
                thenBranch: substituteTypesInExpression(thenBranch, substitution: substitution),
                elseBranch: elseBranch.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )
            
        case .call(let callee, let arguments, let type):
            let newCallee = substituteTypesInExpression(callee, substitution: substitution)
            let newArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            let newType = substituteType(type, substitution: substitution)
            
            // Apply lowering for primitive type methods (__equals, __compare)
            // This mirrors the lowering done in TypeChecker for direct calls
            if case .methodReference(let base, let method, _) = newCallee {
                // Lower primitive `__equals(self ref, other ref) Bool` to scalar equality
                if method.methodKind == .equals,
                   newType == .bool,
                   newArguments.count == 1,
                   case .reference(let lhsInner) = base.type,
                   case .reference(let rhsInner) = newArguments[0].type,
                   lhsInner == rhsInner,
                   isBuiltinEqualityComparable(lhsInner)
                {
                    let lhsVal: TypedExpressionNode = .derefExpression(expression: base, type: lhsInner)
                    let rhsVal: TypedExpressionNode = .derefExpression(expression: newArguments[0], type: rhsInner)
                    return .comparisonExpression(left: lhsVal, op: .equal, right: rhsVal, type: .bool)
                }
                
                // Lower primitive `__compare(self ref, other ref) Int` to scalar comparisons
                if method.methodKind == .compare,
                   newType == .int,
                   newArguments.count == 1,
                   case .reference(let lhsInner) = base.type,
                   case .reference(let rhsInner) = newArguments[0].type,
                   lhsInner == rhsInner,
                   isBuiltinOrderingComparable(lhsInner)
                {
                    let lhsVal: TypedExpressionNode = .derefExpression(expression: base, type: lhsInner)
                    let rhsVal: TypedExpressionNode = .derefExpression(expression: newArguments[0], type: rhsInner)
                    
                    let less: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .less, right: rhsVal, type: .bool)
                    let greater: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .greater, right: rhsVal, type: .bool)
                    let minusOne: TypedExpressionNode = .integerLiteral(value: -1, type: .int)
                    let plusOne: TypedExpressionNode = .integerLiteral(value: 1, type: .int)
                    let zero: TypedExpressionNode = .integerLiteral(value: 0, type: .int)
                    
                    let gtBranch: TypedExpressionNode = .ifExpression(condition: greater, thenBranch: plusOne, elseBranch: zero, type: .int)
                    return .ifExpression(condition: less, thenBranch: minusOne, elseBranch: gtBranch, type: .int)
                }
            }
            
            return .call(callee: newCallee, arguments: newArguments, type: newType)
            
        case .methodReference(let base, let method, let type):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            var newMethod = Symbol(
                name: method.name,
                type: substituteType(method.type, substitution: substitution),
                kind: method.kind,
                methodKind: method.methodKind
            )
            
            // Resolve trait method placeholders to concrete methods
            // Placeholder names have the format "__trait_TraitName_methodName"
            // where methodName may start with underscores (e.g., "__equals")
            if method.name.hasPrefix("__trait_") && !newBase.type.containsGenericParameter {
                // Extract the method name from the placeholder
                // Format: "__trait_TraitName_methodName"
                let prefix = "__trait_"
                let remainder = String(method.name.dropFirst(prefix.count))
                // Find the first underscore that separates trait name from method name
                // The trait name doesn't contain underscores, so we find the first underscore
                if let underscoreIndex = remainder.firstIndex(of: "_") {
                    let methodName = String(remainder[remainder.index(after: underscoreIndex)...])
                    
                    // Look up the concrete method on the substituted base type
                    if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName) {
                        newMethod = Symbol(
                            name: concreteMethod.name,
                            type: concreteMethod.type,
                            kind: concreteMethod.kind,
                            methodKind: concreteMethod.methodKind
                        )
                    }
                }
            }
            
            return .methodReference(
                base: newBase,
                method: newMethod,
                type: substituteType(type, substitution: substitution)
            )
            
        case .whileExpression(let condition, let body, let type):
            return .whileExpression(
                condition: substituteTypesInExpression(condition, substitution: substitution),
                body: substituteTypesInExpression(body, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .typeConstruction(let identifier, let arguments, let type):
            let substitutedType = substituteType(identifier.type, substitution: substitution)
            
            // If the substituted type is a concrete structure or union, we need to:
            // 1. Update the identifier name to match the concrete type's layout name
            // 2. Ensure the concrete type is instantiated
            var newName = identifier.name
            if case .structure(let layoutName, _, let isGenericInstantiation) = substitutedType {
                newName = layoutName
                // Trigger instantiation of the concrete type if needed
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !substitutedType.containsGenericParameter {
                    // Find the template and instantiate
                    // Extract base name from the layout name (e.g., "Pair_I_I" -> "Pair")
                    let baseName = layoutName.split(separator: "_").first.map(String.init) ?? layoutName
                    if let template = input.genericTemplates.structTemplates[baseName] {
                        // Extract type args from the substituted type's members
                        // We need to reconstruct the type args from the layout name
                        // For now, we'll add a pending request with the substituted type
                        // The instantiateStruct method will handle the actual instantiation
                        
                        // Parse the layout name to extract type args
                        // Layout name format: "BaseName_Arg1_Arg2_..."
                        let suffix = String(layoutName.dropFirst(baseName.count + 1)) // Remove "BaseName_"
                        let argLayoutKeys = suffix.split(separator: "_").map(String.init)
                        
                        // Try to reconstruct the type args from the layout keys
                        // This is a heuristic - we look for types that match the layout keys
                        var typeArgs: [Type] = []
                        for key in argLayoutKeys {
                            if let builtinType = resolveBuiltinType(key) {
                                typeArgs.append(builtinType)
                            } else if key == "I" {
                                typeArgs.append(.int)
                            } else if key == "R" {
                                typeArgs.append(.reference(inner: .int)) // Heuristic
                            } else if key.hasPrefix("Struct_") {
                                // Nested struct - need to look up
                                typeArgs.append(.structure(name: key, members: [], isGenericInstantiation: true))
                            } else {
                                // Unknown type - use the substituted type's info
                                break
                            }
                        }
                        
                        // If we couldn't reconstruct the type args, try to use the substitution map
                        if typeArgs.count != template.typeParameters.count {
                            typeArgs = template.typeParameters.compactMap { param in
                                substitution[param.name]
                            }
                        }
                        
                        if typeArgs.count == template.typeParameters.count {
                            pendingRequests.append(InstantiationRequest(
                                kind: .structType(template: template, args: typeArgs),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            } else if case .union(let layoutName, _, let isGenericInstantiation) = substitutedType {
                newName = layoutName
                // Similar logic for unions
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !substitutedType.containsGenericParameter {
                    let baseName = layoutName.split(separator: "_").first.map(String.init) ?? layoutName
                    if let template = input.genericTemplates.unionTemplates[baseName] {
                        let typeArgs: [Type] = template.typeParameters.compactMap { param in
                            substitution[param.name]
                        }
                        
                        if typeArgs.count == template.typeParameters.count {
                            pendingRequests.append(InstantiationRequest(
                                kind: .unionType(template: template, args: typeArgs),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            }
            
            let newIdentifier = Symbol(
                name: newName,
                type: substitutedType,
                kind: identifier.kind,
                methodKind: identifier.methodKind
            )
            return .typeConstruction(
                identifier: newIdentifier,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )
            
        case .memberPath(let source, let path):
            let newPath = path.map { sym in
                Symbol(
                    name: sym.name,
                    type: substituteType(sym.type, substitution: substitution),
                    kind: sym.kind,
                    methodKind: sym.methodKind
                )
            }
            return .memberPath(
                source: substituteTypesInExpression(source, substitution: substitution),
                path: newPath
            )
            
        case .subscriptExpression(let base, let arguments, let method, let type):
            let newMethod = Symbol(
                name: method.name,
                type: substituteType(method.type, substitution: substitution),
                kind: method.kind,
                methodKind: method.methodKind
            )
            return .subscriptExpression(
                base: substituteTypesInExpression(base, substitution: substitution),
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) },
                method: newMethod,
                type: substituteType(type, substitution: substitution)
            )
            
        case .unionConstruction(let type, let caseName, let arguments):
            return .unionConstruction(
                type: substituteType(type, substitution: substitution),
                caseName: caseName,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            )
            
        case .intrinsicCall(let intrinsic):
            return .intrinsicCall(substituteTypesInIntrinsic(intrinsic, substitution: substitution))
            
        case .matchExpression(let subject, let cases, let type):
            let newCases = cases.map { matchCase in
                TypedMatchCase(
                    pattern: substituteTypesInPattern(matchCase.pattern, substitution: substitution),
                    body: substituteTypesInExpression(matchCase.body, substitution: substitution)
                )
            }
            return .matchExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                cases: newCases,
                type: substituteType(type, substitution: substitution)
            )
        }
    }
    
    /// Substitutes types in a statement.
    private func substituteTypesInStatement(
        _ stmt: TypedStatementNode,
        substitution: [String: Type]
    ) -> TypedStatementNode {
        switch stmt {
        case .variableDeclaration(let identifier, let value, let mutable):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: substituteType(identifier.type, substitution: substitution),
                kind: identifier.kind,
                methodKind: identifier.methodKind
            )
            return .variableDeclaration(
                identifier: newIdentifier,
                value: substituteTypesInExpression(value, substitution: substitution),
                mutable: mutable
            )
            
        case .assignment(let target, let value):
            return .assignment(
                target: substituteTypesInExpression(target, substitution: substitution),
                value: substituteTypesInExpression(value, substitution: substitution)
            )
            
        case .compoundAssignment(let target, let op, let value):
            return .compoundAssignment(
                target: substituteTypesInExpression(target, substitution: substitution),
                operator: op,
                value: substituteTypesInExpression(value, substitution: substitution)
            )
            
        case .expression(let expr):
            return .expression(substituteTypesInExpression(expr, substitution: substitution))
            
        case .return(let value):
            return .return(value: value.map { substituteTypesInExpression($0, substitution: substitution) })
            
        case .break:
            return .break
            
        case .continue:
            return .continue
        }
    }
    
    /// Substitutes types in a pattern.
    private func substituteTypesInPattern(
        _ pattern: TypedPattern,
        substitution: [String: Type]
    ) -> TypedPattern {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
            return pattern
            
        case .variable(let symbol):
            let newSymbol = Symbol(
                name: symbol.name,
                type: substituteType(symbol.type, substitution: substitution),
                kind: symbol.kind,
                methodKind: symbol.methodKind
            )
            return .variable(symbol: newSymbol)
            
        case .unionCase(let caseName, let tagIndex, let elements):
            return .unionCase(
                caseName: caseName,
                tagIndex: tagIndex,
                elements: elements.map { substituteTypesInPattern($0, substitution: substitution) }
            )
        }
    }
    
    /// Substitutes types in an intrinsic call.
    private func substituteTypesInIntrinsic(
        _ intrinsic: TypedIntrinsic,
        substitution: [String: Type]
    ) -> TypedIntrinsic {
        switch intrinsic {
        case .allocMemory(let count, let resultType):
            return .allocMemory(
                count: substituteTypesInExpression(count, substitution: substitution),
                resultType: substituteType(resultType, substitution: substitution)
            )
            
        case .deallocMemory(let ptr):
            return .deallocMemory(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .copyMemory(let dest, let source, let count):
            return .copyMemory(
                dest: substituteTypesInExpression(dest, substitution: substitution),
                source: substituteTypesInExpression(source, substitution: substitution),
                count: substituteTypesInExpression(count, substitution: substitution)
            )
            
        case .moveMemory(let dest, let source, let count):
            return .moveMemory(
                dest: substituteTypesInExpression(dest, substitution: substitution),
                source: substituteTypesInExpression(source, substitution: substitution),
                count: substituteTypesInExpression(count, substitution: substitution)
            )
            
        case .refCount(let val):
            return .refCount(val: substituteTypesInExpression(val, substitution: substitution))
            
        case .ptrInit(let ptr, let val):
            return .ptrInit(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                val: substituteTypesInExpression(val, substitution: substitution)
            )
            
        case .ptrDeinit(let ptr):
            return .ptrDeinit(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .ptrPeek(let ptr):
            return .ptrPeek(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .ptrOffset(let ptr, let offset):
            return .ptrOffset(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                offset: substituteTypesInExpression(offset, substitution: substitution)
            )
            
        case .ptrTake(let ptr):
            return .ptrTake(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .ptrReplace(let ptr, let val):
            return .ptrReplace(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                val: substituteTypesInExpression(val, substitution: substitution)
            )
            
        case .float32Bits(let value):
            return .float32Bits(value: substituteTypesInExpression(value, substitution: substitution))
            
        case .float64Bits(let value):
            return .float64Bits(value: substituteTypesInExpression(value, substitution: substitution))
            
        case .printString(let message):
            return .printString(message: substituteTypesInExpression(message, substitution: substitution))
            
        case .printInt(let value):
            return .printInt(value: substituteTypesInExpression(value, substitution: substitution))
            
        case .printBool(let value):
            return .printBool(value: substituteTypesInExpression(value, substitution: substitution))
            
        case .panic(let message):
            return .panic(message: substituteTypesInExpression(message, substitution: substitution))
            
        case .exit(let code):
            return .exit(code: substituteTypesInExpression(code, substitution: substitution))
            
        case .abort:
            return .abort
        }
    }
    
    /// Substitutes type parameters in a type.
    private func substituteType(_ type: Type, substitution: [String: Type]) -> Type {
        return SemaUtils.substituteType(type, substitution: substitution)
    }
    
    // MARK: - Dependency Ordering
    
    /// Sorts generated nodes by dependency order for correct C compilation.
    /// Types must be declared before they are used.
    private func sortByDependencyOrder(_ nodes: [TypedGlobalNode]) -> [TypedGlobalNode] {
        // For now, we rely on the order in which nodes are generated.
        // A full implementation would perform topological sorting based on type dependencies.
        // The current TypeChecker already handles this by generating dependencies before
        // the declarations that use them.
        return nodes
    }
}

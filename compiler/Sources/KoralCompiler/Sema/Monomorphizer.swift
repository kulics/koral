// Monomorphizer.swift
// Implements the monomorphization phase that processes instantiation requests
// and generates concrete types and functions from generic templates.

import Foundation

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
    private var processedRequestKeys: Set<InstantiationKey> = []
    
    // MARK: - Recursion Detection
    
    /// Types currently being instantiated (for recursion detection)
    private var instantiatingTypes: Set<String> = []
    
    /// Functions currently being instantiated (for recursion detection)
    private var instantiatingFunctions: Set<String> = []
    
    /// Current recursion depth for instantiation
    private var currentRecursionDepth: Int = 0
    
    /// Maximum allowed recursion depth to prevent infinite loops
    private let maxRecursionDepth: Int = 100
    
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
                    if case .structure(let decl) = identifier.type,
                       decl.isGenericInstantiation {
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
                    if case .union(let decl) = identifier.type,
                       decl.isGenericInstantiation {
                        instantiatedTypes[identifier.name] = identifier.type
                    }
                    resultNodes.append(node)
                case .globalFunction(let identifier, _, _):
                    // Track already-generated functions
                    generatedLayouts.insert(identifier.name)
                    // Cache the function type
                    instantiatedFunctions[identifier.name] = (identifier.name, identifier.type)
                    resultNodes.append(node)
                case .givenDeclaration(let type, let methods):
                    // Track already-generated extension methods
                    // Calculate the type name for mangling
                    let typeName: String
                    switch type {
                    case .structure(let decl):
                        typeName = decl.name
                    case .union(let decl):
                        typeName = decl.name
                    default:
                        typeName = type.description
                    }
                    
                    for method in methods {
                        // Calculate mangled name (TypeName_MethodName)
                        let mangledName = "\(typeName)_\(method.identifier.name)"
                        generatedLayouts.insert(mangledName)
                        instantiatedFunctions[mangledName] = (mangledName, method.identifier.type)
                    }
                    resultNodes.append(node)
                default:
                    resultNodes.append(node)
                }
            }
        }
        
        // Initialize pending requests with all collected instantiation requests
        pendingRequests = Array(input.instantiationRequests)
        
        // Process all instantiation requests (including transitive ones)
        while !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            try processRequest(request)
        }
        
        // Resolve genericStruct/genericUnion types in all result nodes
        // This ensures no parameterized types reach CodeGen
        var resolvedResultNodes: [TypedGlobalNode] = []
        for node in resultNodes {
            let resolvedNode = try resolveTypesInGlobalNode(node)
            resolvedResultNodes.append(resolvedNode)
        }
        
        // Also resolve types in generated nodes (they may contain nested generic types)
        var resolvedGeneratedNodes: [TypedGlobalNode] = []
        for node in generatedNodes {
            let resolvedNode = try resolveTypesInGlobalNode(node)
            resolvedGeneratedNodes.append(resolvedNode)
        }
        
        // Insert generated nodes before the result nodes (for C definition order)
        // Types and functions must be declared before they are used
        return MonomorphizedProgram(globalNodes: resolvedGeneratedNodes + resolvedResultNodes)
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
        
        // Check recursion depth
        guard currentRecursionDepth < maxRecursionDepth else {
            throw SemanticError(.generic("Maximum instantiation depth exceeded (possible infinite recursion)"), line: currentLine)
        }
        
        // Generate a key for this request to avoid duplicate processing
        let key = request.deduplicationKey
        guard !processedRequestKeys.contains(key) else {
            return
        }
        processedRequestKeys.insert(key)
        
        currentRecursionDepth += 1
        defer { currentRecursionDepth -= 1 }
        
        do {
            switch request.kind {
            case .structType(let template, let args):
                _ = try instantiateStruct(template: template, args: args)
                
            case .unionType(let template, let args):
                _ = try instantiateUnion(template: template, args: args)
                
            case .function(let template, let args):
                _ = try instantiateFunction(template: template, args: args)
                
            case .extensionMethod(let baseType, let template, let typeArgs, let methodTypeArgs):
                _ = try instantiateExtensionMethod(
                    baseType: baseType,
                    template: template,
                    typeArgs: typeArgs,
                    methodTypeArgs: methodTypeArgs
                )
            }
        } catch let e as SemanticError {
            throw e
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
        
        // Note: Trait constraints were already validated by TypeChecker at declaration time
        
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
        let placeholderDecl = StructDecl(
            name: layoutName,
            modulePath: [],
            sourceFile: "",
            access: .default,
            members: [],
            isGenericInstantiation: true
        )
        let placeholder = Type.structure(decl: placeholderDecl)
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
        let specificDecl = StructDecl(
            name: layoutName,
            modulePath: [],
            sourceFile: "",
            access: .default,
            members: resolvedMembers,
            isGenericInstantiation: true
        )
        let specificType = Type.structure(decl: specificDecl)
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
                        methodTypeArgs: [],
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
            let canonicalDecl = StructDecl(
                name: layoutName,
                modulePath: [],
                sourceFile: "",
                access: .default,
                members: canonicalMembers,
                isGenericInstantiation: true
            )
            let canonicalType = Type.structure(decl: canonicalDecl)
            
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
        
        // Note: Trait constraints were already validated by TypeChecker at declaration time
        
        // Check cache
        let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
        if let existing = instantiatedTypes[key] {
            return existing
        }
        
        // Calculate layout name
        let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
        let layoutName = "\(template.name)_\(argLayoutKeys)"
        
        // Create placeholder for recursion
        let placeholderDecl = UnionDecl(
            name: layoutName,
            modulePath: [],
            sourceFile: "",
            access: .default,
            cases: [],
            isGenericInstantiation: true
        )
        let placeholder = Type.union(decl: placeholderDecl)
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
        let specificDecl = UnionDecl(
            name: layoutName,
            modulePath: [],
            sourceFile: "",
            access: .default,
            cases: resolvedCases,
            isGenericInstantiation: true
        )
        let specificType = Type.union(decl: specificDecl)
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
                        methodTypeArgs: [],
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
            
            let canonicalDecl = UnionDecl(
                name: layoutName,
                modulePath: [],
                sourceFile: "",
                access: .default,
                cases: canonicalCases,
                isGenericInstantiation: true
            )
            let canonicalType = Type.union(decl: canonicalDecl)
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
        
        // Note: Trait constraints were already validated by TypeChecker at declaration time
        
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
            // Fallback: use abort (this shouldn't happen in normal operation)
            typedBody = .intrinsicCall(.abort)
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
    ///   - template: The generic extension method template to instantiate
    ///   - typeArgs: The type arguments used to instantiate the base type
    ///   - methodTypeArgs: The type arguments for method-level generic parameters
    /// - Returns: The symbol for the instantiated method
    private func instantiateExtensionMethod(
        baseType: Type,
        template: GenericExtensionMethodTemplate,
        typeArgs: [Type],
        methodTypeArgs: [Type]
    ) throws -> Symbol {
        // Resolve the base type if it's a parameterized type
        let resolvedBaseType = resolveParameterizedType(baseType)
        
        // Derive the structure name from the base type
        let structureName: String
        switch resolvedBaseType {
        case .structure(let decl):
            // Extract base name from mangled name (e.g., "List_I" -> "List")
            structureName = decl.name.split(separator: "_").first.map(String.init) ?? decl.name
        case .genericStruct(let templateName, _):
            structureName = templateName
        case .genericUnion(let templateName, _):
            structureName = templateName
        case .union(let decl):
            structureName = decl.name.split(separator: "_").first.map(String.init) ?? decl.name
        case .pointer(_):
            structureName = "Pointer"
        default:
            structureName = resolvedBaseType.description
        }
        
        return try instantiateExtensionMethodFromEntry(
            baseType: resolvedBaseType,
            structureName: structureName,
            genericArgs: typeArgs,
            methodTypeArgs: methodTypeArgs,
            methodInfo: template
        )
    }
    
    /// Instantiates an extension method from a method entry.
    private func instantiateExtensionMethodFromEntry(
        baseType: Type,
        structureName: String,
        genericArgs: [Type],
        methodTypeArgs: [Type],
        methodInfo: GenericExtensionMethodTemplate
    ) throws -> Symbol {
        let typeParams = methodInfo.typeParams
        let methodTypeParams = methodInfo.method.typeParameters
        let method = methodInfo.method
        
        if typeParams.count != genericArgs.count {
            throw SemanticError.typeMismatch(
                expected: "\(typeParams.count) args", got: "\(genericArgs.count)")
        }
        
        if methodTypeParams.count != methodTypeArgs.count {
            throw SemanticError.typeMismatch(
                expected: "\(methodTypeParams.count) method type args", got: "\(methodTypeArgs.count)")
        }
        
        // Calculate mangled name (include method type args if present)
        let argLayoutKeys = genericArgs.map { $0.layoutKey }.joined(separator: "_")
        let methodArgLayoutKeys = methodTypeArgs.map { $0.layoutKey }.joined(separator: "_")
        let mangledName: String
        if methodTypeArgs.isEmpty {
            mangledName = "\(structureName)_\(argLayoutKeys)_\(method.name)"
        } else {
            mangledName = "\(structureName)_\(argLayoutKeys)_\(method.name)_\(methodArgLayoutKeys)"
        }
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
        // Add method-level type parameter substitutions
        for (i, paramInfo) in methodTypeParams.enumerated() {
            typeSubstitution[paramInfo.name] = methodTypeArgs[i]
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
        
        // IMPORTANT: Cache the function BEFORE processing the body to prevent infinite recursion
        // This allows recursive methods (like rehash calling insert, insert calling rehash) to work
        instantiatedFunctions[key] = (mangledName, functionType)
        
        // Get the typed body from the declaration-time checked body
        let typedBody: TypedExpressionNode
        if let checkedBody = methodInfo.checkedBody {
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
        
        let kind = getCompilerMethodKind(method.name)
        return Symbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
    }
    
    /// Creates a placeholder body for methods that need re-checking.
    private func createPlaceholderBody(returnType: Type) -> TypedExpressionNode {
        switch returnType {
        case .void:
            return .blockExpression(statements: [], finalExpression: nil, type: .void)
        case .int:
            return .integerLiteral(value: "0", type: .int)
        case .bool:
            return .booleanLiteral(value: false, type: .bool)
        default:
            // Use abort as fallback (this shouldn't happen in normal operation)
            return .intrinsicCall(.abort)
        }
    }

    
    // MARK: - Helper Methods
    
    /// Extracts the method name from a mangled name (e.g., "Float32_to_bits" -> "to_bits")
    private func extractMethodName(_ mangledName: String) -> String {
        if mangledName.hasPrefix("Float32_") {
            return String(mangledName.dropFirst("Float32_".count))
        } else if mangledName.hasPrefix("Float64_") {
            return String(mangledName.dropFirst("Float64_".count))
        } else if let idx = mangledName.lastIndex(of: "_") {
            return String(mangledName[mangledName.index(after: idx)...])
        }
        return mangledName
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
    private func lookupConcreteMethodSymbol(on selfType: Type, name: String, methodTypeArgs: [Type] = []) throws -> Symbol? {
        switch selfType {
        case .reference(let inner):
            // For reference types, look up the method on the inner type
            return try lookupConcreteMethodSymbol(on: inner, name: name, methodTypeArgs: methodTypeArgs)
            
        case .structure(let decl):
            let typeName = decl.name
            let isGen = decl.isGenericInstantiation
            if let methods = extensionMethods[typeName], let sym = methods[name] {
                // Generate mangled name for the method (include method type args if present)
                let methodArgLayoutKeys = methodTypeArgs.map { $0.layoutKey }.joined(separator: "_")
                let mangledName = methodTypeArgs.isEmpty ? "\(typeName)_\(name)" : "\(typeName)_\(name)_\(methodArgLayoutKeys)"
                return Symbol(
                    name: mangledName,
                    type: sym.type,
                    kind: sym.kind,
                    methodKind: sym.methodKind
                )
            }
            if isGen, let info = layoutToTemplateInfo[typeName] {
                if let extensions = input.genericTemplates.extensionMethods[info.base],
                   let ext = extensions.first(where: { $0.method.name == name })
                {
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: info.args,
                        methodTypeArgs: methodTypeArgs,
                        methodInfo: ext
                    )
                }
            }
            return nil
            
        case .union(let decl):
            let typeName = decl.name
            let isGen = decl.isGenericInstantiation
            if let methods = extensionMethods[typeName], let sym = methods[name] {
                // Generate mangled name for the method (include method type args if present)
                let methodArgLayoutKeys = methodTypeArgs.map { $0.layoutKey }.joined(separator: "_")
                let mangledName = methodTypeArgs.isEmpty ? "\(typeName)_\(name)" : "\(typeName)_\(name)_\(methodArgLayoutKeys)"
                return Symbol(
                    name: mangledName,
                    type: sym.type,
                    kind: sym.kind,
                    methodKind: sym.methodKind
                )
            }
            if isGen, let info = layoutToTemplateInfo[typeName] {
                if let extensions = input.genericTemplates.extensionMethods[info.base],
                   let ext = extensions.first(where: { $0.method.name == name })
                {
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: info.args,
                        methodTypeArgs: methodTypeArgs,
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
                    methodTypeArgs: methodTypeArgs,
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
                // Generate mangled name for the method
                let mangledName = "\(typeName)_\(name)"
                return Symbol(
                    name: mangledName,
                    type: sym.type,
                    kind: sym.kind,
                    methodKind: sym.methodKind
                )
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
            if let builtinType = resolveBuiltinType(name) {
                return builtinType
            }
            // Check if it's a known concrete struct type
            if let concreteType = input.genericTemplates.concreteStructTypes[name] {
                return concreteType
            }
            // Check if it's a known concrete union type
            if let concreteType = input.genericTemplates.concreteUnionTypes[name] {
                return concreteType
            }
            // Check if it's a known struct template (non-generic reference)
            if let template = input.genericTemplates.structTemplates[name] {
                // Non-generic struct reference
                if template.typeParameters.isEmpty {
                    let decl = StructDecl(
                        name: name,
                        modulePath: [],
                        sourceFile: "",
                        access: .default,
                        members: [],
                        isGenericInstantiation: false
                    )
                    return .structure(decl: decl)
                }
            }
            // Check if it's a known union template (non-generic reference)
            if let template = input.genericTemplates.unionTemplates[name] {
                // Non-generic union reference
                if template.typeParameters.isEmpty {
                    let decl = UnionDecl(
                        name: name,
                        modulePath: [],
                        sourceFile: "",
                        access: .default,
                        cases: [],
                        isGenericInstantiation: false
                    )
                    return .union(decl: decl)
                }
            }
            // Otherwise treat as generic parameter
            return .genericParameter(name: name)
            
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
            
        case .functionType(let paramTypes, let returnType):
            // Resolve function type: [ParamType1, ParamType2, ..., ReturnType]Func
            let resolvedParamTypes = try paramTypes.map { try resolveTypeNode($0, substitution: substitution) }
            let resolvedReturnType = try resolveTypeNode(returnType, substitution: substitution)
            let parameters = resolvedParamTypes.map { Parameter(type: $0, kind: .byVal) }
            return .function(parameters: parameters, returns: resolvedReturnType)
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
        let decl = StructDecl(
            name: "String",
            modulePath: [],
            sourceFile: "",
            access: .default,
            members: [],
            isGenericInstantiation: false
        )
        return .structure(decl: decl)
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
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
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
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
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
            
        case .ifPatternExpression(let subject, let pattern, let bindings, let thenBranch, let elseBranch, let type):
            let newBindings = bindings.map { (name, mutable, bindType) in
                (name, mutable, substituteType(bindType, substitution: substitution))
            }
            return .ifPatternExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                bindings: newBindings,
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
            if case .methodReference(let base, let method, _, _, _) = newCallee {
                // Intercept Float32/Float64 to_bits intrinsic method
                let methodName = extractMethodName(method.name)
                if methodName == "to_bits" {
                    if base.type == .float32 && newArguments.isEmpty {
                        return .intrinsicCall(.float32Bits(value: base))
                    } else if base.type == .float64 && newArguments.isEmpty {
                        return .intrinsicCall(.float64Bits(value: base))
                    }
                }
                
                // Lower primitive `__equals(self, other) Bool` to scalar equality
                if method.methodKind == .equals,
                   newType == .bool,
                   newArguments.count == 1,
                   base.type == newArguments[0].type,
                   isBuiltinEqualityComparable(base.type)
                {
                    return .comparisonExpression(left: base, op: .equal, right: newArguments[0], type: .bool)
                }
                
                // Lower primitive `__compare(self, other) Int` to scalar comparisons
                if method.methodKind == .compare,
                   newType == .int,
                   newArguments.count == 1,
                   base.type == newArguments[0].type,
                   isBuiltinOrderingComparable(base.type)
                {
                    let lhsVal = base
                    let rhsVal = newArguments[0]
                    
                    let less: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .less, right: rhsVal, type: .bool)
                    let greater: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .greater, right: rhsVal, type: .bool)
                    let minusOne: TypedExpressionNode = .integerLiteral(value: "-1", type: .int)
                    let plusOne: TypedExpressionNode = .integerLiteral(value: "1", type: .int)
                    let zero: TypedExpressionNode = .integerLiteral(value: "0", type: .int)
                    
                    let gtBranch: TypedExpressionNode = .ifExpression(condition: greater, thenBranch: plusOne, elseBranch: zero, type: .int)
                    return .ifExpression(condition: less, thenBranch: minusOne, elseBranch: gtBranch, type: .int)
                }
            }
            
            return .call(callee: newCallee, arguments: newArguments, type: newType)
        
        case .genericCall(let functionName, let typeArgs, let arguments, let type):
            // Substitute type arguments
            let substitutedTypeArgs = typeArgs.map { substituteType($0, substitution: substitution) }
            // Substitute arguments
            let newArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            // Substitute return type
            let newType = substituteType(type, substitution: substitution)
            
            // If type args still contain generic parameters, keep as genericCall
            if substitutedTypeArgs.contains(where: { $0.containsGenericParameter }) {
                return .genericCall(
                    functionName: functionName,
                    typeArgs: substitutedTypeArgs,
                    arguments: newArguments,
                    type: newType
                )
            }
            
            // Convert to regular call by instantiating the function
            if let template = input.genericTemplates.functionTemplates[functionName] {
                // Ensure the function is instantiated
                let key = InstantiationKey.function(templateName: functionName, args: substitutedTypeArgs)
                if !processedRequestKeys.contains(key) {
                    pendingRequests.append(InstantiationRequest(
                        kind: .function(template: template, args: substitutedTypeArgs),
                        sourceLine: currentLine,
                        sourceFileName: currentFileName
                    ))
                }
                
                // Calculate the mangled name
                let argLayoutKeys = substitutedTypeArgs.map { $0.layoutKey }.joined(separator: "_")
                let mangledName = "\(functionName)_\(argLayoutKeys)"
                
                // Create the callee as a variable reference to the mangled function
                let functionType = Type.function(
                    parameters: newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                let callee: TypedExpressionNode = .variable(
                    identifier: Symbol(name: mangledName, type: functionType, kind: .function)
                )
                
                return .call(callee: callee, arguments: newArguments, type: newType)
            }
            
            // Fallback: keep as genericCall
            return .genericCall(
                functionName: functionName,
                typeArgs: substitutedTypeArgs,
                arguments: newArguments,
                type: newType
            )
            
        case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, let type):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            var newMethod = Symbol(
                name: method.name,
                type: substituteType(method.type, substitution: substitution),
                kind: method.kind,
                methodKind: method.methodKind,
                modulePath: method.modulePath,
                sourceFile: method.sourceFile,
                access: method.access
            )
            
            // Substitute type args if present
            let substitutedTypeArgs = typeArgs?.map { substituteType($0, substitution: substitution) }
            
            // Substitute method type args if present
            let substitutedMethodTypeArgs = methodTypeArgs?.map { substituteType($0, substitution: substitution) }
            
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
                    // Pass methodTypeArgs for generic methods
                    if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: substitutedMethodTypeArgs ?? []) {
                        newMethod = Symbol(
                            name: concreteMethod.name,
                            type: concreteMethod.type,
                            kind: concreteMethod.kind,
                            methodKind: concreteMethod.methodKind,
                            modulePath: concreteMethod.modulePath,
                            sourceFile: concreteMethod.sourceFile,
                            access: concreteMethod.access
                        )
                    }
                }
            }
            // Resolve generic extension method to mangled name
            else if !newBase.type.containsGenericParameter {
                // Look up the concrete method on the substituted base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: method.name) {
                    newMethod = Symbol(
                        name: concreteMethod.name,
                        type: concreteMethod.type,
                        kind: concreteMethod.kind,
                        methodKind: concreteMethod.methodKind,
                        modulePath: concreteMethod.modulePath,
                        sourceFile: concreteMethod.sourceFile,
                        access: concreteMethod.access
                    )
                }
            }
            
            return .methodReference(
                base: newBase,
                method: newMethod,
                typeArgs: substitutedTypeArgs,
                methodTypeArgs: substitutedMethodTypeArgs,
                type: substituteType(type, substitution: substitution)
            )
            
        case .whileExpression(let condition, let body, let type):
            return .whileExpression(
                condition: substituteTypesInExpression(condition, substitution: substitution),
                body: substituteTypesInExpression(body, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .whilePatternExpression(let subject, let pattern, let bindings, let body, let type):
            let newBindings = bindings.map { (name, mutable, bindType) in
                (name, mutable, substituteType(bindType, substitution: substitution))
            }
            return .whilePatternExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                bindings: newBindings,
                body: substituteTypesInExpression(body, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .typeConstruction(let identifier, let typeArgs, let arguments, let type):
            let substitutedType = substituteType(identifier.type, substitution: substitution)
            
            // If the substituted type is a concrete structure or union, we need to:
            // 1. Update the identifier name to match the concrete type's layout name
            // 2. Ensure the concrete type is instantiated
            var newName = identifier.name
            if case .structure(let decl) = substitutedType {
                let layoutName = decl.name
                let isGenericInstantiation = decl.isGenericInstantiation
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
                        var typeArgsReconstructed: [Type] = []
                        for key in argLayoutKeys {
                            if let builtinType = resolveBuiltinType(key) {
                                typeArgsReconstructed.append(builtinType)
                            } else if key == "I" {
                                typeArgsReconstructed.append(.int)
                            } else if key == "R" {
                                typeArgsReconstructed.append(.reference(inner: .int)) // Heuristic
                            } else if key.hasPrefix("Struct_") {
                                // Nested struct - need to look up
                                let nestedDecl = StructDecl(
                                    name: key,
                                    modulePath: [],
                                    sourceFile: "",
                                    access: .default,
                                    members: [],
                                    isGenericInstantiation: true
                                )
                                typeArgsReconstructed.append(.structure(decl: nestedDecl))
                            } else {
                                // Unknown type - use the substituted type's info
                                break
                            }
                        }
                        
                        // If we couldn't reconstruct the type args, try to use the substitution map
                        if typeArgsReconstructed.count != template.typeParameters.count {
                            typeArgsReconstructed = template.typeParameters.compactMap { param in
                                substitution[param.name]
                            }
                        }
                        
                        if typeArgsReconstructed.count == template.typeParameters.count {
                            pendingRequests.append(InstantiationRequest(
                                kind: .structType(template: template, args: typeArgsReconstructed),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            } else if case .union(let decl) = substitutedType {
                let layoutName = decl.name
                let isGenericInstantiation = decl.isGenericInstantiation
                newName = layoutName
                // Similar logic for unions
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !substitutedType.containsGenericParameter {
                    let baseName = layoutName.split(separator: "_").first.map(String.init) ?? layoutName
                    if let template = input.genericTemplates.unionTemplates[baseName] {
                        let typeArgsReconstructed: [Type] = template.typeParameters.compactMap { param in
                            substitution[param.name]
                        }
                        
                        if typeArgsReconstructed.count == template.typeParameters.count {
                            pendingRequests.append(InstantiationRequest(
                                kind: .unionType(template: template, args: typeArgsReconstructed),
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
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            // Substitute type args if present
            let substitutedTypeArgs = typeArgs?.map { substituteType($0, substitution: substitution) }
            return .typeConstruction(
                identifier: newIdentifier,
                typeArgs: substitutedTypeArgs,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )
            
        case .memberPath(let source, let path):
            let newPath = path.map { sym in
                Symbol(
                    name: sym.name,
                    type: substituteType(sym.type, substitution: substitution),
                    kind: sym.kind,
                    methodKind: sym.methodKind,
                    modulePath: sym.modulePath,
                    sourceFile: sym.sourceFile,
                    access: sym.access
                )
            }
            return .memberPath(
                source: substituteTypesInExpression(source, substitution: substitution),
                path: newPath
            )
            
        case .subscriptExpression(let base, let arguments, let method, let type):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            var newMethod = Symbol(
                name: method.name,
                type: substituteType(method.type, substitution: substitution),
                kind: method.kind,
                methodKind: method.methodKind,
                modulePath: method.modulePath,
                sourceFile: method.sourceFile,
                access: method.access
            )
            
            // Resolve method name to mangled name for generic extension methods
            if !newBase.type.containsGenericParameter {
                // Look up the concrete method on the substituted base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: method.name) {
                    newMethod = Symbol(
                        name: concreteMethod.name,
                        type: concreteMethod.type,
                        kind: concreteMethod.kind,
                        methodKind: concreteMethod.methodKind,
                        modulePath: concreteMethod.modulePath,
                        sourceFile: concreteMethod.sourceFile,
                        access: concreteMethod.access
                    )
                }
            }
            
            return .subscriptExpression(
                base: newBase,
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
            
        case .staticMethodCall(let baseType, let methodName, let typeArgs, let arguments, let type):
            // Substitute types in the static method call
            let substitutedBaseType = substituteType(baseType, substitution: substitution)
            let substitutedTypeArgs = typeArgs.map { substituteType($0, substitution: substitution) }
            let substitutedArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            let substitutedReturnType = substituteType(type, substitution: substitution)
            
            return .staticMethodCall(
                baseType: substitutedBaseType,
                methodName: methodName,
                typeArgs: substitutedTypeArgs,
                arguments: substitutedArguments,
                type: substitutedReturnType
            )
            
        case .lambdaExpression(let parameters, let captures, let body, let type):
            // Substitute types in lambda parameters
            let newParameters = parameters.map { param in
                Symbol(
                    name: param.name,
                    type: substituteType(param.type, substitution: substitution),
                    kind: param.kind,
                    methodKind: param.methodKind,
                    modulePath: param.modulePath,
                    sourceFile: param.sourceFile,
                    access: param.access
                )
            }
            // Substitute types in captures
            let newCaptures = captures.map { capture in
                CapturedVariable(
                    symbol: Symbol(
                        name: capture.symbol.name,
                        type: substituteType(capture.symbol.type, substitution: substitution),
                        kind: capture.symbol.kind,
                        methodKind: capture.symbol.methodKind,
                        modulePath: capture.symbol.modulePath,
                        sourceFile: capture.symbol.sourceFile,
                        access: capture.symbol.access
                    ),
                    captureKind: capture.captureKind
                )
            }
            return .lambdaExpression(
                parameters: newParameters,
                captures: newCaptures,
                body: substituteTypesInExpression(body, substitution: substitution),
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
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
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
                methodKind: symbol.methodKind,
                modulePath: symbol.modulePath,
                sourceFile: symbol.sourceFile,
                access: symbol.access
            )
            return .variable(symbol: newSymbol)
            
        case .unionCase(let caseName, let tagIndex, let elements):
            return .unionCase(
                caseName: caseName,
                tagIndex: tagIndex,
                elements: elements.map { substituteTypesInPattern($0, substitution: substitution) }
            )
            
        case .comparisonPattern:
            // Comparison patterns don't contain types to substitute
            return pattern
            
        case .andPattern(let left, let right):
            return .andPattern(
                left: substituteTypesInPattern(left, substitution: substitution),
                right: substituteTypesInPattern(right, substitution: substitution)
            )
            
        case .orPattern(let left, let right):
            return .orPattern(
                left: substituteTypesInPattern(left, substitution: substitution),
                right: substituteTypesInPattern(right, substitution: substitution)
            )
            
        case .notPattern(let inner):
            return .notPattern(pattern: substituteTypesInPattern(inner, substitution: substitution))
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

        case .float32FromBits(let bits):
            return .float32FromBits(bits: substituteTypesInExpression(bits, substitution: substitution))
            
        case .float64FromBits(let bits):
            return .float64FromBits(bits: substituteTypesInExpression(bits, substitution: substitution))
            
        case .exit(let code):
            return .exit(code: substituteTypesInExpression(code, substitution: substitution))
            
        case .abort:
            return .abort

        // Low-level IO intrinsics (minimal set using file descriptors)
        case .fwrite(let ptr, let len, let fd):
            return .fwrite(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                len: substituteTypesInExpression(len, substitution: substitution),
                fd: substituteTypesInExpression(fd, substitution: substitution)
            )
            
        case .fgetc(let fd):
            return .fgetc(fd: substituteTypesInExpression(fd, substitution: substitution))
            
        case .fflush(let fd):
            return .fflush(fd: substituteTypesInExpression(fd, substitution: substitution))
            
        case .ptrBits:
            return .ptrBits
        }
    }
    
    /// Substitutes type parameters in a type.
    /// This method extends SemaUtils.substituteType to also resolve genericStruct/genericUnion
    /// to concrete structure/union types by instantiating them.
    private func substituteType(_ type: Type, substitution: [String: Type]) -> Type {
        // First, apply the basic substitution
        let substituted = SemaUtils.substituteType(type, substitution: substitution)
        
        // Then, resolve genericStruct/genericUnion to concrete types
        return resolveParameterizedType(substituted, visited: [])
    }
    
    /// Resolves a parameterized type (genericStruct/genericUnion) to a concrete type.
    /// If the type still contains generic parameters, returns it unchanged.
    /// - Parameter type: The type to resolve
    /// - Parameter visited: Set of visited type declaration UUIDs to prevent infinite recursion
    /// - Returns: The resolved concrete type, or the original type if it can't be resolved yet
    private func resolveParameterizedType(_ type: Type, visited: Set<UUID> = []) -> Type {
        switch type {
        case .genericStruct(let template, let args):
            // First, recursively resolve the type arguments
            let resolvedArgs = args.map { resolveParameterizedType($0) }
            
            // If any arg still contains generic parameters, we can't resolve yet
            if resolvedArgs.contains(where: { $0.containsGenericParameter }) {
                return .genericStruct(template: template, args: resolvedArgs)
            }
            
            // Check if we already have this type cached FIRST
            let cacheKey = "\(template)<\(resolvedArgs.map { $0.description }.joined(separator: ","))>"
            if let cached = instantiatedTypes[cacheKey] {
                return cached
            }
            
            // Look up the struct template and instantiate directly
            if let structTemplate = input.genericTemplates.structTemplates[template] {
                // Directly instantiate the struct type
                do {
                    return try instantiateStruct(template: structTemplate, args: resolvedArgs)
                } catch {
                    // If instantiation fails, return a placeholder
                    let argLayoutKeys = resolvedArgs.map { $0.layoutKey }.joined(separator: "_")
                    let layoutName = "\(template)_\(argLayoutKeys)"
                    let decl = StructDecl(
                        name: layoutName,
                        modulePath: [],
                        sourceFile: "",
                        access: .default,
                        members: [],
                        isGenericInstantiation: true
                    )
                    return .structure(decl: decl)
                }
            }
            
            // Special case: Pointer<T> maps directly to .pointer(element: T)
            if template == "Pointer" && resolvedArgs.count == 1 {
                return .pointer(element: resolvedArgs[0])
            }
            
            return .genericStruct(template: template, args: resolvedArgs)
            
        case .genericUnion(let template, let args):
            // First, recursively resolve the type arguments
            let resolvedArgs = args.map { resolveParameterizedType($0) }
            
            // If any arg still contains generic parameters, we can't resolve yet
            if resolvedArgs.contains(where: { $0.containsGenericParameter }) {
                return .genericUnion(template: template, args: resolvedArgs)
            }
            
            // Check if we already have this type cached FIRST
            let cacheKey = "\(template)<\(resolvedArgs.map { $0.description }.joined(separator: ","))>"
            if let cached = instantiatedTypes[cacheKey] {
                return cached
            }
            
            // Look up the union template and instantiate directly
            if let unionTemplate = input.genericTemplates.unionTemplates[template] {
                // Directly instantiate the union type
                do {
                    return try instantiateUnion(template: unionTemplate, args: resolvedArgs)
                } catch {
                    // If instantiation fails, return a placeholder
                    let argLayoutKeys = resolvedArgs.map { $0.layoutKey }.joined(separator: "_")
                    let layoutName = "\(template)_\(argLayoutKeys)"
                    let decl = UnionDecl(
                        name: layoutName,
                        modulePath: [],
                        sourceFile: "",
                        access: .default,
                        cases: [],
                        isGenericInstantiation: true
                    )
                    return .union(decl: decl)
                }
            }
            
            return .genericUnion(template: template, args: resolvedArgs)
            
        case .reference(let inner):
            return .reference(inner: resolveParameterizedType(inner))
            
        case .pointer(let element):
            return .pointer(element: resolveParameterizedType(element))
            
        case .function(let params, let returns):
            let newParams = params.map { param in
                Parameter(
                    type: resolveParameterizedType(param.type),
                    kind: param.kind
                )
            }
            return .function(
                parameters: newParams,
                returns: resolveParameterizedType(returns)
            )
            
        case .structure(let decl):
            // Check for infinite recursion using UUID
            if visited.contains(decl.id) {
                return type
            }
            var newVisited = visited
            newVisited.insert(decl.id)
            
            let newMembers = decl.members.map { member in
                (
                    name: member.name,
                    type: resolveParameterizedType(member.type, visited: newVisited),
                    mutable: member.mutable
                )
            }
            
            // Only create a new type if members actually changed
            let membersChanged = zip(decl.members, newMembers).contains { old, new in
                old.type != new.type
            }
            if !membersChanged {
                return type
            }
            
            let newDecl = StructDecl(
                name: decl.name,
                modulePath: decl.modulePath,
                sourceFile: decl.sourceFile,
                access: decl.access,
                members: newMembers,
                isGenericInstantiation: decl.isGenericInstantiation,
                typeArguments: decl.typeArguments
            )
            return .structure(decl: newDecl)
            
        case .union(let decl):
            // Check for infinite recursion using UUID
            if visited.contains(decl.id) {
                return type
            }
            var newVisited = visited
            newVisited.insert(decl.id)
            
            let newCases = decl.cases.map { unionCase in
                UnionCase(
                    name: unionCase.name,
                    parameters: unionCase.parameters.map { param in
                        (name: param.name, type: resolveParameterizedType(param.type, visited: newVisited))
                    }
                )
            }
            
            // Only create a new type if cases actually changed
            let casesChanged = zip(decl.cases, newCases).contains { old, new in
                zip(old.parameters, new.parameters).contains { oldParam, newParam in
                    oldParam.type != newParam.type
                }
            }
            if !casesChanged {
                return type
            }
            
            let newDecl = UnionDecl(
                name: decl.name,
                modulePath: decl.modulePath,
                sourceFile: decl.sourceFile,
                access: decl.access,
                cases: newCases,
                isGenericInstantiation: decl.isGenericInstantiation,
                typeArguments: decl.typeArguments
            )
            return .union(decl: newDecl)
            
        default:
            return type
        }
    }
    
    // MARK: - Global Node Type Resolution
    
    /// Resolves all genericStruct/genericUnion types in a global node.
    /// This ensures no parameterized types reach CodeGen.
    private func resolveTypesInGlobalNode(_ node: TypedGlobalNode) throws -> TypedGlobalNode {
        switch node {
        case .globalStructDeclaration(let identifier, let parameters):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: resolveParameterizedType(identifier.type),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            let newParams = parameters.map { param in
                Symbol(
                    name: param.name,
                    type: resolveParameterizedType(param.type),
                    kind: param.kind,
                    methodKind: param.methodKind,
                    modulePath: param.modulePath,
                    sourceFile: param.sourceFile,
                    access: param.access
                )
            }
            return .globalStructDeclaration(identifier: newIdentifier, parameters: newParams)
            
        case .globalUnionDeclaration(let identifier, let cases):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: resolveParameterizedType(identifier.type),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            let newCases = cases.map { unionCase in
                UnionCase(
                    name: unionCase.name,
                    parameters: unionCase.parameters.map { param in
                        (name: param.name, type: resolveParameterizedType(param.type))
                    }
                )
            }
            return .globalUnionDeclaration(identifier: newIdentifier, cases: newCases)
            
        case .globalFunction(let identifier, let parameters, let body):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: resolveParameterizedType(identifier.type),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            let newParams = parameters.map { param in
                Symbol(
                    name: param.name,
                    type: resolveParameterizedType(param.type),
                    kind: param.kind,
                    methodKind: param.methodKind,
                    modulePath: param.modulePath,
                    sourceFile: param.sourceFile,
                    access: param.access
                )
            }
            let newBody = resolveTypesInExpression(body)
            return .globalFunction(identifier: newIdentifier, parameters: newParams, body: newBody)
            
        case .givenDeclaration(let type, let methods):
            // Resolve the type to get the concrete type name
            let resolvedType = resolveParameterizedType(type)
            let typeName: String
            switch resolvedType {
            case .structure(let decl):
                typeName = decl.name
            case .union(let decl):
                typeName = decl.name
            default:
                typeName = resolvedType.description
            }
            
            let newMethods = methods.map { method -> TypedMethodDeclaration in
                // Generate mangled name for the method
                let mangledName = "\(typeName)_\(method.identifier.name)"
                
                return TypedMethodDeclaration(
                    identifier: Symbol(
                        name: mangledName,
                        type: resolveParameterizedType(method.identifier.type),
                        kind: method.identifier.kind,
                        methodKind: method.identifier.methodKind,
                        modulePath: method.identifier.modulePath,
                        sourceFile: method.identifier.sourceFile,
                        access: method.identifier.access
                    ),
                    parameters: method.parameters.map { param in
                        Symbol(
                            name: param.name,
                            type: resolveParameterizedType(param.type),
                            kind: param.kind,
                            methodKind: param.methodKind,
                            modulePath: param.modulePath,
                            sourceFile: param.sourceFile,
                            access: param.access
                        )
                    },
                    body: resolveTypesInExpression(method.body),
                    returnType: resolveParameterizedType(method.returnType)
                )
            }
            return .givenDeclaration(type: resolvedType, methods: newMethods)
            
        case .globalVariable(let identifier, let value, let kind):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: resolveParameterizedType(identifier.type),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            
            return .globalVariable(identifier: newIdentifier, value: resolveTypesInExpression(value), kind: kind)
            
        case .genericTypeTemplate, .genericFunctionTemplate:
            // Templates should not reach this point
            return node
        }
    }
    
    /// Resolves all genericStruct/genericUnion types in an expression.
    private func resolveTypesInExpression(_ expr: TypedExpressionNode) -> TypedExpressionNode {
        switch expr {
        case .integerLiteral(let value, let type):
            return .integerLiteral(value: value, type: resolveParameterizedType(type))
            
        case .floatLiteral(let value, let type):
            return .floatLiteral(value: value, type: resolveParameterizedType(type))
            
        case .stringLiteral(let value, let type):
            return .stringLiteral(value: value, type: resolveParameterizedType(type))
            
        case .booleanLiteral(let value, let type):
            return .booleanLiteral(value: value, type: resolveParameterizedType(type))
            
        case .castExpression(let expression, let type):
            return .castExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .arithmeticExpression(let left, let op, let right, let type):
            return .arithmeticExpression(
                left: resolveTypesInExpression(left),
                op: op,
                right: resolveTypesInExpression(right),
                type: resolveParameterizedType(type)
            )
            
        case .comparisonExpression(let left, let op, let right, let type):
            return .comparisonExpression(
                left: resolveTypesInExpression(left),
                op: op,
                right: resolveTypesInExpression(right),
                type: resolveParameterizedType(type)
            )
            
        case .letExpression(let identifier, let value, let body, let type):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: resolveParameterizedType(identifier.type),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            return .letExpression(
                identifier: newIdentifier,
                value: resolveTypesInExpression(value),
                body: resolveTypesInExpression(body),
                type: resolveParameterizedType(type)
            )
            
        case .andExpression(let left, let right, let type):
            return .andExpression(
                left: resolveTypesInExpression(left),
                right: resolveTypesInExpression(right),
                type: resolveParameterizedType(type)
            )
            
        case .orExpression(let left, let right, let type):
            return .orExpression(
                left: resolveTypesInExpression(left),
                right: resolveTypesInExpression(right),
                type: resolveParameterizedType(type)
            )
            
        case .notExpression(let expression, let type):
            return .notExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .bitwiseExpression(let left, let op, let right, let type):
            return .bitwiseExpression(
                left: resolveTypesInExpression(left),
                op: op,
                right: resolveTypesInExpression(right),
                type: resolveParameterizedType(type)
            )
            
        case .bitwiseNotExpression(let expression, let type):
            return .bitwiseNotExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .derefExpression(let expression, let type):
            return .derefExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .referenceExpression(let expression, let type):
            return .referenceExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .variable(let identifier):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: resolveParameterizedType(identifier.type),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            return .variable(identifier: newIdentifier)
            
        case .blockExpression(let statements, let finalExpression, let type):
            let newStatements = statements.map { resolveTypesInStatement($0) }
            let newFinal = finalExpression.map { resolveTypesInExpression($0) }
            return .blockExpression(
                statements: newStatements,
                finalExpression: newFinal,
                type: resolveParameterizedType(type)
            )
            
        case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
            return .ifExpression(
                condition: resolveTypesInExpression(condition),
                thenBranch: resolveTypesInExpression(thenBranch),
                elseBranch: elseBranch.map { resolveTypesInExpression($0) },
                type: resolveParameterizedType(type)
            )
            
        case .ifPatternExpression(let subject, let pattern, let bindings, let thenBranch, let elseBranch, let type):
            let newBindings = bindings.map { (name, mutable, bindType) in
                (name, mutable, resolveParameterizedType(bindType))
            }
            return .ifPatternExpression(
                subject: resolveTypesInExpression(subject),
                pattern: resolveTypesInPattern(pattern),
                bindings: newBindings,
                thenBranch: resolveTypesInExpression(thenBranch),
                elseBranch: elseBranch.map { resolveTypesInExpression($0) },
                type: resolveParameterizedType(type)
            )
            
        case .call(let callee, let arguments, let type):
            let newCallee = resolveTypesInExpression(callee)
            let newArguments = arguments.map { resolveTypesInExpression($0) }
            let newType = resolveParameterizedType(type)
            
            // Intercept Float32/Float64 to_bits intrinsic method
            if case .methodReference(let base, let method, _, _, _) = newCallee {
                let methodName = extractMethodName(method.name)
                if methodName == "to_bits" {
                    if base.type == .float32 && newArguments.isEmpty {
                        return .intrinsicCall(.float32Bits(value: base))
                    } else if base.type == .float64 && newArguments.isEmpty {
                        return .intrinsicCall(.float64Bits(value: base))
                    }
                }
            }
            
            return .call(
                callee: newCallee,
                arguments: newArguments,
                type: newType
            )
            
        case .genericCall(let functionName, let typeArgs, let arguments, let type):
            // Resolve type args and convert to regular call
            let resolvedTypeArgs = typeArgs.map { resolveParameterizedType($0) }
            let newArguments = arguments.map { resolveTypesInExpression($0) }
            let newType = resolveParameterizedType(type)
            
            // If type args still contain generic parameters, keep as genericCall
            if resolvedTypeArgs.contains(where: { $0.containsGenericParameter }) {
                return .genericCall(
                    functionName: functionName,
                    typeArgs: resolvedTypeArgs,
                    arguments: newArguments,
                    type: newType
                )
            }
            
            // Look up the function template and instantiate
            if let template = input.genericTemplates.functionTemplates[functionName] {
                // Ensure the function is instantiated
                let key = InstantiationKey.function(templateName: functionName, args: resolvedTypeArgs)
                if !processedRequestKeys.contains(key) {
                    pendingRequests.append(InstantiationRequest(
                        kind: .function(template: template, args: resolvedTypeArgs),
                        sourceLine: currentLine,
                        sourceFileName: currentFileName
                    ))
                }
                
                // Calculate the mangled name
                let argLayoutKeys = resolvedTypeArgs.map { $0.layoutKey }.joined(separator: "_")
                let mangledName = "\(functionName)_\(argLayoutKeys)"
                
                // Create the callee as a variable reference to the mangled function
                let functionType = Type.function(
                    parameters: newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                let callee: TypedExpressionNode = .variable(
                    identifier: Symbol(name: mangledName, type: functionType, kind: .function)
                )
                
                return .call(callee: callee, arguments: newArguments, type: newType)
            }
            
            // Fallback: keep as genericCall (shouldn't happen in normal operation)
            return .genericCall(
                functionName: functionName,
                typeArgs: resolvedTypeArgs,
                arguments: newArguments,
                type: newType
            )
            
        case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, let type):
            let newBase = resolveTypesInExpression(base)
            var newMethod = Symbol(
                name: method.name,
                type: resolveParameterizedType(method.type),
                kind: method.kind,
                methodKind: method.methodKind,
                modulePath: method.modulePath,
                sourceFile: method.sourceFile,
                access: method.access
            )
            let resolvedTypeArgs = typeArgs?.map { resolveParameterizedType($0) }
            let resolvedMethodTypeArgs = methodTypeArgs?.map { resolveParameterizedType($0) }
            
            // Resolve method name to mangled name for generic extension methods
            if !newBase.type.containsGenericParameter {
                // Look up the concrete method on the resolved base type
                // Pass method type args for generic methods
                let methodTypeArgsToPass = resolvedMethodTypeArgs ?? []
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: method.name, methodTypeArgs: methodTypeArgsToPass) {
                    // Resolve any parameterized types in the method type
                    let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                    newMethod = Symbol(
                        name: concreteMethod.name,
                        type: resolvedMethodType,
                        kind: concreteMethod.kind,
                        methodKind: concreteMethod.methodKind,
                        modulePath: concreteMethod.modulePath,
                        sourceFile: concreteMethod.sourceFile,
                        access: concreteMethod.access
                    )
                }
            }
            
            return .methodReference(
                base: newBase,
                method: newMethod,
                typeArgs: resolvedTypeArgs,
                methodTypeArgs: resolvedMethodTypeArgs,
                type: resolveParameterizedType(type)
            )
            
        case .whileExpression(let condition, let body, let type):
            return .whileExpression(
                condition: resolveTypesInExpression(condition),
                body: resolveTypesInExpression(body),
                type: resolveParameterizedType(type)
            )
            
        case .whilePatternExpression(let subject, let pattern, let bindings, let body, let type):
            let newBindings = bindings.map { (name, mutable, bindType) in
                (name, mutable, resolveParameterizedType(bindType))
            }
            return .whilePatternExpression(
                subject: resolveTypesInExpression(subject),
                pattern: resolveTypesInPattern(pattern),
                bindings: newBindings,
                body: resolveTypesInExpression(body),
                type: resolveParameterizedType(type)
            )
            
        case .typeConstruction(let identifier, let typeArgs, let arguments, let type):
            let resolvedType = resolveParameterizedType(identifier.type)
            
            // Update the identifier name to match the resolved type's layout name
            var newName = identifier.name
            if case .structure(let decl) = resolvedType {
                newName = decl.name
            } else if case .union(let decl) = resolvedType {
                newName = decl.name
            }
            
            let newIdentifier = Symbol(
                name: newName,
                type: resolvedType,
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            let resolvedTypeArgs = typeArgs?.map { resolveParameterizedType($0) }
            return .typeConstruction(
                identifier: newIdentifier,
                typeArgs: resolvedTypeArgs,
                arguments: arguments.map { resolveTypesInExpression($0) },
                type: resolveParameterizedType(type)
            )
            
        case .memberPath(let source, let path):
            let newPath = path.map { sym in
                Symbol(
                    name: sym.name,
                    type: resolveParameterizedType(sym.type),
                    kind: sym.kind,
                    methodKind: sym.methodKind,
                    modulePath: sym.modulePath,
                    sourceFile: sym.sourceFile,
                    access: sym.access
                )
            }
            return .memberPath(
                source: resolveTypesInExpression(source),
                path: newPath
            )
            
        case .subscriptExpression(let base, let arguments, let method, let type):
            let newBase = resolveTypesInExpression(base)
            var newMethod = Symbol(
                name: method.name,
                type: resolveParameterizedType(method.type),
                kind: method.kind,
                methodKind: method.methodKind,
                modulePath: method.modulePath,
                sourceFile: method.sourceFile,
                access: method.access
            )
            
            // Resolve method name to mangled name for generic extension methods
            if !newBase.type.containsGenericParameter {
                // Look up the concrete method on the resolved base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: method.name) {
                    newMethod = Symbol(
                        name: concreteMethod.name,
                        type: concreteMethod.type,
                        kind: concreteMethod.kind,
                        methodKind: concreteMethod.methodKind,
                        modulePath: concreteMethod.modulePath,
                        sourceFile: concreteMethod.sourceFile,
                        access: concreteMethod.access
                    )
                }
            }
            
            return .subscriptExpression(
                base: newBase,
                arguments: arguments.map { resolveTypesInExpression($0) },
                method: newMethod,
                type: resolveParameterizedType(type)
            )
            
        case .unionConstruction(let type, let caseName, let arguments):
            return .unionConstruction(
                type: resolveParameterizedType(type),
                caseName: caseName,
                arguments: arguments.map { resolveTypesInExpression($0) }
            )
            
        case .intrinsicCall(let intrinsic):
            return .intrinsicCall(resolveTypesInIntrinsic(intrinsic))
            
        case .matchExpression(let subject, let cases, let type):
            let newCases = cases.map { matchCase in
                TypedMatchCase(
                    pattern: resolveTypesInPattern(matchCase.pattern),
                    body: resolveTypesInExpression(matchCase.body)
                )
            }
            return .matchExpression(
                subject: resolveTypesInExpression(subject),
                cases: newCases,
                type: resolveParameterizedType(type)
            )
            
        case .staticMethodCall(let baseType, let methodName, let typeArgs, let arguments, let type):
            // Resolve the base type and type arguments
            let resolvedBaseType = resolveParameterizedType(baseType)
            let resolvedTypeArgs = typeArgs.map { resolveParameterizedType($0) }
            let resolvedArguments = arguments.map { resolveTypesInExpression($0) }
            let resolvedReturnType = resolveParameterizedType(type)
            
            // If base type still contains generic parameters, keep as staticMethodCall
            if resolvedBaseType.containsGenericParameter || resolvedTypeArgs.contains(where: { $0.containsGenericParameter }) {
                return .staticMethodCall(
                    baseType: resolvedBaseType,
                    methodName: methodName,
                    typeArgs: resolvedTypeArgs,
                    arguments: resolvedArguments,
                    type: resolvedReturnType
                )
            }
            
            // Get the template name from the base type
            let templateName: String
            switch resolvedBaseType {
            case .structure(let decl):
                // Extract base name from mangled name (e.g., "List_I" -> "List")
                templateName = decl.name.split(separator: "_").first.map(String.init) ?? decl.name
            case .genericStruct(let name, _):
                templateName = name
            case .union(let decl):
                templateName = decl.name.split(separator: "_").first.map(String.init) ?? decl.name
            case .genericUnion(let name, _):
                templateName = name
            default:
                templateName = resolvedBaseType.description
            }
            
            // Calculate the mangled method name
            // For non-generic types (empty typeArgs), use "TypeName_methodName"
            // For generic types, use "TypeName_TypeArgs_methodName"
            let mangledMethodName: String
            if resolvedTypeArgs.isEmpty {
                mangledMethodName = "\(templateName)_\(methodName)"
            } else {
                let argLayoutKeys = resolvedTypeArgs.map { $0.layoutKey }.joined(separator: "_")
                mangledMethodName = "\(templateName)_\(argLayoutKeys)_\(methodName)"
            }
            
            // Check for concrete extension methods first (for primitive types like Int, UInt, etc.)
            if let methods = extensionMethods[templateName], let _ = methods[methodName] {
                // Method exists in concrete extension methods, just generate the call
                let functionType = Type.function(
                    parameters: resolvedArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: resolvedReturnType
                )
                let callee: TypedExpressionNode = .variable(
                    identifier: Symbol(name: mangledMethodName, type: functionType, kind: .function)
                )
                return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
            }
            
            // Ensure the extension method is instantiated (for generic types)
            if let extensions = input.genericTemplates.extensionMethods[templateName] {
                if let ext = extensions.first(where: { $0.method.name == methodName }) {
                    let key = InstantiationKey.extensionMethod(
                        templateName: templateName,
                        methodName: methodName,
                        typeArgs: resolvedTypeArgs,
                        methodTypeArgs: []  // TODO: Support method-level type args in method calls
                    )
                    if !processedRequestKeys.contains(key) {
                        pendingRequests.append(InstantiationRequest(
                            kind: .extensionMethod(baseType: resolvedBaseType, template: ext, typeArgs: resolvedTypeArgs, methodTypeArgs: []),
                            sourceLine: currentLine,
                            sourceFileName: currentFileName
                        ))
                    }
                }
            }
            
            // Create the function type for the callee
            let functionType = Type.function(
                parameters: resolvedArguments.map { Parameter(type: $0.type, kind: .byVal) },
                returns: resolvedReturnType
            )
            
            // Create the callee as a variable reference to the mangled function
            let callee: TypedExpressionNode = .variable(
                identifier: Symbol(name: mangledMethodName, type: functionType, kind: .function)
            )
            
            return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
            
        case .lambdaExpression(let parameters, let captures, let body, let type):
            // Resolve types in lambda parameters
            let newParameters = parameters.map { param in
                Symbol(
                    name: param.name,
                    type: resolveParameterizedType(param.type),
                    kind: param.kind,
                    methodKind: param.methodKind,
                    modulePath: param.modulePath,
                    sourceFile: param.sourceFile,
                    access: param.access
                )
            }
            // Resolve types in captures
            let newCaptures = captures.map { capture in
                CapturedVariable(
                    symbol: Symbol(
                        name: capture.symbol.name,
                        type: resolveParameterizedType(capture.symbol.type),
                        kind: capture.symbol.kind,
                        methodKind: capture.symbol.methodKind,
                        modulePath: capture.symbol.modulePath,
                        sourceFile: capture.symbol.sourceFile,
                        access: capture.symbol.access
                    ),
                    captureKind: capture.captureKind
                )
            }
            return .lambdaExpression(
                parameters: newParameters,
                captures: newCaptures,
                body: resolveTypesInExpression(body),
                type: resolveParameterizedType(type)
            )
        }
    }
    
    /// Resolves types in a statement.
    private func resolveTypesInStatement(_ stmt: TypedStatementNode) -> TypedStatementNode {
        switch stmt {
        case .variableDeclaration(let identifier, let value, let mutable):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: resolveParameterizedType(identifier.type),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            return .variableDeclaration(
                identifier: newIdentifier,
                value: resolveTypesInExpression(value),
                mutable: mutable
            )
            
        case .assignment(let target, let value):
            return .assignment(
                target: resolveTypesInExpression(target),
                value: resolveTypesInExpression(value)
            )
            
        case .compoundAssignment(let target, let op, let value):
            return .compoundAssignment(
                target: resolveTypesInExpression(target),
                operator: op,
                value: resolveTypesInExpression(value)
            )
            
        case .expression(let expr):
            return .expression(resolveTypesInExpression(expr))
            
        case .return(let value):
            return .return(value: value.map { resolveTypesInExpression($0) })
            
        case .break:
            return .break
            
        case .continue:
            return .continue
        }
    }
    
    /// Resolves types in a pattern.
    private func resolveTypesInPattern(_ pattern: TypedPattern) -> TypedPattern {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
            return pattern
            
        case .variable(let symbol):
            let newSymbol = Symbol(
                name: symbol.name,
                type: resolveParameterizedType(symbol.type),
                kind: symbol.kind,
                methodKind: symbol.methodKind,
                modulePath: symbol.modulePath,
                sourceFile: symbol.sourceFile,
                access: symbol.access
            )
            return .variable(symbol: newSymbol)
            
        case .unionCase(let caseName, let tagIndex, let elements):
            return .unionCase(
                caseName: caseName,
                tagIndex: tagIndex,
                elements: elements.map { resolveTypesInPattern($0) }
            )
            
        case .comparisonPattern:
            // Comparison patterns don't contain types to resolve
            return pattern
            
        case .andPattern(let left, let right):
            return .andPattern(
                left: resolveTypesInPattern(left),
                right: resolveTypesInPattern(right)
            )
            
        case .orPattern(let left, let right):
            return .orPattern(
                left: resolveTypesInPattern(left),
                right: resolveTypesInPattern(right)
            )
            
        case .notPattern(let inner):
            return .notPattern(pattern: resolveTypesInPattern(inner))
        }
    }
    
    /// Resolves types in an intrinsic call.
    private func resolveTypesInIntrinsic(_ intrinsic: TypedIntrinsic) -> TypedIntrinsic {
        switch intrinsic {
        case .allocMemory(let count, let resultType):
            return .allocMemory(
                count: resolveTypesInExpression(count),
                resultType: resolveParameterizedType(resultType)
            )
            
        case .deallocMemory(let ptr):
            return .deallocMemory(ptr: resolveTypesInExpression(ptr))
            
        case .copyMemory(let dest, let source, let count):
            return .copyMemory(
                dest: resolveTypesInExpression(dest),
                source: resolveTypesInExpression(source),
                count: resolveTypesInExpression(count)
            )
            
        case .moveMemory(let dest, let source, let count):
            return .moveMemory(
                dest: resolveTypesInExpression(dest),
                source: resolveTypesInExpression(source),
                count: resolveTypesInExpression(count)
            )
            
        case .refCount(let val):
            return .refCount(val: resolveTypesInExpression(val))
            
        case .ptrInit(let ptr, let val):
            return .ptrInit(
                ptr: resolveTypesInExpression(ptr),
                val: resolveTypesInExpression(val)
            )
            
        case .ptrDeinit(let ptr):
            return .ptrDeinit(ptr: resolveTypesInExpression(ptr))
            
        case .ptrPeek(let ptr):
            return .ptrPeek(ptr: resolveTypesInExpression(ptr))
            
        case .ptrOffset(let ptr, let offset):
            return .ptrOffset(
                ptr: resolveTypesInExpression(ptr),
                offset: resolveTypesInExpression(offset)
            )
            
        case .ptrTake(let ptr):
            return .ptrTake(ptr: resolveTypesInExpression(ptr))
            
        case .ptrReplace(let ptr, let val):
            return .ptrReplace(
                ptr: resolveTypesInExpression(ptr),
                val: resolveTypesInExpression(val)
            )
            
        case .float32Bits(let value):
            return .float32Bits(value: resolveTypesInExpression(value))
            
        case .float64Bits(let value):
            return .float64Bits(value: resolveTypesInExpression(value))

        case .float32FromBits(let bits):
            return .float32FromBits(bits: resolveTypesInExpression(bits))
            
        case .float64FromBits(let bits):
            return .float64FromBits(bits: resolveTypesInExpression(bits))
            
        case .exit(let code):
            return .exit(code: resolveTypesInExpression(code))
            
        case .abort:
            return .abort

        // Low-level IO intrinsics (minimal set using file descriptors)
        case .fwrite(let ptr, let len, let fd):
            return .fwrite(
                ptr: resolveTypesInExpression(ptr),
                len: resolveTypesInExpression(len),
                fd: resolveTypesInExpression(fd)
            )
            
        case .fgetc(let fd):
            return .fgetc(fd: resolveTypesInExpression(fd))
            
        case .fflush(let fd):
            return .fflush(fd: resolveTypesInExpression(fd))
            
        case .ptrBits:
            return .ptrBits
        }
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

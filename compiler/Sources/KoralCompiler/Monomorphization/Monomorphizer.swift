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
    internal let input: TypeCheckerOutput
    
    // MARK: - Caches
    
    /// Cache for instantiated types: "TemplateName<Arg1,Arg2>" -> Type
    internal var instantiatedTypes: [String: Type] = [:]
    
    /// Cache for instantiated functions: "TemplateName<Arg1,Arg2>" -> (MangledName, Type)
    internal var instantiatedFunctions: [String: (String, Type)] = [:]
    
    /// Track which layout names have been generated to avoid duplicates
    internal var generatedLayouts: Set<String> = []
    
    // MARK: - Output
    
    /// Generated global nodes for instantiated types and functions
    internal var generatedNodes: [TypedGlobalNode] = []
    
    // MARK: - State
    
    /// Mapping from Layout Name to Template Info (Base Name + Args)
    internal var layoutToTemplateInfo: [String: (base: String, args: [Type])] = [:]
    
    /// Extension methods indexed by type name (from registry)
    internal var extensionMethods: [String: [String: Symbol]] = [:]

    
    /// Current source line for error reporting
    internal var currentLine: Int = 1 {
        didSet {
            SemanticErrorContext.currentLine = currentLine
        }
    }

    /// Current source file for error reporting
    internal var currentFileName: String = "<input>" {
        didSet {
            SemanticErrorContext.currentFileName = currentFileName
        }
    }
    
    /// Pending instantiation requests (work queue for transitive instantiation)
    internal var pendingRequests: [InstantiationRequest] = []
    
    /// Processed request keys to avoid duplicate processing
    internal var processedRequestKeys: Set<InstantiationKey> = []
    
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
                    instantiatedFunctions[identifier.name] = (identifier.name, identifier.type)
                    resultNodes.append(node)
                case .givenDeclaration(let type, let methods):
                    // Track already-generated extension methods
                    let qualifiedTypeName: String
                    switch type {
                    case .structure(let decl):
                        qualifiedTypeName = decl.qualifiedName
                    case .union(let decl):
                        qualifiedTypeName = decl.qualifiedName
                    default:
                        qualifiedTypeName = type.description
                    }
                    
                    for method in methods {
                        let mangledName = "\(qualifiedTypeName)_\(method.identifier.name)"
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
        var resolvedResultNodes: [TypedGlobalNode] = []
        for node in resultNodes {
            let resolvedNode = try resolveTypesInGlobalNode(node)
            resolvedResultNodes.append(resolvedNode)
        }
        
        // Process any new instantiation requests that were added during type resolution
        while !pendingRequests.isEmpty {
            let request = pendingRequests.removeFirst()
            try processRequest(request)
        }
        
        // Also resolve types in generated nodes
        var resolvedGeneratedNodes: [TypedGlobalNode] = []
        var processedGeneratedCount = 0
        
        while processedGeneratedCount < generatedNodes.count {
            for i in processedGeneratedCount..<generatedNodes.count {
                let resolvedNode = try resolveTypesInGlobalNode(generatedNodes[i])
                resolvedGeneratedNodes.append(resolvedNode)
            }
            processedGeneratedCount = generatedNodes.count
            
            while !pendingRequests.isEmpty {
                let request = pendingRequests.removeFirst()
                try processRequest(request)
            }
        }
        
        return MonomorphizedProgram(globalNodes: resolvedGeneratedNodes + resolvedResultNodes)
    }

    
    // MARK: - Request Processing
    
    /// Processes a single instantiation request.
    private func processRequest(_ request: InstantiationRequest) throws {
        currentLine = request.sourceLine
        currentFileName = request.sourceFileName
        SemanticErrorContext.currentLine = currentLine
        SemanticErrorContext.currentFileName = currentFileName
        
        guard currentRecursionDepth < maxRecursionDepth else {
            throw SemanticError(.generic("Maximum instantiation depth exceeded (possible infinite recursion)"), line: currentLine)
        }
        
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
    
    // MARK: - Helper Methods
    
    internal func getCompilerMethodKind(_ name: String) -> CompilerMethodKind {
        return SemaUtils.getCompilerMethodKind(name)
    }
    
    private func resolveTraitName(from node: TypeNode) throws -> String {
        return try SemaUtils.resolveTraitName(from: node)
    }
    
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
}

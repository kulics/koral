// Monomorphizer.swift
// Implements the monomorphization phase that processes instantiation requests
// and generates concrete types and functions from generic templates.

import Foundation

/// The output from the Monomorphizer phase.
/// Contains only concrete (non-generic) declarations ready for code generation.
public struct MonomorphizedProgram {
    /// The global nodes containing all concrete declarations.
    public let globalNodes: [TypedGlobalNode]
    
    /// 静态方法查找表：(类型名, 方法名) -> DefId
    /// 用于 CodeGen 查找标准库函数的正确 C 标识符
    public let staticMethodLookup: [String: DefId]
    
    /// Creates a new MonomorphizedProgram.
    public init(globalNodes: [TypedGlobalNode], staticMethodLookup: [String: DefId] = [:]) {
        self.globalNodes = globalNodes
        self.staticMethodLookup = staticMethodLookup
    }
    
    /// 查找静态方法的完整限定名
    /// - Parameters:
    ///   - typeName: 类型名（如 "String", "Rune"）
    ///   - methodName: 方法名（如 "empty", "from_bytes_unchecked"）
    /// - Returns: 对应的 DefId，如果未找到则返回 nil
    public func lookupStaticMethod(typeName: String, methodName: String) -> DefId? {
        let key = "\(typeName).\(methodName)"
        return staticMethodLookup[key]
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
    
    // MARK: - DefId Support
    
    /// Unified compiler context
    internal let context: CompilerContext
    
    /// Creates a Symbol with a new DefId for monomorphized entities
    /// - Parameters:
    ///   - name: Symbol name
    ///   - type: Symbol type
    ///   - kind: Symbol kind
    ///   - methodKind: Compiler method kind (default: .normal)
    ///   - modulePath: Module path (default: empty for generated symbols)
    ///   - sourceFile: Source file (default: empty)
    ///   - access: Access modifier (default: .default)
    /// - Returns: A new Symbol with allocated DefId
    internal func makeSymbol(
        name: String,
        type: Type,
        kind: SymbolKind,
        methodKind: CompilerMethodKind = .normal,
        modulePath: [String] = [],
        sourceFile: String = "",
        access: AccessModifier = .default
    ) -> Symbol {
        let isMutable: Bool
        switch kind {
        case .variable(let varKind):
            isMutable = varKind.isMutable
        case .function, .type, .module:
            isMutable = false
        }
        return context.createSymbol(
            name: name,
            modulePath: modulePath,
            sourceFile: sourceFile,
            type: type,
            kind: kind,
            methodKind: methodKind,
            access: access,
            span: .unknown,
            isMutable: isMutable
        )
    }
    
    /// Creates a Symbol by copying from an existing symbol but with a new DefId
    /// Used when transforming symbols during monomorphization
    internal func copySymbolWithNewDefId(
        _ symbol: Symbol,
        newName: String? = nil,
        newType: Type? = nil,
        newModulePath: [String]? = nil,
        newSourceFile: String? = nil
    ) -> Symbol {
        let name = newName ?? context.getName(symbol.defId) ?? "<unknown>"
        let modulePath = newModulePath ?? context.getModulePath(symbol.defId) ?? []
        let sourceFile = newSourceFile ?? context.getSourceFile(symbol.defId) ?? ""
        let access = context.getAccess(symbol.defId) ?? .default
        return makeSymbol(
            name: name,
            type: newType ?? symbol.type,
            kind: symbol.kind,
            methodKind: symbol.methodKind,
            modulePath: modulePath,
            sourceFile: sourceFile,
            access: access
        )
    }
    
    // MARK: - Initialization
    
    /// Creates a new Monomorphizer with the given TypeChecker output.
    /// - Parameter input: The output from the TypeChecker phase
    public init(input: TypeCheckerOutput) {
        self.input = input
        self.context = input.context
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
                case .foreignUsing, .foreignType, .foreignFunction:
                    resultNodes.append(node)
                case .genericTypeTemplate, .genericFunctionTemplate:
                    // Skip template placeholders - they will be instantiated on demand
                    break
                case .globalStructDeclaration(let identifier, _):
                    // Track already-generated struct layouts
                    let identifierName = context.getName(identifier.defId) ?? "<unknown>"
                    generatedLayouts.insert(identifierName)
                    // Also cache the type if it's a generic instantiation
                          if case .structure(let defId) = identifier.type,
                              context.isGenericInstantiation(defId) == true {
                        instantiatedTypes[identifierName] = identifier.type
                    }
                    resultNodes.append(node)
                case .globalUnionDeclaration(let identifier, _):
                    // Track already-generated union layouts
                    let identifierName = context.getName(identifier.defId) ?? "<unknown>"
                    generatedLayouts.insert(identifierName)
                          if case .union(let defId) = identifier.type,
                              context.isGenericInstantiation(defId) == true {
                        instantiatedTypes[identifierName] = identifier.type
                    }
                    resultNodes.append(node)
                case .globalFunction(let identifier, _, _):
                    // Track already-generated functions
                    let identifierName = context.getName(identifier.defId) ?? "<unknown>"
                    generatedLayouts.insert(identifierName)
                    instantiatedFunctions[identifierName] = (identifierName, identifier.type)
                    resultNodes.append(node)
                case .givenDeclaration(let type, let methods):
                    // Track already-generated extension methods
                    let qualifiedTypeName: String
                    switch type {
                    case .structure(let defId):
                        qualifiedTypeName = context.getQualifiedName(defId) ?? type.description
                    case .union(let defId):
                        qualifiedTypeName = context.getQualifiedName(defId) ?? type.description
                    default:
                        qualifiedTypeName = type.description
                    }
                    
                    for method in methods {
                        let methodName = context.getName(method.identifier.defId) ?? "<unknown>"
                        let mangledName = "\(qualifiedTypeName)_\(methodName)"
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
        
        var allNodes = resolvedGeneratedNodes + resolvedResultNodes

        // Finalize trait placeholder resolution after all instantiations.
        var processedCount = processedRequestKeys.count
        var didProcess = true
        while didProcess {
            while !pendingRequests.isEmpty {
                let request = pendingRequests.removeFirst()
                try processRequest(request)
            }

            var reResolved: [TypedGlobalNode] = []
            for node in allNodes {
                let resolvedNode = try resolveTypesInGlobalNode(node)
                reResolved.append(resolvedNode)
            }
            allNodes = reResolved

            didProcess = processedRequestKeys.count != processedCount
            processedCount = processedRequestKeys.count
        }

        // 构建静态方法查找表
        let staticMethodLookup = buildStaticMethodLookup(from: allNodes)
        
        return MonomorphizedProgram(globalNodes: allNodes, staticMethodLookup: staticMethodLookup)
    }
    
    /// 构建静态方法查找表
    /// - Parameter nodes: 所有全局节点
    /// - Returns: (类型名.方法名) -> 完整限定名 的映射
    private func buildStaticMethodLookup(from nodes: [TypedGlobalNode]) -> [String: DefId] {
        var lookup: [String: DefId] = [:]
        
        for node in nodes {
            switch node {
            case .givenDeclaration(let type, let methods):
                // 获取类型的简单名称（不含模块路径）
                let typeName: String
                let qualifiedTypeName: String
                switch type {
                case .structure(let defId):
                    let name = context.getName(defId) ?? type.description
                    typeName = name
                    qualifiedTypeName = context.getQualifiedName(defId) ?? name
                case .union(let defId):
                    let name = context.getName(defId) ?? type.description
                    typeName = name
                    qualifiedTypeName = context.getQualifiedName(defId) ?? name
                default:
                    continue
                }
                
                // 注册每个方法
                for method in methods {
                    // method.identifier.name 是 mangled name，格式为 qualifiedTypeName_methodName
                    // 例如：std_std_String_from_bytes_unchecked
                    // 我们需要提取原始方法名
                    let mangledName = context.getName(method.identifier.defId) ?? "<unknown>"
                    
                    // 从 mangled name 中提取原始方法名
                    // mangled name 格式：qualifiedTypeName_methodName
                    let prefix = "\(qualifiedTypeName)_"
                    let originalMethodName: String
                    if mangledName.hasPrefix(prefix) {
                        originalMethodName = String(mangledName.dropFirst(prefix.count))
                    } else {
                        originalMethodName = mangledName
                    }
                    
                    // 键格式：TypeName.methodName（使用简单类型名和原始方法名）
                    let key = "\(typeName).\(originalMethodName)"
                    lookup[key] = method.identifier.defId
                }
                
            case .globalFunction(let identifier, _, _):
                // 对于全局函数，也可以通过简单名称查找
                let name = context.getName(identifier.defId) ?? "<unknown>"
                
                // 检查是否是类型的静态方法（名称格式：TypeName_methodName）
                if let underscoreIndex = name.firstIndex(of: "_") {
                    let typeName = String(name[..<underscoreIndex])
                    let methodName = String(name[name.index(after: underscoreIndex)...])
                    let key = "\(typeName).\(methodName)"
                    lookup[key] = identifier.defId
                }
                
            default:
                break
            }
        }
        
        return lookup
    }

    // MARK: - Trait Placeholder Instantiation

    internal func instantiateTraitPlaceholderMethod(baseType: Type, name: String, methodTypeArgs: [Type]) throws {
        let base: Type
        switch baseType {
        case .reference(let inner):
            base = inner
        default:
            base = baseType
        }

        switch base {
        case .genericStruct(let template, let args):
            let resolvedArgs = args.map { resolveParameterizedType($0) }
                if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }),
                    let extensions = input.genericTemplates.extensionMethods[template],
                    let ext = extensions.first(where: { $0.method.name == name }),
                    ext.method.typeParameters.count == methodTypeArgs.count {
                let resolvedBase = resolveParameterizedType(.genericStruct(template: template, args: resolvedArgs))
                _ = try instantiateExtensionMethodFromEntry(
                    baseType: resolvedBase,
                    structureName: template,
                    genericArgs: resolvedArgs,
                    methodTypeArgs: methodTypeArgs,
                    methodInfo: ext
                )
            }
        case .genericUnion(let template, let args):
            let resolvedArgs = args.map { resolveParameterizedType($0) }
                if !resolvedArgs.contains(where: { context.containsGenericParameter($0) }),
                    let extensions = input.genericTemplates.extensionMethods[template],
                    let ext = extensions.first(where: { $0.method.name == name }),
                    ext.method.typeParameters.count == methodTypeArgs.count {
                let resolvedBase = resolveParameterizedType(.genericUnion(template: template, args: resolvedArgs))
                _ = try instantiateExtensionMethodFromEntry(
                    baseType: resolvedBase,
                    structureName: template,
                    genericArgs: resolvedArgs,
                    methodTypeArgs: methodTypeArgs,
                    methodInfo: ext
                )
            }
        case .structure(let defId), .union(let defId):
            let typeName = context.getName(defId) ?? ""
            let simpleName = typeName.split(separator: ".").last.map(String.init) ?? typeName
            // Use stored templateName if available, otherwise fall back to full name
            let baseName = context.getTemplateName(defId) ?? simpleName
            var extensions = input.genericTemplates.extensionMethods[baseName]
            if extensions == nil {
                if let matchKey = input.genericTemplates.extensionMethods.keys.first(where: { key in
                    simpleName.hasPrefix(key) || simpleName.contains(key)
                }) {
                    extensions = input.genericTemplates.extensionMethods[matchKey]
                }
            }
            if let extensions,
               let ext = extensions.first(where: { $0.method.name == name }),
               ext.method.typeParameters.count == methodTypeArgs.count {
                                let resolvedTypeArgs = context.getTypeArguments(defId)
                                    ?? layoutToTemplateInfo[typeName]?.args
                if resolvedTypeArgs == nil || resolvedTypeArgs?.count != ext.typeParams.count {
                    throw SemanticError(
                        .generic("Missing type arguments for generic instantiation '\(typeName)' while resolving method '\(name)'."),
                        line: currentLine
                    )
                }
                if let typeArgs = resolvedTypeArgs,
                   typeArgs.count == ext.typeParams.count {
                    _ = try instantiateExtensionMethodFromEntry(
                        baseType: base,
                        structureName: baseName,
                        genericArgs: typeArgs,
                        methodTypeArgs: methodTypeArgs,
                        methodInfo: ext
                    )
                }
            }
        default:
            break
        }
    }

    internal func enqueueTraitPlaceholderRequest(
        baseType: Type,
        methodName: String,
        methodTypeArgs: [Type]
    ) {
        if context.containsGenericParameter(baseType) {
            return
        }
        if methodTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
            return
        }
        pendingRequests.append(InstantiationRequest(
            kind: .traitMethod(
                baseType: baseType,
                methodName: methodName,
                methodTypeArgs: methodTypeArgs
            ),
            sourceLine: currentLine,
            sourceFileName: currentFileName
        ))
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
            case .extensionMethod(_, let baseType, let template, let typeArgs, let methodTypeArgs):
                _ = try instantiateExtensionMethod(
                    baseType: baseType,
                    template: template,
                    typeArgs: typeArgs,
                    methodTypeArgs: methodTypeArgs
                )
            case .traitMethod(let baseType, let methodName, let methodTypeArgs):
                _ = try instantiateTraitPlaceholderMethod(
                    baseType: baseType,
                    name: methodName,
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

    /// 获取或分配类型定义的 DefId（用于单态化生成的类型）
    internal func getOrAllocateTypeDefId(
        name: String,
        kind: TypeDefKind,
        modulePath: [String] = [],
        sourceFile: String = "",
        access: AccessModifier = .default
    ) -> DefId {
        if let existing = context.lookupDefId(modulePath: modulePath, name: name, sourceFile: sourceFile.isEmpty ? nil : sourceFile) {
            return existing
        }
        return context.allocateDefId(
            modulePath: modulePath,
            name: name,
            kind: .type(kind),
            sourceFile: sourceFile,
            access: access,
            span: .unknown
        )
    }
    
    private func resolveTraitName(from node: TypeNode) throws -> String {
        return try SemaUtils.resolveTraitName(from: node)
    }
    
    private func builtinStringType() -> Type {
        let defId = getOrAllocateTypeDefId(name: "String", kind: .structure)
        return .structure(defId: defId)
    }
}

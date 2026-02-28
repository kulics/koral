// MonomorphizerFunctions.swift
// Extension for Monomorphizer that handles function and extension method instantiation.
// This file contains methods for instantiating generic function templates and
// extension methods with concrete type arguments.

import Foundation

// MARK: - Function Instantiation Extension

extension Monomorphizer {

    private func methodLookupCandidates(_ name: String) -> [String] {
        [name]
    }

    private func resolvedReceiverMethodName(_ methodSymbol: Symbol) -> String {
        if let dispatchInfo = receiverMethodDispatch[methodSymbol.defId] {
            return dispatchInfo.methodName
        }
        return context.getName(methodSymbol.defId) ?? ""
    }

    internal func lookupConcreteMethodSymbol(
        on selfType: Type,
        method: Symbol,
        methodTypeArgs: [Type] = [],
        expectedMethodType: Type? = nil
    ) throws -> Symbol? {
        let methodName = resolvedReceiverMethodName(method)
        return try lookupConcreteMethodSymbol(
            on: selfType,
            name: methodName,
            methodTypeArgs: methodTypeArgs,
            expectedMethodType: expectedMethodType
        )
    }
    
    // MARK: - Function Instantiation
    
    /// Instantiates a generic function template with concrete type arguments.
    /// - Parameters:
    ///   - template: The generic function template
    ///   - args: The concrete type arguments
    /// - Returns: A tuple of (specialized symbol name, function type)
    internal func instantiateFunction(template: GenericFunctionTemplate, args: [Type]) throws -> (String, Type) {
        guard template.typeParameters.count == args.count else {
            throw SemanticError.typeMismatch(
                expected: "\(template.typeParameters.count) generic arguments",
                got: "\(args.count)"
            )
        }
        
        // Note: Trait constraints were already validated by TypeChecker at declaration time
        
        // Check cache
        let templateName = context.getName(template.defId) ?? "<unknown>"
        let key = "\(templateName)<\(args.map { $0.description }.joined(separator: ", "))>"
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
        let resolvedParams: [Symbol]
        if let checkedParams = template.checkedParameters {
            resolvedParams = checkedParams.map { param in
                let paramType = substituteType(param.type, substitution: typeSubstitution)
                return copySymbolPreservingDefId(param, newType: paramType)
            }
        } else {
            resolvedParams = try template.parameters.map { param -> Symbol in
                let paramType = try resolveTypeNode(param.type, substitution: typeSubstitution)
                return makeSymbol(
                    name: param.name,
                    type: paramType,
                    kind: .variable(param.mutable ? .MutableValue : .Value)
                )
            }
        }
        
        // Build specialized symbol name
        let argLayoutKeys = args.map { context.getLayoutKey($0) }.joined(separator: "_")
        let mangledName = "\(templateName)_\(argLayoutKeys)"
        
        // Create function type
        let functionType = Type.function(
            parameters: resolvedParams.map {
                Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: resolvedReturnType)
        
        // Skip code generation if function type still contains generic parameters
        if context.containsGenericParameter(functionType) {
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
            let substitutedBody = substituteTypesInExpression(checkedBody, substitution: typeSubstitution)
            typedBody = resolveTypesInExpression(substitutedBody)
        } else {
            // If declaration-time checked body is unavailable, emit an abort body.
            let abortSymbol = makeSymbol(
                name: "abort",
                type: .function(parameters: [], returns: .never),
                kind: .function
            )
            typedBody = .call(callee: TypedExpressionNode.variable(identifier: abortSymbol), arguments: [], type: .never)
        }
        
        // Skip intrinsic functions
        let intrinsicNames = [
            "alloc_memory", "dealloc_memory", "copy_memory", "move_memory", "ref_count",
            "init_memory", "deinit_memory", "take_memory", "null_ptr",
            "downgrade_ref", "upgrade_ref", "ref_is_borrow",
        ]
        
        // Generate global function if not already generated
        if !generatedLayouts.contains(mangledName) && !intrinsicNames.contains(templateName) {
            generatedLayouts.insert(mangledName)
            
            let functionNode = TypedGlobalNode.globalFunction(
                identifier: makeSymbol(name: mangledName, type: functionType, kind: .function),
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
    internal func instantiateExtensionMethod(
        baseType: Type,
        templateName: String,
        template: GenericExtensionMethodTemplate,
        typeArgs: [Type],
        methodTypeArgs: [Type]
    ) throws -> Symbol {
        // Resolve the base type if it's a parameterized type
        let resolvedBaseType = resolveParameterizedType(baseType)
        
        // Derive the structure name from the base type
        let structureName: String
        switch resolvedBaseType {
        case .structure(let defId):
            let name = context.getName(defId) ?? ""
            // Use stored templateName if available, otherwise fall back to full name
            structureName = context.getTemplateName(defId) ?? name
        case .genericStruct(let templateName, _):
            structureName = templateName
        case .genericUnion(let templateName, _):
            structureName = templateName
        case .union(let defId):
            let name = context.getName(defId) ?? ""
            // Use stored templateName if available, otherwise fall back to full name
            structureName = context.getTemplateName(defId) ?? name
        case .pointer(_):
            structureName = "Ptr"
        default:
            structureName = resolvedBaseType.description
        }
        
        // Look up the latest template from the registry to get the checked body.
        // InstantiationRequests capture a snapshot of the template at creation time,
        // which may have checkedBody == nil if the request was recorded before
        // the given block's body was checked in Pass 3. The registry always has
        // the final version with checkedBody set.
          let resolvedTemplate: GenericExtensionMethodTemplate
        if template.checkedBody == nil,
              let extensions = input.genericTemplates.extensionMethods[templateName],
           let latest = extensions.first(where: {
               $0.method.name == template.method.name &&
               $0.typeParams.count == template.typeParams.count &&
               $0.checkedBody != nil
           }) {
            resolvedTemplate = latest
        } else {
            resolvedTemplate = template
        }
        
        return try instantiateExtensionMethodFromEntry(
            baseType: resolvedBaseType,
            structureName: structureName,
            genericArgs: typeArgs,
            methodTypeArgs: methodTypeArgs,
            methodInfo: resolvedTemplate
        )
    }
    
    /// Instantiates an extension method from a method entry.
    internal func instantiateExtensionMethodFromEntry(
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
        
        // Build specialized method symbol name (including method type args when present)
        let argLayoutKeys = genericArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
        let methodArgLayoutKeys = methodTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
        let receiverLayoutKey = context.getLayoutKey(baseType)
        let receiverGenericArgCount: Int = {
            switch baseType {
            case .structure(let defId), .union(let defId):
                return context.getTypeArguments(defId)?.count ?? 0
            case .genericStruct(_, let args), .genericUnion(_, let args):
                return args.count
            case .pointer:
                return 1
            default:
                return 0
            }
        }()
        let requiresSelfDisambiguation = receiverGenericArgCount > genericArgs.count
        let mangledName: String
        let methodBaseName = method.name
        if genericArgs.isEmpty {
            if methodTypeArgs.isEmpty {
                mangledName = "\(structureName)_\(methodBaseName)"
            } else {
                mangledName = "\(structureName)_\(methodBaseName)_\(methodArgLayoutKeys)"
            }
        } else if methodTypeArgs.isEmpty {
            mangledName = "\(structureName)_\(argLayoutKeys)_\(methodBaseName)"
        } else {
            mangledName = "\(structureName)_\(argLayoutKeys)_\(methodBaseName)_\(methodArgLayoutKeys)"
        }
        let disambiguatedMangledName: String
        if requiresSelfDisambiguation {
            disambiguatedMangledName = "\(mangledName)_self_\(receiverLayoutKey)"
        } else {
            disambiguatedMangledName = mangledName
        }
        let key = "ext:\(disambiguatedMangledName)"
        
        // Check cache
        if let cachedSymbol = instantiatedFunctionSymbols[key] {
            return copySymbolPreservingDefId(cachedSymbol)
        }
        if let (cachedName, cachedType) = instantiatedFunctions[key] {
            let kind = getCompilerMethodKind(methodBaseName)
            let cachedSymbol = instantiatedFunctionSymbols[key] ?? makeSymbol(
                name: cachedName,
                type: cachedType,
                kind: .function,
                methodKind: kind
            )
            instantiatedFunctionSymbols[key] = cachedSymbol
            return copySymbolPreservingDefId(cachedSymbol)
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
        let returnType: Type
        if let checkedReturnType = methodInfo.checkedReturnType {
            returnType = substituteType(checkedReturnType, substitution: typeSubstitution)
        } else {
            returnType = try resolveTypeNode(method.returnType, substitution: typeSubstitution)
        }
        let params: [Symbol]
        if let checkedParams = methodInfo.checkedParameters {
            params = checkedParams.map { param in
                let paramType = substituteType(param.type, substitution: typeSubstitution)
                return copySymbolPreservingDefId(param, newType: paramType)
            }
        } else {
            params = try method.parameters.map { param -> Symbol in
                let paramType = try resolveTypeNode(param.type, substitution: typeSubstitution)
                return makeSymbol(
                    name: param.name,
                    type: paramType,
                    kind: .variable(param.mutable ? .MutableValue : .Value)
                )
            }
        }
        
        // Create function type
        let functionType = Type.function(
            parameters: params.map {
                Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
        )
        
        // Skip code generation if function type still contains generic parameters
        if context.containsGenericParameter(functionType) {
            let kind = getCompilerMethodKind(methodBaseName)
            return makeSymbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
        }
        
        // IMPORTANT: Cache the function BEFORE processing the body to prevent infinite recursion
        // This allows recursive methods (like rehash calling insert, insert calling rehash) to work
        instantiatedFunctions[key] = (disambiguatedMangledName, functionType)
        let methodKind = getCompilerMethodKind(methodBaseName)
        if instantiatedFunctionSymbols[key] == nil {
            instantiatedFunctionSymbols[key] = makeSymbol(
                name: disambiguatedMangledName,
                type: functionType,
                kind: .function,
                methodKind: methodKind
            )
        }
        
        // Get the typed body from the declaration-time checked body
        let typedBody: TypedExpressionNode
        if let checkedBody = methodInfo.checkedBody {
            // Use the declaration-time checked body and substitute types
            let substitutedBody = substituteTypesInExpression(checkedBody, substitution: typeSubstitution)
            typedBody = resolveTypesInExpression(substitutedBody)
        } else {
            // If declaration-time checked body is unavailable, use a conservative placeholder body.
            typedBody = createPlaceholderBody(returnType: returnType)
        }
        
        // Generate global function if not already generated
        let generatedSymbol: Symbol
        if !generatedLayouts.contains(disambiguatedMangledName) {
            generatedLayouts.insert(disambiguatedMangledName)
            generatedSymbol = instantiatedFunctionSymbols[key] ?? makeSymbol(
                name: disambiguatedMangledName,
                type: functionType,
                kind: .function,
                methodKind: methodKind
            )
            let functionNode = TypedGlobalNode.globalFunction(
                identifier: generatedSymbol,
                parameters: params,
                body: typedBody
            )
            generatedNodes.append(functionNode)
        } else if let cachedSymbol = instantiatedFunctionSymbols[key] {
            generatedSymbol = cachedSymbol
        } else {
            generatedSymbol = makeSymbol(
                name: disambiguatedMangledName,
                type: functionType,
                kind: .function,
                methodKind: methodKind
            )
        }

        instantiatedFunctionSymbols[key] = generatedSymbol
        if receiverMethodDispatch[generatedSymbol.defId] == nil {
            receiverMethodDispatch[generatedSymbol.defId] = ReceiverMethodDispatchInfo(
                methodDefId: generatedSymbol.defId,
                methodName: methodBaseName,
                owner: .concreteType(typeName: structureName)
            )
        }

        // Register structured lookup: baseType name + method name -> DefId
        // This keeps buildStaticMethodLookup DefId-driven from instantiation metadata.
        let baseTypeName: String?
        switch baseType {
        case .structure(let defId): baseTypeName = context.getName(defId)
        case .union(let defId):     baseTypeName = context.getName(defId)
        default:                    baseTypeName = nil
        }
        let concreteLookupTypeName = baseTypeName ?? structureName
        let lookupKey = "\(concreteLookupTypeName).\(methodBaseName)"
        extensionMethodDefIds[lookupKey] = generatedSymbol.defId

        // Only register template-name aliases for non-generic receivers.
        // Generic instantiations must stay keyed by concrete layout names
        // to avoid cross-instantiation collisions (e.g. List_U8 vs List_String).
        if genericArgs.isEmpty, structureName != concreteLookupTypeName {
            let templateKey = "\(structureName).\(methodBaseName)"
            extensionMethodDefIds[templateKey] = generatedSymbol.defId
        }

        return copySymbolPreservingDefId(generatedSymbol)
    }
    
    /// Creates a placeholder body for methods that need re-checking.
    internal func createPlaceholderBody(returnType: Type) -> TypedExpressionNode {
        switch returnType {
        case .void:
            return .blockExpression(statements: [], type: .void)
        case .int:
            return .integerLiteral(value: "0", type: .int)
        case .bool:
            return .booleanLiteral(value: false, type: .bool)
        default:
            // Conservative default path: abort for non-default-constructible returns.
            let abortSymbol = makeSymbol(
                name: "abort",
                type: .function(parameters: [], returns: .never),
                kind: .function
            )
            return .call(callee: TypedExpressionNode.variable(identifier: abortSymbol), arguments: [], type: .never)
        }
    }

    private func selectExtensionTemplateForBase(
        baseType: Type,
        methodName: String,
        methodTypeArgCount: Int? = nil,
        extensionTypeArgCount: Int? = nil
    ) -> GenericExtensionMethodTemplate? {
        for candidateName in extensionLookupTypeNames(for: baseType) {
            guard let extensions = input.genericTemplates.extensionMethods[candidateName],
                  let selected = selectExtensionTemplate(
                    extensions,
                    name: methodName,
                    methodTypeArgCount: methodTypeArgCount,
                    extensionTypeArgCount: extensionTypeArgCount
                  ) else {
                continue
            }
            return selected
        }
        return nil
    }
    
    // MARK: - Intrinsic Extension Method Instantiation
    
    /// Instantiates an intrinsic extension method.
    internal func instantiateIntrinsicExtensionMethod(
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
        
        let argLayoutKeys = genericArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
        let methodBaseName = method.name
        let mangledName = "\(structureName)_\(argLayoutKeys)_\(methodBaseName)"
        let key = "ext:\(mangledName)"
        
        if let (cachedName, cachedType) = instantiatedFunctions[key] {
            let kind = getCompilerMethodKind(methodBaseName)
            return makeSymbol(name: cachedName, type: cachedType, kind: .function, methodKind: kind)
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
            return makeSymbol(
                name: param.name,
                type: paramType,
                kind: .variable(param.mutable ? .MutableValue : .Value)
            )
        }
        
        let funcType = Type.function(
            parameters: params.map {
                Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
        )
        
        instantiatedFunctions[key] = (mangledName, funcType)
        let kind = getCompilerMethodKind(methodBaseName)
        return makeSymbol(name: mangledName, type: funcType, kind: .function, methodKind: kind)
    }
    
    // MARK: - Method Lookup
    
    /// Looks up a concrete method symbol on a type.
    internal func lookupConcreteMethodSymbol(
        on selfType: Type,
        name: String,
        methodTypeArgs: [Type] = [],
        expectedMethodType: Type? = nil
    ) throws -> Symbol? {
        switch selfType {
        case .reference(let inner):
            // For reference types, look up the method on the inner type
            return try lookupConcreteMethodSymbol(
                on: inner,
                name: name,
                methodTypeArgs: methodTypeArgs,
                expectedMethodType: expectedMethodType
            )

        case .genericStruct(let template, let args):
            let resolvedArgs = args.map { resolveParameterizedType($0) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return nil
            }
                if let extensions = input.genericTemplates.extensionMethods[template],
                    let ext = selectExtensionTemplate(
                        extensions,
                        name: name,
                        extensionTypeArgCount: resolvedArgs.count
                    )
            {
                let resolvedBase = resolveParameterizedType(selfType)
                let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                    methodInfo: ext,
                    baseType: resolvedBase,
                    extensionTypeArgs: resolvedArgs,
                    providedMethodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                )
                return try instantiateExtensionMethodFromEntry(
                    baseType: resolvedBase,
                    structureName: template,
                    genericArgs: resolvedArgs,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    methodInfo: ext
                )
            }
            let resolved = resolveParameterizedType(selfType)
            if resolved != selfType {
                return try lookupConcreteMethodSymbol(
                    on: resolved,
                    name: name,
                    methodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                )
            }
            if let traitTargetCandidate = try lookupTraitTargetExtensionMethod(
                on: selfType,
                name: name,
                methodTypeArgs: methodTypeArgs,
                expectedMethodType: expectedMethodType
            ) {
                return traitTargetCandidate
            }
            return nil

        case .genericUnion(let template, let args):
            let resolvedArgs = args.map { resolveParameterizedType($0) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return nil
            }
                if let extensions = input.genericTemplates.extensionMethods[template],
                    let ext = selectExtensionTemplate(
                        extensions,
                        name: name,
                        extensionTypeArgCount: resolvedArgs.count
                    )
            {
                let resolvedBase = resolveParameterizedType(selfType)
                let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                    methodInfo: ext,
                    baseType: resolvedBase,
                    extensionTypeArgs: resolvedArgs,
                    providedMethodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                )
                return try instantiateExtensionMethodFromEntry(
                    baseType: resolvedBase,
                    structureName: template,
                    genericArgs: resolvedArgs,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    methodInfo: ext
                )
            }
            let resolved = resolveParameterizedType(selfType)
            if resolved != selfType {
                return try lookupConcreteMethodSymbol(
                    on: resolved,
                    name: name,
                    methodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                )
            }
            if let traitTargetCandidate = try lookupTraitTargetExtensionMethod(
                on: selfType,
                name: name,
                methodTypeArgs: methodTypeArgs,
                expectedMethodType: expectedMethodType
            ) {
                return traitTargetCandidate
            }
            return nil
            
        case .structure(let defId):
            let typeName = context.getName(defId) ?? ""
            let isGen = context.isGenericInstantiation(defId) ?? false
            let baseName = context.getTemplateName(defId) ?? typeName
            if name == "map",
               let mapCandidate = try instantiateIteratorMapFromExpectedType(
                baseType: selfType,
                methodTypeArgs: methodTypeArgs,
                expectedMethodType: expectedMethodType
               ) {
                return mapCandidate
            }
                if name == "fold",
                    let foldCandidate = try instantiateIteratorFoldFromExpectedType(
                     baseType: selfType,
                     methodTypeArgs: methodTypeArgs,
                     expectedMethodType: expectedMethodType
                    ) {
                     return foldCandidate
                }
            if let methods = extensionMethods[typeName],
               let entry = methodLookupCandidates(name).compactMap({ methods[$0] }).first {
                     if let ext = selectExtensionTemplateForBase(
                          baseType: selfType,
                          methodName: name,
                          methodTypeArgCount: methodTypeArgs.isEmpty ? nil : methodTypeArgs.count
                         ),
                         (!methodTypeArgs.isEmpty || context.containsGenericParameter(entry.symbol.type) || expectedMethodType != nil) {
                    let extensionTypeArgs: [Type]
                    if let info = layoutToTemplateInfo[typeName] {
                        extensionTypeArgs = info.args.map { normalizeTypeArgument($0) }
                    } else if let typeArgs = context.getTypeArguments(defId) {
                        extensionTypeArgs = typeArgs.map { normalizeTypeArgument($0) }
                    } else {
                        extensionTypeArgs = []
                    }
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: baseName,
                        genericArgs: extensionTypeArgs,
                        methodTypeArgs: try inferExtensionMethodTypeArgs(
                            methodInfo: ext,
                            baseType: selfType,
                            extensionTypeArgs: extensionTypeArgs,
                            providedMethodTypeArgs: methodTypeArgs,
                            expectedMethodType: expectedMethodType
                        ),
                        methodInfo: ext
                    )
                }
                if methodTypeArgs.isEmpty,
                   let expectedMethodType,
                   let matched = lookupInstantiatedExtensionMethodSymbol(
                    baseType: selfType,
                    methodName: name,
                    expectedMethodType: expectedMethodType
                   ) {
                    return copySymbolPreservingDefId(matched)
                }
                if let traitInfo = entry.trait,
                   let traitResolved = try instantiateTraitEntryMethod(
                    baseType: selfType,
                    traitInfo: traitInfo,
                    methodName: name,
                    methodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                   ) {
                    return traitResolved
                }
                if let expectedMethodType,
                   let candidates = remappedFunctionDefIds[entry.symbol.defId],
                   let matched = candidates.first(where: { methodTypeMatchesExpected($0.type, expected: expectedMethodType) }) {
                    let matchedType = resolveParameterizedType(matched.type)
                    return Symbol(
                        defId: matched.defId,
                        type: matchedType,
                        kind: .function,
                        methodKind: entry.symbol.methodKind
                    )
                }
                return copySymbolPreservingDefId(entry.symbol)
            }
            // Try generic extension methods - use stored templateName if available
                if let ext = selectExtensionTemplateForBase(
                    baseType: selfType,
                    methodName: name
                )
            {
                if let info = layoutToTemplateInfo[typeName] {
                    let normalizedArgs = info.args.map { normalizeTypeArgument($0) }
                    let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                        methodInfo: ext,
                        baseType: selfType,
                        extensionTypeArgs: normalizedArgs,
                        providedMethodTypeArgs: methodTypeArgs,
                        expectedMethodType: expectedMethodType
                    )
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        methodInfo: ext
                    )
                }
                if let typeArgs = context.getTypeArguments(defId) {
                    let normalizedArgs = typeArgs.map { normalizeTypeArgument($0) }
                    if normalizedArgs.count == ext.typeParams.count {
                    let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                        methodInfo: ext,
                        baseType: selfType,
                        extensionTypeArgs: normalizedArgs,
                        providedMethodTypeArgs: methodTypeArgs,
                        expectedMethodType: expectedMethodType
                    )
                    layoutToTemplateInfo[typeName] = (base: baseName, args: typeArgs)
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: baseName,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        methodInfo: ext
                    )
                    }
                }
                if isGen && context.getTypeArguments(defId) == nil && layoutToTemplateInfo[typeName]?.args == nil {
                    throw SemanticError(
                        .generic("Missing type arguments for generic instantiation '\(typeName)' while resolving method '\(name)'."),
                        span: SourceSpan(location: SourceLocation(line: currentLine, column: 1))
                    )
                }
            }
            if let traitTargetCandidate = try lookupTraitTargetExtensionMethod(
                on: selfType,
                name: name,
                methodTypeArgs: methodTypeArgs,
                expectedMethodType: expectedMethodType
            ) {
                return traitTargetCandidate
            }
            return nil
            
        case .union(let defId):
            let typeName = context.getName(defId) ?? ""
            let isGen = context.isGenericInstantiation(defId) ?? false
            let baseName = context.getTemplateName(defId) ?? typeName
            if name == "map",
               let mapCandidate = try instantiateIteratorMapFromExpectedType(
                baseType: selfType,
                methodTypeArgs: methodTypeArgs,
                expectedMethodType: expectedMethodType
               ) {
                return mapCandidate
            }
                if name == "fold",
                    let foldCandidate = try instantiateIteratorFoldFromExpectedType(
                     baseType: selfType,
                     methodTypeArgs: methodTypeArgs,
                     expectedMethodType: expectedMethodType
                    ) {
                     return foldCandidate
                }
            if let methods = extensionMethods[typeName],
               let entry = methodLookupCandidates(name).compactMap({ methods[$0] }).first {
                     if let ext = selectExtensionTemplateForBase(
                          baseType: selfType,
                          methodName: name,
                          methodTypeArgCount: methodTypeArgs.isEmpty ? nil : methodTypeArgs.count
                         ),
                         (!methodTypeArgs.isEmpty || context.containsGenericParameter(entry.symbol.type) || expectedMethodType != nil) {
                    let extensionTypeArgs: [Type]
                    if let info = layoutToTemplateInfo[typeName] {
                        extensionTypeArgs = info.args.map { normalizeTypeArgument($0) }
                    } else if let typeArgs = context.getTypeArguments(defId) {
                        extensionTypeArgs = typeArgs.map { normalizeTypeArgument($0) }
                    } else {
                        extensionTypeArgs = []
                    }
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: baseName,
                        genericArgs: extensionTypeArgs,
                        methodTypeArgs: try inferExtensionMethodTypeArgs(
                            methodInfo: ext,
                            baseType: selfType,
                            extensionTypeArgs: extensionTypeArgs,
                            providedMethodTypeArgs: methodTypeArgs,
                            expectedMethodType: expectedMethodType
                        ),
                        methodInfo: ext
                    )
                }
                if methodTypeArgs.isEmpty,
                   let expectedMethodType,
                   let matched = lookupInstantiatedExtensionMethodSymbol(
                    baseType: selfType,
                    methodName: name,
                    expectedMethodType: expectedMethodType
                   ) {
                    return copySymbolPreservingDefId(matched)
                }
                if let traitInfo = entry.trait,
                   let traitResolved = try instantiateTraitEntryMethod(
                    baseType: selfType,
                    traitInfo: traitInfo,
                    methodName: name,
                    methodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                   ) {
                    return traitResolved
                }
                if let expectedMethodType,
                   let candidates = remappedFunctionDefIds[entry.symbol.defId],
                   let matched = candidates.first(where: { methodTypeMatchesExpected($0.type, expected: expectedMethodType) }) {
                    let matchedType = resolveParameterizedType(matched.type)
                    return Symbol(
                        defId: matched.defId,
                        type: matchedType,
                        kind: .function,
                        methodKind: entry.symbol.methodKind
                    )
                }
                return copySymbolPreservingDefId(entry.symbol)
            }
            // Use stored templateName if available
                if let ext = selectExtensionTemplateForBase(
                    baseType: selfType,
                    methodName: name
                )
            {
                if let info = layoutToTemplateInfo[typeName] {
                    let normalizedArgs = info.args.map { normalizeTypeArgument($0) }
                    let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                        methodInfo: ext,
                        baseType: selfType,
                        extensionTypeArgs: normalizedArgs,
                        providedMethodTypeArgs: methodTypeArgs,
                        expectedMethodType: expectedMethodType
                    )
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        methodInfo: ext
                    )
                }
                if let typeArgs = context.getTypeArguments(defId) {
                    let normalizedArgs = typeArgs.map { normalizeTypeArgument($0) }
                    if normalizedArgs.count == ext.typeParams.count {
                    let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                        methodInfo: ext,
                        baseType: selfType,
                        extensionTypeArgs: normalizedArgs,
                        providedMethodTypeArgs: methodTypeArgs,
                        expectedMethodType: expectedMethodType
                    )
                    layoutToTemplateInfo[typeName] = (base: baseName, args: typeArgs)
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: baseName,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        methodInfo: ext
                    )
                    }
                }
                if isGen && context.getTypeArguments(defId) == nil && layoutToTemplateInfo[typeName]?.args == nil {
                    throw SemanticError(
                        .generic("Missing type arguments for generic instantiation '\(typeName)' while resolving method '\(name)'."),
                        span: SourceSpan(location: SourceLocation(line: currentLine, column: 1))
                    )
                }
            }
            if let traitTargetCandidate = try lookupTraitTargetExtensionMethod(
                on: selfType,
                name: name,
                methodTypeArgs: methodTypeArgs,
                expectedMethodType: expectedMethodType
            ) {
                return traitTargetCandidate
            }
            return nil
            
        case .pointer(let element):
            // Check intrinsic extension methods first
                if let extensions = input.genericTemplates.intrinsicExtensionMethods["Ptr"],
                    let ext = extensions.first(where: { $0.method.name == name })
            {
                return try instantiateIntrinsicExtensionMethod(
                    baseType: selfType,
                    structureName: "Ptr",
                    genericArgs: [element],
                    methodInfo: ext
                )
            }
            
            // Then check regular extension methods
                if let extensions = input.genericTemplates.extensionMethods["Ptr"],
                    let ext = selectExtensionTemplate(
                        extensions,
                        name: name,
                        extensionTypeArgCount: 1
                    )
            {
                let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                    methodInfo: ext,
                    baseType: selfType,
                    extensionTypeArgs: [element],
                    providedMethodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                )
                return try instantiateExtensionMethodFromEntry(
                    baseType: selfType,
                    structureName: "Ptr",
                    genericArgs: [element],
                    methodTypeArgs: resolvedMethodTypeArgs,
                    methodInfo: ext
                )
            }
            return nil
            
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64,
             .bool:
            let typeName = selfType.description
                if let methods = extensionMethods[typeName],
                    let entry = methodLookupCandidates(name).compactMap({ methods[$0] }).first {
                     if !methodTypeArgs.isEmpty,
                         let extensions = input.genericTemplates.extensionMethods[typeName],
                         let ext = selectExtensionTemplate(
                          extensions,
                          name: name,
                          methodTypeArgCount: methodTypeArgs.count,
                          extensionTypeArgCount: 0
                         ) {
                    let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                        methodInfo: ext,
                        baseType: selfType,
                        extensionTypeArgs: [],
                        providedMethodTypeArgs: methodTypeArgs,
                        expectedMethodType: expectedMethodType
                    )
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: typeName,
                        genericArgs: [],
                        methodTypeArgs: resolvedMethodTypeArgs,
                        methodInfo: ext
                    )
                }
                return copySymbolPreservingDefId(entry.symbol)
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

    private func normalizeTypeArgument(_ type: Type) -> Type {
        switch type {
        case .genericStruct(let template, let args):
            return .genericStruct(template: template, args: args.map { normalizeTypeArgument($0) })
        case .genericUnion(let template, let args):
            return .genericUnion(template: template, args: args.map { normalizeTypeArgument($0) })
        case .reference(let inner):
            return .reference(inner: normalizeTypeArgument(inner))
        case .weakReference(let inner):
            return .weakReference(inner: normalizeTypeArgument(inner))
        case .pointer(let element):
            return .pointer(element: normalizeTypeArgument(element))
        case .function(let params, let returns):
            let newParams = params.map { param in
                Parameter(
                    type: normalizeTypeArgument(param.type),
                    kind: param.kind
                )
            }
            return .function(parameters: newParams, returns: normalizeTypeArgument(returns))
        default:
            return type
        }
    }

    private func extensionLookupTypeNames(for baseType: Type) -> [String] {
        let resolvedBaseType = resolveParameterizedType(baseType)
        switch resolvedBaseType {
        case .structure(let defId):
            let concreteName = context.getName(defId) ?? ""
            if let templateName = context.getTemplateName(defId), templateName != concreteName {
                return [concreteName, templateName]
            }
            return [concreteName]
        case .genericStruct(let templateName, _):
            return [templateName]
        case .genericUnion(let templateName, _):
            return [templateName]
        case .union(let defId):
            let concreteName = context.getName(defId) ?? ""
            if let templateName = context.getTemplateName(defId), templateName != concreteName {
                return [concreteName, templateName]
            }
            return [concreteName]
        case .pointer:
            return ["Ptr"]
        default:
            return [resolvedBaseType.description]
        }
    }

    private func extensionStructureName(for baseType: Type) -> String {
        let resolvedBaseType = resolveParameterizedType(baseType)
        switch resolvedBaseType {
        case .structure(let defId):
            let name = context.getName(defId) ?? ""
            return context.getTemplateName(defId) ?? name
        case .genericStruct(let templateName, _):
            return templateName
        case .genericUnion(let templateName, _):
            return templateName
        case .union(let defId):
            let name = context.getName(defId) ?? ""
            return context.getTemplateName(defId) ?? name
        case .pointer:
            return "Ptr"
        default:
            return resolvedBaseType.description
        }
    }

    private func methodTypeMatchesExpected(_ candidate: Type, expected: Type?) -> Bool {
        guard let expected else { return true }
        if candidate == expected {
            return true
        }
        if !context.containsGenericParameter(expected) {
            return false
        }
        return typeMatchesExpectedPattern(actual: candidate, expected: expected)
    }

    private func typeMatchesExpectedPattern(actual: Type, expected: Type) -> Bool {
        if actual == expected {
            return true
        }
        switch expected {
        case .genericParameter:
            return true
        case .reference(let expectedInner):
            guard case .reference(let actualInner) = actual else { return false }
            return typeMatchesExpectedPattern(actual: actualInner, expected: expectedInner)
        case .weakReference(let expectedInner):
            guard case .weakReference(let actualInner) = actual else { return false }
            return typeMatchesExpectedPattern(actual: actualInner, expected: expectedInner)
        case .pointer(let expectedInner):
            guard case .pointer(let actualInner) = actual else { return false }
            return typeMatchesExpectedPattern(actual: actualInner, expected: expectedInner)
        case .function(let expectedParams, let expectedReturn):
            guard case .function(let actualParams, let actualReturn) = actual,
                  actualParams.count == expectedParams.count else {
                return false
            }
            for (actualParam, expectedParam) in zip(actualParams, expectedParams) {
                guard typeMatchesExpectedPattern(actual: actualParam.type, expected: expectedParam.type) else {
                    return false
                }
            }
            return typeMatchesExpectedPattern(actual: actualReturn, expected: expectedReturn)
        case .genericStruct(let expectedTemplate, let expectedArgs):
            let actualArgs: [Type]
            switch actual {
            case .genericStruct(let actualTemplate, let args):
                guard actualTemplate == expectedTemplate else { return false }
                actualArgs = args
            case .structure(let defId):
                guard context.getTemplateName(defId) == expectedTemplate,
                      let args = context.getTypeArguments(defId) else {
                    return false
                }
                actualArgs = args
            default:
                return false
            }
            guard actualArgs.count == expectedArgs.count else { return false }
            for (actualArg, expectedArg) in zip(actualArgs, expectedArgs) {
                guard typeMatchesExpectedPattern(actual: actualArg, expected: expectedArg) else {
                    return false
                }
            }
            return true
        case .genericUnion(let expectedTemplate, let expectedArgs):
            let actualArgs: [Type]
            switch actual {
            case .genericUnion(let actualTemplate, let args):
                guard actualTemplate == expectedTemplate else { return false }
                actualArgs = args
            case .union(let defId):
                guard context.getTemplateName(defId) == expectedTemplate,
                      let args = context.getTypeArguments(defId) else {
                    return false
                }
                actualArgs = args
            default:
                return false
            }
            guard actualArgs.count == expectedArgs.count else { return false }
            for (actualArg, expectedArg) in zip(actualArgs, expectedArgs) {
                guard typeMatchesExpectedPattern(actual: actualArg, expected: expectedArg) else {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }

    internal func lookupInstantiatedExtensionMethodSymbol(
        baseType: Type,
        methodName: String,
        expectedMethodType: Type? = nil
    ) -> Symbol? {
        let lookupTypeNames = extensionLookupTypeNames(for: baseType)
        var candidates: [DefId] = []
        var seenCandidateIds: Set<DefId> = []

        let appendCandidate: (DefId) -> Void = { [self] defId in
            guard !seenCandidateIds.contains(defId) else { return }
            if let symbolType = self.context.getSymbolType(defId) {
                guard self.methodTypeMatchesExpected(symbolType, expected: expectedMethodType) else {
                    return
                }
            } else if expectedMethodType != nil {
                return
            }
            seenCandidateIds.insert(defId)
            candidates.append(defId)
        }

        for typeName in lookupTypeNames {
            let key = "\(typeName).\(methodName)"
            if let direct = extensionMethodDefIds[key] {
                appendCandidate(direct)
            }
        }

        let resolvedDefId: DefId?
        if candidates.count == 1 {
            resolvedDefId = candidates.first
        } else if expectedMethodType == nil {
            resolvedDefId = candidates.first
        } else {
            resolvedDefId = nil
        }

        guard let defId = resolvedDefId else {
            return nil
        }
        let symbolType = context.getSymbolType(defId) ?? expectedMethodType ?? .void
        let symbolKind = context.getSymbolKind(defId) ?? .function
        let methodKind = context.getSymbolMethodKind(defId) ?? .normal
        return Symbol(defId: defId, type: symbolType, kind: symbolKind, methodKind: methodKind)
    }

    private func unifyGenericTypePattern(
        pattern: Type,
        actual: Type,
        typeParamNames: Set<String>,
        inferred: inout [String: Type]
    ) -> Bool {
        switch pattern {
        case .genericParameter(let name) where typeParamNames.contains(name):
            if let existing = inferred[name] {
                return existing == actual
            }
            inferred[name] = actual
            return true
        case .reference(let pInner):
            guard case .reference(let aInner) = actual else { return false }
            return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
        case .weakReference(let pInner):
            guard case .weakReference(let aInner) = actual else { return false }
            return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
        case .pointer(let pInner):
            guard case .pointer(let aInner) = actual else { return false }
            return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
        case .genericStruct(let pTemplate, let pArgs):
            let aArgs: [Type]
            switch actual {
            case .genericStruct(let aTemplate, let args):
                guard pTemplate == aTemplate else { return false }
                aArgs = args
            case .structure(let defId):
                guard context.getTemplateName(defId) == pTemplate,
                      let args = context.getTypeArguments(defId) else {
                    return false
                }
                aArgs = args
            default:
                return false
            }
            guard pArgs.count == aArgs.count else { return false }
            for (pArg, aArg) in zip(pArgs, aArgs) {
                guard unifyGenericTypePattern(pattern: pArg, actual: aArg, typeParamNames: typeParamNames, inferred: &inferred) else {
                    return false
                }
            }
            return true
        case .genericUnion(let pTemplate, let pArgs):
            let aArgs: [Type]
            switch actual {
            case .genericUnion(let aTemplate, let args):
                guard pTemplate == aTemplate else { return false }
                aArgs = args
            case .union(let defId):
                guard context.getTemplateName(defId) == pTemplate,
                      let args = context.getTypeArguments(defId) else {
                    return false
                }
                aArgs = args
            default:
                return false
            }
            guard pArgs.count == aArgs.count else { return false }
            for (pArg, aArg) in zip(pArgs, aArgs) {
                guard unifyGenericTypePattern(pattern: pArg, actual: aArg, typeParamNames: typeParamNames, inferred: &inferred) else {
                    return false
                }
            }
            return true
        case .function(let pParams, let pRet):
            guard case .function(let aParams, let aRet) = actual,
                  pParams.count == aParams.count else { return false }
            for (pParam, aParam) in zip(pParams, aParams) {
                guard unifyGenericTypePattern(pattern: pParam.type, actual: aParam.type, typeParamNames: typeParamNames, inferred: &inferred) else {
                    return false
                }
            }
            return unifyGenericTypePattern(pattern: pRet, actual: aRet, typeParamNames: typeParamNames, inferred: &inferred)
        default:
            return pattern == actual
        }
    }

    private func inferTraitExtensionTypeArgs(
        baseType: Type,
        methodInfo: GenericExtensionMethodTemplate,
        expectedMethodType: Type,
        methodTypeArgs: [Type]
    ) throws -> [Type]? {
        guard case .function(let actualParams, let actualReturn) = expectedMethodType else {
            return nil
        }

        var substitution: [String: Type] = ["Self": resolveParameterizedType(baseType)]
        let methodTypeParams = methodInfo.method.typeParameters
        if !methodTypeArgs.isEmpty {
            guard methodTypeParams.count == methodTypeArgs.count else {
                return nil
            }
            for (index, methodTypeParam) in methodTypeParams.enumerated() {
                substitution[methodTypeParam.name] = methodTypeArgs[index]
            }
        }

        let patternParams: [Parameter]
        let patternReturn: Type
        if let checkedParameters = methodInfo.checkedParameters,
           let checkedReturnType = methodInfo.checkedReturnType {
            patternParams = checkedParameters.map { param in
                Parameter(type: substituteType(param.type, substitution: substitution), kind: fromSymbolKindToPassKind(param.kind))
            }
            patternReturn = substituteType(checkedReturnType, substitution: substitution)
        } else {
            let params = try methodInfo.method.parameters.map { param -> Parameter in
                let paramType = try resolveTypeNode(param.type, substitution: substitution)
                return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
            }
            patternParams = params
            patternReturn = try resolveTypeNode(methodInfo.method.returnType, substitution: substitution)
        }

        guard patternParams.count == actualParams.count else {
            return nil
        }

        var typeParamNames = Set(methodInfo.typeParams.map { $0.name })
        if methodTypeArgs.isEmpty {
            typeParamNames.formUnion(methodTypeParams.map { $0.name })
        }
        var inferred: [String: Type] = [:]
        for (patternParam, actualParam) in zip(patternParams, actualParams) {
            if !unifyGenericTypePattern(
                pattern: patternParam.type,
                actual: actualParam.type,
                typeParamNames: typeParamNames,
                inferred: &inferred
            ) {
                return nil
            }
        }

        if !unifyGenericTypePattern(
            pattern: patternReturn,
            actual: actualReturn,
            typeParamNames: typeParamNames,
            inferred: &inferred
        ) {
            return nil
        }

        let ordered = methodInfo.typeParams.compactMap { inferred[$0.name] }
        return ordered.count == methodInfo.typeParams.count ? ordered : nil
    }

    private func inferExtensionMethodTypeArgs(
        methodInfo: GenericExtensionMethodTemplate,
        baseType: Type,
        extensionTypeArgs: [Type],
        providedMethodTypeArgs: [Type],
        expectedMethodType: Type?
    ) throws -> [Type] {
        if !providedMethodTypeArgs.isEmpty || methodInfo.method.typeParameters.isEmpty {
            return providedMethodTypeArgs
        }
        guard let expectedMethodType,
              case .function(let actualParams, let actualReturn) = expectedMethodType else {
            return providedMethodTypeArgs
        }

        var substitution: [String: Type] = ["Self": resolveParameterizedType(baseType)]
        for (index, typeParam) in methodInfo.typeParams.enumerated() where index < extensionTypeArgs.count {
            substitution[typeParam.name] = extensionTypeArgs[index]
        }

        let patternParams: [Parameter]
        let patternReturn: Type
        if let checkedParameters = methodInfo.checkedParameters,
           let checkedReturnType = methodInfo.checkedReturnType {
            patternParams = checkedParameters.map { param in
                Parameter(type: substituteType(param.type, substitution: substitution), kind: fromSymbolKindToPassKind(param.kind))
            }
            patternReturn = substituteType(checkedReturnType, substitution: substitution)
        } else {
            patternParams = try methodInfo.method.parameters.map { param in
                let paramType = try resolveTypeNode(param.type, substitution: substitution)
                return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
            }
            patternReturn = try resolveTypeNode(methodInfo.method.returnType, substitution: substitution)
        }

        guard patternParams.count == actualParams.count else {
            return providedMethodTypeArgs
        }

        let methodTypeParamNames = Set(methodInfo.method.typeParameters.map { $0.name })
        var inferred: [String: Type] = [:]
        for (patternParam, actualParam) in zip(patternParams, actualParams) {
            if !unifyGenericTypePattern(
                pattern: patternParam.type,
                actual: actualParam.type,
                typeParamNames: methodTypeParamNames,
                inferred: &inferred
            ) {
                return providedMethodTypeArgs
            }
        }

        if !unifyGenericTypePattern(
            pattern: patternReturn,
            actual: actualReturn,
            typeParamNames: methodTypeParamNames,
            inferred: &inferred
        ) {
            return providedMethodTypeArgs
        }

        let ordered = methodInfo.method.typeParameters.compactMap { inferred[$0.name] }
        return ordered.count == methodInfo.method.typeParameters.count ? ordered : providedMethodTypeArgs
    }

    private func extractTemplateTypeArgs(_ type: Type, templateName: String) -> [Type]? {
        let resolved = resolveParameterizedType(type)
        switch resolved {
        case .genericStruct(let template, let args) where template == templateName:
            return args
        case .genericUnion(let template, let args) where template == templateName:
            return args
        case .structure(let defId), .union(let defId):
            guard context.getTemplateName(defId) == templateName else {
                return nil
            }
            return context.getTypeArguments(defId)
        default:
            return nil
        }
    }

    private func instantiateIteratorMapFromExpectedType(
        baseType: Type,
        methodTypeArgs: [Type],
        expectedMethodType: Type?
    ) throws -> Symbol? {
        guard let expectedMethodType,
              case .function(_, let expectedReturn) = expectedMethodType,
              let mappedArgs = extractTemplateTypeArgs(expectedReturn, templateName: "MappedIterator"),
              mappedArgs.count == 3,
              let iteratorExtensions = input.genericTemplates.extensionMethods["Iterator"],
              let mapTemplate = selectExtensionTemplate(iteratorExtensions, name: "map") else {
            return nil
        }

        let iteratorElementType = mappedArgs[0]
        let mappedElementType = mappedArgs[1]
        let resolvedMethodTypeArgs = methodTypeArgs.isEmpty ? [mappedElementType] : methodTypeArgs

        return try instantiateExtensionMethodFromEntry(
            baseType: resolveParameterizedType(baseType),
            structureName: extensionStructureName(for: baseType),
            genericArgs: [iteratorElementType],
            methodTypeArgs: resolvedMethodTypeArgs,
            methodInfo: mapTemplate
        )
    }

    private func inferIteratorElementType(from baseType: Type) -> Type? {
        let resolved = resolveParameterizedType(baseType)
        switch resolved {
        case .structure(let defId), .union(let defId):
            return context.getTypeArguments(defId)?.first
        case .genericStruct(_, let args), .genericUnion(_, let args):
            return args.first
        default:
            return nil
        }
    }

    private func instantiateIteratorFoldFromExpectedType(
        baseType: Type,
        methodTypeArgs: [Type],
        expectedMethodType: Type?
    ) throws -> Symbol? {
        guard let expectedMethodType,
              case .function(_, let expectedReturn) = expectedMethodType,
              let iteratorElementType = inferIteratorElementType(from: baseType),
              let iteratorExtensions = input.genericTemplates.extensionMethods["Iterator"],
              let foldTemplate = selectExtensionTemplate(iteratorExtensions, name: "fold") else {
            return nil
        }

        let accumulatorType = methodTypeArgs.first ?? expectedReturn
        return try instantiateExtensionMethodFromEntry(
            baseType: resolveParameterizedType(baseType),
            structureName: extensionStructureName(for: baseType),
            genericArgs: [iteratorElementType],
            methodTypeArgs: [accumulatorType],
            methodInfo: foldTemplate
        )
    }

    private func instantiateTraitEntryMethod(
        baseType: Type,
        traitInfo: TypedTraitConformance,
        methodName: String,
        methodTypeArgs: [Type],
        expectedMethodType: Type?
    ) throws -> Symbol? {
        guard let methods = input.genericTemplates.extensionMethods[traitInfo.traitName],
              let methodInfo = selectExtensionTemplate(
                methods,
                name: methodName,
                methodTypeArgCount: methodTypeArgs.isEmpty ? nil : methodTypeArgs.count
              ) else {
            return nil
        }

        let resolvedBaseType = resolveParameterizedType(baseType)
        let inferredTypeArgs = try inferTraitExtensionTypeArgs(
            baseType: resolvedBaseType,
            methodInfo: methodInfo,
            expectedMethodType: expectedMethodType ?? entryLikeExpectedMethodType(baseType: resolvedBaseType, methodName: methodName),
            methodTypeArgs: methodTypeArgs
        )

        let traitTypeArgs = traitInfo.traitTypeArgs.map { resolveParameterizedType($0) }
        let extensionTypeArgs: [Type]
        if let inferredTypeArgs, inferredTypeArgs.count == methodInfo.typeParams.count {
            extensionTypeArgs = inferredTypeArgs
        } else if traitTypeArgs.count == methodInfo.typeParams.count {
            extensionTypeArgs = traitTypeArgs
        } else {
            return nil
        }

        let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
            methodInfo: methodInfo,
            baseType: resolvedBaseType,
            extensionTypeArgs: extensionTypeArgs,
            providedMethodTypeArgs: methodTypeArgs,
            expectedMethodType: expectedMethodType
        )

        return try instantiateExtensionMethodFromEntry(
            baseType: resolvedBaseType,
            structureName: extensionStructureName(for: resolvedBaseType),
            genericArgs: extensionTypeArgs,
            methodTypeArgs: resolvedMethodTypeArgs,
            methodInfo: methodInfo
        )
    }

    private func entryLikeExpectedMethodType(baseType: Type, methodName: String) -> Type {
        // Best-effort approximation used only for trait-entry instantiation when call-site
        // expected type is unavailable at this point.
        return .function(parameters: [Parameter(type: baseType, kind: .byVal)], returns: .genericParameter(name: methodName))
    }

    private func lookupTraitTargetExtensionMethod(
        on selfType: Type,
        name: String,
        methodTypeArgs: [Type],
        expectedMethodType: Type?
    ) throws -> Symbol? {
        guard let expectedMethodType else {
            return nil
        }

        let resolvedBaseType = resolveParameterizedType(selfType)
        let structureName = extensionStructureName(for: resolvedBaseType)
        let nameCandidates = methodLookupCandidates(name)
        var matches: [Symbol] = []

        for (traitName, methods) in input.genericTemplates.extensionMethods {
            guard input.genericTemplates.traits[traitName] != nil else {
                continue
            }
            for methodInfo in methods where nameCandidates.contains(methodInfo.method.name) {
                guard let inferredTypeArgs = try inferTraitExtensionTypeArgs(
                    baseType: resolvedBaseType,
                    methodInfo: methodInfo,
                    expectedMethodType: expectedMethodType,
                    methodTypeArgs: methodTypeArgs
                ) else {
                    continue
                }
                let resolvedMethodTypeArgs = try inferExtensionMethodTypeArgs(
                    methodInfo: methodInfo,
                    baseType: resolvedBaseType,
                    extensionTypeArgs: inferredTypeArgs,
                    providedMethodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedMethodType
                )
                let methodSymbol = try instantiateExtensionMethodFromEntry(
                    baseType: resolvedBaseType,
                    structureName: structureName,
                    genericArgs: inferredTypeArgs,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    methodInfo: methodInfo
                )
                matches.append(methodSymbol)
            }
        }

        if matches.count > 1 {
            throw SemanticError(
                .generic("Ambiguous method '\(name)' for type '\(selfType.description)' via trait extensions"),
                span: SourceSpan(location: SourceLocation(line: currentLine, column: 1))
            )
        }

        return matches.first
    }
    
    // MARK: - Helper Methods
    
    /// Checks if a type supports builtin equality comparison.
    internal func isBuiltinEqualityComparable(_ type: Type) -> Bool {
        return SemaUtils.isBuiltinEqualityComparable(type)
    }
    
    /// Checks if a type supports builtin ordering comparison.
    internal func isBuiltinOrderingComparable(_ type: Type) -> Bool {
        return SemaUtils.isBuiltinOrderingComparable(type)
    }

    /// Checks if a type supports builtin arithmetic operations.
    internal func isBuiltinArithmeticType(_ type: Type) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64:
            return true
        default:
            return false
        }
    }

    // MARK: - Trait Object Method Resolution

    /// Returns an ordered list of trait methods for vtable layout.
    /// Parent trait methods come first (in declaration order), then the trait's own methods.
    /// This mirrors the logic in TypeCheckerTraits.swift's orderedTraitMethods.
    internal func orderedTraitMethods(_ traitName: String) -> [(name: String, signature: TraitMethodSignature)] {
        var visited: Set<String> = []
        return orderedTraitMethodsHelper(traitName, visited: &visited)
    }

    private func orderedTraitMethodsHelper(
        _ traitName: String,
        visited: inout Set<String>
    ) -> [(name: String, signature: TraitMethodSignature)] {
        if visited.contains(traitName) { return [] }
        visited.insert(traitName)

        if SemaUtils.isBuiltinTrait(traitName) { return [] }

        guard let decl = input.genericTemplates.traits[traitName] else {
            return []
        }

        var result: [(name: String, signature: TraitMethodSignature)] = []
        var seen: Set<String> = []

        // Parent trait methods first
        for parent in decl.superTraits {
            let parentMethods = orderedTraitMethodsHelper(parent.baseName, visited: &visited)
            for entry in parentMethods where !seen.contains(entry.name) {
                result.append(entry)
                seen.insert(entry.name)
            }
        }

        // Then this trait's own methods
        for m in decl.methods where !seen.contains(m.name) {
            result.append((name: m.name, signature: m))
            seen.insert(m.name)
        }

        return result
    }

    /// Computes the vtable index for a method in a trait.
    /// Methods are ordered by declaration order, with parent trait methods first.
    internal func vtableMethodIndex(traitName: String, methodName: String) -> Int? {
        let ordered = orderedTraitMethods(traitName)
        return ordered.firstIndex(where: { $0.name == methodName })
    }

    /// Extracts the inner trait object type from a type, unwrapping reference if needed.
    /// Returns (traitName, typeArgs) if the type is a trait object or reference to trait object.
    internal func extractTraitObjectType(_ type: Type) -> (traitName: String, typeArgs: [Type])? {
        switch type {
        case .traitObject(let traitName, let typeArgs):
            return (traitName, typeArgs)
        case .reference(let inner):
            if case .traitObject(let traitName, let typeArgs) = inner {
                return (traitName, typeArgs)
            }
            return nil
        default:
            return nil
        }
    }

    /// Creates a zero literal for a builtin numeric type.
    internal func makeZeroLiteral(for type: Type) -> TypedExpressionNode {
        switch type {
        case .float32, .float64:
            return .floatLiteral(value: "0.0", type: type)
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64:
            return .integerLiteral(value: "0", type: type)
        default:
            return .integerLiteral(value: "0", type: .int)
        }
    }
}

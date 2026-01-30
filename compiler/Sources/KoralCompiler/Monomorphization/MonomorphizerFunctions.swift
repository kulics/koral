// MonomorphizerFunctions.swift
// Extension for Monomorphizer that handles function and extension method instantiation.
// This file contains methods for instantiating generic function templates and
// extension methods with concrete type arguments.

import Foundation

// MARK: - Function Instantiation Extension

extension Monomorphizer {
    
    // MARK: - Function Instantiation
    
    /// Instantiates a generic function template with concrete type arguments.
    /// - Parameters:
    ///   - template: The generic function template
    ///   - args: The concrete type arguments
    /// - Returns: A tuple of (mangled name, function type)
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
        
        // Calculate mangled name
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
            // Fallback: use abort (this shouldn't happen in normal operation)
            typedBody = .intrinsicCall(.abort)
        }
        
        // Skip intrinsic functions
        let intrinsicNames = [
            "alloc_memory", "dealloc_memory", "copy_memory", "move_memory", "ref_count",
            "init_memory", "deinit_memory", "take_memory", "offset_ptr", "null_ptr",
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
        
        return try instantiateExtensionMethodFromEntry(
            baseType: resolvedBaseType,
            structureName: structureName,
            genericArgs: typeArgs,
            methodTypeArgs: methodTypeArgs,
            methodInfo: template
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
        
        // Calculate mangled name (include method type args if present)
        let argLayoutKeys = genericArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
        let methodArgLayoutKeys = methodTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
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
            return makeSymbol(name: cachedName, type: cachedType, kind: .function, methodKind: kind)
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
            let kind = getCompilerMethodKind(method.name)
            return makeSymbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
        }
        
        // IMPORTANT: Cache the function BEFORE processing the body to prevent infinite recursion
        // This allows recursive methods (like rehash calling insert, insert calling rehash) to work
        instantiatedFunctions[key] = (mangledName, functionType)
        
        // Get the typed body from the declaration-time checked body
        let typedBody: TypedExpressionNode
        if let checkedBody = methodInfo.checkedBody {
            // Use the declaration-time checked body and substitute types
            let substitutedBody = substituteTypesInExpression(checkedBody, substitution: typeSubstitution)
            typedBody = resolveTypesInExpression(substitutedBody)
        } else {
            // Fallback: create a placeholder body (this shouldn't happen in normal operation)
            typedBody = createPlaceholderBody(returnType: returnType)
        }
        
        // Generate global function if not already generated
        if !generatedLayouts.contains(mangledName) {
            generatedLayouts.insert(mangledName)
            let kind = getCompilerMethodKind(method.name)
            let functionNode = TypedGlobalNode.globalFunction(
                identifier: makeSymbol(
                    name: mangledName, type: functionType, kind: .function, methodKind: kind),
                parameters: params,
                body: typedBody
            )
            generatedNodes.append(functionNode)
        }
        
        let kind = getCompilerMethodKind(method.name)
        return makeSymbol(name: mangledName, type: functionType, kind: .function, methodKind: kind)
    }
    
    /// Creates a placeholder body for methods that need re-checking.
    internal func createPlaceholderBody(returnType: Type) -> TypedExpressionNode {
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
        let mangledName = "\(structureName)_\(argLayoutKeys)_\(method.name)"
        let key = "ext:\(mangledName)"
        
        if let (cachedName, cachedType) = instantiatedFunctions[key] {
            let kind = getCompilerMethodKind(method.name)
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
        let kind = getCompilerMethodKind(method.name)
        return makeSymbol(name: mangledName, type: funcType, kind: .function, methodKind: kind)
    }
    
    // MARK: - Method Lookup
    
    /// Looks up a concrete method symbol on a type.
    internal func lookupConcreteMethodSymbol(on selfType: Type, name: String, methodTypeArgs: [Type] = []) throws -> Symbol? {
        switch selfType {
        case .reference(let inner):
            // For reference types, look up the method on the inner type
            return try lookupConcreteMethodSymbol(on: inner, name: name, methodTypeArgs: methodTypeArgs)

        case .genericStruct(let template, let args):
            let resolvedArgs = args.map { resolveParameterizedType($0) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return nil
            }
            if let extensions = input.genericTemplates.extensionMethods[template],
               let ext = extensions.first(where: { $0.method.name == name })
            {
                let resolvedBase = resolveParameterizedType(selfType)
                return try instantiateExtensionMethodFromEntry(
                    baseType: resolvedBase,
                    structureName: template,
                    genericArgs: resolvedArgs,
                    methodTypeArgs: methodTypeArgs,
                    methodInfo: ext
                )
            }
            let resolved = resolveParameterizedType(selfType)
            if resolved != selfType {
                return try lookupConcreteMethodSymbol(on: resolved, name: name, methodTypeArgs: methodTypeArgs)
            }
            return nil

        case .genericUnion(let template, let args):
            let resolvedArgs = args.map { resolveParameterizedType($0) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return nil
            }
            if let extensions = input.genericTemplates.extensionMethods[template],
               let ext = extensions.first(where: { $0.method.name == name })
            {
                let resolvedBase = resolveParameterizedType(selfType)
                return try instantiateExtensionMethodFromEntry(
                    baseType: resolvedBase,
                    structureName: template,
                    genericArgs: resolvedArgs,
                    methodTypeArgs: methodTypeArgs,
                    methodInfo: ext
                )
            }
            let resolved = resolveParameterizedType(selfType)
            if resolved != selfType {
                return try lookupConcreteMethodSymbol(on: resolved, name: name, methodTypeArgs: methodTypeArgs)
            }
            return nil
            
        case .structure(let defId):
            let typeName = context.getName(defId) ?? ""
            let qualifiedTypeName = context.getQualifiedName(defId) ?? typeName
            let isGen = context.isGenericInstantiation(defId) ?? false
            if let methods = extensionMethods[typeName], let sym = methods[name] {
                // Generate mangled name for the method (include method type args if present)
                // Use qualifiedTypeName to include module path
                let methodArgLayoutKeys = methodTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                let mangledName = methodTypeArgs.isEmpty ? "\(qualifiedTypeName)_\(name)" : "\(qualifiedTypeName)_\(name)_\(methodArgLayoutKeys)"
                return copySymbolWithNewDefId(sym, newName: mangledName, newModulePath: [])
            }
            // Try generic extension methods - use stored templateName if available
            let baseName = context.getTemplateName(defId) ?? typeName
            if let extensions = input.genericTemplates.extensionMethods[baseName],
               let ext = extensions.first(where: { $0.method.name == name })
            {
                if let info = layoutToTemplateInfo[typeName] {
                    let normalizedArgs = info.args.map { normalizeTypeArgument($0) }
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: methodTypeArgs,
                        methodInfo: ext
                    )
                }
                if let typeArgs = context.getTypeArguments(defId) {
                    let normalizedArgs = typeArgs.map { normalizeTypeArgument($0) }
                    if normalizedArgs.count == ext.typeParams.count {
                    layoutToTemplateInfo[typeName] = (base: baseName, args: typeArgs)
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: baseName,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: methodTypeArgs,
                        methodInfo: ext
                    )
                    }
                }
                if isGen && context.getTypeArguments(defId) == nil && layoutToTemplateInfo[typeName]?.args == nil {
                    throw SemanticError(
                        .generic("Missing type arguments for generic instantiation '\(typeName)' while resolving method '\(name)'."),
                        line: currentLine
                    )
                }
            }
            return nil
            
        case .union(let defId):
            let typeName = context.getName(defId) ?? ""
            let qualifiedTypeName = context.getQualifiedName(defId) ?? typeName
            let isGen = context.isGenericInstantiation(defId) ?? false
            if let methods = extensionMethods[typeName], let sym = methods[name] {
                // Generate mangled name for the method (include method type args if present)
                // Use qualifiedTypeName to include module path
                let methodArgLayoutKeys = methodTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                let mangledName = methodTypeArgs.isEmpty ? "\(qualifiedTypeName)_\(name)" : "\(qualifiedTypeName)_\(name)_\(methodArgLayoutKeys)"
                return copySymbolWithNewDefId(sym, newName: mangledName, newModulePath: [])
            }
            // Use stored templateName if available
            let baseName = context.getTemplateName(defId) ?? typeName
            if let extensions = input.genericTemplates.extensionMethods[baseName],
               let ext = extensions.first(where: { $0.method.name == name })
            {
                if let info = layoutToTemplateInfo[typeName] {
                    let normalizedArgs = info.args.map { normalizeTypeArgument($0) }
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: info.base,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: methodTypeArgs,
                        methodInfo: ext
                    )
                }
                if let typeArgs = context.getTypeArguments(defId) {
                    let normalizedArgs = typeArgs.map { normalizeTypeArgument($0) }
                    if normalizedArgs.count == ext.typeParams.count {
                    layoutToTemplateInfo[typeName] = (base: baseName, args: typeArgs)
                    return try instantiateExtensionMethodFromEntry(
                        baseType: selfType,
                        structureName: baseName,
                        genericArgs: normalizedArgs,
                        methodTypeArgs: methodTypeArgs,
                        methodInfo: ext
                    )
                    }
                }
                if isGen && context.getTypeArguments(defId) == nil && layoutToTemplateInfo[typeName]?.args == nil {
                    throw SemanticError(
                        .generic("Missing type arguments for generic instantiation '\(typeName)' while resolving method '\(name)'."),
                        line: currentLine
                    )
                }
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
               let ext = extensions.first(where: { $0.method.name == name })
            {
                return try instantiateExtensionMethodFromEntry(
                    baseType: selfType,
                    structureName: "Ptr",
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
                return copySymbolWithNewDefId(sym, newName: mangledName, newModulePath: [])
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
        case .pointer(let element):
            return .pointer(element: normalizeTypeArgument(element))
        default:
            return type
        }
    }
    
    // MARK: - Helper Methods
    
    /// Extracts the method name from a mangled name (e.g., "Float32_to_bits" -> "to_bits")
    internal func extractMethodName(_ mangledName: String) -> String {
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
    internal func isBuiltinEqualityComparable(_ type: Type) -> Bool {
        return SemaUtils.isBuiltinEqualityComparable(type)
    }
    
    /// Checks if a type supports builtin ordering comparison.
    internal func isBuiltinOrderingComparable(_ type: Type) -> Bool {
        return SemaUtils.isBuiltinOrderingComparable(type)
    }
}

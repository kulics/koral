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
    
    // MARK: - Method Lookup
    
    /// Looks up a concrete method symbol on a type.
    internal func lookupConcreteMethodSymbol(on selfType: Type, name: String, methodTypeArgs: [Type] = []) throws -> Symbol? {
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
                if let extensions = input.genericTemplates.extensionMethods[info.base] {
                    if let ext = extensions.first(where: { $0.method.name == name }) {
                        do {
                            let result = try instantiateExtensionMethodFromEntry(
                                baseType: selfType,
                                structureName: info.base,
                                genericArgs: info.args,
                                methodTypeArgs: methodTypeArgs,
                                methodInfo: ext
                            )
                            return result
                        } catch {
                            return nil
                        }
                    }
                }
            }
            // If not found in layoutToTemplateInfo, try to extract base name from the type name
            // This handles cases where the type was instantiated but not yet registered in layoutToTemplateInfo
            if isGen {
                // Extract base name from mangled name (e.g., "List_I" -> "List")
                let baseName = typeName.split(separator: "_").first.map(String.init) ?? typeName
                if let extensions = input.genericTemplates.extensionMethods[baseName],
                   let ext = extensions.first(where: { $0.method.name == name })
                {
                    // Try to extract type args from the type's members
                    // For now, use the decl's members to reconstruct type args
                    var typeArgs: [Type] = []
                    if let _ = input.genericTemplates.structTemplates[baseName] {
                        // Extract type args from the layout name suffix
                        let suffix = String(typeName.dropFirst(baseName.count + 1)) // Remove "BaseName_"
                        let argLayoutKeys = suffix.split(separator: "_").map(String.init)
                        // Try to reconstruct types from layout keys
                        for key in argLayoutKeys {
                            if let builtinType = SemaUtils.resolveBuiltinType(key) {
                                typeArgs.append(builtinType)
                            } else if key == "I" {
                                typeArgs.append(.int)
                            } else if key == "U" {
                                typeArgs.append(.uint)
                            } else if key == "B" {
                                typeArgs.append(.bool)
                            } else if key == "F32" {
                                typeArgs.append(.float32)
                            } else if key == "F64" {
                                typeArgs.append(.float64)
                            } else {
                                // Assume it's a struct type
                                let structDecl = StructDecl(
                                    name: key,
                                    modulePath: [],
                                    sourceFile: "",
                                    access: .default,
                                    members: [],
                                    isGenericInstantiation: key.contains("_")
                                )
                                typeArgs.append(.structure(decl: structDecl))
                            }
                        }
                    }
                    if typeArgs.count == ext.typeParams.count {
                        // Register in layoutToTemplateInfo for future lookups
                        layoutToTemplateInfo[typeName] = (base: baseName, args: typeArgs)
                        return try instantiateExtensionMethodFromEntry(
                            baseType: selfType,
                            structureName: baseName,
                            genericArgs: typeArgs,
                            methodTypeArgs: methodTypeArgs,
                            methodInfo: ext
                        )
                    }
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

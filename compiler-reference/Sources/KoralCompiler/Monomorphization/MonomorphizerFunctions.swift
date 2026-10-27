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

    private func preservedPassKind(
        for parameterType: TypeNode
    ) -> PassKind {
        switch parameterType {
        case .reference(_, let mutable, _):
            return mutable ? .byMutRef : .byRef
        default:
            return .byVal
        }
    }

    private func preservedParameters(
        resolvedParams: [Symbol],
        declaredParams: [(name: String, mutable: Bool, type: TypeNode, named: Bool, defaultValue: ExpressionNode?)]
    ) -> [Parameter] {
        zip(resolvedParams, declaredParams).map { resolved, declared in
            Parameter(type: resolved.type, kind: preservedPassKind(for: declared.type))
        }
    }



    internal func alignMethodReferenceBase(_ base: TypedExpressionNode, to methodType: Type) -> TypedExpressionNode {
        guard case .function(let params, _) = methodType,
              let receiverType = params.first?.type else {
            return base
        }

        if base.type == receiverType {
            return base
        }

        switch (base.type, receiverType) {
        case (.mutableReference(let inner), .reference(let expectedInner)) where inner == expectedInner:
            return base
        case (.borrowedReference(let inner), .reference(let expectedInner)) where inner == expectedInner:
            return base
        case (.mutableBorrowedReference(let inner), .reference(let expectedInner)) where inner == expectedInner:
            return base
        case (.mutableBorrowedReference(let inner), .borrowedReference(let expectedInner)) where inner == expectedInner:
            return base
        case (.mutableWeakReference(let inner), .weakReference(let expectedInner)) where inner == expectedInner:
            return base
        case (_, .reference(let inner)) where inner == base.type:
            return .referenceExpression(expression: base, type: receiverType)
        case (_, .mutableReference(let inner)) where inner == base.type:
            return .referenceExpression(expression: base, type: receiverType)
        case (_, .borrowedReference(let inner)) where inner == base.type:
            return .referenceExpression(expression: base, type: receiverType)
        case (_, .mutableBorrowedReference(let inner)) where inner == base.type:
            return .referenceExpression(expression: base, type: receiverType)
        case (_, .weakReference(let inner)) where inner == base.type:
            return .referenceExpression(expression: base, type: receiverType)
        case (_, .mutableWeakReference(let inner)) where inner == base.type:
            return .referenceExpression(expression: base, type: receiverType)
        case (.reference(let inner), _) where inner == receiverType:
            return .derefExpression(expression: base, type: inner)
        case (.mutableReference(let inner), _) where inner == receiverType:
            return .derefExpression(expression: base, type: inner)
        case (.borrowedReference(let inner), _) where inner == receiverType:
            return .derefExpression(expression: base, type: inner)
        case (.mutableBorrowedReference(let inner), _) where inner == receiverType:
            return .derefExpression(expression: base, type: inner)
        case (.weakReference(let inner), _) where inner == receiverType:
            return .derefExpression(expression: base, type: inner)
        case (.mutableWeakReference(let inner), _) where inner == receiverType:
            return .derefExpression(expression: base, type: inner)
        default:
            break
        }

        if case .referenceExpression(let inner, _) = base {
            if inner.type == receiverType {
                return inner
            }
            switch (inner.type, receiverType) {
            case (.mutableReference(let innerType), .reference(let expectedInner)) where innerType == expectedInner:
                return inner
            case (.borrowedReference(let innerType), .reference(let expectedInner)) where innerType == expectedInner:
                return inner
            case (.mutableBorrowedReference(let innerType), .reference(let expectedInner)) where innerType == expectedInner:
                return inner
            case (.mutableBorrowedReference(let innerType), .borrowedReference(let expectedInner)) where innerType == expectedInner:
                return inner
            case (.mutableWeakReference(let innerType), .weakReference(let expectedInner)) where innerType == expectedInner:
                return inner
            default:
                break
            }
        }

        return base
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
        
        // Resolve to the latest template snapshot from registry when available.
        // Instantiation requests may carry an earlier copy with checkedBody == nil
        // if they were recorded before declaration-time body checking finalized.
        let resolvedTemplate: GenericFunctionTemplate
        if template.checkedBody == nil {
            if let latestByDefId = input.genericTemplates.functionTemplates.values.first(where: {
                $0.defId == template.defId && $0.checkedBody != nil
            }) {
                resolvedTemplate = latestByDefId
            } else if let latestByName = input.genericTemplates.functionTemplates[templateName],
                      latestByName.checkedBody != nil {
                resolvedTemplate = latestByName
            } else {
                resolvedTemplate = template
            }
        } else {
            resolvedTemplate = template
        }

        // Create type substitution map
        var typeSubstitution: [String: Type] = [:]
        for (i, paramInfo) in resolvedTemplate.typeParameters.enumerated() {
            typeSubstitution[paramInfo.name] = args[i]
        }
        
        // Resolve parameters and return type
        let resolvedReturnType = try resolveTypeNode(resolvedTemplate.returnType, substitution: typeSubstitution)
        let resolvedParams: [Symbol]
        if let checkedParams = resolvedTemplate.checkedParameters {
            resolvedParams = checkedParams.map { param in
                let paramType = substituteType(param.type, substitution: typeSubstitution)
                return copySymbolPreservingDefId(param, newType: paramType)
            }
        } else {
            resolvedParams = try resolvedTemplate.parameters.map { param -> Symbol in
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
            parameters: preservedParameters(
                resolvedParams: resolvedParams,
                declaredParams: resolvedTemplate.parameters
            ),
            returns: resolvedReturnType)
        
        // Skip code generation if function type still contains generic parameters
        if context.containsGenericParameter(functionType) {
            return ("", functionType)
        }

        if input.genericTemplates.intrinsicGenericFunctions.contains(templateName) {
            return (mangledName, functionType)
        }
        
        // Cache early to support recursion
        instantiatedFunctions[key] = (mangledName, functionType)
        
        // Type-check the body with substituted types
        // Note: In the current implementation, we use the pre-checked body from declaration-time
        // and substitute types. For full correctness, we would need to re-check with concrete types.
        let typedBody: TypedExpressionNode
        if let checkedBody = resolvedTemplate.checkedBody {
            // Use the declaration-time checked body and substitute types
            let substitutedBody = substituteTypesInExpression(checkedBody, substitution: typeSubstitution)
            typedBody = resolveTypesInExpression(substitutedBody)
        } else {
            fatalError("Monomorphizer invariant violated: missing checkedBody for generic function template '\(templateName)' (defId=\(resolvedTemplate.defId.id))")
        }
        
        // Generate global function if not already generated
        if !generatedLayouts.contains(mangledName) {
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
        let resolvedBaseType = canonicalReferenceLikeBaseType(resolveParameterizedType(baseType))
        
        // Derive the structure name from the base type
        let structureName: String
        switch resolvedBaseType {
        case .structure(let defId):
            let name = context.getName(defId) ?? ""
            // Use stored templateName if available, otherwise fall back to full name
            structureName = context.getTemplateName(defId) ?? name
        case .genericStruct(_, _):
            structureName = templateName
        case .genericEnum(_, _):
            structureName = templateName
        case .`enum`(let defId):
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
               let extensions = input.genericTemplates.extensionMethods[context.methodOwner(of: baseType)],
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

    private func canonicalReferenceLikeBaseType(_ baseType: Type) -> Type {
        switch baseType {
        case .borrowedReference(let inner):
            return .reference(inner: inner)
        case .mutableBorrowedReference(let inner):
            return .mutableReference(inner: inner)
        default:
            return baseType
        }
    }

    private func registerInstantiatedExtensionMethodLookup(
        baseType: Type,
        structureName: String,
        methodBaseName: String,
        methodTypeArgs: [Type] = [],
        templateMethodDefId: DefId? = nil,
        generatedSymbol: Symbol,
        functionType: Type? = nil,
        conformanceTraitName: String?,
        conformanceTraitDefId: DefId?
    ) {
        if receiverMethodDispatch[generatedSymbol.defId] == nil {
            receiverMethodDispatch[generatedSymbol.defId] = ReceiverMethodDispatchInfo(
                methodDefId: generatedSymbol.defId,
                methodName: methodBaseName,
                owner: .concreteType(ownerType: baseType),
                conformanceTraitName: conformanceTraitName,
                conformanceTraitDefId: conformanceTraitDefId,
                traitMethodDefId: receiverMethodDispatch[templateMethodDefId ?? .invalid]?.traitMethodDefId
            )
        }

        instantiatedMethodDefIds.insert(generatedSymbol.defId)

        // Register under the DECLARATION's DefId (rustc: Instance keyed by the
        // item's DefId + GenericArgs). The template's DefId is the identity that
        // call sites carry in `methodReference.method.defId`.
        if let templateDefId = templateMethodDefId {
            let fullKey = context.receiverMethodKey(baseType, templateDefId, methodTypeArgs: methodTypeArgs)
            extensionMethodDefIds[fullKey] = generatedSymbol.defId

            // Register remap: template DefId -> instantiated DefId, so identity-based
            // lookup can find the instantiation of a specific declaration.
            if let functionType {
                remappedFunctionDefIds[templateDefId, default: []].append(
                    (defId: generatedSymbol.defId, type: functionType)
                )
                // Also register under the trait method's DefId for dual-key lookup.
                if let traitMethodDefId = receiverMethodDispatch[templateDefId]?.traitMethodDefId {
                    remappedFunctionDefIds[traitMethodDefId, default: []].append(
                        (defId: generatedSymbol.defId, type: functionType)
                    )
                    // Dual-key in the identity map: trait method references carry
                    // the trait method's DefId, so register under that too.
                    let traitKey = context.receiverMethodKey(baseType, traitMethodDefId, methodTypeArgs: methodTypeArgs)
                    extensionMethodDefIds[traitKey] = generatedSymbol.defId
                }
            }
        }
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
            case .structure(let defId), .`enum`(let defId):
                return context.getTypeArguments(defId)?.count ?? 0
            case .genericStruct(_, let args), .genericEnum(_, let args):
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
        // The owner's declaration identity joins the mangle, exactly as a type's
        // own C name does (`Box_I_d184` -- see SemaUtils.makeLayoutName). Two
        // modules may each declare `Box`, so `Box_I_stamp` alone names two
        // different methods and one C definition answers for both.
        let ownerSuffix: String
        switch context.methodOwner(of: baseType) {
        case .decl(let ownerDefId):
            ownerSuffix = ownerDefId.isValid ? "_d\(ownerDefId.id)" : ""
        case .builtin:
            ownerSuffix = ""
        }
        if genericArgs.isEmpty {
            if methodTypeArgs.isEmpty {
                mangledName = "\(structureName)_\(methodBaseName)\(ownerSuffix)"
            } else {
                mangledName = "\(structureName)_\(methodBaseName)_\(methodArgLayoutKeys)\(ownerSuffix)"
            }
        } else if methodTypeArgs.isEmpty {
            mangledName = "\(structureName)_\(argLayoutKeys)_\(methodBaseName)\(ownerSuffix)"
        } else {
            mangledName = "\(structureName)_\(argLayoutKeys)_\(methodBaseName)_\(methodArgLayoutKeys)\(ownerSuffix)"
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
            registerInstantiatedExtensionMethodLookup(
                baseType: baseType,
                structureName: structureName,
                methodBaseName: methodBaseName,
                methodTypeArgs: methodTypeArgs,
                templateMethodDefId: method.defId,
                generatedSymbol: cachedSymbol,
                functionType: cachedSymbol.type,
                conformanceTraitName: methodInfo.conformanceTraitName,
                conformanceTraitDefId: methodInfo.conformanceTraitDefId
            )
            return copySymbolPreservingDefId(cachedSymbol)
        }
        if let (cachedName, cachedType) = instantiatedFunctions[key] {
            let cachedSymbol = instantiatedFunctionSymbols[key] ?? makeSymbol(
                name: cachedName,
                type: cachedType,
                kind: .function
            )
            instantiatedFunctionSymbols[key] = cachedSymbol
            registerInstantiatedExtensionMethodLookup(
                baseType: baseType,
                structureName: structureName,
                methodBaseName: methodBaseName,
                methodTypeArgs: methodTypeArgs,
                templateMethodDefId: method.defId,
                generatedSymbol: cachedSymbol,
                functionType: cachedType,
                conformanceTraitName: methodInfo.conformanceTraitName,
                conformanceTraitDefId: methodInfo.conformanceTraitDefId
            )
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
            parameters: preservedParameters(
                resolvedParams: params,
                declaredParams: method.parameters
            ),
            returns: returnType
        )
        if method.parameters.first?.name == "self",
           baseType.indirectionCompatibilityInfo != nil,
           let receiverParam = params.first,
           !instantiatedReceiver(receiverParam.type, matches: baseType) {
            throw SemanticError(
                .generic("Receiver type \(receiverParam.type) does not match instantiated method owner \(baseType)."),
                span: SourceSpan(location: SourceLocation(line: currentLine, column: 1))
            )
        }
        
        // Skip code generation if function type still contains generic parameters
        if context.containsGenericParameter(functionType) {
            return makeSymbol(name: mangledName, type: functionType, kind: .function)
        }
        
        // IMPORTANT: Cache the function BEFORE processing the body to prevent infinite recursion
        // This allows recursive methods (like rehash calling insert, insert calling rehash) to work
        instantiatedFunctions[key] = (disambiguatedMangledName, functionType)
        if instantiatedFunctionSymbols[key] == nil {
            instantiatedFunctionSymbols[key] = makeSymbol(
                name: disambiguatedMangledName,
                type: functionType,
                kind: .function
            )
        }
        
        // Get the typed body from the declaration-time checked body
        let typedBody: TypedExpressionNode
        if let checkedBody = methodInfo.checkedBody {
            // Use the declaration-time checked body and substitute types
            let substitutedBody = substituteTypesInExpression(checkedBody, substitution: typeSubstitution)
            typedBody = resolveTypesInExpression(substitutedBody)
        } else {
            fatalError("Monomorphizer invariant violated: missing checkedBody for extension method '\(method.name)' on '\(structureName)'")
        }
        
        // Generate global function if not already generated
        let generatedSymbol: Symbol
        if !generatedLayouts.contains(disambiguatedMangledName) {
            generatedLayouts.insert(disambiguatedMangledName)
            generatedSymbol = instantiatedFunctionSymbols[key] ?? makeSymbol(
                name: disambiguatedMangledName,
                type: functionType,
                kind: .function
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
                kind: .function
            )
        }

        instantiatedFunctionSymbols[key] = generatedSymbol
        registerInstantiatedExtensionMethodLookup(
            baseType: baseType,
            structureName: structureName,
            methodBaseName: methodBaseName,
            methodTypeArgs: methodTypeArgs,
            templateMethodDefId: method.defId,
            generatedSymbol: generatedSymbol,
            functionType: functionType,
            conformanceTraitName: methodInfo.conformanceTraitName,
            conformanceTraitDefId: methodInfo.conformanceTraitDefId
        )

        return copySymbolPreservingDefId(generatedSymbol)
    }
    
    /// Creates a placeholder body for methods that need re-checking.
    internal func createPlaceholderBody(returnType: Type) -> TypedExpressionNode {
        fatalError("Monomorphizer invariant violated: attempted to create placeholder body for return type '\(returnType)'")
    }

    private func instantiatedReceiver(_ expected: Type, matches actual: Type) -> Bool {
        let resolvedExpected = resolveParameterizedType(expected)
        let resolvedActual = resolveParameterizedType(actual)
        if resolvedExpected == resolvedActual {
            return true
        }
        switch resolvedActual {
        case .reference(let inner), .mutableReference(let inner),
             .borrowedReference(let inner), .mutableBorrowedReference(let inner),
             .weakReference(let inner), .mutableWeakReference(let inner),
             .pointer(let inner), .mutablePointer(let inner):
            if resolveParameterizedType(inner) == resolvedExpected {
                return true
            }
        default:
            break
        }
        switch resolvedExpected {
        case .reference(let inner), .mutableReference(let inner),
             .borrowedReference(let inner), .mutableBorrowedReference(let inner),
             .weakReference(let inner), .mutableWeakReference(let inner),
             .pointer(let inner), .mutablePointer(let inner):
            if resolveParameterizedType(inner) == resolvedActual {
                return true
            }
        default:
            break
        }
        return resolvedExpected.compatibleIndirectionInners(with: resolvedActual) != nil
    }

    private func selectExtensionTemplateForBase(
        baseType: Type,
        methodName: String,
        methodTypeArgCount: Int? = nil,
        extensionTypeArgCount: Int? = nil
    ) -> GenericExtensionMethodTemplate? {
        guard let extensions = input.genericTemplates.extensionMethods[context.methodOwner(of: baseType)],
            let selected = selectExtensionTemplate(
                extensions,
                name: methodName,
                methodTypeArgCount: methodTypeArgCount,
                extensionTypeArgCount: extensionTypeArgCount
            )
        else {
            return nil
        }
        return selected
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
            return makeSymbol(name: cachedName, type: cachedType, kind: .function)
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
            parameters: preservedParameters(
                resolvedParams: params,
                declaredParams: method.parameters
            ),
            returns: returnType
        )
        
        instantiatedFunctions[key] = (mangledName, funcType)
        return makeSymbol(name: mangledName, type: funcType, kind: .function)
    }
    
    // MARK: - Method Lookup

    /// Outcome of identity-based method instantiation lookup.
    /// Always carries the resolved DefId and fully-substituted type.
    internal enum MethodInstanceResolution {
        /// Use this symbol: carries the INSTANTIATED DefId and the substituted type.
        case instantiated(Symbol)
        /// The definition-time DefId is already the emitted identity (concrete
        /// given method, intrinsic/built-in). The type is fully substituted.
        case keepDefinitionTime(type: Type)
    }

    internal func identityReceiverLookupCandidates(_ receiverType: Type) -> [Type] {
        var candidates: [Type] = []
        var seen: Set<Type> = []
        func append(_ candidate: Type) {
            let resolved = resolveParameterizedType(candidate)
            guard seen.insert(resolved).inserted else {
                return
            }
            candidates.append(resolved)
        }

        let resolved = resolveParameterizedType(receiverType)
        append(resolved)
        switch resolved {
        case .reference(let inner), .mutableReference(let inner),
             .borrowedReference(let inner), .mutableBorrowedReference(let inner),
             .weakReference(let inner), .mutableWeakReference(let inner):
            append(inner)
        default:
            break
        }
        return candidates
    }

    internal func resolveMethodInstanceByIdentityForReceiver(
        definitionMethod: Symbol,
        substitutedMethodType: Type,
        substitutedMethodTypeArgs: [Type],
        receiverType: Type
    ) throws -> MethodInstanceResolution {
        var keepDefinitionTime: MethodInstanceResolution?
        var lastError: Error?

        for candidate in identityReceiverLookupCandidates(receiverType) {
            guard !context.containsGenericParameter(candidate) else {
                continue
            }
            do {
                let resolution = try resolveMethodInstanceByIdentity(
                    definitionMethod: definitionMethod,
                    substitutedMethodType: substitutedMethodType,
                    substitutedMethodTypeArgs: substitutedMethodTypeArgs,
                    receiverType: candidate
                )
                switch resolution {
                case .instantiated:
                    return resolution
                case .keepDefinitionTime:
                    if keepDefinitionTime == nil {
                        keepDefinitionTime = resolution
                    }
                }
            } catch {
                lastError = error
            }
        }

        if let keepDefinitionTime {
            return keepDefinitionTime
        }
        if let lastError {
            throw lastError
        }
        return .keepDefinitionTime(type: substitutedMethodType)
    }

    internal func resolveStandaloneMethodFunctionReference(
        definitionMethod: Symbol,
        substitutedFunctionType: Type,
        substitutedMethodTypeArgs: [Type] = []
    ) -> Symbol? {
        let resolvedFunctionType = resolveParameterizedType(substitutedFunctionType)
        guard case .function(let parameters, let returns) = resolvedFunctionType else {
            return nil
        }

        var receiverCandidates: [Type] = []
        var seen: Set<Type> = []
        func appendCandidate(_ candidate: Type) {
            for resolved in identityReceiverLookupCandidates(candidate) {
                guard !context.containsGenericParameter(resolved),
                      seen.insert(resolved).inserted else {
                    continue
                }
                receiverCandidates.append(resolved)
            }
        }

        if let first = parameters.first {
            appendCandidate(first.type)
        }
        appendCandidate(returns)
        switch returns {
        case .genericStruct(_, let args), .genericEnum(_, let args):
            for arg in args {
                appendCandidate(arg)
            }
        case .structure(let defId), .enum(let defId):
            for arg in context.getTypeArguments(defId) ?? [] {
                appendCandidate(arg)
            }
        default:
            break
        }
        if case .concreteType(let ownerType)? = receiverMethodDispatch[definitionMethod.defId]?.owner {
            appendCandidate(ownerType)
        }
        if let ownerType = exactTemplateOwnerType(forMethodDefId: definitionMethod.defId) {
            appendCandidate(ownerType)
        } else if let ownerType = uniqueConcreteOwnerTypeForMethodSymbol(definitionMethod) {
            appendCandidate(ownerType)
        }
        for receiverType in receiverCandidates {
            guard let resolution = try? resolveMethodInstanceByIdentityForReceiver(
                definitionMethod: definitionMethod,
                substitutedMethodType: resolvedFunctionType,
                substitutedMethodTypeArgs: substitutedMethodTypeArgs,
                receiverType: receiverType
            ) else {
                continue
            }

            switch resolution {
            case .instantiated(let instantiated):
                return Symbol(
                    defId: instantiated.defId,
                    type: resolveParameterizedType(instantiated.type),
                    kind: instantiated.kind
                )
            case .keepDefinitionTime:
                continue
            }
        }

        let exactRemaps = (remappedFunctionDefIds[definitionMethod.defId] ?? []).filter {
            resolveParameterizedType($0.type) == resolvedFunctionType
        }
        if exactRemaps.count == 1 {
            return Symbol(defId: exactRemaps[0].defId, type: resolvedFunctionType, kind: definitionMethod.kind)
        }

        return nil
    }

    internal func resolveTraitPlaceholderMethodByIdentity(
        traitMethodDefId: DefId,
        expectedMethodType: Type,
        methodTypeArgs: [Type],
        receiverType: Type
    ) -> Symbol? {
        guard traitMethodDefId.isValid else {
            return nil
        }
        let definitionMethod = Symbol(
            defId: traitMethodDefId,
            type: expectedMethodType,
            kind: .function
        )
        guard let resolution = try? resolveMethodInstanceByIdentityForReceiver(
            definitionMethod: definitionMethod,
            substitutedMethodType: expectedMethodType,
            substitutedMethodTypeArgs: methodTypeArgs,
            receiverType: receiverType
        ) else {
            return nil
        }
        switch resolution {
        case .instantiated(let instantiated):
            return Symbol(
                defId: instantiated.defId,
                type: resolveParameterizedType(instantiated.type),
                kind: instantiated.kind
            )
        case .keepDefinitionTime:
            return nil
        }
    }

    private func uniqueConcreteOwnerTypeForMethodSymbol(_ method: Symbol) -> Type? {
        let methodName = receiverMethodDispatch[method.defId]?.methodName ?? context.getName(method.defId) ?? ""
        guard !methodName.isEmpty else {
            return nil
        }
        var owners: [MethodOwner] = []
        var seen = Set<MethodOwner>()
        for (key, entry) in extensionMethods where key.methodName == methodName {
            guard methodTypeMatchesExpected(entry.symbol.type, expected: method.type) else {
                continue
            }
            if seen.insert(key.owner).inserted {
                owners.append(key.owner)
            }
        }
        guard owners.count == 1 else {
            return nil
        }
        return concreteType(for: owners[0])
    }

    private func concreteType(for owner: MethodOwner) -> Type? {
        switch owner {
        case .decl(let ownerDefId):
            return context.defIdMap.lookupType(defId: ownerDefId)
        case .builtin(let name):
            switch name {
            case "Int": return .int
            case "Int8": return .int8
            case "Int16": return .int16
            case "Int32": return .int32
            case "Int64": return .int64
            case "UInt": return .uint
            case "UInt8": return .uint8
            case "UInt16": return .uint16
            case "UInt32": return .uint32
            case "UInt64": return .uint64
            case "WrappingInt": return .wrappingInt
            case "WrappingInt8": return .wrappingInt8
            case "WrappingInt16": return .wrappingInt16
            case "WrappingInt32": return .wrappingInt32
            case "WrappingInt64": return .wrappingInt64
            case "WrappingUInt": return .wrappingUInt
            case "WrappingUInt8": return .wrappingUInt8
            case "WrappingUInt16": return .wrappingUInt16
            case "WrappingUInt32": return .wrappingUInt32
            case "WrappingUInt64": return .wrappingUInt64
            case "Float32": return .float32
            case "Float64": return .float64
            case "Bool": return .bool
            default: return nil
            }
        }
    }

    private func exactTemplateOwnerType(forMethodDefId defId: DefId) -> Type? {
        guard let owner = exactTemplateOwner(forMethodDefId: defId) else {
            return nil
        }
        return concreteType(for: owner)
    }

    private func exactTemplateOwner(forMethodDefId defId: DefId) -> MethodOwner? {
        var owners: [MethodOwner] = []
        var seen = Set<MethodOwner>()
        for (key, entry) in extensionMethods where entry.symbol.defId == defId {
            if seen.insert(key.owner).inserted {
                owners.append(key.owner)
            }
        }
        for (owner, templates) in input.genericTemplates.extensionMethods {
            if templates.contains(where: { $0.method.defId == defId }),
               seen.insert(owner).inserted {
                owners.append(owner)
            }
        }
        guard owners.count == 1 else {
            return nil
        }
        return owners[0]
    }

    /// Finds the extension method template whose declaration DefId matches.
    /// Searches the given owner first, then all owners. Pure identity — never
    /// matches by name. Also matches by `traitMethodDefId` (rustc's
    /// `trait_item_def_id`) so trait-method references find the impl's template.
    internal func extensionMethodTemplate(
        byDefId defId: DefId, owner: MethodOwner
    ) -> GenericExtensionMethodTemplate? {
        if let templates = input.genericTemplates.extensionMethods[owner],
           let hit = templates.first(where: { $0.method.defId == defId }) {
            return hit
        }
        if case .decl(let ownerDefId) = owner,
           input.genericTemplates.traitDeclsByDefId[ownerDefId] != nil {
            return nil
        }
        if let templates = input.genericTemplates.extensionMethods[owner],
           let hit = templates.first(where: {
               receiverMethodDispatch[$0.method.defId]?.traitMethodDefId == defId
           }) {
            return hit
        }
        return nil
    }

    /// Finds (or materializes) the specialization of the SAME method the
    /// definition-time symbol named. The definition-time DefId is authoritative:
    /// this never re-decides which method via name lookup.
    ///
    /// Lookup chain (rustc's `Instance::resolve`):
    ///   L0: already-instantiated → the DefId IS the emitted identity.
    ///   L1: direct hash lookup in `extensionMethodDefIds` by `MethodInstanceKey`
    ///       (DefId + GenericArgs). No type matching — the key is exact identity.
    ///   L2: materialize the template's specialization, then retry L1.
    ///   L3: keepDefinitionTime (concrete given / built-in only).
    /// Identity lookup that NEVER instantiates -- a pure read of the tables.
    ///
    /// `resolveMethodInstanceByIdentity`'s L2 materializes a specialization,
    /// which mutates the monomorphizer. That is right at a call site and wrong
    /// in the middle of type resolution: `refreshListPatternOps` runs while the
    /// resolution worklist is still draining, and an instantiation there
    /// perturbs state that later makes codegen emit a payloadless init for a
    /// tagged enum (`Type`, `InterpolatedStringTokenPart`). This variant
    /// answers only from what is already registered (L0/L1) and leaves the
    /// tables untouched.
    ///
    /// Read-only is not a weaker identity check: the key is still owner + DefId
    /// + type args. It only declines to CREATE anything.
    internal func lookupMethodInstanceIdentityReadonly(
        definitionMethod: Symbol,
        receiverType: Type,
        methodTypeArgs: [Type] = []
    ) -> Symbol? {
        let defId = definitionMethod.defId
        guard defId.isValid else { return nil }
        // L0: the DefId is already the emitted identity.
        if instantiatedMethodDefIds.contains(defId) {
            return definitionMethod
        }
        let identityDefId = receiverMethodDispatch[defId]?.methodDefId ?? defId
        var lookupDefIds: [DefId] = [identityDefId]
        if identityDefId != defId {
            lookupDefIds.append(defId)
        }
        // Dual-key: trait-method references carry the trait METHOD's DefId
        // (rustc's `trait_item_def_id`), not the impl's.
        if let traitMethodDefId = receiverMethodDispatch[defId]?.traitMethodDefId,
           !lookupDefIds.contains(traitMethodDefId) {
            lookupDefIds.append(traitMethodDefId)
        }
        for lookupDefId in lookupDefIds {
            let lookupKey = context.receiverMethodKey(receiverType, lookupDefId, methodTypeArgs: methodTypeArgs)
            if let hit = extensionMethodDefIds[lookupKey] {
                let hitType = context.getSymbolType(hit) ?? definitionMethod.type
                return Symbol(defId: hit, type: hitType, kind: .function)
            }
        }
        return nil
    }


    internal func resolveMethodInstanceByIdentity(
        definitionMethod: Symbol,
        substitutedMethodType: Type,
        substitutedMethodTypeArgs: [Type],
        receiverType: Type
    ) throws -> MethodInstanceResolution {
        let defId = definitionMethod.defId
        let identityDefId = receiverMethodDispatch[defId]?.methodDefId ?? defId

        // Substitute method-level type parameters into the method type so the
        // expected type is fully concrete.
        var fullMethodType = substitutedMethodType
        let owner = context.methodOwner(of: receiverType)
        let dispatchOwner: MethodOwner? = {
            switch receiverMethodDispatch[identityDefId]?.owner ?? receiverMethodDispatch[defId]?.owner {
            case .extensionTemplate(let ownerDefId):
                return .decl(ownerDefId)
            default:
                return nil
            }
        }()
        let exactOwner = exactTemplateOwner(forMethodDefId: identityDefId)
        let template =
            extensionMethodTemplate(byDefId: identityDefId, owner: owner)
            ?? exactOwner.flatMap { extensionMethodTemplate(byDefId: identityDefId, owner: $0) }
            ?? dispatchOwner.flatMap { extensionMethodTemplate(byDefId: identityDefId, owner: $0) }
            ?? (identityDefId == defId ? nil : extensionMethodTemplate(byDefId: defId, owner: owner))
            ?? (identityDefId == defId ? nil : exactOwner.flatMap { extensionMethodTemplate(byDefId: defId, owner: $0) })
            ?? (identityDefId == defId ? nil : dispatchOwner.flatMap { extensionMethodTemplate(byDefId: defId, owner: $0) })
        if !substitutedMethodTypeArgs.isEmpty,
           context.containsGenericParameter(substitutedMethodType) {
            var mSubst: [String: Type] = [:]
            if let template, !template.method.typeParameters.isEmpty {
                for (i, paramInfo) in template.method.typeParameters.enumerated()
                where i < substitutedMethodTypeArgs.count {
                    mSubst[paramInfo.name] = substitutedMethodTypeArgs[i]
                }
            } else {
                let paramNames = collectGenericParameterNames(substitutedMethodType)
                for (i, name) in paramNames.enumerated()
                where i < substitutedMethodTypeArgs.count {
                    mSubst[name] = substitutedMethodTypeArgs[i]
                }
            }
            if !mSubst.isEmpty {
                fullMethodType = substituteType(substitutedMethodType, substitution: mSubst)
            }
        }

        // L0: already-instantiated — the DefId IS the emitted identity.
        if instantiatedMethodDefIds.contains(defId) {
            return .instantiated(Symbol(defId: defId, type: fullMethodType, kind: definitionMethod.kind))
        }

        // L1: direct hash lookup by identity key (DefId + GenericArgs).
        // Check both the definition-time DefId and the trait method DefId
        // (for methods that implement a trait method via `trait_item_def_id`).
        let (_, ownerArgs) = context.methodOwnerAndArgs(of: receiverType)
        let lookupDefIds = identityDefId == defId ? [defId] : [identityDefId, defId]
        func symbolMatchesFullMethodType(_ hit: DefId) -> Bool {
            guard let hitType = context.getSymbolType(hit) else {
                return true
            }
            let resolvedHitType = resolveParameterizedType(hitType)
            guard case .function(let hitParams, let hitReturns) = resolvedHitType,
                  case .function(let expectedParams, let expectedReturns) = fullMethodType,
                  hitParams.count == expectedParams.count,
                  hitReturns == expectedReturns else {
                return resolvedHitType == fullMethodType
            }
            return zip(hitParams, expectedParams).allSatisfy { $0.type == $1.type }
        }
        for lookupDefId in lookupDefIds {
            let lookupKey = context.receiverMethodKey(receiverType, lookupDefId, methodTypeArgs: substitutedMethodTypeArgs)
            if let hit = extensionMethodDefIds[lookupKey] {
                if symbolMatchesFullMethodType(hit) {
                    return .instantiated(Symbol(defId: hit, type: fullMethodType, kind: .function))
                }
            }
            // Dual-key: also check under the trait method DefId.
            if let traitMethodDefId = receiverMethodDispatch[lookupDefId]?.traitMethodDefId
                ?? receiverMethodDispatch[defId]?.traitMethodDefId {
                let traitKey = context.receiverMethodKey(receiverType, traitMethodDefId, methodTypeArgs: substitutedMethodTypeArgs)
                if let hit = extensionMethodDefIds[traitKey] {
                    if symbolMatchesFullMethodType(hit) {
                        return .instantiated(Symbol(defId: hit, type: fullMethodType, kind: .function))
                    }
                }
            }
        }
        // L2: materialize this declaration's specialization, then retry L1.
        if let template {
            let resolvedBase = resolveParameterizedType(receiverType)
            let structureName: String
            switch resolvedBase {
            case .structure(let sDefId):
                structureName = context.getTemplateName(sDefId) ?? context.getName(sDefId) ?? ""
            case .genericStruct(let tDefId, _):
                structureName = context.getTemplateName(tDefId) ?? context.getName(tDefId) ?? ""
            case .genericEnum(let tDefId, _):
                structureName = context.getTemplateName(tDefId) ?? context.getName(tDefId) ?? ""
            case .`enum`(let eDefId):
                structureName = context.getTemplateName(eDefId) ?? context.getName(eDefId) ?? ""
            case .pointer:
                structureName = "Ptr"
            default:
                structureName = resolvedBase.description
            }
            // Derive ownerArgs from the RESOLVED base type (which has concrete
            // type args), not from the original receiverType (which might be a
            // .structure with empty getTypeArguments).
            let receiverOwnerArgs: [Type] = {
                if !ownerArgs.isEmpty { return ownerArgs }
                // Try to get type args from the resolved base.
                switch resolvedBase {
                case .genericStruct(_, let args), .genericEnum(_, let args):
                    return args
                case .structure(let sDefId), .enum(let sDefId):
                    return context.getTypeArguments(sDefId) ?? []
                default:
                    return []
                }
            }()
            let mArgs: [Type]
            if !substitutedMethodTypeArgs.isEmpty {
                mArgs = substitutedMethodTypeArgs
            } else if !template.method.typeParameters.isEmpty {
                mArgs = inferMethodTypeArgsBySignature(template: template, against: fullMethodType)
            } else {
                mArgs = []
            }
            let resolvedOwnerArgs: [Type] = {
                if template.typeParams.count == receiverOwnerArgs.count {
                    return receiverOwnerArgs
                }
                if let inferred = try? inferTraitExtensionTypeArgs(
                    baseType: resolvedBase,
                    methodInfo: template,
                    expectedMethodType: fullMethodType,
                    methodTypeArgs: mArgs
                ) {
                    return inferred
                }
                return receiverOwnerArgs
            }()
            if mArgs.count == template.method.typeParameters.count
                && template.typeParams.count == resolvedOwnerArgs.count {
                do {
                    let instSym = try instantiateExtensionMethodFromEntry(
                        baseType: resolvedBase,
                        structureName: structureName,
                        genericArgs: resolvedOwnerArgs,
                        methodTypeArgs: mArgs,
                        methodInfo: template
                    )
                    // Retry L1 after instantiation.
                    for lookupDefId in lookupDefIds {
                        let retryKey = context.receiverMethodKey(receiverType, lookupDefId, methodTypeArgs: mArgs)
                        if let hit = extensionMethodDefIds[retryKey] {
                            if symbolMatchesFullMethodType(hit) {
                                return .instantiated(Symbol(defId: hit, type: fullMethodType, kind: .function))
                            }
                        }
                    }
                    // The freshly instantiated symbol IS the answer.
                    if symbolMatchesFullMethodType(instSym.defId) {
                        return .instantiated(Symbol(defId: instSym.defId, type: fullMethodType, kind: .function))
                    }
                } catch {
                    // Instantiation failed — fall through to L3.
                }
            }
        }

        // L3: keep the definition-time DefId ONLY if it's already an emitted
        // function (concrete given / built-in). Otherwise the C name would be
        // the template's name.
        if instantiatedMethodDefIds.contains(defId) {
            return .instantiated(Symbol(defId: defId, type: fullMethodType, kind: definitionMethod.kind))
        }
        return .keepDefinitionTime(type: fullMethodType)
    }

    /// Infers method-level type args from the substituted method type by
    /// unifying the template's checked signature against it.
    private func inferMethodTypeArgsBySignature(
        template: GenericExtensionMethodTemplate, against substitutedType: Type
    ) -> [Type] {
        guard case .function(let expectedParams, let expectedReturns) = substitutedType,
              let checkedParams = template.checkedParameters,
              let checkedReturns = template.checkedReturnType else {
            return []
        }
        var bindings: [String: Type] = [:]
        // Unify parameters (skip receiver at position 0).
        for (expected, checked) in zip(expectedParams.dropFirst(), checkedParams.dropFirst()) {
            _ = unifyTypePattern(checked.type, against: expected.type, bindings: &bindings)
        }
        _ = unifyTypePattern(checkedReturns, against: expectedReturns, bindings: &bindings)
        // Collect in declaration order.
        return template.method.typeParameters.map { bindings[$0.name] ?? .genericParameter(name: $0.name) }
    }

    /// Collects generic parameter names from a type in order of first appearance.
    private func collectGenericParameterNames(_ type: Type) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        func collect(_ t: Type) {
            switch t {
            case .genericParameter(let name):
                if seen.insert(name).inserted { names.append(name) }
            case .reference(let inner), .mutableReference(let inner),
                 .borrowedReference(let inner), .mutableBorrowedReference(let inner),
                 .weakReference(let inner), .mutableWeakReference(let inner):
                collect(inner)
            case .function(let params, let returns):
                for p in params { collect(p.type) }
                collect(returns)
            case .genericStruct(_, let args), .genericEnum(_, let args):
                for a in args { collect(a) }
            case .pointer(let element):
                collect(element)
            default:
                break
            }
        }
        collect(type)
        return names
    }

    /// Simple structural unification for method type arg inference.
    private func unifyTypePattern(_ pattern: Type, against concrete: Type, bindings: inout [String: Type]) -> Bool {
        if case .genericParameter(let name) = pattern {
            if let existing = bindings[name] { return existing == concrete }
            bindings[name] = concrete
            return true
        }
        switch (pattern, concrete) {
        case (.reference(let p), .reference(let c)),
             (.mutableReference(let p), .mutableReference(let c)),
             (.borrowedReference(let p), .borrowedReference(let c)),
             (.mutableBorrowedReference(let p), .mutableBorrowedReference(let c)):
            return unifyTypePattern(p, against: c, bindings: &bindings)
        case (.function(let pParams, let pRet), .function(let cParams, let cRet)):
            guard pParams.count == cParams.count else { return false }
            var ok = zip(pParams, cParams).allSatisfy { unifyTypePattern($0.type, against: $1.type, bindings: &bindings) }
            ok = ok && unifyTypePattern(pRet, against: cRet, bindings: &bindings)
            return ok
        case (.genericEnum(let pDefId, let pArgs), .genericEnum(let cDefId, let cArgs)),
             (.genericStruct(let pDefId, let pArgs), .genericStruct(let cDefId, let cArgs)):
            guard pDefId == cDefId, pArgs.count == cArgs.count else { return false }
            return zip(pArgs, cArgs).allSatisfy { unifyTypePattern($0, against: $1, bindings: &bindings) }
        default:
            return pattern == concrete
        }
    }

    private func normalizeTypeArgument(_ type: Type) -> Type {
        switch type {
        case .genericStruct(let tplDefId, let args):
            return .genericStruct(templateDefId: tplDefId, args: args.map { normalizeTypeArgument($0) })
        case .genericEnum(let tplDefId, let args):
            return .genericEnum(templateDefId: tplDefId, args: args.map { normalizeTypeArgument($0) })
        case .reference(let inner):
            return .reference(inner: normalizeTypeArgument(inner))
        case .mutableReference(let inner):
            return .mutableReference(inner: normalizeTypeArgument(inner))
        case .borrowedReference(let inner):
            return .borrowedReference(inner: normalizeTypeArgument(inner))
        case .mutableBorrowedReference(let inner):
            return .mutableBorrowedReference(inner: normalizeTypeArgument(inner))
        case .weakReference(let inner):
            return .weakReference(inner: normalizeTypeArgument(inner))
        case .mutableWeakReference(let inner):
            return .mutableWeakReference(inner: normalizeTypeArgument(inner))
        case .pointer(let element):
            return .pointer(element: normalizeTypeArgument(element))
        case .mutablePointer(let element):
            return .mutablePointer(element: normalizeTypeArgument(element))
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

    /// Types whose methods answer for `baseType`.
    ///
    /// A mutable modifier also yields the immutable one (a `ref T` method is
    /// callable on a `mut ref T`). Otherwise there is exactly one type -- this
    /// used to return the receiver's SPELLINGS, so a nominal contributed both
    /// `concreteName` and `templateName` and a modifier its own name plus the
    /// immutable one.
    private func extensionLookupTypes(for baseType: Type) -> [Type] {
        let resolvedBaseType = resolveParameterizedType(baseType)
        switch resolvedBaseType {
        case .reference(let inner):
            return [.reference(inner: inner)]
        case .mutableReference(let inner):
            return [.mutableReference(inner: inner), .reference(inner: inner)]
        case .borrowedReference(let inner):
            return [.reference(inner: inner)]
        case .mutableBorrowedReference(let inner):
            return [.mutableReference(inner: inner), .reference(inner: inner)]
        case .weakReference(let inner):
            return [.weakReference(inner: inner)]
        case .mutableWeakReference(let inner):
            return [.mutableWeakReference(inner: inner), .weakReference(inner: inner)]
        case .pointer(let inner):
            return [.pointer(element: inner)]
        case .mutablePointer(let inner):
            return [.mutablePointer(element: inner), .pointer(element: inner)]
        default:
            return [resolvedBaseType]
        }
    }

    /// Owner identity of a generic `given` target known by its spelling.
    /// RESOLUTION happens here, once; the identity then comes from the template's
    /// declaration.
    /// Owner identity of a generic `given` target known only by its SPELLING.
    ///
    /// RESOLUTION, not identity: this runs where the only thing in hand is the
    /// name written in `given [T] List`. The identity is the template's
    /// declaration, resolved once here (rustc_resolve). A call site that already
    /// has a `Type` must use `context.methodOwner(of:)` and never this.
    private func ownerOfGenericTemplate(_ name: String) -> MethodOwner {
        if let t = input.genericTemplates.structTemplates[name] {
            return .decl(t.defId)
        }
        if let t = input.genericTemplates.enumTemplates[name] {
            return .decl(t.defId)
        }
        return .builtin(name)
    }

    private func extensionStructureName(for baseType: Type) -> String {
        let resolvedBaseType = resolveParameterizedType(baseType)
        switch resolvedBaseType {
        case .reference:
            return "Ref"
        case .mutableReference:
            return "MutRef"
        case .borrowedReference:
            return "Ref"
        case .mutableBorrowedReference:
            return "MutRef"
        case .weakReference:
            return "WeakRef"
        case .mutableWeakReference:
            return "MutWeakRef"
        case .structure(let defId):
            let name = context.getName(defId) ?? ""
            return context.getTemplateName(defId) ?? name
        case .genericStruct(let tplDefId, _):
            return Type.spelling(tplDefId)
        case .genericEnum(let tplDefId, _):
            return Type.spelling(tplDefId)
        case .`enum`(let defId):
            let name = context.getName(defId) ?? ""
            return context.getTemplateName(defId) ?? name
        case .pointer:
            return "Ptr"
        case .mutablePointer:
            return "MutPtr"
        default:
            return resolvedBaseType.description
        }
    }

    internal func methodTypeMatchesExpected(_ candidate: Type, expected: Type?) -> Bool {
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
        case .reference(let expectedInner),
             .mutableReference(let expectedInner),
             .borrowedReference(let expectedInner),
             .mutableBorrowedReference(let expectedInner),
             .weakReference(let expectedInner),
             .mutableWeakReference(let expectedInner),
             .pointer(let expectedInner),
             .mutablePointer(let expectedInner):
            guard let (_, actualInner) = expected.compatibleIndirectionInners(with: actual) else {
                return false
            }
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
        // Identity: the template's DECLARATION, never its spelling.
        case .genericStruct(let expectedDefId, let expectedArgs):
            let actualArgs: [Type]
            switch actual {
            case .genericStruct(let actualDefId, let args):
                guard actualDefId == expectedDefId else { return false }
                actualArgs = args
            case .structure(let defId):
                guard context.templateDeclaration(of: defId) == expectedDefId,
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
        case .genericEnum(let expectedDefId, let expectedArgs):
            let actualArgs: [Type]
            switch actual {
            case .genericEnum(let actualDefId, let args):
                guard actualDefId == expectedDefId else { return false }
                actualArgs = args
            case .`enum`(let defId):
                guard context.templateDeclaration(of: defId) == expectedDefId,
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
        let lookupTypes = extensionLookupTypes(for: baseType)
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

        // The receiver's OWNER IDENTITY. `lookupTypeNames` used to be a sweep over
        // the receiver's spellings, so one method occupied up to N slots and two
        // same-named types could share them.
        for lookupType in lookupTypes {
            let key = context.receiverMethodLookupKey(lookupType, methodName)
            if let entry = extensionMethods[key] {
                appendCandidate(entry.symbol.defId)
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
        return Symbol(defId: defId, type: symbolType, kind: symbolKind)
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
            switch actual {
            case .reference(let aInner), .mutableReference(let aInner),
                 .borrowedReference(let aInner), .mutableBorrowedReference(let aInner):
                return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
            default:
                return false
            }
        case .mutableReference(let pInner):
            switch actual {
            case .mutableReference(let aInner), .mutableBorrowedReference(let aInner):
                return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
            default:
                return false
            }
        case .borrowedReference(let pInner):
            switch actual {
            case .reference(let aInner), .mutableReference(let aInner),
                 .borrowedReference(let aInner), .mutableBorrowedReference(let aInner):
                return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
            default:
                return false
            }
        case .mutableBorrowedReference(let pInner):
            switch actual {
            case .mutableReference(let aInner), .mutableBorrowedReference(let aInner):
                return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
            default:
                return false
            }
        case .weakReference(let pInner):
            switch actual {
            case .weakReference(let aInner), .mutableWeakReference(let aInner):
                return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
            default:
                return false
            }
        case .mutableWeakReference(let pInner):
            guard case .mutableWeakReference(let aInner) = actual else { return false }
            return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
        case .pointer(let pInner):
            guard case .pointer(let aInner) = actual else { return false }
            return unifyGenericTypePattern(pattern: pInner, actual: aInner, typeParamNames: typeParamNames, inferred: &inferred)
        // Identity: the template's DECLARATION, not its spelling.
        case .genericStruct(let pDefId, let pArgs):
            let aArgs: [Type]
            switch actual {
            case .genericStruct(let aDefId, let args):
                guard aDefId == pDefId else { return false }
                aArgs = args
            case .structure(let defId):
                guard context.templateDeclaration(of: defId) == pDefId,
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
        case .genericEnum(let pDefId, let pArgs):
            let aArgs: [Type]
            switch actual {
            case .genericEnum(let aDefId, let args):
                guard aDefId == pDefId else { return false }
                aArgs = args
            case .`enum`(let defId):
                guard context.templateDeclaration(of: defId) == pDefId,
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

    internal func inferTraitExtensionTypeArgs(
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
            patternParams = zip(checkedParameters, methodInfo.method.parameters).map { param, declared in
                Parameter(
                    type: substituteType(param.type, substitution: substitution),
                    kind: preservedPassKind(for: declared.type)
                )
            }
            patternReturn = substituteType(checkedReturnType, substitution: substitution)
        } else {
            let params = try methodInfo.method.parameters.map { param -> Parameter in
                let paramType = try resolveTypeNode(param.type, substitution: substitution)
                return Parameter(type: paramType, kind: preservedPassKind(for: param.type))
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
            patternParams = zip(checkedParameters, methodInfo.method.parameters).map { param, declared in
                Parameter(
                    type: substituteType(param.type, substitution: substitution),
                    kind: preservedPassKind(for: declared.type)
                )
            }
            patternReturn = substituteType(checkedReturnType, substitution: substitution)
        } else {
            patternParams = try methodInfo.method.parameters.map { param in
                let paramType = try resolveTypeNode(param.type, substitution: substitution)
                return Parameter(type: paramType, kind: preservedPassKind(for: param.type))
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

    private func instantiateTraitEntryMethod(
        baseType: Type,
        traitInfo: TypedTraitConformance,
        methodName: String,
        methodTypeArgs: [Type],
        expectedMethodType: Type?
    ) throws -> Symbol? {
        let resolvedBaseType = resolveParameterizedType(baseType)
        let traitEntryExpectedType = expectedMethodType ?? entryLikeExpectedMethodType(baseType: resolvedBaseType, methodName: methodName)

        let methodInfo: GenericExtensionMethodTemplate? = {
            for candidateName in extensionLookupTypes(for: resolvedBaseType) {
                 guard let methods = input.genericTemplates.extensionMethods[context.methodOwner(of: resolvedBaseType)] else {
                    continue
                }
                guard let selected = selectExtensionTemplate(
                    methods,
                    name: methodName,
                    methodTypeArgCount: methodTypeArgs.isEmpty ? nil : methodTypeArgs.count
                ) else {
                    continue
                }
                if selected.conformanceTraitDefId == traitInfo.traitDefId {
                    return selected
                }
            }
            return nil
        }()
        guard let methodInfo else {
            return nil
        }

        let inferredTypeArgs = try inferTraitExtensionTypeArgs(
            baseType: resolvedBaseType,
            methodInfo: methodInfo,
            expectedMethodType: traitEntryExpectedType,
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

        for (owner, methods) in input.genericTemplates.extensionMethods {
            // "Is this a trait?" is a test of the DECLARATION, answered from the
            // DefId index. Scanning the spelling-keyed `traits` both costs O(n)
            // and cannot see whatever lost the name race.
            guard case .decl(let ownerDefId) = owner,
                input.genericTemplates.isTraitDefId(ownerDefId)
            else {
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
    internal func isBuiltinIntegerType(_ type: Type) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64:
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
    /// The identity of a trait object type: the DECLARATION of its trait plus
    /// the trait arguments. The spelling is returned for display only.
    internal func extractTraitObjectType(_ type: Type) -> (traitName: String, traitDefId: DefId, typeArgs: [Type])? {
        switch type {
        case .traitObject(let traitDefId, let typeArgs):
            return (Type.spelling(traitDefId), traitDefId, typeArgs)
        case .reference(let inner), .mutableReference(let inner),
             .borrowedReference(let inner), .mutableBorrowedReference(let inner):
            if case .traitObject(let traitDefId, let typeArgs) = inner {
                return (Type.spelling(traitDefId), traitDefId, typeArgs)
            }
            return nil
        default:
            return nil
        }
    }

}

// MonomorphizerTypeResolution.swift
// Extension for Monomorphizer that handles type resolution and substitution.
// This file contains methods for resolving TypeNodes to concrete Types,
// resolving parameterized types (genericStruct/genericEnum), and
// resolving types throughout global nodes, expressions, statements, and patterns.

import Foundation

// MARK: - Type Resolution Extension

extension Monomorphizer {
    private func methodLookupBaseType(for base: TypedExpressionNode) -> Type {
        if case .variable = base {
            return base.type
        }
        if case .referenceExpression(let inner, _) = base {
            return methodLookupBaseType(for: inner)
        }
        if case .reference(let inner) = base.type {
            return inner
        }
        if case .mutableReference(let inner) = base.type {
            return inner
        }
        if case .borrowedReference(let inner) = base.type {
            return inner
        }
        if case .mutableBorrowedReference(let inner) = base.type {
            return inner
        }
        return base.type
    }

    func normalizedTraitPlaceholderExpectedMethodType(_ methodType: Type, for lookupBaseType: Type) -> Type {
        guard case .function(let params, let returns) = methodType,
              let first = params.first else {
            return methodType
        }

        let normalizedReceiver: Type
        switch first.type {
        case .reference:
            normalizedReceiver = .reference(inner: lookupBaseType)
        case .mutableReference:
            normalizedReceiver = .mutableReference(inner: lookupBaseType)
        case .borrowedReference(_):
            normalizedReceiver = .borrowedReference(inner: lookupBaseType)
        case .mutableBorrowedReference(_):
            normalizedReceiver = .mutableBorrowedReference(inner: lookupBaseType)
        case .weakReference:
            normalizedReceiver = .weakReference(inner: lookupBaseType)
        case .mutableWeakReference:
            normalizedReceiver = .mutableWeakReference(inner: lookupBaseType)
        default:
            normalizedReceiver = lookupBaseType
        }

        let normalizedParams = [Parameter(type: normalizedReceiver, kind: first.kind)] + params.dropFirst()
        return .function(parameters: normalizedParams, returns: returns)
    }


    /// Pre-populates `traitMethodDefId` links from `.givenDeclaration` nodes
    /// BEFORE the fixpoint loop. Does NOT create remapped symbols — those are
    /// created by `.givenDeclaration` processing in `resolveTypesInGlobalNode`.
    /// This just ensures `receiverMethodDispatch` has `traitMethodDefId` set
    /// for the original method DefIds so the dual-key registration works.
    internal func predeclareGivenMethodRemaps(in nodes: [TypedGlobalNode]) {
        for node in nodes {
            guard case .givenDeclaration(_, let trait, let methods) = node else { continue }
            guard let resolvedTrait = trait else { continue }
            for method in methods {
                let origDefId = method.identifier.defId
                // Ensure receiverMethodDispatch has traitMethodDefId for this method.
                if receiverMethodDispatch[origDefId]?.traitMethodDefId == nil {
                    let canonicalName = receiverMethodDispatch[origDefId]?.methodName
                        ?? (context.getName(origDefId) ?? "")
                    // Find the trait method DefId via the trait's method table.
                    for (_, info) in receiverMethodDispatch
                    where info.methodName == canonicalName
                        && info.conformanceTraitDefId == resolvedTrait.traitDefId
                        && info.traitMethodDefId != nil {
                        receiverMethodDispatch[origDefId] = ReceiverMethodDispatchInfo(
                            methodDefId: origDefId,
                            methodName: canonicalName,
                            owner: receiverMethodDispatch[origDefId]?.owner,
                            conformanceTraitName: info.conformanceTraitName,
                            conformanceTraitDefId: info.conformanceTraitDefId,
                            traitMethodDefId: info.traitMethodDefId
                        )
                        break
                    }
                }
            }
        }
    }

    internal func methodHasCompatibleRefLikeReceiver(_ methodType: Type, baseType: Type) -> Bool {
        guard case .function(let params, _) = methodType,
              let firstParam = params.first else {
            return false
        }
        guard let (expectedInner, actualInner) = firstParam.type.compatibleIndirectionInners(with: baseType) else {
            return false
        }
        return expectedInner == actualInner
    }

    // MARK: - Type Node Resolution
    
    /// Resolves a TypeNode to a concrete Type using the given substitution map.
    /// - Parameters:
    ///   - node: The type node to resolve
    ///   - substitution: Map from type parameter names to concrete types
    /// - Returns: The resolved concrete type
    internal func resolveTypeNode(_ node: TypeNode, substitution: [String: Type]) throws -> Type {
        switch node {
        case .identifier(let name, _):
            // Check substitution map first
            if let substituted = substitution[name] {
                // If the substituted type is a genericStruct, we need to instantiate it
                if case .genericStruct(let templateDefId, let args) = substituted {
                    // By DECLARATION -- the substituted type carries it.
                    if let structTemplate = input.genericTemplates.structTemplate(forDefId: templateDefId) {
                        return try instantiateStruct(template: structTemplate, args: args)
                    }
                }
                // If the substituted type is a genericEnum, we need to instantiate it
                if case .genericEnum(let templateDefId, let args) = substituted {
                    if let enumTemplate = input.genericTemplates.enumTemplate(forDefId: templateDefId) {
                        return try instantiateEnum(template: enumTemplate, args: args)
                    }
                }
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
            // Check if it's a known concrete enum type
            if let concreteType = input.genericTemplates.concreteEnumTypes[name] {
                return concreteType
            }
            // Check if it's a known struct template (non-generic reference)
            if let template = input.genericTemplates.structTemplates[name] {
                // Non-generic struct reference
                if template.typeParameters.isEmpty {
                    let defId = getOrAllocateTypeDefId(name: name, kind: .structure)
                    context.updateStructInfo(defId: defId, members: [], isGenericInstantiation: false, typeArguments: nil)
                    return .structure(defId: defId)
                }
            }
            // Check if it's a known enum template (non-generic reference)
            if let template = input.genericTemplates.enumTemplates[name] {
                // Non-generic enum reference
                if template.typeParameters.isEmpty {
                    let defId = getOrAllocateTypeDefId(name: name, kind: .`enum`)
                    context.updateEnumInfo(defId: defId, cases: [], isGenericInstantiation: false, typeArguments: nil)
                    return .`enum`(defId: defId)
                }
            }
            // Check if it's a trait name → resolve to traitObject type
            // This handles cases like `Error ref` inside enum definitions where
            // the type checker already resolved it but the monomorphizer re-resolves from TypeNodes
            if let traitInfo = input.genericTemplates.traits[name] {
                return .traitObject(traitDefId: traitInfo.defId, typeArgs: [])
            }
            // Otherwise treat as generic parameter
            return .genericParameter(name: name)
            
        case .reference(let inner, mutable: let mutable, span: _):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return mutable ? .mutableReference(inner: innerType) : .reference(inner: innerType)

        case .pointer(let inner, mutable: let mutable, span: _):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return mutable ? .mutablePointer(element: innerType) : .pointer(element: innerType)
            
        case .generic(let base, let args, _):
            // Look up generic template
            let resolvedArgs = try args.map { try resolveTypeNode($0, substitution: substitution) }
            
            // Check if it's a struct template
            if let template = input.genericTemplates.structTemplates[base] {
                // Directly instantiate - no need to add to pendingRequests since we're handling it now
                // The instantiateStruct method has its own caching to avoid duplicate work
                return try instantiateStruct(template: template, args: resolvedArgs)
            }
            
            // Check if it's a enum template
            if let template = input.genericTemplates.enumTemplates[base] {
                // Directly instantiate - no need to add to pendingRequests since we're handling it now
                return try instantiateEnum(template: template, args: resolvedArgs)
            }
            
            throw SemanticError(
                .generic("Unknown generic type: \(base)"),
                span: SourceSpan(location: SourceLocation(line: currentLine, column: 1))
            )
            
        case .inferredSelf:
            if let selfType = substitution["Self"] {
                return selfType
            }
            throw SemanticError(
                .generic("Self type not available in this context"),
                span: SourceSpan(location: SourceLocation(line: currentLine, column: 1))
            )
            
        case .functionType(let paramTypes, let returnType, _):
            // Resolve function type: [ParamType1, ParamType2, ..., ReturnType]Func
            let resolvedParamTypes = try paramTypes.map { try resolveTypeNode($0, substitution: substitution) }
            let resolvedReturnType = try resolveTypeNode(returnType, substitution: substitution)
            let parameters = resolvedParamTypes.map { Parameter(type: $0, kind: .byVal) }
            return .function(parameters: parameters, returns: resolvedReturnType)
            
        case .weakReference(let inner, let mutable, _):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return mutable ? .mutableWeakReference(inner: innerType) : .weakReference(inner: innerType)
        }
    }
    
    /// Resolves a built-in type name to its Type.
    internal func resolveBuiltinType(_ name: String) -> Type? {
        return SemaUtils.resolveBuiltinType(name)
    }
    
    // MARK: - Parameterized Type Resolution
    
    /// Substitutes type parameters in a type.
    /// This method extends SemaUtils.substituteType to also resolve genericStruct/genericEnum
    /// to concrete structure/enum types by instantiating them.
    internal func substituteType(_ type: Type, substitution: [String: Type]) -> Type {
        // First, apply the basic substitution
        let substituted = SemaUtils.substituteType(type, substitution: substitution, context: context)
        
        // Then, resolve genericStruct/genericEnum to concrete types
        return resolveParameterizedType(substituted, visited: [])
    }
    
    /// Resolves a parameterized type (genericStruct/genericEnum) to a concrete type.
    /// If the type still contains generic parameters, returns it unchanged.
    /// - Parameter type: The type to resolve
    /// - Parameter visited: Set of visited DefId ids to prevent infinite recursion
    /// - Returns: The resolved concrete type, or the original type if it can't be resolved yet
    internal func resolveParameterizedType(_ type: Type, visited: Set<UInt64> = []) -> Type {
        switch type {
        case .genericStruct(let typeDefId, let args):
            if let cacheKey = typeInstantiationCacheKey(for: type),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            let resolvedArgs = args.map { resolveParameterizedType($0, visited: visited) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return resolvedArgs == args ? type : .genericStruct(templateDefId: typeDefId, args: resolvedArgs)
            }

            let resolvedType = Type.genericStruct(templateDefId: typeDefId, args: resolvedArgs)
            if let cacheKey = typeInstantiationCacheKey(for: resolvedType),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            // By DECLARATION, never by name -- `template` is display/mangling only.
            if let structTemplate = input.genericTemplates.structTemplate(forDefId: typeDefId) {
                do {
                    return try instantiateStruct(template: structTemplate, args: resolvedArgs)
                } catch {
                    let argLayoutKeys = resolvedArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    let layoutName = SemaUtils.makeLayoutName(baseName: Type.spelling(typeDefId), args: resolvedArgs, context: context, templateDefId: typeDefId)
                    let defId = getOrAllocateTypeDefId(name: layoutName, kind: .structure)
                    let inheritedMutable = typeDefId.isValid ? context.isGenericStructTemplateMutable(typeDefId) : false
                    context.updateStructInfo(defId: defId, members: [], isGenericInstantiation: true, typeArguments: resolvedArgs, templateName: Type.spelling(typeDefId), templateDefId: typeDefId, isMutable: inheritedMutable)
                    return .structure(defId: defId)
                }
            }

            return resolvedArgs == args ? type : resolvedType
            
        case .genericEnum(let typeDefId, let args):
            if let cacheKey = typeInstantiationCacheKey(for: type),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            let resolvedArgs = args.map { resolveParameterizedType($0, visited: visited) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return resolvedArgs == args ? type : .genericEnum(templateDefId: typeDefId, args: resolvedArgs)
            }

            let resolvedType = Type.genericEnum(templateDefId: typeDefId, args: resolvedArgs)
            if let cacheKey = typeInstantiationCacheKey(for: resolvedType),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            // By DECLARATION, never by name -- `template` is display/mangling only.
            if let enumTemplate = input.genericTemplates.enumTemplate(forDefId: typeDefId) {
                do {
                    return try instantiateEnum(template: enumTemplate, args: resolvedArgs)
                } catch {
                    let argLayoutKeys = resolvedArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    let layoutName = SemaUtils.makeLayoutName(baseName: Type.spelling(typeDefId), args: resolvedArgs, context: context, templateDefId: typeDefId)
                    let defId = getOrAllocateTypeDefId(name: layoutName, kind: .`enum`)
                    context.updateEnumInfo(defId: defId, cases: [], isGenericInstantiation: true, typeArguments: resolvedArgs, templateDefId: typeDefId)
                    return .`enum`(defId: defId)
                }
            }

            return resolvedArgs == args ? type : resolvedType
            
        case .reference(let inner):
            let resolvedInner = resolveParameterizedType(inner, visited: visited)
            return resolvedInner == inner ? type : .reference(inner: resolvedInner)
        case .mutableReference(let inner):
            let resolvedInner = resolveParameterizedType(inner, visited: visited)
            return resolvedInner == inner ? type : .mutableReference(inner: resolvedInner)

        case .weakReference(let inner):
            let resolvedInner = resolveParameterizedType(inner, visited: visited)
            return resolvedInner == inner ? type : .weakReference(inner: resolvedInner)
        case .mutableWeakReference(let inner):
            let resolvedInner = resolveParameterizedType(inner, visited: visited)
            return resolvedInner == inner ? type : .mutableWeakReference(inner: resolvedInner)

        case .pointer(let element):
            let resolvedElement = resolveParameterizedType(element, visited: visited)
            return resolvedElement == element ? type : .pointer(element: resolvedElement)
        case .mutablePointer(let element):
            let resolvedElement = resolveParameterizedType(element, visited: visited)
            return resolvedElement == element ? type : .mutablePointer(element: resolvedElement)

        case .function(let params, let returns):
            var paramsChanged = false
            let newParams = params.map { param in
                let resolvedType = resolveParameterizedType(param.type, visited: visited)
                if resolvedType != param.type {
                    paramsChanged = true
                }
                return Parameter(type: resolvedType, kind: param.kind)
            }
            let newReturns = resolveParameterizedType(returns, visited: visited)
            if !paramsChanged && newReturns == returns {
                return type
            }
            return .function(parameters: newParams, returns: newReturns)
            
        case .structure(let defId):
            if resolvedStructEnumDefIds.contains(defId.id) {
                return type
            }
            if visited.contains(defId.id) {
                return type
            }
            var newVisited = visited
            newVisited.insert(defId.id)
            let members = context.getStructMembers(defId) ?? []
            let newMembers = members.map { member in
                (
                    name: member.name,
                    type: resolveParameterizedType(member.type, visited: newVisited),
                    mutable: member.mutable,
                    access: member.access,
                    named: member.named,
                    defaultValue: member.defaultValue
                )
            }
            let membersChanged = zip(members, newMembers).contains { old, new in
                old.type != new.type
            }
            if !membersChanged {
                resolvedStructEnumDefIds.insert(defId.id)
                return type
            }
            let isGeneric = context.isGenericInstantiation(defId) ?? false
            let typeArgs = context.getTypeArguments(defId)
            context.updateStructInfo(defId: defId, members: newMembers, isGenericInstantiation: isGeneric, typeArguments: typeArgs, isMutable: context.isTypeMutable(defId))
            resolvedStructEnumDefIds.insert(defId.id)
            return .structure(defId: defId)
            
        case .`enum`(let defId):
            if resolvedStructEnumDefIds.contains(defId.id) {
                return type
            }
            if visited.contains(defId.id) {
                return type
            }
            var newVisited = visited
            newVisited.insert(defId.id)
            let cases = context.getEnumCases(defId) ?? []
            let newCases = cases.map { enumCase in
                EnumCase(
                    name: enumCase.name,
                    parameters: enumCase.parameters.map { param in
                        (name: param.name, type: resolveParameterizedType(param.type, visited: newVisited), access: param.access, named: param.named, defaultValue: param.defaultValue)
                    }
                )
            }
            let casesChanged = zip(cases, newCases).contains { old, new in
                zip(old.parameters, new.parameters).contains { oldParam, newParam in
                    oldParam.type != newParam.type
                }
            }
            if !casesChanged {
                resolvedStructEnumDefIds.insert(defId.id)
                return type
            }
            let isGeneric = context.isGenericInstantiation(defId) ?? false
            let typeArgs = context.getTypeArguments(defId)
            context.updateEnumInfo(defId: defId, cases: newCases, isGenericInstantiation: isGeneric, typeArguments: typeArgs)
            resolvedStructEnumDefIds.insert(defId.id)
            return .`enum`(defId: defId)
            
        default:
            return type
        }
    }
    
    // MARK: - Global Node Type Resolution
    
    /// Resolves all genericStruct/genericEnum types in a global node.
    /// This ensures no parameterized types reach CodeGen.
    internal func resolveTypesInGlobalNode(_ node: TypedGlobalNode) throws -> TypedGlobalNode {
        switch node {
        case .foreignType(let identifier):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            return .foreignType(identifier: newIdentifier)
        case .foreignStruct(let identifier, let fields):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            let newFields = fields.map { field in
                (name: field.name, type: resolveParameterizedType(field.type))
            }
            return .foreignStruct(identifier: newIdentifier, fields: newFields)
        case .foreignGlobalVariable(let identifier, let mutable):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            return .foreignGlobalVariable(identifier: newIdentifier, mutable: mutable)
        case .foreignFunction(let identifier, let parameters):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            let newParams = parameters.map { param in
                copySymbolWithNewDefId(param, newType: resolveParameterizedType(param.type))
            }
            return .foreignFunction(identifier: newIdentifier, parameters: newParams)
        case .globalStructDeclaration(let identifier, let parameters):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            let newParams = parameters.map { param in
                copySymbolWithNewDefId(
                    param,
                    newType: resolveParameterizedType(param.type)
                )
            }
            return .globalStructDeclaration(identifier: newIdentifier, parameters: newParams)
            
        case .globalEnumDeclaration(let identifier, let cases):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            let newCases = cases.map { enumCase in
                EnumCase(
                    name: enumCase.name,
                    parameters: enumCase.parameters.map { param in
                        (name: param.name, type: resolveParameterizedType(param.type), access: param.access, named: param.named, defaultValue: param.defaultValue)
                    }
                )
            }
            return .globalEnumDeclaration(identifier: newIdentifier, cases: newCases)
            
        case .globalFunction(let identifier, let parameters, let body):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            // Register the remap so method references to the original DefId
            // can find the emitted function.
            if newIdentifier.defId != identifier.defId {
                remappedFunctionDefIds[identifier.defId, default: []].append(
                    (defId: newIdentifier.defId, type: newIdentifier.type)
                )
            }
            let newParams = parameters.map { param in
                copySymbolPreservingDefId(
                    param,
                    newType: resolveParameterizedType(param.type)
                )
            }
            let newBody = resolveTypesInExpression(body)
            return .globalFunction(identifier: newIdentifier, parameters: newParams, body: newBody)
            
        case .givenDeclaration(let type, let trait, let methods):
            // Resolve the type to get the concrete type name
            let resolvedType = resolveParameterizedType(type)
            let resolvedTrait: TypedTraitConformance? = trait.map {
                TypedTraitConformance(
                    traitDefId: $0.traitDefId,
                    traitName: $0.traitName,
                    traitTypeArgs: $0.traitTypeArgs.map { resolveParameterizedType($0) }
                )
            }
            let typeName: String
            switch resolvedType {
            case .structure(let defId):
                let name = context.getName(defId) ?? resolvedType.description
                typeName = name
            case .`enum`(let defId):
                let name = context.getName(defId) ?? resolvedType.description
                typeName = name
            default:
                typeName = resolvedType.description
            }

            var methodMap: [String: ConcreteMethodEntry] = [:]
            let newMethods = methods.map { method -> TypedMethodDeclaration in
                let canonicalMethodBaseName = receiverMethodDispatch[method.identifier.defId]?.methodName
                    ?? (context.getName(method.identifier.defId) ?? "<unknown>")

                let remappedIdentifier = makeSymbol(
                    name: canonicalMethodBaseName,
                    type: resolveParameterizedType(method.identifier.type),
                    kind: method.identifier.kind,
                    modulePath: semanticMethodModulePath(ownerType: resolvedType, trait: resolvedTrait, methodTypeArgs: []),
                    sourceFile: context.getSourceFile(method.identifier.defId) ?? "",
                    access: context.getAccess(method.identifier.defId) ?? .module_private
                )

                let entry = ConcreteMethodEntry(symbol: remappedIdentifier, trait: resolvedTrait)
                extensionMethods[context.receiverMethodLookupKey(resolvedType, canonicalMethodBaseName)] = entry
                // Only mark as instantiated if the method type is fully concrete.
                // Methods with method type params (e.g. `join[T]`) need per-type-arg
                // instantiations — the remapped symbol is just the template's
                // identity, not the emitted function.
                if !context.containsGenericParameter(remappedIdentifier.type) {
                    instantiatedMethodDefIds.insert(remappedIdentifier.defId)
                }
                remappedFunctionDefIds[method.identifier.defId, default: []].append((defId: remappedIdentifier.defId, type: remappedIdentifier.type))
                // Register in the identity-keyed map (rustc: Instance table keyed
                // by DefId + GenericArgs) so resolveMethodInstanceByIdentity L1
                // can find this instantiation by direct hash lookup.
                // ONLY register when the owner type is concrete — generic owners
                // (e.g. `Option[T]` in `given [T] Option[T]`) must be instantiated
                // via L2, not matched directly (their keys would collide with
                // concrete lookups).
                if !context.containsGenericParameter(resolvedType)
                    && !context.containsGenericParameter(remappedIdentifier.type) {
                    let identityKey = context.receiverMethodKey(resolvedType, method.identifier.defId)
                    extensionMethodDefIds[identityKey] = remappedIdentifier.defId
                }
                // Also register under the TRAIT method's DefId (from the
                // definition-time `traitMethodDefId` link) so that methodReference
                // nodes carrying the trait method DefId can find this implementation.
                var resolvedTraitMethodDefId = receiverMethodDispatch[method.identifier.defId]?.traitMethodDefId
                    ?? receiverMethodDispatch[remappedIdentifier.defId]?.traitMethodDefId
                if resolvedTraitMethodDefId == nil {
                    // Fallback: find the trait method DefId by method name in
                    // receiverMethodDispatch (bounded reverse lookup).
                    for (_, info) in receiverMethodDispatch
                    where info.methodName == canonicalMethodBaseName && info.traitMethodDefId != nil {
                        resolvedTraitMethodDefId = info.traitMethodDefId
                        break
                    }
                }
                if let traitMethodDefId = resolvedTraitMethodDefId {
                    remappedFunctionDefIds[traitMethodDefId, default: []].append(
                        (defId: remappedIdentifier.defId, type: remappedIdentifier.type)
                    )
                    // Dual-key: also register in the identity map under the trait
                    // method DefId so trait-method references find this impl.
                    if !context.containsGenericParameter(resolvedType)
                        && !context.containsGenericParameter(remappedIdentifier.type) {
                        let traitIdentityKey = context.receiverMethodKey(resolvedType, traitMethodDefId)
                        extensionMethodDefIds[traitIdentityKey] = remappedIdentifier.defId
                    }
                }
                if let dispatchInfo = receiverMethodDispatch[method.identifier.defId] {
                    receiverMethodDispatch[remappedIdentifier.defId] = ReceiverMethodDispatchInfo(
                        methodDefId: dispatchInfo.methodDefId,
                        methodName: dispatchInfo.methodName,
                        owner: dispatchInfo.owner,
                        conformanceTraitName: dispatchInfo.conformanceTraitName,
                        conformanceTraitDefId: dispatchInfo.conformanceTraitDefId,
                        traitMethodDefId: dispatchInfo.traitMethodDefId
                    )
                }

                return TypedMethodDeclaration(
                    identifier: remappedIdentifier,
                    parameters: method.parameters.map { param in
                        copySymbolPreservingDefId(
                            param,
                            newType: resolveParameterizedType(param.type)
                        )
                    },
                    body: resolveTypesInExpression(method.body),
                    returnType: resolveParameterizedType(method.returnType)
                )
            }
            for (methodName, entry) in methodMap {
                extensionMethods[context.receiverMethodLookupKey(resolvedType, methodName)] = entry
            }
            return .givenDeclaration(type: resolvedType, trait: resolvedTrait, methods: newMethods)
            
        case .globalVariable(let identifier, let value, let kind):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            
            return .globalVariable(identifier: newIdentifier, value: resolveTypesInExpression(value), kind: kind)
            
        case .genericTypeTemplate, .genericFunctionTemplate:
            // Templates should not reach this point
            return node
        }
    }
}


// MARK: - Expression Type Resolution Extension

extension Monomorphizer {
    /// Resolves all genericStruct/genericEnum types in an expression.
    internal func resolveTypesInExpression(_ expr: TypedExpressionNode) -> TypedExpressionNode {
        switch expr {
        case .integerLiteral(let value, let type):
            return .integerLiteral(value: value, type: resolveParameterizedType(type))
            
        case .floatLiteral(let value, let type):
            return .floatLiteral(value: value, type: resolveParameterizedType(type))
            
        case .stringLiteral(let value, let type):
            return .stringLiteral(value: value, type: resolveParameterizedType(type))

        case .interpolatedString(let parts, let type):
            let newParts = parts.map { part -> TypedInterpolatedPart in
                switch part {
                case .literal(let value):
                    return .literal(value)
                case .expression(let expr):
                    return .expression(resolveTypesInExpression(expr))
                }
            }
            return .interpolatedString(parts: newParts, type: resolveParameterizedType(type))
            
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

        case .wrappingArithmeticExpression(let left, let op, let right, let type):
            return .wrappingArithmeticExpression(
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

        case .isExpression(let subject, let pattern, let type):
            return .isExpression(
                subject: resolveTypesInExpression(subject),
                pattern: resolveTypesInPattern(pattern),
                type: resolveParameterizedType(type)
            )

        case .isNotExpression(let subject, let pattern, let type):
            return .isNotExpression(
                subject: resolveTypesInExpression(subject),
                pattern: resolveTypesInPattern(pattern),
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

        case .unsafeDerefExpression(let expression, let type):
            return .unsafeDerefExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .referenceExpression(let expression, let type):
            return .referenceExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )

        case .ptrExpression(let expression, let type):
            return .ptrExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .variable(let identifier):
            let resolvedType = resolveParameterizedType(identifier.type)
            if case .function = identifier.kind,
               let instantiated = resolveStandaloneMethodFunctionReference(
                definitionMethod: identifier,
                substitutedFunctionType: resolvedType
               ) {
                return .variable(identifier: instantiated)
            }
            return .variable(
                identifier: Symbol(
                    defId: identifier.defId,
                    type: resolvedType,
                    kind: identifier.kind
                )
            )
            
        case .blockExpression(let statements, let tailExpression, let type):
            let newStatements = statements.map { resolveTypesInStatement($0) }
            return .blockExpression(
                statements: newStatements,
                tailExpression: tailExpression.map { resolveTypesInExpression($0) },
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
            var newCallee = resolveTypesInExpression(callee)
            var newArguments = arguments.map { resolveTypesInExpression($0) }
            let newType = resolveParameterizedType(type)

            if case .variable(let identifier) = newCallee,
               case .function = identifier.kind {
                let expectedCallType = Type.function(
                    parameters: newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                if let instantiated = resolveStandaloneMethodFunctionReference(
                    definitionMethod: identifier,
                    substitutedFunctionType: expectedCallType
                ) {
                    newCallee = .variable(identifier: instantiated)
                }
            }

            if case .traitMethodPlaceholder(let traitName, let traitDefId, let traitMethodDefId, let methodName, let base, let methodTypeArgs, _) = newCallee,
               extractTraitObjectType(base.type) == nil,
               !context.containsGenericParameter(base.type) {
                let lookupBaseType = methodLookupBaseType(for: base)
                let expectedCallType = Type.function(
                    parameters: [Parameter(type: lookupBaseType, kind: .byVal)]
                        + newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                if let concreteMethod = resolveTraitPlaceholderMethodByIdentity(
                    traitMethodDefId: traitMethodDefId,
                    expectedMethodType: expectedCallType,
                    methodTypeArgs: methodTypeArgs,
                    receiverType: lookupBaseType
                ) {
                    let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                    if case .function(let params, _) = resolvedMethodType {
                        newArguments = zip(newArguments, params.dropFirst()).map { arg, param in
                            alignMethodReferenceBase(
                                arg,
                                to: .function(
                                    parameters: [Parameter(type: param.type, kind: param.kind)],
                                    returns: param.type
                                )
                            )
                        }
                    }
                    newCallee = .methodReference(
                        base: alignMethodReferenceBase(base, to: resolvedMethodType),
                        method: Symbol(defId: concreteMethod.defId, type: resolvedMethodType, kind: concreteMethod.kind),
                        typeArgs: nil,
                        methodTypeArgs: methodTypeArgs,
                        type: resolvedMethodType
                    )
                } else {
                    newCallee = .traitMethodPlaceholder(
                        traitName: traitName,
                        traitDefId: traitDefId,
                        traitMethodDefId: traitMethodDefId,
                        methodName: methodName,
                        base: base,
                        methodTypeArgs: methodTypeArgs,
                        type: newType
                    )
                }
            }

            // Convert traitMethodPlaceholder with trait object base to traitMethodCall
            // This handles the case where a generic function like [T ToString]f(a T ref)
            // is instantiated with T = traitObject("ToString") — method calls on the
            // trait object parameter must use vtable dynamic dispatch.
            if case .traitMethodPlaceholder(_, _, _, let methodName, let base, _, _) = newCallee {
                if let traitObjInfo = extractTraitObjectType(base.type) {
                    if let methodIndex = vtableMethodIndex(traitName: traitObjInfo.traitName, methodName: methodName) {
                        // If the base is a deref of a trait object reference, use the
                        // un-dereferenced reference as the receiver. traitMethodCall expects
                        // a TraitRef (reference type), not a bare traitObject value.
                        let receiver: TypedExpressionNode
                        if case .derefExpression(let inner, _) = base,
                           case .reference(let refInner) = inner.type,
                           case .traitObject = refInner {
                            receiver = inner
                        } else if case .derefExpression(let inner, _) = base,
                                  case .mutableReference(let refInner) = inner.type,
                           case .traitObject = refInner {
                            receiver = inner
                        } else {
                            receiver = base
                        }
                        return .traitMethodCall(
                            receiver: receiver,
                            traitName: traitObjInfo.traitName,
                            traitDefId: traitObjInfo.traitDefId,
                            methodName: methodName,
                            methodIndex: methodIndex,
                            arguments: newArguments,
                            type: newType
                        )
                    }
                }
            }

            // Resolve method reference to the instantiated identity of the
            // definition-time method. Only substitutes types — never re-decides
            // which method via name lookup.
            if case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, _) = newCallee,
               !context.containsGenericParameter(base.type) {
                let declaredMethodType = resolveParameterizedType(method.type)
                let substMethodType: Type = {
                    guard case .function(let declaredParams, _) = declaredMethodType,
                          let receiverParam = declaredParams.first else {
                        return declaredMethodType
                    }
                    let declaredArgumentParams = Array(declaredParams.dropFirst())
                    let argumentParams = newArguments.enumerated().map { index, argument in
                        Parameter(
                            type: argument.type,
                            kind: index < declaredArgumentParams.count ? declaredArgumentParams[index].kind : .byVal
                        )
                    }
                    return .function(
                        parameters: [receiverParam] + argumentParams,
                        returns: newType
                    )
                }()
                let substMArgs = (methodTypeArgs ?? []).map { resolveParameterizedType($0) }
                let resolution = (try? resolveMethodInstanceByIdentityForReceiver(
                    definitionMethod: method,
                    substitutedMethodType: substMethodType,
                    substitutedMethodTypeArgs: substMArgs,
                    receiverType: base.type
                )) ?? .keepDefinitionTime(type: substMethodType)
                switch resolution {
                case .instantiated(let inst):
                    let instType = resolveParameterizedType(inst.type)
                    let adjustedBase = alignMethodReferenceBase(base, to: instType)
                    newCallee = .methodReference(
                        base: adjustedBase,
                        method: Symbol(defId: inst.defId, type: instType, kind: inst.kind),
                        typeArgs: typeArgs,
                        methodTypeArgs: substMArgs,
                        type: instType
                    )
                case .keepDefinitionTime(let resolvedType):
                    let instType = resolveParameterizedType(resolvedType)
                    newCallee = .methodReference(
                        base: base,
                        method: Symbol(defId: method.defId, type: instType, kind: method.kind),
                        typeArgs: typeArgs,
                        methodTypeArgs: substMArgs,
                        type: instType
                    )
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
            if resolvedTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
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
                let key = InstantiationKey.function(templateDefId: template.defId, args: resolvedTypeArgs)
                if !input.genericTemplates.intrinsicGenericFunctions.contains(functionName)
                    && !processedRequestKeys.contains(key) {
                    pendingRequests.append(InstantiationRequest(
                        kind: .function(template: template, args: resolvedTypeArgs),
                        sourceLine: currentLine,
                        sourceFileName: currentFileName
                    ))
                }
                
                // Build specialized function symbol name
                let argLayoutKeys = resolvedTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                let specializedFunctionSymbolName = "\(functionName)_\(argLayoutKeys)"
                
                // Create the callee as a variable reference to the specialized function symbol
                let functionType = Type.function(
                    parameters: newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                let callee: TypedExpressionNode = .variable(
                    identifier: makeSymbol(name: specializedFunctionSymbolName, type: functionType, kind: .function)
                )
                
                return .call(callee: callee, arguments: newArguments, type: newType)
            }
            
            // Keep as genericCall when no matching generic template is available.
            return .genericCall(
                functionName: functionName,
                typeArgs: resolvedTypeArgs,
                arguments: newArguments,
                type: newType
            )
            
        case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, _):
            let newBase = resolveTypesInExpression(base)
            let substMethodType = resolveParameterizedType(method.type)
            let resolvedTypeArgs = typeArgs?.map { resolveParameterizedType($0) }
            let substMArgs = (methodTypeArgs ?? []).map { resolveParameterizedType($0) }
            var adjustedBase = newBase
            var resolvedExpressionType = substMethodType
            var newMethod = Symbol(defId: method.defId, type: substMethodType, kind: method.kind)

            if !context.containsGenericParameter(adjustedBase.type) {
                let resolution: MethodInstanceResolution
                do {
                    resolution = try resolveMethodInstanceByIdentityForReceiver(
                        definitionMethod: method,
                        substitutedMethodType: substMethodType,
                        substitutedMethodTypeArgs: substMArgs,
                        receiverType: adjustedBase.type
                    )
                } catch {
                    resolution = .keepDefinitionTime(type: substMethodType)
                }
                switch resolution {
                case .instantiated(let inst):
                    let instType = resolveParameterizedType(inst.type)
                    adjustedBase = alignMethodReferenceBase(adjustedBase, to: instType)
                    newMethod = Symbol(defId: inst.defId, type: instType, kind: inst.kind)
                    resolvedExpressionType = instType
                case .keepDefinitionTime(let resolvedType):
                    resolvedExpressionType = resolveParameterizedType(resolvedType)
                    newMethod = Symbol(defId: method.defId, type: resolvedExpressionType, kind: method.kind)
                }
            }

            return .methodReference(
                base: adjustedBase,
                method: newMethod,
                typeArgs: resolvedTypeArgs,
                methodTypeArgs: substMArgs,
                type: resolvedExpressionType
            )
            
        case .traitMethodPlaceholder(let traitName, let traitDefId, let traitMethodDefId, let methodName, let base, let methodTypeArgs, let type):
            // Resolve types in the placeholder
            let newBase = resolveTypesInExpression(base)
            let resolvedMethodTypeArgs = methodTypeArgs.map { resolveParameterizedType($0) }
            let resolvedType = resolveParameterizedType(type)
            let lookupBaseType = methodLookupBaseType(for: newBase)
            let normalizedExpectedMethodType = normalizedTraitPlaceholderExpectedMethodType(
                resolvedType,
                for: lookupBaseType
            )
            // Try to resolve to concrete method if base type is now concrete
            if !context.containsGenericParameter(lookupBaseType) {
                // Check if the base type is a trait object — if so, keep as placeholder
                // (the .call case will convert it to traitMethodCall with proper arguments)
                if extractTraitObjectType(lookupBaseType) != nil {
                    return .traitMethodPlaceholder(
                        traitName: traitName,
                        traitDefId: traitDefId,
                        traitMethodDefId: traitMethodDefId,
                        methodName: methodName,
                        base: newBase,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        type: resolvedType
                    )
                }

                if let concreteMethod = resolveTraitPlaceholderMethodByIdentity(
                    traitMethodDefId: traitMethodDefId,
                    expectedMethodType: normalizedExpectedMethodType,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    receiverType: lookupBaseType
                ) {
                    let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                    let adjustedBase = alignMethodReferenceBase(newBase, to: resolvedMethodType)
                    return .methodReference(
                        base: adjustedBase,
                        method: Symbol(defId: concreteMethod.defId, type: resolvedMethodType, kind: concreteMethod.kind),
                        typeArgs: nil,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        type: resolvedMethodType
                    )
                }
            }
            
            // Keep as placeholder if base type is still generic
            return .traitMethodPlaceholder(
                traitName: traitName,
                traitDefId: traitDefId,
                traitMethodDefId: traitMethodDefId,
                methodName: methodName,
                base: newBase,
                methodTypeArgs: resolvedMethodTypeArgs,
                type: resolvedType
            )

        case .traitObjectConversion(let inner, let traitName, let traitDefId, let traitTypeArgs, let concreteType, let type):
            let resolvedConcreteType = resolveParameterizedType(concreteType)
            let resolvedTraitTypeArgs = traitTypeArgs.map { resolveParameterizedType($0) }
            // Collect vtable request for non-generic code paths
            if !context.containsGenericParameter(resolvedConcreteType) {
                let traitRef = CanonicalTraitRef(traitName: traitName, traitDefId: traitDefId, traitTypeArgs: resolvedTraitTypeArgs)
                vtableRequests.insert(VtableRequest(
                    concreteType: resolvedConcreteType,
                    traitName: traitName,
                    traitDefId: traitDefId,
                    traitTypeArgs: resolvedTraitTypeArgs,
                    witnessKey: ConformanceWitness.key(selfType: resolvedConcreteType, traitRef: traitRef)
                ))
                materializeConformanceWitness(
                    concreteType: resolvedConcreteType,
                    traitName: traitName,
                    traitDefId: traitDefId,
                    traitTypeArgs: resolvedTraitTypeArgs
                )
            }
            return .traitObjectConversion(
                inner: resolveTypesInExpression(inner),
                traitName: traitName,
                traitDefId: traitDefId,
                traitTypeArgs: resolvedTraitTypeArgs,
                concreteType: resolvedConcreteType,
                type: resolveParameterizedType(type)
            )

        case .traitMethodCall(let receiver, let traitName, let traitDefId, let methodName, let methodIndex, let arguments, let type):
            return .traitMethodCall(
                receiver: resolveTypesInExpression(receiver),
                traitName: traitName,
                traitDefId: traitDefId,
                methodName: methodName,
                methodIndex: methodIndex,
                arguments: arguments.map { resolveTypesInExpression($0) },
                type: resolveParameterizedType(type)
            )
            
        case .typeConstruction(let identifier, let typeArgs, let arguments, let type):
            let resolvedType = resolveParameterizedType(identifier.type)
            
            // Update the identifier name to match the resolved type's layout name
            var newName = context.getName(identifier.defId) ?? "<unknown>"
            if case .structure(let defId) = resolvedType {
                newName = context.getName(defId) ?? newName
            } else if case .`enum`(let defId) = resolvedType {
                newName = context.getName(defId) ?? newName
            }
            
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newName: newName,
                newType: resolvedType
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
                copySymbolWithNewDefId(
                    sym,
                    newType: resolveParameterizedType(sym.type)
                )
            }
            return .memberPath(
                source: resolveTypesInExpression(source),
                path: newPath
            )
            
        case .enumConstruction(let type, let caseName, let arguments):
            return .enumConstruction(
                type: resolveParameterizedType(type),
                caseName: caseName,
                arguments: arguments.map { resolveTypesInExpression($0) }
            )
            
        case .intrinsicCall(let intrinsic):
            return .intrinsicCall(resolveTypesInIntrinsic(intrinsic))
            
        case .whenExpression(let subject, let cases, let type):
            let newCases = cases.map { matchCase in
                TypedMatchCase(
                    pattern: resolveTypesInPattern(matchCase.pattern),
                    guardExpr: matchCase.guardExpr.map { resolveTypesInExpression($0) },
                    body: resolveTypesInExpression(matchCase.body)
                )
            }
            return .whenExpression(
                subject: resolveTypesInExpression(subject),
                cases: newCases,
                type: resolveParameterizedType(type)
            )
            
        case .staticMethodCall(let baseType, let methodName, let typeArgs, let methodTypeArgs, let arguments, let type):
            // Resolve the base type and type arguments
            let resolvedBaseType = resolveParameterizedType(baseType)
            let resolvedTypeArgs = typeArgs.map { resolveParameterizedType($0) }
            let resolvedMethodTypeArgs = methodTypeArgs.map { resolveParameterizedType($0) }
            let resolvedArguments = arguments.map { resolveTypesInExpression($0) }
            let resolvedReturnType = resolveParameterizedType(type)
            
            // If base type still contains generic parameters, keep as staticMethodCall
            if context.containsGenericParameter(resolvedBaseType) || resolvedTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
                return .staticMethodCall(
                    baseType: resolvedBaseType,
                    methodName: methodName,
                    typeArgs: resolvedTypeArgs,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    arguments: resolvedArguments,
                    type: resolvedReturnType
                )
            }

            // Compute extension-template and emitted symbol scopes from the resolved base type
            let templateName: String
            let emittedTypeScopeName: String
            let isGenericInstantiation: Bool
            switch resolvedBaseType {
            case .structure(let defId):
                let name = context.getName(defId) ?? resolvedBaseType.description
                // Use stored templateName if available, otherwise fall back to full name
                templateName = context.getTemplateName(defId) ?? name
                emittedTypeScopeName = context.getQualifiedName(defId) ?? name
                isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
            case .genericStruct(let tplDefId, _):
                templateName = Type.spelling(tplDefId)
                emittedTypeScopeName = Type.spelling(tplDefId)  // Generic types don't have module path yet
                isGenericInstantiation = false
            case .`enum`(let defId):
                let name = context.getName(defId) ?? resolvedBaseType.description
                // Use stored templateName if available, otherwise fall back to full name
                templateName = context.getTemplateName(defId) ?? name
                emittedTypeScopeName = context.getQualifiedName(defId) ?? name
                isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
            case .genericEnum(let tplDefId, _):
                templateName = Type.spelling(tplDefId)
                emittedTypeScopeName = Type.spelling(tplDefId)  // Generic types don't have module path yet
                isGenericInstantiation = false
            default:
                templateName = resolvedBaseType.description
                emittedTypeScopeName = templateName
                isGenericInstantiation = false
            }
            
            let expectedMethodType = Type.function(
                parameters: resolvedArguments.map { Parameter(type: $0.type, kind: .byVal) },
                returns: resolvedReturnType
            )

            let directLookupKey = context.receiverMethodLookupKey(resolvedBaseType, methodName)
            let staticEntry: ConcreteMethodEntry? = extensionMethods[directLookupKey] ?? {
                let matches = extensionMethods.filter { key, entry in
                    key.owner == directLookupKey.owner
                        && key.ownerArgs == directLookupKey.ownerArgs
                        && (key.methodName == methodName || key.methodName.hasSuffix("_\(methodName)"))
                        && methodTypeMatchesExpected(entry.symbol.type, expected: expectedMethodType)
                }.map(\.value)
                return matches.count == 1 ? matches[0] : nil
            }()

            if let entry = staticEntry {
                let entryType = resolveParameterizedType(entry.symbol.type)
                if !context.containsGenericParameter(entryType),
                   methodTypeMatchesExpected(entryType, expected: expectedMethodType) {
                    let callee: TypedExpressionNode = .variable(
                        identifier: Symbol(
                            defId: entry.symbol.defId,
                            type: entryType,
                            kind: entry.symbol.kind
                        )
                    )
                    return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
                }
                var lookupDefIds: [DefId] = [entry.symbol.defId]
                if let dispatch = receiverMethodDispatch[entry.symbol.defId] {
                    lookupDefIds.append(dispatch.methodDefId)
                    if let traitMethodDefId = dispatch.traitMethodDefId {
                        lookupDefIds.append(traitMethodDefId)
                    }
                }
                var seenLookupDefIds = Set<DefId>()
                for lookupDefId in lookupDefIds where seenLookupDefIds.insert(lookupDefId).inserted {
                    let key = context.receiverMethodKey(
                        resolvedBaseType,
                        lookupDefId,
                        methodTypeArgs: resolvedMethodTypeArgs
                    )
                    if let hit = extensionMethodDefIds[key] {
                        let callee: TypedExpressionNode = .variable(
                            identifier: Symbol(
                                defId: hit,
                                type: expectedMethodType,
                                kind: .function
                            )
                        )
                        return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
                    }
                }
                for lookupDefId in lookupDefIds where seenLookupDefIds.contains(lookupDefId) {
                    let matches = (remappedFunctionDefIds[lookupDefId] ?? []).filter {
                        resolveParameterizedType($0.type) == expectedMethodType
                    }
                    if matches.count == 1 {
                        let callee: TypedExpressionNode = .variable(
                            identifier: Symbol(
                                defId: matches[0].defId,
                                type: expectedMethodType,
                                kind: .function
                            )
                        )
                        return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
                    }
                }
                let resolution = (try? resolveMethodInstanceByIdentityForReceiver(
                    definitionMethod: entry.symbol,
                    substitutedMethodType: expectedMethodType,
                    substitutedMethodTypeArgs: resolvedMethodTypeArgs,
                    receiverType: resolvedBaseType
                )) ?? .keepDefinitionTime(type: expectedMethodType)
                if case .instantiated(let instantiated) = resolution {
                    let functionType = resolveParameterizedType(instantiated.type)
                    let callee: TypedExpressionNode = .variable(
                        identifier: Symbol(
                            defId: instantiated.defId,
                            type: functionType,
                            kind: instantiated.kind
                        )
                    )
                    return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
                }
            }

            if let extensions = input.genericTemplates.extensionMethods[context.methodOwner(of: resolvedBaseType)],
               let template = selectExtensionTemplate(
                extensions,
                name: methodName,
                methodTypeArgCount: resolvedMethodTypeArgs.count,
                extensionTypeArgCount: resolvedTypeArgs.count
               ) {
                let structureName: String = {
                    switch resolvedBaseType {
                    case .structure(let defId), .enum(let defId):
                        return context.getTemplateName(defId) ?? context.getName(defId) ?? templateName
                    case .genericStruct(let defId, _), .genericEnum(let defId, _):
                        return Type.spelling(defId)
                    default:
                        return templateName
                    }
                }()
                let instantiated = try? instantiateExtensionMethodFromEntry(
                    baseType: resolvedBaseType,
                    structureName: structureName,
                    genericArgs: resolvedTypeArgs,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    methodInfo: template
                )
                if let instantiated {
                    let functionType = resolveParameterizedType(instantiated.type)
                    let callee: TypedExpressionNode = .variable(
                        identifier: Symbol(
                            defId: instantiated.defId,
                            type: functionType,
                            kind: instantiated.kind
                        )
                    )
                    return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
                }
            }

            var traitExtensionMatches: [(owner: MethodOwner, template: GenericExtensionMethodTemplate, args: [Type])] = []
            for (owner, templates) in input.genericTemplates.extensionMethods {
                for template in templates where template.method.name == methodName
                    && template.method.typeParameters.count == resolvedMethodTypeArgs.count {
                    if let inferredArgs = try? inferTraitExtensionTypeArgs(
                        baseType: resolvedBaseType,
                        methodInfo: template,
                        expectedMethodType: expectedMethodType,
                        methodTypeArgs: resolvedMethodTypeArgs
                    ) {
                        traitExtensionMatches.append((owner: owner, template: template, args: inferredArgs))
                    }
                }
            }
            if traitExtensionMatches.count == 1 {
                let match = traitExtensionMatches[0]
                let structureName: String = {
                    switch match.owner {
                    case .decl(let defId):
                        return context.spelling(defId)
                    case .builtin(let name):
                        return name
                    }
                }()
                if let instantiated = try? instantiateExtensionMethodFromEntry(
                    baseType: resolvedBaseType,
                    structureName: structureName,
                    genericArgs: match.args,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    methodInfo: match.template
                ) {
                    let functionType = resolveParameterizedType(instantiated.type)
                    let callee: TypedExpressionNode = .variable(
                        identifier: Symbol(
                            defId: instantiated.defId,
                            type: functionType,
                            kind: instantiated.kind
                        )
                    )
                    return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
                }
            }

            return .staticMethodCall(
                baseType: resolvedBaseType,
                methodName: methodName,
                typeArgs: resolvedTypeArgs,
                methodTypeArgs: resolvedMethodTypeArgs,
                arguments: resolvedArguments,
                type: resolvedReturnType
            )
            
        case .lambdaExpression(let parameters, let captures, let body, let type):
            // Resolve types in lambda parameters
            let newParameters = parameters.map { param in
                copySymbolPreservingDefId(
                    param,
                    newType: resolveParameterizedType(param.type)
                )
            }
            // Resolve types in captures
            let newCaptures = captures.map { capture in
                CapturedVariable(
                    symbol: copySymbolPreservingDefId(
                        capture.symbol,
                        newType: resolveParameterizedType(capture.symbol.type)
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
}


// MARK: - Statement Type Resolution Extension

extension Monomorphizer {
    
    /// Resolves types in a statement.
    internal func resolveTypesInStatement(_ stmt: TypedStatementNode) -> TypedStatementNode {
        switch stmt {
        case .variableDeclaration(let identifier, let value, let mutable):
            let newIdentifier = copySymbolPreservingDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
            return .variableDeclaration(
                identifier: newIdentifier,
                value: resolveTypesInExpression(value),
                mutable: mutable
            )

        case .tupleVariableDeclaration(let tupleSymbol, let tupleValue, let bindings):
            let newTupleSymbol = copySymbolPreservingDefId(
                tupleSymbol, newType: resolveParameterizedType(tupleSymbol.type))
            let newBindings = bindings.map { binding -> Symbol? in
                binding.map {
                    copySymbolPreservingDefId($0, newType: resolveParameterizedType($0.type))
                }
            }
            return .tupleVariableDeclaration(
                tupleSymbol: newTupleSymbol, tupleValue: resolveTypesInExpression(tupleValue),
                bindings: newBindings
            )
            
        case .assignment(let target, let op, let value):
            return .assignment(
                target: resolveTypesInExpression(target),
                operator: op,
                value: resolveTypesInExpression(value)
            )
            
        case .expression(let expr):
            return .expression(resolveTypesInExpression(expr))

        case .ifStatement(let condition, let thenBranch, let elseBranch):
            return .ifStatement(
                condition: resolveTypesInExpression(condition),
                thenBranch: resolveTypesInExpression(thenBranch),
                elseBranch: elseBranch.map { resolveTypesInExpression($0) }
            )

        case .ifPatternStatement(let subject, let pattern, let bindings, let thenBranch, let elseBranch):
            return .ifPatternStatement(
                subject: resolveTypesInExpression(subject),
                pattern: resolveTypesInPattern(pattern),
                bindings: bindings.map { ($0.0, $0.1, resolveParameterizedType($0.2)) },
                thenBranch: resolveTypesInExpression(thenBranch),
                elseBranch: elseBranch.map { resolveTypesInExpression($0) }
            )

        case .whileStatement(let condition, let body):
            return .whileStatement(
                condition: resolveTypesInExpression(condition),
                body: resolveTypesInExpression(body)
            )

        case .whilePatternStatement(let subject, let pattern, let bindings, let body):
            return .whilePatternStatement(
                subject: resolveTypesInExpression(subject),
                pattern: resolveTypesInPattern(pattern),
                bindings: bindings.map { ($0.0, $0.1, resolveParameterizedType($0.2)) },
                body: resolveTypesInExpression(body)
            )

        case .whenStatement(let subject, let cases):
            return .whenStatement(
                subject: resolveTypesInExpression(subject),
                cases: cases.map {
                    TypedStatementMatchCase(
                        pattern: resolveTypesInPattern($0.pattern),
                        guardExpr: $0.guardExpr.map { resolveTypesInExpression($0) },
                        body: resolveTypesInExpression($0.body)
                    )
                }
            )
            
        case .return(let value):
            return .return(value: value.map { resolveTypesInExpression($0) })
            
        case .break:
            return .break
            
        case .continue:
            return .continue

        case .deferStatement(let expression):
            return .deferStatement(expression: resolveTypesInExpression(expression))

        }
    }
}

// MARK: - Pattern Type Resolution Extension

extension Monomorphizer {

    /// Re-resolve a list pattern's std methods against its now-concrete list type.
    ///
    /// A symbol kept from the generic template names a function monomorphization
    /// never emits, so the call would not link. Once `List[T]` has a real `T`,
    /// `count` and `__index_get` are instantiated for it exactly as an ordinary
    /// `xs.count()` / `xs[i]` call instantiates them.
    internal func refreshListPatternOps(
        _ ops: ListPatternOps,
        listType: Type,
        elementType: Type
    ) -> ListPatternOps {
        if context.containsGenericParameter(listType) {
            return ListPatternOps(
                listType: listType,
                elementType: elementType,
                countSymbol: ops.countSymbol,
                indexSymbol: ops.indexSymbol
            )
        }
        // `count` / `__index_get` are the compiler's own list-pattern ops, a
        // closed set the pattern lowering names directly. Read-only identity
        // lookup: no instantiation, so the resolution worklist this runs inside
        // is left alone. Still keyed by owner + DefId -- it only declines to
        // CREATE anything.
        let countSymbol = lookupMethodInstanceIdentityReadonly(
            definitionMethod: ops.countSymbol,
            receiverType: listType
        ) ?? ops.countSymbol
        let indexSymbol = lookupMethodInstanceIdentityReadonly(
            definitionMethod: ops.indexSymbol,
            receiverType: listType
        ) ?? ops.indexSymbol
        return ListPatternOps(
            listType: listType,
            elementType: elementType,
            countSymbol: countSymbol,
            indexSymbol: indexSymbol
        )
    }

    /// Resolves types in a pattern.
    internal func resolveTypesInPattern(_ pattern: TypedPattern) -> TypedPattern {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .floatLiteral, .stringLiteral, .wildcard:
            return pattern
        case .nullLiteral(let resultType):
            return .nullLiteral(resultType: resolveParameterizedType(resultType))
        case .weakBinding(let symbol):
            let newSymbol = copySymbolPreservingDefId(
                symbol,
                newType: resolveParameterizedType(symbol.type)
            )
            return .weakBinding(symbol: newSymbol)
        case .traitObjectType(let targetType):
            return .traitObjectType(targetType: resolveParameterizedType(targetType))
        case .traitObjectTypeBinding(let symbol, let targetType):
            let newSymbol = copySymbolPreservingDefId(
                symbol,
                newType: resolveParameterizedType(symbol.type)
            )
            return .traitObjectTypeBinding(
                symbol: newSymbol,
                targetType: resolveParameterizedType(targetType)
            )
            
        case .variable(let symbol):
            let newSymbol = copySymbolPreservingDefId(
                symbol,
                newType: resolveParameterizedType(symbol.type)
            )
            return .variable(symbol: newSymbol)
            
        case .enumCase(let caseName, let tagIndex, let elements):
            return .enumCase(
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
            
        case .structPattern(let typeName, let elements):
            return .structPattern(
                typeName: typeName,
                elements: elements.map { resolveTypesInPattern($0) }
            )

        case .listPattern(let elements, let ops):
            return .listPattern(
                elements: elements.map { resolveTypesInPattern($0) },
                ops: refreshListPatternOps(
                    ops,
                    listType: resolveParameterizedType(ops.listType),
                    elementType: resolveParameterizedType(ops.elementType)
                )
            )

        case .restPattern:
            return pattern
        }
    }
}

// MARK: - Intrinsic Type Resolution Extension

extension Monomorphizer {
    
    /// Resolves types in an intrinsic call.
    internal func resolveTypesInIntrinsic(_ intrinsic: TypedIntrinsic) -> TypedIntrinsic {
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
            



            
        case .downgradeRef(let val, let resultType):
            return .downgradeRef(
                val: resolveTypesInExpression(val),
                resultType: resultType
            )
            
        case .upgradeRef(let val, let resultType):
            let resolvedResultType = resolveParameterizedType(resultType)
            return .upgradeRef(
                val: resolveTypesInExpression(val),
                resultType: resolvedResultType
            )
        case .initMemory(let ptr, let val):
            return .initMemory(
                ptr: resolveTypesInExpression(ptr),
                val: resolveTypesInExpression(val)
            )
        case .deinitMemory(let ptr):
            return .deinitMemory(ptr: resolveTypesInExpression(ptr))
        case .takeMemory(let ptr):
            return .takeMemory(ptr: resolveTypesInExpression(ptr))
        case .nullPtr(let resultType):
            return .nullPtr(resultType: resultType)
            
        case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
            return .spawnThread(
                outHandle: resolveTypesInExpression(outHandle),
                outTid: resolveTypesInExpression(outTid),
                closure: resolveTypesInExpression(closure),
                stackSize: resolveTypesInExpression(stackSize)
            )
            
        }
    }
}

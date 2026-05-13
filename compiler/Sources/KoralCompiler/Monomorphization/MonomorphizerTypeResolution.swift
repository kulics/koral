// MonomorphizerTypeResolution.swift
// Extension for Monomorphizer that handles type resolution and substitution.
// This file contains methods for resolving TypeNodes to concrete Types,
// resolving parameterized types (genericStruct/genericEnum), and
// resolving types throughout global nodes, expressions, statements, and patterns.

import Foundation

// MARK: - Type Resolution Extension

extension Monomorphizer {

    internal func predeclareGivenMethodRemaps(in nodes: [TypedGlobalNode]) {}

    private func methodHasCompatibleRefLikeReceiver(_ methodType: Type, baseType: Type) -> Bool {
        guard case .function(let params, _) = methodType,
              let firstParam = params.first else {
            return false
        }
        switch (firstParam.type, baseType) {
        case (.reference(let lhs), .reference(let rhs)),
             (.reference(let lhs), .mutableReference(let rhs)),
             (.mutableReference(let lhs), .mutableReference(let rhs)),
             (.weakReference(let lhs), .weakReference(let rhs)),
             (.weakReference(let lhs), .mutableWeakReference(let rhs)),
             (.mutableWeakReference(let lhs), .mutableWeakReference(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }

    private func shouldPreserveResolvedMethodReference(_ method: Symbol, baseType: Type) -> Bool {
        let resolvedMethodType = resolveParameterizedType(method.type)
        guard methodHasCompatibleRefLikeReceiver(resolvedMethodType, baseType: baseType) else {
            return false
        }
        guard !context.containsGenericParameter(resolvedMethodType),
              let dispatchInfo = receiverMethodDispatch[method.defId] else {
            return false
        }

        let preservesRefWrapperDispatch: Bool
        switch dispatchInfo.owner {
        case .extensionTemplate(let ownerName)?:
            preservesRefWrapperDispatch = ["Ref", "MutRef", "WeakRef", "MutWeakRef"].contains(ownerName)
        case .concreteType(let typeName)?:
            preservesRefWrapperDispatch = ["Ref", "MutRef", "WeakRef", "MutWeakRef"].contains(typeName)
        default:
            preservesRefWrapperDispatch = false
        }

        return preservesRefWrapperDispatch
    }

    // MARK: - Type Node Resolution
    
    /// Resolves a TypeNode to a concrete Type using the given substitution map.
    /// - Parameters:
    ///   - node: The type node to resolve
    ///   - substitution: Map from type parameter names to concrete types
    /// - Returns: The resolved concrete type
    internal func resolveTypeNode(_ node: TypeNode, substitution: [String: Type]) throws -> Type {
        switch node {
        case .identifier(let name):
            // Check substitution map first
            if let substituted = substitution[name] {
                // If the substituted type is a genericStruct, we need to instantiate it
                if case .genericStruct(let template, let args) = substituted {
                    // Check if it's a struct template
                    if let structTemplate = input.genericTemplates.structTemplates[template] {
                        return try instantiateStruct(template: structTemplate, args: args)
                    }
                }
                // If the substituted type is a genericEnum, we need to instantiate it
                if case .genericEnum(let template, let args) = substituted {
                    if let enumTemplate = input.genericTemplates.enumTemplates[template] {
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
            if input.genericTemplates.traits[name] != nil {
                return .traitObject(traitName: name, typeArgs: [])
            }
            // Otherwise treat as generic parameter
            return .genericParameter(name: name)
            
        case .reference(let inner, mutable: let mutable):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return mutable ? .mutableReference(inner: innerType) : .reference(inner: innerType)

        case .pointer(let inner, mutable: let mutable):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return mutable ? .mutablePointer(element: innerType) : .pointer(element: innerType)
            
        case .generic(let base, let args):
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
            
        case .functionType(let paramTypes, let returnType):
            // Resolve function type: [ParamType1, ParamType2, ..., ReturnType]Func
            let resolvedParamTypes = try paramTypes.map { try resolveTypeNode($0, substitution: substitution) }
            let resolvedReturnType = try resolveTypeNode(returnType, substitution: substitution)
            let parameters = resolvedParamTypes.map { Parameter(type: $0, kind: .byVal) }
            return .function(parameters: parameters, returns: resolvedReturnType)
            
        case .weakReference(let inner, let mutable):
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
        case .genericStruct(let template, let args):
            if let cacheKey = typeInstantiationCacheKey(for: type),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            let resolvedArgs = args.map { resolveParameterizedType($0, visited: visited) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return resolvedArgs == args ? type : .genericStruct(template: template, args: resolvedArgs)
            }

            let resolvedType = Type.genericStruct(template: template, args: resolvedArgs)
            if let cacheKey = typeInstantiationCacheKey(for: resolvedType),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            if let structTemplate = input.genericTemplates.structTemplates[template] {
                do {
                    return try instantiateStruct(template: structTemplate, args: resolvedArgs)
                } catch {
                    let argLayoutKeys = resolvedArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    let layoutName = "\(template)_\(argLayoutKeys)"
                    let defId = getOrAllocateTypeDefId(name: layoutName, kind: .structure)
                    context.updateStructInfo(defId: defId, members: [], isGenericInstantiation: true, typeArguments: resolvedArgs)
                    return .structure(defId: defId)
                }
            }

            return resolvedArgs == args ? type : resolvedType
            
        case .genericEnum(let template, let args):
            if let cacheKey = typeInstantiationCacheKey(for: type),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            let resolvedArgs = args.map { resolveParameterizedType($0, visited: visited) }
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return resolvedArgs == args ? type : .genericEnum(template: template, args: resolvedArgs)
            }

            let resolvedType = Type.genericEnum(template: template, args: resolvedArgs)
            if let cacheKey = typeInstantiationCacheKey(for: resolvedType),
               let cached = instantiatedTypes[cacheKey] {
                return cached
            }

            if let enumTemplate = input.genericTemplates.enumTemplates[template] {
                do {
                    return try instantiateEnum(template: enumTemplate, args: resolvedArgs)
                } catch {
                    let argLayoutKeys = resolvedArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    let layoutName = "\(template)_\(argLayoutKeys)"
                    let defId = getOrAllocateTypeDefId(name: layoutName, kind: .`enum`)
                    context.updateEnumInfo(defId: defId, cases: [], isGenericInstantiation: true, typeArguments: resolvedArgs)
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
                    named: member.named
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
            context.updateStructInfo(defId: defId, members: newMembers, isGenericInstantiation: isGeneric, typeArguments: typeArgs)
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
                        (name: param.name, type: resolveParameterizedType(param.type, visited: newVisited), access: param.access, named: param.named)
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
                        (name: param.name, type: resolveParameterizedType(param.type), access: param.access, named: param.named)
                    }
                )
            }
            return .globalEnumDeclaration(identifier: newIdentifier, cases: newCases)
            
        case .globalFunction(let identifier, let parameters, let body):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
            )
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

            var methodMap = extensionMethods[typeName] ?? [:]
            let newMethods = methods.map { method -> TypedMethodDeclaration in
                let canonicalMethodBaseName = receiverMethodDispatch[method.identifier.defId]?.methodName
                    ?? (context.getName(method.identifier.defId) ?? "<unknown>")

                let remappedIdentifier = makeSymbol(
                    name: canonicalMethodBaseName,
                    type: resolveParameterizedType(method.identifier.type),
                    kind: method.identifier.kind,
                    modulePath: semanticMethodModulePath(ownerType: resolvedType, trait: resolvedTrait, methodTypeArgs: []),
                    sourceFile: context.getSourceFile(method.identifier.defId) ?? "",
                    access: context.getAccess(method.identifier.defId) ?? .protected
                )

                let entry = ConcreteMethodEntry(symbol: remappedIdentifier, trait: resolvedTrait)
                methodMap[canonicalMethodBaseName] = entry
                remappedFunctionDefIds[method.identifier.defId, default: []].append((defId: remappedIdentifier.defId, type: remappedIdentifier.type))

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
            extensionMethods[typeName] = methodMap
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
    private func methodLookupBaseType(for base: TypedExpressionNode) -> Type {
        if case .variable = base {
            return base.type
        }
        if case .referenceExpression(let inner, _) = base {
            switch inner {
            case .variable:
                return base.type
            default:
                return inner.type
            }
        }
        if case .reference(let inner) = base.type {
            return inner
        }
        if case .mutableReference(let inner) = base.type {
            return inner
        }
        return base.type
    }

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

        case .wrappingShiftExpression(let left, let op, let right, let type):
            return .wrappingShiftExpression(
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
            let remappedDefId: DefId = {
                guard let candidates = remappedFunctionDefIds[identifier.defId], !candidates.isEmpty else {
                    return identifier.defId
                }
                let originalMethodName = receiverMethodDispatch[identifier.defId]?.methodName
                let filteredCandidates = candidates.filter { candidate in
                    guard let originalMethodName else {
                        return true
                    }
                    guard let candidateMethodName = receiverMethodDispatch[candidate.defId]?.methodName else {
                        return true
                    }
                    return candidateMethodName == originalMethodName
                }
                let disambiguationCandidates = filteredCandidates.isEmpty ? candidates : filteredCandidates
                if disambiguationCandidates.count == 1 {
                    return disambiguationCandidates[0].defId
                }
                if let matched = disambiguationCandidates.first(where: { candidate in
                    return resolveParameterizedType(candidate.type) == resolvedType
                }) {
                    return matched.defId
                }
                return identifier.defId
            }()
            let newIdentifier = Symbol(
                defId: remappedDefId,
                type: resolvedType,
                kind: identifier.kind
            )
            return .variable(identifier: newIdentifier)
            
        case .blockExpression(let statements, let type):
            let newStatements = statements.map { resolveTypesInStatement($0) }
            return .blockExpression(
                statements: newStatements,
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
            let newArguments = arguments.map { resolveTypesInExpression($0) }
            let newType = resolveParameterizedType(type)

            if case .variable(let identifier) = newCallee,
               case .function = identifier.kind,
               let candidates = remappedFunctionDefIds[identifier.defId],
               candidates.count > 1 {
                let originalMethodName = receiverMethodDispatch[identifier.defId]?.methodName
                let filteredCandidates = candidates.filter { candidate in
                    guard let originalMethodName else {
                        return true
                    }
                    guard let candidateMethodName = receiverMethodDispatch[candidate.defId]?.methodName else {
                        return true
                    }
                    return candidateMethodName == originalMethodName
                }
                let disambiguationCandidates = filteredCandidates.isEmpty ? candidates : filteredCandidates
                let expectedCallType = Type.function(
                    parameters: newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                let matched = disambiguationCandidates.first(where: { resolveParameterizedType($0.type) == expectedCallType })
                    ?? disambiguationCandidates.first(where: { candidate in
                        let candidateType = resolveParameterizedType(candidate.type)
                        guard case .function(let candidateParams, let candidateReturns) = candidateType,
                              case .function(let expectedParams, let expectedReturns) = expectedCallType,
                              candidateParams.count == expectedParams.count,
                              candidateReturns == expectedReturns else {
                            return false
                        }
                        return zip(candidateParams, expectedParams).allSatisfy { $0.type == $1.type }
                    })
                if let matched {
                    newCallee = .variable(
                        identifier: Symbol(
                            defId: matched.defId,
                            type: resolveParameterizedType(matched.type),
                            kind: identifier.kind
                        )
                    )
                }
            }

            if case .traitMethodPlaceholder(let traitName, let methodName, let base, let methodTypeArgs, _) = newCallee,
               extractTraitObjectType(base.type) == nil,
               !context.containsGenericParameter(base.type) {
                let lookupBaseType = methodLookupBaseType(for: base)
                let expectedCallType = Type.function(
                    parameters: [Parameter(type: lookupBaseType, kind: .byVal)]
                        + newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                if let concreteMethod = try? lookupConcreteMethodSymbol(
                    on: lookupBaseType,
                    name: methodName,
                    methodTypeArgs: methodTypeArgs,
                    expectedMethodType: expectedCallType
                ) {
                    let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                    newCallee = .methodReference(
                        base: alignMethodReferenceBase(base, to: resolvedMethodType),
                        method: copySymbolWithNewDefId(concreteMethod, newType: resolvedMethodType),
                        typeArgs: nil,
                        methodTypeArgs: methodTypeArgs,
                        type: resolvedMethodType
                    )
                } else {
                    newCallee = .traitMethodPlaceholder(
                        traitName: traitName,
                        methodName: methodName,
                        base: base,
                        methodTypeArgs: methodTypeArgs,
                        type: newType
                    )
                }
            }

            // Lower wrapping intrinsic methods to scalar ops
            if case .methodReference(let base, let method, _, _, _) = newCallee {
                let methodName = receiverMethodDispatch[method.defId]?.methodName ?? ""
                if isBuiltinArithmeticType(base.type) {
                    if newArguments.count == 1 {
                        let rhs = newArguments[0]
                        switch methodName {
                        case "wrapping_add" where base.type == rhs.type:
                            return .wrappingArithmeticExpression(left: base, op: .plus, right: rhs, type: newType)
                        case "wrapping_sub" where base.type == rhs.type:
                            return .wrappingArithmeticExpression(left: base, op: .minus, right: rhs, type: newType)
                        case "wrapping_mul" where base.type == rhs.type:
                            return .wrappingArithmeticExpression(left: base, op: .multiply, right: rhs, type: newType)
                        case "wrapping_div" where base.type == rhs.type:
                            return .wrappingArithmeticExpression(left: base, op: .divide, right: rhs, type: newType)
                        case "wrapping_rem" where base.type == rhs.type:
                            return .wrappingArithmeticExpression(left: base, op: .remainder, right: rhs, type: newType)
                        case "wrapping_shl" where isMatchingUnsignedShiftAmountType(valueType: base.type, shiftType: rhs.type):
                            return .wrappingShiftExpression(left: base, op: .shiftLeft, right: rhs, type: newType)
                        case "wrapping_shr" where isMatchingUnsignedShiftAmountType(valueType: base.type, shiftType: rhs.type):
                            return .wrappingShiftExpression(left: base, op: .shiftRight, right: rhs, type: newType)
                        default:
                            break
                        }
                    }
                    if methodName == "wrapping_neg", newArguments.isEmpty {
                        let zero = makeZeroLiteral(for: base.type)
                        return .wrappingArithmeticExpression(left: zero, op: .minus, right: base, type: newType)
                    }
                }
            }

            // Lower to_ref intrinsic method on weakref types to upgradeRef/upgradeMutRef nodes
            if case .methodReference(let base, let method, _, _, _) = newCallee {
                let methodName = receiverMethodDispatch[method.defId]?.methodName ?? ""
                if methodName == "to_ref" && newArguments.isEmpty {
                    switch base.type {
                    case .weakReference(let inner):
                        let refType = Type.reference(inner: inner)
                        let optionType = Type.genericEnum(template: "Option", args: [refType])
                        return .intrinsicCall(.upgradeRef(val: base, resultType: optionType))
                    case .mutableWeakReference(let inner):
                        let refType = Type.mutableReference(inner: inner)
                        let optionType = Type.genericEnum(template: "Option", args: [refType])
                        return .intrinsicCall(.upgradeMutRef(val: base, resultType: optionType))
                    default:
                        break
                    }
                }
            }

            // Convert traitMethodPlaceholder with trait object base to traitMethodCall
            // This handles the case where a generic function like [T ToString]f(a T ref)
            // is instantiated with T = traitObject("ToString") — method calls on the
            // trait object parameter must use vtable dynamic dispatch.
            if case .traitMethodPlaceholder(_, let methodName, let base, _, _) = newCallee {
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
                            methodName: methodName,
                            methodIndex: methodIndex,
                            arguments: newArguments,
                            type: newType
                        )
                    }
                }
            }

            // Re-resolve method references using actual call argument types.
            // This enables omitted method generic arguments to be inferred at call sites.
            if case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, _) = newCallee,
               !context.containsGenericParameter(base.type) {
                let resolvedMethodTypeArgs = methodTypeArgs ?? []
                let methodTypeArgsForLookup: [Type] =
                    resolvedMethodTypeArgs.contains(where: { context.containsGenericParameter($0) })
                    ? []
                    : resolvedMethodTypeArgs
                if !shouldPreserveResolvedMethodReference(method, baseType: base.type) {
                    let expectedMethodType = resolveParameterizedType(method.type)
                    let expectedCallTypeWithReceiver = Type.function(
                        parameters: [Parameter(type: base.type, kind: .byVal)]
                            + newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                        returns: newType
                    )
                    let expectedCallTypeWithoutReceiver = Type.function(
                        parameters: newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                        returns: newType
                    )

                    let preferredExpectedTypes: [Type] =
                        methodTypeArgsForLookup.isEmpty && context.containsGenericParameter(expectedMethodType)
                        ? [expectedCallTypeWithReceiver, expectedMethodType, expectedCallTypeWithoutReceiver]
                        : [expectedMethodType, expectedCallTypeWithReceiver, expectedCallTypeWithoutReceiver]

                    let concreteMethod = preferredExpectedTypes.compactMap {
                        try? lookupConcreteMethodSymbol(
                            on: base.type,
                            method: method,
                            methodTypeArgs: methodTypeArgsForLookup,
                            expectedMethodType: $0
                        )
                    }.first ?? nil

                    if let concreteMethod {
                        let resolvedConcreteMethodType = resolveParameterizedType(concreteMethod.type)
                        let adjustedBase = alignMethodReferenceBase(base, to: resolvedConcreteMethodType)
                        newCallee = .methodReference(
                            base: adjustedBase,
                            method: copySymbolWithNewDefId(concreteMethod, newType: resolvedConcreteMethodType),
                            typeArgs: typeArgs,
                            methodTypeArgs: methodTypeArgsForLookup,
                            type: resolvedConcreteMethodType
                        )
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
                if !processedRequestKeys.contains(key) {
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
            var newMethod = copySymbolWithNewDefId(
                method,
                newType: resolveParameterizedType(method.type)
            )
            let resolvedTypeArgs = typeArgs?.map { resolveParameterizedType($0) }
            let resolvedMethodTypeArgs = methodTypeArgs?.map { resolveParameterizedType($0) }
            let effectiveMethodTypeArgs: [Type] = {
                let explicit = resolvedMethodTypeArgs ?? []
                if !explicit.isEmpty {
                    return explicit
                }
                return []
            }()
            var adjustedBase = newBase
            var resolvedExpressionType = resolveParameterizedType(method.type)
            let methodTypeArgsToPass = effectiveMethodTypeArgs

            // Resolve method reference to a concrete symbol (DefId + specialized type)
            if !context.containsGenericParameter(adjustedBase.type) {
                let resolvedMethodType = resolveParameterizedType(method.type)
                resolvedExpressionType = resolvedMethodType
                if shouldPreserveResolvedMethodReference(method, baseType: adjustedBase.type) {
                    newMethod = copySymbolWithNewDefId(method, newType: resolvedMethodType)
                } else {
                    if let concreteMethod = try? lookupConcreteMethodSymbol(
                        on: adjustedBase.type,
                        method: method,
                        methodTypeArgs: methodTypeArgsToPass,
                        expectedMethodType: resolvedMethodType
                    ) {
                        let resolvedConcreteMethodType = resolveParameterizedType(concreteMethod.type)
                        adjustedBase = alignMethodReferenceBase(adjustedBase, to: resolvedConcreteMethodType)
                        newMethod = copySymbolWithNewDefId(
                            concreteMethod,
                            newType: resolvedConcreteMethodType
                        )
                        resolvedExpressionType = resolvedConcreteMethodType
                    } else {
                        if let logicalMethodName = receiverMethodDispatch[method.defId]?.methodName,
                           let concreteMethod = lookupInstantiatedExtensionMethodSymbol(
                            baseType: adjustedBase.type,
                            methodName: logicalMethodName,
                            expectedMethodType: resolvedMethodType
                           ) {
                                let resolvedConcreteMethodType = resolveParameterizedType(concreteMethod.type)
                                adjustedBase = alignMethodReferenceBase(adjustedBase, to: resolvedConcreteMethodType)
                                newMethod = copySymbolWithNewDefId(
                                    concreteMethod,
                                    newType: resolvedConcreteMethodType
                                )
                                resolvedExpressionType = resolvedConcreteMethodType
                            }
                    }
                }
            }
            
            return .methodReference(
                base: adjustedBase,
                method: newMethod,
                typeArgs: resolvedTypeArgs,
                methodTypeArgs: methodTypeArgsToPass,
                type: resolvedExpressionType
            )
            
        case .traitMethodPlaceholder(let traitName, let methodName, let base, let methodTypeArgs, let type):
            // Resolve types in the placeholder
            let newBase = resolveTypesInExpression(base)
            let resolvedMethodTypeArgs = methodTypeArgs.map { resolveParameterizedType($0) }
            let resolvedType = resolveParameterizedType(type)
            
            // Enqueue trait placeholder request for later resolution
            enqueueTraitPlaceholderRequest(
                baseType: newBase.type,
                methodName: methodName,
                methodTypeArgs: resolvedMethodTypeArgs
            )
            
            // Try to resolve to concrete method if base type is now concrete
            if !context.containsGenericParameter(newBase.type) {
                // Check if the base type is a trait object — if so, keep as placeholder
                // (the .call case will convert it to traitMethodCall with proper arguments)
                if extractTraitObjectType(newBase.type) != nil {
                    return .traitMethodPlaceholder(
                        traitName: traitName,
                        methodName: methodName,
                        base: newBase,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        type: resolvedType
                    )
                }

                // Look up the concrete method on the resolved base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(
                    on: newBase.type,
                    name: methodName,
                    methodTypeArgs: resolvedMethodTypeArgs,
                    expectedMethodType: resolvedType
                ) {
                    let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                    let adjustedBase = alignMethodReferenceBase(newBase, to: resolvedMethodType)
                    return .methodReference(
                        base: adjustedBase,
                        method: copySymbolWithNewDefId(concreteMethod, newType: resolvedMethodType),
                        typeArgs: nil,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        type: resolvedMethodType
                    )
                } else {
                    // Try to instantiate the method first
                    _ = try? instantiateTraitPlaceholderMethod(
                        baseType: newBase.type,
                        name: methodName,
                        methodTypeArgs: resolvedMethodTypeArgs
                    )
                    if let concreteMethod = try? lookupConcreteMethodSymbol(
                        on: newBase.type,
                        name: methodName,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        expectedMethodType: resolvedType
                    ) {
                        let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                        let adjustedBase = alignMethodReferenceBase(newBase, to: resolvedMethodType)
                        return .methodReference(
                            base: adjustedBase,
                            method: copySymbolWithNewDefId(concreteMethod, newType: resolvedMethodType),
                            typeArgs: nil,
                            methodTypeArgs: resolvedMethodTypeArgs,
                            type: resolvedMethodType
                        )
                    }
                }
            }
            
            // Keep as placeholder if base type is still generic
            return .traitMethodPlaceholder(
                traitName: traitName,
                methodName: methodName,
                base: newBase,
                methodTypeArgs: resolvedMethodTypeArgs,
                type: resolvedType
            )

        case .traitObjectConversion(let inner, let traitName, let traitTypeArgs, let concreteType, let type):
            let resolvedConcreteType = resolveParameterizedType(concreteType)
            let resolvedTraitTypeArgs = traitTypeArgs.map { resolveParameterizedType($0) }
            // Collect vtable request for non-generic code paths
            if !context.containsGenericParameter(resolvedConcreteType) {
                vtableRequests.insert(VtableRequest(
                    concreteType: resolvedConcreteType,
                    traitName: traitName,
                    traitTypeArgs: resolvedTraitTypeArgs
                ))
            }
            return .traitObjectConversion(
                inner: resolveTypesInExpression(inner),
                traitName: traitName,
                traitTypeArgs: resolvedTraitTypeArgs,
                concreteType: resolvedConcreteType,
                type: resolveParameterizedType(type)
            )

        case .traitMethodCall(let receiver, let traitName, let methodName, let methodIndex, let arguments, let type):
            return .traitMethodCall(
                receiver: resolveTypesInExpression(receiver),
                traitName: traitName,
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
            case .genericStruct(let name, _):
                templateName = name
                emittedTypeScopeName = name  // Generic types don't have module path yet
                isGenericInstantiation = false
            case .`enum`(let defId):
                let name = context.getName(defId) ?? resolvedBaseType.description
                // Use stored templateName if available, otherwise fall back to full name
                templateName = context.getTemplateName(defId) ?? name
                emittedTypeScopeName = context.getQualifiedName(defId) ?? name
                isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
            case .genericEnum(let name, _):
                templateName = name
                emittedTypeScopeName = name  // Generic types don't have module path yet
                isGenericInstantiation = false
            default:
                templateName = resolvedBaseType.description
                emittedTypeScopeName = templateName
                isGenericInstantiation = false
            }
            
            // Build emitted method symbol name from type scope + method logical name.
            // For instantiated generic types, emittedTypeScopeName already includes type args.
            let specializedMethodSymbolName: String
            if isGenericInstantiation || resolvedTypeArgs.isEmpty {
                // emittedTypeScopeName already includes type args for generic instantiations
                if resolvedMethodTypeArgs.isEmpty {
                    specializedMethodSymbolName = "\(emittedTypeScopeName)_\(methodName)"
                } else {
                    let methodArgLayoutKeys = resolvedMethodTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    specializedMethodSymbolName = "\(emittedTypeScopeName)_\(methodName)_\(methodArgLayoutKeys)"
                }
            } else {
                // For uninstantiated generic types, add type args
                let argLayoutKeys = resolvedTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                if resolvedMethodTypeArgs.isEmpty {
                    specializedMethodSymbolName = "\(emittedTypeScopeName)_\(argLayoutKeys)_\(methodName)"
                } else {
                    let methodArgLayoutKeys = resolvedMethodTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    specializedMethodSymbolName = "\(emittedTypeScopeName)_\(argLayoutKeys)_\(methodName)_\(methodArgLayoutKeys)"
                }
            }
            
            // Prefer concrete symbol lookup so calls always target remapped DefIds.
            if let concreteMethod = try? lookupConcreteMethodSymbol(
                on: resolvedBaseType,
                name: methodName,
                methodTypeArgs: resolvedMethodTypeArgs
            ) {
                let functionType = Type.function(
                    parameters: resolvedArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: resolvedReturnType
                )
                let callee: TypedExpressionNode = .variable(
                    identifier: copySymbolPreservingDefId(
                        concreteMethod,
                        newType: functionType
                    )
                )
                return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
            }
            
            // Ensure the extension method is instantiated (for generic types)
            if let extensions = input.genericTemplates.extensionMethods[templateName] {
                if let ext = selectExtensionTemplate(
                    extensions,
                    name: methodName,
                    methodTypeArgCount: resolvedMethodTypeArgs.count,
                    extensionTypeArgCount: resolvedTypeArgs.count
                ) {
                    let key = InstantiationKey.extensionMethod(
                        templateName: templateName,
                        methodName: methodName,
                        typeArgs: resolvedTypeArgs,
                        methodTypeArgs: resolvedMethodTypeArgs
                    )
                    if !processedRequestKeys.contains(key) {
                        pendingRequests.append(InstantiationRequest(
                            kind: .extensionMethod(templateName: templateName, baseType: resolvedBaseType, template: ext, typeArgs: resolvedTypeArgs, methodTypeArgs: resolvedMethodTypeArgs),
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
            
            // Create callee from the specialized emitted symbol name.
            let callee: TypedExpressionNode = .variable(
                identifier: makeSymbol(name: specializedMethodSymbolName, type: functionType, kind: .function)
            )
            
            return .call(callee: callee, arguments: resolvedArguments, type: resolvedReturnType)
            
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

        case .pairVariableDeclaration(let pairSymbol, let pairValue,
                                let firstSymbol, let firstMember, let firstMutable,
                                let secondSymbol, let secondMember, let secondMutable):
            let newPairSymbol = copySymbolPreservingDefId(
                pairSymbol, newType: resolveParameterizedType(pairSymbol.type))
            let newFirstMember = copySymbolPreservingDefId(
                firstMember, newType: resolveParameterizedType(firstMember.type))
            let newSecondMember = copySymbolPreservingDefId(
                secondMember, newType: resolveParameterizedType(secondMember.type))
            let newFirstSymbol = firstSymbol.map {
                copySymbolPreservingDefId($0, newType: resolveParameterizedType($0.type))
            }
            let newSecondSymbol = secondSymbol.map {
                copySymbolPreservingDefId($0, newType: resolveParameterizedType($0.type))
            }
            return .pairVariableDeclaration(
                pairSymbol: newPairSymbol, pairValue: resolveTypesInExpression(pairValue),
                firstSymbol: newFirstSymbol, firstMember: newFirstMember, firstMutable: firstMutable,
                secondSymbol: newSecondSymbol, secondMember: newSecondMember, secondMutable: secondMutable
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

        case .finally(let expression):
            return .finally(expression: resolveTypesInExpression(expression))

        case .yield(let target, let value):
            return .yield(target: target, value: resolveTypesInExpression(value))
        }
    }
}

// MARK: - Pattern Type Resolution Extension

extension Monomorphizer {
    
    /// Resolves types in a pattern.
    internal func resolveTypesInPattern(_ pattern: TypedPattern) -> TypedPattern {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
            return pattern
            
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
            
        case .refCount(let val):
            return .refCount(val: resolveTypesInExpression(val))

        case .refIsBorrow(let val):
            return .refIsBorrow(val: resolveTypesInExpression(val))

        case .makeRef(let ptr, let owner, let resultType):
            return .makeRef(
                ptr: resolveTypesInExpression(ptr),
                owner: resolveTypesInExpression(owner),
                resultType: resolveParameterizedType(resultType)
            )

        case .makeMutRef(let ptr, let owner, let resultType):
            return .makeMutRef(
                ptr: resolveTypesInExpression(ptr),
                owner: resolveTypesInExpression(owner),
                resultType: resolveParameterizedType(resultType)
            )
            
        case .downgradeRef(let val, let resultType):
            return .downgradeRef(
                val: resolveTypesInExpression(val),
                resultType: resultType
            )
        case .downgradeMutRef(let val, let resultType):
            return .downgradeMutRef(
                val: resolveTypesInExpression(val),
                resultType: resultType
            )
            
        case .upgradeRef(let val, let resultType):
            let resolvedResultType = resolveParameterizedType(resultType)
            return .upgradeRef(
                val: resolveTypesInExpression(val),
                resultType: resolvedResultType
            )
        case .upgradeMutRef(let val, let resultType):
            let resolvedResultType = resolveParameterizedType(resultType)
            return .upgradeMutRef(
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

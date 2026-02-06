// MonomorphizerTypeResolution.swift
// Extension for Monomorphizer that handles type resolution and substitution.
// This file contains methods for resolving TypeNodes to concrete Types,
// resolving parameterized types (genericStruct/genericUnion), and
// resolving types throughout global nodes, expressions, statements, and patterns.

import Foundation

// MARK: - Type Resolution Extension

extension Monomorphizer {
    
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
                // If the substituted type is a genericUnion, we need to instantiate it
                if case .genericUnion(let template, let args) = substituted {
                    if let unionTemplate = input.genericTemplates.unionTemplates[template] {
                        return try instantiateUnion(template: unionTemplate, args: args)
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
            // Check if it's a known concrete union type
            if let concreteType = input.genericTemplates.concreteUnionTypes[name] {
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
            // Check if it's a known union template (non-generic reference)
            if let template = input.genericTemplates.unionTemplates[name] {
                // Non-generic union reference
                if template.typeParameters.isEmpty {
                    let defId = getOrAllocateTypeDefId(name: name, kind: .union)
                    context.updateUnionInfo(defId: defId, cases: [], isGenericInstantiation: false, typeArguments: nil)
                    return .union(defId: defId)
                }
            }
            // Otherwise treat as generic parameter
            return .genericParameter(name: name)
            
        case .reference(let inner):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return .reference(inner: innerType)

        case .pointer(let inner):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return .pointer(element: innerType)
            
        case .generic(let base, let args):
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
            
        case .moduleQualified(_, let name):
            // 模块限定类型：直接解析类型名
            // 在 Monomorphizer 阶段，模块信息已经不重要，直接使用类型名
            if let substituted = substitution[name] {
                return substituted
            }
            if let builtinType = resolveBuiltinType(name) {
                return builtinType
            }
            if let concreteType = input.genericTemplates.concreteStructTypes[name] {
                return concreteType
            }
            if let concreteType = input.genericTemplates.concreteUnionTypes[name] {
                return concreteType
            }
            return .genericParameter(name: name)
            
        case .moduleQualifiedGeneric(_, let base, let args):
            // 模块限定泛型类型
            let resolvedArgs = try args.map { try resolveTypeNode($0, substitution: substitution) }
            
            if let template = input.genericTemplates.structTemplates[base] {
                return try instantiateStruct(template: template, args: resolvedArgs)
            }
            
            if let template = input.genericTemplates.unionTemplates[base] {
                return try instantiateUnion(template: template, args: resolvedArgs)
            }
            
            throw SemanticError(.generic("Unknown generic type: \(base)"), line: currentLine)
            
        case .weakReference(let inner):
            let innerType = try resolveTypeNode(inner, substitution: substitution)
            return .weakReference(inner: innerType)
        }
    }
    
    /// Resolves a built-in type name to its Type.
    internal func resolveBuiltinType(_ name: String) -> Type? {
        return SemaUtils.resolveBuiltinType(name)
    }
    
    // MARK: - Parameterized Type Resolution
    
    /// Substitutes type parameters in a type.
    /// This method extends SemaUtils.substituteType to also resolve genericStruct/genericUnion
    /// to concrete structure/union types by instantiating them.
    internal func substituteType(_ type: Type, substitution: [String: Type]) -> Type {
        // First, apply the basic substitution
        let substituted = SemaUtils.substituteType(type, substitution: substitution, context: context)
        
        // Then, resolve genericStruct/genericUnion to concrete types
        return resolveParameterizedType(substituted, visited: [])
    }
    
    /// Resolves a parameterized type (genericStruct/genericUnion) to a concrete type.
    /// If the type still contains generic parameters, returns it unchanged.
    /// - Parameter type: The type to resolve
    /// - Parameter visited: Set of visited DefId ids to prevent infinite recursion
    /// - Returns: The resolved concrete type, or the original type if it can't be resolved yet
    internal func resolveParameterizedType(_ type: Type, visited: Set<UInt64> = []) -> Type {
        switch type {
        case .genericStruct(let template, let args):
            // Check if we already have this type cached FIRST (before resolving args)
            // This handles recursive types like List<Expr ref> where Expr contains List<Expr ref>
            let initialCacheKey = "\(template)<\(args.map { $0.description }.joined(separator: ","))>"
            if let cached = instantiatedTypes[initialCacheKey] {
                return cached
            }
            
            // First, recursively resolve the type arguments
            let resolvedArgs = args.map { resolveParameterizedType($0, visited: visited) }
            
            // If any arg still contains generic parameters, we can't resolve yet
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return .genericStruct(template: template, args: resolvedArgs)
            }
            
            // Check cache again with resolved args (in case description changed)
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
                    let argLayoutKeys = resolvedArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    let layoutName = "\(template)_\(argLayoutKeys)"
                    let defId = getOrAllocateTypeDefId(name: layoutName, kind: .structure)
                    context.updateStructInfo(defId: defId, members: [], isGenericInstantiation: true, typeArguments: resolvedArgs)
                    return .structure(defId: defId)
                }
            }
            
            return .genericStruct(template: template, args: resolvedArgs)
            
        case .genericUnion(let template, let args):
            // Check if we already have this type cached FIRST (before resolving args)
            let initialCacheKey = "\(template)<\(args.map { $0.description }.joined(separator: ","))>"
            if let cached = instantiatedTypes[initialCacheKey] {
                return cached
            }
            
            // First, recursively resolve the type arguments
            let resolvedArgs = args.map { resolveParameterizedType($0, visited: visited) }
            
            // If any arg still contains generic parameters, we can't resolve yet
            if resolvedArgs.contains(where: { context.containsGenericParameter($0) }) {
                return .genericUnion(template: template, args: resolvedArgs)
            }
            
            // Check cache again with resolved args (in case description changed)
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
                    let argLayoutKeys = resolvedArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                    let layoutName = "\(template)_\(argLayoutKeys)"
                    let defId = getOrAllocateTypeDefId(name: layoutName, kind: .union)
                    context.updateUnionInfo(defId: defId, cases: [], isGenericInstantiation: true, typeArguments: resolvedArgs)
                    return .union(defId: defId)
                }
            }
            
            return .genericUnion(template: template, args: resolvedArgs)
            
        case .reference(let inner):
            return .reference(inner: resolveParameterizedType(inner, visited: visited))
            
        case .pointer(let element):
            return .pointer(element: resolveParameterizedType(element, visited: visited))
            
        case .function(let params, let returns):
            let newParams = params.map { param in
                Parameter(
                    type: resolveParameterizedType(param.type, visited: visited),
                    kind: param.kind
                )
            }
            return .function(
                parameters: newParams,
                returns: resolveParameterizedType(returns, visited: visited)
            )
            
        case .structure(let defId):
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
                    mutable: member.mutable
                )
            }
            let membersChanged = zip(members, newMembers).contains { old, new in
                old.type != new.type
            }
            if !membersChanged {
                return type
            }
            let isGeneric = context.isGenericInstantiation(defId) ?? false
            let typeArgs = context.getTypeArguments(defId)
            context.updateStructInfo(defId: defId, members: newMembers, isGenericInstantiation: isGeneric, typeArguments: typeArgs)
            return .structure(defId: defId)
            
        case .union(let defId):
            if visited.contains(defId.id) {
                return type
            }
            var newVisited = visited
            newVisited.insert(defId.id)
            let cases = context.getUnionCases(defId) ?? []
            let newCases = cases.map { unionCase in
                UnionCase(
                    name: unionCase.name,
                    parameters: unionCase.parameters.map { param in
                        (name: param.name, type: resolveParameterizedType(param.type, visited: newVisited))
                    }
                )
            }
            let casesChanged = zip(cases, newCases).contains { old, new in
                zip(old.parameters, new.parameters).contains { oldParam, newParam in
                    oldParam.type != newParam.type
                }
            }
            if !casesChanged {
                return type
            }
            let isGeneric = context.isGenericInstantiation(defId) ?? false
            let typeArgs = context.getTypeArguments(defId)
            context.updateUnionInfo(defId: defId, cases: newCases, isGenericInstantiation: isGeneric, typeArguments: typeArgs)
            return .union(defId: defId)
            
        default:
            return type
        }
    }
    
    // MARK: - Global Node Type Resolution
    
    /// Resolves all genericStruct/genericUnion types in a global node.
    /// This ensures no parameterized types reach CodeGen.
    internal func resolveTypesInGlobalNode(_ node: TypedGlobalNode) throws -> TypedGlobalNode {
        switch node {
        case .foreignUsing:
            return node
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
            
        case .globalUnionDeclaration(let identifier, let cases):
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
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
            
        case .givenDeclaration(let type, let methods):
            // Resolve the type to get the concrete type name
            let resolvedType = resolveParameterizedType(type)
            let typeName: String
            let qualifiedTypeName: String
            switch resolvedType {
            case .structure(let defId):
                let name = context.getName(defId) ?? resolvedType.description
                typeName = name
                qualifiedTypeName = context.getQualifiedName(defId) ?? name
            case .union(let defId):
                let name = context.getName(defId) ?? resolvedType.description
                typeName = name
                qualifiedTypeName = context.getQualifiedName(defId) ?? name
            default:
                typeName = resolvedType.description
                qualifiedTypeName = typeName
            }
            
            let newMethods = methods.map { method -> TypedMethodDeclaration in
                // Generate mangled name for the method
                // Use qualifiedTypeName to include module path
                let qualifiedPrefix = "\(qualifiedTypeName)_"
                let qualifiedCName = sanitizeCIdentifier(qualifiedTypeName)
                let qualifiedCPrefix = "\(qualifiedCName)_"
                let mangledName: String
                let identifierName = context.getName(method.identifier.defId) ?? "<unknown>"
                if identifierName.hasPrefix(qualifiedPrefix)
                    || identifierName.hasPrefix(qualifiedCPrefix) {
                    mangledName = identifierName
                } else {
                    mangledName = "\(qualifiedTypeName)_\(identifierName)"
                }
                
                // 创建新的 Symbol，使用空的 modulePath
                // 因为 mangledName 已经包含了完整的模块路径信息
                // 这样 Symbol.qualifiedName 就不会再添加模块路径前缀
                return TypedMethodDeclaration(
                    identifier: makeSymbol(
                        name: mangledName,
                        type: resolveParameterizedType(method.identifier.type),
                        kind: method.identifier.kind,
                        methodKind: method.identifier.methodKind,
                        modulePath: [],  // 空的 modulePath，因为 mangledName 已经包含了模块路径
                        sourceFile: context.getSourceFile(method.identifier.defId) ?? "",
                        access: context.getAccess(method.identifier.defId) ?? .default
                    ),
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
            return .givenDeclaration(type: resolvedType, methods: newMethods)
            
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
    
    /// Resolves all genericStruct/genericUnion types in an expression.
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
            
        case .comparisonExpression(let left, let op, let right, let type):
            return .comparisonExpression(
                left: resolveTypesInExpression(left),
                op: op,
                right: resolveTypesInExpression(right),
                type: resolveParameterizedType(type)
            )
            
        case .letExpression(let identifier, let value, let body, let type):
            let newIdentifier = copySymbolPreservingDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
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

        case .ptrExpression(let expression, let type):
            return .ptrExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )

        case .deptrExpression(let expression, let type):
            return .deptrExpression(
                expression: resolveTypesInExpression(expression),
                type: resolveParameterizedType(type)
            )
            
        case .variable(let identifier):
            let newIdentifier = copySymbolPreservingDefId(
                identifier,
                newType: resolveParameterizedType(identifier.type)
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
                let key = InstantiationKey.function(templateName: functionName, args: resolvedTypeArgs)
                if !processedRequestKeys.contains(key) {
                    pendingRequests.append(InstantiationRequest(
                        kind: .function(template: template, args: resolvedTypeArgs),
                        sourceLine: currentLine,
                        sourceFileName: currentFileName
                    ))
                }
                
                // Calculate the mangled name
                let argLayoutKeys = resolvedTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                let mangledName = "\(functionName)_\(argLayoutKeys)"
                
                // Create the callee as a variable reference to the mangled function
                let functionType = Type.function(
                    parameters: newArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: newType
                )
                let callee: TypedExpressionNode = .variable(
                    identifier: makeSymbol(name: mangledName, type: functionType, kind: .function)
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
            var newMethod = copySymbolWithNewDefId(
                method,
                newType: resolveParameterizedType(method.type)
            )
            let resolvedTypeArgs = typeArgs?.map { resolveParameterizedType($0) }
            let resolvedMethodTypeArgs = methodTypeArgs?.map { resolveParameterizedType($0) }
            
            // Track the resolved return type (will be updated if we find a concrete method)
            var resolvedReturnType = resolveParameterizedType(type)
            let methodTypeArgsToPass = resolvedMethodTypeArgs ?? []

            // Resolve method name to mangled name for generic extension methods
            let methodName = context.getName(method.defId) ?? ""
            if !context.containsGenericParameter(newBase.type) {
                // Look up the concrete method on the resolved base type
                // Pass method type args for generic methods
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: methodTypeArgsToPass) {
                    // Resolve any parameterized types in the method type
                    let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                    newMethod = copySymbolWithNewDefId(
                        concreteMethod,
                        newType: resolvedMethodType
                    )
                    // Extract the return type from the concrete method's function type
                    if case .function(_, let returns) = resolvedMethodType {
                        resolvedReturnType = returns
                    }
                }
            }
            
            return .methodReference(
                base: newBase,
                method: newMethod,
                typeArgs: resolvedTypeArgs,
                methodTypeArgs: resolvedMethodTypeArgs,
                type: resolvedReturnType
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
                // Look up the concrete method on the resolved base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: resolvedMethodTypeArgs) {
                    let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                    var resolvedReturnType = resolvedType
                    if case .function(_, let returns) = resolvedMethodType {
                        resolvedReturnType = returns
                    }
                    var adjustedBase = newBase
                    if case .function(let params, _) = resolvedMethodType, let firstParam = params.first {
                        if case .reference(let inner) = firstParam.type, inner == adjustedBase.type {
                            adjustedBase = .referenceExpression(expression: adjustedBase, type: firstParam.type)
                        } else if case .reference(let inner) = adjustedBase.type, inner == firstParam.type {
                            adjustedBase = .derefExpression(expression: adjustedBase, type: inner)
                        }
                    }
                    return .methodReference(
                        base: adjustedBase,
                        method: copySymbolWithNewDefId(concreteMethod, newType: resolvedMethodType),
                        typeArgs: nil,
                        methodTypeArgs: resolvedMethodTypeArgs,
                        type: resolvedReturnType
                    )
                } else {
                    // Try to instantiate the method first
                    _ = try? instantiateTraitPlaceholderMethod(
                        baseType: newBase.type,
                        name: methodName,
                        methodTypeArgs: resolvedMethodTypeArgs
                    )
                    if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: resolvedMethodTypeArgs) {
                        let resolvedMethodType = resolveParameterizedType(concreteMethod.type)
                        var resolvedReturnType = resolvedType
                        if case .function(_, let returns) = resolvedMethodType {
                            resolvedReturnType = returns
                        }
                        var adjustedBase = newBase
                        if case .function(let params, _) = resolvedMethodType, let firstParam = params.first {
                            if case .reference(let inner) = firstParam.type, inner == adjustedBase.type {
                                adjustedBase = .referenceExpression(expression: adjustedBase, type: firstParam.type)
                            } else if case .reference(let inner) = adjustedBase.type, inner == firstParam.type {
                                adjustedBase = .derefExpression(expression: adjustedBase, type: inner)
                            }
                        }
                        return .methodReference(
                            base: adjustedBase,
                            method: copySymbolWithNewDefId(concreteMethod, newType: resolvedMethodType),
                            typeArgs: nil,
                            methodTypeArgs: resolvedMethodTypeArgs,
                            type: resolvedReturnType
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
            var newName = context.getName(identifier.defId) ?? "<unknown>"
            if case .structure(let defId) = resolvedType {
                newName = context.getName(defId) ?? newName
            } else if case .union(let defId) = resolvedType {
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
            
        case .subscriptExpression(let base, let arguments, let method, let type):
            let newBase = resolveTypesInExpression(base)
            var newMethod = copySymbolWithNewDefId(
                method,
                newType: resolveParameterizedType(method.type)
            )
            
            // Resolve method name to mangled name for generic extension methods
            let methodName = context.getName(method.defId) ?? ""
            if !context.containsGenericParameter(newBase.type) {
                // Look up the concrete method on the resolved base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName) {
                    newMethod = copySymbolWithNewDefId(concreteMethod)
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
            if context.containsGenericParameter(resolvedBaseType) || resolvedTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
                return .staticMethodCall(
                    baseType: resolvedBaseType,
                    methodName: methodName,
                    typeArgs: resolvedTypeArgs,
                    arguments: resolvedArguments,
                    type: resolvedReturnType
                )
            }
            
            // Get the template name and qualified name from the base type
            let templateName: String
            let qualifiedTypeName: String
            let isGenericInstantiation: Bool
            switch resolvedBaseType {
            case .structure(let defId):
                let name = context.getName(defId) ?? resolvedBaseType.description
                // Use stored templateName if available, otherwise fall back to full name
                templateName = context.getTemplateName(defId) ?? name
                qualifiedTypeName = context.getQualifiedName(defId) ?? name
                isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
            case .genericStruct(let name, _):
                templateName = name
                qualifiedTypeName = name  // Generic types don't have module path yet
                isGenericInstantiation = false
            case .union(let defId):
                let name = context.getName(defId) ?? resolvedBaseType.description
                // Use stored templateName if available, otherwise fall back to full name
                templateName = context.getTemplateName(defId) ?? name
                qualifiedTypeName = context.getQualifiedName(defId) ?? name
                isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
            case .genericUnion(let name, _):
                templateName = name
                qualifiedTypeName = name  // Generic types don't have module path yet
                isGenericInstantiation = false
            default:
                templateName = resolvedBaseType.description
                qualifiedTypeName = templateName
                isGenericInstantiation = false
            }
            
            // Calculate the mangled method name using qualified type name
            // For instantiated generic types, qualifiedTypeName already includes type args
            // For non-generic types, just use "QualifiedTypeName_methodName"
            let mangledMethodName: String
            if isGenericInstantiation || resolvedTypeArgs.isEmpty {
                // qualifiedTypeName already includes type args for generic instantiations
                mangledMethodName = "\(qualifiedTypeName)_\(methodName)"
            } else {
                // For uninstantiated generic types, add type args
                let argLayoutKeys = resolvedTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                mangledMethodName = "\(qualifiedTypeName)_\(argLayoutKeys)_\(methodName)"
            }
            
            // Check for concrete extension methods first (for primitive types like Int, UInt, etc.)
            if let methods = extensionMethods[templateName], let _ = methods[methodName] {
                // Method exists in concrete extension methods, just generate the call
                let functionType = Type.function(
                    parameters: resolvedArguments.map { Parameter(type: $0.type, kind: .byVal) },
                    returns: resolvedReturnType
                )
                let callee: TypedExpressionNode = .variable(
                    identifier: makeSymbol(name: mangledMethodName, type: functionType, kind: .function)
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
                            kind: .extensionMethod(templateName: templateName, baseType: resolvedBaseType, template: ext, typeArgs: resolvedTypeArgs, methodTypeArgs: []),
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
                identifier: makeSymbol(name: mangledMethodName, type: functionType, kind: .function)
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
            
        case .assignment(let target, let op, let value):
            return .assignment(
                target: resolveTypesInExpression(target),
                operator: op,
                value: resolveTypesInExpression(value)
            )

        case .deptrAssignment(let pointer, let op, let value):
            return .deptrAssignment(
                pointer: resolveTypesInExpression(pointer),
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
        case .offsetPtr(let ptr, let offset):
            return .offsetPtr(
                ptr: resolveTypesInExpression(ptr),
                offset: resolveTypesInExpression(offset)
            )
        case .takeMemory(let ptr):
            return .takeMemory(ptr: resolveTypesInExpression(ptr))
        case .nullPtr(let resultType):
            return .nullPtr(resultType: resultType)
            
        }
    }
}

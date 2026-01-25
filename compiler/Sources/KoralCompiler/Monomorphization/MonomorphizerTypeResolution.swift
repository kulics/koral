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
    internal func resolveBuiltinType(_ name: String) -> Type? {
        return SemaUtils.resolveBuiltinType(name)
    }
    
    // MARK: - Parameterized Type Resolution
    
    /// Substitutes type parameters in a type.
    /// This method extends SemaUtils.substituteType to also resolve genericStruct/genericUnion
    /// to concrete structure/union types by instantiating them.
    internal func substituteType(_ type: Type, substitution: [String: Type]) -> Type {
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
    internal func resolveParameterizedType(_ type: Type, visited: Set<UUID> = []) -> Type {
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
            if resolvedArgs.contains(where: { $0.containsGenericParameter }) {
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
            // Check if we already have this type cached FIRST (before resolving args)
            let initialCacheKey = "\(template)<\(args.map { $0.description }.joined(separator: ","))>"
            if let cached = instantiatedTypes[initialCacheKey] {
                return cached
            }
            
            // First, recursively resolve the type arguments
            let resolvedArgs = args.map { resolveParameterizedType($0, visited: visited) }
            
            // If any arg still contains generic parameters, we can't resolve yet
            if resolvedArgs.contains(where: { $0.containsGenericParameter }) {
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
    internal func resolveTypesInGlobalNode(_ node: TypedGlobalNode) throws -> TypedGlobalNode {
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
            
            // Track the resolved return type (will be updated if we find a concrete method)
            var resolvedReturnType = resolveParameterizedType(type)
            
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
}


// MARK: - Statement Type Resolution Extension

extension Monomorphizer {
    
    /// Resolves types in a statement.
    internal func resolveTypesInStatement(_ stmt: TypedStatementNode) -> TypedStatementNode {
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
}

// MARK: - Pattern Type Resolution Extension

extension Monomorphizer {
    
    /// Resolves types in a pattern.
    internal func resolveTypesInPattern(_ pattern: TypedPattern) -> TypedPattern {
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
}

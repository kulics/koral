// MonomorphizerExpressionSubstitution.swift
// Extension for Monomorphizer that handles expression type substitution.
// This file contains methods for substituting type parameters in expressions,
// statements, patterns, and intrinsic calls with concrete types.

import Foundation

// MARK: - Expression Type Substitution Extension

extension Monomorphizer {
    private func substitutionMethodLookupBaseType(for base: TypedExpressionNode) -> Type {
        if case .variable = base {
            return base.type
        }
        if case .referenceExpression(let inner, _) = base {
            return substitutionMethodLookupBaseType(for: inner)
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
        if case .weakReference(let inner) = base.type {
            return inner
        }
        if case .mutableWeakReference(let inner) = base.type {
            return inner
        }
        return base.type
    }


    // MARK: - Expression Substitution
    
    /// Substitutes type parameters in a typed expression with concrete types.
    /// - Parameters:
    ///   - expr: The expression to transform
    ///   - substitution: Map from type parameter names to concrete types
    /// - Returns: The expression with substituted types
    internal func substituteTypesInExpression(
        _ expr: TypedExpressionNode,
        substitution: [String: Type]
    ) -> TypedExpressionNode {
        switch expr {
        case .integerLiteral(let value, let type):
            return .integerLiteral(value: value, type: substituteType(type, substitution: substitution))
            
        case .floatLiteral(let value, let type):
            return .floatLiteral(value: value, type: substituteType(type, substitution: substitution))
            
        case .stringLiteral(let value, let type):
            return .stringLiteral(value: value, type: substituteType(type, substitution: substitution))

        case .interpolatedString(let parts, let type):
            let newParts = parts.map { part -> TypedInterpolatedPart in
                switch part {
                case .literal(let value):
                    return .literal(value)
                case .expression(let expr):
                    return .expression(substituteTypesInExpression(expr, substitution: substitution))
                }
            }
            return .interpolatedString(parts: newParts, type: substituteType(type, substitution: substitution))
            
        case .booleanLiteral(let value, let type):
            return .booleanLiteral(value: value, type: substituteType(type, substitution: substitution))
            
        case .castExpression(let expression, let type):
            return .castExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .arithmeticExpression(let left, let op, let right, let type):
            return .arithmeticExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

        case .wrappingArithmeticExpression(let left, let op, let right, let type):
            return .wrappingArithmeticExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

        case .comparisonExpression(let left, let op, let right, let type):
            return .comparisonExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .andExpression(let left, let right, let type):
            return .andExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .orExpression(let left, let right, let type):
            return .orExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .notExpression(let expression, let type):
            return .notExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

        case .isExpression(let subject, let pattern, let type):
            return .isExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

        case .isNotExpression(let subject, let pattern, let type):
            return .isNotExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .bitwiseExpression(let left, let op, let right, let type):
            return .bitwiseExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

            
        case .bitwiseNotExpression(let expression, let type):
            return .bitwiseNotExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .derefExpression(let expression, let type):
            return .derefExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

        case .unsafeDerefExpression(let expression, let type):
            return .unsafeDerefExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .referenceExpression(let expression, let type):
            return .referenceExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

        case .ptrExpression(let expression, let type):
            return .ptrExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .variable(let identifier):
            let identifierName = context.getName(identifier.defId) ?? "<unknown>"
            var newName = identifierName
            let newType = substituteType(identifier.type, substitution: substitution)
            var resolvedIdentifier = Symbol(defId: identifier.defId, type: newType, kind: identifier.kind)
            if case .function = identifier.kind,
               let instantiated = resolveStandaloneMethodFunctionReference(
                definitionMethod: identifier,
                substitutedFunctionType: newType
               ) {
                resolvedIdentifier = instantiated
            }
            
            // For generic function templates, rewrite to the specialized emitted symbol name.
            let isFunction: Bool
            if case .function = identifier.kind {
                isFunction = true
            } else {
                isFunction = false
            }
            
            if isFunction,
               case .function(_, _) = identifier.type,
               !substitution.isEmpty {
                // Check if this is a generic function template
                if let template = input.genericTemplates.functionTemplates[identifierName] {
                    // Build the specialized symbol name using substituted type arguments.
                    let typeArgs = template.typeParameters.compactMap { param -> Type? in
                        substitution[param.name]
                    }
                    if typeArgs.count == template.typeParameters.count {
                        let argLayoutKeys = typeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                        newName = "\(identifierName)_\(argLayoutKeys)"
                        
                        // Ensure the function is instantiated
                        if !input.genericTemplates.intrinsicGenericFunctions.contains(identifierName)
                            && !generatedLayouts.contains(newName)
                            && !typeArgs.contains(where: { context.containsGenericParameter($0) }) {
                            pendingRequests.append(InstantiationRequest(
                                kind: .function(template: template, args: typeArgs),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            }

            
            if case .function = identifier.kind,
               newName != identifierName {
                let newIdentifier = copySymbolWithNewDefId(
                    identifier,
                    newName: newName,
                    newType: newType
                )
                return .variable(identifier: newIdentifier)
            }

            let newIdentifier = Symbol(
                defId: resolvedIdentifier.defId,
                type: resolvedIdentifier.type,
                kind: identifier.kind
            )
            return .variable(identifier: newIdentifier)
            
        case .blockExpression(let statements, let tailExpression, let type):
            let newStatements = statements.map { substituteTypesInStatement($0, substitution: substitution) }
            return .blockExpression(
                statements: newStatements,
                tailExpression: tailExpression.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )
            
        case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
            return .ifExpression(
                condition: substituteTypesInExpression(condition, substitution: substitution),
                thenBranch: substituteTypesInExpression(thenBranch, substitution: substitution),
                elseBranch: elseBranch.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )
            
        case .ifPatternExpression(let subject, let pattern, let bindings, let thenBranch, let elseBranch, let type):
            let newBindings = bindings.map { (name, mutable, bindType) in
                (name, mutable, substituteType(bindType, substitution: substitution))
            }
            return .ifPatternExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                bindings: newBindings,
                thenBranch: substituteTypesInExpression(thenBranch, substitution: substitution),
                elseBranch: elseBranch.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )
            
        case .call(let callee, let arguments, let type):
            var newCallee = substituteTypesInExpression(callee, substitution: substitution)
            var newArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            let newType = substituteType(type, substitution: substitution)

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
                let lookupBaseType = substitutionMethodLookupBaseType(for: base)
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
                    let resolvedMethodType = concreteMethod.type
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

            if case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, _) = newCallee,
               !context.containsGenericParameter(base.type) {
                let declaredMethodType = substituteType(method.type, substitution: substitution)
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
                let substMArgs = (methodTypeArgs ?? []).map { substituteType($0, substitution: substitution) }
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

            return .call(callee: newCallee, arguments: newArguments, type: newType)

        
        case .genericCall(let functionName, let typeArgs, let arguments, let type):
            // Substitute type arguments
            let substitutedTypeArgs = typeArgs.map { substituteType($0, substitution: substitution) }
            // Substitute arguments
            let newArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            // Substitute return type
            let newType = substituteType(type, substitution: substitution)
            
            // If type args still contain generic parameters, keep as genericCall
            if substitutedTypeArgs.contains(where: { context.containsGenericParameter($0) }) {
                return .genericCall(
                    functionName: functionName,
                    typeArgs: substitutedTypeArgs,
                    arguments: newArguments,
                    type: newType
                )
            }
            
            // Convert to regular call by instantiating the function
            if let template = input.genericTemplates.functionTemplates[functionName] {
                // Ensure the function is instantiated
                let key = InstantiationKey.function(templateDefId: template.defId, args: substitutedTypeArgs)
                if !input.genericTemplates.intrinsicGenericFunctions.contains(functionName)
                    && !processedRequestKeys.contains(key) {
                    pendingRequests.append(InstantiationRequest(
                        kind: .function(template: template, args: substitutedTypeArgs),
                        sourceLine: currentLine,
                        sourceFileName: currentFileName
                    ))
                }
                
                // Build specialized function symbol name
                let argLayoutKeys = substitutedTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
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
                typeArgs: substitutedTypeArgs,
                arguments: newArguments,
                type: newType
            )

            
        case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, _):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            let substMethodType = substituteType(method.type, substitution: substitution)
            let substitutedTypeArgs = typeArgs?.map { substituteType($0, substitution: substitution) }
            let substitutedMethodTypeArgs = (methodTypeArgs ?? []).map { substituteType($0, substitution: substitution) }
            var adjustedBase = newBase
            var resolvedExpressionType = substMethodType
            var newMethod = Symbol(defId: method.defId, type: substMethodType, kind: method.kind)

            if !context.containsGenericParameter(adjustedBase.type) {
                let resolution = (try? resolveMethodInstanceByIdentityForReceiver(
                    definitionMethod: method,
                    substitutedMethodType: substMethodType,
                    substitutedMethodTypeArgs: substitutedMethodTypeArgs,
                    receiverType: adjustedBase.type
                )) ?? .keepDefinitionTime(type: substMethodType)
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
                typeArgs: substitutedTypeArgs,
                methodTypeArgs: substitutedMethodTypeArgs,
                type: resolvedExpressionType
            )
            
        case .traitMethodPlaceholder(let traitName, let traitDefId, let traitMethodDefId, let methodName, let base, let methodTypeArgs, let type):
            // Substitute types in the placeholder
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            let substitutedMethodTypeArgs = methodTypeArgs.map { substituteType($0, substitution: substitution) }
            let substitutedType = substituteType(type, substitution: substitution)
            let lookupBaseType = substitutionMethodLookupBaseType(for: newBase)
            let normalizedExpectedMethodType = normalizedTraitPlaceholderExpectedMethodType(
                substitutedType,
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
                        methodTypeArgs: substitutedMethodTypeArgs,
                        type: substitutedType
                    )
                }

                if let concreteMethod = resolveTraitPlaceholderMethodByIdentity(
                    traitMethodDefId: traitMethodDefId,
                    expectedMethodType: normalizedExpectedMethodType,
                    methodTypeArgs: substitutedMethodTypeArgs,
                    receiverType: lookupBaseType
                ) {
                    let resolvedMethodType = concreteMethod.type
                    let adjustedBase = alignMethodReferenceBase(newBase, to: resolvedMethodType)
                    return .methodReference(
                        base: adjustedBase,
                        method: Symbol(defId: concreteMethod.defId, type: resolvedMethodType, kind: concreteMethod.kind),
                        typeArgs: nil,
                        methodTypeArgs: substitutedMethodTypeArgs,
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
                methodTypeArgs: substitutedMethodTypeArgs,
                type: substitutedType
            )

        case .traitObjectConversion(let inner, let traitName, let traitDefId, let traitTypeArgs, let concreteType, let type):
            let substitutedInner = substituteTypesInExpression(inner, substitution: substitution)
            let substitutedTraitTypeArgs = traitTypeArgs.map { substituteType($0, substitution: substitution) }
            let substitutedConcreteType = substituteType(concreteType, substitution: substitution)
            let substitutedType = substituteType(type, substitution: substitution)

            // Collect vtable request when concrete type is fully resolved
            if !context.containsGenericParameter(substitutedConcreteType) {
                let traitRef = CanonicalTraitRef(traitName: traitName, traitDefId: traitDefId, traitTypeArgs: substitutedTraitTypeArgs)
                vtableRequests.insert(VtableRequest(
                    concreteType: substitutedConcreteType,
                    traitName: traitName,
                    traitDefId: traitDefId,
                    traitTypeArgs: substitutedTraitTypeArgs,
                    witnessKey: ConformanceWitness.key(selfType: substitutedConcreteType, traitRef: traitRef)
                ))
                materializeConformanceWitness(
                    concreteType: substitutedConcreteType,
                    traitName: traitName,
                    traitDefId: traitDefId,
                    traitTypeArgs: substitutedTraitTypeArgs
                )
            }

            return .traitObjectConversion(
                inner: substitutedInner,
                traitName: traitName,
                traitDefId: traitDefId,
                traitTypeArgs: substitutedTraitTypeArgs,
                concreteType: substitutedConcreteType,
                type: substitutedType
            )

        case .traitMethodCall(let receiver, let traitName, let traitDefId, let methodName, let methodIndex, let arguments, let type):
            return .traitMethodCall(
                receiver: substituteTypesInExpression(receiver, substitution: substitution),
                traitName: traitName,
                traitDefId: traitDefId,
                methodName: methodName,
                methodIndex: methodIndex,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )
            
        case .typeConstruction(let identifier, let typeArgs, let arguments, let type):
            let substitutedType = substituteType(identifier.type, substitution: substitution)
            
            // If the substituted type is a concrete structure or enum, we need to:
            // 1. Update the identifier name to match the concrete type's layout name
            // 2. Ensure the concrete type is instantiated
            var newName = context.getName(identifier.defId) ?? "<unknown>"
            if case .structure(let defId) = substitutedType {
                let layoutName = context.getName(defId) ?? substitutedType.description
                let isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
                newName = layoutName
                // Trigger instantiation of the concrete type if needed
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !context.containsGenericParameter(substitutedType) {
                    // Find the template and instantiate
                    // By DECLARATION -- the instance links to its template.
                    if let template = input.genericTemplates.structTemplate(
                        forDefId: context.templateDeclaration(of: defId)) {
                        let typeArgsReconstructed: [Type] = context.getTypeArguments(defId)
                            ?? template.typeParameters.compactMap { param in
                                substitution[param.name]
                            }
                        if typeArgsReconstructed.count != template.typeParameters.count {
                            fatalError("Missing type arguments for generic instantiation '\(layoutName)' during substitution.")
                        }
                        pendingRequests.append(InstantiationRequest(
                            kind: .structType(template: template, args: typeArgsReconstructed),
                            sourceLine: currentLine,
                            sourceFileName: currentFileName
                        ))
                    }
                }
            } else if case .`enum`(let defId) = substitutedType {
                let layoutName = context.getName(defId) ?? substitutedType.description
                let isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
                newName = layoutName
                // Similar logic for enums
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !context.containsGenericParameter(substitutedType) {
                    // By DECLARATION -- the instance links to its template.
                    if let template = input.genericTemplates.enumTemplate(
                        forDefId: context.templateDeclaration(of: defId)) {
                        let typeArgsReconstructed: [Type] = context.getTypeArguments(defId)
                            ?? template.typeParameters.compactMap { param in
                                substitution[param.name]
                            }
                        if typeArgsReconstructed.count != template.typeParameters.count {
                            fatalError("Missing type arguments for generic instantiation '\(layoutName)' during substitution.")
                        }
                        pendingRequests.append(InstantiationRequest(
                            kind: .enumType(template: template, args: typeArgsReconstructed),
                            sourceLine: currentLine,
                            sourceFileName: currentFileName
                        ))
                    }
                }
            }
            
            let newIdentifier = copySymbolWithNewDefId(
                identifier,
                newName: newName,
                newType: substitutedType
            )
            // Substitute type args if present
            let substitutedTypeArgs = typeArgs?.map { substituteType($0, substitution: substitution) }
            return .typeConstruction(
                identifier: newIdentifier,
                typeArgs: substitutedTypeArgs,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) },
                type: substituteType(type, substitution: substitution)
            )

            
        case .memberPath(let source, let path):
            let newPath = path.map { sym in
                copySymbolWithNewDefId(
                    sym,
                    newType: substituteType(sym.type, substitution: substitution)
                )
            }
            return .memberPath(
                source: substituteTypesInExpression(source, substitution: substitution),
                path: newPath
            )
            
        case .enumConstruction(let type, let caseName, let arguments):
            return .enumConstruction(
                type: substituteType(type, substitution: substitution),
                caseName: caseName,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            )
            
        case .intrinsicCall(let intrinsic):
            return .intrinsicCall(substituteTypesInIntrinsic(intrinsic, substitution: substitution))
            
        case .whenExpression(let subject, let cases, let type):
            let newCases = cases.map { matchCase in
                TypedMatchCase(
                    pattern: substituteTypesInPattern(matchCase.pattern, substitution: substitution),
                    guardExpr: matchCase.guardExpr.map { substituteTypesInExpression($0, substitution: substitution) },
                    body: substituteTypesInExpression(matchCase.body, substitution: substitution)
                )
            }
            return .whenExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                cases: newCases,
                type: substituteType(type, substitution: substitution)
            )
            
        case .staticMethodCall(let baseType, let methodName, let typeArgs, let methodTypeArgs, let arguments, let type):
            // Substitute types in the static method call
            let substitutedBaseType = substituteType(baseType, substitution: substitution)
            let substitutedTypeArgs = typeArgs.map { substituteType($0, substitution: substitution) }
            let substitutedMethodTypeArgs = methodTypeArgs.map { substituteType($0, substitution: substitution) }
            let substitutedArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            let substitutedReturnType = substituteType(type, substitution: substitution)

            return .staticMethodCall(
                baseType: substitutedBaseType,
                methodName: methodName,
                typeArgs: substitutedTypeArgs,
                methodTypeArgs: substitutedMethodTypeArgs,
                arguments: substitutedArguments,
                type: substitutedReturnType
            )

            
        case .lambdaExpression(let parameters, let captures, let body, let type):
            // Substitute types in lambda parameters
            let newParameters = parameters.map { param in
                copySymbolPreservingDefId(
                    param,
                    newType: substituteType(param.type, substitution: substitution)
                )
            }
            // Substitute types in captures
            let newCaptures = captures.map { capture in
                CapturedVariable(
                    symbol: copySymbolPreservingDefId(
                        capture.symbol,
                        newType: substituteType(capture.symbol.type, substitution: substitution)
                    ),
                    captureKind: capture.captureKind
                )
            }
            return .lambdaExpression(
                parameters: newParameters,
                captures: newCaptures,
                body: substituteTypesInExpression(body, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
        }
    }
    
    // MARK: - Statement Substitution
    
    /// Substitutes types in a statement.
    internal func substituteTypesInStatement(
        _ stmt: TypedStatementNode,
        substitution: [String: Type]
    ) -> TypedStatementNode {
        switch stmt {
        case .variableDeclaration(let identifier, let value, let mutable):
            let newIdentifier = copySymbolPreservingDefId(
                identifier,
                newType: substituteType(identifier.type, substitution: substitution)
            )
            return .variableDeclaration(
                identifier: newIdentifier,
                value: substituteTypesInExpression(value, substitution: substitution),
                mutable: mutable
            )

        case .tupleVariableDeclaration(let tupleSymbol, let tupleValue, let bindings):
            let newTupleSymbol = copySymbolPreservingDefId(
                tupleSymbol, newType: substituteType(tupleSymbol.type, substitution: substitution))
            let newBindings = bindings.map { binding -> Symbol? in
                binding.map {
                    copySymbolPreservingDefId($0, newType: substituteType($0.type, substitution: substitution))
                }
            }
            return .tupleVariableDeclaration(
                tupleSymbol: newTupleSymbol,
                tupleValue: substituteTypesInExpression(tupleValue, substitution: substitution),
                bindings: newBindings
            )

            
        case .assignment(let target, let op, let value):
            return .assignment(
                target: substituteTypesInExpression(target, substitution: substitution),
                operator: op,
                value: substituteTypesInExpression(value, substitution: substitution)
            )
            
        case .expression(let expr):
            return .expression(substituteTypesInExpression(expr, substitution: substitution))

        case .ifStatement(let condition, let thenBranch, let elseBranch):
            return .ifStatement(
                condition: substituteTypesInExpression(condition, substitution: substitution),
                thenBranch: substituteTypesInExpression(thenBranch, substitution: substitution),
                elseBranch: elseBranch.map { substituteTypesInExpression($0, substitution: substitution) }
            )

        case .ifPatternStatement(let subject, let pattern, let bindings, let thenBranch, let elseBranch):
            return .ifPatternStatement(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                bindings: bindings.map { ($0.0, $0.1, substituteType($0.2, substitution: substitution)) },
                thenBranch: substituteTypesInExpression(thenBranch, substitution: substitution),
                elseBranch: elseBranch.map { substituteTypesInExpression($0, substitution: substitution) }
            )

        case .whileStatement(let condition, let body):
            return .whileStatement(
                condition: substituteTypesInExpression(condition, substitution: substitution),
                body: substituteTypesInExpression(body, substitution: substitution)
            )

        case .whilePatternStatement(let subject, let pattern, let bindings, let body):
            return .whilePatternStatement(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                bindings: bindings.map { ($0.0, $0.1, substituteType($0.2, substitution: substitution)) },
                body: substituteTypesInExpression(body, substitution: substitution)
            )

        case .whenStatement(let subject, let cases):
            return .whenStatement(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                cases: cases.map {
                    TypedStatementMatchCase(
                        pattern: substituteTypesInPattern($0.pattern, substitution: substitution),
                        guardExpr: $0.guardExpr.map { substituteTypesInExpression($0, substitution: substitution) },
                        body: substituteTypesInExpression($0.body, substitution: substitution)
                    )
                }
            )
            
        case .return(let value):
            return .return(value: value.map { substituteTypesInExpression($0, substitution: substitution) })
            
        case .break:
            return .break
            
        case .continue:
            return .continue

        case .deferStatement(let expression):
            return .deferStatement(expression: substituteTypesInExpression(expression, substitution: substitution))

        }
    }
    
    // MARK: - Pattern Substitution
    
    /// Substitutes types in a pattern.
    internal func substituteTypesInPattern(
        _ pattern: TypedPattern,
        substitution: [String: Type]
    ) -> TypedPattern {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .floatLiteral, .stringLiteral, .wildcard:
            return pattern
        case .nullLiteral(let resultType):
            return .nullLiteral(resultType: substituteType(resultType, substitution: substitution))
        case .weakBinding(let symbol):
            let newSymbol = copySymbolPreservingDefId(
                symbol,
                newType: substituteType(symbol.type, substitution: substitution)
            )
            return .weakBinding(symbol: newSymbol)
        case .traitObjectType(let targetType):
            return .traitObjectType(targetType: substituteType(targetType, substitution: substitution))
        case .traitObjectTypeBinding(let symbol, let targetType):
            let newSymbol = copySymbolPreservingDefId(
                symbol,
                newType: substituteType(symbol.type, substitution: substitution)
            )
            return .traitObjectTypeBinding(
                symbol: newSymbol,
                targetType: substituteType(targetType, substitution: substitution)
            )
            
        case .variable(let symbol):
            let newSymbol = copySymbolPreservingDefId(
                symbol,
                newType: substituteType(symbol.type, substitution: substitution)
            )
            return .variable(symbol: newSymbol)
            
        case .enumCase(let caseName, let tagIndex, let elements):
            return .enumCase(
                caseName: caseName,
                tagIndex: tagIndex,
                elements: elements.map { substituteTypesInPattern($0, substitution: substitution) }
            )

            
        case .comparisonPattern:
            // Comparison patterns don't contain types to substitute
            return pattern
            
        case .andPattern(let left, let right):
            return .andPattern(
                left: substituteTypesInPattern(left, substitution: substitution),
                right: substituteTypesInPattern(right, substitution: substitution)
            )
            
        case .orPattern(let left, let right):
            return .orPattern(
                left: substituteTypesInPattern(left, substitution: substitution),
                right: substituteTypesInPattern(right, substitution: substitution)
            )
            
        case .notPattern(let inner):
            return .notPattern(pattern: substituteTypesInPattern(inner, substitution: substitution))
            
        case .structPattern(let typeName, let elements):
            return .structPattern(
                typeName: typeName,
                elements: elements.map { substituteTypesInPattern($0, substitution: substitution) }
            )

        case .listPattern(let elements, let ops):
            return .listPattern(
                elements: elements.map { substituteTypesInPattern($0, substitution: substitution) },
                ops: refreshListPatternOps(
                    ops,
                    listType: substituteType(ops.listType, substitution: substitution),
                    elementType: substituteType(ops.elementType, substitution: substitution)
                )
            )

        case .restPattern:
            return pattern
        }
    }
    
    // MARK: - Intrinsic Substitution
    
    /// Substitutes types in an intrinsic call.
    internal func substituteTypesInIntrinsic(
        _ intrinsic: TypedIntrinsic,
        substitution: [String: Type]
    ) -> TypedIntrinsic {
        switch intrinsic {
        case .allocMemory(let count, let resultType):
            return .allocMemory(
                count: substituteTypesInExpression(count, substitution: substitution),
                resultType: substituteType(resultType, substitution: substitution)
            )
            
        case .deallocMemory(let ptr):
            return .deallocMemory(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .copyMemory(let dest, let source, let count):
            return .copyMemory(
                dest: substituteTypesInExpression(dest, substitution: substitution),
                source: substituteTypesInExpression(source, substitution: substitution),
                count: substituteTypesInExpression(count, substitution: substitution)
            )
            
        case .moveMemory(let dest, let source, let count):
            return .moveMemory(
                dest: substituteTypesInExpression(dest, substitution: substitution),
                source: substituteTypesInExpression(source, substitution: substitution),
                count: substituteTypesInExpression(count, substitution: substitution)
            )

            



            
        case .downgradeRef(let val, let resultType):
            return .downgradeRef(
                val: substituteTypesInExpression(val, substitution: substitution),
                resultType: substituteType(resultType, substitution: substitution)
            )
            
        case .upgradeRef(let val, let resultType):
            return .upgradeRef(
                val: substituteTypesInExpression(val, substitution: substitution),
                resultType: substituteType(resultType, substitution: substitution)
            )
            
        case .initMemory(let ptr, let val):
            return .initMemory(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                val: substituteTypesInExpression(val, substitution: substitution)
            )
        case .deinitMemory(let ptr):
            return .deinitMemory(ptr: substituteTypesInExpression(ptr, substitution: substitution))
        case .takeMemory(let ptr):
            return .takeMemory(ptr: substituteTypesInExpression(ptr, substitution: substitution))
        case .nullPtr(let resultType):
            return .nullPtr(resultType: substituteType(resultType, substitution: substitution))
            
        case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
            return .spawnThread(
                outHandle: substituteTypesInExpression(outHandle, substitution: substitution),
                outTid: substituteTypesInExpression(outTid, substitution: substitution),
                closure: substituteTypesInExpression(closure, substitution: substitution),
                stackSize: substituteTypesInExpression(stackSize, substitution: substitution)
            )
            
        }
    }
}

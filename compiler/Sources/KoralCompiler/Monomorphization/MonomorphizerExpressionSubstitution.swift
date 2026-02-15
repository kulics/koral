// MonomorphizerExpressionSubstitution.swift
// Extension for Monomorphizer that handles expression type substitution.
// This file contains methods for substituting type parameters in expressions,
// statements, patterns, and intrinsic calls with concrete types.

import Foundation

// MARK: - Expression Type Substitution Extension

extension Monomorphizer {
    
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

        case .wrappingShiftExpression(let left, let op, let right, let type):
            return .wrappingShiftExpression(
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
            
        case .letExpression(let identifier, let value, let body, let type):
            let newIdentifier = copySymbolPreservingDefId(
                identifier,
                newType: substituteType(identifier.type, substitution: substitution)
            )
            return .letExpression(
                identifier: newIdentifier,
                value: substituteTypesInExpression(value, substitution: substitution),
                body: substituteTypesInExpression(body, substitution: substitution),
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

        case .deptrExpression(let expression, let type):
            return .deptrExpression(
                expression: substituteTypesInExpression(expression, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .variable(let identifier):
            let identifierName = context.getName(identifier.defId) ?? "<unknown>"
            var newName = identifierName
            let newType = substituteType(identifier.type, substitution: substitution)
            
            // Check if this is a generic function that needs its name updated to the mangled name
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
                    // Calculate the mangled name using the substituted type arguments
                    let typeArgs = template.typeParameters.compactMap { param -> Type? in
                        substitution[param.name]
                    }
                    if typeArgs.count == template.typeParameters.count {
                        let argLayoutKeys = typeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
                        newName = "\(identifierName)_\(argLayoutKeys)"
                        
                        // Ensure the function is instantiated
                        if !generatedLayouts.contains(newName) && !typeArgs.contains(where: { context.containsGenericParameter($0) }) {
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

            let newIdentifier = copySymbolPreservingDefId(
                identifier,
                newType: newType
            )
            return .variable(identifier: newIdentifier)
            
        case .blockExpression(let statements, let finalExpression, let type):
            let newStatements = statements.map { substituteTypesInStatement($0, substitution: substitution) }
            let newFinal = finalExpression.map { substituteTypesInExpression($0, substitution: substitution) }
            return .blockExpression(
                statements: newStatements,
                finalExpression: newFinal,
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
            let newCallee = substituteTypesInExpression(callee, substitution: substitution)
            let newArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            let newType = substituteType(type, substitution: substitution)

            
            // Apply lowering for primitive type methods (equals, compare)
            // This mirrors the lowering done in TypeChecker for direct calls
            if case .methodReference(let base, let method, _, _, _) = newCallee {
                let rawMethodName = context.getName(method.defId) ?? ""
                let methodName = extractMethodName(rawMethodName)
                // Lower primitive `equals(self, other) Bool` to scalar equality
                if methodName == "equals",
                   newType == .bool,
                   newArguments.count == 1,
                   base.type == newArguments[0].type,
                   isBuiltinEqualityComparable(base.type)
                {
                    return .comparisonExpression(left: base, op: .equal, right: newArguments[0], type: .bool)
                }

                // Lower primitive `compare(self, other) Int` to scalar comparisons
                if methodName == "compare",
                   newType == .int,
                   newArguments.count == 1,
                   base.type == newArguments[0].type,
                   isBuiltinOrderingComparable(base.type)
                {
                    let lhsVal = base
                    let rhsVal = newArguments[0]

                    let less: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .less, right: rhsVal, type: .bool)
                    let greater: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .greater, right: rhsVal, type: .bool)
                    let minusOne: TypedExpressionNode = .integerLiteral(value: "-1", type: .int)
                    let plusOne: TypedExpressionNode = .integerLiteral(value: "1", type: .int)
                    let zero: TypedExpressionNode = .integerLiteral(value: "0", type: .int)

                    let gtBranch: TypedExpressionNode = .ifExpression(condition: greater, thenBranch: plusOne, elseBranch: zero, type: .int)
                    return .ifExpression(condition: less, thenBranch: minusOne, elseBranch: gtBranch, type: .int)
                }

                // Lower primitive arithmetic intrinsic methods to scalar ops
                if isBuiltinArithmeticType(base.type) {
                    if newArguments.count == 1, base.type == newArguments[0].type {
                        switch methodName {
                        case "add":
                            return .arithmeticExpression(left: base, op: .plus, right: newArguments[0], type: newType)
                        case "sub":
                            return .arithmeticExpression(left: base, op: .minus, right: newArguments[0], type: newType)
                        case "mul":
                            return .arithmeticExpression(left: base, op: .multiply, right: newArguments[0], type: newType)
                        case "div":
                            return .arithmeticExpression(left: base, op: .divide, right: newArguments[0], type: newType)
                        case "rem":
                            switch base.type {
                            case .float32, .float64:
                                break
                            default:
                                return .arithmeticExpression(left: base, op: .modulo, right: newArguments[0], type: newType)
                            }
                        case "wrapping_add":
                            return .wrappingArithmeticExpression(left: base, op: .plus, right: newArguments[0], type: newType)
                        case "wrapping_sub":
                            return .wrappingArithmeticExpression(left: base, op: .minus, right: newArguments[0], type: newType)
                        case "wrapping_mul":
                            return .wrappingArithmeticExpression(left: base, op: .multiply, right: newArguments[0], type: newType)
                        case "wrapping_div":
                            return .wrappingArithmeticExpression(left: base, op: .divide, right: newArguments[0], type: newType)
                        case "wrapping_mod":
                            return .wrappingArithmeticExpression(left: base, op: .modulo, right: newArguments[0], type: newType)
                        case "wrapping_shl":
                            return .wrappingShiftExpression(left: base, op: .shiftLeft, right: newArguments[0], type: newType)
                        case "wrapping_shr":
                            return .wrappingShiftExpression(left: base, op: .shiftRight, right: newArguments[0], type: newType)
                        default:
                            break
                        }
                    }
                    if methodName == "neg", newArguments.isEmpty {
                        let zero = makeZeroLiteral(for: base.type)
                        return .arithmeticExpression(left: zero, op: .minus, right: base, type: newType)
                    }
                    if methodName == "wrapping_neg", newArguments.isEmpty {
                        let zero = makeZeroLiteral(for: base.type)
                        return .wrappingArithmeticExpression(left: zero, op: .minus, right: base, type: newType)
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
                let key = InstantiationKey.function(templateName: functionName, args: substitutedTypeArgs)
                if !processedRequestKeys.contains(key) {
                    pendingRequests.append(InstantiationRequest(
                        kind: .function(template: template, args: substitutedTypeArgs),
                        sourceLine: currentLine,
                        sourceFileName: currentFileName
                    ))
                }
                
                // Calculate the mangled name
                let argLayoutKeys = substitutedTypeArgs.map { context.getLayoutKey($0) }.joined(separator: "_")
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
            
            // Fallback: keep as genericCall
            return .genericCall(
                functionName: functionName,
                typeArgs: substitutedTypeArgs,
                arguments: newArguments,
                type: newType
            )

            
        case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, let type):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            var newMethod = copySymbolWithNewDefId(
                method,
                newType: substituteType(method.type, substitution: substitution)
            )
            
            // Substitute type args if present
            let substitutedTypeArgs = typeArgs?.map { substituteType($0, substitution: substitution) }
            
            // Substitute method type args if present
            let substitutedMethodTypeArgs = methodTypeArgs?.map { substituteType($0, substitution: substitution) }
            let effectiveMethodTypeArgs = substitutedMethodTypeArgs ?? []
            
            // Track the resolved return type (will be updated if we find a concrete method)
            var resolvedReturnType = substituteType(type, substitution: substitution)
            
            // Resolve generic extension method to mangled name
            let methodName = context.getName(method.defId) ?? ""
            if !context.containsGenericParameter(newBase.type) {
                // Look up the concrete method on the substituted base type
                // Pass method type args for generic methods
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: effectiveMethodTypeArgs) {
                    newMethod = copySymbolWithNewDefId(concreteMethod)
                    // Extract the return type from the concrete method's function type
                    if case .function(_, let returns) = concreteMethod.type {
                        resolvedReturnType = returns
                    }
                }
            }
            
            return .methodReference(
                base: newBase,
                method: newMethod,
                typeArgs: substitutedTypeArgs,
                methodTypeArgs: effectiveMethodTypeArgs,
                type: resolvedReturnType
            )
            
        case .traitMethodPlaceholder(let traitName, let methodName, let base, let methodTypeArgs, let type):
            // Substitute types in the placeholder
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            let substitutedMethodTypeArgs = methodTypeArgs.map { substituteType($0, substitution: substitution) }
            let substitutedType = substituteType(type, substitution: substitution)
            
            // Enqueue trait placeholder request for later resolution
            enqueueTraitPlaceholderRequest(
                baseType: newBase.type,
                methodName: methodName,
                methodTypeArgs: substitutedMethodTypeArgs
            )
            
            // Try to resolve to concrete method if base type is now concrete
            if !context.containsGenericParameter(newBase.type) {
                // Look up the concrete method on the substituted base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: substitutedMethodTypeArgs) {
                    // Extract the return type from the concrete method's function type
                    var resolvedReturnType = substitutedType
                    if case .function(_, let returns) = concreteMethod.type {
                        resolvedReturnType = returns
                    }
                    var adjustedBase = newBase
                    if case .function(let params, _) = concreteMethod.type, let firstParam = params.first {
                        if case .reference(let inner) = firstParam.type, inner == adjustedBase.type {
                            adjustedBase = .referenceExpression(expression: adjustedBase, type: firstParam.type)
                        } else if case .reference(let inner) = adjustedBase.type, inner == firstParam.type {
                            adjustedBase = .derefExpression(expression: adjustedBase, type: inner)
                        }
                    }
                    return .methodReference(
                        base: adjustedBase,
                        method: copySymbolWithNewDefId(concreteMethod),
                        typeArgs: nil,
                        methodTypeArgs: substitutedMethodTypeArgs,
                        type: resolvedReturnType
                    )
                } else {
                    // Try to instantiate the method first
                    _ = try? instantiateTraitPlaceholderMethod(
                        baseType: newBase.type,
                        name: methodName,
                        methodTypeArgs: substitutedMethodTypeArgs
                    )
                    if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: substitutedMethodTypeArgs) {
                        var resolvedReturnType = substitutedType
                        if case .function(_, let returns) = concreteMethod.type {
                            resolvedReturnType = returns
                        }
                        var adjustedBase = newBase
                        if case .function(let params, _) = concreteMethod.type, let firstParam = params.first {
                            if case .reference(let inner) = firstParam.type, inner == adjustedBase.type {
                                adjustedBase = .referenceExpression(expression: adjustedBase, type: firstParam.type)
                            } else if case .reference(let inner) = adjustedBase.type, inner == firstParam.type {
                                adjustedBase = .derefExpression(expression: adjustedBase, type: inner)
                            }
                        }
                        return .methodReference(
                            base: adjustedBase,
                            method: copySymbolWithNewDefId(concreteMethod),
                            typeArgs: nil,
                            methodTypeArgs: substitutedMethodTypeArgs,
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
                methodTypeArgs: substitutedMethodTypeArgs,
                type: substitutedType
            )
            
        case .whileExpression(let condition, let body, let type):
            return .whileExpression(
                condition: substituteTypesInExpression(condition, substitution: substitution),
                body: substituteTypesInExpression(body, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .whilePatternExpression(let subject, let pattern, let bindings, let body, let type):
            let newBindings = bindings.map { (name, mutable, bindType) in
                (name, mutable, substituteType(bindType, substitution: substitution))
            }
            return .whilePatternExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                pattern: substituteTypesInPattern(pattern, substitution: substitution),
                bindings: newBindings,
                body: substituteTypesInExpression(body, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )

            
        case .typeConstruction(let identifier, let typeArgs, let arguments, let type):
            let substitutedType = substituteType(identifier.type, substitution: substitution)
            
            // If the substituted type is a concrete structure or union, we need to:
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
                    let baseName = context.getTemplateName(defId) ?? layoutName
                    if let template = input.genericTemplates.structTemplates[baseName] {
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
            } else if case .union(let defId) = substitutedType {
                let layoutName = context.getName(defId) ?? substitutedType.description
                let isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
                newName = layoutName
                // Similar logic for unions
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !context.containsGenericParameter(substitutedType) {
                    let baseName = context.getTemplateName(defId) ?? layoutName
                    if let template = input.genericTemplates.unionTemplates[baseName] {
                        let typeArgsReconstructed: [Type] = context.getTypeArguments(defId)
                            ?? template.typeParameters.compactMap { param in
                                substitution[param.name]
                            }
                        if typeArgsReconstructed.count != template.typeParameters.count {
                            fatalError("Missing type arguments for generic instantiation '\(layoutName)' during substitution.")
                        }
                        pendingRequests.append(InstantiationRequest(
                            kind: .unionType(template: template, args: typeArgsReconstructed),
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
            
        case .subscriptExpression(let base, let arguments, let method, let type):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            var newMethod = copySymbolWithNewDefId(
                method,
                newType: substituteType(method.type, substitution: substitution)
            )
            
            // Resolve method name to mangled name for generic extension methods
            let methodName = context.getName(method.defId) ?? ""
            if !context.containsGenericParameter(newBase.type) {
                // Look up the concrete method on the substituted base type
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName) {
                    newMethod = copySymbolWithNewDefId(concreteMethod)
                }
            }
            
            return .subscriptExpression(
                base: newBase,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) },
                method: newMethod,
                type: substituteType(type, substitution: substitution)
            )

            
        case .unionConstruction(let type, let caseName, let arguments):
            return .unionConstruction(
                type: substituteType(type, substitution: substitution),
                caseName: caseName,
                arguments: arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            )
            
        case .intrinsicCall(let intrinsic):
            return .intrinsicCall(substituteTypesInIntrinsic(intrinsic, substitution: substitution))
            
        case .matchExpression(let subject, let cases, let type):
            let newCases = cases.map { matchCase in
                TypedMatchCase(
                    pattern: substituteTypesInPattern(matchCase.pattern, substitution: substitution),
                    body: substituteTypesInExpression(matchCase.body, substitution: substitution)
                )
            }
            return .matchExpression(
                subject: substituteTypesInExpression(subject, substitution: substitution),
                cases: newCases,
                type: substituteType(type, substitution: substitution)
            )
            
        case .staticMethodCall(let baseType, let methodName, let typeArgs, let arguments, let type):
            // Substitute types in the static method call
            let substitutedBaseType = substituteType(baseType, substitution: substitution)
            let substitutedTypeArgs = typeArgs.map { substituteType($0, substitution: substitution) }
            let substitutedArguments = arguments.map { substituteTypesInExpression($0, substitution: substitution) }
            let substitutedReturnType = substituteType(type, substitution: substitution)
            
            return .staticMethodCall(
                baseType: substitutedBaseType,
                methodName: methodName,
                typeArgs: substitutedTypeArgs,
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

            
        case .assignment(let target, let op, let value):
            return .assignment(
                target: substituteTypesInExpression(target, substitution: substitution),
                operator: op,
                value: substituteTypesInExpression(value, substitution: substitution)
            )

        case .deptrAssignment(let pointer, let op, let value):
            return .deptrAssignment(
                pointer: substituteTypesInExpression(pointer, substitution: substitution),
                operator: op,
                value: substituteTypesInExpression(value, substitution: substitution)
            )
            
        case .expression(let expr):
            return .expression(substituteTypesInExpression(expr, substitution: substitution))
            
        case .return(let value):
            return .return(value: value.map { substituteTypesInExpression($0, substitution: substitution) })
            
        case .break:
            return .break
            
        case .continue:
            return .continue
        }
    }
    
    // MARK: - Pattern Substitution
    
    /// Substitutes types in a pattern.
    internal func substituteTypesInPattern(
        _ pattern: TypedPattern,
        substitution: [String: Type]
    ) -> TypedPattern {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
            return pattern
            
        case .variable(let symbol):
            let newSymbol = copySymbolPreservingDefId(
                symbol,
                newType: substituteType(symbol.type, substitution: substitution)
            )
            return .variable(symbol: newSymbol)
            
        case .unionCase(let caseName, let tagIndex, let elements):
            return .unionCase(
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

            
        case .refCount(let val):
            return .refCount(val: substituteTypesInExpression(val, substitution: substitution))
            
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
            
        }
    }
}

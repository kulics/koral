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
            
        case .comparisonExpression(let left, let op, let right, let type):
            return .comparisonExpression(
                left: substituteTypesInExpression(left, substitution: substitution),
                op: op,
                right: substituteTypesInExpression(right, substitution: substitution),
                type: substituteType(type, substitution: substitution)
            )
            
        case .letExpression(let identifier, let value, let body, let type):
            let newIdentifier = Symbol(
                name: identifier.name,
                type: substituteType(identifier.type, substitution: substitution),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
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
            
        case .variable(let identifier):
            var newName = identifier.name
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
                if let template = input.genericTemplates.functionTemplates[identifier.name] {
                    // Calculate the mangled name using the substituted type arguments
                    let typeArgs = template.typeParameters.compactMap { param -> Type? in
                        substitution[param.name]
                    }
                    if typeArgs.count == template.typeParameters.count {
                        let argLayoutKeys = typeArgs.map { $0.layoutKey }.joined(separator: "_")
                        newName = "\(identifier.name)_\(argLayoutKeys)"
                        
                        // Ensure the function is instantiated
                        if !generatedLayouts.contains(newName) && !typeArgs.contains(where: { $0.containsGenericParameter }) {
                            pendingRequests.append(InstantiationRequest(
                                kind: .function(template: template, args: typeArgs),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            }

            
            let newIdentifier = Symbol(
                name: newName,
                type: newType,
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
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

            
            // Apply lowering for primitive type methods (__equals, __compare)
            // This mirrors the lowering done in TypeChecker for direct calls
            if case .methodReference(let base, let method, _, _, _) = newCallee {
                // Intercept Float32/Float64 to_bits intrinsic method
                let methodName = extractMethodName(method.name)
                if methodName == "to_bits" {
                    if base.type == .float32 && newArguments.isEmpty {
                        return .intrinsicCall(.float32Bits(value: base))
                    } else if base.type == .float64 && newArguments.isEmpty {
                        return .intrinsicCall(.float64Bits(value: base))
                    }
                }
                
                // Lower primitive `__equals(self, other) Bool` to scalar equality
                if method.methodKind == .equals,
                   newType == .bool,
                   newArguments.count == 1,
                   base.type == newArguments[0].type,
                   isBuiltinEqualityComparable(base.type)
                {
                    return .comparisonExpression(left: base, op: .equal, right: newArguments[0], type: .bool)
                }
                
                // Lower primitive `__compare(self, other) Int` to scalar comparisons
                if method.methodKind == .compare,
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
            if substitutedTypeArgs.contains(where: { $0.containsGenericParameter }) {
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
                let argLayoutKeys = substitutedTypeArgs.map { $0.layoutKey }.joined(separator: "_")
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
            
            // Fallback: keep as genericCall
            return .genericCall(
                functionName: functionName,
                typeArgs: substitutedTypeArgs,
                arguments: newArguments,
                type: newType
            )

            
        case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, let type):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            var newMethod = Symbol(
                name: method.name,
                type: substituteType(method.type, substitution: substitution),
                kind: method.kind,
                methodKind: method.methodKind,
                modulePath: method.modulePath,
                sourceFile: method.sourceFile,
                access: method.access
            )
            
            // Substitute type args if present
            let substitutedTypeArgs = typeArgs?.map { substituteType($0, substitution: substitution) }
            
            // Substitute method type args if present
            let substitutedMethodTypeArgs = methodTypeArgs?.map { substituteType($0, substitution: substitution) }
            
            // Track the resolved return type (will be updated if we find a concrete method)
            var resolvedReturnType = substituteType(type, substitution: substitution)
            
            // Resolve trait method placeholders to concrete methods
            // Placeholder names have the format "__trait_TraitName_methodName"
            // where methodName may start with underscores (e.g., "__equals")
            if method.name.hasPrefix("__trait_") && !newBase.type.containsGenericParameter {
                // Extract the method name from the placeholder
                // Format: "__trait_TraitName_methodName"
                let prefix = "__trait_"
                let remainder = String(method.name.dropFirst(prefix.count))
                // Find the first underscore that separates trait name from method name
                // The trait name doesn't contain underscores, so we find the first underscore
                if let underscoreIndex = remainder.firstIndex(of: "_") {
                    let methodName = String(remainder[remainder.index(after: underscoreIndex)...])
                    
                    // Look up the concrete method on the substituted base type
                    // Pass methodTypeArgs for generic methods
                    if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: methodName, methodTypeArgs: substitutedMethodTypeArgs ?? []) {
                        newMethod = Symbol(
                            name: concreteMethod.name,
                            type: concreteMethod.type,
                            kind: concreteMethod.kind,
                            methodKind: concreteMethod.methodKind,
                            modulePath: concreteMethod.modulePath,
                            sourceFile: concreteMethod.sourceFile,
                            access: concreteMethod.access
                        )
                        // Extract the return type from the concrete method's function type
                        if case .function(_, let returns) = concreteMethod.type {
                            resolvedReturnType = returns
                        }
                    }
                }
            }

            // Resolve generic extension method to mangled name
            else if !newBase.type.containsGenericParameter {
                // Look up the concrete method on the substituted base type
                // Pass method type args for generic methods
                if let concreteMethod = try? lookupConcreteMethodSymbol(on: newBase.type, name: method.name, methodTypeArgs: substitutedMethodTypeArgs ?? []) {
                    newMethod = Symbol(
                        name: concreteMethod.name,
                        type: concreteMethod.type,
                        kind: concreteMethod.kind,
                        methodKind: concreteMethod.methodKind,
                        modulePath: concreteMethod.modulePath,
                        sourceFile: concreteMethod.sourceFile,
                        access: concreteMethod.access
                    )
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
                methodTypeArgs: substitutedMethodTypeArgs,
                type: resolvedReturnType
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
            var newName = identifier.name
            if case .structure(let decl) = substitutedType {
                let layoutName = decl.name
                let isGenericInstantiation = decl.isGenericInstantiation
                newName = layoutName
                // Trigger instantiation of the concrete type if needed
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !substitutedType.containsGenericParameter {
                    // Find the template and instantiate
                    // Extract base name from the layout name (e.g., "Pair_I_I" -> "Pair")
                    let baseName = layoutName.split(separator: "_").first.map(String.init) ?? layoutName
                    if let template = input.genericTemplates.structTemplates[baseName] {
                        // Extract type args from the substituted type's members
                        // We need to reconstruct the type args from the layout name
                        // For now, we'll add a pending request with the substituted type
                        // The instantiateStruct method will handle the actual instantiation
                        
                        // Parse the layout name to extract type args
                        // Layout name format: "BaseName_Arg1_Arg2_..."
                        let suffix = String(layoutName.dropFirst(baseName.count + 1)) // Remove "BaseName_"
                        let argLayoutKeys = suffix.split(separator: "_").map(String.init)
                        
                        // Try to reconstruct the type args from the layout keys
                        // This is a heuristic - we look for types that match the layout keys
                        var typeArgsReconstructed: [Type] = []
                        for key in argLayoutKeys {
                            if let builtinType = resolveBuiltinType(key) {
                                typeArgsReconstructed.append(builtinType)
                            } else if key == "I" {
                                typeArgsReconstructed.append(.int)
                            } else if key == "R" {
                                typeArgsReconstructed.append(.reference(inner: .int)) // Heuristic
                            } else if key.hasPrefix("Struct_") {
                                // Nested struct - need to look up
                                let nestedDecl = StructDecl(
                                    name: key,
                                    modulePath: [],
                                    sourceFile: "",
                                    access: .default,
                                    members: [],
                                    isGenericInstantiation: true
                                )
                                typeArgsReconstructed.append(.structure(decl: nestedDecl))
                            } else {
                                // Unknown type - use the substituted type's info
                                break
                            }
                        }

                        
                        // If we couldn't reconstruct the type args, try to use the substitution map
                        if typeArgsReconstructed.count != template.typeParameters.count {
                            typeArgsReconstructed = template.typeParameters.compactMap { param in
                                substitution[param.name]
                            }
                        }
                        
                        if typeArgsReconstructed.count == template.typeParameters.count {
                            pendingRequests.append(InstantiationRequest(
                                kind: .structType(template: template, args: typeArgsReconstructed),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            } else if case .union(let decl) = substitutedType {
                let layoutName = decl.name
                let isGenericInstantiation = decl.isGenericInstantiation
                newName = layoutName
                // Similar logic for unions
                if isGenericInstantiation && !generatedLayouts.contains(layoutName) && !substitutedType.containsGenericParameter {
                    let baseName = layoutName.split(separator: "_").first.map(String.init) ?? layoutName
                    if let template = input.genericTemplates.unionTemplates[baseName] {
                        let typeArgsReconstructed: [Type] = template.typeParameters.compactMap { param in
                            substitution[param.name]
                        }
                        
                        if typeArgsReconstructed.count == template.typeParameters.count {
                            pendingRequests.append(InstantiationRequest(
                                kind: .unionType(template: template, args: typeArgsReconstructed),
                                sourceLine: currentLine,
                                sourceFileName: currentFileName
                            ))
                        }
                    }
                }
            }
            
            let newIdentifier = Symbol(
                name: newName,
                type: substitutedType,
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
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
                Symbol(
                    name: sym.name,
                    type: substituteType(sym.type, substitution: substitution),
                    kind: sym.kind,
                    methodKind: sym.methodKind,
                    modulePath: sym.modulePath,
                    sourceFile: sym.sourceFile,
                    access: sym.access
                )
            }
            return .memberPath(
                source: substituteTypesInExpression(source, substitution: substitution),
                path: newPath
            )
            
        case .subscriptExpression(let base, let arguments, let method, let type):
            let newBase = substituteTypesInExpression(base, substitution: substitution)
            var newMethod = Symbol(
                name: method.name,
                type: substituteType(method.type, substitution: substitution),
                kind: method.kind,
                methodKind: method.methodKind,
                modulePath: method.modulePath,
                sourceFile: method.sourceFile,
                access: method.access
            )
            
            // Resolve method name to mangled name for generic extension methods
            if !newBase.type.containsGenericParameter {
                // Look up the concrete method on the substituted base type
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
                Symbol(
                    name: param.name,
                    type: substituteType(param.type, substitution: substitution),
                    kind: param.kind,
                    methodKind: param.methodKind,
                    modulePath: param.modulePath,
                    sourceFile: param.sourceFile,
                    access: param.access
                )
            }
            // Substitute types in captures
            let newCaptures = captures.map { capture in
                CapturedVariable(
                    symbol: Symbol(
                        name: capture.symbol.name,
                        type: substituteType(capture.symbol.type, substitution: substitution),
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
            let newIdentifier = Symbol(
                name: identifier.name,
                type: substituteType(identifier.type, substitution: substitution),
                kind: identifier.kind,
                methodKind: identifier.methodKind,
                modulePath: identifier.modulePath,
                sourceFile: identifier.sourceFile,
                access: identifier.access
            )
            return .variableDeclaration(
                identifier: newIdentifier,
                value: substituteTypesInExpression(value, substitution: substitution),
                mutable: mutable
            )

            
        case .assignment(let target, let value):
            return .assignment(
                target: substituteTypesInExpression(target, substitution: substitution),
                value: substituteTypesInExpression(value, substitution: substitution)
            )
            
        case .compoundAssignment(let target, let op, let value):
            return .compoundAssignment(
                target: substituteTypesInExpression(target, substitution: substitution),
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
            let newSymbol = Symbol(
                name: symbol.name,
                type: substituteType(symbol.type, substitution: substitution),
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
            
        case .ptrInit(let ptr, let val):
            return .ptrInit(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                val: substituteTypesInExpression(val, substitution: substitution)
            )
            
        case .ptrDeinit(let ptr):
            return .ptrDeinit(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .ptrPeek(let ptr):
            return .ptrPeek(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .ptrOffset(let ptr, let offset):
            return .ptrOffset(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                offset: substituteTypesInExpression(offset, substitution: substitution)
            )
            
        case .ptrTake(let ptr):
            return .ptrTake(ptr: substituteTypesInExpression(ptr, substitution: substitution))
            
        case .ptrReplace(let ptr, let val):
            return .ptrReplace(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                val: substituteTypesInExpression(val, substitution: substitution)
            )
            
        case .float32Bits(let value):
            return .float32Bits(value: substituteTypesInExpression(value, substitution: substitution))
            
        case .float64Bits(let value):
            return .float64Bits(value: substituteTypesInExpression(value, substitution: substitution))

        case .float32FromBits(let bits):
            return .float32FromBits(bits: substituteTypesInExpression(bits, substitution: substitution))
            
        case .float64FromBits(let bits):
            return .float64FromBits(bits: substituteTypesInExpression(bits, substitution: substitution))
            
        case .exit(let code):
            return .exit(code: substituteTypesInExpression(code, substitution: substitution))
            
        case .abort:
            return .abort


        // Low-level IO intrinsics (minimal set using file descriptors)
        case .fwrite(let ptr, let len, let fd):
            return .fwrite(
                ptr: substituteTypesInExpression(ptr, substitution: substitution),
                len: substituteTypesInExpression(len, substitution: substitution),
                fd: substituteTypesInExpression(fd, substitution: substitution)
            )
            
        case .fgetc(let fd):
            return .fgetc(fd: substituteTypesInExpression(fd, substitution: substitution))
            
        case .fflush(let fd):
            return .fflush(fd: substituteTypesInExpression(fd, substitution: substitution))
            
        case .ptrBits:
            return .ptrBits
        }
    }
}

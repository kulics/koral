// MonomorphizerTypes.swift
// Extension for Monomorphizer that handles struct and union type instantiation.
// This file contains methods for instantiating generic struct and union templates
// with concrete type arguments.

import Foundation

// MARK: - Type Instantiation Extension

extension Monomorphizer {
    
    // MARK: - Struct Instantiation
    
    /// Instantiates a generic struct template with concrete type arguments.
    /// - Parameters:
    ///   - template: The generic struct template
    ///   - args: The concrete type arguments
    /// - Returns: The instantiated concrete type
    internal func instantiateStruct(template: GenericStructTemplate, args: [Type]) throws -> Type {
        guard template.typeParameters.count == args.count else {
            throw SemanticError.typeMismatch(
                expected: "\(template.typeParameters.count) generic arguments",
                got: "\(args.count)"
            )
        }
        
        // Note: Trait constraints were already validated by TypeChecker at declaration time
        
        // Special case: Pointer<T> maps directly to .pointer(element: T)
        if template.name == "Pointer" {
            return .pointer(element: args[0])
        }
        
        // Check cache
        let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
        if let cached = instantiatedTypes[key] {
            return cached
        }
        
        // Calculate layout name
        let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
        let layoutName = "\(template.name)_\(argLayoutKeys)"
        
        // Create placeholder for recursion detection
        let placeholderDecl = StructDecl(
            name: layoutName,
            defId: getOrAllocateTypeDefId(name: layoutName, kind: .structure),
            modulePath: [],
            sourceFile: "",
            access: .default,
            members: [],
            isGenericInstantiation: true
        )
        let placeholder = Type.structure(decl: placeholderDecl)
        instantiatedTypes[key] = placeholder

        // Resolve members with concrete types
        var resolvedMembers: [(name: String, type: Type, mutable: Bool)] = []
        do {
            // Create type substitution map
            var typeSubstitution: [String: Type] = [:]
            for (i, paramInfo) in template.typeParameters.enumerated() {
                typeSubstitution[paramInfo.name] = args[i]
            }
            
            for param in template.parameters {
                var fieldType = try resolveTypeNode(param.type, substitution: typeSubstitution)
                if fieldType == placeholder {
                    throw SemanticError.invalidOperation(
                        op: "Direct recursion in generic struct \(layoutName) not allowed (use ref)",
                        type1: param.name, type2: "")
                }
                // Resolve any nested genericStruct/genericUnion types
                // This ensures types like List<T ref> get instantiated
                fieldType = resolveParameterizedType(fieldType, visited: [])
                resolvedMembers.append((name: param.name, type: fieldType, mutable: param.mutable))
            }
        } catch {
            instantiatedTypes.removeValue(forKey: key)
            throw error
        }
        
        // Create the concrete type
        let specificDecl = StructDecl(
            name: layoutName,
            defId: getOrAllocateTypeDefId(name: layoutName, kind: .structure),
            modulePath: [],
            sourceFile: "",
            access: .default,
            members: resolvedMembers,
            isGenericInstantiation: true
        )
        let specificType = Type.structure(decl: specificDecl)
        instantiatedTypes[key] = specificType
        layoutToTemplateInfo[layoutName] = (base: template.name, args: args)
        
        // Force instantiate __drop if it exists for this type
        if let methods = input.genericTemplates.extensionMethods[template.name] {
            for entry in methods {
                if entry.method.name == "__drop" {
                    _ = try instantiateExtensionMethodFromEntry(
                        baseType: specificType,
                        structureName: template.name,
                        genericArgs: args,
                        methodTypeArgs: [],
                        methodInfo: entry
                    )
                }
            }
        }
        
        // Skip code generation if type still contains generic parameters
        if specificType.containsGenericParameter {
            return specificType
        }

        // Generate global type declaration if not already generated
        if !generatedLayouts.contains(layoutName) {
            generatedLayouts.insert(layoutName)
            
            // Convert to TypedGlobalNode using resolved members (not canonical)
            // The canonical transformation is only for C type mapping, not for type identity
            let params = resolvedMembers.map { param in
                makeSymbol(
                    name: param.name,
                    type: param.type,
                    kind: param.mutable ? .variable(.MutableValue) : .variable(.Value)
                )
            }
            
            let typeSymbol = makeSymbol(name: layoutName, type: specificType, kind: .type)
            generatedNodes.append(.globalStructDeclaration(identifier: typeSymbol, parameters: params))
        }
        
        return specificType
    }
    
    // MARK: - Union Instantiation
    
    /// Instantiates a generic union template with concrete type arguments.
    /// - Parameters:
    ///   - template: The generic union template
    ///   - args: The concrete type arguments
    /// - Returns: The instantiated concrete type
    internal func instantiateUnion(template: GenericUnionTemplate, args: [Type]) throws -> Type {
        guard template.typeParameters.count == args.count else {
            throw SemanticError.typeMismatch(
                expected: "\(template.typeParameters.count) generic types", got: "\(args.count)")
        }
        
        // Note: Trait constraints were already validated by TypeChecker at declaration time

        // Check cache
        let key = "\(template.name)<\(args.map { $0.description }.joined(separator: ","))>"
        if let existing = instantiatedTypes[key] {
            return existing
        }
        
        // Calculate layout name
        let argLayoutKeys = args.map { $0.layoutKey }.joined(separator: "_")
        let layoutName = "\(template.name)_\(argLayoutKeys)"
        
        // Create placeholder for recursion
        let placeholderDecl = UnionDecl(
            name: layoutName,
            defId: getOrAllocateTypeDefId(name: layoutName, kind: .union),
            modulePath: [],
            sourceFile: "",
            access: .default,
            cases: [],
            isGenericInstantiation: true
        )
        let placeholder = Type.union(decl: placeholderDecl)
        instantiatedTypes[key] = placeholder
        
        // Resolve cases with concrete types
        var resolvedCases: [UnionCase] = []
        do {
            var typeSubstitution: [String: Type] = [:]
            for (i, paramInfo) in template.typeParameters.enumerated() {
                typeSubstitution[paramInfo.name] = args[i]
            }
            
            for c in template.cases {
                var params: [(name: String, type: Type)] = []
                for p in c.parameters {
                    var resolved = try resolveTypeNode(p.type, substitution: typeSubstitution)
                    if resolved == placeholder {
                        throw SemanticError.invalidOperation(
                            op: "Direct recursion in generic union \(layoutName) not allowed (use ref)",
                            type1: p.name, type2: "")
                    }
                    // Resolve any nested genericStruct/genericUnion types
                    // This ensures types like List<Expr ref> get instantiated
                    resolved = resolveParameterizedType(resolved, visited: [])
                    params.append((name: p.name, type: resolved))
                }
                resolvedCases.append(UnionCase(name: c.name, parameters: params))
            }
        } catch {
            instantiatedTypes.removeValue(forKey: key)
            throw error
        }
        
        // Create the concrete type
        let specificDecl = UnionDecl(
            name: layoutName,
            defId: getOrAllocateTypeDefId(name: layoutName, kind: .union),
            modulePath: [],
            sourceFile: "",
            access: .default,
            cases: resolvedCases,
            isGenericInstantiation: true
        )
        let specificType = Type.union(decl: specificDecl)
        instantiatedTypes[key] = specificType
        layoutToTemplateInfo[layoutName] = (base: template.name, args: args)

        // Force instantiate __drop if it exists
        if let methods = input.genericTemplates.extensionMethods[template.name] {
            for entry in methods {
                if entry.method.name == "__drop" {
                    _ = try instantiateExtensionMethodFromEntry(
                        baseType: specificType,
                        structureName: template.name,
                        genericArgs: args,
                        methodTypeArgs: [],
                        methodInfo: entry
                    )
                }
            }
        }
        
        // Skip code generation if type still contains generic parameters
        if specificType.containsGenericParameter {
            return specificType
        }
        
        // Generate global declaration for CodeGen
        if !generatedLayouts.contains(layoutName) {
            generatedLayouts.insert(layoutName)
            
            // Use resolved cases directly (not canonical) for the declaration
            // The canonical transformation is only for C type mapping, not for type identity
            let typeSymbol = makeSymbol(name: layoutName, type: specificType, kind: .type)
            generatedNodes.append(
                .globalUnionDeclaration(identifier: typeSymbol, cases: resolvedCases))
        }
        
        return specificType
    }
}

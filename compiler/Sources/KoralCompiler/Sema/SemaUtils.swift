// SemaUtils.swift
// Shared utility functions used by both TypeChecker and Monomorphizer.
// This file contains common logic that was previously duplicated between the two components.

/// Represents a trait constraint, which can be either a simple trait name or a generic trait.
public enum TraitConstraint: CustomStringConvertible {
    case simple(name: String)
    case generic(base: String, args: [TypeNode])
    
    public var description: String {
        switch self {
        case .simple(let name):
            return name
        case .generic(let base, let args):
            let argsStr = args.map { $0.description }.joined(separator: ", ")
            return "[\(argsStr)]\(base)"
        }
    }
    
    /// Returns the base trait name (e.g., "Iterator" for [T]Iterator)
    public var baseName: String {
        switch self {
        case .simple(let name): return name
        case .generic(let base, _): return base
        }
    }
}

/// Namespace for shared semantic analysis utility functions.
public enum SemaUtils {
    
    // MARK: - Compiler Method Kind Resolution
    
    /// Returns the compiler method kind for a method name.
    /// Used to identify special compiler-recognized methods like __drop, at, etc.
    /// - Parameter name: The method name to check
    /// - Returns: The corresponding CompilerMethodKind
    public static func getCompilerMethodKind(_ name: String) -> CompilerMethodKind {
        switch name {
        case "__drop": return .drop
        default: return .normal
        }
    }
    
    // MARK: - Trait Name Resolution
    
    /// Resolves a trait name from a TypeNode.
    /// - Parameter node: The type node to resolve
    /// - Returns: The trait name as a string
    /// - Throws: SemanticError if the node is not a valid trait identifier
    public static func resolveTraitName(from node: TypeNode) throws -> String {
        switch node {
        case .identifier(let name):
            return name
        case .generic(let base, _):
            // For generic traits like [T]Iterator, return the base name
            return base
        default:
            throw SemanticError.invalidOperation(
                op: "invalid trait bound",
                type1: String(describing: node),
                type2: ""
            )
        }
    }
    
    /// Resolves a trait constraint from a TypeNode, preserving generic type arguments.
    /// - Parameter node: The type node to resolve
    /// - Returns: The trait constraint
    /// - Throws: SemanticError if the node is not a valid trait constraint
    public static func resolveTraitConstraint(from node: TypeNode) throws -> TraitConstraint {
        switch node {
        case .identifier(let name):
            return .simple(name: name)
        case .generic(let base, let args):
            return .generic(base: base, args: args)
        default:
            throw SemanticError.invalidOperation(
                op: "invalid trait bound",
                type1: String(describing: node),
                type2: ""
            )
        }
    }
    
    // MARK: - Built-in Type Checking
    
    /// Checks if a type supports builtin equality comparison.
    /// - Parameter type: The type to check
    /// - Returns: true if the type supports builtin equality comparison
    public static func isBuiltinEqualityComparable(_ type: Type) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64,
             .bool,
             .pointer:
            return true
        default:
            return false
        }
    }
    
    /// Checks if a type supports builtin ordering comparison.
    /// - Parameter type: The type to check
    /// - Returns: true if the type supports builtin ordering comparison
    public static func isBuiltinOrderingComparable(_ type: Type) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64,
             .bool:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Built-in Type Resolution
    
    /// Resolves a built-in type name to its Type.
    /// - Parameter name: The type name to resolve
    /// - Returns: The corresponding Type, or nil if not a built-in type
    public static func resolveBuiltinType(_ name: String) -> Type? {
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
        case "Float32": return .float32
        case "Float64": return .float64
        case "Bool": return .bool
        case "Void": return .void
        default: return nil
        }
    }
    
    // MARK: - Built-in Trait Checking
    
    /// Checks if a trait name is a built-in trait that doesn't require explicit method implementations.
    /// - Parameter name: The trait name to check
    /// - Returns: true if the trait is a built-in trait (Any or Copy)
    public static func isBuiltinTrait(_ name: String) -> Bool {
        return name == "Any" || name == "Copy"
    }
    
    // MARK: - Trait Method Flattening
    
    /// Returns all methods required by a trait, including inherited methods.
    /// This is a pure function that takes the traits dictionary as a parameter.
    /// - Parameters:
    ///   - traitName: The name of the trait
    ///   - traits: Dictionary of trait declarations
    ///   - currentLine: Current source line for error reporting
    /// - Returns: Dictionary mapping method names to their signatures
    /// - Throws: SemanticError if the trait is undefined
    public static func flattenedTraitMethods(
        _ traitName: String,
        traits: [String: TraitDeclInfo],
        currentLine: Int?
    ) throws -> [String: TraitMethodSignature] {
        var visited: Set<String> = []
        return try flattenedTraitMethodsHelper(traitName, traits: traits, visited: &visited, currentLine: currentLine)
    }
    
    /// Helper function for flattenedTraitMethods that tracks visited traits.
    private static func flattenedTraitMethodsHelper(
        _ traitName: String,
        traits: [String: TraitDeclInfo],
        visited: inout Set<String>,
        currentLine: Int?
    ) throws -> [String: TraitMethodSignature] {
        if visited.contains(traitName) {
            return [:]
        }
        visited.insert(traitName)
        
        if isBuiltinTrait(traitName) {
            return [:]
        }
        
        guard let decl = traits[traitName] else {
            throw SemanticError(.generic("Undefined trait: \(traitName)"), line: currentLine)
        }
        
        var methods: [String: TraitMethodSignature] = [:]
        for parent in decl.superTraits {
            let parentMethods = try flattenedTraitMethodsHelper(parent.baseName, traits: traits, visited: &visited, currentLine: currentLine)
            for (name, sig) in parentMethods {
                methods[name] = sig
            }
        }
        for m in decl.methods {
            methods[m.name] = m
        }
        return methods
    }
    
    // MARK: - Trait Validation
    
    /// Validates that a trait name is defined.
    /// - Parameters:
    ///   - name: The trait name to validate
    ///   - traits: Dictionary of trait declarations
    ///   - currentLine: Current source line for error reporting
    /// - Throws: SemanticError if the trait is undefined
    public static func validateTraitName(
        _ name: String,
        traits: [String: TraitDeclInfo],
        currentLine: Int?
    ) throws {
        if isBuiltinTrait(name) {
            return
        }
        if traits[name] == nil {
            throw SemanticError(.generic("Undefined trait: \(name)"), line: currentLine)
        }
    }
    
    // MARK: - Type Substitution
    
    /// Substitutes a type by replacing generic parameters with concrete types.
    /// - Parameters:
    ///   - type: The type to substitute
    ///   - substitution: Map from type parameter names to concrete types
    /// - Returns: The substituted type
    public static func substituteType(_ type: Type, substitution: [String: Type], context: CompilerContext) -> Type {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return type
            
        case .genericParameter(let name):
            return substitution[name] ?? type
            
        case .reference(let inner):
            return .reference(inner: substituteType(inner, substitution: substitution, context: context))
            
        case .pointer(let element):
            return .pointer(element: substituteType(element, substitution: substitution, context: context))
            
        case .weakReference(let inner):
            return .weakReference(inner: substituteType(inner, substitution: substitution, context: context))
            
        case .function(let params, let returns):
            let newParams = params.map { param in
                Parameter(
                    type: substituteType(param.type, substitution: substitution, context: context),
                    kind: param.kind
                )
            }
            return .function(
                parameters: newParams,
                returns: substituteType(returns, substitution: substitution, context: context)
            )
            
        case .structure(let defId):
            let members = context.getStructMembers(defId) ?? []
            let isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
            let newMembers = members.map { member in
                (
                    name: member.name,
                    type: substituteType(member.type, substitution: substitution, context: context),
                    mutable: member.mutable
                )
            }
            let newTypeArguments = context.getTypeArguments(defId)?.map { substituteType($0, substitution: substitution, context: context) }
            context.updateStructInfo(
                defId: defId,
                members: newMembers,
                isGenericInstantiation: isGenericInstantiation,
                typeArguments: newTypeArguments
            )
            return .structure(defId: defId)
            
        case .union(let defId):
            let cases = context.getUnionCases(defId) ?? []
            let isGenericInstantiation = context.isGenericInstantiation(defId) ?? false
            let newCases = cases.map { unionCase in
                UnionCase(
                    name: unionCase.name,
                    parameters: unionCase.parameters.map { param in
                        (name: param.name, type: substituteType(param.type, substitution: substitution, context: context))
                    }
                )
            }
            let newTypeArguments = context.getTypeArguments(defId)?.map { substituteType($0, substitution: substitution, context: context) }
            context.updateUnionInfo(
                defId: defId,
                cases: newCases,
                isGenericInstantiation: isGenericInstantiation,
                typeArguments: newTypeArguments
            )
            return .union(defId: defId)
            
        case .genericStruct(let template, let args):
            let newArgs = args.map { substituteType($0, substitution: substitution, context: context) }
            return .genericStruct(template: template, args: newArgs)
            
        case .genericUnion(let template, let args):
            let newArgs = args.map { substituteType($0, substitution: substitution, context: context) }
            return .genericUnion(template: template, args: newArgs)
            
        case .opaque:
            return type
            
        case .module:
            // Module types should not be substituted
            return type
            
        case .typeVariable:
            // Type variables should not be substituted by generic parameter substitution
            // They are handled by the constraint solver
            return type
        }
    }
    
    /// Resolves a layout key to a built-in type.
    private static func resolveBuiltinTypeFromLayoutKey(_ key: String) -> Type? {
        switch key {
        case "I": return .int
        case "I8": return .int8
        case "I16": return .int16
        case "I32": return .int32
        case "I64": return .int64
        case "U": return .uint
        case "U8": return .uint8
        case "U16": return .uint16
        case "U32": return .uint32
        case "U64": return .uint64
        case "F32": return .float32
        case "F64": return .float64
        case "B": return .bool
        case "V": return .void
        case "N": return .never
        default: return nil
        }
    }
    
    // MARK: - Layout Key Generation
    
    /// Generates a mangled layout name for a generic instantiation.
    /// - Parameters:
    ///   - baseName: The base template name
    ///   - args: The type arguments
    /// - Returns: The mangled layout name
    public static func generateLayoutName(baseName: String, args: [Type]) -> String {
        let argLayoutKeys = args.map { $0.stableKey }.joined(separator: "_")
        return "\(baseName)_\(argLayoutKeys)"
    }
    public static func makeLayoutName(baseName: String, args: [Type], context: CompilerContext) -> String {
        let argLayoutKeys = args.map { context.getLayoutKey($0) }.joined(separator: "_")
        return "\(baseName)_\(argLayoutKeys)"
    }
    
    /// Generates a cache key for a generic instantiation.
    /// - Parameters:
    ///   - baseName: The base template name
    ///   - args: The type arguments
    /// - Returns: The cache key string
    public static func generateCacheKey(baseName: String, args: [Type]) -> String {
        return "\(baseName)<\(args.map { $0.description }.joined(separator: ","))>"
    }
}

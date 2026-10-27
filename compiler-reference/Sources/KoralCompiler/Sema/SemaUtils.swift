// SemaUtils.swift
// Shared utility functions used by both TypeChecker and Monomorphizer.
// This file contains common logic that was previously duplicated between the two components.

// NOTE: The `Bound` (alias `TraitConstraint`) type now lives in `Bound.swift`.

/// Namespace for shared semantic analysis utility functions.
public enum SemaUtils {

    // MARK: - Trait Name Resolution
    
    /// Resolves a trait name from a TypeNode.
    /// - Parameter node: The type node to resolve
    /// - Returns: The trait name as a string
    /// - Throws: SemanticError if the node is not a valid trait identifier
    public static func resolveTraitName(from node: TypeNode) throws -> String {
        switch node {
        case .identifier(let name, _):
            return name
        case .generic(let base, _, _):
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
        case .identifier(let name, _):
            return .trait(defId: .invalid, name: name, args: [])
        case .generic(let base, let args, _):
            return .trait(defId: .invalid, name: base, args: args)
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
             .wrappingInt, .wrappingInt8, .wrappingInt16, .wrappingInt32, .wrappingInt64,
             .wrappingUInt, .wrappingUInt8, .wrappingUInt16, .wrappingUInt32, .wrappingUInt64,
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
             .wrappingInt, .wrappingInt8, .wrappingInt16, .wrappingInt32, .wrappingInt64,
             .wrappingUInt, .wrappingUInt8, .wrappingUInt16, .wrappingUInt32, .wrappingUInt64,
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
        case "Void": return .void
        default: return nil
        }
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
        
        guard let decl = traits[traitName] else {
            let span = currentLine.map { SourceSpan(location: SourceLocation(line: $0, column: 1)) } ?? .unknown
            throw SemanticError(.generic("Undefined trait: \(traitName)"), span: span)
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
    
    /// Returns an ordered list of trait methods for vtable layout.
    /// Parent trait methods come first (in declaration order), then the trait's own methods.
    /// This is a pure function that takes the traits dictionary as a parameter.
    /// - Parameters:
    ///   - traitName: The name of the trait
    ///   - traits: Dictionary of trait declarations
    ///   - currentLine: Current source line for error reporting
    /// - Returns: Ordered array of (name, signature) pairs
    /// - Throws: SemanticError if the trait is undefined
    public static func orderedTraitMethods(
        _ traitName: String,
        traits: [String: TraitDeclInfo],
        currentLine: Int?
    ) throws -> [(name: String, signature: TraitMethodSignature)] {
        var visited: Set<String> = []
        return try orderedTraitMethodsHelper(traitName, traits: traits, visited: &visited, currentLine: currentLine)
    }
    
    private static func orderedTraitMethodsHelper(
        _ traitName: String,
        traits: [String: TraitDeclInfo],
        visited: inout Set<String>,
        currentLine: Int?
    ) throws -> [(name: String, signature: TraitMethodSignature)] {
        if visited.contains(traitName) { return [] }
        visited.insert(traitName)
        
        guard let decl = traits[traitName] else {
            let span = currentLine.map { SourceSpan(location: SourceLocation(line: $0, column: 1)) } ?? .unknown
            throw SemanticError(.generic("Undefined trait: \(traitName)"), span: span)
        }
        
        var result: [(name: String, signature: TraitMethodSignature)] = []
        var seen: Set<String> = []
        
        // Parent trait methods first
        for parent in decl.superTraits {
            let parentMethods = try orderedTraitMethodsHelper(parent.baseName, traits: traits, visited: &visited, currentLine: currentLine)
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
    
    // MARK: - Trait Validation (original)
    
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
        if traits[name] == nil {
            let span = currentLine.map { SourceSpan(location: SourceLocation(line: $0, column: 1)) } ?? .unknown
            throw SemanticError(.generic("Undefined trait: \(name)"), span: span)
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
             .wrappingInt, .wrappingInt8, .wrappingInt16, .wrappingInt32, .wrappingInt64,
             .wrappingUInt, .wrappingUInt8, .wrappingUInt16, .wrappingUInt32, .wrappingUInt64,
             .float32, .float64, .bool, .void, .never:
            return type
            
        case .genericParameter(let name):
            return substitution[name] ?? type
            
        case .reference(let inner):
            return .reference(inner: substituteType(inner, substitution: substitution, context: context))

        case .mutableReference(let inner):
            return .mutableReference(inner: substituteType(inner, substitution: substitution, context: context))

        case .borrowedReference(let inner):
            return .borrowedReference(inner: substituteType(inner, substitution: substitution, context: context))

        case .mutableBorrowedReference(let inner):
            return .mutableBorrowedReference(inner: substituteType(inner, substitution: substitution, context: context))
            
        case .pointer(let element):
            return .pointer(element: substituteType(element, substitution: substitution, context: context))

        case .mutablePointer(let element):
            return .mutablePointer(element: substituteType(element, substitution: substitution, context: context))
            
        case .weakReference(let inner):
            return .weakReference(inner: substituteType(inner, substitution: substitution, context: context))
        case .mutableWeakReference(let inner):
            return .mutableWeakReference(inner: substituteType(inner, substitution: substitution, context: context))
            
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
            
        case .structure:
            // The type IS its DefId; its members are not part of the type
            // expression, so there is nothing here for a substitution to
            // rewrite. Walking into the declaration instead is what made
            // `List.sort_by` over a mutable newtype overflow the compiler's
            // stack: the walk is over the DECLARATION graph, which is cyclic
            // (a nominal whose members reach back to it), and it also wrote
            // substituted members back into the shared context from inside a
            // pure-looking function. Monomorphization concretizes an
            // instantiation's members where that belongs. Same as koralc's
            // `substitute_type`, which never opens a nominal.
            return type

        case .`enum`:
            return type
            
        case .genericStruct(let defId, let args):
            let newArgs = args.map { substituteType($0, substitution: substitution, context: context) }
            return .genericStruct(templateDefId: defId, args: newArgs)
            
        case .genericEnum(let defId, let args):
            let newArgs = args.map { substituteType($0, substitution: substitution, context: context) }
            return .genericEnum(templateDefId: defId, args: newArgs)
            
        case .opaque:
            return type
            
        case .module:
            // Module types should not be substituted
            return type
            
        case .typeVariable:
            // Type variables should not be substituted by generic parameter substitution
            // They are handled by the constraint solver
            return type
            
        case .traitObject(let defId, let typeArgs):
            if typeArgs.isEmpty { return type }
            let newArgs = typeArgs.map { substituteType($0, substitution: substitution, context: context) }
            return .traitObject(traitDefId: defId, typeArgs: newArgs)
        case .error:
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
        case "WI": return .wrappingInt
        case "WI8": return .wrappingInt8
        case "WI16": return .wrappingInt16
        case "WI32": return .wrappingInt32
        case "WI64": return .wrappingInt64
        case "WU": return .wrappingUInt
        case "WU8": return .wrappingUInt8
        case "WU16": return .wrappingUInt16
        case "WU32": return .wrappingUInt32
        case "WU64": return .wrappingUInt64
        case "F32": return .float32
        case "F64": return .float64
        case "B": return .bool
        case "V": return .void
        case "N": return .never
        default: return nil
        }
    }
    
    // MARK: - Layout Key Generation
    
    /// Generates a specialized layout symbol name for a generic instantiation.
    /// - Parameters:
    ///   - baseName: The base template name
    ///   - args: The type arguments
    /// - Returns: The specialized layout symbol name
    public static func generateLayoutName(baseName: String, args: [Type]) -> String {
        let argLayoutKeys = args.map { $0.stableKey }.joined(separator: "_")
        return "\(baseName)_\(argLayoutKeys)"
    }
    public static func makeLayoutName(
        baseName: String,
        args: [Type],
        context: CompilerContext,
        templateDefId: DefId? = nil
    ) -> String {
        let argLayoutKeys = args.map { context.getLayoutKey($0) }.joined(separator: "_")
        // Include the template's declaration identity so same-named generic
        // templates from different modules do not collapse into one layout.
        if let templateDefId, templateDefId.isValid {
            return "\(baseName)_\(argLayoutKeys)_d\(templateDefId.id)"
        }
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

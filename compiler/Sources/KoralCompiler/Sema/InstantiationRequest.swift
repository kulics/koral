// InstantiationRequest.swift
// Defines data structures for recording instantiation requests during type checking.
// These requests are collected by the TypeChecker and processed by the Monomorphizer.

/// The kind of instantiation request, specifying what generic entity needs to be instantiated.
public enum InstantiationKind {
    /// Request to instantiate a generic struct with specific type arguments.
    /// - Parameters:
    ///   - template: The generic struct template to instantiate
    ///   - args: The concrete type arguments to substitute for type parameters
    case structType(template: GenericStructTemplate, args: [Type])
    
    /// Request to instantiate a generic union with specific type arguments.
    /// - Parameters:
    ///   - template: The generic union template to instantiate
    ///   - args: The concrete type arguments to substitute for type parameters
    case unionType(template: GenericUnionTemplate, args: [Type])
    
    /// Request to instantiate a generic function with specific type arguments.
    /// - Parameters:
    ///   - template: The generic function template to instantiate
    ///   - args: The concrete type arguments to substitute for type parameters
    case function(template: GenericFunctionTemplate, args: [Type])
    
    /// Request to instantiate an extension method on a generic type.
    /// - Parameters:
    ///   - baseType: The concrete type on which the method is called
    ///   - templateName: The name of the generic type template (e.g., "List", "Option")
    ///   - typeArgs: The type arguments used to instantiate the base type
    ///   - methodName: The name of the method to instantiate
    case extensionMethod(
        baseType: Type,
        templateName: String,
        typeArgs: [Type],
        methodName: String
    )
}

/// A request to instantiate a generic entity with specific type arguments.
/// These requests are collected during type checking and processed during monomorphization.
public struct InstantiationRequest {
    /// The kind of instantiation (struct, union, function, or extension method)
    public let kind: InstantiationKind
    
    /// The source line where the instantiation was requested, used for error reporting
    public let sourceLine: Int

    /// The source file where the instantiation was requested, used for error reporting
    public let sourceFileName: String
    
    /// Creates a new instantiation request.
    /// - Parameters:
    ///   - kind: The kind of instantiation
    ///   - sourceLine: The source line number (for error reporting)
    ///   - sourceFileName: The source file display name (for error reporting)
    public init(kind: InstantiationKind, sourceLine: Int, sourceFileName: String) {
        self.kind = kind
        self.sourceLine = sourceLine
        self.sourceFileName = sourceFileName
    }
}

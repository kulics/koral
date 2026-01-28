// InstantiationRequest.swift
// Defines data structures for recording instantiation requests during type checking.
// These requests are collected by the TypeChecker and processed by the Monomorphizer.

/// The kind of instantiation request, specifying what generic entity needs to be instantiated.
public enum InstantiationKind: Hashable {
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
    ///   - baseType: The concrete type on which the method is called (genericStruct/genericUnion or concrete)
    ///   - template: The generic extension method template to instantiate
    ///   - typeArgs: The type arguments used to instantiate the base type
    ///   - methodTypeArgs: The type arguments for method-level generic parameters
    case extensionMethod(
        templateName: String,
        baseType: Type,
        template: GenericExtensionMethodTemplate,
        typeArgs: [Type],
        methodTypeArgs: [Type]
    )

    /// Request to instantiate a trait placeholder method on a concrete type.
    /// - Parameters:
    ///   - baseType: The concrete base type the trait method is called on
    ///   - methodName: The trait method name (e.g., "next")
    ///   - methodTypeArgs: The type arguments for method-level generic parameters
    case traitMethod(
        baseType: Type,
        methodName: String,
        methodTypeArgs: [Type]
    )
    
    // MARK: - Hashable conformance
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .structType(let template, let args):
            hasher.combine(0)
            hasher.combine(template.defId.id)
            for arg in args {
                hasher.combine(arg.stableKey)
            }
        case .unionType(let template, let args):
            hasher.combine(1)
            hasher.combine(template.defId.id)
            for arg in args {
                hasher.combine(arg.stableKey)
            }
        case .function(let template, let args):
            hasher.combine(2)
            hasher.combine(template.defId.id)
            for arg in args {
                hasher.combine(arg.stableKey)
            }
        case .extensionMethod(let templateName, _, let template, let typeArgs, let methodTypeArgs):
            hasher.combine(3)
            hasher.combine(templateName)
            hasher.combine(template.method.name)
            for arg in typeArgs {
                hasher.combine(arg.stableKey)
            }
            for arg in methodTypeArgs {
                hasher.combine(arg.stableKey)
            }
        case .traitMethod(let baseType, let methodName, let methodTypeArgs):
            hasher.combine(4)
            hasher.combine(baseType.stableKey)
            hasher.combine(methodName)
            for arg in methodTypeArgs {
                hasher.combine(arg.stableKey)
            }
        }
    }
    
    public static func == (lhs: InstantiationKind, rhs: InstantiationKind) -> Bool {
        switch (lhs, rhs) {
        case (.structType(let lTemplate, let lArgs), .structType(let rTemplate, let rArgs)):
            return lTemplate.defId == rTemplate.defId && lArgs == rArgs
        case (.unionType(let lTemplate, let lArgs), .unionType(let rTemplate, let rArgs)):
            return lTemplate.defId == rTemplate.defId && lArgs == rArgs
        case (.function(let lTemplate, let lArgs), .function(let rTemplate, let rArgs)):
            return lTemplate.defId == rTemplate.defId && lArgs == rArgs
        case (.extensionMethod(let lTemplateName, _, let lTemplate, let lTypeArgs, let lMethodTypeArgs), .extensionMethod(let rTemplateName, _, let rTemplate, let rTypeArgs, let rMethodTypeArgs)):
            return lTemplateName == rTemplateName && lTemplate.method.name == rTemplate.method.name && lTypeArgs == rTypeArgs && lMethodTypeArgs == rMethodTypeArgs
        case (.traitMethod(let lBase, let lName, let lMethodTypeArgs), .traitMethod(let rBase, let rName, let rMethodTypeArgs)):
            return lBase == rBase && lName == rName && lMethodTypeArgs == rMethodTypeArgs
        default:
            return false
        }
    }
}

/// A structured key for deduplicating instantiation requests.
/// Uses template names and type arguments for efficient comparison and hashing.
public enum InstantiationKey: Hashable {
    /// Key for struct type instantiation
    case structType(templateName: String, args: [Type])
    
    /// Key for union type instantiation
    case unionType(templateName: String, args: [Type])
    
    /// Key for function instantiation
    case function(templateName: String, args: [Type])
    
    /// Key for extension method instantiation
    case extensionMethod(templateName: String, methodName: String, typeArgs: [Type], methodTypeArgs: [Type])

    /// Key for trait placeholder method instantiation
    case traitMethod(baseType: Type, methodName: String, methodTypeArgs: [Type])
    
    // MARK: - Hashable conformance
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .structType(let templateName, let args):
            hasher.combine(0)
            hasher.combine(templateName)
            for arg in args {
                hasher.combine(arg.stableKey)
            }
        case .unionType(let templateName, let args):
            hasher.combine(1)
            hasher.combine(templateName)
            for arg in args {
                hasher.combine(arg.stableKey)
            }
        case .function(let templateName, let args):
            hasher.combine(2)
            hasher.combine(templateName)
            for arg in args {
                hasher.combine(arg.stableKey)
            }
        case .extensionMethod(let templateName, let methodName, let typeArgs, let methodTypeArgs):
            hasher.combine(3)
            hasher.combine(templateName)
            hasher.combine(methodName)
            for arg in typeArgs {
                hasher.combine(arg.stableKey)
            }
            for arg in methodTypeArgs {
                hasher.combine(arg.stableKey)
            }
        case .traitMethod(let baseType, let methodName, let methodTypeArgs):
            hasher.combine(4)
            hasher.combine(baseType.stableKey)
            hasher.combine(methodName)
            for arg in methodTypeArgs {
                hasher.combine(arg.stableKey)
            }
        }
    }
    
    public static func == (lhs: InstantiationKey, rhs: InstantiationKey) -> Bool {
        switch (lhs, rhs) {
        case (.structType(let lName, let lArgs), .structType(let rName, let rArgs)):
            return lName == rName && lArgs == rArgs
        case (.unionType(let lName, let lArgs), .unionType(let rName, let rArgs)):
            return lName == rName && lArgs == rArgs
        case (.function(let lName, let lArgs), .function(let rName, let rArgs)):
            return lName == rName && lArgs == rArgs
        case (.extensionMethod(let lTName, let lMName, let lArgs, let lMethodArgs), .extensionMethod(let rTName, let rMName, let rArgs, let rMethodArgs)):
            return lTName == rTName && lMName == rMName && lArgs == rArgs && lMethodArgs == rMethodArgs
        case (.traitMethod(let lBase, let lName, let lMethodArgs), .traitMethod(let rBase, let rName, let rMethodArgs)):
            return lBase == rBase && lName == rName && lMethodArgs == rMethodArgs
        default:
            return false
        }
    }
}

/// A request to instantiate a generic entity with specific type arguments.
/// These requests are collected during type checking and processed during monomorphization.
public struct InstantiationRequest: Hashable {
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
    
    /// Returns a structured key for deduplication.
    /// The key is based on template name and type arguments, ignoring source location.
    public var deduplicationKey: InstantiationKey {
        switch kind {
        case .structType(let template, let args):
            return .structType(templateName: "def#\(template.defId.id)", args: args)
        case .unionType(let template, let args):
            return .unionType(templateName: "def#\(template.defId.id)", args: args)
        case .function(let template, let args):
            return .function(templateName: "def#\(template.defId.id)", args: args)
        case .extensionMethod(let templateName, _, let template, let typeArgs, let methodTypeArgs):
            return .extensionMethod(
                templateName: templateName,
                methodName: template.method.name,
                typeArgs: typeArgs,
                methodTypeArgs: methodTypeArgs
            )
        case .traitMethod(let baseType, let methodName, let methodTypeArgs):
            return .traitMethod(
                baseType: baseType,
                methodName: methodName,
                methodTypeArgs: methodTypeArgs
            )
        }
    }
    
    // MARK: - Hashable conformance (ignores source location)
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
    }
    
    public static func == (lhs: InstantiationRequest, rhs: InstantiationRequest) -> Bool {
        return lhs.kind == rhs.kind
    }
}

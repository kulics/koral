import Foundation

// MARK: - Type Resolution Extension
// This extension contains methods for resolving TypeNode to Type,
// type coercion, and type checking utilities.

extension TypeChecker {
  
  // MARK: - Core Type Resolution
  
  /// 将 TypeNode 解析为语义层 Type，支持函数参数/返回位置的一层 reference(T)
  func resolveTypeNode(_ node: TypeNode) throws -> Type {
    switch node {
    case .identifier(let name):
      if let t = currentScope.resolveType(name, sourceFile: currentSourceFile) {
        return t
      }
      if traits[name] != nil {
        throw SemanticError.invalidOperation(op: "use trait as type", type1: name, type2: "")
      }
      throw SemanticError.undefinedType(name)
    case .inferredSelf:
      guard let t = currentScope.resolveType("Self") else {
        throw SemanticError.undefinedType("Self")
      }
      return t
    case .reference(let inner):
      // 仅支持一层，在 parser 已限制；此处直接映射到 Type.reference
      let base = try resolveTypeNode(inner)
      return .reference(inner: base)
    case .generic(let base, let args):
      if let template = currentScope.lookupGenericStructTemplate(base) {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic arguments",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        
        // Special case: Pointer<T> resolves directly to .pointer(element: T)
        if template.name == "Pointer" {
          return .pointer(element: resolvedArgs[0])
        }
        
        // Build recursion detection key
        let recursionKey = "\(base)<\(resolvedArgs.map { $0.description }.joined(separator: ","))>"
        
        // Check for recursion - if we're already resolving this type, return parameterized type
        // This allows recursive types through ref (e.g., type [T]Node(value T, next ref [T]Node))
        if resolvingGenericTypes.contains(recursionKey) {
          return .genericStruct(template: base, args: resolvedArgs)
        }
        
        // Record instantiation request for deferred monomorphization
        // Skip if any argument contains generic parameters (will be recorded when fully resolved)
        if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
          recordInstantiation(InstantiationRequest(
            kind: .structType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Return parameterized type instead of instantiating
        return .genericStruct(template: base, args: resolvedArgs)
      } else if let template = currentScope.lookupGenericUnionTemplate(base) {
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        
        // Validate type argument count
        guard template.typeParameters.count == resolvedArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic types",
            got: "\(resolvedArgs.count)"
          )
        }
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
        
        // Build recursion detection key
        let recursionKey = "\(base)<\(resolvedArgs.map { $0.description }.joined(separator: ","))>"
        
        // Check for recursion - if we're already resolving this type, return parameterized type
        // This allows recursive types through ref
        if resolvingGenericTypes.contains(recursionKey) {
          return .genericUnion(template: base, args: resolvedArgs)
        }
        
        // Record instantiation request for deferred monomorphization
        // Skip if any argument contains generic parameters (will be recorded when fully resolved)
        if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
          recordInstantiation(InstantiationRequest(
            kind: .unionType(template: template, args: resolvedArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Return parameterized type instead of instantiating
        return .genericUnion(template: base, args: resolvedArgs)
      } else {
        throw SemanticError.undefinedType(base)
      }
    case .functionType(let paramTypes, let returnType):
      // Resolve function type: [ParamType1, ParamType2, ..., ReturnType]Func
      let resolvedParamTypes = try paramTypes.map { try resolveTypeNode($0) }
      let resolvedReturnType = try resolveTypeNode(returnType)
      let parameters = resolvedParamTypes.map { Parameter(type: $0, kind: .byVal) }
      return .function(parameters: parameters, returns: resolvedReturnType)
    }
  }
  
  /// Resolves a TypeNode to a Type using the given substitution map for type parameters.
  func resolveTypeNodeWithSubstitution(_ node: TypeNode, substitution: [String: Type]) throws -> Type {
    switch node {
    case .identifier(let name):
      // Check if it's a type parameter that should be substituted
      if let substitutedType = substitution[name] {
        return substitutedType
      }
      // Otherwise resolve as a regular type
      return try resolveTypeNode(node)
      
    case .generic(let base, let args):
      let resolvedArgs = try args.map { try resolveTypeNodeWithSubstitution($0, substitution: substitution) }
      // Create a generic type
      return .genericStruct(template: base, args: resolvedArgs)
      
    default:
      return try resolveTypeNode(node)
    }
  }
  
  // MARK: - Generic Constraint Enforcement
  
  func enforceGenericConstraints(typeParameters: [TypeParameterDecl], args: [Type]) throws {
    guard typeParameters.count == args.count else { return }
    
    // Build a substitution map from type parameter names to actual types
    var substitution: [String: Type] = [:]
    for (i, param) in typeParameters.enumerated() {
      substitution[param.name] = args[i]
    }
    
    for (i, param) in typeParameters.enumerated() {
      for c in param.constraints {
        let constraint = try SemaUtils.resolveTraitConstraint(from: c)
        
        switch constraint {
        case .simple(let traitName):
          // Simple trait constraint (e.g., T Any, T Equatable)
          // If the argument is a generic parameter, check if it has the required constraint
          // in its bounds rather than checking for concrete method implementations
          if case .genericParameter(let argName) = args[i] {
            // Check if the generic parameter has the required trait bound
            if let bounds = genericTraitBounds[argName] {
              if traitName != "Any" && !bounds.contains(where: { $0.baseName == traitName }) {
                throw SemanticError(.generic(
                  "Generic parameter \(argName) does not have required constraint \(traitName)"
                ), line: currentLine)
              }
            }
            // If bounds exist and contain the trait (or trait is Any), constraint is satisfied
            continue
          }
          
          let ctx = "checking constraint \(param.name): \(traitName)"
          try enforceTraitConformance(args[i], traitName: traitName, context: ctx)
          
        case .generic(let baseTrait, let traitArgs):
          // Generic trait constraint (e.g., R [T]Iterator)
          // We need to check that the actual type implements the trait with the correct type arguments
          
          // First, substitute type parameters in the trait arguments
          let resolvedTraitArgs = try traitArgs.map { arg -> Type in
            try resolveTypeNodeWithSubstitution(arg, substitution: substitution)
          }
          
          // If the argument is a generic parameter, check if it has a matching generic trait bound
          if case .genericParameter(let argName) = args[i] {
            // For now, check if the generic parameter has the base trait bound
            // A more sophisticated check would verify the type arguments match
            if let bounds = genericTraitBounds[argName] {
              if !bounds.contains(where: { $0.baseName == baseTrait }) {
                throw SemanticError(.generic(
                  "Generic parameter \(argName) does not have required constraint \(constraint)"
                ), line: currentLine)
              }
            }
            continue
          }
          
          // For concrete types, check trait conformance with the resolved type arguments
          let ctx = "checking constraint \(param.name): \(constraint)"
          try enforceGenericTraitConformance(args[i], traitName: baseTrait, traitTypeArgs: resolvedTraitArgs, context: ctx)
        }
      }
    }
  }
  
  // MARK: - Trait Conformance
  
  func enforceTraitConformance(
    _ selfType: Type,
    traitName: String,
    context: String? = nil
  ) throws {
    if traitName == "Any" {
      return
    }

    try validateTraitName(traitName)
    let required = try flattenedTraitMethods(traitName)

    var missing: [String] = []
    var mismatched: [String] = []

    for name in required.keys.sorted() {
      guard let sig = required[name] else { continue }
      
      // For generic methods (methods with type parameters), we only check that the method exists
      // We don't check the exact type signature because the method type parameters are not known
      // at trait conformance checking time
      if !sig.typeParameters.isEmpty {
        // Check if the method exists on the type
        let methodExists = try checkMethodExists(on: selfType, name: sig.name)
        if !methodExists {
          let expectedSig = try formatTraitMethodSignature(sig, selfType: selfType)
          missing.append("missing method \(sig.name): expected \(expectedSig)")
        }
        continue
      }
      
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: selfType)
      let expectedSig = try formatTraitMethodSignature(sig, selfType: selfType)

      guard let actualSym = try lookupConcreteMethodSymbol(on: selfType, name: sig.name) else {
        missing.append("missing method \(sig.name): expected \(expectedSig)")
        continue
      }
      if actualSym.type != expectedType {
        mismatched.append(
          "method \(sig.name) has type \(actualSym.type), expected \(expectedType) (expected \(expectedSig))"
        )
      }
    }

    if !missing.isEmpty || !mismatched.isEmpty {
      var msg = "Type \(selfType) does not conform to trait \(traitName)"
      if let context {
        msg += " (\(context))"
      }
      if !missing.isEmpty {
        msg += "\n" + missing.joined(separator: "\n")
      }
      if !mismatched.isEmpty {
        msg += "\n" + mismatched.joined(separator: "\n")
      }
      throw SemanticError(.generic(msg), line: currentLine)
    }
  }
  
  /// Checks if a method exists on a type (without resolving its full type signature).
  /// This is used for generic methods where we can't resolve the full type signature
  /// without knowing the method type arguments.
  func checkMethodExists(on selfType: Type, name: String) throws -> Bool {
    switch selfType {
    case .structure(let decl):
      let typeName = decl.name
      if let methods = extensionMethods[typeName], methods[name] != nil {
        return true
      }
      return false

    case .union(let decl):
      let typeName = decl.name
      if let methods = extensionMethods[typeName], methods[name] != nil {
        return true
      }
      return false
      
    case .genericStruct(let templateName, _):
      if let extensions = genericExtensionMethods[templateName],
         extensions.contains(where: { $0.method.name == name })
      {
        return true
      }
      return false
      
    case .genericUnion(let templateName, _):
      if let extensions = genericExtensionMethods[templateName],
         extensions.contains(where: { $0.method.name == name })
      {
        return true
      }
      return false

    case .pointer(_):
      if let extensions = genericIntrinsicExtensionMethods["Pointer"],
        extensions.contains(where: { $0.method.name == name })
      {
        return true
      }
      if let extensions = genericExtensionMethods["Pointer"],
        extensions.contains(where: { $0.method.name == name })
      {
        return true
      }
      return false

    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64,
      .bool:
      let typeName = selfType.description
      if let methods = extensionMethods[typeName], methods[name] != nil {
        return true
      }
      return false

    default:
      return false
    }
  }

  /// Checks if a type conforms to a generic trait with specific type arguments.
  /// For example, checking if ListIterator conforms to [Int]Iterator.
  /// - Parameters:
  ///   - selfType: The type to check
  ///   - traitName: The trait name (e.g., "Iterator")
  ///   - traitTypeArgs: The type arguments for the trait (e.g., [Int] for [Int]Iterator)
  ///   - context: Optional context string for error messages
  func enforceGenericTraitConformance(
    _ selfType: Type,
    traitName: String,
    traitTypeArgs: [Type],
    context: String? = nil
  ) throws {
    if traitName == "Any" {
      return
    }

    try validateTraitName(traitName)
    
    guard let traitInfo = traits[traitName] else {
      throw SemanticError(.generic("Undefined trait: \(traitName)"), line: currentLine)
    }
    
    // Validate type argument count
    guard traitInfo.typeParameters.count == traitTypeArgs.count else {
      throw SemanticError(.generic(
        "Trait \(traitName) expects \(traitInfo.typeParameters.count) type arguments, got \(traitTypeArgs.count)"
      ), line: currentLine)
    }
    
    // Create type substitution map from trait type parameters to concrete types
    var substitution: [String: Type] = [:]
    for (i, param) in traitInfo.typeParameters.enumerated() {
      substitution[param.name] = traitTypeArgs[i]
    }
    
    let required = try flattenedTraitMethods(traitName)

    var missing: [String] = []
    var mismatched: [String] = []

    for name in required.keys.sorted() {
      guard let sig = required[name] else { continue }
      let expectedType = try expectedFunctionTypeForGenericTraitMethod(sig, selfType: selfType, substitution: substitution)
      let expectedSig = try formatGenericTraitMethodSignature(sig, selfType: selfType, substitution: substitution)

      guard let actualSym = try lookupConcreteMethodSymbol(on: selfType, name: sig.name) else {
        missing.append("missing method \(sig.name): expected \(expectedSig)")
        continue
      }
      if actualSym.type != expectedType {
        mismatched.append(
          "method \(sig.name) has type \(actualSym.type), expected \(expectedType) (expected \(expectedSig))"
        )
      }
    }

    if !missing.isEmpty || !mismatched.isEmpty {
      var msg = "Type \(selfType) does not conform to trait \(traitName)"
      if !traitTypeArgs.isEmpty {
        let argsStr = traitTypeArgs.map { $0.description }.joined(separator: ", ")
        msg = "Type \(selfType) does not conform to trait [\(argsStr)]\(traitName)"
      }
      if let context {
        msg += " (\(context))"
      }
      if !missing.isEmpty {
        msg += "\n" + missing.joined(separator: "\n")
      }
      if !mismatched.isEmpty {
        msg += "\n" + mismatched.joined(separator: "\n")
      }
      throw SemanticError(.generic(msg), line: currentLine)
    }
  }

  /// Computes the expected function type for a generic trait method with type substitution.
  func expectedFunctionTypeForGenericTraitMethod(
    _ method: TraitMethodSignature,
    selfType: Type,
    substitution: [String: Type]
  ) throws -> Type {
    return try withNewScope {
      // Bind Self type
      try currentScope.defineType("Self", type: selfType)
      
      // Bind trait type parameters
      for (name, type) in substitution {
        try currentScope.defineType(name, type: type)
      }
      
      // Bind method-level type parameters as generic parameters
      for typeParam in method.typeParameters {
        try currentScope.defineType(typeParam.name, type: .genericParameter(name: typeParam.name))
      }

      let params: [Parameter] = try method.parameters.map { param in
        let t = try resolveTypeNode(param.type)
        return Parameter(type: t, kind: .byVal)
      }
      let ret = try resolveTypeNode(method.returnType)
      return Type.function(parameters: params, returns: ret)
    }
  }

  /// Formats a generic trait method signature with type substitution for error messages.
  func formatGenericTraitMethodSignature(
    _ method: TraitMethodSignature,
    selfType: Type,
    substitution: [String: Type]
  ) throws -> String {
    return try withNewScope {
      try currentScope.defineType("Self", type: selfType)
      
      for (name, type) in substitution {
        try currentScope.defineType(name, type: type)
      }
      
      // Bind method-level type parameters as generic parameters
      for typeParam in method.typeParameters {
        try currentScope.defineType(typeParam.name, type: .genericParameter(name: typeParam.name))
      }

      let paramsDesc = try method.parameters.map { param -> String in
        let resolvedType = try resolveTypeNode(param.type)
        let mutPrefix = param.mutable ? "mut " : ""
        return "\(mutPrefix)\(param.name) \(resolvedType)"
      }.joined(separator: ", ")

      let ret = try resolveTypeNode(method.returnType)
      return "\(method.name)(\(paramsDesc)) \(ret)"
    }
  }
  
  /// Enforces that a type conforms to a generic trait with specific type arguments.
  func enforceGenericTraitConformanceForIterable(_ type: Type, traitName: String, traitArgs: [Type], context: String) throws {
    // For generic traits like [T]Iterator, we need to check:
    // 1. The type has a `next` method (for Iterator)
    // 2. The return type matches [T]Option where T is the expected element type
    
    // Get the trait methods
    let traitMethods = try flattenedTraitMethods(traitName)
    
    // For each method in the trait, check if the type implements it with correct types
    for (methodName, _) in traitMethods {
      // Look up the method on the type
      let structType: Type
      if case .reference(let inner) = type { structType = inner } else { structType = type }
      
      // Try to find the method using extensionMethods dictionary
      var methodFound = false
      
      switch structType {
      case .structure(let decl):
        if let methods = extensionMethods[decl.name], methods[methodName] != nil {
          methodFound = true
        }
      case .genericStruct(let template, _):
        // For generic structs, check if there's a generic extension method
        if let extensions = genericExtensionMethods[template],
           extensions.contains(where: { $0.method.name == methodName }) {
          methodFound = true
        }
      default:
        break
      }
      
      if !methodFound {
        throw SemanticError(.generic(
          "Type \(type) does not implement method '\(methodName)' required by trait \(traitName)"
        ), line: currentLine)
      }
    }
  }
  
  // MARK: - Type Checking Utilities
  
  func isIntegerType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  func isFloatType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64:
      return true
    default:
      return false
    }
  }

  func isStringType(_ type: Type) -> Bool {
    switch type {
    case .structure(let decl):
      return decl.name == "String"
    default:
      return false
    }
  }
  
  func singleByteASCII(from value: String) -> UInt8? {
    let bytes = Array(value.utf8)
    guard bytes.count == 1 else { return nil }
    guard bytes[0] <= 0x7F else { return nil }
    return bytes[0]
  }

  // Coerce numeric literals to the expected numeric type for annotations/parameters.
  func coerceLiteral(_ expr: TypedExpressionNode, to expected: Type) -> TypedExpressionNode
  {
    if isIntegerType(expected) {
      if case .integerLiteral(let value, _) = expr {
        return .integerLiteral(value: value, type: expected)
      }

      // Allow "a" / 'a' (post-escape, single-byte ASCII) to coerce to UInt8.
      if expected == .uint8, case .stringLiteral(let value, _) = expr {
        if let b = singleByteASCII(from: value) {
          return .integerLiteral(value: String(b), type: .uint8)
        }
      }
    }
    if isFloatType(expected) {
      if case .floatLiteral(let value, _) = expr {
        return .floatLiteral(value: value, type: expected)
      }
    }
    return expr
  }
}

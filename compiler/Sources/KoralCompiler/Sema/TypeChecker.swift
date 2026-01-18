public class TypeChecker {
  // Store type information for variables and functions
  private var currentScope: Scope = Scope()
  private let ast: ASTNode
  // TypeName -> MethodName -> MethodSymbol
  private var extensionMethods: [String: [String: Symbol]] = [:]

  private var traits: [String: TraitDeclInfo] = [:]

  // Generic parameter name -> list of trait bounds currently in scope
  private var genericTraitBounds: [String: [String]] = [:]

  // Generic Template Extensions: TemplateName -> [GenericExtensionMethodTemplate]
  private var genericExtensionMethods: [String: [GenericExtensionMethodTemplate]] = [:]
  private var genericIntrinsicExtensionMethods:
    [String: [(typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)]] =
      [:]

  // Instantiation requests collected during type checking (for deferred monomorphization)
  private var instantiationRequests: Set<InstantiationRequest> = []
  
  // Stack of generic types currently being resolved (for recursion detection)
  private var resolvingGenericTypes: Set<String> = []
  
  // Sets to track intrinsic generic types and functions for special handling during monomorphization
  private var intrinsicGenericTypes: Set<String> = []
  private var intrinsicGenericFunctions: Set<String> = []

  private var currentLine: Int = 1 {
    didSet {
      SemanticErrorContext.currentLine = currentLine
    }
  }
  private var currentFileName: String {
    didSet {
      SemanticErrorContext.currentFileName = currentFileName
    }
  }

  // File mapping for diagnostics (since stdlib globals are prepended)
  private let coreGlobalCount: Int
  private let coreFileName: String
  private let userFileName: String
  private var currentFunctionReturnType: Type?
  private var loopDepth: Int = 0

  private var synthesizedTempIndex: Int = 0

  public init(
    ast: ASTNode,
    coreGlobalCount: Int = 0,
    coreFileName: String = "std/core.koral",
    userFileName: String = "<input>"
  ) {
    self.ast = ast
    self.coreGlobalCount = max(0, coreGlobalCount)
    self.coreFileName = coreFileName
    self.userFileName = userFileName
    self.currentFileName = userFileName
    SemanticErrorContext.currentFileName = userFileName
    SemanticErrorContext.currentLine = 1
  }

  private func builtinStringType() -> Type {
    if let stringType = currentScope.lookupType("String") {
      return stringType
    }
    // Fallback: std should normally define `type String(...)`.
    return .structure(name: "String", members: [], isGenericInstantiation: false)
  }

  // Wrapper for shared utility function from SemaUtils.swift
  private func getCompilerMethodKind(_ name: String) -> CompilerMethodKind {
    return SemaUtils.getCompilerMethodKind(name)
  }

  private func isBuiltinEqualityComparable(_ type: Type) -> Bool {
    return SemaUtils.isBuiltinEqualityComparable(type)
  }

  private func isBuiltinOrderingComparable(_ type: Type) -> Bool {
    return SemaUtils.isBuiltinOrderingComparable(type)
  }

  private func isIntegerScalarType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  private func isSignedIntegerScalarType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64:
      return true
    default:
      return false
    }
  }

  private func isUnsignedIntegerScalarType(_ type: Type) -> Bool {
    switch type {
    case .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  private func isFloatScalarType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64:
      return true
    default:
      return false
    }
  }

  private func isValidExplicitCast(from: Type, to: Type) -> Bool {
    if from == to { return true }

    // Numeric casts (ints <-> ints/uints/floats and floats <-> ints/uints/floats).
    if (isIntegerScalarType(from) || isFloatScalarType(from)) && (isIntegerScalarType(to) || isFloatScalarType(to)) {
      return true
    }

    // Pointer casts.
    if case .pointer = from {
      if case .pointer = to { return true }
      if to == .int || to == .uint { return true }
    }
    if case .pointer = to {
      if from == .int || from == .uint { return true }
    }

    return false
  }

  private func withTempIfRValue(
    _ expr: TypedExpressionNode,
    prefix: String,
    _ body: (TypedExpressionNode) throws -> TypedExpressionNode
  ) rethrows -> TypedExpressionNode {
    if expr.valueCategory == .lvalue {
      return try body(expr)
    }
    let sym = nextSynthSymbol(prefix: prefix, type: expr.type)
    let varExpr: TypedExpressionNode = .variable(identifier: sym)
    let inner = try body(varExpr)
    return .letExpression(identifier: sym, value: expr, body: inner, type: inner.type)
  }

  private func ensureBorrowed(_ expr: TypedExpressionNode, expected: Type) throws -> TypedExpressionNode {
    if expr.type == expected {
      return expr
    }
    if case .reference(let inner) = expected, expr.type == inner {
      if expr.valueCategory == .lvalue {
        return .referenceExpression(expression: expr, type: expected)
      }
      throw SemanticError.invalidOperation(op: "implicit ref", type1: expr.type.description, type2: "rvalue")
    }
    throw SemanticError.typeMismatch(expected: expected.description, got: expr.type.description)
  }

  private func buildEqualsCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    let methodName = "__equals"
    let receiverType = lhs.type

    let methodSym: Symbol
    if case .genericParameter(let paramName) = receiverType {
      guard hasTraitBound(paramName, "Equatable") else {
        throw SemanticError(.generic("Type \(receiverType) is not constrained by trait Equatable"), line: currentLine)
      }
      let methods = try flattenedTraitMethods("Equatable")
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait Equatable is missing required method \(methodName)"), line: currentLine)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)
      methodSym = Symbol(
        name: "__trait_Equatable_\(methodName)",
        type: expectedType,
        kind: .function,
        methodKind: .equals
      )
    } else {
      guard let concrete = try lookupConcreteMethodSymbol(on: receiverType, name: methodName) else {
        throw SemanticError.undefinedMember(methodName, receiverType.description)
      }
      methodSym = concrete
    }

    guard case .function(let params, let returns) = methodSym.type else {
      throw SemanticError.invalidOperation(op: "call", type1: methodSym.type.description, type2: "")
    }
    if params.count != 2 {
      throw SemanticError.invalidArgumentCount(function: methodName, expected: max(0, params.count - 1), got: 1)
    }
    if returns != .bool {
      throw SemanticError.typeMismatch(expected: "Bool", got: returns.description)
    }

    // Value-passing semantics: pass lhs and rhs directly
    let callee: TypedExpressionNode = .methodReference(base: lhs, method: methodSym, typeArgs: nil, type: methodSym.type)
    return .call(callee: callee, arguments: [rhs], type: .bool)
  }

  private func buildCompareCall(lhs: TypedExpressionNode, rhs: TypedExpressionNode) throws -> TypedExpressionNode {
    guard lhs.type == rhs.type else {
      throw SemanticError.typeMismatch(expected: lhs.type.description, got: rhs.type.description)
    }

    let methodName = "__compare"
    let receiverType = lhs.type

    let methodSym: Symbol
    if case .genericParameter(let paramName) = receiverType {
      guard hasTraitBound(paramName, "Comparable") else {
        throw SemanticError(.generic("Type \(receiverType) is not constrained by trait Comparable"), line: currentLine)
      }
      let methods = try flattenedTraitMethods("Comparable")
      guard let sig = methods[methodName] else {
        throw SemanticError(.generic("Trait Comparable is missing required method \(methodName)"), line: currentLine)
      }
      let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: receiverType)
      methodSym = Symbol(
        name: "__trait_Comparable_\(methodName)",
        type: expectedType,
        kind: .function,
        methodKind: .compare
      )
    } else {
      guard let concrete = try lookupConcreteMethodSymbol(on: receiverType, name: methodName) else {
        throw SemanticError.undefinedMember(methodName, receiverType.description)
      }
      methodSym = concrete
    }

    guard case .function(let params, let returns) = methodSym.type else {
      throw SemanticError.invalidOperation(op: "call", type1: methodSym.type.description, type2: "")
    }
    if params.count != 2 {
      throw SemanticError.invalidArgumentCount(function: methodName, expected: max(0, params.count - 1), got: 1)
    }
    if returns != .int {
      throw SemanticError.typeMismatch(expected: "Int", got: returns.description)
    }

    // Value-passing semantics: pass lhs and rhs directly
    let callee: TypedExpressionNode = .methodReference(base: lhs, method: methodSym, typeArgs: nil, type: methodSym.type)
    return .call(callee: callee, arguments: [rhs], type: .int)
  }

  private func nextSynthSymbol(prefix: String, type: Type) -> Symbol {
    synthesizedTempIndex += 1
    return Symbol(
      name: "__koral_\(prefix)_\(synthesizedTempIndex)",
      type: type,
      kind: .variable(.Value)
    )
  }

  /// 为方法调用创建临时物化
  /// 当 base 是右值且方法期望 `self ref` 时，生成 letExpression 包装临时变量和方法调用
  /// 
  /// 例如：`"hello".count_byte()` 转换为：
  /// ```
  /// letExpression(
  ///   identifier: __koral_temp_recv_1,
  ///   value: "hello",
  ///   body: call(
  ///     callee: methodReference(
  ///       base: referenceExpression(variable(__koral_temp_recv_1)),
  ///       method: count_byte
  ///     ),
  ///     arguments: []
  ///   )
  /// )
  /// ```
  private func materializeTemporaryForMethodCall(
    base: TypedExpressionNode,
    method: Symbol,
    methodType: Type,
    params: [Parameter],
    returns: Type,
    arguments: [ExpressionNode]
  ) throws -> TypedExpressionNode {
    // 1. 创建临时变量符号
    let tempSymbol = nextSynthSymbol(prefix: "temp_recv", type: base.type)
    
    // 2. 创建临时变量表达式（这是一个 lvalue）
    let tempVar: TypedExpressionNode = .variable(identifier: tempSymbol)
    
    // 3. 创建引用表达式（对临时变量取引用）
    let refType: Type = .reference(inner: base.type)
    let refExpr: TypedExpressionNode = .referenceExpression(expression: tempVar, type: refType)
    
    // 4. 创建方法引用
    let finalCallee: TypedExpressionNode = .methodReference(
      base: refExpr, method: method, typeArgs: nil, type: methodType)
    
    // 5. 处理方法参数
    var typedArguments: [TypedExpressionNode] = []
    for (arg, param) in zip(arguments, params.dropFirst()) {
      var typedArg = try inferTypedExpression(arg)
      typedArg = coerceLiteral(typedArg, to: param.type)
      if typedArg.type != param.type {
        // Try implicit ref/deref for arguments as well (mirrors self handling).
        if case .reference(let inner) = param.type, inner == typedArg.type {
          if typedArg.valueCategory == .lvalue {
            typedArg = .referenceExpression(expression: typedArg, type: param.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = typedArg.type, inner == param.type {
          typedArg = .derefExpression(expression: typedArg, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: param.type.description,
            got: typedArg.type.description
          )
        }
      }
      typedArguments.append(typedArg)
    }
    
    // 6. 创建方法调用
    let call: TypedExpressionNode = .call(callee: finalCallee, arguments: typedArguments, type: returns)
    
    // 7. 包装在 letExpression 中
    return .letExpression(identifier: tempSymbol, value: base, body: call, type: returns)
  }

  /// Records an instantiation request for deferred monomorphization.
  /// This method collects all generic instantiation points during type checking
  /// so they can be processed later by the Monomorphizer.
  private func recordInstantiation(_ request: InstantiationRequest) {
    instantiationRequests.insert(request)
  }

  // Wrapper for shared utility function from SemaUtils.swift
  private func resolveTraitName(from node: TypeNode) throws -> String {
    return try SemaUtils.resolveTraitName(from: node)
  }

  private func validateTraitName(_ name: String) throws {
    try SemaUtils.validateTraitName(name, traits: traits, currentLine: currentLine)
  }

  private func flattenedTraitMethods(_ traitName: String) throws -> [String: TraitMethodSignature] {
    return try SemaUtils.flattenedTraitMethods(traitName, traits: traits, currentLine: currentLine)
  }

  private func recordGenericTraitBounds(_ typeParameters: [TypeParameterDecl]) throws {
    for param in typeParameters {
      let bounds = try param.constraints.map { try resolveTraitName(from: $0) }
      for b in bounds {
        try validateTraitName(b)
      }
      genericTraitBounds[param.name] = bounds
    }
  }
  
  /// Checks if a type parameter has a trait bound, including inherited traits.
  /// For example, if K has bound HashKey and HashKey extends Equatable,
  /// then hasTraitBound("K", "Equatable") returns true.
  private func hasTraitBound(_ paramName: String, _ traitName: String) -> Bool {
    guard let bounds = genericTraitBounds[paramName] else {
      return false
    }
    
    // Check direct bounds
    if bounds.contains(traitName) {
      return true
    }
    
    // Check inherited traits
    for bound in bounds {
      if let traitInfo = traits[bound] {
        // Check if this trait inherits from the target trait
        if traitInfo.superTraits.contains(traitName) {
          return true
        }
        // Recursively check super traits
        for superTrait in traitInfo.superTraits {
          if hasTraitInheritance(superTrait, traitName) {
            return true
          }
        }
      }
    }
    
    return false
  }
  
  /// Checks if a trait inherits from another trait (directly or transitively).
  private func hasTraitInheritance(_ traitName: String, _ targetTrait: String) -> Bool {
    if traitName == targetTrait {
      return true
    }
    
    guard let traitInfo = traits[traitName] else {
      return false
    }
    
    if traitInfo.superTraits.contains(targetTrait) {
      return true
    }
    
    for superTrait in traitInfo.superTraits {
      if hasTraitInheritance(superTrait, targetTrait) {
        return true
      }
    }
    
    return false
  }

  private func expectedFunctionTypeForTraitMethod(
    _ method: TraitMethodSignature,
    selfType: Type
  ) throws -> Type {
    return try withNewScope {
      // Bind both `Self` and inferred self placeholder.
      try currentScope.defineType("Self", type: selfType)

      let params: [Parameter] = try method.parameters.map { param in
        let t = try resolveTypeNode(param.type)
        return Parameter(type: t, kind: .byVal)
      }
      let ret = try resolveTypeNode(method.returnType)
      return Type.function(parameters: params, returns: ret)
    }
  }

  private func formatTraitMethodSignature(
    _ method: TraitMethodSignature,
    selfType: Type
  ) throws -> String {
    return try withNewScope {
      try currentScope.defineType("Self", type: selfType)

      let paramsDesc = try method.parameters.map { param -> String in
        let resolvedType = try resolveTypeNode(param.type)
        let mutPrefix = param.mutable ? "mut " : ""
        return "\(mutPrefix)\(param.name) \(resolvedType)"
      }.joined(separator: ", ")

      let ret = try resolveTypeNode(method.returnType)
      return "\(method.name)(\(paramsDesc)) \(ret)"
    }
  }

  private func lookupConcreteMethodSymbol(on selfType: Type, name: String) throws -> Symbol? {
    switch selfType {
    case .structure(let typeName, _, _):
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      return nil

    case .union(let typeName, _, _):
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      return nil
      
    case .genericStruct(let templateName, let args):
      // Look up method on generic struct template
      if let extensions = genericExtensionMethods[templateName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: templateName,
          typeArgs: args,
          methodInfo: ext
        )
      }
      return nil
      
    case .genericUnion(let templateName, let args):
      // Look up method on generic union template
      if let extensions = genericExtensionMethods[templateName],
         let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: templateName,
          typeArgs: args,
          methodInfo: ext
        )
      }
      return nil

    case .pointer(let element):
      if let extensions = genericIntrinsicExtensionMethods["Pointer"],
        let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveIntrinsicExtensionMethod(
          baseType: selfType,
          templateName: "Pointer",
          typeArgs: [element],
          methodInfo: ext
        )
      }

      if let extensions = genericExtensionMethods["Pointer"],
        let ext = extensions.first(where: { $0.method.name == name })
      {
        return try resolveGenericExtensionMethod(
          baseType: selfType,
          templateName: "Pointer",
          typeArgs: [element],
          methodInfo: ext
        )
      }
      return nil

    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64,
      .float32, .float64,
      .bool:
      let typeName = selfType.description
      if let methods = extensionMethods[typeName], let sym = methods[name] {
        return sym
      }
      return nil

    default:
      return nil
    }
  }
  
  /// Resolves a generic extension method without instantiating it.
  /// Returns a symbol with the substituted function type and records an instantiation request.
  private func resolveGenericExtensionMethod(
    baseType: Type,
    templateName: String,
    typeArgs: [Type],
    methodInfo: GenericExtensionMethodTemplate
  ) throws -> Symbol {
    let typeParams = methodInfo.typeParams
    let method = methodInfo.method
    
    guard typeParams.count == typeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(typeParams.count) type arguments",
        got: "\(typeArgs.count)"
      )
    }
    
    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in typeParams.enumerated() {
      substitution[param.name] = typeArgs[i]
    }
    substitution["Self"] = baseType
    
    // Resolve function type with substitution
    let functionType = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      
      let returnType = try resolveTypeNode(method.returnType)
      let params = try method.parameters.map { param -> Parameter in
        let paramType = try resolveTypeNode(param.type)
        return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
      }
      
      return Type.function(parameters: params, returns: returnType)
    }
    
    // Record instantiation request if type args are concrete
    if !typeArgs.contains(where: { $0.containsGenericParameter }) {
      recordInstantiation(InstantiationRequest(
        kind: .extensionMethod(
          baseType: baseType,
          template: methodInfo,
          typeArgs: typeArgs
        ),
        sourceLine: currentLine,
        sourceFileName: currentFileName
      ))
    }
    
    let kind = getCompilerMethodKind(method.name)
    return Symbol(name: method.name, type: functionType, kind: .function, methodKind: kind)
  }
  
  /// Resolves an intrinsic extension method without instantiating it.
  private func resolveIntrinsicExtensionMethod(
    baseType: Type,
    templateName: String,
    typeArgs: [Type],
    methodInfo: (typeParams: [TypeParameterDecl], method: IntrinsicMethodDeclaration)
  ) throws -> Symbol {
    let (typeParams, method) = methodInfo
    
    guard typeParams.count == typeArgs.count else {
      throw SemanticError.typeMismatch(
        expected: "\(typeParams.count) type arguments",
        got: "\(typeArgs.count)"
      )
    }
    
    // Create type substitution map
    var substitution: [String: Type] = [:]
    for (i, param) in typeParams.enumerated() {
      substitution[param.name] = typeArgs[i]
    }
    substitution["Self"] = baseType
    
    // Resolve function type with substitution
    let functionType = try withNewScope {
      for (paramName, paramType) in substitution {
        try currentScope.defineType(paramName, type: paramType)
      }
      
      let returnType = try resolveTypeNode(method.returnType)
      let params = try method.parameters.map { param -> Parameter in
        let paramType = try resolveTypeNode(param.type)
        return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
      }
      
      return Type.function(parameters: params, returns: returnType)
    }
    
    let kind = getCompilerMethodKind(method.name)
    return Symbol(name: method.name, type: functionType, kind: .function, methodKind: kind)
  }

  private func enforceTraitConformance(
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

  /// Checks if a type conforms to a generic trait with specific type arguments.
  /// For example, checking if ListIterator conforms to [Int]Iterator.
  /// - Parameters:
  ///   - selfType: The type to check
  ///   - traitName: The trait name (e.g., "Iterator")
  ///   - traitTypeArgs: The type arguments for the trait (e.g., [Int] for [Int]Iterator)
  ///   - context: Optional context string for error messages
  private func enforceGenericTraitConformance(
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
  private func expectedFunctionTypeForGenericTraitMethod(
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

      let params: [Parameter] = try method.parameters.map { param in
        let t = try resolveTypeNode(param.type)
        return Parameter(type: t, kind: .byVal)
      }
      let ret = try resolveTypeNode(method.returnType)
      return Type.function(parameters: params, returns: ret)
    }
  }

  /// Formats a generic trait method signature with type substitution for error messages.
  private func formatGenericTraitMethodSignature(
    _ method: TraitMethodSignature,
    selfType: Type,
    substitution: [String: Type]
  ) throws -> String {
    return try withNewScope {
      try currentScope.defineType("Self", type: selfType)
      
      for (name, type) in substitution {
        try currentScope.defineType(name, type: type)
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

  private func enforceGenericConstraints(typeParameters: [TypeParameterDecl], args: [Type]) throws {
    guard typeParameters.count == args.count else { return }
    for (i, param) in typeParameters.enumerated() {
      for c in param.constraints {
        let traitName = try resolveTraitName(from: c)
        
        // If the argument is a generic parameter, check if it has the required constraint
        // in its bounds rather than checking for concrete method implementations
        if case .genericParameter(let argName) = args[i] {
          // Check if the generic parameter has the required trait bound
          if let bounds = genericTraitBounds[argName] {
            if traitName != "Any" && !bounds.contains(traitName) {
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
      }
    }
  }

  private func resolveSubscriptUpdateMethod(
    base: TypedExpressionNode,
    args: [TypedExpressionNode]
  ) throws -> (method: Symbol, finalBase: TypedExpressionNode, valueType: Type) {
    let methodName = "__update_at"
    let type = base.type

    // Unwrap reference for method lookup
    let structType: Type
    if case .reference(let inner) = type { structType = inner } else { structType = type }

    // Get the type name for error messages
    let typeName: String
    switch structType {
    case .structure(let name, _, _):
      typeName = name
    case .genericStruct(let template, _):
      typeName = template
    default:
      throw SemanticError.invalidOperation(op: "subscript", type1: type.description, type2: "")
    }

    var methodSymbol: Symbol? = nil
    
    // Try to look up method on concrete type first
    if case .structure(let name, _, _) = structType {
      if let extensions = extensionMethods[name], let sym = extensions[methodName] {
        methodSymbol = sym
      }
    }
    
    // If not found, try generic type lookup
    if methodSymbol == nil {
      if case .genericStruct(let templateName, let args) = structType {
        if let extensions = genericExtensionMethods[templateName],
           let ext = extensions.first(where: { $0.method.name == methodName })
        {
          methodSymbol = try resolveGenericExtensionMethod(
            baseType: structType,
            templateName: templateName,
            typeArgs: args,
            methodInfo: ext
          )
        }
      }
    }

    guard let method = methodSymbol else {
      throw SemanticError.undefinedMember(methodName, typeName)
    }
    guard case .function(let params, let returns) = method.type else { fatalError() }

    if returns != .void {
      throw SemanticError.typeMismatch(expected: "Void", got: returns.description)
    }

    let expectedIndexArgCount = params.count - 2  // excluding self + value
    if args.count != expectedIndexArgCount {
      throw SemanticError.invalidArgumentCount(
        function: methodName, expected: expectedIndexArgCount, got: args.count)
    }

    // Adjust base for self param (implicit ref/deref rules)
    var finalBase = base
    if let firstParam = params.first {
      if firstParam.type != base.type {
        if case .reference(let inner) = firstParam.type, inner == base.type {
          // Implicit Ref for self requires an addressable base
          if base.valueCategory == .lvalue {
            finalBase = .referenceExpression(expression: base, type: firstParam.type)
          } else {
            throw SemanticError.invalidOperation(
              op: "implicit ref", type1: base.type.description, type2: "rvalue")
          }
        } else if case .reference(let inner) = base.type, inner == firstParam.type {
          // Implicit deref: only safe for Copy
          finalBase = .derefExpression(expression: base, type: inner)
        } else {
          throw SemanticError.typeMismatch(
            expected: firstParam.type.description, got: base.type.description)
        }
      }
    }

    // Check index argument types (exclude last param, which is value)
    if params.count >= 2 {
      let indexParams = params.dropFirst().dropLast()
      for (arg, param) in zip(args, indexParams) {
        if arg.type != param.type {
          throw SemanticError.typeMismatch(
            expected: param.type.description, got: arg.type.description)
        }
      }
    }

    let valueType = params.last!.type
    return (method: method, finalBase: finalBase, valueType: valueType)
  }

  /// Performs type checking on the AST and returns the TypeCheckerOutput.
  /// The output contains:
  /// - The typed program with all declarations type-checked
  /// - The collected instantiation requests for deferred monomorphization
  /// - The registry of generic templates for the Monomorphizer
  public func check() throws -> TypeCheckerOutput {
    switch self.ast {
    case .program(let declarations):
      var typedDeclarations: [TypedGlobalNode] = []
      // Clear any previous state
      instantiationRequests.removeAll()

      // === PASS 1: Collect all type definitions ===
      // This pass registers all types, traits, and function signatures
      // so that forward references work correctly
      for (index, decl) in declarations.enumerated() {
        self.currentFileName = (index < coreGlobalCount) ? coreFileName : userFileName
        self.currentLine = decl.line
        do {
          try collectTypeDefinition(decl)
        } catch let e as SemanticError {
          throw e
        }
      }
      
      // === PASS 2: Register all given method signatures ===
      // This allows methods in one given block to call methods in another given block
      // regardless of declaration order
      for (index, decl) in declarations.enumerated() {
        self.currentFileName = (index < coreGlobalCount) ? coreFileName : userFileName
        self.currentLine = decl.line
        do {
          try collectGivenSignatures(decl)
        } catch let e as SemanticError {
          throw e
        }
      }
      
      // === PASS 3: Check function bodies and generate typed AST ===
      // Now that all types and method signatures are defined, we can check function bodies
      // which may reference types or methods defined later in the file
      for (index, decl) in declarations.enumerated() {
        self.currentFileName = (index < coreGlobalCount) ? coreFileName : userFileName
        self.currentLine = decl.line
        do {
          if let typedDecl = try checkGlobalDeclaration(decl) {
            typedDeclarations.append(typedDecl)
          }
        } catch let e as SemanticError {
          throw e
        }
      }
      
      // Build the typed program
      let program = TypedProgram.program(globalNodes: typedDeclarations)
      
      // Build the generic template registry
      // Separate concrete types into structs and unions
      let allConcreteTypes = currentScope.getAllConcreteTypes()
      var concreteStructs: [String: Type] = [:]
      var concreteUnions: [String: Type] = [:]
      for (name, type) in allConcreteTypes {
        switch type {
        case .structure:
          concreteStructs[name] = type
        case .union:
          concreteUnions[name] = type
        default:
          break
        }
      }
      
      let registry = GenericTemplateRegistry(
        structTemplates: currentScope.getAllGenericStructTemplates(),
        unionTemplates: currentScope.getAllGenericUnionTemplates(),
        functionTemplates: currentScope.getAllGenericFunctionTemplates(),
        extensionMethods: genericExtensionMethods,
        intrinsicExtensionMethods: genericIntrinsicExtensionMethods,
        traits: traits,
        concreteExtensionMethods: extensionMethods,
        intrinsicGenericTypes: intrinsicGenericTypes,
        intrinsicGenericFunctions: intrinsicGenericFunctions,
        concreteStructTypes: concreteStructs,
        concreteUnionTypes: concreteUnions
      )
      
      return TypeCheckerOutput(
        program: program,
        instantiationRequests: instantiationRequests,
        genericTemplates: registry
      )
    }
  }
  
  // MARK: - Pass 1: Type Collection
  
  /// Collects type definitions without checking function bodies.
  /// This allows forward references to work correctly.
  private func collectTypeDefinition(_ decl: GlobalNode) throws {
    switch decl {
    case .traitDeclaration(let name, let typeParameters, let superTraits, let methods, let access, let line):
      self.currentLine = line
      if traits[name] != nil {
        throw SemanticError.duplicateDefinition(name, line: line)
      }
      // Note: We don't validate superTraits here because they might be forward references
      // They will be validated in pass 2
      traits[name] = TraitDeclInfo(
        name: name,
        typeParameters: typeParameters,
        superTraits: superTraits,
        methods: methods,
        access: access,
        line: line
      )
      
    case .globalUnionDeclaration(let name, let typeParameters, let cases, let access, let line):
      self.currentLine = line
      if currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: line)
      }
      
      if !typeParameters.isEmpty {
        // Register generic union template
        let template = GenericUnionTemplate(
          name: name, typeParameters: typeParameters, cases: cases, access: access)
        currentScope.defineGenericUnionTemplate(name, template: template)
      } else {
        // Register placeholder for non-generic union (allows recursive references)
        let placeholder = Type.union(name: name, cases: [], isGenericInstantiation: false)
        try currentScope.defineType(name, type: placeholder)
      }
      
    case .globalStructDeclaration(let name, let typeParameters, let parameters, _, let line):
      self.currentLine = line
      if currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: line)
      }
      
      if !typeParameters.isEmpty {
        // Register generic struct template
        let template = GenericStructTemplate(
          name: name, typeParameters: typeParameters, parameters: parameters)
        currentScope.defineGenericStructTemplate(name, template: template)
      } else {
        // Register placeholder for non-generic struct (allows recursive references)
        let placeholder = Type.structure(name: name, members: [], isGenericInstantiation: false)
        try currentScope.defineType(name, type: placeholder)
      }
      
    case .globalFunctionDeclaration(_, let typeParameters, _, _, _, _, let line):
      self.currentLine = line
      // For generic functions, we just note that they exist
      // The full template will be registered in pass 2
      if !typeParameters.isEmpty {
        // Mark as generic function (will be fully registered in pass 2)
        // We don't need to do anything here since pass 2 handles it
      }
      // For non-generic functions, we also defer to pass 2
      // since we need to resolve parameter types which may reference forward types
      
    case .globalVariableDeclaration:
      // Variables are handled in pass 2
      break
      
    case .givenDeclaration(let typeParams, let typeNode, _, let line):
      self.currentLine = line
      // For generic given, we just note the base type exists
      // The methods will be registered in pass 2
      if !typeParams.isEmpty {
        // Generic given - base type should already be registered
        if case .generic(let baseName, _) = typeNode {
          // Verify the base type exists (struct or union template)
          if currentScope.lookupGenericStructTemplate(baseName) == nil &&
             currentScope.lookupGenericUnionTemplate(baseName) == nil {
            // It might be an intrinsic type like Pointer, which is OK
          }
        }
      }
      // Non-generic given is handled in pass 2
      
    case .intrinsicTypeDeclaration(let name, let typeParameters, _, let line):
      self.currentLine = line
      if currentScope.hasTypeDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: line)
      }
      
      if !typeParameters.isEmpty {
        // Register as intrinsic generic type
        intrinsicGenericTypes.insert(name)
        let template = GenericStructTemplate(
          name: name, typeParameters: typeParameters, parameters: [])
        currentScope.defineGenericStructTemplate(name, template: template)
      } else {
        // Non-generic intrinsic type - register the actual type
        let type: Type
        switch name {
        case "Int": type = .int
        case "Int8": type = .int8
        case "Int16": type = .int16
        case "Int32": type = .int32
        case "Int64": type = .int64
        case "UInt": type = .uint
        case "UInt8": type = .uint8
        case "UInt16": type = .uint16
        case "UInt32": type = .uint32
        case "UInt64": type = .uint64
        case "Float32": type = .float32
        case "Float64": type = .float64
        case "Bool": type = .bool
        case "Void": type = .void
        case "Never": type = .never
        default:
          type = .structure(name: name, members: [], isGenericInstantiation: false)
        }
        try currentScope.defineType(name, type: type)
      }
      
    case .intrinsicFunctionDeclaration(let name, let typeParameters, _, _, _, let line):
      self.currentLine = line
      if !typeParameters.isEmpty {
        intrinsicGenericFunctions.insert(name)
      }
      // Function signature will be registered in pass 3
      
    case .intrinsicGivenDeclaration:
      // Handled in pass 2 (signature) and pass 3 (body)
      break
    }
  }
  
  // MARK: - Pass 2: Given Signature Collection
  
  /// Collects given method signatures without checking bodies.
  /// This allows methods in one given block to call methods in another given block.
  /// Also resolves struct and union types so function signatures can reference them.
  private func collectGivenSignatures(_ decl: GlobalNode) throws {
    switch decl {
    case .givenDeclaration(let typeParams, let typeNode, let methods, let line):
      self.currentLine = line
      if !typeParams.isEmpty {
        // Generic Given - register method signatures
        guard case .generic(let baseName, let args) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }

        // Validate that args are exactly the type params
        if args.count != typeParams.count {
          throw SemanticError.typeMismatch(
            expected: "\(typeParams.count) generic params", got: "\(args.count)")
        }
        for (i, arg) in args.enumerated() {
          guard case .identifier(let argName) = arg, argName == typeParams[i].name else {
            throw SemanticError.invalidOperation(
              op: "generic given specialization not supported", type1: String(describing: arg),
              type2: "")
          }
        }

        // Initialize extension methods dictionary for this base type
        if genericExtensionMethods[baseName] == nil {
          genericExtensionMethods[baseName] = []
        }
        
        // Create a generic Self type for declaration-time checking
        let genericSelfArgs = typeParams.map { Type.genericParameter(name: $0.name) }
        let genericSelfType: Type
        if baseName == "Pointer" && genericSelfArgs.count == 1 {
          genericSelfType = .pointer(element: genericSelfArgs[0])
        } else if currentScope.lookupGenericStructTemplate(baseName) != nil {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        } else if currentScope.lookupGenericUnionTemplate(baseName) != nil {
          genericSelfType = .genericUnion(template: baseName, args: genericSelfArgs)
        } else {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        }
        
        // Register all method signatures (without checking bodies)
        for method in methods {
          let (checkedParams, checkedReturnType) = try withNewScope {
            for typeParam in typeParams {
              try currentScope.defineType(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(typeParams)
            
            try currentScope.defineType("Self", type: genericSelfType)
            currentScope.define("self", genericSelfType, mutable: false)
            
            let returnType = try resolveTypeNode(method.returnType)
            let params = try method.parameters.map { param -> Symbol in
              let paramType = try resolveTypeNode(param.type)
              return Symbol(
                name: param.name, type: paramType,
                kind: .variable(param.mutable ? .MutableValue : .Value))
            }
            
            // Validate __drop signature
            if method.name == "__drop" {
              if params.count != 1 || params[0].name != "self" {
                throw SemanticError.invalidOperation(
                  op: "__drop must have exactly one parameter 'self'", type1: "", type2: "")
              }
              if case .reference(_) = params[0].type {
                // OK
              } else {
                throw SemanticError.invalidOperation(
                  op: "__drop 'self' parameter must be a reference",
                  type1: params[0].type.description, type2: "")
              }
              if returnType != .void {
                throw SemanticError.invalidOperation(
                  op: "__drop must return Void", type1: returnType.description, type2: "")
              }
            }
            
            return (params, returnType)
          }
          
          // Register the method template (without checked body)
          genericExtensionMethods[baseName]!.append(GenericExtensionMethodTemplate(
            typeParams: typeParams,
            method: method,
            checkedBody: nil,
            checkedParameters: checkedParams,
            checkedReturnType: checkedReturnType
          ))
        }
      }
      // Non-generic given is handled in pass 3
      
    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let line):
      self.currentLine = line
      if !typeParams.isEmpty {
        // Generic intrinsic given - register method signatures
        guard case .generic(let baseName, _) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }

        if genericIntrinsicExtensionMethods[baseName] == nil {
          genericIntrinsicExtensionMethods[baseName] = []
        }

        for m in methods {
          genericIntrinsicExtensionMethods[baseName]!.append((typeParams: typeParams, method: m))
        }
      }
      // Non-generic intrinsic given is handled in pass 3
      
    case .globalStructDeclaration(let name, let typeParameters, let parameters, _, let line):
      self.currentLine = line
      // Resolve non-generic struct types so function signatures can reference them
      if typeParameters.isEmpty {
        // Non-generic struct: resolve member types and finalize the type definition
        let placeholder = currentScope.lookupType(name)!
        
        let params = try parameters.map { param -> Symbol in
          let paramType = try resolveTypeNode(param.type)
          if paramType == placeholder {
            throw SemanticError.invalidOperation(
              op: "Direct recursion in struct \(name) not allowed (use ref)", type1: param.name,
              type2: "")
          }
          return Symbol(
            name: param.name, type: paramType,
            kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
        }
        
        // Define the new type
        let typeType = Type.structure(
          name: name,
          members: params.map { (name: $0.name, type: $0.type, mutable: $0.isMutable()) },
          isGenericInstantiation: false
        )
        currentScope.overwriteType(name, type: typeType)
      }
      // Generic structs are handled in pass 3
      
    case .globalUnionDeclaration(let name, let typeParameters, let cases, _, let line):
      self.currentLine = line
      // Resolve non-generic union types so function signatures can reference them
      if typeParameters.isEmpty {
        // Non-generic union: resolve case types and finalize the type definition
        let placeholder = currentScope.lookupType(name)!
        
        var unionCases: [UnionCase] = []
        for c in cases {
          var params: [(name: String, type: Type)] = []
          for p in c.parameters {
            let resolved = try resolveTypeNode(p.type)
            if resolved == placeholder {
              throw SemanticError.invalidOperation(
                op: "Direct recursion in union \(name) not allowed (use ref)", type1: p.name,
                type2: "")
            }
            params.append((name: p.name, type: resolved))
          }
          unionCases.append(UnionCase(name: c.name, parameters: params))
        }
        
        let unionType = Type.union(name: name, cases: unionCases, isGenericInstantiation: false)
        currentScope.overwriteType(name, type: unionType)
      }
      // Generic unions are handled in pass 3
      
    case .globalFunctionDeclaration(let name, let typeParameters, let parameters, let returnTypeNode, _, _, let line):
      self.currentLine = line
      // Register function signature so it can be called from methods defined earlier
      if typeParameters.isEmpty {
        // Non-generic function: register signature now
        let returnType = try resolveTypeNode(returnTypeNode)
        let params = try parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          // In Koral, 'mutable' in parameter means it's a mutable reference (ref)
          let passKind: PassKind = param.mutable ? .byMutRef : .byVal
          return Parameter(type: paramType, kind: passKind)
        }
        let functionType = Type.function(parameters: params, returns: returnType)
        currentScope.define(name, functionType, mutable: false)
      }
      // Generic functions are handled in pass 3
      
    case .intrinsicFunctionDeclaration(let name, let typeParameters, let parameters, let returnTypeNode, _, let line):
      self.currentLine = line
      // Register intrinsic function signature so it can be called from methods defined earlier
      if typeParameters.isEmpty {
        let returnType = try resolveTypeNode(returnTypeNode)
        let params = try parameters.map { param -> Parameter in
          let paramType = try resolveTypeNode(param.type)
          let passKind: PassKind = param.mutable ? .byMutRef : .byVal
          return Parameter(type: paramType, kind: passKind)
        }
        let functionType = Type.function(parameters: params, returns: returnType)
        currentScope.define(name, functionType, mutable: false)
      }
      // Generic intrinsic functions are handled in pass 3
      
    default:
      // Other declarations are handled in pass 3
      break
    }
  }

  private func checkGlobalDeclaration(_ decl: GlobalNode) throws -> TypedGlobalNode? {
    switch decl {
    case .traitDeclaration(_, _, let superTraits, _, _, let line):
      self.currentLine = line
      // Trait was registered in pass 1, now validate superTraits
      for parent in superTraits {
        try validateTraitName(parent)
      }
      return nil

    case .globalUnionDeclaration(
      let name, let typeParameters, let cases, _, let line):
      self.currentLine = line

      if !typeParameters.isEmpty {
        // Generic union template was registered in pass 1
        // Now validate case parameter types
        try withNewScope {
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)
          
          for c in cases {
            for p in c.parameters {
              _ = try resolveTypeNode(p.type)
            }
          }
        }
        
        return .genericTypeTemplate(name: name)
      }

      // Non-generic union: already resolved in Pass 2
      // Just return the typed declaration
      let type = currentScope.lookupType(name)!
      
      var unionCases: [UnionCase] = []
      if case .union(_, let cases, _) = type {
        unionCases = cases
      }
      
      return .globalUnionDeclaration(
        identifier: Symbol(name: name, type: type, kind: .type), cases: unionCases)

    case .globalVariableDeclaration(let name, let typeNode, let value, let isMut, _, let line):
      self.currentLine = line
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name, line: line)
      }
      let type = try resolveTypeNode(typeNode)
      let typedValue = try inferTypedExpression(value)
      if typedValue.type != .never && typedValue.type != type {
        throw SemanticError.typeMismatch(
          expected: type.description, got: typedValue.type.description)
      }
      currentScope.define(name, type, mutable: isMut)
      return .globalVariable(
        identifier: Symbol(name: name, type: type, kind: .variable(isMut ? .MutableValue : .Value)),
        value: typedValue,
        kind: isMut ? .MutableValue : .Value
      )

    case .globalFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let body, let access,
      let line):
      self.currentLine = line
      
      // For non-generic functions, skip duplicate check if already defined in Pass 2
      if typeParameters.isEmpty && currentScope.lookup(name) != nil {
        // Already defined in Pass 2, continue with body checking
      } else if currentScope.hasFunctionDefinition(name) {
        throw SemanticError.duplicateDefinition(name, line: line)
      }

      if !typeParameters.isEmpty {
        // Define placeholder template for recursion
        let placeholderTemplate = GenericFunctionTemplate(
          name: name,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: ExpressionNode.call(
            callee: .identifier("panic"), arguments: [.stringLiteral("recursion")]),
          access: access
        )
        currentScope.defineGenericFunctionTemplate(name, template: placeholderTemplate)

        // Perform declaration-site checking and store results
        let (checkedBody, checkedParams, checkedReturnType) = try withNewScope {
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)

          let returnType = try resolveTypeNode(returnTypeNode)
          let params = try parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          // Perform declaration-site checking
          let (typedBody, _) = try checkFunctionBody(params, returnType, body)
          return (typedBody, params, returnType)
        }

        // Create template with checked results
        let template = GenericFunctionTemplate(
          name: name,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: body,
          access: access,
          checkedBody: checkedBody,
          checkedParameters: checkedParams,
          checkedReturnType: checkedReturnType
        )
        currentScope.defineGenericFunctionTemplate(name, template: template)
        return .genericFunctionTemplate(name: name)
      }

      // Pre-calculate function type to allow recursion
      let returnType = try resolveTypeNode(returnTypeNode)
      let params = try parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: .variable(param.mutable ? .MutableValue : .Value))
      }

      let functionType = Type.function(
        parameters: params.map {
          Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
        },
        returns: returnType
      )

      // Define placeholder for recursion (skip if already defined in Pass 2)
      if currentScope.lookup(name) == nil {
        currentScope.define(name, functionType, mutable: false)
      }

      let (typedBody, _) = try checkFunctionBody(params, returnType, body)

      return .globalFunction(
        identifier: Symbol(name: name, type: functionType, kind: .function),
        parameters: params,
        body: typedBody
      )

    case .intrinsicFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnTypeNode, let access, let line):
      self.currentLine = line
      
      // Skip duplicate check for non-generic functions (already defined in Pass 2)
      if typeParameters.isEmpty && currentScope.lookup(name) != nil {
        // Already defined in Pass 2, just return nil
        return nil
      }
      
      guard case nil = currentScope.lookup(name) else {
        throw SemanticError.duplicateDefinition(name, line: line)
      }

      // Create a dummy body for intrinsic representation
      let dummyBody = ExpressionNode.booleanLiteral(false)

      if !typeParameters.isEmpty {
        try withNewScope {
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)
          _ = try resolveTypeNode(returnTypeNode)
          _ = try parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }
        }

        let template = GenericFunctionTemplate(
          name: name,
          typeParameters: typeParameters,
          parameters: parameters,
          returnType: returnTypeNode,
          body: dummyBody,
          access: access
        )
        currentScope.defineGenericFunctionTemplate(name, template: template)
        
        // Mark as intrinsic generic function for special handling during monomorphization
        intrinsicGenericFunctions.insert(name)
        
        return .genericFunctionTemplate(name: name)
      }

      let (functionType, _, _) = try withNewScope {
        let returnType = try resolveTypeNode(returnTypeNode)
        let params = try parameters.map { param -> Symbol in
          let paramType = try resolveTypeNode(param.type)
          return Symbol(
            name: param.name, type: paramType,
            kind: .variable(param.mutable ? .MutableValue : .Value))
        }
        let funcType = Type.function(
          parameters: params.map { Parameter(type: $0.type, kind: .byVal) }, returns: returnType)
        // Dummy typed body
        let typedBody = TypedExpressionNode.integerLiteral(value: "0", type: .int)
        return (funcType, typedBody, params)
      }
      currentScope.define(name, functionType, mutable: false)
      return nil

    case .givenDeclaration(let typeParams, let typeNode, let methods, let line):
      self.currentLine = line
      if !typeParams.isEmpty {
        // Generic Given - signatures were registered in Pass 2 (collectGivenSignatures)
        // Now we only need to check method bodies
        guard case .generic(let baseName, _) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }
        
        // Create a generic Self type for body checking
        let genericSelfArgs = typeParams.map { Type.genericParameter(name: $0.name) }
        let genericSelfType: Type
        if baseName == "Pointer" && genericSelfArgs.count == 1 {
          genericSelfType = .pointer(element: genericSelfArgs[0])
        } else if currentScope.lookupGenericStructTemplate(baseName) != nil {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        } else if currentScope.lookupGenericUnionTemplate(baseName) != nil {
          genericSelfType = .genericUnion(template: baseName, args: genericSelfArgs)
        } else {
          genericSelfType = .genericStruct(template: baseName, args: genericSelfArgs)
        }
        
        // Find the templates registered in Pass 2 and check their bodies
        guard let templates = genericExtensionMethods[baseName] else {
          return nil
        }
        
        // Find the templates for this given block (they were added in order)
        // We need to find templates that match our methods
        for (_, method) in methods.enumerated() {
          // Find the template for this method
          guard let templateIndex = templates.firstIndex(where: { 
            $0.method.name == method.name && 
            $0.typeParams.count == typeParams.count &&
            $0.checkedBody == nil  // Not yet checked
          }) else {
            continue
          }
          
          let template = templates[templateIndex]
          
          // Check method body
          let checkedBody = try withNewScope {
            for typeParam in typeParams {
              try currentScope.defineType(
                typeParam.name, type: .genericParameter(name: typeParam.name))
            }
            try recordGenericTraitBounds(typeParams)
            
            try currentScope.defineType("Self", type: genericSelfType)
            currentScope.define("self", genericSelfType, mutable: false)
            
            let (typedBody, _) = try checkFunctionBody(
              template.checkedParameters ?? [],
              template.checkedReturnType ?? .void,
              method.body
            )
            return typedBody
          }
          
          // Update the template with the checked body
          genericExtensionMethods[baseName]![templateIndex] = GenericExtensionMethodTemplate(
            typeParams: template.typeParams,
            method: template.method,
            checkedBody: checkedBody,
            checkedParameters: template.checkedParameters,
            checkedReturnType: template.checkedReturnType
          )
        }

        // Return nil as we process these lazily upon instantiation
        return nil
      }

      let type = try resolveTypeNode(typeNode)
      let typeName: String
      if case .structure(let name, _, _) = type {
        typeName = name
      } else if case .union(let name, _, _) = type {
        typeName = name
      } else if case .int = type {
        typeName = type.description
      } else if case .int8 = type {
        typeName = type.description
      } else if case .int16 = type {
        typeName = type.description
      } else if case .int32 = type {
        typeName = type.description
      } else if case .int64 = type {
        typeName = type.description
      } else if case .uint = type {
        typeName = type.description
      } else if case .uint8 = type {
        typeName = type.description
      } else if case .uint16 = type {
        typeName = type.description
      } else if case .uint32 = type {
        typeName = type.description
      } else if case .uint64 = type {
        typeName = type.description
      } else if case .float32 = type {
        typeName = type.description
      } else if case .float64 = type {
        typeName = type.description
      } else if case .bool = type {
        typeName = type.description
      } else {
        throw SemanticError.invalidOperation(
          op: "given extends only struct or union", type1: type.description, type2: "")
      }

      var typedMethods: [TypedMethodDeclaration] = []

      if extensionMethods[typeName] == nil {
        extensionMethods[typeName] = [:]
      }

      // Pass 1: pre-register all method symbols so methods can call each other regardless
      // of declaration order within the `given` block.
      struct GivenMethodInfo {
        let method: MethodDeclaration
        let symbol: Symbol
        let params: [Symbol]
        let returnType: Type
      }

      var methodInfos: [GivenMethodInfo] = []
      methodInfos.reserveCapacity(methods.count)

      for method in methods {
        let (methodType, params, returnType) = try withNewScope {
          for typeParam in method.typeParameters {
            try currentScope.defineType(
              typeParam.name, type: .genericParameter(name: typeParam.name))
          }

          try currentScope.defineType("Self", type: type)
          currentScope.define("self", type, mutable: false)

          let returnType = try resolveTypeNode(method.returnType)
          let params = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          // Validate __drop signature
          if method.name == "__drop" {
            if params.count != 1 || params[0].name != "self" {
              throw SemanticError.invalidOperation(
                op: "__drop must have exactly one parameter 'self'", type1: "", type2: "")
            }
            if case .reference(_) = params[0].type {
              // OK
            } else {
              throw SemanticError.invalidOperation(
                op: "__drop 'self' parameter must be a reference",
                type1: params[0].type.description, type2: "")
            }
            if returnType != .void {
              throw SemanticError.invalidOperation(
                op: "__drop must return Void", type1: returnType.description, type2: "")
            }
          }

          let functionType = Type.function(
            parameters: params.map {
              Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
          )
          return (functionType, params, returnType)
        }

        let methodKind = getCompilerMethodKind(method.name)
        let methodSymbol = Symbol(
          name: method.name,  // Use original method name, Monomorphizer will mangle it
          type: methodType,
          kind: .function,
          methodKind: methodKind
        )

        extensionMethods[typeName]![method.name] = methodSymbol
        methodInfos.append(
          GivenMethodInfo(
            method: method, symbol: methodSymbol, params: params, returnType: returnType)
        )
      }

      // Pass 2: typecheck bodies with full method set available.
      for info in methodInfos {
        let typedBody = try withNewScope {
          for typeParam in info.method.typeParameters {
            try currentScope.defineType(
              typeParam.name, type: .genericParameter(name: typeParam.name))
          }

          try currentScope.defineType("Self", type: type)
          currentScope.define("self", type, mutable: false)

          let (typedBody, _) = try checkFunctionBody(info.params, info.returnType, info.method.body)
          return typedBody
        }

        typedMethods.append(
          TypedMethodDeclaration(
            identifier: info.symbol,
            parameters: info.params,
            body: typedBody,
            returnType: info.returnType
          )
        )
      }

      return .givenDeclaration(type: type, methods: typedMethods)

    case .intrinsicGivenDeclaration(let typeParams, let typeNode, let methods, let line):
      self.currentLine = line
      if !typeParams.isEmpty {
        // Generic Given (Intrinsic)
        guard case .generic(let baseName, let args) = typeNode else {
          throw SemanticError.invalidOperation(
            op: "generic given on non-generic type", type1: "", type2: "")
        }
        if args.count != typeParams.count {
          throw SemanticError.typeMismatch(
            expected: "\(typeParams.count) generic params", got: "\(args.count)")
        }
        for (i, arg) in args.enumerated() {
          guard case .identifier(let argName) = arg, argName == typeParams[i].name else {
            throw SemanticError.invalidOperation(
              op: "generic given specialization not supported", type1: String(describing: arg),
              type2: "")
          }
        }

        if genericIntrinsicExtensionMethods[baseName] == nil {
          genericIntrinsicExtensionMethods[baseName] = []
        }

        for m in methods {
          genericIntrinsicExtensionMethods[baseName]!.append((typeParams: typeParams, method: m))
        }
        return nil
      }

      let type = try resolveTypeNode(typeNode)

      let typeName: String
      let shouldEmitGiven: Bool
      switch type {
      case .structure(let name, _, _):
        typeName = name
        shouldEmitGiven = true
      case .union(let name, _, _):
        typeName = name
        shouldEmitGiven = true
      case .int, .int8, .int16, .int32, .int64,
        .uint, .uint8, .uint16, .uint32, .uint64,
        .float32, .float64,
        .bool:
        typeName = type.description
        shouldEmitGiven = false
      default:
        throw SemanticError.invalidOperation(
          op: "intrinsic given target not supported", type1: type.description, type2: "")
      }

      var typedMethods: [TypedMethodDeclaration] = []

      for method in methods {
        let (methodType, typedBody, params, returnType) = try withNewScope {
          try currentScope.defineType("Self", type: type)
          let returnType = try resolveTypeNode(method.returnType)
          let params = try method.parameters.map { param -> Symbol in
            let paramType = try resolveTypeNode(param.type)
            return Symbol(
              name: param.name, type: paramType,
              kind: .variable(param.mutable ? .MutableValue : .Value))
          }

          let functionType = Type.function(
            parameters: params.map {
              Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
            },
            returns: returnType
          )
          // Dummy body for intrinsic
          let typedBody = TypedExpressionNode.integerLiteral(value: "0", type: .int)
          return (functionType, typedBody, params, returnType)
        }

        let methodKind = getCompilerMethodKind(method.name)
        let methodSymbol = Symbol(
          name: method.name,  // Use original method name, Monomorphizer will mangle it
          type: methodType,
          kind: .function,
          methodKind: methodKind
        )

        if shouldEmitGiven {
          typedMethods.append(
            TypedMethodDeclaration(
              identifier: methodSymbol,
              parameters: params,
              body: typedBody,
              returnType: returnType
            ))
        }
        if extensionMethods[typeName] == nil {
          extensionMethods[typeName] = [:]
        }
        extensionMethods[typeName]![method.name] = methodSymbol
      }

      return shouldEmitGiven ? .givenDeclaration(type: type, methods: typedMethods) : nil

    case .globalStructDeclaration(
      let name, let typeParameters, let parameters, _, let line):
      self.currentLine = line
      // Note: Type was already registered in Pass 1 (collectTypeDefinition)
      // Non-generic types are resolved in Pass 2 (collectGivenSignatures)

      if !typeParameters.isEmpty {
        // Generic struct template was already registered in Pass 1
        // Now validate field types with type parameters in scope
        try withNewScope {
          // Define type parameters as generic parameter types
          for param in typeParameters {
            try currentScope.defineType(param.name, type: .genericParameter(name: param.name))
          }
          try recordGenericTraitBounds(typeParameters)
          
          // Validate all field types are valid under the type parameters
          for param in parameters {
            _ = try resolveTypeNode(param.type)
          }
        }
        
        return .genericTypeTemplate(name: name)
      }

      // Non-generic struct: already resolved in Pass 2
      // Just return the typed declaration
      let typeType = currentScope.lookupType(name)!

      let params = try parameters.map { param -> Symbol in
        let paramType = try resolveTypeNode(param.type)
        return Symbol(
          name: param.name, type: paramType,
          kind: param.mutable ? .variable(.MutableValue) : .variable(.Value))
      }

      return .globalStructDeclaration(
        identifier: Symbol(name: name, type: typeType, kind: .type),
        parameters: params
      )

    case .intrinsicTypeDeclaration(let name, let typeParameters, _, let line):
      self.currentLine = line
      // Note: Type was already registered in Pass 1 (collectTypeDefinition)
      // Pass 2 just returns the appropriate node

      if typeParameters.isEmpty {
        // Non-generic intrinsic type was already registered in Pass 1
        let type = currentScope.lookupType(name) ?? .structure(name: name, members: [], isGenericInstantiation: false)
        let dummySymbol = Symbol(name: name, type: type, kind: .variable(.Value))
        return .globalStructDeclaration(identifier: dummySymbol, parameters: [])
      } else {
        // Generic intrinsic template was already registered in Pass 1
        // intrinsicGenericTypes was also already populated in Pass 1
        return .genericTypeTemplate(name: name)
      }
    }
  }

  private func checkFunctionBody(
    _ params: [Symbol],
    _ returnType: Type,
    _ body: ExpressionNode
  ) throws -> (TypedExpressionNode, Type) {
    let previousReturnType = currentFunctionReturnType
    currentFunctionReturnType = returnType
    defer { currentFunctionReturnType = previousReturnType }

    return try withNewScope {
      // Add parameters to new scope
      for param in params {
        currentScope.define(param.name, param.type, mutable: param.isMutable())
      }

      let typedBody = try inferTypedExpression(body)
      if typedBody.type != .never && typedBody.type != returnType {
        throw SemanticError.typeMismatch(
          expected: returnType.description, got: typedBody.type.description)
      }
      let functionType = Type.function(
        parameters: params.map {
          Parameter(type: $0.type, kind: fromSymbolKindToPassKind($0.kind))
        }, returns: returnType)
      return (typedBody, functionType)
    }
  }

  private func convertExprToTypeNode(_ expr: ExpressionNode) throws -> TypeNode {
    switch expr {
    case .identifier(let name):
      return .identifier(name)
    case .subscriptExpression(let base, let args):
      if case .identifier(let baseName) = base {
        let typeArgs = try args.map { try convertExprToTypeNode($0) }
        return .generic(base: baseName, args: typeArgs)
      }
      throw SemanticError.invalidOperation(
        op: "Complex type expression not supported", type1: "", type2: "")
    default:
      throw SemanticError.typeMismatch(expected: "Type Identifier", got: String(describing: expr))
    }
  }

  // 新增用于返回带类型的表达式的类型推导函数
  private func inferTypedExpression(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .castExpression(let typeNode, let innerExpr):
      let targetType = try resolveTypeNode(typeNode)
      let typedInner = try inferTypedExpression(innerExpr)

      if !isValidExplicitCast(from: typedInner.type, to: targetType) {
        throw SemanticError.invalidOperation(
          op: "cast",
          type1: typedInner.type.description,
          type2: targetType.description
        )
      }

      // Cast always produces an rvalue.
      return .castExpression(expression: typedInner, type: targetType)

    case .integerLiteral(let value, let suffix):
      let type: Type
      if let suffix = suffix {
        switch suffix {
        case .i: type = .int
        case .i8: type = .int8
        case .i16: type = .int16
        case .i32: type = .int32
        case .i64: type = .int64
        case .u: type = .uint
        case .u8: type = .uint8
        case .u16: type = .uint16
        case .u32: type = .uint32
        case .u64: type = .uint64
        case .f32, .f64:
          throw SemanticError.typeMismatch(expected: "integer suffix", got: suffix.rawValue)
        }
      } else {
        type = .int
      }
      return .integerLiteral(value: value, type: type)

    case .floatLiteral(let value, let suffix):
      let type: Type
      if let suffix = suffix {
        switch suffix {
        case .f32: type = .float32
        case .f64: type = .float64
        case .i, .i8, .i16, .i32, .i64, .u, .u8, .u16, .u32, .u64:
          throw SemanticError.typeMismatch(expected: "float suffix", got: suffix.rawValue)
        }
      } else {
        type = .float64
      }
      return .floatLiteral(value: value, type: type)

    case .stringLiteral(let value):
      return .stringLiteral(value: value, type: builtinStringType())

    case .booleanLiteral(let value):
      return .booleanLiteral(value: value, type: .bool)

    case .matchExpression(let subject, let cases, _):
      let typedSubject = try inferTypedExpression(subject)
      // Auto-deref subject type for pattern matching
      var subjectType = typedSubject.type
      if case .reference(let inner) = subjectType {
        subjectType = inner
      }

      var typedCases: [TypedMatchCase] = []
      var resultType: Type?

      for c in cases {
        try withNewScope {
          let (pattern, vars) = try checkPattern(c.pattern, subjectType: subjectType)
          for (name, mut, type) in vars {
            currentScope.define(name, type, mutable: mut)
          }
          let typedBody = try inferTypedExpression(c.body)
          if let rt = resultType {
            if typedBody.type != .never {
              if rt == .never {
                // Previous cases were all Never, this is the first concrete type
                resultType = typedBody.type
              } else if typedBody.type != rt {
                throw SemanticError.typeMismatch(
                  expected: rt.description, got: typedBody.type.description)
              }
            }
          } else {
            resultType = typedBody.type
          }
          typedCases.append(TypedMatchCase(pattern: pattern, body: typedBody))
        }
      }
      
      // Exhaustiveness checking
      let patterns = typedCases.map { $0.pattern }
      let resolvedCases = resolveUnionCasesForExhaustiveness(subjectType)
      let checker = ExhaustivenessChecker(
        subjectType: subjectType,
        patterns: patterns,
        currentLine: currentLine,
        resolvedUnionCases: resolvedCases
      )
      try checker.check()
      
      return .matchExpression(subject: typedSubject, cases: typedCases, type: resultType ?? .void)

    case .identifier(let name):
      if currentScope.isMoved(name) {
        throw SemanticError.variableMoved(name)
      }
      guard let type = currentScope.lookup(name) else {
        throw SemanticError.undefinedVariable(name)
      }
      return .variable(identifier: Symbol(name: name, type: type, kind: .variable(.Value)))

    case .blockExpression(let statements, let finalExpression):
      return try withNewScope {
        var typedStatements: [TypedStatementNode] = []
        var blockType: Type = .void  // Default if no final expression
        var foundNever = false

        for stmt in statements {
          let typedStmt = try checkStatement(stmt)
          typedStatements.append(typedStmt)

          switch typedStmt {
          case .expression(let expr):
            if expr.type == .never {
              blockType = .never
              foundNever = true
            }
          case .return, .break, .continue:
            blockType = .never
            foundNever = true
          default:
            break
          }
        }

        if let finalExpr = finalExpression {
          let typedFinalExpr = try inferTypedExpression(finalExpr)
          // If we already found a Never statement, the block is Never regardless of final expr?
          // Actually, if a statement is Never, the final expression is unreachable.
          // For now, let's respect final expression type if reachable, or override if Never.
          if foundNever {
            // Block is forced to Never
            blockType = .never
          } else {
            blockType = typedFinalExpr.type
          }
          return .blockExpression(
            statements: typedStatements, finalExpression: typedFinalExpr,
            type: blockType)
        }

        if foundNever { blockType = .never }

        return .blockExpression(
          statements: typedStatements, finalExpression: nil, type: blockType)
      }

    case .arithmeticExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) || isFloatType(typedLeft.type) {
          typedRight = coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type,
          isIntegerType(typedRight.type) || isFloatType(typedRight.type)
        {
          typedLeft = coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      let resultType = try checkArithmeticOp(op, typedLeft.type, typedRight.type)
      return .arithmeticExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

    case .comparisonExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) || isFloatType(typedLeft.type) {
          typedRight = coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type,
          isIntegerType(typedRight.type) || isFloatType(typedRight.type)
        {
          typedLeft = coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      // Allow single-byte ASCII string literals to coerce to UInt8 in comparisons.
      if typedLeft.type != typedRight.type {
        if typedLeft.type == .uint8 {
          typedRight = coerceLiteral(typedRight, to: .uint8)
        }
        if typedRight.type == .uint8 {
          typedLeft = coerceLiteral(typedLeft, to: .uint8)
        }
      }

      // Operator sugar for Equatable: lower `==`/`<>` to `__equals(self ref, other ref)`
      // for non-builtin scalar types (struct/union/String/generic parameters).
      if (op == .equal || op == .notEqual), typedLeft.type == typedRight.type,
        !isBuiltinEqualityComparable(typedLeft.type)
      {
        let eq = try buildEqualsCall(lhs: typedLeft, rhs: typedRight)
        if op == .notEqual {
          return .notExpression(expression: eq, type: .bool)
        }
        return eq
      }

      // Operator sugar for Comparable: lower `<`/`<=`/`>`/`>=` to
      // `__compare(self ref, other ref) Int` for non-builtin scalar types
      // (struct/union/String/generic parameters).
      if (op == .greater || op == .less || op == .greaterEqual || op == .lessEqual),
        typedLeft.type == typedRight.type,
        !isBuiltinOrderingComparable(typedLeft.type)
      {
        let cmp = try buildCompareCall(lhs: typedLeft, rhs: typedRight)
        let zero: TypedExpressionNode = .integerLiteral(value: "0", type: .int)
        return .comparisonExpression(left: cmp, op: op, right: zero, type: .bool)
      }

      let resultType = try checkComparisonOp(op, typedLeft.type, typedRight.type)
      return .comparisonExpression(
        left: typedLeft, op: op, right: typedRight, type: resultType)

    case .letExpression(let name, let typeNode, let value, let mutable, let body):
      var typedValue = try inferTypedExpression(value)

      if let typeNode = typeNode {
        let type = try resolveTypeNode(typeNode)
        typedValue = coerceLiteral(typedValue, to: type)
        if typedValue.type != type {
          throw SemanticError.typeMismatch(
            expected: type.description, got: typedValue.type.description)
        }
      }

      return try withNewScope {
        currentScope.define(name, typedValue.type, mutable: mutable)
        let symbol = Symbol(
          name: name, type: typedValue.type, kind: .variable(mutable ? .MutableValue : .Value))

        let typedBody = try inferTypedExpression(body)

        return .letExpression(
          identifier: symbol, value: typedValue, body: typedBody, type: typedBody.type)
      }

    case .ifExpression(let condition, let thenBranch, let elseBranch):
      let typedCondition = try inferTypedExpression(condition)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      let typedThen = try inferTypedExpression(thenBranch)

      if let elseExpr = elseBranch {
        let typedElse = try inferTypedExpression(elseExpr)

        let resultType: Type
        if typedThen.type == typedElse.type {
          resultType = typedThen.type
        } else if typedThen.type == .never {
          resultType = typedElse.type
        } else if typedElse.type == .never {
          resultType = typedThen.type
        } else {
          throw SemanticError.typeMismatch(
            expected: typedThen.type.description,
            got: typedElse.type.description
          )
        }

        return .ifExpression(
          condition: typedCondition, thenBranch: typedThen, elseBranch: typedElse,
          type: resultType)
      } else {
        return .ifExpression(
          condition: typedCondition, thenBranch: typedThen, elseBranch: nil, type: .void)
      }

    case .whileExpression(let condition, let body):
      let typedCondition = try inferTypedExpression(condition)
      if typedCondition.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: typedCondition.type.description)
      }
      loopDepth += 1
      defer { loopDepth -= 1 }
      let typedBody = try inferTypedExpression(body)
      return .whileExpression(
        condition: typedCondition,
        body: typedBody,
        type: .void
      )

    case .call(let callee, let arguments):
      // Check if callee is a static method call on a generic type (e.g., [Int]List.new())
      if case .memberPath(let baseExpr, let path) = callee,
         case .genericInstantiation(let baseName, let args) = baseExpr,
         path.count == 1 {
        let memberName = path[0]
        let resolvedArgs = try args.map { try resolveTypeNode($0) }
        
        // Check if it's a generic struct with a static method
        if let template = currentScope.lookupGenericStructTemplate(baseName) {
          // Validate type argument count
          guard template.typeParameters.count == resolvedArgs.count else {
            throw SemanticError.typeMismatch(
              expected: "\(template.typeParameters.count) generic arguments",
              got: "\(resolvedArgs.count)"
            )
          }
          
          // Validate generic constraints
          try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
          
          // Record instantiation request for deferred monomorphization
          if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
            recordInstantiation(InstantiationRequest(
              kind: .structType(template: template, args: resolvedArgs),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
          
          // Create parameterized type
          let baseType = Type.genericStruct(template: baseName, args: resolvedArgs)
          
          // Look up static method on generic struct
          if let extensions = genericExtensionMethods[baseName] {
            if let ext = extensions.first(where: { $0.method.name == memberName }) {
              let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
              if isStatic {
                let methodSym = try resolveGenericExtensionMethod(
                  baseType: baseType, templateName: baseName, typeArgs: resolvedArgs,
                  methodInfo: ext)
                if methodSym.methodKind != .normal {
                  throw SemanticError(
                    .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                    line: currentLine)
                }
                
                // Get function parameters and return type
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
                }
                
                // Check argument count
                if arguments.count != params.count {
                  throw SemanticError.invalidArgumentCount(
                    function: memberName,
                    expected: params.count,
                    got: arguments.count
                  )
                }
                
                // Type check arguments
                var typedArguments: [TypedExpressionNode] = []
                for (arg, param) in zip(arguments, params) {
                  var typedArg = try inferTypedExpression(arg)
                  typedArg = coerceLiteral(typedArg, to: param.type)
                  if typedArg.type != param.type {
                    throw SemanticError.typeMismatch(
                      expected: param.type.description,
                      got: typedArg.type.description
                    )
                  }
                  typedArguments.append(typedArg)
                }
                
                // Return staticMethodCall node
                return .staticMethodCall(
                  baseType: baseType,
                  methodName: memberName,
                  typeArgs: resolvedArgs,
                  arguments: typedArguments,
                  type: returnType
                )
              }
            }
          }
        }
        
        // Check if it's a generic union with a case constructor or static method
        if let template = currentScope.lookupGenericUnionTemplate(baseName) {
          // Validate type argument count
          guard template.typeParameters.count == resolvedArgs.count else {
            throw SemanticError.typeMismatch(
              expected: "\(template.typeParameters.count) generic arguments",
              got: "\(resolvedArgs.count)"
            )
          }
          
          // Validate generic constraints
          try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
          
          // Record instantiation request for deferred monomorphization
          if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
            recordInstantiation(InstantiationRequest(
              kind: .unionType(template: template, args: resolvedArgs),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
          
          // Create parameterized type
          let baseType = Type.genericUnion(template: baseName, args: resolvedArgs)
          
          // Check if it's a union case constructor
          var substitution: [String: Type] = [:]
          for (i, param) in template.typeParameters.enumerated() {
            substitution[param.name] = resolvedArgs[i]
          }
          
          if let c = template.cases.first(where: { $0.name == memberName }) {
            let resolvedParams = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try c.parameters.map { param -> Parameter in
                let paramType = try resolveTypeNode(param.type)
                return Parameter(type: paramType, kind: .byVal)
              }
            }
            
            if arguments.count != resolvedParams.count {
              throw SemanticError.invalidArgumentCount(
                function: "\(baseName).\(memberName)",
                expected: resolvedParams.count,
                got: arguments.count
              )
            }
            
            var typedArgs: [TypedExpressionNode] = []
            for (arg, param) in zip(arguments, resolvedParams) {
              var typedArg = try inferTypedExpression(arg)
              typedArg = coerceLiteral(typedArg, to: param.type)
              if typedArg.type != param.type {
                throw SemanticError.typeMismatch(
                  expected: param.type.description, got: typedArg.type.description)
              }
              typedArgs.append(typedArg)
            }
            
            return .unionConstruction(type: baseType, caseName: memberName, arguments: typedArgs)
          }
          
          // Look up static method on generic union
          if let extensions = genericExtensionMethods[baseName] {
            if let ext = extensions.first(where: { $0.method.name == memberName }) {
              let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
              if isStatic {
                let methodSym = try resolveGenericExtensionMethod(
                  baseType: baseType, templateName: baseName, typeArgs: resolvedArgs,
                  methodInfo: ext)
                if methodSym.methodKind != .normal {
                  throw SemanticError(
                    .generic("compiler protocol method \(memberName) cannot be called explicitly"),
                    line: currentLine)
                }
                
                guard case .function(let params, let returnType) = methodSym.type else {
                  throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
                }
                
                if arguments.count != params.count {
                  throw SemanticError.invalidArgumentCount(
                    function: memberName,
                    expected: params.count,
                    got: arguments.count
                  )
                }
                
                var typedArguments: [TypedExpressionNode] = []
                for (arg, param) in zip(arguments, params) {
                  var typedArg = try inferTypedExpression(arg)
                  typedArg = coerceLiteral(typedArg, to: param.type)
                  if typedArg.type != param.type {
                    throw SemanticError.typeMismatch(
                      expected: param.type.description,
                      got: typedArg.type.description
                    )
                  }
                  typedArguments.append(typedArg)
                }
                
                return .staticMethodCall(
                  baseType: baseType,
                  methodName: memberName,
                  typeArgs: resolvedArgs,
                  arguments: typedArguments,
                  type: returnType
                )
              }
            }
          }
        }
      }
      
      // Check if callee is a generic instantiation (Constructor call or Function call)
      if case .genericInstantiation(let base, let args) = callee {
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
          
          // Record instantiation request for deferred monomorphization
          // Skip if any argument contains generic parameters (will be recorded when fully resolved)
          if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
            recordInstantiation(InstantiationRequest(
              kind: .structType(template: template, args: resolvedArgs),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
          
          // Create type substitution map
          var substitution: [String: Type] = [:]
          for (i, param) in template.typeParameters.enumerated() {
            substitution[param.name] = resolvedArgs[i]
          }
          
          // Resolve member types with substitution
          let memberTypes = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try template.parameters.map { param -> (name: String, type: Type, mutable: Bool) in
              let fieldType = try resolveTypeNode(param.type)
              return (name: param.name, type: fieldType, mutable: param.mutable)
            }
          }

          if arguments.count != memberTypes.count {
            throw SemanticError.invalidArgumentCount(
              function: base,
              expected: memberTypes.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, expectedMember) in zip(arguments, memberTypes) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: expectedMember.type)
            if typedArg.type != expectedMember.type {
              throw SemanticError.typeMismatch(
                expected: expectedMember.type.description,
                got: typedArg.type.description
              )
            }
            typedArguments.append(typedArg)
          }
          
          // Return parameterized type
          let genericType = Type.genericStruct(template: base, args: resolvedArgs)

          return .typeConstruction(
            identifier: Symbol(name: base, type: genericType, kind: .type),
            typeArgs: resolvedArgs,
            arguments: typedArguments,
            type: genericType
          )
        } else if let template = currentScope.lookupGenericFunctionTemplate(base) {
          // Special handling for explicit intrinsic template calls (e.g. [Int]alloc_memory)
          if base == "alloc_memory" {
            let resolvedArgs = try args.map { try resolveTypeNode($0) }
            guard resolvedArgs.count == 1 else {
              throw SemanticError.typeMismatch(
                expected: "1 generic arg", got: "\(resolvedArgs.count)")
            }
            let T = resolvedArgs[0]

            guard arguments.count == 1 else {
              throw SemanticError.invalidArgumentCount(
                function: base, expected: 1, got: arguments.count)
            }
            let countExpr = try inferTypedExpression(arguments[0])
            if countExpr.type != .int {
              throw SemanticError.typeMismatch(expected: "Int", got: countExpr.type.description)
            }

            return .intrinsicCall(
              .allocMemory(count: countExpr, resultType: .pointer(element: T)))
          }

          if base == "dealloc_memory" {
            let resolvedArgs = try args.map { try resolveTypeNode($0) }
            guard resolvedArgs.count == 1 else {
              throw SemanticError.typeMismatch(
                expected: "1 generic arg", got: "\(resolvedArgs.count)")
            }
            // We don't need T, but we checked args count.

            guard arguments.count == 1 else {
              throw SemanticError.invalidArgumentCount(
                function: base, expected: 1, got: arguments.count)
            }
            let ptrExpr = try inferTypedExpression(arguments[0])
            // Check pointer type? Sema checks this later for normal calls, but here we do it maybe?
            // Actually, `ptrExpr.type` should match `[T]Pointer`.
            return .intrinsicCall(.deallocMemory(ptr: ptrExpr))
          }

          if base == "ref_count" {
            _ = try args.map { try resolveTypeNode($0) }
            guard arguments.count == 1 else {
              throw SemanticError.invalidArgumentCount(
                function: base, expected: 1, got: arguments.count)
            }
            let val = try inferTypedExpression(arguments[0])
            return .intrinsicCall(.refCount(val: val))
          }
          if base == "copy_memory" {
            _ = try args.map { try resolveTypeNode($0) }
            guard arguments.count == 3 else {
              throw SemanticError.invalidArgumentCount(
                function: base, expected: 3, got: arguments.count)
            }
            let d = try inferTypedExpression(arguments[0])
            let s = try inferTypedExpression(arguments[1])
            let c = try inferTypedExpression(arguments[2])
            return .intrinsicCall(.copyMemory(dest: d, source: s, count: c))
          }
          if base == "move_memory" {
            _ = try args.map { try resolveTypeNode($0) }
            guard arguments.count == 3 else {
              throw SemanticError.invalidArgumentCount(
                function: base, expected: 3, got: arguments.count)
            }
            let d = try inferTypedExpression(arguments[0])
            let s = try inferTypedExpression(arguments[1])
            let c = try inferTypedExpression(arguments[2])
            return .intrinsicCall(.moveMemory(dest: d, source: s, count: c))
          }

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
          
          // Record instantiation request for deferred monomorphization
          // Skip if any argument contains generic parameters (will be recorded when fully resolved)
          if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
            recordInstantiation(InstantiationRequest(
              kind: .function(template: template, args: resolvedArgs),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
          
          // Create type substitution map
          var substitution: [String: Type] = [:]
          for (i, param) in template.typeParameters.enumerated() {
            substitution[param.name] = resolvedArgs[i]
          }
          
          // Resolve parameter and return types with substitution
          let (params, returnType) = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            let resolvedParams = try template.parameters.map { param -> Parameter in
              let paramType = try resolveTypeNode(param.type)
              return Parameter(type: paramType, kind: param.mutable ? .byMutRef : .byVal)
            }
            let resolvedReturn = try resolveTypeNode(template.returnType)
            return (resolvedParams, resolvedReturn)
          }

          if arguments.count != params.count {
            throw SemanticError.invalidArgumentCount(
              function: base,
              expected: params.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, expectedParam) in zip(arguments, params) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: expectedParam.type)
            if typedArg.type != expectedParam.type {
              throw SemanticError.typeMismatch(
                expected: expectedParam.type.description,
                got: typedArg.type.description
              )
            }
            typedArguments.append(typedArg)
          }

          // Return genericCall node instead of instantiated call
          return .genericCall(
            functionName: base,
            typeArgs: resolvedArgs,
            arguments: typedArguments,
            type: returnType
          )
        } else {
          throw SemanticError.undefinedType(base)
        }
      }

      // Resolve Callee (Check Union Constructor)
      var preResolvedCallee: TypedExpressionNode? = nil
      do {
        preResolvedCallee = try inferTypedExpression(callee)
      } catch is SemanticError {
        // Fallthrough
        preResolvedCallee = nil
      }

      if let resolved = preResolvedCallee, case .variable(let symbol) = resolved {
        if case .function(_, let returnType) = symbol.type {
          // Check for union constructor (both concrete and generic)
          var unionName: String? = nil
          if case .union(let uName, _, _) = returnType {
            unionName = uName
          } else if case .genericUnion(let templateName, _) = returnType {
            unionName = templateName
          }
          
          if let uName = unionName {
            // Check if symbol name is uName.CaseName
            if symbol.name.starts(with: uName + ".") {
              let caseName = String(symbol.name.dropFirst(uName.count + 1))
              let params = symbol.type.functionParameters!

              if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                  function: symbol.name, expected: params.count, got: arguments.count)
              }

              var typedArgs: [TypedExpressionNode] = []
              for (arg, param) in zip(arguments, params) {
                var typedArg = try inferTypedExpression(arg)
                typedArg = coerceLiteral(typedArg, to: param.type)
                if typedArg.type != param.type {
                  throw SemanticError.typeMismatch(
                    expected: param.type.description, got: typedArg.type.description)
                }
                typedArgs.append(typedArg)
              }

              return .unionConstruction(type: returnType, caseName: caseName, arguments: typedArgs)
            }
          }
        }
      }

      // Check if it is a constructor call OR implicit generic function call
      if case .identifier(let name) = callee {
        // 1. Try Generic Function Template (Implicit Inference)
        if let template = currentScope.lookupGenericFunctionTemplate(name) {
          var inferred: [String: Type] = [:]

          if arguments.count != template.parameters.count {
            throw SemanticError.invalidArgumentCount(
              function: name,
              expected: template.parameters.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (argExpr, param) in zip(arguments, template.parameters) {
            var typedArg = try inferTypedExpression(argExpr)
            do {
              let expectedType = try resolveTypeNode(param.type)
              typedArg = coerceLiteral(typedArg, to: expectedType)
            } catch let error as SemanticError {
              // During implicit generic inference, parameter types may reference template
              // type parameters (e.g. `T`, `[T]Pointer`) which are not in the caller scope.
              // Skip literal coercion in that case; we'll infer `T` via unify().
              if case .undefinedType(let name) = error.kind,
                template.typeParameters.contains(where: { $0.name == name })
              {
                // no-op
              } else {
                throw error
              }
            }
            typedArguments.append(typedArg)
            try unify(
              node: param.type, type: typedArg.type, inferred: &inferred,
              typeParams: template.typeParameters.map { $0.name })
          }

          let resolvedArgs = try template.typeParameters.map { param -> Type in
            guard let type = inferred[param.name] else {
              throw SemanticError.typeMismatch(
                expected: "inferred type for \(param.name)", got: "unknown")
            }
            return type
          }

          if template.name == "dealloc_memory" {
            return .intrinsicCall(.deallocMemory(ptr: typedArguments[0]))
          }
          if template.name == "copy_memory" {
            return .intrinsicCall(
              .copyMemory(
                dest: typedArguments[0], source: typedArguments[1], count: typedArguments[2]))
          }
          if template.name == "move_memory" {
            return .intrinsicCall(
              .moveMemory(
                dest: typedArguments[0], source: typedArguments[1], count: typedArguments[2]))
          }
          if template.name == "ref_count" {
            return .intrinsicCall(.refCount(val: typedArguments[0]))
          }

          // Record instantiation request for deferred monomorphization
          // Skip if any argument contains generic parameters (will be recorded when fully resolved)
          if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
            recordInstantiation(InstantiationRequest(
              kind: .function(template: template, args: resolvedArgs),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
          
          // Validate generic constraints
          try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedArgs)
          
          // Create type substitution map
          var substitution: [String: Type] = [:]
          for (i, param) in template.typeParameters.enumerated() {
            substitution[param.name] = resolvedArgs[i]
          }
          
          // Resolve return type with substitution
          let returnType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(template.returnType)
          }

          // Return genericCall node instead of instantiated call
          return .genericCall(
            functionName: name,
            typeArgs: resolvedArgs,
            arguments: typedArguments,
            type: returnType
          )
        }

        if let type = currentScope.lookupType(name) {
          guard case .structure(_, let parameters, _) = type else {
            throw SemanticError.invalidOperation(
              op: "construct", type1: type.description, type2: "")
          }

          if arguments.count != parameters.count {
            throw SemanticError.invalidArgumentCount(
              function: name,
              expected: parameters.count,
              got: arguments.count
            )
          }

          var typedArguments: [TypedExpressionNode] = []
          for (arg, expectedMember) in zip(arguments, parameters) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: expectedMember.type)
            if typedArg.type != expectedMember.type {
              throw SemanticError.typeMismatch(
                expected: expectedMember.type.description,
                got: typedArg.type.description
              )
            }
            typedArguments.append(typedArg)
          }

          return .typeConstruction(
            identifier: Symbol(name: name, type: type, kind: .type),
            typeArgs: nil,
            arguments: typedArguments,
            type: type
          )
        }
      }

      // Special handling for intrinsic function calls (alloc_memory, etc.)
      if case .identifier(let name) = callee {
        if let intrinsicNode = try checkIntrinsicCall(name: name, arguments: arguments) {
          return intrinsicNode
        }
      }

      let typedCallee = try inferTypedExpression(callee)

      // Secondary guard: if the resolved callee is a special compiler method, block explicit calls
      if case .variable(let sym) = typedCallee, sym.methodKind != .normal {
        throw SemanticError.invalidOperation(
          op: "Explicit call to \(sym.name) is not allowed", type1: "", type2: "")
      }

      // Method call
      if case .methodReference(let base, let method, _, let methodType) = typedCallee {
        // Intercept Pointer methods
        if case .pointer(_) = base.type,
          let node = try checkIntrinsicPointerMethod(base: base, method: method, args: arguments)
        {
          return node
        }

        // Intercept Float32/Float64 intrinsic methods
        if base.type == .float32 || base.type == .float64,
          let node = try checkIntrinsicFloatMethod(base: base, method: method, args: arguments)
        {
          return node
        }

        if case .function(let params, let returns) = method.type {
          if arguments.count != params.count - 1 {
            throw SemanticError.invalidArgumentCount(
              function: method.name,
              expected: params.count - 1,
              got: arguments.count
            )
          }

          // Check base type against first param
          // 如果 base 是 rvalue 且方法期望 self ref，使用临时物化
          if let firstParam = params.first,
             case .reference(let inner) = firstParam.type,
             inner == base.type,
             base.valueCategory == .rvalue {
            // 右值临时物化：将方法调用包装在 letExpression 中
            return try materializeTemporaryForMethodCall(
              base: base,
              method: method,
              methodType: methodType,
              params: params,
              returns: returns,
              arguments: arguments
            )
          }
          
          var finalBase = base
          if let firstParam = params.first {
            if base.type != firstParam.type {
              // 尝试自动取引用：期望 T ref，实际是 T
              if case .reference(let inner) = firstParam.type, inner == base.type {
                if base.valueCategory == .lvalue {
                  finalBase = .referenceExpression(expression: base, type: firstParam.type)
                } else {
                  // 这个分支不应该被执行，因为上面已经处理了 rvalue 的情况
                  throw SemanticError.invalidOperation(
                    op: "implicit ref", type1: base.type.description, type2: "rvalue")
                }
              } else if case .reference(let inner) = base.type, inner == firstParam.type {
                // 尝试自动解引用：期望 T，实际是 T ref
                // Only safe for Copy types (otherwise this would implicitly move).
                finalBase = .derefExpression(expression: base, type: inner)
              } else {
                throw SemanticError.typeMismatch(
                  expected: firstParam.type.description,
                  got: base.type.description
                )
              }
            }
          }

          let finalCallee: TypedExpressionNode = .methodReference(
            base: finalBase, method: method, typeArgs: nil, type: methodType)


          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params.dropFirst()) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: param.type)
            if typedArg.type != param.type {
              // Try implicit ref/deref for arguments as well (mirrors self handling).
              if case .reference(let inner) = param.type, inner == typedArg.type {
                if typedArg.valueCategory == .lvalue {
                  typedArg = .referenceExpression(expression: typedArg, type: param.type)
                } else {
                  throw SemanticError.invalidOperation(
                    op: "implicit ref", type1: typedArg.type.description, type2: "rvalue")
                }
              } else if case .reference(let inner) = typedArg.type, inner == param.type {
                typedArg = .derefExpression(expression: typedArg, type: inner)
              } else {
                throw SemanticError.typeMismatch(
                  expected: param.type.description,
                  got: typedArg.type.description
                )
              }
            }
            typedArguments.append(typedArg)
          }

          // Lower primitive `__equals(self, other)` to direct scalar comparison.
          if method.methodKind == .equals,
            returns == .bool,
            params.count == 2,
            params[0].type == params[1].type,
            isBuiltinEqualityComparable(params[0].type)
          {
            return .comparisonExpression(left: finalBase, op: .equal, right: typedArguments[0], type: .bool)
          }

          // Lower primitive `__compare(self, other) Int` to scalar comparisons.
          if method.methodKind == .compare,
            returns == .int,
            params.count == 2,
            params[0].type == params[1].type,
            isBuiltinOrderingComparable(params[0].type)
          {
            let lhsVal = finalBase
            let rhsVal = typedArguments[0]

            let less: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .less, right: rhsVal, type: .bool)
            let greater: TypedExpressionNode = .comparisonExpression(left: lhsVal, op: .greater, right: rhsVal, type: .bool)
            let minusOne: TypedExpressionNode = .integerLiteral(value: "-1", type: .int)
            let plusOne: TypedExpressionNode = .integerLiteral(value: "1", type: .int)
            let zero: TypedExpressionNode = .integerLiteral(value: "0", type: .int)

            let gtBranch: TypedExpressionNode = .ifExpression(condition: greater, thenBranch: plusOne, elseBranch: zero, type: .int)
            return .ifExpression(condition: less, thenBranch: minusOne, elseBranch: gtBranch, type: .int)
          }

          return .call(callee: finalCallee, arguments: typedArguments, type: returns)
        }
      }

      // Function call
      if case .function(let params, let returns) = typedCallee.type {
        if arguments.count != params.count {
          throw SemanticError.invalidArgumentCount(
            function: "expression",
            expected: params.count,
            got: arguments.count
          )
        }

        var typedArguments: [TypedExpressionNode] = []
        for (arg, param) in zip(arguments, params) {
          var typedArg = try inferTypedExpression(arg)
          typedArg = coerceLiteral(typedArg, to: param.type)
          if typedArg.type != param.type {
            throw SemanticError.typeMismatch(
              expected: param.type.description,
              got: typedArg.type.description
            )
          }
          typedArguments.append(typedArg)
        }

        return .call(
          callee: typedCallee,
          arguments: typedArguments,
          type: returns
        )
      }

      throw SemanticError.invalidOperation(
        op: "call", type1: typedCallee.type.description, type2: "")

    case .andExpression(let left, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .andExpression(left: typedLeft, right: typedRight, type: .bool)

    case .orExpression(let left, let right):
      let typedLeft = try inferTypedExpression(left)
      let typedRight = try inferTypedExpression(right)
      if typedLeft.type != .bool || typedRight.type != .bool {
        throw SemanticError.typeMismatch(
          expected: "Bool", got: "\(typedLeft.type) and \(typedRight.type)")
      }
      return .orExpression(left: typedLeft, right: typedRight, type: .bool)

    case .notExpression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      if typedExpr.type != .bool {
        throw SemanticError.typeMismatch(expected: "Bool", got: typedExpr.type.description)
      }
      return .notExpression(expression: typedExpr, type: .bool)

    case .bitwiseExpression(let left, let op, let right):
      var typedLeft = try inferTypedExpression(left)
      var typedRight = try inferTypedExpression(right)

      // Allow numeric literals to coerce to the other operand type.
      if typedLeft.type != typedRight.type {
        if isIntegerType(typedLeft.type) {
          typedRight = coerceLiteral(typedRight, to: typedLeft.type)
        }
        if typedLeft.type != typedRight.type, isIntegerType(typedRight.type) {
          typedLeft = coerceLiteral(typedLeft, to: typedRight.type)
        }
      }

      if !isIntegerScalarType(typedLeft.type) || typedLeft.type != typedRight.type {
        throw SemanticError.typeMismatch(
          expected: "Matching Integer Types", got: "\(typedLeft.type) \(op) \(typedRight.type)")
      }
      return .bitwiseExpression(left: typedLeft, op: op, right: typedRight, type: typedLeft.type)

    case .bitwiseNotExpression(let expr):
      let typedExpr = try inferTypedExpression(expr)
      if !isIntegerScalarType(typedExpr.type) {
        throw SemanticError.typeMismatch(expected: "Integer Type", got: typedExpr.type.description)
      }
      return .bitwiseNotExpression(expression: typedExpr, type: typedExpr.type)

    case .derefExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      if case .reference(let innerType) = typedInner.type {
        return .derefExpression(expression: typedInner, type: innerType)
      } else {
        throw SemanticError.typeMismatch(
          expected: "Reference type",
          got: typedInner.type.description
        )
      }

    case .refExpression(let inner):
      let typedInner = try inferTypedExpression(inner)
      // 禁止对引用再次取引用（仅单层）
      if case .reference(_) = typedInner.type {
        throw SemanticError.invalidOperation(
          op: "ref", type1: typedInner.type.description, type2: "")
      }
      return .referenceExpression(expression: typedInner, type: .reference(inner: typedInner.type))

    case .subscriptExpression(let base, let arguments):
      let typedBase = try inferTypedExpression(base)
      let typedArguments = try arguments.map { try inferTypedExpression($0) }
      let resolvedSubscript = try resolveSubscript(base: typedBase, args: typedArguments)

      return resolvedSubscript

    case .memberPath(let baseExpr, let path):
      // 1. Check if baseExpr is a Type (Generic Instantiation) for static method access or Union Constructor
      if case .genericInstantiation(let baseName, let args) = baseExpr {
        if let template = currentScope.lookupGenericStructTemplate(baseName) {
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
          
          // Record instantiation request for deferred monomorphization
          // Skip if any argument contains generic parameters (will be recorded when fully resolved)
          if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
            recordInstantiation(InstantiationRequest(
              kind: .structType(template: template, args: resolvedArgs),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
          
          // Create parameterized type
          let type = Type.genericStruct(template: baseName, args: resolvedArgs)

          if path.count == 1 {
            let memberName = path[0]
            // Look up static method on generic struct
            if let extensions = genericExtensionMethods[baseName] {
              if let ext = extensions.first(where: { $0.method.name == memberName }) {
                let isStatic =
                  ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
                if isStatic {
                  let methodSym = try resolveGenericExtensionMethod(
                    baseType: type, templateName: baseName, typeArgs: resolvedArgs,
                    methodInfo: ext)
                  if methodSym.methodKind != .normal {
                    throw SemanticError(
                      .generic(
                        "compiler protocol method \(memberName) cannot be called explicitly"),
                      line: currentLine)
                  }
                  return .variable(identifier: methodSym)
                }
              }
            }
          }
        } else if let template = currentScope.lookupGenericUnionTemplate(baseName) {
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
          
          // Record instantiation request for deferred monomorphization
          // Skip if any argument contains generic parameters (will be recorded when fully resolved)
          if !resolvedArgs.contains(where: { $0.containsGenericParameter }) {
            recordInstantiation(InstantiationRequest(
              kind: .unionType(template: template, args: resolvedArgs),
              sourceLine: currentLine,
              sourceFileName: currentFileName
            ))
          }
          
          // Create parameterized type
          let type = Type.genericUnion(template: baseName, args: resolvedArgs)

          if path.count == 1 {
            let memberName = path[0]
            // Look up union case constructor
            // Create type substitution to resolve case parameter types
            var substitution: [String: Type] = [:]
            for (i, param) in template.typeParameters.enumerated() {
              substitution[param.name] = resolvedArgs[i]
            }
            
            // Find the case and resolve its parameter types
            if let c = template.cases.first(where: { $0.name == memberName }) {
              let resolvedParams = try withNewScope {
                for (paramName, paramType) in substitution {
                  try currentScope.defineType(paramName, type: paramType)
                }
                return try c.parameters.map { param -> Parameter in
                  let paramType = try resolveTypeNode(param.type)
                  return Parameter(type: paramType, kind: .byVal)
                }
              }
              
              let symbolName = "\(baseName).\(memberName)"
              let constructorType = Type.function(parameters: resolvedParams, returns: type)
              let symbol = Symbol(
                name: symbolName, type: constructorType, kind: .variable(.Value))
              return .variable(identifier: symbol)
            }
          }
        }
      }

      // 2. Check if baseExpr is a Type (Identifier) for static method access
      if case .identifier(let name) = baseExpr, let type = currentScope.lookupType(name) {
        if path.count == 1 {
          let memberName = path[0]
          var methodSymbol: Symbol?

          // Static trait methods on generic parameters (no `self` parameter)
          if case .genericParameter(let paramName) = type,
            let bounds = genericTraitBounds[paramName]
          {
            for traitName in bounds {
              let methods = try flattenedTraitMethods(traitName)
              if let sig = methods[memberName] {
                if sig.parameters.first?.name == "self" {
                  continue
                }
                let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: type)
                methodSymbol = Symbol(
                  name: "__trait_\(traitName)_\(memberName)",
                  type: expectedType,
                  kind: .function
                )
                break
              }
            }
          }

          if case .structure(let typeName, _, _) = type {
            if let methods = extensionMethods[typeName], let sym = methods[memberName] {
              methodSymbol = sym
            }
          }

          if let method = methodSymbol {
            if method.methodKind != .normal {
              throw SemanticError(
                .generic(
                  "compiler protocol method \(memberName) cannot be called explicitly"),
                line: currentLine)
            }
            // Return the function symbol directly (static function reference)
            return .variable(identifier: method)
          }
        }
      }

      // 3. Union Constructor Access via member path (e.g., UnionType.CaseName)
      // This is not a "Function variable" but a direct Constructor node which expects a Call parent.
      // However, we are inside `memberPath`. The parser sees `Option.Some(1)` as Call(MemberPath(Option, Some), [1]).
      // So here we should return a "Function" type that is the constructor.
      if case .identifier(let name) = baseExpr, let type = currentScope.lookupType(name) {
        if path.count == 1 {
          let memberName = path[0]
          if case .union(_, let cases, _) = type {
            if let c = cases.first(where: { $0.name == memberName }) {
              // Found Union Case. Return a synthetic Function Symbol representing the constructor.
              let paramTypes = c.parameters.map { Parameter(type: $0.type, kind: .byVal) }
              let funcType = Type.function(parameters: paramTypes, returns: type)
              let symbol = Symbol(name: "\(name).\(memberName)", type: funcType, kind: .function)
              // We abuse .variable node to transport this symbol up to the Call handler?
              // Or creating a specialized Node?
              // If we return .variable(symbol), the Call handler will see a function variable and try to "call" it.
              // That works for normal functions. For Union constructor, we need to distinguish it in `checkCall` to emit `unionConstruction`.

              // We can mark the symbol name specially or check effectively later.
              // Better: Create a distinct SymbolKind for Constructor? Or check if Symbol name matches Union.Case.

              // Actually, let's keep it simple. If we return a Variable(Function), checkCall will try to invoke it.
              // But `checkCall` logic usually handles `variable` node.
              return .variable(identifier: symbol)
            }
          }
        }
      }

      // infer base
      let inferredBase = try inferTypedExpression(baseExpr)

      // access member optimization: peel auto-deref to access ref directly
      let typedBase: TypedExpressionNode
      if case .derefExpression(let inner, _) = inferredBase {
        typedBase = inner
      } else {
        typedBase = inferredBase
      }

      var currentType: Type = {
        if case .reference(let inner) = typedBase.type { return inner }
        return typedBase.type
      }()
      var typedPath: [Symbol] = []

      for (index, memberName) in path.enumerated() {
        let isLast = index == path.count - 1

        let typeToLookup = {
          if case .reference(let inner) = currentType { return inner }
          return currentType
        }()

        // Check if it is a structure to access members
        var foundMember = false
        if case .structure(_, let members, _) = typeToLookup {
          if let mem = members.first(where: { $0.name == memberName }) {
            let sym = Symbol(
              name: mem.name, type: mem.type, kind: .variable(mem.mutable ? .MutableValue : .Value))
            typedPath.append(sym)
            currentType = mem.type
            foundMember = true
          }
        }
        
        // Handle genericStruct types - look up member from template
        if !foundMember, case .genericStruct(let templateName, let typeArgs) = typeToLookup {
          if let template = currentScope.lookupGenericStructTemplate(templateName) {
            // Create type substitution map
            var substitution: [String: Type] = [:]
            for (i, param) in template.typeParameters.enumerated() {
              if i < typeArgs.count {
                substitution[param.name] = typeArgs[i]
              }
            }
            
            // Look up member in template and substitute types
            if let param = template.parameters.first(where: { $0.name == memberName }) {
              let memberType = try withNewScope {
                for (paramName, paramType) in substitution {
                  try currentScope.defineType(paramName, type: paramType)
                }
                return try resolveTypeNode(param.type)
              }
              let sym = Symbol(
                name: param.name, type: memberType, kind: .variable(param.mutable ? .MutableValue : .Value))
              typedPath.append(sym)
              currentType = memberType
              foundMember = true
            }
          }
        }

        if !foundMember {
          if isLast {
            let typeName = typeToLookup.description
            if let methods = extensionMethods[typeName], let methodSym = methods[memberName] {
              if methodSym.methodKind != .normal {
                throw SemanticError(
                  .generic(
                    "compiler protocol method \(memberName) cannot be called explicitly"),
                  line: currentLine)
              }
              let base: TypedExpressionNode
              if typedPath.isEmpty {
                base = typedBase
              } else {
                base = .memberPath(source: typedBase, path: typedPath)
              }
              return .methodReference(base: base, method: methodSym, typeArgs: nil, type: methodSym.type)
            }

            if case .pointer(let element) = typeToLookup {
              if let extensions = genericIntrinsicExtensionMethods["Pointer"] {
                for ext in extensions {
                  if ext.method.name == memberName {
                    let methodSym = try resolveIntrinsicExtensionMethod(
                      baseType: typeToLookup,
                      templateName: "Pointer",
                      typeArgs: [element],
                      methodInfo: ext
                    )
                    if methodSym.methodKind != .normal {
                      throw SemanticError(
                        .generic(
                          "compiler protocol method \(memberName) cannot be called explicitly"),
                        line: currentLine)
                    }
                    let base: TypedExpressionNode
                    if typedPath.isEmpty {
                      base = typedBase
                    } else {
                      base = .memberPath(source: typedBase, path: typedPath)
                    }
                    return .methodReference(base: base, method: methodSym, typeArgs: [element], type: methodSym.type)
                  }
                }
              }

              if let extensions = genericExtensionMethods["Pointer"] {
                for ext in extensions {
                  if ext.method.name == memberName {
                    let methodSym = try resolveGenericExtensionMethod(
                      baseType: typeToLookup,
                      templateName: "Pointer",
                      typeArgs: [element],
                      methodInfo: ext
                    )
                    if methodSym.methodKind != .normal {
                      throw SemanticError(
                        .generic(
                          "compiler protocol method \(memberName) cannot be called explicitly"),
                        line: currentLine)
                    }
                    let base: TypedExpressionNode
                    if typedPath.isEmpty {
                      base = typedBase
                    } else {
                      base = .memberPath(source: typedBase, path: typedPath)
                    }
                    return .methodReference(base: base, method: methodSym, typeArgs: [element], type: methodSym.type)
                  }
                }
              }
            }
            
            // Handle genericStruct types
            if case .genericStruct(let templateName, let typeArgs) = typeToLookup {
              if let extensions = genericExtensionMethods[templateName] {
                for ext in extensions {
                  if ext.method.name == memberName {
                    let methodSym = try resolveGenericExtensionMethod(
                      baseType: typeToLookup,
                      templateName: templateName,
                      typeArgs: typeArgs,
                      methodInfo: ext
                    )
                    if methodSym.methodKind != .normal {
                      throw SemanticError(
                        .generic(
                          "compiler protocol method \(memberName) cannot be called explicitly"),
                        line: currentLine)
                    }
                    let base: TypedExpressionNode
                    if typedPath.isEmpty {
                      base = typedBase
                    } else {
                      base = .memberPath(source: typedBase, path: typedPath)
                    }
                    return .methodReference(base: base, method: methodSym, typeArgs: typeArgs, type: methodSym.type)
                  }
                }
              }
            }
            
            // Handle genericUnion types
            if case .genericUnion(let templateName, let typeArgs) = typeToLookup {
              if let extensions = genericExtensionMethods[templateName] {
                for ext in extensions {
                  if ext.method.name == memberName {
                    let methodSym = try resolveGenericExtensionMethod(
                      baseType: typeToLookup,
                      templateName: templateName,
                      typeArgs: typeArgs,
                      methodInfo: ext
                    )
                    if methodSym.methodKind != .normal {
                      throw SemanticError(
                        .generic(
                          "compiler protocol method \(memberName) cannot be called explicitly"),
                        line: currentLine)
                    }
                    let base: TypedExpressionNode
                    if typedPath.isEmpty {
                      base = typedBase
                    } else {
                      base = .memberPath(source: typedBase, path: typedPath)
                    }
                    return .methodReference(base: base, method: methodSym, typeArgs: typeArgs, type: methodSym.type)
                  }
                }
              }
            }

            // Trait-bounded instance methods on generic parameters
            if case .genericParameter(let paramName) = typeToLookup,
              let bounds = genericTraitBounds[paramName]
            {
              for traitName in bounds {
                let methods = try flattenedTraitMethods(traitName)
                if let sig = methods[memberName] {
                  if sig.parameters.first?.name != "self" {
                    continue
                  }
                  let expectedType = try expectedFunctionTypeForTraitMethod(sig, selfType: typeToLookup)
                  let placeholder = Symbol(
                    name: "__trait_\(traitName)_\(memberName)",
                    type: expectedType,
                    kind: .function,
                    methodKind: getCompilerMethodKind(memberName)
                  )

                  if placeholder.methodKind != .normal {
                    throw SemanticError(
                      .generic(
                        "compiler protocol method \(memberName) cannot be called explicitly"),
                      line: currentLine)
                  }

                  let base: TypedExpressionNode
                  if typedPath.isEmpty {
                    base = typedBase
                  } else {
                    base = .memberPath(source: typedBase, path: typedPath)
                  }
                  return .methodReference(base: base, method: placeholder, typeArgs: nil, type: expectedType)
                }
              }
            }
          }

          if case .structure(let typeName, _, _) = typeToLookup {
            throw SemanticError.undefinedMember(memberName, typeName)
          } else {
            throw SemanticError.invalidOperation(
              op: "member access", type1: typeToLookup.description, type2: "")
          }
        }
      }
      return .memberPath(source: typedBase, path: typedPath)

    case .staticMethodCall(let typeName, let typeArgs, let methodName, let arguments):
      // Handle static method call from AST: TypeName.methodName(...) or [T]TypeName.methodName(...)
      
      // Intercept Float32.from_bits and Float64.from_bits intrinsic static methods
      if typeArgs.isEmpty && methodName == "from_bits" {
        if typeName == "Float32" {
          guard arguments.count == 1 else {
            throw SemanticError.invalidArgumentCount(function: "from_bits", expected: 1, got: arguments.count)
          }
          var bits = try inferTypedExpression(arguments[0])
          bits = coerceLiteral(bits, to: .uint32)
          if bits.type != .uint32 {
            throw SemanticError.typeMismatch(expected: "UInt32", got: bits.type.description)
          }
          return .intrinsicCall(.float32FromBits(bits: bits))
        } else if typeName == "Float64" {
          guard arguments.count == 1 else {
            throw SemanticError.invalidArgumentCount(function: "from_bits", expected: 1, got: arguments.count)
          }
          var bits = try inferTypedExpression(arguments[0])
          bits = coerceLiteral(bits, to: .uint64)
          if bits.type != .uint64 {
            throw SemanticError.typeMismatch(expected: "UInt64", got: bits.type.description)
          }
          return .intrinsicCall(.float64FromBits(bits: bits))
        }
      }
      
      // Intercept Pointer.bits() intrinsic static method
      if typeName == "Pointer" && methodName == "bits" {
        if let node = try checkIntrinsicPointerStaticMethod(typeName: typeName, methodName: methodName, args: arguments) {
          return node
        }
      }
      
      let resolvedTypeArgs = try typeArgs.map { try resolveTypeNode($0) }
      
      // Check if it's a generic struct
      if let template = currentScope.lookupGenericStructTemplate(typeName) {
        // Validate type argument count
        guard template.typeParameters.count == resolvedTypeArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic arguments",
            got: "\(resolvedTypeArgs.count)"
          )
        }
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedTypeArgs)
        
        // Record instantiation request for deferred monomorphization
        if !resolvedTypeArgs.contains(where: { $0.containsGenericParameter }) {
          recordInstantiation(InstantiationRequest(
            kind: .structType(template: template, args: resolvedTypeArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Create parameterized type
        let baseType = Type.genericStruct(template: typeName, args: resolvedTypeArgs)
        
        // Look up static method on generic struct
        if let extensions = genericExtensionMethods[typeName] {
          if let ext = extensions.first(where: { $0.method.name == methodName }) {
            let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
            if isStatic {
              let methodSym = try resolveGenericExtensionMethod(
                baseType: baseType, templateName: typeName, typeArgs: resolvedTypeArgs,
                methodInfo: ext)
              if methodSym.methodKind != .normal {
                throw SemanticError(
                  .generic("compiler protocol method \(methodName) cannot be called explicitly"),
                  line: currentLine)
              }
              
              // Get function parameters and return type
              guard case .function(let params, let returnType) = methodSym.type else {
                throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
              }
              
              // Check argument count
              if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                  function: methodName,
                  expected: params.count,
                  got: arguments.count
                )
              }
              
              // Type check arguments
              var typedArguments: [TypedExpressionNode] = []
              for (arg, param) in zip(arguments, params) {
                var typedArg = try inferTypedExpression(arg)
                typedArg = coerceLiteral(typedArg, to: param.type)
                if typedArg.type != param.type {
                  throw SemanticError.typeMismatch(
                    expected: param.type.description,
                    got: typedArg.type.description
                  )
                }
                typedArguments.append(typedArg)
              }
              
              // Return staticMethodCall node
              return .staticMethodCall(
                baseType: baseType,
                methodName: methodName,
                typeArgs: resolvedTypeArgs,
                arguments: typedArguments,
                type: returnType
              )
            }
          }
        }
        
        throw SemanticError.undefinedMember(methodName, typeName)
      }
      
      // Check if it's a generic union
      if let template = currentScope.lookupGenericUnionTemplate(typeName) {
        // Validate type argument count
        guard template.typeParameters.count == resolvedTypeArgs.count else {
          throw SemanticError.typeMismatch(
            expected: "\(template.typeParameters.count) generic arguments",
            got: "\(resolvedTypeArgs.count)"
          )
        }
        
        // Validate generic constraints
        try enforceGenericConstraints(typeParameters: template.typeParameters, args: resolvedTypeArgs)
        
        // Record instantiation request for deferred monomorphization
        if !resolvedTypeArgs.contains(where: { $0.containsGenericParameter }) {
          recordInstantiation(InstantiationRequest(
            kind: .unionType(template: template, args: resolvedTypeArgs),
            sourceLine: currentLine,
            sourceFileName: currentFileName
          ))
        }
        
        // Create parameterized type
        let baseType = Type.genericUnion(template: typeName, args: resolvedTypeArgs)
        
        // Look up static method on generic union
        if let extensions = genericExtensionMethods[typeName] {
          if let ext = extensions.first(where: { $0.method.name == methodName }) {
            let isStatic = ext.method.parameters.isEmpty || ext.method.parameters[0].name != "self"
            if isStatic {
              let methodSym = try resolveGenericExtensionMethod(
                baseType: baseType, templateName: typeName, typeArgs: resolvedTypeArgs,
                methodInfo: ext)
              if methodSym.methodKind != .normal {
                throw SemanticError(
                  .generic("compiler protocol method \(methodName) cannot be called explicitly"),
                  line: currentLine)
              }
              
              guard case .function(let params, let returnType) = methodSym.type else {
                throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
              }
              
              if arguments.count != params.count {
                throw SemanticError.invalidArgumentCount(
                  function: methodName,
                  expected: params.count,
                  got: arguments.count
                )
              }
              
              var typedArguments: [TypedExpressionNode] = []
              for (arg, param) in zip(arguments, params) {
                var typedArg = try inferTypedExpression(arg)
                typedArg = coerceLiteral(typedArg, to: param.type)
                if typedArg.type != param.type {
                  throw SemanticError.typeMismatch(
                    expected: param.type.description,
                    got: typedArg.type.description
                  )
                }
                typedArguments.append(typedArg)
              }
              
              return .staticMethodCall(
                baseType: baseType,
                methodName: methodName,
                typeArgs: resolvedTypeArgs,
                arguments: typedArguments,
                type: returnType
              )
            }
          }
        }
        
        throw SemanticError.undefinedMember(methodName, typeName)
      }
      
      // Check if it's a non-generic type (e.g., String.empty())
      if let type = currentScope.lookupType(typeName) {
        // For non-generic types, typeArgs should be empty
        if !resolvedTypeArgs.isEmpty {
          throw SemanticError(.generic("Type \(typeName) is not generic"), line: currentLine)
        }
        
        // Get the type name for method lookup
        let lookupTypeName: String
        switch type {
        case .structure(let name, _, _):
          lookupTypeName = name
        case .union(let name, _, _):
          lookupTypeName = name
        default:
          lookupTypeName = type.description
        }
        
        // Look up static method
        if let methods = extensionMethods[lookupTypeName], let methodSym = methods[methodName] {
          if methodSym.methodKind != .normal {
            throw SemanticError(
              .generic("compiler protocol method \(methodName) cannot be called explicitly"),
              line: currentLine)
          }
          
          guard case .function(let params, let returnType) = methodSym.type else {
            throw SemanticError(.generic("Expected function type for static method"), line: currentLine)
          }
          
          // Check if it's a static method (no self parameter or first param is not self)
          let isStatic = params.isEmpty || {
            // Check if first parameter is self by looking at the method signature
            // For static methods, there's no self parameter
            // We can't easily check this from the function type alone,
            // so we assume if it's in extensionMethods and being called statically, it's valid
            true
          }()
          
          if !isStatic {
            throw SemanticError(.generic("Method \(methodName) requires an instance"), line: currentLine)
          }
          
          if arguments.count != params.count {
            throw SemanticError.invalidArgumentCount(
              function: methodName,
              expected: params.count,
              got: arguments.count
            )
          }
          
          var typedArguments: [TypedExpressionNode] = []
          for (arg, param) in zip(arguments, params) {
            var typedArg = try inferTypedExpression(arg)
            typedArg = coerceLiteral(typedArg, to: param.type)
            if typedArg.type != param.type {
              throw SemanticError.typeMismatch(
                expected: param.type.description,
                got: typedArg.type.description
              )
            }
            typedArguments.append(typedArg)
          }
          
          return .staticMethodCall(
            baseType: type,
            methodName: methodName,
            typeArgs: [],
            arguments: typedArguments,
            type: returnType
          )
        }
        
        throw SemanticError.undefinedMember(methodName, typeName)
      }
      
      throw SemanticError.undefinedType(typeName)

    case .forExpression(let pattern, let iterable, let body):
      return try inferForExpression(pattern: pattern, iterable: iterable, body: body)

    case .genericInstantiation(let base, _):
      throw SemanticError.invalidOperation(op: "use type as value", type1: base, type2: "")
    }
  }

  // MARK: - For Loop Type Checking and Desugaring

  /// Type checks a for expression and desugars it to let + while + match.
  /// for <pattern> = <iterable> then <body>
  /// becomes:
  /// let mut __koral_iter_N = <iterable>.iterator() then  // or just <iterable> if it's already an iterator
  ///   while true then
  ///     when __koral_iter_N.next() is {
  ///       .Some(<pattern>) then <body>,
  ///       .None then break
  ///     }
  private func inferForExpression(
    pattern: PatternNode,
    iterable: ExpressionNode,
    body: ExpressionNode
  ) throws -> TypedExpressionNode {
    // 1. Type check the iterable expression
    let typedIterable = try inferTypedExpression(iterable)
    let iterableType = typedIterable.type
    
    // 2. First check if the expression type itself is an iterator
    //    (has a next(self ref) [T]Option method)
    if let elementType = try? extractIteratorElementType(iterableType) {
      // The expression itself is an iterator, use it directly
      try checkForLoopPatternExhaustiveness(pattern: pattern, elementType: elementType)
      return try desugarForLoop(
        pattern: pattern,
        typedIterable: typedIterable,
        iteratorType: iterableType,
        elementType: elementType,
        body: body,
        needsIteratorCall: false  // Don't call iterator(), use expression directly
      )
    }
    
    // 3. Look up the iterator() method on the iterable type
    guard let iteratorMethod = try lookupConcreteMethodSymbol(on: iterableType, name: "iterator") else {
      throw SemanticError(.generic(
        "Type \(iterableType) is not iterable: missing iterator() method and does not implement Iterator"
      ), line: currentLine)
    }
    
    // 4. Get the iterator type from the method's return type
    guard case .function(_, let iteratorType) = iteratorMethod.type else {
      throw SemanticError(.generic("iterator() must be a function"), line: currentLine)
    }
    
    // 5. Extract the element type from the iterator
    let elementType = try extractIteratorElementType(iteratorType)
    
    // 6. Check pattern exhaustiveness against element type
    try checkForLoopPatternExhaustiveness(pattern: pattern, elementType: elementType)
    
    // 7. Desugar the for loop
    return try desugarForLoop(
      pattern: pattern,
      typedIterable: typedIterable,
      iteratorType: iteratorType,
      elementType: elementType,
      body: body,
      needsIteratorCall: true  // Need to call iterator()
    )
  }

  /// Extracts the element type T from an iterator type.
  /// The iterator must have a next(self ref) [T]Option method.
  private func extractIteratorElementType(_ iteratorType: Type) throws -> Type {
    // Look up the next method on the iterator type
    guard let nextMethod = try lookupConcreteMethodSymbol(on: iteratorType, name: "next") else {
      throw SemanticError(.generic(
        "Iterator type \(iteratorType) missing next() method"
      ), line: currentLine)
    }
    
    // Verify the return type is [T]Option
    guard case .function(_, let returnType) = nextMethod.type else {
      throw SemanticError(.generic("Iterator.next() must be a function"), line: currentLine)
    }
    
    // Check if return type is Option<T>
    switch returnType {
    case .genericUnion(let template, let args) where template == "Option" && args.count == 1:
      return args[0]
    default:
      throw SemanticError(.generic(
        "Iterator.next() must return [T]Option, got \(returnType)"
      ), line: currentLine)
    }
  }

  /// Checks that the for loop pattern is exhaustive for the element type.
  private func checkForLoopPatternExhaustiveness(pattern: PatternNode, elementType: Type) throws {
    // For simple variable bindings and wildcards, they are always exhaustive
    switch pattern {
    case .variable, .wildcard:
      return
    case .unionCase:
      // For union case patterns, we need to check exhaustiveness
      // This is a simplified check - a full implementation would use the exhaustiveness checker
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive for element type \(elementType). Use a simple variable binding."
      ), line: currentLine)
    case .booleanLiteral, .integerLiteral, .stringLiteral:
      throw SemanticError(.generic(
        "For loop pattern must be exhaustive. Literal patterns are not exhaustive."
      ), line: currentLine)
    }
  }

  /// Desugars a for loop into let + while + match.
  /// - Parameters:
  ///   - needsIteratorCall: If true, calls iterator() on the iterable. If false, uses the expression directly as the iterator.
  private func desugarForLoop(
    pattern: PatternNode,
    typedIterable: TypedExpressionNode,
    iteratorType: Type,
    elementType: Type,
    body: ExpressionNode,
    needsIteratorCall: Bool
  ) throws -> TypedExpressionNode {
    // Generate unique iterator variable name
    let iterVarName = "__koral_iter_\(synthesizedTempIndex)"
    synthesizedTempIndex += 1
    
    // Create iterator symbol (mutable)
    let iterSymbol = Symbol(name: iterVarName, type: iteratorType, kind: .variable(.MutableValue))
    
    // Build the iterator initialization expression
    let iteratorInit: TypedExpressionNode
    if needsIteratorCall {
      // Build: iterable.iterator()
      iteratorInit = try buildIteratorCall(typedIterable: typedIterable, iteratorType: iteratorType)
    } else {
      // Use the expression directly as the iterator
      iteratorInit = typedIterable
    }
    
    // Enter a new scope for the let expression
    return try withNewScope {
      // Define the iterator variable in scope
      currentScope.define(iterVarName, iteratorType, mutable: true)
      
      // Build: __koral_iter_N.next()
      let iterVarExpr = TypedExpressionNode.variable(identifier: iterSymbol)
      let iterRefExpr = TypedExpressionNode.referenceExpression(
        expression: iterVarExpr,
        type: .reference(inner: iteratorType)
      )
      let nextCall = try buildNextCall(iterRef: iterRefExpr, elementType: elementType)
      
      // Build the match expression body
      // We need to enter a new scope for the pattern bindings
      let matchExpr = try buildForLoopMatchExpression(
        nextCall: nextCall,
        pattern: pattern,
        elementType: elementType,
        body: body
      )
      
      // Build: while true then match
      loopDepth += 1
      let whileExpr = TypedExpressionNode.whileExpression(
        condition: .booleanLiteral(value: true, type: .bool),
        body: matchExpr,
        type: .void
      )
      loopDepth -= 1
      
      // Build: let mut __iter = iterator() then while ...
      return .letExpression(
        identifier: iterSymbol,
        value: iteratorInit,
        body: whileExpr,
        type: .void
      )
    }
  }

  /// Builds the iterator() method call on the iterable.
  private func buildIteratorCall(
    typedIterable: TypedExpressionNode,
    iteratorType: Type
  ) throws -> TypedExpressionNode {
    // Look up the iterator method
    guard let iteratorMethod = try lookupConcreteMethodSymbol(on: typedIterable.type, name: "iterator") else {
      throw SemanticError(.generic("iterator() method not found"), line: currentLine)
    }
    
    // Build method reference
    let methodRef = TypedExpressionNode.methodReference(
      base: typedIterable,
      method: iteratorMethod,
      typeArgs: nil,
      type: iteratorMethod.type
    )
    
    // Build call
    return .call(callee: methodRef, arguments: [], type: iteratorType)
  }

  /// Builds the next() method call on the iterator reference.
  private func buildNextCall(
    iterRef: TypedExpressionNode,
    elementType: Type
  ) throws -> TypedExpressionNode {
    // Get the iterator type from the reference
    guard case .reference(let iteratorType) = iterRef.type else {
      throw SemanticError(.generic("Expected reference to iterator"), line: currentLine)
    }
    
    // Look up the next method
    guard let nextMethod = try lookupConcreteMethodSymbol(on: iteratorType, name: "next") else {
      throw SemanticError(.generic("next() method not found"), line: currentLine)
    }
    
    // Build method reference
    let methodRef = TypedExpressionNode.methodReference(
      base: iterRef,
      method: nextMethod,
      typeArgs: nil,
      type: nextMethod.type
    )
    
    // The return type is [T]Option
    let optionType = Type.genericUnion(template: "Option", args: [elementType])
    
    // Build call
    return .call(callee: methodRef, arguments: [], type: optionType)
  }

  /// Builds the match expression for the for loop body.
  private func buildForLoopMatchExpression(
    nextCall: TypedExpressionNode,
    pattern: PatternNode,
    elementType: Type,
    body: ExpressionNode
  ) throws -> TypedExpressionNode {
    // Build Some case pattern with the user's pattern
    let somePattern = try buildSomePattern(userPattern: pattern, elementType: elementType)
    
    // Type check the body in a new scope with pattern bindings
    let typedBody = try withNewScope {
      // Bind pattern variables
      try bindPatternVariables(pattern: pattern, type: elementType)
      
      // Type check body
      loopDepth += 1
      let result = try inferTypedExpression(body)
      loopDepth -= 1
      return result
    }
    
    // Build None case with break
    let nonePattern = TypedPattern.unionCase(caseName: "None", tagIndex: 0, elements: [])
    let breakExpr = TypedExpressionNode.blockExpression(
      statements: [.break],
      finalExpression: nil,
      type: .void
    )
    
    // Build match cases
    let someCase = TypedMatchCase(pattern: somePattern, body: typedBody)
    let noneCase = TypedMatchCase(pattern: nonePattern, body: breakExpr)
    
    return .matchExpression(
      subject: nextCall,
      cases: [someCase, noneCase],
      type: .void
    )
  }

  /// Builds the Some pattern wrapping the user's pattern.
  private func buildSomePattern(userPattern: PatternNode, elementType: Type) throws -> TypedPattern {
    let innerPattern = try convertPatternToTypedPattern(userPattern, expectedType: elementType)
    // Some has tag index 1 (None is 0, Some is 1 in Option)
    return .unionCase(caseName: "Some", tagIndex: 1, elements: [innerPattern])
  }

  /// Converts an AST pattern to a typed pattern.
  private func convertPatternToTypedPattern(_ pattern: PatternNode, expectedType: Type) throws -> TypedPattern {
    switch pattern {
    case .variable(let name, let mutable, _):
      let varKind: VariableKind = mutable ? .MutableValue : .Value
      let symbol = Symbol(name: name, type: expectedType, kind: .variable(varKind))
      return .variable(symbol: symbol)
    case .wildcard:
      return .wildcard
    case .booleanLiteral(let value, _):
      return .booleanLiteral(value: value)
    case .integerLiteral(let value, _, _):
      return .integerLiteral(value: value)
    case .stringLiteral(let value, _):
      return .stringLiteral(value: value)
    case .unionCase(let caseName, let elements, _):
      let typedElements = try elements.map { elem -> TypedPattern in
        // For union case elements, we need to determine the expected type
        // This is a simplified implementation
        try convertPatternToTypedPattern(elem, expectedType: .void)
      }
      return .unionCase(caseName: caseName, tagIndex: 0, elements: typedElements)
    }
  }

  /// Binds pattern variables in the current scope.
  private func bindPatternVariables(pattern: PatternNode, type: Type) throws {
    switch pattern {
    case .variable(let name, let mutable, _):
      currentScope.define(name, type, mutable: mutable)
    case .wildcard, .booleanLiteral, .integerLiteral, .stringLiteral:
      // No variables to bind
      break
    case .unionCase(_, let elements, _):
      // For union cases, we would need to bind nested variables
      // This is a simplified implementation
      for elem in elements {
        try bindPatternVariables(pattern: elem, type: .void)
      }
    }
  }

  private func checkIntrinsicCall(name: String, arguments: [ExpressionNode]) throws
    -> TypedExpressionNode?
  {
    switch name {
    case "alloc_memory":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      // Handle generics? [T]alloc_memory
      // The parser doesn't pass generic args here directly in Call expression?
      // Wait, explicit generic call .generic(fn, args) is distinct from call?
      // In AST, Call is (callee, arguments). If callee is .generic(base, args), we catch it in generic instantiation.
      // But for intrinsic alloc_memory, we might need to know T.
      // Let's assume Koral's `[Int]alloc_memory(2)` resolves to `alloc_memory` with a generic instance.
      // If `alloc_memory` is defined as `intrinsic let [T]alloc_memory...`, standard resolution might find it.
      // But we want to bypass that.
      // Strategy: If `callee` is `identifier`, and `currentScope` has `alloc_memory`, it's the generic template.
      // We need to support `[Int]alloc_memory(...)`.
      // If so, `callee` is NOT `identifier`, it is `generic(base, args)`.
      // `inferTypedExpression` handles `.generic` by instantiating.
      // We should intercept `generic` too or let it instantiate and then check the name?
      // If we let it instantiate, we get a function. Then we call it.
      // So `callee` will be a `TypedExpressionNode`? No, `callee` in `checkIntrinsicCall` is `ExpressionNode` (identifier).
      return nil  // handled in generic inst for now or handled after resolution?

    // Non-generic intrinsics
    case "exit":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let code = try inferTypedExpression(arguments[0])
      if code.type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: code.type.description)
      }
      return .intrinsicCall(.exit(code: code))
    case "abort":
      guard arguments.count == 0 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 0, got: arguments.count)
      }
      return .intrinsicCall(.abort)

    // Low-level IO intrinsics (minimal set using file descriptors)
    case "fwrite":
      guard arguments.count == 3 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 3, got: arguments.count)
      }
      let ptr = try inferTypedExpression(arguments[0])
      let len = try inferTypedExpression(arguments[1])
      let fd = try inferTypedExpression(arguments[2])
      guard case .pointer(let elem) = ptr.type, elem == .uint8 else {
        throw SemanticError.typeMismatch(expected: "[UInt8]Pointer", got: ptr.type.description)
      }
      if len.type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: len.type.description)
      }
      if fd.type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: fd.type.description)
      }
      return .intrinsicCall(.fwrite(ptr: ptr, len: len, fd: fd))

    case "fgetc":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let fd = try inferTypedExpression(arguments[0])
      if fd.type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: fd.type.description)
      }
      return .intrinsicCall(.fgetc(fd: fd))

    case "fflush":
      guard arguments.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: name, expected: 1, got: arguments.count)
      }
      let fd = try inferTypedExpression(arguments[0])
      if fd.type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: fd.type.description)
      }
      return .intrinsicCall(.fflush(fd: fd))

    default: return nil
    }
  }

  private func checkIntrinsicPointerMethod(
    base: TypedExpressionNode, method: Symbol, args: [ExpressionNode]
  ) throws -> TypedExpressionNode? {
    // method.name is mangled (e.g. Pointer_I_init). Extract the method name.
    var name = method.name
    if name.hasPrefix("Pointer_") {
      if let idx = name.lastIndex(of: "_") {
        name = String(name[name.index(after: idx)...])
      }
    }

    guard case .pointer(let elementType) = base.type else { return nil }

    switch name {
    case "init":
      guard args.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: "init", expected: 1, got: args.count)
      }
      var val = try inferTypedExpression(args[0])
      val = coerceLiteral(val, to: elementType)
      if val.type != elementType {
        throw SemanticError.typeMismatch(
          expected: elementType.description, got: val.type.description)
      }
      return .intrinsicCall(.ptrInit(ptr: base, val: val))
    case "deinit":
      guard args.count == 0 else {
        throw SemanticError.invalidArgumentCount(function: "deinit", expected: 0, got: args.count)
      }
      return .intrinsicCall(.ptrDeinit(ptr: base))
    case "peek":
      guard args.count == 0 else {
        throw SemanticError.invalidArgumentCount(function: "peek", expected: 0, got: args.count)
      }
      return .intrinsicCall(.ptrPeek(ptr: base))
    case "offset":
      guard args.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: "offset", expected: 1, got: args.count)
      }
      let offset = try inferTypedExpression(args[0])
      if offset.type != .int {
        throw SemanticError.typeMismatch(expected: "Int", got: offset.type.description)
      }
      return .intrinsicCall(.ptrOffset(ptr: base, offset: offset))
    case "take":
      guard args.count == 0 else {
        throw SemanticError.invalidArgumentCount(function: "take", expected: 0, got: args.count)
      }
      return .intrinsicCall(.ptrTake(ptr: base))
    case "replace":
      guard args.count == 1 else {
        throw SemanticError.invalidArgumentCount(function: "replace", expected: 1, got: args.count)
      }
      var val = try inferTypedExpression(args[0])
      val = coerceLiteral(val, to: elementType)
      if val.type != elementType {
        throw SemanticError.typeMismatch(
          expected: elementType.description, got: val.type.description)
      }
      return .intrinsicCall(.ptrReplace(ptr: base, val: val))
    default:
      return nil
    }
  }

  private func checkIntrinsicPointerStaticMethod(
    typeName: String, methodName: String, args: [ExpressionNode]
  ) throws -> TypedExpressionNode? {
    // Handle Pointer.bits() static method
    if methodName == "bits" {
      guard args.count == 0 else {
        throw SemanticError.invalidArgumentCount(function: "bits", expected: 0, got: args.count)
      }
      return .intrinsicCall(.ptrBits)
    }
    return nil
  }

  private func checkIntrinsicFloatMethod(
    base: TypedExpressionNode, method: Symbol, args: [ExpressionNode]
  ) throws -> TypedExpressionNode? {
    // Extract the method name from mangled name (e.g., "Float32_to_bits" -> "to_bits")
    var name = method.name
    if name.hasPrefix("Float32_") {
      name = String(name.dropFirst("Float32_".count))
    } else if name.hasPrefix("Float64_") {
      name = String(name.dropFirst("Float64_".count))
    } else if let idx = name.lastIndex(of: "_") {
      name = String(name[name.index(after: idx)...])
    }

    switch base.type {
    case .float32:
      switch name {
      case "to_bits":
        guard args.count == 0 else {
          throw SemanticError.invalidArgumentCount(function: "to_bits", expected: 0, got: args.count)
        }
        return .intrinsicCall(.float32Bits(value: base))
      default:
        return nil
      }
    case .float64:
      switch name {
      case "to_bits":
        guard args.count == 0 else {
          throw SemanticError.invalidArgumentCount(function: "to_bits", expected: 0, got: args.count)
        }
        return .intrinsicCall(.float64Bits(value: base))
      default:
        return nil
      }
    default:
      return nil
    }
  }

  // 新增用于返回带类型的语句的检查函数
  private func checkStatement(_ stmt: StatementNode) throws -> TypedStatementNode {
    do {
      return try checkStatementInternal(stmt)
    } catch let e as SemanticError {
      throw e
    }
  }

  private func checkStatementInternal(_ stmt: StatementNode) throws -> TypedStatementNode {
    switch stmt {
    case .variableDeclaration(let name, let typeNode, let value, let mutable, let line):
      self.currentLine = line
      var typedValue = try inferTypedExpression(value)
      let type: Type

      if let typeNode = typeNode {
        type = try resolveTypeNode(typeNode)
        typedValue = coerceLiteral(typedValue, to: type)
        if typedValue.type != .never && typedValue.type != type {
          throw SemanticError.typeMismatch(
            expected: type.description, got: typedValue.type.description)
        }
      } else {
        type = typedValue.type
      }

      currentScope.define(name, type, mutable: mutable)
      return .variableDeclaration(
        identifier: Symbol(
          name: name, type: type, kind: mutable ? .variable(.MutableValue) : .variable(.Value)),
        value: typedValue,
        mutable: mutable
      )

    case .assignment(let target, let value, let line):
      self.currentLine = line
      // Lower `x[i] = v` into a call to `x.__update_at(i, v)`.
      if case .subscriptExpression(let baseExpr, let argExprs) = target {
        let typedBase = try inferTypedExpression(baseExpr)
        let typedArgs = try argExprs.map { try inferTypedExpression($0) }

        // Resolve expected value type from `__update_at`.
        let (_, _, expectedValueType) = try resolveSubscriptUpdateMethod(
          base: typedBase, args: typedArgs)

        // Evaluate base (by reference), args, rhs once.
        if typedBase.valueCategory != .lvalue {
          throw SemanticError.invalidOperation(
            op: "implicit ref", type1: typedBase.type.description, type2: "rvalue")
        }
        let baseRefType: Type = .reference(inner: typedBase.type)
        let baseRefExpr: TypedExpressionNode = .referenceExpression(
          expression: typedBase, type: baseRefType)
        let baseSym = nextSynthSymbol(prefix: "sub_base", type: baseRefType)
        var stmts: [TypedStatementNode] = [
          .variableDeclaration(identifier: baseSym, value: baseRefExpr, mutable: false)
        ]

        var argSyms: [Symbol] = []
        for a in typedArgs {
          let s = nextSynthSymbol(prefix: "sub_idx", type: a.type)
          argSyms.append(s)
          stmts.append(.variableDeclaration(identifier: s, value: a, mutable: false))
        }

        var typedValue = try inferTypedExpression(value)
        typedValue = coerceLiteral(typedValue, to: expectedValueType)
        if typedValue.type != .never && typedValue.type != expectedValueType {
          throw SemanticError.typeMismatch(
            expected: expectedValueType.description, got: typedValue.type.description)
        }
        let valSym = nextSynthSymbol(prefix: "sub_val", type: typedValue.type)
        stmts.append(.variableDeclaration(identifier: valSym, value: typedValue, mutable: false))

        let baseVar: TypedExpressionNode = .variable(identifier: baseSym)
        let argVars: [TypedExpressionNode] = argSyms.map { .variable(identifier: $0) }
        let (updateMethod, finalBase, _) = try resolveSubscriptUpdateMethod(
          base: baseVar, args: argVars)

        let callee: TypedExpressionNode = .methodReference(
          base: finalBase,
          method: updateMethod,
          typeArgs: nil,
          type: updateMethod.type
        )
        let callExpr: TypedExpressionNode = .call(
          callee: callee,
          arguments: argVars + [.variable(identifier: valSym)],
          type: .void
        )
        stmts.append(.expression(callExpr))

        return .expression(.blockExpression(statements: stmts, finalExpression: nil, type: .void))
      }

      let typedTarget = try resolveLValue(target)
      var typedValue = try inferTypedExpression(value)
      typedValue = coerceLiteral(typedValue, to: typedTarget.type)

      if typedValue.type != .never && typedTarget.type != typedValue.type {
        throw SemanticError.typeMismatch(
          expected: typedTarget.type.description, got: typedValue.type.description)
      }

      return .assignment(target: typedTarget, value: typedValue)

    case .compoundAssignment(let target, let op, let value, let line):
      self.currentLine = line
      // Lower `x[i] op= v` into a call to `x.__update_at(i, deref x[i] op v)`.
      if case .subscriptExpression(let baseExpr, let argExprs) = target {
        let typedBase = try inferTypedExpression(baseExpr)
        let typedArgs = try argExprs.map { try inferTypedExpression($0) }

        // Evaluate base (by reference), args once.
        if typedBase.valueCategory != .lvalue {
          throw SemanticError.invalidOperation(
            op: "implicit ref", type1: typedBase.type.description, type2: "rvalue")
        }
        let baseRefType: Type = .reference(inner: typedBase.type)
        let baseRefExpr: TypedExpressionNode = .referenceExpression(
          expression: typedBase, type: baseRefType)
        let baseSym = nextSynthSymbol(prefix: "sub_base", type: baseRefType)
        var stmts: [TypedStatementNode] = [
          .variableDeclaration(identifier: baseSym, value: baseRefExpr, mutable: false)
        ]

        var argSyms: [Symbol] = []
        for a in typedArgs {
          let s = nextSynthSymbol(prefix: "sub_idx", type: a.type)
          argSyms.append(s)
          stmts.append(.variableDeclaration(identifier: s, value: a, mutable: false))
        }

        let baseVar: TypedExpressionNode = .variable(identifier: baseSym)
        let argVars: [TypedExpressionNode] = argSyms.map { .variable(identifier: $0) }
        let readRef = try resolveSubscript(base: baseVar, args: argVars)

        let elementType: Type
        let oldValueExpr: TypedExpressionNode
        if case .reference(let inner) = readRef.type {
          elementType = inner
          oldValueExpr = .derefExpression(expression: readRef, type: inner)
        } else {
          elementType = readRef.type
          oldValueExpr = readRef
        }
        let oldSym = nextSynthSymbol(prefix: "sub_old", type: elementType)
        stmts.append(.variableDeclaration(identifier: oldSym, value: oldValueExpr, mutable: false))

        var typedRhs = try inferTypedExpression(value)
        typedRhs = coerceLiteral(typedRhs, to: elementType)
        if typedRhs.type != .never && typedRhs.type != elementType {
          throw SemanticError.typeMismatch(
            expected: elementType.description, got: typedRhs.type.description)
        }

        let _ = try checkArithmeticOp(compoundOpToArithmeticOp(op), elementType, typedRhs.type)
        let rhsSym = nextSynthSymbol(prefix: "sub_rhs", type: typedRhs.type)
        stmts.append(.variableDeclaration(identifier: rhsSym, value: typedRhs, mutable: false))

        let newValueExpr: TypedExpressionNode = .arithmeticExpression(
          left: .variable(identifier: oldSym),
          op: compoundOpToArithmeticOp(op),
          right: .variable(identifier: rhsSym),
          type: elementType
        )

        let (updateMethod, finalBase, expectedValueType) = try resolveSubscriptUpdateMethod(
          base: baseVar, args: argVars)
        if expectedValueType != elementType {
          throw SemanticError.typeMismatch(
            expected: expectedValueType.description, got: elementType.description)
        }
        let callee: TypedExpressionNode = .methodReference(
          base: finalBase, method: updateMethod, typeArgs: nil, type: updateMethod.type)
        let callExpr: TypedExpressionNode = .call(
          callee: callee,
          arguments: argVars + [newValueExpr],
          type: .void
        )
        stmts.append(.expression(callExpr))

        return .expression(.blockExpression(statements: stmts, finalExpression: nil, type: .void))
      }

      let typedTarget = try resolveLValue(target)
      let typedValue = coerceLiteral(try inferTypedExpression(value), to: typedTarget.type)
      let _ = try checkArithmeticOp(compoundOpToArithmeticOp(op), typedTarget.type, typedValue.type)
      return .compoundAssignment(target: typedTarget, operator: op, value: typedValue)

    case .expression(let expr, let line):
      self.currentLine = line
      return .expression(try inferTypedExpression(expr))

    case .return(let value, let line):
      self.currentLine = line
      guard let returnType = currentFunctionReturnType else {
        throw SemanticError.invalidOperation(op: "return outside of function", type1: "", type2: "")
      }

      if let value = value {
        if returnType == .void {
          throw SemanticError.typeMismatch(expected: "Void", got: "non-Void")
        }

        var typedValue = try inferTypedExpression(value)
        typedValue = coerceLiteral(typedValue, to: returnType)
        if typedValue.type != .never && typedValue.type != returnType {
          throw SemanticError.typeMismatch(
            expected: returnType.description, got: typedValue.type.description)
        }
        return .return(value: typedValue)
      }

      if returnType != .void {
        throw SemanticError.typeMismatch(expected: returnType.description, got: "Void")
      }
      return .return(value: nil)

    case .break(let line):
      self.currentLine = line
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "break outside of while", type1: "", type2: "")
      }
      return .break

    case .continue(let line):
      self.currentLine = line
      if loopDepth <= 0 {
        throw SemanticError.invalidOperation(op: "continue outside of while", type1: "", type2: "")
      }
      return .continue
    }
  }

  private func resolveLValue(_ expr: ExpressionNode) throws -> TypedExpressionNode {
    switch expr {
    case .identifier(let name):
      guard let type = currentScope.lookup(name) else {
        throw SemanticError.undefinedVariable(name)
      }
      guard currentScope.isMutable(name) else { throw SemanticError.assignToImmutable(name) }
      return .variable(identifier: Symbol(name: name, type: type, kind: .variable(.MutableValue)))

    case .memberPath(let base, let path):
      // Check if base evaluates to a Reference type (RValue allowed)
      // OR if base resolves to an LValue (Mut Value required)

      let inferredBase = try inferTypedExpression(base)
      // Optimization: Peel auto-deref for lvalue resolution
      let typedBase: TypedExpressionNode
      if case .derefExpression(let inner, _) = inferredBase {
        typedBase = inner
      } else {
        typedBase = inferredBase
      }

      // Now resolve path members on typedBase.
      var currentType = typedBase.type
      var resolvedPath: [Symbol] = []

      // Wait, memberPath AST implementation is flat?
      // `case memberPath(base: ExpressionNode, path: [String])`
      // Yes.

      for memberName in path {
        // Unwrap reference if needed
        if case .reference(let inner) = currentType { currentType = inner }

        // Handle concrete structure types
        if case .structure(_, let members, _) = currentType {
          guard let member = members.first(where: { $0.name == memberName }) else {
            throw SemanticError.undefinedMember(memberName, currentType.description)
          }

          if !member.mutable {
            // Can we mutate immutable member?
            // If struct is mutable (LValue), then immutable fields are still immutable.
            throw SemanticError.assignToImmutable(memberName)
          }

          resolvedPath.append(
            Symbol(name: member.name, type: member.type, kind: .variable(.MutableValue)))
          currentType = member.type
          continue
        }
        
        // Handle genericStruct types - look up member from template
        if case .genericStruct(let templateName, let typeArgs) = currentType {
          guard let template = currentScope.lookupGenericStructTemplate(templateName) else {
            throw SemanticError.undefinedType(templateName)
          }
          
          // Create type substitution map
          var substitution: [String: Type] = [:]
          for (i, param) in template.typeParameters.enumerated() {
            if i < typeArgs.count {
              substitution[param.name] = typeArgs[i]
            }
          }
          
          // Look up member in template
          guard let param = template.parameters.first(where: { $0.name == memberName }) else {
            throw SemanticError.undefinedMember(memberName, currentType.description)
          }
          
          if !param.mutable {
            throw SemanticError.assignToImmutable(memberName)
          }
          
          // Resolve member type with substitution
          let memberType = try withNewScope {
            for (paramName, paramType) in substitution {
              try currentScope.defineType(paramName, type: paramType)
            }
            return try resolveTypeNode(param.type)
          }
          
          resolvedPath.append(
            Symbol(name: param.name, type: memberType, kind: .variable(.MutableValue)))
          currentType = memberType
          continue
        }

        throw SemanticError.invalidOperation(
          op: "member access on non-struct", type1: currentType.description, type2: "")
      }
      return .memberPath(source: typedBase, path: resolvedPath)

    case .subscriptExpression(_, _):
      // Direct assignment to `x[i]` is lowered to `__update_at` in statement checking.
      // Treat subscript as an invalid assignment target here.
      throw SemanticError.invalidOperation(op: "assignment target", type1: "subscript", type2: "")

    case .derefExpression(_):
      // `deref r = ...` is intentionally disallowed.
      // Writes must go through explicit setters like `__update_at` (for subscripts).
      throw SemanticError.invalidOperation(op: "assignment target", type1: "deref", type2: "")

    default:
      throw SemanticError.invalidOperation(
        op: "assignment target", type1: String(describing: expr), type2: "")
    }
  }

  private func resolveSubscript(base: TypedExpressionNode, args: [TypedExpressionNode]) throws
    -> TypedExpressionNode
  {
    let methodName = "__at"
    let type = base.type

    // Unwrap reference
    let structType: Type
    if case .reference(let inner) = type { structType = inner } else { structType = type }

    // Get the type name for error messages
    let typeName: String
    switch structType {
    case .structure(let name, _, _):
      typeName = name
    case .genericStruct(let template, _):
      typeName = template
    default:
      throw SemanticError.invalidOperation(op: "subscript", type1: type.description, type2: "")
    }

    var methodSymbol: Symbol? = nil
    
    // Try to look up method on concrete type first
    if case .structure(let name, _, _) = structType {
      if let extensions = extensionMethods[name], let sym = extensions[methodName] {
        methodSymbol = sym
      }
    }
    
    // If not found, try generic type lookup
    if methodSymbol == nil {
      if case .genericStruct(let templateName, let typeArgs) = structType {
        if let extensions = genericExtensionMethods[templateName],
           let ext = extensions.first(where: { $0.method.name == methodName })
        {
          methodSymbol = try resolveGenericExtensionMethod(
            baseType: structType,
            templateName: templateName,
            typeArgs: typeArgs,
            methodInfo: ext
          )
        }
      }
    }

    guard let method = methodSymbol else {
      throw SemanticError.undefinedMember(methodName, typeName)
    }

    guard case .function(let params, let returns) = method.type else { fatalError() }

    var finalBase = base
    if let firstParam = params.first {
      if firstParam.type != base.type {
        if case .reference(let inner) = firstParam.type, inner == base.type {
          // Implicit Ref for self
          finalBase = .referenceExpression(expression: base, type: firstParam.type)
        }
      }
    }

    if args.count != params.count - 1 {
      throw SemanticError.invalidArgumentCount(
        function: methodName, expected: params.count - 1, got: args.count)
    }

    for (arg, param) in zip(args, params.dropFirst()) {
      if arg.type != param.type {
        throw SemanticError.typeMismatch(
          expected: param.type.description, got: arg.type.description)
      }
    }

    // Determine return type (auto deref logic REMOVED for clarity, we return what method returns)
    // Actually, standard subscript behavior:
    // If method returns Ref, subscript expression is LValue of inner type.
    // But `type` property of TypedExpressionNode usually reflects the Value type for LValues?
    // Checkout `resolveLValue`...

    // If `__at` returns `Int ref`, then the expression has type `Int ref`.
    // If we strip ref here, we say expression is `Int`.
    // But `CodeGen` needs to know if it's a pointer or value.

    // Let's modify behavior strictly:
    // Subscript expression type matches method return type exactly.
    // Then if it is Ref, usage sites decide to deref.

    return .subscriptExpression(base: finalBase, arguments: args, method: method, type: returns)
  }

  private func compoundOpToArithmeticOp(_ op: CompoundAssignmentOperator) -> ArithmeticOperator {
    switch op {
    case .plus: return .plus
    case .minus: return .minus
    case .multiply: return .multiply
    case .divide: return .divide
    case .modulo: return .modulo
    }
  }

  // 将 TypeNode 解析为语义层 Type，支持函数参数/返回位置的一层 reference(T)
  private func resolveTypeNode(_ node: TypeNode) throws -> Type {
    switch node {
    case .identifier(let name):
      if traits[name] != nil {
        throw SemanticError.invalidOperation(op: "use trait as type", type1: name, type2: "")
      }
      guard let t = currentScope.resolveType(name) else {
        throw SemanticError.undefinedType(name)
      }
      return t
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
    }
  }

  private func checkPattern(_ pattern: PatternNode, subjectType: Type) throws -> (
    TypedPattern, [(String, Bool, Type)]
  ) {
    var bindings: [(String, Bool, Type)] = []

    switch pattern {
    case .integerLiteral(let val, let suffix, _):
      // Determine expected type from suffix or default to Int
      let expectedType: Type
      if let suffix = suffix {
        switch suffix {
        case .i: expectedType = .int
        case .i8: expectedType = .int8
        case .i16: expectedType = .int16
        case .i32: expectedType = .int32
        case .i64: expectedType = .int64
        case .u: expectedType = .uint
        case .u8: expectedType = .uint8
        case .u16: expectedType = .uint16
        case .u32: expectedType = .uint32
        case .u64: expectedType = .uint64
        case .f32, .f64:
          throw SemanticError.typeMismatch(expected: "integer type", got: suffix.rawValue)
        }
      } else {
        expectedType = .int
      }
      if subjectType != expectedType {
        throw SemanticError.typeMismatch(expected: expectedType.description, got: subjectType.description)
      }
      return (.integerLiteral(value: val), [])

    case .booleanLiteral(let val, _):
      if subjectType != .bool {
        throw SemanticError.typeMismatch(expected: "Bool", got: subjectType.description)
      }
      return (.booleanLiteral(value: val), [])

    case .stringLiteral(let value, let line):
      if isStringType(subjectType) {
        return (.stringLiteral(value: value), [])
      }
      if subjectType == .uint8 {
        guard let byte = singleByteASCII(from: value) else {
          throw SemanticError(
            .generic("String literal pattern must be exactly one ASCII byte when matching UInt8"),
            line: line)
        }
        return (.integerLiteral(value: String(byte)), [])
      }
      throw SemanticError.typeMismatch(expected: "String or UInt8", got: subjectType.description)

    case .wildcard(_):
      return (.wildcard, [])

    case .variable(let name, let mutable, _):
      // Bind variable to the subject
      let symbol = Symbol(
        name: name, type: subjectType, kind: .variable(mutable ? .MutableValue : .Value))
      return (.variable(symbol: symbol), [(name, mutable, subjectType)])

    case .unionCase(let caseName, let subPatterns, _):
      // Handle both concrete union and genericUnion types
      let typeName: String
      let cases: [UnionCase]
      
      switch subjectType {
      case .union(let name, let unionCases, _):
        typeName = name
        cases = unionCases
        
      case .genericUnion(let templateName, let typeArgs):
        // Look up the union template and substitute type parameters
        guard let template = currentScope.lookupGenericUnionTemplate(templateName) else {
          throw SemanticError.undefinedType(templateName)
        }
        
        typeName = templateName
        
        // Create substitution map
        var substitution: [String: Type] = [:]
        for (i, param) in template.typeParameters.enumerated() {
          substitution[param.name] = typeArgs[i]
        }
        
        // Resolve case parameter types with substitution
        cases = try template.cases.map { caseDef in
          let resolvedParams: [(name: String, type: Type)] = try caseDef.parameters.map { param in
            let resolvedType = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try resolveTypeNode(param.type)
            }
            return (name: param.name, type: resolvedType)
          }
          return UnionCase(name: caseDef.name, parameters: resolvedParams)
        }
        
      default:
        throw SemanticError.typeMismatch(expected: "Union Type", got: subjectType.description)
      }

      guard let caseIndex = cases.firstIndex(where: { $0.name == caseName }) else {
        throw SemanticError(.generic("Union case '\(caseName)' not found in type '\(typeName)'"))
      }
      let caseDef = cases[caseIndex]

      if caseDef.parameters.count != subPatterns.count {
        throw SemanticError.invalidArgumentCount(
          function: caseName, expected: caseDef.parameters.count, got: subPatterns.count)
      }

      var typedSubPatterns: [TypedPattern] = []
      for (idx, subPat) in subPatterns.enumerated() {
        let paramType = caseDef.parameters[idx].type
        let (typedSub, subBindings) = try checkPattern(subPat, subjectType: paramType)
        typedSubPatterns.append(typedSub)
        bindings.append(contentsOf: subBindings)
      }

      return (
        .unionCase(caseName: caseName, tagIndex: caseIndex, elements: typedSubPatterns), bindings
      )
    }
  }

  private func singleByteASCII(from value: String) -> UInt8? {
    let bytes = Array(value.utf8)
    guard bytes.count == 1 else { return nil }
    guard bytes[0] <= 0x7F else { return nil }
    return bytes[0]
  }

  private func unify(
    node: TypeNode, type: Type, inferred: inout [String: Type], typeParams: [String]
  ) throws {
    // print("Unify node: \(node) with type: \(type) (canonical: \(type.canonical))")
    switch node {
    case .identifier(let name):
      if typeParams.contains(name) {
        if let existing = inferred[name] {
          if existing != type {
            throw SemanticError.typeMismatch(expected: existing.description, got: type.description)
          }
        } else {
          inferred[name] = type
        }
      }
    case .inferredSelf:
      break
    case .reference(let inner):
      if case .reference(let innerType) = type {
        try unify(node: inner, type: innerType, inferred: &inferred, typeParams: typeParams)
      }
    case .generic(let base, let args):
      if case .pointer(let element) = type, base == "Pointer", args.count == 1 {
        try unify(node: args[0], type: element, inferred: &inferred, typeParams: typeParams)
      } else if case .genericStruct(let templateName, let typeArgs) = type {
        // Match against genericStruct type
        if templateName == base && typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      } else if case .genericUnion(let templateName, let typeArgs) = type {
        // Match against genericUnion type
        if templateName == base && typeArgs.count == args.count {
          for (argNode, argType) in zip(args, typeArgs) {
            try unify(node: argNode, type: argType, inferred: &inferred, typeParams: typeParams)
          }
        }
      }
    }
  }

  private func withNewScope<R>(_ body: () throws -> R) rethrows -> R {
    let previousScope = currentScope
    let previousTraitBounds = genericTraitBounds
    currentScope = currentScope.createChild()
    defer {
      currentScope = previousScope
      genericTraitBounds = previousTraitBounds
    }
    return try body()
  }

  private func isIntegerType(_ type: Type) -> Bool {
    switch type {
    case .int, .int8, .int16, .int32, .int64,
      .uint, .uint8, .uint16, .uint32, .uint64:
      return true
    default:
      return false
    }
  }

  private func isFloatType(_ type: Type) -> Bool {
    switch type {
    case .float32, .float64:
      return true
    default:
      return false
    }
  }

  private func isStringType(_ type: Type) -> Bool {
    switch type {
    case .structure(let name, _, _):
      return name == "String"
    default:
      return false
    }
  }

  // Coerce numeric literals to the expected numeric type for annotations/parameters.
  private func coerceLiteral(_ expr: TypedExpressionNode, to expected: Type) -> TypedExpressionNode
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

  private func checkArithmeticOp(_ op: ArithmeticOperator, _ lhs: Type, _ rhs: Type) throws
    -> Type
  {
    if lhs == rhs {
      if isIntegerType(lhs) { return lhs }
      if isFloatType(lhs) { return lhs }
    }
    throw SemanticError.invalidOperation(
      op: String(describing: op), type1: lhs.description, type2: rhs.description)
  }

  private func checkComparisonOp(_ op: ComparisonOperator, _ lhs: Type, _ rhs: Type) throws
    -> Type
  {
    if lhs == rhs {
      return .bool
    }
    throw SemanticError.invalidOperation(
      op: String(describing: op), type1: lhs.description, type2: rhs.description)
  }

  /// Resolve union cases for exhaustiveness checking.
  /// For generic unions, this looks up the template and substitutes type parameters.
  private func resolveUnionCasesForExhaustiveness(_ type: Type) -> [UnionCase]? {
    switch type {
    case .union(_, let cases, _):
      return cases
      
    case .genericUnion(let templateName, let typeArgs):
      // Look up the union template and substitute type parameters
      guard let template = currentScope.lookupGenericUnionTemplate(templateName) else {
        return nil
      }
      
      // Create substitution map
      var substitution: [String: Type] = [:]
      for (i, param) in template.typeParameters.enumerated() {
        if i < typeArgs.count {
          substitution[param.name] = typeArgs[i]
        }
      }
      
      // Resolve case parameter types with substitution
      do {
        let resolvedCases: [UnionCase] = try template.cases.map { caseDef in
          let resolvedParams: [(name: String, type: Type)] = try caseDef.parameters.map { param in
            let resolvedType = try withNewScope {
              for (paramName, paramType) in substitution {
                try currentScope.defineType(paramName, type: paramType)
              }
              return try resolveTypeNode(param.type)
            }
            return (name: param.name, type: resolvedType)
          }
          return UnionCase(name: caseDef.name, parameters: resolvedParams)
        }
        return resolvedCases
      } catch {
        return nil
      }
      
    default:
      return nil
    }
  }
}

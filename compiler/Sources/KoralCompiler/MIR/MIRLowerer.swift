import Foundation

final class MIRLowerer {
  private let program: MonomorphizedProgram
  private let context: CompilerContext

  init(program: MonomorphizedProgram, context: CompilerContext) {
    self.program = program
    self.context = context
  }

  func lower() -> MIRProgram {
    var globals: [MIRGlobal] = []
    var functions: [MIRFunction] = []

    for request in sortedVTableRequests() {
      globals.append(.traitVTable(makeTraitVTable(from: request)))
    }

    for node in program.globalNodes {
      switch node {
      case .foreignFunction(let identifier, let parameters):
        globals.append(.foreignFunction(identifier: identifier, parameters: parameters))
      case .foreignType(let identifier):
        globals.append(.foreignType(identifier: identifier))
      case .foreignStruct(let identifier, let fields):
        globals.append(.foreignStruct(identifier: identifier, fields: fields))
      case .foreignGlobalVariable(let identifier, let mutable):
        globals.append(.foreignGlobalVariable(identifier: identifier, mutable: mutable))
      case .globalVariable(let identifier, let value, let kind):
        let initializer = lowerGlobalInitializer(identifier: identifier, value: value)
        globals.append(.globalVariable(identifier: identifier, initializerFunction: initializer.identifier, kind: kind))
        functions.append(initializer)
      case .globalStructDeclaration(let identifier, let parameters):
        globals.append(.structDeclaration(identifier: identifier, parameters: parameters))
      case .globalEnumDeclaration(let identifier, let cases):
        globals.append(.enumDeclaration(identifier: identifier, cases: cases))
      case .globalFunction(let identifier, let parameters, let body):
        let kind = MIRFunctionKind.global
        globals.append(.function(identifier: identifier, parameters: parameters, kind: kind))
        if shouldLowerFunction(identifier: identifier) {
          functions.append(lowerFunction(identifier: identifier, parameters: parameters, body: body, kind: kind))
        }
      case .givenDeclaration(let type, let trait, let methods):
        globals.append(.given(type: type, trait: trait, methods: methods.map(\.identifier)))
        guard !context.containsGenericParameter(type) else { continue }
        for method in methods where shouldLowerFunction(identifier: method.identifier) {
          functions.append(
            lowerFunction(
              identifier: method.identifier,
              parameters: method.parameters,
              body: method.body,
              kind: .given(type: type, trait: trait)
            )
          )
        }
      case .genericTypeTemplate(let name), .genericFunctionTemplate(let name):
        globals.append(.templatePlaceholder(name: name))
      }
    }

    let loweredProgram = MIRProgram(
      globals: globals,
      functions: functions,
      context: context,
      staticMethodLookup: program.staticMethodLookup,
      traits: program.traits,
      receiverMethodDispatch: program.receiverMethodDispatch
    )
    return MIRReferenceAllocationPromoter(program: loweredProgram).promote()
  }

  private func sortedVTableRequests() -> [VtableRequest] {
    program.vtableRequests.sorted { lhs, rhs in
      vTableRequestSortKey(lhs) < vTableRequestSortKey(rhs)
    }
  }

  private func makeTraitVTable(from request: VtableRequest) -> MIRTraitVTable {
    let methods = makeTraitVTableMethods(for: request)
    return MIRTraitVTable(
      concreteType: request.concreteType,
      traitName: request.traitName,
      traitTypeArguments: request.traitTypeArgs,
      methods: methods
    )
  }

  private func makeTraitVTableMethods(for request: VtableRequest) -> [MIRTraitVTableMethod] {
    guard let orderedMethods = try? SemaUtils.orderedTraitMethods(
      request.traitName,
      traits: program.traits,
      currentLine: nil
    ) else {
      return []
    }

    let substitution = traitTypeParameterSubstitution(for: request)
    return orderedMethods.map { methodName, signature in
      let parameters = signature.parameters.map { parameter in
        MIRTraitVTableParameter(
          name: parameter.name,
          type: resolveVTableTypeNode(parameter.type, traitTypeParamSubstitution: substitution),
          isSelf: parameter.name == "self"
        )
      }
      return MIRTraitVTableMethod(
        name: methodName,
        returnType: resolveVTableTypeNode(signature.returnType, traitTypeParamSubstitution: substitution),
        parameters: parameters,
        selfByValue: isSelfByValueTraitSignature(signature)
      )
    }
  }

  private func traitTypeParameterSubstitution(for request: VtableRequest) -> [String: Type] {
    guard let traitInfo = program.traits[request.traitName], !traitInfo.typeParameters.isEmpty else {
      return [:]
    }
    var result: [String: Type] = [:]
    for (index, parameter) in traitInfo.typeParameters.enumerated() where index < request.traitTypeArgs.count {
      result[parameter.name] = request.traitTypeArgs[index]
    }
    return result
  }

  private func isSelfByValueTraitSignature(_ signature: TraitMethodSignature) -> Bool {
    guard let firstParam = signature.parameters.first, firstParam.name == "self" else {
      return false
    }
    if case .reference = firstParam.type {
      return false
    }
    return true
  }

  private func resolveVTableTypeNode(
    _ node: TypeNode,
    traitTypeParamSubstitution: [String: Type]
  ) -> Type? {
    switch node {
    case .identifier(let name):
      if let substituted = traitTypeParamSubstitution[name] {
        return substituted
      }
      if let builtinType = SemaUtils.resolveBuiltinType(name) {
        return builtinType
      }
      return resolveNominalVTableType(named: name)
    case .reference(let inner, let mutable):
      guard let resolved = resolveVTableTypeNode(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) else {
        return nil
      }
      return mutable ? .mutableReference(inner: resolved) : .reference(inner: resolved)
    case .weakReference(let inner, let mutable):
      guard let resolved = resolveVTableTypeNode(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) else {
        return nil
      }
      return mutable ? .mutableWeakReference(inner: resolved) : .weakReference(inner: resolved)
    case .pointer(let inner, let mutable):
      guard let resolved = resolveVTableTypeNode(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) else {
        return nil
      }
      return mutable ? .mutablePointer(element: resolved) : .pointer(element: resolved)
    case .generic(let base, let args):
      let resolvedArgs = args.compactMap {
        resolveVTableTypeNode($0, traitTypeParamSubstitution: traitTypeParamSubstitution)
      }
      guard resolvedArgs.count == args.count else { return nil }
      return resolveGenericVTableType(named: base, args: resolvedArgs)
    case .functionType(let paramTypes, let returnType):
      let resolvedParams = paramTypes.compactMap {
        resolveVTableTypeNode($0, traitTypeParamSubstitution: traitTypeParamSubstitution)
      }
      guard resolvedParams.count == paramTypes.count,
            let resolvedReturn = resolveVTableTypeNode(returnType, traitTypeParamSubstitution: traitTypeParamSubstitution) else {
        return nil
      }
      let params = resolvedParams.map { Parameter(type: $0, kind: .byVal) }
      return .function(parameters: params, returns: resolvedReturn)
    case .inferredSelf:
      return nil
    }
  }

  private func resolveNominalVTableType(named name: String) -> Type? {
    for node in program.globalNodes {
      switch node {
      case .globalStructDeclaration(let identifier, _), .foreignStruct(let identifier, _):
        guard nominalSymbol(identifier, matches: name), case .structure(let defId) = identifier.type else { continue }
        return .structure(defId: defId)
      case .globalEnumDeclaration(let identifier, _):
        guard nominalSymbol(identifier, matches: name), case .`enum`(let defId) = identifier.type else { continue }
        return .`enum`(defId: defId)
      default:
        continue
      }
    }

    if let defId = context.lookupDefId(modulePath: [], name: name, sourceFile: nil),
       let kind = context.getKind(defId) {
      switch kind {
      case .type(.structure): return .structure(defId: defId)
      case .type(.`enum`): return .`enum`(defId: defId)
      default: break
      }
    }

    return nil
  }

  private func resolveGenericVTableType(named name: String, args: [Type]) -> Type? {
    for node in program.globalNodes {
      switch node {
      case .globalStructDeclaration(let identifier, _), .foreignStruct(let identifier, _):
        if nominalSymbol(identifier, matches: name) {
          return .genericStruct(template: name, args: args)
        }
      case .globalEnumDeclaration(let identifier, _):
        if nominalSymbol(identifier, matches: name) {
          return .genericEnum(template: name, args: args)
        }
      default:
        continue
      }
    }

    if let defId = context.lookupDefId(modulePath: [], name: name, sourceFile: nil),
       let kind = context.getKind(defId) {
      switch kind {
      case .type(.structure), .genericTemplate(.structure):
        return .genericStruct(template: name, args: args)
      case .type(.`enum`), .genericTemplate(.`enum`):
        return .genericEnum(template: name, args: args)
      default:
        break
      }
    }

    return nil
  }

  private func nominalSymbol(_ symbol: Symbol, matches name: String) -> Bool {
    let symbolNames = [
      context.getName(symbol.defId),
      context.getQualifiedName(symbol.defId),
    ].compactMap { $0 }
    return symbolNames.contains { candidate in
      candidate == name || candidate.components(separatedBy: ".").last == name
    }
  }

  private func vTableRequestSortKey(_ request: VtableRequest) -> String {
    let args = request.traitTypeArgs.map { context.getDebugName($0) }.joined(separator: ",")
    return "\(request.traitName)<\(args)>|\(context.getDebugName(request.concreteType))"
  }

  private func shouldLowerFunction(identifier: Symbol) -> Bool {
    !context.containsGenericParameter(identifier.type)
  }

  private func lowerFunction(
    identifier: Symbol,
    parameters: [Symbol],
    body: TypedExpressionNode,
    kind: MIRFunctionKind
  ) -> MIRFunction {
    let builder = MIRFunctionBuilder(
      program: program,
      identifier: identifier,
      parameters: parameters,
      returnType: functionReturnType(identifier.type),
      kind: kind,
      body: body,
      context: context
    )
    return builder.lower()
  }

  private func lowerGlobalInitializer(identifier: Symbol, value: TypedExpressionNode) -> MIRFunction {
    let functionType = Type.function(parameters: [], returns: identifier.type)
    let initializer = context.createSymbol(
      name: "__mir_global_init_\(identifier.defId.id)",
      modulePath: context.getModulePath(identifier.defId) ?? [],
      sourceFile: context.getSourceFile(identifier.defId) ?? "<mir_global_init>",
      type: functionType,
      kind: .function,
      access: .private
    )
    return lowerFunction(identifier: initializer, parameters: [], body: value, kind: .global)
  }

  private func functionReturnType(_ type: Type) -> Type {
    guard case .function(_, let returns) = type else {
      return .void
    }
    return returns
  }

  static func lowerStandaloneLambdaFunction(
    program: MonomorphizedProgram,
    context: CompilerContext,
    parameters: [Symbol],
    captures: [CapturedVariable],
    body: TypedExpressionNode,
    type: Type
  ) -> MIRFunction {
    let uniqueName = UUID().uuidString.replacingOccurrences(of: "-", with: "_")
    let identifier = context.createSymbol(
      name: "__mir_codegen_lambda_\(uniqueName)",
      modulePath: [],
      sourceFile: "<mir_codegen_lambda>",
      type: type,
      kind: .function
    )
    let builder = MIRFunctionBuilder(
      program: program,
      identifier: identifier,
      parameters: parameters,
      capturedSymbols: captures.map(\.symbol),
      returnType: standaloneLambdaReturnType(type),
      kind: .global,
      body: body,
      context: context
    )
    return builder.lower()
  }

  private static func standaloneLambdaReturnType(_ type: Type) -> Type {
    guard case .function(_, let returns) = type else {
      return .void
    }
    return returns
  }
}

private func traitObjectTypeArguments(from receiverType: Type) -> [Type] {
  switch receiverType {
  case .reference(let inner), .mutableReference(let inner):
    return traitObjectTypeArguments(from: inner)
  case .traitObject(_, let typeArgs):
    return typeArgs
  default:
    return []
  }
}

private func ownershipUse(for expression: TypedExpressionNode) -> MIROwnershipUse {
  expression.valueCategory == .lvalue ? .copy : .move
}

private final class MIRFunctionBuilder {
  private struct MIRYieldTargetContext {
    let id: YieldTargetId
    let resultLocal: MIRLocalID?
    let joinBlock: MIRBlockID
    let baseScopeDepth: Int
  }

  private let program: MonomorphizedProgram
  private let identifier: Symbol
  private let parameters: [Symbol]
  private let capturedSymbols: [Symbol]
  private let returnType: Type
  private let kind: MIRFunctionKind
  private let body: TypedExpressionNode
  private let context: CompilerContext

  private let entryBlock = MIRBlockID(rawValue: 0)
  private var nextLocalID = 0
  private var nextBlockID = 0
  private var nextScopeID = 0
  private var locals: [MIRLocal] = []
  private var blocks: [MIRBasicBlock] = []
  private var currentBlockIndex = 0
  private var terminatedBlocks: Set<MIRBlockID> = []
  private var localByDefId: [UInt64: MIRLocalID] = [:]
  private var patternPlaceByDefId: [UInt64: MIRPlace] = [:]
  private var loopStack: [(continueBlock: MIRBlockID, breakBlock: MIRBlockID, scopeDepth: Int)] = []
  private var scopeStack: [MIRScopeID] = []
  private var finaliesByScope: [MIRScopeID: [TypedExpressionNode]] = [:]
  private var yieldTargetStack: [MIRYieldTargetContext] = []

  init(
    program: MonomorphizedProgram,
    identifier: Symbol,
    parameters: [Symbol],
    capturedSymbols: [Symbol] = [],
    returnType: Type,
    kind: MIRFunctionKind,
    body: TypedExpressionNode,
    context: CompilerContext
  ) {
    self.program = program
    self.identifier = identifier
    self.parameters = parameters
    self.capturedSymbols = capturedSymbols
    self.returnType = returnType
    self.kind = kind
    self.body = body
    self.context = context
  }

  func lower() -> MIRFunction {
    appendBlock()
    for parameter in parameters {
      let local = makeLocal(
        name: context.getName(parameter.defId) ?? "param_\(parameter.defId.id)",
        type: parameter.type,
        mutability: parameter.isMutable() ? .mutable : .immutable,
        storage: .parameter,
        symbol: parameter
      )
      localByDefId[parameter.defId.id] = local.id
      append(.declare(local.id))
    }

    for capture in capturedSymbols {
      let local = makeLocal(
        name: context.getName(capture.defId) ?? "capture_\(capture.defId.id)",
        type: capture.type,
        mutability: capture.isMutable() ? .mutable : .immutable,
        storage: .capture,
        symbol: capture
      )
      localByDefId[capture.defId.id] = local.id
      append(.declare(local.id))
    }

    let result = lowerExpression(body)
    finishImplicitReturn(result: result)

    return MIRFunction(
      identifier: identifier,
      parameters: parameters,
      returnType: returnType,
      kind: kind,
      entryBlock: entryBlock,
      locals: locals,
      blocks: blocks
    )
  }

  private func lowerLambdaFunction(
    parameters: [Symbol],
    captures: [CapturedVariable],
    body: TypedExpressionNode,
    type: Type
  ) -> MIRFunction {
    let identifier = context.createSymbol(
      name: "__mir_lambda_\(self.identifier.defId.id)_\(nextLocalID)_\(nextBlockID)",
      modulePath: [],
      sourceFile: "<mir_lambda>",
      type: type,
      kind: .function
    )
    let builder = MIRFunctionBuilder(
      program: program,
      identifier: identifier,
      parameters: parameters,
      capturedSymbols: captures.map(\.symbol),
      returnType: lambdaReturnType(type),
      kind: .global,
      body: body,
      context: context
    )
    return builder.lower()
  }

  private func lambdaReturnType(_ type: Type) -> Type {
    guard case .function(_, let returns) = type else {
      return .void
    }
    return returns
  }

  @discardableResult
  private func appendBlock() -> MIRBlockID {
    nextBlockID += 1
    let id = MIRBlockID(rawValue: nextBlockID - 1)
    blocks.append(MIRBasicBlock(id: id, statements: [], terminator: .unreachable))
    currentBlockIndex = blocks.count - 1
    return id
  }

  private func makeBlock() -> MIRBlockID {
    appendBlock()
  }

  private var currentBlockID: MIRBlockID {
    blocks[currentBlockIndex].id
  }

  private var currentBlockIsTerminated: Bool {
    terminatedBlocks.contains(currentBlockID)
  }

  private func setCurrentBlock(_ id: MIRBlockID) {
    guard let index = blocks.firstIndex(where: { $0.id == id }) else {
      return
    }
    currentBlockIndex = index
  }

  private func append(_ statement: MIRStatement) {
    guard !currentBlockIsTerminated else { return }
    blocks[currentBlockIndex].statements.append(statement)
  }

  private func terminate(_ terminator: MIRTerminator) {
    guard !currentBlockIsTerminated else { return }
    blocks[currentBlockIndex].terminator = terminator
    terminatedBlocks.insert(currentBlockID)
  }

  private func makeLocal(
    name: String,
    type: Type,
    mutability: MIRMutability,
    storage: MIRStorage,
    symbol: Symbol?
  ) -> MIRLocal {
    let id = MIRLocalID(rawValue: nextLocalID)
    nextLocalID += 1
    let local = MIRLocal(
      id: id,
      name: name,
      type: type,
      mutability: mutability,
      storage: storage,
      symbol: symbol
    )
    locals.append(local)
    return local
  }

  private func makeTemporary(type: Type, nameHint: String = "tmp") -> MIRLocal {
    makeLocal(
      name: "\(nameHint)_\(nextLocalID)",
      type: type,
      mutability: .mutable,
      storage: .temporary,
      symbol: nil
    )
  }

  private func makeScopeID() -> MIRScopeID {
    defer { nextScopeID += 1 }
    return MIRScopeID(rawValue: nextScopeID)
  }

  private func finishImplicitReturn(result: MIRExprResult?) {
    guard !currentBlockIsTerminated else { return }
    if body.type == .never || returnType == .never {
      terminate(.unreachable)
      return
    }
    if returnType == .void {
      terminate(.returnValue(nil))
      return
    }
    if let operand = returnOperand(for: result) {
      terminate(.returnValue(operand))
      return
    }
    terminate(.unreachable)
  }

  private func returnOperand(for result: MIRExprResult?) -> MIROperand? {
    if let operand = result?.operand {
      return operand
    }
    if let place = result?.place {
      if case .local(let local) = place {
        return .local(local)
      }
      return materialize(.placeRead(place, ownership: .copy), type: result?.type ?? returnType)
    }
    return nil
  }

  private func lowerExpression(_ expression: TypedExpressionNode) -> MIRExprResult? {
    guard !currentBlockIsTerminated else { return nil }

    switch expression {
    case .integerLiteral(let value, let type):
      return MIRExprResult(type: type, category: .rvalue, operand: .constant(.integer(value, type)), place: nil)
    case .floatLiteral(let value, let type):
      return MIRExprResult(type: type, category: .rvalue, operand: .constant(.float(value, type)), place: nil)
    case .stringLiteral(let value, let type):
      return MIRExprResult(type: type, category: .rvalue, operand: .constant(.string(value, type)), place: nil)
    case .interpolatedString:
      fatalError("Unsupported interpolated string reached MIR lowering")
    case .booleanLiteral(let value, _):
      return MIRExprResult(type: .bool, category: .rvalue, operand: .constant(.boolean(value)), place: nil)
    case .variable(let symbol):
      if case .function = symbol.kind {
        return MIRExprResult(type: symbol.type, category: .rvalue, operand: .function(symbol), place: nil)
      }
      let place = lowerPlace(expression) ?? .global(symbol.defId)
      return MIRExprResult(type: symbol.type, category: expression.valueCategory, operand: nil, place: place)
    case .blockExpression(let statements, let type):
      return lowerBlock(statements: statements, type: type)
    case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
      return lowerIfExpression(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch, type: type)
    case .ifPatternExpression(let subject, let pattern, let bindings, let thenBranch, let elseBranch, let type):
      return lowerIfPatternExpression(
        subject: subject,
        pattern: pattern,
        bindings: bindings,
        thenBranch: thenBranch,
        elseBranch: elseBranch,
        type: type
      )
    case .arithmeticExpression(let left, let op, let right, let type):
      return lowerBinary(left: left, right: right, type: type, operatorKind: .arithmetic(op, checked: true))
    case .wrappingArithmeticExpression(let left, let op, let right, let type):
      return lowerBinary(left: left, right: right, type: type, operatorKind: .wrappingArithmetic(op))
    case .wrappingShiftExpression(let left, let op, let right, let type):
      return lowerBinary(left: left, right: right, type: type, operatorKind: .wrappingShift(op))
    case .comparisonExpression(let left, let op, let right, let type):
      return lowerBinary(left: left, right: right, type: type, operatorKind: .comparison(op))
    case .isExpression(let subject, let pattern, let type):
      return lowerPatternTest(subject: subject, pattern: pattern, negated: false, type: type)
    case .isNotExpression(let subject, let pattern, let type):
      return lowerPatternTest(subject: subject, pattern: pattern, negated: true, type: type)
    case .andExpression(let left, let right, let type):
      return lowerShortCircuit(left: left, right: right, type: type, shortCircuitValue: false)
    case .orExpression(let left, let right, let type):
      return lowerShortCircuit(left: left, right: right, type: type, shortCircuitValue: true)
    case .bitwiseExpression(let left, let op, let right, let type):
      let checkedShift = op == .shiftLeft || op == .shiftRight
      return lowerBinary(left: left, right: right, type: type, operatorKind: .bitwise(op, checkedShift: checkedShift))
    case .notExpression(let inner, let type):
      return lowerUnary(inner: inner, type: type, operatorKind: .logicalNot)
    case .bitwiseNotExpression(let inner, let type):
      return lowerUnary(inner: inner, type: type, operatorKind: .bitwiseNot)
    case .castExpression(let inner, let type):
      let operand = lowerOperand(inner)
      let result = materialize(.cast(operand, to: type), type: type)
      return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
    case .typeConstruction(let identifier, _, let arguments, let type):
      let values = arguments.map { lowerValue($0) }
      let result = materialize(.aggregate(MIRAggregate(type: identifier.type, fields: values)), type: type)
      return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
    case .enumConstruction(let type, let caseName, let arguments):
      let values = arguments.map { lowerValue($0) }
      let result = materialize(.enumCase(MIREnumConstruction(type: type, caseName: caseName, arguments: values)), type: type)
      return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
    case .call(let callee, let arguments, let type):
      return lowerCall(callee: callee, arguments: arguments, type: type, original: expression)
    case .genericCall(let functionName, _, _, _):
      fatalError("Unsupported generic call reached MIR lowering: \(functionName)")
    case .staticMethodCall(let baseType, let methodName, _, _, _, _):
      fatalError("Unsupported static method call reached MIR lowering: \(methodName) on \(baseType)")
    case .methodReference(_, let method, _, _, _):
      let methodName = context.getName(method.defId) ?? "def#\(method.defId.id)"
      fatalError("Unsupported method reference value reached MIR lowering: \(methodName)")
    case .referenceExpression(let inner, let type):
      if let place = lowerPlace(inner) {
        let kind = referenceKind(for: type)
        let result = materialize(.ref(place, kind: kind, allocation: .stackBorrow), type: type)
        return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
      }
      if !context.containsGenericParameter(inner.type) {
        let sourceValue = lowerValue(inner)
        guard !currentBlockIsTerminated else { return nil }
        let sourceLocal = makeTemporary(type: inner.type, nameHint: "ref_source")
        append(.declare(sourceLocal.id))
        append(.assign(.local(sourceLocal.id), sourceValue))
        let result = materialize(
          .ref(.local(sourceLocal.id), kind: referenceKind(for: type), allocation: .heapOwned),
          type: type
        )
        return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
      }
      fatalError("Unsupported generic reference expression reached MIR lowering")
    case .ptrExpression(let inner, let type):
      if let place = lowerPlace(inner) {
        let result = materialize(.pointer(place), type: type)
        return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
      }
      fatalError("Unsupported pointer expression reached MIR lowering")
    case .derefExpression:
      if let place = lowerPlace(expression) {
        return MIRExprResult(type: expression.type, category: .lvalue, operand: nil, place: place)
      }
      if case .derefExpression = expression {
        fatalError("Unsupported deref expression value reached MIR lowering")
      }
      return nil
    case .memberPath:
      if let place = lowerPlace(expression) {
        return MIRExprResult(type: expression.type, category: expression.valueCategory, operand: nil, place: place)
      }
      fatalError("Unsupported member-path value reached MIR lowering")
    case .intrinsicCall(let intrinsic):
      return lowerIntrinsicCall(intrinsic)
    case .whenExpression(let subject, let cases, let type):
      if canLowerSimpleWhen(subject: subject, cases: cases) {
        return lowerSimpleWhenExpression(subject: subject, cases: cases, type: type)
      }
      fatalError("Unsupported when expression reached MIR lowering")
    case .lambdaExpression(let parameters, let captures, let body, let type):
      let captureSources = captures.map { capturePlace(for: $0.symbol) }
      let value = MIRValue.lambda(
        MIRLambda(
          parameters: parameters,
          captures: captures,
          captureSources: captureSources,
          function: lowerLambdaFunction(parameters: parameters, captures: captures, body: body, type: type),
          type: type
        )
      )
      let result = materialize(value, type: type)
      return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
    case .traitMethodPlaceholder(let traitName, let methodName, _, _, _):
      fatalError("Unsupported trait method placeholder reached MIR lowering: \(traitName).\(methodName)")
    case .traitObjectConversion(let inner, let traitName, let traitTypeArgs, let concreteType, let type):
      let result = materialize(
        .traitObjectConversion(
          MIRTraitObjectConversion(
            inner: lowerValue(inner),
            sourceOwnership: ownershipUse(for: inner),
            traitName: traitName,
            traitTypeArguments: traitTypeArgs,
            concreteType: concreteType,
            type: type
          )
        ),
        type: type
      )
      return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
    case .traitMethodCall(let receiver, let traitName, let methodName, let methodIndex, let arguments, let type):
      let value = MIRValue.traitMethodCall(
        MIRTraitMethodCall(
          receiver: lowerValue(receiver),
          receiverOwnership: ownershipUse(for: receiver),
          traitName: traitName,
          traitTypeArguments: traitObjectTypeArguments(from: receiver.type),
          methodName: methodName,
          methodIndex: methodIndex,
          arguments: lowerArgumentValues(arguments),
          argumentOwnerships: arguments.map(ownershipUse(for:)),
          type: type
        )
      )
      if type == .never {
        append(.evaluate(value))
        terminate(.unreachable)
        return nil
      }
      if type == .void {
        append(.evaluate(value))
        return MIRExprResult(type: .void, category: .rvalue, operand: .constant(.void), place: nil)
      }
      let result = materialize(value, type: type)
      return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
    }
  }

  private func lowerBlock(statements: [TypedStatementNode], type: Type) -> MIRExprResult? {
    let parentScopeDepth = scopeStack.count
    let scope = makeScopeID()
    append(.scopeEnter(scope))
    scopeStack.append(scope)

    let ownedYieldTargets = statements.reduce(into: Set<YieldTargetId>()) { ids, statement in
      ids.formUnion(statement.ownedYieldTargetIDs)
    }
    let blockProducesValue = type != .void && type != .never
    let usesYieldJoin = !ownedYieldTargets.isEmpty && type != .never
    let resultLocal: MIRLocal? = blockProducesValue
      ? makeTemporary(type: type, nameHint: "block_result")
      : nil
    if let resultLocal {
      append(.declare(resultLocal.id))
    }

    let blockBody = currentBlockID
    let joinBlock = usesYieldJoin ? makeBlock() : nil
    let yieldTargetDepth = joinBlock.map {
      pushYieldTargets(
        ownedYieldTargets,
        resultLocal: resultLocal,
        joinBlock: $0,
        baseScopeDepth: parentScopeDepth
      )
    } ?? yieldTargetStack.count
    if usesYieldJoin {
      setCurrentBlock(blockBody)
    }

    let result: MIRExprResult?

    if type != .void,
       type != .never,
       let last = statements.last,
       case .expression(let expression) = last {
      for statement in statements.dropLast() {
        lowerStatement(statement)
      }
      result = lowerExpression(expression)
    } else {
      for statement in statements {
        lowerStatement(statement)
      }
      result = MIRExprResult(type: type, category: .rvalue, operand: type == .void ? .constant(.void) : nil, place: nil)
    }

    if let resultLocal, let result, !currentBlockIsTerminated {
      assignBranchResult(result, to: resultLocal.id)
    }

    if !currentBlockIsTerminated {
      emitFinalies(for: scope)
    }
    if !currentBlockIsTerminated {
      append(.scopeExit(scope))
    }
    _ = scopeStack.popLast()
    finaliesByScope.removeValue(forKey: scope)
    restoreYieldTargets(toDepth: yieldTargetDepth)

    if let joinBlock {
      if !currentBlockIsTerminated {
        terminate(.goto(joinBlock))
      }
      setCurrentBlock(joinBlock)
      if let resultLocal {
        return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
      }
      return MIRExprResult(type: type, category: .rvalue, operand: type == .void ? .constant(.void) : nil, place: nil)
    }

    if let resultLocal {
      return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
    }

    return result
  }

  private func lowerStatement(_ statement: TypedStatementNode) {
    guard !currentBlockIsTerminated else { return }

    switch statement {
    case .variableDeclaration(let symbol, let value, let mutable):
      let initialValue = lowerValue(value)
      let local = makeLocal(
        name: context.getName(symbol.defId) ?? "local_\(symbol.defId.id)",
        type: symbol.type,
        mutability: mutable ? .mutable : .immutable,
        storage: .local,
        symbol: symbol
      )
      localByDefId[symbol.defId.id] = local.id
      append(.declare(local.id))
      if symbol.type != .void && symbol.type != .never {
        append(.assign(.local(local.id), initialValue))
      } else {
        append(.evaluate(initialValue))
      }
    case .pairVariableDeclaration(
      let pairSymbol,
      let pairValue,
      let firstSymbol,
      let firstMember,
      let firstMutable,
      let secondSymbol,
      let secondMember,
      let secondMutable
    ):
      lowerPairVariableDeclaration(
        pairSymbol: pairSymbol,
        pairValue: pairValue,
        firstSymbol: firstSymbol,
        firstMember: firstMember,
        firstMutable: firstMutable,
        secondSymbol: secondSymbol,
        secondMember: secondMember,
        secondMutable: secondMutable
      )
    case .assignment(let target, let operatorKind, let value):
      lowerAssignment(target: target, operatorKind: operatorKind, value: value)
    case .expression(let expression):
      if let result = lowerExpression(expression) {
        if let operand = result.operand {
          append(.evaluate(.operand(operand)))
        } else if let place = result.place {
          append(.evaluate(.placeRead(place, ownership: .borrow)))
        }
      }
    case .ifStatement(let condition, let thenBranch, let elseBranch):
      _ = lowerIfExpression(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch, type: .void)
    case .ifPatternStatement(let subject, let pattern, _, let thenBranch, let elseBranch):
      if canLowerPatternWithBindings(pattern, subjectType: subject.type) {
        _ = lowerSimpleIfPatternExpression(
          subject: subject,
          pattern: pattern,
          thenBranch: thenBranch,
          elseBranch: elseBranch,
          type: .void
        )
        return
      }
      fatalError("Unsupported if-pattern statement reached MIR lowering")
    case .whileStatement(let condition, let body):
      lowerWhile(condition: condition, body: body)
    case .whilePatternStatement(let subject, let pattern, _, let body):
      if canLowerPatternWithBindings(pattern, subjectType: subject.type) {
        lowerSimpleWhilePattern(subject: subject, pattern: pattern, body: body)
        return
      }
      fatalError("Unsupported while-pattern statement reached MIR lowering")
    case .whenStatement(let subject, let cases):
      let expressionCases = cases.map { TypedMatchCase(pattern: $0.pattern, body: $0.body) }
      if canLowerSimpleWhen(subject: subject, cases: expressionCases) {
        _ = lowerSimpleWhenExpression(subject: subject, cases: expressionCases, type: .void)
        return
      }
      fatalError("Unsupported when statement reached MIR lowering")
    case .return(let value):
      guard let value else {
        emitScopeExits(fromDepth: 0)
        terminate(.returnValue(nil))
        return
      }
      if value.type == .never {
        _ = lowerExpression(value)
        terminate(.unreachable)
        return
      }
      if case .referenceExpression(let inner, let type) = value,
         let place = lowerPlace(inner) {
        let operand = materialize(
          .ref(place, kind: referenceKind(for: type), allocation: .heapOwned),
          type: type
        )
        emitScopeExits(fromDepth: 0)
        terminate(.returnValue(operand))
        return
      }
      let result = lowerExpression(value)
      guard !currentBlockIsTerminated else { return }
      guard let operand = returnOperand(for: result) else {
        terminate(.unreachable)
        return
      }
      emitScopeExits(fromDepth: 0)
      terminate(.returnValue(operand))
    case .break:
      if let loop = loopStack.last {
        emitScopeExits(fromDepth: loop.scopeDepth)
        terminate(.goto(loop.breakBlock))
      } else {
        terminate(.unreachable)
      }
    case .continue:
      if let loop = loopStack.last {
        emitScopeExits(fromDepth: loop.scopeDepth)
        terminate(.goto(loop.continueBlock))
      } else {
        terminate(.unreachable)
      }
    case .finally(let expression):
      if let scope = scopeStack.last {
        finaliesByScope[scope, default: []].append(expression)
      } else {
        _ = lowerExpression(expression)
      }
    case .yield(let target, let value):
      lowerYield(target: target, value: value)
    }
  }

  private func lowerYield(target: YieldTargetId, value: TypedExpressionNode) {
    guard let yieldContext = yieldTargetStack.last(where: { $0.id == target }) else {
      fatalError("Unsupported yield without MIR target reached MIR lowering")
    }

    let loweredValue = lowerValue(value)
    guard !currentBlockIsTerminated else { return }
    if let resultLocal = yieldContext.resultLocal {
      append(.assign(.local(resultLocal), loweredValue))
    } else {
      append(.evaluate(loweredValue))
    }
    emitScopeExits(fromDepth: yieldContext.baseScopeDepth)
    terminate(.goto(yieldContext.joinBlock))
  }

  private func emitScopeExits(fromDepth baseScopeDepth: Int) {
    guard scopeStack.count > baseScopeDepth else { return }
    for scope in scopeStack[baseScopeDepth...].reversed() {
      emitFinalies(for: scope)
      guard !currentBlockIsTerminated else { return }
      append(.scopeExit(scope))
    }
  }

  private func emitFinalies(for scope: MIRScopeID) {
    guard let finalies = finaliesByScope[scope], !finalies.isEmpty else { return }
    for expression in finalies.reversed() {
      lowerStatement(.expression(expression))
      guard !currentBlockIsTerminated else { return }
    }
  }

  private func pushYieldTargets(
    _ targets: Set<YieldTargetId>,
    resultLocal: MIRLocal?,
    joinBlock: MIRBlockID,
    baseScopeDepth: Int? = nil
  ) -> Int {
    let previousDepth = yieldTargetStack.count
    guard !targets.isEmpty else { return previousDepth }
    let targetBaseScopeDepth = baseScopeDepth ?? scopeStack.count
    for target in targets {
      if yieldTargetStack.contains(where: { $0.id == target }) {
        continue
      }
      yieldTargetStack.append(
        MIRYieldTargetContext(
          id: target,
          resultLocal: resultLocal?.id,
          joinBlock: joinBlock,
          baseScopeDepth: targetBaseScopeDepth
        )
      )
    }
    return previousDepth
  }

  private func restoreYieldTargets(toDepth depth: Int) {
    guard yieldTargetStack.count > depth else { return }
    yieldTargetStack.removeSubrange(depth..<yieldTargetStack.count)
  }

  private func lowerBranchBody(_ expression: TypedExpressionNode, resultLocal: MIRLocal?) {
    guard let resultLocal, expression.type != .never, expression.type != .void else {
      _ = lowerExpression(expression)
      return
    }

    if expression.containsYield {
      guard let result = lowerExpression(expression), !currentBlockIsTerminated else {
        return
      }
      assignBranchResult(result, to: resultLocal.id)
      return
    }

    append(.assign(.local(resultLocal.id), lowerValue(expression)))
  }

  private func preparePatternSubject(
    _ subject: TypedExpressionNode,
    nameHint: String
  ) -> (place: MIRPlace, scope: MIRScopeID?)? {
    guard let result = lowerExpression(subject) else {
      return nil
    }

    let subjectValue: MIRValue
    if let operand = result.operand {
      subjectValue = .operand(operand)
    } else if let place = result.place {
      let ownership: MIROwnershipUse = result.category == .lvalue ? .copy : .move
      subjectValue = .placeRead(place, ownership: ownership)
    } else {
      return nil
    }

    let subjectScope = makeScopeID()
    append(.scopeEnter(subjectScope))
    scopeStack.append(subjectScope)

    let subjectLocal = makeTemporary(type: subject.type, nameHint: nameHint)
    append(.declare(subjectLocal.id))
    append(.assign(.local(subjectLocal.id), subjectValue))
    return (.local(subjectLocal.id), subjectScope)
  }

  private func assignBranchResult(_ result: MIRExprResult, to local: MIRLocalID) {
    if let operand = result.operand {
      append(.assign(.local(local), .operand(operand)))
      return
    }

    if let place = result.place {
      append(.assign(.local(local), .placeRead(place, ownership: .copy)))
    }
  }

  private func lowerAssignment(
    target: TypedExpressionNode,
    operatorKind: CompoundAssignmentOperator?,
    value: TypedExpressionNode
  ) {
    let loweredValue = lowerValue(value)
    guard let place = lowerPlace(target) else {
      fatalError("Unsupported assignment target reached MIR lowering")
    }
    if let operatorKind {
      append(.compoundAssign(MIRCompoundAssignment(target: place, operatorKind: operatorKind, value: loweredValue)))
    } else {
      append(.assign(place, loweredValue))
    }
  }

  private func lowerPairVariableDeclaration(
    pairSymbol: Symbol,
    pairValue: TypedExpressionNode,
    firstSymbol: Symbol?,
    firstMember: Symbol,
    firstMutable: Bool,
    secondSymbol: Symbol?,
    secondMember: Symbol,
    secondMutable: Bool
  ) {
    let pairInitialValue = lowerValue(pairValue)
    guard !currentBlockIsTerminated else { return }

    let pairLocal = makeLocal(
      name: context.getName(pairSymbol.defId) ?? "pair_\(pairSymbol.defId.id)",
      type: pairSymbol.type,
      mutability: .mutable,
      storage: .temporary,
      symbol: pairSymbol
    )
    localByDefId[pairSymbol.defId.id] = pairLocal.id
    append(.declare(pairLocal.id))
    append(.assign(.local(pairLocal.id), pairInitialValue))

    let pairPlace = MIRPlace.local(pairLocal.id)
    lowerPairBinding(
      symbol: firstSymbol,
      member: firstMember,
      mutable: firstMutable,
      pairPlace: pairPlace
    )
    lowerPairBinding(
      symbol: secondSymbol,
      member: secondMember,
      mutable: secondMutable,
      pairPlace: pairPlace
    )
  }

  private func lowerPairBinding(
    symbol: Symbol?,
    member: Symbol,
    mutable: Bool,
    pairPlace: MIRPlace
  ) {
    let fieldPlace = MIRPlace.field(base: pairPlace, field: member)
    guard let symbol else {
      if needsDrop(member.type) {
        append(.drop(fieldPlace))
      }
      return
    }

    let local = makeLocal(
      name: context.getName(symbol.defId) ?? "local_\(symbol.defId.id)",
      type: symbol.type,
      mutability: mutable ? .mutable : .immutable,
      storage: .local,
      symbol: symbol
    )
    localByDefId[symbol.defId.id] = local.id
    append(.declare(local.id))
    append(.assign(.local(local.id), .placeRead(fieldPlace, ownership: .move)))
  }

  private func lowerIfExpression(
    condition: TypedExpressionNode,
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    type: Type
  ) -> MIRExprResult? {
    guard !currentBlockIsTerminated else { return nil }

    let resultLocal: MIRLocal? = (type != .void && type != .never)
      ? makeTemporary(type: type, nameHint: "if_result")
      : nil
    if let resultLocal {
      append(.declare(resultLocal.id))
    }

    let conditionOperand = lowerOperand(condition)
    let branchBlock = currentBlockID
    let thenBlock = makeBlock()
    let elseBlock = makeBlock()
    let joinBlock = makeBlock()
    let yieldTargetDepth = pushYieldTargets(
      thenBranch.ownedYieldTargetIDs.union(elseBranch?.ownedYieldTargetIDs ?? []),
      resultLocal: resultLocal,
      joinBlock: joinBlock
    )
    defer { restoreYieldTargets(toDepth: yieldTargetDepth) }

    setCurrentBlock(branchBlock)
    terminate(.branch(condition: conditionOperand, thenBlock: thenBlock, elseBlock: elseBlock))

    setCurrentBlock(thenBlock)
    lowerBranchBody(thenBranch, resultLocal: resultLocal)
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(elseBlock)
    if let elseBranch {
      lowerBranchBody(elseBranch, resultLocal: resultLocal)
    }
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(joinBlock)
    guard let resultLocal else {
      return MIRExprResult(type: type, category: .rvalue, operand: type == .void ? .constant(.void) : nil, place: nil)
    }
    return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
  }

  private func lowerWhile(condition: TypedExpressionNode, body: TypedExpressionNode) {
    let predecessorBlock = currentBlockID
    let conditionBlock = makeBlock()
    let bodyBlock = makeBlock()
    let exitBlock = makeBlock()
    setCurrentBlock(predecessorBlock)
    terminate(.goto(conditionBlock))

    setCurrentBlock(conditionBlock)
    let conditionOperand = lowerOperand(condition)
    terminate(.branch(condition: conditionOperand, thenBlock: bodyBlock, elseBlock: exitBlock))

    setCurrentBlock(bodyBlock)
    loopStack.append((continueBlock: conditionBlock, breakBlock: exitBlock, scopeDepth: scopeStack.count))
    _ = lowerExpression(body)
    _ = loopStack.popLast()
    if !currentBlockIsTerminated {
      terminate(.goto(conditionBlock))
    }

    setCurrentBlock(exitBlock)
  }

  private func lowerPatternTest(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    negated: Bool,
    type: Type
  ) -> MIRExprResult? {
    if !context.containsGenericParameter(subject.type),
       canLowerSimplePattern(pattern, subjectType: subject.type),
       let operand = lowerSimplePatternTest(subject: subject, pattern: pattern, negated: negated) {
      return MIRExprResult(type: type, category: .rvalue, operand: operand, place: nil)
    }
    fatalError("Unsupported pattern test reached MIR lowering")
  }

  private func lowerSimplePatternTest(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    negated: Bool
  ) -> MIROperand? {
    guard let preparedSubject = preparePatternSubject(subject, nameHint: "pattern_test_subject") else {
      return nil
    }
    let condition = lowerSimplePatternCondition(
      subjectValue: .placeRead(preparedSubject.place, ownership: .borrow),
      subjectPlace: preparedSubject.place,
      subjectType: subject.type,
      pattern: pattern,
      negated: negated
    )
    if let subjectScope = preparedSubject.scope {
      append(.scopeExit(subjectScope))
      _ = scopeStack.popLast()
    }
    return condition
  }

  private func lowerSimplePatternCondition(
    subjectValue: MIRValue,
    subjectPlace: MIRPlace? = nil,
    subjectType: Type,
    pattern: TypedPattern,
    negated: Bool
  ) -> MIROperand? {
    let matchedSubject = patternMatchSubject(value: subjectValue, type: subjectType)
    let matchedValue = matchedSubject.value
    let matchedType = matchedSubject.type
    let matchedPlace = subjectPlace.map { patternMatchPlace(place: $0, type: subjectType).place }

    switch pattern {
    case .wildcard, .variable:
      return .constant(.boolean(!negated))
    case .booleanLiteral(let value):
      guard matchedType == .bool else { return nil }
      let subjectOperand = materialize(matchedValue, type: matchedType)
      let expected = MIROperand.constant(.boolean(value))
      let op: ComparisonOperator = negated ? .notEqual : .equal
      return materialize(
        .binary(MIRBinaryOperation(left: subjectOperand, operatorKind: .comparison(op), right: expected, type: .bool)),
        type: .bool
      )
    case .integerLiteral(let value):
      let comparisonSubject: MIROperand
      let comparisonType: Type
      if let matchedPlace,
         let runeValue = runePatternValueAccess(subjectPlace: matchedPlace, subjectType: matchedType) {
        comparisonSubject = materialize(.placeRead(runeValue.place, ownership: .borrow), type: runeValue.type)
        comparisonType = runeValue.type
      } else {
        guard matchedType.isIntegerType else { return nil }
        comparisonSubject = materialize(matchedValue, type: matchedType)
        comparisonType = matchedType
      }
      let expected = MIROperand.constant(.integer(value, comparisonType))
      let op: ComparisonOperator = negated ? .notEqual : .equal
      return materialize(
        .binary(MIRBinaryOperation(left: comparisonSubject, operatorKind: .comparison(op), right: expected, type: .bool)),
        type: .bool
      )
    case .stringLiteral(let value):
      guard isStringPatternType(matchedType),
            let equalsMethod = stringEqualsMethodSymbol(for: matchedType) else {
        return nil
      }
      let subjectArgument: MIRValue
      if let matchedPlace {
        subjectArgument = .placeRead(matchedPlace, ownership: .copy)
      } else {
        subjectArgument = matchedValue
      }
      let result = materialize(
        .call(
          MIRCall(
            callee: .function(equalsMethod),
            arguments: [subjectArgument, .operand(.constant(.string(value, matchedType)))],
            type: .bool
          )
        ),
        type: .bool
      )
      if negated {
        return materialize(
          .unary(MIRUnaryOperation(operatorKind: .logicalNot, operand: result, type: .bool)),
          type: .bool
        )
      }
      return result
    case .enumCase(let caseName, let tagIndex, let elements):
      return lowerEnumCasePatternCondition(
        subjectValue: matchedValue,
        subjectPlace: matchedPlace,
        subjectType: matchedType,
        caseName: caseName,
        tagIndex: tagIndex,
        elements: elements,
        negated: negated
      )
    case .comparisonPattern(let patternOperator, let value):
      guard matchedType.isIntegerType else { return nil }
      let subjectOperand = materialize(matchedValue, type: matchedType)
      let expected = MIROperand.constant(.integer(String(value), matchedType))
      return materialize(
        .binary(MIRBinaryOperation(left: subjectOperand, operatorKind: .comparison(comparisonOperator(for: patternOperator, negated: negated)), right: expected, type: .bool)),
        type: .bool
      )
    case .notPattern(let inner):
      return lowerSimplePatternCondition(subjectValue: matchedValue, subjectPlace: matchedPlace, subjectType: matchedType, pattern: inner, negated: !negated)
    case .andPattern(let left, let right):
      return lowerCombinedPatternCondition(
        subjectValue: matchedValue,
        subjectPlace: matchedPlace,
        subjectType: matchedType,
        left: left,
        right: right,
        operatorKind: negated ? .logicalOr : .logicalAnd,
        negatedOperands: negated
      )
    case .orPattern(let left, let right):
      return lowerCombinedPatternCondition(
        subjectValue: matchedValue,
        subjectPlace: matchedPlace,
        subjectType: matchedType,
        left: left,
        right: right,
        operatorKind: negated ? .logicalAnd : .logicalOr,
        negatedOperands: negated
      )
    case .structPattern(_, let elements):
      return lowerStructPatternCondition(
        subjectPlace: matchedPlace,
        subjectType: matchedType,
        elements: elements,
        negated: negated
      )
    }
  }

  private func lowerCombinedPatternCondition(
    subjectValue: MIRValue,
    subjectPlace: MIRPlace?,
    subjectType: Type,
    left: TypedPattern,
    right: TypedPattern,
    operatorKind: MIRBinaryOperator,
    negatedOperands: Bool
  ) -> MIROperand? {
    guard let leftOperand = lowerSimplePatternCondition(
      subjectValue: subjectValue,
      subjectPlace: subjectPlace,
      subjectType: subjectType,
      pattern: left,
      negated: negatedOperands
    ) else {
      return nil
    }
    guard let rightOperand = lowerSimplePatternCondition(
      subjectValue: subjectValue,
      subjectPlace: subjectPlace,
      subjectType: subjectType,
      pattern: right,
      negated: negatedOperands
    ) else {
      return nil
    }
    return materialize(
      .binary(MIRBinaryOperation(left: leftOperand, operatorKind: operatorKind, right: rightOperand, type: .bool)),
      type: .bool
    )
  }

  private func lowerEnumCasePatternCondition(
    subjectValue: MIRValue,
    subjectPlace: MIRPlace?,
    subjectType: Type,
    caseName: String,
    tagIndex: Int,
    elements: [TypedPattern],
    negated: Bool
  ) -> MIROperand? {
    guard case .enum(let defId) = subjectType,
          let cases = context.getEnumCases(defId),
          cases.indices.contains(tagIndex) else {
      return nil
    }

    let caseDef = cases[tagIndex]
    guard caseDef.parameters.count == elements.count else {
      return nil
    }

    let tagOperand = materialize(.enumTag(MIREnumTag(subject: subjectValue, enumType: subjectType)), type: .int)
    let expected = MIROperand.constant(.integer(String(tagIndex), .int))
    let tagCondition = materialize(
      .binary(MIRBinaryOperation(left: tagOperand, operatorKind: .comparison(.equal), right: expected, type: .bool)),
      type: .bool
    )

    if elements.allSatisfy({ $0.isConditionlessPayloadPattern }) {
      if negated {
        return materialize(
          .unary(MIRUnaryOperation(operatorKind: .logicalNot, operand: tagCondition, type: .bool)),
          type: .bool
        )
      }
      return tagCondition
    }

    guard let subjectPlace else { return nil }

    let resultLocal = makeTemporary(type: .bool, nameHint: "pattern_match")
    append(.declare(resultLocal.id))

    let branchBlock = currentBlockID
    let payloadBlock = makeBlock()
    let failedBlock = makeBlock()
    let joinBlock = makeBlock()

    setCurrentBlock(branchBlock)
    terminate(.branch(condition: tagCondition, thenBlock: payloadBlock, elseBlock: failedBlock))

    setCurrentBlock(payloadBlock)
    var payloadResult = MIROperand.constant(.boolean(true))
    for (index, element) in elements.enumerated() {
      let parameter = caseDef.parameters[index]
      let payloadPlace = MIRPlace.enumPayload(
        base: subjectPlace,
        caseName: caseName,
        fieldName: parameter.name,
        fieldIndex: index,
        fieldType: parameter.type
      )
      guard let payloadCondition = lowerSimplePatternCondition(
        subjectValue: .placeRead(payloadPlace, ownership: .borrow),
        subjectPlace: payloadPlace,
        subjectType: parameter.type,
        pattern: element,
        negated: false
      ) else {
        return nil
      }
      payloadResult = materialize(
        .binary(MIRBinaryOperation(left: payloadResult, operatorKind: .logicalAnd, right: payloadCondition, type: .bool)),
        type: .bool
      )
    }
    if negated {
      payloadResult = materialize(
        .unary(MIRUnaryOperation(operatorKind: .logicalNot, operand: payloadResult, type: .bool)),
        type: .bool
      )
    }
    if !currentBlockIsTerminated {
      append(.assign(.local(resultLocal.id), .operand(payloadResult)))
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(failedBlock)
    append(.assign(.local(resultLocal.id), .operand(.constant(.boolean(negated)))))
    terminate(.goto(joinBlock))

    setCurrentBlock(joinBlock)
    return .local(resultLocal.id)
  }

  private func lowerStructPatternCondition(
    subjectPlace: MIRPlace?,
    subjectType: Type,
    elements: [TypedPattern],
    negated: Bool
  ) -> MIROperand? {
    guard case .structure(let defId) = subjectType,
          let members = context.getStructMembers(defId),
          members.count == elements.count else {
      return nil
    }

    var condition: MIROperand = .constant(.boolean(true))
    if !elements.allSatisfy({ $0.isWildcardOnly }) {
      guard let subjectPlace else { return nil }
      for (index, element) in elements.enumerated() {
        let member = members[index]
        let fieldPlace = MIRPlace.field(
          base: subjectPlace,
          field: makeSyntheticPatternFieldSymbol(name: member.name, type: member.type)
        )
        guard let fieldCondition = lowerSimplePatternCondition(
          subjectValue: .placeRead(fieldPlace, ownership: .borrow),
          subjectPlace: fieldPlace,
          subjectType: member.type,
          pattern: element,
          negated: false
        ) else {
          return nil
        }
        condition = materialize(
          .binary(MIRBinaryOperation(left: condition, operatorKind: .logicalAnd, right: fieldCondition, type: .bool)),
          type: .bool
        )
      }
    }

    if negated {
      return materialize(
        .unary(MIRUnaryOperation(operatorKind: .logicalNot, operand: condition, type: .bool)),
        type: .bool
      )
    }
    return condition
  }

  private func patternMatchPlace(place: MIRPlace, type: Type) -> (place: MIRPlace, type: Type) {
    switch type {
    case .reference(let inner),
         .mutableReference(let inner),
         .weakReference(let inner),
         .mutableWeakReference(let inner):
      return (.deref(base: .placeRead(place, ownership: .borrow), pointee: inner), inner)
    default:
      return (place, type)
    }
  }

  private func patternMatchSubject(value: MIRValue, type: Type) -> (value: MIRValue, type: Type) {
    switch type {
    case .reference(let inner),
         .mutableReference(let inner),
         .weakReference(let inner),
         .mutableWeakReference(let inner):
      return (.placeRead(.deref(base: value, pointee: inner), ownership: .borrow), inner)
    default:
      return (value, type)
    }
  }

  private func patternMatchType(_ type: Type) -> Type {
    switch type {
    case .reference(let inner),
         .mutableReference(let inner),
         .weakReference(let inner),
         .mutableWeakReference(let inner):
      return inner
    default:
      return type
    }
  }

  private func canLowerSimplePattern(_ pattern: TypedPattern, subjectType: Type) -> Bool {
    let matchedType = patternMatchType(subjectType)
    switch pattern {
    case .wildcard:
      return true
    case .booleanLiteral:
      return matchedType == .bool
    case .stringLiteral:
      return isStringPatternType(matchedType)
    case .integerLiteral:
      return matchedType.isIntegerType || isRunePatternType(matchedType)
    case .comparisonPattern:
      return matchedType.isIntegerType
    case .enumCase(_, let tagIndex, let elements):
      guard case .enum(let defId) = matchedType,
            let cases = context.getEnumCases(defId),
            cases.indices.contains(tagIndex) else { return false }
      let caseDef = cases[tagIndex]
      return caseDef.parameters.count == elements.count
        && zip(elements, caseDef.parameters).allSatisfy { canLowerSimplePattern($0.0, subjectType: $0.1.type) }
    case .structPattern(_, let elements):
      guard case .structure(let defId) = matchedType,
            let members = context.getStructMembers(defId),
            members.count == elements.count else { return false }
      return zip(elements, members).allSatisfy { canLowerSimplePattern($0.0, subjectType: $0.1.type) }
    case .andPattern(let left, let right),
         .orPattern(let left, let right):
      return !left.introducesBinding
        && !right.introducesBinding
        && canLowerSimplePattern(left, subjectType: matchedType)
        && canLowerSimplePattern(right, subjectType: matchedType)
    case .notPattern(let inner):
      return canLowerSimplePattern(inner, subjectType: matchedType)
    default:
      return false
    }
  }

  private func canLowerPatternWithBindings(_ pattern: TypedPattern, subjectType: Type) -> Bool {
    if canLowerSimplePattern(pattern, subjectType: subjectType) {
      return true
    }

    let matchedType = patternMatchType(subjectType)
    guard !context.containsGenericParameter(matchedType) else { return false }
    switch pattern {
    case .variable:
      return true
    case .enumCase(_, let tagIndex, let elements):
      guard case .enum(let defId) = matchedType,
            let cases = context.getEnumCases(defId),
            cases.indices.contains(tagIndex) else {
        return false
      }
      let caseDef = cases[tagIndex]
      return caseDef.parameters.count == elements.count
        && zip(elements, caseDef.parameters).allSatisfy { canLowerPatternWithBindings($0.0, subjectType: $0.1.type) }
    case .structPattern(_, let elements):
      guard case .structure(let defId) = matchedType,
            let members = context.getStructMembers(defId),
            members.count == elements.count else {
        return false
      }
      return zip(elements, members).allSatisfy { canLowerPatternWithBindings($0.0, subjectType: $0.1.type) }
    case .andPattern(let left, let right),
         .orPattern(let left, let right):
      return canLowerPatternWithBindings(left, subjectType: matchedType)
        && canLowerPatternWithBindings(right, subjectType: matchedType)
    default:
      return false
    }
  }

  private func withPatternBindings(
    pattern: TypedPattern,
    subjectPlace: MIRPlace,
    subjectType: Type,
    _ body: () -> Void
  ) {
    let savedPatternPlaces = patternPlaceByDefId
    bindPatternVariables(pattern: pattern, subjectPlace: subjectPlace, subjectType: subjectType)
    body()
    patternPlaceByDefId = savedPatternPlaces
  }

  private func bindPatternVariables(pattern: TypedPattern, subjectPlace: MIRPlace, subjectType: Type) {
    let matchedSubject = patternMatchPlace(place: subjectPlace, type: subjectType)
    let matchedPlace = matchedSubject.place
    let matchedType = matchedSubject.type

    switch pattern {
    case .variable(let symbol):
      if symbol.type != .void {
        if symbol.type == subjectType {
          patternPlaceByDefId[symbol.defId.id] = subjectPlace
        } else {
          patternPlaceByDefId[symbol.defId.id] = matchedPlace
        }
      }
    case .enumCase(let caseName, let tagIndex, let elements):
      guard case .enum(let defId) = matchedType,
            let cases = context.getEnumCases(defId),
            cases.indices.contains(tagIndex) else {
        return
      }
      let caseDef = cases[tagIndex]
      for (index, element) in elements.enumerated() where index < caseDef.parameters.count {
        let parameter = caseDef.parameters[index]
        let payloadPlace = MIRPlace.enumPayload(
          base: matchedPlace,
          caseName: caseName,
          fieldName: parameter.name,
          fieldIndex: index,
          fieldType: parameter.type
        )
        bindPatternVariables(pattern: element, subjectPlace: payloadPlace, subjectType: parameter.type)
      }
    case .structPattern(_, let elements):
      guard case .structure(let defId) = matchedType,
            let members = context.getStructMembers(defId),
            members.count == elements.count else {
        return
      }
      for (index, element) in elements.enumerated() {
        let member = members[index]
        let fieldPlace = MIRPlace.field(
          base: matchedPlace,
          field: makeSyntheticPatternFieldSymbol(name: member.name, type: member.type)
        )
        bindPatternVariables(pattern: element, subjectPlace: fieldPlace, subjectType: member.type)
      }
    case .andPattern(let left, let right):
      bindPatternVariables(pattern: left, subjectPlace: matchedPlace, subjectType: matchedType)
      bindPatternVariables(pattern: right, subjectPlace: matchedPlace, subjectType: matchedType)
    case .orPattern(let left, let right):
      bindOrPatternVariables(left: left, right: right, subjectPlace: subjectPlace, subjectType: subjectType)
    default:
      break
    }
  }

  private func bindOrPatternVariables(
    left: TypedPattern,
    right: TypedPattern,
    subjectPlace: MIRPlace,
    subjectType: Type
  ) {
    declarePatternBindingLocals(for: left)

    guard let leftCondition = lowerSimplePatternCondition(
      subjectValue: .placeRead(subjectPlace, ownership: .borrow),
      subjectPlace: subjectPlace,
      subjectType: subjectType,
      pattern: left,
      negated: false
    ) else {
      return
    }

    let branchBlock = currentBlockID
    let leftBlock = makeBlock()
    let rightBlock = makeBlock()
    let joinBlock = makeBlock()

    setCurrentBlock(branchBlock)
    terminate(.branch(condition: leftCondition, thenBlock: leftBlock, elseBlock: rightBlock))

    setCurrentBlock(leftBlock)
    assignPatternBindingLocals(pattern: left, subjectPlace: subjectPlace, subjectType: subjectType)
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(rightBlock)
    assignPatternBindingLocals(pattern: right, subjectPlace: subjectPlace, subjectType: subjectType)
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(joinBlock)
  }

  private func declarePatternBindingLocals(for pattern: TypedPattern) {
    for symbol in pattern.bindingSymbols where symbol.type != .void {
      if patternPlaceByDefId[symbol.defId.id] != nil {
        continue
      }
      let nameHint = context.getName(symbol.defId) ?? "pattern_binding"
      let local = makeTemporary(type: symbol.type, nameHint: nameHint)
      append(.declare(local.id))
      patternPlaceByDefId[symbol.defId.id] = .local(local.id)
    }
  }

  private func assignPatternBindingLocals(pattern: TypedPattern, subjectPlace: MIRPlace, subjectType: Type) {
    let matchedSubject = patternMatchPlace(place: subjectPlace, type: subjectType)
    let matchedPlace = matchedSubject.place
    let matchedType = matchedSubject.type

    switch pattern {
    case .variable(let symbol):
      guard symbol.type != .void,
            let destination = patternPlaceByDefId[symbol.defId.id] else {
        return
      }
      let sourcePlace = symbol.type == subjectType ? subjectPlace : matchedPlace
      append(.assign(destination, .placeRead(sourcePlace, ownership: .copy)))
    case .enumCase(let caseName, let tagIndex, let elements):
      guard case .enum(let defId) = matchedType,
            let cases = context.getEnumCases(defId),
            cases.indices.contains(tagIndex) else {
        return
      }
      let caseDef = cases[tagIndex]
      for (index, element) in elements.enumerated() where index < caseDef.parameters.count {
        let parameter = caseDef.parameters[index]
        let payloadPlace = MIRPlace.enumPayload(
          base: matchedPlace,
          caseName: caseName,
          fieldName: parameter.name,
          fieldIndex: index,
          fieldType: parameter.type
        )
        assignPatternBindingLocals(pattern: element, subjectPlace: payloadPlace, subjectType: parameter.type)
      }
    case .structPattern(_, let elements):
      guard case .structure(let defId) = matchedType,
            let members = context.getStructMembers(defId),
            members.count == elements.count else {
        return
      }
      for (index, element) in elements.enumerated() {
        let member = members[index]
        let fieldPlace = MIRPlace.field(
          base: matchedPlace,
          field: makeSyntheticPatternFieldSymbol(name: member.name, type: member.type)
        )
        assignPatternBindingLocals(pattern: element, subjectPlace: fieldPlace, subjectType: member.type)
      }
    case .andPattern(let left, let right):
      assignPatternBindingLocals(pattern: left, subjectPlace: matchedPlace, subjectType: matchedType)
      assignPatternBindingLocals(pattern: right, subjectPlace: matchedPlace, subjectType: matchedType)
    case .orPattern(let left, let right):
      bindOrPatternVariables(left: left, right: right, subjectPlace: subjectPlace, subjectType: subjectType)
    case .wildcard, .booleanLiteral, .integerLiteral, .stringLiteral, .comparisonPattern, .notPattern:
      break
    }
  }

  private func makeSyntheticPatternFieldSymbol(name: String, type: Type) -> Symbol {
    let uniqueName = UUID().uuidString.replacingOccurrences(of: "-", with: "_")
    return context.createSymbol(
      name: name,
      modulePath: ["__mir_pattern_field", uniqueName],
      sourceFile: "<mir_pattern_field>",
      type: type,
      kind: .variable(.Value),
      access: .private
    )
  }

  private func isStringPatternType(_ type: Type) -> Bool {
    guard case .structure = type else { return false }
    return true
  }

  private func isRunePatternType(_ type: Type) -> Bool {
    guard case .structure(let defId) = type else { return false }
    return context.getName(defId) == "Rune"
  }

  private func runePatternValueAccess(subjectPlace: MIRPlace, subjectType: Type) -> (place: MIRPlace, type: Type)? {
    guard case .structure(let defId) = subjectType,
          context.getName(defId) == "Rune",
          let members = context.getStructMembers(defId),
          let valueMember = members.first(where: { $0.name == "value" }) else {
      return nil
    }
    let valuePlace = MIRPlace.field(
      base: subjectPlace,
      field: makeSyntheticPatternFieldSymbol(name: valueMember.name, type: valueMember.type)
    )
    return (valuePlace, valueMember.type)
  }

  private func stringEqualsMethodSymbol(for type: Type) -> Symbol? {
    for node in program.globalNodes {
      guard case .givenDeclaration(let receiverType, _, let methods) = node,
            receiverType == type else {
        continue
      }

      for method in methods {
        let methodName = program.receiverMethodDispatch[method.identifier.defId]?.methodName
          ?? context.getName(method.identifier.defId)
        if methodName == "equals" {
          return method.identifier
        }
      }
    }

    var lookupTypeNames: [String] = {
      switch type {
      case .structure(let defId), .enum(let defId):
        let qualified = context.getQualifiedName(defId)
        let plain = context.getName(defId)
        return [qualified, plain].compactMap { $0 }
      default:
        return []
      }
    }()

    if !lookupTypeNames.contains("String") {
      lookupTypeNames.append("String")
    }

    for typeName in lookupTypeNames {
      guard let defId = program.lookupStaticMethod(typeName: typeName, methodName: "equals") else {
        continue
      }
      let methodType = context.getSymbolType(defId)
        ?? .function(
          parameters: [
            Parameter(type: type, kind: passKindForParameterType(type)),
            Parameter(type: type, kind: passKindForParameterType(type)),
          ],
          returns: .bool
        )
      let kind = context.getSymbolKind(defId) ?? .function
      return Symbol(defId: defId, type: methodType, kind: kind)
    }

    return nil
  }

  private func comparisonOperator(
    for patternOperator: ComparisonPatternOperator,
    negated: Bool
  ) -> ComparisonOperator {
    switch (patternOperator, negated) {
    case (.greater, false), (.lessEqual, true):
      return .greater
    case (.less, false), (.greaterEqual, true):
      return .less
    case (.greaterEqual, false), (.less, true):
      return .greaterEqual
    case (.lessEqual, false), (.greater, true):
      return .lessEqual
    }
  }

  private func lowerIfPatternExpression(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    bindings: [(String, Bool, Type)],
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    type: Type
  ) -> MIRExprResult? {
    if canLowerPatternWithBindings(pattern, subjectType: subject.type) {
      return lowerSimpleIfPatternExpression(
        subject: subject,
        pattern: pattern,
        thenBranch: thenBranch,
        elseBranch: elseBranch,
        type: type
      )
    }
    fatalError("Unsupported if-pattern expression reached MIR lowering")
  }

  private func lowerSimpleIfPatternExpression(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    type: Type
  ) -> MIRExprResult? {
    guard !currentBlockIsTerminated else { return nil }

    let resultLocal: MIRLocal? = (type != .void && type != .never)
      ? makeTemporary(type: type, nameHint: "if_pattern_result")
      : nil
    if let resultLocal {
      append(.declare(resultLocal.id))
    }

    guard let preparedSubject = preparePatternSubject(subject, nameHint: "if_pattern_subject") else {
      return nil
    }
    let subjectPlace = preparedSubject.place
    let subjectScope = preparedSubject.scope

    let condition = lowerSimplePatternCondition(
      subjectValue: .placeRead(subjectPlace, ownership: .borrow),
      subjectPlace: subjectPlace,
      subjectType: subject.type,
      pattern: pattern,
      negated: false
    ) ?? .constant(.boolean(false))

    let branchBlock = currentBlockID
    let thenBlock = makeBlock()
    let elseBlock = makeBlock()
    let joinBlock = makeBlock()
    let yieldTargetDepth = pushYieldTargets(
      thenBranch.ownedYieldTargetIDs.union(elseBranch?.ownedYieldTargetIDs ?? []),
      resultLocal: resultLocal,
      joinBlock: joinBlock
    )
    defer { restoreYieldTargets(toDepth: yieldTargetDepth) }

    setCurrentBlock(branchBlock)
    terminate(.branch(condition: condition, thenBlock: thenBlock, elseBlock: elseBlock))

    setCurrentBlock(thenBlock)
    withPatternBindings(pattern: pattern, subjectPlace: subjectPlace, subjectType: subject.type) {
      lowerBranchBody(thenBranch, resultLocal: resultLocal)
    }
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(elseBlock)
    if let elseBranch {
      lowerBranchBody(elseBranch, resultLocal: resultLocal)
    }
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(joinBlock)
    if let subjectScope {
      append(.scopeExit(subjectScope))
      _ = scopeStack.popLast()
    }
    guard let resultLocal else {
      return MIRExprResult(type: type, category: .rvalue, operand: type == .void ? .constant(.void) : nil, place: nil)
    }
    return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
  }

  private func lowerSimpleWhilePattern(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    body: TypedExpressionNode
  ) {
    let predecessorBlock = currentBlockID
    let conditionBlock = makeBlock()
    let bodyBlock = makeBlock()
    let exitBlock = makeBlock()
    setCurrentBlock(predecessorBlock)
    terminate(.goto(conditionBlock))

    setCurrentBlock(conditionBlock)
    let subjectValue = lowerValue(subject)
    guard !currentBlockIsTerminated else { return }
    let subjectLocal = makeTemporary(type: subject.type, nameHint: "while_pattern_subject")
    append(.declare(subjectLocal.id))
    append(.assign(.local(subjectLocal.id), subjectValue))
    let condition = lowerSimplePatternCondition(
      subjectValue: .placeRead(.local(subjectLocal.id), ownership: .borrow),
      subjectPlace: .local(subjectLocal.id),
      subjectType: subject.type,
      pattern: pattern,
      negated: false
    ) ?? .constant(.boolean(false))
    terminate(.branch(condition: condition, thenBlock: bodyBlock, elseBlock: exitBlock))

    setCurrentBlock(bodyBlock)
    loopStack.append((continueBlock: conditionBlock, breakBlock: exitBlock, scopeDepth: scopeStack.count))
    withPatternBindings(pattern: pattern, subjectPlace: .local(subjectLocal.id), subjectType: subject.type) {
      _ = lowerExpression(body)
    }
    _ = loopStack.popLast()
    if !currentBlockIsTerminated {
      terminate(.goto(conditionBlock))
    }

    setCurrentBlock(exitBlock)
  }

  private func canLowerSimpleWhen(subject: TypedExpressionNode, cases: [TypedMatchCase]) -> Bool {
    guard !context.containsGenericParameter(subject.type) else { return false }
    guard cases.allSatisfy({ canLowerPatternWithBindings($0.pattern, subjectType: subject.type) }) else { return false }
    return true
  }

  private func lowerSimpleWhenExpression(
    subject: TypedExpressionNode,
    cases: [TypedMatchCase],
    type: Type
  ) -> MIRExprResult? {
    guard !currentBlockIsTerminated else { return nil }

    let resultLocal: MIRLocal? = (type != .void && type != .never)
      ? makeTemporary(type: type, nameHint: "when_result")
      : nil
    if let resultLocal {
      append(.declare(resultLocal.id))
    }

    guard let preparedSubject = preparePatternSubject(subject, nameHint: "when_subject") else {
      return nil
    }
    let subjectPlace = preparedSubject.place
    let subjectScope = preparedSubject.scope

    let dispatchBlock = currentBlockID

    let caseBlocks = cases.map { _ in makeBlock() }
    let nextBlocks = cases.map { _ in makeBlock() }
    let joinBlock = makeBlock()
    let yieldTargetDepth = pushYieldTargets(
      cases.reduce(into: Set<YieldTargetId>()) { ids, matchCase in
        ids.formUnion(matchCase.body.ownedYieldTargetIDs)
      },
      resultLocal: resultLocal,
      joinBlock: joinBlock
    )
    defer { restoreYieldTargets(toDepth: yieldTargetDepth) }

    setCurrentBlock(dispatchBlock)

    for (index, matchCase) in cases.enumerated() {
      let checkBlock = currentBlockID
      let caseBlock = caseBlocks[index]
      let nextBlock = nextBlocks[index]

      setCurrentBlock(checkBlock)
      let subjectRead = MIRValue.placeRead(subjectPlace, ownership: .borrow)
      guard let condition = lowerSimplePatternCondition(
        subjectValue: subjectRead,
        subjectPlace: subjectPlace,
        subjectType: subject.type,
        pattern: matchCase.pattern,
        negated: false
      ) else {
        terminate(.goto(nextBlock))
        setCurrentBlock(nextBlock)
        continue
      }
      terminate(.branch(condition: condition, thenBlock: caseBlock, elseBlock: nextBlock))

      setCurrentBlock(caseBlock)
      withPatternBindings(pattern: matchCase.pattern, subjectPlace: subjectPlace, subjectType: subject.type) {
        lowerBranchBody(matchCase.body, resultLocal: resultLocal)
      }
      if !currentBlockIsTerminated {
        terminate(.goto(joinBlock))
      }

      setCurrentBlock(nextBlock)
    }

    if !currentBlockIsTerminated {
      terminate(.unreachable)
    }

    setCurrentBlock(joinBlock)
    if let subjectScope {
      append(.scopeExit(subjectScope))
      _ = scopeStack.popLast()
    }
    guard let resultLocal else {
      return MIRExprResult(type: type, category: .rvalue, operand: type == .void ? .constant(.void) : nil, place: nil)
    }
    return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
  }

  private func lowerArgumentValues(_ arguments: [TypedExpressionNode]) -> [MIRValue] {
    var values: [MIRValue] = []
    values.reserveCapacity(arguments.count)
    for argument in arguments {
      values.append(lowerValue(argument))
      if currentBlockIsTerminated { break }
    }
    return values
  }

  private func lowerBinary(
    left: TypedExpressionNode,
    right: TypedExpressionNode,
    type: Type,
    operatorKind: MIRBinaryOperator
  ) -> MIRExprResult {
    let leftOperand = lowerOperand(left)
    let rightOperand = lowerOperand(right)
    let result = materialize(
      .binary(MIRBinaryOperation(left: leftOperand, operatorKind: operatorKind, right: rightOperand, type: type)),
      type: type
    )
    return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
  }

  private func lowerShortCircuit(
    left: TypedExpressionNode,
    right: TypedExpressionNode,
    type: Type,
    shortCircuitValue: Bool
  ) -> MIRExprResult? {
    let resultLocal = makeTemporary(type: type, nameHint: shortCircuitValue ? "or_result" : "and_result")
    append(.declare(resultLocal.id))

    let leftOperand = lowerOperand(left)
    guard !currentBlockIsTerminated else { return nil }

    let branchBlock = currentBlockID
    let rightBlock = makeBlock()
    let shortBlock = makeBlock()
    let joinBlock = makeBlock()

    setCurrentBlock(branchBlock)
    if shortCircuitValue {
      terminate(.branch(condition: leftOperand, thenBlock: shortBlock, elseBlock: rightBlock))
    } else {
      terminate(.branch(condition: leftOperand, thenBlock: rightBlock, elseBlock: shortBlock))
    }

    setCurrentBlock(rightBlock)
    let rightScope = makeScopeID()
    append(.scopeEnter(rightScope))
    lowerBranchBody(right, resultLocal: resultLocal)
    if !currentBlockIsTerminated {
      append(.scopeExit(rightScope))
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(shortBlock)
    append(.assign(.local(resultLocal.id), .operand(.constant(.boolean(shortCircuitValue)))))
    terminate(.goto(joinBlock))

    setCurrentBlock(joinBlock)
    return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
  }

  private func lowerCall(
    callee: TypedExpressionNode,
    arguments: [TypedExpressionNode],
    type: Type,
    original: TypedExpressionNode
  ) -> MIRExprResult? {
    if case .methodReference(let base, let method, _, _, _) = callee,
       !context.containsGenericParameter(callee.type),
       let callableMethod = concreteMethodSymbol(method: method, calleeType: callee.type, resultType: type) {
      var argumentValues: [MIRValue] = [lowerValue(base)]
      guard !currentBlockIsTerminated else { return nil }
      argumentValues.reserveCapacity(arguments.count + 1)
      for argument in arguments {
        argumentValues.append(lowerValue(argument))
        guard !currentBlockIsTerminated else { return nil }
      }
      return finishCall(callee: .function(callableMethod), arguments: argumentValues, type: type)
    }

    if context.containsGenericParameter(callee.type)
      || arguments.contains(where: { context.containsGenericParameter($0.type) }) {
      fatalError("Unsupported generic dynamic call reached MIR lowering")
    }

    let calleeOperand = lowerOperand(callee)
    guard !currentBlockIsTerminated else { return nil }

    var argumentValues: [MIRValue] = []
    argumentValues.reserveCapacity(arguments.count)
    for argument in arguments {
      argumentValues.append(lowerValue(argument))
      guard !currentBlockIsTerminated else { return nil }
    }

    return finishCall(callee: calleeOperand, arguments: argumentValues, type: type)
  }

  private func concreteMethodSymbol(
    method: Symbol,
    calleeType: Type,
    resultType: Type
  ) -> Symbol? {
    guard case .function(let parameters, _) = calleeType else { return nil }

    let concreteType = Type.function(parameters: parameters, returns: resultType)
    guard !context.containsGenericParameter(concreteType) else { return nil }

    return Symbol(defId: method.defId, type: concreteType, kind: method.kind)
  }

  private func finishCall(
    callee: MIROperand,
    arguments: [MIRValue],
    type: Type
  ) -> MIRExprResult? {
    let value = MIRValue.call(MIRCall(callee: callee, arguments: arguments, type: type))
    if type == .never {
      append(.evaluate(value))
      terminate(.unreachable)
      return nil
    }
    if type == .void {
      append(.evaluate(value))
      return MIRExprResult(type: .void, category: .rvalue, operand: .constant(.void), place: nil)
    }
    let result = materialize(value, type: type)
    return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
  }

  private func lowerIntrinsicCall(_ intrinsic: TypedIntrinsic) -> MIRExprResult? {
    let resultType = intrinsic.type
    let lowered = MIRValue.intrinsic(lowerIntrinsic(intrinsic))
    if resultType == .never {
      append(.evaluate(lowered))
      terminate(.unreachable)
      return nil
    }
    if resultType == .void {
      append(.evaluate(lowered))
      return MIRExprResult(type: .void, category: .rvalue, operand: .constant(.void), place: nil)
    }
    let result = materialize(lowered, type: resultType)
    return MIRExprResult(type: resultType, category: .rvalue, operand: result, place: nil)
  }

  private func lowerIntrinsic(_ intrinsic: TypedIntrinsic) -> MIRIntrinsic {
    switch intrinsic {
    case .allocMemory(let count, let resultType):
      return .allocMemory(count: lowerValue(count), resultType: resultType)
    case .deallocMemory(let ptr):
      return .deallocMemory(ptr: lowerValue(ptr))
    case .copyMemory(let dest, let source, let count):
      return .copyMemory(dest: lowerValue(dest), source: lowerValue(source), count: lowerValue(count))
    case .moveMemory(let dest, let source, let count):
      return .moveMemory(dest: lowerValue(dest), source: lowerValue(source), count: lowerValue(count))
    case .isUniqueMutable(let value):
      return .isUniqueMutable(value: lowerUniquenessProbeValue(value))
    case .makeRef(let ptr, let owner, let resultType):
      return .makeRef(ptr: lowerValue(ptr), owner: lowerValue(owner), resultType: resultType)
    case .makeMutRef(let ptr, let owner, let resultType):
      return .makeMutRef(ptr: lowerValue(ptr), owner: lowerValue(owner), resultType: resultType)
    case .refCount(let ref):
      return .refCount(ref: lowerValue(ref))
    case .downgradeRef(let value, let resultType):
      return .downgradeRef(value: lowerValue(value), resultType: resultType)
    case .downgradeMutRef(let value, let resultType):
      return .downgradeMutRef(value: lowerValue(value), resultType: resultType)
    case .upgradeRef(let value, let resultType):
      return .upgradeRef(value: lowerValue(value), resultType: resultType)
    case .upgradeMutRef(let value, let resultType):
      return .upgradeMutRef(value: lowerValue(value), resultType: resultType)
    case .initMemory(let ptr, let value):
      return .initMemory(ptr: lowerValue(ptr), value: lowerValue(value))
    case .deinitMemory(let ptr):
      return .deinitMemory(ptr: lowerValue(ptr))
    case .takeMemory(let ptr):
      return .takeMemory(ptr: lowerValue(ptr), resultType: intrinsic.type)
    case .nullPtr(let resultType):
      return .nullPtr(resultType: resultType)
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      return .spawnThread(
        outHandle: lowerValue(outHandle),
        outTid: lowerValue(outTid),
        closure: lowerValue(closure),
        stackSize: lowerValue(stackSize)
      )
    }
  }

  private func lowerUnary(
    inner: TypedExpressionNode,
    type: Type,
    operatorKind: MIRUnaryOperator
  ) -> MIRExprResult {
    let operand = lowerOperand(inner)
    let result = materialize(.unary(MIRUnaryOperation(operatorKind: operatorKind, operand: operand, type: type)), type: type)
    return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
  }

  private func lowerValue(_ expression: TypedExpressionNode) -> MIRValue {
    if context.containsGenericParameter(expression.type) {
      switch expression {
      case .referenceExpression(let inner, let type):
        if let place = lowerPlace(inner) {
          return .ref(place, kind: referenceKind(for: type), allocation: .stackBorrow)
        }
      case .ptrExpression(let inner, _):
        if let place = lowerPlace(inner) {
          return .pointer(place)
        }
      default:
        break
      }
    }
    if let result = lowerExpression(expression) {
      if let operand = result.operand {
        return .operand(operand)
      }
      if let place = result.place {
        return .placeRead(place, ownership: .copy)
      }
    }
    return .operand(.constant(.void))
  }

  private func lowerUniquenessProbeValue(_ expression: TypedExpressionNode) -> MIRValue {
    if case .castExpression(let inner, let targetType) = expression,
       isOwnershipPreservingProbeCast(sourceType: inner.type, targetType: targetType) {
      return lowerUniquenessProbeValue(inner)
    }

    if let result = lowerExpression(expression) {
      if let place = result.place {
        return .placeRead(place, ownership: .borrow)
      }
      if let operand = result.operand {
        if case .local(let localID) = operand {
          return .placeRead(.local(localID), ownership: .borrow)
        }
        return .operand(operand)
      }
    }

    return .operand(.constant(.void))
  }

  /// Returns true for types that have move-only (unique) semantics:
  /// mutable references, mutable pointers, and mutable weak references.
  private func isMoveOnlyType(_ type: Type) -> Bool {
    switch type {
    case .mutableReference, .mutablePointer, .mutableWeakReference:
      return true
    default:
      return false
    }
  }

  private func isOwnershipPreservingProbeCast(sourceType: Type, targetType: Type) -> Bool {
    switch (sourceType, targetType) {
    case (.reference, .reference),
         (.reference, .mutableReference),
         (.mutableReference, .reference),
         (.mutableReference, .mutableReference),
         (.weakReference, .weakReference),
         (.weakReference, .mutableWeakReference),
         (.mutableWeakReference, .weakReference),
         (.mutableWeakReference, .mutableWeakReference):
      return true
    default:
      return false
    }
  }

  private func lowerOperand(_ expression: TypedExpressionNode) -> MIROperand {
    if let result = lowerExpression(expression) {
      if let operand = result.operand {
        return operand
      }
      if let place = result.place {
        return materialize(.placeRead(place, ownership: .copy), type: result.type)
      }
    }
    return .constant(.void)
  }

  private func materialize(_ value: MIRValue, type: Type) -> MIROperand {
    if type == .void {
      append(.evaluate(value))
      return .constant(.void)
    }
    let local = makeTemporary(type: type)
    append(.declare(local.id))
    append(.assign(.local(local.id), value))
    return .local(local.id)
  }

  private func lowerPlace(_ expression: TypedExpressionNode) -> MIRPlace? {
    switch expression {
    case .variable(let symbol):
      return capturePlace(for: symbol)
    case .memberPath(let source, let path):
      let basePlace: MIRPlace?
      switch source.type {
      case .reference(let inner),
           .mutableReference(let inner),
           .weakReference(let inner),
           .mutableWeakReference(let inner),
           .pointer(let inner),
           .mutablePointer(let inner):
        basePlace = .deref(base: .operand(lowerOperand(source)), pointee: inner)
      default:
        basePlace = lowerPlace(source)
      }
      guard var place = basePlace else { return nil }
      for field in path {
        place = .field(base: place, field: field)
      }
      return place
    case .derefExpression(let inner, let type):
      return .deref(base: .operand(lowerOperand(inner)), pointee: type)
    case .castExpression(let inner, let type):
      switch (inner.type, type) {
      case (.reference, .reference),
           (.reference, .mutableReference),
           (.mutableReference, .reference),
           (.mutableReference, .mutableReference):
        return lowerPlace(inner)
      default:
        if inner.type == type {
          return lowerPlace(inner)
        }
        return nil
      }
    default:
      return nil
    }
  }

  private func capturePlace(for symbol: Symbol) -> MIRPlace {
    if let local = localByDefId[symbol.defId.id] {
      return .local(local)
    }
    if let place = patternPlaceByDefId[symbol.defId.id] {
      return place
    }
    return .global(symbol.defId)
  }

  private func referenceKind(for type: Type) -> MIRReferenceKind {
    switch type {
    case .mutableReference:
      return .mutable
    case .weakReference:
      return .weak
    case .mutableWeakReference:
      return .mutableWeak
    default:
      return .shared
    }
  }

  private func needsDrop(_ type: Type) -> Bool {
    switch type {
    case .structure, .enum, .reference, .mutableReference, .function, .weakReference, .mutableWeakReference:
      return true
    default:
      return false
    }
  }

}

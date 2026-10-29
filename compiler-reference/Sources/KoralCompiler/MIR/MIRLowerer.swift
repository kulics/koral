import Foundation

final class MIRLowerer {
  private let program: MonomorphizedProgram
  private let context: CompilerContext

  private struct InstantiatedTraitMethod {
    let traitRef: CanonicalTraitRef
    let methodName: String
    let signature: TraitMethodSignature
    let substitution: [String: Type]
  }

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
          let loweredParameters = canonicalDropParameters(
            identifier: identifier,
            parameters: parameters,
            traitConformance: nil
          )
          functions.append(
            lowerFunction(
              identifier: identifier,
              parameters: loweredParameters,
              body: body,
              kind: kind
            )
          )
        }
      case .givenDeclaration(let type, let trait, let methods):
        globals.append(.given(type: type, trait: trait, methods: methods.map(\.identifier)))
        guard !context.containsGenericParameter(type) else { continue }
        for method in methods where shouldLowerFunction(identifier: method.identifier) {
          let params = canonicalDropParameters(
            identifier: method.identifier,
            parameters: method.parameters,
            traitConformance: trait
          )
          functions.append(
            lowerFunction(
              identifier: method.identifier,
              parameters: params,
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
      traitDeclsByDefId: program.traitDeclsByDefId,
      conformanceWitnesses: program.conformanceWitnesses,
      receiverMethodDispatch: program.receiverMethodDispatch
    )
    return loweredProgram
  }

  /// For std Drop implementations, `drop(self)` lowers to a mutable pointer
  /// receiver in MIR/C. This is identity-based (`conformanceTraitDefId` +
  /// logical method name), never derived from the instantiated symbol spelling.
  private func canonicalDropParameters(
    identifier: Symbol,
    parameters: [Symbol],
    traitConformance: TypedTraitConformance?
  ) -> [Symbol] {
    guard isStdDropMethod(identifier: identifier, traitConformance: traitConformance),
          let first = parameters.first,
          context.getName(first.defId) == "self"
    else {
      return parameters
    }

    let baseSelfType: Type
    switch first.type {
    case .mutablePointer(let inner):
      baseSelfType = inner
    default:
      baseSelfType = first.type
    }

    let pointerSelf = Symbol(
      defId: first.defId,
      type: .mutablePointer(element: baseSelfType),
      kind: first.kind
    )
    return [pointerSelf] + Array(parameters.dropFirst())
  }

  private func isStdDropMethod(
    identifier: Symbol,
    traitConformance: TypedTraitConformance?
  ) -> Bool {
    guard let stdDrop = context.stdDropTraitDefId else {
      return false
    }

    if let traitConformance, traitConformance.traitDefId != stdDrop {
      return false
    }

    guard let dispatch = program.receiverMethodDispatch[identifier.defId] else {
      return false
    }

    return dispatch.conformanceTraitDefId == stdDrop && dispatch.methodName == "drop"
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
      traitDefId: request.traitDefId,
      traitTypeArguments: request.traitTypeArgs,
      methods: methods
    )
  }

  private func makeTraitVTableMethods(for request: VtableRequest) -> [MIRTraitVTableMethod] {
    let traitRef = CanonicalTraitRef(
      traitName: request.traitName,
      traitDefId: request.traitDefId,
      traitTypeArgs: request.traitTypeArgs
    )
    if let witness = program.conformanceWitnesses[request.witnessKey] {
      return witness.requirementSlots.map { slot in
        MIRTraitVTableMethod(
          traitMethodDefId: slot.traitMethodDefId,
          name: slot.methodName,
          returnType: slot.returnType,
          parameters: slot.parameters.map {
            MIRTraitVTableParameter(
              name: $0.name,
              type: $0.type,
              isSelf: $0.name == "self"
            )
          },
          selfByValue: isSelfByValueRequirementSlot(slot)
        )
      }
    }
    let orderedMethods = instantiatedTraitMethods(for: traitRef, concreteType: request.concreteType)
    return orderedMethods.map { method in
      let parameters = method.signature.parameters.map { parameter in
        MIRTraitVTableParameter(
          name: parameter.name,
          type: resolveVTableTypeNode(parameter.type, traitTypeParamSubstitution: method.substitution),
          isSelf: parameter.name == "self"
        )
      }
      return MIRTraitVTableMethod(
        traitMethodDefId: .invalid,
        name: method.methodName,
        returnType: resolveVTableTypeNode(method.signature.returnType, traitTypeParamSubstitution: method.substitution),
        parameters: parameters,
        selfByValue: isSelfByValueTraitSignature(method.signature)
      )
    }
  }

  private func isSelfByValueRequirementSlot(_ slot: RequirementSlot) -> Bool {
    guard let firstParam = slot.parameters.first, firstParam.name == "self" else {
      return false
    }
    switch firstParam.type {
    case .reference,
         .mutableReference,
         .borrowedReference,
         .mutableBorrowedReference,
         .weakReference,
         .mutableWeakReference,
         .pointer,
         .mutablePointer:
      return false
    default:
      return true
    }
  }

  private func instantiatedTraitMethods(
    for traitRef: CanonicalTraitRef,
    concreteType: Type
  ) -> [InstantiatedTraitMethod] {
    var ordered: [InstantiatedTraitMethod] = []
    var seenMethods: Set<String> = []
    var visitedTraits: Set<String> = []
    collectInstantiatedTraitMethods(
      for: traitRef,
      concreteType: concreteType,
      visitedTraits: &visitedTraits,
      seenMethods: &seenMethods,
      ordered: &ordered
    )
    return ordered
  }

  private func collectInstantiatedTraitMethods(
    for traitRef: CanonicalTraitRef,
    concreteType: Type,
    visitedTraits: inout Set<String>,
    seenMethods: inout Set<String>,
    ordered: inout [InstantiatedTraitMethod]
  ) {
    let visitKey = "\(traitRef.cacheKey)|self=\(context.getDebugName(concreteType))"
    // The ref already carries its declaration, so look that up rather than
    // re-resolving the spelling (an alias, or a same-named trait from another
    // module). The name path remains only for a ref that never got one.
    let traitInfo = traitRef.traitDefId.isValid
      ? program.traitDeclsByDefId[traitRef.traitDefId]
      : program.traits[traitRef.traitName]
    guard visitedTraits.insert(visitKey).inserted,
          let traitInfo else {
      return
    }

    let substitution = traitTypeParameterSubstitution(
      traitName: traitRef.traitName,
      traitTypeArgs: traitRef.traitTypeArgs,
      concreteType: concreteType
    )

    for parent in traitInfo.superTraits {
      guard let parentRef = instantiateTraitRef(parent, substitution: substitution) else {
        continue
      }
      collectInstantiatedTraitMethods(
        for: parentRef,
        concreteType: concreteType,
        visitedTraits: &visitedTraits,
        seenMethods: &seenMethods,
        ordered: &ordered
      )
    }

    for method in traitInfo.methods where seenMethods.insert(method.name).inserted {
      ordered.append(
        InstantiatedTraitMethod(
          traitRef: traitRef,
          methodName: method.name,
          signature: method,
          substitution: substitution
        )
      )
    }
  }

  private func instantiateTraitRef(
    _ constraint: TraitConstraint,
    substitution: [String: Type]
  ) -> CanonicalTraitRef? {
    switch constraint {
    case .trait(let defId, let name, let args):
      let resolvedArgs = args.compactMap {
        resolveVTableTypeNode($0, traitTypeParamSubstitution: substitution)
      }
      guard resolvedArgs.count == args.count else {
        return nil
      }
      return CanonicalTraitRef(traitName: name, traitDefId: defId, traitTypeArgs: resolvedArgs)
    case .mutable, .foreign:
      // A shape requirement is not a trait; it has no vtable ref.
      return nil
    }
  }

  private func traitTypeParameterSubstitution(
    traitName: String,
    traitTypeArgs: [Type],
    concreteType: Type
  ) -> [String: Type] {
    var result: [String: Type] = ["Self": concreteType]
    guard let traitInfo = program.traits[traitName], !traitInfo.typeParameters.isEmpty else {
      return result
    }
    for (index, parameter) in traitInfo.typeParameters.enumerated() where index < traitTypeArgs.count {
      result[parameter.name] = traitTypeArgs[index]
    }
    return result
  }

  private func isSelfByValueTraitSignature(_ signature: TraitMethodSignature) -> Bool {
    guard let firstParam = signature.parameters.first, firstParam.name == "self" else {
      return false
    }
    switch firstParam.type {
    case .reference:
      return false
    default:
      break
    }
    return true
  }

  private func resolveVTableTypeNode(
    _ node: TypeNode,
    traitTypeParamSubstitution: [String: Type]
  ) -> Type? {
    switch node {
    case .identifier(let name, _):
      if let substituted = traitTypeParamSubstitution[name] {
        return substituted
      }
      if let builtinType = SemaUtils.resolveBuiltinType(name) {
        return builtinType
      }
      return resolveNominalVTableType(named: name)
    case .reference(let inner, let mutable, _):
      guard let resolved = resolveVTableTypeNode(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) else {
        return nil
      }
      return mutable ? .mutableReference(inner: resolved) : .reference(inner: resolved)
    case .weakReference(let inner, let mutable, _):
      guard let resolved = resolveVTableTypeNode(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) else {
        return nil
      }
      return mutable ? .mutableWeakReference(inner: resolved) : .weakReference(inner: resolved)
    case .pointer(let inner, let mutable, _):
      guard let resolved = resolveVTableTypeNode(inner, traitTypeParamSubstitution: traitTypeParamSubstitution) else {
        return nil
      }
      return mutable ? .mutablePointer(element: resolved) : .pointer(element: resolved)
    case .generic(let base, let args, _):
      let resolvedArgs = args.compactMap {
        resolveVTableTypeNode($0, traitTypeParamSubstitution: traitTypeParamSubstitution)
      }
      guard resolvedArgs.count == args.count else { return nil }
      return resolveGenericVTableType(named: base, args: resolvedArgs)
    case .functionType(let paramTypes, let returnType, _):
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
      return traitTypeParamSubstitution["Self"]
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
          return .genericStruct(templateDefId: context.templateDeclaration(of: identifier.defId), args: args)
        }
      case .globalEnumDeclaration(let identifier, _):
        if nominalSymbol(identifier, matches: name) {
          return .genericEnum(templateDefId: context.templateDeclaration(of: identifier.defId), args: args)
        }
      default:
        continue
      }
    }

    if let defId = context.lookupDefId(modulePath: [], name: name, sourceFile: nil),
       let kind = context.getKind(defId) {
      switch kind {
      case .type(.structure), .genericTemplate(.structure):
        return .genericStruct(templateDefId: context.templateDeclaration(of: defId), args: args)
      case .type(.`enum`), .genericTemplate(.`enum`):
        return .genericEnum(templateDefId: context.templateDeclaration(of: defId), args: args)
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
  private var deferredExpressionsByScope: [MIRScopeID: [TypedExpressionNode]] = [:]

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
    storage: MIRStorage,
    symbol: Symbol?
  ) -> MIRLocal {
    let id = MIRLocalID(rawValue: nextLocalID)
    nextLocalID += 1
    let local = MIRLocal(
      id: id,
      name: name,
      type: type,
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
        let resolvedType = programFunctionType(for: symbol.defId) ?? receiverAwareFunctionType(for: symbol)
        let resolvedSymbol = Symbol(defId: symbol.defId, type: resolvedType, kind: symbol.kind)
        return MIRExprResult(type: resolvedType, category: .rvalue, operand: .function(resolvedSymbol), place: nil)
      }
      let place = lowerPlace(expression) ?? .global(symbol.defId)
      return MIRExprResult(type: symbol.type, category: expression.valueCategory, operand: nil, place: place)
    case .blockExpression(let statements, let tailExpression, let type):
      return lowerBlock(statements: statements, tailExpression: tailExpression, type: type)
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
    case .derefExpression, .unsafeDerefExpression:
      if let place = lowerPlace(expression) {
        return MIRExprResult(type: expression.type, category: .lvalue, operand: nil, place: place)
      }
      if case .derefExpression = expression {
        fatalError("Unsupported deref expression value reached MIR lowering")
      }
      if case .unsafeDerefExpression = expression {
        fatalError("Unsupported unsafe deref expression value reached MIR lowering")
      }
      return nil
    case .memberPath:
      if let place = lowerPlace(expression) {
        return MIRExprResult(type: expression.type, category: expression.valueCategory, operand: nil, place: place)
      }
      if let place = lowerMaterializedMemberPathPlace(expression) {
        return MIRExprResult(type: expression.type, category: expression.valueCategory, operand: nil, place: place)
      }
      fatalError("Unsupported member-path value reached MIR lowering")
    case .intrinsicCall(let intrinsic):
      return lowerIntrinsicCall(intrinsic)
    case .whenExpression(let subject, let cases, let type):
      if canLowerSimpleWhen(subject: subject, cases: cases) {
        if canLowerToSwitchValue(subject: subject, cases: cases) {
          return lowerSwitchWhenExpression(subject: subject, cases: cases, type: type)
        }
        return lowerSimpleWhenExpression(subject: subject, cases: cases, type: type)
      }
      fatalError("Unsupported when expression reached MIR lowering: subject=\(subject.type) caseCount=\(cases.count)")
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
    case .traitMethodPlaceholder(let traitName, _, let traitMethodDefId, let methodName, let base, _, let type):
      fatalError("Unsupported trait method placeholder reached MIR lowering: \(traitName).\(methodName)#\(traitMethodDefId.id) base=\(base.type) type=\(type)")
    case .traitObjectConversion(let inner, let traitName, let traitDefId, let traitTypeArgs, let concreteType, let type):
      let loweredInner: MIRValue
      if case .referenceExpression(let sourceExpr, let refType) = inner,
         let place = lowerPlace(sourceExpr) {
        let allocation: MIRReferenceAllocation = ownershipUse(for: inner) == .move ? .heapOwnedMove : .heapOwned
        loweredInner = .ref(place, kind: referenceKind(for: refType), allocation: allocation)
      } else {
        loweredInner = lowerValue(inner)
      }
      let result = materialize(
        .traitObjectConversion(
          MIRTraitObjectConversion(
            inner: loweredInner,
            sourceOwnership: ownershipUse(for: inner),
            traitName: traitName,
            traitDefId: traitDefId,
            traitTypeArguments: traitTypeArgs,
            concreteType: concreteType,
            type: type
          )
        ),
        type: type
      )
      return MIRExprResult(type: type, category: .rvalue, operand: result, place: nil)
    case .traitMethodCall(let receiver, let traitName, let traitDefId, let methodName, let methodIndex, let arguments, let type):
      let value = MIRValue.traitMethodCall(
        MIRTraitMethodCall(
          receiver: lowerValue(receiver),
          receiverOwnership: ownershipUse(for: receiver),
          traitName: traitName,
          traitDefId: traitDefId,
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

  private func lowerBlock(statements: [TypedStatementNode], tailExpression: TypedExpressionNode?, type: Type) -> MIRExprResult? {
    let parentScopeDepth = scopeStack.count
    let scope = makeScopeID()
    append(.scopeEnter(scope))
    scopeStack.append(scope)
    let blockProducesValue = type != .void && type != .never
    let resultLocal: MIRLocal? = blockProducesValue
      ? makeTemporary(type: type, nameHint: "block_result")
      : nil
    if let resultLocal {
      append(.declare(resultLocal.id))
    }

    let result: MIRExprResult?

    for statement in statements {
      lowerStatement(statement)
    }

    if let tailExpression, !currentBlockIsTerminated {
      result = lowerExpression(tailExpression)
    } else {
      result = MIRExprResult(type: type, category: .rvalue, operand: type == .void ? .constant(.void) : nil, place: nil)
    }

    if let resultLocal, let result, !currentBlockIsTerminated {
      assignBranchResult(result, to: resultLocal.id)
    }

    if !currentBlockIsTerminated {
      emitDeferredExpressions(for: scope)
    }
    if !currentBlockIsTerminated {
      append(.scopeExit(scope))
    }
    _ = scopeStack.popLast()
    deferredExpressionsByScope.removeValue(forKey: scope)

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
    case .tupleVariableDeclaration(let tupleSymbol, let tupleValue, let bindings):
      lowerTupleVariableDeclaration(
        tupleSymbol: tupleSymbol,
        tupleValue: tupleValue,
        bindings: bindings
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
      let expressionCases = cases.map { TypedMatchCase(pattern: $0.pattern, guardExpr: $0.guardExpr, body: $0.body) }
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
          .ref(place, kind: referenceKind(for: type), allocation: .heapOwnedMove),
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
    case .deferStatement(let expression):
      if let scope = scopeStack.last {
        deferredExpressionsByScope[scope, default: []].append(expression)
      } else {
        _ = lowerExpression(expression)
      }
    }
  }

  private func emitScopeExits(fromDepth baseScopeDepth: Int) {
    guard scopeStack.count > baseScopeDepth else { return }
    for scope in scopeStack[baseScopeDepth...].reversed() {
      emitDeferredExpressions(for: scope)
      guard !currentBlockIsTerminated else { return }
      append(.scopeExit(scope))
    }
  }

  private func emitDeferredExpressions(for scope: MIRScopeID) {
    guard let deferredExpressions = deferredExpressionsByScope[scope], !deferredExpressions.isEmpty else { return }
    for expression in deferredExpressions.reversed() {
      lowerStatement(.expression(expression))
      guard !currentBlockIsTerminated else { return }
    }
  }

  private func lowerBranchBody(_ expression: TypedExpressionNode, resultLocal: MIRLocal?) {
    guard let resultLocal, expression.type != .never, expression.type != .void else {
      _ = lowerExpression(expression)
      return
    }

    if case .referenceExpression(let inner, let type) = expression,
       let place = lowerPlace(inner) {
      let refValue = MIRValue.ref(place, kind: referenceKind(for: type), allocation: .heapOwned)
      append(.assign(.local(resultLocal.id), refValue))
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

    // If the subject is already a place (variable/parameter), use it directly.
    // This avoids copying into a temporary, which would cause double-drop:
    // the temporary is dropped at scope_exit AND the original is dropped later.
    if let place = result.place {
      return (place, nil)
    }

    // For complex expressions (rvalues), evaluate once and store in a temporary.
    // The temporary is dropped at when/if scope_exit.
    if let operand = result.operand {
      let subjectScope = makeScopeID()
      append(.scopeEnter(subjectScope))
      scopeStack.append(subjectScope)

      let subjectLocal = makeTemporary(type: subject.type, nameHint: nameHint)
      append(.declare(subjectLocal.id))
      append(.assign(.local(subjectLocal.id), .operand(operand)))
      return (.local(subjectLocal.id), subjectScope)
    }

    return nil
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

  /// `let (a, b, c) = expr;` -- bind each slot to the struct field at the same
  /// position. The number of slots equals the number of fields.
  private func lowerTupleVariableDeclaration(
    tupleSymbol: Symbol,
    tupleValue: TypedExpressionNode,
    bindings: [Symbol?]
  ) {
    let tupleInitialValue = lowerValue(tupleValue)
    guard !currentBlockIsTerminated else { return }

    let tupleLocal = makeLocal(
      name: context.getName(tupleSymbol.defId) ?? "tuple_\(tupleSymbol.defId.id)",
      type: tupleSymbol.type,
      storage: .temporary,
      symbol: tupleSymbol
    )
    localByDefId[tupleSymbol.defId.id] = tupleLocal.id
    append(.declare(tupleLocal.id))
    append(.assign(.local(tupleLocal.id), tupleInitialValue))

    let tuplePlace = MIRPlace.local(tupleLocal.id)
    for (index, binding) in bindings.enumerated() {
      lowerTupleBinding(
        symbol: binding,
        index: index,
        tuplePlace: tuplePlace,
        tupleType: tupleSymbol.type
      )
    }
  }

  /// A slot binds the struct field at the same position. The field list comes
  /// from the type's DECLARATION order -- identity only, never a name lookup.
  /// A discarded slot drops its field at the destructuring site.
  private func lowerTupleBinding(
    symbol: Symbol?,
    index: Int,
    tuplePlace: MIRPlace,
    tupleType: Type
  ) {
    guard let members = resolvedPatternStructMembers(for: tupleType),
          members.indices.contains(index) else {
      return
    }
    let member = members[index]
    let fieldPlace = MIRPlace.field(
      base: tuplePlace,
      field: makeSyntheticPatternFieldSymbol(name: member.name, type: member.type)
    )
    guard let symbol else {
      if needsDrop(member.type) {
        append(.drop(fieldPlace))
      }
      return
    }

    let local = makeLocal(
      name: context.getName(symbol.defId) ?? "local_\(symbol.defId.id)",
      type: symbol.type,
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
    // `?name` / `is not ?name`: test liveness of the upgrade result. A
    // positive test also binds the strong reference from the Some payload.
    if case .weakBinding = pattern {
      return lowerWeakBindingPatternTest(subject: subject, pattern: pattern, negated: negated, type: type)
    }
    // A positive test whose pattern binds establishes the bindings only on the
    // matching edge: the names are live in the rest of the guard and in the
    // body, and a failed test must not write payload values into their slots.
    if !negated, pattern.introducesBinding {
      return lowerBindingPatternTest(subject: subject, pattern: pattern, type: type)
    }
    if !context.containsGenericParameter(subject.type),
       canLowerSimplePattern(pattern, subjectType: subject.type),
       let operand = lowerSimplePatternTest(subject: subject, pattern: pattern, negated: negated) {
      return MIRExprResult(type: type, category: .rvalue, operand: operand, place: nil)
    }
    fatalError("Unsupported pattern test reached MIR lowering")
  }

  /// The Bool result of a binding `is` test, with the pattern's slots filled
  /// on the matching edge. One slot per name is claimed before the test and
  /// filled on success: the names are live in the rest of the guard and in the
  /// body -- and must land in the SAME slots however many readings a guarded
  /// arm re-runs the guard on -- and a failed test must not write payload
  /// values into them (reading a non-matching variant's payload is garbage).
  /// The subject stays in an ordinary temporary (no scope teardown) so the
  /// fill's source places stay live through the guard's tail and the body.
  private func lowerBindingPatternTest(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    type: Type
  ) -> MIRExprResult? {
    let subjectPlace: MIRPlace
    if let place = lowerPlace(subject) {
      subjectPlace = place
    } else {
      let subjectValue = lowerValue(subject)
      guard !currentBlockIsTerminated else { return nil }
      let subjectLocal = makeTemporary(type: subject.type, nameHint: "is_test_subject")
      append(.declare(subjectLocal.id))
      append(.assign(.local(subjectLocal.id), subjectValue))
      subjectPlace = .local(subjectLocal.id)
    }
    declarePatternBindingLocals(for: pattern)
    guard let condition = lowerSimplePatternCondition(
      subjectValue: .placeRead(subjectPlace, ownership: .borrow),
      subjectPlace: subjectPlace,
      subjectType: subject.type,
      pattern: pattern,
      negated: false
    ) else {
      return MIRExprResult(type: type, category: .rvalue, operand: .constant(.boolean(false)), place: nil)
    }
    let resultLocal = makeTemporary(type: .bool, nameHint: "is_test")
    append(.declare(resultLocal.id))
    let conditionEnd = currentBlockID
    let bindBlock = makeBlock()
    let failBlock = makeBlock()
    let joinBlock = makeBlock()
    setCurrentBlock(conditionEnd)
    terminate(.branch(condition: condition, thenBlock: bindBlock, elseBlock: failBlock))

    setCurrentBlock(bindBlock)
    assignPatternBindingLocals(pattern: pattern, subjectPlace: subjectPlace, subjectType: subject.type)
    append(.assign(.local(resultLocal.id), .operand(.constant(.boolean(true)))))
    terminate(.goto(joinBlock))

    setCurrentBlock(failBlock)
    append(.assign(.local(resultLocal.id), .operand(.constant(.boolean(false)))))
    terminate(.goto(joinBlock))

    setCurrentBlock(joinBlock)
    return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
  }

  /// Liveness test plus (on the alive edge) the strong-reference binding for
  /// `?name`. `is not ?name` keeps the negated liveness test and no binding:
  /// the name there is only a probe for death. The subject is the upgrade
  /// intrinsic (`Option[T]`), so liveness is the Some tag; the fill extracts
  /// the Some payload into the name's claimed slot.
  private func lowerWeakBindingPatternTest(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    negated: Bool,
    type: Type
  ) -> MIRExprResult? {
    let subjectPlace: MIRPlace
    if let place = lowerPlace(subject) {
      subjectPlace = place
    } else {
      let subjectValue = lowerValue(subject)
      guard !currentBlockIsTerminated else { return nil }
      let subjectLocal = makeTemporary(type: subject.type, nameHint: "weak_test_subject")
      append(.declare(subjectLocal.id))
      append(.assign(.local(subjectLocal.id), subjectValue))
      subjectPlace = .local(subjectLocal.id)
    }
    let tagOperand = materialize(
      .enumTag(MIREnumTag(
        subject: .placeRead(subjectPlace, ownership: .borrow),
        enumType: subject.type)),
      type: .int)
    // Niche layout: 0 = None, 1 = Some. Alive = tag != 0.
    let aliveOperand = materialize(
      .binary(MIRBinaryOperation(
        left: tagOperand,
        operatorKind: .comparison(.notEqual),
        right: .constant(.integer("0", .int)),
        type: .bool)),
      type: .bool)
    if negated {
      return MIRExprResult(
        type: type,
        category: .rvalue,
        operand: materialize(
          .binary(MIRBinaryOperation(
            left: aliveOperand,
            operatorKind: .comparison(.equal),
            right: .constant(.boolean(false)),
            type: .bool)),
          type: .bool),
        place: nil)
    }
    declarePatternBindingLocals(for: pattern)
    let resultLocal = makeTemporary(type: .bool, nameHint: "is_test")
    append(.declare(resultLocal.id))
    let conditionEnd = currentBlockID
    let bindBlock = makeBlock()
    let failBlock = makeBlock()
    let joinBlock = makeBlock()
    setCurrentBlock(conditionEnd)
    terminate(.branch(condition: aliveOperand, thenBlock: bindBlock, elseBlock: failBlock))

    setCurrentBlock(bindBlock)
    assignPatternBindingLocals(pattern: pattern, subjectPlace: subjectPlace, subjectType: subject.type)
    append(.assign(.local(resultLocal.id), .operand(.constant(.boolean(true)))))
    terminate(.goto(joinBlock))

    setCurrentBlock(failBlock)
    append(.assign(.local(resultLocal.id), .operand(.constant(.boolean(false)))))
    terminate(.goto(joinBlock))

    setCurrentBlock(joinBlock)
    return MIRExprResult(type: type, category: .rvalue, operand: .local(resultLocal.id), place: nil)
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
    let matchedSubject = patternMatchSubject(value: subjectValue, type: subjectType, pattern: pattern)
    let matchedValue = matchedSubject.value
    let matchedType = matchedSubject.type
    let matchedPlace = subjectPlace.map { patternMatchPlace(place: $0, type: subjectType, pattern: pattern).place }

    switch pattern {
    case .wildcard, .variable:
      return .constant(.boolean(!negated))
    case .weakBinding:
      // `?name` in `when` / `is`: test liveness. If the subject is still the
      // weak handle, upgrade first; if it is already `Option[T]` (the `when`
      // desugaring wrapped it), just read the tag.
      let optionType: Type
      let subjectForTag: MIRValue
      switch subjectType {
      case .weakReference(let inner), .mutableWeakReference(let inner):
        optionType = Type.genericEnum(
          templateDefId: context.defIdMap.lookupGenericEnumTemplateDefId("Option") ?? .invalid,
          args: [inner])
        let upgradeLocal = makeTemporary(type: optionType, nameHint: "weak_cond_up")
        append(.declare(upgradeLocal.id))
        append(.assign(.local(upgradeLocal.id), .intrinsic(.upgradeRef(
          value: subjectValue, resultType: optionType))))
        subjectForTag = .placeRead(.local(upgradeLocal.id), ownership: .borrow)
      default:
        // Already an Option[T] (the subject was wrapped during type checking).
        optionType = subjectType
        subjectForTag = subjectValue
      }
      // The niche-layout `enumTag` returns 0 for None, 1 for Some.
      let tagOperand = materialize(
        .enumTag(MIREnumTag(
          subject: subjectForTag,
          enumType: optionType)),
        type: .int)
      let isAlive = MIRValue.binary(MIRBinaryOperation(
        left: tagOperand,
        operatorKind: .comparison(.notEqual),
        right: .constant(.integer("0", .int)),
        type: .bool))
      let aliveOperand = materialize(isAlive, type: .bool)
      return negated ? materialize(
        .binary(MIRBinaryOperation(
          left: aliveOperand,
          operatorKind: .comparison(.equal),
          right: .constant(.boolean(false)),
          type: .bool)),
        type: .bool) : aliveOperand
    case .traitObjectType(let targetType):
      return lowerTraitObjectTypePatternCondition(
        subjectValue: matchedValue,
        subjectType: matchedType,
        targetType: targetType,
        negated: negated
      )
    case .traitObjectTypeBinding(_, let targetType):
      return lowerTraitObjectTypePatternCondition(
        subjectValue: matchedValue,
        subjectType: matchedType,
        targetType: targetType,
        negated: negated
      )
    case .booleanLiteral(let value):
      guard matchedType == .bool else { return nil }
      let subjectOperand = materialize(matchedValue, type: matchedType)
      let expected = MIROperand.constant(.boolean(value))
      let op: ComparisonOperator = negated ? .notEqual : .equal
      return materialize(
        .binary(MIRBinaryOperation(left: subjectOperand, operatorKind: .comparison(op), right: expected, type: .bool)),
        type: .bool
      )
    case .nullLiteral(let resultType):
      // `p is null`: compare against a null pointer of the subject's own
      // pointer type (the pattern joined that type when it was checked).
      let nullType: Type
      switch matchedType {
      case .pointer, .mutablePointer:
        nullType = matchedType
      default:
        nullType = resultType
      }
      let subjectOperand = materialize(matchedValue, type: nullType)
      let nullOperand = materialize(.intrinsic(.nullPtr(resultType: nullType)), type: nullType)
      let op: ComparisonOperator = negated ? .notEqual : .equal
      return materialize(
        .binary(MIRBinaryOperation(left: subjectOperand, operatorKind: .comparison(op), right: nullOperand, type: .bool)),
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
    case .floatLiteral(let value):
      // The literal takes the subject's width: `1.1` against `Float32` is the
      // `Float32` nearest 1.1, the same value `y == 1.1` compares against.
      guard matchedType == .float32 || matchedType == .float64 else { return nil }
      let subjectOperand = materialize(matchedValue, type: matchedType)
      let expected = MIROperand.constant(.float(value, matchedType))
      let floatOp: ComparisonOperator = negated ? .notEqual : .equal
      return materialize(
        .binary(MIRBinaryOperation(left: subjectOperand, operatorKind: .comparison(floatOp), right: expected, type: .bool)),
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
            argumentOwnerships: [.copy, .move],
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
      // A rune subject compares through its `value` field, the way a rune
      // equality pattern matches; the value is already a code point.
      let comparisonSubject: MIROperand
      let comparisonType: Type
      if let matchedPlace,
         let runeValue = runePatternValueAccess(subjectPlace: matchedPlace, subjectType: matchedType) {
        comparisonSubject = materialize(.placeRead(runeValue.place, ownership: .borrow), type: runeValue.type)
        comparisonType = runeValue.type
      } else {
        guard matchedType.isIntegerType || matchedType == .float32 || matchedType == .float64 else { return nil }
        comparisonSubject = materialize(matchedValue, type: matchedType)
        comparisonType = matchedType
      }
      let expected: MIROperand =
        (comparisonType == .float32 || comparisonType == .float64)
        ? .constant(.float(value, comparisonType))
        : .constant(.integer(value, comparisonType))
      return materialize(
        .binary(MIRBinaryOperation(left: comparisonSubject, operatorKind: .comparison(comparisonOperator(for: patternOperator, negated: negated)), right: expected, type: .bool)),
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
    case .listPattern(let elements, let ops):
      return lowerListPatternCondition(
        subjectPlace: matchedPlace,
        ops: ops,
        elements: elements,
        negated: negated
      )
    case .restPattern:
      // A rest slot never reaches the lowerer on its own: the enclosing element
      // list expands or forwards it. Standing alone it constrains nothing.
      return .constant(.boolean(!negated))
    }
  }

  private func lowerTraitObjectTypePatternCondition(
    subjectValue: MIRValue,
    subjectType: Type,
    targetType: Type,
    negated: Bool
  ) -> MIROperand? {
    guard let info = traitObjectPatternInfo(subjectType: subjectType, targetType: targetType) else {
      return nil
    }
    let condition = materialize(
      .intrinsic(
        .traitObjectMatches(
          value: subjectValue,
          traitName: info.traitName,
          traitDefId: info.traitDefId,
          traitTypeArguments: info.traitTypeArguments,
          concreteType: info.concreteType
        )
      ),
      type: .bool
    )
    if negated {
      return materialize(
        .unary(MIRUnaryOperation(operatorKind: .logicalNot, operand: condition, type: .bool)),
        type: .bool
      )
    }
    return condition
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
    let resolvedSubjectType = resolveConcretePatternNominalType(subjectType)
    guard let cases = resolvedPatternEnumCases(for: resolvedSubjectType),
          cases.indices.contains(tagIndex) else {
      return nil
    }

    let caseDef = cases[tagIndex]
    guard caseDef.parameters.count == elements.count else {
      return nil
    }

    let tagOperand = materialize(.enumTag(MIREnumTag(subject: subjectValue, enumType: resolvedSubjectType)), type: .int)
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
    let resolvedSubjectType = resolveConcretePatternNominalType(subjectType)
    guard let members = resolvedPatternStructMembers(for: resolvedSubjectType),
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

  /// The position a pattern slot reads in the subject list.
  ///
  /// Slots before the rest count forward from the front and are compile-time
  /// constants. Slots after it count back from the end, so their position is
  /// `count - k` -- only the last slot is at a fixed distance from the end.
  private func listSlotIndexOperand(
    slotIndex: Int,
    elements: [TypedPattern],
    countValue: MIROperand
  ) -> MIROperand {
    if let restIndex = elements.firstIndex(where: { $0.isRestSlot }), slotIndex > restIndex {
      let fromEnd = elements.count - slotIndex
      return materialize(
        .binary(MIRBinaryOperation(
          left: countValue,
          operatorKind: .arithmetic(.minus, checked: false),
          right: .constant(.integer(String(fromEnd), .uint)),
          type: .uint
        )),
        type: .uint
      )
    }
    return .constant(.integer(String(slotIndex), .uint))
  }

  /// The subject handle as a call receiver.
  ///
  /// A `type mutable` handle is refcounted, so the receiver is handed over as a
  /// counted COPY exactly as an ordinary `xs.count()` call does. Passing the
  /// raw handle would let the callee's drop free the list out from under the
  /// pattern.
  private func listSubjectArgument(_ place: MIRPlace) -> MIRValue {
    .placeRead(place, ownership: .copy)
  }

  /// `xs.count()`, the subject's length.
  private func listCountValue(subjectPlace: MIRPlace, ops: ListPatternOps) -> MIROperand {
    materialize(
      .call(MIRCall(
        callee: .function(ops.countSymbol),
        arguments: [listSubjectArgument(subjectPlace)],
        argumentOwnerships: [.copy],
        type: .uint
      )),
      type: .uint
    )
  }

  /// Read one element out of the subject list into a fresh local.
  ///
  /// A list element sits behind a computed index, so there is no stable place
  /// to alias; it is copied out first and everything below destructures that
  /// value. The observable semantics is `let x = xs[i]`.
  private func materializeListSlot(
    subjectPlace: MIRPlace,
    ops: ListPatternOps,
    slotIndex: Int,
    elements: [TypedPattern],
    countValue: MIROperand
  ) -> MIRPlace {
    let indexValue = listSlotIndexOperand(slotIndex: slotIndex, elements: elements, countValue: countValue)
    let elementValue = materialize(
      .call(MIRCall(
        callee: .function(ops.indexSymbol),
        arguments: [
          listSubjectArgument(subjectPlace),
          .operand(indexValue)
        ],
        argumentOwnerships: [.copy, .move],
        type: ops.elementType
      )),
      type: ops.elementType
    )
    let local = makeTemporary(type: ops.elementType, nameHint: "list_elem")
    append(.declare(local.id))
    append(.assign(.local(local.id), .operand(elementValue)))
    return .local(local.id)
  }

  /// Compile a list pattern to a Bool: the length test first, then the slot
  /// tests. The length test forks so a slot is never read out of bounds.
  private func lowerListPatternCondition(
    subjectPlace: MIRPlace?,
    ops: ListPatternOps,
    elements: [TypedPattern],
    negated: Bool
  ) -> MIROperand? {
    guard let subjectPlace else { return nil }

    let restIndex = elements.firstIndex(where: { $0.isRestSlot })
    let fixedSlotIndices = elements.indices.filter { index in
      if case .restPattern = elements[index] { return false }
      return true
    }
    // Without a rest the length must match exactly; with one the written slots
    // are a lower bound.
    let bound = fixedSlotIndices.count
    let lengthOperator: ComparisonOperator = restIndex == nil ? .equal : .greaterEqual

    let countValue = listCountValue(subjectPlace: subjectPlace, ops: ops)
    let lengthCondition = materialize(
      .binary(MIRBinaryOperation(
        left: countValue,
        operatorKind: .comparison(lengthOperator),
        right: .constant(.integer(String(bound), .uint)),
        type: .bool
      )),
      type: .bool
    )

    // Nothing left to test once the length is right: `[...]`, `[_, _]`.
    let needsSlotTests = elements.contains { !$0.isConditionlessPayloadPattern }
    if !needsSlotTests {
      if negated {
        return materialize(
          .unary(MIRUnaryOperation(operatorKind: .logicalNot, operand: lengthCondition, type: .bool)),
          type: .bool
        )
      }
      return lengthCondition
    }

    let resultLocal = makeTemporary(type: .bool, nameHint: "pattern_match")
    append(.declare(resultLocal.id))

    let branchBlock = currentBlockID
    let slotsBlock = makeBlock()
    let failedBlock = makeBlock()
    let joinBlock = makeBlock()

    setCurrentBlock(branchBlock)
    terminate(.branch(condition: lengthCondition, thenBlock: slotsBlock, elseBlock: failedBlock))

    setCurrentBlock(slotsBlock)
    var slotsResult = MIROperand.constant(.boolean(true))
    for slotIndex in fixedSlotIndices {
      let element = elements[slotIndex]
      let elementPlace = materializeListSlot(
        subjectPlace: subjectPlace,
        ops: ops,
        slotIndex: slotIndex,
        elements: elements,
        countValue: countValue
      )
      guard let slotCondition = lowerSimplePatternCondition(
        subjectValue: .placeRead(elementPlace, ownership: .borrow),
        subjectPlace: elementPlace,
        subjectType: ops.elementType,
        pattern: element,
        negated: false
      ) else {
        return nil
      }
      slotsResult = materialize(
        .binary(MIRBinaryOperation(left: slotsResult, operatorKind: .logicalAnd, right: slotCondition, type: .bool)),
        type: .bool
      )
    }
    if negated {
      slotsResult = materialize(
        .unary(MIRUnaryOperation(operatorKind: .logicalNot, operand: slotsResult, type: .bool)),
        type: .bool
      )
    }
    if !currentBlockIsTerminated {
      append(.assign(.local(resultLocal.id), .operand(slotsResult)))
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(failedBlock)
    append(.assign(.local(resultLocal.id), .operand(.constant(.boolean(negated)))))
    terminate(.goto(joinBlock))

    setCurrentBlock(joinBlock)
    return .local(resultLocal.id)
  }

  private func patternMatchPlace(place: MIRPlace, type: Type, pattern: TypedPattern) -> (place: MIRPlace, type: Type) {
    guard let info = type.indirectionCompatibilityInfo else {
      return (place, type)
    }
    // A raw pointer peels exactly when the type checker auto-dereffed the
    // subject for this pattern; a `null` or trait-object test keeps it.
    if info.family == .rawPointer, typedPatternRequiresRawSubject(pattern) {
      return (place, type)
    }
    return (.deref(base: .placeRead(place, ownership: .borrow), pointee: info.inner), info.inner)
  }

  /// The patterns whose test reads the RAW subject: a `null` pattern compares
  /// the pointer itself and a trait-object pattern matches the wrapper. The
  /// type checker keeps the subject un-dereferenced for these and derefs one
  /// level for every other pattern, so MIR must see the same subject the
  /// pattern was checked against (Sema's `untypedPatternRequiresRawSubject`).
  private func typedPatternRequiresRawSubject(_ pattern: TypedPattern) -> Bool {
    switch pattern {
    case .nullLiteral, .traitObjectType, .traitObjectTypeBinding:
      return true
    case .enumCase(_, _, let elements),
         .structPattern(_, let elements):
      return elements.contains { typedPatternRequiresRawSubject($0) }
    case .listPattern(let elements, _):
      return elements.contains { typedPatternRequiresRawSubject($0) }
    case .andPattern(let left, let right),
         .orPattern(let left, let right):
      return typedPatternRequiresRawSubject(left) || typedPatternRequiresRawSubject(right)
    case .notPattern(let inner):
      return typedPatternRequiresRawSubject(inner)
    default:
      return false
    }
  }

  private func resolveWrappedPatternType(
    inner: TypeNode,
    substitution: [String: Type],
    wrap: (Type) -> Type
  ) -> Type? {
    if let traitInner = resolvePatternTraitObjectType(inner, substitution: substitution) {
      return wrap(traitInner)
    }
    guard let resolved = resolvePatternTypeNode(inner, substitution: substitution) else {
      return nil
    }
    return wrap(resolved)
  }

  private func resolveConcretePatternNominalType(_ type: Type) -> Type {
    switch type {
    case .genericStruct, .genericEnum:
      let targetName = context.getDebugName(type)
      for node in program.globalNodes {
        switch node {
        case .globalStructDeclaration(let identifier, _),
             .foreignStruct(let identifier, _),
             .globalEnumDeclaration(let identifier, _):
          if context.getDebugName(identifier.type) == targetName {
            return identifier.type
          }
        default:
          continue
        }
      }
      return type
    default:
      return type
    }
  }

  private func resolvePatternTypeNode(_ node: TypeNode, substitution: [String: Type]) -> Type? {
    switch node {
    case .identifier(let name, _):
      if let substituted = substitution[name] {
        return substituted
      }
      if let builtinType = SemaUtils.resolveBuiltinType(name) {
        return builtinType
      }
      for global in program.globalNodes {
        switch global {
        case .globalStructDeclaration(let identifier, _), .foreignStruct(let identifier, _):
          let symbolNames = [context.getName(identifier.defId), context.getQualifiedName(identifier.defId)].compactMap { $0 }
          guard symbolNames.contains(where: { $0 == name || $0.components(separatedBy: ".").last == name }),
                case .structure(let defId) = identifier.type else { continue }
          return .structure(defId: defId)
        case .globalEnumDeclaration(let identifier, _):
          let symbolNames = [context.getName(identifier.defId), context.getQualifiedName(identifier.defId)].compactMap { $0 }
          guard symbolNames.contains(where: { $0 == name || $0.components(separatedBy: ".").last == name }),
                case .`enum`(let defId) = identifier.type else { continue }
          return .`enum`(defId: defId)
        default:
          continue
        }
      }
      if let defId = context.lookupDefId(modulePath: [], name: name, sourceFile: nil),
         let kind = context.getKind(defId) {
        switch kind {
        case .type(.structure):
          return .structure(defId: defId)
        case .type(.`enum`):
          return .`enum`(defId: defId)
        default:
          break
        }
      }
      return nil
    case .reference(let inner, let mutable, _):
      return resolveWrappedPatternType(inner: inner, substitution: substitution) {
        mutable ? .mutableReference(inner: $0) : .reference(inner: $0)
      }
    case .weakReference(let inner, let mutable, _):
      return resolveWrappedPatternType(inner: inner, substitution: substitution) {
        mutable ? .mutableWeakReference(inner: $0) : .weakReference(inner: $0)
      }
    case .pointer(let inner, let mutable, _):
      guard let resolved = resolvePatternTypeNode(inner, substitution: substitution) else {
        return nil
      }
      return mutable ? .mutablePointer(element: resolved) : .pointer(element: resolved)
    case .generic(let base, let args, _):
      let resolvedArgs = args.compactMap { resolvePatternTypeNode($0, substitution: substitution) }
      guard resolvedArgs.count == args.count else { return nil }
      for global in program.globalNodes {
        switch global {
        case .globalStructDeclaration(let identifier, _), .foreignStruct(let identifier, _):
          let symbolNames = [context.getName(identifier.defId), context.getQualifiedName(identifier.defId)].compactMap { $0 }
          if symbolNames.contains(where: { $0 == base || $0.components(separatedBy: ".").last == base }) {
            return .genericStruct(templateDefId: context.templateDeclaration(of: identifier.defId), args: resolvedArgs)
          }
        case .globalEnumDeclaration(let identifier, _):
          let symbolNames = [context.getName(identifier.defId), context.getQualifiedName(identifier.defId)].compactMap { $0 }
          if symbolNames.contains(where: { $0 == base || $0.components(separatedBy: ".").last == base }) {
            return .genericEnum(templateDefId: context.templateDeclaration(of: identifier.defId), args: resolvedArgs)
          }
        default:
          continue
        }
      }
      if let defId = context.lookupDefId(modulePath: [], name: base, sourceFile: nil),
         let kind = context.getKind(defId) {
        switch kind {
        case .type(.structure), .genericTemplate(.structure):
          return .genericStruct(templateDefId: context.templateDeclaration(of: defId), args: resolvedArgs)
        case .type(.`enum`), .genericTemplate(.`enum`):
          return .genericEnum(templateDefId: context.templateDeclaration(of: defId), args: resolvedArgs)
        default:
          break
        }
      }
      return nil
    case .functionType(let paramTypes, let returnType, _):
      let resolvedParams = paramTypes.compactMap { resolvePatternTypeNode($0, substitution: substitution) }
      guard resolvedParams.count == paramTypes.count,
            let resolvedReturn = resolvePatternTypeNode(returnType, substitution: substitution) else {
        return nil
      }
      let params = resolvedParams.map { Parameter(type: $0, kind: .byVal) }
      return .function(parameters: params, returns: resolvedReturn)
    case .inferredSelf:
      return substitution["Self"]
    }
  }

  private func resolvePatternTraitObjectType(
    _ node: TypeNode,
    substitution: [String: Type]
  ) -> Type? {
    switch node {
    case .identifier(let name, _):
      guard SemaUtils.resolveBuiltinType(name) == nil else { return nil }
      guard resolvePatternTypeNode(node, substitution: substitution) == nil else { return nil }
      return .traitObject(traitDefId: program.traits[name]?.defId ?? .invalid, typeArgs: [])
    case .generic(let base, let args, _):
      let resolvedArgs = args.compactMap { resolvePatternTypeNode($0, substitution: substitution) }
      guard resolvedArgs.count == args.count else { return nil }
      return .traitObject(traitDefId: program.traits[base]?.defId ?? .invalid, typeArgs: resolvedArgs)
    default:
      return nil
    }
  }

  private func resolvedPatternStructMembers(
    for type: Type
  ) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)]? {
    let resolvedType = resolveConcretePatternNominalType(type)
    switch resolvedType {
    case .structure(let defId):
      if let members = context.getStructMembers(defId) {
        return members
      }
      if let members = instantiatedStructMembers(for: defId) {
        return members
      }
      for node in program.globalNodes {
        switch node {
        case .globalStructDeclaration(let identifier, let parameters)
          where patternProgramTypeMatches(identifier.type, resolvedType):
          return parameters.map { parameter in
            (
              name: context.getName(parameter.defId) ?? "",
              type: parameter.type,
              mutable: parameter.isMutable(),
              access: .public,
              named: true,
            defaultValue: nil
            )
          }
        case .foreignStruct(let identifier, let fields)
          where patternProgramTypeMatches(identifier.type, resolvedType):
          return fields.map { field in
            (
              name: field.name,
              type: field.type,
              mutable: false,
              access: .public,
              named: true,
            defaultValue: nil
            )
          }
        default:
          continue
        }
      }
      return nil
    case .genericStruct(let tplDefId, let args):
      if let members = programStructMembers(matching: resolvedType) {
        return members
      }
      // The type carries the template's DECLARATION; there is no name lookup.
      guard tplDefId.isValid,
            let info = context.defIdMap.getGenericStructTemplateInfo(tplDefId) else {
        return nil
      }
      var substitution: [String: Type] = [:]
      for (index, param) in info.typeParameters.enumerated() where index < args.count {
        substitution[param.name] = args[index]
      }
      var resolvedMembers: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)] = []
      resolvedMembers.reserveCapacity(info.parameters.count)
      for member in info.parameters {
        guard let resolvedType = resolvePatternTypeNode(member.type, substitution: substitution) else {
          return nil
        }
        resolvedMembers.append((name: member.name, type: resolvedType, mutable: member.mutable, access: member.access, named: member.named, defaultValue: member.defaultValue))
      }
      return resolvedMembers
    default:
      return nil
    }
  }

  private func resolvedPatternEnumCases(for type: Type) -> [EnumCase]? {
    let resolvedType = resolveConcretePatternNominalType(type)
    switch resolvedType {
    case .`enum`(let defId):
      if let cases = context.getEnumCases(defId) {
        return cases
      }
      if let cases = instantiatedEnumCases(for: defId) {
        return cases
      }
      for node in program.globalNodes {
        guard case .globalEnumDeclaration(let identifier, let cases) = node,
              patternProgramTypeMatches(identifier.type, resolvedType) else {
          continue
        }
        return cases
      }
      return nil
    case .genericEnum(let tplDefId, let args):
      if let cases = programEnumCases(matching: resolvedType) {
        return cases
      }
      guard tplDefId.isValid,
            let info = context.defIdMap.getGenericEnumTemplateInfo(tplDefId) else {
        return nil
      }
      var substitution: [String: Type] = [:]
      for (index, param) in info.typeParameters.enumerated() where index < args.count {
        substitution[param.name] = args[index]
      }
      var resolvedCases: [EnumCase] = []
      resolvedCases.reserveCapacity(info.cases.count)
      for caseDecl in info.cases {
        var resolvedParams: [(name: String, type: Type, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)] = []
        resolvedParams.reserveCapacity(caseDecl.parameters.count)
        for parameter in caseDecl.parameters {
          guard let resolvedType = resolvePatternTypeNode(parameter.type, substitution: substitution) else {
            return nil
          }
          resolvedParams.append((name: parameter.name, type: resolvedType, access: AccessModifier.public, named: parameter.named, defaultValue: parameter.defaultValue))
        }
        resolvedCases.append(EnumCase(name: caseDecl.name, parameters: resolvedParams))
      }
      return resolvedCases
    default:
      return nil
    }
  }

  private func patternProgramTypeMatches(_ lhs: Type, _ rhs: Type) -> Bool {
    lhs == rhs || context.getDebugName(lhs) == context.getDebugName(rhs)
  }

  private func programStructMembers(
    matching type: Type
  ) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)]? {
    for node in program.globalNodes {
      switch node {
      case .globalStructDeclaration(let identifier, let parameters)
        where patternProgramTypeMatches(identifier.type, type):
        return parameters.map { parameter in
          (
            name: context.getName(parameter.defId) ?? "",
            type: parameter.type,
            mutable: parameter.isMutable(),
            access: .public,
            named: true,
          defaultValue: nil
          )
        }
      case .foreignStruct(let identifier, let fields)
        where patternProgramTypeMatches(identifier.type, type):
        return fields.map { field in
          (
            name: field.name,
            type: field.type,
            mutable: false,
            access: .public,
            named: true,
          defaultValue: nil
          )
        }
      default:
        continue
      }
    }
    return nil
  }

  private func programEnumCases(matching type: Type) -> [EnumCase]? {
    for node in program.globalNodes {
      guard case .globalEnumDeclaration(let identifier, let cases) = node,
            patternProgramTypeMatches(identifier.type, type) else {
        continue
      }
      return cases
    }
    return nil
  }

  private func instantiatedStructMembers(
    for defId: DefId
  ) -> [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)]? {
    guard let templateName = context.getTemplateName(defId),
          let args = context.getTypeArguments(defId) else {
      return nil
    }
    // Prefer the instance's own link to its template; re-deriving it from the
    // template's spelling picks whichever module registered last.
    // The instance's own link to its template. `templateName` is display only.
    let templateDefId = context.templateDeclaration(of: defId)
    guard templateDefId.isValid,
          let info = context.defIdMap.getGenericStructTemplateInfo(templateDefId) else {
      return nil
    }
    var substitution: [String: Type] = [:]
    for (index, param) in info.typeParameters.enumerated() where index < args.count {
      substitution[param.name] = args[index]
    }
    var resolvedMembers: [(name: String, type: Type, mutable: Bool, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)] = []
    resolvedMembers.reserveCapacity(info.parameters.count)
    for member in info.parameters {
      guard let resolvedType = resolvePatternTypeNode(member.type, substitution: substitution) else {
        return nil
      }
      resolvedMembers.append((name: member.name, type: resolvedType, mutable: member.mutable, access: member.access, named: member.named, defaultValue: member.defaultValue))
    }
    return resolvedMembers
  }

  private func instantiatedEnumCases(for defId: DefId) -> [EnumCase]? {
    guard let templateName = context.getTemplateName(defId),
          let args = context.getTypeArguments(defId) else {
      return nil
    }
    let templateDefId = context.templateDeclaration(of: defId)
    guard templateDefId.isValid,
          let info = context.defIdMap.getGenericEnumTemplateInfo(templateDefId) else {
      return nil
    }
    var substitution: [String: Type] = [:]
    for (index, param) in info.typeParameters.enumerated() where index < args.count {
      substitution[param.name] = args[index]
    }
    var resolvedCases: [EnumCase] = []
    resolvedCases.reserveCapacity(info.cases.count)
    for caseDecl in info.cases {
      var resolvedParams: [(name: String, type: Type, access: AccessModifier, named: Bool, defaultValue: ExpressionNode?)] = []
      resolvedParams.reserveCapacity(caseDecl.parameters.count)
      for parameter in caseDecl.parameters {
        guard let resolvedType = resolvePatternTypeNode(parameter.type, substitution: substitution) else {
          return nil
        }
        resolvedParams.append((name: parameter.name, type: resolvedType, access: .public, named: parameter.named, defaultValue: parameter.defaultValue))
      }
      resolvedCases.append(EnumCase(name: caseDecl.name, parameters: resolvedParams))
    }
    return resolvedCases
  }

  private func patternMatchSubject(value: MIRValue, type: Type, pattern: TypedPattern) -> (value: MIRValue, type: Type) {
    switch type {
    case .reference(let inner),
         .mutableReference(let inner),
         .borrowedReference(let inner),
         .mutableBorrowedReference(let inner),
         .weakReference(let inner),
         .mutableWeakReference(let inner):
      return (.placeRead(.deref(base: value, pointee: inner), ownership: .borrow), inner)
    case .pointer(let inner), .mutablePointer(let inner):
      // One pointer indirection, exactly when the type checker auto-dereffed
      // the subject for this pattern (a `null` test keeps the raw subject).
      guard !typedPatternRequiresRawSubject(pattern) else {
        return (value, type)
      }
      return (.placeRead(.deref(base: value, pointee: inner), ownership: .borrow), inner)
    default:
      return (value, type)
    }
  }

  private func patternMatchType(_ type: Type, pattern: TypedPattern) -> Type {
    switch type {
    case .reference(let inner),
         .mutableReference(let inner),
         .borrowedReference(let inner),
         .mutableBorrowedReference(let inner),
         .weakReference(let inner),
         .mutableWeakReference(let inner):
      return resolveConcretePatternNominalType(inner)
    case .pointer(let inner), .mutablePointer(let inner):
      guard !typedPatternRequiresRawSubject(pattern) else {
        return resolveConcretePatternNominalType(type)
      }
      return resolveConcretePatternNominalType(inner)
    default:
      return resolveConcretePatternNominalType(type)
    }
  }

  private func canLowerSimplePattern(_ pattern: TypedPattern, subjectType: Type) -> Bool {
    let matchedType = patternMatchType(subjectType, pattern: pattern)
    switch pattern {
    case .wildcard:
      return true
    case .traitObjectType(let targetType):
      return traitObjectPatternInfo(subjectType: matchedType, targetType: targetType) != nil
    case .booleanLiteral:
      return matchedType == .bool
    case .nullLiteral(let resultType):
      switch matchedType {
      case .pointer, .mutablePointer:
        return true
      default:
        switch resultType {
        case .pointer, .mutablePointer:
          return true
        default:
          return false
        }
      }
    case .stringLiteral:
      return isStringPatternType(matchedType)
    case .integerLiteral:
      return matchedType.isIntegerType || isRunePatternType(matchedType)
    case .floatLiteral:
      return matchedType == .float32 || matchedType == .float64
    case .comparisonPattern:
      return matchedType.isIntegerType || isRunePatternType(matchedType)
        || matchedType == .float32 || matchedType == .float64
    case .enumCase(_, let tagIndex, let elements):
      guard let cases = resolvedPatternEnumCases(for: matchedType),
            cases.indices.contains(tagIndex) else { return false }
      let caseDef = cases[tagIndex]
      return caseDef.parameters.count == elements.count
        && zip(elements, caseDef.parameters).allSatisfy { canLowerSimplePattern($0.0, subjectType: $0.1.type) }
    case .structPattern(_, let elements):
      guard let members = resolvedPatternStructMembers(for: matchedType),
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
    case .traitObjectTypeBinding:
      return false
    case .listPattern(let elements, let ops):
      return elements.allSatisfy { element in
        if element.isRestSlot { return true }
        return canLowerSimplePattern(element, subjectType: ops.elementType)
      }
    case .restPattern:
      return true
    default:
      return false
    }
  }

  private func canLowerPatternWithBindings(_ pattern: TypedPattern, subjectType: Type) -> Bool {
    if canLowerSimplePattern(pattern, subjectType: subjectType) {
      return true
    }

    let matchedType = patternMatchType(subjectType, pattern: pattern)
    guard !context.containsGenericParameter(matchedType) else { return false }
    switch pattern {
    case .variable, .weakBinding:
      return true
    case .traitObjectTypeBinding(_, let targetType):
      return traitObjectPatternInfo(subjectType: matchedType, targetType: targetType) != nil
    case .enumCase(_, let tagIndex, let elements):
      guard let cases = resolvedPatternEnumCases(for: matchedType),
            cases.indices.contains(tagIndex) else {
        return false
      }
      let caseDef = cases[tagIndex]
      return caseDef.parameters.count == elements.count
        && zip(elements, caseDef.parameters).allSatisfy { canLowerPatternWithBindings($0.0, subjectType: $0.1.type) }
    case .structPattern(_, let elements):
      guard let members = resolvedPatternStructMembers(for: matchedType),
            members.count == elements.count else {
        return false
      }
      return zip(elements, members).allSatisfy { canLowerPatternWithBindings($0.0, subjectType: $0.1.type) }
    case .andPattern(let left, let right),
         .orPattern(let left, let right):
      return canLowerPatternWithBindings(left, subjectType: matchedType)
        && canLowerPatternWithBindings(right, subjectType: matchedType)
    case .listPattern(let elements, let ops):
      guard !context.containsGenericParameter(ops.elementType) else { return false }
      return elements.allSatisfy { element in
        if element.isRestSlot { return true }
        return canLowerPatternWithBindings(element, subjectType: ops.elementType)
      }
    case .restPattern:
      return true
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
    let matchedSubject = patternMatchPlace(place: subjectPlace, type: subjectType, pattern: pattern)
    let matchedPlace = matchedSubject.place
    let matchedType = resolveConcretePatternNominalType(matchedSubject.type)

    switch pattern {
    case .weakBinding(let symbol):
      if symbol.type != .void {
        // If the subject is already `Option[T]` (the `when` desugaring wrapped
        // it), extract the Some payload directly. Otherwise upgrade first.
        let payloadBase: MIRPlace
        switch subjectType {
        case .weakReference, .mutableWeakReference:
          let innerType = symbol.type
          let optionType = Type.genericEnum(
            templateDefId: context.defIdMap.lookupGenericEnumTemplateDefId("Option") ?? .invalid,
            args: [innerType])
          let upgradeLocal = makeTemporary(type: optionType, nameHint: "weak_bind_up")
          append(.declare(upgradeLocal.id))
          append(.assign(.local(upgradeLocal.id), .intrinsic(.upgradeRef(
            value: .placeRead(subjectPlace, ownership: .borrow),
            resultType: optionType))))
          payloadBase = .local(upgradeLocal.id)
        default:
          payloadBase = subjectPlace
        }
        let payloadPlace = MIRPlace.enumPayload(
          base: payloadBase,
          caseName: "Some",
          fieldName: "value",
          fieldIndex: 0,
          fieldType: symbol.type)
        let bindLocal = makeTemporary(type: symbol.type, nameHint: "weak_bind")
        append(.declare(bindLocal.id))
        append(.assign(.local(bindLocal.id), .placeRead(payloadPlace, ownership: .copy)))
        patternPlaceByDefId[symbol.defId.id] = .local(bindLocal.id)
      }
    case .variable(let symbol):
      if symbol.type != .void {
        if symbol.type == subjectType {
          patternPlaceByDefId[symbol.defId.id] = subjectPlace
        } else {
          patternPlaceByDefId[symbol.defId.id] = matchedPlace
        }
      }
    case .traitObjectTypeBinding(let symbol, let targetType):
      assignTraitObjectPatternBinding(symbol: symbol, targetType: targetType, sourcePlace: matchedPlace)
    case .enumCase(let caseName, let tagIndex, let elements):
      guard let cases = resolvedPatternEnumCases(for: matchedType),
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
        // If the payload is accessed through a deref (e.g., when self.current in
        // { .Some(c) then ... }), the binding would alias into the deref target.
        // If the body later modifies the deref target (self.current = ...), the
        // binding would read stale data. Materialize the payload into a local.
        let resolvedPlace: MIRPlace
        if goesThroughDeref(matchedPlace) && parameter.type != .void {
          let local = makeTemporary(type: parameter.type, nameHint: sanitizeCIdentifier(parameter.name.isEmpty ? "payload" : parameter.name))
          append(.declare(local.id))
          append(.assign(.local(local.id), .placeRead(payloadPlace, ownership: .copy)))
          resolvedPlace = .local(local.id)
        } else {
          resolvedPlace = payloadPlace
        }
        bindPatternVariables(pattern: element, subjectPlace: resolvedPlace, subjectType: parameter.type)
      }
    case .structPattern(_, let elements):
      guard let members = resolvedPatternStructMembers(for: matchedType),
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
    case .listPattern(let elements, let ops):
      let countValue = listCountValue(subjectPlace: matchedPlace, ops: ops)
      for (slotIndex, element) in elements.enumerated() {
        if case .restPattern = element { continue }
        let elementPlace = materializeListSlot(
          subjectPlace: matchedPlace,
          ops: ops,
          slotIndex: slotIndex,
          elements: elements,
          countValue: countValue
        )
        bindPatternVariables(pattern: element, subjectPlace: elementPlace, subjectType: ops.elementType)
      }
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
    let matchedSubject = patternMatchPlace(place: subjectPlace, type: subjectType, pattern: pattern)
    let matchedPlace = matchedSubject.place
    let matchedType = matchedSubject.type

    switch pattern {
    case .weakBinding(let symbol):
      guard symbol.type != .void,
            let destination = patternPlaceByDefId[symbol.defId.id] else {
        return
      }
      // The subject is the upgrade result (`Option[T]`). Extract the Some payload.
      let payloadPlace = MIRPlace.enumPayload(
        base: matchedPlace,
        caseName: "Some",
        fieldName: "value",
        fieldIndex: 0,
        fieldType: symbol.type
      )
      append(.assign(destination, .placeRead(payloadPlace, ownership: .copy)))
    case .variable(let symbol):
      guard symbol.type != .void,
            let destination = patternPlaceByDefId[symbol.defId.id] else {
        return
      }
      let sourcePlace = symbol.type == subjectType ? subjectPlace : matchedPlace
      append(.assign(destination, .placeRead(sourcePlace, ownership: .copy)))
    case .traitObjectTypeBinding(let symbol, let targetType):
      guard let destination = patternPlaceByDefId[symbol.defId.id] else {
        return
      }
      append(.assign(
        destination,
        .intrinsic(.traitObjectDowncast(value: .placeRead(matchedPlace, ownership: .borrow), resultType: targetType))
      ))
    case .enumCase(let caseName, let tagIndex, let elements):
      guard let cases = resolvedPatternEnumCases(for: matchedType),
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
      guard let members = resolvedPatternStructMembers(for: matchedType),
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
    case .listPattern(let elements, let ops):
      let countValue = listCountValue(subjectPlace: matchedPlace, ops: ops)
      for (slotIndex, element) in elements.enumerated() {
        if case .restPattern = element { continue }
        let elementPlace = materializeListSlot(
          subjectPlace: matchedPlace,
          ops: ops,
          slotIndex: slotIndex,
          elements: elements,
          countValue: countValue
        )
        assignPatternBindingLocals(pattern: element, subjectPlace: elementPlace, subjectType: ops.elementType)
      }
    case .wildcard, .booleanLiteral, .integerLiteral, .floatLiteral, .stringLiteral, .comparisonPattern, .notPattern, .traitObjectType, .restPattern, .nullLiteral:
      break
    }
  }

  private func assignTraitObjectPatternBinding(symbol: Symbol, targetType: Type, sourcePlace: MIRPlace) {
    let destination: MIRPlace
    if let existing = patternPlaceByDefId[symbol.defId.id] {
      destination = existing
    } else {
      let local = makeTemporary(type: targetType, nameHint: context.getName(symbol.defId) ?? "trait_object_binding")
      append(.declare(local.id))
      destination = .local(local.id)
      patternPlaceByDefId[symbol.defId.id] = destination
    }

    append(.assign(
      destination,
      .intrinsic(.traitObjectDowncast(value: .placeRead(sourcePlace, ownership: .borrow), resultType: targetType))
    ))
  }

  private func traitObjectPatternInfo(
    subjectType: Type,
    targetType: Type
  ) -> (traitName: String, traitDefId: DefId, traitTypeArguments: [Type], concreteType: Type)? {
    guard case .traitObject(let traitDefId, let traitTypeArguments) = subjectType else {
      return nil
    }

    switch targetType {
    case .reference(let concreteType), .mutableReference(let concreteType):
      return (Type.spelling(traitDefId), traitDefId, traitTypeArguments, concreteType)
    // New syntax: bare concrete type (no * prefix)
    case .structure, .enum, .genericStruct, .genericEnum:
      return (Type.spelling(traitDefId), traitDefId, traitTypeArguments, targetType)
    default:
      return nil
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
    // The subject's declaration identity decides, never its spelling: a user
    // type is not a string pattern however it is named.
    return context.isStdNominalType(type, context.stdStringDefId)
  }

  private func isRunePatternType(_ type: Type) -> Bool {
    return context.isStdNominalType(type, context.stdRuneDefId)
  }

  private func runePatternValueAccess(subjectPlace: MIRPlace, subjectType: Type) -> (place: MIRPlace, type: Type)? {
    guard case .structure(let defId) = subjectType,
          context.isStdNominal(defId, context.stdRuneDefId),
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
    // Find `equals` as a member of the receiver TYPE. Looking the type up by
    // name instead let an unrelated declaration of the same spelling win, and
    // needed a hardcoded `"String"` fallback to work at all.
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

  /// `if w is ?name then A else B` -- the subject is already the upgrade
  /// intrinsic (`Option[T]`). Branch on Some/None, bind the Some payload.
  private func lowerWeakBindingIfExpression(
    subject: TypedExpressionNode,
    symbol: Symbol,
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    type: Type
  ) -> MIRExprResult? {
    let resultLocal: MIRLocal? = (type != .void && type != .never)
      ? makeTemporary(type: type, nameHint: "if_pattern_result")
      : nil
    if let resultLocal {
      append(.declare(resultLocal.id))
    }

    guard let preparedSubject = preparePatternSubject(subject, nameHint: "weak_up") else {
      return nil
    }
    let subjectPlace = preparedSubject.place
    let subjectScope = preparedSubject.scope

    let innerType = symbol.type
    let optionType = subject.type

    // The niche-layout `enumTag` returns 0 for None (NULL niche) and 1 for
    // Some (non-NULL niche). Alive = tag != 0.
    let tagOperand = materialize(
      .enumTag(MIREnumTag(
        subject: .placeRead(subjectPlace, ownership: .borrow),
        enumType: optionType)),
      type: .int)
    let zeroOperand = MIROperand.constant(.integer("0", .int))
    let isSomeValue = MIRValue.binary(MIRBinaryOperation(
      left: tagOperand,
      operatorKind: .comparison(.notEqual),
      right: zeroOperand,
      type: .bool))
    let isSomeLocal = materialize(isSomeValue, type: .bool)

    let branchBlock = currentBlockID
    let thenBlock = makeBlock()
    let elseBlock = makeBlock()
    let joinBlock = makeBlock()

    setCurrentBlock(branchBlock)
    terminate(.branch(
      condition: isSomeLocal,
      thenBlock: thenBlock,
      elseBlock: elseBlock))

    setCurrentBlock(thenBlock)
    let payloadPlace = MIRPlace.enumPayload(
      base: subjectPlace,
      caseName: "Some",
      fieldName: "value",
      fieldIndex: 0,
      fieldType: innerType)
    if let dest = patternPlaceByDefId[symbol.defId.id] {
      append(.assign(dest, .placeRead(payloadPlace, ownership: .copy)))
    } else {
      let bindLocal = makeTemporary(type: symbol.type, nameHint: "weak_bind")
      append(.declare(bindLocal.id))
      append(.assign(.local(bindLocal.id), .placeRead(payloadPlace, ownership: .copy)))
      patternPlaceByDefId[symbol.defId.id] = .local(bindLocal.id)
    }
    let thenResult = lowerExpression(thenBranch)
    if let resultLocal, let thenResult {
      if let thenOperand = thenResult.operand {
        append(.assign(.local(resultLocal.id), .operand(thenOperand)))
      } else if let thenPlace = thenResult.place {
        append(.assign(.local(resultLocal.id), .placeRead(thenPlace, ownership: .copy)))
      }
    }
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(elseBlock)
    if let elseBranch {
      let elseResult = lowerExpression(elseBranch)
      if let resultLocal, let elseResult {
        if let elseOperand = elseResult.operand {
          append(.assign(.local(resultLocal.id), .operand(elseOperand)))
        } else if let elsePlace = elseResult.place {
          append(.assign(.local(resultLocal.id), .placeRead(elsePlace, ownership: .copy)))
        }
      }
    }
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }

    setCurrentBlock(joinBlock)
    if let subjectScope {
      append(.scopeExit(subjectScope))
      scopeStack.removeAll { $0 == subjectScope }
    }
    if let resultLocal {
      return MIRExprResult(
        type: type, category: .rvalue,
        operand: .local(resultLocal.id), place: nil)
    }
    return MIRExprResult(type: type, category: .rvalue, operand: .constant(.void), place: nil)
  }

  private func lowerSimpleIfPatternExpression(
    subject: TypedExpressionNode,
    pattern: TypedPattern,
    thenBranch: TypedExpressionNode,
    elseBranch: TypedExpressionNode?,
    type: Type
  ) -> MIRExprResult? {
    guard !currentBlockIsTerminated else { return nil }

    // `?name` unpacks a weak handle: upgrade, branch on Some/None, bind the
    // Some payload to `name` in the then-branch.
    if case .weakBinding(let symbol) = pattern {
      return lowerWeakBindingIfExpression(
        subject: subject, symbol: symbol,
        thenBranch: thenBranch, elseBranch: elseBranch, type: type)
    }

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
    guard !context.containsGenericParameter(patternMatchType(subject.type, pattern: cases.first?.pattern ?? .wildcard)) else { return false }
    guard cases.allSatisfy({ canLowerPatternWithBindings($0.pattern, subjectType: subject.type) }) else { return false }
    return true
  }

  /// Check if a when expression can be lowered to a SwitchValue terminator.
  /// This is possible when all patterns are simple enum case patterns
  /// (with conditionless payloads) or simple integer/boolean literal patterns,
  /// with at most one wildcard/default case.
  private func canLowerToSwitchValue(subject: TypedExpressionNode, cases: [TypedMatchCase]) -> Bool {
    // Must have at least 2 cases to benefit from switch
    guard cases.count >= 2 else { return false }
    // A guarded arm needs its own conditional test, which a SwitchValue cannot
    // express -- fall back to the branch chain.
    guard cases.allSatisfy({ $0.guardExpr == nil }) else { return false }

    // Dereference reference types to get the actual subject type
    let subjectType: Type
    switch subject.type {
    case .reference(let inner), .mutableReference(let inner),
         .borrowedReference(let inner), .mutableBorrowedReference(let inner),
         .weakReference(let inner), .mutableWeakReference(let inner):
      subjectType = inner
    default:
      subjectType = subject.type
    }

    var hasDefault = false
    var enumCaseCount = 0
    var literalCount = 0

    for matchCase in cases {
      switch matchCase.pattern {
      case .wildcard, .variable:
        hasDefault = true
      case .enumCase(_, _, let elements):
        guard case .enum = subjectType else { return false }
        // Only simple enum cases (no complex payload bindings) can use switch
        guard elements.allSatisfy({ $0.isConditionlessPayloadPattern }) else { return false }
        enumCaseCount += 1
      case .integerLiteral:
        guard subjectType.isIntegerType else { return false }
        literalCount += 1
      case .booleanLiteral:
        guard subjectType == .bool else { return false }
        literalCount += 1
      default:
        return false
      }
    }

    // Must have at least 2 non-default cases
    return (enumCaseCount + literalCount) >= 2
  }

  /// Extract the switch constant for a pattern, if it can be used in a SwitchValue.
  private func switchConstantForPattern(_ pattern: TypedPattern, subjectType: Type) -> MIRConstant? {
    switch pattern {
    case .enumCase(_, let tagIndex, _):
      return .integer(String(tagIndex), .int)
    case .integerLiteral(let value):
      return .integer(value, subjectType)
    case .booleanLiteral(let value):
      return .boolean(value)
    default:
      return nil
    }
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

    setCurrentBlock(dispatchBlock)

    for (index, matchCase) in cases.enumerated() {
      let checkBlock = currentBlockID
      let caseBlock = caseBlocks[index]
      let nextBlock = nextBlocks[index]

      setCurrentBlock(checkBlock)
      // An arm whose pattern offers several readings is matched as a
      // backtracking chain (the guard re-runs per reading); an or-free
      // pattern keeps the single-test path, which binds by alias.
      let alternatives = matchCase.pattern.orAlternatives
      if alternatives.count > 1 {
        lowerWhenArmAlternativeChain(
          arm: matchCase,
          alternatives: alternatives,
          subjectPlace: subjectPlace,
          subjectType: subject.type,
          resultLocal: resultLocal,
          bodyBlock: caseBlock,
          nextBlock: nextBlock,
          joinBlock: joinBlock
        )
        setCurrentBlock(nextBlock)
        continue
      }

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
        if let guardExpr = matchCase.guardExpr {
          // Arm guard, evaluated with the pattern's bindings in scope. A false
          // guard falls through to the next arm's check. `makeBlock` moves the
          // cursor, so the branch is emitted back in the block the guard
          // computation landed in.
          let guardOperand = materialize(lowerValue(guardExpr), type: .bool)
          let guardBlock = currentBlockID
          let bodyBlock = makeBlock()
          setCurrentBlock(guardBlock)
          terminate(.branch(condition: guardOperand, thenBlock: bodyBlock, elseBlock: nextBlock))
          setCurrentBlock(bodyBlock)
        }
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

  /// One arm of a branch-chain `when` whose pattern offers several readings.
  ///
  /// The readings run in backtracking order: each is tested, its bindings fill
  /// the shared slots, and the guard is re-evaluated on THOSE bindings. The
  /// next reading is tried when the test fails OR the guard refuses -- never
  /// the left-biased "guard runs once on the first matching reading". All
  /// readings share one body block, so the arm body lowers exactly once.
  private func lowerWhenArmAlternativeChain(
    arm: TypedMatchCase,
    alternatives: [TypedPattern],
    subjectPlace: MIRPlace,
    subjectType: Type,
    resultLocal: MIRLocal?,
    bodyBlock: MIRBlockID,
    nextBlock: MIRBlockID,
    joinBlock: MIRBlockID
  ) {
    // One slot per name, filled from each reading's own layout. Claimed
    // before the first test so every path through the chain sees the same
    // places; a reading that matches overwrites the slots with its values.
    let entryBlock = currentBlockID
    let savedPatternPlaces = patternPlaceByDefId
    declarePatternBindingLocals(for: arm.pattern)

    // The arm gives up here -- every reading either failed to match or was
    // refused by the guard -- and leaves like a single-test arm whose guard
    // said false: next arm's check.
    let armFailBlock = makeBlock()
    setCurrentBlock(armFailBlock)
    terminate(.goto(nextBlock))

    var testBlock = entryBlock
    for (altIndex, alternative) in alternatives.enumerated() {
      setCurrentBlock(testBlock)
      let isLast = altIndex + 1 == alternatives.count
      let subjectRead = MIRValue.placeRead(subjectPlace, ownership: .borrow)
      let condition = lowerSimplePatternCondition(
        subjectValue: subjectRead,
        subjectPlace: subjectPlace,
        subjectType: subjectType,
        pattern: alternative,
        negated: false
      )
      let conditionEnd = currentBlockID
      // A reading that does not match hands over to the next reading's test;
      // the last one hands over to the arm's give-up block. `makeBlock` moves
      // the cursor, so come back to the condition's block before terminating.
      let failBlock = isLast ? armFailBlock : makeBlock()
      let fillBlock = makeBlock()
      setCurrentBlock(conditionEnd)
      guard let condition else {
        terminate(.goto(failBlock))
        testBlock = failBlock
        continue
      }
      terminate(.branch(condition: condition, thenBlock: fillBlock, elseBlock: failBlock))

      setCurrentBlock(fillBlock)
      assignPatternBindingLocals(pattern: alternative, subjectPlace: subjectPlace, subjectType: subjectType)
      // The guard runs on THIS reading's bindings and may refuse them: a
      // false guard tries the next reading, same as a failed match.
      if let guardExpr = arm.guardExpr {
        let guardOperand = materialize(lowerValue(guardExpr), type: .bool)
        let guardEnd = currentBlockID
        let realBodyBlock = makeBlock()
        setCurrentBlock(guardEnd)
        terminate(.branch(condition: guardOperand, thenBlock: realBodyBlock, elseBlock: failBlock))
        setCurrentBlock(realBodyBlock)
      }
      terminate(.goto(bodyBlock))
      testBlock = failBlock
    }

    setCurrentBlock(bodyBlock)
    lowerBranchBody(arm.body, resultLocal: resultLocal)
    patternPlaceByDefId = savedPatternPlaces
    if !currentBlockIsTerminated {
      terminate(.goto(joinBlock))
    }
  }

  /// Lower a when expression with simple enum/literal patterns to SwitchValue.
  /// This replaces a linear chain of branch checks with a single switch dispatch,
  /// significantly reducing the number of MIR locals and C stack frame size.
  private func lowerSwitchWhenExpression(
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

    // Extract the switch operand: enum tag for enum types, subject value for int/bool
    // Handle reference types by dereferencing (matching patternMatchSubject logic)
    let switchOperand: MIROperand
    let subjectRead = MIRValue.placeRead(subjectPlace, ownership: .borrow)
    // Every arm the switch path accepts (literal / enum-case / catchall) keeps
    // the auto-dereffed subject, so any arm's pattern gives the same peel.
    let (matchedValue, matchedType) = patternMatchSubject(
      value: subjectRead, type: subject.type, pattern: cases.first?.pattern ?? .wildcard)

    switch matchedType {
    case .enum:
      let tagValue = MIRValue.enumTag(MIREnumTag(subject: matchedValue, enumType: matchedType))
      let tagLocal = materialize(tagValue, type: .int)
      switchOperand = tagLocal
    default:
      // For int/bool, materialize the matched value
      switchOperand = materialize(matchedValue, type: matchedType)
    }

    let dispatchBlock = currentBlockID
    let joinBlock = makeBlock()

    // Build switch cases and default
    var switchCases: [MIRSwitchCase] = []
    var defaultBlock: MIRBlockID?

    for (index, matchCase) in cases.enumerated() {
      let caseBlock = makeBlock()

      switch matchCase.pattern {
      case .wildcard, .variable:
        defaultBlock = caseBlock
      default:
        if let constant = switchConstantForPattern(matchCase.pattern, subjectType: subject.type) {
          switchCases.append(MIRSwitchCase(value: constant, target: caseBlock))
        }
      }
    }

    // If no explicit default, create one that goes to join (or unreachable)
    let effectiveDefault: MIRBlockID
    if let db = defaultBlock {
      effectiveDefault = db
    } else {
      let unreachableBlock = makeBlock()
      setCurrentBlock(unreachableBlock)
      terminate(.unreachable)
      effectiveDefault = unreachableBlock
    }

    // Emit the switch terminator
    setCurrentBlock(dispatchBlock)
    terminate(.switchValue(switchOperand, cases: switchCases, defaultBlock: effectiveDefault))

    // Emit case bodies - map patterns to their switch case blocks
    for (index, matchCase) in cases.enumerated() {
      let caseBlock: MIRBlockID
      switch matchCase.pattern {
      case .wildcard, .variable:
        guard let db = defaultBlock else { continue }
        caseBlock = db
      case .enumCase(_, let tagIndex, _):
        let constant = MIRConstant.integer(String(tagIndex), .int)
        guard let sc = switchCases.first(where: {
          if case .integer(let v, _) = $0.value { return v == String(tagIndex) }
          return false
        }) else { continue }
        caseBlock = sc.target
      case .integerLiteral(let value):
        guard let sc = switchCases.first(where: {
          if case .integer(let v, _) = $0.value { return v == value }
          return false
        }) else { continue }
        caseBlock = sc.target
      case .booleanLiteral(let value):
        guard let sc = switchCases.first(where: {
          if case .boolean(let v) = $0.value { return v == value }
          return false
        }) else { continue }
        caseBlock = sc.target
      default:
        continue
      }

      setCurrentBlock(caseBlock)
      withPatternBindings(pattern: matchCase.pattern, subjectPlace: subjectPlace, subjectType: subject.type) {
        lowerBranchBody(matchCase.body, resultLocal: resultLocal)
      }
      if !currentBlockIsTerminated {
        terminate(.goto(joinBlock))
      }
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

  /// Generic-parameter names in a type, in first-appearance order.
  private func genericParameterNames(in type: Type) -> [String] {
    var seen: [String] = []
    func walk(_ t: Type) {
      switch t {
      case .genericParameter(let name):
        if !seen.contains(name) { seen.append(name) }
      case .function(let params, let returns):
        for p in params { walk(p.type) }
        walk(returns)
      case .genericStruct(_, let args), .genericEnum(_, let args), .traitObject(_, let args):
        for arg in args { walk(arg) }
      case .structure, .enum, .opaque:
        // A nominal's members are not part of the type expression; only its
        // arguments are, and those are the generic cases above.
        break
      case .reference(let inner), .mutableReference(let inner),
           .borrowedReference(let inner), .mutableBorrowedReference(let inner),
           .weakReference(let inner), .mutableWeakReference(let inner):
        walk(inner)
      case .pointer(let element), .mutablePointer(let element):
        walk(element)
      default:
        break
      }
    }
    walk(type)
    return seen
  }

  private func lowerCall(
    callee: TypedExpressionNode,
    arguments: [TypedExpressionNode],
    type: Type,
    original: TypedExpressionNode
  ) -> MIRExprResult? {
    // A method-generic call still spells the method's own parameters in its
    // function type: `fold[U](self, U, (U, T) -> U) U` says `U` even at a call
    // site that already knows `U = Int`. Substitute them before deciding the
    // callee is generic, or the call falls through to the generic bail-out.
    let resolvedCalleeType: Type = {
      guard case .methodReference(_, let method, _, let methodTypeArgs, _) = callee,
            let margs = methodTypeArgs, !margs.isEmpty
      else {
        return callee.type
      }
      // Declaration order when it is on file, first-appearance order otherwise.
      // A method's own parameters are exactly the generic parameters still left
      // in its function type -- the receiver's have already been substituted.
      let names = context.methodTypeParameterNames[method.defId]
        ?? genericParameterNames(in: callee.type)
      guard !names.isEmpty else { return callee.type }
      var substitution: [String: Type] = [:]
      for (name, arg) in zip(names, margs) where substitution[name] == nil {
        substitution[name] = arg
      }
      guard !substitution.isEmpty else { return callee.type }
      return SemaUtils.substituteType(callee.type, substitution: substitution, context: context)
    }()

    if case .methodReference(let base, let method, _, _, _) = callee,
       !context.containsGenericParameter(resolvedCalleeType),
       let callableMethod = concreteMethodSymbol(method: method, calleeType: resolvedCalleeType, resultType: type) {
      var argumentValues: [MIRValue] = [lowerMethodReceiverArgument(base, method: callableMethod)]
      argumentValues.reserveCapacity(arguments.count + 1)
      let methodType: Type
      if case .function = callableMethod.type, !context.containsGenericParameter(callableMethod.type) {
        methodType = callableMethod.type
      } else {
        methodType = preferredFunctionType(for: callableMethod)
      }
      let methodParameters: [Parameter]
      if case .function(let parameters, _) = methodType {
        methodParameters = parameters
      } else {
        methodParameters = []
      }
      for (index, argument) in arguments.enumerated() {
        let expectedType = (index + 1) < methodParameters.count ? methodParameters[index + 1].type : nil
        argumentValues.append(lowerCallArgument(argument, expectedType: expectedType))
        guard !currentBlockIsTerminated else { return nil }
      }
      guard !currentBlockIsTerminated else { return nil }
      var argumentOwnerships: [MIROwnershipUse] = [ownershipUse(for: base)]
      argumentOwnerships.reserveCapacity(arguments.count + 1)
      argumentOwnerships.append(contentsOf: arguments.map(ownershipUse(for:)))
      return finishCall(
        callee: .function(callableMethod),
        arguments: argumentValues,
        argumentOwnerships: argumentOwnerships,
        type: type
      )
    }

    if context.containsGenericParameter(callee.type)
      || arguments.contains(where: { context.containsGenericParameter($0.type) }) {
      fatalError("Unsupported generic dynamic call reached MIR lowering: callee=\(callee) calleeType=\(callee.type) argTypes=\(arguments.map { $0.type })")
    }

    let calleeOperand = lowerOperand(callee)
    guard !currentBlockIsTerminated else { return nil }
    let argumentValues = lowerCallArgumentValues(callee: calleeOperand, arguments: arguments)
    guard !currentBlockIsTerminated else { return nil }
    return finishCall(
      callee: calleeOperand,
      arguments: argumentValues,
      argumentOwnerships: arguments.map(ownershipUse(for:)),
      type: type
    )
  }

  private func lowerCallArgumentValues(callee: MIROperand, arguments: [TypedExpressionNode]) -> [MIRValue] {
    let parameterTypes = functionParameterTypes(for: callee)
    var values: [MIRValue] = []
    values.reserveCapacity(arguments.count)
    for (index, argument) in arguments.enumerated() {
      let expectedType = index < parameterTypes.count ? parameterTypes[index] : nil
      values.append(lowerCallArgument(argument, expectedType: expectedType))
      if currentBlockIsTerminated { break }
    }
    return values
  }

  private func lowerCallArgument(_ argument: TypedExpressionNode, expectedType: Type?) -> MIRValue {
    if let borrowed = lowerBorrowedReferenceArgument(argument, expectedType: expectedType) {
      return borrowed
    }
    return lowerValue(argument)
  }

  private func lowerMethodReceiverArgument(_ base: TypedExpressionNode, method: Symbol) -> MIRValue {
    let methodType: Type
    if case .function = method.type, !context.containsGenericParameter(method.type) {
      methodType = method.type
    } else {
      methodType = programFunctionType(for: method.defId) ?? receiverAwareFunctionType(for: method)
    }
    if case .function(let parameters, _) = methodType,
       let first = parameters.first,
       let borrowed = lowerBorrowedReferenceArgument(base, expectedType: first.type) {
      return borrowed
    }
    return lowerValue(base)
  }

  private func lowerBorrowedReferenceArgument(_ argument: TypedExpressionNode, expectedType: Type?) -> MIRValue? {
    guard let expectedType else { return nil }

    func expectedRefInfo(_ type: Type) -> (family: Type.IndirectionFamily, inner: Type, mutable: Bool)? {
      type.indirectionCompatibilityInfo
    }

    switch expectedType {
    case .reference(let inner):
      // Managed ref T: only pass through existing compatible refs, no implicit T → ref T
      if isCompatibleManagedReferenceArgument(argument.type, expectedInner: inner, mutable: false) {
        return lowerValue(argument)
      }
    case .mutableReference(let inner):
      // Managed ref mutable T: only pass through existing compatible refs, no implicit T → ref mutable T
      if isCompatibleManagedReferenceArgument(argument.type, expectedInner: inner, mutable: true) {
        return lowerValue(argument)
      }
    case .borrowedReference(let inner):
      if canBorrowArgument(argument.type, as: inner), let place = lowerPlace(argument) {
        return .ref(place, kind: .shared, allocation: .stackBorrow)
      }
      if let info = expectedRefInfo(expectedType),
         let actualInfo = argument.type.indirectionCompatibilityInfo,
         info.family == actualInfo.family,
         !info.mutable,
         (actualInfo.inner == inner || context.containsGenericParameter(inner)) {
        return lowerValue(argument)
      }
    case .mutableBorrowedReference(let inner):
      if canBorrowArgument(argument.type, as: inner), let place = lowerPlace(argument) {
        return .ref(place, kind: .mutable, allocation: .stackBorrow)
      }
      if let info = expectedRefInfo(expectedType),
         let actualInfo = argument.type.indirectionCompatibilityInfo,
         info.family == actualInfo.family,
         info.mutable,
         actualInfo.mutable,
         (actualInfo.inner == inner || context.containsGenericParameter(inner)) {
        return lowerValue(argument)
      }
    case .weakReference(let inner):
      // A value that is already a weak handle is the expected kind of value
      // and passes through untouched (the wrap branch below must not rebuild
      // the handle as a weak REFERENCE of its place -- a template-spelled
      // expectation `?T` with a concrete `?Box` argument is what used to land
      // there). Anything else the borrow rule accepts is weak-wrapped through
      // the runtime's downgrade -- the same construction `expr as ?T` uses --
      // not through a reference.
      if !isWeakHandleType(argument.type),
         canBorrowArgument(argument.type, as: inner) {
        return .intrinsic(.downgradeRef(value: lowerValue(argument), resultType: expectedType))
      }
      if argument.type == expectedType {
        return lowerValue(argument)
      }
    case .mutableWeakReference(let inner):
      if !isWeakHandleType(argument.type),
         canBorrowArgument(argument.type, as: inner) {
        return .intrinsic(.downgradeRef(value: lowerValue(argument), resultType: expectedType))
      }
      if argument.type == expectedType {
        return lowerValue(argument)
      }
    default:
      break
    }
    return nil
  }

  private func isCompatibleManagedReferenceArgument(_ actualType: Type, expectedInner: Type, mutable: Bool) -> Bool {
    let expectedType: Type = mutable ? .mutableReference(inner: expectedInner) : .reference(inner: expectedInner)
    guard let (_, actualInner) = expectedType.compatibleIndirectionInners(with: actualType) else {
      return false
    }
    return actualInner == expectedInner || context.containsGenericParameter(expectedInner)
  }

  private func functionParameterTypes(for callee: MIROperand) -> [Type] {
    let calleeType: Type
    switch callee {
    case .function(let symbol):
      calleeType = programFunctionType(for: symbol.defId) ?? preferredFunctionType(for: symbol)
    case .local(let localID):
      calleeType = locals.first(where: { $0.id == localID })?.type ?? .void
    case .constant:
      return []
    }
    guard case .function(let parameters, _) = calleeType else {
      return []
    }
    return parameters.map(\.type)
  }

  private func concreteMethodSymbol(
    method: Symbol,
    calleeType: Type,
    resultType: Type
  ) -> Symbol? {
    // If the method symbol's type is already concrete, trust it — the
    // monomorphizer substituted method-level type parameters into it.
    if case .function = method.type, !context.containsGenericParameter(method.type) {
      return Symbol(defId: method.defId, type: method.type, kind: method.kind)
    }
    if let programType = programFunctionType(for: method.defId) {
      return Symbol(defId: method.defId, type: programType, kind: method.kind)
    }

    let preferredType = preferredFunctionType(for: method)
    if case .function = preferredType, !context.containsGenericParameter(preferredType) {
      return Symbol(defId: method.defId, type: preferredType, kind: method.kind)
    }

    guard case .function(let parameters, _) = calleeType else { return nil }

    let concreteType = Type.function(parameters: parameters, returns: resultType)
    guard !context.containsGenericParameter(concreteType) else { return nil }

    return Symbol(defId: method.defId, type: concreteType, kind: method.kind)
  }

  private func preferredFunctionType(for symbol: Symbol) -> Type {
    let symbolType = symbol.type
    let contextType = context.getSymbolType(symbol.defId)

    if case .function = symbolType, !context.containsGenericParameter(symbolType) {
      return symbolType
    }

    if let contextType,
       case .function = contextType,
       !context.containsGenericParameter(contextType) || !context.containsGenericParameter(symbolType) {
      return contextType
    }

    return symbolType
  }

  private func programFunctionType(for defId: DefId) -> Type? {
    for node in program.globalNodes {
      switch node {
      case .globalFunction(let identifier, let parameters, _):
        guard identifier.defId == defId else { continue }
        let returnType: Type
        if case .function(_, let returns) = identifier.type {
          returnType = returns
        } else {
          returnType = .void
        }
        return .function(
          parameters: parameters.map { Parameter(type: $0.type, kind: passKindForParameterType($0.type)) },
          returns: returnType
        )
      case .givenDeclaration(_, _, let methods):
        guard let method = methods.first(where: { $0.identifier.defId == defId }) else { continue }
        return .function(
          parameters: method.parameters.map { Parameter(type: $0.type, kind: passKindForParameterType($0.type)) },
          returns: method.returnType
        )
      default:
        continue
      }
    }
    return nil
  }

  private func receiverAwareFunctionType(for symbol: Symbol) -> Type {
    let symbolType = preferredFunctionType(for: symbol)
    guard let contextType = context.getSymbolType(symbol.defId),
          case .function(let contextParams, let contextReturn) = contextType,
          case .function(let symbolParams, let symbolReturn) = symbolType,
          let contextReceiver = contextParams.first?.type,
          let symbolReceiver = symbolParams.first?.type else {
      return symbolType
    }

    if isRefLikeType(contextReceiver) && !isRefLikeType(symbolReceiver) {
      let mergedParams = [Parameter(type: contextReceiver, kind: passKindForType(contextReceiver))]
        + symbolParams.dropFirst()
      return .function(parameters: mergedParams, returns: context.containsGenericParameter(contextReturn) ? symbolReturn : contextReturn)
    }

    return symbolType
  }

  private func isWeakHandleType(_ type: Type) -> Bool {
    switch type {
    case .weakReference, .mutableWeakReference:
      return true
    default:
      return false
    }
  }

  private func canBorrowArgument(_ actualType: Type, as expectedInner: Type) -> Bool {
    if actualType == expectedInner || context.containsGenericParameter(expectedInner) {
      return true
    }
    if !isRefLikeType(actualType) {
      return true
    }
    return context.getLayoutKey(actualType) == context.getLayoutKey(expectedInner)
  }

  private func isRefLikeType(_ type: Type) -> Bool {
    switch type {
    case .reference, .mutableReference,
         .borrowedReference, .mutableBorrowedReference,
         .weakReference, .mutableWeakReference:
      return true
    default:
      return false
    }
  }

  private func passKindForType(_ type: Type) -> PassKind {
    passKindForParameterType(type)
  }

  private func finishCall(
    callee: MIROperand,
    arguments: [MIRValue],
    argumentOwnerships: [MIROwnershipUse],
    type: Type
  ) -> MIRExprResult? {
    if case .function(let sym) = callee {
      let n = context.getName(sym.defId) ?? ""
    }
    let value = MIRValue.call(MIRCall(
      callee: callee,
      arguments: arguments,
      argumentOwnerships: argumentOwnerships,
      type: type
    ))
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
    case .downgradeRef(let value, let resultType):
      return .downgradeRef(value: lowerValue(value), resultType: resultType)
    case .upgradeRef(let value, let resultType):
      return .upgradeRef(value: lowerValue(value), resultType: resultType)
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

  private func lowerBorrowedSourceValue(_ expression: TypedExpressionNode) -> MIRValue {
    if case .castExpression(let inner, let targetType) = expression,
       isOwnershipPreservingBorrowCast(sourceType: inner.type, targetType: targetType) {
      return lowerBorrowedSourceValue(inner)
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

  private func isOwnershipPreservingBorrowCast(sourceType: Type, targetType: Type) -> Bool {
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

  /// The drop ABI hands `self` in as a pointer while the type system still
  /// calls it `Self`, so a local that is a pointer OF its own symbol type is
  /// that re-typed `self`. Reading it as the symbol's type means reading the
  /// pointee. A pointer the user declared has the pointer type on both sides
  /// and is left alone.
  private func derefDropSelfPlace(_ place: MIRPlace, for symbol: Symbol) -> MIRPlace {
    guard case .local(let localID) = place,
          let localType = locals.first(where: { $0.id == localID })?.type else {
      return place
    }
    let pointee: Type
    switch localType {
    case .pointer(let inner), .mutablePointer(let inner):
      pointee = inner
    default:
      return place
    }
    guard symbol.type == pointee else { return place }
    return .deref(base: .placeRead(place, ownership: .borrow), pointee: pointee)
  }

  private func lowerPlace(_ expression: TypedExpressionNode) -> MIRPlace? {
    switch expression {
    case .variable(let symbol):
      return derefDropSelfPlace(capturePlace(for: symbol), for: symbol)
    case .memberPath(let source, let path):
      let basePlace: MIRPlace?
      switch source.type {
      case .reference(let inner),
           .mutableReference(let inner),
           .borrowedReference(let inner),
           .mutableBorrowedReference(let inner),
           .weakReference(let inner),
           .mutableWeakReference(let inner),
           .pointer(let inner),
           .mutablePointer(let inner):
        basePlace = .deref(base: lowerBorrowedSourceValue(source), pointee: inner)
      default:
        basePlace = lowerPlace(source)
      }
      guard var place = basePlace else {
        return lowerMaterializedMemberPathPlace(expression)
      }
      for field in path {
        place = .field(base: place, field: field)
      }
      return place
        case .derefExpression(let inner, let type),
          .unsafeDerefExpression(let inner, let type):
      return .deref(base: lowerBorrowedSourceValue(inner), pointee: type)
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

  private func lowerMaterializedMemberPathPlace(_ expression: TypedExpressionNode) -> MIRPlace? {
    guard case .memberPath(let source, let path) = expression else {
      return nil
    }

    let sourceResult: MIRExprResult
    if let lowered = lowerExpression(source) {
      sourceResult = lowered
    } else {
      return nil
    }
    guard !currentBlockIsTerminated else { return nil }

    let basePlace: MIRPlace?
    if let place = sourceResult.place {
      basePlace = place
    } else if let operand = sourceResult.operand {
      switch operand {
      case .local(let localID):
        basePlace = .local(localID)
      default:
        let local = makeTemporary(type: source.type, nameHint: "member_base")
        append(.declare(local.id))
        append(.assign(.local(local.id), .operand(operand)))
        basePlace = .local(local.id)
      }
    } else {
      basePlace = nil
    }

    guard var place = basePlace else { return nil }
    for field in path {
      place = .field(base: place, field: field)
    }
    return place
  }

  private func capturePlace(for symbol: Symbol) -> MIRPlace {
    if let local = localByDefId[symbol.defId.id] {
      return .local(local)
    }
    if let place = patternPlaceByDefId[symbol.defId.id] {
      return place
    }
    // A flow payload is bound by the pattern of the arm that carries it, so it
    // is registered like any other pattern variable. Anything with no local
    // binding is a global.
    return .global(symbol.defId)
  }

  private func isReferenceType(_ type: Type) -> Bool {
    switch type {
    case .reference, .mutableReference, .weakReference, .mutableWeakReference:
      return true
    default:
      return false
    }
  }

  private func goesThroughDeref(_ place: MIRPlace) -> Bool {
    switch place {
    case .deref:
      return true
    case .field(let base, _),
         .enumPayload(let base, _, _, _, _):
      return goesThroughDeref(base)
    case .local, .global, .pointerElement:
      return false
    }
  }

  private func referenceKind(for type: Type) -> MIRReferenceKind {
    switch type {
    case .mutableReference, .mutableBorrowedReference:
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

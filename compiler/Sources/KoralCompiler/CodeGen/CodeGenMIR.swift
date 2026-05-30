import Foundation

private struct MIRValueCleanup {
  let name: String
  let type: Type
}

private struct MIRValueEmission {
  let expression: String
  let cleanups: [MIRValueCleanup]
}

private struct MIRPlaceAccess {
  let path: String
  let control: String
  let cleanups: [MIRValueCleanup]
}

private struct MIRLocalLifetimePlan {
  let rootLocals: [MIRLocalID]
  let localsByScope: [MIRScopeID: [MIRLocalID]]
}

final class MIRFunctionCodeEmitter {
  private let codeGen: CodeGen
  private let function: MIRFunction
  private let resolver: MIRTypeResolver
  private let localByID: [MIRLocalID: MIRLocal]
  private let localNameByID: [MIRLocalID: String]
  private let initFlagByLocalID: [MIRLocalID: String]
  private let lifetimePlan: MIRLocalLifetimePlan
  private let blockLabelByID: [MIRBlockID: String]
  private var lambdaCounter = 0
  private var nestedTypeDefinitions = ""
  private var nestedFunctionDefinitions = ""

  var generatedDefinitions: String {
    nestedTypeDefinitions + nestedFunctionDefinitions
  }

  init(codeGen: CodeGen, function: MIRFunction, localNameOverridesByDefId: [UInt64: String] = [:]) {
    self.codeGen = codeGen
    self.function = function
    self.resolver = MIRTypeResolver(function: function, context: codeGen.context)
    self.localByID = Dictionary(uniqueKeysWithValues: function.locals.map { ($0.id, $0) })

    var names: [MIRLocalID: String] = [:]
    for local in function.locals {
      if let symbol = local.symbol {
        names[local.id] = localNameOverridesByDefId[symbol.defId.id] ?? codeGen.cIdentifier(for: symbol)
      } else {
        let base = sanitizeCIdentifier(local.name)
        let stem = base.isEmpty ? "mir_local" : base
        names[local.id] = "__mir_\(stem)_\(local.id.rawValue)"
      }
    }
    self.localNameByID = names

    var flags: [MIRLocalID: String] = [:]
    for local in function.locals where local.storage != .capture && local.type != .void && local.type != .never && codeGen.needsDrop(local.type) {
      flags[local.id] = "__mir_init_\(local.id.rawValue)"
    }
    self.initFlagByLocalID = flags

    self.lifetimePlan = Self.buildLifetimePlan(function: function, needsDrop: codeGen.needsDrop)
    self.blockLabelByID = Dictionary(uniqueKeysWithValues: function.blocks.map { ($0.id, "__mir_bb_\($0.id.rawValue)") })
  }

  func emitBody() {
    emitLocalDeclarations()
    for block in function.blocks {
      emitBlock(block)
    }
  }

  private static func buildLifetimePlan(
    function: MIRFunction,
    needsDrop: (Type) -> Bool
  ) -> MIRLocalLifetimePlan {
    var parentScopeByScope: [MIRScopeID: MIRScopeID] = [:]
    var exitPositionByScope: [MIRScopeID: Int] = [:]
    var declaredScopeByLocal: [MIRLocalID: MIRScopeID] = [:]
    var declarationOrderByLocal: [MIRLocalID: Int] = [:]
    var lastUseByLocal: [MIRLocalID: Int] = [:]
    var activeScopes: [MIRScopeID] = []
    var position = 0

    func recordUse(_ local: MIRLocalID) {
      lastUseByLocal[local] = max(lastUseByLocal[local] ?? Int.min, position)
    }

    func walkOperand(_ operand: MIROperand) {
      if case .local(let local) = operand {
        recordUse(local)
      }
    }

    func walkPlace(_ place: MIRPlace) {
      switch place {
      case .local(let local):
        recordUse(local)
      case .global:
        break
      case .field(let base, _),
           .enumPayload(let base, _, _, _, _):
        walkPlace(base)
      case .deref(let base, _),
           .pointerElement(let base, _):
        walkValue(base)
      }
    }

    func walkIntrinsic(_ intrinsic: MIRIntrinsic) {
      switch intrinsic {
      case .allocMemory(let count, _):
        walkValue(count)
      case .deallocMemory(let ptr),
           .deinitMemory(let ptr),
           .takeMemory(let ptr, _),
           .isUniqueMutable(let ptr),
           .downgradeRef(let ptr, _),
           .downgradeMutRef(let ptr, _),
           .upgradeRef(let ptr, _),
           .upgradeMutRef(let ptr, _):
        walkValue(ptr)
      case .copyMemory(let dest, let source, let count),
           .moveMemory(let dest, let source, let count):
        walkValue(dest)
        walkValue(source)
        walkValue(count)
      case .makeRef(let ptr, let owner, _),
           .makeMutRef(let ptr, let owner, _),
           .initMemory(let ptr, let owner):
        walkValue(ptr)
        walkValue(owner)
      case .nullPtr:
        break
      case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
        walkValue(outHandle)
        walkValue(outTid)
        walkValue(closure)
        walkValue(stackSize)
      }
    }

    func walkValue(_ value: MIRValue) {
      switch value {
      case .operand(let operand):
        walkOperand(operand)
      case .placeRead(let place, _),
           .pointer(let place):
        walkPlace(place)
      case .binary(let operation):
        walkOperand(operation.left)
        walkOperand(operation.right)
      case .unary(let operation):
        walkOperand(operation.operand)
      case .call(let call):
        walkOperand(call.callee)
        for argument in call.arguments {
          walkValue(argument)
        }
      case .aggregate(let aggregate):
        for field in aggregate.fields {
          walkValue(field)
        }
      case .enumCase(let construction):
        for argument in construction.arguments {
          walkValue(argument)
        }
      case .enumTag(let tag):
        walkValue(tag.subject)
      case .traitObjectConversion(let conversion):
        walkValue(conversion.inner)
      case .traitMethodCall(let call):
        walkValue(call.receiver)
        for argument in call.arguments {
          walkValue(argument)
        }
      case .ref(let place, _, _):
        walkPlace(place)
      case .cast(let operand, _):
        walkOperand(operand)
      case .intrinsic(let intrinsic):
        walkIntrinsic(intrinsic)
      case .lambda(let lambda):
        for source in lambda.captureSources {
          walkPlace(source)
        }
      }
    }

    for block in function.blocks {
      for statement in block.statements {
        position += 1
        switch statement {
        case .scopeEnter(let scope):
          if let parent = activeScopes.last {
            parentScopeByScope[scope] = parent
          }
          activeScopes.append(scope)
        case .scopeExit(let scope):
          exitPositionByScope[scope] = position
          if let index = activeScopes.lastIndex(of: scope) {
            activeScopes.remove(at: index)
          }
        case .declare(let local):
          if let scope = activeScopes.last {
            declaredScopeByLocal[local] = scope
          }
          declarationOrderByLocal[local] = position
          recordUse(local)
        case .assign(let place, let value):
          walkPlace(place)
          walkValue(value)
        case .compoundAssign(let assignment):
          walkPlace(assignment.target)
          walkValue(assignment.value)
        case .drop(let place):
          walkPlace(place)
        case .retain(let value),
             .release(let value),
             .evaluate(let value):
          walkValue(value)
        case .debugSource:
          break
        }
      }

      position += 1
      switch block.terminator {
      case .branch(let condition, _, _):
        walkOperand(condition)
      case .switchValue(let operand, _, _):
        walkOperand(operand)
      case .returnValue(let operand):
        if let operand {
          walkOperand(operand)
        }
      case .goto,
           .unreachable:
        break
      }
    }

    var rootLocals: [MIRLocalID] = []
    var localsByScope: [MIRScopeID: [MIRLocalID]] = [:]

    for local in function.locals where local.type != .void && local.type != .never && needsDrop(local.type) {
      let usePosition = lastUseByLocal[local.id] ?? declarationOrderByLocal[local.id] ?? Int.min
      var scope = declaredScopeByLocal[local.id]
      while let scopeID = scope,
            let exitPosition = exitPositionByScope[scopeID],
            usePosition > exitPosition {
        scope = parentScopeByScope[scopeID]
      }

      if let scope {
        localsByScope[scope, default: []].append(local.id)
      } else {
        rootLocals.append(local.id)
      }
    }

    let sortByDeclaration: (MIRLocalID, MIRLocalID) -> Bool = { lhs, rhs in
      (declarationOrderByLocal[lhs] ?? Int.min) < (declarationOrderByLocal[rhs] ?? Int.min)
    }
    rootLocals.sort(by: sortByDeclaration)
    for key in localsByScope.keys {
      localsByScope[key]?.sort(by: sortByDeclaration)
    }

    return MIRLocalLifetimePlan(rootLocals: rootLocals, localsByScope: localsByScope)
  }

  private func emitLocalDeclarations() {
    for local in function.locals where local.storage != .parameter && local.storage != .capture && local.type != .void && local.type != .never {
      guard let name = localNameByID[local.id] else { continue }
      codeGen.addIndent()
      codeGen.appendToBuffer("\(codeGen.cTypeName(local.type)) \(name);\n")
    }

    for local in function.locals where initFlagByLocalID[local.id] != nil {
      guard let flag = initFlagByLocalID[local.id] else { continue }
      let initial = local.storage == .parameter ? "1" : "0"
      codeGen.addIndent()
      codeGen.appendToBuffer("_Bool \(flag) = \(initial);\n")
    }
  }

  private func emitBlock(_ block: MIRBasicBlock) {
    guard let label = blockLabelByID[block.id] else { return }
    let preservedLocal = preservedReturnLocal(for: block.terminator)
    codeGen.addIndent()
    codeGen.appendToBuffer("\(label):;\n")
    for statement in block.statements {
      emitStatement(statement, preserving: preservedLocal)
    }
    emitTerminator(block.terminator, preserving: preservedLocal)
  }

  private func emitStatement(_ statement: MIRStatement, preserving preservedLocal: MIRLocalID?) {
    switch statement {
    case .declare:
      break
    case .assign(let place, let value):
      emitAssign(place: place, value: value)
    case .compoundAssign(let assignment):
      emitCompoundAssign(assignment)
    case .drop(let place):
      emitDrop(place)
    case .retain(let value):
      emitRetain(value)
    case .release(let value):
      emitRelease(value)
    case .evaluate(let value):
      emitEvaluate(value)
    case .scopeEnter:
      break
    case .scopeExit(let scope):
      emitScopeCleanup(scope, excluding: preservedLocal)
    case .debugSource:
      break
    }
  }

  private func emitTerminator(_ terminator: MIRTerminator, preserving preservedLocal: MIRLocalID?) {
    switch terminator {
    case .goto(let block):
      emitGoto(block)
    case .branch(let condition, let thenBlock, let elseBlock):
      let conditionExpr = emitOperandExpression(condition)
      codeGen.addIndent()
      codeGen.appendToBuffer("if (\(conditionExpr)) { goto \(label(for: thenBlock)); }\n")
      codeGen.addIndent()
      codeGen.appendToBuffer("goto \(label(for: elseBlock));\n")
    case .switchValue(let operand, let cases, let defaultBlock):
      let switchExpr = emitOperandExpression(operand)
      codeGen.addIndent()
      codeGen.appendToBuffer("switch (\(switchExpr)) {\n")
      codeGen.withIndent {
        for switchCase in cases {
          codeGen.addIndent()
          codeGen.appendToBuffer("case \(switchCaseExpression(switchCase.value)): goto \(label(for: switchCase.target));\n")
        }
        codeGen.addIndent()
        if let defaultBlock {
          codeGen.appendToBuffer("default: goto \(label(for: defaultBlock));\n")
        } else {
          codeGen.appendToBuffer("default: __builtin_unreachable();\n")
        }
      }
      codeGen.addIndent()
      codeGen.appendToBuffer("}\n")
    case .returnValue(let operand):
      emitReturn(operand, preserving: preservedLocal)
    case .unreachable:
      codeGen.addIndent()
      codeGen.appendToBuffer("__builtin_unreachable();\n")
    }
  }

  private func emitAssign(place: MIRPlace, value: MIRValue) {
    let access = emitPlaceAccess(place)
    let valueEmission = emitValue(value)
    let destinationType = resolver.type(of: place) ?? function.returnType

    if let localID = localTargetID(for: place), let flag = initFlagByLocalID[localID] {
      if localByID[localID]?.type == destinationType {
        emitGuardedDrop(flag: flag, type: destinationType, expression: access.path)
      }
    } else if codeGen.needsDrop(destinationType) {
      let prepared = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(destinationType))
      codeGen.emitCopyOrMove(type: destinationType, source: valueEmission.expression, dest: prepared, isLvalue: false)
      codeGen.appendDropStatement(for: destinationType, value: access.path, indent: codeGen.indent)
      codeGen.emitCopyOrMove(type: destinationType, source: prepared, dest: access.path, isLvalue: false)
      consumeMovedSource(value)
      emitCleanups(access.cleanups)
      emitCleanups(residualCleanups(for: valueEmission, consumedExpression: true))
      setInitFlag(localTargetID(for: place), to: true)
      return
    }

    codeGen.emitCopyOrMove(type: destinationType, source: valueEmission.expression, dest: access.path, isLvalue: false)
    consumeMovedSource(value)
    emitCleanups(access.cleanups)
    emitCleanups(residualCleanups(for: valueEmission, consumedExpression: true))
    setInitFlag(localTargetID(for: place), to: true)
  }

  private func emitCompoundAssign(_ assignment: MIRCompoundAssignment) {
    let access = emitPlaceAccess(assignment.target)
    let valueEmission = emitValue(assignment.value)
    let targetType = resolver.type(of: assignment.target) ?? .void

    if (assignment.operatorKind == .shiftLeft || assignment.operatorKind == .shiftRight) && targetType.isIntegerType {
      let op: BitwiseOperator = assignment.operatorKind == .shiftLeft ? .shiftLeft : .shiftRight
      let functionName = codeGen.checkedShiftFuncName(op: op, type: targetType)
      codeGen.addIndent()
      codeGen.appendToBuffer("\(access.path) = \(functionName)(\(access.path), \(valueEmission.expression));\n")
    } else {
      let op = codeGen.compoundOpToC(assignment.operatorKind)
      codeGen.addIndent()
      codeGen.appendToBuffer("\(access.path) \(op) \(valueEmission.expression);\n")
    }

    consumeMovedSource(assignment.value)
    emitCleanups(access.cleanups)
    emitCleanups(residualCleanups(for: valueEmission, consumedExpression: true))
  }

  private func emitDrop(_ place: MIRPlace) {
    let access = emitPlaceAccess(place)
    if let localID = localTargetID(for: place), let flag = initFlagByLocalID[localID] {
      emitGuardedDrop(flag: flag, type: resolver.type(of: place) ?? .void, expression: access.path)
    } else {
      codeGen.appendDropStatement(for: resolver.type(of: place) ?? .void, value: access.path, indent: codeGen.indent)
      if let rootLocal = rootLocal(of: place), localTargetID(for: place) == nil {
        setInitFlag(rootLocal, to: false)
      }
    }
    emitCleanups(access.cleanups)
  }

  private func emitRetain(_ value: MIRValue) {
    let emission = emitValue(value, sourceMode: true)
    let type = resolver.type(of: value) ?? .void
    switch type {
    case .reference, .mutableReference, .traitObject:
      codeGen.addIndent()
      codeGen.appendToBuffer("if (((\(emission.expression)).control)) { __koral_retain(((\(emission.expression)).control)); }\n")
    case .weakReference, .mutableWeakReference:
      codeGen.addIndent()
      codeGen.appendToBuffer("if (((\(emission.expression)).control)) { __koral_weak_retain(((\(emission.expression)).control)); }\n")
    case .function:
      codeGen.addIndent()
      codeGen.appendToBuffer("__koral_closure_retain(\(emission.expression));\n")
    default:
      fatalError("Unsupported retain type in MIR codegen: \(type)")
    }
    emitCleanups(emission.cleanups)
  }

  private func emitRelease(_ value: MIRValue) {
    let emission = emitValue(value, sourceMode: true)
    codeGen.appendDropStatement(for: resolver.type(of: value) ?? .void, value: emission.expression, indent: codeGen.indent)
    emitCleanups(emission.cleanups)
  }

  private func emitEvaluate(_ value: MIRValue) {
    let emission = emitValue(value)
    let type = resolver.type(of: value) ?? .void
    if shouldDropDiscardedValue(value: value, type: type) {
      if case .operand(.local(let local)) = value {
        if let flag = initFlagByLocalID[local] {
          emitGuardedDrop(flag: flag, type: type, expression: emission.expression)
        } else {
          codeGen.appendDropStatement(for: type, value: emission.expression, indent: codeGen.indent)
        }
      } else {
        codeGen.appendDropStatement(for: type, value: emission.expression, indent: codeGen.indent)
      }
      emitCleanups(residualCleanups(for: emission, consumedExpression: true))
      if case .operand(.local(let local)) = value {
        setInitFlag(local, to: false)
      }
      return
    }

    emitCleanups(emission.cleanups)
  }

  private func emitScopeCleanup(_ scope: MIRScopeID, excluding preservedLocal: MIRLocalID?) {
    let locals = lifetimePlan.localsByScope[scope] ?? []
    for local in locals.reversed() {
      if local == preservedLocal {
        continue
      }
      guard let flag = initFlagByLocalID[local], let info = localByID[local], let name = localNameByID[local] else {
        continue
      }
      emitGuardedDrop(flag: flag, type: info.type, expression: name)
    }
  }

  private func emitReturn(_ operand: MIROperand?, preserving preservedLocal: MIRLocalID?) {
    if let operand {
      let emission = emitOperandValue(operand)
      let returnedLocal = preservedLocal ?? preservedReturnLocal(for: operand, emission: emission)
      setInitFlag(returnedLocal, to: false)
      emitRootCleanup(excluding: returnedLocal)
      codeGen.addIndent()
      codeGen.appendToBuffer("return \(emission.expression);\n")
      emitCleanups(residualCleanups(for: emission, consumedExpression: true))
      return
    }

    emitRootCleanup(excluding: nil)
    codeGen.addIndent()
    codeGen.appendToBuffer("return;\n")
  }

  private func emitRootCleanup(excluding preservedLocal: MIRLocalID?) {
    for local in lifetimePlan.rootLocals.reversed() {
      if local == preservedLocal {
        continue
      }
      guard let flag = initFlagByLocalID[local], let info = localByID[local], let name = localNameByID[local] else {
        continue
      }
      emitGuardedDrop(flag: flag, type: info.type, expression: name)
    }
  }

  private func preservedReturnLocal(for operand: MIROperand, emission: MIRValueEmission) -> MIRLocalID? {
    if case .local(let local) = operand {
      return local
    }

    return localNameByID.first(where: { $0.value == emission.expression })?.key
  }

  private func preservedReturnLocal(for terminator: MIRTerminator) -> MIRLocalID? {
    guard case .returnValue(let operand?) = terminator else {
      return nil
    }

    if case .local(let local) = operand {
      return local
    }

    return nil
  }

  private func emitGuardedDrop(flag: String, type: Type, expression: String) {
    codeGen.addIndent()
    codeGen.appendToBuffer("if (\(flag)) {\n")
    codeGen.withIndent {
      codeGen.appendDropStatement(for: type, value: expression, indent: codeGen.indent)
      codeGen.addIndent()
      codeGen.appendToBuffer("\(flag) = 0;\n")
    }
    codeGen.addIndent()
    codeGen.appendToBuffer("}\n")
  }

  private func emitValue(_ value: MIRValue, sourceMode: Bool = false) -> MIRValueEmission {
    switch value {
    case .operand(let operand):
      return emitOperandValue(operand)
    case .placeRead(let place, let ownership):
      return emitPlaceRead(place: place, ownership: ownership, sourceMode: sourceMode)
    case .binary(let operation):
      return emitBinary(operation)
    case .unary(let operation):
      return emitUnary(operation)
    case .call(let call):
      return emitCall(call)
    case .aggregate(let aggregate):
      return emitAggregate(aggregate)
    case .enumCase(let construction):
      return emitEnumCase(construction)
    case .enumTag(let tag):
      return emitEnumTag(tag)
    case .traitObjectConversion(let conversion):
      return emitTraitObjectConversion(conversion)
    case .traitMethodCall(let call):
      return emitTraitMethodCall(call)
    case .ref(let place, let kind, let allocation):
      return emitReference(place: place, kind: kind, allocation: allocation)
    case .pointer(let place):
      return emitPointer(place)
    case .cast(let operand, let type):
      return emitCastOperand(operand, targetType: type)
    case .intrinsic(let intrinsic):
      return emitIntrinsic(intrinsic)
    case .lambda(let lambda):
      return emitLambda(lambda)
    }
  }

  private func emitLambda(_ lambda: MIRLambda) -> MIRValueEmission {
    var captureSourceOverrides: [UInt64: String] = [:]
    var captureSourceCleanups: [MIRValueCleanup] = []
    for (capture, source) in zip(lambda.captures, lambda.captureSources) {
      let access = emitPlaceAccess(source)
      captureSourceOverrides[capture.symbol.defId.id] = access.path
      captureSourceCleanups.append(contentsOf: access.cleanups)
    }
    let closure = generateLambdaExpression(lambda, captureSourceOverrides: captureSourceOverrides)
    emitCleanups(captureSourceCleanups)
    return MIRValueEmission(
      expression: closure,
      cleanups: cleanupForTemporaryResult(expression: closure, type: lambda.type)
    )
  }

  private func nextLambdaName() -> String {
    let name = "__koral_lambda_\(function.identifier.defId.id)_\(lambdaCounter)"
    lambdaCounter += 1
    return name
  }

  private func captureFieldName(for symbol: Symbol) -> String {
    codeGen.cIdentifier(for: symbol)
  }

  private func generateLambdaExpression(
    _ lambda: MIRLambda,
    captureSourceOverrides: [UInt64: String]
  ) -> String {
    guard case .function(let functionParameters, let returnType) = lambda.type else {
      fatalError("Lambda expression must have function type")
    }

    let lambdaName = nextLambdaName()
    if lambda.captures.isEmpty {
      generateNoCaptureLambdaFunction(
        name: lambdaName,
        parameters: lambda.parameters,
        functionParameters: functionParameters,
        returnType: returnType,
        mirFunction: lambda.function
      )
      return codeGen.nextTempWithInit(
        cType: "struct __koral_Closure",
        initExpr: "{ .fn = (void*)\(lambdaName), .env = NULL, .drop = NULL }"
      )
    }

    let envStructName = "\(lambdaName)_env"
    generateLambdaEnvStruct(name: envStructName, captures: lambda.captures)
    generateCaptureLambdaFunction(
      name: lambdaName,
      envStructName: envStructName,
      parameters: lambda.parameters,
      functionParameters: functionParameters,
      returnType: returnType,
      captures: lambda.captures,
      mirFunction: lambda.function
    )

    let envVar = codeGen.nextTempWithInit(
      cType: "struct \(envStructName)*",
      initExpr: "(struct \(envStructName)*)malloc(sizeof(struct \(envStructName)))"
    )
    codeGen.addIndent()
    codeGen.appendToBuffer("\(envVar)->__refcount = 1;\n")

    for capture in lambda.captures {
      let fieldName = captureFieldName(for: capture.symbol)
      guard let source = captureSourceOverrides[capture.symbol.defId.id] else {
        fatalError("Missing MIR lambda capture source for \(capture.symbol.defId.id)")
      }
      codeGen.addIndent()
      codeGen.appendCopyAssignment(for: capture.symbol.type, source: source, dest: "\(envVar)->\(fieldName)", indent: "")
    }

    return codeGen.nextTempWithInit(
      cType: "struct __koral_Closure",
      initExpr: "{ .fn = (void*)\(lambdaName), .env = \(envVar), .drop = __koral_\(envStructName)_drop }"
    )
  }

  private func renderNestedMIRFunctionBody(
    _ mirFunction: MIRFunction,
    localNameOverridesByDefId: [UInt64: String] = [:]
  ) -> (definitions: String, body: String) {
    let savedBuffer = codeGen.buffer
    let savedIndent = codeGen.indent
    codeGen.buffer = ""
    codeGen.indent = "  "

    let emitter = MIRFunctionCodeEmitter(
      codeGen: codeGen,
      function: mirFunction,
      localNameOverridesByDefId: localNameOverridesByDefId
    )
    emitter.emitBody()
    let body = codeGen.buffer
    let definitions = emitter.generatedDefinitions

    codeGen.buffer = savedBuffer
    codeGen.indent = savedIndent
    return (definitions, body)
  }

  private func generateNoCaptureLambdaFunction(
    name: String,
    parameters: [Symbol],
    functionParameters: [Parameter],
    returnType: Type,
    mirFunction: MIRFunction
  ) {
    let returnCType = codeGen.cTypeName(returnType)
    let params = parameters.enumerated().map { index, parameter in
      "\(codeGen.cTypeName(functionParameters[index].type)) \(codeGen.cIdentifier(for: parameter))"
    }
    let paramsStr = params.isEmpty ? "void" : params.joined(separator: ", ")
    let nested = renderNestedMIRFunctionBody(mirFunction)

    var functionBuffer = nested.definitions
    functionBuffer += "\nstatic \(returnCType) \(name)(\(paramsStr));\n"
    functionBuffer += "static \(returnCType) \(name)(\(paramsStr)) {\n"
    functionBuffer += nested.body
    functionBuffer += "}\n"
    nestedFunctionDefinitions += functionBuffer
  }

  private func generateCaptureLambdaFunction(
    name: String,
    envStructName: String,
    parameters: [Symbol],
    functionParameters: [Parameter],
    returnType: Type,
    captures: [CapturedVariable],
    mirFunction: MIRFunction
  ) {
    let returnCType = codeGen.cTypeName(returnType)
    var params = ["void* __env"]
    for (index, parameter) in parameters.enumerated() {
      params.append("\(codeGen.cTypeName(functionParameters[index].type)) \(codeGen.cIdentifier(for: parameter))")
    }

    var localNameOverridesByDefId: [UInt64: String] = [:]
    for capture in captures {
      localNameOverridesByDefId[capture.symbol.defId.id] = "__captured->\(captureFieldName(for: capture.symbol))"
    }
    let nested = renderNestedMIRFunctionBody(mirFunction, localNameOverridesByDefId: localNameOverridesByDefId)

    var functionBuffer = nested.definitions
    functionBuffer += "\nstatic \(returnCType) \(name)(\(params.joined(separator: ", ")));\n"
    functionBuffer += "static \(returnCType) \(name)(\(params.joined(separator: ", "))) {\n"
    functionBuffer += "  struct \(envStructName)* __captured = (struct \(envStructName)*)__env;\n"
    functionBuffer += nested.body
    functionBuffer += "}\n"
    nestedFunctionDefinitions += functionBuffer
  }

  private func generateLambdaEnvStruct(name: String, captures: [CapturedVariable]) {
    func appendIndented(_ code: String, to buffer: inout String, indent: String) {
      let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      for line in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
        buffer += "\(indent)\(line)\n"
      }
    }

    func dropCodeForCapturedField(_ type: Type, fieldExpr: String) -> String {
      switch type {
      case .function:
        return "__koral_closure_release(\(fieldExpr));\n"
      case .structure(let defId):
        if codeGen.context.isForeignStruct(defId) { return "" }
        let typeName = codeGen.cIdentifierByDefId[codeGen.defIdKey(defId)] ?? codeGen.context.getCIdentifier(defId) ?? "T_\(defId.id)"
        return "__koral_\(typeName)_drop(&(\(fieldExpr)));\n"
      case .enum(let defId):
        let typeName = codeGen.cIdentifierByDefId[codeGen.defIdKey(defId)] ?? codeGen.context.getCIdentifier(defId) ?? "U_\(defId.id)"
        return "__koral_\(typeName)_drop(&(\(fieldExpr)));\n"
      default:
        return TypeHandlerRegistry.shared.generateDropCode(type, value: fieldExpr)
      }
    }

    var structBuffer = "\nstruct \(name) {\n"
    structBuffer += "  _Atomic intptr_t __refcount;\n"
    for capture in captures {
      structBuffer += "  \(codeGen.cTypeName(capture.symbol.type)) \(captureFieldName(for: capture.symbol));\n"
    }
    structBuffer += "};\n"

    structBuffer += "\nstatic void __koral_\(name)_drop(void* raw_env) {\n"
    structBuffer += "  struct \(name)* env = (struct \(name)*)raw_env;\n"
    for capture in captures {
      let fieldExpr = "env->\(captureFieldName(for: capture.symbol))"
      appendIndented(dropCodeForCapturedField(capture.symbol.type, fieldExpr: fieldExpr), to: &structBuffer, indent: "  ")
    }
    structBuffer += "  free(raw_env);\n"
    structBuffer += "}\n"
    nestedTypeDefinitions += structBuffer
  }

  private func emitOperandValue(_ operand: MIROperand) -> MIRValueEmission {
    switch operand {
    case .local(let local):
      return MIRValueEmission(expression: localName(for: local), cleanups: [])
    case .function(let symbol):
      return MIRValueEmission(expression: codeGen.qualifiedName(for: symbol), cleanups: [])
    case .constant(let constant):
      switch constant {
      case .integer(let value, _):
        return MIRValueEmission(expression: value, cleanups: [])
      case .float(let value, _):
        return MIRValueEmission(expression: value, cleanups: [])
      case .boolean(let value):
        return MIRValueEmission(expression: value ? "1" : "0", cleanups: [])
      case .void:
        return MIRValueEmission(expression: "0", cleanups: [])
      case .string(let value, let type):
        let expression = codeGen.generateStringLiteral(value, type: type)
        return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: type))
      }
    }
  }

  private func emitPlaceRead(place: MIRPlace, ownership: MIROwnershipUse, sourceMode: Bool) -> MIRValueEmission {
    let access = emitPlaceAccess(place)
    let type = resolver.type(of: place) ?? .void

    if ownership == .move {
      consumeMovedPlace(place)
    }

    if sourceMode || ownership != .copy || !codeGen.needsDrop(type) {
      return MIRValueEmission(expression: access.path, cleanups: access.cleanups)
    }

    let temp = codeGen.emitTempCopyOrMove(type: type, source: access.path, isLvalue: true)
    emitCleanups(access.cleanups)
    return MIRValueEmission(expression: temp, cleanups: cleanupForTemporaryResult(expression: temp, type: type))
  }

  private func emitBinary(_ operation: MIRBinaryOperation) -> MIRValueEmission {
    let left = emitOperandExpression(operation.left)
    let right = emitOperandExpression(operation.right)
    let resultType = operation.type
    let cType = codeGen.cTypeName(resultType)

    let expression: String
    switch operation.operatorKind {
    case .arithmetic(let op, let checked):
      if checked && resultType.isIntegerType {
        let functionName = codeGen.checkedArithmeticFuncName(op: op, type: resultType)
        expression = codeGen.nextTempWithInit(cType: cType, initExpr: "\(functionName)(\(left), \(right))")
      } else {
        expression = codeGen.nextTempWithInit(cType: cType, initExpr: "\(left) \(codeGen.arithmeticOpToC(op)) \(right)")
      }
    case .wrappingArithmetic(let op):
      let functionName = codeGen.wrappingArithmeticFuncName(op: op, type: resultType)
      expression = codeGen.nextTempWithInit(cType: cType, initExpr: "\(functionName)(\(left), \(right))")
    case .comparison(let op):
      expression = codeGen.nextTempWithInit(cType: cType, initExpr: "\(left) \(codeGen.comparisonOpToC(op)) \(right)")
    case .logicalAnd:
      expression = codeGen.nextTempWithInit(cType: "_Bool", initExpr: "\(left) && \(right)")
    case .logicalOr:
      expression = codeGen.nextTempWithInit(cType: "_Bool", initExpr: "\(left) || \(right)")
    case .bitwise(let op, let checkedShift):
      if checkedShift && resultType.isIntegerType {
        let functionName = codeGen.checkedShiftFuncName(op: op, type: resultType)
        expression = codeGen.nextTempWithInit(cType: cType, initExpr: "\(functionName)(\(left), \(right))")
      } else {
        expression = codeGen.nextTempWithInit(cType: cType, initExpr: "\(left) \(codeGen.bitwiseOpToC(op)) \(right)")
      }
    case .wrappingShift(let op):
      let functionName = codeGen.wrappingShiftFuncName(op: op, type: resultType)
      expression = codeGen.nextTempWithInit(cType: cType, initExpr: "\(functionName)(\(left), \(right))")
    }

    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: resultType))
  }

  private func emitUnary(_ operation: MIRUnaryOperation) -> MIRValueEmission {
    let operand = emitOperandExpression(operation.operand)
    let resultType = operation.type
    switch operation.operatorKind {
    case .logicalNot:
      let expression = codeGen.nextTempWithInit(cType: "_Bool", initExpr: "!\(operand)")
      return MIRValueEmission(expression: expression, cleanups: [])
    case .bitwiseNot:
      let expression = codeGen.nextTempWithInit(cType: codeGen.cTypeName(resultType), initExpr: "~\(operand)")
      return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: resultType))
    }
  }

  private func emitCall(_ call: MIRCall) -> MIRValueEmission {
    let argumentEmissions = call.arguments.map { emitValue($0) }
    let argumentList = argumentEmissions.map(\.expression)

    let expression: String
    switch call.callee {
    case .function(let symbol):
      expression = emitDirectCall(functionName: codeGen.qualifiedName(for: symbol), arguments: argumentList, returnType: call.type)
    default:
      let calleeType = resolver.type(of: call.callee) ?? .void
      guard case .function(let parameters, let returns) = calleeType else {
        fatalError("Unsupported MIR callee type in \(function.identifier.defId.id): \(calleeType)")
      }
      let calleeExpr = emitOperandExpression(call.callee)
      expression = emitClosureCall(closureExpr: calleeExpr, parameters: parameters, returnType: returns, arguments: argumentList)
    }

    for argument in call.arguments {
      consumeMovedSource(argument)
    }
    for emission in argumentEmissions {
      emitCleanups(residualCleanups(for: emission, consumedExpression: true))
    }

    if call.type == .void || call.type == .never {
      return MIRValueEmission(expression: "", cleanups: [])
    }
    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: call.type))
  }

  private func emitAggregate(_ aggregate: MIRAggregate) -> MIRValueEmission {
    let fieldEmissions = aggregate.fields.map { emitValue($0) }
    let args = fieldEmissions.map(\.expression).joined(separator: ", ")
    let expression = codeGen.nextTempWithInit(cType: codeGen.cTypeName(aggregate.type), initExpr: "{\(args)}")
    for (value, emission) in zip(aggregate.fields, fieldEmissions) {
      consumeMovedSource(value)
      emitCleanups(residualCleanups(for: emission, consumedExpression: true))
    }
    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: aggregate.type))
  }

  private func emitEnumCase(_ construction: MIREnumConstruction) -> MIRValueEmission {
    guard case .enum(let defId) = construction.type else {
      fatalError("MIR enum construction requires enum type")
    }

    let cases = codeGen.context.getEnumCases(defId) ?? []
    guard let caseIndex = cases.firstIndex(where: { $0.name == construction.caseName }) else {
      fatalError("Unknown enum case \(construction.caseName) in MIR codegen")
    }

    let expression = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(construction.type))
    codeGen.addIndent()
    codeGen.appendToBuffer("\(expression).tag = \(caseIndex);\n")

    let caseInfo = cases[caseIndex]
    let fieldEmissions = construction.arguments.map { emitValue($0) }
    let memberBase = "\(expression).data.\(sanitizeCIdentifier(construction.caseName))"
    var emissionIndex = 0
    for parameter in caseInfo.parameters {
      if parameter.type == .void {
        continue
      }
      let emission = fieldEmissions[emissionIndex]
      let fieldName = sanitizeCIdentifier(parameter.name)
      codeGen.addIndent()
      codeGen.appendToBuffer("\(memberBase).\(fieldName) = \(emission.expression);\n")
      consumeMovedSource(construction.arguments[emissionIndex])
      emitCleanups(residualCleanups(for: emission, consumedExpression: true))
      emissionIndex += 1
    }

    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: construction.type))
  }

  private func emitEnumTag(_ tag: MIREnumTag) -> MIRValueEmission {
    let subject = emitValue(tag.subject, sourceMode: true)
    let expression = codeGen.nextTempWithInit(cType: codeGen.cTypeName(.int), initExpr: "\(subject.expression).tag")
    emitCleanups(subject.cleanups)
    return MIRValueEmission(expression: expression, cleanups: [])
  }

  private func emitTraitObjectConversion(_ conversion: MIRTraitObjectConversion) -> MIRValueEmission {
    let inner = emitValue(conversion.inner, sourceMode: true)
    let innerType = resolver.type(of: conversion.inner) ?? conversion.type
    let expression = codeGen.generateTraitObjectConversionABI(
      innerResult: inner.expression,
      innerType: innerType,
      sourceOwnership: conversion.sourceOwnership,
      traitName: conversion.traitName,
      traitTypeArgs: conversion.traitTypeArguments,
      concreteType: conversion.concreteType
    )
    if conversion.sourceOwnership == .move {
      consumeMovedSource(conversion.inner)
    }
    emitCleanups(residualCleanups(for: inner, consumedExpression: conversion.sourceOwnership == .move))
    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: conversion.type))
  }

  private func emitTraitMethodCall(_ call: MIRTraitMethodCall) -> MIRValueEmission {
    let receiver = emitValue(call.receiver, sourceMode: true)
    let arguments = call.arguments.map { emitValue($0, sourceMode: true) }
    let abiArguments = zip(arguments, zip(call.arguments, call.argumentOwnerships)).map { emission, payload in
      CodeGenTraitCallArgument(value: emission.expression, type: resolver.type(of: payload.0) ?? .void, ownership: payload.1)
    }
    let expression = codeGen.generateTraitMethodCallABI(
      receiverResult: receiver.expression,
      receiverOwnership: call.receiverOwnership,
      traitName: call.traitName,
      traitTypeArgs: call.traitTypeArguments,
      methodName: call.methodName,
      arguments: abiArguments,
      type: call.type
    )
    if call.receiverOwnership == .move {
      consumeMovedSource(call.receiver)
    }
    emitCleanups(residualCleanups(for: receiver, consumedExpression: call.receiverOwnership == .move))
    for ((value, ownership), emission) in zip(zip(call.arguments, call.argumentOwnerships), arguments) {
      if ownership == .move {
        consumeMovedSource(value)
      }
      emitCleanups(residualCleanups(for: emission, consumedExpression: ownership == .move))
    }
    if call.type == .void || call.type == .never {
      return MIRValueEmission(expression: "", cleanups: [])
    }
    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: call.type))
  }

  private func emitReference(
    place: MIRPlace,
    kind: MIRReferenceKind,
    allocation: MIRReferenceAllocation
  ) -> MIRValueEmission {
    let resultType = resolver.type(of: .ref(place, kind: kind, allocation: allocation)) ?? .void
    guard kind == .shared || kind == .mutable else {
      fatalError("Unsupported MIR reference kind in direct emission: \(kind)")
    }

    if allocation == .heapOwned {
      return emitHeapReference(place: place, resultType: resultType, allocation: allocation)
    }
    return emitBorrowedReference(place: place, resultType: resultType)
  }

  private func emitBorrowedReference(place: MIRPlace, resultType: Type) -> MIRValueEmission {
    let access = emitPlaceAccess(place)
    let result = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(resultType))
    codeGen.addIndent()
    codeGen.appendToBuffer("\(result).ptr = &\(access.path);\n")
    codeGen.addIndent()
    codeGen.appendToBuffer("\(result).control = \(access.control);\n")
    codeGen.addIndent()
    codeGen.appendToBuffer("if (\(result).control) { __koral_retain(\(result).control); }\n")
    emitCleanups(access.cleanups)
    return MIRValueEmission(expression: result, cleanups: cleanupForTemporaryResult(expression: result, type: resultType))
  }

  private func emitHeapReference(
    place: MIRPlace,
    resultType: Type,
    allocation: MIRReferenceAllocation
  ) -> MIRValueEmission {
    let access = emitPlaceAccess(place)
    let pointeeType = resolver.type(of: place) ?? .void
    let pointeeCType = codeGen.cTypeName(pointeeType)
    let result = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(resultType))
    let shouldTransfer = allocation == .heapOwned && canTransferOwnedHeapReference(place: place)

    codeGen.addIndent()
    codeGen.appendToBuffer("\(result).ptr = malloc(sizeof(\(pointeeCType)));\n")
    codeGen.emitCopyOrMove(
      type: pointeeType,
      source: access.path,
      dest: "*(\(pointeeCType)*)\(result).ptr",
      isLvalue: !shouldTransfer
    )
    if shouldTransfer {
      consumeMovedPlace(place)
    }

    codeGen.addIndent()
    codeGen.appendToBuffer("\(result).control = malloc(sizeof(struct __koral_Control));\n")
    codeGen.addIndent()
    codeGen.appendToBuffer("((struct __koral_Control*)\(result).control)->strong_count = 1;\n")
    codeGen.addIndent()
    codeGen.appendToBuffer("((struct __koral_Control*)\(result).control)->weak_count = 1;\n")
    codeGen.addIndent()
    codeGen.appendToBuffer("((struct __koral_Control*)\(result).control)->ptr = \(result).ptr;\n")
    switch pointeeType {
    case .structure(let defId):
      let typeName = codeGen.cIdentifierByDefId[codeGen.defIdKey(defId)] ?? codeGen.context.getCIdentifier(defId) ?? "T_\(defId.id)"
      codeGen.addIndent()
      codeGen.appendToBuffer("((struct __koral_Control*)\(result).control)->dtor = (__koral_Dtor)__koral_\(typeName)_drop;\n")
    case .enum(let defId):
      let typeName = codeGen.cIdentifierByDefId[codeGen.defIdKey(defId)] ?? codeGen.context.getCIdentifier(defId) ?? "U_\(defId.id)"
      codeGen.addIndent()
      codeGen.appendToBuffer("((struct __koral_Control*)\(result).control)->dtor = (__koral_Dtor)__koral_\(typeName)_drop;\n")
    default:
      codeGen.addIndent()
      codeGen.appendToBuffer("((struct __koral_Control*)\(result).control)->dtor = NULL;\n")
    }
    emitCleanups(access.cleanups)
    return MIRValueEmission(expression: result, cleanups: cleanupForTemporaryResult(expression: result, type: resultType))
  }

  private func canTransferOwnedHeapReference(place: MIRPlace) -> Bool {
    guard case .local(let local) = place else {
      return false
    }
    return initFlagByLocalID[local] != nil
  }

  private func emitPointer(_ place: MIRPlace) -> MIRValueEmission {
    let access = emitPlaceAccess(place)
    let type = resolver.type(of: .pointer(place)) ?? .void
    let expression = codeGen.nextTempWithInit(cType: codeGen.cTypeName(type), initExpr: "&\(access.path)")
    emitCleanups(access.cleanups)
    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: type))
  }

  private func emitCastOperand(_ operand: MIROperand, targetType: Type) -> MIRValueEmission {
    let sourceEmission = emitOperandValue(operand)
    let sourceType = resolver.type(of: operand) ?? targetType

    if isOwnershipPreservingCast(sourceType: sourceType, targetType: targetType) {
      return sourceEmission
    }

    let expression = emitScalarOrPointerCast(expression: sourceEmission.expression, sourceType: sourceType, targetType: targetType)
    emitCleanups(sourceEmission.cleanups)
    return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: targetType))
  }

  private func isOwnershipPreservingCast(sourceType: Type, targetType: Type) -> Bool {
    switch (sourceType, targetType) {
    case (.reference, .reference),
         (.reference, .mutableReference),
         (.mutableReference, .reference),
         (.mutableReference, .mutableReference),
         (.weakReference, .weakReference),
         (.weakReference, .mutableWeakReference),
         (.mutableWeakReference, .weakReference),
         (.mutableWeakReference, .mutableWeakReference),
         (.pointer, .pointer),
         (.pointer, .mutablePointer),
         (.mutablePointer, .pointer),
         (.mutablePointer, .mutablePointer):
      return true
    default:
      return false
    }
  }

  private func emitIntrinsic(_ intrinsic: MIRIntrinsic) -> MIRValueEmission {
    switch intrinsic {
    case .allocMemory(let count, let resultType):
      let countEmission = emitValue(count, sourceMode: true)
      let elementType: Type
      switch resultType {
      case .pointer(let element), .mutablePointer(let element):
        elementType = element
      default:
        fatalError("alloc_memory expects pointer result type")
      }
      let expression = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(resultType))
      codeGen.addIndent()
      codeGen.appendToBuffer("\(expression) = malloc(\(countEmission.expression) * sizeof(\(codeGen.cTypeName(elementType))));\n")
      emitCleanups(countEmission.cleanups)
      return MIRValueEmission(expression: expression, cleanups: [])

    case .deallocMemory(let ptr):
      let ptrEmission = emitValue(ptr, sourceMode: true)
      codeGen.addIndent()
      codeGen.appendToBuffer("free(\(ptrEmission.expression));\n")
      emitCleanups(ptrEmission.cleanups)
      return MIRValueEmission(expression: "", cleanups: [])

    case .copyMemory(let dest, let source, let count):
      return emitMemoryTransfer(functionName: "memcpy", dest: dest, source: source, count: count)

    case .moveMemory(let dest, let source, let count):
      return emitMemoryTransfer(functionName: "memmove", dest: dest, source: source, count: count)

    case .isUniqueMutable(let value):
      let valueEmission = emitValue(value, sourceMode: true)
      let result = codeGen.nextTempWithDecl(cType: "int")
      let control = controlExpression(for: resolver.type(of: value) ?? .void, value: valueEmission.expression)
      codeGen.addIndent()
      codeGen.appendToBuffer("\(result) = 0;\n")
      codeGen.addIndent()
      codeGen.appendToBuffer("if (\(control)) {\n")
      codeGen.withIndent {
        codeGen.addIndent()
        codeGen.appendToBuffer("\(result) = (atomic_load(&((struct __koral_Control*)\(control))->strong_count) == 1);\n")
      }
      codeGen.addIndent()
      codeGen.appendToBuffer("}\n")
      emitCleanups(valueEmission.cleanups)
      return MIRValueEmission(expression: result, cleanups: [])

    case .makeRef(let ptr, let owner, let resultType),
         .makeMutRef(let ptr, let owner, let resultType):
      let ptrEmission = emitValue(ptr, sourceMode: true)
      let ownerEmission = emitValue(owner, sourceMode: true)
      let result = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(resultType))
      codeGen.addIndent()
      codeGen.appendToBuffer("\(result).ptr = (void*)\(ptrEmission.expression);\n")
      codeGen.addIndent()
      codeGen.appendToBuffer("\(result).control = \(ownerEmission.expression).control;\n")
      codeGen.addIndent()
      codeGen.appendToBuffer("if (\(result).control) { __koral_retain(\(result).control); }\n")
      emitCleanups(ptrEmission.cleanups + ownerEmission.cleanups)
      return MIRValueEmission(expression: result, cleanups: cleanupForTemporaryResult(expression: result, type: resultType))

    case .downgradeRef(let value, let resultType),
         .downgradeMutRef(let value, let resultType):
      let valueEmission = emitValue(value, sourceMode: true)
      let expression: String
      switch resolver.type(of: value) ?? .void {
      case .reference(let inner) where isTraitObjectType(inner),
           .mutableReference(let inner) where isTraitObjectType(inner):
        expression = codeGen.nextTempWithDecl(cType: "struct __koral_TraitWeakRef")
        let weakTemp = codeGen.nextTempWithDecl(cType: "struct __koral_WeakRef")
        codeGen.addIndent()
        codeGen.appendToBuffer("\(weakTemp) = __koral_downgrade_ref((struct __koral_Ref){\(valueEmission.expression).ptr, \(valueEmission.expression).control});\n")
        codeGen.addIndent()
        codeGen.appendToBuffer("\(expression).control = \(weakTemp).control;\n")
        codeGen.addIndent()
        codeGen.appendToBuffer("\(expression).vtable = \(valueEmission.expression).vtable;\n")
      default:
        expression = codeGen.nextTempWithInit(cType: codeGen.cTypeName(resultType), initExpr: "__koral_downgrade_ref(\(valueEmission.expression))")
      }
      emitCleanups(valueEmission.cleanups)
      return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: resultType))

    case .upgradeRef(let value, let resultType),
         .upgradeMutRef(let value, let resultType):
      let valueEmission = emitValue(value, sourceMode: true)
      let successVar = codeGen.nextTempWithDecl(cType: "int")
      let expression: String
      switch resolver.type(of: value) ?? .void {
      case .weakReference(let inner) where isTraitObjectType(inner),
           .mutableWeakReference(let inner) where isTraitObjectType(inner):
        let upgraded = codeGen.nextTempWithInit(cType: "struct __koral_Ref", initExpr: "__koral_upgrade_ref((struct __koral_WeakRef){\(valueEmission.expression).control}, &\(successVar))")
        expression = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(resultType))
        codeGen.addIndent()
        codeGen.appendToBuffer("if (\(successVar)) {\n")
        codeGen.withIndent {
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).tag = 1;\n")
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).data.Some.value.ptr = \(upgraded).ptr;\n")
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).data.Some.value.control = \(upgraded).control;\n")
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).data.Some.value.vtable = \(valueEmission.expression).vtable;\n")
        }
        codeGen.addIndent()
        codeGen.appendToBuffer("} else {\n")
        codeGen.withIndent {
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).tag = 0;\n")
        }
        codeGen.addIndent()
        codeGen.appendToBuffer("}\n")
      default:
        let upgraded = codeGen.nextTempWithInit(cType: "struct __koral_Ref", initExpr: "__koral_upgrade_ref(\(valueEmission.expression), &\(successVar))")
        expression = codeGen.nextTempWithDecl(cType: codeGen.cTypeName(resultType))
        codeGen.addIndent()
        codeGen.appendToBuffer("if (\(successVar)) {\n")
        codeGen.withIndent {
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).tag = 1;\n")
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).data.Some.value = \(upgraded);\n")
        }
        codeGen.addIndent()
        codeGen.appendToBuffer("} else {\n")
        codeGen.withIndent {
          codeGen.addIndent()
          codeGen.appendToBuffer("\(expression).tag = 0;\n")
        }
        codeGen.addIndent()
        codeGen.appendToBuffer("}\n")
      }
      emitCleanups(valueEmission.cleanups)
      return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: resultType))

    case .initMemory(let ptr, let value):
      let ptrEmission = emitValue(ptr, sourceMode: true)
      let valueEmission = emitValue(value, sourceMode: true)
      let elementType: Type
      switch resolver.type(of: ptr) ?? .void {
      case .pointer(let element), .mutablePointer(let element):
        elementType = element
      default:
        fatalError("init_memory expects pointer operand")
      }
      codeGen.appendCopyAssignment(
        for: elementType,
        source: valueEmission.expression,
        dest: "*(\(codeGen.cTypeName(elementType))*)\(ptrEmission.expression)",
        indent: codeGen.indent
      )
      consumeMovedSource(value)
      emitCleanups(ptrEmission.cleanups)
      emitCleanups(residualCleanups(for: valueEmission, consumedExpression: true))
      return MIRValueEmission(expression: "", cleanups: [])

    case .deinitMemory(let ptr):
      let ptrEmission = emitValue(ptr, sourceMode: true)
      let elementType: Type
      switch resolver.type(of: ptr) ?? .void {
      case .pointer(let element), .mutablePointer(let element):
        elementType = element
      default:
        fatalError("deinit_memory expects pointer operand")
      }
      let path = "*(\(codeGen.cTypeName(elementType))*)\(ptrEmission.expression)"
      codeGen.appendDropStatement(for: elementType, value: path, indent: codeGen.indent)
      emitCleanups(ptrEmission.cleanups)
      return MIRValueEmission(expression: "", cleanups: [])

    case .takeMemory(let ptr, let resultType):
      let ptrEmission = emitValue(ptr, sourceMode: true)
      let expression = codeGen.nextTempWithInit(cType: codeGen.cTypeName(resultType), initExpr: "*(\(codeGen.cTypeName(resultType))*)\(ptrEmission.expression)")
      emitCleanups(ptrEmission.cleanups)
      return MIRValueEmission(expression: expression, cleanups: cleanupForTemporaryResult(expression: expression, type: resultType))

    case .nullPtr(let resultType):
      let expression = codeGen.nextTempWithInit(cType: codeGen.cTypeName(resultType), initExpr: "NULL")
      return MIRValueEmission(expression: expression, cleanups: [])

    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      let outHandleEmission = emitValue(outHandle, sourceMode: true)
      let outTidEmission = emitValue(outTid, sourceMode: true)
      let closureEmission = emitValue(closure, sourceMode: true)
      let stackSizeEmission = emitValue(stackSize, sourceMode: true)
      let expression = codeGen.nextTempWithInit(
        cType: "int32_t",
        initExpr: "__koral_spawn_thread(\(outHandleEmission.expression), \(outTidEmission.expression), \(closureEmission.expression), \(stackSizeEmission.expression))"
      )
      emitCleanups(outHandleEmission.cleanups + outTidEmission.cleanups + closureEmission.cleanups + stackSizeEmission.cleanups)
      return MIRValueEmission(expression: expression, cleanups: [])
    }
  }

  private func emitMemoryTransfer(
    functionName: String,
    dest: MIRValue,
    source: MIRValue,
    count: MIRValue
  ) -> MIRValueEmission {
    let destEmission = emitValue(dest, sourceMode: true)
    let sourceEmission = emitValue(source, sourceMode: true)
    let countEmission = emitValue(count, sourceMode: true)
    let elementType: Type
    switch resolver.type(of: dest) ?? .void {
    case .pointer(let element), .mutablePointer(let element):
      elementType = element
    default:
      fatalError("memory transfer expects pointer destination")
    }
    codeGen.addIndent()
    codeGen.appendToBuffer(
      "\(functionName)(\(destEmission.expression), \(sourceEmission.expression), \(countEmission.expression) * sizeof(\(codeGen.cTypeName(elementType))));\n"
    )
    emitCleanups(destEmission.cleanups + sourceEmission.cleanups + countEmission.cleanups)
    return MIRValueEmission(expression: "", cleanups: [])
  }

  private func emitDirectCall(functionName: String, arguments: [String], returnType: Type) -> String {
    if returnType == .void || returnType == .never {
      codeGen.addIndent()
      codeGen.appendToBuffer("\(functionName)(\(arguments.joined(separator: ", ")));\n")
      return ""
    }
    return codeGen.nextTempWithInit(
      cType: codeGen.cTypeName(returnType),
      initExpr: "\(functionName)(\(arguments.joined(separator: ", ")) )".replacingOccurrences(of: " )", with: ")")
    )
  }

  private func emitClosureCall(
    closureExpr: String,
    parameters: [Parameter],
    returnType: Type,
    arguments: [String]
  ) -> String {
    let returnCType = codeGen.cTypeName(returnType)
    let noCaptureParams = parameters.map { codeGen.cTypeName($0.type) }.joined(separator: ", ")
    let noCaptureSignature = noCaptureParams.isEmpty ? "void" : noCaptureParams
    let withCaptureSignature = (["void*"] + parameters.map { codeGen.cTypeName($0.type) }).joined(separator: ", ")
    let args = arguments.joined(separator: ", ")
    let argsWithEnv = args.isEmpty ? "\(closureExpr).env" : "\(closureExpr).env, \(args)"

    if returnType == .void || returnType == .never {
      codeGen.addIndent()
      codeGen.appendToBuffer("if (\(closureExpr).env == NULL) {\n")
      codeGen.withIndent {
        codeGen.addIndent()
        codeGen.appendToBuffer("((\(returnCType) (*)(\(noCaptureSignature)))(\(closureExpr).fn))(\(args));\n")
      }
      codeGen.addIndent()
      codeGen.appendToBuffer("} else {\n")
      codeGen.withIndent {
        codeGen.addIndent()
        codeGen.appendToBuffer("((\(returnCType) (*)(\(withCaptureSignature)))(\(closureExpr).fn))(\(argsWithEnv));\n")
      }
      codeGen.addIndent()
      codeGen.appendToBuffer("}\n")
      return ""
    }

    let result = codeGen.nextTempWithDecl(cType: returnCType)
    codeGen.addIndent()
    codeGen.appendToBuffer("if (\(closureExpr).env == NULL) {\n")
    codeGen.withIndent {
      codeGen.addIndent()
      codeGen.appendToBuffer("\(result) = ((\(returnCType) (*)(\(noCaptureSignature)))(\(closureExpr).fn))(\(args));\n")
    }
    codeGen.addIndent()
    codeGen.appendToBuffer("} else {\n")
    codeGen.withIndent {
      codeGen.addIndent()
      codeGen.appendToBuffer("\(result) = ((\(returnCType) (*)(\(withCaptureSignature)))(\(closureExpr).fn))(\(argsWithEnv));\n")
    }
    codeGen.addIndent()
    codeGen.appendToBuffer("}\n")
    return result
  }

  private func emitPlaceAccess(_ place: MIRPlace) -> MIRPlaceAccess {
    switch place {
    case .local(let local):
      let name = localName(for: local)
      let type = resolver.type(of: place) ?? .void
      return MIRPlaceAccess(path: name, control: controlExpression(for: type, value: name), cleanups: [])
    case .global(let defId):
      let name = codeGen.cIdentifierByDefId[codeGen.defIdKey(defId)]
        ?? codeGen.context.getCIdentifier(defId)
        ?? sanitizeCIdentifier(codeGen.context.getName(defId) ?? "global_\(defId.id)")
      let type = resolver.type(of: place) ?? .void
      return MIRPlaceAccess(path: name, control: controlExpression(for: type, value: name), cleanups: [])
    case .field(let base, let field):
      let baseAccess = emitPlaceAccess(base)
      let baseType = resolver.type(of: base) ?? .void
      let memberName = sanitizeCIdentifier(codeGen.context.getName(field.defId) ?? "field")
      switch baseType {
      case .reference(let inner), .mutableReference(let inner):
        let path = "((\(codeGen.cTypeName(inner))*)\(baseAccess.path).ptr)->\(memberName)"
        return MIRPlaceAccess(path: path, control: "\(baseAccess.path).control", cleanups: baseAccess.cleanups)
      case .pointer, .mutablePointer:
        let path = "\(baseAccess.path)->\(memberName)"
        return MIRPlaceAccess(path: path, control: "NULL", cleanups: baseAccess.cleanups)
      default:
        let path = "\(baseAccess.path).\(memberName)"
        return MIRPlaceAccess(path: path, control: baseAccess.control, cleanups: baseAccess.cleanups)
      }
    case .enumPayload(let base, let caseName, let fieldName, _, _):
      let baseAccess = emitPlaceAccess(base)
      let path = "\(baseAccess.path).data.\(sanitizeCIdentifier(caseName)).\(sanitizeCIdentifier(fieldName))"
      return MIRPlaceAccess(path: path, control: baseAccess.control, cleanups: baseAccess.cleanups)
    case .deref(let base, let pointee):
      let baseEmission = emitValue(base, sourceMode: true)
      let baseType = resolver.type(of: base) ?? .void
      switch baseType {
      case .reference, .mutableReference:
        let path = "(*(\(codeGen.cTypeName(pointee))*)\(baseEmission.expression).ptr)"
        return MIRPlaceAccess(path: path, control: "\(baseEmission.expression).control", cleanups: baseEmission.cleanups)
      case .pointer, .mutablePointer:
        let path = "(*(\(codeGen.cTypeName(pointee))*)\(baseEmission.expression))"
        return MIRPlaceAccess(path: path, control: "NULL", cleanups: baseEmission.cleanups)
      default:
        fatalError("MIR deref base is not a reference or pointer: \(baseType)")
      }
    case .pointerElement(let base, let element):
      let baseEmission = emitValue(base, sourceMode: true)
      let path = "(*(\(codeGen.cTypeName(element))*)\(baseEmission.expression))"
      return MIRPlaceAccess(path: path, control: "NULL", cleanups: baseEmission.cleanups)
    }
  }

  private func emitScalarOrPointerCast(expression: String, sourceType: Type, targetType: Type) -> String {
    if sourceType == targetType {
      return expression
    }

    func isFloat(_ type: Type) -> Bool {
      switch type {
      case .float32, .float64:
        return true
      default:
        return false
      }
    }

    func isSignedInt(_ type: Type) -> Bool {
      switch type {
      case .int, .int8, .int16, .int32, .int64:
        return true
      default:
        return false
      }
    }

    func isUnsignedInt(_ type: Type) -> Bool {
      switch type {
      case .uint, .uint8, .uint16, .uint32, .uint64:
        return true
      default:
        return false
      }
    }

    func minMaxMacros(for type: Type) -> (String, String)? {
      switch type {
      case .int8: return ("INT8_MIN", "INT8_MAX")
      case .int16: return ("INT16_MIN", "INT16_MAX")
      case .int32: return ("INT32_MIN", "INT32_MAX")
      case .int64: return ("INT64_MIN", "INT64_MAX")
      case .int: return ("INTPTR_MIN", "INTPTR_MAX")
      case .uint8: return ("0", "UINT8_MAX")
      case .uint16: return ("0", "UINT16_MAX")
      case .uint32: return ("0", "UINT32_MAX")
      case .uint64: return ("0", "UINT64_MAX")
      case .uint: return ("0", "UINTPTR_MAX")
      default: return nil
      }
    }

    let targetCType = codeGen.cTypeName(targetType)
    if isFloat(sourceType) && (isSignedInt(targetType) || isUnsignedInt(targetType)), let (minMacro, maxMacro) = minMaxMacros(for: targetType) {
      let floatValue = codeGen.nextTempWithInit(cType: "double", initExpr: "(double)\(expression)")
      codeGen.addIndent()
      codeGen.appendToBuffer("if (!(\(floatValue) >= (double)\(minMacro) && \(floatValue) <= (double)\(maxMacro))) {\n")
      codeGen.withIndent {
        codeGen.addIndent()
        codeGen.appendToBuffer("__koral_panic_float_cast_overflow();\n")
      }
      codeGen.addIndent()
      codeGen.appendToBuffer("}\n")
      return codeGen.nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(floatValue)")
    }

    let targetIsPointer: Bool = {
      switch targetType {
      case .pointer, .mutablePointer:
        return true
      default:
        return false
      }
    }()

    let sourceIsPointer: Bool = {
      switch sourceType {
      case .pointer, .mutablePointer:
        return true
      default:
        return false
      }
    }()

    if targetIsPointer {
      switch sourceType {
      case .uint:
        return codeGen.nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))(uintptr_t)\(expression)")
      case .int:
        return codeGen.nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))(intptr_t)\(expression)")
      default:
        return codeGen.nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(expression)")
      }
    }

    if sourceIsPointer {
      return codeGen.nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(expression)")
    }

    return codeGen.nextTempWithInit(cType: targetCType, initExpr: "(\(targetCType))\(expression)")
  }

  private func emitOperandExpression(_ operand: MIROperand) -> String {
    switch operand {
    case .local(let local):
      return localName(for: local)
    case .function(let symbol):
      return codeGen.qualifiedName(for: symbol)
    case .constant(let constant):
      switch constant {
      case .integer(let value, _), .float(let value, _):
        return value
      case .boolean(let value):
        return value ? "1" : "0"
      case .void:
        return "0"
      case .string:
        fatalError("String constants must be materialized before direct operand emission")
      }
    }
  }

  private func emitGoto(_ block: MIRBlockID) {
    codeGen.addIndent()
    codeGen.appendToBuffer("goto \(label(for: block));\n")
  }

  private func label(for block: MIRBlockID) -> String {
    blockLabelByID[block] ?? "__mir_bb_\(block.rawValue)"
  }

  private func localName(for local: MIRLocalID) -> String {
    localNameByID[local] ?? "__mir_local_\(local.rawValue)"
  }

  private func emitCleanups(_ cleanups: [MIRValueCleanup]) {
    for cleanup in cleanups.reversed() {
      codeGen.appendDropStatement(for: cleanup.type, value: cleanup.name, indent: codeGen.indent)
    }
  }

  private func residualCleanups(for emission: MIRValueEmission, consumedExpression: Bool) -> [MIRValueCleanup] {
    guard consumedExpression else { return emission.cleanups }
    return emission.cleanups.filter { $0.name != emission.expression }
  }

  private func cleanupForTemporaryResult(expression: String, type: Type) -> [MIRValueCleanup] {
    guard !expression.isEmpty, codeGen.needsDrop(type) else { return [] }
    return [MIRValueCleanup(name: expression, type: type)]
  }

  private func shouldDropDiscardedValue(value: MIRValue, type: Type) -> Bool {
    guard codeGen.needsDrop(type) else { return false }
    switch value {
    case .placeRead(_, .borrow):
      return false
    default:
      return true
    }
  }

  private func localTargetID(for place: MIRPlace) -> MIRLocalID? {
    if case .local(let local) = place {
      return local
    }
    return nil
  }

  private func rootLocal(of place: MIRPlace) -> MIRLocalID? {
    switch place {
    case .local(let local):
      return local
    case .field(let base, _),
         .enumPayload(let base, _, _, _, _):
      return rootLocal(of: base)
    case .global,
         .deref,
         .pointerElement:
      return nil
    }
  }

  private func setInitFlag(_ local: MIRLocalID?, to value: Bool) {
    guard let local, let flag = initFlagByLocalID[local] else { return }
    codeGen.addIndent()
    codeGen.appendToBuffer("\(flag) = \(value ? "1" : "0");\n")
  }

  private func consumeMovedPlace(_ place: MIRPlace) {
    setInitFlag(rootLocal(of: place), to: false)
  }

  private func consumeMovedSource(_ value: MIRValue) {
    switch value {
    case .operand(.local(let local)):
      setInitFlag(local, to: false)
    case .placeRead(let place, let ownership):
      if ownership == .move {
        consumeMovedPlace(place)
      }
    case .cast(let operand, let targetType):
      let sourceType = resolver.type(of: operand) ?? targetType
      guard isOwnershipPreservingCast(sourceType: sourceType, targetType: targetType) else {
        break
      }
      if case .local(let local) = operand {
        setInitFlag(local, to: false)
      }
    default:
      break
    }
  }

  private func controlExpression(for type: Type, value: String) -> String {
    switch type {
    case .reference, .mutableReference, .weakReference, .mutableWeakReference, .traitObject:
      return "\(value).control"
    default:
      return "NULL"
    }
  }

  private func isTraitObjectType(_ type: Type) -> Bool {
    if case .traitObject = type {
      return true
    }
    return false
  }

  private func switchCaseExpression(_ constant: MIRConstant) -> String {
    switch constant {
    case .integer(let value, _):
      return value
    case .boolean(let value):
      return value ? "1" : "0"
    case .float, .string, .void:
      fatalError("Unsupported MIR switch constant in codegen: \(constant)")
    }
  }
}

extension CodeGen {
  func emitMIRFunctionBody(_ mirFunction: MIRFunction, localNameOverridesByDefId: [UInt64: String] = [:]) {
    let emitter = MIRFunctionCodeEmitter(
      codeGen: self,
      function: mirFunction,
      localNameOverridesByDefId: localNameOverridesByDefId
    )
    emitter.emitBody()
    if !emitter.generatedDefinitions.isEmpty {
      buffer = emitter.generatedDefinitions + buffer
    }
  }

  func generateMIRGlobalFunction(
    _ identifier: Symbol,
    _ params: [Symbol],
    _ mirFunction: MIRFunction
  ) {
    let cName = cIdentifier(for: identifier)
    let returnType = getFunctionReturnType(identifier.type)
    let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")

    let savedBuffer = buffer
    buffer = ""
    buffer += "\(returnType) \(cName)(\(paramList)) {\n"
    withIndent {
      emitMIRFunctionBody(mirFunction)
    }
    buffer += "}\n"

    let functionCode = buffer
    buffer = savedBuffer

    buffer += functionCode
  }
}
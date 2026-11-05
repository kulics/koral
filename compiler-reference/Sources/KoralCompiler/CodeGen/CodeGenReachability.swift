// CodeGenReachability.swift - prune unreachable functions before emission
//
// Mirrors `compiler/koralc/codegen/codegen_reachability.koral`: shrink
// `mirProgram.functions` to the reachable set so dead monomorphizations carry
// neither implementations nor declarations into the C output.
//
// Roots: user main, global initializers, Drop methods (the std Drop trait's
// declaration identity, with a `drop`/`*_drop*` name belt) and the witness of
// every requested vtable method. Edges: every function symbol named by a kept
// body -- calls, function values, capture sources, drop function pointers.
// Lambda bodies are nested definitions emitted with their host, so pruning the
// host prunes them too.
//
// Identity is the C symbol name, not the DefId: call sites carry instance
// identity and definitions carry declaration identity, and the two differ
// while still spelling one C symbol. A DefId index prunes definitions that
// are called.
//
// A missed root surfaces as a link error (the dangling scan only sees bare
// `name();` declarations); the differential oracle sees behavior changes.

extension CodeGen {
  /// Shrink `mirProgram.functions` to the reachable set, order preserved.
  func pruneUnreachableFunctions() {
    var byName: [String: [MIRFunction]] = [:]
    for function in mirProgram.functions {
      byName[cIdentifier(for: function.identifier), default: []].append(function)
    }

    var keep = Set<String>()
    var worklist: [String] = []
    let stdDropTrait = context.stdDropTraitDefId

    for function in mirProgram.functions {
      let declName = context.getName(function.identifier.defId) ?? ""
      let isRoot: Bool
      switch function.kind {
      case .given(_, let trait):
        // Drop implementations and derived drop glue must stay: the release
        // path hands out function pointers to them.
        var isDrop = Self.isDropGlueName(declName)
        if let trait, let stdDropTrait, trait.traitDefId == stdDropTrait {
          isDrop = true
        }
        isRoot = isDrop
      case .global:
        isRoot = declName == "main" || Self.isDropGlueName(declName)
      }
      if isRoot {
        noteFunction(function.identifier, &keep, &worklist)
      }
    }
    for global in mirProgram.globals {
      if case .globalVariable(_, let initializerFunction, _) = global {
        noteFunction(initializerFunction, &keep, &worklist)
      }
    }
    expandCallEdges(&keep, &worklist, byName)

    // Witness roots: the seed's vtable requests come from the .traitVTable
    // globals -- the exact source processVtableRequests() emits from. Resolve
    // each requested method through the same witness walk, so a witness the
    // vtable names can never be pruned out from under it.
    for global in mirProgram.globals {
      guard case .traitVTable(let vtable) = global else { continue }
      for method in vtable.methods {
        if let implDefId = resolveMethodDefIdFromWitness(
          concreteType: vtable.concreteType,
          traitName: vtable.traitName,
          traitDefId: vtable.traitDefId,
          traitTypeArgs: vtable.traitTypeArguments,
          traitMethodDefId: method.traitMethodDefId
        ), let symbol = emittedMethodSymbol(defId: implDefId) {
          noteFunction(symbol, &keep, &worklist)
        }
      }
    }
    expandCallEdges(&keep, &worklist, byName)

    mirProgram.functions = mirProgram.functions.filter {
      keep.contains(cIdentifier(for: $0.identifier))
    }
  }

  /// A drop method or derived drop glue shows up under three spellings:
  /// `drop` (the method name), `Type_drop` (derived glue) and `Type_drop_dNN`
  /// (after monomorphization). Match them all.
  private static func isDropGlueName(_ name: String) -> Bool {
    name == "drop" || name.contains("_drop")
  }

  private func noteFunction(
    _ identifier: Symbol,
    _ keep: inout Set<String>,
    _ worklist: inout [String]
  ) {
    let cName = cIdentifier(for: identifier)
    if !keep.contains(cName) {
      keep.insert(cName)
      worklist.append(cName)
    }
  }

  private func expandCallEdges(
    _ keep: inout Set<String>,
    _ worklist: inout [String],
    _ byName: [String: [MIRFunction]]
  ) {
    while let current = worklist.popLast() {
      guard let functions = byName[current] else { continue }
      for function in functions {
        var refs: [String] = []
        collectFunctionBodyRefs(function, &refs)
        for refName in refs where !keep.contains(refName) {
          keep.insert(refName)
          worklist.append(refName)
        }
      }
    }
  }

  // MARK: - Reference walkers

  private func collectOperandRefs(_ operand: MIROperand, _ out: inout [String]) {
    if case .function(let symbol) = operand {
      out.append(cIdentifier(for: symbol))
    }
  }

  private func collectPlaceRefs(_ place: MIRPlace, _ out: inout [String]) {
    switch place {
    case .local, .global:
      break
    case .field(let base, _), .enumPayload(let base, _, _, _, _):
      collectPlaceRefs(base, &out)
    case .deref(let base, _), .pointerElement(let base, _):
      collectValueRefs(base, &out)
    }
  }

  private func collectValueRefs(_ value: MIRValue, _ out: inout [String]) {
    switch value {
    case .operand(let operand):
      collectOperandRefs(operand, &out)
    case .placeRead(let place, _):
      collectPlaceRefs(place, &out)
    case .binary(let op):
      collectOperandRefs(op.left, &out)
      collectOperandRefs(op.right, &out)
    case .unary(let op):
      collectOperandRefs(op.operand, &out)
    case .call(let call):
      collectOperandRefs(call.callee, &out)
      for argument in call.arguments {
        collectValueRefs(argument, &out)
      }
    case .aggregate(let aggregate):
      for field in aggregate.fields {
        collectValueRefs(field, &out)
      }
    case .enumCase(let construction):
      for argument in construction.arguments {
        collectValueRefs(argument, &out)
      }
    case .enumTag(let tag):
      collectValueRefs(tag.subject, &out)
    case .traitObjectConversion(let conversion):
      collectValueRefs(conversion.inner, &out)
    case .traitMethodCall(let call):
      collectValueRefs(call.receiver, &out)
      for argument in call.arguments {
        collectValueRefs(argument, &out)
      }
    case .ref(let place, _, _), .pointer(let place):
      collectPlaceRefs(place, &out)
    case .cast(let operand, _, _):
      collectOperandRefs(operand, &out)
    case .intrinsic(let node):
      collectIntrinsicRefs(node, &out)
    case .lambda(let lambda):
      // The nested definition is emitted with its host; if the same body also
      // sits in the top-level list (it should not), keep it as well so the
      // output matches the unpruned one.
      out.append(cIdentifier(for: lambda.function.identifier))
      collectFunctionBodyRefs(lambda.function, &out)
    }
  }

  private func collectIntrinsicRefs(_ node: MIRIntrinsic, _ out: inout [String]) {
    switch node {
    case .allocMemory(let count, _), .allocString(let count, _):
      collectValueRefs(count, &out)
    case .deallocMemory(let ptr):
      collectValueRefs(ptr, &out)
    case .copyMemory(let dest, let source, let count),
         .moveMemory(let dest, let source, let count):
      collectValueRefs(dest, &out)
      collectValueRefs(source, &out)
      collectValueRefs(count, &out)
    case .downgradeRef(let value, _), .upgradeRef(let value, _):
      collectValueRefs(value, &out)
    case .traitObjectMatches(let value, _, _, _, _),
         .traitObjectDowncast(let value, _):
      collectValueRefs(value, &out)
    case .initMemory(let ptr, let value):
      collectValueRefs(ptr, &out)
      collectValueRefs(value, &out)
    case .deinitMemory(let ptr), .takeMemory(let ptr, _):
      collectValueRefs(ptr, &out)
    case .nullPtr:
      break
    case .fixedArrayLiteral(_, let elements):
      for element in elements {
        collectValueRefs(element, &out)
      }
    case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
      collectValueRefs(outHandle, &out)
      collectValueRefs(outTid, &out)
      collectValueRefs(closure, &out)
      collectValueRefs(stackSize, &out)
    }
  }

  private func collectStatementRefs(_ statement: MIRStatement, _ out: inout [String]) {
    switch statement {
    case .declare, .scopeEnter, .scopeExit, .debugSource:
      break
    case .assign(let place, let value):
      collectPlaceRefs(place, &out)
      collectValueRefs(value, &out)
    case .compoundAssign(let assignment):
      collectPlaceRefs(assignment.target, &out)
      collectValueRefs(assignment.value, &out)
    case .drop(let place):
      collectPlaceRefs(place, &out)
    case .retain(let value), .release(let value), .evaluate(let value):
      collectValueRefs(value, &out)
    }
  }

  private func collectTerminatorRefs(_ terminator: MIRTerminator, _ out: inout [String]) {
    switch terminator {
    case .goto, .unreachable:
      break
    case .branch(let condition, _, _):
      collectOperandRefs(condition, &out)
    case .switchValue(let operand, _, _):
      collectOperandRefs(operand, &out)
    case .returnValue(let operand):
      if let operand {
        collectOperandRefs(operand, &out)
      }
    }
  }

  /// Walk one function body (nested lambda bodies included) and append the C
  /// names of every function symbol it references.
  private func collectFunctionBodyRefs(_ function: MIRFunction, _ out: inout [String]) {
    for block in function.blocks {
      for statement in block.statements {
        collectStatementRefs(statement, &out)
      }
      collectTerminatorRefs(block.terminator, &out)
    }
  }
}

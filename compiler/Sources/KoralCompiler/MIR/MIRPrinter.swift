import Foundation

final class MIRPrinter {
  private let program: MIRProgram
  private var context: CompilerContext { program.context }

  init(program: MIRProgram) {
    self.program = program
  }

  func render() -> String {
    var lines: [String] = []
    lines.append("mir program globals=\(program.globals.count) functions=\(program.functions.count)")
    lines.append(renderSummaryLine())
    if let blockerLine = renderBlockerFunctionLine() {
      lines.append(blockerLine)
    }
    for global in program.globals.compactMap(renderTraitVTableGlobal) {
      lines.append(global)
    }
    for function in program.functions {
      lines.append(render(function))
    }
    return lines.joined(separator: "\n") + "\n"
  }

  func renderSummary() -> String {
    var lines = [
      "mir program globals=\(program.globals.count) functions=\(program.functions.count)",
      renderSummaryLine()
    ]
    if let blockerLine = renderBlockerFunctionLine() {
      lines.append(blockerLine)
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func renderSummaryLine() -> String {
    let stats = MIRStatsCollector.collect(program)
    return "mir stats blocks=\(stats.blockCount) locals=\(stats.localCount) statements=\(stats.statementCount) terminators=\(stats.terminatorCount) values=\(stats.valueCount) calls=\(stats.callCount) aggregates=\(stats.aggregateCount) enums=\(stats.enumConstructionCount) vtables=\(stats.traitVTableCount) branches=\(stats.branchTerminatorCount) switches=\(stats.switchTerminatorCount) fully_structured_functions=\(stats.fullyStructuredFunctionCount)/\(stats.functionCount) mir_codegen_candidates=\(stats.mirCodeGenCandidateFunctionCount)/\(stats.functionCount) mir_codegen_blockers=\(stats.mirCodeGenBlockerCount) mir_codegen_blocker_kinds=\(renderCounts(stats.mirCodeGenBlockerKinds))"
  }

  private func renderCounts(_ counts: [String: Int]) -> String {
    if counts.isEmpty { return "none" }
    return counts
      .sorted { lhs, rhs in
        if lhs.value == rhs.value { return lhs.key < rhs.key }
        return lhs.value > rhs.value
      }
      .map { "\($0.key):\($0.value)" }
      .joined(separator: ",")
  }

  private func renderBlockerFunctionLine(limit: Int = 12) -> String? {
    let stats = MIRStatsCollector.collect(program)
    let blockerFunctions = zip(program.functions, stats.functionStats)
      .filter { $0.1.mirCodeGenBlockerCount > 0 }
      .sorted { lhs, rhs in
        if lhs.1.mirCodeGenBlockerCount == rhs.1.mirCodeGenBlockerCount {
          return renderFunctionName(lhs.0) < renderFunctionName(rhs.0)
        }
        return lhs.1.mirCodeGenBlockerCount > rhs.1.mirCodeGenBlockerCount
      }
      .prefix(limit)

    if blockerFunctions.isEmpty { return nil }
    let rendered = blockerFunctions.map { function, functionStats in
      "\(renderFunctionName(function)):\(functionStats.mirCodeGenBlockerCount)[\(renderCounts(functionStats.mirCodeGenBlockerKinds))]"
    }.joined(separator: " ")
    return "mir blocker_functions \(rendered)"
  }

  private func renderFunctionName(_ function: MIRFunction) -> String {
    context.getQualifiedName(function.identifier.defId)
      ?? context.getName(function.identifier.defId)
      ?? "def#\(function.identifier.defId.id)"
  }

  private func renderTraitVTableGlobal(_ global: MIRGlobal) -> String? {
    guard case .traitVTable(let vtable) = global else { return nil }
    return "vtable \(renderTraitName(vtable.traitName, vtable.traitTypeArguments)) for \(context.getDebugName(vtable.concreteType))"
  }

  private func render(_ function: MIRFunction) -> String {
    var lines: [String] = []
    let name = renderFunctionName(function)
    lines.append("func \(name)(\(renderParameters(function.parameters))) -> \(context.getDebugName(function.returnType)) [\(renderKind(function.kind))] {")
    for local in function.locals {
      lines.append("  local \(local.id) \(local.name): \(context.getDebugName(local.type)) [\(renderStorage(local.storage))]")
    }
    for block in function.blocks {
      lines.append("  \(block.id):")
      for statement in block.statements {
        lines.append("    \(renderStatement(statement))")
      }
      lines.append("    \(renderTerminator(block.terminator))")
    }
    lines.append("}")
    return lines.joined(separator: "\n")
  }

  private func renderParameters(_ parameters: [Symbol]) -> String {
    parameters.map { parameter in
      let name = context.getName(parameter.defId) ?? "param_\(parameter.defId.id)"
      return "\(name): \(context.getDebugName(parameter.type))"
    }.joined(separator: ", ")
  }

  private func renderKind(_ kind: MIRFunctionKind) -> String {
    switch kind {
    case .global:
      return "global"
    case .given(let type, let trait):
      if let trait {
        return "given \(context.getDebugName(type)) as \(trait.traitName)"
      }
      return "given \(context.getDebugName(type))"
    }
  }

  private func renderStorage(_ storage: MIRStorage) -> String {
    switch storage {
    case .parameter: return "parameter"
    case .capture: return "capture"
    case .local: return "local"
    case .temporary: return "temporary"
    }
  }

  private func renderStatement(_ statement: MIRStatement) -> String {
    switch statement {
    case .declare(let local):
      return "declare \(local)"
    case .assign(let place, let value):
      return "assign \(renderPlace(place)), \(renderValue(value))"
    case .compoundAssign(let assignment):
      return "compound_assign[\(renderCompoundAssignmentOperator(assignment.operatorKind))] \(renderPlace(assignment.target)), \(renderValue(assignment.value))"
    case .drop(let place):
      return "drop \(renderPlace(place))"
    case .retain(let value):
      return "retain \(renderValue(value))"
    case .release(let value):
      return "release \(renderValue(value))"
    case .evaluate(let value):
      return "evaluate \(renderValue(value))"
    case .scopeEnter(let scope):
      return "scope_enter \(scope)"
    case .scopeExit(let scope):
      return "scope_exit \(scope)"
    case .debugSource(let span):
      return "debug_source \(span)"
    }
  }

  private func renderTerminator(_ terminator: MIRTerminator) -> String {
    switch terminator {
    case .goto(let target):
      return "goto \(target)"
    case .branch(let condition, let thenBlock, let elseBlock):
      return "branch \(renderOperand(condition)), \(thenBlock), \(elseBlock)"
    case .switchValue(let operand, let cases, let defaultBlock):
      let renderedCases = cases.map { "\(renderConstant($0.value)): \($0.target)" }.joined(separator: ", ")
      if let defaultBlock {
        return "switch \(renderOperand(operand)) [\(renderedCases)] default \(defaultBlock)"
      }
      return "switch \(renderOperand(operand)) [\(renderedCases)]"
    case .returnValue(let operand):
      if let operand {
        return "return \(renderOperand(operand))"
      }
      return "return"
    case .unreachable:
      return "unreachable"
    }
  }

  private func renderValue(_ value: MIRValue) -> String {
    switch value {
    case .operand(let operand):
      return renderOperand(operand)
    case .placeRead(let place, let ownership):
      return "read[\(ownership)] \(renderPlace(place))"
    case .binary(let operation):
      return "binary[\(renderBinaryOperator(operation.operatorKind))] \(renderOperand(operation.left)), \(renderOperand(operation.right)): \(context.getDebugName(operation.type))"
    case .unary(let operation):
      return "unary[\(renderUnaryOperator(operation.operatorKind))] \(renderOperand(operation.operand)): \(context.getDebugName(operation.type))"
    case .call(let call):
      let arguments = call.arguments.map(renderValue).joined(separator: ", ")
      return "call[args=\(renderOwnerships(call.argumentOwnerships))] \(renderOperand(call.callee))(\(arguments)): \(context.getDebugName(call.type))"
    case .aggregate(let aggregate):
      return "aggregate \(context.getDebugName(aggregate.type))"
    case .enumCase(let construction):
      return "enum \(context.getDebugName(construction.type)).\(construction.caseName)"
    case .enumTag(let tag):
      return "enum_tag \(renderValue(tag.subject)): \(context.getDebugName(tag.enumType))"
    case .traitObjectConversion(let conversion):
      return "trait_object_conversion[\(conversion.sourceOwnership)] \(renderTraitName(conversion.traitName, conversion.traitTypeArguments)) inner=\(renderValue(conversion.inner)) concrete=\(context.getDebugName(conversion.concreteType)): \(context.getDebugName(conversion.type))"
    case .traitMethodCall(let call):
      return "trait_call[receiver=\(call.receiverOwnership), args=\(renderOwnerships(call.argumentOwnerships))] \(renderTraitName(call.traitName, call.traitTypeArguments)).\(call.methodName) receiver=\(renderValue(call.receiver))(\(call.arguments.map(renderValue).joined(separator: ", "))): \(context.getDebugName(call.type))"
    case .ref(_, let kind, let allocation):
      return "ref[\(kind), \(allocation)]"
    case .pointer(let place):
      return "ptr \(renderPlace(place))"
    case .cast(let operand, let type):
      return "cast \(renderOperand(operand)) to \(context.getDebugName(type))"
    case .intrinsic:
      return "intrinsic"
    case .lambda(let lambda):
      return "lambda params=\(lambda.parameters.count) captures=\(lambda.captures.count): \(context.getDebugName(lambda.type))"
    }
  }

  private func renderOperand(_ operand: MIROperand) -> String {
    switch operand {
    case .local(let local):
      return "\(local)"
    case .constant(let constant):
      return renderConstant(constant)
    case .function(let symbol):
      return context.getQualifiedName(symbol.defId)
        ?? context.getName(symbol.defId)
        ?? "def#\(symbol.defId.id)"
    }
  }

  private func renderOwnerships(_ ownerships: [MIROwnershipUse]) -> String {
    if ownerships.isEmpty { return "none" }
    return ownerships.map { "\($0)" }.joined(separator: ",")
  }

  private func renderPlace(_ place: MIRPlace) -> String {
    switch place {
    case .local(let local):
      return "\(local)"
    case .global(let defId):
      return context.getQualifiedName(defId) ?? context.getName(defId) ?? "def#\(defId.id)"
    case .field(let base, let field):
      let fieldName = context.getName(field.defId) ?? "field_\(field.defId.id)"
      return "\(renderPlace(base)).\(fieldName)"
    case .enumPayload(let base, let caseName, let fieldName, let fieldIndex, _):
      return "\(renderPlace(base)).\(caseName).\(fieldName)#\(fieldIndex)"
    case .deref(_, let pointee):
      return "deref \(context.getDebugName(pointee))"
    case .pointerElement(_, let element):
      return "element \(context.getDebugName(element))"
    }
  }

  private func renderConstant(_ constant: MIRConstant) -> String {
    switch constant {
    case .integer(let value, let type):
      return "\(value):\(context.getDebugName(type))"
    case .float(let value, let type):
      return "\(value):\(context.getDebugName(type))"
    case .string(let value, _):
      return "\"\(value)\""
    case .boolean(let value):
      return value ? "true" : "false"
    case .void:
      return "void"
    }
  }

  private func renderBinaryOperator(_ operatorKind: MIRBinaryOperator) -> String {
    switch operatorKind {
    case .arithmetic(let op, let checked):
      return checked ? "checked_\(renderArithmeticOperator(op))" : renderArithmeticOperator(op)
    case .wrappingArithmetic(let op):
      return "wrapping_\(renderArithmeticOperator(op))"
    case .comparison(let op):
      return renderComparisonOperator(op)
    case .logicalAnd:
      return "logical_and"
    case .logicalOr:
      return "logical_or"
    case .bitwise(let op, let checkedShift):
      return checkedShift ? "checked_\(renderBitwiseOperator(op))" : renderBitwiseOperator(op)
    case .wrappingShift(let op):
      return "wrapping_\(renderBitwiseOperator(op))"
    }
  }

  private func renderUnaryOperator(_ operatorKind: MIRUnaryOperator) -> String {
    switch operatorKind {
    case .logicalNot:
      return "not"
    case .bitwiseNot:
      return "bitwise_not"
    }
  }

  private func renderCompoundAssignmentOperator(_ op: CompoundAssignmentOperator) -> String {
    switch op {
    case .plus: return "add"
    case .minus: return "sub"
    case .multiply: return "mul"
    case .divide: return "div"
    case .remainder: return "rem"
    case .bitwiseAnd: return "bit_and"
    case .bitwiseOr: return "bit_or"
    case .bitwiseXor: return "bit_xor"
    case .shiftLeft: return "shl"
    case .shiftRight: return "shr"
    }
  }

  private func renderArithmeticOperator(_ op: ArithmeticOperator) -> String {
    switch op {
    case .plus: return "add"
    case .minus: return "sub"
    case .multiply: return "mul"
    case .divide: return "div"
    case .remainder: return "rem"
    }
  }

  private func renderComparisonOperator(_ op: ComparisonOperator) -> String {
    switch op {
    case .equal: return "eq"
    case .notEqual: return "ne"
    case .greater: return "gt"
    case .less: return "lt"
    case .greaterEqual: return "ge"
    case .lessEqual: return "le"
    }
  }

  private func renderBitwiseOperator(_ op: BitwiseOperator) -> String {
    switch op {
    case .and: return "bit_and"
    case .or: return "bit_or"
    case .xor: return "bit_xor"
    case .shiftLeft: return "shl"
    case .shiftRight: return "shr"
    }
  }

  private func renderTraitName(_ traitName: String, _ typeArguments: [Type]) -> String {
    guard !typeArguments.isEmpty else { return traitName }
    return "\(traitName)<\(typeArguments.map { context.getDebugName($0) }.joined(separator: ", "))>"
  }
}

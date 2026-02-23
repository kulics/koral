// MARK: - Expression Code Generation Helper Extension

extension CodeGen {
  
  // MARK: - Operator Conversion Methods
  
  func arithmeticOpToC(_ op: ArithmeticOperator) -> String {
    switch op {
    case .plus: return "+"
    case .minus: return "-"
    case .multiply: return "*"
    case .divide: return "/"
    case .modulo: return "%"
    }
  }

  func comparisonOpToC(_ op: ComparisonOperator) -> String {
    switch op {
    case .equal: return "=="
    case .notEqual: return "!="
    case .greater: return ">"
    case .less: return "<"
    case .greaterEqual: return ">="
    case .lessEqual: return "<="
    }
  }

  func bitwiseOpToC(_ op: BitwiseOperator) -> String {
    switch op {
    case .and: return "&"
    case .or: return "|"
    case .xor: return "^"
    case .shiftLeft: return "<<"
    case .shiftRight: return ">>"
    }
  }

  func compoundOpToC(_ op: CompoundAssignmentOperator) -> String {
    switch op {
    case .plus: return "+="
    case .minus: return "-="
    case .multiply: return "*="
    case .divide: return "/="
    case .modulo: return "%="
    case .bitwiseAnd: return "&="
    case .bitwiseOr: return "|="
    case .bitwiseXor: return "^="
    case .shiftLeft: return "<<="
    case .shiftRight: return ">>="
    }
  }

  // MARK: - Checked Arithmetic Helpers

  func checkedArithmeticFuncName(op: ArithmeticOperator, type: Type) -> String {
    let opName: String
    switch op {
    case .plus: opName = "add"
    case .minus: opName = "sub"
    case .multiply: opName = "mul"
    case .divide: opName = "div"
    case .modulo: opName = "mod"
    }
    return "koral_checked_\(opName)_\(typeSuffix(type))"
  }

  func checkedShiftFuncName(op: BitwiseOperator, type: Type) -> String {
    let opName: String
    switch op {
    case .shiftLeft: opName = "shl"
    case .shiftRight: opName = "shr"
    default: fatalError("Not a shift operation: \(op)")
    }
    return "koral_checked_\(opName)_\(typeSuffix(type))"
  }

  func wrappingArithmeticFuncName(op: ArithmeticOperator, type: Type) -> String {
    let opName: String
    switch op {
    case .plus: opName = "add"
    case .minus: opName = "sub"
    case .multiply: opName = "mul"
    case .divide: opName = "div"
    case .modulo: opName = "mod"
    }
    return "koral_wrapping_\(opName)_\(typeSuffix(type))"
  }

  func wrappingShiftFuncName(op: BitwiseOperator, type: Type) -> String {
    let opName: String
    switch op {
    case .shiftLeft: opName = "shl"
    case .shiftRight: opName = "shr"
    default: fatalError("Not a shift operation: \(op)")
    }
    return "koral_wrapping_\(opName)_\(typeSuffix(type))"
  }

  func typeSuffix(_ type: Type) -> String {
    switch type {
    case .int: return "isize"
    case .int8: return "i8"
    case .int16: return "i16"
    case .int32: return "i32"
    case .int64: return "i64"
    case .uint: return "usize"
    case .uint8: return "u8"
    case .uint16: return "u16"
    case .uint32: return "u32"
    case .uint64: return "u64"
    default: fatalError("Not an integer type: \(type)")
    }
  }

  // MARK: - Reference Component Building
  
  /// Build reference components: returns (access path, control block pointer)
  func buildRefComponents(_ expr: TypedExpressionNode) -> (path: String, control: String) {
    switch expr {
    case .variable(let identifier):
      // Lambda capture aliases — captured variables accessed through env pointer
      if let alias = capturedVarAliases[identifier.defId.id] {
        if case .reference(_) = identifier.type {
          return (alias, "(\(alias)).control")
        }
        return (alias, "NULL")
      }
      let cName = cIdentifier(for: identifier)
      let path = patternBindingAliases[cName] ?? cName
      if case .reference(_) = identifier.type {
        return (path, "(\(path)).control")
      }
      return (path, "NULL")
    case .memberPath(let source, let path):
      var (basePath, baseControl) = buildRefComponents(source)
      var curType = source.type

      for member in path {
        if case .reference(let inner) = curType {
          // Dereferencing a ref type updates the control block
          baseControl = "\(basePath).control"
          let innerCType = cTypeName(inner)
          let memberName = sanitizeCIdentifier(context.getName(member.defId) ?? "<unknown>")
          basePath = "((\(innerCType)*)\(basePath).ptr)->\(memberName)"
        } else if case .pointer = curType {
          let memberName = sanitizeCIdentifier(context.getName(member.defId) ?? "<unknown>")
          basePath = "\(basePath)->\(memberName)"
        } else {
          // Accessing member of value type keeps the same control block
          let memberName = sanitizeCIdentifier(context.getName(member.defId) ?? "<unknown>")
          basePath += ".\(memberName)"
        }
        curType = member.type
      }
      return (basePath, baseControl)
    case .subscriptExpression(let base, let args, let method, let type):
         guard case .function(_, let returns) = method.type else { fatalError() }
         let callNode = TypedExpressionNode.call(
             callee: .methodReference(base: base, method: method, typeArgs: nil, methodTypeArgs: nil, type: method.type),
             arguments: args,
             type: returns)
         let refResult = generateExpressionSSA(callNode)
         
         if case .reference(_) = type {
             return (refResult, "\(refResult).control")
         } else {
             return (refResult, "NULL")
         }

    case .derefExpression(let inner, let type):
         // Dereferencing a reference type gives us an LValue
         let refResult = generateExpressionSSA(inner)
         let cType = cTypeName(type)
         let path = "(*(\(cType)*)\(refResult).ptr)"
         let control = "\(refResult).control"
         return (path, control)
         
    default:
      fatalError("ref requires lvalue (variable or memberAccess)")
    }
  }
  
  // MARK: - Member Path Generation
  
  func generateMemberPath(_ source: TypedExpressionNode, _ path: [Symbol]) -> String {
    let sourceResult = generateExpressionSSA(source)
    var access = sourceResult
    var curType = source.type
    for member in path {
      var memberAccess: String
      let memberName = sanitizeCIdentifier(context.getName(member.defId) ?? "<unknown>")
      if case .reference(let inner) = curType {
        let innerCType = cTypeName(inner)
        memberAccess = "((\(innerCType)*)\(access).ptr)->\(memberName)"
      } else if case .pointer = curType {
        memberAccess = "\(access)->\(memberName)"
      } else {
        memberAccess = "\(access).\(memberName)"
      }
      
      // Only apply type cast for non-reference struct members when the C types differ
      // This handles cases where generic type parameters are replaced with concrete types
      // but the C representation needs explicit casting
      if case .structure(let defId) = curType.canonical,
        let canonicalMembers = context.getStructMembers(defId) {
          let memberName = context.getName(member.defId) ?? "<unknown>"
          if let canonicalMember = canonicalMembers.first(where: { $0.name == memberName }) {
          // Compare C type representations instead of Type equality
          // This avoids issues with UUID-based type identity for generic instantiations
          let canonicalCType = cTypeName(canonicalMember.type)
          let memberCType = cTypeName(member.type)
          if canonicalCType != memberCType {
            // Skip cast for reference types - they all use struct Ref
            if case .reference(_) = member.type {
              // No cast needed for reference types
            } else {
              let targetCType = cTypeName(member.type)
              memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
            }
          }
        }
      }
      
      access = memberAccess
      curType = member.type
    }
    let cType = cTypeName(path.last?.type ?? .void)
    let result = nextTempWithInit(cType: cType, initExpr: access)
    return result
  }
  
  // MARK: - Block Scope Generation
  
  func generateBlockScope(
    _ statements: [TypedStatementNode]
  ) -> String {
    pushScope()
    // Process all statements, handling yield specially
    var result = ""
    for stmt in statements {
      if case .yield(let value) = stmt {
        // yield expression becomes the block's value
        let temp = generateExpressionSSA(value)
        if value.type != .void && value.type != .never {
          let cType = cTypeName(value.type)
          let resultVar = nextTempWithDecl(cType: cType)
          if value.valueCategory == .lvalue {
            // Returning an lvalue from a block:
            // - Copy types must be copied, because scope cleanup will drop the original.
            appendCopyAssignment(for: value.type, source: temp, dest: resultVar, indent: indent)
          } else {
            addIndent()
            appendToBuffer("\(resultVar) = \(temp);\n")
          }
          result = resultVar
        }
      } else {
        generateStatement(stmt)
      }
    }
    popScope()
    return result
  }
  
  // MARK: - Function Call Generation
  
  func generateCall(
    _ callee: TypedExpressionNode, _ arguments: [TypedExpressionNode], _ type: Type
  ) -> String {
    if case .methodReference(let base, let method, _, _, _) = callee {
      var allArgs = [base]
      allArgs.append(contentsOf: arguments)
      return generateFunctionCall(method, allArgs, type)
    }

    // Handle trait method placeholder calls
    if case .traitMethodPlaceholder(let traitName, let methodName, let base, _, _) = callee {
      fatalError("Unresolved trait method placeholder: \(traitName).\(methodName) on \(base.type)")
    }

    if case .variable(let identifier) = callee {
      // Check if this is a function type variable (closure call)
      // Regular functions have kind = .function, while closure variables have kind = .variable
      if case .variable(_) = identifier.kind,
         case .function(let funcParams, let returnType) = identifier.type {
        return generateClosureCall(
          closureVar: qualifiedName(for: identifier),
          funcParams: funcParams,
          returnType: returnType,
          arguments: arguments
        )
      }
      return generateFunctionCall(identifier, arguments, type)
    }

    // Handle indirect call through expression (e.g., lambda expression result)
    if case .function(let funcParams, let returnType) = callee.type {
      let closureResult = generateExpressionSSA(callee)
      return generateClosureCall(
        closureVar: closureResult,
        funcParams: funcParams,
        returnType: returnType,
        arguments: arguments
      )
    }

    fatalError("Indirect call not supported: callee type = \(callee.type)")
  }

  
  /// Generates code for calling a closure (function type variable)
  /// Handles both no-capture (env == NULL) and with-capture (env != NULL) cases
  func generateClosureCall(
    closureVar: String,
    funcParams: [Parameter],
    returnType: Type,
    arguments: [TypedExpressionNode]
  ) -> String {
    // Generate argument values
    var argResults: [String] = []
    for arg in arguments {
      let result = generateExpressionSSA(arg)
      if arg.valueCategory == .lvalue {
        let cType = cTypeName(arg.type)
        let copyResult = nextTempWithDecl(cType: cType)
        appendCopyAssignment(for: arg.type, source: result, dest: copyResult, indent: indent)
        argResults.append(copyResult)
      } else {
        argResults.append(result)
      }
    }
    
    let returnCType = cTypeName(returnType)
    
    // Build function pointer type for no-capture case: ReturnType (*)(Args...)
    var noCaptureParamTypes: [String] = []
    for param in funcParams {
      noCaptureParamTypes.append(cTypeName(param.type))
    }
    let noCaptureParamsStr = noCaptureParamTypes.isEmpty ? "void" : noCaptureParamTypes.joined(separator: ", ")
    let noCaptureFnPtrType = "\(returnCType) (*)(\(noCaptureParamsStr))"
    
    // Build function pointer type for with-capture case: ReturnType (*)(void*, Args...)
    var withCaptureParamTypes: [String] = ["void*"]
    for param in funcParams {
      withCaptureParamTypes.append(cTypeName(param.type))
    }
    let withCaptureParamsStr = withCaptureParamTypes.joined(separator: ", ")
    let withCaptureFnPtrType = "\(returnCType) (*)(\(withCaptureParamsStr))"
    
    // Build argument list strings
    let argsStr = argResults.joined(separator: ", ")
    let argsWithEnvStr = argResults.isEmpty ? "\(closureVar).env" : "\(closureVar).env, \(argsStr)"
    
    // Generate conditional call based on env == NULL
    if returnType == .void || returnType == .never {
      addIndent()
      appendToBuffer("if (\(closureVar).env == NULL) {\n")
      indent += "  "
      addIndent()
      appendToBuffer("((\(noCaptureFnPtrType))(\(closureVar).fn))(\(argsStr));\n")
      indent = String(indent.dropLast(2))
      addIndent()
      appendToBuffer("} else {\n")
      indent += "  "
      addIndent()
      appendToBuffer("((\(withCaptureFnPtrType))(\(closureVar).fn))(\(argsWithEnvStr));\n")
      indent = String(indent.dropLast(2))
      addIndent()
      appendToBuffer("}\n")
      return ""
    } else {
      let result = nextTempWithDecl(cType: returnCType)
      addIndent()
      appendToBuffer("if (\(closureVar).env == NULL) {\n")
      indent += "  "
      addIndent()
      appendToBuffer("\(result) = ((\(noCaptureFnPtrType))(\(closureVar).fn))(\(argsStr));\n")
      indent = String(indent.dropLast(2))
      addIndent()
      appendToBuffer("} else {\n")
      indent += "  "
      addIndent()
      appendToBuffer("\(result) = ((\(withCaptureFnPtrType))(\(closureVar).fn))(\(argsWithEnvStr));\n")
      indent = String(indent.dropLast(2))
      addIndent()
      appendToBuffer("}\n")
      return result
    }
  }

  func generateFunctionCall(
    _ identifier: Symbol, _ arguments: [TypedExpressionNode], _ type: Type
  ) -> String {
    var paramResults: [String] = []
    // struct/union类型参数传递用值，isValue==false 的参数自动递归 copy
    for arg in arguments {
      let result = generateExpressionSSA(arg)
      if arg.valueCategory == .lvalue {
        let cType = cTypeName(arg.type)
        let copyResult = nextTempWithDecl(cType: cType)
        appendCopyAssignment(for: arg.type, source: result, dest: copyResult, indent: indent)
        paramResults.append(copyResult)
      } else {
        paramResults.append(result)
      }
    }
    
    addIndent()
    if type == .void || type == .never {
      appendToBuffer("\(qualifiedName(for: identifier))(")
      appendToBuffer(paramResults.joined(separator: ", "))
      appendToBuffer(");\n")
      return ""
    } else {
      let cType = cTypeName(type)
      let result = nextTempWithInit(cType: cType, initExpr: "\(qualifiedName(for: identifier))(\(paramResults.joined(separator: ", ")))")
      return result
    }
  }
  
  // MARK: - Assignment Generation
  
  func generateAssignment(_ identifier: Symbol, _ value: TypedExpressionNode) {
    if value.type == .void || value.type == .never {
      _ = generateExpressionSSA(value)
      return
    }
    let valueResult = generateExpressionSSA(value)
    if value.valueCategory == .lvalue {
      let copyResult = nextTempWithDecl(cType: cTypeName(value.type))
      appendCopyAssignment(for: value.type, source: valueResult, dest: copyResult, indent: indent)
      addIndent()
      appendDropStatement(for: identifier.type, value: qualifiedName(for: identifier), indent: "")
      addIndent()
      appendToBuffer("\(qualifiedName(for: identifier)) = \(copyResult);\n")
    } else {
      addIndent()
      appendDropStatement(for: identifier.type, value: qualifiedName(for: identifier), indent: "")
      addIndent()
      appendToBuffer("\(qualifiedName(for: identifier)) = \(valueResult);\n")
    }
  }

  func generateMemberAccessAssignment(
    _ base: Symbol,
    _ memberPath: [Symbol], _ value: TypedExpressionNode
  ) {
    if value.type == .void || value.type == .never {
      _ = generateExpressionSSA(value)
      return
    }
    let baseResult = qualifiedName(for: base)
    let valueResult = generateExpressionSSA(value)
    var accessPath = baseResult
    var curType = base.type
    for (index, item) in memberPath.enumerated() {
      let isLast = index == memberPath.count - 1
      let memberLookupName = context.getName(item.defId) ?? "<unknown>"
      let memberName = sanitizeCIdentifier(memberLookupName)
      let memberType = item.type
      
      var memberAccess: String
      if case .reference(let inner) = curType {
          let innerCType = cTypeName(inner)
          memberAccess = "((\(innerCType)*)\(accessPath).ptr)->\(memberName)"
      } else {
          memberAccess = "\(accessPath).\(memberName)"
      }
      
      // Only apply type cast for non-reference struct members when the C types differ
      if case .structure(let defId) = curType.canonical,
        let canonicalMembers = context.getStructMembers(defId),
         let canonicalMember = canonicalMembers.first(where: { $0.name == memberLookupName }) {
          let canonicalCType = cTypeName(canonicalMember.type)
          let memberCTypeStr = cTypeName(memberType)
          if canonicalCType != memberCTypeStr {
            if case .reference(_) = memberType {
              // No cast needed for reference types
            } else {
              let targetCType = cTypeName(memberType)
              memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
            }
          }
      }
      
      accessPath = memberAccess
      curType = memberType
      
      if isLast {
        if value.valueCategory == .lvalue {
          let copyResult = nextTempWithDecl(cType: cTypeName(value.type))
          appendCopyAssignment(for: value.type, source: valueResult, dest: copyResult, indent: indent)
          addIndent()
          appendDropStatement(for: memberType, value: accessPath, indent: "")
          addIndent()
          appendToBuffer("\(accessPath) = \(copyResult);\n")
        } else {
          addIndent()
          appendDropStatement(for: memberType, value: accessPath, indent: "")
          addIndent()
          appendToBuffer("\(accessPath) = \(valueResult);\n")
        }
        return
      }
    }
    addIndent()
    appendToBuffer("\(accessPath) = \(valueResult);\n")
  }
}

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
    case .power: return "**"  // Special handling needed
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
    case .power: return "**="  // Special handling needed
    case .bitwiseAnd: return "&="
    case .bitwiseOr: return "|="
    case .bitwiseXor: return "^="
    case .shiftLeft: return "<<="
    case .shiftRight: return ">>="
    }
  }
  
  // MARK: - Reference Component Building
  
  /// Build reference components: returns (access path, control block pointer)
  func buildRefComponents(_ expr: TypedExpressionNode) -> (path: String, control: String) {
    switch expr {
    case .variable(let identifier):
      let path = identifier.qualifiedName
      if case .reference(_) = identifier.type {
        return (path, "\(path).control")
      } else {
        return (path, "NULL")
      }
    case .memberPath(let source, let path):
      var (basePath, baseControl) = buildRefComponents(source)
      var curType = source.type

      for member in path {
        if case .reference(let inner) = curType {
          // Dereferencing a ref type updates the control block
          baseControl = "\(basePath).control"
          let innerCType = getCType(inner)
          basePath = "((\(innerCType)*)\(basePath).ptr)->\(member.qualifiedName)"
        } else {
          // Accessing member of value type keeps the same control block
          basePath += ".\(member.qualifiedName)"
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
         let cType = getCType(type)
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
      if case .reference(let inner) = curType {
          let innerCType = getCType(inner)
          memberAccess = "((\(innerCType)*)\(access).ptr)->\(member.qualifiedName)"
      } else {
          memberAccess = "\(access).\(member.qualifiedName)"
      }
      
      // Only apply type cast for non-reference struct members when the C types differ
      // This handles cases where generic type parameters are replaced with concrete types
      // but the C representation needs explicit casting
      if case .structure(let decl) = curType.canonical {
        if let canonicalMember = decl.members.first(where: { $0.name == member.name }) {
          // Compare C type representations instead of Type equality
          // This avoids issues with UUID-based type identity for generic instantiations
          let canonicalCType = getCType(canonicalMember.type)
          let memberCType = getCType(member.type)
          if canonicalCType != memberCType {
            // Skip cast for reference types - they all use struct Ref
            if case .reference(_) = member.type {
              // No cast needed for reference types
            } else {
              let targetCType = getCType(member.type)
              memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
            }
          }
        }
      }
      
      access = memberAccess
      curType = member.type
    }
    let result = nextTemp()
    addIndent()
    appendToBuffer("\(getCType(path.last?.type ?? .void)) \(result) = \(access);\n")
    return result
  }
  
  // MARK: - Block Scope Generation
  
  func generateBlockScope(
    _ statements: [TypedStatementNode], finalExpr: TypedExpressionNode?
  ) -> String {
    pushScope()
    // Process all statements first
    for stmt in statements {
      generateStatement(stmt)
    }

    // Generate final expression
    var result = ""
    if let finalExpr = finalExpr {
      let temp = generateExpressionSSA(finalExpr)
      if finalExpr.type != .void && finalExpr.type != .never {
        let resultVar = nextTemp()
        if case .structure(let decl) = finalExpr.type {
          if finalExpr.valueCategory == .lvalue {
            // Returning an lvalue struct from a block:
            // - Copy types must be copied, because scope cleanup will drop the original.
            switch finalExpr {
            default:
              addIndent()
              appendToBuffer("\(getCType(finalExpr.type)) \(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(temp));\n")
            }
          } else {
            addIndent()
            appendToBuffer("\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n")
          }
        } else if case .union(let decl) = finalExpr.type {
          if finalExpr.valueCategory == .lvalue {
            switch finalExpr {
            default:
              addIndent()
              appendToBuffer("\(getCType(finalExpr.type)) \(resultVar) = __koral_\(decl.qualifiedName)_copy(&\(temp));\n")
            }
          } else {
            addIndent()
            appendToBuffer("\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n")
          }
        } else {
          addIndent()
          appendToBuffer("\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n")
          if case .reference(_) = finalExpr.type, finalExpr.valueCategory == .lvalue {
            addIndent()
            appendToBuffer("__koral_retain(\(resultVar).control);\n")
          }
        }
        result = resultVar
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

    if case .variable(let identifier) = callee {
      // Check if this is a function type variable (closure call)
      // Regular functions have kind = .function, while closure variables have kind = .variable
      if case .variable(_) = identifier.kind,
         case .function(let funcParams, let returnType) = identifier.type {
        return generateClosureCall(
          closureVar: identifier.qualifiedName,
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
      if case .structure(let decl) = arg.type {
        if arg.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          appendToBuffer("\(getCType(arg.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(result));\n")
          argResults.append(copyResult)
        } else {
          argResults.append(result)
        }
      } else if case .union(let decl) = arg.type {
        if arg.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          appendToBuffer("\(getCType(arg.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(result));\n")
          argResults.append(copyResult)
        } else {
          argResults.append(result)
        }
      } else if case .reference(_) = arg.type {
        if arg.valueCategory == .lvalue {
          addIndent()
          appendToBuffer("__koral_retain(\(result).control);\n")
        }
        argResults.append(result)
      } else {
        argResults.append(result)
      }
    }
    
    let returnCType = getCType(returnType)
    
    // Build function pointer type for no-capture case: ReturnType (*)(Args...)
    var noCaptureParamTypes: [String] = []
    for param in funcParams {
      noCaptureParamTypes.append(getCType(param.type))
    }
    let noCaptureParamsStr = noCaptureParamTypes.isEmpty ? "void" : noCaptureParamTypes.joined(separator: ", ")
    let noCaptureFnPtrType = "\(returnCType) (*)(\(noCaptureParamsStr))"
    
    // Build function pointer type for with-capture case: ReturnType (*)(void*, Args...)
    var withCaptureParamTypes: [String] = ["void*"]
    for param in funcParams {
      withCaptureParamTypes.append(getCType(param.type))
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
      let result = nextTemp()
      addIndent()
      appendToBuffer("\(returnCType) \(result);\n")
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
      if case .structure(let decl) = arg.type {
        if arg.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          appendToBuffer("\(getCType(arg.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(result));\n")
          paramResults.append(copyResult)
        } else {
          paramResults.append(result)
        }
      } else if case .union(let decl) = arg.type {
        if arg.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          appendToBuffer("\(getCType(arg.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(result));\n")
          paramResults.append(copyResult)
        } else {
          paramResults.append(result)
        }
      } else if case .reference(_) = arg.type {
        if arg.valueCategory == .lvalue {
          addIndent()
          appendToBuffer("__koral_retain(\(result).control);\n")
        }
        paramResults.append(result)
      } else {
        paramResults.append(result)
      }
    }
    
    addIndent()
    if type == .void || type == .never {
      appendToBuffer("\(identifier.qualifiedName)(")
      appendToBuffer(paramResults.joined(separator: ", "))
      appendToBuffer(");\n")
      return ""
    } else {
      let result = nextTemp()
      appendToBuffer("\(getCType(type)) \(result) = \(identifier.qualifiedName)(")
      appendToBuffer(paramResults.joined(separator: ", "))
      appendToBuffer(");\n")
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
    if case .structure(let decl) = identifier.type {
      if value.valueCategory == .lvalue {
        let copyResult = nextTemp()
        addIndent()
        appendToBuffer("\(getCType(value.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n")
        addIndent()
        appendToBuffer("__koral_\(decl.qualifiedName)_drop(&\(identifier.qualifiedName));\n")
        addIndent()
        appendToBuffer("\(identifier.qualifiedName) = \(copyResult);\n")
      } else {
        addIndent()
        appendToBuffer("__koral_\(decl.qualifiedName)_drop(&\(identifier.qualifiedName));\n")
        addIndent()
        appendToBuffer("\(identifier.qualifiedName) = \(valueResult);\n")
      }
    } else if case .union(let decl) = identifier.type {
      if value.valueCategory == .lvalue {
        let copyResult = nextTemp()
        addIndent()
        appendToBuffer("\(getCType(value.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n")
        addIndent()
        appendToBuffer("__koral_\(decl.qualifiedName)_drop(&\(identifier.qualifiedName));\n")
        addIndent()
        appendToBuffer("\(identifier.qualifiedName) = \(copyResult);\n")
      } else {
        addIndent()
        appendToBuffer("__koral_\(decl.qualifiedName)_drop(&\(identifier.qualifiedName));\n")
        addIndent()
        appendToBuffer("\(identifier.qualifiedName) = \(valueResult);\n")
      }
    } else if case .reference(_) = identifier.type {
      addIndent()
      appendToBuffer("__koral_release(\(identifier.qualifiedName).control);\n")
      addIndent()
      appendToBuffer("\(identifier.qualifiedName) = \(valueResult);\n")
      if value.valueCategory == .lvalue {
        addIndent()
        appendToBuffer("__koral_retain(\(identifier.qualifiedName).control);\n")
      }
    } else {
      addIndent()
      appendToBuffer("\(identifier.qualifiedName) = \(valueResult);\n")
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
    let baseResult = base.qualifiedName
    let valueResult = generateExpressionSSA(value)
    var accessPath = baseResult
    var curType = base.type
    for (index, item) in memberPath.enumerated() {
      let isLast = index == memberPath.count - 1
      let memberName = item.name
      let memberType = item.type
      
      var memberAccess: String
      if case .reference(let inner) = curType {
          let innerCType = getCType(inner)
          memberAccess = "((\(innerCType)*)\(accessPath).ptr)->\(memberName)"
      } else {
          memberAccess = "\(accessPath).\(memberName)"
      }
      
      // Only apply type cast for non-reference struct members when the C types differ
      if case .structure(let decl) = curType.canonical {
        if let canonicalMember = decl.members.first(where: { $0.name == memberName }) {
          let canonicalCType = getCType(canonicalMember.type)
          let memberCTypeStr = getCType(memberType)
          if canonicalCType != memberCTypeStr {
            if case .reference(_) = memberType {
              // No cast needed for reference types
            } else {
              let targetCType = getCType(memberType)
              memberAccess = "*(\(targetCType)*)&(\(memberAccess))"
            }
          }
        }
      }
      
      accessPath = memberAccess
      curType = memberType
      
      if isLast, case .structure(let decl) = memberType {
        if value.valueCategory == .lvalue {
          let copyResult = nextTemp()
          addIndent()
          appendToBuffer("\(getCType(value.type)) \(copyResult) = __koral_\(decl.qualifiedName)_copy(&\(valueResult));\n")
          addIndent()
          appendToBuffer("__koral_\(decl.qualifiedName)_drop(&\(accessPath));\n")
          addIndent()
          appendToBuffer("\(accessPath) = \(copyResult);\n")
        } else {
          addIndent()
          appendToBuffer("__koral_\(decl.qualifiedName)_drop(&\(accessPath));\n")
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

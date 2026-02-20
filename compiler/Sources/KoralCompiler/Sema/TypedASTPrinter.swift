public func printTypedAST(_ node: TypedProgram) {
  var indent: String = ""

  func symbolLabel(_ symbol: Symbol) -> String {
    return "def#\(symbol.defId.id)"
  }

  func printTypedGlobalNode(_ node: TypedGlobalNode) {
    switch node {
    case .foreignUsing(let libraryName):
      print("\(indent)ForeignUsing: \(libraryName)")

    case .foreignFunction(let identifier, let parameters):
      print("\(indent)ForeignFunction:")
      print("\(indent)  Identifier: \(symbolLabel(identifier)): \(identifier.type)")
      print("\(indent)  Parameters:")
      withIndent {
        for param in parameters {
          print("\(indent)\(symbolLabel(param)): \(param.type)")
        }
      }

    case .foreignType(let identifier):
      print("\(indent)ForeignType:")
      print("\(indent)  Identifier: \(symbolLabel(identifier)): \(identifier.type)")

    case .foreignStruct(let identifier, let fields):
      print("\(indent)ForeignStruct:")
      print("\(indent)  Identifier: \(symbolLabel(identifier)): \(identifier.type)")
      print("\(indent)  Fields:")
      withIndent {
        for field in fields {
          print("\(indent)\(field.name): \(field.type)")
        }
      }

    case .foreignGlobalVariable(let identifier, let mutable):
      print("\(indent)ForeignGlobalVariable:")
      print("\(indent)  Identifier: \(symbolLabel(identifier)): \(identifier.type)")
      print("\(indent)  Mutable: \(mutable)")

    case .globalVariable(let identifier, let value, let mutable):
      print("\(indent)GlobalVariable:")
      print("\(indent)  Identifier: \(symbolLabel(identifier)): \(identifier.type)")
      print("\(indent)  Mutable: \(mutable)")
      print("\(indent)  Value:")
      withIndent {
        withIndent {
          printTypedExpression(value)
        }
      }

    case .globalFunction(let identifier, let parameters, let body):
      print("\(indent)GlobalFunction:")
      print("\(indent)  Identifier: \(symbolLabel(identifier)): \(identifier.type)")
      print("\(indent)  Parameters:")
      withIndent {
        for param in parameters {
          print("\(indent)\(symbolLabel(param)): \(param.type)")
        }
      }
      print("\(indent)  Body:")
      withIndent {
        printTypedExpression(body)
      }

    case .globalStructDeclaration(let identifier, let parameters):
      print("\(indent)StructDeclaration:")
      print("\(indent)  Name: \(symbolLabel(identifier)): \(identifier.type)")
      print("\(indent)  Parameters:")
      withIndent {
        for param in parameters {
          print("\(indent)\(symbolLabel(param)): \(param.type)")
          print("\(indent)  Mutable: \(param.isMutable())")
        }
      }

    case .globalUnionDeclaration(let identifier, let cases):
      print("\(indent)UnionDeclaration:")
      print("\(indent)  Name: \(symbolLabel(identifier)): \(identifier.type)")
      withIndent {
        for c in cases {
          print("\(indent)Case: \(c.name)")
          withIndent {
            for param in c.parameters {
              print("\(indent)\(param.name): \(param.type)")
            }
          }
        }
      }

    case .genericTypeTemplate(let name):
      print("\(indent)GenericTypeTemplate: \(name)")

    case .genericFunctionTemplate(let name):
      print("\(indent)GenericFunctionTemplate: \(name)")

    case .givenDeclaration(let type, let methods):
      print("\(indent)GivenDeclaration: \(type)")
      withIndent {
        for method in methods {
          print("\(indent)Method: \(symbolLabel(method.identifier)) : \(method.identifier.type)")
          print("\(indent)  Parameters:")
          withIndent {
            for param in method.parameters {
              print("\(indent)\(symbolLabel(param)): \(param.type)")
            }
          }
          print("\(indent)  Body:")
          withIndent {
            printTypedExpression(method.body)
          }
        }
      }
    }
  }

  func printTypedStatement(_ stmt: TypedStatementNode) {
    switch stmt {
    case .variableDeclaration(let identifier, let value, let mutable):
      print("\(indent)VariableDeclaration:")
      print("\(indent)  Identifier: \(symbolLabel(identifier)): \(identifier.type)")
      print("\(indent)  Mutable: \(mutable)")
      print("\(indent)  Value:")
      withIndent {
        printTypedExpression(value)
      }

    case .assignment(let target, let op, let value):
      if let op {
        print("\(indent)Assignment: \(op)")
      } else {
        print("\(indent)Assignment:")
      }
      print("\(indent)  Target:")
      withIndent {
          printTypedExpression(target)
      }
      print("\(indent)  Value:")
      withIndent {
        printTypedExpression(value)
      }

    case .deptrAssignment(let pointer, let op, let value):
      if let op {
        print("\(indent)DeptrAssignment: \(op)")
      } else {
        print("\(indent)DeptrAssignment")
      }
      print("\(indent)  Pointer:")
      withIndent {
        printTypedExpression(pointer)
      }
      print("\(indent)  Value:")
      withIndent {
        printTypedExpression(value)
      }

    case .expression(let expr):
      printTypedExpression(expr)

    case .return(let value):
      print("\(indent)Return")
      if let value {
        withIndent { printTypedExpression(value) }
      }

    case .break:
      print("\(indent)Break")

    case .continue:
      print("\(indent)Continue")
    }
  }

  func printTypedExpression(_ expr: TypedExpressionNode) {
    switch expr {
    case .integerLiteral(let value, let type):
      print("\(indent)IntLiteral: \(value) : \(type)")

    case .floatLiteral(let value, let type):
      print("\(indent)FloatLiteral: \(value) : \(type)")

    case .stringLiteral(let value, let type):
      print("\(indent)StringLiteral: \"\(value)\" : \(type)")
    case .interpolatedString(let parts, let type):
      print("\(indent)InterpolatedString: : \(type)")
      withIndent {
        for part in parts {
          switch part {
          case .literal(let value):
            print("\(indent)Literal: \"\(value)\"")
          case .expression(let expr):
            print("\(indent)Expression:")
            withIndent {
              printTypedExpression(expr)
            }
          }
        }
      }

    case .booleanLiteral(let value, let type):
      print("\(indent)BoolLiteral: \(value) : \(type)")

    case .castExpression(let inner, let type):
      print("\(indent)CastExpression: : \(type)")
      withIndent {
        print("\(indent)Operand:")
        withIndent {
          printTypedExpression(inner)
        }
      }

    case .variable(let identifier):
      print("\(indent)Variable: \(symbolLabel(identifier)) : \(identifier.type)")

    case .blockExpression(let statements, let finalExpr, let type):
      print("\(indent)Block: \(type)")
      withIndent {
        for stmt in statements {
          printTypedStatement(stmt)
        }
        if let finalExpr = finalExpr {
          print("\(indent)FinalExpression:")
          withIndent {
            printTypedExpression(finalExpr)
          }
        }
      }

    case .arithmeticExpression(let left, let op, let right, let type):
      print("\(indent)ArithmeticExpression: \(op) : \(type)")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printTypedExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printTypedExpression(right)
        }
      }

    case .wrappingArithmeticExpression(let left, let op, let right, let type):
      print("\(indent)WrappingArithmeticExpression: \(op) : \(type)")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printTypedExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printTypedExpression(right)
        }
      }

    case .wrappingShiftExpression(let left, let op, let right, let type):
      print("\(indent)WrappingShiftExpression: \(op) : \(type)")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printTypedExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printTypedExpression(right)
        }
      }

    case .comparisonExpression(let left, let op, let right, let type):
      print("\(indent)ComparisonExpression: \(op) : \(type)")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printTypedExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printTypedExpression(right)
        }
      }

    case .bitwiseExpression(let left, let op, let right, let type):
      print("\(indent)BitwiseExpression: \(op) : \(type)")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printTypedExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printTypedExpression(right)
        }
      }

    case .bitwiseNotExpression(let operand, let type):
      print("\(indent)BitwiseNotExpression: : \(type)")
      withIndent {
        print("\(indent)Operand:")
        withIndent {
          printTypedExpression(operand)
        }
      }

    case .derefExpression(let operand, let type):
      print("\(indent)DerefExpression: : \(type)")
      withIndent {
        print("\(indent)Operand:")
        withIndent {
          printTypedExpression(operand)
        }
      }

    case .ptrExpression(let operand, let type):
      print("\(indent)PtrExpression: : \(type)")
      withIndent {
        print("\(indent)Operand:")
        withIndent {
          printTypedExpression(operand)
        }
      }

    case .deptrExpression(let operand, let type):
      print("\(indent)DeptrExpression: : \(type)")
      withIndent {
        print("\(indent)Operand:")
        withIndent {
          printTypedExpression(operand)
        }
      }

    case .letExpression(let identifier, let value, let body, let type):
      print("\(indent)LetExpression: \(symbolLabel(identifier)) : \(type)")
      withIndent {
        print("\(indent)Value:")
        withIndent {
          printTypedExpression(value)
        }
        print("\(indent)Body:")
        withIndent {
          printTypedExpression(body)
        }
      }

    case .ifExpression(let condition, let thenBranch, let elseBranch, let type):
      print("\(indent)IfExpression: \(type)")
      withIndent {
        print("\(indent)Condition:")
        withIndent {
          printTypedExpression(condition)
        }
        print("\(indent)Then:")
        withIndent {
          printTypedExpression(thenBranch)
        }
        if let elseBranch = elseBranch {
          print("\(indent)Else:")
          withIndent {
            printTypedExpression(elseBranch)
          }
        }
      }

    case .whileExpression(let condition, let body, let type):
      print("\(indent)WhileExpression: \(type)")
      withIndent {
        print("\(indent)Condition:")
        withIndent {
          printTypedExpression(condition)
        }
        print("\(indent)Body:")
        withIndent {
          printTypedExpression(body)
        }
      }

    case .subscriptExpression(let base, let arguments, let method, let type):
      print("\(indent)Subscript: \(type)")
      print("\(indent)  Base:")
      withIndent {
          printTypedExpression(base)
      }
      print("\(indent)  Method: \(symbolLabel(method))")
      print("\(indent)  Arguments:")
      withIndent {
          for arg in arguments {
              printTypedExpression(arg)
          }
      }
    case .matchExpression(let subject, let cases, let type):
      print("\(indent)Match: \(type)")
      print("\(indent)  Subject:")
      withIndent { printTypedExpression(subject) }
      print("\(indent)  Cases:")
      withIndent {
          for c in cases {
              print("\(indent)  Case Pattern: \(c.pattern)")
              print("\(indent)  Body:")
              withIndent { printTypedExpression(c.body) }
          }
      }
    case .call(let callee, let arguments, let type):
      print("\(indent)Call: \(type)")
      withIndent {
        print("\(indent)Callee:")
        withIndent {
          printTypedExpression(callee)
        }
        print("\(indent)Arguments:")
        withIndent {
          for arg in arguments {
            printTypedExpression(arg)
          }
        }
      }

    case .genericCall(let functionName, let typeArgs, let arguments, let type):
      print("\(indent)GenericCall: \(functionName) : \(type)")
      withIndent {
        print("\(indent)TypeArgs: \(typeArgs.map { $0.description }.joined(separator: ", "))")
        print("\(indent)Arguments:")
        withIndent {
          for arg in arguments {
            printTypedExpression(arg)
          }
        }
      }

    case .methodReference(let base, let method, let typeArgs, let methodTypeArgs, let type):
      print("\(indent)MethodReference: \(symbolLabel(method)) : \(type)")
      if let typeArgs = typeArgs, !typeArgs.isEmpty {
        withIndent {
          print("\(indent)TypeArgs: \(typeArgs.map { $0.description }.joined(separator: ", "))")
        }
      }
      if let methodTypeArgs = methodTypeArgs, !methodTypeArgs.isEmpty {
        withIndent {
          print("\(indent)MethodTypeArgs: \(methodTypeArgs.map { $0.description }.joined(separator: ", "))")
        }
      }
      withIndent {
        print("\(indent)Base:")
        withIndent {
          printTypedExpression(base)
        }
      }

    case .traitMethodPlaceholder(let traitName, let methodName, let base, let methodTypeArgs, let type):
      print("\(indent)TraitMethodPlaceholder: \(traitName).\(methodName) : \(type)")
      if !methodTypeArgs.isEmpty {
        withIndent {
          print("\(indent)MethodTypeArgs: \(methodTypeArgs.map { $0.description }.joined(separator: ", "))")
        }
      }
      withIndent {
        print("\(indent)Base:")
        withIndent {
          printTypedExpression(base)
        }
      }

    case .traitObjectConversion(let inner, let traitName, let traitTypeArgs, let concreteType, let type):
      print("\(indent)TraitObjectConversion: \(concreteType) → \(traitName) ref : \(type)")
      if !traitTypeArgs.isEmpty {
        withIndent {
          print("\(indent)TraitTypeArgs: \(traitTypeArgs.map { $0.description }.joined(separator: ", "))")
        }
      }
      withIndent {
        printTypedExpression(inner)
      }

    case .traitMethodCall(let receiver, let traitName, let methodName, let methodIndex, let arguments, let type):
      print("\(indent)TraitMethodCall: \(traitName).\(methodName) [vtable:\(methodIndex)] : \(type)")
      withIndent {
        print("\(indent)Receiver:")
        withIndent {
          printTypedExpression(receiver)
        }
        if !arguments.isEmpty {
          print("\(indent)Arguments:")
          withIndent {
            for arg in arguments {
              printTypedExpression(arg)
            }
          }
        }
      }

    case .memberPath(let source, let path):
      print("\(indent)MemberPath: \(path.map { symbolLabel($0) }.joined(separator: "."))")
      withIndent {
        print("\(indent)Source:")
        withIndent {
          printTypedExpression(source)
        }
      }

    case .andExpression(let left, let right, let type):
      print("\(indent)AndExpression: \(type)")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printTypedExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printTypedExpression(right)
        }
      }

    case .orExpression(let left, let right, let type):
      print("\(indent)OrExpression: \(type)")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printTypedExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printTypedExpression(right)
        }
      }

    case .notExpression(let expr, let type):
      print("\(indent)NotExpression: \(type)")
      withIndent {
        printTypedExpression(expr)
      }

    case .referenceExpression(let expression, let type):
      print("\(indent)ReferenceExpression: \(type)")
      withIndent {
        printTypedExpression(expression)
      }

    case .typeConstruction(let identifier, let typeArgs, let arguments, let type):
      print("\(indent)TypeConstruction: \(symbolLabel(identifier)) : \(type)")
      if let typeArgs = typeArgs, !typeArgs.isEmpty {
        withIndent {
          print("\(indent)TypeArgs: \(typeArgs.map { $0.description }.joined(separator: ", "))")
        }
      }
      withIndent {
        print("\(indent)Arguments:")
        withIndent {
          for arg in arguments {
            printTypedExpression(arg)
          }
        }
      }

    case .unionConstruction(let type, let caseName, let arguments):
      print("\(indent)UnionConstruction: \(type) . \(caseName)")
      withIndent {
        print("\(indent)Arguments:")
        withIndent {
          for arg in arguments {
            printTypedExpression(arg)
          }
        }
      }

    case .intrinsicCall(let node):
      print("\(indent)IntrinsicCall: \(node)")
      
    case .staticMethodCall(let baseType, let methodName, let typeArgs, let methodTypeArgs, let arguments, let type):
      print("\(indent)StaticMethodCall: \(baseType).\(methodName) : \(type)")
      if !typeArgs.isEmpty {
        withIndent {
          print("\(indent)TypeArgs: \(typeArgs.map { $0.description }.joined(separator: ", "))")
        }
      }
      if !methodTypeArgs.isEmpty {
        withIndent {
          print("\(indent)MethodTypeArgs: \(methodTypeArgs.map { $0.description }.joined(separator: ", "))")
        }
      }
      withIndent {
        print("\(indent)Arguments:")
        withIndent {
          for arg in arguments {
            printTypedExpression(arg)
          }
        }
      }
      
    case .ifPatternExpression(let subject, let pattern, let bindings, let thenBranch, let elseBranch, let type):
      print("\(indent)IfPatternExpression: \(type)")
      withIndent {
        print("\(indent)Subject:")
        withIndent {
          printTypedExpression(subject)
        }
        print("\(indent)Pattern: \(pattern)")
        print("\(indent)Bindings: \(bindings.map { "\($0.0): \($0.2)" }.joined(separator: ", "))")
        print("\(indent)Then:")
        withIndent {
          printTypedExpression(thenBranch)
        }
        if let elseBranch = elseBranch {
          print("\(indent)Else:")
          withIndent {
            printTypedExpression(elseBranch)
          }
        }
      }
      
    case .whilePatternExpression(let subject, let pattern, let bindings, let body, let type):
      print("\(indent)WhilePatternExpression: \(type)")
      withIndent {
        print("\(indent)Subject:")
        withIndent {
          printTypedExpression(subject)
        }
        print("\(indent)Pattern: \(pattern)")
        print("\(indent)Bindings: \(bindings.map { "\($0.0): \($0.2)" }.joined(separator: ", "))")
        print("\(indent)Body:")
        withIndent {
          printTypedExpression(body)
        }
      }
      
    case .lambdaExpression(let parameters, let captures, let body, let type):
      print("\(indent)LambdaExpression: \(type)")
      withIndent {
        print("\(indent)Parameters:")
        withIndent {
          for param in parameters {
            print("\(indent)\(symbolLabel(param)): \(param.type)")
          }
        }
        if !captures.isEmpty {
          print("\(indent)Captures:")
          withIndent {
            for capture in captures {
              print("\(indent)\(symbolLabel(capture.symbol)): \(capture.symbol.type) (\(capture.captureKind))")
            }
          }
        }
        print("\(indent)Body:")
        withIndent {
          printTypedExpression(body)
        }
      }
    }
  }

  func withIndent(_ body: () -> Void) {
    let oldIndent = indent
    indent += "  "
    body()
    indent = oldIndent
  }

  switch node {
  case .program(let nodes):
    print("\(indent)TypedProgram:")
    withIndent {
      for node in nodes {
        printTypedGlobalNode(node)
      }
    }
  }
}

public func printTypedAST(_ node: TypedProgram) {
  var indent: String = ""

  func printTypedGlobalNode(_ node: TypedGlobalNode) {
    switch node {
    case .globalVariable(let identifier, let value, let mutable):
      print("\(indent)GlobalVariable:")
      print("\(indent)  Identifier: \(identifier.name): \(identifier.type)")
      print("\(indent)  Mutable: \(mutable)")
      print("\(indent)  Value:")
      withIndent {
        withIndent {
          printTypedExpression(value)
        }
      }

    case .globalFunction(let identifier, let parameters, let body):
      print("\(indent)GlobalFunction:")
      print("\(indent)  Identifier: \(identifier.name): \(identifier.type)")
      print("\(indent)  Parameters:")
      withIndent {
        for param in parameters {
          print("\(indent)\(param.name): \(param.type)")
        }
      }
      print("\(indent)  Body:")
      withIndent {
        printTypedExpression(body)
      }

    case .globalTypeDeclaration(let identifier, let parameters):
      print("\(indent)TypeDeclaration:")
      print("\(indent)  Name: \(identifier.name): \(identifier.type)")
      print("\(indent)  Parameters:")
      withIndent {
        for param in parameters {
          print("\(indent)\(param.name): \(param.type)")
          print("\(indent)  Mutable: \(param.isMutable())")
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
          print("\(indent)Method: \(method.identifier.name) : \(method.identifier.type)")
          print("\(indent)  Parameters:")
          withIndent {
            for param in method.parameters {
              print("\(indent)\(param.name): \(param.type)")
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
      print("\(indent)  Identifier: \(identifier.name): \(identifier.type)")
      print("\(indent)  Mutable: \(mutable)")
      print("\(indent)  Value:")
      withIndent {
        printTypedExpression(value)
      }

    case .assignment(let target, let value):
      print("\(indent)Assignment:")

      switch target {
      case .variable(let identifier):
        print("\(indent)  Target: \(identifier.name): \(identifier.type)")
      case .memberAccess(let base, let memberPath):
        print("\(indent)  Target: MemberAccess Chain")
        print("\(indent)    Base: \(base.name): \(base.type)")
        print("\(indent)    Path: \(memberPath.map { $0.name }.joined(separator: "."))")
        for (index, item) in memberPath.enumerated() {
          print("\(indent)      Member[\(index)]: \(item.name): \(item.type)")
        }
      }

      print("\(indent)  Value:")
      withIndent {
        printTypedExpression(value)
      }

    case .compoundAssignment(let target, let op, let value):
      print("\(indent)CompoundAssignment: \(op)")

      switch target {
      case .variable(let identifier):
        print("\(indent)  Target: \(identifier.name): \(identifier.type)")
      case .memberAccess(let base, let memberPath):
        print("\(indent)  Target: MemberAccess Chain")
        print("\(indent)    Base: \(base.name): \(base.type)")
        print("\(indent)    Path: \(memberPath.map { $0.name }.joined(separator: "."))")
        for (index, item) in memberPath.enumerated() {
          print("\(indent)      Member[\(index)]: \(item.name): \(item.type)")
        }
      }

      print("\(indent)  Value:")
      withIndent {
        printTypedExpression(value)
      }

    case .expression(let expr):
      printTypedExpression(expr)
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

    case .booleanLiteral(let value, let type):
      print("\(indent)BoolLiteral: \(value) : \(type)")

    case .variable(let identifier):
      print("\(indent)Variable: \(identifier.name) : \(identifier.type)")

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

    case .letExpression(let identifier, let value, let body, let type):
      print("\(indent)LetExpression: \(identifier.name) : \(type)")
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
        print("\(indent)Else:")
        withIndent {
          printTypedExpression(elseBranch)
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

    case .methodReference(let base, let method, let type):
      print("\(indent)MethodReference: \(method.name) : \(type)")
      withIndent {
        print("\(indent)Base:")
        withIndent {
          printTypedExpression(base)
        }
      }

    case .memberPath(let source, let path):
      print("\(indent)MemberPath: \(path.map { $0.name }.joined(separator: "."))")
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

    case .typeConstruction(let identifier, let arguments, let type):
      print("\(indent)TypeConstruction: \(identifier.name) : \(type)")
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

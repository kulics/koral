// Helper functions for printing AST nodes
public func printAST(_ node: ASTNode) {
  var indent: String = ""

  func printGlobalNode(_ node: GlobalNode) {
    switch node {
    case .globalVariableDeclaration(let name, let type, let value, let mutable):
      print("\(indent)GlobalVariableDeclaration:")
      print("\(indent)  Name: \(name)")
      print("\(indent)  Type: \(type)")
      print("\(indent)  Mutable: \(mutable)")
      print("\(indent)  Value:")
      withIndent {
        printExpression(value)
      }

    case .globalFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnType, let body):
      print("\(indent)GlobalFunctionDeclaration:")
      print("\(indent)  Name: \(name)")
      print("\(indent)  TypeParameters:")
      for param in typeParameters {
        print("\(indent)    \(param)")
      }
      print("\(indent)  Parameters:")
      for param in parameters {
        let modStr = param.mutable ? "mut " : ""
        print("\(indent)    \(modStr)\(param.name): \(param.type)")
      }
      print("\(indent)  ReturnType: \(returnType)")
      print("\(indent)  Body:")
      withIndent {
        withIndent {
          printExpression(body)
        }
      }

    case .globalTypeDeclaration(let name, let parameters):
      print("\(indent)TypeDeclaration \(name)")
      for param in parameters {
        print("\(indent)  \(param.name): \(param.type)")
        print("\(indent)  Mutable: \(param.mutable)")
      }

    case .givenDeclaration(let type, let methods):
      print("\(indent)GivenDeclaration:")
      print("\(indent)  Type: \(type)")
      print("\(indent)  Methods:")
      withIndent {
        for method in methods {
          print("\(indent)MethodDeclaration:")
          print("\(indent)  Name: \(method.name)")
          print("\(indent)  TypeParameters:")
          for param in method.typeParameters {
            print("\(indent)    \(param)")
          }
          print("\(indent)  Parameters:")
          for param in method.parameters {
            let modStr = param.mutable ? "mut " : ""
            print("\(indent)    \(modStr)\(param.name): \(param.type)")
          }
          print("\(indent)  ReturnType: \(method.returnType)")
          print("\(indent)  Body:")
          withIndent {
            withIndent {
              printExpression(method.body)
            }
          }
        }
      }
    }
  }

  func printStatement(_ node: StatementNode) {
    switch node {
    case .variableDeclaration(let name, let type, let value, let mutable):
      print("\(indent)VariableDeclaration:")
      print("\(indent)  Name: \(name)")
      if let type = type {
        print("\(indent)  Type: \(type)")
      } else {
        print("\(indent)  Type: Inferred")
      }
      print("\(indent)  Mutable: \(mutable)")
      withIndent {
        printExpression(value)
      }

    case .assignment(let target, let value):
      print("\(indent)Assignment:")

      switch target {
      case .variable(let name):
        print("\(indent)  Target: \(name)")
      case .memberAccess(let base, let memberPath):
        print("\(indent)  Target: \(base).\(memberPath.joined(separator: "."))")
      }

      print("\(indent)  Value:")
      withIndent {
        withIndent {
          printExpression(value)
        }
      }

    case .compoundAssignment(let target, let op, let value):
      print("\(indent)CompoundAssignment: \(op)")
      switch target {
      case .variable(let name):
        print("\(indent)  Target: \(name)")
      case .memberAccess(let base, let memberPath):
        print("\(indent)  Target: \(base).\(memberPath.joined(separator: "."))")
      }
      print("\(indent)  Value:")
      withIndent {
        withIndent {
          printExpression(value)
        }
      }

    case .expression(let expr):
      printExpression(expr)
    }
  }

  func printExpression(_ node: ExpressionNode) {
    switch node {
    case .integerLiteral(let value):
      print("\(indent)IntegerLiteral: \(value)")
    case .floatLiteral(let value):
      print("\(indent)FloatLiteral: \(value)")
    case .stringLiteral(let str):
      print("\(indent)StringLiteral: \(str)")
    case .booleanLiteral(let value):
      print("\(indent)BoolLiteral: \(value)")
    case .identifier(let name):
      print("\(indent)Identifier: \(name)")
    case .blockExpression(let statements, let finalExpression):
      print("\(indent)BlockExpression:")
      withIndent {
        for statement in statements {
          printStatement(statement)
        }
        if let finalExpr = finalExpression {
          print("\(indent)FinalExpression:")
          withIndent {
            printExpression(finalExpr)
          }
        }
      }
    case .arithmeticExpression(let left, let op, let right):
      print("\(indent)ArithmeticExpression:")
      withIndent {
        printExpression(left)
        print("\(indent)Operator: \(op)")
        printExpression(right)
      }
    case .comparisonExpression(let left, let op, let right):
      print("\(indent)ComparisonExpression:")
      withIndent {
        printExpression(left)
        print("\(indent)Operator: \(op)")
        printExpression(right)
      }
    case .ifExpression(let condition, let thenBranch, let elseBranch):
      print("\(indent)IfExpression:")
      print("\(indent)  Condition:")
      withIndent {
        withIndent {
          printExpression(condition)
        }
      }
      print("\(indent)  ThenBranch:")
      withIndent {
        withIndent {
          printExpression(thenBranch)
        }
      }
      print("\(indent)  ElseBranch:")
      withIndent {
        withIndent {
          printExpression(elseBranch)
        }
      }
    case .whileExpression(let condition, let body):
      print("\(indent)WhileExpression:")
      print("\(indent)  Condition:")
      withIndent {
        withIndent {
          printExpression(condition)
        }
      }
      print("\(indent)  Body:")
      withIndent {
        withIndent {
          printExpression(body)
        }
      }
    case .call(let callee, let arguments):
      print("\(indent)Call:")
      print("\(indent)  Callee:")
      withIndent {
        printExpression(callee)
      }
      print("\(indent)  Arguments:")
      withIndent {
        withIndent {
          for arg in arguments {
            printExpression(arg)
          }
        }
      }
    case .bitwiseExpression(let left, let op, let right):
      print("\(indent)BitwiseExpression:")
      withIndent {
        printExpression(left)
        print("\(indent)Operator: \(op)")
        printExpression(right)
      }
    case .bitwiseNotExpression(let operand):
      print("\(indent)BitwiseNotExpression:")
      withIndent {
        printExpression(operand)
      }
    case .andExpression(let left, let right):
      print("\(indent)AndExpression:")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printExpression(right)
        }
      }

    case .orExpression(let left, let right):
      print("\(indent)OrExpression:")
      withIndent {
        print("\(indent)Left:")
        withIndent {
          printExpression(left)
        }
        print("\(indent)Right:")
        withIndent {
          printExpression(right)
        }
      }

    case .notExpression(let expr):
      print("\(indent)NotExpression:")
      withIndent {
        printExpression(expr)
      }

    case .refExpression(let expr):
      print("\(indent)RefExpression:")
      withIndent {
        printExpression(expr)
      }

    case .memberPath(let base, let path):
      print("\(indent)MemberPath: \(path.joined(separator: "."))")
      print("\(indent)  Base:")
      withIndent {
        printExpression(base)
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
  case .program(let statements):
    print("\(indent)Program:")
    withIndent {
      for statement in statements {
        printGlobalNode(statement)
      }
    }
  }
}

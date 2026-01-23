// Helper functions for printing AST nodes
public func printAST(_ node: ASTNode) {
  var indent: String = ""

  func printGlobalNode(_ node: GlobalNode) {
    switch node {
    case .usingDeclaration(let decl):
      let pathStr = decl.pathSegments.joined(separator: ".")
      let aliasStr = decl.alias.map { " = \($0)" } ?? ""
      let batchStr = decl.isBatchImport ? ".*" : ""
      print("\(indent)UsingDeclaration: \(decl.pathKind) \(pathStr)\(batchStr)\(aliasStr)")
      print("\(indent)  Access: \(decl.access)")
      
    case .globalVariableDeclaration(let name, let type, let value, let mutable, let access, _):
      print("\(indent)GlobalVariableDeclaration:")
      print("\(indent)  Access: \(access)")
      print("\(indent)  Name: \(name)")
      print("\(indent)  Type: \(type)")
      print("\(indent)  Mutable: \(mutable)")
      print("\(indent)  Value:")
      withIndent {
        printExpression(value)
      }

    case .globalFunctionDeclaration(
      let name, let typeParameters, let parameters, let returnType, let body, let access, _):
      print("\(indent)GlobalFunctionDeclaration:")
      print("\(indent)  Access: \(access)")
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

    case .globalStructDeclaration(let name, let typeParameters, let parameters, let access, _):
      print("\(indent)StructDeclaration \(name)")
      print("\(indent)  Access: \(access)")
      if !typeParameters.isEmpty {
        print("\(indent)  TypeParameters: \(typeParameters)")
      }
      for param in parameters {
        print("\(indent)  \(param.name): \(param.type)")
        print("\(indent)  Mutable: \(param.mutable)")
        print("\(indent)  Access: \(param.access)")
      }

    case .globalUnionDeclaration(let name, let typeParameters, let cases, let access, _):
      print("\(indent)UnionDeclaration \(name)")
      print("\(indent)  Access: \(access)")
      if !typeParameters.isEmpty {
        print("\(indent)  TypeParameters: \(typeParameters)")
      }
      for unionCase in cases {
        print("\(indent)  Case \(unionCase.name)")
        for param in unionCase.parameters {
            print("\(indent)    \(param.name): \(param.type)")
        }
      }

    case .intrinsicFunctionDeclaration(let name, let typeParameters, let parameters, let returnType, let access, _):
      print("\(indent)IntrinsicFunctionDeclaration:")
      print("\(indent)  Access: \(access)")
      print("\(indent)  Name: \(name)")
      print("\(indent)  TypeParameters: \(typeParameters)")
      print("\(indent)  Parameters:")
      for param in parameters {
        let modStr = param.mutable ? "mut " : ""
        print("\(indent)    \(modStr)\(param.name): \(param.type)")
      }
      print("\(indent)  ReturnType: \(returnType)")

    case .intrinsicTypeDeclaration(let name, let typeParameters, let access, _):
        print("\(indent)IntrinsicTypeDeclaration \(name)")
        print("\(indent)  Access: \(access)")
        if !typeParameters.isEmpty {
          print("\(indent)  TypeParameters: \(typeParameters)")
        }

    case .givenDeclaration(let typeParams, let type, let methods, _):
      print("\(indent)GivenDeclaration:")
      if !typeParams.isEmpty {
        print("\(indent)  TypeParameters: \(typeParams)")
      }
      print("\(indent)  Type: \(type)")
      print("\(indent)  Methods:")
      withIndent {
        for method in methods {
          print("\(indent)MethodDeclaration:")
          print("\(indent)  Name: \(method.name)")
          withIndent {
            printExpression(method.body)
          }
        }
      }

    case .intrinsicGivenDeclaration(let typeParams, let type, let methods, _):
      print("\(indent)IntrinsicGivenDeclaration:")
      if !typeParams.isEmpty {
        print("\(indent)  TypeParameters: \(typeParams)")
      }
      print("\(indent)  Type: \(type)")
      print("\(indent)  Methods:")
      withIndent {
        for method in methods {
            print("\(indent)IntrinsicMethodDeclaration:")
            print("\(indent)  Name: \(method.name)")
        }
      }

    case .traitDeclaration(let name, let typeParameters, let superTraits, let methods, let access, _):
      print("\(indent)TraitDeclaration: \(name)")
      print("\(indent)  Access: \(access)")
      if !typeParameters.isEmpty {
        print("\(indent)  TypeParameters: \(typeParameters)")
      }
      if !superTraits.isEmpty {
        print("\(indent)  SuperTraits: \(superTraits)")
      }
      if methods.isEmpty {
        print("\(indent)  Methods: (none)")
      } else {
        print("\(indent)  Methods:")
        withIndent {
          for m in methods {
            print("\(indent)    \(m.name)")
          }
        }
      }
    }
  }

  func printStatement(_ node: StatementNode) {
    switch node {
    case .variableDeclaration(let name, let type, let value, let mutable, _):
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

    case .assignment(let target, let value, _):
      print("\(indent)Assignment:")

      print("\(indent)  Target:")
      withIndent {
          withIndent {
             printExpression(target)
          }
      }

      print("\(indent)  Value:")
      withIndent {
        withIndent {
          printExpression(value)
        }
      }

    case .compoundAssignment(let target, let op, let value, _):
      print("\(indent)CompoundAssignment: \(op)")
      print("\(indent)  Target:")
      withIndent {
          withIndent {
             printExpression(target)
          }
      }
      print("\(indent)  Value:")
      withIndent {
        withIndent {
          printExpression(value)
        }
      }

    case .expression(let expr, _):
      printExpression(expr)

    case .return(let value, _):
      print("\(indent)Return:")
      if let value {
        withIndent {
          printExpression(value)
        }
      }

    case .break:
      print("\(indent)Break")

    case .continue:
      print("\(indent)Continue")
    }
  }

  func printExpression(_ node: ExpressionNode) {
    switch node {
    case .integerLiteral(let value, let suffix):
      if let suffix = suffix {
        print("\(indent)IntegerLiteral: \(value)\(suffix)")
      } else {
        print("\(indent)IntegerLiteral: \(value)")
      }
    case .floatLiteral(let value, let suffix):
      if let suffix = suffix {
        print("\(indent)FloatLiteral: \(value)\(suffix)")
      } else {
        print("\(indent)FloatLiteral: \(value)")
      }
    case .stringLiteral(let str):
      print("\(indent)StringLiteral: \(str)")
    case .booleanLiteral(let value):
      print("\(indent)BoolLiteral: \(value)")
    case .castExpression(let type, let expr):
      print("\(indent)CastExpression: (\(type))")
      withIndent {
        printExpression(expr)
      }
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
      if let elseBranch = elseBranch {
        print("\(indent)  ElseBranch:")
        withIndent {
          withIndent {
            printExpression(elseBranch)
          }
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
    case .letExpression(let name, let type, let value, let mutable, let body):
      print("\(indent)LetExpression: \(mutable ? "mut " : "")\(name)")
      if let type = type {
        print("\(indent)  Type: \(type)")
      }
      print("\(indent)  Value:")
      withIndent {
        withIndent {
          printExpression(value)
        }
      }
      print("\(indent)  Body:")
      withIndent {
        withIndent {
          printExpression(body)
        }
      }
    case .subscriptExpression(let base, let arguments):
      print("\(indent)Subscript:")
      print("\(indent)  Base:")
      withIndent {
          withIndent {
              printExpression(base)
          }
      }
      print("\(indent)  Arguments:")
      withIndent {
          withIndent {
              for arg in arguments {
                  printExpression(arg)
              }
          }
      }
    case .matchExpression(let subject, let cases, _):
      print("\(indent)Match:")
      print("\(indent)  Subject:")
      withIndent { withIndent { printExpression(subject) } }
      print("\(indent)  Cases:")
      withIndent {
          for c in cases {
              print("\(indent)  Case Pattern: \(c.pattern)")
              print("\(indent)  Body:")
              withIndent { withIndent { printExpression(c.body) } }
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

    case .derefExpression(let expr):
      print("\(indent)DerefExpression:")
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

    case .genericMethodCall(let base, let methodTypeArgs, let methodName, let arguments):
      let typeArgsStr = methodTypeArgs.map { "\($0)" }.joined(separator: ", ")
      print("\(indent)GenericMethodCall: .[\(typeArgsStr)]\(methodName)")
      print("\(indent)  Base:")
      withIndent {
        printExpression(base)
      }
      print("\(indent)  Arguments:")
      withIndent {
        withIndent {
          for arg in arguments {
            printExpression(arg)
          }
        }
      }

    case .genericInstantiation(let base, let args):
      print("\(indent)GenericInstantiation: \(base)")
      print("\(indent)  Args: \(args)")
      
    case .staticMethodCall(let typeName, let typeArgs, let methodName, let arguments):
      let typeArgsStr = typeArgs.isEmpty ? "" : "[\(typeArgs.map { "\($0)" }.joined(separator: ", "))]"
      print("\(indent)StaticMethodCall: \(typeArgsStr)\(typeName).\(methodName)")
      print("\(indent)  Arguments:")
      withIndent {
        withIndent {
          for arg in arguments {
            printExpression(arg)
          }
        }
      }
    
    case .forExpression(let pattern, let iterable, let body):
      print("\(indent)ForExpression:")
      print("\(indent)  Pattern: \(pattern)")
      print("\(indent)  Iterable:")
      withIndent {
        withIndent {
          printExpression(iterable)
        }
      }
      print("\(indent)  Body:")
      withIndent {
        withIndent {
          printExpression(body)
        }
      }
    
    case .rangeExpression(let op, let left, let right):
      print("\(indent)RangeExpression: \(op)")
      if let l = left {
        print("\(indent)  Left:")
        withIndent {
          withIndent {
            printExpression(l)
          }
        }
      }
      if let r = right {
        print("\(indent)  Right:")
        withIndent {
          withIndent {
            printExpression(r)
          }
        }
      }
      
    case .ifPatternExpression(let subject, let pattern, let thenBranch, let elseBranch, _):
      print("\(indent)IfPatternExpression:")
      print("\(indent)  Subject:")
      withIndent {
        withIndent {
          printExpression(subject)
        }
      }
      print("\(indent)  Pattern: \(pattern)")
      print("\(indent)  ThenBranch:")
      withIndent {
        withIndent {
          printExpression(thenBranch)
        }
      }
      if let elseBranch = elseBranch {
        print("\(indent)  ElseBranch:")
        withIndent {
          withIndent {
            printExpression(elseBranch)
          }
        }
      }
      
    case .whilePatternExpression(let subject, let pattern, let body, _):
      print("\(indent)WhilePatternExpression:")
      print("\(indent)  Subject:")
      withIndent {
        withIndent {
          printExpression(subject)
        }
      }
      print("\(indent)  Pattern: \(pattern)")
      print("\(indent)  Body:")
      withIndent {
        withIndent {
          printExpression(body)
        }
      }
      
    case .lambdaExpression(let parameters, let returnType, let body, _):
      let paramsStr = parameters.map { param in
        if let type = param.type {
          return "\(param.name) \(type)"
        } else {
          return param.name
        }
      }.joined(separator: ", ")
      let returnStr = returnType.map { " \($0)" } ?? ""
      print("\(indent)LambdaExpression: (\(paramsStr))\(returnStr) ->")
      print("\(indent)  Body:")
      withIndent {
        withIndent {
          printExpression(body)
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
  case .program(let globalNodes):
    print("\(indent)Program:")
    withIndent {
      for node in globalNodes {
        printGlobalNode(node)
      }
    }
  }
}

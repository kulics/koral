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

    case .foreignUsingDeclaration(let libraryName, _):
      print("\(indent)ForeignUsingDeclaration: \(libraryName)")
      
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

    case .foreignFunctionDeclaration(let name, let parameters, let returnType, let access, _):
      print("\(indent)ForeignFunctionDeclaration:")
      print("\(indent)  Access: \(access)")
      print("\(indent)  Name: \(name)")
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

    case .foreignTypeDeclaration(let name, let cname, let fields, let access, _):
        print("\(indent)ForeignTypeDeclaration \(name)")
        if let cname {
          print("\(indent)  CName: \(cname)")
        }
        print("\(indent)  Access: \(access)")
        if let fields {
          for field in fields {
            print("\(indent)  Field \(field.name): \(field.type)")
          }
        }
    case .foreignLetDeclaration(let name, let type, let mutable, let access, _):
        let mutLabel = mutable ? "mut " : ""
        print("\(indent)ForeignLetDeclaration \(mutLabel)\(name)")
        print("\(indent)  Access: \(access)")
        print("\(indent)  Type: \(type)")

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

    case .givenTraitDeclaration(let typeParams, let type, let trait, let methods, _):
      print("\(indent)GivenTraitDeclaration:")
      if !typeParams.isEmpty {
        print("\(indent)  TypeParameters: \(typeParams)")
      }
      print("\(indent)  Type: \(type)")
      print("\(indent)  Trait: \(trait)")
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
        let superTraitsDesc = superTraits.map { $0.description }
        print("\(indent)  SuperTraits: \(superTraitsDesc)")
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

    case .typeAliasDeclaration(let name, let targetType, let access, _):
      print("\(indent)TypeAliasDeclaration: \(name)")
      print("\(indent)  Access: \(access)")
      print("\(indent)  TargetType: \(targetType)")
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

    case .assignment(let target, let op, let value, _):
      if let op {
        print("\(indent)Assignment: \(op)")
      } else {
        print("\(indent)Assignment:")
      }

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

    case .deptrAssignment(let pointer, let op, let value, _):
      if let op {
        print("\(indent)DeptrAssignment: \(op)")
      } else {
        print("\(indent)DeptrAssignment:")
      }
      print("\(indent)  Pointer:")
      withIndent {
        withIndent {
          printExpression(pointer)
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

    case .`defer`(let expression, _):
      print("\(indent)Defer:")
      withIndent {
        printExpression(expression)
      }

    case .yield(let value, _):
      print("\(indent)Yield:")
      withIndent {
        printExpression(value)
      }
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
    case .interpolatedString(let parts, _):
      print("\(indent)InterpolatedString:")
      withIndent {
        for part in parts {
          switch part {
          case .literal(let value):
            print("\(indent)Literal: \(value)")
          case .expression(let expr):
            print("\(indent)Expression:")
            withIndent {
              printExpression(expr)
            }
          }
        }
      }
    case .booleanLiteral(let value):
      print("\(indent)BoolLiteral: \(value)")
    case .castExpression(let type, let expr):
      print("\(indent)CastExpression: (\(type))")
      withIndent {
        printExpression(expr)
      }
    case .identifier(let name):
      print("\(indent)Identifier: \(name)")
    case .blockExpression(let statements):
      print("\(indent)BlockExpression:")
      withIndent {
        for statement in statements {
          printStatement(statement)
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

    case .unaryMinusExpression(let expr):
      print("\(indent)UnaryMinusExpression:")
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

    case .ptrExpression(let expr):
      print("\(indent)PtrExpression:")
      withIndent {
        printExpression(expr)
      }

    case .deptrExpression(let expr):
      print("\(indent)DeptrExpression:")
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

    case .qualifiedMethodCall(let base, let traitName, let methodName, let arguments):
      print("\(indent)QualifiedMethodCall: .(\(traitName))\(methodName)")
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

    case .qualifiedGenericMethodCall(let base, let traitName, let methodTypeArgs, let methodName, let arguments):
      let typeArgsStr = methodTypeArgs.map { "\($0)" }.joined(separator: ", ")
      print("\(indent)QualifiedGenericMethodCall: .(\(traitName))[\(typeArgsStr)]\(methodName)")
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
      
    case .implicitMemberExpression(let memberName, let arguments, _):
      print("\(indent)ImplicitMemberExpression: .\(memberName)")
      if !arguments.isEmpty {
        print("\(indent)  Arguments:")
        withIndent {
          withIndent {
            for arg in arguments {
              printExpression(arg)
            }
          }
        }
      }

    case .orElseExpression(let operand, let defaultExpr, _):
      print("\(indent)OrElseExpression:")
      print("\(indent)  Operand:")
      withIndent {
        withIndent {
          printExpression(operand)
        }
      }
      print("\(indent)  Default:")
      withIndent {
        withIndent {
          printExpression(defaultExpr)
        }
      }

    case .andThenExpression(let operand, let transformExpr, _):
      print("\(indent)AndThenExpression:")
      print("\(indent)  Operand:")
      withIndent {
        withIndent {
          printExpression(operand)
        }
      }
      print("\(indent)  Transform:")
      withIndent {
        withIndent {
          printExpression(transformExpr)
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

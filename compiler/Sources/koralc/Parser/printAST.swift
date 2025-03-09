// Helper functions for printing AST nodes
public func printAST(_ node: ASTNode) {
    var indent: String = ""
    
    func printGlobalNode(_ node: GlobalNode) {
        switch node {
        case let .globalVariableDeclaration(name, type, value, mutable):
            print("\(indent)GlobalVariableDeclaration:")
            print("\(indent)  Name: \(name)")
            print("\(indent)  Type: \(type)")
            print("\(indent)  Mutable: \(mutable)")
            withIndent {
                printExpression(value)
            }
            
        case let .globalFunctionDeclaration(name, parameters, returnType, body):
            print("\(indent)GlobalFunctionDeclaration:")
            print("\(indent)  Name: \(name)")
            print("\(indent)  Parameters:")
            for param in parameters {
                print("\(indent)    \(param.name): \(param.type)")
            }
            print("\(indent)  ReturnType: \(returnType)")
            print("\(indent)  Body:")
            withIndent {
                withIndent {
                    printExpression(body)
                }
            }
        }
    }

    func printStatement(_ node: StatementNode) {
        switch node {
        case let .variableDeclaration(name, type, value, mutable):
            print("\(indent)VariableDeclaration:")
            print("\(indent)  Name: \(name)")
            print("\(indent)  Type: \(type)")
            print("\(indent)  Mutable: \(mutable)")
            withIndent {
                printExpression(value)
            }
            
        case let .assignment(name, value):
            print("\(indent)Assignment:")
            print("\(indent)  Name: \(name)")
            print("\(indent)  Value:")
            withIndent {
                withIndent {
                    printExpression(value)
                }
            }
            
        case let .expression(expr):
            printExpression(expr)
        }
    }

    func printExpression(_ node: ExpressionNode) {
        switch node {
        case let .integerLiteral(value):
            print("\(indent)IntegerLiteral: \(value)")
        case let .floatLiteral(value):
            print("\(indent)FloatLiteral: \(value)")
        case let .stringLiteral(str):
            print("\(indent)StringLiteral: \(str)")
        case let .boolLiteral(value):
            print("\(indent)BoolLiteral: \(value)")
        case let .identifier(name):
            print("\(indent)Identifier: \(name)")
        case let .blockExpression(statements, finalExpression):
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
        case let .arithmeticExpression(left, op, right):
            print("\(indent)ArithmeticExpression:")
            withIndent {
                printExpression(left)
                print("\(indent)Operator: \(op)")
                printExpression(right)
            }
        case let .comparisonExpression(left, op, right):
            print("\(indent)ComparisonExpression:")
            withIndent {
                printExpression(left)
                print("\(indent)Operator: \(op)")
                printExpression(right)
            }
        case let .ifExpression(condition, thenBranch, elseBranch):
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
        case let .functionCall(name, arguments):
            print("\(indent)FunctionCall:")
            print("\(indent)  Name: \(name)")
            print("\(indent)  Arguments:")
            withIndent {
                withIndent {
                    for arg in arguments {
                        printExpression(arg)
                    }
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
    case let .program(statements):
        print("\(indent)Program:")
        withIndent {
            for statement in statements {
                printGlobalNode(statement)
            }
        }
    }
}
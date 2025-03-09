public func printTypedAST(_ node: TypedProgram) {
    var indent: String = ""

    func printTypedGlobalNode(_ node: TypedGlobalNode) {
        switch node {
        case let .globalVariable(identifier, value, mutable):
            print("\(indent)GlobalVariable:")
            print("\(indent)  Identifier: \(identifier.name): \(identifier.type)")
            print("\(indent)  Mutable: \(mutable)")
            print("\(indent)  Value:")
            withIndent {
                withIndent {
                    printTypedExpression(value)
                }
            }
            
        case let .globalFunction(identifier, parameters, body):
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
        }
    }
    
    func printTypedStatement(_ stmt: TypedStatementNode) {
        switch stmt {
        case let .variableDecl(identifier, value, mutable):
            print("\(indent)VariableDeclaration:")
            print("\(indent)  Identifier: \(identifier.name): \(identifier.type)")
            print("\(indent)  Mutable: \(mutable)")
            print("\(indent)  Value:")
            withIndent {
                printTypedExpression(value)
            }
            
        case let .assignment(identifier, value):
            print("\(indent)Assignment:")
            print("\(indent)  Target: \(identifier.name): \(identifier.type)")
            print("\(indent)  Value:")
            withIndent {
                printTypedExpression(value)
            }
            
        case let .expression(expr):
            printTypedExpression(expr)
        }
    }
    
    func printTypedExpression(_ expr: TypedExpressionNode) {
        switch expr {
        case let .intLiteral(value, type):
            print("\(indent)IntLiteral: \(value) : \(type)")
            
        case let .floatLiteral(value, type):
            print("\(indent)FloatLiteral: \(value) : \(type)")
            
        case let .stringLiteral(value, type):
            print("\(indent)StringLiteral: \"\(value)\" : \(type)")
            
        case let .boolLiteral(value, type):
            print("\(indent)BoolLiteral: \(value) : \(type)")
            
        case let .variable(identifier):
            print("\(indent)Variable: \(identifier.name) : \(identifier.type)")
            
        case let .block(statements, finalExpr, type):
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
            
        case let .arithmeticOp(left, op, right, type):
            print("\(indent)ArithmeticOperation: \(op) : \(type)")
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
            
        case let .comparisonOp(left, op, right, type):
            print("\(indent)ComparisonOperation: \(op) : \(type)")
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
            
        case let .ifExpr(condition, thenBranch, elseBranch, type):
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
            
        case let .functionCall(identifier, arguments, type):
            print("\(indent)FunctionCall: \(identifier.name) : \(type)")
            withIndent {
                print("\(indent)Arguments:")
                withIndent {
                    for arg in arguments {
                        printTypedExpression(arg)
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
    case let .program(nodes):
        print("\(indent)TypedProgram:")
        withIndent {
            for node in nodes {
                printTypedGlobalNode(node)
            }
        }
    }
}

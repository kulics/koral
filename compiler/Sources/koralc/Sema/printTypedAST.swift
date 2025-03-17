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
            
        case let .globalTypeDeclaration(identifier, parameters):
            print("\(indent)TypeDeclaration:")
            print("\(indent)  Name: \(identifier.name): \(identifier.type)")
            print("\(indent)  Parameters:")
            withIndent {
                for param in parameters {
                    print("\(indent)\(param.name): \(param.type)")
                }
            }
        }
    }
    
    func printTypedStatement(_ stmt: TypedStatementNode) {
        switch stmt {
        case let .variableDeclaration(identifier, value, mutable):
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
        case let .integerLiteral(value, type):
            print("\(indent)IntLiteral: \(value) : \(type)")
            
        case let .floatLiteral(value, type):
            print("\(indent)FloatLiteral: \(value) : \(type)")
            
        case let .stringLiteral(value, type):
            print("\(indent)StringLiteral: \"\(value)\" : \(type)")
            
        case let .booleanLiteral(value, type):
            print("\(indent)BoolLiteral: \(value) : \(type)")
            
        case let .variable(identifier):
            print("\(indent)Variable: \(identifier.name) : \(identifier.type)")
            
        case let .blockExpression(statements, finalExpr, type):
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
            
        case let .arithmeticExpression(left, op, right, type):
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
            
        case let .comparisonExpression(left, op, right, type):
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
            
        case let .ifExpression(condition, thenBranch, elseBranch, type):
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

        case let .whileExpression(condition, body, type):
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

        case let .andExpression(left, right, type):
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

        case let .orExpression(left, right, type):
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

        case let .notExpression(expr, type):
            print("\(indent)NotExpression: \(type)")
            withIndent {
                printTypedExpression(expr)
            }
            
        case let .typeConstruction(identifier, arguments, type):
            print("\(indent)TypeConstruction: \(identifier.name) : \(type)")
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

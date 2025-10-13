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
            print("\(indent)  Value:")
            withIndent {
                printExpression(value)
            }
            
        case let .globalFunctionDeclaration(name, typeParameters, parameters, returnModifier, returnType, body):
            print("\(indent)GlobalFunctionDeclaration:")
            print("\(indent)  Name: \(name)")
            print("\(indent)  TypeParameters:")
            for param in typeParameters {
                print("\(indent)    \(param)")
            }
            print("\(indent)  Parameters:")
            for param in parameters {
                let modStr: String
                switch param.modifier {
                case .none: modStr = ""
                case .ref: modStr = "ref "
                case .own: modStr = "own "
                case .mut: modStr = "mut "
                case .mutRef: modStr = "mut ref "
                case .mutOwn: modStr = "mut own "
                }
                print("\(indent)    \(modStr)\(param.name): \(param.type)")
            }
            let retModStr: String
            switch returnModifier {
            case .none: retModStr = ""
            case .ref: retModStr = "ref "
            case .own: retModStr = "own "
            case .mut: retModStr = "mut "
            case .mutRef: retModStr = "mut ref "
            case .mutOwn: retModStr = "mut own "
            }
            print("\(indent)  ReturnType: \(retModStr)\(returnType)")
            print("\(indent)  Body:")
            withIndent {
                withIndent {
                    printExpression(body)
                }
            }
            
        case let .globalTypeDeclaration(name, parameters, isValue):
            print("\(indent)TypeDeclaration \(name)")
            print("\(indent)  IsValue: \(isValue)")
            for param in parameters {
                print("\(indent)  \(param.name): \(param.type)")
                print("\(indent)  Mutable: \(param.mutable)")
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
            
        case let .assignment(target, value):
            print("\(indent)Assignment:")
            
            switch target {
            case let .variable(name):
                print("\(indent)  Target: \(name)")
            case let .memberAccess(base, memberPath):
                print("\(indent)  Target: \(base).\(memberPath.joined(separator: "."))")
            }
            
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
        case let .booleanLiteral(value):
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
        case let .whileExpression(condition, body):
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
        case let .functionCall(name, typeArguments, arguments):
            print("\(indent)FunctionCall:")
            print("\(indent)  Name: \(name)")
            print("\(indent)  TypeArguments:")
            withIndent {
                withIndent {
                    for arg in typeArguments {
                        print(arg)
                    }
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
        case let .andExpression(left, right):
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
            
        case let .orExpression(left, right):
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
            
        case let .notExpression(expr):
            print("\(indent)NotExpression:")
            withIndent {
                printExpression(expr)
            }
            
        case let .memberAccess(expr, member):
            print("\(indent)MemberAccess:")
            print("\(indent)  Member: \(member)")
            withIndent {
                printExpression(expr)
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
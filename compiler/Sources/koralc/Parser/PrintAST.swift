// Helper functions for printing AST nodes
public class ASTPrinter {
    private var indent: String = ""
    
    public init() {}
    
    public func print(_ node: ASTNode) {
        printAST(node)
    }
    
    private func printAST(_ node: ASTNode) {
        switch node {
        case let .program(statements):
            Swift.print("\(indent)Program:")
            withIndent {
                for statement in statements {
                    printGlobalNode(statement)
                }
            }
        }
    }

    private func printGlobalNode(_ node: GlobalNode) {
        switch node {
        case let .globalVariableDeclaration(name, type, value, mutable):
            Swift.print("\(indent)GlobalVariableDeclaration:")
            Swift.print("\(indent)  Name: \(name)")
            Swift.print("\(indent)  Type: \(type)")
            Swift.print("\(indent)  Mutable: \(mutable)")
            withIndent {
                printExpression(value)
            }
            
        case let .globalFunctionDeclaration(name, parameters, returnType, body):
            Swift.print("\(indent)GlobalFunctionDeclaration:")
            Swift.print("\(indent)  Name: \(name)")
            Swift.print("\(indent)  Parameters:")
            for param in parameters {
                Swift.print("\(indent)    \(param.name): \(param.type)")
            }
            Swift.print("\(indent)  ReturnType: \(returnType)")
            Swift.print("\(indent)  Body:")
            withIndent {
                withIndent {
                    printExpression(body)
                }
            }
        }
    }

    private func printStatement(_ node: StatementNode) {
        switch node {
        case let .variableDeclaration(name, type, value, mutable):
            Swift.print("\(indent)VariableDeclaration:")
            Swift.print("\(indent)  Name: \(name)")
            Swift.print("\(indent)  Type: \(type)")
            Swift.print("\(indent)  Mutable: \(mutable)")
            withIndent {
                printExpression(value)
            }
            
        case let .assignment(name, value):
            Swift.print("\(indent)Assignment:")
            Swift.print("\(indent)  Name: \(name)")
            Swift.print("\(indent)  Value:")
            withIndent {
                withIndent {
                    printExpression(value)
                }
            }
            
        case let .expression(expr):
            printExpression(expr)
        }
    }

    private func printExpression(_ node: ExpressionNode) {
        switch node {
        case let .integerLiteral(value):
            Swift.print("\(indent)IntegerLiteral: \(value)")
        case let .floatLiteral(value):
            Swift.print("\(indent)FloatLiteral: \(value)")
        case let .stringLiteral(str):
            Swift.print("\(indent)StringLiteral: \(str)")
        case let .boolLiteral(value):
            Swift.print("\(indent)BoolLiteral: \(value)")
        case let .identifier(name):
            Swift.print("\(indent)Identifier: \(name)")
        case let .blockExpression(statements, finalExpression):
            Swift.print("\(indent)BlockExpression:")
            withIndent {
                for statement in statements {
                    printStatement(statement)
                }
                if let finalExpr = finalExpression {
                    Swift.print("\(indent)FinalExpression:")
                    withIndent {
                        printExpression(finalExpr)
                    }
                }
            }
        case let .arithmeticExpression(left, op, right):
            Swift.print("\(indent)ArithmeticExpression:")
            withIndent {
                printExpression(left)
                Swift.print("\(indent)Operator: \(op)")
                printExpression(right)
            }
        case let .comparisonExpression(left, op, right):
            Swift.print("\(indent)ComparisonExpression:")
            withIndent {
                printExpression(left)
                Swift.print("\(indent)Operator: \(op)")
                printExpression(right)
            }
        case let .ifExpression(condition, thenBranch, elseBranch):
            Swift.print("\(indent)IfExpression:")
            Swift.print("\(indent)  Condition:")
            withIndent {
                withIndent {
                    printExpression(condition)
                }
            }
            Swift.print("\(indent)  ThenBranch:")
            withIndent {
                withIndent {
                    printExpression(thenBranch)
                }
            }
            Swift.print("\(indent)  ElseBranch:")
            withIndent {
                withIndent {
                    printExpression(elseBranch)
                }
            }
        case let .functionCall(name, arguments):
            Swift.print("\(indent)FunctionCall:")
            Swift.print("\(indent)  Name: \(name)")
            Swift.print("\(indent)  Arguments:")
            withIndent {
                withIndent {
                    for arg in arguments {
                        printExpression(arg)
                    }
                }
            }
        }
    }
    
    private func withIndent(_ body: () -> Void) {
        let oldIndent = indent
        indent += "  "
        body()
        indent = oldIndent
    }
}

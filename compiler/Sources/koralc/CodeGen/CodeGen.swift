public class CodeGen {
    private let ast: TypedProgram
    private var indent: String = ""
    private var buffer: String = ""
    private var tempVarCounter = 0
    private var globalInitializations: [(String, TypedExpressionNode)] = []

    public init(ast: TypedProgram) {
        self.ast = ast
    }

    public func generate() -> String {
        // 添加标准头文件
        buffer = """
        #include <stdio.h>
        #include <stdbool.h>
        
        """
        
        // 生成程序体
        generateProgram(ast)
        return buffer
    }

    private func generateProgram(_ program: TypedProgram) {
        switch program {
        case let .program(nodes):
            // 先生成所有类型声明
            for node in nodes {
                if case let .globalTypeDeclaration(identifier, parameters) = node {
                    generateTypeDeclaration(identifier, parameters)
                }
            }
            buffer += "\n"
            
            // 先生成所有函数声明
            for node in nodes {
                if case let .globalFunction(identifier, params, _) = node {
                    generateFunctionDeclaration(identifier, params)
                }
            }
            buffer += "\n"
            
            // 生成全局变量声明
            for node in nodes {
                if case let .globalVariable(identifier, value, _) = node {
                    let cType = getCType(identifier.type)
                    
                    // 简单表达式直接初始化
                    switch value {
                        case .integerLiteral(_,_), .floatLiteral(_,_), 
                            .stringLiteral(_,_), .booleanLiteral(_,_):
                            buffer += "\(cType) \(identifier.name) = "
                            buffer += generateExpressionSSA(value)
                            buffer += ";\n"
                        default:
                            // 复杂表达式延迟到 main 函数中初始化
                            buffer += "\(cType) \(identifier.name);\n"
                            globalInitializations.append((identifier.name, value))
                    }
                }
            }
            buffer += "\n"
            
            // 生成函数实现
            for node in nodes {
                if case let .globalFunction(identifier, params, body) = node {
                    generateGlobalFunction(identifier, params, body)
                }
            }

            // 生成 main 函数用于初始化全局变量
            if !globalInitializations.isEmpty {
                generateMainFunction()
            }
        }
    }

    private func generateMainFunction() {
        buffer += "\nint main() {\n"
        withIndent {
            // 生成全局变量初始化
            for (name, value) in globalInitializations {
                let resultVar = generateExpressionSSA(value)
                addIndent()
                buffer += "\(name) = \(resultVar);\n"
            }
            // 如果需要的话，这里可以调用用户定义的 main 函数
            addIndent()
            buffer += "return 0;\n"
        }
        buffer += "}\n"
    }

    private func generateFunctionDeclaration(_ identifier: TypedIdentifierNode, _ params: [TypedIdentifierNode]) {
        let returnType = getFunctionReturnType(identifier.type)
        let paramList = params.map { getCType($0.type) + " " + $0.name }.joined(separator: ", ")
        buffer += "\(returnType) \(identifier.name)(\(paramList));\n"
    }

    private func generateGlobalFunction(_ identifier: TypedIdentifierNode, 
                                     _ params: [TypedIdentifierNode], 
                                     _ body: TypedExpressionNode) {
        let returnType = getFunctionReturnType(identifier.type)
        let paramList = params.map { getCType($0.type) + " " + $0.name }.joined(separator: ", ")
        buffer += "\(returnType) \(identifier.name)(\(paramList)) {\n"
        withIndent {
            generateFunctionBody(body)
        }
        buffer += "}\n"
    }

    private func generateFunctionBody(_ body: TypedExpressionNode) {
        let resultVar = generateExpressionSSA(body)
        if body.type != .void {
            addIndent()
            buffer += "return \(resultVar);\n"
        }
    }

    private func generateExpressionSSA(_ expr: TypedExpressionNode) -> String {
        switch expr {
        case let .integerLiteral(value, _):
            return String(value)
            
        case let .floatLiteral(value, _):
            return String(value)
            
        case let .stringLiteral(value, _):
            return "\"\(value)\""
            
        case let .booleanLiteral(value, _):
            return value ? "true" : "false"
            
        case let .variable(identifier):
            return identifier.name
            
        case let .blockExpression(statements, finalExpr, type):
            for stmt in statements {
                generateStatement(stmt)
            }
            
            if let finalExpr = finalExpr {
                if type == .void {
                    _ = generateExpressionSSA(finalExpr)
                    return ""
                } else {
                    let result = nextTemp()
                    let lastName = generateExpressionSSA(finalExpr)
                    addIndent()
                    buffer += "\(getCType(type)) \(result) = \(lastName);\n"
                    return result
                }
            }
            return ""
            
        case let .arithmeticExpression(left, op, right, type):
            let leftResult = generateExpressionSSA(left)
            let rightResult = generateExpressionSSA(right)
            let result = nextTemp()
            addIndent()
            buffer += "\(getCType(type)) \(result) = \(leftResult) \(arithmeticOpToC(op)) \(rightResult);\n"
            return result
            
        case let .comparisonExpression(left, op, right, type):
            let leftResult = generateExpressionSSA(left)
            let rightResult = generateExpressionSSA(right)
            let result = nextTemp()
            addIndent()
            buffer += "\(getCType(type)) \(result) = \(leftResult) \(comparisonOpToC(op)) \(rightResult);\n"
            return result
            
        case let .ifExpression(condition, thenBranch, elseBranch, type):
            let conditionVar = generateExpressionSSA(condition)
            
            if type == .void {
                addIndent()
                buffer += "if (\(conditionVar)) {\n"
                withIndent {
                    _ = generateExpressionSSA(thenBranch)
                }
                addIndent()
                buffer += "} else {\n"
                withIndent {
                    _ = generateExpressionSSA(elseBranch)
                }
                addIndent()
                buffer += "}\n"
                return ""
            } else {
                let resultVar = nextTemp()
                addIndent()
                buffer += "\(getCType(type)) \(resultVar);\n"
                addIndent()
                buffer += "if (\(conditionVar)) {\n"
                withIndent {
                    let thenResult = generateExpressionSSA(thenBranch)
                    addIndent()
                    buffer += "\(resultVar) = \(thenResult);\n"
                }
                addIndent()
                buffer += "} else {\n"
                withIndent {
                    let elseResult = generateExpressionSSA(elseBranch)
                    addIndent()
                    buffer += "\(resultVar) = \(elseResult);\n"
                }
                addIndent()
                buffer += "}\n"
                return resultVar
            }

        case let .functionCall(identifier, arguments, type):
            let argResults = arguments.map(generateExpressionSSA)
            
            if type == .void {
                addIndent()
                buffer += "\(identifier.name)("
                buffer += argResults.joined(separator: ", ")
                buffer += ");\n"
                return ""
            } else {
                let result = nextTemp()
                addIndent()
                buffer += "\(getCType(type)) \(result) = \(identifier.name)("
                buffer += argResults.joined(separator: ", ")
                buffer += ");\n"
                return result
            }

        case let .whileExpression(condition, body, _):
            let labelPrefix = nextTemp()
            addIndent()
            buffer += "\(labelPrefix)_start:\n"
            let conditionVar = generateExpressionSSA(condition)
            addIndent()
            buffer += "if (!\(conditionVar)) { goto \(labelPrefix)_end; }\n"
            _ = generateExpressionSSA(body)
            addIndent()
            buffer += "goto \(labelPrefix)_start;\n"
            addIndent()
            buffer += "\(labelPrefix)_end:\n"
            return ""
            
        case let .andExpression(left, right, _):
            let result = nextTemp()
            let leftResult = generateExpressionSSA(left)
            let endLabel = nextTemp()
            
            addIndent()
            buffer += "bool \(result);\n"
            addIndent()
            buffer += "if (!\(leftResult)) {\n"
            withIndent {
                addIndent()
                buffer += "\(result) = false;\n"
                addIndent() 
                buffer += "goto \(endLabel);\n"
            }
            addIndent()
            buffer += "}\n"
            let rightResult = generateExpressionSSA(right)
            addIndent()
            buffer += "\(result) = \(rightResult);\n"
            addIndent()
            buffer += "\(endLabel):\n"
            return result
            
        case let .orExpression(left, right, _):
            let result = nextTemp()
            let leftResult = generateExpressionSSA(left) 
            let endLabel = nextTemp()
            
            addIndent()
            buffer += "bool \(result);\n"
            addIndent()
            buffer += "if (\(leftResult)) {\n"
            withIndent {
                addIndent()
                buffer += "\(result) = true;\n"
                addIndent()
                buffer += "goto \(endLabel);\n"
            }
            addIndent()
            buffer += "}\n"
            let rightResult = generateExpressionSSA(right)
            addIndent()
            buffer += "\(result) = \(rightResult);\n"
            addIndent()
            buffer += "\(endLabel):\n"
            return result
            
        case let .notExpression(expr, _):
            let exprResult = generateExpressionSSA(expr)
            let result = nextTemp()
            addIndent()
            buffer += "bool \(result) = !\(exprResult);\n"
            return result

        case let .typeConstruction(identifier, arguments, _):
            // 先求值所有参数
            let argResults = arguments.map(generateExpressionSSA)
            
            // 使用 C 语言的复合字面量语法进行初始化
            let result = nextTemp()
            addIndent()
            buffer += "struct \(identifier.name) \(result) = {" 
            buffer += argResults.joined(separator: ", ")
            buffer += "};\n"
            return result
        }
    }

    private func nextTemp() -> String {
        tempVarCounter += 1
        return "_t\(tempVarCounter)"
    }

    private func generateStatement(_ stmt: TypedStatementNode) {
        switch stmt {
        case let .variableDeclaration(identifier, value, _):
            // void 类型的值不能赋给变量
            if value.type == .void {
                _ = generateExpressionSSA(value)
            } else {
                let valueResult = generateExpressionSSA(value)
                addIndent()
                buffer += "\(getCType(identifier.type)) \(identifier.name) = \(valueResult);\n"
            }
        case let .assignment(identifier, value):
            // void 类型的值不能赋值
            if value.type == .void {
                _ = generateExpressionSSA(value)
            } else {
                let valueResult = generateExpressionSSA(value)
                addIndent()
                buffer += "\(identifier.name) = \(valueResult);\n"
            }
        case let .expression(expr):
            _ = generateExpressionSSA(expr)
        }
    }

    private func arithmeticOpToC(_ op: ArithmeticOperator) -> String {
        switch op {
        case .plus: return "+"
        case .minus: return "-"
        case .multiply: return "*"
        case .divide: return "/"
        case .modulo: return "%"
        }
    }

    private func comparisonOpToC(_ op: ComparisonOperator) -> String {
        switch op {
        case .equal: return "=="
        case .notEqual: return "!="
        case .greater: return ">"
        case .less: return "<"
        case .greaterEqual: return ">="
        case .lessEqual: return "<="
        }
    }

    private func getCType(_ type: Type) -> String {
        switch type {
        case .int: return "int"
        case .float: return "double"
        case .string: return "const char*"
        case .bool: return "bool"
        case .void: return "void"
        case .function(_, _):
            fatalError("Function type not supported in getCType")
        case let .userDefined(name, _):
            return "struct \(name)"
        }
    }

    private func getFunctionReturnType(_ type: Type) -> String {
        switch type {
        case .function(_, let returns):
            return getCType(returns)
        default:
            fatalError("Expected function type")
        }
    }

    private func addIndent() {
        buffer += indent
    }

    private func withIndent(_ body: () -> Void) {
        let oldIndent = indent
        indent += "    "
        body()
        indent = oldIndent
    }

    private func generateTypeDeclaration(_ identifier: TypedIdentifierNode, _ parameters: [TypedIdentifierNode]) {
        buffer += "struct \(identifier.name) {\n"
        withIndent {
            for param in parameters {
                addIndent()
                buffer += "\(getCType(param.type)) \(param.name);\n"
            }
        }
        buffer += "};\n"
    }
}

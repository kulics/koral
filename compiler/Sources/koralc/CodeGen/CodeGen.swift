public class CodeGen {
    private let ast: TypedProgram
    private var indent: String = ""
    private var buffer: String = ""
    private var tempVarCounter = 0

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
            var globalInitFunctions: [(String, TypedExpressionNode)] = []  // 新增
            // 收集全局变量初始化表达式
            for node in nodes {
                if case let .globalVariable(identifier, value, _) = node {
                    let initFuncName = "_init_" + identifier.name
                    globalInitFunctions.append((initFuncName, value))
                }
            }
            
            // 先生成所有初始化函数声明
            for (funcName, value) in globalInitFunctions {
                buffer += "\(getCType(value.type)) \(funcName)();\n"
            }
            
            // 生成所有函数声明
            for node in nodes {
                if case let .globalFunction(identifier, params, _) = node {
                    generateFunctionDeclaration(identifier, params)
                }
            }
            buffer += "\n"
            
            // 生成初始化函数实现
            for (funcName, value) in globalInitFunctions {
                buffer += "\(getCType(value.type)) \(funcName)() {\n"
                withIndent {
                    let resultVar = generateExpressionSSA(value)
                    addIndent()
                    buffer += "return \(resultVar);\n"
                }
                buffer += "}\n\n"
            }
            
            // 生成其他全局实现
            for node in nodes {
                generateGlobalNode(node)
                buffer += "\n"
            }
        }
    }

    private func generateFunctionDeclaration(_ identifier: TypedIdentifierNode, _ params: [TypedIdentifierNode]) {
        let returnType = getFunctionReturnType(identifier.type)
        let paramList = params.map { getCType($0.type) + " " + $0.name }.joined(separator: ", ")
        buffer += "\(returnType) \(identifier.name)(\(paramList));\n"
    }

    private func generateGlobalNode(_ node: TypedGlobalNode) {
        switch node {
        case let .globalVariable(identifier, _, _):
            let cType = getCType(identifier.type)
            let initFuncName = "_init_" + identifier.name
            buffer += "\(cType) \(identifier.name) = \(initFuncName)();\n"
            
        case let .globalFunction(identifier, params, body):
            let returnType = getFunctionReturnType(identifier.type)
            let paramList = params.map { getCType($0.type) + " " + $0.name }.joined(separator: ", ")
            buffer += "\(returnType) \(identifier.name)(\(paramList)) {\n"
            withIndent {
                generateFunctionBody(body)
            }
            buffer += "}\n"
        }
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
        case let .intLiteral(value, _):
            return String(value)
            
        case let .floatLiteral(value, _):
            return String(value)
            
        case let .stringLiteral(value, _):
            return "\"\(value)\""
            
        case let .boolLiteral(value, _):
            return value ? "true" : "false"
            
        case let .variable(identifier):
            return identifier.name
            
        case let .block(statements, finalExpr, type):
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
            
        case let .arithmeticOp(left, op, right, type):
            let leftResult = generateExpressionSSA(left)
            let rightResult = generateExpressionSSA(right)
            let result = nextTemp()
            addIndent()
            buffer += "\(getCType(type)) \(result) = \(leftResult) \(arithmeticOpToC(op)) \(rightResult);\n"
            return result
            
        case let .comparisonOp(left, op, right, type):
            let leftResult = generateExpressionSSA(left)
            let rightResult = generateExpressionSSA(right)
            let result = nextTemp()
            addIndent()
            buffer += "\(getCType(type)) \(result) = \(leftResult) \(comparisonOpToC(op)) \(rightResult);\n"
            return result
            
        case let .ifExpr(condition, thenBranch, elseBranch, type):
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

        case let .whileExpr(condition, body, _):
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
        }
    }

    private func nextTemp() -> String {
        tempVarCounter += 1
        return "_t\(tempVarCounter)"
    }

    private func generateStatement(_ stmt: TypedStatementNode) {
        switch stmt {
        case let .variableDecl(identifier, value, _):
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
}

public class CodeGen {
    private let ast: TypedProgram
    private var indent: String = ""
    private var buffer: String = ""
    private var tempVarCounter = 0
    private var globalInitializations: [(String, TypedExpressionNode)] = []
    private var lifetimeScopeStack: [[(String, Type)]] = []

    public init(ast: TypedProgram) {
        self.ast = ast
    }

    private func pushScope() {
        lifetimeScopeStack.append([])
    }

    private func popScope() {
        let vars = lifetimeScopeStack.removeLast()
        // 反向遍历变量列表,对可变类型变量调用 destroy
        for (name, type) in vars.reversed() {
            if case .structure(let typeName, _, false) = type {
                addIndent()
                buffer += "\(typeName)_drop(\(name));\n"
            }
        }
    }

    private func registerVariable(_ name: String, _ type: Type) {
        lifetimeScopeStack[lifetimeScopeStack.count-1].append((name, type))
    }

    public func generate() -> String {
        buffer = """
        #include <stdio.h>
        #include <stdlib.h>
        #include <stdatomic.h>

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
                if case let .globalTypeDeclaration(identifier, parameters, isValue) = node {
                    generateTypeDeclaration(identifier, parameters, isValue)
                }
            }
            buffer += "\n"
            
            // 先生成所有函数声明
            for node in nodes {
                if case let .globalFunction(identifier, params, _) = node {
                    generateFunctionDeclaration(identifier, params)
                }
                if case let .givenDeclaration(_, methods) = node {
                    for method in methods {
                        generateFunctionDeclaration(method.identifier, method.parameters)
                    }
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
                if case let .givenDeclaration(_, methods) = node {
                    for method in methods {
                        generateGlobalFunction(method.identifier, method.parameters, method.body)
                    }
                }
            }

            // 生成 main 函数用于初始化全局变量
            if (!globalInitializations.isEmpty) {
                generateMainFunction()
            }
        }
    }

    private func generateMainFunction() {
        buffer += "\nint main() {\n"
        withIndent {
            // 生成全局变量初始化
            pushScope()
            for (name, value) in globalInitializations {
                let resultVar = generateExpressionSSA(value)
                addIndent()
                buffer += "\(name) = \(resultVar);\n"
            }
            popScope()
            // 如果需要的话，这里可以调用用户定义的 main 函数
            addIndent()
            buffer += "return 0;\n"
        }
        buffer += "}\n"
    }

    private func generateFunctionDeclaration(_ identifier: Symbol, _ params: [Symbol]) {
        let returnType = getFunctionReturnType(identifier.type)
        let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
        buffer += "\(returnType) \(identifier.name)(\(paramList));\n"
    }

    private func generateGlobalFunction(_ identifier: Symbol, 
                                     _ params: [Symbol], 
                                     _ body: TypedExpressionNode) {
        let returnType = getFunctionReturnType(identifier.type)
        let paramList = params.map { getParamCDecl($0) }.joined(separator: ", ")
        buffer += "\(returnType) \(identifier.name)(\(paramList)) {\n"

        withIndent {
            generateFunctionBody(body, params)
        }
        buffer += "}\n"
    }

    // 生成参数的 C 声明：类型若为 reference(T) 则 getCType 返回 T*
    private func getParamCDecl(_ param: Symbol) -> String {
        return "\(getCType(param.type)) \(param.name)"
    }

    private func generateFunctionBody(_ body: TypedExpressionNode, _ params: [Symbol]) {
        pushScope()
        for param in params {
            registerVariable(param.name, param.type)
        }
        let resultVar = generateExpressionSSA(body)
        let result = nextTemp()
        if case let .structure(typeName, _, false) = body.type {
            addIndent()
            if body.valueCategory == .lvalue {
                buffer += "\(getCType(body.type)) \(result) = \(typeName)_copy(&\(resultVar));\n"
            } else {
                buffer += "\(getCType(body.type)) \(result) = \(resultVar);\n"
            }
        } else if body.type != .void {
            addIndent()
            buffer += "\(getCType(body.type)) \(result) = \(resultVar);\n"
        }
        popScope()
        
        if body.type != .void {
            addIndent()
            buffer += "return \(result);\n"
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
            return value ? "1" : "0"
            
        case let .variable(identifier):
            return identifier.name
            
        case let .blockExpression(statements, finalExpr, _):
            return generateBlockScope(statements, finalExpr: finalExpr)
            
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
                    pushScope()
                    _ = generateExpressionSSA(thenBranch)
                    popScope()
                }
                addIndent()
                buffer += "} else {\n"
                withIndent {
                    pushScope()
                    _ = generateExpressionSSA(elseBranch)
                    popScope()
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
                    pushScope()
                    let thenResult = generateExpressionSSA(thenBranch)
                    addIndent()
                    buffer += "\(resultVar) = \(thenResult);\n"
                    popScope()
                }
                addIndent()
                buffer += "} else {\n"
                withIndent {
                    pushScope()
                    let elseResult = generateExpressionSSA(elseBranch)
                    addIndent()
                    buffer += "\(resultVar) = \(elseResult);\n"
                    popScope()
                }
                addIndent()
                buffer += "}\n"
                return resultVar
            }

        case let .call(callee, arguments, type):
            return generateCall(callee, arguments, type)
        case .methodReference:
            fatalError("Method reference not in call position is not supported yet")
        case let .referenceExpression(inner, _):
            // 取引用：对左值构建可寻址路径，然后取地址
            let lvaluePath = buildLValuePath(inner)
            return "&\(lvaluePath)"

        case let .whileExpression(condition, body, _):
            let labelPrefix = nextTemp()
            addIndent()
            buffer += "\(labelPrefix)_start: {\n"
            withIndent {
                let conditionVar = generateExpressionSSA(condition)
                addIndent()
                buffer += "if (!\(conditionVar)) { goto \(labelPrefix)_end; }\n"
                pushScope()
                _ = generateExpressionSSA(body)
                popScope()
                addIndent()
                buffer += "goto \(labelPrefix)_start;\n"
            }
            addIndent()
            buffer += "}\n"
            addIndent()
            buffer += "\(labelPrefix)_end: {\n"
            addIndent()
            buffer += "}\n"
            return ""
            
        case let .andExpression(left, right, _):
            let result = nextTemp()
            let leftResult = generateExpressionSSA(left)
            let endLabel = nextTemp()
            
            addIndent()
            buffer += "_Bool \(result);\n"
            addIndent()
            buffer += "if (!\(leftResult)) {\n"
            withIndent {
                addIndent()
                buffer += "\(result) = 0;\n"
                addIndent() 
                buffer += "goto \(endLabel);\n"
            }
            addIndent()
            buffer += "}\n"
            // 单独处理短路时的临时对象
            pushScope()
            let rightResult = generateExpressionSSA(right)
            addIndent()
            buffer += "\(result) = \(rightResult);\n"
            popScope()
            addIndent()
            buffer += "\(endLabel): {\n"
            addIndent()
            buffer += "}\n"
            return result
            
        case let .orExpression(left, right, _):
            let result = nextTemp()
            let leftResult = generateExpressionSSA(left) 
            let endLabel = nextTemp()
            
            addIndent()
            buffer += "_Bool \(result);\n"
            addIndent()
            buffer += "if (\(leftResult)) {\n"
            withIndent {
                addIndent()
                buffer += "\(result) = 1;\n"
                addIndent()
                buffer += "goto \(endLabel);\n"
            }
            addIndent()
            buffer += "}\n"
            // 单独处理短路时的临时对象
            pushScope()
            let rightResult = generateExpressionSSA(right)
            addIndent()
            buffer += "\(result) = \(rightResult);\n"
            popScope()
            addIndent()
            buffer += "\(endLabel): {\n"
            addIndent()
            buffer += "}\n"
            return result
            
        case let .notExpression(expr, _):
            let exprResult = generateExpressionSSA(expr)
            let result = nextTemp()
            addIndent()
            buffer += "_Bool \(result) = !\(exprResult);\n"
            return result

        case let .typeConstruction(identifier, arguments, _):
            let result = nextTemp()
            var argResults: [String] = []
            for arg in arguments {
                let argResult = generateExpressionSSA(arg)
                
                if case let .structure(typeName, _, false) = arg.type {
                    addIndent()
                    let argCopy = nextTemp()
                    if arg.valueCategory == .lvalue {
                        buffer += "\(getCType(arg.type)) \(argCopy) = \(typeName)_copy(&\(argResult));\n"
                    } else {
                        buffer += "\(getCType(arg.type)) \(argCopy) = \(argResult);\n"
                    }
                    argResults.append(argCopy)
                } else {
                    argResults.append(argResult)
                }
            }

            addIndent()
            buffer += "\(getCType(identifier.type)) \(result) = {"
            buffer += argResults.joined(separator: ", ")
            buffer += "};\n"
            return result
        case let .memberPath(source, path):
            return generateMemberPath(source, path)
        }
    }

    // 构建可作为左值的访问路径字符串，仅支持变量与成员访问
    private func buildLValuePath(_ expr: TypedExpressionNode) -> String {
        switch expr {
        case let .variable(identifier):
            return identifier.name
        case let .memberPath(source, path):
            var base = buildLValuePath(source)
            var curType = source.type
            for member in path {
                let op: String = { if case .reference(_) = curType { return "->" } else { return "." } }()
                base += "\(op)\(member.name)"
                curType = member.type
            }
            return base
        default:
            fatalError("ref requires lvalue (variable or memberAccess)")
        }
    }

    private func nextTemp() -> String {
        tempVarCounter += 1
        return "_t\(tempVarCounter)"
    }

    private func generateStatement(_ stmt: TypedStatementNode) {
        switch stmt {
        case let .variableDeclaration(identifier, value, _):
            let valueResult = generateExpressionSSA(value)
            // void 类型的值不能赋给变量
            if value.type != .void {
                // 如果是可变类型，增加引用计数
                if case .structure(let typeName, _, false) = identifier.type {
                    addIndent()
                    buffer += "\(getCType(identifier.type)) \(identifier.name) = "
                    if value.valueCategory == .lvalue {
                        buffer += "\(typeName)_copy(&\(valueResult));\n"
                    } else {
                        buffer += "\(valueResult);\n"
                    }
                    registerVariable(identifier.name, identifier.type)
                } else {
                    addIndent()
                    buffer += "\(getCType(identifier.type)) \(identifier.name) = \(valueResult);\n"
                }
            }
        case let .assignment(target, value):
            switch target {
            case .variable(let identifier):
                generateAssignment(identifier, value)
            case .memberAccess(let base, let memberPath):
                generateMemberAccessAssignment(base, memberPath, value)
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
        case .bool: return "_Bool"
        case .void: return "void"
        case .function(_, _):
            fatalError("Function type not supported in getCType")
        case let .structure(name, _, _):
            return "struct \(name)"
        case let .reference(inner):
            return "\(getCType(inner)) *"
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

    private func generateTypeDeclaration(_ identifier: Symbol, 
                                   _ parameters: [Symbol], 
                                   _ isValue: Bool) {
        let name = identifier.name
        // 所有类型都生成 struct，字段为值类型
        buffer += "struct \(name) {\n"
        withIndent {
            for param in parameters {
                addIndent()
                buffer += "\(getCType(param.type)) \(param.name);\n"
            }
        }
        buffer += "};\n\n"

        // 自动生成 copy/drop，仅 isValue==false 的类型需要递归处理
        buffer += "struct \(name) \(name)_copy(const struct \(name) *self) {\n"
        withIndent {
            buffer += "    struct \(name) result;\n"
            for param in parameters {
                buffer += "    result.\(param.name) = "
                if case let .structure(fieldTypeName, _, fieldIsVal) = param.type, !fieldIsVal {
                    buffer += "\(fieldTypeName)_copy(&self->\(param.name));\n"
                } else {
                    buffer += "self->\(param.name);\n"
                }
            }
            buffer += "    return result;\n"
        }
        buffer += "}\n\n"

        buffer += "void \(name)_drop(struct \(name) self) {\n"
        withIndent {
            for param in parameters {
                if case let .structure(fieldTypeName, _, fieldIsVal) = param.type, !fieldIsVal {
                    buffer += "    \(fieldTypeName)_drop(self.\(param.name));\n"
                }
            }
        }
        buffer += "}\n\n"
    }
    
    private func generateBlockScope(_ statements: [TypedStatementNode], finalExpr: TypedExpressionNode?) -> String {       
        pushScope()
        // 先处理所有语句
        for stmt in statements {
            generateStatement(stmt)
        }
        
        // 生成最终表达式
        var result = ""
        if let finalExpr = finalExpr {
            let temp = generateExpressionSSA(finalExpr)
            if finalExpr.type != .void {
                let resultVar = nextTemp()
                addIndent()
                buffer += "\(getCType(finalExpr.type)) \(resultVar) = \(temp);\n"
                result = resultVar
            }
        }
        popScope()
        return result
    }

    private func generateAssignment(_ identifier: Symbol, _ value: TypedExpressionNode) {
        if value.type == .void {
            _ = generateExpressionSSA(value)
            return
        }
        let valueResult = generateExpressionSSA(value)
        if case let .structure(typeName, _, false) = identifier.type {
            if value.valueCategory == .lvalue {
                let copyResult = nextTemp()
                addIndent()
                buffer += "\(getCType(value.type)) \(copyResult) = \(typeName)_copy(&\(valueResult));\n"
                addIndent()
                buffer += "\(typeName)_drop(\(identifier.name));\n"
                addIndent()
                buffer += "\(identifier.name) = \(copyResult);\n"
            } else {
                addIndent()
                buffer += "\(typeName)_drop(\(identifier.name));\n"
                addIndent()
                buffer += "\(identifier.name) = \(valueResult);\n"
            }
        } else {
            addIndent()
            buffer += "\(identifier.name) = \(valueResult);\n"
        }
    }

    private func generateMemberAccessAssignment(_ base: Symbol,
                     _ memberPath: [Symbol], _ value: TypedExpressionNode) {
        if value.type == .void {
            _ = generateExpressionSSA(value)
            return
        }
        let baseResult = base.name
        let valueResult = generateExpressionSSA(value)
        var accessPath = baseResult
        var curType = base.type
        for (index, item) in memberPath.enumerated() {
            let isLast = index == memberPath.count - 1
            let memberName = item.name
            let memberType = item.type
            let op: String = { if case .reference(_) = curType { return "->" } else { return "." } }()
            accessPath += "\(op)\(memberName)"
            curType = memberType
            if isLast, case let .structure(typeName, _, false) = memberType {
                if value.valueCategory == .lvalue {
                    let copyResult = nextTemp()
                    addIndent()
                    buffer += "\(getCType(value.type)) \(copyResult) = \(typeName)_copy(&\(valueResult));\n"
                    addIndent()
                    buffer += "\(typeName)_drop(\(accessPath));\n"
                    addIndent()
                    buffer += "\(accessPath) = \(copyResult);\n"
                } else {
                    addIndent()
                    buffer += "\(typeName)_drop(\(accessPath));\n"
                    addIndent()
                    buffer += "\(accessPath) = \(valueResult);\n"
                }
                return
            }
        }
        addIndent()
        buffer += "\(accessPath) = \(valueResult);\n"
    }

    private func generateCall(_ callee: TypedExpressionNode, _ arguments: [TypedExpressionNode], _ type: Type) -> String {
        if case let .methodReference(base, method, _) = callee {
            var allArgs = [base]
            allArgs.append(contentsOf: arguments)
            return generateFunctionCall(method, allArgs, type)
        }
        
        if case let .variable(identifier) = callee {
            return generateFunctionCall(identifier, arguments, type)
        }
        
        fatalError("Indirect call not supported yet")
    }

    private func generateFunctionCall(_ identifier: Symbol, _ arguments: [TypedExpressionNode], _ type: Type) -> String {
        var paramResults: [String] = []
        // struct类型参数传递用值，isValue==false 的 struct 参数自动递归 copy
        for arg in arguments {
            let result = generateExpressionSSA(arg)
            if case let .structure(typeName, _, false) = arg.type {
                if arg.valueCategory == .lvalue {
                    let copyResult = nextTemp()
                    addIndent()
                    buffer += "\(getCType(arg.type)) \(copyResult) = \(typeName)_copy(&\(result));\n"
                    paramResults.append(copyResult)
                } else {
                    paramResults.append(result)
                }
            } else {
                paramResults.append(result)
            }
        }
        addIndent()
        if (type == .void) {
            buffer += "\(identifier.name)("
            buffer += paramResults.joined(separator: ", ")
            buffer += ");\n"
            return ""
        } else {
            let result = nextTemp()
            buffer += "\(getCType(type)) \(result) = \(identifier.name)("
            buffer += paramResults.joined(separator: ", ")
            buffer += ");\n"
            return result
        }
    }
    
    private func generateMemberPath(_ source: TypedExpressionNode, _ path: [Symbol]) -> String {
        let sourceResult = generateExpressionSSA(source)
        var access = sourceResult
        var curType = source.type
        for member in path {
            let op: String = { if case .reference(_) = curType { return "->" } else { return "." } }()
            access += "\(op)\(member.name)"
            curType = member.type
        }
        let result = nextTemp()
        addIndent()
        buffer += "\(getCType(path.last?.type ?? .void)) \(result) = \(access);\n"
        return result
    }
}

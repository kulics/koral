public class CodeGen {
    private let ast: TypedProgram
    private var indent: String = ""
    private var buffer: String = ""
    private var tempVarCounter = 0
    private var globalInitializations: [(String, TypedExpressionNode)] = []
    private var rcscopeStack: [[(String, Type)]] = []

    public init(ast: TypedProgram) {
        self.ast = ast
    }

    private func pushScope() {
        rcscopeStack.append([])
    }

    private func popScope() {
        let vars = rcscopeStack.removeLast()
        // 反向遍历变量列表,对可变类型变量调用 destroy
        for (name, type) in vars.reversed() {
            if case .userDefined(let typeName, _, false) = type {
                addIndent()
                buffer += "\(typeName)_destroy(\(name));\n"
            }
        }
    }

    private func registerVariable(_ name: String, _ type: Type) {
        rcscopeStack[rcscopeStack.count-1].append((name, type))
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
        let paramList = params.map { getCType($0.type) + " " + $0.name }.joined(separator: ", ")
        buffer += "\(returnType) \(identifier.name)(\(paramList));\n"
    }

    private func generateGlobalFunction(_ identifier: Symbol, 
                                     _ params: [Symbol], 
                                     _ body: TypedExpressionNode) {
        let returnType = getFunctionReturnType(identifier.type)
        let paramList = params.map { getCType($0.type) + " " + $0.name }.joined(separator: ", ")
        buffer += "\(returnType) \(identifier.name)(\(paramList)) {\n"
        withIndent {
            generateFunctionBody(body, params)
        }
        buffer += "}\n"
    }

    private func generateFunctionBody(_ body: TypedExpressionNode, _ params: [Symbol]) {
        pushScope()
        for param in params {
            registerVariable(param.name, param.type)
        }
        let resultVar = generateExpressionSSA(body)
        if case let .userDefined(typeName, _, false) = body.type {
            addIndent()
            buffer += "\(typeName)_copy(\(resultVar));\n"
        }
        popScope()
        
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

        case let .functionCall(identifier, arguments, type):
            return generateFunctionCall(identifier, arguments, type)

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
                argResults.append(argResult)

                // 如果是引用类型,增加引用计数
                if case let .userDefined(typeName, _, false) = arg.type {
                    addIndent()
                    buffer += "\(typeName)_copy(\(argResult));\n"
                }
            }

            if case let .userDefined(typeName, parameters, false) = identifier.type {
                // 可变类型构造 - 现在返回指针
                addIndent()
                buffer += "\(getCType(identifier.type)) \(result) = \(typeName)_new();\n"
                
                // 初始化字段
                for (idx, arg) in argResults.enumerated() {
                    addIndent()
                    buffer += "\(result)->\(parameters[idx].name) = \(arg);\n"
                }

                registerVariable(result, identifier.type)
            } else {
                // 不可变类型构造保持不变
                addIndent()
                buffer += "\(getCType(identifier.type)) \(result) = {"
                buffer += argResults.joined(separator: ", ")
                buffer += "};\n"
            }
            return result
        case let .memberAccess(source, member):
            return generateMemberAccess(source, member)
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
                if case .userDefined(let typeName, _, false) = identifier.type {
                    addIndent()
                    buffer += "\(typeName)_copy(\(valueResult));\n"
                    registerVariable(identifier.name, identifier.type)
                }
                addIndent()
                buffer += "\(getCType(identifier.type)) \(identifier.name) = \(valueResult);\n"
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
        case let .userDefined(name, _, isValue):
            if isValue {
                return "struct \(name)"
            } else {
                return "struct \(name)*"
            }
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
        if isValue {
            // Handle value types
            buffer += "struct \(name) {\n"
            withIndent {
                for param in parameters {
                    addIndent()
                    buffer += "\(getCType(param.type)) \(param.name);\n"
                }
            }
            buffer += "};\n\n"
        } else {
            // Handle reference types
            buffer += "struct \(name) {\n"
            withIndent {
                addIndent()
                buffer += "atomic_size_t _rc_count;\n"  // Reference counting field
                for param in parameters {
                    addIndent()
                    buffer += "\(getCType(param.type)) \(param.name);\n"
                }
            }
            buffer += "};\n\n"
            
            buffer += """
            struct \(name)* \(name)_new() {
                struct \(name)* ptr = malloc(sizeof(struct \(name)));
                atomic_init(&ptr->_rc_count, 1);
                return ptr;
            }\n\n
            """
            buffer += """
            void \(name)_destroy(struct \(name)* value) {
                if (!value) return;
                if (atomic_fetch_sub(&value->_rc_count, 1) == 1) {\n
            """
            // Destroy reference type fields
            for param in parameters {
                withIndent {
                    if case let .userDefined(fieldTypeName, _, fieldIsVal) = param.type,
                        !fieldIsVal {
                        addIndent()
                        addIndent()
                        buffer += "\(fieldTypeName)_destroy(value->\(param.name));\n"
                    }
                }
            }
            
            buffer += """
                    free(value);
                }
            }
            
            struct \(name)* \(name)_copy(struct \(name)* other) {
                if (other) {
                    atomic_fetch_add(&other->_rc_count, 1);
                }
                return other;
            }\n\n
            """
        } 
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
        if case let .userDefined(typeName, _, false) = identifier.type {
            addIndent()
            buffer += "\(typeName)_destroy(\(identifier.name));\n"
            addIndent()
            buffer += "\(typeName)_copy(\(valueResult));\n"
        }
        addIndent()
        buffer += "\(identifier.name) = \(valueResult);\n"
    }

    private func generateMemberAccessAssignment(_ base: Symbol,
                     _ memberPath: [Symbol], _ value: TypedExpressionNode) {
        if value.type == .void {
            _ = generateExpressionSSA(value)
            return
        }
        
        // Start with the base variable
        let baseResult = base.name
        let valueResult = generateExpressionSSA(value)
        
        // Generate the full access path for the final assignment
        var accessPath = baseResult
        var currentType = base.type
        
        // Build up the access chain
        for (index, item) in memberPath.enumerated() {
            let isLast = index == memberPath.count - 1
            let memberName = item.name
            let memberType = item.type
            
            // Determine the access operator (. or ->)
            if case .userDefined(_, _, false) = currentType {
                accessPath += "->\(memberName)"
            } else {
                accessPath += ".\(memberName)"
            }
            
            // Update current type for next iteration
            currentType = memberType
            
            // If this is the last member and it's a reference type, handle memory management
            if isLast, case let .userDefined(typeName, _, false) = memberType {
                let tempRef = nextTemp()
                addIndent()
                buffer += "\(getCType(memberType))* \(tempRef) = &(\(accessPath));\n"
                addIndent()
                buffer += "\(typeName)_destroy(*\(tempRef));\n"
                addIndent()
                buffer += "*\(tempRef) = \(typeName)_copy(\(valueResult));\n"
                return
            }
        }
        
        // For value types or if there's no special memory management needed
        addIndent()
        buffer += "\(accessPath) = \(valueResult);\n"
    }

    private func generateFunctionCall(_ identifier: Symbol, _ arguments: [TypedExpressionNode], _ type: Type) -> String {
        var paramResults: [String] = []
        
        // 处理参数传递
        for arg in arguments {
            let result = generateExpressionSSA(arg)
            // 如果参数是引用类型且需要传递引用,使用复制构造
            if case let .userDefined(typeName, _, false) = arg.type {
                let copyResult = nextTemp()
                addIndent()
                buffer += "\(getCType(arg.type)) \(copyResult) = \(typeName)_copy(\(result));\n"
                paramResults.append(copyResult)
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
            if case .userDefined(_, _, false) = type {
                registerVariable(result, type)
            }
            return result
        }
    }
    
    private func generateMemberAccess(_ source: TypedExpressionNode, _ member: Symbol) -> String {
        let sourceResult = generateExpressionSSA(source)
        let result = nextTemp()
               
        addIndent()
        // If source expression is a reference type, use -> operator
        if case .userDefined(_, _, false) = source.type {
            buffer += "\(getCType(member.type)) \(result) = \(sourceResult)->\(member.name);\n"
        } else {
            buffer += "\(getCType(member.type)) \(result) = \(sourceResult).\(member.name);\n"
        }
        return result
    }
}

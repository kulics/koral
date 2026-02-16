/// 逃逸分析模块
/// 
/// 在代码生成阶段分析引用是否会逃逸出其源变量的作用域，
/// 自动决定数据分配在栈上还是堆上。
///
/// 逃逸分析采用两阶段方法：
/// 1. 预分析阶段：扫描函数体，识别所有可能逃逸的变量
/// 2. 代码生成阶段：根据预分析结果决定分配策略

/// 逃逸分析结果
public enum EscapeResult {
    case noEscape           // 不逃逸，可以栈分配
    case escapeToReturn     // 逃逸到返回值
    case escapeToField      // 逃逸到结构体字段
    case escapeToParameter  // 逃逸到函数参数（被存储）
    case unknown            // 无法确定，采用保守策略（假设逃逸）
}

/// 变量的逃逸信息
public struct EscapeInfo {
    public let variableName: String
    public let scopeLevel: Int
    public let escapeResult: EscapeResult
    
    public init(variableName: String, scopeLevel: Int, escapeResult: EscapeResult) {
        self.variableName = variableName
        self.scopeLevel = scopeLevel
        self.escapeResult = escapeResult
    }
}

/// 逃逸分析诊断报告
public struct EscapeDiagnostic {
    public let variableName: String
    public let reason: EscapeResult
    public let functionName: String
    
    public init(variableName: String, reason: EscapeResult, functionName: String) {
        self.variableName = variableName
        self.reason = reason
        self.functionName = functionName
    }
    
    /// 格式化诊断信息
    public func format() -> String {
        let reasonDescription: String
        switch reason {
        case .noEscape:
            reasonDescription = "does not escape"
        case .escapeToReturn:
            reasonDescription = "escapes to return value"
        case .escapeToField:
            reasonDescription = "escapes to struct field"
        case .escapeToParameter:
            reasonDescription = "escapes to function parameter"
        case .unknown:
            reasonDescription = "escape status unknown (conservative heap allocation)"
        }
        return "[escape-analysis] Variable '\(variableName)' \(reasonDescription) in function '\(functionName)'"
    }
}

/// 单个参数的逃逸状态
public enum ParameterEscapeState {
    case noEscape       // 参数不会逃逸
    case escapes        // 参数会逃逸（通过 init_memory、返回值、字段赋值等）
}

/// 一个函数的参数逃逸摘要
public struct FunctionEscapeSummary {
    /// 每个参数的逃逸状态，索引对应参数位置
    /// 对于方法：index 0 = self, index 1+ = 其他参数
    public let parameterStates: [ParameterEscapeState]
}

/// 全局逃逸分析的完整结果
public struct GlobalEscapeResult {
    /// 函数 DefId -> 参数逃逸摘要
    public let summaries: [UInt64: FunctionEscapeSummary]

    /// 函数 DefId -> 该函数中已标记为逃逸的变量名集合
    public let escapedVariablesPerFunction: [UInt64: [String: EscapeResult]]
}

/// 代码生成时的逃逸分析上下文
/// 
/// 追踪变量作用域层级和已标记为逃逸的变量，
/// 用于在生成引用相关代码时决定栈/堆分配策略。
public class EscapeContext {
    /// Compiler context for symbol metadata lookup
    public let context: CompilerContext?
    /// 当前函数的返回类型
    public var returnType: Type?
    
    /// 变量名 -> 作用域层级
    public var variableScopes: [String: Int] = [:]
    
    /// 当前作用域层级
    public var currentScopeLevel: Int = 0
    
    /// 已标记为逃逸的变量及其逃逸原因
    public var escapedVariables: [String: EscapeResult] = [:]
    
    /// 作用域栈，用于追踪每个作用域中声明的变量
    private var scopeStack: [[String]] = []
    
    /// 当前是否在返回语句上下文中
    public var inReturnContext: Bool = false
    
    /// 当前是否在结构体字段赋值上下文中
    public var inFieldAssignmentContext: Bool = false
    
    /// 是否启用逃逸分析报告
    public var reportingEnabled: Bool = false
    
    /// 当前正在分析的函数名
    public var currentFunctionName: String = ""
    
    /// 收集的诊断信息
    public private(set) var diagnostics: [EscapeDiagnostic] = []
    
    /// 全局摘要表引用（在全局分析阶段设置）
    public var globalSummaries: [UInt64: FunctionEscapeSummary]?
    
    /// MonomorphizedProgram 引用，用于静态方法查找
    public var program: MonomorphizedProgram?
    
    public init(reportingEnabled: Bool = false, context: CompilerContext? = nil) {
        self.reportingEnabled = reportingEnabled
        self.context = context
    }
    
    /// 进入新作用域
    public func enterScope() {
        currentScopeLevel += 1
        scopeStack.append([])
    }
    
    /// 离开作用域
    public func leaveScope() {
        // 清理当前作用域中的变量
        if let currentScopeVars = scopeStack.popLast() {
            for varName in currentScopeVars {
                variableScopes.removeValue(forKey: varName)
            }
        }
        currentScopeLevel = max(0, currentScopeLevel - 1)
    }
    
    /// 注册变量到当前作用域
    public func registerVariable(_ name: String) {
        variableScopes[name] = currentScopeLevel
        if !scopeStack.isEmpty {
            scopeStack[scopeStack.count - 1].append(name)
        }
    }
    
    /// 获取变量的作用域层级
    public func getScopeLevel(_ name: String) -> Int? {
        return variableScopes[name]
    }
    
    /// 标记变量为逃逸
    public func markEscaped(_ name: String, reason: EscapeResult) {
        escapedVariables[name] = reason
        
        // 如果启用了报告，记录诊断信息
        if reportingEnabled && reason != .noEscape {
            let diagnostic = EscapeDiagnostic(
                variableName: name,
                reason: reason,
                functionName: currentFunctionName
            )
            diagnostics.append(diagnostic)
        }
    }
    
    /// 检查变量是否逃逸
    public func isEscaped(_ name: String) -> Bool {
        return escapedVariables[name] != nil
    }
    
    /// 获取变量的逃逸原因
    public func getEscapeReason(_ name: String) -> EscapeResult? {
        return escapedVariables[name]
    }
    
    /// 重置上下文（用于新函数）
    public func reset(returnType: Type?, functionName: String = "") {
        self.returnType = returnType
        self.variableScopes = [:]
        self.currentScopeLevel = 0
        self.escapedVariables = [:]
        self.scopeStack = []
        self.inReturnContext = false
        self.inFieldAssignmentContext = false
        self.currentFunctionName = functionName
        self.globalSummaries = nil
        self.program = nil
    }
    
    /// 获取所有诊断信息的格式化输出
    public func getFormattedDiagnostics() -> String {
        return diagnostics.map { $0.format() }.joined(separator: "\n")
    }
    
    /// 清除所有诊断信息
    public func clearDiagnostics() {
        diagnostics = []
    }
    
    // MARK: - 逃逸分析核心逻辑
    
    /// 分析引用表达式是否会逃逸
    /// 
    /// 根据引用的源表达式和当前上下文，判断引用是否会逃逸出其源变量的作用域。
    /// 
    /// - Parameter inner: 被引用的表达式
    /// - Returns: 逃逸分析结果
    public func analyzeEscape(_ inner: TypedExpressionNode) -> EscapeResult {
        // 如果是 rvalue，总是需要堆分配（因为没有持久的内存地址）
        if inner.valueCategory == .rvalue {
            return .unknown
        }
        
        // 获取被引用的变量名
        guard let variableName = extractVariableName(from: inner) else {
            // 无法确定变量名，采用保守策略
            return .unknown
        }
        
        // 检查变量是否已被标记为逃逸
        if let existingReason = escapedVariables[variableName] {
            return existingReason
        }
        
        // 检查是否在返回语句上下文中
        if inReturnContext {
            // 检查返回类型是否是引用类型
            if let returnType = returnType, case .reference(_) = returnType {
                // 检查变量是否是局部变量（作用域层级 > 0）
                if let scopeLevel = variableScopes[variableName], scopeLevel > 0 {
                    markEscaped(variableName, reason: .escapeToReturn)
                    return .escapeToReturn
                }
            }
        }
        
        // 检查是否在结构体字段赋值上下文中
        if inFieldAssignmentContext {
            // 如果引用被存储到结构体字段，可能会逃逸
            if let scopeLevel = variableScopes[variableName], scopeLevel > 0 {
                markEscaped(variableName, reason: .escapeToField)
                return .escapeToField
            }
        }
        
        // 默认情况：不逃逸
        return .noEscape
    }
    
    /// 从表达式中提取变量名
    /// 
    /// - Parameter expr: 表达式
    /// - Returns: 变量名，如果无法提取则返回 nil
    private func extractVariableName(from expr: TypedExpressionNode) -> String? {
        switch expr {
        case .variable(let identifier):
            return context?.getName(identifier.defId)
        case .memberPath(let source, _):
            // 对于成员路径，提取源变量名
            return extractVariableName(from: source)
        case .derefExpression(let inner, _):
            // 对于解引用表达式，提取内部变量名
            return extractVariableName(from: inner)
        case .ptrExpression(let inner, _):
            return extractVariableName(from: inner)
        case .deptrExpression(let inner, _):
            return extractVariableName(from: inner)
        default:
            return nil
        }
    }
    
    /// 检查表达式是否引用了局部变量
    /// 
    /// - Parameter expr: 表达式
    /// - Returns: 如果引用了局部变量返回 true
    public func referencesLocalVariable(_ expr: TypedExpressionNode) -> Bool {
        guard let variableName = extractVariableName(from: expr) else {
            return false
        }
        
        // 检查变量是否是局部变量（作用域层级 > 0）
        if let scopeLevel = variableScopes[variableName], scopeLevel > 0 {
            return true
        }
        
        return false
    }
    
    /// 检查引用是否应该使用堆分配
    /// 
    /// 这是逃逸分析的主要入口点，用于在代码生成时决定分配策略。
    /// 
    /// - Parameter inner: 被引用的表达式
    /// - Returns: 如果应该使用堆分配返回 true，否则返回 false（使用栈分配）
    public func shouldUseHeapAllocation(_ inner: TypedExpressionNode) -> Bool {
        let result = analyzeEscape(inner)
        switch result {
        case .noEscape:
            return false
        case .escapeToReturn, .escapeToField, .escapeToParameter, .unknown:
            return true
        }
    }
    
    // MARK: - 预分析阶段
    
    /// 预分析函数体，识别所有可能逃逸的变量
    /// 
    /// 这个方法在代码生成之前调用，扫描整个函数体来识别：
    /// 1. 返回引用类型时，被引用的局部变量
    /// 2. 存储到结构体字段的引用所指向的局部变量
    /// 
    /// - Parameters:
    ///   - body: 函数体表达式
    ///   - params: 函数参数列表
    public func preAnalyze(body: TypedExpressionNode, params: [Symbol]) {
        // 首先注册参数（作用域层级 0，不会逃逸）
        for param in params {
            let name = context?.getName(param.defId) ?? "<unknown>"
            variableScopes[name] = 0
        }
        
        // 进入函数体作用域
        enterScope()
        
        // 分析函数体
        preAnalyzeExpression(body)
        
        // 离开作用域（但保留逃逸信息）
        leaveScope()
    }
    
    /// 预分析表达式，识别逃逸变量
    private func preAnalyzeExpression(_ expr: TypedExpressionNode) {
        switch expr {
        case .integerLiteral, .floatLiteral, .stringLiteral, .booleanLiteral:
            break

        case .interpolatedString(let parts, _):
            for part in parts {
                if case .expression(let expr) = part {
                    preAnalyzeExpression(expr)
                }
            }
            
        case .variable:
            break
            
        case .castExpression(let inner, _):
            preAnalyzeExpression(inner)
            
        case .arithmeticExpression(let left, _, let right, _),
             .wrappingArithmeticExpression(let left, _, let right, _),
             .wrappingShiftExpression(let left, _, let right, _):
            preAnalyzeExpression(left)
            preAnalyzeExpression(right)
            
        case .comparisonExpression(let left, _, let right, _):
            preAnalyzeExpression(left)
            preAnalyzeExpression(right)
            
        case .letExpression(let identifier, let value, let body, _):
            preAnalyzeExpression(value)
            // 注册变量到当前作用域
            let name = context?.getName(identifier.defId) ?? "<unknown>"
            variableScopes[name] = currentScopeLevel
            if !scopeStack.isEmpty {
                scopeStack[scopeStack.count - 1].append(name)
            }
            preAnalyzeExpression(body)
            
        case .andExpression(let left, let right, _):
            preAnalyzeExpression(left)
            preAnalyzeExpression(right)
            
        case .orExpression(let left, let right, _):
            preAnalyzeExpression(left)
            preAnalyzeExpression(right)
            
        case .notExpression(let inner, _):
            preAnalyzeExpression(inner)
            
        case .bitwiseExpression(let left, _, let right, _):
            preAnalyzeExpression(left)
            preAnalyzeExpression(right)
            
        case .bitwiseNotExpression(let inner, _):
            preAnalyzeExpression(inner)
            
        case .derefExpression(let inner, _):
            preAnalyzeExpression(inner)

        case .ptrExpression(let inner, _):
            preAnalyzeExpression(inner)

        case .deptrExpression(let inner, _):
            preAnalyzeExpression(inner)
            
        case .referenceExpression(let inner, _):
            // 检查这个引用是否会逃逸（基于当前上下文）
            preAnalyzeExpression(inner)
            
        case .blockExpression(let statements, let finalExpr, _):
            enterScope()
            for stmt in statements {
                preAnalyzeStatement(stmt)
            }
            if let finalExpr = finalExpr {
                // 如果函数返回引用类型，检查最终表达式
                if let returnType = returnType, case .reference(_) = returnType {
                    checkReturnEscape(finalExpr)
                }
                preAnalyzeExpression(finalExpr)
            }
            leaveScope()
            
        case .ifExpression(let condition, let thenBranch, let elseBranch, _):
            preAnalyzeExpression(condition)
            preAnalyzeExpression(thenBranch)
            if let elseBranch = elseBranch {
                preAnalyzeExpression(elseBranch)
            }
            
        case .ifPatternExpression(let subject, let pattern, _, let thenBranch, let elseBranch, _):
            preAnalyzeExpression(subject)
            preAnalyzePattern(pattern)
            enterScope()
            preAnalyzeExpression(thenBranch)
            leaveScope()
            if let elseBranch = elseBranch {
                preAnalyzeExpression(elseBranch)
            }
            
        case .call(let callee, let arguments, _):
            preAnalyzeExpression(callee)
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            // Inter-procedural escape propagation: consult callee's summary
            if let summaries = globalSummaries {
                var calleeDefId: UInt64? = nil
                var selfArg: TypedExpressionNode? = nil
                switch callee {
                case .methodReference(let base, let method, _, _, _):
                    calleeDefId = method.defId.id
                    selfArg = base
                case .variable(let identifier):
                    if case .function = identifier.kind {
                        calleeDefId = identifier.defId.id
                    }
                default:
                    break
                }
                if let cDefId = calleeDefId, let summary = summaries[cDefId] {
                    // For method calls: index 0 = self, index 1+ = arguments
                    // For regular calls: index i = arguments[i]
                    if let selfArg = selfArg {
                        // Method call
                        if summary.parameterStates.count > 0 && summary.parameterStates[0] == .escapes {
                            markRefArgumentAsEscaping(selfArg)
                        }
                        for (i, arg) in arguments.enumerated() {
                            let paramIdx = i + 1
                            if paramIdx < summary.parameterStates.count && summary.parameterStates[paramIdx] == .escapes {
                                markRefArgumentAsEscaping(arg)
                            }
                        }
                    } else {
                        // Regular function call
                        for (i, arg) in arguments.enumerated() {
                            if i < summary.parameterStates.count && summary.parameterStates[i] == .escapes {
                                markRefArgumentAsEscaping(arg)
                            }
                        }
                    }
                }
            }
            
        case .genericCall(_, _, let arguments, _):
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            
        case .methodReference(let base, _, _, _, _):
            preAnalyzeExpression(base)
            
        case .traitMethodPlaceholder(_, _, let base, _, _):
            preAnalyzeExpression(base)
            
        case .traitObjectConversion(let inner, _, _, _, _):
            preAnalyzeExpression(inner)

        case .traitMethodCall(let receiver, _, _, _, let arguments, _):
            preAnalyzeExpression(receiver)
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            // Conservative: trait method calls can't be statically resolved,
            // so mark all ref arguments as escaping
            if globalSummaries != nil {
                markRefArgumentAsEscaping(receiver)
                for arg in arguments {
                    markRefArgumentAsEscaping(arg)
                }
            }
            
        case .staticMethodCall(let baseType, let methodName, _, let arguments, _):
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            // Inter-procedural: look up static method summary
            if let summaries = globalSummaries, let prog = program {
                let typeName = context?.getTypeName(baseType) ?? ""
                if let defId = prog.lookupStaticMethod(typeName: typeName, methodName: methodName) {
                    if let summary = summaries[defId.id] {
                        for (i, arg) in arguments.enumerated() {
                            if i < summary.parameterStates.count && summary.parameterStates[i] == .escapes {
                                markRefArgumentAsEscaping(arg)
                            }
                        }
                    }
                }
            }
            
        case .whileExpression(let condition, let body, _):
            preAnalyzeExpression(condition)
            enterScope()
            preAnalyzeExpression(body)
            leaveScope()
            
        case .whilePatternExpression(let subject, let pattern, _, let body, _):
            preAnalyzeExpression(subject)
            preAnalyzePattern(pattern)
            enterScope()
            preAnalyzeExpression(body)
            leaveScope()
            
        case .typeConstruction(_, _, let arguments, let type):
            for arg in arguments {
                preAnalyzeExpression(arg)
                // 检查是否将引用传递给结构体构造函数
                // 如果结构体被返回，引用可能逃逸
                checkTypeConstructionEscape(arg: arg, constructedType: type)
            }
            
        case .memberPath(let source, _):
            preAnalyzeExpression(source)
            
        case .subscriptExpression(let base, let arguments, _, _):
            preAnalyzeExpression(base)
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            
        case .unionConstruction(_, _, let arguments):
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            
        case .intrinsicCall(let intrinsic):
            preAnalyzeIntrinsic(intrinsic)
            
        case .matchExpression(let subject, let cases, _):
            preAnalyzeExpression(subject)
            for matchCase in cases {
                enterScope()
                preAnalyzePattern(matchCase.pattern)
                preAnalyzeExpression(matchCase.body)
                leaveScope()
            }
            
        case .lambdaExpression(_, let captures, let body, _):
            // Lambda 表达式：被捕获的变量应该标记为逃逸
            for capture in captures {
                let name = context?.getName(capture.symbol.defId) ?? "<unknown>"
                markEscaped(name, reason: .escapeToField)
            }
            // 分析 Lambda 体
            enterScope()
            preAnalyzeExpression(body)
            leaveScope()
        }
    }
    
    /// 预分析语句
    private func preAnalyzeStatement(_ stmt: TypedStatementNode) {
        switch stmt {
        case .variableDeclaration(let identifier, let value, _):
            preAnalyzeExpression(value)
            // 注册变量到当前作用域
            let name = context?.getName(identifier.defId) ?? "<unknown>"
            variableScopes[name] = currentScopeLevel
            if !scopeStack.isEmpty {
                scopeStack[scopeStack.count - 1].append(name)
            }
            
        case .assignment(let target, _, let value):
            preAnalyzeExpression(target)
            preAnalyzeExpression(value)
            // 检查是否是结构体字段赋值
            checkFieldAssignmentEscape(target: target, value: value)

        case .deptrAssignment(let pointer, _, let value):
            preAnalyzeExpression(pointer)
            preAnalyzeExpression(value)
            // deptr assignment 和 init_memory 本质相同：把值写入指针目标，
            // 值脱离当前栈帧的生命周期管理。递归检查 value 中的引用逃逸。
            checkPointerStoreEscape(value)
            
        case .expression(let expr):
            preAnalyzeExpression(expr)
            
        case .return(let value):
            if let value = value {
                preAnalyzeExpression(value)
                // 检查返回值是否导致逃逸
                if let returnType = returnType, case .reference(_) = returnType {
                    checkReturnEscape(value)
                }
            }
            
        case .break, .continue:
            break
        }
    }
    
    /// 预分析模式匹配
    private func preAnalyzePattern(_ pattern: TypedPattern) {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
            break
        case .variable(let symbol):
            let name = context?.getName(symbol.defId) ?? "<unknown>"
            variableScopes[name] = currentScopeLevel
            if !scopeStack.isEmpty {
                scopeStack[scopeStack.count - 1].append(name)
            }
        case .unionCase(_, _, let elements):
            for element in elements {
                preAnalyzePattern(element)
            }
        case .comparisonPattern:
            // Comparison patterns don't have expressions to analyze
            break
        case .andPattern(let left, let right):
            preAnalyzePattern(left)
            preAnalyzePattern(right)
        case .orPattern(let left, let right):
            preAnalyzePattern(left)
            preAnalyzePattern(right)
        case .notPattern(let inner):
            preAnalyzePattern(inner)
        case .structPattern(_, let elements):
            for element in elements {
                preAnalyzePattern(element)
            }
        }
    }
    
    /// 预分析内置函数调用
    private func preAnalyzeIntrinsic(_ intrinsic: TypedIntrinsic) {
        switch intrinsic {
        case .allocMemory(let count, _):
            preAnalyzeExpression(count)
        case .deallocMemory(let ptr):
            preAnalyzeExpression(ptr)
        case .copyMemory(let dest, let src, let count):
            preAnalyzeExpression(dest)
            preAnalyzeExpression(src)
            preAnalyzeExpression(count)
        case .moveMemory(let dest, let src, let count):
            preAnalyzeExpression(dest)
            preAnalyzeExpression(src)
            preAnalyzeExpression(count)
        case .refCount(let val):
            preAnalyzeExpression(val)
        case .downgradeRef(let val, _):
            preAnalyzeExpression(val)
        case .upgradeRef(let val, _):
            preAnalyzeExpression(val)
        case .initMemory(let ptr, let val):
            preAnalyzeExpression(ptr)
            preAnalyzeExpression(val)
            // When a value is stored to a pointer via init_memory, any ref
            // inside that value escapes — the pointer target (e.g. List storage)
            // may outlive the current scope. This covers List.push, Set.insert,
            // Map.set, etc. which all store elements through init_memory.
            checkPointerStoreEscape(val)
        case .deinitMemory(let ptr):
            preAnalyzeExpression(ptr)
        case .takeMemory(let ptr):
            preAnalyzeExpression(ptr)
        case .nullPtr:
            break  // No expressions to analyze
        }
    }
    
    /// 检查返回值是否导致局部变量逃逸
    /// 
    /// 当函数返回引用类型时，检查返回的引用是否指向局部变量。
    /// 如果是，标记该变量为逃逸。
    private func checkReturnEscape(_ expr: TypedExpressionNode) {
        switch expr {
        case .referenceExpression(let inner, _):
            // 直接返回引用表达式
            if let varName = extractVariableName(from: inner) {
                if let scopeLevel = variableScopes[varName], scopeLevel > 0 {
                    markEscaped(varName, reason: .escapeToReturn)
                }
            }
            
        case .variable(let identifier):
            // 返回一个引用类型的变量
            if case .reference(let innerType) = identifier.type {
                // 这个变量本身是引用类型，检查它是否指向局部变量
                // 这种情况比较复杂，需要追踪引用的来源
                // 目前采用保守策略：如果变量是局部的且类型是引用，标记为逃逸
                let name = context?.getName(identifier.defId) ?? "<unknown>"
                if let scopeLevel = variableScopes[name], scopeLevel > 0 {
                    // 检查这个引用变量的值是否来自局部变量
                    // 由于我们在预分析阶段，无法完全追踪，采用保守策略
                    _ = innerType // 使用变量避免警告
                }
            }
            
        case .blockExpression(_, let finalExpr, _):
            if let finalExpr = finalExpr {
                checkReturnEscape(finalExpr)
            }
            
        case .ifExpression(_, let thenBranch, let elseBranch, _):
            checkReturnEscape(thenBranch)
            if let elseBranch = elseBranch {
                checkReturnEscape(elseBranch)
            }
            
        case .ifPatternExpression(_, _, _, let thenBranch, let elseBranch, _):
            checkReturnEscape(thenBranch)
            if let elseBranch = elseBranch {
                checkReturnEscape(elseBranch)
            }
            
        case .letExpression(_, _, let body, _):
            checkReturnEscape(body)
            
        case .matchExpression(_, let cases, _):
            for matchCase in cases {
                checkReturnEscape(matchCase.body)
            }
            
        default:
            break
        }
    }
    
    /// 检查结构体字段赋值是否导致局部变量逃逸
    /// 
    /// 当引用被存储到结构体字段时，检查引用是否指向局部变量。
    /// 如果是，标记该变量为逃逸。
    private func checkFieldAssignmentEscape(target: TypedExpressionNode, value: TypedExpressionNode) {
        // 检查目标是否是结构体字段
        guard isStructFieldTarget(target) else { return }
        
        // 检查值是否是引用类型
        guard case .reference(_) = value.type else { return }
        
        // 检查值是否是引用表达式或引用类型变量
        switch value {
        case .referenceExpression(let inner, _):
            if let varName = extractVariableName(from: inner) {
                if let scopeLevel = variableScopes[varName], scopeLevel > 0 {
                    markEscaped(varName, reason: .escapeToField)
                }
            }
            
        case .variable(let identifier):
            // 如果是引用类型的变量，可能需要追踪其来源
            // 目前采用保守策略
            if case .reference(_) = identifier.type {
                // 变量本身是引用类型，检查它是否是局部变量
                let name = context?.getName(identifier.defId) ?? "<unknown>"
                if let scopeLevel = variableScopes[name], scopeLevel > 0 {
                    // 这个引用变量被存储到字段，可能导致逃逸
                    // 但我们需要追踪这个引用指向的原始变量
                    // 目前采用保守策略，不标记（因为引用本身可能来自参数）
                }
            }
            
        default:
            break
        }
    }
    
    /// 检查表达式是否是结构体字段目标
    private func isStructFieldTarget(_ target: TypedExpressionNode) -> Bool {
        switch target {
        case .memberPath(let source, let path):
            if !path.isEmpty {
                if case .structure(_) = source.type {
                    return true
                }
                if case .union(_) = source.type {
                    return true
                }
            }
            return false
        default:
            return false
        }
    }
    
    /// 检查类型构造是否导致引用逃逸
    /// 
    /// 当引用被传递给结构体构造函数时，如果结构体可能被返回或存储，
    /// 引用指向的变量可能逃逸。
    private func checkTypeConstructionEscape(arg: TypedExpressionNode, constructedType: Type) {
        // 只检查引用类型的参数
        guard case .reference(_) = arg.type else { return }
        
        switch arg {
        case .referenceExpression(let inner, _):
            // 直接传递引用表达式给构造函数
            if let varName = extractVariableName(from: inner) {
                if let scopeLevel = variableScopes[varName], scopeLevel > 0 {
                    // 引用被传递给结构体构造函数，可能逃逸
                    // 采用保守策略：标记为逃逸
                    markEscaped(varName, reason: .escapeToField)
                }
            }
            
        case .variable(let identifier):
            // 传递引用类型的变量给构造函数
            // 这种情况需要追踪引用的来源
            // 目前采用保守策略
            _ = identifier
            _ = constructedType
            
        default:
            break
        }
    }

    /// 检查写入指针目标的值是否导致引用逃逸
    ///
    /// 当值被写入指针目标时（init_memory 或 deptr assignment），该值脱离了
    /// 当前栈帧的生命周期管理。递归检查值及其构造函数参数中是否包含
    /// `ref local_var` 或参数变量，如果是则标记为逃逸。
    ///
    /// 覆盖场景：
    /// - `init_memory(ptr, ref local_var)` — 直接存储引用
    /// - `init_memory(ptr, SomeType(ref local_var))` — 引用包在构造函数里
    /// - `deptr ptr = SomeType.Variant(value)` — value 是参数变量（用于 summary）
    private func checkPointerStoreEscape(_ val: TypedExpressionNode) {
        switch val {
        case .referenceExpression(let inner, _):
            if let varName = extractVariableName(from: inner) {
                if variableScopes[varName] != nil {
                    // scopeLevel > 0: 局部变量，标记逃逸
                    // scopeLevel == 0: 参数变量，标记逃逸（用于 summary 构建）
                    markEscaped(varName, reason: .escapeToParameter)
                }
            }
        case .variable(let identifier):
            // 参数变量直接传入（不包在 ref 里），用于 summary 构建
            if case .reference = identifier.type {
                let varName = context?.getName(identifier.defId) ?? "<unknown>"
                if let scopeLevel = variableScopes[varName], scopeLevel == 0 {
                    markEscaped(varName, reason: .escapeToParameter)
                }
            }
        case .typeConstruction(_, _, let arguments, _):
            // 递归检查构造函数参数，如 SetBucket.Occupied(value)
            for arg in arguments {
                checkPointerStoreEscape(arg)
            }
        case .unionConstruction(_, _, let arguments):
            for arg in arguments {
                checkPointerStoreEscape(arg)
            }
        default:
            break
        }
    }

    /// 标记参数表达式中的 ref local_var 为逃逸
    ///
    /// 当调用一个函数且该函数的某个参数被标记为逃逸时，
    /// 检查对应的实参是否包含 `ref local_var`，如果是则标记该局部变量为逃逸。
    private func markRefArgumentAsEscaping(_ arg: TypedExpressionNode) {
        switch arg {
        case .referenceExpression(let inner, _):
            if let varName = extractVariableName(from: inner) {
                if let scopeLevel = variableScopes[varName], scopeLevel > 0 {
                    markEscaped(varName, reason: .escapeToParameter)
                }
            }
        default:
            break
        }
    }
}


// MARK: - Global Escape Analyzer

/// 全局逃逸分析器
/// 
/// 在代码生成之前对所有函数进行一次全局逃逸分析 pass，
/// 按调用图逆拓扑序分析所有函数，为每个函数的参数生成逃逸摘要。
public class GlobalEscapeAnalyzer {
    private let context: CompilerContext
    private let program: MonomorphizedProgram
    private var summaries: [UInt64: FunctionEscapeSummary] = [:]
    private var escapedVariablesPerFunction: [UInt64: [String: EscapeResult]] = [:]
    private var callGraph: [UInt64: Set<UInt64>] = [:]
    private var functionInfo: [UInt64: (identifier: Symbol, params: [Symbol], body: TypedExpressionNode)] = [:]

    public init(context: CompilerContext, program: MonomorphizedProgram) {
        self.context = context
        self.program = program
    }

    // MARK: - Entry Point

    /// 运行全局逃逸分析，返回完整结果
    public func analyze() -> GlobalEscapeResult {
        // Step 1: Collect all functions
        collectFunctions()

        // Step 2: Build call graph
        buildCallGraph()

        // Step 3: Compute reverse topological order (with SCC handling)
        let order = computeReverseTopologicalOrder()

        // Step 4: Analyze functions in order (callees before callers)
        for defId in order {
            guard let info = functionInfo[defId] else { continue }
            analyzeFunction(defId: defId, identifier: info.identifier, params: info.params, body: info.body)
        }

        // Step 5: Return the complete result
        return GlobalEscapeResult(
            summaries: summaries,
            escapedVariablesPerFunction: escapedVariablesPerFunction
        )
    }

    // MARK: - Function Collection

    /// 收集所有函数信息
    private func collectFunctions() {
        for node in program.globalNodes {
            switch node {
            case .globalFunction(let identifier, let params, let body):
                functionInfo[identifier.defId.id] = (identifier: identifier, params: params, body: body)

            case .givenDeclaration(let type, let methods):
                if context.containsGenericParameter(type) { continue }
                for method in methods {
                    functionInfo[method.identifier.defId.id] = (
                        identifier: method.identifier,
                        params: method.parameters,
                        body: method.body
                    )
                }

            default:
                break
            }
        }
    }

    // MARK: - Call Graph Building

    /// 构建调用图
    private func buildCallGraph() {
        for (defId, info) in functionInfo {
            callGraph[defId] = []
            extractCallsFromExpression(info.body, callerDefId: defId)
        }
    }

    /// 从 callee 表达式中提取被调用函数的 DefId
    private func extractCalleeDefId(from callee: TypedExpressionNode) -> UInt64? {
        switch callee {
        case .methodReference(_, let method, _, _, _):
            return method.defId.id
        case .variable(let identifier):
            if case .function = identifier.kind {
                return identifier.defId.id
            }
            return nil
        default:
            return nil
        }
    }

    /// 递归遍历表达式，提取所有调用边加入调用图
    private func extractCallsFromExpression(_ expr: TypedExpressionNode, callerDefId: UInt64) {
        switch expr {
        case .integerLiteral, .floatLiteral, .stringLiteral, .booleanLiteral:
            break

        case .interpolatedString(let parts, _):
            for part in parts {
                if case .expression(let expr) = part {
                    extractCallsFromExpression(expr, callerDefId: callerDefId)
                }
            }

        case .variable:
            break

        case .castExpression(let inner, _):
            extractCallsFromExpression(inner, callerDefId: callerDefId)

        case .arithmeticExpression(let left, _, let right, _),
             .wrappingArithmeticExpression(let left, _, let right, _),
             .wrappingShiftExpression(let left, _, let right, _):
            extractCallsFromExpression(left, callerDefId: callerDefId)
            extractCallsFromExpression(right, callerDefId: callerDefId)

        case .comparisonExpression(let left, _, let right, _):
            extractCallsFromExpression(left, callerDefId: callerDefId)
            extractCallsFromExpression(right, callerDefId: callerDefId)

        case .letExpression(_, let value, let body, _):
            extractCallsFromExpression(value, callerDefId: callerDefId)
            extractCallsFromExpression(body, callerDefId: callerDefId)

        case .andExpression(let left, let right, _),
             .orExpression(let left, let right, _):
            extractCallsFromExpression(left, callerDefId: callerDefId)
            extractCallsFromExpression(right, callerDefId: callerDefId)

        case .notExpression(let inner, _),
             .bitwiseNotExpression(let inner, _):
            extractCallsFromExpression(inner, callerDefId: callerDefId)

        case .bitwiseExpression(let left, _, let right, _):
            extractCallsFromExpression(left, callerDefId: callerDefId)
            extractCallsFromExpression(right, callerDefId: callerDefId)

        case .derefExpression(let inner, _),
             .ptrExpression(let inner, _),
             .deptrExpression(let inner, _),
             .referenceExpression(let inner, _):
            extractCallsFromExpression(inner, callerDefId: callerDefId)

        case .blockExpression(let statements, let finalExpr, _):
            for stmt in statements {
                extractCallsFromStatement(stmt, callerDefId: callerDefId)
            }
            if let finalExpr = finalExpr {
                extractCallsFromExpression(finalExpr, callerDefId: callerDefId)
            }

        case .ifExpression(let condition, let thenBranch, let elseBranch, _):
            extractCallsFromExpression(condition, callerDefId: callerDefId)
            extractCallsFromExpression(thenBranch, callerDefId: callerDefId)
            if let elseBranch = elseBranch {
                extractCallsFromExpression(elseBranch, callerDefId: callerDefId)
            }

        case .ifPatternExpression(let subject, _, _, let thenBranch, let elseBranch, _):
            extractCallsFromExpression(subject, callerDefId: callerDefId)
            extractCallsFromExpression(thenBranch, callerDefId: callerDefId)
            if let elseBranch = elseBranch {
                extractCallsFromExpression(elseBranch, callerDefId: callerDefId)
            }

        case .call(let callee, let arguments, _):
            // Extract callee DefId and add edge
            if let calleeDefId = extractCalleeDefId(from: callee) {
                callGraph[callerDefId]?.insert(calleeDefId)
            }
            // Recurse into callee and arguments
            extractCallsFromExpression(callee, callerDefId: callerDefId)
            for arg in arguments {
                extractCallsFromExpression(arg, callerDefId: callerDefId)
            }

        case .genericCall(_, _, let arguments, _):
            for arg in arguments {
                extractCallsFromExpression(arg, callerDefId: callerDefId)
            }

        case .methodReference(let base, _, _, _, _):
            extractCallsFromExpression(base, callerDefId: callerDefId)

        case .traitMethodPlaceholder(_, _, let base, _, _):
            extractCallsFromExpression(base, callerDefId: callerDefId)

        case .traitObjectConversion(let inner, _, _, _, _):
            extractCallsFromExpression(inner, callerDefId: callerDefId)

        case .traitMethodCall(let receiver, _, _, _, let arguments, _):
            // Do NOT add edge for trait method calls (can't statically resolve)
            extractCallsFromExpression(receiver, callerDefId: callerDefId)
            for arg in arguments {
                extractCallsFromExpression(arg, callerDefId: callerDefId)
            }

        case .staticMethodCall(let baseType, let methodName, _, let arguments, _):
            // Try to look up the static method DefId
            let typeName = context.getTypeName(baseType)
            if let defId = program.lookupStaticMethod(typeName: typeName, methodName: methodName) {
                callGraph[callerDefId]?.insert(defId.id)
            }
            // Recurse into arguments
            for arg in arguments {
                extractCallsFromExpression(arg, callerDefId: callerDefId)
            }

        case .whileExpression(let condition, let body, _):
            extractCallsFromExpression(condition, callerDefId: callerDefId)
            extractCallsFromExpression(body, callerDefId: callerDefId)

        case .whilePatternExpression(let subject, _, _, let body, _):
            extractCallsFromExpression(subject, callerDefId: callerDefId)
            extractCallsFromExpression(body, callerDefId: callerDefId)

        case .typeConstruction(_, _, let arguments, _):
            for arg in arguments {
                extractCallsFromExpression(arg, callerDefId: callerDefId)
            }

        case .memberPath(let source, _):
            extractCallsFromExpression(source, callerDefId: callerDefId)

        case .subscriptExpression(let base, let arguments, _, _):
            extractCallsFromExpression(base, callerDefId: callerDefId)
            for arg in arguments {
                extractCallsFromExpression(arg, callerDefId: callerDefId)
            }

        case .unionConstruction(_, _, let arguments):
            for arg in arguments {
                extractCallsFromExpression(arg, callerDefId: callerDefId)
            }

        case .intrinsicCall(let intrinsic):
            extractCallsFromIntrinsic(intrinsic, callerDefId: callerDefId)

        case .matchExpression(let subject, let cases, _):
            extractCallsFromExpression(subject, callerDefId: callerDefId)
            for matchCase in cases {
                extractCallsFromExpression(matchCase.body, callerDefId: callerDefId)
            }

        case .lambdaExpression(_, _, let body, _):
            // Do NOT add lambda calls to call graph, but recurse into body
            extractCallsFromExpression(body, callerDefId: callerDefId)
        }
    }

    /// 递归遍历语句，提取调用边
    private func extractCallsFromStatement(_ stmt: TypedStatementNode, callerDefId: UInt64) {
        switch stmt {
        case .variableDeclaration(_, let value, _):
            extractCallsFromExpression(value, callerDefId: callerDefId)

        case .assignment(let target, _, let value):
            extractCallsFromExpression(target, callerDefId: callerDefId)
            extractCallsFromExpression(value, callerDefId: callerDefId)

        case .deptrAssignment(let pointer, _, let value):
            extractCallsFromExpression(pointer, callerDefId: callerDefId)
            extractCallsFromExpression(value, callerDefId: callerDefId)

        case .expression(let expr):
            extractCallsFromExpression(expr, callerDefId: callerDefId)

        case .return(let value):
            if let value = value {
                extractCallsFromExpression(value, callerDefId: callerDefId)
            }

        case .break, .continue:
            break
        }
    }

    /// 递归遍历内置函数调用，提取调用边
    private func extractCallsFromIntrinsic(_ intrinsic: TypedIntrinsic, callerDefId: UInt64) {
        switch intrinsic {
        case .allocMemory(let count, _):
            extractCallsFromExpression(count, callerDefId: callerDefId)
        case .deallocMemory(let ptr):
            extractCallsFromExpression(ptr, callerDefId: callerDefId)
        case .copyMemory(let dest, let src, let count):
            extractCallsFromExpression(dest, callerDefId: callerDefId)
            extractCallsFromExpression(src, callerDefId: callerDefId)
            extractCallsFromExpression(count, callerDefId: callerDefId)
        case .moveMemory(let dest, let src, let count):
            extractCallsFromExpression(dest, callerDefId: callerDefId)
            extractCallsFromExpression(src, callerDefId: callerDefId)
            extractCallsFromExpression(count, callerDefId: callerDefId)
        case .refCount(let val):
            extractCallsFromExpression(val, callerDefId: callerDefId)
        case .downgradeRef(let val, _):
            extractCallsFromExpression(val, callerDefId: callerDefId)
        case .upgradeRef(let val, _):
            extractCallsFromExpression(val, callerDefId: callerDefId)
        case .initMemory(let ptr, let val):
            extractCallsFromExpression(ptr, callerDefId: callerDefId)
            extractCallsFromExpression(val, callerDefId: callerDefId)
        case .deinitMemory(let ptr):
            extractCallsFromExpression(ptr, callerDefId: callerDefId)
        case .takeMemory(let ptr):
            extractCallsFromExpression(ptr, callerDefId: callerDefId)
        case .nullPtr:
            break
        }
    }

    // MARK: - Topological Order (Tarjan's SCC)

    /// 计算逆拓扑序（被调用函数先于调用者）using Tarjan's SCC algorithm.
    /// SCCs with more than one node (cycles/mutual recursion) have all their
    /// parameters conservatively marked as `.escapes`.
    /// Tarjan's algorithm naturally emits SCCs in reverse topological order.
    private func computeReverseTopologicalOrder() -> [UInt64] {
        var index = 0
        var stack: [UInt64] = []
        var onStack: Set<UInt64> = []
        var indices: [UInt64: Int] = [:]
        var lowlinks: [UInt64: Int] = [:]
        var result: [UInt64] = []

        func strongConnect(_ v: UInt64) {
            indices[v] = index
            lowlinks[v] = index
            index += 1
            stack.append(v)
            onStack.insert(v)

            for w in callGraph[v] ?? [] {
                // Only consider edges to functions we know about
                guard functionInfo[w] != nil else { continue }
                if indices[w] == nil {
                    strongConnect(w)
                    lowlinks[v] = min(lowlinks[v]!, lowlinks[w]!)
                } else if onStack.contains(w) {
                    lowlinks[v] = min(lowlinks[v]!, indices[w]!)
                }
            }

            if lowlinks[v] == indices[v] {
                // Found an SCC - pop all nodes in this SCC
                var scc: [UInt64] = []
                while true {
                    let w = stack.removeLast()
                    onStack.remove(w)
                    scc.append(w)
                    if w == v { break }
                }

                // If SCC has more than one node (cycle), we still analyze each
                // function normally. Summaries for SCC peers may be incomplete,
                // but missing summaries are safely skipped (no propagation = safe).
                // This avoids over-conservative marking that breaks correct code.

                // Add SCC nodes to result (they form a group at the same level)
                result.append(contentsOf: scc)
            }
        }

        // Visit all functions
        for defId in functionInfo.keys {
            if indices[defId] == nil {
                strongConnect(defId)
            }
        }

        return result
    }

    // MARK: - Per-Function Analysis

    /// 分析单个函数，生成参数摘要
    private func analyzeFunction(defId: UInt64, identifier: Symbol, params: [Symbol], body: TypedExpressionNode) {
        // Create a temporary EscapeContext for this function
        let escCtx = EscapeContext(reportingEnabled: false, context: context)

        // Extract the function's return type
        let funcReturnType: Type?
        if case .function(_, let returns) = identifier.type {
            funcReturnType = returns
        } else {
            funcReturnType = nil
        }

        escCtx.reset(returnType: funcReturnType, functionName: context.getName(identifier.defId) ?? "<unknown>")

        // Set the global summaries so call-site propagation works
        escCtx.globalSummaries = self.summaries
        escCtx.program = self.program

        // Run the existing preAnalyze
        escCtx.preAnalyze(body: body, params: params)

        // Store the per-function escaped variables, but filter out parameter-level
        // escapes. Parameter escape info is only used for building summaries — the
        // actual memory allocation decision for parameters belongs to the caller,
        // not the callee.
        let paramNames = Set(params.compactMap { context.getName($0.defId) })
        var localEscaped: [String: EscapeResult] = [:]
        for (name, reason) in escCtx.escapedVariables {
            if paramNames.contains(name) {
                continue  // Skip parameter variables
            }
            localEscaped[name] = reason
        }
        escapedVariablesPerFunction[defId] = localEscaped

        // Build the parameter summary if not already set (SCC case already has one)
        if summaries[defId] == nil {
            var paramStates: [ParameterEscapeState] = []
            for param in params {
                let paramName = context.getName(param.defId) ?? "<unknown>"
                if escCtx.escapedVariables[paramName] != nil {
                    paramStates.append(.escapes)
                } else {
                    paramStates.append(.noEscape)
                }
            }
            summaries[defId] = FunctionEscapeSummary(parameterStates: paramStates)
        }
    }
}

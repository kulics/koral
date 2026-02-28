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

    /// 引用变量来源追踪：ref 变量名 -> 所有可能的原始被引用变量名
    ///
    /// 例如：`let r = ref x` 记录为 r -> {x}；
    /// 条件分支：`let r = if flag then ref a else ref b` 记录为 r -> {a, b}；
    /// 链式传递：`let r2 = r` 记录为 r2 -> {x}（继承 r 的所有来源）。
    private var referenceOrigins: [String: Set<String>] = [:]
    
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
        // 清理当前作用域中的变量（但保留 referenceOrigins 以支持跨作用域追踪）
        if let currentScopeVars = scopeStack.popLast() {
            for varName in currentScopeVars {
                variableScopes.removeValue(forKey: varName)
            }
        }
        currentScopeLevel = max(0, currentScopeLevel - 1)
    }
    
    /// 注册变量到当前作用域
    public func registerVariable(_ name: String) {
        registerVariable(name, withInitialValue: nil)
    }

    /// 注册变量到当前作用域，并在可能时追踪 ref 来源
    private func registerVariable(_ name: String, withInitialValue value: TypedExpressionNode?) {
        variableScopes[name] = currentScopeLevel
        if !scopeStack.isEmpty {
            scopeStack[scopeStack.count - 1].append(name)
        }

        if let value = value {
            let origins = extractReferenceOrigins(from: value)
            if !origins.isEmpty {
                referenceOrigins[name] = origins
            } else {
                referenceOrigins.removeValue(forKey: name)
            }
        } else {
            referenceOrigins.removeValue(forKey: name)
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
        self.referenceOrigins = [:]
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

    /// 解析引用变量的所有最终来源（处理 r2 -> r1 -> x 链，支持多来源）
    private func resolveReferenceOrigins(for name: String) -> Set<String> {
        guard let directOrigins = referenceOrigins[name] else {
            return [name]
        }

        var result: Set<String> = []
        var visited: Set<String> = [name]

        var worklist = Array(directOrigins)
        while let current = worklist.popLast() {
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            if let nextOrigins = referenceOrigins[current] {
                // This variable also has origins — keep resolving
                worklist.append(contentsOf: nextOrigins)
            } else {
                // Terminal — this is a real source variable
                result.insert(current)
            }
        }

        return result.isEmpty ? [name] : result
    }

    /// 从表达式中提取引用的所有可能来源变量名（支持条件分支、match、block 等）
    private func extractReferenceOrigins(from expr: TypedExpressionNode) -> Set<String> {
        switch expr {
        case .referenceExpression(let inner, _):
            guard let sourceName = extractVariableName(from: inner) else { return [] }
            return resolveReferenceOrigins(for: sourceName)

        case .variable(let identifier):
            guard case .reference = identifier.type else { return [] }
            let name = context?.getName(identifier.defId) ?? "<unknown>"
            return resolveReferenceOrigins(for: name)

        case .castExpression(let inner, _):
            return extractReferenceOrigins(from: inner)

        case .traitObjectConversion(let inner, _, _, _, _):
            return extractReferenceOrigins(from: inner)

        case .ifExpression(_, let thenBranch, let elseBranch, _):
            var origins = extractReferenceOrigins(from: thenBranch)
            if let elseBranch = elseBranch {
                origins.formUnion(extractReferenceOrigins(from: elseBranch))
            }
            return origins

        case .ifPatternExpression(_, _, _, let thenBranch, let elseBranch, _):
            var origins = extractReferenceOrigins(from: thenBranch)
            if let elseBranch = elseBranch {
                origins.formUnion(extractReferenceOrigins(from: elseBranch))
            }
            return origins

        case .matchExpression(_, let cases, _):
            var origins: Set<String> = []
            for matchCase in cases {
                origins.formUnion(extractReferenceOrigins(from: matchCase.body))
            }
            return origins

        case .blockExpression(let statements, _):
            // Check yield statements for reference origins
            for stmt in statements {
                if case .yield(let value) = stmt {
                    return extractReferenceOrigins(from: value)
                }
            }
            return []

        case .letExpression(_, _, let body, _):
            return extractReferenceOrigins(from: body)

        default:
            return []
        }
    }

    /// 按作用域规则标记变量（或其所有引用来源）为逃逸
    private func markEscapedVariableIfTracked(_ variableName: String, reason: EscapeResult) {
        let origins = resolveReferenceOrigins(for: variableName)

        var marked = false
        for origin in origins {
            if variableScopes[origin] != nil {
                markEscaped(origin, reason: reason)
                marked = true
            }
        }

        if !marked {
            // Secondary path: mark the variable itself if it's tracked
            if variableScopes[variableName] != nil {
                markEscaped(variableName, reason: reason)
            }
        }
    }

    /// 递归扫描表达式中的引用，并按需要标记为逃逸
    private func markEscapedReferences(in expr: TypedExpressionNode, reason: EscapeResult) {
        switch expr {
        case .referenceExpression(let inner, _):
            if let varName = extractVariableName(from: inner) {
                markEscapedVariableIfTracked(varName, reason: reason)
            }

        case .variable(let identifier):
            if case .reference = identifier.type {
                let name = context?.getName(identifier.defId) ?? "<unknown>"
                markEscapedVariableIfTracked(name, reason: reason)
            }

        case .typeConstruction(_, _, let arguments, _):
            for arg in arguments {
                markEscapedReferences(in: arg, reason: reason)
            }

        case .unionConstruction(_, _, let arguments):
            for arg in arguments {
                markEscapedReferences(in: arg, reason: reason)
            }

        case .castExpression(let inner, _):
            markEscapedReferences(in: inner, reason: reason)

        case .traitObjectConversion(let inner, _, _, _, _):
            markEscapedReferences(in: inner, reason: reason)

        case .ifExpression(_, let thenBranch, let elseBranch, _):
            markEscapedReferences(in: thenBranch, reason: reason)
            if let elseBranch = elseBranch {
                markEscapedReferences(in: elseBranch, reason: reason)
            }

        case .ifPatternExpression(_, _, _, let thenBranch, let elseBranch, _):
            markEscapedReferences(in: thenBranch, reason: reason)
            if let elseBranch = elseBranch {
                markEscapedReferences(in: elseBranch, reason: reason)
            }

        case .matchExpression(_, let cases, _):
            for matchCase in cases {
                markEscapedReferences(in: matchCase.body, reason: reason)
            }

        case .blockExpression(let statements, _):
            // Check yield statements for escaped references
            for stmt in statements {
                if case .yield(let value) = stmt {
                    markEscapedReferences(in: value, reason: reason)
                }
            }

        case .letExpression(_, _, let body, _):
            markEscapedReferences(in: body, reason: reason)

        default:
            break
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
            registerVariable(name, withInitialValue: value)
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
            
        case .blockExpression(let statements, _):
            enterScope()
            for stmt in statements {
                preAnalyzeStatement(stmt)
            }
            // Check yield statements for return escape
            for stmt in statements {
                if case .yield(let value) = stmt {
                    if let returnType = returnType, case .reference(_) = returnType {
                        checkReturnEscape(value)
                    }
                    preAnalyzeExpression(value)
                }
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
            do {
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
                let summary = calleeDefId.flatMap { globalSummaries?[$0] }
                if let summary = summary {
                    // Have summary: use precise escape info
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
                } else {
                    // No summary available (builtin/generic/unknown function):
                    // conservatively mark all ref arguments as escaping
                    if let selfArg = selfArg {
                        markRefArgumentAsEscaping(selfArg)
                    }
                    for arg in arguments {
                        markRefArgumentAsEscaping(arg)
                    }
                }
            }
            
        case .genericCall(_, _, let arguments, _):
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            // Generic calls have no summary: conservatively mark all ref args as escaping
            for arg in arguments {
                markRefArgumentAsEscaping(arg)
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
            markRefArgumentAsEscaping(receiver)
            for arg in arguments {
                markRefArgumentAsEscaping(arg)
            }
            
        case .staticMethodCall(let baseType, let methodName, _, _, let arguments, _):
            for arg in arguments {
                preAnalyzeExpression(arg)
            }
            // Inter-procedural: look up static method summary
            do {
                var foundSummary = false
                if let summaries = globalSummaries, let prog = program {
                    let typeName = context?.getTypeName(baseType) ?? ""
                    if let defId = prog.lookupStaticMethod(typeName: typeName, methodName: methodName) {
                        if let summary = summaries[defId.id] {
                            foundSummary = true
                            for (i, arg) in arguments.enumerated() {
                                if i < summary.parameterStates.count && summary.parameterStates[i] == .escapes {
                                    markRefArgumentAsEscaping(arg)
                                }
                            }
                        }
                    }
                }
                if !foundSummary {
                    // No summary: conservatively mark all ref args as escaping
                    for arg in arguments {
                        markRefArgumentAsEscaping(arg)
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
                // 检查是否将引用传递给 union 构造函数
                // 如果 union 被返回或存储，引用可能逃逸
                checkTypeConstructionEscape(arg: arg, constructedType: .void)
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
                // Mark the captured variable itself as escaped
                markEscapedVariableIfTracked(name, reason: .escapeToField)
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
            registerVariable(name, withInitialValue: value)
            
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

        case .defer(let expression):
            preAnalyzeExpression(expression)

        case .yield(let value):
            preAnalyzeExpression(value)
        }
    }
    
    private func preAnalyzePattern(_ pattern: TypedPattern) {
        switch pattern {
        case .booleanLiteral, .integerLiteral, .stringLiteral, .wildcard:
            break
        case .variable(let symbol):
            let name = context?.getName(symbol.defId) ?? "<unknown>"
            registerVariable(name, withInitialValue: nil)
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
        case .refIsBorrow(let val):
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
        case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
            preAnalyzeExpression(outHandle)
            preAnalyzeExpression(outTid)
            preAnalyzeExpression(closure)
            preAnalyzeExpression(stackSize)
            // The closure escapes to another thread
            checkPointerStoreEscape(closure)
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
            _ = inner
            markEscapedReferences(in: expr, reason: .escapeToReturn)
            
        case .variable(let identifier):
            // 返回一个引用类型变量时，标记其来源局部变量逃逸
            _ = identifier
            markEscapedReferences(in: expr, reason: .escapeToReturn)

        case .castExpression(let inner, _):
            checkReturnEscape(inner)

        case .traitObjectConversion(let inner, _, _, _, _):
            checkReturnEscape(inner)

        case .typeConstruction(_, _, let arguments, _):
            for arg in arguments {
                checkReturnEscape(arg)
            }

        case .unionConstruction(_, _, let arguments):
            for arg in arguments {
                checkReturnEscape(arg)
            }
            
        case .blockExpression(let statements, _):
            for stmt in statements {
                if case .yield(let value) = stmt {
                    checkReturnEscape(value)
                }
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

        markEscapedReferences(in: value, reason: .escapeToField)
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
        _ = constructedType
        markEscapedReferences(in: arg, reason: .escapeToField)
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
        markEscapedReferences(in: val, reason: .escapeToParameter)
    }

    /// 标记参数表达式中的 ref local_var 为逃逸
    ///
    /// 当调用一个函数且该函数的某个参数被标记为逃逸时，
    /// 检查对应的实参是否包含 `ref local_var`，如果是则标记该局部变量为逃逸。
    private func markRefArgumentAsEscaping(_ arg: TypedExpressionNode) {
        markEscapedReferences(in: arg, reason: .escapeToParameter)
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

        // Step 3: Compute reverse topological order as SCC groups
        let sccGroups = computeSCCGroups()

        // Step 4: Analyze SCC groups in order (callees before callers)
        for scc in sccGroups {
            // Check if this SCC has any cycles (including self-loops)
            let hasCycle: Bool
            if scc.count == 1 {
                let defId = scc[0]
                hasCycle = callGraph[defId]?.contains(defId) ?? false
            } else {
                hasCycle = true
            }

            if !hasCycle {
                // Single function with no self-loop — analyze once
                let defId = scc[0]
                guard let info = functionInfo[defId] else { continue }
                analyzeFunction(defId: defId, identifier: info.identifier, params: info.params, body: info.body)
            } else {
                // SCC with cycle (including self-recursive) — iterate to fixed point
                // Initialize all summaries in this SCC to noEscape
                for defId in scc {
                    guard let info = functionInfo[defId] else { continue }
                    let paramCount = info.params.count
                    summaries[defId] = FunctionEscapeSummary(
                        parameterStates: Array(repeating: .noEscape, count: paramCount)
                    )
                }

                let maxIterations = 10
                for _ in 0..<maxIterations {
                    var changed = false
                    for defId in scc {
                        guard let info = functionInfo[defId] else { continue }
                        let oldSummary = summaries[defId]
                        analyzeFunction(defId: defId, identifier: info.identifier, params: info.params, body: info.body)
                        if summaries[defId]?.parameterStates != oldSummary?.parameterStates {
                            changed = true
                        }
                    }
                    if !changed { break }
                }
            }
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

            case .givenDeclaration(let type, _, let methods):
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

        case .blockExpression(let statements, _):
            for stmt in statements {
                extractCallsFromStatement(stmt, callerDefId: callerDefId)
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

        case .staticMethodCall(let baseType, let methodName, _, _, let arguments, _):
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

        case .defer(let expression):
            extractCallsFromExpression(expression, callerDefId: callerDefId)

        case .yield(let value):
            extractCallsFromExpression(value, callerDefId: callerDefId)
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
        case .refIsBorrow(let val):
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
        case .spawnThread(let outHandle, let outTid, let closure, let stackSize):
            extractCallsFromExpression(outHandle, callerDefId: callerDefId)
            extractCallsFromExpression(outTid, callerDefId: callerDefId)
            extractCallsFromExpression(closure, callerDefId: callerDefId)
            extractCallsFromExpression(stackSize, callerDefId: callerDefId)
        }
    }

    // MARK: - Topological Order (Iterative Kosaraju SCC)

    /// 计算 SCC 分组，按逆拓扑序排列（被调用函数先于调用者）。
    /// 每个 SCC 是一组互相递归的函数。单函数无循环时 SCC 大小为 1。
    /// 使用迭代版 Kosaraju，避免深调用图下递归栈溢出。
    private func computeSCCGroups() -> [[UInt64]] {
        let vertices = functionInfo.keys.sorted()

        var reverseGraph: [UInt64: Set<UInt64>] = [:]
        for v in vertices {
            reverseGraph[v] = []
        }
        for v in vertices {
            for w in callGraph[v] ?? [] {
                guard functionInfo[w] != nil else { continue }
                reverseGraph[w, default: []].insert(v)
            }
        }

        var visited: Set<UInt64> = []
        var finishOrder: [UInt64] = []

        for start in vertices {
            if visited.contains(start) { continue }
            visited.insert(start)

            var stack: [(node: UInt64, neighbors: [UInt64], nextIndex: Int)] = [
                (start, (reverseGraph[start] ?? []).sorted(), 0)
            ]

            while let frame = stack.last {
                if frame.nextIndex < frame.neighbors.count {
                    var updated = frame
                    let nextNode = updated.neighbors[updated.nextIndex]
                    updated.nextIndex += 1
                    stack[stack.count - 1] = updated

                    if !visited.contains(nextNode) {
                        visited.insert(nextNode)
                        stack.append((nextNode, (reverseGraph[nextNode] ?? []).sorted(), 0))
                    }
                } else {
                    finishOrder.append(frame.node)
                    _ = stack.popLast()
                }
            }
        }

        func forwardNeighbors(_ node: UInt64) -> [UInt64] {
            (callGraph[node] ?? []).filter { functionInfo[$0] != nil }.sorted()
        }

        var assigned: Set<UInt64> = []
        var result: [[UInt64]] = []

        for start in finishOrder.reversed() {
            if assigned.contains(start) { continue }

            var component: [UInt64] = []
            var stack: [UInt64] = [start]
            assigned.insert(start)

            while let current = stack.popLast() {
                component.append(current)
                for neighbor in forwardNeighbors(current) {
                    if !assigned.contains(neighbor) {
                        assigned.insert(neighbor)
                        stack.append(neighbor)
                    }
                }
            }

            result.append(component)
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

        // Build the parameter summary (always overwrite — needed for SCC iteration)
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

// BidirectionalInference.swift
// Bidirectional type inference for Koral language.

import Foundation

/// 推断结果，包含类型和收集到的约束
public struct InferenceResult {
    /// 推断的类型
    public let type: Type
    
    /// 收集到的约束
    public let constraints: [Constraint]
    
    public init(type: Type, constraints: [Constraint] = []) {
        self.type = type
        self.constraints = constraints
    }
}

/// 双向类型推断器
/// 实现双向类型检查算法，支持合成模式和检查模式
public class BidirectionalInference {
    /// 约束求解器
    private let solver: ConstraintSolver
    
    /// 类型环境（变量名到类型的映射）
    private var typeEnvironment: [String: Type] = [:]
    
    /// 收集到的约束
    private var collectedConstraints: [Constraint] = []
    
    /// 初始化双向推断器
    public init() {
        self.solver = ConstraintSolver()
    }
    
    /// 使用现有求解器初始化
    public init(solver: ConstraintSolver) {
        self.solver = solver
    }
    
    // MARK: - Type Variable Management
    
    /// 创建新的类型变量
    /// - Parameters:
    ///   - name: 可选的描述性名称
    ///   - span: 源位置
    /// - Returns: 新的类型变量
    public func freshTypeVariable(name: String? = nil, span: SourceSpan) -> TypeVariable {
        return TypeVariable.fresh(name: name, span: span)
    }
    
    /// 创建类型变量对应的类型
    public func freshType(name: String? = nil, span: SourceSpan) -> Type {
        return .typeVariable(freshTypeVariable(name: name, span: span))
    }
    
    // MARK: - Environment Management
    
    /// 扩展类型环境
    /// - Parameters:
    ///   - name: 变量名
    ///   - type: 变量类型
    public func extendEnvironment(name: String, type: Type) {
        typeEnvironment[name] = type
    }
    
    /// 查找变量类型
    /// - Parameter name: 变量名
    /// - Returns: 变量类型，如果未找到则返回 nil
    public func lookupType(name: String) -> Type? {
        return typeEnvironment[name]
    }
    
    /// 保存当前环境状态
    public func saveEnvironment() -> [String: Type] {
        return typeEnvironment
    }
    
    /// 恢复环境状态
    public func restoreEnvironment(_ env: [String: Type]) {
        typeEnvironment = env
    }
    
    // MARK: - Constraint Management
    
    /// 添加约束
    public func addConstraint(_ constraint: Constraint) {
        collectedConstraints.append(constraint)
        solver.addConstraint(constraint)
    }
    
    /// 添加相等约束
    public func addEqualConstraint(_ t1: Type, _ t2: Type, span: SourceSpan) {
        addConstraint(.equal(t1, t2, span))
    }
    
    /// 添加默认整数类型约束
    public func addDefaultIntConstraint(_ tv: TypeVariable, span: SourceSpan) {
        addConstraint(.defaultInt(tv, span))
    }
    
    /// 添加默认浮点类型约束
    public func addDefaultFloatConstraint(_ tv: TypeVariable, span: SourceSpan) {
        addConstraint(.defaultFloat(tv, span))
    }
    
    /// 获取所有收集到的约束
    public var constraints: [Constraint] {
        return collectedConstraints
    }
    
    // MARK: - Bidirectional Type Checking Core
    
    /// 合成模式：从表达式推断类型
    /// Γ ⊢ e ⇒ τ
    /// - Parameters:
    ///   - expr: 表达式
    ///   - span: 源位置
    /// - Returns: 推断的类型
    public func synthesize(_ expr: ExpressionNode, span: SourceSpan) -> Type {
        switch expr {
        // 整数字面量
        case .integerLiteral(_, let suffix):
            return synthesizeIntegerLiteral(suffix: suffix, span: span)
            
        // 浮点字面量
        case .floatLiteral(_, let suffix):
            return synthesizeFloatLiteral(suffix: suffix, span: span)
            
        // 布尔字面量
        case .booleanLiteral:
            return .bool
            
        // 字符串字面量
        case .stringLiteral:
            return lookupType(name: "String") ?? .genericStruct(template: "String", args: [])
            
        // 变量引用
        case .identifier(let name):
            if let type = lookupType(name: name) {
                return type
            }
            // 未找到变量，创建类型变量
            let tv = freshTypeVariable(name: name, span: span)
            return .typeVariable(tv)
            
        // Lambda 表达式
        case .lambdaExpression(let params, let returnType, let body, let lambdaSpan):
            return synthesizeLambda(params: params, returnType: returnType, body: body, span: lambdaSpan)
            
        // 函数调用
        case .call(let callee, let args):
            return synthesizeCall(callee: callee, args: args, span: span)
            
        // 块表达式
        case .blockExpression(let statements, let finalExpr):
            return synthesizeBlock(statements: statements, finalExpr: finalExpr, span: span)
            
        // 算术表达式
        case .arithmeticExpression(let left, _, let right):
            let leftType = synthesize(left, span: span)
            let rightType = synthesize(right, span: span)
            addEqualConstraint(leftType, rightType, span: span)
            return leftType
            
        // 比较表达式
        case .comparisonExpression(let left, _, let right):
            let leftType = synthesize(left, span: span)
            let rightType = synthesize(right, span: span)
            addEqualConstraint(leftType, rightType, span: span)
            return .bool
            
        // 逻辑与
        case .andExpression(let left, let right):
            let _ = check(left, expected: .bool, span: span)
            let _ = check(right, expected: .bool, span: span)
            return .bool
            
        // 逻辑或
        case .orExpression(let left, let right):
            let _ = check(left, expected: .bool, span: span)
            let _ = check(right, expected: .bool, span: span)
            return .bool
            
        // 逻辑非
        case .notExpression(let operand):
            let _ = check(operand, expected: .bool, span: span)
            return .bool
            
        // 条件表达式
        case .ifExpression(let condition, let thenBranch, let elseBranch):
            return synthesizeIf(condition: condition, thenBranch: thenBranch, elseBranch: elseBranch, span: span)
            
        // 其他表达式类型暂时返回类型变量
        default:
            let tv = freshTypeVariable(name: "expr", span: span)
            return .typeVariable(tv)
        }
    }
    
    /// 检查模式：验证表达式是否符合期望类型
    /// Γ ⊢ e ⇐ τ
    /// - Parameters:
    ///   - expr: 表达式
    ///   - expected: 期望类型
    ///   - span: 源位置
    /// - Returns: 检查后的类型（通常等于 expected）
    public func check(_ expr: ExpressionNode, expected: Type, span: SourceSpan) -> Type {
        switch expr {
        // 整数字面量可以检查为任何整数类型
        case .integerLiteral(_, let suffix):
            return checkIntegerLiteral(suffix: suffix, expected: expected, span: span)
            
        // 浮点字面量可以检查为任何浮点类型
        case .floatLiteral(_, let suffix):
            return checkFloatLiteral(suffix: suffix, expected: expected, span: span)
            
        // Lambda 表达式检查为函数类型
        case .lambdaExpression(let params, let returnType, let body, let lambdaSpan):
            return checkLambda(params: params, returnType: returnType, body: body, expected: expected, span: lambdaSpan)
            
        // 其他情况：回退到合成模式，然后添加相等约束
        default:
            let synthesized = synthesize(expr, span: span)
            addEqualConstraint(synthesized, expected, span: span)
            return expected
        }
    }
    
    // MARK: - Synthesis Helpers
    
    /// 合成整数字面量类型
    private func synthesizeIntegerLiteral(suffix: NumericSuffix?, span: SourceSpan) -> Type {
        if let suffix = suffix {
            return integerTypeFromSuffix(suffix)
        }
        // 无后缀时，创建类型变量并添加默认约束
        let tv = freshTypeVariable(name: "int_lit", span: span)
        addDefaultIntConstraint(tv, span: span)
        return .typeVariable(tv)
    }
    
    /// 合成浮点字面量类型
    private func synthesizeFloatLiteral(suffix: NumericSuffix?, span: SourceSpan) -> Type {
        if let suffix = suffix {
            return floatTypeFromSuffix(suffix)
        }
        // 无后缀时，创建类型变量并添加默认约束
        let tv = freshTypeVariable(name: "float_lit", span: span)
        addDefaultFloatConstraint(tv, span: span)
        return .typeVariable(tv)
    }
    
    /// 合成 Lambda 表达式类型
    private func synthesizeLambda(
        params: [(name: String, type: TypeNode?)],
        returnType: TypeNode?,
        body: ExpressionNode,
        span: SourceSpan
    ) -> Type {
        let savedEnv = saveEnvironment()
        
        // 为每个参数创建类型
        var paramTypes: [Type] = []
        for param in params {
            let paramType: Type
            if let typeNode = param.type {
                // 有显式类型注解
                paramType = resolveTypeNode(typeNode)
            } else {
                // 无类型注解，创建类型变量
                paramType = freshType(name: param.name, span: span)
            }
            paramTypes.append(paramType)
            extendEnvironment(name: param.name, type: paramType)
        }
        
        // 推断函数体类型
        let bodyType: Type
        if let retTypeNode = returnType {
            let expectedRetType = resolveTypeNode(retTypeNode)
            bodyType = check(body, expected: expectedRetType, span: span)
        } else {
            bodyType = synthesize(body, span: span)
        }
        
        restoreEnvironment(savedEnv)
        
        // 构建函数类型
        let parameters = paramTypes.map { Parameter(type: $0, kind: .byVal) }
        return .function(parameters: parameters, returns: bodyType)
    }
    
    /// 合成函数调用类型
    private func synthesizeCall(callee: ExpressionNode, args: [ExpressionNode], span: SourceSpan) -> Type {
        let calleeType = synthesize(callee, span: span)
        
        switch calleeType {
        case .function(let params, let ret):
            // 检查参数类型
            for (arg, param) in zip(args, params) {
                let _ = check(arg, expected: param.type, span: span)
            }
            return ret
            
        case .typeVariable(let tv):
            // 被调用者类型未知，创建返回类型变量
            let retType = freshType(name: "ret", span: span)
            let argTypes = args.map { synthesize($0, span: span) }
            let funcType = Type.function(
                parameters: argTypes.map { Parameter(type: $0, kind: .byVal) },
                returns: retType
            )
            addEqualConstraint(.typeVariable(tv), funcType, span: span)
            return retType
            
        default:
            // 非函数类型，返回类型变量
            return freshType(name: "call_result", span: span)
        }
    }
    
    /// 合成块表达式类型
    private func synthesizeBlock(statements: [StatementNode], finalExpr: ExpressionNode?, span: SourceSpan) -> Type {
        // 处理语句（可能引入新的绑定）
        for stmt in statements {
            processStatement(stmt, span: span)
        }
        
        // 返回最终表达式的类型
        if let finalExpr = finalExpr {
            return synthesize(finalExpr, span: span)
        }
        return .void
    }
    
    /// 合成条件表达式类型
    private func synthesizeIf(condition: ExpressionNode, thenBranch: ExpressionNode, elseBranch: ExpressionNode?, span: SourceSpan) -> Type {
        let _ = check(condition, expected: .bool, span: span)
        let thenType = synthesize(thenBranch, span: span)
        
        if let elseBranch = elseBranch {
            let elseType = synthesize(elseBranch, span: span)
            addEqualConstraint(thenType, elseType, span: span)
            return thenType
        }
        
        return .void
    }
    
    // MARK: - Check Helpers
    
    /// 检查整数字面量
    private func checkIntegerLiteral(suffix: NumericSuffix?, expected: Type, span: SourceSpan) -> Type {
        if let suffix = suffix {
            let literalType = integerTypeFromSuffix(suffix)
            addEqualConstraint(literalType, expected, span: span)
            return expected
        }
        
        // 检查期望类型是否为整数类型
        if expected.isIntegerType {
            return expected
        }
        
        // 期望类型是类型变量，添加约束
        if case .typeVariable = expected {
            let tv = freshTypeVariable(name: "int_lit", span: span)
            addDefaultIntConstraint(tv, span: span)
            addEqualConstraint(.typeVariable(tv), expected, span: span)
            return expected
        }
        
        // 其他情况，合成后添加约束
        let synthesized = synthesizeIntegerLiteral(suffix: suffix, span: span)
        addEqualConstraint(synthesized, expected, span: span)
        return expected
    }
    
    /// 检查浮点字面量
    private func checkFloatLiteral(suffix: NumericSuffix?, expected: Type, span: SourceSpan) -> Type {
        if let suffix = suffix {
            let literalType = floatTypeFromSuffix(suffix)
            addEqualConstraint(literalType, expected, span: span)
            return expected
        }
        
        // 检查期望类型是否为浮点类型
        if isFloatType(expected) {
            return expected
        }
        
        // 期望类型是类型变量，添加约束
        if case .typeVariable = expected {
            let tv = freshTypeVariable(name: "float_lit", span: span)
            addDefaultFloatConstraint(tv, span: span)
            addEqualConstraint(.typeVariable(tv), expected, span: span)
            return expected
        }
        
        // 其他情况，合成后添加约束
        let synthesized = synthesizeFloatLiteral(suffix: suffix, span: span)
        addEqualConstraint(synthesized, expected, span: span)
        return expected
    }
    
    /// 检查 Lambda 表达式
    private func checkLambda(
        params: [(name: String, type: TypeNode?)],
        returnType: TypeNode?,
        body: ExpressionNode,
        expected: Type,
        span: SourceSpan
    ) -> Type {
        guard case .function(let expectedParams, let expectedRet) = expected else {
            // 期望类型不是函数类型，回退到合成模式
            let synthesized = synthesizeLambda(params: params, returnType: returnType, body: body, span: span)
            addEqualConstraint(synthesized, expected, span: span)
            return expected
        }
        
        // 参数数量检查
        guard params.count == expectedParams.count else {
            // 参数数量不匹配，添加约束让求解器报错
            let synthesized = synthesizeLambda(params: params, returnType: returnType, body: body, span: span)
            addEqualConstraint(synthesized, expected, span: span)
            return expected
        }
        
        let savedEnv = saveEnvironment()
        
        // 从期望类型推断参数类型
        for (param, expectedParam) in zip(params, expectedParams) {
            let paramType: Type
            if let typeNode = param.type {
                // 有显式类型注解，验证一致性
                paramType = resolveTypeNode(typeNode)
                addEqualConstraint(paramType, expectedParam.type, span: span)
            } else {
                // 无类型注解，使用期望类型
                paramType = expectedParam.type
            }
            extendEnvironment(name: param.name, type: paramType)
        }
        
        // 检查函数体
        let _ = check(body, expected: expectedRet, span: span)
        
        restoreEnvironment(savedEnv)
        
        return expected
    }
    
    // MARK: - Statement Processing
    
    /// 处理语句
    private func processStatement(_ stmt: StatementNode, span: SourceSpan) {
        switch stmt {
        case .variableDeclaration(let name, let typeAnnotation, let value, let mutable, let stmtSpan):
            let _ = mutable  // 忽略 mutable
            let _ = stmtSpan  // 忽略 span
            let valueType: Type
            if let typeAnnotation = typeAnnotation {
                let annotatedType = resolveTypeNode(typeAnnotation)
                valueType = check(value, expected: annotatedType, span: span)
            } else {
                valueType = synthesize(value, span: span)
            }
            extendEnvironment(name: name, type: valueType)
            
        case .expression(let expr, _):
            let _ = synthesize(expr, span: span)
            
        default:
            break
        }
    }
    
    // MARK: - Type Resolution
    
    /// 解析类型节点
    private func resolveTypeNode(_ typeNode: TypeNode) -> Type {
        switch typeNode {
        case .identifier(let name):
            return resolveSimpleType(name)
        case .functionType(let params, let ret):
            let paramTypes = params.map { resolveTypeNode($0) }
            let retType = resolveTypeNode(ret)
            return .function(
                parameters: paramTypes.map { Parameter(type: $0, kind: .byVal) },
                returns: retType
            )
        case .generic(let base, let args):
            let argTypes = args.map { resolveTypeNode($0) }
            return .genericStruct(template: base, args: argTypes)
        case .reference(let inner):
            return .reference(inner: resolveTypeNode(inner))
        case .inferredSelf:
            // Self 类型需要从上下文获取
            return .genericParameter(name: "Self")
        case .moduleQualified(_, let name):
            // 模块限定类型：简化处理，直接解析类型名
            return resolveSimpleType(name)
        case .moduleQualifiedGeneric(_, let base, let args):
            // 模块限定泛型类型
            let argTypes = args.map { resolveTypeNode($0) }
            return .genericStruct(template: base, args: argTypes)
        }
    }
    
    /// 解析简单类型名
    private func resolveSimpleType(_ name: String) -> Type {
        switch name {
        case "Int": return .int
        case "Int8": return .int8
        case "Int16": return .int16
        case "Int32": return .int32
        case "Int64": return .int64
        case "UInt": return .uint
        case "UInt8": return .uint8
        case "UInt16": return .uint16
        case "UInt32": return .uint32
        case "UInt64": return .uint64
        case "Float32": return .float32
        case "Float64": return .float64
        case "Bool": return .bool
        case "Void": return .void
        case "Never": return .never
        default:
            // 查找环境中的类型
            if let type = lookupType(name: name) {
                return type
            }
            // 假设是泛型参数
            return .genericParameter(name: name)
        }
    }
    
    // MARK: - Helper Functions
    
    /// 从后缀获取整数类型
    private func integerTypeFromSuffix(_ suffix: NumericSuffix) -> Type {
        switch suffix {
        case .i: return .int
        case .i8: return .int8
        case .i16: return .int16
        case .i32: return .int32
        case .i64: return .int64
        case .u: return .uint
        case .u8: return .uint8
        case .u16: return .uint16
        case .u32: return .uint32
        case .u64: return .uint64
        case .f32: return .float32
        case .f64: return .float64
        }
    }
    
    /// 从后缀获取浮点类型
    private func floatTypeFromSuffix(_ suffix: NumericSuffix) -> Type {
        switch suffix {
        case .f32: return .float32
        case .f64: return .float64
        default: return .float64
        }
    }
    
    /// 检查是否为浮点类型
    private func isFloatType(_ type: Type) -> Bool {
        switch type {
        case .float32, .float64: return true
        default: return false
        }
    }
    
    // MARK: - Solving
    
    /// 求解所有约束并返回类型替换
    public func solve() throws -> TypeSubstitution {
        return try solver.solve()
    }
    
    /// 解析类型（应用当前绑定）
    public func resolve(_ type: Type) -> Type {
        return solver.resolve(type)
    }
}

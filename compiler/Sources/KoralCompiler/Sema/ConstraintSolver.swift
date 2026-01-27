// ConstraintSolver.swift
// Constraint solver for bidirectional type inference.

import Foundation

/// 约束求解错误
public enum ConstraintSolverError: Error, CustomStringConvertible, @unchecked Sendable {
    /// 合一失败
    case unificationFailed(UnificationError)
    
    /// 未解决的类型变量
    case unsolvedTypeVariable(TypeVariable)
    
    /// 约束冲突
    case conflictingConstraints(Constraint, Constraint)
    
    /// Trait 约束不满足
    case traitNotSatisfied(type: Type, trait: String, span: SourceSpan)
    
    public var description: String {
        switch self {
        case .unificationFailed(let error):
            return "Unification failed: \(error)"
        case .unsolvedTypeVariable(let tv):
            return "Unsolved type variable: \(tv.detailedDescription)"
        case .conflictingConstraints(let c1, let c2):
            return "Conflicting constraints: \(c1) and \(c2)"
        case .traitNotSatisfied(let type, let trait, let span):
            return "Type \(type) does not satisfy trait \(trait) at \(span)"
        }
    }
}

/// 约束求解器
/// 负责收集和求解类型约束，产生类型替换
public class ConstraintSolver {
    /// 并查集，用于管理类型变量的等价类
    private let unionFind: UnionFind<TypeVariable>
    
    /// 合一器
    private let unifier: Unifier

    /// 统一查询上下文
    private let context: CompilerContext
    
    /// 待处理的约束队列
    private var constraints: [Constraint]
    
    /// 默认类型约束（延迟处理）
    private var defaultConstraints: [Constraint]
    
    /// 收集到的错误
    private var errors: [ConstraintSolverError]
    
    /// Trait 检查器（可选，用于验证 trait 约束）
    public var traitChecker: ((Type, String) -> Bool)?
    
    /// 初始化约束求解器
    public init(context: CompilerContext) {
        self.context = context
        self.unionFind = UnionFind<TypeVariable>()
        self.unifier = Unifier(unionFind: unionFind, context: context)
        self.constraints = []
        self.defaultConstraints = []
        self.errors = []
    }
    
    /// 添加约束
    /// - Parameter constraint: 要添加的约束
    public func addConstraint(_ constraint: Constraint) {
        switch constraint {
        case .defaultInt, .defaultFloat:
            // 默认类型约束延迟处理
            defaultConstraints.append(constraint)
        default:
            constraints.append(constraint)
        }
    }
    
    /// 添加多个约束
    /// - Parameter constraints: 要添加的约束数组
    public func addConstraints(_ constraints: [Constraint]) {
        for constraint in constraints {
            addConstraint(constraint)
        }
    }
    
    /// 求解所有约束
    /// - Returns: 类型替换
    /// - Throws: ConstraintSolverError 如果求解失败
    public func solve() throws -> TypeSubstitution {
        errors.removeAll()
        
        // 按优先级排序约束
        constraints.sort { $0.priority < $1.priority }
        
        // 处理主要约束
        while !constraints.isEmpty {
            let constraint = constraints.removeFirst()
            try processConstraint(constraint)
        }
        
        // 处理默认类型约束
        for constraint in defaultConstraints {
            try processDefaultConstraint(constraint)
        }
        
        // 检查是否有错误
        if !errors.isEmpty {
            throw errors.first!
        }
        
        // 构建类型替换
        return buildSubstitution()
    }
    
    /// 处理单个约束
    private func processConstraint(_ constraint: Constraint) throws {
        switch constraint {
        case .equal(let t1, let t2, let span):
            do {
                try unifier.unify(t1, t2, span: span)
            } catch let error as UnificationError {
                errors.append(.unificationFailed(error))
            }
            
        case .instantiate(let tv, let template, let args, let span):
            // 创建泛型实例类型并与类型变量合一
            let instanceType: Type
            // 根据模板名称判断是结构体还是联合类型
            // 这里简化处理，实际需要查询类型注册表
            instanceType = .genericStruct(template: template, args: args)
            
            do {
                try unifier.unify(.typeVariable(tv), instanceType, span: span)
            } catch let error as UnificationError {
                errors.append(.unificationFailed(error))
            }
            
        case .traitBound(let type, let traitName, let span):
            // 解析类型
            let resolvedType = unifier.resolve(type)
            
            // 如果类型仍包含类型变量，延迟检查
            if context.containsTypeVariable(resolvedType) {
                // 重新添加约束，稍后处理
                constraints.append(constraint)
            } else {
                // 检查 trait 约束
                if let checker = traitChecker {
                    if !checker(resolvedType, traitName) {
                        errors.append(.traitNotSatisfied(
                            type: resolvedType,
                            trait: traitName,
                            span: span
                        ))
                    }
                }
            }
            
        case .defaultInt, .defaultFloat:
            // 这些在 processDefaultConstraint 中处理
            break
        }
    }
    
    /// 处理默认类型约束
    private func processDefaultConstraint(_ constraint: Constraint) throws {
        switch constraint {
        case .defaultInt(let tv, let span):
            let resolved = unifier.resolve(.typeVariable(tv))
            
            // 如果类型变量仍未解决，应用默认类型
            if case .typeVariable = resolved {
                do {
                    try unifier.unify(.typeVariable(tv), .int, span: span)
                } catch let error as UnificationError {
                    errors.append(.unificationFailed(error))
                }
            }
            
        case .defaultFloat(let tv, let span):
            let resolved = unifier.resolve(.typeVariable(tv))
            
            // 如果类型变量仍未解决，应用默认类型
            if case .typeVariable = resolved {
                do {
                    try unifier.unify(.typeVariable(tv), .float64, span: span)
                } catch let error as UnificationError {
                    errors.append(.unificationFailed(error))
                }
            }
            
        default:
            break
        }
    }
    
    /// 构建类型替换
    private func buildSubstitution() -> TypeSubstitution {
        var mapping: [TypeVariable: Type] = [:]
        
        for (tv, type) in unifier.currentBindings {
            // 完全解析类型
            let resolvedType = unifier.resolve(type)
            mapping[tv] = resolvedType
        }
        
        return TypeSubstitution(mapping: mapping)
    }
    
    /// 解析类型（使用当前绑定）
    public func resolve(_ type: Type) -> Type {
        return unifier.resolve(type)
    }
    
    /// 获取收集到的错误
    public var collectedErrors: [ConstraintSolverError] {
        return errors
    }
    
    /// 检查是否有未解决的类型变量
    /// - Parameter type: 要检查的类型
    /// - Returns: 未解决的类型变量列表
    public func unsolvedVariables(in type: Type) -> [TypeVariable] {
        let resolved = unifier.resolve(type)
        return context.freeTypeVariables(in: resolved)
    }
}

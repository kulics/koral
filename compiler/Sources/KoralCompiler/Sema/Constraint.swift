// Constraint.swift
// Type constraints for bidirectional type inference.

import Foundation

/// 类型约束，表示类型之间的关系
/// 用于约束收集和求解过程
public enum Constraint: CustomStringConvertible {
    /// 相等约束：两个类型必须相等
    /// - Parameters:
    ///   - lhs: 左侧类型
    ///   - rhs: 右侧类型
    ///   - span: 产生此约束的源位置
    case equal(Type, Type, SourceSpan)
    
    /// 实例化约束：类型变量必须是某个泛型类型的实例
    /// - Parameters:
    ///   - variable: 类型变量
    ///   - template: 泛型模板名称
    ///   - args: 类型参数
    ///   - span: 产生此约束的源位置
    case instantiate(TypeVariable, String, [Type], SourceSpan)
    
    /// Trait 约束：类型必须实现某个 trait
    /// - Parameters:
    ///   - type: 需要满足约束的类型
    ///   - traitName: trait 名称
    ///   - span: 产生此约束的源位置
    case traitBound(Type, String, SourceSpan)
    
    /// 默认整数类型约束：如果类型变量未被其他约束确定，则默认为 Int
    /// - Parameters:
    ///   - variable: 类型变量
    ///   - span: 产生此约束的源位置
    case defaultInt(TypeVariable, SourceSpan)
    
    /// 默认浮点类型约束：如果类型变量未被其他约束确定，则默认为 Float64
    /// - Parameters:
    ///   - variable: 类型变量
    ///   - span: 产生此约束的源位置
    case defaultFloat(TypeVariable, SourceSpan)
    
    // MARK: - Accessors
    
    /// 获取约束的源位置
    public var sourceSpan: SourceSpan {
        switch self {
        case .equal(_, _, let span),
             .instantiate(_, _, _, let span),
             .traitBound(_, _, let span),
             .defaultInt(_, let span),
             .defaultFloat(_, let span):
            return span
        }
    }
    
    /// 获取约束中涉及的所有类型
    public var involvedTypes: [Type] {
        switch self {
        case .equal(let t1, let t2, _):
            return [t1, t2]
        case .instantiate(let tv, _, let args, _):
            return [.typeVariable(tv)] + args
        case .traitBound(let t, _, _):
            return [t]
        case .defaultInt(let tv, _):
            return [.typeVariable(tv)]
        case .defaultFloat(let tv, _):
            return [.typeVariable(tv)]
        }
    }
    
    /// 获取约束中涉及的所有类型变量
    public var involvedTypeVariables: [TypeVariable] {
        var result: [TypeVariable] = []
        for type in involvedTypes {
            result.append(contentsOf: type.freeTypeVariables)
        }
        return result
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        switch self {
        case .equal(let t1, let t2, _):
            return "\(t1) = \(t2)"
        case .instantiate(let tv, let template, let args, _):
            let argsStr = args.map { $0.description }.joined(separator: ", ")
            return "\(tv) ~ [\(argsStr)]\(template)"
        case .traitBound(let t, let traitName, _):
            return "\(t): \(traitName)"
        case .defaultInt(let tv, _):
            return "\(tv) ?= Int"
        case .defaultFloat(let tv, _):
            return "\(tv) ?= Float64"
        }
    }
}

// MARK: - Constraint Priority

extension Constraint {
    /// 约束优先级，用于确定求解顺序
    /// 较低的值表示较高的优先级
    public var priority: Int {
        switch self {
        case .equal:
            return 0  // 最高优先级：相等约束
        case .instantiate:
            return 1  // 实例化约束
        case .traitBound:
            return 2  // Trait 约束
        case .defaultInt, .defaultFloat:
            return 10 // 最低优先级：默认类型约束
        }
    }
}

// MARK: - Type Extension for TypeVariable

extension Type {
    /// 获取类型中的所有自由类型变量
    public var freeTypeVariables: [TypeVariable] {
        switch self {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return []
        case .typeVariable(let tv):
            return [tv]
        case .function(let params, let returns):
            var result: [TypeVariable] = []
            for param in params {
                result.append(contentsOf: param.type.freeTypeVariables)
            }
            result.append(contentsOf: returns.freeTypeVariables)
            return result
        case .structure(let defId):
            var result: [TypeVariable] = []
            for member in TypedDefContext.current?.getStructMembers(defId) ?? [] {
                result.append(contentsOf: member.type.freeTypeVariables)
            }
            return result
        case .union(let defId):
            var result: [TypeVariable] = []
            for c in TypedDefContext.current?.getUnionCases(defId) ?? [] {
                for param in c.parameters {
                    result.append(contentsOf: param.type.freeTypeVariables)
                }
            }
            return result
        case .reference(let inner):
            return inner.freeTypeVariables
        case .pointer(let element):
            return element.freeTypeVariables
        case .genericParameter:
            return []
        case .genericStruct(_, let args):
            return args.flatMap { $0.freeTypeVariables }
        case .genericUnion(_, let args):
            return args.flatMap { $0.freeTypeVariables }
        case .module:
            return []
        }
    }
    
    /// 检查类型是否包含类型变量
    public var containsTypeVariable: Bool {
        return !freeTypeVariables.isEmpty
    }
}

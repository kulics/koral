// Unifier.swift
// Unification algorithm for type inference.

import Foundation

/// 合一错误类型
public enum UnificationError: Error, CustomStringConvertible, @unchecked Sendable {
    /// 类型不匹配
    case typeMismatch(expected: Type, got: Type, span: SourceSpan)
    /// 参数数量不匹配
    case arityMismatch(expected: Int, got: Int, span: SourceSpan)
    
    /// 发生检查失败（无限类型）
    case occursCheck(variable: TypeVariable, type: Type, span: SourceSpan)
    
    /// 泛型模板不匹配
    case templateMismatch(expected: String, got: String, span: SourceSpan)
    
    public var description: String {
        switch self {
        case .typeMismatch(let expected, let got, let span):
            return "Type mismatch at \(span): expected \(expected), got \(got)"
        case .arityMismatch(let expected, let got, let span):
            return "Arity mismatch at \(span): expected \(expected) parameters, got \(got)"
        case .occursCheck(let variable, let type, let span):
            return "Infinite type at \(span): \(variable) occurs in \(type)"
        case .templateMismatch(let expected, let got, let span):
            return "Template mismatch at \(span): expected \(expected), got \(got)"
        }
    }
}

/// 合一器，用于判断两个类型是否可以统一
public class Unifier {
    /// 并查集，用于管理类型变量的等价类
    private let unionFind: UnionFind<TypeVariable>
    
    /// 类型变量到具体类型的绑定
    private var bindings: [TypeVariable: Type]
    
    /// 统一查询上下文
    private let context: CompilerContext
    
    /// 初始化合一器
    /// - Parameters:
    ///   - unionFind: 并查集实例
    ///   - bindings: 初始绑定
    public init(
        unionFind: UnionFind<TypeVariable>,
        bindings: [TypeVariable: Type] = [:],
        context: CompilerContext
    ) {
        self.unionFind = unionFind
        self.bindings = bindings
        self.context = context
    }
    
    /// 获取当前绑定
    public var currentBindings: [TypeVariable: Type] {
        return bindings
    }
    
    /// 合一两个类型
    /// - Parameters:
    ///   - t1: 第一个类型
    ///   - t2: 第二个类型
    ///   - span: 源位置（用于错误报告）
    /// - Throws: UnificationError 如果合一失败
    public func unify(_ t1: Type, _ t2: Type, span: SourceSpan) throws {
        // 首先解析类型变量
        let resolved1 = resolve(t1)
        let resolved2 = resolve(t2)
        
        // 如果解析后相等，直接返回
        if resolved1 == resolved2 {
            return
        }
        
        switch (resolved1, resolved2) {
        // 类型变量与任意类型
        case (.typeVariable(let tv), let t):
            try bindVariable(tv, to: t, span: span)
            
        case (let t, .typeVariable(let tv)):
            try bindVariable(tv, to: t, span: span)
            
        // 函数类型
        case (.function(let params1, let ret1), .function(let params2, let ret2)):
            if params1.count != params2.count {
                throw UnificationError.arityMismatch(
                    expected: params1.count,
                    got: params2.count,
                    span: span
                )
            }
            
            // 合一参数类型
            for (p1, p2) in zip(params1, params2) {
                try unify(p1.type, p2.type, span: span)
            }
            
            // 合一返回类型
            try unify(ret1, ret2, span: span)
            
        // 泛型结构体
        case (.genericStruct(let template1, let args1), .genericStruct(let template2, let args2)):
            if template1 != template2 {
                throw UnificationError.templateMismatch(
                    expected: template1,
                    got: template2,
                    span: span
                )
            }
            
            if args1.count != args2.count {
                throw UnificationError.arityMismatch(
                    expected: args1.count,
                    got: args2.count,
                    span: span
                )
            }
            
            for (a1, a2) in zip(args1, args2) {
                try unify(a1, a2, span: span)
            }
            
        // 泛型联合类型
        case (.genericUnion(let template1, let args1), .genericUnion(let template2, let args2)):
            if template1 != template2 {
                throw UnificationError.templateMismatch(
                    expected: template1,
                    got: template2,
                    span: span
                )
            }
            
            if args1.count != args2.count {
                throw UnificationError.arityMismatch(
                    expected: args1.count,
                    got: args2.count,
                    span: span
                )
            }
            
            for (a1, a2) in zip(args1, args2) {
                try unify(a1, a2, span: span)
            }
            
        // 引用类型
        case (.reference(let inner1), .reference(let inner2)):
            try unify(inner1, inner2, span: span)
            
        // 指针类型
        case (.pointer(let elem1), .pointer(let elem2)):
            try unify(elem1, elem2, span: span)
            
        // 结构体类型（基于声明实体比较）
        case (.structure(let decl1), .structure(let decl2)):
            if decl1 != decl2 {
                throw UnificationError.typeMismatch(
                    expected: resolved1,
                    got: resolved2,
                    span: span
                )
            }
            
        // 联合类型（基于声明实体比较）
        case (.union(let decl1), .union(let decl2)):
            if decl1 != decl2 {
                throw UnificationError.typeMismatch(
                    expected: resolved1,
                    got: resolved2,
                    span: span
                )
            }
            
        // 泛型参数
        case (.genericParameter(let name1), .genericParameter(let name2)):
            if name1 != name2 {
                throw UnificationError.typeMismatch(
                    expected: resolved1,
                    got: resolved2,
                    span: span
                )
            }
        // 其他情况：类型不匹配
        default:
            throw UnificationError.typeMismatch(
                expected: resolved1,
                got: resolved2,
                span: span
            )
        }
    }
    
    /// 绑定类型变量到具体类型
    /// - Parameters:
    ///   - tv: 类型变量
    ///   - type: 要绑定的类型
    ///   - span: 源位置
    /// - Throws: UnificationError 如果发生检查失败
    private func bindVariable(_ tv: TypeVariable, to type: Type, span: SourceSpan) throws {
        // 发生检查：防止无限类型
        if occurs(tv, in: type) {
            throw UnificationError.occursCheck(variable: tv, type: type, span: span)
        }
        
        let root = unionFind.find(tv)
        
        // 如果类型是另一个类型变量，合并它们
        if case .typeVariable(let otherTV) = type {
            let otherRoot = unionFind.find(otherTV)
            if root != otherRoot {
                // 合并两个类型变量
                let newRoot = unionFind.union(root, otherRoot)
                
                // 如果其中一个已经有绑定，保留该绑定
                if let existingBinding = bindings[root] {
                    bindings[newRoot] = existingBinding
                    if root != newRoot {
                        bindings.removeValue(forKey: root)
                    }
                } else if let existingBinding = bindings[otherRoot] {
                    bindings[newRoot] = existingBinding
                    if otherRoot != newRoot {
                        bindings.removeValue(forKey: otherRoot)
                    }
                }
            }
        } else {
            // 绑定到具体类型
            if let existingBinding = bindings[root] {
                // 如果已有绑定，需要合一
                try unify(existingBinding, type, span: span)
            } else {
                bindings[root] = type
            }
        }
    }
    
    /// 发生检查：检查类型变量是否出现在类型中
    /// - Parameters:
    ///   - tv: 类型变量
    ///   - type: 要检查的类型
    /// - Returns: 如果类型变量出现在类型中返回 true
    public func occurs(_ tv: TypeVariable, in type: Type) -> Bool {
        let resolved = resolve(type)
        
        switch resolved {
        case .typeVariable(let otherTV):
            return unionFind.find(tv) == unionFind.find(otherTV)
            
        case .function(let params, let ret):
            return params.contains { occurs(tv, in: $0.type) } || occurs(tv, in: ret)
            
        case .genericStruct(_, let args):
            return args.contains { occurs(tv, in: $0) }
            
        case .genericUnion(_, let args):
            return args.contains { occurs(tv, in: $0) }
            
        case .reference(let inner):
            return occurs(tv, in: inner)
            
        case .pointer(let elem):
            return occurs(tv, in: elem)
            
        case .structure(let defId):
            return (context.getStructMembers(defId) ?? []).contains { occurs(tv, in: $0.type) }
            
        case .union(let defId):
            return (context.getUnionCases(defId) ?? []).contains { c in
                c.parameters.contains { occurs(tv, in: $0.type) }
            }
            
        default:
            return false
        }
    }
    
    /// 解析类型，将类型变量替换为其绑定的类型
    /// - Parameter type: 要解析的类型
    /// - Returns: 解析后的类型
    public func resolve(_ type: Type) -> Type {
        switch type {
        case .typeVariable(let tv):
            let root = unionFind.find(tv)
            if let boundType = bindings[root] {
                // 递归解析绑定的类型
                return resolve(boundType)
            }
            // 返回代表元对应的类型变量
            return .typeVariable(root)
            
        case .function(let params, let ret):
            let resolvedParams = params.map { Parameter(type: resolve($0.type), kind: $0.kind) }
            let resolvedRet = resolve(ret)
            return .function(parameters: resolvedParams, returns: resolvedRet)
            
        case .genericStruct(let template, let args):
            return .genericStruct(template: template, args: args.map { resolve($0) })
            
        case .genericUnion(let template, let args):
            return .genericUnion(template: template, args: args.map { resolve($0) })
            
        case .reference(let inner):
            return .reference(inner: resolve(inner))
            
        case .pointer(let elem):
            return .pointer(element: resolve(elem))
            
        default:
            return type
        }
    }
}

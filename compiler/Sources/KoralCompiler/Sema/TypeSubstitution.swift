// TypeSubstitution.swift
// Type substitution for bidirectional type inference.

import Foundation

/// 类型替换：将类型变量映射到具体类型
public struct TypeSubstitution {
    /// 类型变量到类型的映射
    private var mapping: [TypeVariable: Type]
    
    /// 创建空的类型替换
    public init() {
        self.mapping = [:]
    }
    
    /// 从映射创建类型替换
    /// - Parameter mapping: 类型变量到类型的映射
    public init(mapping: [TypeVariable: Type]) {
        self.mapping = mapping
    }
    
    /// 添加或更新绑定
    /// - Parameters:
    ///   - tv: 类型变量
    ///   - type: 要绑定的类型
    public mutating func bind(_ tv: TypeVariable, to type: Type) {
        mapping[tv] = type
    }
    
    /// 获取类型变量的绑定
    /// - Parameter tv: 类型变量
    /// - Returns: 绑定的类型，如果未绑定则返回 nil
    public func lookup(_ tv: TypeVariable) -> Type? {
        return mapping[tv]
    }
    
    /// 应用替换到类型
    /// - Parameter type: 要应用替换的类型
    /// - Returns: 替换后的类型
    public func apply(_ type: Type) -> Type {
        switch type {
        case .typeVariable(let tv):
            if let boundType = mapping[tv] {
                // 递归应用替换，处理链式绑定
                return apply(boundType)
            }
            return type
            
        case .function(let params, let ret):
            let newParams = params.map { Parameter(type: apply($0.type), kind: $0.kind) }
            let newRet = apply(ret)
            return .function(parameters: newParams, returns: newRet)
            
        case .genericStruct(let template, let args):
            return .genericStruct(template: template, args: args.map { apply($0) })
            
        case .genericUnion(let template, let args):
            return .genericUnion(template: template, args: args.map { apply($0) })
            
        case .reference(let inner):
            return .reference(inner: apply(inner))
            
        case .pointer(let elem):
            return .pointer(element: apply(elem))
            
        case .structure(let defId):
            guard let members = TypedDefContext.current?.getStructMembers(defId) else {
                return type
            }
            if members.contains(where: { $0.type.containsTypeVariable }) {
                let newMembers = members.map { (name: $0.name, type: apply($0.type), mutable: $0.mutable) }
                if var map = TypedDefContext.current {
                    let isGeneric = map.isGenericInstantiation(defId) ?? false
                    let typeArgs = map.getTypeArguments(defId)
                    map.addStructInfo(defId: defId, members: newMembers, isGenericInstantiation: isGeneric, typeArguments: typeArgs)
                    TypedDefContext.current = map
                }
            }
            return type
            
        case .union(let defId):
            guard let cases = TypedDefContext.current?.getUnionCases(defId) else {
                return type
            }
            if cases.contains(where: { c in c.parameters.contains { $0.type.containsTypeVariable } }) {
                let newCases = cases.map { c in
                    UnionCase(
                        name: c.name,
                        parameters: c.parameters.map { (name: $0.name, type: apply($0.type)) }
                    )
                }
                if var map = TypedDefContext.current {
                    let isGeneric = map.isGenericInstantiation(defId) ?? false
                    let typeArgs = map.getTypeArguments(defId)
                    map.addUnionInfo(defId: defId, cases: newCases, isGenericInstantiation: isGeneric, typeArguments: typeArgs)
                    TypedDefContext.current = map
                }
            }
            return type
            
        default:
            return type
        }
    }
    
    /// 组合两个替换
    /// 结果替换等价于先应用 self，再应用 other
    /// - Parameter other: 另一个替换
    /// - Returns: 组合后的替换
    public func compose(_ other: TypeSubstitution) -> TypeSubstitution {
        var result = TypeSubstitution()
        
        // 首先应用 other 到 self 的所有绑定
        for (tv, type) in mapping {
            result.mapping[tv] = other.apply(type)
        }
        
        // 然后添加 other 中不在 self 中的绑定
        for (tv, type) in other.mapping {
            if result.mapping[tv] == nil {
                result.mapping[tv] = type
            }
        }
        
        return result
    }
    
    /// 检查类型是否包含未解决的类型变量
    /// - Parameter type: 要检查的类型
    /// - Returns: 如果包含未解决的类型变量返回 true
    public func hasUnsolvedVariables(_ type: Type) -> Bool {
        let applied = apply(type)
        return applied.containsTypeVariable
    }
    
    /// 获取类型中未解决的类型变量
    /// - Parameter type: 要检查的类型
    /// - Returns: 未解决的类型变量列表
    public func unsolvedVariables(in type: Type) -> [TypeVariable] {
        let applied = apply(type)
        return applied.freeTypeVariables
    }
    
    /// 获取所有绑定的类型变量
    public var boundVariables: Set<TypeVariable> {
        return Set(mapping.keys)
    }
    
    /// 获取映射的数量
    public var count: Int {
        return mapping.count
    }
    
    /// 检查是否为空
    public var isEmpty: Bool {
        return mapping.isEmpty
    }
    
    /// 获取所有绑定
    public var bindings: [(TypeVariable, Type)] {
        return mapping.map { ($0.key, $0.value) }
    }
}

// MARK: - CustomStringConvertible

extension TypeSubstitution: CustomStringConvertible {
    public var description: String {
        if mapping.isEmpty {
            return "{}"
        }
        
        let entries = mapping.map { "\($0.key) -> \($0.value)" }
        return "{ " + entries.joined(separator: ", ") + " }"
    }
}

// MARK: - Equatable

extension TypeSubstitution: Equatable {
    public static func == (lhs: TypeSubstitution, rhs: TypeSubstitution) -> Bool {
        guard lhs.mapping.count == rhs.mapping.count else {
            return false
        }
        
        for (tv, type) in lhs.mapping {
            guard let rhsType = rhs.mapping[tv], type == rhsType else {
                return false
            }
        }
        
        return true
    }
}

// UnionFind.swift
// Union-Find (Disjoint Set Union) data structure for type inference.

import Foundation

/// 并查集数据结构，用于高效管理类型变量的等价类
/// 支持路径压缩和按秩合并优化
public class UnionFind<T: Hashable> {
    /// 父节点映射
    private var parent: [T: T] = [:]
    
    /// 秩（树的高度上界）
    private var rank: [T: Int] = [:]
    
    /// 初始化空的并查集
    public init() {}
    
    /// 查找元素的代表元（带路径压缩）
    /// - Parameter x: 要查找的元素
    /// - Returns: 元素所在等价类的代表元
    public func find(_ x: T) -> T {
        // 如果元素不存在，将其初始化为自己的父节点
        if parent[x] == nil {
            parent[x] = x
            rank[x] = 0
        }
        
        // 路径压缩：将路径上的所有节点直接连接到根
        if parent[x] != x {
            parent[x] = find(parent[x]!)
        }
        
        return parent[x]!
    }
    
    /// 合并两个元素所在的等价类（按秩合并）
    /// - Parameters:
    ///   - x: 第一个元素
    ///   - y: 第二个元素
    /// - Returns: 合并后的代表元
    @discardableResult
    public func union(_ x: T, _ y: T) -> T {
        let rootX = find(x)
        let rootY = find(y)
        
        // 已经在同一个等价类中
        if rootX == rootY {
            return rootX
        }
        
        let rankX = rank[rootX] ?? 0
        let rankY = rank[rootY] ?? 0
        
        // 按秩合并：将较小的树连接到较大的树
        if rankX < rankY {
            parent[rootX] = rootY
            return rootY
        } else if rankX > rankY {
            parent[rootY] = rootX
            return rootX
        } else {
            // 秩相同时，任选一个作为根，并增加其秩
            parent[rootY] = rootX
            rank[rootX] = rankX + 1
            return rootX
        }
    }
    
    /// 检查两个元素是否在同一个等价类中
    /// - Parameters:
    ///   - x: 第一个元素
    ///   - y: 第二个元素
    /// - Returns: 如果在同一等价类中返回 true
    public func connected(_ x: T, _ y: T) -> Bool {
        return find(x) == find(y)
    }
    
    /// 获取所有等价类
    /// - Returns: 等价类的数组，每个等价类是一个元素集合
    public func equivalenceClasses() -> [[T]] {
        var classes: [T: [T]] = [:]
        
        for element in parent.keys {
            let root = find(element)
            if classes[root] == nil {
                classes[root] = []
            }
            classes[root]!.append(element)
        }
        
        return Array(classes.values)
    }
    
    /// 获取等价类的数量
    public var classCount: Int {
        var roots = Set<T>()
        for element in parent.keys {
            roots.insert(find(element))
        }
        return roots.count
    }
    
    /// 获取所有已知元素
    public var elements: Set<T> {
        return Set(parent.keys)
    }
    
    /// 检查元素是否已被添加到并查集中
    public func contains(_ x: T) -> Bool {
        return parent[x] != nil
    }
    
    /// 重置并查集
    public func reset() {
        parent.removeAll()
        rank.removeAll()
    }
}

// MARK: - TypeVariable 专用扩展

extension UnionFind where T == TypeVariable {
    /// 获取类型变量的代表元对应的类型
    /// - Parameters:
    ///   - tv: 类型变量
    ///   - bindings: 类型变量到具体类型的绑定
    /// - Returns: 代表元对应的类型，如果未绑定则返回类型变量本身
    public func resolveType(_ tv: TypeVariable, bindings: [TypeVariable: Type]) -> Type {
        let root = find(tv)
        if let boundType = bindings[root] {
            return boundType
        }
        return .typeVariable(root)
    }
}

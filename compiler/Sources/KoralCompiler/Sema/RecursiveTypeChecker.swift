import Foundation

// MARK: - Recursive Type Checker
// 递归类型检查器 - 检测 struct 和 union 类型定义中的间接递归

/// 类型依赖信息
public struct TypeDependency {
    /// 依赖的目标类型 DefId
    public let targetDefId: DefId
    /// 字段名（用于错误信息）
    public let fieldName: String
    /// 源代码位置
    public let sourceSpan: SourceSpan
    
    public init(targetDefId: DefId, fieldName: String, sourceSpan: SourceSpan) {
        self.targetDefId = targetDefId
        self.fieldName = fieldName
        self.sourceSpan = sourceSpan
    }
}

/// 循环节点
public struct CycleNode {
    /// 类型的 DefId
    public let defId: DefId
    /// 类型名称
    public let typeName: String
    /// 导致依赖的字段名
    public let fieldName: String?
    
    public init(defId: DefId, typeName: String, fieldName: String? = nil) {
        self.defId = defId
        self.typeName = typeName
        self.fieldName = fieldName
    }
}

/// 递归循环信息
public struct RecursionCycle {
    /// 循环路径中的类型
    public let path: [CycleNode]
    /// 循环开始的索引
    public let startIndex: Int
    
    public init(path: [CycleNode], startIndex: Int) {
        self.path = path
        self.startIndex = startIndex
    }
    
    /// 获取循环路径的字符串表示
    public func pathString() -> String {
        // path 已经包含了完整的循环路径（包括回到起点的节点）
        // 只需要从 startIndex 开始取出循环部分
        let cycleNodes = Array(path[startIndex...])
        let parts = cycleNodes.map { $0.typeName }
        return parts.joined(separator: " -> ")
    }
}

/// DFS 访问状态（三色标记法）
private enum VisitState {
    case white  // 未访问
    case gray   // 正在访问（在当前路径上）
    case black  // 已完成访问
}

/// 递归类型检查器
/// 检测 struct 和 union 类型定义中的间接递归
public class RecursiveTypeChecker {
    private let context: CompilerContext
    
    /// 类型依赖图：类型 DefId -> 依赖的类型 DefId 列表
    private var dependencyGraph: [DefId: [TypeDependency]] = [:]
    
    /// 所有需要检查的类型 DefId
    private var allTypeDefIds: [DefId] = []
    
    /// 初始化检查器
    public init(context: CompilerContext) {
        self.context = context
    }
    
    /// 执行递归检查
    /// - Returns: 检测到的循环列表，每个循环包含类型路径
    public func check() throws -> [RecursionCycle] {
        // 1. 构建类型依赖图
        buildDependencyGraph()
        
        // 2. 使用 DFS 检测循环
        return detectCycles()
    }

    
    // MARK: - Value Type Edge Detection
    
    /// 检查类型是否为值类型边（非 ref/ptr/weakref）
    /// 值类型边会导致无限大小，需要检测循环
    private func isValueTypeEdge(_ type: Type) -> Bool {
        switch type {
        case .reference, .pointer, .weakReference:
            // ref/ptr/weakref 是固定大小的指针，不会导致无限大小
            return false
        case .structure, .union:
            // 直接的 struct/union 类型是值类型边
            return true
        case .genericStruct, .genericUnion:
            // 泛型实例化也是值类型边
            return true
        default:
            // 基本类型、函数类型等不是值类型边
            return false
        }
    }
    
    /// 从类型中提取值类型依赖的 DefId
    /// 递归处理嵌套类型，但跳过 ref/ptr/weakref 包装的类型
    private func extractValueTypeDefIds(from type: Type) -> [DefId] {
        switch type {
        case .reference, .pointer, .weakReference:
            // ref/ptr/weakref 打破循环，不继续追踪
            return []
        case .structure(let defId):
            return [defId]
        case .union(let defId):
            return [defId]
        case .genericStruct(_, let args), .genericUnion(_, let args):
            // 对于泛型类型，检查类型参数中的值类型依赖
            var result: [DefId] = []
            for arg in args {
                result.append(contentsOf: extractValueTypeDefIds(from: arg))
            }
            return result
        default:
            return []
        }
    }
    
    // MARK: - Dependency Graph Building
    
    /// 从 struct 成员类型中提取值类型依赖
    private func extractValueTypeDependencies(
        from members: [(name: String, type: Type, mutable: Bool)],
        sourceSpan: SourceSpan
    ) -> [TypeDependency] {
        var dependencies: [TypeDependency] = []
        for member in members {
            let defIds = extractValueTypeDefIds(from: member.type)
            for defId in defIds {
                dependencies.append(TypeDependency(
                    targetDefId: defId,
                    fieldName: member.name,
                    sourceSpan: sourceSpan
                ))
            }
        }
        return dependencies
    }
    
    /// 从 union case 参数类型中提取值类型依赖
    private func extractValueTypeDependencies(
        from cases: [UnionCase],
        sourceSpan: SourceSpan
    ) -> [TypeDependency] {
        var dependencies: [TypeDependency] = []
        for unionCase in cases {
            for param in unionCase.parameters {
                let defIds = extractValueTypeDefIds(from: param.type)
                for defId in defIds {
                    dependencies.append(TypeDependency(
                        targetDefId: defId,
                        fieldName: "\(unionCase.name).\(param.name)",
                        sourceSpan: sourceSpan
                    ))
                }
            }
        }
        return dependencies
    }
    
    /// 构建类型依赖图
    private func buildDependencyGraph() {
        dependencyGraph.removeAll()
        allTypeDefIds.removeAll()
        
        // 遍历所有已分配的 DefId
        for defId in context.defIdMap.allDefIds {
            guard let kind = context.getKind(defId) else { continue }
            
            let sourceSpan = context.getSpan(defId) ?? .unknown
            
            switch kind {
            case .type(.structure):
                // 检查是否有成员信息（非泛型模板）
                if let members = context.getStructMembers(defId) {
                    allTypeDefIds.append(defId)
                    let deps = extractValueTypeDependencies(from: members, sourceSpan: sourceSpan)
                    if !deps.isEmpty {
                        dependencyGraph[defId] = deps
                    }
                }
                
            case .type(.union):
                // 检查是否有 case 信息（非泛型模板）
                if let cases = context.getUnionCases(defId) {
                    allTypeDefIds.append(defId)
                    let deps = extractValueTypeDependencies(from: cases, sourceSpan: sourceSpan)
                    if !deps.isEmpty {
                        dependencyGraph[defId] = deps
                    }
                }
                
            default:
                break
            }
        }
    }
    
    // MARK: - Cycle Detection
    
    /// 使用 DFS 检测循环
    private func detectCycles() -> [RecursionCycle] {
        var visitState: [DefId: VisitState] = [:]
        var cycles: [RecursionCycle] = []
        
        // 初始化所有类型为白色（未访问）
        for defId in allTypeDefIds {
            visitState[defId] = .white
        }
        
        // 对每个未访问的类型执行 DFS
        for defId in allTypeDefIds {
            if visitState[defId] == .white {
                var path: [CycleNode] = []
                dfs(defId: defId, visitState: &visitState, path: &path, cycles: &cycles)
            }
        }
        
        return cycles
    }
    
    /// DFS 遍历检测循环
    private func dfs(
        defId: DefId,
        visitState: inout [DefId: VisitState],
        path: inout [CycleNode],
        cycles: inout [RecursionCycle]
    ) {
        // 标记为灰色（正在访问）
        visitState[defId] = .gray
        
        let typeName = context.getName(defId) ?? "<unknown>"
        let node = CycleNode(defId: defId, typeName: typeName, fieldName: nil)
        path.append(node)
        
        // 遍历所有依赖
        if let dependencies = dependencyGraph[defId] {
            for dep in dependencies {
                let targetState = visitState[dep.targetDefId] ?? .white
                
                switch targetState {
                case .white:
                    // 未访问，继续 DFS
                    dfs(defId: dep.targetDefId, visitState: &visitState, path: &path, cycles: &cycles)
                    
                case .gray:
                    // 发现循环！找到循环开始的位置
                    if let startIndex = path.firstIndex(where: { $0.defId == dep.targetDefId }) {
                        // 更新路径中的字段名信息
                        var cyclePath = path
                        let targetName = context.getName(dep.targetDefId) ?? "<unknown>"
                        cyclePath.append(CycleNode(
                            defId: dep.targetDefId,
                            typeName: targetName,
                            fieldName: dep.fieldName
                        ))
                        cycles.append(RecursionCycle(path: cyclePath, startIndex: startIndex))
                    }
                    
                case .black:
                    // 已完成访问，跳过
                    break
                }
            }
        }
        
        // 标记为黑色（已完成）
        visitState[defId] = .black
        path.removeLast()
    }
}

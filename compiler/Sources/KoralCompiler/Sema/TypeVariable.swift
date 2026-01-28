// TypeVariable.swift
// Represents a type variable for bidirectional type inference.

import Foundation

/// 类型变量，表示待推断的未知类型
/// 用于双向类型推断过程中表示尚未确定的类型
public struct TypeVariable: Hashable, Equatable, CustomStringConvertible, Sendable {
    /// 唯一标识符
    public let id: Int
    
    /// 可选的描述性名称（用于错误消息和调试）
    public let name: String?
    
    /// 引入此类型变量的源位置
    public let sourceSpan: SourceSpan
    
    /// 私有初始化器，通过 fresh() 方法创建
    private init(id: Int, name: String?, sourceSpan: SourceSpan) {
        self.id = id
        self.name = name
        self.sourceSpan = sourceSpan
    }
    
    // MARK: - Factory
    
    /// 全局计数器，用于生成唯一 ID
    /// 使用 nonisolated(unsafe) 因为访问由 NSLock 保护
    nonisolated(unsafe) private static var counter: Int = 0
    
    /// 用于线程安全的锁
    private static let lock = NSLock()
    
    /// 创建新的类型变量
    /// - Parameters:
    ///   - name: 可选的描述性名称
    ///   - span: 引入此类型变量的源位置
    /// - Returns: 新的类型变量
    public static func fresh(name: String? = nil, span: SourceSpan) -> TypeVariable {
        lock.lock()
        defer { lock.unlock() }
        
        let id = counter
        counter += 1
        return TypeVariable(id: id, name: name, sourceSpan: span)
    }
    
    // MARK: - Hashable & Equatable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: TypeVariable, rhs: TypeVariable) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        if let name = name {
            return "?\(name)_\(id)"
        } else {
            return "?T\(id)"
        }
    }
    
    /// 用于错误消息的详细描述
    public var detailedDescription: String {
        var result = description
        if sourceSpan.isKnown {
            result += " (introduced at \(sourceSpan))"
        }
        return result
    }
}

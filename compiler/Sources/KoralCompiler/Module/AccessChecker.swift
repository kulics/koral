import Foundation

// MARK: - Access Error Types

/// 访问控制错误类型
public enum AccessError: Error, CustomStringConvertible {
    case privateAccess(symbol: String, span: SourceSpan)
    case protectedAccess(symbol: String, definedIn: [String], accessedFrom: [String], span: SourceSpan)
    case cannotReexportExternal(path: [String], span: SourceSpan)
    case insufficientTypeVisibility(
        symbol: String,
        symbolAccess: AccessModifier,
        type: String,
        typeAccess: AccessModifier,
        span: SourceSpan
    )
    case traitNotImplementable(trait: String, reason: String, span: SourceSpan)
    
    public var description: String {
        switch self {
        case .privateAccess(let symbol, let span):
            return "\(span): Cannot access private symbol '\(symbol)'"
            
        case .protectedAccess(let symbol, let definedIn, let accessedFrom, let span):
            let definedPath = definedIn.isEmpty ? "<root>" : definedIn.joined(separator: ".")
            let accessPath = accessedFrom.isEmpty ? "<root>" : accessedFrom.joined(separator: ".")
            return "\(span): Cannot access protected symbol '\(symbol)' defined in '\(definedPath)' from '\(accessPath)'"
            
        case .cannotReexportExternal(let path, let span):
            return "\(span): Cannot re-export external module symbol '\(path.joined(separator: "."))'"
            
        case .insufficientTypeVisibility(let symbol, let symbolAccess, let type, let typeAccess, let span):
            return "\(span): \(symbolAccess) symbol '\(symbol)' uses \(typeAccess) type '\(type)' in its signature"
            
        case .traitNotImplementable(let trait, let reason, let span):
            return "\(span): Trait '\(trait)' cannot be implemented externally: \(reason)"
        }
    }
}

// MARK: - Access Checker

/// 访问控制检查器
public class AccessChecker {
    
    public init() {}
    
    // MARK: - Symbol Access Check
    
    /// 检查模块符号访问是否合法
    /// - Parameters:
    ///   - symbolName: 符号名称
    ///   - access: 符号访问级别
    ///   - definedIn: 符号定义模块
    ///   - definedInFile: 符号定义文件
    ///   - from: 访问者所在的模块
    ///   - fromFile: 访问者所在的文件
    ///   - span: 源码位置
    /// - Throws: AccessError 如果访问不合法
    public func checkModuleAccess(
        symbolName: String,
        access: AccessModifier,
        definedIn: ModuleInfo,
        definedInFile: String,
        from: ModuleInfo,
        fromFile: String,
        span: SourceSpan
    ) throws {
        switch access {
        case .public:
            // public 符号总是可访问
            return
            
        case .protected:
            // protected 符号只能从定义模块及其子模块访问
            if !isSubmoduleOf(from, definedIn) {
                throw AccessError.protectedAccess(
                    symbol: symbolName,
                    definedIn: definedIn.path,
                    accessedFrom: from.path,
                    span: span
                )
            }
            
        case .private:
            // private 符号只能从同一文件访问
            if definedInFile != fromFile {
                throw AccessError.privateAccess(
                    symbol: symbolName,
                    span: span
                )
            }
        }
    }
    
    // MARK: - Re-export Check
    
    /// 检查重导出是否合法
    /// - Parameters:
    ///   - using: using 声明
    ///   - module: 当前模块
    ///   - unit: 编译单元
    /// - Throws: AccessError 如果重导出不合法
    public func checkReexport(
        using: UsingDeclaration,
        module: ModuleInfo,
        unit: CompilationUnit
    ) throws {
        // 只有 public using 才是重导出
        guard using.access == .public else { return }
        
        // 外部模块符号禁止重导出
        if using.pathKind == .external {
            throw AccessError.cannotReexportExternal(
                path: using.pathSegments,
                span: using.span
            )
        }
        
        // 同一编译单元内的符号可以重导出
        // (submodule 和 parent 路径都在同一编译单元内)
    }
    
    // MARK: - Signature Visibility Check
    
    /// 检查函数签名的可见性一致性
    /// - Parameters:
    ///   - symbolName: 符号名称
    ///   - symbolAccess: 符号的访问级别
    ///   - types: 签名中使用的类型列表 (类型名, 类型访问级别)
    ///   - span: 源码位置
    /// - Throws: AccessError 如果类型可见性不足
    public func checkSignatureVisibility(
        symbolName: String,
        symbolAccess: AccessModifier,
        types: [(name: String, access: AccessModifier)],
        span: SourceSpan
    ) throws {
        for (typeName, typeAccess) in types {
            if !isAtLeast(typeAccess, symbolAccess) {
                throw AccessError.insufficientTypeVisibility(
                    symbol: symbolName,
                    symbolAccess: symbolAccess,
                    type: typeName,
                    typeAccess: typeAccess,
                    span: span
                )
            }
        }
    }
    
    /// 检查类型访问级别是否至少达到要求
    /// - Parameters:
    ///   - actual: 实际访问级别
    ///   - required: 要求的访问级别
    /// - Returns: 是否满足要求
    private func isAtLeast(_ actual: AccessModifier, _ required: AccessModifier) -> Bool {
        let order: [AccessModifier: Int] = [
            .private: 0,
            .protected: 1,
            .public: 2
        ]
        
        let actualLevel = order[actual] ?? 0
        let requiredLevel = order[required] ?? 0
        
        return actualLevel >= requiredLevel
    }
    
    // MARK: - Trait Implementation Check
    
    /// 检查 trait 是否可以在外部模块实现
    /// - Parameters:
    ///   - traitName: trait 名称
    ///   - traitMethods: trait 方法列表 (方法名, 访问级别)
    ///   - implementingModule: 实现 trait 的模块
    ///   - traitModule: trait 定义所在的模块
    ///   - span: 源码位置
    /// - Throws: AccessError 如果 trait 不能在外部实现
    public func checkTraitImplementable(
        traitName: String,
        traitMethods: [(name: String, access: AccessModifier)],
        implementingModule: ModuleInfo,
        traitModule: ModuleInfo,
        span: SourceSpan
    ) throws {
        // 如果实现模块是 trait 模块或其子模块，总是可以实现
        if isSubmoduleOf(implementingModule, traitModule) {
            return
        }
        
        // 外部模块只能实现所有方法都是 public 的 trait
        for (methodName, methodAccess) in traitMethods {
            if methodAccess != .public {
                throw AccessError.traitNotImplementable(
                    trait: traitName,
                    reason: "method '\(methodName)' is not public",
                    span: span
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// 检查 child 是否是 parent 的子模块（或相同模块）
    private func isSubmoduleOf(_ child: ModuleInfo, _ parent: ModuleInfo) -> Bool {
        // 相同模块
        if child === parent {
            return true
        }
        
        // 检查 child 的路径是否以 parent 的路径开头
        if child.path.count <= parent.path.count {
            return false
        }
        
        for (i, segment) in parent.path.enumerated() {
            if child.path[i] != segment {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Default Access Modifiers
    
    /// 获取全局声明的默认访问修饰符
    /// - Parameter node: 全局节点
    /// - Returns: 默认访问修饰符
    public static func defaultAccess(for node: GlobalNode) -> AccessModifier {
        switch node {
        case .usingDeclaration(let decl):
            return decl.access
        case .foreignUsingDeclaration:
            return .private
            
           case .globalFunctionDeclaration, .globalVariableDeclaration,
               .globalStructDeclaration, .globalUnionDeclaration,
               .intrinsicFunctionDeclaration, .intrinsicTypeDeclaration,
               .foreignFunctionDeclaration, .foreignTypeDeclaration,
               .foreignLetDeclaration,
               .typeAliasDeclaration:
            return .protected
            
        case .traitDeclaration:
            return .protected
            
        case .givenDeclaration, .givenTraitDeclaration, .intrinsicGivenDeclaration:
            // given 声明本身没有访问修饰符，其方法有各自的访问修饰符
            return .private
        }
    }
    
    /// 获取 struct 字段的默认访问修饰符
    public static func defaultAccessForStructField() -> AccessModifier {
        return .public
    }
    
    /// 获取 union 构造器字段的默认访问修饰符
    public static func defaultAccessForUnionCase() -> AccessModifier {
        return .public
    }
    
    /// 获取成员函数的默认访问修饰符
    public static func defaultAccessForMethod() -> AccessModifier {
        return .protected
    }
    
    /// 获取 trait 方法的默认访问修饰符
    public static func defaultAccessForTraitMethod() -> AccessModifier {
        return .public
    }
    
    /// 获取 using 声明的默认访问修饰符
    public static func defaultAccessForUsing() -> AccessModifier {
        return .private
    }
}

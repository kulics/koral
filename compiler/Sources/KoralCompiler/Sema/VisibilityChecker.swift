import Foundation

// MARK: - ImportKind Extension

/// 扩展 ImportKind 以支持可见性检查
extension ImportKind {
    /// 是否允许直接访问（不需要模块前缀）
    public var allowsDirectAccess: Bool {
        return self.isDirectlyAccessible
    }
}

// MARK: - Visibility Error

/// 可见性错误类型
public enum VisibilityError: Error, CustomStringConvertible {
    /// 符号需要模块前缀访问
    case requiresModulePrefix(symbol: String, modulePath: [String], suggestedPrefix: String)
    /// 符号不可访问（private 或 protected 限制）
    case notAccessible(symbol: String, reason: String)
    /// 泛型参数不需要模块前缀
    case genericParameterNoPrefix(name: String)
    
    public var description: String {
        switch self {
        case .requiresModulePrefix(let symbol, let modulePath, let suggestedPrefix):
            let path = modulePath.joined(separator: ".")
            return "'\(symbol)' is defined in module '\(path)'. Use '\(suggestedPrefix).\(symbol)' to access it."
        case .notAccessible(let symbol, let reason):
            return "Cannot access '\(symbol)': \(reason)"
        case .genericParameterNoPrefix(let name):
            return "Generic parameter '\(name)' should not require module prefix"
        }
    }
}

// MARK: - Visibility Checker

/// 可见性检查器
/// 负责检查符号是否可以从当前位置直接访问，以及生成正确的访问建议
public class VisibilityChecker {
    private let context: CompilerContext
    
    public init(context: CompilerContext) {
        self.context = context
    }
    
    // MARK: - Direct Access Check
    
    /// 检查符号是否可以从当前位置直接访问（不需要模块前缀）
    /// 
    /// 可以直接访问的情况：
    /// 1. 符号是泛型参数
    /// 2. 符号来自同一模块
    /// 3. 符号来自父模块
    /// 4. 符号来自标准库
    /// 5. 符号通过批量导入 (using module.*) 引入
    /// 6. 符号通过成员导入 (using module.Symbol) 引入
    /// 
    /// 不允许直接访问的情况：
    /// 1. 符号来自子模块（需要通过 module.symbol 访问）
    /// 2. 符号来自兄弟模块（需要通过 module.symbol 访问）
    /// 3. 符号来自外部模块且只通过模块导入引入
    ///
    /// - Parameters:
    ///   - symbolModulePath: 符号所在的模块路径
    ///   - currentModulePath: 当前代码所在的模块路径
    ///   - symbolName: 符号名称（用于成员导入检查）
    ///   - importedModules: 当前模块导入的模块列表
    ///   - isGenericParameter: 是否是泛型参数
    /// - Returns: 是否可以直接访问
    public func canAccessDirectly(
        symbolModulePath: [String],
        currentModulePath: [String],
        symbolName: String? = nil,
        importGraph: ImportGraph? = nil,
        isGenericParameter: Bool = false
    ) -> Bool {
        // 泛型参数总是可以直接访问
        if isGenericParameter {
            return true
        }
        
        // 空路径总是可直接访问（局部变量/参数）
        if symbolModulePath.isEmpty {
            return true
        }
        
        // 同一模块可以直接访问
        if symbolModulePath == currentModulePath {
            return true
        }
        
        // 仅标准库根模块符号可直接访问；子模块符号需要显式导入
        if symbolModulePath.count == 1 && symbolModulePath[0] == "std" {
            return true
        }
        
        // 检查符号是否来自父模块（符号的 modulePath 是当前 modulePath 的前缀）
        // 例如：当前在 ["expr_eval", "frontend"]，符号在 ["expr_eval"]
        // 父模块的符号可以直接访问
        if symbolModulePath.count < currentModulePath.count {
            let prefix = Array(currentModulePath.prefix(symbolModulePath.count))
            if prefix == symbolModulePath {
                return true
            }
        }
        
        // 检查符号是否来自导入的模块
        let importKind = getImportKind(
            symbolModulePath: symbolModulePath,
            symbolName: symbolName,
            currentModulePath: currentModulePath,
            importGraph: importGraph
        )
        
        return importKind.allowsDirectAccess
    }
    
    // MARK: - Import Kind Detection
    
    /// 获取符号的导入类型
    ///
    /// - Parameters:
    ///   - symbolModulePath: 符号所在的模块路径
    ///   - symbolName: 符号名称
    ///   - importedModules: 当前模块导入的模块列表
    /// - Returns: 导入类型
    public func getImportKind(
        symbolModulePath: [String],
        symbolName: String?,
        currentModulePath: [String],
        importGraph: ImportGraph? = nil
    ) -> ImportKind {
        return importGraph?.getImportKind(
            symbolModulePath: symbolModulePath,
            symbolName: symbolName,
            inModule: currentModulePath
        ) ?? .moduleImport
    }
    
    // MARK: - Module Prefix Calculation
    
    /// 获取访问符号所需的模块前缀
    /// 
    /// 例如：
    /// - 当前在 ["expr_eval"]，符号在 ["expr_eval", "frontend"]
    ///   返回 "frontend"
    /// - 当前在 ["expr_eval", "backend"]，符号在 ["expr_eval", "frontend"]
    ///   返回 "frontend"（通过 super.frontend 访问）
    /// - 当前在 ["expr_eval"]，符号在 ["other_module"]
    ///   返回 "other_module"
    ///
    /// - Parameters:
    ///   - symbolModulePath: 符号所在的模块路径
    ///   - currentModulePath: 当前代码所在的模块路径
    /// - Returns: 需要的模块前缀，如果不需要前缀返回空字符串
    public func getRequiredPrefix(
        symbolModulePath: [String],
        currentModulePath: [String]
    ) -> String {
        // 空路径不需要前缀
        if symbolModulePath.isEmpty {
            return ""
        }
        
        // 同一模块不需要前缀
        if symbolModulePath == currentModulePath {
            return ""
        }
        
        // 检查是否是子模块
        // 例如：当前在 ["expr_eval"]，符号在 ["expr_eval", "frontend"]
        if symbolModulePath.count > currentModulePath.count {
            let prefix = Array(symbolModulePath.prefix(currentModulePath.count))
            if prefix == currentModulePath {
                // 返回直接子模块名
                return symbolModulePath[currentModulePath.count]
            }
        }
        
        // 检查是否是兄弟模块
        // 例如：当前在 ["expr_eval", "backend"]，符号在 ["expr_eval", "frontend"]
        if symbolModulePath.count >= 2 && currentModulePath.count >= 2 {
            // 找到共同祖先
            var commonPrefixLength = 0
            for i in 0..<min(symbolModulePath.count, currentModulePath.count) {
                if symbolModulePath[i] == currentModulePath[i] {
                    commonPrefixLength = i + 1
                } else {
                    break
                }
            }
            
            if commonPrefixLength > 0 && commonPrefixLength < symbolModulePath.count {
                // 返回从共同祖先开始的第一个不同部分
                return symbolModulePath[commonPrefixLength]
            }
        }
        
        // 外部模块：返回模块名
        if !symbolModulePath.isEmpty {
            return symbolModulePath.last ?? ""
        }
        
        return ""
    }
    
    // MARK: - Visibility Check with Error
    
    /// 检查符号可见性，如果不可直接访问则抛出错误
    ///
    /// - Parameters:
    ///   - symbolModulePath: 符号所在的模块路径
    ///   - currentModulePath: 当前代码所在的模块路径
    ///   - symbolName: 符号名称
    ///   - importedModules: 当前模块导入的模块列表
    ///   - isGenericParameter: 是否是泛型参数
    /// - Throws: VisibilityError 如果符号不可直接访问
    public func checkVisibility(
        symbolModulePath: [String],
        currentModulePath: [String],
        symbolName: String,
        importGraph: ImportGraph? = nil,
        isGenericParameter: Bool = false
    ) throws {
        if !canAccessDirectly(
            symbolModulePath: symbolModulePath,
            currentModulePath: currentModulePath,
            symbolName: symbolName,
            importGraph: importGraph,
            isGenericParameter: isGenericParameter
        ) {
            let prefix = getRequiredPrefix(
                symbolModulePath: symbolModulePath,
                currentModulePath: currentModulePath
            )
            throw VisibilityError.requiresModulePrefix(
                symbol: symbolName,
                modulePath: symbolModulePath,
                suggestedPrefix: prefix
            )
        }
    }
    
    // MARK: - Type Visibility Check
    
    /// 检查类型的可见性
    /// 
    /// 特殊处理：
    /// - 泛型参数类型不需要检查
    /// - 标准库类型总是可访问
    /// - 局部类型绑定不需要检查
    ///
    /// - Parameters:
    ///   - type: 要检查的类型
    ///   - typeName: 类型名称
    ///   - currentModulePath: 当前代码所在的模块路径
    ///   - importedModules: 当前模块导入的模块列表
    ///   - isLocalBinding: 是否是局部类型绑定
    ///   - isGenericParameter: 是否是泛型参数
    /// - Throws: VisibilityError 如果类型不可直接访问
    public func checkTypeVisibility(
        type: Type,
        typeName: String,
        currentModulePath: [String],
        importGraph: ImportGraph? = nil,
        isLocalBinding: Bool = false,
        isGenericParameter: Bool = false
    ) throws {
        // 局部类型绑定（如泛型替换、Self 绑定）不需要检查模块可见性
        if isLocalBinding {
            return
        }
        
        // 泛型参数不需要检查模块可见性
        if isGenericParameter {
            return
        }
        
        // 如果类型本身是泛型参数类型，也不需要检查
        if case .genericParameter = type {
            return
        }
        
        // 获取类型的模块路径
        let typeModulePath: [String]
        switch type {
        case .structure(let defId):
            typeModulePath = context.getModulePath(defId) ?? []
        case .union(let defId):
            typeModulePath = context.getModulePath(defId) ?? []
        case .opaque(let defId):
            typeModulePath = context.getModulePath(defId) ?? []
        case .genericStruct, .genericUnion:
            // 泛型模板目前没有存储模块路径，暂时跳过检查
            // TODO: 为泛型模板添加模块路径支持
            return
        default:
            // 基本类型、泛型参数等不需要检查
            return
        }
        
        // 空模块路径表示标准库类型或局部类型，总是可访问
        if typeModulePath.isEmpty {
            return
        }
        
        // 仅标准库根模块类型可默认访问；子模块类型需显式导入
        if typeModulePath.count == 1 && typeModulePath[0] == "std" {
            return
        }
        
        // 检查是否可以直接访问
        try checkVisibility(
            symbolModulePath: typeModulePath,
            currentModulePath: currentModulePath,
            symbolName: typeName,
            importGraph: importGraph,
            isGenericParameter: false
        )
    }
    
    // MARK: - Symbol Visibility Check
    
    /// 检查符号的可见性（用于变量和函数）
    ///
    /// - Parameters:
    ///   - symbolModulePath: 符号所在的模块路径
    ///   - symbolName: 符号名称
    ///   - currentModulePath: 当前代码所在的模块路径
    ///   - importedModules: 当前模块导入的模块列表
    /// - Throws: VisibilityError 如果符号不可直接访问
    public func checkSymbolVisibility(
        symbolModulePath: [String],
        symbolName: String,
        currentModulePath: [String],
        importGraph: ImportGraph? = nil
    ) throws {
        // 空模块路径表示局部符号，总是可访问
        if symbolModulePath.isEmpty {
            return
        }
        
        // 仅标准库根模块符号可默认访问；子模块符号需显式导入
        if symbolModulePath.count == 1 && symbolModulePath[0] == "std" {
            return
        }
        
        // 检查是否可以直接访问
        try checkVisibility(
            symbolModulePath: symbolModulePath,
            currentModulePath: currentModulePath,
            symbolName: symbolName,
            importGraph: importGraph,
            isGenericParameter: false
        )
    }
    
    // MARK: - Error Message Generation
    
    /// 生成可见性错误消息
    ///
    /// - Parameters:
    ///   - symbolName: 符号名称
    ///   - symbolModulePath: 符号所在的模块路径
    ///   - currentModulePath: 当前代码所在的模块路径
    /// - Returns: 错误消息字符串
    public func generateErrorMessage(
        symbolName: String,
        symbolModulePath: [String],
        currentModulePath: [String]
    ) -> String {
        let prefix = getRequiredPrefix(
            symbolModulePath: symbolModulePath,
            currentModulePath: currentModulePath
        )
        let modulePath = symbolModulePath.joined(separator: ".")
        return "'\(symbolName)' is defined in module '\(modulePath)'. Use '\(prefix).\(symbolName)' to access it."
    }
}

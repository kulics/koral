import Foundation

// MARK: - ImportKind Extension

/// 扩展 ImportKind 以支持可见性检查
extension ImportKind {
    /// 是否允许直接访问
    public var allowsDirectAccess: Bool {
        return self.isDirectlyAccessible
    }
}

// MARK: - Visibility Error

/// 可见性错误类型
public enum VisibilityError: Error, CustomStringConvertible {
    /// 符号未通过当前文件的 using 声明导入
    case symbolNotImported(symbol: String, modulePath: [String])
    /// 符号不可访问（private 或 protected 限制）
    case notAccessible(symbol: String, reason: String)
    /// 泛型参数不需要模块导入
    case genericParameterNoPrefix(name: String)
    
    public var description: String {
        switch self {
        case .symbolNotImported(let symbol, let modulePath):
            let path = modulePath.joined(separator: "::")
            return "'\(symbol)' is defined in module '\(path)'. Import it explicitly with using \(path) { \(symbol) }."
        case .notAccessible(let symbol, let reason):
            return "Cannot access '\(symbol)': \(reason)"
        case .genericParameterNoPrefix(let name):
            return "Generic parameter '\(name)' should not require a module import"
        }
    }
}

// MARK: - Visibility Checker

/// 可见性检查器
/// 负责检查符号是否可以从当前位置直接访问，以及生成显式导入建议
public class VisibilityChecker {
    private let context: CompilerContext
    
    public init(context: CompilerContext) {
        self.context = context
    }

    private func isStdRoot(_ modulePath: [String]) -> Bool {
        modulePath.count == 1 && (modulePath[0] == "Std" || modulePath[0] == "std")
    }

    private func isStdModule(_ modulePath: [String]) -> Bool {
        guard let first = modulePath.first else { return false }
        return first == "Std" || first == "std"
    }
    
    // MARK: - Direct Access Check
    
    /// 检查符号是否可以从当前位置直接访问
    /// 
    /// 可以直接访问的情况：
    /// 1. 符号是泛型参数
    /// 2. 符号来自同一模块
    /// 3. 符号通过 `using module::path { .. }` 引入
    /// 4. 符号通过 `using module::path { Symbol }` 引入
    /// 
    /// 不允许直接访问的情况：
    /// 1. 符号来自未显式导入的其它模块
    /// 2. 符号来自未显式导入的兄弟模块
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
        currentSourceFile: String? = nil,
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

        // std root is a compiler-provided prelude for non-std modules only.
        // std's own modules must use normal explicit imports between std modules.
        if isStdRoot(symbolModulePath) && !isStdModule(currentModulePath) {
            return true
        }
        
        // 检查符号是否来自导入的模块
        let importKind = getImportKind(
            symbolModulePath: symbolModulePath,
            symbolName: symbolName,
            currentModulePath: currentModulePath,
            currentSourceFile: currentSourceFile,
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
        currentSourceFile: String? = nil,
        importGraph: ImportGraph? = nil
    ) -> ImportKind {
        return importGraph?.getImportKind(
            symbolModulePath: symbolModulePath,
            symbolName: symbolName,
            inModule: currentModulePath,
            inSourceFile: currentSourceFile
        ) ?? .moduleImport
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
        currentSourceFile: String? = nil,
        symbolName: String,
        importGraph: ImportGraph? = nil,
        isGenericParameter: Bool = false
    ) throws {
        if !canAccessDirectly(
            symbolModulePath: symbolModulePath,
            currentModulePath: currentModulePath,
            currentSourceFile: currentSourceFile,
            symbolName: symbolName,
            importGraph: importGraph,
            isGenericParameter: isGenericParameter
        ) {
            throw VisibilityError.symbolNotImported(
                symbol: symbolName,
                modulePath: symbolModulePath
            )
        }
    }
    
    // MARK: - Type Visibility Check
    
    /// 检查类型的可见性
    /// 
    /// 特殊处理：
    /// - 泛型参数类型不需要检查
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
        currentSourceFile: String? = nil,
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
        case .`enum`(let defId):
            typeModulePath = context.getModulePath(defId) ?? []
        case .opaque(let defId):
            typeModulePath = context.getModulePath(defId) ?? []
        case .genericStruct, .genericEnum:
            // 泛型模板目前没有存储模块路径，暂时跳过检查
            // TODO: 为泛型模板添加模块路径支持
            return
        default:
            // 基本类型、泛型参数等不需要检查
            return
        }
        
        // 空模块路径表示内建类型或局部类型，总是可访问
        if typeModulePath.isEmpty {
            return
        }

        // std root is a compiler-provided prelude for non-std modules only.
        if isStdRoot(typeModulePath) && !isStdModule(currentModulePath) {
            return
        }
        
        // 检查是否可以直接访问
        try checkVisibility(
            symbolModulePath: typeModulePath,
            currentModulePath: currentModulePath,
            currentSourceFile: currentSourceFile,
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
        currentSourceFile: String? = nil,
        importGraph: ImportGraph? = nil
    ) throws {
        // 空模块路径表示局部符号，总是可访问
        if symbolModulePath.isEmpty {
            return
        }

        // std root is a compiler-provided prelude for non-std modules only.
        if isStdRoot(symbolModulePath) && !isStdModule(currentModulePath) {
            return
        }
        
        // 检查是否可以直接访问
        try checkVisibility(
            symbolModulePath: symbolModulePath,
            currentModulePath: currentModulePath,
            currentSourceFile: currentSourceFile,
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
        let modulePath = symbolModulePath.joined(separator: "::")
        return "'\(symbolName)' is defined in module '\(modulePath)'. Import it explicitly with using \(modulePath) { \(symbolName) }."
    }
}

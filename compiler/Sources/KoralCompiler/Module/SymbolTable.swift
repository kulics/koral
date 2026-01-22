import Foundation

// MARK: - Symbol Error Types

/// 符号系统错误类型
public enum SymbolError: Error, CustomStringConvertible {
    case duplicateSymbol(name: String, existingSpan: SourceSpan, newSpan: SourceSpan)
    case symbolNotFound(name: String, span: SourceSpan)
    case symbolConflict(name: String, existingAccess: AccessModifier, newAccess: AccessModifier, span: SourceSpan)
    case importConflict(name: String, from: String, existingFrom: String, span: SourceSpan)
    
    public var description: String {
        switch self {
        case .duplicateSymbol(let name, let existingSpan, let newSpan):
            return "Duplicate symbol '\(name)' at \(newSpan), previously defined at \(existingSpan)"
        case .symbolNotFound(let name, let span):
            return "\(span): Symbol '\(name)' not found"
        case .symbolConflict(let name, let existingAccess, let newAccess, let span):
            return "\(span): Symbol '\(name)' conflicts with existing \(existingAccess) symbol (new: \(newAccess))"
        case .importConflict(let name, let from, let existingFrom, let span):
            return "\(span): Imported symbol '\(name)' from '\(from)' conflicts with existing import from '\(existingFrom)'"
        }
    }
}

// MARK: - Module Symbol Kind

/// 模块级符号类型
public enum ModuleSymbolKind: CustomStringConvertible {
    case function
    case variable
    case type
    case trait
    case module
    
    public var description: String {
        switch self {
        case .function: return "function"
        case .variable: return "variable"
        case .type: return "type"
        case .trait: return "trait"
        case .module: return "module"
        }
    }
}

// MARK: - Module Symbol

/// 模块级符号信息
public struct ModuleSymbol {
    /// 符号名称
    public let name: String
    
    /// 符号类型
    public let kind: ModuleSymbolKind
    
    /// 访问修饰符
    public let access: AccessModifier
    
    /// 定义所在的模块
    public weak var definedIn: ModuleInfo?
    
    /// 定义所在的文件路径
    public let definedInFile: String
    
    /// 源码位置
    public let span: SourceSpan
    
    /// 对于模块符号，指向模块信息
    public var moduleRef: ModuleInfo?
    
    /// 完整限定名（用于代码生成）
    public var qualifiedName: String {
        guard let module = definedIn else {
            return name
        }
        if module.path.isEmpty {
            return name
        }
        let modulePath = module.path.joined(separator: "_")
        return "\(modulePath)_\(name)"
    }
    
    public init(
        name: String,
        kind: ModuleSymbolKind,
        access: AccessModifier,
        definedIn: ModuleInfo?,
        definedInFile: String,
        span: SourceSpan,
        moduleRef: ModuleInfo? = nil
    ) {
        self.name = name
        self.kind = kind
        self.access = access
        self.definedIn = definedIn
        self.definedInFile = definedInFile
        self.span = span
        self.moduleRef = moduleRef
    }
}

// MARK: - Module Symbol Table

/// 模块符号表
/// 管理模块内的符号可见性和作用域
public class ModuleSymbolTable {
    /// 所属模块
    public weak var module: ModuleInfo?
    
    /// 本文件的 private 符号（文件路径 -> 符号名 -> 符号）
    private var privateSymbols: [String: [String: ModuleSymbol]] = [:]
    
    /// 模块级 protected/public 符号（符号名 -> 符号）
    private var moduleSymbols: [String: ModuleSymbol] = [:]
    
    /// 导入的符号（符号名 -> (符号, 来源模块路径)）
    private var importedSymbols: [String: (symbol: ModuleSymbol, fromModule: String)] = [:]
    
    public init(module: ModuleInfo? = nil) {
        self.module = module
    }
    
    // MARK: - Add Symbol
    
    /// 添加符号到符号表
    /// - Parameters:
    ///   - symbol: 要添加的符号
    ///   - file: 定义符号的文件路径
    /// - Throws: SymbolError 如果符号冲突
    public func addSymbol(_ symbol: ModuleSymbol, fromFile file: String) throws {
        switch symbol.access {
        case .private:
            // private 符号只在本文件可见，不同文件可以有同名 private 符号
            if privateSymbols[file] == nil {
                privateSymbols[file] = [:]
            }
            if let existing = privateSymbols[file]?[symbol.name] {
                throw SymbolError.duplicateSymbol(
                    name: symbol.name,
                    existingSpan: existing.span,
                    newSpan: symbol.span
                )
            }
            privateSymbols[file]?[symbol.name] = symbol
            
        case .protected, .public:
            // protected/public 符号在模块内唯一
            if let existing = moduleSymbols[symbol.name] {
                throw SymbolError.duplicateSymbol(
                    name: symbol.name,
                    existingSpan: existing.span,
                    newSpan: symbol.span
                )
            }
            moduleSymbols[symbol.name] = symbol
            
        case .default:
            // 默认访问级别根据符号类型确定
            // 这里暂时当作 protected 处理
            if let existing = moduleSymbols[symbol.name] {
                throw SymbolError.duplicateSymbol(
                    name: symbol.name,
                    existingSpan: existing.span,
                    newSpan: symbol.span
                )
            }
            moduleSymbols[symbol.name] = symbol
        }
    }
    
    /// 添加模块符号（子模块导入）
    /// - Parameters:
    ///   - name: 符号名称（可能是别名）
    ///   - module: 子模块
    ///   - access: 访问修饰符
    ///   - span: 源码位置
    ///   - file: 定义所在文件
    /// - Throws: SymbolError 如果符号冲突
    public func addModuleSymbol(
        name: String,
        module submodule: ModuleInfo,
        access: AccessModifier,
        span: SourceSpan,
        fromFile file: String
    ) throws {
        let symbol = ModuleSymbol(
            name: name,
            kind: .module,
            access: access,
            definedIn: self.module,
            definedInFile: file,
            span: span,
            moduleRef: submodule
        )
        try addSymbol(symbol, fromFile: file)
    }
    
    /// 添加导入的符号
    /// - Parameters:
    ///   - symbol: 要导入的符号
    ///   - fromModule: 来源模块路径
    ///   - file: 导入所在文件
    /// - Throws: SymbolError 如果符号冲突
    public func addImportedSymbol(
        _ symbol: ModuleSymbol,
        fromModule: String,
        toFile file: String
    ) throws {
        // 检查是否与本地符号冲突
        if let existing = privateSymbols[file]?[symbol.name] {
            throw SymbolError.duplicateSymbol(
                name: symbol.name,
                existingSpan: existing.span,
                newSpan: symbol.span
            )
        }
        
        if let existing = moduleSymbols[symbol.name] {
            throw SymbolError.duplicateSymbol(
                name: symbol.name,
                existingSpan: existing.span,
                newSpan: symbol.span
            )
        }
        
        // 检查是否与其他导入冲突
        if let (existingSymbol, existingFrom) = importedSymbols[symbol.name] {
            if existingFrom != fromModule {
                throw SymbolError.importConflict(
                    name: symbol.name,
                    from: fromModule,
                    existingFrom: existingFrom,
                    span: symbol.span
                )
            }
            // 同一来源的重复导入，忽略
            _ = existingSymbol
            return
        }
        
        importedSymbols[symbol.name] = (symbol, fromModule)
    }
    
    // MARK: - Lookup
    
    /// 查找符号
    /// - Parameters:
    ///   - name: 符号名称
    ///   - fromFile: 查找所在的文件
    ///   - fromModule: 查找所在的模块（用于访问检查）
    /// - Returns: 找到的符号，如果未找到返回 nil
    public func lookup(
        _ name: String,
        fromFile file: String,
        fromModule: ModuleInfo? = nil
    ) -> ModuleSymbol? {
        // 1. 先查本文件 private 符号
        if let symbol = privateSymbols[file]?[name] {
            return symbol
        }
        
        // 2. 查模块级符号
        if let symbol = moduleSymbols[name] {
            // 检查访问权限
            if canAccess(symbol: symbol, from: fromModule) {
                return symbol
            }
        }
        
        // 3. 查导入的符号
        if let (symbol, _) = importedSymbols[name] {
            return symbol
        }
        
        return nil
    }
    
    /// 查找模块级符号（包括 private 符号，用于访问检查）
    /// - Parameters:
    ///   - name: 符号名称
    ///   - fromFile: 查找所在的文件（用于查找 private 符号）
    /// - Returns: 找到的符号
    public func lookupModuleSymbol(_ name: String, fromFile: String? = nil) -> ModuleSymbol? {
        // 先查模块级符号（protected/public）
        if let symbol = moduleSymbols[name] {
            return symbol
        }
        
        // 如果提供了文件路径，也查找该文件的 private 符号
        if let file = fromFile, let symbol = privateSymbols[file]?[name] {
            return symbol
        }
        
        // 查找所有文件的 private 符号（用于访问检查时报错）
        for (_, symbols) in privateSymbols {
            if let symbol = symbols[name] {
                return symbol
            }
        }
        
        return nil
    }
    
    /// 获取所有 public 符号
    /// - Returns: public 符号列表
    public func getAllPublicSymbols() -> [ModuleSymbol] {
        return moduleSymbols.values.filter { $0.access == .public }
    }
    
    /// 获取所有 protected 及以上可见性的符号
    /// - Returns: protected 和 public 符号列表
    public func getAllProtectedAndPublicSymbols() -> [ModuleSymbol] {
        return moduleSymbols.values.filter { $0.access == .protected || $0.access == .public }
    }
    
    // MARK: - Batch Import
    
    /// 批量导入模块的所有 public 符号
    /// - Parameters:
    ///   - sourceModule: 源模块
    ///   - toFile: 导入到的文件
    /// - Throws: SymbolError 如果符号冲突
    public func importAllPublicSymbols(
        from sourceModule: ModuleInfo,
        toFile file: String
    ) throws {
        guard let sourceTable = sourceModule.symbolTable else {
            return
        }
        
        let publicSymbols = sourceTable.getAllPublicSymbols()
        let fromModulePath = sourceModule.pathString
        
        for symbol in publicSymbols {
            // 导入的符号变为 private
            let importedSymbol = ModuleSymbol(
                name: symbol.name,
                kind: symbol.kind,
                access: .private,
                definedIn: symbol.definedIn,
                definedInFile: symbol.definedInFile,
                span: symbol.span,
                moduleRef: symbol.moduleRef
            )
            try addImportedSymbol(importedSymbol, fromModule: fromModulePath, toFile: file)
        }
    }
    
    // MARK: - Access Check
    
    /// 检查是否可以访问符号
    /// - Parameters:
    ///   - symbol: 要访问的符号
    ///   - from: 访问者所在的模块
    /// - Returns: 是否可以访问
    private func canAccess(symbol: ModuleSymbol, from: ModuleInfo?) -> Bool {
        switch symbol.access {
        case .public:
            return true
            
        case .protected:
            // protected 符号只能从定义模块及其子模块访问
            guard let from = from, let definedIn = symbol.definedIn else {
                return false
            }
            return isSubmoduleOf(from, definedIn)
            
        case .private:
            // private 符号只能从同一文件访问（已在 lookup 中处理）
            return false
            
        case .default:
            // 默认当作 protected
            guard let from = from, let definedIn = symbol.definedIn else {
                return false
            }
            return isSubmoduleOf(from, definedIn)
        }
    }
    
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
}



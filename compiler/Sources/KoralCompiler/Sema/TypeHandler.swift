import Foundation

private func cTypeIdentifierOrFallback(_ type: Type, fallback: String) -> String {
    return TypeHandlerRegistry.shared.cTypeIdentifier(for: type) ?? fallback
}

// MARK: - TypeHandler Protocol

/// 类型处理器协议 - 确保所有类型都有完整的处理逻辑
/// 
/// 这个协议定义了处理不同类型所需的所有方法，包括：
/// - 成员解析
/// - 可见性检查
/// - C 代码生成
/// - 拷贝和析构代码生成
///
/// 通过使用协议，我们可以确保每种类型都有完整的处理逻辑，
/// 避免遗漏特定类型的处理。
public protocol TypeHandler {
    /// 处理器支持的类型种类
    var supportedKinds: Set<TypeHandlerKind> { get }
    
    /// 检查此处理器是否可以处理给定类型
    func canHandle(_ type: Type) -> Bool
    
    /// 获取类型的成员列表
    /// - Parameter type: 要查询的类型
    /// - Returns: 成员列表，每个成员包含名称、类型和是否可变
    func getMembers(_ type: Type) -> [(name: String, type: Type, mutable: Bool)]
    
    /// 获取类型的方法列表
    /// - Parameter type: 要查询的类型
    /// - Returns: 方法名称列表
    func getMethods(_ type: Type) -> [String]
    
    /// 检查类型是否需要拷贝函数
    /// - Parameter type: 要检查的类型
    /// - Returns: 是否需要拷贝函数
    func needsCopyFunction(_ type: Type) -> Bool
    
    /// 检查类型是否需要析构函数
    /// - Parameter type: 要检查的类型
    /// - Returns: 是否需要析构函数
    func needsDropFunction(_ type: Type) -> Bool
    
    /// 生成 C 类型名称
    /// - Parameter type: 要生成的类型
    /// - Returns: C 类型名称字符串
    func generateCTypeName(_ type: Type) -> String
    
    /// 生成拷贝代码
    /// - Parameters:
    ///   - type: 要拷贝的类型
    ///   - source: 源变量名
    ///   - dest: 目标变量名
    /// - Returns: 拷贝代码字符串
    func generateCopyCode(_ type: Type, source: String, dest: String) -> String
    
    /// 生成析构代码
    /// - Parameters:
    ///   - type: 要析构的类型
    ///   - value: 变量名
    /// - Returns: 析构代码字符串
    func generateDropCode(_ type: Type, value: String) -> String
    
    /// 获取类型的限定名（用于 C 代码生成）
    /// - Parameter type: 要查询的类型
    /// - Returns: 限定名字符串
    func getQualifiedName(_ type: Type) -> String
    
    /// 检查类型是否包含泛型参数
    /// - Parameter type: 要检查的类型
    /// - Returns: 是否包含泛型参数
    func containsGenericParameter(_ type: Type) -> Bool
}

// MARK: - TypeHandlerKind

/// 类型处理器支持的类型种类
public enum TypeHandlerKind: Hashable {
    case primitive      // 原始类型（Int, Bool, etc.）
    case structure      // 结构体类型
    case union          // 联合类型
    case function       // 函数类型
    case reference      // 引用类型
    case pointer        // 指针类型
    case genericParameter  // 泛型参数
    case genericStruct  // 泛型结构体
    case genericUnion   // 泛型联合
    case module         // 模块类型
    case typeVariable   // 类型变量
}

// MARK: - Default Implementation

extension TypeHandler {
    /// 默认实现：检查类型是否可以处理
    public func canHandle(_ type: Type) -> Bool {
        let kind = TypeHandlerKind.from(type)
        return supportedKinds.contains(kind)
    }
    
    /// 默认实现：大多数类型没有成员
    public func getMembers(_ type: Type) -> [(name: String, type: Type, mutable: Bool)] {
        return []
    }
    
    /// 默认实现：大多数类型没有方法
    public func getMethods(_ type: Type) -> [String] {
        return []
    }
    
    /// 默认实现：原始类型不需要拷贝函数
    public func needsCopyFunction(_ type: Type) -> Bool {
        return false
    }
    
    /// 默认实现：原始类型不需要析构函数
    public func needsDropFunction(_ type: Type) -> Bool {
        return false
    }
    
    /// 默认实现：检查是否包含泛型参数
    public func containsGenericParameter(_ type: Type) -> Bool {
        return type.containsGenericParameter
    }
}

// MARK: - TypeHandlerKind Extension

extension TypeHandlerKind {
    /// 从 Type 获取对应的 TypeHandlerKind
    public static func from(_ type: Type) -> TypeHandlerKind {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return .primitive
        case .structure:
            return .structure
        case .union:
            return .union
        case .function:
            return .function
        case .reference:
            return .reference
        case .pointer:
            return .pointer
        case .genericParameter:
            return .genericParameter
        case .genericStruct:
            return .genericStruct
        case .genericUnion:
            return .genericUnion
        case .module:
            return .module
        case .typeVariable:
            return .typeVariable
        }
    }
}


// MARK: - StructHandler

/// 结构体类型处理器
/// 
/// 处理 struct 类型的所有操作，包括：
/// - 成员解析
/// - 可见性检查
/// - C 代码生成（类型声明、拷贝、析构）
public class StructHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.structure]
    }
    
    public init() {}
    
    public func canHandle(_ type: Type) -> Bool {
        if case .structure = type {
            return true
        }
        return false
    }
    
    public func getMembers(_ type: Type) -> [(name: String, type: Type, mutable: Bool)] {
        guard case .structure(let decl) = type else {
            return []
        }
        return decl.members
    }
    
    public func getMethods(_ type: Type) -> [String] {
        // 方法信息存储在 SymbolTable 中，这里返回空
        // 实际的方法查找应该通过 TypeChecker 进行
        return []
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        guard case .structure = type else {
            return false
        }
        // 结构体总是需要拷贝函数
        // 即使所有成员都是原始类型，我们也生成拷贝函数以保持一致性
        return true
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        guard case .structure = type else {
            return false
        }
        // 结构体总是需要析构函数
        return true
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        guard case .structure(let decl) = type else {
            return "void"
        }
        let qualifiedName = cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
        return "struct \(qualifiedName)"
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        guard case .structure(let decl) = type else {
            return ""
        }
        let qualifiedName = cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
        return "\(dest) = __koral_\(qualifiedName)_copy(&\(source));"
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        guard case .structure(let decl) = type else {
            return ""
        }
        let qualifiedName = cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
        return "__koral_\(qualifiedName)_drop(&\(value));"
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        guard case .structure(let decl) = type else {
            return ""
        }
        return cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        guard case .structure(let decl) = type else {
            return false
        }
        return decl.members.contains { $0.type.containsGenericParameter }
    }
    
    // MARK: - Struct-Specific Methods
    
    /// 获取结构体的访问修饰符
    public func getAccessModifier(_ type: Type) -> AccessModifier? {
        guard case .structure(let decl) = type else {
            return nil
        }
        return decl.access
    }
    
    /// 获取结构体的模块路径
    public func getModulePath(_ type: Type) -> [String]? {
        guard case .structure(let decl) = type else {
            return nil
        }
        return decl.modulePath
    }
    
    /// 获取结构体的源文件
    public func getSourceFile(_ type: Type) -> String? {
        guard case .structure(let decl) = type else {
            return nil
        }
        return decl.sourceFile
    }
    
    /// 检查结构体是否是泛型实例化
    public func isGenericInstantiation(_ type: Type) -> Bool {
        guard case .structure(let decl) = type else {
            return false
        }
        return decl.isGenericInstantiation
    }
    
    /// 获取泛型类型参数
    public func getTypeArguments(_ type: Type) -> [Type]? {
        guard case .structure(let decl) = type else {
            return nil
        }
        return decl.typeArguments
    }
}


// MARK: - UnionHandler

/// 联合类型处理器
/// 
/// 处理 union 类型的所有操作，包括：
/// - Case 解析
/// - 可见性检查
/// - C 代码生成（类型声明、拷贝、析构）
/// 
/// 注意：Union 类型的拷贝逻辑需要特别处理，因为需要根据 tag 来决定
/// 拷贝哪个 case 的数据。
public class UnionHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.union]
    }
    
    public init() {}
    
    public func canHandle(_ type: Type) -> Bool {
        if case .union = type {
            return true
        }
        return false
    }
    
    public func getMembers(_ type: Type) -> [(name: String, type: Type, mutable: Bool)] {
        // Union 没有传统意义上的成员，它有 cases
        // 返回空数组，使用 getCases 方法获取 cases
        return []
    }
    
    public func getMethods(_ type: Type) -> [String] {
        return []
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        guard case .union = type else {
            return false
        }
        // Union 总是需要拷贝函数
        return true
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        guard case .union = type else {
            return false
        }
        // Union 总是需要析构函数
        return true
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        guard case .union(let decl) = type else {
            return "void"
        }
        let qualifiedName = cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
        return "struct \(qualifiedName)"
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        guard case .union(let decl) = type else {
            return ""
        }
        let qualifiedName = cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
        return "\(dest) = __koral_\(qualifiedName)_copy(&\(source));"
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        guard case .union(let decl) = type else {
            return ""
        }
        let qualifiedName = cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
        return "__koral_\(qualifiedName)_drop(&\(value));"
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        guard case .union(let decl) = type else {
            return ""
        }
        return cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        guard case .union(let decl) = type else {
            return false
        }
        return decl.cases.contains { c in
            c.parameters.contains { $0.type.containsGenericParameter }
        }
    }
    
    // MARK: - Union-Specific Methods
    
    /// 获取 Union 的所有 cases
    public func getCases(_ type: Type) -> [UnionCase]? {
        guard case .union(let decl) = type else {
            return nil
        }
        return decl.cases
    }
    
    /// 获取指定 case 的信息
    public func getCase(_ type: Type, name: String) -> UnionCase? {
        guard case .union(let decl) = type else {
            return nil
        }
        return decl.cases.first { $0.name == name }
    }
    
    /// 获取 case 的索引（用于 tag）
    public func getCaseIndex(_ type: Type, name: String) -> Int? {
        guard case .union(let decl) = type else {
            return nil
        }
        return decl.cases.firstIndex { $0.name == name }
    }
    
    /// 获取 Union 的访问修饰符
    public func getAccessModifier(_ type: Type) -> AccessModifier? {
        guard case .union(let decl) = type else {
            return nil
        }
        return decl.access
    }
    
    /// 获取 Union 的模块路径
    public func getModulePath(_ type: Type) -> [String]? {
        guard case .union(let decl) = type else {
            return nil
        }
        return decl.modulePath
    }
    
    /// 获取 Union 的源文件
    public func getSourceFile(_ type: Type) -> String? {
        guard case .union(let decl) = type else {
            return nil
        }
        return decl.sourceFile
    }
    
    /// 检查 Union 是否是泛型实例化
    public func isGenericInstantiation(_ type: Type) -> Bool {
        guard case .union(let decl) = type else {
            return false
        }
        return decl.isGenericInstantiation
    }
    
    /// 获取泛型类型参数
    public func getTypeArguments(_ type: Type) -> [Type]? {
        guard case .union(let decl) = type else {
            return nil
        }
        return decl.typeArguments
    }
    
    /// 生成 Union 构造器代码
    /// 
    /// 这个方法生成创建 Union 实例的代码，包括设置 tag 和初始化对应 case 的数据
    public func generateConstructorCode(
        _ type: Type,
        caseName: String,
        resultVar: String,
        argAssignments: [(fieldName: String, argCode: String)]
    ) -> String {
        guard case .union(let decl) = type else {
            return ""
        }
        
        let typeName = cTypeIdentifierOrFallback(type, fallback: decl.qualifiedName)
        guard let tagIndex = getCaseIndex(type, name: caseName) else {
            return ""
        }
        
        var code = ""
        code += "struct \(typeName) \(resultVar);\n"
        code += "\(resultVar).tag = \(tagIndex);\n"
        
        let escapedCaseName = caseName.replacingOccurrences(of: "-", with: "_")
        for (fieldName, argCode) in argAssignments {
            code += "\(resultVar).data.\(escapedCaseName).\(fieldName) = \(argCode);\n"
        }
        
        return code
    }
}


// MARK: - GenericHandler

/// 泛型类型处理器
/// 
/// 处理泛型类型（genericStruct、genericUnion、genericParameter）的所有操作。
/// 
/// 泛型类型在单态化之前是未实例化的模板，需要特殊处理：
/// - genericStruct/genericUnion: 带有类型参数的泛型类型引用
/// - genericParameter: 泛型参数（如 T, U）
public class GenericHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.genericStruct, .genericUnion, .genericParameter]
    }
    
    public init() {}
    
    public func canHandle(_ type: Type) -> Bool {
        switch type {
        case .genericStruct, .genericUnion, .genericParameter:
            return true
        default:
            return false
        }
    }
    
    public func getMembers(_ type: Type) -> [(name: String, type: Type, mutable: Bool)] {
        // 泛型类型在实例化之前没有具体的成员
        return []
    }
    
    public func getMethods(_ type: Type) -> [String] {
        return []
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        // 泛型类型在实例化后才需要拷贝函数
        // 这里返回 true，因为实例化后的类型通常需要拷贝
        switch type {
        case .genericStruct, .genericUnion:
            return true
        case .genericParameter:
            // 泛型参数本身不需要拷贝函数，它会被替换为具体类型
            return false
        default:
            return false
        }
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        switch type {
        case .genericStruct, .genericUnion:
            return true
        case .genericParameter:
            return false
        default:
            return false
        }
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        switch type {
        case .genericStruct(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            return "struct \(template)_\(argsStr)"
        case .genericUnion(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            return "struct \(template)_\(argsStr)"
        case .genericParameter(let name):
            // 泛型参数不应该出现在代码生成阶段
            return "/* generic parameter \(name) */"
        default:
            return "void"
        }
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        switch type {
        case .genericStruct(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            let qualifiedName = "\(template)_\(argsStr)"
            return "\(dest) = __koral_\(qualifiedName)_copy(&\(source));"
        case .genericUnion(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            let qualifiedName = "\(template)_\(argsStr)"
            return "\(dest) = __koral_\(qualifiedName)_copy(&\(source));"
        case .genericParameter:
            // 泛型参数不应该出现在代码生成阶段
            return "/* cannot copy generic parameter */"
        default:
            return ""
        }
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        switch type {
        case .genericStruct(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            let qualifiedName = "\(template)_\(argsStr)"
            return "__koral_\(qualifiedName)_drop(&\(value));"
        case .genericUnion(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            let qualifiedName = "\(template)_\(argsStr)"
            return "__koral_\(qualifiedName)_drop(&\(value));"
        case .genericParameter:
            return "/* cannot drop generic parameter */"
        default:
            return ""
        }
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        switch type {
        case .genericStruct(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            return "\(template)_\(argsStr)"
        case .genericUnion(let template, let args):
            let argsStr = args.map { $0.layoutKey }.joined(separator: "_")
            return "\(template)_\(argsStr)"
        case .genericParameter(let name):
            return name
        default:
            return ""
        }
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        switch type {
        case .genericParameter:
            return true
        case .genericStruct(_, let args), .genericUnion(_, let args):
            return args.contains { $0.containsGenericParameter }
        default:
            return false
        }
    }
    
    // MARK: - Generic-Specific Methods
    
    /// 获取泛型模板名称
    public func getTemplateName(_ type: Type) -> String? {
        switch type {
        case .genericStruct(let template, _), .genericUnion(let template, _):
            return template
        case .genericParameter(let name):
            return name
        default:
            return nil
        }
    }
    
    /// 获取类型参数列表
    public func getTypeArguments(_ type: Type) -> [Type]? {
        switch type {
        case .genericStruct(_, let args), .genericUnion(_, let args):
            return args
        default:
            return nil
        }
    }
    
    /// 检查是否是泛型结构体
    public func isGenericStruct(_ type: Type) -> Bool {
        if case .genericStruct = type {
            return true
        }
        return false
    }
    
    /// 检查是否是泛型联合
    public func isGenericUnion(_ type: Type) -> Bool {
        if case .genericUnion = type {
            return true
        }
        return false
    }
    
    /// 检查是否是泛型参数
    public func isGenericParameter(_ type: Type) -> Bool {
        if case .genericParameter = type {
            return true
        }
        return false
    }
    
    /// 获取泛型参数名称
    public func getGenericParameterName(_ type: Type) -> String? {
        if case .genericParameter(let name) = type {
            return name
        }
        return nil
    }
}


// MARK: - PrimitiveHandler

/// 原始类型处理器
/// 
/// 处理所有原始类型（Int, Bool, Float, Void, Never 等）
public class PrimitiveHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.primitive]
    }
    
    public init() {}
    
    public func canHandle(_ type: Type) -> Bool {
        switch type {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .bool, .void, .never:
            return true
        default:
            return false
        }
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        return false
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        return false
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        switch type {
        case .int: return "intptr_t"
        case .int8: return "int8_t"
        case .int16: return "int16_t"
        case .int32: return "int32_t"
        case .int64: return "int64_t"
        case .uint: return "uintptr_t"
        case .uint8: return "uint8_t"
        case .uint16: return "uint16_t"
        case .uint32: return "uint32_t"
        case .uint64: return "uint64_t"
        case .float32: return "float"
        case .float64: return "double"
        case .bool: return "int"
        case .void: return "void"
        case .never: return "void"
        default: return "void"
        }
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        // 原始类型直接赋值
        return "\(dest) = \(source);"
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        // 原始类型不需要析构
        return ""
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        return type.description
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        return false
    }
}

// MARK: - ReferenceHandler

/// 引用类型处理器
/// 
/// 处理引用类型（reference）的所有操作
public class ReferenceHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.reference]
    }
    
    public init() {}
    
    public func canHandle(_ type: Type) -> Bool {
        if case .reference = type {
            return true
        }
        return false
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        // 引用类型需要增加引用计数
        return true
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        // 引用类型需要减少引用计数
        return true
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        return "struct Ref"
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        return """
        \(dest) = \(source);
        __koral_retain(\(dest).control);
        """
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        return "__koral_release(\(value).control);"
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        guard case .reference(let inner) = type else {
            return ""
        }
        return "\(inner.description) ref"
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        guard case .reference(let inner) = type else {
            return false
        }
        return inner.containsGenericParameter
    }
    
    // MARK: - Reference-Specific Methods
    
    /// 获取引用的内部类型
    public func getInnerType(_ type: Type) -> Type? {
        guard case .reference(let inner) = type else {
            return nil
        }
        return inner
    }
}

// MARK: - FunctionHandler

/// 函数类型处理器
/// 
/// 处理函数类型的所有操作
public class FunctionHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.function]
    }
    
    public init() {}
    
    public func canHandle(_ type: Type) -> Bool {
        if case .function = type {
            return true
        }
        return false
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        // 函数类型（闭包）可能需要拷贝环境
        return true
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        // 函数类型（闭包）可能需要释放环境
        return true
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        return "struct __koral_Closure"
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        // 闭包的拷贝需要特殊处理
        return "\(dest) = \(source);"
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        // 闭包的析构需要特殊处理
        return ""
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        guard case .function(let params, let returns) = type else {
            return ""
        }
        let paramTypes = params.map { $0.type.description }.joined(separator: ", ")
        return "(\(paramTypes)) -> \(returns)"
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        guard case .function(let params, let returns) = type else {
            return false
        }
        return returns.containsGenericParameter || params.contains { $0.type.containsGenericParameter }
    }
    
    // MARK: - Function-Specific Methods
    
    /// 获取函数参数列表
    public func getParameters(_ type: Type) -> [Parameter]? {
        guard case .function(let params, _) = type else {
            return nil
        }
        return params
    }
    
    /// 获取函数返回类型
    public func getReturnType(_ type: Type) -> Type? {
        guard case .function(_, let returns) = type else {
            return nil
        }
        return returns
    }
}

// MARK: - PointerHandler

/// 指针类型处理器
public class PointerHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.pointer]
    }
    
    public init() {}
    
    public func canHandle(_ type: Type) -> Bool {
        if case .pointer = type {
            return true
        }
        return false
    }
    
    public func needsCopyFunction(_ type: Type) -> Bool {
        return false
    }
    
    public func needsDropFunction(_ type: Type) -> Bool {
        return false
    }
    
    public func generateCTypeName(_ type: Type) -> String {
        guard case .pointer(let element) = type else {
            return "void*"
        }
        // 递归获取元素类型的 C 类型名
        let registry = TypeHandlerRegistry.shared
        let elementCType = registry.handler(for: element).generateCTypeName(element)
        return "\(elementCType)*"
    }
    
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        return "\(dest) = \(source);"
    }
    
    public func generateDropCode(_ type: Type, value: String) -> String {
        return ""
    }
    
    public func getQualifiedName(_ type: Type) -> String {
        guard case .pointer(let element) = type else {
            return ""
        }
        return "\(element.description) ptr"
    }
    
    public func containsGenericParameter(_ type: Type) -> Bool {
        guard case .pointer(let element) = type else {
            return false
        }
        return element.containsGenericParameter
    }
    
    // MARK: - Pointer-Specific Methods
    
    /// 获取指针的元素类型
    public func getElementType(_ type: Type) -> Type? {
        guard case .pointer(let element) = type else {
            return nil
        }
        return element
    }
}

// MARK: - TypeHandlerRegistry

/// 类型处理器注册表
/// 
/// 管理所有类型处理器，提供统一的类型处理接口。
/// 使用单例模式确保全局只有一个注册表实例。
public final class TypeHandlerRegistry: @unchecked Sendable {
    /// 共享实例
    public static let shared = TypeHandlerRegistry()
    
    /// 已注册的处理器列表
    private var handlers: [TypeHandler] = []

    /// 可选的 C 类型名解析器（用于 CodeGen 注入冲突安全命名）
    private var cTypeNameResolver: ((Type) -> String?)?
    
    /// 默认处理器（用于未知类型）
    private let defaultHandler: TypeHandler
    
    private init() {
        // 创建默认处理器
        defaultHandler = PrimitiveHandler()
        
        // 注册所有内置处理器
        registerBuiltinHandlers()
    }
    
    /// 注册内置处理器
    private func registerBuiltinHandlers() {
        handlers.append(PrimitiveHandler())
        handlers.append(StructHandler())
        handlers.append(UnionHandler())
        handlers.append(GenericHandler())
        handlers.append(ReferenceHandler())
        handlers.append(FunctionHandler())
        handlers.append(PointerHandler())
    }
    
    /// 注册自定义处理器
    public func register(_ handler: TypeHandler) {
        handlers.insert(handler, at: 0)  // 自定义处理器优先
    }

    /// 设置 C 类型名解析器
    ///
    /// 用于 CodeGen 注入冲突安全的 struct/union 命名规则。
    public func setCTypeNameResolver(_ resolver: ((Type) -> String?)?) {
        cTypeNameResolver = resolver
    }

    /// 获取用于函数命名的 C 类型标识符（不包含 `struct ` 前缀）
    public func cTypeIdentifier(for type: Type) -> String? {
        guard let override = cTypeNameResolver?(type) else { return nil }
        if override.hasPrefix("struct ") {
            return String(override.dropFirst("struct ".count))
        }
        return override
    }
    
    /// 获取类型对应的处理器
    public func handler(for type: Type) -> TypeHandler {
        for handler in handlers {
            if handler.canHandle(type) {
                return handler
            }
        }
        return defaultHandler
    }
    
    /// 获取指定种类的处理器
    public func handler(for kind: TypeHandlerKind) -> TypeHandler? {
        for handler in handlers {
            if handler.supportedKinds.contains(kind) {
                return handler
            }
        }
        return nil
    }
    
    // MARK: - Convenience Methods
    
    /// 生成类型的 C 类型名
    public func generateCTypeName(_ type: Type) -> String {
        if let override = cTypeNameResolver?(type) {
            return override
        }
        return handler(for: type).generateCTypeName(type)
    }

    /// 生成已解析类型的 C 类型名（用于 CodeGen）
    public func generateConcreteCTypeName(_ type: Type) -> String {
        switch type {
        case .genericParameter(let name):
            fatalError("Generic parameter \(name) should be resolved before CodeGen")
        case .genericStruct(let template, _):
            fatalError("Generic struct \(template) should be resolved before CodeGen")
        case .genericUnion(let template, _):
            fatalError("Generic union \(template) should be resolved before CodeGen")
        case .module:
            fatalError("Module type should not appear in CodeGen")
        case .typeVariable(let tv):
            fatalError("Type variable \(tv) should be resolved before CodeGen")
        default:
            return generateCTypeName(type)
        }
    }
    
    /// 生成拷贝代码
    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        return handler(for: type).generateCopyCode(type, source: source, dest: dest)
    }
    
    /// 生成析构代码
    public func generateDropCode(_ type: Type, value: String) -> String {
        return handler(for: type).generateDropCode(type, value: value)
    }
    
    /// 检查类型是否需要拷贝函数
    public func needsCopyFunction(_ type: Type) -> Bool {
        return handler(for: type).needsCopyFunction(type)
    }
    
    /// 检查类型是否需要析构函数
    public func needsDropFunction(_ type: Type) -> Bool {
        return handler(for: type).needsDropFunction(type)
    }
    
    /// 获取类型的限定名
    public func getQualifiedName(_ type: Type) -> String {
        return handler(for: type).getQualifiedName(type)
    }
    
    /// 获取类型的成员
    public func getMembers(_ type: Type) -> [(name: String, type: Type, mutable: Bool)] {
        return handler(for: type).getMembers(type)
    }
    
    /// 检查类型是否包含泛型参数
    public func containsGenericParameter(_ type: Type) -> Bool {
        return handler(for: type).containsGenericParameter(type)
    }
}

// MARK: - Type Extension for Handler Access

extension Type {
    /// 获取此类型的处理器
    public var handler: TypeHandler {
        return TypeHandlerRegistry.shared.handler(for: self)
    }
    
    /// 获取此类型的 C 类型名
    public var cTypeName: String {
        return TypeHandlerRegistry.shared.generateCTypeName(self)
    }
    
    /// 检查此类型是否需要拷贝函数
    public var needsCopy: Bool {
        return TypeHandlerRegistry.shared.needsCopyFunction(self)
    }
    
    /// 检查此类型是否需要析构函数
    public var needsDrop: Bool {
        return TypeHandlerRegistry.shared.needsDropFunction(self)
    }
}

/// CIdentifierUtils.swift - C 标识符生成工具
///
/// 提供统一的 C 标识符生成逻辑，供 CodeGen 和 DefId 系统共同使用。
/// 确保整个编译器中 C 标识符的生成方式一致。

import Foundation

// MARK: - C Keyword Set

/// C 语言关键字集合，包含 C89/C99/C11/C23 标准关键字和常见扩展
public let cKeywordsSet: Set<String> = [
    // C89 关键字
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "double", "else", "enum", "extern", "float", "for", "goto", "if",
    "int", "long", "register", "return", "short", "signed", "sizeof", "static",
    "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while",
    
    // C99 新增关键字
    "inline", "restrict", "_Bool", "_Complex", "_Imaginary",
    
    // C11 新增关键字
    "_Alignas", "_Alignof", "_Atomic", "_Generic", "_Noreturn", "_Static_assert", "_Thread_local",
    
    // C23 新增关键字
    "true", "false", "nullptr", "constexpr", "typeof", "typeof_unqual",
    "_BitInt", "_Decimal32", "_Decimal64", "_Decimal128",
    
    // 常见编译器扩展和保留标识符
    "asm", "__asm", "__asm__", "__attribute__", "__typeof__",
    "__inline", "__inline__", "__restrict", "__restrict__",
    "__volatile__", "__const__", "__signed__", "__unsigned__",
    
    // 标准库常用宏和类型（避免冲突）
    "NULL", "EOF", "FILE", "size_t", "ptrdiff_t", "intptr_t", "uintptr_t",
    "int8_t", "int16_t", "int32_t", "int64_t",
    "uint8_t", "uint16_t", "uint32_t", "uint64_t",
    "bool"
]

/// 转义前缀，用于避免与 C 关键字冲突
public let cEscapePrefix = "_k_"

// MARK: - Public Functions

/// 检查标识符是否需要转义，如果需要则返回转义后的标识符
/// - Parameter name: 原始标识符
/// - Returns: 转义后的标识符（如果需要转义）或原始标识符
public func escapeCKeyword(_ name: String) -> String {
    // 空字符串直接返回
    guard !name.isEmpty else { return name }
    
    // 检查是否是 C 关键字
    if cKeywordsSet.contains(name) {
        return cEscapePrefix + name
    }
    
    // 检查是否以 _k_ 开头（避免与转义后的标识符冲突）
    if name.hasPrefix(cEscapePrefix) {
        return cEscapePrefix + name
    }
    
    // 检查是否是保留标识符模式（以下划线开头后跟大写字母或双下划线）
    if name.hasPrefix("_") {
        let secondIndex = name.index(after: name.startIndex)
        if secondIndex < name.endIndex {
            let secondChar = name[secondIndex]
            if secondChar.isUppercase || secondChar == "_" {
                return cEscapePrefix + name
            }
        }
    }
    
    return name
}

/// 清理标识符，将非法字符替换为下划线，并转义 C 关键字
/// - Parameter name: 原始标识符
/// - Returns: 有效的 C 标识符
public func sanitizeCIdentifier(_ name: String) -> String {
    var result = ""
    for char in name {
        if char.isLetter || char.isNumber || char == "_" {
            result.append(char)
        } else {
            result.append("_")
        }
    }
    // 应用关键字转义
    return escapeCKeyword(result)
}

/// 生成文件标识符（用于 private 符号的文件隔离）
/// 使用文件路径的哈希值生成短标识符
/// - Parameter sourceFile: 源文件路径
/// - Returns: 文件标识符字符串（如 "f1234"）
public func generateFileIdentifier(_ sourceFile: String) -> String {
    var hash: UInt32 = 0
    for char in sourceFile.utf8 {
        hash = hash &* 31 &+ UInt32(char)
    }
    return "f\(hash % 10000)"
}

/// 生成 C 标识符
/// - Parameters:
///   - modulePath: 模块路径
///   - name: 符号名称
///   - isPrivate: 是否为 private 符号
///   - sourceFile: 源文件路径（用于 private 符号隔离）
///   - typeArguments: 泛型类型参数（可选）
/// - Returns: 唯一的 C 标识符
public func generateCIdentifier(
    modulePath: [String],
    name: String,
    isPrivate: Bool = false,
    sourceFile: String = "",
    typeArguments: [String]? = nil
) -> String {
    var parts: [String] = []
    
    // 添加模块路径
    if !modulePath.isEmpty {
        parts.append(modulePath.joined(separator: "_"))
    }
    
    // 添加文件标识符（用于 private 符号隔离）
    if isPrivate && !sourceFile.isEmpty {
        parts.append(generateFileIdentifier(sourceFile))
    }
    
    // 添加清理后的名称
    parts.append(sanitizeCIdentifier(name))
    
    // 添加类型参数（用于泛型实例化）
    if let typeArgs = typeArguments, !typeArgs.isEmpty {
        parts.append(typeArgs.joined(separator: "_"))
    }
    
    return parts.joined(separator: "_")
}

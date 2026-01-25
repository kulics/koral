# Koral 编译器架构文档

## 概述

Koral 编译器采用多阶段编译架构，将源代码转换为 C 代码，然后通过 C 编译器生成可执行文件。

## 编译流程

```
┌─────────┐    ┌─────────┐    ┌─────────────────────────────────────┐
│  Lexer  │ →  │ Parser  │ →  │              AST                    │
└─────────┘    └─────────┘    └─────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ModuleResolver (Phase 0)                         │
│  - 解析模块结构和文件依赖                                            │
│  - 记录 using 声明                                                  │
│  - 输出: ModuleTree + ImportGraph                                   │
└─────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    NameCollector (Pass 1)                           │
│  - 收集所有类型和函数名称                                            │
│  - 分配 DefId                                                       │
│  - 输出: DefIdMap + NameTable                                       │
└─────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    TypeResolver (Pass 2)                            │
│  - 解析类型成员和函数签名                                            │
│  - 构建完整的类型信息                                                │
│  - 输出: TypedDefMap + SymbolTable                                  │
└─────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    BodyChecker (Pass 3)                             │
│  - 检查函数体和表达式                                                │
│  - 进行类型推导                                                      │
│  - 输出: TypedAST                                                   │
└─────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Monomorphizer                                    │
│  - 泛型实例化                                                        │
│  - 输出: MonomorphizedAST                                           │
└─────────────────────────────────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CodeGen                                          │
│  - 生成 C 代码                                                       │
│  - 使用 DefId 生成唯一标识符                                         │
└─────────────────────────────────────────────────────────────────────┘
```

## 核心组件

### 1. DefId 系统

DefId（Definition Identifier）是唯一标识每个全局定义的核心数据结构。

**文件位置**: `compiler/Sources/KoralCompiler/Sema/DefId.swift`

```swift
public struct DefId: Hashable, Equatable {
    public let modulePath: [String]  // 模块路径
    public let name: String          // 定义名称
    public let kind: DefKind         // 定义类型
    public let sourceFile: String    // 源文件路径
    public let id: UInt64            // 唯一数字 ID
    
    public var cIdentifier: String   // 生成 C 标识符
    public var qualifiedName: String // 完整限定名
}
```

**DefIdMap** 管理所有 DefId 的分配和查找：
- `allocate()`: 分配新的 DefId
- `lookup()`: 查找 DefId
- `detectCIdentifierConflicts()`: 检测 C 标识符冲突
- `uniqueCIdentifier()`: 生成唯一的 C 标识符

### 2. Pass 架构

编译器使用三阶段 Pass 架构：

**文件位置**: `compiler/Sources/KoralCompiler/Sema/PassInterfaces.swift`

| Pass | 名称 | 职责 | 输出 |
|------|------|------|------|
| Pass 1 | NameCollector | 收集类型和函数名称 | DefIdMap, NameTable |
| Pass 2 | TypeResolver | 解析类型签名 | TypedDefMap, SymbolTable |
| Pass 3 | BodyChecker | 检查函数体 | TypedAST |

### 3. 类型处理系统

TypeHandler 协议统一了所有类型的处理逻辑。

**文件位置**: `compiler/Sources/KoralCompiler/Sema/TypeHandler.swift`

```swift
public protocol TypeHandler {
    func canHandle(_ type: Type) -> Bool
    func getMembers(_ type: Type) -> [(name: String, type: Type)]?
    func getMethods(_ type: Type) -> [String]?
    func needsCopyFunction(_ type: Type) -> Bool
    func needsDropFunction(_ type: Type) -> Bool
    func generateCTypeName(_ type: Type) -> String
    func generateCopyCode(_ type: Type, source: String, dest: String) -> String
    func generateDropCode(_ type: Type, value: String) -> String
}
```

**内置处理器**:
- `PrimitiveHandler`: 处理基本类型 (Int, Bool, etc.)
- `StructHandler`: 处理结构体类型
- `UnionHandler`: 处理联合类型
- `GenericHandler`: 处理泛型类型
- `ReferenceHandler`: 处理引用类型
- `FunctionHandler`: 处理函数类型
- `PointerHandler`: 处理指针类型

### 4. 可见性检查

VisibilityChecker 负责符号可见性验证。

**文件位置**: `compiler/Sources/KoralCompiler/Sema/VisibilityChecker.swift`

```swift
public class VisibilityChecker {
    func canAccessDirectly(...) -> Bool
    func getRequiredPrefix(...) -> String
    func checkTypeVisibility(...) throws
}
```

### 5. 诊断系统

DiagnosticCollector 收集编译过程中的所有错误和警告。

**文件位置**: `compiler/Sources/KoralCompiler/Diagnostics/DiagnosticCollector.swift`

```swift
public class DiagnosticCollector {
    func error(_ message: String, at span: SourceSpan, ...)
    func warning(_ message: String, at span: SourceSpan, ...)
    func secondaryError(_ message: String, ...)
    func hasErrors() -> Bool
    func getDiagnostics() -> [Diagnostic]
}
```

**特性**:
- 收集所有错误而不是在第一个错误时停止
- 区分主要错误和次要错误（由其他错误引起）
- 支持修复建议和注释

## 模块系统

### 模块路径

模块路径是一个字符串数组，表示模块的层次结构：
- `["expr_eval"]`: 根模块
- `["expr_eval", "frontend"]`: 子模块

### 导入类型

| 类型 | 语法 | 说明 |
|------|------|------|
| 文件合并 | `using "file.koral"` | 合并同一模块的文件 |
| 模块导入 | `using self.child` | 导入子模块 |
| 符号导入 | `using module.Symbol` | 导入特定符号 |
| 批量导入 | `using module.*` | 导入所有公共符号 |

## 泛型系统

### 泛型参数作用域

泛型参数存储在专门的作用域中，与普通类型分开：

```swift
public class Scope {
    private var genericParameters: [String: Type] = [:]
    
    func defineGenericParameter(_ name: String, type: Type)
    func isGenericParameter(_ name: String) -> Bool
}
```

### 泛型实例化

Monomorphizer 负责泛型实例化：
1. 收集所有泛型实例化请求
2. 为每个唯一的类型参数组合生成具体类型
3. 使用 `layoutKey` 生成唯一的类型名称

## 代码生成

### C 标识符生成

C 标识符通过以下规则生成：
1. 模块路径用下划线连接
2. Private 符号包含文件哈希
3. C 关键字自动转义（添加 `_k_` 前缀）

### 类型布局键

`Type.layoutKey` 用于生成唯一的类型标识符：
- 基本类型: `I` (Int), `B` (Bool), `V` (Void)
- 引用类型: `R_<inner>`
- 泛型类型: `<template>_<args>`

## 测试

### 单元测试

| 测试文件 | 测试内容 |
|----------|----------|
| DefIdTests.swift | DefId 系统 |
| PassArchitectureTests.swift | Pass 架构 |
| GenericScopeTests.swift | 泛型作用域 |
| TypeHandlerTests.swift | 类型处理器 |
| DiagnosticCollectorTests.swift | 诊断系统 |
| CodeGenTests.swift | 代码生成 |
| NameCollectorTests.swift | 名称收集 |

### 集成测试

集成测试位于 `compiler/Tests/Cases/` 目录，覆盖：
- 基本语法和类型
- 泛型和 trait
- 模块系统
- 错误处理

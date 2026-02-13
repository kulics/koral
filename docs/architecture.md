# Koral 编译器架构文档

## 概述

Koral 编译器采用多阶段编译架构，将源代码转换为 C 代码，然后通过 C 编译器（clang）生成可执行文件。编译器使用 Swift 6.0 编写，分为 `KoralCompiler` 库和 `koralc` 可执行目标两个模块。

## 编译流程

```
源代码 (.koral)
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Lexer + Parser                             │
│  - 词法分析 + 语法分析                                               │
│  - 输出: ASTNode (.program(globalNodes:))                           │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ModuleResolver (Phase 0)                         │
│  - 解析模块结构和文件依赖                                            │
│  - 处理 using 声明（文件合并、子模块、父模块、外部模块）                │
│  - 输出: CompilationUnit (ModuleTree + ImportGraph + AST)           │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    TypeChecker (Pass 1 → 2 → 3)                    │
│                                                                     │
│  Pass 1: NameCollector                                              │
│    - 收集所有类型和函数名称，分配 DefId                               │
│    - 输出: DefIdMap                                                  │
│                                                                     │
│  Pass 2: TypeResolver                                               │
│    - 解析类型成员和函数签名                                          │
│    - 构建完整的类型信息（StructInfo, UnionInfo, FunctionSignature）   │
│    - 输出: 填充后的 DefIdMap                                         │
│                                                                     │
│  Pass 3: BodyChecker                                                │
│    - 检查函数体和表达式，进行类型推导                                 │
│    - 约束求解（Constraint Solver + Unifier）                         │
│    - 穷尽性检查（ExhaustivenessChecker）                             │
│    - 输出: TypedAST + InstantiationRequests                         │
│                                                                     │
│  最终输出: TypeCheckerOutput                                         │
│    (TypedProgram, InstantiationRequests, GenericTemplateRegistry,    │
│     CompilerContext)                                                 │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Monomorphizer                                    │
│  - 处理泛型实例化请求                                                │
│  - 为每个唯一的类型参数组合生成具体类型和函数                         │
│  - 替换泛型参数为具体类型（TypeSubstitution）                        │
│  - 输出: MonomorphizedProgram (仅包含具体声明)                       │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CodeGen                                          │
│  - 逃逸分析（EscapeAnalysis）决定栈/堆分配                          │
│  - 生成 C 代码（类型声明、函数、内存管理）                            │
│  - Lambda 闭包代码生成                                               │
│  - 输出: .c 文件                                                     │
└─────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Clang                                            │
│  - 编译 C 代码 + koral_runtime.c → 可执行文件                       │
│  - 链接 foreign using 声明的外部库                                   │
└─────────────────────────────────────────────────────────────────────┘
```

## Driver

`Driver` 是编译器的入口点，负责协调整个编译流程。

**文件位置**: `compiler/Sources/KoralCompiler/Driver/Driver.swift`

支持三种命令：
- `build`（默认）：编译为可执行文件
- `run`：编译并运行
- `emit-c`：仅生成 C 代码

命令行选项：
- `-o, --output <path>`：输出目录
- `--no-std`：不链接标准库
- `--escape-analysis-report`：输出逃逸分析诊断

Driver 的主要流程：
1. 初始化 `ModuleResolver`，加载标准库（`std/std.koral`）
2. 解析用户代码，合并标准库和用户代码的 AST
3. 合并两个 `ImportGraph`
4. 调用 `TypeChecker.check()` 进行语义分析
5. 调用 `Monomorphizer.monomorphize()` 进行泛型实例化
6. 调用 `CodeGen.generate()` 生成 C 代码
7. 调用 clang 编译 C 代码（链接 `koral_runtime.c` 和 foreign 库）

## 核心组件

### 1. DefId 系统

DefId（Definition Identifier）是唯一标识每个全局定义的核心数据结构，设计参考 Rust 编译器。

**文件位置**: `compiler/Sources/KoralCompiler/Sema/DefId.swift`

DefId 本身是一个轻量级的纯索引：

```swift
public struct DefId: Hashable, Equatable {
    public let id: UInt64  // 唯一数字 ID
}
```

所有元数据由 `DefIdMap` 统一管理，通过 `DefId.id` 查询：

```swift
public class DefIdMap {
    // 核心映射
    private var idToMetadata: [UInt64: Metadata]     // ID → 元数据
    private var nameToDefId: [String: DefId]          // 名称键 → DefId
    
    // 类型信息映射
    private var typeMap: [UInt64: Type]                // DefId → 类型
    private var signatureMap: [UInt64: FunctionSignature]  // DefId → 函数签名
    private var structInfoMap: [UInt64: StructTypeInfo]    // DefId → 结构体信息
    private var unionInfoMap: [UInt64: UnionTypeInfo]      // DefId → 联合类型信息
    private var symbolInfoMap: [UInt64: SymbolInfo]        // DefId → 符号信息
    
    // 泛型模板映射
    private var genericStructTemplates: [String: DefId]
    private var genericUnionTemplates: [String: DefId]
    private var genericFunctionTemplates: [String: DefId]
    
    // FFI 相关
    private var foreignStructFields: [UInt64: [(name: String, type: Type)]]
    private var cnameMap: [UInt64: String]
    
    // 导入记录
    private var importRecords: [UInt64: ImportRecord]
}
```

`Metadata` 包含定义的基本信息：

```swift
public struct Metadata {
    public let modulePath: [String]   // 模块路径
    public let name: String           // 定义名称
    public let kind: DefKind          // 定义类型
    public let sourceFile: String     // 源文件路径
    public let access: AccessModifier // 访问修饰符
    public let span: SourceSpan       // 源码位置
}
```

`DefKind` 枚举：

```swift
public enum DefKind: Hashable, Equatable {
    case type(TypeDefKind)                    // structure, union, trait, opaque
    case function
    case variable
    case module
    case genericTemplate(GenericTemplateKind) // structure, union, function
}
```

关键方法：
- `allocate()` — 分配新的 DefId
- `lookup(modulePath:name:sourceFile:)` — 查找 DefId（sourceFile 用于 private 符号精确查找）
- `detectCIdentifierConflicts()` — 检测 C 标识符冲突
- `uniqueCIdentifier(for:)` — 生成唯一的 C 标识符（带冲突解决）

### 2. CompilerContext

`CompilerContext` 是统一的编译上下文，封装 `DefIdMap` 并提供查询/更新 API。

**文件位置**: `compiler/Sources/KoralCompiler/Sema/CompilerContext.swift`

```swift
public final class CompilerContext {
    public private(set) var defIdMap: DefIdMap
    
    // 查询 API
    func getName(_ defId: DefId) -> String?
    func getStructMembers(_ defId: DefId) -> [(name: String, type: Type, mutable: Bool)]?
    func getUnionCases(_ defId: DefId) -> [UnionCase]?
    func getCIdentifier(_ defId: DefId) -> String?
    
    // 类型工具
    func getLayoutKey(_ type: Type) -> String    // 生成唯一类型标识符
    func getDebugName(_ type: Type) -> String    // 生成可读调试名称
    func containsGenericParameter(_ type: Type) -> Bool
    func freeTypeVariables(in type: Type) -> [TypeVariable]
    
    // 更新 API
    func updateStructInfo(defId:members:isGenericInstantiation:typeArguments:templateName:)
    func updateUnionInfo(defId:cases:isGenericInstantiation:typeArguments:templateName:)
    func createSymbol(name:modulePath:sourceFile:type:kind:...) -> Symbol
}
```

`CompilerContext` 贯穿整个编译流程，从 TypeChecker 传递到 Monomorphizer 再到 CodeGen。

### 3. 类型系统

**文件位置**: `compiler/Sources/KoralCompiler/Sema/Type.swift`

```swift
public indirect enum Type {
    // 原始类型
    case int, int8, int16, int32, int64
    case uint, uint8, uint16, uint32, uint64
    case float32, float64
    case bool, void, never
    
    // 复合类型
    case function(parameters: [Parameter], returns: Type)
    case structure(defId: DefId)
    case union(defId: DefId)
    case reference(inner: Type)
    case pointer(element: Type)
    case weakReference(inner: Type)
    case opaque(defId: DefId)           // foreign type
    
    // 泛型相关
    case genericParameter(name: String)
    case genericStruct(template: String, args: [Type])
    case genericUnion(template: String, args: [Type])
    
    // 内部使用
    case module(info: ModuleSymbolInfo)
    case typeVariable(TypeVariable)     // 类型推导中的未知类型
}
```

注意：`structure`、`union`、`opaque` 类型仅存储 `DefId`，具体的成员/case 信息通过 `DefIdMap` 查询。这避免了循环引用问题，也使得类型相等性比较高效（只比较 DefId）。

### 4. Pass 架构

**文件位置**: `compiler/Sources/KoralCompiler/Sema/PassInterfaces.swift`

编译器使用 Phase 0 + 三阶段 Pass 架构，每个 Pass 有明确的输入/输出类型：

| 阶段 | 名称 | 输入 | 输出 | 职责 |
|------|------|------|------|------|
| Phase 0 | ModuleResolver | 源文件路径 | `ModuleResolverOutput` | 解析模块结构、文件依赖、using 声明 |
| Pass 1 | NameCollector | `ModuleResolverOutput` | `NameCollectorOutput` | 收集类型和函数名称，分配 DefId |
| Pass 2 | TypeResolver | `NameCollectorOutput` | `TypeResolverOutput` | 解析类型成员和函数签名 |
| Pass 3 | BodyChecker | `TypeResolverOutput` | `BodyCheckerOutput` | 检查函数体，类型推导，穷尽性检查 |

Pass 输出采用嵌套结构，每个 Pass 的输出包含前一个 Pass 的输出：

```
BodyCheckerOutput
  ├── typedAST: TypedProgram
  ├── instantiationRequests: Set<InstantiationRequest>
  └── typeResolverOutput: TypeResolverOutput
        └── nameCollectorOutput: NameCollectorOutput
              ├── defIdMap: DefIdMap
              └── moduleResolverOutput: ModuleResolverOutput
                    ├── moduleTree: ModuleTree
                    ├── importGraph: ImportGraph
                    ├── astNodes: [GlobalNode]
                    └── nodeSourceInfoList: [GlobalNodeSourceInfo]
```

TypeChecker 最终输出 `TypeCheckerOutput`：

```swift
public struct TypeCheckerOutput {
    public let program: TypedProgram
    public let instantiationRequests: Set<InstantiationRequest>
    public let genericTemplates: GenericTemplateRegistry
    public let context: CompilerContext
}
```

### 5. 类型处理系统（TypeHandler）

**文件位置**: `compiler/Sources/KoralCompiler/Sema/TypeHandler.swift`

`TypeHandler` 协议统一了所有类型的处理逻辑，包括成员解析、C 代码生成、拷贝/析构代码生成：

```swift
public protocol TypeHandler {
    var supportedKinds: Set<TypeHandlerKind> { get }
    func canHandle(_ type: Type) -> Bool
    func getMembers(_ type: Type) -> [(name: String, type: Type, mutable: Bool)]
    func getMethods(_ type: Type) -> [String]
    func needsCopyFunction(_ type: Type) -> Bool
    func needsDropFunction(_ type: Type) -> Bool
    func generateCTypeName(_ type: Type) -> String
    func generateCopyCode(_ type: Type, source: String, dest: String) -> String
    func generateDropCode(_ type: Type, value: String) -> String
    func getQualifiedName(_ type: Type) -> String
    func containsGenericParameter(_ type: Type) -> Bool
}
```

`TypeHandlerKind` 枚举：

```
primitive, structure, union, function, reference, pointer,
weakReference, genericParameter, genericStruct, genericUnion,
module, typeVariable, opaque
```

内置处理器（由 `TypeHandlerRegistry` 单例管理）：

| 处理器 | 处理类型 | 说明 |
|--------|----------|------|
| `PrimitiveHandler` | Int, Bool, Float32 等 | 直接映射到 C 类型，无需拷贝/析构 |
| `StructHandler` | structure | 生成 struct 声明、copy/drop 函数 |
| `UnionHandler` | union | 生成 tagged union、按 tag 分发 copy/drop |
| `GenericHandler` | genericStruct, genericUnion, genericParameter | 泛型类型，实例化后委托给具体处理器 |
| `ReferenceHandler` | reference | 引用计数（retain/release） |
| `WeakReferenceHandler` | weakReference | 弱引用计数（weak_retain/weak_release） |
| `FunctionHandler` | function | 闭包（`__koral_Closure` 结构体） |
| `PointerHandler` | pointer | 裸指针，无需拷贝/析构 |
| `OpaqueHandler` | opaque | foreign type，不透明类型 |

`TypeHandlerRegistry` 还支持注入 `CompilerContext` 和自定义 C 类型名解析器（用于 CodeGen 阶段的冲突安全命名）。

### 6. 作用域系统

**文件位置**: `compiler/Sources/KoralCompiler/Sema/Scope.swift`

`UnifiedScope` 管理符号的作用域层次，支持：

- 普通变量（`names`）和私有变量（`privateNames`，按 `name@sourceFile` 键存储）
- 类型名（`typeNames`）和私有类型名（`privateTypeNames`）
- 泛型参数（`genericParameters`，优先查找）
- 函数符号（`functionSymbols`）
- 直接可访问符号（`directlyAccessible`，用于 using 导入的符号）
- 移动语义追踪（`movedVariables`）
- 泛型模板（通过 `DefIdMap` 存储和查找）

查找优先级：泛型参数 → 私有名称（带 sourceFile）→ 普通名称 → 父作用域。

类型解析内置了原始类型映射（`resolveType`）：`"Int"` → `.int`，`"Float32"` → `.float32` 等。

### 7. 模块系统

**文件位置**: `compiler/Sources/KoralCompiler/Module/`

#### ModuleResolver

解析模块结构，处理四种 using 声明：

| 类型 | 语法 | 说明 |
|------|------|------|
| 文件合并 | `using "file"` | 合并同一模块的文件，共享符号表 |
| 子模块 | `using self.child` | 导入子模块（目录结构：`child/child.koral`） |
| 父模块 | `using super.sibling` | 通过 super 链导航到父模块再导入 |
| 外部模块 | `using std` | 从标准库或外部路径导入 |

每种导入还支持批量导入（`.*`）和符号导入（`.Symbol`）。

`ModuleInfo` 表示一个模块：

```swift
public class ModuleInfo {
    public let path: [String]           // 模块路径
    public let entryFile: String        // 入口文件（绝对路径）
    public var mergedFiles: [String]    // 合并的文件
    public var submodules: [String: ModuleInfo]
    public weak var parent: ModuleInfo?
    public var globalNodes: [(node: GlobalNode, sourceFile: String)]
    public var usingDeclarations: [UsingDeclaration]
    public var submoduleAccesses: [String: ModuleAccessInfo]
}
```

模块名必须是有效标识符：小写字母开头，只包含小写字母、数字和下划线。

#### ImportGraph

记录模块间的导入关系，用于可见性检查：

```swift
public struct ImportGraph {
    public var edges: [(source: [String], target: [String], kind: ImportKind)]
    public var symbolImports: [(module: [String], target: [String], symbol: String, kind: ImportKind)]
}
```

`ImportKind`：`local`、`moduleImport`、`batchImport`、`memberImport`。

#### AccessChecker

检查符号访问权限：

| 访问级别 | 规则 |
|----------|------|
| `public` | 任何地方可访问 |
| `protected`（默认） | 定义模块及其子模块可访问 |
| `private` | 仅同一文件可访问 |

默认访问级别：
- 全局声明（函数、类型、trait）：`protected`
- struct 字段：`protected`
- union case：`public`
- trait 方法：`public`
- using 声明：`private`

### 8. 泛型系统

#### 泛型模板

泛型模板在 Pass 1 注册到 `DefIdMap`，包含三种：

```swift
GenericStructTemplateInfo  // 泛型结构体模板
GenericUnionTemplateInfo   // 泛型联合类型模板
GenericFunctionTemplateInfo // 泛型函数模板（含可选的已检查体）
```

#### 泛型实例化（Monomorphization）

**文件位置**: `compiler/Sources/KoralCompiler/Monomorphization/`

`Monomorphizer` 处理 `InstantiationRequest`，为每个唯一的类型参数组合：
1. 生成具体的类型定义（替换泛型参数为具体类型）
2. 生成具体的函数实现
3. 使用 `layoutKey` 生成唯一的类型名称（如 `List_I` 表示 `List[Int]`）

输出 `MonomorphizedProgram`，仅包含具体（非泛型）声明，可直接用于代码生成。

### 9. 诊断系统

**文件位置**: `compiler/Sources/KoralCompiler/Diagnostics/`

| 组件 | 职责 |
|------|------|
| `DiagnosticCollector` | 收集所有错误和警告（不在第一个错误时停止） |
| `DiagnosticError` | 包装各阶段错误，附加阶段和文件信息 |
| `DiagnosticRenderer` | 渲染诊断信息（带源码片段和位置指示） |
| `SourceManager` | 管理源文件内容，提供源码片段查询 |
| `SourceSpan` / `SourceLocation` | 源码位置信息 |

`DiagnosticCollector` 区分主要错误和次要错误（由其他错误引起），支持修复建议（fixHint）和注释（notes）。

### 10. 逃逸分析

**文件位置**: `compiler/Sources/KoralCompiler/CodeGen/EscapeAnalysis.swift`

在代码生成阶段分析引用是否逃逸出作用域，决定栈/堆分配策略。

采用两阶段方法：
1. **预分析**：扫描函数体，识别所有可能逃逸的变量
2. **代码生成**：根据预分析结果决定分配策略

逃逸结果：

| 结果 | 说明 | 分配策略 |
|------|------|----------|
| `noEscape` | 不逃逸 | 栈分配 |
| `escapeToReturn` | 逃逸到返回值 | 堆分配 |
| `escapeToField` | 逃逸到结构体字段 | 堆分配 |
| `escapeToParameter` | 逃逸到函数参数 | 堆分配 |
| `unknown` | 无法确定 | 堆分配（保守策略） |

### 11. 代码生成

**文件位置**: `compiler/Sources/KoralCompiler/CodeGen/`

| 文件 | 职责 |
|------|------|
| `CodeGen.swift` | 主入口，类型声明排序，全局初始化 |
| `CodeGenExpressions.swift` | 表达式代码生成 |
| `CodeGenStatements.swift` | 语句代码生成 |
| `CodeGenTypes.swift` | 类型声明代码生成 |
| `CodeGenMemory.swift` | 内存管理（copy/drop 函数生成） |
| `CodeGenLambda.swift` | Lambda 闭包代码生成（环境结构体、捕获） |
| `CodeGenValidation.swift` | 代码生成验证 |
| `CIdentifierUtils.swift` | C 标识符生成工具 |
| `EscapeAnalysis.swift` | 逃逸分析 |

#### C 标识符生成规则

```
模块路径用下划线连接: ["std", "io"] → "std_io"
Private 符号包含文件哈希: "f1234_myFunc"
C 关键字自动转义: "int" → "_k_int"
保留标识符模式转义: "_Foo" → "_k__Foo"
```

#### 类型布局键（layoutKey）

用于生成唯一的类型标识符，在泛型实例化中使用：

| 类型 | layoutKey |
|------|-----------|
| Int | `I` |
| Bool | `B` |
| Void | `V` |
| Float32 | `F32` |
| Float64 | `F64` |
| Int8..Int64 | `I8`..`I64` |
| UInt..UInt64 | `U`..`U64` |
| reference(T) | `R_<T>` |
| pointer(T) | `P_<T>` |
| weakReference(T) | `W_<T>` |
| structure/union | `modulePath_name` |
| genericStruct | `template_arg1_arg2` |

## 目录结构

```
compiler/
├── Package.swift                    # Swift Package Manager 配置
├── Sources/
│   ├── koralc/
│   │   └── main.swift               # 编译器入口
│   └── KoralCompiler/
│       ├── Parser/
│       │   ├── Lexer.swift           # 词法分析器
│       │   ├── Parser.swift          # 语法分析器（主入口）
│       │   ├── ParserDeclarations.swift  # 声明解析
│       │   ├── ParserExpressions.swift   # 表达式解析
│       │   ├── ParserPatterns.swift      # 模式解析
│       │   ├── ParserTypes.swift         # 类型解析
│       │   ├── ParserError.swift         # 解析错误
│       │   ├── AST.swift                 # AST 节点定义
│       │   └── ASTPrinter.swift          # AST 打印
│       ├── Sema/
│       │   ├── DefId.swift               # DefId 系统和 DefIdMap
│       │   ├── CompilerContext.swift      # 统一编译上下文
│       │   ├── Type.swift                # 类型定义
│       │   ├── TypeHandler.swift         # 类型处理器协议和实现
│       │   ├── TypeChecker.swift         # 类型检查器主入口
│       │   ├── TypeCheckerPasses.swift   # Pass 调度
│       │   ├── TypeCheckerOutput.swift   # TypeChecker 输出结构
│       │   ├── NameCollector.swift       # Pass 1: 名称收集
│       │   ├── TypeResolver.swift        # Pass 2: 类型解析
│       │   ├── BodyChecker.swift         # Pass 3: 函数体检查
│       │   ├── TypeCheckerExpressions.swift  # 表达式类型检查
│       │   ├── TypeCheckerStatements.swift   # 语句类型检查
│       │   ├── TypeCheckerGenerics.swift     # 泛型类型检查
│       │   ├── TypeCheckerLambda.swift       # Lambda 类型检查
│       │   ├── TypeCheckerMethods.swift      # 方法类型检查
│       │   ├── TypeCheckerPatterns.swift     # 模式类型检查
│       │   ├── TypeCheckerTraits.swift       # Trait 类型检查
│       │   ├── TypeCheckerTypeResolution.swift # 类型解析
│       │   ├── Scope.swift               # 作用域管理
│       │   ├── Constraint.swift          # 类型约束
│       │   ├── ConstraintSolver.swift    # 约束求解器
│       │   ├── Unifier.swift             # 类型统一
│       │   ├── UnionFind.swift           # 并查集（用于类型统一）
│       │   ├── TypeVariable.swift        # 类型变量
│       │   ├── TypeSubstitution.swift    # 类型替换
│       │   ├── BidirectionalInference.swift  # 双向类型推导
│       │   ├── ExhaustivenessChecker.swift   # 穷尽性检查
│       │   ├── PatternSpace.swift            # 模式空间
│       │   ├── RecursiveTypeChecker.swift    # 递归类型检查
│       │   ├── VisibilityChecker.swift       # 可见性检查
│       │   ├── PassInterfaces.swift      # Pass 接口定义
│       │   ├── SemanticError.swift       # 语义错误
│       │   ├── SemanticErrorContext.swift # 错误上下文
│       │   ├── SemaUtils.swift           # 语义分析工具
│       │   ├── TypedAST.swift            # 类型化 AST 节点
│       │   └── TypedASTPrinter.swift     # 类型化 AST 打印
│       ├── Module/
│       │   ├── ModuleResolver.swift      # 模块解析器
│       │   ├── ImportGraph.swift         # 导入图
│       │   └── AccessChecker.swift       # 访问控制检查
│       ├── Monomorphization/
│       │   ├── Monomorphizer.swift       # 泛型实例化主入口
│       │   ├── MonomorphizerFunctions.swift      # 函数实例化
│       │   ├── MonomorphizerTypes.swift          # 类型实例化
│       │   ├── MonomorphizerTypeResolution.swift # 类型解析
│       │   ├── MonomorphizerExpressionSubstitution.swift # 表达式替换
│       │   ├── GenericTemplateRegistry.swift     # 泛型模板注册表
│       │   └── InstantiationRequest.swift        # 实例化请求
│       ├── CodeGen/
│       │   ├── CodeGen.swift             # 代码生成主入口
│       │   ├── CodeGenExpressions.swift  # 表达式代码生成
│       │   ├── CodeGenStatements.swift   # 语句代码生成
│       │   ├── CodeGenTypes.swift        # 类型声明代码生成
│       │   ├── CodeGenMemory.swift       # 内存管理代码生成
│       │   ├── CodeGenLambda.swift       # Lambda 代码生成
│       │   ├── CodeGenValidation.swift   # 代码生成验证
│       │   ├── CIdentifierUtils.swift    # C 标识符工具
│       │   └── EscapeAnalysis.swift      # 逃逸分析
│       ├── Diagnostics/
│       │   ├── DiagnosticCollector.swift  # 诊断收集器
│       │   ├── DiagnosticError.swift      # 诊断错误
│       │   ├── DiagnosticRenderer.swift   # 诊断渲染
│       │   ├── SourceManager.swift        # 源文件管理
│       │   ├── SourceLocation.swift       # 源码位置
│       │   └── SourceSpan.swift           # 源码范围
│       └── Driver/
│           └── Driver.swift              # 编译器驱动
├── Tests/
│   ├── Cases/                            # 集成测试用例 (.koral 文件)
│   ├── CasesOutput/                      # 集成测试输出（生成的 C 代码和可执行文件）
│   └── koralcTests/
│       ├── IntegrationTests.swift        # 集成测试（编译+运行 .koral 文件）
│       └── koralcTests.swift             # 其他测试
```

## 测试

### 集成测试

集成测试位于 `compiler/Tests/Cases/`，每个 `.koral` 文件是一个独立的测试用例。`IntegrationTests.swift` 中为每个测试用例定义一个 `test_xxx()` 方法，调用 `runCase(named:)` 编译并运行测试文件。

测试覆盖范围：
- 基本语法和类型（整数、浮点、字符串、布尔）
- 控制流（if/while/for/when...is/return/break/continue）
- 泛型和 trait
- 模块系统（子模块、访问控制、多文件）
- Lambda 和闭包
- FFI（foreign type/function/let）
- 内存管理（引用计数、drop、逃逸分析、弱引用）
- 标准库（List、Map、Set、Option、Result、Stream、Range、Duration）
- 错误检测（类型错误、穷尽性、重复定义等）

### 运行测试

```bash
cd compiler

# 运行所有测试
swift test

# 运行集成测试
swift test --filter IntegrationTests

# 并行运行（加速）
swift test --parallel
```

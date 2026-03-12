# Koral 编译器自举架构设计文档

> 本文档基于当前 Swift 实现的 koralc 编译器分析，为 Koral 语言自举（用 Koral 编写 koralc）提供架构参考。
> 文档不包含具体实现代码，但包含解释原理的 Koral 伪代码和 C 伪代码。

---

## 1. 自举策略总览

### 1.1 自举路径

自举采用经典的三阶段方法：

- Stage 0（当前）：Swift 编写的 koralc，编译 Koral → C → 可执行文件
- Stage 1：用 Koral 编写新的 koralc，由 Stage 0 编译
- Stage 2：用 Stage 1 编译自身，验证输出一致性

Stage 1 的目标是产生与 Stage 0 功能等价的编译器。Stage 2 用于验证自举正确性——Stage 1 和 Stage 2 的输出应当完全一致（或语义等价）。

### 1.2 自举前置条件

自举编译器需要 Koral 语言本身具备以下能力：

- 字符串处理（词法分析、源码读取、C 代码生成）
- 文件 I/O（读取源文件、写入 .c 文件）
- 进程调用（调用 clang）
- 哈希表 / 动态数组（符号表、AST 节点存储）
- 递归数据结构（AST、类型表示）
- 模式匹配（AST 遍历的核心手段）
- 泛型（容器类型、通用算法）
- Trait 对象或泛型约束（多态分派）
- FFI（调用 C 标准库的文件操作、进程管理）

### 1.3 自举范围界定

Stage 1 不需要实现所有优化。最小可行自举编译器应包含：

- 完整的词法分析和语法分析
- 完整的类型检查和类型推断
- 单态化泛型
- C 代码生成
- 基础的逃逸分析（可简化为保守策略：默认堆分配）
- 模块系统
- 基础诊断信息

可延后的特性：
- 增量编译
- 调试信息生成（DWARF）
- 栈展开（unwind）
- 非单态化泛型（类型擦除 / 字典传递）
- 高级逃逸分析优化

---

## 2. 编译器流水线

### 2.1 总体流水线

```
源文件 (.koral)
    │
    ▼
┌──────────────┐
│  模块解析     │  ModuleResolver: 解析 using 声明，构建编译单元
│  (Module)    │  输入: 入口文件路径
│              │  输出: CompilationUnit (模块树 + 导入图)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  词法分析     │  Lexer: 源码 → Token 流
│  (Lexer)     │  输入: 源码字符串
│              │  输出: Token 序列
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  语法分析     │  Parser: Token 流 → AST
│  (Parser)    │  输入: Token 序列
│              │  输出: ASTNode (未类型化的语法树)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  语义分析     │  TypeChecker: AST → TypedAST
│  (Sema)      │  包含: 名称收集、类型检查、Trait 一致性检查、
│              │        穷举性检查、可见性检查
│              │  输出: TypeCheckerOutput (TypedAST + 实例化请求 + 泛型模板注册表)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  单态化       │  Monomorphizer: 泛型模板 → 具体类型/函数
│  (Mono)      │  输入: TypeCheckerOutput
│              │  输出: MonomorphizedProgram (纯具体声明)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  代码生成     │  CodeGen: MonomorphizedProgram → C 源码
│  (CodeGen)   │  包含: 逃逸分析、ARC 插入、vtable 生成
│              │  输出: C 源码字符串
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  后端编译     │  调用 clang: C 源码 → 可执行文件
│  (Backend)   │  链接 koral_runtime.c 和外部库
└──────────────┘
```

### 2.2 各阶段数据流

```
源文件 → [ModuleResolver] → CompilationUnit
                                  │
                                  ├── rootModule: ModuleInfo
                                  │     ├── entryFile: String
                                  │     ├── mergedFiles: [String]
                                  │     └── submodules: [String: ModuleInfo]
                                  │
                                  ├── importGraph: ImportGraph
                                  │     ├── edges: [(source, target, kind)]
                                  │     ├── symbolImports: [(module, target, symbol, kind)]
                                  │     └── moduleAliases: [(module, alias, target)]
                                  │
                                  └── loadedModules: [String: ModuleInfo]

CompilationUnit → [Lexer + Parser] → ASTNode.program(globalNodes)

ASTNode → [TypeChecker] → TypeCheckerOutput
                              │
                              ├── program: TypedProgram
                              ├── instantiationRequests: Set<InstantiationRequest>
                              ├── genericTemplates: GenericTemplateRegistry
                              └── context: CompilerContext (DefIdMap + 类型信息)

TypeCheckerOutput → [Monomorphizer] → MonomorphizedProgram
                                          │
                                          ├── globalNodes: [TypedGlobalNode]  (纯具体)
                                          ├── staticMethodLookup: [String: DefId]
                                          ├── traits: [String: TraitDeclInfo]
                                          ├── vtableRequests: Set<VtableRequest>
                                          └── receiverMethodDispatch: [DefId: DispatchInfo]

MonomorphizedProgram → [CodeGen] → C 源码字符串
```

---

## 3. 关键数据结构设计

### 3.1 DefId 系统

DefId 是编译器中最核心的基础设施，参考 Rust 编译器的设计。每个全局定义（类型、函数、变量、模块）都有一个唯一的 DefId，所有元数据通过 DefIdMap 集中管理。

设计原则：
- DefId 本身是一个轻量的 UInt64 索引，用于高效比较和哈希
- 所有元数据（名称、模块路径、源文件、访问修饰符、源码位置、C 标识符）存储在 DefIdMap 中
- 通过 CompilerContext 提供统一的查询接口

```koral
// DefId 的 Koral 表示
type DefId(id UInt64)

// DefId 的种类
type DefKind {
    TypeDef(TypeDefKind),
    Function(),
    Variable(),
    Module(),
    GenericTemplate(GenericTemplateKind),
}

type TypeDefKind {
    Structure(),
    Union(),
    Trait(),
    Opaque(),
}

// DefIdMap: DefId → 元数据的集中存储
type DefIdMap(
    mut names [UInt64, String]Map,
    mut module_paths [UInt64, [String]List]Map,
    mut source_files [UInt64, String]Map,
    mut kinds [UInt64, DefKind]Map,
    mut access_modifiers [UInt64, AccessModifier]Map,
    mut spans [UInt64, SourceSpan]Map,
    mut c_identifiers [UInt64, String]Map,
    mut next_id UInt64,
)
```

自举建议：
- DefId 系统应当是最先实现的基础设施之一
- DefIdMap 的查询应通过 CompilerContext 封装，避免直接访问
- 为未来的增量编译预留：DefId 可以包含 crate/module 前缀位

### 3.2 类型系统表示

类型系统使用递归联合类型表示，这是自举中最适合用 Koral 自身 union 类型表达的部分：

```koral
type Type {
    // 基本类型
    IntType(),
    Int8Type(),
    Int16Type(),
    Int32Type(),
    Int64Type(),
    UIntType(),
    UInt8Type(),
    UInt16Type(),
    UInt32Type(),
    UInt64Type(),
    Float32Type(),
    Float64Type(),
    BoolType(),
    VoidType(),
    NeverType(),

    // 复合类型
    FunctionType(parameters [Parameter]List, returns Type ref),
    StructureType(def_id DefId),
    UnionType(def_id DefId),
    ReferenceType(inner Type ref),
    PointerType(element Type ref),
    WeakReferenceType(inner Type ref),
    OpaqueType(def_id DefId),

    // 泛型相关
    GenericParameter(name String),
    GenericStruct(template String, args [Type]List),
    GenericUnion(template String, args [Type]List),

    // 类型推断
    TypeVariable(tv TypeVar ref),

    // Trait 对象
    TraitObject(trait_name String, type_args [Type]List),

    // 模块
    ModuleType(info ModuleSymbolInfo),
}
```

自举建议：
- Type 是递归类型，需要通过 `ref` 打断递归（堆分配）
- 考虑为常用类型（Int、Bool、Void 等）使用全局单例，避免重复分配
- `stableKey` 方法用于类型的字符串化表示，作为缓存键使用

### 3.3 AST 节点设计

AST 使用两层设计：未类型化的 AST（Parser 输出）和类型化的 TypedAST（TypeChecker 输出）。

```koral
// 未类型化 AST（Parser 输出）
type ASTNode {
    Program(global_nodes [GlobalNode]List),
}

type GlobalNode {
    UsingDecl(decl UsingDeclaration),
    ForeignUsing(library String),
    ForeignFunction(name String, params [ParamDecl]List, ret TypeNode),
    ForeignType(name String),
    FunctionDecl(name String, params [ParamDecl]List, ret TypeNode, body ExprNode),
    TypeDecl(name String, fields [FieldDecl]List),
    UnionDecl(name String, cases [CaseDecl]List),
    TraitDecl(name String, parents [String]List, methods [TraitMethodSig]List),
    GivenDecl(target TypeNode, trait_name String, methods [MethodDecl]List),
    GenericFunctionDecl(type_params [TypeParamDecl]List, /* ... */),
    GenericTypeDecl(type_params [TypeParamDecl]List, /* ... */),
    // ...
}

// 类型化 AST（TypeChecker 输出）
type TypedGlobalNode {
    ForeignUsing(library_name String),
    ForeignFunction(identifier Symbol, parameters [Symbol]List),
    GlobalFunction(identifier Symbol, parameters [Symbol]List, body TypedExpr),
    TypeDeclaration(identifier Symbol, fields [Symbol]List),
    UnionDeclaration(identifier Symbol, cases [UnionCase]List),
    GivenDeclaration(target_type Type, trait_conformance TypedTraitConformance, methods [TypedMethod]List),
    // ...
}
```

自举建议：
- AST 节点大量使用 union 类型，这是 Koral 的强项
- 考虑为每个 AST 节点附加 SourceSpan，用于错误报告
- TypedAST 中的 Symbol 包含 DefId + Type + SymbolKind，是语义信息的载体

### 3.4 Symbol 与 Scope

```koral
type Symbol(
    def_id DefId,
    symbol_type Type,
    kind SymbolKind,
    method_kind CompilerMethodKind,
)

type SymbolKind {
    Variable(VariableKind),
    Function(),
    TypeSymbol(),
    ModuleSymbol(ModuleSymbolInfo),
}

type VariableKind {
    Value(),
    MutableValue(),
    Reference(),
    MutableReference(),
}
```

作用域使用链式结构，每个作用域持有父作用域的引用：

```koral
type Scope(
    mut names [String, DefId]Map,
    mut type_names [String, DefId]Map,
    mut moved_variables [String]Set,
    parent Scope ref,  // 或 [Scope]Option
)
```

自举建议：
- Scope 的 parent 链通过 `ref` 实现，利用 ARC 自动管理生命周期
- 查找符号时沿 parent 链向上搜索，直到找到或到达顶层作用域

---

## 4. 语义分析策略

### 4.1 多遍类型检查

当前编译器的语义分析采用多遍（multi-pass）策略，这对于处理前向引用和跨模块依赖至关重要：

**Pass 1 — 名称收集（NameCollector）**
- 扫描所有全局节点，收集类型名、函数名、变量名
- 为每个定义分配 DefId，注册到 DefIdMap
- 注册泛型模板到 GenericTemplateRegistry
- 此阶段不解析函数体，只收集签名

**Pass 2 — 签名解析**
- 解析所有类型签名（函数参数类型、返回类型、字段类型）
- 解析 Trait 声明和继承关系
- 解析泛型约束
- 此阶段延迟泛型约束验证（`deferGenericConstraintValidation`），避免跨模块的顺序依赖

**Pass 3 — 函数体检查（BodyChecker）**
- 逐个检查函数体
- 执行类型推断和约束求解
- 收集泛型实例化请求（InstantiationRequest）
- 检查 Trait 一致性
- 执行穷举性检查

**Pass 4 — 后处理**
- 验证所有延迟的泛型约束
- 检查未使用的导入
- 最终的可见性验证

自举建议：
- 多遍策略是必须的，因为 Koral 允许前向引用
- 名称收集阶段应尽可能轻量，只记录"存在性"信息
- 签名解析和函数体检查可以考虑按模块并行化（为未来增量编译铺路）

### 4.2 类型推断策略

当前编译器使用双向类型推断（Bidirectional Type Inference）+ 约束求解的混合策略：

**双向推断的两个方向：**
- 合成模式（Synthesis）：从表达式推断类型（自底向上）
- 检查模式（Checking）：用期望类型验证表达式（自顶向下）

**约束系统：**

```koral
type Constraint {
    // 两个类型必须相等
    Equal(lhs Type, rhs Type, span SourceSpan),
    // 类型变量必须是某个泛型类型的实例
    Instantiate(tv TypeVar, template String, args [Type]List, span SourceSpan),
    // 类型必须实现某个 Trait
    TraitBound(target_type Type, trait_name String, span SourceSpan),
    // 默认类型（整数字面量默认为 Int）
    DefaultInt(tv TypeVar, span SourceSpan),
    // 默认类型（浮点字面量默认为 Float64）
    DefaultFloat(tv TypeVar, span SourceSpan),
}
```

**求解流程：**
1. 遍历表达式，为未知类型创建 TypeVariable
2. 根据上下文生成约束（Equal、TraitBound 等）
3. 按优先级排序约束
4. 使用合一算法（Unifier）求解主要约束
5. 处理默认类型约束（DefaultInt、DefaultFloat）
6. 构建最终的 TypeSubstitution

**合一算法核心：**
- 使用并查集（Union-Find）管理类型变量的等价类
- 发生检查（Occurs Check）防止无限类型
- 支持结构化类型的递归合一（函数类型、泛型类型等）

```koral
// 合一的伪代码逻辑
// unify(T1, T2) 的核心分支：
//   TypeVar(tv), T  → 绑定 tv = T（需 occurs check）
//   T, TypeVar(tv)  → 绑定 tv = T
//   Function(p1, r1), Function(p2, r2) → 逐参数合一 + 返回类型合一
//   GenericStruct(t1, args1), GenericStruct(t2, args2) → 模板名相同 + 逐参数合一
//   相同基本类型 → 成功
//   其他 → 类型不匹配错误
```

自举建议：
- Union-Find 是类型推断的关键数据结构，需要高效实现
- TypeVariable 使用全局递增 ID，需要线程安全的计数器（自举初期可用简单全局变量）
- 约束求解器应当能够报告清晰的错误信息，包含源码位置

### 4.3 Trait 一致性检查

Trait 系统的检查包含以下方面：

- 显式一致性声明：`given Type Trait { ... }` 必须实现所有 requirement 方法
- 方法签名匹配：参数类型、返回类型必须与 Trait 声明一致
- Trait 继承：实现子 Trait 前必须先实现父 Trait
- 对象安全性：用作 Trait 对象的 Trait 不能有泛型方法或在参数/返回值中使用 Self
- 孤儿规则：`given Type Trait` 要求 Type 或 Trait 至少有一个定义在当前模块

**一致性缓存：**
当前编译器使用多级缓存避免重复检查：
- `objectSafetyCache`：Trait 名 → 是否对象安全
- `flattenedTraitMethodsCache`：Trait 名 → 展平后的所有方法签名
- `traitConformanceCache`：(类型描述, Trait 名) → 是否通过
- `genericConstraintCache`：泛型约束键 → 是否已验证

### 4.4 穷举性检查

模式匹配的穷举性检查确保 `when` 表达式覆盖所有可能的值：

- 对 Union 类型：检查所有 case 是否被覆盖
- 对 Bool 类型：检查 true 和 false
- 对数值/字符串类型：需要通配符 `_` 兜底
- 检测不可达模式（已被前面的模式覆盖的模式）

当前实现使用 PatternSpace 抽象来表示已覆盖的模式空间，逐步减少未覆盖空间。

---

## 5. 语法糖 Lowering 策略

### 5.1 需要 Lowering 的语法糖

以下语法糖应在语义分析阶段或之前被降低为更基础的表示：

| 语法糖 | Lowering 目标 |
|--------|--------------|
| `for x in collection then body` | `let mut iter = collection.iterator(); while iter.next() is .Some(x) then body` |
| `x += y` | `x = x + y`（以及其他复合赋值） |
| `a or else b` | `when a in { .Some(v) then v, .None then b }` 或 Result 版本 |
| `a and then f` | `when a in { .Some(v) then f(v), .None then .None() }` |
| `a > b` | `a.compare(b) > 0`（通过 Ord trait） |
| `a == b` | `a.equals(b)`（通过 Eq trait） |
| `a + b` | `a.add(b)`（通过 Add trait） |
| `a[i]` | `a.at(i)` / `a.update_at(i, v)`（通过 Index/MutIndex trait） |
| 集合字面量 `[1, 2, 3]` | `List.new()` + 逐元素 `push` |
| Map 字面量 `["a": 1]` | `Map.new()` + 逐键值 `insert` |
| 隐式成员表达式 `.Some(v)` | 根据上下文类型补全为 `[T]Option.Some(v)` |
| 字符串插值 `"hello \(name)"` | 字符串拼接表达式 |

### 5.2 Lowering 时机

建议的 Lowering 时机：

- **Parser 阶段 Lowering**：字符串插值（已在词法分析阶段处理为 InterpolatedStringPart）
- **TypeChecker 阶段 Lowering**：运算符到 Trait 方法的映射、`for` 循环、`or else`/`and then`、集合字面量、隐式成员表达式
- **不做 Lowering**：`if`/`while`/`when` 保持原始结构，直接在 CodeGen 中处理

自举建议：
- 运算符 Lowering 是最关键的，因为它决定了 Trait 系统的使用方式
- `for` 循环的 Lowering 依赖 Iterator trait，需要标准库配合
- 集合字面量的 Lowering 需要知道目标类型（List/Set/Map），依赖类型推断结果

---

## 6. 单态化泛型实现策略

### 6.1 当前实现分析

当前编译器采用完全单态化（Full Monomorphization）策略，类似 Rust 和 C++ 模板：

**工作流程：**
1. TypeChecker 在遇到泛型使用时，收集 InstantiationRequest
2. Monomorphizer 处理所有请求，为每个 `(模板, 类型参数)` 组合生成具体代码
3. 传递性实例化：如果实例化过程中发现新的泛型使用，加入工作队列
4. 递归检测：防止无限实例化（如 `[T]List` 包含 `[[T]List]List`）

**实例化请求类型：**

```koral
type InstantiationKind {
    // 泛型结构体实例化: [Int]List → List_Int
    StructType(template GenericStructTemplate, args [Type]List),
    // 泛型联合类型实例化: [Int]Option → Option_Int
    UnionType(template GenericUnionTemplate, args [Type]List),
    // 泛型函数实例化: [Int]identity → identity_Int
    FunctionInst(template GenericFunctionTemplate, args [Type]List),
    // 泛型扩展方法实例化
    ExtensionMethod(template_name String, base_type Type, template GenericExtensionMethodTemplate, type_args [Type]List, method_type_args [Type]List),
    // Trait 占位方法实例化
    TraitMethod(base_type Type, method_name String, method_type_args [Type]List),
}
```

**去重策略：**
- 使用 InstantiationKey 进行去重，基于模板名 + 类型参数
- 已处理的请求记录在 `processedRequestKeys: Set<InstantiationKey>` 中
- 类型缓存 `instantiatedTypes` 和函数缓存 `instantiatedFunctions` 避免重复生成

### 6.2 布局名生成

单态化后的类型需要唯一的布局名（Layout Name），用于 C 代码中的结构体名：

```
模板名_参数1布局键_参数2布局键_...

例如：
  [Int]List      → List_Int
  [String]Option → Option_String
  [Int, String]Map → Map_Int_String
```

布局键（Layout Key）是类型的规范化字符串表示，确保相同类型参数组合产生相同的布局名。

### 6.3 声明时类型检查 + 实例化时替换

当前编译器对泛型函数和扩展方法采用"声明时检查 + 实例化时替换"的策略：

1. 声明时：使用 `genericParameter` 类型检查函数体，生成 `checkedBody`
2. 实例化时：将 `checkedBody` 中的 `genericParameter` 替换为具体类型
3. 替换后可能需要重新解析某些表达式（如方法调用的分派）

这种策略的优势是避免了对同一函数体的重复类型检查，只需做类型替换。

### 6.4 自举中的单态化实现建议

```koral
// Monomorphizer 的核心循环
type Monomorphizer(
    mut pending_requests [InstantiationRequest]List,
    mut processed_keys [InstantiationKey]Set,
    mut instantiated_types [String, Type]Map,
    mut instantiated_functions [String, (String, Type)]Map,
    mut generated_nodes [TypedGlobalNode]List,
    input TypeCheckerOutput,
)

// 伪代码：主循环
// given Monomorphizer {
//     monomorphize(self ref) MonomorphizedProgram = {
//         // 1. 将初始请求加入队列
//         for req in self.input.instantiation_requests then
//             self.pending_requests.push(req)
//
//         // 2. 工作队列循环
//         while self.pending_requests.is_not_empty() then {
//             let req = self.pending_requests.pop_front()
//             let key = req.deduplication_key()
//             if self.processed_keys.contains(key) then continue
//             self.processed_keys.insert(key)
//
//             when req.kind in {
//                 .StructType(template, args) then self.instantiate_struct(template, args),
//                 .UnionType(template, args) then self.instantiate_union(template, args),
//                 .FunctionInst(template, args) then self.instantiate_function(template, args),
//                 .ExtensionMethod(...) then self.instantiate_extension_method(...),
//                 .TraitMethod(...) then self.instantiate_trait_method(...),
//             }
//         }
//
//         // 3. 构建输出
//         yield MonomorphizedProgram(...)
//     }
// }
```

### 6.5 未来扩展：非单态化泛型

完全单态化会导致代码膨胀。未来可以考虑混合策略：

**字典传递（Dictionary Passing）：**
- 对于只通过 Trait 约束使用的泛型参数，传递 vtable 字典而非生成具体代码
- 类似 Haskell 的类型类字典或 Swift 的 witness table

**类型擦除（Type Erasure）：**
- 对于大小已知的类型参数，使用 `void*` + 大小信息
- 需要运行时的类型信息支持

**选择性单态化：**
- 对热路径使用单态化（零开销）
- 对冷路径使用字典传递（减少代码大小）
- 可以通过 profile-guided optimization 指导决策

自举阶段建议先实现完全单态化，这是最简单且性能最好的方案。

---

## 7. 代码生成策略

### 7.1 C 后端架构

当前编译器生成 C 代码，这是自举的理想选择——C 是最广泛支持的编译目标，且 Koral 的内存模型（ARC + 逃逸分析）可以自然地映射到 C。

**C 代码结构：**

```c
// 1. 头文件包含
#include <stdint.h>
#include <stdbool.h>
#include "koral_runtime.h"

// 2. 前向声明（所有 struct）
struct Point;
struct List_Int;

// 3. 类型定义（按依赖顺序排列）
struct Point {
    intptr_t x;
    intptr_t y;
};

// 4. 每个类型的 copy/drop 函数
struct Point __koral_Point_copy(const struct Point *self) { ... }
void __koral_Point_drop(struct __koral_Ref self_ref) { ... }

// 5. Union 类型（tagged union）
struct Option_Int {
    intptr_t tag;
    union {
        struct { intptr_t value; } Some;
    } data;
};

// 6. Vtable 结构体和实例
struct __koral_vtable_Drawable { ... };
static const struct __koral_vtable_Drawable __koral_vtable_Drawable_for_Circle = { ... };

// 7. 函数定义
intptr_t add(intptr_t x, intptr_t y) { return x + y; }

// 8. main 函数
int main(int argc, char** argv) { ... }
```

### 7.2 类型映射

| Koral 类型 | C 类型 |
|-----------|--------|
| `Int` | `intptr_t` |
| `UInt` | `uintptr_t` |
| `Int8` ~ `Int64` | `int8_t` ~ `int64_t` |
| `UInt8` ~ `UInt64` | `uint8_t` ~ `uint64_t` |
| `Float32` | `float` |
| `Float64` | `double` |
| `Bool` | `bool` |
| `Void` | `void` |
| `Never` | `void` (noreturn) |
| `T ref` | `struct __koral_Ref` |
| `T ptr` | `T*` |
| `T weakref` | `struct __koral_WeakRef` |
| `struct Type` | `struct TypeName` |
| `union Type` | `struct TypeName` (tagged union) |
| `Trait ref` | `struct __koral_Ref` (vtable 在 ref 内部) |
| `[P1, P2, R]Func` | 函数指针或闭包结构体 |

### 7.3 引用计数实现

```c
// 运行时的引用计数结构
struct __koral_Ref {
    void* ptr;           // 指向数据
    intptr_t* ref_count; // 引用计数
    void (*drop)(struct __koral_Ref); // 析构函数指针
    void* vtable;        // vtable 指针（trait 对象使用）
};

// 引用计数操作
void __koral_retain(struct __koral_Ref ref);   // ref_count++
void __koral_release(struct __koral_Ref ref);  // ref_count--，到 0 时调用 drop 并释放
```

### 7.4 逃逸分析与分配策略

逃逸分析决定值是分配在栈上还是堆上：

**逃逸判定规则：**
- `noEscape`：值不逃逸当前作用域 → 栈分配（C 局部变量）
- `escapeToReturn`：值作为返回值逃逸 → 堆分配（box）
- `escapeToField`：值被存储到结构体字段 → 堆分配
- `escapeToParameter`：值被传递给可能存储它的函数 → 堆分配
- `unknown`：无法确定 → 保守堆分配

**两阶段分析：**
1. 预分析阶段：扫描函数体，识别所有可能逃逸的变量
2. 代码生成阶段：根据预分析结果决定分配策略

```c
// 不逃逸 → 栈分配
struct Point local_point;
local_point.x = 1;
local_point.y = 2;

// 逃逸 → 堆分配
struct __koral_Ref heap_point = __koral_alloc(sizeof(struct Point), __koral_Point_drop);
((struct Point*)heap_point.ptr)->x = 3;
((struct Point*)heap_point.ptr)->y = 4;
```

自举建议：
- 初始版本可以采用保守策略：所有 `ref` 类型都堆分配
- 逃逸分析可以逐步完善，先支持简单的局部变量分析
- `-m` 标志用于输出逃逸分析诊断，帮助调试

### 7.5 Vtable 生成

Trait 对象的动态分派通过 vtable 实现：

```c
// Trait 声明 → vtable 结构体
struct __koral_vtable_Drawable {
    // 每个 requirement 方法一个函数指针
    struct __koral_String (*draw)(struct __koral_Ref self);
};

// 具体类型的 vtable 实例
// Circle 实现 Drawable 的 wrapper 函数
static struct __koral_String __koral_Drawable_draw_wrapper_Circle(struct __koral_Ref self) {
    struct Circle* concrete = (struct Circle*)self.ptr;
    return Circle_draw(*concrete);
}

// vtable 实例（静态常量）
static const struct __koral_vtable_Drawable __koral_vtable_Drawable_for_Circle = {
    .draw = __koral_Drawable_draw_wrapper_Circle,
};

// 动态分派调用
struct __koral_Ref shape = /* ... */;
struct __koral_vtable_Drawable* vt = (struct __koral_vtable_Drawable*)shape.vtable;
vt->draw(shape);
```

### 7.6 Lambda / 闭包生成

Lambda 表达式生成环境结构体 + 函数：

```c
// Lambda: (x Int) -> x + captured_base
// 生成环境结构体
struct __koral_lambda_env_0 {
    intptr_t captured_base;  // 捕获的变量
};

// 生成 Lambda 函数
intptr_t __koral_lambda_0(struct __koral_lambda_env_0* __captured, intptr_t x) {
    return x + __captured->captured_base;
}
```

捕获规则：
- 不可变值类型：按值捕获（复制到环境结构体）
- 引用类型：按引用捕获（增加引用计数）
- 可变变量：不允许捕获（编译错误）

### 7.7 字符串常量生成策略

字符串常量的生成对编译器性能至关重要。编译器自身是字符串密集型应用，错误消息、标识符、C 代码片段中包含大量字符串字面量。

**当前实现分析：**

当前编译器对每个字符串字面量生成一对 `static const` 变量——一个字节数组和一个 StringStorage 结构体，然后构造一个 String 值，其 `ref` 的 `control` 指针为 `NULL`（表示静态分配，不参与引用计数）：

```c
// "hello" 的生成结果
static const uint8_t __t42_bytes[] = { 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x00 };
static const struct StringStorage __t42_storage = { (uint8_t*)__t42_bytes, 5, 6 };
struct String __t43 = (struct String){ (struct __koral_Ref){ (void*)&__t42_storage, NULL } };
```

关键设计点：
- `control == NULL` 表示静态生命周期，`__koral_release` 遇到 NULL control 时跳过释放
- 字节数组和 storage 都是 `static const`，存储在只读数据段，零运行时开销
- 每次使用字符串字面量都生成独立的 static 变量，即使内容相同

**自举建议——字符串去重：**

当前实现中相同内容的字符串字面量会生成重复的 static 变量。对于编译器这种字符串密集型程序，应当实现字符串常量池（String Interning）：

```c
// 去重前：两处 "error" 生成两份
static const uint8_t __t10_bytes[] = { 0x65, 0x72, 0x72, 0x6F, 0x72, 0x00 };
static const struct StringStorage __t10_storage = { ... };
static const uint8_t __t99_bytes[] = { 0x65, 0x72, 0x72, 0x6F, 0x72, 0x00 };
static const struct StringStorage __t99_storage = { ... };

// 去重后：共享同一份
static const uint8_t __koral_str_0_bytes[] = { 0x65, 0x72, 0x72, 0x6F, 0x72, 0x00 };
static const struct StringStorage __koral_str_0_storage = { ... };
// 所有 "error" 字面量引用 __koral_str_0_storage
```

实现方式：在 CodeGen 中维护一个 `[String, String]Map`（字面量内容 → 生成的 C storage 变量名），首次遇到时生成 static 变量并记录，后续遇到相同内容时直接复用。

**模式匹配中的字符串常量：**

`when` 表达式中的字符串模式也需要生成 static 常量用于比较。当前实现为每个模式分支独立生成字节数组和 storage，然后调用 `String.equals` 进行比较。字符串去重池应当同时覆盖字面量表达式和模式匹配中的字符串常量。

### 7.8 C 标识符生成

Koral 的限定名需要转换为合法的 C 标识符：

```
模块路径_函数名
例如：
  std.io.println → std_io_println
  my_mod.Point   → my_mod_Point

泛型实例化：
  [Int]List      → List_Int
  [String, Int]Map → Map_String_Int

Trait 实现方法：
  given Point Eq { equals } → Point_trait_Eq_equals

Vtable：
  __koral_vtable_Drawable_for_Circle
```

自举建议：
- C 标识符生成需要处理名称冲突（不同模块的同名类型）
- DefId 可以作为最终的去重手段（`T_<defid>`）
- 保留 `__koral_` 前缀用于运行时和编译器生成的符号

---

## 8. 模块系统

### 8.1 模块解析流程

模块解析是编译的第一步，负责将文件系统结构映射为模块层次：

```
my_project/
├── main.koral           # 根模块入口
├── utils.koral          # using Self.Utils... → 合并到根模块
├── models/
│   ├── models.koral     # models 子模块入口
│   ├── user.koral       # using Self.User... → 合并到 Models
│   └── post.koral       # using Self.Post... → 合并到 Models
└── services/
    ├── services.koral   # services 子模块入口
    └── auth.koral       # using Self.Auth... → 合并到 Services
```

**模块入口文件规则：**
- 目录模块的入口文件必须与目录同名：`models/models.koral`
- 入口文件名必须以小写字母开头，只包含小写字母、数字和下划线
- 如果同时存在 `foo.koral` 和 `foo/foo.koral`，报歧义错误

**导入类型：**
- `using Self.Utils...`：模块合并（将 Utils 的内容合并到当前模块作用域）
- `using Self.Models`：子模块导入（通过 `Models.User` 访问）
- `using Self.Models.User`：成员导入（直接使用 `User`）
- `using Self.Models.*`：批量导入（所有公开符号直接可用）
- `using Super.Sibling`：父模块导入
- `using Std.Io as Io`：别名导入
- 在 std 子模块中，根模块 `Std` 的 `public` 符号默认可见，无需重复导入

### 8.2 导入图（ImportGraph）

ImportGraph 记录模块间的导入关系，用于可见性检查：

```koral
type ImportGraph(
    // 模块级导入边
    mut edges [(source [String]List, target [String]List, kind ImportKind)]List,
    // 符号级导入
    mut symbol_imports [(module [String]List, target [String]List, symbol String, kind ImportKind)]List,
    // 模块别名
    mut module_aliases [(module [String]List, alias String, target [String]List)]List,
)

type ImportKind {
    Local(),           // 当前模块定义
    MemberImport(),    // using module.Symbol
    BatchImport(),     // using module.*
    ModuleImport(),    // using module（需要前缀访问）
}
```

### 8.3 可见性规则

| 修饰符 | 可见范围 |
|--------|---------|
| `public` | 所有模块 |
| `protected`（默认） | 当前模块及子模块 |
| `private` | 仅当前文件 |

**孤儿规则：**
- `given Type Trait { ... }` 要求 Type 或 Trait 至少有一个定义在当前根模块子树中
- `given Trait { ... }`（工具方法）只允许在 Trait 的根模块子树中定义
- `given Type { ... }`（扩展方法）只允许在 Type 的根模块子树中定义

### 8.4 标准库加载

标准库通过 `KORAL_HOME` 环境变量或相对路径定位：

1. Driver 首先加载 `std/std.koral` 作为标准库编译单元
2. 将标准库的所有模块注入用户编译单元的导入图（batch import）
3. 合并两个编译单元的导入图
4. 标准库的 `koral_runtime.c` 在链接阶段一起编译

自举建议：
- 模块解析器应当是独立的、可测试的组件
- 导入图的构建应在语法分析之前完成
- 标准库的预加载机制需要特殊处理（`--no-std` 选项）

---

## 9. 诊断系统

### 9.1 错误分类

当前编译器的错误分为以下几类：

- **LexerError**：词法错误（非法字符、未闭合字符串等）
- **ParserError**：语法错误（意外的 token、缺少分隔符等）
- **SemanticError**：语义错误（类型不匹配、未定义变量、Trait 不满足等）
- **ModuleError**：模块错误（文件未找到、循环依赖、歧义模块等）
- **AccessError**：访问控制错误（访问 private/protected 成员）

### 9.2 源码位置追踪

每个错误都携带 SourceSpan 信息：

```koral
type SourceLocation(line Int, column Int)

type SourceSpan(
    start SourceLocation,
    end SourceLocation,
    file String,
)
```

SourceManager 负责加载源文件内容，用于在错误消息中显示代码片段：

```
main.koral:5:10: error: Type mismatch: expected Int, got String
    let x Int = "hello"
              ^~~~~~~
```

### 9.3 DiagnosticCollector

对于可以继续编译的非致命错误，使用 DiagnosticCollector 收集所有诊断信息，在编译结束后统一报告。

自举建议：
- 错误消息的质量直接影响开发体验，应当投入足够精力
- SourceSpan 应当贯穿整个编译流水线
- 考虑支持 "did you mean?" 建议（编辑距离算法）

---

## 10. 编译选项

### 10.1 基础命令

```
koralc [command] <file.koral> [options]

命令:
  build     编译为可执行文件（默认）
  run       编译并运行
  emit-c    仅生成 C 代码

选项:
  -o, --output <dir>    输出目录（默认为输入文件所在目录）
  --no-std              不加载标准库
  -m, -m=<N>            输出逃逸分析诊断信息
```

### 10.2 自举阶段建议增加的选项

```
  --emit-ast            输出 AST（调试用）
  --emit-typed-ast      输出类型化 AST（调试用）
  --emit-mono           输出单态化后的程序（调试用）
  --dump-defid-map      输出 DefId 映射表（调试用）
  --verbose             详细编译日志
  --time-passes         输出各编译阶段耗时
```

这些调试选项对于自举过程中的问题排查至关重要。

---

## 11. 自举实现路线图

### 11.1 阶段划分

**Phase 0：基础设施**
- 实现 DefId / DefIdMap
- 实现 SourceSpan / SourceLocation
- 实现基础的诊断系统
- 确保标准库的 String、List、Map、Set 可用

**Phase 1：前端**
- 实现 Lexer（Token 枚举 + 状态机）
- 实现 Parser（递归下降）
- 实现 AST 节点定义
- 实现模块解析器

**Phase 2：语义分析**
- 实现 Type 枚举和类型工具函数
- 实现 NameCollector（名称收集）
- 实现基础的 TypeChecker（不含泛型）
- 实现 Scope 管理
- 实现 Trait 一致性检查

**Phase 3：泛型与单态化**
- 实现 TypeVariable 和约束系统
- 实现 Union-Find
- 实现 ConstraintSolver
- 实现 GenericTemplateRegistry
- 实现 Monomorphizer

**Phase 4：代码生成**
- 实现 C 代码生成器
- 实现类型到 C 类型的映射
- 实现 ARC 代码插入
- 实现 vtable 生成
- 实现 Lambda/闭包生成

**Phase 5：完善**
- 实现逃逸分析
- 实现穷举性检查
- 完善错误消息
- 实现所有编译选项
- 通过所有现有测试用例

### 11.2 测试策略

- 复用现有的 `compiler/Tests/Cases/` 目录中的所有测试用例
- 自举编译器的输出应与 Swift 版本的输出一致
- 使用差异测试（diff testing）：比较两个编译器生成的 C 代码
- 最终验证：自举编译器能编译自身

### 11.3 风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| Koral 标准库不够完善 | 通过 FFI 补充缺失的功能 |
| 递归类型导致栈溢出 | 使用 `ref` 打断递归，必要时增加栈大小 |
| 编译速度慢 | 初期可接受，后续通过增量编译优化 |
| 错误消息不够清晰 | 逐步完善，参考 Swift 版本的错误消息 |
| 泛型实例化代码膨胀 | 初期可接受，后续考虑混合策略 |

---

## 12. 长期架构改进

当前编译器的架构是一个直接的 TypedAST → C 代码生成流水线，没有中间表示层。这在自举初期是合理的，但对于长期维护和优化存在明显瓶颈。本节先分析现有架构的局限，然后提出改进方案。

### 12.1 引入中间表示层（KIR）

**现有架构的问题：**

当前编译器的逃逸分析直接在 TypedAST 上进行（`EscapeAnalysis.swift` 中的 `preAnalyzeExpression` 递归遍历 TypedExpressionNode），然后在 C 代码生成阶段根据分析结果决定分配策略。这种"分析和生成交织"的设计有以下问题：

1. 逃逸分析的精度受限于 TypedAST 的抽象层次——TypedAST 保留了大量高层语义信息（如 `when` 表达式、`for` 循环），分析器需要理解每种高层构造的语义
2. ARC 操作（retain/release）的插入点散布在 CodeGen 的各个角落，难以验证正确性
3. 无法在 ARC 插入后做进一步优化（如消除冗余的 retain/release 对）
4. 逃逸分析、ARC 插入、finally 清理、模式匹配展开等变换相互耦合

**建议引入 Koral IR（KIR）：**

在 MonomorphizedProgram 和 C 代码生成之间引入一层显式的中间表示：

```
MonomorphizedProgram (TypedAST)
        │
        ▼
┌──────────────────┐
│  KIR Lowering    │  TypedAST → KIR
│                  │  展开高层构造（when/for/finally/or else）
│                  │  显式化控制流（基本块 + 跳转）
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│  逃逸分析        │  在 KIR 上做更精确的数据流分析
│  (Escape)        │  标记每个分配点的逃逸状态
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│  ARC 优化        │  插入 retain/release
│  (ARC Pass)      │  消除冗余的 retain/release 对
│                  │  合并相邻的 release 调用
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│  C 代码发射      │  KIR → C 源码（机械翻译）
│  (C Emitter)     │  
└──────────────────┘
```

**KIR 的设计要点：**

```koral
// KIR 是基于基本块的 SSA-like 表示
type KIRFunction(
    name String,
    params [KIRParam]List,
    return_type KIRType,
    blocks [BasicBlock]List,
    entry_block BlockId,
)

type BasicBlock(
    id BlockId,
    instructions [KIRInst]List,
    terminator Terminator,
)

type KIRInst {
    // 值操作
    Alloca(dest VarId, ty KIRType),              // 栈分配
    HeapAlloc(dest VarId, ty KIRType, dtor FuncId), // 堆分配
    Load(dest VarId, src VarId),
    Store(dest VarId, src VarId),
    FieldGet(dest VarId, base VarId, field String),
    FieldSet(base VarId, field String, value VarId),

    // ARC 操作（显式化）
    Retain(var VarId),
    Release(var VarId),
    WeakRetain(var VarId),
    WeakRelease(var VarId),

    // 函数调用
    Call(dest VarId, func FuncId, args [VarId]List),
    VtableCall(dest VarId, receiver VarId, method String, args [VarId]List),

    // 类型操作
    Construct(dest VarId, ty KIRType, args [VarId]List),
    TagCheck(dest VarId, value VarId, tag Int),
    TagExtract(dest VarId, value VarId, tag Int, field String),
    Cast(dest VarId, value VarId, target_type KIRType),

    // 其他
    Copy(dest VarId, src VarId),
    Drop(var VarId),
    Literal(dest VarId, value KIRLiteral),
}

type Terminator {
    Return(value VarId),
    Branch(target BlockId),
    CondBranch(cond VarId, then_block BlockId, else_block BlockId),
    Switch(value VarId, cases [(Int, BlockId)]List, default BlockId),
    Unreachable(),
}
```

**KIR 带来的收益：**

1. 逃逸分析可以在基本块级别做精确的数据流分析，而非在树形 AST 上做近似分析
2. ARC 操作显式化后，可以做 retain/release 消除优化（如果一个值在 retain 后立即被 release，两者可以消除）
3. `when`/`for`/`finally` 等高层构造在 Lowering 到 KIR 时被展开为基本块和跳转，C 代码发射变成简单的机械翻译
4. 为未来切换到 LLVM IR 后端铺路——KIR 到 LLVM IR 的映射比 TypedAST 到 LLVM IR 简单得多
5. 可以在 KIR 上实现更多优化 pass（常量折叠、死代码消除、内联等）

**自举阶段建议：**

自举初期不需要 KIR，直接从 TypedAST 生成 C 代码（与当前 Swift 实现一致）。但在架构设计上应当预留 KIR 的插入点——将 CodeGen 拆分为"Lowering"和"Emission"两个概念上独立的阶段，即使初期它们在同一个 pass 中完成。

### 12.2 逃逸分析的长期改进

**现有实现的局限：**

当前的逃逸分析是函数内分析（intra-procedural）为主，辅以有限的过程间分析（inter-procedural）。`EscapeContext` 在代码生成时追踪变量的作用域层级和逃逸状态，`GlobalEscapeResult` 提供函数级的参数逃逸摘要。

主要局限：
- 分析在 TypedAST 上进行，需要为每种 AST 节点编写分析逻辑（当前 `preAnalyzeExpression` 有 30+ 个 case 分支）
- 过程间分析依赖函数摘要（`FunctionEscapeSummary`），但摘要的精度有限
- 无法处理条件逃逸（"如果走 then 分支则逃逸，走 else 分支则不逃逸"）
- Trait 方法调用和泛型调用采用保守策略（假设所有 ref 参数逃逸）

**基于 KIR 的改进方案：**

如果引入 KIR，逃逸分析可以改为标准的数据流分析：

1. 构建连接图（Connection Graph）：每个分配点和变量是节点，赋值/传参/返回是边
2. 在基本块级别做前向数据流分析，传播逃逸状态
3. 支持条件逃逸：不同控制流路径可以有不同的逃逸结论，取保守合并
4. 过程间分析：为每个函数生成参数逃逸摘要，调用点使用摘要而非保守假设

**分阶段实施：**
- Phase 1（自举）：保守策略，所有 `ref` 堆分配
- Phase 2：函数内逃逸分析（与当前 Swift 实现等价）
- Phase 3：引入 KIR 后，基于数据流的精确分析
- Phase 4：过程间分析 + 条件逃逸

### 12.3 ARC 优化

当前编译器在 C 代码生成时直接插入 `__koral_retain` / `__koral_release` 调用。这种方式简单但产生大量冗余操作。

**可优化的模式：**

```c
// 模式 1：临时值的 retain + release 可以消除
struct __koral_Ref tmp = some_ref;
__koral_retain(tmp.control);
use(tmp);
__koral_release(tmp.control);
// 如果 some_ref 在此期间不会被释放，retain/release 对可以消除

// 模式 2：连续 release 可以合并
__koral_release(a.control);
__koral_release(b.control);
__koral_release(c.control);
// 如果 a, b, c 的 drop 函数没有副作用交互，可以批量处理

// 模式 3：move 语义消除 retain
// 如果值被 move 而非 copy，不需要 retain
struct __koral_Ref moved = original;
// original 不再使用 → 不需要 retain moved，也不需要 release original
```

**基于 KIR 的 ARC 优化 pass：**

在 KIR 上，ARC 操作是显式的指令（`Retain`/`Release`），可以做标准的编译器优化：
- 活跃性分析：确定每个 `Retain` 是否有对应的 `Release`
- 冗余消除：如果 `Retain` 和 `Release` 之间没有可能释放该引用的操作，消除这对操作
- Move 检测：如果值的最后一次使用是传递给另一个所有者，转换为 move（省略 retain + release）

### 12.4 TypeChecker 的长期重构

**现有架构的问题：**

当前 TypeChecker 是一个大型的 class，通过 Swift extension 分散到多个文件中（TypeCheckerExpressions、TypeCheckerStatements、TypeCheckerGenerics 等）。所有状态（scope、traits、conformances、caches）都是 TypeChecker 的实例变量，这导致：

1. 状态管理复杂，难以理解哪些状态在哪个阶段被修改
2. 难以并行化（所有状态共享）
3. 测试困难（需要构造完整的 TypeChecker 实例）

**改进方向：**

将 TypeChecker 拆分为无状态的函数集合 + 显式的上下文参数：

```koral
// 现有风格（有状态的方法）
// given TypeChecker {
//     check_expression(self ref, expr ExprNode) TypedExpr = {
//         self.current_span = expr.span  // 修改实例状态
//         when expr in { ... }
//     }
// }

// 改进风格（显式上下文）
// let check_expression(expr ExprNode, ctx CheckContext ref) TypedExpr = {
//     ctx.update_span(expr.span)
//     when expr in { ... }
// }
//
// type CheckContext(
//     scope Scope ref,
//     context CompilerContext ref,
//     diagnostics DiagnosticCollector ref,
//     // ... 其他需要的状态
// )
```

这种风格更适合 Koral 的函数式倾向，也更容易测试和并行化。

### 12.5 增量编译

增量编译的核心思想是只重新编译发生变化的部分。为此需要：

**DefId 稳定性：**
- DefId 需要在编译之间保持稳定（相同的定义产生相同的 DefId）
- 可以使用 `(模块路径, 名称, 种类)` 的哈希作为 DefId，而非简单的递增计数器
- 或者维护一个持久化的 DefId 映射文件

**依赖追踪：**
- 记录每个函数/类型依赖的其他定义
- 当某个定义变化时，只重新检查依赖它的定义
- 模块级别的粗粒度依赖追踪是最简单的起点

**缓存策略：**
- 缓存每个模块的 TypeCheckerOutput
- 缓存单态化结果
- 缓存生成的 C 代码片段
- 使用内容哈希判断是否需要重新编译

**架构预留：**
- CompilerContext 的设计已经考虑了并行编译的需求（`@unchecked Sendable`）
- DefIdMap 的集中式设计便于序列化和反序列化
- 模块系统的独立性使得模块级增量编译成为可能

### 12.6 调试信息生成

为了支持源码级调试，编译器需要在生成的 C 代码中嵌入调试信息：

**`#line` 指令：**
最简单的方案是在生成的 C 代码中插入 `#line` 指令，将 C 代码的行号映射回 Koral 源码：

```c
#line 42 "main.koral"
intptr_t x = 10;
#line 43 "main.koral"
intptr_t y = x + 1;
```

这样使用 gdb/lldb 调试时，断点和单步执行会显示 Koral 源码位置。

**DWARF 信息：**
更完善的方案是生成自定义的 DWARF 调试信息，但这需要：
- 理解 DWARF 格式
- 在 C 代码中嵌入类型信息
- 处理单态化后的类型名映射

建议先实现 `#line` 指令方案，后续再考虑完整的 DWARF 支持。

### 12.7 栈展开（Unwind）

当前 Koral 没有异常机制，`finally` 是确定性的作用域清理。但未来可能需要：

**Panic 展开：**
- `panic()` 当前直接终止程序，不保证 `finally` 执行
- 如果要支持 panic 展开，需要：
  - 在每个作用域注册清理函数
  - panic 时沿调用栈逆序执行清理
  - 类似 C++ 的 `__cxa_throw` / `__cxa_catch` 机制

**实现方案：**

方案 A — setjmp/longjmp：
```c
jmp_buf __koral_panic_buf;
if (setjmp(__koral_panic_buf) != 0) {
    __koral_cleanup_scope();
    longjmp(__koral_parent_panic_buf, 1);
}
```

方案 B — 返回值传播（类似 Go）：
```c
int result = some_function();
if (__koral_is_panicking()) {
    __koral_cleanup_scope();
    return ERROR_CODE;
}
```

方案 C — C++ 异常（如果后端切换到 C++）：
```cpp
try {
    some_function();
} catch (__koral_panic& e) {
    __koral_cleanup_scope();
    throw;
}
```

如果引入了 KIR，panic 展开可以在 KIR 层面建模——每个可能 panic 的调用点生成一条到清理基本块的异常边，清理块执行 `finally` 和 `drop`，然后继续传播。这比在 C 代码生成中手动插入 setjmp/longjmp 更加清晰和可维护。

建议自举阶段不实现 panic 展开，保持当前的"panic 即终止"语义。

### 12.8 非单态化泛型

完全单态化的问题：
- 代码膨胀：`[Int]List`、`[String]List`、`[Float64]List` 各生成一份完整代码
- 编译时间：每个实例化都需要完整的代码生成
- 无法支持动态加载的泛型代码

**字典传递方案：**

```c
// 单态化版本
intptr_t max_Int(intptr_t a, intptr_t b) {
    return a > b ? a : b;
}

// 字典传递版本
void* max_generic(void* a, void* b, struct __koral_OrdDict* dict) {
    if (dict->compare(a, b) > 0) return a;
    return b;
}

// Ord 字典
struct __koral_OrdDict {
    int (*compare)(void*, void*);
    // ... 其他 Ord 方法
};
```

**混合策略的判断标准：**
- 函数体较小（内联候选）→ 单态化
- 函数体较大且类型参数只通过 Trait 使用 → 字典传递
- 类型参数用于内存布局（字段类型）→ 必须单态化

如果引入了 KIR，混合策略可以在 KIR 层面实现——单态化和字典传递生成不同的 KIR 指令序列，但共享同一个 C 代码发射器。

这是一个长期优化目标，不影响自举。

### 12.9 长期流水线演进路线

总结各阶段的流水线演进：

**自举阶段（与当前 Swift 实现等价）：**
```
源码 → Lexer → Parser → TypeChecker → Monomorphizer → CodeGen(直接生成C) → clang
```

**中期（引入 KIR）：**
```
源码 → Lexer → Parser → TypeChecker → Monomorphizer → KIR Lowering → 逃逸分析 → ARC 插入 → C Emitter → clang
```

**长期（多后端 + 优化）：**
```
源码 → Lexer → Parser → TypeChecker → Monomorphizer → KIR Lowering → 逃逸分析 → ARC 优化 → 常量折叠 → 死代码消除 → { C Emitter | LLVM IR Emitter } → 后端
```

每个阶段都是向后兼容的——新增的 pass 不影响已有 pass 的接口，只是在流水线中插入新的变换步骤。

---

## 13. 编译器自身的 Koral 代码组织

### 13.1 建议的模块结构

```
koralc/
├── main.koral                    # 入口
├── driver/
│   └── driver.koral              # Driver: 编译流水线协调
├── diagnostics/
│   ├── diagnostics.koral         # 入口
│   ├── error.koral               # 错误类型定义
│   ├── source_manager.koral      # 源码管理
│   └── renderer.koral            # 错误渲染
├── module/
│   ├── module.koral              # 入口
│   ├── resolver.koral            # 模块解析
│   ├── import_graph.koral        # 导入图
│   └── access_checker.koral      # 访问控制
├── parser/
│   ├── parser.koral              # 入口
│   ├── lexer.koral               # 词法分析
│   ├── ast.koral                 # AST 节点定义
│   └── parser_impl.koral         # 语法分析实现
├── sema/
│   ├── sema.koral                # 入口
│   ├── def_id.koral              # DefId 系统
│   ├── types.koral               # 类型定义
│   ├── typed_ast.koral           # TypedAST 节点
│   ├── scope.koral               # 作用域管理
│   ├── name_collector.koral      # 名称收集
│   ├── type_checker.koral        # 类型检查主逻辑
│   ├── constraint.koral          # 约束定义
│   ├── constraint_solver.koral   # 约束求解
│   ├── unifier.koral             # 合一算法
│   ├── union_find.koral          # 并查集
│   ├── trait_checker.koral       # Trait 一致性
│   ├── exhaustiveness.koral      # 穷举性检查
│   └── compiler_context.koral    # 编译器上下文
├── mono/
│   ├── mono.koral                # 入口
│   ├── monomorphizer.koral       # 单态化主逻辑
│   ├── template_registry.koral   # 泛型模板注册表
│   └── instantiation.koral       # 实例化请求
└── codegen/
    ├── codegen.koral             # 入口
    ├── codegen_types.koral       # 类型代码生成
    ├── codegen_expr.koral        # 表达式代码生成
    ├── codegen_stmt.koral        # 语句代码生成
    ├── codegen_memory.koral      # 内存管理代码生成
    ├── codegen_vtable.koral      # Vtable 代码生成
    ├── codegen_lambda.koral      # Lambda 代码生成
    ├── escape_analysis.koral     # 逃逸分析
    └── c_identifier.koral        # C 标识符工具
```

### 13.2 AST 遍历风格：`when` 而非访问者模式

自举编译器不应使用访问者模式（Visitor Pattern）。Koral 拥有强大的模式匹配和穷举性检查，`when` 表达式是遍历 AST 的最佳手段。访问者模式在 Java/C++ 中弥补的是缺乏 ADT 模式匹配的缺陷，在 Koral 中引入它只会增加不必要的间接层和 Trait 对象开销。

设计原则：
- 所有 AST/TypedAST 遍历一律使用 `when` 表达式
- 利用穷举性检查确保新增 AST 节点时所有遍历点都被更新
- 每个编译阶段（TypeChecker、Monomorphizer、CodeGen）直接对 union 类型做模式匹配
- 如果需要在多处共享遍历逻辑，提取为接受 union 值的普通函数，而非 Trait

```koral
// 推荐：直接用 when 遍历
let generate_expression(expr TypedExpr, ctx CodeGenContext ref) String = {
    when expr in {
        .IntegerLiteral(value, _) then value.to_string(),
        .StringLiteral(value, type) then generate_string_literal(value, type, ctx),
        .BinaryOp(left, op, right, _) then {
            let l = generate_expression(deref left, ctx)
            let r = generate_expression(deref right, ctx)
            yield l + " " + op.to_c() + " " + r
        },
        .Call(callee, args, _) then generate_call(deref callee, args, ctx),
        // ... 穷举所有 case，编译器会检查遗漏
    }
}

// 不推荐：访问者模式
// trait [T Any]ExprVisitor { visit_int(self, ...) T; visit_call(self, ...) T; ... }
// 这在 Koral 中是反模式——增加间接层，丢失穷举性保证
```

对于需要多后端支持的场景（如未来同时支持 C 和 LLVM IR 后端），使用 Trait 封装后端接口是合理的，但 Trait 方法内部仍然应该用 `when` 遍历 AST：

```koral
// 后端接口 Trait（合理使用）
trait CodeBackend {
    emit_module(self ref, program MonomorphizedProgram) String
}

// C 后端实现内部仍然用 when
// given CBackend CodeBackend {
//     emit_module(self ref, program MonomorphizedProgram) String = {
//         for node in program.global_nodes then
//             when node in { ... }  // 直接模式匹配
//     }
// }
```

---

## 14. 关键实现注意事项

### 14.1 递归数据结构

AST 和 Type 都是递归数据结构。在 Koral 中，递归 union 类型需要通过 `ref` 打断递归：

```koral
// 直接递归 — 编译器需要 ref 来确定大小
type ExprNode {
    IntLiteral(value Int),
    BinaryOp(op BinOp, left ExprNode ref, right ExprNode ref),
    IfExpr(cond ExprNode ref, then_branch ExprNode ref, else_branch ExprNode ref),
    Block(stmts [ExprNode]List),
    // ...
}
```

### 14.2 字符串处理性能

编译器是字符串密集型应用。需要注意：
- Lexer 应当避免大量的字符串复制，考虑使用切片/视图
- 符号表的键查找应当高效（哈希表）
- C 代码生成使用 StringBuilder 模式，避免频繁的字符串拼接

### 14.3 错误恢复

Parser 应当具备基本的错误恢复能力：
- 遇到语法错误时，跳过到下一个同步点（如 `}`、`;`、`let`）
- 尽可能多地报告错误，而非在第一个错误处停止
- TypeChecker 也应当能在类型错误后继续检查

### 14.4 内存使用

编译器处理大型项目时需要注意内存使用：
- AST 节点数量可能很大，考虑使用 arena 分配器（如果标准库支持）
- DefIdMap 的各个映射表会随项目规模线性增长
- 单态化可能导致类型和函数数量爆炸，需要有效的去重

---

## 附录 A：当前 Swift 编译器的关键文件对照

| 功能 | Swift 文件 | 自举对应模块 |
|------|-----------|-------------|
| 入口 | `koralc/main.swift` | `main.koral` |
| 驱动 | `Driver/Driver.swift` | `driver/driver.koral` |
| 词法 | `Parser/Lexer.swift` | `parser/lexer.koral` |
| 语法 | `Parser/Parser.swift` + 扩展 | `parser/parser_impl.koral` |
| AST | `Parser/AST.swift` | `parser/ast.koral` |
| DefId | `Sema/DefId.swift` | `sema/def_id.koral` |
| 类型 | `Sema/Type.swift` | `sema/types.koral` |
| TypedAST | `Sema/TypedAST.swift` | `sema/typed_ast.koral` |
| 上下文 | `Sema/CompilerContext.swift` | `sema/compiler_context.koral` |
| 作用域 | `Sema/Scope.swift` | `sema/scope.koral` |
| 名称收集 | `Sema/NameCollector.swift` | `sema/name_collector.koral` |
| 类型检查 | `Sema/TypeChecker.swift` + 扩展 | `sema/type_checker.koral` |
| 约束 | `Sema/Constraint.swift` | `sema/constraint.koral` |
| 求解器 | `Sema/ConstraintSolver.swift` | `sema/constraint_solver.koral` |
| 合一 | `Sema/Unifier.swift` | `sema/unifier.koral` |
| 并查集 | `Sema/UnionFind.swift` | `sema/union_find.koral` |
| 穷举 | `Sema/ExhaustivenessChecker.swift` | `sema/exhaustiveness.koral` |
| 单态化 | `Monomorphization/Monomorphizer.swift` + 扩展 | `mono/monomorphizer.koral` |
| 模板注册 | `Monomorphization/GenericTemplateRegistry.swift` | `mono/template_registry.koral` |
| 代码生成 | `CodeGen/CodeGen.swift` + 扩展 | `codegen/codegen.koral` |
| 逃逸分析 | `CodeGen/EscapeAnalysis.swift` | `codegen/escape_analysis.koral` |
| 模块解析 | `Module/ModuleResolver.swift` | `module/resolver.koral` |
| 导入图 | `Module/ImportGraph.swift` | `module/import_graph.koral` |
| 诊断 | `Diagnostics/*.swift` | `diagnostics/*.koral` |

---

## 附录 B：自举验证清单

- [ ] Lexer 能正确词法分析所有 Token 类型（包括字符串插值、范围运算符等）
- [ ] Parser 能解析所有语法结构（包括泛型前缀语法 `[T]List`）
- [ ] 模块系统能正确解析所有导入类型
- [ ] DefId 系统能为所有定义分配唯一标识
- [ ] 类型检查能处理所有基本类型和复合类型
- [ ] 类型推断能正确推断变量类型和泛型参数
- [ ] Trait 一致性检查能验证所有 given 声明
- [ ] 穷举性检查能检测不完整的模式匹配
- [ ] 单态化能正确实例化所有泛型使用
- [ ] C 代码生成能产生正确的 C 代码
- [ ] ARC 代码能正确管理引用计数
- [ ] Vtable 能正确实现动态分派
- [ ] Lambda/闭包能正确捕获变量
- [ ] 逃逸分析能正确判断栈/堆分配
- [ ] 所有 296 个现有测试用例通过
- [ ] 自举编译器能编译自身（Stage 2 验证）

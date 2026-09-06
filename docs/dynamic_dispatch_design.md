# Koral 动态派发语义完善设计

状态：草案，供审阅

日期：2026-09-05

范围：

- 完善 trait requirement、conformance、witness、vtable、trait object、type pattern downcast 的统一语义
- 给出对现有文档、Swift host 编译器、自举编译器、测试的实施修改建议

非目标：

- 本文档不追求稳定 ABI
- 本文档不要求兼容历史 vtable 布局或现有运行时内部表示
- 本文档不在第一阶段引入完整运行时反射系统；只要求动态派发和 exact downcast 语义闭合

## 1. 背景与目标

当前 Koral 已经具备以下能力：

- trait requirement 与 `given Type as Trait` 的显式实现
- trait object 的动态派发
- 泛型 trait 与父 trait
- `if ... is ...`、`while ... is ...`、`when ... in { ... }` 的模式匹配

但这些能力还没有形成一个完整、统一、可扩展的语义闭环。当前主要缺口有：

1. 泛型父 trait 的实例参数没有完整贯穿 requirement 展开、方法身份、witness 与 vtable。
2. 缺失完整 witness 时，后段仍可能继续生成 vtable。
3. vtable fallback 依赖弱方法身份，如方法名或近似名字匹配，而不是 requirement 身份。
4. 部分 trait conformance / trait bound 比较会忽略 trait arguments，只比较 trait base name。
5. trait object 还不能通过 Koral 自身模式系统完成 exact downcast。
6. downcast 的类型模式还不能自然绑定变量，导致匹配成功后难以继续使用具体实现类型。

本文的目标是将这些点合并为一套单一设计：

- 上游先形成完整、实例化后的 conformance witness。
- 中游只传播 witness 所定义的 requirement 槽位和方法身份。
- 下游从 witness 派生 vtable 与 trait object。
- 模式匹配直接复用该动态类型信息完成 exact downcast。

## 2. 总体设计结论

### 2.1 采用 witness-first，而不是 name-first

动态派发的核心语义应改为：

1. 先解析 `given` 为一个完整的 conformance witness。
2. witness 必须已经包含：
   - 具体的 `Self` 类型
   - 目标 trait 及其具体 trait arguments
   - 所有父 trait 的实例化结果
   - requirement 的稳定身份与有序槽位
   - 每个 requirement 对应的唯一实现方法
3. vtable、trait object conversion、trait method call 全部从 witness 出发，而不是再通过字符串、逻辑名或零散 fallback 重新猜实现。

这意味着 “是否可以动态派发” 的判定上移到语义阶段，而不是等到 MIR/codegen 再兜底。

### 2.2 downcast 先做 exact concrete-ref type pattern

本阶段不做开放式运行时反射，也不引入完整稳定 ABI。trait object downcast 只需要支持：

- 对实现类型的精确匹配
- 对指针层数和可变性的精确检查
- 匹配成功后把具体引用类型绑定给变量

这已经足够覆盖：

```koral
if err is *IoError then {}

if err is io *IoError then {
    io.detail()
}

when err in {
    io *IoError then io.detail(),
    _ then "unknown",
}
```

## 3. 术语与核心数据模型

### 3.1 CanonicalTraitRef

引入规范化 trait 引用：

- `traitName`
- `traitArgs`

语义上，`Error`、`Iterator[Int]`、`Parent[List[String]]` 都是不同的 `CanonicalTraitRef`。

规则：

- 所有 conformance 比较都基于 `CanonicalTraitRef`。
- 所有父 trait 展开都必须得到新的 `CanonicalTraitRef`。
- 不能把只看 `baseName` 的比较继续留在语义主路径中。

### 3.2 RequirementSlot

引入 requirement 槽位身份，至少包含：

- `declaringTraitRef` 或 declaring trait declaration identity
- `methodName`
- requirement 原始签名
- 经过 `Self + trait arguments + ancestor substitution` 代换后的实例化签名
- 稳定顺序 index

要求：

- vtable 排序以 RequirementSlot 顺序为准。
- 动态派发按 RequirementSlot 查槽位。
- fallback 不得再靠 “同名即可” 或 “名字后缀接近即可” 判定实现身份。

### 3.3 ConformanceWitness

引入一等语义对象 `ConformanceWitness`，至少包含：

- `selfType`
- `traitRef`
- `originGiven`
- `parentWitnesses`
- `orderedRequirementSlots`
- `implementationsBySlot`

要求：

- 所有 requirement 必须被完整满足后，witness 才是有效的。
- 无有效 witness 时，禁止生成 trait object conversion、trait method call、vtable。
- generic trait 的 witness 不是裸 trait declaration，而是 trait declaration 在具体 trait args 下的实例。

## 4. 语法决策

### 4.1 结论

本方案推荐的绑定语法为：

```koral
if a is err *IoError then {}

when a in {
    err *IoError then {},
    _ then {},
}
```

而不是：

- `err as *IoError`
- `err: *IoError`

### 4.2 为什么不采用 `err as *IoError`

`as` 在 Koral 当前语义中已经承载了三类非常明确的角色：

- `given Type as Trait`
- `(value as Trait).method(...)`
- `using ... { Name as Alias }`

这些都更接近 “限定 / 归属 / 转换上下文”，而不是 “模式绑定”。如果把 `err as *IoError` 用作 pattern binding，读者很容易把它误读成一种 cast 或 qualification，而不是 “匹配成功后绑定整个被匹配值”。

技术上它不是做不到，但它会把 `as` 的语义域进一步拉宽，增加解析和文档说明负担。

### 4.3 为什么不采用 `err: *IoError`

`err: *IoError` 的问题在于：

- 冒号更像“标签”或“命名字段”，而不是普通绑定语法的延伸。
- 对顶层 type pattern 绑定来说，额外标点并没有提供决定性的辨识收益，因为右侧 `*` 已经足够明确地表明后面是引用类型模式。
- 若后续把这套写法推广到更多绑定场景，冒号版本会让模式看起来更像结构字段匹配，而不是“把整个匹配值绑定为某种形状”。

### 4.4 为什么采用 `err *IoError`

`err *IoError` 的好处是：

- 它更接近 Koral 自身已有的绑定习惯，例如 `let name Type = expr`，左边先给出绑定名，右边给出类型形状。
- 它不会和 `as` 的既有职责冲突。
- 右侧以 `*` 起头，足以把它与普通变量绑定区分开。
- 它让 trait object downcast 看起来更像“匹配成功后得到一个更具体的绑定”，而不是一个额外的 cast 语法。

本阶段建议只把该语法用于 type pattern binding，而不立即把它扩展到所有 pattern alias 场景。也就是先支持：

```koral
err *IoError
```

暂不在本阶段引入：

```koral
whole Point(x, y)
whole .Some(v)
```

未来如果需要更通用的 alias pattern，需要单独设计更普适的空白绑定规则；本阶段不默认把该形式推广到所有 pattern。

## 5. 类型模式与 downcast 语义

### 5.1 本阶段支持的目标模式

本阶段的运行时类型模式仅用于 trait object 的实现类型断言，目标模式限定为：

- `*ConcreteType`
- `*mutable ConcreteType`

其中 `ConcreteType` 可以是：

- 非 trait 的具体 struct / enum / opaque 类型
- 具体泛型实例，如 `ParseError[Int]`

本阶段不支持作为目标模式的类型：

- trait 本身
- trait object 类型
- `Self`
- 泛型参数
- 裸值类型写法，如 `IoError`
- 多余或错误层数的引用类型，如 `**IoError`

### 5.2 subject 的静态类型要求

类型模式只能匹配静态类型为 trait object 引用的 subject：

- `*Trait`
- `*mutable Trait`

本阶段不要求支持弱 trait object 或其它 ref-like 变体的 downcast。后续如需扩展，再单独设计。

### 5.3 匹配规则

设 subject 的静态类型为 `SubjectTraitRef`，运行时实际 witness 为 `W`，目标模式为 `TargetRefType`。

匹配成功当且仅当：

1. `W.selfType` 与 `TargetRefType` 所指向的具体类型完全一致。
2. 指针层数完全一致。
3. 目标模式不能要求比 subject 更强的可变性。
4. 泛型参数完全一致。

等价地说：

- `*Error` 可以匹配 `*IoError`
- `*Error` 不可以匹配 `IoError`
- `*Error` 不可以匹配 `*mutable IoError`
- `*mutable Error` 可以匹配 `*IoError`
- `*mutable Error` 可以匹配 `*mutable IoError`
- `*Error` 不可以匹配 `**IoError`
- `*Error` 不可以匹配 `*NetError`，除非运行时实现就是 `NetError`
- `*ParserError[Int]` 只匹配 `*ParserError[Int]`，不匹配 `*ParserError[String]`

### 5.4 绑定结果类型

若 `a` 的静态类型为 `*Error`，则：

```koral
if a is err *IoError then {
    // err 的类型是 *IoError
}
```

若 `a` 的静态类型为 `*mutable Error`，则：

```koral
if a is err *mutable IoError then {
    // err 的类型是 *mutable IoError
}
```

绑定结果必须保留指针层，不能自动解成值类型。这是为了维持 Koral 当前规则：trait object 本身不支持直接解引用为实现值，也不通过 pattern 偷偷引入值级复制/移动语义。

### 5.5 `is` / `when` / `while` 中的可见性与绑定

延续当前模式绑定规则：

- `a is *IoError` 可以在任意布尔位置使用，结果为 `Bool`
- `a is err *IoError` 只有在 `if` / `while` 的绑定上下文中才有意义
- `when a in { err *IoError then ... }` 在该 arm 的 body 中绑定 `err`

因此本阶段建议：

- 允许 `if a is err *IoError then ...`
- 允许 `while a is err *IoError then ...`
- 允许 `when a in { err *IoError then ... }`
- 不允许把带绑定的 `is` 模式作为普通布尔表达式的一部分逃逸到无绑定作用域的位置，例如 `let ok = a is err *IoError`

### 5.6 穷尽性与可达性

trait object 的实现类型集合对用户语义来说应视为开放集合，因此：

- `when err in { *IoError then ..., *NetError then ... }` 不应视为穷尽
- 这类 `when` 默认仍需要 `_`

可达性规则：

- 完全相同的实现类型模式若再次出现，则第二个分支不可达
- 仅绑定名不同但目标类型相同，也视为重复
- 不同实现类型模式互不覆盖
- `or` 分支若绑定的名字或类型不一致，应报错

例如：

```koral
when err in {
    a *IoError then 1,
    b *IoError then 2, // 不可达
    _ then 3,
}
```

而：

```koral
when err in {
    a *IoError or a *NetError then 1, // 应报错：a 的绑定类型不一致
    _ then 2,
}
```

## 6. 父 trait 实例化与 requirement 展开规则

### 6.1 父 trait 不是裸 trait name，而是实例化结果

若有：

```koral
trait Parent[T Any] {
    value(*self) T
}

trait Child[T Any] Parent[List[T]] {
    child_only(*self) Int
}
```

则 `Child[Int]` 的父 trait 不是 `Parent`，而是 `Parent[List[Int]]`。

要求：

- parent trait 展开必须先做 trait-arg substitution
- requirement 展开顺序建立在实例化后的 parent chain 上
- 父 trait requirement 的签名中若出现 trait type param，必须使用展开后的具体实参

### 6.2 子 trait witness 必须内含 parent witness

`ConformanceWitness(Child[Int])` 必须显式包含：

- `ConformanceWitness(Parent[List[Int]])`

而不是在 vtable 阶段临时再从 `Child` 名字反推 `Parent`。

### 6.3 不允许冲突的父 trait 实例化

若一个 trait 通过不同路径继承得到同一个基 trait 的两个不同实例，比如：

- `Parent[List[Int]]`
- `Parent[List[String]]`

则应在 trait 定义或 conformance 形成阶段报错，而不是把冲突推迟到 vtable 布局时才暴露。

## 7. witness、conformance 与 vtable 规则

### 7.1 有效 witness 的判定条件

一个 witness 只有在以下条件都满足时才有效：

1. 目标 trait object-safe。
2. 父 trait 实例链完整且无冲突。
3. 每个 requirement 都有唯一实现。
4. 每个实现方法签名在实例化后与 requirement slot 完全匹配。
5. 所有 trait arguments 都已经 concrete 化到允许进入后段的程度。

### 7.2 vtable 只能由有效 witness 生成

规则：

- 不能因为存在 `traitName + concreteType` 组合就直接生成 vtable。
- 必须先有有效 witness。
- 若缺失某个 requirement 的实现，直接在 witness 构建阶段报错，禁止产生部分 vtable。

### 7.3 vtable 槽位身份

每个 vtable 槽位都对应一个 RequirementSlot，而不是一个“看起来像这个方法”的逻辑名。

后果：

- codegen 不需要再扫 given/global method 列表做近似匹配
- method fallback 不再以方法名后缀、同名工具方法、静态表近似结果作为动态派发身份依据
- 动态派发的槽位顺序与 requirement 展开顺序严格一致

### 7.4 trait object conversion

把 `*Concrete` 或 `*mutable Concrete` 擦除为 trait object 时，转换节点中应保存：

- 目标 `CanonicalTraitRef`
- 具体 `ConformanceWitness`
- 具体 `selfType`

本阶段不要求这些必须体现在稳定 ABI 中；只要求编译器内部语义上存在该信息，并可在 codegen 选择任何当前实现方便的内部表示。

## 8. conformance 比较与 trait bound 规则

### 8.1 任何显式 conformance 比较都必须包含 trait arguments

以下概念都不得只比较 trait base name：

- `hasNominalConformance`
- generic trait bound 查询
- `findTraitConstraint`
- parent trait satisfied 检查
- trait tool / extension method 通过 trait 约束做查找时的选择
- vtable request dedup key
- dynamic dispatch receiver trait identity

### 8.2 约束匹配要基于 `CanonicalTraitRef`

例如：

- `[T Iterator[Int]]` 不等同于 `[T Iterator[String]]`
- `given Box[String] as Parse[Utf8]` 不满足 `Parse[Utf16]`

### 8.3 generic parameter bound 查询要返回完整 constraint

不应再只问：

- “参数 T 是否有 trait `Iterator` bound？”

而应问：

- “参数 T 是否满足 `Iterator[Int]`？”

如果只需要判断 base trait 继承链，也必须保留 trait args 再比较，而不是把参数擦除掉。

## 9. 对文档的修改建议

### 9.1 `docs/grammar.bnf`

需要新增或调整：

- type pattern 的语法
- type pattern binding 的语法
- `is` 带绑定模式的上下文限制说明
- trait object type pattern 的非穷尽说明

建议新增的语义草案：

```bnf
<pattern> ::= <primary-pattern>
           | <comparison-pattern>

<match-pattern> ::= <or-pattern>

<primary-pattern> ::= ...
                    | <trait-object-type-pattern>
                    | <trait-object-type-binding-pattern>

<trait-object-type-binding-pattern> ::= <identifier> <trait-object-type-pattern>

<trait-object-type-pattern> ::= "*" <concrete-type-pattern>
                              | "*" "mutable" <concrete-type-pattern>

<concrete-type-pattern> ::= <type-identifier>
                          | <type-identifier> "[" <type-list> "]"
```

并补充语义注释：

- 仅在 trait object subject 上合法
- 仅匹配具体实现类型
- 不自动解引用
- 不构成穷尽匹配
- 在 pattern 上下文中，若标识符后直接跟一个以 `*` 开始的类型模式，则按绑定型 type pattern 解析

### 9.2 `docs/document.md`

需要补充：

- trait object 章节中的 dynamic type / downcast 规则
- `if is` 与 `when` 的类型模式示例
- 指针层数、可变性、泛型参数的 exact match 规则
- 绑定形式 `err *IoError`
- 开放世界下 `when` 仍需 `_`

### 9.3 `docs/document-zh.md`

与英文文档同步更新同样内容。

### 9.4 `docs/grammar_preview.koral`

需要补充示例：

```koral
if err is *IoError then {}

if err is io *IoError then {
    println(io.message())
}

when err in {
    io *IoError then println(io.message()),
    _ then println("other"),
}
```

### 9.5 `docs/developer-guide.md`

建议新增一小节，说明以下防漂移规则：

- trait args 不得在 conformance / witness / vtable 上被忽略
- 动态派发必须由完整 witness 驱动
- type pattern downcast 不得把 trait object 偷偷降格为值语义

## 10. 对 Swift host 编译器源码的修改建议

### 10.1 Parser / AST

建议修改文件：

- `compiler/Sources/KoralCompiler/Parser/AST.swift`
- `compiler/Sources/KoralCompiler/Parser/ParserPatterns.swift`
- `compiler/Sources/KoralCompiler/Parser/ParserExpressions.swift`

建议修改内容：

- 为 `PatternNode` 新增 trait-object type pattern 节点
- 为 `PatternNode` 新增 type pattern binding 节点
- 解析 `err *IoError`
- 保持现有命名 pattern arg 与新顶层绑定 pattern 的语法边界清晰

### 10.2 Typed AST / pattern typing

建议修改文件：

- `compiler/Sources/KoralCompiler/Sema/TypedAST.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerPatterns.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerExpressions.swift`

建议修改内容：

- 为 `TypedPattern` 新增 exact implementation type pattern 节点
- 为 `TypedPattern` 新增绑定版本或在节点中携带绑定 symbol
- 在 pattern checker 中验证：
  - subject 必须是 trait object ref
  - target 必须是具体引用类型
  - 不能请求更强可变性
  - 不能省略引用层
- 在 `if` / `while` / `when` 中把绑定作用域接入现有 pattern binding 规则

### 10.3 Trait / conformance model

建议修改文件：

- `compiler/Sources/KoralCompiler/Sema/TypeChecker.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTraits.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerMethods.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTypeResolution.swift`
- `compiler/Sources/KoralCompiler/Sema/SemaUtils.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/GenericTemplateRegistry.swift`

建议修改内容：

- 引入 `CanonicalTraitRef`
- 引入显式 `ConformanceWitness`
- 统一 parent trait 实例化展开
- 让 trait bound 查询返回完整 constraint，而不是只看 trait base name
- 清理 base-name-only 的 shortcut

### 10.4 Monomorphization / MIR

建议修改文件：

- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerTypes.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerFunctions.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerExpressionSubstitution.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerTypeResolution.swift`
- `compiler/Sources/KoralCompiler/MIR/MIR.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRVerifier.swift`

建议修改内容：

- `VtableRequest` 从 “类型 + trait 名字 + args” 升级为 “要求某个 witness 的动态派发表现”
- MIR vtable method 列表建立在实例化后的 RequirementSlot 上
- MIR verifier 检查：
  - vtable 对应完整 witness
  - 槽位数与 requirement 数一致
  - downcast pattern 只针对合法 trait object subject

### 10.5 CodeGen

建议修改文件：

- `compiler/Sources/KoralCompiler/CodeGen/CodeGenVtable.swift`
- `compiler/Sources/KoralCompiler/CodeGen/CodeGenMIR.swift`

建议修改内容：

- 去除基于弱名字身份的动态派发 fallback
- 直接从 witness / requirement slot 解析实现方法符号
- 支持 type pattern downcast 的运行时判定

本阶段由于 ABI 不稳定，可以允许 codegen 采用任何当前实现方便的内部表示，只要语义满足本文规则。

## 11. 对 bootstrap 编译器源码的修改建议

### 11.1 AST / Parser / Typed AST

建议修改文件：

- `bootstrap/koralc/ast/nodes.koral`
- `bootstrap/koralc/ast/printer.koral`
- `bootstrap/koralc/parser/core.koral`
- `bootstrap/koralc/parser/core_expressions.koral`
- `bootstrap/koralc/typed/typed_ast.koral`
- `bootstrap/koralc/typed/typed_printer.koral`

建议修改内容：

- 新增 trait-object type pattern 节点
- 新增绑定型 type pattern 节点
- 打印与调试输出同步支持新 pattern

### 11.2 Sema / conformance / pattern checking

建议修改文件：

- `bootstrap/koralc/sema/trait_checker.koral`
- `bootstrap/koralc/sema/type_checker.koral`
- `bootstrap/koralc/sema/type_checker_decls.koral`
- `bootstrap/koralc/sema/type_checker_methods.koral`
- `bootstrap/koralc/sema/type_checker_visibility.koral`
- `bootstrap/koralc/sema/type_checker_expressions_dispatch.koral`
- `bootstrap/koralc/sema/type_checker_expressions_control_flow.koral`
- `bootstrap/koralc/sema/type_checker_substitution.koral`

建议修改内容：

- 引入与 host 同步的 `CanonicalTraitRef` / witness 观念
- parent trait 实例参数完整贯穿
- trait args 查询、conformance key、bound 匹配统一改为比较完整 trait ref
- pattern checker 支持 exact implementation type pattern 与绑定

### 11.3 Mono / MIR / CodeGen

建议修改文件：

- `bootstrap/koralc/mono/generic_template_registry.koral`
- `bootstrap/koralc/mono/mono.koral`
- `bootstrap/koralc/mono/mono_functions.koral`
- `bootstrap/koralc/mono/mono_expr_substitution.koral`
- `bootstrap/koralc/mono/mono_type_resolution.koral`
- `bootstrap/koralc/mir/mir.koral`
- `bootstrap/koralc/mir/mir_function_builder.koral`
- `bootstrap/koralc/mir/mir_lowerer.koral`
- `bootstrap/koralc/codegen/codegen_vtable.koral`
- `bootstrap/koralc/codegen/codegen_mir.koral`

建议修改内容：

- 让 vtable request 与 trait method call 依赖完整 witness 信息
- 让 parent trait requirement 的实例化结果进入 MIR method slot
- 去除后段按名字猜实现的路径
- 增加 trait-object type pattern downcast lowering

## 12. 测试修改建议

建议新增测试类别：

### 12.1 父 trait 参数贯穿

- child trait 继承 generic parent，并验证 parent requirement 的签名在 dynamic dispatch 中已使用具体实参
- 多层父 trait 链中 `Self` 与 trait args 混合代换

### 12.2 缺失 witness 拒绝生成 vtable

- given 缺 requirement
- 签名不匹配
- parent witness 冲突
- object-safe 失败

### 12.3 弱方法身份回归

- 同名工具方法与 requirement 方法并存
- 父 trait 与子 trait 有同名 requirement
- 仅名字相近但签名不同的方法不得被错误选中

### 12.4 trait args 参与 conformance 比较

- `Iterator[Int]` 与 `Iterator[String]`
- `Parse[Utf8]` 与 `Parse[Utf16]`
- generic bound 查找必须区分 trait args

### 12.5 downcast type pattern

- `if a is *IoError`
- `if a is err *IoError`
- `when a in { err *IoError then ..., _ then ... }`
- `*Error` 不能匹配 `IoError`
- `*Error` 不能匹配 `*mutable IoError`
- `*mutable Error` 可以匹配 `*IoError`
- `*mutable Error` 可以匹配 `*mutable IoError`
- 泛型实例 exact match

### 12.6 开放世界与穷尽性

- trait object type pattern 的 `when` 没有 `_` 时应拒绝
- 重复实现类型 pattern 不可达
- `or` 中绑定名一致但类型不同应报错

## 13. 分阶段实施计划

### 阶段 1：统一 trait identity 与 conformance 比较

目标：

- 所有显式 conformance / bound / parent trait 查询都纳入 `CanonicalTraitRef`

完成标准：

- 不再存在 base-name-only 的语义主路径
- host 与 bootstrap 在 trait args 比较上行为一致

### 阶段 2：引入完整 witness，并收紧 vtable 生成前置条件

目标：

- vtable 只能从完整 witness 生成
- 父 trait 参数实例化链完整贯穿到 requirement slot

完成标准：

- 缺失 requirement 时不再生成部分 vtable
- 动态派发槽位与 requirement 展开顺序一致

### 阶段 3：加入 trait object exact downcast type pattern

目标：

- 支持 `*Concrete` 与 `name *Concrete` 的 pattern
- 支持 `if` / `while` / `when` 中的绑定与使用

完成标准：

- host 与 bootstrap 都通过同一批语义测试
- type pattern 不破坏现有模式绑定和控制流 lowering

### 阶段 4：清理旧 fallback 与补全文档

目标：

- 删除不再需要的弱身份 fallback
- 同步更新所有文档与示例

完成标准：

- `docs/grammar.bnf`、`docs/document.md`、`docs/document-zh.md`、`docs/grammar_preview.koral` 一致
- 开发文档明确记录新的防漂移原则

## 14. 审阅重点

本轮建议优先拍板以下四点：

1. 是否接受 `err *IoError` 作为第一阶段唯一推荐绑定语法。
2. 是否接受 “type pattern 只做 exact concrete-ref match，不自动解引用” 这一规则。
3. 是否接受 “trait object type pattern 不构成穷尽匹配，默认仍需 `_`” 这一规则。
4. 是否接受 “vtable 只能由完整 witness 生成，禁止部分 vtable” 作为硬约束。

若以上四点通过，后续实现基本就是工程展开，而不是再回到根语义层面重开设计。
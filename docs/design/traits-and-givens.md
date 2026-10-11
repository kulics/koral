# trait / `given` / trait object

> **Status**：Implemented
> **范围**：trait 身份、conformance 与 witness、`given` 的分工、trait object、`Any` 的两个位
> **用法**见 [`../guide/document.md`](../guide/document.md)「Traits and `given` Blocks / Trait
> Objects / Extension Methods / Object Safety」；**本文只记为什么**。
> **共同前提**（身份是声明的 `DefId`）见 [`README.md`](README.md)。

## 摘要

trait 的身份是**声明**，含类型实参，永远不是名字。conformance 与 witness 都按身份记录。
`given` 是「把能力接到已有类型上」的机制，与 trait 声明分开。
`Any` 在两个位置上是两件不同的东西：约束位是**无约束**，trait 位是**普通 trait 名**。

## 背景

trait 系统要回答「这个类型有没有这个能力」。回答的方式有两种：

- 按名字比（写法一样就算有）
- 按声明比（同一个声明才算有）

按名字比会在别名、限定路径、跨模块同名这三种情况下错判。所以全系统按声明比。

## 非目标

- **泛型实例化的键**（`owner_args` 等）→ [`generics-and-monomorphization.md`](generics-and-monomorphization.md)。
- **trait / `given` 的语法** → [`../guide/document.md`](../guide/document.md)。
- **weak 引用的运行时表示** → [`thin-pointer-design.md`](thin-pointer-design.md)。

## 方案

### trait 身份含类型实参

出处：`../implementation/developer-guide.md`「Language Rules That Commonly Drift」（已迁出）。

- Generic trait identity includes trait arguments. Do not compare only the base trait name on conformance, witness, vtable, or generic-bound paths.

`Add[Int]` 与 `Add[String]` 是**两个**约束。只比基名会让它们互相当作对方的实现。

### 缓存键故意不含拼写

出处：`compiler/koralc/sema/type_checker.koral` 的 `CanonicalTraitRef.cache_key`。

```koral
/// Keyed on the trait's DECLARATION identity and its type arguments and
/// nothing else. The spelling is deliberately absent: `trait_name` is for
/// diagnostics and C-mangling only, and folding it in would split one
/// declaration into several keys whenever two call sites spell it
/// differently (a source spelling vs. `def_id_spelling`, an import alias,
/// a qualified path) -- so a witness recorded under one spelling would not
/// be found under another. Identity is the DefId (rustc: `Res::Def(..,
/// DefId)`; `trait_name` is the equivalent of a `Symbol` kept for printing).
```

**键里多一个名字，永远只能「把一个声明拆成几个键」。** 同一个 trait 有三种写法（源码拼写、
import 别名、限定路径），拼写进键就等于 witness 记在一个写法下、换个写法就找不到。

### vtable 的身份、去重键与 C 名都按声明

vtable 的身份是 **(具体类型, trait 声明, trait 类型实参)**，三处必须一致：

| 处 | 键 |
|---|---|
| MIR 的 vtable 身份 / 查找 | `MIRTraitVTable.matches`（koralc）· `MIRTraitVTableKey`（Swift） |
| codegen 的请求去重、结构体去重、实例去重 | 同一身份 |
| MIR 校验器的 inventory | 同一身份 |
| 发出的 C 符号 | `<trait 拼写>_d<DefId>[_<类型实参>]_for_<具体类型 C 名>` |

**C 符号必须能区分两个同名 trait。** 只用拼写时，两个模块各声明一个 `Tag`、
又各有同名的具体类型 `Box`，会同时撞三处：去重表只留一条请求、inventory 报假的
`duplicate vtable key`、C 里 `__koral_vtable_Tag_for_Box` 被声明两次。
`_d<DefId>` 是类型名已经用的同一套消歧（`List_I_d58`）。

回归用例：`tests/compiler-cases/trait_same_name_cross_module_same_type_test/`。

**方法序号也要按声明查。** vtable 里的 `methodIndex` 来自 trait 的方法序
（父 trait 在前）。按拼写查会取到另一个同名 trait 的序号。Swift 的
`inferTraitObjectMethodCall` 曾用 `visibleTraitInfo(traitName)?.defId` 从**名字**
反查 trait，两个 `Tag` 时拿到错的那个，MIR 校验器随即报
`trait method call receiver type does not match call trait metadata`；
现在从接收者的 trait-object 类型取 `DefId`。

与共同前提一致：名字只在解析边界、显示、C 改编三处合法。

**同一批点已一并改掉**（2026-10-10）：Swift 里另有 8 处
`.traitMethodPlaceholder(traitDefId: visibleTraitInfo(traitName)?.defId ?? .invalid, ...)`，
都在**泛型参数接收者**上——`[T Tag]` 约束里的 `Tag` 是拼写，placeholder 记的
`traitDefId` 回头按名字查。现在全部改从**约束 / 匹配到的 bound** 取：

| 处 | 身份来源 |
|---|---|
| 限定调用、`inferMethodOnType` | `resolveBound(traitConstraint).defId` |
| `inferGenericMethodCallExpression` | `GenericMethodResolutionResult.traitDefId`（新增字段） |
| 重建 placeholder | 沿用传入 placeholder 自己的 `traitDefId` |
| `buildEqualsCall` / `buildCompareCall` / 算术 | 匹配到的 bound；无 bound 才落 std 的 lang item |
| `buildTraitMethodCall` | `matchedTraitRef.traitDefId`（顺带把 `traits[name]` 换成 `traitDeclsByDefId`） |

回归用例：`tests/compiler-cases/trait_same_name_bound_same_type_test/`——两个模块各声明
`trait Tag`，同一文件里都当泛型约束用，具体类型也都叫 `Box`。7/40/47。

### 导入别名必须也能命名 trait

`using "m" { Tag as AlphaTag }` 里的 `AlphaTag` 要能当**约束**和**trait object 类型**用。
改前它只绑成普通类型（甚至根本没绑：`extractSymbolInfo` 没有 `.traitDeclaration`
分支，trait 从不进 `publicTypes`），`traits["AlphaTag"]` 查不到。

两边都补上了，而且**别名只进名字表、不进类型表**：给 trait 再加一条类型绑定，会让
`Result[T].Error(...)` 里的 `Error` 解析到一个合成的 trait object，`String` 传不进去
（76 个用例当场红）。别名注册进 trait 注册表与 mono 的名字表两处——只注册前者，
泛型约束在单态化阶段仍按名字查 `generic_templates.traits`，实例化不触发，报
`function operand has unresolved generic type`。

**没改名的 `using` 也是绑定**，键是 **(导入方模块, 本地拼写)**。见
[`name-resolution.md`](name-resolution.md)「trait 的 `using` 也是绑定」——写裸键、用环境里的
当前模块路径、或只处理 `as` 重命名的边，都会让 `using "m" { Tag }` 这条最常见写法失效：
bound 里的 `Tag` 掉到最后的裸名层，报「Import it explicitly」，而文件里明明导入了它。
两个模块各有一个 `trait Tag` 时，它还会解析成另一个模块的那一个。

### 单态化按声明比，不按拼写

`Bound` 的 `def_id` 在**注册进模板注册表时**解析一次，绑定发生在写这个 bound 的模块里。
此后单态化阶段问「这个类型实参满不满足这个约束」，比的是两个 `DefId`
（`trait_identity_matches`），不是两个字符串。

改前 `type_satisfies_bound_constraint` 丢掉 `Bound` 自带的 `def_id`、取 `bound_base_name`
发给 `trait_name_matches`，后者把**两边的拼写**各自查一次未限定索引再比结果。两个同名
trait 时两个拼写落在同一个声明上，判定对任意一对都为真——是过宽匹配，不是解析失败。

同一条线上的 `select_trait_tool_template_cached`、`lookup_given_trait_decls_fuzzy`、
`infer_trait_args_from_extension_template_binding`、`instantiate_trait_target_static_method`
一并改掉：缓存键也必须带声明（`d<id>`），否则两个同名 trait 共用一个槽。
`MethodOwner.Decl(trait_def_id)` 直接用，不再 `trait_owner_by_name` 反查。

**输入端**同理：`instantiate_trait_target_static_method` 收 `Option[DefId]` 而不是
`Option[String]`。原先两个调用点写着 `def_id_spelling(trait_def_id)` 把身份先拆成拼写再传下去，
下游又拼回 DefId——正是 §24.3 记为「0」的那一类往返。

### sema 的满足性链也是身份对身份

`Bound` 的 `def_id` 在注册时解析一次；`satisfies_bound` 往下走
`satisfies_trait_requirement_with_args` → `trait_conformance_key` → … 一整条链都吃
`trait_def_id`。原先这条链拆掉 `Bound` 自带的 `def_id`、取拼写在**当前模块**重新解析——
在另一个模块的上下文里，两个同名 trait 就换人了。

名字只留在两个位置：

- **书写处的解析边界**：`lang_trait_def_id("Eq")`（运算符的 lang item 拼写）、
  `given X as Tag` 的 `trait_def_id_of(trait_name)`。语法不带声明，这里必须读一次名字。
- **打消息**：`trait_missing_conformance_message` 一类。诊断要拼写，判定不要。

`ExplicitTraitConformanceKey` 的 `equals` / `hash` 本来就只比
`(target_type, trait_def_id, trait_arg_types)`——名字在字段里但不参与身份。这正是它该有的形状。

**trait object 的 trait 不必在作用域里。** `make_alpha().value()` 里 `value` 属于
`alpha.Tag`，而 root 从未 `using` 过 `Tag`。所以 `trait_name_from_type` 是 display-only，
身份要走 `trait_def_id_from_type`：拼写在使用方模块查不到，而且就算查得到，那也是
「正在检查的模块」而非「写下期望的模块」。

### lang item 按声明身份记一次

出处：`compiler/koralc/sema/compiler_context.koral`。

```koral
// Every std type the compiler gives built-in behaviour to (`Option` /
// `Result` for `and then`, `String` / `List` / `Deque` / `Dict` for
// subscripting and collection literals, `Range` for `..`, `Pair` for
// destructuring) is recorded here ONCE, by declaration identity, when the
// std module is registered. Later questions compare the identity, so a user
// type with the same spelling is a different type and never inherits the
// built-in behaviour.
```

`Drop` 同理：`set_std_drop_trait_def_id` 在**首次识别时**解析一次声明身份，
之后所有「这是不是 Drop 协议？」都比这个身份——**用户自定义的 `trait Drop` 不得被当成 std 的**
（记录 §16.3、§22.4）。身份铸造点只有一个（`is_std_drop_trait("Drop")`），下游全比 DefId。

### `Any` 是两个东西

出处：`compiler/koralc/ast/nodes.koral` 的 `Bound`、`compiler/koralc/sema/type_checker.koral`。

**约束位**（`given [T Any] One { ... }`）：`Any` 是**无约束**，不是「一种约束」。

```koral
/// Recognise a bound from its source spelling. `Any` produces no bound at all
/// -- it is the absence of a bound, not a bound.
```

`Bound` 只有两种：`Trait(def_id, name, args)` 与 `Mutable()`。`Any` 与「不是 bound 的形状」
一并返回 `None`——它们以前会退化成 `"?"` 哨兵，每个消费方都要特判。

**trait 位**（`trait Any { ... }` 或把它当 trait 名引用）：`Any` 是**普通 trait 名**，没有特权：

```koral
// `Any` gets no free pass here: it is an ordinary trait name and, like
// any other, is an error when nothing declares it.
```

### trait object 不设 marker

出处：`../implementation/developer-guide.md`「Language Rules That Commonly Drift」（已迁出）。

- Trait-object exact type patterns use the concrete type name directly and operate on the erased trait-object subject; they do not auto-deref to the concrete value type.
- Trait-object exact type patterns are open-world checks. In `when`, they do not make a match exhaustive; keep a default `_` arm.
- Trait objects are direct trait-name types; no `Object` marker trait is required.

「能不能变成 trait object」由 **object safety** 把关，不由一个空 marker 把关。
精确类型模式是**开放世界**检查——它不能让 `when` 变穷尽。

### weak 是约束不是 marker

- Weak capability is expressed with the `mutable` type-parameter constraint plus `?T`, not via a `Weak` marker trait.

（同一段原文，已迁出。）weak 是「这个类型必须是 `type mutable`」的**形状要求**，
所以它写在类型参数约束里，而不是一个空 trait。

### `given` 与 trait 声明分开

`trait` 声明能力；`given X { ... }` 把方法接到已有类型上；`given X as Trait { ... }` 声明遵循。
分开的理由：能力的**定义**与能力的**授予**是两件事——一个类型可以被第三方授予能力，
不必改它的声明。出处：记录 §6 的语法备忘（用法见手册）。

## 替代方案

**替代方案原文未记载。** 可反推但无取舍记录：

- **按名字（拼写）比 trait**——注释说明了危害（witness 找不到），但没记录为何曾是候选。
- **`Object` marker trait**——只说「不需要」，没记录谁提过、为何否掉。
- **`Weak` marker trait**——同上，只有一行结论。
- **`Any` 作为一种约束**——曾经是（退化成 `"?"` 哨兵），已否掉；理由记在 `Bound` 的注释里
  （每个消费方都要特判），但没记录当初为何那么设计。

## 风险与未决

- **object safety 的完整判据**：`../guide/document.md` 的「Object Safety」是**规则清单**，
  不是取舍记录——哪些规则是硬性的、哪些是实现权衡，未记。
- **`given` 与 trait 分开的完整论证**：只从语法形状反推，无正面论证。
- **`Eq`/`Ord`/`Hash` 用值接收者**：[`std-api-design.md`](std-api-design.md) 的「Trait Design Guidance」
  一节登记为遗留例外（那节随 Receiver Design 一起从 `developer-guide` 迁出），只说 historical
  reasons，具体历史未记。

## 实施

无单独的实现记录文件。trait 身份从名字键改成 DefId 键的**迁移过程**记在
[`../implementation/identity-matching-tracking.md`](../implementation/identity-matching-tracking.md)
§4–§5、§16.3、§22.4（带日期的记录，只追加不改写）。

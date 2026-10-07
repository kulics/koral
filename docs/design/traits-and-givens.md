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

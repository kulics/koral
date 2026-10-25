# 控制流

> **Status**：Implemented
> **范围**：控制流的求值形态与跳转语句的绑定规则
> **用法**见 [`../guide/document.md`](../guide/document.md)「2. Control Flow」；**本文只记为什么**。
> **语法**见 [`../guide/grammar.bnf`](../guide/grammar.bnf)。

## 摘要

`if` / `when` / `while` / `for` **都用表达式形态的表层语法**。其中 `if` / `when` 可以产生值，
`while` / `for` 总是产生 `Void`。`break` / `continue` 绑定到**最内层循环**，分支不改变绑定目标；
函数与 lambda 边界会拦截它们。

> **本文整体材料不足。** 下面只记已有的结论与一条有测试看护的回归教训，
> **不补写取舍论证**（见文末）。

## 背景

控制流要定两件事：这些结构是不是表达式（能不能产生值），以及跳转语句绑到哪里。

## 非目标

- **各语句的语法与示例** → [`../guide/document.md`](../guide/document.md) §2、
  [`../guide/grammar.bnf`](../guide/grammar.bnf)。
- **一般表达式的求值顺序** → 不在本文。**流程算子的求值与短路**在本文
  「流程算子的求值顺序：短路」。

## 方案

### 四个结构都是表达式形态

出处：[`../guide/document.md`](../guide/document.md) 概述、[`../guide/grammar.bnf`](../guide/grammar.bnf)。

`if`, `when`, `while`, and `for` all use expression-form surface syntax. `if` and `when` may produce
values; `while` and `for` always produce `Void`.

文法里两处注记：

- Single-branch `if`/`when`/`while`/`for` semantically produce Void.
- `while` / `for` evaluate to `Void` unless they terminate early with `Never` control flow.

> **设计动机**（项目目标：生成友好 / 审阅友好，2026-10 补记）：四个结构的分支/循环体
> 共用**同一个形状**（`... then ...`；`when` 的外层是 `when x in { pat then … }`，
> `then` 属于每个 arm），生成器只有一条控制流模板要学，审阅者只认一种形状；
> 差异只留在「能不能产生值」这一维（`if`/`when` 产分支值，`while`/`for` 产 `Void`），
> 而不是四种各自不同的语法。这是动机记录，不是取舍论证——论证原文未记载（见文末）。

### `break` / `continue` 的绑定

出处：[`../guide/document.md`](../guide/document.md) §2，看护用例
`tests/compiler-cases/break_across_branch_test.koral`。

**`break` 绑定到最内层的循环。分支不会拦截它。** `if`、`when` 的分支体、`or else` 的默认值、
`and then` 的变换体，以及作为表达式使用的 `if`，都只是位于 `break` 与它的循环之间，不改变绑定目标。

**函数或 lambda 边界会拦截这两个语句**——闭包里的 `break` 或 `continue` 没有可绑定的循环，是错误。

> ⚠️ **不要把「break 不能穿透分支边界」当成语言规则。** 那是 bootstrap 编译器的一次**回归**：
> 未完成的 "branch break target" 脚手架（无测试、无可用实现）曾错误拒绝 `or else` / `and then` /
> `if` 表达式体内的 `break`，却接受 `when` 分支体与 `if` 语句里一模一样的 `break`。
> `break_across_branch_test.koral` 就是为看护它而加的。语言规则是**分支不拦截**。

### 流程算子的求值顺序：短路

`and then` / `or else` / `or return` 是**短路**的，左到右求值：

| 写法 | 求值 |
|---|---|
| `a and then b` | 先 `a`。是 `Some`/`Ok` 才求 `b`（`it` 为解包值）；否则直接传播，`b` 不求值 |
| `a or else b` | 先 `a`。是 `None`/`Error` 才求 `b`；否则用 `a` 的值，`b` 不求值 |
| `a or return` | 先 `a`。是 `None`/`Error` 就从所在函数返回，后面的都不求值 |

副作用因此只发生在被选中的那一侧。这与主流语言的值兜底算子一致
（`??` / `?:` 一律短路），对照见
[`flow-logical-layers.md`](flow-logical-layers.md)「其它语言怎么做的」。

实现上 `and then` 脱糖成对左操作数的 `when`：只有命中的分支体执行，变换体因此天然
不在空值路径上求值。`or return` 是 `or else as e in { return .Error(e); }` /
`or else { return .None(); }` 的语法糖（脱糖用编译器内部的绑定名）。

> **设计动机**（项目目标：生成友好 / 审阅友好，2026-10 补记）：错误与缺席的流动**写在
> 表达式里**——语言没有 `throw` / `try` / `catch`（文法里不存在这些词），传播点 `or return`
> 与兜底点 `or else` 都在源码里可见。审阅者不必扫调用图才能知道一个错误会走到哪里；
> 生成器也只需在这几个词法点上做决定。副作用只发生在被选中一侧，进一步缩小了要盯的面。

### `defer` 的位置

`defer` 在当前作用域结束时执行清理，顺序与登记相反。用法见
[`../guide/document.md`](../guide/document.md) §2「Cleanup with `defer`」。

## 替代方案

**替代方案原文未记载。** 尤其没有记录：

- 为何是表达式化而不是语句式
- 为何 `while` / `for` 不产生值（集合推导？`collect`？）——**未记**
- 为何 `break` 不穿透函数边界（这在多数语言里是常识，但 Koral 未记论证）

## 风险与未决

- **求值顺序与副作用次序**：已记，见上「流程算子的求值顺序：短路」。
  **分组**是另一件事，见 [`flow-logical-layers.md`](flow-logical-layers.md)。
- **`Never` 与控制流**：`while` / `for` 在 `Never` 提前终止时的求值形态只在文法注记里提了一句，
  无设计说明。

## 实施

无单独实现记录。`break` / `continue` 的绑定规则由回归用例看住——它一度把
`or else` / `and then` 误判成分支边界。流程层 / 逻辑层分层的实施记在
[`flow-logical-layers.md`](flow-logical-layers.md) 的「实现与看护」一节。

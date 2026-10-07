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
- **求值顺序、副作用次序** → 原文未记载，不在本文。

## 方案

### 四个结构都是表达式形态

出处：[`../guide/document.md`](../guide/document.md) 概述、[`../guide/grammar.bnf`](../guide/grammar.bnf)。

`if`, `when`, `while`, and `for` all use expression-form surface syntax. `if` and `when` may produce
values; `while` and `for` always produce `Void`.

文法里两处注记：

- Single-branch `if`/`when`/`while`/`for` semantically produce Void.
- `while` / `for` evaluate to `Void` unless they terminate early with `Never` control flow.

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

### `defer` 的位置

`defer` 在当前作用域结束时执行清理，顺序与登记相反。用法见
[`../guide/document.md`](../guide/document.md) §2「Cleanup with `defer`」。

## 替代方案

**替代方案原文未记载。** 尤其没有记录：

- 为何是表达式化而不是语句式
- 为何 `while` / `for` 不产生值（集合推导？`collect`？）——**未记**
- 为何 `break` 不穿透函数边界（这在多数语言里是常识，但 Koral 未记论证）

## 风险与未决

- **求值顺序与副作用次序**：未记。`and then` / `or else` 的短路语义在手册里有写法，
  但「为什么这样定」没有记录。
- **`Never` 与控制流**：`while` / `for` 在 `Never` 提前终止时的求值形态只在文法注记里提了一句，
  无设计说明。

## 实施

无实现记录。上述回归的修复过程记在
[`thin-pointer-design.md`](thin-pointer-design.md) 的「后续修复：bootstrap 的 `break`
分支边界误判（已修）」一节。

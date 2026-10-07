# design/ — 设计文档

某个子系统**为什么这样设计**：决定了什么、放弃了什么、当时的取舍。
读者是想理解或评审一个决策的人。

**设计文档记「决定」，不记「执行过程」。** 怎么落地、落到哪了，写进
[`../implementation/`](../implementation/)。两者通过同名词干 + 状态登记表 + 互相链接配对。

## 共同前提

> **身份是声明的 `DefId`。名字只在三个地方合法：解析边界、显示、C 改编（mangling）。**
> 解析完成后只比身份，不比名字。
> 出处：[`../implementation/identity-matching-tracking.md`](../implementation/identity-matching-tracking.md) §0 / §5.4 / §7.8

这条贯穿本目录所有文档。**各文档只写「它在本主题上意味着什么」，不要复述前提本身。**

## 分工边界（防重复的关键）

一条事实只有一个家。要引用就链过去，**不复制**——复制出来的第二份迟早会漂移。
下面这张表是**主题归属**：某个话题的正本在哪一份，以及它**不该**写什么。
⚠️ 归属 ≠ 已写全——某条理由如果原文没有取舍记录，正本里会明写「材料不足」，
不因为「归属这里」就等于有内容（见上面「材料不足就如实记」）。

| 文档 | 主题归属（这些归它讲） | **不记**（另有家） |
|---|---|---|
| `type-semantics.md` | managed ref 语法整体删除的决策；可变性为何是声明处；`Clone` 为何浅；`Drop` 语义契约；weak 为何是 `mutable`+`?T` | 对象**布局** → `thin-pointer-design.md`；用法 → `guide/document.md` |
| `control-flow.md` | 为何表达式化；`while`/`for` 为何产出 `Void`；`break`/`continue` 绑定到最内层循环、函数边界拦截 | 语法 → `guide/grammar.bnf`、`guide/document.md` §2 |
| `generics-and-monomorphization.md` | 为何单态化；模板身份是声明；实例键为何带 `owner_args`；类型身份为何不得依赖声明顺序 | 泛型写法 → `guide/document.md` |
| `traits-and-givens.md` | trait 身份是 DefId 且含实参；witness 按实例记；`given` 为何独立；`Any` 两个位的区别 | trait 写法 → `guide/document.md` §5 |
| `name-resolution.md` | 符号是 `(module, name)`；解析顺序；裸名不是解析；禁止名字兜底；可见性默认值 | 模块/包设计 → `module-design.md` |
| `std-api-design.md` | `self` 接收者规则；消耗语义；命名契约；登记在案的遗留例外 | std 具体 API → `../api/std/` |
| `module-design.md` | 模块与导入的命名、语法、manifest | 导入写法 → `guide/document.md` |
| `thin-pointer-design.md` | 对象/头布局、借用表示、trait object 布局、niche | 语言可见的内存语义 → `type-semantics.md` |

## 去重铁律

1. **一条事实只有一个家。** 写之前先 `grep` 看有没有别处已经写了。
2. **迁移是「搬」不是「抄」**：源处必须失去该块（留一行指针），目标处必须逐字得到它。
3. **同义多处时删拷贝**，不是三份都留着。留下的那一份是正本，其余改指针。
4. **代码注释里的规则归位后**，注释只加一行指针，**内容不删**——注释解释「这条规则在此处咬合」，
   设计文档解释「这条规则为何存在」，两者不是重复。

## 材料不足就如实记

盘点确认有些裁定**只有结论句、没有取舍记录**（例：为何选 declaration-site mutability 而非
field-level；为何 `Clone` 浅不深；weak 为何不用 marker trait）。这类只记结论，并注明
**「替代方案原文未记载」**。

**不要事后编造取舍**——补写的「替代方案」会伪装成当时的决策依据，比空白更糟。

## 状态登记表

| 设计 | Status | 对应实现记录 | 最近状态变更 |
|---|---|---|---|
| [`module-design.md`](module-design.md) —— 模块与导入 | Implemented（模块与导入部分） | [`../implementation/module-design-implementation.md`](../implementation/module-design-implementation.md) | 2026-10-05 |
| [`thin-pointer-design.md`](thin-pointer-design.md) —— 薄指针对象表示 | Implemented（步骤 1–4b） | 文内 `## 实施` 一节（未单独拆出） | 2026-10 |
| [`type-semantics.md`](type-semantics.md) —— type / type mutable / Clone / Drop | Implemented | 无单独记录（随 std 与两编译器同批） | 2026-10 |
| [`control-flow.md`](control-flow.md) —— 控制流 | Implemented（**材料不足**） | 见 `thin-pointer-design.md` 的 break 回归一节 | 2026-10 |
| [`generics-and-monomorphization.md`](generics-and-monomorphization.md) —— 泛型与单态化 | Implemented | [`../implementation/identity-matching-tracking.md`](../implementation/identity-matching-tracking.md) §4–§5 | 2026-10 |
| [`traits-and-givens.md`](traits-and-givens.md) —— trait / given / trait object | Implemented | 同上 §4–§5、§16.3、§22.4 | 2026-10 |
| [`name-resolution.md`](name-resolution.md) —— 名字解析与身份边界 | Implemented | 同上 §15–§24 | 2026-10 |
| [`std-api-design.md`](std-api-design.md) —— 标准库 API 设计约定 | Implemented | 无单独记录（随 `std/` API 落地） | 2026-10 |

新的设计落地后，把状态从 Draft 改成 Implemented，并在「对应实现记录」一栏补上链接。

## Status 取值

| 值 | 含义 |
|---|---|
| `Draft` | 在讨论，还没定 |
| `Accepted` | 已定，尚未实施 |
| `Implemented` | 已落地（注明范围，若有分期） |
| `Superseded` | 被新设计取代，注明取代者 |

## 每份设计文档的骨架

```
# <标题>
> Status: <Draft|Accepted|Implemented|Superseded> · 日期 · 对应实现（链到 ../implementation/）
## 摘要
## 背景
## 非目标          ← 必须存在
## 方案
## 替代方案        ← 必须存在
## 风险与未决
## 实施
```

其余各节（`## 迁移`、`## 示例`、`## 附录`、`## 现状` …）按内容取舍，有就写，没有不硬凑。

要求：

- **Status 头放在正文最前**，一行说清状态、日期、对应的实现记录。
- **`## 摘要`** 是「一句话说清这个设计是什么」，`module-design.md` 的做法是范例。
- **`## 非目标` 与 `## 替代方案` 必须存在**。当时没考虑过别的方案就写「原文未记载」，
  **不要事后编造**——补写的「替代方案」会伪装成当时的决策依据。
- **改写已有设计成 RFC 体例时，只搬块、不改写句子**：原文每一段必须逐字出现在新结构的某处。
  新增的只有脚手架标题和「原文未记载」占位。用 `/tmp/no_loss.py` 一类的机械比对证明零丢信息
  （本次重组就是这么验的）。
- **重命名章节时，把原标题留在标题里**，例如 `## 背景 —— 原文「1. 概念」`。
  文档自身和实现记录里的 `§N` / `第 N 节` 引用靠它继续可 grep。
- 长篇设计若分期实施，把每期的状态放进 `## 实施`，不要新开一份文档。

## 命名

- 一份设计一个文件，按子系统命名：`<subsystem>-design.md`。
- 它的执行记录叫 `<subsystem>-implementation.md`，放 `../implementation/`，词干保持一致。
- 一旦定名就别改。名字是 grep 锚点和 `git log --follow` 的抓手。

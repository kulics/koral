# guide/ — 面向用户的说明文档

学会 Koral 这门语言要看的材料都在这里。这一类是**手册**，不是设计文档，也不是实现记录。

## 阅读顺序

1. **[`document.md`](document.md)** —— 语言参考手册（英文）。它自己就是按学习路线排的：
   语言基本元素 → 控制流 → 自定义类型 → 模式匹配 → 抽象设计 → 外部互操作。
   中文读者从 [`document-zh.md`](document-zh.md) 开始。
2. **[`grammar.bnf`](grammar.bnf)** —— 规范性文法。涉及语法细节、要判断写法对不对时看它。
3. **[`grammar_preview.koral`](grammar_preview.koral)** —— 语法示例。**非权威**，只是便于对照阅读。

## 三份材料的权威性不一样

| 文件 | 体裁 | 权威性 |
|---|---|---|
| `grammar.bnf` | 规范文法 | **规范性** —— 实现必须符合它 |
| `document.md` / `document-zh.md` | 语言手册 | **解释性** —— 解释语言，不规定语言 |
| `grammar_preview.koral` | 语法示例 | **非权威** —— 可能领先于 parser，不得据此判断对错 |

`grammar_preview.koral` 这条是 [`../implementation/developer-guide.md`](../implementation/developer-guide.md)
的 "Language Rules That Commonly Drift" 明确写的。

**不一致时没有「谁自动获胜」。** `document.md` 开头的规范说明要求三者**收敛**：

> 如果本文档、BNF 与实现出现不一致，请更新实现和/或文档，使三者收敛。

`grammar_preview.koral` 是 `docs/` 里唯一的 `.koral` 文件。它**不在 koralfmt 语料闸门内**
（`corpus_roots()` 只覆盖 `std/` `compiler/` `toolchain/` `samples/`），从未被格式化验证看护。

## 英文 / 中文同步规则

`document.md` 与 `document-zh.md` 是**共同维护的一对**，不是「原文 + 译文」的主从关系：

- 任何结构性改动（章节增删、链接、路径）必须**同一个改动里两份都改**。
- 两份的链接位点是平行的：开头的规范说明（约第 10 行）与结尾的 std API 指引。
  改一处就要改另一处，改完比对两份的路径行。
- 内容上出现分歧时，以 `document.md` 为准，`document-zh.md` 跟进。

## 手册与规范的分工

- 手册里写**怎么用、为什么这样用**。
- 语法形式上的规定写在 `grammar.bnf`；手册只在需要时引用它，不复述文法产生式。
- 手册、BNF 与实现三者不一致时，**改实现和/或改文档使三者收敛**，而不是让读者自行判断。
  这条写在 `document.md` 开头的规范说明里。

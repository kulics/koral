# implementation/ — 实现说明文档

怎么参与实现，以及一次次改造是怎么做的。读者是贡献者，和事后审计历史的人。

这里**两类文档写法完全不同**，混用会出事：

## 一、活的章程

**必须遵守的流程**：构建顺序、信任边界、验证链、PR checklist、"Document first" 规则、
编译器角色分工。随行为变化而**修订**。

| 文件 | 管的是什么 |
|---|---|
| [`developer-guide.md`](developer-guide.md) | 构建 / 测试 / 调试 / 开发流程、编译器角色分工 |
| [`bootstrap-productization.md`](bootstrap-productization.md) | bootstrap 产品化的约束、信任边界、panic 判定方法 |

- 被 `README.md`、`tests/README.md`、`compiler/README.md`、`compiler-reference/README.md`
  引用，是全仓库最常被指的文档。
- **`### Compiler roles` 这节的标题不能改** —— `README.md` 用 `#compiler-roles` 锚点链着它。
  只改内容不改标题；改了标题就得同步改所有锚点链接。
- 判断一份东西该不该写进章程的标准：**读者需要照做**。写「怎么做」，不写「当时做了什么」。

## 二、实现记录 —— 其余四份

这些写**现在的实现是什么样、怎么演进成这样、否决了什么及原因**，不写「当时做了什么、
接下来要改什么」。读者是想理解或评审这个实现的人。

| 文件 | 记的是什么 |
|---|---|
| [`module-design-implementation.md`](module-design-implementation.md) | 模块与导入的实现裁定、CLI 信封规则 |
| [`identity-matching-tracking.md`](identity-matching-tracking.md) | 身份匹配（DefId）模型、演进、硬性约束与被否方案 |
| [`samples-capability.md`](samples-capability.md) | 样本验证的分界判据、语言缺口、被否掉的下沉 |
| [`flow-operator-forms-implementation.md`](flow-operator-forms-implementation.md) | 流程算子形态与折叠的落地、载荷作用域、被否的实现写法 |

写法：

- **写现状，不写流水账。** 只记三件事：现在怎么做、怎么演进到这样、否决了什么及为什么。
  「当时改了哪几处、跑了几个用例、还剩几处没做」是过程，不进文档——git 历史有。
- **每份顶部给一行状态**：当前范围与未决。读者不该通读才知道现状。
- **带 `§N` 的节号是引用锚点**：设计文档与代码注释按 `§N` 指过来。改节号前先 grep。
- **文件名一旦定名就别改**，理由同设计文档：grep 锚点与 `git log --follow`。
- **路径指针要能解析**：文档搬家后，指过去路径字符串要修到能解析。只改路径，不改措辞。

## 为什么章程和记录不分成两个目录

现在只有 2 份章程 + 4 份记录，多一层目录不值当。分界靠本 README 的上述规则和各自的写法。
等记录多到章程被埋住，再收进 `records/` 子目录。

## 写新文档前

1. 读者需要**照做**吗？→ 给 `developer-guide.md` 加一节，别开新文件。
2. 是**某个改造的实现裁定**吗？→ 开 `<topic>-tracking.md` 或 `<topic>.md`，
   写现状 / 演进 / 被否方案，顶部写状态。
   **已经实现的东西不叫 `plan`。** `plan` 是给「还没做」的；一旦落地，文件名和正文都改成
   现在的陈述——名字说 plan、正文写「已修」，读者会以为问题还在。
3. 是**为什么这样设计**吗？→ 去 [`../design/`](../design/)。

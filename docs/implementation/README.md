# implementation/ — 实现说明文档

怎么参与实现，以及一次次改造是怎么做的。读者是贡献者，和事后审计历史的人。

这里**两类文档写法完全不同**，混用会出事：

## 一、活的章程 —— [`developer-guide.md`](developer-guide.md)

**必须遵守的流程**：构建顺序、信任边界、验证链、PR checklist、"Document first" 规则、
编译器角色分工。

- 随行为变化而**修订**。改了工作方式或验证步骤，同批更新它。
- 被 `README.md`、`tests/README.md`、`compiler/README.md`、`compiler-reference/README.md`、
  `.github/workflows/ci.yml` 引用，是全仓库最常被指的一份文档。
- **`### Compiler roles` 这节的标题不能改** —— `README.md` 用 `#compiler-roles` 锚点链着它。
  只改内容不改标题；改了标题就得同步改所有锚点链接。
- 判断一份东西该不该写进它的标准：**读者需要照做**。写「怎么做」，不写「当时做了什么」。

## 二、带日期的记录 —— 其余三份

| 文件 | 记的是什么 |
|---|---|
| [`module-design-implementation.md`](module-design-implementation.md) | 模块设计的落地计划、验收判据、复核 |
| [`identity-matching-tracking.md`](identity-matching-tracking.md) | 身份匹配（DefId）改造的执行记录 |
| [`bootstrap-productization-plan.md`](bootstrap-productization-plan.md) | bootstrap 产品化的计划与各期取证 |

写法：

- **只追加，不重写。** 历史正文是当时的记录，改它就毁了证据。新结论以
  `## 附：<标题>（<日期>）` 的形式追加到文末，或开新的一节。
- **每份顶部给一行状态**：已完成什么 / 还剩什么。读者不该通读 1500 行才知道现状。
- **路径指针是唯一例外**：文档搬家后，记录里指向别的文档的路径字符串要修到能解析。
  只改路径，其余措辞一字不动 —— 坏掉的指针不是历史叙述，是坏掉的指针。
- **文件名一旦定名就别改**，理由同设计文档：grep 锚点与 `git log --follow`。

## 为什么章程和记录不分成两个目录

现在只有 1 份章程 + 3 份记录，多一层目录不值当。分界靠本 README 的上述规则和各自的写法。
等记录多到章程被埋住，再收进 `records/` 子目录。

## 写新文档前

1. 读者需要**照做**吗？→ 给 `developer-guide.md` 加一节，别开新文件。
2. 是**一次改造的执行过程**吗？→ 开 `<topic>-tracking.md` 或 `<topic>-plan.md`，顶部写状态与日期。
3. 是**为什么这样设计**吗？→ 去 [`../design/`](../design/)。

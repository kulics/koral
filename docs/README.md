# docs/ — 文档地图

这份文件是 `docs/` 的**唯一入口**。`docs/` 根目录下只有它一个文件，其余文档按用途分四类。

新写文档前先看下表决定放哪，再看对应目录的 `README.md` 了解该类的写法约定。

## 目录

| 目录 | 收什么 | 读者 | 状态语义 |
|---|---|---|---|
| [`guide/`](guide/) | **学会这门语言**；含规范性文法 | 语言使用者 | 手册随实现走；文法是规范 |
| [`api/`](api/) | **机器生成**的 API 签名页 | 查「这个函数长什么样」 | 永远由工具写，禁止手改 |
| [`design/`](design/) | 某个子系统**为什么这样设计** | 想理解 / 评审决策 | 有 Status：Draft / Accepted / Implemented / Superseded |
| [`implementation/`](implementation/) | **怎么参与实现** + 落地记录 | 贡献者 / 审计历史 | 章程持续维护；记录只追加 |

```
docs/
  README.md                    本文件
  guide/                       面向用户的说明文档
    README.md                  本类边界
    document.md                语言参考（en，解释性）
    document-zh.md             语言参考（zh，解释性）
    grammar.bnf                ★ 规范性文法
    grammar_preview.koral         非权威示例
  api/                         API 文档（生成物）
    README.md                  手写，其余是生成物
    std/                       14 页 std 模块 API
  design/                      设计文档（记「为什么这样设计」）
    README.md                        共同前提 / 分工边界 / 状态登记表
    module-design.md                 模块与导入
    thin-pointer-design.md           薄指针对象表示
    type-semantics.md                type / type mutable / Clone / Drop
    control-flow.md                  控制流
    generics-and-monomorphization.md 泛型与单态化
    traits-and-givens.md             trait / given / trait object
    name-resolution.md               名字解析与身份
    std-api-design.md                标准库 API 设计约定
  implementation/              实现说明文档
    README.md                          章程 vs 记录
    developer-guide.md                    活的章程
    module-design-implementation.md       记录
    identity-matching-tracking.md         记录
    bootstrap-productization-plan.md      记录
```

## 该放哪

| 你要写的东西 | 去处 |
|---|---|
| 语言的用法说明、教程、参考手册 | `guide/` |
| 某个 API 的签名 | 不手写 —— 改 std 源码后跑生成器，见 [`api/README.md`](api/README.md) |
| 某个子系统的设计决策 | `design/`，加 Status 头，登记进 [`design/README.md`](design/README.md) 的状态表 |
| 怎么构建 / 测试 / 贡献 | [`implementation/developer-guide.md`](implementation/developer-guide.md) |
| 一次改造的执行过程与结论 | `implementation/`，**只追加**，见 [`implementation/README.md`](implementation/README.md) |

## 各体裁的权威性

`guide/` 里三份材料不是一回事：

- **`guide/grammar.bnf`** —— 规范性文法。
- **`guide/document.md` / `document-zh.md`** —— 解释性手册，解释语言、不规定语言。
- **`guide/grammar_preview.koral`** —— **非权威**示例。可能领先于 parser，**不得据此判断对错**
  （`implementation/developer-guide.md` 的 "Language Rules That Commonly Drift" 明确如此）。

**它们不一致时怎么办**，`guide/document.md` 开头的规范说明给了规则：

> 如果本文档、BNF 与实现出现不一致，请更新实现和/或文档，使三者收敛。

也就是说：**没有「谁自动获胜」**——收敛是义务，不是优先级。

## 生成物

`api/std/` 下的 14 页由 `toolchain/doc` 从 `std/` 源码生成：

```bash
bin/toolchain-doc-gen/koral_doc --self-test   # 生成器自检
bin/toolchain-doc-gen/koral_doc               # 重新生成
bin/toolchain-doc-gen/koral_doc --check       # 过期闸门：与磁盘上的页逐字节比对
```

生成器会**递归删掉输出目录下所有 `.md`** 再写入，所以 `api/std/` 里只能放生成页。
详见 [`api/README.md`](api/README.md)。

## 相关

- 语言入口：[`guide/document.md`](guide/document.md) · [语言文档（中文）](guide/document-zh.md)
- 贡献者必读：[`implementation/developer-guide.md`](implementation/developer-guide.md)
- 标准库 API：[`api/std/`](api/std/)

# fmt tests

`koralfmt` 的回归测试。**跑一个命令，两件事一起验**：语言面的内联断言，和整个仓库
真实源码的语料闸门。

## 运行

```bash
bin/compiler/koralc build --package-config toolchain/koralfmt/koral.json --target-module koralfmt/test -o bin/koralfmt-test
bin/koralfmt-test/koralfmt__test
```

输出形如：

```
90/90 tests passed
corpus gate: 217 files checked, 0 failed
```

任何一项失败都打印期望与实际，退出码非 0。

## 两处内容

### 1. `test_fmt.koral` — 语言面断言

`t.test(name, input, expected)` 比对格式化结果，`t.test_error_contains` 比对拒绝理由，
`t.test_checked` 走 `format_source_checked`，**同时**断言格式化契约与幂等性
（见 `toolchain/koral-syntax/README.md`）。

覆盖面要跟语言面一起走。`koralfmt` 曾经落后于语言一整个版本——`type mutable`、
`mutable` 约束、具名参数、默认值、`using` 新写法都解析不了，而测试还是绿的：
断言全在它认识的那部分语法上。后来又漏掉修饰符顺序（`foreign public let`）、
trait 方法参数上的 `mutable`、`..` 与 rune 默认值、`(a, b)` 成对模式、
`name Type` 绑定模式、跨行 import 列表——**每一条都是编译器接受、而它拒绝或改写**。
这些现在都有断言盯着；新语法进来时一并加。

### 2. 语料闸门 — 真实源码

`run_corpus_gate` 走 `std/`、`compiler/`、`toolchain/`、`samples/` 下每一个 `.koral`
文件，对每一个调用 `format_source_checked`。一个文件要过，必须：

- **格式化成功** —— 解析器认识它
- **不丢 token** —— 契约成立（除 `;` 与 `,` 外逐 token 相同）
- **到达不动点** —— 再跑一次输出不变

`tests/` 不在扫描范围内：那里有大量**故意写错**的用例。`toolchain/koralfmt/test/cases/`
下的 fixture 同理排除。

这条闸门的价值是它跟着代码走：谁写了新语法、而 formatter 还不认识，当场红，
而不是等到有人手动格式化时才发现。

## `cases/` — 供人看的独立样例

`.koral` 是输入，`.expected` 是格式化结果，`.error` 是拒绝时的错误子串。
**不被任何代码读取**，只是把 `test_fmt.koral` 里同批场景摊开成文件，方便直接看。

> 早前这里写的是「`cases/` 由文件驱动的 runner 跑」——那个 runner 不存在。
> 实际一直是 `test_fmt.koral` 的内联断言在跑，而 `cases/` 里躺着三份过期期望
> （其中一份还在用已从语言模型删除的 `*mutable` 引用语法），谁也照不出它们。
> 现在以 `test_fmt.koral` 为准。

## 加用例

直接往 `test_fmt.koral` 里加断言。语料闸门不需要跟着改——它自动覆盖新文件。

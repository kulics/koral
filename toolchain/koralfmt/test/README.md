# fmt tests

`koralfmt` 的回归测试。

## 两处内容，一处是闸门

- **`toolchain/koralfmt/test_fmt.koral` — 真正的测试套件**，断言全写在文件里
  （`t.test(name, input, expected)` 比对格式化结果，`t.test_error_contains` 比对
  拒绝理由）。这是唯一会判通过/失败的东西。
- **`cases/` — 同批场景的独立输入/期望文件**，供人直接看，不被任何代码读取。
  `.koral` 是输入，`.expected` 是格式化结果，`.error` 是拒绝时的错误子串。

> 早前这里写的是「`cases/` 由文件驱动的 runner 跑」——那个 runner 不存在。
> 实际一直是 `test_fmt.koral` 的内联断言在跑，而 `cases/` 里躺着三份过期期望
> （其中一份还在用已从语言模型删除的 `*mutable` 引用语法），谁也照不出它们。
> 现在以 `test_fmt.koral` 为准，`cases/` 的期望按它的真实输出对齐过。

## 运行

```bash
# 编译（用 release，见 docs/developer-guide.md 的说明）
compiler/.build/release/koralc build toolchain/koralfmt/test_fmt.koral -o /tmp/fmttest

# 跑
/tmp/fmttest/test_fmt
```

失败会打印期望与实际，退出码非 0。

## 加用例

直接往 `test_fmt.koral` 里加断言。**新语法要一并加**——`koralfmt` 曾经落后于语言
一整个版本（`type mutable`、`mutable` 约束、具名参数、默认值、`using` 新写法都解析
不了），而 218 个真实源文件里 89 个它读不懂，测试却还是绿的：50 条断言全在它
认识的那部分语法上。覆盖面要跟语言面一起走。

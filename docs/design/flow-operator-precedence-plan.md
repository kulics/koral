# 流程运算符与布尔运算符分层（Flow / Logical Layers）

> **Status**：Implemented · 2026-10-11
> **范围**：`and then` / `or else` / `or return` 与 `and` / `or` 的分组规则
> **体裁**：设计文档 —— 记决定与取舍，不记执行过程。

## 摘要

`and then`、`or else`、`or return` 是**流程层**（值流）；`and`、`or` 是**逻辑层**（布尔）。
两层**不隐式混用**：一个表达式是一条流程链或一条逻辑链，跨层必须加括号。
层内优先级不变（`and then` > `or else` / `or return`；`and` > `or`）。

```
a and (b or else c)              合法，语义就是它
(a and b) or else c              合法，语义是另一回事
a and b or else c                拒绝
opt and then it == 1 and false   拒绝
```

## 背景

这两组运算符一度坐在**同一条优先级阶梯**上，四档从紧到松：
`and then` > `or else` / `or return` > `and` > `or`。层内相对顺序没错，问题是**跨层可以直接
拼接**，于是 `a and b or else c` 这样的写法合法，而它字面上读起来像
`(a and b) or else c`，实际分组是 `a and (b or else c)`。

这不是优先级记忆问题，而是**阅读顺序与解析顺序打架**。读者得记住两个「中间层」的存在，
才能判断表达式边界——加工后的代码依赖隐藏规则，阅读负担大于它的价值。

## 非目标

- 不改 `and then` / `or else` 的语义（值兜底、可选链、早返回传播）。
- 不把 `and` / `or` 改成别的语法。
- 不设计全局优先级表。本设计只管流程层与逻辑层怎么分开。
- 不动 `break` / `continue` 的绑定规则（见 [`control-flow.md`](control-flow.md)）。

## 方案

### 规则

**一个表达式是一条流程链或一条逻辑链，不是两者混合。** 首个运算符决定进哪条链；
两条链都只吃自己那一层的运算符，遇到另一层的就拒绝。**括号是唯一的跨层方式**——
括号内重新从顶层开始，可以是任意一层。

层内优先级保持不变：

- **流程层**：`and then` 比 `or else` / `or return` 更紧。
  `f() and then g(it) or else h()` 是 `(f() and then g(it)) or else h()`。
- **逻辑层**：`and` 比 `or` 更紧。`a or b and c` 是 `a or (b and c)`。

### 允许

| 写法 | 分组 |
|---|---|
| `f() and then g(it) or else h()` | 流程接流程 |
| `a or b and c` | 逻辑接逻辑 |
| `a and (b or else c)` | 逻辑，右操作数是括起来的流程 |
| `(a and b) or else c` | 流程，左操作数是括起来的逻辑 |
| `opt and then (it == 1 and false)` | 流程，变换体是括起来的逻辑 |
| `ready and (opt and then it > 0 or else false)` | 逻辑，右操作数是括起来的流程 |

### 拒绝

| 写法 | 为什么 |
|---|---|
| `a and b or else c` | 字面读作 `(a and b) or else c`，实际会是 `a and (b or else c)` |
| `opt and then it == 1 and false` | 同理，两个方向都猜不得 |
| `a or b or else c` | 同上 |

「禁止混用」不等于取消优先级——优先级是语法规则，禁止隐式跨层混用是**阅读体验**规则。

### 诊断

两向各一句，span 落在**闯入的那个运算符**上（`and then` 取 `and`），读者一眼看到该给谁
加括号：

| 情形 | 文本 |
|---|---|
| 逻辑运算符到流程层 | `'and' / 'or' cannot be mixed with the flow operators 'and then' / 'or else' / 'or return' without parentheses` |
| 流程运算符到逻辑层 | `'and then' / 'or else' / 'or return' cannot be mixed with logical 'and' / 'or' without parentheses` |

### 文法

```
<expression> ::= <flow-expression> | <logical-expression>

<layer-operand> ::= <not-expression>

<flow-expression>    ::= <and-then-expression>
                       (("or" "else" <and-then-expression>) | ("or" "return"))*
<and-then-expression> ::= <layer-operand> ("and" "then" <layer-operand>)*

<logical-expression>     ::= <logical-and-expression> ("or" <logical-and-expression>)*
<logical-and-expression> ::= <layer-operand> ("and" <layer-operand>)*
```

无运算符时两个分支重合（裸 `<layer-operand>` 既是流程链也是逻辑链的零算子情形），
所以取层只在运算符出现后才可观测。

## 演进

**规则侧**：从「四档一条阶梯 + 允许跨层直连」到「两层 + 跨层要括号」。
层内优先级一个字没动；动的只是跨层那一步从隐式变显式。

**实现侧**：一度想在原四级阶梯上加事后判定（在 `parse_and` / `parse_or` /
`parse_option_flow` 里各查一下右操作数）。实际落地是把阶梯换成了**分层链**，两条理由：

1. **事后判定报不到该报的 token。** `a and b or else c` 的分组发生在 `parse_and` 的
   右操作数内部，错误发现时 `or else` 已被吃进 `OrElse` 节点，能指出的位置是那个节点的
   起点（`b`），不是要读者加括号的那个运算符。
2. **`a or b or else c` 在阶梯上根本走不到检查点。** `parse_or` 在 `or else` 处 `break`，
   剩下 `or else c` 成游离记号，报的是「unexpected token」，读者看不出规则。

现在的形状：先解析操作数，由其后的**第一个运算符**决定进哪条链。

```
parse_expression  := 操作数 层尾
层尾              := 流程链 | 逻辑链      // 由首运算符定层
流程链            := and-then 链 (("or" "else" and-then 链) | ("or" "return"))*
and-then 链       := 操作数 ("and" "then" 操作数)*
逻辑链            := 逻辑-and 链 ("or" 逻辑-and 链)*
逻辑-and 链       := 操作数 ("and" 操作数)*
操作数            := <not-expression>
```

三个前端同批改（koralc、Swift 编译器、共享的 koral-syntax），诊断文本逐字相同。

**括号现在是载荷**：printer 丢一个就把合法源改成被拒的混用。koralfmt 的
「parse parity with the compiler」按契约同批加了拒绝与断言，接受断言盯住括号保留。

## 替代方案

### 只写清楚优先级，不禁止混用

**否掉。** 那正是现状：规则本身没错，但读者必须记住四档顺序才能判断
`a and b or else c` 的边界。文档写得再清楚，也改变不了「自然读法 ≠ 实际分组」。

### 先 warning 后 error

**否掉。** 这属于**读取不可靠的语法**，不是可接受的模糊写法。warning 只会继续放大误读——
代码在被修掉之前，每个读者都要先被误导一次。直接按 error。

### 调整四档的相对顺序

**否掉，且没必要。** 问题不在层内相对顺序，在跨层直连。重排只会把误读换成另一种误读。

### 其它语言怎么做的

流程层 = 值兜底 / 分支选择 / 结果传播，逻辑层 = 布尔组合。主流语言一律把前者当**清晰的
中间层**，且不许它与后者无括号拼接：

| 语言 | 值兜底算子 | 规则 |
|---|---|---|
| JavaScript | `??` | 右结合；**不能**与 `||` / `&&` 直接混用，必须加括号，否则语法错误 |
| C# | `??` | 右结合；不与逻辑运算无意混用，靠明确的结合规则 + 跨层要括号 |
| Swift | `??` | 右结合；与条件表达式、布尔运算**分层使用**，不串 |
| Kotlin | `?:`（Elvis） | 右结合；不设计成可与 `&&` / `||` 连写的东西 |

共性是：**值兜底是一个中间层，不是布尔逻辑的一部分**。Koral 采用同一取向——
`and then` / `or else` / `or return` 是那个中间层。

## 风险与未决

- **工具链三方必须收敛。** parser、BNF、手册按各自节奏更新就会漂移；按 `docs/README`
  约定三者一起改，不能只改文档。
- **`and then` / `or else` 的求值顺序与副作用次序没有设计记录。** 本设计只定「怎么分组」，
  不定「求值顺序」。见 [`control-flow.md`](control-flow.md)「风险与未决」第 1 条。

## 实施

2026-10-11 落地。三个前端同批改：`compiler/koralc/parser/core_precedence.koral`、
`compiler-reference/Sources/KoralCompiler/Parser/ParserExpressions.swift`、
`toolchain/koral-syntax/parser.koral`。存量里断言旧分组的 3 个用例随规则改义。

看护两侧：编译器侧 9 个用例（5 个拒绝各一句诊断、2 个括号跨层按括号求值、2 个守层内
优先级未被误伤），formatter 侧 5 条拒绝断言 + 4 条接受断言。
其中 `flow_parens_logical_in_flow_test` 断言 `(a and b) or else c` **能过 parser**，
随后被 sema 以 `'or else' can only be used with Option or Result types` 拒——
证明拒绝混用的是**括号**，不是类型。

## 参考资料

- [docs/design/control-flow.md](control-flow.md)
- [docs/guide/grammar.bnf](../guide/grammar.bnf) · [document.md](../guide/document.md) ·
  [document-zh.md](../guide/document-zh.md)
- [toolchain/koral-syntax/parser.koral](../../toolchain/koral-syntax/parser.koral)
- JavaScript `??`：MDN “Nullish coalescing operator (??)”
- C# `??`：Microsoft Learn “?? and ??= operators”
- Swift nil-coalescing：Swift Book “Basic Operators”
- Kotlin Elvis `?:`：Kotlin docs “Operators and special symbols”

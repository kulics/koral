# Flow Operator Precedence and Mixing Safety

> Status: Implemented · 2026-10-11 · 实施记录见文末「实施」
> 设计问题在 parser / docs / tests 里一起收敛

## 摘要

Koral 现在的 `and then`、`or else` / `or return` 与 `and` / `or` 的相对优先级是合理的：

- `and then` 最紧
- `or else` / `or return` 居中
- `and` 次之
- `or` 最松

但“允许它们和布尔 `and` / `or` 隐式混用”会让代码在阅读时出现强烈的歧义感。对读者而言，最头痛的不是“优先级表是否正确”，而是“为什么 `a and b or else c` 看起来像合法自然写法，却是另一个层级的分组”。

因此，建议保留优先级层级不变，但把“跨层直接混用”收紧成必须显式括号。也就是：

- 允许：`opt and then (it == 1 and false)`
- 允许：`a and (b or else c)`
- 允许：`(a and b) or else c`
- 不允许：`a and b or else c`
- 不允许：`opt and then it == 1 and false`

这个方案更符合主流语言在 `??` / `?:` 等值流操作上的习惯：把“值兜底 / 分支选择 / 结果传播”当成一个清晰的中间层，而不是让它随便和布尔逻辑拼接。

## 背景

Koral 的 flow operators 已经在语法与手册中固定成三类意图：

- `and then`：可选链 / value transform，左值为 `Some` / `Ok` 时应用右值变换
- `or else` / `or return`：值合并 / 早返回传播，左值为空 / 错误时回退到默认值或返回
- `and` / `or`：布尔逻辑组合

在当前的 parser 设计中，层级已写成：

- `and then`
- `or else` / `or return`
- `and`
- `or`

这在 [toolchain/koral-syntax/parser.koral](../../toolchain/koral-syntax/parser.koral) 里被显式分成 `parse_and_then`、`parse_option_flow`、`parse_and`、`parse_or`，并在 [docs/guide/document-zh.md](../guide/document-zh.md) 与 [docs/guide/grammar.bnf](../guide/grammar.bnf) 中写明。

问题不在“这四层相对顺序错不对”，而在于：这些层之间的直接混用过于放纵。读者在看到 `a and b or else c` 时，能很自然地想成 `(a and b) or else c`；但真实语义是 `a and (b or else c)`。这不只是优先级记忆问题，而是加工后的代码依赖隐藏规则，阅读负担明显大于其价值。

## 非目标

- 不在本设计中讨论 `and then` / `or else` 的语义是否要改成更像 Rust 的 `?`、`match`、`Result` 的语法糖。
- 不讨论是否把 `and` / `or` 改成更偏函数式语法。这里的目标只限于 flow operators 的可读性与“二义性收紧”。
- 不讨论 `break` / `continue` 的控制流绑定规则；它们已经在 [docs/design/control-flow.md](control-flow.md) 里记述。
- 不尝试为所有语法设计一套全局“优先级绝对值表”；重点是让 Koral 的 flow layer 与 boolean layer 清晰地分开。

## 现状问题：为什么“看起来自然”的写法反而难读

当前行为是：

- `and then` 比 `or else` 更紧
- `or else` 比 `and` 更紧
- `and` 比 `or` 更紧

也就是说：

- `f() and then g(it) or else h()` → `(f() and then g(it)) or else h()`
- `a and b or else c` → `a and (b or else c)`

这个“按优先级解析”没有错误。真正的问题在于：

- `a and b or else c` 在字面上看，像是“先求 `a and b`，再做 `or else`”
- 但语法上的真实分组是“先求 `b or else c`，再再和 `a` 组合”

这会让代码从自然语言的阅读顺序和 parser 的解释顺序打架。Koral 的这种 flow operator 是“值流处理”，与普通布尔逻辑是不同层；如果允许直连而不要求括号，读者就必须记住：

- `and then` / `or else` 是中间层；
- `and` / `or` 是外层；
- 直接混用时要猜 parser，而不是根据自然阅读来猜。

这不是一个可持续的语法体验。

## 其它语言的复核：`??` / `?:` 的真实设计思路

下面两组对照是本设计的关键输入：

### 1) JavaScript：`??` 不能和 `||` / `&&` 直接混用

MDN 对 `??` 的文档明确说明：

- `??` 是 nullish coalescing operator
- 它是 right-associative
- `a ?? b ?? c` 等价于 `a ?? (b ?? c)`
- 但 `??` 不能和 `||` / `&&` 直接混用，必须写括号，否则会报语法错误

也就是说，语法设计上 JavaScript 采用的是“明确的语义层 + 直接混用非法”的模式：

- 合法：`a ?? (b || c)`
- 合法：`(a || b) ?? c`（如果类型允许）
- 非法：`a || b ?? c`
- 非法：`a && b ?? c`

这和 Koral 尤其像：`and then` / `or else` 是值流层，`and` / `or` 是布尔层；跨层拼接一律需要显式说明。

### 2) C#：`??` 也是右结合，并避免和逻辑运算无意混用

C# `??` 是 null-coalescing operator，文档明确写了：

- 它是 right-associative
- `a ?? b ?? c` 等价于 `a ?? (b ?? c)`
- 它的语义是“如果左侧非 null，就返回左值，否则返回右值”
- 它通常与 `?:` 一起形成一个明显的“值兜底”和“条件分支”的中间层

从设计风格看，C# 并不依赖“把优先级调成最多层大概就不出事”；它更偏向于：

- 对这类 value-propagation operator 设定非常清楚的结合规则
- 对跨层混用严格要求括号

这与 Koral 的问题非常相似：读者没有必要记住一个极其容易误读的“隐式优先级表”，而是要求写法明显。

### 3) Swift：`??` 作为 nil-coalescing，是中间层，不和布尔运算乱串

Swift 的 nil-coalescing 运算 `??` 的设计也同样是：

- 右结合
- 与条件表达式、布尔运算分层使用
- “如果左值是 nil，就用右值”被当成一类明晰的值处理逻辑，而非布尔逻辑的一部分

Swift 与 C# / JS 的共性都不是把 `??` 当成可以随意混和的“普通逻辑运算符”，而是把它视作“值兜底的中间层”。

### 4) Kotlin：Elvis `?:` 也一样，强调显式分层

Kotlin 没有 `??`，但它的 Elvis operator `?:` 是等价思路：

- `a ?: b` 表示：`a` 非空则用 `a`，否则用 `b`
- 它是 right-associative
- 它不被设计成和 `&&` / `||` “随便连写”的东西

这说明：在多门语言里，值兜底和逻辑组合确实是两类不同语义层，设计通常会避免无括号混用。

## 结论：Koral 应采用的策略

### 设计目标

1. 保持 `and then` / `or else` / `or return` 作为值流表达式的稳定优先级。
2. 明确它们属于一个中间层：不是布尔逻辑的一部分。
3. 要求跨层混用显式括号，不让它们隐式吞掉外层 `and` / `or` 或相反方向的歧义。

### 决策

保留优先级层次：

- `and then` > `or else` / `or return` > `and` > `or`

同时增加“禁止直接混用”的规则：

- `and then`、`or else`、`or return` 与 `and`、`or` 之间不能隐式拼接
- 只有括号可以跨层

### 允许的写法

- `a and (b or else c)`
- `(a and b) or else c`
- `ready and (opt and then it > 0 or else false)`
- `opt and then (it == 1 and false)`

### 禁止的写法

- `a and b or else c`
- `opt and then it == 1 and false`
- `a or b or else c`（若不加括号，歧义过强）

“禁止混用”并不等于取消优先级，它是对“优先级不够清晰”的补丁。优先级是语法规则；禁止隐式跨层混用是阅读体验规则。

## 预期收益

### 1) 读者体验明显提升

最重要的收益不是“语法更复杂”，而是读代码时不再需要靠脑补 parser 规则来判断表达式边界。

### 2) 语法更像主流语言

主流语言中的 `??` / `?:` 设计都偏向：

- 语义层清晰
- 混用要求显式括号
- 代码更接近自然语言阅读习惯

Koral 做成同样的风格会更容易被接受。

### 3) 维护成本低

这并不是重构整个表达式系统，而是收紧一种容易误读的写法。修复面只在 parser 和 docs/tests 上，且不需要动 AST 语义结构。

## 实施计划

### 阶段 1：parser 收紧

修改 [toolchain/koral-syntax/parser.koral](../../toolchain/koral-syntax/parser.koral) 中的 `parse_and` / `parse_or` / `parse_option_flow` / `parse_and_then`，加强以下检查：

- 在 `parse_and` 中，如果右值中出现 flow operator 但未使用括号，报错
- 在 `parse_or` 中，同理处理
- 在 `parse_option_flow` 中，禁止 `or else` / `or return` 与上层 `and` / `or` 直接隐式拼接
- 允许在括号中的子表达式继续访问外层层级

原则：

- 解析器允许显式分组
- 解析器拒绝“看起来自然但存在隐式歧义”的写法

### 阶段 2：文法与手册同步

更新：

- [docs/guide/grammar.bnf](../guide/grammar.bnf)
- [docs/guide/document-zh.md](../guide/document-zh.md)
- [docs/guide/document.md](../guide/document.md)
- [docs/guide/grammar_preview.koral](../guide/grammar_preview.koral)

新增说明：

- 语义层级保留不变
- 跨层混用必须括号
- 它们不是布尔逻辑的一部分

### 阶段 3：回归测试

新增 parse/diagnostic tests，包括：

- `a and b or else c` => 语法错误
- `opt and then it == 1 and false` => 语法错误
- `a and (b or else c)` => 合法
- `(a and b) or else c` => 合法
- `opt and then (it == 1 and false)` => 合法

可以在 compiler-runner / parser regression tests 中做一组最小测试，覆盖“允许”和“禁止”的两端。

## 风险与未决

### 风险 1：历史代码的兼容性

现有项目中可能已经出现一些“依赖隐式混用”的写法。如果直接开启严格模式，可能引发编译失败；需要在一轮兼容性修正里同步清理。

### 风险 2：工具链文档漂移

如果 parser、BNF、手册分别按各自节奏更新，很容易出现三处不一致。这里必须按 docs/README 约定：三者应该收敛，任何不一致都要更新而不仅仅改文档。

### 风险 3：是否需要 warning 还是 error

某些项目可能更希望“先 warning，后 error”。对本设计，建议直接按 error 对待，因为这属于读取不可靠的语法，不是可接受的模糊写法。warning 只会继续放大误读。

## 结论

Koral 的优先级层位并不需要大改；真正应该改的是把“跨层隐式混用”从允许状态变成显式分组状态。这个修正最符合其它语言 `??` / `?:` 的设计经验：

- 清晰中间层
- 右结合
- 跨层必须括号
- 让代码更符合自然阅读和长期维护成本

这会把 Koral 的 flow operators 从“记忆题”改成“清楚的语义层”，是一次低风险、高收益的语法整理。

## 参考资料

- [docs/design/control-flow.md](control-flow.md)
- [docs/guide/document-zh.md](../guide/document-zh.md)
- [docs/guide/document.md](../guide/document.md)
- [docs/guide/grammar.bnf](../guide/grammar.bnf)
- [toolchain/koral-syntax/parser.koral](../../toolchain/koral-syntax/parser.koral)
- JavaScript `??`：MDN “Nullish coalescing operator (??)”
- C# `??`：Microsoft Learn “?? and ??= operators”
- Swift nil-coalescing：Swift Book “Basic Operators”
- Kotlin Elvis `?:`：Kotlin docs “Operators and special symbols”

## 备注

这份文档是“为什么这样设计”的计划说明，不是运行时/formal-proof 说明；它的目标是给 parser / docs / tests 提供一个一致的行动目标，并明确这不是对已有优先级的一次大改，而是对“混用友好性”的一次收紧。

## 实施

2026-10-11 落地。三个前端同批改：`compiler/koralc/parser/core_precedence.koral`、
`compiler-reference/Sources/KoralCompiler/Parser/ParserExpressions.swift`、
`toolchain/koral-syntax/parser.koral`。

**与「实施计划」的一处差别，先记这个。** 阶段 1 说的是「修改 `parse_and` / `parse_or` /
`parse_option_flow` / `parse_and_then`，加强检查」——即在原来的四级阶梯上事后判定。实际是把
阶梯换成了**分层链**，理由有两条：

1. **事后判定报不到该报的 token。** 原结构里 `a and b or else c` 的分组发生在
   `parse_and` 的右操作数内部，错误发现时 `or else` 已经被吃进 `OrElse` 节点，
   能指出的位置是那个节点的起点（`b`），不是要读者加括号的那个运算符。
2. **`a or b or else c` 在原结构里根本走不到检查点。** `parse_or` 在 `or else` 处
   `break`，剩下 `or else c` 成了游离记号，报的是「unexpected token」，读者看不出规则。

现在的形状是：先解析操作数，由其后的**第一个运算符**决定进哪条链；两条链都只吃自己那一层的
运算符，遇到另一层的就在**那个运算符上**拒绝。层内优先级原样保留。

```
parse_expression      := 操作数 层尾
层尾                  := 流程链 | 逻辑链          // 由首运算符定层
流程链                := and-then 链 (("or" "else" and-then 链) | ("or" "return"))*
and-then 链           := 操作数 ("and" "then" 操作数)*
逻辑链                := 逻辑-and 链 ("or" 逻辑-and 链)*
逻辑-and 链           := 操作数 ("and" 操作数)*
操作数                := <not-expression>（即原 `parse_logical_not`，未改）
```

**诊断**（两编译器逐字相同，差分闸门默认开）：

| 情形 | 文本 |
|---|---|
| 逻辑运算符到流程层 | `'and' / 'or' cannot be mixed with the flow operators 'and then' / 'or else' / 'or return' without parentheses` |
| 流程运算符到逻辑层 | `'and then' / 'or else' / 'or return' cannot be mixed with logical 'and' / 'or' without parentheses` |

span 落在闯入的那个运算符上（`and then` 的 `and`），读者一眼看到该给谁加括号。
koralc 走 `parser_error_at_current`，Swift 走 `ParserError.rejectedConstruct`——
后者本就是「记号都合法、构型被拒」这一类，比套 `unexpectedToken` 的
`Unexpected token: <got>, expected: <want>` 框子更贴。

**风险 1 的实际答案**：存量混用只有一处——`tests/compiler-cases/` 里 3 个断言旧分组的
用例本身。`std/`、`compiler/`、`compiler-reference/`、`toolchain/`、`samples/`、
`tests/compiler-runner/` 全部干净（它们要么纯流程、要么纯逻辑，跨层处本来就写了括号）。
`codegen_mir.koral:97` 那种 `(a or else b) and (c or else d)` 是括号跨层，不是混用。

**风险 3 的答案**：按 error，不是 warning。理由见「风险与未决」。

**测试**（9 个，覆盖禁止与允许两端，以及层内优先级未被误伤）：

| 用例 | 断言 |
|---|---|
| `flow_mix_and_after_flow_error` | `'and' cannot be mixed with the flow operators` |
| `flow_mix_or_after_flow_error` | `'or' cannot be mixed with the flow operators` |
| `flow_mix_and_then_after_logical_error` | `'and then' cannot be mixed with logical` |
| `flow_mix_or_else_after_logical_error` | `'or else' cannot be mixed with logical` |
| `flow_mix_or_return_after_logical_error` | `'or return' cannot be mixed with logical` |
| `flow_mix_parens_allowed_test` | 两种括号跨层写法按括号的语义求值 |
| `flow_parens_logical_in_flow_test` | `(a and b) or else c` **能过 parser**，随后被 sema 以 `'or else' can only be used with Option or Result types` 拒——证明拒绝的是类型，不是解析 |
| `flow_layer_internal_precedence_test` | `opt and then it * 10 or else 0` == 20（`and then` 仍紧于 `or else`） |
| `logical_layer_internal_precedence_test` | `a or b and c` == 1（`and` 仍紧于 `or`） |

原 `and_then_and_precedence` / `or_else_and_precedence` / `or_option_flow_precedence`
三个用例断言的正是被禁止的分组，按新规则改名改义（`git mv` 保留历史）。

**formatter 侧的同批看护**（`toolchain/koral-syntax/README.md`「Parse parity」要求：
编译器新拒一个形状，这里就要同批加拒绝 + 断言）：`koral-syntax/parser.koral` 加了同样的
拒绝，`toolchain/koralfmt/test_fmt.koral` 的「parse parity with the compiler」段加了
5 条拒绝断言 + 4 条接受断言。后者专门盯**括号不能被 printer 吃掉**——括号现在是载荷：
丢一个就把合法源改成了被拒的混用。README 的拒绝表补了这一行。

**验证**：seed 自检、主闸、stage2、差分四道各 **662/662**（656 + 新增 6 个用例），
自举 `FIXED POINT`、`dangling=0`；formatter **132/132**（123 + 新增 9 条）· corpus 220/0；
`koral_doc --check` 14 模块最新；samples 与 `toolchain/koral` 构建工具在
**两个编译器下都能构建**，`cat` 样例测试 10/10、`sha256sum` 13/13 通过。

**尚未做**：`and then` / `or else` 的短路语义与副作用次序**仍然没有设计记录**——
`control-flow.md`「风险与未决」第 1 条原样开放。本次只收紧「怎么分组」，不动「求值顺序」。

# 流程算子的形态与折叠

> **Status**：Implemented · 2026-10-24
> **范围**：`and then` / `or else` / `or return` 的操作数形态、`it` 的存废、`and then` 的折叠规则
> **分组规则**（流程层/逻辑层怎么分开）见 [`flow-logical-layers.md`](flow-logical-layers.md)；
> **求值顺序与短路**见 [`control-flow.md`](control-flow.md)；
> **文法产生式**见 [`../guide/grammar.bnf`](../guide/grammar.bnf)；**用法**见 [`../guide/document.md`](../guide/document.md)。
> **取舍判据**（复杂度预算、设计公理）见 [`design-axioms.md`](design-axioms.md)。
> **本文只记为什么**；怎么落地见 [`../implementation/flow-operator-forms-implementation.md`](../implementation/flow-operator-forms-implementation.md)。

## 摘要

三个算子各按自己的角色取形态，共享一条显式绑定通道：

- `and then` **以解包值为接收者**——链式（`and then .f()`）或绑定（`and then as v in …`）；
- `or else` **提供替代值**——裸表达式或绑定（`or else as e in …`，**仅 Result**，绑 `Error`）；
- **没有隐式 `it`**，`it` 不是关键字，是普通标识符。

`and then` **折叠**：变换的声明返回类型已是同族就直接采用，否则包一层。
`or else` / `or return` 不折叠——**只有包装结果的算子才折叠**。

## 背景

要定的三件事：

1. **操作数的形态。** 旧设计里 `and then` / `or else` 的操作数是普通表达式，靠隐式关键字
   `it` 指代解包值（`and then it * 2`）。形态的问题是：要不要把绑定显式化，显式化之后
   常见路径会不会变长。
2. **`it` 的存废。** `it` 是硬关键字，占死一个标识符；嵌套时会遮蔽；且它是全语言唯一的
   隐式绑定名——lambda 参数必须具名（`(x) => …`），唯独流程算子例外。
3. **`and then` 是 map 还是 bind。** 旧设计恒不展平：变换返回 `Option[V]` 时结果是
   `Option[Option[V]]`。这个规则与「可选链」的通行语义相反（`?.` 在 Swift / Kotlin / JS
   一律折叠），而链式形态正是以「等价于 `x?.f()`」立的项。

三件事互相牵连：形态决定 `it` 能不能删，链式形态的立项目标又决定 `and then` 必须折叠。

## 非目标

- **流程层与逻辑层怎么分组、为什么禁止隐式跨层混用** → [`flow-logical-layers.md`](flow-logical-layers.md)。
- **求值顺序、短路、`break`/`continue` 的绑定** → [`control-flow.md`](control-flow.md)。
- **运算符的文法产生式、层内优先级** → [`../guide/grammar.bnf`](../guide/grammar.bnf)。
- **三个算子的写法与示例** → [`../guide/document.md`](../guide/document.md) §2「Option and Result Flow」。
- **符号化（`?.` / `??`）** 不在方案内，作为替代方案记在文末。

## 方案

### 形态：各按角色，共享一条绑定通道

| 算子 | 干什么 | 操作数角色 | 形态 |
|---|---|---|---|
| `and then` | 对解包值做变换 | 有接收者 | `.成员链`（链式）｜`as v in <layer-operand>`（绑定） |
| `or else` | 提供替代值 | 没有接收者 | `<layer-operand>`（裸表达式）｜`as e in <layer-operand>`（绑定，仅 Result） |
| `or return` | 传播 | — | 无操作数（语法糖） |

**不对称是角色决定的**，不是不一致。对照 `x?.title ?? "untitled"`：`?.` 后面接成员访问
（链在解包值上继续），`??` 后面接表达式（一个替代值）——同一条不对称。两边共享的是
**绑定形态**（`as n in`）：需要名字时同形，不需要名字时各按角色走短形态。

`and then` **没有裸表达式形态**。变换体天然要对解包值做计算，忽略值的变换不为它留形态
（见「替代方案」）。

绑定体的边界是 `<layer-operand>`，不是完整表达式。于是
`x and then as v in v > 0 or else 0` 仍是 `(x and then as v in v > 0) or else 0`，
与旧变换体的分组、与分层规则一致——绑定体不吞掉后续的 `or else`。

### 链式：前导点是上下文接收者的成员

**前导点永远是「上下文接收者的成员」，上下文有两种。**

- **值上下文**：紧跟 `and then`，接收者是刚被解包的值 → `and then .f()` = `and then as v in v.f()`。
- **类型上下文**：期望类型已知处（`or else` 的默认值、`let x T = .foo()`、有类型的实参位），
  接收者是那个类型 → implicit member，规则原样不动。

一个机制，两个上下文。`and then` 之后的 implicit member 读法不可达（`and then` 不把期望
类型下推到变换体），所以这是把一个死槽位改活，不是抢一个在用的槽位。

链式是**绑定形态的纯语法糖**，没有链式才有的语义——对**后缀链形的体**逐字等价：

```koral
config and then .title            // 糖
config and then as v in v.title   // 展开
```

糖可以随时消掉（链形体总能展开成绑定），因此它骗不了人——观感上被挑的只是糖，
语言是绑定形态。**反向不成立**：`as v in v.port + 1` 这类算在值上的体没有链式写法，
糖只覆盖「点链」那一侧。

链式是**完整后缀链**（`.f(x).g.h`、`.f()[0]`），接收者省略在链首，读作 `x?.f().g`。
多步可选是 `x and then .f() and then .g()`（每步各自展包/包回）；`and then .f().g()` 是
**展包一次后连调**，中间步返回可选时不会自动穿——这是 `?.` 的同一条规则。

### `it` 不复存在

`it` 不是关键字，是普通标识符（`let it = 5`、`for it in xs`、字段名 `it` 全部合法）。
流程算子不再注入任何隐式名字：要名字就写绑定（`as v in`），链式不需要名字。

三条理由各自独立成立：

- `it` 是硬关键字，永久锁死一个短名字（iterator / item 的自然命名）。
- 它是全语言唯一的隐式绑定名，与 lambda 必须具名不对称；嵌套时还会遮蔽
  （`outer and then (inner or else it + 1)` 里 `it` 换了所指）。
- 旧 `or else` 在 Option 上的 `it` 是**未定义的**：绑定落在 `Some` 分支的模式变量上，
  而兜底体跑在 `None` 分支——那条路径上 `it` 从未被绑定，类型检查却放行。

未绑定名诊断对 `it` 特判给迁移指路，但不为它保留关键字。

### 折叠：只有包装结果的算子才折叠

`operand and then transform` 的结果类型**恒为左操作数的同族**（`Option` → `Option`，
`Result` → `Result`）。变换的**声明**返回类型怎么来，决定内层：

| 变换的声明返回类型 | 结果 | 对应 |
|---|---|---|
| 同族（`Option[_]` / `Result[_]`） | **直接采用**，不再包一层 | bind / flat map |
| 其它（普通类型、异族、泛型参数） | **包一层**（`Some(v)` / `Ok(v)`） | map / lift |

「直接采用」不是「展到最内层」：变换返回 `Option[Option[X]]` 时结果就是 `Option[Option[X]]`，
省掉的只是外层那一包。

**判定只看声明类型，泛型参数视为不透明。** `f: (T) -> U` 里的 `U` 是类型参数，
一律走「包一层」——于是 `map[U Any](f (T) -> U) Option[U]` 对所有实例化
（含 `U = Option[V]`）都给出 `Option[U]`，Functor 律不破。判定不得在单态化实例上重做，
否则 `map` 的签名会在 `U = Option[V]` 时被折叠击穿。

折叠之所以存在，是为了撤销一次包装：`and then` 是三个算子里**唯一把结果留在流程族里**
的（`or else` / `or return` 把流程退成内层 `T`，不包装）。所以：

> **只有包装结果的算子才折叠。**

跨族（Option 左、变换返回 Result）取「包一层」，不报错——`map` 必须能构造
`Option[Result[V]]`，若算子在「声明返回异族」时报错，`x and then f(it)` 与 `x.map(f)`
对同一个 `f` 会给出不同裁定。

### `or else` 不折叠，绑定仅 Result

`or else` 的默认值类型**恒为左操作数的内层类型 `T`**，结果恒为 `T`。它不包装，故无可折叠。

绑定形态（`as e in`）**仅对 Result 合法**，绑的是 `Error`；Option 的 `None` 没有载荷，
写绑定是错误，而不是绑一个只在 `Some` 路径存在的变量。

「没有就再试一次」（第二个可选计算）不是 `or else` 的折叠，是另一个操作
（Rust 的 `or_else(f: () -> Option<T>) -> Option[T]`）。它不能挂在 `or else` 上：那会
**翻转 happy path**（`or else d` 在 `Some` 路径交出解包值 `v`，`or else y` 在 `Some` 路径
必须交出 `Some(v)` 才能与 `y` 同型），且结果形状会在 `T` 与 `Option[T]` 之间翻转。
需要它时用 `when`，或将来加同名 std 方法，不压进算子。

### `or return` 不受影响

`or return` 是 `or else { return .Error(e); }` / `or else { return .None(); }` 的语法糖
（脱糖用编译器内部的绑定名）。它与 `or else` 同为出口：结果是内层 `T`，不折叠。

## 演进

从「隐式 `it` + 恒不折叠」到「显式绑定 + 折叠」，三处一起动才自洽：

1. **形态**：操作数从「普通表达式 + 隐式 `it`」变成「链式 / 绑定」两种形态，
   `or else` 保留裸表达式（它的兜底值天然不需要名字）。
2. **`it`**：随形态显式化一并删除，标识符释放。
3. **折叠**：链式形态以「等价于 `x?.f()`」立项，而 `?.` 一律折叠，所以 `and then` 必须从
   map 改成 bind。

只动一处不成立：留着 `it` 则形态多一条后门，不折叠则链式不等价于 `?.`。

这是一次**替换**而不是叠加（公理 7）：`it` 机制整体删除，`and then` 的 map 语义被 bind
语义替换。没有为新写法增加第二套并行规则。

## 替代方案

### 保留 `it`（原样 / 软关键字 / 仅链式位置特殊）

**否掉。** 三条各自独立成立：硬关键字锁死标识符；隐式绑定是全语言唯一一处，嵌套遮蔽要
额外记；Option 上的 `or else it` 是未定义行为（见「方案」）。

「软关键字、只在链式位置特殊」的变体**同样否掉**：`it` 的含义会跟着形态变（链式里是
接收者、绑定体里是普通名字），还要在 `let it = 5` 与 `x and then it.f()` 之间裁定遮蔽。

### 符号化：`x?.f()` / `x ?? 0` / `x?`

**否掉，但要如实记它是强竞争方案。** 优势是纯导航与取默认场景下约 2× 短，且是主流收敛的
形状（Rust 的 `?` 还证明符号能一套通吃 Option + Result，所以「词形才能覆盖两族」不是
决定性理由）。

否掉的决定性理由是**字形占用**：`?` 已经是 weakref（`?T` 类型、`?expr` 升级成 `Option[T]`），
而弱升级的返回值正是 Option，于是 `?h?.f() ?? d` 会在同一表达式里让一个字形承载四到五个
含义。要换符号，第一步是把 weakref 语法挪走——那是另一次更大的破坏性改动。

配套理由：流程/控制词汇通篇是词形，`?.`/`??` 会是仅有的符号型流程算子；`or return` 是可
grep 的传播点；生成器的漂移方向是符号，而 `?x` 在 Koral 里会落到 weakref 语义上
（**语法合法、语义完全不同**），词组则没有「从别的语言漂过来」的口子。

**不加符号别名。** 双拼写违反单一拼写纪律（公理 6）。长度问题在词形内部解：把误当
`or else` 的纯传播块清成 `or return`，比换词表实惠。

### `and then` 后裸调用即方法调用（去掉链式的点）

**否掉。** 那会让 `and then f(x)` 成为全语言唯一一处「裸调用当方法调用」的位置，
打破 `x.f()` 与 `f()` 的语言级不变量。点只做一件事：成员运算符，接收者被省略。

### `and then _.f()`（用通配符写出省略的接收者）

**否掉。** 接收者与点的距离从 8 个字符缩到 1 个，但多两个字符只买视觉；`_` 目前是**模式**
通配符，让它在表达式位当占位符是给它新增第二个含义（Scala 3 就废弃了表达式位 `_` 占位，
理由正是歧义）。

### 绑定形态用 lambda：`and then (v) => body`

**否掉，理由是 body 边界。** lambda 的 body 是完整表达式，`and then (v) => v > 0 or else false`
会把 `or else false` 整个吞进 lambda 体；`as v in` 的 body 是 `<layer-operand>`，
分组与分层规则原样保留。它也更长。

### 绑定分隔词用 `then`：`and then as v then body`

**否掉。** `then` 在全语言是「被选中的分支的体」，它前面永远是一道门（条件、模式+守卫），
`and then` 的 `then` 本身就是 when-arm 的 `then` 压缩进去的——写 `as v in` 时判断已经做完，
剩下的是划作用域，`in` 才是那个词（`when x in { … }` 的 `in` 就是「左边的名字从这里开始
在右边区域可见」）。再写 `then` 会在体里标出第二个分支记号。

### `or else` 也折叠（第二次尝试语义）

**否掉。** 见「方案」：它翻转 happy path，结果形状在 `T` 与 `Option[T]` 之间翻转。
`and then` 的折叠结果形状恒为 `Option<_>`，这条不是。

### 给 `or else` 加链式（`or else .message()` = `as e in e.message()`）

**否掉。** 只在 Result 且成员类型恰好是 `T` 时可用，一个大部分时候用不了的形态比没有更糟。
`or else` 的兜底体多半是「打日志 + 早退」的块，不是单次成员调用。

### 禁掉 `or else` 默认值里的前导点（消掉点的双义）

**否掉。** 那是在单个槽位禁止一个全语言通用机制（implicit member），换来的只是少一种读法。
现在的 wrinkle 是「点的接收者随上下文变」（一个机制、两个上下文），那个 wrinkle 是
「implicit member 在某处非法」（一个例外）——后者概念上更大。安全网是诊断文案。

### 丢值变换（`as _ in expr` 或裸表达式第三分支）

**否掉专门的形态。** 裸表达式第三分支是隐式名字的后门，也是链式与绑定之间的第三种读法；
专用的 `as _ in` 是为省两个字符单开一个形态。

忽略值的变换存在但极少（树内只有两处探针变换）。它们用命名绑定、名字不写进体即可，
不为此加语法。

## 风险与未决

- **折叠的判定落点必须是声明类型。** 若按单态化后的形状重判，`map` 的签名会被击穿
  （`U = Option[V]` 时折叠成 `Option[V]`）。这是本设计唯一要求实现侧专门验证的点。
  若将来判定落点被迫改成「按实例化形状」，`map` 必须改写成不含 `and then` 的 `when`
  形式（对任何规则都正确），并把「泛型参数不透明」写成实现约束。
- **前导点的双义**是链式形态的真实代价（`and then .f()` = 解包值成员，`or else .f()` =
  implicit member），由「上下文接收者」一条规则 + 指路诊断吃掉。若投诉集中，备选是收紧
  `or else` 默认值里的前导点（见替代方案），但默认不做。
- **链式是糖、绑定是正体**，两种拼写并存。它过公理 6（一个问题一种主流表达）的方式是
  「一种语义、两种拼写，糖可随时消掉」，不是两种语义。若将来发现生成器混用，收敛建议是
  只吐绑定形态，而不是删链式。

## 实施

已落地，规则在三端（koralc、Swift 编译器、共享 koral-syntax）与 koralfmt 里同批实现。
落地顺序、载荷作用域的实现形状、看护清单与被否的实现写法见
[`../implementation/flow-operator-forms-implementation.md`](../implementation/flow-operator-forms-implementation.md)。
验证走 [`../implementation/developer-guide.md`](../implementation/developer-guide.md) 的验证链。

## 参考资料

- [docs/design/flow-logical-layers.md](flow-logical-layers.md) · [control-flow.md](control-flow.md) · [design-axioms.md](design-axioms.md)
- [docs/guide/grammar.bnf](../guide/grammar.bnf) · [document.md](../guide/document.md)
- Swift optional chaining：Swift Book “Optional Chaining”（结果不产生双重 optional）
- Rust `Option::and_then` / `map` / `or_else`：std 文档（bind 与 map 是两个方法）
- Scala 3 弃用表达式位 `_` 占位（占位符歧义）

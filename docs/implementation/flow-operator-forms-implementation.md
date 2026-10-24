# `../design/flow-operator-forms.md` —— 实施记录

> **状态**：折叠语义、链式/绑定形态、`it` 删除均已落地，看护齐全。
> 设计正本是 [`../design/flow-operator-forms.md`](../design/flow-operator-forms.md)。
> 验证走 [`developer-guide.md`](developer-guide.md) 的验证链。

## 0. 范围裁定

| 块 | 状态 |
|---|---|
| `and then` 折叠语义（同族直接采用、其余包一层） | 已落地 |
| 链式 `.成员链` 与绑定 `as name in body` | 已落地 |
| `or else as e in`（仅 Result） | 已落地 |
| 隐式 `it` 与 `and then` 的裸表达式形态 | 已删除 |
| `or else` 的裸兜底形态 | 保留（兜底值天然不需要名字） |
| 第二次尝试语义（`or_else(f: () -> Option[T])`） | **不做**，见设计「替代方案」 |

## 1. 为什么分四期

不是按难度分，是按**自举约束**分：`compiler/` 与 `tests/compiler-runner/` 都是 Koral 程序，
改语法必须先让旧编译器认识新语法，才能迁它们的源码。所以顺序固定为
**折叠语义 → 形态（新旧并存）→ 迁源码 → 收形态删 `it`**。

阶段 2 **收不得** `and then` 的裸形态：std 每次构建都要编译，而 `map` 当时还写着
`self and then f(it)`。收形态放在最后一期，等所有源码都不再用它。

## 2. 折叠的判定落点

**判定只看变换的声明返回类型，泛型参数视为不透明。** 这是实现侧唯一必须验证的点：
`map[U Any](f (T) -> U) Option[U]` 对所有实例化（含 `U = Option[V]`）都要给出 `Option[U]`。

- koralc：`type_checker_methods.koral` 的 `and_then_collapses` + `compute_and_then_result_type`
- Swift：`TypeCheckerExpressions.swift` 的 `andThenCollapses` + `computeAndThenResultType`

若实现按单态化后的形状重判，`map` 的签名会在 `U = Option[V]` 时被折叠击穿。那时
`map` 必须改写成不含 `and then` 的 `when` 形式（对任何规则都正确）。

降级时 Some/Ok 分支体随之二选一：折叠直接用变换结果，包一层才建 `Some(v)` / `Ok(v)`；
空侧永远重新包自己的 `None` / `Error`。

## 3. 形态的 AST 承载

两个节点承载形态，缺一不可：

- `FlowChainExpr`（链式，包装后缀链）
- `FlowBindExpr`（`as name in body`）
- `FlowReceiver`（链式的省略接收者，**打印为空**，于是 `FieldAccess` 在它上面读作 `.field`）

`FlowChainExpr` 这层包装是必要的：它让 printer 与 sema 把**链式与 implicit member 分开**
——同串记号，两种所指（见设计「前导点是上下文接收者的成员」）。链式复用整条后缀循环，
所以 `.f(x).g`、`.f()[0]` 都自然支持。

**形态是载荷**：koralfmt 的往返断言盯住前导点与绑定名不丢。

## 4. 载荷的命名与作用域

三种来源的载荷各有一个名字：

| 来源 | 载荷名 |
|---|---|
| `as name in body` | 源码里的 `name` |
| `.成员链` | 保留内部名 `__flow_payload`（`FlowReceiver` 解析到它） |
| `or else` 的裸兜底 | **不绑定**；降级用的模式变量只把载荷从匹配臂送到结果，源码里引用不到 |

**`or else` 的裸兜底不注入任何名字。** 旧设计在这里注入 `it`，而它只在 `Some` 分支的
模式上被绑；兜底体跑在 `None` 分支，读到的是未初始化的局部量。**为什么删 `it`** 见
设计的「`it` 不复存在」，这里只记机制：注入点去掉了，未绑定路径就不存在。

`or return` 的脱糖是 `or else as err in { return .Error(err); }` / `or else { return .None(); }`，
不用任何隐式名字。

Swift MIR 里曾有一处按名字 `"it"` 声明临时量的特判——那正是垃圾值的来源。已删。
绑定名现在都由模式注册，与普通模式变量同路。

## 5. 边界（明确不做）

- **`and then` 的裸表达式形态**——隐式名字的后门，已删，报错指路。
- **丢值变换的专用形态**（`as _ in`）——极少用，命名绑定、名字不写进体即可。
- **`or else` 的链式**——只在 Result 且成员类型恰好是 `T` 时可用。
- **符号别名**（`?.` / `??`）——双拼写违反公理 6。
- **`or else` 的折叠**——翻转 happy path，见设计。

## 6. 看护

| 看护 | 盯什么 |
|---|---|
| `and_then_flatten_same_kind.koral` | 折叠、跨族包一层、显式嵌套只折一次 |
| `and_then_generic_opaque.koral` | 判定落在声明类型（**类型标注即断言**） |
| `flow_chain_form_test.koral` / `flow_bind_form_test.koral` | 链式、绑定、遮蔽、body 边界、糖等价 |
| `flow_payload_scope_test.koral` | 每个算子自己的载荷作用域，互不泄漏 |
| `it_is_ordinary_identifier_test.koral` | `it` 是普通标识符 |
| `and_then_plain_operand_error.koral` / `flow_bind_or_else_option_error.koral` / `flow_chain_member_missing_error.koral` | 三处拒绝 |

koralfmt 侧：链式与绑定的往返断言 + `or else as e in` 是**良构语法**的往返断言。

**看护的分界**：`or else as e in` 在 Option 上是**语义**拒绝，不是语法拒绝。formatter 必须
照常格式化良构语法，拒绝由编译器做——所以那条断言写成往返接受，拒绝归
`flow_bind_or_else_option_error.koral`。

## 7. 被否掉的实现写法

- **把 `FilterMapIterator.next` 塌成一行 bind。** 否掉：它要**跳过**映射为 `None` 的元素
  继续迭代，单行 bind 只走一步。折叠的收益是「串两个可选步骤」，不是「跳过失败的步骤」。
- **用脚本批量改 `it`。** 形状可以机器改，但有两条约束：块体里的替换会把**注释里的英文
  `it`** 一起改掉（`run from inside it` → `run from inside e`），改完必须扫注释；且
  `or else` 在 Option 上没有载荷可绑，脚本会给返回 Option 的源误加绑定。后一条由
  `Option's 'None' has no payload to bind` 当场拦住——正是这条诊断该干的事。
- **用 `test_error_contains` 让 koralfmt 拒绝语义错误。** 否掉：formatter 只管语法。
- **删关键字时不找断言旧规则的看护。** `it` 变普通标识符后，koralfmt 里
  「`it` as declaration name rejected」翻红——它不在编译器套件里，靠 toolchain 步暴露。
  删规则时要把断言该规则的看护一起找出来。

## 8. 验证

`scripts/verify.sh` 全链：seed 自检、主门、自举两轮 + 固定点、stage2、差分门各 809/809，
`FIXED POINT`，`dangling=0`；koralfmt 220/220。差分门默认开诊断比对，两端错误面逐字相同。

跑链的两条：`scripts/verify.sh` 无 `+x`，用 `bash scripts/verify.sh`；不要把链管道给
`tail` 再读退出码——那是最后一个命令的退出码，`permission denied` 也会报成功。

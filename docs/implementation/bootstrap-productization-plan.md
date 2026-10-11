# bootstrap 产品化 —— 约束与演进

> **状态**：产物质量、panic 收口、跨编译器对拍三块均已定型，角色分工已定。

身份匹配改造的执行记录见 [`identity-matching-tracking.md`](identity-matching-tracking.md)。

## 本期边界（明确不做）

- **生成 C 字节一致**不作为目标。两个编译器给 `DefId` 编号的规则不同，
  产物**永远不可能逐字节相同**；对拍的是行为（接受/拒绝、stdout、退出码）与诊断文本。
- `--no-std` 是独立议题，不在这里做。
- 不借这个项目加语言特性。

## 硬性约束

| 规则 | 含义 |
|---|---|
| **行为零变化 / 诊断文本一字不变** | 套件断言精确子串，不得改变（除非用户明确要求行为变化） |
| **不能绕过 / 不硬编码** | 不得用特例表、魔法数字或假实现来过关 |
| **不选最容易通过的办法** | 不得选省事的做法让问题恶化 |
| **一处处手工改** | 禁止盲改正则，逐处手工改 |

（其余仓库级规则见 [`identity-matching-tracking.md`](identity-matching-tracking.md) §1。）

## 信任边界

**测试 harness 永远由冻结的种子编出来，绝不由被测实现编。** 否则被测实现里的
codegen 缺陷会污染本该抓住它的那个东西。这条写进 `.github/workflows/ci.yml` 第 0 步。

## 被否掉的方案

### 过度实例化：不用 DCE，改物化

候选之一是靠死代码消除（DCE）收掉过度实例化。**否掉，改做「泛型 tool block 物化」**：
DCE 是在下游擦症状，物化规则才是根因。

两个引用图上的坑，与路线无关：

- mono 的 `FunctionDecl` body 是**占位**，真身要走 `get_concrete_function_body`。
- `Symbol` 既当引用又当类型引用，遍历引用图时会重复访问同一个节点。

**泛型 tool block = generic extension template，调用期物化。** 不是「声明期就算完」。

### witness-per-instance，而不是把 bootstrap 的 fallback 搬进 Swift

跨编译器分歧时评估过两条路：

| 路线 | 做法 | 结论 |
|---|---|---|
| A | 把 bootstrap 的 fallback 逻辑移植进 Swift | ❌ 否掉——两份实现两套 fallback，分歧只会更多 |
| B | 每个实例一份 witness（rustc 的 `Instance` 模型） | ✅ 采用 |

B 是 rustc 的做法：witness 按**实例**记，不是按 trait 记。

## panic 的判定方法

**可达的 panic 不得变成面向合法输入的用户诊断。** 一个 panic 如果能被合法输入触发，
那是缺陷；改成报诊断等于把缺陷藏起来。判定分三类：

1. **流水线不变量** —— 不可由合法输入触发，保留 panic。
2. **可由合法输入触发** —— 缺陷，必须修。
3. **内部 API 误用** —— 保留 panic。

## 技术约束

- **vtable 头字段名是 `_Base`，不是 `base`。** 曾经撞过名，故改名并做过双重不撞证明；
  该字段是**布局用**，任何地方都不得按名字读它。
- **vtable 槽序是父 trait 在前。** sema 与 mono 曾一个按 LIFO（self 在前）一个按父在前，
  两边不一致会让 `methodIndex` 取错。现在统一**父在前**。
- **用户不该看见 `struct#N`。** `struct#N` / `enum#N` 是身份拼法（`stable_type_key`
  的 `S#N` / `E#N`），不是显示名。显示路径一律读声明名，id 拼法只是最后兜底。
- **`Fn(..)` 与 `Func(..)` 不是缺陷。** `Fn(..)` 是身份键拼法，`Func(..)` 是显示拼法，
  分离是有意的。

## 角色分工

- `compiler/` —— **主实现**，正在开发的那个。
- `compiler-reference/` —— **冻结的 Swift 编译器**：参考预言机、构建种子、备份。
  **冻结不删**。它不是开发目标。

详见 [`developer-guide.md`](developer-guide.md) "Compiler roles" 与
[`../../compiler-reference/README.md`](../../compiler-reference/README.md)。

## 未决

1. **pattern 里的 `*T`** 与表达式层的解析规则仍有残留不一致。
2. **`layout_key` 有两套命名**，无用例可写，尚未统一。
3. **两边转义规则不一致**（C 标识符转义在两个编译器里各写了一份）。

## 参考

- 验证链的权威定义：[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)。
- 差分预言机契约：[`../../tests/README.md`](../../tests/README.md)。
- 身份匹配改造记录：[`identity-matching-tracking.md`](identity-matching-tracking.md)。

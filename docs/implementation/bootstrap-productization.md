# bootstrap 产品化 —— 约束与裁定

> **状态**：产物质量、panic 收口、跨编译器对拍三块均已定型，角色分工已定。
> 本文记**当前**的约束与裁定；执行过程见 [`identity-matching-tracking.md`](identity-matching-tracking.md)。

## 边界（明确不做）

- **生成 C 字节一致**不作为目标。两个编译器给 `DefId` 编号的规则不同，
  产物**永远不可能逐字节相同**；对拍的是行为（接受/拒绝、stdout、退出码）与诊断文本。
- `--no-std` 是独立议题。
- 不借这个项目加语言特性。

## 硬性约束

| 规则 | 含义 |
|---|---|
| **行为零变化 / 诊断文本一字不变** | 套件断言精确子串，不得改变（除非用户明确要求行为变化） |
| **不能绕过 / 不硬编码** | 不得用特例表、魔法数字或假实现来过关 |
| **不选最容易通过的办法** | 不得选省事的做法让问题恶化 |
| **一处处手工改** | 禁止盲改正则，逐处手工改 |

（其余仓库级规则见 [`identity-matching-tracking.md`](identity-matching-tracking.md) §2。）

## 信任边界

**测试 harness 永远由冻结的种子编出来，绝不由被测实现编。** 否则被测实现里的
codegen 缺陷会污染本该抓住它的那个东西。这条写进验证链第 0 步。

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

### 布局键不给单态化实例再拼一次实参

`layout_key_for_def_id` 里「带实参的 nominal 一律拼上实参」看着更单射，**否掉**：
单态化实例的 `name` **就是** `make_layout_name` 的产物，实参已经在名字里了，再拼一次
同一组实参数两遍，同一个类型会因到达路径不同拼出两个键，生成 C 直接编不过。
实例带实参时不二次拼接是正确规则，不是漏。

### 不用「碰撞加后缀」处理 C 名冲突

oracle 侧曾有 `uniqueCIdentifier`（冲突就加后缀）与 `detectCIdentifierConflicts`，
**零调用**，是个看着在兜底的死件，已删除。**否掉把这套接上**：改名会把两个 Koral 名字
落到同一个 C 名这件事**藏起来**。要补就补**检出**，不补改名。

## panic 的判定方法

**可达的 panic 不得变成面向合法输入的用户诊断。** 一个 panic 如果能被合法输入触发，
那是缺陷；改成报诊断等于把缺陷藏起来。判定分三类：

1. **流水线不变量** —— 不可由合法输入触发，保留 panic。
2. **可由合法输入触发** —— 缺陷，必须修。
3. **内部 API 误用** —— 保留 panic。

## 技术约束

- **vtable 头字段名是 `_Base`，不是 `base`。** 曾经撞过名，故改名并做过双重不撞证明；
  该字段是**布局用**，任何地方都不得按名字读它。
- **vtable 槽序是父 trait 在前。** sema 与 mono 一个按 LIFO（self 在前）一个按父在前，
  两边不一致会让 `methodIndex` 取错。统一**父在前**。
- **用户不该看见 `struct#N`。** `struct#N` / `enum#N` 是身份拼法（`stable_type_key`
  的 `S#N` / `E#N`），不是显示名。显示路径一律读声明名，id 拼法只是最后兜底。
- **`Fn(..)` 与 `(..) -> ..` 不是缺陷。** `Fn(..)` 是身份键拼法，`(T1, ..) -> R` 是显示拼法，
  分离是有意的。
- **prelude 的边界是包身份**（`package_id_for_kind(.Std())` /
  `Driver.packageID(for:packageName:)` 铸的那一个），不是模块路径拼写。
  根模块是「该包里的单段模块」——结构属性，不是拼写。
  （设计侧的「prelude 是显式绑定」见 [`../design/name-resolution.md`](../design/name-resolution.md)
  「prelude 是一条显式绑定」，此处只记实现边界。）
- **`substitute_type` 不展开名义类型。** 替换是**类型表达式**上的遍历；声明图可以有环
  （一个 nominal 的成员转一圈指回它自己），展开声明就会不返回，还会让一个纯外观的函数
  改到它碰到的每个 nominal。实例化成员的具体化在 monomorphization 里做。

### C 标识符转义：一份规则，两端共用

`sanitize_codegen_identifier` 只把 **Koral 标识符**变成合法 C 标识符。
**已经是 C 符号**的拼写不经过它：

- 声明上写的 `cname`（含 Monomorphizer 铸的 mangled name）—— 原样使用。`cname` 就是最终拼法。
- foreign 声明的**名字本身就是 C 符号** —— 原样使用。
- 编译器自造的名字（`__koral_*` / `__mir_*`）—— 原样使用。

字符类是 **ASCII**（`[A-Za-z0-9_]`），逐 **scalar** 判定：C 标识符只有 ASCII，非 ASCII
要变成 `_`，一个字素簇产生几个下划线两端必须一致。关键字转义前缀 `_k_` 只挡**独立**
标识符撞关键字，所以组合成名 `Type_method` 之后两端都削一次。

### 布局键：一份实现，在类型上单射

只有 `CompilerContext.get_layout_key`（`mono/mono_types.koral` 曾有一份拼写不同的副本，
已删）。布局键给单态化的 C 实体命名，也当类型相等谓词用，所以必须**单射**——两个类型
共用一个键就是一个 C 符号。函数类型带签名**且带参数个数**（裸的 `Fn_<params>_<ret>`
拼接是二义的：`() -> R` 与 `(R) -> I` 都拼成 `Fn_R_I`），借用不并进拥有
（`BR_` / `MBR_` 对 `R_` / `MR_`）。

## 角色分工

- `compiler/` —— **主实现**，正在开发的那个。
- `compiler-reference/` —— **冻结的 Swift 编译器**：参考预言机、构建种子、备份。
  **冻结不删**。它不是开发目标。

详见 [`developer-guide.md`](developer-guide.md) "Compiler roles" 与
[`../../compiler-reference/README.md`](../../compiler-reference/README.md)。

## 开放缺口

- **`sanitize` 不是单射。** `a-b` 与 `a_b` 都变成 `a_b`，两个 Koral 名字可能落到同一个
  C 名。两端都既不检出也不改名，会以链接期重复符号的形式暴露。要补就得两端同加**检出**
  （改名会把冲突藏起来，见上文被否掉的方案）。

## 参考

- 验证链的权威定义：[`../../scripts/verify.sh`](../../scripts/verify.sh)。
- 差分预言机契约：[`../../tests/README.md`](../../tests/README.md)。
- 身份匹配改造记录：[`identity-matching-tracking.md`](identity-matching-tracking.md)。

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

1. **C 标识符转义仍未收敛成一份规则。** 已修：C89 关键字表补上 `enum`（原先 `union`
   写了两遍、`enum` 没有）、无 `cname` 的 foreign global 落到 sanitizer、pattern 里
   「Unexpected token」的措辞与参考编译器对齐。**没修**，因为不能只删豁免就完事：
   - koralc 的 `escape_codegen_keyword` 有一条参考实现没有的豁免（`__koral_` / `__mir_`
     前缀直通）。它是**载荷**：`file_private let foreign __koral_argc()` 这类运行时符号
     在**调用点**会走 sanitizer，去掉豁免会转义成 `__k___koral_argc`，链接直接失败
     （实测 600+ 用例全红）。正确做法是让 foreign 与生成名绕过 sanitizer。
   - `normalize_codegen_lookup_name` 里的 `_k__k__` 削三字符，正是「先转义再撤销」的补丁。
   - 字符类两边不同（ASCII vs Unicode 的 `isLetter`/`isNumber`）；`layout_key`、
     mono 的 mangled name 等若干处**并不经过** sanitizer，所以同一源码两边 C 名不同
     （实测 `let union()` → koralc `Kw2_union`、参考 `Kw2__k_union`）。
   - oracle 有 `uniqueCIdentifier` 的碰撞加后缀规则，koralc 没有对应物。
2. **`layout_key` 有两套命名，且函数类型会撞 C 符号。** `context.get_layout_key` 把
   `FunctionType` 一律塌成 `"Fn"`，于是 `Box[Func(Int) Int]` 与 `Box[Func(Bool) Void]`
   两个实例共用一个 C 名。`mono/mono_types.koral` 的 `layout_key` 保留签名，两者对
   「借用是否等同拥有」也不一致（前者 `R_`/`MR_` 塌成一类，后者 `bref_`/`ref_` 分开）。
   oracle 同样塌成 `"Fn"`，所以修它要两边同改并配用例。
3. **裸名索引仍有一部分在做解析。** 已把 Swift 侧四处**书写处**的裸查（工具方法归属、
   泛型 bound 的 trait、conformance 反查实参、名字→owner）改成 `visibleTraitInfo`——
   裸索引跨模块 last-wins，回答不了「哪个 `Tag`」。**剩下**：`GivenLocality` 的显示路径、
   `TypeCheckerTypeResolution` 的无 `DefId` 兜底（书写边界，合法），以及 koralc 侧
   mono 里几处经 `generic_templates.traits.get(name)` 的裸查——那些要走
   `resolve_trait_name` 的候选键序列，不是直接换键。
4. **`mutable name Type` / `name Type` 绑 trait object 取到野指针。** 两个编译器都编译
   通过、都打印垃圾值（`bound 4306866680`），两种绑定形式都一样。设计说这类模式
   「operate on the erased trait-object subject; they do not auto-deref to the concrete
   value type」，而实现把绑定标成了具体类型 `Box`，于是按 `Box` 去调方法、指针是擦除后的。
   要先定：绑定应当是擦除后的 subject（那就该标成 trait object 类型），还是具体值
   （那 lowering 就该给出具体 payload）。**这是设计裁定，不是纯代码缺陷。**
5. **`List.sort_by` 在可变 newtype 包装类型上栈溢出**（见
   [`module-design-implementation.md`](module-design-implementation.md) §11）。
6. **`.as(Trait)` 路径上的几个签名仍以名字为入口**（书写处解析，合法，但签名是 name-first）。

已清：prelude 边界从「模块路径 == `["Std"]`」改成**包身份**（`package_id_for_kind(.Std())`
/ `Driver.packageID(for:packageName:)` 铸的那一个），`name_collector` 的同名判定改走同一个
谓词。根模块仍是「该包里的单段模块」——这是结构属性，不是拼写。

## 参考

- 验证链的权威定义：[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)。
- 差分预言机契约：[`../../tests/README.md`](../../tests/README.md)。
- 身份匹配改造记录：[`identity-matching-tracking.md`](identity-matching-tracking.md)。

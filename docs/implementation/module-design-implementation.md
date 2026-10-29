# `../design/module-design.md` —— 实施记录

> **状态**：形态层重做（2026-10-24）、方法面与跨包合并收口、孤儿文件归属（2026-10-25）已落地，看护齐全。
> 设计正本是 [`../design/module-design.md`](../design/module-design.md)。
> 验证走 [`developer-guide.md`](developer-guide.md) 的验证链。

## 0. 范围裁定

| 块 | 状态 |
|---|---|
| 操作由括号定（裸=合并 / 括号=导入） | 已落地 |
| 清单六形态（`{ }` / `{ a, b }` / `{ a as b }` / `{ ... }` / `{ a as b, ... }` / `{ !a, !b, ... }`） | 已落地 |
| 「文件合并」→「模块合并」（概念统一，行为等价） | 已落地 |
| 未登记本地模块走相对路径（导入 + 合并） | 已落地 |
| 模块归属不变量（一文件属一模块） | 已落地 |
| 全仓源码迁移（432 处 bare import → `{ ... }`） | 已落地 |
| **方法面规则**（inherent 跟值走 / trait 跟 trait 名走，Rust 版） | **已落地**（2026-10-25） |
| **模块身份 =（`source`，入口位置）** | **已落地**（2026-10-29）—— 符号前缀 = 入口相对包根的路径段 + 来源哈希 |
| **`modules` 降为对外命名表** | **未做**（本地模块不登记已可，manifest 仍是清单） |
| **孤儿文件报错** | **已移交给 `koral lint`**（2026-10-25）——不是编译条件，见 §8 |

## 1. 形态的 AST 承载

`UsingDecl(specifier, items, import_all, span)` + `UsingModuleItem(name, alias, excluded)`：

- `items = None` → 裸形式（合并）
- `items = Some(list)` → 括号形式；`import_all` 是 `...` 基集的记号
- `{ }` = `Some([])` + `import_all = false`（惰性，什么都不带）
- `{ a as b, ... }` = `Some([a as b])` + `import_all = true`
- `{ !a, ... }` = `Some([!a])` + `import_all = true`

`UsingImportList(items, import_all)` 是解析器给调用方的成对答案，不是一个节点。

## 2. 过滤落在哪

**批导入的过滤挂在 `ImportEdge.filter` 上**，不是展开成符号边。三条读它：

| 读处 | 拦什么 |
|---|---|
| `candidate_keys` 第 3 层（模板名解析） | 被改名/排除的拼写不从批边落下来 |
| `get_import_kind`（可见性） | 同上 |
| `imported_type_entry`（类型表） | 同上 |
| 批导入的 trait 绑定 | 同上 |

**改名同时发一条符号边**（`symbol = 新名`，`original = 原名`），于是新拼写走普通的
符号导入层，不需要批边替它改写。这比「批边带改名表」简单：改名的解析路径与
`{ a as b }` 完全同一条。

**`get_import_kind` 里 `si.original_symbol == name` 那半个匹配是错的**，已删。
它把改名前的拼写也放行了——`{ env as os_env, ... }` 会同时拿到 `env` 和 `os_env`。
本地拼写才是准入依据。

## 3. 裸形式合并为什么不能先载目标

`resolve_module_import` 会顺手 `resolve_module_spec` 把目标当独立模块载入。裸形式
是合并，那一步会让目标的文件先被它自己的模块认领，合并时再认领一次就撞归属不变量。
所以加了 `load Bool`：**合并路径不载入**，由 `merge_module_into` 直接把入口文件并进
当前模块（`resolve_file` 会递归走完目标自己的合并闭包）。

## 4. 归属不变量的落点

`resolve_file` 开头查 `claimed_files: Dict[文件, 模块键]`。第二次认领报错。

**诊断走 `Error: ` 信封、不带位置前缀**——两端都这么拼。原因：Swift 的模块错误
经过 `description` 之外的通道时会挂上环境文件名（见
[`identity-matching-tracking.md`](identity-matching-tracking.md) 与
`SemanticErrorContext.currentFileName` 的老坑），而 koralc 的 `ModuleError.render`
带的是另一个文件。带前缀就必然漂移；不带就逐字一致。

## 5. 边界（明确不做）

- **`hide` / `except` 关键字**——为低频形态占一个关键字不值。排除用 `!`，
  它在 Koral 没有第二个岗位。
- **`{ a, !b, ... }` 混写**——正负不得同表。`!` 只在带 `...` 的清单里出现。
- **目录推断模块树**——模块边界永远由入口文件指明（`name-resolution.md` 硬规则）。
- **`use Trait as _`（不绑名、只带方法）**——Rust 有这个形态，Koral **不新增**。
  `as _` 已被否（`_` 是模式通配符，公理 6 的单一拼写）。要方法不想要名字就别名到一个
  不用的拼写，或用 `{ !X, ... }`。六形态不扩。
- **同类型同名方法不学 Rust 的 inherent 优先**——`MethodTable` 同槽即歧义，保持。
  Rust 那个 `&self` 探测排在 `&mut self` 前面、结果调到 trait 那个的怪例，Koral 不要。

## 6. 看护

| 看护 | 盯什么 |
|---|---|
| `using_import_all_form_test` | `{ ... }` |
| `using_exclude_form_test` / `using_exclude_drops_name_error` | `{ !a, ... }` 及它确实丢名字 |
| `using_rename_form_test` / `using_rename_hides_original_error` | `{ a as b, ... }` 及原名不落下 |
| `using_empty_import_list_placeholder_test` | `{ }` 合法且惰性 |
| `using_exclude_needs_ellipsis_error` / `using_exclude_renamed_error` / `using_mixed_polarity_error` / `using_rename_without_alias_error` | `!` 的四条约束 |
| `using_local_module_import_test` / `using_local_module_merge_form_test` | 本地路径的导入/合并 |
| `using_bare_form_merges_module_test` | 已登记模块的裸形式合并 |
| `using_ownership_invariant_error` | 一文件属一模块 |
| `using_batch_with_named_import_error` | `...` 收尾清单 |

koralfmt 侧：六形态各一条往返断言——**形态是载荷**，逐字不丢。
`using_empty_import_list_error` 与 `using_file_merge_*_list_error` 已随规则翻转改名。

方法面（§9）12 条：`method_face_trait_in_scope_test` / `method_face_missing_trait_error` /
`method_face_unrelated_name_error` / `method_face_inert_import_error` /
`method_face_batch_import_test` / `method_face_alias_keeps_trait_test` /
`method_face_exclude_drops_trait_error` / `method_face_inherent_no_import_test` /
`method_face_prelude_trait_test` / `method_face_bound_brings_methods_test` /
`method_face_merge_brings_methods_test` / `method_face_subtrait_no_supertrait_error`。

## 7. 被否掉的实现写法 / 未做项的理由

- **把 `{ a as b, ... }` 的改名展开成批边的改名表。** 否掉：改名的解析路径会变成
  第二条，与 `{ a as b }` 不同。改名一律走符号边。
- **方法面按「导入了模块就放开该模块全部 `given`」。** 这是旧现状，已被 §9 换掉。
  它的真实机制是**模块可达性**——不导入则整个模块不载入，`given` 根本不注册；
  导入任意一个名字（`{ env }`）就把该模块的全部 `given` 带进来了。
- **在 `resolve_extension_template_signature` 上加一道模板粒度的名字可见性门。**
  **试过，已回退。** 判据写成「点名 trait，或点名类型且该 `given` 与类型同模块」，
  结果把 `List.push`、`Option.is_none` 一起挡掉了——一个模板可能给多个类型供方法。
  正解是**逐个方法**记来源（§9 的 `method_traits`），不是查找处加个 if。
- **「同模块的 `given X as T` 白送」。** 否掉，理由见设计正本「替代方案」——
  Rust 里 `impl Read for File` 就在 `File` 的文件里，`f.read()` 照样要 `use std::io::Read;`。
- **按模板（`conformance_trait_def_id`）一刀切判方法面。** 不够：`given X as Leaf` 经
  `Leaf` 的**扁平方法表**能摸到超 trait `Root` 的方法，按 `Leaf` 判就把它放行了——
  而命名子 trait 不该打开超 trait（Rust：`use a::Sub;` 后 `x.b()` 仍 E0599）。
  改成**接收者方法表记的来源说了算**，无记录时才退回 conformance 自己的 trait。
- **把孤儿文件检查留在编译器里。** 否掉，2026-10-25 移交 `koral lint`。
  它不改产物，回答的是「这份仓库里有没有我以为进了程序、其实没进的东西」——
  仓库的问题不是程序的问题。留在编译器里的代价是两个：两端各抄一份**非语言语义**
  的代码进差分甲骨文；以及 `koralc` 被迫对闭包之外的文件有意见。
- **「与已认领文件同目录」的收窄。** 否掉。它抓「你在编的目录里多了个杂散文件」，
  放过**整个忘掉的目录**——而「加了个 `helpers/` 模块、忘了写那行 `using`」才是
  最常见的漏。改成铺满包根 + manifest `exclude` 显式排夹具。
  `access_checker.koral` 上次之所以被抓到，纯粹因为它凑巧躺在正在编的目录里。
- **模块身份 =（`source`，入口位置）已落地（2026-10-29）。** 派生符号键 =
  `入口路径段_<16 hex 哈希>`，哈希取（`std:`+manifest version / `root:`+包名 /
  `source:`+依赖 source / `single:`，入口相对包根的归一化路径）；改依赖 key
  不再改任何 ABI 符号，同干名不同目录的本地模块不再合并。

## 8. 孤儿文件归谁（2026-10-25）

**切法**：`koralc` 管「这个程序良构吗」，`koral` 管「这份工程良构吗」。
孤儿文件在目标闭包**之外**，按定义就不是要编译的东西，编译器不该有意见。

| | 落点 |
|---|---|
| 扫描 | `toolchain/koral/project_lint.koral`（模块 `koral/lint`，**不带 CLI 类型**，测试可直接调） |
| 命令 | `koral lint [<dir>]`；`koral build` / `koral check` 前置同一条 |
| 排除 | manifest `exclude: ["test/cases"]`——包根相对，目录覆盖其下全部 |
| 看护 | `toolchain/koral/test_lint.koral`（9 条），`verify.sh` 对 7 个包各跑一次 |

**`project_lint` 为什么是独立模块**：它若并进 `koral.koral` 的模块，测试要 import 它就
会把 CLI 的 `main` 一起拖进来，`__koral_user_main` 撞签名。分出去之后测试只 `using
"koral/lint" { … }`。

**`load_config` 不再拒 `package: "std"`**：那条是**选名字**的规则，不是**读 manifest** 的
规则——`koral lint std` 得能在真的 std 包上跑。改到 `is_valid_project_name`（`koral init`
那条路）；构建时 koralc 仍然拒。

**顺带删掉**：`tests/compiler-cases/using_orphan_source_error`（驱动的是编译器侧的检查）。

## 9. 方法面怎么落的（2026-10-25）

**规则**是 Rust 的：inherent 方法跟着值走、零准入；trait 方法跟着 trait 名走；
点名类型不带 trait 方法。设计正本 §3.4 是判据，本节是落点。

**来源记在方法表上**（`MethodTable.method_traits: Dict[MethodOwner, Dict[String, List[DefId]]]`），
不是模板上。`register_conformance_method_signatures_for_concrete_type` 已经分得清
`mark_inherent`（`given X { }` / `given intrinsic X { }`）与 `trait_def_id`（`given X as T`、
工具块物化），顺着它记一条「哪个 trait 提供的」即可。**一个方法可以被多个 trait 提供，
任一在作用域内即放行。**

**门只问一句**：`trait_in_scope(trait_def_id)`——本文件能不能**够到这个 trait 声明**。
它故意不是 `can_access_directly`：那问的是「能不能写这个拼写」，而 `{ T as A }` 让
`T` 不可写却仍让方法面开着（Rust `use Read as R;` 仍允许 `f.read()`）。

**超 trait 不随行于具体接收者**。`resolve_conformance_method_signature` 从 `Leaf` 的
扁平方法表能拿到 `Root` 的 `r`，若按 `Leaf` 判就把 `Root` 的面打开了。改成：
**接收者方法表有记录就按记录判**，无记录才退回 conformance 的 trait。泛型界那条路
（`.GenericParameter`）本来就早退、不走门——界自己带方法（含超 trait）。

**顺手修的一个真 bug**：Swift 侧 `DefIdMap.nextId` 从 `0` 起，而 `DefId.invalid == 0`——
**第一个分配的 DefId 就是 invalid**。本地模块先于 std 处理时，它的第一个 trait 拿到
`defId == .invalid`，conformance 就没法按声明对齐。koralc 一直从 `1` 起，已对齐。

**两端同一处形状不同**：koralc 的门在 `resolve_method_signature_unchecked` 的各条返回路上；
Swift 的 `extensionMethods` 读点分散，关键一处在 `inferMethodOnType`（它排在
`lookupDeclaredMethod` **之前**，不走门就绕过去了）。

## 10. 2026-10-25 跨包合并收口

形态层重做时「合并只在包内」漏了实现——裸形态与路径形态都会把**别的包的**目标并进来。
后果实测是拼运气：`using "std/hex";` 能跑（目标恰好不碰原包私有），`using "std/text";`
死在 `package_private String.data`（旧拼写，今 `protected`）上，且报错指向 std 源码行号。根因是合并让被并文件
换上本包身份，可见性按新包判定。

- **裁定**：合并目标必须是本包模块/文件。裸形态按 `package_id` 判同包；路径形态按
  最长包根前缀判归属（`src`/`src2` 兄弟目录按段边界，不吃裸前缀）。裸文件编译无所属包，
  目标是已登记模块时同样拒绝——两侧判定在 `merge_module_into` / `mergeModule` 与
  `resolve_file_merge` / `resolveFileMerge` 各一道。
- **诊断**：`ModuleError.CrossPackageMerge`，两端逐字相同，指路 `{ … }` 导入。
- **同包合并不受影响**：按名合并本包注册模块（`using_bare_form_merges_module_test`）与
  路径合并本地文件照常。
- 看护：`using_cross_package_merge_error`；跨包路径形态在包布局探针里验证
  （dep 路径依赖被拒、同包 helper 放行）。

验证：seed 自检与主门各 826/826（2026-10-25），跨包诊断两端逐字相同。

## 11. 验证

`scripts/verify.sh` 全链 **ALL GREEN**（2026-10-25，合并 origin/master 后复验）：
seed 自检、主门、stage2、差分门各 **838/838**（823 + 方法面 12 + 跨包/and-then 3，
减去随孤儿检查搬家删除的 `using_orphan_source_error`），`FIXED POINT`，`dangling=0`；
koralfmt 225/225，corpus gate 222 文件 0 失败；样本三个全部构建通过；
doc gen 自检通过、14 个模块的 API 文档是新的。

**project layout**：`koral/lint` 9/9，`koral lint` 对 7 个包各跑一遍全干净。
差分门默认开诊断比对，**两端错误面逐字相同**——方法面的诊断
（`Trait 'T' provides it but is not in scope; …`）与跨包合并的
`CrossPackageMerge` 都在比对范围内。孤儿检查不进差分，它不是语言语义。

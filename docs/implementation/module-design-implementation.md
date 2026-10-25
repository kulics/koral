# `../design/module-design.md` —— 实施记录

> **状态**：形态层重做（2026-10-24）已在两端落地，看护齐全。
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
| **方法面规则**（`given` 跟被点名的东西走） | **未做** |
| **模块身份 =（`source`，入口位置）** | **未做** |
| **`modules` 降为对外命名表** | **未做**（本地模块不登记已可，manifest 仍是清单） |
| **孤儿文件报错**（不被任何模块闭包覆盖） | **未做** |

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
- **方法面收紧**——见 §7，现在是模块可达性决定，不是命名决定。

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

## 7. 被否掉的实现写法 / 未做项的理由

- **把 `{ a as b, ... }` 的改名展开成批边的改名表。** 否掉：改名的解析路径会变成
  第二条，与 `{ a as b }` 不同。改名一律走符号边。
- **方法面按「导入了模块就放开该模块全部 `given`」。** 这是现状，**不是设计想要的**。
  实测发现它的真实机制是**模块可达性**——不导入则整个模块不载入，`given` 根本不注册；
  导入任意一个名字（`{ env }`）就把该模块的全部 `given` 带进来了。设计 §3.4 要的是
  「跟被点名的东西走」。
- **在 `resolve_extension_template_signature` 上加一道模板粒度的名字可见性门。**
  **试过，已回退。** 判据写成「点名 trait，或点名类型且该 `given` 与类型同模块」，
  结果把 `List.push`、`Option.is_none` 一起挡掉了——`given` 的方法面不能按模板一刀切：
  一个模板可能给多个类型供方法，而「谁解锁它」是**逐个方法**的事（inherent 方法跟类型走、
  trait 方法跟 trait 走、跨模块扩展只跟 trait 走）。要做得给方法表记来源，
  那是方法表的键结构改动，不是查找处加个 if。
  **影响面已量过**：全仓 31 个调用非 prelude trait 方法的文件全部走导入全部，
  收紧本身是 0 破坏；难点在判定的粒度，不在兼容性。
- **孤儿文件报错。** 需要「包内源文件全集」与「模块闭包全集」求差，是一个包级扫描。
  归属不变量的正向一半（一文件不属两模块）已落；反向一半未做。
- **模块身份 =（`source`，入口位置）。** 那会改 codegen 符号前缀，属 ABI 变更。
  本地未登记模块的暂用入口文件名作身份，与设计 §5.3.1 不一致，**是有意留的偏差**。

## 8. 验证

`scripts/verify.sh` 全链 **ALL GREEN**（2026-10-24）：seed 自检、主门、stage2、
差分门各 823/823，`FIXED POINT`，`dangling=0`；koralfmt 225/225，corpus gate
220 文件 0 失败；样本三个全部构建通过。差分门默认开诊断比对，两端错误面逐字相同。

## 9. 2026-10-25 跨包合并收口

形态层重做时「合并只在包内」漏了实现——裸形态与路径形态都会把**别的包的**目标并进来。
后果实测是拼运气：`using "std/hex";` 能跑（目标恰好不碰原包私有），`using "std/text";`
死在 `package_private String.data` 上，且报错指向 std 源码行号。根因是合并让被并文件
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

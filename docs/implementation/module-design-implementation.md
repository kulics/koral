# `docs/design/module-design.md` 实施计划与状态

状态：进行中（2026-10-05）

本文是 [module-design.md](../design/module-design.md) 的**实施记录**：范围裁定、分阶段顺序、每阶段的验收判据与状态。
设计本身看 module-design.md；这里只记「怎么落地、落到哪了」。

---

## 0. 范围裁定

| 章节 | 内容 | 本期 |
| --- | --- | --- |
| §1 | package / module 概念、稳定身份 | ✅ 做 |
| §2 | 命名（单段包名、`/` 子路径、边界唯一） | ✅ 做 |
| §3 | 语法（`using "X"` / `using "X" { … }`、文件合并） | ✅ 做 |
| §4 | 解析（切在第一个 `/`、包内名查找） | ✅ 做 |
| §5.1–5.4 | manifest 字段、`modules` key、`dependencies`、模块图从 `using` 派生 | ✅ 做 |
| §6 | 示例 | ✅ 做（作为迁移后的形态核对） |
| §7 | 错误条件 1–22 | ✅ 做 |
| §8 | 迁移（含迁移提示文案） | ✅ 做 |
| §9–§10 | 对照、待定项 | 记录，不实现 |
| §5.5 | `koral.lock` | ❌ 推迟 |
| §11 | 包管理机制（抓取、版本裁决、`koral update`） | ❌ 推迟 |

**推迟的两块是包管理器层，不是模块设计。** 设计文档自己把 §11.4 的 dev-dependencies / workspace /
feature / 版本裁决标成「本次不做」，§5.5 的 lockfile 依赖「抓取」这一尚未存在的能力。
本期把**模块与导入**拉上正轨；包管理器另开任务。

---

## 1. 为什么分三阶段

迁移面（§8）横跨：两个编译器的 parser / manifest / resolver、30 个 `koral.json`、
573 处 `using`、toolchain、测试用例、三份文档。一次性落地无法验证——出错时的草堆太大。

「整链一起改再测」约束的是**接口**：改契约时两侧一起改，不留半条链。它不禁止把一个大工程
分成可验证的阶段。每阶段结束必须走完固定验证链（见 §4），不允许「先记着，最后一起测」。

阶段划分的依据是**耦合度**：

- **身份模型**（manifest + 解析）与**语法**（`using` 写法）是两件事。身份是「正轨」本身，
  语法只是它的拼写。身份先落地，语法迁移就变成纯词法替换；反过来则要先写一层临时映射。
- **错误条件**依赖前两者都定型——每条错误都在说「这个拼写在这个身份模型下不成立」。

---

## 2. 阶段

### 阶段 A — 模块身份与 manifest（§1、§4、§5.1–5.4）

**目标**：模块的身份是 `(package, 子路径)`，源码写全名，manifest 声明包内名。

| 改动 | 现状 | 目标 |
| --- | --- | --- |
| 包名字段 | `name: "Std"` | `package: "std"` |
| 默认构建目标 | 顶层 `entry` | 删——默认 = 主模块（`modules["."]`） |
| `modules` key | 全局唯一名 `std::io` | **包内名** `io`、`.` |
| `requires` | 显式列出模块依赖 | **删**——图从 `using` 派生（§5.4） |
| `dependencies` | `{ name, git, version, module_aliases }` | `{ source, version }`，**key 即源码名** |
| `module_aliases` | 把依赖的模块改名 | **删**——改名就是换 key（§5.3） |
| 解析 | 全局平铺查表 | 切在第一段 → head 是包名 → 查该包的包内名 |

连带：模块图从 `using` 派生 ⇒ 无环检查、可达性、构建排序、`links` 传递全部改从 `using` 边计算
（`Driver` 里 `collectManifestRequiredModuleNames` 的 `requires` 扩张随之消失）。

**解析模型**：`LoadedPackage` 的身份是 `source`（root 用 `package`，std 用 `"std"`），
`self_name` 是它自己源码里的自称。名字解析是**按包上下文**的（§4「每个包用自己的表解析自己的源码」）：
编译某个包的文件时，用那个包自己的 `package` + 它自己的 `dependencies` key + `std`。
所以 `dep_utils` 自己写 `using "dep_utils/…"`，消费方写 `using "game_utils/…"`，落到同一个包。
`path_segments`（符号限定用）取**根包视角的全名**，与今天一致；§10.4 的 ABI 前缀问题仍待定。

**状态：✅ 完成**（2026-10-05，验证链全绿，见 §5）

### 阶段 B — 语法统一（§2、§3、§8）

**目标**：`using` 只有一种写法，specifier 是字符串。

```koral
using "std/io";                     // 全部可见成员
using "std/io" { Reader, Writer };  // 过滤
using "std/io" { Reader as Io };    // 逐项别名
using "./helpers.koral";            // 文件合并
```

- 分类只看路径形状（§3.1）：`./` / `../` 开头 ⇒ 文件合并；否则模块导入
- 文件合并必须以 `.koral` 结尾，且不得与 `{ }` 连用
- `{ }` 省略即全部；`{ .. }` 取消
- 裸名文件合并（`using "utils";`）取消——它落进模块查询，报错并给迁移提示（§8）

**状态：✅ 完成**（2026-10-05，验证链全绿）

### 阶段 C — 错误条件与文档（§7）

24 条错误条件按 §7 逐条落地，含 §8 的迁移提示文案。同步 `grammar.bnf` / `document.md` / `document-zh.md`。

**状态：✅ 完成**（2026-10-05）——§7.23/24（lockfile / 哈希）随 §5.5 一起推迟

---

## 3. 明确不做（本期）

| 项 | 理由 |
| --- | --- |
| `koral.lock` / 抓取 / `koral update` | 包管理器层，依赖尚不存在的抓取能力 |
| 传递依赖版本裁决（§10.2） | 同上 |
| registry（§10.3） | 产品决策，不是命名模型的前提 |
| codegen 标识符前缀（§10.4） | 需在 `source` 哈希与 `package` 之间权衡，独立任务 |
| `as not X` 通用化、operator 降级表、推断特判 | 另一计划（约束表示重构）的边界 |

---

## 4. 验收判据

每阶段结束必须**全绿**，顺序不可换：

1. 种子自检 2. 种子→stage1 3. stage1 全量（主闸门）
4. 自举两轮 + 不动点（emit-c + clang）+ 悬空扫描 = 0
5. stage2 全量 6. oracle 全同（含诊断）

> 步骤措辞于 2026-10-06 随角色重组更新（`compiler/` 为主实现，Swift 冻结为种子与预言机）；
> 链的顺序与判据不变。

外加阶段判据：

- **A**：所有 `koral.json` 无 `requires` / `module_aliases` / `entry` / `name`；
  `modules` key 不含 `::`；`grep -rn 'module_aliases\|"requires"'` 为 0（测试用例的错误形态除外）
- **B**：源码里不再有未加引号的 `using x::y`；不再有 `{ .. }`；
  `grep -rnE 'using[[:space:]]+[A-Za-z_]' --include='*.koral'` 只剩注释
- **C**：§7 的 24 条各有用例（含迁移提示的两条）；三份文档与语法一致

---

## 5. 状态

| 阶段 | 状态 | 备注 |
| --- | --- | --- |
| A | ✅ 完成 | 模块身份与 manifest |
| B | ✅ 完成 | `using` 语法统一，573 处迁移 |
| C | ✅ 完成 | §7 错误条件 + 三份文档 + 设计文档补 prelude（§5.4.1） |

**最终验证**（2026-10-05）：

```
1) Swift 全量          571/571
2) host → stage1       ok
3) stage1 全量         571/571
4) 自举两轮 + 不动点    FIXED POINT，悬空 0
5) stage2 全量         571/571
6) 行为对拍（含诊断）   571/571
```

### §7 错误条件落地情况

| # | 条件 | 状态 |
| --- | --- | --- |
| 1 | 文件合并未以 `.koral` 结尾 | ✅ parser |
| 2 | 目标文件不存在 | ✅ resolver |
| 3 | 文件合并与 `{ }` 连用 | ✅ parser |
| 4 | `{ }` 出现但为空 | ✅ parser |
| 5 | 模块全名不合法（空段、`.`、`..`、非法字符）+ `using ".";` 提示 | ✅ parser |
| 6 | 未知包名 + 迁移提示 | ✅ resolver |
| 7 | 模块不存在 | ✅ resolver |
| 8 | 无主模块 | ✅ resolver |
| 9 | 符号冲突 | ✅ 见 §7.4 / §7.5 |
| 10 | 同一模块在同一文件内 `using` 多次 | ✅ resolver（本期新增） |
| 11 | `using` 未位于文件顶部 | ✅ parser（原有） |
| 12 | 模块图有环 | ✅ resolver（本期改为报环，不再静默跳过） |
| 13 | 包名不是合法标识符 | ✅ |
| 14 | `modules` key 既不是 `.` 也不是合法子路径 | ✅ |
| 15 | ~~同一模块 key 重复~~ | ⏸ 设计文档已改：`modules` 键唯一性结构性保证；`io/` 是非法 key 不是别名 |
| 16 | `entry` 被两个模块声明 / 不在包根内 / 不存在 | ✅ |
| 17 | 同一源码名被两个依赖声明 | ⏸ 设计文档已改：JSON 键唯一性结构性保证，不是可检查条件 |
| 18 | 一个 `source` 被两个 key 声明 | ✅ |
| 19 | `dependencies` key == `package` | ✅ |
| 20 | `dependencies` key 或 `package` 占用 `std` | ✅ |
| 21 | `dependencies` 缺 `source`/`version` / 格式非法 | ✅ |
| 22 | 文件合并成环 | ✅ resolver（本期新增） |
| 23–24 | lockfile / 哈希 | ⏸ 随 §5.5 推迟 |

---

## 7. 复核（2026-10-05）

按设计文档逐条取证，发现 **7 处问题**。6 处已修并补用例钉住，1 处记为未实现。

### 7.1 已修

| 问题 | 条款 | 用例 |
| --- | --- | --- |
| `entry` 逃出包根静默通过 | §7.16 | `manifest_entry_outside_package_root_error` |
| `package: "std"`（root）不拒绝 | §7.20 | `manifest_reserved_std_name_error` |
| 一个 `source` 两个 key 的报错把同一个 key 报两遍，且顺序随哈希迭代 | §4 / §7.18 | `manifest_duplicate_dependency_source_error` |
| 顶层 `links` 被静默忽略 | §5.1 | `manifest_top_level_links_error` |
| 模块全名空段（`a//b`）不报错 | §7.5 | `using_empty_segment_module_name_error` |
| （连带）bootstrap 的 `normalize()` 不折叠 `..`，与 Swift 行为不一致 | — | 由上列用例覆盖 |

### 7.4 §7.9 同名冲突：已实现（读取式校验）

**条款**：「同名冲突报错，用 `as` 消歧——import-all 与本模块定义重名时无法消歧，只能改成显式列表」。

先前记为未实现。**结论是该实现，不该改预期**——规则本身是对的，试错暴露的是接线方式不对：

1. 「导入的名字撞上任何已绑定名字」→ **81 个用例失败**。同一模块的多个文件各自
   `using "std";` 是同一个符号，不是冲突（§3.3.4：`using` 按文件不按模块）。
2. 收紧为「撞上**不同声明**才算」→ 精确了，但不报了。模块级声明会进**裸名索引**
   （跨模块 last-wins），`lookup` 恒等于被导入符号自身。
3. 改查「本模块自己的声明」→ 需要 `currentModulePath` 正确，为此临时改全局状态 →
   **75 个用例失败**；换成显式按模块路径查询后仍在同一处炸。

**做对的形态**：**只读校验**——报告，但不改变哪个绑定获胜，也不碰注册时机。
`Scope.lookupDeclared(inModule:name:)`（值）与 `lookupDeclaredType(inModule:name:)`（类型）
绕开裸名索引，直接问「本模块是否声明了这个名字」。三版炸掉的原因都是顺手改了名字注册。

**连带查出并修掉的两处既有缺陷**：

- **bootstrap 的 `reserve_std_type_name_if_needed` 范围过大**。它保留**所有 std 类型名**，
  于是用户类型 `Duration` 在 bootstrap 报 `Duplicate definition`、Swift 不报。
  真实规则窄得多：只有 **std 的泛型模板名**被保留（`Option[T]`、`List[T]`…）——
  因为编译器按名字构造这些 lang item（`genericEnumType(template: "Option", …)`）。
  非泛型的 `Duration` 可以同名，两个用户模块也可以各自声明 `Box[T]`（`cross_module_same_name_type_test` 钉着）。
  已改为只保留 std 泛型模板名，三类探针（`Option` / `Box` / `Duration`）两侧一致。
- **导入名冲突诊断在 bootstrap 侧被丢弃**。name pass 成功时其 diagnostics 不进最终 collector，
  只有失败路径才带回——于是「恰好是最该报的场合」不报。已合并进最终 collector。

用例：`using_import_name_collision_error.koral`（两种导入形态各一条，文案与提示都钉住）。

### 7.5 §7.9 的两处漏网（二次复核）

上面那版只钉住了「导入 vs **本模块**声明」。**「导入 vs 导入」根本没实现**，
而两侧规则还各错一头——写探针对打才现形：

| 场景 | Swift | bootstrap（改前） |
|---|---|---|
| 两个模块的同名声明，同一文件都导入 | 报 | **不报** |
| 目标名字是 `module_private`（根本导不进来） | 不报 | **报** |
| 目标 `public` + 本模块同名 | 报 | 报 ✓ |

根因是同一件事：bootstrap 把「导入实际带进来的东西」近似成「目标模块**声明**了什么」。
于是既漏掉了同文件里另一个导入已经占用这个拼写，又把根本不可导入的名字算成了冲突。

改后规则与 Swift 同构，两半各管一件事：

- **可见性**：`decl_importable` —— `public` 恒可导入，`package_private` 只在同包内，
  两个 private 层级永不可导。导不进来的名字压根不在这个文件的作用域里，
  它跟谁都不冲突；报它等于让读者为一条自己无法遵守的规则背锅。
- **拼写所有权**：`record_import_binding` —— 一个拼写只有一个 owner，记作
  （目标模块，原名）。第二个**不同**的 owner 才是冲突；同一个声明再次到达不算
  （§3.3.4：`using` 按文件不按模块，同一模块多个文件各自 `using "std";` 是同一个声明）。
  本模块的声明也占拼写，且它自己的可见性不影响这件事。

身份用（目标模块，原名）而不是 DefId：一个模块对每个拼写至多声明一次，
两者一一对应。顺序沿用「先批量后显式」，与 Swift 注册顺序一致，因而报在同一行
`using` 上；批量那侧按名字排序，类型名恒大写、值名恒小写（解析器强制），
所以排序结果恰好等于 Swift「先类型后值」的次序。

**另一处诊断分歧**：`Known package names: `（Swift 空串）vs `... <none>`（bootstrap）。
只在已知名单为空时触发，语料里 `std` 总在名单中，所以 577/577 逐字对拍也看不见。
bootstrap 的 `join_sorted` 注释写明「空则 `<none>`，因为文本要跨编译器比对」，
而 Swift 同族另两条消息（`declared modules:`）本来就用 `<none>`——
是 Swift 自己不一致。已按 `<none>` 对齐。

用例：`using_import_vs_import_collision_error`（导入 vs 导入）、
`using_private_name_not_in_scope_test`（不可导入则不冲突）。

### 7.6 第三轮复核：无用例的条款全部漏检

**上表说「§7 的 24 条各有用例」——不属实。** 逐条对照语料，至少 11 条没有用例
（1、2、3、7、8、11、12、13、14、15、19、21）。没有用例就等于两侧可能同错，
7.5 的导入-vs-导入正是这样藏过去的。给这些条款各写探针对打，**又抓出 7 处**：

| # | 条款 | 分歧 |
| --- | --- | --- |
| 1 | 文件合并后缀 | `file merge path...` / `write "..."`（Swift）vs `File merge path...` / `write '...'`（bootstrap）——大小写与引号 |
| 3 | 合并 + 导入列表 | Swift 不带路径、小写；bootstrap 带路径、大写 |
| 11 | `using` 位置 | 报错列号 1（Swift，指向 `using`）vs 12（bootstrap，指向 decl 后的 token） |
| 12 | 模块图有环 | 信封文件：Swift 指编译目标，bootstrap 指闭合环的那一侧 |
| 8 | 无主模块（`--target-module`） | Swift 把原因塞进名字：`Target module 'p8 (package 'p8' has no main module)' not found...`；bootstrap 只说 `not found` |
| 8' | 无默认目标（无主模块且未给 `--target-module`） | Swift `Target module '<unspecified>' not found...`；bootstrap `missing default target module; pass --target-module` |
| — | manifest 家族文案 | `PackageManifestError` 与 `ModuleError` 对**同一条件**各有一份文案（`\n  declared modules` vs `; declared modules`） |

根因都是同一件事：**一条件两拼写**。`takes no import list` 一句在两侧共 4 个产生点，
文案 3 种；`no main module` 在 manifest 家族与 `ModuleError` 家族各一份；
`missingTargetModule` 被当成万能筐，把原因和占位符都塞进「模块名」。

**收敛原则**：一个条件一句话，以两侧**已经在别处共用**的那句为准：

- 文件合并两条：`File merge '<spec>' takes no import list; it merges the whole file`、
  `File merge path must end in '.koral'; write '<spec>.koral'`（两侧 resolver 本就一致）。
- `no main module` / `module does not exist`：统一为 `ModuleError` 家族的写法
  （带 `write its subpath instead` 提示，`; declared modules:` 连接）。
- 无默认目标：采用 bootstrap 的 `missing default target module; pass --target-module`
  ——它说清了缺什么、该做什么；Swift 的 `<unspecified>` 是个没人写过的名字。
- 信封：模块环指向**闭合环的那条 `using` 所在模块的 entry**（bootstrap 的规则，
  它对文件环与模块环是同一句话：始终指向正在解析的模块；文件环时该模块恰好是根，
  所以那条早已一致，未改）。
- `using` 位置：指向 `using` 关键字（Swift 的 span 更可操作——要移的正是那一行）。

`PackageManifestError.noMainModule` / `unknownModule` 原是**无抛出点的死代码**，
且文案与 `ModuleError` 版本不同。现已接到 `--target-module` 的真实路径上并统一文案。

**#15「同一模块 key 重复」与 #17 同因，改为不实现。** `modules` 也是 JSON 对象，
键天然唯一，解析器看不见重复键；而 key 只允许 `.` 与小写标识段 `/` 连接，
两个不同的合法 key 必然是两个不同的模块。设计里「含 `io`/`io/` 别名」的说法是错的——
`io/` 会被 #14 当非法 key 拒掉（已探 6 种别角拼写：`io/`、`io//`、`./io`、`io/.`、
`""`、`./`），不是 `io` 的另一种拼写。设计文档 §7.15 已划掉。

**补上 11 条用例**（每条钉住文案、位置或信封）：
`using_file_merge_suffix_error`、`using_file_merge_missing_error`、
`using_file_merge_with_list_error`、`using_file_merge_empty_list_error`、
`using_after_declaration_error`、`using_invalid_package_name_error`、
`using_module_not_found_error`、`using_no_main_module_error`、
`using_module_cycle_error`、`manifest_invalid_module_key_error`、
`manifest_dependency_key_equals_package_error`、`manifest_dependency_missing_version_error`、
`manifest_duplicate_module_entry_error`、`manifest_entry_missing_error`。

**范围外观察** → **已一并统一**（第 7.7 节）。

**第三轮验收**（2026-10-05）：

```
1) Swift 全量          593/593
2) host → stage1       ok
3) stage1 全量         593/593
4) 自举两轮 + 不动点    FIXED POINT，悬空 0
5) stage2 全量         593/593
6) 行为对拍 + 诊断逐字对拍  593/593
```

用例 579 → 593（新增 14 条，钉住上面每一处曾经漏检的条款）。

### 7.7 CLI 调用错误：一并统一

这一族不进语料（runner 总是传对参数），所以两侧的漂移没人看见。**bootstrap 自己内部
就不一致**：`--optimize` 两处已经是 `Error: ` + 大写，其余九处是小写无前缀；Swift 只有
`Unknown positional argument` 漏了前缀。

**统一规则**（与 manifest 家族两侧已共用的写法一致）：

- **信封**：`Error: ` + 首词大写。源码诊断用 `path:line:col: stage: msg`，其余失败一律 `Error: `。
- **文案**：`Missing path for <opt> option`（选项要路径）／`Missing value for <opt> option`
  （选项要值，如 `--target-module` 要的是模块名不是路径）——Swift 的区分更准确，以此为准。
- **usage**：`Unknown argument` / `Unknown positional argument` / `Missing input file` /
  `Cannot combine` 之后打印 usage；缺单个选项值不打印。Swift 本就如此，bootstrap 补齐。

顺带修掉一处真缺陷：**源文件不存在时 Swift 把 Foundation 的 `NSCocoaErrorDomain`
原样倒给用户**（`Error: Error Domain=NSCocoaErrorDomain Code=260 ...`），bootstrap 是干净的
一句。已统一为 `Error: Failed to read file: <path>` ——路径才是可操作的信息，
OS 理由是噪音。产生点共三处（Swift 一处、bootstrap 两处），原本三种文案。

`std` 缺失这一支两侧行为一致（都静默降级，随后以 `Undefined variable: println`
之类暴露），无分歧。Swift 的 `getCoreLibPath()` 是**无调用点的死代码**，其中
`Could not locate std/std.koral` 文案不可达；bootstrap 的 `standard library not found`
也落在 `check`/`build` 走不到的路径上。

**第四轮验收**（2026-10-06）：593/593 × 4，FIXED POINT，悬空 0，诊断对拍 593/593；
12 类调用错误逐条对拍逐字相同。

### 7.3 复核时发现的验证链缺陷（比上面更重要）

**`/tmp/chain.sh` 第 6 步没有 `--compare-diagnostics`。** 于是此前所有「行为对拍 N/N」
只比了**接受/拒绝**与**运行时行为**，**诊断文本从未被对拍**。

补上标志后，同一棵树有 **77 处诊断分歧**：

- 69 处 stage 标签：Swift 把 `ParserError`/`LexerError` 包进 `ModuleError` 时丢了内部 stage，
  一律渲染成 `error:`，而 bootstrap 是 `syntax error:` / `lexer error:`
- 8 处渲染前缀：模块错误 Swift 出 `path:line:col: error: msg`，bootstrap 出裸消息；
  manifest 错误 Swift 出 `Error: msg`，bootstrap 出裸消息

**消息文本本身是一致的**——分歧全在信封。已修齐：Swift 从底层错误推导 stage；
bootstrap 的 `ModuleError` 带 span 并在产出处渲染成最终文本；manifest 错误统一带 `Error: ` 前缀。
现在 **576/576 逐字相同**。

链脚本已改（标志写进脚本，不靠记）；[[verification-chain]] 也已更新，
把「标志可选」改成「标志永远必带」并记下这次的教训。

**阶段 A 验收**（2026-10-05）：

```
1) Swift 全量          568/568
2) host → stage1       ok
3) stage1 全量         568/568
4) 自举两轮 + 不动点    FIXED POINT，悬空 0
5) stage2 全量         568/568
6) 行为对拍（含诊断）   568/568
```

- 所有 `koral.json`：无 `name` / `entry` / `requires` / `module_aliases`；`modules` key 无 `::`；
  `dependencies` 只有 `{ source, version }`，key 即源码名 ✅
- `requires` 一删，`std::json` 立刻暴露一处真漏（§6.2），已按设计补 `using` ✅
- `module_aliases` 一删，改名即换 key：`dep_utils` → 消费方 key `game_utils` ✅
- toolchain 的 `koral init` 产出新形态 manifest（`package` + `modules: {"."}`），
  `koral build/check` 走 `--target-module <全名>` ✅

---

## 6. 实施中发现的设计缺口与缺陷

写在前面：下面是**动手才看得见**的东西。设计文档写的是意图，落地时撞到的是细节。
每条都标了它是什么——设计缺口（文档该说而没说）、设计错误（文档说错了）、
编译器缺陷（与设计无关的既有 bug）。

### 6.1 设计缺口：`std` 主模块是 prelude，文档没说（已定）

**现象**：566 个测试用例里 **445 个完全没有 `using`**，其中 295 个直接用 `println`。
`Duration`（std 主模块的类型）不写 `using` 就能用；`DateTime`（`std/time`）不行。

**真相**在 `VisibilityChecker.swift:102`，一行注释写着：

> `std root is a compiler-provided prelude for non-std modules only.`

即：**`std` 主模块对非 std 模块是隐式 prelude**（编译进来 + 进作用域）；
其它模块（含 `std/io`、`std/time`）一律要显式 `using`。

**这不是实现走样，是刻意设计**，只是文档没写。§6.4 的依赖图把主模块画成「基础层」，
与 prelude 读法一致；但 §5.4 的「没有依赖但不 import 的场景」读起来像连 prelude 也不许有。

**裁定**：`std` 主模块 = prelude，对非 std 模块隐式；`using "std";` 仍然合法
（它是 std 子模块文件取得 prelude 的方式，那些文件自己就是 std 的一部分）。
**已按此实现**，并记进设计文档（阶段 C）。

> 证据链：`println` 无 `using` 可用 ⇒ std 主模块进作用域；
> `DateTime` 无 `using` 报 `Undefined type`，有 `using std::os { .. }` 但没 import 时报
> `Import it explicitly with using Std::Time { DateTime }` ⇒ **载入 ≠ 进作用域**，
> 导入才进作用域。两条合起来只能是 prelude。

### 6.2 设计正确性的实证：`std::json` 漏 `std::math`（§5.4 抓到的真漂移）

删掉 `requires`、把模块图改为从 `using` 派生后，`std/json` 立刻编不过：

```
std/json/json_value.koral:88:21: error: Member 'trunc' not found in type 'Float64'
```

`Float64.trunc` / `is_inf` / `is_sign_negative` 声明在 `std/math/float.koral`。
`std/json` **用到了它们**，但源码里一条 `using std::math` 都没有——依赖关系只活在
manifest 的 `requires: ["std", "std::text", "std::math"]` 里。

这正是 §5.4 要消灭的东西（「一处真相，不会出现 manifest 说依赖 X、源码没用这类漂移」）。
**修法是让源码说实话**：`std/json/json_value.koral` 补 `using std::math { .. };`。

顺带核实过：`std::net` / `std::os` / `std::proc` / `std::time` 的 `requires` 与源码
`using` 并集一致，没有第二处漂移。**设计抓到的那一处是真漏，不是误报。**

### 6.3 编译器缺陷：`List.sort_by` 在 mutable newtype wrapper 上栈溢出

`modules.sort_by((m) -> m.full_name());`，其中 `modules: List[ModuleInfo]`，
`ModuleInfo` 是 `type mutable ModuleInfo(module_private mutable storage ModuleInfoStorage)`，
会让 **Swift 编译器自身** SIGSEGV。崩溃报告：

```
exception: EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE
message: Could not determine thread index for stack guard region
```

单帧重复二十余次 ⇒ **无限递归把栈打穿**，不是空指针。

已核实：
- `sort_by` 的 key 换成常量 `-> "k"` **同样崩**，所以与 key 无关，是 `sort_by` 被
  以 `T = ModuleInfo` 实例化这件事本身；
- 在独立小文件里用同构类型（mutable newtype wrapper + `List` + lambda）**复现不出来**，
  所以触发条件还依赖真实代码里类型的规模/形状；
- 这是**既有缺陷**，不是本次改动引入——本轮只动了 `Driver` / `PackageManifest` /
  `ModuleResolver`，没碰 Sema。

**处置**：排序需求本身用**插入时保持有序**的集合实现（`add_module` 按模块路径有序插入），
语义等价且不需要 `sort_by`。**没有绕开问题**——缺陷原样记录在此，待单开任务修
（按 [[bootstrap-debugging-rule]] 的路子，先修 Swift 的 MIR/codegen）。

### 6.4 连带行为变化：不可达模块不再编译

§5.4 说「由 `using` 得到构建排序、**可达性**」。落到实处就是：**没有任何 `using` 指向的模块
根本不参与编译**。三个「given 模块归属」测试和一个「泛型模板要 import」测试因此失真：

- 三个 locality 测试的主模块只有 `let main() Int = 0;`，内容全在子模块里，谁也没 import
  ⇒ 子模块不编译 ⇒ 错误根本不出现。修法：主模块 `using` 那个子模块（`{ .. }`）。
  这不是改测试口径——**在新设计下，想让某段代码被编译就得 import 它**，测试得按这条写。
- `generic_template_requires_import_error_test` 的 `models` 以前靠 `requires` 载入。
  现在改成「import 了 `Witness` 但用 `ImportedBox`」——同一个规则（没 import 的名字不能用），
  同一条文案（`Import it explicitly with using`），但模块是被 import 进来的，
  所以编译器还说得清它在哪。完全不 import 时的文案是 `Undefined type`（已有用例
  `datetime_requires_import.koral` 盯着）。

**`requires` 确实一直在掩盖问题**：`std/json` 漏 `using`（§6.2）、四个测试靠它把代码拽进来。
删掉它换来的是「源码说的算」。

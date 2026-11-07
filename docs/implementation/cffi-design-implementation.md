# cffi-design 实现记录 —— CFFI 落地

> **对应设计**：[`cffi-design.md`](../design/cffi-design.md)（Accepted 2026-11-05）
> **体裁**：实现记录 —— 只追加，记执行与验收，不复述设计。
> **验证链**：[`developer-guide.md`](developer-guide.md) 的 `scripts/verify.sh`。
> **状态**：P1 声明语法、P2 原生构建、P3 条件编译全部落地。

## P1 —— 声明语法（2026-11-05）

**范围**：设计 §B（`let foreign` 体/初值 = 引用/定义、宏常量）+ §C（C 名槽位）+
未决 1 已定案（2026-11-06：`Rune` 不过 FFI，guide 同步）。P2（原生构建）、P3（`#if`）未动。

### 落地面

| 面 | 改动 |
|---|---|
| `compiler/koralc` | AST（`ForeignFunctionDecl`/`ForeignLetDecl` 增 `body`/`initializer`/`cname`）、parser（C 名槽位、体/初值解析、常量初值校验）、sema（导出查体、初值查型、`set_cname`、`is_ffi_compatible_type` 收 `Rune`）、mono（体经 concrete registry、宏常量降级普通全局量、codegen 名表收 cname）、MIR（`ForeignFunction.is_definition`、`ForeignGlobalVariable.initializer`、体/初始化 work item）、codegen（导出不发 extern、静态初始化器文本、foreign 全局量用统一名表） |
| `compiler-reference`（Swift seed） | 同上镜像：AST/ParserDeclarations/NameCollector/TypeCheckerPasses（含 `coerceLiteral`）、MonomorphizerTypeResolution、TypedAST/MIRLowerer/MIR、CodeGen（extern 门、`foreignStaticInitializerText`）、`isFfiCompatibleType` 收 `Rune` |
| `toolchain/koral-syntax`（koralfmt） | CST（`cname` 槽位、`ForeignFunction` 类型）、parser（C 名槽位、`foreign (…)->…` 类型——**顺手修掉存量缺口**：类型位的函数指针解析与 `is_type_start`）、printer/估长（C 名打印） |
| `docs/guide/grammar.bnf` | `<let-decl>` foreign 形态 + `<c-name>` + `<foreign-constant-init>`；限定词注释同步 |
| `docs/guide/document.md` / `document-zh.md` §6 | Foreign 函数（体定方向、C 名槽位、导出规则）+ Foreign 变量（2×2 形态、宏常量）镜像 |
| `tests/compiler-cases` | 6 新用例（见下）；`ffi_foreign_body_error` 翻转删除 |
| `toolchain/koralfmt/test_fmt.koral` | 5 条新形态往返断言 |

### 语义要点（实现口径）

- 体/初值存在性定方向；签名限制（封闭集合、位置参数、无泛型）引用/定义同一套。
- 名字作值的类型统一 `foreign (A) -> R`；有体函数可作回调。
- 变量 2×2：无值=extern 引用；有值+`mutable`=C 变量定义（静态初始化器限常量字面量）；
  有值+非 mutable=宏常量（无实体，降级普通全局量走 accessor/初始化函数；C 名仅对应标注）。
- C 名槽位紧随 `foreign`、Koral 名之前；函数/全局量喂 `cname` 通路（codegen 已「cname 优先、
  逐字使用」）；宏常量不喂（普通 mangling 名，否则与 C 头的宏撞名）。
- `Rune` 收进 `is_ffi_compatible_type`（两编译器），与布局集合同口径（未决 1 收敛）。

### 验收

- koralc 冒烟（四形态）：`5 / 10 / 7 / 2` ✓；seed 同输出 ✓（差分一致）。
- koralfmt：264/264 内联断言 + 语料门 249 文件往返 ✓（含新形态与 `foreign (…)->…` 类型）。
- 新差分用例（`tests/compiler-cases/`）：
  `let_foreign_cname_alias_ok`（C 名别名 + 撞 C 关键字的 Koral 名 + 函数指针）、
  `let_foreign_export_definition_ok`（导出直呼 + 进 `foreign (A) -> R` + 回调）、
  `let_foreign_macro_constant_ok`（C 名是 C 关键字仍编译——证明宏名不进符号）、
  `let_foreign_export_global_ok`（静态初始化 + 原地改写）、
  `let_foreign_init_non_literal_error`（非字面量初值拒绝）、
  `let_foreign_rune_param_error`（`Rune` 不过函数边界）。
- 差分预言机（全量）与 `verify.sh` 全链：见下方「验收补记」。

### 验收补记

- **差分预言机（1202 例）**：首轮 1200/1202——两失败均为本次特性自身对等缺口，
  已修：① 种子的 foreign extern 原型用 Koral 名而调用点用 C 名（`generateForeignFunctionDeclaration`
  改走 `qualifiedName`）；② 非字面量初值的错误锚点两侧不一致（koralc 指 `=`、种子指值），
  统一为值起点。
- **`verify.sh` 全链（2026-11-05）**：四套件各 1202/1202（seed 门 526s、bootstrap 门 599s、
  stage2 474s、差分 793s），自举定值点（s3.c == s4.c 逐字节）与 dangling 扫描过，
  运行时压力（refcount 竞态、weak 初始化契约）与四样例过。唯一致死点在链尾
  `toolchain/doc` 构建：CST 形态变更的 pattern 消费者漏扫（见下第 4 条），修齐后
  链尾（koralfmt 264/264 + 语料 249、koral-tool 9/9、7 包 lint、doc --check）全绿。

### 实现中发现的既有问题（随批处置）

1. `retained_decl_skeleton`（sema 骨架化）会丢新字段——导出体首版丢失的根因；
   修复为与 `FunctionDecl` 同口径保留 body（Param/Type 仍骨架化，mono 从 registry 恢复）。
2. koralfmt 类型位不认 `foreign (…)->…`（`is_type_start` 缺 `KwForeign`、`CstType` 缺
   变体）——存量缺口，P1 回调常态化后必须修，已随批修掉。
3. Swift `inferTypedExpression` 对整数字面量恒按 `Int` 推导，需 `coerceLiteral` 收敛到
   注解宽度——foreign 初值检查沿用全局量同款两步。
4. CST 形态变更（`Func` 加 `body`、`ForeignDecl` 加 `return_type`、`CstType` 加
   `ForeignFunction`）的 pattern 消费者不止编译器——`toolchain/doc` 也穷举这两个枚举。
   漏扫直到 `verify.sh` 链尾才炸出 6 处 arity 错位。与第 1 条同类：形态变更后以
   编译器穷尽性检查为站点清单，范围要含 toolchain 全部消费方。

### 遗留（转设计未决）

- 未决 2（不捕获 lambda 进指针）、未决 4（C `const` 全局符号）、未决 10（同 C 名多别名
  今天报碰撞，可放宽为「仅定义位互斥」）等见设计「风险与未决」。

## P2 —— 原生构建（2026-11-05）

**范围**：设计 §E（manifest `c_sources` / `platform`、C 管线重构、导出头）+ std 平台库
迁 manifest。§D（`#if`）未动。

### 落地面

| 面 | 改动 |
|---|---|
| `compiler/koralc` | manifest（`PackageModuleConfig` / `ResolvedModuleSpec` 加 `c_sources` / `platform`；闭集键校验、包根约束、`.c` 限定、顶层 `c_sources`/`platform` 拒绝为 moved）、driver（`c_sources_of` 沿模块图聚合按路径去重、`run_clang` 拆「编译 C 单元 + 链接」、平台硬编码删除、runtime 链接库改读 std manifest、`koral_exports.h` 随 emit-c 落盘）、codegen（`generate_exports_header`）、可达性（导出体入根） |
| `compiler-reference`（Swift seed） | 同上镜像（host os 原子走 `#if os(...)`） |
| `std` | `__koral_host_os`（`koral_runtime.c/.h`，ABI 6→7）、`std/os.host_os_name()`、`koral.json` 主模块 `platform` 收编 bcrypt/ws2_32/psapi（windows）、m/pthread（linux） |
| `docs/design/module-design.md` §5.1 | 字段表 + 字段细则 |
| `tests/compiler-cases` | 新包用例 `cffi_c_sources_export_ok` |

### 语义要点（实现口径）

- **C 管线**：每个 C 单元（生成 C、`koral_runtime.c`、各 `c_sources`）先各自 `clang -c`，
  再统一链接；`-O` 随构建模式；`.o` 以源文件 stem 命名、撞名加序。
- **runtime 的链接库有家**：`koral_runtime.c` 是 std 的文件，其平台库声明在 std 主模块的
  `platform` 覆盖层里，driver 在拾取 runtime 的同一位置读它——`--no-std` 也链 runtime，
  所以这条不随模块图走。driver 硬编码删除。
- **os 原子一个词表**：`__koral_host_os` → `std/os.host_os_name()` → `platform` 键查询，
  与 `#if os("...")`（P3）同一封闭集；`is_os_condition_atom` 是唯一判定处。
- **导出头**：`koral_exports.h` 随 emit-c / build 落在输出目录（= `c_sources` 的 include
  路径）；内容 = 有体 `let foreign` 原型（**C 名**）+ 导出全局量 `extern` + 签名所需的类型
  声明（opaque → `typedef struct N N;`，foreign 结构体 / `Rune` → `struct N;` 前置，
  fn-ptr / 定长数组 → 生成 C 同款 wrapper typedef）。与生成 C 同一 CodeGen 状态渲染，
  拼写逐字一致；`check` 不写。
- **`type foreign` 在头里只有不透明前置声明**：C 侧要按值布局就在自己的翻译单元补同 tag
  同成员的定义（C11 6.2.7 兼容）——与「C 侧 opaque」的既定口径一致。
- **overlay 全量校验、按 os 取用**：`platform` 每个键在每个宿主都校验（含别家平台的字段），
  只有取用看当前 os——manifest 不因宿主不同而不同地报错。

### 验收

- `cffi_c_sources_export_ok`：顶层 `c_sources` + 三 os 覆盖层 `c_sources`、C 回叫导出函数
  （C 名）与导出全局量、Koral 调 C——两编译器各自 build + 运行同输出，导出头逐字节一致。
- 无 cname 回落拼写两编译器一致（`plain_flag` / `plain_export` 实测）。

### 验收补记

- **`verify.sh` 全链（2026-11-05）**：ALL GREEN。四套件各 **1203/1203**（seed 门 387s、
  bootstrap 门 445s、stage2 393s、差分 896s；用例总数含新包用例），自举定值点
  （s3.c == s4.c）与 dangling 扫描过，运行时压力、样例、工具链（koralfmt 264/264 +
  语料 249、koral-tool 9/9、doc --check 14 模块）、7 包 lint 全过。随批动作仅一件：
  `std/os` 新增 `host_os_name` 后重生成 `docs/api/std`。

### 实现中发现的既有问题（随批处置）

1. **导出体被可达性裁剪**：`prune_unreachable_functions` 只认 `main` / drop 根；唯一调用方
   在 C 侧的导出体直接消失（链接报 `koral_double` 未解析）。两编译器同批修：foreign 函数
   def-id 即根。
2. **Swift 导出头的全局名分叉**：`qualifiedName` 只认 foreign 函数，导出头给全局发了模块
   前缀 mangled 名，与 koralc（cname 优先）不一致。P1 差分看不见符号名（EXPECT 只看行为），
   到 C 回叫才炸出。修：头里全局名走 `cIdentifier`（与定义体同源）。

## P3 —— 条件编译（2026-11-06）

**范围**：设计 §D（`#if` + 条件迷你文法 + 分区检查 + 条件 `using`）。未决 5 随批钉死。

### 落地面

| 面 | 改动 |
|---|---|
| `compiler/koralc` | lexer（`#` 记号）、parser（新文件 `build_cond.koral`：条件树 + 迷你文法 + 分区检查 + 选枝；`parse_program` 重排为「条目表 → 检查 → 选枝」）、`Parser` 携带构建目标原子、`is_arch_condition_atom`（与 `is_os_condition_atom` 同家） |
| `compiler-reference`（Swift seed） | 同上镜像（新文件 `ParserBuildCond.swift`；宿主原子走 `#if os/arch` 编译期判定；**顺手修掉** `Token.===` 显式对照表缺 `.hash` 行的坑） |
| `toolchain/koral-syntax`（koralfmt） | Token `#`、`CstItem.IfBuild` + `CstBuildCond`、解析（分支块条目循环与文件级同一套注释/空行/using 规则）、打印（条件与分支块版式）、validate 递归 |
| `std` | `__koral_host_arch`（runtime，ABI 7→8）、`std/os.host_arch_name()` |
| `docs/guide/grammar.bnf` | `<build-cond-decl>` + 迷你文法 + 分区/using 规则注释 |
| `docs/guide/document.md` / `document-zh.md` | 「Build-Conditional Declarations / 条件编译声明」节 |
| `tests/compiler-cases` | 3 新用例（见下） |

### 语义要点（实现口径）

- **`#if` 不进公开 AST**：parser 内部树（`BuildCondItem`）承载双分支，分区检查通览全树后
  按构建目标选枝、拼回声明表——未选中分支过语法检查、不进名字解析与 sema，公开枚举零改动
  （穷尽性检查不搅全管线）。
- **分区检查 = 纯语法的互斥判定**：同名声明两两求「存在同一 `#if` 构造使二者分居
  then*/else*」；双方都不带条件的同名对不归它管（sema 的重复声明口径不变）。构造身份 =
  `#` 记号的行列（文件内唯一）。
- **选枝的目标原子**：`host_os_name()` / `host_arch_name()`（koralc 经 std/os 取宿主；
  seed 走 `#if os/arch`）——target == host，交叉编译到来时由调用注入。
- **未决 5 首切口径**（已回写设计）：using 位置逐列表递归，`#if` 按「（递归）含 using 即
  using 项」分类；mixed `#if` 选枝后可能翻转相对顺序——纯风格残留，导入图与顺序无关。
- **koralfmt 不做条件求值**：双分支原样保留、版式规范化。

### 验收

- `if_build_select_ok`：嵌套分支、迷你文法全算子（含括号）、**永选不中的分支放 sema 毒药**
  （未解析名字——证明未选中分支不进 sema）；两编译器同输出。
- `if_build_partition_error`（跨构造未分道的同名声明）、`if_build_unknown_value_error`
  （闭集报错列集合）——两编译器报文与列位逐字一致。
- koralfmt 268/268（含 4 条 `#if` 往返）+ 语料门 250 文件。

### 实现中发现的既有问题（随批处置）

1. **Swift `Token.===` 是显式种类对照表**：新记号不加行则静默失配（`currentToken === .hash`
   恒 false，症状是「Unexpected token: #」）。Swift 侧加记号必须同步这张表。

### 验收补记

- **`verify.sh` 全链（2026-11-06）**：ALL GREEN。四套件各 **1206/1206**（seed 门 449s、
  bootstrap 门 449s、stage2 403s、差分 920s；用例总数含 3 个 `#if` 用例），自举定值点
  （s3.c == s4.c）与 dangling 扫描过，运行时压力、样例、工具链（koralfmt 268/268 +
  语料 250、koral-tool 9/9、doc --check 14 模块）、7 包 lint 全过。随批动作仅一件：
  `std/os` 新增 `host_arch_name` 后重生成 `docs/api/std`。

## P4 —— C 名收口（2026-11-07）

**范围**：派生 C 名校验（`let foreign` / `type foreign` 无槽位时 Koral 名必须是合法 C
标识符）+ **`type foreign` 的 C 名槽位**（与 `let foreign` 同拼写同校验）+ 导出头对
C 名不透明类型的声明权让渡 + 文档三处修正。设计 §A.3 / §B / §C 随批回写。

### 落地面

| 位置 | 内容 |
|---|---|
| `compiler/koralc` | parser（`parse_type_decl` C 名槽位 + 两侧派生名校验，报文同槽位族）、AST（`ForeignTypeDecl` 加 `cname`）、name collector（`set_declared_cname`——声明的 vs 派生的分开记）、mono（foreign 类型名表「cname 优先、逐字」）、codegen（导出头：带声明 C 名的不透明类型不发 typedef；foreign 全局量派生名兜底从 sanitize 改逐字） |
| `compiler-reference` | 同上镜像：Parser（槽位 + 派生校验 + `invalidDerivedCName`）、NameCollector、DefIdMap（`declaredCnameIds`）、TypeCheckerPasses（symbol def-id 补挂 C 名——Swift 一条声明两个 DefId）、TypeHandler（opaque 命名认 cname）、CodeGen（导出头让渡 + typedef 命名认 cname） |
| `docs/guide/document.md` / `document-zh.md` | C 名槽位规则加派生名校验；Foreign 类型加槽位；宏常量手抄风险提示；**修掉示例错**：`let foreign stdin: CFile;`（不透明按值收进全局量，与边界规则矛盾）→ `*CFile` |
| `docs/design/cffi-design.md` | §A.3「C 标签由 mangling 生成」改写（真实 C 类型面前理由不成立）；§C 覆盖面扩到 `type foreign`；§E 导出头让渡说明 |

### 语义要点（实现口径）

- **一个 C 名两种来源，一种校验**：显式槽位过 `is_valid_c_name`；省略即 Koral 名逐字，
  同样必须过 `is_valid_c_name`，否则 `Koral name "X" is not a legal C identifier; write a
  C name string after 'foreign'`（两端逐字同报、同锚 Koral 名记号）。豁免路径 = 给槽位。
- **`type foreign` 槽位语义**：结构体 = C 的 struct tag（生成 TU 发 `struct <cname>{…}`、
  导出头前向 `struct <cname>;`、原型拼 `struct <cname>`）；不透明 = C 类型自己的拼写。
  同 tag 同成员（C11 6.2.7）是布局契约，字段表即布局断言。
- **导出头让渡**：带声明 C 名的不透明类型**不**在 `koral_exports.h` 里 typedef——C 名意味着
  声明归 C 侧，shim 先 include 属主头；无槽位的照旧 typedef（自包含）。生成 TU 恒自发
  声明（自包含不动）。
- **declared ≠ derived**：mono 会把派生名也灌进 cname 表，「名字是什么」与「名字是不是
  用户拼的」分开记（`declared_cname_ids`）——让渡只认后者。
- 生成 C 的派生名一律逐字（foreign 名从不改写：改写=改掉一个已存在的符号）；原来
  foreign 全局量兜底分支的 sanitize（静默改链接名）已删。

### 验收

- `foreign_derived_cname_error`（非 ASCII Koral 名）、`foreign_derived_cname_keyword_error`
  （Koral 名撞 C 关键字）、`foreign_type_derived_cname_error`、`foreign_type_cname_error`
  （槽位非法）——四条报文两端逐字一致。
- `foreign_type_cname_ok`（C 名结构体 + 两种不透明）、`foreign_derived_cname_escape_ok`
  （非 C 标识符 Koral 名 + 槽位的豁免路径，导出函数直呼）——两编译器同输出。
- 1251 用例 seed / bootstrap / 差分（含逐字诊断对照）三线全绿。

### 实现中发现的既有问题（随批处置）

1. **「一条声明两条 typedef」是误诊**：那两条 `typedef struct CFile CFile;` +
   `typedef struct FILE FILE;` 是**两条真实声明**——std 自己就有
   `type foreign CFile {}`（`std/utils.koral`），探针撞了它的名字，各发各的 C 名，
   行为正确。单声明只发一条（`type foreign "PH" X {}` 实测）。顺手做的两件卫生：
   同名 typedef 去重（两编译器）；**真查出一个双端分歧**——零字段括号形态
   `type foreign X();` koralc 发 typedef+struct 双份、seed 只发 struct（P1 起就岔），
   已按「零字段 foreign struct 也是 struct」对齐（只发 struct 形态）。
2. **double-failure 角序已修**：Koral 名同时不合值命名法与 C 标识符时两端报文次序
   曾不同。Swift 的 let 路径改成 koralc 的检查序（**形状 → 派生 → 类型参数**，形状
   口味同 koralc 的裸 `(` 嗅探）：`let foreign Ç(…)` 两端都报形状、`let foreign
   café[T](…)` 两端都报派生。顺带对齐了形状错误的口味分歧（注解型 `let Bad (Int) ->
   Int` 两端都归函数名）。

### 补记 —— 同 C 名布局声明的政策（2026-11-07，随批落地）

**问题**：同 C 名的 foreign 类型声明此前被 decl_map 按 C 名并成一份定义（字段多者
赢），两类真实伤害全程静默——同名字段不同类型（用户以为 `tv_sec: Int32`，实际是
std 的 Int64）、互异字段被并集吞掉（clang 在几百行外报 `no member named 'foo'`）。
而 C 自己把同 tag 双定义叫 redefinition。

**政策（沿用 `let foreign` 的定义位/引用位分野）**：

- **struct 形态 = 布局定义位**：两条声明 C 名相同即报错，**字段表一致也报**（两个
  Koral 类型 distinct、不能互传，共享一条声明才是出路）。报文：
  `foreign types 'A' and 'B' both define the C type 'Z'; a C type gets one definition`，
  锚在后一条声明，按来源序（文件、行、列）定先后。
- **opaque 形态 = 引用位**：重复合法（不声明布局，同一个 C 类型的多个视图）；
  **struct × opaque** 同名合法（定义独一份）。
- 撞名检查对 foreign 类型×类型对不再报（结构体对归上面的布局检查，含不透明的对
  合法）；「rename one of them」对这一族是坏建议（C 名是真身份，改名不解决冲突），
  布局检查给自己的报文。折叠检测（值符号、类型×值符号交叉对）照旧。

**随批修掉的两个相邻问题**：

1. **check/build 口径**：布局检查落在名字层（两条命令同路），`check` 现在与
   `build` 一样报 p1/p2/p3 类冲突。折叠族（`aα`/`a_`）的 check 覆盖仍缺——实例
   级名字只在 mono 后可见，把撞名检查搬过 mono 会让 check 失去「免 mono」的低
   时延；记档为取舍，build/emit-c 全覆盖。
2. **声明 span 的双端分歧**：带访问前缀的声明，koralc 的 span 从关键字起、Swift
   从 `public` 起（既有分歧，诊断锚位在前缀声明上会岔开 7 列）。Swift 的
   `startSpan` 捕获移到修饰符之后，无前缀行为不变；`foreign_type_layout_conflict_
   alias_error` 用带 `public` 的第二条声明钉住。

**政策验证**（两端逐字一致）：p1 不同名同 C 名、p2 同名字段漂移、p3 同名同字段、
p4 字段被吞——四案报同一文案；opaque×opaque、struct×opaque、std 的 `CFile` 共存
——三案合法；折叠照报。

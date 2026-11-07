# Koral CFFI 设计 —— 外部互操作与构建集成

> **Status**：Implemented（2026-11-06：P1 声明语法、P2 原生构建、P3 条件编译全部落地）·
> Accepted 2026-11-05
> **对应实现**：[`cffi-design-implementation.md`](../implementation/cffi-design-implementation.md)
> **体裁**：设计文档 —— CFFI 子系统的**知识正本（全集）**：既有规则与新设计同文，取舍随节记录。
> 执行过程与验收判据记在实现记录里。
> **取舍判据**（复杂度预算、设计公理）见 [`design-axioms.md`](design-axioms.md)。
> **用户向镜像**：[`../guide/document.md`](../guide/document.md) §6「External Interop」与
> [`../guide/document-zh.md`](../guide/document-zh.md) §6 两份。本文是正本，**改规则三处同批改**。
> 文法正本是 [`../guide/grammar.bnf`](../guide/grammar.bnf)。

## 摘要

> **CFFI 分四层：什么能过界、谁声明、名字怎么落、选择与构建怎么走。**
> **过界的是封闭集合**——标量、裸指针、`type foreign`、`[N]T`、`foreign (A) -> R`；
> 表达力缺口由 C shim 收，语言不为它们长能力。
> **`let foreign` 是 C 符号声明**：无体 / 无值是引用，有体 / 有值是定义（宏常量 = 值绑定）。
> **C 名是 mangling 槽位的显式拼写**——字符串；外来词汇不进标识符。
> **`#if … then … else …;` 是声明域的编译期分支**：封闭谓词、字符串值、自分界定界。
> **manifest 收 `c_sources` 与 `platform` 覆盖层**：原生源文件随包走，进同一条 C 管线。

## 背景

Koral 编译到 C，CFFI 是它与 C 世界的全部接口。设计目标从项目目标直接推出（[`../../README.md`](../../README.md)）：
生成器少走错路、审阅者少要看点——所以边界**封闭且显式**（审阅者看一眼声明就知道什么能过去）、
名字**各归其位**（Koral 名解析、C 名 mangling）、构建**声明可见**（原生代码写在 manifest，不藏在脚本里）。

既有模型（随两编译器与 std 落地）覆盖：两个过界封闭集合、`type foreign`、`let foreign` 引用、
`foreign (A) -> R`、裸指针、`[N]T`。本次设计补四个缺口：

| 缺口 | 现状 |
|---|---|
| 导出 | `let foreign` 只有无体形态（`foreign function cannot have a body`）；Koral 函数是闭包盒，进不了 C 指针槽 |
| C 名 | C 符号 = Koral 名逐字照抄；codegen 的 `cname_map` 机制已在（注释原话「a declared cname is used verbatim: it exists to spell the real symbol」）但**源码没有语法写它**；大写名 parse error；C 关键字撞名静默炸 C 编译 |
| 按目标存在 | 语言零条件编译；平台差异躲在 `koral_runtime.c` 的 `#if`、`is_windows_host()` 运行时判、driver 硬编码平台库里 |
| 原生源文件 | `modules[*] = { entry, links }`；一次 clang = `生成.c + std/koral_runtime.c -I std …`；C 文件无处声明，`koral_runtime.c` 是 driver 硬编码特例 |

### 提案过闸

| 提案 | 拒绝清单 | 替换哪条规则（公理 7） | 读法收益 | 局部可判 |
|---|---|---|---|---|
| B 引用 / 定义 | 不命中 | 「decl-qualifier 声明无体」→「体 / 值的存在性定方向」 | 生成器对「暴露给 C」不再另立机制 | ✓ |
| C C 名字符串 | 不命中 | 「C 符号 = Koral 名照抄」→ 显式 mangling 槽位 | 绑定行一处核对 C 头文件 | ✓ |
| D `#if` | 不命中 | 「构建图内声明恒在」→「声明按构建目标存在」 | 平台 API 面不再用运行时错误伪装 | ✓ |
| E `c_sources` | 不命中 | 「driver 硬编码 runtime.c / 平台库」→ manifest 声明的通用原生通道 | 包的原生代码随包可见 | ✓ |

## 模型总览

| 层 | 回答的问题 | 归属节 |
|---|---|---|
| **过界类型** | 什么能跨 C 边界，为什么是封闭集 | A |
| **声明** | 谁声明 C 实体——引用还是定义 | B |
| **名字** | C 名怎么落（mangling 槽位） | C |
| **选择与构建** | 声明按目标存在；原生源文件怎么进构建 | D、E |

跨层的一条恒等式：**边界上的每个类型都有确定的 C 表示，每个声明都有确定的 C 名，每个构建
目标都有一份确定的存活声明集**——三者都编译期定案，不需要全局推断（公理 2）。

## 方案

### A. 过界类型与封闭集合（既有）

#### A.1 两个封闭集合

「能过 FFI 边界」不是一张表，是**两张**——函数槽位与布局槽位的要求不同，这是有意的：

**集合一 · 函数边界**（`is_ffi_compatible_type`：`let foreign` 参数 / 返回、`foreign (A) -> R`
组件；`compiler/koralc/sema/type_checker.koral`）：

| 成员 | 说明 |
|---|---|
| 内建标量 | Int 家族、Wrapping 家族、Float32 / Float64、Bool |
| `Void` / `Never` | **只在返回位**（参数位拒——C 没有 void 值） |
| 不透明 `type foreign X {}` | 集内，但**按值即拒**——只能活在 `*` 后 |
| `*T` / `*mutable T` | pointee 是 `Void` 或**集合二**成员 |
| `foreign (A) -> R` | 组件按集合二校验（返回可 `Void` / `Never`），类型解析期定案 |
| std `Rune` | **分歧中**——guide §6 说含 Rune，实现未收（见「风险与未决」1） |

**集合二 · 布局边界**（`satisfies_foreign_constraint`：foreign 全局量类型、`type foreign`
字段、`[N]T` 元素、`T: foreign` 界、指针 pointee；`compiler/koralc/sema/type_checker_visibility.koral`）：

| 成员 | 说明 |
|---|---|
| 内建标量 | Int / Wrapping / Float 家族、Bool |
| `*T` / `*mutable T` | pointee 是 `Void` 或递归在集内（`*String` 拒——managed pointee 一样过界） |
| `type foreign` 结构体 | C 布局，按值可用 |
| std `Rune` | 集内**唯一的名义类型**：名义只为带方法，表示是定长 Unicode scalar；按 DefId 身份识别 |
| 不透明 `type foreign X {}` | 集内；按值使用仍拒（`opaque_by_value_type`） |
| `[N]T` | 元素递归在集内 |
| `foreign (A) -> R` | 组件在集内（返回可 `Void` / `Never`） |
| 泛型参数 | 带 `T: foreign` 界的参数 |

**共同排除**：Koral `type`、闭包（`(A) -> R`）、托管引用——按值或隔着指针都不跨界。

**为什么封闭**：C ABI 的每个槽位必须是**表示确定**的类型——调用约定、对齐、拷贝语义都要
编译期可定；托管对象的表示是编译器的自由（[`thin-pointer-design.md`](thin-pointer-design.md)），
不能许诺给 C。副产品是**跨界零所有权成本**：边界上没有引用计数动作，收发都是纯 C 值。
封闭集合还让「局部可判」成立——用户不必推断某类型过不过界，查表即得。

#### A.2 raw pointer：跨界载体

`*T` / `*mutable T` 是 FFI 的载体类型，也是低层内存的通用形态。设计要点（细则见 guide §6
与 [`type-semantics.md`](type-semantics.md)）：

- 显式拼写（公理 3）：`*T` / `*mutable T` 是类型，`&` / `&mutable` 是取址，`*p` 是解引用——
  没有托管引用的隐式转换层；
- `*Void` / `*mutable Void` = C `void*`，**每个边界上都合法**（参数、返回、指针组件、
  全局量、字段）；
- 可变性跟**指针的类型**走，不跟绑定走：`*mutable T` 链上写入，`*T` 链中段重置其后的写权限；
- `null` 是硬关键字字面量，加入指针位，可比较、可作模式（`p is null`）；
- `as` 做指针重解释（换元素类型、指针 ↔ 整数地址）；
- 指针下标 `p[i]` 是 **C 下标，不查边界**（与 `[N]T` 相反，见 A.4）；
- pointee 也得过界（集合二）——裸指针能过边界只到它指向的东西为止。

#### A.3 `type foreign`：C 布局类型

两种形态，一套规则（C 的规则，用 Koral 的拼写）：

```koral
type foreign CFile {};                                    // 不透明句柄（无字段）
type foreign KoralTimespec(tv_sec: Int64, tv_nsec: Int64); // FFI 结构体
```

- **不透明句柄**没有布局：只出现在 `*` 后（字段、全局量、按值参数一律拒）。经典
  incomplete-struct 指针模式（`*FILE`）。
- **结构体**字段只收裸 `name: Type` 位置字段——无访问修饰符、无 `mutable`、无命名字段、
  无默认值。C 布局公开且恒可写；改不了什么的标记只会撒谎。
- 字段类型过**集合二**；禁止直接自递归（`*Self` 报错——自递归走指针）。
- 不能声明 `mutable`（可变性属于 Koral 自己的 nominal 声明），不接受泛型参数。
- **可变值语义**：赋值与传参按值拷贝；方法里 `self` 是这样一个拷贝——**没有可变 self**，
  要改接收者就收 `*mutable T` 参数。就地写入（`x.v = v`）与所有值类型同一套矩阵：
  `let mutable` ✓、`mutable` 参数（本地拷贝）✓、`*mutable T` 链接 ✓、`type mutable` 的
  `mutable` 字段 ✓；`let` / 普通参数 / `self` / `*T` 链 / 临时值 ✗。
- 显式 `Drop` 被拒绝：C 值没有析构——代码生成是纯 C 赋值拷贝，drop 是空操作。
- `given` 方法可写（`self` 语义同上）。
- **C 名槽位**（2026-11-07）：`type foreign "timespec" KoralTimespec(…)` ——结构体形态取 C 的
  struct tag，不透明形态取 C 类型自己的拼写；不写则 Koral 名逐字（且必须是合法 C 标识符）。
  布局匹配仍不靠名字（字段表=布局断言，同 tag 同成员 = C11 6.2.7 兼容），但名字对上了，
  shim include 真实头文件后按值也能过 export 原型。

#### A.4 `[N]T`：定长数组

- C 布局的 N 元定长数组；可变值语义（拷贝与写入矩阵同 A.3）。
- 字面量：非空恰好 N 个元素；`[]` 是全零缓冲。
- 下标**做越界检查**：下标只求值一次，越界 panic，不会读到相邻内存（`*T` 的下标才是
  不查边界的 C 下标）。
- 元素类型过**集合二**；**不过函数边界**——`let foreign` 的参数 / 返回写 `*T`（那才是 C
  数组参数的真身）；可按值出现在全局量位与 `type foreign` 字段。

#### A.5 `foreign (A) -> R`：函数指针

```koral
let foreign abs(x: Int32): Int32;

let main(): Int = {
    let f: foreign (Int32) -> Int32 = abs;    // `let foreign` 函数
    let cb: foreign (Int32) -> Int32 = null;  // 可为 null，同 *T
    return 0;
};
```

- **裸 C 函数指针，不是 Koral 闭包**。居者：`let foreign` 函数（引用——本次起含定义）、
  同类型值、`null`（同 `*T` 的空语义：可空、可 `==` / `!=`、可 `is null` 模式）。
- 赋值是**精确同构**：参数个数 + 参数类型 + 返回，名字不看。与闭包类型 `(A) -> R` **零转换**
  ——lambda / Koral 函数值是闭包盒（`__koral_Closure`），塞进去就是普通类型不匹配。
- 调用只用位置参数、直呼 C；经指针调用写作 `(p)(args)`。
- 组件过界：参数位拒 `Void` / `Never` / 按值不透明；返回可 `Void` / `Never`。
  `foreign (Void) -> R` 被拒——那是零参指针的错拼。
- 代码生成按签名**惰性铸造** C typedef（`typedef R (*…)(…)`），同签名共享。

### B. `let foreign`：C 符号声明——引用与定义

**一个拼写一个概念**：`let foreign` = 「这条声明对应 C 世界的实体」（`decl-qualifier` 一族
说的是「定义在哪里」——`foreign` 在 C，`intrinsic` 在编译器）。方向由**体 / 初值的存在性**
决定——C 自己的声明模型（`extern int f(int);` 与 `int f(int) { … }` 同一条声明语法）：

| 形态 | 语义 | 生成 | 状态 |
|---|---|---|---|
| `let foreign f(…): R;` | 引用（extern 函数） | `extern R f(…);` | 已落地 |
| `let foreign f(…): R = { … };` | **定义**（C ABI 导出函数） | `R f(…) { … }` | 已落地（P1） |
| `let foreign mutable x: T;` | 引用（extern 可变量） | `extern T x;` | 已落地 |
| `let foreign x: T;` | 引用（extern 只读量） | `extern const T x;` | 已落地 |
| `let foreign mutable x: T = v;` | **定义**（C 变量） | `T x = v;` | 已落地（P1） |
| `let foreign x: T = v;` | **C 宏常量的值绑定**（无存储、无符号） | 无实体；Koral 侧常量 | 已落地（P1） |

规则：

- **签名限制不变**：位置参数、无泛型、不支持命名参数与默认值；参数 / 返回逐项过
  **集合一**——C ABI 的诚实性就是封闭集合存在的理由，导出不放松一分。
- 有体 `let foreign` 在 Koral 侧可直接调用，与普通函数无异；名字作值的类型**统一**为
  `foreign (A) -> R`（导入已是如此），可赋给指针槽、传给 C。**不**转换为闭包类型。
- 可见性（public / internal / …）只管 Koral 侧名字；**C 符号恒导出**（C 没有模块可见性）。
- panic 契约：打印 + `abort()`，跨导出边界**无栈展开**（现行为即安全，写进 guide 防将来
  静默破坏）。
- 导出定义撞名（两个模块导出同一 C 符号）是错误：现有 C 名碰撞检查从「sanitize 折叠检测」
  扩到定义位；链接器兜底。**引用**的重复声明合法（同一外部符号绑两次，见
  `foreign_function_duplicate_default_internal` 用例）。
- foreign 全局量是 **C 直接读取的布局对象**：可按值收 `type foreign` / `[N]T`（函数边界
  不收它们）；访问绕过 Koral 全局量的初始化器机制（裸 extern）。
- 宏常量是「C 世界的值」：值从 C 头文件复制，`mutable` 决定变量位有无存储——无存储即常量
  （宏的对应物），有存储即 C 变量定义。C 的 `const` 全局**符号**暂缺位（「风险与未决」4）。

### C. C 名槽位：外来词汇 = 字符串（已实施 P1）

```koral
let foreign "CreateFileA" create_file_a(path: *UInt8, access: UInt32): UInt32;
let foreign "GetLastError" get_last_error(): UInt32;
let foreign "AF_INET6" af_inet6: Int32 = 10;
```

- **拼写**：字符串写在 `foreign` 之后、Koral 名之前，是声明的一部分。这是 mangling 槽位的
  显式拼写（[`name-resolution.md`](name-resolution.md) 三个合法名字出口里的「C 改编」）——
  身份仍是 DefId，C 名只是改编结果。
- **语义**：这条声明**在 C 世界的名字**。函数 / 全局量 = 链接名（进 `cname` 通路，codegen 已
  「cname 优先、逐字使用」）；宏常量 = 宏名（对应标注，无实体）。可省略；省略 = Koral 名逐字
  （现状兼容，std 的 `__koral_*` 绑定不动）——**但此时 Koral 名就是 C 名，必须是合法 C
  标识符**，否则报错要求给槽位（2026-11-07 收紧：此前派生名不校验，非法 C 一路漏到 clang）。
- **覆盖面**：`let foreign`（函数、全局量、宏常量）与 **`type foreign`**（2026-11-07 起同一
  槽位）：结构体形态是 C 的 struct tag（`"timespec"` → `struct timespec`），不透明形态是 C
  类型自己的拼写（`"FILE"` → `FILE`）。带 C 名的不透明类型**归 C 侧声明**——导出头不代为
  typedef，shim 先 include 属主头；结构体照发前向声明（同 tag 同成员 = C11 6.2.7 兼容）。
  原「C 标签由 mangling 生成、不需要别名」的理由在真实 C 类型面前不成立：`FILE` / `timespec`
  的名字是 C 世界的，Koral 名对不上就要转型、按值位根本没法桥接。
- **一并修掉存量坑**：Koral 名撞 C 关键字（`let foreign "abs" int(…)`）从此有出路——
  C 名与 Koral 名各归各（不给槽位则报错，见上）。注意 C 名本身必须是合法 C 标识符：
  `open$NOCANCEL` 这类链接器级怪名（汇编级符号）仍走 C shim——extern 拼写受 C 词法约束。
- **原则**：标识符只属于 Koral 名字空间；**外来词汇（路径、模块名、C 名、构建目标名）一律
  字符串**——与 `using "std/io"`、`#if os("windows")` 同一条规则。

### D. `#if`：声明域的编译期分支（已实施 P3）

**表层**（住声明域；`#` 标记编译期，`if` / `then` / `else` / `and` / `or` / `not` 全部复用，
零新增保留字）：

```koral
#if os("windows") and not arch("x86_64") then {
    let foreign "CreateFileA" create_file_a(path: *UInt8, access: UInt32): UInt32;
} else {
    let foreign "open" open_path(path: *UInt8, flags: Int32): Int32;
};
```

- **文法**：`"#" "if" <build-cond> "then" <decl-block> ("else" <decl-block>)? ";"`，
  `<decl-block> ::= "{" <global-decl>* "}"`。**分支一律是块**（单声明也包一层）——否则单声明
  分支的 `;` 会与「一切以 `;` 收尾」打架。整条以 `;` 收尾，**没有 `#endif` 配对物**。
- **条件迷你文法**（不是表达式，不进名字解析）：

  ```text
  <build-cond> ::= <cond-or>
  <cond-or>    ::= <cond-and> ("or" <cond-and>)*
  <cond-and>   ::= <cond-not> ("and" <cond-not>)*
  <cond-not>   ::= "not" <cond-not> | <cond-atom>
  <cond-atom>  ::= <pred-head> "(" <pred-value> ")" | "(" <build-cond> ")"
  <pred-head>  ::= "os" | "arch"
  ```

  值是字符串字面量，按谓词头的封闭集校验：`os ∈ {"windows","linux","macos"}`、
  `arch ∈ {"x86_64","aarch64"}`。未知谓词头 / 未知值 → 报错并列出封闭集。
- **`else` 不必须**。但**同名互补的唯一主流表达是 if / else 分区**：同一拼写的多条声明必须在
  `#if … else …` 分支树上两两分道（一条在 then 侧、另一条在 else 侧），否则报重复声明；
  无条件声明与条件声明同名即冲突。嵌套分道合法。检查是**纯语法、与构建目标无关**的——
  不存在「Windows 上过了、Linux 上炸」的漂移错误。
- **未选中分支不进 sema**（不解析名字、不查类型），但语法必须合法。
- **`using` 允许在分支块内**（条件合并 / 条件导入），受「using 在文件顶部」的同一约束
  （位置细则随文法定稿，见「风险与未决」5）。嵌套 `#if` 允许。
- 语句 / 表达式级不做（「非目标」）；平台分歧用每平台声明表达。

### E. 原生构建集成（已实施 P2）

**manifest**（[`module-design.md`](module-design.md) §5.1 `modules[*]` 的扩展）：

```json
".": {
  "entry": "main.koral",
  "links": ["m"],
  "c_sources": ["native/compat.c"],
  "platform": {
    "windows": { "links": ["ws2_32"], "c_sources": ["native/win.c"] }
  }
}
```

- **`c_sources`**：相对包根的 `.c` 路径；编译一次。**仅根包可声明**（2026-11-06 收紧）：
  依赖包清单带 `c_sources` 在加载时拒绝——原生代码是信任边界，按包身份把关，不看路径拼法。
- **`platform` 覆盖层**：键是 `#if` 同一套 os 原子（字符串）加 **`default`**（其余主机的兜底，
  运行时链接库不因主机不在封闭集而静默丢失），值是 `{ links?, c_sources? }`
  增量叠加。它收编 driver 今天硬编码的平台库（Windows `-lbcrypt -lws2_32 -lpsapi`、
  POSIX `-lm -lpthread` 迁入 std 的 manifest），driver 硬编码删除——条件词汇与源码侧一套。
- **同一条 C 管线**：`run_clang` 从「一条平铺命令」重构为「编译 C 单元 + 链接」：生成 `.c`、
  `koral_runtime.c`（内置）、各包 `c_sources` 先各自编译再统一链接，`-O` 级别随构建模式。
- **导出头**：按有体 `let foreign`（与导出全局量）生成 `koral_exports.h`，挂到各 `c_sources`
  的 include path——C 文件回叫 Koral 的原型不靠手抄；`type foreign` 以不透明前向声明出现
  （带 C 名的不透明类型除外——那是 C 侧的类型，导出头不代为声明，shim 先 include 属主头）。
- **`koral_runtime.c` 保持内置**：它是 ABI 基座（`koral_runtime.h` 带 ABI 版本号，`--no-std`
  也要链），不是包特性；被替换的是「硬编码单文件」这条通路本身——同一条管线，runtime 是
  第一个常客（公理 7 的替换项）。
- 单文件模式（无 manifest）无 `c_sources`；`check` / `emit-c` 不动编译 / 链接步。

### F. 四层的咬合与逃生舱

- C 节的 C 名字符串出现在 B 节导出头的原型上（导出原型用 C 名，不是 Koral 名）；
- D 节的条件原子与 E 节的 `platform` 键是同一套词汇（字符串、同一封闭集）；
- 语言表达不了的（varargs、宏函数、inline、平台怪形、C `const` 全局符号）一律写进
  `c_sources` 的 shim 文件里，对外只露封闭集合内的干净符号——**shim 是复杂度预算的出口**。

## 非目标

- **varargs（`...`）不过边界**——封闭集合不含变长参数；要 `printf` 一族，写 C shim 里的定参封装。
- **调用约定只有 C 默认一种**——stdcall / vectorcall 等不做（x86_64 / aarch64 上无分歧）。
- **表达式级 / 语句级条件编译**（`cfg!()`、函数体内的 `#if`）——不做；平台分歧用「每平台一个
  声明」表达。仓颉同样只做声明 / 导入级，这一范围是业界共识的下限。
- **feature flags / 自定义条件**——v1 条件集封闭（os、arch）；自定义条件轴是登记在案的演进位
  （[`module-design.md`](module-design.md) §11.4 搁置的 feature 同一条线）。
- **文本预处理器**（宏展开、`#define`）——不设。
- **注解 / 属性系统**——不为条件编译开 `@` 类别。
- **C 宏的链接**——宏无符号实体，不存在「绑定宏」；只有宏常量的值绑定（B 节）。
- **managed 类型跨界**（Koral `type`、闭包、托管引用）——按值或隔着指针都不行（A.1）。
- **unsafe 块模型**——Koral 不设 `unsafe` 区块；危险性由类型拼写承担（`*T` 就是显式标记，
  见 A.2），不另立第二种「不安全」表达。

## 替代方案

**既有模型（A 节）的取舍记录原文未记载**——封闭集合为何两套、为何无 unsafe 块、`type foreign`
为何是值语义，都只有结论与实现。本轮调研的横比列在下面，**是后补对照，不是当时的取舍记录**：

| 对照 | 仓颉 | Rust | Koral 的位置 |
|---|---|---|---|
| 导入 / 导出 | `foreign func` 只导入 + `@C func` 导出（两个形态） | `extern "C" { }` 块 + `#[no_mangle]`（两处） | **一个 `let foreign`，体定方向**（B 节） |
| 函数指针 | 泛型类型 `CFunc<(A) -> B>`，foreign / `@C` / 不捕获 lambda 三类可居 | `fn` 指针，非捕获闭包可强转 | `foreign (A) -> R`，居者见 A.5（不捕获 lambda 未定案，「风险与未决」2） |
| 不安全表达 | `unsafe { }` 块包 foreign 调用 | `unsafe` 块 | 类型拼写（`*T`），无块 |
| varargs | 支持（`...`） | 不支持 | 不支持，C shim 兜 |
| 条件编译 | `@When[os == "Linux"]` 逐项标注 | `#[cfg(…)]` 逐项标注 | `#if` 块 + 分区（D 节） |

本次四项能力的替代方案（均为本轮真实讨论过的取舍）：

- **`let foreign f(…) = "CName";` 用 `=` 写别名**——否。`= "…"` 与函数体（表达式体）同形歧义：
  `let foreign f(…): *UInt8 = "strerror";` 读不出是别名还是返回字符串的体。
- **foreign 名字位放宽大小写（名字即 C 名）**——否。绑定文件与 C 头逐一对应、零映射是真实
  优势；但大写名进表达式位与类型构造 `Foo(x)` 同形（读者形状启发失灵），大小写类规则开例外
  （公理 6 要登记），C 关键字 / 怪名仍无解，两编译器解析与检查多处开口。C 名字符串全收这些
  能力，故取后者。
- **裸 `if` 住声明域**——否。「if 形但带标记」是业界折中：Jai `#if`、V `$if`、Mojo
  `@parameter if`、Julia `@static if`、C# / Delphi / Swift `#if`；裸 `if` 只有 Zig 一家，靠
  comptime 一般机制托底。Koral 无 comptime，`if` 一词双域太激进。
- **`on windows` 后缀 / 守卫新关键字**——否。不为守卫新增保留字。
- **Swift 式 `#if … #endif`**——否。`#endif` 配对与嵌套是生成器风险（恰是要消灭的类别）；
  无 `;` 的指令行破坏分号均一。自分界块 + `;` 取代它。
- **仓颉 `@When[…]` / Rust `#[cfg(…)]` 逐项标注**——否。条件紧贴声明、逐行自带平台信息是真实
  优势；但要为 Koral 开注解 / 属性类别（复杂度预算的大动作，属性天生招引 payload 膨胀）。
  逐行信息由 `#if` 块 + 分区可见性承担。
- **Go 文件级（文件名后缀 / 构建标签）**——否。零语法是真实优势（std 规模验证充分）；但条件
  住文件名 / 注释，声明处看不见平台，「同名互补跨文件」成常态，与「显式、局部可判」相悖。
  文件级能力由 `#if` 块内的条件 `using` 收编，不另立机制。
- **Nim / Odin `when` 专词**——否。Koral 的 `when` 已被模式匹配占用（`when x in { … }`），
  一词双形是 [`module-design.md`](module-design.md) 刚清掉的那类双载。
- **条件值用裸原子（`os(windows)`）或枚举 case 形（`os(.Windows)`）**——否。`windows` 不是
  标识符，就不该长成标识符；外来词汇 = 字符串（与 `using "std/io"`、`let foreign
  "CreateFileA"` 同规则），且值域出现 `x86-64` 这类词时裸词破功。
- **`else` 强制配对**——否。单平台 API（`CreateFileA` 只在 Windows 存在）是主流场景，空
  `else { }` 是纯负担；业界 `#if` 系的 `else` 全部可选（必须配对的 `#endif` 已被自分界消掉）。
- **同名互补写两个独立 `#if` 块（Cangjie / Rust 形态）**——否。它们没有 else 才那样写；Koral
  有分区，分区是唯一主流表达（公理 6），且检查纯语法、与目标无关。
- **varargs 直接进封闭集合**——否。变长参数的类型位无法诚实表达；C shim 定参封装是既定逃生舱。
- **C 宏直接绑定为符号**——不可能。宏无链接实体，只做值绑定（B 节）。

## 风险与未决

1. **`Rune` 在函数边界的归属**——已收敛（2026-11-06 定案）：二选一走了「改 guide」。
   `Rune` 与 `String` 同为 std 名义类型，表示由编译器做主，**不过 FFI**（函数边界与
   布局边界都拒，static 初值白名单同步剔除 rune 字面量）。guide §6 两份已同步。
2. **不捕获 lambda 进 `foreign (A) -> R`**：仓颉 `CFunc` 与 Rust 的 fn-pointer 强转都允许
   非捕获 lambda；对 Koral 是 B 节的延伸（捕获与否语法可见、局部可判）。**已提议，未定案。**
3. **自定义条件（feature 轴）**：仓颉走 `--cfg` / `cfg.toml` 键值对；Koral 若引入，条件文法加
   `<pred-head> <cmp> <string>` 变体即可，但「同名分区」在开放轴上的形态与
   [`module-design.md`](module-design.md) §11.4 的 feature 一起过闸。
4. **C `const` 全局符号缺位**：非 mutable + 有值已被宏常量占用，`extern const T x` 的**定义**
   形态不可表达；写 C shim 兜，或将来给宏常量另立形态再腾位。
5. **`#if` 块内 `using` 的位置规则**（已随 P3 钉死）：「using 在文件顶部」按**逐列表递归**
   执行——文件与每个分支块各自「using 项在前、其它在后」，`#if` 整条按「（递归）含 `using`
   即 using 项」分类。检查是纯语法的；副作用是两条 mixed `#if` 选枝后可能翻转相对顺序
   （纯风格残留，导入图与顺序无关，不影响语义）。
6. **panic 跨导出边界**：现行为 = 打印 + `abort()`（无栈展开，安全）；作为契约写进 guide，
   防止将来引入 unwind 时静默破坏导出语义。
7. **双编译器同步**：每项都要落 `toolchain/koral-syntax`、`koralc`、`compiler-reference`
   （Swift seed）、`koralfmt`、`grammar.bnf`、guide 中英两份；差分坑（seed 的 typed span 多
   `.unknown`、多错误收集分叉）→ 测试必须单失败点。
8. **`platform` 覆盖层只有 os 轴**：arch 维度的 manifest 分流（按 arch 挑 `c_sources`）不在
   v1——C 文件内部用自己的 `#if` 兜。
9. **两张封闭集合的维护点不止 sema 一处**：koralc 单态化器里的 `type_satisfies_foreign_bound`
   复检与 sema 集合**不同构**（指针不查 pointee、缺 Opaque / FixedArray / FnPtr 案），Swift
   侧无对应复检。收敛方向：删重复复检或对齐集合——不许第三份手抄。
10. **C 名碰撞口径偏严**：两条 `let foreign` 引用同一 C 符号（两个别名）今天报碰撞——
    C 本身允许重复 extern 声明；可放宽为「仅定义位互斥、引用位去重」。P1 保持严格口径。

## 实施

既有模型（A 节）已随两编译器与 std 落地。分期（细节与验收判据记入实现记录，不在此展开）：

1. **P1 —— 声明语法**（已落地）：C 节（C 名槽位）+ B 节（体 / 值形态、宏常量）同一批文法改动；
   两编译器 + koralfmt + `grammar.bnf` + guide 同批；`ffi_foreign_body_error` 翻转，新增
   别名 / 导出 / 撞名差分用例。**随批收敛「风险与未决」1（Rune）。**
2. **P2 —— 原生构建**（已落地）：E 节（`c_sources` / `platform` / 导出头 / driver 管线重构）；
   std 平台库迁 manifest；`koral_runtime.c` 入同管线。
3. **P3 —— 条件编译**（已落地）：D 节（`#if` + 条件迷你文法 + 分区检查 + 条件 `using`）。

落地记录按词干配对 [`cffi-design-implementation.md`](../implementation/cffi-design-implementation.md)，
验证链走 [`developer-guide.md`](../implementation/developer-guide.md)。

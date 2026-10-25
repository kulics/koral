# Koral 模块与导入设计

> **Status**：Implemented（2026-10-24 形态层重做、2026-10-25 方法面已落地；身份/命名表/孤儿文件三条未做，见「实施」）· 2026-10-25
> **对应实现**：[`module-design-implementation.md`](../implementation/module-design-implementation.md)
> **体裁**：设计文档 —— 记决定与取舍，不记执行过程。执行过程与验收判据在实现记录里。
> **取舍判据**（复杂度预算、设计公理）见 [`design-axioms.md`](design-axioms.md)。

## 摘要 —— 原文「0. 一句话」（2026-10-24 重写，2026-10-25 方法面改 Rust 版）

> **外部单元是 package，包内含一个或多个 module。**
> **单文件即模块**——文件不是模块系统的概念，它只是模块的最小尺寸。
> **`using "X";` 是合并（边界消掉），`using "X" { … };` 是导入（边界保留）。**
> 括号是「边界还在」的记号，也是过滤器的家；两者不许交叉。
> **合并只在包内**——别的包的模块只能导入，包边界是合并停下的地方。
> **`given` 挂在类型（+ trait）上**：inherent 方法跟着值走，trait 方法跟着 trait 名走。
> **点名类型不带来 trait 方法**——与 Rust 同规则，实测钉死。
> **模块全名 = `包名[/子路径]`** 只对已登记模块；未登记的本地模块走相对路径。
> **单模块包不特殊处理**——它就是只有主模块的包，主模块名 = 包名。


## 背景 —— 原文「1. 概念」

| 概念 | 是什么 | 稳定身份 | 例子 |
| --- | --- | --- | --- |
| **package** | 外部可使用单元：一份 `koral.json`、一个版本、一组依赖 | **`source`**（§5.3） | `httpr`、`std` |
| **module** | 包内的构建单元 = **入口文件 + 它传递合并进来的一切** | **(包的 `source`, 入口在包内的位置)** | `httpr/conn`、`std/io` |
| **file** | **模块的最小尺寸**。单文件 = 只有入口、无合并的模块 | 不单独成概念 | `util.koral` |

**「文件合并」不是独立概念**：`using "./x.koral";` 合并的是**以 `x.koral` 为入口的那个模块**。
对单文件模块，行为与旧的「文件合并」逐字相同；对 `util.koral` 里还合并了 `util_more.koral`
的情况，合并模块-util 也是整条闭包——**行为等价，概念数从 3 降到 1（模块）+ 2（操作）**。

**模块全名 = 包名 [ "/" 子路径 ]**——这是**已登记模块的写法**，不是身份。

- **包名**：这个包在**源码里**的名字（`package` 字段），也是自引用的前缀。它不是身份——身份是 `source`
- **子路径**：模块在包内的位置，`/` 分段
- **主模块**：子路径为空的那个模块，**模块全名 = 包名本身**

> 模块全名含本地源码名，所以**同一个模块在不同工程拼写不同**（`httpr/conn` vs `http/conn`）。
> 跨工程不变的是 **`(source, 入口在包内的位置)`**——去重、lockfile、ABI 符号都看它（§5.3）。
> `std` 没有 `source`（built-in），它的身份是 `(工具链版本, 入口位置)`。

**主模块不是「根」**：它与子模块是平级的两个模块，只是子路径为空。`std` 与 `std/io` 之间没有父子、挂载、re-export 语义。

### 1.1 三种包形态（写法一致，不特殊处理）

| 形态 | manifest | 源码 |
| --- | --- | --- |
| 只有主模块 | `modules: { ".": … }` | `using "slug" { make_slug };` |
| 主模块 + 子模块 | `modules: { ".": …, "conn": … }` | `using "httpr" { Request };`、`using "httpr/conn" { Conn };` |
| 只有子模块 | `modules: { "compiler": …, … }` | `using "koral/compiler/parser" { Parser };` |

三者共用同一套规则：**主模块就是「子路径为空」的那个模块**。单模块包只是恰好只有一个模块。


## 非目标

原文未单列「非目标」。范围边界记在别处，此处只做指引，不代原文另立目标：

- 「## 风险与未决」（原文 §10「边界与待定」）记了边界条件。
- 「### 尚未覆盖的包管理能力」（原文 §11.4）明确列了本次不做的包管理能力。

## 方案

命名、语法、解析、manifest 与包管理机制共同构成方案。各子节保留原标题与原编号，
便于与实现记录里的章节号对照。

### 命名 —— 原文「2. 命名」

#### 2.1 词法

```text
包名       ::= 标识符                       # 单段：slug、httpr、std
子路径     ::= 标识符 ("/" 标识符)*
模块全名   ::= 包名 [ "/" 子路径 ]
```

> `标识符` 沿用语言本身的词法规则（小写开头、字母数字下划线），另加：不得是保留字。

**包名是单段标识符**（`slug`、`httpr`、`koral`、`std`），像 Rust crate / npm package。**模块全名全程无 `.`**，就是 `ident/ident/ident`；`/` 只用于分隔模块子路径。

> `.` 唯一的出现处是 `modules` 的 key `"."`（§5.2），那是 manifest 记法、不是模块名。

> **为什么不用倒序域名（`com.kulice.koral`）？**
> 因为**名字不承担唯一性**——身份是 `source`（§5.3）。既然如此，名字就只该为可读性服务：
>
> | | 单名 | 倒序域名 |
> | --- | --- | --- |
> | 源码长度 | 短 | 长 |
> | 词法 | 纯 `ident/ident` | 首段要容 `.` |
> | 唯一性 | 不管（`source` 管） | 名义上管，但**不自证** |
>
> 倒序域名看似自带唯一性，其实不然——`com.google.guava` 谁都能声明，除非 registry 验证域名（Maven Central 就是这么做的）。**要验证就得有 registry**，而我们的身份已经交给 `source` 了，没必要再让名字背这个包袱。
>
> Go 之所以用路径，是因为它**没有中央 registry**，路径必须兼作身份；Rust/npm/PyPI 有 registry，所以用单名。**Koral 把身份交给 `source`，所以两边的好处都能拿：名字短，且不需要 registry。**

| | 包名 | 包 / 模块边界 | 模块子路径 |
| --- | --- | --- | --- |
| Go | 域名式长路径 | 不可见（靠网络 + build list 猜） | `/` |
| **Koral** | **单段标识符** | **第一个 `/`** | `/` |

```text
httpr/conn/json
└─包名┘└─子路径─┘
      ↑ 第一个 /
```

#### 2.2 边界为什么唯一

| 约束 | 推论 |
| --- | --- |
| 包名**单段，不含 `/`** | 边界只可能在 `/` |
| 子路径的段也是标识符，**不含 `.`** | 段之间不会混淆 |

⇒ **第一个 `/` 就是包 / 模块边界**，零启发式、零查表。模块全名是纯 `ident/ident` 序列。

#### 2.3 与 Go 的关键差别

Go 的 import path 是扁平字符串（`github.com/kulics/koral/compiler/parser`），`/` 既分隔域名段又分隔模块段，所以边界看不出来。Go 只好：

1. **下载期问网络**：`GET ...?go-get=1` 拿 `<meta name="go-import" content="github.com/kulics/koral git ...">`，meta 明说 module root；
2. **编译期查 build list**：取最长 module path 前缀，剩下的是包目录。

代价是**同一个字符串在不同 build list 下可能切在不同位置**。Koral 的包名是单段标识符，边界写在字符串里。


### 语法 —— 原文「3. 语法」（2026-10-24 重写）

```koral
using "./helpers.koral";                       // 合并：目标模块并进当前模块
using "std/io" { };                            // 导入：什么都不带（惰性占位）
using "std/io" { Reader, Writer };             // 导入：白名单
using "std/io" { Reader as IoReader };         // 导入：别名
using "std/io" { ... };                        // 导入：全部
using "std/os" { Config as OsConfig, ... };    // 导入：全部，个别改名
using "std/os" { !Config, ... };               // 导入：全部，排除个别
```

**操作由有无括号决定，不由路径形状决定。**

| 形态 | 操作 | 边界 |
| --- | --- | --- |
| `using "spec";` | **合并**——目标模块并进当前模块 | **消掉** |
| `using "spec" { … };` | **导入**——取目标模块的名字 | **保留** |

**语义根据是硬的：过滤器只在跨边界时才有意义。** 合并是「成为我的一部分」，没什么可挑的；
导入是「从它那里拿」，才有成员面可挑。括号不是装饰，它就是「边界还在」的记号。

这条切分同时卸掉了旧设计的一个语义双载：旧的 `using "x";` 既表示「合并文件」又表示「导入
模块全部成员」，**同一个写法两个操作**，全靠字符串形状区分。现在裸形式只表示合并、括号形式
只表示导入，两件事各归各，判据在文法层而不在字符串字面量里。

> **取舍动机**（项目目标：生成友好 / 审阅友好）：操作由**文法形状**表达，生成器没有
> 「该写哪种」的选择题，审阅者看一眼括号就知道边界在不在。相应地**不设** `{ * }`、`{ .. }`、
> 裸名文件合并、`hide` / `except` 关键字等并行写法。

#### 3.1 specifier：目标在哪，与操作无关

| specifier | 指什么 |
| --- | --- |
| `./x.koral`、`../y/z.koral` | **本地模块的入口文件**（相对当前文件解析，允许 `.` / `..`） |
| `pkg`、`pkg/sub` | **已登记模块**（经 `dependencies` 的 key + `modules`，§4） |

- 目标永远是**模块**（单文件模块也是模块）；specifier 只回答「它在哪」。
- 本地路径必须以 `.koral` 结尾，显式指出入口文件——**不引入目录推断**，模块边界由入口
  文件指明，不从目录猜（[`name-resolution.md`](name-resolution.md) 硬规则）。
- **未登记的本地模块 → 相对路径；已登记的 → `package[/subpath]`，不许用路径。**
  一个目标只有一种写法（公理 6）。路径指向已登记入口时报错并给名字。

#### 3.2 合并（原「文件合并」）

```koral
using "./helpers.koral";        // 路径拼写：合并单文件模块
using "mypkg/util";             // 名字拼写：合并本包的已登记模块
```

把目标模块的**整个合并闭包**并进当前模块，边界消掉。它不是外部单元依赖、不是包导入、
不是子模块声明、不是别名机制。

约束：

- **合并只在包内。** 目标必须是**本包**的模块：被并文件换上本包的身份，其
  `module_private` 成为本模块的——这套封装只对**自己包里的代码**合法。别的包的模块
  只能导入（`{ … }`），永远不能合并；包边界就是合并停下的地方（§1「悬崖在包边界」）。
  无所属包的裸文件编译没有包边界，目标是已登记模块时同样拒绝。
- 路径拼写按当前文件所在目录解析，必须以 `.koral` 结尾；名字拼写写已登记模块的全名。
  两种拼写都是合并，差别只剩位置，不是机制；
- **不允许与 `{ … }` 结合**——合并就是全部，无从挑选；
- **被合并的模块不得再被导入**（§7 不变量）；
- 合并传递闭包 = 模块的文件集。

> **旧名「文件合并」已废。** 它暗示「目标是文件」，而目标其实是模块——单文件模块只是
> 最小尺寸。概念统一到「模块合并」后，`./x.koral` 与 `pkg/sub` 的差别只剩位置，不是机制。

#### 3.3 导入清单

六种形态，构成一个集合代数：

| 形态 | 名字面 | 用途 |
| --- | --- | --- |
| `{ }` | ∅ | **惰性占位**——不绑名、不带方法面（同 Go 的 `import _`） |
| `{ a, b }` | {a, b} | 白名单 |
| `{ a as b }` | {a→b} | 别名 |
| `{ ... }` | U | 全部可见成员 |
| `{ a as b, ... }` | U 中 `a` 改拼作 `b`，其余全收 | 全量 + 改名 |
| `{ !a, !b, ... }` | U \ {a, b} | 全量 + 排除 |

```text
import-list  ::= "{" "}"                                    // 惰性
               | "{" "..." "}"                              // 全量
               | "{" import-item ("," import-item)* "}"     // 白名单
               | "{" rename-item ("," rename-item)* "," "..." "}"   // 全量 + 改名
               | "{" "!" name ("," "!" name)* "," "..." "}" // 全量 + 排除
import-item  ::= name ("as" name)?
rename-item  ::= name "as" name
```

约束：

1. **`!` 只出现在带 `...` 的清单里**，且**不得与正面条目混写**——`{ !a }` 与 `{ a, !b, ... }`
   皆报错。`...` 明确基集是全集，`!` 只做减法；
   **两条轴不组合，「全量、改一个、排除一个」（`{ a as b, !c, ... }`）不提供**——
   一张清单一个轴换来整套代数一行可判，而同一模块每文件只准一条 `using`，
   写两条也拼不出组合。将来真有需求，出路是放开混写，不是加第二条 `using`；
2. **`hide` / `except` 一律不设**——为一个低频形态占一个关键字不值（见「替代方案」）；
3. **别名必须与被引标识符的大小写类一致**——`Reader as IoReader` 合法，`Reader as reader` 报错；
4. `{ a as b, ... }` 里点名的条目从 U 取出并改写拼写，`...` 是 U 减去点名的那些——
   **不重不漏**。它替换的是「为了改一个名字把 49 个名字列全」这条笨路；
5. `{ }` **合法且惰性**。它是改代码时的占位符：重构中途不必删行、不必让 lint 吵。
   它**不**绑名字，也**不**带方法面（§3.4）。

**为什么黑名单值得做**：Koral 的全局函数是扁平的（`read_file`、`open_file` 是自由函数，
不是 `fs::read_file`），撞名压力比 Rust / Go 大；`std/os` 已导出 50 个名字、`std/math` 38 个。
「全量减去撞的那两三个」会比在别的语言里常用。真实的排除清单是 1–3 项，不是 20 项，
所以 `!` 的字形重量在长清单里糊掉的顾虑不成立。

**`!` 在 Koral 没有第二个岗位**（逻辑取反是 `not`、不等是 `!=`、强解包会破坏公理 9 的
「错误从表达式里走」、模式取反破坏 `when` 穷尽性）。它要么在这里干活，要么该从三个前端的
lexer 里删掉——**「已词法化、无产生式」的中间态是纯负债**，不允许保持。

#### 3.4 方法面：inherent 跟着值走，trait 跟着 trait 名走

`using` 带进来的是两样东西：**名字**（清单挑的）与**方法面**（可派发的 `given` 方法）。
后者只跟**被点名的 trait** 与**值本身**走，**不跟模块走**：

| 调用形态 | 准入 |
| --- | --- |
| `x.m(…)`，`m` 来自 `given X { … }` | **无**——有 `X` 的值即可 |
| `x.m(…)`，`m` 来自 `given X as T { … }` 或 `given T { … }` | **`T` 在作用域内** |
| `X.m(…)`（关联 / 限定形式） | **`X` 在作用域内** |

> **点名类型不带来任何 trait 方法。点名 trait 在所有实现类型上打开它的方法。**

这就是 Rust 的规则。判据是硬的，两处实测（rustc 1.88）：

- `pub struct File` 与 `impl Read for File` 同在 `library/std/src/fs.rs`（115 行 / 1308 行），
  **同文件同模块**；`use std::fs::File;` 后调 `f.read()` 仍然 E0599
  「trait `Read` … is implemented but not in scope; perhaps you want to import it」；
- 最小反例：`S`、`T`、`impl T for S` **全在同一模块**，外模块拿 `S` 的值不 import `T`，
  `s.m()` 同样 E0599。

**「同模块的 `given X as T` 白送」被明确否掉**（见「替代方案」）：它会让同一个 trait 方法
在不同接收者上准入不同、让 impl 挪文件改下游、让读清单判不了，而换来的只是省一行
`using`——那一行编译器会直接写给你。

**`T` 在作用域内**指下列之一：

1. `T` 在当前文件所属模块里声明——**合并进来的也算**（合并就是同模块）；
2. `{ T }` 或 `{ T as A }` 显式导入。**改名仍然算**：`{ T as A }` 让 `A` 可写、`T` 不可写，
   但 **trait 本身在作用域内**，它的方法照旧用自己的名字调（Rust：`use std::io::Read as R;`
   仍允许 `f.read()`）；
3. 从 `T` 所在模块批导入且未被 `!` 排除（`{ ... }`、`{ !a, ... }`）；
4. prelude（`std` 主模块的 trait）；
5. 出现在**当前声明的泛型界**里（`[T IntoPath]`、`[T Ord and Hash]`）——**含该界的超 trait**。

**不算的**：`{ }` · 导入了模块里别的名字（`{ env }`）· **导入了类型（`{ Path }`）** · 什么都没写。

第 5 条与其余四条刻意不同：界是写在**当前声明**里的，`fn go[T Leaf](x T) = x.r() + x.l()`
在 `Leaf: Root` 下两个方法都能调，而**具体接收者**只导入 `Leaf` 时 `x.r()` 不行——
Rust 一样（`use a::Sub;` 之后 `x.b()` 仍是 E0599）。界是「我声明了这个约束」，
导入是「我拿了这个名字」，两件事。

推论：

- **合并 = 方法面全开**。`using "./x.koral";` 之后 x 的 trait 都是同模块，名字与方法一起到。
  合并/导入的对比因此更硬：一个是全开，一个按清单；
- **impl 全局注册、门在 trait**。只要模块进了构建图，它的 `given` 就是候选；能不能调只看
  trait 在不在作用域。所以 `std/os` 的 `given String as IntoPath` 被别的文件加载了，
  也漏不到没点名 `IntoPath` 的文件里——prelude 泄漏不存在；
- **诊断必须给补丁**。非 inherent 方法找不到时，报错要写出
  `Trait 'T' provides it but is not in scope; import it with using "…" { T };`。
  对齐 Rust 的 E0599 help——不给的话读者看见一个明明存在的方法被说成不存在。

规则：

1. **一个拼写只有一个所有者**，第二个**不同**声明撞同一个拼写才是冲突；同一声明到两次不算
   （身份是声明，不是名字）。矩阵（用户向镜像在 `../guide/document.md`「Name Collisions」）：
   与本模块顶层声明撞名、与本文件另一 import 的**不同**声明撞名、与 prelude
   （`std` 主模块的 `List`、`Eq`、`Clone`…）撞名——三者皆报错；同一声明经两条路径到达、
   函数内局部 `let` 遮蔽——两者皆合法。消歧用 `as`（改名）或 `!`（排除）；
2. **同一模块在同一文件内只 `using` 一次**：`using "std/io" { ... };` 与 `using "std/io" { Reader };`
   并存报错。跨文件不重复——各文件各自 `using`；
3. **模块名不绑定为命名空间**——导入 `Reader` 后写 `Reader`，不写 `io.Reader`
   （见「替代方案」：上一代就是限定访问，被整套拿掉）；
4. **`using` 必须位于文件顶部**，在任何其它顶层声明之前；
5. 导入绑定是**文件作用域**，不 re-export；`public using` 报错。

> **`{ }` 与 Go 的 `import _` 对齐**：绑名字 ❌、副作用 ❌（Koral 无此机制）、
> 用途是**改代码时的占位符**。按 §3.4 它也不带方法面——**真正惰性**，这正是它的定义。

> 📎 **本节规则在 `../guide/document.md` / `document-zh.md` 的「Using Declarations」里各有一份
> 用户向镜像**。改任何一条要三处同批改。


### 解析 —— 原文「4. 解析」

**源码 `using` 有两条路，由 specifier 形状分流（§3.1）**：

```text
resolve(spec):
  if spec 以 "./" 或 "../" 开头:            # 本地模块
      按当前文件目录归一化，允许 "." / ".."
      指到的文件必须以 ".koral" 结尾
      若该入口已在某个模块的 modules 里登记 → 报错并给出应写的 package[/subpath]
      否则以它为入口立一个本地模块（未登记）
      身份 = (本包身份, 入口相对包根的归一化路径)

  else:                                     # 已登记模块
      切在第一个 "/"：
          head = "/" 之前的部分      （无 "/" 时 head = 整串）
          tail = "/" 之后的部分      （无 "/" 时 tail = ""）

      head 必须是已注册包名，否则报「未知包名」
          已注册包名 = 本包的 package + 各依赖的源码名（dependencies 的 key）+ 保留名 "std"

      在 head 对应包的 modules 里查**包内名**：
          tail == ""  → 查 key "."
          tail != ""  → 查 key = tail
      查不到 → tail 为空则「该包没有主模块」，否则「模块不存在」
```

**一个目标只有一种写法。** 本地未登记模块走路径，已登记模块走 `package[/subpath]`——
路径若指到已登记入口就报错，不给第二种拼写（公理 6）。

> **注意查的是包内名，不是模块全名。** 消费方写 `http/conn`，被依赖包的 key 是 `conn`
> （它自己写作 `httpr/conn`）。解析时按子路径 `conn` 命中，与它内部怎么拼无关。
>
> **`.` 只出现在 `modules` 的 key 里**（指代本包主模块），源码不写 `.`——主模块在源码里就是包名本身。
>
> **每个包用自己的表解析自己的源码。** 编译 `httpr` 的文件时用 `httpr` 自己的 `package` 与
> `dependencies`，与消费方给它起什么名字无关。这正是「包级」而非「工程级」的作用域——
> 所以传递依赖的源码不会因为消费方改名而失效。

**歧义性**（载入期全部定案——报错或键唯一，绝不静默歧义）：

| 情况 | 会不会冲突 | 原因 |
| --- | --- | --- |
| 包名 vs 包名 | ❌ | `dependencies` 的 key 在本工程内唯一 |
| 两个 `source` 抢一个 key | ❌ | JSON 键天然唯一，解析器看不见重复键（§7 错误 23） |
| **一个 `source` 抢两个 key** | ❌ | **载入期报错**——否则同一模块有两种拼写，破坏「一工程一写法」 |
| 包名 vs 子路径 | ❌ | 引用一律带包名，源码无裸子路径写法 |
| **本包源码名 vs 依赖源码名** | ❌ | `dependencies` 的 key **不得等于本包的 `package`** |
| `std` vs 用户包名 / 依赖 key | ❌ | `std` 保留，二者都不得占用 |


### manifest —— 原文「5. manifest」

#### 5.1 字段（4 个）

| 字段 | 含义 | 必填 |
| --- | --- | --- |
| `package` | **本包的源码名**——自引用前缀，也是消费方的默认源码名 | ✓ |
| `version` | 版本 | ✓ |
| `modules` | **对外命名表**：包内名 → { entry, links }（见 5.2） | — |
| `dependencies` | **源码名 → { source, version }** | — |

> **`package` 不是身份。** 身份是 `source`（§5.3）。`package` 只回答「源码里管这个包叫什么」，
> 所以**不必全局唯一**——两个包可以都叫 `httpr`，只要 `source` 不同。
> 包自己**不声明** `source`：位置由消费方的 `dependencies` 决定（同 npm / Zig）。
>
> 所有主流语言都要求写这个名字，但角色不同：
>
> | | Rust `name` | Go `module` | npm `name` | Zig `name` | **Koral `package`** |
> | --- | --- | --- | --- | --- | --- |
> | 自引用 | ✗ `crate::` | ✓ 全路径 | ✓ | ✗ 相对 | **✓** |
> | 是身份吗 | ✓ | ✓ | ✓ | ✓ | **✗ 身份是 `source`** |
>
> 取 npm 的用法（自引用 + 默认名），但把身份让给 `source`。

> 没有 `name`（与 `package` 重复）、没有顶层 `entry`（默认目标 = 主模块）、没有 `module`（与 `modules` 重复）、没有 self-`as`（自引用就写 `package`）。

**默认构建目标 = 主模块**（`modules` 里 key 为 `"."` 的那个）。没有主模块时用 CLI 指定。

`modules` 每条的字段：

| 字段 | 含义 |
| --- | --- |
| `entry` | 模块入口文件，**相对包根**（`conn/conn.koral`）；同模块的其余文件用模块合并并入 |
| `links` | 传递给链接器的库名（如 `["m", "pthread"]`），沿用现状，本次不变 |

**没有 `requires`**：模块图从 `using` 派生（§5.4）。

#### 5.2 `modules` 是对外命名表，不是模块清单

**这是本次的角色重定义。** 旧设计里 `modules` 是模块清单——本地每个模块都得登记，
否则用不了；「想让一块代码变成独立单元」与「给兄弟文件用几个名字」之间是一道悬崖。

新角色：**`modules` 回答「外部包能按什么名字引用我」，外加 `links`。**
本地模块不必登记——走相对路径（§4）。登记的动机只有两个：

1. 要让外部包按名字引用它；
2. 要给它挂 `links`。

于是梯度是连续的，悬崖只出现在**包边界**——那正是该有悬崖的地方（分发单元、版本、
身份都从那里开始）：

| 规模 | 写法 | 动 manifest 吗 |
| --- | --- | --- |
| 一个文件给兄弟几个名字 | `using "./util.koral" { a, b };` | **否** |
| 几个文件合成一个单元 | `util.koral` 内 `using "./util_more.koral";` | **否** |
| 同包内互相引用 | `using "./util.koral" { a };` | **否** |
| 要对外可命名 | `modules` 里给它一个 key | 是 |
| 要 `links` | `modules` 里写 | 是 |

与 `public` / `package_private` 是同一条边界上的两层，概念一致：manifest 说的不再是
「我有哪些模块」，而是「我对外露出哪些名字」。

`modules` 的 key 是模块在**包内**的名字：

| | 写法 | 例子 |
| --- | --- | --- |
| 主模块 | `.` | key `"."` |
| 子模块 | `子路径` | key `"conn"`、`"compiler/parser"` |

`entry` 是相对包根的文件路径（`conn/conn.koral`），与 key 同视角。

> **`.` 是 npm `exports` 的先例**（`exports: { ".": "./index.js", "./conn": "./conn.js" }`）。它只是 manifest 记法，不是源码语法——源码里主模块就是「包名本身」。

#### 5.3 `dependencies`：key 即源码名，source 即身份

```json
"dependencies": {
  "http": { "source": "https://github.com/me/httpr", "version": "^0.4" },
  "slug": { "source": "path:../slug",              "version": "^1.2" }
}
```

| 字段 | 是什么 |
| --- | --- |
| **key** | **源码名**——`using "http/conn"` 里写的就是它 |
| **source** | **纯获取位置，同时是身份**（URL / git 仓库 / `path:`）。**不含 ref**——tag / commit 不写在这里 |
| **version** | **semver 约束**（区间，如 `^0.4`）。精确版本由 `koral.lock` 钉住 |

**三件事分开**：

| | 是什么 | 谁保证 |
| --- | --- | --- |
| 源码名 | `using` 里写什么 | `dependencies` 的 key |
| 身份 | 这是不是同一个包 | `source` |
| 获取位置 | 去哪下载 | `source` |
| 精确版本 + 内容哈希 | 用的是哪一版、有没有被篡改 | **`koral.lock`**（§5.5） |

> 身份与获取位置**故意合一**（同 Go 的 module path）：一个 URL 天下唯一，不必再有第二套标识。
> 源码名是独立的第三件事——所以去中心不影响源码可读性。

- **`path:` 是相对路径，不是稳定身份**：它相对**声明它的 manifest** 解析。lockfile 里存的是**相对 lockfile 归一化后**的路径（或绝对路径），否则两个包写的 `path:../slug` 会指向不同目录。`path:` 依赖视为**本地开发依赖**，不参与跨工程共享；
- **改名就是换 key**：`"http": { "source": "…/httpr", "version": "^0.4" }`，不需要额外的 `package` 字段；
- **包自己声明的 `package` 只用于它自己的源码自引用**，不参与消费方解析（npm / Zig 的做法）；
- 两个不同 `source` 抢同一个 key → manifest 载入期报错；
- **惯例**：不改名时 key 取该包的 `package`（`"httpr": { "source": "…/httpr", … }`），这样各工程拼写一致、源码可复制。这只是约定，不强制——消费方总要显式写 key。

##### 5.3.1 模块身份 =（包身份，入口在包内的位置）

**包身份是 `source`；模块身份是 `source` 加上入口文件相对包根的归一化位置。**
`modules` 的 key 是**对外拼写**，不是身份的一部分。

推论：

- **改依赖 key 不改 ABI 符号。** 符号看 `source` + 目标自己的入口位置，消费方改名碰不到它。
  旧设计里 codegen 的 `path_segments` 取本地源码名，换 key 就改符号——那是 bug 的形状，
  本条把它消掉（原「风险与未决」第 4 条即此，现已关闭）。
- **移动入口文件会改内部符号**，但那在包自己控制之内，可接受；要稳定的对外 ABI，就把该
  模块登记进 `modules` 并**不要动它的 entry**。
- 两个包都有 `conn/conn.koral` 不撞——`source` 不同。
- 未登记的本地模块与已登记模块**同一条身份规则**，不新增第二套。

> 为什么不取「模块全名」作身份：那里面含消费方起的源码名，换 key 就变——身份会跟着
> 别人的命名走。为什么不取 `modules` 的 key：未登记的本地模块没有 key，而它们同样需要
> 身份。入口位置是**模块自己说了算**的那一个量，两类模块共用。

#### 5.4 模块图：从 `using` 派生

**`modules` 里没有 `requires`。** 模块依赖图由该模块所有文件的 `using` 语句并集决定：

```text
module_deps(M) = { 每条 using "…" { … } 指到的模块 }   // 合并不跨模块边界，不进图
```

由它得到构建排序、可达性。**一处真相**，不会出现「manifest 说依赖 X、源码没用」这类漂移。

两条推论：

- **模块图必须无环**——有环报错并列出环。模块是符号导入单元，循环导入意味着两边都在用对方尚未完成的符号，没有清晰语义；
- **`links` 沿模块图传递**——A `using` B 且 B 有 `links: ["m"]`，则最终链接带上 `-lm`。`links` 是 C 链接需求，跟着代码走。

> **没有「依赖但不 import」的场景**：Koral 模块导入的就是符号，不 import 就用不上。
> 若日后出现（例如只为拉入 `links`），再加一个显式字段——那是新增能力，不是补漏。
>
> **唯一的例外是 `std` 主模块（prelude，见 §5.4.1）**——它是编译器提供的基座，
> 不是从 `using` 派生出来的边。

##### 5.4.1 `std` 主模块是 prelude

**`std` 的主模块对非 `std` 模块是隐式 prelude**：编译器把它编进来并放进作用域，
不需要写 `using`。其余模块——包括 `std/io`、`std/time`——一律要显式导入。

这是刻意的，不是实现走样：

- `println`、`Duration`、`List` 这些是每个程序都要的基座；
- 要求每个文件各写一行 `using "std" { ... };` 不增加任何信息；
- §6.4 的依赖图把主模块画成「基础层」，与 prelude 读法一致。

规则边界：

| | 是否在作用域里 |
| --- | --- |
| `std` 主模块的符号（`println`、`Duration`…） | ✅ 非 `std` 模块隐式可见 |
| `std/io`、`std/time` 等子模块的符号 | ❌ 必须显式 `using` |
| `std` 子模块文件用 `std` 主模块的符号 | ❌ 要写 `using "std" { ... };`（它们自己就是 `std` 的一部分） |

**注意形态**：`using "std" { ... };` 是**导入**（带上 prelude 名字），不是合并。
裸形式 `using "std";` 在新规则下是**合并**——把整个 `std` 主模块吞进当前模块，几乎
永远不是你想要的。`std` 自己的 76 个子模块文件要写的是 `{ ... }` 形态。

> **「Import it explicitly」诊断的两条边界**：诊断引用的写法必须是读者**真能写**的
> 现行拼写；该诊断只对**调用方自己写过**的名字发出——经被调方签名传来的名字不再要求导入。

#### 5.5 `koral.lock`：整棵依赖树

> ⚠️ **本节是设计稿，尚未实现。** `koral.lock` / `koral lock` / `koral update` 目前只出现在
> 错误文案里，编译器没有读写 lockfile 的实现。本节描述的是目标形态。

根工程生成、**提交进版本库**，记录解析后的**完整依赖树**：

```json
{
  "version": 1,
  "packages": {
    "https://github.com/me/httpr": {
      "version": "0.4.1",
      "hash": "sha256-…",
      "dependencies": { "slug": "path:../slug" }
    },
    "path:../slug": {
      "version": "1.2.0",
      "hash": "sha256-…",
      "dependencies": {}
    }
  }
}
```

- **key 是 `source`**（身份），值含**精确版本**、**内容哈希**、以及该包自己的依赖解析结果；
- **覆盖全树**——直接依赖与传递依赖都钉住（同 Go `go.sum`、npm `package-lock.json`、Nix `flake.lock`）；
- **首次生成**时抓取并记录哈希，**其后每次构建校验**，不匹配即报错；
- 生成锁文件是一次显式操作（`koral lock` / 首次 build），刷新需显式（`koral update`）；
- **`std` 不进 lockfile**——它是 built-in，随工具链分发，身份即工具链版本。


### 错误条件 —— 原文「7. 错误条件」

#### 合并

1. 本地路径未以 `.koral` 结尾；
2. 目标 `.koral` 文件不存在；
3. 与 `{ … }` 导入列表同时出现（合并就是全部，无从挑选）；
4. **目标不在本包**——跨包裸合并/跨包路径合并都拒绝，指路 `{ … }` 导入（§3.2）。

#### 导入清单

5. `!` 出现但清单里没有 `...`（`{ !a }`）；或 `!` 与正面条目混写（`{ a, !b, ... }`）；
6. `{ … }` 里同时出现 `hide`（不设该关键字）——报错并指路 `!`；
7. 模块全名不是合法的 `ident/ident` 序列（空段、`.`、`..`、非法字符）——若写了 `using ".";`，提示「主模块在源码里写包名，`"."` 只是 manifest 记法」；
8. **未知包名**——若它像旧的裸名文件合并写法，给出迁移提示（§8）；
9. 包名命中但模块不存在；
10. 包名命中、子路径为空，但该包没有主模块（列出该包已声明的模块）；
11. **本地路径指到一个已在 `modules` 里登记的入口**——报错并给出应写的 `package[/subpath]`（一个目标一种写法）；
12. 撞名矩阵命中：import 名与本模块顶层声明、与本文件另一 import 的不同声明、与 prelude 撞名
    ——皆报错；同一声明到两次不报（见 §3.3）。白名单撞名提示「用 `as` 改名」，
    全量清单撞名提示「用 `as` 改名」或「用 `!` 排除」；
13. **同一模块在同一文件内被 `using` 多次**；
14. **`using` 未位于文件顶部**；
15. **模块图有环**（列出环路）。

#### 模块归属（不变量）

16. **一个模块被合并进两个模块**——同一份源码进两个构建单元，两套身份；
17. **被合并的模块又被导入**——合并消掉了边界，它已不是独立模块；
18. **包内有源文件不被任何模块的合并闭包覆盖**（孤儿文件）——它不在编译单元里，
    不参与任何检查，是纯负债。

> 这三条是同一条不变量的三个面：**每个源文件恰好属于一个模块的闭包；一个模块要么独立、
> 要么被合并进恰好一个模块，二选一。** 旧设计只防「entry 被两个模块声明」，没防
> 「文件被两个模块合」与「文件谁也不认领」。

#### manifest

19. 包名不是合法标识符（含 `/`、大小写、数字开头、是保留字）；
20. `modules` 的 key 既不是 `.` 也不是合法子路径；
21. **同一模块 key 重复**不是可检查的错误条件：`modules` 是 JSON 对象，键天然唯一，解析器看不见重复键；key 只允许 `.` 与合法子路径，两个不同的合法 key 必然是两个模块，不存在别名（`io/` 会被 20 当非法 key 拒掉，不是 `io` 的另一种拼写）。真正可查的是 20；
22. **`entry` 文件被两个模块声明**，或不在包根内、或不存在；
23. **同一源码名被两个依赖声明**不是可检查的错误条件，同 21（JSON 键天然唯一；§4 歧义表「包名 vs 包名」一行即此）。真正要防的是 24（一个 `source` 两个 key），那条可查；
24. **一个 `source` 被两个 key 声明**（同一模块会有两种拼写）；
25. **`dependencies` 的 key 等于本包的 `package`**（自引用与依赖撞车）；
26. **`dependencies` 的 key 或 `package` 占用保留名 `std`**；
27. `dependencies` 条目缺 `source` / `version`，或格式非法（`source` 含 ref、`version` 不是 semver 约束）；
28. **模块合并成环**（`a.koral` ↔ `b.koral`）。

#### 构建期

29. **`koral.lock` 与 manifest 不符**（树里有 manifest 未声明的包 / 版本不满足约束）；
30. **哈希校验失败**（lockfile 记录的 hash 与实际抓取内容不符）。


### 包管理机制 —— 原文「11. 包管理机制」

命名与语法已经闭环；本节是**包管理器本身**的机制决定。

#### 11.1 三件事的分工（已定）

| | 是什么 | 写在哪 |
| --- | --- | --- |
| 源码名 | `using` 里写什么 | `dependencies` 的 key |
| **位置 / 身份** | 去哪下载、是不是同一个包 | `dependencies[*].source`（**不含 ref**） |
| **版本约束** | 能接受哪一版 | `dependencies[*].version`（semver 区间） |
| **精确版本 + 哈希** | 用的是哪一版、有没有被篡改 | **`koral.lock`**（覆盖全树） |

`source` 只管位置，`version` 只管约束，两者不重叠；ref（tag / commit）不写进 manifest，由 lockfile 的解析结果决定。

#### 11.2 完整性覆盖全树（已定）

`koral.lock`（§5.5）记录**整棵依赖树**的 `source` + `version` + `hash`，根工程生成并提交。

| | 机制 | 消费方首次抓取就校验 | 覆盖范围 |
| --- | --- | --- | --- |
| Zig | `build.zig.zon` 的 `.hash` | ✓（哈希在 manifest） | 直接依赖 |
| **Koral** | **`koral.lock`** | ✗（首次生成时记录） | **全树** |
| Go | `go.sum` | ✗ | 全树 |
| npm | `package-lock.json` | ✗ | 全树 |

> Koral 与 Go / npm 同档：**首次生成 lockfile 时不校验，其后每次校验**。
> 好处是哈希只需在根工程写一次、覆盖全树；代价是新增依赖的第一次抓取无保护。

哈希只活在 lockfile 里（manifest 不设 `dependencies[*].hash`），一处真相。

#### 11.3 模块图从 `using` 派生（已定）

`modules` 里没有 `requires`（§5.4）。一处真相，不存在「manifest 说依赖 X、源码没用」的漂移。

#### 11.4 尚未覆盖的包管理能力

以下暂缺，**本次不做**，是否进 v1 需另行定：

- **dev-dependencies**（只供测试 / 示例用）
- **workspace / monorepo**（多包共用一份 lockfile）
- **feature / optional dependency**
- **版本区间与升级策略**（含传递依赖版本冲突的裁决，见 §10.2）


## 兼容与旧写法 —— 原文「8. 迁移」

**不设兼容层。** 旧写法直接报错，错误信息把该写什么指清楚。

`using` 的裸名是**包名**，不是文件路径：

```text
error: Unknown package name "utils"
  A name in 'using' is a package name: this package's 'package', one of its
  'dependencies' keys, or the reserved "std".
```

想做模块合并写 `using "./utils.koral";`；想导入模块，先在 `koral.json` 的
`dependencies` 里声明该包（未登记的本地模块直接写相对路径即可）。`{ .. }` 这类
「导入全部」的旧写法不存在：导入全部可见符号写 `using "std/io" { ... };`。

**风险窗口**：裸名写法落到模块查询。若恰好存在同名包（如 `dependencies` 里把某包
改名成 `utils`），会**静默解析到无关包**。这是「裸名是包名」这条规则的固有代价。

**演进**：

1. `using "x"` 一度兼做裸名文件合并与模块导入，靠有无 `./` 区分。两者语义不同、
   错误也不同，于是拆成两条：合并强制 `./` + `.koral`，裸名一律是包名。
2. **2026-10-24 二次拆分**：操作不再由路径形状定，改由**有无括号**定（§3）。
   裸形式只表示合并、括号形式只表示导入，判据从字符串字面量升到文法层。
   代价是旧的 `using "std/io";`（导入全部）要机械迁成 `using "std/io" { ... };`。

## 示例 —— 原文「6. 示例」

### 6.1 单模块包

```json
{
  "package": "slug",
  "version": "1.2.0",
  "modules": {
    ".": {
      "entry": "slug.koral",
      "links": []
    }
  }
}
```

```koral
// slug.koral
using "./rules.koral";        // 合并
using "std" { ... };
using "std/text" { ... };

public let make_slug(input String) String = { ... }
```

```koral
// 别处
using "slug" { make_slug };
```

**一个包、一条 `"."`、一个名字。** 与多模块写法完全一致，无特殊规则。

### 6.2 主模块 + 子模块

```json
{
  "package": "httpr",
  "version": "0.4.1",
  "modules": {
    ".":    { "entry": "client.koral",    "links": [] },
    "conn": { "entry": "conn/conn.koral", "links": [] },
    "json": { "entry": "json/json.koral", "links": [] },
    "form": { "entry": "form/form.koral", "links": [] }
  },
  "dependencies": {
    "slug": { "source": "path:../slug", "version": "^1.2" }
  }
}
```

```koral
// httpr/json/json.koral
using "httpr" { Request };        // 本包主模块
using "httpr/conn" { Conn };      // 本包子模块
using "slug" { make_slug };       // 跨包
using "std" { ... };
using "std/json" { Value };
```

### 6.3 无主模块的包

```json
{
  "package": "koral",
  "version": "0.1.0",
  "modules": {
    "compiler":        { "entry": "compiler/compiler.koral",     "links": [] },
    "compiler/lexer":  { "entry": "compiler/lexer/lexer.koral",  "links": [] },
    "compiler/parser": { "entry": "compiler/parser/parser.koral", "links": [] }
  }
}
```

```koral
using "koral/compiler/parser" { Parser };   // ✓
using "koral";                        // ✗ 该包没有主模块
```

### 6.4 标准库 `std`

[std/koral.json](../../std/koral.json) 共 14 个模块：主模块（key `"."`）+ 13 个子模块
（`container`、`hex`、`io`、`json`、`math`、`net`、`os`、`proc`、`rand`、`sync`、`text`、
`time`、`async`）。源码侧的写法是包全名 `package[/subpath]`：

| 模块全名 | manifest key | 源码 |
| --- | --- | --- |
| `std` | `.` | `using "std" { ... };` |
| `std/io` | `io` | `using "std/io" { Reader };` |
| `std/json` | `json` | `using "std/json" { ... };` |
| `std/container` | `container` | `using "std/container" { ... };` |

```json
{
  "package": "std",
  "version": "0.1.0",
  "modules": {
    ".":         { "entry": "std.koral", "links": [] },
    "container": { "entry": "container/container.koral", "links": [] },
    "hex":       { "entry": "hex/hex.koral", "links": [] },
    "text":      { "entry": "text/text.koral", "links": [] },
    "math":      { "entry": "math/math.koral", "links": [] },
    "io":        { "entry": "io/io.koral", "links": [] },
    "json":      { "entry": "json/json.koral", "links": [] },
    "time":      { "entry": "time/time.koral", "links": [] },
    "async":     { "entry": "async/async.koral", "links": [] },
    "rand":      { "entry": "rand/rand.koral", "links": [] },
    "sync":      { "entry": "sync/sync.koral", "links": [] },
    "net":       { "entry": "net/net.koral", "links": [] },
    "os":        { "entry": "os/os.koral", "links": [] },
    "proc":      { "entry": "proc/proc.koral", "links": [] }
  }
}
```

模块依赖方向（主模块是基础层；下表从各模块的 `using` 派生，非手写）：

```text
基础层（只依赖主模块）：container  hex  text  math  io  rand  sync  async
json → math, text        time → text
net  → hex, io, text     os   → io, time      proc → io, os
```

**子模块依赖主模块，主模块不依赖任何子模块**（主模块的 `using` 不指向任何子模块），所以 `using "std";` 不会拉进 IO / 网络等重模块。这张图是**从各模块的 `using` 派生**出来的，不是手写的。

主模块同时是 **prelude**（§5.4.1）：非 `std` 模块不用写 `using "std";` 就能看到它。

`std` 是 **保留包名**（无 `.`、不写进 `dependencies`、随工具链分发于 `KORAL_HOME/std/`），其余规则与普通包完全一致。

### 6.5 消费方

```json
{
  "package": "myapp",
  "version": "0.1.0",
  "modules": {
    ".":      { "entry": "src/main.koral",          "links": [] },
    "models": { "entry": "src/models/models.koral", "links": [] }
  },
  "dependencies": {
    "http": { "source": "https://github.com/me/httpr", "version": "^0.4" },
    "slug": { "source": "path:../slug",              "version": "^1.2" }
  }
}
```

```koral
// src/main.koral
using "./cli.koral";              // 合并
using "myapp/models" { User };    // 本包子模块
using "http" { Client };          // 跨包，被改过名
using "http/json" { to_json_body };
using "slug" { make_slug };
using "std" { ... };
```

注意：

- `httpr` 被换成本地源码名 `http`，本工程只能写 `http/...`；改名就是换 key，没有额外字段；
- `models` 用到了 `slug`，所以它必须在 `dependencies`——**用到就要声明**；
- **身份看 `source`**：`http` 与 `slug` 是两个不同的包，去重与传递依赖合并都不看名字。


## 替代方案 —— 原文「9. 与主流语言对照」

### 上一代模块模型（被整套替换）

**这不是假想方案，是实际跑过的一代，被拿掉了。** 留在 `tests/compiler-cases/` 的化石
（`using Super.A().*`、`Use 'C.bar' to access it`、`models_User` 模块路径前缀 mangling、
`child is imported as file_private by the parent`）与编译器现报的
`Module-prefixed access is not supported` 是它的痕迹。

| 上一代 | 现在 | 为什么删 |
| --- | --- | --- |
| **模块名是命名空间**（`X.ping()`、`C.bar`） | 扁平命名，模块名不绑定 | 一个名字要两条解析路径（先查命名空间再查裸名）；公理 6 的「一种主流表达」被破 |
| **`using "x" as X` 整模块改名** | 只能给单个名字 `as` | 模块名不是命名空间，改它没有所指 |
| **`using Super.A().*`**（父相对 + 批量） | `using "pkg/sub" { … }` | `Super` 引入模块父子关系，而主模块不是「根」——父子是被明确否掉的模型 |
| **`...` / `{ .. }` 批量省略** | 省略 `{ }` 即全部 | 同一语义多个拼写，违反单一拼写纪律 |
| **父模块用 `file_private using` 控制子模块可见性** | 模块之间无父子、无 re-export | re-export 让「谁能看到什么」要沿模块图回溯，局部判不了 |
| **C 符号带模块路径前缀**（`models_User`） | 身份 =（`source`，入口位置） | 前缀取本地源码名，换依赖 key 就改符号 |

**为什么记在这里**：这套东西被替换过一次（公理 7「替换不叠加」），而替代方案里没记，
下一轮评审必然重新问「为什么不给 `io.Reader`」。记下来是一劳永逸的那一步。

### 方法面：不采用「同模块的 `given X as T` 白送」

**否掉。** 初稿 §3.4 写过「点名类型 `X` → `X` 的 inherent 方法 **+ 与 `X` 同模块**声明的
`given X as T` 方法」，理由是「拿到了 `File` 却不能 `read` 像缺了基本功能」。**实测推翻**：
Rust 里 `impl Read for File` 就写在 `File` 自己的文件里，`f.read()` 照样要 `use std::io::Read;`。

| | 「同模块白送」 | **Rust 规则（现行）** |
| --- | --- | --- |
| 同一 trait 方法在不同接收者上 | **准入不同**（`given Path as IntoPath` 在 `std/os`，`Path` 也在；`String` 不在） | 一致 |
| impl 挪个文件 | **下游静默断** | 无影响 |
| 读 `using "std/os" { Path };` | 判不出 `into_path` 能不能用 | 判得出 |
| `given T { … }` 工具块 | 与 `given T` 必然同模块 → 工具方法白送、required 方法不送，**同一 trait 内分裂** | 一致 |
| 规则条数 | 三条准入 | 两条准入 |

「基本功能」由三层吃掉，不由弱化规则吃掉：

| 层 | 准入 | `File` 的例子 |
| --- | --- | --- |
| **inherent** | 有值就行 | `metadata` / `set_len` / `sync_all` |
| **自由函数** | 导入函数名 | `read_file(path)` / `write_file(path, …)` |
| **trait** | trait 在作用域 | `read` / `write` / `seek` |

`read` 不是 `File` 的基本功能，`File` **参与 `Reader` 抽象**才是——所以它是 trait 方法，
`fn copy<R: Reader, W: Writer>(…)` 才能作用在任何东西上。要「读一个文件」用 `read_file`；
要「流式读」说明你正在用 `Reader`，那点名 `Reader` 不是摩擦，是信号。

配套：**诊断必须把该补的 `using` 写出来**（§3.4），否则这条规则的代价就没人付得起。

### 排除导入的拼写

### 排除导入的拼写

**否掉 `hide` / `except` / `hiding` 关键字。** 为一个低频形态占一个关键字不值——那几个词
除这里没有任何作用。**否掉 `as _`**（Scala 的「改名成通配符」）：`_` 是模式通配符，
让它在表达式位当占位符是给它新增第二个含义。

**选 `!`**，理由：

1. 它在 Koral **没有第二个岗位**（逻辑取反是 `not`、不等是 `!=`、强解包破坏公理 9、
   模式取反破坏 `when` 穷尽性）——要么在这里干活，要么该从三个前端删掉 token，
   「已词法化、无产生式」的中间态是纯负债；
2. 过滤清单里 `!` = 非是既有习惯（`.gitignore`、`.dockerignore`、glob 否定）——
   导入清单本来就是名字过滤器；
3. 文法均一：`!a` 前缀修饰与 `a as b` 后缀修饰挂在同一个条目上；
4. 真实排除清单是 1–3 项，「`!` 在长清单里糊掉」的顾虑不成立。

**先例如实记**：排除导入不是业界收敛形状，是少数派特性——Haskell / PureScript 的
`hiding (…)`、Scala 2/3 的 `{ a => _, _ }` / `{ a as _, * }`、Dart 的 `import 'x' hide a, b`。
Rust / Python / Go / ESM / Java / Kotlin / Swift 都没有（Python 由导出方 `__all__` 控制，
Go 干脆没有通配导入）。没有可抄的形状，拼写是自己定的。

### 不采用操作由路径形状决定（旧设计）

旧设计用 specifier 形状（`./` vs 裸名）区分「文件合并」与「模块导入」。**否掉**：
判据藏在字符串字面量里，读者要先读路径形状才知道发生了什么；而两种操作的语义完全不同
（一个消边界、一个留边界）。**改由有无括号决定**——判据在文法层，且语义根据是硬的：
过滤器只在跨边界时才有意义。

### 不采用目录推断模块树

**否掉**（[`name-resolution.md`](name-resolution.md) 硬规则）。模块边界永远由**入口文件**
指明，不从目录猜。`using "./models/models.koral" { User };` 显式写出入口，
而不是 `using "./models";` 去找 `models/models.koral`。

### 不采用模块名作为命名空间（`io.read()`）

**否掉，且是替换而非叠加**——上一代就是这么做的，被整套拿掉（见上）。配套观察：
Koral 里**类型是命名空间**（`String.new` 可以），**模块不是**（`io.read()` 不行）。
扁平命名的代价由命名约定吃掉（`IoError` 而不是 `Error`，因为 `Error` 在 prelude），
收益是公理 2/9 的局部可判断：一个裸名在一个文件里恒指一个声明。

### 对照表

| | Go | npm/Node | Rust | **Koral** |
| --- | --- | --- | --- | --- |
| 分发单元 | module (`go.mod`) | package (`package.json`) | crate (`Cargo.toml`) | **package (`koral.json`)** |
| 构建单元 | package（目录） | 文件 | module (`mod`) | **module（= 入口 + 合并闭包）** |
| 单模块怎么写 | 根 package 路径 = module path | `import "mylib"` → `exports["."]` | crate 根 (`lib.rs`) | **`using "slug" { … };`** |
| 主模块表示 | 路径等于 module path | `exports` 的 `"."` | crate 根 | **`modules` 的 `"."`** |
| 自引用 | 全名 | 按包名 | `crate::foo` | **按包名（已登记）/ 相对路径（未登记）** |
| 身份 = 获取位置 | 是（module path） | 否（registry 名） | 否（registry 名） | **是（`source` + 入口位置）** |
| 改名 | 只改标识符 | `imports` 字段 | `foo = { package = "bar" }` | **换 `dependencies` 的 key** |
| 无 registry 可用 | ✓ `GOPROXY=direct` | ✗ | ✗ | **✓ `source` 是 URL/git/path** |
| 哈希钉住 | `go.sum` | `package-lock.json` | `Cargo.lock` | **`koral.lock`（全树）** |
| 构建图来源 | import 语句 | import 语句 | `mod` / `use` | **`using`（派生）** |
| 依赖声明 | `go.mod` `require` | `dependencies` | `[dependencies]` | **`dependencies`** |
| 全量导入 | 无 | `import *` | `use foo::*` | **`{ ... }`** |
| 排除导入 | 无 | 无 | 无 | **`{ !a, ... }`**（同 Dart `hide`、Haskell `hiding`） |
| 惰性导入 | `import _` | 无 | `use foo as _` | **`{ }`** |
| trait 方法准入 | 无 trait | 无 trait | **trait 在作用域** | **trait 在作用域（同 Rust）** |

**从各语言借来的惯例**：

| 做法 | 来自 |
| --- | --- |
| `.` 表包根 | npm `exports` |
| 主模块 = 包名本身，单模块不特殊 | Go / npm / Rust |
| `dependencies` 的 key 即源码名 | npm / Cargo / Zig / Nix / Bazel |
| `source` 作身份（URL / git / path） | npm / Zig / Nix / Bazel |
| 哈希钉住、无 registry 也能防篡改 | Zig `.hash`、Go `go.sum`、Nix `flake.lock` |
| 相对路径带 `./`，裸名是包 | ES modules |
| `{ }` 惰性占位 | Go 的 `import _` |
| 排除导入 | Dart `hide` / Haskell `hiding`（拼写改用 `!`） |
| 方法面：inherent 免准入、trait 要在作用域 | Rust |
| 声明用包内名、引用用全名 | Java（类名 vs import） |


## 风险与未决 —— 原文「10. 边界与待定」

1. **`source` 的取值形式**：URL、git、`path:`；**不含 ref**（§5.3）。具体协议（`https:` / `git+https:` / `path:`）待定。
2. **传递依赖**：需定义间接依赖版本冲突的裁决规则。身份看 `source`，所以两个不同 `source` 撞同一个源码名时报错；两个相同 `source` 的版本冲突则按 semver 合并（或报错）。
3. **registry 是可选的**：`source` 已能自证身份，registry 只在需要**搜索、治理、集中分发**时才有价值。它是产品决策，不是命名模型的前提——留着不碍事，没有也能跑。
4. ~~**codegen 标识符映射**~~ —— **已关闭**（2026-10-24）。§5.3.1 把模块身份定为
   **（`source`，入口在包内的位置）**，符号前缀取它，不取本地源码名。换 `dependencies` 的
   key 不再改 ABI 符号。剩下的实现细节（`source` 哈希的具体编码）归实现记录。
5. **改名的连带影响**：换 `dependencies` 的 key 就改了源码名，`modules` key 是包内名、不动；
   但消费方源码里的全名会变，需一次性脚本替换。**ABI 符号不受影响**（§5.3.1）。
6. **包的自称与消费方源码名可能不一致**：包写 `package: "httpr"`，消费方写 `"http"`。前者只用于该包自己的源码自引用，后者用于消费方。两者不必相同。
7. **移动入口文件会改模块身份**（§5.3.1）。包内可控，但工具应当在 `entry` 变更时提示
   「模块身份已变」——这是实现侧的看护点，不是设计留白。
8. **扁平命名的撞名压力**：全局函数是自由函数（`read_file` 不是 `fs::read_file`），
   `std/os` 已导出 50 个名字。今天靠命名约定（`IoError` 不叫 `Error`）+ 默认 `module_private`
   拦住，**约定无机制**。若撞名成为常态，备选是**限定访问替换 `{ ... }`**（公理 7，不是叠加）
   ——现在不做，但答案先写死，免得将来重开。


## 实施

设计本身到「## 方案」为止。**怎么落地、落到哪了**记在实现记录，不在本文重复：

- [`module-design-implementation.md`](../implementation/module-design-implementation.md)
  —— 范围裁定、分阶段顺序、每阶段的验收判据与状态。

本文与该记录按文件名词干配对：`module-design.md` / `module-design-implementation.md`。

**2026-10-24 形态层重做 + 2026-10-25 方法面**：已落地的见
[`module-design-implementation.md`](../implementation/module-design-implementation.md) §0。
三条**未做**，理由记在那里 §7：

| 未做 | 理由摘要 |
| --- | --- |
| §5.3.1 模块身份 =（`source`，入口位置） | 会改 codegen 符号前缀，属 ABI 变更；本地未登记模块暂用入口名，**是有意留的偏差** |
| §5.2 `modules` 降为对外命名表 | 本地模块不登记已可用；manifest 仍是清单 |
| §7 孤儿文件报错 | 需要包级「源文件全集 − 模块闭包全集」扫描；正向一半（一文件不属两模块）已落 |

验证走 [`../implementation/developer-guide.md`](../implementation/developer-guide.md) 的验证链。

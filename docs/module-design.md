# Koral 模块与导入设计

状态：提案

## 0. 一句话

> **外部单元是 package，包内含一个或多个 module。**
> 模块全名 = `包名[/子路径]`，源码写全名；manifest 里声明用包内名。
> **`using "X";` 一律是「把 X 的全部可见成员带进来」**——X 是文件还是模块，只是路径不同。
> **单模块包不特殊处理**——它就是只有主模块的包，主模块名 = 包名。

## 1. 概念

| 概念 | 是什么 | 稳定身份 | 例子 |
| --- | --- | --- | --- |
| **package** | 外部可使用单元：一份 `koral.json`、一个版本、一组依赖 | **`source`**（§5.3） | `httpr`、`std` |
| **module** | 包内的构建单元：一个入口文件 + 若干合并文件 | **(包的 `source`, 子路径)** | `httpr/conn`、`std/io` |

**模块全名 = 包名 [ "/" 子路径 ]**——这是**写法**，不是身份。

- **包名**：这个包在**源码里**的名字（`package` 字段），也是自引用的前缀。它不是身份——身份是 `source`
- **子路径**：模块在包内的位置，`/` 分段
- **主模块**：子路径为空的那个模块，**模块全名 = 包名本身**

> 模块全名含本地源码名，所以**同一个模块在不同工程拼写不同**（`httpr/conn` vs `http/conn`）。
> 跨工程不变的是 `(source, 子路径)`——去重、lockfile、ABI 符号都该看它。
> `std` 没有 `source`（built-in），它的身份是 `(工具链版本, 子路径)`。

**主模块不是「根」**：它与子模块是平级的两个模块，只是子路径为空。`std` 与 `std/io` 之间没有父子、挂载、re-export 语义。

### 1.1 三种包形态（写法一致，不特殊处理）

| 形态 | manifest | 源码 |
| --- | --- | --- |
| 只有主模块 | `modules: { ".": … }` | `using "slug" { make_slug };` |
| 主模块 + 子模块 | `modules: { ".": …, "conn": … }` | `using "httpr" { Request };`、`using "httpr/conn" { Conn };` |
| 只有子模块 | `modules: { "compiler": …, … }` | `using "koral/compiler/parser" { Parser };` |

三者共用同一套规则：**主模块就是「子路径为空」的那个模块**。单模块包只是恰好只有一个模块。

## 2. 命名

### 2.1 词法

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

### 2.2 边界为什么唯一

| 约束 | 推论 |
| --- | --- |
| 包名**单段，不含 `/`** | 边界只可能在 `/` |
| 子路径的段也是标识符，**不含 `.`** | 段之间不会混淆 |

⇒ **第一个 `/` 就是包 / 模块边界**，零启发式、零查表。模块全名是纯 `ident/ident` 序列。

### 2.3 与 Go 的关键差别

Go 的 import path 是扁平字符串（`github.com/kulics/koral/compiler/parser`），`/` 既分隔域名段又分隔模块段，所以边界看不出来。Go 只好：

1. **下载期问网络**：`GET ...?go-get=1` 拿 `<meta name="go-import" content="github.com/kulics/koral git ...">`，meta 明说 module root；
2. **编译期查 build list**：取最长 module path 前缀，剩下的是包目录。

代价是**同一个字符串在不同 build list 下可能切在不同位置**。Koral 的包名是单段标识符，边界写在字符串里。

## 3. 语法

```koral
// 全部带进来
using "./helpers.koral";      // 文件：把顶层定义并入当前模块
using "std/io";               // 模块：导入全部可见符号

// 只带一部分
using "std/io" { Reader, Writer };
using "std/io" { Reader as IoReader };
```

**核心语义统一**：`using "X";` 一律是「把 X 的全部可见成员带进来」，不管 X 是文件还是模块。`{ ... }` 只是**过滤器**——省略即全部。

### 3.1 分类：相对路径 vs 模块

沿用 ES modules 的惯例：

| specifier | 类别 |
| --- | --- |
| 以 `./` 或 `../` 开头 | **文件合并** |
| 其它 | **模块导入** |

判别只看路径形状，与有没有 `{ }` 无关。

### 3.2 文件合并

```koral
using "./helpers.koral";
```

把目标文件的**顶层定义并入当前模块**。它不是外部单元依赖、不是包导入、不是子模块声明、不是别名机制。

specifier 必须：

1. 以 `./` 或 `../` 开头；
2. 以 `.koral` 结尾。

约束：

- 按当前文件所在目录解析，允许中间出现 `.` / `..`；
- 不创建新的模块标识，不参与包 / 模块解析；
- 不允许与 `{ ... }` 导入列表结合（合并就是全部，无从挑选）。

### 3.3 模块导入

```koral
using "std/io";                        // 全部可见符号
using "std/io" { Reader, Writer };     // 显式
using "std/io" { Reader as IoReader }; // 逐项别名
```

规则：

1. `{ ... }` 省略即「全部可见符号」；出现则不能为空；
2. 列表项是 **`符号名`** 或 **`符号名 as 新名`**，符号名沿用语言标识符规则；允许尾逗号；
3. 同名冲突报错，用 `as` 消歧——**import-all 与本模块定义重名时无法消歧，只能改成显式列表**；
4. **同一模块在同一文件内只 `using` 一次**：`using "std/io";` 与 `using "std/io" { Reader };` 并存报错。跨文件不重复——各文件各自 `using`；
5. **模块名不绑定为命名空间**——导入 `Reader` 后写 `Reader`，不写 `io.Reader`；
6. **`using` 必须位于文件顶部**，在任何其它顶层声明之前。

> **不需要 `*` 通配符**：省略 `{ }` 就是全部，`{ * }` 无从出现。
> 相对旧写法 `using std::io { .. }`，新写法是 `using "std/io";`。

## 4. 解析

**源码 `using`（只有全名一种写法）**：

```text
resolve(spec):
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

> **注意查的是包内名，不是模块全名。** 消费方写 `http/conn`，被依赖包的 key 是 `conn`
> （它自己写作 `httpr/conn`）。解析时按子路径 `conn` 命中，与它内部怎么拼无关。
>
> **`.` 只出现在 `modules` 的 key 里**（指代本包主模块），源码不写 `.`——主模块在源码里就是包名本身。
>
> **每个包用自己的表解析自己的源码。** 编译 `httpr` 的文件时用 `httpr` 自己的 `package` 与
> `dependencies`，与消费方给它起什么名字无关。这正是「包级」而非「工程级」的作用域——
> 所以传递依赖的源码不会因为消费方改名而失效。

**歧义性**（载入期全部可查）：

| 情况 | 会不会冲突 | 原因 |
| --- | --- | --- |
| 包名 vs 包名 | ❌ | `dependencies` 的 key 在本工程内唯一 |
| 两个 `source` 抢一个 key | ❌ | 载入期报错（§7 错误 17） |
| **一个 `source` 抢两个 key** | ❌ | **载入期报错**——否则同一模块有两种拼写，破坏「一工程一写法」 |
| 包名 vs 子路径 | ❌ | 引用一律带包名，源码无裸子路径写法 |
| **本包源码名 vs 依赖源码名** | ❌ | `dependencies` 的 key **不得等于本包的 `package`** |
| `std` vs 用户包名 / 依赖 key | ❌ | `std` 保留，二者都不得占用 |

## 5. manifest

### 5.1 字段（4 个）

| 字段 | 含义 | 必填 |
| --- | --- | --- |
| `package` | **本包的源码名**——自引用前缀，也是消费方的默认源码名 | ✓ |
| `version` | 版本 | ✓ |
| `modules` | **包内名 → { entry, links }** | ✓ |
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
| `entry` | 模块入口文件，**相对包根**（`conn/conn.koral`）；同模块的其余文件用文件合并并入 |
| `links` | 传递给链接器的库名（如 `["m", "pthread"]`），沿用现状，本次不变 |

**没有 `requires`**：模块图从 `using` 派生（§5.4）。

### 5.2 `modules` 的 key：包内名

manifest 描述**包内部**，所以用模块在包内的名字：

| | 写法 | 例子 |
| --- | --- | --- |
| 主模块 | `.` | key `"."` |
| 子模块 | `子路径` | key `"conn"`、`"compiler/parser"` |

`entry` 是相对包根的文件路径（`conn/conn.koral`），与 key 同视角。

> **`.` 是 npm `exports` 的先例**（`exports: { ".": "./index.js", "./conn": "./conn.js" }`）。它只是 manifest 记法，不是源码语法——源码里主模块就是「包名本身」。

### 5.3 `dependencies`：key 即源码名，source 即身份

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

### 5.4 模块图：从 `using` 派生

**`modules` 里没有 `requires`。** 模块依赖图由该模块所有文件的 `using` 语句并集决定：

```text
module_deps(M) = { 每条 using "…" { … } / using "…"; 指到的模块 }   // 排除文件合并
```

由它得到构建排序、可达性。**一处真相**，不会出现「manifest 说依赖 X、源码没用」这类漂移。

两条推论：

- **模块图必须无环**——有环报错并列出环。模块是符号导入单元，循环导入意味着两边都在用对方尚未完成的符号，没有清晰语义；
- **`links` 沿模块图传递**——A `using` B 且 B 有 `links: ["m"]`，则最终链接带上 `-lm`。`links` 是 C 链接需求，跟着代码走。

> **没有「依赖但不 import」的场景**：Koral 模块导入的就是符号，不 import 就用不上。
> 若日后出现（例如只为拉入 `links`），再加一个显式字段——那是新增能力，不是补漏。

### 5.5 `koral.lock`：整棵依赖树

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

## 6. 示例

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
using "./rules.koral";        // 文件合并
using "std";
using "std/text";

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
using "std";
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

现状 [std/koral.json](../std/koral.json) 的 `std` / `std::io` / `std::json` …，**`std` 成为 `"."`，`std::io` 成为 `io`**：

| 现状 module 名 | manifest key | 源码 |
| --- | --- | --- |
| `std` | `.` | `using "std";` |
| `std::io` | `io` | `using "std/io" { Reader };` |
| `std::json` | `json` | `using "std/json";` |
| `std::container` | `container` | `using "std/container";` |

```json
{
  "package": "std",
  "version": "0.1.0",
  "modules": {
    ".":         { "entry": "std.koral", "links": [] },
    "container": { "entry": "container/container.koral", "links": [] },
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

模块依赖方向（主模块是基础层）：

```text
        ┌──────────────── ．（主模块，核心类型）────────────────┐
        │                                                     │
   container  text  math  io  rand  sync  async               │
                    │     │                                   │
                   json  net ─── os ─── proc                  │
                    │     │                                   │
                   time ──┘                                   │
```

**子模块依赖主模块，主模块不依赖任何子模块**（主模块的 `using` 不指向任何子模块），所以 `using "std";` 不会拉进 IO / 网络等重模块。这张图是**从各模块的 `using` 派生**出来的，不是手写的。

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
using "./cli.koral";              // 文件合并
using "myapp/models" { User };    // 本包子模块
using "http" { Client };          // 跨包，被改过名
using "http/json" { to_json_body };
using "slug" { make_slug };
using "std";
```

注意：

- `httpr` 被换成本地源码名 `http`，本工程只能写 `http/...`；改名就是换 key，没有额外字段；
- `models` 用到了 `slug`，所以它必须在 `dependencies`——**用到就要声明**；
- **身份看 `source`**：`http` 与 `slug` 是两个不同的包，去重与传递依赖合并都不看名字。

## 7. 错误条件

### 文件合并

1. specifier 未以 `.koral` 结尾；
2. 目标 `.koral` 文件不存在；
3. 与 `{ ... }` 导入列表同时出现（合并就是全部，无从挑选）。

### 模块导入

4. `{ }` 出现但为空；
5. 模块全名不是合法的 `ident/ident` 序列（空段、`.`、`..`、非法字符）——若写了 `using ".";`，提示「主模块在源码里写包名，`"."` 只是 manifest 记法」；
6. **未知包名**——若它像旧的裸名文件合并写法，给出迁移提示（§8）；
7. 包名命中但模块不存在；
8. 包名命中、子路径为空，但该包没有主模块（列出该包已声明的模块）；
9. 同一符号被两个模块导入（或与本模块定义重名）且未用 `as` 消歧——import-all 撞名时提示「改为显式列表」；
10. **同一模块在同一文件内被 `using` 多次**；
11. **`using` 未位于文件顶部**；
12. **模块图有环**（列出环路）。

### manifest

13. 包名不是合法标识符（含 `/`、大小写、数字开头、是保留字）；
14. `modules` 的 key 既不是 `.` 也不是合法子路径；
15. 同一模块 key 重复；
16. **`entry` 文件被两个模块声明**，或不在包根内、或不存在；
17. 同一源码名被两个依赖声明（key 重复）；
18. **一个 `source` 被两个 key 声明**（同一模块会有两种拼写）；
19. **`dependencies` 的 key 等于本包的 `package`**（自引用与依赖撞车）；
20. **`dependencies` 的 key 或 `package` 占用保留名 `std`**；
21. `dependencies` 条目缺 `source` / `version`，或格式非法（`source` 含 ref、`version` 不是 semver 约束）；
22. **文件合并成环**（`a.koral` ↔ `b.koral`）。

### 构建期

23. **`koral.lock` 与 manifest 不符**（树里有 manifest 未声明的包 / 版本不满足约束）；
24. **哈希校验失败**（lockfile 记录的 hash 与实际抓取内容不符）。

## 8. 迁移

不保留兼容层，但错误信息必须把旧写法指清楚。

```koral
using "utils";            // 旧：裸名文件合并
```

被分类为模块导入（不以 `./` 开头），查不到包名 `utils`，报：

```text
error: 未知包名 "utils"
  想做文件合并 → using "./utils.koral";
  想导入模块   → 先在 koral.json 的 dependencies 里声明该包
```

```koral
using "std/io" { .. };    // 旧：.. 表全部
```

```text
error: 未知符号 ".."
  导入全部可见符号请省略列表 → using "std/io";
```

**风险窗口**：裸名写法会落到模块查询。若恰好存在同名包（如 `dependencies` 里把某包改名成 `utils`），会**静默解析到无关包**。

- 迁移期：迁移脚本必须一次改完 243 处裸名，不留尾巴；
- 迁移后：源码里不应再有裸名文件合并，风险消失。

### 迁移面

| 对象 | 内容 | 量级 |
| --- | --- | --- |
| 文件合并 | `using "x"` → `using "./x.koral"`；`using "./x"` → 补 `.koral` | 243 处（脚本化） |
| 模块导入 | `using std::io { X }` → `using "std/io" { X }`；`{ .. }` → 省略 | 330 处 / 236 文件 |
| manifest | 加 `package`；`modules` key `std` → `.`、`std::io` → `io`；`module_aliases` → `dependencies` 的 key | 中 |
| Swift 编译器 | Parser / ModuleResolver / PackageManifest | 中 |
| bootstrap 编译器 | `bootstrap/koralc` 的 lexer / parser / module / driver | 大 |
| toolchain | `toolchain/koral/config.koral` | 中 |
| 测试 | `tests/compiler-cases` | 559 用例 |
| 文档 | `grammar.bnf` / `document.md` / `document-zh.md` | 中 |

> bootstrap 目前 semantic 通过率 139/456。语法面变更应等它稳定后再动，或并行推进并单独验收。

## 9. 与主流语言对照

| | Go | npm/Node | Rust | **Koral** |
| --- | --- | --- | --- | --- |
| 分发单元 | module (`go.mod`) | package (`package.json`) | crate (`Cargo.toml`) | **package (`koral.json`)** |
| 构建单元 | package（目录） | 文件 | module (`mod`) | **module** |
| 单模块怎么写 | 根 package 路径 = module path | `import "mylib"` → `exports["."]` | crate 根 (`lib.rs`) | **`using "slug";`** |
| 主模块表示 | 路径等于 module path | `exports` 的 `"."` | crate 根 | **`modules` 的 `"."`** |
| 自引用 | 全名 | 按包名 | `crate::foo` | **按包名** |
| 身份 = 获取位置 | 是（module path） | 否（registry 名） | 否（registry 名） | **是（`source`）** |
| 改名 | 只改标识符 | `imports` 字段 | `foo = { package = "bar" }` | **换 `dependencies` 的 key** |
| 无 registry 可用 | ✓ `GOPROXY=direct` | ✗ | ✗ | **✓ `source` 是 URL/git/path** |
| 哈希钉住 | `go.sum` | `package-lock.json` | `Cargo.lock` | **`koral.lock`（全树）** |
| 构建图来源 | import 语句 | import 语句 | `mod` / `use` | **`using`（派生）** |
| 依赖声明 | `go.mod` `require` | `dependencies` | `[dependencies]` | **`dependencies`** |
| 通配导入 | 无 | `import *` | `use foo::*` | **省略 `{ }`** |

**从各语言借来的惯例**：

| 做法 | 来自 |
| --- | --- |
| `.` 表包根 | npm `exports` |
| 主模块 = 包名本身，单模块不特殊 | Go / npm / Rust |
| `dependencies` 的 key 即源码名 | npm / Cargo / Zig / Nix / Bazel |
| `source` 作身份（URL / git / path） | npm / Zig / Nix / Bazel |
| 哈希钉住、无 registry 也能防篡改 | Zig `.hash`、Go `go.sum`、Nix `flake.lock` |
| 相对路径带 `./`，裸名是包 | ES modules |
| `using "X";` 省略列表即全部 | 文件合并语义的自然推广 |
| 声明用包内名、引用用全名 | Java（类名 vs import） |

## 10. 边界与待定

1. **`source` 的取值形式**：URL、git、`path:`；**不含 ref**（§5.3）。具体协议（`https:` / `git+https:` / `path:`）待定。
2. **传递依赖**：需定义间接依赖版本冲突的裁决规则。身份看 `source`，所以两个不同 `source` 撞同一个源码名时报错；两个相同 `source` 的版本冲突则按 semver 合并（或报错）。
3. **registry 是可选的**：`source` 已能自证身份，registry 只在需要**搜索、治理、集中分发**时才有价值。它是产品决策，不是命名模型的前提——留着不碍事，没有也能跑。
4. **codegen 标识符映射**：包名与子路径都是标识符，但**不同包可能有同名子模块**（`httpr/conn` 与 `myapp/conn`），符号必须带包区分。基准应是 §1 的稳定身份 **`(source, 子路径)`**，不是本地源码名——否则换 `dependencies` 的 key 会改 ABI 符号。用 `source` 哈希作前缀最稳，用 `package` 作前缀可读但包改名会改符号，需权衡。
5. **改名的连带影响**：换 `dependencies` 的 key 就改了源码名，`modules` key 是包内名、不动；但消费方源码里的全名会变，需一次性脚本替换。
6. **包的自称与消费方源码名可能不一致**：包写 `package: "httpr"`，消费方写 `"http"`。前者只用于该包自己的源码自引用，后者用于消费方。两者不必相同。

## 11. 包管理机制

命名与语法已经闭环；本节是**包管理器本身**的机制决定。

### 11.1 三件事的分工（已定）

| | 是什么 | 写在哪 |
| --- | --- | --- |
| 源码名 | `using` 里写什么 | `dependencies` 的 key |
| **位置 / 身份** | 去哪下载、是不是同一个包 | `dependencies[*].source`（**不含 ref**） |
| **版本约束** | 能接受哪一版 | `dependencies[*].version`（semver 区间） |
| **精确版本 + 哈希** | 用的是哪一版、有没有被篡改 | **`koral.lock`**（覆盖全树） |

`source` 只管位置，`version` 只管约束，两者不重叠；ref（tag / commit）不写进 manifest，由 lockfile 的解析结果决定。

### 11.2 完整性覆盖全树（已定）

`koral.lock`（§5.5）记录**整棵依赖树**的 `source` + `version` + `hash`，根工程生成并提交。

| | 机制 | 消费方首次抓取就校验 | 覆盖范围 |
| --- | --- | --- | --- |
| Zig | `build.zig.zon` 的 `.hash` | ✓（哈希在 manifest） | 直接依赖 |
| **Koral** | **`koral.lock`** | ✗（首次生成时记录） | **全树** |
| Go | `go.sum` | ✗ | 全树 |
| npm | `package-lock.json` | ✗ | 全树 |

> Koral 与 Go / npm 同档：**首次生成 lockfile 时不校验，其后每次校验**。
> 好处是哈希只需在根工程写一次、覆盖全树；代价是新增依赖的第一次抓取无保护。

`dependencies[*].hash` **已删除**——哈希只活在 lockfile 里，一处真相。

### 11.3 模块图从 `using` 派生（已定）

`modules` 里没有 `requires`（§5.4）。一处真相，不存在「manifest 说依赖 X、源码没用」的漂移。

### 11.4 尚未覆盖的包管理能力

以下暂缺，**本次不做**，是否进 v1 需另行定：

- **dev-dependencies**（只供测试 / 示例用）
- **workspace / monorepo**（多包共用一份 lockfile）
- **feature / optional dependency**
- **版本区间与升级策略**（含传递依赖版本冲突的裁决，见 §10.2）

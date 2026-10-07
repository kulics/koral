# samples 能力验证计划

> **状态（2026-10-07）**：四个样本的规划已定，顺序 1→2→3→4。
> **1 `sha256sum` 已落地**（13/13，NIST 四向量全中，与 coreutils 对拍 5/5）；2/3/4 未开工。
> 本文是 `<topic>-plan.md` 记录体裁：**只追加，不重写**，新结论以 `## 附：<标题>（<日期>）` 追加到文末。

## 目标

用真实样本程序验证语言能力，并在**写完之后**才决定哪些能力该下沉到 `std`。

顺序原则是老规矩：**不预先抽象**。第一个抽象等第二个用例出现再做。
所以本文的「下沉候选」是**待验证的假设**，不是既定改动 —— 真正的裁决依据是样本写完后
留下的重复代码。

---

## 分界判据

**下沉到 `std`** 当且仅当四条同时成立：

1. **通用** —— 不止这一个样本会用；
2. **契约可写死** —— 能进 `api/std/` 文档，能版本化；
3. **不含应用语义** —— 不夹带 CLI 参数规则、退出码策略、输出格式；
4. **合 `../design/std-api-design.md` 约定** —— `self` 接收者、声明处可变性、
   `into_*` / `to_*` / `as_*` 命名契约。

**留在 sample**：

- **策略** —— CLI 参数语义、退出码、输出格式、并行粒度；
- **内容** —— 被验证的算法或协议本体（SHA-256 压缩函数、HTTP 状态机）。
  它是「证明语言写得出这个」的证据，不是设施。

---

## 现成的地基

多数管线已经有了。这一条决定了缺口比第一眼看上去小：

| 设施 | 状态 | 位置 |
|---|---|---|
| 字节流抽象 | ✅ | `Reader` / `Writer` / `Seeker`（各 1–2 个方法） |
| 三方实现 | ✅ | `File`、`ByteBuffer`、`TcpSocket` 均 `as Reader` / `as Writer` |
| 流式工具 | ✅ | `read_all` / `write_all` / `copy_all_to`（`std/io/utils.koral`） |
| 行读取 | ✅ | `BufReader.read_line` / `read_until` / `read_byte` / `read_rune` |
| 正则 | ✅ | `Regex`：`find` / `find_all` / `captures` / `replace` / `split` |
| 目录遍历 | ✅ | `walk_dir` / `read_dir` / `DirIterator` |
| 环绕算术 | ✅ | `wrapping_add` / `sub` / `mul` / `neg`（`std/arithmetic.koral`） |
| 位旋转 | ✅ | `rotate_left` / `rotate_right`（`std/primitives.koral`） |
| 并发原语 | ✅ | `Mutex`、`make_channel`、`run_task`、`available_parallelism` |
| 网络 | ✅ | `TcpListener` / `TcpSocket` / `UdpSocket` + 超时 / nodelay |

`BufReader[R Reader]` 是泛型的，`TcpSocket as Reader` 已成立 —— **HTTP 直接能套，不等新设施**。

### 两个已经付过成本的洞

这两条不是推测，是仓库里已经有重复代码或绕行：

1. **hex 编解码** —— `std/net/ip_addr.koral:240-316` 有一整套 `file_private` 的
   `hex_digit_value` / `hex_string` / `hex_char`，只服务 IPv6 地址格式化。
   而 `../design/module-design.md` §5.5 的 `koral.lock` 要记「精确版本 + 内容哈希」，
   展示成 hex 是必需的。
2. **stdin / stdout 不是流** —— `samples/cat/src/cat.koral:269` 的 `process_stdin` 走
   `scanln()`，`process_file` 走 `BufReader`，**同一个程序里两条无法统一的路径**。

---

## 样本规划

### 1. `samples/sha256sum` —— 字节 / 位运算 / 流式

**能力需求**

| 能力 | |
|---|---|
| 流式分块读文件 | ✅ `File.read` + `List[UInt8]` |
| 32 位环绕加法 | ✅ `UInt32.wrapping_add` |
| 循环右移 | ✅ `UInt32.rotate_right` |
| 十六进制输出 | ❌ 缺（见上，`ip_addr` 已私有一份） |
| `<hash>  <name>` 格式 | sample |

**下沉候选**：hex 编解码。
**留 sample**：SHA-256 算法本体、CLI、`-c` 校验模式、多文件。

**黄金参照**：NIST FIPS 180-4 测试向量（决定性判据）。

**会逼出什么**：大文件不能 `read_all`，得真走流式 —— 唯一会暴露「流式 API 顺不顺手」的样本。

### 2. `samples/grep` —— 正则 / 流式行处理

**能力需求**

| 能力 | |
|---|---|
| 正则匹配 | ✅ |
| 逐行流式 | ✅ `BufReader.read_line` |
| 递归目录 | ✅ `walk_dir` |
| **stdin 当 Reader** | ❌ 缺 |
| **stdout 当 Writer** | ❌ 缺 |
| 退出码 / 多文件前缀 / flag | sample |

**下沉候选**：`stdin()` / `stdout()` / `stderr()` 作为 `Reader` / `Writer`。
**留 sample**：全部 CLI 语义、`-n` / `-i` / `-v` / `-c` / `-l` / `-o`、输出格式、二进制探测。

**黄金参照**：`grep -E`。

> ⚠️ **方言前提**：`std` 的正则是 **POSIX ERE**（`std/koral_runtime.c:1138`
> `regcomp(..., REG_EXTENDED)`，外加一层 `__koral_regex_translate_pattern_posix` 翻译）。
> 参照必须取 `grep -E`，不是默认 BRE，否则差分大面积假红。
>
> ⚠️ **跨平台双引擎**：`std/koral_runtime.c:1209` 起 Windows 用手写回溯引擎，
> 与 POSIX `regcomp` 是两套实现。这个样本会是第一个压到它的东西 —— 按本仓库方法论是收益。

### 3. `samples/grep-j`（并行版）← **最该做**

**能力需求**

| 能力 | |
|---|---|
| `available_parallelism()` | ✅ |
| 通道 / 互斥 | ✅ `make_channel` / `Mutex` |
| **工作池** | ❌ 缺（只有 `run_task` 一次性 spawn+join） |
| **`Send` / `Sync` 约束** | ❌ **语言层缺口** |
| 结果有序合并 | sample |

**下沉候选**：有界工作池。
**留 sample**：切分粒度、输出有序性策略、与单线程结果一致的保证（**黄金参照的来源**）。

> `tests/compiler-runner/scheduler.koral:79-153` 已经手写了一份 worker 池
> （`worker_count` + `make_channel` + 三把 `Mutex`）。重复代码在仓库里，是下沉的信号。

**会逼出什么**：这就是建它的目的。多线程共享搜索状态会撞上已定位的语言缺口 ——
`run_task(f Func() Void)` 捕获任意 `type mutable`，无 `Send`/`Sync`；`strong_count` 是
`memory_order_relaxed`。它让缺口从「口头判断」变成「样本编不过或跑不对」。

> **做法**：先把样本写成**会红的样子**当复现器留着，再开语言改动。不边写边改语言 ——
> 与「整链一起改再测」一致。

### 4. `samples/http` —— 网络 / 并发 I/O 模型

**能力需求**

| 能力 | |
|---|---|
| TCP | ✅ |
| `BufReader` 套 `TcpSocket` | ✅ 已成立 |
| **非阻塞 / poll** | ❌ 缺 |
| 并发连接处理 | 只能线程模型 |
| 请求/响应状态机、keep-alive、chunked | sample |

**下沉候选**：`set_nonblocking` 及 socket 选项补全（`TcpSocket` 已有
`set_nodelay` / `set_read_timeout` / `set_write_timeout`，缺非阻塞是 API 面的自然缺口）。
**不下沉 HTTP**：HTTP 是协议不是设施，等第二个消费者出现再议 `std/net/http`。
**留 sample**：HTTP/1.1 解析与状态机、路由、静态文件服务、并发模型选择。

**黄金参照**：RFC 7230 + `curl`。

**会逼出什么**：唯一会逼出「并发 I/O 模型」决定的样本（事件循环 vs thread-per-connection）。
排最后，等 3 把并发契约定了再动。

---

## 下沉候选汇总（**待验证，非既定**）

| 新增 | 触发者 | 为什么属于 `std` | 优先级 |
|---|---|---|---|
| **hex 编解码** | sha256sum | `ip_addr.koral` 已私有重复一份；`koral.lock` 也要 | **高** |
| **`stdin/stdout/stderr` 为流** | grep | `cat` 已付过成本（两条路径）；管道工具通病 | **高** |
| **有界工作池** | grep-j | `scheduler.koral` 已手写一份 | 中 |
| **`set_nonblocking`** | http | `TcpSocket` API 面的自然缺口 | 中 |
| `Hasher` / 摘要 trait | — | ⚠️ 不做：只有一个算法；且 `Hash` 名字已被 `std/traits.koral:10` 占用 | **不做** |
| `std/http` | — | ⚠️ 不做：等第二个消费者 | **不做** |

**每个 `std` 新增的落地义务**：`tests/compiler-cases/` 加用例 · `koral_doc` 重新生成
`api/std/` 并过 `--check` · 遵 `../design/std-api-design.md` 命名契约 ·
套件计数与本文、`bootstrap-productization-plan.md` 的验证链数字同步更新。

---

## 顺序

按**能逼出什么**排，不按实现难度：

| # | 样本 | 产出 |
|---|---|---|
| 1 | `sha256sum` | NIST 向量判对错；hex 顺进 `std`；摸清 `koral.lock` 还差什么 |
| 2 | `grep` | `stdin/stdout` 顺进 `std`；盖住正则；暴露 POSIX / Windows 双引擎分歧 |
| 3 | `grep-j` | **逼出 `Send`/`Sync` 缺口**；工作池顺进 `std` |
| 4 | `http` | 最大；等 3 定完并发契约再动 |

---

## 验证

样本遵守与 `samples/cat` 相同的形状：

```
samples/<name>/src/<name>.koral     样本本体
samples/<name>/test/<name>_test.koral   单入口测试（unit + property）
```

- 构建：`bin/compiler/koralc build samples/<name>/src/<name>.koral -o bin/sample-<name>`
- 测试：`bin/compiler/koralc run samples/<name>/test/<name>_test.koral -o .`
  （测试进程调用上一步构建出的二进制，与 `cat_test.koral` 同形）
- **判据可判定**：每个样本必须有黄金参照（NIST 向量 / `grep -E` / RFC + curl），
  对拍结果逐字节比对。不可判定「做对了」的样本不建。

---

## 附：sample 1 `sha256sum` 落地与发现（2026-10-07）

### 产物

```
samples/sha256sum/src/sha256sum.koral    SHA-256 + hex + CLI
samples/sha256sum/test/sha256sum_test.koral   13 项：4 NIST + 6 unit + 3 property
```

构建与测试同 `samples/cat` 形状：

```bash
bin/compiler/koralc build samples/sha256sum/src/sha256sum.koral -o bin/sample-sha256sum
bin/compiler/koralc build samples/sha256sum/test/sha256sum_test.koral -o bin/sample-sha256sum-test
./bin/sample-sha256sum-test/sha256sum_test
```

| 判据 | 结果 |
|---|---|
| NIST FIPS 180-4 四向量（空 / `abc` / 双块 / 100 万 `a`） | **4/4 逐字节全中** |
| 与 coreutils `sha256sum` 对拍（含 3000 字节随机二进制） | **5/5** |
| 测试套件 | **13/13** |
| `koralfmt --check` | 通过 |
| 格式化器闸门 | **107/107**，corpus **219/0**（含新增 2 文件） |

### 一、`std` 现有面已足够的部分

算法本体**没有产生任何新 `std` 需求**。写之前以为会缺的，其实都在：

| 需要 | 实际有 |
|---|---|
| 32 位环绕加法 | `UInt32.wrapping_add`（`std/arithmetic.koral:137`） |
| 循环右移 | `UInt32.rotate_right`（`std/primitives.koral`） |
| 按位取反 / 异或 | `~` / `^` |
| 预分配字节缓冲 | `make_bytes(count)`（`std/list.koral:518`） |
| `span` 解析 | `List.slice_spec(span)` → `SliceSpec.start()/end()` |
| 流式读文件 | `File.read(into: buf)` 返回读到的字节数 |

> ⚠️ **一处误判记下来**：最初手写了 8192 次 `push` 来撑开缓冲区，据此以为
> 「没有预分配填充」是缺口。**不是缺口** —— `make_bytes` 一直都在，只是没找到。
> 取证结论要先查 `std` 全表再下判断。

### 二、该下沉的公共能力

**hex 编解码** —— 判据四条全中，且**消费者已有三个**：

1. 本样本的摘要输出（GNU 格式是小写 hex）
2. `std/net/ip_addr.koral:240-316` 已私有一份（`hex_digit_value` / `hex_string` / `hex_char`）
3. `../design/module-design.md` §5.5 的 `koral.lock` 要把内容哈希展示成 hex

形状建议（遵 `../design/std-api-design.md` 的 `to_*` / `from_*` 契约，与现有
`String.to_bytes()` / `String.from_bytes()` 对称）：

- `List[UInt8].to_hex() String`
- `List[UInt8].from_hex(s String) Result[List[UInt8]]`

**小写固定**（`ip_addr` 与 coreutils 都是小写）。变体等有第二个消费者再说。

### 三、明确不下沉

| 候选 | 裁定 | 理由 |
|---|---|---|
| SHA-256 算法本体 | **留 sample** | 是「证明写得出」的内容，不是设施 |
| `Hasher` / 摘要 trait | **不建** | 只有一个算法；且 `Hash` 名字已被 `std/traits.koral:10` 容器哈希占用，将来真抽象得改名 |

### 四、顺带撞到的两个真问题（都不是抽象候选）

**1. 模块级常量数据无处安放 —— 语言表达力缺口**

`<let-decl>` 强制带 `<function-signature>`（`grammar.bnf:68`），所以文件作用域只有函数，
没有数据常量。SHA-256 的 K 表（64 个 `UInt32`）与 H 初值（8 个）因此只能在运行时建好、
挂在对象上。**64 个编译期常量被迫变成每次建 hasher 的一次分配**。

**2. 解析对齐缺口 —— `koral-syntax` 与 `koralc` 不一致（缺陷）**

最小复现：

```koral
public let f(block List[UInt8], b UInt) UInt32 = {
    let word = (block[b](UInt32) << 24)
        | (block[b + 1](UInt32) << 16);
    return word;
};
```

| | 表现 |
|---|---|
| `bin/compiler/koralc check` | **接受**（exit 0） |
| `bin/koralfmt/koralfmt --check` | **拒绝**：`expected ';' after let declaration` |

`toolchain/koral-syntax/parser.koral:287` 的 `is_line_join_peek()` 白名单只有
`.KwAnd or .KwOr or .KwIs or .KwThen or .KwElse or .Dot or .Arrow` —— 运算符开头的续行不在内。

**规范本身有张力，需先裁定再改**：

- `grammar.bnf:647` 与 `document.md:111` 标题：**「换行没有语义」**、**「没有续行概念」**
  ⇒ 按字面，任何形状都该跨行自由。
- 但 `grammar.bnf:651` 又**枚举**了可续行的六个引导词（`.` / `and then` / `or else` /
  `then` / `else` / `is`）——`is_line_join_peek()` 实现的正是这份枚举。

所以两个读法：(a) 枚举是举例，标题规则统治，koralc 对、koral-syntax 过严；
(b) 枚举穷尽，缺 `;` 是错误，koralc 过松。**本样本未裁决**，写法改用具名中间量
（每个 `let` 以 `;` 收尾），在两种读法下都合法 —— 且对位打包本来更易读。

> 格式化契约**未破**：koralfmt 的 printer 不产出运算符开头的续行（它把运算符留在行尾、
> 从下标内断行），输出能重新解析、能安定。破的是**接受面**，不是安定性。
>
> **这正是 sample 的价值**：corpus 闸门只覆盖已经写出来的代码，永远测不到这种
> 「人会这么写但工具拒收」的形状。建议单独开一次改动裁定并修，附 `test_fmt.koral` 断言。

---

## 附：解析对齐缺口已收（2026-10-07）

上一节记的「规范张力」已裁定：**换行没有语义，只看分号**。四条枚举的「续行引导词」是错的，
白名单不必要。改动：

| 改动 | 落点 |
|---|---|
| 删掉四条续行引导词枚举，只留「表达式可自由跨行，只有 `;` 结束它」 | `guide/grammar.bnf` Statement Termination |
| 删掉 `is_line_join_peek` 白名单 + `should_break_expr_at_peek` + 13 处调用 | `toolchain/koral-syntax/parser.koral` |
| 删掉配套的 `newline_before_current` / `line_join_grouping` / `at_newline_boundary`（后者本就是死代码）与 18 处进出调用 | 同上 |
| `parse_postfix` 不再在换行处断开，`f\n(x)` 就是 `f(x)` | 同上 |
| 契约写进包文档 | `toolchain/koral-syntax/README.md` |
| 接受面断言 ×3（运算符续行 / 调用跨行 / 链跨行） | `toolchain/koralfmt/test_fmt.koral` |

`document.md` / `document-zh.md` **本来就对**（写的是「没有接续符或换行续行概念」，无枚举），未改。
`compiler/koralc` 的 lexer 只记 `has_newline_before`、不产换行 token，本就符合，未改。

| 判据 | 结果 |
|---|---|
| 复现器 `let w = a\n \| b;` | 两边**都接受**（改前 koralfmt 报 `expected ';' after let declaration`） |
| 格式化器 | **110/110**（+3 断言），corpus **219/0** |
| `sha256sum` 样本 | 13/13 仍绿 |
| `koral_doc --self-test` / `--check` | 通过 / 13 模块未过期 |

### 顺带发现：缺分号是**另一处**既有缺陷（未修）

对拍同一输入 `let x = 1\nlet y = 2;`：

| | 改前 koralfmt | 改后 koralfmt | koralc |
|---|---|---|---|
| 接受？ | ✅ | ✅ | ❌ `Unexpected token: let, expected: ';'` |
| 输出 | 补出 `let x = 1;` | 补出 `let x = 1;` | — |

用改前二进制做了二分：**缺分号被接受是既有行为，非本次引入**；本次只动了运算符续行。

但性质更重 —— 格式化器在**替用户补上编译器拒绝的分号**，正是 README 警告的方向
（「把源文件改写成编译器随后会拒绝的形状」）。根因：声明级解析器（`finish_func_or_var`、
`parse_type_decl` 等）**根本不检查 `;`**，而语句级解析器（`parse_var_decl_stmt` 等）检查了。
顶层与语句两套处理分离，收紧要在 6+ 个声明解析器里补，属**另一批改动**，需自带断言。

---

## 附：分号缺口已收（2026-10-07）

**裁定**：行为跟编译器匹配，格式化器**不擅自补分号**。Koral 无 ASI —— `;` 在语句与声明上必填、
在块尾表达式上必禁，不是「可有可无」。

### 改动

| 改动 | 落点 |
|---|---|
| `eat_decl_semi` / `finish_decl_item`：声明收尾必查 `;` | `toolchain/koral-syntax/parser.koral` |
| `parse_top_item` 5 处 + `parse_member_items` 2 处 + `parse_trait_members` 1 处统一过收口 | 同上 |
| 块内裸表达式**必须是尾**：后面还有项就报错，不补 `;`（补了会把尾表达式变成语句） | 同上 |
| 契约检查收紧：只允许 `,` 变动，`;` 两侧逐个计数 | `toolchain/koral-syntax/contract.koral` |
| 契约文字：删掉「ASI 会补的分号」那句（与 grammar「无 ASI」直接矛盾） | `contract.koral` + `koral-syntax/README.md` |
| 拒绝断言 ×5（顶层 / type / 成员 / 块内 let / 裸表达式非尾） | `toolchain/koralfmt/test_fmt.koral` |
| 51 个用例的**输入**补 `;`（它们本是非法程序，期望输出早就带 `;`） | 同上 |

### 判据

| | |
|---|---|
| 解析对齐矩阵 9 形状 | **9/9 全一致**（该拒的都拒、该收的都收） |
| 格式化器 | **115/115**（+5 断言），corpus **219/0** |
| `sha256sum` 样本 | 13/13 |
| `koral_doc --check` | 13 模块未过期 |

### 途中一处自己的错（记下来防再犯）

用 `replace_all` 把 `return .Ok(.Decl(d));` 全换成 `return self.finish_decl_item(d);`，
**命中了我刚写的 `finish_decl_item` 自己的返回句**——它自调用，吞掉 `;` 后第二次检查自然报错，
110 个用例全红。正是「不要盲改，一处处手工改」要防的。

### 一处分歧留给裁定：`using` 要不要 `;`

`grammar.bnf` 的 `<using-decl>` 写着 `";"` 必填，但 **koralc 实测不查**：
`using "./x.koral"` 无 `;` 编译通过。按「行为跟编译器匹配」，koral-syntax 也接受（已实测 9/9 对齐）。
**规范与实现不一致，哪边为准待定**——若定「必填」，改的是 koralc；若定「可选」，改的是 grammar.bnf。

---

## 附：`using` 分号收口 + `std/hex` 落地（2026-10-07）

### 一、`using` 的 `;` 收口

上一节记的分歧已裁定：**必填**。两边都修：

| | 改动 |
|---|---|
| `compiler/koralc/parser/core_precedence.koral` | `parse_using_decl` 尾部接 `require_semicolon()`（复用既有 helper，诊断措辞不变） |
| `toolchain/koral-syntax/parser.koral` | `validate_using_trailing_tokens` 由「容忍 `;`」改为「必须有且仅有一个 `;`」 |
| 用例 | `tests/compiler-cases/using_missing_semicolon_error.koral` + `test_fmt.koral` 断言 ×1 |

**取证**：改动前种子（冻结 Swift）**本就拒** `using` 缺 `;`，是 koralc 单侧松了。
六步链在改前对新用例即报 597/597 —— 说明差分预言机早就抓不到这一条（老用例里没有），
正是「绿的覆盖面小于已知分歧面」的又一例。

### 二、`std/hex` 落地

| | |
|---|---|
| 新模块 | `std/hex/hex.koral`，注册进 `std/koral.json` |
| API | `encode_hex(bytes List[UInt8]) String` · `decode_hex(s String) Result[List[UInt8]]` |
| 用例 | `hex_encode_decode_test`（往返/大小写/空输入）· `hex_decode_error_test`（奇数长度/非法位/带位置） |
| 生成物 | `docs/api/std/hex.md`，模块数 13 → **14** |

**迁移**（两处消费者全部切到 std）：

| 原处 | 处置 |
|---|---|
| `samples/sha256sum` 的 `to_hex` / `hex_chars` | **删除**，改 `encode_hex` |
| `std/net/ip_addr.koral` 的 `hex_char` + `hex_string` 的逐位拼装 | **删除**，`hex_string` 改为 `encode_hex` + RFC 5952 去前导零 |
| `std/net/ip_addr.koral` 的 `hex_digit_value` | **删除**，`parse_groups` 改为收整组字符交 `decode_hex` |

IPv6 的两处保留逻辑是**地址格式自身的规则**，不是 hex 编码：RFC 5952 §4.3 组内去前导零、
每组 1–4 位。它们已不再重复 hex 位运算。

### 判据

| | |
|---|---|
| 六步链 | 种子 **599** · 主门禁 **599** · `FIXED POINT` + `dangling=0` · stage2 **599** · 差分 **599** |
| 格式化器 | **116/116**，corpus **220/0** |
| `sha256sum` 样本 | 13/13，摘要与 coreutils 逐字节一致（迁移零行为变化） |
| `koral_doc` | 自检通过，**14** 模块未过期 |

### 三、命名语序裁定：`encode_hex`（动在前）

见本轮答复正文的完整分析。一句话：std 的 ~100 个多词自由函数**动词一律在前**
（`create_dir` / `read_file` / `write_text_file` / `make_bytes` / `set_env`…），无一例外；
名在前的是无动词的名词短语（`available_parallelism`）或主谓式谓语（`path_exist`）。
限定语修饰的是**宾语**而非动词（`write_text_file` 的 `text` 修饰 `file`）。

---

## 附：类型显示与身份混用收口（2026-10-07）

**触发**：`or else` 的 `it` 报错时印 `Type '*Error'` —— 受管引用 `*T` 已从语言删除，
表层 trait object 就写 trait 名本身（`document.md` "Trait Objects"：**without exposing
internal wrappers in the public surface**）。出现 `*` 即内部表示泄漏。

### 根因：同一套拼法抄了四份

| 出处 | 语言 | 拼法 |
|---|---|---|
| `compiler/koralc/typed/types.koral` `type_string_wrapper_prefix` | Koral | `*` `*mutable ` `?*` `?*mutable ` |
| `compiler/koralc/typed/types.koral` `type_display_name` | Koral | 只在**顶层**解析名字，其余落到 `type_to_string` → 嵌套位置漏 `struct#N` |
| `compiler/koralc/sema/type_checker.koral` `display_type_name` | Koral | **第三份**同样的前缀表 |
| `compiler-reference/.../Type.swift` `description` | Swift | 同样四处 |

已删/过时的拼法：`*T` `*mutable T`（受管引用，语言已删）· `?*T` `?*mutable T`（表层是 `?T`，
`?*T` 是 koral-syntax 明令拒收的 legacy）。

### 改动

| | |
|---|---|
| 三份 Koral 前缀表 | `Reference`/`MutableReference` → 不印；`WeakReference`/`MutableWeakReference` → `?` |
| `type_display_name` | 逐层递归解析名字，不再整包丢给 `type_to_string` |
| 种子 `Type.description` | 同四处 |
| 种子 4 处**拿 `description` 当身份键** | 改 `stableKey`（递归守卫 ×2、约束缓存键、穷举集合） |
| 种子穷举消息 | 集合改存 `Type`（本就 `Hashable` 于 `stableHashKey`），消息走 `description` 显示 |

后两条是**既有的越界用法**：`Type.swift` 的 `genericStruct` 分支注释明写
「`Type.spelling` is display only」，而 `stableKey` 才是身份（`Ref(...)`/`MutRef(...)` 分得开）。
显示修复会让这些键撞车（`reference(A)` 与 `A` 同串），所以必须同批改。

### 判据

| | |
|---|---|
| `it` 的类型 | `Type 'Error'`（原 `Type '*Error'`） |
| `?T` 的类型 | `Type '?C'`（原 `Type '?*struct#111'`） |
| 六步链 | 种子 **599** · 主门禁 **599** · `FIXED POINT` + `dangling=0` · stage2 **599** · **差分 599** |
| 格式化器 / 样本 / `koral_doc` | 116/116 + corpus 220/0 · 13/13 · 14 模块未过期 |

差分预言机在此**起了作用**：koralc 先改对时它报 `*Problem` vs `Problem`，指明种子带着同一缺陷。

### 留下的一处：`ref` / `weakref` 词汇

`No blanket given exists for 'ref' and 'Add'` 里的 `ref` / `weakref` / `mutptr` 来自
`conformance_template_key(...).display()`，**有注释写明是有意的**（"Display only: the diagnostic
names the modifier"）。但它们不是表层词汇（表层是 `?T`、`*unsafe mutable T`，`ref` 无表层写法）。
属措辞裁定，未擅动。

---

## 附：拼法表合并（2026-10-08）

上一节说「三份前缀表只是改齐，没有合」。已合。

### 结构

`compiler/` 只有一个模块（`koral.json` 仅 `main.koral` 一个 entry，其余文件合并），
所以共享用 `module_private` 即可，不必开 `public`。

```
typed/types.koral
  module_private TypeStringWrapperKind / TypeStringWrapperChain   ← 剥层结构
  module_private split_type_string_wrappers(t)                     ← 剥层
  module_private type_string_wrapper_prefix(kind)                  ← ★ 唯一拼法表
  module_private type_string_prefixes(chain)                       ← ★ 剥层 + 拼法
```

三处渲染路径**只决定基类型叫什么**，前缀一律来自 `type_string_prefixes`：

| 路径 | 基名策略 | 行 |
|---|---|---|
| `type_to_string_impl` | id 拼法（`struct#N`） | `types.koral:1190` |
| `DefIdMap.type_display_name` | 声明名 + `get_original_def_id` 兜底 | `types.koral:482` |
| `TypeChecker.display_type_name` | 先做别名规范化 / 默认字面量具体化，再命名 | `type_checker.koral:1675` |

`TypeChecker.display_type_name` 原先那套自带前缀表已删，拆成
`display_type_name`（预处理）+ `display_type_base_name`（命名）。`type_display_name`
原先我为修 `struct#N` 临时内联的那份也删了，改走同一张表。

**grep 验零残留**：全库再无第二处前缀字符串。

### 判据

| | |
|---|---|
| 显示行为 | 与合并前逐项一致：`Error` / `?C` / `C` / `Box[Int]` |
| 六步链 | 种子 **599** · 主门禁 **599** · `FIXED POINT` + `dangling=0` · stage2 **599` · **差分 599** |
| 格式化器 / 样本 / `koral_doc` | 116/116 + corpus 220/0 · 13/13 · 14 模块未过期 |

### 有意没合的：基名策略

三处的**基名解析**保留各自实现，因为它们真的不同：

- `type_to_string` 是自由函数，靠全局 `display_context`（`def_id_spelling`）拿名字，
  对泛型模板与 trait object 已如此，但裸 `StructureType`/`EnumType` 仍印 `struct#N`；
- `DefIdMap.type_display_name` 多一层 `get_original_def_id` 兜底（别名/导入）；
- `TypeChecker.display_type_name` 多做别名规范化与默认字面量具体化，且函数类型印 `Func(`
  而 `type_to_string` 印 `Fn(`。

后两条是**另一层分歧**（命名策略、函数类型拼法），不在「拼法表」这一类里。
`struct#N` 泄漏已由 `bootstrap-productization-plan.md` 记为**既修过的缺陷类**
（「用户不该看见 `struct#N`」），要根治应让 `type_to_string` 对结构体/枚举也走
`def_id_spelling`，并统一 `Fn`/`Func` —— 属后续一批。

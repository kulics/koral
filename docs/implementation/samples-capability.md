# samples 能力验证 —— 判据、缺口与被否的下沉

> **状态**：`cat`、`sha256sum`、`expr-eval`、`grep` 已落地；`grep-j` / `http` 未开工。
> `cat`、`sha256sum`、`grep` 有黄金参照；`expr-eval` 是登记在案的例外（见「验证」）。
> 未决：缺口表三项（`grep` 轮关闭了 stdin/stdout 流句柄一项），以及 `grep-j` 的拆法
> （见「各样本要点与坑」）。本文记**当前**的判据与裁定。

## 为什么用样本

语言能力靠**真实样本程序**验证，不靠单点用例。样本要长到能撞出抽象边界。

**抽象不提前：第一个抽象等第二个用例。** 只有一个用例时，抽象是猜的。

## 分界判据：下沉 `std` 还是留在 sample

四条都满足才下沉：

1. **两个以上用例**都要它（不是「以后可能要」）。
2. 它的**名字与签名**能按 [`../design/std-api-design.md`](../design/std-api-design.md) 的契约定下来。
3. 它不依赖 sample 的领域概念。
4. 它在 `std` 现有面里**确实没有**——先把 std 全表翻完再宣称缺口。

> **踩过的坑**：`make_bytes` 早就在 std 里，却按「缺一个字节构造」开了下沉候选。
> **宣称缺口前先把 std 的完整 API 表翻一遍。**

## 验证

每个样本必须有**黄金参照**（golden reference）并**逐字节对拍**，不能只看退出码。
布局：`samples/<name>/src/` 放实现，`samples/<name>/test/` 放带黄金参照的测试。
构建产物统一进仓库根 `bin/`（`bin/samples/<name>`），样本目录不带自己的 `bin/`；
测试从仓库根跑，参照同目录下 `bin/samples/` 的二进制。
`scripts/verify.sh` 的样例闸门只做**构建 + 冒烟**；黄金对拍在各样本 `test/` 入口里单独跑。

> **登记在案的例外**：`expr-eval` 不满足上述布局——它是扁平多模块布局
> （`expr_eval.koral` + `frontend/` / `backend/` / `types/`，无 `test/` 目录），验证方式是
> `scripts/verify.sh` 的编译 + 冒烟管道（`expr_eval.koral` 进样例闸门，无黄金对拍）。
> 它的价值在撞抽象边界（多模块、递归下降、AST），不按「黄金参照」验收。
> 新样本仍按上面两条做；要给 expr-eval 补黄金测试时再撤销本例外。

## 被否掉的下沉

- **`Hasher` / digest trait 不下沉。** `Hash` 这个名字已被 `std/traits.koral` 占用
  （值相等哈希），digest 语义不同，起不了不冲突的名字。sha256sum 里自带。

## 命名裁定：自由函数动词在前

自由函数**动词在前**：`create_dir` / `read_file` / `encode_hex`。
（方法名的 `into_*` / `to_*` / `as_*` 契约是另一回事，见
[`../design/std-api-design.md`](../design/std-api-design.md)。）

## 已知语言 / std 缺口

样本做下去会撞到的真缺口（不是抽象候选）：

| 缺口 | 影响 |
|---|---|
| **常量表没有不可变集合类型** | 模块级 `let` 能放数据常量（2026-10-14 起），但 `List` 是 `type mutable` 共享对象，`let` 保护绑定不保护内容——常量表只能靠 `private` + 不改动的纪律（`sha256sum` 的 K 表即此） |
| **无 `Send` / `Sync`** | `run_task` 能捕获任意 `type mutable`，共享引用计数只是存活计数，不构成载荷的线程间转移判定；并行样本没法表达「只能在线程间转移」 |
| **无非阻塞 / poll** | `std/net` 是纯阻塞面；线程每连接的网络样本今天能写，事件驱动 / 大规模并发表达不了 |

## 各样本要点与坑

### `sha256sum`（已落地）

字节 / 位运算 / 流式。黄金参照是 NIST 向量。

K 表是模块级共享绑定（`private let round_constants`），**只读纪律**看住——
`List` 是 `type mutable`，误 `push` 会静默毁掉之后所有摘要。H 初值表是模块级模板
（`private let initial_state`），被 `state` 原地改写，所以每个 hasher 从
`initial_state.clone()` 起步，不共享。

### `cat`（已落地）

字节流复制 + 多文件。黄金参照是 `coreutils cat`。

### `grep`（已落地）

ERE 匹配 + stdin / 文件行流 + 多文件前缀。黄金参照是 **`grep -E`**
（期望值取自 `grep -E` 的输出；用 BRE `grep` 当参照会把方言差异当成实现缺陷）。

- flag 面：`-n -i -v -c -l -L -h -o -q -x -w -r` 与可重复的 `-e PATTERN` / `-f FILE`、
  数字选项 `-A/-B/-C/-m`（簇写与分写皆可，`-C2`/`-C 2`）；短 flag 可簇写（`-in`）；
  上下文行按 GNU 格式（`:` 匹配行 / `-` 上下文行 / `--` 组分隔）；`-l` 对 stdin 沿用
  GNU 的 `(standard input)` 显示名；输出模式优先序 `-l`/`-L` > `-c` > 普通。
  与 GNU 的有意分歧记录在 `grep.koral` 头注（`-o`+`-v` 报用法错、`-o` 不跨模式去重）。

- **正则就是 `std/text` 的 `Regex`**（始终 POSIX ERE，`REG_EXTENDED`），`grep` 自己
  没有引擎；方言保真（尤其 Windows 侧手写回溯引擎）是 runtime 的债，对拍
  `grep -E` 时会露出来。
- 行流走 `BufReader(stdin())` / `BufReader(File)` 的 `read_line`：尾换行随行带回，
  **末行无换行原样回写**（`grep` 语义，也是字节保真的钉扎点）。
- 退出码：0 有匹配 / 1 无匹配 / 2 出错（坏模式、文件打不开）。

### `grep-j`（未开工，最该做）

并行版 grep，撞并发面。**并发压力不需要正则引擎**——固定字符串匹配
（`grep -F` 语义）就能撞出 `Send` / `Sync` 缺口和 worker pool，与正则引擎解耦成
两个独立项目；黄金参照用 `grep -F`，还没有 ERE 方言问题。
worker pool 会和 `http` 重复（该不该抽象看分界判据，大概率先留在 sample）。

### `http`（未开工）

网络 + 并发整合（`net` / `async` / `sync` 三个面在样本里的第一次合流）。
阻塞 `net` + 线程每连接今天就能写；非阻塞 / poll 缺口只挡事件驱动规模，先不做。
worker pool 是分界判据的第二个用例（第一个在 `grep-j`）。

## 基名策略：有意不合并

类型显示拼法表里有三套**基名**策略，它们语义不同，**有意不合并**——
合了会让两个不同的东西显示成一个。见
[`identity-matching-tracking.md`](identity-matching-tracking.md) §23.2。

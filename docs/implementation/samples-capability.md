# samples 能力验证 —— 判据、缺口与被否的下沉

> **状态**：`cat`、`sha256sum`、`expr-eval` 已落地；`grep` / `grep-j` / `http` 未开工。
> `cat` 与 `sha256sum` 有黄金参照；`expr-eval` 是登记在案的例外（见「验证」）。
> 本文记**当前**的判据与裁定。

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
| **模块级常量无处安放** | file-scope `let` 必须带签名，没有模块级数据常量 |
| **无 `Send` / `Sync`** | `run_task` 能捕获任意 `type mutable`，`strong_count` 是 relaxed；并行样本没法表达「只能在线程间转移」 |
| **stdin / stdout 不是流** | 流式样本（`cat` / `grep`）只能整块读 |
| **无非阻塞 / poll** | 网络样本（`http`）的并发 I/O 模型表达不了 |

## 各样本要点与坑

### `sha256sum`（已落地）

字节 / 位运算 / 流式。黄金参照是 NIST 向量。

### `cat`（已落地）

字节流复制 + 多文件。黄金参照是 `coreutils cat`。

### `grep`（未开工）

- **POSIX ERE 方言**：`regcomp(..., REG_EXTENDED)`，黄金参照必须是 **`grep -E`**，
  不是默认的 BRE `grep`。用错参照会把方言差异当成实现缺陷。
- **两套正则引擎**：POSIX 侧用 `regcomp`，Windows 侧是手写回溯引擎。
  对拍必须意识到两边可能有方言差异。

### `grep-j`（未开工，最该做）

并行版 grep。会撞出 `Send` / `Sync` 缺口，以及 worker pool 在两个样本里重复
（该不该抽象看分界判据，大概率先留在 sample）。

### `http`（未开工）

网络 / 并发 I/O 模型。会撞出非阻塞 / poll 缺口。

## 基名策略：有意不合并

类型显示拼法表里有三套**基名**策略，它们语义不同，**有意不合并**——
合了会让两个不同的东西显示成一个。见
[`identity-matching-tracking.md`](identity-matching-tracking.md) §23.2。

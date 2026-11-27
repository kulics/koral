# 切片与统一存储块——实施规划

> **Status**：未开工（2026-11-27 规划）· 对应设计 [`../design/slice-design.md`](../design/slice-design.md)
> **范围**：分期、门槛、钉子清单与实施侧注意项。**决定的为什么**都在设计文档，本文只记怎么落。

## 分期

### P0 运行时与块基元（std/koral_runtime.* + C 钉）

- immortal 空块常量：`strong = weak = -1、len = cap = 0`，**放可写段**；增长/放块路径对负数哨兵
  **跳过 len 写**（.rodata 写陷阱 = 空列表首次 push segfault，承重条款）。
- 块 alloc intrinsic 统一：`[Control | len: Int | cap: Int | 元素区]`，元素区
  `align_up(24, alignof(T))` 起、`sizeof(T)` 步长；drop glue 走现有 `__koral_Dtor` 释放点
  单态化，块头不存 dtor。
- strong_count 读取助手（逃逸检查用）。
- C 钉扩展 `tests/runtime-cases/`：迁移 len 归零（防二次析构）、析构顺序、immortal 空块的
  retain/release/weak 早退、`free` 追踪器下的块账目。在案的 `refcount_release_race.c` 一族照走。

### P1 编译器表示层（koralc + compiler-reference 双镜像）

- `[]T` / `[]mutable T` 类型拼写**落五面**：koralc 解析器+AST、compiler-reference 解析器+AST、
  `toolchain/koral-syntax`（koralfmt CST/打印/宽度估计 + doc 生成 destructures）、
  `docs/guide/grammar.bnf`、`tests/compiler-cases/`。漏 koral-syntax 会被语料门拒收。
- 类型规则：`[]mutable T → []T` 单向隐式收窄（公理 3 例外已登记）；两者非 `sendable`；
  无字面量构造。
- 表示迁移：List/ByteBuffer/FrozenList 换块句柄（owner = 块句柄 + 版本；FrozenList 无版本）；
  String 值 16B `{块句柄, off: u32, len: u32}` 不变；空 owner/空窗持 immortal 空块。
- 合成 retain/release（`type` 值形 + 内部 ARC，同 String 先例）；泛型擦除位 NULL-dtor 是
  **已知洞**（在案），不扩不修。
- 下标规则：切片 `__index_get`/`__index_set`/`__index_slot` + Range 形（`s[a..<b]` 是 Range
  表达式实参，**不加新语法**，只加类型规则）；`[]` 内建覆盖行已登记 design-axioms。
- **双界检查进发射路径**（H1 修复的发射形态，承重）：窗口下标/方法访问统一发
  `i < w.len && off+i < 块.len`；迭代器每步一查（两界可折叠成一次 min 比较）；批量内在
  （拷贝/比较）入口一查。漏一条发射路径 = H1 重现。
- **六步验证链照走**（含 differential oracle）；两编译器一条声明两个 DefId 的坑见在案记忆。

### P2 std 切片面 + 修改纪律

- 切片方法面：`count`/`is_empty`/`get`/`first`/`last`/`contains`/`iterator` +
  `to_list`/`to_frozen_list`（拼写对齐 List 读侧）。
- 转换面：`String.as_slice`/`FrozenList.as_slice`/`CString.as_slice`；
  `String.from_slice` + `from_slice_unchecked`（from_bytes 家族成对）；
  `List.borrow_slice`/`into_slice`、`ByteBuffer.borrow_slice`/`into_slice`/`count`。
- 修改纪律：元素赋值存新→释旧；`remove_at` 收缩块 len；换块把旧块 len 归零（跳哨兵）；
  `clear` = 放块（不动旧块 len）；槽位置空仅调试卫生构建。
- 版本号（owner 字段，侦测式、结构计数）：捕获点=迭代器创建/回调方法入口/借出入口；
  检查点=for-in 每步/回调返回后/借出退出（**版本先、逃逸后**）；`retain` 改"先评后改"；
  `sort` 不检查、`sort_by` 交换不 bump。
- 逃逸检查：块 RC == 入口值（窗口建立后那份）；零长派生窗照折叠持根块。
- **`borrow_slice` 的 self 保留跨调用**（borrowed-self 优化不得覆盖此方法）——漏了就是检查
  读已释放 owner。
- 纯度/槽装载消去分析扩展：**窗口写判不纯**，`subscript_sibling_grow_guard` 四闸覆盖窗口下标
  （漏 = 借用实参消去配 UAF）。
- 迭代器对象 +8B（期望版本字段）。

### P3 io 迁移 + BufReader 帧

- 22 个 span 签名换切片（设计文档「API 变更清单」A 表逐条）；`Range.resolve_span` 从 io 面
  退役（保留给 Range 语义）。
- `BufReader.read_frame(): []UInt8`：帧 retain 块、Go 静默契约（覆写=陈旧字节、压缩/换块=
  块界 panic），回归两结局都要钉。
- fs 便利函数、`push_list`/`insert_list_at`/`push_string` 的 span 不在本期（设计 D 表登记）。

### P4 钉子、基准与文档收尾

- **测试钉**（compiler-cases + runtime-cases）：
  - 双界：窗界/块界越界 panic、remove 收缩后尾部窗读 panic、换块后旧窗读 panic；
  - `[]mutable String` 漂移槽（remove 平移后窗写不 UAF）、`[]UInt8` 零字节形；
  - 版本号：回调中 push/remove→panic；元素写/排序交换**不**panic；for-in 体结构修改→panic；
    切片迭代 + owner 修改→块界 panic；
  - 逃逸检查：存窗/派生子窗/零长窗/闭包捕获→panic；嵌套借出组合成立；
  - `into_slice`：残留别名见空壳、借出期间调 into_slice→panic；
  - 析构重入：clear 析构里再 clear/push、元素赋值旧值析构里同槽赋值；
  - immortal 空块：空列表首次 push 不 segfault、空窗合成释放早退；
  - 帧：覆写字节陈旧、压缩后帧读 panic、帧钉块不悬垂。
- **基准**（benchmarks/，量具纪律照走）：纯 push / 空体 for-in ≤ 1.10×；带体 map/for-in/求和
  ≤ 1.03×；`s[i]` 遍历 vs `xs[i]` ≤ 1.03×；小列表足迹（10⁶ 个 cap-8）按账面 +16～32MB 验收。
- **panic 文案**：版本/逃逸/越界 + 空槽（调试卫生）四类按 panic 锚点规则定锚；两编译器逐字一致。
- **文档同步**：as_/to_/into_/borrow_ 命名契约并入 std-api-design；guide 用法节（中英）；
  `[]` 覆盖行登记已做。

## 实施侧注意项（2026-11-27 拉取后评估）

- 81765f00 的**泛型作用域撞名修复**落了 mono 命名规约——块 glue 的单态化符号（per-T drop/
  alloc）命名走修复后的实例键规约，勿回退旧拼法。
- **弱句柄发射修复**（81765f00）确认 `__koral_WeakRef` 无 ptr 字段、弱的弱按值拷贝 +weak_retain
  ——块的 weak_count 只走 free 判定协议的设计前提不变。
- 4278b81b/77b7d3d7 的 SIGPIPE/stdio flush/进程组语义与块协议无关，但 **verify.sh 的钉子
  阶段已更新**——验证链按新脚本走。
- `docs/implementation/` 的成对登记惯例：落地后本文状态改 Implemented 并把各期实际落点
  补进分期小节。

## 风险看护（设计文档「风险与未决」的执行映射）

| 风险 | 看护手段 |
|---|---|
| 版本税超预算 | P4 基准门槛；超差先查依赖链，短路机制不预置 |
| 小列表足迹 +18% | P4 足迹案；std 内部小列表负载抽查 |
| 帧两结局回归收敛成一种 | P4 帧钉两种都钉 |
| 三项实施正确性前提（self 保留/immortal 空块/双界全路径） | P2/P4 钉子逐项对号 |
| 泛型擦除 NULL-dtor 泄漏（在案已知洞） | P1 明确不扩不修；可选块头 dtor 封堵留独立小项另批 |

# 切片与统一存储块——实施规划

> **Status**：Implemented（2026-11-27 规划 · 2026-11-27/28 落地）· 对应设计 [`../design/slice-design.md`](../design/slice-design.md)
> **范围**：分期、门槛、钉子清单与实施侧注意项。**决定的为什么**都在设计文档，本文只记怎么落。
> **落点速览**：P0 运行时三件 + C 钉；P1 双编译器五面全落（`[]T` = std 名义 + 语法糖，
> `TypeNode.Slice` 归约锚定 `Slice[T]`/`MutSlice[T]`）；P2 std 切片面 + 修改锁 +
> retain-first + 迁移置空；P3 io 22 签名迁移 + `read_frame`；P4 测试钉 22 项 + 文档同步 +
> 全链绿。实施途中另修两处真缺陷（视图返回约定、`clear = 放块`），见文末「实施途中破案」。

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
- 表示迁移：List/ByteBuffer/FrozenList 换块句柄（owner = 块句柄 + 修改锁；FrozenList 无锁）；
  String 值 16B `{块句柄, off: u32, len: u32}` 不变；空 owner/空窗持 immortal 空块。
- 合成 retain/release（`type` 值形 + 内部 ARC，同 String 先例）；泛型擦除位 NULL-dtor 是
  **已知洞**（在案），不扩不修。
- 下标规则：切片 `__index_get`/`__index_set`/`__index_slot` + Range 形（`s[a..<b]` 是 Range
  表达式实参，**不加新语法**，只加类型规则）；`[]` 内建覆盖行已登记 design-axioms。
- **双界检查进发射路径**（已随锁定案删除——窗口访问只发自身 len 界 `i < w.len`；
  陈旧槽由锁结构性封死）
- **六步验证链照走**（含 differential oracle）；两编译器一条声明两个 DefId 的坑见在案记忆。

### P2 std 切片面 + 修改纪律

- 切片方法面：`count`/`is_empty`/`get`/`first`/`last`/`contains`/`iterator` +
  `to_list`/`to_frozen_list`（拼写对齐 List 读侧）。
- 转换面：`String.as_slice`/`FrozenList.as_slice`/`CString.as_slice`；
  `String.from_slice` + `from_slice_unchecked`（from_bytes 家族成对）；
  `List.borrow_slice`/`into_slice`、`ByteBuffer.borrow_slice`/`into_slice`/`count`。
- 修改纪律：元素赋值存新→释旧；换块把旧块 len 归零（跳哨兵，纯账目）；`clear` = 放块；
  批量释放两形——放块/腾位形（clear/pop/remove_at/take_at，逐步一致、不加锁）与在位压缩形
  （retain/dedup 压缩段，**锁内运行**）；槽位置空退役（仅调试卫生）。
- **修改锁**（owner 字段 flag/深度计数，预防式）：加锁只在 std——借出闭包全程、带用户代码的
  List 方法全程（map/retain/sort/sort_by/binary_search_by/binary_search/contains/equals/compare/hash/dedup、
  迭代器终端）、批量释放压缩段；查锁进全部修改入口（mutator 全集 + 下标写 + into_* 族，含
  别名），命中 **入口立刻 panic**（锚点=肇事调用点）。for-in 不上锁不检查（回归钉）。
- **retain-first**（跨用户代码的元素引用保留形）：切片方法调用户代码前 retain 元素（contains
  的 equals）；sort/sort_by 暂存跨比较器保留形；回调实参/循环变量保留形（现状约定）。
- 逃逸检查：块 RC == 入口值（窗口建立后那份）；零长派生窗照折叠持根块。
- **`borrow_slice` 的 self 保留跨调用**（borrowed-self 优化不得覆盖此方法）——锁释放与逃逸
  检查读 owner，漏了就是操作已释放内存。
- 纯度/槽装载消去分析扩展：**窗口写判不纯**，`subscript_sibling_grow_guard` 四闸覆盖窗口下标
  （漏 = 借用实参消去配 UAF）。

### P3 io 迁移 + BufReader 帧

- 22 个 span 签名换切片（设计文档「API 变更清单」A 表逐条）；`Range.resolve_span` 从 io 面
  退役（保留给 Range 语义）。
- `BufReader.read_frame(): []UInt8`：帧 retain 块、字面 Go 静默契约（过期读 = 陈旧字节，
  唯一结局），回归钉看住"不悬垂、只陈旧"。
- fs 便利函数、`push_list`/`insert_list_at`/`push_string` 的 span 不在本期（设计 D 表登记）。

### P4 钉子、基准与文档收尾

- **测试钉**（compiler-cases + runtime-cases）：
  - 锁：回调/借出中 push/remove/下标写/clear/into_slice → **入口立刻 panic**（锚点=调用点）；
    经别名修改同 panic；sort 比较器中改表 panic；嵌套深度正确（借出+回调嵌套解一层仍锁着）；
    **窗写在借出中合法**（回归钉）；**for-in 体修改不 panic**（回归钉，游标语义）；
  - retain-first：切片 `contains` 的 equals 里窗写释放被查元素 → 安全；sort 暂存跨比较器
    窗写 → 安全；循环变量在 for-in 体里被 remove → 仍安全；
  - 窗界：`s[i]`/`s[a..<b]` 越界 panic；派生窗界限正确；
  - 逃逸检查：存窗/派生子窗/零长窗/闭包捕获→panic；嵌套借出组合成立；
  - `into_slice`：残留别名见空壳；
  - 析构重入：clear/pop/remove 析构里再 clear/push → 安全；retain 压缩段析构重入修改 → panic；
  - immortal 空块：空列表首次 push 不 segfault、空窗合成释放早退；
  - 帧：过期读 = 陈旧字节（唯一结局）、帧钉块不悬垂。
- **基准**（benchmarks/，量具纪律照走）：纯 push ≤ 1.05×（查锁一跳）；for-in **零回归**；
  带体 map/求和 ≤ 1.03×；`s[i]` 遍历 vs `xs[i]` ≤ 1.03×；小列表足迹（10⁶ 个 cap-8）按账面
  +16～32MB 验收。
- **panic 文案**：锁违规/逃逸/越界三类按 panic 锚点规则定锚（锁违规锚点 = 肇事修改调用点）；
  两编译器逐字一致。
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
| 锁税超预算 | P4 基准门槛；超差先查锁字段是否与 owner 同缓存行 |
| 小列表足迹 +18% | P4 足迹案；std 内部小列表负载抽查 |
| 帧契约看住（过期 = 陈旧字节且不悬垂） | P4 帧钉"不悬垂、只陈旧" |
| 三项实施正确性前提（self 保留/immortal 空块/retain-first 全持有点） | P2/P4 钉子逐项对号 |
| 锁覆盖清单完备性（D1 前提） | 加锁点/查锁点两清单对号；新增用户代码方法/修改操作须进清单，各留回归钉 |
| 泛型擦除 NULL-dtor 泄漏（在案已知洞） | P1 明确不扩不修；可选块头 dtor 封堵留独立小项另批 |

## 各期实际落点（2026-11-27/28）

- **P0**：`__koral_empty_block`（immortal 常量，可写段）/`__koral_block_alloc`（24B 头
  ABI + 8 对齐上限）/`__koral_strong_count` 三件入 `std/koral_runtime.*`；
  `tests/runtime-cases/block_sentinel_pin.c` 进 verify.sh runtime-stress（24B 头、
  alloc init 契约、immortal 哨兵 no-op）。
- **P1**：`[]T`/`[]mutable T` 五面（koralc 解析/AST/打印、种子解析/AST、koral-syntax
  CST/打印/宽度、grammar.bnf、compiler-cases）；选型=**std 名义 + 语法糖**
  （`TypeNode.Slice` 归约锚定 `Slice[T]`/`MutSlice[T]`，protected 拼写即可见性）；
  alloc/empty intrinsic 全链、下标 `__index_get`/`__index_slot`/`__index_range` 分派、
  `[]mutable T → []T` 收窄（CastExpr 结构体族发射）。
- **P2**：`std/slice.koral`（Block 块化名义 + Slice/MutSlice 24B 值窗 + 读侧方法面 +
  `contains`/`iterator`/`to_list`/`to_frozen_list`）；List/FrozenList/ByteBuffer 块化
  迁移（owner=块句柄+lock_depth）；**修改锁**（lock/unlock/with_locked 双助手、14 mutator
  入口查锁、map/retain/sort*/binary_search*/contains/equals/compare/hash/dedup 全程包锁）；
  **retain-first**（切片 contains/回调实参/循环变量/sort 暂存）；`borrow_slice`（锁+块 RC
  逃逸检查）/`into_slice`（掏空先于转移）；String/Bytes 统一化（`Bytes` 别名废除、
  字面量发内联块形）；`String.from_slice` 家族。
- **P3**：io 22 签名迁移（trait+全部 impl+测试见证）、`read_frame` 落、koralfmt 315/315+
  语料门 263/263。
- **P4**：测试钉 22 项（锁族 8 panic、逃逸/窗界 5 panic、retain-first/重入/窗写/游标/帧 7
  positive、方法面/下标基座 2 回归）；panic 文案三类
  （锁违规/逃逸/越界）两编译器逐字一致（同 std 源，differential 盖章）；命名契约并入
  std-api-design、guide 用法节（中英）。
  **基准实测**（`benchmarks/regression/`，基线=HEAD e964ab48 工作树 vs 现行，best-of
  交错跑）：for-in 求和 ✓ 零回归（现行反快 ~15%）；带体 map/求和 ✓ ~1.00×；`s[i]` vs
  `xs[i]` 同构建 ✓ ~0.8–1.3×（噪声内，中位 <1）；小列表足迹 ✓ +31.9MB（账面 +16～32MB 内）；
  纯 push 初测 ~2.3×（门槛 1.05×）未达，**经 push 实验后收敛到噪声地板内**（见下）。
  途中先修掉一项放大器：`self.block.len = x` 写回形会物化块句柄副本（每 push 一对
  retain/release + 不透明调用打断装载），改 Ref 形写回后纯 push 从 ~6× 收敛到 ~2.3×。

  **push 实验（2026-11-28）：~2.3× → 量具噪声地板（~1.0–1.15×）**。归因是三层连锁，
  缺一即每迭代重装 len（基线平铺布局的 len 是循环携带寄存器，统一块版全丢）：
  1. **`_Noreturn` 声明/定义失配**：codegen 按 `type_is_never` 给**声明**发 `_Noreturn`、
     **定义**漏发——clang 丢掉 noreturn，锁检查冷路径的 Never 助手调用退化成全量
     clobber 的 MemoryDef，热循环的 store→load 转发链整个作废。修=定义同缀（koralc
     `codegen_mir.koral` + 种子 `CodeGenMIR.swift`/`CodeGen.swift` 声明侧补齐对齐）。
  2. **len 住在 grow 变址槽**：块头 len 经块句柄间接，grow 换块即装载地址循环变；
     基线 len 在盒里、grow 不碰才能 phi 携带。修=盒侧热计数 `len`（grow 不变槽）+
     块头镜像恒同步（析构契约；镜像先写、盒存收口转发链）。
  3. **装载先于锁检查**：装载落在锁分支之后（非循环头块）时不提升/不转发。修=push
     先读 len 再查锁（锁门的是修改，读计数不是修改）。
  残余=~锁检查 2 指令（S1 设计税，地板）+ 块头 +16 寻址 1 指令（统一布局）+ 镜像存
  1 笔（「恒同步」稳健性选择）。量具轮间摆幅实测 ±15%（比值 0.86–1.16 翻），残余已
  落在噪声地板内。**候选再收**（未做，风险换收益交用户拍板）：镜像改「同步于暴露面」
  （`List: Drop` + 转移点同步，Drop 体先于字段释放已实证）省 1 存；cap/source 入盒
  （省 1 层依赖装载/1 条寻址指令）但换块点漏同步 = 越界/UAF 风险。

## 实施途中破案（两处真缺陷，均已修 + 钉）

1. **视图返回约定（P0 级 UAF/读 0 族）**：结果是裸指针的访问器（`__index_slot` 等）返回
   的是**基座内存的视图**——实参必须 +0 借入、基座活过延迟装载。koralc 侧 rule 5 把
   派生取址判成逃逸 → 接收者跑 owned 约定 + 末次使用移动 → 被调方释放基座后装载读已
   释放内存（`make()[1]`/`let v = t[1]`（t 临死）/同插值双下标三形状全中）。修法=种子
   `mirResultBorrowsArguments` 的镜像三处：`finish_call` 实参 ownership 全 Borrow、
   `lower_trait_method_call` 同规、`compute_borrowed_param_slots` 按结果类型无条件入表
   （被调方不释放 + vtable 释放网配平）。钉：`subscript_call_result_ok`。
2. **`clear = 放块`**：实现沿袭旧形（在位 drop + 清 len 保容量），与设计「owner 换
   immortal 空块、旧块交 RC-0」相悖；在位形的析构重入 push 会长进正在析构的块，扩容
   搬移把未初始化槽搬成句柄 = 二次析构。修=按设计改放块形。钉：
   `slice_destructor_reentry_ok`（自摘重入 + 封底链）。
   **测试侧坑**：`let _ = expr` 的临时活到**作用域尾**——pop/take_at 返回值的析构时机
   要收进助手帧；无界自生 drop 链（drop 里 push 无条件体）会把析构递归成栈溢出，探针
   要 id 递降封底 + 收尾解除武装。

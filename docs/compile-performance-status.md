# 编译性能：状态跟踪

日期：2026-09-26（release 构建 + 双模式上线）

本文档跟踪**编译速度**这项工作：问题定位、基线测量、已实施的改进、后续候选方向。
实施完成后更新文末状态表。

## 问题与结论

最初的判断是「编译慢因为生成的 C 文件太大」，打算在 MIR → codegen 之间做无效代码裁剪。
在最大的真实用例（用 Swift 编译出 bootstrap 的 C 文件）上实测后，结论是**两件事**：

1. **纯死代码裁剪给不出「大量减少」** —— 见下「无效代码裁剪：已评估、暂不实施」。
2. **真正的原因是宿主编译器一直在用 debug 构建** —— `compiler/.build/debug/koralc`。
   debug 的 Swift 二进制无优化、带完整运行时检查，对一个跑几百万次分配的编译器慢得离谱。
   改成 release 后 **`emit-c` 快 6.2 倍、端到端快 3.7 倍**，而且产物字节完全一致。

---

## 构建模式（已上线）

两个编译器都有 debug / release 两种模式。**跑测试和任何重复编译一律用 release**，
只有要单步调试编译器本身时才用 debug。

### 宿主 Swift 编译器

```bash
cd compiler
swift build -c debug       # -> compiler/.build/debug/koralc   （调试编译器用）
swift build -c release     # -> compiler/.build/release/koralc （跑测试 / 编大工程用）
```

### 生成二进制的构建模式（`koralc` 新增开关）

控制 clang 优化级，之前硬编码 `-O1`（`Driver.swift`）：

```bash
koralc build app.koral -o out --debug       # clang -O0 -g   不优化、可调试
koralc build app.koral -o out               # clang -O1      默认，行为与历史一致
koralc build app.koral -o out --release     # clang -O2      优化
koralc build app.koral -o out --optimize 3  # 显式指定 0/1/2/3/s/fast
```

默认仍是 `-O1`，不传开关时产物字节不变。

### 优化级实测：bootstrap 本体

用上面的开关把 bootstrap 本体在各优化级下编出来，测两头——编它自己要多久，以及它跑起来多快
（跑起来 = 让它去编 `tests/compiler-runner` 包）：

| 级别 | 编 bootstrap 自身 | 二进制体积 | bootstrap 运行（编 runner 包） |
|---|---|---|---|
| `-O0` | 55.5 s | 28,312,568 | **65.33 s** |
| `-O1` | 81.7 s | 6,449,032 | 10.21 s |
| `-O2` | 85.8 s | 6,564,264 | **9.85 s** ← 运行时最优 |
| `-O3` | 88.9 s | 6,934,680 | 9.92 s |
| `-Os` | 81.3 s | 5,851,464 | 11.39 s |
| `-Ofast` | 89.3 s | 6,934,680 | 9.93 s |

533 套件端到端（bootstrap 本体在各优化级下）：

| 级别 | 套件耗时 | 结果 |
|---|---|---|
| `-O1` | 267.9 s | 533/533 |
| `-O2` | 262.6 s | 533/533 |

**结论：**

1. **分界在 `-O0` 和其余之间**：`-O0` 比 `-O1` 慢 **6.4 倍**。`--debug`（`-O0 -g`）只用于调试，
   绝不能拿来跑测试或编大工程。
2. **`-O2` 是运行时最优，但只比 `-O1` 快 3.5%**（套件上 2%），代价是编 bootstrap 自身多花 5% 时间。
3. **`-O3` / `-Ofast` 不比 `-O2` 快**（9.92 / 9.93 vs 9.85），反而编译更慢、二进制更大；`-Os` 明显更慢。

所以默认 `-O1` 是站得住的选择；要榨那 2–4% 就给 bootstrap 加 `--release`。
默认值一行可改，若要改成 `-O2` 直接调 `Driver.swift` 的 `defaultOptimizeArgs`。

---

## 性能基线与实测

### 测量口径

- macOS (Darwin 27.0.0)，单次运行，未做缓存/预热控制；
- `emit-c` = 只生成 C（不含 clang），隔离 codegen 成本；
- `build` = codegen + clang + link 全程；
- 阶段拆分用 `KORAL_PROFILE_PHASES=1`。

复现：

```bash
D=compiler/.build/debug/koralc
R=compiler/.build/release/koralc

/usr/bin/time $R emit-c --package-config bootstrap/koral.json --target-module koralc -o /tmp/b/emit
/usr/bin/time $R build --package-config bootstrap/koral.json --target-module koralc -o /tmp/b/build

# 阶段拆分
KORAL_PROFILE_PHASES=1 $R build --package-config bootstrap/koral.json --target-module koralc -o /tmp/b/build
```

### 宿主编译器：debug vs release（目标 = `bootstrap/koral.json`）

| 指标 | debug 宿主 | release 宿主 | 提升 |
|---|---|---|---|
| `emit-c` 耗时 | 264.6 s | **42.9 s** | **6.2x** |
| `build` 耗时（codegen + clang） | 303.1 s | **81.9 s** | **3.7x** |
| 生成 C 体积 | 110,376,946 B | 110,376,946 B | 相同 |
| 产物二进制 | 6,449,032 B | 6,449,032 B | 相同 |

产物逐字节一致 —— 变的只是宿主编译器自己跑得快，语义未动。

### 阶段拆分（release 宿主，`bootstrap/koral.json`）

`emit-c` 合计 41.9 s：

| 阶段 | 耗时 | 占比 |
|---|---|---|
| type check | 951 ms | 2% |
| monomorphize | 4,034 ms | 10% |
| mir | 4,382 ms | 10% |
| **codegen** | **32,512 ms** | **78%** |
| — 其中 function-implementations | **32,175 ms** | 77% |
| — 其中 type-declarations | 127 ms | 0% |
| — 其中 foreign-declarations | 168 ms | 0% |

`build` 合计 81.3 s：codegen 32.4 s + **clang 39.2 s（48%）** + 其余约 9.7 s。

**两个结论：**
1. **78% 的 codegen 时间花在往 C 里写 8,252 个函数体** —— 压 C 体积 / 并行生成确实打在点子上。
2. release 模式下**最大单项是 clang（39.2 s）**，因为要在 105 MB 的**单个翻译单元**上跑优化。

### 测试套件（533 用例）

| 模式 | 结果 | 套件耗时 |
|---|---|---|
| debug 宿主 + 默认 `-O1` | **533/533** | 60.1 s |
| release 宿主 + 默认 `-O1` | **533/533** | 48.2 s |
| release 宿主 + `--release`（`-O2`） | **533/533** | 51.1 s |
| release 编出的 bootstrap + 默认 `-O1` | **533/533** | 262.8 s |

`-O2` 下 533/533 说明生成的 C 没有会被更高优化级暴露的未定义行为。

---

## 无效代码裁剪：已评估、暂不实施

原计划在 MIR → codegen 之间做可达性裁剪。在 `koralc.c`（105 MB / 3,040,675 行 / 8,252 个函数）上实测后搁置。

### C 文件构成

| 类别 | 函数数 | 字节 | 占文件 |
|---|---|---|---|
| `__mono_method_*`（单态化出来的方法） | 3,088 | 71,074,096 | **64.4%** |
| `Koralc_*`（编译器自身方法） | 520 | 29,316,391 | **26.6%** |
| 容器 `List/Dict/Set/…` | 1,827 | 6,647,540 | 6.0% |
| codegen 合成的 copy/drop 辅助 | 2,636 | 983,573 | **0.9%** |
| `Std_*` | 75 | 489,494 | 0.4% |

函数体占文件 **98.6%**。体量极度头部集中：**前 145 个函数就占了函数体字节的一半**。
最大单个函数体 `__mono_method_S_736_..._check_call_expr_ref` 有 **102,237 行 / 3.35 MB**
（22,483 条 `if`、1,767 个基本块）。

### 可达性余量

以 `main` 为根做调用图可达性：

| 项 | 数量 | 字节 |
|---|---|---|
| 函数定义总数 | 8,252 | 108,847,463 |
| 可达 | 6,102（73.9%） | 95,545,377（87.8%） |
| **不可达** | **2,150（26.1%）** | **13,302,086（12.2%）** |
| 只被死代码引用的结构体 | 159 / 1,527（10.4%） | — |
| 不可达的 `__mono_*` 实例 | 1,135 / 3,088（36.8%） | 5,859,687 |

**12.2% 是上限，不是预估。** 该分析看不到 vtable 间接调用，因此把一部分其实活着的函数算成了死的；
建模 vtable 边之后真实可删只会更少。

### 为什么不靠裁剪

- 91% 的字节是 `__mono_method_*` + `Koralc_*`，即编译器自己的类型检查器/解析器，**都是活代码**；
- codegen 合成的 copy/drop 辅助只占 **0.9%**，类型级裁剪在这上面几乎没有油水；
- 巨大的函数体是**活的**，裁剪碰不到。

若要真正「大量减少」，得压**活代码**的体积，那属于另一个量级的工作（泛型函数体共享以减少单态化、
或降低 C 输出冗余度），见下。

---

## Bootstrap 慢在哪里：profile 结论与已实施优化

### 差距有多大

同一目标、同一口径（`check` = 解析 + 类型检查）：

| 目标 | Swift | Bootstrap（优化前） | 倍数 |
|---|---|---|---|
| trivial / hello | 0.06 s | 2.8 s | ~45x |
| runner 包 | 0.15 s | 7.8 s | 52x |
| bootstrap 包（99k 行） | 1.40 s | 191.2 s | **136x** |
| emit-c（runner 包，含后段） | 0.53 s | 9.2 s | 17x |
| 533 套件 | 50.4 s | 262.6 s | 5.2x |

关键对照：**`--no-std` 下 bootstrap 0.005 s vs Swift 0.009 s——编译器本身不慢**。
带 std 后 bootstrap 2.82 s，即 **std 的类型检查是大头，且每次编译都重做**。
（std 编译缓存两侧都没有，本期不做。）

### Self-time 热点（优化前，`sample` 采样 runner 包 `emit-c`）

| self | 占比 | 项 |
|---|---|---|
| 3187 | **12.0%** | `lookup_current_file_def_id` |
| 3069 | 11.5% | `__koral_release`（ARC） |
| 2325 | 8.7% | `__koral_retain`（ARC） |
| 1389 | 5.2% | `Dict_U_Std_String_find_slot` |
| 1377 | 5.2% | `Eq_equals`（串比较） |
| 1368 | 5.1% | `lookup_current_file_type_symbol` |

归类：**name/def 查找 23.3%**、ARC 20.3%、Dict/串哈希 18.4%。

### 已实施 1：删除按名字找 DefId 的整条路径

`type_checker_visibility.koral` 的 `lookup_current_file_def_id` 原先**对整个程序所有 DefId 做线性扫描**，
扫不到才落到 `context.lookup_def_id(...)`。后者才是正确的身份机制——`allocate_full` 注册时建的
`(module_path, name, source_file)` 键表，O(1)，且正确区分 file-private 键。`get_or_allocate_top_level_def_id`
（`type_checker.koral`）就是用它的。

也就是说这个线性扫描是 `get_or_allocate_top_level_def_id` 的**残缺重复实现**。`type_checker_decls.koral` 里
甚至把正确答案放在兜底位：

```koral
let fallback_type = Type.StructureType(self.get_or_allocate_top_level_def_id(name, ...));
let resolved_struct_type = self.lookup_current_file_type_symbol(name) or else fallback_type;
```

改法：**删掉扫描，直接走键查表**，`lookup_current_file_def_id` 缩成一行委托。
净代码量是减少的（中途试过的 `name_candidates` 同名候选索引也一并删掉了——它是给错误抽象打补丁，
且比直接查表慢 2 倍）。

### 已实施 2：`Dict` / `Set` 用掩码代替取模

`find_slot` 原先每次探测都做 `% capacity`（整数除法）。`new()` 从 16 起、`rehash` 每次翻倍，桶数本就是
2 的幂；把 `with_capacity` 也规约成 2 的幂后，`& (capacity - 1)` 与 `% capacity` 等价但省掉除法。
`UInt.hash()` 是恒等映射，所以 `Dict[UInt, X]`（`DefIdMap` 里 28 张表）每次查找原本都在做整数除法。

### 已实施 3：codegen 的 DefId 反查索引

`codegen.koral` 里 `is_foreign_function_def_id` / `is_foreign_global_var_def_id` /
`is_foreign_type_def_id` / `concrete_struct_fields_from_program` / `concrete_enum_cases_from_program`
原先每次调用都全量扫 `program.globals`（是 O(N)×调用次数）。改成构造时一次预热建索引
（`build_def_id_indices`），之后 O(1) 查表；同 id 重复时用 `try_insert` 保持「取先出现者」语义。

**实测收益 ≈ 0**（check hello 1.00x、runner 包 1.00x、bootstrap 包 1.00x）。索引本身生效了
（`is_foreign_type_def_id` 从 self-time 3.2% 消失），但那些扫描本来就没占多少墙钟——
我此前把「30+ 处全量遍历」当成了热点，判断错了。改动保留，属于可扩展性/代码质量修复：
不依赖 DefId 稠密（模块导出后会稀疏），且五个 helper 缩成一行。

### 已实施 4：ARC 快路径内联（L1）

对照 Swift 为何更快：Swift 的 MIR 规则与我们**完全相同**
（`MIRLowerer.swift:496`：lvalue→copy / rvalue→move，同样没有最后使用点分析），
它的 ARC 是交给 SIL/LLVM 的 `ARCOptimizer` 消掉的，`swift_retain`/`swift_release` 对优化器透明。

而我们的 `__koral_retain`/`__koral_release` **定义在 `koral_runtime.c`**，生成的 C 里
每次引用计数都是不透明函数调用——LLVM 看不到函数体，一对都消不掉，还多一层调用开销。

改法（对齐 Swift 运行时的「快路径内联、慢路径外联」）：

```c
// koral_runtime.h
void __koral_release_slow(struct __koral_Control* control);

static inline void __koral_retain(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    atomic_fetch_add(&control->strong_count, 1);
}

static inline void __koral_release(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    int prev = atomic_fetch_sub(&control->strong_count, 1);
    if (prev == 1) { __koral_release_slow(control); }   // 析构 + 释放外联，不撑大调用点
}
```

`koral_runtime.c` 里的重复定义删除，只保留 `__koral_release_slow`。

**收益（min-of-4）：**

| | L1 前 | L1 后 | |
|---|---|---|---|
| check hello | 0.184 s | 0.166 s | **1.11x** |
| check string_methods | 0.189 s | 0.170 s | **1.11x** |
| check runner 包 | 0.393 s | 0.356 s | **1.10x** |
| 533 套件 | 69.9 s | **62.3 s** | **1.12x** |

正确性：**Swift 533/533**（49.2 s）、**Bootstrap 533/533**（62.3 s）。

### 已尝试并回退：哈希散列器


`UInt.hash()` 是 `self`（恒等），而 `DefIdMap` 的键正是 `Dict[UInt, X]`。业界标准做法是在 **map 内部**
做散列而不是改 `key.hash()`（对齐 Java `HashMap.hash = h ^ (h >>> 16)`）：

- Java `HashMap.hash()` —— XOR 折叠高位
- Rust `FxHash` / Knuth Fibonacci hashing —— **乘法混合器** `h * 0x517cc1b727220a95`
- Go `memhash`、Swift `Dictionary` 的 SipHash、Abseil SwissTable 的 H1 —— 都拒绝恒等哈希

按 FxHash 乘法常量在 `find_slot` 内实现后实测：

| | 无散列 | 有散列 |
|---|---|---|
| check hello / string_methods / list_test | 0.189–0.205 s | 0.191–0.208 s |
| check runner 包 | 0.407 s | 0.412 s |

**零收益（0.98–0.99x，在噪声内）**——今天的 DefId 是连续的 1..N，恒等哈希本来就散得开，混合器只在
id 稀疏/对齐时才见效。更关键的是它**改变了 `Dict`/`Set` 的迭代顺序**，而 `for_loop_basic.koral`
把桶序钉进了期望输出（`Dict iteration: b -> 2 / a -> 1`）→ 532/533。

零收益 + 破坏一个测试，因此**回退**。等模块导出使 DefId 变稀疏后再回头做，届时需要一并裁定
**`Dict`/`Set` 迭代顺序是否属于语言契约**：若不属于，`for_loop_basic` 不该钉桶序；若属于，散列器就不能改。

### 收益实测（累计）

| 目标 | 基线 | 最终 | 提升 |
|---|---|---|---|
| check hello | 2.829 s | **0.198 s** | **14.3x** |
| check string_methods | 3.027 s | **0.202 s** | **15.0x** |
| check list_test | 0.514 s* | 0.205 s | — |
| check runner 包 | 7.805 s | **0.416 s** | **18.8x** |
| **533 套件** | **262.6 s** | **72.0 s** | **3.65x** |

\* list_test 基线未单独测，此处列的是中途值作参考。

分阶段：去掉线性扫描后 262.6 → 98.3 s；再加 `Dict`/`Set` 掩码 → 84.6 s；
最后删掉多余的 `name_candidates`、直接走键查表 → **72.0 s**。

### 正确性验证

| 项 | 结果 |
|---|---|
| 533 全量（优化后 bootstrap） | **533/533**，98.3 s |
| 533 全量（Swift，回归确认） | **533/533**，50.2 s，无变化 |
| C 产物字节一致 | runner 包 + `hello` + `string_methods` + `list_test` **全部 SHA-256 一致** |


### 已尝试并回退（二）：copy-on-last-use（L2/L3 安全版）

目标是把「本该 move 却 copy」的对消掉。codegen 侧机制其实已经齐备——
`emit_place_read` 对 `Move()` 直接返回原地（不 copy），并调用 `consume_moved_place`
抑制源的 drop；缺的只是把 ownership 标成 `Move`。Swift 的 `ownershipUse`
（`MIRLowerer.swift:496`）规则与我们相同（lvalue→copy），它靠 SIL 的 `ARCOptimizer`
做 `isLastUse`/`move_value`，我们没有 SIL，所以想在 MIR 层自己做。

做了一个「安全版」后处理：只处理**赋值一次、`PlaceRead(Local, Copy())` 一次、
两次提及分处不同语句、全函数再无任何其它提及**的局部量。实测 **530/533**，两类失败：

**1. 循环漏洞（SIGSEGV）** —— `sync_mutex_test` / `sync_channel_test` exit=139。

判据按**静态**语句计数，但循环让一条语句执行多次：

```
x = make();
while ... { use(copy(x)); }   // 静态 1 次读，动态 N 次
```

静态看是「1 赋 + 1 读」→ 判为可 move → 第一次迭代就把 x 搬空，后续迭代读已释放内存。
**静态提及数 ≠ 动态执行次数**，绕不开循环就得做真正的活性分析。

**2. 析构顺序改变（可观察）** —— `pair_destructuring_drop` case5：

| | 输出 |
|---|---|
| 期望 / 优化前 | `Drop 79` 然后 `Drop 80` |
| 优化后 | `Drop 80` 然后 `Drop 79` |

两个 drop 都还在（无泄漏、无 double-free），但**次序反了**。move 让值不再在源的作用域退出时析构，
而是跟着目标走，析构次序随之改变。

**结论：L2 不是纯优化**，它会改变可观察的析构顺序，与哈希散列器遇到的迭代顺序是同一类问题——
**需要先裁定析构顺序是否属于语言契约**，才能决定这条路线能不能走。

已回退到 L1 状态，**533/533 恢复**。

---

## 已评估、不做：Ref 布局（胖指针 → 单指针）

`Ref` 现状：

```
值      struct { void* ptr; void* control; }     ← 16 字节
分配    [ __koral_Control (24B) | payload ]
        Control { strong(4), weak(4), dtor(8), ptr(8) }   ← ptr 冗余
```

**发现**

1. **胖指针的立论理由已经消失。** `make_ref`/`make_mut_ref`（共享 control、`ptr` 指向宿主内部
   字段的子引用）只剩 `koral_runtime.h` 里一句注释，运行时与 codegen 里都不存在——
   那是「简化类型系统」迁移删掉托管引用表层（`*T`/`?*T`/`box()`）时的遗留。
2. **`Control.ptr` 完全冗余。** 合并分配约定是 `[Control | payload]`，payload 固定在 `control + 1`。
   全运行时只有 2 处用到它（`dtor(control->ptr)`、`upgrade_ref` 里回取 payload）。
3. **托管 nominal 值都是 16 字节。** `String`/`List`/`Dict`/`Option[...]` 的每个局部量、字段、
   参数、返回值。比 `__koral_Ref`（105 MB 的 C 里总共只出现 5,146 次）重要得多。
4. **借用形态窄而明确。** 2,476 处 `control = NULL` 全是 vtable wrapper 里的 `__koral_self`
   （把 `self` 当借用引用传给实际方法），不是普遍现象。

**为什么不做（实测）**

单指针能省的是「16 字节双字拷贝」这件事。它在 self-time 里占多少：

| | 占 self-time |
|---|---|
| 托管值 `_copy` 辅助函数 | **0.7%** |
| 托管值 `_drop` 辅助函数 | **2.0%** |
| **合计** | **2.7%** |

唯一算得上热点的 `_copy` 是 `__koral_Koralc_MIRGlobal_copy`（0.64%）——那是拷 **`MIRGlobal` 大枚举**，
与值宽度无关；`__koral_Std_String_copy` 那些真正的托管值拷贝没进 top 200。
而且 `_copy` 函数体里大头是 `retain`，不是那 16 字节的 memcpy。

**收益上限 1–3%，成本却是动运行时 ABI + codegen 值表示 + 所有 copy/drop + vtable wrapper +
trait object**，且落在所有权敏感区（L2 就是在这里翻的车）。投入产出不成比例。

`Control.ptr` 那 8 字节是真实的设计债（该清理但不急），实测也不会超过 2%。

**若将来要做**，借用形态是唯一阻碍，三条出路：借用走独立类型（Swift 的 guaranteed 参数做法）／
字面量给静态不可变 control 块（Swift 的 immortal object）／vtable wrapper 改传裸指针。

---

## 已评估、不做：类型解析跳过无变化重建（A）

### 立论

`resolve_types_in_expression` 在 monomorphize 之后跑一遍，把每个 `TypedExpr` 节点**无条件重建**。
实测它的类型解析部分几乎不做事：

| | |
|---|---|
| `resolve_parameterized_type` 调用 | 198,183 次 |
| 命中缓存 | 197,214（**99.5%**） |
| 真正解析 | 969（**0.5%**） |

加了缓存快路径实测 **1.00x**——连容器分配都不是成本。所以成本全在**重建节点**上，
方案 A = 「递归结果无变化就返回原节点，不重建」。

### 为什么重建在 Koral 里贵（容器 / clone 的调查结论）

先查了「Koral 容器不 COW，会不会有大量多余 clone」——**结论是没有**：

1. `List`/`Dict`/`Set` 是 `type mutable` → Managed → ARC。赋值是
   `result = *self; __koral_retain(result.control)`，**O(1)，根本不 clone**。
   比 Swift 的 COW 还便宜（连写时复制都没有）。
2. `List.clone()` / `Dict.clone()` 存在，但 `bootstrap/koralc` **一次都没调用**。
3. 生成 C 里的 `__koral_*_copy` 调用点（`list_test` 1197 处）已由 L2 实测过，消掉它们收益 ≤1%。

真正贵的是同一件事的另一面——**递归枚举是装箱的**：

| | 重建一个 AST 节点 |
|---|---|
| Swift | `TypedExpressionNode` 是内联 enum，几乎免费 |
| **Koral** | `TypedExprKind` / `Type` 因自引用被判定 Managed，值是 `{ptr, control}` + **一次堆分配** |

即 `TypedExpr` 重建 = 2 次 malloc。这就是 resolve 一趟占 monomorphize 81% 的原因。

### 实测：天花板

把 `resolve_types_in_expression` 整趟短路（返回原节点），重建 bootstrap，比阶段耗时：

**runner 包 `emit-c`（墙钟 0.94 s）**

| 阶段 | 基线 | resolve 短路 | 差 |
|---|---|---|---|
| type check | 256 ms | 259 ms | — |
| **monomorphize** | **96.5 ms** | **17.9 ms** | **-81%** |
| mir | 75.6 ms | —（失败于 verify） | — |
| codegen | ≈450 ms | — | — |

**小用例（533 套件的典型形态，`drop_test`）** — 墙钟 0.26 s

| 阶段 | 耗时 | 占比 |
|---|---|---|
| type check | 124.3 ms | 48% |
| **monomorphize** | **22.9 ms** | **9%** |
| mir | 19.6 ms | 7% |
| codegen | ≈76 ms | 29% |

→ resolve 占 monomorphize 的 81%，但 monomorphize 本身只占 9–10%。
**A 的天花板是 5–8%**，且这是短路*整趟*的上限（含必须做的那部分），实际还要再打折扣。

与 L2（≤1%）、Ref 布局（≤2.7%）同量级偏上。**按既定标准不做。**

`substitute_types_in_expression` 只在泛型函数体上跑（173 个 body），实测并入短路后的
17.9 ms 之内，**不是独立的大头**。

---

## 已实施 5：别名导入线性扫描 + 源文件路径规范化分配

### 病理（与已修的 `lookup_current_file_def_id` 同一类）

`try_resolve_named_type_without_diag` 对每个命名类型都会走一遍
`resolve_imported_alias_type`，而它是**对整个 `symbol_imports` 做线性扫描**，
每一项还要比较源文件路径——比较本身又是**两侧各重建一个字符串**：

```koral
normalize_source_file_for_match(s) == normalize_source_file_for_match(c)
// 内部：path.to_runes() + StringBuilder + push_rune + to_string()
```

而规范化只做一件事：把 `\` 映射成 `/`。POSIX 路径下这是恒等映射，却每次都
`to_runes()` + 逐码点 `StringBuilder` 重建两遍。大目标（bootstrap 包）实测这一条
路径占类型检查的 **35%**（`source_file_matches` 34.9% / `normalize_source_file_for_match` 33.5%）。
Swift 同口径**完全没有这一项**。

### 改法

1. **`ImportGraph` 加按名字索引** `symbol_imports_by_name`（`symbol` 与 `original_symbol` 都入键），
   `add_symbol_import` / `merge` 时维护。三个别名解析器 + `get_import_kind` 从线性扫描改成
   一次哈希查找；候选列表按 `symbol_imports` 顺序排列，倒序遍历以保持「同名多条取靠后者」的既有语义。
   过滤条件（模块 / 源文件 / 具体字段）原样保留，语义不变。
2. **`source_file_paths_equal` 逐字节比较、把 `\` 当 `/`，零分配**。`\`/`/` 都是单字节
   且不会出现在 UTF-8 续字节里，规范化也不改变字节长度，所以与「先规范化再比较」完全等价。

### 收益

| 目标 | 前 | 后 | |
|---|---|---|---|
| **bootstrap 包 check** | 5552 ms | **3568 ms** | **1.56x** |
| runner 包 check | 355 ms | 306 ms | 1.16x |
| 小用例 check | 164 ms | 165 ms | 1.00x |
| **533 套件** | 72.0 s | **67.6 s** | 1.06x |

**533/533 全绿。** 程序越大收益越高（别名查找次数随用户代码增长）；
小用例里 std 是主体，别名查找不是瓶颈——见下。

---

## 发现：`check` 的 3 倍差距 100% 在 std

同一小用例（`drop_test.koral`）：

| | 带 std | `--no-std` |
|---|---|---|
| Swift `check` | **0.05 s** | 0.00 s |
| Bootstrap `check` | **0.15 s** | 0.00 s |
| | **3.0x** | |

两侧 `--no-std` 都是 0.00 s，即**编译器本身不慢，差距全部在 std 的 parse + type-check**，
而它**每次编译都重做**。533 套件 72.0 s ≈ 533 × 0.15 s，几乎整个套件就是 533 次 std 类型检查。

这不是「std 编译缓存」（两侧都没有，做了不改变相对差距），而是**把 std 的类型检查本身变快 3 倍**
才能缩掉 check 的差距。

### 实测构成：小用例（std 主导）两侧对照

口径：`check` 同一小用例，`xctrace` 采样（bootstrap 13,143 samples / Swift 7,959 samples）。

| | Bootstrap | Swift | |
|---|---|---|---|
| 墙钟 | 168 ms | 58 ms | **2.9x** |
| 解析 / 词法 | 19% | 37% | |
| **类型检查** | **78%** | **49%** | |
| 类型检查绝对耗时 | **131 ms** | **29 ms** | **4.6x** |

差距在**类型检查的单位成本**，不是解析。类型检查内部 self-time：

| | Bootstrap | Swift |
|---|---|---|
| **分配器**（malloc/free 全家） | **27%** | 10% |
| **哈希 + 相等**（`trait_Hash_hash` / `trait_Eq_equals`） | **17%** | 13%（`Dictionary.find` + `Hasher`） |
| **`for i in 0..<n` 迭代器**（`Range_U_iterator`） | **3.9%** | **0** |
| 容器 `new`/`drop` 抖动 | ≈5% | — |

两点结论：

1. **哈希/相等两边占比接近**（17% vs 13%），不是差距来源；**分配是 27% vs 10%**，
   才是 Koral 侧额外付的账。
2. **`for i in 0..<n` 在 Koral 里要走 `RangeIterator` + `Option`**，Swift 是直接整数循环，
   这部分成本 Swift 侧为 0。编译器里最常见的循环就是它。

大目标（bootstrap 包）的构成完全不同——那里的热点是别名导入扫描（35%，已修），
所以「打 std 类型检查」和「打大程序」是两件事，需要分别治。

---
## 已实施 6：`for` 循环专用降低（区间循环不走迭代器）

### 病理

`for x in a..<b` 原先走通用的 for-in 降低：

```
let __iter = iterable.iterator();      // RangeIterator 是 type mutable → 装箱托管值，一次堆分配
while true then {
  when __iter.next() in {              // 每步一次调用 + Option 装箱
    .Some(x) then body, .None() then break
  }
}
```

对区间循环这些全是纯开销——起点、终点、步进在降低时就是已知的。
实测（std 类型检查内部 self-time）：`Range_U_iterator` 3.9%，而 `String.hash()` /
`String.equals()` 内部也是 `for i in 0..<len`，把这层开销放大到每次 Dict 查找。

**注意与「手动把 std 里的 for 改成 while」的区别**：那是在错误的层次上打补丁，
语言写法一变就失效。这里是在编译器里给 `for` 做专门的降低，源码不动。

### 改法（Swift 先行，再同步 bootstrap）

`inferForExpression` / `lower_for_expr` 前面加一条区间专用路径，把迭代状态摊平成本地计数器：

```
let mutable i = a;
let end = b;
while i < end then {
  let x = i;                    // 绑定每轮取值
  i = i.succ().unwrap();        // 先自增
  <body>                        // 再跑 body
}
```

先自增再跑 body，`continue` 直接回到条件判断，不需要收尾逻辑；`break` 自然生效。
`succ()` 在 `i < end` 时不可能返回 `None`（`end` 本身是一个 `T`，故 `end <= max_value`），
所以 `unwrap()` 不会触发。

**适用范围**：有界闭开区间 `a..<b`（`for i in 0..<n` 是压倒性的常见写法）+ 简单绑定（含 `_`）。
`a..=b`（末元自增会碰到 `max_value`）、半开/无界区间、解构绑定、非区间可迭代对象
**仍走通用迭代器路径**，语义不变。生成的 C 里 `RangeIterator` 出现次数为 **0**。

### 收益

| 目标 | 降低前 | 降低后 | |
|---|---|---|---|
| 小用例 check | 169 ms | **109 ms** | **1.55x** |
| bootstrap 包 check | 3612 ms | **2654 ms** | **1.36x** |
| 533 套件 | 67.6 s | **60.9 s** | 1.11x |

连带把 **#3 哈希/相等** 一起打了：`String.hash()`/`equals()` 的内层是 `for i in 0..<len`，
类型检查内部的「哈希 + 相等」self-time 从 **17% 降到 6.5%**。
Swift 侧无变化（Swift 的 `for i in 0..<n` 本来就是零开销整数循环）——这项收益全部落在 Koral 代码上。

---

## 已实施 7：容器懒分配 + 词法标识符重复物化

- **`List.new()` / `Dict.new()` / `Set.new()` 不再预分配**：空容器是 `null` 指针，首次
  `push`/`insert` 时才分配（`find_slot` 对 `capacity == 0` 直接返回 `.None()`，`rehash`
  从 16 起步）。编译器里每个 `Scope` 带 5 个容器，大量是空的或只有一两项。
  对应 Swift `Array`/`Dictionary`/`Set` 的空实例零缓冲语义。
- **`read_identifier` 里 `text.to_string()` 原先调两次**（关键字判定一次、`Identifier(...)` 构造一次），
  非关键字标识符每个都付两次堆分配。改成物化一次复用。

| 目标 | 前 | 后 | |
|---|---|---|---|
| 小用例 check | 110 ms | **104 ms** | 1.06x |
| bootstrap 包 check | 2667 ms | **2557 ms** | 1.04x |

---

## 后续候选（不在本期）

依据上面的阶段拆分，收益从高到低：

| 手段 | 打击目标 | 预期 | 成本 |
|---|---|---|---|
| **拆 C 成多个翻译单元 + 并行 clang** | clang 39.2 s（48%） | 39.2 s → 约 8–15 s，峰值内存大降 | 中 |
| **并行生成 C** | codegen 32.5 s（40%） | 函数体彼此独立，可分片 | 中 |
| **压 C 冗余度**（不改语义） | C 体积 → codegen + clang | 平均每函数 368 行，`if` 守卫/临时量/init-flag 可收紧 | 中高 |
| **std 预编译成 .o 复用** | 小用例构建 | 测试套件大幅变快 | 中 |
| **泛型函数体共享**（少单态化） | `__mono_method_*` 64.4% | C 缩减最大，但可能伤运行时性能 | 高 |

---

## 验证口径

| 项 | 口径 |
|---|---|
| 功能正确性 | `./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/release/koralc -j=8` → **533/533** |
| | `--compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc -j=8` → **533/533** |
| 默认行为不变 | 不传优化开关时 clang 仍 `-O1`，产物字节与历史一致 |
| 调试路径可用 | `--debug`（`-O0 -g`）产出可调试二进制，全套用例仍绿 |

---

## 状态

| 项 | 值 |
|---|---|
| 基线测量 | **已完成** |
| release vs debug 实测对比 | **已完成**（emit-c 6.2x / build 3.7x） |
| 阶段耗时拆分 | **已完成**（codegen 78% / clang 48% of build） |
| 双模式构建（Swift + koralc 构建模式开关） | **已完成**（`--debug`/`--release`/`--optimize`，默认 `-O1`） |
| 优化级扫描 | **已完成**（`-O2` 仅比 `-O1` 快 3.5%；`-O0` 慢 6.4 倍） |
| 删除按名字找 DefId 的线性扫描 | **已完成**（直连 `allocate_full` 的键表） |
| `Dict`/`Set` 掩码代替取模 | **已完成** |
| codegen DefId 反查索引 | **已完成**（收益 ≈0，属可扩展性修复） |
| **ARC 快路径内联（L1）** | **已完成**（check 1.10–1.11x，套件 1.12x） |
| 哈希散列器 | **已尝试并回退**（今天零收益 + 改变迭代顺序使 `for_loop_basic` 失败） |
| 类型解析跳过无变化重建（A） | **已评估、不做**（天花板 5–8%；且容器不 COW 并未导致多余 clone） |
| `check` 3 倍差距定位 | **已完成**（100% 在 std 的 parse + type-check，两侧 `--no-std` 都是 0.00 s） |
| **别名导入索引 + 路径比较零分配** | **已完成**（bootstrap 包 check 1.56x，533 套件 1.06x，533/533） |
| **`for` 区间循环专用降低** | **已完成**（小用例 1.55x、bootstrap 包 1.36x；哈希/相等 17%→6.5%） |
| **容器懒分配 + 标识符重复物化** | **已完成**（1.04–1.06x） |
| 与 Swift 的差距 | check **1.78x**（原 45–136x）；533 套件 **1.24x**（原 5.2x） |
| 全量验证 | **Swift 533/533**（49.0 s）、**Bootstrap 533/533**（60.9 s） |
| std 类型检查累计收益 | 小用例 check **164.3 → 103.9 ms（1.58x）**；bootstrap 包 check **5552 → 2557 ms（2.17x）** |
| 无效代码裁剪 | **已评估、暂不实施**（上限约 12%） |
| 临时调试代码 | 无 |

### 剩余优化空间（L2/L3/L4，未做）

| 层 | 做法 | 对应 Swift | 风险 |
|---|---|---|---|
| L2 | MIR 层 copy-on-last-use → move | `ARCOptimizer` 的 `isLastUse`/`move_value` | 中（需 CFG 活性分析） |
| L3 | retain/release 对消 | ARC pair elimination | 中（与 L2 共用活性分析） |
| L4 | 聚合按引用传递，避免 `_copy` 整个聚合 | — | 中 |

L1 已经「让优化器看得见」；L2/L3 是在此基础上把本该 move 的对消掉。

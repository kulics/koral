# 数值域分工与转换语义的落地

> **状态**：已落地（2026-11-11）。范围：计数域 `Int` 化（下标/长度/计数/偏移/区间位置/查找结果/
> 字节数/match group/capacity）、同宽符号互转改受检、折叠字面量形状与种子对齐。
> 未决：无。语义裁定见 [`../design/numeric-families-design.md`](../design/numeric-families-design.md)
> §转换语义 与 [`../design/std-api-design.md`](../design/std-api-design.md) §计数域与宽度域；
> 本文记**实现长什么样、为什么长这样、否决了什么**。

## §1 计数域与宽度域在实现里的分界

签名层的分界由 std 的 API 承载（判据见 std-api-design §计数域与宽度域）。实现层的
配套形态：

- **计数搬运路径零转型**：`x.count()` 的结果以 `Int` 一路流到下标、区间、比较、
  循环计数；迁移把原先的 `UInt(x.count())` / `Int(x.count())` 转型整体删除。
  计数在搬运路径上再出现 `UInt(...)` 转型即为残量，测试与审计都按此判。
- **FFI/内存原语边界受检转换**：`alloc_memory` / `copy_memory` / `move_memory` /
  `compare_memory` / `alloc_bytes` 与一切 `let foreign` 声明保持 `UInt` 宽度形；
  std 对外用 `Int`，在边界处先校验负值（公开入口按「`<Type> <method> negative <param>`」
  panic）再做受检转换。宽度域的转换只出现在这类边界与真正的位模式场景。
- **位模式场景用回绕惯用法**：`UInt(WrappingUInt(x))`（或 `.hash()`，等价取位模式）。
  典型落点：`std` 的 `Hash` 实现（`Int`/`Int64`/`WrappingInt`/`WrappingInt64` 四处）、
  regex 捕获槽位 -1 哨兵的 undo 存取、`next_int` 的 XOR-min 偏移二进制映射、
  `math/integer.koral` 位工具箱的掩码构造与 rotate/swap 往返、gcd/lcm 的 `|MIN|` 幅值。
  这些代码在旧规则下靠同宽重解释静默工作；新规则下裸 `UInt(负值)` 运行期 panic，
  所以它们全部显式走了回绕腿，**语义逐位不变**（哈希值跨迁移稳定）。

## §2 转换语义的实现形状

规则（值域相同免检、其余按目标家族）实现在双编译器的转换守卫里：

- **符号守卫按符号差发，往返守卫按宽度差发，各自独立**。旧实现把符号守卫写在
  `if (sizeof(S) != sizeof(T))` 块内，同宽符号互转落进恒假分支 = 裸 C 位重解释。
  现在符号守卫在块外——同宽 `UInt ↔ Int` 受检——往返守卫仍借 `sizeof` 让同宽对
  的死代码被 C 编译器折掉（平台无关性不丢）。
- **浮点转整数先截断后受检**：边界用半开双精度常量表达「截断值落在 [MIN, MAX]」。
  64 位上 `(double)INT64_MAX` 会向上取整到 2^63，旧的 `<= (double)MAX` 会把 `2^63`
  放进未定义行为；现在是 `>= -2^63 && < 2^63`（无符号 `> -1 && < 2^64`）。
  NaN/±inf 落在同一 panic。
- **`Type(literal)` 折叠成裸字面量**（与种子 `tryOptimizeLiteralCast` 同形）：
  折叠结果不包 `CastExpr`，保留字面量的收窄能力。两点边界：
  1. 折叠字面量**只在自己的转换处按目标宽度受检一次**；外层转换把它当**值**，
     不按外层宽度复查拼写（`WrappingUInt(WrappingInt(-5))` 回绕，不报错；
     `WrappingUInt(-5)` 作为字面量笔误照旧拒绝——这是种子的既有形状）。
  2. int 字面量→浮点目标折叠成 float 字面量；float 字面量→整数目标**不折叠**，
     走运行期受检转换（`Int(1e30)` 必须 panic，折叠会绕开检查）。

## §3 编译器侧的下标/位置 ABI

- **集合下标索引类型由 std 的 `__index_get`/`__index_slot` 签名驱动**（现为 `Int`）；
  指针、String、定长数组在两编译器里硬编码期望型，已同步改 `Int`。
  指针下标与 `ptr + offset` 偏移闸接受 `Int` 与整数字面量——负偏移是裸 C 寻址；
  `UInt` 偏移拒绝（与下标 ABI 一致）。字面量在下标位置推断 `Int` 由期望型传导而成，
  无独立推断规则。
- **下标 ABI 的检查形状是 coerce-then-exact**（与种子的 `coerceLiteral` 同序）：
  字面量操作数（含折叠 `Type(literal)`）先重贴参数型再要求相等，非字面量的
  不匹配照旧报错——`xs[UInt(0)]` 两侧一致接受，`xs[u]`（`u: UInt` 变量）两侧
  一致拒绝。精确相等检查单独存在时（指针下标值径/写径）同样先 coerce。
- **插值 lowering 的合成量全是 `Int`**：`"\(x)"` 展开的 total/offset/partLen 曾硬编码
  `uint_type`，与 `Bytes.wrap(len: Int)` 冲突时会让一切带插值的程序构建失败——
  两编译器的插值块已整链改 `Int`。
- **列表模式的索引常量与 `count` 结果型**跟随 std 签名（`Type.IntType()`）；
  **数组长度载体**（`TypeNode.FixedArray` / `Type.FixedArrayType` / 种子 `fixedArray`）
  是计数域，取 `Int`/`Int64`，解析守卫对称改到 `Int.max / 10`（两侧接受域一致）。
- 缺省索引字面量（`a[]` 形）与写路径期望型同批改 `Int`。

## §4 被否方案

1. **同宽符号互转免检、按位重解释**——被 [`numeric-families-design.md`](../design/numeric-families-design.md)
   替代方案 7 否决；此处不重复。回绕家族的同宽符号互转保留回绕（有回绕答案就回绕）。
2. **计数统一 `UInt` / 统一 `Int`**——被 std-api-design §计数域与宽度域 否决：
   前者把负值检查从类型里删掉并在每个消费点付转型，后者让位模式/宽度域谎报不变量。
3. **`Seeker.seek`/`file_size` 保持 `UInt64` 宽度形**——否决。文件偏移就是「偏移」，
   归计数域；`SeekOrigin` 三元统一 `Int`（原 `Start: UInt64` / `End,Current: Int64` 的
   不对称是历史形态），`byte_buffer` 的溢出安全 seek 以无幅值比较重写，
   「极端偏移只 Error 不 panic」的承诺保持。
4. **BitSet 宇宙 `size` 留 `UInt`**——否决：它计「多少个」、进计数算术、是
   `new(size)` 的计数实参；成员值留 `UInt`（位位置）。值↔域的交叉在推导线
   （`value >= UInt(size)`）各留一次受检转换，计数搬运路径仍零转型。
5. **`find_from` 越上界保留 panic**——否决（用户裁定）：Option 型访问器是全函数，
   负值与越上界一律归 `None`；下标与修改类 API 越域（含负值）panic；
   容量/分配类负值 panic。三条边界各有用例钉住。

## §5 边界行为

| 形态 | 行为 | 钉子 |
|---|---|---|
| `xs[-1]` / `s[-1]` / `[N]T` 负下标 | 越界 panic | `list_negative_index_panic` 等 |
| `xs.get(-1)` / `find_from(-1, …)` | `None`（全函数） | `list_get_negative_none_test`、`string_find_from_negative_test` |
| `insert_at(-1, …)` 等修改类 | 越界 panic | `list_insert_at_negative_panic` |
| `with_capacity(-1)` 等容量类 | `<Type> <method> negative <param>` panic | `list_with_capacity_negative_panic` |
| `p[i]` / `p + i` 负偏移 | 裸 C 寻址，合法 | 指针下标规则（guide） |
| 同宽符号互转（常规） | 受检，越域 panic | `numeric_conversion_same_width_sign_panic*` |
| 同宽符号互转（回绕） | 回绕（模 2^N） | `numeric_conversion_same_width_checked_test` |
| 浮点→整数截断边界 | 先截断后受检 | `numeric_conversion_float_trunc_bounds_test`、`*_2p63_panic` |
| `slice_spec` 负界/哨兵 | 负界越界 panic；哨兵按 `Int.max_value()` 判别 | 由 `substring`/`slice_spec` 族既有用例覆盖 |

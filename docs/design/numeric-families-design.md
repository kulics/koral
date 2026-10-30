# 数值类型家族与转换语义

> Status: Draft · 2026-10-26 · 无实现记录（尚未施工）
>
> 用户可见的写法与规则见 [`../guide/document.md`](../guide/document.md) §Numeric Casting；
> 本文只讲**为什么是这样**，以及否决了什么。

## 摘要

整数按**算术/转换策略**分成平行家族：常规（`Int`、`UInt8`…）、回绕（`WrappingInt`、`WrappingUInt8`…）、
饱和（`SaturatingInt`…，**预留未实现**）。每个家族十个类型，同宽平行、强制类型隔离。
转换只有一套拼写 `Type(x)`，**策略由目标类型决定**：同宽无损重贴标签，改宽度时常规家族受检、
回绕家族截断；字面量一律编译期受检。浮点不设家族，浮点转整数先向零截断再按目标家族执行范围策略。

本方案**替换**掉 `wrapping_add` / `wrapping_sub` / … 与 `wrapping_cast` 两族方法
（[`design-axioms.md`](design-axioms.md) 公理 7 的出口）。

## 背景

`wrapping_*` 方法族把「这一段走模算术」的意图**摊在每个操作上**：漏写一个前缀就悄悄改了语义，
编译器看不出来。转换侧的 `wrapping_cast` 又引入了第二套转换拼写，与 `Type(x)` 并存——
两套词表表达同一件事的两个策略，读者要先问「这里该用哪个」。

同时，`Type(x)` 的受检规则（[`../guide/document.md`](../guide/document.md) §Numeric Casting）
已经确立「目标类型的取值范围就是契约」。回绕不该是**操作**上的标记，该是**类型**上的标记。

## 非目标

- **不做关联类型 / 类型构造器**：家族是十个并列的内建类型，不是 `Wrapping[T]`
  （[`design-axioms.md`](design-axioms.md) 拒绝清单：高阶类型）。
- **不做函数重载**：`Type(x)` 一族同形，靠目标类型区分策略，不靠重载集选型
  （拒绝清单：函数重载）。
- **不给回绕/饱和家族文本边界操作**（`parse`、格式化规格…）。那些不是整数操作，
  在回绕家族上「解析 `"999..."` 该截断还是报错」没有自然答案，所以留在常规家族。
  数学工具箱（`Numeric`/`Integer`）与二进制工具箱（`BinaryInteger`）**三家族都实现**，见 §操作面。
- **不改浮点算术语义**：浮点溢出仍是 IEEE 的 ±inf，不另设 `WrappingFloat*`。
- **不做 sealed trait**：那是独立的语言能力（封闭 trait），与本设计正交，另行交付。

## 方案

### 三个家族

| 家族 | 类型 | 算术溢出 | 改宽度转换 | 状态 |
|---|---|---|---|---|
| 常规 | `Int` `Int8` `Int16` `Int32` `Int64` `UInt` `UInt8` `UInt16` `UInt32` `UInt64` | panic | 受检 | 已有 |
| 回绕 | `WrappingInt` `WrappingInt8` … `WrappingUInt64` | 模 2^N | 截断 | **本设计** |
| 饱和 | `SaturatingInt` `SaturatingInt8` … `SaturatingUInt64` | 夹到 MIN/MAX | 夹到 MIN/MAX | **预留** |

同一家族内部十个类型同宽平行、强制隔离（`WrappingInt` 与 `Int` 不能直接相加）。
`Wrapping*` 与同名常规类型**同宽同 ABI**——回绕是编译期策略，不是运行时表示。

### 操作面：只做算术

对齐 Rust `Wrapping<T>` 提供的集合：

- 算术 `+ - * / %` 与一元 `-`
- 移位 `<< >>`
- 位运算 `& | ^ !`
- 相等与顺序 `== != < > <= >=`、`Hash`
- 显示、进出转换

**不含**整数工具箱（`count_ones` / `leading_zeros` / `reverse_bits` / `swap_bytes` /
`rotate_left` / `parse` / 格式化规格）。这是刻意切开的：**常规代码尽量用 `Int`**，
回绕家族只是「活在模算术里的那个数」。用户需要工具箱时转到常规家族取用。

**trait 面**取最小可用集：`Eq` `Ord` `Hash` `Clone` `Default` `ToString`。
够放进 `Dict`/`List` 做键、够打印，不为完整性补别的。这是常规家族已有 trait 的子集，
不新增 trait 定义。

**两个抽象，三个家族都实现。** 整数能力分属两个不同的概念，不能混进一个 trait：

| 抽象 | 成员 | 说的是 |
|---|---|---|
| `Numeric` / `Integer` | `abs` `pow` `gcd` `lcm` `ilog2` `ilog10` | **数学整数** |
| `BinaryInteger` | `count_ones` `count_zeros` `leading_*` `trailing_*` `rotate_*` `reverse_bits` `swap_bytes` | **定宽二进制整数** |

依据是别处已有的拆分：Haskell 是 `class Bits a` 与 `class Bits b => FiniteBits b`，
而且它的 `Integer`（无界数学整数）**是 `Bits` 但不是 `FiniteBits`** —— 正因为那不是一个
定宽二进制字。Swift 是 `BinaryInteger`，C++ `<bit>` 是 `unsigned_integer` concept。
三家都把二进制整数当独立抽象，没人把它塞进数学整数。所以 `Integer` **不得**有位操作；
`BinaryInteger` 是独立的公开 trait，常规与回绕（及将来的饱和）三家族都实现。

位运算的**运算符**（`& | ^ ~`、`<< >>`）是内建的、已家族多态，不进 `BinaryInteger`；
`BinaryInteger` 承载的是方法。

**溢出策略只落在会溢出的操作上**：`+ - * / %`、一元 `-`、`abs`、`pow`、`lcm`
随家族变；`BinaryInteger` 与 `gcd`/`ilog2` 这类全函数在三家族上行为完全相同，
函数体可逐字相同。

同一份函数体在不同家族上行为不同，因为 `+ - * / %` 本身是家族多态的：

```koral
given Int8: Integer { pow(self, e: UInt): Self = { …用 self * self… }; };   // 溢出 panic
given WrappingInt8: Integer { pow(self, e: UInt): Self = { …用 self * self… }; }; // 溢出回绕
```

**方法名不携带策略。** 因此 `Integer` 不得有 `wrapping_abs` / `wrapping_pow` 这类
「名字标策略」的成员——那正是本设计要取代的形态（`wrapping_add` 一族的残留）。
溢出策略一律由接收者的家族决定：`Int.MIN.abs()` panic，`WrappingInt.MIN.abs()` 绕回 `MIN`。

**家族的分界线是：有没有回绕答案。有就回绕，没有才 panic。**

| 情形 | 有回绕答案吗 | 处置 |
|---|---|---|
| 算术溢出 | 有（mod 2^N） | 回绕 |
| 移位量越界 | 有（对位宽取模） | 回绕 |
| 移出的位 | —— | 丢弃（两家族一致，是移位本身的定义） |
| 除零 / 取余零 | 没有 | panic |
| `NaN` / ±inf 转整数 | 没有 | panic |
| `MIN / -1` | 有（绕到 `MIN`） | 回绕 |

依据是**对称性**：用户写 `Wrapping*` 就是声明「这里接受回绕」。若算术溢出绕、移位量溢出却炸，
类型就只兑现了一半承诺。掩码之后两种策略仍然都拿得到——要掩码用 `Wrapping*`，要 panic
用普通类型；若反过来让回绕家族也 panic，掩码就只能在每个调用点手写 `x << (n & mask)`，
家族模型就成了只有一个选项。

Rust 同此：`Wrapping<T>` 的 `Shl` 委托给 `wrapping_shl` 做掩码，panic 留给普通 `<<`。

除零是**定义域**错误而非溢出：`x / 0` 不存在回绕答案，所以照旧 panic。`NaN`/±inf 转整数同理。

这样每个新家族是十个小表面，不是十个完整整数类型。

### 转换语义：目标决定策略

只有一套拼写 `Type(x)`。**策略由目标类型决定**，与源类型无关：

| 源 → 目标 | 同宽 | 改宽度 |
|---|---|---|
| 常规 → 常规 | 无损重贴标签（含符号互转的位重解释） | **受检** |
| 常规 → 回绕 | 无损重贴标签 | **截断** |
| 回绕 → 常规 | 无损重贴标签 | **受检** |
| 回绕 → 回绕 | 无损重贴标签 | **截断** |

- **同宽**永远无损重贴标签：不绕也不报错。`Int(WrappingInt(n))` 就是取回 `n`。
- **改宽度 + 常规目标**：受检，装不下 panic（`Panic: numeric conversion overflow`）。
- **改宽度 + 回绕目标**：取目标宽度的低位（按补码截断或符号/零扩展），永不 panic。

规则一句话：

> **字面量一律编译期受检；运行期的值由目标类型决定——常规受检，回绕截断；同宽无损。**

**为什么是外层决定**：目标类型就是意图所在，写 `WrappingUInt8(x)` 就是明说「取低 8 位」。
若由源类型决定，`UInt8(a + b)` 的语义取决于 `a`/`b` 的血统，读者得追表达式来源才能知道规则——
这正是严格类型隔离要消灭的非局部判断。外层决定也让「目标类型的取值范围是契约」这一既有裁定
覆盖全部情形，不需要新增第二条规则。

### 字面量

- **一律编译期受检，按宽度判断，不按家族判断。** `WrappingUInt8(300)` 是错误
  （`Integer literal 300 is out of range for UInt8`），不是 44。
  理由：写死的常量装不下是**作者笔误**，不是数据相关的溢出。
  Rust 同此（`let x: u8 = 300;` 是编译错误）。
- **完整参与整数字面量收窄。** `WrappingInt(n) + 123`、`123 + WrappingInt(n)`、
  `WrappingUInt8(x) == 255` 都成立，字面量向另一侧的整数类型靠拢。
  **这是内建类型相对泛型包装的核心收益**（见替代方案 1）。

### 浮点

浮点**不设家族**。浮点溢出已经得到 IEEE 的 ±inf（即饱和），「回绕」对浮点没有意义。
因此没有 `WrappingFloat*` / `SaturatingFloat*`；将来若要，按公理 7 单独过闸。

转换规则：

| 方向 | 规则 |
|---|---|
| 整数 → 浮点 | 不检查。精度可失（\|n\| > 2^53 时），永不报错 |
| 浮点 → 浮点 | 不检查。收窄可失精度或溢出得 ±inf |
| 浮点 → 整数 | 先**向零截断**得整数值，再按**目标家族**执行范围策略 |

浮点收窄（`Float32(Float64(x))`）**维持不检查**：IEEE 已经定义了行为（丢精度、
溢出得 ±inf），受检会是一条没有需求支撑的新限制，而且 ±inf 对浮点不是错误状态。

浮点 → 整数的两步：

1. **定义域**：`NaN` 与 ±inf 没有可截断的整数值，**一律 panic**，与目标家族无关。
2. **范围**：截断后的整数值按目标家族处理——常规受检（`Int(1e20)` panic）、
   回绕截断（`WrappingUInt8(300.7)` → 44）、饱和夹取（`SaturatingInt(1e20)` → `Int.MAX`）。

### 预留：饱和家族

命名与操作面与回绕家族**平行**：`SaturatingInt` … `SaturatingUInt64`，
同一套操作集，区别只在策略——算术溢出夹到 MIN/MAX，改宽度转换夹到 MIN/MAX。

落地时的语义参照：

- `SaturatingInt(a) + SaturatingInt(b)` 溢出得 `SaturatingInt.MAX` / `.MIN`
- `SaturatingUInt8(big)` → 255，不是 44
- `SaturatingInt(1e20)` → `SaturatingInt.MAX`（这正是 Rust `as` 的浮点转整数行为）

**本设计只预留空间，不实施。** 见风险 1。

## 演进

1. `Type(x)` 的受检规则先落地，确立「目标类型是契约」。
2. `wrapping_cast` 作为方法族的逃生口加入（`Type(x)` 受检后需要 opt-out）。
3. 本设计把回绕从**操作标记**改成**类型家族**，并替换掉步骤 2 与 `wrapping_*` 方法族。

## 替代方案

**1. 泛型包装 `Wrapping[T]`（Rust 的做法）——否决。**

Rust 的 `Wrapping<T>` 只实现同型二元运算（`impl Add for Wrapping<usize>`，无 `impl Add<T> for
Wrapping<T>`），所以 `n + 1` 不成立，每个常量都要写成 `n + Wrapping(1)`。哈希、CRC、FNV 这类
代码常量极多，摩擦是持续性的。字面量也无从推断——泛型实例没有可供收窄靠拢的具体类型。
另外它引入 `.value` / `.0` 第二套取出概念，以及单态化实例键
（`Wrapping[Int]` 与 `Wrapping[UInt]` 是不同实例，需要 `owner_args`）。

内建类型下 `WrappingInt(n) + 123` 直接成立，因为整数字面量收窄规则已经有目标类型可依。
**这不是「和 Rust 不一样」，是对 Rust 实际痛点的修复。**

**2. 方法族 `wrapping_add` / `wrapping_cast`——被本方案取代。**

这正是公理 7 要求的出口。方法族把意图摊在每个操作上，漏写前缀是静默改语义；
两套转换拼写（`Type(x)` 与 `wrapping_cast`）让读者先做词表选择。

**3. sealed trait + `wrapping_cast[T: Integer]`——不再需要。**

原是给 `wrapping_cast[T: Any]` 的空约束补一个封闭 bound。`wrapping_cast` 去掉后，
「哪些类型参与整数位移动」由类型系统本身表达（三个家族都是内建类型），不再需要 trait。
sealed trait 作为通用语言能力另行独立交付。

**4. 转换策略由源类型（内层）决定——否决。**

理由见方案 §转换语义。简言之：会让语义依赖表达式血统，破坏局部可判断；也会让类型隔离
只挡住运算、挡不住转换。

**5. 回绕家族的移位也 panic（只让算术回绕）——否决。**

理由见 §操作面的分界线：那会让类型只兑现一半承诺，且把掩码的负担推到每个调用点。
模拟 x86 的移位计数、可变旋转、数据相关位提取都需要掩码，是有真实用途的形态。

**6. 浮点家族（`WrappingFloat*` / `SaturatingFloat*`）——否决。**

浮点溢出已是 IEEE 的 ±inf。「回绕」对无符号位模式可定义、对浮点不可定义。

## 风险与未决

1. **复杂度预算（最大风险）。** 常规 10 + 回绕 10 + 预留饱和 10 = **30 个整数类型**。
   进项是二十个内建类型；出口是删掉两个方法族（`wrapping_*` 八个 × 十类型、`wrapping_cast`）。
   **饱和家族落地时没有现成出口**——它是纯叠加，届时须自证净赚并单独过
   [`design-axioms.md`](design-axioms.md)「提案过闸」。本文只预留命名与语义空间，不预支预算。

2. **编译器自身在用 `wrapping_*`。** koralc 的哈希路径写了
   `hash.wrapping_mul(31).wrapping_add(...)`。删方法族意味着改写编译器内部到回绕家族，
   触及自举链路。**这是替换的真实成本**，不能只删声明了事。备选是暂时保留方法族作别名，
   但那就违反公理 7 的「有出有进」——倾向一次性改干净。

3. **两编译器的差分一致性。** 转换矩阵 4×2 + 字面量规则 + 浮点两步，全部要在
   koralc 与 compiler-reference 逐字一致。矩阵大，是差分 oracle 的高风险面。

4. **回绕的 C 映射零成本假设。** `Wrapping*` 必须与同名常规类型同宽同 ABI，
   回绕只体现在**代码生成期不发溢出检查**（当前 `+` 会发 `__koral_panic_overflow_add`）。
   若某处给回绕家族发了检查，或给常规家族漏发，策略就错了。

5. **除零、移位越界、`MIN / -1`。** 三处的裁定见 §操作面的「有没有回绕答案」分界线。
   仍是**两端最容易做出不同选择**的地方，尤其是 `MIN / -1`（C 的 `INT64_MIN / -1` 是
   未定义行为，不显式处理就会一边 panic 一边静默）。改动这三处时先看 §操作面。

6. **未决：`Wrapping*` 是否可作泛型实参**（`List[WrappingInt]`）。
   作为内建类型应当可以，但要确认它在实例键、显示、单态化里走常规整数类型的路径。

### 两编译器诊断条数的残留差异

以下差异**无用例覆盖**，是两编译器错误恢复粒度不同造成的。登记在此，不在本设计内修；
前两条要动错误模型的**声明内**粒度，代价与收益不匹配。

| 形状 | 种子 | 主实现 |
|---|---|---|
| 同一声明内两个相同违例（两个调用，或一个块内两条语句） | 1 条 | 2 条 |
| 签名错误后面的函数体错误 | 3 条 | 4 条（多报函数体不匹配） |

跨声明的重复违例已经逐条对齐（种子在声明边界恢复并重置约束缓存）；差异只剩声明内。

### 先前就有的差异（与本设计无关）

- 种子拒绝 `panic(...); return 0;`（「unreachable statement after control flow terminator」），主实现接受。
- 函数体内嵌套的泛型 `let`，解析器报错文本不同（`Expected '=' in let statement` vs `Expected type identifier, got: [`）。
- 名字阶段报错后，主实现仍会追加 import 冲突诊断，种子在该路径不再检查 import 冲突。

## 实施

分三期，每期独立可验：

**一期：类型家族与转换**
- 两个编译器加十个 `Wrapping*` 类型（类型表、显示、代码生成映射、字面量收窄与范围检查）
- 转换矩阵落地（目标决定策略 + 同宽无损）
- 浮点两步规则落地
- **删除 `wrapping_cast`** 及其用例

**二期：操作面与方法族替换**
- `Wrapping*` 的操作面（算术、移位、位运算、顺序、哈希、显示）
- 除零 / `MIN / -1` 语义
- **删除 `wrapping_*` 方法族**，改写 koralc 哈希路径等内部调用点
- 改写 `std` 与 `samples` 的调用点（`sha256sum`、`ip_addr`、`traits` 的哈希）

**三期：文档与看护**
- [`../guide/document.md`](../guide/document.md) §Numeric Casting 改写为家族视角
- 用例覆盖转换矩阵全表、字面量规则、浮点两步、除零、`MIN / -1`
- 差分 oracle 全绿

饱和家族**不在本设计实施范围内**；落地时另行过闸并单独立项。

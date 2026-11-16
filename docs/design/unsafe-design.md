# unsafe 机制 —— 不安全操作与安全责任边界

> **Status**：Accepted · 2026-11-15
> **范围**：`unsafe` 表达式、`let unsafe` 声明标记、不安全操作集、foreign 安全位
> **体裁**：设计文档 —— 记决定与取舍,不记执行过程。
> **取舍判据**（复杂度预算、设计公理）见 [`design-axioms.md`](design-axioms.md)。
> **用户向镜像**：[`../guide/document.md`](../guide/document.md) 与
> [`../guide/document-zh.md`](../guide/document-zh.md)。本文是正本,**改规则三处同批改**。
> 文法正本是 [`../guide/grammar.bnf`](../guide/grammar.bnf)。

## 摘要

> **unsafe 由两件东西构成:一个块表达式,一个声明标记。**
> **危险性由操作承担,不由类型拼写承担**——`*T` 只标载体,读写裸内存的**操作**
> 与调用不安全**契约**才要 `unsafe` 上下文。
> **`unsafe { }` 的词法范围就是 unsafe 上下文**;`let unsafe` 是调用契约,
> 函数体**不**隐含上下文。
> **foreign 逐条显式定安全位**;签名带裸指针 / C 函数指针的无体引用**必须**标 `unsafe`。
> **机制不检查契约,只归属责任**——块内违约照旧是 UB;换来的是危险段落
> 与契约声明从此有形。

## 背景

裸指针操作在 Koral 里一直是「逃生通道」:类型检查放行,契约写在注释里
（`std/string.koral` 的 `from_utf8_ptr_unchecked` 命名、`dealloc_memory` 的前置条件
注释）。危险性的唯一标记是**类型拼写** `*T`——这有三个补不上的缺口:

1. **函数级契约表达不了。**「这个函数不安全,调用方担保前置条件」只能靠命名约定
   （`_unchecked` 后缀）;约定不可执行,对生成器不可见。
2. **无指针签名的危险函数隐形。**一个内部 `dealloc_memory` 托管指针、或调用危险
   C 函数的函数,签名干净,与普通函数外观无异。
3. **危险段落无锚点。**审阅者要在整份实现里嗅探危险操作;「哪些行碰未检查内存」
   没有标记。

### 提案过闸

| 提案 | 拒绝清单 | 替换哪条规则（公理 7） | 读法收益 | 局部可判 |
|---|---|---|---|---|
| `unsafe` 块表达式 + `let unsafe` 标记 | 不命中 | 「危险性由类型拼写承担,不设 unsafe 区块」（[`cffi-design.md`](cffi-design.md) 非目标）→ 「危险性由操作承担,unsafe 上下文把关;类型拼写只标载体」 | 审阅者扫 `unsafe` 边界即知危险段落,契约注释有锚点;调用者看 `let unsafe` 即知契约 | ✓ 需不需要 unsafe 查操作表;在不在上下文看词法嵌套,不扫调用图 |

**一个词一个含义。** `unsafe` 早是保留字（`type unsafe sendable`）。两个位同源:
**「此处安全责任由作者承担,编译器不再把关」**——`type unsafe sendable` 担保
线程安全,`unsafe { }` / `let unsafe` 担保内存安全。不引入第二个概念。

## 方案

### A. `unsafe` 表达式

```koral
let n = unsafe { base[3] };              // 单操作
let sum = unsafe {                        // 多操作,一个边界 = 一处安全推理
    let mutable p = self.data + offset;
    p[0] = p[0] + 1;
    p[0]
};
```

- **形态只有块形**:`unsafe { … }`,块表达式的全部规则照旧(尾表达式求值、
  `;` 收尾、`return` / `break` 穿透)。不提供单表达式糖——`unsafe x + y` 有
  结合歧义,且一个问题只留一种主流表达(公理 6)。
- **unsafe 上下文 = 块的词法范围**,含嵌套块、`when` 臂、**lambda 体**
  (词法继承);**函数边界切断**:定义在上下文外的函数体 / lambda 体不继承。
- **`let unsafe` 函数体不隐含上下文**(R2):体内不安全操作仍要 `unsafe { }`。
  全裸体函数包一个整块即可;`let unsafe` 是**调用契约**,与体内容正交。
- 类型检查后 `unsafe` 表达式**透明消失**(只包块求值)——MIR / codegen 零感知,
  ABI 零变化。

### B. `let unsafe` 声明标记

```koral
// 自由函数 / intrinsic / foreign:紧跟 `let`,限定词之前
public let unsafe first_byte(p: *UInt8): UInt8 = *p;
public let unsafe intrinsic alloc_memory[T: Any](capacity: UInt): *mutable T;
let unsafe foreign strlen(p: *UInt8): UInt;

// 方法(given 成员):可见性之后、名字之前
given Buffer {
    unsafe slot_at(self, i: UInt): *mutable UInt8 = self.data + i;
};

// trait 需求:名字之前(需求不设可见性槽,`unsafe` 是唯一的成员级标记)
trait Blob {
    unsafe raw_bytes(self): *UInt8;
};
given MyBlob: Blob {
    unsafe raw_bytes(self): *UInt8 = self.storage;   // 标记必须与需求一致
};
```

- 标记位:函数声明(`FunctionDecl` / `IntrinsicFunctionDecl` / `ForeignFunctionDecl`)、
  外部全局量(`ForeignLetDecl`)、方法(`GivenMember`)、trait 需求(`TraitMember`)。
- **变量拒绝**:`let unsafe x: T = v` 报错——变量不携带契约。foreign 宏常量
  (有值 + 无 `mutable`)同样拒绝:它是编译期值,不是 C 状态。
- **实现与需求一致**:trait 需求标 `unsafe`,实现方法必须同标;反之亦然。
  不一致是错误(两条文案,见 F)。
- 契约注释(`///` 谁担保什么、前置条件)是**约定**,写入 guide;注解机制不设
  (拒绝清单),编译器不强制。

### C. 不安全操作集

**归类原则:触碰原始内存 + 调用不安全契约。**产生 / 搬运指针值不触内存,不标。

| # | 操作 | 拼写 | 需 unsafe | 依据 |
|---|---|---|---|---|
| A1 | 裸指针解引用 | `*p`(读/写) | ✓ | 未检查内存访问 |
| A2 | 裸指针下标 | `p[i]` 读 / 写 | ✓ | C 下标不查边界(与 `[N]T` 相反) |
| A3 | 经指针成员投影 | `(p).f` 读 / 写 | ✓ | 自动解引用 |
| A4 | 指针算术 | `p + n` / `p - n` | ✓ | 越界指针**形成**即无效(C 模型),边界推理落在算术处 |
| B1 | 调用 `let unsafe` 实体 | 函数 / 方法 / trait 方法(vtable 调用同规则) | ✓ | 契约归调用方 |
| B2 | 调用标记 `unsafe` 的 foreign | `let unsafe foreign` 的调用 | ✓ | 同 B1 |
| B3 | C 函数指针调用 | `(p)(args)` | ✓ 恒 | `foreign (A) -> R` 是裸 C 指针,目标契约无从查证 |
| B4 | 访问标记 `unsafe` 的外部全局量 | `let unsafe foreign` 的读 / 写 | ✓ | 同 B1 |
| C1 | 内存内在族 | `alloc / dealloc / copy / move / compare / init / deinit / take_memory` | ✓ | 声明标 `let unsafe intrinsic`,与 B1 同一机制,无特例 |
| — | 取址 | `&x` / `&mutable x` | ✗ | 产生惰性指针值,不触内存;既有闸(字面量 / 临时 / 锁字段)不动 |
| — | `null`、指针比较、`is null` 模式 | | ✗ | 惰性值 |
| — | 重解释转换 | `as` 指针↔指针、指针↔Int/UInt | ✗ | 危险总在解引用兑现;`&x as *T` 是主流良性路径 |
| — | 有界下标 `[N]T`、托管操作、`alloc_bytes`、`spawn_thread` | | ✗ | 越界 panic / sendable 检查把关 |

### D. 调用契约规则

- **R1 上下文 = 词法嵌套**。`unsafe { }` 体内是 unsafe 上下文,lambda 体词法继承;
  函数边界切断。每个函数体入口把上下文复位(声明序无关)。
- **R2 `let unsafe` 函数体不隐含上下文**。
- **R3 实现与需求一致**(双向,见 B)。
- **R4 值流动自由**:unsafe 操作产出的值(指针、地址整数)是普通值,安全代码
  可持有 / 传递 / 比较——危险在操作,不在值。
- **R5 泛型与派发零影响**:检查对声明的 DefId 标记判,调用点局部即判;
  vtable / 单态化 / codegen 零改动。
- **R6 `let unsafe` 函数不得作值**(v1):出现在值位(非直接调用)报错。
  函数值类型不带安全位——那要改 `(A) -> R` 类型面(演进位)。
- **R7 多余 `unsafe` 不报**(v1,无 warning 基建;演进位)。

### E. foreign 安全位(显式二选一)

| 形态 | 安全位 | 访问 / 调用 |
|---|---|---|
| `let unsafe foreign f(…): R;` | 标记 | 需 unsafe 上下文 |
| `let foreign f(…): R;` | 作者断言安全 | 安全上下文可直接调 |
| `let unsafe foreign f(…): R = { … };`(导出定义) | 标记(Koral 侧调用契约) | 需 unsafe 上下文 |
| `let unsafe foreign [mutable] x: T;`(extern 引用) | 标记 | 访问需 unsafe 上下文 |
| `let foreign [mutable] x: T = v;`(C 变量定义) | 可选标记 | 按标记;不标 = 作者断言安全 |
| `let foreign x: T = v;`(宏常量) | 无标记位(标了报错) | 恒安全(编译期值,无 C 状态) |

- **"体/值的存在性定方向"是同一条铰链**(cffi §B 既有规则):有体/有值 = Koral
  实体,按普通契约走;无体/无值 = C 实体,安全位由作者逐条声明。
- **加固判据(编译器强制)**:无体/无值的 foreign 声明,签名 / 类型含
  `*T` / `*mutable T` / `*Void` / `foreign (A) -> R` 时**必须**标 `unsafe`,
  否则报错。签名纯标量的才允许安全断言(如 `abs`)。判据纯签名形状,局部可判;
  作用是把「懒惰迁移 = 全打安全断言」的失手方向堵死。
- `foreign (A) -> R` 函数指针的调用恒需 unsafe(B3),与指针签名加固同一理由:
  裸 C 指针的使用者担保不了目标契约。类型带安全位是演进位。

### F. 诊断文案(双编译器逐字正本)

解析错误:

```
Expected '{' after 'unsafe'
'unsafe' must be written before 'foreign' / 'intrinsic'
Cannot mark a variable 'unsafe': only function and foreign declarations carry safety contracts.
Cannot mark a foreign constant 'unsafe': a macro constant is a compile-time value, not C state.
Foreign function 'f' must be marked 'unsafe': its signature carries a raw pointer or C function pointer.
Foreign variable 'x' must be marked 'unsafe': its type carries a raw pointer or C function pointer.
```

语义错误:

```
Cannot dereference a raw pointer outside an 'unsafe' block: raw pointer reads and writes are unchecked memory access.
Cannot use unchecked subscript on a raw pointer outside an 'unsafe' block: pointer indexing does not check bounds.
Cannot access a member through a raw pointer outside an 'unsafe' block: the access dereferences the pointer without checks.
Cannot perform pointer arithmetic outside an 'unsafe' block: an out-of-range pointer is invalid even before it is dereferenced.
Cannot call unsafe function 'f' outside an 'unsafe' block: the declaration is marked 'unsafe'.
Cannot call a C function pointer outside an 'unsafe' block: the pointer's target contract is unknown.
Cannot access unsafe global 'x' outside an 'unsafe' block: the declaration is marked 'unsafe'.
Cannot implement unsafe requirement 'm' with a safe method: the implementation must also be marked 'unsafe'.
Cannot implement safe requirement 'm' with an unsafe method: the requirement is not marked 'unsafe'.
Unsafe function 'f' cannot be used as a value: call it directly or wrap it in a safe function.
```

## 非目标

- **`unsafe trait` / `unsafe impl`**——Rust 的旗舰用途是 `unsafe impl Send`;
  Koral 的 `type unsafe sendable` 已是更强的对应物(逐字段规则在案)。演进位。
- **`unsafe (A) -> R` 函数值类型**——v1 禁函数作值(R6);类型面是演进位。
- **warning 体系 / 多余 `unsafe` 诊断**——无基建,登记演进位。
- **UB / 数据竞争检测、契约验证**——机制只归属责任,不验证责任。
- **受检下标降级**——`p[i]` 保持 C 下标语义;`[N]T` 保持越界 panic。
- **任何 codegen / ABI 变化**——纯前端机制。

## 替代方案

- **沿用「类型拼写即危险标记」**——否。三个缺口见「背景」;`_unchecked` 命名约定
  本身就是对函数级标记的需求,机制是把约定形式化。
- **单表达式糖 `unsafe expr`**——否。`unsafe x + y` 结合歧义;公理 6 一种主流表达。
- **`let unsafe` 函数体隐含上下文**(Rust 2015 形)——否。函数内看不出哪行危险;
  「生成器少走错路」要的是逐操作的强制点。全裸体函数包一个整块,ceremony 同形。
- **foreign 无体恒 unsafe(隐式铰链,不设安全断言位)**——否。`abs` 这类无害
  C 函数被迫包装;显式二选一把判断还给绑定作者,与 Rust 2024 `unsafe extern`
  的逐条定安全位收敛到同一形。加固判据堵住失手方向。
- **`as` 重解释进 unsafe 集**——否。惰性指针值,危险总在解引用兑现;
  `&x as *T` 是主流良性路径,标注是纯噪音。指针算术不在此列:C 模型下越界
  指针形成即无效,边界推理要落在算术处。
- **`let unsafe` 函数作值 + 调用点不查**——否。值传出去后调用点无从判断,
  违反公理 9。类型带安全位是正解但动 `(A) -> R` 类型面,留演进位。
- **`unsafe trait` / `unsafe impl` 进 v1**——否。真实需求(`Send` 类断言)已被
  `type unsafe sendable` 覆盖且更细;为假想需求开 trait 新轴是纯叠加。
- **`&` / `&mutable` 取址进 unsafe 集**——否。取址产生惰性值不触内存;
  危险在解引用兑现。既有取址闸(字面量 / 临时 / 锁字段)保持原样。

## 风险与未决

| 风险 | 说明 | 对策 |
|---|---|---|
| 迁移失手方向 | 裸 `let foreign` = 安全断言,懒惰迁移会全打安全 | 加固判据(签名带指针强制 `unsafe`);余下纯标量声明逐条过审 |
| 「安全」声明撒谎 | 包装层 / 安全断言写错契约,编译器拦不住 | 与 Rust 同级;谎言从此有形(声明位与 unsafe 边界可见),契约注释是约定 |
| 仪式感 | 纯指针算法文件行级包裹是净噪音 | 整区一个 `unsafe { }`;一个边界 = 一处安全推理 |
| 迁移 churn 掩护回归 | std/测试机械改写的大 diff | 迁移独立成批;rc 窗口 + benchmark 复跑(纯前端,预期持平) |

**未决(不阻塞)**

1. `unsafe (A) -> R` 函数值类型 —— 需要时给函数值类型加安全位。
2. `unsafe trait` / `unsafe impl` —— 出现 `type unsafe sendable` 覆盖不了的
   不变量型 trait 再议。
3. 多余 `unsafe` 的 warning —— 等 warning 基建。
4. ~~trait 需求位是否再开可见性槽~~ —— **已定(2026-11-16):不设槽。** 需求(与工具块
   成员)的可见性 = trait 的档次(接口件随容器),实现写修饰符必须相等,偏窄偏宽都是
   声明处错误;`unsafe` 仍是唯一成员级标记。正本见
   [`traits-and-givens.md`](traits-and-givens.md)「conformance 成员的可见性随需求」。

## 实施

1. **P1 机制**(已落地 2026-11-15):两编译器(解析 / AST / sema / 诊断)+
   `toolchain/koral-syntax`(CST / 解析 / 打印)+ koralfmt 断言 + `grammar.bnf`
   + 正负钉测试(25 个 `unsafe_*` 用例,含读/写全形态与子树位)。
2. **P2 迁移**(已落地 2026-11-15):std 声明标记(内存内在 8 + `let unsafe
   foreign` 138 + String 裸指针构造 4:`from_utf8_ptr[_unchecked]` /
   `from_cstring[_unchecked]`,调用方担保指针可读)+ 操作点包块(~535 处);
   涉指针测试用例机械包块;guide 中英两份;cffi / concurrency 两处旧规则收敛。
3. **P3 收口**(已落地 2026-11-15):两编译器全量 1447/1447、差分逐字一致、
   koralfmt 语料闸全绿。实施中按 §C 的"读/写"口径补关了初版漏掉的四类洞
   (解引用写位、成员写位、实参子树、算术操作数子树)与裸指针下标的写位成员
   形态;并顺手对齐一处既有分歧(`Type(块)` 实参在 koralc 误把目标类型当
   要求推进块尾)。

落地记录与验收判据按惯例入 [`../implementation/`](../implementation/)。

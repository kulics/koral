# 并发安全：`sendable` 族 · 对象锁 · 跨界检查

> **Status**：Implemented · 2026-11-12 · 对应实现：P1–P6 全部落地（见文内「实施」）——含对象锁重设计（访问点短锁、赋值求值顺序统一「左路径与下标→RHS→写入」、`op=` 两步解糖、旧值解锁后放、锁去可重入）、同步原语定形（全局量初始化 / `AtomicCell` / `Lazy`，见「同步原语的形状」）与 ARC 优化（参数借用、末次使用移动、借用型绑定成对消除）；2026-11-12 增「同步语义五级分层」（L1–L5 与三条推论）并按它重定同步原语形状（`update_and_get` 同名同义、回调锁外 + 最后写入线程判panic、并发容器自含数据结构、锁外析构、`init_owner` 原子化）
> **范围**：跨线程共享的类型约束（`sendable` 族）、对象锁语义、跨界检查、RC 分流、同步语义分层
> **体裁**：设计文档 —— 记决定与取舍，不记执行过程。
> **用法**（用户向）见 [`../guide/document.md`](../guide/document.md) §Concurrency 与 [`../guide/document-zh.md`](../guide/document-zh.md) §并发（中英镜像）；写法细则以 koralfmt 为准。

## 摘要

并发安全是**类型的声明处性质**：`sendable` 族在声明处定死一个类型能否跨线程共享、由谁保证安全——safe 形态编译器验证字段并内置对象锁，unsafe 形态开发者承诺并自管同步；泛型按实参条件成立。跨线程只有四条路，检查全部落在声明处/形成处，**方法的参数类型与返回类型不受任何约束**。承诺边界是**数据竞争自由**，不含逻辑原子性、死锁自由与内存序。

## 背景

现状是 OS 线程 + 裸锁 + 通道 + seq_cst 原子：线程入口收一个无差别的 `() -> Void` 闭包，捕获任意值都放行，线程安全全靠约定（`std/sync/mutex.koral` 的注释契约："Programmers are responsible…"）。设计文档已两次把并发安全点名记成 **Send/Sync 缺口** 并押后（[`stdio-design.md`](stdio-design.md)、[`../implementation/samples-capability.md`](../implementation/samples-capability.md)）——本设计是那个议题的正本。

判据从项目目标（生成器少走错路、审阅者少要看点，见 [`design-axioms.md`](design-axioms.md)）推出，并发安全必须：在声明处一次决定（公理 1）、局部可判断（公理 2）、复杂度不摊到使用点（公理 4）。所有权/借用与 actor 模型在该判据下出局（见「替代方案」）。

**过闸（公理 7）**：本设计替换两条现行规则——「并发安全靠约定」→ 靠类型声明；「全原子 RC 统一制」→ 按 `sendable` 分流。

## 非目标

- **不约束方法的参数类型与返回类型**。跨界检查的落点是声明处/形成处（见「方案·跨界检查」），函数签名系统不动。
- 不引入借用、生命周期、move 语义。内存模型契约（`type` / `type mutable`、`Clone`、`Drop`）不变，正本在 [`type-semantics.md`](type-semantics.md)。
- 不承诺逻辑原子性（跨语句复合操作）、死锁自由、内存序（原子 API 之外）。
- 不做 actor / 隔离模型，不引入消息/await 调用纪律。
- 不改变 C FFI 的过界封闭集合（[`cffi-design.md`](cffi-design.md)）；裸指针的并发归属只是一条「非 `sendable`」规则。
- ~~不设 `[T: sendable]` 约束位~~（**已反转，2026-11-08**：`sendable` 是可组合类型种类约束，与 `mutable`/`foreign` 同槽，见「方案·可组合种类约束」——条件规则继续覆盖容器需求，两者并存不冲突）。

## 方案

### 声明形态（六形态）

类型修饰符槽扩为 `"type" "unsafe"? "sendable"? "mutable"?`（现行 `"type" "mutable"?` 的位置）；`unsafe` 必须伴随 `sendable`，单独 `unsafe` 拒绝。枚举只有 immutable 形态（`mutable` 仅 struct 是既有规则）；别名不写修饰符，跟随被别名类型。

| 声明 | 字段约束 | 对象锁 | RC | 含义 |
|---|---|---|---|---|
| `type` | — | 无 | 原子 | 线程内值 |
| `type mutable` | 仅 `mutable` 字段 | 无 | 原子 | 线程内共享对象 |
| `type sendable` | 全部字段 `sendable` | 无（浅不可变） | 原子 | 冻结数据，可安全共享 |
| `type sendable mutable` | 全部字段 `sendable` | **有** | 原子 | 共享可变，编译器给安全 |
| `type unsafe sendable` | 无 | 无 | 原子 | 开发者承诺可共享 |
| `type unsafe sendable mutable` | 无 | **无** | 原子 | 开发者承诺，同步自管 |

```koral
type sendable Point(x: Int, y: Int);
type sendable mutable Counter(mutable hits: Int);
type unsafe sendable mutable Mutex(private handle: *UInt8);
type sendable Shape { Circle(r: Float64), Rect(w: Float64, h: Float64) };
```

**裁定一：锁是 safe 契约的执行机制，不是 `mutable` 的属性。** 只有 safe `sendable mutable` 带内置对象锁。`unsafe` 的定位是把同步控制权交还开发者（Mutex / Atomic / 无锁 CAS）；且 FFI 内变路径（如 `std/sync/atomic.koral` 把 `&self.value` 交给原子操作）本来就绕过对象锁——强制上锁只收税、不担保。

**裁定二：safe `sendable mutable` 禁止对字段取址。** 取址交给 FFI 就绕开锁承诺；与「逃生舱只对 `foreign` 开放」（[`type-semantics.md`](type-semantics.md)）同向。

### 承诺边界

safe `sendable` 承诺**数据竞争自由**：跨线程共享该类型（及其可达的 safe 状态）不产生内存层数据竞争。明确**不**提供：

- **方法级原子性**——方法体是逐访问同步；**原子性只到「单次访问」粒度（标量原子读写 / 引用与多字长字段短锁），跨访问复合操作不具原子性**（裁定：不做方法级临界区、不提供显式锁块，见「替代方案」）。需要跨访问原子时，用 `AtomicCell` / `Mutex` 显式声明；
- 一格以上的快照一致性（`if c.a < c.b` 是两次读、两个临界区）；
- 死锁自由（对象锁嵌套、与 std `Mutex` 混用都可能死锁）；
- 原子 API 之外的内存序承诺。

### 派生规则（封闭清单）

1. **标量族**（`Bool` / `Int`… / `Float64` / `Rune`）：`sendable`。
2. **名义类型**：按声明。safe 形态编译器**验证**字段全部 `sendable`——标注写错是编译错，不是洞。`type mutable` 不标 `sendable` 即非 `sendable`，即便字段全 `sendable`：声明处定，不做推断。
3. **泛型（条件 sendable）**：`X[A, B]` 是 `sendable` ⟺ `X` 声明了 `sendable`（含 `unsafe`）**且**全部实参 `sendable`。**这条对 safe/unsafe 统一执行**——`unsafe` 只免字段/payload 检查，不免实参条件，否则 `Channel[非sendable]` 能把非 sendable 值夹带走私（见「跨界检查」）。注意与 `Mutable` / `Foreign` 的恒等判定不同，本条需要对实参结构递归。
4. **枚举**：`sendable` ⟺ 声明 + 全部 payload 类型 `sendable`（`unsafe` 免检查）。
5. **函数/闭包类型**：`sendable (A) -> R` 是独立形态（前缀位，类型位仅存此形）。**形成处**检查：无捕获的函数值自然满足；lambda 只有全部捕获 `sendable` 才得 `sendable` 函数类型。放宽转换 `sendable (A) -> R` → `(A) -> R` 合法，反向拒绝。捕获判定走**约束查询**（`satisfies_sendable_constraint`）：裸泛型参数不免费——`f[T: Any]` 里 `run_task` 捕获 `T` 被拒，`T: sendable` / `T: P`（`trait sendable`）才过；数组/弱引用等结构同样严格递归，不再穿透自由通行证（2026-11-09 裁定，堵泛型捕获洗白）。
6. **trait object**：共享性**跟 trait 声明走**（2026-11-08 重设计）——`trait sendable Foo` 的对象恒 `sendable`，其余 trait 的对象不跨界。类型位的 `sendable Trait` 限定**已删除**（见「替代方案」）。
7. **`?T` 弱句柄**：`sendable` ⟺ `T` 是 `sendable`。升级走强计数 CAS，原子 RC 下跨线程升级安全。
8. **裸指针** `*T` / `*mutable T`、`foreign (A) -> R` 函数指针：**非 `sendable`**。跨 FFI 的共享内存由 `unsafe` 形态覆盖。
9. **`type foreign`**（可变值语义，按值拷贝）：**不可声明任何 sendable 形态**（2026-11-09 裁定）——布局是 C 的，共享性不可验证，`foreign sendable` / `foreign unsafe sendable` 皆解析错（"foreign type cannot be marked …"）。foreign 复合值与 `foreign (A) -> R` 只活在 `type unsafe sendable` 的**受信内部**（字段检查对 `unsafe` 免检）或线程内状态；safe `sendable` 的字段检查天然拒绝它们（foreign 恒非 sendable）。**`[N]T`** 仍按元素条件成立（`[4]Int32` 可入 safe `sendable`）。
10. 其余复合（元组、可选等）走 3 / 4 的条件规则。

### trait sendability（声明侧，2026-11-08 裁定）

**`trait sendable Foo`**——修饰符跟在关键字后（镜像 `type sendable` 槽位）。三条规则：

1. **对象恒 sendable**：`trait sendable` 的 trait object 按声明即 `sendable`，无需逐点限定、无需装箱检查。
2. **实现必须 sendable**：`given Bar: Foo` 处检查 `Bar` 是 `sendable`（safe 或 unsafe 均可——形态承诺由实现类型自己携带）；不满足 → `Type 'Bar' must be sendable to implement sendable trait 'Foo'`（锚 given 目标类型）。泛型 `given` **必须证明**每个实参 sendable——约束位收口（`given[T: sendable] Box[T]: Foo`），缺位报同族错误并点名补 bound（严格形态的健全性理由见「可组合种类约束」）。
3. **继承显式**：`trait A: B` 且 `B` 是 `sendable` 时 `A` 必须显式声明 `sendable`，否则 `Trait 'A' extends sendable trait 'B' and must be declared sendable`（锚 trait 名）。不推断。

没有 `unsafe sendable trait` 形态——trait 只收"是否 sendable"一个轴。**混合 trait**（部分实现线程内）不声明 `sendable`，跨界出路是泛型参数化（下节）或 `unsafe sendable` 包装。`Error` 即 `trait sendable Error`（单一形态，与 Swift `Error: Sendable` 对齐）：所有错误类型必须 sendable，`Result` 的错误载荷就是普通 `Error`。

### 可组合种类约束（`Bound.Sendable`）

`sendable` 与 `mutable`/`foreign` 同族，是**泛型约束位的类型种类约束**，`and` 组合、与 trait 约束共存：

```koral
let drain[R: Reader and sendable](source: R): Void = ...;   // 混合 trait 的主流出路
type sendable Box[T: mutable and sendable](inner: T);
```

满足判定 = `is_sendable_type`；裸泛型参数**不免费**（`T: Any` 不向 `U: sendable` 转发——`generic_param_is_sendable_bounded` 只认 `sendable` 约束或 `trait sendable` 约束）。这与条件规则并存：约束位管"参数在此处必须可跨"，条件规则管"容器自身何时可跨"。

**泛型参数约束必填（2026-11-09 裁定）**：每个泛型参数必须显式带约束，下限 `T: Any`（`Any` 语义上即无约束位）——裸 `[T]` / `given[T]` 是解析错（"expected ':' after generic parameter name" / "Type parameter 'T' requires a constraint"），koralc / Swift 参照 / koralfmt 三侧解析器一致强制。

**泛型 `given` 实现 `trait sendable` 必须证明（2026-11-09 裁定，严格形态）**：约束位收口——`given[T: sendable] Box[T]: Ping`，缺位即错（`Type 'Box[T]' must be sendable to implement sendable trait 'Ping'; give its generic parameters 'sendable' bounds`，锚 given 目标类型）。**装箱检查已随之删除**——声明处是唯一证明点。理由是健全性而不仅是偏好：派生查询对裸泛型参数按 sendable 算（`is_sendable_type`，服务字段检查的"无假设模式"），约束转发又规定"`P: Ping`（`trait sendable`）即 P sendable"——宽松读法让这条蕴含为假，非 sendable 载荷可经泛型中继（`fn relay[P: Ping](p: P)`）或 `sendable` 闭包捕获洗进恒 sendable 的对象，而装箱/捕获检查看到的只是"已通过"的抽象 `P`。严格形态使「X: sendable trait ⟹ X sendable」恒真，两条洗白路径同时关闭；与 Swift 的 `extension Box: Ping where T: Sendable` 同形。

### 跨界检查

**原理**：一个值跨线程只有四条路——(a) 被 spawn 的闭包捕获；(b) 存进共享对象的字段；(c) 存进全局量；(d) 经通道缓冲（通道句柄必须先共享给对端，通道本身条件 `sendable`，值随句柄一起被拦下）。四条路的检查全部落在**声明处/形成处**，所以**方法参数与返回不需要任何约束**——这是本设计能不碰函数签名系统的关键。

| 检查点 | 规则 | 时机 |
|---|---|---|
| spawn / `run_task` / `Task` | 参数类型写成 `sendable () -> Void`（`spawn_thread` intrinsic 签名改造） | 调用处 |
| 闭包 | `sendable` 函数类型只收 `sendable` 捕获（判定走约束查询：裸泛型参数须带 `sendable` 约束才过） | lambda 形成处 |
| 共享对象字段 | 字段类型必须 `sendable`（safe 形态） | 类型声明处 |
| 全局量 / 静态量 | 类型必须 `sendable`；`let mutable` 全局的**绑定槽**与字段同协议（标量槽原子读写、引用/多字长短锁、RHS 锁外、旧值解锁后放） | 声明处 |
| trait object | 共享性由 trait 声明携带（`trait sendable`）；非 sendable trait 的对象不跨界 | `given` 处 |
| 方法参数 / 返回 | **不检查** | — |

std 落点因此干净：`Task` 的字段是 `func: sendable () -> Void`，`Task.new(f)` 的检查自然发生在实参位，`Task` 本身可为 safe 形态；真正需要 `unsafe` 的只剩自带同步的受信基座（`Mutex` / `Thread` / `Atomic*`，裸指针或自带原子操作）。

### 赋值求值顺序（全类型统一）

赋值 `place = expr` 的求值顺序**统一为从左到右**，对所有类型一致：

1. **先求左边路径与下标**：按书写顺序求值基表达式与下标表达式（副作用各一次），
   得到**借出的 lvalue**——**owner 句柄 + 字段号**。owner 句柄在 **RHS 之前**就抓住，
   这对**每一类 place 都成立**，不只锁定相关的：锁相关性只决定读/写**协议**，
   从不决定求值顺序。
2. **再求右边**：RHS 完整求值，**不持任何锁**。
3. **最后写入**：经借出的 lvalue 走写协议；下标槽位**始终在写入时刻重查**
   （RHS 若令容器重分配，写入落新缓冲，绝不落陈旧缓冲）。
4. **写入之后**：先解锁（若有），再释放槽位旧值——析构绝不进锁。

`op= ` 一律解糖成**两步操作**（读 + 算 + 写，整体**不原子**）：lvalue 求值一次，
读协议取旧值，RHS 求值，新值按**运算符重载解析**合成（内建算术或 trait 调用），
再走写协议——泛型处与普通类型的运算符重载实现完全兼容。跨线程原子递增请用
`AtomicCell.update_and_get` 或 `Mutex`，语言不再假装 `+=` 原子。

### 对象锁语义（safe `sendable mutable`）

锁是**访问点短锁**——每次字段访问一把，按字段种类分协议（顺序一致性）：

| 访问 | 种类 | 协议 |
|---|---|---|
| 读 | 非 `mutable` 字段 | 直接读（构造后不变，无同步） |
| 读 | `mutable` 标量字段（单字：整数族/浮点/Bool/裸指针/无载荷枚举） | 原子 load |
| 读 | 引用类型 / 多字长字段 | 短锁内读（复制句柄的 retain 同在锁内） |
| 写 | 标量字段 | 原子 store |
| 写 | 引用类型 / 多字长字段 | 短锁内写；**解锁后**释放旧值 |

1. **RHS 在锁外求值**，锁只包住最后一次读取或写入：`x.f = x.f + 1` 是两次独立
   访问（读 + 写），**不是原子**。跨访问的原子性必须显式声明（`Mutex` / `AtomicCell`）。
2. **锁不需要可重入**：任何时刻至多持一把短锁——路径中间的
   读各取各放，RHS 不持锁，旧值释放在解锁之后。析构里回调宿主对象不会死锁。
3. **锁按对象划**；嵌套路径 `a.b.c` 逐对象取放，不同时持。跨对象锁序由程序员负责，
   死锁不承诺（见「风险与未决」）；方法体不是整段临界区。
4. **全局 `let mutable` 与字段同规则**：标量槽原子读写、引用/多字长短锁、RHS 锁外、
   旧值解锁后放；不可变 `let` 全局直接读。
5. **不提供显式锁块**。

### 同步语义五级分层（L1–L5）

**裁定（2026-11-12）**：全语言的同步点按**五级**分层定死——每级的语义、范围、锁内
允许什么、死锁责任各归其位，任何新同步 API 先入级再落地。这张表是同步语义的正本，
「同步原语的形状」按级引用它。

| 级别 | 语义 | 范围 | 锁内允许什么 | 死锁责任 |
|---|---|---|---|---|
| **L1 编译器短锁** | 访问点短锁：一次字段访问一个原子步骤 | safe `sendable mutable` 对象的字段访问、`let mutable` 全局绑定槽 | **什么都不允许**——无任何用户代码，析构也不允许（旧值一律解锁后放） | **Koral 保证不死锁**：任何时刻至多持一把短锁，锁内无用户代码，锁内不可能再取锁 |
| **L2 std 自同步单步** | 单步线性化：一次操作一个原子步骤 | `AtomicCell` 的 `get`/`set`/`swap`/`compare_exchange`、`Concurrent*` 的单步操作 | **只允许元素类型的 `eq` / `hash`**，且实现必须是纯函数（契约，见手册）；**不允许任意回调与析构**（删除/替换/清空一律锁外析构） | **守契约时 Koral 保证不死锁**；`eq`/`hash` 非纯 = 违约 |
| **L3 无锁回调** | 乐观执行：锁内只取快照、验证、提交；回调在锁外跑 | `AtomicCell.update_and_get`、`ConcurrentDict.update_and_get` | 锁内只有快照/验证/提交三步；**析构在锁外**；回调不持任何锁 | **Koral 保证不因内部回调死锁**；**回调同线程写同一个对象 → panic**（按最后写入线程判定）；正常竞争**无上限重试**，不保证有限次数完成 |
| **L4 一次性初始化** | 状态机认领唯一一次初始化；初始化器无锁运行 | `Lazy.get`、全局量初始化 | 初始化**不持锁**；等待者只等发布 | **同线程自依赖 → panic**（结果确定）；**跨线程环不检测**（可能死锁，见「跨线程环不检测」） |
| **L5 显式原语** | 程序员自己的临界区 | `Mutex` / `SharedMutex` / `Semaphore` / `Channel` / `LatchGate` | **任意**——用户代码、回调、析构都可以 | **程序员负责** |

**三条推论**（从表里直接掉出来，写新代码先对这三条）：

1. **析构是隐式用户代码**（`Drop` 可以回调宿主对象），**不得出现在 L1 / L2 的锁内**。
   「旧值解锁后放」「删除/清空锁外析构」不是优化偏好，是这条推论的执行形式。
2. **回调是否持锁、是否可能多次执行，必须能从名字看出来；同名必须同义。**
   `update_and_get` 在 `AtomicCell` 与 `ConcurrentDict` 上同义：乐观、回调不持锁、
   可能多次执行、按版本号提交——名字承诺的形状不得随类型漂移（此前
   `ConcurrentDict.update_and_get` 的回调在锁内跑、一次性执行，正是同名异义，
   2026-11-12 收敛）。同理 `Lazy.new(f)` 的初始化器：恰好一次、不持锁。
3. **运行时检测面只覆盖「同线程、结果确定」的那一类问题**——同线程初始化环、
   回调写同一个对象。跨线程环、锁序、竞争、逻辑原子性**不做运行时检测**：
   它们落在文档契约或程序员责任里（L4 的跨线程环、L5 全部、L1 的跨对象锁序）。

#### 跨线程环不检测

L4 的两个成员只诊断**同线程**环：全局量的初始化链是线程局部的（`a -> b -> a` 报路径），
`Lazy` 靠 `init_owner`（原子）认出"初始化器里 `get()` 自己"。**跨线程环不检测**：
线程 A 初始化 `a` 时等 `b`、线程 B 初始化 `b` 时等 `a`，两边各自合法，合成环——
运行时只看到"对方还没发布"，无法在单点判定，检测它需要全局等待图（跨 L4 状态的
全局分析），而其结果也不是"结果确定"的一类（见推论 3）。**裁定：跨线程环可能死锁，
不检测，写进文档**（本节与手册）；Lazy 同理（两个 `Lazy` 的初始化器互相 `get()`）。

### 同步原语的形状（全局量 · `AtomicCell` · `Lazy` · `Concurrent*`）

自带同步的工具同形：**状态机/版本号认领初始化或提交，被认领的代码在无锁状态下运行**；
锁内只做 L2 允许的事。

- **全局量（L4）**：每个全局的初始化器**至多运行一次**，由对自己**状态字节**的 CAS 认领
  （0 = 未初始化、1 = 初始化中、2 = 完成）。**没有进程级初始化锁**——初始化一个全局
  从不串行化另一个；初始化器**不持任何锁**运行，因此可以访问别的全局、拿别的锁而无
  锁序死锁。初始化器内部重入自己就是初始化环，按 `global initialization cycle: a -> b -> a`
  panic（链是线程局部的）；输掉认领的线程等发布。**跨线程环不检测**（见上节）。
  全局仍在主函数体之前急切运行：模块内按声明序，跨模块按 `using` 拓扑序。
- **`AtomicCell[T]`（L2 单步 + L3 组合）**：`get` / `set` / `swap` / `compare_exchange`
  是格自身 Mutex 上的 L2 单步线性化。**`compare_exchange` 的 `Eq` 在锁内跑**——按 L2
  属允许范围（元素类型的 `eq`），`Eq` 须为纯函数是**契约，只写在手册**，不做运行时
  检查（2026-11-12 裁定：此前对该点的额外限制撤回）。`update_and_get` 是 L3 无锁回调：
  锁内取快照，updater **不持锁**运行，仅当格未变（版本号）才提交，否则重试——updater
  **可能跑多次**、不得有副作用，读格合法、**写格使每次尝试作废**。验证失败且**最后一次
  写入是 updater 所在线程**（格记最后写入线程）→ panic
  `AtomicCell.update_and_get: the updater wrote the same cell`；正常竞争**无上限重试**
  （旧的 10 万次上限撤除），不保证有限次数完成。旧值一律在解锁之后释放。
- **`Lazy[T]`（L4）**：逐值状态机（0/1/2）认领唯一一次初始化，`init_owner` 是**原子**
  （认领线程 id，2026-11-12 从普通字段改原子：同线程自依赖判定点，跨线程读写不得
  竞争）；初始化器**不持锁**运行（可以调别的 lazy、全局与锁）。同一值的初始化器里
  `get()` 不死锁，而是 panic `Lazy.get: the initializer called get() on the same Lazy`；
  其余线程在条件变量上等值发布。**跨线程环不检测**（见上节）。
- **`ConcurrentDict` / `ConcurrentSet` / `ConcurrentDeque`（L2 单步 + L3 组合）**：
  单步操作是容器自身读写锁上的 L2 线性化，锁内只跑键的 `hash` / `eq`（L2 契约同上）；
  **数据结构自含**——自有开放寻址表 / 环形缓冲，不依赖 `Dict` / `Set` / `Deque`
  与 `hash_lookup`（2026-11-12 裁定：完全解耦，各自的不变量各自维护；冻结快照经
  包内构造入口进 `FrozenDict` / `FrozenSet`，那是类型边界不是数据结构依赖）。
  **删除/替换/清空一律锁外析构**：被挤出的键值先取出、解锁后再放。`update_and_get`
  与 `AtomicCell` **同名同义**：回调锁外跑、可能多次执行、**按条目版本号提交**
  （写别的条目不作废本条目）；验证失败且最后一次写入是回调线程（条目记写者、
  条目失踪时退回容器的最后写入线程）→ panic
  `ConcurrentDict.update_and_get: the updater wrote the same container`；正常竞争
  无上限重试。旧的 busy-owner 重入围栏**整个删除**——回调与析构都不在锁内跑，
  重入不再需要围栏，需要的是 L3 的最后写入线程判定。

### `unsafe` 契约

- **语义**：开发者承诺该类型**及其可达状态**跨线程共享无数据竞争。编译器不做字段推导、不给锁。
- 原子 RC 保住计数器本身（RC 全程原子，见「RC 分流」）；字段竞争在承诺范围内。**撒谎 = UB**（C 后端无兜底）。
- **可认领 vs `foreign` 不可认领**：`foreign` 的谎言在每个使用点炸（布局），所以不让用户认领；`sendable` 的谎言集中在一个声明点、审阅可见、命名带警戒色——与 Rust `unsafe impl Send` 同形，可认领。`unsafe` 只出现在类型修饰符位，**不是** unsafe 块/函数体系，不引入第二个概念。
- **守信审计规则（2026-11-12）**：`unsafe sendable` 的承诺一旦写成「**跨线程共用**」（"wait/kill/cancel from another thread is idiomatic" 一类），实现就**必须自同步**——对普通字段的 check-then-act 是数据竞争，不因声明在 `unsafe` 上而免责。承诺写成「**交接不共用**」（File 的 "TRANSFER, not SHARE" 形态）才允许无锁。首轮全量审计（38 个声明）：30 个自同步守信；4 个违约已修——`Thread`（wait/detach 的 waited/detached 普通标志 → 原子状态认领）、`Timer`/`Ticker`（cancel 与 reset 竞争 ctx 释放的 C 级 UAF → 内部互斥）、`Process`（wait/管道句柄的 check-then-act → 内部互斥）；`Task` 补交接契约行。析构侧：全部 Drop 只在 RC 0 发生、不碰共享静态。

### RC 分流

- **（2026-11-11 收敛）受管对象的 RC 一律原子**。此前按「非 `sendable` 静态类型 → 非原子」分流，前提是"非 sendable 箱子绝不被多线程碰"——被两类惯用形态打破：① `unsafe sendable` 聚合的非 `sendable` 字段（`ConcurrentDict` 的 `map: Dict` 在共享锁下被多线程 retain/release）；② 闭包捕获把非 `sendable` 箱子带到别的线程（析构释放并发于别处使用）。复现：4 读线程 + 共享锁 `get`，约三成概率 use-after-free 或 `self escaped a drop body`。参照编译器全程原子，koralc 对齐。
- 恢复非原子优化的唯一健全形态：判据取「从任何 `sendable` / `unsafe sendable` 聚合字段出发的传递可达闭包**之外**」（裸指针穿透归 `unsafe` 契约）；单看静态类型不再够。留作未决，正确性先于快。
- immortal `-1` 哨兵与 weak 升级语义不变。
- 诚实记账：`_copy` / `_drop` 合计占 self-time 2.7%（[`thin-pointer-design.md`](thin-pointer-design.md)），全原子的预期代价是个位数百分比（见基准复测）。

### Drop 与析构

**析构是隐式用户代码**（五级推论 1）：`Drop` 体可以回调宿主对象，所以它不比显式回调
更安全——**不得出现在 L1 / L2 的锁内**。对象锁的「旧值解锁后放」、并发容器的
「删除/替换/清空锁外析构」都是这条的执行形式；L3 的回调锁外跑同样让析构只在锁外发生。
这条纪律**不依赖平台锁的重入行为**——同线程重入一把非递归锁是 POSIX/Win32 的
未定义行为：Linux glibc（writer-nonrecursive）与 Windows SRWLOCK 会自死锁，而
Darwin 的 `pthread_rwlock` 会放行（实测），所以「析构在锁内」在 macOS 上可能静默
通过、在别的平台上死锁；判定只能落在「析构位置」本身，不能落在「锁会不会拦住」。

sendable 类型的析构在**最后句柄死亡的那个线程**执行，析构体须线程无关；线程亲和资源（文件游标、socket、PRNG）不标 `sendable`，或契约写明析构线程无关。这是「`Drop` 让共享可观察」（[`type-semantics.md`](type-semantics.md)）在并发轴上的延伸。析构期间的 immortal 哨兵与 weak 不复活规则不变；最后句柄已死 ⇒ 析构体内的字段访问无并发，锁无害。

### 推荐模式：线程内私有状态 + sendable 消息

并发的**首选形态**：私有状态留在线程内（可以是**非 `sendable`**，无锁开销），消息（`sendable`）走 Channel——`Channel[Msg]` 的条件规则自然要求 `Msg` 是 `sendable`。这正是 actor 想要的形态，用现有工具表达，且比锁方案高效（无竞争、无锁）。共享可变 + 对象锁是第二形态；自带同步的受信基座（`Mutex` / `Atomic*`）是 `unsafe` 形态。

### std 落点

| 子系统 | 标注 |
|---|---|
| `Option` / `Result` / `Pair` / `Range` / `Duration`、纯标量枚举 | `sendable`（safe）+ 条件规则 |
| 内部裸存储、构造后不变的内部块（`Bytes` 类） | `unsafe sendable`（持析构则 `unsafe sendable mutable`），承诺「构造后不可变」（编译器无法验证行为不可变，逃生舱是诚实形态）。`String` 自值类型重塑后字段可验证（`Bytes`+标量），升 safe `sendable`——不可验证的部分随 `Bytes` 的 unsafe 标下沉（2026-11-09 裁定） |
| `List` / `Dict` / `Set` / `Deque` / `StringBuilder` / 迭代器 | **不标记（线程内工作状态）**——不跨线程（RC 仍原子，见「RC 分流」） |
| `FrozenList` / `FrozenDict` / `FrozenSet`（新增） | `unsafe sendable mutable` + 条件规则：对象形态承载自有缓冲的析构（用户析构仅 `type mutable`，2026-11-09 随值类型禁 Drop 裁定转入）；独立存储、只读快照、构造时拷贝、无写能力；内建**下标只读**（`FrozenList`/`FrozenDict`）、集合字面量可作目标类型；构造=可变侧 `to_frozen_*` + 字面量——**跨线程携带集合数据的唯一形态**（2026-11-08 裁定：可变容器不跨线程，传数据走 Frozen 系） |
| `ConcurrentDict` / `ConcurrentSet` / `ConcurrentDeque`（新增） | `unsafe sendable mutable`（条件于 `K`/`T`；L2 单步 + L3 组合，形态见「同步原语的形状」）——**自含数据结构**（自有开放寻址表 / 环形缓冲，不依赖 `Dict`/`Set`/`Deque`/`hash_lookup`，2026-11-12 裁定），删除/替换/清空锁外析构，`to_frozen_*` 经包内构造入口出快照 |
| `Channel` / `SendChannel` / `RecvChannel` / `ChannelStorage` | `unsafe sendable mutable`（条件于 `T`；环形缓冲 + 自管 Mutex/Condvar，条件规则看住跨界） |
| `Mutex` / `SharedMutex` / `Thread` | `unsafe sendable mutable`（裸指针 handle，受信基座） |
| `Atomic*` | `unsafe sendable mutable`（自带原子操作，FFI 内变路径不走对象锁） |
| `AtomicCell[T]` | `unsafe sendable mutable`（条件于 `T: sendable`；L2 单步 + L3 组合，形态见「同步原语的形状」）——`op=` 两步解糖之后，跨访问原子递增等场景的显式工具；`compare_exchange` 的 `Eq` 在锁内（L2 范围），纯函数契约写在手册 |
| `Lazy[T]` | `unsafe sendable mutable`（条件于 `T`；L4，状态机 + 原子 `init_owner` + 条件变量自管，形态见「同步原语的形状」） |
| `Task` / `run_task` / `spawn_thread` | `sendable () -> Void` 参数位 |

**错误侧裁定（2026-11-08，随 trait 重设计收编）**：`Error` 是 `trait sendable`——错误类型**单一形态**，必须自行声明 `sendable` / `unsafe sendable` 才能实现它（`given` 处检查，与 Swift `Error: Sendable` 对齐）。`Result[T]` 的错误载荷是普通 `Error`（声明已携带共享性），Result 因此是 safe `sendable`。

**std 分类判定框架（2026-11-08，四档）**：新 std 类型按此入档，不按"领域"批量贴标——
**A 纯值数据**（字段是标量/类型参数/可验证的 sendable 字段）→ `sendable`（safe）；**B 契约不可变**（内部裸存储、构造后不变的内部块，`Bytes` 类）→ `unsafe sendable`+不可变承诺（String 自重塑后其值归 A 档）；**C 句柄/自管同步且跨线程交接或共用是惯用形态** → `unsafe sendable mutable`+逐类型一行契约（交接型写明"转移而非共用"，如 `File`；共用型写明内部串行化，如 `Stdout` 单次 write 原子）；**D 工作状态**（构建器/游标/迭代器/解析器/可变树）→ **不标记**。C 档准入判据是"交接出现在惯用程序里"，不是"理论上能传"。

**JsonValue 裁定（2026-11-08）**：JsonValue 改坐 **Frozen 树**（载荷 `FrozenList[JsonValue]` / `FrozenDict[String, JsonValue]`），归 A 档 **safe `sendable`**（自引用递归与 `Node(children: List[Node])` 同款成立）；解析/构建留在 D 档（`JsonParser` + builder，累积可变缓冲、`build()` 冻结）。原地修改 API 移除——JSON 值天然是构造后只读的数据，`Channel[JsonValue]` 由此直接可用。

## 替代方案

以下取舍记录于本轮设计讨论（2026-11-07/08），不是事后补写。

- **所有权 + 借用**——**否**。与两次既有裁定正面冲突（managed-ref 语义整体删除、声明处可变性否掉能力系统，见 [`type-semantics.md`](type-semantics.md)）；借用检查是流敏感分析，错误修复点常不在报错点，对生成器是最难自愈的错误类；与 `type mutable` 共享身份语义根本冲突（Rust 的对应物 `Rc<RefCell>` / `Arc<Mutex>` 本身也不做借用检查）；内存安全已由 RC + weak 覆盖，免 RC 流量的收益上限 1–3%（[`thin-pointer-design.md`](thin-pointer-design.md)）。
- **actor / 隔离模型**——**否**（作为语言模型）。要求第二套调用纪律（消息 / await），调用点要判「会不会跳线程」，破坏局部可推理（公理 9）；共享同步读被迫异步化。它独有的表达力（消息串行 = 方法级逻辑原子性）在 Koral 由「线程内私有状态 + sendable 消息」模式覆盖且更高效；监督树 / 位置透明是库层议题。**裁定：不做 actor 模型，只用 `sendable` + channel。**
- **方法级临界区（monitor）**——**否**。原子性按方法划界更贴「对象锁」直觉，但方法体内 IO 长持锁，且「外部直接字段写」与「方法原子性」的边界会长出第二套规则。**裁定：不做方法级临界区。**
- **显式锁块（`lock obj then { ... }` / `with_lock`）**——**否**。语言不提供第二种临界区拼写（公理 6）；原子性只到「单次访问」，跨访问复合操作需要原子性时用 `AtomicCell` / `Mutex` 显式声明。**裁定：不提供显式锁块。**
- **`type`（immutable）按字段自动推导 `sendable`**——**否**。显式声明与「声明处选定」统一；Swift 的教训是 **推断**是痛苦主源；且布局是实现细节的契约下，推导不得依赖 inline / RC 布局，字段级推导又让审阅者失去「一眼可判」。
- **`unsafe sendable mutable` 也带对象锁**——**否**。`unsafe` 的定位是同步自管；强制锁对 FFI 内变路径无效、对无锁设计只收税。锁因此定位为 safe 契约的执行机制，而非 `mutable` 的属性。
- **条件规则只对 safe 形态执行**——**否**。`unsafe` 若免实参条件，`Channel[非sendable]` 就能夹带走私，通道检查点（跨界检查 (d)）整个失效；条件规则是机械推导，成本与语义都支持对六形态统一。
- **类型位 `sendable Trait` 限定**（装箱处查具体类型）——**否**（2026-11-08 重设计，此前为方案形态）。它是全设计里唯一的"使用点定共享性质"，违反声明处优先；改为 `trait sendable` 声明（`given` 处一次立约、装箱免检）+ `Bound.Sendable` 约束组合承接混合 trait。代价：非 sendable trait 的擦除对象无法直接跨界（出路=泛型参数化或 `unsafe sendable` 包装）。
- **`sendable` 二等（不进类型系统，靠使用点标记传播）**——**否**。存储经过中间变量后性质丢失，不健全；类型级修饰是唯一闭合形态（Swift `@Sendable` 同此结论）。
- **Frozen 系 builder（`FrozenListBuilder` 等）**——**否**（2026-11-08）。可变容器本身就是 builder（线程内累积、边界处 `to_frozen_*`），再设一层是重复 API；构造=转换+集合字面量两条路。

## 风险与未决

| 项 | 说明 | 对策 |
|---|---|---|
| 每访问上锁的性能 | 单线程代码也付；热点路径可能可感 | 先立语义后实测；锁消除 / 单线程构建留作未决 |
| 跨对象锁序 | 嵌套路径逐对象取放、不同时持锁；但一次操作先后访问多个对象，加锁次序仍可能与别的线程相反 | 加锁次序由程序员负责；死锁不承诺，文档警示 |
| safe `sendable mutable` 的逃生舱 | 字段取址会绕开锁承诺 | 已禁止并落地检查（「取址仅限 `foreign`」，覆盖整条取址路径的 owner 链） |

**未决（不阻塞）**

1. **`ChannelStorage` 内部复核**：环形缓冲的字段访问在 `unsafe` 下自管同步，条件规则看住 `T`；实现时复核边界协议。
2. **trait object 运行时侧**：擦除侧本就保守原子；RC 全原子后此项无涉，随「RC 分流」的可达闭包优化一并再议。

## 实施

已全部落地（P1–P6，`compiler/` 与 `compiler-reference/` 双编译器同步）：

1. **语义与检查**（P1）：`sendable` 六形态语法 + `Bound.Sendable` 约束位（`compiler/koralc/ast/nodes.koral` 的 `Bound` 枚举挂点）+ 声明/字段校验 + 泛型条件递归 + 派生闭合 + 跨界检查（spawn 签名、全局量、装箱）；sem / mono 双侧。
2. **锁语义**（P2/P5）：即「对象锁语义」的访问点短锁形态——赋值统一「左路径与下标 → RHS → 写入 → 解锁 → 释放旧值」，`op=` 两步解糖走运算符重载，字段按种类分协议，全局 `let mutable` 同协议；`AtomicCell` / `Lazy` / 全局量按「同步原语的形状」落地；无显式锁块，safe `sendable mutable` 已放行使用。
3. **非原子 RC 分流**（P3）——2026-11-11 因 `unsafe sendable` 聚合可达性不健全收敛回全原子（见「RC 分流」），基准复测随行。
4. **std 迁移 + 用户文档**（P4）：guide「Memory Model」增并发节（中英镜像）。
5. **ARC 优化**（P5/P6，koralc 实现侧、时序不可见，Swift 参照保持语义裁判）：受管参数按 **+0 借用**传入、逃逸点才 retain（逃逸分析按「函数实例, 参数槽」，`self` 即参数 0）；**末次使用移动**按**判 G**放行——从使用点出发的每条执行路径（含回边）在碰到下一次值读前必经一次定义，同语句多读保守拒绝，覆盖多读局部的最后复制读、跨块汇合点、owned 参数与 `self`，循环形状按「定义截断」放行或拒绝，析构时序零变化；析构可观察性污染覆盖**单态化实例的泛型实参**与**枚举载荷**（`for_loop_drop` 时序钉看住）；**借用投影风险面**：+0 借用读（借用实参/借用接收者/借用 PlaceRead）与取址（`Ref`/`Pointer`）会把指向对象内部的裸引用送出去并活得比 +1 长（`bytes.borrow_ptr()` 的指针活过载荷释放），带任何一处的局部整体禁移；**init_memory 的实参算消费性使用**（契约即接管 value 的所有权，发射侧 `consume_moved_source` 对可转移形态真会清 init flag）——值源局部同样整体禁移，否则末次移动会与它抢同一个 +1（2026-11-12 细化）；**借用型绑定成对消除**（Swift retain/release pair elimination 同形）限**非持有源**（借用参数/捕获/链式别名，其 +1 的所有权在函数体之外）：`let b = <非持有源>` 的全部使用都不消费时 b 即别名，绑定不 retain、作用域尾不 release；tracked 局部源的 +1 可能死在作用域尾/循环重定义的写协议里，需源生死点可达性分析，留作后续。用户 `Drop` 类型不移动、闭包捕获不作移动源（多发射闭包与 Swift 同判）。运行时 **RC 计数器**（`__koral_rc_stats_*`，包在 `KORAL_RC_STATS` 里——**发布面剔除**，普通构建零痕迹，钉子站用该宏单独编出）把每种形状的收益钉成精确数字（`rc_counter_pin`：别名 0、移动链 0、多读末移恰 1、释放侧逐一相符），verify.sh 另以 "release surface OK" 反钉保证测试面不漏进发布产物。与 Swift 的差别只在析构时序契约这一处，是有意分歧。
6. **五级分层收敛**（2026-11-12，std 侧）：「同步语义五级分层」落地——`AtomicCell.update_and_get` 去 10 万次上限、格记最后写入线程、回调写同一格改 panic；`compare_exchange` 的锁内 `Eq` 撤回额外限制（L2 范围，纯函数契约只写手册）；`ConcurrentDict.update_and_get` 回调移出锁、按条目版本号提交、busy-owner 围栏整体删除；`Concurrent*` 三容器改**自含数据结构**（`std/sync/concurrent_dict.koral` / `concurrent_set.koral` / `concurrent_deque.koral`），删除/替换/清空锁外析构，冻结快照走 `dict.koral` / `set.koral` 的包内构造入口；`Lazy.init_owner` 改原子；跨线程环不检测写进设计与手册。测试面：回调锁外读回入、同对象写 panic、锁外析构回入、并发 `Lazy` 单次初始化各有钉。

验证：**双编译器同步**（`compiler/` 与 `compiler-reference/`），差分对齐的已知坑（typed span、多错误收集、span 锚点、符号名、literal range 循环变量）在 sema 改动中会全踩一遍；[`../implementation/samples-capability.md`](../implementation/samples-capability.md) 押着的 grep-j 并行样例当验收用例。

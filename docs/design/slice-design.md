# 切片与统一存储块：`[]T` / `[]mutable T`

> **Status**：Accepted · 2026-11-26 · 对应实现（未建，落地时补 `../implementation/`）
> **范围**：统一存储块表示、切片类型、借出与逃逸、修改版本号、BufReader 帧、io 切片化、性能开销账
> **前置**：[`type-semantics.md`](type-semantics.md)（`type`/`type mutable`/`Clone`/`Drop`）、
> [`thin-pointer-design.md`](thin-pointer-design.md)（RcBox 头与协议）、
> [`std-api-design.md`](std-api-design.md)（接收者与消耗契约）；
> **用法**（落地后）见 [`../guide/document.md`](../guide/document.md)。**本文记规则正本与为什么。**

## 摘要

一块**定长内联存储块**统一 List / FrozenList / ByteBuffer / String 的缓冲表示；用户面新增
两个窗口类型 `[]T`（只读）与 `[]mutable T`（可写），**零拷贝只进不出**——可变 owner 零拷贝
以 `borrow_slice` 借出（禁逃逸，块 RC 检查兜底）或 `into_slice` 消费转移（owner 消灭后窗即
属主，可逃逸），写死块 owner 以 `as_slice` 放出可逃逸窗口，出切片一律拷贝。迭代/回调期间的结构修改由 **owner 上的修改版本号**（侦测式）在步边界 panic；
帧走 Go 静默过期。安全地板是结构性的（定长块 + 块界可达性 + 保留形实参），panic 是诊断层。

## 背景

三件事汇到同一个设计点：

1. **两个真实 UAF 族**（2026-11-26 记录在案）：①带回调的容器方法（`map`/`sort_by`/`retain`）
   一边回调一边修改——算法把元素区指针缓存跨闭包调用，回调里 `push` 换块即悬垂；②元素释放
   重入（`clear`/析构里再动容器）——释放半途的容器被重入修改，二次释放或泄漏。
2. **变换拷贝开销**：String 已窗口化（Go 式 `{bytes, off, len}`，fa415386），但 List/ByteBuffer
   的区域操作仍全拷贝（`sublist` 复制、io 用 `span: Range[Int]` 选区后拷贝）。
3. **无借用系统**：Koral 没有生命周期标注，业界"活背衬可逃逸裸窗"被全员压制（C# `Span` 禁存
   字段、Swift "Don't store substrings"、Go #45038 反面事故）；**保留式窗口**（窗口 retain 背衬）
   是唯一被验证的视图安全形（WebKit 结论：保留 owner 比拷字节便宜）。

落点：**定长内联块 + 保留式窗口 + 短命借出 + 侦测式版本号**。不引入借用系统、不引入第二种
区域表达（[`design-axioms.md`](design-axioms.md) 公理 6/7）。

## 非目标

- **借用/生命周期系统**——切片是无借用语言下的必要让步，不发展成引用模型。寿命政策分两档：
  **借出窗短命**（作用域 + 逃逸检查）；`into_slice`/`as_slice` 窗可长持（单线程，`[]mutable T`
  的可变块已无 owner，写死块无竞态）。
- **切片跨线程**——`[]T`/`[]mutable T` 一律非 `sendable`，永不放宽（String 能 sendable 是内容
  契约不可变，切片没有这个契约）。
- **Dict/Set/Deque 的块化**——本次只覆盖 List / FrozenList / ByteBuffer / String；其余容器留观。
- **String 语义变化**——值语义、`type sendable`、16B 窗口表示、2^31-1 内容上限全部不变。
- **小对象内联（SSO 类）**——块形统一优先；见「替代方案」。
- **自动拷贝阈值**（小窗自动解钉）——沿用 clone 阀政策，见「替代方案」。

## 方案

### 统一存储块

所有元素缓冲收敛为一种块（[`thin-pointer-design.md`](thin-pointer-design.md) 的 RcBox
`[Control | payload]` 一次 malloc，协议不变：强弱双计数、隐式 weak +1、free 唯一判定点 =
weak 零穿越、immortal -1 / 析构窗口 -2 哨兵）：

```text
[ Control 8B | len: Int | cap: Int | 元素区… ]
 24B 头；元素区基址 = 块地址 + align_up(24, alignof(T))；步长 sizeof(T)
```

- **len/cap 是平台字宽 Int**——表示迁移不得缩水容量（与今日 List 的 `len: Int, cap: Int`
  同级，无 4G 元素上限）。
- **元素内联**：块地址 + 编译期常量 = 元素区基址，没有第二个可变指针（比今日 `Bytes` 的
  `data` 字段还少一跳）。`alignof(T) ≤ 8` 的类型（句柄、String 值、`UInt8`）零填充。
- **块自描述析构**：块 RC-0 按块内 `len` 跑逐元素释放 glue（T 单态化，dtor 由释放点传入，
  仍是 `__koral_Dtor` 协议——**块头不存 dtor**）。窗口可以比 owner 活得久，析构不问 owner。
- **两种生命形态，同一种头**：写死块（String/FrozenList/CString 的块）`cap == len`，构造期写完
  永不再写；可增长块（List/ByteBuffer）按摊还翻倍。
- **空 owner 不持 null 句柄**：持 **immortal 空块**（strong = weak = -1、len = cap = 0 的静态
  常量，不分配），count 为 0。合成释放走既有负数早退，不会算 `NULL - sizeof(Control)`。
- **增长 = 换块**：新块分配 → 按位搬移元素句柄（不动 RC）→ **旧块 len 归零**（防旧块 RC-0
  把搬走的元素再析构）→ 释放旧块。旧块若被窗口钉住则随窗口存活**不悬垂，但内容不可达**
  （len 已归零，块界 panic）——与 `clear` 的"可读快照"不同：clear 不动旧块 len。归零写
  **对负数哨兵跳过**（immortal 空块的 len 本来就是 0，且常量可能落只读段——写它会在空列表
  首次 push 时 segfault）。

### 切片 `[]T` / `[]mutable T`

两个内建窗口类型，`type` 值语义（拷贝 = 合成 retain 块字段，同 String 的值形 + 内部 ARC）：

```text
[]T / []mutable T = { 块句柄, off: Int, len: Int }   // 24B
```

- **off/len 用 Int**——能寻址整个 Int 容量区间，`s[a..<b]` 的 Int 边界直通，无窄化检查。
- **单向转换**：`[]mutable T` 隐式转 `[]T`（能力收窄）；反向不存在；元素类型不变型。
- **非 `sendable`**（见「非目标」）。
- **无结构修改**：没有 push/remove/clear/resize——结构修改只能走 owner 句柄。元素读写在窗内：
  `s[i]`（越界 panic，返回元素按保留形实参约定）、`s[i] = v`（存新→释旧）。
- **继续切片**：`s[a..<b]` O(1) 折叠到根块（`{块, off+a, b-a}`），越界 panic；`off+a`/`b-a`
  用防溢出形（先判 `0 ≤ a ≤ b ≤ len` 再做减法）。派生窗继承双界（窗界 + 块界）。只有切片有
  区间下标形；owner 类型暂不加（String 有 `substring`、List 有 `sublist`，语义见「来源与转换」）。
  `s[a..<b]` 不是新语法——`a..<b` 是 `Range[Int]` 表达式实参，走既有下标形，只增类型规则；
  五面负担只落在 `[]T`/`[]mutable T` 类型拼写上。全部调用按仓库拼写：闭包是位置 lambda 实参
  （`xs.borrow_slice((s) => ...)`，同 `dret.retain((x) => x % 2 == 0)`），标签实参是
  `label = value`（`f.read(into = s)`）。
- **空窗持 immortal 空块**（同上，strong = weak = -1），无 RC 流量（负数早退），不参与逃逸
  检查记账。空窗指**从空 owner 取出的窗**；`s[a..<a]` 一类**零长派生窗照折叠式持根块**——
  保留根块引用，存出零长窗也会被逃逸检查抓到。
- **无切片字面量**——只能从 owner 类型取得（来源可追溯）。
- **std 方法面**（读侧拼写对齐 List）：`count(self): Int`、`is_empty(self): Bool`、
  `get(self, index: Int): Option[T]`、`first(self): Option[T]`、`last(self): Option[T]`、
  `contains(self, value: T): Bool`、`iterator(self)`（进迭代管道），加 `to_list(self): List[T]`、
  `to_frozen_list(self): FrozenList[T]` 两个拷贝出口；`[]mutable T` 另有元素写（下标）。
  越界策略照 std-api-design 三条：`get` 全函数归 `None`，下标 panic。窗口方法只读写窗内
  区间，不动结构。

### 来源与转换：`as_` / `to_` / `into_` 与借出

命名契约经全库清点核验（对照 [`std-api-design.md`](std-api-design.md) 的 into_/to_/as_ 规则
与撞名扫描）：**`as_` = 零拷贝视图、`to_` = 拷贝、`into_` = 消费转移**——into_ 族 8 个先例
全部清空接收者，`into_frozen_list`（O(1) 移交、self 置空）就是 `into_slice` 的同契约先例；
进 String 走 `String.from_*` 家族（`from_bytes` 先例，checked/unchecked 成对）；`to_*` 的
全局契约是"非消耗派生"（`CString.to_string` 零拷贝是登记在案的既有例外），**切片族内
`to_*` 一律拷贝**。借出拼写 `borrow_slice` 归 `borrow_ptr`/`borrow_mut_ptr` 的非持有访问族。
落地时并入 std-api-design 命名契约。

| 方向 | 形态 | 语义 |
|---|---|---|
| String / FrozenList / CString → `[]T` | `as_slice()` | 零拷贝、**可逃逸**（写死块生而不可变，窗口天然安全） |
| List / ByteBuffer → `[]T` / `[]mutable T` | `borrow_slice((s) => ...)` | 零拷贝**借出**，闭包作用域，**禁逃逸** |
| List / ByteBuffer → `[]mutable T` | `into_slice()` | **消费转移**：掏空先于转移，owner 消灭，窗**可逃逸**（此后结构修改永不可能） |
| `[]T` → `s[a..<b]` | 下标 | 零拷贝折叠 |
| `[]UInt8` → String | `String.from_slice` / `from_slice_unchecked` | 拷贝 + UTF-8 校验（`from_bytes` 家族成对拼写） |
| `[]T` → List / FrozenList | `to_list` / `to_frozen_list` | 拷贝（既有拼写复用，切片不加 `to_bytes`——公理 6） |
| List → FrozenList、ByteBuffer/StringBuilder → String | `into_*` | 消费转移：**掏空先于转移**（owner 字段归零再交块），无需唯一性检查¹ |
| 迭代器/惰性序列 → 切片 | `to_*` | 物化拷贝（唯一形态） |

> ¹ 托管别名（`let saved = xs`）共享**同一对象**而非两份块句柄，且切片不从可变 owner 逃逸，
> 「两 owner 共享一块缓冲」不可能发生——掏空对所有别名一致可见。若将来出现 owner 值拷贝
> 语义或可变块逃逸窗，唯一性检查（RC==1）才回来。

写死块 owner 之间还有零拷贝互转（如 `CString.to_string()` 共享块回 String）——同为写死块，
共享安全，不在上表口径内（表管的是**出切片**与可变 owner）。

**可变块窗口的两条出路**：逃逸禁令的根源是"存在能结构修改的 owner"。因此可变块的零拷贝
窗口只有两种合法形态——**借出**（`borrow_slice`，作用域内活视图，禁逃逸，下述检查兜底）与
**消费转移**（`into_slice`：owner 掏空消灭后，窗即这块内存的唯一属主，固定长度、可长持、
无逃逸限制——这是创建可变切片的常规手段；短命政策只约束借出窗）。

**借出（`borrow_slice`）**：`list.borrow_slice((s) => ...)` 把 `[]mutable T` 窗口借给闭包
（隐式降级覆盖只读用法），返回值透传。闭包结束时两个检查，**按序**：

1. **版本检查**：owner 版本号未变（见下节），不符 panic。**必须先查**——`clear`/`into_*`
   一类放块操作会把块 RC 压到入口值之下，先查逃逸会把"借出期间结构修改"误报成"逃逸"。
2. **逃逸检查**：块的 strong_count == 入口值（**窗口建立后**读到的那份，含窗自己的一份），
   不符 panic。打在**块**上才能抓全——拷贝、`s[a..<b]` 派生窗、存入容器、闭包捕获都 retain 块。

嵌套借出组合成立（各自对入口值检查）。`borrow_ptr` 交出的裸指针不被任何检查看见——维持
现有调用方保活契约（FFI 边界自担）。

### 修改版本号

owner 对象（List/ByteBuffer）带一个只增不减的 `version: Int`，**侦测式**（Java `modCount` 同型）：

- **计数口径 = 结构修改**：增（push/insert）、删（pop/remove_at）、清空（clear）、换块才 bump。
  **元素赋值、排序交换、fill/reverse 不 bump**（Java 同口径：`set` 不算结构修改）。
- **捕获点**：迭代器创建（`for x in xs`）、带回调方法入口、`borrow_slice` 入口。
- **检查点**：for-in 每步、回调方法每次闭包返回后、`borrow_slice` 退出。不符即 panic
  （报文：结构修改发生于迭代/借出期间）。panic 锚点按 panic 锚点规则打在检查点。
- **回调与修改不交错**：自修改型回调操作（`retain`）实现为"先评后改"（谓词全跑完再压缩）；
  `sort` 无回调不需检查；`sort_by` 的交换是元素级不 bump，不自伤。
- **无持有状态**：只有捕获值与比较，没有 set/clear 配对，`break`/`return` 出口无清理义务。

迭代期间元素写合法且安全（保留形实参 + 存新释旧）；换块导致的窗内漂移由块界封住（下节），
最坏是 panic 或陈旧内容，不悬垂。**切片自身的迭代**（`for x in s`）无版本可查（版本住
owner）——由块界/尾部 panic 兜底，结局同上。

### 回调元素实参约定

带回调的方法（`map`/`retain`/`sort_by`/迭代器 `for_each` 等）向闭包传元素按**保留形**：
调用前 +1 进闭包参数槽，闭包退出 -1（就是 `(T) -> U` 的现状约定，**零新增开销**）。闭包体内
元素对象永不因外部释放而悬垂——"回调中修改 panic"因此是可预测性规则而非安全必需。
**借用形（+0）留作未来优化**：启用时必须把"回调期间一切释放性修改"升为预防式禁令才安全，
届时另行过闸。`for x in xs` / `for x in s` 的循环变量同此约定（保留形）。

### 修改纪律与析构重入

- **元素赋值 = 存新→释旧**：槽里先落新值再释放旧值；旧值析构重入同槽赋值时账目平（新旧各
  释一次），不二次释放不泄漏。
- **可达性 = 块 len**（对任意 T 统一的承重条款）：`remove_at` 收缩块 len、换块把旧块 len
  归零（**同时**防旧块 RC-0 析构已搬走的元素），窗口的块界检查使陈旧槽既读不到也释放不到——
  迁移后旧块里的重复句柄、删除后尾部的陈旧句柄（含 `[]mutable String` 内联值形）全部不可达。
  **槽位置空降级为卫生措施**（调试构建/裸指针防御用，发布构建可省）：它对 POD 无意义
  （0 是合法字节）、对退化值要求释放 glue null 容忍，不能作为地板条款。
- **空块哨兵（定案）**：空 owner/空窗**不持 null 句柄**（`__koral_release(NULL)` 会算出
  `NULL - sizeof(Control)` 的控制地址 = UB），统一持 **immortal 空块**（strong = weak = -1、
  len = cap = 0 的静态常量，与字面量 immortal 同族）——合成释放走既有负数早退，不引入
  release 的 NULL 早退。配套承重条款：**增长/放块路径对负数哨兵跳过 len 写**（常量可能落
  只读段；哨兵块 len 本来就是 0，跳写零损失）。
- **clear = 放块**：owner 换成 immortal 空块，旧块交 RC-0 统一析构元素（旧块 len 不动，
  窗界照常）；被窗口钉住时元素随窗口存活（快照），重入者见空 owner，天然安全。析构重入
  由此不需要任何守卫。
- **析构窗口**：块 RC-0 的元素释放在析构哨兵（-2）保护下进行，弱升级失败，`drop` 不复活。

### BufReader 帧

`read_frame(): []UInt8` 交出内部缓冲的零拷贝窗口（帧 retain 块），**Go 语义**：帧在下一次读取
前有效。过期后按失效方式分两种结局，**皆非 UB**：原地覆写/未搬动 = 读到**陈旧字节**（Go 同款，
逻辑错误）；压缩收缩或换块 = 块界越界 **panic**（比 Go 强，免费——块界是地板条款，不为帧
另设世代号，省掉 Frame 类型与块字段两处结构）。读取填充在块内容量内自由进行；换块后帧钉
旧块（不悬垂）。帧是唯一"读取继续、窗口作废"的特例，只读、不进版本号视野。契约内的用法
（下次读取前消费完帧）与 Go 完全一致；panic 只出现在**违反契约**的程序里（Go 那里是静默
读垃圾）。

### io 迁移

Reader/Writer 签名换切片，删除 `span: Range[Int] = ...` 参数（`Range.resolve_span` 从 io 面退场）：

```koral
read(self, into: []mutable UInt8 =): Result[Int]
write(self, from: []UInt8 =): Result[Int]
```

覆盖全部 22 个带 `span: Range[Int]` 的 io 签名（trait 2 + impl/扩展 20），逐条清单见下节
「API 变更清单」。**无传参位隐式借出糖**——调用点显式
`list.borrow_slice((s) => file.read(into = s))`。

### API 变更清单

类型名与签名逐字对齐 `std/` 源码；`【span】` = 该参数删除。

**A. 本次迁移——io 面（22 个 span 签名 → 切片）**

| 类型 | 现签名（节选） | 新签名 |
|---|---|---|
| trait `Reader` | `read(self, into: List[UInt8] =, span: Range[Int] = ...): Result[Int]` | `read(self, into: []mutable UInt8 =): Result[Int]` |
| trait `Writer` | `write(self, from: List[UInt8] =, span: Range[Int] = ...): Result[Int]` | `write(self, from: []UInt8 =): Result[Int]` |
| `BufReader[R]` | `read_until(self, delim: UInt8, into: List[UInt8] =, span: Range[Int] = ...): Result[Int]` | `read_until(self, delim: UInt8, into: []mutable UInt8 =): Result[Int]` |
| `BufReader[R]: Reader` | `read(self, into: List[UInt8] =, span: Range[Int] =): Result[Int]` | `read(self, into: []mutable UInt8 =): Result[Int]` |
| `BufWriter[W]: Writer` | `write(self, from: List[UInt8] =, span: Range[Int] =): Result[Int]` | `write(self, from: []UInt8 =): Result[Int]` |
| `ByteBuffer: Reader` / `: Writer` | 同 trait 两形 | 同 trait 两形 |
| `Stdin: Reader`；`Stdout: Writer`；`Stderr: Writer` | 同 trait 两形 | 同 trait 两形 |
| `File: Reader` / `: Writer`（os） | 同 trait 两形 | 同 trait 两形 |
| `TcpSocket: Reader` / `: Writer` | 同 trait 两形 | 同 trait 两形 |
| `UdpSocket` | `send_to[T: ToSocketAddr](self, addr: T, from: List[UInt8] =, span: Range[Int] = ...): Result[Int]`；`recv_from(self, into: List[UInt8] =, span: Range[Int] = ...): Result[Pair[Int, SocketAddr]]`；`send`/`recv` 同两形 | 【span】；`from: []UInt8 =` / `into: []mutable UInt8 =` |
| `StdinPipe: Writer`；`StdoutPipe: Reader`；`StderrPipe: Reader` | 同 trait 两形 | 同 trait 两形 |
| `Writer` 扩展（utils） | `write_all(self, from: List[UInt8] =, span: Range[Int] = ...): Result[Void]` | `write_all(self, from: []UInt8 =): Result[Void]` |

`Range.resolve_span`（std/range.koral:92）从 io 面退役，保留给 Range 语义本身。

**B. 本次新增——切片面**

| 所在 | 新 API（签名形） | 语义 |
|---|---|---|
| 内建 `[]T`/`[]mutable T` | `s[i]`（`__index_get`）、`s[i] = v`（`__index_set`/`__index_slot`，仅 `[]mutable T`）、`s[a..<b]`（Range 形） | 下标 panic；区间 O(1) 折叠 |
| `[]T`/`[]mutable T` | `count(self): Int`、`is_empty(self): Bool`、`get(self, index: Int): Option[T]`、`first(self): Option[T]`、`last(self): Option[T]`、`contains(self, value: T): Bool`、`iterator(self)` | 读侧拼写对齐 List |
| `[]T`/`[]mutable T` | `to_list(self): List[T]`、`to_frozen_list(self): FrozenList[T]` | 拷贝出口 |
| `String` / `FrozenList[T]` / `CString` | `as_slice(self)` → `[]UInt8` / `[]T` / `[]UInt8` | 零拷贝窗 |
| `String`（静态） | `from_slice(bytes: []UInt8): Result[String]`、`unsafe from_slice_unchecked(bytes: []UInt8): String` | 拷贝 + UTF-8 校验（`from_bytes` 家族成对，`unsafe` 标记同先例） |
| `List[T]` | `borrow_slice[U: Any](self, fn: ([]mutable T) -> U): U` | 借出（作用域 + 版本/逃逸双检查） |
| `List[T]` | `into_slice(self): []mutable T` | 消费转移（同 `into_frozen_list` 契约：O(1) 移交、self 置空） |
| `ByteBuffer` | `borrow_slice[U: Any](self, fn: ([]mutable UInt8) -> U): U`、`into_slice(self): []mutable UInt8` | 同上两形 |
| `ByteBuffer` | `count(self): Int` | len 入块后的访问器（内部 `buf.len` 字段调用点迁移） |
| `BufReader[R]` | `read_frame(self): []UInt8` | 帧（Go 语义） |

**C. 命名体检结论**（全库撞名扫描 + std-api-design 契约对照）

- `into_slice` ✅ 严丝合缝（into_ 族先例全部清空接收者；`into_frozen_list` 同契约）。
- `as_slice` ✅ 契约相符（as_ = 非消耗观察）；as_ 过往只用于标量提取，本族首例容器视图。
- `to_list`/`to_frozen_list` ✅ 既有拼写直接复用；切片**不加 `to_bytes`**（`to_list` 已覆盖，公理 6）。
- **`with_slice` 改名 `borrow_slice`**：`with_*` 被构造器族（`with_capacity` ×14）占据，易误读；
  `borrow_*` 有 `borrow_ptr`/`borrow_mut_ptr` 非持有访问族先例。
- **`sub` 弃用**：撞 `Sub` 算术 trait（std/arithmetic.koral:26，全数值族 20+ 实现）；再切片只有
  `s[a..<b]` 下标形。
- 计数方法唯一拼写 `count()`（全库无 `len()`/`size()` 方法）；`get` = Option 全函数、越界
  panic 的下标走私有 `__index_get` 机制；`*_at` 后缀专用于按索引定位的操作。
- 标签方向照旧：读入缓冲 `into`、写出缓冲 `from`；贴标签参数声明尾随 `=`；闭包是位置 lambda。

**D. 后续批次（登记在案，本次不动）**

- `List.push_list(self, other: List[T], span: Range[Int] = ...)`（std/list.koral:139）、
  `List.insert_list_at(self, index: Int, other: List[T], span: Range[Int] = ...)`（:173）、
  `StringBuilder.push_string(self, other: String, span: Range[Int] = ...)`（std/string.koral:251）
  的 span 参数——随后续 API 批次切片化或删除。
- fs 便利函数（`read_file`/`write_file`/`append_file`/`write_text_file`/`append_text_file`/
  `read_text_file`）保持 `List[UInt8]`/String 整缓冲形——函数无重载（公理拒绝清单），换切片形
  伤最常见的整缓冲调用。
- `String.substring`/`List.sublist` 与 private 的 `make_substring`/`make_slice` 语义不变。

**E. 不变面（表示层换块，API 不动）**

- `Bytes`（protected）与 `alloc_bytes` intrinsic：内部表示并入统一块，`Bytes.wrap` 一族照旧。
- `into_string`/`into_string_unchecked`/`into_bytes`（ByteBuffer/StringBuilder）、
  `into_frozen_list`/`into_frozen_set`/`into_frozen_dict`：契约不变（清空接收者/移交存储），
  实现走"掏空先于转移"；Dict/Set/Deque 不块化，其 into_ 一族本次不动。
- `to_string`/`to_bytes`/`to_frozen_list` 一族拷贝语义不变；`CString.to_string` 的零拷贝
  例外维持（登记在案）。
- `borrow_ptr`/`borrow_mut_ptr`：调用方保活契约不变。

### String 的位置

String 表示不变：`type sendable String { 块句柄, off: u32, len: u32 }` = 16B——2^31-1 内容
上限政策（在手册）使 u32 精确覆盖，Token/AST/Json 等热点字段不 +8B。String 的块是写死块，
`as_slice()` 是 u32→Int 加宽直通；`to_string()` 拷贝 + 上限检查。`clone` 仍是唯一解钉阀。

### 安全性论证

**结构性地板（不依赖任何运行时检查）**：

1. 窗口 retain 块——块不因窗口在场而释放；
2. 块定长内联——块活则元素区永不动，窗口没有第二根会悬垂的指针；
3. **双界检查**：窗口访问同时要求 `i < w.len`（窗界）与 `off + i < 块.len`（块界），
   越界 panic。**块 len 是可达性边界**：`remove_at` 收缩块 len、换块把旧块 len 归零——
   陈旧/搬移槽整体不可达，对任意元素类别（句柄/内联值 `[]String`/POD `[]UInt8`）统一成立；
4. 元素赋值存新→释旧；
5. 回调实参保留形。

**诊断层**（panic = abort（`__koral_panic_*` NORETURN），无展开——守卫无复位问题，逃逸物
panic 后不可达）：版本号（步边界）、逃逸检查（块 RC）、帧静默契约。

对抗核查（全部落地板或诊断层，无 UB 路径）：

| # | 攻击面 | 拦截 | 结局 |
|---|---|---|---|
| 1 | 回调里 `xs.push` 换块 | 版本号（回调返回即查，先于内部指针再用） | panic |
| 2 | 回调里经别名改（`let saved = xs`） | 版本住 owner，别名同对象 | panic |
| 3 | for-in 体里 `xs.remove_at` | 迭代器步间查版本 | panic |
| 4 | 借出闭包里 `xs.push` 后继续用窗 | 窗钉旧块 + 块界 + 退出版本检查 | 不悬垂，panic |
| 5 | 迁移/删除后窗口读写漂移槽（含 `[]mutable String` 重复句柄、`[]UInt8` 零字节形） | 块界：remove 收缩 len、迁移 len 归零 → 越界 panic；释放路径同样够不到陈旧槽 | 非 UB |
| 6 | 切片迭代（`for x in s`）期间 owner 结构修改 | 无版本可查；块界/尾部 panic 或陈旧 | 非 UB |
| 7 | 借出窗口逃逸（存窗/派生子窗/捕获） | 退出块 RC == 入口值（派生窗 retain 块，抓全）；版本先查防误报 | panic |
| 8 | `clear` 的元素析构重入 clear/push | clear=放块，重入见空 owner | 安全 |
| 9 | 元素赋值旧值析构重入同槽赋值 | 存新→释旧 | 安全 |
| 10 | 排序比较器里改元素/结构 | 元素写安全（保留形）；结构改 → 案 1 | 安全 / panic |
| 11 | 帧过期读取 | 覆写 = 陈旧字节；压缩/换块 = 块界 panic | 非 UB |
| 12 | 帧持有中读取填充换块 | 帧钉旧块 | 不悬垂 |
| 13 | 泛型擦除位 drop 块 | NULL dtor 已知洞（在案）；可选块头 dtor 封 | 泄漏，非 UB |
| 14 | 空 owner/空窗释放 | immortal 空块（-1 哨兵）走负数早退，不用 null 句柄 | 安全 |
| 15 | `into_slice` 后经残留别名改 owner | 掏空先于转移：别名见 immortal 空壳，转移块不受影响 | 安全 |
| 16 | 借出期间调 `into_slice` | 消灭 owner = 结构修改 → 版本先查 panic；转移窗又推高块 RC → 逃逸检查兜底 | panic |

### 性能开销账

**内存账**（对今日表示，64 位）：

| 对象 | 今天 | 新 | 差 |
|---|---|---|---|
| List 对象 | 24B（source/len/cap） | 16B（块句柄+版本） | −8B |
| List 空 | 24B、零分配 | 16B、零分配 | −8B |
| List 非空合计 | 24 + stride·cap（2 分配） | 40 + stride·cap（2 分配） | **+16B** |
| ByteBuffer 合计 | 32 + cap | 48 + cap | **+16B** |
| FrozenList 合计 | 16 + stride·len | 32 + stride·len | **+16B** |
| String 值 / 块 | 16B / 24B 头（Control+data+len） | 16B / 24B 头（Control+len+cap） | 0 |
| 切片值 | — | 24B | 新增 |
| 迭代器 | 16B（源+索引） | 24B（+期望版本） | +8B（栈上） |

- **+16B/非空容器是统一存储块的硬价**：今日 List/ByteBuffer 缓冲是裸 malloc，窗口共享要求
  RC 化（Control 8B）+ len/cap 自描述进块；owner 瘦身抵掉一部分。摊薄：100 元素（cap 128）
  ≈ +1.5%，>1000 元素才 <0.2%。**malloc 尺寸类取整另计 0–16B/容器**（88B 落 96 档一类）。
- **最坏场景 = 海量小列表**：`grow_to` 从 0 起 cap=8，1–8 元素 List[句柄] 实为 88B→104B
  （+18%，取整后常差一档）；10⁶ 个这样的列表 +16～32MB。缓解：尺寸已知的小集合用**定长数组
  `[N]T`**（零块开销）；这是 RC 共享性的价格，不为小对象再开第二种块形。
- 分配次数、增长换块频率、元素步长、String 全部持平；块 RC 操作是原子的（String 跨线程
  要求），按对象生命期计次（建块/换块/放块/借出各一次），不按元素计次，可忽略。

**计算账**（逐机制）：

| 机制 | 新增成本 | 量级 |
|---|---|---|
| 结构修改 | 版本自增（1 次写） | 纯 push 微循环 ~3–10% 上限，实负载 ≲1% |
| for-in 步（owner 上） | 版本比较（1 load+cmp；对象 16B 同缓存行） | 空体循环 ~3–10% 上限，实负载 ≲1% |
| 回调返回（map/sort_by/retain） | 版本比较 | 被闭包调用成本掩盖 |
| `borrow_slice` | 窗口建/销（RC 对）+ 版本捕获/比较 + RC 读 | ~6 次内存操作/借出，可忽略 |
| `borrow_slice` 调用形态 | 闭包环境 + 间接调用（对比今日直调 `span` 形） | 小块热 io 循环注意批量摊薄；换零拷贝与禁逃逸 |
| 逃逸检查 | 1 次 strong_count 读 | 可忽略 |
| 槽位置空（卫生措施） | 发布构建可省（承重已由块界承担） | 0 |
| `s[i]` | 双界 2 次比较 + 1 次定址（vs `xs[i]` 1 检查 + owner 一跳） | 净持平；迭代器/批量形态每步一查 |
| `xs.count()` | owner→块 一跳（今日直读字段） | 热循环把 count 提出循环即消 |
| 元素实参 | 0（保留形 = 现状约定） | 0 |
| `borrow_ptr` | 无 data 字段可少一跳 | 略快 |
| io read/write | 删 `resolve_span` | 略快 |
| 帧读 | 0 拷贝（新能力） | 面向行解析大胜 |

**预算与验收**（实施时用 `benchmarks/` 微基准核对，量具纪律照旧）：

- 纯 `push` / 空体 for-in 微基准 ≤ 1.10×；带真实体的 map/for-in/求和类 ≤ 1.03×；
  `s[i]` 遍历与 `xs[i]` 差距 ≤ 1.03×；string_transform 案例不回归（另有在案预算）。
- 足迹按上表验收；10⁶ 小列表密集场景单独抽查。
- 超预算时的优化位（按 profile 取用）：count 提出循环/切片迭代、借用形回调参数（挂起项）、
  槽位置空全免（卫生措施默认只进调试构建）。

## 与公理的关系

- **公理 6**（一种主流表达）：借出/窗口场景只有一种表达——切片；独立 `ListView`/`Substring`
  类型否决（见「替代方案」）。拷贝性由 `as_`/`to_`/`into_` 命名一种拼写承担。
- **公理 7**（替换而非叠加）：替换两样现行规则——① io 的 `span: Range[Int]` 参数形态整体删除；
  ② 「区域操作一律拷贝」的现状被"借出零拷贝 + 拷贝出口"二分替代。String 的 `Bytes` 专属块
  并入统一存储块。
- **公理 3**（显式优于隐式引用转换）**登记一项例外**：`[]mutable T → []T` 是**单向能力收窄**
  的隐式转换。它不是 managed-ref 式引用转换层级（无反向、无叠加层、不产生新身份），是
  Rust 重借用/C# `Span→ReadOnlySpan` 的同型收窄；显式化会让每个只读调用点多一次噪音换零
  能力。登记为例外，不作为先例外推（今后任何隐式转换仍须逐项过闸）。

## 演进

2026-11-16 切片化分析（String 窗口化可行、List 活视图缺兜底）→ 2026-11-24 变换拷贝深研
（Go 式窗口入表示、clone 解钉）→ 2026-11-26 fa415386 落地 String 窗口化 → 同日九点方案
评估（三 UB 洞：句柄 RC 检查/裸指针缓存/可变零拷贝逃逸）→ 四轮收敛：定长内联块替代
"重导出基址"不变量、版本号替代 flag 锁、零拷贝只进不出（frozen 位删除）、Go 静默帧、
块头 Int（u32 容量缩水否决）→ 2026-11-27 补 `into_slice` 消费转移（可变切片的常规创建
手段）与 API 变更清单。本文即终态。

## 替代方案

| 否决项 | 为什么 |
|---|---|
| 用户面 `StringView`/`ListView` 类型 | 撞公理 6/7 + 悬垂 bug 族 + C# Span 禁存教训（2026-11-16/24 研究）；独立视图类型被 `[]T` 替代 |
| 可逃逸活窗 + 存活期禁改（P2/Go 形） | "存了片切片就再也 push 不了"的永久封锁脚枪；P1（借出 + 拷贝出口）替代 |
| 块内 frozen 位 | 随「零拷贝只进不出」失去职责；写死块生而不可变替代 |
| 帧世代号（Frame 类型 + 块字段） | 两处结构买"过期即 panic"；Go 静默（陈旧字节、永不悬垂）替代，切片短命政策压缩暴露面 |
| 预防式守卫（flag 锁，mutator 入口拦） | 失败模式不对称：set/clear 配对跨 break/return 多出口，漏 reset = 容器永久锁死（灾难性误报）；漏 bump 只是漏报一次。侦测式版本号替代，panic 锚点损失可接受 |
| 自动小窗拷贝阈值 | 2026-11-24 研究否决（split/lines 共享收益优先）；clone 阀替代 |
| 块头 len/cap 用 u32 | 把 List 容量砍到 4G 元素；表示迁移不得缩水能力。Int 替代 |
| String 窗口统一 24B | 每个 String 值 +8B（Token/AST/Json 热点结构膨胀）；2^31-1 政策使 u32 精确，保持 16B |
| 传参位隐式借出糖 | 用户否决——显式 `borrow_slice` 闭包形，借出点可见 |
| 切片放宽 sendable | 用户否决——`[]mutable T` 可别名可变块（竞态），`[]T` 无内容不可变契约；与寿命无关 |
| 切片字面量构造 | 来源必须可追溯（只能从 owner 取） |
| `into_*` 唯一性检查（RC==1） | 「切片不逃逸 + 别名共享对象」使共享缓冲条件不存在；掏空先于转移替代 |
| owner 镜像 len/cap | 双份真相 = 同步 bug 面；count 一跳可接受 |
| 小对象内联（SSO 类块） | 块形统一优先；string-windowing 研究已列为后置优化候选 |
| 块头存 dtor 指针（+8B） | 可封泛型 TypeVar NULL-dtor 泄漏洞；默认不加（与 `__koral_Dtor` 协议一致），留作独立小项 |
| `with_slice` 拼写 | `with_*` 被 `with_capacity` 构造器族占据（×14），易误读成构造器；`borrow_slice` 归 `borrow_ptr` 非持有访问族 |
| `sub` 取子区间拼写 | 撞 `Sub` 算术 trait（全数值族 20+ 实现）；`s[a..<b]` 下标形是唯一切片子区间表达 |

## 风险与未决

- **版本税实测**：纯微循环预算 1.10×，若实测超差，先查比较是否独立一条依赖链，再考虑
  按"唯一可达迭代"短路（当前无此机制，不预置）。
- **小列表足迹**：+16B/非空容器在"海量小列表"负载下可见（+18%@cap 8，取整后可差一档）；
  std 内部该类负载（如语法树邻接）迁移后抽查一次。
- **帧失效的两种结局**（覆写 = 陈旧字节、压缩/换块 = 块界 panic）是文档契约——回归用例
  要把两种都看住，避免实现悄悄收敛成其中一种。
- **实施正确性前提三项**（漏一项即非 UB 级事故）：borrow_slice 的 self 保留跨调用（否则
  闭包放走 owner 后检查读已释放的 version）；空 owner/空窗用 immortal 空块而非 null 句柄
  （否则合成释放算 `NULL - sizeof(Control)`）；双界检查进全部窗口访问路径（漏一条 = H1
  重现）。
- **泛型擦除 NULL-dtor 泄漏**（在案）在统一块下泄的是元素而非块本体；可选块头 dtor 封堵。
- **实现未开始**：双编译器镜像、五面语法、纯度闸扩展（见「实施」）均未动工。

## 实施

- **类型拼写 `[]T` / `[]mutable T` 落五面**：koralc 解析器+AST、compiler-reference 解析器+AST、
  `toolchain/koral-syntax`（koralfmt CST/打印/宽度估计与 doc 生成 destructures）、
  `docs/guide/grammar.bnf`、`tests/compiler-cases/`——漏 koral-syntax 会被语料门拒收。
- **运行时**：新增 strong_count 读取助手（逃逸检查用）；块 alloc intrinsic 统一
  （Control+len+cap 初始化，drop glue 复用现有 `__koral_Dtor` 释放点单态化）；immortal
  空块常量（**strong = weak = -1**、len = cap = 0）供空 owner/空窗持用——放**可写段**，
  且增长/放块路径对负数哨兵**跳过 len 写**（双保险，跳写是承重条款）；不引入 release 的
  NULL 早退。
- **borrow_slice 的 self 保留形**：调用期间持 owner +1（版本/逃逸检查读 owner，闭包里
  放走外部引用不得带走它）——borrowed-self 优化不得覆盖此方法。
- **双界检查进发射路径**：窗口下标/方法访问统一发 `i < w.len && off+i < 块.len`；迭代器
  每步一查（可把两界折叠成一次 min 比较）；批量内在（拷贝/比较）入口一查。
- **下标规则**：`[]` 是内建规则（[`design-axioms.md`](design-axioms.md) 拒绝清单登记），
  增补切片读写与 `s[a..<b]` 区间形（仅切片有区间下标）；同步更新该行登记。
- **纯度/槽装载消去分析**：窗口写必须判不纯（否则借用实参消去配 UAF）——
  `subscript_sibling_grow_guard` 一族四闸覆盖窗口下标。
- **List/ByteBuffer/FrozenList 表示重构**：裸 ptr → 块句柄 + 版本号；`Drop`/增长/清理路径
  按本文化解构与修改纪律改写；双编译器镜像 + 六步验证链照走。
- **panic 文案**：版本/逃逸/越界三类新 panic 按 panic 锚点规则定锚点，另加空槽一类（仅
  调试卫生构建可达，安全代码的空槽在不可达区）；文案两编译器逐字一致。
- **基准**：`benchmarks/` 增 push/for-in/map/slice 遍历/小列表足迹案，按「性能开销账」预算看护。
- **文档同步**：[`design-axioms.md`](design-axioms.md) `[]` 覆盖行、[`std-api-design.md`](std-api-design.md)
  as_/to_/into_ 命名契约、[`../guide/document.md`](../guide/document.md) 用法节（落地时）。

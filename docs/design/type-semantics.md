# type 语义：`type` / `type mutable` / `Clone` / `Drop`

> **Status**：Implemented
> **范围**：语言可见的类型与内存语义契约
> **用法**见 [`../guide/document.md`](../guide/document.md)（「The Core Idea: `type` / `type mutable`」
> 与「Memory Model」）；**本文只记为什么**。
> **对象/头布局**见 [`thin-pointer-design.md`](thin-pointer-design.md)；本文不写布局。

## 摘要

Koral 的名义类型只有两种形态，**在声明处选定**：浅不可变的 `type`，与共享对象 `type mutable`。
别名、可变性、布局都从这一个决定派生出来。

配套的两条是：`Clone` 明定浅拷贝；`Drop` 是编译器保留的析构入口，不是用户可调方法。

## 背景

语言需要回答「一个值能不能改、改了别人看不看得见、谁负责释放」。常见做法有三类：

- 逐字段可变性（每个字段一个 `mut`）
- 能力系统（`&mut` / `&` 之类的引用类别）
- **声明处可变性**——整个类型的性质在声明处定死

Koral 的落点是第三类的骨架 + 逐字段/逐绑定的标记：**类型形态**（`type` / `type mutable`）
在声明处定死身份与共享语义，**字段可变性**在 `type mutable` 里逐字段写 `mutable`，
**绑定可变性**逐绑定写 `let` / `let mutable`（参数用 `mutable`）——成员能不能改跟**类型定义**
走，不跟绑定走。动机之一是**生成友好 / 审阅友好**（项目目标）：类型形态一眼可判「谁能改
什么」，生成器不必为每条引用做局部可变性决定——能力系统把这个决定摊到了每一处使用点。
（三种方案的取舍记录见「替代方案」，原文未记载选它的论证。）

曾存在过一套 **managed reference 语义**（借用类型 `&T`、弱引用类型 `?*T` / `?*mutable T`、
`box()` 装箱），**已整体删除**。注意删掉的是这套**语义**，不是这些字符：`*T` / `*mutable T`
今天是**裸指针**的现行拼写，`&` / `&mutable` 是**取址运算符**（见「方案」）。

## 非目标

- **对象/头布局、指针宽度、借用的表示**——见 [`thin-pointer-design.md`](thin-pointer-design.md)。
- **`type` / `type mutable` 的写法与示例**——见 [`../guide/document.md`](../guide/document.md)。
- **编译性能优化项**不在本文。

## 方案

### 声明处可变性

原文出处：`../implementation/developer-guide.md`「Simplified Reference and ARC Semantics」（已迁出）。

The active model is the simplified, declaration-site mutability design:

- the managed-ref semantics are removed: no borrow type `&T`, no weak types `?*T` / `?*mutable T`, and no `box()`
- raw pointers are spelled `*T` / `*mutable T` (the formatter's spelling, no space after `*`); `&` / `&mutable` are the address-of operators that form them; a pointer spelling carries no `unsafe`
- `unsafe` exists as a keyword in the type-modifier slot only: `type` `"unsafe"?` `"sendable"?` `"mutable"?`, giving six declaration forms (`type`, `type mutable`, `type sendable`, `type sendable mutable`, `type unsafe sendable`, `type unsafe sendable mutable`). `unsafe` must accompany `sendable`; `unsafe` alone is refused. It is not an unsafe block/function system and introduces no second concept (see [`concurrency-design.md`](concurrency-design.md)「`unsafe` 契约」)
- weak references are `?T` (see「弱引用」)
- `type mutable` controls nominal shared-object semantics and is the only home of field mutability: each field is immutable unless its declaration carries `mutable`, and member mutability follows the type definition, not the binding
- non-`type mutable` nominal types must keep all fields immutable; only `type mutable` types may declare `mutable` fields
- `Clone` is explicitly shallow-copy semantics: duplicate the object handle or backing storage, not a recursive deep copy

The compiler may still use ARC and hidden storage for implementation, but those choices are not user-visible semantics. The language contract is about shared identity and field mutability, not whether a value happened to be heap-backed or box-optimized.

```koral
type Vec(x: Int, y: Int);

type mutable Counter(mutable value: Int, id: UInt);

let c = Counter(0, 1);
c.value = 1;    // valid because Counter declares a mutable field

let v = Vec(1, 2);
// v.x = 3;     // invalid: Vec is not type mutable and its fields are immutable
```

**一句话**：身份与共享是**类型形态的性质**（声明处一次定死），字段可变性在 `type mutable`
里**逐字段声明**（`mutable` 标记），绑定可变性逐绑定声明（`let` / `let mutable`、`mutable`
参数）；成员可变性跟**类型定义**走，不跟绑定走。语言里仍然不存在独占引用/借用类别这一层——
用户不用想。

### 内存模型契约

对外承诺与不承诺的部分，正本在
[`../guide/document.md`](../guide/document.md) 的「Memory Model」一节（用户要读）。此处只记取舍：

- `type` **不承诺值语义**。拷贝、传参、存储都可能共享底仓。这个共享**不可观察**——正因为类型
  浅不可变，编译器才可以自由把它优化掉。这条承诺是**无条件**的：用户析构只住 `type mutable`，
  `type` 的清理由合成的逐字段 release 承担，析构计数不可能把构造身份漏出来，也就没有任何
  可观察量跟着句柄数走。见下「`Drop` 让共享可观察——所以析构只住 `type mutable`」。
- `type mutable` 的**身份是语义的一部分**。赋值与传参交出同一个对象的句柄。
- **引用计数是实现细节**。两种形态内部都可能用 ARC 与隐藏存储。

⇒ 用户不得依赖「是不是引用计数」「有没有装箱」。这两件事被明确开除出语言契约。

### `Clone` 是浅拷贝

`clone(self): Self` 复制句柄或底仓一层，**不递归深拷贝**。嵌套的 `type mutable` 元素保持共享。

出处：`std/traits.koral` 的 `Clone` 约定；`../guide/document.md`「`clone()`」一节是用户说明。

### `Drop` 语义

原文出处：`../implementation/developer-guide.md`「Drop Semantics」（已迁出）。

- `Drop` uses `drop(self): Void`.
- `Drop` lives **only on `type mutable`**. A plain `type` is refused with `Only a 'type mutable' can implement Drop` — enums included: there is no `type mutable` form for them, so an enum can never carry a `Drop`. `foreign` is refused separately with `Foreign type cannot implement Drop` (see `validateDropTargetLayout` in `compiler-reference/Sources/KoralCompiler/Sema/TypeCheckerPasses.swift`). A plain `type`'s cleanup is the synthesized per-field release.
- `Drop` is a normal trait requirement with a compiler-reserved finalization context; it is not a user-invoked method.
- A `type mutable` that implements `Drop` is an ARC-backed object at runtime. The destructor runs exactly once, when the last owning handle dies — the handle count is observable, but only on `type mutable`, whose identity is already semantic. During the destructor the object sits in the destroying window (`strong_count = -2`), so a `retain`/`release` pair cannot resurrect it or re-enter the destructor; see `std/koral_runtime.c`.
- `Drop` is separate from weak capability; trait objects are gated by object safety rather than an `Object` marker trait.
- The compiler may perform finalization in an internal managed-lifetime context and still hide the raw address details from user code.
- Do not impose a primitive-field whitelist on `Drop` implementors. Composite-field types are valid; the important restriction is destructor behavior, not field shape.

### 弱引用

weak 能力写作 **`mutable` 约束 + `?T`**，不设 marker trait。
用户 API 只有两步：**`x as ?T` 构造**弱句柄，**`?expr` 升级**回 `Option[T]`。
弱引用不保活。运行时内部名与表示见 [`thin-pointer-design.md`](thin-pointer-design.md)「弱引用」。

**`?T` 是句柄，不透明。** 在升级之前它不携带被引用对象的字段、分支或
载荷，所以**一切试探或利用形状的操作都必须在 `?T` 上拒绝**：成员读写、方法调用、
解构、迭代、分支匹配。把句柄**整体**绑定（`let x = w`、`for x in ws`、传参、
返回、存入集合）是合法的，并且保留 `?T`。

这条裁定的落点是**解析后所有读取类型形状的地方**，不是某一处 if：取址可以剥
（`&x` 得到的 `*T` 是被引用对象的别名），弱句柄不可以（它不是别名，是指向 control block
的独立句柄，见 [`thin-pointer-design.md`](thin-pointer-design.md)「弱引用」）。任何
一处「为方便把 `?T` 剥成 `T`」都会重新打开这个洞。

### `foreign` 是 FFI 边界

`foreign` 是**类型种类约束**，与 `mutable` 同类（写在约束位：`[T: foreign]`），不是 trait，
也不是 marker trait。它标记**表示由 Koral 的布局自由之外决定、可以跨 FFI 的值**。
`borrow_ptr` / `borrow_mut_ptr` 这类把托管值变成裸指针的逃生舱**只对 `foreign` 开放**——
否则就成了「任意类型 → 裸指针」的桥，绕过所有权。

它满足的是一个**封闭集合**，由编译器判定：

- 内置标量：`Bool`、`Int`/`Int8..64`、`UInt`/`UInt8..64`、`Float32`、`Float64`
- 裸指针：`*T`、`*mutable T`（指向的类型也要在集合里；`*Void` / `*mutable Void` 是
  C 的 `void*`，作为特例放行——`Void` 只在 pointee 位不算出界）
- `type foreign` 声明（布局就是 C 的那个，不透明形 `type foreign X {}` 同样在内；
  不透明形没有布局，只以 `*X` 出现——按值的字段、全局量、函数参数/组件一律拒绝）
- `[N]T` 定长数组（元素也要在集合里；C 布局即 `T data[N]`，用单字段包装
  struct 表示——C 标准保证同布局，赋值/传参/返回却是合法 C）
- `foreign (A) -> R` 函数指针（签名组件也要过界；返回位可 `Void`/`Never`，
  参数位不收——C 没有 void 值，`foreign (Void) -> R` 就是零参指针的错误拼写）
- std 的 `Rune`（唯一的名义类型：它成为名义只是为了带方法，表示是固定的 Unicode 标量）

**用户声明不能认领 `foreign`。** 这正是它取代 `Pod` 的理由：`Pod` 是空 marker trait，
用户可以写 `given MyType: Pod {}` 把自己的类型标成 FFI 安全——一个安全洞。
而 Koral `type` 的布局由编译器选，跨边界的裸指针对它没有意义；要跨 FFI 的结构体应当
写 `type foreign`。

`type foreign` 的值语义是**可变值语义**：赋值/传参按值拷贝；就地修改只经
`let mutable`、`mutable` 参数（本地拷贝，不写回）、`*mutable T` 链接，
以及 `type mutable` 对象的 `mutable` 字段（对象语义）。`self` 是值拷贝——
不提供可变 self，要改接收者收 `*mutable T`。字段只收裸 `name: Type`（C 布局
位置、公开、恒可写），字段类型必须在上面的封闭集合里；显式 `Drop` 拒绝
（代码生成对 foreign 值的 drop 是空操作，接受它就是撒谎）。

`[N]T` 与 `type foreign` 同档：可变值语义、同一套写入矩阵；`foreign (A) -> R`
则是裸 C 函数指针——`null` 与 `*T` 同族，`let foreign` 函数与同类型值入住，
lambda/闭包不转换（那是一个带环境的 Koral 值，不是 C 指针）。

### `Drop` 让共享可观察——所以析构只住 `type mutable`

`type` 的内存模型承诺是「共享不可观察」——正因为类型浅不可变，编译器才可以把共享优化掉。
用户析构恰恰会破坏这条：析构在最后一个句柄消失时跑一次，「构造了几次、有几个句柄」因此
可观察——析构体把**构造身份**从析构计数里漏出来，同字段值不再可互换。所以这条承诺是
**无条件**的，办法是釜底抽薪：**用户析构不许住在 `type` 上**（见上「`Drop` 语义」的拒绝
规则），`type` 的清理由合成的逐字段 release 承担——没有任何可观察量跟着句柄数走。
析构只住 `type mutable`：那里的身份本来就是语义的一部分，运行时按 ARC 支撑的对象对待。

这是一条**契约**层的裁定：它约束的是「用户能依赖什么」和「编译器不许优化掉什么」。
（2026-11-08 收口：此前「`type` + `Drop`」的例外层已整体删除。）

### 析构期间对象不可复活

语言规则允许 `drop` 里对 `self` 调方法（`self.m()` 是接收者使用，不是逃逸）。普通方法按值
接收者，也就是会 retain 一次、在方法结束时 release 一次——而此刻强引用计数已经是 0。

**裁定**：析构函数体执行期间，对象进入**不可复活**状态（运行时的 destroying 哨兵
`strong_count = -2`）：

- 这段时间里的 `retain` / `release` 不改变符号（不会复活对象、不会重新进入析构），
  只朝 -2 记账，接收者的那一对正好抵消。析构体结束后计数若不再是 -2——`self` 净逃出
  drop 体被存进别处——运行时直接报错，而不是放那个句柄变成悬垂指针。
- weak 的升级（`?expr`）要求 `strong_count > 0`，所以析构期间的弱引用拿不回对象——这正是
  「`self` 不得逃逸」在运行时那一侧的对应物。

析构函数体结束后计数恢复 0；内存的释放判定点是隐式 weak 的零穿越（weak_count 递减到 0
的那一方 free 整块）。

出处：`std/koral_runtime.c` 的 `__koral_release_slow`。**这不是静态字面量的 immortal
哨兵**（`strong_count = -1`，见 [`thin-pointer-design.md`](thin-pointer-design.md)）——
两个哨兵语义不同、不共享：weak 操作只对 -1 早退（静态块永不释放），**析构期间的 weak
递减必须照常进行**（-2 下 weak 不早退）。-1 说的是「不再由引用计数决定生死」，
-2 说的是「正在析构，不许复活」。

### `Frozen` 系：跨线程集合的落点

这套规则的直接落点是 `FrozenList[T]` / `FrozenDict[K, V]` / `FrozenSet[T]`——跨线程携带
集合数据的载体（可变容器一律不跨线程）。它们声明成 `type unsafe sendable mutable`：
**`mutable` 形态是自有 buffer 及其析构住的地方**（用户析构只住 `type mutable`，即上文
「`Drop` 语义」的规则），「构造后只读」的承诺让快照在实践中只读。过界是**拷贝**：
`to_frozen_list()` / `to_frozen_dict()` / `to_frozen_set()` 批量拷进**独立存储**（不嵌源容器），
源容器照常可用，`to_list()` / `to_dict()` / `to_set()` 再拷回来——没有移动、没有消费。
条件 sendable 规则照旧：`FrozenList[T]` 只在 `T` sendable 时 sendable，所以
`FrozenList[List[Int]]` 不能过界。`FrozenList` / `FrozenDict` 的下标只读（赋值是编译
错误），`FrozenSet` 没有下标。用户面说明见
[`../guide/document.md`](../guide/document.md)「Frozen Collections」。

## 替代方案

**替代方案原文未记载。** 当时的取舍没有留下记录，此处不补写。

已知**没有**被采用的形态（从「已删除的 managed ref 语法」可以反推，但选它的理由无记录）：

- 引用类别系统（`&` / `&mutable` / `box()`）——曾存在，已整体删除。
- 全面的逐字段可变性（每个字段自带 `mut`、任何类型可写）——**没有**被采用；逐字段 `mutable`
  标记只活在 `type mutable` 里，`type` 的字段一律不可变（见上「声明处可变性」）。

## 风险与未决

- **为何是声明处可变性而非 field-level / capability 系统**：只有结论，无取舍记录。
- **为何保留 ARC 而不是纯 move/借用**：无记录。`thin-pointer-design.md` 的风险表提到析构顺序
  可观察、哨兵 refcount（immortal -1 / destroying -2）的原子行为，但那是实施风险，不是
  「选 ARC」的论证。
- **`Clone` 为何浅不深**：`std/traits.koral` 只有定义，无取舍记录。
- **`Drop` 为何不设原始字段白名单**：原文只说「不要加」，没有记录谁想加过、为什么错。
- **weak 为何用 `mutable`+`?T` 而非 marker trait**：只有一行结论，无取舍记录。
- **`Drop` 例外覆盖到哪一层**（2026-10-20 裁定，2026-11-08 收口）：这条例外已经不存在——
  用户析构只住 `type mutable`（见上「`Drop` 语义」的拒绝规则），`type` + `Drop` 的组合
  直接被拒绝，「析构跑几次」在 `type` 上不再有任何可观察面。旧问题「`type` + Drop +
  方法改 OS 状态」随之消解：需要析构或内部可变的句柄型（文件游标、socket 流、锁、PRNG）
  本来就该声明成 `type mutable`。见 [`std-api-design.md`](std-api-design.md)
  「Handle Types and Interior Mutation」。

## 实施

已落地，无单独的实现记录文件——语义契约在 `std/` 与两个编译器里同批实现，验证走
[`../implementation/developer-guide.md`](../implementation/developer-guide.md) 的验证链。

`Drop` 的运行时表示、immortal（-1）/ destroying（-2）哨兵、niche `Option` 等实施细节见
[`thin-pointer-design.md`](thin-pointer-design.md) 的「实施」一节。

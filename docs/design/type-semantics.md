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

Koral 选第三类。managed reference 语法（`*T` / `*mutable T` / `?*T` / `?*mutable T` / `&` /
`&mutable` / `box()`）曾存在过，**已整体删除**。

## 非目标

- **对象/头布局、指针宽度、借用的表示**——见 [`thin-pointer-design.md`](thin-pointer-design.md)。
- **`type` / `type mutable` 的写法与示例**——见 [`../guide/document.md`](../guide/document.md)。
- **编译性能优化项**不在本文。

## 方案

### 声明处可变性

原文出处：`../implementation/developer-guide.md`「Simplified Reference and ARC Semantics」（已迁出）。

The active model is the simplified, declaration-site mutability design:

- managed refs are removed: no `*T`, `*mutable T`, `?*T`, `?*mutable T`, no `&`, no `&mutable`, and no `box()`
- raw pointers remain: `*unsafe T`, `*unsafe mutable T`, `&unsafe`, `&unsafe mutable`
- `type mutable` controls nominal shared-object semantics, not field-by-field mutability for ordinary types
- non-`type mutable` nominal types must keep all fields immutable; only `type mutable` types may declare `mutable` fields
- `Clone` is explicitly shallow-copy semantics: duplicate the object handle or backing storage, not a recursive deep copy

The compiler may still use ARC and hidden storage for implementation, but those choices are not user-visible semantics. The language contract is about shared identity and field mutability, not whether a value happened to be heap-backed or box-optimized.

```koral
type Vec(x Int, y Int);

type mutable Counter(mutable value Int, id UInt);

let c = Counter(0, 1);
c.value = 1;    // valid because Counter declares a mutable field

let v = Vec(1, 2);
// v.x = 3;     // invalid: Vec is not type mutable and its fields are immutable
```

**一句话**：可变性是**类型的性质**，不是字段的性质，也不是引用的性质。
所以语言里不存在「这个字段可变、那个不可变、这个引用是独占的」这一层——用户不写、也不用想。

### 内存模型契约

对外承诺与不承诺的部分，正本在
[`../guide/document.md`](../guide/document.md) 的「Memory Model」一节（用户要读）。此处只记取舍：

- `type` **不承诺值语义**。拷贝、传参、存储都可能共享底仓。这个共享**不可观察**——正因为类型
  浅不可变，编译器才可以自由把它优化掉。
- `type mutable` 的**身份是语义的一部分**。赋值与传参交出同一个对象的句柄。
- **引用计数是实现细节**。两种形态内部都可能用 ARC 与隐藏存储。

⇒ 用户不得依赖「是不是引用计数」「有没有装箱」。这两件事被明确开除出语言契约。

### `Clone` 是浅拷贝

`clone(self) Self` 复制句柄或底仓一层，**不递归深拷贝**。嵌套的 `type mutable` 元素保持共享。

出处：`std/traits.koral` 的 `Clone` 约定；`../guide/document.md`「`clone()`」一节是用户说明。

### `Drop` 语义

原文出处：`../implementation/developer-guide.md`「Drop Semantics」（已迁出）。

- `Drop` uses `drop(self) Void`.
- `Drop` is a normal trait requirement with a compiler-reserved finalization context; it is not a user-invoked method.
- A type that implements `Drop` must behave as an ARC-backed object at runtime, even when the compiler's layout analysis may optimize away some extra layers for a local value.
- `Drop` is separate from weak capability; trait objects are gated by object safety rather than an `Object` marker trait.
- The compiler may perform finalization in an internal managed-lifetime context and still hide the raw address details from user code.
- Do not impose a primitive-field whitelist on `Drop` implementors. Composite-field types are valid; the important restriction is destructor behavior, not field shape.

### 弱引用

weak 能力写作 **`mutable` 约束 + `?T`**，不设 marker trait。
`downgrade(T)` 得 `?T`，`upgrade(?T)` 回 `Option[T]`。弱引用不保活。

### `Pod` 是 FFI 边界

`Pod` 是空的标记 trait，标记**可安全跨 FFI 的值**。`borrow_ptr` / `borrow_mut_ptr` 这类把托管值
变成裸指针的逃生舱**只对 `Pod` 开放**——否则就成了「任意类型 → 裸指针」的桥，绕过所有权。
出处：`std/traits.koral`。

## 替代方案

**替代方案原文未记载。** 当时的取舍没有留下记录，此处不补写。

已知**没有**被采用的形态（从「已删除的 managed ref 语法」可以反推，但选它的理由无记录）：

- 引用类别系统（`&` / `&mutable` / `box()`）——曾存在，已整体删除。
- 逐字段可变性——`type mutable` 明确**不是**这个（见上「声明处可变性」）。

## 风险与未决

- **为何是声明处可变性而非 field-level / capability 系统**：只有结论，无取舍记录。
- **为何保留 ARC 而不是纯 move/借用**：无记录。`thin-pointer-design.md` 的风险表提到析构顺序
  可观察、`-1` refcount 的原子行为，但那是实施风险，不是「选 ARC」的论证。
- **`Clone` 为何浅不深**：`std/traits.koral` 只有定义，无取舍记录。
- **`Drop` 为何不设原始字段白名单**：原文只说「不要加」，没有记录谁想加过、为什么错。
- **weak 为何用 `mutable`+`?T` 而非 marker trait**：只有一行结论，无取舍记录。

## 实施

已落地，无单独的实现记录文件——语义契约在 `std/` 与两个编译器里同批实现，验证走
[`../implementation/developer-guide.md`](../implementation/developer-guide.md) 的验证链。

`Drop` 的运行时表示、`-1` immortal refcount、niche `Option` 等实施细节见
[`thin-pointer-design.md`](thin-pointer-design.md) 的「实施」一节。

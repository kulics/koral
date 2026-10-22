# 薄指针对象表示（Thin Object Pointer）

> **Status**：Implemented · 2026-10
> **范围**：值表示 / 堆布局 / ARC 头 / 引用与借用 / trait object
> **体裁**：设计文档 —— 记决定与取舍，不记执行过程。

## 摘要

托管对象是一个 `[Control | payload]` 块，句柄是**一个字**，存 payload 地址；
control 由 `payload - sizeof(Control)` 反推。ARC 头是 8 B、两个引用计数；
`dtor` 不在头里，在释放调用点单态化。`Option[T]` 在 `T` 是单个可空指针字时用 niche，
不设 tag。

## 背景

托管值一度是 `{ void* ptr; void* control; }` 双字句柄（`shared_ptr` 形状）。三条实测
让这个形状站不住：

1. **`control` 字在系统里没有任何一处是必需的** —— 要么是 `NULL` 死字，要么可由 `ptr` 推出。
2. 唯一能证明双字合理的形态是 `shared_ptr` 的 aliasing 构造（借 payload 内部、记宿主
   control）。**它在 110 MB 生成 C 与 325 个测试用例里出现 0 次**，而且表层语法根本
   产生不了它——托管对象永远整体借、整体持有。
3. **ARC 头占托管堆字节的 49.7%**，占全部堆字节的 28.2%。

## 非目标

- **语言语法**（表层无可见变化）。
- **编译性能优化**。
- **小容器 / 指针打标**（步骤 4c）——见「风险与未决」。

语言可见的内存语义契约（`type` / `type mutable`、`Clone` 浅拷贝、`Drop`、
managed ref 语法删除）的正本是 [`type-semantics.md`](type-semantics.md)。
本文只写**对象/头布局与值表示**。

## 方案

### 托管对象

```c
struct __koral_Control {
    _Atomic int strong_count;
    _Atomic int weak_count;
};

#define __koral_control_of(p) \
    ((struct __koral_Control*)((char*)(p) - sizeof(struct __koral_Control)))
#define __koral_payload_of(c) \
    ((void*)((char*)(c) + sizeof(struct __koral_Control)))
```

- 头是 **8 B**，两个引用计数。`ptr` 与 `dtor` 都不在头里。
- **`dtor` 在释放调用点单态化**，由调用方作为 `__koral_Dtor` 传进
  `__koral_release_value(payload, dtor)`——同 Rust 的 `RcBox { strong, weak, value }`。
  类型擦除的析构走 vtable 的首个成员：
  `struct __koral_VTableHeader { __koral_Dtor destroy; };`
- `[Control | payload]` **一次 malloc**，强弱计数都归零才整块释放。
  弱引用靠 control 存活，不靠 payload。

### 值 / 句柄

托管值、owning 引用、借用，**统一是 `void*`（payload 地址）**。

```c
struct Koralc_Type { void* ptr; };        // 8 B
struct Std_String  { void* ptr; };        // 8 B
```

| 操作 | 发什么 |
|---|---|
| 拷贝 | `__koral_retain_value((src).ptr);` |
| 析构 | `__koral_release_value((x).ptr, dtor);` |
| 字段访问 | `((Payload*)x.ptr)->f` |
| 建对象 | `x.ptr = __koral_payload_of(malloc(sizeof(struct __koral_Control) + sizeof(struct Payload)));` |

`__koral_release_value` 收**两个参数**：`dtor` 在释放调用点传入，不由头读取。
`x.ptr` 是 payload 地址，control 块在 `ptr - sizeof(Control)`。

### trait object

**采用 Swift 的瘦对象指针约定**：对象句柄一个字，引用计数在 payload 之前的固定偏移处。
**不采用 Swift 的扁平 existentials 布局**
（`{ 3-word inline buffer | value metadata | witness tables }`）。

```c
struct __koral_TraitRef {
    void* ptr;             // payload 地址
    const void* vtable;    // 静态 vtable 实例
};                          // 16 B
```

vtable 是**每个（trait, 具体类型, 类型实参）一份静态结构体**，成员为函数指针，
首成员是 `__koral_VTableHeader`（`destroy`）。

### 弱引用

```c
struct __koral_WeakRef { void* control; };   // 1 字，存 control 地址
```

**弱引用不与强句柄同形。** 强句柄存 payload 地址，弱引用存 **control 地址**。
理由：**payload 可能已经销毁**，而 weak 仍要能查 `strong_count` 判断能否 upgrade。
这也与 niche 表里的 `__koral_WeakRef | control == NULL` 一致。

（用户 API 是 `?T(x)` 构造、`?expr` 升级；下面两个名字是 **C 运行时内部**
`__koral_downgrade_ref` / `__koral_upgrade_ref`，不是用户可调函数。）

- `__koral_downgrade_ref(p)` → `w.control = __koral_control_of(r.ptr); __koral_weak_retain(w.control);`
- `__koral_upgrade_ref(w)` → CAS `strong_count`（要求 `>0`）到 `+1`，成功则
  `r.ptr = __koral_payload_of(control)`——从 control **反推** payload。

### 借用（本设计的关键裁定）

> **方法借用者同样传瘦指针，只是不触发 retain / release。**

```c
void* r = &local;                 // 或 &local 的 payload 地址
```

依据（实测）：形态 A（借栈局部，1,747 处）与形态 F（user `Drop` 前奏，209 处）
的 `control` **本来就是 `NULL`**，从来没有 retain/release。借用的寿命由**栈作用域**
保证（局部活过借用），不靠引用计数；类型系统已禁止借用逃逸——不能进 struct 字段、
enum payload、返回类型、全局变量、lambda 捕获。

因此借用就是「非拥有的瘦指针」，与 `*T` 同宽，只是不可解引用到裸内存之外、
不可 `free`。

| 场景 | 传什么 | retain/release |
|---|---|---|
| 方法接收者按引用传参 | `void*`（payload 地址） | 无 |
| `Drop.drop(self)` 前奏 | `void* raw_payload` | 无 |
| owning 参数 / 返回 | `void*`（payload 地址） | 有 |
| trait 方法接收者 | `void*` | 调用点按 ownership 决定 |

**双字句柄唯一能立论的形态（内部借用：借 payload 内部、记宿主 control）在整个系统里
从未出现。** 这是删掉 `control` 字的直接依据。

### 静态值 / 字面量：immortal 头

`retain(p)` 读的是 `p - sizeof(Control)`，**不能再用 `control == NULL` 当哨兵**。
改用 immortal 头（Swift 的做法）：字面量在 `.rodata` 里前置一个真 `Control`，
control 与 payload 合在一个常量结构体里发：

```c
static const struct {
    struct __koral_Control ctrl;
    struct <Payload> payload;
} <name>_block = { { -1, -1 }, { ... } };
/* 值 = { .ptr = &<name>_block.payload } */
```

`retain`/`release` 读到 `strong_count == -1` 直接返回。成本是每个静态字面量多 8 B
常量数据；收益是 `control == NULL` 这个「静态 / 非拥有」双重哨兵消失，表示统一。

⚠️ **当前实现里还没有静态托管值**：字符串字面量每次都 `malloc`。immortal 头已写进
运行时为将来预留。

同一个哨兵也用在**析构期间**：`__koral_release_slow` 在跑析构函数体前后把
`strong_count` 置 -1 / 恢复 0，让 `drop` 里的 `self.m()`（按值接收者会 retain）不复活
对象、不重入析构。理由见 [`type-semantics.md`](type-semantics.md)「析构期间对象不可复活」。

### 尺寸与收益

| | 改造前 | 现在 |
|---|---|---|
| `__koral_Control` | 24 B | **8 B** |
| 托管句柄 / `Ref` | 16 B | **8 B** |
| `__koral_TraitRef` | 24 B | **16 B** |
| `String` 堆块 | 40 B | **24 B** |
| `List` 堆块 | 48 B | **32 B** |
| `Option[String]` | 24 B | **8 B**（niche） |
| `Option[Int]` | 24 B | **16 B**（无 niche，保留 tag） |

bootstrap 自举包（`check --package-config compiler/koral.json --target-module koralc`）的分配量：

| | 改造前 | 现在 | Δ |
|---|---|---|---|
| 全部分配字节 | 5,473,058,018 | 3,903,581,274 | **−1.57 GB / −28.7%** |
| 托管块字节 | 3,108,388,760 | 2,339,742,736 | −24.7% |
| 裸分配字节 | 2,364,669,258 | 1,563,838,538 | −33.9% |
| 分配次数 | 91,001,559 | 91,001,513 | **不变** |

裸分配字节降 33.9% 是**句柄减半的连锁效应**：`List[Managed]` / `Dict[String, Type]`
这些容器的底层数组元素从 16 B 变 8 B，整块数组随之减半——「句柄宽度 → 容器元素 →
结构体字段」的传导链。分配次数不变、只有尺寸变小，与预测一致。

设计层收益（比字节更重要）：

1. **布局权真正交还编译器。** `docs/guide/document.md` 承诺「`type` 无身份、布局是实现细节」，
   双字句柄把一个具体内存模型焊进了 ABI。瘦下来之后 `type` 的内联 / 去箱化才有空间。
2. **与主流 ARC/refcount 语言对齐。** Swift / ObjC / Rust `Rc` / Go 指针都是一个字。
   `shared_ptr` 的双字是 C++ 为 aliasing 做的专门妥协，Koral 不需要 aliasing 却承担了成本。
3. **FFI 自然。** 托管值过 C 边界就是一个指针，与 `*T` 一致。
4. **解锁后续表示优化**：小字符串 / 小容器、指针打标、vtable 进头。

吞吐收益**不是**理由：`_copy`/`_drop` 辅助函数合计只占 self-time 2.7%，上限 1–3%。
本项按**表示层项目**推进。

## 演进

不是一步到位，是四步收敛的。每一步都独立可验，后一步依赖前一步的形状。

1. **控制块与 payload 合并成一次 malloc。** 最初 payload 与 control 各一次 malloc
   （2× malloc）。合成 `[Control | payload]`，control 里的 `ptr` 字段记录 payload 位置。
2. **借用改成瘦指针。** `Type.borrowedReference` 从来没被真正用起来——for 循环的迭代器
   被类型化成 owning 的 `*mutable T`，而它只需要「读写下一项」。借用量不需要 control，
   于是借用变成非拥有的 `void*`。
3. **句柄去胖。** `control` 字要么是死的 `NULL`、要么可由 `ptr` 推出；aliasing 形态
   出现 0 次。句柄只存 payload 地址，`Control.ptr` 字段一并删除。
4. **头砍到 8 B，`dtor` 移出头。** drop glue 改在释放调用点单态化，类型擦除走 vtable
   首成员。随后 `Option[T]` 在 `T` 是单个可空指针字时用 niche（无 tag）。

**途中暴露并修掉的两个潜伏缺陷**：`.traitObject` 曾落到 `PrimitiveHandler`，拷贝不
retain、析构不 release——`dtor` 变真之后把静默泄漏变成了 use-after-free；`needsDrop`
没覆盖 `.genericStruct` / `.genericEnum`，泛型实例的左值拷贝被当成 move 降级。

## 替代方案

### `shared_ptr` 形状的双字句柄

**否掉。** 理由见「背景」：`control` 字无一处必需，aliasing 形态 0 次，且表层语法产生不了。
双字只为 C++ 的 aliasing 构造服务，Koral 不需要。

### Swift 的扁平 existentials 布局

**否掉。** `{ 3-word inline buffer | value metadata | witness tables }` 是为「小值免装箱」
服务的。Koral 的 trait object 永远来自一个 owning 托管引用，payload 本来就在
`[Control | payload]` 堆块里；内联缓冲区里能放下的永远只是那个指针，等于白付
value-metadata 与 value-witness-table 的成本。而且 Koral 的装箱点在**类型层**
（`type mutable` / `Drop` / 递归 → Managed），不在 existential 边界，两套装箱机制
叠加没有收益。

### `dtor` 留在头里 / 改成 vtable 索引

**留头里否掉**——那是头从 16 B 砍到 8 B 的那一步。改成 vtable 索引（再省 4 B，但每个
托管类型多一张表）**留作未决**。

### weak 存 payload 地址

**否掉。** payload 可能已销毁，而 weak 仍要查 `strong_count` 判断能否 upgrade。
存 control 才不悬垂。原文曾把「weak 与句柄同形」写进目标布局，是自相矛盾的一侧。

### `control == NULL` 当「静态 / 非拥有」哨兵

**否掉。** 瘦指针下 `retain(p)` 读 `p - sizeof(Control)`，这个哨兵读不到。
改成 immortal 头（`strong_count = -1`）。

### 与 Swift 布局的逐项对照

| | Swift | Koral | 采用？ |
|---|---|---|---|
| 对象句柄 | 1 字（指向 payload） | 1 字 | ✅ |
| 引用计数位置 | 对象头固定负偏移 | `Control` 在 `ptr - 1` | ✅ |
| 静态对象 | immortal refcount | `strong_count = -1` 头 | ✅ |
| weak | 侧表 / 头内 weak 计数 | `Control.weak_count` | ✅ |
| 派发信息 | metadata / isa 在对象头 | **独立 vtable 字在 trait object 上** | ❌ 不用 |
| existentials | 3 字内联缓冲 + value metadata + witness tables | `{ptr, vtable}` 两字 | ❌ 不用 |
| 小值免装箱 | value witness / 内联缓冲 | 不做（装箱在类型层已决定） | ❌ |

## 风险与未决

| 风险 | 说明 | 对策 |
|---|---|---|
| 析构顺序可观察 | 与 move 优化同一敏感区 | 每步单独跑全量，不叠加未验证改动 |
| 静态字面量体积 | 每个字面量多 8 B 常量（当前尚未实际发生） | 实测字面量数量后评估；必要时按内容去重 |
| `-1` refcount 与原子操作 | `atomic_fetch_add` 对 `-1` 的行为要验证 | 运行时单测；或 `retain`/`release` 首行判 `-1` |
| 借用逃逸 | 靠「借用只是 `void*` 局部量/参数」这条约定 | 保留「不可返回 / 不可存储」的检查，检查目标是传参约定而非类型 |

**未决（不阻塞）**

1. `dtor` 改成 vtable 索引 —— 头再省 4 B，但每个托管类型多一张表。
2. 静态字面量按内容去重 —— 需要先量字面量数量。
3. `?Trait`（`TraitWeakRef`，16 B）收到 1 字 —— 需要 vtable 另存，与「不用扁平布局」
   的取向一致但要多一张侧表。
4. 小容器 / 指针打标（步骤 4c）。

## 实施

四步（合并分配、借用瘦化、句柄去胖、头砍到 8 B + niche）均已落地，两个编译器同步。
实测见「尺寸与收益」。步骤 4c 见「风险与未决」。

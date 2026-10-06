# 薄指针对象表示设计（Thin Object Pointer）

状态：**第 1–4b 步已完成**（Swift 534/534；Bootstrap 534/534）
范围：值表示 / 堆布局 / ARC 头 / 引用与借用 / trait object
不涉及：语言语法（表层无可见变化）、编译性能优化项

## 实施状态

| 步骤 | 内容 | 状态 | 验证 |
|---|---|---|---|
| 1 | 删 `Control.ptr` | ✅ **完成** | 533/533 |
| 2 | 借用改瘦指针 | ✅ **完成** | 533/533 |
| 3 | 托管值 / owning ref 改瘦指针 | ✅ **完成** | Swift 533/533；Bootstrap 532/533 |
| 4a | 头砍到 8 B：`dtor` 移出头 | ✅ **完成** | Swift 533/533；Bootstrap 533/533 |
| 4b | niche `Option[T]` | ✅ **完成** | Swift 534/534；Bootstrap 534/534 |
| 4c | 小容器 / 打标 | ⬜ 后续，不在本期 | — |

### 总账（bootstrap `check` 自举包，分配量）

| | 基线 | 第 1 步 | 第 3 步后 | 总 Δ |
|---|---|---|---|---|
| 托管块字节 | 3,108,388,760 | 2,593,073,376 | **2,339,742,736** | **−24.7%** |
| 裸分配字节 | 2,364,669,258 | 2,364,660,706 | **1,563,838,538** | **−33.9%** |
| **全部分配字节** | **5,473,058,018** | 4,957,734,082 | **3,903,581,274** | **−1.57 GB / −28.7%** |
| 托管块均值 | 48.3 B | 40.3 B | **36.3 B** | −12 B |
| 裸分配均值 | 88.9 B | 88.9 B | **58.8 B** | −30 B |
| 分配次数 | 91,001,559 | 91,001,513 | 91,001,513 | **不变** |

裸分配字节降 33.9% 是**句柄减半的连锁效应**：`List[Managed]` / `Dict[String, Type]`
这些容器的底层数组元素从 16 B 变 8 B，整块数组随之减半。这正是设计预期里
「句柄宽度 → 容器元素 → 结构体字段」的传导链。

生成 C 体积：109,810,249 → **107,698,331**（−1.9%）。

### 第 1 步实测（已完成）

| 指标 | 基线 | 第 1 步后 | Δ |
|---|---|---|---|
| `sizeof(__koral_Control)` | 24 B | **16 B** | −8 |
| `String` 堆块 | 40 B | **32 B** | −8 |
| `List` 堆块 | 48 B | **40 B** | −8 |
| 托管块均值 | 48.3 B | **40.3 B** | −8 |
| 托管块字节 | 3,108,388,760 | **2,593,073,376** | **−16.6%** |
| 全部分配字节 | 5,473,058,018 | **4,957,734,082** | **−515 MB / −9.4%** |
| 头占托管块 | 49.7% | **39.7%** | |
| 头占全堆 | 28.2% | **20.8%** | |
| 托管块 / 裸分配次数 | 64,414,339 / 26,587,220 | 64,414,319 / 26,587,194 | **不变** |

分配次数完全不变、只有尺寸变小 —— 与预测一致（−8 B × 64.4M = −515 MB）。
块大小分布从「26.8% 在 32–47 B」变成「**96.1% 在 32–47 B**」。

改动点：

- `std/koral_runtime.h` — 删 `Control.ptr`；新增 `__koral_payload_of` / `__koral_control_of`
- `std/koral_runtime.c` — 2 处消费点改用 `__koral_payload_of(control)`
- `CodeGen/CodeGen.swift:1265`、`CodeGenMIR.swift:1715 / 1774 / 1937` — 4 处发射点不再写 `Control.ptr`

### 第 2 步实测（已完成）

借用 = **非拥有瘦指针**：一个指向目标值的裸指针，不带 control、不 retain / 不 release，
寿命由借用点的栈作用域保证。

bootstrap 生成 C（110 MB）形态清点：

| 形态 | 基线 | 第 2 步后 | |
|---|---|---|---|
| **A** 胖借用 `{ptr=&local, control=NULL}` | **1,747** | **0** | ✅ 消灭 |
| **N** 瘦借用 `T* = &place` | 0 | **559** | 新形态 |
| **B** 内部借用 | 0 | 0 | 从未出现 |
| **D** trait 擦除 `{ptr=x.ptr, control=x.control}` | 519 | 519 | 不变（owning） |
| **F** user `Drop` 前奏 `{ptr=raw, control=NULL}` | 209 | 209 | 不变 |
| `.control = NULL` 合计 | 1,956 | **209** | **−89%** |
| `struct __koral_Ref` 出现 | 4,100 | **606** | **−85%** |
| 生成 C 体积 | 109,810,249 | **108,686,839** | −1.1 MB |

for 循环的迭代器借用（占胖借用的 100%）从三步中转变成一步直取：

```c
// 之前
struct __koral_Ref _t;  _t.ptr = &iter;  _t.control = NULL;
struct ListIterator_X tmp = _copy(&(*(struct ListIterator_X*)_t.ptr));
// 现在
struct ListIterator_X tmp = _copy(&iter);
```

**修正（相对 §6 的原判断）**：`Type.borrowedReference` / `mutableBorrowedReference`
**不是死变体，而是借用的正确标记** —— 借用与 owning ref 的 C 表示不同
（`T*` vs `struct __koral_Ref`），必须由类型区分。原先它们只是**从未被播种**：
for 循环迭代器借用被误标成 `.mutableReference`，`MIRTypeResolver` 又一律把
`.ref(..., stackBorrow)` 解析成 owning 类型。本次修正为：

| 改动 | |
|---|---|
| 播种 | for 循环迭代器 → `.mutableBorrowedReference`（`TypeCheckerExpressions`） |
| 解析 | `MIRTypeResolver.type(of: .ref)` 按 `allocation` 区分 borrowed / owning |
| 种类 | `referenceKind(for:)` 把 `.mutableBorrowedReference` 归到 `.mutable` |
| C 类型 | 借用 → `"<innerCType>*"`（`ReferenceHandler.generateCTypeName`） |
| 语义 | 借用 `needsCopyFunction` / `needsDropFunction` = false |
| codegen | `emitBorrowedReference` 只发 `T* = &place`；`emitPlaceAccess` 的 `.field` / `.deref`、`controlExpression` 分出借用分支 |

因此 §6 里「删除 `Type.borrowedReference` + 13 处逃逸禁令」**不成立，改为保留**：
类型是标记，禁令（不可进字段 / 返回 / 全局 / lambda 捕获）仍是「借用不逃逸」的保证。

### 第 3 步实测（已完成）

值表示 / owning ref / trait object 全部单字化：

| | 今天 | 目标 | 实测 |
|---|---|---|---|
| `__koral_Control` | 24 B | 16 B | ✅ 16 B |
| 托管值句柄 | 16 B | 8 B | ✅ **8 B** |
| `__koral_Ref` | 16 B | 8 B | ✅ **8 B** |
| `__koral_TraitRef` | 24 B | 16 B | ✅ **16 B** |
| `__koral_WeakRef` | 8 B | 8 B | ✅ 8 B |
| `Option[String]` | 24 B | 16 B | ✅ **16 B** |
| `String` 堆块 | 40 B | 32 B | ✅ 32 B |
| `List` 堆块 | 48 B | 40 B | ✅ 40 B |

生成 C 的 control 痕迹：**2,475 → 14**（剩下的全是 `__koral_WeakRef` / `__koral_TraitWeakRef`
的 control 字，弱引用本来就是单字）。

改动点：

- `std/koral_runtime.h` — `__koral_Ref` / `__koral_TraitRef` 去掉 `control` 字；
  新增 `__koral_retain_value` / `__koral_release_value`（从 payload 指针出发，内部换算 control）；
  `KORAL_IMMORTAL_REFCOUNT`（见下）
- `std/koral_runtime.c` — `__koral_ref_drop` / `__koral_downgrade_ref` / `__koral_upgrade_ref`
  改由 `__koral_control_of(ptr)` 推出 control
- `CodeGenTypes.swift` — 托管值 `_copy` / `_drop` 改 `__koral_retain_value` / `__koral_release_value`；
  user `Drop` 前奏不再写 `control = NULL`
- `CodeGen.swift` — 托管 wrapper 声明只留 `void* ptr`；字面量构造、引用 copy/drop
- `CodeGenMIR.swift` — 3 处分配序列改 `__koral_payload_of(malloc(...))`；
  downgrade / upgrade / cast 的 control 字全部改为 ptr；删掉 `MIRPlaceAccess.control` 与 `controlExpression`
  （第 2 步后已无人读取）
- `CodeGenVtable.swift` — `TraitRef` 构造、trait 调用的 `self` 参数
- `TypeHandler.swift` — owning ref 的 copy/drop 走 `_value` 包装

**§3.6 静态字面量的修正**：原设计以为字面量是 `{ptr=&rodata, control=NULL}` 需要 immortal 头。
实测**当前实现里没有静态托管值**（`static const struct __koral_payload_*` 命中 0 次）——
字符串字面量每次都 `malloc` 字节 + `[Control|payload]` 块。因此：

- `KORAL_IMMORTAL_REFCOUNT` 与 retain/release 的 `< 0` 早退**已经写进运行时**，
  为将来引入静态托管值预留（也顺带让 `__koral_retain_value` 对 NULL 安全）。
- 「字面量零分配」本身是另一项独立优化，不在本期。若将来做，immortal 头即可直接用。

### 第 4a 步 — 头砍到 8 B：`dtor` 移出头

**动机**（实测）：107 MB 生成 C 里 10,459 处堆分配，**每一处都设了非 NULL 的 `dtor`**（414 个不同目标），
`weak_count` 全库 0 次弱引用。头的三个字段里，只有 `dtor` 是可以挪走的。

**做法**（对齐 Rust `RcBox { strong, weak, value }`——头里没有 dtor，drop glue 在
`Rc::drop::<T>` 处单态化）：

| | 之前 | 之后 |
|---|---|---|
| `__koral_Control` | `{strong, weak, dtor}` = 16 B | `{strong, weak}` = **8 B** |
| `__koral_release_value` | `(payload)`，dtor 从头读 | `(payload, dtor)`，**调用点传** |
| 类型擦除的析构 | 头里的 `dtor` | vtable 的 `base.destroy` |
| `__koral_ref_drop` | 通用 dtor | **删除**，按内层类型单态化 thunk |

8 B 是下限：payload 要 8 字节对齐，4 字节头会把 payload 挤到未对齐地址。
`weak_count` 保留 —— weak 的语义是「control 块比 payload 活得久」，这个计数必须在。

**vtable 公共前缀**（对应 Swift 把 value witness 塞进 metadata 头，但**不用扁平布局**）：

```c
struct __koral_VTableHeader { __koral_Dtor destroy; };
struct __koral_vtable_Error {
    struct __koral_VTableHeader base;   // 必须是第一个成员，destroy 落在 offset 0
    struct Std_String (*message)(struct __koral_Ref);
};
```

trait object 释放读 `((const struct __koral_VTableHeader*)vt)->destroy`，不需要知道具体 trait。
Koral 的 trait object 一律装箱，所以不需要 Swift 的3 词内联缓冲 + value metadata + witness tables。

**布局实测**（`clang -O1` + `sizeof`）：

| | 实测 |
|---|---|
| `__koral_Control` | **8 B** |
| `__koral_Ref` | 8 B |
| `__koral_TraitRef` | 16 B |
| `__koral_WeakRef` | 8 B |
| `__koral_VTableHeader` | 8 B |
| vtable `base` 偏移 | **0** ✅ |

**预期收益**：托管块均值 36.3 → 28.3 B（−22%），约 **515 MB** 托管堆字节（占总量 13.2%）。
实际分配器收益可能更大 —— 28 B 与 36 B 常落在不同的 malloc size class（48 → 32）。

**块大小实测**（`clang -O1` + `sizeof`）：

| | 第 3 步后 | 第 4a 步后 | Δ |
|---|---|---|---|
| `String` 堆块 | 32 B | **24 B** | −8 |
| `List` 堆块 | 40 B | **32 B** | −8 |
| `String` 句柄 | 8 B | 8 B | 不变 |

**改动点（Swift 侧）**：

- `std/koral_runtime.h` / `.c` — `Control` 去 `dtor`；`release_slow(control, dtor)`；
  `__koral_release_value(payload, dtor)`；新增 `__koral_VTableHeader`、`__koral_traitref_drop`；
  删除 `__koral_ref_drop`
- `CodeGen.swift` — 新增 `dropFunctionPointer(for:)`（drop glue 函数指针解析）、
  `materializeDropThunk(for:)`（`Ref[Y]` 这类无现成 glue 的按需物化）、
  `appendReleaseHandleStatement`（trait object 走 `vtable->destroy`）；
  `appendDropStatement` 直接分派引用类型
- `CodeGenTypes.swift` — `_drop` 传 `__koral_X_payload_drop`
- `CodeGenVtable.swift` — vtable 结构体加 `base` 前缀；实例发 `.base = { destroy }`；
  wrapper 释放传具体类型的 glue
- `CodeGenMIR.swift` — 分配点不再写 `->dtor`；释放点传 dtor
- `TypeHandler.swift` — `ReferenceHandler` 认领 `.traitObject`（见下）；drop 带 dtor

**顺带修掉的两个既有缺陷**：

1. **`.traitObject` 掉进 `PrimitiveHandler`**：`ReferenceHandler.canHandle` 不认裸 `.traitObject`，
   拷贝不 retain、析构不 release。第 4a 步让析构真正释放之后，这个静默泄漏变成了
   提前释放（`or_return_basic` 等 4 例段错误）。已让 `ReferenceHandler` 认领 `.traitObject`。
2. **`needsDrop` 不认泛型实例化**：`.genericStruct` / `.genericEnum` 落到 `default: return false`，
   导致 `emitCopyOrMove` 把 lvalue 拷贝当 move。已并入 `hasNontrivialNominalDrop` 判断。

---

### 第 4b 步 — niche `Option[T]`（设计，待实施）

**动机**：`Option` 现在是显式标签联合 `struct { intptr_t tag; union {...} data; }`。
`Option[Int]` = 16 B，`Option[String]` = 8（tag）+ 8（handle）= 16 B。
瘦指针之后 `String` / `Ref` / `TraitRef` 的表示都是 `void*` 系，**NULL 这个位模式是空的**
（活对象的 handle 永不为 NULL）—— 这就是 niche。

实测确认过一件关键事：`__koral_upgrade_ref` 失败返回的 `r.ptr = NULL` 是**瞬时的**，
`CodeGenMIR` 立刻转成 `.tag = 0`，从不作为活值流出。所以 `Ref` 也能拿到 NULL niche，
不只是 managed 名义类型。

#### 哪些表示有 niche

| 表示 | 空位模式 | 判定 |
|---|---|---|
| managed 名义 wrapper `struct X { void* ptr; }` | `ptr == NULL` | ✅ |
| `__koral_Ref` / `__koral_TraitRef` | `ptr == NULL` | ✅ |
| `__koral_WeakRef` | `control == NULL` | ✅ |
| 瘦借用 `T*` | `== NULL` | ✅（但借用不可存储，实际用不到） |
| `Int` / `UInt` / `Float` | 无 | ✗ |
| 裸指针 `*unsafe T` | NULL 可能是合法值 | ✗（保守排除） |
| `Closure { fn, env, drop }` | 不确定 | ✗（保守排除） |

#### 布局规则

对**两 case、其中恰好一个无参数、另一个恰好一个参数且该参数有 niche** 的枚举
（这正是 `Option[T] { None(), Some(value T) }` 的形状）：

```c
struct Option_Std_String_d91 {
    union {
        struct {} None;
        struct { struct Std_String value; } Some;
    } data;
};   // sizeof == sizeof(struct Std_String) == 8
```

**去掉 `intptr_t tag`**，`None` 用 niche 值表示。`data.Some.value` 的字段路径**不变**，
所以绝大多数 codegen 不用动。

#### 读写路径

| | tag 布局 | niche 布局 |
|---|---|---|
| 构造 `Some(x)` | `e.tag = 1; e.data.Some.value = x;` | `e.data.Some.value = x;`（x 永不为 niche） |
| 构造 `None()` | `e.tag = 0;` | **清零 payload**：`e.data.Some.value.ptr = NULL;` |
| `when` 分派 | `switch (e.tag)` | `switch (e.data.Some.value.ptr == NULL ? 0 : 1)` |
| `_copy` / `_drop` | `switch (self->tag)` | 同上，换成 niche 测试 |

关键是 **`emitEnumTag` 只负责把 case 序号算成一个 `intptr_t`**，后面的 switch/match
机器完全不用改。所以 niche 只动「tag 怎么算」和「tag 存不存」两处。

#### 需要改的地方

| 文件 | 内容 |
|---|---|
| `CodeGen.swift` | 新增 `hasNullNiche(_:)`、`enumNicheLayout(_:)`（返回空 case 序号 / payload case 序号 / 字段名 / 内层类型）、`nicheTagExpression(...)` |
| `CodeGenTypes.swift` | niche 枚举的 payload struct 不发 `intptr_t tag;`；`_copy` / `_drop` 的 `switch (self->tag)` 换成 niche 测试 |
| `CodeGenMIR.swift` | `emitEnumCase` 构造：空 case 写 niche（清零 payload），不发 `.tag =`；`emitEnumTag` 用 niche 测试 |

`std/option.koral` 的 `is_some` / `is_none` / `unwrap` / `map` 等全走 `when self in {...}`，
**不用改**。

#### 嵌套与回落

- **`Option[Option[T]]` 不叠加 niche**：内层已经把唯一的空位模式（NULL）用掉了，
  外层若也用 NULL 表示 `None`，就和内层的 `.Some(Option.None())` 撞在一起，
  两种值无法区分。所以「自己已经用了 niche 的类型」不再给外层提供 niche。
  这和 Rust 的处理一致（Rust 靠额外的对齐指针值造第二个 niche，Koral 不做）。
  `hasNullNiche` 因此只认**原始的单字可空指针表示**（managed wrapper / Ref / WeakRef / 借用），
  不认 niche 布局后的枚举。
- `Option[Int]`：`Int` 无 niche → 回落 tag 布局。两套并存。
- `Result[T, E]`：两个 case 都有 payload → 无 niche，回落。
- `Option[Pair[String, String]]`：两个字，没有单一空位模式 → 回落。

#### 实测（Swift 侧已完成）

| | tag 布局 | niche 布局 | Δ |
|---|---|---|---|
| `Option[String]` | 16 B | **8 B** | **−50%** |
| `Option[Ref[T]]` / `Option[Box]` | 16 B | **8 B** | **−50%** |
| `Option[Int]` | 16 B | 16 B | 无 niche，回落 |
| `Option[Option[String]]` | 16 B | 16 B | 内层已占 niche，回落 |
| `Option[Pair[String,String]]` | 24 B | 24 B | 两字，无 niche，回落 |

实际分派（`option_niche_layout_test` 生成的 C 里逐个核对）：

```
Option_Std_String_d91                    NICHE
Option_Option_Std_String_d91_d91         TAG      ← 嵌套回落
Option_I_d91 / I8 / I16 / I32 / I64      TAG
Option_U_d91 / U8 / U16 / U32 / U64      TAG
Option_Std_Rune_d91                      TAG
Option_Pair_Std_String_Std_String_...    TAG
```

生成代码形态（`Option[String]`）：

```c
struct Option_Std_String_d91 {
    union {
        struct {} None;
        struct { struct Std_String value; } Some;
    } data;
};

struct Option_Std_String_d91 __koral_Option_Std_String_d91_copy(const struct Option_Std_String_d91 *self) {
    struct Option_Std_String_d91 result;
    switch (((self->data.Some.value.ptr == NULL) ? 0 : 1)) {
    case 0: // None
        result.data.Some.value.ptr = NULL;   // 空 case 必须写回 niche，否则 result 带脏值
        break;
    case 1: // Some
        result.data.Some.value = __koral_Std_String_copy(&self->data.Some.value);
        break;
    }
    return result;
}
```

`std/option.koral` 的 `is_some` / `is_none` / `unwrap` / `map` 全走 `when self in {...}`，
**一行没改** —— `emitEnumTag` 只负责把 case 序号算成 `intptr_t`，后面的 switch 机器不变。

新增回归用例 `tests/compiler-cases/option_niche_layout_test.koral`，锁住三件事：
niche 路径的 Some/None 进出、tag 回落路径、以及 `Option[Option[String]]` 三种可区分状态。

#### 风险

- `Some(x)` 里 `x` 恰好是 niche 值会破坏编码。**不变量：活的 owning handle 永不为 NULL**。
  这条要写进类型系统的假设里；将来若有「可空句柄」类型，必须先排除出 niche 名单。
- 构造 `None` 必须**清零整个 payload**，否则 `data.Some.value.ptr` 读到脏值会判成 `Some`。

---

### 第 4a 步 Bootstrap 同步记录

| | 结果 |
|---|---|
| Swift 宿主编译器 | **533/533**（70.5 s） |
| Bootstrap 编译器 | **533/533**（62.0 s） |

比第 3 步后的 532/533 多了 1 例 —— 原先挂的 `sync_channel_test`（并发用例）这次过了，
说明它的失败是第 3 步 bootstrap 同步里某个遗漏的表示层改动，不是并发本身的问题。

bootstrap 侧的改动：

- `codegen_memory.koral` — 新增 `drop_function_pointer` / `materialize_drop_thunk` /
  `append_release_handle_statement` / `append_release_value_line` / `is_trait_object_type`；
  `append_release_control_line` 只保留 retain/weak 路径，release 一律走 `append_release_handle_statement`
- `codegen_types.koral` — 托管名义 `_drop` 传 `__koral_X_payload_drop`
- `codegen_vtable.koral` — vtable 结构体加 `struct __koral_VTableHeader base;` 前缀；
  实例发 `.base = { destroy }`；wrapper 释放传具体类型 glue
- `codegen_mir.koral` — 分配点不再写 `->dtor`；`MIRPlaceAccess` 去 `control`；
  释放点传 dtor
- `codegen_expressions_literals.koral` — immortal 头的 `Control` 初始化器从 3 字段改 2 字段
- `codegen_generate.koral` — drop thunk 占位 + splice

**vtable 布局的一个坑**：vtable 加了 `base` 前缀之后，MIR 里按索引发方法调用的
匿名前缀结构体（`vtable_prefix_struct_type_for_mir_method`）也必须同步加 `base`，
否则 slot 0 会被当成方法指针、把 `destroy` 当方法调掉。改完这一处，
14 个 trait-object / `e.message()` 相关的失败一次性消失。

---
### 第 4b 步 Bootstrap 同步记录

| | 结果 |
|---|---|
| Swift 宿主编译器 | **534/534** |
| Bootstrap 编译器 | **534/534** |

**布局一致性**（`option_niche_layout_test` 两边 emit-c 后逐个核对，DefId 后缀归一化）：

14 个 `Option` 实例化，**0 处不符**。

| `Option[T]` | Swift | Bootstrap |
|---|---|---|
| `Option[String]` / `Option[Box]` | NICHE | NICHE |
| `Option[I]` / `I8` / `I16` / `I32` / `I64` | TAG | TAG |
| `Option[U]` / `U8` / `U16` / `U32` / `U64` | TAG | TAG |
| `Option[Rune]` | TAG | TAG |
| `Option[Pair[String,String]]` | TAG | TAG |
| `Option[Option[String]]` | TAG | TAG |

（两个编译器的 DefId 编号本来就不同：`Option_Std_String_d91` vs `_d49`，命名规则一致。）

bootstrap 侧改动：`codegen_memory.koral`（`EnumNicheLayout` + niche 判定/测试/置空/取 tag）、
`codegen_types.koral`（条件发 tag、copy/drop 走 niche 测试）、
`codegen_mir.koral`（`emit_enum_case` 空 case 写 niche、`emit_enum_tag` 出 niche 三元、
`emit_upgrade_ref` 不再发 `.tag = 1/0`）。

#### 自举包里的实际分布

bootstrap 编译器自己的包（约 10 万行）里 **243 个 `Option` 实例化**：

- **NICHE 58 个** —— 全是 managed 句柄，且都是热路径容器：
  `Option[Dict[String, Type]]`、`Option[Dict[String, Symbol]]`、`Option[Expr]`、
  `Option[Field]`、`Option[FunctionParamSpec]`、`Option[CompilationUnit]` …
- **TAG 185 个** —— `Option[Int]` / `Option[Bool]` / `Option[Float]` / 各种无 niche 的枚举

每个 niche 实例化从 16 B 降到 8 B（payload 是 8 B 句柄，tag 是 8 B）。

#### 后续修复：bootstrap 的 `break` 分支边界误判（已修）

原先 `bin/compiler/koralc check --package-config compiler/koral.json` 会报

```
compiler/koralc/mono/mono_expr_substitution.koral:1152:65: error: break cannot penetrate through branch boundary
```

同一个文件 Swift 编译器接受。已确认**不是本次表示层改动引起的**（规则实现在 `mono/` 与 `sema/`，
本次改动前零改动；关掉 niche 重建同样报错），随后单独修掉了。

根因：bootstrap 里有一套**未完成的「branch break target」脚手架**——`BranchBreakTarget`
的三个字段（`did_explicit_branch_break` / `construct_stack_depth_at_creation`）和
`current_branch_break_target()`、MIR 侧的 `lower_branch_break()`、
`typed_expr_contains_branch_break()` **全部只声明不调用**。唯一活着的副作用是
`push_branch_break_target()` 往 `exitable_construct_stack` 压了一个 `.Branch()` 标记，
于是 `break` 的检查把 `or else` 默认值、`and then` 变换体、`if` 表达式里的 `break`
误判成「穿越分支边界」。而 `when` 分支体和 `if` 语句不触发，行为自相矛盾。

对齐 Swift 的语义（实测钉死）：`break` 绑到最内层循环，`if` / `when` / `or else` /
`and then` / `if` 表达式都不拦截。修法是把整套死脚手架删掉（-279 行），并把
break/continue/defer 的报错文案对齐 Swift。

新增 `tests/compiler-cases/break_across_branch_test.koral` 与
`break_outside_loop_error.koral` 等看护。`docs/document.md` / `docs/document-zh.md`
里「不能穿透分支边界」的描述已改写。

**随后又发现并修掉了 Swift 侧的对偶缺陷**：`break` / `continue` 写在**闭包**里时，
Swift 不报错、而是**静默生成空操作**（循环照跑满），因为 `inferLambdaExpression`
只重置了 `insideDefer`，没重置 `loopDepth`。bootstrap 一直是拦对的。修法是在
lambda body 检查前把 `loopDepth` / `exitableConstructStack` 归零，两个语句都拦。

最后把两侧的死脚手架清干净并收敛到同一形态：Swift 删掉
`ExitableConstruct` / `exitableConstructStack` / 那条永不触发的 `.branch` 检查，
把 `loopDepth: Int` 换成 `inLoop: Bool`（2 个循环点原本没有 `defer`，异常时会泄漏深度，
一并改成 save/restore）；bootstrap 删掉只写不读的 `loop_depth`。两边现在都只有
`in_loop` / `inLoop` + `in_defer` / `insideDefer` 两个状态字段，并在
decl / member / lambda / 全局表达式四处函数边界统一归零。

最终 541/541（双侧），`break` / `continue` 在
`if` / `when` / `or else` / `and then` / `if` 表达式 / 闭包边界
六类位置的行为两边完全一致。

---
### 第 1–4b 步动态分配实测（补测）

前面几步的静态布局是实测的；动态分配字节差当时没能重测——测负载
`bootstrap check` 自举包被那个 break bug 挡住了。修掉之后补测如下。

**测量方法**：`DYLD_INTERPOSE` 拦截 `malloc`/`calloc`/`realloc`，统计**进程内累计堆分配
字节数与次数**。基线 = `76ae6d17`（薄指针改造前）用其自身编译器与 std 建出的 bootstrap；
当前 = 最新。两边跑**同一份负载源**，各自用自己的 std（混用会因运行时 ABI 不同而编译失败）。

| 负载 | 基线 | 当前 | Δ |
|---|---|---|---|
| `check` test-runner（1919 行 + std） | 399,507,003 B | **261,806,937 B** | **−34.5%** |
| `build` test-runner（类型检查 + 代码生成 + clang） | 1,122,873,342 B | **756,599,959 B** | **−32.6%** |
| `check` std（13 个模块） | 227,770,769 B | **148,329,055 B** | **−34.9%** |
| **合计** | **1,750,151,114 B** | **1,166,735,951 B** | **−583,415,163 B / −33.3%** |

| | 基线 | 当前 | Δ |
|---|---|---|---|
| 分配次数 | 31,457,462 | 31,269,286 | **−0.6%**（不变） |
| 平均每次分配（三负载合计） | 55.6 B | **37.3 B** | **−32.9%** |
| 峰值 RSS（`build` 负载） | 359,317,504 B | 364,183,552 B | +1.4%（噪声内，不是本项指标） |

分配次数几乎不变、单次尺寸降 32.9% —— 这正对上设计预期：改造没有增减对象个数，
只是把每个对象做小了（句柄 16→8、头 24→8、`Option[managed]` 24→8）。
峰值 RSS 不受影响也正常，它由**存活集**与生成 C 的缓冲区决定，与累计分配量是两回事。

**最富的负载（bootstrap 自检 10 万行包）无法做对比**：基线编译器编不了自己的源，
会撞上 `mono_expr_substitution.koral:1152` 的 break bug（正是本轮修掉的那个）。
也就是说 `bootstrap check` 自举包这条路径**在修复之前从来没跑通过**，现在 exit=0。

---
---

## 0. 结论先行

当前每个托管值都是 `{ void* ptr; void* control; }` 双字句柄（`shared_ptr` 形状）。
实测表明：

1. **`{ptr, control}` 的 `control` 字在系统里没有任何一处是必需的** —— 要么是 `NULL` 死字，要么可由 `ptr` 推出。
2. 唯一能证明双字合理的形态（借 payload 内部、记宿主 control，即 `shared_ptr` 的 aliasing 构造）**在 110 MB 生成 C 与 325 个测试用例中出现 0 次**，且表层语法根本产生不了它。
3. **ARC 头（24 B）占托管堆字节的 49.7%**，占全部堆字节的 28.2%。

因此目标布局：

```
托管对象      [ Control(16B) | payload ]        一次 malloc
值 / 句柄     void*                             payload 地址；control 在 ptr - 1
trait object  { void* ptr; const void* vtable } 16 B
弱引用        void*                             与句柄同形
借用          void*                             不 retain / 不 release
```

---

## 1. 现状

### 1.1 值表示

| Koral 类型 | C 类型 | 大小 | ARC |
|---|---|---|---|
| `type` 值类型（无 `Drop`、无递归） | 内联 struct | 不定 | 否 |
| `type mutable` / 有 `Drop` / 递归类型 | 具名 struct `{ void* ptr; void* control; }` | **16 B** | 是 |
| `*T`（owning ref） | `struct __koral_Ref` | **16 B** | 是 |
| `ref *T`（borrowed） | `struct __koral_Ref` | **16 B** | 否 |
| `?T`（weak） | `struct __koral_WeakRef` | 8 B | 弱 |
| `*Trait`（trait object） | `struct __koral_TraitRef` | **24 B** | 是 |
| `?*Trait` | `struct __koral_TraitWeakRef` | 16 B | 弱 |
| `*unsafe T` | `T*` | 8 B | 否 |

### 1.2 堆布局

```
malloc( sizeof(Control) + sizeof(payload) )
[ __koral_Control (24B) | payload ]
   strong(4) weak(4) dtor(8) ptr(8)      ← ptr 与 ptr+1 冗余
```

`Control.ptr` 恒等于 `control + 1`：4 处发射点全部是
`ptr = (char*)control + sizeof(struct __koral_Control)`。
消费点只有 2 处：`dtor(control->ptr)`、`upgrade_ref` 回取 payload。

生命周期（`std/koral_runtime.c`）：

```
strong -> 0 : dtor(payload)；若 weak_count == 0 则 free(control)
weak  -> 0 : 若 strong == 0 则 free(control)
```
即 `[Control | payload]` 整块在「强弱计数都归零」时才释放，弱引用靠 `control` 存活。

### 1.3 引用类型与借用

`*T` / `*mutable T` / `ref *T` / `ref mutable *T` **表层语法已删除**：

- `docs/grammar.bnf` 只保留 `&unsafe` / `&unsafe mutable`（裸指针）与 `*` 解引用。
- Swift parser **从不构造 `addressOfExpression`**（`AST.swift:513` 只有定义，`Parser/` 无构造点）。
- bootstrap parser 无对应节点。
- `coerceReceiverType` 自带注释：*"compiler-internal `.reference`/`.mutableReference` …
  NOT user-written `*T` syntax (which is removed)"*（`TypeCheckerExpressions.swift:696`）。

`.reference` / `.borrowedReference` 因此全部是**编译器内部管道**，来源只有：

1. 方法接收者 auto-ref（`coerceReceiverType`）
2. trait object 擦除（`convertToTraitObject`）
3. `Drop.drop(self)` 的 `self`（`*unsafe mutable Self`，裸指针）

类型层面 borrowed 与 non-borrowed **连 ABI 都不区分**（`Sema/Type.swift:690`）：

```swift
case .reference:                return .byRef
case .borrowedReference:        return .byRef       // 同一 PassKind
case .mutableReference:         return .byMutRef
case .mutableBorrowedReference: return .byMutRef
```
`IndirectionFamily` 也都是 `.managedReference`。差别只在 codegen 里一个 `malloc`、一个不 `malloc`。

---

## 2. 实测

测量口径：macOS ARM64，`compiler-reference/.build/release/koralc` 产出 C，同源码 clang `-O1` 构建。
工作负载 = bootstrap 编译器 `check --package-config compiler/koral.json --target-module koralc`
（9.9 万行 Koral + std）。

### 2.1 大小

| | 今天 | 薄指针 |
|---|---|---|
| `__koral_Control` | 24 B | **16 B**（删 `ptr`） |
| 托管值 / `__koral_Ref` | 16 B | **8 B** |
| `__koral_TraitRef` | 24 B | **16 B** |
| `__koral_WeakRef` | 8 B | 8 B |
| `String` | 16 B | 8 B |
| `Option[String]` | **24 B** | **16 B**（niche 后 8 B） |
| `Option[Int]` | 16 B | 16 B |
| `DictBucket[String, Type]` | 40 B | 24 B |

### 2.2 分配画像

| | 次数 | 字节 | 均值 |
|---|---|---|---|
| 托管堆块 | **64,414,339** | 3,108,388,760 | **48.3 B** |
| 裸分配 | 26,587,220 | 2,364,669,258 | 88.9 B |
| 合计 | 91,001,559 | 5,473,058,018 | |

```
ARC 头 24B × 64.4M = 1,545,944,136 B
    = 全部堆字节的 28.2%
    = 托管块字节的 49.7%
删掉 Control.ptr 后少 515,314,712 B = 全堆 9.4%
```

托管块大小分布（97% 落在 32–63 B，即「头 + 小 payload」）：

| 块大小 | 数量 | 占比 | 典型内容 |
|---|---|---|---|
| 32–47 B | 17,287,609 | 26.8% | `String` = 头24 + `{data,len}`16 = 40 |
| 48–63 B | 45,110,628 | 70.0% | `List`/`Dict`/`Set` = 头24 + `{ptr,len,cap}`24 = 48 |
| 64–175 B | 2,004,298 | 3.1% | `Type` / `TypedExpr` 等 |
| 其余 | 8,494 | 0.01% | |

峰值常驻堆 ~210–250 MB / ~170 万对象。

### 2.3 借用形态清点

按 `ptr` 的来源对生成 C 的**每一个**引用构造点分类：

| 形态 | 生成代码 | bootstrap | 控制字 |
|---|---|---|---|
| **A** 借栈局部 | `x.ptr = &local; x.control = NULL;` | **1,747** | **死** |
| **D** trait 擦除 | `x.ptr = y.ptr; x.control = y.control; x.vtable = ...` | **519** | 活（owning） |
| **F** user `Drop` 前奏 | `x.ptr = raw_payload; x.control = NULL;` | **209** | **死** |
| **B** 内部借用 | `x.ptr = &((struct Payload*)y.ptr)->f; x.control = y.control;` | **0** | — |

计数自洽：`.control = NULL` = 1747 + 209 = 1956；`.control = <y>.control` = 519。无第四形态。

测试套件 496 个文件（533 个用例）中 325 个成功出 C，其余为预期报错用例。
**内部借用（B）命中 0 个用例。**

`{ptr, control}` 双字的唯一立论就是 B —— `std::shared_ptr` 的 aliasing 构造。
它在整个系统里从未出现。

### 2.4 vtable wrapper 实际形态

```c
static struct Std_String __koral_wrapper_Std_Io_IoError_Error_message(struct __koral_Ref self_ref) {
    struct Std_Io_IoError self_val = __koral_Std_Io_IoError_copy((struct Std_Io_IoError*)self_ref.ptr);
    struct Std_String __koral_ret = __mono_method_E_182_trait_Error_margs_none_message(self_val);
    __koral_release(self_ref.control);
    return __koral_ret;
}
```

调用点先 `__koral_retain(self_arg.control)`，wrapper 末尾 `__koral_release` ——
**平衡的 owning 对**，不是借用。且 `self_ref.ptr == control + 1`。

---

## 3. 目标布局

### 3.1 托管对象

```c
struct __koral_Control {
    _Atomic int strong_count;
    _Atomic int weak_count;
    __koral_Dtor dtor;
    /* 不再有 ptr —— payload 恒在 control 之后 */
};

#define __koral_control_of(p) \
    ((struct __koral_Control*)((char*)(p) - sizeof(struct __koral_Control)))
#define __koral_payload_of(c) \
    ((void*)((char*)(c) + sizeof(struct __koral_Control)))
```

- 头 24 → **16 B**。
- `dtor` 仍按函数指针存：每个托管类型不同，放侧表或做 vtable 索引是后续优化，不在本期。
- 强弱计数语义不变。

### 3.2 值 / 句柄

托管值、owning 引用、借用，**统一是 `void*`（payload 地址）**。

```c
struct Koralc_Type { void* ptr; };        // 8 B
struct Std_String  { void* ptr; };        // 8 B
```

| 操作 | 以前 | 现在 |
|---|---|---|
| 拷贝 | `dst = src; retain(src.control);` | `dst = src; __koral_retain(__koral_control_of(src.ptr));` |
| 析构 | `release(x.control);` | `__koral_release(__koral_control_of(x.ptr));` |
| 字段访问 | `((Payload*)x.ptr)->f` | 不变 |
| 建对象 | `x.control = malloc(24+sz); x.ptr = x.control + 24;` | `x.ptr = malloc(16+sz);`（payload 在 `ptr`） |

### 3.3 trait object

**采用 Swift 的瘦对象指针约定**：对象句柄一个字，引用计数在 payload 之前的固定偏移处，
派发所需信息由句柄反推。**不采用 Swift 的扁平 existentials 布局**
（`{ 3-word inline buffer | value metadata | witness tables }`）。

```c
struct __koral_TraitRef {
    void* ptr;             // payload 地址
    const void* vtable;    // 静态 vtable 实例
};                          // 16 B（今天 24 B）
```

**为什么不采用扁平布局：**

1. Swift 的扁平 existentials 是为「小值免装箱」服务的 —— 3 字内联缓冲区存得下就存值本身。
   Koral 的 trait object 永远来自一个 **owning 托管引用**（`convertToTraitObject` 走
   `heapOwned`，`ptr == control + 1`），payload 本来就在 `[Control | payload]` 堆块里。
   内联缓冲区里能放下的永远只是那个指针，等于白付 value-metadata 与 value-witness-table 的成本。
2. Koral 的装箱点在**类型层**（`type mutable` / `Drop` / 递归 → Managed），不是在 existential 边界。
   两套装箱机制叠加没有收益。
3. `{ptr, vtable}` 两字已经能表达全部需求；`control` 由 `ptr` 推出，`retain`/`release`/`downgrade` 都能做。

vtable 仍是**每个（trait, 具体类型, 类型实参）一份静态结构体**，成员为函数指针 —— 这一点不变。

### 3.4 弱引用

```c
struct __koral_WeakRef { void* ptr; };   // 1 字，与强句柄同形
```

- 存 payload 地址；`control` 同样由 `ptr` 推出。
- `weak_count` 保证 `[Control | payload]` 整块活到弱引用归零，所以 `ptr` 不悬垂。
- `downgrade(p)` → `weak_retain(control_of(p)); return (WeakRef){p};`
- `upgrade(w)` → CAS `strong_count` 从 `>0` 到 `+1`，成功则返回 `{w.ptr}`。

### 3.5 借用（本设计的关键裁定）

> **方法借用者同样传瘦指针，只是不触发 retain / release。**

```c
// 以前
struct __koral_Ref r = { &local, NULL };
// 现在
void* r = &local;                 // 或 &local 的 payload 地址
```

依据（实测）：

- 形态 A（1,747 处）的 `control` **本来就是 `NULL`**，今天就没有 retain/release。
- 形态 F（209 处）的 `control` 也是 `NULL`。
- 借用的寿命由**栈作用域**保证（局部活过借用），不靠引用计数。
- 类型系统已禁止借用逃逸：不能进 struct 字段、enum payload、返回类型、全局变量、lambda 捕获。

因此借用就是「非拥有的瘦指针」，与 `*unsafe T` 同宽，只是不可解引用到裸内存之外、不可 `free`。

具体形态：

| 场景 | 传什么 | retain/release |
|---|---|---|
| 方法接收者按引用传参 | `void*`（payload 地址） | 无 |
| `Drop.drop(self)` 前奏 | `void* raw_payload` | 无（`payload_drop` 本来就是这个签名） |
| owning 参数 / 返回 | `void*`（payload 地址） | 有 |
| trait 方法接收者 | `void*` | 调用点按 ownership 决定 |

vtable wrapper 相应变成：

```c
static struct Std_String __koral_wrapper_Std_Io_IoError_Error_message(void* self) {
    struct Std_Io_IoError self_val = __koral_Std_Io_IoError_copy((struct Std_Io_IoError*)self);
    ...
}
```
若调用点 ownership 是 copy，则在调用前 `__koral_retain(__koral_control_of(self))`，
wrapper 内 `__koral_release(__koral_control_of(self))` —— 与今天等价，只是 control 现在由 `self` 推出。

### 3.6 静态值 / 字面量

今天字符串字面量是 `{ .ptr = &rodata_storage, .control = NULL }`，零分配。
薄指针下 `retain(p)` 会去读 `p - 16`，所以**不能再用 `control == NULL` 当哨兵**。

方案：**immortal 头**（Swift 的做法）。字面量在 `.rodata` 里前置一个真 `Control`：

```c
static const struct __koral_Control __koral_immortal_42 = {
    .strong_count = -1, .weak_count = -1, .dtor = NULL,
};
static const struct __koral_payload_Std_String __koral_lit_42 = { data, len };
/* 值 = { .ptr = &__koral_lit_42 } */
```

- `retain`/`release` 读到 `strong_count == -1` 直接返回（或依赖原子加对 -1 恒不为 1 的性质）。
- 成本：每个静态字面量多 16 B 常量数据。
- 收益：`control == NULL` 这个「静态 / 非拥有」双重哨兵消失，表示统一。

---

## 4. 收益

| | 基线 | 最终 | 实测 |
|---|---|---|---|
| 句柄宽度 | 16 B | **8 B** | 容器元素、结构体字段全部减半 |
| 堆块头 | 24 B | **8 B** | 两步合计 −515 MB 分配量 |
| `Option[managed]` / `Option[Ref[T]]` | 24 B | **8 B** | niche 布局，无 tag |
| `Option[Int]` 等无 niche | 24 B | **16 B** | tag 布局保留（Int 无空位模式） |
| `TraitRef` | 24 B | **16 B** | |
| `DictBucket[String,Type]` | 40 B | **24 B** | 每张 `Scope` 的 Dict 都受益 |

设计层收益（比字节更重要）：

1. **布局权真正交还编译器。** `docs/document.md` 承诺「`type` 无身份、布局是实现细节」，
   但今天每个值都是 `shared_ptr` 形状，把一个具体内存模型焊进了 ABI。薄下来之后
   `type` 的内联 / 去箱化才有空间。
2. **与主流 ARC/refcount 语言对齐。** Swift / ObjC / Rust `Rc` / Go 指针都是一个字。
   `shared_ptr` 的双字是 C++ 为 aliasing 做的专门妥协，Koral 不需要 aliasing 却承担了成本。
3. **FFI 自然。** 托管值过 C 边界就是一个指针，与 `*unsafe T` 一致。
4. **解锁后续表示优化**：niche `Option`、小字符串 / 小容器、指针打标、vtable 进头。

吞吐收益**不是**理由：`_copy`/`_drop` 辅助函数合计只占 self-time 2.7%，上限 1–3%。
本项按**表示层项目**推进。

---

## 5. 与 Swift 布局的对照

| | Swift | Koral 目标 | 采用？ |
|---|---|---|---|
| 对象句柄 | 1 字（指向 payload） | 1 字 | ✅ |
| 引用计数位置 | 对象头固定负偏移 | `Control` 在 `ptr - 1` | ✅ |
| 静态对象 | immortal refcount | `strong_count = -1` 头 | ✅ |
| weak | 侧表 / 头内 weak 计数 | `Control.weak_count` | ✅ |
| 派发信息 | metadata / isa 在对象头 | **独立 vtable 字在 trait object 上** | ❌ 不采用扁平布局 |
| existentials | 3 字内联缓冲 + value metadata + witness tables | `{ptr, vtable}` 两字 | ❌ 不采用扁平布局 |
| 小值免装箱 | value witness / 内联缓冲 | 不做（装箱在类型层已决定） | ❌ |

---

## 6. 可一并删除的东西

做完薄指针后，下面这些**全部失去存在理由**，应当一并删除，不要留成分支。

### 运行时（`std/koral_runtime.h` / `.c`）

| 目标 | 位置 | 原因 |
|---|---|---|
| `struct __koral_Control.ptr` | `koral_runtime.h:53` | 恒等于 `control + 1` |
| `__koral_ref_drop` | `koral_runtime.h:92` / `.c:77` | 借用不再持有 control |
| `control == NULL` 哨兵约定 | 全局 | 由 immortal 头取代 |
| `downgrade_ref(struct __koral_Ref)` / `upgrade_ref(struct __koral_WeakRef)` | `koral_runtime.h:95-96` | 参数改瘦指针 |
| `struct __koral_Ref` | `koral_runtime.h:14-17` | 值与借用统一为 `void*` |
| `struct __koral_TraitRef.control` | `koral_runtime.h:25-29` | 由 `ptr` 推出 |

### 类型系统（`compiler-reference/Sources/KoralCompiler` + `compiler/koralc`）

> **第 2 步修正**：`Type.borrowedReference` / `mutableBorrowedReference` 与 `assertNoBorrowedReferenceType`
> **不删** —— 类型是「借用」的标记，禁令是「借用不逃逸」的保证，两者都是薄指针方案的一部分。
> 下面只列真正失效的。

| 目标 | 位置 | 原因 |
|---|---|---|
| `ReferenceHandler` 里 borrowed 的 owning 分支 | `Sema/TypeHandler.swift` | 已在第 2 步分出瘦借用分支；残留的 owning 逻辑可清理 |
| `controlExpression` 的 borrowed 分支返回 `NULL` | `CodeGen/CodeGenMIR.swift:2619` | 第 3 步后所有引用都无 control，函数整体可删 |
| `isNonOwningLocalValue` / `borrowedForwardingLocalIDs` 等簿记 | `CodeGen/CodeGenMIR.swift:31 :54 :60 :85 :105 :125 :370-395 :601 :688` | 第 3 步后「是否拥有」只由传参约定决定 |

### MIR / CodeGen

| 目标 | 位置 | 原因 |
|---|---|---|
| `MIRReferenceAllocation`（`stackBorrow` / `heapOwned` / `heapOwnedMove`） | `MIR/MIR.swift:240-244` | 「是否拥有」变成传参约定，不是值的表示 |
| `borrowedForwardingLocalIDs` + `computeBorrowedForwardingLocals` | `CodeGen/CodeGenMIR.swift:31 :54 :60 :85 :105 :125` | 追踪非拥有局部量的整套簿记失效 |
| `isBorrowedParameterType` / `isNonOwningLocalValue` / `isBorrowedReferenceLikeType` | `CodeGen/CodeGenMIR.swift:601 :688 :678` | 同上 |
| `isNonOwningLocalValue` 驱动的 `nonOwning` 局部量集合 | `CodeGen/CodeGenMIR.swift:370-395` | 同上 |
| `emitBorrowedReference` 的 `control` 字 | `CodeGen/CodeGenMIR.swift:1906-1916` | 借用只发 `void*` |
| `emitHeapReference` 的 `Control.ptr` 赋值 | `CodeGen/CodeGenMIR.swift:1715` 等 4 处 | 字段删除 |
| `appendManagedNominalUserDropPrelude` 的 `__koral_self` | `CodeGen/CodeGenTypes.swift:23-33` | 改传 `void* raw_payload` |
| vtable wrapper 的 `struct __koral_Ref self_ref` | `CodeGen/CodeGenVtable.swift:331` | 改 `void* self` |
| `generateTraitObjectConversionABI` 的 `control` 赋值 | `CodeGen/CodeGenVtable.swift:~525` | `TraitRef` 无 control 字 |

### 保留、不删

- `Control.strong_count` / `weak_count` / `dtor` —— ARC 语义需要。
- vtable 静态实例与 `__koral_TraitRef.vtable` —— 动态派发需要。
- `__koral_WeakRef` —— 保持 1 字。
- `type` 值类型的内联布局判定（`nominalLayoutKind`）—— 不受本项影响。

---

## 7. 实施顺序

> 原则：先 Swift 版本，533/533 通过后再同步 bootstrap。不改 Swift 侧迁就 bootstrap。

### 第 1 步 — 删 `Control.ptr`（独立、低风险）

- 头 24 → 16 B，值表示**不变**（仍是 `{ptr, control}`）。
- 改 4 处发射点（`ptr = (char*)control + sizeof(Control)`）为不写 `Control.ptr`，
  2 处消费点（`dtor(control->ptr)`、`upgrade_ref`）改用 `__koral_payload_of(control)`。
- 预期：分配量 −515 MB（全堆 9.4%），行为不变。
- 验证：533/533。

### 第 2 步 — 借用改瘦指针

- `Type.borrowedReference` 等删除；借用 = 非拥有 `void*`。
- 删除第 6 节「类型系统 / MIR / CodeGen」里列的全部簿记。
- 预期：行为不变，代码量下降。
- 验证：533/533。

### 第 3 步 — 托管值 / owning ref 改瘦指针

- 值表示 `{ptr, control}` → `void*`；copy/drop 用 `control_of`。
- `TraitRef` → `{ptr, vtable}`。
- 静态字面量改 immortal 头。
- 预期：句柄减半，`Option[managed]` 24 → 16 B。
- 验证：533/533 + 生成 C 的 `sizeof` 抽查。

### 第 4 步（后续，不在本期）

- niche `Option[T]`（NULL = None）→ `Option[managed]` 8 B。
- 小字符串 / 小容器、指针打标。
- `dtor` 改 vtable 索引（头再省 4 B）。

---

## 8. 风险与未决

| 风险 | 说明 | 对策 |
|---|---|---|
| 析构顺序可观察 | 与 L2 move 优化同一敏感区 | 每步单独跑 533，不叠加未验证改动 |
| 静态字面量体积 | 每个字面量多 16 B 常量 | 实测 bootstrap 字面量数量后评估；必要时按内容去重 |
| `-1` refcount 与原子操作 | `atomic_fetch_add` 对 `-1` 的行为要验证 | 加一个运行时单测；或 `retain`/`release` 首行判 `-1` |
| 自举 | bootstrap 需同步全部改动 | Swift 先行，验证后再同步 |
| 借用逃逸 | 今天靠 13 处禁令保证；类型删除后靠「借用只是 `void*` 局部量/参数」 | 保留「不可返回 / 不可存储」的检查，但检查目标从类型变成传参约定 |

**未决（不阻塞）**

1. `dtor` 是否改成 vtable 索引 —— 头再省 4 B，但每个托管类型多一张表。留到第 4 步之后。
2. 静态字面量是否按内容去重 —— 需要先量字面量数量。
3. `?*Trait`（`TraitWeakRef`，今天 16 B）是否也收到 1 字 —— 需要 vtable 另存，
   与「不用扁平布局」的取向一致但要多一张侧表。留到第 4 步评估。


---

## Bootstrap 同步记录

按「先 Swift，验证后再同步 bootstrap」完成同步。bootstrap 的表示层与 Swift **等价但不逐字一致**：

| | Swift | Bootstrap |
|---|---|---|
| 借用的 C 类型 | `T*`（`ReferenceHandler` 分出瘦借用分支） | `struct __koral_Ref { void* ptr; }`（同一单字 struct，`emit_retain` 对 borrowed 跳过） |
| 静态字符串字面量 | 每次 `malloc`（无静态托管值） | **immortal 头**：`{ struct __koral_Control ctrl; Payload payload; }`，`strong_count = -1` |

两者都满足「借用不 retain/release、control 由 ptr 推出」。immortal 头已在 bootstrap 落地，
Swift 侧将来引入静态托管值时可直接复用（运行时的 `KORAL_IMMORTAL_REFCOUNT` 早退已就位）。

验证：

| | 结果 |
|---|---|
| Swift 宿主编译器 | **533/533**（48.6 s） |
| Bootstrap 编译器 | **532/533**（61.3 s） |

剩余 1 例 `sync_channel_test`：**编译通过、运行时非零退出**（并发用例）。
与表示层改动的关系待查 —— 它在改动前的 bootstrap 基线上是通过的，需要单独定位。

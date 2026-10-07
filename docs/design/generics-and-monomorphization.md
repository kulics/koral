# 泛型与单态化

> **Status**：Implemented
> **范围**：泛型的实例化、模板与实例的身份、类型实参进键
> **用法**见 [`../guide/document.md`](../guide/document.md)「Generic Data Types / Generic Functions /
> Generic Constraints / Generic Methods」；**本文只记为什么**。
> **共同前提**（身份是声明的 `DefId`）见 [`README.md`](README.md)。

## 摘要

泛型走**单态化**：每个具体实例各自生成一份代码，换取零开销抽象。
由此派生出本文的核心问题——**什么是一个「实例」的身份**。裁定是：
声明归声明，实例归实例，两者的键不同；键里只能有身份，不能有名字。

## 背景

单态化把「一个泛型定义」展开成 N 份具体实现。展开后必须回答三件事：

1. 这一份是**哪个声明**的？
2. 它是该声明的**哪一次实例化**？
3. 两个地方写的同一个东西，**算不算同一个**？

答案里若掺进名字（拼写），第 3 问就会出错——同一个声明换个写法就成了两个身份。

## 非目标

- **trait 身份与 witness** → [`traits-and-givens.md`](traits-and-givens.md)。
- **名字怎么解析成声明** → [`name-resolution.md`](name-resolution.md)。
- **泛型语法与约束写法** → [`../guide/document.md`](../guide/document.md)。

## 方案

### 声明表与实例表的键不同（铁律）

出处：[`../implementation/identity-matching-tracking.md`](../implementation/identity-matching-tracking.md) §5.2
（曾走错两轮，206/557 → 531/557 → 557/557）。

> **铁律**：*声明*表按 `MethodOwner` 键；*实例*表按 `MethodInstanceKey`（owner + owner_args）键。
> 把实例表按 owner 键，就是把 `List[String]` 与 `List[Rune]` 塌成一个。

当时的第一诊断是「C 名字改编与注册表键分家」——**错**。改编名一直是对的，是派发选错了方法
（`String` 的 `to_string` 调到 `Rune.to_string`）。所以：**不要碰名字改编；名字在那里是合法用途。**

真正的根因是 `MethodInstanceKey` 只有 `(owner, method_name, method_type_args)` 时，
`List[String].new` 与 `List[Rune].new` 共享同一个键——它们共享模板 `List`，而 `method_type_args` 为空。

`MethodInstanceKey` 的定义（`compiler/koralc/typed/types.koral`）：

```koral
/// Key of one INSTANTIATED method: which declaration, which instantiation of it,
/// which method, and which method-level type arguments.
///
/// The owner is a `MethodOwner` -- a declaration identity -- so two modules'
/// same-named types cannot share a slot. `owner_args` is the owner's
/// INSTANTIATION: `List[String]` and `List[Rune]` share the owner `List` and
/// differ here, exactly as rustc's `Instance` is `(DefId, GenericArgs)` and not
/// `DefId` alone. Method type arguments are kept as `Type`s too, so nothing is
/// folded into a name string.
public type MethodInstanceKey(
    owner MethodOwner,
    owner_args List[Type],
    method_name String,
    method_type_args List[Type],
);
```

`MethodOwner` 二分：`Decl(DefId)` 只用于**有声明的类型**；原始类型 / 引用 / 指针这些无声明者
才落 `Builtin(封闭集)`。—— rustc 的 `inherent_impls` / `incoherent_impls` 二分。

### 类型身份不能依赖声明顺序

出处：记录 §3.2、§7.6、§23.1。

在模板注册**前**构造的 `Type` 携带 invalid `templateDefId`，身份比对会**静默失败**——不是报错，是错判。
所以：

- 任何新的身份键都必须保证「**先注册、后取键**」，或键本身不依赖模板注册时机。
- **类型自带声明**：不得按拼写把模板找回来。三处 `structTemplates[template]` 式的按名查找
  正是塌缩的根因（§7.6）。
- 父 trait 约束（`ParentTraitConstraint`）**构造时不能定身份**——它可能后声明、顺序敏感。
  做法是链接期 `link_parent_trait_def_ids()` 回填，三处收敛到同一答案（§23.1）。
- 不做 `DefId → 名 → DefId` 往返：查不到就铸新 DefId，等于给同一个类型铸**第二个身份**（§15.2）。
  标量 / 集合这类**无声明者**可以铸占位 DefId，名字只作显示（§19.4）。

**循环类型引用**因此可以处理（原文出处：`../implementation/developer-guide.md` FAQ，已迁出）：

`Type` uses `DefId` indexing instead of embedding recursive type payloads directly. Pass 1 registers names and allocates `DefId`, Pass 2 resolves full details and fills `DefIdMap`.

### `owner_args` 之外：实例化两步

出处：`../implementation/developer-guide.md`「Bootstrap Self-Hosting Repair Notes」内的可迁移裁定
（记录段里的设计规则）。

- 泛型实例化是**两步：先替换、再立即具体化嵌套的参数化类型**。少一步会留下未具体化的嵌套。
- **pattern 变量绑定用 place-based**，不要一律物化拷贝：绑定在语义上是引用式载荷时，
  保留被匹配的 place。

### niche 判定读实例化后的 case 列表

出处：记录 §14.2。

布局 / niche 判定必须读**实例化后**的 case 列表，不是模板的。
「查不到 niche」≠「真没有 niche」——`.GenericEnum` 要先解析到实例的布局声明。

### `bound_may_hold` 与 `satisfies_bound` 永不合并

出处：`compiler/koralc/sema/type_checker_visibility.koral`。

```koral
/// Could `subject` still satisfy `b` after type substitution? Distinct from
/// `satisfies_bound` on purpose: materialization decisions need "might
/// become true later", call sites need "is true now". Never merge the two.
```

两问是不同的问题：**物化决策**要「将来可能成立」，**调用点**要「现在成立」。
合并它们会让其中一侧静默出错。

### 新增一个 `Type` 的契约

出处：`../implementation/developer-guide.md`「Adding a New Type」。原文只给了清单：

> Also update: `description`, `stableKey`, `canonical`, `Equatable` implementation

**（下句是本文的推论，原文无此论证）**：这四项对应身份、显示、归一化三个角色，
少一个就会有一处退回按名字比较。

## 替代方案

**替代方案原文未记载。** 下面是从「已否掉的写法」可以反推的，不是当时的取舍记录：

- **实例表按 owner 键**（即忽略 `owner_args`）——走过一轮，把 `List[String]` 与 `List[Rune]`
  塌成一个；有记录的失败数据（206/557），但没记录当初为何那么设计。
- **按名字（拼写）当身份键**——记录 §15.3 说明了危害（「键里多一个名字，永远只能
  「把一个声明拆成几个键」，不可能区分出 DefId 区分不了的东西」），但没记录为何曾考虑它。
- **不单态化（走 trait object / 虚表）** ——无记录。

## 风险与未决

- **为何单态化而不是动态派发**：只有结论（「零开销抽象」），无取舍记录。
- **`bound_may_hold` 的完整判定边界**：注释说明了「为何分开」，未记「何时该用哪一个」的判据表。
- **实例表的完整清单**：记录 §4.2 列出了需要重键的表名（`extension_methods`、
  `conformance_index`、`method_param_specs`…），那是迁移清单，不是设计上的表边界。

## 实施

无单独的实现记录文件。实例表重键的**迁移过程**记在
[`../implementation/identity-matching-tracking.md`](../implementation/identity-matching-tracking.md)
§4–§5（那是带日期的记录，只追加不改写）。

# 方法声明命名空间

> **Status**：Implemented（冲突代数与注册漏斗 2026-11-24 落地；派生索引的写入收拢见实现记录「未尽」）· 2026-11-24 · 对应实现 [`../implementation/method-namespace-implementation.md`](../implementation/method-namespace-implementation.md)

## 摘要

方法声明按**「适用范围 × 出处」一等记录**进单一命名空间（owner → 名字 → 声明记录）。
声明期冲突是**冲突代数**的一行（重叠 = 接收者集合相交；跨种类 scope 同名即冲突，
同 scope 再按 kind 细分），不是散在各注册点的特判；代数保证非工具记录在任一接收者上
至多一条，查找因此与来源顺序无关。

## 背景

一个方法声明要回答四个问题：**谁声明的**（DefId，见共同前提）、**哪些接收者看得见**
（适用范围）、**由谁提供**（出处）、**撞名时谁让位**（冲突）。此前前两个维度隐含在
存储布局里——范围靠"存在实例槽还是通用槽还是模板"表达，出处靠 `inherent_keys` /
`providing_traits` / `tool_type_params` 等标志位表达。后果是每条声明期规则都必须
在每个注册点各写一遍（pass-2 签名、pass-2/3 conformance、工具物化、模板注册），且
判定"两个声明是否作用到同一接收者"要靠 `owner_args` 空满、`type_params` 计数这类
形状启发式反推。历史代价：实例 given 功能的注册点双份（只改一处从另一处泄漏）、
owner 形参计数规则散布六处、`instance_owner_args` 漏判引用包裹的 trait object、
以及为「实例化 given 与泛型 given 禁止重叠」再补的两本名册（2026-11-23）。

把范围与出处提为一等字段后，所有声明期规则共用一个重叠谓词，不再随需求增长补表。

## 非目标

- **不改用户可见语义。** 冲突代数与现行语义逐格一致（含已落地的「禁止重叠」）；
  本设计只重排"规则存在哪里、如何判定"。用户向表述 → [`../guide/document.md`](../guide/document.md)。
- **不动单态化。** 模板注册表继续持有签名/函数体与实例键，实例键含 `owner_args`
  的裁定 → [`generics-and-monomorphization.md`](generics-and-monomorphization.md)。
- **不含方法面（可调性）。** inherent 跟着值走、trait 方法跟着 trait 名走 →
  [`module-design.md`](module-design.md) §3.4；命名空间只在查找出给出记录，
  可调性判定不在本设计内。
- **不含模块级名字撞名矩阵与导入规则** → [`module-design.md`](module-design.md) §3.3、
  [`name-resolution.md`](name-resolution.md)。
- **不含 given 的孤儿/局部性规则与 witness 身份** → [`traits-and-givens.md`](traits-and-givens.md)。

## 方案

### 声明记录的三个维度

```
MethodDeclRecord(
    def_id: DefId,                       // 声明身份（共同前提）
    owner: MethodOwner,                  // 所属类型，按声明身份
    name: String,
    scope: Family | Instance(args),      // 适用范围：整族实例 | 恰好一个实例
    kind:  Inherent | Requirement(trait) | Tool(trait),   // 出处
    …                                  // symbol / 签名 / 函数体来源
)
```

- **scope** 一等化，不再由"存放在哪个注册表"表达。`Family` 覆盖 owner 的全部实例
  （泛型 `given[T] X[T]`；具体类型上的 `given X` 整族即自身）；`Instance(args)`
  恰好一个实例（`given X[Int]`）。
- **kind** 一等化，取代散落的 inherent 标志与 providing-trait 列表。工具物化
  （`given T { … }` 的成员落到实现类型）是 `Tool`，与 `Requirement` 区分。

记录按 `(owner, name)` 归入一个命名空间：

```
MethodNamespace: Dict[MethodOwner, Dict[String, List[MethodDeclRecord]]]
```

### 重叠的定义：接收者集合相交

两个声明**重叠** ⇔ 同 owner 同 name ∧ 接收者集合相交：

```
Instance(x) ∩ Instance(y) = (x == y)
Instance(x) ∩ Family      = true        // Family 覆盖每个实例
Family      ∩ Family      = true
```

这是本设计的修正点：旧模型把"撞名"理解成**同一槽位**（精确实参相等），`Family` 与
`Instance(x)` 因槽位不同被判不相交，于是同名共存、靠遮蔽裁决。按集合相交定义后，
「实例化目标的 `given` 与泛型 `given` 不能声明同名方法」不是特例，就是重叠定义的
直接后果——同一实例上出现了第二个定义。

### 冲突代数

scope 不相交则一律合法（不相交实例可同名）。scope 相交时分两层：

**跨种类 scope（`Instance(x) × Family`）：双方非 Tool 的同名一律
`Duplicate definition: <name>`，不细分 kind。** 这就是「实例化目标的 `given`
与泛型 `given` 不能声明同名方法」（2026-11-23 落地）——重叠规则刻意只看名字，
不引入 kind 级裁决。

**同一 scope 内部的相交**（同实例两声明、`Family` 两声明）按 kind 细分：

|  | `Inherent` | `Requirement(T)` | `Tool(T)` |
|---|---|---|---|
| **`Inherent`** | `Duplicate definition: <name>` | `Duplicate definition: <name>`（任何声明顺序） | 合法：Inherent 胜，工具不占名 |
| **`Requirement(T)`** | — | 同 trait 双实现先被 conformance 冲突拒（"Conflicting conformance"）；异 trait 同名到同一范围 = 现行 ambiguous 诊断（文案保留） | 合法：要求胜，工具让位（现状：tool never owns） |
| **`Tool(T)`** | — | — | 合法：共存，可调性由方法面决定（§3.4） |

- 诊断文案与现行逐字一致：`Duplicate definition: <name>`、`Ambiguous method '<n>'
  for type '<T>' via trait extensions`、`Conflicting conformance: …`。
- 工具块（`given T { … }`）在两层里都不占名：跨种类 scope 与同 scope 的
  `Tool` 行都放行，可调性交方法面（§3.4）。

### 注册漏斗与派生索引

唯一入口 `register_method_decl(record)`：先做冲突代数判定（返回精确冲突类型），
再把记录写入命名空间，最后写**派生索引**——实例槽、通用槽、模板条目只是漏斗留下的
查询缓存，供查找与单态化走熟路。所有现存注册点（pass-2 签名、pass-2/3 conformance、
工具物化、模板注册）改为调漏斗，不再自带查重；同块两个成员、跨块同实例、跨种类
重叠都是同一个重叠谓词，`seen_names` 一类的块内特判随之消失。

### 查找是全序

接收者 r 上取 `r ∈ scope` 的记录：`Instance` 先于 `Family`（更具体者优先——仅在
工具记录共存时才实际裁决），kind 优先级 `Inherent > Requirement > Tool`；`Tool`
与 `Requirement` 的可调性另由方法面门（§3.4）过滤。代数保证非工具记录至多一条，
**查找不需要"谁先注册"参与裁决**——现行的注册顺序竞态（inherent 标志先到先得）消失。

## 替代方案

**A. 维持按注册路径分储，每来一个需求补一本表。** **否掉。** 语义维度藏在布局里，
每条声明期规则要在全部注册点各写一遍，改一处漏一处的事故反复发生（见「背景」）；
补表的边际成本不收敛——名册、`inherent_keys`、`method_sources` 都是同一维度的碎片。

**B. 不新增状态，从现有注册表反推（`owner_args` 空满 + `type_params` 计数判来源）。**
**否掉。** 反推形状启发式区分不了工具物化与泛型 given 的 conformance 成员（字段
形态几乎相同，而两者在代数里取值相反），且依赖"工具物化晚于签名 pass"这类检查
外部的时序不变量——将来谁改注册时机就静默漏报或误报。形状启发式正是
`instance_owner_args` 引用包裹误判一类事故的来源。

**C. 单一声明注册表 + 冲突代数（本设计）。** 采纳。状态总量反而下降：命名空间
吃掉实例槽的语义职责、`inherent_keys`、两本名册与 `method_sources` 的一部分。

## 风险与未决

- **双编译器镜像。** 两侧同批改，差分预言机（行为 + 诊断逐字比对）是迁移的安全网；
  逐格保真的重点是 `Requirement × Requirement` 行与工具让位行，以现有测试钉住。
- **未决：`given Box`（未实例化泛型类型的 given）的归属。** 实证（2026-11-23）其
  方法在具体与泛型上下文均不可见（死声明）。选项：拒绝该形态（与
  `given[E] Box[Int]` 的特化拒绝同族）或按 `Family` 记入并参与冲突代数。
  2026-11-23 的修复取窄口径：不参与（不入册）。重构时须先裁此项。
- **未决：工具让位是否改为显式一行。** 现状 tool never owns the name（后注册的
  inherent/要求覆盖工具副本）；代数已把它表达为合法行，是否再区分"先来后到"待议。

## 实施

2026-11-24 落地（独立一笔）：`MethodDeclRecord` / 命名空间 / 注册漏斗进两个编译器，
散布查重迁入冲突代数，两本临时名册收编删除。施工对照表、角落统一清单与保真核对见
[`../implementation/method-namespace-implementation.md`](../implementation/method-namespace-implementation.md)；
派生索引的写入点收拢与 `inherent_keys` 等字段吸收留在后续（实现记录「未尽」）。

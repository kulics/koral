# 名字解析与身份边界

> **Status**：Implemented
> **范围**：符号键、解析顺序、名字→身份的唯一边界、可见性默认值、C 标识符唯一性
> **用法**见 [`../guide/document.md`](../guide/document.md)「Modules and Visibility / Resolution」；
> **本文只记为什么**。
> **模块与包的设计**（命名、语法、manifest）见 [`module-design.md`](module-design.md)——
> 那是正本，本文不重复。
> **共同前提**见 [`README.md`](README.md)。

## 摘要

名字解析是**唯一**把拼写变成身份的地方，而且只发生一次。解析顺序有四层，裸名在最后
且**不算解析**。解析完成后，任何地方都不许再退回名字比较。

## 背景

编译器里到处要回答「这是不是同一个东西」。两种做法：

- 解析完就比身份（`DefId`）——一处可能出错，之后全对
- 各处都留一道按名字的兜底——每处都可能出错，而且**静默**出错

Koral 选前者，并把「不留兜底」写成硬性约束。

## 非目标

- **模块与包的命名、manifest、文件合并** → [`module-design.md`](module-design.md)。
- **导入语句的写法** → [`../guide/document.md`](../guide/document.md)。
- **trait / 泛型的身份键** → [`traits-and-givens.md`](traits-and-givens.md)、
  [`generics-and-monomorphization.md`](generics-and-monomorphization.md)。

## 方案

### 作用域符号是 `(module, name)`

出处：[`../implementation/identity-matching-tracking.md`](../implementation/identity-matching-tracking.md) §3.1。

模块级符号的键是 **`(module, name)`**，不是裸名。否则两个模块里的同名 `type Plain`
会塌进一个符号槽。

### 解析顺序四层，裸名不是解析

出处：记录 §17.2、§17.3、§18.2。

> 解析顺序 = **本模块声明 → 符号导入 → 批量/模块导入 → 裸名**。

- 裸名排在最后，而且**不是解析**：它只服务「Import it explicitly」这条诊断。
  rustc_resolve 里没有全局名表。
- 导入图是**共享环境状态**，不是每个 `DefIdMap` 各一份；import 边带 `sourceFile`，匹配必须比文件。
- 裸名回退会把「此处没声明也没导入」与「导入了 mod_a 的同名符号」混成一件事（§18.2）——
  所以必须插一层 import，而不是在查不到时退回裸名。

候选键的优先级实现见 `compiler/koralc/mono/generic_template_registry.koral`（1→4，裸名最后）。

### 名字 → 身份只有一个边界

出处：记录 §21.1、§21.5。

- 名字必须在**边界处**变成身份：`resolve_type_node_identity`（形状解析，不做实例化）。
  之后的匹配器吃 `Type`、比 DefId。
- **为什么不给 `TypeNode` 加 `DefId` 字段**：`TypeNode` 是语法，解析期没有 scope；
  身份是 sema 产出的 `Type` 的职责。把身份塞进语法节点，会在错误的阶段分配它。

### 禁止「查不到就退名字」

出处：记录 §1、§15.1、§19.2、§24.2。这是**硬性约束**，一直在生效。

> **不要用名字来兜底** —— 身份判定失败时不得退回名字比较。（记录 §1 硬性约束原文）

- **无效 `DefId` 是错误态**，名字找不回来。留名字兜底「教坏后来人」（§15.1）。
- **`Type.==` 的名字兜底是恒真式**（左比左），修好也不该恢复名字比较，改成比身份（§19.2）。
- **身份键里不许出现名字**：键里多一个名字永远只能把一个声明拆成几个键（§15.3）。
- **`DefId` 不稠密**，禁止当数组下标索引（§1）。
- 「字符串当键」本身无罪——**键由谁决定才是问题**。键里带声明即可（§24.3）。

**唯一合法的名字出口**：

| 用途 | 为什么合法 |
|---|---|
| 解析边界（拼写 → 声明） | 只发生一次，见上 |
| 显示 / 诊断 | 用户要读 |
| C 改编（mangling） | 目标语言要合法标识符 |
| `Builtin` 封闭集 | 无声明者，名字即槽位 |

出处：记录 §5.4、§7.8。`primitive_extension_template_name` **保留**——标量没有声明，
身份就是封闭集槽位（rustc `SimplifyType` / `incoherent_impls`），不是身份意义上的名字匹配（§19.4）。

### 名字比较必须同层

出处：记录 §10。

做名字（C 名）比较时，**两侧必须处于同一层**。`ownerDefId` 解析到模板，而 C 名是实例化层——
跨层比名字会误判。

### 类型参数 shadow 同名全局

出处：`compiler/koralc/sema/scope.koral`、`compiler/koralc/sema/type_checker_resolution.koral`。

```koral
// A type parameter shadows any same-named module-level declaration
```

类型参数是**词法 binder**：`define_generic_param` / `define_generic_binding` 把它登记成
binder 并遮蔽同名模块级类型；`define_type` **不能**遮蔽它。否则用户写的 `type T`
会劫持 std 里 `[T ...]` 的 `T`。记录 §4.2。

原文出处：`../implementation/developer-guide.md` FAQ（已迁出）。

Use `UnifiedScope.defineGenericParameter()` to register generic parameters. Lookup prioritizes generic parameters over ordinary names.

### 可见性默认值

原文出处：`../implementation/developer-guide.md`「Access Control Defaults」（已迁出）。

| Declaration | Default Access |
|-------------|----------------|
| global `let`/variable, function, type, trait | `module_private` |
| struct field | `public` |
| trait method | `public` |
| given method | `module_private` |
| enum case & case fields | no per-item modifier; visible with the enum type |
| using declaration | file-local (imported bindings are not re-exported) |

> **这张表在 `../guide/document.md` / `document-zh.md` 的「Default Access Levels」里各有一份
> 用户向镜像。改任何一行要三处同批改。**

> **依据原文未记载**——只有这张表，没有记录为什么是这些默认值。

### 模块选择必须 manifest 驱动

出处：`../implementation/developer-guide.md`「Module System Development」第 4 步（那里保留为一行工作提醒，本条是正本）。

- Keep module selection manifest-driven; do not reintroduce directory-inferred module trees.

符号表不得依赖发现顺序（`using` 的先后）；`loaded_modules` 按模块路径排序。
出处：`compiler/koralc/module/module_info.koral`。

### C 标识符唯一性

出处：`../implementation/developer-guide.md` FAQ（已迁出）。

Use `DefIdMap.uniqueCIdentifier(for:)` or `CIdentifierUtils.generateCIdentifier()` to handle module path, private symbol file isolation, C keyword escaping, and collision resolution.

**四个要素缺一不可**：模块路径、private 符号的文件隔离、C 关键字转义、碰撞消解。
private 符号的文件作用域不得遮蔽同级（`compiler-reference/.../DefId.swift`）。

## 替代方案

**替代方案原文未记载。** 可反推但无取舍记录：

- **多层名字兜底链**（「DefId 查不到就退名字」）——走过，被硬性约束禁止；记录说明了危害，
  没记录当初为何那么设计（§24.2）。
- **给 `TypeNode` 加 `DefId` 字段**——记录 §21.5 说明了为何否掉（解析期无 scope）。
- **裸名解析**（全局名表）——rustc_resolve 没有，注释提到这一点，但没记录 Koral 是否考虑过。
- **目录推断模块树**——只说「不要重新引入」，没记录为何否掉。

## 风险与未决

- **可见性默认值的依据**：只有表，无论证（见上）。
- **`path_segments` 为何仍是名字限定**：`compiler/koralc/module/package_manifest.koral` 的注释
  指向 [`module-design.md`](module-design.md)「风险与未决」第 4 条（codegen 标识符映射），
  那条记录说基准应是 `(source, 子路径)` 而非本地源码名，**且仍是开放项**。
  （注：旧注释写「§10.4」，指该节第 4 条，不是小节号。）
- **名字匹配保留处的完整边界**：记录 §7.8 有迁移期的清点表（`lookupGenericStructTemplate`、
  `MethodOwner.Builtin` 封闭集、`stdStringDefId` 等 lang item、`generateCIdentifier` 等），但那是
  **逐处打注释的清点结果**，不是设计上的边界定义——「哪几处可以合法读名字」本身没有正面论证。

## 实施

无单独的实现记录文件。名字键改身份键、清掉名字兜底的**迁移过程**记在
[`../implementation/identity-matching-tracking.md`](../implementation/identity-matching-tracking.md)
§15–§24（带日期的记录，只追加不改写）。

# 简化类型系统迁移状态

日期：2026-09-25（重写整理版）

本文档是简化类型系统迁移的**总结文档**，只保留当前仍有指导价值的信息。历史逐日进展与已修复问题的根因分析见 git 历史。

## 基本规则

- 迁移顺序：Swift `compiler/`、`std/`、测试 → runner、samples、toolchain → bootstrap 对齐 Swift。
- 不保留兼容垫片：旧托管引用表层语法、旧 receiver 适配、COW、逃逸分析提升路径一律删除。
- **不使用名称回退 / 启发式兜底**：身份判定一律用 DefId。字符串只作索引键（Swift 亦如此），不作身份。
- 不修改 Swift 侧来迁就 bootstrap；Swift 是行为基线。
- 阶段状态、验证结果和剩余阻塞以本文档为准。

## 设计约束（已确认）

- 移除托管引用表层：`*T`、`*mutable T`、`?*T`、托管 `&` / `&mutable`、`box()`、托管解引用。
- 保留 raw pointer：`*unsafe T`、`*unsafe mutable T`、`&unsafe`、`&unsafe mutable` 及其解引用。
- 声明处可变性：`type A` / `type mutable B`；枚举和类型别名不能声明为 `type mutable`。
- receiver 只保留 `self`；trait object 表层直接写 trait 名。
- 弱引用表层为 `?T`，类型参数约束显式写 `mutable`；公开入口只有 `downgrade` / `upgrade`。
- 删除目标已完成：`Deref`、ref blanket conformance、逃逸分析、托管引用分配提升、`Weak`、`Object`、COW uniqueness。
- 容器与有状态迭代器为共享语义 `type mutable` 对象；需要独立副本时显式 `clone()`。
- `Drop` 签名只接受 `drop(self) Void`。

## 布局判定结论（关键）

- `self` 按拷贝传递；ARC / 隐藏间接层由类型布局分析决定，与 method call receiver 适配无关。
- `type mutable` 恒为 managed（共享对象语义）。
- plain `type` 只暴露值语义；底层是 inline value 还是 managed wrapper 由编译器按语义属性决定，已确认的触发条件：
  - 值递归
  - 显式 `Drop` conformance
- managed nominal 的 copy 必须对嵌套 managed 字段逐个 retain，与外层 control block 的 retain 配套；否则参数 drop 会造成 use-after-free。

## 当前状态

| 项 | 值 |
|---|---|
| Swift 全量 | **528/528**（2026-09-26 复验） |
| Bootstrap 全量 | **528/528**（2026-09-26 复验） |
| 临时调试代码 | **已全部清除**（`KORAL_DEBUG_SUBST_CONTEXT` 系列探针、`trace_*` 辅助函数、`[inflate]`/`[tool-*]`/`[mono-*]` 等打印均已删除） |
| 自举（bootstrap 编译自身） | **非目标**，当前不通。见下「自举（非目标）」 |
| Swift 构建 | `cd compiler && swift build` |
| Bootstrap 构建 | `compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap` |
| 快速自检 | `compiler/.build/debug/koralc check --package-config bootstrap/koral.json --target-module koralc`（约 5 秒，只做语法/语义，可用来快速试错） |
| 测试 | `./bin/compiler-test-runner/compiler_runner --compiler swift \| bootstrap [--bootstrap-koralc bin/bootstrap/koralc] -j=8` |
| 单例 | `... --filter <name>` |

迁移起点基线：510/528。**2026-09-25 傍晚从 193 提到 503。**

**2026-09-26：193 → 528/528，Swift / Bootstrap 全量均绿（自举为非目标，未打通）。**

### 2026-09-26 根因修复（均已对照 Swift 的结构与逻辑）

1. **物化出的 trait-tool 模板缺类型参数**（`filter` 调用被发出但无定义）。
   `materialize_trait_tool_members_for_conformance` 用 `trait_bindings.contains_key` 过滤掉 conformance 自己的类型参数——`given[T Any] ListIterator[T] as Iterator[T]` 里 `T` 与 `Iterator[T]` 的 `T` 同名，于是模板 `type_params` 变成 0 个，而 receiver `ListIterator[Int]` 还带 1 个实参，下游每个元数检查都拒掉它。
   Swift 把两个角色分开：**作用域**里 `defineType(traitParam.name, traitArgTypes[index])` 会覆盖同名外层参数（等价于过滤），**模板注册**用 `typeParams: typeParams` 完整列表。已拆成 `type_params`（作用域）与 `declared_type_params`（模板元数）两个参数。
   同时撤掉为此加过的两处 `not is_empty and` 元数放宽——那是掩盖根因。

2. **二次替换导致类型自我捕获**（`List[Pair[UInt, T]]` 膨胀成 `List[Pair[UInt, Pair[UInt, Pair[UInt, T]]]]`）。
   `resolve_static_method_signature_for_receiver` 已把 receiver 实参替换进签名，调用点又用 `apply_static_method_type_bindings` 替换一次；`List` 的参数叫 `T` 而实参 `Pair[UInt, T]` 含外层 `T`，第二遍捕获自己。
   Swift 的 `resolveGenericExtensionMethod`（`TypeCheckerMethods.swift:562-610`）**只替换一次**，调用方直接用返回类型。已改为：三条 lookup 路径都返回已替换签名（`lookup_method_signature` 那条补 `bind_static_declaration_signature`），返回类型只再推断**方法自身**的类型参数（`resolve_static_method_param_bindings`）。

3. **`Type(Trait).method(...)` 被解析成「构造调用 + 成员访问」**（`trait_entity_*` 整簇 + object-safety 误报）。
   Swift 在 postfix 位置优先尝试 trait 限定（`ParserExpressions.swift:734-738`）：`Type(Trait)` → `traitQualificationExpression`，其次才是 postfix cast，最后才是普通调用。bootstrap 的 `try_parse_postfix_cast_suffix` 抢先把它当成 `Num as Tag` 强转。
   已按 Swift 的顺序在 `parse_postfix_suffixes` 里插入限定判定。同时 `QualifiedMethodCall` / `QualifiedGenericMethodCall` 对**具体类型** receiver 走 `check_static_method_call_ref` 直达实现（Swift 的 `.staticMethodCall` 分支），只有泛型参数 receiver 才走 vtable。
   object-safety 仍按 Swift 在**裸 trait 名当类型用**时检查（`TypeCheckerTypeResolution.swift:295`），不能去掉——`trait_object_safety_error` 依赖它。

4. **约束强制点**（`sum`/`product`/`average`/`copy_all_to` 全无）。
   Swift 只在**调用点** `enforceGenericConstraints`；物化期是声明活动，不报。已引入 `constraint_enforcement_deferred`：物化 tool body 时抑制约束诊断，调用点正常强制（`borrow_ptr_non_pod_error` 因此恢复）。

5. **`capture_place` / `lower_place` 的 name-keyed 查表排在 DefId-keyed 之前**（`for_loop_nested` + `time_of_day_basic` 同一簇）。
   `let c` 被路由到同名 pattern 绑定的 place。已改为 DefId 优先，name 表只做无 DefId 时的兜底。

6. **方法自身带类型参数时，具体 target 两条路径都不留 body**（`copy_all_to[W Writer]`）。
   `should_store_concrete_given_body` 用 `should_retain_template_body` 当闸，而模板分支只对泛型 target 开——`copy_all_to[W Writer]` 在具体 `ByteBuffer` 上两头落空，签名仍含 `W` 被 `should_lower_function` 丢弃。
   已把模板分支的闸改成 `should_retain_template_body`，两条路径互斥。

7. **`trait_tool_type_params_satisfied` 的判定**见下「剩余阻塞」——这是当前唯一未收口的点。

### 自举（非目标）

**测试口径已达标：Swift 与 Bootstrap 均 528/528。自举不作为验收条件。**

当前 `bin/bootstrap/koralc` 编译不了 `bootstrap/koralc/`，卡在 **C 编译期**（sema/mono 已能生成 133MB 的 `koralc.c`）：

```
passing 'struct List_Koralc_Type_d251' to parameter of incompatible type 'struct List_Koralc_TypedExpr_d251'   (17 处同形)
```

17 处是同一形态：`infer_extension_method_type_args(..., args, ...)` 的第 6 个实参 `args List[TypedExpr]` 被编译成了 `base_type` 的 `GenericEnum.args` 字段（`List[Type]`）。
根源是 `enqueue_extension_method_for_static_call` 里 `when base_type in { .GenericEnum(_, _, args) then ... }` 的 pattern 变量 `args` 遮蔽了同名函数参数 `args`，而**隐式成员解析把这个裸 `args` 解析成了 scrutinee 的字段**——即隐式成员作用域从 `when` 臂里漏了出去。与本轮修掉的 `capture_place` name-keyed 泄漏同族，但在 sema 层。

另有一处相关：`sum`/`product`/`average` 会被强制实例化到 `DictIterator[String, X]`（元素 `Pair[String, X]` 无 `Zero`/`One`），body 里的 `T.zero()` 解析不出。全仓无 `.sum()` 调用点，属强制实例化；触发链已排除 `maybe_record_extension_method_instantiation` / `enqueue_extension_method_for_static_call` / `resolve_concrete_method_call` / `instantiate_conformance_trait_method_for_type`。
Swift 的 `buildTraitToolMethodInfo` 只在 trait 实参是**裸泛型参数**时才把 tool 约束合并进绑定（`guard case .genericParameter ... else { continue }`），据此区分「可派发」与「不可派发」；但该规则会误伤 `into_list`（`given[T Any]`）与 `neq`，需配合「约束仅为 `Any` 则恒可用」一起实现。**本轮未收口。**

### 本轮失败的形态（高度集中）

335 个失败用例的 `build_stderr.txt` **内容几乎完全相同**（约 73 行），全部来自 `std/iterator.koral` 在 trait-tool 物化期重检查 tool body 时的报错。也就是说：**这不是 335 个独立问题，是一处 std 编译失败把所有链接 std 的用例一起带下水。**

典型报错：

```
iterator.koral:475: Type mismatch: expected Option[Pair[UInt, T]], got Option[Pair[UInt, Pair[UInt, T]]]
iterator.koral:685: Type mismatch: expected Set[Pair[UInt, T]],   got Set[Pair[UInt, Pair[UInt, T]]]
iterator.koral:437: Type mismatch: expected Pair[UInt, Pair[UInt, T]], got Pair[UInt, T]
```

`Pair[UInt, T]` 只出现在 `EnumerateIterator[T, R] as Iterator[Pair[UInt, T]]`，`Pair[A, B]` 只出现在 `ZipIterator`。所以膨胀严格限定在**把 tool 方法物化到「trait 参数被映射成含同名参数的复合类型」的 conformance 上**。

---

## 核心架构结论：身份必须用 DefId

### 问题形态

模板 / 派发记录里**没有声明身份**，匹配只能退回名字，由此派生出全部症状：

| 记录 | 迁移前 | Swift |
|---|---|---|
| `GenericExtensionMethodTemplate` | 只有 `conformance_trait_name Option[String]` | `conformanceTraitName` **+ `conformanceTraitDefId: DefId?`** |
| `ReceiverMethodDispatchInfo` | 只有 `conformance_trait_name Option[String]` | `methodDefId` **+ `conformanceTraitDefId`** |
| `TraitInfo`（sema 注册表） | 只有 `name String` | `TraitDeclInfo` 有 `defId` |

**重要澄清**：Swift 的模板注册表也仍以 `[String: ...]` 为索引（只有 `receiverMethodDispatch` 是 `[DefId: ...]`）。所以「索引用字符串」不是问题本身；**分歧在于身份判定**必须用 DefId，而不是名字比较、后缀猜测或完整度启发式。

### 更深一层：方法声明身份两边都没有

比注册表键更根本的缺口是 —— **方法这一级没有声明身份**：

| | 字段 |
|---|---|
| Swift `MethodDeclaration`（`AST.swift:293`） | `name` / `typeParameters` / `parameters` / `returnType` / `body` / `access` —— **无 DefId** |
| bootstrap `GivenMember`（原状） | `name` / `type_params` / `access` / `params` / `return_type` / `body` —— **无 DefId** |

而物化时两边都**新铸** DefId（Swift `makeGlobalSymbol`、bootstrap `allocate_unindexed_def_id`）。结果是「同一个方法的两次到达」和「两个同名的不同方法」在数据上**无法区分**。

Swift 用 `extensionMethodTraitSources[typeName][methodName] = [traitName]` 以 **trait 名**近似这个判据 —— 对 `comparable` 这类"一个方法经多条 trait 路径到达"仍然分不开（多个 trait 名），对跨模块同名 trait 也会撞。这就是「两边都没走完整 DefId 路线」的具体含义。

**由此解释的症状**：Pass2/Pass3 槽位键分裂、`filter` 有调用无定义、改键导致 IO 回归、`ends_with(".Drop")` 猜测、`select_extension_method` 按完整度排序、四条 sync/backfill 路径、MIR 层 body 重检查、以及 `comparable`/`trait_same_name_method_conflict` 的取舍。

---

## 已解决

### 1. 所有权 / move 语义（`HeapOwnedMove`）

- `MIRReferenceAllocation` 补 `HeapOwnedMove()`，与 `MIR.swift:241-245` 三值对齐。
- `emit_heap_reference` 的 ownership 决策改由**显式信号**驱动；删除 `can_transfer_owned_heap_reference` 猜测。
- `consume_moved_source` 的 `.Ref` 分支按 Swift `consumeMovedSource` 实现（原为 no-op 桩）。
- `lower_return` 的 referenceExpression → `HeapOwnedMove`（Swift `MIRLowerer.swift:1103` 此处**无条件** move）。
- `lower_trait_object_conversion` 补 Swift 880–886 的 RefExpr 分支并携带 ownership 信号。

### 2. `emit_drop` 缺失的 root-local invalidation（`pair_destructuring_drop` 真正根因）

ASan 定位：`heap-use-after-free` in `__koral_release`，发生在 case4 —— 逐字段显式 drop 之后容器在 scope end **再次被 drop**。

Swift `emitDrop` 在 drop 子 place 后执行 `setInitFlag(rootLocal, to: false)`，bootstrap 缺失。补齐后 `pair_destructuring_drop` 通过（原先 SIGSEGV）。

### 3. subscript 写回（`subscript_test` 真正根因）

- `lower_place` 的 `.MemberPath` 在 base 无 place（如 `__index_get(pairs, 0)` 返回值）时回退到**已存在但未接入**的 `lower_materialized_member_path_place`，对齐 Swift `lowerPlace`。
- `lower_assignment` 不再把 `None` 静默丢弃，改为 `report_lowering_error`。

### 4. 逃逸分析 / 旧托管引用死机制

- `mir_lowerer.koral` **2460 → 918 行**：整体移除 `MIRReferenceAllocationPromoter`、`MIRReferenceAllocationFunctionPromoter` 与全部逃逸分析 helper。已确认零外部引用。
- 删除 6 个死 intrinsic：`IsUniqueMutable`、`RefCount`、`MakeRef`、`MakeMutRef`、`DowngradeMutRef`、`UpgradeMutRef` 及 snake_case 名称匹配入口，覆盖 13 个文件；同时删除只服务于它们的 4 个孤儿 helper。
- `DowngradeRef` / `UpgradeRef`（现行 weak API）全链路保留。

### 5. DefId 身份模型（结构对齐 Swift）

- 补 DefId 字段：`GenericExtensionMethodTemplate.conformance_trait_def_id`、`ReceiverMethodDispatchInfo.conformance_trait_def_id`、`TraitInfo.def_id`。
- **21 个构造点全部穿透**。名字→DefId 只在注册边界解析一次（`trait_def_id_of`），与 Swift 的 `visibleTraitInfo(name)?.defId` 同一模式。
- `same_extension_template_slot` 改为比较 `conformance_trait_def_id`。
- 新增 `is_std_drop_trait_def_id`，严格照抄 Swift `CodeGen.isStdDropTraitDefId`（核心是 `traitInfo.def_id == traitDefId`，同名不同声明会被拒）；4 处 Drop 判定从名字比较改为 DefId 比较。

### 6. 删除字符串匹配（部分）

- `resolve_trait_name` / `resolve_struct_name` / `resolve_enum_name` / `resolve_function_name` 的后缀扫描循环（4 处）已删，改为精确键查找。
- `lookup_extension_methods` / `lookup_extension_method` 的后缀扫描已删。
- `select_extension_method` 三级启发式降为 Swift 的两级（有 `checkedBody` 优先，否则取第一个）。
- `lookup_extension_methods_fuzzy` 的 `trait_name_matches` 后缀合并改为按 `conformance_trait_def_id` 匹配。

### 7. trait tool 声明不再进 extension_methods（对齐 Swift）

Swift 对 `given Trait { ... }` 在 `collectGivenSignatures` 收进 `traitToolBlocks` 后**立即 return**（`TypeCheckerPasses.swift:1249`），**不**注册进 `genericExtensionMethods`；工具方法只在 **conformance 时** materialize 并打上 `conformanceTraitDefId`（`TypeCheckerPasses.swift:3297`）。

bootstrap 原先在声明时就注册，再靠 4 条 sync/backfill 路径搬运。现已按 Swift 在 `check_given_members_for_type` 用 `is_trait_tool_declaration` 挡住注册。

### 8. mono 不动点

把「resolve 全部节点」与「drain 队列」包进以 `processed_request_keys.count` 增长为条件的循环（对齐 `Monomorphizer.swift:652-671`）。结构正确、行为中性。

### 9. C 类型依赖规则（#4）

`record_dependencies_from_type` 补上 Swift `requiresCompleteNominalDefinition` 的跳过规则：managed nominal 不产生依赖边。结构性消除 `List_Koralc_Token` / `Koralc_Token` 一类排序簇。

### 10. `type mutable` 收敛（#5）

`MIRBlockID` / `MIRLocalID` / `MIRScopeID` / `TemplateField` / `TemplateParam` 改为 plain `type`（5 个，均无 mutable 字段）。`Koralc_MIRScopeID.tag` 误发射消失。

### 11. trait tool 链路对齐 Swift（B）

严格照抄 `TypeCheckerPasses.swift:3297` 的 materialize 循环：

- **父 trait 工具纳入**（原 `source_trait_name <> trait_name` 会丢弃继承的工具；Swift 的 `flattenedTraitToolMethodEntries` 递归 `superTraits`）
- 按名排序（确定性物化顺序）
- own-requirement 与显式实现两条让位规则
- `given Trait { }` 声明期不再注册进 `extension_methods`（对齐 Swift `collectGivenSignatures` 的 early return）

**删除 4 条 compensating sync 路径**（Swift 无对应物，它们只因工具方法被提前注册才存在）：
`sync_trait_tool_template_key`、`register_trait_tool_templates_for_concrete_type`、`backfill_trait_tool_method_to_existing_conformances`、`backfill_checked_trait_tool_method_to_existing_conformances`。

`type_checker_templates.koral` **1463 → 1032 行**。

### 12. 方法声明身份（DefId）—— 结构已补齐

这是此前**两边都缺**的一维：`GivenMember` / `MethodDeclaration` 只有名字，没有声明身份。

已加：
- `GivenMember.def_id DefId`、`MethodDeclaration.def_id DefId`
- **收集期一次分配**（`register_trait_tool_block` 为每个工具方法分配并存入 `trait_tool_blocks`）
- **物化时沿用**（`check_given_members_for_type` 优先用 `m.def_id`，不再每次新铸）
- `copy_method_declaration` 保留身份
- `method_table` 歧义判定改为按**方法自身 DefId**

正确的判定形式已就位：

```
同一声明、多次到达  → 同一 DefId → 覆盖
两个声明、同名      → 两个 DefId → 歧义
```

---

## 本轮修复与根因（2026-09-25 下午）

### 已修 3 处

**1. `materialize_trait_tool_members_for_conformance` 缺 bounds 安装**

Swift `buildTraitToolMethodInfo`（`TypeCheckerPasses.swift:3059-3084`，body 路径 `3354-3380` 再来一遍）做两件事：

- `recordGenericTraitBounds(typeParams)` —— conformance 自己的类型参数界
- 把 tool block 的类型参数界 **merge 到 trait 参数所映射到的那个参数名**上

bootstrap 这里 `owner_type_params` **恒为空**：`trait_tool_source_trait_bindings` 把**所有** owner 参数名塞进 `trait_bindings`，回过头又按 `trait_bindings` 过滤，一个不剩。于是 `register_generic_constraints([])`，重检查 tool body 时 `T` 完全无界，报 `Type T does not explicitly implement trait Hash (checking constraint T: Hash)`。

已补 `install_conformance_and_tool_bounds`（conformance 界 + tool 界 merge + snapshot/restore）。

**2. `Any` / `mutable` 被当成真 trait 声明**

Swift `SemaUtils.isBuiltinTrait` = `name == "Any" || name == "mutable"`，`flattenedTraitMethodsHelper` 对 builtin **返回空方法集**。bootstrap 两个 flatten 路径（`TraitRegistry.flatten_methods_in_module`、`flattened_trait_tool_methods_in_trait`）报 `Undefined trait: Any` / `Trait 'Any' not found`，一次编译刷出 360 条。

已补 `is_builtin_trait`（`typed/types.koral`），两处 flatten 对 builtin 返回空集。**报错从 436 行降到 76 行**。

**3. 类型替换被套用两次（静态路径）**

Swift `resolveGenericExtensionMethod`（`TypeCheckerMethods.swift:581-610`）：把 substitution 图作用在**声明形态**的签名上，**只作用一次**。

bootstrap 的 `resolve_static_extension_template_signature`（`type_checker_methods.koral`）先把 bindings 套在 `template.checked_return_type` 上返回**已实例化** symbol，`resolve_static_method_return_type_for_call` 再套一次。trace 证据：

```
[subst] method=new raw=List[Pair[UInt, T]] out=List[Pair[UInt, Pair[UInt, T]]] bindings=[T=Pair[UInt, T]]
```

绑定 `T = Pair[UInt, T]` 的**右侧仍含 `T`**，所以任何二次套用都会膨胀。已改成声明形态 + 单次替换（tier-2 返回未实例化声明，`Self` 由 `resolve_static_call_type_bindings` 统一注入）。修后 trace 变为 `raw=List[T] out=List[Pair[UInt, T]]`，正确。

### 未修：同一缺陷在实例方法路径（当前主阻塞）

膨胀仍在，探针（`KORAL_DEBUG_SUBST_CONTEXT=1`，`apply_type_bindings` 上挂的 `[inflate]` 探测器）给出：

```
[inflate] raw=Option[Pair[UInt, T]] out=Option[Pair[UInt, Pair[UInt, T]]]
          bindings=[R=R T=Pair[UInt, T] Self=EnumerateIterator[T, R]]
```

`raw` **已经是正确结果**（1 层），被这套 bindings 又套了一次。要点：

- `Self=EnumerateIterator[T, R]` 是**未实例化**的 target —— 这正是物化时 `trait_tool_source_trait_bindings` 产出的映射
- `T=Pair[UInt, T]` 是 trait 参数到 conformance 实参的映射
- 说明 receiver 侧的 unification（`resolve_signature_call_type_bindings` → `infer_type_bindings(self_param_type, receiver_type)`）在给一个**已经绑定好的** symbol 重算映射

与静态路径同一类缺陷，位置在 `resolve_method_return_type_for_call` / `resolve_signature_return_type`。

**为什么不能用「跳过含自身 key 的绑定」这类启发式**：`Pair[GP("T"), Int]` 配 `{T: Int}` 也满足「值含 key」以外的误判条件，会漏替换。正确做法只能是**声明形态 + 单次替换**贯穿全部签名产出点（`resolve_conformance_method_signature`、`resolve_trait_registry_method_signature`、`lookup_method_signature` 等都要返回声明形态），与 Swift `lookupConcreteMethodSymbol` 直接使用 symbol 类型的模型一致。

**判据**（用来验证修复是否彻底）：`first`/`into_set`/`reduce` 三处 `Type mismatch` 消失，且 `[inflate]` 探针零输出。

### 进展（同日稍晚）

按 Swift「声明形态 + 单次替换」又修掉**同构的第二处**：

- `resolve_extension_method_template_signature` 的 `checked_return_type` 分支（实例方法路径）—— 与静态路径那个是孪生缺陷。改成对称处理：`checked_parameters` / `checked_return_type` 是同一层级的**已解析**形态，直接使用（对应 Swift `TypeCheckerMethods.swift:587-610`），不再叠加 conformance 实参映射。

`[inflate]` 探针 **245 → 33**。

### 剩余（第三处，未收口）

33 处膨胀的两种形态：

```
bindings=[T=Pair[UInt, Pair[UInt, T]]]                    ← 绑定值本身已被二次替换
bindings=[T=Pair[UInt, T] Self=List[Pair[UInt, T]]]       ← Self 已过替换
```

已排除的调用点（均加了探针且**零膨胀**）：
`bind_direct_method_signature`、`resolve_signature_return_type`、`resolve_method_return_type_for_call`、`resolve_static_method_return_type_for_call`、`bind_method_symbol_type`、`resolve_conformance_method_signature`、`conformance_type_key_matches`。

### 膨胀收口（同日，四处同构缺陷）

「对**已解析**类型再套一次替换图」这个缺陷在四个地方重复出现，全部按 Swift `resolveGenericExtensionMethod`（`TypeCheckerMethods.swift:587-610`：`checkedParameters`/`checkedReturnType` 已解析，直接用）修掉：

| # | 位置 | 探针计数 |
|---|---|---|
| ① | `resolve_static_extension_template_signature` | 245 → … |
| ② | `resolve_extension_method_template_signature` | … → 33 |
| ③ | `type_checker_expressions_static_calls.koral:941`（对已实例化的 `declared_receiver_type` 再套） | 33 → 31 |
| ④ | `type_checker_expressions_static_calls.koral:965`（对 `resolve_static_method_return_type_for_call` 的结果再套 `apply_static_method_type_bindings`） | 31 → **5** |

### 边界修正（同日收尾）：「已解析」不等于「不需要替换」

上一版把「已解析不再套」扩大到了整个 `bindings`，这是**过度矫正**：`checked_parameters` / `checked_return_type` 只是**已经烘焙了 conformance 的 trait 实参**，模板自身的类型参数仍然要绑定。

错误形态从 228 条暴涨到 228+（`Type Range[UInt] does not explicitly implement trait [T, RangeIterator[T]]Iterable`、`Type T does not explicitly implement trait Step`、`deque.koral:144 expected UInt, got T`）—— trait 实参被留成了裸 `T`。

正确边界（三处统一）：

```
checked_bindings = 模板自身 typeParams → 实参 + method typeParams + Self
bindings         = checked_bindings + conformance trait 实参

checked_*            → 套 checked_bindings   （trait 实参已在里面，不能再套）
TypeNode 路径 / 约束  → 套 bindings           （声明形态，需要完整替换）
```

修正后报错 **228 → 72**，`Step` / `Iterable` / `Range` 一族全部消失。

### 决定性发现：约束强制点（193 → 503）

用最小探针判定两边行为：

| | `s.runes().into_list()`（不调 `into_set`） | `s.runes().into_set()` |
|---|---|---|
| Swift | 0 错误 | **调用点**报 `Rune: Hash` |
| Bootstrap（改前） | 物化期就报 `Rune: Hash` | 同样报 |

**Swift 只在调用点强制约束；bootstrap 在物化期重检查 tool body 时就强制了。** 多出来的那一层是当时 72 条报错的全部来源。

两处修正：

1. **`resolve_extension_method_template_signature` 的 owner 约束循环**（`type_checker_methods.koral:1234`）
   它拿 `template.type_params`（即 `type mutable Set[T Hash]` 的 `T Hash`）去强制。Swift `resolveGenericExtensionMethod`（`TypeCheckerMethods.swift:562-610`）用的是 `methodInfo.typeParams`，而 Pass 2（`TypeCheckerPasses.swift:1470`）填的是**方法自己的**类型参数，从不是目标类型的。目标类型的约束是它的**良构性**，在类型以具体实参构成处兑现，不在每次方法解析时。
   → 关掉该循环：报错 72 → 10。

2. **`trait_tool_type_params_satisfied`（`type_checker_members.koral`）**
   tool 的类型参数约束若被 trait 绑定不满足（`given[T Ord] Iterator[T] { max }` 物化到 `EnumerateIterator` 时 `T → Pair[UInt,T]` 而 `Pair[UInt,T]: Ord` 不成立），**跳过物化**。这正是 Swift 观察到的行为：该特化根本不会被构造出来，自然也不会在调用点报错。
   → 报错 10 → **0**，全量 193 → **503**。



```
24  Type K does not explicitly implement trait Hash (checking constraint K: Hash)
 8  Type Rune does not explicitly implement trait Hash (checking constraint T: Hash)
 8  Type 'Pair[UInt, Pair[UInt, T]]' does not satisfy trait 'Hash' …   ← 残留膨胀（34 处）
 8  Type 'Pair[K, V]' does not satisfy trait 'Hash' because inner type 'V' does not implement 'Hash'
 8  Type 'Pair[A, B]' does not satisfy trait 'Hash' …
```

要点：

- **`Rune` 确实没有 `Hash` conformance**（`std/rune.koral` 只有 `Eq`/`Ord`/`ToString`/`Pod`）。`given[T Hash] Iterator[T] { into_set }` 物化到 `StringRunesIterator`（`Iterator[Rune]`）时需要 `Rune: Hash`。
- **Swift 不报这些**，因为 Swift 的 `lookupConcreteMethodSymbolDirect` 返回 symbol **不做约束检查**，`enforceGenericConstraints` 只在 `resolveGenericExtensionMethod` 里做。bootstrap 在 `resolve_extension_method_template_signature:1234-1255` 对模板类型参数做检查，比 Swift 严。
- 另外 `Pair[K,V]` / `Pair[A,B]` 的 `Hash` 需要元素 `Hash` —— tool 的 `T Hash` 映射到**非泛型参数**时 Swift 用 `guard case .genericParameter` 跳过（`TypeCheckerPasses.swift:3368`），bootstrap 的 `install_conformance_and_tool_bounds` 也已同样跳过，所以这些是**真实约束缺失**，不是映射错误。

**下一步**：核对 bootstrap 的约束检查触发点与 Swift 的差异 —— 哪些地方 Swift 不查而 bootstrap 查（尤其物化期 tool body 重检查）。判据：`Rune`/`Pair` 那 32 条消失且 Swift 侧对应行为不变。



### 剩余 15 例（513/528）

| 簇 | 用例 | 状态 |
|---|---|---|
| trait-tool 方法签名 | `stream_simple`、`stream_basic`、`stream_api_test`、`stream_inference_test`、`stream_sum_product_average` | 见下 |
| trait entity 泛型 | `trait_entity_generic_trait`、`trait_entity_generic_type_trait` | `Undefined type: T` |
| 其它 trait entity | `merge_basic`、`qualified_call`、`qualified_generic_method` | 各异 |
| C 生成 | `for_loop_nested`、`io_utils_test` | 类型不匹配 |
| 语法/语义 | `trailing_comma_test`（`add` 多余位置参数） | — |
| 杂项 | `time_of_day_basic`、`borrow_ptr_non_pod_error` | 待查 |

**stream 簇不是「lambda 推断」问题**（曾误判）。最小探针：

```
list.iterator().filter((x Int) -> x > 2)   ✓  显式标注
list.iterator().filter(f)                  ✓  具名函数
list.iterator().filter(5)                  ✓  ← 错误实参也被接受！
list.iterator().filter((x) -> x > 2)       ✗  Cannot infer type for parameter 'x'
apply((x) -> x > 2, 5)                     ✓  普通函数调用推断正常
```

`filter(5)` 不报错 ⇒ **`filter` 的参数类型解析出来是 `Unknown`**。显式 lambda 能过是因为它自带类型、不依赖期望类型；推断 lambda 需要具体期望类型才失败。所以要查的是**签名本身**，不是推断。

`filter(self, fn Func(T) Bool)` 的 `T` 是 **trait 的**类型参数，必须绑到该 receiver 的 conformance 实参（`ListIterator[Int]` → `T = Int`）。已修两处同源：

- `resolve_trait_tool_method_signature` —— 原先只绑 `Self` + 方法类型参数，补上 `trait_method_bindings(trait_name, base_type)`（与 `resolve_trait_registry_method_signature` 同一来源）。**`trait_entity_generic_trait` 由此通过。**
- `resolve_extension_method_template_signature` —— 同样补上该映射。

但 `filter` 仍走不到正确形态。**下一步**：确认 `filter` 从哪条 tier 返回（加窄探针打印 `fn` 的解析结果），再对症 —— 它的解析路径不止这两条，或 `checked_parameters` 缺失时 TypeNode 路径拿到的 `bindings` 不含该映射。

### `filter` 为何是 `Unknown`（已定位）

`[tool-reg] key=ListIterator method=filter body=yes` —— **注册正常**。但调用解析出来是 `Unknown`：

```
list.iterator().filter() / .filter(1,2,3)   ✓  元数不检查
let a Int    = ...filter(5)                 ✓  返回类型不检查
let b String = ...filter(5)                 ✓
list.iterator().nosuchmethod(5)             ✓  ← 未定义方法也静默通过（独立问题）
list.iterator().next()                      → Option[Int]  ✓  正常方法不受影响
```

`make_method_callable_symbol` 的 `[sig]` 探针**零输出** ⇒ `filter` 根本没构造出 symbol。

**两处元数过滤把物化出来的 tool 模板拒了**：

物化时 `owner_type_params` 被 `trait_bindings` 过滤成**空**（`trait_tool_source_trait_bindings` 把所有 owner 参数名都塞进 `trait_bindings`，回过头又按它过滤），于是 `template.type_params.count() == 0`，而 receiver 的 `actual_type_args.count() == 1`：

1. `resolve_extension_method_template_signature` 开头的 `template.type_params.count() <> actual_type_args.count()` → 返回 `None`
2. `generic_template_registry.select_extension_method` 的 `extension_type_arg_count` 过滤 → 选不中

两处统一为：**只有声明了类型参数的模板才有元数可查**；无声明类型参数的模板（物化出来的 trait-tool 方法）已绑定到目标类型，接受 receiver 自带的实参。

（这与「`owner_type_params` 恒为空」是同一个上游缺陷的两个下游表现 —— 见 `install_conformance_and_tool_bounds` 那条。）

修完后签名恢复正常（`lam8` 正确报 `expected Func(Int) Bool, got Int`，`stream_simple` **check 通过**）。

### 剩余主簇：生成的 C 里没有对应定义（已隔离）

`stream_simple` 现在败在 C/链接层：

```
initializing 'struct List_I_d59' with an expression of incompatible type 'int'
```

即调用了**未声明的函数**（C 隐式 `int`）。检查生成的 C：

```
10978:  struct FilterIterator_I_ListIterator_I_d60_d35 _t472 = ListIterator_I_d60_filter(...);   ← 只有这一处调用
grep 'ListIterator_I_d60_' → 只有 copy / drop / payload_drop，**没有 filter / into_list 的声明或定义**
```

而 `Std_String*Iterator_filter` 是**有声明**的（3276-3384 行）。所以 `ListIterator` 这一支的 trait-tool 方法体没有被实例化/发射。

这与最初记录的「生成的 C 里没有对应定义」是同一簇，现在干净地隔离出来：**sema 已正确解析并发出调用，mono 侧的定义没跟上**。





### A. 五个「便宜实现」——全部已解决

| # | 问题 | 状态 |
|---|---|---|
| 1 | `HeapOwnedMove` 缺失 —— 真实语义漏洞 | ✅ 已修 |
| 2 | 逃逸分析链 ~1540 行死代码 | ✅ 已删 |
| 3 | 6 个死 intrinsic 表层泄漏 | ✅ 已删 |
| 4 | C 类型声明三相结构 | ✅ 已修 |
| 5 | `type mutable` 滥用 | ✅ 已修 |

**#4 详情（含一处自我更正）**：先前判断「bootstrap 缺三相结构」**是错的** —— `emit_type_declarations` 早已是 ① `emit_type_forward_declarations` → ② `emit_managed_nominal_wrapper_declarations` → ③ 稳定拓扑序完整定义，与 Swift `generateProgram` 同构。

真正的差距在**依赖抽取规则**。Swift `requiresCompleteNominalDefinition`：

```swift
case .structure, .enum, .genericStruct, .genericEnum:
    return !usesManagedNominalRepresentation(type)   // managed nominal 不产生依赖边
```

managed nominal 的 C 结构体只是 `{void* ptr; void* control;}`，不提及 payload，所以引用它从不要求它先定义。bootstrap 的 `record_dependencies_from_type` 对所有 struct/enum 都记边，于是 `List_Koralc_Token` 与 `Koralc_Token` 被强行排序 —— 这就是旧文档「类型簇 wrapper 需排到 payload 之前」的来源。已补上同一条跳过规则，该问题被**结构性消除**而非调排序器。

**#5 详情**：5 个**无 mutable 字段**却声明为 `type mutable` 的类型（违反 RFC 4.2）已改为 plain `type`：

- `MIRBlockID` / `MIRLocalID` / `MIRScopeID` —— Swift 均为纯值 `struct { let rawValue: Int }`。改为 `type mutable` 使每个 ID 成为堆分配 + ARC 的 managed nominal；`MIRScopeID` 这正是 `Koralc_MIRScopeID.tag` 误发射的根源（被分派进 managed-nominal 路径）。现已确认该误发射消失。
- `TemplateField` / `TemplateParam` —— 无 mutable 字段（`is_mutable` 是字段**名**），Swift 为普通 struct。

保留 `type mutable` 的（确实含 `mutable` 字段，符合 RFC 4.2）：`MIRProgram`（`mutable functions`）、`MIRBasicBlock`（`mutable statements`/`terminator`）、`GenericFunctionTemplate` / `GenericExtensionMethodTemplate`（`mutable checked_*`）、`GenericTemplateRegistry`（mutable 字典）。

### B. 方法声明身份未贯穿全部注册点（当前主要阻塞）

第 12 条把「方法声明 DefId」这一维补上了，但**还没贯穿到所有注册点**，所以判定不生效、`comparable`/`trait_same_name_method_conflict` 仍是取舍。

已定位的下一处：`type_checker.koral:2612` 的 Pass 2 signature 注册用 `make_method_callable_symbol_with_param_types(...)` 构造 symbol，**内部新铸 DefId**，与 `m.def_id` 不一致 → 同一方法两次注册仍是两个 DefId。

收口要求：**所有** `method_table.register` / `register_extension_method_template` 的 symbol 都必须携带同一个源 DefId。

### B2. Swift 侧的方法身份改造（未开始）

同一改造要在 Swift 做：

- Swift 的 `MethodDeclaration`（`AST.swift:293`）同样**没有 DefId**
- Swift 的歧义判定 `extensionMethodTraitSources[typeName][methodName] = [traitName]`（`TypeCheckerPasses.swift:1638`）按 **trait 名**，应改为按方法声明 DefId
- Swift 的 `extensionMethods` / `concreteExtensionMethods` / `traits` 仍按名字分桶 → 跨模块同名 trait 会撞桶

判据对照（Swift 现状 vs 目标）：

| | 现状 | 目标 |
|---|---|---|
| 同一声明多次到达 | 靠 `contains(traitName)` 挡 | 同一 DefId → 覆盖 |
| 两个声明同名 | `existingSources.isEmpty` 启发 | 两个 DefId → 歧义 |
| 跨模块同名 trait | 撞桶 | DefId 区分 |

### C. 剩余字符串匹配（Swift 无对应物）

`mono_functions.koral` / `mono_type_resolution.koral` 仍有约 20 处名字匹配：

- `trait_name_matches`（`mono_functions.koral:531`，`ends_with(".\(right)")`）余 9 处调用
- `trait_target_static_trait_name_matches`（`mono_type_resolution.koral:8845`）2 处
- `select_trait_tool_template_cached` 7 处调用（按名字缓存）
- `template_name.ends_with(".Pair")`（`mono_expr_substitution.koral:226`）
- `trait_name.ends_with(".Randomizable")`（`mono_functions.koral:58`）
- `codegen_compose_method_c_name`（`mono.koral`）—— 第二套 C 名拼装，与 `make_extension_method_layout_name` 公式不一致；Swift 只有一个 mangler
- `remap_source_keys` 混用 `structure_name` / `concrete_lookup_type_name` / `conformance_trait_name`

### D. 其它已定位问题

1. **`for_loop_nested`**：`c.push(100)` 的 receiver 落到前一 `for c in chars` 循环变量的 `when`-subject payload（`__mir_when_subject_13_13.data.Some.value`），符号→local 映射问题，与所有权无关。已排除非确定性（`emit-c` 同源码 3 次 MD5 一致）。
2. **诊断归属**：`SourceSpan` 只有 `start`/`end`，不带文件；诊断用 `self.storage.file_path`。曾观察到同一 span 对多个文件重复上报，且指向不含对应构造的签名行（误导性极强）。`recheck_concrete_given_member_body` 已正确设 `file_path`，泄漏点在普通 template body 路径，未定位。
3. **`GenericConstraintBound` 只有 `trait_name String`**，无 DefId —— 约束侧身份仍未穿透。
4. **`def_id_invalid()` 占位点剩余 30 处**：`compiler_context` 6、`type_checker` 4、`mono_type_resolution` 4、`generic_template_registry` 4、`types` 3、`type_checker_methods` 3，其余各 1。

---

## 剩余 15 例

| 簇 | 用例 | 归属 |
|---|---|---|
| 取舍对 | `comparable`（与下一行二选一） | B |
| 取舍对 | `trait_same_name_method_conflict`（当前通过） | B |
| trait tool / generic extension | `trait_entity_generic_trait`、`trait_entity_generic_type_trait`、`trait_entity_merge_basic`、`trait_entity_qualified_call`、`trait_entity_qualified_generic_method` | B |
| Stream | `stream_simple`、`stream_basic`、`stream_sum_product_average`、`stream_api_test`、`stream_inference_test` | B |
| 杂项 | `for_loop_nested` | D1 |
| | `io_utils_test`、`time_of_day_basic`、`trailing_comma_test` | 待定位 |

## 下一步顺序

1. **实例方法路径的「声明形态 + 单次替换」**（当前主阻塞）—— 把 `resolve_conformance_method_signature` / `resolve_trait_registry_method_signature` / `lookup_method_signature` 等签名产出点统一到声明形态，调用点只替换一次。判据：`[inflate]` 零输出、`first`/`into_set`/`reduce` 三处 `Type mismatch` 消失。预期可一次性收回绝大部分 335 个失败（它们共享同一处 std 报错）。
2. **B：方法 DefId 贯穿全部注册点** —— `type_checker.koral` Pass 2 用 `make_method_callable_symbol_with_param_types` 内部新铸 DefId，与 `m.def_id` 不一致。目标：`comparable` 与 `trait_same_name_method_conflict` 同时通过。
3. **B2：Swift 侧同一改造** —— 改完**单独验证 Swift 仍 528/528**（注意：Swift 源码已有 `MethodDeclaration.defId` 等改动，但 `compiler/.build/debug/koralc` 是改动前构建的，需重建后验证）。
4. **C**：删剩余约 20 处字符串匹配；统一 C 名 mangler。
5. **D1/D2/D3** 与剩余 `def_id_invalid()` 穿透。
6. **删除本轮临时 trace**（`trace_call_return_substitution` / `trace_named_return_substitution` / `apply_type_bindings` 上的 `[inflate]` 探测器，均挂在 `KORAL_DEBUG_SUBST_CONTEXT` 下）。

## 验证方式（避免回退）

按经验：**整条链改完再统一测试**，不要改一点测一点 —— 后者会在 `comparable` / `trait_same_name_method_conflict` 这类互斥用例上来回摆动，看起来像反复回退。Swift 与 bootstrap **分别**验证。

## 最终门禁

- Bootstrap build 成功。
- Bootstrap self-host `check --package-config bootstrap/koral.json --target-module koralc` 成功。
- `./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/bootstrap -j=8` 达到 528/528；网络类波动用重复运行区分环境失败与编译器回归。
- 删除临时 debug 输出，完成内存测试分离与最终 bootstrap 审阅报告。

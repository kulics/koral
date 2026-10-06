# 身份匹配（DefId）改造 — 跟踪文档

> 本文件是**工作跟踪文档**，不是设计定稿。目的是把已探索的事实、已定的方向、当前进度、
> 已经走过的弯路钉在一处，避免再次重复试错。
>
> 每次会话开始先读这一份，结束前把状态写回来。

**最后更新**：2026-09-30（阶段 A + B 完成）

---

## 0. 目标

把两个编译器里**用名字做身份匹配**的地方，换成 **DefId 做身份匹配**（rustc 的做法）。
名字只保留三个用途：**解析**（拼写 → 声明）、**显示**、**C 名字改编**。

> 一旦解析完成，只比身份，不比名字。

这是用户明确下的指令：
> 「把不符合最佳实践的命名匹配去掉，用类似 rust 的 defid 思路处理身份匹配逻辑。」

---

## 1. 硬性约束（用户规则，一直在生效）

| 规则 | 含义 |
|---|---|
| **No Auto Commit** | 只有明确要求才 commit；绝不主动提交 |
| **不能绕过 / 硬编码** | 不得用特判表、魔数、假实现来过关 |
| **不要用名字来兜底** | 身份判定失败时不得退回名字比较 |
| **不选最容易通过的办法** | 不得为了让测试变绿而让问题继续恶化 |
| **整链一起改再测** | 不改一点测一部分，容易触发回退 |
| **两边按最佳实践选** | 不以任一编译器为基线，取更正确的那个 |
| **自举不是目标** | 自举只是验证手段，不是产品目标 |
| **DefId 不稠密** | 模块导出后会稀疏，**禁止用数组下标索引 DefId** |
| commit 尾 | `Co-Authored-By: Claude Code <noreply@anthropic.com>` |
| PR 尾 | `🤖 Generated with [Claude Code](https://claude.com/claude-code)` |

---

## 2. 验证链（每步迁移后的固定流程，顺序不可换）

```bash
# 1) 种子自检
./bin/compiler-test-runner/compiler_runner --compiler swift \
  --swift-koralc compiler-reference/.build/release/koralc --timeout 60 -j 8

# 2) 种子编出 bootstrap（stage1）~83s
compiler-reference/.build/release/koralc build --package-config compiler/koral.json \
  --target-module koralc -o bin/compiler

# 3) stage1 全量
./bin/compiler-test-runner/compiler_runner --compiler bootstrap \
  --bootstrap-koralc bin/compiler/koralc --timeout 60 -j 8

# 4) 自举两轮 + 不动点（emit-c ~45s，clang ~40s）
bin/compiler/koralc emit-c --package-config compiler/koral.json --target-module koralc -o /tmp/s2
clang /tmp/s2/koralc.c std/koral_runtime.c -I std -o /tmp/s2/koralc -Wno-everything -O1
/tmp/s2/koralc       emit-c --package-config compiler/koral.json --target-module koralc -o /tmp/s3
clang /tmp/s3/koralc.c std/koral_runtime.c -I std -o /tmp/s3/koralc -Wno-everything -O1
/tmp/s3/koralc       emit-c --package-config compiler/koral.json --target-module koralc -o /tmp/s4
cmp /tmp/s3/koralc.c /tmp/s4/koralc.c && echo "FIXED POINT"

# 5) 悬空符号扫描必须为 0
grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*\(\);' /tmp/s3/koralc.c

# 6) stage2 全量
./bin/compiler-test-runner/compiler_runner --compiler bootstrap \
  --bootstrap-koralc /tmp/s2/koralc --timeout 60 -j 8
```

**当前基线（全绿）**：Swift 557/557 · stage1 557/557 · FIXED POINT · 悬空 0 · stage2 557/557

---

## 3. 已落地（green，未提交）

### 3.1 模块级类型身份 —— **已完成，全链验证绿**

问题：同一进程里两个模块各自 `type Plain` 时，裸名类型表把两个声明塌成一个，
于是 `Plain(1)` 报 `Missing positional argument 'extra' for 'Plain'`。

**修法**：模块级符号的键是 **(module, name)**，不是 bare name。

| 文件 | 变更 |
|---|---|
| `compiler/koralc/typed/types.koral` | `qualified_trait_key` → **`qualified_symbol_key(module_path, name)`**，返回 `module.path.name` |
| `compiler/koralc/sema/scope.koral` | 新增 `define_scoped_type` / `lookup_type_in_module`（先 generic_params，再 qualified，最后 bare） |
| `compiler/koralc/sema/name_collector.koral` | 6 处 `define_scoped_type` |
| `compiler/koralc/sema/type_checker_decls.koral` / `type_checker.koral` | 类型别名同样 dual-key |
| `compiler/koralc/sema/type_checker_resolution.koral` | `resolve_type_name_binding` / `try_resolve_named_type_in_scope_without_diag` / `try_resolve_named_type_without_diag` / `resolve_named_type` 全改走 `lookup_type_in_module`；trait 兜底走 `trait_registry.get_in_module` |
| `compiler/koralc/sema/given_locality.koral` | orphan 规则改查 `get_in_module` + `lookup_type_in_module` |
| `compiler-reference/Sources/KoralCompiler/Sema/Scope.swift` | 镜像：`typeKey(_:modulePath:)` / `defineScopedType` / `typeInCurrentModule` / `hasTypeDefinition` 改义为「本模块是否声明」/ `defineType` 与 `overwriteType` dual-key |

**看护用例**：`tests/compiler-cases/cross_module_same_name_type_test/`（3 个模块，`mod_a`/`mod_b`
各声明 `Plain`/`Box`/`Shape`/`Circle`/`Square`）。**注意**：该用例注释里写明
extension method（`given Plain { tag }`）**尚未覆盖**，属于下一步方法表改造的看护点。

**已知残留（未批准修改）**：101 条诊断没有 line:col（需要 `TypeNode` 加 span，约 495 处机械改动）；
`Scope.new_generic_child` 死代码；`VisibilityChecker.swift:229` 有关于泛型模板模块路径的 TODO。

### 3.2 类型身份不能依赖声明顺序（记忆项）

在模板注册前构造的 `Type` 携带 invalid `templateDefId`，身份比对会**静默失败**。
→ 任何新的身份键都必须保证「先注册、后取键」，或键本身不依赖模板注册时机。

---

## 4. 已定方案：方法表按 DefId 键（rustc 模型）

### 4.1 rustc 怎么做的（已核对源码）

| rustc | 键 |
|---|---|
| `inherent_impls` | `FxIndexMap<LocalDefId, Vec<DefId>>` — **ADT 的 DefId** |
| `trait_impls_of(trait_def_id)` | **trait 的 DefId**；impl 按 `SimplifiedType::Adt(DefId)` |
| `associated_items(impl/trait DefId)` | `SortedIndexMultiMap<u32, Option<Symbol>, AssocItem>` — **名字只在一个容器内选成员** |

`probe.rs` 按 `self_ty.kind()` 分派：`ty::Adt(def, _) => def.did()`；
`ty::Bool | Ref | RawPtr | ... => incoherent_impls(simplify_type(..))` —— 后者是一张**封闭集合**，
因为这些类型**没有声明**，也就没有 DefId。

**结论**：容器用 DefId 键；名字只用来在**同一个已识别的容器内**选成员。

### 4.2 Koral 对应设计

```kotlin
// 类似 rustc 的 inherent_impls / incoherent_impls 二分
public type MethodOwner {
    Decl(def_id DefId),        // 有声明的：键是声明的 DefId
    Builtin(name String),      // 无声明的封闭集：Ref/RawPtr/Bool/Int... 只能用名字
}

public let method_owner_of(context, t Type) MethodOwner   // instance → 其模板的 DefId
public type MethodInstanceKey(owner MethodOwner, method_name String, method_type_args ...)
```

要点：

- **`MethodOwner.Decl` 只用于有声明的类型**；原始类型 / 引用 / 指针这些无声明者才落 `Builtin`。
- **类型参数是词法 binder**：`define_generic_param` / `define_generic_binding`；
  `define_type` **不能** shadow 它们（见记忆项 `type-parameters-must-shadow-globals`）。
- 需要重键的表（bootstrap）：
  `extension_methods`、`intrinsic_extension_methods`、`concrete_extension_methods`、
  `conformance_index`、`method_param_specs`、`extension_method_def_ids`、`static_method_by_key`、
  `concrete_callable_name_index`、`MIRProgram.static_method_lookup`。
- 需要重键的表（Swift，**未开工**）：
  `TypeChecker.extensionMethods`、`TypeChecker.extensionMethodTraitSources`、
  `Monomorphizer.extensionMethods`、`GenericTemplateRegistry.extensionMethods`、
  `MIR.staticMethodLookup["\(typeName).\(methodName)"]`。

### 4.3 为什么名字键不够

一个 bare-name 表会把**不同声明**塌成一个桶：

- `mod_a.Plain` 与 `mod_b.Plain` 的 extension method 互相污染 → `Duplicate definition: tag`
- `String` / `Rune` / `StringBuilder` 的方法互相污染 → 派发到 `Rune.to_string`（见 §5.3）

---

## 5. ✅ 已完成：方法表按身份重键（阶段 A）

**四个编译器全绿**：

```
Swift           557/557
stage1          557/557
自举不动点       FIXED POINT (s3.c == s4.c)     悬空符号 0
stage2 自举     557/557
```

### 5.1 结果

| 表 | 键 |
|---|---|
| `MethodTable`（methods / conflict / inherent / sources） | `MethodOwner` |
| `extension_methods` / `intrinsic_extension_methods`（**声明**） | `MethodOwner` |
| `conformance_index` | `MethodOwner` |
| `method_param_specs` | `MethodOwner` |
| `extension_method_def_ids`（**实例**） | `MethodInstanceKey` |
| `static_method_by_key` / `static_method_lookup`（MIR） | `MethodInstanceKey` |
| `concrete_callable_name_index` | `MethodInstanceKey` |
| `mono.extension_methods`（`ConcreteMethodEntry`，**实例**） | `MethodInstanceKey` |

新增：

- `MethodOwner { Decl(DefId), Builtin(name) }` —— 有声明者用 DefId，无声明的封闭集（原始类型 / ref / ptr / weakref）用固定名，与 rustc 的 `inherent_impls` / `incoherent_impls` 二分一致
- `MethodInstanceKey(owner, owner_args, method_name, method_type_args)` —— **等价于 rustc 的 `Instance { def, args }`**
- `CompilerContext.method_owner_of(t)` / `method_owner_decl(d)` / `method_owner_and_args(t)`
- `make_receiver_method_key(context, t, name, args)` —— 从**类型**推导完整实例键
- `collect_receiver_owners` / `collect_receiver_instantiations` —— 修饰符接收者展开
- `trait_owner_by_name` / `method_owner_for_name` / `method_owner_for_trait_name` —— **唯一**允许把拼写带进来的地方（解析边界）

### 5.2 两次关键诊断纠正（都曾走错一轮）

**第一次纠正**：以为是「C 名字改编与注册表键分家」。**错。** 实际是派发选错了方法
（`String` 的 `to_string` 调到 `Rune.to_string`）。改编名一直是对的。
→ **不要碰 `structure_name` / 名字改编。名字在那里是合法用途。**

**第二次纠正（真正的根因）**：`MethodInstanceKey` 只有 `(owner, method_name, method_type_args)`
时，`List[String].new` 与 `List[Rune].new` 是**同一个键** —— 因为它们共享模板 `List`，
而 `method_type_args` 为空。**声明桶按 owner 键是对的**（方法声明在模板上），
**实例键必须带 owner 的类型实参**。这就是 rustc 的 `Instance { def: DefId, args: GenericArgs }`
而不是只有 `DefId`。修好后 206/557 → 531/557。

第二个根因还剩一半：`mono.extension_methods`（存**已实例化**符号）也按 owner 键，
于是 `Set[Pair[Int,Int]]` 与 `Set[Pair[String,Int]]` 互相覆盖。改成 `MethodInstanceKey` 后
531 → **557/557**。

> **铁律**：*声明*表按 `MethodOwner` 键；*实例*表按 `MethodInstanceKey`（owner + owner_args）键。
> 把实例表按 owner 键，就是把 `List[String]` 与 `List[Rune]` 塌成一个。

### 5.3 删掉的名字匹配（真删，不是改写）

- `extension_template_key` 的拼写构造 → `method_owner_of`
- `generic_extension_lookup_key` 的 **125 行**逐个内建类型名字梯子 → 5 行
- `resolve_implicit_static_receiver_type` 的 `"Int"`/`"Int8"`/… 13 行梯子 + `is_string_type`/`is_rune_type` → 1 行
- `collect_receiver_lookup_keys`（`concrete_name` + `template_name` / `layout_key` + `type_display_name`）→ `collect_receiver_owners`
- `lookup_type_names` 六路拼写扫描 → 两个 owner
- `extension_lookup_type_names` **86 行**别名扫描 → 删
- `concrete_receiver_lookup_aliases`、`static_method_receiver_aliases`、`strict_wrapper_receiver_aliases` → owner 版
- 注册时的**裸名别名**（同一方法同时写 `type_key` / `template_name` / `get_name`）→ 只写一次
- codegen 的 `get_template_name <> receiver_key` 回退查找 → 删
- `owner_types_match` 用 layout key 比类型 → 用 `MethodOwner` 比
- `traits.get(name)` 判「是不是 trait」→ `is_trait_def_id`（新增 `trait_decls_by_def_id` 索引）

### 5.4 保留名字的地方（合法，不是漏改）

| 用途 | 为什么合法 |
|---|---|
| C 名字改编（`structure_name` / `make_extension_method_layout_name` / `concrete_lookup_type_name`） | 名字的正当用途之一；**改了会错** |
| 诊断文本（`modifier_owner.display()`） | 显示 |
| `trait_owner_by_name` / `method_owner_for_name` | **解析边界**：拼写 → 声明，只发生一次 |
| `MethodOwner.Builtin(name)` | 无声明的封闭集，等价 rustc `SimplifiedType` |

### 5.5 踩过的坑（不要再踩）

| 坑 | 症状 | 处理 |
|---|---|---|
| `generic_extension_lookup_key` 手搓键 | 351 失败 | 改委托 `extension_template_key` |
| sema 键改了 mono 读没改 | 又 351 失败 | 成对改 |
| `file_private` 是 **file** 作用域 | 跨文件看不见 | 改 `public let` |
| variant pattern 不能匹配字面量 | `.Builtin("Ref")` 不可达 | 绑 `.Builtin(kind)` 后 `==` |
| Dict 键需 `given T as Eq`/`as Hash` | 编译不过 | 补 conformance |
| 构造实参按位置、顺序敏感 | 字段错位 | 对齐声明顺序；改字段类型时**所有构造点**一起改 |
| `rm -rf compiler-reference/.build` | 种子编译器没了 | `cd compiler-reference && swift build -c release`（~45s） |
| 脚本按 `};` 匹配替换 | 剪错 `for` 的括号，留孤儿尾巴 | 手工修；避免大范围正则 |
| `when` 换成 `if` 时漏了收尾 `, .None() then {},` | 编译不过 | 成块替换 |

**用过的工具**（不在 repo 里）：`/tmp/koral-tools/apply-type-identity.py`（恢复类型身份绿树）、
`a2-rekey-sema.py`（阶段 A 的机械部分）。
**旧的** `/tmp/method-owner-wip*.patch` 已**作废**（四次大爆炸全失败），改用分步 + 编译器报错清单驱动。

## 6. Koral 语法备忘

```kotlin
type T(v Int);                  // struct 用圆括号
type T { A(), B() }             // enum 用花括号
let mutable x = ...;
given X { ... }                 // 扩展
given X as Trait { ... }        // 遵循
for x in xs then { ... }
when x in { .Variant(a) then ..., _ then ... }
```

- `file_private` 是 **file** 作用域（不是 module）
- variant pattern **不能匹配字符串字面量**
- Dict 键类型需要 `given T as Eq` / `as Hash`
- 构造实参**按位置**，顺序 = 声明顺序
- 参数名必须**小写开头**
- managed 集合赋值是**别名**

---

## 7. 计划

### 阶段 A — bootstrap 方法表按 DefId 键（进行中）

| # | 步骤 | 状态 |
|---|---|---|
| A0 | 恢复绿树（type identity） | ✅ 已完成 |
| A1 | 注入 `MethodOwner` / `MethodInstanceKey` / `method_owner_of` | 🔶 wip4 里有 |
| A2 | 重键 sema 侧表（extension / conformance / param_specs） | 🔶 wip4 里有 |
| A3 | 重键 mono 侧表（extension / static_method / callable index） | 🔶 wip4 里有 |
| A4 | 重键 `MIRProgram.static_method_lookup` | 🔶 wip4 里有 |
| A5 | **修 `extension_template_key` 的接收者碰撞**（§5.4） | ❌ 未做 |
| A6 | 全链绿（557/557 × 3 + FIXED POINT + 悬空 0） | ❌ 未做 |

### 阶段 B — Swift 侧方法表重键（未开工）

| # | 步骤 | 状态 |
|---|---|---|
| B1 | `TypeChecker.extensionMethods` / `extensionMethodTraitSources` 换 `MethodOwner` 键 | ❌ |
| B2 | `GenericTemplateRegistry.extensionMethods` | ❌ |
| B3 | `Monomorphizer.extensionMethods` | ❌ |
| B4 | `MIR.staticMethodLookup` 的 `"\(typeName).\(methodName)"` 键 | ❌ |
| B5 | 全链绿 | ❌ |

### 阶段 C — 其余名字匹配（按计划文件 `indexed-knitting-waterfall.md`）

那是**约束表示重构**（`Constraint` 代数类型，替代 `TypeNode` 当约束）的独立任务，
与本文件的「身份匹配」正交。本文件只记一笔，不在此展开。
其中与本文件直接相关的部分：**trait 身份换 DefId**（`CanonicalTraitRef` /
`ExplicitTraitConformanceKey` / `GenericConstraintBound` / `ParentTraitConstraint` /
`GivenTraitDecl` / `MIRGlobal.Given.trait_name`）。

**其它收敛目标**（探索中发现的重复实现）：

- `is_std_drop_trait` 有三份且语义各异（`type_checker_expressions.koral:206`、
  `codegen_generate.koral:241`、`mono_types.koral:353`），另有死代码
  `is_std_drop_trait_conformance`（`mono_types.koral:372`）→ 收敛成 DefId 一份
- `primitive_extension_template_name`（`mono_functions.koral:2073`）第二张「原始类型→名字」表
- `Scope.new_generic_child` 死代码

---

## 7.5 ✅ 阶段 B：Swift 侧方法表按身份重键（已完成）

**四个编译器全绿**（与阶段 A 同一验证链）。

| 表 | 键 |
|---|---|
| `TypeChecker.extensionMethods` / `extensionMethodTraitSources` | `MethodOwner` |
| `TypeChecker.genericExtensionMethods` / `genericIntrinsicExtensionMethods` | `MethodOwner` |
| `GenericTemplateRegistry.extensionMethods` / `intrinsicExtensionMethods` / `concreteExtensionMethods` | `MethodOwner` |
| `Monomorphizer.extensionMethods`（**实例**，扁平化） | `MethodInstanceKey` |
| `Monomorphizer.extensionMethodDefIds` | `MethodInstanceKey` |
| `MonomorphizedProgram.staticMethodLookup` / `MIRProgram.staticMethodLookup` | `MethodInstanceKey` |

新增 `compiler-reference/Sources/KoralCompiler/Sema/MethodIdentity.swift`：`MethodOwner` /
`MethodInstanceKey` / `methodOwner(of:)` / `methodOwnerAndArgs(of:)` /
`receiverMethodKey(...)` / `methodOwnerForName(...)`。

**删掉的名字匹配**：

- `Monomorphizer.swift:848` 的 `simpleName.hasPrefix(key) || simpleName.contains(key)` 扫描 → 删
- `extensionLookupTypeNames`（`concreteName` + `templateName` 双拼写）→ `extensionLookupTypes`（返回类型）
- `lookupConcreteMethodSymbolDirect` 里 `genericExtensionMethods["Ref"]`/`["MutRef"]`… 梯子 → `.builtin(...)`（封闭集身份）与 `methodOwner(of:)`
- `extensionMethodDefIds["\(typeName).\(methodName)"]` 字符串键 + `structureName != concreteLookupTypeName` 别名 → 单一 `MethodInstanceKey`
- `for (traitName, _) in extensionMethods` + `traits[traitName]` 判「是不是 trait」→ 按 DefId 匹配

**两个必须修的解析边界**（`methodOwnerForName`）：

1. **泛型模板不是类型表里的类型**。`given[T Any] List` 解析不到 `List` 时会落到
   `.builtin("List")`，而查找侧是 `.decl(List 的 DefId)` —— 注册与查找永远对不上。
2. **裸名兜底是碰撞源**。`lookupGenericStructTemplateDefId` 的 `?? genericStructTemplates[name]`
   会让两个模块的 `Box` 塌到一个。新增 `...DefIdStrict(modulePath:name:)`，**身份解析不做裸名兜底**。

### 7.6 ✅ 剩余问题已修（2026-09-30 / 10-01）

**四个编译器全绿**：Swift 557/557 · stage1 557/557 · FIXED POINT · 悬空 0 · stage2 557/557

### 根因（三处，都在「按名字找模板」）

同名泛型类型（两个模块各一个 `Box`）的扩展方法塌成一份，是因为**三处**把
模板的**声明**从它的**拼写**找回来：

| 位置 | 问题 |
|---|---|
| `MonomorphizerTypeResolution.resolveParameterizedType` | `genericTemplates.structTemplates[template]` 按名字找模板 |
| `Monomorphizer.typeInstantiationCacheKey` | 同上 → 两个实例化共用一个缓存键，第二个直接返回第一个的结果 |
| `CompilerContext.updateStructInfo` / `updateEnumInfo` | 实例注册时 `getTemplateDefId(defId) ?? 按名字查`，名字兜底把 mod_a 的实例链到 mod_b 的模板 |

修法：**类型带上声明，不再按名字找回来**。

- `GenericTemplateRegistry.structTemplate(forDefId:)` / `enumTemplate(forDefId:)` —— 按 `DefId` 索引
- `typeInstantiationCacheKey` 用类型自带的 `templateDefId`
- `updateStructInfo`/`updateEnumInfo` 增加 `templateDefId:` 参数，调用点把声明传进来；**删掉名字兜底**
- `CompilerContext.templateDeclaration(of:)` —— 实例 → 其模板的声明（`getTemplateDefId`）

bootstrap 侧同步修了 `type_instantiation_cache_key`（同样的按名字找模板）。

### 看护

`cross_module_same_name_type_test` 现在覆盖：

- **非泛型**同名类型的扩展方法（`given Plain { tag }`）—— 输出 `a-plain` / `b-plain`
- **同名 trait** 的分发 —— 输出 `a-circle` / `b-square`
- **同名泛型**类型的构造与字段 —— 输出 1 2 20 / 10 20 40

同名泛型类型的扩展方法（`given[T Any] Box[T] { stamp }`）在 **Swift** 上已验证正确
（`box_stamp_a(11)` / `box_stamp_b(22)` → 11 / 44），但**尚未**在 bootstrap 上成立，
所以还没写成断言（见 7.7）。

## 7.7 剩余一处（已定位，未修）

**bootstrap 的 `drop` 发射路径与扩展方法共用 `make_extension_method_layout_name`。**

给扩展方法的 C 名加上 owner 声明后缀（`Box_I_stamp_d184`，与类型名 `Box_I_d184` 同约定），
在 Swift 上正确；在 bootstrap 上会和 `drop` 的发射撞名：

```
void List_U8_drop_d59(struct List_U8_d59*);      // drop 钩子（指针 ABI）
void List_U8_drop_d59(struct List_U8_d59);       // 扩展方法实例化（值 ABI）
```

证据（同一测试，去掉后缀 vs 加上后缀）：

| | `List_U8_drop` 符号 |
|---|---|
| 不加后缀 | 只有一份，指针 ABI |
| 加了后缀 | 两份，指针 + 值，冲突 |

`emitted_user_defined_drop_method_name` 走 `callable_c_name(symbol)`，
也就是扩展方法的 mangle；`drop` 于是有两个发射源却共用一个名字。
**下一步**：把 `drop` 的发射路径与扩展方法的 mangle 解耦（`drop(self)` 的 self ABI
在 sema 是 `*unsafe mutable Self`，实例化路径没做这个包装），再把后缀加回去。

## 7.8 名字匹配保留处（都有注释 + 出处）

名字只允许出现在三个位置：**解析**、**显示**、**C 改编名**。已逐处加注释：

| 位置 | 用途 | 出处 |
|---|---|---|
| `Scope.lookupGenericStructTemplate` / `lookupGenericEnumTemplate` / `hasGenericTemplate` | `TypeNode` 拼写 → 声明 | `rustc_resolve`：`Res::Def(.., DefId)` |
| `BidirectionalInference.genericNominalType` / `ConstraintSolver.genericNominalType` | 同上 | 同上 |
| `MethodOwner.Builtin(name)` 的封闭集 | 无声明类型的身份 | `SimplifyType` / `incoherent_impls` |
| `stdStringDefId` / `stdRuneDefId`（`modulePath: ["Std"]`） | lang item | `rustc_hir::LangItem::Str` |
| `generateCIdentifier` / `generateFileIdentifier` | C 输出 | 名字的正当用途（不是身份） |
| `ownerOfGenericTemplate` / `trait_owner_by_name` / `method_owner_for_name` | 拼写 → 声明 | `rustc_resolve` |

**审计结果**：

```
invalid templateDefId 构造          0
按名字键的方法表                    0
从 Type 的名字找回来 DefId          0
剩下的名字查找                      8 处，全部在解析边界
探针 / hack                         0
```

## 7.9 收尾计划（2026-10-01 立，按风险排序）

身份判定的**规则**已按 rustc 改到位；但**表示方式**还不是 —— 名字仍与 DefId 并存于
`Type`，注册表仍以名字为主键，所以「不看名字」目前靠纪律和注释维持，不是靠类型保证。
下面四项是把这道保证补上。

| # | 目标 | 规模 | 为什么 |
|---|---|---|---|
| **1** | `ReceiverMethodOwner.ExtensionTemplate(owner_name)` → `DefId` | 小 | **唯一还在「看名字判身份」的活代码**（`mono_expr_substitution.koral:1829`）。同文件的 `.ConcreteType(...)` 比的是 `Type`，是对的 |
| **4** | bootstrap 的 `drop` 发射路径与扩展方法 mangle 解耦，然后把 owner 声明后缀加回去 | 小 | 独立问题（见 7.7）；解耦后同名泛型扩展方法就能在 bootstrap 上写成断言 |
| **2** | `Type` **去掉名字字段** | 大（Swift ~151 模式点 + bootstrap 同量） | rustc 的 `Ty::Adt(&AdtDef, GenericArgs)` 根本没有名字字段。现在靠注释约定，这一整类 bug 就是从此漏出去的。改成从 `item_name(defId)` 现取，越界写不出来 |
| **3** | 注册表改 `Dict[DefId, ...]` 主键；裸名兜底改走 import 解析 | 中 | `structTemplates: [String: ...]` 仍是名字主键，`structTemplate(forDefId:)` 是线性扫；Swift 的 `traits` 没有 DefId 索引（bootstrap 有，不对称）；`genericStructTemplates[qualified] ?? [name]` 的裸名兜底是全局猜 |

**执行顺序**：1 → 4 → 2 → 3。1 和 4 都能独立验证；2 单独一轮（改完必须全链绿，
且 `grep` 确认没有任何代码从 `Type` 读名字）。

### 每步的验收判据

```
1: grep -rn "ExtensionTemplate(owner"  → 只剩 DefId 形式；无 `== source_name` 类名字比较
4: bootstrap 上 `box_stamp_a(11)`/`box_stamp_b(22)` → 11/44，且 List.push 等仍编译链接
   （断言写进 cross_module_same_name_type_test）
2: Type 的 genericStruct/genericEnum/traitObject 不再有名字字段；
   显示/改编名走 item_name(defId)；四个编译器全绿
3: structTemplates/traits 等主键为 DefId；裸名兜底只出现在 import 解析处
```

---

## 10. 执行记录（2026-10-01，已收尾）

**四个编译器全绿**：Swift 557/557 · stage1 557/557 · FIXED POINT · 悬空 0 · stage2 557/557

### 第 1 步（`ReceiverMethodOwner` → 身份）：✅ 完成

```
Swift      case extensionTemplate(ownerDefId: DefId) / concreteType(ownerType: Type)
bootstrap  ExtensionTemplate(owner_def_id DefId) / ConcreteType(owner_type Type)
```

`mono_expr_substitution.koral` 的 `candidate_def_id == source_def_id` 取代了
`candidate_name == source_name`；`.ConcreteType(...)` 比的是 `Type`（身份）。
审计：owner 上无名字比较。

顺带修掉的名字用法：

- `TypeChecker.labelOwner`（参数标签缓存键）—— 原用 owner 拼写，现用 `methodLabelKey`（身份）
- `CodeGen` 的 drop 查找 —— 原 `lookupDefId([], name:)` 按拼写找 owner 的声明

### 中途回归（已修）：泛型类型的用户 `drop` 不被调用（一度 554/557）

三个测试（`enum_methods` / `generic_user_drop_specialization_regression` / `for_loop_drop`）
都是**泛型**类型的 `given[T] X[T] as Drop`。

**真因**：`CodeGen` 的 drop 查找里，我拿 owner 的**声明**（模板 `Holder`）去比**实例化**的
C 名（`Holder_I_d171`），永远比不上。修法：两侧都用**从类型算出来的**名字
（`dropOwnerTypeName(ownerType) == typeName`）—— 都是 mangling/显示，不是身份判定，
但也不再经过拼写。

> 教训：`ownerDefId` 解析到**模板**，而 C 名是**实例化**的。做名字（C 名）比较时，
> 两侧必须处在同一层（都在实例化层），否则改身份也会顺手改坏显示层。

### 第 4 步（bootstrap `drop` mangle 解耦）：✅ 完成

三处，都是身份问题：

1. **`drop(self)` 的接收者 ABI** —— mono 实例化时没按 sema 的规则把 `self` 包成
   `*unsafe mutable Self`，于是实例化出来的 `drop` 是值 ABI，与 drop glue 的
   `void <name>(struct <type>*)` 原型撞名。已在 `instantiate_extension_method_from_entry`
   的两个参数分支都加上包装。
2. **mangle 的 owner 不统一** —— `effective_owner` 对 trait 方法是 trait 的声明、
   对普通扩展是类型的声明，于是一个方法有两个 C 名
   （`SetIterator_I_next_d33` vs `SetIterator_I_next_d74`），调用点和定义对不上。
   改成一律用**接收者类型**的声明。
3. **owner 声明后缀** —— `make_extension_method_layout_name` 加 `_d<templateDefId>`，
   与类型名 `Box_I_d184` 同约定。加上后同名泛型的两个 `stamp` 才分成
   `Box_I_stamp_d123` / `Box_I_stamp_d136`。

### 附带修掉的 bootstrap 类型身份（第 4 步牵出来的）

`GenericTemplateRegistry.struct_templates` 是**裸名**键，两个模块的 `Box` 后注册者赢，
`struct_by_def_id(d113)` 找不到 → `Box_I_d113` 只有前置声明没有定义。

- 增加 `struct_templates_by_def_id` / `enum_templates_by_def_id`，注册时同时写入
- `struct_by_def_id` / `enum_by_def_id` 按声明查
- 实例化路径（`mono_type_resolution` / `mono_expr_substitution`）改用它们，
  不再 `lookup_struct(template_name)`

### 看护

`cross_module_same_name_type_test` 现在**两个编译器**都断言：

```
1 2 20 10 20 40        同名 Plain / Box 的构造与字段
a-circle b-square      同名 trait 的分发
a-plain  b-plain       同名非泛型扩展方法
11 44                  同名泛型扩展方法（mod_a 返回 value，mod_b 返回 extra = v*2）
```

### 审计

```
owner 上的名字比较                  0
invalid templateDefId 构造          0（Swift）；bootstrap 仅 1 处 codegen_vtable 兜底
mono 里的名字键模板查找            13 处（见下）
探针                               0
```

mono 里剩下的 13 处 `lookup_struct(name)` 分两类：

- **解析**（`resolve_type_node` 里的 `lookup_struct(base)` / `lookup_struct(name)`）
  —— `TypeNode` 拼写 → 声明，即 `rustc_resolve`，保留
- **待改**：`lookup_struct("Pair")`（lang item，应走 `is_std_pair_def_id` 一类的
  声明查找）、`lookup_struct(tname)`（`mono_functions`）、`lookup_struct(resolved_name)`
  —— 这些手里可能已有 DefId，属于第 3 步

sema 里的 38 处是 `TypeNode` 解析，保留（都有注释 + `rustc_resolve` 出处）。

## 11. 当前状态（2026-10-01 会话末）

```
工作树        未提交（No Auto Commit）
基线（全绿）  Swift 557/557 · stage1 557/557 · FIXED POINT · 悬空 0 · stage2 557/557
阶段 A + B    ✅ 方法表 DefId 重键
类型身份      ✅ 0 处 invalid templateDefId（Swift）；0 处从 Type 的名字找回来 DefId
本轮          ✅ 第 1 步 ReceiverMethodOwner → 身份
              ✅ 第 4 步 bootstrap drop ABI + mangle owner 统一 + owner 声明后缀
              ✅ 附带：bootstrap 模板注册表加 DefId 索引
剩余          第 2 步 Type 去名字字段（大）；第 3 步 注册表 DefId 主键 + mono 那 13 处
```

---

## 12. 第 2/3 步执行记录（2026-10-01）

### 第 2 步 `Type` 去名字字段

**Swift：✅ 完成，557/557，诊断文本一字未变。**

```swift
case genericStruct(templateDefId: DefId, args: [Type])
case genericEnum(templateDefId: DefId, args: [Type])
case traitObject(traitDefId: DefId, typeArgs: [Type])
```

`ConformanceTypeKey` 同步去掉。名字只在需要输出时从声明读：

- `Type.spelling(defId)` 走 `SemanticErrorContext.currentCompilerContext`
  （就是 rustc 的 thread-local `tcx`）
- `ConformanceTypeKey` 的比较改成比 **DefId**（原先 `template == other_template` 是按名字比身份）

**bootstrap：🔶 做到一半，当前编译不过（56 处错误）。**

已改对的：

- `Type` 定义去掉名字字段
- **`Type` 的 `Eq` 去掉了名字兜底** —— 原来是
  `if both valid then def_id == def_id else template == other_template`，
  这正是「身份按名字兜底」。现在只比 DefId
- `stable_type_hash` / `stable_type_key` 不再把名字混进键
- 增加 `DisplayContext` + `def_id_spelling(def_id)`（Koral 没有模块级 `mutable`，
  所以把可变状态放进不可变绑定里）—— 这是 Swift 的 ambient context 的对应物
- `trait_conformance_target_matches*` 从比模板**名字**改成比模板**声明**

**没做完的**：约 800 个模式点里还剩约 50 处的名字读取没接上
（`template` / `template_name` / `trait_name` / `name` 等），
以及若干处构造器/模式的字段数对不上。这些是机械收尾，但不能再用盲改脚本 ——
前几轮脚本把 `let x = ...` 的绑定名也替换掉了，反复打架。

> 教训：**Koral 的 `when`/`is` 模式是隐式绑定（不用 `let`），且 `is` 不允许绑定**；
> 而 Swift 是 `case .x(let a, let b)`。同一个改动在两边的机械修法完全不同，
> 盲改脚本必须按语言分开写。

### 第 3 步 注册表 DefId 主键

**部分完成**（跟着第 2/4 步顺带做的）：

- bootstrap `GenericTemplateRegistry` 加了 `struct_templates_by_def_id` /
  `enum_templates_by_def_id`，`struct_by_def_id` / `enum_by_def_id` 按声明查
- Swift 同构的 `structTemplate(forDefId:)` / `enumTemplate(forDefId:)`
- mono 的实例化路径已改用它们

**没做**：裸名兜底改走 import 解析（`DefIdMap` 的全局裸名表仍在）；
Swift 的 `traits` 还没有 DefId 索引。

## 13. 当前状态（2026-10-01 会话末）

```
工作树        未提交（No Auto Commit）
Swift         557/557  ✅ 第 2 步完成（Type 无名字字段，诊断不变）
⚠️ bootstrap  编译不过（第 2 步剩约 50 处名字读取 + 字段数收尾）
              —— 本轮未能跑 stage1 / 自举 / stage2
上一轮基线    全链绿 557×3 + FIXED POINT + 0 悬空（第 1/4 步 + 注册表 DefId 索引）
```


## 14. 第 2 步收尾 + 两个回归（2026-10-01）

第 2 步（`Type` 去名字字段）在 bootstrap 侧手工改完约 91 处后能编译，
但测试套挂了。两个根因，都不是身份问题，是「显示上下文没接上」和
「布局判定与结构体定义不一致」。

### 14.1 `d19`：环境显示上下文从未接线

**症状**：`std/traits.koral: missing trait info for d19`、`Trait 'd19' not found`、
`Undefined trait: d19`。`d19` 是 `def_id_spelling` 在查不到名字时的兜底串
`"d\(def_id.id)"`。

**根因**：`set_display_context` 在 `typed/types.koral:17` 定义了，**但全库没有任何调用点**。
于是 `display_context.map` 恒为 `None`，`def_id_spelling` 对**每一个** DefId 都返回
`d<id>`。凡把它当解析键用的地方（`resolve_trait_registry_method_signature` 等）全部查空。

**修法**：在 `TypeChecker.new` 里装上 `set_display_context(context.def_id_map)`，
与 Swift 的 `SemanticErrorContext.currentCompilerContext = context`
（`TypeChecker.swift:1068`）和 rustc 的 thread-local `tcx` 一一对应。

> 教训：引入一个环境上下文时，**必须在同一笔改动里接线**。只写 reader 不写 writer，
> 编译器照常编译，坏掉的是所有下游查询 —— 与第 2 步之前「加了 `Type.unknown`
> 却没改每个构造点的失败路径」是同一类错误。

### 14.2 `no member named 'tag'`：niche 判定读了模板的 case 列表

**症状**：自举第 1 轮 emit-c 出的 C 编不过：
```
error: no member named 'tag' in 'struct Option_Koralc_DefIdMap_d241'
    _t160952.tag = 0;
```

**根因**：两处用了**不同**的 case 列表，判定结论相反。

| 谁 | 读哪份 case | 结论 |
|---|---|---|
| `generate_enum_declaration` | 实例化后的（payload = `DefIdMap`） | 有 niche，**不写** `tag` |
| `enum_niche_layout_for_type` | **模板**的（payload = 未实例化的 `T`） | `has_null_niche(T)` 为假 → 「无 niche」→ 构造写 `.tag = 0` |

`concrete_enum_cases_from_def` 见到未解析泛型就返回 `None`，于是「查不到 niche」
和「真没有 niche」混为一谈 —— 后者走 tag 布局，前者应该去看实例化后的声明。

函数自己的注释写的是「泛型实例化会先解析到具体布局的 case 列表」，代码却传了模板。
Swift 侧同名函数的注释写的是「模板」，与它（同样读模板的）代码一致。

**修法**：`.GenericEnum(_, _)` 先经 `find_type_def_id_by_layout_or_template(t)`
解析到**实例的布局声明**，再从那份声明读 case —— 与同文件 `enum_case_info`
（`codegen_mir.koral:2672`）和 `register_type_declaration_for_used_type`
（`codegen_types.koral:116`）已有的做法一致。不是新引入的解析路径，是把这一处
对齐到同一份声明。

**Swift 侧无此缺陷**（已核实，不是假设）：Swift 的 codegen 只见单态化后的
`.enum(defId)`（`CodeGenMIR.swift` 里根本没有 `genericEnum` 分支），
对 `Option[DefIdMap].None()` 发的是 `_t44452.data.Some.value.ptr = NULL;`，
正是 niche 编码。两边因此在**行为**上对齐了；表示层的差异（Swift 单态化出新 DefId
vs bootstrap 携带 `GenericEnum(template_def_id, args)`）是另一件事，记在 7.2。

### 14.3 看护

新增 `tests/compiler-cases/generic_enum_managed_payload_niche_regression.koral`：
泛型枚举 + managed 名义 payload（`type mutable NicheCell(mutable data List[Int])`）
+ 全局初始化里构造 `.None()`。

**验证过它真的能抓回归**（不是想当然写的）：把修法临时回退重编，
测试编译失败，报的就是同一句
`no member named 'tag' in 'struct Option_..._NicheCell_d49'`，编译器退出码 1。
修法恢复后 PASS，Swift 侧也 PASS。

### 14.4 当前状态（2026-10-01，本节末）

```
工作树    未提交（No Auto Commit）
套件      558/558  ×3（Swift / stage1 / stage2）—— 新增 1 条回归用例
自举      FIXED POINT + 0 悬空
第 2 步   ✅ 完成（Type 无名字字段，诊断一字未改）
```

剩余（第 3 步）：

- 裸名兜底改走 import 解析（`DefIdMap.genericStructTemplates[name]` 全局裸名表仍在）
- Swift 的 `traits: [String: TraitDeclInfo]` 还没有 DefId 索引（bootstrap 有）
- 7.8 列的 8 处解析边界名字匹配：注释 + 出处已补，待最终复核

## 15. 第 3 步推进：清掉剩余的名字兜底与名字绕路（2026-10-01）

在第 2 步收尾之后，把「应该按 DefId 走却还在绕名字」的逻辑逐处清掉。
全部手工一处一处改，每处先读上下文再改，不跑正则。

### 15.1 删掉的名字兜底（`不要用名字来兜底`）

**`compiler_context.koral` 六处**（`requires_managed_nominal_layout_type` 的
`.GenericStruct` / `.GenericEnum` 分支，各三处）：

```kotlin
let resolved_template_def_id = if template_def_id.is_valid() then template_def_id
    else self.def_id_map.lookup_generic_*_template_def_id(def_id_spelling(template_def_id))
        or else def_id_invalid();
```

兜底只在 `template_def_id` **无效**时才跑，而无效 DefId 的 `def_id_spelling` 是
`"d0"`，查表永远查不到 —— 死代码。更糟的是它教坏后来人：身份丢了可以靠名字找回来。
改成 `let resolved_template_def_id = template_def_id;`，并注明「无效即错误态，
名字找不回来」。

**`type_checker_expressions_static_calls.koral`** 的 `generic_struct_template_def_id(name, def_id)`
同样是「有效就用 DefId，否则按名字查」，且两处调用点传的名字是
`def_id_spelling(无效 DefId)` = `"d0"`。连同它服务的
`generic_struct_type_parameter_names` 一起改：参数从 `(name, def_id)` 收成 `(def_id)`，
两个来源都按 DefId 查（`get_type_arguments(def_id)` / `struct_by_def_id(def_id)`）。
顺带把 `infer_generic_struct_constructor_return_type_for_def_id` 里被白传一路的
`template_name` 参数删掉（两处调用点都在送名字，函数体内早已不用）。

### 15.2 删掉的 DefId → 名字 → DefId 绕路

按名字查回来的正是手里那个 DefId —— 绕一圈只会丢：

| 位置 | 原来 | 现在 |
|---|---|---|
| `type_checker_decls.mark_explicit_drop_conformance` | `lookup_struct(def_id_spelling(tplDefId))` 再取 `template.def_id` | `set_explicit_drop(tplDefId)` |
| `type_checker_expressions` 成员访问（3 处） | 同上绕路拿字段表 | `struct_by_def_id(tplDefId)` |
| `mono_functions` 占位类型实例化 | `lookup_struct(def_id_spelling(...))` | `struct_by_def_id(...)`（紧邻的 `.GenericEnum` 分支本来就是这么写的） |
| `type_checker_expressions_lowering.type_construction_symbol_for_type` | 查注册表取 `template.def_id`，查不到就**另铸一个新 DefId** | `Symbol(tplDefId, ...)` |

最后一行最值得记：查不到时 `allocate_unindexed_def_id(def_id_spelling(tplDefId))`
会给同一个类型铸出**第二个身份** —— 两次构造同一个 `Box[Int]` 会拿到两个不同的
DefId。类型手里已经有 `tplDefId`，它就是身份（rustc 的 `Ty::Adt` 一直带着 `DefId`）。
非泛型那一支（标量/集合，本来就没有声明）保留铸占位 DefId，名字只作显示。

### 15.3 `cache_key` 里的名字（身份键被名字污染）

`CanonicalTraitRef.cache_key()` 是 `"<def_id>#[args]<trait_name>"` —— **名字在身份键里**。
它自己的注释写着「`trait_name` exists only so diagnostics and C-mangling can print it」，
与实现矛盾。

实际后果已经能在调用点看到：`mono_type_resolution.koral:1439` 用**源拼写**
`trait_name` 建键，`6729` 用 `def_id_spelling(trait_def_id)` 建键。两者一旦不同
（导入别名、限定路径、或 `def_id_spelling` 落到 `d<id>` 兜底），witness 就查不到，
`mir_lowerer` 的 vtable 请求落空。

改成只含 DefId + 类型实参。名字从身份键里彻底消失，两个调用点**由构造而一致**，
不再依赖「大家碰巧拼得一样」。诊断一字未改（套件断言精确串，558/558 证明）。

> 判断标准：**身份键里不许出现名字**。名字只在显示与 C 改编名里出现。
> 键里多一个名字，永远只能「把一个声明拆成几个键」，不可能区分出 DefId 区分不了的东西。

### 15.4 删除的死状态

`DefIdMap.generic_struct_template_def_ids` / `generic_enum_template_def_ids`
（裸名 → DefId 全局表）在上面这些兜底删掉后变成**只写不读**，连同两个访问器一并删除。
注意这不是对称删除：Swift 的 `DefIdMap.genericStructTemplates` 仍然活着，它是 Swift
那一侧**解析边界**的索引（`lookupGenericStructTemplate` 等93 处），是正当的；
bootstrap 的解析边界索引在 `GenericTemplateRegistry`，这份是重复的死表。

### 15.5 审计

```
身份键里出现名字                            0
DefId → 名字 → 名字表查回                   0
名字兜底（身份丢了靠名字找）                 0
裸名 → DefId 全局表                        0
名字 → 声明（解析边界，正当）        bootstrap 33 / Swift 93
探针 / hack                                 0
```

### 15.6 状态

```
工作树    未提交（No Auto Commit）
套件      558/558 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

## 16. 第 3 步推进：trait / 模板的 DefId 索引 + Drop lang item 收敛（2026-10-01）

### 16.1 「按名字的表里扫 DefId」不是身份匹配，但是错的索引

两处都在用**名字键**的表做身份判断：

| 位置 | 原来 |
|---|---|
| bootstrap `lookup_trait_by_def_id` | `for entry in self.traits` 扫名字表比 `def_id` |
| bootstrap `lookup_function_by_def_id` | 同上 |
| Swift `structTemplate(forDefId:)` / `enumTemplate(forDefId:)` | 同上 |
| Swift `MonomorphizerFunctions:2046` | `traits.values.contains { $0.defId == ownerDefId }` |

比的是 DefId（身份对），但索引是名字表。名字表在重名下是 last-wins，
扫它既 O(n)，又看不见输掉那次重名竞争的条目。

bootstrap 的 `trait_decls_by_def_id` **早就建好了却没被用**。补齐用法，并给
`function_templates` 也加 `function_templates_by_def_id`；Swift 侧给
`structTemplates` / `enumTemplates` / `traits` 各加一个 DefId 索引。

> 关键点：Swift 的 `getAllGeneric*Templates()` 同时写**裸名**和**模块限定名**两个键，
> 所以 `values` 是无损的 —— 从它建的 DefId 索引是同一批声明的另一个视图，
> 不是第二份事实。这一点写进注释了，免得后人当成冗余删掉。

### 16.2 Swift 的 `traits` 一直没有 DefId 索引（bootstrap 有）

`TypeChecker.traits` / `qualifiedTraits` 只有名字键，写入点是
`TypeCheckerPasses:855`。在那里补 `traitDeclsByDefId[traitInfo.defId] = traitInfo`，
并**从源头**一路带下去（`GenericTemplateRegistry` → `MonomorphizedProgram` →
`MIRProgram`），而不是各自从名字表反推 —— 从名字表反推会继承它的 last-wins 损失。

改掉的按名字取 trait 声明（手里明明有 DefId）：

- `TypeCheckerTraits:305,359` —— `traits[actual.traitName]`，`actual` 是
  `CanonicalTraitRef`，本来就带 `traitDefId`
- `TypeCheckerTypeResolution:592` —— 同上（这一处是**解析边界**，名字查找合法，
  但已有 DefId 时不该再读名字；诊断文案仍是拼写，一字未改）
- `MIRLowerer:220` —— `program.traits[traitRef.traitName]`

### 16.3 `Drop` 从 4 份解析收敛成 1 个 lang item

计划文件里点过名的问题（"`is_std_drop_trait` 有三份、语义各不同"）。Swift 侧原状：

| 位置 | 解析方式 | 问题 |
|---|---|---|
| `TypeChecker.stdDropTraitDefId` | `traits["Drop"]` + `modulePath == ["Std"]` | 正确，是基准 |
| `CodeGen.isStdDropTraitDefId` | 自己再查一遍 `mirProgram.traits["Drop"]` + 模块判断 | 重复 |
| `MIRLowerer.isStdDropTraitConformance` | 自己再查一遍 + 模块判断 | 重复 |
| `MonomorphizerTypes` ×2 | `traits["Drop"]?.defId` | **没有模块判断** |

最后一行是真缺陷：用户自己声明一个 `trait Drop` 就会被当成 std 的 Drop。
而且 `entry.conformanceTraitDefId == stdDropDefId` 在 lang item 查不到时是
`nil == nil` → **为真**，任何没挂 trait 的 `drop` 方法都会被误匹配。

收敛到 `CompilerContext.stdDropTraitDefId`，与已有的 `stdStringDefId` /
`stdRuneDefId` 同一 lang-item 形式（`(module, name)` 唯一，对应
`rustc_hir::LangItem::Drop`）。四处都改成比这一个 DefId，
`MonomorphizerTypes` 顺带修掉 `nil == nil`。

bootstrap 侧本来就是这个模型（`def_id_map.std_drop_trait_id` +
`set_std_drop_trait_def_id`），本次不动。

### 16.4 审计

```
身份键里出现名字                            0
名字表里扫 DefId 做身份判断                  0
Drop 的独立解析器                     1 处（注释里说明为何不用），活代码 0
DefId 索引   Swift 3 个 / bootstrap 4 个
```

### 16.5 状态

```
工作树    未提交（No Auto Commit）
套件      558/558 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

**剩余**：解析边界那 33 / 93 处「名字 → 声明」改成走 import 解析
（`Scope.getAllGeneric*Templates()` 仍然从裸名快照建表）。
这是正当位置上的名字查找，不是身份污染；改的是**解析精度**（别名、限定路径），
不是身份匹配。

## 17. 解析边界改走 import 解析（2026-10-01，**部分完成**）

### 17.1 先造了一个失败用例（没有先改代码）

`mod_a` / `mod_b` 各声明一个形状不同的 `Box[T]`，main 用**裸名**导入其中一个：

```kotlin
using probe::mod_a { Box };        // 故意不加别名
using probe::mod_b { make_b };
let a Box[Int] = make_a_local(1);  // `Box` 必须指 mod_a 的 Box
println(a.value.to_string());
```

**两个编译器都错**，而且是同一个错：

```
error: 'Box' is defined in module 'Probe::ModB'. Import it explicitly with using Probe::ModB { Box }.
```

main 明明 `using probe::mod_a { Box }`，编译器却拿 mod_b 的 `Box` 去比对可见性，
然后说「你没导入它」——**从没考虑过 mod_a 的那个**。bootstrap 更糟：
`Missing positional argument 'more' for 'Box'`，说明它真的拿 mod_b 的两字段 `Box`
去检查 `Box(v)` 的构造参数。

根因：裸名表是**全局 last-wins**（`typeNames[name]` / `struct_templates[name]` /
`genericStructTemplates[name]`），它回答的是「哪个模块最后注册的」，不是「这个模块导入的是哪个」。

### 17.2 修法：导入排在裸名之前

解析顺序（这是全部要点）：

1. 本模块自己的声明（模块限定键）
2. **符号导入**（`using m { x }`；`using m { x as y }` 时本地拼写是 `y`、声明叫 `x`）
3. **批量/模块导入**（`using m { .. }`、`using m;`）—— 不产生符号边，两边拼写相同
4. 裸名键

(4) 排最后，并且**不是解析**：那个键跨模块 last-wins，回答不了「哪个 `Box`」。
它保留下来只为一件事——名字在别处有声明但此处没导入时，仍能报
`... is defined in module 'M'. Import it explicitly`。
（`generic_template_requires_import_error_test` 断言的就是这句，一字不能变。）

rustc_resolve 就是按模块的导入表建解析结果，根本没有可回退的全局名表。

### 17.3 Swift 侧：✅ 完成并验证

- `Scope.bindingViaImport` / `typeViaImport` —— 值与类型两条路径都插在裸名查找之前
- `DefIdMap.importedTemplateDefId` —— 泛型模板同样处理
- **`DefIdMap.sharedImportGraph`**：导入图是**共享**环境状态，装一次。
  不能挂在某个 `DefIdMap` 实例上——`ConstraintSolver` / `BidirectionalInference`
  各自 `CompilerContext()` 新建自己的 map，必须所有实例给同一个答案。
  与 `SemanticErrorContext.currentCompilerContext` 同一类环境状态。
- import 边带 `sourceFile`（`using` 所在文件），匹配时必须比对文件
  （同 `ImportGraph.getImportKind` 的规则）—— 这一点一开始漏了，导致全部匹配失败。

验证：

```
探针    Swift: 1 / 2  ✅（a.value=mod_a 的 value，b.extra=mod_b 的 extra）
套件    Swift 558/558  ✅（含 generic_template_requires_import_error_test）
```

### 17.4 bootstrap 侧：⚠️ 部分完成

已做：

- `struct_templates` / `enum_templates` 补**模块限定键**（原来只有裸名）
- `GenericTemplateRegistry.candidate_keys` 按上面的 1→4 顺序出候选键，
  `resolve_struct_name` / `resolve_enum_name` / `resolve_function_name` /
  `resolve_trait_name` 都改用它
- registry 加 `current_module_path` / `current_source_file` / `current_import_graph`
  环境上下文，由 `TypeChecker.install_name_resolution_context` 在切模块时装上

**未做**：探针在 bootstrap 上仍然失败。构造器那条路**不经过**
`resolve_struct_name` —— 调试输出显示 `candidate_keys("Box")` 从未被调用。
构造参数表走的是 `resolve_static_call_param_specs(type_name, ...)`，
而 `type_name` 是**拼写**（`def_id_spelling(template_def_id)`），再经
`method_owner_for_name` 回到裸名表。还有 `try_resolve_named_type_without_diag`
里 `global_scope.lookup_type_in_module` / `resolve_imported_alias_type` 等
几张表，需要按同样的 1→4 顺序过一遍。

### 17.5 回归用例**暂未入库**

`generic_enum_managed_payload_niche_regression` 那次是先入库再验证能抓回归的。
这次的 `bare_import_same_name_type`（即 17.1 的探针）**故意没放进
`tests/compiler-cases/`**——它在 bootstrap 上会失败，入库会把套件打红。
等 17.4 做完、两个编译器都过，再入库并回退验证（确认它真能抓回归）。

### 17.6 状态

```
工作树    未提交（No Auto Commit）
套件      558/558 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

## 18. bootstrap 侧收尾：解析改走 import 解析（2026-10-01，✅ 完成）

接着 17.4。构造器那条路的排查结论：`resolve_static_call_param_specs` **不是**
元凶——调试输出显示它根本没被 `Box` 调用过。真正的漏点有两处，都在**类型解析**。

### 18.1 漏点一：`resolve_imported_alias_type` 拿不到类型

它已经是对的形状（按 import 边找 `entry.target` / `entry.original_symbol`），
调试也证明边匹配上了：

```
[DBG] alias Box: candidates=1 cur=[Probe] file=Some(.../probe.koral)
[DBG]   cand module=[Probe] target=[Probe, ModA] sym=Box orig=Box sf=Some(.../probe.koral)
```

但它返回 `None`。原因：找到 DefId 之后读的是 `get_symbol_type(def_id)`，
而**泛型模板的 DefId 没有 symbol_type**——它是「等着填类型实参的声明」，
不是单态值。读不到就当没找到，一路掉进下面的 last-wins 名字表。

修法：按声明的 `kind` 造类型（`GenericTemplate(Structure())` → `StructureType(def_id)`），
与旁边 `lookup_current_file_type_symbol` 已有的做法一致。抽出
`type_for_declared_def_id` 两处共用。

### 18.2 漏点二：`Scope.lookup_type_in_module` 的裸名回退

```kotlin
type_entries.get(qualified)   // 1. 模块限定键 —— 对
type_entries.get(name)        // 2. 裸名键 —— 跨模块 last-wins ✗
```

(2) 插在 (1) 后面、又没有 import 这一层，于是「本模块没声明、也没导入」
和「本模块没声明、但导入了 mod_a 的」混成一件事，后者被 mod_b 抢走。

按 17.2 的顺序补上 import 这一层（`imported_type_entry`）：符号导入边
（比 `entry.symbol == name`，并按 `source_file_matches` 过滤文件）→ 批量/模块
导入边 → 最后才裸名键。`Scope` 加 `import_graph` / `source_file` 环境上下文，
由 `TypeChecker.install_name_resolution_context` 与 registry 的一起装上。

### 18.3 回归用例已入库

`tests/compiler-cases/bare_import_same_name_type/`（多模块，`mod_a` / `mod_b`
各一个形状不同的 `Box[T]`，main 裸名导入 mod_a 的）。

**验证过它真能抓回归**（不是想当然写的）：把 18.2 的 import 层与 18.1 的
`type_for_declared_def_id` 一并回退重编，测试编译失败，报的就是注释里写的那句

```
error: 'Box' is defined in module 'BareImportSameNameType::ModB'. Import it explicitly ...
```

修法恢复后 PASS。

> 记一笔：这两处对该用例是**互相冗余**的——只回退其中一处，测试仍然过
> （另一处兜住了）。所以只回退单点不能证明回归被抓住；两个都回退才失败。
> 防御纵深，但看护用例必须按「两个都坏」来验证。

### 18.4 状态

```
工作树    未提交（No Auto Commit）
套件      559/559 ×3（Swift / stage1 / stage2）—— 新增 1 条回归用例
自举      FIXED POINT + 0 悬空
诊断      一字未改（generic_template_requires_import_error_test 仍断言
          "Import it explicitly with using"，未变）
```

解析边界的「名字 → 声明」现在按 **本模块声明 → 符号导入 → 批量导入 → 裸名**
出候选，裸名排最后且只服务于「没导入时怎么报错」。身份仍然只在 DefId 上。

## 19. 收尾（2026-10-01）

对 7.9 的四条验收判据与 §7 的「其它收敛目标」逐条核对后收尾。

### 19.1 Swift `CanonicalTraitRef.cacheKey` 仍在键里放名字（真缺陷，已修）

§15.3 我报「身份键里出现名字 = 0」——**那只对 bootstrap 成立**，Swift 漏了：

```swift
public var cacheKey: String { "\(traitDefId.id)#\(description)" }   // description 含 traitName
```

与 §15.3 在 bootstrap 修掉的是同一缺陷。改成与 bootstrap 同形
（`defId` 或 `defId#[args]`），实参走 `Type.stableKey`。

### 19.2 顺带查出两处相关缺陷（一并修）

**(a) `Type.stableKey` / `stableHashKey` 也折了名字。**
`"GS(\(Type.spelling(defId)))#\(defId.id)[...]"` —— DefId 已经在键里了，
名字是纯冗余，只可能把一个声明拆成几个键。三处 `stableKey` +
三处 `stableHashKey` 的 `Type.spelling` 全部去掉。

**(b) `Type.==` 的名字兜底是个恒真式。**

```swift
if lDefId.isValid && rDefId.isValid { return lDefId == rDefId }
return Type.spelling(lDefId) == Type.spelling(lDefId)   // 自己比自己，永真
```

注释写着「fall back to the name」，实现却是左比左。后果：任一侧身份未解析时，
**任意两个**不同的泛型模板判等。三处（`genericStruct` / `genericEnum` /
`traitObject`）都改成 `return lDefId == rDefId` —— 不是把名字补回来
（名字不该在这里），是比较身份。

> 教训：名字兜底本身就是错的，所以「修好它」也不该是恢复成
> `l == r` 的名字比较。而恒真式能活下来，正因为没有用例覆盖
> 「一侧身份未解析」这条路。

### 19.3 `Scope.new_generic_child` 死代码：已删

零调用点。

### 19.4 `primitive_extension_template_name`：评估为**保留**

`mono_functions.koral`，两组调用点（`type_satisfies_trait_constraint` 与
占位类型实例化）都在用，不是死代码。

它把 `Type.IntType()` 桥接成内置空间里的名字，用于找声明在 `Int` / `Bool` …
上的扩展方法。**这不是身份意义上的名字匹配**：标量与修饰符没有声明、没有 DefId，
它们的身份就是有限封闭集合里的槽位——与 rustc 的
`rustc_middle::ty::fast_reject::SimplifyType` 及其喂给的 `incoherent_impls`
同一机制，`MethodOwner.Builtin(name)` 亦然。用户类型进不了这个集合，名字撞不上。
已补注释与出处。

### 19.5 判据 3 的字面达成情况：⚠️ 仍是「部分」

`structTemplates: [String: ...]` / `struct_templates Dict[String, ...]` 作为
**注册主键**仍在。但核对下来：

- 身份查找全部走 DefId 索引（`structTemplate(forDefId:)` / `struct_by_def_id`
  等，全库 50 处调用）
- 无任何「拿名字表条目比 DefId」的身份判断
- 裸名兜底已改走 import 解析（§17–18）

名字表只承担「拼写 → 声明」这一件事，那是解析边界，属正当。
要字面达成「主键为 DefId」得把名字表降成由 DefId 表派生的视图，是纯整理、
不改正确性，没做。

### 19.6 审计（修正 15.5 的口径）

```
身份键 / 稳定键里出现名字
  CanonicalTraitRef.cacheKey / cache_key        0  ✅（本轮修）
  Type.stableKey / stableHashKey                0  ✅（本轮修）
  其它 cache key 用 (module, name) 限定键        4  ⚠️ 等价于 (module,name) 身份
  其它 cache key 用裸名                          2  ⚠️ 真名字匹配
Type.== 名字兜底                                 0  ✅（本轮修，原本是恒真式）
Type.spelling / def_id_spelling 进入比较        32  ⚠️ 类型节点模式匹配的解析边界
死代码（new_generic_child / is_std_drop_trait_conformance）  0  ✅
```

**没做完的两类**（本轮不在计划内，记下）：

1. 两个裸名 cache key：`TypeCheckerTypeResolution.swift:585`
   `"\(baseName):\(traitName)"`（blanket given 缓存）、
   `mono_functions.koral:624` `"\(trait_name)|\(method_name)|..."`。
   重名 trait 跨模块会撞同一个槽。
2. 32 处 `Type.spelling` / `def_id_spelling` 进比较 —— 把源里的类型节点模式
   与实例化后的类型配对时按拼写比。这是解析边界（源语法 → 声明），但更对的
   做法是解析期就把类型节点定成 DefId 再比身份。

### 19.7 状态

```
工作树    未提交（No Auto Commit）
套件      559/559 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

## 20. 清掉 §19.6 的两类（2026-10-01）

### 20.1 类一：裸名 cache key —— ✅ 两处都改

| 位置 | 原来 | 现在 |
|---|---|---|
| `TypeCheckerTypeResolution.findBlanketGivenConstraints` | `"\(baseName):\(traitName)"` | `"\(baseName):\(traitDefId.id)"` |
| `mono_functions` trait-tool 模板缓存 | `"\(trait_name)\|\(method_name)\|..."` | 先 `trait_owner_by_name` 定身份，键成 `"d<id>\|..."` / `"b:<builtin>\|..."` |

值里保留的约束名**不改**：它在 `enforceTraitConformance` 处是解析边界，
诊断也按拼写打印。键撞车才是缺陷。

### 20.2 类二：拼写进比较 —— 其中 **11 处恒真式**已修（真缺陷）

清的过程中发现类二里混着一类比「名字匹配」更糟的东西：**同一绑定自己比自己**。

```kotlin
.GenericStruct(tplDefId, pattern_args) then when actual in {
    .GenericStruct(tplDefId, actual_args) then {          // 内层 tplDefId 遮蔽外层
        if def_id_spelling(tplDefId) == def_id_spelling(tplDefId) then {   // 恒真
```

`when` 的分支是**绑定**不是相等约束，内层把外层的 `tplDefId` 遮蔽了。后果：
**任意两个泛型模板都判为匹配**——两个模板的身份从来没比过。

Swift 侧同形，只是写法换成把一侧丢成 `_`：

```swift
case (.genericStruct(let tplDefId, let expectedArgs), .genericStruct(_, let actualArgs)):
  guard Type.spelling(tplDefId) == Type.spelling(tplDefId) && ...   // 恒真
```

修法：内层改绑 `actual_def_id`，比较改成 `tplDefId == actual_def_id`
（Swift 侧把 `_` 换成 `let actualDefId` / `let pDefId`）。名字不补回来——
名字本就不该在这里，要比的是身份。

| 文件 | 处数 |
|---|---|
| `mono_type_resolution.koral` | 5 |
| `mono_expr_substitution.koral` | 1 |
| `TypeChecker.swift` | 3 |
| `TypeCheckerMethods.swift` | 2 |
| **合计** | **11** |

> 与 19.2(b) 的 `Type.==` 恒真式是同一批暗伤，都出自更早那次盲改。
> **没有用例能分辨**：修完 559/559 与修前一致，说明「两个不同模板不该匹配」
> 这条路全库没有断言看着。跨模块用例走的是别的检查路径。

### 20.3 类二剩下的 21 处：⚠️ 是结构性问题，没做

恒真式清完后剩 21 处，全部形如 `def_id_spelling(template_def_id) == type_name`
（`type_name` / `base` / `trait_name` 来自**源里的类型节点**）。已带注释标明是
解析边界。

**要真正清掉，不是把这 21 行换个写法**——把名字查找搬到比较处只是挪位置。
正确做法是：**解析期就给模式里的类型名定好 DefId 并随模式携带**，这里直接比身份。
那要动 `Pattern` / `TypeNode` 的表示，与 7.9 第 2 步「`Type` 去名字字段」同量级。

写成 `resolve(type_name) == template_def_id` 反而更糟：在匹配热路径上再做一次
名字解析，且若不带上模式所在模块，仍会撞 last-wins。所以**留着，不动**，
等做「解析期定 DefId」那一轮一起改。

### 20.4 状态

```
工作树    未提交（No Auto Commit）
套件      559/559 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

```
裸名 cache key                       0  ✅
恒真式（X == X）                      0  ✅
身份键 / 稳定键含名字                  0  ✅
拼写进比较（解析边界，待结构性改造）    21  ⚠️
```

---

## 21. 结构性改造：21 处拼写比较清零

20.3 说「留着，不动」，并判断要动 `Pattern`/`TypeNode` 表示才能清。**判断有一半是错的**：
不必给 `TypeNode` 加 DefId 字段，也不必把名字查找搬到比较处。真正缺的是一件事——
**名字必须在边界处变成身份，而边界一直在，只是没被用作边界**。

### 21.1 支点：形状解析

`resolve_type_node`（mono 侧 `TypeNode → Type`）是**唯一**合法的名字出口，但它会
`instantiate_*`，把 `Box[T]` 物化成布局。匹配要的是**形状**，不是布局。故补一个孪生：

```kotlin
// The `Type` a `TypeNode` denotes as a SHAPE: every nominal base resolved to
// its DECLARATION DefId, every type parameter left symbolic.
public let resolve_type_node_identity(mono, node, type_params) Type
```

不实例化，只定身份。此后匹配器吃的是两个 `Type`，比的是 DefId，**再也见不到名字**。

### 21.2 顺带发现：`collect_generic_bindings_from_type` 是死代码

Type↔Type 版匹配器（上一轮修过其中的恒真式）**只有自递归、无任何外部调用**。
也就是说 20.2 里 11 处恒真式有 1 处修在死代码上——修复本身没错，但那份匹配器
从未生效过。本轮把它变成真正的匹配器（`collect_generic_bindings_from_shape`），
由 `collect_generic_bindings_from_type_node` 解析形状后转调。**净删 215 行死代码**，
两套匹配器合成一套。

同批删掉的还有 `enum_case_params_by_template_name`——按名字反查 `enum_template_names`
的索引，同样零调用。

### 21.3 各簇怎么清的

| 簇 | 原来 | 现在 |
|---|---|---|
| TypeNode↔Type 匹配（mono 8 处） | `base == def_id_spelling(tplDefId)` | 解析成形状后比 DefId |
| 模式里的类型名（sema/mono 8 处） | `def_id_spelling(x) == type_name` | `struct_pattern_def_id(name)` 解析一次，比 DefId |
| conformance 的 Self 绑定（3 处） | `def_id_spelling(x) == trait_name` | `conformance_trait_def_id_named(name)` 一次 |
| 扩展模板按名择项（1 处） | `conformance_trait_name == conformance_trait_name` | `conformance_trait_def_id ==` |
| Swift 对偶（9 处） | `Type.spelling(tplDefId) == name` | `nominalDefId(for:)` / `getTemplateDefId` / `template.defId` |

关键点：**解析一次，多次比身份**。`type_name` / `trait_name` 保留下来只为打诊断。

### 21.4 两处「一次解析」要落到哪张表

非泛型 nominal 在**类型表**，泛型模板在**模板表**，一张表答不了。
Swift 侧 `lookupGenericStructTemplate("Point")` 返回 nil，7 个结构模式用例当场红
（`Type mismatch: expected Point, got Point`）。修成两表都查一次。
bootstrap 同因同修，抽出 `mono_nominal_from_declared_name` 供形状解析与模式解析共用，
免得两处再各自长歪。

顺手清掉 `nominalDefId(for:)` 里 `lookupGenericStructTemplate(Type.spelling(tplDefId))?.defId`
这种 **DefId→名→DefId 往返**：`genericStruct(tplDefId, _)` 本来就带着答案。

### 21.5 为什么不是「给 TypeNode 加 DefId 字段」

20.3 的方案要动 `TypeNode`/`Pattern` 表示并让所有构造点填 DefId。但 `TypeNode` 是
**语法**，在解析期还没有 scope 可查——DefId 只能在 sema 填，而 sema 填完就该产出
`Type`。`Type` 早就在做这件事了。所以正确的一步是**让匹配器吃 `Type`**，
而不是给语法节点塞一份半生不熟的解析结果。

### 21.6 审计

```
裸名 cache key                        0  ✅
恒真式（X == X）                       0  ✅
身份键 / 稳定键含名字                   0  ✅
拼写进身份比较（sema / mono / Swift）    0  ✅
DefId→名→DefId 往返                    0  ✅
```

**还剩两类，性质不同，不在本轮：**

| 类 | 位置 | 性质 |
|---|---|---|
| Drop 的 C 名匹配 | `codegen_generate.koral:254,275`、`CodeGen.swift:1668,1693` | `emitted_type_c_name_fallback(x) == type_name` —— **mangling 桶**，按规则合法；但 `is_std_drop_trait` 有三份实现待收敛（计划第 7 项） |
| codegen/MIR 按名字分发 trait | `program.traits.get(trait_name)` ×10、`conformance == trait_name` ×3 | **名字键索引 + 名字当身份**。`resolve_method_def_id` 手里**已有** `trait_def_id` 却把名字往下传。`ConcreteCallableInfo` 也已带 `trait_conformance_def_id`。是真缺陷，但整条 codegen 分发链要一起改 |

### 21.7 状态

```
工作树    未提交（No Auto Commit）
套件      559/559 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

---

## 22. codegen/MIR 按名字分发 trait + Drop 收敛

21.6 留下的第二类。**`resolve_method_def_id` 手里已经有 `trait_def_id`，却把 `trait_name`
往下传**，下游用名字比对 `info.trait_conformance` / `Given` 的 trait——同名 trait 会互相吞方法。

### 22.1 索引：`MIRProgram` 只有名表

`TraitDeclInfo` 一直带 `def_id`，但 `MIRProgram.traits` 是 `Dict[String, ...]`，
拿身份也得先转回名字。补一张对偶索引：

```kotlin
// Declaration identity -> declaration. Anything asking "is this the trait X"
// reads here: two same-named traits from different modules are different traits.
traits_by_def_id Dict[UInt, TraitDeclInfo],
```

`MonomorphizedProgram` 不必再存一份——它本来就带 `generic_templates`，
`trait_by_def_id` 直接转调已有的 `lookup_trait_by_def_id`。**索引不再有第二份事实。**

### 22.2 换掉名字比对

| 位置 | 原来 | 现在 |
|---|---|---|
| `lookup_trait_method_def_id` | `info.trait_conformance == trait_name` | `info.trait_conformance_def_id == trait_def_id` |
| `lookup_trait_method_def_id_from_given_globals*` | `conformance <> trait_name` | `given_id <> trait_def_id` |
| `trait_member_type_bindings` | `trait_info(trait_name, ...)` | `trait_by_def_id` |
| `collect_instantiated_trait_members*` | 递归传 `parent.name` | 递归传 `parent_def_id` |
| visit key（cycle 打断） | `qualified_symbol_key(path, name)` | `spelling#<def_id>` |
| `type_looks_traitlike_for_storage` | `traits.get(get_name(def_id))` | `trait_by_def_id(def_id)` |

**visit key 是真缺陷**：两份同名 trait 共用一个 visit 槽，后来的那份当「已经访问过」被跳过，
vtable 少方法。

### 22.3 `register_given_members_def_ids` 自己绕回了名字

参数里明明有 `trait_conformance_def_id`，`ReceiverMethodDispatchInfo` 那段却又
`trait_registry.get(trait_name)` 重查一遍——**身份→名→身份往返**。删掉重查，直接用参数。

### 22.4 Drop 收敛（计划第 7 项）

原来三份：sema 的名字版（**铸造点**：读一次 `"Drop"` 拼写，记下 DefId）、
codegen 的身份版、mono 的**第三份重新按名字推导**的版本。

mono 那份删掉，统一走 `context.is_std_drop_impl_def_id`。现在的分工与 rustc `LangItem` 一致：

```
is_std_drop_trait("Drop")     读拼写、定身份（唯一的名字出口）
is_std_drop_impl_def_id(id)   比身份（全部下游）
```

`is_std_drop_trait_conformance` 死代码已在别处清掉。Swift 侧本来就是
`isStdDropTrait(_ defId: DefId?)`，无需改。

### 22.5 顺带删掉的死代码

- `get_ordered_raw_trait_members` —— 只自递归，被 DefId 版行走取代
- `resolve_trait_member_for_vtable` / `resolve_trait_members_for_vtable` —— 活的是 `_with_bindings` 版

### 22.6 审计

```
名字当身份（sema / mono / codegen / mir / Swift）      0  ✅
DefId→名→表 / DefId→名→DefId 往返                     0  ✅
恒真式（X == X）                                      0  ✅
裸名 cache key                                        0  ✅
```

**还剩三类：**

| 类 | 位置 | 性质 |
|---|---|---|
| `ParentTraitConstraint` 只有名字 | `trait_checker.koral:10` | 父 trait 遍历**被迫**先解析名字。真修法是给它加 `def_id`（计划第 5 项「trait 身份换 DefId」） |
| `trait_info(name, path)` ×3 | codegen_vtable / mir_lowerer / mir_verifier | **名字→声明解析，合法边界**，只是三份重复。收成一份是整洁问题 |
| Drop 的 C 名匹配 | `user_defined_drop_type_key == type_name`、`dropOwnerTypeName == typeName` | **mangling 桶**。布局键已按声明盖戳（`Box_I_d184`）；这两处是拿盖过戳的 C 名当句柄 |

### 22.7 状态

```
工作树    未提交（No Auto Commit）
套件      559/559 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

---

## 23. `ParentTraitConstraint` 带上声明身份（计划第 5 项收尾）

22.6 的第一类。`GenericConstraintBound` / `ExplicitTraitConformanceKey` / `GivenTraitDecl`
早就有 `trait_def_id`，**只剩 `ParentTraitConstraint` 只有名字**，于是每处父 trait 遍历
都得先把名字解析回声明。

### 23.1 顺序陷阱：不能在构造时定身份

`collect_signatures` 里 trait 是边走边注册的，父 trait 可能**后面才声明**。
在构造点解析会随声明顺序给出不同结果——正是
「Type identity can't depend on declaration order」那条教训。

代码里其实已经有答案：`validate_trait_parent_existence` 的注释写着
*「Every trait is registered by now, so a parent list can be resolved.」*
——第二个子遍就是链接点。照它做：

```kotlin
public type ParentTraitConstraint(
    name String,                    // display only
    type_arg_nodes List[TypeNode],
    def_id DefId,                   // identity
);
```

1. 构造时能解析就解析（同文件前向声明之外都成立）；
2. `link_parent_trait_def_ids()` 在 trait 子遍之后跑，**回填**仍无效的 DefId；
3. `check_decl` 的二次注册此时全量可见，解析必然正确。

三处收敛到同一个答案，与声明顺序无关。链接时同步改写
`trait_registry` 与 `generic_templates.traits` 两份视图，避免留下不一致。

### 23.2 换掉的名字比对

| 位置 | 原来 | 现在 |
|---|---|---|
| `trait_is_ancestor_of` / `traits_are_related` | 名字递归 + `parent.name == ancestor` | **DefId 递归**，`Set[UInt]` 访问集 |
| `validate_inheritance_graph` | 名字键的 visited/stack | DefId 键；名字只并行留着打印环 |
| 歧义告警 `trait_name <> first_trait` | 名字当身份 | `bound_trait_def_id <> first_trait_def_id` |
| `has_inheritance_internal` | `get_in_module(parent.name)` | `get_by_def_id(parent.def_id)` |
| 父 trait 的类型实参绑定 | `trait_info(parent.name)` | `trait_by_def_id(parent.def_id)` |
| `GenericConstraintBound(...)` | `trait_def_id_of(parent.name)` | `parent.def_id` |
| mono 有序方法名遍历 | 名字键 visit | `..._from_def` 版，DefId 键 |

**visit key 又是真缺陷**：`qualified_symbol_key(module_path, name)` 让同层级里两个同名
父 trait 共用一个访问槽。三处（trait_checker / type_checker_methods / mono×2）一并改。

### 23.3 顺带删掉的死代码

- `check_parent_traits_satisfied[_in_module]` —— 无外部调用；里面的
  `given_trait == parent.name` 是一处纯名字身份比对
- codegen_vtable / mir_lowerer / mir_verifier 三份 `trait_def_id_by_name` —— 父遍历改走
  `parent.def_id` 后再无调用者
- 由此 `trait_info(name, path)` 三份重复只剩一份（codegen_vtable），
  出口只剩 `resolve_vtable_named_type` —— 处理 `TypeNode` 里的标识符名字，**合法的名字解析**

### 23.4 审计

```
名字当身份（sema / mono / codegen / mir / Swift）      0  ✅
DefId→名→表 / DefId→名→DefId 往返                     0  ✅
恒真式（X == X）                                      0  ✅
裸名 cache key                                        0  ✅
```

**还剩两类：**

| 类 | 位置 | 性质 |
|---|---|---|
| 名字键递归助手 ×7 | `collect_ordered_trait_members`、`flatten_methods_in_module`、`trait_declares_requirement_in_trait`、`flattened_trait_tool_methods_in_trait`、`bind_ancestor_trait_type_params_recursive`、`collect_trait_method_bindings_recursive`、`has_direct_explicit_trait_conformance` | 签名收 `String`，递归再按名字查表。身份在**入口**已经用上（拿 `parent_info.name`），只是助手签名还没换成 DefId。属签名整洁 + 访问集去重 |
| Drop 的 C 名匹配 | `user_defined_drop_type_key == type_name`、`dropOwnerTypeName == typeName` | **mangling 桶**；布局键已按声明盖戳 |

### 23.5 状态

```
工作树    未提交（No Auto Commit）
套件      559/559 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

---

## 24. 名字键递归助手收尾 + Swift 往返清理

23.4 的第一类。7 个助手签名收 `String`，递归再按名字查表——**身份在入口已经用上了**
（先取 `parent_info.name`），只是链路还没贯通。

### 24.1 七个助手全部改成按声明递归

统一形状：入口把名字解析**一次**，递归只传 DefId，访问集 `Set[String]` → `Set[UInt]`。

| 助手 | 原来递归传 | 现在 |
|---|---|---|
| `collect_ordered_trait_members` | `(parent_info.name, module_path)` | `(parent.def_id)` |
| `flatten_methods_in_module` | `(parent_info.name, module_path)` | 新增 `flatten_methods_for_def(def_id)` |
| `trait_declares_requirement_in_trait` | `(parent_info.name, ...)` | `(parent.def_id, ...)` |
| `flattened_trait_tool_methods_in_trait` | `(parent_info.name, ...)` | `(parent.def_id, parent.name, ...)` —— 名字只喂诊断 |
| `bind_ancestor_trait_type_params_recursive` | `(parent.name, ...)` | `(parent.def_id, ...)` |
| `collect_trait_method_bindings_recursive` | `(parent.name, ...)` | `(parent.def_id, ...)` |
| `has_direct_explicit_trait_conformance` | `parent.name` 进 key | `parent.def_id` 直接进 key |

`flatten_methods_for_def` 对绑不上的父节点返回空集（沿用原来的 `or else { continue;}`），
"Trait 'X' not found" 只由名字入口产生——诊断一字未改。

顺带：`requirement_slots` 里 `generic_templates.traits.get(current.trait_name)` 是
**DefId→名→表** 往返，`CanonicalTraitRef` 本来就带 `trait_def_id`，改成
`lookup_trait_by_def_id`。

### 24.2 Swift 侧 12 处往返

`currentScope.lookupGenericEnumTemplate(Type.spelling(tplDefId))` 这类写法——
类型带着 `tplDefId`，却先转回名字再查表。`genericStructTemplate(defId:)` /
`genericEnumTemplate(defId:)` 21.4 就加好了，11 处直接换。

第 12 处（`isMutableNominalReceiverType`）是**四层名字兜底链**：

```
genericStructTemplate(defId:)  →  lookupGenericStructTemplate(去限定名)
                               →  lookupType(全拼写)  →  lookupType(去限定名)
```

「DefId 查不到就退名字」正是「不要用名字来兜底」禁止的形状。收成两条身份判断
（模板声明的 `isMutable` + `context.isTypeMutable(tplDefId)`），套件 559/559 未动。

### 24.3 审计

```
名字当身份                                  0  ✅
DefId→名→表 / DefId→名→DefId 往返          0  ✅
恒真式（X == X）                            0  ✅
裸名 cache key                              0  ✅
```

**名字键访问集**还有 7 处 `Set[String]`，但键里都带声明
（`d<id>` / `spelling#<id>` / `CanonicalTraitRef.cacheKey`），同名 trait 不会撞槽。
字符串当键没问题，**键由谁决定**才是问题。

**只剩一类：Drop 的 C 名匹配**（`user_defined_drop_type_key == type_name`、
`dropOwnerTypeName == typeName`）——**mangling 桶**。布局键已按声明盖戳（`Box_I_d184`），
这两处拿盖过戳的 C 名当句柄，按规则合法。

### 24.4 状态

```
工作树    未提交（No Auto Commit）
套件      559/559 ×3（Swift / stage1 / stage2）
自举      FIXED POINT + 0 悬空
诊断      一字未改
```

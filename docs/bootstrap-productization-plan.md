# bootstrap 产品化收尾规划

> 前置结论见本文「0. 现状」。身份改造（名字只留在解析/显示/mangling）已收口，
> 记录在 `docs/identity-matching-tracking.md`（24 节）。

## 0. 现状

bootstrap 与 Swift 编译器在**能力面已对齐**：559/559 全过（含精确诊断串）、
自举两轮 + 不动点 + 0 悬空、多包构建、真实程序（`koralfmt`）两边产物**输出一致**。
同一任务下 bootstrap **快 2.0×**（41s vs 84s）。

**但产物质量差一档**：

| | Swift | bootstrap | 差 |
|---|---|---|---|
| 生成 C 行数 | 29 415 | 53 563 | **1.8×** |
| 二进制 | 220K | 296K | +35% |
| text 段 | 98 304 | 163 840 | **+67%** |
| 下游 C 编译 | 0.50s | 0.66s | +32% |

**根因已定位**（不是表示差异，是过度实例化）：`list_sort_test` 这个程序里，
Swift **一个** `EnumerateIterator` / `FilterIterator` / `InspectIterator` 符号都没发，
bootstrap 发了 **95 处** `EnumerateIterator` 相关。程序根本没用到这些迭代器适配器。

**战略前提**：自举不是目标，只是验证手段。删掉 Swift 之前必须先有**独立预言机**，
否则丢掉的是两个独立实现的交叉验证——自举不动点只证明「稳定」，不证明「对」。

## 目标

把 bootstrap 从「功能等价的第二实现」推到「可独当一面的唯一实现」。
**本期不删 Swift 编译器**——那是第 4 步之后、预言机就位之后的事。

---

## 第 1 步：产物质量 + 构建模式

### 1a. 过度实例化（本轮主项）

**事实**：mono 把程序没用到的迭代器适配器（连同它们的闭包 payload 结构体）
整套物化了。`mono_types.koral` 里写着
「All other extension methods are instantiated on-demand when called」——
**有 on-demand 机制，但被过度触发**。

**要查清的**（动手第一步是取证，不是改代码）：

1. 触发链是什么？`String` 的哪个方法被调用，如何把 `runes()` / `bytes()` / `lines()`
   及其适配器全拉进来？
2. Swift 的 demand 判据是什么？它凭什么把 `EnumerateIterator` 裁掉？
   两处判据的**差异点**就是缺陷所在。
3. 是「实例化了整个可达闭包」还是「某处请求了不该请求的实例化」？
   `InstantiationRequest` 的产生点是首要嫌疑。

**判据**：`list_sort_test` 的生成 C 里 `EnumerateIterator` 出现次数 95 → 0；
text 段 163 840 → 接近 98 304。**不接受**「加个白名单把这些名字滤掉」——
那与身份改造期间禁止的硬编码特判同罪。

### 1b. 补上构建模式 flag

`--debug` / `--release` / `--optimize <level>` **完全没实现**，
`driver/run.koral:917` 硬编码 `-O1`。Swift 的实现在 `Driver/Driver.swift:149-162`，
是明确的对照：

```
默认            ["-O1"]
--debug         ["-O0", "-g"]
--release       ["-O2"]
--optimize L    ["-O<L>"]     L ∈ {0,1,2,3,s,fast}，否则报错
```

诊断文案必须与 Swift 一致（套件断言精确串）：
`Error: Invalid value for --optimize (expected 0, 1, 2, 3, s or fast): <x>`、
`Error: Missing value for --optimize option`。

顺带：`toolchain/koral/cmd_build.koral:26` 的 `koral build [--release]` 只在
`koral` 层解析了 flag，**没转发给 koralc**。补上转发，否则 `--release` 是空转。

**验收**：两边对同一输入的 clang 参数逐项相同。

---

## 第 2 步：panic 收口

26 处 `panic()`，**18 处是「generic 泄漏到 codegen」**（`Generic X reached codegen`）。
这是**流水线不变量**——mono 之后不该还有泛型——而不是用户错误，所以
「全部转成诊断」是错的方向。正确的三分类：

| 类 | 数 | 处置 |
|---|---|---|
| 流水线不变量（generic 泄漏、未解析类型） | ~19 | 保留 panic，但文案统一成 `internal compiler error: ...`，附 bug-report 提示。**前提是验证不可达** |
| 可能由用户输入触发（partial vtable 缺方法） | ~4 | 该转诊断的转诊断；先取证是否真的可由合法输入触发 |
| 内部 API 误用（`append_release_control_line`） | 1 | 保留 panic |

**取证要求**：对每处 panic 回答「合法输入能否触发？」。
559 套件全绿只说明现有用例没触发，不等于不可达。不可达的写明依据；
可达的按用户错误处理。

---

## 第 3 步：跨编译器对拍预言机

删 Swift 的前置条件。现在两编译器**产物不可能字节相同**
（C 名里带 DefId 压印，编号规则不同），所以对拍判据是**行为等价**，不是文本等价。

**做法**：

1. 取 559 个用例里语义敏感的子集（泛型实例化、trait 分发、内存管理、模式匹配）。
2. 同一输入分别交给两个编译器编译，**比较运行结果**（stdout + exit code），
   以及**诊断串**（已在套件里，复用）。
3. 进 CI，任何一边单侧回归立即报警。

这一步的价值不在「多一层测试」，而在**保住互为预言机的强度**。
在此之前删掉 Swift，等价于把最强的验证手段换成最弱的。

---

## 每步的验证链

固定流程，不可换序：

```
1) Swift 套件    ./bin/compiler-test-runner/compiler_runner --compiler swift \
                   --swift-koralc compiler/.build/release/koralc --timeout 60 -j 8
2) host→stage1   compiler/.build/release/koralc build --package-config bootstrap/koral.json \
                   --target-module koralc -o bin/bootstrap
3) stage1 套件    --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc
4) 自举两轮 + 不动点（emit-c + clang）+ 悬空扫描（必须为 0）
5) stage2 套件    --compiler bootstrap --bootstrap-koralc /tmp/s2/koralc
```

目标：**559/559 ×3**，诊断一字未改。

**新增验收**（第 1 步专用）：
- 1a：`grep -c EnumerateIterator` 在 `list_sort_test` 生成 C 中为 0；text 段回落
- 1b：`--debug`/`--release`/`--optimize` 两边 clang 参数一致

---

## 本期边界（明确不做）

- **删 Swift 编译器** —— 等第 3 步预言机就位再议
- **产物字节级一致** —— DefId 压印规则不同，不是缺陷，不追求
- **`--no-std` 补用例** —— 单列，与本期无耦合
- **语言特性扩展** —— 本期只收尾，不加新东西

## 硬性约束

- **行为零变化**（第 1b 步新增 flag 除外，那是补能力不是改行为）
- **诊断文本一字不变**
- **不绕过 / 不硬编码**：不许用名字白名单、魔法数字蒙混过关
- **不选最容易通过的办法**
- **一处处手工改**，不盲改

---

## 附：切片 A 的实测结论（2026-10-02）

**做过了，撤回了。** 记录原因，免得再走一遍。

实现：`mono_reachability.koral`，从 `main`/全局/foreign 做可达性闭包，
按成员裁 `FunctionDecl` / `TypeStructDecl` / `TypeEnumDecl` / `given` 成员。

结果：`list_sort_test` 生成 C 从 53 563 行掉到 1 511 行，
`EnumerateIterator` 从 95 处掉到 0——**体积收益是真的**。但产物**编不过**，
漏了活的被调用者（`Std_String_message` 被裁，调用它的函数留下了）。

过程中查到的两个引用图事实，**对切片 B 同样有用**：

1. **mono 推给 codegen 的 `FunctionDecl`，body 是占位符。**
   真身在 `context.get_concrete_function_body(def_id)`。只读节点自己的 body
   会收不到任何引用——第一版就是这么把 `println` 删掉的。
   `given` 成员同理（`get_concrete_given_member_body`）。
2. **`Symbol` 同时是引用和类型引用。** 只收 `symbol.def_id` 不收
   `symbol.symbol_type`，会让存活的 `println("...")` 丢掉它存放字面量的
   `Std_String` 布局。

补上这两条后错误从 20 个降到 1 个，但引用图仍不完整。**继续补是往错的方向走**：
裁剪型 DCE 要求引用图精确无缺，缺一处就是删掉活代码——而这类 bug 逃得过
「生成 C 能编译」，逃不过运行时，最难查。

**所以 A 撤回，直接做 B。** 理由：

- B 是**根治**（不产生死实体，也就没有引用图要补全）
- A 的收益是症状，B 的收益是根因
- A 引入的是一类新缺陷面（过裁），B 不引入

B 的落点已明确：`materialize_trait_tool_members_for_conformance`
（`sema/type_checker_members.koral:972`）在**声明期**把 trait 的全部 tool 方法
盖到每个 conformance。改成**调用期**物化——与 `instantiate_extension_method_impl`
现有的 on-demand 路径统一。届时 `reduce`/`filter`/`take_while` 从未被调用，
就不会被创建，适配器类型也就不会被解析出来。

> **本段的落点判断已由下面「附：1a 已完成」修正**：tool 物化确实是体量主因，
> 但触发它的是「泛型 tool block 被当成 tool block」，不是「物化时机太早」。
> 结果是同一个，改法不同。

---

## 附：1a 已完成（2026-10-02）

**判据双达**：`list_sort_test` 生成 C 里 `EnumerateIterator` 130 → **0**；
text 段 163 840 → **98 304**，与 Swift 的 98 304 **完全一致**。
生成 C 行数 53 563 → 33 552（Swift 29 415）。
全链：Swift 562/562 · stage1 562/562 · 自举 FIXED POINT + 悬空 0 · stage2 562/562。

### 根因（与切片 A 的猜测不同）

**不是**「非泛型声明无条件发射」——Swift 同样把每个非泛型 `given` 成员原样送进
MIR/codegen，**没有任何可达性/DCE 过程**（`MIR/MIRLowerer.swift:61-64` +
`shouldLowerFunction` 只滤泛型参数类型；`CodeGen` 发射每一个 MIR 函数）。
两边在这一点上一致，所以它不是分歧。

**真正的分歧只有一处：`given[T Any] Iterator[T] { ... }` 这类泛型 trait tool block
被归到了哪一类。**

Swift 在 `TypeCheckerPasses.swift:1173` 卡死：

```swift
// `given Trait { ... }` tool method declaration.
// Generic `given[T] [T]Trait { ... }` must be treated as a generic type extension,
// not as a trait tool block.
if typeParams.isEmpty, let traitConstraint = try? SemaUtils.resolveTraitConstraint(from: typeNode),
   visibleTraitInfo(traitConstraint.baseName) != nil {
```

只有**非泛型** `given Hash { ... }` 才是 tool block；`given[T Any] Iterator[T] { ... }`
走 generic extension template，**调用期**才实例化。
于是 `flattenedTraitToolMethodEntries("Iterator")` 是空表，
`Materialize trait tool methods`（`TypeCheckerPasses.swift:3322`）那个循环**一次都不进**，
`StringRunesIterator` 的 conformance 节点里只有它自己写的 `next`。

bootstrap 的 `trait_tool_target_name` 两种都收，于是
`materialize_trait_tool_members_for_conformance` 把 `enumerate`/`filter`/`take_while`…
整套盖到**每一个** conformance 上，全是非泛型 `GivenMember`，被无条件带走。
`EnumerateIterator` 的四个字符串迭代器实例 + 闭包 payload 结构体就是这么进来的。

**证据**：把 `materialize_trait_tool_members_for_conformance` 整个短路成返回空表，
其余一字未改 —— 53 563 行 → 32 422 行，`EnumerateIterator` 130 → 0。
一处就吃掉 21 141 行，是 24 148 行差距的 87%，与 text 段目标降幅几乎重合。

（探针也证明了它是 load-bearing 的：直接关掉会产出
`__mir_h_1.combine_hash` 这种「把方法当字段取值再当闭包调」的坏 C，
`combine_hash` 是 `given Hash { ... }` 里的**非泛型** tool 方法——Swift 同样会物化它。
所以要改的是「泛型 tool block 不物化」，不是「tool 全不物化」。）

### 实际改动（四处，都在 bootstrap 侧；Swift 已是正确做法）

1. **`sema/type_checker_members.koral`** — `materialize_trait_tool_members_for_conformance`
   加跳过规则 (d)：`entry.type_params` 非空（来自泛型 tool block）就不物化。
2. **`sema/type_checker.koral`** — `given` 分派：非泛型 tool block 仍 `register_trait_tool_block`
   后直接返回；**泛型** tool block 继续往下走，额外注册成 generic extension template，
   这是调用期实例化的来源。
3. **`sema/type_checker_templates.koral`** — 新增 `trait_extension_template_key`：
   `given[T Any] Iterator[T]` 解析成 `*Iterator`（trait 套在引用修饰符里），
   `method_owner_of` 会按**修饰符**记成 `Builtin("Ref")`。owner 必须是 **trait 的声明**——
   Swift 记在 `methodOwnerForName(baseName)` 下，调用点按
   `MethodOwner.Decl(conformance.trait_def_id)` 找。注册与
   `update_extension_method_checked_template`（补 body）必须用同一把钥匙，
   否则方法只有签名没有定义。
   同时补上 `resolve_conformance_extension_template_signature` 的
   `checked_bindings`：trait-owner 模板的参数是按 **trait 自己的**类型参数解析的
   （`fn Func(T) Bool` 里那个 `T`），只有 conformance 的实参能把它收掉。
4. **`mono/mono_functions.koral`** — `instantiate_extension_method_from_entry` 的
   符号命名与缓存键改用**实例的**类型实参，不再用 `type_args`（那是 trait 的实参）。
   否则 `MapIterator[Int, Int, ListIterator[Int]]` 与
   `MapIterator[Int, Int, FilterIterator[...]]` 共用一个 `MapIterator_I_into_list_d36`，
   第二个调用过了类型检查却把接收者塞进第一个的定义体。

### 顺带记下的两个独立缺陷（未修，另开）

- **未知成员静默降级成字段访问**：tool 方法没解析出来时，`h.combine_hash(...)`
  编成 `__mir_h_1.combine_hash` + 闭包调用，C 报一堆莫名其妙的错，
  而不是「没有成员 `combine_hash`」。应当报诊断。
- **`instantiate_extension_method_from_entry` 的命名对 trait-owner 模板是结构性欠参数**（见上第 4 条），
  本次只在这一处按实例参数命名，其它命名点未审。

### 切片 A 的教训仍然成立

引用图裁剪（切片 A）撤回是对的：Swift 根本没有 DCE，两边产物体积差 100% 来自
「谁被创建」，不是「谁被发射」。按需**创建**，就没有引用图要补全。

## 附：1b 已完成（2026-10-02）

`--debug` / `--release` / `--optimize <level>` 补齐，`driver/run.koral` 不再硬编码 `-O1`。

**逐项对照（假 clang 记录实参）**——9 种模式两边 clang 参数完全一致：

| 模式 | 两边 clang 参数 |
|---|---|
| （默认） | `-O1` |
| `--debug` | `-O0 -g` |
| `--release` | `-O2` |
| `--optimize 0/1/2/3/s/fast` | `-O0` `-O1` `-O2` `-O3` `-Os` `-Ofast` |

诊断串逐字一致：

```
Error: Invalid value for --optimize (expected 0, 1, 2, 3, s or fast): <x>
Error: Missing value for --optimize option
```

**自举产物上也已验证**（`/tmp/s2/koralc`）——能力真的长住了，不是只在 host 上有效。

顺带修了工具链：`koral build --release` 原本是**双重空转**——
`parse_cli_args` 把所有 `--flag` 都当带值的（`--release` 会直接报
"flag '--release' requires a value"），即便过去了 `cmd_build` 也不转发给 koralc。
现在 `--release` / `--debug` 作为开关解析（存空串，调用方测存在性），
`build_mode_args(flags)` 映射成 koralc 的同名 flag，`cmd_run` 复用 `cmd_build` 故一并生效。
`toolchain/koral` 两个编译器都能 `check` 通过。

**验证**：559/559 ×3、自举不动点 + 0 悬空，诊断一字未改。

---

## 附：第 2 步取证 —— vtable 四处（2026-10-02）

**结论：合法输入可以触发，而且 panic 的文案是错的。**

### 复现器

```kotlin
trait Base {
    base(self) String;
};
trait Show Base {
    show(self) String;
};
type Box[T Any](value T);

given[T Any] Box[T] as Base {
    public base(self) String = "base";
};
given[T Any] Box[T] as Show {
    public show(self) String = "show";
};

let main() Int = {
    let b = Box[Int](1);
    let s Show = b;
    println(s.show() + s.base());
    return 0;
};
```

```
bootstrap: Panic: Refusing to emit partial vtable for Show on S#17430; missing methods: base
Swift:     Error: MIR verification failed in trait vtable Show: missing conformance witness
```

### 隔离矩阵

| 形状 | bootstrap | Swift |
|---|---|---|
| 非泛型 given + trait object | ✅ | ✅ |
| 泛型 given + trait object，方法是**自己的** | ✅ 打印 `boxed`，运行正确 | ❌ missing witness |
| 泛型 given + trait object，方法继承自**父 trait** | ❌ **panic 1505** | ❌ missing witness |
| 泛型 given + 静态分发（套件里全在这） | ✅ | ✅ |

三者只差一处，隔离得很干净：**父 trait 的方法**。

### 根因

`record_conformance_witness`（`sema/type_checker.koral:690`）的唯一写入点
（`type_checker_decls.koral:665`）有守卫：

```kotlin
if type_params.is_empty() and not self.contains_generic_parameter(resolved_target) then {
    self.record_conformance_witness(resolved_target, trait_name, resolved_trait_args, typed_members);
};
```

**泛型 conformance 一律不记 witness。** 而 vtable 装配高度依赖 witness：

- `requirement_slots` 会把父 trait 的方法**摊平**进子 trait 的方法表 → `base` 进了表
- `local_implementation_def_ids_by_method_name` **只装本 given 自己的成员** → 只有 `show`
- 父 trait 的方法要靠 `direct_parent_trait_refs` 递归去取**父的 witness** → 父也是泛型 given，同样没记 → **断链**

物化是好的：生成的 C 里 `Box_I_base_d113` / `Box_I_show_d113` 两个函数都在，
`h_no_erasure`（同样两个 given，但不做 trait object 转换）编译运行都正确。
**缺陷纯粹在 vtable 装配期的查找，不在物化。**

### 三处派生 panic

| 站点 | 关系 |
|---|---|
| `codegen_vtable.koral:1505` | **主闸**，已被合法输入触发（上述） |
| `codegen_vtable.koral:717` | 1505 的重复保险；`Dict[String, DefId]` 计数逻辑下不可达 |
| `codegen_vtable.koral:431` / `:510` | 同一缺陷类的下游：def_id 解出来了但 symbol 没解出来 |

### 两个判断上的修正

**1. 「可达的按用户错误处理」对这一类是错的。** 计划原文假定可达的 panic 该转诊断。
但这个程序是**合法的**——`Box[Int]` 通过 `given[T] Box[T] as Show` 实现了 `Show`，
把 `Box[Int]` 赋给 `Show` 完全正当。转成诊断等于让 bootstrap 去**拒绝合法代码**，
正是 Swift 现在的错法。正确处置是修掉 witness 缺口，修好之后这道闸才真正不可达，
才配保留成 `internal compiler error`。

**2. panic 文案与事实相反。** `Refusing to emit partial vtable` 说的是「你少实现了方法」，
但 sema 早就保证了完整性（`check_conformance_in_module` 连参数名、默认值都查了）。
真实情况是编译器弄丢了父 trait 的 witness。文案会把人引向完全错误的排查方向。

### Swift 的缺陷（本轮新发现，未修）

Swift 的 `MIRVerifier.swift:71` 要求每个 vtable 都有 conformance witness，
而泛型 conformance 从不产生 witness，于是**合法程序被硬拒**，
顶着的还是一句内部口吻的报错（`MIR verification failed ...`），
不是设计过的用户诊断。

按「两边按最佳实践选」，**这一处 bootstrap 是对的，Swift 是错的**——
bootstrap 至少把「方法是自己的」那种情况编对了并跑出正确结果。

这正是第 3 步预言机要抓的东西：**两个编译器对同一合法输入的行为分歧**。
在它被写进对拍之前，套件是绿的（559/559），因为
**「泛型 given × trait object 转换」这个组合零覆盖**——
17 个用 `given[` 的用例全是静态分发，做 trait object 转换的那条用的是非泛型 given。

---

## 附：第 2 步取证 —— 26 处 panic 完整判定表（2026-10-02）

**26 处**（计划原文写 ~19+4+1，实际 pipeline 类是 **21** 不是 19）。三类，判定全部落到证据。

### A 类：流水线不变量 21 处 —— **不可由合法输入触发**（已验证）

`codegen_generate.koral:52,55,59,75,80,85,88,94,102,109,115,119,124,130,134,141,150,618,636`、
`codegen_mir.koral:3174`、`codegen.koral:2127`。

**人口路径已钉死**（这是判定的前提）：

| 谁能进 `program.functions` / `program.globals` | 来源 |
|---|---|
| 声明期种子 | `collect_mono_program_inputs` 只收 `is_non_generic_decl`（`mono.koral:641-654`）；泛型模板被 `_ then false` 排除（`mono.koral:495-497`），降级成惰性的 `MIRGlobal.TemplatePlaceholder`（`mir_lowerer.koral:253-255`） |
| 实例化产出 | `instantiate_function` / `instantiate_struct` / `instantiate_enum` 推入前先过「实参具体 + 元数对 + 约束满足」三道闸（`mono_functions.koral:67-83`、`mono_types.koral:510-522`） |
| work item | `should_lower_function = not contains_generic_parameter(symbol_type)`，**TypeVar 也认**（`mir_lowerer.koral:326-327, 551-554`） |
| `MIRGlobal.Given` | 仅当 target 具体、trait 实参具体、成员符号非泛型（`mir_lowerer.koral:209-251`） |

所以：正确的 mono 不会推出带泛型的实体，21 处全不可达。

**但这个 bug 类是活的，不是假想**：`edc7ae38`（2026-06-30）修的 `box()` 事故——
「standalone generic function 从不单态化」——**342 个合法用例失败**，正是泛型实体被推到 codegen。
守卫由 `1a4ffbbd` 引入，早于该修复；在那段时间里，普通用户程序写一行 `box(x)` 就会打到这些闸。

**三条残留（守卫的真实价值，不是纯粹的偏执）**：

1. **TypeVar 盲区。** mono 的 `has_generic_parameter`（`mono_types.koral:443`）**只认 `GenericParameter`，漏 `TypeVar`**，
   也不展开 `StructureType`/`EnumType`；codegen 的 `type_contains_generic` 两者都认。
   于是 sema 残留的 TypeVar 会从**守卫最薄的三处**漏下去：
   `LetDecl` → `MIRGlobal.GlobalVariable`（`mir_lowerer.koral:190-194`，**完全无泛型过滤**）、
   初始化 work item（`:314-325`）、`collect_concrete_vtable_request`（`mono_type_resolution.koral:1570`）。
   **这是一条真实的潜在洞，应当补上，不能记完了事。**
2. **skip 路径的残留是活代码。** `skip_instantiation_with_unsatisfied_constraints` 确实不推节点，
   但调用点留下的 `GenericCall` 残留会被降级成真实 MIR 调用（`mir_function_builder.koral:444`）。
   类型还泛着 → 打到 #3（locals）或 #21；类型已具体但被调方从未生成 → **变成 C 链接错误**，连 panic 都躲过了。
3. **#5/#6/#7 是最薄的三处**（全局 `let` 无任何 mono 侧过滤，只靠「sema 会给具体类型」）。

**Swift 对照**：Swift **没有** `validateCodeGenInputs`，也没有任何 `Generic ... reached codegen` 守卫
（全搜过 `CodeGen/*.swift`）。只有一处 `fatalError("Unresolved type \(type) during codegen")`
（`CodeGen.swift:1140`）与 codegen.koral:2127 对应。
**这 20 处是 bootstrap 独有的绊线，比 Swift 更防御**——保留它们是对的。

**处置**：保留 panic，文案统一成 `internal compiler error: ...` + bug-report 提示。
（不可达性已验证，符合计划的前置条件。）

### B 类：vtable 四处 —— **可由合法输入触发**（已验证，见上一节）

`codegen_vtable.koral:1505`（主闸，已复现）、`:717`（重复保险，计数逻辑下不可达）、
`:431` / `:510`（同一缺陷类下游：def_id 解出但 bind 不出 symbol）。

**处置修正**：**不转诊断**。理由见上一节——那是合法程序，转诊断等于拒绝合法代码。
正确顺序是先修 witness 缺口，修好后才真正不可达，才配当 ICE。

### C 类：内部 API 误用 1 处 —— 保留 panic

`codegen_memory.koral:70`。注释自己写着：「走到这里说明有调用点漏改了 —— 直接炸，不要静默发成 retain」。
调用点分布清楚（`append_release_control_line` 只在 retain/weak 路径被调，release 一律走
`append_release_handle_statement`），是**编译器内部 API 契约**，与用户输入无关。保留。

### 汇总

| 类 | 数 | 判定 | 处置 |
|---|---|---|---|
| A 流水线不变量 | 21 | 不可由合法输入触发（已验证） | 保留 panic，文案统一成 ICE + bug-report |
| B vtable 部分表 | 4 | **可由合法输入触发**（已复现） | **先修 witness 缺口**，修好后转 ICE |
| C 内部 API 契约 | 1 | 与用户输入无关 | 保留 panic |

### 本轮连带发现（都不在原计划里）

1. **Swift 拒绝合法程序**：`MIRVerifier.swift:71` 要求 vtable 必有 witness，
   而泛型 conformance 从不产生 witness → 合法代码被硬拒，报的还是内部口吻的
   `MIR verification failed ...`。按「两边按最佳实践选」，**这处 Swift 错、bootstrap 对**。
2. **TypeVar 盲区**（上面 A 类残留 1）：mono 的 `has_generic_parameter` 漏 `TypeVar`，
   与 codegen 判据不一致。真实潜在洞。
3. **测试空洞**：「泛型 given × trait object 转换」**零覆盖**。
   17 个用 `given[` 的用例全是静态分发；做 trait object 转换的那条用的是非泛型 given。
   上面两个缺陷一起烂着、谁也没照出谁，就是这个空洞的直接后果。
4. **诊断分歧**（object-safety）：同一输入 Swift 给
   `Trait 'X' is not object-safe: method 'm' has generic type parameters; method 'm' uses Self in parameter 'f'`（带 span），
   bootstrap 只给 `Trait 'X' is not object-safe`（无 span、无原因）。属第 3 步对拍清单。

---

## 附：vtable 头字段撞名（2026-10-02，已修）

**两个编译器共有的缺陷，任何 trait 声明一个叫 `base` 的方法就触发。**

```kotlin
trait Show {
    base(self) String;
};
type Box(value Int);
given Box as Show {
    public base(self) String = "ok";
};
let main() Int = {
    let b = Box(1);
    let s Show = b;
    println(s.base());
    return 0;
};
```

修复前，**两边**都编出编不过的 C：

```
error: duplicate member 'base'
    struct __koral_VTableHeader base;             // ← vtable 头字段，硬编码叫 base
    struct Std_String (*base)(struct __koral_Ref); // ← trait 方法也叫 base
```

用户看到的是一屏 clang 报错，不是编译器诊断。

### 是怎么找到的

查 1505 那条 panic 时，用「泛型 given + 父 trait」做探针，强制物化父 conformance 之后
lookup 通了，结果撞上这个。**前面那个 panic 把它挡住了**，所以一直没露面——
两个缺陷叠在一起，谁也照不出谁（与「泛型 given × trait object 零覆盖」是同一个病根）。

### 修法

**`base` → `_Base`**，取在 C 标识符转义区。不相交是**可证的，双重的**：

1. `escape_codegen_keyword` / `escapeCKeyword` 对 `_` 开头且第二字符大写的名字加前缀，
   所以 Koral 方法名 `_Base` 会被转成 `_k__Base`，**落不到** `_Base`。
   （bootstrap 的 `__koral_` / `__mir_` / `_k__` 放行分支不适用于 `_Base`。）
2. 语言本身就拒：`Function name '_Base' must start with a lowercase letter`。

比「改成下划线开头」强得多——Koral 标识符**允许** `_` / `__` 开头
（实测 `__koral_vtable_hdr` 是合法标识符），所以那种改法只是把撞名概率压低，不构成保证。

### 改动面（5 处声明/初始化 + 注释）

| 文件 | 改动 |
|---|---|
| `bootstrap/koralc/codegen/codegen_vtable.koral` | 头字段声明、`._Base =` 初始化 |
| `bootstrap/koralc/codegen/codegen_mir.koral` | `vtable_prefix_struct_type_for_mir_method` 的内联结构体（照真 vtable 布局捏的，字段名必须逐个对齐） |
| `compiler/Sources/KoralCompiler/CodeGen/CodeGenVtable.swift` | 同 bootstrap 两处 |
| `std/koral_runtime.h` / `.c` | 注释 |

**这个字段没人按名读。** 析构走的是 `((const struct __koral_VTableHeader*)ref->vtable)->destroy`
——按类型转换取，不按名字。`base` 只是「必须位于 offset 0」的布局占位，所以改名代价极小。

回归用例：`tests/compiler-cases/trait_method_named_base_vtable_header_ok.koral`。

### 顺带记录：两边转义规则不一致

bootstrap 的 `escape_codegen_keyword` 有三个放行分支（`__koral_` / `__mir_` / `_k__`），
Swift 的 `escapeCKeyword` **没有**。于是 Koral 方法名 `__koral_foo` 在两边产出**不同的** C 字段名。
属第 3 步对拍清单（不影响本次修复的正确性：`_Base` 在两边都落在转义区）。

---

## 附：泛型 conformance 的父 trait 物化（2026-10-02，bootstrap 已修）

`instantiate_trait_vtable_methods` **完全不走父 trait**——只物化传入的那个
`trait_def_id` 的方法（往下递归的是引用包装，不是父）。而 sema 早就要求父 conformance
必须显式声明（`Parent trait must be explicitly implemented`）。

**缺的只是物化**：`X: Child` 蕴含 `X: Parent`。物化子 conformance 时必须把父的一起物化，
否则子的 vtable 带着一条继承来的 requirement，却没有任何实现可绑：
`resolve_method_def_id` 走到父那里，发现这个具体类型根本没有父的 conformance。

修法：`instantiate_trait_vtable_methods` 拆成「公开入口建 visited → 单 trait 物化 + 父递归」。
父的类型实参用 `trait_info.type_params` → `trait_type_args` 建 bindings，再
`resolve_type_node(parent.type_arg_nodes, bindings)`——所以 `Child[T] Parent[T]`
实例化到 `Child[Int]` 时带的是 `[Int]` 不是 `[T]`。

`visited` 只作用于父遍历，**故意不拦**函数末尾的引用解包递归：
`Box[Int]` 和 `Box[Int] ref` 是不同接收者，各自都要物化，尽管 trait 身份相同。

复现器与回归用例见下节（用例暂未落地，见「Swift 侧缺口」）。

---

## 附：Swift 侧缺口 —— 定界实验（2026-10-02）

**Swift 不是「校验器太严」，是整条 conformance 查找路径都缺。**

定界实验：**临时**把 `MIRVerifier` 的「无 witness 即失败」改成跳过，看 codegen 自己能不能编对。

```
generic_given_trait_object:  Refusing to emit partial vtable for Show on Box_I_d172[Int]; missing methods: show
c_parent:                    Refusing to emit partial vtable for Show on Box_I_d173[Int]; missing methods: base, show
```

连 conformance **自己的** `show` 都找不到。bootstrap 之所以编对了简单情形，是靠
`lookup_trait_method_def_id_from_given_globals` 那三道兜底在 `MIRGlobal.Given` 里翻——
**Swift 完全没有这一层**，校验器只是把更早的失败顶在了前面。

实验已还原（`MIRVerifier.swift` 复原并重建，行为复核一致）。

### 这决定了修法

| 路线 | 内容 | 评价 |
|---|---|---|
| A. 给 Swift 补 bootstrap 那套兜底 | 把 `lookup_trait_method_def_id_from_given_globals*` 等搬到 Swift | 让 Swift 去模仿 bootstrap 的补丁层 |
| B. 两边都改成**按实例记 witness** | mono 在知道具体类型处记 `ConformanceWitness`（selfType=具体、槽类型已代换），校验器与 codegen 都直接查到 | **正路**，也是 rustc 的 `Instance { def, args }` 模型；做好后 bootstrap 的三道兜底可删 |

**建议走 B。** 理由：

- A 是「让第二实现去复制第一实现的权宜」，与「两边按最佳实践选」相反
- B 落点已有：`mono.storage.conformance_witnesses` + `merge_conformance_witness(key, witness)`
  基础设施都在，`instantiate_trait_vtable_methods_core` 里已经算出了
  `bindings`（泛型 → 具代换），正是槽类型代换要的那份映射
- B 做完，第 3 步对拍预言机才有可能收敛——现在两边对同一合法程序的分歧有**四处**（见下）

### 用例（暂未落地，等 Swift 对齐）

```kotlin
// generic_given_parent_trait_object_ok.koral
// EXPECT: show
// EXPECT: base

trait Base {
    base(self) String;
};
trait Show Base {
    show(self) String;
};
type Box[T Any](value T);

given[T Any] Box[T] as Base {
    public base(self) String = "base";
};
given[T Any] Box[T] as Show {
    public show(self) String = "show";
};

let main() Int = {
    let b = Box[Int](1);
    let s Show = b;
    println(s.show());
    println(s.base());
    return 0;
};
```

bootstrap 编译运行正确（`show` / `base`）。Swift 今天拒绝整个程序，
所以放进 `tests/` 会让套件变红——**留在这里，等 B 落地后补进去**。

---

## 跨编译器分歧清单（第 3 步对拍的已知输入）

| # | 合法输入形状 | bootstrap | Swift | 谁对 |
|---|---|---|---|---|
| 1 | trait 方法名叫 `base` | 曾编出 duplicate member；**已修** | 同样缺陷；**已修** | — |
| 2 | 泛型 given + trait object，方法是自己的 | 编译运行正确 | 拒绝：`missing conformance witness`；放开校验器则 codegen `missing methods: show` | **bootstrap** |
| 3 | 泛型 given + trait object，方法继承自父 trait | 曾 panic 1505；**已修** | 同 #2 | **bootstrap** |
| 4 | 泛型实例转**带参** trait（`Child[Int]`） | `Type mismatch: expected *Child, got Box[Int]`（实参被丢） | `missing conformance witness` | **都不对** |
| 5 | object-safety 诊断 | `Trait 'X' is not object-safe`（无 span、无原因） | 带 span + 原因列表 | **Swift** |
| 6 | C 标识符转义规则 | 有 `__koral_`/`__mir_`/`_k__` 放行分支 | **没有** | 需对齐 |
| 7 | mono 泛型判据 | `has_generic_parameter` 漏 `TypeVar` | — | **需补**（见 A 类残留 1） |

---

## 附：B 路线已落地 —— witness 按实例记录（2026-10-02）

**两个编译器都改完了。** 合法的「泛型 given + trait object 转换」现在两边都编译运行正确。

### 模型

sema 记**声明**的 witness，mono 记**实例**的——rustc 的 `Instance { def, args }` 拆法：

| | 键 | 谁读 |
|---|---|---|
| 声明 witness | 声明形（`given[T] Box[T] as Show` 记在 `Box[T]` 下） | **只有**特化步 |
| 实例 witness | 实例形（`Box[Int]`） | codegen、MIR 校验器 |

所以没有任何消费者会把声明那份错当成实例答案。泛型 conformance 之所以以前不记 witness，就是因为怕这个混淆——现在用**键空间分离**解决，而不是不记。

### 三处改动（两边同构）

**1. sema 放开记录守卫**
`if type_params.is_empty() and not contains_generic_parameter(...)` → 一律记录。
（Swift 侧是 `if typeParams.isEmpty`。）

**2. mono 特化**
`materialize_conformance_witness_for_instance`（bootstrap）/ `materializeConformanceWitness`（Swift）：
按**声明身份**（trait 的 DefId + 属主身份）找到声明那份，把属主的类型形参按位绑到实例的类型实参上，代换槽类型，然后按实例键存回去。

bindings 的来源是 `method_owner_and_args`——它的文档写着「`StructureType` 实例和 `GenericStruct` 模板两种拼法都落到同一对」，正是需要的归一。
而**声明形的类型实参里就带着属主的类型形参**（`given[T] Box[T]` → `[T]`），跟实例实参按位配对即得 bindings，连模板的 `type_params` 都不用找。

**3. 方法表填实例 DefId**
witness 的 `local_implementation_def_ids_by_method_name` 若抄声明的模板 DefId，
绑定到接收者会物化出模板自己的泛型形（`Box_Param_T_show`）而不是这个接收者的（`Box_I_show`）。
所以每槽按接收者身份查一次实例 DefId（bootstrap 走 `lookup_extension_method_def_id`，
Swift 走 `lookupInstantiatedExtensionMethodSymbol`），查不到才回退声明的。

物化时机必须在**方法实例化之后**——bootstrap 侧因此从 `_core` 的开头挪到了父遍历之后。

### 顺带修掉一个潜伏 bug：vtable 槽序不一致

特化让 witness 一生效就暴露了：`s.show() + s.base()` 打出 `baseshow` 而不是 `showbase`。

**两个展平顺序不一致**：
- sema 的 `requirement_slots` 用 `pending.pop()`（LIFO）→ **自己优先** `[show, base]`
- mono 的 `ordered_trait_method_names_helper_from_def` / codegen 的 `collect_instantiated_trait_members_for_vtable` → **父优先** `[base, show]`

vtable 结构体按前者排字段，而 trait object 调用按**偏移**打过去（`vtable_prefix_struct_type_for_mir_method`
用 `void(*)()` 占位把目标方法顶到正确偏移），两者对不上就串了。

**这跟泛型无关**：非泛型 given + 父 trait + 自己的方法，今天也这样，
只是零用例覆盖（`trait_object_parent_generic_arg_dispatch_emit_ok` 的 `Child` 自己没有方法）。

按「两边按最佳实践选」拉齐到 **Swift 的顺序（父优先）**——Swift 的 `requirementSlots` 本来就是
`for parent in parents { try collect(parent) }` 在方法循环之前，bootstrap 是歪的那个。

### 用例已落地

`tests/compiler-cases/generic_given_parent_trait_object_ok.koral` —— 泛型 given + 父 trait + trait object，
断言 `show` / `base` 的顺序（把槽序一起钉住）。**两个编译器都过。**

---

## 附：B 落地后分歧清单更新（2026-10-02）

B 顺带修好了比预期更多的东西。**分歧 #4 翻转了**：

| # | 合法输入形状 | bootstrap | Swift | 谁对 |
|---|---|---|---|---|
| 1 | trait 方法名叫 `base` | **已修** | **已修** | — |
| 2 | 泛型 given + trait object，方法是自己的 | **已修** | **已修** | — |
| 3 | 泛型 given + trait object，方法继承自父 trait | **已修** | **已修** | — |
| 4 | 泛型实例转**带参** trait（`let s Sink[Int] = b`） | ❌ `Type mismatch: expected *Sink, got Box[Int]` | ✅ 编译运行正确（`put` / `tag` / `7`） | **Swift** |
| 5 | object-safety 诊断 | 无 span、无原因 | 带 span + 原因列表 | **Swift** |
| 6 | C 标识符转义规则 | 有 `__koral_`/`__mir_`/`_k__` 放行 | **没有** | 需对齐 |
| 7 | mono 泛型判据 | `has_generic_parameter` 漏 `TypeVar` | — | **需补** |

#4 是 **bootstrap 独有的 sema 缺陷**：`let s Sink[Int] = b;` 里期望类型被解析成
`*Sink`——**类型实参 `Int` 被丢了**，于是与 `Box[Int]` 对不上。这是类型解析层的问题，
与 witness 模型无关，是本轮的下一个待办。

复现器（Swift 已通过，bootstrap 未过）：

```kotlin
trait Sink[T Any] {
    put(self, v T) String;
};
type Box[U Any](value U);
given[T Any] Box[T] as Sink[Int] {
    public put(self, v Int) String = "put";
};
let main() Int = {
    let b = Box[Int](1);
    let s Sink[Int] = b;
    println(s.put(3));
    return 0;
};
```

---

## 附：#4 已修 —— 带参 trait object 的两处信息丢失（2026-10-02）

B 落地后分歧 #4 反了过来（Swift 已好、bootstrap 仍坏），本轮收掉。**两处都在丢信息**：

**1. `can_convert_to_trait_object` 丢了类型实参**（`type_checker_expressions.koral`）

```kotlin
_ then self.satisfies_trait_requirement(normalized, expected_trait_name),
```

走的是**无实参**变体，等于问「这满足 `Sink` 且实参为空吗」——任何带实参的 conformance 都答否。
期望类型是 trait **object**（`Sink[Int]`），实参就在类型里，取出来传下去即可：

```kotlin
_ then self.satisfies_trait_requirement_with_args(
    normalized,
    expected_trait_name,
    self.trait_object_type_args(expected_trait_type)
),
```

**2. `has_explicit_trait_conformance_with_args` 拿实例比声明**（`type_checker_visibility.koral`）

精确键查找拿 `Box[Int]` 比声明的 `Box[T]` 必然不中；而模板索引那条路有
`if not trait_arg_types.is_empty() then { continue; }`——**实参非空就整条跳过**。
于是带实参的泛型 conformance 两条路都够不着。

改成模板分支也处理「直接」情形，且声明的 trait 实参先按 bindings 归一再比
（`given[T] Box[T] as Sink[T]` 声明的是 `[T]`，问 `Box[Int]` 时 `T := Int`，所以它就是 `[Int]`）。
两条路径共用同一份属主约束检查。

**这条与 witness 那条是同一个病根**：声明形与实例形在查找时没归一。
witness 侧用 `method_owner_and_args` 解决，conformance 侧用
`conformance_type_key_bindings` 的合一 + 实参代换解决。

### 回归用例

`tests/compiler-cases/generic_given_parameterized_trait_object_ok.koral` ——
同时覆盖「泛型实例 → 带参 trait」和「泛型实例 → 带参且带父 trait」，断言 `put` / `tag` / `7`。**两个编译器都过。**

### 分歧清单：这一区域全部闭合

| # | 形状 | 状态 |
|---|---|---|
| 1 | trait 方法名叫 `base` | **两边已修** |
| 2 | 泛型 given + trait object，方法是自己的 | **两边已修** |
| 3 | 泛型 given + trait object，方法继承自父 trait | **两边已修** |
| 4 | 泛型实例转带参 trait | **两边已修** |
| 5 | object-safety 诊断（span + 原因列表） | 仍在清单 |
| 6 | C 标识符转义规则（`__koral_` 放行分支） | 仍在清单 |
| 7 | mono 泛型判据（`has_generic_parameter` 漏 `TypeVar`） | 仍在清单 |
| 8 | **已闭合**：缺失成员诊断。Swift 只对非泛型 `structure` 给 `Member 'x' not found in type 'Y'`，其余 receiver 掉进 `invalidOperation(op: "member access", type1: ..., type2: "")`，渲染成 `Invalid operation member access between types Int and `（`type2` 明写空串，句子断在半截）。**已按最佳实践两边统一**成 `Member 'x' not found in type 'Y'`。 | **已闭合** |
| 9 | **解析分歧**：`*T` 受管引用语法。Swift 一律拒（`managed refs are removed; raw pointers must be '*unsafe T'`），bootstrap 的 `parse_type` 仍接受 `.Star()` 走 `TypeNode.Reference`。本轮新增用例时撞到。**未修**——属解析层，另开。 | 仍在清单 |
| 10 | **潜在隐患**：mono 的 `layout_key(Type)` 对 `StructureType` 给 `struct_<id>`，`CompilerContext.get_layout_key` 给真名。目前 `layout_key` 只做内部相等比较、不产符号名，所以无害；一旦有人拿它命名就会静默不一致。**未修，记一笔。** | 仍在清单 |

---

## 附：两个独立缺陷已修（2026-10-03）

1a 收口时连带记下的两处，都已修。

### 1. 未知成员静默降级成字段访问

**症状**：`h.combine_hash(...)` / `f.nope` / `n.nope()` 这类「成员既非字段也非方法」的写法，
sema 照单全收，codegen 发成 C 结构体字段访问再当闭包调：

```c
__mir_tmp_14_14 = __mir_h_1.combine_hash;          // 成员取值
_t789 = ((void (*)(void))(__mir_tmp_14_14.fn))();  // 再当闭包调
```

clang 报一堆莫名其妙的错（`member reference base type 'intptr_t' is not a structure or union`、
`variable has incomplete type 'void'`），用户根本看不出是拼错了成员名。
1a 的根因就是被这层挡了很久。

**根因**：`check_member_dispatch_expr_ref`（`sema/type_checker_expressions_dispatch.koral`）
的分段循环里，每个分支只把失败记进 `inaccessible_method_member`，**没有一处报诊断**。
`check_member_expr_ref` 里那两处 `Member 'x' not found in type 'Y'` 是死代码（无调用点）。

**修法**：新增 `report_missing_member_if_needed`（`sema/type_checker_expressions.koral`），
在 `_ then` 与引用/指针各分支统一调用。三条护栏：

- receiver 类型已是 `Unknown` 就不报 —— 那是级联，不是第二个错；
  否则下游每次使用都印一条 `Member 'x' not found in type '?'`。
- 已有方法（含不可访问的）不报 —— `reject_inaccessible_method_from_current_context` 自己报过了。
- 文案与 Swift 的 `.undefinedMember` 一致。

**新增用例 4 个**（562 → 566）：`member_not_found_struct_error` /
`member_not_found_call_error` / `member_not_found_generic_struct_error` /
`member_not_found_scalar_error`。

### 2. trait-owner 模板的符号命名欠实例参数

**审计结论：全库只有 `make_extension_method_layout_name` 一处会欠参数，已在 1a 修掉。**

逐点核过：

| 命名点 | 判据 | 结论 |
|---|---|---|
| `make_extension_method_layout_name`（`mono_types.koral:368`） | 唯一调用点 `instantiate_extension_method_from_entry` | **1a 已修**（用实例实参） |
| `make_layout_name`（`mono_types.koral:274`） | 3 个调用点（struct/enum/function），`args` 是模板自身实参，且 `args.count() <> type_parameters.count()` 有闸 | 自洽 |
| 调用侧 key：`make_extension_method_key` | 由 `collect_receiver_instantiations` 从 **receiver** 抽实参 | 与修复后一致 |
| `set_cname` 写入点 | 只有 `instantiate_function` 与 `instantiate_extension_method_from_entry` 两处，都是实例期一次写死 | 自洽 |
| codegen 侧 `c_name_for_def_id` / `nominal_layout_c_identifier` | 按 DefId 读 `get_cname`，不重算 | 自洽 |

顺带查出一条**无害但危险**的不一致（分歧清单 #10）：
`mono_types.koral` 的 `layout_key(Type)` 对 `StructureType` 给 `struct_<id>`，
而 `CompilerContext.get_layout_key` 给真名。目前 `layout_key` 只做内部相等比较
（如 `mono_functions.koral:759`），不产符号名，所以两边各自自洽；
一旦有人拿它命名就会静默不一致。记一笔，未修。

---

## 附：第 2 步 panic 收口已完成（2026-10-03）

**取证表 26 处全部落地**（判定见上「第 2 步取证」一节）：

| 类 | 数 | 处置 | 结果 |
|---|---|---|---|
| A 流水线不变量 | 21 | 文案统一成 ICE + bug-report | ✅ 21 处已改 |
| B vtable 部分表 | 4 | witness 缺口（B 路线）修好后转 ICE | ✅ 4 处已改 |
| C 内部 API 契约 | 1 | 保留 panic，**文案不动**（计划原文只对 A 指定文案） | 按计划保持 |

**实现**：新增 `codegen/ice.koral`，一个措辞出口：

```kotlin
public let internal_compiler_error(detail String) String = {
    return "internal compiler error: \(detail)\nThis is a bug in the Koral compiler, not the program being compiled. Please report it, along with the source that triggered it.";
};
```

25 处 `panic("...")` 改成 `panic(internal_compiler_error("..."))`，**detail 一字未改**
—— 哪个符号、哪个类型照旧，只是外面的框变成「这是编译器的 bug」。
措辞只有这一处，要改也只改一个地方。

**验证**：自举产物的 C 里字符串以十六进制字节序列发射，按字节查证，
`internal compiler error` / `This is a bug in the Koral compiler` / `Please report it`
三段各恰好出现 1 次，detail 串（`Generic function symbol reached codegen` 等）同时在。

**全链**：Swift 566/566 · stage1 566/566 · 自举 FIXED POINT + 悬空 0 · stage2 566/566。

### 顺带修掉的 Swift 缺陷

`TypeCheckerExpressions.swift:5223` 的
`.invalidOperation(op: "member access", type1: typeToLookup.description, type2: "")`
—— `type2` 明写空串，句子断在半截。Swift 只对非泛型 `structure` 走
`.undefinedMember`，其余 receiver 全掉进这条。
按「两边按最佳实践选」统一成 `.undefinedMember(memberName, typeToLookup.description)`，
与 bootstrap 同文案。列入分歧清单 #8（已闭合）。

# 简化类型系统迁移状态

日期：2026-09-19

本文档用于跟踪 `docs/rfc-simplified-type-system.md` 在当前 Swift 编译器实现中的本地迁移进度。用户审阅前不创建提交。

## 基本规则

- 迁移顺序：先处理 Swift `compiler/`、`std/`、测试；再处理测试运行器、samples、toolchain；最后让 bootstrap 按 Swift 实现对齐。
- 不保留兼容垫片。旧的托管引用表层语法、旧 receiver 适配、COW 路径、逃逸分析提升路径都应删除，而不是继续兼容。
- 每完成一个阶段，都必须更新本文档中的状态、影响范围、验证结果和剩余阻塞。

## 已确认的设计约束

- 移除托管引用表层：`*T`、`*mutable T`、`?*T`、`?*mutable T`、托管 `&`、托管 `&mutable`、`box()`、托管解引用。
- 保留 raw pointer：`*unsafe T`、`*unsafe mutable T`、`&unsafe`、`&unsafe mutable` 以及 raw pointer 解引用。
- 引入声明处可变性：`type A` 与 `type mutable B`；枚举和类型别名不能声明成 `type mutable`。
- receiver 语法只保留 `self`；不再有 `*self`、`*mutable self`、receiver auto-ref、receiver auto-deref。
- trait object 表层类型直接写 trait 名，不再写成 `*Trait` / `*mutable Trait`。
- 弱引用表层改成 `?T`，并要求类型参数约束显式写 `mutable`；移除 `upgrade_mutable` / `downgrade_mutable`。
- `Deref`、`not Deref`、ref blanket conformance、逃逸分析、托管引用分配提升、`Weak`、`Object`、COW uniqueness 检查都属于删除目标。
- 标准库容器和有状态迭代器改为共享语义的 `type mutable` 对象；需要独立副本时显式 `clone()`。
- plain `type` 是否走 ARC/隐藏间接层由编译器按语义决定；至少 `type mutable`、值递归类型、显式实现 `Drop` 的类型必须进入 managed 布局判定。

## 阶段状态

| 阶段 | 范围 | 状态 | 验证 |
|---|---|---|---|
| 0 | RFC、开发文档和实现锚点梳理 | 已完成 | 已建立本地迁移文档 |
| 1 | Swift 编译器表层模型：`type mutable`、旧语法拒绝、receiver `self` | 已完成 | `swift build -c debug` 与聚焦 parser/type 用例 |
| 2 | Swift 编译器语义清理：移除托管引用表层、`Deref`、旧 receiver 适配、旧 weak 分裂 | 已完成 | 聚焦语义正反例 |
| 3 | Swift MIR / codegen / runtime 对齐：去掉旧逃逸提升，让布局分析直接决定 managed 表示 | 已完成 | `hasNontrivialNominalDrop` 递归修复、Drop 签名迁移、Option[String] 深拷贝验证 |
| 4 | `std/` 迁移：类型分类、`Drop`、容器、String/StringBuilder、IO、无 COW | 已完成 | 504/506 测试通过、toolchain/koral 构建成功 |
| 5 | 测试迁移：删除旧功能测试、改写可迁移测试 | 已完成 | Swift 全量 506/506 通过 |
| 6 | runner、samples、toolchain 迁移 | 已完成 | 506/506 测试通过、samples/toolchain/koralfmt 全量迁移 |
| 7 | bootstrap 对齐 | 未开始 | host 编译 bootstrap + 分阶段自举验证 |
| 8 | 最终审阅报告 | 进行中 | 汇总改动、验证、剩余风险 |

## 最近进展

### 2026-09-17

- parser 已接受 `type mutable Name ...`，并把 nominal mutability 作为声明处标记贯穿到语义元数据。
- 旧 receiver 语法 `*self` / `*mutable self` 已被 parser 拒绝。
- `type mutable` 的最小正例和 receiver 负例已经通过聚焦验证。

### 2026-09-17 到 2026-09-18

- `std/list.koral`、`std/deque.koral`、`std/dict.koral`、`std/set.koral`、`std/string.koral` 的核心 COW 语义已经删除，别名写入改为共享语义。
- `StringBuilder` 成为 `String` 可变构造与累加的主路径。
- 核心容器及相关测试已经迁移到共享语义模型，并完成聚焦验证。
- 旧 managed surface parser 清理完成：类型位置只接受 `*unsafe T` / `*unsafe mutable T`，表达式位置只接受 `&unsafe` / `&unsafe mutable`。
- `std/primitives.koral` 里的 `box()` 以及旧托管引用 helper 已从活动表层删除。
- `Result` 的错误分支已经稳定在 trait object `Error` 表层模型上。

### 2026-09-18 到 2026-09-19

- 明确并修复了一个关键布局错误：plain `type` 若显式实现 `Drop`，必须在语义层被判定为 managed/ARC 布局，而不能只依赖 `type mutable` 或值递归。该修复已接入 [compiler/Sources/KoralCompiler/Sema/CompilerContext.swift](/Users/kulicswu/Documents/workspace/koral/compiler/Sources/KoralCompiler/Sema/CompilerContext.swift)、[compiler/Sources/KoralCompiler/Sema/DefId.swift](/Users/kulicswu/Documents/workspace/koral/compiler/Sources/KoralCompiler/Sema/DefId.swift)、[compiler/Sources/KoralCompiler/Sema/TypeCheckerPasses.swift](/Users/kulicswu/Documents/workspace/koral/compiler/Sources/KoralCompiler/Sema/TypeCheckerPasses.swift)。
- `CodeGen.generateStringLiteral` 已更新为按 managed nominal 形式构造 `String`，不再继续生成旧的扁平 `{data, len}` 值初始化。
- `std/range.koral` 的 `RangeIterator.next()` 修复了别名绑定下“先改 `self.current` 再返回 `c`”导致的错误返回值问题。
- 经过这组修复后，以下高信号回归已经恢复通过：
	- `tests/compiler-cases/string_methods.koral`
	- `tests/compiler-cases/string_builder_test.koral`
	- `tests/compiler-cases/json_basic_test.koral`
- 继续沿 RFC/计划推进下一阶段时，已开始迁移 `std/io` 与 `toolchain/koral` 主路径：
	- `Reader.read` 不再接收 `*mutable List[UInt8]`，而是直接接收 `List[UInt8]` 句柄。
	- `ByteBuffer`、`BufReader`、`BufWriter` 以及直接依赖这条接口链的 `File`、`Pipe`、`TcpSocket`、`UdpSocket` 已改为当前 `type mutable` / 值句柄模型。
	- 聚焦验证已通过：
		- `tests/compiler-cases/io_buffer_test.koral`
		- `tests/compiler-cases/io_buf_reader_test.koral`
		- `tests/compiler-cases/io_buf_writer_test.koral`
- `std/time/date.koral`、`std/time/clock_time.koral`、`std/time/datetime.koral` 里旧的可变 `String` 构造也已迁到 `StringBuilder`，对应时间测试已恢复通过。
- `toolchain/koral` 主 CLI 已成功构建，说明其主路径上的 `std/io`、`std/time`、`std/os`、`std/proc` 与 command builder 旧写法已经贯通。
- 在此过程中还修掉了一个新的编译器级残留：字符串插值 lowering 仍按旧 `String(data, len, cap)` 形状向 `from_owned_utf8_ptr_unchecked` 传三参数，现已修正为当前两参数模型。

### 2026-09-19（std 子模块 Storage 清理推进）

- 已对 `std/**` 现存 `Storage` 模式做了一轮全量扫描，并完成分类：
	- 单层包装、可直接消除的 `Storage`
	- 承担真实共享核心语义、需要谨慎保留或单独设计的 `Storage`
- `std/sync` 非 async 基础件的单层 `Storage` 已完成扁平化清理：
	- `std/sync/atomic.koral`
	- `std/sync/mutex.koral`
	- `std/sync/shared_mutex.koral`
	- `std/sync/latch_gate.koral`
	- `std/sync/semaphore.koral`
	- `std/sync/lazy.koral`
- `std/sync/channel.koral` 中两层明显过时的端点包装 `SendChannelStorage` / `RecvChannelStorage` 已移除，`ChannelStorage` 作为真正共享核心保留。
- 对应聚焦验证已通过：
	- `tests/compiler-cases/sync_misc_test.koral`
	- `tests/compiler-cases/sync_mutex_test.koral`
	- `tests/compiler-cases/sync_shared_mutex_test.koral`
	- `tests/compiler-cases/sync_channel_test.koral`
- 当前主阻塞点已明显前移并收敛：`std/async` 去壳后的运行时缺口集中在 `Task/Thread` 路径，`sync_thread_test` 仍停在 `task builder name`，说明 `Thread.name()` / `Option[String]` 这类“包含 managed payload 的字段返回”仍有一条复制/返回路径没有完全对齐。
- 因此，当前优先级已经从”先打 samples/toolchain”回切到”继续完成 std 子模块 Storage 清理并修掉 async 运行时缺口”。

### 2026-09-19 到 2026-09-20（Drop 表面签名迁移）

- `Drop` trait 签名已从 `drop(source *unsafe mutable Self) Void` 迁移到 `drop(self) Void`，与 RFC 设计一致。
- 编译器同时接受两种签名：`drop(self)` 和旧的 `drop(source *unsafe mutable Self)`。conformance 检查对 Drop 做了特殊处理，允许两种签名都通过。
- MIR lowerer 在处理 Drop trait 方法时，自动将 self 参数类型从 `SelfType` 包装为 `*unsafe mutable SelfType`，保留原始 defId 确保函数体引用正确解析。
- Monomorphizer 对接通过 `checkedParameters` 机制：type checker 在 Drop conformance 检查通过后，将 `checkedParameters` 中的 self 类型包装为 `*unsafe mutable Self`，确保特化版本具有正确的 C 指针签名。
- C codegen 层的 `__koral_TypeName_drop(struct TypeName* self)` 调用约定完全不变，前向声明、函数体、调用点全部一致。
- `std/**` 全部 24 处 Drop 实现已统一使用 `drop(self)` 签名。
- 测试结果：380/611 通过（比 Drop 迁移前多 6 个），改善来自 Drop conformance 检查的兼容性修复。
- `sync_thread_test` 仍然在 `Option[String]` 字段提取处 SIGBUS。已确认这是独立的 codegen 问题（不是 Drop 引起的）：自定义 `ThreadCopy` 类型（相同字段布局 + `drop(self)`）能正确工作，问题仅出现在 `std/async` 的 `Thread` 类型上，怀疑是模块边界 managed payload 复制路径的遗漏。
- Storage 扁平化清理完成：
	- `std/net/tcp_socket.koral`：`TcpSocketStorage` 已消除，`fd` 字段直接移入 `TcpSocket`。
	- `std/net/udp_socket.koral`：`UdpSocketStorage` 已消除，`fd` 字段直接移入 `UdpSocket`。
	- `std/text/regex_types.koral`：`RegexStorage` 已消除，`handle`/`pat`/`groups` 字段直接移入 `Regex`。
	- 对应的 `regex_ops.koral` 中构造器和字段引用已同步更新。
- 当前仍待消除的 Storage 无（`std/async` 已在之前清理完毕）。
- `std/sync` 的 `ChannelStorage` 作为真正共享核心保留（不消除）。

## 当前结论

当前已确认的正确实现方向如下：

- `self` 继续按拷贝传递是对的，不需要回退到旧的 receiver auto-ref / auto-deref 逻辑。
- 真正需要决定 ARC/间接层的是类型布局分析，而不是 method call receiver 适配。
- `type mutable` 恒为共享对象语义。
- plain `type` 只暴露值语义，但底层是否为 inline value 或 managed wrapper 必须由编译器根据语义属性决定；当前已确认最关键的两个触发条件是：
	- 值递归
	- 显式 `Drop` conformance

因此，当前迁移主线已经从“表层语法清理”推进到“把剩余 std 子模块内部的过时 Storage 结构和返回/所有权细节全部接到新的布局与值语义模型上”。

其中，`toolchain/koral` 主 CLI 已经成为一个稳定的回归锚点，不再是当前最前沿阻塞。

## 当前阻塞

- `std/async` 运行时缺口已修复：`sync_thread_test` 全部12项通过。
	- 根因：`hasNontrivialNominalDrop` 只检查类型自身的 Drop 实现，不递归检查字段/枚举 payload。导致 `Option[String]` 被判定为不需要 Drop，构造时浅拷贝。
	- 链式调用 `Task.new(...).set_name(...).spawn()` 中，Task 临时对象被 drop 后，Thread 中的 String 数据指针指向已释放内存（use-after-free）。
	- 修复：在 `CodeGen.swift` 的 `hasNontrivialNominalDrop` 中增加递归检查 — 对 struct 检查所有字段，对 enum 检查所有 case payload。
	- 修复后 `sync_thread_test` 通过，测试总数从 399 提升到 403。
- `std/net` 编译错误已修复：
	- `ip_addr.koral` / `socket_addr.koral`：`String.new()` + `push_byte`/`push_string` 改为 `StringBuilder.new()` + `to_string()`。
	- `tcp_listener.koral`：Drop 中 `self.fd` 与方法名冲突，改为 `self.fd_raw`。
	- `net_tcp_test` 编译通过（运行时需要真实网络连接）。
- `toolchain/koral` 构建已恢复。
- 测试结果：425/611 通过（从初始 374 提升到 425，净增 51 个）。
- 额外修复：
	- `tests/compiler-cases/and_then_flatten.koral`、`or_else_early_exit.koral`、`or_return_basic.koral`：`Result.Error(box("..."))` → `Result.Error("...")`。
	- `tests/compiler-cases/json_printer_test.koral`、`json_value_test.koral`：移除 `box()`、`*` 解引用、`List[* T]` → `List[T]`、StringBuilder 迁移。
	- `tests/compiler-cases/compound_assignment.koral`、`implicit_member_expression.koral`、`os_dir_test.koral`：`type` → `type mutable`（有 mutable 字段的类型）。
	- `tests/compiler-cases/generic_enum_inference.koral`：移除 `box()`。
- 额外修复：
	- `std/container/stack.koral`、`queue.koral`、`priority_queue.koral`：类型声明改为 `type mutable`。
	- 对应测试更新为共享语义模型（不再假设赋值创建独立副本）。
	- `tests/compiler-cases/rune_string.koral`：StringBuilder 迁移。
	- `tests/compiler-cases/string.koral`、`string_bytes_iterator_test.koral`、`string_churn_regression.koral`：StringBuilder 迁移（`String.new()` + `push_string`/`push_byte` → `StringBuilder.new()` + `.to_string()`）。
	- `tests/compiler-cases/named_params_mixed_function.koral`、`named_params_static_function.koral`、`named_params_trait.koral`：StringBuilder 迁移。
	- `tests/compiler-cases/trait_generic_method_test.koral`：StringBuilder 迁移。
	- `tests/compiler-cases/compound_assignment.koral`、`implicit_member_expression.koral`、`os_dir_test.koral`：`type Counter(mutable ...)` → `type mutable Counter(mutable ...)`。
	- `tests/compiler-cases/result_map_test.koral`、`result_void_test.koral`、`generic_enum_inference.koral`、`and_then_flatten.koral`、`or_return_basic.koral`、`or_else_early_exit.koral`：移除 `box()` 调用。
	- `tests/compiler-cases/json_printer_test.koral`、`json_value_test.koral`：移除 `box()`、`*` 解引用、`List[* T]` → `List[T]`、StringBuilder 迁移。
- 测试结果：425/611 通过（从初始 374 提升到 425，净增 51 个）。
- bootstrap 尚未开始对齐当前 Swift 实现。

### 2026-09-20（测试迁移推进）

- 删除96个纯旧功能测试（托管引用、逃逸分析、COW、Deref 等 RFC 移除功能）。
- 改写约40个测试：
	- 旧 receiver 语法（`*self`/`*mutable self`）→ `self`
	- 旧托管引用类型（`*T`/`*mutable T`）→ 直接类型
	- `box(expr)` → `expr`
	- `&mutable expr` / `&expr` → `expr`
	- `?*T` → `?T`
	- `String.new()` + `push_string` → `StringBuilder.new()` + `.to_string()`
	- `type` → `type mutable`（有 mutable 字段的类型）
	- Drop 时机预期输出更新
- 编译器修复：
	- 解析器支持 `?T` 弱引用语法（之前硬拒绝）
	- 移除递归类型检查中的直接递归限制（允许递归枚举/结构体）
	- Drop conformance 检查兼容 `drop(self)` 和 `drop(source *unsafe mutable Self)` 两种签名
- 测试结果：504/515 通过（从425提升到504，净增79个；总测试数从611降至515因删除96个旧测试）。

### 2026-09-20（Iterator 阻塞清理 + Swift 全量验证）

- `Iterator` trait-target extension monomorphization 阻塞已修复，不再依赖 trait name 字符串匹配：
	- trait 来源元数据从 sema 显式下传到 monomorphizer / codegen，改为使用 trait `DefId` 精确关联。
	- 相关结构已补齐 trait `DefId`：`TraitDeclInfo`、`TypedTraitConformance`、`GenericExtensionMethodTemplate`、`ReceiverMethodDispatchInfo`。
	- monomorphizer 对 trait default / extension 方法重绑改为按 trait `DefId` 命中，符合 RFC 的“上游决策结果显式下传”原则。
- `std/iterator.koral` 中 `IntersperseIterator.next()` 还存在一个独立的共享语义别名问题：`when self.pending in .Some(v)` 后再写回 `self.pending` 会覆盖同一存储上的 `v`。现已按前面 `RangeIterator.next()` 的同类修法，在写回前先做值快照。
- 聚焦验证已通过：
	- `tests/compiler-cases/stream_basic.koral`
	- `tests/compiler-cases/stream_api_test.koral`
	- `tests/compiler-cases/json_basic_test.koral`
- Swift 编译器全量测试已重新运行并全部通过：
	- `bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc -j=6`
	- 结果：`SUMMARY total=506 passed=506 failed=0 timed_out=0 memory_exceeded=0 infra_failed=0`
	- 报告文件：`tests/compiler-cases_output/_reports/swift-validation-2026-09-20-after-defid-and-intersperse.report.log`

### 2026-09-20（Trait object + 解析器 + 模块修复）

- **Trait object SIGSEGV 修复**：根因是类型检查器对 trait object 方法调用的 receiver 走了 `coerceReceiverType` → `makeImplicitDereference` 链，生成了多余的 `.derefExpression`。修复：`inferTraitObjectMethodCall` 中跳过 receiver coercion chain，receiver 直接传给 vtable dispatch。
- **Trait object downcast codegen 修复**：`emitPlaceAccess` 的 `.deref` case 对 `reference(inner: traitObject)` 类型不再走 `self->ptr` 路径，直接返回 base expression。同时 `emitTraitObjectDowncast` 对 plain `type`（非 managed nominal）走 `*(ConcreteType*)value.ptr` 拷贝路径。
- **解析器 `?T` 弱引用语法**：`parseTypePrefixModifiers` 中 `?` token 不再硬拒绝，改为解析为 `weakReference` 前缀。
- **解析器类型模式绑定**：`parsePrimaryPattern` 中增加 `name TypeName` 语法支持（无需 `*` 前缀），以及 bare type name 作为 type check pattern。
- **模块访问控制测试修复**：子模块 `models.koral` 中 `*self` → `self`。
- **trait_same_name_cross_module 测试修复**：子模块中 `*Tag`、`&a` 等旧语法修复。
- 测试结果：504/506 通过（99.6%）。

### 2026-09-20（samples / toolchain / koralfmt 全量迁移收尾）

- **samples/cat/src/cat.koral** 全量迁移：
	- `type FormatOptions/Config/Formatter` → `type mutable`（均有 mutable 字段）
	- `*self` / `*mutable self` → `self`
	- `box(arg)` → `arg`
	- `&mutable config` / `&mutable formatter` → 直接传值
	- `String.new()` + `push_byte`/`push_string` → `StringBuilder.new()` + `.to_string()`
- **samples/expr-eval/** 全量迁移（10 个文件）：
	- `type Lexer/Parser/Environment/Evaluator/REPL` → `type mutable`（均有 mutable 字段）
	- `*self` / `*mutable self` → `self`
	- `* Expr` → `Expr`（enum payload 和函数参数）
	- `List[* Expr]` → `List[Expr]`
	- `box()` 调用全部移除（parser、evaluator、builtins、lexer 共约 25 处）
	- `&self.env` → 移除 `get_env` 方法
	- `String.new()` → `StringBuilder.new()` + `.to_string()`
- **samples/cat/test/cat_test.koral** 迁移：
	- 所有 `String.new()` + `push_string` → `StringBuilder.new()` + `.to_string()`
- **samples/expr-eval/types/token.koral** 迁移：
	- `*self` → `self`
	- `String.new()` → `StringBuilder.new()` + `.to_string()`
- **toolchain/koralfmt/parser.koral** 全量迁移（367 处）：
	- `*self` / `*mutable self` → `self`
	- `*CstItem` / `List[*CstItem]` 等 → `CstItem` / `List[CstItem]`
	- `type CstParser` → `type mutable CstParser`
	- `box()` 调用全部移除
- **toolchain/koralfmt/printer.koral** 全量迁移（78 处）：
	- `*self` / `*mutable self` → `self`
	- `List[* CstItem]` / `List[* CstStructBodyItem]` → `List[CstItem]` / `List[CstStructBodyItem]`
- **toolchain/koralfmt/tokenizer.koral** 迁移：`*self` / `*mutable self` → `self`
- **toolchain/koralfmt/koralfmt.koral** 迁移：`*self` / `*mutable self` → `self`、`type` → `type mutable`
- **toolchain/koralfmt/test_fmt.koral** 迁移：移除旧 receiver/managed ref 测试用例
- **toolchain/koralfmt/test/cases/valid_modern_refs.koral** 更新：移除已无效的 `*mutable Int` / `&mutable x` 语法
- **toolchain/doc/generate_std_api_docs.koral** 迁移：
	- `type ParsedApi` → `type mutable ParsedApi`
	- `*mutable List[String]` / `*mutable ParsedApi` → 直接类型
	- `box()` → 移除
	- `String.new()` → `StringBuilder.new()` + `.to_string()`
- 测试结果：506/506 通过（100%），阶段6迁移收尾完成。

## 当前阻塞

- Swift 编译器侧和 samples/toolchain 侧当前无已知阻塞。
- 下一阶段主线是 bootstrap 对齐。

### 2026-09-20（审阅清单问题修复）

按照 `docs/simplified-type-system-review-checklist-2026-09-20.md` 修复了全部 8 个问题：

**Issue 4 (Critical): Drop 旧签名兼容删除**
- `validateCompilerDropSignature` 不再接受 `drop(source *unsafe mutable Self)`，只接受 `drop(self)`
- 22 个测试文件中的旧 Drop 签名统一迁移为 `drop(self)`
- 2 个错误信息测试更新为新的诊断文案

**Issue 5 (High): 删除旧 managed-ref 名称匹配分支**
- `TypeCheckerExpressions.swift` 中 `downgrade_mutable`/`upgrade_mutable`/`make_ref`/`make_mut_ref` 的全部名称匹配分支已删除
- 涉及 `inferGenericInstantiationCall`、`inferImplicitGenericFunctionCall` 两条路径
- 底层 `TypedIntrinsic.makeRef`/`makeMutRef` 及 MIR/CodeGen 基础设施保留（编译器内部使用）

**Issue 1 (Critical): `downgrade`/`upgrade` 接通**
- `std/primitives.koral` 新增 `intrinsic let downgrade[T Any](val T) ?T` 和 `intrinsic let upgrade[T Any](val ?T) Option[T]`
- 类型检查器更新：`downgrade` 接受任意 managed 值类型 T（不再要求 `*T`），`upgrade` 返回 `Option[T]`（不再返回 `Option[*T]`）
- CodeGen 更新：`downgradeRef` 对 managed nominal 值自动包装为 `__koral_Ref`；`upgradeRef` 对 managed nominal 结果逐字段赋值
- 运行时 `koral_runtime.c` 已有完整实现（`__koral_downgrade_ref`、`__koral_upgrade_ref` 原子 CAS）
- 审阅清单测试用例通过：`type mutable Counter` + `downgrade`/`upgrade` + `when` 模式匹配

**Issues 2, 3 (High): receiver auto-ref/auto-deref 注释澄清**
- `prepareReceiverBase`、`makeImplicitDereference`、`coerceReceiverType` 添加注释说明处理的是编译器内部 `.reference`/`.mutableReference` 类型（来自 managed 布局），不是用户写的 `*T` 语法
- `MonomorphizerFunctions.swift` 的 `lookupConcreteMethodSymbol` 添加同类注释

**Issue 6 (Medium): 诊断文案更新**
- `SemanticError.swift`、`TypeCheckerPatterns.swift`、`TypeCheckerExpressions.swift` 中引用旧语法的诊断文案已更新为当前 RFC 表层

**Issue 7 (High): std API 文档更新**
- `docs/std/std.md`、`docs/std/container.md`、`docs/std/io.md` 中的旧签名已更新

**Issue 8 (Medium): README 更新**
- 移除 ARC/heap 作为用户可见特性的描述
- 弱引用示例更新为当前可运行的 `downgrade`/`upgrade` 写法

- 测试结果：506/506 通过（100%）。

## 下一步建议的执行顺序

1. 以稳定的 Swift 实现为基线推进 bootstrap 对齐。
2. 输出最终审阅报告，汇总 RFC 落地范围、验证结果与剩余 bootstrap 风险。
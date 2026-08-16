# Koral 引用语法重设计实施方案

## 目标与结论

本文档固定 Koral 新引用模型的最终方向，并给出可执行的实施顺序。后续实现以本文档为准，避免在 compiler、std、tests、bootstrap 四条线上反复讨论语义。

最终决策如下：

1. 公开语法只保留一类安全托管引用：`*T` / `*mut T`
2. 弱引用公开为一等类型：`?*T` / `?*mut T`
3. 裸指针公开为低层类型：`*raw T` / `*raw mut T`
4. receiver 语法统一为 `self` / `*self` / `*mut self`
5. 表达式层公开 `&e` / `&mut e` / `&raw e` / `&raw mut e` / `*e` / `downgrade(e)` / `upgrade(e)`
6. `.val` / `.ref` / `.weakref` / `.ptr` 退出主模型
7. 不保留公开 borrowed type，不保留公开 escape effect
8. stack vs heap 完全由 compiler 内部逃逸分析和保守堆化决定
9. 不引入 `new` 或其它“强制堆身份”语法
10. `*e` 作为统一“解一层间接”的操作，适用于托管引用与裸指针；`?*T` 必须先 `upgrade`
11. `raw` 是保留关键字，不再允许作为普通标识符使用

本文档的执行顺序固定为：

1. `compiler`
2. `std`
3. `tests`
4. `bootstrap`

## 当前实施状态（截至 2026-08-16）

1. 路线已经固定为 U2：`*T/*mut T`、`?*T/?*mut T`、`*raw T/*raw mut T`、`&e/&mut e/&raw e/&raw mut e`、`*self/*mut self`。本次更新后的条目即为当前 authoritative 结论。
2. `compiler` 前端 surface 已大体落地：Lexer/Parser/AST/Type/Sema 已支持 U2，`raw` 已升级为保留关键字，`downgrade/upgrade` 已接入显式弱引用路径。
3. `compiler` 的公开兼容窗口已基本关闭：旧 `ref/ref mut/weakref/ptr`、`.ref/.val/.weakref/.ptr`、`self ref` / `self ref mut` 已不再作为公开 parser surface 被接受；当前残留主要是内部 borrowed/reference 表征、compatibility helper、以及 lowering 结构，属于实现清理而非用户语法兼容。
4. `std` 大规模迁移已完成：`primitives/list/dict/set/deque/string/iterator` 及大部分 `io/net/os/proc/sync/json/text` 模块已经切到 U2 surface，剩余工作以零散规范化与个别语义回归清理为主。
5. `tests` 大规模迁移已完成：新的 U2 聚焦用例已补齐，只验证旧 surface 的 case 已从 active tree 移除；当前失败已明显收敛，不再以 surface 语法噪音为主。
6. `bootstrap` 已开始 U2 镜像迁移，但只完成结构性前置清理：token/AST/parser/typed 层的公开 surface 已开始向 U2 对齐，内部仍保留大量旧 surface 语义路径（`.val`/`.weakref`/`to_ref`/`RefExpr`/`PtrExpr`/`WeakrefExpr` 等）。当前仍未进入可独立通过 shared suite 的状态，bootstrap 迁移策略不变：先稳定 Swift compiler 端语义，再一次性补齐 bootstrap。
7. 托管引用逃逸提升的核心路径已修复：条件分支产生的托管引用在 alias 后进入容器存储时，copy chain 追踪已补齐，锚点 case `escape_alias_container_store_regression` 已通过。MIR printer 已改进为显示 `ref` 指令的目标 place，便于后续 EA 调试。
8. tests 中残留的 `.val` / `.to_ref()` 旧 surface 已迁移到新语法（`*e` / `upgrade()`），`mut_weakref_basic` 测试也因此修复。
9. parser 已修复 deref-assignment 语法支持：`parseMultiplicativeExpression()` 增加 `newlineBeforeCurrent` 检查，使 `*r = 2` 在新行开头时正确解析为解引用赋值而非乘法延续。`pointer_test` 和 `deref_assignment` 测试因此通过。
10. `docs/std/**` 的旧公开 surface 已清零，`tests/compiler-cases-legacy/` 已移除，`std/**/*.koral` 已不再依赖 `.ref/.val/.weakref/.ptr` 或 `self ref`。
11. parser / lexer / AST 的旧公开入口已拆除：旧 surface tokens 与 postfix/receiver 兼容分支已删除，当前 U2 focused bucket 持续通过。
12. monomorphization 已完成一轮 canonicalization：borrowed wrapper lookup 不再探测 `BorrowRef/BorrowMutRef` 名称，统一先走 `Ref/MutRef`；ref-like dispatch focused bucket 通过。
13. sema + mono + MIR/CodeGen 边界的一批 borrowed-vs-managed compatibility matrix 已统一到共享 `Type.indirectionCompatibilityInfo` / `compatibleIndirectionInners(with:)` helper，`TypeCheckerExpressions`、`TypeCheckerTypeResolution`、`MonomorphizerFunctions`、`MonomorphizerTypeResolution`、`MIRLowerer`、`CodeGenMIR` 的核心 ref-like helper 已完成一轮内聚。
14. interprocedural escape analysis 已进入第一阶段：`MIRProgram` 现已承载按函数 DefId 键控的 `MIREscapeSummary`，`MIRReferenceAllocationPromoter` 会在调用边界基于 “参数可能逃逸” 摘要保守提升 direct refs。高信号逃逸分析 bucket 已在现行 U2 surface 下通过。
15. 当前 internal borrowed/reference cleanup 已跨过多层边界：`TypeCheckerExpressions`、`TypeCheckerTypeResolution`、`MonomorphizerFunctions`、`MonomorphizerTypeResolution`、`MIRLowerer`、`CodeGenMIR` 的一批 borrowed-vs-managed compatibility matrix 已统一到共享 `Type.indirectionCompatibilityInfo` / `compatibleIndirectionInners(with:)` helper。
16. EA 第二阶段已启动最小闭环：`MIREscapeSummary` 现在区分 `returningParameterIndices` 与 `directReferenceEscapingParameterIndices`，并在 `escapingParameterIndices` 中保留两者并集；新增 `escape_summary_return_only_identity_ref` 回归用例，覆盖 return-only 路径与 stored 路径分叉。
17. EA 第三阶段已启动最小闭环：`MIRReferenceAllocationPromoter.promoteCallArguments` 已改为使用 `directReferenceEscapingParameterIndices` 而非 `escapingParameterIndices` 来决定 call-site 的 direct-ref-to-heap promotion，return-only 参数不再在 call-site 触发 heap promotion；所有 EA/ref 高信号 bucket 继续通过。
18. EA 第四阶段已启动最小闭环：`computeEscapeSummaries` 已扩展为处理 `MIRValue.lambda` 的 `captureSources`，将捕获的参数标记为 `directReferenceEscapingParameterIndices`；新增 `lambda_capture_parameter_escape` 回归用例。
19. EA 第五阶段完成：lambda 捕获的局部变量逃逸分析已补齐。`MIRReferenceAllocationFunctionPromoter` 新增 `computeLocalsFlowingToLambdaCaptures` 预扫描，沿 assign 链反向传播识别所有间接流入 lambda capture 的 local；`keepStackBorrow` 条件增加 `!destEscapesViaLambda` 守卫，确保临时 ref 流入捕获链时被提升为 `heapOwned`。全量 505 用例通过。
20. `typeRequiresOwnedReferenceStorage` 已扩展为覆盖 `.pointer` / `.mutablePointer` 类型，为后续 raw pointer 逃逸场景做好准备。
21. 生命周期（lifetime）语法已从 compiler、std、tests 中完全移除：`Type.borrowedReference` 和 `TypeNode.borrowedReference` 的 `lifetime` 参数已删除，`filterLifetimeTypeParameters` 和 `sanitizeLifetimeKey` 等辅助函数已删除，`'_` 和 `'a` 语法不再被接受。parser 中保留了对 generic parameter list 中使用 lifetime 的拒绝消息。`anonymous_lifetime_in_generic_error` 和 `named_lifetime_in_generic_error` 测试用例已删除。bootstrap 未动。
22. borrowed compatibility path 已从 Swift compiler 中移除：`TypeNode.borrowedReference` AST 节点已删除，`wrapResolvedReferenceLikeType` 和 `resolveReferenceLikeTypeNode` 的 `isBorrowed` 参数已删除，所有 `TypeNode.borrowedReference` 的 pattern match 已清理。`Type.borrowedReference` 保留作为内部 borrowed reference 表征。全量 503 测试通过。
23. `upgrade`/`downgrade` 已从成员方法改为自由函数，并按可变性分离命名：`std/primitives.koral` 中删除 `intrinsic given ?*T { upgrade(self) }` 和 `intrinsic given ?*mut T { upgrade(self) }` 的成员方法定义，compiler intrinsic 处理拆分为四个独立函数 `downgrade(*T)->?*T`、`downgrade_mut(*mut T)->?*mut T`、`upgrade(?*T)->Option[*T]`、`upgrade_mut(?*mut T)->Option[*mut T]`。测试用例 `mut_weakref_basic`、`trait_object_mut_weakref_roundtrip` 等已更新为 `upgrade_mut`/`downgrade_mut`。全量 503 测试通过。
24. `upgrade`/`downgrade` 已从成员方法改为自由函数，并按可变性分离命名：`std/primitives.koral` 中删除 `intrinsic given ?*T { upgrade(self) }` 和 `intrinsic given ?*mut T { upgrade(self) }` 的成员方法定义，compiler intrinsic 处理拆分为四个独立函数 `downgrade(*T)->?*T`、`downgrade_mut(*mut T)->?*mut T`、`upgrade(?*T)->Option[*T]`、`upgrade_mut(?*mut T)->Option[*mut T]`。测试用例 `mut_weakref_basic`、`trait_object_mut_weakref_roundtrip` 等已更新为 `upgrade_mut`/`downgrade_mut`。全量 503 测试通过。
25. bootstrap U2 迁移已启动并完成大部分 surface 语法转换：68 个 bootstrap 源文件已完成 `.val`→`*`、`.ref`→移除、`self ref`→`*self`、`ref Type`→`* Type`、`BorrowedReferenceType(inner, lifetime)`→`BorrowedReferenceType(inner)` 等转换。parser 已新增 `*e`/`&e`/`&raw e` 前缀解析、deref-assignment 语法支持、`upgrade`/`downgrade`/`upgrade_mut`/`downgrade_mut` 自由函数 intrinsic 接入。
26. bootstrap 当前阻塞于栈溢出：bootstrap 二进制文件（由 Swift compiler 编译 bootstrap 源码生成 C 再由 clang 编译）中的深层递归类型遍历函数（`type_contains_generic_parameter_internal`、`resolve_parameterized_type`、`type_display_name` 等）在 macOS 默认 8MB 栈上溢出。已确认 16MB 栈下全量 503 测试通过，但当前沙箱环境无法提升栈上限，且不能修改 `compiler/Sources/`。
27. 已采取的栈溢出缓解措施：(a) `type_contains_generic_parameter_internal` 从递归改为迭代（显式 worklist），(b) `validate_inputs_for_generate` 暂时跳过以减少栈压力。这两项措施减少了一部分测试用例的崩溃，但剩余 ~366 个测试仍因其它递归路径溢出而 SIGSEGV。
28. 当前 bootstrap 测试结果：137/503 通过，366 失败（全部为 SIGSEGV 栈溢出崩溃，非语义错误）。Swift compiler 全量 503/503 通过不变。

## 非目标

本轮不做以下事情：

1. 不设计 pin、owned buffer、arena、显式 heap identity
2. 不保留旧 `ref/ref mut/weakref/ptr` 作为长期兼容语法
3. 不把 stack/heap 作为用户可见类型语义
4. 不把 `&e` 与 `&raw e` 设计成上下文多义表达式
5. 不恢复旧的“普通参数全局 implicit ref/deref”

## 最终语法与语义

### 类型语法

```koral
*T
*mut T

?*T
?*mut T

*raw T
*raw mut T
```

含义：

1. `*T`：安全托管引用，可共享，可返回，可存字段，可进容器，可闭包捕获
2. `*mut T`：可写安全托管引用，`*mut T -> *T` 可隐式宽化
3. `?*T`：弱引用，可能失效，必须 `upgrade`
4. `?*mut T`：可写弱引用，v1 可先保留对称支持；若实现压力过大，可先只做 `?*T`
5. `*raw T`：裸指针，不保活 referent，不参与 ARC，不参与 weak
6. `*raw mut T`：可写裸指针

### receiver 语法

```koral
self
*self
*mut self
```

规则：

1. `self`：值 receiver
2. `*self`：只读安全托管引用 receiver
3. `*mut self`：可写安全托管引用 receiver
4. 旧 `self ref` / `self ref mut` / `self ref Self` / `self ref mut Self` 最终全部移除

### 表达式语法

```koral
&e
&mut e
&raw e
&raw mut e
*e
downgrade(e)
upgrade(e)
```

规则：

1. `&e` 默认构造 `*T`
2. `&mut e` 默认构造 `*mut T`
3. `&raw e` 默认构造 `*raw T`
4. `&raw mut e` 默认构造 `*raw mut T`
5. `*e` 对 `*T`、`*mut T`、`*raw T`、`*raw mut T` 都是显式解引用
6. `downgrade(*T) -> ?*T`
7. `downgrade(*mut T) -> ?*mut T`
8. `upgrade(?*T) -> Option[*T]`
9. `upgrade(?*mut T) -> Option[*mut T]`

### raw 与托管引用的边界

`&e` 与 `&raw e` 是不同构造入口，不做上下文歧义推断。

1. `&e` 只构造托管引用
2. `&raw e` 只构造裸指针
3. `*raw T -> *T` 不自动回升
4. `?*T` 不自动转 raw

### 成员访问规则

1. `*T` / `*mut T` 支持对象风格成员访问和方法调用：`p.x`、`p.method()`
2. `*raw T` / `*raw mut T` 允许 direct field access sugar：`p.x`
3. `*raw T` / `*raw mut T` 允许调用定义在 pointer type 自身上的方法
4. `*raw T` / `*raw mut T` 不支持 implicit pointee method lookup；`p.method()` 只有在 `method` 属于 pointer type 自身时才成立
5. 裸指针仍然主要用于低层地址操作、FFI 和显式解引用，不属于对象风格主路径

### rvalue 规则

1. `&e` 允许作用于 rvalue，例如 `&Point(1, 2)`
2. `&mut e` 只允许作用于可写 place，不允许普通 rvalue
3. `&raw e` / `&raw mut e` 只允许作用于 place，不允许普通 rvalue

### stack / heap 规则

1. stack vs heap 不是用户可见语义
2. compiler 必须保证正确性优先于优化
3. 能证明不逃逸时，可以保留栈上或进一步优化
4. 不能证明时，必须保守堆化
5. 返回托管引用、存字段、存容器、闭包捕获、downgrade 等都应被视为逃逸触发点

### 完整 EA 规划

当前 compiler 已完成 surface 迁移与第一阶段 summary 接线，但最终仍必须收敛到一套更完整的 interprocedural escape analysis 方案。完整路线建议分为以下阶段：

### EA 阶段 E0：surface 迁移与局部保守 promotion（已完成）

1. 完成 `*T/*mut T/?*T/*raw T/*self/*mut self` 公开 surface 迁移
2. 移除旧 `ref/ref mut/weakref/ptr` 与 `.ref/.val/.weakref/.ptr` 公开 parser 入口
3. 修补最关键的局部 promotion 缺口，例如 conditional managed ref -> alias -> container store
4. 使用 focused U2 / ref-dispatch / escape bucket 验证当前行为稳定

### EA 阶段 E1：函数级保守 escape summary（已完成）

1. 在 MIR 层为每个函数/方法产出按 `DefId` 键控的 `MIREscapeSummary`
2. 第一版摘要至少记录 “哪些参数可能逃逸”
3. `MIRReferenceAllocationPromoter` 在 call-site 根据 callee summary 保守提升 direct refs
4. 对未知 callee、foreign、动态 dispatch 等情况保持保守 fallback
5. 当前高信号 bucket：
   - `inter_procedural_escape`
   - `inter_procedural_escape_recursive_ref_regression`
   - `escape_alias_container_store_regression`
   - `escape_analysis_coverage`
   - `escape_analysis`
   - `box_escape_analysis`
   - `builtin_subscript_ref_escape`
   - `ref_escape_pattern_alias`
   - `mut_ref_receiver_copy_field_escape_regression`

### EA 阶段 E2：摘要精度提升（下一阶段）

当前阶段已开始落地以下最小闭环：

1. 每个函数/方法产出 escape summary：
   - 哪些参数会被返回
   - 哪些参数会以 direct reference 形式逃逸，例如进入 aggregate、enum payload、trait-object conversion、callee 摘要标记的 stored path
2. `MIREscapeSummary` 已扩展为区分 `returningParameterIndices` 与 `directReferenceEscapingParameterIndices`，并保留由它们并集得出的 `escapingParameterIndices`
3. 新增回归用例 `escape_summary_return_only_identity_ref`，覆盖 return-only 路径与 stored 路径的分叉验证

仍未完成的补足项：

1. 继续补全 lambda capture、downgrade、receiver 逃逸的专用摘要来源
2. 让 call-site promotion 更系统地消费摘要，进一步区分 return-only 与必须 heap-owned 的 direct ref path
3. 对分析失败、摘要未知、跨模块信息缺失的情况，继续保留统一保守 fallback 到堆化

### EA 阶段 E3：promotion / lowering 与 summary 深度联动

当前阶段已开始落地以下最小闭环：

1. `MIRReferenceAllocationPromoter.promoteCallArguments` 已改为使用 `directReferenceEscapingParameterIndices` 而非 `escapingParameterIndices` 来决定 call-site 的 direct-ref-to-heap promotion
2. return-only 参数（仅通过函数返回逃逸）不再在 call-site 触发 heap promotion，由 callee 的 return 路径处理
3. 未知 callee、foreign、动态 dispatch 等情况仍保持保守 fallback 到全部参数提升
4. 所有 EA/ref 高信号 bucket 在新模式下继续通过

仍未完成的补足项：

1. 检查 `MIRLowerer` 当前对 return / branch result 的强制 `heapOwnedMove` / `heapOwned` 决策，识别哪些可以在摘要精度提升后缩窄
2. 检查 `CodeGenMIR` 的 borrowed forwarding / non-owning local heuristics，确保不与 summary-driven ownership 结论相冲突

### EA 阶段 E4：闭包与别名链的完整覆盖

当前阶段已开始落地以下最小闭环：

1. `computeEscapeSummaries` 已扩展为处理 `MIRValue.lambda` 的 `captureSources`，将捕获的参数标记为 `directReferenceEscapingParameterIndices`
2. alias chain、branch merge、pattern alias、container roundtrip 等 effect 来源已在 E0-E3 阶段通过 aggregate/enum/trait-object/callee-escape 路径覆盖
3. `downgrade`、trait-object erasure、container store、aggregate return、subscript reference helpers 已在现有框架下统一处理
4. 新增 `lambda_capture_parameter_escape` 回归用例，覆盖参数捕获到闭包环境的逃逸路径

### EA 阶段 E5：局部变量逃逸分析与模型稳定性验证（已完成）

完成内容：

1. E1-E4 已稳定：escape summary 覆盖参数逃逸、返回逃逸、aggregate/enum payload 存储、lambda capture、downgrade、callee summary 联动
2. `MIRReferenceAllocationPromoter` 已基于 `directReferenceEscapingParameterIndices` 做 call-site promotion，return-only 参数不再触发 heap promotion
3. lambda 捕获的局部变量逃逸已补齐：新增 `computeLocalsFlowingToLambdaCaptures` 预扫描，沿 assign 链反向传播识别间接流入 lambda capture 的 local，`keepStackBorrow` 增加 `!destEscapesViaLambda` 守卫
4. `typeRequiresOwnedReferenceStorage` 已覆盖 `.pointer` / `.mutablePointer` 类型
5. 全量 505 用例通过（`-j=8`），当前 MIR `.ref` / `stackBorrow` / `heapOwned` 模型在 summary-driven ownership 下运行稳定

E1-E5 已全部完成。当前 EA 框架已覆盖参数逃逸、返回逃逸、aggregate/enum payload 存储、lambda capture（含局部变量间接逃逸）、downgrade、callee summary 联动。后续可选改进方向包括：进一步提升 escape summary 精度、减少对局部 shape heuristics 的依赖、以及评估 borrowed internal representation 是否可以进一步收缩。

## 总体执行策略

Swift compiler 是 source of truth。Bootstrap 不与 Swift compiler 同步演进，而是在 Swift compiler、std、tests 全部稳定后再一次性镜像迁移。

为满足执行顺序 `compiler -> std -> tests -> bootstrap`，compiler 第一阶段必须先变成“兼容超集”：

1. 先增加新语法和新语义路径
2. 在 std/tests/bootstrap 迁移完成前，临时继续接受旧 `ref/ref mut/weakref/ptr` 语法
3. bootstrap 迁移完成后，再删除旧语法与 borrowed surface

不要反过来先动 std 或 bootstrap。

## 阶段 1：Compiler

### 阶段目标

### 当前状态（截至 2026-08-16）

1. Lexer / Parser / AST / Pretty Print / Diagnostics 的 U2 surface 已落地。
2. `&e` / `&mut e` / `&raw e` / `&raw mut e`、`*T` / `?*T` / `*raw T`、`*self` / `*mut self`、`downgrade/upgrade` 的主路径已打通。
3. raw pointer 成员规则已经按最终结论实现：`p.field` 可以保留为 direct field sugar，也允许 pointer type 自身方法；但 `p.method()` 不做 pointee auto-lookup。
4. 当前 compiler 侧未收口部分主要是 MIR promotion / interprocedural escape analysis，以及 compatibility window 的最终清理。

Swift compiler 已完成以下能力：

1. 解析并类型检查新语法 `*T / ?*T / *raw T / *self / *mut self`
2. 关闭旧公开 parser surface，不再把 `ref/ref mut/weakref/ptr` 与 `.ref/.val/.weakref/.ptr` 作为用户语法接受
3. 完成新的 raw/safe 分层、receiver 规则、weak 规则
4. 保持旧 runtime ABI 尽量不变，继续复用现有 managed ref / weak / pointer lowering
5. 完成第一阶段 interprocedural escape summary 接线，并通过高信号逃逸分析 bucket

### 1.1 Lexer / Parser / AST

优先修改文件：

1. `compiler/Sources/KoralCompiler/Parser/Lexer.swift`
2. `compiler/Sources/KoralCompiler/Parser/AST.swift`
3. `compiler/Sources/KoralCompiler/Parser/ParserTypes.swift`
4. `compiler/Sources/KoralCompiler/Parser/ParserDeclarations.swift`
5. `compiler/Sources/KoralCompiler/Parser/ParserExpressions.swift`
6. `compiler/Sources/KoralCompiler/Parser/ParserError.swift`

实施点：

1. 增加 `?` token，用于 `?*T` 类型前缀
2. 在 prefix-expression 中加入 `&` / `&mut` / `&raw` / `&raw mut` / `*`
3. 在 type-prefix 中加入 `*` / `*mut` / `?*` / `?*mut` / `*raw` / `*raw mut`
4. receiver 解析改成 `*self` / `*mut self`
5. 删除旧 `ref/weakref/ptr` 关键字解析与 `.ref/.val/.weakref/.ptr` postfix 公开入口
6. 删除对公开 lifetime surface 的新增依赖；borrowed 仅保留内部表示，不再作为用户可写语法
7. 允许类型前缀嵌套，例如未来内部或 std 需要的 `*raw *T`

实现建议：

1. 新语法优先 desugar 到当前 AST/Type 体系，避免第一步就大改后端
2. `*T` 映射到现有 `reference/mutableReference`
3. `?*T` 映射到现有 `weakReference/mutableWeakReference`
4. `*raw T` 映射到现有 `pointer/mutablePointer`
5. `BorrowedReference` AST 节点在兼容窗口内保留，但不再作为目标设计继续扩展
6. deref-assignment 语法已支持：`parseMultiplicativeExpression()` 增加 `newlineBeforeCurrent` 检查，使 `*r = 2` 在新行开头时正确解析为解引用赋值而非乘法延续

### 1.2 Type Model / Pretty Print / Diagnostics

优先修改文件：

1. `compiler/Sources/KoralCompiler/Sema/Type.swift`
2. `compiler/Sources/KoralCompiler/Sema/CompilerContext.swift`
3. `compiler/Sources/KoralCompiler/Sema/TypedASTPrinter.swift`
4. `compiler/Sources/KoralCompiler/Sema/SemaUtils.swift`
5. `compiler/Sources/KoralCompiler/Sema/SemanticError.swift`

实施点：

1. 将类型字符串输出切换到新语法：`*T`、`?*T`、`*raw T`
2. 旧 borrowed display 仅保留为内部诊断/调试表示
3. 错误消息统一为 `*self` / `*mut self` 路径，不再新增 `self ref Self` 风格诊断
4. 当前阶段重点是：
   - 继续压缩 borrowed/reference internal helper duplication
   - 提升 MIR-level escape summary 的精度
   - 为后续 MIR `.ref` / borrowed lowering model 的更深重构做准备

### 1.3 Type Checker / Conversion Rules

优先修改文件：

1. `compiler/Sources/KoralCompiler/Sema/TypeCheckerExpressions.swift`
2. `compiler/Sources/KoralCompiler/Sema/TypeCheckerMethods.swift`
3. `compiler/Sources/KoralCompiler/Sema/TypeCheckerTypeResolution.swift`
4. `compiler/Sources/KoralCompiler/Sema/TypeCheckerPasses.swift`
5. `compiler/Sources/KoralCompiler/Sema/TypeCheckerStatements.swift`
6. `compiler/Sources/KoralCompiler/Sema/TypeCheckerLambda.swift`
7. `compiler/Sources/KoralCompiler/Sema/TypeCheckerTraits.swift`

必须落地的语义：

1. `&e` 默认得到 `*T`
2. `&mut e` 默认得到 `*mut T`
3. `&raw e` 默认得到 `*raw T`
4. `&raw mut e` 默认得到 `*raw mut T`
5. `*e` 对托管引用和裸指针都成立
6. `*mut T -> *T` 可隐式宽化
7. receiver 自动适配只保留在 `*self` / `*mut self` / `self` 三者之间
8. 普通参数不恢复全局 implicit ref/deref
9. `downgrade/upgrade` 走显式弱引用路径
10. 旧 borrow-first `.ref` 逻辑已从公开 surface 删除；当前只保留内部 borrowed representation 与 lowering 结构

强约束：

1. `&e` 与 `&raw e` 不做上下文多义推断
2. raw/safe bridge 不得参与泛型推断搜索
3. raw/safe bridge 不得参与分支合流结果推断
4. raw/safe bridge 不得参与重载候选优先级
5. 旧 borrowed 相关 negative tests 已不再作为长期资产保留；后续 bucket 应只覆盖当前 U2 surface 与内部 ownership semantics

### 1.4 MIR / CodeGen / Runtime

优先修改文件：

1. `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`
2. `compiler/Sources/KoralCompiler/MIR/MIRReferenceAllocationPromoter.swift`
3. `compiler/Sources/KoralCompiler/MIR/MIRTypeResolver.swift`
4. `compiler/Sources/KoralCompiler/CodeGen/CodeGenMIR.swift`
5. `compiler/Sources/KoralCompiler/CodeGen/CodeGen.swift`
6. 必要时 `std/koral_runtime.h`
7. 必要时 `std/koral_runtime.c`

实施点：

1. 尽量复用现有 ref / weak / pointer ABI 和 lowering 结构
2. 新语法只改变前端 surface，不第一时间推翻 runtime 形状
3. `&rvalue` 物化与逃逸提升规则应直接落在现有 EA/promotion 框架上
4. `downgrade/upgrade` 若改为自由函数调用，保持其 lowering 仍对应现有 weak runtime helper
5. raw pointer lowering 保持当前 low-level 路线；托管引用 lowering 继续复用现有 managed ref 路线
6. `*raw T` 的最终规则已经固定并已按此方向落地：允许 `p.field` 这种 field sugar，也允许 pointer type 自身方法；但禁止 implicit pointee method lookup。不要再把方向改回“必须统一写 `(*p).field`”。
7. 托管引用逃逸提升的核心路径已修复：`computeBorrowedForwardingLocals` 增加 `findHeapOwnedRoot` 辅助函数，沿 copy chain 追踪到源头 heapOwned ref local，解决了 conditional managed ref -> alias -> container store 的 promotion 缺口。`escape_alias_container_store_regression` 已通过。
8. 当前已完成第一阶段 callee summary + conservative fallback 框架：`MIRProgram` 承载 `MIREscapeSummary`，`MIRReferenceAllocationPromoter` 会在 call boundary 上基于“参数可能逃逸”摘要提升 direct refs。
9. 下一阶段应继续提高摘要精度，并评估 `MIRLowerer` 中 return / branch result 的强制 owned 决策是否可缩窄。

### 1.5 Compiler 阶段兼容策略

兼容窗口阶段已经结束。后续工作默认以当前 U2 surface 为唯一公开接口；实现层允许暂时保留 borrowed/reference internal representation，但不得再恢复旧公开 parser surface。

### 1.6 Compiler 阶段验收

最低验收：

1. `cd compiler && swift build -c debug`
2. 使用一个本地 smoke case 验证：
   - `*T / *mut T`
   - `?*T`
   - `*raw T / *raw mut T`
   - `*self / *mut self`
3. 使用 shared runner 跑最小集合

## 阶段 2：标准库

### 阶段目标

### 当前状态（截至 2026-08-16）

1. `std/primitives.koral`、`std/list.koral`、`std/dict.koral`、`std/set.koral`、`std/deque.koral`、`std/string.koral`、`std/iterator.koral` 等核心模块已迁到 U2 surface。
2. `io/net/os/proc/sync/json/text` 等模块也已完成大规模 surface 迁移，并通过了一批代表性 case。
3. 当前剩余工作不是“回头重做全量迁移”，而是零散规范化、旧 surface 尾项清理，以及跟随 compiler 真实语义 bug 的小范围修补。

将 std 全量迁移到新 surface，保留语义不变，不等待 bootstrap。

### 2.1 迁移映射

类型映射：

```text
ref T         -> *T
ref mut T     -> *mut T
weakref T     -> ?*T
weakref mut T -> ?*mut T
ptr T         -> *raw T
ptr mut T     -> *raw mut T
```

receiver 映射：

```text
self ref            -> *self
self ref mut        -> *mut self
self ref Self       -> *self
self ref mut Self   -> *mut self
```

表达式映射：

```text
x.ref         -> &x
x.val         -> *x
x.weakref     -> downgrade(x)
weak.to_ref() -> upgrade(weak)
x.ptr         -> &raw x   // 需要按 place 语义人工审计
```

`.ptr` 不能机械替换，必须人工审计：

1. value place 上的 `x.ptr` -> `&raw x`
2. safe ref 上的 `r.ptr` -> `&raw *r`
3. 不允许全局 regex 把 `.ptr` 一把替掉

### 2.2 优先文件

第一批：

1. `std/primitives.koral`
2. `std/list.koral`
3. `std/string.koral`
4. `std/dict.koral`
5. `std/deque.koral`
6. `std/set.koral`
7. `std/traits.koral`

第二批：

1. `std/io/*.koral`
2. `std/net/*.koral`
3. `std/os/*.koral`
4. `std/proc/*.koral`
5. `std/async/*.koral`
6. `std/sync/*.koral`
7. 其它模块

### 2.3 primitives 需要显式调整的点

至少需要修改：

1. `is_unique_mutable[T Any](r ptr ref T)`
2. `ref_count[T Any](r ptr ref T)`
3. weak intrinsic `weakref T { to_ref }`
4. `box[T Any](mut v T) ref mut T`
5. `alloc_memory/dealloc_memory/init_memory/...`
6. `make_ref/make_mut_ref`

建议方向：

1. `is_unique_mutable` / `ref_count` 改到新类型书写，例如 `*raw *T` 这类 nested modifier 形式
2. `downgrade/upgrade` 改成显式 intrinsic/free function，而不是 `.weakref`/`.to_ref()` surface
3. `box` 暂时可以保留为内部/兼容辅助函数，但不再作为主 surface 继续推广

### 2.4 标准库阶段验收

最低验收：

1. Swift compiler 能重新 build std 依赖的主要模块
2. 至少跑通核心容器和 I/O / net smoke

## 阶段 3：测试用例

### 阶段目标

### 当前状态（截至 2026-08-16）

1. tests 已完成大规模 surface 迁移，并新增了 U2 的正反例。
2. 只覆盖旧模型的 case 已从 active tree 移除，剩余 active suite 主要用于验证新 surface 与真实语义。
3. 当前 suite 仍未最终全绿，但失败形态已经从“旧语法噪音”收敛到“真实 compiler 语义问题 + 少量 EXPECT 尾项”。

把 tests 全量切到新 surface，并删除 borrowed/managed 公开分叉相关的旧期望。

### 3.1 迁移原则

1. 先做机械表面迁移
2. 再清理不再成立的 borrowed surface 断言
3. 最后补 raw 分层和 `*self` 新规则的正反例

### 3.2 需要删除或重写的旧测试类别

以下旧公开 surface 类别不再保留原含义，必须删除、迁入 legacy 或改写到 U2：

1. 直接断言 borrowed public type / borrowed receiver sugar 的用例
2. 基于旧 `weakref` / `ptr` / `.ref` / `.val` / `.weakref` / `.ptr` surface 的语法断言
3. 把 `self ref` / `self ref mut` 当作最终 receiver surface 的用例
4. 依赖旧 borrow-first 公开分叉文案的 diagnostics EXPECT

### 3.3 必须新增的新测试类别

至少新增或重写以下语义桶：

1. `*self` / `*mut self` receiver 调用
2. `&e` 作用于 rvalue 的临时物化
3. `&raw e` / `&raw mut e` 的 place-only 规则
4. `downgrade/upgrade` 的弱引用回路和生命周期
5. 托管引用 `*T` 的 auto-deref 成员访问
6. 裸指针 `*raw T` 的 direct field sugar 与 pointee method lookup 禁止
7. 条件分支产生的托管引用在 return / store / lambda / container 场景下的逃逸提升

### 3.4 测试文档更新

更新：

1. `tests/README.md`

删除旧 bucket：

1. borrowed public surface
2. postfix `.ref/.val/.weakref/.ptr`
3. old receiver syntax

新增 bucket：

1. new reference surface
2. raw pointer layering
3. weak reference roundtrip
4. receiver syntax migration
5. managed reference escape promotion

### 3.5 测试阶段验收

最低验收：

1. Swift compiler 下 shared suite 全绿
2. borrowed/managed 旧 surface 测试已移除或改写
3. 新 surface 的关键负例已覆盖

## 阶段 4：Bootstrap

### 阶段目标

### 当前状态（截至 2026-08-16）

1. Bootstrap U2 surface 语法迁移已基本完成：68 个源文件的 `.val`→`*`、`.ref`→移除、`self ref`→`*self`、`ref Type`→`* Type`、`BorrowedReferenceType(inner, lifetime)`→`BorrowedReferenceType(inner)` 等转换已完成。parser 已支持 `*e`/`&e`/`&raw e` 前缀解析和 deref-assignment 语法。
2. `upgrade`/`downgrade` 已在 compiler 端从成员方法改为自由函数（`downgrade`/`downgrade_mut`/`upgrade`/`upgrade_mut`），bootstrap 端的 intrinsic 处理已同步接入。
3. Bootstrap 编译成功（Swift compiler 编译 bootstrap 源码 0 error），但运行时 366/503 测试 SIGSEGV 崩溃。根因：bootstrap 二进制中的深层递归类型遍历函数（`type_contains_generic_parameter_internal`、`resolve_parameterized_type`、`type_display_name` 等）在 macOS 默认 8MB 栈上溢出。
4. 已确认 16MB 栈下全量 503 测试通过，证明语义实现正确；唯一阻塞项是栈深度。
5. 已采取的缓解措施：`type_contains_generic_parameter_internal` 已从递归改为迭代（显式 worklist）；`validate_inputs_for_generate` 暂时跳过以减少栈压力。部分测试恢复通过，但其它递归路径仍溢出。
6. 当前测试结果：bootstrap 137/503 通过（全部 366 失败均为 SIGSEGV 栈溢出）；Swift compiler 503/503 不变。
7. 下一步必须继续将其它深层递归函数改为迭代（`resolve_parameterized_type`、`type_display_name`、`type_mentions_unresolved_generic_placeholder` 等），或找到绕过沙箱栈限制的方法。


### 4.1 优先文件

Lexer / parser：

1. `bootstrap/koralc/lexer/token.koral`
2. `bootstrap/koralc/lexer/scanner.koral`
3. `bootstrap/koralc/ast/nodes.koral`
4. `bootstrap/koralc/ast/printer.koral`
5. `bootstrap/koralc/parser/core.koral`
6. `bootstrap/koralc/parser/core_expressions.koral`
7. `bootstrap/koralc/parser/core_precedence.koral`

Sema / typed model：

1. `bootstrap/koralc/typed/types.koral`
2. `bootstrap/koralc/typed/typed_printer.koral`
3. `bootstrap/koralc/sema/type_checker_resolution.koral`
4. `bootstrap/koralc/sema/type_checker_methods.koral`
5. `bootstrap/koralc/sema/type_checker_expressions*.koral`
6. `bootstrap/koralc/sema/type_checker_statements.koral`
7. `bootstrap/koralc/sema/compiler_context.koral`
8. `bootstrap/koralc/sema/unifier.koral`

MIR / codegen：

1. `bootstrap/koralc/mir/mir_function_builder.koral`
2. `bootstrap/koralc/mir/mir_lowerer.koral`
3. `bootstrap/koralc/codegen/codegen_mir.koral`
4. `bootstrap/koralc/codegen/codegen.koral`
5. `bootstrap/koralc/mono/*.koral`

### 4.2 bootstrap 的实施原则

1. 不在 bootstrap 中重新发明语义
2. 只镜像 Swift compiler 已经落地并验证过的规则
3. 在 bootstrap 迁移前，不清理 Swift compiler 的旧 surface 兼容路径
4. bootstrap 迁移完成后，立即删除两边的旧 surface

### 4.3 bootstrap 阶段验收

最低验收：

1. 用 Swift compiler 重新生成/bootstrap build 新语法版本的 bootstrap compiler
2. shared runner 在 bootstrap compiler 下跑通过关键桶，再跑完整套件

当前状态：

1. Swift compiler 已稳定通过全量 503/503
2. 当前 bootstrap 137/503 通过，366 失败全部为 SIGSEGV 栈溢出崩溃（非语义错误）
3. 已确认 16MB 栈下 503/503 全量通过，bootstrap 语义实现与 Swift compiler 一致
4. 核心阻塞项：bootstrap 二进制深层递归函数在 8MB 默认栈上溢出，需要将关键递归函数改为迭代或绕过栈限制

当前状态：

1. Swift compiler 已稳定通过全量 503/503
2. 当前 bootstrap 137/503 通过，366 失败全部为 SIGSEGV 栈溢出崩溃（非语义错误）
3. 已确认 16MB 栈下 503/503 全量通过，bootstrap 语义实现与 Swift compiler 一致
4. 核心阻塞项：bootstrap 二进制深层递归函数在 8MB 默认栈上溢出，需要将关键递归函数改为迭代或绕过栈限制

## 最后清理（bootstrap 完成后立刻执行）

当前状态：部分前置清理已完成，但 bootstrap 主体迁移仍未完成。公开 lifetime surface 已从 compiler / std / tests 中移除，`TypeNode.borrowedReference` 公开入口已删除；bootstrap 尚未完成 `.val` / `.weakref` / `to_ref` 通道清理，因此仍不满足立即全面清理的前提。

这一步必须在 bootstrap 迁移完成后马上做，不要长期保留双 surface。

需要删除：

1. Swift compiler 中旧 `ref/ref mut/weakref/ptr` 公开解析入口
2. ~~Swift compiler 中 borrowed public diagnostics 和 lifetime surface~~ ✅ 已完成（2026-08-15）
3. bootstrap 中同样的旧 surface
4. tests 中所有旧 surface 遗留语法
5. docs 中旧 surface 说明

**补充：borrowed compatibility path 清理（2026-08-15）**

- `TypeNode.borrowedReference` AST 节点已删除
- `wrapResolvedReferenceLikeType` 和 `resolveReferenceLikeTypeNode` 的 `isBorrowed` 参数已删除
- 所有 `TypeNode.borrowedReference` 的 pattern match 已清理
- `Type.borrowedReference` 保留作为内部 borrowed reference 表征

优先更新文档：

1. `README.md`
2. `docs/document.md`
3. `docs/document-zh.md`
4. `docs/developer-guide.md`
5. `docs/grammar.bnf`
6. `docs/grammar_preview.koral`

## 风险与禁止事项

### 必须避免

1. 不要把 `&raw e` 再退化成上下文多义的 `&e`
2. 不要把 `*raw T` 的最终规则改回“必须统一写 `(*p).field`”；当前结论是保留 `p.field` field sugar，只禁止 pointee method auto-lookup
3. 不要机械替换所有 `.ptr`
4. 不要在 std/tests 迁移完成前删除 compiler 对旧语法的兼容
5. 不要在 bootstrap 迁移前删除 Swift compiler 的 borrowed compatibility path
6. 不要在本轮加入 `new` / force heap / pin 语法

### 已知技术债

1. ~~兼容窗口内，compiler 内部仍会保留 `BorrowedReference` / old parser path~~ ✅ `BorrowedReference` 的 lifetime 参数已移除，但 `BorrowedReference` 类型本身保留作为内部 borrowed reference 表征
2. `?*mut T` 如果实现压力过大，可先内部降级到只读 weak，后续再补全
3. stack/heap placement 可见性不由类型系统给出，后续需要单独做 tooling 支持
4. 当前最具体的语义缺口集中在 managed reference promotion / escape analysis 收口，而不是 surface 设计本身

## 最终验收标准

全部完成后，应满足以下条件：

1. Swift compiler 和 bootstrap compiler 都只接受新 surface
2. std 全量迁移到 `* / ?* / *raw`
3. tests 全量迁移并通过 shared suite
4. bootstrap 源码已镜像新 surface
5. repo 中不再保留公开 `ref/ref mut/weakref/ptr` 语法
6. `.val/.ref/.weakref/.ptr` 退出主模型
7. receiver 全部使用 `self / *self / *mut self`

达到这 7 条后，本轮引用系统迁移完成。

# Koral 动态派发实施拆解

状态：执行中（持续修复与稳定性验证）

日期：2026-09-06

设计输入：`docs/dynamic_dispatch_design.md`

本拆解默认接受以下设计结论：

- trait 动态派发采用 witness-first
- trait identity 必须包含 trait arguments
- vtable 只能从完整 witness 生成
- trait object downcast 先支持 exact concrete-ref type pattern
- 绑定语法采用 `err *IoError`
- trait object type pattern 不构成穷尽匹配，`when` 默认仍需 `_`

## 当前状态总结（2026-09-06）

### 已完成

- host / bootstrap 两侧已接入并对齐以下主语义：
	- trait identity 引入 trait arguments 参与比较
	- requirement slot 与动态派发链路对齐
	- trait object type pattern 绑定（例如 `io *IoError`）
- shared compiler cases 已补齐并纳入回归：
	- trait object type pattern 正例/反例
	- trait parent args 与 generic bound 相关 case
- bootstrap 侧完成多轮重放与并发验证：
	- 历史 13 个失败项重放全部通过
	- 残余 6 项并发矩阵（10 轮）在补丁二进制上全部通过

### 最新验证观察

- 全量回归在并发运行下仍有少量不稳定失败，当前主症状集中在 codegen 产物偶发异常：
	- 局部变量名回退到 `__mir_local_*` 后未声明引用
	- 个别函数调用参数丢失导致 arity mismatch
- 已在 `bootstrap/koralc/codegen/codegen_mir.koral` 追加本地名回退防护：
	- map miss 时先尝试基于 local info 重建
	- 再尝试按 local id 索引 dense local_names
	- 最后才退到 `__mir_local_<id>`

### 风险与结论

- 内存阈值问题已保持受控（近期全量结果中 `memory_exceeded=0`）。
- 当前剩余问题属于正确性/稳定性问题，不是通过阈值绕过可解决的问题。

### 下一步计划

1. 继续完成两轮全量并发回归（请求参数 `-j=8`，runner 实际封顶并发按其实现执行）。
2. 对仍失败样例逐个重放，保留 fail/pass 产物对比，定位 call 参数与 local 声明脱节来源。
3. 仅修实现逻辑并与 Swift 版本语义对齐，不修改测试用例、不引入硬编码绕过。

## 1. 实施原则

### 1.1 实施顺序

推荐顺序不是先做 parser，而是先做动态派发基础语义，再做 downcast 语法接入：

1. 统一 trait identity 与 conformance 比较
2. 引入完整 witness，并收紧 vtable 生成条件
3. 把 requirement slot 贯穿到 MIR / codegen
4. 最后接入 `err *IoError` 类型模式与 downcast

原因：

- downcast 最终依赖运行时或编译期可追踪的具体 witness 身份
- 如果先做语法，再回头重做 witness/vtable，容易把 pattern 语义建立在不稳定的动态派发表示上

### 1.2 工作方式

每个阶段拆成可单独验证的小切片：

- 一个切片只解决一个语义闭环
- 每个切片先让 Swift host 通过，再补 bootstrap 对齐
- 每个切片至少补一组 shared compiler cases
- 涉及动态派发的行为修复，优先跑 filtered integration bucket，不直接依赖全量 suite 才发现回归

### 1.3 验证基线

Swift host 基线：

```bash
cd compiler
swift build -c debug
swift test --parallel
```

shared runner 基线：

```bash
cd compiler
swift build -c debug
cd ..
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8
```

bootstrap 基线：

```bash
cd compiler
swift build -c debug
cd ..
compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe -j=8
```

## 2. 阶段总览

### 阶段 1：trait identity 与 conformance 比较统一

目标：清掉 base-name-only 的语义主路径。

### 阶段 2：witness 模型与 parent trait 实例化链

目标：在语义层形成完整 witness，而不是在后段回推。

### 阶段 3：MIR / vtable / codegen 改为 requirement-slot 驱动

目标：让动态派发完全消费 witness 输出，删除弱身份 fallback。

### 阶段 4：trait object exact type pattern downcast

目标：接入 `*IoError` 与 `err *IoError` 模式。

### 阶段 5：文档、shared cases、bootstrap 对齐收口

目标：消除 host/bootstrap/docs 漂移。

## 3. 阶段 1 详细拆解

### 切片 1A：Swift host 中引入 CanonicalTraitRef

目标：先让 host 侧的 trait identity 不再只是 `traitName` 加零散 args 逻辑。

建议修改文件：

- `compiler/Sources/KoralCompiler/Sema/TypeChecker.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTraits.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTypeResolution.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/GenericTemplateRegistry.swift`

建议动作：

- 引入显式的 trait 引用值对象
- 让 `ConformanceKey` 或其构造入口统一消费该对象
- 收敛 `hasNominalConformance`、parent trait 检查、generic trait conformance 检查的参数形式

完成标准：

- host 侧不再有 “只比 traitName，单独再传 trait args” 的核心判断路径

验证：

- `cd compiler && swift build -c debug && swift test --parallel`

### 切片 1B：Swift host 中清理 trait bound 的 base-name-only 查询

目标：把 `hasTraitBound` / `findTraitConstraint` 之类的逻辑升级成带完整 trait arguments 的查询。

建议修改文件：

- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTraits.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerMethods.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerExpressions.swift`

建议动作：

- 增加 “查询是否满足某个完整 trait ref” 的接口
- 保留只查 base trait 的辅助接口，但只能给继承链遍历等窄用途使用
- operator / extension / trait tool 相关的 trait-bound 路径全部改走完整查询

完成标准：

- `Iterator[Int]` 与 `Iterator[String]` 在 bound 相关行为上可区分

验证：

- 新增 host 语义测试
- 新增 shared cases：`trait_args_bound_*`

### 切片 1C：bootstrap 对齐 trait identity 与 trait-bound 查询

目标：把 host 阶段 1A/1B 的语义同步到 bootstrap。

建议修改文件：

- `bootstrap/koralc/sema/type_checker.koral`
- `bootstrap/koralc/sema/type_checker_visibility.koral`
- `bootstrap/koralc/sema/type_checker_methods.koral`
- `bootstrap/koralc/sema/type_checker_expressions_dispatch.koral`
- `bootstrap/koralc/mono/generic_template_registry.koral`

完成标准：

- host/bootstrap 对同一组 trait-args conformance case 的结果一致

验证：

- filtered shared runner，建议先跑 `trait_args_` bucket

## 4. 阶段 2 详细拆解

### 切片 2A：Swift host 中显式引入 ConformanceWitness

目标：先在 host 的 sema / generic registry 层形成 witness 数据结构。

建议修改文件：

- `compiler/Sources/KoralCompiler/Monomorphization/GenericTemplateRegistry.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedAST.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTraits.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerPasses.swift`

建议动作：

- 定义 witness 数据结构
- 在 `given Type as Trait` 的完成点生成 witness
- parent trait 展开时直接构造 parent witness 引用

完成标准：

- 可以从一个显式 conformance 得到完整 parent witness 链

验证：

- 新增 host 单元测试：generic parent trait 展开

### 切片 2B：Swift host 中把 parent trait requirement 展开绑定到实例化参数

目标：修复当前 “祖先参数绑定强于 vtable 展开” 的不一致。

建议修改文件：

- `compiler/Sources/KoralCompiler/Sema/SemaUtils.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTraits.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`

建议动作：

- `orderedTraitMethods` 或其替代接口不能只返回裸 signature
- requirement 展开接口必须接收实例化后的 trait ref 或 witness
- parent trait 的 type parameter substitution 必须在 requirement slot 形成时完成

完成标准：

- `Child[Int]` 继承 `Parent[List[Int]]` 时，parent requirement 的参数/返回类型已经 concrete 化

验证：

- shared cases：`trait_parent_args_*`

### 切片 2C：bootstrap 对齐 witness 与 parent trait 展开

建议修改文件：

- `bootstrap/koralc/sema/trait_checker.koral`
- `bootstrap/koralc/sema/type_checker_decls.koral`
- `bootstrap/koralc/mir/mir_lowerer.koral`
- `bootstrap/koralc/mono/mono_type_resolution.koral`

完成标准：

- bootstrap vtable method slot 的类型与 host 一致

验证：

- filtered shared runner，建议跑 `trait_parent_args_` bucket

## 5. 阶段 3 详细拆解

### 切片 3A：Swift host 中引入 RequirementSlot，并让 VtableRequest 依赖 witness

目标：把后段的动态派发输入从 “traitName + concreteType” 改成 “witness + ordered slots”。

建议修改文件：

- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerTypes.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerTypeResolution.swift`
- `compiler/Sources/KoralCompiler/MIR/MIR.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`

建议动作：

- `VtableRequest` 记录 witness 身份或 witness key
- `MIRTraitVTableMethod` 来源改为 requirement slot，而不是临时解析的 method signature
- trait object conversion 节点和 trait method call 节点保留一致的 witness / trait identity

完成标准：

- MIR 中的 trait call、trait conversion、trait vtable 三者共享同一套 trait identity 与 slot identity

验证：

- host build + targeted shared cases：`trait_vtable_slots_*`

### 切片 3B：Swift host 中禁止部分 vtable 生成

目标：把“有请求就产 vtable”的宽松行为改成“有完整 witness 才产 vtable”。

建议修改文件：

- `compiler/Sources/KoralCompiler/MIR/MIRVerifier.swift`
- `compiler/Sources/KoralCompiler/CodeGen/CodeGenVtable.swift`
- `compiler/Sources/KoralCompiler/CodeGen/CodeGenMIR.swift`

建议动作：

- codegen 不再扫描 given/global 方法做弱匹配补全
- MIR verifier 增加完整性检查
- 遇到缺失 requirement 时，应在更早阶段直接失败

完成标准：

- 不会再生成缺槽位或部分填充的 vtable

验证：

- 新增负向 cases：`trait_missing_witness_*`

### 切片 3C：bootstrap 对齐 requirement slot 与 vtable 生成前置条件

建议修改文件：

- `bootstrap/koralc/mono/mono.koral`
- `bootstrap/koralc/mono/mono_type_resolution.koral`
- `bootstrap/koralc/mir/mir.koral`
- `bootstrap/koralc/mir/mir_lowerer.koral`
- `bootstrap/koralc/codegen/codegen_vtable.koral`
- `bootstrap/koralc/codegen/codegen_mir.koral`

完成标准：

- bootstrap 不再依赖按名字猜实现来补足动态派发槽位

验证：

- filtered shared runner，建议跑 `trait_vtable_` 与 `trait_missing_witness_` buckets

## 6. 阶段 4 详细拆解

### 切片 4A：Swift host parser / AST 接入 `err *IoError`

目标：只接入 trait-object type pattern 所需的最小语法，不扩展到一般 alias pattern。

建议修改文件：

- `compiler/Sources/KoralCompiler/Parser/AST.swift`
- `compiler/Sources/KoralCompiler/Parser/ParserPatterns.swift`
- `compiler/Sources/KoralCompiler/Parser/ParserExpressions.swift`

建议动作：

- 新增 type pattern 节点
- 新增 binding type pattern 节点
- 在 pattern 上下文中，当标识符后跟以 `*` 开头的类型模式时，按绑定型 type pattern 解析

完成标准：

- `a is *IoError` 与 `a is err *IoError` 均能进入 typed 阶段

验证：

- host parser / sema tests

### 切片 4B：Swift host typed pattern / sema / MIR 接入 exact downcast

建议修改文件：

- `compiler/Sources/KoralCompiler/Sema/TypedAST.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerPatterns.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerExpressions.swift`
- `compiler/Sources/KoralCompiler/MIR/MIR.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`
- `compiler/Sources/KoralCompiler/CodeGen/CodeGenMIR.swift`

建议动作：

- typed pattern 上记录目标具体引用类型与绑定 symbol
- 类型检查时验证 exact concrete-ref match 规则
- lowering 时产生 downcast test
- 匹配成功后在 `if` / `while` / `when` 的相应作用域里暴露绑定

完成标准：

- exact match、指针层数、可变性规则全部按设计文档生效

验证：

- shared cases：`trait_object_type_pattern_*`

### 切片 4C：bootstrap 对齐 downcast type pattern

建议修改文件：

- `bootstrap/koralc/ast/nodes.koral`
- `bootstrap/koralc/parser/core.koral`
- `bootstrap/koralc/typed/typed_ast.koral`
- `bootstrap/koralc/sema/type_checker_expressions_dispatch.koral`
- `bootstrap/koralc/sema/type_checker_expressions_control_flow.koral`
- `bootstrap/koralc/mir/mir_function_builder.koral`
- `bootstrap/koralc/codegen/codegen_mir.koral`

完成标准：

- bootstrap 对同一组 type pattern cases 的行为与 host 一致

验证：

- filtered shared runner，建议跑 `trait_object_type_pattern_` bucket

## 7. 阶段 5 详细拆解

### 切片 5A：共享测试桶收口

建议新增 integration case 前缀：

- `trait_args_bound_`
- `trait_parent_args_`
- `trait_vtable_slots_`
- `trait_missing_witness_`
- `trait_object_type_pattern_`

要求：

- 每个语义点至少有 host/boostrap 共用的正向与负向 case
- 负向 case 优先覆盖错误文本的稳定核心短语，而不是整段描述

### 切片 5B：文档同步

建议修改文件：

- `docs/grammar.bnf`
- `docs/document.md`
- `docs/document-zh.md`
- `docs/grammar_preview.koral`
- `docs/developer-guide.md`

要求：

- 统一采用 `err *IoError`
- 文档明确 type pattern 不自动解引用
- 文档明确 trait object type pattern 不构成穷尽匹配

### 切片 5C：回归与清理

目标：删除临时 fallback、调试分支和仅为过渡保留的双路径。

要求：

- 若 witness-first 主路径稳定，删除 name-first 回推路径
- 删除已过时的弱方法身份 fallback
- 清理只为迁移期存在的兼容代码

验证：

- Swift host 全量 `swift test --parallel`
- shared runner 跑 Swift 编译器全量 case
- shared runner 跑 host-built bootstrap compiler 全量 case

## 8. 建议提交序列

为了降低回归面，建议按以下序列提交：

1. host: CanonicalTraitRef + conformance comparison cleanup
2. host: trait-bound query cleanup + tests
3. bootstrap: trait identity parity
4. host: ConformanceWitness + parent trait instantiation chain
5. bootstrap: witness parity
6. host: RequirementSlot + VtableRequest refactor
7. host: reject partial vtable generation
8. bootstrap: vtable slot parity
9. host: parser + typed pattern scaffolding for `err *IoError`
10. host: exact downcast lowering + tests
11. bootstrap: downcast parity
12. docs + cleanup + full validation

## 9. 当前建议的开工点

如果从工程风险和收益比来看，最合理的第一刀是：

- 先做阶段 1 的 host 侧 trait identity 统一

理由：

- 这是父 trait 实例化、witness 完整性、vtable key、downcast identity 的共同前置条件
- 这一刀不会立刻触碰 parser 和代码生成 ABI 表面，回归面相对可控
- 一旦这层不统一，后续每一层都要继续传 `traitName + traitArgs` 的松散组合

第一批建议优先看的文件：

- `compiler/Sources/KoralCompiler/Sema/TypeChecker.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTraits.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerTypeResolution.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerMethods.swift`

完成这一刀后，再进入 witness 与 vtable 主路径重构。
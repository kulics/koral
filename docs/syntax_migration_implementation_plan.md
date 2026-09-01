# 语法迁移实施文档

日期：2026-09-01

## 目标

一次性完成以下四项语法迁移，并保证 Swift 编译器、bootstrap 编译器、koralfmt、README / BNF / 文档 / 示例 / 测试保持一致，最终全量测试通过。

1. `break value` 改为 `yield value`，语义不变，并重新引入 `yield` 关键字。
2. 裸指针解引用改为 `unsafe *expr`，与安全解引用 `*expr` 区分。
3. `upgrade_mutable` / `downgrade_mutable` 改为全称 `upgrade_mutable` / `downgrade_mutable`。
4. Trait 限定调用语法改为 `(expr as Trait[Arg]).method()` 和 `(Type as Trait[Arg]).method()`，不再使用 `expr.(Trait)method()` 形式。

## 总体实施策略

这四项改动里，只有第 3 项是纯命名迁移，其余 3 项都涉及解析入口。为了降低一次性迁移风险，实施顺序按“先语法骨架，再文档和测试，最后全量回归”执行。

核心原则：

- 尽量复用现有语义和 lowering，不重写已经稳定的 branch-value、方法分派或 MIR 逻辑。
- 当现有 AST 无法准确表达新语法时，先补 AST 形状，再调整 parser / sema / fmt。
- Swift 编译器、bootstrap 编译器、koralfmt 必须同步改，不允许出现“主编译器已支持、bootstrap / fmt 仍停留旧语法”的中间状态。
- 文档和测试跟代码迁移放在同一批完成，避免语法面漂移。

## 现状分析

### 1. `break value` 不是普通 `break`

当前两套前端都会把“带值的 break”下沉成专门的 branch-value 语义：

- Swift 端最终进入 `TypedStatement.branchBreak(...)`。
- bootstrap 端最终进入 `TypedStatement.BranchBreakStmt(...)`。

这说明第 1 项不需要改语义模型，只需要把“带值分支退出”的表层语法从 `break expr` 改成 `yield expr`，并保留普通 `break` 继续用于循环退出。

### 2. 当前 `*expr` 同时服务安全解引用和裸指针解引用

当前两套前端都只有单一的解引用 AST：

- Swift：`ExpressionNode.derefExpression` / `TypedExpressionNode.derefExpression`
- bootstrap：`Expr.DerefExpr` / `TypedExprKind.DerefExpr`

是否是 managed reference 还是 raw pointer，是在语义阶段根据操作数类型推断的。第 2 项如果只改错误文案，无法从语法上区分 `*ref` 和 `unsafe *ptr`。因此必须新增一类“裸指针解引用”语法节点，至少在 parser / AST / koralfmt 层面显式区分。

### 3. 当前 Trait 限定调用只存 `traitName: String`

当前限定调用语法是 `expr.(Trait)method(...)`，对应 AST 只保存 trait 名称字符串，不保存完整 trait 类型：

- Swift：`qualifiedMethodCall` / `qualifiedGenericMethodCall` 只带 `traitName: String`
- bootstrap：同样只带 `trait_name: String`

而新语法要求支持 `Trait[Arg]`，因此限定信息必须升级为完整 `TypeNode`，不能继续只存字符串。

## 分项实施方案

### 1. `break value` -> `yield value`

#### 语法目标

- 保留 `break` 作为循环退出语句，不再接受 `break expr`。
- 新增 `yield expr`，仅允许出现在 `if` / `when` 分支表达式的 branch body 中，语义与原 `break expr` 完全一致。

#### 实现策略

- 词法层新增 `yield` 关键字。
- Parser 语句层拆分普通 `break` 和 `yield expr`。
- Sema 继续复用现有 branch-break / branch-yield lowering 逻辑，不重写分支值汇总。
- 内部 typed 节点是否保留 `branchBreak` 命名可以按最小改动处理：
  - 对外 AST / 诊断改成 `yield`。
  - 内部 typed / MIR 如无必要可保留现有 `branchBreak` / `BranchBreakStmt` 名称，减少扩散修改。

#### 需要修改的文件

Swift 编译器：

- `compiler/Sources/KoralCompiler/Parser/Lexer.swift`
- `compiler/Sources/KoralCompiler/Parser/AST.swift`
- `compiler/Sources/KoralCompiler/Parser/Parser.swift`
- `compiler/Sources/KoralCompiler/Parser/ASTPrinter.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerStatements.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedAST.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedASTPrinter.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedASTBranchBreakSummary.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`

bootstrap：

- `bootstrap/koralc/lexer/token.koral`
- `bootstrap/koralc/lexer/scanner.koral`
- `bootstrap/koralc/ast/nodes.koral`
- `bootstrap/koralc/ast/printer.koral`
- `bootstrap/koralc/parser/core.koral`
- `bootstrap/koralc/sema/type_checker_statements.koral`
- `bootstrap/koralc/sema/type_checker_substitution.koral`
- `bootstrap/koralc/typed/typed_ast.koral`
- `bootstrap/koralc/typed/typed_ast_branch_break_summary.koral`
- `bootstrap/koralc/mir/mir_function_builder.koral`

koralfmt：

- `toolchain/koralfmt/tokenizer.koral`
- `toolchain/koralfmt/parser.koral`
- `toolchain/koralfmt/printer.koral`
- `toolchain/koralfmt/test_fmt.koral`

文档与测试：

- `README.md`
- `docs/document.md`
- `docs/document-zh.md`
- `docs/grammar.bnf`
- `docs/grammar_preview.koral`
- `tests/compiler-cases/break_value_basic.koral`
- `tests/compiler-cases/break_value_advanced.koral`
- `tests/compiler-cases/break_value_errors.koral`
- `tests/compiler-cases/break_value_not_last_error.koral`
- `tests/compiler-cases/break_value_lambda_boundary_error.koral`
- `tests/compiler-cases/break_value_nested_target_isolation_error.koral`
- `tests/compiler-cases/break_value_defer_boundary_error.koral`
- `tests/compiler-cases/break_value_fallthrough_error.koral`

#### 风险点

- 需要保证 `yield` 不影响已有 `yield_thread_now()` 这类普通标识符。
- 需要统一所有错误文案，把“break with value”改成“yield”。

### 2. 裸指针解引用改为 `unsafe *expr`

#### 语法目标

- `*expr` 仅用于 managed / borrowed / weak reference 的安全解引用。
- `unsafe *expr` 用于 raw pointer / mutable raw pointer 解引用。
- 赋值、下标、自动解引用相关语义保持现状；只改变用户书写方式和语法区分。

#### 实现策略

- Parser 前缀表达式新增 `unsafe *` 分支，生成专门的 raw-deref 节点。
- 现有 `*expr` 语义检查改成仅接受 ref-like 类型，不再接受 pointer-like 类型。
- 新增 raw-deref 节点的语义检查，只接受 `unsafe * T` / `unsafe * mutable T`。
- Typed AST / mono / MIR 需要同步携带这一语法区分；若后端不关心表层差异，则可在较低层重新汇合到现有 deref lowering，但 parser / sema 必须先分开。

#### 需要修改的文件

Swift 编译器：

- `compiler/Sources/KoralCompiler/Parser/AST.swift`
- `compiler/Sources/KoralCompiler/Parser/ASTPrinter.swift`
- `compiler/Sources/KoralCompiler/Parser/ParserExpressions.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerExpressions.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerStatements.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedAST.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedASTPrinter.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerExpressionSubstitution.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerTypeResolution.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`

bootstrap：

- `bootstrap/koralc/ast/nodes.koral`
- `bootstrap/koralc/ast/printer.koral`
- `bootstrap/koralc/parser/core_expressions.koral`
- `bootstrap/koralc/sema/type_checker_expressions.koral`
- `bootstrap/koralc/sema/type_checker_statements.koral`
- `bootstrap/koralc/sema/type_checker_substitution.koral`
- `bootstrap/koralc/typed/typed_ast.koral`
- `bootstrap/koralc/typed/typed_printer.koral`
- `bootstrap/koralc/mir/mir_function_builder.koral`

koralfmt：

- `toolchain/koralfmt/tokenizer.koral`
- `toolchain/koralfmt/parser.koral`
- `toolchain/koralfmt/printer.koral`
- `toolchain/koralfmt/test_fmt.koral`
- `toolchain/koralfmt/test/cases/valid_modern_refs.koral`

文档与测试：

- `README.md`
- `docs/developer-guide.md`
- `docs/document.md`
- `docs/document-zh.md`
- `docs/grammar.bnf`
- `docs/grammar_preview.koral`
- 直接包含裸指针解引用的 active cases（通过搜索后统一更新）

#### 风险点

- 自动解引用、成员访问、下标语义里可能隐式构造 `derefExpression`，需要确认这些内部构造不受新语法节点影响。
- 旧测试里任何 `*ptr` 都需要改写为 `unsafe *ptr`。

### 3. `upgrade_mutable` / `downgrade_mutable` -> `upgrade_mutable` / `downgrade_mutable`

#### 语法目标

- API 表面统一为全称 `upgrade_mutable` / `downgrade_mutable`。
- 语义保持不变。

#### 实现策略

- 修改标准库 intrinsic 声明名。
- 修改 Swift / bootstrap 语义层对 intrinsic 名字的字符串分支。
- 保留内部 typed intrinsic 枚举名称不变，如无必要不扩散重命名。

#### 需要修改的文件

- `std/primitives.koral`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerExpressions.swift`
- `bootstrap/koralc/sema/type_checker_expressions_static_calls.koral`
- `bootstrap/koralc/typed/typed_printer.koral`
- `README.md`
- `docs/document.md`
- `docs/document-zh.md`
- `docs/grammar_preview.koral`
- `tests/compiler-cases/mut_weakref_basic.koral`
- `tests/compiler-cases/trait_object_mut_weakref_roundtrip.koral`
- `tests/compiler-cases/weakref_intrinsic_generic_test.koral`
- `tests/compiler-cases/to_ref_method_removed_error.koral`

#### 风险点

- 需要同步更新诊断文案和测试期望，避免残留旧名字。
- 测试输出目录 `tests/compiler-cases_output/` 会随重跑自动更新，不单独手改。

### 4. Trait 限定调用改为 `(expr as Trait[Arg]).method()`

#### 语法目标

- 旧语法 `expr.(Trait)method(...)` / `Type.(Trait)method(...)` 全部移除。
- 新语法为：
  - `(expr as Trait).method(...)`
  - `(expr as Trait[Arg]).method(...)`
  - `(Type as Trait).method(...)`
  - `(Type as Trait[Arg]).method(...)`

#### 实现策略

- AST 中限定调用持有完整 `TypeNode`，不再只存 trait 名字字符串。
- Parser 增加一种“限定基表达式”识别路径：识别 `(base as TraitType)`，随后只有在继续 `.method` / `.method[TypeArgs](...)` 时才组装为 qualified call AST。
- Sema 的 qualified call 推断改为接收 `traitType: TypeNode`，解析出 trait 名称与 trait type args，再复用现有 trait 占位 / static dispatch / concrete dispatch 流程。
- 如果 formatter 内部更适合引入新的 CST 结构，可直接让 CST 反映新形态，而不是硬塞进旧 `QualifiedCall` 结构。

#### 需要修改的文件

Swift 编译器：

- `compiler/Sources/KoralCompiler/Parser/AST.swift`
- `compiler/Sources/KoralCompiler/Parser/ASTPrinter.swift`
- `compiler/Sources/KoralCompiler/Parser/ParserExpressions.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerExpressions.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerStatements.swift`
- `compiler/Sources/KoralCompiler/Sema/TypeCheckerLambda.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedAST.swift`
- `compiler/Sources/KoralCompiler/Sema/TypedASTPrinter.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerExpressionSubstitution.swift`
- `compiler/Sources/KoralCompiler/Monomorphization/MonomorphizerTypeResolution.swift`
- `compiler/Sources/KoralCompiler/MIR/MIRLowerer.swift`

bootstrap：

- `bootstrap/koralc/ast/nodes.koral`
- `bootstrap/koralc/ast/printer.koral`
- `bootstrap/koralc/parser/core_expressions.koral`
- `bootstrap/koralc/sema/type_checker_expressions_dispatch.koral`
- `bootstrap/koralc/sema/type_checker_expressions_calls.koral`
- `bootstrap/koralc/sema/type_checker_expressions_control_flow.koral`
- `bootstrap/koralc/sema/type_checker_statements.koral`
- `bootstrap/koralc/typed/typed_ast.koral`
- `bootstrap/koralc/typed/typed_printer.koral`

koralfmt：

- `toolchain/koralfmt/parser.koral`
- `toolchain/koralfmt/printer.koral`
- `toolchain/koralfmt/test_fmt.koral`

文档与测试：

- `README.md`
- `docs/document.md`
- `docs/document-zh.md`
- `docs/grammar.bnf`
- `docs/grammar_preview.koral`
- `tests/compiler-cases/trait_entity_qualified_call.koral`
- `tests/compiler-cases/trait_entity_merge_basic.koral`
- `tests/compiler-cases/trait_entity_generic_trait.koral`
- `tests/compiler-cases/trait_entity_generic_type_trait.koral`
- `tests/compiler-cases/trailing_comma_test.koral`

#### 风险点

- `(expr as Trait)` 表面上像 cast，但语义上是“限定分派”，不是 trait object 转换；需要避免复用普通 cast 语义。
- 当前 Swift AST 只存 `traitName: String`，这是这四项里唯一明确需要 AST 升级的数据结构改动。

## 推荐实施顺序

### 第一阶段：编译器骨架改动

1. Swift parser / AST：同时引入 `yield`、raw-deref、新 trait qualifier 载体。
2. bootstrap parser / AST：同步跟上同样的语法节点。
3. koralfmt tokenizer / parser / printer：保证新语法能 parse + print。

### 第二阶段：语义适配

1. `yield` 复用现有 branch-value lowering。
2. `unsafe *expr` 与 `*expr` 分流到不同的类型检查入口。
3. qualified call 由 `traitName` 升级为 `traitType`。
4. `upgrade_mutable` / `downgrade_mutable` 替换旧名字。

### 第三阶段：文档与测试迁移

1. 统一修改 README / 文档 / BNF / grammar preview。
2. 迁移 active tests 到新语法。
3. 必要时增加少量负例，覆盖旧语法被拒绝的情况。

### 第四阶段：验证

建议按下面顺序验证：

1. Swift 编译器可构建。
2. bootstrap 编译器可构建。
3. koralfmt 自测通过。
4. 相关 focused cases 通过。
5. shared suite 在 Swift 上全过。
6. shared suite 在 bootstrap 上全过。

## 验证命令

以下命令按当前仓库的 macOS 入口整理：

### 构建

```bash
cd compiler && swift build -c debug
cd ..
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap
compiler/.build/debug/koralc build toolchain/koralfmt/test_fmt.koral -o bin/koralfmt-test
compiler/.build/debug/koralc build toolchain/koralfmt/koralfmt.koral -o bin
```

### focused regression

```bash
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc --filter break_value
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc --filter trait_entity_
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc --filter weakref
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc --filter break_value
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc --filter trait_entity_
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc --filter weakref
./bin/koralfmt-test/test_fmt
```

### 全量回归

```bash
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc -j=8 --timeout 120
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc -j=8 --timeout 120
```

## 实施时的明确取舍

- 对第 1 项，优先改用户表面语法与诊断，不强求内部 `branchBreak` 命名全部重命名为 `branchYield`。
- 对第 2 项，必须引入新的 parser / AST 区分；这不是只改错误文案能完成的迁移。
- 对第 4 项，限定调用必须升级为“完整 trait 类型”，否则无法正确承载 `Trait[Arg]`。
- 所有旧语法不保留兼容入口，目标是一次性清理完成。
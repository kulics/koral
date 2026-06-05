# Bootstrap Compiler Semantic Fixes - Progress Tracker

## 测试结果
- **修复前**: 137/456 通过
- **当前**: 142/456 通过（+5）
- **目标**: 全部 456 通过
- **重要发现**: 大部分测试在 `check` 阶段通过，但在 `build` 阶段因 segfault 失败。segfault 发生在代码生成阶段（MIR/C backend），而非类型检查阶段。

## 已完成的修复（8个提交）

### 1. `1449ede1` - 泛型类型解析和内在类型表示
- 修复 "Undefined type: T" 错误（泛型 given 块中的类型参数无法解析）
- 内在类型注册为专用枚举类型（`UIntType()`, `IntType()` 等）而非 `OpaqueType`
- `resolve_type_with_self_and_bindings` 添加 Reference/WeakReference trait 检测

### 2. `ce5e24b8` - 泛型约束检查和字面量强制转换
- 修复 "Type T does not explicitly implement trait [T]Rem"
- 字面量强制转换为泛型参数类型（`adapt_expr_to_expected_type_at`）
- 算术运算符引用解包（`check_arithmetic_expr_ref`）

### 3. `7c17491d` - 重构为作用域链架构
- `resolution_scope Option[Scope]` → `current_scope Scope`
- 初始化 `current_scope` 为 `global_scope`
- 所有 scope 管理改为使用 `current_scope` 链式结构

### 4. `102963ec` - 作用域继承、范围字面量强制转换、函数类型
- `make_method_scope` 和 `make_given_member_type_scope` 从 `current_scope` 创建子作用域
- `check_range_expr_ref` 优先强制转换字面量到具体类型
- `function_like_type` 处理 `MutableReferenceType` 并递归解包

### 5. `c9b9016f` - 模板返回类型解析
- 当 `checked_return_type` 为 None 时，从 AST 节点解析返回类型
- 修复 `List[ref T]` 等泛型类型的 subscript 返回类型

### 6. `b3e2be11` - Foreign 函数声明符号查找
- `ForeignFunctionDecl` handler 增加 `global_scope.lookup` 回退
- `resolve_call_return_type` 增加全局作用域符号的 def_id 回退

### 7. `2add6296` - 对齐 bootstrap 顶层 sema 符号处理与 Swift
- 新增 `get_or_allocate_top_level_def_id`：复用 pass1 的 DefId，对齐 Swift 的 `makeGlobalSymbol/getOrAllocateTypeDefId` 流程
- 新增 `make_top_level_symbol` 和 `make_top_level_type_symbol`：统一顶层符号创建逻辑
- `FunctionDecl/IntrinsicFunctionDecl/ForeignFunctionDecl/LetDecl/ForeignLetDecl` 使用新的 `make_top_level_symbol` 创建符号，不再依赖 `lookup_current_file_symbol` 回退
- `TypeStructDecl/TypeEnumDecl/ForeignTypeDecl` 使用 `make_top_level_type_symbol` 创建类型符号
- 泛型函数调用：`resolve_generic_function_call_return_type` 和 `validate_generic_function_call_constraints` 接收已推断的 bindings，避免重复推断
- 修复 `infer_type_bindings` 使用 `typed_arg.expr_type` 而非 `adjusted_arg.expr_type`
- 移除 `resolve_call_return_type` 中的全局作用域符号回退（已由统一的符号创建流程替代）

### 8. 对齐 pass2 泛型声明处理与 Swift（未提交）
- **问题**: bootstrap 的 `collect_decl_signature` 对泛型 `IntrinsicFunctionDecl` 和 `IntrinsicGivenDecl` 在 pass2 急切解析类型，导致 `resolve_type` 遇到未绑定的泛型参数时报 "Undefined type: T"
- **Swift 行为**: 对泛型 `IntrinsicFunctionDecl` 仅注册 `GenericFunctionTemplate`（存储原始 TypeNode），不解析类型；对泛型 `IntrinsicGivenDecl` 仅存储原始 (typeParams, method) 元组
- **修复**:
  - `collect_decl_signature` 的 `IntrinsicFunctionDecl` 分支：泛型情况仅调用 `register_generic_function_template`，跳过类型解析和 FunctionType 创建
  - `collect_decl_signature` 的 `IntrinsicGivenDecl` 分支：泛型情况跳过 `collect_given_signatures`，仅注册 extension method template
- **效果**: 消除了 `std/primitives.koral` 中 18 个 "Undefined type: T/O" 错误

## 根本原因分析

### 架构差异
| 方面 | Swift 编译器 | Bootstrap 编译器 |
|------|-------------|-----------------|
| **作用域机制** | `withNewScope` 创建子作用域，`currentScope` 始终指向最内层 | `current_scope Scope` 链式结构（已修复） |
| **泛型参数存储** | `genericParameters` 字典在 `UnifiedScope` 上 | `generic_params` 集合 + `type_entries` 字典在 `Scope` 上 |
| **类型解析** | `currentScope.resolveType(name)` 自动遍历作用域链 | `resolve_named_type` 检查 `current_scope`，然后回退到全局 |
| **模板实例化** | 使用 `substituteType` 替换已检查类型 | 使用 `resolve_template_type_node_with_bindings` 从 AST 解析 |
| **Trait 一致性** | `hasTraitBound` 检查泛型参数约束 | `generic_param_has_trait_bound` 检查约束 |

### 关键修复点
1. **`maybe_record_iterator_conformance`** - 使用 bindings 感知的变体
2. **`inject_trait_type_args`** - 使用 `resolve_type_with_bindings` 替代 `resolve_type`
3. **`bind_ancestor_trait_type_params_recursive`** - 在解析前设置 `resolution_scope`
4. **`collect_given_signatures`** - 总是创建包含泛型参数的 scope
5. **`IntrinsicFunctionDecl`** - 在 `resolve_type` 前设置 `resolution_scope`
6. **`resolve_template_type_node_with_bindings`** - 添加 `resolution_scope` 检查
7. **`name_collector`** - 内在类型注册为专用枚举类型

## 剩余问题（314个失败）

### 298 个崩溃测试（unexpected_nonzero_exit）
编译器在 `build` 阶段因 segfault 崩溃。**重要**: 这些测试在 `check` 阶段大部分能通过，segfault 发生在代码生成阶段（MIR/C backend），而非类型检查。

**可能原因**:
1. MIR C backend 栈帧压力（memory 中记录的 Root cause 2）
2. trait conformance 检查的深层递归导致栈溢出

### 6 个基础设施错误（infrastructure_error）
测试基础设施问题，需要逐个调查。

### 10 个缺少期望错误（missing_expected_error）
编译器未产生期望的错误消息，需要逐个调查：
- `checked_div_min.koral` - 缺少 "Panic: integer overflow in division"
- `if_is_single_branch_type_error.koral` - 缺少期望错误
- `cast_float_overflow_panic.koral` - 缺少期望错误
- `checked_div_zero.koral` - 缺少期望错误
- `random_zero_seed_panic.koral` - 缺少期望错误
- `checked_overflow_add.koral` - 缺少期望错误
- `random_empty_range_panic.koral` - 缺少期望错误
- `checked_overflow_mul.koral` - 缺少期望错误
- `checked_shift_invalid.koral` - 缺少期望错误
- `checked_overflow_sub.koral` - 缺少期望错误

### 泛型推断问题
- `list_sort_test.koral` - "Undefined type: K"：`sort_by[K Ord]` 的泛型参数 K 无法从 lambda `(x) -> x` 推断
- 需要改进泛型函数调用的类型推断逻辑

## 待修复的其他问题

### 298 个崩溃测试
大部分崩溃是由于 std 库错误导致的级联失败。修复上述 4 个 foreign 函数错误后，预计会通过更多测试。

### 19 个缺少期望错误
这些测试期望编译器产生特定错误消息，但 bootstrap 编译器产生了不同的错误或没有错误。需要逐个调查。

## 关键文件

| 文件 | 作用 |
|------|------|
| `bootstrap/koralc/sema/type_checker.koral` | 主类型检查器，pass 2/3 处理 |
| `bootstrap/koralc/sema/type_checker_members.koral` | 成员类型解析，given 块处理 |
| `bootstrap/koralc/sema/type_checker_methods.koral` | 方法解析，模板实例化 |
| `bootstrap/koralc/sema/type_checker_templates.koral` | 模板管理，扩展方法注册 |
| `bootstrap/koralc/sema/type_checker_resolution.koral` | 类型解析核心 |
| `bootstrap/koralc/sema/type_checker_visibility.koral` | trait 一致性检查 |
| `bootstrap/koralc/sema/type_checker_decls.koral` | 声明处理 |
| `bootstrap/koralc/sema/type_checker_expressions.koral` | 表达式类型检查 |
| `bootstrap/koralc/sema/name_collector.koral` | Pass 1 名称收集 |
| `bootstrap/koralc/sema/compiler_context.koral` | 编译器上下文，符号表 |

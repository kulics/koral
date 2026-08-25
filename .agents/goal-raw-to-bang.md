# Goal: raw关键字改感叹号 (!) — 已完成

## 概述

将 Koral 语言中 raw pointer 相关的 `raw` 关键字语法替换为 `!` (感叹号) 语法。

### 语法变更对照

| 旧语法                | 新语法           | 含义               |
|-----------------------|------------------|--------------------|
| `*raw T`              | `*! T`           | raw pointer 类型   |
| `*raw mut T`          | `*! mut T`       | mutable raw pointer 类型 |
| `&raw expr`           | `&! expr`        | raw address-of     |
| `&raw mut expr`       | `&! mut expr`    | mutable raw address-of |

## 已完成的修改

### 编译器 (Swift, 11个文件)

- **Lexer.swift** — `rawKeyword` token 枚举改为 `bang`; `!` 字符不再抛出 lexer error, 改为返回 `.bang`; 关键字表中移除 `"raw"` 映射
- **AST.swift** — `TypeNode.description` 中 pointer case 输出改为 `*!` / `*! mut`
- **ParserExpressions.swift** — 解析 address-of 时改为匹配 `.bang`
- **ParserTypes.swift** — 解析 pointer type 时改为匹配 `.bang`
- **CompilerContext.swift** — `getDebugName` 输出改为 `*!`
- **SemanticError.swift** — 错误信息更新
- **Type.swift** — Type 枚举描述更新
- **TypeCheckerExpressions.swift** — 表达式类型检查更新
- **TypeCheckerMethods.swift** — 方法类型检查更新
- **TypeCheckerPasses.swift** — 类型检查 pass 更新
- **TypeCheckerStatements.swift** — 语句类型检查更新

### Bootstrap 编译器 (Koral, 12个文件)

- **token.koral** — `KwRaw()` 枚举改为 `Bang()`
- **scanner.koral** — 移除 `"raw"` 关键字映射; 新增 `!` 字符扫描
- **core.koral** — `parse_type` 中 `.KwRaw()` 改为 `.Bang()`
- **core_expressions.koral** — `parse_unary` 中 `.KwRaw()` 改为 `.Bang()`
- **core_precedence.koral** — `token_text` 显示改为 `"!"`
- **compiler_context.koral** — 调试名输出改为 `*!`
- **types.koral** / **unifier.koral** / **typed_printer.koral** — 类型显示更新
- **type_checker.koral** / **type_checker_decls.koral** / **type_checker_expressions.koral** / **type_checker_expressions_dispatch.koral** / **type_checker_expressions_lowering.koral** / **type_checker_expressions_static_calls.koral** / **type_checker_statements.koral** — 错误信息更新
- **codegen_buffer.koral** — 自身类型定义 `*raw mut` 改为 `*! mut`

### 标准库 (36个 .koral 文件)

所有 `std/` 下的 `.koral` 文件已批量迁移：`*raw` -> `*!`, `*raw mut` -> `*! mut`, `&raw` -> `&!`, `&raw mut` -> `&! mut`

### 测试用例 (54个 .koral 文件)

所有 `tests/compiler-cases/` 下的 `.koral` 文件已批量迁移，包括源码和 EXPECT-ERROR 期望错误信息。

### 格式化工具 (Koral, 5个文件)

- **tokenizer.koral** — `KwRaw` -> `Bang`, 扫描逻辑简化为 `*!`
- **parser.koral** — 解析规则更新
- **test_fmt.koral** — 测试用例更新
- **test/cases/valid_modern_refs.koral** + **.expected** — 测试更新

### 文档 (4个 .md 文件)

- **developer-guide.md**, **document.md**, **document-zh.md**, **std.md** — 代码示例中的 `raw` 语法已更新

## 验证结果

### Swift 编译器
- **swift build**: 编译通过
- **类型检查**: 374/508 测试用例通过 (191个是预期失败的错误测试用例)
- **错误信息匹配**: 所有 EXPECT-ERROR 测试用例的期望错误信息与实际输出一致
- **意外失败**: 5个, 均为预存问题, 与 raw->! 迁移无关

### Bootstrap 编译器
- **类型检查**: `koralc check` 通过
- **构建**: `koralc build` 成功生成新 `koralc.exe`
- **测试**: hello, raw_sigils_basic_test, pointer_test, cast_pointer_int_uint, ffi_opaque_ptr_required, raw_address_of_literal_error, raw_address_of_temporary_error, drop_wrong_param_count_error, ffi_pointer_member_error — 全部 PASS

## 注意事项

1. `raw` 在英文注释/文档中作为普通单词使用（如 "raw bytes", "raw buffer"）的保留不动
2. 文档中 "raw pointer" / "raw 指针" 作为概念描述保留不动
3. 测试文件名含 `raw_` 前缀的保留不动（如 `raw_sigils_basic_test.koral`）
4. Bootstrap 编译器已重新构建，支持 `!` 语法
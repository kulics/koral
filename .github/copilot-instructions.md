# Koral 的 Copilot 指南（给 AI 编码代理）

## 仓库结构（先理解大图）
- Swift 编译器工程在 `compiler/`（SwiftPM）。会产出：
  - 可执行文件 `koralc`（入口：`compiler/Sources/koralc/main.swift`）
  - 库 `KoralCompiler`（核心实现）
- 编译流水线由 `compiler/Sources/KoralCompiler/Driver/Driver.swift` 的 `Driver` 串起：
  1) 读取 stdlib：`compiler/Sources/std/std.koral`（入口文件，内部用 `using` 合并标准库，走 `ModuleResolver`）
  2) 模块解析：`ModuleResolver` 统一处理单文件/多文件与 `using` 依赖，收集节点与来源信息
  3) 语义分析：`TypeChecker`（合并 std/user 的 `ImportGraph`）→ `Monomorphizer`（泛型专门化）
  4) 代码生成：`CodeGen.generate()` 生成 C，并根据 `foreign using` 的库名追加 `-l<name>`，调用 `clang` 编译
  5) 诊断输出：`SourceManager` 负责错误片段渲染（std 源文件会以 `std/<file>` 的展示名注册）

## 主要改动入口（按模块改，不要堆在 Driver）
- 解析（词法/语法/AST）：`compiler/Sources/KoralCompiler/Parser/`（`Lexer.swift`, `Parser.swift`, `AST.swift`）
- 模块系统：`compiler/Sources/KoralCompiler/Module/`（`ModuleResolver.swift` 等）
- 语义与类型系统：`compiler/Sources/KoralCompiler/Sema/`（`TypeChecker.swift`, `Type.swift`, `SemanticError.swift` 等）
- 泛型单态化：`compiler/Sources/KoralCompiler/Monomorphization/Monomorphizer.swift`
- 诊断与错误渲染：`compiler/Sources/KoralCompiler/Diagnostics/`
- C 后端：`compiler/Sources/KoralCompiler/CodeGen/CodeGen.swift`
- 标准库：`compiler/Sources/std/std.koral`（入口文件，默认每次编译都会被加载并拼接到用户 AST 前面）

## 模块系统注意事项（实现约束）
- 模块入口文件名必须是合法模块名：小写字母开头，只能包含小写字母/数字/下划线；否则会报 `invalidEntryFileName`。
- 外部模块解析顺序：先标准库路径，再 `externalPaths`；找不到会抛 `externalModuleNotFound`。

## CLI 用法（当前实现）
- `koralc <file.koral> [options]`：默认 `build`
- `koralc [command] <file.koral> [options]`，支持命令：`build`、`run`、`emit-c`
- 选项：
  - `-o` / `--output <dir>`：输出目录（否则默认在输入文件所在目录）
  - `--no-std`：不加载 `std.koral`（做隔离/最小化复现很有用）
  - `--escape-analysis-report`：打印逃逸分析诊断
  - `build` 成功会输出 `Build successful: <path>`，并在输出目录生成 `.c` 与可执行文件
  - `emit-c` 只生成 `.c` 不编译；`run` 会编译并运行

## 开发者工作流（最常用命令）
在 `compiler/`（Swift package 根目录）下运行：
- 编译：`swift build -c debug`
- 编译一个 `.koral`（默认 build）：`swift run koralc path/to/file.koral`
- 编译并运行：`swift run koralc run path/to/file.koral`
- 只生成 C（调试 CodeGen）：`swift run koralc emit-c path/to/file.koral -o outDir`

## 外部依赖（很关键）
- `koralc` 会直接调用 `clang`（见 `Driver.process(...)`）。必须确保 `clang` 在 `PATH` 上能被找到。
- Windows：`Driver` 会在 `PATH/Path/path` 里找 `clang.exe`（也会尝试 `.cmd/.bat`）。安装 LLVM 或其他提供 `clang.exe` 的工具链后，确认终端里运行 `clang --version` 可用。

## stdlib 定位与环境变量（容易踩坑）
- `Driver.getCoreLibPath()` 的查找顺序：
  1) `KORAL_HOME`：期望 `$KORAL_HOME/compiler/Sources/std/std.koral`
  2) 当前工作目录下的 `Sources/std/std.koral`（SwiftPM 构建目录）
  3) 当前工作目录下的 `compiler/Sources/std/std.koral`（仓库根目录运行测试）
- `Driver.getStdLibPath()` 也用于模块解析的标准库根目录定位（同样的查找顺序，但目录为 `.../std/`）。
- 如果你在非预期目录运行 `koralc` 导致找不到 stdlib，直接把 `KORAL_HOME` 设为仓库根目录最稳。

## 测试（本仓库的真实运行方式）
- 集成测试在 `compiler/Tests/koralcTests/IntegrationTests.swift`：遍历 `compiler/Tests/Cases/*.koral`。
- 用例通过注释断言输出（子串匹配、按顺序向前扫描）：
  - `// EXPECT: <substring>`：期望标准输出包含该子串
  - `// EXPECT-ERROR: <substring>`：期望非零退出码 + 输出包含该子串
- 测试不会 `swift run`，而是直接执行已构建的 `.build/debug/koralc(.exe)`，所以跑测试前先：
  - `swift build -c debug`
  - `swift test`
- 调试产物：设置 `KORAL_TEST_KEEP_C=1` 会把每个用例的生成物留在 `Tests/CasesOutput/<caseName>/`（默认会清理临时目录）。

## 改行为时的注意点（与用例耦合）
- 用例断言的是输出子串：尽量保持现有报错/打印文案稳定，否则会引发大量测试改动。
- 新语法/类型规则优先落在对应阶段（Parser vs Module vs Sema vs CodeGen），不要把规则“硬塞”进 `Driver`。

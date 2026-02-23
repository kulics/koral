# Koral Copilot Guide (for AI Coding Agents)

## Repository Structure (Understand the Big Picture First)
- The Swift compiler project is in `compiler/` (SwiftPM). It produces:
  - Executable `koralc` (entry: `compiler/Sources/koralc/main.swift`)
  - Library `KoralCompiler` (core implementation)
- The compilation pipeline is orchestrated by `Driver` in `compiler/Sources/KoralCompiler/Driver/Driver.swift`:
  1) Load stdlib: `std/std.koral` (preloaded by `Driver`, then resolved by `ModuleResolver`)
  2) Module resolution: `ModuleResolver` handles single-file/multi-file modules and `using`, collecting AST nodes and source metadata
  3) Semantic analysis: `TypeChecker` (merges std/user `ImportGraph`) → `Monomorphizer` (generic specialization)
  4) Code generation: `CodeGen.generate()` emits C; appends `-l<name>` for `foreign using`; passes `std/koral_runtime.c` to `clang` if present
  5) Diagnostics: `SourceManager` renders source snippets (stdlib sources are registered with display names like `std/<file>`)

## Primary Change Points (Modify by Module, Not in Driver)
- Parsing (lexer/parser/AST): `compiler/Sources/KoralCompiler/Parser/` (`Lexer.swift`, `Parser.swift`, `AST.swift`)
- Module system: `compiler/Sources/KoralCompiler/Module/` (`ModuleResolver.swift`, etc.)
- Semantics and type system: `compiler/Sources/KoralCompiler/Sema/` (`TypeChecker.swift`, `Type.swift`, `SemanticError.swift`, etc.)
- Monomorphization: `compiler/Sources/KoralCompiler/Monomorphization/Monomorphizer.swift`
- Diagnostics and error rendering: `compiler/Sources/KoralCompiler/Diagnostics/`
- C backend: `compiler/Sources/KoralCompiler/CodeGen/CodeGen.swift`
- Standard library: `std/std.koral` (entry file loaded by default before user AST)

## Module System Notes (Implementation Constraints)
- Module entry file names must be valid module names: start with a lowercase letter, followed only by lowercase letters, digits, or `_`; otherwise `invalidEntryFileName` is reported.
- External module lookup order: stdlib path first, then `externalPaths`; if unresolved, throws `externalModuleNotFound`.
- `using std...` does not trigger filesystem loading of external modules (stdlib is already preloaded by `Driver`); it is mainly for visibility/import graph construction.

## CLI Usage (Current Behavior)
- `koralc <file.koral> [options]`: defaults to `build`
- `koralc [command] <file.koral> [options]`, supported commands: `build`, `run`, `emit-c`
- If command is omitted, the first argument must end with `.koral`; otherwise usage is rejected.
- Options:
  - `-o` / `--output <dir>`: output directory (defaults to input file directory)
  - `--no-std`: do not load `std.koral` (useful for isolation/minimal reproductions)
  - `--escape-analysis-report`: print escape analysis diagnostics
  - On successful `build`, outputs `Build successful: <path>` and writes executable to output directory (temporary `.c` is cleaned up)
  - `emit-c` writes `<basename>.c` to output directory and returns
  - `run` compiles and executes (temporary `.c` is cleaned up)

## Developer Workflow (Most Common Commands)
Run these under `compiler/` (Swift package root):
- Build: `swift build -c debug`
- Compile one `.koral` (default `build`): `swift run koralc path/to/file.koral`
- Compile and run: `swift run koralc run path/to/file.koral`
- Emit C only (CodeGen debugging): `swift run koralc emit-c path/to/file.koral -o outDir`

## External Dependency (Important)
- `koralc` directly invokes `clang` (see `Driver.process(...)`). Ensure `clang` is discoverable in `PATH`.
- On Windows, `Driver` searches `PATH/Path/path` and tries suffixes `.exe/.cmd/.bat`. After installing LLVM or another toolchain providing `clang.exe`, verify with `clang --version` in terminal.
- On Windows, `bcrypt` is auto-linked by the driver when needed by runtime (`-lbcrypt`) even without explicit `foreign using`.

## stdlib Location and Environment Variables (Common Pitfall)
- `Driver.getCoreLibPath()` lookup order:
  1) `KORAL_HOME`: expects `$KORAL_HOME/std/std.koral`
  2) `std/std.koral` under current working directory
  3) `std/std.koral` under parent directory
  4) `std/std.koral` under grandparent directory
- `Driver.getStdLibPath()` uses the same order for locating the stdlib root directory (`.../std/`).
- If `koralc` cannot find stdlib due to working directory differences, set `KORAL_HOME` to repository root.

## Testing (How It Really Runs in This Repo)
- Integration tests are in `compiler/Tests/koralcTests/IntegrationTests.swift`, which explicitly calls `runCase(...)` methods over cases in `compiler/Tests/Cases/` (including subdirectory entry cases).
- Case assertions are comment-based output checks (substring matching with forward scan):
  - `// EXPECT: <substring>`: stdout must contain this substring
  - `// EXPECT-ERROR: <substring>`: exit code must be non-zero and output must contain this substring
- Tests do not run `swift run`; they directly execute built binary `.build/debug/koralc(.exe)`, so run before testing:
  - `swift build -c debug`
  - `swift test`
- Debug artifacts: tests use temporary directories under `Tests/CasesOutput/<caseName>/<uuid>/` and clean them by default.
- Test harness captures stdout/stderr through temporary files (not pipes) to avoid buffer deadlocks on large outputs.

## Behavior Change Notes (Coupled with Test Cases)
- Tests assert output substrings. Keep existing diagnostics/log wording stable whenever possible to avoid broad test churn.
- Put new syntax/type rules in the correct stage (Parser vs Module vs Sema vs CodeGen), and do not force them into `Driver`.

# Koral Copilot Guide (for AI Coding Agents)

## Repository Structure (Read First)
- Compiler project: `compiler/` (SwiftPM)
  - Executable: `koralc` (`compiler/Sources/koralc/main.swift`)
  - Library: `KoralCompiler`
- Self-hosting compiler: `bootstrap/koralc/`
  - Entry: `bootstrap/koralc/main.koral`
  - Driver entry: `bootstrap/koralc/driver/run.koral`
- Formatter: `toolchain/fmt/`
- Stdlib and runtime: `std/` (`std/std.koral`, `std/koral_runtime.c`, `std/koral_runtime.h`)
- Pipeline owner: `Driver` (`compiler/Sources/KoralCompiler/Driver/Driver.swift`)
  1) Preload stdlib entry `std/std.koral` (unless `--no-std`)
  2) Module resolution (`ModuleResolver`)
  3) Semantic passes (`TypeChecker`) + monomorphization (`Monomorphizer`)
  4) C generation (`CodeGen.generate()`) + clang link
  5) Diagnostics with source snippets (`SourceManager`)
- Bootstrap pipeline follows the same broad stages under `bootstrap/koralc/{module,parser,sema,mono,codegen}/`.

## Where to Change Code
- Swift parser/AST: `compiler/Sources/KoralCompiler/Parser/`
- Swift module system: `compiler/Sources/KoralCompiler/Module/`
- Swift semantics/types: `compiler/Sources/KoralCompiler/Sema/`
- Swift monomorphization: `compiler/Sources/KoralCompiler/Monomorphization/`
- Swift diagnostics: `compiler/Sources/KoralCompiler/Diagnostics/`
- Swift C backend: `compiler/Sources/KoralCompiler/CodeGen/`
- Bootstrap parser/AST: `bootstrap/koralc/{parser,ast}/`
- Bootstrap module system: `bootstrap/koralc/module/`
- Bootstrap semantics/types: `bootstrap/koralc/{sema,typed}/`
- Bootstrap monomorphization: `bootstrap/koralc/mono/`
- Bootstrap diagnostics: `bootstrap/koralc/diagnostics/`
- Bootstrap C backend: `bootstrap/koralc/codegen/`
- Formatter: `toolchain/fmt/`
- Stdlib: `std/` (`std/std.koral` is the default entry)

## Module System Notes (Implementation Constraints)
- Module entry file names must be valid module names: start with a lowercase letter, followed only by lowercase letters, digits, or `_`; otherwise `invalidEntryFileName` is reported.
- External module lookup order: stdlib path first, then `externalPaths`; if unresolved, throws `externalModuleNotFound`.
- File-based using (`using "file"`) resolves relative to the current file's directory, not the module root.
- `using "file"` merges the file into the current module; it does not create a namespace or submodule.
- Cross-module imports must use explicit module syntax: `using std::io { Reader }`, `using std::io { Reader as IoReader }`, or `using std::io { .. }`.
- `..` must be the only item inside a module import list.
- Imported symbols are file-local bindings and are never re-exported automatically.
- Module identity comes from `koral.json` / `std/koral.json`; do not reintroduce removed source forms such as `using "file" as Name`, `using Super...`, `using Std.Io`, `using Std.Io as Io`, `using Std.Io.*`, `public using ...`, or `foreign using`.

## Language Notes That Commonly Drift
- String literals use double quotes (`"..."`); rune literals use single quotes (`'x'`).
- Type aliases must start with an uppercase letter.
- Do not trust `docs/grammar_preview.koral` as an exact grammar reference. It is illustrative and currently leads the parser in a few areas; confirm grammar-sensitive changes against `docs/grammar.bnf`, parser code, and tests.

## CLI Behavior (Swift Driver)
- Shape:
  - `koralc <file.koral> [options]` (default command: `build`)
  - `koralc [build|check|run|emit-c] <file.koral> [options]`
  - `koralc [build|check|run|emit-c] --package-config <koral.json> --target-module <module> [options]`
- If command is omitted, the first arg must either be a `.koral` file or an option such as `--package-config`.
- Options:
  - `-o`, `--output <dir>`
  - `--package-config <path>`
  - `--target-module <name>`
  - `--deps-root <path>`
  - `--std-config <path>`
  - `--no-std`
  - `-m` / `-m=<N>`: print escape-analysis diagnostics
- Output:
  - `check`: type-check only (no monomorphization/codegen/clang)
  - `build`: executable + `Build successful: <path>`
  - `run`: compile then execute
  - `emit-c`: write `<basename>.c` and return
  - `build` / `run` use a temporary `.c` file that is cleaned up automatically.

## CLI Behavior (Bootstrap Driver)
- Entry executable is produced from `bootstrap/koralc/main.koral`.
- Commands supported by `bootstrap/koralc/driver/run.koral`:
  - `bootstrap-koralc --emit-ast <file.koral>`
  - `bootstrap-koralc --emit-typed-ast <file.koral>|--package-config <koral.json> [options]`
  - `bootstrap-koralc --resolve-module <file.koral>|--package-config <koral.json> [options]`
  - `bootstrap-koralc --emit-c <file.koral>|--package-config <koral.json> [-o <dir>] [options]`
  - `bootstrap-koralc check <file.koral>|--package-config <koral.json> [options]`
  - `bootstrap-koralc build <file.koral>|--package-config <koral.json> [-o <dir>] [options]`
- Bootstrap driver supports `--package-config`, `--target-module`, `--deps-root`, and `--std-config`, but still does not mirror Swift driver's `run` command or `-m` escape-analysis flag.
- Set `KORAL_DEBUG_PHASE=1` to print phase markers during bootstrap debugging.

## Toolchain and Runtime
- `koralc` invokes `clang` directly; ensure it is in `PATH`.
- Bootstrap `build` also invokes `clang` directly.
- If present, `std/koral_runtime.c` is passed to clang.
- Native link inputs come from resolved manifest `links` on package/module configs.
- Windows: drivers auto-add `-lbcrypt` and `-lws2_32` when needed.

## Stdlib Resolution
Lookup order for stdlib root / `std/std.koral`:
1. `KORAL_HOME`
2. `./std/`
3. `../std/`
4. `../../std/`

If not found from current working directory, set `KORAL_HOME` to repo root. Swift driver expects both `std/std.koral` and `std/koral.json`; bootstrap probes can use `--no-std` when isolating frontend issues.

## Testing in This Repo
Run under `compiler/`:
1. `swift build -c debug`
2. `cd ..`
3. `compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner`
4. `./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8`

Notes:
- The supported shared runner package is `tests/compiler-runner/koral.json` targeting module `compiler_runner`.
- Cases: `tests/compiler-cases/`
- Expectations from comments:
  - `// EXPECT: ...`
  - `// EXPECT-EXACT: ...`
  - `// EXPECT-ERROR: ...`
  - `// EXIT: ...`
- The shared runner supports parallelism via `-j <N>` / `-j=<N>`.
- Tests execute built binaries, not `swift run`.
- Temp outputs: `tests/compiler-cases_output/<case>/<uuid>/` (auto-cleaned)

## Bootstrap Debugging
- Shared integration cases live under `tests/compiler-cases/`; no separate bootstrap test entry remains.
- Build trust boundary: use the Swift-hosted `bin/koralc.exe` (or `compiler/.build/.../koralc`) to build `bootstrap/koral.json` target `koralc` and `tests/compiler-runner/koral.json` target `compiler_runner` during normal bootstrap testing and debugging.
- Do not switch normal bootstrap test execution over to a bootstrap-built bootstrap compiler or bootstrap-built runner unless the task is explicitly self-hosting validation; next-stage bootstrap artifacts are not assumed stable enough to be the default harness.
- When debugging bootstrap frontend failures, prefer `--emit-typed-ast` before full `build`; it isolates module resolution / sema progress from later clang or link failures.
- For self-hosting regressions, compare Swift-side implementation and bootstrap counterpart rather than patching only one compiler unless the task is explicitly bootstrap-only.

## Diagnostics and Stability
- Prefer stable error wording (tests assert output substrings).
- Prefer adding syntax/type rules in the correct module (Parser/Module/Sema/CodeGen), not in `Driver`.
- CLI error rendering goes through `DiagnosticError` + renderer when wrapped.

## Koral Coding Rule
- When writing or modifying Koral code, always consult the relevant language and project documentation first (for example `docs/document.md`, `docs/grammar.bnf`, parser code/tests, and `docs/std/`). Use `docs/grammar_preview.koral` only as an illustrative sketch, not as an authority.
- Ensure the resulting code follows current Koral language rules, module conventions, and repository best practices.
- If docs and code behavior appear to conflict, treat the compiler/tested behavior as source of truth and align documentation updates in the same change when appropriate.
- For grammar-sensitive work, prefer `docs/grammar.bnf`, parser implementation, and compiler tests over `docs/grammar_preview.koral` examples.

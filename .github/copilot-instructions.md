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
- `using "file"` (no alias) merges the file into the current module (shared `protected` scope).
- `using "file" as Name` (with alias) declares a named submodule.
- Explicit member imports are parser-normalized now: `using Std.Io.Reader` and `using Super.Mod.Symbol` set `importedSymbol` explicitly instead of relying on resolver inference.
- `using path as alias` enforces first-segment case matching: uppercase targets require uppercase aliases, lowercase targets require lowercase aliases.
- `Self` is no longer valid in `using` declarations; use string syntax instead.

## Language Notes That Commonly Drift
- String literals use double quotes (`"..."`); rune literals use single quotes (`'x'`).
- Type aliases must start with an uppercase letter.
- Do not trust `docs/grammar_preview.koral` as an exact grammar reference. It is illustrative and currently leads the parser in a few areas; confirm grammar-sensitive changes against `docs/grammar.bnf`, parser code, and tests.

## CLI Behavior (Swift Driver)
- Shape:
  - `koralc <file.koral> [options]` (default command: `build`)
  - `koralc [build|run|emit-c] <file.koral> [options]`
- If command omitted, first arg must end with `.koral`.
- Options:
  - `-o`, `--output <dir>`
  - `--no-std`
  - `-m` / `-m=<N>`: print escape-analysis diagnostics
- Output:
  - `build`: executable + `Build successful: <path>`
  - `run`: compile then execute
  - `emit-c`: write `<basename>.c` and return
  - Non-`emit-c` modes use a temporary `.c` file that is cleaned up automatically.

## CLI Behavior (Bootstrap Driver)
- Entry executable is produced from `bootstrap/koralc/main.koral`.
- Commands supported by `bootstrap/koralc/driver/run.koral`:
  - `bootstrap-koralc --emit-ast <file.koral>`
  - `bootstrap-koralc --emit-typed-ast <file.koral> [--no-std]`
  - `bootstrap-koralc --resolve-module <file.koral>`
  - `bootstrap-koralc --emit-c <file.koral> [-o <dir>] [--no-std]`
  - `bootstrap-koralc build <file.koral> [-o <dir>] [--no-std]`
- Bootstrap driver does not currently mirror Swift driver's `run` command or `-m` escape-analysis flag.
- Set `KORAL_DEBUG_PHASE=1` to print phase markers during bootstrap debugging.

## Toolchain and Runtime
- `koralc` invokes `clang` directly; ensure it is in `PATH`.
- Bootstrap `build` also invokes `clang` directly.
- If present, `std/koral_runtime.c` is passed to clang.
- `foreign using "x"` appends `-lx`.
- Windows: drivers auto-add `-lbcrypt` and `-lws2_32` when needed.

## Stdlib Resolution
Lookup order for stdlib root / `std/std.koral`:
1. `KORAL_HOME`
2. `./std/`
3. `../std/`
4. `../../std/`

If not found from current working directory, set `KORAL_HOME` to repo root. Swift driver hard-fails when std cannot be found; bootstrap probes can use `--no-std` when isolating frontend issues.

## Testing in This Repo
Run under `compiler/`:
1. `swift build -c debug`
2. `swift test --disable-swift-testing --enable-xctest --parallel`

Notes:
- Integration tests: `compiler/Tests/koralcTests/IntegrationTests.swift`
- Cases: `compiler/Tests/Cases/`
- Expectations from comments:
  - `// EXPECT: ...`
  - `// EXPECT-ERROR: ...`
- Tests execute built binary (`.build/debug/koralc(.exe)`), not `swift run`.
- Temp outputs: `Tests/CasesOutput/<case>/<uuid>/` (auto-cleaned)
- On Windows Swift 6.2, plain `swift test` may print a misleading `0 tests in 0 suites` Swift Testing summary for this XCTest-based target; prefer the explicit XCTest flags above.

## Bootstrap Debugging
- Bootstrap smoke cases live under `bootstrap/test/cases/`.
- Build trust boundary: use the Swift-hosted `bin/koralc.exe` (or `compiler/.build/.../koralc`) to build both `bootstrap/koralc/main.koral` and `bootstrap/test/main.koral` during normal bootstrap testing and debugging.
- Do not switch normal bootstrap test execution over to a bootstrap-built bootstrap compiler or bootstrap-built runner unless the task is explicitly self-hosting validation; next-stage bootstrap artifacts are not assumed stable enough to be the default harness.
- When debugging bootstrap frontend failures, prefer `--emit-typed-ast` before full `build`; it isolates module resolution / sema progress from later clang or link failures.
- For self-hosting regressions, compare Swift-side implementation and bootstrap counterpart rather than patching only one compiler unless the task is explicitly bootstrap-only.

## Diagnostics and Stability
- Prefer stable error wording (tests assert output substrings).
- Prefer adding syntax/type rules in the correct module (Parser/Module/Sema/CodeGen), not in `Driver`.
- CLI error rendering goes through `DiagnosticError` + renderer when wrapped.

## Koral Coding Rule
- When writing or modifying Koral code, always consult the relevant language and project documentation first (for example `docs/document.md`, `docs/grammar.bnf`, `docs/grammar_preview.koral`, and `docs/std/`).
- Ensure the resulting code follows current Koral language rules, module conventions, and repository best practices.
- If docs and code behavior appear to conflict, treat the compiler/tested behavior as source of truth and align documentation updates in the same change when appropriate.
- For grammar-sensitive work, prefer `docs/grammar.bnf`, parser implementation, and compiler tests over `docs/grammar_preview.koral` examples.

# Koral Copilot Guide (for AI Coding Agents)

## Repository Structure (Read First)
- Compiler project: `compiler/` (SwiftPM)
  - Executable: `koralc` (`compiler/Sources/koralc/main.swift`)
  - Library: `KoralCompiler`
- Pipeline owner: `Driver` (`compiler/Sources/KoralCompiler/Driver/Driver.swift`)
  1) Preload stdlib entry `std/std.koral` (unless `--no-std`)
  2) Module resolution (`ModuleResolver`)
  3) Semantic passes (`TypeChecker`) + monomorphization (`Monomorphizer`)
  4) C generation (`CodeGen.generate()`) + clang link
  5) Diagnostics with source snippets (`SourceManager`)

## Where to Change Code
- Parser/AST: `compiler/Sources/KoralCompiler/Parser/`
- Module system: `compiler/Sources/KoralCompiler/Module/`
- Semantics/types: `compiler/Sources/KoralCompiler/Sema/`
- Monomorphization: `compiler/Sources/KoralCompiler/Monomorphization/`
- Diagnostics: `compiler/Sources/KoralCompiler/Diagnostics/`
- C backend: `compiler/Sources/KoralCompiler/CodeGen/`
- Stdlib: `std/` (`std/std.koral` is the default entry)

## Module System Notes (Implementation Constraints)
- Module entry file names must be valid module names: start with a lowercase letter, followed only by lowercase letters, digits, or `_`; otherwise `invalidEntryFileName` is reported.
- External module lookup order: stdlib path first, then `externalPaths`; if unresolved, throws `externalModuleNotFound`.
- `using std...` does not trigger filesystem loading of external modules (stdlib is already preloaded by `Driver`); it is mainly for visibility/import graph construction.

## CLI Behavior (Current)
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

## Toolchain and Runtime
- `koralc` invokes `clang` directly; ensure it is in `PATH`.
- If present, `std/koral_runtime.c` is passed to clang.
- `foreign using "x"` appends `-lx`.
- Windows: driver auto-adds `-lbcrypt` when needed.

## Stdlib Resolution
Lookup order for stdlib root / `std/std.koral`:
1. `KORAL_HOME`
2. `./std/`
3. `../std/`
4. `../../std/`

If not found from current working directory, set `KORAL_HOME` to repo root.

## Testing in This Repo
Run under `compiler/`:
1. `swift build -c debug`
2. `swift test --parallel`

Notes:
- Integration tests: `compiler/Tests/koralcTests/IntegrationTests.swift`
- Cases: `compiler/Tests/Cases/`
- Expectations from comments:
  - `// EXPECT: ...`
  - `// EXPECT-ERROR: ...`
- Tests execute built binary (`.build/debug/koralc(.exe)`), not `swift run`.
- Temp outputs: `Tests/CasesOutput/<case>/<uuid>/` (auto-cleaned)

## Diagnostics and Stability
- Prefer stable error wording (tests assert output substrings).
- Prefer adding syntax/type rules in the correct module (Parser/Module/Sema/CodeGen), not in `Driver`.
- CLI error rendering goes through `DiagnosticError` + renderer when wrapped.

## Koral Coding Rule
- When writing or modifying Koral code, always consult the relevant language and project documentation first (for example `docs/document.md`, `docs/grammar.bnf`, `docs/grammar_preview.koral`, and `docs/std/`).
- Ensure the resulting code follows current Koral language rules, module conventions, and repository best practices.
- If docs and code behavior appear to conflict, treat the compiler/tested behavior as source of truth and align documentation updates in the same change when appropriate.

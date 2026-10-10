# Koral Compiler Developer Guide

## Quick Start

### Repository Structure

At repository root:

- `compiler/` — **the primary compiler implementation** (`koralc`), written in Koral and self-hosting.
  This is what you develop.
- `compiler-reference/` — the **frozen** Swift compiler (`koralc`): reference oracle, bootstrap seed,
  and backup. Not a development target — see "Compiler roles" below.
- `std/` — standard library sources and runtime C files
- `tests/` — shared integration cases (`compiler-cases/`) and the shared Koral test runner (`compiler-runner/`)
- `toolchain/` — `koral` build tool, `koral-syntax` shared parser/printer package, `koralfmt` formatter, `doc` std API doc generator, VS Code extension
- `samples/` — sample programs
- `docs/` — documentation, split by audience into `guide/` (language reference + normative grammar),
  `api/` (generated std API), `design/` (design decisions), `implementation/` (this guide + records).
  Start at `docs/README.md`.

### Compiler roles

There are two compiler implementations and they are not equal.

- **`compiler/` is the implementation under development.** Every functional change lands here first.
  It is written in Koral and self-hosts; it builds to `bin/compiler/koralc`.
- **`compiler-reference/` is frozen.** It is kept as three things at once:
  1. the **reference oracle** — the differential gate compiles every case under both compilers and
     requires them to agree, so one-sided drift is caught even when both suites are green;
  2. the **build seed** — it is what builds `bin/compiler` (and the test runner) from source;
  3. a **backup** — if the self-hosting chain breaks, this is the compiler that still works.

Deleting it would trade the strongest cross-check in the repo for the weakest: a self-host fixed
point only proves a compiler is *stable under its own output*, not that it is *right*.

**Why the oracle is shaped this way** (operational contract: [`../../tests/README.md`](../../tests/README.md)):

- The two compilers must agree **in order of how damning the disagreement is**: accept/reject, then
  exact stdout and exit code, then verbatim diagnostic text. Layer 2 is *exact* rather than a
  subsequence match because two compilers can both satisfy "output contains X then Y" and still
  print entirely different things in between.
- **Generated artifacts are deliberately not compared.** The two compilers stamp `DefId`s into C
  symbol names under different numbering rules, so a textual diff of the generated C would be pure
  noise. Behaviour is the contract; the C text is not.

**When you may touch `compiler-reference/`:** only to keep the oracle honest — for example when the
primary implementation deliberately changes language behaviour and the frozen reference must follow
so the two can keep being compared. Ordinary language work does **not** go there. A change to
`compiler-reference/` is exceptional and should be reviewed as such.

> **Naming note.** The test runner's CLI predates these directory names and keeps them: the
> `--compiler bootstrap` kind and the `--bootstrap-koralc <path>` flag mean **the self-hosting
> compiler built from `compiler/`** (`bin/compiler/koralc`), and `--compiler swift` /
> `--swift-koralc` mean the frozen seed in `compiler-reference/`. The flag names describe the
> implementation language and are stable API; the directories above are the source of truth for
> where the code lives.

### Build the Compiler

`compiler/` is the implementation you build and use day to day. It cannot build itself from
nothing, so the **frozen seed** (`compiler-reference/`) builds it — that is the only reason the
seed is still on the critical path. Build the seed once (or after it changes), then build
bootstrap from it.

Both compilers have a **debug** and a **release** build mode. **Use release for running
tests and for any repeated compilation work**; drop to debug only when you need to step
through the compiler itself.

The frozen seed is built with SwiftPM's two configurations:

```bash
cd compiler-reference

# debug   — unoptimized, for debugging the compiler itself
swift build -c debug       # -> compiler-reference/.build/debug/koralc

# release — optimized, for running tests and compiling anything large
swift build -c release     # -> compiler-reference/.build/release/koralc
```

The debug binary is roughly **6x slower** at generating C for a large package and **3.7x
slower** end-to-end than the release one, so the choice is not cosmetic. Measured on
`compiler/koral.json`:

| seed build | `emit-c` | `build` (codegen + clang) |
|---|---|---|
| `swift build -c debug` | 264.6 s | 303.1 s |
| `swift build -c release` | 42.9 s | 81.9 s |

Binaries produced from generated C have their own mode, selected by `koralc` flags that
control the clang optimization level (`--debug` / `--release` / `--optimize <level>`,
default `-O1`):

```bash
koralc build app.koral -o out --debug     # clang -O0 -g  (unoptimized, debuggable)
koralc build app.koral -o out             # clang -O1     (default, unchanged behaviour)
koralc build app.koral -o out --release   # clang -O2     (optimized)
koralc build app.koral -o out --optimize 3
```

### Run Tests

The **primary gate** is the suite against `bin/compiler/koralc`. Build the seed and the compiler once, then run it:

```bash
cd compiler-reference && swift build -c release && cd ..
compiler-reference/.build/release/koralc build --package-config compiler/koral.json --target-module koralc -o bin/compiler
compiler-reference/.build/release/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc -j=8
```

To debug a failing case, rebuild the seed with `swift build -c debug` and point
`--swift-koralc` at `compiler-reference/.build/debug/koralc` instead. Add `--filter <name>` to
run a single case, and `--verbose` to see the exact compiler command line.

### Run Shared Test Runner

The shared integration test runner is implemented in Koral under `tests/compiler-runner/`.
It defaults to `--compiler bootstrap` — the implementation under development. `--compiler swift`
targets the frozen seed, `--compiler differential` runs both against each other, and
`--compiler custom` takes any binary via `--compiler-bin`.

Important trust boundary:

- **The oracle and the test harness are built by the frozen reference, never by the implementation under test.** Use the seed `koralc` to build both `bin/compiler/koralc` and the test runner executable. If the compiler under test built the harness, a codegen defect in it would corrupt the very thing meant to catch it.
- Run the seed-built runner against the seed-built `bin/compiler/koralc`.
- Do not rebuild the compiler with itself and then use that next-stage binary as the default test harness; that path is reserved for explicit self-hosting validation and is not assumed stable.

```bash
# 1) Build the frozen seed (only when it changed or is missing) — see "Build the Compiler"
cd compiler-reference
swift build -c release
cd ..

# 2) Build the compiler and the test runner WITH THE SEED (trust boundary above)
compiler-reference/.build/release/koralc build --package-config compiler/koral.json --target-module koralc -o bin/compiler
compiler-reference/.build/release/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner

# 3) PRIMARY GATE — the suite against bin/compiler/koralc
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc -j=8

# 4) Seed self-check + the differential oracle (when the seed or cross-compiler agreement is in scope)
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler-reference/.build/release/koralc -j=8
./bin/compiler-test-runner/compiler_runner --compiler differential --swift-koralc compiler-reference/.build/release/koralc --bootstrap-koralc bin/compiler/koralc -j=8
```

Common options:

- `--cases <dir>`: set test case root (default: `tests/compiler-cases`)
- `--compiler <kind>`: select `bootstrap`, `swift`, `custom`, or `differential` compiler mode (default: `bootstrap`)
- `--filter <substring>`: run only cases whose file name or relative path contains the substring
- `-j <N>` / `-j=<N>`: worker count for parallel case execution (default: `1`)
- `--timeout <sec>`: per-case timeout in seconds (default: `120`)
- `--memory-limit <MB>`: per-case RSS ceiling (default: `1024`)
- `--compiler-bin <path>`: explicit compiler executable path when `--compiler custom`
- `--bootstrap-koralc <path>`: explicit path of the self-hosting compiler (built from `compiler/`)
- `--swift-koralc <path>`: explicit Swift compiler executable path
- `--report-file <path>`: write stable summary log (default: `tests/compiler-cases_output/_reports/latest-summary.log`)
- `--verbose`: print per-case command lines
- `-h`, `--help`: print usage

Examples:

```bash
# Run only hello-related cases
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc --filter hello

# Seed self-check — the frozen reference compiler
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler-reference/.build/release/koralc -j=8

# Point to a custom compiler path
./bin/compiler-test-runner/compiler_runner --compiler custom --compiler-bin path/to/koralc -j=8
```

Current expectations syntax in case files:

- `// EXPECT: <substring>`: output line sequence must contain each substring in order
- `// EXPECT-EXACT: <line>`: normalized non-empty output must exactly match the listed lines
- `// EXPECT-ERROR: <substring>`: case must exit non-zero and contain each error substring in order
- `// EXIT: <code>`: require an explicit process exit code

Current runner exit codes:

- `0`: all matched cases passed
- `1`: one or more cases failed (assertion, timeout, or infra failure)
- `2`: CLI/configuration errors (e.g. invalid flags or missing compiler binary)

Case names with these prefixes are tagged for conflict grouping metadata:

- `sync_`
- `net_`
- `os_env_`

Windows notes:

- The default self-hosting compiler path is auto-selected as `bin/compiler/koralc.exe` when `OS` contains `Windows`.
- Output matching normalizes CRLF to LF before evaluating `EXPECT` comments.

### Compile Koral Programs

Use the primary implementation (`bin/compiler/koralc`) unless you are specifically exercising the
seed:

```bash
# Build a manifest target module
bin/compiler/koralc build --package-config path/to/koral.json --target-module app/main

# Type-check only
bin/compiler/koralc check --package-config path/to/koral.json --target-module app/main

# Build and run
bin/compiler/koralc run --package-config path/to/koral.json --target-module app/main

# Emit C only
bin/compiler/koralc emit-c --package-config path/to/koral.json --target-module app/main -o output/

# Disable stdlib preload
bin/compiler/koralc build --package-config path/to/koral.json --target-module app/main --no-std
```

The frozen seed is reached the same way, just with its own binary:

```bash
compiler-reference/.build/release/koralc build --package-config path/to/koral.json --target-module app/main
# or, once the seed is built:  cd compiler-reference && swift run koralc build ...
```

Which `koralc` does `koral build` pick? — the Koral build tool (`toolchain/koral`) resolves the
compiler through `find_koralc()`, and **the primary implementation wins**. Under `$KORAL_HOME` it looks for, in order:
`bin/compiler/koralc`, `bin/compiler-clone`, `bin/compiler-new`, `bin/koralc`, `$KORAL_HOME/koralc`,
then — only as a last resort — the seed at `compiler-reference/.build/release/koralc` (or its
Windows triple dir), and finally `compiler-reference/.build/debug/koralc`. Only if none of those
exist does it fall back to `PATH`. So a fresh clone resolves to the seed until you build
`bin/compiler/koralc`, and to the primary implementation from then on.

CLI shape in current implementation:

- `koralc [build|check|run|emit-c] --package-config <koral.json> [--target-module <module>] [options]`
- If no command is given, the first argument must be an option such as `--package-config`.
- Top-level manifest `entry` is the default target module name, not a source file path.

Output behavior:

- `check`: type-checks only; it does not run monomorphization, C generation, or clang
- `build`: writes executable and prints `Build successful: <path>`
- `run`: compiles and runs executable
- `emit-c`: writes `<basename>.c` to output directory and exits
- `build` and `run` use a temporary `.c` file that is cleaned up automatically

### Standard Library Resolution (`KORAL_HOME`)

`Driver.getCoreLibPath()` / `Driver.getStdLibPath()` search in this order:

1. `KORAL_HOME` (expects `$KORAL_HOME/std/std.koral` and `$KORAL_HOME/std/koral.json`)
2. `std/std.koral` / `std/koral.json` in current working directory
3. `std/std.koral` / `std/koral.json` in parent directory
4. `std/std.koral` / `std/koral.json` in grandparent directory

If you run `koralc` outside the repository root, set `KORAL_HOME` explicitly.

```bash
# macOS / Linux
export KORAL_HOME=/path/to/koral

# Windows PowerShell
$env:KORAL_HOME = "C:\path\to\koral"
```

Notes:

- If the driver cannot find std sources or `std/koral.json`, it prints an error and exits.
- `Driver.getStdLibPath()` is also used to add `std/` include path and `koral_runtime.c` to clang when available.

## Module System Rules That Commonly Drift

The module and import rules are the design's own; their canonical text is
[`../design/module-design.md`](../design/module-design.md) (命名 / 语法 / manifest) and the
normative grammar is [`../guide/grammar.bnf`](../guide/grammar.bnf). This guide does not restate them.

When checking for drift, what most often goes wrong:

- import spelling — has the superseded `using std::io { .. }` form crept back in? The grammar has
  no module-path form and no `..` import item.
- `using "file"` — is it being treated as a submodule declaration or an alias rather than a merge?
- module names — is anything inferring them from the directory tree instead of `koral.json`? 

## Language Rules That Commonly Drift

- String literals use double quotes (`"..."`); rune literals use single quotes (`'x'`).
- Type aliases must start with an uppercase letter.
- `[]` is builtin syntax only for `String`, `List`, `Deque`, `Dict`, `*unsafe`, and `*unsafe mutable`; custom traits do not define subscript behavior.
- `docs/guide/grammar_preview.koral` is illustrative only and may lead the parser. For grammar-sensitive work, treat `docs/guide/grammar.bnf`, parser code, and tests as authoritative.

The trait / trait-object / weak rules that used to live here are design rulings; their canonical text
is [`../design/traits-and-givens.md`](../design/traits-and-givens.md). What drifts, and what to check:

- trait identity — does any path compare only the base trait name, dropping the trait arguments?
- trait-object patterns — does anything treat them as exhaustive, or auto-deref them?
- trait objects — has an `Object` marker trait been reintroduced?
- weak capability — has it been turned into a marker trait instead of a constraint?

## Type Semantics and Drop Semantics

The declaration-site mutability model, the memory-model contract, `Clone` shallow-copy semantics and
the `Drop` contract live in [`../design/type-semantics.md`](../design/type-semantics.md). That is the
canonical text; this guide does not restate it.

## Bootstrap Self-Hosting Repair Notes

The current bootstrap compiler has been repaired back to a stable self-hosting chain. This section records the root causes that mattered, the Swift-architecture alignments that fixed them, and the validation flow that should be reused when similar regressions return.

### Root Causes That Actually Mattered

- Several bootstrap hot paths were relying on mutable local values that the current bootstrap compiler lowered as temporary boxed copies when passed through `&mutable`-style method calls. The symptom was not immediate type failure; it showed up later as use-after-free, malformed generated C, or corrupted codegen state.
- The most important instances were:
    - `CodeGen` lifecycle in `generate_c_from_mir`: separate phase calls were mutating different effective `CodeGen` objects instead of one stable instance.
    - `MIRFunctionCodeEmitter` nested-definition flow: body emission could mutate emitter-owned strings and then later read from a moved-from local emitter value.
    - `RecursiveTypeChecker.detect_cycles`: local `Dict` / `List` working state passed into DFS was lowered through transient boxed copies and then reused after release.
- Generic struct/enum instantiation in bootstrap mono resolved template type nodes, but did not consistently re-run nested parameterized type concretization the way Swift does. This showed up as wrong concrete type layers in generated C for cases such as `Option[List[*T]]`.
- Pattern variable lowering in bootstrap MIR builder was over-eagerly materializing copied locals for enum payload matches. For `Option[*T]` payloads this regressed ref-like semantics and produced value/ref mismatches.

### Swift Alignments That Fixed The Bugs

- Treat the codegen driver as operating on one stable mutable object. In bootstrap, `generate_c_from_mir` should keep a single boxed `CodeGen` and mutate that one instance through prelude, body emission, finalization, and string extraction.
- Avoid by-value `CodeGen` receivers on codegen hot paths. Swift effectively has reference semantics here; bootstrap needed the same practical behavior to stop copying internal state such as caches and output buffers.
- When bootstrap MIR/codegen needs mutable helper state that survives across multiple calls, prefer one stable boxed object over repeatedly passing stack locals through method calls.
- Align generic type instantiation with Swift's two-step approach:
    1. substitute template parameters
    2. immediately resolve nested parameterized types to concrete instantiated types
- Align MIR pattern-variable binding with Swift's place-based binding strategy. Do not always materialize a copied local for a variable pattern; preserve the matched place when the binding is semantically a reference-like payload.
- Align local-name lookup in MIR codegen with Swift's `localNameByID` model instead of assuming `MIRLocalID.raw_value == locals` array index everywhere.

### Bounded Self-Host Validation Flow

For late bootstrap failures, do not trust long shell chains that interleave generation, clang, and the next-stage run. Use isolated stages.

Recommended flow:

```bash
# 1) Build stage1 with the frozen seed
compiler-reference/.build/release/koralc build --package-config compiler/koral.json --target-module koralc -o bin/compiler

# 2) Generate stage2 C
./bin/compiler/koralc emit-c --package-config compiler/koral.json --target-module koralc -o bin/compiler-stage2

# 3) Compile stage2
clang bin/compiler-stage2/koralc.c std/koral_runtime.c -I std -o bin/compiler-stage2/koralc -Wno-everything -O1

# 4) Generate later stages one step at a time
./bin/compiler-stage2/koralc emit-c --package-config compiler/koral.json --target-module koralc -o bin/compiler-stage3
clang bin/compiler-stage3/koralc.c std/koral_runtime.c -I std -o bin/compiler-stage3/koralc -Wno-everything -O1
./bin/compiler-stage3/koralc emit-c --package-config compiler/koral.json --target-module koralc -o bin/compiler-stage4
```

What counts as "the chain works":

1. **Every stage compiles.** Each `koralc.c` must pass `clang` with zero errors,
   and link into a runnable binary. A stage that generates C which does not
   compile is a compiler bug, not a source problem — the same package compiles
   cleanly under the frozen seed.
2. **A fixed point is reached.** `bin/compiler-stage3/koralc.c` and
   `bin/compiler-stage4/koralc.c` must be byte-identical. Stage2 is generated by
   the seed-built compiler and is allowed to differ; stage3 onward must stop
   moving. If they differ, diff them — the delta shows which symbol names or
   layouts are not yet stable.
   ```bash
   cmp bin/compiler-stage3/koralc.c bin/compiler-stage4/koralc.c && echo "fixed point"
   ```
3. **The next-stage binary still works.** Run the shared suite against it:
   ```bash
   ./bin/compiler-test-runner/compiler_runner --compiler bootstrap      --bootstrap-koralc bin/compiler-stage2/koralc --timeout 60 -j 8
   ```
   Use it for validation only — see the note below about not promoting a
   next-stage binary to the default harness.
4. **No residual scratch state.** Delete `bin/compiler-stage*` once validated
   (see Cleanup Rules below); they are ~130 MB of C each.

Two invariants the generated C must hold; both have been violated in ways the
shared suite did not catch, so check them directly when stage2 stops compiling:

- **Every emitted symbol name comes from fully concrete types.** A name built
  while a type is still generic ends up containing the generic parameter markers
  (`Param_K`, `Param_V` from `CompilerContext.get_layout_key`) and is never
  defined, so C falls back to an implicit `int` declaration.

  A marker is `Param_` followed by a **bare type-parameter name**. Do not grep
  for `_Param_` alone: a type that is genuinely called `Param` (e.g. the
  compiler's own `Koralc.Param`) mangles to `List_Koralc_Param_d251`, which
  matches that pattern and is completely healthy. The reliable discriminator is
  the C symptom, not the spelling:
  ```bash
  # should print 0
  grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*\(\);' bin/compiler-stage2/koralc.c
  ```
  Any non-zero count is a dangling symbol, and that is the bug. It is a symptom,
  not a cause: it means an extension method was instantiated for a type whose
  constraints do not hold, so its body's call targets never resolved. Fix the
  constraint check, not the name builder.
- **A pattern test must not leak state into nested patterns.** `is` and `when`
  lower a pattern test with a cached subject tag/operand/comparison local; when
  recursing into enum payloads or struct fields that cache has to be cleared,
  otherwise the inner pattern compares the OUTER enum's tag against the INNER
  case index. Symptoms are subtle: wrong `when` arms, and codegen decisions like
  "is this value a bare function pointer?" answering wrong, which then skips the
  function-to-closure wrap and emits `f = some_fn;` where a
  `struct __koral_Closure` literal is required.

Operational rules:

- Keep per-case runner timeout enabled (`--timeout 120` is the current stable baseline).
- Wrap long self-host or suite runs in an outer memory / CPU cap. On this macOS setup, a CPU cap remains useful, but Python's `resource.setrlimit` for `RLIMIT_AS` / `RLIMIT_DATA` may reject updates even when the shell reports unlimited limits. If that happens, keep `--timeout` enabled, apply the CPU cap, and reduce runner parallelism instead of assuming address/data limits can always be enforced from Python.
- Prefer ASan over ad hoc logging once a failure is reproducible. In this repair, ASan was decisive for identifying UAFs in `CodeGen`, `MIRFunctionCodeEmitter`, and `RecursiveTypeChecker` working-state handling.

### Cleanup Rules After Bootstrap Debugging

- Remove temporary codegen probe logging after the failing boundary is identified. Keeping those probes in-tree can change ownership/lifetime lowering and create misleading secondary failures.
- Clean out stale stage directories under `bin/` once a repair is validated. Keep only actively useful entrypoints such as `bin/compiler/`, `bin/compiler-test-runner/`, and current user-facing tool outputs.
- If a bootstrap fix touches parser, MIR lowering, mono, or codegen, rerun both self-host validation and focused semantic buckets before trusting a full-suite green result.

### Named-Parameter Guardrail

Named-parameter behavior is an active compatibility surface and must not regress as a side effect of bootstrap repairs.

Do not keep positional-call workarounds in `std/` once named-parameter handling is repaired. Those edits can hide real regressions by making the standard library avoid the affected call paths.

High-signal cases to rerun when parser, sema call lowering, MIR lowering, or codegen call paths change:

- `named_params_basic`
- `named_params_struct`
- `named_params_trait`
- `named_params_generics`
- `named_params_pattern`
- `named_params_errors`
- `named_params_mismatch_error`
- `named_params_pattern_error`
- `named_params_unexpected_label_error`
- `named_params_foreign_error`
- `named_params_lambda_error`

Suggested focused rerun loop:

```bash
cases=(
    named_params_basic
    named_params_struct
    named_params_trait
    named_params_generics
    named_params_pattern
    named_params_errors
    named_params_mismatch_error
    named_params_pattern_error
    named_params_unexpected_label_error
    named_params_foreign_error
    named_params_lambda_error
)

for case_name in "${cases[@]}"; do
    ./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc --filter "$case_name" --timeout 120
done
```

## Standard Library Receiver Design

Receiver form, consumption semantics, naming contract and trait design guidance for `std`
APIs live in [`../design/std-api-design.md`](../design/std-api-design.md). That is the canonical
text; this guide does not restate it. Use its "Review Checklist" when adding or changing a
`std` API.

## Adding a New Type

### 1) Add a New `Type` Case

In `Type.swift`:

```swift
public indirect enum Type {
    // ... existing cases
    case myNewType(/* args */)
}
```

Also update:
- `description`
- `stableKey`
- `canonical`
- `Equatable` implementation

### 2) Add a `TypeHandlerKind`

```swift
public enum TypeHandlerKind: Hashable {
    // ... existing kinds
    case myNewType
}
```

Update mapping in `TypeHandlerKind.from(_ type: Type)`.

### 3) Implement a `TypeHandler`

```swift
public class MyNewTypeHandler: TypeHandler {
    public var supportedKinds: Set<TypeHandlerKind> {
        return [.myNewType]
    }

    public init() {}

    public func generateCTypeName(_ type: Type) -> String {
        return "my_new_type_t"
    }

    public func generateCopyCode(_ type: Type, source: String, dest: String) -> String {
        return "\(dest) = \(source);"
    }

    public func generateDropCode(_ type: Type, value: String) -> String {
        return ""
    }

    public func getQualifiedName(_ type: Type) -> String {
        return "MyNewType"
    }
}
```

### 4) Register in `TypeHandlerRegistry`

Inside `TypeHandlerRegistry.registerBuiltinHandlers()`:

```swift
handlers.append(MyNewTypeHandler())
```

### 5) Update `CompilerContext`

Add branches for the new type in:
- `getLayoutKey(_ type: Type)`
- `getDebugName(_ type: Type)`
- `containsGenericParameter(_ type: Type)`

## Adding a New Semantic Analysis Pass

### 1) Define Pass Output

In `PassInterfaces.swift`:

```swift
public struct MyPassOutput: PassOutput {
    public let previousOutput: TypeResolverOutput
    public let myData: MyDataType
}
```

### 2) Implement the Pass

```swift
public class MyPass: CompilerPass {
    typealias Input = TypeResolverInput
    typealias Output = MyPassOutput

    var name: String { "MyPass" }

    func run(input: Input) throws -> Output {
        return MyPassOutput(
            previousOutput: input.typeResolverOutput,
            myData: processedData
        )
    }
}
```

### 3) Integrate into `TypeChecker`

Call the new pass from `check()` in `TypeCheckerPasses.swift`.

## Adding Diagnostics

### Use `DiagnosticCollector`

```swift
diagnosticCollector.error(
    "Error message",
    at: sourceSpan,
    fileName: currentFileName,
    fixHint: "Suggested fix"
)

diagnosticCollector.warning(
    "Warning message",
    at: sourceSpan,
    fileName: currentFileName
)

diagnosticCollector.secondaryError(
    "Secondary error",
    at: sourceSpan,
    fileName: currentFileName,
    causedBy: "Primary error description"
)
```

### Add a New `SemanticError`

In `SemanticError.swift`:

```swift
public enum Kind: Sendable {
    // ... existing kinds
    case myNewError(String)
}

// Add in messageWithoutLocation
case .myNewError(let detail):
    return "My new error: \(detail)"
```

## Module System Development

### Add a New Import Kind

1. Extend `UsingDeclarationKind` only if the language actually gains a new source form.
2. Update `ParserDeclarations.swift` and `compiler/koralc/parser/core_precedence.koral`.
3. Update `recordImportToGraph()` and the bootstrap counterpart if the new form changes import visibility.
4. Keep module selection manifest-driven; do not reintroduce directory-inferred module trees
   (the ruling is in [`../design/name-resolution.md`](../design/name-resolution.md)).

### Module Resolution Flow

```text
resolveModule(entryFile:)
  └── resolveFile(file:module:unit:)
        ├── Lexer + Parser → AST
        ├── Extract using declarations
        │   └── resolveUsing(using:module:unit:currentFile:)
        │       ├── resolveFileMerge()    → merge another source file into the same module
        │       └── recordImportToGraph() → record explicit module imports
        └── Collect non-using top-level nodes
```

### Access Control Defaults

The default-access table is a design ruling; its canonical text is
[`../design/name-resolution.md`](../design/name-resolution.md). This guide does not restate it.

## Code Generation Development

### Generate C Code

```swift
let cName = context.getCIdentifier(defId) ?? "fallback"

let registry = TypeHandlerRegistry.shared
let cTypeName = registry.generateCTypeName(type)
let copyCode = registry.generateCopyCode(type, source: src, dest: dst)
let dropCode = registry.generateDropCode(type, value: val)
```

### C Identifier Utilities

Use helpers from `CIdentifierUtils.swift`:

```swift
escapeCKeyword("int")
sanitizeCIdentifier("my-func")
generateFileIdentifier("myfile.koral")

generateCIdentifier(
    modulePath: ["std", "io"],
    name: "print_line",
    isPrivate: false
)
```

### Handle Generic Instantiations

```swift
let key = context.getLayoutKey(.genericStruct(template: "List", args: [.int]))
let debug = context.getDebugName(.genericStruct(template: "List", args: [.int]))
```

## Test Development

### Add an Integration Test

1. Create a `.koral` case under `tests/compiler-cases/`:

```koral
// my_feature.koral
// EXPECT: test passed

using std { .. }

let main() Void = {
    println("test passed")
}
```

2. Nothing else. The shared runner **discovers cases by walking `tests/compiler-cases/`** — there is
   no registry to update. Rebuild nothing; rerun the runner.

For failure cases, add `// EXPECT-ERROR: ...`; the test harness expects a non-zero exit and matching error output substring.

How integration tests run (current behavior):

- The shared runner executes the compiler binary you point it at (`--bootstrap-koralc` /
  `--swift-koralc` / `--compiler-bin`), which defaults to `bin/compiler/koralc`.
- Build before running tests:

```bash
cd compiler-reference
swift build -c release
cd ..
compiler-reference/.build/release/koralc build --package-config compiler/koral.json --target-module koralc -o bin/compiler
compiler-reference/.build/release/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc -j=8
```

- Output assertions are comment-based and order-sensitive:
    - `// EXPECT: <substring>`
    - `// EXPECT-ERROR: <substring>`
- Each run uses an isolated output directory under `tests/compiler-cases_output/<caseName>/`.
- **Output is auto-cleaned at the start of each run**: everything under `tests/compiler-cases_output/` is removed except `_reports/`. So the directory only ever holds the most recent run's artifacts (for debugging a failure) and cannot accumulate — left unchecked it grew to 110 GB.

### Add Multi-file / Module Tests

```text
tests/compiler-cases/my_module_test/
├── koral.json              # explicit module table
├── my_module_test.koral    # root module entry
├── helper.koral            # merged file (using "helper")
└── child/
    └── child.koral         # separate module entry declared in manifest
```

```json
{
  "name": "MyModuleTest",
  "version": "0.1.0",
  "entry": "my_module_test",
  "modules": {
    "my_module_test": {
      "entry": "my_module_test.koral",
      "requires": ["my_module_test::child"],
      "links": []
    },
    "my_module_test::child": {
      "entry": "child/child.koral",
      "requires": [],
      "links": []
    }
  }
}
```

## Debugging Tips

### Print AST

```swift
let printer = ASTPrinter()
print(printer.print(ast))
```

### Print TypedAST

```swift
let printer = TypedASTPrinter()
print(printer.print(typedAST))
```

### Inspect `DefIdMap`

```swift
print(defIdMap.description)
```

### Render Diagnostics with Source

```swift
print(diagnosticError.renderForCLI())
```

### Inspect Generated C

```bash
swift run koralc emit-c --package-config path/to/koral.json --target-module app/main -o output/
```

## FAQ

### How are cyclic type references handled?

Design ruling — see [`../design/generics-and-monomorphization.md`](../design/generics-and-monomorphization.md).

### How are generic parameter scopes handled?

Design ruling — see [`../design/name-resolution.md`](../design/name-resolution.md).

### How is C identifier uniqueness guaranteed?

Design ruling — see [`../design/name-resolution.md`](../design/name-resolution.md).

### How do I add a new trait?

1. Define the trait in `std/traits.koral`
2. `TypeChecker` collects trait definitions in Pass 1
3. Pass 3 checks `given` declarations against trait requirements
4. `Monomorphizer` handles generic trait-constraint instantiation

### How do I add a new intrinsic function?

1. Add a new intrinsic case in `AST.swift`
2. Add type checking in `TypeCheckerExpressions.swift`
3. Add MIR lowering in `MIRLowerer.swift`
4. Add target C emission in `CodeGenMIR.swift` only if the intrinsic needs a backend-specific spelling or runtime helper
5. Declare it in stdlib with `intrinsic`

### How do I add a new foreign binding?

1. Declare external libraries in package or module `links` inside `koral.json`
2. Declare external functions with `let foreign`
3. Declare external types with `type foreign` (optional fields)
4. CodeGen emits C declarations; Driver appends linker flags from the resolved manifest graph

## Canonical sources and change workflow

### Change control principle

Every functional change must follow a documentation-first loop:

1. update the specification or workflow doc first,
2. update the implementation,
3. update or add tests/samples,
4. validate the affected toolchain in the documented order.

Code alone is not the source of truth. If the behavior changes, the docs must change first.

### Canonical source map

Use these files as the authoritative references:

- `docs/README.md` — the documentation map: which document goes where, and each category's conventions.
- `docs/implementation/developer-guide.md` (this file) — required change workflow, compiler roles and trust boundary, and validation checklist.
- `docs/design/` — **why the language and std are shaped the way they are.** Each design doc is the
  canonical text for its rulings; do not restate them here. Start at `docs/design/README.md`, which
  also carries the shared premise (identity is the declaration's `DefId`) and the de-duplication rule.
- `tests/README.md` — unified test runner contract, flags, buckets, and rerun guidance.
- `compiler/koral.json`, `tests/compiler-runner/koral.json`, `std/koral.json` — build/package targets for the compiler-side builds.
- `toolchain/koralfmt/test/README.md` — formatter gate: language assertions plus the corpus check, and how to run both.
- `toolchain/koral-syntax/README.md` — the formatter's contract (the reason its gate is a gate).
- `README.md` — top-level repo shape, prerequisites, quick start, and public contribution guidance.

### Required change workflow

1. **Document first**: update the governing doc in `docs/` (which one is decided by `docs/README.md`), or `tests/README.md` / toolchain docs when behavior, workflow, or validation steps change.
2. **Update implementation**: change compiler/runtime/toolchain code only after the doc baseline is updated.
3. **Update tests**: update existing expectations or add regression coverage before merge.
4. **Validate the build order**: rebuild the seed if it changed, rebuild the compiler with the seed, then run the shared runner against `bin/compiler/koralc` (primary) and the seed self-check.
5. **Validate samples**: build representative samples after compiler/runtime changes.
6. **Validate toolchain**: run formatter and/or doc-generator validation when formatting rules, std surface, or generated docs are affected.
7. **Self-review**: confirm the diff aligns with the updated docs and the checklist below.

### Ordering rules

#### Compiler changes (primary first; seed-built artifacts)

Use this order when changing compiler, std, runtime, or test-runner behavior. The suite you
optimize for is the **bootstrap** one; the seed builds the artifacts but is not the gate.

```bash
# 1) Build the frozen seed (only when it changed or is missing)
cd compiler-reference
swift build -c release
cd ..

# 2) Build bootstrap and the shared test runner WITH THE SEED (trust boundary above)
compiler-reference/.build/release/koralc build --package-config compiler/koral.json --target-module koralc -o bin/compiler
compiler-reference/.build/release/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner

# 3) PRIMARY GATE — run the suite against bin/compiler/koralc
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc -j=8

# 4) Seed self-check and the differential oracle, when the seed or cross-compiler agreement is in scope
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler-reference/.build/release/koralc -j=8
./bin/compiler-test-runner/compiler_runner --compiler differential --swift-koralc compiler-reference/.build/release/koralc --bootstrap-koralc bin/compiler/koralc -j=8
```

Do not use a bootstrap-built next-stage binary as the default test harness unless the task is explicitly self-hosting validation.

#### Bootstrap changes

When changing `compiler/` sources only, the seed is frozen and does not need rebuilding. Rebuild
in the same seed-first order:

1. rebuild the compiler with the frozen seed (skip the seed rebuild unless it changed),
2. rerun the shared test runner for `--compiler bootstrap` and relevant buckets,
3. run the self-host chain when parser, MIR lowering, mono, or codegen is touched.

### Samples verification

After compiler/runtime changes, build representative samples to catch compilation regressions outside the test suite.

```bash
# Example: build a sample with the primary compiler
bin/compiler/koralc build samples/expr-eval/expr_eval.koral -o bin/samples
```

Use the repository's sample build/package targets if the sample uses a manifest.

### Toolchain verification

`toolchain/koral-syntax` is the syntactic front end both `koralfmt` and the std
API doc generator build on: tokenizer, CST, parser, printer, and the formatting
contract. Neither tool scans raw text for declarations. If a change touches how
Koral is parsed or spelled, it lands there first and both consumers follow.

```bash
# Formatter: language assertions + a corpus gate over every real .koral file
bin/compiler/koralc build --package-config toolchain/koralfmt/koral.json --target-module koralfmt/test -o bin/koralfmt-test
bin/koralfmt-test/koralfmt__test

# Std API docs: extraction self-test, then "are the checked-in pages current?"
bin/compiler/koralc build --package-config toolchain/doc/koral.json --target-module koral_doc -o bin/toolchain-doc-gen
bin/toolchain-doc-gen/koral_doc --self-test
bin/toolchain-doc-gen/koral_doc --check

# Regenerate the pages after a change to std's public surface
bin/toolchain-doc-gen/koral_doc
```

The formatter's contract is why its gate can be a gate. The canonical text is
[`../../toolchain/koral-syntax/README.md`](../../toolchain/koral-syntax/README.md); this guide does
not restate it. That is also where the product-binary rebuild lives — the two
targets above are the *gate*, not `bin/koralfmt` itself, and running a stale
formatter is how a rejected spelling silently survives in a tree that passes
every assertion here.

### PR/change checklist

- [ ] The governing doc was updated before or alongside the code change.
- [ ] The change lands in `compiler/` first; `compiler-reference/` is touched only to keep the frozen oracle honest.
- [ ] Build provenance holds: the oracle and the test harness are built by the frozen seed, never by the implementation under test.
- [ ] The shared test runner passes for **`--compiler bootstrap` (the primary implementation)** and the seed self-check when affected.
- [ ] Samples are built when the compiler/runtime surface changes.
- [ ] Toolchain validation is rerun when formatting or docs are affected.
- [ ] The final diff documents the exact verification performed.

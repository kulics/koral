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
- `toolchain/` — `koral` build tool, `koralfmt` formatter, `doc` std API doc generator, VS Code extension
- `samples/` — sample programs
- `docs/` — language docs and this guide

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
bin/compiler/koralc build --package-config path/to/koral.json --target-module app::main

# Type-check only
bin/compiler/koralc check --package-config path/to/koral.json --target-module app::main

# Build and run
bin/compiler/koralc run --package-config path/to/koral.json --target-module app::main

# Emit C only
bin/compiler/koralc emit-c --package-config path/to/koral.json --target-module app::main -o output/

# Disable stdlib preload
bin/compiler/koralc build --package-config path/to/koral.json --target-module app::main --no-std
```

The frozen seed is reached the same way, just with its own binary:

```bash
compiler-reference/.build/release/koralc build --package-config path/to/koral.json --target-module app::main
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

- Module entry file names must be valid module names: start with a lowercase letter, then continue with lowercase letters, digits, or `_`.
- `using "file"` resolves relative to the current file's directory, not the module root.
- `using "file"` merges the target file into the current module; it does not create a submodule or alias.
- Cross-module imports must use explicit module syntax such as `using std::io { Reader }` or `using std::io { .. }`.
- `..` must be the only item inside a module import list.
- Imported symbols are file-local bindings and are not re-exported automatically.
- Module imports bind symbols only; they must not create a source-level module namespace or support `module.Symbol` access.
- Module names come from `koral.json` / `std/koral.json`; 

## Language Rules That Commonly Drift

- String literals use double quotes (`"..."`); rune literals use single quotes (`'x'`).
- Type aliases must start with an uppercase letter.
- `[]` is builtin syntax only for `String`, `List`, `Deque`, `*unsafe`, and `*unsafe mutable`; custom traits do not define subscript behavior.
- `docs/grammar_preview.koral` is illustrative only and may lead the parser. For grammar-sensitive work, treat `docs/grammar.bnf`, parser code, and tests as authoritative.
- Generic trait identity includes trait arguments. Do not compare only the base trait name on conformance, witness, vtable, or generic-bound paths.
- Trait-object exact type patterns use the concrete type name directly and operate on the erased trait-object subject; they do not auto-deref to the concrete value type.
- Trait-object exact type patterns are open-world checks. In `when`, they do not make a match exhaustive; keep a default `_` arm.
- Trait objects are direct trait-name types; no `Object` marker trait is required.
- Weak capability is expressed with the `mutable` type-parameter constraint plus `?T`, not via a `Weak` marker trait.

## Simplified Reference and ARC Semantics

The active model is the simplified, declaration-site mutability design:

- managed refs are removed: no `*T`, `*mutable T`, `?*T`, `?*mutable T`, no `&`, no `&mutable`, and no `box()`
- raw pointers remain: `*unsafe T`, `*unsafe mutable T`, `&unsafe`, `&unsafe mutable`
- `type mutable` controls nominal shared-object semantics, not field-by-field mutability for ordinary types
- non-`type mutable` nominal types must keep all fields immutable; only `type mutable` types may declare `mutable` fields
- `Clone` is explicitly shallow-copy semantics: duplicate the object handle or backing storage, not a recursive deep copy

The compiler may still use ARC and hidden storage for implementation, but those choices are not user-visible semantics. The language contract is about shared identity and field mutability, not whether a value happened to be heap-backed or box-optimized.

```koral
type Vec(x Int, y Int);

type mutable Counter(mutable value Int, id UInt);

let c = Counter(0);
c.value = 1;    // valid because Counter declares a mutable field

let v = Vec(1, 2);
// v.x = 3;     // invalid: Vec is not type mutable and its fields are immutable
```

## Drop Semantics

- `Drop` uses `drop(self) Void`.
- `Drop` is a normal trait requirement with a compiler-reserved finalization context; it is not a user-invoked method.
- A type that implements `Drop` must behave as an ARC-backed object at runtime, even when the compiler's layout analysis may optimize away some extra layers for a local value.
- `Drop` is separate from weak capability; trait objects are gated by object safety rather than an `Object` marker trait.
- The compiler may perform finalization in an internal managed-lifetime context and still hide the raw address details from user code.
- Do not impose a primitive-field whitelist on `Drop` implementors. Composite-field types are valid; the important restriction is destructor behavior, not field shape.

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

When designing standard-library APIs, `self` is the only receiver form. Whether `self` acts as an immutable or mutable receiver depends entirely on the type declaration:

- For `type` (immutable types), `self` is an immutable receiver. Fields are all immutable and there is no shared-object identity.
- For `type mutable` (mutable types), `self` is a mutable receiver on the shared object. Fields can be mutated in place if declared `mutable`.

There is no `*self` or `*mutable self`. There is no auto-ref or auto-deref. The type declaration determines the receiver behavior.

Primary rule:

- On `type`, `self` is naturally suited for observation, derivation, and transformation that returns new values, since the receiver is immutable and there is no shared-object aliasing concern.
- On `type mutable`, `self` provides shared access to the mutable object. Methods that modify in place (such as `push` on `List`) and methods that observe (such as `count` on `List`) both use `self`; the difference is in what the method body does, not the receiver form.
- On either kind, `self` may semantically consume the receiver when the method is a terminal extraction, ownership conversion, or linear builder step.

### Default Receiver Choices

Use `self` on `type` when the call should leave the original value logically usable by the caller. Since `type` is immutable, all methods naturally preserve the caller's value.

Common cases on `type`:

- predicates such as `is_empty`, `contains`, `starts_with`
- accessors and getters such as `count`, `name`, `pattern`
- formatting and display such as `to_string`, `message`
- pure derived values such as `dir_name`, `base_name`, `components`
- view-producing methods that do not consume the source
- transformation methods that return new values, such as `trim`, `normalize`, `to_ascii_uppercase`

Use `self` on `type mutable` for both mutation and observation.

Common mutation cases on `type mutable`:

- container updates such as `push`, `insert`, `remove`, `clear`
- stateful cursor updates
- mutation APIs returning removed values, such as `pop` or `take_at`

Common observation cases on `type mutable`:

- accessors and getters such as `count`, `peek`, `is_empty`
- predicates and display methods

Use `self` on either kind of type when consuming the receiver is part of the API contract.

Common consumption cases:

- terminal extraction such as `unwrap`, `expect`, `into_list`
- transforming combinators on ownership-carrying enums such as `Option.map` and `Result.map`
- iterator adapters or terminal operations that must consume iteration state
- linear builders such as `Task.set_name(...).set_stack_size(...).spawn()`
- explicit ownership-conversion methods with `into_*` naming

Builder-style APIs need one extra distinction:

- keep `self` when the builder is intentionally modeled as a linear fluent pipeline whose chained calls conceptually move from one configuration stage to the next
- on `type mutable`, builders naturally support chaining via the shared handle, so methods that configure and return the same handle are idiomatic
- on `type`, a builder that needs repeated configuration should use a consuming `self` pipeline if the chaining behavior is part of the public contract

### Returned New Values Do Not Consume the Receiver

Returning a new value is not, by itself, a reason to consume the receiver.

On `type`, all methods naturally leave the original value usable because `type` is immutable. Transformation methods such as path manipulation, string trimming, and structural projections return new values while the original remains unchanged.

On `type mutable`, methods that return new values while preserving the shared object (such as `pop` returning a removed element) also do not consume the receiver.

Consume the receiver only when the API is intentionally framed as consuming or forwarding ownership, such as `into_*` methods or terminal combinators.

### Small Pure Value Types

For compact immutable value types, receiver design may prioritize value-style ergonomics over strict borrow minimality.

Examples include:

- `Duration`
- `Date`
- `ClockTime`
- `MonoTime`
- sometimes `DateTime` when treated as a compact timestamp value rather than a heavy handle
- compact address or identifier values such as `Ipv4Addr`, `Ipv6Addr`, `IpAddr`, and `SocketAddr`
- compact bitflag wrappers such as `RegexFlag`

For such types, it is acceptable to keep observation and pure derivation methods on `self` when all of the following are true:

- the type is cheap to copy relative to the surrounding API
- the methods conceptually behave like arithmetic or scalar queries
- the family already uses value receivers consistently
- borrowing would add signature noise without unlocking important mutation or aliasing guarantees

Do not apply this exception to heap-owning value types such as `String`, `Path`, containers, or other APIs where shared-object semantics materially improve reuse expectations for callers.

This exception can also cover "sum-of-small-values" enums and tiny wrappers whose payloads are still plain value data rather than handles or heap ownership. Network address values and regex flag bitmasks fit this category; JSON values, strings, paths, and collections generally do not.

### Handle Types and Interior Mutation

Some standard-library types are handles around shared mutable state, for example buffered readers, files, sockets, processes, or timers backed by OS resources. These are `type mutable` types.

For such handle types, `self` provides shared access to the handle, and methods that change underlying state (such as advancing a file cursor or buffering new data) model shared handle mutation, not direct value mutation of the outer type.

This pattern is inherent to `type mutable`. Do not generalize interior-mutation reasoning to `type` types such as containers, strings, or path values, which must remain semantically immutable.

### Borrowed Methods Implemented via Iteration

Do not let an iterator implementation detail force a method to appear consuming.

If a method is semantically observational or purely derived, its public API should reflect that, even when the easiest implementation strategy is to iterate.

Prefer the following order:

1. Implement the method directly with traversal over storage or fields.
2. If the type can cheaply create an iterator snapshot without semantically consuming the value, construct that iterator internally and keep the method observational.
3. Only expose a consuming method when iteration truly consumes unique state as part of the API contract.

This distinction matters because many iterators are consuming in the iterator sense while their source container is not consuming in the API sense. On `type mutable` containers, creating an iterator passes the shared handle and does not consume the container.

Examples:

- a `List` or `String` method may remain observational even if it creates an owned iterator object internally, because the iterator only snapshots shared storage plus cursor state
- a stream, generator, or one-shot parser should not expose observation methods that secretly consume its progression state

### Iterable as a Borrowed Protocol

`Iterator` itself is inherently consuming: `next(self)` advances the iterator's internal cursor and may exhaust the iteration.

`Iterable`, however, is usually better modeled as a borrowed-producing protocol: creating an iterator is typically an observation of the source, not a change to it.

For `type mutable` containers, `iterator(self)` naturally models this: the call passes the shared handle to the container, creates an iterator that snapshots the container's storage and cursor state, and the container itself remains reusable. The `type mutable` declaration ensures the container has shared-object identity, and the iterator is an independent cursor over that shared storage.

For `type` values (such as range-like values), `iterator(self)` is equally appropriate since `type` is inherently non-consuming.

Typical `Iterable` cases where the source remains reusable:

- containers such as `List`, `Set`, `Dict`, `Deque`, `Queue`, `Stack`, and `PriorityQueue` (all `type mutable`)
- range-like values where the range is a reusable description and the iterator carries the advancing cursor (typically `type`)

Typical consuming `Iterable`-like cases would be one-shot sources such as generators, streams, or parsers whose progression state lives in the source value itself.

This design also means observational methods such as set algebra should not be treated as consuming merely because they happen to call `iterator()`. If the source collection is `type mutable`, the public API naturally preserves the shared handle.

### Arithmetic Traits and Arithmetic-Like APIs

Do not equate "returns a new value" or "looks like an operator" with consuming ownership.

Core arithmetic traits such as `Add`, `Sub`, `Mul`, `Div`, `Rem`, and `Neg` describe pure value algebra and should generally stay value-based. They primarily model scalar algebra over small immutable values, and redesigning them would impose broad signature churn across numeric APIs for little semantic gain.

Use this distinction:

- arithmetic traits describe pure value algebra and may remain `self` / value-parameter based
- non-trait methods that merely resemble algebra should still choose receivers by the actual source type's ownership semantics

Apply that rule to API design as follows:

- for small pure value types such as `Duration`, `Date`, `ClockTime`, and `MonoTime`, arithmetic-style methods and nearby derived operations may stay on `self`
- for heavier values or handle-adjacent types such as `DateTime`, follow the type's own `type` or `type mutable` semantics when the method is observational or derived
- for heap-owning containers (typically `type mutable`), set algebra operations such as `union`, `intersection`, `difference`, and `symmetric_difference` follow the container's own semantics even though they are mathematically operator-like

`duration_to` should be classified by type semantics, not by name alone:

- on scalar-like time values (typically `type`), `duration_to(self, other)` is naturally value-style
- on heavier timestamp-like types, follow the type's own declaration semantics

Likewise, predicates such as `is_subset_of` and `is_superset_of` are observational set queries, not arithmetic consumption. They should follow the normal observation semantics for containers.

For non-receiver operands, stay pragmatic. Ordinary parameters do not get receiver adjustment, so the current language design naturally supports `self + value operand` as the right balance for APIs like set algebra and random generation helpers.

If implementing an observation method requires a local value copy to feed an iterator, that is acceptable when the copied value is just a cheap outer handle or immutable small value. Treat that as an implementation artifact, not as evidence that the method should be consuming.

When migrating existing methods to the new `type` / `type mutable` model, recheck two common implementation leftovers:

- branches that still pass or return the receiver by value when the method should preserve it
- helper or iterator constructors that still consume the receiver when they only need observation access

In both cases, the fix is often to adjust the implementation to work with the shared handle rather than consuming the value. This is a migration detail, not a reason to change the public API design.

If the implementation would require copying a large value or heap-owning structure solely to satisfy a consuming iterator API, prefer one of these instead:

- add a helper that traverses storage directly
- add a dedicated borrowed-view iterator type or borrowed-producing helper
- keep the method consuming only if the operation is genuinely consumption-oriented

The public API design should be driven by ownership semantics at the call site, not by the convenience of a specific iterator implementation.

### Trait Design Guidance

For new traits, the receiver semantics are determined by the implementing type's declaration:

- for `type` implementors, `self` provides immutable access suitable for observation traits
- for `type mutable` implementors, `self` provides shared mutable access suitable for mutation traits
- consuming traits use `self` on either kind of type when the method semantically consumes the receiver
- trait-object upcasting uses direct trait names and object safety instead of an `Object` marker trait
- weak capability is opt-in via `mutable` constraints and `?T`

Existing core traits are not fully uniform today. In particular, observation traits such as `ToString` and `Error` already follow borrow-oriented design, while `Eq`, `Ord`, and `Hash` remain value-receiver traits for historical reasons. Treat those core traits as legacy constraints unless the task is explicitly a wider trait redesign.

`Formattable` should currently be treated the same way: it remains rooted in scalar formatting and inherited widely across numeric types. Do not use its scalar-value design as evidence that unrelated derived or observational APIs should follow the same pattern.

### Naming Guidance

Receiver choice and method naming should reinforce each other:

- prefer `into_*` for consuming conversions and ownership-moving adapters
- prefer `to_*`, `as_*`, `with_*`, and predicate/getter names for observation or derivation
- avoid naming a borrowed method in a way that suggests linear consumption

### Review Checklist

Before adding or changing a method in `std/`, ask:

1. After this call, should the caller still expect to use the original receiver value? (Almost always yes; the caller retains the original.)
2. Is the receiver `type` or `type mutable`? (This determines whether `self` is immutable or mutable.)
3. Does the method name match the ownership behavior of the receiver and the method body?

If the type is `type`, all methods are observation or transformation by nature. If the type is `type mutable`, both mutation and observation methods use `self`; verify that the method body matches the stated intent. If the method semantically consumes the receiver, ensure that consumption is part of the public contract (e.g., `into_*` naming).

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
4. Keep module selection manifest-driven; do not reintroduce directory-inferred module trees.

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

| Declaration | Default Access |
|-------------|----------------|
| global function/type/trait | `module_private` |
| struct field | `public` |
| enum case | `public` |
| trait method | `public` |
| given method | `module_private` |
| using declaration | file-local (imported bindings are not re-exported) |

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
swift run koralc emit-c --package-config path/to/koral.json --target-module app::main -o output/
```

## FAQ

### How are cyclic type references handled?

`Type` uses `DefId` indexing instead of embedding recursive type payloads directly. Pass 1 registers names and allocates `DefId`, Pass 2 resolves full details and fills `DefIdMap`.

### How are generic parameter scopes handled?

Use `UnifiedScope.defineGenericParameter()` to register generic parameters. Lookup prioritizes generic parameters over ordinary names.

### How is C identifier uniqueness guaranteed?

Use `DefIdMap.uniqueCIdentifier(for:)` or `CIdentifierUtils.generateCIdentifier()` to handle module path, private symbol file isolation, C keyword escaping, and collision resolution.

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
2. Declare external functions with `foreign let`
3. Declare external types with `foreign type` (optional fields)
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

- `docs/developer-guide.md` — required change workflow, compiler roles and trust boundary, and validation checklist.
- `tests/README.md` — unified test runner contract, flags, buckets, and rerun guidance.
- `compiler/koral.json`, `tests/compiler-runner/koral.json`, `std/koral.json` — build/package targets for the compiler-side builds.
- `toolchain/koralfmt/test/README.md` — formatter regression test contract and execution steps.
- `README.md` — top-level repo shape, prerequisites, quick start, and public contribution guidance.

### Required change workflow

1. **Document first**: update the governing doc in `docs/`, or `tests/README.md` / toolchain docs when behavior, workflow, or validation steps change.
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

Run these validations when the change affects formatting, std API surface, or generated documentation:

```bash
# Build formatter regression runner
bin/compiler/koralc build toolchain/koralfmt/test_fmt.koral -o toolchain/koralfmt/build

# Run formatter regression suite
toolchain/koralfmt/build/test_fmt

# Build std API doc generator
bin/compiler/koralc build toolchain/doc/generate_std_api_docs.koral -o bin/toolchain-doc-gen

# Run doc generator from repo root so it can locate std sources
bin/toolchain-doc-gen/generate_std_api_docs
```

### PR/change checklist

- [ ] The governing doc was updated before or alongside the code change.
- [ ] The change lands in `compiler/` first; `compiler-reference/` is touched only to keep the frozen oracle honest.
- [ ] Build provenance holds: the oracle and the test harness are built by the frozen seed, never by the implementation under test.
- [ ] The shared test runner passes for **`--compiler bootstrap` (the primary implementation)** and the seed self-check when affected.
- [ ] Samples are built when the compiler/runtime surface changes.
- [ ] Toolchain validation is rerun when formatting or docs are affected.
- [ ] The final diff documents the exact verification performed.

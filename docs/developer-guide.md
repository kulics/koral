# Koral Compiler Developer Guide

## Quick Start

### Repository Structure

At repository root:

- `compiler/` — Swift compiler (`koralc`) and tests
- `std/` — standard library sources and runtime C files
- `docs/` — language docs and this guide
- `bootstrap/` — self-hosting compiler implementation
- `toolchain/koralfmt/` — formatter sources
- `toolchain/doc/` — std API doc generator
- `toolchain/koral/` — Koral build tool implementation

### Build the Compiler

```bash
cd compiler
swift build -c debug
```

### Run Tests

```bash
cd compiler
swift build -c debug
cd ..
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8
```

### Run Shared Test Runner

The shared integration test runner is implemented in Koral under `tests/compiler-runner/` and should be built using the Swift host compiler. It can target the Swift compiler, the bootstrap compiler, or a custom compiler binary.

Important trust boundary:

- Use the Swift-hosted `koralc` to build the bootstrap compiler executable and the bootstrap test runner executable.
- Run the host-built runner against the host-built bootstrap compiler.
- Do not rebuild the bootstrap compiler with itself and then use that next-stage binary as the default test harness; that path is reserved for explicit self-hosting validation and is not assumed stable.

```bash
# 1) Build host compiler
cd compiler
swift build -c debug
cd ..

# 2) Build bootstrap compiler executable
compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap

# 3) Build shared test runner executable
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner

# 4) Run shared cases against the host-built bootstrap compiler
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe -j=8
```

Common options:

- `--cases <dir>`: set test case root (default: `tests/compiler-cases`)
- `--compiler <kind>`: select `bootstrap`, `swift`, or `custom` compiler mode
- `--filter <substring>`: run only cases whose file name or relative path contains the substring
- `-j <N>` / `-j=<N>`: worker count for parallel case execution (default: `1`)
- `--timeout <sec>`: per-case timeout in seconds (default: `120`)
- `--memory-limit <MB>`: per-case RSS ceiling (default: `1024`)
- `--compiler-bin <path>`: explicit compiler executable path when `--compiler custom`
- `--bootstrap-koralc <path>`: explicit bootstrap compiler executable path
- `--swift-koralc <path>`: explicit Swift compiler executable path
- `--report-file <path>`: write stable summary log (default: `tests/compiler-cases_output/_reports/latest-summary.log`)
- `--verbose`: print per-case command lines
- `-h`, `--help`: print usage

Examples:

```bash
# Run only hello-related cases
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe --filter hello

# Run shared cases against the Swift compiler
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8

# Point to a custom compiler path
./bin/compiler-test-runner/compiler_runner.exe --compiler custom --compiler-bin path/to/koralc.exe -j=8
```

Current expectations syntax in case files:

- `// EXPECT: <substring>`: output line sequence must contain each substring in order
- `// EXPECT-EXACT: <line>`: normalized non-empty output must exactly match the listed lines
- `// EXPECT-ERROR: <substring>`: case must exit non-zero and contain each error substring in order
- `// EXIT: <code>`: require an explicit process exit code

Current runner exit codes:

- `0`: all matched cases passed
- `1`: one or more cases failed (assertion, timeout, or infra failure)
- `2`: CLI/configuration errors (e.g. invalid flags or missing bootstrap compiler binary)

Case names with these prefixes are tagged for conflict grouping metadata:

- `sync_`
- `net_`
- `os_env_`

Windows notes:

- Default bootstrap compiler path is auto-selected as `bin/bootstrap/koralc.exe` when `OS` contains `Windows`.
- Output matching normalizes CRLF to LF before evaluating `EXPECT` comments.

### Compile Koral Programs

```bash
# Build a manifest target module
swift run koralc build --package-config path/to/koral.json --target-module app::main

# Type-check only
swift run koralc check --package-config path/to/koral.json --target-module app::main

# Build and run
swift run koralc run --package-config path/to/koral.json --target-module app::main

# Emit C only
swift run koralc emit-c --package-config path/to/koral.json --target-module app::main -o output/

# Disable stdlib preload
swift run koralc build --package-config path/to/koral.json --target-module app::main --no-std
```

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
# 1) Build the host bootstrap compiler with the Swift compiler
compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap

# 2) Generate stage2 C
./bin/bootstrap/koralc emit-c --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap-stage2

# 3) Compile stage2
clang bin/bootstrap-stage2/koralc.c std/koral_runtime.c -I std -o bin/bootstrap-stage2/koralc -Wno-everything -O1

# 4) Generate later stages one step at a time
./bin/bootstrap-stage2/koralc emit-c --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap-stage3
clang bin/bootstrap-stage3/koralc.c std/koral_runtime.c -I std -o bin/bootstrap-stage3/koralc -Wno-everything -O1
./bin/bootstrap-stage3/koralc emit-c --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap-stage4
```

Operational rules:

- Keep per-case runner timeout enabled (`--timeout 120` is the current stable baseline).
- Wrap long self-host or suite runs in an outer memory / CPU cap. On this macOS setup, a CPU cap remains useful, but Python's `resource.setrlimit` for `RLIMIT_AS` / `RLIMIT_DATA` may reject updates even when the shell reports unlimited limits. If that happens, keep `--timeout` enabled, apply the CPU cap, and reduce runner parallelism instead of assuming address/data limits can always be enforced from Python.
- Prefer ASan over ad hoc logging once a failure is reproducible. In this repair, ASan was decisive for identifying UAFs in `CodeGen`, `MIRFunctionCodeEmitter`, and `RecursiveTypeChecker` working-state handling.

### Cleanup Rules After Bootstrap Debugging

- Remove temporary codegen probe logging after the failing boundary is identified. Keeping those probes in-tree can change ownership/lifetime lowering and create misleading secondary failures.
- Clean out stale stage directories under `bin/` once a repair is validated. Keep only actively useful entrypoints such as `bin/bootstrap/`, `bin/compiler-test-runner/`, and current user-facing tool outputs.
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
    ./bin/compiler-test-runner/main --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc --filter "$case_name" --timeout 120
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
2. Update `ParserDeclarations.swift` and `bootstrap/koralc/parser/core_precedence.koral`.
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

2. Add a test method in `IntegrationTests.swift`:

```swift
func test_my_feature() throws { try runCase(named: "my_feature.koral") }
```

For failure cases, add `// EXPECT-ERROR: ...`; the test harness expects a non-zero exit and matching error output substring.

How integration tests run (current behavior):

- Tests execute the prebuilt binary directly: `.build/debug/koralc(.exe)`.
- Build before running tests:

```bash
cd compiler
swift build -c debug
cd ..
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8
```

- Output assertions are comment-based and order-sensitive:
    - `// EXPECT: <substring>`
    - `// EXPECT-ERROR: <substring>`
- Each run uses an isolated temp output directory under `tests/compiler-cases_output/<caseName>/<uuid>/`, then cleans it up.

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

- `docs/developer-guide.md` — required change workflow, bootstrap/compiler ordering, and validation checklist.
- `tests/README.md` — unified test runner contract, flags, buckets, and rerun guidance.
- `bootstrap/koral.json`, `tests/compiler-runner/koral.json`, `std/koral.json` — build/package targets for the compiler-side builds.
- `toolchain/koralfmt/test/README.md` — formatter regression test contract and execution steps.
- `README.md` — top-level repo shape, prerequisites, quick start, and public contribution guidance.

### Required change workflow

1. **Document first**: update the governing doc in `docs/`, or `tests/README.md` / toolchain docs when behavior, workflow, or validation steps change.
2. **Update implementation**: change compiler/runtime/toolchain code only after the doc baseline is updated.
3. **Update tests**: update existing expectations or add regression coverage before merge.
4. **Validate compiler bootstrap order**: rebuild the host compiler first, then rebuild bootstrap, then run the shared runner against bootstrap and Swift builds.
5. **Validate samples**: build representative samples after compiler/runtime changes.
6. **Validate toolchain**: run formatter and/or doc-generator validation when formatting rules, std surface, or generated docs are affected.
7. **Self-review**: confirm the diff aligns with the updated docs and the checklist below.

### Ordering rules

#### Compiler changes (host -> bootstrap -> tests)

Use this order when changing compiler, std, runtime, or test-runner behavior:

```bash
# 1) Build Swift host compiler
cd compiler
swift build -c debug
cd ..

# 2) Build bootstrap compiler using the host-built compiler
compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap

# 3) Build shared test runner
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner

# 4) Run tests against bootstrap
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe -j=8

# 5) Run tests against Swift host compiler
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8
```

Do not use a bootstrap-built next-stage binary as the default test harness unless the task is explicitly self-hosting validation.

#### Bootstrap changes

When changing bootstrap sources only, rebuild in the same host-first order:

1. rebuild Swift host compiler,
2. rebuild bootstrap with host-built compiler,
3. rerun the shared test runner for `--compiler bootstrap` and relevant buckets.

### Samples verification

After compiler/runtime changes, build representative samples to catch compilation regressions outside the test suite.

```bash
# Example: build a sample using the host-built compiler
compiler/.build/debug/koralc build samples/expr-eval/expr_eval.koral -o bin/samples
```

Use the repository's sample build/package targets if the sample uses a manifest.

### Toolchain verification

Run these validations when the change affects formatting, std API surface, or generated documentation:

```bash
# Build formatter regression runner
compiler/.build/debug/koralc build toolchain/koralfmt/test_fmt.koral -o toolchain/koralfmt/build

# Run formatter regression suite
toolchain/koralfmt/build/test_fmt.exe

# Build std API doc generator
compiler/.build/debug/koralc build toolchain/doc/generate_std_api_docs.koral -o bin/toolchain-doc-gen

# Run doc generator from repo root so it can locate std sources
bin/toolchain-doc-gen/toolchain_doc_gen.exe
```

### PR/change checklist

- [ ] The governing doc was updated before or alongside the code change.
- [ ] The change preserves host-first build ordering for compiler/bootstrap flows.
- [ ] The shared test runner passes for both bootstrap and Swift targets when affected.
- [ ] Samples are built when the compiler/runtime surface changes.
- [ ] Toolchain validation is rerun when formatting or docs are affected.
- [ ] The final diff documents the exact verification performed.

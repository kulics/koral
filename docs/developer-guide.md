# Koral Compiler Developer Guide

## Quick Start

### Repository Structure

At repository root:

- `compiler/` — Swift compiler (`koralc`) and tests
- `std/` — standard library sources and runtime C files
- `docs/` — language docs and this guide
- `bootstrap/` — self-hosting compiler implementation
- `toolchain/fmt/` — formatter sources

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
- `--compiler-bin <path>`: explicit compiler executable path when `--compiler custom`
- `--bootstrap-koralc <path>`: explicit bootstrap compiler executable path
- `--swift-koralc <path>`: explicit Swift compiler executable path
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

# Print escape analysis diagnostics (Go-style)
swift run koralc build --package-config path/to/koral.json --target-module app::main -m
swift run koralc build --package-config path/to/koral.json --target-module app::main -m=2
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
- `[]` is builtin syntax only for `String`, `List`, `Deque`, `ptr`, and `ptr mut`; custom traits do not define subscript behavior.
- `docs/grammar_preview.koral` is illustrative only and may lead the parser. For grammar-sensitive work, treat `docs/grammar.bnf`, parser code, and tests as authoritative.

## Reference Creation Semantics (`.ref` / `box`)

Koral distinguishes read-only references (`ref T`) from mutable references (`ref mut T`), and read-only pointers (`ptr T`) from mutable pointers (`ptr mut T`):

- `x.ref` forms a managed reference from an existing lvalue. The result type depends on the source's mutability:
    - `let mut` binding → `ref mut T`
    - `let` (immutable) binding → `ref T`
    - Mutable path (e.g. `ref mut`'s `mut` field) → `ref mut T`
- `ref mut T` implicitly converts to `ref T` (widening). The reverse is not allowed.
- `.ref` on rvalues is rejected.
- `ref T` supports `.val` read only. `ref mut T` supports `.val` read and `.val = expr` assignment.
- `ptr T` supports `.val` read only. `ptr mut T` supports `.val` read, `.val = expr`, and `p[i] = expr`.
- `box(expr)` returns `ref mut T` — an escaping managed reference from temporaries/literals.
- `box` should be understood as binding its parameter locally and returning `v.ref`; once that reference escapes, cleanup transfers to the ref owner instead of dropping the local again.
- Ordinary parameter `mut` is local binding mutability only. It is not part of the function signature, function type, or trait/given conformance comparison.

```koral
let mut x = 10
let rx ref mut Int = x.ref    // let mut → ref mut T

let y = 10
let ry ref Int = y.ref        // let → ref T (read-only)

let owned ref mut Int = box(42)   // box() returns ref mut T

// let rz = 42.ref            // error: rvalue cannot be borrowed
```

## Drop Semantics

- `Drop` uses `drop(source ptr mut Self) Void`.
- Treat `Drop.drop` as a compiler-reserved destructor entry, not a normal user-callable method.
- The parameter is raw owned storage, so `Drop` should not rely on ref-style escape distinctions such as borrow-vs-owned checks.
- Do not impose a primitive-field whitelist on `Drop` implementors. Composite-field types are valid; the important restriction is destructor behavior, not field shape.

## Standard Library Receiver Design

When designing standard-library APIs, choose method receivers by ownership semantics first and implementation convenience second.

Primary rule:

- Use `self ref` for observation and derivation.
- Use `self ref mut` for in-place mutation.
- Use `self` only when the method semantically consumes the receiver.

This is a semantic default, not a mechanical rule. For small immutable value types that behave like scalars in the API, using `self` for observation can still be reasonable when it keeps the whole type family consistent and avoids borrow-heavy signatures.

This rule matters because receiver adjustment has asymmetric call behavior:

- `self ref` accepts both lvalue and rvalue receivers. Rvalue calls may materialize a temporary.
- `self ref mut` requires a writable lvalue receiver.
- `self` transfers ownership and should therefore communicate real consumption, not just implementation preference.

### Default Receiver Choices

Use `self ref` when the call should leave the original value logically usable by the caller.

Common `self ref` cases:

- predicates such as `is_empty`, `contains`, `starts_with`
- accessors and getters such as `count`, `name`, `pattern`
- formatting and display such as `to_string`, `message`
- pure derived values such as `dir_name`, `base_name`, `components`
- view-producing methods that do not consume the source

Use `self ref mut` when the method mutates the receiver in place.

Common `self ref mut` cases:

- container updates such as `push`, `insert`, `remove`, `clear`
- stateful cursor updates on direct value types
- mutation APIs returning removed values, such as `pop` or `take_at`

Use `self` only when consuming the receiver is part of the API contract.

Common `self` cases:

- terminal extraction such as `unwrap`, `expect`, `into_list`
- transforming combinators on ownership-carrying enums such as `Option.map` and `Result.map`
- iterator adapters or terminal operations that must consume iteration state
- linear builders such as `Task.set_name(...).set_stack_size(...).spawn()`
- explicit ownership-conversion methods with `into_*` naming

Builder-style APIs need one extra distinction:

- keep `self` when the builder is intentionally modeled as a linear fluent pipeline whose chained calls conceptually move from one configuration stage to the next
- prefer `self ref` when the API is really a reusable handle with derived helper methods or repeatable configuration/query operations, even if the implementation stores state behind a ref

In other words, "internally ref-backed" does not automatically make a builder-style API borrowed. Use `self` only when the chaining behavior is part of the public contract, not merely because returning `self` is convenient.

### Returned New Values Do Not Imply `self`

Returning a new value is not, by itself, a reason to use `self`.

Prefer `self ref` when the method computes a new value but the caller should still think of the original receiver as available. Examples include path manipulation, string trimming, and structural projections.

Prefer `self` only when the API is intentionally framed as consuming or forwarding ownership.

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

Do not apply this exception to heap-owning value types such as `String`, `Path`, containers, or other APIs where `self ref` materially improves reuse expectations for callers.

This exception can also cover "sum-of-small-values" enums and tiny wrappers whose payloads are still plain value data rather than handles or heap ownership. Network address values and regex flag bitmasks fit this category; JSON values, strings, paths, and collections generally do not.

### Handle Types and Interior Mutation

Some standard-library types are handles around shared mutable state, for example buffered readers, files, sockets, processes, or timers backed by internal `ref mut` storage or OS resources.

For such handle types, methods may use `self ref` even when the underlying state changes. In these cases the API models shared access to a handle, not direct value mutation of the outer type.

Use this exception deliberately. Do not generalize handle-style `self ref` mutation to ordinary value types such as containers, strings, or path values.

### Borrowed Methods Implemented via Iteration

Do not let an iterator implementation detail force a public receiver to become `self`.

If a method is semantically observational or purely derived, it should usually remain `self ref` even when the easiest implementation strategy is to iterate.

Prefer the following order:

1. Implement the method directly with borrowed traversal over storage or fields.
2. If the type can cheaply create an iterator snapshot without semantically consuming the value, keep the public method on `self ref` and construct that iterator internally.
3. Only keep the public receiver as `self` when iteration truly consumes unique state as part of the API contract.

This distinction matters because many iterators are consuming in the iterator sense while their source container is not consuming in the API sense.

Examples:

- a `List` or `String` method may stay `self ref` even if it creates an owned iterator object internally, because the iterator only snapshots shared storage plus cursor state
- a stream, generator, or one-shot parser should not expose borrowed observation methods that secretly consume its progression state

### Iterable as a Borrowed Protocol

`Iterator` itself is inherently consuming and should stay `next(self ref mut)`.

`Iterable`, however, is usually better modeled as a borrowed-producing protocol: creating an iterator is typically an observation of the source, not ownership transfer of the source.

When evaluating `iterator(...)`, use this rule:

- prefer `iterator(self ref)` when the iterator is just a snapshot of shared storage plus cursor state
- keep `iterator(self)` only when creating the iterator must semantically consume unique progression state from the source itself

Typical borrowed `Iterable` cases include:

- containers such as `List`, `Set`, `Dict`, `Deque`, `Queue`, `Stack`, and `PriorityQueue`
- range-like values where the range is a reusable description and the iterator carries the advancing cursor

Typical consuming `Iterable`-like cases would be one-shot sources such as generators, streams, or parsers whose progression state lives in the source value itself.

In current `std/`, `Iterable.iterator` now uses `self ref`, which matches the snapshot-style behavior of the existing container and range implementations. Treat that as the default model for reusable sources rather than as a special-case optimization.

This is also why observational methods such as set algebra should not be forced onto `self` merely because they happen to call `iterator()`. If the source collection remains reusable, the public API should still be designed as borrowed.

### Arithmetic Traits and Arithmetic-Like APIs

Do not equate "returns a new value" or "looks like an operator" with consuming ownership.

Core arithmetic traits such as `Add`, `Sub`, `Mul`, `Div`, `Rem`, and `Neg` are value-style protocols today and should generally stay that way. They primarily model scalar algebra over small immutable values, and changing them to borrowed receivers would impose broad signature churn across numeric APIs for little semantic gain.

Use this distinction:

- arithmetic traits describe pure value algebra and may remain `self` / value-parameter based
- non-trait methods that merely resemble algebra should still choose receivers by the actual source type's ownership semantics

Apply that rule to API design as follows:

- for small pure value types such as `Duration`, `Date`, `ClockTime`, and `MonoTime`, arithmetic-style methods and nearby derived operations may stay on `self`
- for heavier values or handle-adjacent types such as `DateTime`, use `self ref` when the method is observational or derived and not semantically consuming
- for heap-owning containers, set algebra operations such as `union`, `intersection`, `difference`, and `symmetric_difference` should usually use `self ref` even though they are mathematically operator-like

`duration_to` should be classified by type semantics, not by name alone:

- on scalar-like time values, `duration_to(self, other)` can remain value-style
- on heavier timestamp-like types, `duration_to(self ref, other)` is often the better expression of caller expectations

Likewise, predicates such as `is_subset_of` and `is_superset_of` are observational set queries, not arithmetic consumption. They should follow the normal borrowed rule for containers.

For non-receiver operands, stay pragmatic. Ordinary parameters do not get receiver adjustment, so changing container-like operands from value parameters to `ref` parameters often degrades call-site ergonomics more than it improves ownership clarity. In the current language design, `borrowed receiver + value operand` is often the right balance for APIs like set algebra and random generation helpers.

If implementing a `self ref` method requires a local value copy to feed an iterator, that is acceptable when the copied value is just a cheap outer handle or immutable small value. Treat that as an implementation artifact, not as evidence that the public receiver should be `self`.

When migrating an existing method from `self` to `self ref`, recheck two common implementation leftovers:

- branches that still `return self` even though the method returns an owned value
- helper or iterator constructors that still receive `self` even though they expect an owned source value

In both cases, the fix is often to pass or return `self.val` explicitly. This is a migration detail, not a reason to change the public receiver back to `self`.

If the implementation would require copying a large value or heap-owning structure solely to satisfy a consuming iterator API, prefer one of these instead:

- add a borrowed helper that traverses storage directly
- add a dedicated borrowed-view iterator type or borrowed-producing helper
- keep the method on `self` only if the operation is genuinely consumption-oriented

Avoid exposing `.val`-style dereference-copy patterns in public API design discussions. The public rule should be driven by ownership semantics at the call site, not by the current convenience of a specific iterator implementation.

### Trait Design Guidance

For new traits, prefer the narrowest receiver that matches the semantic contract:

- observation traits should usually use `self ref`
- mutation traits should use `self ref mut`
- consuming traits should use `self`
- traits intended for trait objects should keep requirement receivers on `self ref` / `self ref mut` only
- `ref Trait` can call only `self ref` requirements, while `ref mut Trait` can call both `self ref mut` and `self ref`

Existing core traits are not fully uniform today. In particular, `ToString`, `Error`, and indexing traits already follow borrow-oriented design, while `Eq`, `Ord`, and `Hash` remain value-receiver traits for historical reasons. Treat those core traits as legacy constraints unless the task is explicitly a wider trait redesign.

`Formattable` should currently be treated the same way: it remains a value-receiver trait largely because it is rooted in scalar formatting and inherited widely across numeric types. Do not use its value-style receiver as evidence that unrelated derived or observational APIs should also prefer `self`.

### Naming Guidance

Receiver choice and method naming should reinforce each other:

- prefer `into_*` for consuming conversions and ownership-moving adapters
- prefer `to_*`, `as_*`, `with_*`, and predicate/getter names for borrowed observation or derivation
- avoid naming a borrowed method in a way that suggests linear consumption

### Review Checklist

Before adding or changing a method in `std/`, ask:

1. After this call, should the caller still expect to use the original receiver value?
2. Is any mutation directly observable on the receiver itself, or only through an underlying shared handle?
3. Is the method a terminal operation, extraction, or ownership conversion?
4. Does the method name match the ownership behavior implied by the receiver?
5. Would switching from `self` to `self ref` silently broaden call sites by allowing rvalue temporary materialization, and is that desirable for this API?

If the answer to (1) is yes, default to `self ref`. If the answer to (3) is yes, `self` is usually the right choice. If the answer to (2) is direct mutation, use `self ref mut`.

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
| global function/type/trait | `protected` |
| struct field | `protected` |
| enum case | `public` |
| trait method | `public` |
| given method | `protected` |
| using declaration | `private` |

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

### Escape Analysis Integration

```swift
escapeContext.reset(returnType: funcReturnType, functionName: funcName)
escapeContext.preAnalyze(body: typedBody, params: params)

if escapeContext.shouldUseHeapAllocation(innerExpr) {
    // heap
} else {
    // stack
}
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

### View Escape Analysis Diagnostics

Use `-m` / `-m=<N>`:

```bash
swift run koralc build --package-config path/to/koral.json --target-module app::main -m
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

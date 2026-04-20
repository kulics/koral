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

# Run all tests
swift test --parallel
```

The current `compiler/Tests/koralcTests` target uses Swift Testing (`import Testing`, `@Suite`, `@Test`).
On this checkout, forcing XCTest with `--disable-swift-testing --enable-xctest` can produce
`warning: No matching test cases were run.`

### Run Bootstrap Test Runner

The bootstrap-side test runner is implemented in Koral under `bootstrap/test/` and should be built using the Swift host compiler until self-hosting is stable.

Important trust boundary:

- Use the Swift-hosted `koralc` to build the bootstrap compiler executable and the bootstrap test runner executable.
- Run the host-built runner against the host-built bootstrap compiler.
- Do not rebuild the bootstrap compiler with itself and then use that next-stage binary as the default test harness; that path is reserved for explicit self-hosting validation and is not assumed stable.

```bash
# 1) Build host compiler
cd compiler
swift build -c debug

# 2) Build bootstrap compiler executable
cd ..
compiler/.build/debug/koralc build bootstrap/koralc/main.koral -o out/bootstrap

# 3) Build bootstrap test runner executable
compiler/.build/debug/koralc build bootstrap/test/main.koral -o out/bootstrap-test

# 4) Run tests against the host-built bootstrap compiler
./out/bootstrap-test/main --bootstrap-koralc out/bootstrap/main
```

Common options:

- `--cases <dir>`: set test case root (default: `bootstrap/test/cases`)
- `--filter <substring>`: run only cases whose file name or relative path contains the substring
- `-j <N>` / `-j=<N>`: worker count for parallel case execution (default: `1`)
- `--timeout <sec>`: per-case timeout in seconds (default: `60`)
- `--bootstrap-koralc <path>`: explicit bootstrap compiler executable path
- `--verbose`: print per-case command lines
- `-h`, `--help`: print usage

Examples:

```bash
# Run only hello-related cases
./out/bootstrap-test/main --bootstrap-koralc out/bootstrap/main --filter hello

# Run in parallel
./out/bootstrap-test/main --bootstrap-koralc out/bootstrap/main -j 4

# Point to a custom bootstrap compiler path
./out/bootstrap-test/main --bootstrap-koralc out/bootstrap/main
```

Current expectations syntax in case files:

- `// EXPECT: <substring>`: output line sequence must contain each substring in order
- `// EXPECT-ERROR: <substring>`: case must exit non-zero and contain each error substring in order

Current runner exit codes:

- `0`: all matched cases passed
- `1`: one or more cases failed (assertion, timeout, or infra failure)
- `2`: CLI/configuration errors (e.g. invalid flags or missing bootstrap compiler binary)

Case names with these prefixes are tagged for conflict grouping metadata:

- `sync_`
- `net_`
- `os_env_`

Windows notes:

- Default bootstrap compiler path is auto-selected as `out/bootstrap/main.exe` when `OS` contains `Windows`.
- Output matching normalizes CRLF to LF before evaluating `EXPECT` comments.

### Compile Koral Programs

```bash
# Build an executable (default command is build)
swift run koralc path/to/file.koral

# Build and run
swift run koralc run path/to/file.koral

# Emit C only
swift run koralc emit-c path/to/file.koral -o output/

# Disable stdlib preload
swift run koralc path/to/file.koral --no-std

# Print escape analysis diagnostics (Go-style)
swift run koralc path/to/file.koral -m
swift run koralc path/to/file.koral -m=2
```

CLI shape in current implementation:

- `koralc <file.koral> [options]` (defaults to `build`)
- `koralc [build|run|emit-c] <file.koral> [options]`
- If no command is given, the first argument must end with `.koral`.

Output behavior:

- `build`: writes executable and prints `Build successful: <path>`
- `run`: compiles and runs executable
- `emit-c`: writes `<basename>.c` to output directory and exits
- Non-`emit-c` modes use a temporary `.c` file that is cleaned up automatically

### Standard Library Resolution (`KORAL_HOME`)

`Driver.getCoreLibPath()` / `Driver.getStdLibPath()` search in this order:

1. `KORAL_HOME` (expects `$KORAL_HOME/std/std.koral`)
2. `std/std.koral` in current working directory
3. `std/std.koral` in parent directory
4. `std/std.koral` in grandparent directory

If you run `koralc` outside the repository root, set `KORAL_HOME` explicitly.

```bash
# macOS / Linux
export KORAL_HOME=/path/to/koral

# Windows PowerShell
$env:KORAL_HOME = "C:\path\to\koral"
```

Notes:

- If `Driver.getCoreLibPath()` cannot find `std/std.koral`, the driver prints an error and exits.
- `Driver.getStdLibPath()` is also used to add `std/` include path and `koral_runtime.c` to clang when available.

## Reference Creation Semantics (`.ref` / `box`)

Koral distinguishes read-only references (`T ref`) from mutable references (`T mut ref`), and read-only pointers (`T ptr`) from mutable pointers (`T mut ptr`):

- `x.ref` forms a managed reference from an existing lvalue. The result type depends on the source's mutability:
  - `let mut` binding → `T mut ref`
  - `let` (immutable) binding → `T ref`
  - Mutable path (e.g. `mut ref`'s `mut` field) → `T mut ref`
- `T mut ref` implicitly converts to `T ref` (widening). The reverse is not allowed.
- `.ref` on rvalues is rejected.
- `T ref` supports `.val` read only. `T mut ref` supports `.val` read and `.val = expr` assignment.
- `T ptr` supports `.val` read only. `T mut ptr` supports `.val` read, `.val = expr`, and `p[i] = expr`.
- `box(expr)` returns `T mut ref` — an escaping managed reference from temporaries/literals.

```koral
let mut x = 10
let rx Int mut ref = x.ref    // let mut → T mut ref

let y = 10
let ry Int ref = y.ref        // let → T ref (read-only)

let owned Int mut ref = box(42)   // box() returns T mut ref

// let rz = 42.ref            // error: rvalue cannot be borrowed
```

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

1. Add a path kind in `UsingDeclaration.pathKind`
2. Add corresponding `resolveXxx()` logic in `ModuleResolver`
3. Record import edges in `recordImportToGraph()`
4. Implement visibility rules in `AccessChecker`

### Module Resolution Flow

```text
resolveModule(entryFile:)
  └── resolveFile(file:module:unit:)
        ├── Lexer + Parser → AST
        ├── Extract using declarations
        │   └── resolveUsing(using:module:unit:currentFile:)
        │       ├── resolveSubmoduleMerge() → merge submodule into current module
        │       ├── resolveSubmodule()   → create child module and recurse
        │       ├── resolveParent()      → navigate through Super chain
        │       └── resolveExternal()    → lookup external module
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

1. Create a `.koral` case under `compiler/Tests/Cases/`:

```koral
// my_feature.koral
// EXPECT: test passed

using Std.*

let main() = {
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
swift build -c debug
swift test --parallel
```

- Output assertions are comment-based and order-sensitive:
    - `// EXPECT: <substring>`
    - `// EXPECT-ERROR: <substring>`
- Each run uses an isolated temp output directory under `Tests/CasesOutput/<caseName>/<uuid>/`, then cleans it up.

### Add Multi-file / Module Tests

```text
Tests/Cases/my_module_test/
├── my_module_test.koral    # entry file (must match folder name)
├── helper.koral            # merged file (using "helper")
└── child/
    └── child.koral         # submodule (using "child" as Child)
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
swift run koralc hello.koral -m
```

### Inspect Generated C

```bash
swift run koralc emit-c myfile.koral -o output/
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
3. Add code generation in `CodeGenExpressions.swift`
4. Declare it in stdlib with `intrinsic`

### How do I add a new foreign binding?

1. Declare external library with `foreign using "library"`
2. Declare external functions with `foreign let`
3. Declare external types with `foreign type` (optional fields)
4. CodeGen emits C declarations; Driver appends linker `-l` flags

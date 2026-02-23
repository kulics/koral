# Koral Compiler Developer Guide

## Quick Start

### Build the Compiler

```bash
cd compiler
swift build -c debug
```

### Run Tests

```bash
# Run all tests
swift test

# Run integration tests only
swift test --filter IntegrationTests

# Run in parallel (faster)
swift test --parallel

# Run one specific test
swift test --filter IntegrationTests/test_hello
```

### Compile Koral Programs

```bash
# Build an executable (default command is build)
swift run koralc hello.koral

# Build and run
swift run koralc run hello.koral

# Emit C only
swift run koralc emit-c hello.koral -o output/

# Disable stdlib linkage
swift run koralc hello.koral --no-std

# Print escape analysis report
swift run koralc hello.koral --escape-analysis-report
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
        │       ├── resolveFileMerge()   → merge file into current module
        │       ├── resolveSubmodule()   → create child module and recurse
        │       ├── resolveParent()      → navigate through super chain
        │       └── resolveExternal()    → lookup external module
        └── Collect non-using top-level nodes
```

### Access Control Defaults

| Declaration | Default Access |
|-------------|----------------|
| global function/type/trait | `protected` |
| struct field | `protected` |
| union case | `public` |
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

using std.*

let main() = {
    print_line("test passed")
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
swift test
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
    └── child.koral         # submodule (using self.child)
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
print(diagnosticCollector.formatWithSource(sourceManager: sourceManager))
```

### View Escape Analysis Report

Use `--escape-analysis-report`, or in code:

```swift
let escapeContext = EscapeContext(reportingEnabled: true, context: context)
print(escapeContext.getFormattedDiagnostics())
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

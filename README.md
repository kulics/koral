# The Koral Programming Language

Koral is an experimental compiled language that combines **Go's aggressive escape analysis** with **Swift's Automatic Reference Counting (ARC)**. It targets C to deliver predictable, high-performance memory management without a garbage collector, while keeping the syntax clean and its core control flow expression-oriented.

This repository contains the compiler, standard library, formatter, language documentation, and sample projects.

> Status: Koral is in an experimental stage and is not yet production-ready.

Reference note:

- `README.md` is a high-level overview, not the canonical grammar document.
- For syntax-sensitive details, use `docs/grammar.bnf` and current compiler behavior as the source of truth.
- If this README disagrees with the compiler, prefer compiler behavior and update the README.

## The Core Idea: ARC + Escape Analysis

Most compiled languages make you choose: either you get high-level ergonomics with a tracing garbage collector, or you get manual control with verbose syntax. Koral offers a middle ground:

1. **Escape Analysis First**: Every allocation is analyzed at compile time. If the compiler can prove that an object does not escape its current scope, it is allocated on the stack. Stack allocation is practically free and completely bypasses ARC overhead.
2. **ARC for the Rest**: If an object *does* escape, it is allocated on the heap and managed via Automatic Reference Counting. This provides predictable, pause-free performance.

Because Koral compiles to C, stack allocations become standard C local variables. The backend compiler can heavily optimize them, often keeping them entirely in CPU registers and optimizing away reference counting operations for local data.

```koral
// The compiler sees this doesn't escape. 
// It's allocated on the stack. No ARC overhead.
let local_point = Point(1, 2)

// box(...) creates an owned escaping mutable reference.
let heap_point = box(Point(3, 4))

// The 'ref' keyword borrows from an existing lvalue.
// Result mutability depends on the source: let mut → ref mut, let → ref.
let mut local_point2 = Point(3, 4)
let heap_point_ref = local_point2.ref  // ref mut (from let mut)

// Bumping the refcount, no deep copy
let shared_point = heap_point 
```

## Language Highlights

- **No GC, No Manual `free`**: Automatic memory management based on reference counting and escape analysis.
- **Expression-Oriented Control Flow**: `if`, `when`, and blocks produce values; `while` and `for` keep the same surface style but remain statement-only.
- **Zero-Cost Abstractions**: Generics with trait constraints and monomorphization.
- **Algebraic Data Types**: Structs and enums with exhaustive pattern matching.
- **C Interop**: Foreign function interface (FFI) and a C backend for broad platform compatibility.

## Syntax Quick Tour

### Expression-oriented core control flow

```koral
let sign = if x > 0 then 1 else if x < 0 then -1 else 0

let label = when status in {
    .Active then "running",
    .Paused(reason) then "paused: " + reason,
    .Stopped then "done",
}
```

Blocks are also expressions, so branch bodies can stay local instead of forcing helper functions. When a branch body uses a block, that block still defaults to `Void`; use `yield` to produce the enclosing `if` or `when` expression's value from inside the block.

```koral
let label = if score >= 90 then {
    if score == 100 then {
        yield "perfect"
    }
    yield "A"
} else {
    yield "other"
}
```

`while` and `for` intentionally keep the same `... then ...` surface shape, but they are statements rather than value-producing expressions.

### Pattern matching built into `if` and `while`

Rules:

- `is` may destructure directly inside `if` and `while` conditions.
- Bound names from an earlier `is` clause remain visible to later `and` clauses.
- Condition chains evaluate left-to-right with normal short-circuit behavior.

```koral
if config.get("port") is .Some(v) then start_server(v)

while iter.next() is .Some(item) then process(item)
```

You can chain multiple condition clauses with `and`.
Each clause runs only if previous clauses succeed, and bindings from earlier `is` clauses are visible to later clauses.

```koral
if load() is .Some(a) and parse(a) is .Ok(b) and b.is_valid() then use(b)

while source.next() is .Some(raw) and decode(raw) is .Ok(msg) then handle(msg)
```

### Pattern combinators: `or`, `and`, `not`

```koral
when temperature in {
    > 0 and < 100 then "liquid",
    <= 0 then "solid",
    >= 100 then "gas",
}
```

### `or else` / `and then` / `or return` — Error flow as keywords

```koral
let port = config.get("port") or else 8080

let name = user and then it.profile and then it.display_name or else "anonymous"

let read_config(path String) Result[Config] = {
    let text = read_text_file(path) or return
    let parsed = parse_json(text) or return
    return .Ok(parsed)
}
```

### Generics

```koral
let nums = List[Int].new()
let scores = Dict[String, Int].new()
let max[T Ord](a T, b T) T = if a > b then a else b
```

### Traits and `given` blocks

```koral
trait Greet {
    greet(self ref) String
}

type Bot(name String)

given Bot as Greet {
    greet(self ref) String = "beep boop, I'm " + self.name
}

let g ref Greet = box(Bot("K-9"))  // trait object
```

### Algebraic data types with implicit member syntax

Rules:

- `.Member(...)` requires an expected type from context.
- It may construct enum cases or call static methods.
- If the expected type is not known, the expression is rejected.

```koral
type Result[T Any] {
    Ok(value T),
    Error(error ref Error),
}

let parse_int(s String) Result[Int] =
    if s == "42" then .Ok(42) else .Error(box("bad input"))
```

### Lazy streams

```koral
let result = list.iterator()
    .filter((x) -> x > 0)
    .map((x) -> x * 2)
    .take(10)
    .fold(0, (acc, x) -> acc + x)
```

## Language Capabilities

### Type System

- Primitive types: `Bool`, `Int`, `UInt`, `Int8`–`Int64`, `UInt8`–`UInt64`, `Float32`, `Float64`, `Never`
- Structs (product types): `type Point(x Int, y Int)`
- Enums (sum types / tagged enums): `type Shape { Circle(r Float64), Rectangle(w Float64, h Float64) }`
- Type aliases: `type Name = TargetType`
- Generic types and functions: `Type[T]`, `func[T Constraint](...)`
- Function types: `Func[Int, Int, Int]` — `(Int, Int) -> Int`
- Reference types: `ref` (read-only), `ref mut` (mutable), `ptr` (read-only), `ptr mut` (mutable), `weakref` (read-only weak), `weakref mut` (mutable weak)

### Control Flow

- `if / then / else` expressions (with pattern matching via `is`)
- `while` statements (with pattern matching via `is`)
- `for` statements over any `Iterable`
- `when` expressions for exhaustive pattern matching
- `finally` for deterministic cleanup
- `break`, `continue`, `return`
- `yield` inside `if` / `when` branch bodies for branch values and early branch exit

### Pattern Matching

- Wildcard (`_`), literal, variable binding, comparison (`> n`, `<= n`)
- Struct/Pair/Enum destructuring (including nested)
- Logical patterns: `or`, `and`, `not`

### Traits and Generics

- Trait definitions with inheritance: `trait Ord Eq { ... }`
- Generic trait declarations use postfix type parameters: `trait Iterator[T Any] { ... }`
- Implementations via `given` blocks
- Trait objects for runtime polymorphism: `ref Greet`, `ref mut Greet`
- Operator overloading through algebraic traits (`Add`, `Sub`, `Mul`, `Div`, `Index`, etc.)

### Functions and Lambdas

- Top-level and generic functions
- Named parameters: `let connect(host: String, port: Int) = ...` called as `connect(host: "localhost", port: 8080)`
- Lambda expressions: `(x Int) Int -> x * 2`
- Closures with captured variables
- Literals: strings use `"..."`; rune literals use `'...'` (default `Rune`, can infer to `UInt8` in explicit byte context)
- Duration suffix literals: `10s`, `250ms`, `30min`, `2h`, `150us`, `42ns`
- Pair literal: `(a, b)` (equivalent to `Pair(a, b)`)
- Pair destructuring: `let (a, b) = pair` (binds Pair fields to separate variables)
- Collection literals:
    - List: `[1, 2, 3]` (defaults to `List[T]` when no explicit type context exists)
    - Set: `let s Set[Int] = [1, 2, 3]`
    - Dict: `["k": 1, "v": 2]`
    - Empty literal `[]` requires explicit type context (e.g. `let xs List[Int] = []`)
- String interpolation: `"value = \(x)"`
- Multiline string literals: `"""..."""` with Swift-style indentation stripping

### Memory Management

- Automatic reference counting with copy-on-write semantics
- Escape analysis for stack vs. heap allocation decisions
- Weak references (`weakref` / `weakref mut`) for breaking reference cycles
- `finally` for deterministic resource cleanup

Reference creation rules:
- `.ref` result type depends on the source's mutability: `let mut` binding → `ref mut T`, `let` binding → `ref T`, mutable path → `ref mut T`.
- `ref mut T` implicitly converts to `ref T` (widening). The reverse is not allowed.
- `.ref` on rvalues is rejected by the compiler.
- **No implicit ref promotion or auto-deref for function/method arguments.** If a function expects `ref T`, the caller must use `a.ref`. If it expects `T`, the caller must use `a.val`. This applies to all arguments, including method arguments.
- **Auto-ref and auto-deref only apply to method receivers (`self`).** `self ref` methods accept values via auto-ref; `self` methods accept `ref T` via auto-deref (following Go's pointer receiver behavior).
- Calling a `self ref` method on an rvalue can introduce hidden retain/allocation cost due to temporary materialization.
- Trait objects follow the same mutability split as ordinary refs: `ref Trait` can call only `self ref` requirements, while `ref mut Trait` can call both `self ref mut` and `self ref` requirements.
- `ref T` is read-only: `.val` read only. `ref mut T` supports `.val` read and `.val = expr` assignment.
- `ptr T` is read-only: `.val` read only. `ptr mut T` supports `.val` read, `.val = expr`, and `p[i] = expr`.
- Use `box(expr)` for owned escaping references from literals/temporaries — returns `ref mut T`.
- `box` forms the escaping reference directly from its parameter local; once that reference escapes, cleanup transfers to the ref owner instead of dropping the local again.
- Ordinary parameter `mut` is only local binding mutability inside the function body. It is not part of the function signature and is ignored for trait/given matching.
- `Drop` uses `drop(source ptr mut Self) Void`. It is a compiler-only destructor entry, and `Drop` implementations are allowed on types with composite fields.

Weak reference rules:
- `.weakref` on a `ref T` produces `weakref T`; on a `ref mut T` produces `weakref mut T`. It is only valid on ref types.
- `.to_ref()` on a `weakref T` returns `Option[ref T]`; on a `weakref mut T` returns `Option[ref mut T]`.
- `weakref mut T` implicitly converts to `weakref T` (widening).

```koral
let strong ref mut Int = box(42)
let weak weakref mut Int = strong.weakref   // ref mut → weakref mut

when weak.to_ref() in {
    .Some(r) then println(r.val),
    .None    then println("expired"),
}
```

### Module System

Module rules summary:

- `using "path"` merges another file into the current module scope.
- `using module::path { Symbol, Other as Alias }` imports explicit symbols visible to the importing file: `public` from any package, plus `protected public` when importing from the same package.
- `using module::path { .. }` imports all symbols visible to the importing file from that module, and `..` must be the only item.
- Module imports bind symbols only; they do not bind a module name or namespace. Use `Symbol`, not `module.Symbol`.
- Entry file basenames must match `[a-z][a-z0-9_]*`.

- File merge (`using "file_name"` / `using "./helpers"` / `using "../shared/format"`) is resolved relative to the current file directory
- Modules are declared in `koral.json`; `std` modules are declared in `std/koral.json`
- Top-level manifest `entry` is the default target module name (for example `app::main`), not a source file path
- Per-module dependency edges use `requires`; non-`std` packages do not need to list `std` manually
- Imports are file-local bindings and never re-export automatically
- Access control: `public`, `protected public` (same-package), `protected` (same module, default for top-level declarations), `private`
- Direct `Type(...)` construction requires constructor field visibility at call site; non-public fields should be initialized via public factory methods
- Module entry file basename must match `[a-z][a-z0-9_]*`
- String in `using "file"` is the literal file name (no case conversion); file is resolved relative to the current file's directory
- Type aliases must start with an uppercase letter (`type Name = ...`)

### FFI

- `foreign let` for binding C functions
- `foreign type` for opaque or layout-compatible C types
- Native library linking is configured in `koral.json` / `std/koral.json` via `links`, not via source syntax

## Standard Library Overview

The standard library (`std/`) ships with the compiler and is loaded automatically unless `--no-std` is specified.

Commonly used pieces:

- Core types: `Int`, `Float64`, `String`, `Rune`, `Bool`
- Collections: `List[T]`, `Dict[K, V]`, `Set[T]`
- Error flow: `Option[T]`, `Result[T]`, `or else`, `and then`, `or return`
- Runtime and system modules: `Io`, `Os`, `Proc`, `Time`, `Async`, `Sync`, `Net`
- Utility modules: `Math`, `Rand`, `Text`, `Container`

Minimal examples:

```koral
let nums List[Int] = [1, 2, 3]
let scores Dict[String, Int] = ["alice": 10, "bob": 8]

let port = Option[Int].Some(8080) or else 80
let doubled = Option[Int].Some(21) and then it * 2

let parse_port(text String) Result[Int] = {
    let port = parse_int(text) or return
    return .Ok(port)
}

let ok = Result[Int].Ok(42)
let err = Result[Int].Error(box("failed"))
```

For full module-by-module API documentation, see `docs/std/`.

## Repository Layout

- `compiler/` — Swift compiler project (`koralc`, `KoralCompiler`)
- `bootstrap/` — self-hosting compiler implementation and bootstrap tests
- `std/` — standard library modules and runtime C files
- `docs/` — language and developer documentation
- `toolchain/fmt/` — formatter implementation and tests
- `samples/` — example projects
- `test/` — ad-hoc language playground and cases

## Prerequisites

- Swift toolchain (for building `koralc`)
- A C compiler in `PATH` (`clang` recommended)

On Windows, ensure `clang.exe` is available from terminal:

```bash
clang --version
```

## Build from Source

```bash
cd compiler
swift build -c debug
```

## Run the Compiler

```bash
# Build a single source file directly
swift run koralc build hello.koral

# Build a manifest-declared target module
swift run koralc build --package-config path/to/koral.json --target-module app::main

# Build and run
swift run koralc run --package-config path/to/koral.json --target-module app::main

# Emit C only
swift run koralc emit-c --package-config path/to/koral.json --target-module app::main -o out
```

## Common Options

- `-o, --output <dir>`: output directory
- `--package-config <path>`: build from a package manifest
- `--target-module <name>`: choose the manifest target module, for example `app::main`
- `--deps-root <path>`: dependency root directory for manifest-driven builds
- `--std-config <path>`: explicit std manifest path
- `--no-std`: compile without loading the std manifest
- `-m` / `-m=<N>`: print escape analysis diagnostics (Go-style; `-m -m` or higher level currently same output)

## Test

The only supported test entry lives under `tests/`.

```bash
cd compiler
swift build -c debug
cd ..
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8
```

See [tests/README.md](tests/README.md) for bootstrap mode, custom compiler mode, and other runner flags.

## Documentation

- [Language Guide (English)](docs/document.md)
- [语言文档（中文）](docs/document-zh.md)
- [Grammar (BNF)](docs/grammar.bnf)
- [Compiler Developer Guide](docs/developer-guide.md)

## Standard Library Resolution (`KORAL_HOME`)

If `koralc` cannot find `std/std.koral` / `std/koral.json` due to your working directory, set `KORAL_HOME` to the repository root.

```bash
# macOS / Linux
export KORAL_HOME=/path/to/koral

# Windows PowerShell
$env:KORAL_HOME = "C:\path\to\koral"
```

## Contributing

Issues and pull requests are welcome. If you change parser/type-checker/codegen behavior, please add or update integration test cases under `tests/compiler-cases/`.

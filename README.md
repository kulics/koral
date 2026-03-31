# The Koral Programming Language

Koral is an experimental compiled language that combines **Go's aggressive escape analysis** with **Swift's Automatic Reference Counting (ARC)**. It targets C to deliver predictable, high-performance memory management without a garbage collector, while keeping the syntax clean and expression-oriented.

This repository contains the compiler, standard library, formatter, language documentation, and sample projects.

> Status: Koral is in an experimental stage and is not yet production-ready.

## The Core Idea: ARC + Escape Analysis

Most compiled languages make you choose: either you get high-level ergonomics with a tracing garbage collector, or you get manual control with verbose syntax. Koral offers a middle ground:

1. **Escape Analysis First**: Every allocation is analyzed at compile time. If the compiler can prove that an object does not escape its current scope, it is allocated on the stack. Stack allocation is practically free and completely bypasses ARC overhead.
2. **ARC for the Rest**: If an object *does* escape, it is allocated on the heap and managed via Automatic Reference Counting. This provides predictable, pause-free performance.

Because Koral compiles to C, stack allocations become standard C local variables. The backend compiler can heavily optimize them, often keeping them entirely in CPU registers and optimizing away reference counting operations for local data.

```koral
// The compiler sees this doesn't escape. 
// It's allocated on the stack. No ARC overhead.
let local_point = Point(1, 2)

// box(...) creates an owned reference on the heap.
let heap_point = box(Point(3, 4))

// The 'ref' keyword borrows from an existing mutable lvalue.
let mut local_point2 = Point(3, 4)
let heap_point_ref = ref local_point2

// Bumping the refcount, no deep copy
let shared_point = heap_point 
```

## Language Highlights

- **No GC, No Manual `free`**: Automatic memory management based on reference counting and escape analysis.
- **Expression-Oriented**: `if`, `when`, `while`, and blocks all produce values.
- **Zero-Cost Abstractions**: Generics with trait constraints and monomorphization.
- **Algebraic Data Types**: Structs and unions with exhaustive pattern matching.
- **C Interop**: Foreign function interface (FFI) and a C backend for broad platform compatibility.

## Syntax Quick Tour

### Everything is an expression

```koral
let sign = if x > 0 then 1 else if x < 0 then -1 else 0

let label = when status in {
    .Active then "running",
    .Paused(reason) then "paused: " + reason,
    .Stopped then "done",
}
```

### Pattern matching built into `if` and `while`

```koral
if config.get("port") is .Some(v) then start_server(v)

while iter.next() is .Some(item) then process(item)
```

You can chain multiple condition clauses with `;`.
Each clause runs only if previous clauses succeed, and bindings from earlier `is` clauses are visible to later clauses.

```koral
if load() is .Some(a); parse(a) is .Ok(b); b.is_valid() then use(b)

while source.next() is .Some(raw); decode(raw) is .Ok(msg) then handle(msg)
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

let name = user and then _.profile and then _.display_name or else "anonymous"

let read_config(path String) [Config]Result = {
    let text = read_text_file(path) or return
    let parsed = parse_json(text) or return
    .Ok(parsed)
}
```

### Prefix generics

```koral
let nums = [Int]List.new()
let scores = [String, Int]Map.new()
let [T Ord]max(a T, b T) T = if a > b then a else b
```

### Traits and `given` blocks

```koral
trait Greet {
    greet(self) String
}

type Bot(name String)

given Bot {
    public greet(self) String = "beep boop, I'm " + self.name
}

let g Greet ref = box(Bot("K-9"))  // trait object
```

### Algebraic data types with implicit member syntax

```koral
type [T Any]Result {
    Ok(value T),
    Error(error Error ref),
}

let parse_int(s String) [Int]Result =
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
- Unions (sum types / tagged enums): `type Shape { Circle(r Float64), Rectangle(w Float64, h Float64) }`
- Type aliases: `type Name = TargetType`
- Generic types and functions: `[T Ord]`, `[K Hash, V Any]`
- Function types: `[Int, Int, Int]Func` — `(Int, Int) -> Int`
- Reference types: `ref`, `ptr`, `weakref`

### Control Flow

- `if / then / else` expressions (with pattern matching via `is`)
- `while` loops (with pattern matching via `is`)
- `for` loops over any `Iterable`
- `when` expressions for exhaustive pattern matching
- `finally` for deterministic cleanup
- `break`, `continue`, `return`, `yield`

### Pattern Matching

- Wildcard (`_`), literal, variable binding, comparison (`> n`, `<= n`)
- Struct/Pair/union destructuring (including nested)
- Logical patterns: `or`, `and`, `not`

### Traits and Generics

- Trait definitions with inheritance: `trait Ord Eq { ... }`
- Generic trait declarations use prefix generic syntax: `trait [T Any]Iterator { ... }`
- Implementations via `given` blocks
- Trait objects for runtime polymorphism: `Greet ref`
- Operator overloading through algebraic traits (`Add`, `Sub`, `Mul`, `Div`, `Index`, etc.)

### Functions and Lambdas

- Top-level and generic functions
- Lambda expressions: `(x Int) Int -> x * 2`
- Closures with captured variables
- Literals: strings use `"..."`; rune literals use `'...'` (default `Rune`, can infer to `UInt8` in explicit byte context)
- Duration suffix literals: `10s`, `250ms`, `30min`, `2h`, `150us`, `42ns`
- Pair literal: `(a, b)` (equivalent to `Pair(a, b)`)
- Pair destructuring: `let (a, b) = pair` (binds Pair fields to separate variables)
- Collection literals:
    - List: `[1, 2, 3]` (defaults to `[T]List` when no explicit type context exists)
    - Set: `let s [Int]Set = [1, 2, 3]`
    - Map: `["k": 1, "v": 2]`
    - Empty literal `[]` requires explicit type context (e.g. `let xs [Int]List = []`)
- String interpolation: `"value = \(x)"`
- Multiline string literals: `"""..."""` with Swift-style indentation stripping

### Memory Management

- Automatic reference counting with copy-on-write semantics
- Escape analysis for stack vs. heap allocation decisions
- Weak references (`weakref`) for breaking reference cycles
- `finally` for deterministic resource cleanup

Reference creation rules (current semantics):
- `ref x` requires `x` to be a mutable lvalue (`let mut` binding or reachable mutable field).
- `ref` on immutable bindings or rvalues is rejected by the compiler.
- `deref` on `T ref` is read-only. Deref assignment (`deref x = v`) is only allowed on pointer types (`T ptr`).
- Use `box(expr)` for owned heap references from literals/temporaries (e.g. `box(42)`, `box(Point(1,2))`).

### Module System

- File merge (`using "file_name"`) — merges file contents into current module, sharing `protected` visibility
- Submodule declaration (`public using "file_name" as Name`) — registers a named submodule
- External imports (`using Std.Io`, `using Super.Sibling`)
- Member imports (`using Std.Io.Reader`)
- Alias imports (`using Std.Io as Io`)
- Batch imports (`using Std.Io.*`)
- Access control: `public`, `protected` (default), `private`
- Direct `Type(...)` construction requires constructor field visibility at call site; non-public fields should be initialized via public factory methods
- Submodule entry file must match directory name: `foo/foo.koral` (not `foo/index.koral`)
- Module entry file basename must match `[a-z][a-z0-9_]*`
- String in `using "file"` is the literal file name (no case conversion); file is resolved relative to the current file's directory
- In std submodules, symbols declared as `public` in root `Std` are default-visible; no redundant `using Std.X` is required for those root exports
- `using path as alias` follows first-letter case matching: uppercase target -> uppercase alias, lowercase target -> lowercase alias
- Type aliases must start with an uppercase letter (`type Name = ...`)

### FFI

- `foreign let` for binding C functions
- `foreign type` for opaque or layout-compatible C types
- `foreign using "lib"` for linking external libraries

## Standard Library Overview

The standard library (`std/`) ships with the compiler and is loaded automatically unless `--no-std` is specified.

Commonly used pieces:

- Core types: `Int`, `Float64`, `String`, `Rune`, `Bool`
- Collections: `[T]List`, `[K, V]Map`, `[T]Set`
- Error flow: `[T]Option`, `[T]Result`, `or else`, `and then`, `or return`
- Runtime and system modules: `Io`, `Os`, `Proc`, `Time`, `Async`, `Sync`, `Net`
- Utility modules: `Math`, `Rand`, `Text`, `Container`

Minimal examples:

```koral
let nums [Int]List = [1, 2, 3]
let scores [String, Int]Map = ["alice": 10, "bob": 8]

let port = [Int]Option.Some(8080) or else 80
let doubled = [Int]Option.Some(21) and then _ * 2

let parse_port(text String) [Int]Result = {
    let port = parse_int(text) or return
    .Ok(port)
}

let ok = [Int]Result.Ok(42)
let err = [Int]Result.Error(box("failed"))
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
# Build (default command)
swift run koralc path/to/file.koral

# Build and run
swift run koralc run path/to/file.koral

# Emit C only
swift run koralc emit-c path/to/file.koral -o out
```

## Common Options

- `-o, --output <dir>`: output directory (default: input file directory)
- `--no-std`: compile without loading `std/std.koral`
- `-m` / `-m=<N>`: print escape analysis diagnostics (Go-style; `-m -m` or higher level currently same output)

## Test

Run in `compiler/`:

```bash
swift build -c debug
swift test --disable-swift-testing --enable-xctest --parallel
```

## Documentation

- [Language Guide (English)](docs/document.md)
- [语言文档（中文）](docs/document-zh.md)
- [Grammar (BNF)](docs/grammar.bnf)
- [Compiler Developer Guide](docs/developer-guide.md)

## Standard Library Resolution (`KORAL_HOME`)

If `koralc` cannot find `std/std.koral` due to your working directory, set `KORAL_HOME` to the repository root.

```bash
# macOS / Linux
export KORAL_HOME=/path/to/koral

# Windows PowerShell
$env:KORAL_HOME = "C:\path\to\koral"
```

## Contributing

Issues and pull requests are welcome. If you change parser/type-checker/codegen behavior, please add or update integration test cases under `compiler/Tests/Cases/`.

# The Koral Programming Language

Koral is an open-source programming language focused on performance, readability, and practical cross-platform development.

This repository contains the compiler, standard library, formatter, language documentation, and sample projects.

> Status: Koral is in an experimental stage and is not yet production-ready.

## Highlights

- Modern, easy-to-scan syntax with optional semicolons and expression-oriented design.
- Automatic memory management based on reference counting, ownership analysis, and escape analysis.
- Generics with trait constraints and monomorphization for zero-cost abstraction.
- Algebraic data types (structs and unions) with exhaustive pattern matching.
- Trait-based polymorphism with trait objects for runtime dispatch.
- First-class functions, lambdas, and closures.
- Multi-paradigm support (imperative + functional style).
- Module system with access control (`public` / `protected` / `private`).
- Foreign function interface (FFI) for seamless C interop.
- C backend for broad platform compatibility.

## Language Capabilities

### Type System

- Primitive types: `Bool`, `Int`, `UInt`, `Int8`–`Int64`, `UInt8`–`UInt64`, `Float32`, `Float64`, `Never`
- Structs (product types): `type Point(x Int, y Int)`
- Unions (sum types / tagged enums): `type Shape { Circle(r Float64), Rectangle(w Float64, h Float64) }`
- Type aliases: `type Name = TargetType`
- Generic types and functions: `[T Ord]`, `[K Hashable, V Any]`
- Function types: `[Int, Int, Int]Func` — `(Int, Int) -> Int`
- Reference types: `ref`, `ptr`, `weakref`

### Control Flow

- `if / then / else` expressions (with pattern matching via `is`)
- `while` loops (with pattern matching via `is`)
- `for` loops over any `Iterable`
- `when` expressions for exhaustive pattern matching
- `defer` for deterministic cleanup
- `break`, `continue`, `return`, `yield`

### Pattern Matching

- Wildcard (`_`), literal, variable binding, comparison (`> n`, `<= n`)
- Struct and union destructuring (including nested)
- Logical patterns: `or`, `and`, `not`

### Traits and Generics

- Trait definitions with inheritance: `trait Ord Eq { ... }`
- Implementations via `given` blocks
- Trait objects for runtime polymorphism: `Greet ref`
- Operator overloading through algebraic traits (`Add`, `Sub`, `Mul`, `Div`, `Index`, etc.)

### Functions and Lambdas

- Top-level and generic functions
- Lambda expressions: `(x Int) Int -> x * 2`
- Closures with captured variables
- String interpolation: `"value = \(x)"`

### Memory Management

- Automatic reference counting with copy-on-write semantics
- Escape analysis for stack vs. heap allocation decisions
- Weak references (`weakref`) for breaking reference cycles
- `defer` for deterministic resource cleanup

### Module System

- File merging (`using "file"`)
- Submodule imports (`using self.sub`)
- External package imports (`using pkg.mod`)
- Batch imports (`using pkg.mod.*`)
- Access control: `public`, `protected` (default), `private`

### FFI

- `foreign let` for binding C functions
- `foreign type` for opaque or layout-compatible C types
- `foreign using "lib"` for linking external libraries

## Standard Library Overview

The standard library (`std/`) ships with the compiler and is loaded automatically unless `--no-std` is specified.

| Module | Description |
|---|---|
| **Core types** | `Bool`, `Int`, `UInt`, `Float32`, `Float64`, `String`, `Rune` |
| **Option / Result** | `[T]Option` (Some/None), `[T]Result` (Ok/Error) with `or else` / `and then` chaining |
| **Collections** | `[T]List`, `[K,V]Map`, `[T]Set` — dynamic array, hash map, hash set |
| **Range** | `[T]Range` with 9 interval variants (closed, open, half-open, from, to, full) |
| **Stream** | Lazy iterator API — `filter`, `map`, `flat_map`, `fold`, `zip`, `take`, `skip`, … |
| **Traits** | `Eq`, `Ord`, `Hashable`, `ToString`, `Iterator`, `Iterable`, `Error`, `Add`/`Sub`/`Mul`/`Div`/`Rem`, `Index`/`MutIndex`, `Scale`, `Affine` |
| **IO** | `print`, `println`, `readln`, `panic`, `assert`, `args()` |
| **IO (submodule)** | `Buffer`, `BufReader`, `BufWriter`, `Reader`/`Writer` traits, `IoError`, `SeekPos` |
| **OS** | `File`, `FileInfo`, `DirEntry`, directory/path/environment operations |
| **Command** | `Command` builder, `Process`, `ExitStatus`, `CommandOutput`, I/O redirection |
| **Time** | `Duration`, `MonoTime`, `DateTime`, `TimeZone`, `sleep` |
| **Math** | Trigonometric, logarithmic, power, rounding functions; `FloatingPoint`, `Integer`, `Natural` traits |
| **Convert** | `Parseable`, `Formattable`, `RadixParseable` traits; `parse`, `format` functions |
| **Regex** | `Regex`, `Match`, `Captures`, `RegexFlag` |
| **Random** | `RandomSource`, `Randomizable`, `DefaultRandomSource`, `Random` |
| **Net** | `TcpListener`, `TcpSocket`, `UdpSocket`, `IpAddr`, `SocketAddr` |
| **Sync** | `Mutex`, `SharedMutex`, `Channel`, `Barrier`, `Semaphore`, `Lazy`, `Atomic` |
| **Task** | `Thread`, `Task`, `Timer`, `run_task` |

## Repository Layout

- `compiler/` — Swift compiler project (`koralc`, `KoralCompiler`)
- `std/` — standard library modules and runtime C files
- `docs/` — language and developer documentation
- `fmt/` — formatter implementation and tests
- `samples/` — example projects

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
- `--escape-analysis-report`: print escape analysis diagnostics

## Test

Run in `compiler/`:

```bash
swift build -c debug
swift test
```

## Documentation

- [Language Guide (English)](docs/document.md)
- [语言文档（中文）](docs/document-zh.md)
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

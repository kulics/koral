# The Koral Programming Language

Koral is an experimental compiled language that uses a **simplified type system** (`type` / `type mutable`). It targets C to deliver predictable, high-performance compilation without a garbage collector, while keeping the syntax clean and its core control flow expression-oriented.

This repository contains the compiler, standard library, formatter, language documentation, and sample projects.

> Status: Koral is in an experimental stage and is not yet production-ready.

Reference note:

- `README.md` is a high-level overview, not the canonical grammar document.
- For syntax-sensitive details, use `docs/grammar.bnf` together with the language reference in `docs/document.md` and `docs/document-zh.md`.
- When implementation and docs drift, resolve the mismatch by updating the implementation and/or the documents so they converge.

## The Core Idea: `type` / `type mutable`

Koral's type system distinguishes between two kinds of composite types:

- **`type`** (immutable): An immutable value type. The compiler decides the internal layout. Fields cannot be mutated after construction.
- **`type mutable`** (mutable): A mutable object type with shared semantics. Fields are immutable by default; individual fields can be declared `mutable` to allow in-place mutation through shared references.

```koral
// Immutable value type — compiler decides layout.
type Point(x Int, y Int);

// Mutable shared object.
type mutable Counter(mutable count Int);

let p = Point(1, 2);
let c = Counter(0);
c.count = c.count + 1;  // in-place mutation through shared reference
```

## Language Highlights

- **No GC, No Manual `free`**: Automatic memory management based on `type` / `type mutable` semantics.
- **Expression-Oriented Control Flow**: `if`, `when`, `while`, and `for` share the same expression surface syntax; `if` and `when` may produce branch values, while `while` and `for` always produce `Void`.
- **Zero-Cost Abstractions**: Generics with trait constraints and monomorphization.
- **Algebraic Data Types**: Structs and enums with exhaustive pattern matching.
- **C Interop**: Foreign function interface (FFI) and a C backend for broad platform compatibility.

## Syntax Quick Tour

### Expression-oriented core control flow

```koral
let sign = if x > 0 then 1 else if x < 0 then -1 else 0;

let label = when status in {
    .Active then "running",
    .Paused(reason) then "paused: " + reason,
    .Stopped then "done",
}
```

Blocks are also expressions, so branch bodies can stay local instead of forcing helper functions. In expression-form `if`/`when`, a block branch still defaults to `Void`; use `yield expression` to produce the enclosing expression's value from inside the block.

```koral
let label = if score >= 90 then {
    if score == 100 then {
        yield "perfect";
    }
    yield "A";
} else {
    yield "other";
}
```

`while` and `for` intentionally keep the same `... then ...` surface shape, but they are statements rather than value-producing expressions.

### Pattern matching built into `if` and `while`

Rules:

- `is` may destructure directly inside `if` and `while` conditions.
- Bound names from an earlier `is` clause remain visible to later `and` clauses.
- Condition chains evaluate left-to-right with normal short-circuit behavior.

```koral
if config.get("port") is .Some(v) then start_server(v);

while iter.next() is .Some(item) then process(item);
```

You can chain multiple condition clauses with `and`.
Each clause runs only if previous clauses succeed, and bindings from earlier `is` clauses are visible to later clauses.

```koral
if load() is .Some(a) and parse(a) is .Ok(b) and b.is_valid() then use(b);

while source.next() is .Some(raw) and decode(raw) is .Ok(msg) then handle(msg);
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
let port = config.get("port") or else 8080;

let name = (user and then it.profile and then it.display_name) or else "anonymous";

let read_config(path String) Result[Config] = {
    let text = read_text_file(path) or return;
    let parsed = parse_json(text) or return;
    return .Ok(parsed);
}
```

### Generics

```koral
let nums = List[Int].new();
let scores = Dict[String, Int].new();
let max[T Ord](a T, b T) T = if a > b then a else b;
```

### Traits and `given` blocks

```koral
trait Greet {
    greet(self) String;
}

type Bot(name String);

given Bot as Greet {
    greet(self) String = "beep boop, I'm " + self.name;
}

let g Greet = Bot("K-9");  // trait object
```

### Algebraic data types with implicit member syntax

Rules:

- `.Member(...)` requires an expected type from context.
- It may construct enum cases or call static methods.
- If the expected type is not known, the expression is rejected.

```koral
type Result[T Any] {
    Ok(value T),
    Error(error Error),
}

let parse_int(s String) Result[Int] =
    if s == "42" then .Ok(42) else .Error("bad input");
```

### Lazy streams

```koral
let result = list.iterator();
    .filter((x) -> x > 0);
    .map((x) -> x * 2);
    .take(10);
    .fold(0, (acc, x) -> acc + x);
```

## Language Capabilities

### Type System

- Primitive types: `Bool`, `Int`, `UInt`, `Int8`–`Int64`, `UInt8`–`UInt64`, `Float32`, `Float64`, `Never`
- Structs (product types): `type Point(x Int, y Int)`
- Enums (sum types / tagged enums): `type Shape { Circle(r Float64), Rectangle(w Float64, h Float64) }`
- Type aliases: `type Name = TargetType`
- Generic types and functions: `Type[T]`, `func[T Constraint](...)`
- Function types: `Func(Int, Int) Int` — `(Int, Int) -> Int`
- Type mutability: `type` (immutable value semantics), `type mutable` (shared object semantics)

### Control Flow

- `if / then / else` expressions (with pattern matching via `is`)
- `while` statements (with pattern matching via `is`)
- `for` statements over any `Iterable`
- `when` expressions/statements for exhaustive pattern matching
- `defer` for deterministic cleanup
- `break`, `continue`, `return`, `yield`
- `yield expression` inside the nearest value-producing `if` / `when` branch body for branch values and early branch exit

### Pattern Matching

- Wildcard (`_`), literal, variable binding, comparison (`> n`, `<= n`)
- Struct/Pair/Enum destructuring (including nested)
- Logical patterns: `or`, `and`, `not`

### Traits and Generics

- Trait definitions with inheritance: `trait Ord Eq { ... }`
- Generic trait declarations use postfix type parameters: `trait Iterator[T Any] { ... }`
- Implementations via `given` blocks
- Trait objects for runtime polymorphism: `Greet`
- Operator overloading through algebraic traits (`Add`, `Sub`, `Neg`, `Mul`, `Div`, `Rem`, `Eq`, `Ord`)

### Functions and Lambdas

- Top-level and generic functions
- Constructor labels and default-fill: `type Point(x Int, y Int)` constructed as `Point(x: 1, y: 2)` or `Point(x: 1, ...)`; ordinary static methods remain positional-only
- Lambda expressions: `(x Int) Int -> x * 2`
- Closures with captured variables
- Literals: strings use `"..."`; rune literals use `'...'` (default `Rune`, can infer to `UInt8` in explicit byte context)
- Duration suffix literals: `10s`, `250ms`, `150us`, `42ns`
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

- `type` values are immutable. The compiler decides the internal layout.
- `type mutable` values are mutable shared objects.
- `defer` for deterministic resource cleanup.

```koral
// Immutable value — compiler decides representation.
let p = Point(1, 2);

// Mutable shared object.
type mutable Counter(mutable count Int);
let c = Counter(0);
c.count = c.count + 1;
```

### Module System

Module rules summary:

- `using "path"` merges another file into the current module scope.
- `using module::path { Symbol, Other as Alias }` imports explicit symbols visible to the importing file: `public` from any package, plus `package_private` when importing from the same package.
- `using module::path { .. }` imports all symbols visible to the importing file from that module, and `..` must be the only item.
- Module imports bind symbols only; they do not bind a module name or namespace. Use `Symbol`, not `module.Symbol`.
- Entry file basenames must match `[a-z][a-z0-9_]*`.

- File merge (`using "file_name"` / `using "./helpers"` / `using "../shared/format"`) is resolved relative to the current file directory
- Modules are declared in `koral.json`; `std` modules are declared in `std/koral.json`
- Top-level manifest `entry` is the default target module name (for example `app::main`), not a source file path
- Per-module dependency edges use `requires`; non-`std` packages do not need to list `std` manually
- Imports are file-local bindings and never re-export automatically
- Access control: `public`, `package_private` (same-package), `module_private` (same module, default for top-level declarations), `file_private`
- Direct `Type(...)` construction requires constructor field visibility at call site; non-public fields should be initialized via public factory methods
- Module entry file basename must match `[a-z][a-z0-9_]*`
- String in `using "file"` is the literal file name (no case conversion); file is resolved relative to the current file's directory
- Type aliases must start with an uppercase letter (`type Name = ...`)

### FFI

- `foreign let` for binding C functions
- `foreign type` for opaque or layout-compatible C types
- Native library linking is configured in `koral.json` / `std/koral.json` via `links`, not via source syntax
- Raw pointers: `*unsafe T` (read-only), `*unsafe mutable T` (read-write); formed with `&unsafe` / `&unsafe mutable`
- Weak references: `?T` (requires `mutable` constraint); `downgrade(T)` / `upgrade(?T)`

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
let nums List[Int] = [1, 2, 3];
let scores Dict[String, Int] = ["alice": 10, "bob": 8];

let port = Option[Int].Some(8080) or else 80;
let doubled = Option[Int].Some(21) and then it * 2;

let parse_port(text String) Result[Int] = {
    let port = parse_int(text) or return;
    return .Ok(port);
}

let ok = Result[Int].Ok(42);
let err = Result[Int].Error("failed");
```

## Documentation

- [Language Guide (English)](docs/document.md)
- [语言文档（中文）](docs/document-zh.md)
- [Grammar (BNF)](docs/grammar.bnf)
- [Standard Library API Docs](docs/std/)
- [Compiler Developer Guide](docs/developer-guide.md)

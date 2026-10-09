# The Koral Programming Language

Koral is an experimental compiled language that uses a **simplified type system** (`type` / `type mutable`). It targets C to deliver predictable, high-performance compilation without a garbage collector, while keeping the syntax clean and its core control flow expression-oriented.

This repository contains two compiler implementations — `compiler/`, the self-hosting primary implementation, and `compiler-reference/`, the frozen Swift compiler serving as reference oracle, build seed, and backup — plus the standard library, formatter, language documentation, and sample projects.

> Status: Koral is in an experimental stage and is not yet production-ready.

Reference note:

- `README.md` is a high-level overview, not the canonical grammar document.
- For syntax-sensitive details, use `docs/guide/grammar.bnf` together with the language reference in `docs/guide/document.md` and `docs/guide/document-zh.md`.
- When implementation and docs drift, resolve the mismatch by updating the implementation and/or the documents so they converge.

## The Core Idea: `type` / `type mutable`

Koral's nominal types come in exactly two forms, chosen at the declaration site:

- **`type`** — a shallowly immutable nominal type. Fields cannot be mutated after construction, values have **no identity**, and the compiler decides the layout. **Value semantics is not promised**: copies may share backing storage, which is unobservable precisely because the type is shallowly immutable. A type that implements `Drop` is the exception — its destructor runs once per object, so the sharing is observable and the type is treated like `type mutable` on that axis.
- **`type mutable`** — a shared object type. Assignment and argument passing hand out handles to the **same** object. Fields are immutable by default; only explicitly declared `mutable` fields can be modified in place.

```koral
// Shallowly immutable — compiler decides layout.
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
    .Active() then "running",
    .Paused(reason) then "paused: " + reason,
    .Stopped() then "done",
};
```

Blocks are also expressions, so branch bodies can stay local instead of forcing helper functions. A block may end with a final expression without a trailing semicolon; that final expression becomes the block's value. If the block has no final expression, or the last expression ends with a semicolon, the block evaluates to `Void`.

```koral
let label = if score >= 90 then {
    if score == 100 then {
        "perfect"
    } else {
        "A"
    }
} else {
    "other"
};
```

`while` and `for` intentionally keep the same `... then ...` surface shape and are ordinary expressions whose result type is `Void`.

```koral
let loop_value = while ready() then {
    process_next();
};
```

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
};
```

### `or else` / `and then` / `or return` — Error flow as keywords

```koral
let port = config.get("port") or else 8080;

let name = (user and then it.profile and then it.display_name) or else "anonymous";

let read_config(path String) Result[Config] = {
    let text = read_text_file(path) or return;
    let parsed = parse_json(text) or return;
    return .Ok(parsed);
};
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
};

type Bot(name String);

given Bot as Greet {
    greet(self) String = "beep boop, I'm " + self.name;
};

let g Greet = Bot("K-9");  // trait object

// Fully qualified call (Rust-style `<Type as Trait>::method`) selects the
// trait's method explicitly. The receiver of an instance method is the first
// argument, so instance and static trait methods share one form.
let bot = Bot("R2");
println(Bot(Greet).greet(bot));
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
};

let parse_int(s String) Result[Int] =
    if s == "42" then .Ok(42) else .Error("bad input");
```

### Lazy streams

A chain is one expression — the calls are joined by the leading `.`, and the
statement ends at the single trailing `;`. Do not put `;` between the calls;
that would terminate the statement and leave the next line as a bare implicit
member expression.

```koral
let result = list.iterator()
    .filter((x) -> x > 0)
    .map((x) -> x * 2)
    .take(10)
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
- Type mutability: `type` (shallowly immutable, no identity, no promise of value semantics), `type mutable` (shared object semantics)

### Control Flow

- `if / then / else` expressions (with pattern matching via `is`)
- `while` expressions (with pattern matching via `is`)
- `for` expressions over any `Iterable`
- `when` expressions for exhaustive pattern matching
- `defer` for deterministic cleanup
- `break`, `continue`, `return`
- Value-producing `if` / `when`: the branch's final expression becomes the branch value

### Pattern Matching

- Wildcard (`_`), literal, variable binding, comparison (`> n`, `<= n`)
- Struct/Enum destructuring and tuple destructuring (including nested)
- Logical patterns: `or`, `and`, `not`

### Traits and Generics

- Trait definitions with inheritance: `trait Ord Eq { ... }`
- Generic trait declarations use postfix type parameters: `trait Iterator[T Any] { ... }`
- Implementations via `given` blocks
- Trait objects for runtime polymorphism: `Greet`
- Fully qualified calls: `Type(Trait).method(receiver, ...)` — Rust-style qualified path, with the receiver as the first argument
- Operator overloading through algebraic traits (`Add`, `Sub`, `Neg`, `Mul`, `Div`, `Rem`, `Eq`, `Ord`)

### Functions and Lambdas

- Top-level and generic functions
- Call labels and defaults: the declaration fixes the call shape with no optional-label form — a positional parameter (`name Type`) is passed by position and never by label, a named parameter (`name: Type`) must be passed by label, and only named parameters may declare defaults (`name: Int = 1`). Positional parameters must come before named ones, at declarations and at call sites. Constructors, free functions, methods and static methods all follow the same rules
- Lambda expressions: `(x Int) Int -> x * 2`
- Closures with captured variables
- Literals: strings use `"..."`; rune literals use `'...'` (default `Rune`, can infer to `UInt8` in explicit byte context)
- Duration suffix literals: `10s`, `250ms`, `150us`, `42ns`
- Tuple destructuring: `let (a, b, c) = s` binds a struct's fields by position (any field count; `Pair` is just a two-field struct). There is no tuple literal — build a `Pair` with its constructor.
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

- `using` has one form; the specifier is a string, and its **shape** decides what it means: starting with `./` or `../` is a **file merge**, anything else is a **module import**.
- File merge (`using "./helpers.koral";` / `using "../shared/format.koral";`) resolves against the current file's directory, must end in `.koral`, and merges the target's top-level definitions into the current module. It takes no part in package/module resolution and may not be combined with `{ ... }`.
- Module import (`using "std/io";` / `using "std/io" { Reader, Writer };` / `using "std/io" { Reader as IoReader };`) binds symbols only. `{ ... }` omitted means every visible member; if written, it may not be empty — `{ .. }` and `{ * }` are no longer spellings of anything.
- Module imports do not bind a module name or namespace. Use `Symbol`, not `module.Symbol`; `as` renames one imported symbol, never the module.
- Imported names are file-local bindings and are never re-exported; a name collision is an error and `as` disambiguates.
- Modules are declared in `koral.json`; `std` modules are declared in `std/koral.json`. `modules` maps a package-internal name (`.`, `conn`, `compiler/parser`) to `{ entry, links }`, and `entry` is the entry **file** relative to the package root.
- The module graph is the union of the modules' `using` statements. There is no `requires` and no top-level `entry` — the default build target is the main module.
- Module full names are `package[/subpath]`; a package name is a single identifier segment. `/` separates subpaths.
- The `std` main module is the prelude and is in scope without being named; every other module needs an explicit import.
- Imports are file-local bindings and never re-export automatically
- Access control: `public`, `package_private` (same-package), `module_private` (same module, default for top-level declarations), `file_private`
- Direct `Type(...)` construction requires constructor field visibility at call site; non-public fields should be initialized via public factory methods
- A module entry file's stem must start with a lowercase letter and continue with lowercase letters, digits or `_`
- Type aliases must start with an uppercase letter (`type Name = ...`)

### FFI

Declaration qualifiers sit **immediately after the keyword** — the slot `type mutable` and `let mutable` occupy. Access modifiers are the only prefix modifiers: they say who can see a declaration, not what kind of thing it is.

- `let foreign` for binding C functions
- `type foreign` for opaque or layout-compatible C types
- `let intrinsic` / `type intrinsic` for declarations built into the compiler (standard library only)
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
};

let ok = Result[Int].Ok(42);
let err = Result[Int].Error("failed");
```

## Repository layout

Two compiler implementations live here, and they are not equal:

- **`compiler/`** — the primary compiler implementation, written in Koral and self-hosting. **This is what you develop.**
- **`compiler-reference/`** — the **frozen** Swift compiler, kept as the reference oracle (the differential gate compares the two), the build seed (it builds `compiler/` from source), and a backup.

Deleting the frozen reference would trade the strongest cross-check in the repo for the weakest: a self-host fixed point proves a compiler is stable under its own output, not that it is right. See [Compiler roles](docs/implementation/developer-guide.md#compiler-roles) for when it may be touched.

- `std/` — standard library sources and runtime C files
- `tests/` — shared integration cases and the shared test runner
- `toolchain/` — `koral` build tool, `koral-syntax` (the shared Koral parser/printer), `koralfmt` formatter, std API doc generator, VS Code extension
- `samples/` — sample programs
- `docs/` — documentation, split by audience into `guide/`, `api/`, `design/`, `implementation/`. Start at [`docs/README.md`](docs/README.md).

## Documentation

Everything under `docs/` is organised by audience — see the [documentation map](docs/README.md) for where each kind of document lives.

- [Language Guide (English)](docs/guide/document.md)
- [语言文档（中文）](docs/guide/document-zh.md)
- [Grammar (BNF)](docs/guide/grammar.bnf) — normative
- [Standard Library API Docs](docs/api/std/) — generated
- [Design Documents](docs/design/)
- [Compiler Developer Guide](docs/implementation/developer-guide.md)

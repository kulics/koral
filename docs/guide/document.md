# The Koral Programming Language

Koral is an open-source programming language focused on performance, readability, and practical cross-platform development.

Through carefully designed syntax rules, this language can effectively reduce reading and writing burden, allowing you to put your real attention on solving problems.

Specification note:

- This document is the user-facing language reference.
- For grammar-sensitive questions, read this document together with `docs/guide/grammar.bnf`.
- If examples in this document, the BNF, and the implementation disagree, update the implementation and/or the documents so they converge.

This manual is ordered the way the language is learned: **language basics**, then **control flow**, then **custom types**, then **pattern matching**, then **abstraction**, and finally **external interop**.

## Overview

### Key Features

- Modern, easy-to-scan syntax with explicit semicolons and expression-oriented control flow: `if`, `when`, `while`, and `for` all use expression-form surface syntax. `if` and `when` may produce values; `while` and `for` always produce `Void`.
- Automatic memory management driven by declaration-site type semantics: shallowly immutable `type` versus shared `type mutable` objects. Layout and lifetime details are owned by the compiler.
- Concurrency safety declared at the type site: the `sendable` family marks which types may cross threads, safe `sendable mutable` objects carry built-in locking — one short lock per field access, not reentrant and never needing to be — and the checks live at declaration and formation sites. Cross-thread collection data is copied, not moved: `to_frozen_list()` and friends bulk-copy into independent `type unsafe sendable mutable` snapshot storage with a construction-then-read-only promise; the source stays usable, and `to_list()` copies back.
- Generics with trait constraints and monomorphization for zero-cost abstraction.
- Algebraic data types (structs and enums) with exhaustive pattern matching.
- Trait-based polymorphism with trait objects for runtime dispatch.
- First-class functions, lambdas, and closures.
- Multi-paradigm programming (combining functional and imperative).
- Module system with access control (`private` / `internal` / `protected` / `public`).
- Foreign function interface (FFI) for seamless C interop.
- C backend for broad platform compatibility.

### The Core Idea: `type` / `type mutable`

Koral's nominal types come in two mutability forms, chosen at the declaration site. Everything else in the language — aliasing, mutation and layout — follows from this one decision. A separate `sendable` axis governs cross-thread sharing (see [Concurrency](#concurrency)) — it composes with both forms and never alters them.

**`type` — a shallowly immutable nominal type.**

- Fields cannot be mutated after construction, and a `mutable` field cannot be declared.
- Values have **no identity**: two values with equal fields are interchangeable.
- The **layout is chosen by the compiler**. Inline storage, hidden indirection and shared backing are all implementation details and may differ from release to release.
- **Value semantics is not part of the language contract.** Copying, argument passing and storage may share backing storage. That sharing is unobservable precisely because the type is shallowly immutable — so the compiler is free to optimize it away.
- **A `type` cannot implement `Drop`.** A `type` promises no identity — same-field values are interchangeable — and a destructor would leak construction identity through the drop count. Cleanup is the synthesized field release instead; types that need a destructor declare `type mutable`; see [`Drop`](#drop).

**`type mutable` — a shared object type.**

- Values have identity: assignment and argument passing hand out handles to the **same** object.
- Fields are immutable by default; only explicitly declared `mutable` fields may be modified in place, and only through the shared handle.

```koral
type Point(x: Int, y: Int);

type mutable Counter(mutable value: Int, id: UInt);

let p = Point(1, 2);
// p.x = 3;      // error: Point is `type`, its fields are immutable

let c = Counter(0, 1);
c.value = 5;      // ok: Counter is `type mutable` and `value` is a mutable field
// c.id = 2;     // error: `id` is not a mutable field
```

The compiler may use reference counting and hidden storage internally for either form. Those choices are not user-visible semantics: the language contract is `type` versus `type mutable`, never a managed-reference syntax. Cleanup follows the same line — a `type` is cleaned up by its synthesized field release, and only a `type mutable` may implement `Drop`.

### Installation and Usage

`Koral` currently compiles to C and invokes `clang` in the backend, so `clang` must be available in `PATH`.

#### Compilation and Execution

You can compile either a single source file directly or a manifest-declared module graph.

1.  **Build a single file**:
    ```bash
    koralc build hello.koral;
    ```
2.  **Build a manifest-declared target module**:
    ```bash
    koralc build --package-config koral.json --target-module app;
    ```
3.  **Type-check only**:
    ```bash
    koralc check --package-config koral.json --target-module app;
    ```
4.  **Compile and run**: Use the `run` command to compile and execute in one step.
    ```bash
    koralc run --package-config koral.json --target-module app;
    ```
5.  **Emit C only**: Use `emit-c` to generate C source.
    ```bash
    koralc emit-c --package-config koral.json --target-module app -o out;
    ```

Common options:

- `-o, --output <dir>`: output directory
- `--package-config <path>`: build from a package manifest
- `--target-module <full name>`: choose the target module (`package[/subpath]`); defaults to the main module
- `--requires-root <path>`: dependency root for manifest-driven builds
- `--std-config <path>`: explicit std manifest path
- `--no-std`: compile without loading modules declared by `std/koral.json`

## 1. Language Basics

### Program Structure

#### Statements and Semicolons

In Koral, statements are the smallest unit of composition.

Statement termination rules:

- Every statement and declaration must end with a semicolon `;`.
- `}` is not a statement terminator; it is part of block, type, trait, and given syntax.
- Newlines have no semantic significance.
- There is no automatic semicolon insertion (ASI).
- There is no join token or line continuation concept.
- `()` and `[]` are grouping structures only; they do not provide newline termination semantics.
- A bare `if`, `when`, `for`, or `while` expression in statement position must end with `;`.
- Top-level declarations (functions, types, traits, given implementations) must end with `;`.

```koral
let a = 0;
let b = 1;

let count = "abc".count();

let branch = if false then 1 else 2;

let grouped = (1 + 2);

let fib(n: Int): Int = {
    if n <= 1 then { return n; };
    return fib(n - 1) + fib(n - 2);
};

if x > 0 then {
    println("positive");
} else {
    println("non-positive");
};
```

#### Entry Function

Every executable program needs an entry point. In Koral, this entry point is the `main` function. A typical `main` function declaration is as follows.

```koral
let main(): Void = {};
```

Here we declare a function named `main`. The right side of `=` is the function body, `{}` represents an empty block expression, returning `Void`.

The `main` function must:

- Have no parameters.
- Return `Int` or `Void`.

```koral
let main(): Int = {
    println("Hello");
    return 0;
};
```

#### Displaying Output

The standard library provides the `println` function to print a line of text to the standard output.

```koral
let main(): Void = println("Hello, world!");
```

Now try to execute this program, and we can see `Hello, world!` displayed on the console.

#### Comments

Comments are parts of the code ignored by the compiler, used to provide explanations to people reading the code.

```koral
// This is a single-line comment, starting from double slashes to the end of the line

/*
    This is a block comment.
    It can span multiple lines.
    /* Koral supports nested block comments */
*/
```

#### Identifiers

Identifiers are names given to variables, functions, types, etc. The naming rules are:

1. Case sensitive. `Myname` and `myname` are two different identifiers.
2. **Types** and **Constructors** must start with an **uppercase letter** (leading `_` is allowed), e.g. `Int`, `String`, `Point`.
3. **Variables**, **Functions**, **Members** must start with a **lowercase letter** or underscore (e.g., `main`, `println`, `x`).
4. Other characters in identifiers can be underscores `_`, letters, or numbers.
5. Within the same `{}`, identifiers with the same name cannot be defined repeatedly.
6. In different `{}`, identifiers with the same name can be defined, and the language will prioritize the identifier defined in the current scope.

### Build-Conditional Declarations

`#if` selects declarations per build target — os and arch — at compile time. It lives in the declaration domain: branches hold global declarations (including nested `#if`), never statements or expressions.

```koral
#if os("windows") then {
    let foreign "CreateFileA" create_file_a(path: *UInt8, access: UInt32): UInt32;
} else {
    let foreign "open" open_path(path: *UInt8, flags: Int32): Int32;
};
```

- The condition is a small closed grammar, not an expression: `os("...")` and `arch("...")` atoms combined with `and`, `or`, `not`, and parentheses. Values come from closed sets — `os` ∈ `windows` / `linux` / `macos`, `arch` ∈ `x86_64` / `aarch64`. An unknown predicate or value is an error that names the set.
- Branches are always blocks, and the whole construct ends with `;`. There is no `#endif`.
- The unselected branch still has to parse, but its names are never resolved and its types never checked.
- Same-name declarations must be partitioned across the branches of one `#if … else …` — one per side. Two declarations that can coexist are a duplicate declaration; an unconditional declaration may never share a name with a conditional one. The check is pure syntax: no build target turns a passing file red.
- `using` may appear inside a branch block (conditional imports). A `#if` that contains a `using` belongs to the file's using region — the same "imports first" rule as at top level.

### Values and Literals

We only need a few simple basic types to carry out most of the work.

#### Booleans

Booleans refer to logical values, they can only be true or false. The default boolean is `Bool` type.

```koral
let b1: Bool = true;
let b2: Bool = false;
let isGreater = 5 > 3; // Result is true
```

#### Numbers and Numeric Literals

Koral provides rich numeric types to meet different needs. The default integer is `Int` type, and floating-point numbers use `Float64` (64-bit) or `Float32` (32-bit).

- `Int`: Platform-dependent signed integer (usually 64-bit).
- `UInt`: Platform-dependent unsigned integer (usually 64-bit).
- `Int8`, `Int16`, `Int32`, `Int64`: Fixed-width signed integers.
- `UInt8`, `UInt16`, `UInt32`, `UInt64`: Fixed-width unsigned integers.
- `Float32`: 32-bit floating-point number.
- `Float64`: 64-bit floating-point number.

```koral
let i: Int = 3987349;
let f: Float64 = 3.14;
let b: UInt8 = 255;
```

Numeric literals support underscores `_` as separators for readability:

```koral
let million = 1_000_000;
let pi = 3.141_592_653;
```

A digit separator must sit **between two digits** of the same digit run — the integer part, the fractional part, or the exponent digits, in any base. It may not lead, not trail, not double, and not sit against `.`:

```koral
let ok1 = 1_000;        // fine: between digits
let ok2 = 1.0_0_1;      // fine: between fraction digits
let ok3 = 1_0e1_0;      // fine: separators in mantissa and exponent
let ok4 = 0xFF_FF;      // fine: between hex digits

// let bad1 = 1_;       // error: trailing separator
// let bad2 = _1;       // not a literal at all — `_1` is an identifier
// let bad3 = 1__0;     // error: doubled separator
// let bad4 = 1_.0;     // error: separator against '.'
// let bad5 = 1.0_;     // error: trailing separator
// let bad6 = 0x_1;     // error: leading separator after the base prefix
```

Each invalid form is a lexical error: `Invalid digit separator '_' in numeric literal`. A numeric literal can never start with `_` (that would be an identifier), and `1._x` is member access on `1`, not a float — a fraction needs a digit right after `.`.

Koral also supports binary, octal, and hexadecimal integer literals using the `0b`, `0o`, and `0x` prefixes respectively:

```koral
let bin = 0b1010;          // Binary, value is 10
let oct = 0o755;           // Octal, value is 493
let hex = 0xFF;            // Hexadecimal, value is 255
```

Non-decimal literals also support underscore separators:

```koral
let mask = 0xFF_FF;        // Hexadecimal, value is 65535
let flags = 0b1010_0101;   // Binary, value is 165
```

Note: Non-decimal literals only support integers, not floating-point numbers. Hexadecimal letters are case-insensitive (`0xABcd` is equivalent to `0xabCD`).

Floating-point literals also support scientific notation using the `e` exponent suffix:

```koral
let a = 1e3;      // 1000.0
let b = 1e-3;     // 0.001
let c = 2.5e+2;   // 250.0
let d = 1_000e2;  // 100000.0
```

Note: Only lowercase `e` is supported for exponent notation, consistent with the `0b`/`0o`/`0x` prefix convention. `e` opens an exponent only when a digit or [sign] digit follows it: `1e10` and `2.5e-3` are floats, but `1exp` is the integer `1` and the identifier `exp` (and `1e_1` is `1` and `e_1`).

#### Duration Literals

Duration literals are supported with integer suffixes:

```koral
let a = 10s;
let b = 250ms;
let e = 150us;
let f = 42ns;
```

Supported suffixes are `s`, `ms`, `us`, `ns`. A duration literal is sugar for a `Duration` construction after unit normalization — `10s` is `Duration.new(seconds = 10, nanoseconds = 0)` — and the result is unwrapped for you. Negative durations keep unary-minus semantics (for example `-5s` is parsed as unary `-` applied to `5s`).

#### Numeric Casting

Different numeric types require explicit conversion using `Type(expr)` syntax:

```koral
let a: Int = 42;
let b: Float64 = Float64(a);    // Int -> Float64
let c: Int32 = Int32(a);        // Int -> Int32
let d: UInt8 = UInt8(255);      // Int -> UInt8
```

Pointer reinterpretation and weak construction use a different spelling,
`expr as Type` (see [Raw Pointer Types](#raw-pointer-types)): `p as *T`,
`u as *Int`, `p as UInt`, `b as ?T` — an `as` target is pointer or weak only.
`Type(expr)` is numeric conversion, construction (`Point(1, 2)`), and
trait-object upcasting (`Drawable(c)`); `Bool(x)` and `String(x)` are errors
(`Type does not support cast`), a numeric `as` is an error (`Numeric
conversion is written 'Type(expr)', not 'expr as Type'`), and any other `as`
target is refused (`'as' casts to pointer or weak types`).

There is only one conversion spelling, and the **target type decides the
policy**. The integers form three parallel families — ten types each, same
widths, strictly isolated (`WrappingInt` and `Int` never mix in one operation):

| Family | Types | Arithmetic overflow | Width-changing conversion | Status |
|---|---|---|---|---|
| Regular | `Int` `Int8` `Int16` `Int32` `Int64` `UInt` `UInt8` `UInt16` `UInt32` `UInt64` | panics | checked | default |
| Wrapping | `WrappingInt` `WrappingInt8` ... `WrappingUInt64` | wraps modulo 2^N | takes the target's low bits | built in |
| Saturating | `SaturatingInt` `SaturatingInt8` ... | clamps to MIN/MAX | clamps to MIN/MAX | reserved, not implemented |

The boundary is **whether a wrapped answer exists**: wrap when one does, panic
only when none does. Arithmetic overflow wraps (modulo 2^N); an out-of-range
shift amount is masked to the width (`WrappingInt8(1) << 9` is `2`); `MIN / -1`
wraps to `MIN`. Division and remainder by zero have no wrapped answer and still
panic — as does converting a NaN or an infinity to an integer. `Wrapping*` types
share the regular types' width and ABI: the family is a compile-time policy, not
a different machine value.

The conversion matrix follows from the target alone. A conversion is
**unchecked** only when the two types hold exactly the same values — same width
and same signedness. Anything else, a width change or a signedness flip, is a
real conversion and follows the target family's policy:

| Source → Target | Same width & signedness | Width change or signedness flip |
|---|---|---|
| Regular → Regular | lossless retype | **checked** |
| Regular → Wrapping | lossless retype | **wraps** |
| Wrapping → Regular | lossless retype | **checked** |
| Wrapping → Wrapping | lossless retype | **wraps** |

- **Same width and signedness** is a lossless retype — the two types hold the
  same values. `UInt64(x: UInt)` and `Int(WrappingInt(n))` are free; the latter
  gives `n` back unchanged.
- **Any conversion to a regular target that can lose a value** is checked
  against the target type's range — a signedness flip included. `UInt(-5)`
  panics at run time; it is not reinterpreted. A conversion moves values, not
  bit patterns: `-5` and `18446744073709551611` are different numbers, and only
  the Wrapping family is in the business of ignoring that.
- **Any conversion to a Wrapping target** takes the target width's low bits —
  truncating, or sign/zero-extending when widening the two's-complement
  representation — and never panics. A signedness flip at the same width wraps
  modulo 2^N, which is the wrapped answer the family promises.

```koral
let big: Int = 300;
let a: UInt8 = UInt8(big);                        // Panic: numeric conversion overflow
let n: Int = -5;
// let u: UInt = UInt(n);                         // Panic: numeric conversion overflow
let u: UInt = UInt(WrappingUInt(n));              // 18446744073709551611 -- wrapped on purpose
let low: UInt8 = UInt8(WrappingUInt8(big));       // 44 -- the low byte
let b: Int8 = -1;
let wide: UInt = UInt(WrappingUInt(b));           // 18446744073709551615 -- sign-extends first
let raw: UInt8 = UInt8(WrappingUInt8(b));         // 255
```

The byte-take idiom -- serialization, hashing, bit tricks -- is where the
Wrapping target earns its keep: truncation is the point and a panic would be
noise. A negative `Int8` hashed through it sign-extends, so the same number
hashes the same whichever width it arrives in:

```koral
given Int8: Hash {
    public hash(self): UInt = UInt(WrappingUInt(self));
};
```

A literal is checked at **compile time**, by width and not by family: a constant
that does not fit is an author's mistake, not data-dependent overflow.
`WrappingUInt8(300)` is the same `Integer literal 300 is out of range for UInt8`
error as `UInt8(300)`. Literals also join the other operand's integer width in
either operand position — `WrappingInt(n) + 123` and `123 + WrappingInt(n)` are
both ordinary Wrapping arithmetic.

Floats have no family. An integer converted to a float is never checked —
precision may be lost (`|n|` > 2^53) — and a float narrowing to a float is
never checked either (it may lose precision or overflow to ±inf). A float
converts to an integer in two steps:

1. **Domain**: NaN and ±inf have no truncatable integer value and panic,
   whatever the target family.
2. **Range**: the value truncated toward zero then follows the target's policy
   — a regular target checks (`Int(1e20)` panics), a Wrapping target takes the
   low bits (`WrappingUInt8(300.7)` is `44`).

#### String ↔ Number

Converting between text and numbers is not a cast — there is no numeric
relationship to exploit. It goes through `std/text`, which defines three
traits: `Parseable` (`parse`), `RadixParseable` (`parse_radix`) and
`Formattable` (`format`).

```koral
using "std/text" { ... };

// String -> number: a static method on the target type, returning Result[Self]
let n = Int.parse("42") or else 0;            // 42
let f = Float64.parse("3.14") or else 0.0;    // 3.14
let b = Int.parse_radix("ff", 16) or else 0;  // 255

// number -> String
let s = 42.to_string();                       // "42"

// number -> String with a format spec
let hex = 255.format("x");                    // "ff"
let fixed = 3.14159.format(".2f");            // "3.14"
let sci = 1500.0.format(".2e");               // "1.50e3"
```

`parse` rejects anything it cannot make sense of, so it hands back a
`Result` rather than a best-effort number — `Int.parse("abc")` is
`.Error`, not `0`. Integer types implement `RadixParseable` for bases
2–36; floats parse decimal, `nan`, `inf` and `-inf` only.

A float's `to_string` is the **shortest decimal that parses back to the same
value** — round-trip is the contract, not a fixed digit count: `2.3` prints
`"2.3"`, `1e20` prints `"1e+20"`, `0.0` prints `"0"` (it is the same text JSON
numbers use). `Float32` round-trips through `Float32.parse`, `Float64` through
`Float64.parse`. When you need a *presentation* — fixed decimals, scientific
notation, width — say so with `.format(spec)` instead.

There are no free-function conversions in `std` — no `parse_int`, `to_int`
or `to_string(x)`. Use `T.parse(s)`, `parse_radix`, `.to_string()` and
`.format(spec)`.

#### Strings

In Koral, strings are used to represent text data. `String` type is a UTF-8 encoded character sequence.

String literals use double quotes `""` only.

```koral
let s1: String = "Hello, world!";
```

Koral supports string interpolation, allowing expressions to be embedded in strings using `\(expr)` syntax:

```koral
let name = "Koral";
let count = 3;
println("Hello, \(name)!");                    // Hello, Koral!
println("Count: \(count)");                    // Count: 3
println("Mixed \(name) has \(count) messages"); // Mixed Koral has 3 messages
println("Sum \(1 + (2 * 3))");                 // Sum 7
```

Escape characters use backslash `\`:

```koral
"\n";        // Newline
"\t";        // Tab
"\r";        // Carriage return
"\v";        // Vertical tab
"\f";        // Form feed
"\0";        // Null character
"\\";        // Backslash
"\"";        // Double quote
"\'";        // Single quote
"\x41";      // Hex byte escape: exactly 2 hex digits (0x00–0xFF), e.g. \x41 = 'A'
"\u{41}";    // Unicode scalar escape: 1–6 hex digits, e.g. \u{41} = 'A', \u{1F600} = 😀
```

##### Multiline String Literals

Use `"""` delimiters to write strings that span multiple lines, following the same rules as Swift:

- The opening `"""` must be immediately followed by a newline.
- The closing `"""` must be on its own line. Its leading whitespace (spaces or tabs) defines the common indentation prefix that is stripped from every content line.
- Every content line must be indented at least as much as the closing `"""`, otherwise a compile error is reported.
- The same escape sequences and `\(...)` interpolation as regular strings are supported.

```koral
let message = """
    Hello, Koral!
    Welcome to multiline strings.
    """;
// Equivalent to "Hello, Koral!\nWelcome to multiline strings."

let name = "World";
let greeting = """
    Hello, \(name)!
    Have a great day.
    """;
// Equivalent to "Hello, World!\nHave a great day."
```

The indentation of the closing `"""` determines how much is stripped:

```koral
let s = """
        indented content
        second line
    """;
// Closing """ is indented 4 spaces, content is indented 8 spaces.
// After stripping 4 spaces: "    indented content\n    second line"
```

Common String methods:

```koral
let s = "Hello, World!";
s.count();                        // 13 - byte length
s.is_empty();                     // false
s.contains("World");              // true
s.starts_with("Hello");           // true
s.ends_with("!");                 // true
s.to_ascii_lowercase();           // "hello, world!"
s.to_ascii_uppercase();           // "HELLO, WORLD!"
s.trim_ascii();                   // Trim leading/trailing whitespace
s.substring(0..<5);               // "Hello" - slicing
s.find("World");                  // Some(7)
s.replace_all("World", with = "Koral"); // "Hello, Koral!"
s.split(",");                     // Iterable view over the separator-split parts
s.lines();                        // Iterable view over the lines

// Join a list of strings
list.join_to_string(", ");        // Join List[String] with separator
```

To build a `String` incrementally, use `StringBuilder`:

```koral
let sb = StringBuilder.new();
sb.push_string("Hello");
sb.push_byte(',');
sb.push_string(" World");
let s = sb.to_string();
```

#### Runes

Rune literals use single quotes `''` and represent exactly one Unicode scalar value.

```koral
let r: Rune = 'A';
let nl: Rune = '\n';
let smile: Rune = '\u{1F600}';
```

Rune literal typing rules:

- Default type is `Rune`.
- In an explicit `UInt8` context, a rune literal can be inferred as byte (`UInt8`) if it is a single ASCII character.

#### Collection Literals

Koral supports collection literals for the built-in collection types: `List[T]`, `Set[T]`, `Dict[K, V]`, and the frozen snapshots `FrozenList[T]`, `FrozenSet[T]`, and `FrozenDict[K, V]` (see [Frozen Collections](#frozen-collections)).

```koral
let a = [1, 2, 3];                    // inferred as List[Int]
let b: Set[Int] = [1, 2, 3];           // inferred as Set[Int] from context
let c = ["x": 1, "y": 2];             // inferred as Dict[String, Int]
let f: FrozenList[Int] = [1, 2, 3];   // frozen snapshot from context
let empty: List[Int] = [];             // empty literal requires type context
```

Rules:

- `[e1, e2, ...]` is a collection literal. Without type context, it is inferred as `List[T]`.
- In `Set[T]` or `FrozenSet[T]` context, the same syntax is inferred as a set; duplicates collapse.
- `[k1: v1, k2: v2, ...]` is a dict literal and is inferred as `Dict[K, V]` — or `FrozenDict[K, V]` in that context; the last duplicate key wins.
- `[]` cannot be inferred without type context and must be annotated.
- Trailing commas are allowed for both collection and dict literals.
- Collection literals only target the built-in containers and their frozen snapshots (`List` / `Set` / `Dict` / `FrozenList` / `FrozenSet` / `FrozenDict`), not third-party container types.

`List`, `Set`, `Dict` and `Deque` are `type mutable` shared objects: they do not use copy-on-write. Mutating a container is visible through every handle, and an independent copy must be made explicitly with `clone()`. They are thread-confined working state — none of them may cross a thread boundary (see [Frozen Collections](#frozen-collections)).

Iteration order over a `Dict` or `Set` is **unspecified**: it follows the table layout, which is seeded per process (the hash-flooding defence), so it can differ between runs. Code that needs a stable order sorts the keys itself. `List` and `Deque` iterate in storage order.

### Variables and Bindings

Koral's variables use binding semantics, equivalent to binding a variable name and a value together. For safety reasons, variables are immutable by default, but we also provide mutable variables.

#### Read-only Bindings

In Koral, read-only variables are declared using the `let` keyword, following the principle of declaration before use.

Koral ensures type safety through static typing. Variable bindings can explicitly annotate types at declaration. Inside a function body, when there is enough information in the context, we can also omit the type, and the compiler will infer the variable's type. Global bindings never infer — see [Global Bindings](#global-bindings).

```koral
let a: Int = 5;   // Explicit type annotation
let b = 123;     // Automatic type inference (local bindings only)
```

Once a read-only variable is declared, its value cannot be changed within the current scope.

```koral
let a = 5;
a = 6 // Error
```

Note that a read-only binding to a `type mutable` object still allows mutating that object's `mutable` fields — the binding is fixed, the object is shared:

```koral
let xs = [10, 20, 30];
xs[1] = 99;      // ok: List is `type mutable`; the binding itself is not reassigned
```

#### Mutable Bindings

If we need a variable that can be rebound, we can use a mutable variable declaration with `let mutable`.

```koral
let mutable a: Int = 5;   // Explicit type annotation
let mutable b = 123;     // Automatic type inference (local bindings only)
```

#### Global Bindings

Inference is a convenience of function bodies. A **global** binding — a `let`
or `let mutable` declaration at the top level of a module — must carry an
explicit type annotation; an unannotated global is a compile error
(`Missing type: global variable declarations must explicitly declare a type`).
Functions and methods already require full signatures, so every global surface
reads with its types spelled out and only local names are inferred.

```koral
let counter: Int = 0;        // global: the annotation is required
let cache: Dict[String, Int] = Dict[String, Int].new();

let main(): Int = {
    let step = 2;            // local: inferred
    return counter + step;
};
```

The rule keeps a module's public shape checkable from its declarations alone —
a global's type is visible to every importer and to the initializer-ordering
machinery without following its initializer's inference.

#### Tuple Destructuring

A parenthesized binding destructures a **struct by position**: the number of
binding slots must equal the number of fields, and they bind in declaration
order. Each slot supports `_` (discard), `mutable` (mutable binding), and an
optional type annotation. There must be at least two slots — `(x)` is a
parenthesized binding, not a destructuring.

`Pair` is just a two-field struct, so this is how a `Pair` is taken apart too.

```koral
let (a, b) = Pair(1, 2);                    // a two-field struct
let (c: Int, d: String) = Pair(3, "hello");   // explicit type annotations
let (mutable e, f) = Pair(10, 20);          // mutable binding
let (_, g) = Pair(1, 2);                    // discard the first field

type Point3(x: Int, y: Int, z: Int);
let (px, py, pz) = Point3(1, 2, 3);         // any field count
```

There is no tuple/pair **literal**. Build a `Pair` with its constructor, like any
other type: `Pair[Int, String](1, "a")`.

### Assignment

For mutable bindings, we can change which value they refer to multiple times when needed.

```koral
let mutable a = 0;
a = 1;  // Legal
a = 2;  // Legal
```

### Block Expressions

In Koral, `{}` represents a block expression.

Block rules:

- A block contains zero or more statements.
- A `Result` may not be dropped silently: a statement holding one must use it or discard it on purpose — `let _ = expr;` says "drop this". A silently dropped `Result` is a lost error, and this is what keeps that from happening. Other statement values drop silently as usual (`Void`, `Never`, and effectful helpers that hand back an observation their callers ignore).
- A block may end with a final expression that does not use a trailing semicolon.
- If a block has a final expression, the block's type and value are the type and value of that expression.
- If a block has no final expression, or the last expression ends with a semicolon, the block's type is `Void`.
- `return`, `break`, and `continue` can end the block early and therefore give that block type `Never`.
- Plain `break` exits the nearest enclosing `while` or `for` loop.
- A block ending with `return`, `break`, or `continue` has type `Never`.

Examples:

```koral
let load(path: String): Result[Int] = {
    let text = read_text_file(path) or return;
    return Int.parse(text);
};

let increment(): Int = {
    let base = 41;
    base + 1
};

let a: Void = {};
let main(): Void = {
    let c = 7;
    let d = c + 14;
    println(((c + 3) * 5 + d / 3).to_string());
};
```

### Operators

Operators are symbols that tell the compiler to perform specific mathematical or logical operations.

#### Arithmetic Operators

```koral
let a = 4;
let b = 2;
println( a + b );    // + Add
println( a - b );    // - Subtract
println( a * b );    // * Multiply
println( a / b );    // / Divide
println( a % b );    // % Modulus
```

#### Comparison Operators

Comparison operators compare two values. The result is `Bool` type. 

```koral
let a = 4;
let b = 2;
println( a == b );     // == Equal
println( a != b );     // != Not equal
println( a > b );      // > Greater than
println( a >= b );     // >= Greater than or equal to
println( a < b );      // < Less than
println( a <= b );     // <= Less than or equal to
```

Koral also supports chained ordering comparisons as syntax sugar for interval-style predicates:

```koral
println(1 < x < 3);
println(10 >= y > 0);
println(a <= b <= c);
```

Chains are restricted to `<`, `<=`, `>`, and `>=`, and every operator in the chain must stay in the same direction family (ascending `<`/`<=` or descending `>`/`>=`). Mixed chains such as `a < b > c`, `a < b == c`, or `a == b < c` are rejected; write them explicitly with `and` instead.
Each operand in a valid chain is evaluated at most once, and the chain short-circuits from left to right.

#### Logical Operators

Logical operators perform logical operations (AND, OR, NOT) on two Bool type operands.

```koral
let a = true;
let b = false;
println( a and b );       // AND, true only if both are true
println( a or b );        // OR, true if either one is true
println( not a );         // NOT, boolean negation
```

`and` and `or` have short-circuit semantics:

```koral
let a = false and f(); // f() will not be executed
let b = true or f();   // f() will not be executed
```

#### Bitwise Operators

```koral
let a = 4;
let b = 2;
println( a & b );    // Bitwise AND
println( a | b );    // Bitwise OR
println( a ^ b );    // Bitwise XOR
println( ~a );       // Bitwise NOT
println( a << b );   // Left shift
println( a >> b );   // Right shift
```

#### Range Operators

Range operators generate a range (Range), commonly used in loops or pattern matching.

```koral
1..5;     // 1 <= x <= 5 (Closed interval)
1..<5;    // 1 <= x < 5  (Right open interval)
1<..5;    // 1 < x <= 5  (Left open interval)
1<..<5;   // 1 < x < 5   (Open interval)
1...;     // 1 <= x      (Right unbounded, inclusive start)
1<...;    // 1 < x       (Right unbounded, exclusive start)
...5;     // x <= 5      (Left unbounded, inclusive end)
...<5;    // x < 5       (Left unbounded, exclusive end)
...;      // Full range
```

The `..` family is the connector: both bounds are written, always. The `...`
family marks the elided bound — it stands where the missing bound would be, so
a `...` range has at most one bound (`1...` is the range from 1 onward, `...5`
the range up to 5, `...` the full range). The `<` always sits between the dots
and the bound it excludes.

These range operators construct `Range` values. They are distinct from chained comparison predicates such as `1 < x < 5`, which produce `Bool`.

#### Compound Assignment

```koral
let mutable x = 10;
x += 5;       // x = x + 5
x -= 2;       // x = x - 2
x *= 3;       // x = x * 3
x /= 2;       // x = x / 2
x %= 4;       // x = x % 4

let mutable y = 12;
y &= 10;     // y = y & 10
y |= 1;      // y = y | 1
y ^= 15;     // y = y ^ 15
y <<= 1;     // y = y << 1
y >>= 2;     // y = y >> 2
```

Each `op=` **is** its spelled desugaring — two steps, not one atomic step. The
target is evaluated first (left path and subscripts), then the current value is
read, then the operator runs — built-in arithmetic or trait overloading, so a
generic `T` with an `Add` implementation behaves exactly like the built-ins —
and the result is written back. On a `type sendable mutable` field each step
takes its own short lock or atomic access (see [Object Locks](#object-locks)),
so `x.f += 1` is **not** atomic across threads; a concurrent increment belongs
to `AtomicCell.update_and_get` or a `Mutex`.

#### Operator Precedence

Operator precedence from high to low:

1. Postfix: calls `()`, subscripts `[]`, member access `.`, qualified paths `Type(Trait)`, generic method suffixes
2. Prefix / Control flow: unary `-`, `~`, dereference `*`, raw address-of `&`, `&mutable`; `if`, `while`, `for`, `when`
3. Multiplication/Division: `*`, `/`, `%`
4. Addition/Subtraction: `+`, `-`
5. Shift: `<<`, `>>`
6. Bitwise AND: `&`
7. Bitwise XOR: `^`
8. Bitwise OR: `|`
9. Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
10. Range: `..`, `..<`, `<..`, `<..<` (closed); `...`, `...<`, `<...` (open)
11. Pattern test: `is`, `is not`
12. Logical NOT: `not`
13. Flow layer, tightest to loosest: `and then`, then `or else` / `or return`
14. Logical layer, tightest to loosest: `and`, then `or`

Rows 13 and 14 are **two separate layers**, not four steps of one ladder. Everything
above them is the ordinary ladder; these two sit at the same level as each other and
are entered one at a time. Precedence *inside* a layer is as listed, but **the two
layers do not mix implicitly**. Crossing from one to the other takes parentheses:

Everything in rows 1–12 — including **comparison** — binds tighter than both
layers, the way comparison binds tighter than `??`/flow operators in Swift. So
`a == b or else c` groups as `(a == b) or else c`, never `a == (b or else c)`,
and `opt or else x == y` groups as `opt or else (x == y)`.

- `f() and then as v in g(v) or else h()` groups as `(f() and then as v in g(v)) or else h()` — flow with flow, fine.
- `a or b and c` groups as `a or (b and c)` — logical with logical, fine.
- `a and (b or else c)` — fine, and means that.
- `(a and b) or else c` — fine, and means something else.
- `a and b or else c` — **refused**. It looks like `(a and b) or else c` and would have parsed as `a and (b or else c)`; neither is what the line reads as, so say which with parentheses.
- `opt and then as v in v == 1 and false` — **refused**, for the same reason.

```koral
let opt: Option[Int] = Option[Int].Some(1);
let ready: Bool = true;

// `and then` runs first inside the flow layer, then `or else`:
let inLayer = opt and then as v in v * 2 or else 0;   // 84

// The transform is the intended scope of `and` — say so:
let good = opt and then as v in (v == 1 and false);   // Some(false)

// The logical `and` wants a flow result on its right — say so:
let good2 = ready and (opt and then as v in v > 0 or else false);   // true
```

This is the same rule `??` follows in languages that have it: a value-coalescing operator is a clear middle layer and does not chain onto boolean logic without a parenthesis. Note that `(ready and opt)` is not a fix for the mixed form: `and` requires `Bool` on both sides, so a flow result has to be reduced to `Bool` first (as in `good2`) before it can take part in a logical `and`.

#### Evaluation Order

Koral evaluates expressions **strictly left-to-right**. Wherever operands are sequenced in the syntax, source order is evaluation order — there is no unspecified order anywhere:

1. **Call arguments** (including qualified-call and constructor arguments) evaluate left-to-right: `f(trace(1), trace(2))` runs `trace(1)` before `trace(2)`.
2. **Binary operands** (`+`, `*`, `==`, `&`, `<<`, …) evaluate left-to-right: in `trace(1) + trace(2)`, the left side runs first.
3. **`and` / `or`** evaluate the left operand first and **short-circuit**: the right operand is skipped when the left decides the result.
4. **`and then` / `or else` / `or return`** evaluate the left operand first and short-circuit: the transform / default is skipped when the left side is `None` / `Error` (for `and then`) or `Some` / `Ok` (for `or else`).
5. **Collection and dict literals** evaluate elements in source order; for a dict entry the key is evaluated before its value.
6. **Constructor fields** evaluate in source order, not in declaration order.
7. **Assignments** evaluate the left path and its subscripts first, then the right-hand side, then perform the write — the same order for every type. `xs[f()] = g()` runs `f()`, then `g()`, then writes the slot.

```koral
// Each trace prints its argument; the printed order is the evaluation order.
let a = trace(1) + trace(2);          // [1][2]
let b = sum(trace(3), trace(4));      // [3][4]
let c = [trace(5), trace(6)];         // [5][6]
let d = [trace(7): trace(8)];         // [7][8] -- key before value
let p = Point(trace(9), trace(10));   // [9][10]

// Short-circuit: the right side never runs when the left decides the result.
let e = traceb(false) and traceb(true);   // [false side] only
let f = opt_none and then as v in trace(v);   // transform skipped
let g = opt_some or else trace(12);       // default skipped
```

### Functions

Functions are independent blocks of code used to complete specific tasks.

#### Definition

Functions are defined using the `let` keyword. The function name is followed by `()` indicating the parameters, and the return type follows the parentheses, introduced by `:`. Named functions and methods must spell out the return type explicitly.

The right side of `=` must declare an expression, and the value of this expression is the return value of the function.

```koral
let f1(): Int = 1;
let f2(a: Int): Int = a + 1;
let f3(a: Int): Int = a + 1;
```

#### Calling

Use `()` syntax to call functions:

```koral
let a = f1();
let b = f2(1);
```

#### Parameters

Parameters are data that the function can receive during execution. Koral supports two kinds of parameters: positional and named.

##### Positional Parameters

Declared as `name: Type` (no `=`). A positional parameter must be passed **by
position** — it can never be passed by label.

```koral
let add(x: Int, y: Int): Int = x + y;
let a = add(1, 2); // a == 3
```

##### Named Parameters

Declared as `name: Type =` — the `=` is the named marker. With no literal after
the `=`, the caller must supply the value; `name: Type = 123` adds a default.
A named parameter must be passed **by label** (`name = value`).

```koral
let connect(host: String, port: Int =): Void = {};
connect("localhost", port = 8080);
```

##### Mixing Rules

A parameter's declaration fixes its call shape with no exceptions:

- Declared named (`name: Type =`) → the call **must** use the label (`name = value`).
- Declared positional (`name: Type`) → the call **must not** use a label.

There is no optional-label form: the declaration chooses one of exactly two call shapes. Positional parameters must come before named parameters in the declaration; at the call site, positional arguments are matched by position first, then named arguments are matched by label.

```koral
type Window(title: String, width: Int =, height: Int =);

// Positional fills 'title'; named 'width'/'height' must be labelled
let w = Window("hello", width = 900, height = 600);
// Window("hello", 900, 600)      // error: 'width' must be passed by label
// Window("hello", width = 900, height = 600, title = "x")  // error: 'title' is positional
```

##### Default Values

Only named parameters (those marked with `=`) can have default values. A default value is specified as a literal after `=`:

```koral
type Config(
    count: Int = 42,
    name: String = "hello",
    enabled: Bool = true,
    ratio: Float64 = 3.14,
    ch: Rune = 'A',
    items: List[Int] = [],
    flags: Dict[String, Int] = [],
    span: Range[Int] = ...,
);
```

Supported default value literals:

| Kind | Examples |
|------|----------|
| Integer | `0`, `42` |
| Float | `3.14`, `0.0` |
| Bool | `true`, `false` |
| String | `"hello"` |
| Rune | `'A'` |
| Empty collection | `[]` (List, Set, or Dict, inferred from type context) |
| Empty range | `...` (resolves to `Range[T].Full()`) |
| Null pointer | `null` (joins `*T` / `*mutable T`) |

The default value type must match the parameter type. For example, `name: String = 42` is an error.

Mutable parameters use the `mutable` keyword:

```koral
let increment(mutable x: Int): Int = { x += 1; return x };
```

For ordinary parameters, `mutable` only makes the local binding writable inside the function body. It is not part of the function signature, does not change the function type, and is ignored when checking trait/given method compatibility.

##### Constructor Calls

Struct, enum, and function calls all follow the same positional/named rules —
the declaration decides, the call obeys:

```koral
type Shape {
    Circle(radius: Float64),            // positional case parameter
    Line(start: Point =, end: Point =),    // named case parameters
};

// Positional parameter: passed by position, never by label
let s1 = Shape.Circle(1.0);

// Named parameters: passed by label (argument order may vary)
let s2 = Shape.Line(end = Point(1, 1), start = Point(0, 0));
// Shape.Line(Point(0, 0), Point(1, 1))   // error: 'start' must be passed by label
```

Pattern matching destructures under exactly the same label rules: a field
declared named must be matched by label, and a field declared positional must
not be.

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start = p, end = e) then println(p.x),
};

if b is Button(w, height = _, label = l) then println(l);
// Button declares `width` positional and `height`/`label` named
```

#### Function Types

In Koral, functions are also a type. Function types are declared using `(T1, T2, ...) -> R` syntax, where `T1, T2, ...` are parameter types and `R` is the return type.

```koral
let square(x: Int): Int = x * x;        // (Int) -> Int
let f: (Int) -> Int = square;
let a = f(2);                         // a == 4
```

We can also define function type parameters or return values:

```koral
let hello(): Void = println("Hello, world!");
let run(f: () -> Void): Void = f();
let toRun(): (() -> Void) -> Void = run;

let main(): Void = toRun()(hello);
```

### Lambdas and Closures

#### Lambda Expressions

Lambda expressions are very similar to function definitions, except that `=` is replaced by `=>`, and there is no function name or `let` keyword.

```koral
let f1(x: Int): Int = x + 1;            // (Int) -> Int
let f2 = (x: Int): Int => x + 1;        // (Int) -> Int
let a = f1(1) + f2(1);                // a == 4
```

When the type of lambda can be inferred from context, parameter types and return type can be omitted:

```koral
let f: (Int) -> Int = (x) => x + 1;
```

Lambda supports multiple forms:

```koral
() => 42;                           // No parameters
(x) => x * 2;                      // Single param, type inferred
(x: Int) => x * 2;                  // Single param with type
(x, y) => x + y;                   // Multiple params, types inferred
(x: Int, y: Int): Int => x + y;       // Full type annotations
(x) => { let y = x * 2; return y + 1; };  // Block body
```

#### Closures

Lambda expressions can capture variables from their surrounding scope. This is called a closure.

```koral
let make_adder(base: Int): (Int) -> Int = {
    return (x) => base + x;
};

let add10 = make_adder(10);
let result = add10(32);  // result == 42
```

##### Capture Rules

Closure capture is **copy-only**. A closure owns its captures, so an escaping closure never points at storage it does not own.

- An immutable binding (`let`) is captured by copy.
- A `type mutable` object is captured as a shared handle: the closure and the outside observe the same object.
- A `let mutable` binding **cannot** be captured. Doing so would let a closure mutate storage it does not own, so the compiler rejects it.

To carry mutable state into a closure, hold it in a `Cell` — a shared `type mutable` box — and capture the cell:

```koral
let make_counter(): () -> Int = {
    let counter = Cell(0);              // shared mutable state
    return () => {
        counter.value = counter.value + 1;
        return counter.value;
    };
};

let c = make_counter();
c();  // 1
c();  // 2
```

The same rule applies to any `type mutable` object — capture it and share it:

```koral
let xs = [10, 20];
let add = () => { xs.push(30) };   // ok: `xs` is a shared handle
```

#### Currying

Closures enable currying:

```koral
let add: (Int) -> (Int) -> Int = (x) => (y) => x + y;

let add10 = add(10);
let result = add10(32);  // result == 42
let sum = add(20)(22);   // sum == 42
```

## 2. Control Flow

### Conditional Expressions

Selection structures are used to judge given conditions and control the flow of the program.

In Koral, selection structures use `if` syntax. `if` is followed by a judgment condition. When the condition is `true`, the `then` branch is executed. When the condition is `false`, the `else` branch is executed. `if` is always an expression. With both `then` and `else`, it produces a value; without `else`, the single-branch `if` produces `Void`.

```koral
let main(): Void = if 1 == 1 then println("yes") else println("no");
```

`if` with `else` is also an expression. The `then` and `else` branches must be followed by expressions — or by a bare control transfer, described below.

```koral
let main(): Void = println(if 1 == 1 then "yes" else "no");
```

Since `if` itself is also an expression, `else` can naturally be followed by another `if` expression for chained conditions.

```koral
let x = 0;
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less";
```

When we don't need to handle the `else` branch, we can omit it. The single-branch form is still an expression, but it produces `Void`: its block branch defaults to `Void`.

```koral
let main(): Void = if 1 == 1 then println("yes");
```

When an `if` with `else` uses a block branch, the final expression of that block becomes the branch value.

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

#### Branch Bodies and Control Transfers

A branch body — the slot after `then` or `else` — is an expression, or one of the three control transfers written **bare**: `return <value>?`, `break`, or `continue`. A bare transfer is sugar for the single-jump block you would otherwise write: `then return x` means exactly `then { return x; }`. The branch types `Never`, so it unifies with a value branch like any block that cannot fall through. The same rule covers every body slot: both branches of `if`, the body of `while` and `for`, and the arms of `when`.

```koral
let classify(x: Int): String = {
    if x > 0 then return "pos" else return "non-pos";
};

let findFirst(xs: List[Int]): Int = {
    for x in xs then return x;
    return 0 - 1;
};
```

A control transfer is not an expression. It is legal only in a branch body — `let x = return 3;` or `f(break)` is a parse error. Whether `return` carries a value follows the same rule as the `return <value>;` statement: whatever can start an expression does. A branch body takes no `;` of its own; the `;` in `if c then return 3;` terminates the enclosing statement.

### Loops

#### while Expression

In Koral, loop structures use `while` syntax. `while` is followed by a judgment condition. When the condition is `true`, the following body executes, then control returns to the condition for the next iteration. `while` is an expression that produces `Void`.

```koral
let mutable i = 0;
while i < 10 then {
    println(i);
    i += 1;
};
```

#### for Loop

The `for` loop is used to traverse any object that implements the iterator interface (such as lists, maps, sets, ranges, etc.).

In each iteration, the next value produced by the iterator is bound and the body following `then` runs. The loop binding position takes the **full match pattern** grammar — exactly what a `when` arm takes — but it must **cover every element value**: a loop cannot skip an element the pattern refuses, so a pattern that leaves any value unmatched is rejected at compile time with `For binding cannot fail; use 'when' to match`. Coverage is judged by the exhaustiveness checker, not by shape alone: `.Only(v)` on a one-case enum and `.A(x) or .B(x)` on a two-case enum are accepted even though each side of the `or` alone, or the enum destructure on a multi-case type, is refused. `for` is an expression that produces `Void`.

```koral
let nums: List[Int] = [10, 20, 30];
for x in nums then {
    println(x);
};

for i in 0..5 then {
    println(i);
};

let loop_value = while false then {
    println("unreachable");
};

let for_value = for x in nums then {
    println(x);
};
```

The binding is a pattern: `_`, `x`, `mutable x`, struct destructuring, tuple destructuring and nested destructuring all qualify, as long as the result is irrefutable:

```koral
let pairs: List[Pair[Int, Int]] = [Pair(1, 2), Pair(3, 4)];

for (left, right) in pairs then {
    println((left + right).to_string());
};

for Point(x, y, z) in points then {
    println(x);
};
```

`for` also takes a `where` guard, after the iterable and before `then` — the same slot a `when` arm guard takes before its `then`. A false guard skips the element and moves on to the next iteration; it does not end the loop. The pattern's bindings are visible in the guard:

```koral
for p in points where p.x > 0 then {
    println(p.x);
};
```

#### break and continue

- `break`: Exit the innermost enclosing `while` / `for` loop.
- `continue`: Skip the current iteration. It binds to the loop the same way `break` does.

```koral
let mutable i = 0;
while true then {
    if i > 20 then {
        break;
    };
    if i % 2 == 0 then { i += 1; continue; };
    println(i);
    i += 1;
};
```

### Early Exit: `return`

- `return` leaves the enclosing function with a value (or `Void`).
- Plain `break` exits the nearest enclosing `while` / `for` loop.

All three may be written bare as a branch body — `if c then return v`, `when x in { .None() then break, ... }` — which is sugar for the single-jump block (see [Branch Bodies and Control Transfers](#branch-bodies-and-control-transfers)).

`break` always binds to the innermost enclosing loop. Branches do not intercept it: an `if`, a `when` arm, an `or else` default, an `and then` transform, or an `if` used as an expression all sit between the `break` and its loop without changing the target. A function or lambda boundary does intercept both statements — `break` or `continue` inside a closure has no loop to bind to and is an error.

### Cleanup with `defer`

The `defer` statement declares a cleanup expression to be executed when the current block scope exits. The deferred expression runs regardless of whether the scope exits normally or early via `return`, `break`, or `continue`.

When execution takes a `Never` termination path (for example `panic()`, `abort()`, or `exit()`) and the program terminates immediately, execution of in-scope `defer` is not guaranteed.

`defer` is followed by an expression whose return value is discarded.

```koral
let main(): Void = {
    println("start");
    defer println("cleanup");
    println("work");
    // Output: start, work, cleanup
};
```

Multiple `defer` statements in the same scope execute in reverse declaration order (LIFO):

```koral
let main(): Void = {
    defer println("first");
    defer println("second");
    defer println("third");
    // Output: third, second, first
};
```

`defer` binds to the block scope where it is declared, not the function scope. In loops, `defer` executes at the end of each iteration:

```koral
let mutable i = 0;
while i < 3 then {
    i += 1;
    defer println("cleanup");
    println(i);
    // Each iteration outputs: value of i, cleanup
};
```

The deferred expression can also be a block expression:

```koral
defer {
    println("cleaning up");
    close(handle);
};
```

#### Restrictions

- `return`, `break`, and `continue` are not allowed inside a `defer` expression.
- Nested `defer` is not allowed inside a `defer` expression.
- `defer` is not an exception-style stack unwinding mechanism; it is not guaranteed on `panic/abort/exit` `Never` termination paths.
- These restrictions do not cross Lambda boundaries — Lambdas have their own independent scope.

### Option and Result Flow

Koral provides three special operators for working with `Option` and `Result` types:

- `or else`: Value coalescing. Returns the right-hand default value when the left side is `None` or `Error`.
- `and then`: Optional chaining / value transformation. Applies the right-hand transformation when the left side is `Some` or `Ok`. The result always stays in the same `Option` / `Result` kind: when the transformation's own return type is already that kind, its value **is** the result (one wrap is collapsed), and anything else is wrapped once. A generic transform's type parameter is opaque and therefore wrapped — so `map[U: Any](f: (T) -> U): Option[U]` keeps `Option[U]` for every `U`, including `U = Option[V]`.
- `or return`: Early-return propagation sugar. It unwraps `Some` / `Ok`, and on `None` / `Error` returns from the enclosing function.

#### Naming the unwrapped value

There is no implicit name. Two spellings give the transformation access to the unwrapped value, and they differ only in whether it needs a name:

- **Chain** — `and then .member(...)`: the receiver is the unwrapped value, so `config and then .window.title` reads as `config?.window.title`. A leading dot here is always a member of the unwrapped value (never an implicit member construction). The chain is a full postfix run: `.f(x).g`, `.f()[0]`.
- **Binder** — `and then as v in body`: names the unwrapped value for `body`. `body` is a single layer operand, so an `or else` written after it belongs to the enclosing chain: `x and then as v in v * 2 or else 0` is `(x and then as v in v * 2) or else 0`.

The chain is sugar for the binder — `x and then .f()` and `x and then as v in v.f()` have the same type and value — so the chain can always be expanded when a name helps.

`or else` takes a fallback value, which needs no name in the common case. When the fallback must look at the error, bind it:

- `or else as e in body` — `e` is the `Error` value. **`Result` only**: `None` has no payload, so the binder form on `Option` is an error.
- The fallback's type is the left operand's **payload** type: with `x Option[T]`, `x or else d` makes `d` a `T`, not an `Option[T]`.

Precedence follows the parser: inside the flow layer `and then` binds tighter than `or else` / `or return`. The flow layer as a whole does not mix with logical `and` / `or` without parentheses — see [Operator Precedence](#operator-precedence).

```koral
let opt = Option[Int].Some(42);
let val = opt or else 0;           // 42 (because opt is Some)

let none = Option[Int].None();
let val2 = none or else 0;         // 0 (because none is None)

let mapped = opt and then as v in v * 2;  // Some(84)

// The transform returns Option, so its value is the result — one wrap is
// collapsed, not doubled. A transform returning a bare value is wrapped once.
let half(x: Int): Option[Int] =
    if x % 2 == 0 then Option[Int].Some(x / 2) else Option[Int].None();
let chained = opt and then as v in half(v);  // Some(21) — type Option[Int]

// The chain is sugar over the binder: the receiver is the unwrapped value.
type Config(window: Window);
type Window(title: String);
let cfg = Option[Config].Some(Config(Window("untitled")));
let title = cfg and then .window.title or else "none";   // "untitled"

// Naming the error on a Result.
let parsed = Result[String].Error("bad input");
let shown = parsed or else as e in e.message();          // "bad input"

let load_port(path: String): Result[Int] = {
    let text = read_text_file(path) or return;
    return Int.parse(text);
};
```

`or return` is equivalent to a fixed `or else` early-return pattern:

- For `Result`: `expr or return` is equivalent to `expr or else as e in { return .Error(e); }`
- For `Option`: `expr or return` is equivalent to `expr or else { return .None(); }`

It must be used inside a function whose return kind matches the propagated value:

- `Result` propagation requires the enclosing function to return `Result`
- `Option` propagation requires the enclosing function to return `Option`

## 3. Custom Types

Koral provides a powerful type system that allows you to define your own data structures. Use the `type` keyword to define a shallowly immutable nominal, and `type mutable` to define a shared object.

### `type`: Shallowly Immutable Nominals

A `type` declaration introduces a nominal type whose fields are all immutable. Values of a `type` have **no identity**, and the compiler decides the layout — inline, hidden indirection, or shared backing. Value semantics is not promised: copies may share storage, which is unobservable precisely because the type is shallowly immutable. A `type` **cannot implement `Drop`**: its cleanup is the synthesized field release, and only a `type mutable` carries a destructor — see [`Drop`](#drop).

Struct fields can be positional or named. A positional field is `name: Type`; a named field is marked with `=` — `width: Int =` (the caller must pass it) or `height: Int = 600` (with a default).

#### Definition

```koral
type Empty();
type Point(x: Int, y: Int);

type Config(
    name: String,               // positional field
    width: Int =,               // named field (no default)
    height: Int = 600,         // named field with default
    title: String = "Untitled" // named field with default
);
```

Rules:

- Positional fields must come before named fields.
- Only named fields can have default values.
- Default values must be literals: integer, float, bool, string, rune, `[]` (empty collection), or `...` (empty range).
- A `type` cannot declare `mutable` fields, and cannot be declared `mutable` itself (`type mutable` is the other declaration form).

#### Construction

Use `()` syntax to call the constructor:

```koral
let a: Point = Point(0, 0);

// Named fields are called with labels; positional fields are not
let c1: Config = Config("main", width = 800);
let c2: Config = Config("main", width = 800, height = 900, title = "App");
// height and title use their defaults: 600 and "Untitled"
```

#### Field Access

Use `.` syntax to access member variables. Fields of a `type` are read-only:

```koral
type Point(x: Int, y: Int);

let main(): Void = {
    let a = Point(64, 128);
    println(a.x);  // 64
    println(a.y);  // 128
    // a.x = 2;    // error: `type` fields are immutable
};
```

### `type mutable`: Shared Mutable Objects

A `type mutable` declaration introduces a shared object with identity. Assignment and argument passing hand out handles to the same object; fields are immutable by default and only explicitly declared `mutable` fields may be modified in place.

#### Mutable Fields

```koral
type mutable Counter(mutable value: Int, id: UInt);

let main(): Void = {
    let c = Counter(0, 1);
    c.value = 5;  // ok, because Counter is `type mutable` and `value` is a mutable field
    // c.id = 2;  // error: `id` is not a mutable field
};
```

The mutability of member variables follows the type definition, not the binding: a read-only binding to a `type mutable` object can still mutate that object's `mutable` fields.

```koral
type mutable Counter(mutable value: Int);

let c = Counter(0);
c.value = 1;      // ok: shared object, binding is not reassigned
```

Independent copies are explicit: containers and other shared objects do not use copy-on-write.

```koral
let a = [1, 2];
let b = a.clone();   // independent copy
b.push(3);
// a is still [1, 2]
```

### Enums

Enums allow you to define a type that can be one of several different variants. Each variant can carry different types of data.

```koral
type Shape {
    Circle(radius: Float64),
    Rectangle(width: Float64, height: Float64),
};

let s = Shape.Circle(1.0);
```

Enum declarations cannot be `mutable` — enums are shallowly immutable like `type`.

#### Using Enum Values

Extract data from enum variants through pattern matching (see [Pattern Matching](#4-pattern-matching)):

```koral
let area = when s in {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
};
```

#### Implicit Member Expressions

Implicit member expressions use `.memberName(...)` syntax.

Rules:

- They are valid only when the expected type is known from context.
- They may construct enum cases or call static methods.
- They require parentheses; bare `.Name` is not a valid implicit member expression.
- If the compiler cannot infer the expected type, the expression is rejected.

Design note:

- Enum cases remain data constructors semantically, but Koral gives implicit member expressions a uniform explicit construction or call surface.
- In expression position, zero-field enum cases still use `.Name()` rather than the bare `.Name`.
- Pattern syntax also requires parentheses; zero-field enum case patterns must be written as `.Name()`.

```koral
// Enum construction — omit the Option[Int] prefix
let a: Option[Int] = .Some(42);
let b: Option[Int] = .None();

// In function arguments
let process(opt: Option[Int]): Void = when opt in {
    .Some(v) then println(v.to_string()),
    .None() then println("none"),
};
process(.Some(10));

// In assignments
let mutable x: Option[Int] = .None();
x = .Some(100);

// In conditional expression branches
let c: Option[Int] = if true then .Some(1) else .None();

// Static method calls — omit the List[Int] prefix
let list: List[Int] = .new();
let list2: List[Int] = .with_capacity(10);
```

### Type Aliases

Type aliases allow you to define a new name for an existing type, improving code readability. Use the `type AliasName = TargetType` syntax.

```koral
type Meters = Int;
type Coord = Point;
type IntList = List[Int];
```

Type aliases are fully eliminated at compile time — an alias is completely equivalent to its target type:

```koral
type Meters = Int;

let distance: Meters = 100;
let add_meters(a: Meters, b: Meters): Meters = a + b;
let result = add_meters(distance, 50);  // result == 150
```

Aliases can be chained:

```koral
type Meters = Int;
type Distance = Meters;  // Distance ultimately resolves to Int
```

Type aliases support access modifiers:

```koral
public type Meters = Int;       // Public
private type InternalId = Int;  // File-scoped only
```

Restrictions:

- Generic type aliases are supported (e.g., `type OrdList[T: Ord] = List[T];`): arity and bounds are checked at the instantiation point, and the target type is expanded with the bindings at instantiation. A direct self-reference is a misspelling; an expansion cycle reports `Circular type alias`. A generic alias without its type arguments names no type. Type aliases are fully erased at semantic checking.
- Circular references are not allowed (e.g., `type A = A`).
- Type alias names must start with an uppercase letter (leading `_` is allowed).
- A type alias cannot be declared `mutable` — mutability is a property of the nominal declaration, not of an alias.

### Generics

Generics allow you to write code that applies to multiple types, improving code reusability.

#### Generic Data Types

Generic data types use `TypeName[T: Constraint]` syntax to define generic parameters:

```koral
type Pair[T1: Any, T2: Any](left: T1, right: T2);
```

When constructing generic data types, pass actual types in the generic parameter position:

```koral
let a1 = Pair[Int, Int](1, 2);
let a2 = Pair[Bool, String](true, "hello");
```

When the context type is clear, generic type parameters can be omitted:

```koral
let a1 = Pair(1, 2);           // Inferred as Pair[Int, Int]
let a2 = Pair(true, "hello");  // Inferred as Pair[Bool, String]
```

There is **no tuple/pair literal**. `(1, 2)` is not an expression — it is the
*destructuring* form, and only appears where something is being taken apart
(`let (a, b) = p;`, a `when`/`is` pattern). Build a `Pair` with its constructor:

```koral
let p1 = Pair(1, 2);
let p2 = Pair(true, "hello");
let (a, b) = p1;              // destructuring, not a literal
```

#### Generic Functions

Generic functions write type parameters after the function name:

```koral
let identity[T: Any](x: T): T = x;

println(identity(42));       // 42
println(identity("hello"));  // hello
```

#### Generic Constraints

Generic parameters **must** specify Trait constraints to limit acceptable types. A parameter that
takes no trait constraint is spelled `[T: Any]` — `Any` is the *absence* of a constraint, not a
constraint of its own:

```koral
let max_val[T: Ord](a: T, b: T): T = if a > b then a else b;
let contains[T: Eq](list: List[T], value: T): Bool = list.contains(value);
```

Multiple constraints are connected with `and`:

```koral
let describe[T: ToString and Hash](value: T): String = value.to_string();
```

Constraints can also use generic trait forms (for example `Iterator[T]`), and the
three **shape constraints**. A shape constraint is a keyword, not a trait: no
declaration can implement it, and the compiler decides whether a type satisfies
it from the type's own declaration.

- `T: mutable` — the subject must have been declared `type mutable`. This is what
  weak references require (`x as ?T` / `?expr` spell it).
- `T: foreign` — the subject's representation is fixed outside Koral's layout
  freedom and may cross the FFI boundary: a built-in scalar, a `*` /
  `*mutable` pointer (to one of these, or to `Void` — C's `void*`), or a
  `type foreign` declaration. It is
  a **closed set**; a Koral `type` is not in it, because the compiler chooses its
  layout — and neither is std's `Rune`, a nominal like `String` whose
  representation is the compiler's business. This is what `List.borrow_ptr`
  / `borrow_mut_ptr` require.
- `T: sendable` — the subject may cross a thread boundary: declared `sendable`
  (safe or `unsafe` form), or derived — scalars qualify, composites follow the
  derivation rules (see [Concurrency](#concurrency)). This is what shared
  object fields, globals, and channels demand.

```koral
let consume[I: Iterator[Int]](iter: I): Void = {};
let read_bytes[T: foreign](buf: List[T]): *T = buf.borrow_ptr();
let drain[T: Reader and sendable](source: T): Int = source.read();
let bump[T: mutable and sendable](c: T): T = c;
let pass[T: foreign and sendable](x: T): T = x;
```

A generic parameter carries its own bounds into a call: inside `f[T: Any]`, a call
that needs the `mutable` constraint is rejected, because a bare `T` is not
declared `mutable`. Inside `g[T: mutable]` the same call is accepted. The
`sendable` constraint is just as strict: a bare `T: Any` does not forward into a
`U: sendable` slot, so the parameter must declare `T: sendable` itself.

A bound-constrained extension block only contributes members where the bound
actually holds. Given

```koral
given[T: Add[T] and Zero, R: Iterator[T]] LazyView[T, R] {
    public sum(self): T = { ... };
};
```

`sum` is a member of `LazyView` only for `T` that satisfy `Add[T] and Zero`.
A pipeline over `Pair[A, B]` satisfies neither, so it does not acquire `sum`,
and a call to it there is a type error. Constraints that are still open are not
rejections: for a generic conformance such as
`given[T: Any, R: Iterator[T]] FilterIterator[T, R]: Iterator[T]`, `T` may still
become `Int`, so `sum` remains available and is checked again at each call site.

#### Generic Methods

`given` blocks can also define generic methods:

```koral
given[T: Any] Option[T] {
    public map[U: Any](self, f: (T) -> U): Option[U] = self and then as v in f(v);
};
```

#### `Never` Type Restrictions

The `Never` type represents computations that never return (e.g., infinite loops, panics). It is the bottom type.

- `Never` cannot be used as a struct field type.
- `Never` cannot be used as an enum payload type.
- `Never` cannot be used as a function parameter type.
- `Never` may be used as a return type to indicate a function never returns.

### The `Self` Type

`Self` is a built-in type keyword that refers to the implementing type inside `trait` definitions, `given` blocks, and their method signatures. It is not a standalone type alias — it is resolved by the compiler to the concrete type that is implementing the trait.

- Inside a `trait` definition, `Self` represents the future implementing type.
- Inside a `given Type: Trait` block, `Self` is equivalent to `Type`.
- `Self` can appear in method parameter types, return types, and field types within trait/given contexts.

```koral
trait Eq {
    equals(self, other: Self): Bool;
};

type Point(x: Int, y: Int);

given Point: Eq {
    // Here Self resolves to Point, so `other: Self` is the same as `other: Point`.
    equals(self, other: Point): Bool = self.x == other.x and self.y == other.y;
};
```

### Memory and Resources

Koral provides efficient and safe memory management through declaration-site type semantics and compiler-managed layout.

#### Memory Model

- **`type`** (shallowly immutable): no identity, and no promise of value semantics. The compiler may use stack slots, registers, inline storage, hidden heap blocks or reference counting — whichever it can prove correct — because the sharing it introduces cannot be observed. Its cleanup is the synthesized field release; it cannot implement `Drop`.
- **`type mutable`** (shared object): identity is part of the semantics. Assignment and argument passing share the same object. Only explicitly declared `mutable` fields can be modified in place.
- **`type foreign`** (mutable value semantics): a C-layout value. Assignment and argument passing copy; the copy is modified in place through `let mutable`, `mutable` parameters and `*mutable T` links, and `self` is a plain copy — there is no mutable self. Its fields are always-writable C slots, and its contents are limited to types that cross the FFI boundary (see [External Interop](#6-external-interop)).
- **Raw pointers**: the pointer types are `*T` / `*mutable T`; `&` / `&mutable` are the address-of operators that form them, and only from addressable storage. They are low-level memory access for FFI and remain subject to address-stability and layout constraints (see [External Interop](#6-external-interop)).
- **Sharing across threads is a declared property too.** The model has a concurrency axis: which types may cross thread boundaries — and who guarantees their safety — is decided at the declaration site by the `sendable` family. See [Concurrency](#concurrency).
- **Reference counting is an implementation detail.** The compiler may use ARC and hidden storage internally for both forms. The language contract itself is stated under **The Core Idea: `type` / `type mutable`** in this manual.

#### `Drop`

Types that need a cleanup step declare `type mutable` and implement the `Drop` trait:

```koral
trait Drop {
    drop(self): Void;
};
```

`Drop.drop` is a compiler-only destructor entry point running in a finalization context. It is not called as an ordinary user method. **Only a `type mutable` can implement `Drop`**: the destructor runs once when the last owning handle dies, so it belongs to the shared-object layer. A `type` promises no identity — same-field values are interchangeable — and a destructor would leak construction identity through the drop count.

A `type` is instead cleaned up by its **synthesized field release** — the fields' own releases drive inner managed values to their final release, so a resource wrapped in a `type mutable` field still comes free with no user destructor (the Swift struct-around-class shape, e.g. `type File(inner: FileBox)`).

Because the destructor runs exactly once per object, a `Drop` type's sharing is **observable** — see [Memory Model](#memory-model). That is exactly why `Drop` is reserved for `type mutable`.

**`self` does not escape a `drop` body.** The object is being destroyed; letting it out would resurrect a dying value or move fields out from under the destructor. Inside `drop`, `self` may appear **only as the receiver** of a field read/write (`self.x`, `self.x = v`) or a method call (`self.close()`). It may not be returned, bound to a new name, stored into a field, collection or global, passed as an ordinary argument, or captured by a lambda.

```koral
trait Drop {
    drop(self): Void;
};

type mutable File(mutable fd: Int);

given File: Drop {
    drop(self): Void = {
        let n = self.fd;   // ok: field read
        self.fd = n;       // ok: field write (the field is `mutable`)
        // stash(self);    // error: `self` escapes the destructor
    };
};
```

A method call on `self` inside `drop` works like a field access. The destructor
hands `self` in as a pointer while the type system still calls it `Self`, so the
call site dereferences it. An ordinary method also takes its receiver by value,
which retains: the object is un-resurrectable for the duration of its own
destructor, so the retain and the method's matching release do nothing and the
destructor is not re-entered.

```koral
given File {
    close(self): Int = {
        return self.fd;
    };
};

given File: Drop {
    drop(self): Void = {
        println("closed: \(self.close())");
    };
};
```

#### `clone()`

Shared objects are never copied implicitly. When an independent copy is genuinely needed, ask for it explicitly with `clone()`:

```koral
trait Clone {
    clone(self): Self;
};
```

`List`, `Set`, `Dict` and `Deque` implement `clone()` as a **shallow** copy: the container itself is new, elements are copied one level, so nested `type mutable` elements stay shared.

```koral
let a = [1, 2];
let b = a.clone();
b.push(3);
// a is still [1, 2]
```

#### Weak References

Weak references do not keep the referent alive. They are written as `?T` and are only valid for types that satisfy the `mutable` constraint.

Use `x as ?T` to construct a weak reference (a handle wrap, not a bit reinterpretation). Use `?expr` to upgrade: the result is `Option[T]` — `.Some(v)` when the object is still alive, `.None()` when it is dead.

```koral
type mutable Node(mutable value: Int);

let node = Node(42);
let weak = node as ?Node;               // ?Node
let value = when ?weak in {
    .Some(v) then v.value,              // v is Node, only when alive
    .None() then 0,
};
```

**A weak reference is a handle, not a value.** Until it is upgraded it carries
no fields, no cases and no payload of the referent, so anything that tests or
exploits the referent's *shape* is refused against a `?T`:

- member access, read or write — `w.value`, `w.value = 1`
- a method call — `w.get()`
- destructuring — `let (a, b) = w`, `for (a, b) in ws`
- iteration — `for x in w`
- matching cases — `when w in { Box(x) then ... }`

Binding the handle *whole* is fine and keeps the `?T`:

```koral
let w = node as ?Node;
let w2: ?Node = w;              // ok: the handle is copied
let xs = List[?Node].new();
xs.push(w);
for h in xs then {             // ok: `h` is `?Node`
    when ?h in {               // the only way to reach the referent
        .Some(v) then { /* ... */ },
        .None() then {},
    };
};
```

### Concurrency

Concurrency safety in Koral is a **declaration-site property**, decided where a type is declared rather than where a value is passed — the same split as `type` versus `type mutable`. The `sendable` family of modifiers says which types may cross thread boundaries and who vouches for their safety: the safe forms are verified by the compiler and guarded by built-in locking, while the `unsafe` forms hand synchronization back to the developer. There is no borrow checker, and no second calling discipline to learn.

#### Declaring Sendable Types

The type-modifier slot takes `unsafe`? `sendable`? `mutable`?, giving six declaration forms:

| Declaration | Fields | Object lock | Meaning |
|---|---|---|---|
| `type` | — | none | thread-local value |
| `type mutable` | only `mutable` fields mutate | none | thread-local shared object |
| `type sendable` | every field `sendable` | none (shallowly immutable) | frozen data, safe to share |
| `type sendable mutable` | every field `sendable` | **built in** | shared mutation, compiler-guarded |
| `type unsafe sendable` | unconstrained | none | developer promises it is shareable |
| `type unsafe sendable mutable` | unconstrained | none | developer promises; synchronization is its own |

```koral
type sendable Point(x: Int, y: Int);

type sendable mutable Counter(mutable hits: Int);

type unsafe sendable mutable Mutex(private handle: *UInt8);

type sendable Shape {
    Circle(r: Float64),
    Rect(w: Float64, h: Float64),
};
```

Rules:

- `unsafe` must accompany `sendable`; `unsafe` alone is refused. The safe forms let the compiler verify the declaration; `unsafe sendable` turns verification off and hands the responsibility to the developer (see [`unsafe sendable`](#unsafe-sendable)).
- The safe forms **verify** their contents: every field — every enum payload — must itself be `sendable`. A wrong annotation is a compile error, not a hole.
- Nothing is inferred. A `type mutable` whose fields are all `sendable` is still not `sendable` unless its declaration says so.
- Enums take the immutable forms, `type sendable` and `type unsafe sendable`; `mutable` remains struct-only.
- `type foreign` cannot be marked at all — `type foreign sendable FX(a: Int32);` is refused with `foreign type cannot be marked sendable`. A foreign layout is C's and cannot promise thread sharing. Foreign values live inside `type unsafe sendable` trusted interiors or thread-local state (see [`unsafe sendable`](#unsafe-sendable)).
- Type aliases and `type intrinsic` cannot be marked. An alias follows the type it names.

#### Derivation Rules

Whether a composite type is `sendable` derives mechanically from its parts — a closed list:

- **Scalars** — `Bool`, the numeric types, `Rune` — are always `sendable`.
- **Nominal types** are `sendable` exactly as declared.
- **Generic types**: `X[A, B]` is `sendable` only if `X` is declared `sendable` **and** every type argument is `sendable`. This condition applies to the `unsafe` forms too — otherwise a sendable container could smuggle non-sendable values across a boundary.
- **Enums**: declared `sendable` and every payload type `sendable` (`unsafe` skips the payload check).
- **Function types**: `sendable (A) -> R` is a distinct form. A function value with no captures qualifies naturally; a lambda qualifies only when **every** capture is `sendable`. A bare generic parameter is not `sendable` by default — capturing `x: T` of `f[T: Any]` in a `sendable` closure is refused (`sendable closure cannot capture non-sendable value 'x'`), and a `T: sendable` bound (or a `trait sendable` bound) is what admits it. A `sendable` function value converts to the plain form, never the reverse. The qualifier applies only to function types.

```koral
let run(f: sendable () -> Void): Void = f();

let main(): Void = {
    let n = 40;
    run(() => println("plain"));           // no captures
    run(() => println("capture \(n)"));    // `n` is sendable
};
```

- **Trait objects**: a trait object is `sendable` exactly when its trait is declared `trait sendable`; a plain trait's objects are never `sendable`. See [Trait Sendability](#trait-sendability).
- **Weak references**: `?T` is `sendable` exactly when `T` is.
- **Fixed-size arrays**: `[N]T` is `sendable` exactly when `T` is.
- **Never `sendable`**: raw pointers `*T` / `*mutable T`, foreign function pointers `foreign (A) -> R`, and `type foreign` values. Memory shared across the FFI goes through an `unsafe sendable` wrapper instead.

#### Trait Sendability

A trait's sendability is declared on the trait itself: `trait sendable Foo` declares a trait whose objects are **always** `sendable`. The guarantee is paid for at the `given` — **every** implementation must itself be `sendable` (safe or `unsafe` form), checked where the implementation is declared.

```koral
trait sendable Speak {
    speak(self): Int;
};

type sendable Robot(id: Int);

given Robot: Speak {
    speak(self): Int = self.id;
};

let greet(s: Speak): Int = s.speak();

let main(): Void = {
    let obj: Speak = Robot(7);    // `Speak` objects are sendable — they cross
    println(greet(obj));
};
```

An implementation that is not `sendable` is refused at the `given`: `Type 'Human' must be sendable to implement sendable trait 'Speak'`. A generic implementation must prove every admitted instantiation the same way — spell the proof in the bounds, `given[T: sendable] Box[T]: Speak`, or the `given` is refused with `Type 'Box[T]' must be sendable to implement sendable trait 'Speak'; give its generic parameters 'sendable' bounds`. The declaration is the single proof point: a `Speak` object is never re-checked at the boxing site, because every implementation is already known to be `sendable`. Inheritance demands the same explicitness — a trait that extends a `sendable` trait must declare `sendable` itself, or the always-sendable object family would grow a non-sendable branch: `Trait 'Child' extends sendable trait 'Base' and must be declared sendable`. Nothing is inferred.

A trait declared without `sendable` keeps non-sendable objects, and there is no type-position qualifier to change that: `sendable Trait` is refused with `'sendable' qualifier applies only to function types; declare the trait 'sendable' instead` — `sendable` in type position qualifies function types only (see [Derivation Rules](#derivation-rules)). There is no `unsafe sendable trait` form either: implementation types carry their own safe / `unsafe` forms, and a `trait sendable`'s objects are `sendable` either way.

**Mixed traits.** When the trait you need is not `sendable`, its objects stay thread-local and the behavior crosses in one of two ways. The mainstream one is generic parameterization — demand the trait and sendability together with the composable kind bound (see [Generic Constraints](#generic-constraints)):

```koral
trait Reader {
    read(self): Int;
};

type sendable Msg(len: Int);
type Plain(len: Int);          // not sendable

given Msg: Reader {
    read(self): Int = self.len;
};

given Plain: Reader {
    read(self): Int = self.len;
};

let drain[T: Reader and sendable](source: T): Int = source.read();

let main(): Void = {
    println("read \(drain(Msg(3)))");
    // drain(Plain(1));
    //     error: Type 'Plain' does not satisfy the 'sendable' constraint
};
```

The second path wraps the object in an `unsafe sendable` type that vouches for it — the promise is yours, as with every `unsafe` form:

```koral
type unsafe sendable SharedReader(inner: Reader);
```

**Errors are one form.** `Error` is declared `trait sendable Error`: every error type must be `sendable`, checked at its `given`, and `Result`'s error side is the plain `Error` trait object — there is no separate sendable spelling. Errors describe failure as values and routinely travel inside `Result` across threads, so their shared nature is declared once, where the error type is declared.

#### Crossing Thread Boundaries

A value crosses threads in only a few ways — it is captured by a spawned closure, stored into a shared object's field, stored into a global, or buffered through a channel. Each route is checked where the value is declared or formed, never in ordinary function signatures:

| Checked at | Rule |
|---|---|
| spawn — `run_task` / `Task` | the closure is `sendable () -> Void`; non-`sendable` captures are refused at the call |
| closure formation | a `sendable` function type accepts only `sendable` captures |
| shared object fields | safe `sendable` forms verify every field at the declaration |
| globals | the type must be `sendable`; a `let mutable` global's slot locks per variable (see [Object Locks](#object-locks)) |
| channel buffers | `Channel[T]` is `sendable` only when `T` is, so a non-sendable message type is refused where the channel is typed |
| trait declarations / `given` blocks | `trait sendable` makes its objects always `sendable`, and every implementation must be `sendable` (see [Trait Sendability](#trait-sendability)) |
| method parameters and returns | **not checked** — any type is allowed |

Everything outside that table is unconstrained: an ordinary function may accept and return any type, `sendable` or not, and passing values between ordinary calls on one thread asks nothing of them. A closure that reaches for the wrong capture is refused where the `sendable` function type is formed:

```koral
type mutable Local(mutable n: Int);

let run(f: sendable () -> Void): Void = f();

let main(): Void = {
    let v = Local(1);
    // run(() => println("captured \(v.n)"));
    //     error: sendable closure cannot capture non-sendable value 'v'
};
```

#### Object Locks

A safe `type sendable mutable` object carries built-in synchronization, applied **per access** by field kind. All of it is sequentially consistent:

| Access | Field kind | Protocol |
|---|---|---|
| read | non-`mutable` field | plain read (immutable after construction) |
| read | `mutable` scalar field (integers, floats, `Bool`, raw pointers, payload-free enums) | atomic load |
| read | reference-typed or multi-word field | read under a short lock (the handle copy's `retain` stays inside) |
| write | scalar field | atomic store |
| write | reference-typed or multi-word field | write under a short lock; the old value is released **after** the unlock |

- **Assignments evaluate left to right: the left path and subscripts first, then the right-hand side, then the write.** The right-hand side runs outside every lock; the lock (or atomic store) covers only the final write. This order is the same for ordinary `type mutable` values.

```koral
type sendable mutable Counter(mutable hits: Int);

let main(): Void = {
    let c = Counter(0);
    c.hits = c.hits + 1;   // a read, then a write — NOT atomic across threads
};
```

- **`op=` is two steps, not atomic.** `x.f += e` reads `x.f` (per the read protocol), applies `+` through the operator — built-in arithmetic or trait overloading, so generic code sees the same implementation — and writes back (per the write protocol). A concurrent increment belongs to `AtomicCell.update_and_get` or a `Mutex`, not to `+=`.
- **The lock is not reentrant — it never needs to be.** At most one short lock is held at a time: intermediate path reads take and release their own locks, the right-hand side holds nothing, and the old value is released after the unlock, so a destructor calling back into the host object cannot deadlock.
- **Locks are per object.** A nested path `a.b.c` locks each owner separately on the way down; a right-hand side that touches *another* object takes that object's lock as well — lock ordering across objects stays yours to design.
- **Each `let mutable` global follows the field rules**: atomic load/store for a scalar slot, a short lock for a reference or multi-word slot, right-hand side outside, old value released after the unlock.
- Taking the **address of a field** of a locked object is refused — a raw pointer would route around the protocol.

What object locks deliberately do **not** promise — the same boundary Rust, Go, and Swift draw:

- **No cross-access atomicity.** One access — one read or one write — is the atomicity unit. A compound operation across accesses is not atomic: `x.f = x.f + 1` is a read and a write. When a wider atomic step is genuinely needed, use `AtomicCell.update_and_get`, or keep the state under a `Mutex` of your own in an `unsafe` form.
- **No explicit lock blocks.** The language offers no second critical-section spelling.
- **No deadlock freedom.** Short locks can still deadlock against `std` locks through user code.
- **No memory-ordering promises** beyond sequential consistency for these accesses and what the atomic APIs state.

#### `unsafe sendable`

The `unsafe` forms are the escape hatch for types the compiler cannot verify: synchronized primitives, FFI handles, lock-free designs.

```koral
type unsafe sendable mutable Mutex(private handle: *UInt8);
```

The contract: **the developer promises that the type, and everything reachable from it, is free of data races when shared across threads.** The compiler does no field checking and adds no locks. Atomic reference counting protects only the counters themselves — races on fields, and on the counters of reachable non-`sendable` objects, are part of the promise. **A broken promise is undefined behavior.**

Reach for `unsafe sendable` when the type brings its own synchronization (`Mutex`, atomic cells, thread-safe FFI handles) — not to silence a check that has not actually been satisfied.

#### Self-Synchronized Primitives

The `std` primitives that bring their own synchronization — `AtomicCell`, the `ConcurrentDict` / `ConcurrentSet` / `ConcurrentDeque` containers, `Lazy`, and global initializers — run a fixed discipline, and the shape of every operation is part of its name (the same name always means the same thing, in every type):

- **Single-step operations hold their lock for exactly one step.** `AtomicCell.get` / `set` / `swap` / `compare_exchange` and each `Concurrent*` operation are one linearizable step. Inside the lock, the only user code allowed is an element's `hash` / `eq` (a dict key's, or `compare_exchange`'s `Eq`) — and those must be **pure functions**: no side effects, no locks, no calling back into anything. This is a contract, not a checked restriction; violating it breaks the guarantee.
- **Destructors never run inside these locks.** A displaced or deleted value is released after the unlock — a `Drop` body is user code like any other and may call back into the world.
- **`update_and_get` runs its callback outside the lock**, on `AtomicCell` and `ConcurrentDict` alike. The callback therefore **may run more than once** — the update is optimistic, committed only when the snapshot still validates — and must not have side effects outside the value it computes. Reading the object from the callback is fine. **Writing the object the callback updates panics** (`AtomicCell.update_and_get: the updater wrote the same cell`, `ConcurrentDict.update_and_get: the updater wrote the same container`) instead of retrying forever. Ordinary contention simply retries: there is **no attempt limit** and no guarantee of finishing in a bounded number of steps. A `ConcurrentDict` update validates per entry, so a write to a *different* entry never invalidates it.
- **One-time initialization** — `Lazy` and global initializers — runs the initializer **outside any lock**, at most once; other threads wait for the value to be published. A `Lazy[T]` publishes `T` to any thread that calls `get`, so `T` is constrained `sendable`, exactly like `AtomicCell`'s. An initializer that re-enters its own value on the same thread panics with the cycle spelled out (`global initialization cycle: a -> b -> a`, `Lazy.get: the initializer called get() on the same Lazy`). **Cross-thread cycles are not detected**: two threads initializing two values that need each other simply deadlock — that shape is documented, not diagnosed.
- **The explicit primitives** — `Mutex`, `SharedMutex`, `Semaphore`, `Channel`, `LatchGate` — are your own critical sections. Anything may run inside, including callbacks and destructors, and deadlock freedom is the programmer's responsibility.

#### Frozen Collections

The mutable containers — `List`, `Dict`, `Set`, `Deque`, `StringBuilder`, and the iterators — are `type mutable` thread-confined working state: none of them is `sendable`, and none of them crosses a boundary. The cross-thread story for collection **data** is to build in mutable containers and **freeze at the boundary**: `FrozenList[T]`, `FrozenDict[K, V]`, and `FrozenSet[T]` are immutable snapshots that may cross threads.

A snapshot is carried by a `type unsafe sendable mutable` object — the `mutable` form is where the owned buffer and its destructor live (user destructors are `type mutable` only), and the construction-then-immutable promise keeps the snapshot read-only in practice — with **independent storage** of its own (it does not embed the source container). The conditional rule still applies: `FrozenList[T]` is `sendable` only when `T` is, so `FrozenList[List[Int]]` cannot cross.

```koral
let source = List[Int].new();
source.push(2);
source.push(4);
source.push(6);
let frozen = source.to_frozen_list();    // copies into independent storage
```

- Convert with `List.to_frozen_list()` / `Dict.to_frozen_dict()` / `Set.to_frozen_set()`; the source stays usable afterwards. Copy back out with `to_list()` / `to_dict()` / `to_set()`. A lazy pipeline collects the same way: `view.to_frozen_list()` / `view.to_frozen_set()`.
- The read halves are `count`, `is_empty`, `get`, `contains` (`contains_key` on dicts), and `iterator`. There are **no mutation methods and no builders** — the snapshot is written once at construction and never touched again.
- Built-in subscripts read snapshots: `frozen[i]` and `frozen_dict[key]` behave exactly like `List[i]` and `Dict[key]` (same out-of-range / missing-key panics), and assigning to them is a compile error. `FrozenSet` has no subscript.
- Collection literals target the frozen family through type context, with the mutable rules carried over — set literals dedup, dict literals keep the last duplicate key, `[]` needs context:

```koral
let f: FrozenList[Int] = [1, 2, 3];
let d: FrozenDict[String, Int] = ["a": 1];
let s: FrozenSet[Int] = [1, 2, 2];        // dedup: two elements
let empty: FrozenList[Int] = [];
```

A snapshot travels like any other `sendable` value — captured by a spawned closure, stored in a shared field, or sent through a channel:

```koral
using "std/async" { ... };
using "std/sync" { ... };

let main(): Void = {
    let source = List[Int].new();
    source.push(10);
    let frozen = source.to_frozen_list();

    let (sender, receiver) = make_channel[FrozenList[Int]](1);
    let worker = run_task(() => {
        let got = receiver.recv().unwrap();
        println("worker got \(got.count()) \(got[0])");
    });
    let _ = sender.send(frozen);
    let _ = worker.wait();
};
```

`JsonValue` sits on the frozen tree: it is a `type sendable` enum whose `Array` and `Object` payloads are `FrozenList[JsonValue]` and `FrozenDict[String, JsonValue]`, so a parsed document crosses threads directly — `Channel[JsonValue]` works. `as_array()` and `as_object()` hand the frozen payloads out as `Option[FrozenList[JsonValue]]` and `Option[FrozenDict[String, JsonValue]]`; parsing and building stay on the mutable side.

#### Workers and Channels

The recommended shape for concurrent code: keep each thread's state **thread-confined** — it may stay plain, even non-`sendable`, since nobody else can see it and it needs no locks — and pass `sendable` messages between threads over channels. Collection data rides along as frozen snapshots (see [Frozen Collections](#frozen-collections)). A channel is conditionally `sendable` in its message type, so a non-sendable message type is refused where the channel is declared, not where messages flow.

```koral
using "std/async" { ... };
using "std/sync" { ... };

type sendable Msg {
    Job(id: Int),
    Quit(),
};

let main(): Void = {
    let (sender, receiver) = make_channel[Msg](16);

    // The tally is thread-confined; only `Msg` crosses threads.
    let worker = run_task(
        () => {
            let mutable total = 0;
            while true then {
                when receiver.recv() in {
                    .Ok(msg) then {
                        when msg in {
                            .Job(id) then {
                                total = total + id;
                            },
                            .Quit() then {
                                break;
                            },
                        };
                    },
                    .Error(_) then {
                        break;
                    },
                };
            };
            println("total \(total)");
        },
    );

    let _ = sender.send(Msg.Job(1));
    let _ = sender.send(Msg.Job(2));
    let _ = sender.send(Msg.Quit());
    let _ = worker.wait();
};
```

Shared mutable objects with object locks are the second form of concurrency; synchronized primitives you trust are the `unsafe` form. Closing the channel is the other way to end a worker: when the last `SendChannel` handle is dropped, `recv()` reports `.Error` once buffered messages are drained.

**Reference counting follows sendability, but that is not part of the language contract.** `sendable` types use atomic reference counting and non-`sendable` types non-atomic; rely on neither — it is an implementation detail, like layout, and may change.

## 4. Pattern Matching

Koral has powerful pattern matching capabilities, mainly used through `when` expressions and the `is` operator. Patterns are also the binding form used in `if` and `while` conditions, and the binding a `for` loop takes (see [for Loop](#for-loop)).

### Pattern Forms

Supported patterns include:

- Wildcard pattern: `_` (matches any value)
- Literal patterns: `1`, `-5`, `1.5`, `-2.25`, `"abc"`, `'a'`, `true` (negative numeric literals such as `-5` are supported)
- Variable binding patterns: `x` (matches any value and binds to x), `mutable x` (mutable binding)
- Comparison patterns: `> 5`, `< 0`, `>= 10`, `<= -1`, `> 1.5`, `>= 'a'`
- Struct destructuring patterns: `Point(x, y)`, `Rect(Point(a, b), w, h)`
- Tuple destructuring pattern: `(a, b, c)` — positional destructuring of a struct with exactly that many fields (`Pair` included, being a two-field struct); at least two slots
- List destructuring patterns: `[]`, `[a, b]`, `[a, ...]`, `[a, ..., b]`, `[...]` — destructures a `List[T]` by length
- Rest pattern: `...` — ignores slots (the unwritten middle in a list, the whole element list in a struct or enum case); see below
- Enum case patterns: `.Some(v)`, `.None()`
- Trait-object exact type patterns: `IoError`, `err: IoError`
- (removed: weak binding patterns `?v` / `?Node(v)` — use `?expr` to get `Option[T]`; construction is `x as ?T`)
- Logical patterns: `pattern and pattern`, `pattern or pattern`, `not pattern`
- `is` chains: `x is A or is B`, `x is A and is not B` — several tests on one subject, joined by the connectors `or is` / `and is`

A literal matches exactly the types its `==` would accept: integers against
integer types (`-5` never matches an unsigned type), floats against `Float32` /
`Float64`, `true` against `Bool`, strings against `String`, runes against
`Rune` (or an ASCII `UInt8`). A float literal matches under IEEE equality at
the subject's width (`1.1` against `Float32` is `Float32(1.1)`), so `NaN` matches
no literal -- catch it with a guard such as `v where v != v` -- and `0.0` matches
`-0.0`. A comparison bound follows the same kind rule: `> 1` is an integer
bound, `> 1.0` a float one, `> 'a'` a rune one (compared by code point). A
bound may lie outside the subject's domain (`>= -1` on `UInt8` matches
everything).

Destructuring follows exactly the call rules: a field declared named must be
matched by label, and a field declared positional must not be.

#### List Patterns and the Rest Pattern

A list pattern destructures a `List[T]` by length. Each slot is checked against
`T`, and a binding is exactly `let name = subject[i]`. Without a rest slot the
length must match exactly; with one the written slots become a lower bound:

```koral
[]              // only the empty list
[a, b]          // only a two-element list
[a, ...]        // length >= 1, the first element bound to a
[..., b]        // length >= 1, the last element bound to b
[a, ..., b]     // length >= 2, first and last bound
[...]           // any list -- the same as `_`
```

The rest pattern `...` only **ignores** slots: it never binds, so `...x` is an
error, and it is only ever a slot of an element list — at most one per list.
Everywhere else (`...` as a whole arm, under `not`, alone in `( ... )`) it is
refused.

It means different things in the two kinds of element list. In a **list**
element list it swallows the unwritten middle and may sit alongside the written
slots (see the table above). In a **struct or enum-case** element list it is
whole-list elision: it must be the element list's **only** slot, and it ignores
every field — named or not:

```koral
Point(...)      // the same as Point(_, _, _)
.RGB(...)       // the same as .RGB(_, _, _)
Button(...)     // named fields too: the same as Button(_, height = _, label = _)
```

To ignore only some fields, write `_` for each one and do not mix it with `...`:
`Point(x, _, y)`, not `Point(x, ..., y)`. A tuple pattern takes no rest slot at
all (`( ... )` is the parenthesized-pattern error).

List patterns take part in exhaustiveness by length. A pattern covers a length
completely only when **every** slot is irrefutable, so `[]` and `[x, ...]`
together cover every list, while `[1, ...]` does not (it misses a list whose
head is not 1). In a struct or enum-case pattern the rest marker changes
nothing: the field count is fixed, so it is the whole row of `_`.

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start = p, end = e) then println(p.x),
};

if b is Button(w, height = _, label = l) then println(l);
```

Logical combinators carry rules about what a pattern may bind:

- `a and b` runs both sides, so the two sides must not bind the same name -- one
  name would end up with two different values.
- `a or b` matches one side or the other, so both sides must bind the same names,
  and a name must mean the same type on both sides.
- `not p` matches by the absence of a shape, so `p` must not bind anything.

The two sides of an `or` may still place a name differently. Each branch reads
its own layout, so `a` and `b` below come from whichever branch matched.

```koral
type E {
    A(a: Int, b: Int),
    B(a: Int, mid: Int, b: Int),
};

when e in {
    .A(a, b) or .B(a, _, b) then a + b,
};
```

### `when` Expressions

The `when` expression allows you to compare a value against a series of patterns and execute corresponding code based on the matching pattern. It is similar to `switch` statements in other languages, but more powerful. `when` is always an expression. It returns the value of the matching branch; a single-branch `when` has its branch's type (the patterns must still cover every value). Used as a statement, it produces `Void`.

```koral
let x = 5;
let result = when x in {
    1 then "one",
    2 then "two",
    _ then "other",
};
```

An arm body may also be a bare control transfer — `1 then return 31` is sugar for `1 then { return 31; }` (see [Branch Bodies and Control Transfers](#branch-bodies-and-control-transfers)).

An arm may carry a guard: `pat where cond then body`. The pattern's bindings are
visible in `cond`, the guard is evaluated before the branch body, and a false
guard falls through to the next arm. The guard is part of the arm, never of a
sub-pattern -- `a or b where c` reads `(a or b) where c` -- but its evaluation
is **backtracking**: when the arm pattern offers several readings through
`or`, each reading binds its own values and the guard is re-evaluated on those
bindings. The leftmost reading whose guard accepts wins; a refused guard falls
through to the next reading of the same arm, and only when every reading is
refused does the arm fail and the next arm get its turn. A guard must be `Bool`.
`for` uses the same keyword in the same slot (see [for Loop](#for-loop)); the
retired `if` spelling is rejected with a message naming `where`.

```koral
let kind = when v in {
    .Some(n) where n > 0 then "positive",
    .Some(n) where n < 0 then "negative",
    .Some(n) then "zero",
    .None() then "empty",
};
```

A guarded arm covers nothing for exhaustiveness (see [Exhaustiveness
Checking](#exhaustiveness-checking)): the `when` above is complete because of
the unguarded `.Some(n)` and `.None()` arms, not because of the guarded ones.

The guard's `is` conjuncts bind, exactly like an `if`/`while` condition's (see
[`is` Expressions](#is-expressions)): `where o is .Some(w) and w > 0` binds `w`
from the first step and the rest of the guard reads it, and the names stay
visible in the branch body. The same restrictions apply -- bindings under
expression `or`/`not` and in `is not` are rejected.

A pattern binding is scoped to its own branch. Inside the branch it names the
matched payload; outside the `when` it does not exist, and an outer binding of
the same name keeps its meaning. Different branches may reuse a name freely --
their bindings are independent.

```koral
let f(s: Shape, radius: String): String = {
    let mutable inner = "";
    when s in {
        // `radius` here is the payload of `Circle`.
        .Circle(radius) then { inner = radius.to_string(); },
        _ then { inner = "none"; },
    };
    // `radius` here is the `String` parameter again.
    return radius + "/" + inner;
};
```

Like `if`, a block branch in `when` uses its final expression as the branch value.

```koral
let label = when score in {
    100 then {
        println("bonus");
        "perfect"
    },
    >= 90 then {
        if has_curve(score) then {
            "A+"
        } else {
            "A"
        }
    },
    _ then { "other" },
};
```

Further examples:

```koral
// Enum type matching
type Shape {
    Circle(radius: Float64),
    Rectangle(width: Float64, height: Float64),
};

let area = when shape in {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
};

// Comparison patterns
let grade = when score in {
    >= 90 then "A",
    >= 80 then "B",
    >= 70 then "C",
    _ then "F",
};

// Logical patterns
when x in {
    1 or 2 or 3 then println("small"),
    _ then println("big"),
};

// Struct destructuring patterns
type Point(x: Int, y: Int);
type Rect(origin: Point, width: Int, height: Int);

let p = Point(10, 20);
when p in {
    Point(x, y) then println(x + y),  // 30
};

// Nested struct destructuring
let r = Rect(Point(1, 2), 30, 40);
when r in {
    Rect(Point(a, b), w, h) then println(a + b + w + h),  // 73
};

// Struct destructuring in if...is
if p is Point(x, y) then {
    println(x * y);  // 200
};

// Exact trait-object implementation type matching
trait Problem {
    render(self): String;
};

type IoError(code: Int);

given IoError: Problem {
    render(self): String = "io";
};

let err: Problem = IoError(7);
when err in {
    io: IoError then println(io.render()),
    _ then println("other"),
};

// Wildcard and literal field matching
when p in {
    Point(0, y) then println(y),  // Match when first field is 0
    Point(_, y) then println(y),  // Ignore first field
};

// Generic struct destructuring
type Box[T: Any](val: T);
let b = Box[Int](42);
when b in {
    Box(v) then println(v),  // 42
};
```

### `is` Tests

The `is` operator checks whether a value matches a pattern, and the result is always `Bool`. It is a general-purpose expression and can appear in `let` initializers, return expressions, function arguments, and other expression positions.

`is not` is the negated form and returns the inverse match result.

When used in the condition of an `if` or `while` expression, a successful `is` match can also bind variables from the pattern into the current scope. Outside those condition contexts, `is` may only perform a boolean test and may not introduce bindings. The `when ... in` construct uses its own pattern matching on the matched value and does not use `is` for binding.

`is` accepts a single pattern directly. Several tests on one subject join with the two-token connectors `or is` / `and is`, forming one pattern: `x is A or is B` is `x is (A or B)`, so the two sides share bindings the way a `when` arm's `or` does. `and is` binds tighter than `or is`, and the whole chain binds tighter than the expression-level `and` / `or` — so `a is x or is y and b > 1` reads `(a is x or is y) and (b > 1)`. A connector is only one when it is followed by `is`; a bare `or` / `and` is the expression operator.

`(` in pattern position opens a tuple pattern (`is (a, b)`) and never groups a single pattern. For a chain, use `or is` / `and is`.

```koral
let opt = Option[Int].Some(42);
let has_value = opt is .Some(_);
let is_empty = opt is not .Some(_);

if opt is .Some(v) then {
    println(v);  // 42
};

// Comparison pattern
if score is >= 60 then {
    println("passed");
};

// `is` chain: one subject, several patterns
if argv is [] or is [_, ...] then {
    println("no arguments, or only the program name");
};

let p = Point(1, 2);
if p is Point(_, _) and is not Point(0, 0) then {
    println("a point, but not the origin");
};

if x is 0 or is 1 then {
    println("small");
};

// Standard boolean composition still works in conditions
if opt is .Some(v) and v > 0 then {
    println(v);
};
```

### Lazy Pipelines

Iteration splits into two roles:

- **`Iterator[T]`** is a **cursor**. It is one-shot and has exactly one method,
  `next(self): Option[T]`. Nothing on it observes without advancing, so no call
  can quietly spend it while pretending to ask a question. Handing a cursor to
  `for` walks it to the end.
- **`Iterable[T, R]`** can hand out a **fresh cursor on every call**
  (`iterator(self): R`): containers, ranges, and every lazy pipeline.

A lazy pipeline is entered through `lazy()` and never leaves: it returns a
`LazyView`, and each adapter returns another `LazyView`, so a chain is written
once. Nothing lazy is spelled on the container
itself — `dict.take(key)`, `string.find(pat)`, `list.first()` and friends keep
the container's own meaning, and names like `map`, `filter`, `to_list` and
`collect` on a container are left free for a future eager API.

```koral
let view = list.lazy().filter((x) => x > 0).map((x) => x * 2);

view.count();        // builds a cursor, walks it, drops it
view.is_empty();     // looks at one element, drops the cursor
view.to_list();      // [2, 4, 6]
view.count();        // 3 -- the pipeline was never spent

list.count();        // the container's own O(1) count
```

`lazy()` is a door, not a wrapper: it is written once, on the container, and a
`LazyView` has no `lazy()` to repeat — the chain it hands back is already
lazy. A `LazyView` is a value — nothing in it mutates — so binding one to a
name and using it twice agrees with itself.

Its signature is `LazyView[T, R]`: the element type and the cursor type the
pipeline will hand out. It holds a cursor factory rather than a source, so the
chain does not pick up a type parameter per stage and no per-stage view type
exists. The cursor that comes out is an ordinary monomorphized `Iterator`, so
`next` on it is a direct call.

A cursor is a different thing: `list.iterator()` names one position, and
pulling from it advances it. To run a pipeline over a one-shot source (a file's
lines, a socket), collect it into a list first.

Sources that describe a walk rather than a position hand back an `Iterable`
**view**, and pipelines chain straight off it through `lazy()`: `string.split(sep)`,
`string.lines()`, `string.bytes()`, `string.runes()`,
`string.split_ascii_whitespace()`, `dict.keys()`, `dict.values()`,
`regex.find_all(text)`, `regex.captures_all(text)` and `regex.split(text)`.
A view is never spent — `for` and every pipeline start from a fresh cursor —
while one-shot sources stay cursors: `read_dir` and `walk_dir` advance an OS
handle and hand out nothing repeatable.

### Conditions and Loop Bindings

`if` and `while` conditions integrate `is` bindings, which is the idiomatic way to consume iterators and to destructure in place.

```koral
let opt = Option[Int].Some(42);
if opt is .Some(v) then {
    println(v);  // 42
} else {
    println("None");
};

let mutable iter = list.iterator();
while iter.next() is .Some(v) then {
    println(v);
};
```

Multiple conditions use standard `and` / `or` / `not` composition. When the left side of an `and` is an `is` match with bindings, those bindings are available to later `and` clauses and to the `then` branch:

```koral
if foo() is .A(x) and bar(x) is .B(y) and y > 0 then {
    println(y);
} else {
    println("no match");
};

while iter.next() is .Some(item) and parse(item) is .Ok(v) then {
    println(v);
};
```

Rules for condition composition:

- Conditions are evaluated left-to-right with normal short-circuiting.
- Bindings introduced by earlier `is` clauses are available in later `and` clauses and in the `then` branch.
- Bound `is` matches are not allowed under `or` branches or beneath `not`.
- For `while` conditions, clauses are also left-to-right and short-circuiting. When a clause fails, the loop terminates.

### Logical Pattern Combinators

Patterns combine with `and`, `or` and `not`:

```koral
when temperature in {
    > 0 and < 100 then "liquid",
    <= 0 then "solid",
    >= 100 then "gas",
};
```

Under `is`, group combinators with parentheses:

```koral
if x is 0 or is 1 then {
    println("small");
};
```

### Exhaustiveness Checking

The `when` expression checks that patterns are exhaustive:

- For `Bool` types, both `true` and `false` must be covered (or a wildcard used).
- For `enum` types, all cases must be covered (or a wildcard used).
- For `Int` / `UInt` types, comparison patterns (`> 0`, `<= 0`, etc.) can establish exhaustiveness when they fully cover the integer range. A wildcard is otherwise required.
- For float and `Rune` types, literal and comparison patterns contribute no coverage -- there is no finite domain to close -- so a wildcard or variable binding is required.
- For struct types, `StructName(_, _)`-style patterns with wildcards for every field are treated as exhaustive.
- Duplicate patterns are rejected at compile time.
- Unreachable patterns (patterns already covered by earlier arms) are rejected at compile time. Wildcard and variable binding patterns are exempt from this check.
- A guarded arm (`pat where cond then ...`) covers nothing: the guard may fail, so the arm is never relied on for exhaustiveness. Cover the same pattern with an unguarded arm, or use a wildcard.

```koral
// Exhaustive via comparison patterns
let classify(x: Int): Int = when x in {
    > 0 then 1,
    <= 0 then 0,
};
```

### Exact Type Patterns

Trait objects also support exact implementation-type testing through the pattern system.

```koral
trait Problem {
    render(self): String;
};

type IoError(code: Int);
type NetError(code: Int);

given IoError: Problem {
    render(self): String = "io";
};

given NetError: Problem {
    render(self): String = "net";
};

let err: Problem = IoError(7);

if err is IoError then {
    println("io");
};

if err is io: IoError then {
    println(io.render());
};

let label = when err in {
    io: IoError then io.render(),
    _ then "other",
};
```

Rules:

- Exact type patterns are only valid when the subject is a trait object.
- The target must be a concrete type name.
- Matching is exact on the implementation type and its generic arguments.
- The subject stays a trait object; it is not auto-dereferenced to the implementation value. `err is io: IoError` binds `io` as `IoError`.
- These patterns are open-world tests; in `when`, they do not count as exhaustive coverage, so a default `_` arm is still required.

## 5. Abstraction

Koral uses Traits to define shared behavior. This is similar to interfaces or type classes in other languages.

### Traits and `given` Blocks

#### Defining a Trait

A Trait defines a set of method signatures that any implementing type must provide.

```koral
trait Printable {
    to_string(self): String;
};
```

Traits support inheritance using parent Trait names:

```koral
trait Ord: Eq {
    compare(self, other: Self): Int;
};
```

Multiple parent Traits are connected with `and`:

```koral
trait MyTrait: Eq and Hash {
    my_method(self): Int;
};
```

#### Implementing a Trait

Use a `given Type: Trait { ... }` impl block to implement a Trait for a specific type:

```koral
trait Eq {
    equals(self, other: Self): Bool;
};

trait Ord: Eq {
    compare(self, other: Self): Int;
};

type Point(x: Int, y: Int);

given Point: Eq {
    equals(self, other: Point): Bool = self.x == other.x and self.y == other.y;
};

given Point: Ord {
    compare(self, other: Point): Int = self.x - other.x;
};
```

Notes:

- `given Type: Trait` is the explicit conformance entry point.
- Parent/child traits are implemented level-by-level: implementing `Ord` does not implicitly implement `Eq`.

#### Named Parameters in Traits and Implementations

Trait methods support named parameters. Implementations must match the trait's parameter classification:

- If a trait method parameter is named (`name: Type =`), the implementation must also declare it as named (it keeps the `=` marker and does not repeat a default).
- If a trait method parameter is positional (`name: Type`), the implementation must also declare it as positional.

Default value rules for trait and given:

- If the trait declares a default value for a named parameter, the given implementation **must not** redeclare it. The trait is the single source of defaults.
- If the trait declares no default value, the given implementation **cannot** add one.

```koral
trait Drawable {
    draw(self, color: String =, thickness: Int =): String;
};

type Circle(radius: Int);

given Circle: Drawable {
    // 'color' and 'thickness' are named, matching the trait
    draw(self, color: String =, thickness: Int =): String = color + thickness.to_string();
};
```

#### Method Receiver Forms

- `self` is the only receiver form.
- For `type` (shallowly immutable), `self` is an immutable receiver.
- For `type mutable` (shared objects), `self` is a receiver that can modify explicit `mutable` fields.

### Trait Tool Methods

Koral supports `given Trait { ... }` for trait tool methods.

Rules:

- Methods declared inside `trait` are **requirements** (used for conformance checks and dynamic dispatch through trait objects).
- Methods declared inside `given Trait` are **tool methods** (ergonomic helpers), and are **not** requirement witnesses.
- Tool methods are not merged into a concrete type's inherent method set; they participate in call resolution based on context.

Example:

```koral
trait Eq {
    equals(self, other: Self): Bool;
};

given Eq {
    not_equals(self, other: Self): Bool = not self.equals(other);
};

type Num(x: Int);

given Num: Eq {
    equals(self, other: Num): Bool = self.x == other.x;
};

let a = Num(1);
let b = Num(2);
println(a.not_equals(b));
```

Constrained tool block example:

```koral
trait Cursor[T: Any] {
    next(self): Option[T];
};

given[T: Ord] Cursor[T] {
    max(self): Option[T] = {
        let mutable best = self.next();
        while self.next() is .Some(v) then {
            best = when best in {
                .Some(b) then if v > b then Option[T].Some(v) else Option[T].Some(b),
                .None() then Option[T].Some(v),
            };
        };
        return best;
    };
};

// For types implementing Cursor[Int], max is available
```

Dispatch rules:

- Requirement methods: witness/vtable dispatch in generic and trait-object contexts.
- Tool methods (`given Trait`): static dispatch (not virtual dispatch entry points).

Tool methods are available in:

- Generic constraint contexts (e.g. `[T: Trait]`)
- Trait object contexts
- Concrete types that explicitly implement the trait

#### Override and Conflict Rules

- A type may have one `given` implementation of a trait, whatever type arguments the trait carries: `given Vec: Add[Int]` and `given Vec: Add[Vec]` conflict, exactly like a duplicate `given Point: T`.
- Tool methods are non-override by default.
- Inherent type methods win over trait tool methods.
- If the same method signature appears from multiple trait tool sources, Koral does not choose implicitly. You must disambiguate explicitly with a fully qualified call: `Type(TraitName).method(value, ...)`.
- If two traits define the same method and one inherits from the other, the child trait's implementation takes precedence (no ambiguity).
- `given Trait` cannot define a method with the same name/signature as a requirement of that trait.

#### Trait Inheritance Rules

- A trait can inherit from one or more parent traits: `trait Child: Parent1 and Parent2 { ... }`.
- Trait inheritance is acyclic; cycles are detected and rejected at compile time.
- A type implementing a child trait must also implement all parent traits (directly or via a `given` block).

#### Module Boundary Rules

Boundary anchoring rules:

- `given Trait { ... }` is allowed only within the trait's root module subtree.
- `given Type { ... }` is allowed only within the type's root module subtree.
- `given Type: Trait { ... }` follows orphan rules: either the type or the trait must be local to the current root module.
- Cross-crate injection is not allowed.

### Fully Qualified Calls

When multiple candidates conflict, use a fully qualified call. There are two spellings:

- `Type(TraitName).method(...)` — type-qualified. The receiver of an instance method is the first call argument; a static trait method takes no receiver.
- `expr(TraitName).method(...)` — receiver-qualified. The receiver is the base expression and is not repeated in the arguments. Instance methods only.

Both are composite: the `expr(TraitName)` / `Type(TraitName)` prefix must carry a method call.

- Generic traits carry their arguments in the qualification: `Type(TraitName[Args...]).method(...)`
- Generic method type args still appear on the method: `Type(TraitName).method[TypeArgs...](...)`

```
Type(TraitName).method(receiver, ...)   // instance method (type-qualified)
Type(TraitName).static_method(...)      // static trait method
expr(TraitName).method(...)             // instance method (receiver-qualified)
```

```koral
trait Tag {
    value(self): Int;
};

given Tag {
    plus_ten(self): Int = self.value() + 10;
    kind(self): Int = 42;
};

type Num(x: Int);

given Num: Tag {
    value(self): Int = self.x;
};

let n = Num(7);
println(Num(Tag).plus_ten(n).to_string());  // 17
println(Num(Tag).kind(n).to_string());      // 42
```

For generic methods, the trait qualification wraps the type before method type arguments.

### Trait Objects

Trait objects are Koral's mechanism for runtime polymorphism (dynamic dispatch), and the surface syntax is the trait name itself.

#### Basic Syntax

Trait-object construction follows these rules:

- The target type is a trait name (with type arguments if the trait is generic, `Transform[Int]`).
- The source value must implement the trait and be converted into that trait-object context.
- No `Object` marker trait is required.

```koral
trait Drawable {
    draw(self): String;
};

type Circle(radius: Int);

given Circle: Drawable {
    draw(self): String = "Drawing circle";
};

let shape: Drawable = Circle(10);   // implicit coercion on assignment
shape.draw();

let d = Drawable(Circle(10));      // explicit upcast, one positional argument
d.draw();
Drawable(Circle(10)).draw();       // anywhere an expression is needed
```

The assignment coerces the concrete value into the trait-object context. The
explicit upcast is the one-argument call form `Trait(expr)` — `Drawable(c)`,
or `Transform[Int](c)` for a generic trait. A trait target follows the
nominal rule, so `c as Drawable` is refused as a cast spelling (`Construction
is written 'Type(args)', not 'expr as Type'`). Casting from one trait object
to another is refused (`Cannot cast a trait object to another trait object`),
and the upcast takes exactly one positional argument (`A cast takes exactly
one positional argument: write 'Type(expr)'`).

Important rules:

- Trait-object dispatch uses the concrete value's semantics without exposing internal wrappers in the public surface.
- Any trait can be used as a trait-object target if it is object-safe.
- Trait objects do not support direct dereference; use trait methods through dynamic dispatch.

#### Object Safety

Only Traits that satisfy the following conditions can be used as trait objects:

- Methods must not have generic parameters.
- The receiver, if present, must be `self`.
- `Self` must not appear in method parameters or return types.

```koral
// Object-safe — can be used as a trait object
trait Error {
    message(self): String;
};

// Not object-safe — cannot be used as a trait object
trait Eq {
    equals(self, other: Self): Bool;
};
```

Exact implementation-type tests on trait objects are described under [Exact Type Patterns](#exact-type-patterns).

### Operator Overloading

Koral supports trait-based operator overloading for arithmetic, bitwise, and comparison operations. Subscripts are built in and are not user-overloadable.

The built-in operator mappings are:

- `+` -> `Add[R]` via `add(self, other: R): Self`
- `-` (binary) -> `Sub[R]` via `sub(self, other: R): Self`
- `-` (unary) -> `Neg` via `neg(self): Self`
- `*` -> `Mul[R]` via `mul(self, other: R): Self`
- `/` -> `Div[R]` via `div(self, other: R): Self`
- `%` -> `Rem[R]` via `rem(self, other: R): Self`
- `&` -> `BitAnd[R]` via `bit_and(self, other: R): Self`
- `|` -> `BitOr[R]` via `bit_or(self, other: R): Self`
- `^` -> `BitXor[R]` via `bit_xor(self, other: R): Self`
- `~` (unary) -> `BitNot` via `bit_not(self): Self`
- `<<` -> `ShiftLeft[R]` via `shift_left(self, other: R): Self`
- `>>` -> `ShiftRight[R]` via `shift_right(self, other: R): Self`
- `==` / `!=` -> `Eq` via `equals(self, other: Self): Bool`
- `<` / `>` / `<=` / `>=` -> `Ord` via `compare(self, other: Self): Int`

Same-direction chained ordering comparisons such as `a < b < c` are syntax sugar over these existing comparison operators. The compiler lowers them into pairwise comparisons with single-evaluation and short-circuit semantics; they do not introduce a separate trait or dispatch mechanism.

A pair of same-width integer operands (the `Wrapping` family included) takes the built-in path for the arithmetic and bitwise operators -- checked arithmetic and shifts for the regular family, modular arithmetic and masked shift amounts for `Wrapping` -- and everything else dispatches through the traits above.

The bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`) dispatch through `BitAnd` / `BitOr` / `BitXor` / `BitNot` / `ShiftLeft` / `ShiftRight`, under the same rules as arithmetic.

```koral
type Vec2(x: Int, y: Int);

given Vec2: Add[Vec2] {
    add(self, other: Vec2): Vec2 = Vec2(self.x + other.x, self.y + other.y);
};

given Vec2: Neg {
    neg(self): Vec2 = Vec2(-self.x, -self.y);
};

given Vec2: Eq {
    equals(self, other: Vec2): Bool = self.x == other.x and self.y == other.y;
};

given Vec2: Ord {
    compare(self, other: Vec2): Int =
        if self.x != other.x then self.x.compare(other.x) else self.y.compare(other.y);
};

let sum = Vec2(1, 2) + Vec2(3, 4);
let flipped = -sum;
let same = sum == Vec2(4, 6);
let ordered = Vec2(1, 0) < Vec2(2, 0);
```

Bitwise operators overload the same way:

```koral
type Bits(mask: UInt32);

given Bits: BitAnd[Bits] {
    bit_and(self, other: Bits): Bits = Bits(self.mask & other.mask);
};

given Bits: BitNot {
    bit_not(self): Bits = Bits(~self.mask);
};

// The rhs type is the trait's `R`: a shift count reads naturally as `Int`.
given Bits: ShiftLeft[Int] {
    shift_left(self, other: Int): Bits = Bits(self.mask << UInt32(other));
};

let both = Bits(0xF0) & Bits(0x33);
let complement = ~both;
let wide = Bits(1) << 8;
```

Compound assignment (`&=`, `|=`, `^=`, `<<=`, `>>=`) is the same two-step
desugaring spelled out in [Compound Assignment](#compound-assignment): each
`op=` reads the target, runs the operator — built-in arithmetic or the trait
(`Add`, `ShiftLeft`, …) — and writes back, so the right-hand side takes the
operator's own operand type. A `ShiftLeft[Int]` implementation therefore makes
`m <<= 2` take an `Int` count, and a generic `T` behaves exactly like the
built-ins. The step is not atomic across threads.

#### Builtin Subscript Rules

- `value[key]` and `value[key] = expr` are supported only for `String`, `List[T]`, `Deque[T]`, `Dict[K, V]`, `FrozenList[T]`, `FrozenDict[K, V]`, fixed-size arrays `[N]T`, `*T`, and `*mutable T`.
- A **numeric index is an `Int`** — counts and positions are signed throughout the standard library, so an integer literal in subscript position infers `Int`, and an `Int` variable needs no conversion to index. `Dict[K, V]` / `FrozenDict[K, V]` take a `K` key instead.
- On `String`, `List`, `Deque`, `FrozenList` and fixed-size arrays the index is bounds-checked: an out-of-range **or negative** index panics. Pointer subscripts are the exception — `p[i]` is unchecked C indexing, and a negative `i` is raw pointer arithmetic.
- `String[key]` returns a `UInt8` byte value. It is read-only and not addressable.
- `List[T]` and `Deque[T]` (both `type mutable`) support value reads, assignment, and nested place updates.
- `FrozenList[T]` and `FrozenDict[K, V]` subscripts are read-only: `frozen[i]` and `frozen_dict[key]` read exactly like `List[i]` / `Dict[key]` (same out-of-range / missing-key panics), and assigning to one is a compile error. `FrozenSet[T]` has no subscript.
- Fixed-size arrays `[N]T` support value reads, assignment, and compound updates, bounds-checked (see [Fixed-Size Arrays](#fixed-size-arrays)).
- `*T` supports `*expr` reads only. `*mutable T` supports both `*expr` reads and writes.
- User-defined types cannot implement `[]` through traits, and generic constraints cannot add subscript capability.

```koral
let list = [10, 20, 30];
println(list[0]);
list[1] = 99;

let text = "abc";
let b: UInt8 = text[1];

let p: *mutable Int = alloc_memory[Int](2);
p[0] = list[0];
let first = p[0];
dealloc_memory(p);
```

### Extension Methods

The `given` block can also be used to directly add methods to types:

```koral
given Point {
    public distance(self): Float64 = {
        let dx = Float64(self.x);
        let dy = Float64(self.y);
        return dx + dy; // ...
    };

    // Methods without self are called via type name
    public origin(): Point = Point(0, 0);
};

let p = Point.origin();
```

### Standard Library Core Traits

The most commonly used core traits are:

- `Add[R]` / `Sub[R]` / `Neg` / `Mul[R]` / `Div[R]` / `Rem[R]`: arithmetic operator traits.
- `BitAnd[R]` / `BitOr[R]` / `BitXor[R]` / `BitNot` / `ShiftLeft[R]` / `ShiftRight[R]`: bitwise operator traits.
- `Eq` / `Ord`: equality and ordering.
- `Hash`: hash support for dict/set keys.
- `ToString`: conversion to string.
- `Clone`: explicit shallow copy (`clone(self): Self`).
- `Iterator[T]`: iteration protocol — a one-shot cursor (`next(self): Option[T]`), and nothing else.
- `Iterable[T, R]`: can hand out a fresh cursor on every call (`iterator(self): R`). Enter a lazy pipeline with `lazy()`, which returns a `LazyView`.
- `Error`: error message interface (`message(self): String`). Declared `trait sendable Error` — every error type must be `sendable`, and `Result`'s error side is the plain `Error` trait object.
- `Drop`: destructor hook (`drop(self): Void`).

Arithmetic, bitwise, and comparison operators are lowered to trait methods internally (for example `+` to `Add`, `&` to `BitAnd`). Subscripts are resolved by builtin compiler rules instead of public traits.

### Modules and Visibility

Koral organizes code with two nested units:

| Concept | What it is | Stable identity | Example |
| --- | --- | --- | --- |
| **package** | A reusable external unit: one `koral.json`, one version, one set of dependencies | `source` | `httpr`, `std` |
| **module** | A build unit inside a package: one entry file plus the files merged into it | `(source, subpath)` | `httpr/conn`, `std/io` |

**A module's full name is `package[/subpath]`**, and source always writes the full
name. The main module is the one with an empty subpath, so its full name IS the
package name. It is not a "root": it sits beside its submodules with no
re-export semantics.

#### Manifest

A `koral.json` has five fields:

```json
{
  "package": "httpr",
  "version": "0.4.1",
  "modules": {
    ".":    { "entry": "client.koral",    "links": [] },
    "conn": { "entry": "conn/conn.koral", "links": [] }
  },
  "dependencies": {
    "slug": { "source": "path:../slug", "version": "^1.2" }
  },
  "exclude": ["test/cases"]
}
```

- **`package`** -- this package's source name: the self-reference prefix and the
  default name a consumer uses. **It is not identity**; identity is `source`.
- **`version`** -- the version.
- **`modules`** -- **package-internal name** -> `{ entry, links }`. The main
  module's key is `"."`; a submodule's key is its subpath (`"conn"`,
  `"compiler/parser"`). `entry` is the entry file, relative to the package root.
- **`dependencies`** -- **source name** -> `{ source, version }`. `source` is the
  fetch location and the identity, and carries no ref; `version` is a semver
  constraint. Renaming a dependency is changing its key -- there is no extra field.
- **`exclude`** -- package-root-relative paths that are **not** package source:
  formatter fixtures, generated inputs, anything `.koral` that no module may
  claim. Optional. The compiler never reads it; `koral lint` does.

`koral lint` reviews the project's layout, separately from compiling it. Its one
check today: every `.koral` file under the package root must belong to exactly
one module's closure. A file nobody claims is compiled nowhere and checked by
nothing -- the usual cause is a `using` that was never written. `koral build`
and `koral check` run the same check first.

There is no top-level `entry` (the default build target IS the main module), no
`name` (it duplicates `package`), no `requires` (the module graph comes from
`using`), and no `module_aliases` (renaming is the dependency key).

#### Using Declarations

`using` has one form. The **operation** follows from the braces; the specifier
only says where the target is:

| Form | Operation | Boundary |
| --- | --- | --- |
| `using "spec";` | **merge** -- the target joins this module | gone |
| `using "spec" { … };` | **import** -- take names from the target | kept |

| Specifier | Names |
| --- | --- |
| `./x.koral`, `../y/z.koral` | the module rooted at that entry file |
| `pkg`, `pkg/sub` | a registered module's `package[/subpath]` |

Every `using` must sit at the top of the file, before any other top-level
declaration. A module is imported once per file.

A **single file is a module** -- the smallest kind. There is no separate
"file merge" concept: the bare form merges a module, and a module happens to be
one file when it merges nothing.

##### Merge

```koral
using "./helpers.koral";
using "./util.koral";          // a module that itself merges others
```

The target's whole closure joins the current module and its boundary is gone:
its `internal` names become this module's `internal` names.

1. A local path must end in `.koral` and is resolved against the directory of
   the current file; `.` / `..` may appear;
2. A merged module may be merged into at most one module, and once merged it
   cannot also be imported -- every source file is compiled into exactly one
   module;
3. Merging a registered module of this package (`using "mypkg/util";`) is legal
   and does the same thing; it is rarely what you want.

##### Import

```koral
using "std/os" { };                          // nothing at all
using "std/io" { Reader, Writer };           // only some
using "std/io" { Reader as IoReader };       // per-name alias
using "std/os" { ... };                      // every visible member
using "std/os" { Config as OsConfig, ... };  // every member, `Config` renamed
using "std/os" { !Config, !Builder, ... };   // every member but these
```

| Form | Names |
| --- | --- |
| `{ }` | none -- a placeholder while editing, like Go's `import _` |
| `{ a, b }` | exactly these |
| `{ a as b }` | exactly these, one renamed |
| `{ ... }` | every visible member |
| `{ a as b, ... }` | every member, `a` spelled `b` |
| `{ !a, !b, ... }` | every member but `a` and `b` |

1. `...` is the base set and closes the list. Items alongside it are renames or
   exclusions (`!`), never both; a positive item without `as` next to `...` is
   redundant and rejected. `{ !a }` without `...` is rejected.
2. An item is `Name` or `Name as Alias`, trailing comma allowed. The alias must
   keep the referenced name's case class: `Reader as IoReader` is valid,
   `Reader as reader` is an error. The item may be a trait: `Tag as AlphaTag`
   binds `AlphaTag` as a trait name and it can be used as a generic bound or a
   trait-object type. The alias is a spelling -- the trait it names is the same
   declaration.
3. `as` renames one imported symbol, never the module -- a module name is not a
   namespace, so after `using "std/io" { Reader };` you write `Reader`, not
   `io.Reader`. A local path may also import: `using "./util.koral" { a };`
   names the module rooted at `util.koral` and needs no manifest entry.
4. Imported names are file-local bindings and are not re-exported.
5. A name collision is an error; `as` renames and `!` excludes. The diagnostic
   says which.

##### Name Collisions

A spelling has **one** owner. A second, *different* owner under the same
spelling is the clash. Identity is the declaration, not the name — so the same
declaration arriving twice is never a clash.

| The import's name vs… | Result |
| --- | --- |
| a top-level declaration in this module | **error** |
| another import in this file, different declaration | **error** |
| the prelude (`std`'s root: `List`, `Eq`, `Clone`, …), different declaration | **error** |
| the same declaration arriving again (two files of one module each `using "std" { ... };`) | fine |
| a local `let` inside a function | fine — nested shadowing is legal |

The fix depends on the form: a bare name can take `as`, and a `{ ... }` list can
take either `as` (rename) or `!` (drop). The diagnostic says which.

```koral
using "game/render" { List };              // error: the prelude owns `List`
using "game/render" { List as RList };     // fine
using "game/render" { ... };               // error if `render` exports a `List`
using "game/render" { !List, ... };        // fine -- drop theirs
using "game/render" { Sprite };            // fine
```

##### Method Face

An import brings two things: **names** (what the list picks) and the **method
face** -- which `given` methods are dispatchable here. The face follows what is
*named*, never the module that happens to hold it:

| Call | Needs |
| --- | --- |
| `x.m(…)`, `m` from `given X { … }` | **nothing** -- a value of `X` is enough |
| `x.m(…)`, `m` from `given X: T { … }` or `given T { … }` | **`T` in scope** |
| `X.m(…)` (associated / qualified) | **`X` in scope** |

Naming a type brings **no** trait methods. Naming a trait opens its methods on
**every** implementing type.

`T` is in scope when it is declared in this file's module (a merged module
counts -- merging removes the boundary), imported as `{ T }` or `{ T as A }`,
batch-imported without `!`, in the prelude, or named in the enclosing
declaration's generic bounds. Renaming keeps it: `{ T as A }` leaves `T`
unwritable but the trait is still in scope and its methods are called by their
own names.

Not in scope: `{ }`, an unrelated name (`{ env }`), **the type itself**
(`{ Path }`), nothing at all.

A generic **bound** is different from an import: `[T: Leaf]` puts `Leaf`'s
methods in scope for that parameter, supertraits included. So `fn go[T: Leaf](x: T) = x.r() + x.l()`
works with `Leaf: Root`, while a concrete receiver with only `Leaf` imported
cannot call `r()`.

```koral
using "std/os" { open_file, File };         // `File` named
f.read(into = buf, span = ...);               // error: `Reader` is not in scope

using "std/io" { Reader };                  // name the trait you are using
f.read(into = buf, span = ...);               // fine

using "std/os" { read_file };               // the free function needs no trait
read_file("/etc/hosts");
```

When a method exists but its trait is out of scope, the diagnostic says so and
prints the `using` line to add.

#### Resolution

`using "X"` splits at the first `/`:

```
head = the first segment   (no "/" -> head is the whole string)
tail = the rest            (no "/" -> tail is "")
```

`head` must be a registered package name -- **this package's `package`, one of
its `dependencies` keys, or the reserved `std`** -- otherwise "unknown package
name". Then the package's `modules` is consulted for the **package-internal
name**: `"."` when `tail` is empty, otherwise `tail`.

> **Every package resolves its own source with its own table.** Compiling
> `httpr`'s files uses `httpr`'s own `package` and `dependencies`, whatever the
> consumer chose to call it. So `dep_utils` writes `using "dep_utils/…"` while
> its consumer writes `using "game_utils/…"`, and both land on one package.

The module graph is the union of the modules' `using` statements -- **there is no
`requires`, one source of truth**. From it come build ordering and reachability;
the graph must be acyclic; `links` propagate along it.

**The `std` main module is the prelude.** For non-`std` modules the compiler
brings it in and puts it in scope without being named. Every other module
(including `std/io` and `std/time`) needs an explicit import. `using "std";` is
still legal -- it is how `std`'s own submodule files get the prelude.

#### Entry File Names

- A module entry file's stem must start with a lowercase letter;
- The rest may only be lowercase letters, digits or `_`;
- Every segment of a module full name follows the language's identifier rules
  (lowercase start, letters/digits/underscore) and may not be a reserved word;
- A package name is a **single** identifier segment: no `/`, no `.`. `/` only
  separates subpaths, so the first `/` is the package/module boundary.

#### Access Modifiers

Koral provides four access levels to control symbol visibility:

| Modifier | Visibility |
|----------|------------|
| `private` | Accessible only within the same file |
| `internal` | Accessible within the current logical module (the default) |
| `protected` | Accessible from any module in the same package |
| `public` | Accessible from anywhere |

Package scope follows the manifest graph: the root package, `std`, and each dependency package are separate package boundaries.

> **`protected` means package-visible, not subclass-visible.** In Java, C++,
> C# and Kotlin `protected` grants access to subclasses; Koral's `protected`
> grants access to every module in the same package -- the distribution
> boundary. Koral has no inheritance, so the subclass reading does not apply.
> (Readers of early Koral material: `protected` used to be the module-level
> spelling; that role is now `internal`.)

##### Default Access Levels

An unannotated declaration is `internal` (module-visible). Write an access
modifier only to mark a deviation from that default: `private` narrows it,
`protected` and `public` widen it.

| Declaration | Default |
|-------------|---------|
| Global `let`/variables, functions, types, traits, type aliases | `internal` |
| Struct fields | `internal` |
| Member functions (in `given` blocks) | `internal` |
| Trait requirements | the trait declaration's level |
| Enum cases & case fields | the enum declaration's level |
| `using` declaration | file-local (imported bindings are not re-exported) |

Trait requirements and enum cases are interface items: they take no access
modifier of their own (`Access modifier on trait method is not supported`) and
inherit the visibility of the declaration that contains them. A `given`
declaration itself takes no access modifier either
(`Access modifier on given declaration is not supported`); its member
methods may.

Direct struct construction `Type(...)` is only allowed when all referenced
fields are visible at the call site. Since fields default to `internal`,
constructing a type from another module fails with
`Cannot directly construct type 'X' because field 'a' is internal. Use a public factory method instead.`
Expose a public factory method instead -- or, for value-carrier types such as
std's `Pair`, declare the fields `public` so callers may construct them
directly.

### Project Structure Example

```
my_project/
├── koral.json;
├── main.koral           # "." (main module) entry;
├── utils.koral          # merged into the main module;
├── models/
│   ├── models.koral     # "models" entry;
│   └── user.koral       # merged into "models";
└── services/
    └── services.koral   # "services" entry;
```

```json
{
  "package": "app",
  "version": "0.1.0",
  "modules": {
    ".":        { "entry": "main.koral",           "links": [] },
    "models":   { "entry": "models/models.koral",  "links": [] },
    "services": { "entry": "services/services.koral", "links": [] }
  }
}
```

```koral
// main.koral
using "./utils.koral";
using "app/models" { User };
using "app/services" { authenticate };

public let main(): Void = {
    let user = User.new("Alice");
    if authenticate(user) then {
        println("Welcome!");
    };
};
```

## 6. External Interop

This chapter collects the low-level surface: raw pointers, address-taking, and the C foreign function interface.

### Raw Pointer Types

Raw pointers are low-level memory access for FFI and system programming:

- `*T` — read-only pointer. Supports `*expr` dereference read but NOT `*expr` assignment or `p[i]` assignment.
- `*mutable T` — mutable pointer. Supports `*expr` dereference read, `*expr = value` assignment, `p[i]` read, and `p[i] = value` assignment.
- `*mutable T` implicitly converts to `*T`. The reverse is not allowed.

The null pointer is the literal `null`. It joins an expected `*T` or
`*mutable T` — any pointee, including type parameters — and compares with
`==` / `!=`:

```koral
let p: *Int = null;
let m: *mutable Int = null;
if p == null then { ... };
if m != null then { *m = 42; };
```

`null` also matches as a literal pattern — `p is null`, `p is not null`, or a
`when` arm `null then …` (literal patterns are not exhaustive alone, so a
`when` over them still needs a catch-all) — and it fills pointer-typed
defaults (`let f(p: *Int = null): Int = …`, `type Node(p: *Int = null)`).
Through `as`, `null as UInt` is the zero address; `null as *Int` /
`null as *mutable T` cast the null pointer to those pointer types, while
`null as ?Box` is an error — a weak handle has no null spelling. A `null`
with no pointer type to join reports `Cannot infer a pointer type for 'null':
add a type annotation`; a non-pointer expected type reports `Type mismatch:
expected <T>, got null`. `null` is a hard keyword (like `true` / `false`) and
cannot be rebound as an identifier.

Pointer reinterpretation is written `expr as Type`. A `*mutable T` reads as
its `*T` view (`p as *T`), a pointer may be re-read through a different
pointee in one step (`p as *UInt`), and pointers cross to and from integer
addresses in both directions (`p as UInt` / `u as *Int`). The result takes
parentheses before a method call: `(self as *T).equals(other as *T)`.

A parenthesized type head is the same target as the bare name in expression
position: `(*Foo).f()` looks `f` up on the `*Foo` method face, just as
`(Point).origin()` is `Point.origin()` and `(Point)(1, 2)` is
`Point(1, 2)`. Parentheses in a TYPE group exactly one type — `let p: (*Int)`
is `let p: *Int`, `let f: ((Int) -> Int) = g` annotates a function value — and
a prefix written outside the group applies to the whole group: `*(Int)` is
`*Int`, while `*(Int) -> Int` is a pointer to the function type
`(Int) -> Int`.

The old type-constructor spellings are rejected. `*Int(u)` now reads as the
operator chain `*(Int(u))` and `?Box(b)` as `?(Box(b))`, so they fail with
the natural operator errors; the paren and alias call forms `(*Int)(u)` /
`(?Box)(b)` / `MyPtr(u)` report `Pointer and weak casts are written
'expr as Type', not 'Type(expr)'`, and `UInt(p)` reports `Pointer and
integer casts are written 'expr as Type', not 'Type(expr)'`.

### Unsafe Address-Of and Dereference

`&` / `&mutable` are raw address-of operators. They require addressable storage; literals and temporaries are rejected.

```koral
let p: *Int = &value;
let mp: *mutable UInt8 = &mutable bytes[0];

let x = *p;       // raw deref read
*mp = 42;         // raw deref write
let q = &value as *Int;   // (&value) as *Int: cast groups over the whole prefix

// let bad = & 42  // error: raw address-of needs addressable storage
```

Rules:

- `&` produces `*T`; `&mutable` produces `*mutable T`.
- `*expr` reads and `*expr = value` writes are the raw dereference forms.
- `as` binds looser than the prefix operators: `&x as *T` is `(&x) as *T`
  and `*p as *Int` is `(*p) as *Int`.
- Raw pointers are not a general "any type to `*T`" bridge: the std helpers that hand out raw pointers require the `foreign` shape constraint on the element type (see [Generic Constraints](#generic-constraints)).

### Foreign Function Interface

Koral supports interoperability with C through the `foreign` keyword.

#### Linking External Libraries

Native libraries are declared in package or module `links` inside `koral.json` / `std/koral.json`:

```json
{
  "modules": {
    ".": { "entry": "main.koral", "links": ["m"] }
  }
}
```

The compiler adds linker flags from the resolved manifest graph. `libc` is implicitly linked by default and does not need to be declared.

> **Where the qualifier goes.** `foreign` and `intrinsic` are written
> **immediately after the keyword** — `let foreign`, `type foreign`, `type
> intrinsic`, `given intrinsic` — the same slot `type mutable` and `let mutable`
> already occupy. Access modifiers are the only prefix modifiers: they say who
> can see a declaration, not what kind of thing it is. The two qualifiers are
> mutually exclusive, and they come before `mutable`, which describes the
> binding (`let foreign mutable errno: Int32;`).

#### Foreign Functions

Declare external C functions. Foreign functions use positional parameters only; named parameters (the `=` marker) are not supported.
**Body presence decides the direction**: no body is a reference (extern
linkage); a body is a definition — a C ABI export.

```koral
let foreign sin(x: Float64): Float64;                    // reference: links C's sin
let foreign "CreateFileA" create_file(path: *UInt8): UInt32;  // reference + C name
let foreign add_one(x: Int32): Int32 = {                 // definition: exported to C
    return x + Int32(1);
};
```

- **The C-name slot**: a string written right after `foreign`, before the Koral
  name — it is this declaration's **name in the C world**. Identifiers belong to
  the Koral namespace only; foreign vocabulary (C symbol names, macro names) is
  spelled as strings. Omitted, the C name is the Koral name verbatim, so the
  Koral name must then itself be a legal C identifier — the compiler refuses
  one that is not and points at the slot. With a slot the two names part ways,
  and the Koral name may even collide with a C keyword harmlessly — each side
  calls its own.
- An exported (body-bearing) function's signature restrictions are **exactly**
  the reference ones: closed set, positional parameters, no generics. It is
  callable from Koral like any function, and as a value its type is
  `foreign (A) -> R` — it can be passed to C as a callback.
- Visibility (`public` / `internal` / …) governs the Koral-side name only; the
  **C symbol is always exported** (C has no module visibility).
- A panic never unwinds across an export boundary: it prints and `abort()`s.

#### Foreign Variables

The value's presence and `mutable` pick the form:

```koral
let foreign mutable errno: Int32;            // reference: extern mutable variable
let foreign stdin: *CFile;                   // reference: bare `extern` (Koral-side mutability is a language check, not `const`)
let foreign mutable counter: Int32 = 0;      // definition: C variable (static init)
let foreign "AF_INET6" af_inet6: Int32 = 10; // macro constant: value binding
```

- An initializer must be a **constant literal** (optionally negated / `null`) —
  C static initializers are constant expressions.
- A value with no `mutable` is a **C macro constant** binding: the value is
  copied from the C header, and no C entity is produced (a macro has no link
  symbol); the C-name slot records the macro's name as a correspondence label.
  The value is copied **by hand** — nothing checks it against the macro's real
  value, so a header change moves silently; re-check the binding when the
  header changes.

#### Boundary Types

What may cross a `let foreign` function boundary is a closed set decided by the
compiler — parameter and return types must be:

- a built-in scalar; `Void` / `Never` are legal in
  **return** position only — C has no void values, so a parameter cannot be
  either, and `foreign (Void) -> R` would just be the zero-argument pointer
  spelled wrong;
- a raw pointer `*T` / `*mutable T` **whose pointee crosses too** — `*Box` and
  `*Void` are fine, `*Bad` and `*(closure)` are not: a raw pointer is only as
  FFI-shaped as what it points at;
- a `type foreign` handle behind `*` (an opaque `type foreign CFile {}` appears
  only as `*CFile` — it has no layout, so no field, global or function-pointer
  component may hold one by value);
- a `foreign (A) -> R` function pointer whose components pass the same rules.

A Koral `type`, closure or managed reference never crosses — by value or
behind a pointer. A `type foreign` struct or `[N]T` array crosses **by value
only as a global** (`let foreign v: KoralTimespec;`): a foreign global is a
layout object C reads directly, while function parameters and returns take
`*T` (a C array parameter really is a pointer).

> **`*Void` is `void*`.** `*Void` / `*mutable Void` are C's `void*` spellings
> and stay legal at every boundary — parameters, returns, function-pointer
> components, globals and `type foreign` fields.

#### Foreign Types

Declare external C types:

```koral
// Opaque type (no fields)
type foreign CFile {};

// The same kind of type under its name in the C world
type foreign "FILE" CFileHandle {};

// FFI struct with fields (aligned with C layout)
type foreign "timespec" KoralTimespec(tv_sec: Int64, tv_nsec: Int64);
```

The rules are C's, spelled in Koral:

- **The C-name slot** works exactly as on `let foreign` (same spelling, same
  validation): it is the type's **name in the C world** — the C struct tag for
  the struct form (`"timespec"` makes it `struct timespec`), the C type's own
  spelling for the opaque form (`"FILE"` makes it `FILE`). That is what lets a
  real C type cross a boundary untranslated: a shim that includes the owning
  header meets the same tag and type. An opaque type with a C name is the C
  side's declaration — the export header does **not** redeclare it, so include
  the owning header before `koral_exports.h`. Omitted, the C name is the Koral
  name verbatim, and the Koral name must itself be a legal C identifier.
- A `type foreign` cannot be declared `mutable` — mutability is a property of
  Koral's own nominal declarations — and it takes no generic parameters.
- Fields are bare `name: Type`: positional, with no access modifiers, no
  `mutable` marker, no named fields, no defaults. C layout is public and
  always writable; a marker that changes nothing would only lie.
- Every field type must cross the FFI boundary — a built-in scalar, a `*`
  / `*mutable` pointer to one (or to `Void`, C's
  `void*`), or another `type foreign` declaration: the same closed set the
  `foreign` constraint names. An opaque `type foreign X {}` still appears only
  behind `*` — it has no layout to store. Direct self-recursion is refused
  (write `*Self`).
- `type foreign` values follow **mutable value semantics**: assignment and
  argument passing copy. `self` in a method is such a copy, so there is no
  mutable self — to mutate a receiver, take a `*mutable T` parameter.
- An explicit `Drop` is refused: a C value has no destructor (codegen copies
  it with plain C assignment and drops it as a no-op).

In-place writes (`x.v = value`, `x.a.b = value`) follow the same matrix as
any value type:

| Write through | Allowed |
| --- | --- |
| `let mutable` binding | yes |
| `mutable` parameter (its local copy — it does **not** write back) | yes |
| `*mutable T` link (the pointer's TYPE decides, not its binding) | yes |
| a `type mutable` object's `mutable` field, through any path reaching it | yes |
| `let` binding, plain parameter, `self`, `*T` link, temporary | no |

A read-only handle segment (`*T`) in the middle of a chain resets write
permission for the rest of it. `&mutable` / `&mutable expr` forms a
`*mutable T` and needs one of the writable forms above.

#### Fixed-Size Arrays

`[N]T` is a C-layout fixed array of N elements of `T`: mutable value semantics
(copies on assignment and passing; the same write matrix as above applies to
`a[i] = v`). A numeric subscript is bounds-checked: the index is evaluated
once and an out-of-range or negative one panics instead of reading neighbouring
memory.
`T` must cross the FFI boundary — a built-in scalar, a `*` /
`*mutable` pointer, another `type foreign` or `type foreign`'s array-friendly
forms.

```koral
type foreign Buf(data: [4]Int32, len: Int32);

let main(): Int = {
    let mutable a: [4]Int32 = [1, 2, 3, 4];   // exactly N elements
    let mutable z: [4]Int32 = [];             // the zeroed buffer
    a[2] = Int32(9);                          // subscript writes into storage
    let p: *Int32 = &a[0];                    // element address
    return 0;
};
```

- Non-empty literals carry exactly N elements; `[]` is the all-zero buffer.
- `a[i]` is bounds-checked on reads and writes (only `*T` indexing is
  unchecked C indexing); `[N]T` cannot cross a
  function boundary at the FFI (`let foreign` params/returns take `*T` —
  that is what a C array parameter really is).

#### Foreign Function Types

`foreign (T) -> R` is a bare C function pointer. It is **not** a Koral
closure: only `let foreign` functions and same-typed values inhabit it, and
`null` joins it the way it joins `*T`.

```koral
let foreign abs(x: Int32): Int32;

let main(): Int = {
    let f: foreign (Int32) -> Int32 = abs;    // a `let foreign` function
    let cb: foreign (Int32) -> Int32 = null;  // nullable, like *T
    if cb != null then {
        println(f(Int32(-1)).to_string());
    };
    return 0;
};
```

- Calls are positional-only, straight to C. Every signature component must
  cross the FFI boundary under the same rules as `let foreign` parameters and
  returns (see [Boundary Types](#boundary-types)).
- A lambda or Koral function value is a closure and does not convert;
  assigning one is the ordinary type mismatch.

### Intrinsic Declarations

The `intrinsic` keyword declares types and functions built into the compiler:

```koral
type intrinsic Int;
```

Intrinsics are reserved for the standard library.

## Appendix: Standard Library Essentials

Use these as the minimal everyday building blocks:

```koral
// List (shared object — clone() for an independent copy)
let nums: List[Int] = [1, 2, 3];

// Dict
let scores: Dict[String, Int] = ["alice": 10, "bob": 8];

// Set
let tags: Set[String] = ["koral", "lang"];

// Option + or else / and then
let port = Option[Int].Some(8080) or else 80;
let doubled = Option[Int].Some(21) and then as v in v * 2;

// or return
let read_number(path: String): Result[Int] = {
    let text = read_text_file(path) or return;
    return Int.parse(text);
};

// Result (error side is Error trait object)
let ok = Result[Int].Ok(42);
let err = Result[Int].Error("failed");

// Building a String incrementally
let sb = StringBuilder.new();
sb.push_string("built");
let s = sb.to_string();

// Shared mutable state for closures
let counter = Cell(0);
counter.value = counter.value + 1;
```

For complete API reference, see docs under `docs/api/std/`.

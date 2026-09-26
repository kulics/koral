# The Koral Programming Language

Koral is an open-source programming language focused on performance, readability, and practical cross-platform development.

Through carefully designed syntax rules, this language can effectively reduce reading and writing burden, allowing you to put your real attention on solving problems.

Specification note:

- This document is the user-facing language reference.
- For grammar-sensitive questions, read this document together with `docs/grammar.bnf`.
- If examples in this document, the BNF, and the implementation disagree, update the implementation and/or the documents so they converge.

This manual is ordered the way the language is learned: **language basics**, then **control flow**, then **custom types**, then **pattern matching**, then **abstraction**, and finally **external interop**.

## Overview

### Key Features

- Modern, easy-to-scan syntax with explicit semicolons and expression-oriented control flow: `if`, `when`, `while`, and `for` all use expression-form surface syntax. `if` and `when` may produce values; `while` and `for` always produce `Void`.
- Automatic memory management driven by declaration-site type semantics: shallowly immutable `type` versus shared `type mutable` objects. Layout and lifetime details are owned by the compiler.
- Generics with trait constraints and monomorphization for zero-cost abstraction.
- Algebraic data types (structs and enums) with exhaustive pattern matching.
- Trait-based polymorphism with trait objects for runtime dispatch.
- First-class functions, lambdas, and closures.
- Multi-paradigm programming (combining functional and imperative).
- Module system with access control (`public` / `package_private` / `module_private` / `file_private`).
- Foreign function interface (FFI) for seamless C interop.
- C backend for broad platform compatibility.

### The Core Idea: `type` / `type mutable`

Koral's nominal types come in exactly two forms, chosen at the declaration site. Everything else in the language — aliasing, mutation and layout — follows from this one decision.

**`type` — a shallowly immutable nominal type.**

- Fields cannot be mutated after construction, and a `mutable` field cannot be declared.
- Values have **no identity**: two values with equal fields are interchangeable.
- The **layout is chosen by the compiler**. Inline storage, hidden indirection and shared backing are all implementation details and may differ from release to release.
- **Value semantics is not part of the language contract.** Copying, argument passing and storage may share backing storage. That sharing is unobservable precisely because the type is shallowly immutable — so the compiler is free to optimize it away.

**`type mutable` — a shared object type.**

- Values have identity: assignment and argument passing hand out handles to the **same** object.
- Fields are immutable by default; only explicitly declared `mutable` fields may be modified in place, and only through the shared handle.

```koral
type Point(x Int, y Int);

type mutable Counter(mutable value Int, id UInt);

let p = Point(1, 2);
// p.x = 3;      // error: Point is `type`, its fields are immutable

let c = Counter(0, 1);
c.value = 5;      // ok: Counter is `type mutable` and `value` is a mutable field
// c.id = 2;     // error: `id` is not a mutable field
```

The compiler may use reference counting and hidden storage internally for either form. Those choices are not user-visible semantics: the language contract is `type` versus `type mutable`, never a managed-reference syntax.

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
    koralc build --package-config koral.json --target-module app::main;
    ```
3.  **Type-check only**:
    ```bash
    koralc check --package-config koral.json --target-module app::main;
    ```
4.  **Compile and run**: Use the `run` command to compile and execute in one step.
    ```bash
    koralc run --package-config koral.json --target-module app::main;
    ```
5.  **Emit C only**: Use `emit-c` to generate C source.
    ```bash
    koralc emit-c --package-config koral.json --target-module app::main -o out;
    ```

Common options:

- `-o, --output <dir>`: output directory
- `--package-config <path>`: build from a package manifest
- `--target-module <name>`: choose the manifest target module
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
- `if`, `when`, `for`, and `while` used as statements must end with `;`.
- Top-level declarations (functions, types, traits, given implementations) must end with `;`.

```koral
let a = 0;
let b = 1;

let count = "abc".count();

let branch = if false then 1 else 2;

let grouped = (1 + 2);

let fib(n Int) Int = {
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
let main() Void = {};
```

Here we declare a function named `main`. The right side of `=` is the function body, `{}` represents an empty block expression, returning `Void`.

The `main` function must:

- Have no parameters.
- Return `Int` or `Void`.

```koral
let main() Int = {
    println("Hello");
    return 0;
};
```

#### Displaying Output

The standard library provides the `println` function to print a line of text to the standard output.

```koral
let main() Void = println("Hello, world!");
```

Now try to execute this program, and we can see `Hello, world!` displayed on the console.

#### Comments

Comments are parts of the code ignored by the compiler, used to provide explanations to people reading the code.

```koral
// This is a single-line comment, starting from double slashes to the end of the line

/*
    This is a block comment.;
    It can span multiple lines.;
    /* Koral supports nested block comments */
*/
```

#### Identifiers

Identifiers are names given to variables, functions, types, etc. The naming rules are:

1. Case sensitive. `Myname` and `myname` are two different identifiers.
2. **Types** and **Constructors** must start with an **uppercase letter** (e.g., `Int`, `String`, `Point`).
3. **Variables**, **Functions**, **Members** must start with a **lowercase letter** or underscore (e.g., `main`, `println`, `x`).
4. Other characters in identifiers can be underscores `_`, letters, or numbers.
5. Within the same `{}`, identifiers with the same name cannot be defined repeatedly.
6. In different `{}`, identifiers with the same name can be defined, and the language will prioritize the identifier defined in the current scope.

### Values and Literals

We only need a few simple basic types to carry out most of the work.

#### Booleans

Booleans refer to logical values, they can only be true or false. The default boolean is `Bool` type.

```koral
let b1 Bool = true;
let b2 Bool = false;
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
let i Int = 3987349;
let f Float64 = 3.14;
let b UInt8 = 255;
```

Numeric literals support underscores `_` as separators for readability:

```koral
let million = 1_000_000;
let pi = 3.141_592_653;
```

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

Note: Only lowercase `e` is supported for exponent notation, consistent with the `0b`/`0o`/`0x` prefix convention.

#### Duration Literals

Duration literals are supported with integer suffixes:

```koral
let a = 10s;
let b = 250ms;
let e = 150us;
let f = 42ns;
```

Supported suffixes are `s`, `ms`, `us`, `ns`. A duration literal is sugar for a `Duration` construction after unit normalization — `10s` is `Duration.new(seconds: 10, nanoseconds: 0)` — and the result is unwrapped for you. Negative durations keep unary-minus semantics (for example `-5s` is parsed as unary `-` applied to `5s`).

#### Numeric Casting

Different numeric types require explicit conversion using `expr(Type)` syntax:

```koral
let a Int = 42;
let b Float64 = a(Float64);    // Int -> Float64
let c Int32 = a(Int32);        // Int -> Int32
let d UInt8 = 255(UInt8);      // Int -> UInt8
```

#### Strings

In Koral, strings are used to represent text data. `String` type is a UTF-8 encoded character sequence.

String literals use double quotes `""` only.

```koral
let s1 String = "Hello, world!";
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
    """
// Equivalent to "Hello, Koral!\nWelcome to multiline strings."

let name = "World";
let greeting = """
    Hello, \(name)!
    Have a great day.
    """
// Equivalent to "Hello, World!\nHave a great day."
```

The indentation of the closing `"""` determines how much is stripped:

```koral
let s = """
        indented content
        second line
    """
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
s.replace_all("World", with: "Koral"); // "Hello, Koral!"
s.split(",");                     // Split by separator
s.lines();                        // Split by lines

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
let r Rune = 'A';
let nl Rune = '\n';
let smile Rune = '\u{1F600}';
```

Rune literal typing rules:

- Default type is `Rune`.
- In an explicit `UInt8` context, a rune literal can be inferred as byte (`UInt8`) if it is a single ASCII character.

#### Collection Literals

Koral supports collection literals for the three built-in collection types: `List[T]`, `Set[T]`, and `Dict[K, V]`.

```koral
let a = [1, 2, 3];                    // inferred as List[Int]
let b Set[Int] = [1, 2, 3];           // inferred as Set[Int] from context
let c = ["x": 1, "y": 2];             // inferred as Dict[String, Int]
let empty List[Int] = [];             // empty literal requires type context
```

Rules:

- `[e1, e2, ...]` is a collection literal. Without type context, it is inferred as `List[T]`.
- In `Set[T]` context, the same syntax is inferred as Set.
- `[k1: v1, k2: v2, ...]` is a dict literal and is inferred as `Dict[K, V]`.
- `[]` cannot be inferred without type context and must be annotated.
- Trailing commas are allowed for both collection and dict literals.
- Collection literals only target built-in `List` / `Set` / `Dict`, not third-party container types.

`List`, `Set`, `Dict` and `Deque` are `type mutable` shared objects: they do not use copy-on-write. Mutating a container is visible through every handle, and an independent copy must be made explicitly with `clone()`.

### Variables and Bindings

Koral's variables use binding semantics, equivalent to binding a variable name and a value together. For safety reasons, variables are immutable by default, but we also provide mutable variables.

#### Read-only Bindings

In Koral, read-only variables are declared using the `let` keyword, following the principle of declaration before use.

Koral ensures type safety through static typing. Variable bindings can explicitly annotate types at declaration. When there is enough information in the context, we can also omit the type, and the compiler will infer the variable's type.

```koral
let a Int = 5;   // Explicit type annotation
let b = 123;     // Automatic type inference
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
let mutable a Int = 5;   // Explicit type annotation
let mutable b = 123;     // Automatic type inference
```

#### Pair Destructuring

When the right-hand side expression is a `Pair`, you can use parenthesized syntax to bind each element to a separate variable. Each binding position supports `_` (discard), `mutable` (mutable), and an optional type annotation.

```koral
let (a, b) = (1, 2);                  // Type inference
let (c Int, d String) = (3, "hello");  // Explicit type annotations
let (mutable e, f) = (10, 20);             // Mutable binding
let (_, g) = (1, 2);                   // Discard first element
```

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
- A block may end with a final expression that does not use a trailing semicolon.
- If a block has a final expression, the block's type and value are the type and value of that expression.
- If a block has no final expression, or the last expression ends with a semicolon, the block's type is `Void`.
- `return`, `break`, and `continue` can end the block early and therefore give that block type `Never`.
- Plain `break` (without expression) exits the nearest enclosing `while` or `for` loop.
- A block ending with `return`, `break`, or `continue` has type `Never`.

Examples:

```koral
let load(path String) Result[Int] = {
    let text = read_text_file(path) or return;
    return parse_int(text);
};

let increment() Int = {
    let base = 41;
    base + 1
};

let a Void = {};
let main() Void = {
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

Comparison operators compare two values. The result is `Bool` type. Note that not equal is represented by `<>`.

```koral
let a = 4;
let b = 2;
println( a == b );     // == Equal
println( a <> b );     // <> Not equal
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
1..;      // 1 <= x      (Right unbounded, inclusive start)
1<..;     // 1 < x       (Right unbounded, exclusive start)
..5;      // x <= 5      (Left unbounded, inclusive end)
..<5;     // x < 5       (Left unbounded, exclusive end)
..;       // Full range
```

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

#### Operator Precedence

Operator precedence from high to low:

1. Postfix: calls `()`, subscripts `[]`, member access `.`, qualified paths `Type(Trait)`, generic method suffixes
2. Prefix / Control flow: unary `-`, `~`, dereference `*`, raw address-of `&unsafe`, `&unsafe mutable`; `if`, `while`, `for`, `when`
3. Multiplication/Division: `*`, `/`, `%`
4. Addition/Subtraction: `+`, `-`
5. Shift: `<<`, `>>`
6. Bitwise AND: `&`
7. Bitwise XOR: `^`
8. Bitwise OR: `|`
9. Comparison: `==`, `<>`, `<`, `>`, `<=`, `>=`
10. Range: `..`, `..<`, `<..`, `<..<`
11. Pattern test: `is`, `is not`
12. Logical NOT: `not`
13. Optional chaining: `and then`
14. Logical AND: `and`
15. Value coalescing / early-return propagation: `or else`, `or return`
16. Logical OR: `or`

When mixing `and then`, `or else`, and `or return` in one expression, use parentheses to make intent explicit.

### Functions

Functions are independent blocks of code used to complete specific tasks.

#### Definition

Functions are defined using the `let` keyword. The function name is followed by `()` indicating the parameters, and the return type follows the parentheses. Named functions and methods must spell out the return type explicitly.

The right side of `=` must declare an expression, and the value of this expression is the return value of the function.

```koral
let f1() Int = 1;
let f2(a Int) Int = a + 1;
let f3(a Int) Int = a + 1;
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

Declared as `name Type` (no colon). A positional parameter must be passed **by
position** — it can never be passed by label.

```koral
let add(x Int, y Int) Int = x + y;
let a = add(1, 2); // a == 3
```

##### Named Parameters

Declared as `name: Type` (with colon). A named parameter must be passed **by
label**.

```koral
let connect(host String, port: Int) Void = {};
connect("localhost", port: 8080);
```

##### Mixing Rules

A parameter's declaration fixes its call shape with no exceptions:

- Declared named (`name: Type`) → the call **must** use the label.
- Declared positional (`name Type`) → the call **must not** use a label.

There is no optional-label form: the declaration chooses one of exactly two call shapes. Positional parameters must come before named parameters in the declaration; at the call site, positional arguments are matched by position first, then named arguments are matched by label.

```koral
type Window(title String, width: Int, height: Int);

// Positional fills 'title'; named 'width'/'height' must be labelled
let w = Window("hello", width: 900, height: 600);
// Window("hello", 900, 600)      // error: 'width' must be passed by label
// Window("hello", width: 900, height: 600, title: "x")  // error: 'title' is positional
```

##### Default Values

Only named parameters can have default values. A default value is specified as a literal after `=`:

```koral
type Config(
    count: Int = 42,
    name: String = "hello",
    enabled: Bool = true,
    ratio: Float64 = 3.14,
    ch: Rune = 'A',
    items: List[Int] = [],
    flags: Dict[String, Int] = [],
    span: Range[Int] = ..,
);
```

Supported default value literals:

| Kind | Examples |
|------|----------|
| Integer | `0`, `42`, `-1` |
| Float | `3.14`, `0.0` |
| Bool | `true`, `false` |
| String | `"hello"` |
| Rune | `'A'` |
| Empty collection | `[]` (List, Set, or Dict, inferred from type context) |
| Empty range | `..` (resolves to `Range[T].Full()`) |

The default value type must match the parameter type. For example, `name: String = 42` is an error.

Mutable parameters use the `mutable` keyword:

```koral
let increment(mutable x Int) Int = { x += 1; return x };
```

For ordinary parameters, `mutable` only makes the local binding writable inside the function body. It is not part of the function signature, does not change the function type, and is ignored when checking trait/given method compatibility.

##### Constructor Calls

Struct, enum, and function calls all follow the same positional/named rules —
the declaration decides, the call obeys:

```koral
type Shape {
    Circle(radius Float64),            // positional case parameter
    Line(start: Point, end: Point),    // named case parameters
}

// Positional parameter: passed by position, never by label
let s1 = Shape.Circle(1.0);

// Named parameters: passed by label (argument order may vary)
let s2 = Shape.Line(end: Point(1, 1), start: Point(0, 0));
// Shape.Line(Point(0, 0), Point(1, 1))   // error: 'start' must be passed by label
```

Pattern matching destructures under exactly the same label rules: a field
declared named must be matched by label, and a field declared positional must
not be.

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start: p, end: e) then println(p.x),
}

if b is Button(w, height: _, label: l) then println(l);
// Button declares `width` positional and `height`/`label` named
```

#### Function Types

In Koral, functions are also a type. Function types are declared using `Func(T1, T2, ...) R` syntax, where `T1, T2, ...` are parameter types and `R` is the return type.

```koral
let square(x Int) Int = x * x;        // Func(Int) Int
let f Func(Int) Int = square;
let a = f(2);                         // a == 4
```

We can also define function type parameters or return values:

```koral
let hello() Void = println("Hello, world!");
let run(f Func() Void) Void = f();
let toRun() Func(Func() Void) Void = run;

let main() Void = toRun()(hello);
```

### Lambdas and Closures

#### Lambda Expressions

Lambda expressions are very similar to function definitions, except that `=` is replaced by `->`, and there is no function name or `let` keyword.

```koral
let f1(x Int) Int = x + 1;            // Func(Int) Int
let f2 = (x Int) Int -> x + 1;        // Func(Int) Int
let a = f1(1) + f2(1);                // a == 4
```

When the type of lambda can be inferred from context, parameter types and return type can be omitted:

```koral
let f Func(Int) Int = (x) -> x + 1;
```

Lambda supports multiple forms:

```koral
() -> 42;                           // No parameters
(x) -> x * 2;                      // Single param, type inferred
(x Int) -> x * 2;                  // Single param with type
(x, y) -> x + y;                   // Multiple params, types inferred
(x Int, y Int) Int -> x + y;       // Full type annotations
(x) -> { let y = x * 2; return y + 1 };  // Block body
```

#### Closures

Lambda expressions can capture variables from their surrounding scope. This is called a closure.

```koral
let make_adder(base Int) Func(Int) Int = {
    return (x) -> base + x;
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
let make_counter() Func() Int = {
    let counter = Cell(0);              // shared mutable state
    return () -> {
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
let add = () -> { xs.push(30) };   // ok: `xs` is a shared handle
```

#### Currying

Closures enable currying:

```koral
let add Func(Int) Func(Int) Int = (x) -> (y) -> x + y;

let add10 = add(10);
let result = add10(32);  // result == 42
let sum = add(20)(22);   // sum == 42
```

## 2. Control Flow

### Conditional Expressions

Selection structures are used to judge given conditions and control the flow of the program.

In Koral, selection structures use `if` syntax. `if` is followed by a judgment condition. When the condition is `true`, the `then` branch is executed. When the condition is `false`, the `else` branch is executed. `if` is always an expression. With both `then` and `else`, it produces a value; without `else`, the single-branch `if` produces `Void`.

```koral
let main() Void = if 1 == 1 then println("yes") else println("no");
```

`if` with `else` is also an expression. The `then` and `else` branches must be followed by expressions.

```koral
let main() Void = println(if 1 == 1 then "yes" else "no");
```

Since `if` itself is also an expression, `else` can naturally be followed by another `if` expression for chained conditions.

```koral
let x = 0;
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less";
```

When we don't need to handle the `else` branch, we can omit it. In that case the construct is a statement and does not produce a value; its block branch still defaults to `Void`.

```koral
let main() Void = if 1 == 1 then println("yes");
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

### Loops

#### while Statement

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

In each iteration, the next value produced by the iterator will try to match `pattern`. If the match is successful, the statement body following `then` is executed. `for` is an expression that produces `Void`.

```koral
let nums List[Int] = [10, 20, 30];
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

The loop binding position accepts the same shapes as `let`: a single binding or a `Pair` destructuring binding. Each element may use `_`, `mutable`, and an optional type annotation.

```koral
let pairs List[Pair[Int, Int]] = [Pair(1, 2), Pair(3, 4)];

for (left, right) in pairs then {
    println((left + right).to_string());
};
```

#### break and continue

- `break`: Exit the loop. Cannot penetrate through the innermost exitable construct (loop or branch).
- `continue`: Skip the current iteration.

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
- Plain `break` (without expression) exits the nearest enclosing `while` / `for` loop.

`break` cannot penetrate the innermost exitable construct: it cannot cross a branch boundary to reach an outer loop target.

### Cleanup with `defer`

The `defer` statement declares a cleanup expression to be executed when the current block scope exits. The deferred expression runs regardless of whether the scope exits normally or early via `return`, `break`, or `continue`.

When execution takes a `Never` termination path (for example `panic()`, `abort()`, or `exit()`) and the program terminates immediately, execution of in-scope `defer` is not guaranteed.

`defer` is followed by an expression whose return value is discarded.

```koral
let main() Void = {
    println("start");
    defer println("cleanup");
    println("work");
    // Output: start, work, cleanup
};
```

Multiple `defer` statements in the same scope execute in reverse declaration order (LIFO):

```koral
let main() Void = {
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
- `and then`: Optional chaining / value transformation. Applies the right-hand transformation when the left side is `Some` or `Ok`. If the right-hand side already produces the same `Option` / `Result` kind, the result is flattened by one layer.
- `or return`: Early-return propagation sugar. It unwraps `Some` / `Ok`, and on `None` / `Error` returns from the enclosing function.

In `and then` and `or else` expressions, the keyword `it` refers to the unwrapped value: for `and then`, `it` is the inner `Some` or `Ok` value; for `or else` on a `Result`, `it` is the `Error` value.

Precedence follows the parser: `and then` binds tighter than logical `and`, while `or else` / `or return` bind tighter than logical `or` but looser than logical `and`.

```koral
let opt = Option[Int].Some(42);
let val = opt or else 0;           // 42 (because opt is Some)

let none = Option[Int].None();
let val2 = none or else 0;         // 0 (because none is None)

let mapped = opt and then it * 2;  // Some(84)

let load_port(path String) Result[Int] = {
    let text = read_text_file(path) or return;
    return parse_int(text);
};
```

`or return` is equivalent to a fixed `or else` early-return pattern:

- For `Result`: `expr or return` is equivalent to `expr or else { return .Error(it) }`
- For `Option`: `expr or return` is equivalent to `expr or else { return .None() }`

It must be used inside a function whose return kind matches the propagated value:

- `Result` propagation requires the enclosing function to return `Result`
- `Option` propagation requires the enclosing function to return `Option`

## 3. Custom Types

Koral provides a powerful type system that allows you to define your own data structures. Use the `type` keyword to define a shallowly immutable nominal, and `type mutable` to define a shared object.

### `type`: Shallowly Immutable Nominals

A `type` declaration introduces a nominal type whose fields are all immutable. Values of a `type` have **no identity**, and the compiler decides the layout — inline, hidden indirection, or shared backing. Value semantics is not promised: copies may share storage, which is unobservable precisely because the type is shallowly immutable.

Struct fields can be positional or named. Named fields use colon syntax and can have default values.

#### Definition

```koral
type Empty();
type Point(x Int, y Int);

type Config(
    name String,               // positional field
    width: Int,                // named field (no default)
    height: Int = 600,         // named field with default
    title: String = "Untitled" // named field with default
);
```

Rules:

- Positional fields must come before named fields.
- Only named fields can have default values.
- Default values must be literals: integer, float, bool, string, rune, `[]` (empty collection), or `..` (empty range).
- A `type` cannot declare `mutable` fields, and cannot be declared `mutable` itself (`type mutable` is the other declaration form).

#### Construction

Use `()` syntax to call the constructor:

```koral
let a Point = Point(0, 0);

// Named fields are called with labels; positional fields are not
let c1 Config = Config("main", width: 800);
let c2 Config = Config("main", width: 800, height: 900, title: "App");
// height and title use their defaults: 600 and "Untitled"
```

#### Field Access

Use `.` syntax to access member variables. Fields of a `type` are read-only:

```koral
type Point(x Int, y Int);

let main() Void = {
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
type mutable Counter(mutable value Int, id UInt);

let main() Void = {
    let c = Counter(0, 1);
    c.value = 5;  // ok, because Counter is `type mutable` and `value` is a mutable field
    // c.id = 2;  // error: `id` is not a mutable field
};
```

The mutability of member variables follows the type definition, not the binding: a read-only binding to a `type mutable` object can still mutate that object's `mutable` fields.

```koral
type mutable Counter(mutable value Int);

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
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
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
let a Option[Int] = .Some(42);
let b Option[Int] = .None();

// In function arguments
let process(opt Option[Int]) Void = when opt in {
    .Some(v) then println(v.to_string()),
    .None() then println("none"),
};
process(.Some(10));

// In assignments
let mutable x Option[Int] = .None();
x = .Some(100);

// In conditional expression branches
let c Option[Int] = if true then .Some(1) else .None();

// Static method calls — omit the List[Int] prefix
let list List[Int] = .new();
let list2 List[Int] = .with_capacity(10);
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

let distance Meters = 100;
let add_meters(a Meters, b Meters) Meters = a + b;
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
file_private type InternalId = Int;  // File-scoped only
```

Restrictions:

- Type aliases do not support generic parameters (e.g., `type Alias[T] = List[T]` is invalid), but the target type can be a generic instantiation (e.g., `type IntList = List[Int]`).
- Circular references are not allowed (e.g., `type A = A`).
- Type alias names must start with an uppercase letter.
- A type alias cannot be declared `mutable` — mutability is a property of the nominal declaration, not of an alias.

### Generics

Generics allow you to write code that applies to multiple types, improving code reusability.

#### Generic Data Types

Generic data types use `TypeName[T Constraint]` syntax to define generic parameters:

```koral
type Pair[T1 Any, T2 Any](left T1, right T2);
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

Pair also supports a literal form:

```koral
let p1 = (1, 2);               // Equivalent to Pair(1, 2)
let p2 = (true, "hello");     // Equivalent to Pair(true, "hello")
```

#### Generic Functions

Generic functions write type parameters after the function name:

```koral
let identity[T Any](x T) T = x;

println(identity(42));       // 42
println(identity("hello"));  // hello
```

#### Generic Constraints

Generic parameters can specify Trait constraints to limit acceptable types:

```koral
let max_val[T Ord](a T, b T) T = if a > b then a else b;
let contains[T Eq](list List[T], value T) Bool = list.contains(value);
```

Multiple constraints are connected with `and`:

```koral
let describe[T ToString and Hash](value T) String = value.to_string();
```

Constraints can also use generic trait forms (for example `Iterator[T]`), and the
special `mutable` constraint used by weak references (it requires a `type mutable`
type, as `downgrade` / `upgrade` do):

```koral
let consume[I Iterator[Int]](iter I) Void = {};
```

#### Generic Methods

`given` blocks can also define generic methods:

```koral
given[T Any] Option[T] {
    public map[U Any](self, f Func(T) U) Option[U] = self and then f(it);
}
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
- Inside a `given Type as Trait` block, `Self` is equivalent to `Type`.
- `Self` can appear in method parameter types, return types, and field types within trait/given contexts.

```koral
trait Eq {
    equals(self, other Self) Bool;
};

type Point(x Int, y Int);

given Point as Eq {
    // Here Self resolves to Point, so `other Self` is the same as `other Point`.
    equals(self, other Point) Bool = self.x == other.x and self.y == other.y;
};
```

### Memory and Resources

Koral provides efficient and safe memory management through declaration-site type semantics and compiler-managed layout.

#### Memory Model

- **`type`** (shallowly immutable): no identity, and no promise of value semantics. The compiler may use stack slots, registers, inline storage, hidden heap blocks or reference counting — whichever it can prove correct — because the sharing it introduces cannot be observed.
- **`type mutable`** (shared object): identity is part of the semantics. Assignment and argument passing share the same object. Only explicitly declared `mutable` fields can be modified in place.
- **Raw pointers**: `&unsafe` / `&unsafe mutable` form raw pointers only from addressable storage. They are low-level memory access for FFI and remain subject to address-stability and layout constraints (see [External Interop](#6-external-interop)).
- **Reference counting is an implementation detail.** The compiler may use ARC and hidden storage internally for both forms. The language contract is `type` versus `type mutable`, never a managed-reference syntax.

#### `Drop`

Types that need a cleanup step implement the `Drop` trait:

```koral
trait Drop {
    drop(self) Void;
};
```

`Drop.drop` is a compiler-only destructor entry point running in a finalization context. It is not called as an ordinary user method. A type that implements `Drop` is always reference-counted, and its `drop` runs when the last owning handle dies.

#### `clone()`

Shared objects are never copied implicitly. When an independent copy is genuinely needed, ask for it explicitly with `clone()`:

```koral
trait Clone {
    clone(self) Self;
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

Use `downgrade(T)` to create `?T`, and `upgrade(?T)` to attempt upgrading back to `Option[T]`.

```koral
type mutable Node(mutable value Int);

let node = Node(42);
let weak = downgrade(node);      // ?Node
let upgraded = upgrade(weak);    // Option[Node]
```

## 4. Pattern Matching

Koral has powerful pattern matching capabilities, mainly used through `when` expressions and the `is` operator. Patterns are also the binding form used in `if` and `while` conditions and in `for` loops.

### Pattern Forms

Supported patterns include:

- Wildcard pattern: `_` (matches any value)
- Literal patterns: `1`, `-5`, `"abc"`, `'a'`, `true` (negative integer literals such as `-5` are supported)
- Variable binding patterns: `x` (matches any value and binds to x), `mutable x` (mutable binding)
- Comparison patterns: `> 5`, `< 0`, `>= 10`, `<= -1`
- Struct destructuring patterns: `Point(x, y)`, `Rect(Point(a, b), w, h)`
- Pair destructuring pattern: `(a, b)` (equivalent to `Pair(a, b)` pattern)
- Enum case patterns: `.Some(v)`, `.None()`
- Trait-object exact type patterns: `IoError`, `err IoError`
- Logical patterns: `pattern and pattern`, `pattern or pattern`, `not pattern`

Destructuring follows exactly the call rules: a field declared named must be
matched by label, and a field declared positional must not be.

```koral
when s in {
    .Circle(r) then println(r),
    .Line(start: p, end: e) then println(p.x),
};

if b is Button(w, height: _, label: l) then println(l);
```

### `when` Expressions

The `when` expression allows you to compare a value against a series of patterns and execute corresponding code based on the matching pattern. It is similar to `switch` statements in other languages, but more powerful. `when` is always an expression. A single-branch `when` produces `Void`; with more than one branch it returns the value of the matching branch.

```koral
let x = 5;
let result = when x in {
    1 then "one",
    2 then "two",
    _ then "other",
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
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
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
type Point(x Int, y Int);
type Rect(origin Point, width Int, height Int);

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
    render(self) String;
};

type IoError(code Int);

given IoError as Problem {
    render(self) String = "io";
};

let err Problem = IoError(7);
when err in {
    io IoError then println(io.render()),
    _ then println("other"),
};

// Wildcard and literal field matching
when p in {
    Point(0, y) then println(y),  // Match when first field is 0
    Point(_, y) then println(y),  // Ignore first field
};

// Generic struct destructuring
type Box[T Any](val T);
let b = Box[Int](42);
when b in {
    Box(v) then println(v),  // 42
};
```

### `is` Tests

The `is` operator checks whether a value matches a pattern, and the result is always `Bool`. It is a general-purpose expression and can appear in `let` initializers, return expressions, function arguments, and other expression positions.

`is not` is the negated form and returns the inverse match result.

When used in the condition of an `if` or `while` statement, a successful `is` match can also bind variables from the pattern into the current scope. Outside those condition contexts, `is` may only perform a boolean test and may not introduce bindings. The `when ... in` construct uses its own pattern matching on the matched value and does not use `is` for binding.

`is` accepts a single pattern directly. If you need logical pattern combinators under `is`, group them explicitly with parentheses so the parser can distinguish them from expression-level `and` / `or` / `not`.

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

if x is (0 or 1) then {
    println("small");
};

// Standard boolean composition still works in conditions
if opt is .Some(v) and v > 0 then {
    println(v);
};
```

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
if x is (0 or 1) then {
    println("small");
};
```

### Exhaustiveness Checking

The `when` expression checks that patterns are exhaustive:

- For `Bool` types, both `true` and `false` must be covered (or a wildcard used).
- For `enum` types, all cases must be covered (or a wildcard used).
- For `Int` / `UInt` types, comparison patterns (`> 0`, `<= 0`, etc.) can establish exhaustiveness when they fully cover the integer range. A wildcard is otherwise required.
- For struct types, `StructName(_, _)`-style patterns with wildcards for every field are treated as exhaustive.
- Duplicate patterns are rejected at compile time.
- Unreachable patterns (patterns already covered by earlier arms) are rejected at compile time. Wildcard and variable binding patterns are exempt from this check.

```koral
// Exhaustive via comparison patterns
let classify(x Int) Int = when x in {
    > 0 then 1,
    <= 0 then 0,
};
```

### Exact Type Patterns

Trait objects also support exact implementation-type testing through the pattern system.

```koral
trait Problem {
    render(self) String;
};

type IoError(code Int);
type NetError(code Int);

given IoError as Problem {
    render(self) String = "io";
};

given NetError as Problem {
    render(self) String = "net";
};

let err Problem = IoError(7);

if err is IoError then {
    println("io");
};

if err is io IoError then {
    println(io.render());
};

let label = when err in {
    io IoError then io.render(),
    _ then "other",
};
```

Rules:

- Exact type patterns are only valid when the subject is a trait object.
- The target must be a concrete type name.
- Matching is exact on the implementation type and its generic arguments.
- The subject stays a trait object; it is not auto-dereferenced to the implementation value. `err is io IoError` binds `io` as `IoError`.
- These patterns are open-world tests; in `when`, they do not count as exhaustive coverage, so a default `_` arm is still required.

## 5. Abstraction

Koral uses Traits to define shared behavior. This is similar to interfaces or type classes in other languages.

### Traits and `given` Blocks

#### Defining a Trait

A Trait defines a set of method signatures that any implementing type must provide.

```koral
trait Printable {
    to_string(self) String;
};
```

Traits support inheritance using parent Trait names:

```koral
trait Ord Eq {
    compare(self, other Self) Int;
};
```

Multiple parent Traits are connected with `and`:

```koral
trait MyTrait Eq and Hash {
    my_method(self) Int;
};
```

#### Implementing a Trait

Use a `given Type as Trait { ... }` impl block to implement a Trait for a specific type:

```koral
trait Eq {
    equals(self, other Self) Bool;
};

trait Ord Eq {
    compare(self, other Self) Int;
};

type Point(x Int, y Int);

given Point as Eq {
    equals(self, other Point) Bool = self.x == other.x and self.y == other.y;
};

given Point as Ord {
    compare(self, other Point) Int = self.x - other.x;
};
```

Notes:

- `given Type as Trait` is the explicit conformance entry point.
- Parent/child traits are implemented level-by-level: implementing `Ord` does not implicitly implement `Eq`.

#### Named Parameters in Traits and Implementations

Trait methods support named parameters. Implementations must match the trait's parameter classification:

- If a trait method parameter is named (`name: Type`), the implementation must also declare it as named.
- If a trait method parameter is positional (`name Type`), the implementation must also declare it as positional.

Default value rules for trait and given:

- If the trait declares a default value for a named parameter, the given implementation **must not** redeclare it. The trait is the single source of defaults.
- If the trait declares no default value, the given implementation **cannot** add one.

```koral
trait Drawable {
    draw(self, color: String, thickness: Int) String;
};

type Circle(radius Int);

given Circle as Drawable {
    // 'color' and 'thickness' are named, matching the trait
    draw(self, color: String, thickness: Int) String = color + thickness.to_string();
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
    equals(self, other Self) Bool;
};

given Eq {
    not_equals(self, other Self) Bool = not self.equals(other);
};

type Num(x Int);

given Num as Eq {
    equals(self, other Num) Bool = self.x == other.x;
};

let a = Num(1);
let b = Num(2);
println(a.not_equals(b));
```

Constrained tool block example:

```koral
trait Cursor[T Any] {
    next(self) Option[T];
};

given[T Ord] Cursor[T] {
    max(self) Option[T] = {
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

- Generic constraint contexts (e.g. `[T Trait]`)
- Trait object contexts
- Concrete types that explicitly implement the trait

#### Override and Conflict Rules

- Tool methods are non-override by default.
- Inherent type methods win over trait tool methods.
- If the same method signature appears from multiple trait tool sources, Koral does not choose implicitly. You must disambiguate explicitly with a fully qualified call: `Type(TraitName).method(value, ...)`.
- If two traits define the same method and one inherits from the other, the child trait's implementation takes precedence (no ambiguity).
- `given Trait` cannot define a method with the same name/signature as a requirement of that trait.

#### Trait Inheritance Rules

- A trait can inherit from one or more parent traits: `trait Child Parent1 and Parent2 { ... }`.
- Trait inheritance is acyclic; cycles are detected and rejected at compile time.
- A type implementing a child trait must also implement all parent traits (directly or via a `given` block).

#### Module Boundary Rules

Boundary anchoring rules:

- `given Trait { ... }` is allowed only within the trait's root module subtree.
- `given Type { ... }` is allowed only within the type's root module subtree.
- `given Type as Trait { ... }` follows orphan rules: either the type or the trait must be local to the current root module.
- Cross-crate injection is not allowed.

### Fully Qualified Calls

When multiple candidates conflict, use a fully qualified call. The form is conceptually Rust's qualified path `<Type as Trait>::method`:

- `Type(TraitName).method(...)` selects `TraitName`'s method on `Type`
- Generic traits carry their arguments in the qualification: `Type(TraitName[Args...]).method(...)`
- Generic method type args still appear on the method: `Type(TraitName).method[TypeArgs...](...)`

There is a single written form. The receiver of an instance method is simply the first call argument, so instance and static trait methods are spelled the same way:

```
Type(TraitName).method(receiver, ...)   // instance method
Type(TraitName).static_method(...)      // static trait method
```

```koral
trait Tag {
    value(self) Int;
};

given Tag {
    plus_ten(self) Int = self.value() + 10;
    kind(self) Int = 42;
};

type Num(x Int);

given Num as Tag {
    value(self) Int = self.x;
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

- The target type is a trait name.
- The source value must implement the trait and be converted into that trait-object context.
- No `Object` marker trait is required.

```koral
trait Drawable {
    draw(self) String;
};

type Circle(radius Int);

given Circle as Drawable {
    draw(self) String = "Drawing circle";
};

let shape Drawable = Circle(10);
shape.draw();
```

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
    message(self) String;
};

// Not object-safe — cannot be used as a trait object
trait Eq {
    equals(self, other Self) Bool;
};
```

Exact implementation-type tests on trait objects are described under [Exact Type Patterns](#exact-type-patterns).

### Operator Overloading

Koral supports trait-based operator overloading for arithmetic and comparison operations. Subscripts are built in and are not user-overloadable.

The built-in operator mappings are:

- `+` -> `Add[R]` via `add(self, other R) Self`
- `-` (binary) -> `Sub[R]` via `sub(self, other R) Self`
- `-` (unary) -> `Neg` via `neg(self) Self`
- `*` -> `Mul[R]` via `mul(self, other R) Self`
- `/` -> `Div[R]` via `div(self, other R) Self`
- `%` -> `Rem[R]` via `rem(self, other R) Self`
- `==` / `<>` -> `Eq` via `equals(self, other Self) Bool`
- `<` / `>` / `<=` / `>=` -> `Ord` via `compare(self, other Self) Int`

Same-direction chained ordering comparisons such as `a < b < c` are syntax sugar over these existing comparison operators. The compiler lowers them into pairwise comparisons with single-evaluation and short-circuit semantics; they do not introduce a separate trait or dispatch mechanism.

Bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`) are currently built-in and are not customized through public operator traits.

```koral
type Vec2(x Int, y Int);

given Vec2 as Add[Vec2] {
    add(self, other Vec2) Vec2 = Vec2(self.x + other.x, self.y + other.y);
};

given Vec2 as Neg {
    neg(self) Vec2 = Vec2(-self.x, -self.y);
};

given Vec2 as Eq {
    equals(self, other Vec2) Bool = self.x == other.x and self.y == other.y;
};

given Vec2 as Ord {
    compare(self, other Vec2) Int =
        if self.x <> other.x then self.x.compare(other.x) else self.y.compare(other.y);
};

let sum = Vec2(1, 2) + Vec2(3, 4);
let flipped = -sum;
let same = sum == Vec2(4, 6);
let ordered = Vec2(1, 0) < Vec2(2, 0);
```

#### Builtin Subscript Rules

- `value[key]` and `value[key] = expr` are supported only for `String`, `List[T]`, `Deque[T]`, `*unsafe T`, and `*unsafe mutable T`.
- `String[key]` returns a `UInt8` byte value. It is read-only and not addressable.
- `List[T]` and `Deque[T]` (both `type mutable`) support value reads, assignment, and nested place updates.
- `*unsafe T` supports `*expr` reads only. `*unsafe mutable T` supports both `*expr` reads and writes.
- User-defined types cannot implement `[]` through traits, and generic constraints cannot add subscript capability.

```koral
let list = [10, 20, 30];
println(list[0]);
list[1] = 99;

let text = "abc";
let b UInt8 = text[1];

let p *unsafe mutable Int = alloc_memory[Int](2);
p[0] = list[0];
let first = p[0];
dealloc_memory(p);
```

### Extension Methods

The `given` block can also be used to directly add methods to types:

```koral
given Point {
    public distance(self) Float64 = {
        let dx = self.x(Float64);
        let dy = self.y(Float64);
        return dx + dy; // ...
    };

    // Methods without self are called via type name
    public origin() Point = Point(0, 0);
};

let p = Point.origin();
```

### Standard Library Core Traits

The most commonly used core traits are:

- `Add[R]` / `Sub[R]` / `Neg` / `Mul[R]` / `Div[R]` / `Rem[R]`: arithmetic operator traits.
- `Eq` / `Ord`: equality and ordering.
- `Hash`: hash support for dict/set keys.
- `ToString`: conversion to string.
- `Clone`: explicit shallow copy (`clone(self) Self`).
- `Iterator[T]`: iteration protocol (`next(self) Option[T]`).
- `Error`: error message interface (`message(self) String`).
- `Drop`: destructor hook (`drop(self) Void`).

Arithmetic and comparison operators are lowered to trait methods internally (for example `+` to `Add`). Subscripts are resolved by builtin compiler rules instead of public traits.

### Modules and Visibility

Koral provides a powerful module system for organizing code across multiple files and directories.

#### Module Concepts

A **module** in Koral is an explicit build unit declared in `koral.json` (or `std/koral.json` for the standard library). A module consists of its entry file plus any files merged into it via `using "path"`.

- **Target module**: The module selected by `--target-module`
- **Peer module**: Another manifest-declared module in the same package
- **External module**: A module coming from std or another package dependency
- Top-level manifest `entry`: The default target module name, for example `app::main`

Entry filename constraints:

- Module entry file basename must start with a lowercase letter.
- Remaining characters may only be lowercase letters, digits, or `_`.
- Source-level module names come from the manifest and use `::` separators (for example, `app::models`, `std::io`).

#### Using Declarations

The `using` keyword is used for file merge and explicit symbol import. All `using` declarations must appear at the beginning of a file, before any other declarations.

##### File Merge

Use string syntax to merge another file into the current module scope:

```koral
using "utils";        // Merges utils.koral into current module
using "./helpers";    // Relative paths are allowed
using "../shared/format";
```

File merge rules:

1. The path is resolved relative to the current file's directory.
2. The string names a source file without the `.koral` suffix.
3. Relative segments such as `.` and `..` are allowed.
4. File merge does not create a namespace, alias, or export surface.
5. Merged files share the same module scope, so `module_private` declarations remain visible across files in that module.

##### Module Symbol Import

Import visible symbols from another module with explicit braces:

```koral
using std::io { Reader };
using std::json { parse, Value };
using std::io { Reader as IoReader, Writer };
using std::io { .. };
```

Notes:

1. `using module { symbol-list }` imports symbols visible to the importing file: `public` from any package, and `package_private` when the importer is in the same package.
2. `as` applies per imported symbol, not to the module itself. An import alias binds the original declaration — it does not create a new entity.
3. `using module { .. }` imports all symbols visible to the importing file, and `..` must appear alone.
4. Imported names are file-local bindings and are not re-exported automatically.
5. Module legality is checked against manifest `requires`; the compiler does not infer modules from directory structure.
6. Non-`std` packages get `std` automatically; do not list `std` manually in application/test package manifests.
7. A module import never binds the module name as a namespace object. Import `Reader` with `using std::io { Reader }`, then write `Reader`, not `std.io.Reader` or `io.Reader`.

#### Access Modifiers

Koral provides four access levels to control symbol visibility:

| Modifier | Visibility |
|----------|------------|
| `public` | Accessible from anywhere |
| `package_private` | Accessible from any module in the same package |
| `module_private` | Accessible within the current logical module |
| `file_private` | Accessible only within the same file |

Package scope follows the manifest graph: the root package, `std`, and each dependency package are separate package boundaries.

##### Default Access Levels

| Declaration | Default |
|-------------|---------|
| Global functions, variables, types | `module_private` |
| Struct fields | `public` |
| Enum constructor fields | `public` |
| Member functions (in `given` blocks) | `module_private` |
| Trait methods | `public` |

Direct struct construction `Type(...)` is only allowed when all referenced fields are visible at the call site.
If a type has inaccessible `file_private`/`module_private`/`package_private` fields, use an exposed public factory method.

### Project Structure Example

```
my_project/
├── koral.json;
├── main.koral           # app::main entry;
├── utils.koral          # merged into app::main;
├── models/
│   ├── models.koral     # app::models entry;
│   └── user.koral       # merged into app::models;
└── services/
    └── services.koral   # app::services entry;
```

```json
{
  "name": "MyProject",
  "version": "0.1.0",
  "entry": "app::main",
  "modules": {
    "app::main": {
      "entry": "main.koral",
      "requires": ["app::models", "app::services"],
      "links": [];
    },
    "app::models": {
      "entry": "models/models.koral",
      "requires": [],
      "links": [];
    },
    "app::services": {
      "entry": "services/services.koral",
      "requires": ["app::models"],
      "links": [];
    }
  }
}
```

```koral
// main.koral
using "utils";
using app::models { User };
using app::services { authenticate };
using std { .. };

public let main() Void = {
    let user = User.new("Alice");
    if authenticate(user) then {
        println("Welcome!");
    };
};
```

## 6. External Interop

This chapter collects the low-level surface: raw pointers, unsafe address-taking, and the C foreign function interface.

### Raw Pointer Types

Raw pointers are low-level memory access for FFI and system programming:

- `*unsafe T` — read-only pointer. Supports `*expr` dereference read but NOT `*expr` assignment or `p[i]` assignment.
- `*unsafe mutable T` — mutable pointer. Supports `*expr` dereference read, `*expr = value` assignment, `p[i]` read, and `p[i] = value` assignment.
- `*unsafe mutable T` implicitly converts to `*unsafe T`. The reverse is not allowed.

### Unsafe Address-Of and Dereference

`&unsafe` / `&unsafe mutable` are raw address-of operators. They require addressable storage; literals and temporaries are rejected.

```koral
let p *unsafe Int = &unsafe value;
let mp *unsafe mutable UInt8 = &unsafe mutable bytes[0];

let x = *p;       // raw deref read
*mp = 42;         // raw deref write

// let bad = &unsafe 42  // error: raw address-of needs addressable storage
```

Rules:

- `&unsafe` produces `*unsafe T`; `&unsafe mutable` produces `*unsafe mutable T`.
- `*expr` reads and `*expr = value` writes are the raw dereference forms.
- Raw pointers are not a general "any type to `*unsafe T`` bridge: the std helpers that hand out raw pointers are restricted to plain-old-data element types.

### Foreign Function Interface

Koral supports interoperability with C through the `foreign` keyword.

#### Linking External Libraries

Native libraries are declared in package or module `links` inside `koral.json` / `std/koral.json`:

```json
{
  "modules": {
    "app::main": {
      "entry": "main.koral",
      "requires": [],
      "links": ["m"];
    }
  }
}
```

The compiler adds linker flags from the resolved manifest graph. `libc` is implicitly linked by default and does not need to be declared.

#### Foreign Functions

Declare external C functions. Foreign functions use positional parameters only; named parameters (colon syntax) are not supported.

```koral
foreign let sin(x Float64) Float64;
foreign let exit(code Int) Never;
foreign let abort() Never;
```

#### Foreign Types

Declare external C types:

```koral
// Opaque type (no fields)
foreign type CFile {};

// FFI struct with fields (aligned with C layout)
foreign type KoralTimespec(tv_sec Int64, tv_nsec Int64);
```

A foreign type cannot be declared `mutable` — mutability is a property of Koral's own nominal declarations.

### Intrinsic Declarations

The `intrinsic` keyword declares types and functions built into the compiler:

```koral
public intrinsic type Int;
```

Intrinsics are reserved for the standard library.

## Appendix: Standard Library Essentials

Use these as the minimal everyday building blocks:

```koral
// List (shared object — clone() for an independent copy)
let nums List[Int] = [1, 2, 3];

// Dict
let scores Dict[String, Int] = ["alice": 10, "bob": 8];

// Set
let tags Set[String] = ["koral", "lang"];

// Option + or else / and then
let port = Option[Int].Some(8080) or else 80;
let doubled = Option[Int].Some(21) and then it * 2;

// or return
let read_number(path String) Result[Int] = {
    let text = read_text_file(path) or return;
    return parse_int(text);
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

For complete API reference, see docs under `docs/std/`.

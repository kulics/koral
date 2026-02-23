# The Koral Programming Language

Koral is an efficiency-focused open source programming language that helps you easily build cross-platform software.

Through carefully designed syntax rules, this language can effectively reduce reading and writing burden, allowing you to put your real attention on solving problems.

## Key Features

- Easy to distinguish, modern syntax.
- Automatic memory management (based on reference counting and ownership).
- Generics and Trait system.
- Multi-paradigm programming (combining functional and imperative).
- Cross-platform.

## Installation and Usage

Currently `Koral` supports compiling to `C`, so a C compiler needs to be installed on the system (such as `gcc` or `clang`).

### Compilation and Execution

Assuming you have a file named `hello.koral`.

1.  **Compile**: Run the compiler command (assuming the compiler is named `koralc`), it will scan all `.koral` files in the current folder and automatically translate them to target files with the same name (e.g., `hello` executable).
    ```bash
    koralc .
    ```
2.  **Run**: Run the generated executable directly.
    ```bash
    ./hello
    ```

## Basic Syntax

### Basic Statements and Semicolons

In Koral, statements are the smallest unit of composition.

The basic form of statements is as follows, usually consisting of a small piece of code ending with a semicolon `;`.

```koral
let a = 0;
let b = 1;
```

A statement usually ends with an explicit semicolon, but if the last expression of the statement is immediately followed by a newline, the semicolon can be omitted. This makes constructs like `if`, `while`, etc. look cleaner.

```koral
// Ends with a newline, semicolon omitted
let a = { 
    1 + 1 
} 

// Ends with a newline, semicolon omitted
let b = 1
let c = 2
```

### Entry Function

Every executable program needs an entry point. In Koral, this entry point is the `main` function. A typical `main` function declaration is as follows.

```koral
let main() = {}
```

Here we declare a function named `main`. The right side of `=` is the function body, `{}` represents an empty block expression, returning `Void`.

The `main` function can also accept parameters (command line arguments) and return an integer (status code), but this depends on the specific runtime environment support. More details about functions will be explained in later chapters.

### Display Information

The standard library provides the `print_line` function to print a line of text to the standard output.

```koral
let main() = print_line("Hello, world!")
```

Now try to execute this program, and we can see `Hello, world!` displayed on the console.

### Comments

Comments are parts of the code ignored by the compiler, used to provide explanations to people reading the code.

```koral
// This is a single-line comment, starting from double slashes to the end of the line

/*
    This is a block comment.
    It can span multiple lines.
    /* Koral supports nested block comments */
*/
```

### Variables

Koral's variables use binding semantics, equivalent to binding a variable name and a value together. For safety reasons, variables are immutable by default, but we also provide mutable variables.

#### Read-only Variables

In Koral, read-only variables are declared using the `let` keyword, following the principle of declaration before use.

Koral ensures type safety through static typing. Variable bindings can explicitly annotate types at declaration. When there is enough information in the context, we can also omit the type, and the compiler will infer the variable's type.

```koral
let a Int = 5   // Explicit type annotation
let b = 123     // Automatic type inference
```

Once a read-only variable is declared, its value cannot be changed within the current scope.

```koral
let a = 5
a = 6 // Error
```

#### Mutable Variables

If we need a variable that can be reassigned, we can use a mutable variable declaration with `let mut`.

```koral
let mut a Int = 5   // Explicit type annotation
let mut b = 123     // Automatic type inference
```

### Assignment

For mutable variables, we can change their value multiple times when needed.

```koral
let mut a = 0
a = 1  // Legal
a = 2  // Legal
```

### Block Expressions

In Koral, `{}` represents a block expression. A block expression can contain a series of statements and an optional final expression. The value of the last expression in the block is the value of the entire block. If there is no last expression, the value is Void.

```koral
let a Void = {}
let b Int = {
    let c = 7
    let d = c + 14
    (c + 3) * 5 + d / 3  // Return value of the block
}
```

### Identifiers

Identifiers are names given to variables, functions, types, etc. The naming rules are:

1. Case sensitive. `Myname` and `myname` are two different identifiers.
2. **Types** and **Constructors** must start with an **uppercase letter** (e.g., `Int`, `String`, `Point`).
3. **Variables**, **Functions**, **Members** must start with a **lowercase letter** or underscore (e.g., `main`, `print_line`, `x`).
4. Other characters in identifiers can be underscores `_`, letters, or numbers.
5. Within the same `{}`, identifiers with the same name cannot be defined repeatedly.
6. In different `{}`, identifiers with the same name can be defined, and the language will prioritize the identifier defined in the current scope.

## Basic Types

We only need a few simple basic types to carry out most of the work.

### Numeric Types

Koral provides rich numeric types to meet different needs. The default integer is `Int` type, and floating-point numbers use `Float64` (64-bit) or `Float32` (32-bit).

- `Int`: Platform-dependent signed integer (usually 64-bit).
- `UInt`: Platform-dependent unsigned integer (usually 64-bit).
- `Int8`, `Int16`, `Int32`, `Int64`: Fixed-width signed integers.
- `UInt8`, `UInt16`, `UInt32`, `UInt64`: Fixed-width unsigned integers.
- `Float32`: 32-bit floating-point number.
- `Float64`: 64-bit floating-point number.

```koral
let i Int = 3987349
let f Float64 = 3.14
let b UInt8 = 255
```

Numeric literals support underscores `_` as separators for readability:

```koral
let million = 1_000_000
let pi = 3.141_592_653
```

Koral also supports binary, octal, and hexadecimal integer literals using the `0b`, `0o`, and `0x` prefixes respectively:

```koral
let bin = 0b1010          // Binary, value is 10
let oct = 0o755           // Octal, value is 493
let hex = 0xFF            // Hexadecimal, value is 255
```

Non-decimal literals also support underscore separators:

```koral
let mask = 0xFF_FF        // Hexadecimal, value is 65535
let flags = 0b1010_0101   // Binary, value is 165
```

Note: Non-decimal literals only support integers, not floating-point numbers. Hexadecimal letters are case-insensitive (`0xABcd` is equivalent to `0xabCD`).

### Type Casting

Different numeric types require explicit conversion using `(Type)expr` syntax:

```koral
let a Int = 42
let b Float64 = (Float64)a    // Int -> Float64
let c Int32 = (Int32)a        // Int -> Int32
let d UInt8 = (UInt8)255      // Int -> UInt8
```

### Strings

In Koral, strings are used to represent text data. `String` type is a UTF-8 encoded character sequence.

You can use double quotes `""` or single quotes `''` to wrap text content.

```koral
let s1 String = "Hello, world!"
let s2 String = 'Hello, world!' // Same as s1
```

Koral supports string interpolation, allowing expressions to be embedded in strings using `\(expr)` syntax:

```koral
let name = "Koral"
let count = 3
print_line("Hello, \(name)!")                    // Hello, Koral!
print_line("Count: \(count)")                    // Count: 3
print_line("Mixed \(name) has \(count) messages") // Mixed Koral has 3 messages
print_line("Sum \(1 + (2 * 3))")                 // Sum 7
```

Escape characters use backslash `\`:

```koral
"\n"   // Newline
"\t"   // Tab
"\r"   // Carriage return
"\v"   // Vertical tab
"\f"   // Form feed
"\0"   // Null character
"\\"   // Backslash
"\""   // Double quote
"\'"   // Single quote
```

Common String methods:

```koral
let s = "Hello, World!"
s.count()                    // 13 - byte length
s.is_empty()                 // false
s.contains("World")          // true
s.starts_with("Hello")       // true
s.ends_with("!")             // true
s.to_ascii_lowercase()       // "hello, world!"
s.to_ascii_uppercase()       // "HELLO, WORLD!"
s.trim_ascii()               // Trim leading/trailing whitespace
s.slice(0..<5)               // "Hello" - slicing
s.find_index("World")        // Some(7)
s.replace_all("World", "Koral") // "Hello, Koral!"
s.split(",")                 // Split by separator
s.lines()                    // Split by lines

// Join a list of strings
join_strings(list, ", ")     // Join [String]List with separator
```

### Booleans

Booleans refer to logical values, they can only be true or false. The default boolean is `Bool` type.

```koral
let b1 Bool = true
let b2 Bool = false
let isGreater = 5 > 3 // Result is true
```

### Reference Types

Reference types are used to refer to another value rather than holding it. This is useful when sharing data or avoiding copying. Add the `ref` keyword after the type name to declare a reference type.

Use the `ref` expression to create a reference:

```koral
let a = ref 42           // Creates an Int ref
let b = deref a          // Dereference, gets 42
print_line(ref_count(a)) // Reference count
```

References use reference counting for automatic memory management. When the reference count drops to zero, memory is automatically freed.

#### Weak References

Weak references don't increase the reference count, used to break reference cycles. Use the `weakref` type suffix:

```koral
let strong = ref 42
let weak = downgrade_ref(strong)   // Downgrade to weak reference
let upgraded = upgrade_ref(weak)   // Try to upgrade, returns Option
```

### Memory Management

Koral aims to provide efficient and safe memory management, combining automatic memory management with manual control.

- **Value Semantics**: By default, types in Koral (such as `Int`, structs) have value semantics. Data is copied during assignment or parameter passing.
- **References**: Use the `ref` keyword to create references. Koral uses reference counting and ownership analysis to automatically manage reference lifecycles, preventing dangling pointers and memory leaks.
- **Move Semantics**: For variables that haven't been copied, assignment and parameter passing result in ownership transfer (Move). Once ownership is transferred, the original variable can no longer be used.

## Operators

Operators are symbols that tell the compiler to perform specific mathematical or logical operations.

### Arithmetic Operators

```koral
let a = 4
let b = 2
print_line( a + b )    // + Add
print_line( a - b )    // - Subtract
print_line( a * b )    // * Multiply
print_line( a / b )    // / Divide
print_line( a % b )    // % Modulus
```

### Comparison Operators

Comparison operators compare two values. The result is `Bool` type. Note that not equal is represented by `<>`.

```koral
let a = 4
let b = 2
print_line( a == b )     // == Equal
print_line( a <> b )     // <> Not equal 
print_line( a > b )      // > Greater than
print_line( a >= b )     // >= Greater than or equal to
print_line( a < b )      // < Less than
print_line( a <= b )     // <= Less than or equal to
```

### Logical Operators

Logical operators perform logical operations (AND, OR, NOT) on two Bool type operands.

```koral
let a = true
let b = false
print_line( a and b )       // AND, true only if both are true
print_line( a or b )        // OR, true if either one is true
print_line( not a )         // NOT, boolean negation
```

`and` and `or` have short-circuit semantics:

```koral
let a = false and f() // f() will not be executed
let b = true or f()   // f() will not be executed
```

### Bitwise Operators

```koral
let a = 4
let b = 2
print_line( a & b )    // Bitwise AND
print_line( a | b )    // Bitwise OR
print_line( a ^ b )    // Bitwise XOR
print_line( ~a )       // Bitwise NOT
print_line( a << b )   // Left shift
print_line( a >> b )   // Right shift
```

### Range Operators

Range operators generate a range (Range), commonly used in loops or pattern matching.

```koral
1..5     // 1 <= x <= 5 (Closed interval)
1..<5    // 1 <= x < 5  (Right open interval)
1<..5    // 1 < x <= 5  (Left open interval)
1<..<5   // 1 < x < 5   (Open interval)
1...     // 1 <= x      (Right unbounded, inclusive start)
1<...    // 1 < x       (Right unbounded, exclusive start)
...5     // x <= 5      (Left unbounded, inclusive end)
...<5    // x < 5       (Left unbounded, exclusive end)
....     // Full range
```

### Compound Assignment

```koral
let mut x = 10
x += 5       // x = x + 5
x -= 2       // x = x - 2
x *= 3       // x = x * 3
x /= 2       // x = x / 2
x %= 4       // x = x % 4

let mut y = 12
y &= 10     // y = y & 10
y |= 1      // y = y | 1
y ^= 15     // y = y ^ 15
y <<= 1     // y = y << 1
y >>= 2     // y = y >> 2
```

### Value Coalescing and Optional Chaining

Koral provides two special operators for working with `Option` and `Result` types:

- `or else`: Value coalescing. Returns the right-hand default value when the left side is `None` or `Error`.
- `and then`: Optional chaining / value transformation. Applies the right-hand transformation when the left side is `Some` or `Ok`.

```koral
let opt = [Int]Option.Some(42)
let val = opt or else 0           // 42 (because opt is Some)

let none = [Int]Option.None()
let val2 = none or else 0         // 0 (because none is None)

let mapped = opt and then _ * 2   // Some(84)
```

### Operator Precedence

Operator precedence from high to low:

1. Prefix: `not`, `~`, type cast `(Type)expr`
2. Multiplication/Division: `*`, `/`, `%`
3. Addition/Subtraction: `+`, `-`
4. Shift: `<<`, `>>`
5. Relation: `<`, `>`, `<=`, `>=`
6. Equality: `==`, `<>`
7. Bitwise AND: `&`
8. Bitwise XOR: `^`
9. Bitwise OR: `|`
10. Range: `..`, `..<`, `<..`, `<..<`, `...`, `<...`, `...<`, `....`
11. Logical AND: `and`
12. Optional chaining: `and then`
13. Logical OR: `or`
14. Value coalescing: `or else`

## Selection Structure

Selection structures are used to judge given conditions and control the flow of the program.

In Koral, selection structures use `if` syntax. `if` is followed by a judgment condition. When the condition is `true`, the `then` branch is executed. When the condition is `false`, the `else` branch is executed.

```koral
let main() = if 1 == 1 then print_line("yes") else print_line("no")
```

`if` is also an expression. The `then` and `else` branches must be followed by expressions.

```koral
let main() = print_line(if 1 == 1 then "yes" else "no")
```

Since `if` itself is also an expression, `else` can naturally be followed by another `if` expression for chained conditions.

```koral
let x = 0
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less"
```

When we don't need to handle the `else` branch, we can omit it, in which case its value is `Void`.

```koral
let main() = if 1 == 1 then print_line("yes")
```

### if is Pattern Matching

`if` also supports `is` pattern matching syntax, allowing you to destructure values in conditions:

```koral
let opt = [Int]Option.Some(42)
if opt is .Some(v) then {
    print_line(v)  // 42
} else {
    print_line("None")
}
```

### let Expression

`let` can also be used as an expression, allowing you to bind a variable before calculating the subsequent expression. The scope of this variable is limited to the expression following `then`.

```koral
// val is only visible in the if expression
let val = get_value() then if val > 0 then {
    // code when val > 0
} else {
    // code when val <= 0
}
```

## Loop Structure

### while Expression

In Koral, loop structures use `while` syntax. `while` is followed by a judgment condition. When the condition is `true`, the following expression is executed, then it returns to the condition for the next iteration. `while` is also an expression.

```koral
let mut i = 0
while i < 10 then {
    print_line(i)
    i += 1
}
```

#### while is Pattern Matching

`while` also supports `is` pattern matching, commonly used for iterator loops:

```koral
let mut iter = list.iterator()
while iter.next() is .Some(v) then {
    print_line(v)
}
```

### break and continue

- `break`: Exit the loop.
- `continue`: Skip the current iteration.

```koral
let mut i = 0
while true then {
    if i > 20 then break
    if i % 2 == 0 then { i += 1; continue }
    print_line(i)
    i += 1
}
```

### for Loop

The `for` loop is used to traverse any object that implements the iterator interface (such as lists, maps, sets, ranges, etc.).

In each iteration, the next value produced by the iterator will try to match `pattern`. If the match is successful, the expression following `then` is executed.

```koral
// Traverse a list
let mut list = [Int]List.new()
list.push(10)
list.push(20)
list.push(30)

for x = list then {
    print_line(x)
}

// Traverse a Map
let mut map = [String, Int]Map.new()
map.insert("a", 1)
map.insert("b", 2)

for entry = map then {
    print(entry.key)
    print(" -> ")
    print_line(entry.value)
}

// Traverse a Set
let mut set = [Int]Set.new()
set.insert(100)
set.insert(200)

for v = set then {
    print_line(v)
}
```

### defer Statement

The `defer` statement declares a cleanup expression to be executed when the current block scope exits. The deferred expression runs regardless of whether the scope exits normally or early via `return`, `break`, or `continue`.

When execution takes a `Never` termination path (for example `panic()`, `abort()`, or `exit()`) and the program terminates immediately, execution of in-scope `defer` is not guaranteed.

`defer` is followed by an expression whose return value is discarded.

```koral
let main() = {
    print_line("start")
    defer print_line("cleanup")
    print_line("work")
    // Output: start, work, cleanup
}
```

Multiple `defer` statements in the same scope execute in reverse declaration order (LIFO):

```koral
let main() = {
    defer print_line("first")
    defer print_line("second")
    defer print_line("third")
    // Output: third, second, first
}
```

`defer` binds to the block scope where it is declared, not the function scope. In loops, `defer` executes at the end of each iteration:

```koral
let mut i = 0
while i < 3 then {
    i += 1
    defer print_line("cleanup")
    print_line(i)
    // Each iteration outputs: value of i, cleanup
}
```

The deferred expression can also be a block expression:

```koral
defer {
    print_line("cleaning up")
    close(handle)
}
```

#### Restrictions

- `return`, `break`, and `continue` are not allowed inside a `defer` expression.
- Nested `defer` is not allowed inside a `defer` expression.
- `defer` is not an exception-style stack unwinding mechanism; it is not guaranteed on `panic/abort/exit` `Never` termination paths.
- These restrictions do not cross Lambda boundaries — Lambdas have their own independent scope.

## Pattern Matching

Koral has powerful pattern matching capabilities, mainly used through `when` expressions and the `is` operator.

### when Expression

The `when` expression allows you to compare a value against a series of patterns and execute corresponding code based on the matching pattern. It is similar to `switch` statements in other languages, but more powerful. `when` is also an expression and returns the value of the matching branch.

```koral
let x = 5
let result = when x is {
    1 then "one",
    2 then "two",
    _ then "other",
}
```

Supported patterns include:

- Wildcard pattern: `_` (matches any value)
- Literal patterns: `1`, `"abc"`, `true`
- Variable binding patterns: `x` (matches any value and binds to x), `mut x` (mutable binding)
- Comparison patterns: `> 5`, `< 0`, `>= 10`, `<= -1`
- Struct destructuring patterns: `Point(x, y)`, `Rect(Point(a, b), w, h)`
- Union case patterns: `.Some(v)`, `.None`
- Logical patterns: `pattern and pattern`, `pattern or pattern`, `not pattern`

```koral
// Union type matching
type Shape {
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
}

let area = when shape is {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
}

// Comparison patterns
let grade = when score is {
    >= 90 then "A",
    >= 80 then "B",
    >= 70 then "C",
    _ then "F",
}

// Logical patterns
when x is {
    1 or 2 or 3 then print_line("small"),
    _ then print_line("big"),
}

// Struct destructuring patterns
type Point(x Int, y Int)
type Rect(origin Point, width Int, height Int)

let p = Point(10, 20)
when p is {
    Point(x, y) then print_line(x + y),  // 30
}

// Nested struct destructuring
let r = Rect(Point(1, 2), 30, 40)
when r is {
    Rect(Point(a, b), w, h) then print_line(a + b + w + h),  // 73
}

// Struct destructuring in if...is
if p is Point(x, y) then {
    print_line(x * y)  // 200
}

// Wildcard and literal field matching
when p is {
    Point(0, y) then print_line(y),       // Match when first field is 0
    Point(_, y) then print_line(y),       // Ignore first field
}

// Generic struct destructuring
type [T Any]Box(val T)
let b = [Int]Box(42)
when b is {
    Box(v) then print_line(v),  // 42
}
```

### is Operator

The `is` operator is used to check if a value matches a pattern, and the result is of `Bool` type.

When used in conditional expressions such as `if` or `while`, if the match is successful, it can also bind variables in the pattern to the current scope.

```koral
let opt = [Int]Option.Some(42)
if opt is .Some(v) then {
    print_line(v)  // 42
}

// Comparison pattern
if score is >= 60 then {
    print_line("passed")
}
```

## Functions

Functions are independent blocks of code used to complete specific tasks.

### Definition

Functions are defined using the `let` keyword. The function name is followed by `()` indicating the parameters, and the return type follows the parentheses. The return type can be omitted when the context is clear.

The right side of `=` must declare an expression, and the value of this expression is the return value of the function.

```koral
let f1() Int = 1
let f2(a Int) Int = a + 1
let f3(a Int) = a + 1     // Return type inferred
```

### Calling

Use `()` syntax to call functions:

```koral
let a = f1()
let b = f2(1)
```

### Parameters

Parameters are data that the function can receive during execution. Use `ParameterName Type` to declare parameters.

```koral
let add(x Int, y Int) = x + y
let a = add(1, 2) // a == 3
```

Mutable parameters use the `mut` keyword:

```koral
let increment(mut x Int) = { x += 1; x }
```

### Function Types

In Koral, functions are also a type. Function types are declared using `[T1, T2, ..., R]Func` syntax, where `T1, T2, ...` are parameter types and `R` is the return type.

```koral
let sqrt(x Int) = x * x          // [Int, Int]Func
let f [Int, Int]Func = sqrt
let a = f(2)                      // a == 4
```

We can also define function type parameters or return values:

```koral
let hello() = print_line("Hello, world!")
let run(f [Void]Func) = f()
let toRun() = run

let main() = toRun()(hello)
```

### Lambda Expressions

Lambda expressions are very similar to function definitions, except that `=` is replaced by `->`, and there is no function name or `let` keyword.

```koral
let f1(x Int) Int = x + 1            // [Int, Int]Func
let f2 = (x Int) Int -> x + 1        // [Int, Int]Func
let a = f1(1) + f2(1)                // a == 4
```

When the type of lambda can be inferred from context, parameter types and return type can be omitted:

```koral
let f [Int, Int]Func = (x) -> x + 1
```

Lambda supports multiple forms:

```koral
() -> 42                           // No parameters
(x) -> x * 2                      // Single param, type inferred
(x Int) -> x * 2                  // Single param with type
(x, y) -> x + y                   // Multiple params, types inferred
(x Int, y Int) Int -> x + y       // Full type annotations
(x) -> { let y = x * 2; y + 1 }  // Block body
```

### Closures

Lambda expressions can capture variables from their surrounding scope. This is called a closure.

```koral
let make_adder(base Int) [Int, Int]Func = {
    (x) -> base + x
}

let add10 = make_adder(10)
let result = add10(32)  // result == 42
```

#### Capture Rules

Koral only allows capturing **immutable** variables. Attempting to capture a mutable variable will result in a compile error.

```koral
let x = 10
let f = () -> x + 1  // OK: x is immutable

let mut y = 20
let g = () -> y + 1  // Error: cannot capture mutable variable 'y'
```

#### Currying

Closures enable currying:

```koral
let add [Int, [Int, Int]Func]Func = (x) -> (y) -> x + y

let add10 = add(10)
let result = add10(32)  // result == 42
let sum = add(20)(22)   // sum == 42
```

## Data Types

Data types are data collections composed of a series of data with the same type or different types. It is a composite data type.

Koral provides a powerful type system that allows you to define your own data structures. Use the `type` keyword to define.

### Struct (Product Type)

Structs are used to combine multiple related values together. Each field has a name and a type.

#### Definition

```koral
type Empty()
type Point(x Int, y Int)
```

#### Construction

Use `()` syntax to call the constructor:

```koral
let a Point = Point(0, 0)
```

#### Using Member Variables

Use `.` syntax to access member variables:

```koral
type Point(x Int, y Int)

let main() = {
    let a = Point(64, 128)
    print_line(a.x)  // 64
    print_line(a.y)  // 128
}
```

#### Mutable Member Variables

Member variables are read-only by default. Use the `mut` keyword to mark mutable member variables:

```koral
type Point(mut x Int, mut y Int)

let main() = {
    let a = Point(64, 128)
    a.x = 2  // ok, because x is mut
    a.y = 0  // ok, because y is mut
}
```

The mutability of member variables follows the type definition, not the instance variable.

### Union (Sum Type)

Unions allow you to define a type that can be one of several different variants. Each variant can carry different types of data.

```koral
type Shape {
    Circle(radius Float64),
    Rectangle(width Float64, height Float64),
}

let s = Shape.Circle(1.0)
```

#### Using Union Values

Extract data from union variants through pattern matching:

```koral
let area = when s is {
    .Circle(r) then 3.14 * r * r,
    .Rectangle(w, h) then w * h,
}
```

#### Implicit Member Expressions

When the expected type is known from context (e.g., variable declaration with type annotation, function parameter with type signature), you can omit the type name and use `.memberName` syntax to construct union values or call static methods:

```koral
// Union construction — omit the [Int]Option prefix
let a [Int]Option = .Some(42)
let b [Int]Option = .None()

// In function arguments
let process(opt [Int]Option) Void = when opt is {
    .Some(v) then print_line(v.to_string()),
    .None then print_line("none"),
}
process(.Some(10))

// In assignments
let mut x [Int]Option = .None()
x = .Some(100)

// In conditional expression branches
let c [Int]Option = if true then .Some(1) else .None()

// Static method calls — omit the [Int]List prefix
let list [Int]List = .new()
let list2 [Int]List = .with_capacity(10)
```

> Implicit member expressions require the compiler to infer the expected type from context. If there is no type annotation, the compiler will report an error.

### Type Alias

Type aliases allow you to define a new name for an existing type, improving code readability. Use the `type AliasName = TargetType` syntax.

```koral
type Meters = Int
type Coord = Point
type IntList = [Int]List
```

Type aliases are fully eliminated at compile time — an alias is completely equivalent to its target type:

```koral
type Meters = Int

let distance Meters = 100
let add_meters(a Meters, b Meters) Meters = a + b
let result = add_meters(distance, 50)  // result == 150
```

Aliases can be chained:

```koral
type Meters = Int
type Distance = Meters  // Distance ultimately resolves to Int
```

Type aliases support access modifiers:

```koral
public type Meters = Int       // Public
private type InternalId = Int  // File-scoped only
```

Restrictions:
- Type aliases do not support generic parameters (e.g., `type [T]Alias = [T]List` is invalid), but the target type can be a generic instantiation (e.g., `type IntList = [Int]List`).
- Circular references are not allowed (e.g., `type A = A`).

## Trait and Given

Koral uses Traits to define shared behavior. This is similar to interfaces or type classes in other languages.

### Defining Trait

A Trait defines a set of method signatures that any implementing type must provide.

```koral
trait Printable {
    to_string(self) String
}
```

Traits support inheritance using parent Trait names:

```koral
trait Ord Eq {
    compare(self, other Self) Int
}
```

Multiple parent Traits are connected with `and`:

```koral
trait MyTrait Eq and Hashable {
    my_method(self) Int
}
```

### Implementing Trait (Given)

Use the `given` keyword to implement a Trait for a specific type:

```koral
given Point {
    equals(self, other Point) Bool = self.x == other.x and self.y == other.y
    compare(self, other Point) Int = self.x - other.x
}
```

### Extension Methods

The `given` block can also be used to directly add methods to types:

```koral
given Point {
    public distance(self) Float64 = {
        let dx = (Float64)self.x
        let dy = (Float64)self.y
        // ...
    }
    
    // Methods without self are called via type name
    public origin() Point = Point(0, 0)
}

let p = Point.origin()
```

### Standard Library Core Traits

Koral's standard library defines the following core Traits:

| Trait | Description | Methods |
|-------|-------------|---------|
| `Eq` | Equality comparison | `equals(self, other Self) Bool` |
| `Ord` | Ordering (extends Eq) | `compare(self, other Self) Int` |
| `Hashable` | Hashing (extends Eq) | `hash(self) UInt` |
| `ToString` | String conversion | `to_string(self) String` |
| `[T]Iterator` | Iterator | `next(self ref) [T]Option` |
| `[T, R]Iterable` | Iterable | `iterator(self) R` |
| `Add` | Addition | `add(self, other Self) Self`, `zero() Self` |
| `Sub` | Subtraction (extends Add) | `sub(self, other Self) Self`, `neg(self) Self` |
| `Mul` | Multiplication | `mul(self, other Self) Self`, `one() Self` |
| `Div` | Division (extends Mul) | `div(self, other Self) Self` |
| `Rem` | Remainder (extends Div) | `rem(self, other Self) Self` |
| `[K, V]Index` | Subscript read | `at(self, key K) V` |
| `[K, V]MutIndex` | Subscript write (extends Index) | `set_at(self ref, key K, value V) Void` |
| `Error` | Error interface | `message(self) String` |
| `Deref` | Dereference control (built-in) | *(prevents deref of trait objects)* |

Arithmetic operators are automatically lowered to corresponding Trait method calls:
- `+` → `Add.add`
- `-` → `Sub.sub`
- `*` → `Mul.mul`
- `/` → `Div.div`
- `%` → `Rem.rem`
- `a[k]` → `Index.at`
- `a[k] = v` → `MutIndex.set_at`

### Trait Objects

Trait objects are Koral's mechanism for runtime polymorphism (dynamic dispatch). Using the `TraitName ref` syntax, you can erase any type that implements a Trait into a uniform reference type.

#### Basic Syntax

Use the `ref` keyword to convert a concrete type into a trait object:

```koral
trait Drawable {
    draw(self) String
}

type Circle(radius Int)
type Square(side Int)

given Circle { public draw(self) String = "Drawing circle" }
given Square { public draw(self) String = "Drawing square" }

// Create a trait object
let shape Drawable ref = ref Circle(10)

// Call methods through the trait object (dynamic dispatch)
shape.draw()  // "Drawing circle"
```

#### Object Safety

Only Traits that satisfy the following conditions can be used as trait objects:

- Methods must not have generic parameters
- `Self` must not appear in method parameters or return types (except as the receiver `self`)

```koral
// Object-safe — can be used as a trait object
trait Error {
    message(self) String
}

// Not object-safe — cannot be used as a trait object
trait Eq {
    equals(self, other Self) Bool  // Self appears in parameters
}
```

#### Error Trait and Result

The standard library defines the `Error` trait. Any type that implements `message(self) String` can be used as an error type:

```koral
trait Error {
    message(self) String
}

// String implements the Error trait by default
given String {
    public message(self) String = self
}
```

`Result` uses `Error ref` (a trait object) as its error side, requiring only one generic parameter:

```koral
type [T Any] Result {
    Ok(value T),
    Error(error Error ref),
}

// Use a string as an error
let result = [Int]Result.Error(ref "something went wrong")

// Read the error message
when result is {
    .Ok(v) then print_line(v.to_string()),
    .Error(e) then print_line(e.message()),
}

// Convenience method
result.error_message()  // "something went wrong"
```

#### Deref Trait

`Deref` is a built-in trait that controls dereference behavior. Trait objects (`TraitName ref`) do not implement `Deref`, so they cannot be dereferenced. This ensures trait objects are always used through references.

## Generics

Generics allow you to write code that applies to multiple types, improving code reusability.

### Generic Data Types

Generic data types use `[T Constraint]` syntax before the identifier to define generic parameters:

```koral
type [T1 Any, T2 Any]Pair(left T1, right T2)
```

When constructing generic data types, pass actual types in the generic parameter position:

```koral
let a1 = [Int, Int]Pair(1, 2)
let a2 = [Bool, String]Pair(true, "hello")
```

When the context type is clear, generic type parameters can be omitted:

```koral
let a1 = Pair(1, 2)           // Inferred as [Int, Int]Pair
let a2 = Pair(true, "hello")  // Inferred as [Bool, String]Pair
```

### Generic Functions

Generic functions use the same syntax before the function name:

```koral
let [T Any]identity(x T) T = x

print_line(identity(42))       // 42
print_line(identity("hello"))  // hello
```

### Generic Constraints

Generic parameters can specify Trait constraints to limit acceptable types:

```koral
let [T Ord]max_val(a T, b T) T = if a > b then a else b
let [T Eq]contains(list [T]List, value T) Bool = list.contains(value)
```

Multiple constraints are connected with `and`:

```koral
let [T ToString and Hashable]describe(value T) String = value.to_string()
```

### Generic Methods

`given` blocks can also define generic methods:

```koral
given [T Any] [T]Option {
    public [U Any]map(self, f [T, U]Func) [U]Option = self and then f(_)
}
```

## Standard Library Collection Types

### List

`[T]List` is a dynamic array type with generic support.

```koral
// Creation
let mut list = [Int]List.new()
let mut list2 = [Int]List.with_capacity(100)

// Add and remove
list.push(1)
list.push(2)
list.push(3)
list.pop()              // Returns Option.Some(3)
list.insert(0, 0)       // Insert at index 0
list.remove(0)          // Remove element at index 0

// Access
list[0]                  // Subscript access (panics on out of bounds)
list.get(0)              // Safe access, returns Option
list.front()             // First element, returns Option
list.back()              // Last element, returns Option

// Info
list.count()             // Number of elements
list.is_empty()          // Whether empty
list.contains(1)         // Whether contains (requires Eq)

// Transform
list.slice(1..3)         // Slice
list.filter((x) -> x > 1)   // Filter
list.map((x) -> x * 2)      // Map
list.sort()                  // Sort (requires Ord)
list.sort_by((x) -> x)      // Sort by key

// Concatenation
let combined = list + other_list  // List concatenation
```

### Map

`[K, V]Map` is a hash map type. Key type must implement `Hashable`.

```koral
let mut map = [String, Int]Map.new()

// Insert and remove
map.insert("a", 1)      // Returns Option (old value)
map.remove("a")         // Returns Option (removed value)

// Access
map["a"]                 // Subscript access (panics if key not found)
map.get("a")             // Safe access, returns Option

// Info
map.count()
map.is_empty()
map.contains_key("a")

// Iteration
for entry = map then {
    print_line(entry.key)
    print_line(entry.value)
}

// Keys and values
for k = map.keys() then { print_line(k) }
for v = map.values() then { print_line(v) }
```

### Set

`[T]Set` is a hash set type. Element type must implement `Hashable`.

```koral
let mut set = [Int]Set.new()

// Add and remove
set.insert(1)            // Returns Bool (whether new)
set.remove(1)            // Returns Bool (whether existed)

// Info
set.count()
set.is_empty()
set.contains(1)

// Set operations
let union = set1.union(set2)
let inter = set1.intersection(set2)
let diff = set1.difference(set2)
```

### Option

`[T]Option` is an optional type representing a value that may or may not exist.

```koral
type [T Any] Option {
    None(),
    Some(value T),
}

let opt = [Int]Option.Some(42)
let none = [Int]Option.None()

opt.is_some()            // true
opt.is_none()            // false
opt.unwrap()             // 42 (panics on None)
opt.unwrap_or(0)         // 42 (returns default on None)
opt.map((x) -> x * 2)   // Some(84)

// or else and and then
let val = opt or else 0
let mapped = opt and then _ * 2
```

### Result

`[T]Result` is a result type representing an operation that may succeed or fail. The error side is fixed to `Error ref` (a trait object).

```koral
type [T Any] Result {
    Ok(value T),
    Error(error Error ref),
}

let ok = [Int]Result.Ok(42)
let err = [Int]Result.Error(ref "failed")

ok.is_ok()               // true
ok.is_error()            // false
ok.unwrap()              // 42 (panics on Error)
ok.unwrap_or(0)          // 42 (returns default on Error)
ok.map((x) -> x * 2)    // Ok(84)
err.error_message()      // "failed"
```

## Module System

Koral provides a powerful module system for organizing code across multiple files and directories.

### Module Concepts

A **module** in Koral consists of an entry file and all files it depends on through `using` declarations.

- **Root Module**: The module formed by the compilation entry file and its dependencies
- **Submodule**: A module in a subdirectory, with `index.koral` as its entry file
- **External Module**: Modules from outside the current compilation unit (e.g., standard library)

### Using Declarations

The `using` keyword is used to import modules and symbols. All `using` declarations must appear at the beginning of a file, before any other declarations.

#### File Merging

Use string literal syntax to merge files from the same directory into the current module:

```koral
using "utils"      // Merges utils.koral into current module
using "helpers"    // Merges helpers.koral into current module
```

Merged files share the same scope — their `public` and `protected` symbols are mutually visible.

#### Submodule Import

Use `self.` prefix to import submodules from subdirectories:

```koral
using self.models              // Import models/ subdirectory as submodule (private)
protected using self.models    // Import and share within current module
public using self.models       // Import and expose to external modules
```

Access submodule members using dot notation:

```koral
using self.models
let user = models.User("Alice")
```

You can also import specific symbols or batch import:

```koral
using self.models.User         // Import specific symbol
using self.models.*            // Batch import all public symbols
```

#### Parent Module Access

Use `super.` prefix to access parent modules within the same compilation unit:

```koral
using super.sibling            // Import from parent module
using super.super.uncle        // Import from grandparent module
```

#### External Module Import

Import external modules without any prefix:

```koral
using std                      // Import std module
using std.collections          // Import collections from std
using txt = std.text           // Import with alias
```

#### Foreign Using

Use `foreign using` to declare external shared libraries (`.so` / `.dylib` / `.dll`) to link against. The compiler automatically adds `-l` flags during the linking phase:

```koral
foreign using "m"       // Link libm (math library), equivalent to -lm
foreign using "pthread"  // Link libpthread
```

> Note: `foreign using` does not import header files. It tells the linker which library to link. C function declarations are done via `foreign let`.

### Access Modifiers

Koral provides three access levels to control symbol visibility:

| Modifier | Visibility |
|----------|------------|
| `public` | Accessible from anywhere |
| `protected` | Accessible within current module and all submodules |
| `private` | Accessible only within the same file |

#### Default Access Levels

| Declaration | Default |
|-------------|---------|
| Global functions, variables, types | `protected` |
| Struct fields | `protected` |
| Union constructor fields | `public` |
| Member functions (in `given` blocks) | `protected` |
| Trait methods | `public` |
| Using declarations | `private` |

### Project Structure Example

```
my_project/
├── main.koral           # Root module entry
├── utils.koral          # Merged into root module
├── models/
│   ├── index.koral      # models submodule entry
│   ├── user.koral       # Merged into models module
│   └── post.koral       # Merged into models module
└── services/
    ├── index.koral      # services submodule entry
    └── auth.koral       # Merged into services module
```

```koral
// main.koral
using std
using "utils"
using self.models
using self.services

public let main() = {
    let user = models.User.new("Alice")
    if services.authenticate(user) then {
        print_line("Welcome!")
    }
}
```

## FFI (Foreign Function Interface)

Koral supports interoperability with C through the `foreign` keyword.

### Foreign Using (Linking External Libraries)

Use `foreign using` to declare shared libraries to link against:

```koral
foreign using "m"  // Link libm (math library)
```

The compiler automatically adds `-lm` during the linking phase. `libc` is implicitly linked by default and does not need to be declared.

### Foreign Functions

Declare external C functions:

```koral
foreign using "m"

foreign let sin(x Float64) Float64
foreign let exit(code Int) Never
foreign let abort() Never
```

### Foreign Types

Declare external C types:

```koral
// Opaque type (no fields)
foreign type CFile

// FFI struct with fields (aligned with C layout)
foreign type KoralTimespec(tv_sec Int64, tv_nsec Int64)
```

### Intrinsic

The `intrinsic` keyword declares types and functions built into the compiler:

```koral
public intrinsic type Int
public intrinsic let [T Any]ref_count(r T ref) Int
```

## Standard Library API Reference

### IO Functions

```koral
// Output (auto-flush)
print(value)              // Print to stdout (no newline)
print_line(value)         // Print to stdout (with newline)
print_error(value)        // Print to stderr (no newline)
print_error_line(value)   // Print to stderr (with newline)

// Input
read_line()               // Read a line from stdin, returns [String]Option

// Assertion and panic
panic(message)            // Terminate program with error message
assert(condition, message) // Panic when condition is false
```

All print functions accept any type that implements the `ToString` trait.

### OS Module

```koral
// File operations
read_file(path)           // [String]Result
write_file(path, content) // [Void]Result
append_file(path, content) // [Void]Result
copy_file(src, dst)       // [Void]Result
remove_file(path)         // [Void]Result

// Directory operations
create_dir(path)          // [Void]Result
create_dir_all(path)      // [Void]Result (recursive)
remove_dir(path)          // [Void]Result
remove_dir_all(path)      // [Void]Result (recursive)
read_dir(path)            // [[String]List]Result

// Path operations
path_exists(path)         // Bool
is_file(path)             // Bool
is_dir(path)              // Bool
join_path(base, name)     // String
base_name(path)           // [String]Option
dir_name(path)            // [String]Option
ext_name(path)            // [String]Option
is_absolute(path)         // Bool
normalize_path(path)      // String
absolute_path(path)       // [String]Result
current_dir()             // [String]Result

// Environment variables
get_env(name)             // [String]Option
set_env(name, value)      // Void
home_dir()                // [String]Option
temp_dir()                // String

// Process
run_command(program, args) // [CommandResult]Result
args()                    // [String]List
exit(code)                // Never
abort()                   // Never
```

### Time Module

```koral
// Duration type
Duration.from_nanos(n)    // Create from nanoseconds
Duration.from_micros(n)   // Create from microseconds
Duration.from_millis(n)   // Create from milliseconds
Duration.from_secs(n)     // Create from seconds
Duration.from_mins(n)     // Create from minutes
Duration.from_hours(n)    // Create from hours

d.as_nanos()              // Convert to nanoseconds
d.as_millis()             // Convert to milliseconds
d.as_seconds()            // Convert to seconds

// Sleep
sleep(duration)           // Sleep for specified duration
```

### Rune Type

`Rune` represents a Unicode code point.

```koral
let r = Rune.from_uint32((UInt32)65)  // 'A'
r.to_uint32()             // UInt32 value
r.to_string()             // Convert to UTF-8 string
r.is_ascii()              // Whether ASCII
r.is_ascii_digit()        // Whether ASCII digit
r.is_ascii_letter()       // Whether ASCII letter
r.is_letter()             // Whether Unicode letter
r.is_whitespace()         // Whether whitespace
r.byte_count()            // UTF-8 encoding byte count
```

Strings can iterate over Unicode code points via the `runes()` method:

```koral
for r = "Hello".runes() then {
    print_line(r.to_string())
}
```

For scenarios requiring frequent random access to Runes, use `to_runes()` to convert to a `[Rune]List` in one pass:

```koral
let runes = "Hello".to_runes()
let len = runes.count()    // O(1)
let third = runes[2]       // O(1) random access
```

### Stream API

Stream provides lazy, chainable iterator operations.

```koral
// Create a Stream from any iterable
let s = stream(list)

// Intermediate operations (lazy)
s.filter((x) -> x > 0)       // Filter
s.map((x) -> x * 2)          // Map
s.filter_map((x) -> ...)     // Filter and map
s.take(5)                     // Take first n
s.skip(3)                     // Skip first n
s.step_by(2)                  // Take every nth
s.enumerate()                 // Attach index
s.peek((x) -> print_line(x)) // Peek (side effect)
s.take_while((x) -> x < 10)  // Take while condition
s.skip_while((x) -> x < 5)   // Skip while condition
s.chain(other_stream)         // Chain
s.zip(other_stream)           // Zip
s.flat_map((x) -> ...)       // Flat map
s.intersperse(0)              // Intersperse separator

// Terminal operations (trigger computation)
s.fold(0, (acc, x) -> acc + x) // Fold
s.reduce((a, b) -> a + b)      // Reduce
s.to_list()                     // Collect to list
s.for_each((x) -> print_line(x)) // For each
s.count()                       // Count
s.first()                       // First element
s.last()                        // Last element
s.sum()                         // Sum (requires Add)
s.product()                     // Product (requires Mul)
s.average()                     // Average (requires Add)
s.any((x) -> x > 0)            // Any match
s.all((x) -> x > 0)            // All match
s.none((x) -> x > 0)           // None match
s.min()                         // Minimum (requires Ord)
s.max()                         // Maximum (requires Ord)
```

### Pair Type

```koral
let p = [Int, String]Pair(1, "hello")
p.first   // 1
p.second  // "hello"
```

### Utility Functions

```koral
max(a, b)    // Returns the larger value (requires Ord)
min(a, b)    // Returns the smaller value (requires Ord)
```

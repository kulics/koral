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

A statement usually ends with an explicit semicolon, but if the last expression of the statement is immediately followed by a newline, the semicolon can be omitted. This makes structures like `if`, `while`, etc. look cleaner.

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

Now let's make our program output some content. The standard library provides the `printLine` function to print a line of text to the standard output.

```koral
let main() = printLine("Hello, world!");
```

Now try to execute this program, and we can see `Hello, world!` displayed on the console.

### Comments

Comments are parts of the code ignored by the compiler, used to provide explanations to people reading the code.

For example:

```koral
// This is a single-line comment, starting from double slashes to the end of the line

/*
    This is a block comment.
    It can span multiple lines.
    /* Koral supports nested block comments */
*/
```

### Variables

Koral's variables are a kind of binding semantics, equivalent to binding a variable name and a value together, thus establishing an association, similar to a key-value pair. For security reasons, variables are immutable by default, of course we also provide another kind of variable - mutable variables.

#### Read-only Variables

In Koral, read-only variables are declared using the `let` keyword, following the principle of declaration before use.

Koral ensures type safety through static typing. Variable bindings can explicitly annotate types via `type` at declaration. When there is enough information in the context, we can also omit the type, and the compiler will infer the variable's type from the context.

Example code:

```koral
let a Int = 5; // Explicit type annotation
let b = 123;   // Automatic type inference
```

Once a read-only variable is declared, its value cannot be changed within the current scope.

If we try to assign to a read-only variable, the compiler will report an error.

```koral
let a = 5;
a = 6; // Error
```

#### Mutable Variables

If we need a variable that can be reassigned, we can use a mutable variable declaration.

In Koral, mutable variables are declared using the `let mut` keyword, also following the principle of declaration before use.

Example code:

```koral
let mut a Int = 5; // Explicit type annotation
let mut b = 123; // Automatic type inference
```

### Assignment

For mutable variables, we can change their value multiple times when needed.

Koral's assignment statement uses `=` just like most languages. The left side of `=` must be an assignable variable, and the program will assign the value on the right side of `=` to the variable on the left.

Example code:

```koral
let mut a = 0;
a = 1;  // Legal
a = 2;  // Legal
```

### Block Expressions

In Koral, `{}` represents a block expression. A block expression can contain a series of statements and an optional final expression. The result of a block expression is also an expression.

The **value of the last expression** in the block expression is the value of the entire block. If there is no last expression, the value of the block is Void.

Block expressions can combine a series of operations, such as multi-step initialization of a complex value.

```koral
let a Void = {}
let b Int = {
    let c = 7;
    let d = c + 14;
    (c + 3) * 5 + d / 3  // Return value of the block
}
```

### Identifiers

Identifiers are names given to variables, functions, types, etc. The letters constituting identifiers have certain specifications. The naming rules for identifiers in this language are as follows:

1. Case sensitive. Myname and myname are two different identifiers.
1. **Types** (Type) and **Constructors** (Constructor) must start with an **uppercase letter** (e.g., `Int`, `String`, `Point`).
1. **Variables**, **Functions**, **Members** must start with a **lowercase letter** or underscore (e.g., `main`, `printLine`, `x`).
1. Other characters in identifiers can be underscores `_`, letters, or numbers.
1. Within the same `{}`, identifiers with the same name cannot be defined repeatedly.
1. In different `{}`, identifiers with the same name can be defined, and the language will prioritize the identifier defined in the current scope.

## Basic Types

We only need a few simple basic types to carry out most of the work.

### Numeric Types

Since our current computer architecture is good at calculating integers, an independent integer type helps improve program execution efficiency.

Koral provides rich numeric types to meet different needs.
In Koral, the default integer is `Int` type, which can represent signed integer data.
In Koral, the default decimal is `Float` type, which can represent floating-point data.

- `Int`: Platform-dependent signed integer (usually 64-bit).
- `UInt`: Platform-dependent unsigned integer (usually 64-bit).
- `Int8`, `Int16`, `Int32`, `Int64`: Fixed-width signed integers.
- `UInt8`, `UInt16`, `UInt32`, `UInt64`: Fixed-width unsigned integers.
- `Float`: Default floating-point type (64-bit, equivalent to `Float64`).
- `Float32`: 32-bit floating-point number.
- `Float64`: 64-bit floating-point number.
- `Byte`: Equivalent to `UInt8`.

```koral
let i Int = 3987349;
let f Float = 3.14;
let b UInt8 = 255;
```

### Strings

We do not live in a world with only numbers, so we also very much need to use text to display the information we need.

In this language, strings are used to represent text data. `String` type is a character sequence data of unlimited length.

You can use double quotes `""` or single quotes `''` to wrap a piece of text content, and it will be recognized as a string value.

```koral
let s1 String = "Hello, world!";
let s2 String = 'Hello, world!'; // Same as s1
```

Koral supports string interpolation, allowing expressions to be embedded in strings.

```koral
let name = "Koral";
let s1 String = "Hello, \{name}!"; // Interpolation
let s2 String = 'Hello, \{"world"}!'; // Interpolation
```

### Booleans

Booleans refer to logical values, they can only be true or false. It is often used to assist in judgment logic.

In this language, the default boolean is `Bool` type, which is a type with only two possible values `true` and `false`.

```koral
let b1 Bool = true;
let b2 Bool = false;
let isGreater = 5 > 3; // Result is true
```

### List Types

A list is a generic (introduced later) data type that can store a group of data elements of the same type. Each element has an index to represent its position in the list. The length of the list is not fixed; it can dynamically add or remove elements, and can also quickly access elements via index.

We use `[T]List` to represent a list type, where `T` can be any type.

List types can be initialized using list literals (`[elem1, elem2, …]`), where `elem1` and `elem2` represent elements at corresponding positions, separated by (`,`). We can pass any expression, but all elements must be of the same type. 

```koral
let x [Int]List = [1, 2, 3, 4, 5];
```

As shown in the code above, we created an `[Int]List` using array literal syntax, and its elements are `1, 2, 3, 4, 5` as the literal indicates.

In addition to this literal listing elements, we can also use another list literal (`[default; size]`) that creates a specified size and default value to construct. `default` is the default value, and `size` is the number of elements.

```koral
let y [Int]List = [0; 3];
// y == [0, 0, 0]
```

We can use the array's `size` member function (introduced later) to get its number of elements.

```koral
printLine(x.size()); // 5
```

We can use subscript syntax `[index]` to access elements at a specified index. `index` can only be a value of `Int` type. The subscript starts at 0, `[0]` corresponds to the first element, and so on.

```koral
printLine(x[0]); // 1
printLine(x[2]); // 3
printLine(x[4]); // 5
```

Modifying list elements is similar to assigning to member variables (introduced later), except that subscript syntax is required.

```koral
let main() = {
    let x = [1, 2, 3, 4, 5];
    printLine(x[0]); // 1
    x[0] = 5;
    printLine(x[0]); // 5
}
```

As shown in the code above, we declare x as a list, and then we can use `[index] = value` to assign a value to the element at the specified subscript.

### Reference Types (Reference)

Reference types are used to refer to another value rather than holding it. This is useful when sharing data or avoiding copying. Adding the `ref` keyword after the type name declares a reference type.

```koral
// Declare a function that accepts an Int reference as a parameter
let printList(x [Int]List ref) = printLine(x);
```

There are two ways to create reference types.

#### ref Expression

If we need to get a reference to an existing variable, we can use the `ref` keyword. This is typically used to pass variables on the stack by reference to functions, avoiding value copying.

```koral
let a [Int]List = [1,2,3];
printList(ref a); // Pass reference
```

#### new Function

If we need to directly create a value of a reference type, we can use the `new` function. It allocates memory on the heap and returns a reference to that data.

```koral
let a [Int]List ref = new([1,2,3]);
printList(a); // Pass reference
```

#### Memory Management

Koral aims to provide efficient and safe memory management. It combines the advantages of automatic memory management and manual control.

- **Value Semantics**: By default, types in Koral (such as `Int`, `struct`) have value semantics. This means that when assigning or passing parameters, data is copied (unless optimized away by the compiler). This is similar to structs in C.
- **Reference**: Use the `ref` keyword to create references. References allow you to access data without owning it. Koral uses reference counting and ownership analysis to automatically manage the lifecycle of references, preventing dangling pointers and memory leaks.
- **Copy and Drop Trait**:
    - **Copy**: If a type implements the `Copy` trait, its value is always bitwise copied during assignment. Basic types (such as `Int`, `Float`) implement `Copy` by default.
    - **Drop**: If a type implements the `Drop` trait, the compiler automatically calls the `drop` method when the value of that type goes out of scope or is no longer used. This is used to release non-memory resources (such as file handles, network connections).
- **Move Semantics**: For types that do not implement `Copy`, assignment and parameter passing operations result in ownership transfer (Move). Once ownership is transferred, the original variable can no longer be used.

```koral
type File(fd Int) not Copy; // Explicitly marked as not Copy

// Implement Drop trait to automatically close file
given File Drop {
    drop(self ref) = close(self.fd);
}
```

## Operators

Operators are symbols that tell the compiler to perform specific mathematical or logical operations.

We can simply understand them as calculation symbols in mathematics, but programming languages have their differences.

### Arithmetic Operators

Arithmetic operators are mainly used on numeric type data operations, and most declarations conform to mathematical expectations.

Koral supports standard arithmetic operations, including addition, subtraction, multiplication, division, and modulus. In addition, the exponentiation operator `^` is provided.

```koral
let a = 4;
let b = 2;
printLine( a + b );    // + Add
printLine( a - b );    // - Subtract
printLine( a * b );    // * Multiply
printLine( a / b );    // / Divide
printLine( a % b );    // % Modulus, meaning the remainder after division
printLine( a ^ b );    // ^ Power
```

### Comparison Operators

Comparison operators are used to compare the size relationship between two values. The result is of `Bool` type, `true` if it meets expectations, `false` otherwise. Note that not equal is represented by `<>`.

```koral
let a = 4;
let b = 2;
printLine( a == b );     // == Equal
printLine( a <> b );     // <> Not equal 
printLine( a > b );      // > Greater than
printLine( a >= b );     // >= Greater than or equal to
printLine( a < b );      // < Less than
printLine( a <= b );     // <= Less than or equal to
```

### Logical Operators

Logical operators are mainly used to perform logical operations (AND, OR, NOT) on two Bool type operands.

```koral
let a = true;
let b = false;
printLine( a and b );       // AND, true only if both are true
printLine( a or b );        // OR, true if either one is true
printLine( not a );         // NOT, boolean negation
```

Among them, `and` and `or` have short-circuit semantics. Short-circuit logical operations can skip unnecessary calculations to save computing resources or avoid side effects.

When the value of the expression on the left side of the `and` operator is `false`, the calculation of the expression on the right side of the `and` operator will be skipped.

```koral
let a = false and f(); // f() will not be executed
```

When the value of the expression on the left side of the `or` operator is `true`, the calculation of the expression on the right side of the `or` operator will be skipped.

```koral
let a = true or f(); // f() will not be executed
```

### Bitwise Operators

Bitwise operators are mainly used to perform bitwise operations (AND, OR, XOR, NOT, Left Shift, Right Shift) on two integer type operands.

```koral
let a = 4;
let b = 2;
printLine( a bitand b );    // Bitwise AND
printLine( a bitor b );     // Bitwise OR
printLine( a bitxor b );    // Bitwise XOR
printLine( bitnot a );      // Bitwise NOT
printLine( a bitshl b );    // Left shift
printLine( a bitshr b );    // Right shift
```

### Range Operators

Range operators are used to generate a range (Range). We can fill in the required integer type values at both ends of the range operator to represent a range, commonly used in loops or pattern matching.

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

Koral supports common arithmetic compound assignments, and also supports bitwise compound assignments.

```koral
let mut x = 10;
x += 5;       // x = x + 5
x -= 2;       // x = x - 2
x *= 3;       // x = x * 3
x /= 2;       // x = x / 2
x %= 4;       // x = x % 4
x ^= 2;       // x = x ^ 2 (Power)

let mut y = 0b1100;
y bitand= 0b1010; // y = y bitand 0b1010
y bitor=  0b0001; // y = y bitor 0b0001
y bitxor= 0b1111; // y = y bitxor 0b1111
y bitshl= 1;      // y = y bitshl 1
y bitshr= 2;      // y = y bitshr 2
```

### Operator Precedence

Operator precedence from high to low is as follows:

1. Prefix: `not`, `bitnot`, `+`(unary), `-`(unary)
2. Power: `^` (Right associative)
3. Multiplication/Division: `*`, `/`, `%`
4. Addition/Subtraction: `+`, `-`
5. Shift: `bitshl`, `bitshr`
6. Relation: `<`, `>`, `<=`, `>=`
7. Equality: `==`, `<>`
8. Bitwise AND: `bitand`
9. Bitwise XOR: `bitxor`
10. Bitwise OR: `bitor`
11. Pattern Check: `is`
12. Logical AND: `and`
13. Logical OR: `or`

## Selection Structure

Selection structures are used to judge given conditions, and control the flow of the program based on the results of the judgment.

In Koral, selection structures are represented using `if` syntax. `if` is followed by a judgment condition. When the condition is `true`, the `then` branch following the condition is executed. When the condition is `false`, the `else` branch following the `else` keyword is executed.

For example:

```koral
let main() = if 1 == 1 then printLine("yes") else printLine("no");
```

Executing the above program will show `yes`.

`if` is also an expression. The `then` and `else` branches must be followed by expressions. Depending on the `if` condition, the value of the `if` expression may be one of the `then` or `else` branches.

Therefore, we can also write the above program like this, the two ways are equivalent.

```koral
let main() = printLine(if 1 == 1 then "yes" else "no");
```

Since `if` itself is also an expression, `else` can naturally be followed by another `if` expression, so we can implement continuous condition judgment.

```koral
let x = 0;
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less";
```

When we don't need to handle the `else` branch, we can omit the `else` branch, in which case its value is `Void`.

```koral
let main() = if 1 == 1 then printLine("yes");
```

### let Expression

`let` can also be used as an expression, allowing you to bind a variable before calculating the subsequent expression. The scope of this variable is limited to the expression following `then`. This is often used to introduce temporary variables before `if` or `while`.

Without using `let` expression, we might write like this to achieve the effect of narrowing the scope:

```koral
{
    let val = getValue();
    if val > 0 then {
        // some codes if is true
    } else {
        // some codes if is false
    }
}
```

It can be seen that val belongs to a separate block expression, so val will not be exposed to the scope outside `if`.

Using `let` expression, we can write like this:

```koral
// val is only visible in the if expression
let val = getValue() then if val > 0 then {
    // some codes if is true
} else {
    // some codes if is false
}
```

In this way, val is only visible in `if` and `else`, and will not leak into other scopes.

## Loop Structure

Loop structure refers to a program structure set up to repeatedly execute a certain function in the program. It judges whether to continue executing a certain function or exit the loop based on the conditions in the loop body.

### while Expression

In Koral, loop structures are represented using `while` syntax. `while` is followed by a judgment condition. When the condition is `true`, the following expression is executed, and then it returns to the judgment condition to judge and enter the next round of loop. When the condition is `false`, the loop ends. `while` is also an expression.

```koral
let mut i = 0;
while i < 10 then {
    printLine(i);
    i += 1;
}
```

Executing the above program will print 0 to 10.

### break and continue

- `break`: Exit the loop.
- `continue`: Skip the current iteration.

When we need to actively exit the loop inside the loop, we can use the break statement. The program will exit the current nearest loop when it executes break.

```koral
let main() = {
    let mut i = 0;
    while true then {
        if i > 20 then break;
        printLine(i);
        i = i + 1;
    }
}
```

Executing the above program will print 0 to 20.

If we need to skip certain rounds in the loop, we can use the continue statement. The program will skip the current round of loop when it executes continue, and continue to execute the next loop.

```koral
let main() = {
    let mut i = 0;
    while i <= 10 then {
        if i % 2 == 0 then continue;
        printLine(i);
        i = i + 1;
    }
}
```

Executing the above program will print odd numbers between 0 and 10.

### for Loop

The `for` loop is used to traverse any object that implements the iterator interface (such as lists, arrays, ranges, etc.).

In each iteration, the next value produced by the iterator will try to match `pattern`. If the match is successful, the expression following `then` is executed.

```koral
// Traverse range
for i = 0..10 then {
    printLine(i);
}
```

Executing the above program will print 0 to 10.

```koral
let list = [1,2,3,4,5];

// Traverse list
for item = list then {
    printLine(item);
}

// Use with destructuring
for (index, value) = list.enumerate() then {
    printLine("Index: \{index}, Value: \{value}");
}
```

Executing the above program will first output 1 to 5, and then output 1 to 5 with index.

## Pattern Matching

Koral has powerful pattern matching capabilities, mainly used through `when` expressions and `is` operators.

### when expression

The `when` expression allows you to compare a value against a series of patterns and execute corresponding code based on the matching pattern. It is similar to `switch` statements in other languages, but more powerful. `when` is also an expression and returns the value of the matching branch.

```koral
when x is {
    1 then "one";
    2 then "two";
    _ then "other";
}
```

Supported patterns include:

- Literal patterns: `1`, `"abc"`, `true`
- Range patterns: `0..9`
- Variable binding patterns: `x` (matches any value and binds to x)
- Destructuring patterns: `Point(x, y)`
- Enum patterns: `.Some(v)`
- Type check patterns: `x Int`

### is Operator

The `is` operator is used to check if a value matches a pattern, and the result is of `Bool` type.

When used in conditional expressions such as `if`, if the match is successful, it can also bind variables in the pattern to the current scope for subsequent code use.

```koral
if op is 0..9 then {
    printLine(v);
}
```

## Functions

Functions are independent blocks of code used to complete specific tasks.

Usually we encapsulate a series of tasks that need to be reused into functions to facilitate reuse in other places.

### Definition

We have seen the entry function before, which uses the fixed name main to define.

When we need to define other functions, we can use the same syntax to define functions with other names.

Functions are defined using the `let` keyword. The name of the function is followed by `()` indicating the parameters accepted by this function, and the return type follows the parentheses. The return type can be omitted when the context is clear, and the compiler infers the return type.

The right side of `=` of the function must declare an expression, and the value of this expression is the return value of the function.

```koral
let f1() Int = 1;
let f2(a Int) Int = a + 1;
let f3(a Int) = a + 1;
```

### Call

So how to use these defined functions? We only need to use `()` syntax after the function expression to call the function, thereby obtaining the return value of the function.

`()` must pass parameters of corresponding types according to the requirements of the function definition.

```koral
let a = f1();
let b = f2(1);
```

### Parameters

Parameters are data that the function can receive during execution. Through these different parameters, we can let the function output different return values.

For example, we can implement a square function that returns the square of the parameter each time it is called.

Very simply, we only need to use `ParameterName Type` to declare parameters.

```koral
let sqrt(x Int) = x * x;
let a = sqrt(x); // a == 4
```

sqrt receives an Int type parameter x, and then returns its square value. When calling sqrt, we need to give the corresponding Int type expression to complete the call.

If we need multiple parameters, we can declare them one by one in order, separated by `,`. The call also needs to give expressions in the same order.

```koral
let add(x Int, y Int) = x + y;
let a = add(1, 2); // a == 3
```

### Function Types

In Koral, functions, like Int, Float and other types, are also a type. Similarly, functions can also be used as expressions.

Function types are declared using `[T1, T2, T3,... R]Func` syntax. Like function definitions, parameters and return types need to be declared. Among them, `T1, T2, T3, ...` part is the parameter type sequence. When there are no parameters, it is empty, otherwise it is arranged in order until all parameter types are listed. R is the return type.

After the function is defined, the function name can be used as an expression, assigned to other variables, or used as parameters and return values.

Variables of function types are called using `()` syntax just like functions.

```koral
let sqrt(x Int) = x * x; // [Int, Int]Func
let f [Int, Int]Func = sqrt;
let a = f(2); // a == 4
```

Using this feature, we can also define parameters or return values of function types.

```koral
let hello() = printLine("Hello, world!");
let run(f [Void]Func) = f();
let toRun() = run;

let main() = toRun()(hello);
```

Executing the above code, we will see `Hello, world!`.

### Lambda Expressions

Defining a function first and then passing it in like the above way sometimes seems verbose, because we just want to execute a small piece of function, and may not want to define a function for other places to use.

At this time, we can use the syntax of Lambda expressions to simplify our code.

Lambda expressions are very similar to function definitions, except that `=` is replaced by `->`, and there is no function name and let keyword.

As shown in the code below, the value of f2 is a lambda. Their type is the same as f1, and the syntax is also very similar. Lambda also needs to declare parameters and return types, and needs an expression as a return value.

```koral
let f1(x Int) Int = x + 1; // [Int, Int]Func
let f2 = (x Int) Int -> x + 1; // [Int, Int]Func
let a = f1(1) + f2(1); // a == 4
```

When the type of lambda can be known in our context, we can omit its parameter types and return type.

```koral
let f [Int, Int]Func = (x) -> x + 1;
```

## Data Types

Data types are data collections composed of a series of data with the same type or different types. It is a composite data type.

Obviously, data types are suitable for packaging different data together to form a new type, facilitating the operation of complex data.

Koral provides a powerful type system that allows you to define your own data structures. Use the `type` keyword to define.

### Struct (Product Type)

Structs are used to combine multiple related values together. Each field has a name and a type.

#### Definition

We can use the `type` keyword to declare a new data type. The data type needs to use `()` to declare the member variables it owns, similar to function parameters.

```koral
type Empty();
```

Above we declared a new data type named Empty, which contains no data.

Next, let's define some more meaningful data types.

```koral
type Point(x Int, y Int);
```

Point is a data type with two member variables x and y. It can be used to represent a point in a two-dimensional coordinate system. In this way, we can use the Point type to represent our data in the coordinate system, instead of always using two independent Int data.

#### Construction

So how do we construct a new Point data?

Similar to function types, we also use `()` syntax to call our constructor to get the data we need.

```koral
let a Point = Point(0, 0);
```

#### Using Member Variables

Now that we have a Point data, how do we use the x and y inside?

Very simple, we only need to use `.` syntax to access them.

```koral
type Point(x Int, y Int);

let main() = {
    let a = Point(64, 128);
    printLine(a.x);
    printLine(a.y);
}
```

Executing the above program, we can see 64 and 128.

#### Mutable Member Variables

Member variables, like variables, are read-only by default. So we cannot reassign x and y in Point. If we try to do this, the compiler will report an error.

```koral
type Point(x Int, y Int);

let main() = {
    let a = Point(64, 28);
    a.x = 2; // Error
}
```

We can annotate the mut keyword on member variables when defining the type, so that it will be defined as a mutable member variable. For mutable member variables, we can assign values to them.

The mutability of member variables follows the type and has nothing to do with whether the instance variable is mutable, so we can modify mutable member variables even if we declare read-only variables.

```koral
type Point(mut x Int, mut y Int);

let main() = {
    let a Point = Point(64, 128); // `a` does not need to be declared as mut
    a.x = 2; // ok
    a.y = 0; // ok
}
```

When we assign a variable of a type to another variable for use, the two variables are not the same instance, so our modification of member variables will not affect other variables. In other words, `Point` type can be considered as a value type in other languages.

```koral
type Point(mut x Int, mut y Int);

let main() = {
    let a Point = Point(64, 128); 
    let b Point = a; // ok
    printLine(a.x); // 64
    printLine(b.x); // 64
    a.x = 128;
    printLine(a.x); // 128
    printLine(b.x); // 64
}
```

#### Member Functions

In addition to member variables, data types can also define member functions. Member functions allow our types to directly provide rich functions without relying on external functions.

Defining a member function is simple, just declare a block containing member functions after the type definition.

```koral
type Rectangle(length Int, width Int) {
    area(self) Int = self.length * self.width;
}
```

As shown in the code above, we defined a member function `area`, which is used to calculate the area of the Rectangle.

Different from ordinary function definitions, member functions do not need to start with `let`, and usually the first parameter is `self`. It is used to represent the instance parameter of the current type.

You may have noticed that accessing member variables in member functions is similar to accessing member variables externally, except that we need to use `self` to represent the instance variable name.

Like member variable access, we only need to use `.` syntax to access member functions.

```koral
let main() = {
    let r = Rectangle(2, 4);
    printLine(r.area());
}
```

Executing the above program, we can see 8.

In addition to member functions containing `self`, we can also define member functions that do not contain `self`.

This type of function cannot be accessed using instances, but only using type names. It allows us to define some functions that are highly associated with the type but do not require an instance as a parameter.

```koral
type Point(x Int, y Int) {
    default() Point = Point(0, 0);
}

let main() = {
    let a = Point.default();
    printLine(a.x); // 0
    printLine(a.y); // 0
}
```

For example, in the above example, we defined a member function for constructing default values for Point. Then we called it using `Point.default`.

### Enum (Sum Type)

Enums allow you to define a type that can be one of several different variants. Each variant can carry different types of data. This is very useful when dealing with state machines or error handling.

```koral
type Shape {
    Circle(radius Float);
    Rectangle(width Float, height Float);
}

// Instantiate enum variant
let s = Shape.Circle(1.0);
```

#### Using Enum Values

We can extract data carried in enum variants through Pattern Matching. This is the most common and safest way to handle enums.

```koral
let area = when s is {
    .Circle(r) then 3.14 * r * r;
    .Rectangle(w, h) then w * h;
}
```

In the `when` expression, we use the form `.VariantName` to match specific variants and destructure the data within them.

## Trait and Given

Koral uses Traits to define shared behavior. This is similar to interfaces (Interface) or type classes (Type Class) in other languages.

### Defining Trait

A Trait defines a set of method signatures, and any type that implements the Trait must provide concrete implementations of these methods.

```koral
trait Show {
    toString(self ref) String;
}
```

### Implementing Trait (Given)

Use the `given` keyword to implement a Trait for a specific type. This mechanism allows you to add new behaviors to existing types without modifying the type definition (extensibility).

```koral
given Point Show {
    toString(self ref) String = "Point(\(self.x), \(self.y))";
}
```

### Extension Methods

The `given` block can be used not only to implement Traits, but also to directly add methods to types. These methods are like they come with the type itself.

```koral
given Point {
    // Add distance method to Point type
    distance(self ref) Float = { ... }
}
```

## Generics

Generics allow you to write code that applies to multiple types, thereby improving code reusability.

### Generic Data Types

Let's think about a scenario, what should we do when we want to return two values on the return type of a function?

For simple cases, we can define a fixed type to wrap two values.

```koral
type Pair(left Int, right Int);

let f() Pair = Pair(1, 2);
```

But if we have many different types that need to be wrapped, the above method is not general enough.

We need a Pair that can represent holding arbitrary types, and we can define it with the help of generic data types.

The difference between generic data types and data types is that it needs to additionally declare type parameters. These type parameters indicate that they will be replaced by actual incoming types in the future, so that the types of member variables or member functions can be replaced with concrete types during subsequent instantiation.

```koral
type [T1 Any, T2 Any]Pair(left T1, right T2);
```

As shown in the code above, we declared T1 and T2 two type parameters in the form of another parameter on the left side of `Pair`. The Any on their right indicates the characteristics of T1 and T2, where Any can be any type. Any can also be replaced with other traits.

If we need multiple type parameters, we can declare them one by one in order, separated by `,`. The call also needs to give actual types in the same order.

Unlike ordinary parameters, identifiers of type parameters always start with an uppercase letter and have no type annotation.

Next, let's see how to construct generic data types.

```koral
let main() = {
    lef a1 [Int, Int]Pair = [Int, Int]Pair(1, 2);
    // a1.left Int, a1.right Int
    lef a2 [Bool, Bool]Pair = [Bool, Bool]Pair(true, false);
    // a2.left Bool, a2.right Bool
    lef a3 [Int, String]Pair = [Int, String]Pair(1, "a");
    // a3.left Int, a3.right String
}
```

As shown in the code above, when we use generic Pair, we need to pass actual types in the position of generic parameters. Depending on the types we pass in, the types of left and right of the corresponding variables will also be different.

In this way, we have implemented a sufficiently general Pair type. For two values of any type, we can use it as our return type, greatly simplifying the number of types we need to define.

The above code is still quite verbose to write. In fact, when the context type is clear, we can omit the type parameters during generic type construction. So we can use a more concise way to achieve the above function.

Just like the code below, it is equivalent to the code above.

```koral
let main() = {
    lef a1 = Pair(1, 2);
    // a1 [Int, Int]Pair
    lef a2 = Pair(true, false);
    // a2 [Bool, Bool]Pair
    lef a3 = Pair(1, "a");
    // a3 [Int, String]Pair
}
```

### Generic Functions

Now we already have powerful generic data types, but we still have no way to implement functions for a generic type of arbitrary type, such as merging any two lists of the same type.

Yes, we need to have generic functions to achieve it.

Generic functions are very similar to generic types, both define generic parameters using the same syntax in front of the identifier.

```koral
let [T]mergeList(a [T]List, b [T]List) [T]List = {
    let c [T]List = [];
    for v = a then {
        c.pushBack(v);
    }
    for v = b then {
        c.pushBack(v);
    }
    c
}
```

As shown in the code above, we declared the type parameter T using the same generic syntax on the left side of `mergeList`.

Next, let's see how to call generic functions.

```koral
let main() = {
    let x = [1, 2, 3];
    let y = [4, 5, 6];
    let z = [Int]mergeList(x, y);
    // z == [1, 2, 3, 4, 5, 6]
}
```

As shown in the code above, it is almost the same as ordinary function calls, except that type parameters are added in front of the function name, just like the construction of generic data types.

By the same token, when the context is clear, we can also omit type parameters. The code below is equivalent to the code above.

```koral
let main() = {
    let x = [1, 2, 3];
    let y = [4, 5, 6];
    let z = mergeList(x, y);
}
```
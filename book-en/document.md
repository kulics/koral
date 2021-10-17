# The Feel Programming Language

Feel is an open source programming language focused on efficiency. It can help you easily build cross-platform software.

With well-designed grammar rules, this language can effectively reduce the burden of reading and writing, allowing you to focus on solving problems.

## Key Features

- A modern grammar, which is easy to distinguish.
- Automatic memory management.
- Generics.
- Multi-paradigm programming.
- Cross-platform.
- Unicode.

## Index

1. [Install](#Install)
1. [Basic Grammar](#Basic-Grammar)
1. [Basic Types](#Basic-Types)
1. [Operators](#Operators)
1. [Select Structure](#Select-Structure)
1. [Loop Structure](#Loop-Structure)
1. [Function](#Function)
1. [Structure](#Structure)

## Install

Currently `Feel` supports compilation to `JVM`, so you need to install `JVM` environment on your system.

The execution compiler will scan the `.feel` file of the current folder and automatically translate it to the target file of the same name.

download:

- [JVM](https://github.com/kulics-works/feel-jvm)

## Basic Grammar

### Basic Statement

Within Feel, statements are the smallest unit of composition and each statement must be terminated with a semicolon. Other than this, Feel has no other restrictions on statements and developers are free to write statements in a way that suits their style.  

The basic form of the statement is as follows.

```feel
let a = 0;
let b = 1;
```

Since Feel uses a semicolon as the terminator of a statement, we can write a statement in multiple lines when the elements in a statement are too long.

E.g.

```feel
let a = 1 + 1 + 1
        + 1 + 1;
```

### Entry Function

We need to define an entry point to let the program know where to start from, which we can declare via the main function.

```feel
let main() = {};
```

Here we declare a function named main, `=` with the return value of the function on the right, and `{}` indicating that the function does not execute anything.

More details on the function will be explained in the following sections.

### Display information

Now let's have our program output something to see, we can use the `println` function to print some information to the console.

E.g.

```feel
let main() = println("Hello, world!");
```

Now try to execute this program and we can see `Hello, world!` displayed on the console.

### Comment

Comments are only used to provide additional information to the user and are not actually compiled into the executable program.

E.g:
```
// Comment

/*
    Complicated
    Comment
*/
```

### Variable

Feel's variables are a kind of binding semantics, equivalent to binding a variable name and a value together, thus establishing an association, similar to a key-value pair. For security reasons, Feel's variables cannot be changed by default, but Feel also provides another kind of variables - mutable variables.

#### Immutable Variable

Immutable variables are declared in Feel using the let keyword, and variables are declared first and used later.

Feel ensures type safety through static typing, and variable bindings can be explicitly typed at declaration time, or we can omit the type if there is enough information in the context, and the compiler will infer the type of the variable from the context.

The sample code is as follows.

```feel
let a Int = 5; // Explicitly labeled type
let b = 123; // Auto-inferred type
```

Once an immutable variable has been declared, its type and value will not be changed in the current scope.

If we try to assign a value to an immutable variable, the compiler will report an error.

```feel
let a = 5;
a = 6; // Error
```

#### Mutable Variable

If we need a variable that can be reassigned, we can use a mutable variable declaration.

Mutable variables are declared in Feel with the let mut keyword, again following the first-declared-first-used principle.

The sample code is as follows.

```feel
let mut a Int = 5; // Explicitly labeled type
let mut b = 123; // Auto-inferred type
```

### Assignment

For mutable variables, we can change their value as many times as we need to.

Feel's assignment statement, like most languages, uses the `=` declaration. The left side of `=` must be a variable that can be assigned, and the program will assign the value on the right side of `=` to the variable on the left.

The sample code is as follows.

```feel
let mut a = 0;
a = 1;
a = 2;
```

### Block Expression

In Feel, `{}` represents a block expression, which can contain a series of statements and an optional last expression, and the result of the block expression is also an expression.

The value of the last expression in a block expression is the value of the block. If there is no last expression, then the value of the block is the Void.

A block expression allows you to combine a series of operations, such as multi-step initialization of a complex value.

```feel
let a Void = {};
let b Int = {
    let c = 7; 
    let d = c + 14;
    (c + 3) * 5 + d / 3
};
```

### Identifier

The identifier is the name given to a variable, function, structure, interface, etc. The letters that make up an identifier have a certain specification. The naming rules for identifiers in this language are as follows:

1. Case sensitive, Myname and myname are two different identifiers;
1. The first character of the identifier can begin with an underscore `_` or a letter, but cannot be a number;
1. Other characters in the identifier can be underscore `_`, letters or numbers.
1. Within the same `{}`, identifiers of the same name cannot be defined repeatedly.
1. Within the different `{}`, you can define an identifier for the duplicate name, and the language will prefer the identifier defined in the current scope.

## Basic Types

We only need a few simple basic types to do most of the work.

### Integer

Since our current computer architecture is good at calculating integers, a separate integer type helps to improve the efficiency of the program.

In Feel, the default integer is of type `Int`, which can represent signed integer type data.

E.g:

```feel
let i Int = 3987349;
```

### Float Point Number

Integers don't satisfy our needs for numbers, and we often need to deal with decimals.

In Feel, the default decimal is of type `Float`, which can represent floating-point data.

E.g:

```feel
let f1 float = 855.544;
let f2 float = 0.3141592653;
```

### Character

Computers usually use a specific number to encode characters, so a type is needed to express the characters. This is the `Char` type.

It can only be a single character, it only represents the correspondence between a certain character and a number, so it is a character and a number.

You only need to wrap a character with `''`, it will be recognized as a character value.

E.g:

```feel
let c1 Char = 'x';
let c2 Char = '8';
```

### String

We are not living in a world where only numbers, so we also need to use text to display the information we need.

In this language, the default text is the `String` type, which is an unlimited length of string data.

You only need to wrap a piece of text with `""`, which will be recognized as a string value.

E.g:

```feel
let s String = "Hello, world!";
```

It should be noted that a string is a type consisting of multiple characters, so in fact the string is a fixed-order list, and there is a correspondence between the two. Many times we can process strings as if they were lists.

### Boolean

Boolean refers to logical values because they can only be true or false. It is often used to aid in the judgment logic.

In this language, the default boolean is the `Bool` type, which is a type with only true and false values.

E.g:

```feel
let b1 Bool = true;
let b2 Bool = false;
```

## Operators

Operator is a symbol that tells the compiler to perform specific mathematical or logical operations.

We can simply understand the computational notation in mathematics, but programming languages have different places.

### Arithmetic Operators

The arithmetic operators are mainly used for data operations of numeric types, and most of the statements conform to the expectations in mathematics.

E.g:

```feel
let a = 4;
let b = 2;
println( a + b );    // + plus
println( a - b );    // - minus
println( a * b );    // * multiply
println( a / b );    // / divide
println( a % b );    // % residual, meaning the remainder remaining after the divisibility, the result here is 2
```

### Comparison Operators

The comparison operator is mainly used in judgment conditions to calculate the relationship between two data, with the result being `true` if it meets the expectation and `false` if it doesn't.

E.g:

```feel
let a = 4;
let b = 2;
println( a == b );   // == equal to
println( a <> b );   // <> not equal to
println( a > b );    // > Greater than
println( a >= b );   // >= Greater than or equal to
println( a < b );    // < less than
println( a <= b );   // <= less than or equal to
```

### Logical Operators

Logical operators are also used primarily in judgment conditions to perform logical operations (AND, OR, and NOT).

E.g:

```feel
let a = true;
let b = false;
println( a && b );    // && AND, both are true at the same time
println( a || b );    // || OR, one of them is true
println( ~~a );       // ~~ NOT, boolean inversion
```

## Select Structure

The judgment statement executes the program by one or more of the set conditions, executes the specified statement when the condition is `true`, and executes the specified statement when the condition is `false`.

We only need to use `? expression {}` to declare the judgment statement and enter the corresponding area according to the following values.

E.g:

```feel
let main() = if 1 == 1 then println("yes") else println("no");
```

Executing the above program will show `yes`.

Therefore, we can write the above program in the same way, and the results are equivalent in both ways.

```feel
let main() = println(if 1 == 1 then "yes" else "no");
```

Since if is itself an expression, it is natural that else can be followed by another if expression, so that we can achieve a continuous conditional judgment.

```feel
let x = 0;
let y = if x > 0 then "bigger" else if x == 0 then "equal" else "less";
```

When we don't need to handle else branches, we can omit the else branch. This if syntax without an else branch is not an expression but a statement, and the then branch must be followed by a block expression.

```feel
let main() = {
    if 1 == 1 then {
        println("yes");
    };
};
```

## Loop Structure

A loop structure is a program structure that is set up when a function needs to be executed repeatedly in a program. It is a condition in the loop body that determines whether to continue executing a function or to exit the loop.

In Feel, the loop structure is represented by the while syntax, where the while is followed by a judgment condition, and the branch after the then keyword is executed when the condition is `true`, and then it returns to the judgment condition for the next loop, and ends the loop when the condition is `false`.

This while syntax is a statement and not an expression.

E.g:

```feel
let main() = {
    let mut i = 0;
    while i <= 10 then {
        println(i);
        i = i + 1;
    };
};
```

Executing the above program will print 0 to 10.

The break statement can be used when we need to actively exit the loop in the middle of a loop. The program will exit the current nearest level of the loop when it reaches break.

```feel
let main() = {
    let mut i = 0;
    while true then {
        if i > 20 then {
            break;
        };
        println(i);
        i = i + 1;
    };
};
```

Executing the above program will print 0 to 20.

If we need to skip some rounds in the loop, we can use the continue statement. The program will skip the current round when it reaches continue and continue with the next loop.

```feel
let main() = {
    let mut i = 0;
    while i <= 10 then {
        if i % 2 == 0 then {
            continue;
        };
        println(i);
        i = i + 1;
    };
};
```

Executing the above program will print an odd number between 0 and 10.

## Function

Function is a separate block of code used to accomplish a specific task.

Usually we will package a series of task processing that needs to be reused into a function, which is convenient for reuse in other places.

### Definition

We have already seen the entry function, which is defined using the fixed name main.

When we need to define other functions, we can use the same syntax to define functions with other names.

The function is defined by the let keyword. The function name is followed by `()` to indicate the parameters accepted by the function, and the return type of the function is enclosed in parentheses. The return type can be omitted when the context is clear, and the compiler infers the return type.

An expression must be declared to the right of the function `=`, and the value of this expression is the return value of the function.

```feel
let f1() Int = 1;
let f2(a Int) = a + 1;
```

### Call

So how do we use these defined functions? We just use the `()` syntax after the function expression to call the function and get the function's return value.

`()` must be passed with the corresponding type of arguments as required by the function definition.


```feel
let a = f1();
let b = f2(1);
```

### Parameters

Parameters are the data that a function can receive when it is executed, and with these different parameters we can make the function output different return values.

For example, we can implement a square function that returns the square value of the argument each time it is called.

It is very simple, we only need to use `parameterName type` to declare parameters.

```feel
let sqrt(x Int) Int = x * x;
let a = sqrt(x); // a == 4
```

sqrt takes an argument of type Int, x, and returns the square of it. When calling sqrt we need to give the expression of the corresponding Int type to complete the call.

```feel
let add(x Int, y Int) Int = x + y;
let a = add(1, 2); // a == 3
```

### Function Type

In Feel, a function is a type just like Int, Float, etc. Similarly, a function can be used as an expression.

The type of a function is declared using the fn keyword, and the function definition requires the same declaration of the argument type and return type.

Once a function is defined, the function name can be used as an expression and can be assigned to other variables or used as parameters and return values.

Variables of function types are called with the same `()` syntax as functions.

```feel
let sqrt(x Int) = x * x; // sqrt fn(Int) Int
let f fn(Int) Int = sqrt;
let a = f(2); // a == 4
```

For example, with this feature, we can also define parameters or return values for function types.

```feel
let hello() = println("Hello, world!");
let run(f fn() Void) = f();
let toRun() = run;
let main() = {
    toRun()(hello);
};
```

Executing the above code we see `Hello, world!`.

### Lambda Expression

It's sometimes awkward to define a function and then pass it in as above, because we just want to perform a small function, and we don't necessarily want to define a function for use elsewhere.

At this point we can use the syntax of the Lambda expression to simplify our code.

Lambda expressions are very similar to function definitions, except that they are declared using the fn keyword and cannot be specified by name.

As shown in the code below, the value of f2 is a lambda, which is the same type as f1 and has a very similar syntax, with lambda's also declaring parameters and return types, and requiring an expression as the return value.

```feel
let f1(x Int) Int = x + 1; // f1 fn() Int
let f2 = fn(x Int) Int = x + 1; // f2 fn() Int
let a = f1(1) + f2(1); // a == 4
```

## Structure

A structure is a collection of data that consists of a series of data with the same type or different types; it is a composite data type.

Obviously, structures are suitable for packing different data together to form a new type that facilitates the manipulation of complex data.

### Definition

We can declare a new structure using the def keyword. The structure needs to declare the member variables it has using `()`, similar to the parameters of a function.

```feel
def Empty();
```

Above we declared a new structure called Empty, which contains no data at all.

Next let's try defining some more meaningful structures.

```feel
def Point(x Int, y Int);
```

Point is a structure with two member variables, x and y, that can be used to represent a point in a two-dimensional coordinate system. This allows us to use the Point type to represent our data in the coordinate system, instead of always using two separate Int data.

### Construct

So how do we construct a new Point data?

As with the function type, we use the same `()` syntax to call our structure and we get the data we need.

```feel
let a Point = Point(0, 0);
```

### Using Member Variables

Now that we have a Point data, how do we use the x and y in it?

It's simple, we just need to use the `. ` syntax to access them.

```feel
def Point(x Int, y Int);

let main() = {
    let a = Point(64, 128);
    println(a.x);
    println(a.y);
};
```

Executing the above program, we can see 64 and 128.

### Mutable Member Variables

Member variables, like variables, are immutable by default. So we can't reassign values to x and y in Point. If we try to do so, the compiler will report an error.

```feel
def Point(x Int, y Int);

let main() = {
    let a = Point(64, 128);
    a.x = 2; // error
};
```

We can mark a member variable with the mut keyword just like a mutable variable, so that it becomes a mutable member variable and can be reassigned.

```feel
def Point(mut x Int, mut y Int);

let main() = {
    let a = Point(64, 128);
    a.x = 2;
    a.y = 0;
};
```


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
- Multiple backends, supporting C # / Go / JavaScript / Kotlin.
- LLVM will be supported soon.

# Index
1. [Install](#Install)
1. [Basic Grammar](#Basic-Grammar)
1. [Basic Types](#Basic-Types)
1. [Operators](#Operators)
1. [Collection Types](#Collection-Types)
1. [Judgment](#Judgment)
1. [Loop](#Loop)
1. [Function Type](#Function-Type)
1. [Structure Type](#Structure-Type)
1. [Namespace](#Namespace)
1. [Interface Type](#Interface-Type)
1. [Enumeration Type](#Enumeration-Type)
1. [Check](#Check)
1. [Asynchronous Processing](#Asynchronous-Processing)
1. [Generics](#Generics)
1. [Annotations](#Annotations)
1. [Optional Type](#Optional-Type)

# Install
Currently `Feel` supports compilation to `C#/Go/JavaScript/Kotlin`, so you need to install `.NET Core/Go/NodeJS/JDK` environment on your system.

The execution compiler will scan the `.feel` file of the current folder and automatically translate it to the target file of the same name.

we needs to use the function of some language libraries, so please refer to the library corresponding to the compiler.

download:
- [C#](https://github.com/kulics-works/feel-csharp/releases)
- [Go](https://github.com/kulics-works/feel-go/releases)
- [JavaScript](https://github.com/kulics-works/feel-javascript/releases)
- [Kotlin](https://github.com/kulics-works/feel-kotlin/releases)

# Basic Grammar
## Basic Statement
Within this language, any expression must be attributed to the statement.

The basic form of the statement is:
```
StatementContent;
```
In this language, the grammar rules are clear, and each statement has a clear scope and must be terminated by `;` or `newline`.
So in most cases, we can end up using line breaks directly. When there is a special need, you can choose to use `;` to maintain the current line.

So we prefer to write like this:
```
StatementContent
StatementContent
```

## Export Namespace
All content in this language can only be defined in the namespace, which can effectively manage the content into distinct blocks to manage, you can freely define in a separate namespace without having to be too restrictive.

We can use the `<- name` statement to define the namespace of the current file.

E.g:
```
<- Demo
```
The meaning of this statement is to mark the content tag in the current code file as `Demo`, so that the content naming inside is limited to the area, and it is not necessary to consider the naming conflict with the outside of the area.

At the same time, the external area can import `Demo` to use the content, we will learn how to import.

## Import Namespaces
We can use the `name` statement in the import statement `-> {}` to import other namespaces, libraries, and frameworks into a namespace.

E.g:
```
<- Demo

-> {
    System
}
```
This imports the `System` library in the `Demo` namespace and then you can use them in your program.

You can write multiple import statements, and their order does not affect the import function.

For more details on namespaces, please see [Namespace](#Namespace)

## Main Entry
We need to define a main entry to let the program know where to start. The main entry is declared via a function `Main = () {}`.

E.g:
```
<- Demo

-> {
    System
}

Main = () {
}
```
The main entry function here is a function with no arguments and no return value. It is automatically recognized as the main entry. The main entry function is executed when the program starts, so we only need to write the function in the main entry function.

In the examples that follow, we're all executing in the main entry function by default, so we won't show this part of the code too much.

In particular, there can only be one main entry function in a namespace because the entry must be unique.

More details on the function will be explained in the following sections.
## Display information
We use programs to get some useful information, so we need to have the ability to display information for us to browse, this function can be display, print or output.

If we're writing a console program, we can use the `Print()` function, which displays data or text information to the console for us to browse.

E.g:
```
Print("Hello world")    ` Output Hello world `
```
In the examples that follow, we will use the console as a demo environment.

## Comment
Comments are only used to provide additional information to the user and are not actually compiled into the executable program.

E.g:
````
` Comment `

```
    Complicated
    Comment
```
````

## Invariable
### Definition
Invariable in this language refer to data that cannot be changed after initialization. We use `identifier : type` to define invariable.

**The identifier must begin with a uppercase.**

E.g:
```
A : Int
B : Bool
```
This creates an identifier for the name on the left and defines it as the type on the right, where the identifier is a null value.

Once an identifier is created, its data type will not be changed in the valid area.
### Initialization
After we have defined the constant, the assignment statement is used to initialize it. The constant can only be assigned once.

As with regular programming languages, we can use the `identifier = value` statement to assign the data on the right to the identifier on the left.

E.g:
```
A = 1
B = true
```

### Binding
If we need to define and initialize the invariable once, we can use the `identifier : type = value` statement for binding.

E.g:
```
A : Int = 1
B : Bool = false
```

Because this language has intelligent automatic derivation, we can usually omit `: type` when the value is clear.

E.g:
```
A = 1
B = false
```

Since invariable cannot be modified once they have been assigned, we can bind a new constant directly with an assignment.

## Variable
### Definition
Variables in this language refer to data that can continue to change after initialization. We use `identifier : type` to define variables.

**The identifier must begin with a lowercase.**

E.g:
```
a : Int
b : Bool
```
### Assignment
Like invariable, variables are assigned by the same assignment statement, except that variables can be assigned multiple times.

E.g:
```
a = 1
a = 2
b = false
b = true
```
 
### Binding
As with invariable, if we need to define and initialize a variable once, we can use the `identifier : type = value` statement for binding.

E.g:
```
a : Int = 1
b : Bool = false
```

Similarly, we can continue to use automatic derivation.

E.g:
```
a = 1
b = false
```

## Identifier
The identifier is the name given to a variable, function, structure, interface, etc. The letters that make up an identifier have a certain specification. The naming rules for identifiers in this language are as follows:

1. Case sensitive, Myname and myname are two different identifiers;
1. The first character of the identifier can begin with an underscore `_` or a letter, but cannot be a number;
1. Other characters in the identifier can be underscore `_`, letters or numbers.
1. Within the same `{}`, identifiers of the same name cannot be defined repeatedly.
1. Within the different `{}`, you can define an identifier for the duplicate name, and the language will prefer the identifier defined in the current scope.
1. The identifier at the beginning of uppercase is immutable and the identifier at the beginning of lowercase is variable.
1. In namespaces, structs, and interfaces, attributes and method names that begin with an underscore `_` are considered private and the rest are considered public.

# Basic Types
We only need a few simple basic types to do most of the work.

## Integer
Since our current computer architecture is good at calculating integers, a separate integer type helps to improve the efficiency of the program.

In this language, the default integer is the `Int` type, which is a 32-bit signed integer type data, an alias of type `I32`, which is equivalent.

E.g:
```
integer : Int = 3987349
```

If we need integers in other numeric ranges, we can use other types. All supported integer types are listed below.
```
I8          ` 8-bit  signed -128 to 127 `
U8, Byte    ` 8-bit  unsigned 0 to 255 `
I16         ` 16-bit signed -32,768 to 32,767 `
U16         ` 16-bit unsigned 0 to 65,535 `
I32, Int    ` 32-bit signed -2,147,483,648 to 2,147,483,647 `
U32         ` 32-bit unsigned 0 to 4,294,967,295 `
I64         ` 64-bit signed -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807 `
U64         ` 64-bit unsigned 0 to 18,446,744,073,709,551,615 `
```
## Basic Type Conversion
Since the default integers are `Int`, how do we use other types of integers?

We can use the base type conversion to change the number to the type we need, just use the `To_Type()` method.

E.g:
```
integer8 = (16).To_I8()
```

## Float Point Number
Integers don't satisfy our needs for numbers, and we often need to deal with decimals.

In this language, the default decimal is the `Num` type, which is a 64-bit double-precision floating-point data, an alias of the `F64` type, which is equivalent.

E.g:
```
float1 : Num = 855.544
float2 : Num = 0.3141592653
```

It should be noted that due to the particularity of computer computing floating-point numbers, floating-point operations have certain accuracy problems, so the need for precision-sensitive requirements should consider special handling.

All supported floating point types are as follows:
```
F32         ` 32 bits ±1.5e−45 to ±3.4e38 `
F64, Num    ` 64 bits ±5.0e−324 to ±1.7e308 `
```
## Character
Computers usually use a specific number to encode characters, so a type is needed to express the characters. This is the `Chr` type.

It can only be a single character, it only represents the correspondence between a certain character and a number, so it is a character and a number.

You only need to wrap a character with `''`, it will be recognized as a character value.

E.g:
```
char1 : Chr = 'x'
char2 : Chr = '8'
```
## String
We are not living in a world where only numbers, so we also need to use text to display the information we need.

In this language, the default text is the `Str` type, which is an unlimited length of string data.

You only need to wrap a piece of text with `""`, which will be recognized as a string value.

E.g:
```
string : Str = "Hello world!"
```

It should be noted that a string is a type consisting of multiple characters, so in fact the string is a fixed-order list, and there is a correspondence between the two. Many times we can process strings as if they were lists.
## String Template
Many times we need to insert other content into the string. What do we usually do?

E.g:
```
title   = "Year:"
content = 2018
string  = "Hello world! " + title + content.To_Str()
` Hello world! Year:2018 `
```

This certainly does not affect the functionality, but we can use a more intuitive and convenient way, that is, a string template.
We can insert expressions directly using `\{expression}` syntax.

E.g:
```
string = "Hello world! \{title} \{content}"
` Hello world! Year: 2018 `
```

## Boolean
Boolean refers to logical values because they can only be true or false. It is often used to aid in the judgment logic.

In this language, the default boolean is the `Bool` type, which is a type with only true and false values.

E.g:
```
boolean1 : Bool = true       ` true `
boolean2 : Bool = false      ` false `
```
## Any Type
In particular, sometimes a type that can be any object is needed to assist in the completion of the function, which is `Any`.

E.g:
```
a : Any = 1   ` any type `
```

# Operators
Operator is a symbol that tells the compiler to perform specific mathematical or logical operations.

We can simply understand the computational notation in mathematics, but programming languages have different places.

## Arithmetic Operators
The arithmetic operators are mainly used for data operations of numeric types, and most of the statements conform to the expectations in mathematics.

E.g:
```
a = 4
b = 2
Print( a + b )    ` + plus `
Print( a - b )    ` - minus `
Print( a * b )    ` * multiply `
Print( a / b )    ` / divide `
Print( a % b )    ` % residual, meaning the remainder remaining after the divisibility, the result here is 2 `
Print( a ^ b )    ` ^ power `
```
In addition to numbers, there are other types that support arithmetic operations. For example, `Str` can use an addition operation to combine two paragraphs of text.

E.g:
```
a = "hello"
b = "world"
c = a + " " + b     ` "hello world" `
```

## Judging Operators
The judgment operator is mainly used in the judgment statement to calculate the relationship between the two data. The result is in accordance with the expected value of `true` and the non-conformity is `false`.

E.g:
```
a = 4
b = 2
Print( a == b )   ` == equal to `
Print( a <> b )   ` <> not equal to `
Print( a > b )    ` > Greater than `
Print( a >= b )   ` >= Greater than or equal to `
Print( a < b )    ` < less than `
Print( a <= b )   ` <= less than or equal to `
```
## Logical Operators
Logical operators are also used primarily in decision statements to perform logical operations (AND, OR, and NOT).

E.g:
```
a = true
b = false
Print( a && b )    ` && AND, both are true at the same time `
Print( a || b )    ` || OR, one of them is true `
Print( ~~a )       ` ~~ NOT, boolean inversion `
```

## Assignment Operator
The assignment operator is mainly used to assign the data on the right to the identifier on the left, or it can be accompanied by some shortcut operations.

E.g:
```
a = 1       ` = the simplest assignment `
a += 1      ` += First add and then assign `
a -= 1      ` -= First subtraction and then assign `
a *= 1      ` *= First multiply and then assign `
a /= 1      ` /= First divide and then assign `
a %= 1      ` %= First residual and then assign `
a ^= 1      ` ^= First power and then assign `
```
## Bit Operation
Bit operations are the basis for the underlying calculations and are also supported in this language.

E.g:
```
a = 1
a &&& 1      ` bitwise AND `
a ||| 1      ` bitwise OR `
a ^^^ 1      ` bitwise XOR `
~~~a         ` bitwise inversion `
a <<< 1      ` left shift `
a >>> 1      ` right shift `
```

# Collection Types
When we need to combine many of the same types of data together, we can use the collection to accomplish this task.

Our built-in collection types are both list and dictionary.

## List
The List uses an ordered list to store multiple values of the same type. The same value can appear multiple times in a different location in a list.

### Definition
We only need to use the `{ expression }` syntax to enclose the data we need to create a list.
In most cases, data types can be automatically inferred from the language.

E.g:
```
list = { 1;2;3;4;5 }
```
This will create a list of `Int` types containing `1` to `5`.

If you need a list of explicit types, you can use the constructor to create them.

The representation of the list type is `(element_type)List`.

For example we need a list of strings:
```
list = (Str)List{}     ` empty `
```

### Access
If we need to access one of the elements in the list, we can access it with `identifier[index]`.

E.g:
```
Print( list[1] )
```
It should be noted that in the programming language, most of the list start index starts from `0`, the `identifier[0]` gets the first element, and the next element and so on.
### Change Element
If we need to change one of the elements in the list, we can access the element directly and use the assignment statement to change it.

E.g:
```
list[0] = 5
```
It should be noted that we can only access the index of the existing data, if it does not exist, an error will occur.
### Common Operations
```
list.Append(1)          ` Add to the end `
list.Insert(2, 3)       ` Insert element 3 to index 2 `
list.Remove(1)          ` Delete the specified location element `
length = list.Size()    ` Length `
```

## Dictionary
The Dictionary is used to store a collection of unordered data of the same type. Each value of the dictionary is associated with a unique key, and the key is used as an identifier for the value data in the dictionary.

Unlike the data items in the list, the data items in the dictionary are not in a specific order. We need to access the data through identifiers (keys), which is largely the same as the way we use dictionary lookups in the real world.

The dictionary keys can only use the `integer` and `string` types.
### Definition
Similar to the list, the dictionary is also defined using `{}`, except that the dictionary type is a union type of `key` and `value`, and the form is `[key]=value`.

E.g:
```
dictionary = {["a"]=1; ["b"]=2; ["c"]=3}
```
This will create a `(Str, Int)Dictionary` type dictionary containing three entries for `a,b,c`.

If you need an explicit type of dictionary, you can also use the constructor to create it.

The representation of the dictionary type is `(key_type, value_type)Dictionary`.

E.g:
```
dictionary = (Int, Int)Dictionary{}  ` empty `
```
### Access
Similar to the list, we can also use the index to access the data directly.

E.g:
```
Print( dictionary["a"] )
```
### Change Element
Similar to lists, we can also use assignment statements to change elements.

E.g:
```
dictionary["b"] = 5
```
Different from the list, if the index is an index that does not exist, it will not be wrong, and the value will be directly assigned to the new key.
### Common operations
```
dictionary["d"] = 11        ` Add Element `
dictionary.Remove("c")      ` Delete the specified index element `
length = dictionary.Size()  ` Length `
```

# Judgment
The judgment statement executes the program by one or more of the set conditions, executes the specified statement when the condition is `true`, and executes the specified statement when the condition is `false`.

We only need to use `expression ? {}` to declare the judgment statement and enter the corresponding area according to the following values.

E.g:
```
true ? {
    Print("true")     ` true `
}
```
## Simple Judgment
When the judgment value is only of the `Bool` type, the statement is executed only when it is `true`.

If you only need `false`, use `| ? {}` to declare it.

E.g:
```
b = false
b ? {
    ...... ` Because B is false, so never enter this branch `
}
| ? {
    ...... ` proccess false `
}
```

## Successive Judgment
If we have a continuous condition to determine, we can insert the continuous syntax `| expression ? {}`.

E.g:
```
i = 3
i == 0 ? {
    ......
}
| i == 1 ? {
    ......
}
| i == 2 ? {
    ......
}
| ? {
    ......
}
```

## Successive Single-conditional Judgment
If we need to make multiple consecutive equality decisions on an expression, we can use the `expression == | expression ? {}` statement.

Yes, just like above, every condition here is ended when it is executed and does not continue downward.

If multiple conditions need to be merged together, you can use `|` to separate them.

E.g:
```
i == 
| 1 | 2 | 3 ? {
    ......
}
| 4 ? {
    ......
}
```

This syntax can support all comparison operators.

E.g:
```
i <= 
| 0 ? {
    ......
}
| 100 ? {
    ......
}
| 500 ? {
    ......
}
| ? {
    ......
}

x :: 
| Int ? {
    ......
}
| Str ? {
    ......
}
| Num ? {
    ......
}
| ? {
    ......
}
```

# Loop
Sometimes we may need to execute the same piece of code multiple times.

In general, statements are executed in order, the first statement in the function is executed first, then the second statement, and so on.
## Collection loop
If we happen to have a collection that can be an array, a dictionary, or a piece of text, then we can use the `expression @ identifier {}` statement to iterate over the collection, taking each element out of `identifier`.

E.g:
```
arr = {1; 2; 3; 4; 5}
arr @ item {
    Print(item)   ` print every number `
}
```

If we need to fetch the index and value at the same time, we can replace `identifier` with the `[index_identifier]value_identifier` syntax, which is valid for both the list and the dictionary.

E.g:
```
arr @ [i]v {
    Print("\{i}:\{v}")
}
```

## Iterator loop
Sometimes, we don't necessarily have a collection, but we need to take the number from `0` to `100`. We have an iterator syntax to accomplish such a task.

The iterator can take the number from the start point to the end point loop. We use the expression of the set, separated by two numbers using the `..` symbol.

E.g:
```
0 .. 100 @ i {
    Print(i)  ` print every number `
}
```
It should be noted that the meaning of `0 .. 100` is read from `0` to `100`, that is, a total of `101` times. The iterator will execute until the last number is executed, rather than ending one at a time.

The iterator defaults to increment `1` every interval. If we need to take every other number, we can add a condition for each step. Just insert `~ value`.

E.g:
```
0 .. 100 ~ 2 @ i {
    ......
}
```
So every time the interval is not `1` but `2`, we can set other numbers.

We can also let it traverse in reverse order, just use `...`.

E.g:
```
100 ... 0 @ i {
    ......  ` From 100 to 0 `
}
```

If we need to remove the last digit, we can use `..<` (ascending order) and `..>` (descending order).

## Conditional loop
What if we need a loop that only judges a certain condition?
Add a condition to it.

E.g:
```
i = 0
i < 6 @ {
    i += 1
}
```

## Jump out
So how do you jump out of the loop? We can use the `~@` statement to jump out.

E.g:
```
true @ {
    ~@    ` Jumped out without executing anything `
}
```

It should be noted that if you jump out of a multi-level nested loop, you will only jump out of the loop that is closest to you.
## Continue
If you only need to jump out of the current loop, use the `@` statement.

# Function Type
Function is a separate block of code used to accomplish a specific task.

Usually we will package a series of task processing that needs to be reused into a function, which is convenient for reuse in other places.

In practical engineering practice, given a certain input, the function that must accurately return the determined output is considered a better design. Therefore, it is recommended to maintain the independence of the function as much as possible.
## Definition
We have seen the main entry function before, it is only defined using the fixed statement `Main = () {}`.

We only need to define a function using the `(->) {}` collocation. The parentheses in front are the input parameters, and the parentheses in the back are the parameters.

E.g:
```
function = (->) {
    ......
}
```
This defines a function with the identifier `function`.
## Call
Unlike the main entry function, which cannot be called, regular functions can be called with an identifier. We only need to use the `identifier()` statement to use the wrapped function.

E.g:
```
function()  ` Call function `
```

## Parameters
Although functions can perform specific functions without any parameters, more often we need to be able to receive some input data, or can return data, or both, and this requires parameters to help us complete task.

Very simple, we only need to declare the parameters using `identifier : type`.

E.g:
```
func = (x : Int -> y : Int) {
    <- x * 2
}
```
The meaning of this function is that it accepts an `Int` parameter `x` of the input and returns a `Int` parameter `y`.

The left are the in parameters, and the right are the out parameters. There is no limit on the number of parameters in the parentheses, but there are strict requirements on the order and type.
### Return
At this point, even if you don't say it, you can guess that `<-` should be a statement related to the return.

Yes, we only need to use `<-` to specify an explicit return statement.

E.g:
```
<- 1, 2, 3, "Hello"
```
This will return four values ​​of `1, 2, 3, "Hello"`.

If you do not need to return data, you can omit the data.

E.g:
```
<-
```

If it's a function that doesn't need to return a value, the language will automatically add an exit function at the end of the function, so we can optionally omit some of the return statements.

We can use the return statement to terminate the function early in any place within the function, which satisfies our need for logic control.

It should be noted that, like the looping out of the loop, the return statement will only abort the layer function closest to itself.

### Input Parameters
We refer to the parameters entered into the function as input parameters, there can be no or multiple parameters, and there is no limit to the type and identifier.

When we call a function, we need to fill the data in parentheses in the order defined. When the order or type does not match, it is considered to be used incorrectly.

E.g:
```
` Define a function that contains two input parameters `
sell = (price : Int, name : Str ->) {}
` Fill in the required data according to the defined requirements `
sell(1.99, "cola")
```
### Output Parameters
Similar to the input parameters, the output parameter needs to be explicitly defined with an identifier, which makes it easier for the caller to get the function information of the function.

E.g:
```
top_sell = (-> name : Str, count : Int) {
     ......
     <- "cola", 123
}
```
### Omit the Output Parameters
When the language can infer the return value type, we can omit the Output Parameters and '->'.

E.g:
```
top_sell = () {
    ......
    <- "cola", 123
}
```

### Use of return value
So how do we get the return value of a function?

It's very simple, just like we do add, subtract, multiply and divide, just use the function.

E.g:
```
n, c = top_sell()        ` Assign the returned two values ​​to n and c `
```
You can use a definition or assignment statement to get the return value of the function to use, or you can nest a function that meets the requirements into another function.

E.g:
```
Print( top_sell() )      ` print two values ` ​
```

## Function Input Parameter
If we want some of the details of the function to be defined externally, and only the rest of the logic is executed internally, such as processing some functions for a collection traversal, we can use the function input parameters to accomplish this goal.

There is no special way to define function arguments, just replace the argument type with a function, do not need to define the function execution content, and omit the identifier.

E.g:
```
each_1_to_10 = (func : (Int->)) {
     1 .. 10 @ i {
         func(i)
     }
}
```
We define a function entry called `func` whose type is a function that has only one input parameter.

This way we can pass the details of the processing to the external incoming `func` definition.

E.g:
```
Show = (item : Int) {
     Print(item)
}

each_1_to_10(Show)
```
Thus, we executed the `Show` function in the loop inside `each_1_to_10`.

The function input parameter only requires the same parameter type of the function, and does not require the same name of the parameter.

## Lambda Expression
It's sometimes awkward to define a function and then pass it in as above, because we just want to perform a small function, and we don't necessarily want to define a function for use elsewhere.

At this point we can use the syntax of the Lambda expression to simplify our code.

Since the function argument is already determined at the time of declaration, we can use the simplified syntax `(identifier) {statements}` to express it, which means defining the argument identifier and executing the function statement.

E.g:
```
foreach( (it) { 
    Print(it)
    Print(it * it)
    Print(it / 2)
})
take( (a, b) {a + b} )
```
Very simple, the difference from the expression of a function type is that you only need to declare the parameter identifier and execution logic, and neither the type nor the return value need to be declared.

## Lambda Function
Unlike the simplified notation above, we can also write a complete function directly, just as we define functions.

E.g:
```
each_1_to_10( (item : Int ->) {
    Print(item)
})
```

# Structure Type
If we only have a few basic data, it is actually very difficult to describe something more specific.

So we need a feature that wraps data from different attributes to better describe what we need.

Obviously, the function responsible for packaging data is the structure.
## Definition
We can use the `identifier = $ {}` statement to define a structure that has nothing.

E.g:
```
Package = $ {
}
```
Of course, we prefer to pack a few data, such as a student with a name, student number, class, and grade attribute.
We can define this data in the structure of the body just like we would define a normal identifier.

E.g:
```
Student = $ {
    name   : Str = ""
    number : Str = ""
    class  : Int = 0
    grade  : Int = 0
}
```
This way we get the Student structure with these data attributes. This structure is like a type that can be used like `Int, Str, Bool`.

Unlike our original base type, which only stores one type of data, this structure can store data such as name, student number, class, and grade.

This is very much like the concept of assembling different parts together into a whole in reality.

## Build
So how do we build a new structure? As a whole, all of our types can be build using the method `type{}`.

E.g:
```
peter = Student{}
```
This build a `peter` identifier, and all of the student's properties are initialized to `"", "", 0, 0` as set in the definition.

Let's review that our base types and collection types can be created using method, in fact they are all structures.

## Using Properties
Now that we have a `peter`, how do we use the properties inside?

Quite simply, we only need to use the `.` syntax to summon the properties we need.

E.g:
```
Print( peter.name )   ` Printed the name of a student `
```
The same is true for changing the value of an attribute, which is equivalent to a nested identifier. We can use the assignment statement to change the value directly.

E.g:
```
peter.name      = "peter"
peter.number    = "060233"
peter.class     = 2
peter.grade     = 6
```

## Building Assignments
Building a new structure like above and loading the data one by one is very cumbersome, and we can configure it using a simplified syntax.

E.g:
```
peter = Student{
    name    = "peter"
    number  = "060233"
    class   = 2
    grade   = 6
}
```

Similarly, the way a collection is build is actually a build syntax, so we can also create arrays and dictionaries like this.

E.g:
```
list        = (Int)List{ 1; 2; 3; 4; 5 }
dictionary  = (Str, Int)Dictionary{ ["1"]=1; ["2"]=2; ["3"]=3 }
```
## Anonymous Structure
If we only want to wrap some data directly, instead of defining the structure and then using it, can it be like an anonymous function?

Of course.

E.g:
```
peter = $ {
    name    = "peter"
    number  = "060233"
    class   = 2
    grade   = 6
}{}
```

This creates a `peter` data directly, which we can use directly.

## Private Property
Anyone will have some little secrets, and `peter` is the same. Maybe he hides the name of a secret little girlfriend and doesn't want others to know.

We can define private properties to store properties that we don't want to be accessed by the outside world.

E.g:
```
Student = $ {
    ......
    _girl_friend : Str    ` The first character is the identifier of _ is private `
}
```
That's right, if you remember the definition of the identifier, this is how the private identifier is defined. The private identifier is not accessible to the outside world.

So if we define a `peter`, we can't get the value or modify the value through `peter._girl_friend`.

The private property of this structure can not be accessed, and can not be modified. What is the use? Don't worry, we can use the functions.

E.g:
```
Student = $ me { ` declare me `
    ......
    get_girl_friend = () {
        <- me._girl_friend
    }
}
```

The `me` here is used to declare the structure itself, so that you can easily access its own properties. It's just a parameter, so you can freely use identifiers other than `me`.

Through the function properties, we can obtain private properties, and can easily handle other data in the structure according to business needs.

With this function, we can get the private property by calling the function.

E.g:
```
Print( peter.get_girl_friend() )
` Printed the name of a girlfriend of a student `
```
Like data attributes, functions can also be private identifiers. Functions that use private identifiers also mean that only structures can access them.

## Combination
Now let us use our imagination. How do we define a structure that is specifically tailored for Chinese students?

E.g:
```
Chinese_Student = $ {
    name      = ""
    number    = ""
    class     = 0
    grade     = 0
    kungfu    = false    ` not learn kungfu `
}
```
No, no, it's not very elegant to repeat the definition of data. We can reuse the student attributes and add an extra kung fu attribute.

We need to combine this feature, but it's not that complicated, just create a student property.

E.g:
```
Chinese_Student = $ {
    student    = Student{}     ` include the student attribute in it `
    kungfu     = false         ` not learn kungfu `
}
```
This way you can use common attributes through the student attributes in Chinese students.

E.g:
```
chen = Chinese_Student{}
Print( chen.student.name )
```
By combining layers of structure, you can freely assemble anything you want to describe.

More recently, if we want to include all the attributes of a structure directly instead of a combination, we can use the top-level combination statement, declared as `type`.

Top-level combinations extract attributes from the structure to the exterior, just as they contain corresponding attributes directly. This is conducive to the use and transmission of attributes.

E.g:
```
Chinese_Student = $ { 
    Student   ` top-level combination `
    kungfu = false
}
```

In this way, we can call student attributes directly.

E.g:
```
chen = Chinese_Student{}
Print( chen.name )
```

# Namespace
Namespace are designed to provide a way to separate a set of names from other names. A name declared in one namespace does not conflict with a name declared in another namespace.

## Export
In order to facilitate our management of the code, we must write our code in the namespace, we can expose it to external use through public properties, or use private properties to complete our own business.

E.g:
```
<- Name.Space

get_something = () {
    <- "something"
}
```
## Import
We can use other namespace content through the import function, and the namespace content can be called directly after import.

E.g:
```
<- Run

-> { 
    Name.Space 
}

Main = () {
    ` print something `
    Print( get_something() )
}
```

# Interface Type
In reality, we often use protocols to specify specific rules, and people or things can do things according to the expected rules.
We often need to do this in the programming language. This function is the interface.

An interface is used to specify the functions necessary for a particular function, and a structure is considered to implement an interface as long as it contains all the functions required by an interface.

## Definition
Interfaces are defined directly using `{}` and, unlike constructs, none of their members have initial values.

E.g:
```
Protocol = {
}
```

Next, let's design a difficult task that students need to accomplish... homework.

E.g:
```
Homework = {
    Get_count : (->v : Int)
    Do_homework : (->)
}
```
This is a Homework interface that has two functions, one to get the number of homeworks and one to complete them.

Next, we will let the students implement this interface.

## Implementing Interface
We add functions directly to the structure to implement this interface.

E.g:
```
Student = $ {
    count = 999999
    Get_count = () {
        <- count
    }
    Do_homework = () {
        Spend_time(1)       ` took an hour `
        count -= 1          ` completed one `
    }
}
```
It is very difficult for our students to write homework...

Let us explain what happened to this code:
1. We implemented an interface, now `Student` is also considered to be the `Homework` type, we can use a `Student` as `Homework`.
1. Within the interface we include two properties defined by the interface `Get_count, Do_homework`, according to the regulations, one can not be less.
1. We have written the actual values and functions for each of the two properties of the interface, so that these two properties become one of the valid sub-properties of `Student`.
1. We did something in `Do_homework`, which reduced the total amount of work.

## Using the interface
After the interface is included, we can use the student who owns the interface.

E.g:
```
peter = Student{ count=999999 }
Print( peter.Get_count() )
` print 999999, so much `
peter.Do_homework()
` Do somework `
Print( peter.Get_count() )
` print 999998, still so much `
```
If you just use it, there is no advantage to defining these two properties directly in the structure.

Let's think back and forth about the role of the interface. The interface is such that each structure containing the interface has the same properties as specified.

This way for the interface builder, there is no need to care about how the structure follows the interface. Just know that they are all followed and you can use them in the same way.

Now we can create a variety of students, they all follow the same interface, we can use the functions in the interface without any difference.

E.g:
```
` Created three different types of student structures `
student_a = Chinese_Student{}
student_b = American_Student{}
student_c = Japanese_Student{}
` Let them do their homework separately `
student_a.Do_homework()
student_b.Do_homework()
student_c.Do_homework()
```
A more efficient way is to write this function into the function, let the function help us repeat the function of the interface.

E.g:
```
do_homework = (student : Homework) {
    student.Do_homework()
}
` Now we can make each student do their homework more easily `
do_homework(student_a)
do_homework(student_b)
do_homework(student_c)
```
Of course, it's better to put these students in an array so that we can use loops to handle these repetitive tasks.

E.g:
```
arr = (Homework)List{}
arr.add( student_a )
......  ` Insert many many students `
arr @ i {
    do_homework(i)
}
```
╮( ̄▽ ̄)╭
perfect

## Type Judgment
Because the structure type can be converted to an interface type, the original type of data cannot be determined during use.

But sometimes we need to get the raw type of data to deal with, we can use type judgment to help us accomplish this.

We can use `expression :: type` to determine the type of data, and `expression ! type` to convert the data to our type.

E.g:
```
func = (he : Homework) {
    ` Determine if Chinese students `
    he :: Chinese_Student ? {
        ` Convert to Chinese Student Data `
        cs = he ! Chinese_Student
    }
}
```

# Enumeration Type
The enumeration is a set of integer constants with independent names. It can usually be used to mark the type of some business data, which is convenient for judgment processing.
## Definition
We only need to use the `| id` statement.

E.g:
```
Color = $ {
    | Red
    | Green
    | Blue
}
```
The enumeration assigns values to the identifiers in order, resulting in a collection of `Red = 0; Green = 1; Blue = 2`.

This way we don't need to care about their values when we use them, and we can safely mark the business we need to handle.

E.g:
```
c = Random_color()     ` Get a random color `
c == 
| Color.Red ? {
    ......
}
| Color.Green ? {
    ......
}
| Color.Blue ? {
    ......
}
```

It should be noted that enumerations can only be defined under the namespace.
## Specified value
We can also assign a single identifier if needed, and unspecified will continue to accumulate 1 in the order of the previous identifier.

E.g:
```
Number = $ {
    | A = 1   ` 1 `
    | B       ` 2 `
    | C = 1   ` 1 `
    | D       ` 2 `
}
```

# Check
There may be a variety of exceptions in the program.

- May be caused by files or user input.
- May be a coding error or a missing feature in the language.
- Of course, it may also be due to many other unpredictable factors.

Exceptions cannot be completely avoided, but we can choose some means to help us check and report exceptions.

## Reporting an exception
We can use `! <- exception` to declare an exception data anywhere in the function.

E.g:
```
read_file = (name : Str) {
    name.len == 0 ? {
        ! <- Exception("something wrong")
    }
    ......
}
```
So we declare an exception, the exception description is `something wrong`, once the external caller uses the illegal length of `name`, the function will be forced to abort, report the exception up and hand it to the caller.
## Checking exceptions
We can use the `{}` statement to check for exceptions and `& identifier : type ! {}` to handle exceptions.
`type` can be omitted, the default is `Exception`.

E.g:
```
{
    f = read_file("temp.txt")
}
& ex: IO_Exception ! {
    ! <- ex
}
& e ! {
    Print(e.message)
}
```
When an exception occurs, the program enters the error handling block, and `e` is the exception identifier. We can get the exception information or perform other operations.

If there are no exceptions, the logic of the exception handling block will not be entered.

In general, we can make early returns or data processing in exception handling. If there are exceptions that cannot be handled, we can continue to report upwards.

E.g:
```
{
    func()
}
& ex ! {
    ` Can be manually aborted `
    ` <- `
    ! <- ex
}
```

## Checking the delay
If we have a feature that we want to handle regardless of normal or abnormal procedures, such as the release of critical resources, we can use the check latency feature.

Quite simply, using `& ! {}` at the end of the check can declare a statement that checks for delays.

E.g:
```
func = () {
    f : File
    {
        f = read_file("./somecode.file")
    }
    & ! {
        f <> nil ? {
            f.Release()
        }
    }
    ......
}
```
So we declare `f.Release()` which is the statement that releases the file. This statement will not be executed immediately, but will wait for the call to be completed.

With check delays, we can safely handle certain tasks without having to worry about how to exit.

It should be noted that because the check delay is executed before the function exits and will be executed regardless of whether the program is running abnormally or not, the return statement cannot be used in the check delay.

E.g:
```
......
& ! {
    f.Release()
    <-  ` error, can not use the return statement `
}
```

# Asynchronous Processing
A thread is defined as the execution path of the program. Each thread defines a unique control flow. If your application involves complex and time-consuming operations, it is often beneficial to set up different thread execution paths, each thread performing a specific job.

Because the computer processor has a computational bottleneck, it is impossible to process everything one by one in a single-line order. In order to increase the processing capacity, we often need to use asynchronous parallel to solve the calculation problem.

Here we talk about how to handle threading problems more simply, that is, asynchronous processing.

## Asynchronous execution
So how to transform a synchronous function into an asynchronous function? Just use `~>`.

That's right, it's really just using `~>`.

E.g:
```
say_hello = () { 
    Print("hello")
    <- 2020
}

~> say_hello()
```

After converting a synchronous function into an asynchronous function, it will be transferred to a new thread for execution. 

This allows our logic to be processed in parallel, but at the same time makes it impossible for us to directly obtain the return value of this function, because the time when the function execution ends becomes no longer under our control, the current logic will not wait for the asynchronous function, but will continue to execute .

So the following code cannot be passed.

E.g:
```
result = ~> say_hello()
` Error, the current logic will continue to execute, and the return value cannot be obtained directly `
```

## Asynchronous waiting
If we need to convert a synchronous function into an asynchronous function and at the same time hope that the current logic can wait for the execution of this function to end, is it possible to write asynchronous code in a synchronous manner?

The answer is yes, we can use a unique syntax `function~>()` to execute a synchronous function. This function will not only be executed asynchronously, but the current program will also wait for it to complete before continuing to execute down.

In this way, we can get the results we want.

E.g:
```
result = say_hello~>()
` Correct, the current logic will wait for the asynchronous result before continuing execution `
...
```

## Use channel asynchronous communication
For direct waterfall logic, the above syntax can already satisfy our use. But there are some other scenarios where we may need to manually handle more asynchronous details. At this time, we can use channels to pass data to complete our asynchronous tasks.

The channel is a special collection, the type is `(type)Chan`, we can pass the specified type of data to the channel, use` id <~ value` to input data, and use `<~ id` to get data.

E.g:
```
channel = (Int)Chan{}

` The current logic will wait for the data transfer to complete before continuing execution `
channel <~ 666

` For the same reason, the current logic will be suspended when obtaining data `
Print(<~ channel)
......
```

With channels, we can implement asynchronous programming through simple assembly.

E.g:

```
ch = (Int)Chan{}

` Execute a concurrent function `
~> () {
    3 ... 0 @ i {
        ch <~ i
    }
}()

` Cyclic receive channel data `
true @ {
    data = <~ ch
    Print(data)

    ` When encountering data 0, exit the loop `
    data == 0 ? {
        ~@
    }
}
` Output 3 2 1 0 `
```

Since the channel is a collection type, we can also use the traversal syntax.

E.g:
```
ch @ data {
    ......
}
```

# Generics
When encapsulating common components, many times our structures, functions, and interfaces don't need to pay attention to the "what" of the entity passed by the caller. At this time, generics can be used.

For example, we now need a collection that supports adding, deleting, and reading. We hope that any type can be used to encapsulate a generic structure.

Our lists and dictionaries are actually implemented using generics.

## Declaration and Use
Let's see how to use generics to implement a list. We simply declare the generics of the type with the `(generics_identifier)` symbol.

This is a simplified implementation.

E.g:
```
(T)
MyList = $ {
    ` Create Storage `
    items  = (T)Storage{}    
    length = 0

    ` Get a generic data `
    Get = (index: Int -> item: T) {  
        <- items.Get( index )
    }

    ` Add a generic data to the list `
    Append = (item: T) {   
        items.Insert(length-1, item)
        length += 1
    }
}
```
So we define a structure that supports generics, `T` is a generic, in fact it can be any identifier, but habitual we will use `T` as a proxy.

Generics support multiple generations, for example: `(T, H, Q)`.

After the generics are defined, `T` is treated as a real type in the area of ​​the structure, and then we can use it like various places like `Int`.

So how do we use generics?

It's very simple, just use it as we declare it, just pass the real type when calling.

E.g:
```
list_number = (Int)MyList{}   ` Pass in Int type `
```
So we have a list of integer types, is it like this:
```
list_number = (Int)List{}
```
That's right, in fact, our list and dictionary syntax are generics.
## Supported Types
We can use generics in structures, functions, and interface types.

E.g:
```
(T)
func = (data : T -> data : T) {
    <- data
}

(T)
interface = {
    (R)Test : (in : R -> out : T)
}
```
## Generic Constraints
If we need to constrain the type of generics, we only need to use the `(T:contract)` syntax.

E.g:
```
(T:Homework)
StudentGroup = $ {
}
```

# Annotations
Annotations are declarative tags used to pass feature information of various elements (such as structures, functions, components, etc.) in a program at runtime.
Usually we use the annotation feature in many scenes of reflection and data parsing.

## Annotation Statement
We only use `[]`.
If you need to specify the specified attribute, you can use the `identifier = expression` assignment as you would a simplified build of the structure.

Note that it is valid to use before the identifier.

Let's take a look at the database data as a reference to see how to use annotations.

E.g:
```
[Table("test")]
Annotation = $ {
    [Key, Column("id")]
    id : Str
    [Column("name")]
    name : Str
    [Column("data")]
    data : Str
}
```
We declare a structure of `Annotation` that uses annotations to mark the table name `test`, primary key `id`, field `name`, and field `data`.

When processing the database, the database interface can be parsed into the corresponding name for data operations.

We use this structure directly inside the program. When the database function is called, the program will automatically map to the corresponding database data.
This greatly saves us the work of parsing and converting.

# Optional Type
All types in this language can't be null by default, which can avoid null problems to a great extent.
If a type is defined but not assigned, it will not be used.

E.g:
```
a : Int
b = a      ` error, no assignment to a `
```

## Declaration and Use

If you have to use a null type in some cases, you can use a nullable type.
Just add `?` after any type, which is a nullable type.

E.g:
```
a : Int?
b = a      ` b Assigned to an empty Int `
```

## Nil
We need a value that can be any type of null value, so it is `nil` .

E.g:
```
a = nil     ` nil value `
```

Once an optional type has appeared, we need to strictly handle null values ​​to avoid program errors.

E.g:
```
a <> nil ? {
    a.To_Str()
}
```

This is cumbersome, especially when we need to execute multiple functions in succession.
We can use `?` after the expression to use them, so that they will only be executed if they are not empty.

E.g:
```
arr?.To_Str()
```

## Merge Operation
If you want to use another default value when the value of the optional type is null, you can use the `id ? value`.

E.g:
```
b = a ? 128
```

## [Complete Example](../example.feel)
# Basic Type
We only need a few simple basic types to do most of the work.

## Integer
Since our current computer architecture is better at calculating integers, a separate integer type helps to increase the efficiency of the program.

In this language, the default integer is the `Int` type, which is a 32-bit signed integer type data, an alias of type `I32`, which is equivalent.

E.g:
```
Integer: Int = 3987349
```

If we need integers of other numeric ranges, other types can also be used. All supported integer types are shown in the following table.
```
I8      # 8-bit signed     -128 to 127 #
U8      # 8-bit unsigned   0 to 255 #
I16     # 16-bit signed    -32,768 to 32,767 #
U16     # 16-bit unsigned  0 to 65,535 #
I32     # 32-bit signed    -2,147,483,648 to 2,147,483,647 #
U32     # 32-bit unsigned  0 to 4,294,967,295 #
I64     # 64-bit signed    -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807 #
U64     # 64-bit unsigned  0 to 18,446,744,073,709,551,615 #
```
## Basic Type Conversion
Since the default integer is `Int`, how do we use other types of integers?

We can use type conversion to change the number to the type we need, just use the `to Type` method.

E.g:
```
Integer8 := (16).to I8()
```

Note that, the basic type conversion function is only valid for the base type.

If you need all types of casts, use the `to<Type>` method, which crashes against incompatible types, so use it with caution.
## Float 
Integers do not meet our digital needs, and we often need to deal with decimals.

In this language, the default decimal is the `Num` type, which is a 64-bit double-precision floating-point data, an alias of the `F64` type, which is equivalent.

E.g:
```
Float1: Num = 855.544
Float2: Num = 0.3141592653
```
Note that due to the special nature of computer-calculated floating-point numbers, there are certain accuracy issues in floating-point number operations, so the sensitivity-sensitive requirements should consider special handling.

All supported floating-point types are as follows:
```
F32     # 32-bit   ±1.5e−45 to ±3.4e38 #
F64     # 64-bit   ±5.0e−324 to ±1.7e308 #
```
## Literal Rules
Like identifiers, literals can be separated by spaces to improve readability.
```
Integer := 2018 03 09
Float := 3.14159 26535 89793 23846 26433 83279 50288 41971
```
## Character
Computers usually use a specific number to encode characters, so a type is needed to express the characters. This is the `Chr` type.

It can only be a single character, and it only represents the correspondence between a certain character and a number, so it is a character and a number.

You only need to wrap a character with `''`, it will be recognized as a character value.

E.g:
```
Char: Chr = 'x'
Char2: Chr = '8'
```
### String
We are not living in a world of numbers alone, so we also need to use text to display the information we need. 

In this language, the default text is the `Str` type, which is an unlimited-length character array data.

You only need to use `""` package a text content, it will be recognized as a string value.

E.g:
```
String: Str = "Hello world!"
```

It should be noted that a string is a type consisting of multiple characters, so in fact the string is a fixed-order list, and there is a correspondence between the two. Many times we can process strings as if they were lists.
## String Template
Many times we need to insert other content into a string. How do we usually do it?

E.g:
```
Title := "Year:"
Content := 2018
String := "Hello world! " + Title + Content.to Str()
# Hello world! Year:2018 #
```

This of course does not affect the functionality, but we can use a more intuitive and convenient way, that is string templates.
We can insert elements directly in the middle of two strings, and the language will automatically merge into one string.

E.g:
```
String := "Hello world! " Title ""  Content ""
# Hello world! Year:2018 #
```
## Boolean
boolean are logical values ​​because they can only be true or false. It is often used to assist in judging logic.

In this language, the default boolean is the type `Bool`, which is a type that has only True and False values.

E.g:
```
Boolean1: Bool = True      # true #
Boolean2: Bool = False     # false #
```
## Any
In particular, sometimes you need a type that can be any object to assist in the completion of the function, so it is `{}`.

E.g:
```
A: {} = 1  # any type #
```

## Nil value
We will need a value that can be any nil value, so it is `()`.

E.g:
```
() # empty value #
```

### [Next Chapter](operator.md)

## Example of this chapter
```
"Demo" {
    "System"
}

Main() -> () {
    A := 123
    B := A.to I64()
    C := 123.456
    D := "hello"
    E := "" D " world"
    F := True
    G: {} = False
}
```

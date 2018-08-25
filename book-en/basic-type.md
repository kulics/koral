# Basic Type
We only need three simple basic types, we can do most of the work.

## Integer
Since our current computer architecture is better at calculating integers, a separate integer type helps to increase the efficiency of the program.

In this language, the default integer is the `I32` type, which is a 32-bit signed integer type data.

E.g:
```
integer := 3987349
```

If we need integers of other numeric ranges, other types can also be used. All supported integer types are shown in the following table.
```
I8      // 8-bit signed     -128 to 127
U8      // 8-bit unsigned   0 to 255
I16      // 16-bit signed    -32,768 to 32,767
U16     // 16-bit unsigned  0 to 65,535
I32     // 32-bit signed    -2,147,483,648 to 2,147,483,647
U32     // 32-bit unsigned  0 to 4,294,967,295
I64     // 64-bit signed    -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807
U64     // 64-bit unsigned  0 to 18,446,744,073,709,551,615
```
## Basic Type Conversion
Since the default integer is `I32`, how do we use other types of integers?

We can use type conversion to change the number to the type we need, just use the `ToType` method.

E.g:
```
integer8 := (16).ToI8.()
```

Note that, the basic type conversion is only valid for the base type.
## Float 
Integers do not meet our digital needs, and we often need to deal with decimals.

In this language, the default decimal is `F64`, which is a 64-bit double-precision floating-point data.

E.g:
```
float := 855.544
float = 0.3141592653
```
Note that due to the special nature of computer-calculated floating-point numbers, there are certain accuracy issues in floating-point number operations, so the sensitivity-sensitive requirements should consider special handling.

All supported floating-point types are as follows:
```
F32 // 32-bit   ±1.5e−45 to ±3.4e38
F64 // 64-bit   ±5.0e−324 to ±1.7e308
```
### String
We are not living in a world of numbers alone, so we also need to use text to display the information we need. 

In this language, the default text is the `Str` type, which is an unlimited-length character array data.

You only need to use `""` package a text content, it will be recognized as a string value.

E.g:
```
string := "Hello world!"
```
## Mark String
Many times we need to insert other content into a string. How do we usually do it?

E.g:
```
title := "Year:"
content := 2018
string := "Hello world! " + title + content.ToStr.()
// Hello world! Year:2018
```

This of course does not affect the functionality, but we can use a more intuitive and convenient way.
That's the mark string. Just wrap the content with `/""/`, and use `{}` to mark the content in the content.

E.g:
```
string := /"Hello world! {title} {content}"/
// Hello world! Year:2018
```

If you need to use `{` and `}` in the mark string, you only need to use `{{` and `}}`.

E.g:
```
string := /"This is block {{ and }}"/
// This is block { and }
```
## Boolean
boolean are logical values ​​because they can only be true or false. It is often used to assist in judging logic.

In this language, the default boolean is the type `Bool`, which is a type that has only true and false values.

E.g:
```
boolean := true  // true  
boolean = false  // false  
```
## Any
In particular, sometimes you need a type that can be any type to assist in the completion of the function, so it is `Any`.

E.g:
```
a :Any = 1 // any type
```
## Nullable Type
All types in this language can't be null by default, which can avoid null problems to a great extent.
If a type is defined but not assigned, it will not be used.

E.g:
```
a : I32
b := a   // error, no assignment to a
```

If you have to use a type with null values in some cases, you can use a nullable type.
Just add `?` after any type, which is a nullable type.

E.g:
```
a : I32?
b := a   // b assigns an empty I32
```
## null
We will need a value that can be any null value, so it is `null`.

E.g:
```
null // empty value
```
## Create a null value with type
Sometimes, maybe we do not need to specify a specific value, but only want to create a type of default.

Especially when using generics, you can not create directly using type conStructs.

At this time we can use the null create method `null.(type)` to specify a null value that contains a type.

E.g:
```
x := null.(I64?)
y := null.(Protocol?)
z := null.(()->()?)
```
More details on generics can be found in the generic section.

### [Next Chapter](operator.md)

## Example of this chapter
```
Demo
{
    .. System

    Main ()
    {
        a := 123
        b := a.ToI64.()
        c := 123.456
        d := "hello"
        c := /"{d} world"/
        e := true
        f :Any = false
        g :I32? = null
        h := null.(I32?) 
    }
}
```
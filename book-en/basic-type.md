# Basic Type
We only need three simple basic types, we can do most of the work.

## integer
Since our current computer architecture is better at calculating integers, a separate integer type helps to increase the efficiency of the program.

In this language, the default integer is the `integer` type, which is a 32-bit signed integer type data.

E.g:
```
3987349
```
Its size range is
```
-2,147,483,648 ~ 2,147,483,647
```
## float 
Integers do not meet our digital needs, and we often need to deal with decimals.

In this language, the default decimal is `float`, which is a 64-bit double-precision floating-point data.

E.g:
```
855.544
0.3141592653
```
Its size range is
```
-1.79769313486232E+308 ~ 1.79769313486232E+308
```
This is a very large number range, so there is little need to worry about the scope issue.

Note that due to the special nature of computer-calculated floating-point numbers, there are certain accuracy issues in floating-point number operations, so the sensitivity-sensitive requirements should consider special handling.
### text
We are not living in a world of numbers alone, so we also need to use text to display the information we need. This type is `text`.

You only need to use `""` package a text content, it will be recognized as a text value.

E.g:
```
"Hello world!"
```
## bool
`bool` are logical values ​​because they can only be true or false. It is often used to assist in judging logic.

E.g:
```
true // true
false // false
```
## any
In particular, sometimes you need a type that can be any type to assist in the completion of the function, so it is `any`.

E.g:
```
any // any type
```
## nil
Similarly, sometimes you will need a value that can be any nil value to assist in the completion of the function, so it is `nil`.

E.g:
```
nil // empty value
```
## Create a null value with type
Sometimes, maybe we do not need to specify a specific value, but only want to create a type of default.

Especially when using generics, you can not create directly using type constructs.

At this time we can use the null create method `~<>` to specify a null value that contains a type.

E.g:
```
x => ~<integer>;
y => ~<Student>;
```
More details on generics can be found in the generic section.

### [Next Chapter](operator.md)
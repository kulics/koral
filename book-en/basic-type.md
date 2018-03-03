# Basic Type
We only need three simple basic types, we can do most of the work.

### number
In this language, all numbers are simply unified as `number` types. You can use integers or decimals directly without distinction of type, and without specifying the size, they work effectively in most situations.

E.g:

    3987349 // integer
    855.544 // mixed number
    0.3141592653 // pure decimal

Its size range is

    -1.79769313486232E + 308 ~ 1.79769313486232E + 308

This is a very large number of ranges, so there is little need to worry about scoping.
### text
We are not living in a world of numbers alone, so we also need to use text to display the information we need. This type is `text`.

You only need to use `""` package a text content, it will be recognized as a text value.

E.g:

    "Hello world!"

### bool
`bool` are logical values ​​because they can only be true or false. It is often used to assist in judging logic.

E.g:

    true // true
    false // false

### any
In particular, sometimes you need a type that can be any type to assist in the completion of the function, so it is `any`.

E.g:

    any // any type
    
### nil
Similarly, sometimes you will need a value that can be any nil value to assist in the completion of the function, so it is `nil`.

E.g:

    nil // empty value

### Create a null value with type
Sometimes, maybe we do not need to specify a specific value, but only want to create a type of default.

Especially when using generics, you can not create directly using type constructs.

At this time we can use the null create method `~<>` to specify a null value that contains a type.

E.g:

    x => ~<number>;
    y => ~<Student>;

More details on generics can be found in the generic section.

### [Next Chapter](operator.md)
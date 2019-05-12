# Enumeration
Enumerations are a set of integer constants with independent names. Usually can be used to mark some types of business data, to facilitate the judgment process.
## Definition
We only need to use the `id -> type[id id id id]` statement.

E.g:
```
Color -> U8[
    Red
    Green
    Blue
]
```
The enumeration assigns values to the identifiers in order, and finally gets a collection of `Red=0, Green=1, Blue=2`.

In this way, we don't need to care about their values when we use them, and we can mark the business we need to handle.

E.g:
```
c := randomColor()     # Get a random color
c ? Color.Red {
     ......
} Color.Green {
     ......
} Color.Blue {
     ......
}
```

It should be noted that the enumeration can only be defined in the namespace.
## Specified value
If necessary, we can also assign a value to a single identifier. If not specified, we can continue accumulating 1 in the order of the previous identifier.

E.g:
```
Number -> U8[
    A = 1   # 1
    B       # 2
    C = 1   # 1
    D       # 2
]
```

### [Next Chapter](check.md)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    Prt( A.Z )
    Prt( B.Z )
}

A -> U8[
    X 
    Y 
    Z
]

B -> U8[
    X 
    Y=0 
    Z
]
```
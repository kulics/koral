# Enumeration
Enumerations are a set of integer constants with independent names. Usually can be used to mark some types of business data, to facilitate the judgment process.
## Definition
We only need to use the `id [id, id, id, id]` statement.

E.g:
```
Color [Red, Green, Blue]
```
The enumeration assigns values to the identifiers in order, and finally gets a collection of `Red->0, Green->1, Blue->2`.

In this way, we don't need to care about their values when we use them, and we can mark the business we need to handle.

E.g:
```
c := randomColor.()     # Get a random color
c.? Color.Red
{
     ...
}
Color.Green
{
     ...
}
Color.Blue
{
     ...
}
```

It should be noted that the enumeration can only be defined in the namespace.
## Specified value
If necessary, we can also assign a value to a single identifier. If not specified, we can continue accumulating 1 in the order of the previous identifier.

E.g:
```
Number 
[
    a = 1,    # 1
    b,        # 2
    c = 1,    # 1
    d         # 2
]
```

### [Next Chapter](check.md)

## Example of this chapter
```
Demo
{
    System
    XyLang\Library
}

main ()
{
    cmd.print.( A.Z )
    cmd.print.( B.Z )
}

A [X, Y, Z]
B [X, Y=0, Z]
```
# Optional Type
All types in this language can't be nil by default, which can avoid nil problems to a great extent.
If a type is defined but not assigned, it will not be used.

E.g:
```
a: I32
b := a   # error, no assignment to a
```

## Statement and Use

If you have to use a type with nil values in some cases, you can use a nullable type.
Just add `!` after any type, which is a nullable type.

E.g:
```
a: I32!
b := a   # b assigns an empty I32
```

Once an optional type has appeared, we need to strictly handle nil values to avoid program errors.

E.g:
```
# Judgment is not empty and then use
? a ~= nil {
     a.ToStr()
}
```

This is cumbersome, especially when we need to execute multiple functions in succession.
We can use `?` after the expression to use them, so that they will only be executed if they are not empty.

E.g:
```
arr?.ToStr()
```

## Get Pointer
If you need to get a pointer of an optional type, you can use the `id?` syntax.

E.g:
```
b := a?
```
## Get Value
If you need to get an optional type of value, you can use the `id!` syntax.

E.g:
```
b := a!
```
## Merge Operation
If you want to use another default value when the value of the optional type is null, you can use the `id ?! value` syntax.

E.g:
```
b := a ?! 128
```

## [Complete Example](../example.xs)

## Example of this chapter
```
\Demo <- {
    System
}

Example -> {
    Main() -> () {
        a: I32! = nil

        b: [I32!]! = [I32!]!{0}
        b?[0]?.ToStr()?.ToStr()

        c := a?
        d := a!

        e := a ?! 1024
    }
}
```
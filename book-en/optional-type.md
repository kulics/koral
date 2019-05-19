# Optional Type
All types in this language can't be nil by default, which can avoid nil problems to a great extent.
If a type is defined but not assigned, it will not be used.

E.g:
```
a: Int
b := a   # error, no assignment to a
```

## Statement and Use

If you have to use a type with nil values in some cases, you can use a nullable type.
Just add `^` forward any type, which is a nullable type.

E.g:
```
a: ^Int
b := a   # b assigns an empty Int
```

Once an optional type has appeared, we need to strictly handle nil values to avoid program errors.

E.g:
```
# Judgment is not empty and then use
? a >< () {
     a.ToStr()
}
```

This is cumbersome, especially when we need to execute multiple functions in succession.
We can use `^` after the expression to use them, so that they will only be executed if they are not empty.

E.g:
```
arr^.ToStr()
```

## Merge Operation
If you want to use another default value when the value of the optional type is null, you can use the `id.Def(value)` function.

E.g:
```
b := a.Def(128)
```

## [Complete Example](../example.xs)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    a: ^Int = ()

    b: ^[]^Int = []^Int{0}
    b^[0]^.ToStr()^.ToStr()

    e := a.Def(1024)
}
```
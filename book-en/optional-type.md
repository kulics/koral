# Optional Type
All types in this language can't be nil by default, which can avoid nil problems to a great extent.
If a type is defined but not assigned, it will not be used.

E.g:
```
A: Int
B := A   # error, no assignment to A
```

## Statement and Use

If you have to use a type with nil values in some cases, you can use a nullable type.
Just add `^` forward any type, which is a nullable type.

E.g:
```
A: ^Int
B := A  # B assigns an empty Int
```

Once an optional type has appeared, we need to strictly handle nil values to avoid program errors.

E.g:
```
# Judgment is not empty and then use
? A >< () {
     A.to Str()
}
```

This is cumbersome, especially when we need to execute multiple functions in succession.
We can use `^` after the expression to use them, so that they will only be executed if they are not empty.

E.g:
```
Arr^.to Str()
```

## Merge Operation
If you want to use another default value when the value of the optional type is null, you can use the `id.or else(value)` function.

E.g:
```
B := A.or else(128)
```

## [Complete Example](../example.xs)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    A: ^Int = ()

    B: ^[]^Int = []^Int{0}
    B^[0]^.to Str()^.to Str()

    E := A.or else(1024)
}
```
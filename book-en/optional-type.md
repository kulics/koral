# Optional Type
All types in this language can't be nil by default, which can avoid nil problems to a great extent.
If a type is defined but not assigned, it will not be used.

E.g:
```
a: i32
b := a   # error, no assignment to a
```

## Statement and Use

If you have to use a type with nil values in some cases, you can use a nullable type.
Just add `?` after any type, which is a nullable type.

E.g:
```
a: i32?
b := a   # b assigns an empty i32
```

Once an optional type has appeared, we need to strictly handle nil values to avoid program errors.

E.g:
```
# Judgment is not empty and then use
? a ~= nil {
     a.toStr()
}
```

This is cumbersome, especially when we need to execute multiple functions in succession.
We can use `?` after the expression to use them, so that they will only be executed if they are not empty.

E.g:
```
arr?.toStr()
```

## Ignore optional types of warnings
If the data is of an optional type, but we guarantee that the data will not be empty, we can use the mandatory optional type to let the compiler ignore the warning.
Just replace `?` with `!`.

E.g:
```
a: i32!
b := a
a!.toStr()
```

## [Complete Example](../example.xs)

## Example of this chapter
```
\Demo <- {
    System
}

example -> {
    Main() -> () {
        a: i32? = nil

        b: [i32?]? = [i32?]?{0}
        b?[0]?.toStr()?.toStr()

        c: [i32!]! = [i32!]!{0}
        c![0]!.toStr()!.toStr()
    }
}
```
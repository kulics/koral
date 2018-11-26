## Nullable Type
All types in this language can't be nil by default, which can avoid nil problems to a great extent.
If a type is defined but not assigned, it will not be used.

E.g:
```
a : i32
b := a   # error, no assignment to a
```

If you have to use a type with nil values in some cases, you can use a nullable type.
Just add `?` after any type, which is a nullable type.

E.g:
```
a : i32?
b := a   # b assigns an empty i32
```
## Example of this chapter
```
Demo {
    System
    Library
}

Main ()->() {
    a := 123
    b := a.toI64()
    c := 123.456
    d := "hello"
    c := "{d} world"
    e := true
    f :obj = false
    g :i32? = nil
    h := lib.def<i32>()
}
```
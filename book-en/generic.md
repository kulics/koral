# Generic
When encapsulating common components, many times our packages, methods, and protocols do not need to be concerned with what the caller is delivering. This time, generics can be used.

For example, we now need a collection that supports adding, deleting, and reading, and we hope that any type can be used, we can package a generic package.

Our lists and dictionaries are actually implemented using generics.
## Statement and Use
Let's see how we can use generics to implement an List. We just use the `<>` sign after the identifier to enclose the generation of the type.

This is a simplified implementation.

E.g:
```
List<T>() -> {
    items := Storage{T}    # create storage
    Length := 0

    get(index: i32) -> (item: T) { # get some T item
        <- ( items.get( index ) )
    }
  
    add(item: T) -> () {   # add a T item to List
        items.insert(Length, item)
        Length += 1
    }
}
```
So we define a package that supports generics, `T` is a generic type, in fact it can be any identifier, just customary we will use` T` as a synonym.

Generic brackets, like parameters, support multiple generations, for example: `<T, H, Q>`.

After the generic is defined, `T` is treated as a real type within the area of ​​the package, and then we can use it in a variety of desired types just as `i32` does.

Note that because generics are typed at run time, the compiler can not infer generic constructor methods. We can only use the default value create method to construct generic data.

We can use the default value create method `def<type>()` to specify a default value that contains a type.

E.g:
```
x := def<i64>()
y := def<Protocol>()
z := def<()->()>()
```

This way we can use it in generics.

E.g:
```
Package<T>() -> {
    item := def<T>()    # initialized a default value of the generic data
}
```
So how do we use generics?

Very simple, and we can use the same statement, but called when the need to import the real type.

E.g:
```
ListNumber := List<i32>()  # pass in the number type
```
So we have an List of number types, is like this:
```
ListNumber := [i32]{}
```
Yes, in fact, our list and dictionary syntax are syntactic sugar, the actual types are `lst` and `dic`.
## Supported Types
We can use generics in packages, functions, and protocol types.

E.g:
```
Package<T> -> {
    Count: T
}

Func<T>(data: T) -> (data: T) {
    <- (data)
}

Protocol<T> <- {
    test<T>(in: T) -> () {}
}

Implement() -> {

} Protocol<Implement> {
    test<Implement>(in: Implement) -> () {
        
    }
}
```
### [Next Chapter](annotation.md)
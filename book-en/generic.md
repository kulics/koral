# Generic
When encapsulating common components, many times our packages, methods, and protocols do not need to be concerned with what the caller is delivering. This time, generics can be used.

For example, we now need a collection that supports adding, deleting, and reading, and we hope that any type can be used, we can package a generic package.

Our lists and dictionaries are actually implemented using generics.
## Statement and Use
Let's see how we can use generics to implement an List. We just use the `<>` sign after the identifier to enclose the generation of the type.

This is a simplified implementation.

E.g:
```
List<T> -> {
    Items := Storage{T}    # create storage
    Length := 0

    Get(index: Int) -> (item: T) { # get some T item
        <- ( Items.Get( index ) )
    }
  
    Add(item: T) -> () {   # add a T item to List
        Items.insert(Length, item)
        Length += 1
    }
}
```
So we define a package that supports generics, `T` is a generic type, in fact it can be any identifier, just customary we will use` T` as a synonym.

Generic brackets, like parameters, support multiple generations, for example: `<T, H, Q>`.

After the generic is defined, `T` is treated as a real type within the area of ​​the package, and then we can use it in a variety of desired types just as `Int` does.

Note that because generics are typed at run time, the compiler can not infer generic constructor methods. We can only use the default value create method to construct generic data.

We can use the default value create method `Def<type>()` to specify a default value that contains a type.

E.g:
```
x := Def<I64>()
y := Def<Protocol>()
z := Def<()->()>()
```

This way we can use it in generics.

E.g:
```
Package<T> -> {
    Item := Def<T>()    # initialized a default value of the generic data
}
```
So how do we use generics?

Very simple, and we can use the same statement, but called when the need to import the real type.

E.g:
```
listNumber := List<Int>{}  # pass in the number type
```
So we have an List of number types, is like this:
```
listNumber := []Int{}
```
Yes, in fact, our list and dictionary syntax are syntactic sugar, the actual types are `Lst` and `Dic`.
## Supported Types
We can use generics in packages, functions, and protocol types.

E.g:
```
Func<T>(data: T) -> (data: T) {
    <- (data)
}

Protocol<T> <- {
    Test<T>(in: T) -> () {}
}

Implement -> {
} Protocol<Implement> {
    Test<Implement>(in: Implement) -> () {
        
    }
}
```
## Generic Constraints
If we need to constrain the type of generics, we only need to use the `T:id` syntax.

E.g:
```
Package<T:Student> -> {
}
```
### [Next Chapter](annotation.md)
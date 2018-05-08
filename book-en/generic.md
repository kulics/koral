# Generic
When encapsulating common components, many times our packages, methods, and protocols do not need to be concerned with what the caller is delivering. This time, generics can be used.

For example, we now need a collection that supports adding, deleting, and reading, and we hope that any type can be used, we can package a generic package.

As you may recall, our collection uses the `System:Collections:Generic;` namespace, which is generic.

Our arrays and dictionaries are actually generics.

Again, we need to import generic namespaces to use generics.
```
System:Collections:Generic;
```
## Statement and Use
Let's see how we can use generics to implement an array. We just use the `<>` sign after the identifier to enclose the generation of the type.

This is a simplified implementation.

E.g:
```
Array<T> : #()
{
    Items : #Storage.(T); // create storage
    Length : ^i32;

    Get : $(index: i32)~(item: T) // get a generic data
    {
        -> (Items.Get.(index));
    };

    Add : $(item: T)~() // add a generic data into the array
    {
        Items.Insert.(Length, item);
        Length += 1;
    };
};
```
So we define a package that supports generics, `T` is a generic x, in fact it can be any identifier, just customary we will use` T` as a synonym.

Generic brackets, like parameters, support multiple generations, for example: `<T, H, Q>`.

After the generic is defined, `T` is treated as a real type within the area of ​​the package, and then we can use it in a variety of desired types just as `i32` does.

Note that because generics are typed at run time, the compiler can not infer generic constructor methods. We can only use the empty type constructor to construct generic data.

E.g:
```
Package<T> : #()
{
    Item : #(T); / / initialized a null value of the generic data
};
```
So how do we use generics?

Very simple, and we can use the same statement, but called when the need to import the real type.

E.g:
```
ArrNumber : #Array<integer>.(); // pass in the number type
```
So we have an array of number types, is like this:
```
ArrNumber : #[]integer.();
```
## Supported Types
We can use generics in packages, functions, and protocol types.

E.g:
```
Func<T> : $(data: T)~(data: T)
{
    -> (data);
};

Protocol<T> : &
{
    Test<T> : $(in: T)~(){};
};

Implement : #()
{
    ~& Protocol<Implement>
    {
        Test<Implement> : $(in: Implement)~(){};
    };
};
```
### [Next Chapter](annotation.md)
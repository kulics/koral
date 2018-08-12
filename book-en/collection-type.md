# Collection Type
When we need to combine many of the same types of data together, we can use the collection to accomplish this task.

Our built-in collection types are two types of arrays and dictionaries.

Collections need to use namespaces
```
System\Collections\Generic
```
## Array
Array use ordered lists to store multiple values ​​of the same type. The same value can appear more than once in different places in an array.
    
### Definition
We only need to use `[]` to enclose the data we need, and to split each data with `,` to create an array. In most cases, the data type can be automatically inferred by the language.

E.g:
```
arr := [ 1,2,3,4,5 ]
```
This will create a `i32` type array containing` 1` to `5`.

If you need an array of explicit types, you can create them using type tags or type creation syntax.

The array type is represented by `[]type`, where `[]` is a one-dimensional array, so multidimensional arrays can be represented as `[][][]type`.

For example we need a string array:
```
arr := ["1,"2","3" :str]    // tag type
arr2 := [:str]              // empty array
arr3 := []str.{}            // type creation
```
#### .NET Arrays
If we need to use the `.Net` native array type, we can use `[#]type` to represent it.
It can also be created directly using `#[]`.

E.g:
```
arrInt := [#]i32.{}
arrInt = #[1,2,3,4,5]
// corresponds to C#'s int[]
```
### Visit
If we need to access one of the elements in the array we can access it with the `identifier.[index]`.

E.g:
```
Console.WriteLine.( arr.[1] )
```
It should be noted that in the programming language, most of the array starting index is from `0`,` identifier [0] `is the first element obtained, the subsequent elements and so on.
### Change the element
If we need to change one of the elements in the array, we can access that element directly, using an assignment statement to change it.

E.g:
```
arr.[0] = 5
```
Note that we can only access the index of the existing data, if not exist, there will be an error.
### Common operation
```
arr.Add.(1)             // added to the end
arr.Insert.(2, 3)       // insert element 3 to index 2
arr.RemoveAt.(1)        // delete the specified location element
length := arr.Count     // length
```
## Dictionary
A dictionary is a collection of disparate data of the same type. Each value of a dictionary is associated with a unique key, which is used as an identifier for this value data in the dictionary.

Unlike the data items in an array, the data items in the dictionary do not have a specific order. We need to access the data through identifier (key), which is largely the same way we use dictionary literals in the real world.

Dictionary keys can only use `integer` and` string` types.
### Definition
Similar to arrays, dictionaries also use the `[]` definition, except that the dictionaries type is a combination of `key` and` value`, separated by `->`.

E.g:
```
dic := ["a"->1, "b"->2, "c"->3]
```
This will create a `str->i32` type dictionary containing` a, b, c` entries.

If you need an explicit type of dictionary, you can also create it using type tags or type creation syntax.

The dictionary type is represented by `[type]type` and `[type]` represents a one-dimensional dictionary, so the nested dictionary can be represented as `[type][type][type]type`.

This is almost the same as the above array representation method. Yes, arrays and dictionaries essentially use the index to locate the set of data. `[]` Represents a type of the index.

Since arrays only support numeric indexes, you can omit the `[i32]` tag. We can extend `[i32]type` to achieve consistent array types, but we usually don't need to do that (time is money. friend!).

E.g:
```
dicNumNum := [:i32->i32]
dicNumNum2 := [i32]i32.{}
```
### Visit
Like an array, we can also use indexes to access data directly.

E.g:
```
Console.WriteLine.( dic.["a"] )
```
### Change the element
Like arrays, we can also use assignment statements to change to elements.

E.g:
```
dic.["b"] = 5
```
The difference is that with the array, if the assignment is a non-existent index, it will not be wrong, the value will be given directly to the new key.
### Common operation
```
dic.Add.("d", 11)       // add index by method
dic.Remove.("c")        // delete the specified index element
length := dic.Count     // length
```
### [Next Chapter](judgment.md)

## Example of this chapter
```
Demo
{
    .. System, System\Collections\Generic

    Main ()
    {
        arr1 := [1,2,3,4,5]
        arr1.Add.(6)
        arr2 :[]i8 = [1,2,1,2 :i8]
        arr3 := #[1,2,3]

        dic1 := ["a"->1, "b"->2, "c"->3]
        dic1.["d"] = 4
        dic2 :[i8]i8 = [1->1,2->2,3->3 :i8->i8]
    }
}
```
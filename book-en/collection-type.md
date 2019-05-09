# Collection Type
When we need to combine many of the same types of data together, we can use the collection to accomplish this task.

Our built-in collection types are two types of lists and dictionaries.
## List
List use ordered lists to store multiple values ​​of the same type. The same value can appear more than once in different places in an List.
    
### Definition
We only need to use `{ e1,e2,e3 }` syntax to enclose the data we need, and to split each data with `,` to create an List. In most cases, the data type can be automatically inferred by the language.

E.g:
```
list := { 1,2,3,4,5 }
```
This will create a `I32` type List containing` 1` to `5`.

If you need an List of explicit types, you can create them using construct function.

The List type is represented by `[]type`.

For example we need a string list:
```
list := []Str{}         # empty List
```
#### Array
If we need to use the native Array type, we can use `[type]` to represent it.
It can also be created directly using `ArrOf(e1,e2,e3)`.

E.g:
```
arr: [I32] = ArrOf(1,2,3,4,5)
```
### Visit
If we need to access one of the elements in the List we can access it with the `identifier[index]`.

E.g:
```
Prt( list[1] )
```
It should be noted that in the programming language, most of the List starting index is from `0`,` identifier[0] `is the first element obtained, the subsequent elements and so on.
### Change the element
If we need to change one of the elements in the List, we can access that element directly, using an assignment statement to change it.

E.g:
```
list[0] = 5
```
Note that we can only access the index of the existing data, if not exist, there will be an error.
### Common operation
```
list += 1                   # added to the end
list.Insert(2, 3)           # insert element 3 to index 2
list -= 1                   # delete the specified location element
length := list.Len          # length
```
## Dictionary
A dictionary is a collection of disparate data of the same type. Each value of a dictionary is associated with a unique key, which is used as an identifier for this value data in the dictionary.

Unlike the data items in an List, the data items in the dictionary do not have a specific order. We need to access the data through identifier (key), which is largely the same way we use dictionary literals in the real world.

dictionary keys can only use `integer` and` string` types.
### Definition
Similar to lists, dictionaries also use the `{}` definition, except that the dictionaries type is a combination of `key` and` value`, Form is `[key]value`.

E.g:
```
dictionary := {["a"]1, ["b"]2, ["c"]3}
```
This will create a `[Str]I32` type dictionary containing ` a, b, c` entries.

If you need an explicit type of dictionary, you can also create it using construct function.

The dictionary type is represented by `[type]type`.

E.g:
```
dictionaryNumNum := [I32]I32{} # Empty
```
### Visit
Like an List, we can also use indexes to access data directly.

E.g:
```
Prt( dictionary["a"] )
```
### Change the element
Like lists, we can also use assignment statements to change to elements.

E.g:
```
dictionary["b"] = 5
```
The difference is that with the List, if the assignment is a non-existent index, it will not be wrong, the value will be given directly to the new key.
### Common operation
```
dictionary += {["d"]11}         # add index by method
dictionary -= "c"               # delete the specified index element
length := dictionary.Len        # length
```
### [Next Chapter](judgment.md)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    list1 := {1,2,3,4,5}
    list1 += 6
    list2 := []I8{1,2,1,2}
    array := [I8]{1,2,3}

    dictionary1 := {["a"]1, ["b"]2, ["c"]3}
    dictionary1["d"] = 4
    dictionary2 := [I8]I8{[1]1,[2]2,[3]3}
}
```

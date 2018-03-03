# Collection Type
When we need to combine many of the same types of data together, we can use the collection to accomplish this task.

Our built-in collection types are two types of arrays and dictionaries.

Collections need to use namespaces
        
    System.Collections.Generic;

## Array
Array use ordered lists to store multiple values ​​of the same type. The same value can appear more than once in different places in an array.
    
### Definition
We only need to use `[]` to enclose the data we need, and to split each data with `,` to create an array. In most cases, the data type can be automatically inferred by the language.

E.g:

    arr => [1,2,3,4,5];

This will create a `number` type array containing` 1` to `5`.

If you need an empty array of definite type, you can create it using the type-creation syntax.

For example we need a text array:

    arrText => [text]~();

### Visit
If we need to access one of the elements in the array we can access it with the `identifier[index]`.

E.g:

    Console.WriteLine(value: arr[1]);

It should be noted that in the programming language, most of the array starting index is from `0`,` identifier [0] `is the first element obtained, the subsequent elements and so on.
### Change the element
If we need to change one of the elements in the array, we can access that element directly, using an assignment statement to change it.

E.g:

    arr[0] = 5;
    
Note that we can only access the index of the existing data, if not exist, there will be an error.
### Common operation
    
    arr.Add(value: 1); // added to the end
    arr.Insert(index: 2, value: 3); // insert element 3 to index 2
    arr.RemoveAt(index: 1); // delete the specified location element
    length => arr.Count; // length

## Dictionary
A dictionary is a collection of disparate data of the same type. Each value of a dictionary is associated with a unique key, which is used as an identifier for this value data in the dictionary.

Unlike the data items in an array, the data items in the dictionary do not have a specific order. We need to access the data through identifier (key), which is largely the same way we use dictionary literals in the real world.

Dictionary keys can only use `number` and` text` types.
### Definition
Similar to arrays, dictionaries also use the `[]` definition, except that the array type is a combination of `key` and` value`, separated by `:`.

E.g:

    dic => ["a": 1, "b": 2, "c": 3];

This will create a `text: number` type dictionary containing` a, b, c` entries.

If you need a clear dictionary of empty dictionaries, you can also create it using the type-creation syntax.

E.g:

    dicNumNum => [number: number]~();

### Visit
Like an array, we can also use indexes to access data directly.

E.g:

    Console.WriteLine(value: dic["a"]);

### Change the element
Like arrays, we can also use assignment statements to change to elements.

E.g:

    dic["b"] = 5;
    
The difference is that with the array, if the assignment is a non-existent index, it will not be wrong, the value will be given directly to the new key.
### Common operation

    dic.Add(key: "d", value: 11); // add index by method
    dic.Remove(key: "c");  // delete the specified index element
    length => dic.Count; // length

### [Next Chapter](judgment.md)
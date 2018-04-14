# Control Type
The control type is a block of code that encapsulates data operations.

Usually we will encapsulate some data control processes into control types so that there is no need to perform additional methods when using data.

## Simple Definition
If we don't need to define a specific control method for a while, we only need to use `^Type` to define a control type.

E.g:
```
Number : ^i32;
```
This defines a control data with no extra methods. It is similar to `number : 0;` except that it has built-in default control methods and is initialized to null.

We can use it directly like normal data.

## Get Operation
If we want to set a fetch operation, we can add extra code block definitions after the control type like a function.

E.g:
```
Number : ^i32
~get // means get, equivalent to getter in other languages
{
    -> (7); // only returns 7
};
```
In this way, number has a special method to get the value. When calling number, it will execute the internal logic.

Note that this control data has only one getter method, so it only supports the get operation and the caller cannot assign it.
## Set Operation
With the above example, we naturally can think of how to deal with set operations.

E.g:
```
Number : ^i32
...
~set // means set, equivalent to setter in other languages
{
    // ? ? ? Who should give the value? ? ?
};
```
Yes, this raises the question that control types are used to control operations and cannot be used to store data when implementing operations.
So we need to use another type of data to use the control type.

E.g:
```
_number : 0;

Number : ^i32
~set
{
    _number = value; // value represents the value of the input
};
```

Note that this control data has only one set method, then it only supports set operation, and the caller cannot get its value.

A complete example of reading and writing is as follows:
```
_number : 0;

Number : ^i32
~get
{
    -> (_number);
};
~set
{
    _number = value; // value represents the value of the input
};
```

Only when we need to implement the details of the operation need to deal with control data.

Most of the time, we can use only simple definitions to complete the task, because there is no special operation, so it built its own value without our extra processing.

### [Next Chapter](package-type.md)
# Control Type
The control type is a block of code that encapsulates data operations.

Usually we will encapsulate some data control processes into control types so that there is no need to perform additional methods when using data.

## Simple Definition
If we don't need to define a specific control method for a while, we only need to use `id():type` to define a control type.

E.g:
```
Number(): Int
```
This defines a control data with no additional methods, and it has a built-in default control method.

## Get Operation
If we want to set a get operation, we can add `-> ctrl{} ctrl{}` later to define.

E.g:
```
Number(): Int -> get {  # means get, equivalent to getter in other languages #
    <- (7)              # only returns 7 #
}
```
In this way, Number has a special method to get the value. When calling Number, it will execute the internal logic.

Note that this control data has only one getter method, so it only supports the get operation and the caller cannot assign it.
## Set Operation
With the above example, we naturally can think of how to deal with set operations.

E.g:
```
Number(): Int -> set {  # means set, equivalent to setter in other languages #
    # ? ? ? Who should give the value? ? ? #
}
```
Yes, this raises the question that control types are used to control operations and cannot be used to store data when implementing operations.
So we need to use another type of data to use the control type.

E.g:
```
_Number := 0

Number(): Int -> set {
    _Number = value  # value represents the value of the input #
}
```

A complete example of reading and writing is as follows:
```
_Number := 0

Number() :Int -> get {
    <- (_Number)
} set {
    _Number = value  # value represents the value of the input #
}
```

In particular, if we initialize `Number`, the compiler automatically generates the corresponding `_Number` private variable, and then we can omit the step of defining another variable.

E.g:
```
Number(): Int = 0 -> get {
    <- (_Number)
} set {
    _Number = value 
}
```

Only when we need to implement the details of the operation need to deal with control data.

Most of the time, we can use only simple definitions to complete the task, because there is no special operation, so it built its own value without our extra processing.

### [Next Chapter](protocol-type.md)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    Prt(A)
    C = 5
    Prt(C)
}

A(): Int -> get { 
    <- (3) 
}

B := 0
C(): Int -> get { 
    <- (B) 
} set { 
    B = value 
}
```
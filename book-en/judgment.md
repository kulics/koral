# Judgment
The judgment statement executes the program by setting one or more conditions, executes the specified statement if the condition is True, and executes the otherwise specified statement if the condition is False.

We only need to use the `? value {}` to declare the judgment statement, according to the following value into the corresponding area.

E.g:
```
? True {
    Prt("True")  # true
}
```
# Boolean Judgment
When the judgment value is only `Bl`, the statement is executed only if it is `True`. 
If we need to deal with other situations at the same time, we can continue to declare another processing statement after using `value {}`.
If you only need `False`, use `_ {}` to declare it.

E.g:
```
b := False
? b {
    ...... # since b is False, it will never enter this branch
} _ {
    ...... # handle False
}
```

We can also insert more judgments in the middle, and the language will automatically implement them as continuous processing.

E.g:
```
i := 3
? i == 0 {
    ......
} i == 1 {
    ......
} i == 2 {
    ......
}
```

This can be considered as an `if elseif else` structure relative to other languages.
# Condition Judgment
If we need to judge an identifier, we can use the `? value -> case {}` statement, the statement implements multiple conditional matching, and the matching condition is used to execute the corresponding logic, so that it will only execute the statement with successful matching.

E.g:
```
? i -> 1 {
    ......
} 2 {
    ......
}
```
This kind of condition judgment is very suitable for the multi-condition judgment of a certain identifier, and avoids writing too many judgment conditions.

Yes, just as the Boolean Judgment above, every condition here will be terminated when it is done and will not continue to execute.

### Default Condition
What if you need a default condition to execute logic? We can use an anonymous identifier `_` to accomplish this goal.

E.g:
```
? i -> 1 {
    ......
} 2 {
    ......
} _ {
    ......
}
```
In this case can not match, it will go to the default processing area to execute.

This can be thought of as the `switch case default` structure relative to other languages.

### Pattern Matching
Conditional judgment can do more, for example, we need to judge the type of the identifier,
You can use the `? value -> id:type{}` syntax to match types, `id` can be omitted.

E.g:
```
? x -> :I32 {       # When I32
     Prt("I32")
} content:Str {     # when Str
     Prt(content)
} Nil {             # When it is Nil
     Prt("Nil")
}
```
### Get type
If we need to explicitly get the type value, we can use the `?(id)` or `?(:type)` syntax to get it.

E.g:
```
?(expr)    # Get the expression type value
?(:type)   # Get the type value directly by type
```
### [Next Chapter](loop.md)

## Example of this chapter
```
\Demo <- {
    System
}

Main() -> () {
    a := 5
    ? a == 2 { 
        Prt(2) 
    } a == 4 { 
        Prt(4) 
    } _ { 
        Prt("not find") 
    }

    b := 7
    ? b -> 5 { 
        Prt(5) 
    } 7 { 
        Prt(7) 
    } _ { 
        Prt("not find") 
    }

    Prt( ?(b) )
    Prt( ?(:I32) )
}
```
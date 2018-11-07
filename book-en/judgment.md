# Judgment
The judgment statement executes the program by setting one or more conditions, executes the specified statement if the condition is true, and executes the otherwise specified statement if the condition is false.

We only need to use the `? value {}` to declare the judgment statement, according to the following value into the corresponding area.

E.g:
```
? true
{
    cmd.print.("true")  # true
}
```
# Boolean Judgment
When the judgment value is only `bl`, the statement is executed only if it is `true`. 
If we also need to handle `false` at the same time, then we can use the auxiliary notation `? value {}` to continue declare another statement.

E.g:
```
b := false
? b
{
    ... # since b is false, it will never enter this branch
}
?
{
    ... # handle false
}
```

We can also insert more judgments in the middle, and the language will automatically implement them as continuous processing.

E.g:
```
i := 3
? i == 0
{
    ...
}
? i == 1
{
    ...
}
? i == 2
{
    ...
}
```

If we have a special interrupt, we can add a clear `;` to the place where it is needed.

E.g:
```
? i == 0
{
     ...
};
? i == 1
{
     ...
}
```

This can be considered as an `if elseif else` structure relative to other languages.
# Condition Judgment
If we need to judge an identifier, we can use the `id.?{}` statement, the statement implements multiple conditional matching, and the matching condition is used to execute the corresponding logic, so that it will only execute the statement with successful matching.

E.g:
```
i.? 1
{
    ...
}
2
{
    ...
}
```
This kind of condition judgment is very suitable for the multi-condition judgment of a certain identifier, and avoids writing too many judgment conditions.

Yes, just as the Boolean Judgment above, every condition here will be terminated when it is done and will not continue to execute.

### Default Condition
What if you need a default condition to execute logic? We can use an anonymous identifier `_` to accomplish this goal.

E.g:
```
i.? 1
{
    ...
}
2
{
    ...
}
_
{
    ...
}
```
In this case can not match, it will go to the default processing area to execute.

This can be thought of as the `switch case default` structure relative to other languages.

### Pattern Matching
Conditional judgment can do more, for example, we need to judge the type of the identifier,
You can use the `value.?id:type{}` syntax to match types, `id` can be omitted, and the default is `it`.

E.g:
```
x.?
:i32 # When i32
{
     cmd.print.(it)
}
content:str # when str
{
     cmd.print.(content)
}
null # When it is null
{
     cmd.print.("null")
}
```
### Get type
If we need to explicitly get the type value, we can use the `?.(id)` or `?.(:type)` syntax to get it.

E.g:
```
?.(expr)    # Get the expression type value
?.(:type)   # Get the type value directly by type
```
### [Next Chapter](loop.md)

## Example of this chapter
```
Demo
{
    System
    Library
}

main ()
{
    a := 5
    ? a == 2
    { cmd.print.(2) }
    ? a == 4
    { cmd.print.(4) }
    ?
    { cmd.print.("not find") }

    b := 7
    b.?
    5
    { cmd.print.(5) }
    7
    { cmd.print.(7) }
    _
    { cmd.print.("not find") }

    cmd.print.( ?.(b) )
    cmd.print.( ?.(:i32) )
}
```
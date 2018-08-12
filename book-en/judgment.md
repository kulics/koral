# Judgment
The judgment statement executes the program by setting one or more conditions, executes the specified statement if the condition is true, and executes the otherwise specified statement if the condition is false.

We only need to use the `? value {};` to declare the judgment statement, according to the following value into the corresponding area.

E.g:
```
? true
{
    Console.WriteLine.("true")  // true
}
```
# Boolean Judgment
When the judgment value is only `bool`, the statement is executed only if it is `true`. If we also need to handle `false` at the same time, then we can use the auxiliary notation `? value {}` To declare another statement.

E.g:
```
b := false
? b
{
    ... // since b is false, it will never enter this branch
}
?
{
    ... // handle false
}
```
As you may have noticed, yes, there is no `;` between `?` And `?`.

Looking back at our definition, any statement ends with `;`, so when it's not, it's not deemed to be over but will continue.

We only need to add `;` when we need to explicitly break.

This is a useful rule, and we can make a continuous judgment like this.

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
?
{
    ...
}
```
This can be considered as an `if elseif else` structure relative to other languages.
# Condition Judgment
If we need to judge an identifier, we can use the `id.?{};` statement, the statement implements multiple conditional matching, and the matching condition is used to execute the corresponding logic, so that it will only execute the statement with successful matching.

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
You can use the `value.?id:type{};` syntax to match types, `id` can be omitted, and the default is `it`.

E.g:
```
x.?
:i32 // When i32
{
     Console.Write.(it)
}
content:str // when str
{
     Console.Write.(content)
}
null // When it is null
{
     Console.Write.("null")
}
```
### Get type
If we need to explicitly get the type value, we can use the `?.(id)` or `?.(:type)` syntax to get it.

E.g:
```
?.(expr)    // Get the expression type value
?.(:type)   // Get the type value directly by type
```
### [Next Chapter](loop.md)

## Example of this chapter
```
Demo
{
    .. System

    Main ()
    {
        a := 5
        ? a == 2
        { Console.WriteLine.(2) }
        ? a == 4
        { Console.WriteLine.(4) }
        ?
        { Console.WriteLine.("not find") }

        b := 7
        b.?
        5
        { Console.WriteLine.(5) }
        7
        { Console.WriteLine.(7) }
        _
        { Console.WriteLine.("not find") }

        Console.WriteLine.( ?.(b) )
        Console.WriteLine.( ?.(:i32) )
    }
}
```
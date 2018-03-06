# Judgment
The judgment statement executes the program by setting one or more conditions, executes the specified statement if the condition is true, and executes the otherwise specified statement if the condition is false.

We only need to use the `?` to declare the judgment statement, according to the following value into the corresponding area.

E.g:

    ? true
    {
        Console.WriteLine("true"); // true
    };

# Boolean Judgment
When the judgment value is only `bool`, the statement is executed only if it is `true`. If we also need to handle `false` at the same time, then we can use the auxiliary notation` ~? `To declare another statement.

E.g:

    b => false;
    ? b
    {
        ... // since b is false, it will never enter this branch
    }
    ~?
    {
        ... // handle false
    };

As you may have noticed, yes, there is no `;` between `?` And `~?`.

Looking back at our definition, any statement ends with `;`, so when it's not, it's not deemed to be over but will continue.

This is a useful rule, and we can make a continuous judgment like this.

E.g:

    i => 3;
    ? i = 0
    {
        ...
    }
    ? i = 1
    {
        ...
    }
    ? i = 2
    {
        ...
    }
    ~?
    {
        ...
    };

This can be considered as an `if elseif else` structure relative to other languages.
# Condition Judgment
When the judgment value is the other identified basic type (`text, number`), the statement can enter the inner multi-condition matching, we can use the auxiliary symbol `~` to match the conditions to perform the corresponding logic, so it will only execute the statement that matched successfully.

E.g:

    ? i ~ 1
    {
        ...
    }
    ~ 2
    {
        ...
    };


This kind of condition judgment is very suitable for the multi-condition judgment of a certain identifier, and avoids writing too many judgment conditions.

Yes, just as the Boolean Judgment above, every condition here will be terminated when it is done and will not continue to execute.

### Default Condition
What if you need a default condition to execute logic? We can use an anonymous identifier to accomplish this goal.

E.g:

    ? i ~ 1
    {
        ...
    }
    ~ 2
    {
        ...
    }
    ~ _
    {
        ...
    };

In this case can not match, it will go to the default processing area to execute.

This can be thought of as the `switch case default` structure relative to other languages.

### [Next Chapter](loop.md)
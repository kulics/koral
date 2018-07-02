# Check
The program may experience a variety of exceptions.

- May be the result of a file or user input.
- May be encoding errors or missing features in the language.
- Of course, it may be due to many other unpredictable factors.

Abnormal can not be completely avoided, but we can choose some means to help us to check and report anomalies.

## Report Exception
We can declare an exception data using `!~` Anywhere in the function.

E.g:
```
ReadFile : $(name: str)->()
{
    ? name.Length == 0
    {
        !~ #Exception.("something wrong");
    };
};
```
So we declare an exception, the exception is `something wrong`, and once an external caller has used a `name` of an invalid length, the exception is reported up until it is processed or ignored.
## Check Exception
We can use the `!` And the auxiliary symbol `~` to check for blocks that may be abnormal when the function is called.

E.g:
```
!
{
    ReadFile.("temp.txt");
}
~ err
{
    Console.WriteLine.(err.message);
};
```
Here, the `!` Block represents all the functional logic under inspection, `~ err` means that the erroneous data is defined as the identifier `err`, which acts like a in parameter.

Once an exception occurs in the read file function, `err` is checked and the print function is executed. If not, everything is normal and does not go into the exception handling section.

Similarly, the check logic is also inside the function, so if there is an exception that can not be handled, you can continue to report it up.

E.g:
```
...
~ err
{
    !~ err;
};
```
So how do we distinguish between different types of anomalies?

Very simple, we can specify the type after the identifier.

E.g:
```
~ e : IOException
{
    ...
};
```

## Check Defer
If we have a function that we hope can be handled regardless of whether the program is normal or abnormal, such as the release of critical resources, we can use the check defer feature.

Quite simply, using `~!` can declare a statement that checks the delay.

E.g:
```
Func : $()->()
{
    File : ReadFile.("./somecode.xy");
    ~!
    {
        file.Release.();
    };
    ...
};
```
So we declare the `file.Release.();` statement that releases the file. This statement will not be executed immediately, but will wait for the function to be called before exiting.

With check defer, we can safely handle certain tasks without having to worry about how the function exits.

Note that because the check defer is performed before the function exits and the execution state of the program is abnormal or not, the check statement cannot use the return statement.

E.g:
```
...
~!
{
    file.Release.();
    <- (); // error, cannot use return statement
};
```

### Check Defer Order
In particular, if more than one `~!` is used in a statement block, the final execution is to execute the statements in `~!` one by one in reverse order. This is because `~!` is always executed at the end, so the first declaration is executed last, so multiple `~!` will be executed in reverse order of the declaration.

E.g:
```
~! { Console.WriteLine.("1"); };
~! { Console.WriteLine.("2"); };
~! { Console.WriteLine.("3"); };

// final display 3 2 1
```

### Checking Defer Scope
The effective scope of the check delay is only the current one-level statement block, which is very helpful for us to control the execution area.

E.g:
```
Func : $()->()
{
    ...
    @ [0~5] ~ index
    {
        // does not affect the logic outside the loop
        ~! { Console.WriteLine.(index + 1); };
        Console.WriteLine.(index);
    };
    ...
};
```

### [Next Chapter](asynchronous.md)

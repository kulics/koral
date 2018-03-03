# Check
The program may experience a variety of exceptions.

- May be the result of a file or user input.
- May be encoding errors or missing features in the language.
- Of course, it may be due to many other unpredictable factors.

Abnormal can not be completely avoided, but we can choose some means to help us to check and report anomalies.

## Report Exception
We can declare an exception data using `~!` Anywhere in the function.

E.g:

    ReadFile => $(name: text)~()
    {
        ? name.Length == 0
        {
            ~! Exception~(message: "something wrong");
        };
    };

So we declare an exception, the exception is `something wrong`, and once an external caller has used a `name` of an invalid length, the exception is reported up until it is processed or ignored.
## Check Exception
We can use the `!` And the auxiliary symbol `~` to check for blocks that may be abnormal when the function is called.

E.g:

    !
    {
        ReadFile(name: "temp.txt");
    }
    ~ err
    {
        Console.WriteLine(value: err.message);
    };

Here, the `!` Block represents all the functional logic under inspection, `~ err` means that the erroneous data is defined as the identifier `err`, which acts like a in parameter.

Once an exception occurs in the read file function, `err` is checked and the print function is executed. If not, everything is normal and does not go into the exception handling section.

Similarly, the check logic is also inside the function, so if there is an exception that can not be handled, you can continue to report it up.

E.g:

    ...
    ~ err
    {
        ~! err;
    };

So how do we distinguish between different types of anomalies?

Very simple, we have got the error, so at any time through the type of judgment to deal with.

E.g:

    ~ e
    {
        ? e ?: Exception
        {
            ...
        };
    };

More complicated to use sub-conditional judgment statement to continue processing.

### [Next Chapter](asynchronous.md)

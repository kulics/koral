# Check
The program may experience a variety of exceptions.

- May be the result of a file or user input.
- May be encoding errors or missing features in the language.
- Of course, it may be due to many other unpredictable factors.

Abnormal can not be completely avoided, but we can choose some means to help us to check and report anomalies.

## Report Exception
We can declare an exception data using `!.()` Anywhere in the function.

E.g:
```
readFile (name: str)->()
{
    ? name.Length == 0
    {
        !.( Exception.{"something wrong"} )
    }
    ...
}
```
So we declare an exception, the exception description is `something wrong`, once the external caller uses the illegal length of `name`, the function will be forced to abort, report the exception up and hand it to the caller.
## Check Exception
We can use the `.! id:type {}` statement to check for exceptions when using assignment statements or expression statements.
`id` can be omitted, the default is `it`.
`:type` can also be omitted, the default is `Exception`.

E.g:
```
f: file = readFile.("temp.txt").! err: Exception
{
    cmd.print.(err.message)
}
```
When an exception occurs, the program enters the `!` block, and `err` is the exception identifier. We can get the exception information or perform other operations.

If there are no exceptions, the logic of the exception handling block will not be entered.

In general, we can make early returns or data processing in exception handling. If there are exceptions that cannot be handled, we can continue to report upwards.

E.g:
```
Func.().! {
     // can be returned manually
     // <- ()
     !.(it)
}
```
## Fragment
If we come across something that always needs to be declared repeatedly, such as a continuous check, it always returns the same content.

E.g:
```
Do1.().! {
    Log.(it.msg)
    !.(it)
}
Do2.().! {
    Log.(it.msg)
    !.(it)
}
Do3.().! {
    Log.(it.msg)
    !.(it)
}
```

This way of writing is very tedious and worthless.

We can use fragment statements to optimize this content, using `id () -> {}` to declare the fragment statement, the preceding parentheses are arguments.

E.g:
```
checkError (it:Exception) ->
{
    Log.(it.msg)
    !.(it)
}
```

Declaring a fragment statement does not produce any code. The fragment statement is only populated into the location when it is called, which is equivalent to automating the generation of code, which is different from the function.

Use `-> id` to use the fragment statement, now we can handle the above example.

E.g:
```
Do1.().! -> checkError
Do2.().! -> checkError
Do3.().! -> checkError
```

This seems to be much easier.

Fragment statements can greatly reduce the amount of rewritten code, making our work easier, not only for handling errors, but also for general logic.

E.g:
```
a := 0
Handle () ->
{
    a *= a
    cmd.print.(a)
}
a += 1
-> Handle
a += 5
-> Handle
a += 7
-> Handle
```

## Check Defer
If we have a function that we hope can be handled regardless of whether the program is normal or abnormal, such as the release of critical resources, we can use the check defer feature.

Quite simply, using `! {}` can declare a statement that checks the delay.

E.g:
```
Func ()->()
{
    File := readFile.("./somecode.xy")
    !
    {
        file.release.()
    }
    ...
}
```
So we declare the `file.release.()` statement that releases the file. This statement will not be executed immediately, but will wait for the function to be called before exiting.

With check defer, we can safely handle certain tasks without having to worry about how the function exits.

Note that because the check defer is performed before the function exits and the execution state of the program is abnormal or not, the check statement cannot use the return statement.

E.g:
```
...
!
{
    file.release.()
    <- ()    // error, cannot use return statement
}
```

### Check Defer Order
In particular, if multiple deferred statements are used in a single statement block, the final execution is performed one by one in reverse order. This is because the deferred statements are all executed last, so the first declaration will be executed last, so multiple deferred statements will be executed in the reverse order of the declaration.

E.g:
```
! { cmd.print.("1") }
! { cmd.print.("2") }
! { cmd.print.("3") }

// final display 3 2 1
```

### Checking Defer Scope
The effective scope of the check delay is only the current one-level statement block, which is very helpful for us to control the execution area.

E.g:
```
Func ()->()
{
    ...
    [0<<5].@
    {
        // does not affect the logic outside the loop
        ! { cmd.print.(it + 1) }
        cmd.print.(it)
    }
    ...
}
```

### Automatic release
For packages that implement the automatic release protocol, we can use the '!= ' syntax to define variables so that they are automatically released when the function completes.

E.g:
``` 
Res != fileResource.{ "/test.xy"}
...
```

### [Next Chapter](asynchronous.md)

## Example of this chapter
```
Demo
{
    .. System, XyLang\Library

    main ()
    {
        x: i32 = (1 * 1).! err 
        {
            !.(err)
        }

        x != Defer.{}
        !
        {
            x.content = "defer"
            cmd.print.(x.content)
        }
    }

    Defer {} ->
    {
        content :str
    }

    Defer += IDisposable
    {
        Dispose ()->()
        {
            ..content = null
        }
    }
}
```
# Check
The program may experience a variety of exceptions.

- May be the result of a file or user input.
- May be encoding errors or missing features in the language.
- Of course, it may be due to many other unpredictable factors.

Abnormal can not be completely avoided, but we can choose some means to help us to check and report anomalies.

## Report Exception
We can declare an exception data using `!()` Anywhere in the function.

E.g:
```
readFile(name: str) -> () {
    ? name.len == 0 {
        !( Exception("something wrong") )
    }
    todo("...")
}
```
So we declare an exception, the exception description is `something wrong`, once the external caller uses the illegal length of `name`, the function will be forced to abort, report the exception up and hand it to the caller.
## Check Exception
We can use the `! {}` statement to check for exceptions and `id:type {}` to handle exceptions.  
`:type` can be omitted, the default is `Exception`.  

E.g:
```
! {
    f := readFile("temp.txt")
} ex:IOException {
    !(ex)
} e {
    prt(e.message)
}
```
When an exception occurs, the program enters the error process block, and `e` is the exception identifier. We can get the exception information or perform other operations.

If there are no exceptions, the logic of the exception handling block will not be entered.

In general, we can make early returns or data processing in exception handling. If there are exceptions that cannot be handled, we can continue to report upwards.

E.g:
```
! {
    Func()
} ex {
     # can be returned manually
     # <- ()
     !(ex)
}
```

## Check Defer
If we have a function that we hope can be handled regardless of whether the program is normal or abnormal, such as the release of critical resources, we can use the check defer feature.

Quite simply, using `_ {}` at the end of the check can declare a statement that checks for delays.

E.g:
```
func() -> () {
    File: file
    ! {
        File = readFile("./somecode.xs")
    } _ {
        ? File ~= nil {
            File.release()
        }
    }
    todo("...")
}
```
So we declare the `File.release()` statement that releases the file. This statement will not be executed immediately, but will wait for the function to be called before exiting.

With check defer, we can safely handle certain tasks without having to worry about how the function exits.

Note that because the check defer is performed before the function exits and the execution state of the program is abnormal or not, the check statement cannot use the return statement.

E.g:
```
todo("...")
_ {
    File.release()
    <- ()    # error, cannot use return statement
}
```

### Automatic release
For packages that implement the automatic release protocol, we can use the '!= ' syntax to define variables so that they are automatically released when the function completes.

E.g:
``` 
! res := FileResource("/test.xs") {
    todo("...")
}
todo("...")
```

### [Next Chapter](asynchronous.md)

## Example of this chapter
```
\Demo <- {
    System
}

example -> {
    Main() -> () {
        ! {
            x: i32 = (1 * 1)
        } ex {
            !(ex)
        }

        x := Defer()
        ! y := Defer() {
            x.content = "defer"
            prt(x.content)
        } e:Exception {
            !(e)
        } _ {
            ? x ~= nil {
                x.Dispose()
            }
        }
    }
}

Defer() -> {
    content: str
} IDisposable {
    Dispose() -> () {
        ..content = ""
    }
}
```
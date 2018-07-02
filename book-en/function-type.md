# Function Type
Function is a separate piece of code used to accomplish a specific task.

Often we will package a series of tasks that need to be reused as functions for reuse elsewhere.

In practical engineering practice, given a definite input, the function that will surely return exactly to the output is considered to be a better design. Therefore, it is recommended to maintain functional independence as much as possible.
## Definition
Before we have seen the main entrance function, it is only defined using the symbol `$`.

The main entry function is a special case, in fact, the conventional functions of this language must explicitly declare the identifier, in parameters and out parameters.

We only need to use `$()->()` to define a function, the first parenthesis is in parameters, the second parenthesis is out parameters.

E.g:
```
function : $()->()
{
    ...
};
```
This defines a function with the identifier `function`.

Note that the function can be defined in the package and protocol, you can also define inside the function. When you define a function in a function, the intrinsic does not have a public property and belongs only to the private function of the current function.
## Call
Unlike the main entrance function can not be called, conventional functions can be used to call identifier, we only need to add `.()` behind the identifier can use the function.

E.g:
```
function.(); // call function
```
## Parameter
Although functions can perform specific functions without any parameters, more often we need to be able to accept some input data, or to return data, or both, which requires parameters to help us accomplish task.

Very simple, we only need to use `identifier: type` declare the parameters.

E.g:
```
func : $(x: i32)->(y: i32)
{
    <- (x * x);
};
```
The meaning of this function is to accept an input `i32` parameter `x` and a `i32` parameter `y`.

This is very similar to what? Yes, in fact, the parameters and dictionary functions are almost the same, the parameters just tell the function, we need to use this type of data, marked by the identifier to match. Therefore, the expression of the same parameters and dictionaries will help us to understand.

The first parentheses is the in parameter, the second parenthesis is the out parameter. There is no limit to the number of parameters in brackets, but there are strict requirements on the order and type.
### Return
Here, even if you do not know, roughly you can guess that `<-` should be a return-related statement.

Yes, we only need to use `<-` can specify a clear return statement, the return of the brackets can be filled in need to return the data, separated by commas.

E.g:
```
<- (1, 2, 3, "Hello");
```
This will return `1, 2, 3, 'Hello'` four values.

And we call the same method expression, we also need to use the full brackets to express a return statement, even if the function does not need to return any data.

E.g:
```
<- ();
```
The purpose of such a design in order to maintain the integrity of the grammar.

But if it is a function that does not require a return value, the language will automatically add the exit to the end of the function, so we can optionally omit some of the return statements.

We can terminate the function early using the return statement anywhere within the function, which satisfies our logic control needs.

Note that, as with the loop out, the return statement will only be absent from the nearest layer of function.
### In Parameters
We call the parameters which enter the function In Parameters, In Parameters can be none or multiple, there is no restriction on the type and identifier.

When we call the function, we need to fill the brackets with the identifier in the order we defined it. When the order, identifier or type does not match, will be treated as wrong.

E.g:
```
sell : $(price: i32, name: str)->(){}; 
// define one function with two in parameter

sell.(1.99, "cola"); 
// fill in the data that meets the requirements as defined
```
### Out Parameters
Similar to in parameters, out parameters also need to be clearly defined with an identifier, which makes it easier for callers to access the function's role information.

E.g:
```
topSell : $()->(name: str, count: i32)
{
    ...
    <- ("cola", many);
};
```
### The use of the return
So how do we get the return value of a function?

Very simple, just like we do addition, subtraction, multiplication and division to use the same function.

The difference is that for multiple return values ​​we have to wrap each identifier in parentheses like a parameter.

E.g:
```
(n, c) : topSell.(); 
// define the returned two values ​​for n and c
(n, c) = topSell.(); 
// overrides the returned two values ​​to n and c
```
You can use the definition or assignment statement to get the return value of the function to use, you can also use the nested function to another function.

E.g:
```
Console.WriteLine.(topSell.()); // print two values
```
If there is only one return value, the brackets can be taken without.

Note that if you call a function with a return value is not allowed to not receive the return value, because this often leads to accidental negligence lost important data.

E.g:
```
topSell.(); // error, did not explicitly receive the return value
```
But sometimes, as a caller, we do not necessarily need all the return values, but this time we can use the anonymous identifier `_` to help us drop the data. Just need to write it in the corresponding position.

E.g:
```
name, _ : topSell.();
```
If indeed all the return values ​​are not needed, we can also just write a `_` to discard all. But why would need to call such a function? Maybe we should review the code again.

E.g:
```
_ = topSell.(); // for _ , assignment and definition are equivalent
```
## Function In Parameter
If we want part of the function defined by the external, and only perform the rest of the internal logic, such as some set traversal for a collection of functions, then we can use the function parameters to accomplish this goal.

Function In Parameter no special definition of way, just replace the type of the function parameters, do not need to define the contents of the function.

E.g:
```
each1To10 : $(func: $(item: i32)->())->()
{
    @ [1~10] ~ i
    {
        func.(i);
    };
};
```
We define a function named `func`, whose type is a function of only `item`.

So that we can pass the details of the processing to the externally passed `func`.

E.g:
```
print : $(item: i32)->()
{
    Console.WriteLine.(item);
};

each1To10.(print);
```
So, we executed the `print` function in the loop inside `each1To10`.

Function In Parameter only require the same type of function parameters, do not require the same name of the parameters.

## Lambda Expression
As the above way to define a function and then imported into use sometimes appear more verbose, because we just want to perform a little function only, not necessarily to define a function to provide to other places to use.

At this point we can use the syntax of Lambda Expression to reduce the pain of our naming.

Because function arguments are already defined at the time of declaration, we can use simplified syntax `$ <-` to express them, which means define the input parameter identifier and return an expression directly.

E.g:
```
each1To10.( $item <- Console.WriteLine.(item) );
findAll.( $it <- it>7 );
order.( $it <- it.time );
```
Very simple, and the difference between the expression of the function type is that the input only need to declare the identifier, and the parameter is used to include one expression.
## Lambda Function
Unlike the above simplified method, we can also write a complete function directly, just as we define the function.

E.g:
```
each1To10.( $(item:i32)->()
{
     Console.WriteLine.(item);
});
```
### [Next Chapter](control-type.md)
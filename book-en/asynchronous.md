# Asynchronous
Thread is defined as the execution path of the program. Each thread defines a unique control flow. If your application involves complex and time-consuming operations, setting different thread execution paths is often beneficial, with each thread performing a specific job.

Because computer processors have computational bottlenecks, we can not get everything going in a single-line-by-line fashion, and we often need to use asynchronous parallelism to solve computational problems in order to increase processing capacity.

.Net platform has its own thread library `System\Threading`, more about the use of the thread can query the relevant interface.

Here we talk about how to deal with the thread more easily, that is, asynchronous processing.

In other languages ​​it can be considered `async/await` for asynchronous programming end-solutions.

The task data type we use here is `tsk`.
## Asynchronous Declaration
So how to declare a function asynchronously? Use `~>` on it.

That's right, it's really use `~>` on it.

E.g:
```
async ()~>(out: i32) {
    <- (12)
}
```
Once a method has been declared as an async method, the compiler will automatically put a `tsk<>` wrapper around the return value, and the method will be executed asynchronously.

Normal direct call will only get a `tsk` data.

E.g:
```
result := async.()   # result is a Task data
```
Let's see how to make it asynchronously waiting for execution.
## Asynchronous Wait
As with the declaration, we only need to use `<~ function.()` to declare the wait asynchronous function.

E.g:
```
result := <~ async.()
...
```
After declare, the program execution here will temporarily stop the back of the function, until the async function is completed, the `out` value assigned to` result`, and then continue to execute.
## Asynchronous Use Conditions
Asynchronous wait can only be used in asynchronous declared functions.

E.g:
```
# correct
async ()~>(out: i32) {
    <~ tsks.delay.(5000)     # wait for a while
    <- (12)
}
# wrong
async ()->(out: i32) {
    <~ tsks.delay.(5000)     # can not be declared
    <- (12)
}
```
## Empty return value
If the asynchronous function does not return a value, it will also return a `tsk` data, the same as the external call can wait.

We can choose to wait for no data, or we can choose not to wait for data.

E.g:
```
async ()~>() {
    <~ tsks.delay.(5000)    # wait for a while
}

<~ async.()  # correct

task := async.()    # correct, got the Task
```
## Lambda
For lambda, we can also use asynchronous, just use `~>`.

E.g:
```
_ = arr.filter.( $it ~> it > 5)
```
### [Next Chapter](generic.md)
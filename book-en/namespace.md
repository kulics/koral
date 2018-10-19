# Namespace
Namespace are designed to provide a way to separate a set of names from other names. The names declared in one namespace do not conflict with the names declared in another namespace.

## Export
To make it easier for us to manage the code, we must write our code in a namespace. We can expose it to external use through public attributes, or use private attributes to complete only our own business.

Exported names can be nested in a loop so that functions can be split as effectively as folders, multiple namespaces need to be separated by `\`.

E.g:
```
name\space{}

getSomething ()->(content:str)
{
    <- ("something")
}
```
## Import
We can use other namespace contents through the import function. The namespace content can be called directly after import.

It should be noted that the top-level function, the top-level variable, and the top-level constant will be installed as an object with the current file name as the host container.
So by default you need to use a filename to access across the namespace, where the file name is `Demo`.

E.g:
```
run { name\space }

main ()
{
    # 打印 something
    cmd.print.( Demo.getSomething.() )
}
```

If we need to specify the name of the host container, we can specify it using `=name`.

E.g:
```
name\space=helper {}

getSomething ()->(content:str)
{
    <- ("something")
}

------------------------

run{ name\space }

main ()
{
    cmd.print.( helper.getSomething.() )
}
```
## Simplify Import
If we don't want to use the namespace name to call the content every time, we can use the simplified syntax to add `.LastName` to the import.

E.g:
```
run{ name\space.Demo }

main ()
{
    # 打印 something
    cmd.print.( getSomething.() )
}
```
This eliminates the need to call `space` every time.
## Temporary Import
We can use the namespace directly to call function without importing it.

E.g:
```
demo {}

main ()
{
    # 直接使用即可
    cmd.print.( \name\space.Demo.getSomething.() )    
}
```

## [Complete Example](../example.xy)
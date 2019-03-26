# Namespace
Namespace are designed to provide a way to separate a set of names from other names. The names declared in one namespace do not conflict with the names declared in another namespace.

## Export
To make it easier for us to manage the code, we must write our code in a namespace. We can expose it to external use through public attributes, or use private attributes to complete only our own business.

Exported names can be nested in a loop so that functions can be split as effectively as folders, multiple namespaces need to be separated by `\`.

E.g:
```
\Name\Space <- {}

Demo -> {
    GetSomething() -> (content: Str) {
        <- ("something")
    }
}
```
## Import
We can use other namespace contents through the import function. The namespace content can be called directly after import.


E.g:
```
\Run <- { 
    Name\Space 
}

Example -> {
    Main() -> () {
        # print something
        Prt( Demo.GetSomething() )
    }
}
```
## Simplify Import
If we don't want to use the namespace name to call the content every time, we can use the simplified syntax to add `.LastName` to the import.

E.g:
```
\Run <- { 
    Name\Space.Demo 
}

Example -> {
    Main() -> () {
        # print something
        Prt( GetSomething() )
    }
}
```
This eliminates the need to call `space` every time.
## Temporary Import
We can use the namespace directly to call function without importing it.

E.g:
```
\Demo <- {}

Example -> {
    Main() -> () {
        # use it directly
        Prt( \Name\Space.Demo.GetSomething() )    
    }
}
```

## [Advanced](./control-type.md)
## [Back to index](./introduction.md)
## [Complete Example](../example.xs)
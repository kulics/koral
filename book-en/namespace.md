# Namespace
Namespace are designed to provide a way to separate a set of names from other names. The names declared in one namespace do not conflict with the names declared in another namespace.

## Export
To make it easier for us to manage the code, we must write our code in a namespace. We can expose it to external use through public attributes, or use private attributes to complete only our own business.

Exported names can be nested in a loop so that functions can be split as effectively as folders.

E.g:
```
:> name.space
{
    GetSomething => $()~(content:str)
    {
        -> ("something");
    };
};
```
## Import
We can use other namespace contents through the import function. After importing, we need to use the name of the end of the namespace to invoke these contents.

E.g:
```
:> import
{
    <:
    {
        name.space;
    };

    $
    {
        // print something
        Console.WriteLine( space.GetSomething() );
    };
};
```
## Simplify Import
If we don't want to use namespace names every time we call content, we can use a simplified syntax, adding `..` when importing.

E.g:
```
:> import
{
    <:
    {
        .. name.space;
    };

    $
    {
        // print something
        Console.WriteLine( GetSomething() );
    };
};
```
This eliminates the need to call `space` every time.
## .NET Import
For .NET namespaces, just use our normal import syntax.

The difference is that .NET content we do not need to use the namespace name to call the content.

E.g:
```
:> demo
{
    <:
    {
        System;
    };

    $
    {
        System.Console.WriteLine(""); // don't need System

        Console.WriteLine(""); // can be used directly
    };
};
```
## .NET Export
Sometimes we need to use the .NET native namespace mechanism to use some features, such as the use of XAML. Our language features may have some limitations that prevent us from simply using them.

We can use a special export method to declare the native namespace method. Just change `:>` to `#>`.

It should be noted that this export method internally only supports defining packages and protocols.

E.g:
```
#> Pages
{
    <:
    {
        ...
    };

    PageDemo => #~()
    {
        ...
    };
};
```
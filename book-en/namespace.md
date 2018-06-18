# Namespace
Namespace are designed to provide a way to separate a set of names from other names. The names declared in one namespace do not conflict with the names declared in another namespace.

## Export
To make it easier for us to manage the code, we must write our code in a namespace. We can expose it to external use through public attributes, or use private attributes to complete only our own business.

Exported names can be nested in a loop so that functions can be split as effectively as folders, multiple namespaces need to be separated by `\`.

E.g:
```
name\space :
{
    space : #
    {
        GetSomething : $()~(content:str)
        {
            -> ("something");
        };
    };
};
```
## Import
We can use other namespace contents through the import function. The namespace content can be called directly after import.

E.g:
```
import :
~name\space
{
    $
    {
        // print something
        Console.WriteLine.( space.GetSomething.() );
    };
};
```
## Simplify Import
If we don't want to use no construct package names every time we call content, we can use a simplified syntax, adding `..` when importing.

E.g:
```
import :
~..name\space.space
{
    $
    {
        // print something
        Console.WriteLine.( GetSomething.() );
    };
};
```
This eliminates the need to call `space` every time.
## Temporary Import
We can use the namespace directly to call function without importing it.

E.g:
```
demo :
{
    $
    {
        \System.Console.WriteLine.(""); // can be used directly
    };
};
```
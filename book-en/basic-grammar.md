# Basic Grammar
## Basic Statement
In this language, any expression must be attributed to the statement.

The basic form of the statement is:
```
StatementContent;
```
A statement must be terminated by a distinct `;` and often `{}` is used to wrap the contents of a qualified statement.
## Export Namespace
All content in this language can only be defined in the namespace so that content can be efficiently divided into distinct blocks for management. You can define it freely in a separate namespace without undue restrictions on naming.

We can use the `:` statement to define a region's namespace.

E.g:
```
Demo :
{
    ...
};
```
The meaning of this statement is the contents of `{}` will be marked `Demo` in the namespace, so the content naming is limited to the area without having to consider naming conflicts outside the area.

At the same time the external area can import `Demo` to use the contents of which, we will then understand how to import.

Note that only the main entry, package, and protocol statements are supported in the namespace, and these identifiers must be public.
## Import Namespace
We can use the `~` statement to import other namespaces, libraries, frameworks into a namespace.

E.g:
```
Demo :
~System
~System\Collections\Generic
{
};
```
This imports the `System` and` Generic` libraries into the `Demo` namespace, and then you can use them in the program.

Within before braces, you can write multiple import statements whose order does not affect the import functionality.
## Main Entry
We need to define a main entry to let the program know where to start. The main entry through a fixed single symbol `$` statement, and must be valid at the top of the namespace.

E.g:
```
Demo :
~System
~System\Collections\Generic
{
    $
    {
        ...
    };
};
```
The main entry function here is defined at the top of the namespace and is a function with no arguments and no return value. It is automatically recognized as the main entry and the main entry function is executed when the program is started, so we simply write the function main entry function can be.

In the examples that follow, we are by default implemented in the main entry function, so we will not overplay this part of the code.

In particular, there can be only one main entry function in a namespace because the entry must be unique.

More details about the function will be explained in later chapters.

As you may have noticed, in this language, you often start with the symbol, wrap the content with `{}`, and use `;` to end the statement, which is a very important expression of the language that unifies the expression of the statement, In most cases you only need one of the distinguished symbols to complete the parsing and writing of statements.
## Display information
We use the program in order to obtain some useful information, so we need a feature to browse information, this feature can be display, print or output.

If we write a console program, we can use .Net built-in `Console.WriteLine.()` function, it can display data or text information to the console for us to browse.

E.g:
```
Console.WriteLine.("Hello world"); // output Hello world
```
In the following examples, we will all use the console as a presentation environment.
## Comment
Our comments are very similar to the C language, with single-line comment starting with two backslashes `//`:
```
// single-line comment
```
Block comment begin with `/ *` and end with `* /`:
```
/ * multi-line
comment * /
```
Comment do not belong to the statement, so do not need to end with `;`, comment is only used to provide additional information to the user, and will not be really compiled into the executable program.
## Definition
We can bind the type or data to the specified name using the `:` statement.

E.g:
```
a : 1;
```
This creates an identifier for the name on the left and assigns the data on the right to it. In most cases, we do not need to explicitly specify the type of data, and the compiler automatically deduces the type for the data.

Once an identifier is created, its data type will not be changed in the valid area.

## Assignment
Like a normal programming language, we need to use the `=` statement to assign the data on the right to the identifier on the left.

E.g:
```
a = 2;
```
But the definition is not the same, the left side of the assignment can only be an identifier that has been defined, otherwise the assignment statement does not hold.
## Variable data
We can define variable data very easily, and types that are not marked with special symbols are variable data.

E.g:
```
i : 1; 
```

It should be noted that variable data cannot be called externally and can only be used within a defined range. Can be considered private.

## Invariable data
We can also define invariable data, just define it with `:=`.

E.g:
```
j := 2; 
```

Note that invariable data can only be defined within the package without initial.
## Identifier
Identifier is the variable, function, package, protocol, etc. specified name. The letters that make up the identifier all have a certain norm, and the naming convention of the identifier in this language is as follows:

1. Case sensitive, Myname and myname are two different identifiers;
1. The first character of an identifier can start with an underscore (_) or a letter, but it can not be a number;
1. Other characters in the identifier can be underlined (_), letters, or numbers.
1. Within the same `{}`, you can not define more than two identifiers of the same name.
1. In different `{}`, you can define the identifier of the duplicate name, the language will give priority to the identifier defined in the current range.

In particular, in packages and protocols, properties and method names that begin with the underscore (_) are considered private and the rest are considered public.
## Keyword
none.

Yes, you are not mistaken, we do not have keywords. So you can use any character as your identifier, regardless of conflict issues.
## Space and Wrap
By default, both spaces and newlines are ignored by the compiler.

However, in practical projects, the use of partition will effectively improve the reading effect of the code, so we strongly recommend that you use the partition reasonably to improve the source code expression.

E.g:
```
a.b.(x,y).c.(fn:$()~(x:i32){->(2+1);}).d=1+3*5/4;

a.b.(x, y)
.c.(fn: $()~(x: i32)
{
    -> (2 + 1);
}).d = 1 + 3 * 5 / 4;
```
### [Next Chapter](basic-type.md)
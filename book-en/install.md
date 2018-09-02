# Install
Currently, `XyLang` only supports compilation to` C# `, so you need to have `.NET Core 2.x` installed on your system.

Executing `dotnet xylang.dll` will scan the` .xy` file in the current folder and will automatically translate it into a `.cs` file with the same name.

At this stage you need to create a separate `C#` project, to use `xy` for development.

After the iteration, we optimize the automated compilation to perform this part of the function, which may eventually be compiled directly into `CIL` and` LLVM` to generate direct binary executables.

In the future, we will provide executable packages that are compiled for different platforms. If you need them now, you can also use our existing projects to build your own.

It is now recommended to use the .NET Core runtime to use this language. For ease of use, you can create custom command line commands for use on your own system.

`XyLang` needs to use some of the language library features, so you need to refer to `XyLang.Library.dll` in your project to use the library.

Run Package:
<https://github.com/kulics/xylang/releases/tag/v0.18.2>

### [Next Chapter](basic-grammar.md)
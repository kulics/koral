# The XyLang Programming Language
XyLang is a concise open source .NET programming language. 

This is the main source code repository for XyLang. It contains the compiler, and documentation.

The language is designed to improve reading performance and reduce the grammatical burden so that users can focus their real attention on business needs.

Therefore, we abandon many subtle grammatical features, retaining only the most used part, and enhance its versatility.

Eventually making XyLang with very few grammar, only the presence of symbols on the keyboard instead of keywords is sufficient to express all the logic.

## Features
+ Focus on writing and reading.
+ Less grammar, no keywords.
+ Clear semantics, one logic corresponds to only one expression.
+ Support for compilation to .NET platform, with .NET framework and library resources, we can use this language in a very wide range of scenarios.

## Getting Started
Read detail from The [Book](./book-en/introduction.md).  
阅读 [语言说明文档](./book-zh/介绍.md)。

## Quick Preview
```
HelloWorld # export namespace
{
    System # import namespace
}

main () # main function  
{
    # list
    greetings := {"Hello", "Hola", "Bonjour",
                "Ciao", "こんにちは", "안녕하세요",
                "Cześć", "Olá", "Здравствуйте",
                "Chào bạn", "您好"}
                
    greetings.@ # for-each
    {
        cmd.print.(it) # call function
        # match
        it.? [ 0 <= 8 ] 
        {
            cmd.print.(" in 0-8 ")
        }
        _
        {
            cmd.print.(" others ")
            <- @
        }
    }
}
```
## Roadmap
1. 2017.07 ~ 2018.03 
    1. Design syntax.
    1. Completed translator to C # compiler.
1. 2018.03 ~ 2019.03
    1. Rewrite all xy projects using xylang.
    1. Develop vscode syntax plugin.
    1. Compiler features improvements (identifier records, cross-file references, project compilation).
1. 2019.03 ~ 2021.03
    1. Compile to CIL or LLVM.
    1. Improved compilation capabilities and support for language server protocols.
## Compare
Compare with C#, Go, Kotlin, Swift.
Read detail from [Here](./Compare.md).  
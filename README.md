# The XyLang Programming Language
XyLang is a simpler and more friendly .NET programming language.  

This is the main source code repository for XyLang. It contains the compiler, standard library, and documentation.

The language is designed to improve reading performance and reduce the grammatical burden so that users can focus their real attention on business needs.

Therefore, we abandon many subtle grammatical features, retaining only the most used part, and enhance its versatility.

Eventually making XyLang with very few grammar, only the presence of symbols on the keyboard instead of keywords is sufficient to express all the logic.

## Features
+ Focus on writing and reading..
+ Less grammar, no keywords.
+ Clear semantics, one logic corresponds to only one expression.
+ Support for compilation to .NET platform, with .NET framework and library resources, we can use this language in a very wide range of scenarios.

## Getting Started
Read detail from The [Book](./book-en/introduction.md).  
阅读 [语言说明文档](./book-zh/介绍.md)。

## Quick Preview
```
// namespace
Main
~System
{
    // main function
    $  
    {
        // array
        greetings := ["Hello", "Hola", "Bonjour",
                    "Ciao", "こんにちは", "안녕하세요",
                    "Cześć", "Olá", "Здравствуйте",
                    "Chào bạn", "您好"];
        // for-each
        @ greetings ~ item
        {
            // call function
            print.(item);
            // if-switch
            ? item ~ [0~8] 
            {
                print.(" in 0-8");
            }
            ~ _
            {
                print.(" over 10");
                ~@;
            };
        };
    };
};
```
## Roadmap
1. 2017.07 ~ 2018.03 
    1. Design syntax.
    1. Completed translator to C # compiler.
1. 2018.03 ~ 2019.03
    1. Rewrite all xy projects using xylang.
    1. Develop vscode syntax plugin.
    1. Compiler features improvements (identifier records, cross-file references, project compilation).
1. 2019.03 ~ 2020.03
    1. Compile to CIL or LLVM.
    1. Increase the standard library.
## Compare
Compare with C#, Kotlin, Swift.
Read detail from [Here](./Compare.md).  
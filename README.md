# The Xs Programming Language
Xs is a focus on simple, open source, cross-platform programming language.

The language is designed to improve reading and writing efficiency, reduce the burden of grammar, and allow users to focus on solving problems.

So Xs discards the cumbersome features, retains the most versatile features, and elegantly expresses logic with minimal grammar.

This is the main source code repository for Xs. It contains the compiler, and documentation.
## Features
+ Well-designed grammar, easy to write and read.
+ Rules are clear and uniform, intuitive.
+ With the support of. NET platform, we can use this language in a very wide range of scenarios with the help of. NET framework and library resources.

## Getting Started
Read detail from The [Book](./book-en/introduction.md).  
阅读 [语言说明文档](./book-zh/introduction.md)。

## Quick Preview
```
# export namespace
\HelloWorld <- {
    System # import namespace
}
# package
program -> {
    # main function
    Main() -> () {
        # list
        greetings := {"Hello", "Hola", "Bonjour",
                    "Ciao", "こんにちは", "안녕하세요",
                    "Cześć", "Olá", "Здравствуйте",
                    "Chào bạn", "您好"}
        # for-each  
        @ item <- greetings {
            # match
            ? item -> [ 0 <= 8 ] {
                prt(item) # call function
            } _ {
                # lambda
                prt( greetings.filter( {it -> it.len > 4} ) )
                <- @
            }
        }
    }
}
```
## Roadmap
1. 2017.07 ~ 2018.03 
    1. Design syntax.
    1. Completed translator to C # compiler.
1. 2018.03 ~ 2019.03
    1. Add standard library.
    1. Improve grammar to achieve grammatical stability.
1. 2019.03 ~ 2021.03
    1. Rewrite all xylaga projects using Xs.
    1. Complete a mature compiler, Compile to CIL or LLVM or JVM.
    1. Improved compilation capabilities and support for language server protocols.
## Compare
Compare with C#, Go, Kotlin, Swift.
Read detail from [Here](./Compare.md).  
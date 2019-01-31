# The Xs Programming Language
Xs is an open source cross-platform programming language focused on simplicity.

The design goal of this language is to improve the efficiency of reading and writing, reduce the burden of grammar, and enable users to focus their real attention on problem solving.

So we abandon a lot of complicated features and only retain the most general functions. In the end, Xs can express logic gracefully with very little grammar.

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
\HelloWorld {
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
                prt( greetings.filter( {it -> it.count > 4} ) )
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
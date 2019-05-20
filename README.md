# The Xs Programming Language
<p>
  <a href="https://github.com/996icu/996.ICU/blob/master/LICENSE_CN">
    <img alt="996icu" src="https://img.shields.io/badge/license-NPL%20%28The%20996%20Prohibited%20License%29-blue.svg">
  </a>
</p>

Xs is a focus on simple, open source, cross-platform programming language.

The language is designed to improve reading and writing efficiency, reduce the burden of grammar, and allow users to focus on solving problems.

So Xs discards the cumbersome features, retains the most versatile features, and elegantly expresses logic with minimal grammar.

This is the main source code repository for Xs. It contains the compiler, and documentation.
## Features
1. Well-designed grammar, easy to write and read.
1. Rules are clear and uniform, intuitive.
1. With the support of. NET platform, we can use this language in a very wide range of scenarios with the help of. NET framework and library resources.

## Getting Started
- [English](./book-en/introduction.md)
- [中文](./book-zh/introduction.md)

## Quick Preview
```
# export namespace
\HelloWorld <- {
    System # import namespace
}

# main function
Main() -> () {
    # call function
   Say hello world now("start now")
}

# function
Say hello world now(begin: Str) -> () {
    Prt(begin)
    # array
    Greetings around the world := {"Hello", "Hola", "Bonjour",
                "Ciao", "こんにちは", "안녕하세요",
                "Cześć", "Olá", "Здравствуйте",
                "Chào bạn", "你好"}
    # loop
    Greetings around the world @ greeting {
        # judge
        greeting ? "Hello" {
            Prt(greeting + " World!")
        } "你好" {
            Prt(greeting + " 世界！")
        } _ {
            Prt(greeting + " Xs!")
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

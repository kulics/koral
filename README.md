# The Lite Programming Language
<p>
  <a href="https://github.com/996icu/996.ICU/blob/master/LICENSE_CN">
    <img alt="996icu" src="https://img.shields.io/badge/license-NPL%20%28The%20996%20Prohibited%20License%29-blue.svg">
  </a>
</p>

Lite is an open source cross-platform programming language focused on engineering.

The language is designed to be simple, readable, and understandable.

By removing keywords, reducing grammatical features, and unifying expression specifications, the language can effectively reduce the burden of reading and writing, allowing users to focus on solving problems.

This is the main source code repository for Lite. It contains the compiler, and documentation.

## Features
- Well designed grammar, easy to write and read.
- The rules are clear and uniform, in line with intuition.
- Currently supports output to C#/Go/TypeScript, and with their resources, we can already use this language in a very wide range of scenarios.
- Output to LLVM will be supported in the future to support a more comprehensive scenario.

## Getting Started
- [English](./book-en/introduction.md)
- [中文](./book-zh/document.md)

## Quick Preview
```
"HelloWorld" {
    "System"
}

Main() -> () {
    Say hello world now("start now")
}

Say hello world now(begin: Str) -> () {
    Print(begin)
    Greetings around the world := {"Hello", "Hola", "Bonjour",
                "Ciao", "こんにちは", "안녕하세요",
                "Cześć", "Olá", "Здравствуйте",
                "Chào bạn", "你好"}
    Greetings around the world @ greeting {
        greeting ? "Hello" {
            Print(greeting + " World!")
        } "你好" {
            Print(greeting + " 世界！")
        } _ {
            Print(greeting + " Lite!")
        }
    }
}
```
## Roadmap
1. 2017.07 ~ 2018.03 
    1. Design syntax.
    1. Completed translator to C# compiler.
1. 2018.03 ~ 2019.06
    1. Complete the implementation of bootstrap.
    1. Add standard library.
    1. Improve grammar to achieve grammatical stability.
1. 2019.06 ~ 2021.06
    1. Rewrite all Xylaga projects using Lite.
    1. Compile to more languages, including Go/TypeScript/LLVM.
    1. Improved compilation capabilities and support for language server protocols.
## Compare
Compare with C#, Go, Kotlin, Swift, Python.
Read detail from [Here](./Compare.md).  

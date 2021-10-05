# The Feel Programming Language

Feel is an open source programming language focused on efficiency. It can help you easily build cross-platform software.

With well-designed grammar rules, this language can effectively reduce the burden of reading and writing, allowing you to focus on solving problems.

This is the main source code repository for Feel. It contains the compiler, and documentation.

> Warning: This language is still in the experimental stage and cannot meet the production requirements.

## Key Features
- A modern grammar, which is easy to distinguish.
- Automatic memory management.
- Generics.
- Multi-paradigm programming.
- Cross-platform.
- Unicode.

## Getting Started
- [English](./book-en/document.md)
- [中文](./book-zh/document.md)

## Quick Preview

```
let main() Void = {
    println("Hello, world!");
    let greetings = makeGreetings("Fall in love with programming!");
    for (greetings.withIndex() is (index, value)) {
        if (index == 0) {
            println(value, ", 世界!");
        } else {
            println(value, ", world!");
        };
    };
};

let makeGreetings(input Str) Str = listOf(input, "你好", "Hola", "Bonjour",
        "Ciao", "こんにちは", "안녕하세요", "Cześć",
         "Olá", "Здравствуйте", "Chào bạn");
```

## Roadmap
1. 2017.07 ~ 2018.03 
    1. Design grammar.
    1. Achieve the C# compiler.
1. 2018.03 ~ 2020.01
    1. Achieve self-compilation.
    1. Include standard library.
    1. Improve grammar to achieve grammatical stability.
1. 2020.01 ~ 2021.12
    1. Write some projects using Feel.
    1. Compile to more backend, including Kotlin/LLVM.
    1. Improved compilation capabilities and support for language server protocols.

## Compare
Compare with C#, Go, Kotlin, Swift, Python.
Read detail from [Here](./Compare.md).  
## Source Code
[C#](https://github.com/kulics-works/feel-csharp)

[Kotlin](https://github.com/kulics-works/feel-kotlin)

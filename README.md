# The K Programming Language
<p>
  <a href="https://github.com/996icu/996.ICU/blob/master/LICENSE_CN">
    <img alt="996icu" src="https://img.shields.io/badge/license-NPL%20%28The%20996%20Prohibited%20License%29-blue.svg">
  </a>
</p>

K is an open source programming language focused on efficiency. It can help you easily build cross-platform software.

With well-designed grammar rules, this language can effectively reduce the burden of reading and writing, allowing you to focus on solving problems.

This is the main source code repository for K. It contains the compiler, and documentation.

`Warning: This language is still in the experimental stage and cannot meet the production requirements. `

`警告：这个语言目前还处于实验阶段，还未能满足生产要求。`

## Key Features
- The moderm gramar, which is easy to distinguish.
- Automatic memory management.
- Generic.
- Multi-paradigm programming.
- Cross-platform.
- Unicode.
- Multiple backends, support C # / Go / JavaScript / Kotlin.
- LLVM will be supported soon.

## Getting Started
- [English](./book-en/document.md)
- [中文](./book-zh/document.md)

## Quick Preview

```
main : (->) {
    print("Hello, world!")
    greetings : get_greetings("love lite!")
    @ [index]value : greetings {
        ? index.. 0 {
            print(value)
        } 1 {
            print(value + ", 世界!")
        } _ {
            print(value + ", world!")
        }
    }
}

get_greetings : (first str -> result []str) {
    <- first + {"你好"; "Hola"; "Bonjour"
                "Ciao"; "こんにちは"; "안녕하세요"
                "Cześć"; "Olá"; "Здравствуйте"
                "Chào bạn"}
}
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
    1. Write some projects using K.
    1. Compile to more languages, including Go/Kotlin/JavaScript/LLVM.
    1. Improved compilation capabilities and support for language server protocols.

## Compare
Compare with C#, Go, Kotlin, Swift, Python.
Read detail from [Here](./Compare.md).  
## Source Code
[C#](https://github.com/kulics-works/k-csharp)

[Go (not yet)](https://github.com/kulics-works/k-go)

[JavaScript (not yet)](https://github.com/kulics-works/k-javascript)

[Kotlin (not yet)](https://github.com/kulics-works/k-kotlin)

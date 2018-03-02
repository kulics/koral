# The XyLang Programming Language
XyLang is an open source, simple, friendly programming language.  

This is the main source code repository for XyLang. It contains the compiler, standard library, and documentation.

The language is designed to improve reading performance and reduce the grammatical burden so that users can focus their real attention on business needs.
Therefore, we abandon many subtle grammatical features, retaining only the most used part, and enhance its versatility.
Eventually making XyLang with very few grammar, only the presence of symbols on the keyboard instead of keywords is sufficient to express all the logic.

## Features
+ Focus on writing and reading..
+ Less grammar, no keywords.
+ Clear semantics, a logic of only one expression.
+ Support for compilation to .Net platform, with .Net framework and library resources, we can use this language in a very wide range of scenarios.

## Getting Started
Read detail from The [Book]().
阅读 [语言说明文档](./book-zh/介绍.md)。

## Quick Preview

    :> Main
    {
        <: 
        {
            System;
        }

        $  
        {
            greetings => ["Hello", "Hola", "Bonjour",
                        "Ciao", "こんにちは", "안녕하세요",
                        "Cześć", "Olá", "Здравствуйте",
                        "Chào bạn", "您好"];
            @ greetings ~ item
            {
                print(item);
                ? item ~ 0..8 
                {
                    print(" in 0-8");
                }
                ~ _
                {
                    print(" over 10");
                    ~@;
                };
            };
        };
    };


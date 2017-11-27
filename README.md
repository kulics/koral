# The XyLang Programming Language
XyLang is an open source programming language that makes programming easy and simple.  
This is the main source code repository for XyLang. It contains the compiler, standard library, and documentation.

## Features
+ Grammar is few and simplified, no keywords.
+ It is easy to write and read.
+ With CLR, most scenes can be supported.
+ It can be translated into other languages as an portable language.

## Getting Started
Read detail from The [Book]().

## Quick Preview
    --> Main;

    <-- System;

    main => () -> ()  
    {
        greetings => ["Hello", "Hola", "Bonjour",
                     "Ciao", "こんにちは", "안녕하세요",
                     "Cześć", "Olá", "Здравствуйте",
                     "Chào bạn", "您好"];
        @ greetings <- (num, greeting)
        {
            print(greeting);
            ? num 
            {
                ~? 0...10 
                {
                    println(" in 0-10");
                };
                ~? _
                {
                    println(" over 10");
                };
            };
        };
    };
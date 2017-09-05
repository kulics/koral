# The XyLang Programming Language
XyLang is an open source programming language that makes programming easy and simple.  
This is the main source code repository for XyLang. It contains the compiler, standard library, and documentation.

## Features
+ Grammar is few and simplified, only 18 keywords.
+ It is easy to write and read.
+ With CLR, most scenes can be supported.
+ It can be translated into other languages as an portable language.

## Getting Started
Read ["Start"] from The [Book].

["Start"]: https://naxy.me
[Book]: https://naxy.me

## Quick Preview
    xpt Main;

    mpt System;

    invr main = () -> ()  
    {
        vr greetings = ["Hello", "Hola", "Bonjour",
                     "Ciao", "こんにちは", "안녕하세요",
                     "Cześć", "Olá", "Здравствуйте",
                     "Chào bạn", "您好"];
        lp greetings -> (num, geeting)
        {
            print(greeting);
            jg num 
            {
                0...10 ->
                    println();
                _ ->
                    rpt "Something Wrong";
            }
        };
    };
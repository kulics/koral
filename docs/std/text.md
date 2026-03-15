# Std.Text API

## Overview
This page lists the public API of module `Std.Text` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait Parseable {
    public parse(s String) [Self]Result
}

public trait RadixParseable Parseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

public trait Formattable ToString {
    public format(self, spec String) String
}
```

## Types
```koral
public type RegexFlag(value UInt)

public type Regex(storage RegexStorage ref)

public type Match

public type Captures

public type MatchIterator

public type CapturesIterator

public type RegexSplitIterator
```

## Given Implementations
```koral
given Int Formattable {
    public format(self, spec String) String
}

given Int8 Formattable {
    public format(self, spec String) String
}

given Int16 Formattable {
    public format(self, spec String) String
}

given Int32 Formattable {
    public format(self, spec String) String
}

given Int64 Formattable {
    public format(self, spec String) String
}

given UInt Formattable {
    public format(self, spec String) String
}

given UInt8 Formattable {
    public format(self, spec String) String
}

given UInt16 Formattable {
    public format(self, spec String) String
}

given UInt32 Formattable {
    public format(self, spec String) String
}

given UInt64 Formattable {
    public format(self, spec String) String
}

given Float64 Formattable {
    public format(self, spec String) String
}

given Float32 Formattable {
    public format(self, spec String) String
}

given String Formattable {
    public format(self, spec String) String
}

given Int Parseable {
    public parse(s String) [Self]Result
}

given Int RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int8 Parseable {
    public parse(s String) [Self]Result
}

given Int8 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int16 Parseable {
    public parse(s String) [Self]Result
}

given Int16 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int32 Parseable {
    public parse(s String) [Self]Result
}

given Int32 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int64 Parseable {
    public parse(s String) [Self]Result
}

given Int64 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt Parseable {
    public parse(s String) [Self]Result
}

given UInt RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt8 Parseable {
    public parse(s String) [Self]Result
}

given UInt8 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt16 Parseable {
    public parse(s String) [Self]Result
}

given UInt16 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt32 Parseable {
    public parse(s String) [Self]Result
}

given UInt32 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt64 Parseable {
    public parse(s String) [Self]Result
}

given UInt64 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Float64 Parseable {
    public parse(s String) [Self]Result
}

given Float32 Parseable {
    public parse(s String) [Self]Result
}

given Rune Parseable {
    public parse(s String) [Self]Result
}

given Regex {
    public compile(pattern String) [Regex]Result
    public compile_with_flags(pattern String, flags RegexFlag) [Regex]Result
}

given Regex {
    public matches(self, text String) Bool
    public find(self, text String) [Match]Option
}

given Regex {
    public find_all(self, text String) MatchIterator
    public captures(self, text String) [Captures]Option
    public captures_all(self, text String) CapturesIterator
}

given Regex {
    public replace(self, text String, replacement String) String
    public replace_all(self, text String, replacement String) String
}

given Regex {
    public split(self, text String) RegexSplitIterator
}

given RegexFlag {
    public none() RegexFlag
    public ignore_case() RegexFlag
    public multiline() RegexFlag
    public combine(self, other RegexFlag) RegexFlag
    public has(self, flag RegexFlag) Bool
}

given Regex {
    public pattern(self) String
    public group_count(self) UInt
}

given Match {
    public text(self) String
    public start(self) UInt
    public end(self) UInt
}

given Captures {
    public text(self) String
    public start(self) UInt
    public end(self) UInt
    public group_count(self) UInt
    public group(self, index UInt) [String]Option
    public group_start(self, index UInt) [UInt]Option
    public group_end(self, index UInt) [UInt]Option
}

given MatchIterator [Match]Iterator {
    public next(self ref) [Match]Option
}

given CapturesIterator [Captures]Iterator {
    public next(self ref) [Captures]Option
}

given RegexSplitIterator [String]Iterator {
    public next(self ref) [String]Option
}
```

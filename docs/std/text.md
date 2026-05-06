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
given Int as Formattable {
    public format(self, spec String) String
}

given Int8 as Formattable {
    public format(self, spec String) String
}

given Int16 as Formattable {
    public format(self, spec String) String
}

given Int32 as Formattable {
    public format(self, spec String) String
}

given Int64 as Formattable {
    public format(self, spec String) String
}

given UInt as Formattable {
    public format(self, spec String) String
}

given UInt8 as Formattable {
    public format(self, spec String) String
}

given UInt16 as Formattable {
    public format(self, spec String) String
}

given UInt32 as Formattable {
    public format(self, spec String) String
}

given UInt64 as Formattable {
    public format(self, spec String) String
}

given Float64 as Formattable {
    public format(self, spec String) String
}

given Float32 as Formattable {
    public format(self, spec String) String
}

given String as Formattable {
    public format(self, spec String) String
}

given Int as Parseable {
    public parse(s String) [Self]Result
}

given Int as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int8 as Parseable {
    public parse(s String) [Self]Result
}

given Int8 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int16 as Parseable {
    public parse(s String) [Self]Result
}

given Int16 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int32 as Parseable {
    public parse(s String) [Self]Result
}

given Int32 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int64 as Parseable {
    public parse(s String) [Self]Result
}

given Int64 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt as Parseable {
    public parse(s String) [Self]Result
}

given UInt as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt8 as Parseable {
    public parse(s String) [Self]Result
}

given UInt8 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt16 as Parseable {
    public parse(s String) [Self]Result
}

given UInt16 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt32 as Parseable {
    public parse(s String) [Self]Result
}

given UInt32 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt64 as Parseable {
    public parse(s String) [Self]Result
}

given UInt64 as RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Float64 as Parseable {
    public parse(s String) [Self]Result
}

given Float32 as Parseable {
    public parse(s String) [Self]Result
}

given Rune as Parseable {
    public parse(s String) [Self]Result
}

given Regex {
    public compile(pattern String) [Regex]Result
    public compile_with_flags(pattern String, flags RegexFlag) [Regex]Result
}

given Regex {
    public matches(self ref, text String) Bool
    public find(self ref, text String) [Match]Option
}

given Regex {
    public find_all(self ref, text String) MatchIterator
    public captures(self ref, text String) [Captures]Option
    public captures_all(self ref, text String) CapturesIterator
}

given Regex {
    public replace(self ref, text String, with: String) String
    public replace_all(self ref, text String, with: String) String
}

given Regex {
    public split(self ref, text String) RegexSplitIterator
}

given RegexFlag {
    public none() RegexFlag
    public ignore_case() RegexFlag
    public multiline() RegexFlag
    public combine(self, other RegexFlag) RegexFlag
    public has(self, flag RegexFlag) Bool
}

given Regex {
    public pattern(self ref) String
    public group_count(self ref) UInt
}

given Match {
    public text(self ref) String
    public start(self ref) UInt
    public end(self ref) UInt
}

given Captures {
    public text(self ref) String
    public start(self ref) UInt
    public end(self ref) UInt
    public group_count(self ref) UInt
    public group(self ref, index UInt) [String]Option
    public group_start(self ref, index UInt) [UInt]Option
    public group_end(self ref, index UInt) [UInt]Option
}

given MatchIterator as [Match]Iterator {
    public next(self mut ref) [Match]Option
}

given CapturesIterator as [Captures]Iterator {
    public next(self mut ref) [Captures]Option
}

given RegexSplitIterator as [String]Iterator {
    public next(self mut ref) [String]Option
}
```

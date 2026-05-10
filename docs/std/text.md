# Std.Text API

## Overview
This page lists the public API of module `Std.Text` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait Parseable {
    public parse(s String) Result[Self]
}

public trait RadixParseable Parseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

public trait Formattable ToString {
    public format(self, spec String) String
}
```

## Types
```koral
public type RegexFlag(value UInt)

public type Regex(storage ref RegexStorage)

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
    public parse(s String) Result[Self]
}

given Int as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given Int8 as Parseable {
    public parse(s String) Result[Self]
}

given Int8 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given Int16 as Parseable {
    public parse(s String) Result[Self]
}

given Int16 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given Int32 as Parseable {
    public parse(s String) Result[Self]
}

given Int32 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given Int64 as Parseable {
    public parse(s String) Result[Self]
}

given Int64 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given UInt as Parseable {
    public parse(s String) Result[Self]
}

given UInt as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given UInt8 as Parseable {
    public parse(s String) Result[Self]
}

given UInt8 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given UInt16 as Parseable {
    public parse(s String) Result[Self]
}

given UInt16 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given UInt32 as Parseable {
    public parse(s String) Result[Self]
}

given UInt32 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given UInt64 as Parseable {
    public parse(s String) Result[Self]
}

given UInt64 as RadixParseable {
    public parse_radix(s String, radix UInt) Result[Self]
}

given Float64 as Parseable {
    public parse(s String) Result[Self]
}

given Float32 as Parseable {
    public parse(s String) Result[Self]
}

given Rune as Parseable {
    public parse(s String) Result[Self]
}

given Regex {
    public compile(pattern String) Result[Regex]
    public compile_with_flags(pattern String, flags RegexFlag) Result[Regex]
}

given Regex {
    public matches(self ref, text String) Bool
    public find(self ref, text String) Option[Match]
}

given Regex {
    public find_all(self ref, text String) MatchIterator
    public captures(self ref, text String) Option[Captures]
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
    public group(self ref, index UInt) Option[String]
    public group_start(self ref, index UInt) Option[UInt]
    public group_end(self ref, index UInt) Option[UInt]
}

given MatchIterator as Iterator[Match] {
    public next(self mut ref) Option[Match]
}

given CapturesIterator as Iterator[Captures] {
    public next(self mut ref) Option[Captures]
}

given RegexSplitIterator as Iterator[String] {
    public next(self mut ref) Option[String]
}
```

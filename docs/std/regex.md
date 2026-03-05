# std.regex API

## Overview
This page lists the public API of module `std.regex` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

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
given Regex {
    public new(pattern String) [Regex]Result
    public with_flags(pattern String, flags RegexFlag) [Regex]Result
}

given Regex {
    public is_match(self, text String) Bool
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

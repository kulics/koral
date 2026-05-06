# Std.Rand API

## Overview
This page lists the public API of module `Std.Rand` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let default_random() [DefaultRandomSource]Random
```

## Traits
```koral
public trait RandomSource {
    generate(self ref) UInt64
}

public trait Randomizable {
    [R RandomSource]random(source R) Self
}
```

## Types
```koral
public type [R RandomSource]Random

public type DefaultRandomSource
```

## Given Implementations
```koral
given[R RandomSource] [R]Random {
    public new(rng R) [R]Random
    public [T Randomizable]next(self ref) T
    public next_int(self ref, range [Int]Range) Int
    public next_uint(self ref, range [UInt]Range) UInt
    public [T Deref]shuffle(self ref, list [T]List mut ref) Void
    public [T Deref]choose(self ref, list [T]List) [T]Option
}

given UInt64 as Randomizable {
    public [R RandomSource]random(source R) UInt64
}

given UInt32 as Randomizable {
    public [R RandomSource]random(source R) UInt32
}

given UInt16 as Randomizable {
    public [R RandomSource]random(source R) UInt16
}

given UInt8 as Randomizable {
    public [R RandomSource]random(source R) UInt8
}

given Int64 as Randomizable {
    public [R RandomSource]random(source R) Int64
}

given Int32 as Randomizable {
    public [R RandomSource]random(source R) Int32
}

given Int16 as Randomizable {
    public [R RandomSource]random(source R) Int16
}

given Int8 as Randomizable {
    public [R RandomSource]random(source R) Int8
}

given Float64 as Randomizable {
    public [R RandomSource]random(source R) Float64
}

given Float32 as Randomizable {
    public [R RandomSource]random(source R) Float32
}

given Bool as Randomizable {
    public [R RandomSource]random(source R) Bool
}

given UInt as Randomizable {
    public [R RandomSource]random(source R) UInt
}

given Int as Randomizable {
    public [R RandomSource]random(source R) Int
}

given DefaultRandomSource {
    public from_seed(s0 UInt64, s1 UInt64, s2 UInt64, s3 UInt64) DefaultRandomSource
    public new() DefaultRandomSource
}

given DefaultRandomSource as RandomSource {
    public generate(self ref) UInt64
}
```

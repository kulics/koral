# std.rand API

## Overview
This page lists the public API of module `std.rand` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let default_random() [DefaultRandomSource]Random
```

## Traits
```koral
public trait RandomSource {
    generate(self) UInt64
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
    public [T Randomizable]next(self) T
    public next_int(self, range [Int]Range) Int
    public next_uint(self, range [UInt]Range) UInt
    public [T Any]shuffle(self, list [T]List ref) Void
    public [T Any]choose(self, list [T]List) [T]Option
}

given UInt64 Randomizable {
    public [R RandomSource]random(source R) UInt64
}

given UInt32 Randomizable {
    public [R RandomSource]random(source R) UInt32
}

given UInt16 Randomizable {
    public [R RandomSource]random(source R) UInt16
}

given UInt8 Randomizable {
    public [R RandomSource]random(source R) UInt8
}

given Int64 Randomizable {
    public [R RandomSource]random(source R) Int64
}

given Int32 Randomizable {
    public [R RandomSource]random(source R) Int32
}

given Int16 Randomizable {
    public [R RandomSource]random(source R) Int16
}

given Int8 Randomizable {
    public [R RandomSource]random(source R) Int8
}

given Float64 Randomizable {
    public [R RandomSource]random(source R) Float64
}

given Float32 Randomizable {
    public [R RandomSource]random(source R) Float32
}

given Bool Randomizable {
    public [R RandomSource]random(source R) Bool
}

given UInt Randomizable {
    public [R RandomSource]random(source R) UInt
}

given Int Randomizable {
    public [R RandomSource]random(source R) Int
}

given DefaultRandomSource {
    public from_seed(s0 UInt64, s1 UInt64, s2 UInt64, s3 UInt64) DefaultRandomSource
    public new() DefaultRandomSource
}

given DefaultRandomSource RandomSource {
    public generate(self) UInt64
}
```

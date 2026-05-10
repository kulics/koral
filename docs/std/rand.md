# Std.Rand API

## Overview
This page lists the public API of module `Std.Rand` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let default_random() Random[DefaultRandomSource]
```

## Traits
```koral
public trait RandomSource {
    generate(self ref) UInt64
}

public trait Randomizable {
    random[R RandomSource](source R) Self
}
```

## Types
```koral
public type Random[R RandomSource]

public type DefaultRandomSource
```

## Given Implementations
```koral
given[R RandomSource] Random[R] {
    public new(rng R) Random[R]
    public next[T Randomizable](self ref) T
    public next_int(self ref, range Range[Int]) Int
    public next_uint(self ref, range Range[UInt]) UInt
    public shuffle[T Deref](self ref, list mut ref List[T]) Void
    public choose[T Deref](self ref, list List[T]) Option[T]
}

given UInt64 as Randomizable {
    public random[R RandomSource](source R) UInt64
}

given UInt32 as Randomizable {
    public random[R RandomSource](source R) UInt32
}

given UInt16 as Randomizable {
    public random[R RandomSource](source R) UInt16
}

given UInt8 as Randomizable {
    public random[R RandomSource](source R) UInt8
}

given Int64 as Randomizable {
    public random[R RandomSource](source R) Int64
}

given Int32 as Randomizable {
    public random[R RandomSource](source R) Int32
}

given Int16 as Randomizable {
    public random[R RandomSource](source R) Int16
}

given Int8 as Randomizable {
    public random[R RandomSource](source R) Int8
}

given Float64 as Randomizable {
    public random[R RandomSource](source R) Float64
}

given Float32 as Randomizable {
    public random[R RandomSource](source R) Float32
}

given Bool as Randomizable {
    public random[R RandomSource](source R) Bool
}

given UInt as Randomizable {
    public random[R RandomSource](source R) UInt
}

given Int as Randomizable {
    public random[R RandomSource](source R) Int
}

given DefaultRandomSource {
    public from_seed(s0 UInt64, s1 UInt64, s2 UInt64, s3 UInt64) DefaultRandomSource
    public new() DefaultRandomSource
}

given DefaultRandomSource as RandomSource {
    public generate(self ref) UInt64
}
```

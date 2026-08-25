# Std.Io API

## Overview
This page lists the public API of module `Std.Io` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait Reader {
    read(*self, into: *mutable List[UInt8], range Range[UInt]) Result[UInt]
}

public trait Writer {
    write(*self, from: List[UInt8], range Range[UInt]) Result[UInt]
    flush(*self) Result[Void]
}

public trait Seeker {
    seek(*self, pos SeekOrigin) Result[UInt64]
}
```

## Types
```koral
public type BufReader[R Reader]

public type BufWriter[W Writer]

public type ByteBuffer

public type IoError {
    InvalidUtf8(),
    WriteZero(),
    Other(detail String),
}

public type SeekOrigin {
    Start(offset UInt64),
    End(offset Int64),
    Current(offset Int64),
}
```

## Given Implementations
```koral
given[R Reader] BufReader[R] {
    public new(r R) BufReader[R]
    public with_capacity(cap UInt, r R) BufReader[R]
    public read_byte(*self) Result[Option[UInt8]]
    public read_rune(*self) Result[Option[Rune]]
    public read_until(*self, delim UInt8, into: *mutable List[UInt8], range Range[UInt]) Result[UInt]
    public read_line(*self) Result[Option[String]]
    public skip(*self, n UInt) Result[UInt]
}

given[R Reader] BufReader[R] as Reader {
    public read(*self, into: *mutable List[UInt8], range Range[UInt]) Result[UInt]
}

given[R Reader and Seeker] BufReader[R] as Seeker {
    public seek(*self, pos SeekOrigin) Result[UInt64]
}

given[W Writer] BufWriter[W] {
    public new(w W) BufWriter[W]
    public with_capacity(cap UInt, w W) BufWriter[W]
    public write_byte(*self, b UInt8) Result[Void]
    public write_string(*self, s String) Result[Void]
    public write_line(*self, s String) Result[Void]
    public write_rune(*self, r Rune) Result[Void]
}

given[W Writer] BufWriter[W] as Writer {
    public write(*self, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(*self) Result[Void]
}

given[W Writer and Seeker] BufWriter[W] as Seeker {
    public seek(*self, pos SeekOrigin) Result[UInt64]
}

given ByteBuffer {
    public new() ByteBuffer
    public with_capacity(cap UInt) ByteBuffer
    public from_string(s String) ByteBuffer
    public from_bytes(bytes List[UInt8]) ByteBuffer
}

given ByteBuffer as Reader {
    public read(*self, into: *mutable List[UInt8], range Range[UInt]) Result[UInt]
}

given ByteBuffer as Writer {
    public write(*self, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(*self) Result[Void]
}

given ByteBuffer as Seeker {
    public seek(*self, pos SeekOrigin) Result[UInt64]
}

given IoError as Error {
    public message(*self) String
}

given Reader {
    public read_all(*self) Result[List[UInt8]]
    public copy_all_to[W Writer](self, dst W) Result[UInt]
}

given Writer {
    public write_all(*self, from: List[UInt8], range Range[UInt]) Result[Void]
}
```

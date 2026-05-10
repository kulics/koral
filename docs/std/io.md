# Std.Io API

## Overview
This page lists the public API of module `Std.Io` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait Reader {
    read(self ref, into: mut ref List[UInt8], range Range[UInt]) Result[UInt]
}

public trait Writer {
    write(self ref, from: List[UInt8], range Range[UInt]) Result[UInt]
    flush(self ref) Result[Void]
}

public trait Seeker {
    seek(self ref, pos SeekOrigin) Result[UInt64]
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
    public read_byte(self ref) Result[Option[UInt8]]
    public read_rune(self ref) Result[Option[Rune]]
    public read_until(self ref, delim UInt8, into: mut ref List[UInt8], range Range[UInt]) Result[UInt]
    public read_line(self ref) Result[Option[String]]
    public skip(self ref, n UInt) Result[UInt]
}

given[R Reader] BufReader[R] as Reader {
    public read(self ref, into: mut ref List[UInt8], range Range[UInt]) Result[UInt]
}

given[R Reader and Seeker] BufReader[R] as Seeker {
    public seek(self ref, pos SeekOrigin) Result[UInt64]
}

given[W Writer] BufWriter[W] {
    public new(w W) BufWriter[W]
    public with_capacity(cap UInt, w W) BufWriter[W]
    public write_byte(self ref, b UInt8) Result[Void]
    public write_string(self ref, s String) Result[Void]
    public write_line(self ref, s String) Result[Void]
    public write_rune(self ref, r Rune) Result[Void]
}

given[W Writer] BufWriter[W] as Writer {
    public write(self ref, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(self ref) Result[Void]
}

given[W Writer and Seeker] BufWriter[W] as Seeker {
    public seek(self ref, pos SeekOrigin) Result[UInt64]
}

given ByteBuffer {
    public new() ByteBuffer
    public with_capacity(cap UInt) ByteBuffer
    public from_string(s String) ByteBuffer
    public from_bytes(bytes List[UInt8]) ByteBuffer
}

given ByteBuffer as Reader {
    public read(self ref, into: mut ref List[UInt8], range Range[UInt]) Result[UInt]
}

given ByteBuffer as Writer {
    public write(self ref, from: List[UInt8], range Range[UInt]) Result[UInt]
    public flush(self ref) Result[Void]
}

given ByteBuffer as Seeker {
    public seek(self ref, pos SeekOrigin) Result[UInt64]
}

given IoError as Error {
    public message(self ref) String
}

given Reader {
    public read_all(self ref) Result[List[UInt8]]
    public copy_all_to[W Writer](self, dst W) Result[UInt]
}

given Writer {
    public write_all(self ref, from: List[UInt8], range Range[UInt]) Result[Void]
}
```

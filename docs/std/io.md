# Std.Io API

## Overview
This page lists the public API of module `Std.Io` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait Reader {
    read(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
}

public trait Writer {
    write(self ref, from: [UInt8]List, range [UInt]Range) [UInt]Result
    flush(self ref) [Void]Result
}

public trait Seeker {
    seek(self ref, pos SeekOrigin) [UInt64]Result
}
```

## Types
```koral
public type [R Reader]BufReader

public type [W Writer]BufWriter

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
given[R Reader] [R]BufReader {
    public new(r R) [R]BufReader
    public with_capacity(cap UInt, r R) [R]BufReader
    public read_byte(self ref) [[UInt8]Option]Result
    public read_rune(self ref) [[Rune]Option]Result
    public read_until(self ref, delim UInt8, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
    public read_line(self ref) [[String]Option]Result
    public skip(self ref, n UInt) [UInt]Result
}

given[R Reader] [R]BufReader as Reader {
    public read(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
}

given[R Reader and Seeker] [R]BufReader as Seeker {
    public seek(self ref, pos SeekOrigin) [UInt64]Result
}

given[W Writer] [W]BufWriter {
    public new(w W) [W]BufWriter
    public with_capacity(cap UInt, w W) [W]BufWriter
    public write_byte(self ref, b UInt8) [Void]Result
    public write_string(self ref, s String) [Void]Result
    public write_line(self ref, s String) [Void]Result
    public write_rune(self ref, r Rune) [Void]Result
}

given[W Writer] [W]BufWriter as Writer {
    public write(self ref, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self ref) [Void]Result
}

given[W Writer and Seeker] [W]BufWriter as Seeker {
    public seek(self ref, pos SeekOrigin) [UInt64]Result
}

given ByteBuffer {
    public new() ByteBuffer
    public with_capacity(cap UInt) ByteBuffer
    public from_string(s String) ByteBuffer
    public from_bytes(bytes [UInt8]List) ByteBuffer
}

given ByteBuffer as Reader {
    public read(self ref, into: [UInt8]List mut ref, range [UInt]Range) [UInt]Result
}

given ByteBuffer as Writer {
    public write(self ref, from: [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self ref) [Void]Result
}

given ByteBuffer as Seeker {
    public seek(self ref, pos SeekOrigin) [UInt64]Result
}

given IoError as Error {
    public message(self ref) String
}

given Reader {
    public read_all(self ref) [[UInt8]List]Result
    public [W Writer]copy_all_to(self, dst W) [UInt]Result
}

given Writer {
    public write_all(self ref, from: [UInt8]List, range [UInt]Range) [Void]Result
}
```

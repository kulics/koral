# std.io API

## Overview
This page lists the public API of module `std.io` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
```koral
public trait Reader {
    read(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
}

public trait Writer {
    write(self, src [UInt8]List, range [UInt]Range) [UInt]Result
    flush(self) [Void]Result
}

public trait Seeker {
    seek(self, pos SeekOrigin) [UInt64]Result
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
    public with_capacity(r R, cap UInt) [R]BufReader
    public read_byte(self) [[UInt8]Option]Result
    public read_rune(self) [[Rune]Option]Result
    public read_until(self, delim UInt8, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
    public read_line(self) [[String]Option]Result
    public skip(self, n UInt) [UInt]Result
}

given[R Reader] [R]BufReader Reader {
    public read(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
}

given[R Reader and Seeker] [R]BufReader Seeker {
    public seek(self, pos SeekOrigin) [UInt64]Result
}

given[W Writer] [W]BufWriter {
    public new(w W) [W]BufWriter
    public with_capacity(w W, cap UInt) [W]BufWriter
    public write_byte(self, b UInt8) [Void]Result
    public write_string(self, s String) [Void]Result
    public write_line(self, s String) [Void]Result
    public write_rune(self, r Rune) [Void]Result
}

given[W Writer] [W]BufWriter Writer {
    public write(self, src [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self) [Void]Result
}

given[W Writer and Seeker] [W]BufWriter Seeker {
    public seek(self, pos SeekOrigin) [UInt64]Result
}

given ByteBuffer {
    public zero() ByteBuffer
    public with_capacity(cap UInt) ByteBuffer
    public from_string(s String) ByteBuffer
    public from_bytes(bytes [UInt8]List) ByteBuffer
}

given ByteBuffer Reader {
    public read(self, dst [UInt8]List ref, range [UInt]Range) [UInt]Result
}

given ByteBuffer Writer {
    public write(self, src [UInt8]List, range [UInt]Range) [UInt]Result
    public flush(self) [Void]Result
}

given ByteBuffer Seeker {
    public seek(self, pos SeekOrigin) [UInt64]Result
}

given IoError Error {
    public message(self) String
}

given Reader {
    public read_all(self) [[UInt8]List]Result
    public [W Writer]copy_all_to(self, dst W) [UInt]Result
}

given Writer {
    public write_all(self, src [UInt8]List, range [UInt]Range) [Void]Result
}
```

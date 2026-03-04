# std.convert API

## 概述
本页摘录模块 `std.convert` 的公开 API（仅保留声明语法），按自由函数 / trait / 类型 / given 组织。

## 自由函数
（无）

## trait
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

## 类型
（无）

## given
```koral
given Int Formattable {
    public format(self, spec String) String
}

given Int8 Formattable {
    public format(self, spec String) String
}

given Int16 Formattable {
    public format(self, spec String) String
}

given Int32 Formattable {
    public format(self, spec String) String
}

given Int64 Formattable {
    public format(self, spec String) String
}

given UInt Formattable {
    public format(self, spec String) String
}

given UInt8 Formattable {
    public format(self, spec String) String
}

given UInt16 Formattable {
    public format(self, spec String) String
}

given UInt32 Formattable {
    public format(self, spec String) String
}

given UInt64 Formattable {
    public format(self, spec String) String
}

given Float64 Formattable {
    public format(self, spec String) String
}

given Float32 Formattable {
    public format(self, spec String) String
}

given String Formattable {
    public format(self, spec String) String
}

given Int Parseable {
    public parse(s String) [Self]Result
}

given Int RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int8 Parseable {
    public parse(s String) [Self]Result
}

given Int8 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int16 Parseable {
    public parse(s String) [Self]Result
}

given Int16 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int32 Parseable {
    public parse(s String) [Self]Result
}

given Int32 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Int64 Parseable {
    public parse(s String) [Self]Result
}

given Int64 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt Parseable {
    public parse(s String) [Self]Result
}

given UInt RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt8 Parseable {
    public parse(s String) [Self]Result
}

given UInt8 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt16 Parseable {
    public parse(s String) [Self]Result
}

given UInt16 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt32 Parseable {
    public parse(s String) [Self]Result
}

given UInt32 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given UInt64 Parseable {
    public parse(s String) [Self]Result
}

given UInt64 RadixParseable {
    public parse_radix(s String, radix UInt) [Self]Result
}

given Float64 Parseable {
    public parse(s String) [Self]Result
}

given Float32 Parseable {
    public parse(s String) [Self]Result
}
```

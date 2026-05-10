# Std.Json API

## Overview
This page lists the public API of module `Std.Json` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

## Types
```koral
public type JsonError(
    msg String,
    position UInt,
)

public type JsonValue {
    Null(),
    Bool(value Bool),
    Number(value Float64),
    String(value String),
    Array(elements List[ref JsonValue]),
    Object(entries Dict[String, ref JsonValue]),
}
```

## Given Implementations
```koral
given JsonError as Error {
    public message(self ref) String
}

given JsonError as ToString {
    public to_string(self ref) String
}

given JsonValue {
    public is_null(self ref) Bool
    public is_bool(self ref) Bool
    public is_number(self ref) Bool
    public is_string(self ref) Bool
    public is_array(self ref) Bool
    public is_object(self ref) Bool
    public as_bool(self ref) Option[Bool]
    public as_number(self ref) Option[Float64]
    public as_string(self ref) Option[String]
    public as_array(self ref) Option[List[ref JsonValue]]
    public as_object(self ref) Option[Dict[String, ref JsonValue]]
    public get_field(self ref, key String) Option[ref JsonValue]
    public get_element(self ref, index UInt) Option[ref JsonValue]
    public to_string_pretty(self ref) String
}

given JsonValue as Eq {
    public equals(self, other JsonValue) Bool
}

given JsonValue as Parseable {
    public parse(s String) Result[Self]
}

given JsonValue as ToString {
    public to_string(self ref) String
}
```

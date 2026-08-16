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
    Array(elements List[*JsonValue]),
    Object(entries Dict[String, *JsonValue]),
}
```

## Given Implementations
```koral
given JsonError as Error {
    public message(*self) String
}

given JsonError as ToString {
    public to_string(*self) String
}

given JsonValue {
    public is_null(*self) Bool
    public is_bool(*self) Bool
    public is_number(*self) Bool
    public is_string(*self) Bool
    public is_array(*self) Bool
    public is_object(*self) Bool
    public as_bool(*self) Option[Bool]
    public as_number(*self) Option[Float64]
    public as_string(*self) Option[String]
    public as_array(*self) Option[List[*JsonValue]]
    public as_object(*self) Option[Dict[String, *JsonValue]]
    public get_field(*self, key String) Option[*JsonValue]
    public get_element(*self, index UInt) Option[*JsonValue]
    public to_string_pretty(*self) String
}

given JsonValue as Eq {
    public equals(self, other JsonValue) Bool
}

given JsonValue as Parseable {
    public parse(s String) Result[Self]
}

given JsonValue as ToString {
    public to_string(*self) String
}
```

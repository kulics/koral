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
    Array(elements [JsonValue ref]List),
    Object(entries [String, JsonValue ref]Dict),
}
```

## Given Implementations
```koral
given JsonError Error {
    public message(self) String
}

given JsonError ToString {
    public to_string(self) String
}

given JsonValue {
    public is_null(self) Bool
    public is_bool(self) Bool
    public is_number(self) Bool
    public is_string(self) Bool
    public is_array(self) Bool
    public is_object(self) Bool
    public as_bool(self) [Bool]Option
    public as_number(self) [Float64]Option
    public as_string(self) [String]Option
    public as_array(self) [[JsonValue ref]List]Option
    public as_object(self) [[String, JsonValue ref]Dict]Option
    public get_field(self, key String) [JsonValue ref]Option
    public get_element(self, index UInt) [JsonValue ref]Option
}

given JsonValue Eq {
    public equals(self, other JsonValue) Bool
}

given JsonValue {
    public to_json(self) String
    public to_json_pretty(self) String
}

given JsonValue ToString {
    public to_string(self) String
}
```

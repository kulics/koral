# std.time API

## 概述
本页摘录模块 `std.time` 的公开 API（仅保留声明语法），按自由函数 / trait / 类型 / given 组织。

## 自由函数
（无）

## trait
（无）

## 类型
```koral
public type DateTime

public type MonoTime

public type TimeZone
```

## given
```koral
given TimeZone {
    public name(self) String
    public offset_at(self, dt DateTime) Duration
}

given DateTime {
    public now() DateTime
    public now_utc() DateTime
    public epoch() DateTime
    public from_unix_timestamp(ts Duration) DateTime
    public from_unix_seconds(seconds Int64) DateTime
    public from_components(year Int, month Int, day Int, hour Int, min Int, sec Int, nanos Int, tz TimeZone) [DateTime]Result
}

given DateTime {
    public year(self) Int
    public month(self) Int
    public day(self) Int
    public hour(self) Int
    public minute(self) Int
    public second(self) Int
    public nanosecond(self) Int
    public timezone(self) TimeZone
}

given DateTime {
    public to_unix_timestamp(self) Duration
    public to_unix_seconds(self) Int64
    public in_timezone(self, tz TimeZone) DateTime
    public in_utc(self) DateTime
    public in_local(self) DateTime
    public elapsed(self) Duration
}

given DateTime [Duration]Affine {
    public add_vector(self, v Duration) DateTime
    public sub_vector(self, v Duration) DateTime
    public sub_point(self, other DateTime) Duration
}

given DateTime Eq {
    public equals(self, other DateTime) Bool
}

given DateTime Ord {
    public compare(self, other DateTime) Int
}

given DateTime ToString {
    public to_string(self) String
}

given DateTime Parseable {
    public parse(s String) [DateTime]Result
}

given MonoTime {
    public now() MonoTime
    public elapsed(self) Duration
}

given MonoTime [Duration]Affine {
    public add_vector(self, v Duration) MonoTime
    public sub_vector(self, v Duration) MonoTime
    public sub_point(self, other MonoTime) Duration
}

given MonoTime Eq {
    public equals(self, other MonoTime) Bool
}

given MonoTime Ord {
    public compare(self, other MonoTime) Int
}

given TimeZone {
    public utc() TimeZone
    public local() TimeZone
    public from_offset(offset Duration) [TimeZone]Result
    public from_name(name String) [TimeZone]Result
}

given TimeZone Eq {
    public equals(self, other TimeZone) Bool
}
```

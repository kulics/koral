# Std.Time API

## Overview
This page lists the public API of module `Std.Time` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

## Types
```koral
public type ClockTime

public type Date

public type DateTime

public type MonoTime

public type TimeZone
```

## Given Implementations
```koral
given ClockTime {
    public new(hour: Int, minute: Int, second: Int) [ClockTime]Result
    public new_full(hour: Int, minute: Int, second: Int, nanosecond: Int) [ClockTime]Result
    public midnight() ClockTime
}

given ClockTime {
    public hour(self) Int
    public minute(self) Int
    public second(self) Int
    public nanosecond(self) Int
}

given ClockTime [Duration]Affine {
    public add_vector(self, v Duration) ClockTime
    public sub_vector(self, v Duration) ClockTime
    public sub_point(self, other ClockTime) Duration
}

given ClockTime Eq {
    public equals(self, other ClockTime) Bool
}

given ClockTime Ord {
    public compare(self, other ClockTime) Int
}

given ClockTime ToString {
    public to_string(self) String
}

given ClockTime Parseable {
    public parse(s String) [ClockTime]Result
}

given Date {
    public new(year: Int, month: Int, day: Int) [Date]Result
    public epoch() Date
}

given Date {
    public year(self) Int
    public month(self) Int
    public day(self) Int
    public weekday(self) Int
    public day_of_year(self) Int
    public is_leap_year(self) Bool
    public days_in_month(self) Int
}

given Date {
    public add_days(self, n Int) Date
    public days_until(self, other Date) Int
    public add_months(self, months Int) Date
    public add_years(self, years Int) Date
}

given Date Eq {
    public equals(self, other Date) Bool
}

given Date Ord {
    public compare(self, other Date) Int
}

given Date ToString {
    public to_string(self) String
}

given Date Parseable {
    public parse(s String) [Date]Result
}

given TimeZone {
    public name(self) String
    public offset_at(self, datetime DateTime) Duration
}

given DateTime {
    public now() DateTime
    public now_utc() DateTime
    public epoch() DateTime
    public from_unix_timestamp(timestamp Duration) DateTime
    public from_unix_seconds(seconds Int64) DateTime
    public from_parts(date Date, time ClockTime, timezone TimeZone) DateTime
    public from_date_at_midnight(date Date, timezone TimeZone) DateTime
}

given DateTime {
    public year(self) Int
    public month(self) Int
    public day(self) Int
    public hour(self) Int
    public minute(self) Int
    public second(self) Int
    public timezone(self) TimeZone
    public date(self) Date
    public time(self) ClockTime
    public weekday(self) Int
}

given DateTime {
    public to_unix_timestamp(self) Duration
    public to_unix_seconds(self) Int64
    public in_timezone(self, timezone TimeZone) DateTime
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

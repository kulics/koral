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

given ClockTime [Duration]Add {
    public add(self, v Duration) ClockTime
}

given ClockTime [Duration]Sub {
    public sub(self, v Duration) ClockTime
}

given ClockTime {
    public duration_to(self, other ClockTime) Duration
}

given ClockTime Eq {
    public equals(self, other ClockTime) Bool
}

given ClockTime Ord {
    public compare(self, other ClockTime) Int
}

given ClockTime ToString {
    public to_string(self ref) String
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
    public days_to(self, other Date) Int
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
    public to_string(self ref) String
}

given Date Parseable {
    public parse(s String) [Date]Result
}

given TimeZone {
    public name(self ref) String
    public offset_at(self ref, datetime DateTime) Duration
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
    public year(self ref) Int
    public month(self ref) Int
    public day(self ref) Int
    public hour(self ref) Int
    public minute(self ref) Int
    public second(self ref) Int
    public timezone(self ref) TimeZone
    public date(self ref) Date
    public time(self ref) ClockTime
    public weekday(self ref) Int
}

given DateTime {
    public to_unix_timestamp(self ref) Duration
    public to_unix_seconds(self ref) Int64
    public in_timezone(self ref, timezone TimeZone) DateTime
    public in_utc(self ref) DateTime
    public in_local(self ref) DateTime
    public elapsed(self ref) Duration
}

given DateTime [Duration]Add {
    public add(self, v Duration) DateTime
}

given DateTime [Duration]Sub {
    public sub(self, v Duration) DateTime
}

given DateTime {
    public duration_to(self ref, other DateTime) Duration
}

given DateTime Eq {
    public equals(self, other DateTime) Bool
}

given DateTime Ord {
    public compare(self, other DateTime) Int
}

given DateTime ToString {
    public to_string(self ref) String
}

given DateTime Parseable {
    public parse(s String) [DateTime]Result
}

given MonoTime {
    public now() MonoTime
    public elapsed(self) Duration
}

given MonoTime [Duration]Add {
    public add(self, v Duration) MonoTime
}

given MonoTime [Duration]Sub {
    public sub(self, v Duration) MonoTime
}

given MonoTime {
    public duration_to(self, other MonoTime) Duration
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

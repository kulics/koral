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
    public new(hour Int, minute Int, second Int) Result[ClockTime]
    public new_full(hour Int, minute Int, second Int, nanosecond Int) Result[ClockTime]
    public midnight() ClockTime
}

given ClockTime {
    public hour(self) Int
    public minute(self) Int
    public second(self) Int
    public nanosecond(self) Int
}

given ClockTime as Add[Duration] {
    public add(self, v Duration) ClockTime
}

given ClockTime as Sub[Duration] {
    public sub(self, v Duration) ClockTime
}

given ClockTime {
    public duration_to(self, other ClockTime) Duration
}

given ClockTime as Eq {
    public equals(self, other ClockTime) Bool
}

given ClockTime as Ord {
    public compare(self, other ClockTime) Int
}

given ClockTime as ToString {
    public to_string(*self) String
}

given ClockTime as Parseable {
    public parse(s String) Result[ClockTime]
}

given Date {
    public new(year: Int, month: Int, day: Int) Result[Date]
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

given Date as Eq {
    public equals(self, other Date) Bool
}

given Date as Ord {
    public compare(self, other Date) Int
}

given Date as ToString {
    public to_string(*self) String
}

given Date as Parseable {
    public parse(s String) Result[Date]
}

given TimeZone {
    public name(*self) String
    public offset_at(*self, datetime DateTime) Duration
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
    public year(*self) Int
    public month(*self) Int
    public day(*self) Int
    public hour(*self) Int
    public minute(*self) Int
    public second(*self) Int
    public timezone(*self) TimeZone
    public date(*self) Date
    public time(*self) ClockTime
    public weekday(*self) Int
}

given DateTime {
    public to_unix_timestamp(*self) Duration
    public to_unix_seconds(*self) Int64
    public in_timezone(*self, timezone TimeZone) DateTime
    public in_utc(*self) DateTime
    public in_local(*self) DateTime
    public elapsed(*self) Duration
}

given DateTime as Add[Duration] {
    public add(self, v Duration) DateTime
}

given DateTime as Sub[Duration] {
    public sub(self, v Duration) DateTime
}

given DateTime {
    public duration_to(*self, other DateTime) Duration
}

given DateTime as Eq {
    public equals(self, other DateTime) Bool
}

given DateTime as Ord {
    public compare(self, other DateTime) Int
}

given DateTime as ToString {
    public to_string(*self) String
}

given DateTime as Parseable {
    public parse(s String) Result[DateTime]
}

given MonoTime {
    public now() MonoTime
    public elapsed(self) Duration
}

given MonoTime as Add[Duration] {
    public add(self, v Duration) MonoTime
}

given MonoTime as Sub[Duration] {
    public sub(self, v Duration) MonoTime
}

given MonoTime {
    public duration_to(self, other MonoTime) Duration
}

given MonoTime as Eq {
    public equals(self, other MonoTime) Bool
}

given MonoTime as Ord {
    public compare(self, other MonoTime) Int
}

given TimeZone {
    public utc() TimeZone
    public local() TimeZone
    public from_offset(offset Duration) Result[TimeZone]
    public from_name(name String) Result[TimeZone]
}

given TimeZone as Eq {
    public equals(self, other TimeZone) Bool
}
```

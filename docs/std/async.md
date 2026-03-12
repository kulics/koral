# std.async API

## Overview
This page lists the public API of module `std.async` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let [T Any]run_task(f [T]Func) [T]Thread

public let current_thread_id() UInt64

public let yield_thread_now() Void

public let available_parallelism() UInt
```

## Traits
(none)

## Types
```koral
public type [T Any]Task

public type [T Any]Thread

public type Timer
```

## Given Implementations
```koral
given[T Any] [T]Task {
    public new(f [T]Func) [T]Task
    public set_name(self, name String) [T]Task
    public set_stack_size(self, size UInt) [T]Task
    public spawn(self) [T]Thread
}

given[T Any] [T]Thread {
    public wait(self) [T]Result
    public detach(self) Void
    public id(self) UInt64
    public name(self) [String]Option
}

given Timer {
    public once(delay Duration, f [Void]Func) Timer
    public repeating(delay Duration, interval Duration, f [Void]Func) Timer
    public repeating_n(n UInt, delay Duration, interval Duration, f [Void]Func) Timer
    public repeating_next(delay Duration, f [[Duration]Option]Func) Timer
    public cancel(self) Void
    public wait(self) Void
}
```

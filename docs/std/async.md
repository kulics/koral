# Std.Async API

## Overview
This page lists the public API of module `Std.Async` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let run_task(f [Void]Func) Thread

public let current_thread_id() UInt64

public let yield_thread_now() Void

public let available_parallelism() UInt
```

## Traits
(none)

## Types
```koral
public type Task

public type Thread

public type Timer

public type Ticker
```

## Given Implementations
```koral
given Task {
    public new(f [Void]Func) Task
    public set_name(self, name String) Task
    public set_stack_size(self, size UInt) Task
    public spawn(self) Thread
}

given Thread {
    public wait(self) [Void]Result
    public detach(self) Void
    public id(self) UInt64
    public name(self) [String]Option
}

given Timer {
    public new(d Duration) Timer
    public wait(self) Void
    public reset(self, d Duration) Void
    public cancel(self) Void
}

given Ticker {
    public new(interval Duration) Ticker
    public wait(self) Void
    public reset(self, interval Duration) Void
    public cancel(self) Void
}
```

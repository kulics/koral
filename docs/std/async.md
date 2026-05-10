# Std.Async API

## Overview
This page lists the public API of module `Std.Async` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let run_task(f Func[Void]) Thread

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
    public new(f Func[Void]) Task
    public set_name(self, name String) Task
    public set_stack_size(self, size UInt) Task
    public spawn(self) Thread
}

given Thread {
    public wait(self ref) Result[Void]
    public detach(self ref) Void
    public id(self ref) UInt64
    public name(self ref) Option[String]
}

given Timer {
    public new(d Duration) Timer
    public wait(self ref) Void
    public reset(self ref, d Duration) Void
    public cancel(self ref) Void
}

given Ticker {
    public new(interval Duration) Ticker
    public wait(self ref) Void
    public reset(self ref, interval Duration) Void
    public cancel(self ref) Void
}
```

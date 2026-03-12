# Std.Sync API

## Overview
This page lists the public API of module `Std.Sync` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let [T Any]make_channel(capacity UInt) [[T]SendChannel, [T]RecvChannel]Pair
```

## Traits
(none)

## Types
```koral
public type AtomicBool

public type AtomicInt

public type AtomicUInt

public type Barrier

public type [T Any]SendChannel

public type [T Any]RecvChannel

public type [T Any]Lazy

public type Mutex

public type MutexCondvar

public type Semaphore

public type SharedMutex

public type SharedMutexCondvar
```

## Given Implementations
```koral
given AtomicBool {
    public new(value Bool) AtomicBool
    public load(self) Bool
    public store(self, value Bool) Void
    public swap(self, value Bool) Bool
    public compare_exchange(self, expected Bool, desired Bool) Bool
}

given AtomicBool ToString {
    public to_string(self) String
}

given AtomicInt {
    public new(value Int) AtomicInt
    public load(self) Int
    public store(self, value Int) Void
    public swap(self, value Int) Int
    public compare_exchange(self, expected Int, desired Int) Bool
    public fetch_add(self, delta Int) Int
    public fetch_sub(self, delta Int) Int
}

given AtomicInt ToString {
    public to_string(self) String
}

given AtomicUInt {
    public new(value UInt) AtomicUInt
    public load(self) UInt
    public store(self, value UInt) Void
    public swap(self, value UInt) UInt
    public compare_exchange(self, expected UInt, desired UInt) Bool
    public fetch_add(self, delta UInt) UInt
    public fetch_sub(self, delta UInt) UInt
}

given AtomicUInt ToString {
    public to_string(self) String
}

given Barrier {
    public new(count UInt) Barrier
    public depart(self, count UInt) Void
    public arrive(self) Void
    public arrive_and_wait(self) Void
    public wait(self) Void
}

given[T Any] [T]SendChannel {
    public send(self, value T) [Void]Result
    public try_send(self, value T) [Bool]Result
}

given[T Any] [T]RecvChannel {
    public recv(self) [T]Result
    public try_recv(self) [[T]Option]Result
}

given[T Any] [T]Lazy {
    public new(f [T]Func) [T]Lazy
    public get(self) T
    public is_initialized(self) Bool
}

given Mutex {
    public new() Mutex
    public lock(self) Void
    public try_lock(self) Bool
    public unlock(self) Void
    public condvar(self) MutexCondvar
}

given MutexCondvar {
    public wait(self) Void
    public notify(self) Void
    public notify_all(self) Void
}

given Semaphore {
    public new(permits UInt) Semaphore
    public acquire(self) Void
    public try_acquire(self) Bool
    public release(self) Void
}

given SharedMutex {
    public new() SharedMutex
    public lock(self) Void
    public unlock(self) Void
    public try_lock(self) Bool
    public lock_shared(self) Void
    public unlock_shared(self) Void
    public try_lock_shared(self) Bool
    public condvar(self) SharedMutexCondvar
}

given SharedMutexCondvar {
    public wait(self) Void
    public notify(self) Void
    public notify_all(self) Void
}
```

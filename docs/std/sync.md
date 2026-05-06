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

public type [T Any]SendChannel

public type [T Any]RecvChannel

public type LatchGate

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
    public load(self ref) Bool
    public store(self ref, value Bool) Void
    public swap(self ref, value Bool) Bool
    public compare_exchange(self ref, expected: Bool, desired: Bool) Bool
}

given AtomicBool as ToString {
    public to_string(self ref) String
}

given AtomicInt {
    public new(value Int) AtomicInt
    public load(self ref) Int
    public store(self ref, value Int) Void
    public swap(self ref, value Int) Int
    public compare_exchange(self ref, expected: Int, desired: Int) Bool
    public fetch_add(self ref, delta Int) Int
    public fetch_sub(self ref, delta Int) Int
}

given AtomicInt as ToString {
    public to_string(self ref) String
}

given AtomicUInt {
    public new(value UInt) AtomicUInt
    public load(self ref) UInt
    public store(self ref, value UInt) Void
    public swap(self ref, value UInt) UInt
    public compare_exchange(self ref, expected: UInt, desired: UInt) Bool
    public fetch_add(self ref, delta UInt) UInt
    public fetch_sub(self ref, delta UInt) UInt
}

given AtomicUInt as ToString {
    public to_string(self ref) String
}

given[T Any] [T]SendChannel {
    public send(self ref, value T) [Void]Result
    public try_send(self ref, value T) [Bool]Result
}

given[T Any] [T]RecvChannel {
    public recv(self ref) [T]Result
    public try_recv(self ref) [[T]Option]Result
}

given LatchGate {
    public new(count UInt) LatchGate
    public latch(self ref, count UInt) Void
    public unlatch(self ref) Void
    public unlatch_and_wait(self ref) Void
    public wait(self ref) Void
}

given[T Any] [T]Lazy {
    public new(f [T]Func) [T]Lazy
    public get(self ref) T
    public is_initialized(self ref) Bool
}

given Mutex {
    public new() Mutex
    public lock(self ref) Void
    public try_lock(self ref) Bool
    public unlock(self ref) Void
    public condvar(self ref) MutexCondvar
}

given MutexCondvar {
    public wait(self ref) Void
    public notify(self ref) Void
    public notify_all(self ref) Void
}

given Semaphore {
    public new(permits UInt) Semaphore
    public acquire(self ref) Void
    public try_acquire(self ref) Bool
    public release(self ref) Void
}

given SharedMutex {
    public new() SharedMutex
    public lock(self ref) Void
    public unlock(self ref) Void
    public try_lock(self ref) Bool
    public lock_shared(self ref) Void
    public unlock_shared(self ref) Void
    public try_lock_shared(self ref) Bool
    public condvar(self ref) SharedMutexCondvar
}

given SharedMutexCondvar {
    public wait(self ref) Void
    public notify(self ref) Void
    public notify_all(self ref) Void
}
```

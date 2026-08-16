# Std.Sync API

## Overview
This page lists the public API of module `Std.Sync` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let make_channel[T Any](capacity UInt) Pair[SendChannel[T], RecvChannel[T]]
```

## Traits
(none)

## Types
```koral
public type AtomicBool

public type AtomicInt

public type AtomicUInt

public type SendChannel[T Any]

public type RecvChannel[T Any]

public type LatchGate

public type Lazy[T Any]

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
    public load(*self) Bool
    public store(*self, value Bool) Void
    public swap(*self, value Bool) Bool
    public compare_exchange(*self, expected: Bool, desired: Bool) Bool
}

given AtomicBool as ToString {
    public to_string(*self) String
}

given AtomicInt {
    public new(value Int) AtomicInt
    public load(*self) Int
    public store(*self, value Int) Void
    public swap(*self, value Int) Int
    public compare_exchange(*self, expected: Int, desired: Int) Bool
    public fetch_add(*self, delta Int) Int
    public fetch_sub(*self, delta Int) Int
}

given AtomicInt as ToString {
    public to_string(*self) String
}

given AtomicUInt {
    public new(value UInt) AtomicUInt
    public load(*self) UInt
    public store(*self, value UInt) Void
    public swap(*self, value UInt) UInt
    public compare_exchange(*self, expected: UInt, desired: UInt) Bool
    public fetch_add(*self, delta UInt) UInt
    public fetch_sub(*self, delta UInt) UInt
}

given AtomicUInt as ToString {
    public to_string(*self) String
}

given[T Any] SendChannel[T] {
    public send(*self, value T) Result[Void]
    public try_send(*self, value T) Result[Bool]
}

given[T Any] RecvChannel[T] {
    public recv(*self) Result[T]
    public try_recv(*self) Result[Option[T]]
}

given LatchGate {
    public new(count UInt) LatchGate
    public latch(*self, count UInt) Void
    public unlatch(*self) Void
    public unlatch_and_wait(*self) Void
    public wait(*self) Void
}

given[T Any] Lazy[T] {
    public new(f Func[T]) Lazy[T]
    public get(*self) T
    public is_initialized(*self) Bool
}

given Mutex {
    public new() Mutex
    public lock(*self) Void
    public try_lock(*self) Bool
    public unlock(*self) Void
    public condvar(*self) MutexCondvar
}

given MutexCondvar {
    public wait(*self) Void
    public notify(*self) Void
    public notify_all(*self) Void
}

given Semaphore {
    public new(permits UInt) Semaphore
    public acquire(*self) Void
    public try_acquire(*self) Bool
    public release(*self) Void
}

given SharedMutex {
    public new() SharedMutex
    public lock(*self) Void
    public unlock(*self) Void
    public try_lock(*self) Bool
    public lock_shared(*self) Void
    public unlock_shared(*self) Void
    public try_lock_shared(*self) Bool
    public condvar(*self) SharedMutexCondvar
}

given SharedMutexCondvar {
    public wait(*self) Void
    public notify(*self) Void
    public notify_all(*self) Void
}
```

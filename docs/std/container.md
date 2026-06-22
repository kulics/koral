# Std.Container API

## Overview
This page lists the public API of module `Std.Container` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

## Types
```koral
public type PriorityQueue[T Ord]

public type PriorityQueueIterator[T Ord]

public type Queue[T Any]

public type QueueIterator[T Any]

public type Stack[T Any]

public type StackIterator[T Any]
```

## Given Implementations
```koral
given[T Ord and Deref] PriorityQueue[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self ref mut) Void
    public push(self ref mut, value T) Void
    public pop(self ref mut) Option[T]
    public peek(self ref) Option[T]
}

given[T Ord and Deref] PriorityQueue[T] as Iterable[T, PriorityQueueIterator[T]] {
    public iterator(self ref) PriorityQueueIterator[T]
}

given[T Ord and Deref] PriorityQueueIterator[T] as Iterator[T] {
    public next(self ref mut) Option[T]
}

given[T Deref] Queue[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self ref mut) Void
    public push(self ref mut, value T) Void
    public pop(self ref mut) Option[T]
    public peek(self ref) Option[T]
}

given[T Deref] Queue[T] as Iterable[T, QueueIterator[T]] {
    public iterator(self ref) QueueIterator[T]
}

given[T Deref] QueueIterator[T] as Iterator[T] {
    public next(self ref mut) Option[T]
}

given[T Deref] Stack[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self ref mut) Void
    public push(self ref mut, value T) Void
    public pop(self ref mut) Option[T]
    public peek(self ref) Option[T]
}

given[T Deref] Stack[T] as Iterable[T, StackIterator[T]] {
    public iterator(self ref) StackIterator[T]
}

given[T Deref] StackIterator[T] as Iterator[T] {
    public next(self ref mut) Option[T]
}
```

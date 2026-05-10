# Std.Container API

## Overview
This page lists the public API of module `Std.Container` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

## Types
```koral
public type Deque[T Any]

public type DequeIterator[T Any]

public type PriorityQueue[T Ord]

public type PriorityQueueIterator[T Ord]

public type Queue[T Any]

public type QueueIterator[T Any]

public type Stack[T Any]

public type StackIterator[T Any]
```

## Given Implementations
```koral
given[T Deref] Deque[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public reserve(self mut ref, additional UInt) Void
    public is_empty(self ref) Bool
    public push_back(self mut ref, value T) Void
    public push_front(self mut ref, value T) Void
    public pop_front(self mut ref) Option[T]
    public pop_back(self mut ref) Option[T]
    public first(self ref) Option[T]
    public last(self ref) Option[T]
    public get(self ref, index UInt) Option[T]
    public clear(self mut ref) Void
    public reverse(self mut ref) Void
    public retain(self mut ref, predicate Func[T, Bool]) Void
}

given[T Eq and Deref] Deque[T] {
    public contains(self ref, value T) Bool
}

given[T Deref] Deque[T] as Iterable[T, DequeIterator[T]] {
    public iterator(self ref) DequeIterator[T]
}

given[T Deref] DequeIterator[T] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Deref] Deque[T] as Index[UInt, T] {
    public ref_at(self ref, key UInt) ref T
}

given[T Deref] Deque[T] as MutIndex[UInt, T] {
    public mut_ref_at(self mut ref, key UInt) mut ref T
}

given[T Ord and Deref] PriorityQueue[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) Option[T]
    public peek(self ref) Option[T]
}

given[T Ord and Deref] PriorityQueue[T] as Iterable[T, PriorityQueueIterator[T]] {
    public iterator(self ref) PriorityQueueIterator[T]
}

given[T Ord and Deref] PriorityQueueIterator[T] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Deref] Queue[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) Option[T]
    public peek(self ref) Option[T]
}

given[T Deref] Queue[T] as Iterable[T, QueueIterator[T]] {
    public iterator(self ref) QueueIterator[T]
}

given[T Deref] QueueIterator[T] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Deref] Stack[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) Option[T]
    public peek(self ref) Option[T]
}

given[T Deref] Stack[T] as Iterable[T, StackIterator[T]] {
    public iterator(self ref) StackIterator[T]
}

given[T Deref] StackIterator[T] as Iterator[T] {
    public next(self mut ref) Option[T]
}
```

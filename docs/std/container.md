# Std.Container API

## Overview
This page lists the public API of module `Std.Container` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

## Types
```koral
public type mutable PriorityQueue[T Ord];

public type mutable PriorityQueueIterator[T Ord];

public type mutable Queue[T Any];

public type mutable QueueIterator[T Any];

public type mutable Stack[T Any];

public type mutable StackIterator[T Any];
```

## Given Implementations
```koral
given[T Ord] PriorityQueue[T] {
    public new() Self;
    public with_capacity(capacity UInt) Self;
    public count(self) UInt;
    public is_empty(self) Bool;
    public clear(self) Void;
    public push(self, value T) Void;
    public pop(self) Option[T];
    public peek(self) Option[T];
};

given[T Ord] PriorityQueue[T] as Iterable[T, PriorityQueueIterator[T]] {
    public iterator(self) PriorityQueueIterator[T];
};

given[T Ord] PriorityQueueIterator[T] as Iterator[T] {
    public next(self) Option[T];
};

given[T Any] Queue[T] {
    public new() Self;
    public with_capacity(capacity UInt) Self;
    public count(self) UInt;
    public is_empty(self) Bool;
    public clear(self) Void;
    public push(self, value T) Void;
    public pop(self) Option[T];
    public peek(self) Option[T];
};

given[T Any] Queue[T] as Default {
    public default() Self;
};

given[T Any] Queue[T] as Iterable[T, QueueIterator[T]] {
    public iterator(self) QueueIterator[T];
};

given[T Any] QueueIterator[T] as Iterator[T] {
    public next(self) Option[T];
};

given[T Any] Stack[T] {
    public new() Self;
    public with_capacity(capacity UInt) Self;
    public count(self) UInt;
    public is_empty(self) Bool;
    public clear(self) Void;
    public push(self, value T) Void;
    public pop(self) Option[T];
    public peek(self) Option[T];
};

given[T Any] Stack[T] as Default {
    public default() Self;
};

given[T Any] Stack[T] as Iterable[T, StackIterator[T]] {
    public iterator(self) StackIterator[T];
};

given[T Any] StackIterator[T] as Iterator[T] {
    public next(self) Option[T];
};
```

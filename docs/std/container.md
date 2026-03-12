# Std.Container API

## Overview
This page lists the public API of module `Std.Container` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
(none)

## Traits
(none)

## Types
```koral
public type [T Any]Deque

public type [T Any]DequeIterator

public type [T Ord]PriorityQueue

public type [T Ord]PriorityQueueIterator

public type [T Any]Queue

public type [T Any]QueueIterator

public type [T Any]Stack

public type [T Any]StackIterator
```

## Given Implementations
```koral
given[T Any] [T]Deque {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public reserve(self ref, additional UInt) Void
    public is_empty(self) Bool
    public push_back(self ref, value T) Void
    public push_front(self ref, value T) Void
    public pop_front(self ref) [T]Option
    public pop_back(self ref) [T]Option
    public first(self) [T]Option
    public last(self) [T]Option
    public get(self, index UInt) [T]Option
    public clear(self ref) Void
    public reverse(self ref) Void
    public retain(self ref, predicate [T, Bool]Func) Void
}

given[T Eq] [T]Deque {
    public contains(self, value T) Bool
}

given[T Any] [T]Deque [T, [T]DequeIterator]Iterable {
    public iterator(self) [T]DequeIterator
}

given[T Any] [T]DequeIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any] [T]Deque [UInt, T]Index {
    public at(self, key UInt) T
}

given[T Any] [T]Deque [UInt, T]MutIndex {
    public set_at(self ref, key UInt, value T) Void
}

given[T Ord] [T]PriorityQueue {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public is_empty(self) Bool
    public clear(self ref) Void
    public push(self ref, value T) Void
    public pop(self ref) [T]Option
    public peek(self) [T]Option
}

given[T Ord] [T]PriorityQueue [T, [T]PriorityQueueIterator]Iterable {
    public iterator(self) [T]PriorityQueueIterator
}

given[T Ord] [T]PriorityQueueIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any] [T]Queue {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public is_empty(self) Bool
    public clear(self ref) Void
    public push(self ref, value T) Void
    public pop(self ref) [T]Option
    public peek(self) [T]Option
}

given[T Any] [T]Queue [T, [T]QueueIterator]Iterable {
    public iterator(self) [T]QueueIterator
}

given[T Any] [T]QueueIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any] [T]Stack {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public is_empty(self) Bool
    public clear(self ref) Void
    public push(self ref, value T) Void
    public pop(self ref) [T]Option
    public peek(self) [T]Option
}

given[T Any] [T]Stack [T, [T]StackIterator]Iterable {
    public iterator(self) [T]StackIterator
}

given[T Any] [T]StackIterator [T]Iterator {
    public next(self ref) [T]Option
}
```

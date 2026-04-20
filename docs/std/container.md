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
    public reserve(self mut ref, additional UInt) Void
    public is_empty(self) Bool
    public push_back(self mut ref, value T) Void
    public push_front(self mut ref, value T) Void
    public pop_front(self mut ref) [T]Option
    public pop_back(self mut ref) [T]Option
    public first(self) [T]Option
    public last(self) [T]Option
    public get(self, index UInt) [T]Option
    public clear(self mut ref) Void
    public reverse(self mut ref) Void
    public retain(self mut ref, predicate [T, Bool]Func) Void
}

given[T Eq] [T]Deque {
    public contains(self, value T) Bool
}

given[T Any] [T]Deque [T, [T]DequeIterator]Iterable {
    public iterator(self) [T]DequeIterator
}

given[T Any] [T]DequeIterator [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any] [T]Deque [UInt, T]Index {
    public ref_at(self ref, key UInt) T ref
}

given[T Any] [T]Deque [UInt, T]MutIndex {
    public mut_ref_at(self mut ref, key UInt) T mut ref
}

given[T Ord] [T]PriorityQueue {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public is_empty(self) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) [T]Option
    public peek(self) [T]Option
}

given[T Ord] [T]PriorityQueue [T, [T]PriorityQueueIterator]Iterable {
    public iterator(self) [T]PriorityQueueIterator
}

given[T Ord] [T]PriorityQueueIterator [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any] [T]Queue {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public is_empty(self) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) [T]Option
    public peek(self) [T]Option
}

given[T Any] [T]Queue [T, [T]QueueIterator]Iterable {
    public iterator(self) [T]QueueIterator
}

given[T Any] [T]QueueIterator [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any] [T]Stack {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public is_empty(self) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) [T]Option
    public peek(self) [T]Option
}

given[T Any] [T]Stack [T, [T]StackIterator]Iterable {
    public iterator(self) [T]StackIterator
}

given[T Any] [T]StackIterator [T]Iterator {
    public next(self mut ref) [T]Option
}
```

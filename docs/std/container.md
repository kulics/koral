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
given[T Deref] [T]Deque {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public reserve(self mut ref, additional UInt) Void
    public is_empty(self ref) Bool
    public push_back(self mut ref, value T) Void
    public push_front(self mut ref, value T) Void
    public pop_front(self mut ref) [T]Option
    public pop_back(self mut ref) [T]Option
    public first(self ref) [T]Option
    public last(self ref) [T]Option
    public get(self ref, index UInt) [T]Option
    public clear(self mut ref) Void
    public reverse(self mut ref) Void
    public retain(self mut ref, predicate [T, Bool]Func) Void
}

given[T Eq and Deref] [T]Deque {
    public contains(self ref, value T) Bool
}

given[T Deref] [T]Deque as [T, [T]DequeIterator]Iterable {
    public iterator(self ref) [T]DequeIterator
}

given[T Deref] [T]DequeIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Deref] [T]Deque as [UInt, T]Index {
    public ref_at(self ref, key UInt) T ref
}

given[T Deref] [T]Deque as [UInt, T]MutIndex {
    public mut_ref_at(self mut ref, key UInt) T mut ref
}

given[T Ord and Deref] [T]PriorityQueue {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) [T]Option
    public peek(self ref) [T]Option
}

given[T Ord and Deref] [T]PriorityQueue as [T, [T]PriorityQueueIterator]Iterable {
    public iterator(self ref) [T]PriorityQueueIterator
}

given[T Ord and Deref] [T]PriorityQueueIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Deref] [T]Queue {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) [T]Option
    public peek(self ref) [T]Option
}

given[T Deref] [T]Queue as [T, [T]QueueIterator]Iterable {
    public iterator(self ref) [T]QueueIterator
}

given[T Deref] [T]QueueIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Deref] [T]Stack {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public push(self mut ref, value T) Void
    public pop(self mut ref) [T]Option
    public peek(self ref) [T]Option
}

given[T Deref] [T]Stack as [T, [T]StackIterator]Iterable {
    public iterator(self ref) [T]StackIterator
}

given[T Deref] [T]StackIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}
```

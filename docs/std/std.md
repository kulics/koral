# Std API

## Overview
This page lists the public API of module `Std` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let sleep(d Duration) Void

public let make_bytes(count UInt) List[UInt8]

public let make_uninitialized_bytes(count UInt) List[UInt8]

public let box[T Any](mut v T) mut ref T

public let max[T Ord](a T, b T) T

public let min[T Ord](a T, b T) T

public foreign let exit(code Int) Never

public foreign let abort() Never

public let last_error_message() String

public let args() List[String]

public let panic(message String) Never

public let assert(condition Bool, message String) Void

public let print[T ToString](value T) Void

public let println[T ToString](value T) Void

public let eprint[T ToString](value T) Void

public let eprintln[T ToString](value T) Void

public let scanln() Option[String]
```

## Traits
```koral
public trait Zero {
    zero() Self
}

public trait One {
    one() Self
}

public trait Add[R Any] {
    add(self, other R) Self
}

public trait Sub[R Any] {
    sub(self, other R) Self
}

public trait Neg {
    neg(self) Self
}

public trait Mul[R Any] {
    mul(self, other R) Self
}

public trait Div[R Any] {
    div(self, other R) Self
}

public trait Rem[R Any] {
    rem(self, other R) Self
}

public trait Eq {
    equals(self, other Self) Bool
}

public trait Ord Eq {
    compare(self, other Self) Int
}

public trait Bounded Ord {
    max_value() Self
    min_value() Self
}

public trait Iterator[T Any] {
    next(self mut ref) Option[T]
}

public trait Iterable[T Any, R Iterator[T]] {
    iterator(self ref) R
}

public trait Step Bounded {
    succ(self) Option[Self]
    pred(self) Option[Self]
}

public trait ToString {
    to_string(self ref) String
}

public trait Hash Eq {
    hash(self) UInt
}

public trait Error {
    message(self ref) String
}

public trait Drop {
    drop(source mut ptr Self) Void
}
```

## Types
```koral
public type Deque[T Any]

public type DequeIterator[T Any]

public type Dict[K Hash, V Any]

public type DictIterator[K Hash, V Any]

public type DictKeysIterator[K Hash, V Any]

public type DictValuesIterator[K Hash, V Any]

public type Duration

public type FilterIterator[T Any, R Iterator[T]]

public type MapIterator[T Any, U Any, R Iterator[T]]

public type FilterMapIterator[T Any, U Any, R Iterator[T]]

public type TakeIterator[T Any, R Iterator[T]]

public type SkipIterator[T Any, R Iterator[T]]

public type StepIterator[T Any, R Iterator[T]]

public type EnumerateIterator[T Any, R Iterator[T]]

public type InspectIterator[T Any, R Iterator[T]]

public type IntersperseIterator[T Any, R Iterator[T]]

public type TakeWhileIterator[T Any, R Iterator[T]]

public type SkipWhileIterator[T Any, R Iterator[T]]

public type ChainIterator[T Any, R1 Iterator[T], R2 Iterator[T]]

public type ZipIterator[A Any, B Any, R1 Iterator[A], R2 Iterator[B]]

public type FlatMapIterator[T Any, U Any, R Iterator[T], InnerR Iterator[U]]

public type List[T Any]

public type ListIterator[T Any]

public type Option[T Any] {
    None(),
    Some(value T),
}

public type Range[T Ord] {
    Closed(start T, end T),
    ClosedOpen(start T, end T),
    OpenClosed(start T, end T),
    Open(start T, end T),
    From(start T),
    After(start T),
    To(end T),
    Until(end T),
    Full(),
}

public type SliceSpec

public type RangeIterator[T Step]

public type Result[T Any] {
    Ok(value T),
    Error(error ref Error),
}

public type Rune

public type Set[T Hash]

public type SetIterator[T Hash]

public type String

public type StringSplitAsciiWhitespaceIterator

public type StringSplitIterator

public type StringLinesIterator

public type StringBytesIterator

public type StringRunesIterator

public type Pair[T Any, U Any](
    first T,
    second U,
)
```

## Given Implementations
```koral
intrinsic given Int {
    public wrapping_add(self, other Int) Int
    public wrapping_sub(self, other Int) Int
    public wrapping_mul(self, other Int) Int
    public wrapping_div(self, other Int) Int
    public wrapping_rem(self, other Int) Int
    public wrapping_neg(self) Int
    public wrapping_shl(self, other UInt32) Int
    public wrapping_shr(self, other UInt32) Int
}

intrinsic given Int8 {
    public wrapping_add(self, other Int8) Int8
    public wrapping_sub(self, other Int8) Int8
    public wrapping_mul(self, other Int8) Int8
    public wrapping_div(self, other Int8) Int8
    public wrapping_rem(self, other Int8) Int8
    public wrapping_neg(self) Int8
    public wrapping_shl(self, other UInt32) Int8
    public wrapping_shr(self, other UInt32) Int8
}

intrinsic given Int16 {
    public wrapping_add(self, other Int16) Int16
    public wrapping_sub(self, other Int16) Int16
    public wrapping_mul(self, other Int16) Int16
    public wrapping_div(self, other Int16) Int16
    public wrapping_rem(self, other Int16) Int16
    public wrapping_neg(self) Int16
    public wrapping_shl(self, other UInt32) Int16
    public wrapping_shr(self, other UInt32) Int16
}

intrinsic given Int32 {
    public wrapping_add(self, other Int32) Int32
    public wrapping_sub(self, other Int32) Int32
    public wrapping_mul(self, other Int32) Int32
    public wrapping_div(self, other Int32) Int32
    public wrapping_rem(self, other Int32) Int32
    public wrapping_neg(self) Int32
    public wrapping_shl(self, other UInt32) Int32
    public wrapping_shr(self, other UInt32) Int32
}

intrinsic given Int64 {
    public wrapping_add(self, other Int64) Int64
    public wrapping_sub(self, other Int64) Int64
    public wrapping_mul(self, other Int64) Int64
    public wrapping_div(self, other Int64) Int64
    public wrapping_rem(self, other Int64) Int64
    public wrapping_neg(self) Int64
    public wrapping_shl(self, other UInt32) Int64
    public wrapping_shr(self, other UInt32) Int64
}

intrinsic given UInt {
    public wrapping_add(self, other UInt) UInt
    public wrapping_sub(self, other UInt) UInt
    public wrapping_mul(self, other UInt) UInt
    public wrapping_div(self, other UInt) UInt
    public wrapping_rem(self, other UInt) UInt
    public wrapping_shl(self, other UInt32) UInt
    public wrapping_shr(self, other UInt32) UInt
}

intrinsic given UInt8 {
    public wrapping_add(self, other UInt8) UInt8
    public wrapping_sub(self, other UInt8) UInt8
    public wrapping_mul(self, other UInt8) UInt8
    public wrapping_div(self, other UInt8) UInt8
    public wrapping_rem(self, other UInt8) UInt8
    public wrapping_shl(self, other UInt32) UInt8
    public wrapping_shr(self, other UInt32) UInt8
}

intrinsic given UInt16 {
    public wrapping_add(self, other UInt16) UInt16
    public wrapping_sub(self, other UInt16) UInt16
    public wrapping_mul(self, other UInt16) UInt16
    public wrapping_div(self, other UInt16) UInt16
    public wrapping_rem(self, other UInt16) UInt16
    public wrapping_shl(self, other UInt32) UInt16
    public wrapping_shr(self, other UInt32) UInt16
}

intrinsic given UInt32 {
    public wrapping_add(self, other UInt32) UInt32
    public wrapping_sub(self, other UInt32) UInt32
    public wrapping_mul(self, other UInt32) UInt32
    public wrapping_div(self, other UInt32) UInt32
    public wrapping_rem(self, other UInt32) UInt32
    public wrapping_shl(self, other UInt32) UInt32
    public wrapping_shr(self, other UInt32) UInt32
}

intrinsic given UInt64 {
    public wrapping_add(self, other UInt64) UInt64
    public wrapping_sub(self, other UInt64) UInt64
    public wrapping_mul(self, other UInt64) UInt64
    public wrapping_div(self, other UInt64) UInt64
    public wrapping_rem(self, other UInt64) UInt64
    public wrapping_shl(self, other UInt32) UInt64
    public wrapping_shr(self, other UInt32) UInt64
}

given Int as Zero {
    public zero() Int
}

given Int as One {
    public one() Int
}

given Int as Add[Int] {
    public add(self, other Int) Int
}

given Int as Sub[Int] {
    public sub(self, other Int) Int
}

given Int as Neg {
    public neg(self) Int
}

given Int as Mul[Int] {
    public mul(self, other Int) Int
}

given Int as Div[Int] {
    public div(self, other Int) Int
}

given Int as Rem[Int] {
    public rem(self, other Int) Int
}

given Int8 as Zero {
    public zero() Int8
}

given Int8 as One {
    public one() Int8
}

given Int8 as Add[Int8] {
    public add(self, other Int8) Int8
}

given Int8 as Sub[Int8] {
    public sub(self, other Int8) Int8
}

given Int8 as Neg {
    public neg(self) Int8
}

given Int8 as Mul[Int8] {
    public mul(self, other Int8) Int8
}

given Int8 as Div[Int8] {
    public div(self, other Int8) Int8
}

given Int8 as Rem[Int8] {
    public rem(self, other Int8) Int8
}

given Int16 as Zero {
    public zero() Int16
}

given Int16 as One {
    public one() Int16
}

given Int16 as Add[Int16] {
    public add(self, other Int16) Int16
}

given Int16 as Sub[Int16] {
    public sub(self, other Int16) Int16
}

given Int16 as Neg {
    public neg(self) Int16
}

given Int16 as Mul[Int16] {
    public mul(self, other Int16) Int16
}

given Int16 as Div[Int16] {
    public div(self, other Int16) Int16
}

given Int16 as Rem[Int16] {
    public rem(self, other Int16) Int16
}

given Int32 as Zero {
    public zero() Int32
}

given Int32 as One {
    public one() Int32
}

given Int32 as Add[Int32] {
    public add(self, other Int32) Int32
}

given Int32 as Sub[Int32] {
    public sub(self, other Int32) Int32
}

given Int32 as Neg {
    public neg(self) Int32
}

given Int32 as Mul[Int32] {
    public mul(self, other Int32) Int32
}

given Int32 as Div[Int32] {
    public div(self, other Int32) Int32
}

given Int32 as Rem[Int32] {
    public rem(self, other Int32) Int32
}

given Int64 as Zero {
    public zero() Int64
}

given Int64 as One {
    public one() Int64
}

given Int64 as Add[Int64] {
    public add(self, other Int64) Int64
}

given Int64 as Sub[Int64] {
    public sub(self, other Int64) Int64
}

given Int64 as Neg {
    public neg(self) Int64
}

given Int64 as Mul[Int64] {
    public mul(self, other Int64) Int64
}

given Int64 as Div[Int64] {
    public div(self, other Int64) Int64
}

given Int64 as Rem[Int64] {
    public rem(self, other Int64) Int64
}

given UInt as Zero {
    public zero() UInt
}

given UInt as One {
    public one() UInt
}

given UInt as Add[UInt] {
    public add(self, other UInt) UInt
}

given UInt as Sub[UInt] {
    public sub(self, other UInt) UInt
}

given UInt as Mul[UInt] {
    public mul(self, other UInt) UInt
}

given UInt as Div[UInt] {
    public div(self, other UInt) UInt
}

given UInt as Rem[UInt] {
    public rem(self, other UInt) UInt
}

given UInt8 as Zero {
    public zero() UInt8
}

given UInt8 as One {
    public one() UInt8
}

given UInt8 as Add[UInt8] {
    public add(self, other UInt8) UInt8
}

given UInt8 as Sub[UInt8] {
    public sub(self, other UInt8) UInt8
}

given UInt8 as Mul[UInt8] {
    public mul(self, other UInt8) UInt8
}

given UInt8 as Div[UInt8] {
    public div(self, other UInt8) UInt8
}

given UInt8 as Rem[UInt8] {
    public rem(self, other UInt8) UInt8
}

given UInt16 as Zero {
    public zero() UInt16
}

given UInt16 as One {
    public one() UInt16
}

given UInt16 as Add[UInt16] {
    public add(self, other UInt16) UInt16
}

given UInt16 as Sub[UInt16] {
    public sub(self, other UInt16) UInt16
}

given UInt16 as Mul[UInt16] {
    public mul(self, other UInt16) UInt16
}

given UInt16 as Div[UInt16] {
    public div(self, other UInt16) UInt16
}

given UInt16 as Rem[UInt16] {
    public rem(self, other UInt16) UInt16
}

given UInt32 as Zero {
    public zero() UInt32
}

given UInt32 as One {
    public one() UInt32
}

given UInt32 as Add[UInt32] {
    public add(self, other UInt32) UInt32
}

given UInt32 as Sub[UInt32] {
    public sub(self, other UInt32) UInt32
}

given UInt32 as Mul[UInt32] {
    public mul(self, other UInt32) UInt32
}

given UInt32 as Div[UInt32] {
    public div(self, other UInt32) UInt32
}

given UInt32 as Rem[UInt32] {
    public rem(self, other UInt32) UInt32
}

given UInt64 as Zero {
    public zero() UInt64
}

given UInt64 as One {
    public one() UInt64
}

given UInt64 as Add[UInt64] {
    public add(self, other UInt64) UInt64
}

given UInt64 as Sub[UInt64] {
    public sub(self, other UInt64) UInt64
}

given UInt64 as Mul[UInt64] {
    public mul(self, other UInt64) UInt64
}

given UInt64 as Div[UInt64] {
    public div(self, other UInt64) UInt64
}

given UInt64 as Rem[UInt64] {
    public rem(self, other UInt64) UInt64
}

given Float32 as Zero {
    public zero() Float32
}

given Float32 as One {
    public one() Float32
}

given Float32 as Add[Float32] {
    public add(self, other Float32) Float32
}

given Float32 as Sub[Float32] {
    public sub(self, other Float32) Float32
}

given Float32 as Neg {
    public neg(self) Float32
}

given Float32 as Mul[Float32] {
    public mul(self, other Float32) Float32
}

given Float32 as Div[Float32] {
    public div(self, other Float32) Float32
}

given Float64 as Zero {
    public zero() Float64
}

given Float64 as One {
    public one() Float64
}

given Float64 as Add[Float64] {
    public add(self, other Float64) Float64
}

given Float64 as Sub[Float64] {
    public sub(self, other Float64) Float64
}

given Float64 as Neg {
    public neg(self) Float64
}

given Float64 as Mul[Float64] {
    public mul(self, other Float64) Float64
}

given Float64 as Div[Float64] {
    public div(self, other Float64) Float64
}

given String as Add[String] {
    public add(self, other String) String
}

given[T Deref] List[T] as Add[List[T]] {
    public add(self, other Self) Self
}

given Duration as Zero {
    public zero() Duration
}

given Duration as Add[Duration] {
    public add(self, other Duration) Duration
}

given Duration as Sub[Duration] {
    public sub(self, other Duration) Duration
}

given Duration as Neg {
    public neg(self) Duration
}

given Duration as Mul[Int] {
    public mul(self, k Int) Duration
}

given Duration as Div[Int] {
    public div(self, k Int) Duration
}

given Bool as Eq {
    public equals(self, other Bool) Bool
}

given Bool as Ord {
    public compare(self, other Bool) Int
}

given Int as Eq {
    public equals(self, other Int) Bool
}

given Int as Ord {
    public compare(self, other Int) Int
}

given Int as Bounded {
    public max_value() Self
    public min_value() Self
}

given Int8 as Eq {
    public equals(self, other Int8) Bool
}

given Int8 as Ord {
    public compare(self, other Int8) Int
}

given Int8 as Bounded {
    public max_value() Self
    public min_value() Self
}

given Int16 as Eq {
    public equals(self, other Int16) Bool
}

given Int16 as Ord {
    public compare(self, other Int16) Int
}

given Int16 as Bounded {
    public max_value() Self
    public min_value() Self
}

given Int32 as Eq {
    public equals(self, other Int32) Bool
}

given Int32 as Ord {
    public compare(self, other Int32) Int
}

given Int32 as Bounded {
    public max_value() Self
    public min_value() Self
}

given Int64 as Eq {
    public equals(self, other Int64) Bool
}

given Int64 as Ord {
    public compare(self, other Int64) Int
}

given Int64 as Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt as Eq {
    public equals(self, other UInt) Bool
}

given UInt as Ord {
    public compare(self, other UInt) Int
}

given UInt as Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt8 as Eq {
    public equals(self, other UInt8) Bool
}

given UInt8 as Ord {
    public compare(self, other UInt8) Int
}

given UInt8 as Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt16 as Eq {
    public equals(self, other UInt16) Bool
}

given UInt16 as Ord {
    public compare(self, other UInt16) Int
}

given UInt16 as Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt32 as Eq {
    public equals(self, other UInt32) Bool
}

given UInt32 as Ord {
    public compare(self, other UInt32) Int
}

given UInt32 as Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt64 as Eq {
    public equals(self, other UInt64) Bool
}

given UInt64 as Ord {
    public compare(self, other UInt64) Int
}

given UInt64 as Bounded {
    public max_value() Self
    public min_value() Self
}

given Float32 as Eq {
    public equals(self, other Float32) Bool
}

given Float32 as Ord {
    public compare(self, other Float32) Int
}

given Float32 as Bounded {
    public max_value() Self
    public min_value() Self
}

given Float64 as Eq {
    public equals(self, other Float64) Bool
}

given Float64 as Ord {
    public compare(self, other Float64) Int
}

given Float64 as Bounded {
    public max_value() Self
    public min_value() Self
}

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

given[K Hash, V Any] Dict[K, V] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public insert(self mut ref, key K, value V) Void
    public try_insert(self mut ref, key K, value V) Bool
    public insert_dict(self mut ref, other Dict[K, V]) Void
    public get(self ref, key K) Option[V]
    public get_or_insert(self mut ref, key K, value V) V
    public contains_key(self ref, key K) Bool
    public remove(self mut ref, key K) Void
    public try_remove(self mut ref, key K) Bool
    public take(self mut ref, key K) Option[V]
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public retain(self mut ref, predicate Func[K, V, Bool]) Void
}

given[K Hash, V Any] DictIterator[K, V] as Iterator[Pair[K, V]] {
    public next(self mut ref) Option[Pair[K, V]]
}

given[K Hash, V Any] DictKeysIterator[K, V] as Iterator[K] {
    public next(self mut ref) Option[K]
}

given[K Hash, V Any] DictValuesIterator[K, V] as Iterator[V] {
    public next(self mut ref) Option[V]
}

given[K Hash, V Any] Dict[K, V] {
    public keys(self ref) DictKeysIterator[K, V]
    public values(self ref) DictValuesIterator[K, V]
}

given[K Hash, V Any] Dict[K, V] as Iterable[Pair[K, V], DictIterator[K, V]] {
    public iterator(self ref) DictIterator[K, V]
}

given[T Deref] List[T] {
    public group_by[K Hash](self ref, key Func[T, K]) Dict[K, List[T]]
}

given Duration {
    public new(seconds: Int64, nanoseconds: Int64) Result[Duration]
    public as_nanoseconds(self) Int64
    public as_microseconds(self) Int64
    public as_milliseconds(self) Int64
    public as_seconds(self) Int64
    public as_minutes(self) Int64
    public as_hours(self) Int64
    public ratio(self, other Duration) Float64
}

given Duration as Eq {
    public equals(self, other Duration) Bool
}

given Duration as Ord {
    public compare(self, other Duration) Int
}

given[T Any, R Iterator[T]] FilterIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, U Any, R Iterator[T]] MapIterator[T, U, R] as Iterator[U] {
    public next(self mut ref) Option[U]
}

given[T Any, U Any, R Iterator[T]] FilterMapIterator[T, U, R] as Iterator[U] {
    public next(self mut ref) Option[U]
}

given[T Any, R Iterator[T]] TakeIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, R Iterator[T]] SkipIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, R Iterator[T]] StepIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, R Iterator[T]] EnumerateIterator[T, R] as Iterator[Pair[UInt, T]] {
    public next(self mut ref) Option[Pair[UInt, T]]
}

given[T Any, R Iterator[T]] InspectIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, R Iterator[T]] IntersperseIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, R Iterator[T]] TakeWhileIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, R Iterator[T]] SkipWhileIterator[T, R] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Any, R1 Iterator[T], R2 Iterator[T]] ChainIterator[T, R1, R2] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[A Any, B Any, R1 Iterator[A], R2 Iterator[B]] ZipIterator[A, B, R1, R2] as Iterator[Pair[A, B]] {
    public next(self mut ref) Option[Pair[A, B]]
}

given[T Any, U Any, R Iterator[T], InnerR Iterator[U]] FlatMapIterator[T, U, R, InnerR] as Iterator[U] {
    public next(self mut ref) Option[U]
}

given[T Any] Iterator[T] {
    public filter(self, fn Func[T, Bool]) FilterIterator[T, Self]
    public map[U Any](self, fn Func[T, U]) MapIterator[T, U, Self]
    public filter_map[U Any](self, fn Func[T, Option[U]]) FilterMapIterator[T, U, Self]
    public take(self, n UInt) TakeIterator[T, Self]
    public skip(self, n UInt) SkipIterator[T, Self]
    public step_by(self, n UInt) StepIterator[T, Self]
    public enumerate(self) EnumerateIterator[T, Self]
    public inspect(self, fn Func[T, Void]) InspectIterator[T, Self]
    public intersperse(self, v T) IntersperseIterator[T, Self]
    public take_while(self, fn Func[T, Bool]) TakeWhileIterator[T, Self]
    public skip_while(self, fn Func[T, Bool]) SkipWhileIterator[T, Self]
    public chain[R2 Iterator[T]](self, other R2) ChainIterator[T, Self, R2]
    public zip[U Any, R2 Iterator[U]](self, other R2) ZipIterator[T, U, Self, R2]
    public flat_map[U Any, InnerR Iterator[U]](self, fn Func[T, InnerR]) FlatMapIterator[T, U, Self, InnerR]
}

given[T Any] Iterator[T] {
    public fold[U Any](self, initial U, fn Func[U, T, U]) U
    public reduce(self, fn Func[T, T, T]) Option[T]
    public into_list(self) List[T]
    public for_each(self, fn Func[T, Void]) Void
    public count(self) UInt
    public first(self) Option[T]
    public last(self) Option[T]
    public nth(self, n UInt) Option[T]
    public position(self, fn Func[T, Bool]) Option[UInt]
    public find(self, fn Func[T, Bool]) Option[T]
    public find_map[U Any](self, fn Func[T, Option[U]]) Option[U]
    public any(self, fn Func[T, Bool]) Bool
    public all(self, fn Func[T, Bool]) Bool
    public is_empty(self) Bool
    public max_by[K Ord](self, fn Func[T, K]) Option[T]
    public min_by[K Ord](self, fn Func[T, K]) Option[T]
}

given[T Eq] Iterator[T] {
    public contains(self, value T) Bool
}

given[T Ord] Iterator[T] {
    public max(self) Option[T]
    public min(self) Option[T]
}

given[T Hash] Iterator[T] {
    public into_set(self) Set[T]
}

given[T Add[T] and Zero] Iterator[T] {
    public sum(self) T
}

given[T Mul[T] and One] Iterator[T] {
    public product(self) T
}

given[T Add[T] and Div[T] and Zero and One] Iterator[T] {
    public average(self) Option[T]
}

given[T Deref] List[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public reserve(self mut ref, additional UInt) Void
    public push(self mut ref, value T) Void
    public push_list(self mut ref, other List[T]) Void
    public push_sublist(self mut ref, other List[T], range Range[UInt]) Void
    public pop(self mut ref) Option[T]
    public insert_list_at(self mut ref, index UInt, other List[T]) Void
    public insert_sublist_at(self mut ref, index UInt, other List[T], range Range[UInt]) Void
    public insert_at(self mut ref, index UInt, value T) Void
    public remove_at(self mut ref, index UInt) Void
    public take_at(self mut ref, index UInt) T
    public get(self ref, index UInt) Option[T]
    public first(self ref) Option[T]
    public last(self ref) Option[T]
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public fill(self mut ref, value T) Void
    public map[U Deref](self ref, fn Func[T, U]) List[U]
    public reverse(self mut ref) Void
    public borrow_ptr(self ref) ptr T
    public borrow_mut_ptr(self mut ref) mut ptr T
    public slice_spec(self ref, range Range[UInt]) SliceSpec
    public sublist(self ref, range Range[UInt]) List[T]
    public enumerate(self ref) EnumerateIterator[T, ListIterator[T]]
    public retain(self mut ref, predicate Func[T, Bool]) Void
    public sort_by[K Ord](self mut ref, key Func[T, K]) Void
    public binary_search_by[K Ord](self ref, key Func[T, K], target K) Pair[UInt, Bool]
}

given[T Eq and Deref] List[T] as Eq {
    public equals(self, other List[T]) Bool
}

given[T Eq and Deref] List[T] {
    public contains(self ref, value T) Bool
    public dedup(self mut ref) Void
}

given[T Deref] ListIterator[T] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Deref] List[T] as Iterable[T, ListIterator[T]] {
    public iterator(self ref) ListIterator[T]
}

given[T Ord and Deref] List[T] {
    public binary_search(self ref, target T) Pair[UInt, Bool]
    public sort(self mut ref) Void
}

given[T Any] Option[T] {
    public is_some(self ref) Bool
    public is_none(self ref) Bool
    public unwrap(self) T
    public expect(self, message String) T
    public unwrap_or(self, default T) T
    public map[U Any](self, f Func[T, U]) Option[U]
    public filter(self, predicate Func[T, Bool]) Option[T]
}

given[T Eq] Option[T] as Eq {
    public equals(self, other Option[T]) Bool
}

intrinsic given[T Any] weakref T {
    public to_ref(self) Option[ref T]
}

intrinsic given[T Any] mut weakref T {
    public to_ref(self) Option[mut ref T]
}

given Float32 {
    public to_bits(self) UInt32
    public from_bits(bits UInt32) Float32
}

given Float64 {
    public to_bits(self) UInt64
    public from_bits(bits UInt64) Float64
}

given Float32 {
    public inf() Float32
    public nan() Float32
    public min_normal() Float32
    public min_denormal() Float32
    public is_nan(self) Bool
    public is_inf(self) Bool
    public is_normal(self) Bool
}

given Float64 {
    public inf() Float64
    public nan() Float64
    public min_normal() Float64
    public min_denormal() Float64
    public is_nan(self) Bool
    public is_inf(self) Bool
    public is_normal(self) Bool
}

given Float64 {
    public is_finite(self) Bool
    public is_sign_positive(self) Bool
    public is_sign_negative(self) Bool
}

given Float32 {
    public is_finite(self) Bool
    public is_sign_positive(self) Bool
    public is_sign_negative(self) Bool
}

given UInt {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
    public is_power_of_two(self) Bool
    public next_power_of_two(self) Self
}

given UInt64 {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
    public is_power_of_two(self) Bool
    public next_power_of_two(self) Self
}

given UInt32 {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
    public is_power_of_two(self) Bool
    public next_power_of_two(self) Self
}

given UInt16 {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
    public is_power_of_two(self) Bool
    public next_power_of_two(self) Self
}

given UInt8 {
    public is_ascii(self) Bool
    public is_ascii_alphabetic(self) Bool
    public is_ascii_alphanumeric(self) Bool
    public is_ascii_digit(self) Bool
    public is_ascii_hexdigit(self) Bool
    public is_ascii_whitespace(self) Bool
    public is_ascii_uppercase(self) Bool
    public is_ascii_lowercase(self) Bool
    public to_ascii_lowercase(self) UInt8
    public to_ascii_uppercase(self) UInt8
    public equals_ascii_ignore_case(self, other UInt8) Bool
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
    public is_power_of_two(self) Bool
    public next_power_of_two(self) Self
}

given Int {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
}

given Int64 {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
}

given Int32 {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
}

given Int16 {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
}

given Int8 {
    public count_ones(self) UInt
    public count_zeros(self) UInt
    public leading_zeros(self) UInt
    public trailing_zeros(self) UInt
    public leading_ones(self) UInt
    public trailing_ones(self) UInt
    public rotate_left(self, n UInt) Self
    public rotate_right(self, n UInt) Self
    public reverse_bits(self) Self
    public swap_bytes(self) Self
}

given SliceSpec {
    public new(offset: UInt, len: UInt) SliceSpec
    public start(self) UInt
    public end(self) UInt
    public len(self) UInt
}

given[T Ord] Range[T] {
    public contains(self ref, value T) Bool
    public is_empty(self ref) Bool
}

given Int as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given Int8 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given Int16 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given Int32 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given Int64 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given UInt as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given UInt8 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given UInt16 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given UInt32 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given UInt64 as Step {
    public succ(self) Option[Self]
    public pred(self) Option[Self]
}

given[T Step] RangeIterator[T] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given[T Step] Range[T] as Iterable[T, RangeIterator[T]] {
    public iterator(self ref) RangeIterator[T]
}

given[T Any] Result[T] {
    public is_ok(self ref) Bool
    public is_error(self ref) Bool
    public unwrap(self) T
    public expect(self, message String) T
    public unwrap_error(self) ref Error
    public unwrap_or(self, default T) T
    public map[U Any](self, f Func[T, U]) Result[U]
}

given Rune {
    public replacement_char() Rune
    public from_uint32(value UInt32) Result[Rune]
    public from_uint32_unchecked(value UInt32) Rune
    public to_uint32(self) UInt32
    public is_ascii(self) Bool
    public is_ascii_digit(self) Bool
    public is_ascii_hexdigit(self) Bool
    public is_ascii_whitespace(self) Bool
    public is_ascii_alphabetic(self) Bool
    public is_ascii_alphanumeric(self) Bool
    public is_ascii_uppercase(self) Bool
    public is_ascii_lowercase(self) Bool
    public to_ascii_lowercase(self) Rune
    public to_ascii_uppercase(self) Rune
    public is_valid(self) Bool
    public byte_count(self) UInt
    public is_newline(self) Bool
    public equals_ascii_ignore_case(self, other Rune) Bool
    public is_identifier_start(self) Bool
    public is_identifier_continue(self) Bool
}

given Rune as Eq {
    public equals(self, other Rune) Bool
}

given Rune as Ord {
    public compare(self, other Rune) Int
}

given Rune as ToString {
    public to_string(self ref) String
}

given[T Hash] Set[T] {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public insert(self mut ref, value T) Void
    public try_insert(self mut ref, value T) Bool
    public insert_set(self mut ref, other Set[T]) Void
    public contains(self ref, value T) Bool
    public remove(self mut ref, value T) Void
    public try_remove(self mut ref, value T) Bool
    public is_empty(self ref) Bool
    public is_subset_of(self ref, other Set[T]) Bool
    public is_superset_of(self ref, other Set[T]) Bool
    public clear(self mut ref) Void
    public retain(self mut ref, predicate Func[T, Bool]) Void
    public union(self ref, other Set[T]) Set[T]
    public intersection(self ref, other Set[T]) Set[T]
    public difference(self ref, other Set[T]) Set[T]
    public symmetric_difference(self ref, other Set[T]) Set[T]
}

given[T Hash] Set[T] as Iterable[T, SetIterator[T]] {
    public iterator(self ref) SetIterator[T]
}

given[T Hash] SetIterator[T] as Iterator[T] {
    public next(self mut ref) Option[T]
}

given String {
    public from_utf8_ptr_unchecked(bytes ptr UInt8, len UInt) String
    public from_utf8_ptr(bytes ptr UInt8, len UInt) Result[String]
    public from_bytes(bytes List[UInt8]) Result[String]
    public from_bytes_unchecked(bytes List[UInt8]) String
    public from_cstring(cstr ptr UInt8) Result[String]
    public from_cstring_unchecked(cstr ptr UInt8) String
    public with_capacity(capacity UInt) String
    public new() String
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public capacity(self ref) UInt
    public borrow_ptr(self ref) ptr UInt8
    public to_bytes(self ref) List[UInt8]
    public get(self ref, index UInt) Option[UInt8]
    public push_byte(self mut ref, value UInt8) Void
    public push_string(self mut ref, other String) Void
    public push_substring(self mut ref, other String, range Range[UInt]) Void
    public reserve(self mut ref, capacity UInt) Void
    public starts_with(self ref, prefix String) Bool
    public ends_with(self ref, suffix String) Bool
    public find(self ref, pat String) Option[UInt]
    public find_last(self ref, pat String) Option[UInt]
    public is_rune_boundary(self ref, byte_index UInt) Bool
    public slice_spec(self ref, range Range[UInt]) SliceSpec
    public substring(self ref, range Range[UInt]) String
    public trim_ascii_start(self ref) String
    public trim_ascii_end(self ref) String
    public trim_ascii(self ref) String
    public is_ascii(self ref) Bool
    public is_ascii_whitespace(self ref) Bool
    public to_ascii_lowercase(self ref) String
    public to_ascii_uppercase(self ref) String
    public to_ascii_titlecase(self ref) String
    public find_from(self ref, start UInt, pat String) Option[UInt]
    public contains(self ref, pat String) Bool
    public repeat(self ref, times UInt) String
    public replace_n(self ref, pat String, n UInt, with: String) String
    public split_once(self ref, sep String) Option[Pair[String, String]]
    public split_last_once(self ref, sep String) Option[Pair[String, String]]
    public replace_all(self ref, pat String, with: String) String
    public split_ascii_whitespace(self ref) StringSplitAsciiWhitespaceIterator
    public split(self ref, sep String) StringSplitIterator
    public lines(self ref) StringLinesIterator
    public trim_prefix(self ref, prefix String) String
    public trim_suffix(self ref, suffix String) String
    public strip_prefix(self ref, prefix String) Option[String]
    public strip_suffix(self ref, suffix String) Option[String]
    public bytes(self ref) StringBytesIterator
    public runes(self ref) StringRunesIterator
    public to_runes(self ref) List[Rune]
    public push_rune(self mut ref, rune Rune) Void
}

given String as Eq {
    public equals(self, other String) Bool
}

given String as Ord {
    public compare(self, other String) Int
}

given String as Hash {
    public hash(self) UInt
}

given StringSplitAsciiWhitespaceIterator as Iterator[String] {
    public next(self mut ref) Option[String]
}

given StringSplitIterator as Iterator[String] {
    public next(self mut ref) Option[String]
}

given StringLinesIterator as Iterator[String] {
    public next(self mut ref) Option[String]
}

given StringRunesIterator as Iterator[Rune] {
    public next(self mut ref) Option[Rune]
}

given StringBytesIterator as Iterator[UInt8] {
    public next(self mut ref) Option[UInt8]
}

given String as ToString {
    public to_string(self ref) String
}

given Bool as ToString {
    public to_string(self ref) String
}

given Int as ToString {
    public to_string(self ref) String
}

given Int8 as ToString {
    public to_string(self ref) String
}

given Int16 as ToString {
    public to_string(self ref) String
}

given Int32 as ToString {
    public to_string(self ref) String
}

given Int64 as ToString {
    public to_string(self ref) String
}

given UInt as ToString {
    public to_string(self ref) String
}

given UInt8 as ToString {
    public to_string(self ref) String
}

given UInt16 as ToString {
    public to_string(self ref) String
}

given UInt32 as ToString {
    public to_string(self ref) String
}

given UInt64 as ToString {
    public to_string(self ref) String
}

given Float32 as ToString {
    public to_string(self ref) String
}

given Float64 as ToString {
    public to_string(self ref) String
}

given[T ToString, U ToString] Pair[T, U] as ToString {
    public to_string(self ref) String
}

given[T ToString] Option[T] as ToString {
    public to_string(self ref) String
}

given[T ToString and Deref] List[T] as ToString {
    public to_string(self ref) String
}

given[T ToString] Iterator[T] {
    public join_to_string(self, seperator String) String
}

given[T ToString and Deref] List[T] {
    public join_to_string(self, seperator String) String
}

given[K ToString and Hash, V ToString] Dict[K, V] as ToString {
    public to_string(self ref) String
}

given[T ToString and Hash] Set[T] as ToString {
    public to_string(self ref) String
}

given Duration as ToString {
    public to_string(self ref) String
}

given Hash {
    public combine_hash(self, value UInt) UInt
}

given String as Error {
    public message(self ref) String
}

given Bool as Hash {
    public hash(self) UInt
}

given UInt as Hash {
    public hash(self) UInt
}

given UInt8 as Hash {
    public hash(self) UInt
}

given UInt16 as Hash {
    public hash(self) UInt
}

given UInt32 as Hash {
    public hash(self) UInt
}

given UInt64 as Hash {
    public hash(self) UInt
}

given Int as Hash {
    public hash(self) UInt
}

given Int8 as Hash {
    public hash(self) UInt
}

given Int16 as Hash {
    public hash(self) UInt
}

given Int32 as Hash {
    public hash(self) UInt
}

given Int64 as Hash {
    public hash(self) UInt
}

given[T Any] ptr T as Eq {
    public equals(self, other ptr T) Bool
}

given[T Any] ptr T as Hash {
    public hash(self) UInt
}

given[T Any] mut ptr T as Eq {
    public equals(self, other mut ptr T) Bool
}

given[T Any] mut ptr T as Hash {
    public hash(self) UInt
}

given[T Eq and Deref] ref T as Eq {
    public equals(self, other ref T) Bool
}

given[T Eq and Deref] mut ref T as Eq {
    public equals(self, other mut ref T) Bool
}

given[T Hash and Deref] ref T as Hash {
    public hash(self) UInt
}

given[T Hash and Deref] mut ref T as Hash {
    public hash(self) UInt
}

given[T Ord and Deref] ref T as Ord {
    public compare(self, other ref T) Int
}

given[T Ord and Deref] mut ref T as Ord {
    public compare(self, other mut ref T) Int
}

given[T ToString and Deref] ref T as ToString {
    public to_string(self ref) String
}

given[T ToString and Deref] mut ref T as ToString {
    public to_string(self ref) String
}

given[T Eq, U Eq] Pair[T, U] as Eq {
    public equals(self, other Pair[T, U]) Bool
}

given[T Hash, U Hash] Pair[T, U] as Hash {
    public hash(self) UInt
}

given[T Ord, U Ord] Pair[T, U] as Ord {
    public compare(self, other Pair[T, U]) Int
}

given Ord {
    public clamp(self, min: Self, max: Self) Self
}
```

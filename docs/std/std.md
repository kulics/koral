# Std API

## Overview
This page lists the public API of module `Std` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let sleep(d Duration) Void

public let make_bytes(count UInt) [UInt8]List

public let make_uninitialized_bytes(count UInt) [UInt8]List

public let [T Any]box(v T) T ref

public let [T Ord]max(a T, b T) T

public let [T Ord]min(a T, b T) T

public foreign let exit(code Int) Never

public foreign let abort() Never

public let last_error_message() String

public let args() [String]List

public let panic(message String) Never

public let assert(condition Bool, message String) Void

public let [T ToString]print(value T) Void

public let [T ToString]println(value T) Void

public let [T ToString]eprint(value T) Void

public let [T ToString]eprintln(value T) Void

public let scanln() [String]Option
```

## Traits
```koral
public trait Add {
    add(self, other Self) Self
    zero() Self
}

public trait Sub Add {
    sub(self, other Self) Self
}

public trait Neg {
    neg(self) Self
}

public trait Mul {
    mul(self, other Self) Self
    one() Self
}

public trait Div Mul {
    div(self, other Self) Self
}

public trait Rem {
    rem(self, other Self) Self
}

public trait [Scalar Any]Scale {
    scale(self, k Scalar) Self
}

public trait [Scalar Any]InvScale [Scalar]Scale {
    inv_scale(self, k Scalar) Self
}

public trait [Vector Sub]Affine {
    add_vector(self, v Vector) Self
    sub_vector(self, v Vector) Self
    sub_point(self, other Self) Vector
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

public trait [T Any]Iterator {
    next(self ref) [T]Option
}

public trait [T Any, R [T]Iterator]Iterable {
    iterator(self) R
}

public trait Step Bounded {
    succ(self) [Self]Option
    pred(self) [Self]Option
}

public trait ToString {
    to_string(self) String
}

public trait Hash Eq {
    hash(self) UInt
}

public trait Error {
    message(self) String
}

public trait Drop {
    drop(self ref) Void
}

public trait [K Any, V Any]Index {
    at(self, key K) V
}

public trait [K Any, V Any]MutIndex [K, V]Index {
    set_at(self ref, key K, value V) Void
}
```

## Types
```koral
public type [K Hash, V Any]Dict

public type [K Hash, V Any]DictIterator

public type [K Hash, V Any]DictKeysIterator

public type [K Hash, V Any]DictValuesIterator

public type Duration

public type [T Any, R [T]Iterator]FilterIterator

public type [T Any, U Any, R [T]Iterator]MapIterator

public type [T Any, U Any, R [T]Iterator]FilterMapIterator

public type [T Any, R [T]Iterator]TakeIterator

public type [T Any, R [T]Iterator]SkipIterator

public type [T Any, R [T]Iterator]StepIterator

public type [T Any, R [T]Iterator]EnumerateIterator

public type [T Any, R [T]Iterator]InspectIterator

public type [T Any, R [T]Iterator]IntersperseIterator

public type [T Any, R [T]Iterator]TakeWhileIterator

public type [T Any, R [T]Iterator]SkipWhileIterator

public type [T Any, R1 [T]Iterator, R2 [T]Iterator]ChainIterator

public type [A Any, B Any, R1 [A]Iterator, R2 [B]Iterator]ZipIterator

public type [T Any, U Any, R [T]Iterator, InnerR [U]Iterator]FlatMapIterator

public type [T Any]List

public type [T Any]ListIterator

public type [T Any]Option {
    None(),
    Some(value T),
}

public type [T Ord]Range {
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

public type [T Step]RangeIterator

public type [T Any]Result {
    Ok(value T),
    Error(error Error ref),
}

public type Rune

public type [T Hash]Set

public type [T Hash]SetIterator

public type String

public type StringSplitAsciiWhitespaceIterator

public type StringSplitIterator

public type StringLinesIterator

public type StringBytesIterator

public type RunesIterator

public type [T Any, U Any]Pair(
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

given Int Add {
    public add(self, other Int) Int
    public zero() Int
}

given Int Sub {
    public sub(self, other Int) Int
}

given Int Neg {
    public neg(self) Int
}

given Int Mul {
    public mul(self, other Int) Int
    public one() Int
}

given Int Div {
    public div(self, other Int) Int
}

given Int Rem {
    public rem(self, other Int) Int
}

given Int8 Add {
    public add(self, other Int8) Int8
    public zero() Int8
}

given Int8 Sub {
    public sub(self, other Int8) Int8
}

given Int8 Neg {
    public neg(self) Int8
}

given Int8 Mul {
    public mul(self, other Int8) Int8
    public one() Int8
}

given Int8 Div {
    public div(self, other Int8) Int8
}

given Int8 Rem {
    public rem(self, other Int8) Int8
}

given Int16 Add {
    public add(self, other Int16) Int16
    public zero() Int16
}

given Int16 Sub {
    public sub(self, other Int16) Int16
}

given Int16 Neg {
    public neg(self) Int16
}

given Int16 Mul {
    public mul(self, other Int16) Int16
    public one() Int16
}

given Int16 Div {
    public div(self, other Int16) Int16
}

given Int16 Rem {
    public rem(self, other Int16) Int16
}

given Int32 Add {
    public add(self, other Int32) Int32
    public zero() Int32
}

given Int32 Sub {
    public sub(self, other Int32) Int32
}

given Int32 Neg {
    public neg(self) Int32
}

given Int32 Mul {
    public mul(self, other Int32) Int32
    public one() Int32
}

given Int32 Div {
    public div(self, other Int32) Int32
}

given Int32 Rem {
    public rem(self, other Int32) Int32
}

given Int64 Add {
    public add(self, other Int64) Int64
    public zero() Int64
}

given Int64 Sub {
    public sub(self, other Int64) Int64
}

given Int64 Neg {
    public neg(self) Int64
}

given Int64 Mul {
    public mul(self, other Int64) Int64
    public one() Int64
}

given Int64 Div {
    public div(self, other Int64) Int64
}

given Int64 Rem {
    public rem(self, other Int64) Int64
}

given UInt Add {
    public add(self, other UInt) UInt
    public zero() UInt
}

given UInt Sub {
    public sub(self, other UInt) UInt
}

given UInt Mul {
    public mul(self, other UInt) UInt
    public one() UInt
}

given UInt Div {
    public div(self, other UInt) UInt
}

given UInt Rem {
    public rem(self, other UInt) UInt
}

given UInt8 Add {
    public add(self, other UInt8) UInt8
    public zero() UInt8
}

given UInt8 Sub {
    public sub(self, other UInt8) UInt8
}

given UInt8 Mul {
    public mul(self, other UInt8) UInt8
    public one() UInt8
}

given UInt8 Div {
    public div(self, other UInt8) UInt8
}

given UInt8 Rem {
    public rem(self, other UInt8) UInt8
}

given UInt16 Add {
    public add(self, other UInt16) UInt16
    public zero() UInt16
}

given UInt16 Sub {
    public sub(self, other UInt16) UInt16
}

given UInt16 Mul {
    public mul(self, other UInt16) UInt16
    public one() UInt16
}

given UInt16 Div {
    public div(self, other UInt16) UInt16
}

given UInt16 Rem {
    public rem(self, other UInt16) UInt16
}

given UInt32 Add {
    public add(self, other UInt32) UInt32
    public zero() UInt32
}

given UInt32 Sub {
    public sub(self, other UInt32) UInt32
}

given UInt32 Mul {
    public mul(self, other UInt32) UInt32
    public one() UInt32
}

given UInt32 Div {
    public div(self, other UInt32) UInt32
}

given UInt32 Rem {
    public rem(self, other UInt32) UInt32
}

given UInt64 Add {
    public add(self, other UInt64) UInt64
    public zero() UInt64
}

given UInt64 Sub {
    public sub(self, other UInt64) UInt64
}

given UInt64 Mul {
    public mul(self, other UInt64) UInt64
    public one() UInt64
}

given UInt64 Div {
    public div(self, other UInt64) UInt64
}

given UInt64 Rem {
    public rem(self, other UInt64) UInt64
}

given Float32 Add {
    public add(self, other Float32) Float32
    public zero() Float32
}

given Float32 Sub {
    public sub(self, other Float32) Float32
}

given Float32 Neg {
    public neg(self) Float32
}

given Float32 Mul {
    public mul(self, other Float32) Float32
    public one() Float32
}

given Float32 Div {
    public div(self, other Float32) Float32
}

given Float64 Add {
    public add(self, other Float64) Float64
    public zero() Float64
}

given Float64 Sub {
    public sub(self, other Float64) Float64
}

given Float64 Neg {
    public neg(self) Float64
}

given Float64 Mul {
    public mul(self, other Float64) Float64
    public one() Float64
}

given Float64 Div {
    public div(self, other Float64) Float64
}

given String Add {
    public zero() String
    public add(self, other String) String
}

given Duration Add {
    public zero() Duration
    public add(self, other Duration) Duration
}

given Duration Sub {
    public sub(self, other Duration) Duration
}

given Duration Neg {
    public neg(self) Duration
}

given Duration [Int]Scale {
    public scale(self, k Int) Duration
}

given Duration [Int]InvScale {
    public inv_scale(self, k Int) Duration
}

given Bool Eq {
    public equals(self, other Bool) Bool
}

given Bool Ord {
    public compare(self, other Bool) Int
}

given Int Eq {
    public equals(self, other Int) Bool
}

given Int Ord {
    public compare(self, other Int) Int
}

given Int Bounded {
    public max_value() Self
    public min_value() Self
}

given Int8 Eq {
    public equals(self, other Int8) Bool
}

given Int8 Ord {
    public compare(self, other Int8) Int
}

given Int8 Bounded {
    public max_value() Self
    public min_value() Self
}

given Int16 Eq {
    public equals(self, other Int16) Bool
}

given Int16 Ord {
    public compare(self, other Int16) Int
}

given Int16 Bounded {
    public max_value() Self
    public min_value() Self
}

given Int32 Eq {
    public equals(self, other Int32) Bool
}

given Int32 Ord {
    public compare(self, other Int32) Int
}

given Int32 Bounded {
    public max_value() Self
    public min_value() Self
}

given Int64 Eq {
    public equals(self, other Int64) Bool
}

given Int64 Ord {
    public compare(self, other Int64) Int
}

given Int64 Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt Eq {
    public equals(self, other UInt) Bool
}

given UInt Ord {
    public compare(self, other UInt) Int
}

given UInt Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt8 Eq {
    public equals(self, other UInt8) Bool
}

given UInt8 Ord {
    public compare(self, other UInt8) Int
}

given UInt8 Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt16 Eq {
    public equals(self, other UInt16) Bool
}

given UInt16 Ord {
    public compare(self, other UInt16) Int
}

given UInt16 Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt32 Eq {
    public equals(self, other UInt32) Bool
}

given UInt32 Ord {
    public compare(self, other UInt32) Int
}

given UInt32 Bounded {
    public max_value() Self
    public min_value() Self
}

given UInt64 Eq {
    public equals(self, other UInt64) Bool
}

given UInt64 Ord {
    public compare(self, other UInt64) Int
}

given UInt64 Bounded {
    public max_value() Self
    public min_value() Self
}

given Float32 Eq {
    public equals(self, other Float32) Bool
}

given Float32 Ord {
    public compare(self, other Float32) Int
}

given Float32 Bounded {
    public max_value() Self
    public min_value() Self
}

given Float64 Eq {
    public equals(self, other Float64) Bool
}

given Float64 Ord {
    public compare(self, other Float64) Int
}

given Float64 Bounded {
    public max_value() Self
    public min_value() Self
}

given[K Hash, V Any] [K, V]Dict {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public insert(self ref, key K, value V) [V]Option
    public insert_dict(self ref, other [K, V]Dict) Void
    public get(self, key K) [V]Option
    public get_or_insert(self ref, key K, value V) V
    public contains_key(self, key K) Bool
    public remove(self ref, key K) [V]Option
    public is_empty(self) Bool
    public clear(self ref) Void
    public retain(self ref, predicate [K, V, Bool]Func) Void
}

given[K Hash, V Any] [K, V]DictIterator [[K, V]Pair]Iterator {
    public next(self ref) [[K, V]Pair]Option
}

given[K Hash, V Any] [K, V]DictKeysIterator [K]Iterator {
    public next(self ref) [K]Option
}

given[K Hash, V Any] [K, V]DictValuesIterator [V]Iterator {
    public next(self ref) [V]Option
}

given[K Hash, V Any] [K, V]Dict {
    public keys(self) [K, V]DictKeysIterator
    public values(self) [K, V]DictValuesIterator
}

given[K Hash, V Any] [K, V]Dict [[K, V]Pair, [K, V]DictIterator]Iterable {
    public iterator(self) [K, V]DictIterator
}

given[K Hash, V Any] [K, V]Dict [K, V]Index {
    public at(self, key K) V
}

given[T Any] [T]List {
    public [K Hash]group_by(self, key [T, K]Func) [K, [T]List]Dict
}

given Duration {
    public new(seconds: Int64, nanoseconds: Int64) [Duration]Result
    public as_nanoseconds(self) Int64
    public as_microseconds(self) Int64
    public as_milliseconds(self) Int64
    public as_seconds(self) Int64
    public as_minutes(self) Int64
    public as_hours(self) Int64
    public ratio(self, other Duration) Float64
}

given Duration Eq {
    public equals(self, other Duration) Bool
}

given Duration Ord {
    public compare(self, other Duration) Int
}

given[T Any, R [T]Iterator] [T, R]FilterIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, U Any, R [T]Iterator] [T, U, R]MapIterator [U]Iterator {
    public next(self ref) [U]Option
}

given[T Any, U Any, R [T]Iterator] [T, U, R]FilterMapIterator [U]Iterator {
    public next(self ref) [U]Option
}

given[T Any, R [T]Iterator] [T, R]TakeIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]SkipIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]StepIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]EnumerateIterator [[UInt, T]Pair]Iterator {
    public next(self ref) [[UInt, T]Pair]Option
}

given[T Any, R [T]Iterator] [T, R]InspectIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]IntersperseIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]TakeWhileIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]SkipWhileIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any, R1 [T]Iterator, R2 [T]Iterator] [T, R1, R2]ChainIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[A Any, B Any, R1 [A]Iterator, R2 [B]Iterator] [A, B, R1, R2]ZipIterator [[A, B]Pair]Iterator {
    public next(self ref) [[A, B]Pair]Option
}

given[T Any, U Any, R [T]Iterator, InnerR [U]Iterator] [T, U, R, InnerR]FlatMapIterator [U]Iterator {
    public next(self ref) [U]Option
}

given[T Any] [T]Iterator {
    public filter(self, fn [T, Bool]Func) [T, Self]FilterIterator
    public [U Any]map(self, fn [T, U]Func) [T, U, Self]MapIterator
    public [U Any]filter_map(self, fn [T, [U]Option]Func) [T, U, Self]FilterMapIterator
    public take(self, n UInt) [T, Self]TakeIterator
    public skip(self, n UInt) [T, Self]SkipIterator
    public step_by(self, n UInt) [T, Self]StepIterator
    public enumerate(self) [T, Self]EnumerateIterator
    public inspect(self, fn [T, Void]Func) [T, Self]InspectIterator
    public intersperse(self, v T) [T, Self]IntersperseIterator
    public take_while(self, fn [T, Bool]Func) [T, Self]TakeWhileIterator
    public skip_while(self, fn [T, Bool]Func) [T, Self]SkipWhileIterator
    public [R2 [T]Iterator]chain(self, other R2) [T, Self, R2]ChainIterator
    public [U Any, R2 [U]Iterator]zip(self, other R2) [T, U, Self, R2]ZipIterator
    public [U Any, InnerR [U]Iterator]flat_map(self, fn [T, InnerR]Func) [T, U, Self, InnerR]FlatMapIterator
}

given[T Any] [T]Iterator {
    public [U Any]fold(self, initial U, fn [U, T, U]Func) U
    public reduce(self, fn [T, T, T]Func) [T]Option
    public to_list(self) [T]List
    public for_each(self, fn [T, Void]Func) Void
    public count(self) UInt
    public first(self) [T]Option
    public last(self) [T]Option
    public nth(self, n UInt) [T]Option
    public position(self, fn [T, Bool]Func) [UInt]Option
    public find(self, fn [T, Bool]Func) [T]Option
    public [U Any]find_map(self, fn [T, [U]Option]Func) [U]Option
    public any(self, fn [T, Bool]Func) Bool
    public all(self, fn [T, Bool]Func) Bool
    public is_empty(self) Bool
    public [K Ord]max_by(self, fn [T, K]Func) [T]Option
    public [K Ord]min_by(self, fn [T, K]Func) [T]Option
}

given[T Eq] [T]Iterator {
    public contains(self, value T) Bool
}

given[T Ord] [T]Iterator {
    public max(self) [T]Option
    public min(self) [T]Option
}

given[T Hash] [T]Iterator {
    public to_set(self) [T]Set
}

given[T Add] [T]Iterator {
    public sum(self) T
}

given[T Mul] [T]Iterator {
    public product(self) T
}

given[T Add and Div] [T]Iterator {
    public average(self) [T]Option
}

given[T Any] [T]List {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public reserve(self ref, additional UInt) Void
    public push(self ref, value T) Void
    public resolve_indices(self, range [UInt]Range) [[UInt, UInt]Pair]Result
    public push_list(self ref, other [T]List) Void
    public push_sublist(self ref, other [T]List, range [UInt]Range) Void
    public pop(self ref) [T]Option
    public insert_list_at(self ref, index UInt, other [T]List) Void
    public insert_sublist_at(self ref, index UInt, other [T]List, range [UInt]Range) Void
    public insert_at(self ref, index UInt, value T) Void
    public remove_at(self ref, index UInt) T
    public get(self, index UInt) [T]Option
    public first(self) [T]Option
    public last(self) [T]Option
    public is_empty(self) Bool
    public clear(self ref) Void
    public fill(self ref, value T) Void
    public [U Any]map(self, fn [T, U]Func) [U]List
    public reverse(self ref) Void
    public borrow_ptr(self) T ptr
    public borrow_mut_ptr(self ref) T ptr
    public sublist(self, range [UInt]Range) [T]List
    public zero() Self
    public add(self, other Self) Self
    public enumerate(self) [T, [T]ListIterator]EnumerateIterator
    public retain(self ref, predicate [T, Bool]Func) Void
    public [K Ord]sort_by(self ref, key [T, K]Func) Void
    public [K Ord]binary_search_by(self, key [T, K]Func, target K) [UInt, Bool]Pair
}

given[T Eq] [T]List Eq {
    public equals(self, other [T]List) Bool
}

given[T Eq] [T]List {
    public contains(self, value T) Bool
    public dedup(self ref) Void
}

given[T Any] [T]ListIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Any] [T]List [T, [T]ListIterator]Iterable {
    public iterator(self) [T]ListIterator
}

given[T Any] [T]List [UInt, T]Index {
    public at(self, key UInt) T
}

given[T Any] [T]List [UInt, T]MutIndex {
    public set_at(self ref, key UInt, value T) Void
}

given[T Ord] [T]List {
    public binary_search(self, target T) [UInt, Bool]Pair
    public sort(self ref) Void
}

given[T Any] [T]Option {
    public is_some(self) Bool
    public is_none(self) Bool
    public unwrap(self) T
    public expect(self, message String) T
    public unwrap_or(self, default T) T
    public [U Any]map(self, f [T, U]Func) [U]Option
    public filter(self, predicate [T, Bool]Func) [T]Option
}

given[T Eq] [T]Option Eq {
    public equals(self, other [T]Option) Bool
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

given[T Ord] [T]Range {
    public contains(self, value T) Bool
    public is_empty(self) Bool
}

given Int Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int8 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int16 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int32 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int64 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt8 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt16 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt32 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt64 Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given[T Step] [T]RangeIterator [T]Iterator {
    public next(self ref) [T]Option
}

given[T Step] [T]Range [T, [T]RangeIterator]Iterable {
    public iterator(self) [T]RangeIterator
}

given[T Any] [T]Result {
    public is_ok(self) Bool
    public is_error(self) Bool
    public unwrap(self) T
    public expect(self, message String) T
    public unwrap_error(self) Error ref
    public unwrap_or(self, default T) T
    public [U Any]map(self, f [T, U]Func) [U]Result
}

given Rune {
    public replacement_char() Rune
    public from_uint32(value UInt32) [Rune]Result
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

given Rune Eq {
    public equals(self, other Rune) Bool
}

given Rune Ord {
    public compare(self, other Rune) Int
}

given Rune ToString {
    public to_string(self) String
}

given[T Hash] [T]Set {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self) UInt
    public insert(self ref, value T) Bool
    public insert_set(self ref, other [T]Set) Void
    public contains(self, value T) Bool
    public remove(self ref, value T) Bool
    public is_empty(self) Bool
    public is_subset_of(self, other [T]Set) Bool
    public is_superset_of(self, other [T]Set) Bool
    public clear(self ref) Void
    public retain(self ref, predicate [T, Bool]Func) Void
    public union(self, other [T]Set) [T]Set
    public intersection(self, other [T]Set) [T]Set
    public difference(self, other [T]Set) [T]Set
    public symmetric_difference(self, other [T]Set) [T]Set
}

given[T Hash] [T]Set [T, [T]SetIterator]Iterable {
    public iterator(self) [T]SetIterator
}

given[T Hash] [T]SetIterator [T]Iterator {
    public next(self ref) [T]Option
}

given String {
    public from_utf8_ptr_unchecked(bytes UInt8 ptr, len UInt) String
    public from_utf8_ptr(bytes UInt8 ptr, len UInt) [String]Result
    public from_bytes(bytes [UInt8]List) [String]Result
    public from_bytes_unchecked(bytes [UInt8]List) String
    public from_cstring(cstr UInt8 ptr) [String]Result
    public from_cstring_unchecked(cstr UInt8 ptr) String
    public with_capacity(capacity UInt) String
    public new() String
    public count(self) UInt
    public is_empty(self) Bool
    public capacity(self) UInt
    public to_bytes(self) [UInt8]List
    public get(self, index UInt) [UInt8]Option
    public push_byte(self ref, value UInt8) Void
    public push_string(self ref, other String) Void
    public push_substring(self ref, other String, range [UInt]Range) Void
    public reserve(self ref, capacity UInt) Void
    public starts_with(self, prefix String) Bool
    public ends_with(self, suffix String) Bool
    public find(self, pat String) [UInt]Option
    public find_last(self, pat String) [UInt]Option
    public is_rune_boundary(self, byte_index UInt) Bool
    public substring(self, range [UInt]Range) String
    public trim_ascii_start(self) String
    public trim_ascii_end(self) String
    public trim_ascii(self) String
    public is_ascii(self) Bool
    public is_ascii_whitespace(self) Bool
    public to_ascii_lowercase(self) String
    public to_ascii_uppercase(self) String
    public to_ascii_titlecase(self) String
    public find_from(self, start UInt, pat String) [UInt]Option
    public contains(self, pat String) Bool
    public repeat(self, times UInt) String
    public replace_n(self, pat String, n UInt, with: String) String
    public split_once(self, sep String) [[String, String]Pair]Option
    public split_last_once(self, sep String) [[String, String]Pair]Option
    public replace_all(self, pat String, with: String) String
    public split_ascii_whitespace(self) StringSplitAsciiWhitespaceIterator
    public split(self, sep String) StringSplitIterator
    public lines(self) StringLinesIterator
    public trim_prefix(self, prefix String) String
    public trim_suffix(self, suffix String) String
    public strip_prefix(self, prefix String) [String]Option
    public strip_suffix(self, suffix String) [String]Option
    public bytes(self) StringBytesIterator
    public runes(self) RunesIterator
    public to_runes(self) [Rune]List
    public push_rune(self ref, rune Rune) Void
}

given String Eq {
    public equals(self, other String) Bool
}

given String Ord {
    public compare(self, other String) Int
}

given String Hash {
    public hash(self) UInt
}

given String [UInt, UInt8]Index {
    public at(self, key UInt) UInt8
}

given StringSplitAsciiWhitespaceIterator [String]Iterator {
    public next(self ref) [String]Option
}

given StringSplitIterator [String]Iterator {
    public next(self ref) [String]Option
}

given StringLinesIterator [String]Iterator {
    public next(self ref) [String]Option
}

given RunesIterator [Rune]Iterator {
    public next(self ref) [Rune]Option
}

given StringBytesIterator [UInt8]Iterator {
    public next(self ref) [UInt8]Option
}

given String ToString {
    public to_string(self) String
}

given Bool ToString {
    public to_string(self) String
}

given Int ToString {
    public to_string(self) String
}

given Int8 ToString {
    public to_string(self) String
}

given Int16 ToString {
    public to_string(self) String
}

given Int32 ToString {
    public to_string(self) String
}

given Int64 ToString {
    public to_string(self) String
}

given UInt ToString {
    public to_string(self) String
}

given UInt8 ToString {
    public to_string(self) String
}

given UInt16 ToString {
    public to_string(self) String
}

given UInt32 ToString {
    public to_string(self) String
}

given UInt64 ToString {
    public to_string(self) String
}

given Float32 ToString {
    public to_string(self) String
}

given Float64 ToString {
    public to_string(self) String
}

given[T ToString, U ToString] [T, U]Pair ToString {
    public to_string(self) String
}

given[T ToString] [T]Option ToString {
    public to_string(self) String
}

given[T ToString] [T]List ToString {
    public to_string(self) String
}

given[T ToString] [T]Iterator {
    public join_to_string(self, seperator String) String
}

given[T ToString] [T]List {
    public join_to_string(self, seperator String) String
}

given[K ToString and Hash, V ToString] [K, V]Dict ToString {
    public to_string(self) String
}

given[T ToString and Hash] [T]Set ToString {
    public to_string(self) String
}

given Duration ToString {
    public to_string(self) String
}

given Hash {
    public combine_hash(self, value UInt) UInt
}

given String Error {
    public message(self) String
}

given Bool Hash {
    public hash(self) UInt
}

given UInt Hash {
    public hash(self) UInt
}

given UInt8 Hash {
    public hash(self) UInt
}

given UInt16 Hash {
    public hash(self) UInt
}

given UInt32 Hash {
    public hash(self) UInt
}

given UInt64 Hash {
    public hash(self) UInt
}

given Int Hash {
    public hash(self) UInt
}

given Int8 Hash {
    public hash(self) UInt
}

given Int16 Hash {
    public hash(self) UInt
}

given Int32 Hash {
    public hash(self) UInt
}

given Int64 Hash {
    public hash(self) UInt
}

given[T Any] T ptr Eq {
    public equals(self, other T ptr) Bool
}

given[T Any] T ptr Hash {
    public hash(self) UInt
}

given[T Eq and Deref] T ref Eq {
    public equals(self, other T ref) Bool
}

given[T Hash and Deref] T ref Hash {
    public hash(self) UInt
}

given[T Ord and Deref] T ref Ord {
    public compare(self, other T ref) Int
}

given[T ToString and Deref] T ref ToString {
    public to_string(self) String
}

given[T Eq, U Eq] [T, U]Pair Eq {
    public equals(self, other [T, U]Pair) Bool
}

given[T Hash, U Hash] [T, U]Pair Hash {
    public hash(self) UInt
}

given[T Ord, U Ord] [T, U]Pair Ord {
    public compare(self, other [T, U]Pair) Int
}

given Ord {
    public clamp(self, min: Self, max: Self) Self
}
```

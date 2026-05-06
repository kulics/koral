# Std API

## Overview
This page lists the public API of module `Std` (declaration-only syntax), organized by free functions, traits, types, and given implementations.

## Free Functions
```koral
public let sleep(d Duration) Void

public let make_bytes(count UInt) [UInt8]List

public let make_uninitialized_bytes(count UInt) [UInt8]List

public let [T Any]box(v T) T mut ref

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
public trait Zero {
    zero() Self
}

public trait One {
    one() Self
}

public trait [R Any]Add {
    add(self, other R) Self
}

public trait [R Any]Sub {
    sub(self, other R) Self
}

public trait Neg {
    neg(self) Self
}

public trait [R Any]Mul {
    mul(self, other R) Self
}

public trait [R Any]Div {
    div(self, other R) Self
}

public trait [R Any]Rem {
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

public trait [T Any]Iterator {
    next(self mut ref) [T]Option
}

public trait [T Any, R [T]Iterator]Iterable {
    iterator(self ref) R
}

public trait Step Bounded {
    succ(self) [Self]Option
    pred(self) [Self]Option
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
    drop(self mut ref) Void
}

public trait [K Any, V Any]Index {
    ref_at(self ref, key K) V ref
}

public trait [K Any, V Any]MutIndex [K, V]Index {
    mut_ref_at(self mut ref, key K) V mut ref
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

public type SliceSpec

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

public type StringRunesIterator

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

given Int as Zero {
    public zero() Int
}

given Int as One {
    public one() Int
}

given Int as [Int]Add {
    public add(self, other Int) Int
}

given Int as [Int]Sub {
    public sub(self, other Int) Int
}

given Int as Neg {
    public neg(self) Int
}

given Int as [Int]Mul {
    public mul(self, other Int) Int
}

given Int as [Int]Div {
    public div(self, other Int) Int
}

given Int as [Int]Rem {
    public rem(self, other Int) Int
}

given Int8 as Zero {
    public zero() Int8
}

given Int8 as One {
    public one() Int8
}

given Int8 as [Int8]Add {
    public add(self, other Int8) Int8
}

given Int8 as [Int8]Sub {
    public sub(self, other Int8) Int8
}

given Int8 as Neg {
    public neg(self) Int8
}

given Int8 as [Int8]Mul {
    public mul(self, other Int8) Int8
}

given Int8 as [Int8]Div {
    public div(self, other Int8) Int8
}

given Int8 as [Int8]Rem {
    public rem(self, other Int8) Int8
}

given Int16 as Zero {
    public zero() Int16
}

given Int16 as One {
    public one() Int16
}

given Int16 as [Int16]Add {
    public add(self, other Int16) Int16
}

given Int16 as [Int16]Sub {
    public sub(self, other Int16) Int16
}

given Int16 as Neg {
    public neg(self) Int16
}

given Int16 as [Int16]Mul {
    public mul(self, other Int16) Int16
}

given Int16 as [Int16]Div {
    public div(self, other Int16) Int16
}

given Int16 as [Int16]Rem {
    public rem(self, other Int16) Int16
}

given Int32 as Zero {
    public zero() Int32
}

given Int32 as One {
    public one() Int32
}

given Int32 as [Int32]Add {
    public add(self, other Int32) Int32
}

given Int32 as [Int32]Sub {
    public sub(self, other Int32) Int32
}

given Int32 as Neg {
    public neg(self) Int32
}

given Int32 as [Int32]Mul {
    public mul(self, other Int32) Int32
}

given Int32 as [Int32]Div {
    public div(self, other Int32) Int32
}

given Int32 as [Int32]Rem {
    public rem(self, other Int32) Int32
}

given Int64 as Zero {
    public zero() Int64
}

given Int64 as One {
    public one() Int64
}

given Int64 as [Int64]Add {
    public add(self, other Int64) Int64
}

given Int64 as [Int64]Sub {
    public sub(self, other Int64) Int64
}

given Int64 as Neg {
    public neg(self) Int64
}

given Int64 as [Int64]Mul {
    public mul(self, other Int64) Int64
}

given Int64 as [Int64]Div {
    public div(self, other Int64) Int64
}

given Int64 as [Int64]Rem {
    public rem(self, other Int64) Int64
}

given UInt as Zero {
    public zero() UInt
}

given UInt as One {
    public one() UInt
}

given UInt as [UInt]Add {
    public add(self, other UInt) UInt
}

given UInt as [UInt]Sub {
    public sub(self, other UInt) UInt
}

given UInt as [UInt]Mul {
    public mul(self, other UInt) UInt
}

given UInt as [UInt]Div {
    public div(self, other UInt) UInt
}

given UInt as [UInt]Rem {
    public rem(self, other UInt) UInt
}

given UInt8 as Zero {
    public zero() UInt8
}

given UInt8 as One {
    public one() UInt8
}

given UInt8 as [UInt8]Add {
    public add(self, other UInt8) UInt8
}

given UInt8 as [UInt8]Sub {
    public sub(self, other UInt8) UInt8
}

given UInt8 as [UInt8]Mul {
    public mul(self, other UInt8) UInt8
}

given UInt8 as [UInt8]Div {
    public div(self, other UInt8) UInt8
}

given UInt8 as [UInt8]Rem {
    public rem(self, other UInt8) UInt8
}

given UInt16 as Zero {
    public zero() UInt16
}

given UInt16 as One {
    public one() UInt16
}

given UInt16 as [UInt16]Add {
    public add(self, other UInt16) UInt16
}

given UInt16 as [UInt16]Sub {
    public sub(self, other UInt16) UInt16
}

given UInt16 as [UInt16]Mul {
    public mul(self, other UInt16) UInt16
}

given UInt16 as [UInt16]Div {
    public div(self, other UInt16) UInt16
}

given UInt16 as [UInt16]Rem {
    public rem(self, other UInt16) UInt16
}

given UInt32 as Zero {
    public zero() UInt32
}

given UInt32 as One {
    public one() UInt32
}

given UInt32 as [UInt32]Add {
    public add(self, other UInt32) UInt32
}

given UInt32 as [UInt32]Sub {
    public sub(self, other UInt32) UInt32
}

given UInt32 as [UInt32]Mul {
    public mul(self, other UInt32) UInt32
}

given UInt32 as [UInt32]Div {
    public div(self, other UInt32) UInt32
}

given UInt32 as [UInt32]Rem {
    public rem(self, other UInt32) UInt32
}

given UInt64 as Zero {
    public zero() UInt64
}

given UInt64 as One {
    public one() UInt64
}

given UInt64 as [UInt64]Add {
    public add(self, other UInt64) UInt64
}

given UInt64 as [UInt64]Sub {
    public sub(self, other UInt64) UInt64
}

given UInt64 as [UInt64]Mul {
    public mul(self, other UInt64) UInt64
}

given UInt64 as [UInt64]Div {
    public div(self, other UInt64) UInt64
}

given UInt64 as [UInt64]Rem {
    public rem(self, other UInt64) UInt64
}

given Float32 as Zero {
    public zero() Float32
}

given Float32 as One {
    public one() Float32
}

given Float32 as [Float32]Add {
    public add(self, other Float32) Float32
}

given Float32 as [Float32]Sub {
    public sub(self, other Float32) Float32
}

given Float32 as Neg {
    public neg(self) Float32
}

given Float32 as [Float32]Mul {
    public mul(self, other Float32) Float32
}

given Float32 as [Float32]Div {
    public div(self, other Float32) Float32
}

given Float64 as Zero {
    public zero() Float64
}

given Float64 as One {
    public one() Float64
}

given Float64 as [Float64]Add {
    public add(self, other Float64) Float64
}

given Float64 as [Float64]Sub {
    public sub(self, other Float64) Float64
}

given Float64 as Neg {
    public neg(self) Float64
}

given Float64 as [Float64]Mul {
    public mul(self, other Float64) Float64
}

given Float64 as [Float64]Div {
    public div(self, other Float64) Float64
}

given String as [String]Add {
    public add(self, other String) String
}

given[T Deref] [T]List as [[T]List]Add {
    public add(self, other Self) Self
}

given Duration as Zero {
    public zero() Duration
}

given Duration as [Duration]Add {
    public add(self, other Duration) Duration
}

given Duration as [Duration]Sub {
    public sub(self, other Duration) Duration
}

given Duration as Neg {
    public neg(self) Duration
}

given Duration as [Int]Mul {
    public mul(self, k Int) Duration
}

given Duration as [Int]Div {
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

given[K Hash, V Any] [K, V]Dict {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public insert(self mut ref, key K, value V) [V]Option
    public insert_dict(self mut ref, other [K, V]Dict) Void
    public get(self ref, key K) [V]Option
    public get_or_insert(self mut ref, key K, value V) V
    public contains_key(self ref, key K) Bool
    public remove(self mut ref, key K) [V]Option
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public retain(self mut ref, predicate [K, V, Bool]Func) Void
}

given[K Hash, V Any] [K, V]DictIterator as [[K, V]Pair]Iterator {
    public next(self mut ref) [[K, V]Pair]Option
}

given[K Hash, V Any] [K, V]DictKeysIterator as [K]Iterator {
    public next(self mut ref) [K]Option
}

given[K Hash, V Any] [K, V]DictValuesIterator as [V]Iterator {
    public next(self mut ref) [V]Option
}

given[K Hash, V Any] [K, V]Dict {
    public keys(self ref) [K, V]DictKeysIterator
    public values(self ref) [K, V]DictValuesIterator
}

given[K Hash, V Any] [K, V]Dict as [[K, V]Pair, [K, V]DictIterator]Iterable {
    public iterator(self ref) [K, V]DictIterator
}

given[T Deref] [T]List {
    public [K Hash]group_by(self ref, key [T, K]Func) [K, [T]List]Dict
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

given Duration as Eq {
    public equals(self, other Duration) Bool
}

given Duration as Ord {
    public compare(self, other Duration) Int
}

given[T Any, R [T]Iterator] [T, R]FilterIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, U Any, R [T]Iterator] [T, U, R]MapIterator as [U]Iterator {
    public next(self mut ref) [U]Option
}

given[T Any, U Any, R [T]Iterator] [T, U, R]FilterMapIterator as [U]Iterator {
    public next(self mut ref) [U]Option
}

given[T Any, R [T]Iterator] [T, R]TakeIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]SkipIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]StepIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]EnumerateIterator as [[UInt, T]Pair]Iterator {
    public next(self mut ref) [[UInt, T]Pair]Option
}

given[T Any, R [T]Iterator] [T, R]InspectIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]IntersperseIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]TakeWhileIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, R [T]Iterator] [T, R]SkipWhileIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Any, R1 [T]Iterator, R2 [T]Iterator] [T, R1, R2]ChainIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[A Any, B Any, R1 [A]Iterator, R2 [B]Iterator] [A, B, R1, R2]ZipIterator as [[A, B]Pair]Iterator {
    public next(self mut ref) [[A, B]Pair]Option
}

given[T Any, U Any, R [T]Iterator, InnerR [U]Iterator] [T, U, R, InnerR]FlatMapIterator as [U]Iterator {
    public next(self mut ref) [U]Option
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
    public into_list(self) [T]List
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
    public into_set(self) [T]Set
}

given[T [T]Add and Zero] [T]Iterator {
    public sum(self) T
}

given[T [T]Mul and One] [T]Iterator {
    public product(self) T
}

given[T [T]Add and [T]Div and Zero and One] [T]Iterator {
    public average(self) [T]Option
}

given[T Deref] [T]List {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public reserve(self mut ref, additional UInt) Void
    public push(self mut ref, value T) Void
    public push_list(self mut ref, other [T]List) Void
    public push_sublist(self mut ref, other [T]List, range [UInt]Range) Void
    public pop(self mut ref) [T]Option
    public insert_list_at(self mut ref, index UInt, other [T]List) Void
    public insert_sublist_at(self mut ref, index UInt, other [T]List, range [UInt]Range) Void
    public insert_at(self mut ref, index UInt, value T) Void
    public remove_at(self mut ref, index UInt) T
    public get(self ref, index UInt) [T]Option
    public first(self ref) [T]Option
    public last(self ref) [T]Option
    public is_empty(self ref) Bool
    public clear(self mut ref) Void
    public fill(self mut ref, value T) Void
    public [U Deref]map(self ref, fn [T, U]Func) [U]List
    public reverse(self mut ref) Void
    public borrow_ptr(self ref) T ptr
    public borrow_mut_ptr(self mut ref) T mut ptr
    public slice_spec(self ref, range [UInt]Range) SliceSpec
    public sublist(self ref, range [UInt]Range) [T]List
    public enumerate(self ref) [T, [T]ListIterator]EnumerateIterator
    public retain(self mut ref, predicate [T, Bool]Func) Void
    public [K Ord]sort_by(self mut ref, key [T, K]Func) Void
    public [K Ord]binary_search_by(self ref, key [T, K]Func, target K) [UInt, Bool]Pair
}

given[T Eq and Deref] [T]List as Eq {
    public equals(self, other [T]List) Bool
}

given[T Eq and Deref] [T]List {
    public contains(self ref, value T) Bool
    public dedup(self mut ref) Void
}

given[T Deref] [T]ListIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Deref] [T]List as [T, [T]ListIterator]Iterable {
    public iterator(self ref) [T]ListIterator
}

given[T Deref] [T]List as [UInt, T]Index {
    public ref_at(self ref, key UInt) T ref
}

given[T Deref] [T]List as [UInt, T]MutIndex {
    public mut_ref_at(self mut ref, key UInt) T mut ref
}

given[T Ord and Deref] [T]List {
    public binary_search(self ref, target T) [UInt, Bool]Pair
    public sort(self mut ref) Void
}

given[T Any] [T]Option {
    public is_some(self ref) Bool
    public is_none(self ref) Bool
    public unwrap(self) T
    public expect(self, message String) T
    public unwrap_or(self, default T) T
    public [U Any]map(self, f [T, U]Func) [U]Option
    public filter(self, predicate [T, Bool]Func) [T]Option
}

given[T Eq] [T]Option as Eq {
    public equals(self, other [T]Option) Bool
}

intrinsic given [T Any] T weakref {
    public to_ref(self) [T ref]Option
}

intrinsic given [T Any] T mut weakref {
    public to_ref(self) [T mut ref]Option
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

given[T Ord] [T]Range {
    public contains(self ref, value T) Bool
    public is_empty(self ref) Bool
}

given Int as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int8 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int16 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int32 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given Int64 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt8 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt16 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt32 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given UInt64 as Step {
    public succ(self) [Self]Option
    public pred(self) [Self]Option
}

given[T Step] [T]RangeIterator as [T]Iterator {
    public next(self mut ref) [T]Option
}

given[T Step] [T]Range as [T, [T]RangeIterator]Iterable {
    public iterator(self ref) [T]RangeIterator
}

given[T Any] [T]Result {
    public is_ok(self ref) Bool
    public is_error(self ref) Bool
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

given Rune as Eq {
    public equals(self, other Rune) Bool
}

given Rune as Ord {
    public compare(self, other Rune) Int
}

given Rune as ToString {
    public to_string(self ref) String
}

given[T Hash] [T]Set {
    public new() Self
    public with_capacity(capacity UInt) Self
    public count(self ref) UInt
    public insert(self mut ref, value T) Bool
    public insert_set(self mut ref, other [T]Set) Void
    public contains(self ref, value T) Bool
    public remove(self mut ref, value T) Bool
    public is_empty(self ref) Bool
    public is_subset_of(self ref, other [T]Set) Bool
    public is_superset_of(self ref, other [T]Set) Bool
    public clear(self mut ref) Void
    public retain(self mut ref, predicate [T, Bool]Func) Void
    public union(self ref, other [T]Set) [T]Set
    public intersection(self ref, other [T]Set) [T]Set
    public difference(self ref, other [T]Set) [T]Set
    public symmetric_difference(self ref, other [T]Set) [T]Set
}

given[T Hash] [T]Set as [T, [T]SetIterator]Iterable {
    public iterator(self ref) [T]SetIterator
}

given[T Hash] [T]SetIterator as [T]Iterator {
    public next(self mut ref) [T]Option
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
    public count(self ref) UInt
    public is_empty(self ref) Bool
    public capacity(self ref) UInt
    public to_bytes(self ref) [UInt8]List
    public get(self ref, index UInt) [UInt8]Option
    public push_byte(self mut ref, value UInt8) Void
    public push_string(self mut ref, other String) Void
    public push_substring(self mut ref, other String, range [UInt]Range) Void
    public reserve(self mut ref, capacity UInt) Void
    public starts_with(self ref, prefix String) Bool
    public ends_with(self ref, suffix String) Bool
    public find(self ref, pat String) [UInt]Option
    public find_last(self ref, pat String) [UInt]Option
    public is_rune_boundary(self ref, byte_index UInt) Bool
    public slice_spec(self ref, range [UInt]Range) SliceSpec
    public substring(self ref, range [UInt]Range) String
    public trim_ascii_start(self ref) String
    public trim_ascii_end(self ref) String
    public trim_ascii(self ref) String
    public is_ascii(self ref) Bool
    public is_ascii_whitespace(self ref) Bool
    public to_ascii_lowercase(self ref) String
    public to_ascii_uppercase(self ref) String
    public to_ascii_titlecase(self ref) String
    public find_from(self ref, start UInt, pat String) [UInt]Option
    public contains(self ref, pat String) Bool
    public repeat(self ref, times UInt) String
    public replace_n(self ref, pat String, n UInt, with: String) String
    public split_once(self ref, sep String) [[String, String]Pair]Option
    public split_last_once(self ref, sep String) [[String, String]Pair]Option
    public replace_all(self ref, pat String, with: String) String
    public split_ascii_whitespace(self ref) StringSplitAsciiWhitespaceIterator
    public split(self ref, sep String) StringSplitIterator
    public lines(self ref) StringLinesIterator
    public trim_prefix(self ref, prefix String) String
    public trim_suffix(self ref, suffix String) String
    public strip_prefix(self ref, prefix String) [String]Option
    public strip_suffix(self ref, suffix String) [String]Option
    public bytes(self ref) StringBytesIterator
    public runes(self ref) StringRunesIterator
    public to_runes(self ref) [Rune]List
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

given String as [UInt, UInt8]Index {
    public ref_at(self ref, key UInt) UInt8 ref
}

given StringSplitAsciiWhitespaceIterator as [String]Iterator {
    public next(self mut ref) [String]Option
}

given StringSplitIterator as [String]Iterator {
    public next(self mut ref) [String]Option
}

given StringLinesIterator as [String]Iterator {
    public next(self mut ref) [String]Option
}

given StringRunesIterator as [Rune]Iterator {
    public next(self mut ref) [Rune]Option
}

given StringBytesIterator as [UInt8]Iterator {
    public next(self mut ref) [UInt8]Option
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

given[T ToString, U ToString] [T, U]Pair as ToString {
    public to_string(self ref) String
}

given[T ToString] [T]Option as ToString {
    public to_string(self ref) String
}

given[T ToString and Deref] [T]List as ToString {
    public to_string(self ref) String
}

given[T ToString] [T]Iterator {
    public join_to_string(self, seperator String) String
}

given[T ToString and Deref] [T]List {
    public join_to_string(self, seperator String) String
}

given[K ToString and Hash, V ToString] [K, V]Dict as ToString {
    public to_string(self ref) String
}

given[T ToString and Hash] [T]Set as ToString {
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

given[T Any] T ptr as Eq {
    public equals(self, other T ptr) Bool
}

given[T Any] T ptr as Hash {
    public hash(self) UInt
}

given[T Any] T mut ptr as Eq {
    public equals(self, other T mut ptr) Bool
}

given[T Any] T mut ptr as Hash {
    public hash(self) UInt
}

given[T Eq and Deref] T ref as Eq {
    public equals(self, other T ref) Bool
}

given[T Eq and Deref] T mut ref as Eq {
    public equals(self, other T mut ref) Bool
}

given[T Hash and Deref] T ref as Hash {
    public hash(self) UInt
}

given[T Hash and Deref] T mut ref as Hash {
    public hash(self) UInt
}

given[T Ord and Deref] T ref as Ord {
    public compare(self, other T ref) Int
}

given[T Ord and Deref] T mut ref as Ord {
    public compare(self, other T mut ref) Int
}

given[T ToString and Deref] T ref as ToString {
    public to_string(self ref) String
}

given[T ToString and Deref] T mut ref as ToString {
    public to_string(self ref) String
}

given[T Eq, U Eq] [T, U]Pair as Eq {
    public equals(self, other [T, U]Pair) Bool
}

given[T Hash, U Hash] [T, U]Pair as Hash {
    public hash(self) UInt
}

given[T Ord, U Ord] [T, U]Pair as Ord {
    public compare(self, other [T, U]Pair) Int
}

given Ord {
    public clamp(self, min: Self, max: Self) Self
}
```

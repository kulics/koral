# Constructor Labels and Default-Fill Proposal

Status: Draft for review

Date: 2026-09-03

## Summary

This proposal removes function-level named parameter syntax from Koral.

In its place, the language keeps labels only on nominal constructors and adds a trailing default-fill form based on a new `Default` trait.

The core surface is:

```koral
trait Default {
    default() Self
}

type Point(x Int, y Int)

let p1 = Point(1, 2)
let p2 = Point(x: 1, y: 2)
let p3 = Point(y: 2, x: 1)
let p4 = Point(...)
let p5 = Point(x: 1, ...)
```

This proposal intentionally does not keep named labels on ordinary function or method calls.

## Motivation

The current function named-parameter design has three major problems.

First, it pays language and implementation complexity across parser, AST, type checker, bootstrap compiler, formatter, and tests.

Second, its user value is weaker than the surface area suggests. Current named arguments are still fixed-order, do not support reordering, do not support default values, and are not carried by `Func` types or lambda signatures.

Third, the `:` marker feels more natural for field-oriented construction than for function-call protocol. `Point(x: 1, y: 2)` reads intuitively as naming fields. `connect(host: ..., port: ...)` reads more like a library-specific calling convention.

The highest-value part of the current design is not general function labels. It is readable construction of nominal data and readable destructuring of that same data.

This proposal keeps that value and cuts the wider rule set.

## Goals

- Remove function named-parameter syntax and its cross-cutting implementation cost.
- Keep nominal data construction readable.
- Allow concise partial construction when omitted fields have obvious defaults.
- Make the meaning of `x: value` more intuitive by limiting it to constructor and pattern contexts.
- Keep lowering simple by translating constructor labels and `...` into ordinary positional construction before MIR/codegen.

## Non-Goals

- General keyword arguments for ordinary functions.
- Default arguments for ordinary functions.
- Partial pattern matching with `...`.
- Automatic derivation of `Type.default()` from fieldwise defaults in v1.
- Mixing positional constructor arguments and labeled constructor arguments.
- A new distinct syntax for labeled function calls.

## Design Overview

The proposal has four main decisions.

1. Function and method parameters become positional only.
2. Struct fields and enum payload fields are always declared as `name Type`, without using `:` in the declaration.
3. Constructor calls may use positional arguments or labeled arguments, but may not mix them.
4. A trailing `...` in labeled constructor mode fills omitted fields by calling `Default.default()` on each omitted field type.

## Syntax

### Function and Method Declarations

Ordinary function and method declarations use positional parameters only.

```koral
let connect(host String, port Int) Void = {}

trait Reader {
    read(*self, into *mutable List[UInt8], range Range[UInt]) Result[UInt]
}
```

The following becomes invalid:

```koral
let connect(host: String, port: Int) Void = {}
```

### Struct and Enum Field Declarations

Nominal field declarations always use field names, but do not use `:` in the declaration.

```koral
type Point(x Int, y Int)

type Shape {
    Circle(radius Int),
    Rect(width Int, height Int),
}
```

The field name is what later enables labeled construction and labeled destructuring.

### Constructor Calls

Constructors support two ordinary modes and one extended mode.

#### Positional constructor mode

```koral
let p = Point(1, 2)
let s = Shape.Rect(10, 20)
```

#### Labeled constructor mode

```koral
let p = Point(x: 1, y: 2)
let q = Point(y: 2, x: 1)
let s = Shape.Rect(height: 20, width: 10)
```

Labels in constructor mode match by field name, not by position.

#### Labeled constructor mode with default-fill

```koral
let p1 = Point(...)
let p2 = Point(x: 1, ...)
let s = Shape.Rect(width: 10, ...)
```

`...` may only appear as the final argument.

## Grammar Sketch

This is an illustrative sketch, not the full normative grammar.

```bnf
<func-param> ::= "mutable"? <identifier> <type-annotation>

<field> ::= <access-modifier>? "mutable"? <identifier> <type-annotation>
<variant-field> ::= <identifier> <type-annotation>

<constructor-arg-list> ::= <positional-ctor-args>
                         | <labeled-ctor-args>
                         | "..."
                         | <labeled-ctor-args> "," "..."

<positional-ctor-args> ::= <expression> ("," <expression>)* ","?
<labeled-ctor-args> ::= <labeled-ctor-arg> ("," <labeled-ctor-arg>)* ","?
<labeled-ctor-arg> ::= <identifier> ":" <expression>
```

## Detailed Semantics

### What Counts as a Constructor

Labeled arguments and trailing `...` are only valid when the callee resolves to one of the following nominal constructors:

- A struct constructor.
- An enum case payload constructor.
- An implicit enum member constructor such as `.Rect(...)` when the enum type is already known.

They are not valid for:

- Ordinary functions.
- Methods.
- Trait methods.
- Lambda expressions.
- Values of `Func(...)` type.

### Positional Constructor Mode

Positional mode keeps the current behavior.

- Arguments are matched by declaration order.
- The argument count must equal the field count.
- No labels are allowed.
- `...` is not allowed.

### Labeled Constructor Mode

Labeled mode follows these rules.

- Arguments are matched by field name.
- Reordering is allowed.
- Each field name may appear at most once.
- Unknown labels are rejected.
- If `...` is absent, every field must be explicitly provided.
- If `...` is present, every omitted field must be default-fillable.

### No Mixed Positional and Labeled Constructor Calls

This proposal intentionally rejects mixed forms.

Invalid examples:

```koral
Point(1, y: 2)
Point(x: 1, 2)
Point(1, ...)
```

This rule is important. Without it, constructor labels start drifting back toward general function named parameters, and the `...` rules become harder to explain and to implement.

### Default-Fill with `...`

`...` has constructor-specific meaning.

- `Type(...)` means every field is omitted and must be filled by field defaults.
- `Type(x: 1, ...)` means `x` is explicit and all remaining fields are filled by field defaults.
- `...` may only appear once.
- `...` must be the final argument.
- `...` is only valid in constructor calls.
- If every field is already supplied, trailing `...` is rejected as redundant.

Examples:

```koral
type Window(title String, width Int, height Int)

let a = Window(...)
let b = Window(title: "Koral", ...)
let c = Window(width: 800, height: 600, title: "Koral")
```

Invalid examples:

```koral
Window(..., title: "Koral")
Window(title: "Koral", width: 800, height: 600, ...)
Window(800, ...)
```

### `Default` Trait

The proposal adds:

```koral
trait Default {
    default() Self
}
```

`...` is defined in terms of field types, not in terms of the enclosing nominal type.

For each omitted field:

- Let the field type be `T`.
- The type checker requires `T` to implement `Default`.
- The omitted field value is lowered as `T.default()`.

Important consequence:

`Point(...)` is not defined as `Point.default()`.

It is defined as fieldwise filling:

```koral
Point(Int.default(), Int.default())
```

Therefore these two may differ:

```koral
Point(...)
Point.default()
```

This proposal accepts that distinction in v1.

### No Automatic `Type.default()` Derivation in v1

Even if every field type implements `Default`, this proposal does not automatically declare that the enclosing type implements `Default`.

That behavior can be added later if desired, but it should be a separate decision.

The initial version keeps only fieldwise constructor filling.

### Generic Type Inference

Default-fill may only use types that are already known after normal constructor resolution.

Example:

```koral
type Box[T Any](value T)

let a Box[Int] = Box(...)
let b = Box[Int](...)
```

Both are valid because `T` is known to be `Int`.

This is invalid:

```koral
let c = Box(...)
```

because the omitted field type is not known and `...` does not invent a new type argument.

In other words, `...` may satisfy values for already-known field types, but it does not act as a new source of generic inference.

### Access Control

Labeled constructors and `...` must preserve existing direct-construction access rules.

If a type cannot be directly constructed because one of its fields is not accessible, then both of these remain invalid:

```koral
SecretType(...)
SecretType(public_field: 1, ...)
```

`...` must not become a back door around field visibility.

### Pattern Matching and Destructuring

This proposal keeps labeled destructuring for nominal patterns.

```koral
if p is Point(y: py, x: px) then println(px)

when shape in {
    .Rect(height: h, width: w) then println(w * h),
    .Circle(radius: r) then println(r),
}
```

Pattern labels match by field name and may be reordered.

However, v1 does not extend `...` into patterns.

These stay invalid in v1:

```koral
Point(x: px, ...)
.Rect(width: w, ...)
```

This keeps construction and destructuring mostly symmetric without introducing partial-pattern semantics at the same time.

### Lowering Strategy

Constructor labels and `...` should be erased before MIR and code generation.

The front-end should lower:

```koral
Point(y: 2, x: 1)
```

to:

```koral
Point(1, 2)
```

and lower:

```koral
Point(x: 1, ...)
```

to:

```koral
Point(1, Int.default())
```

in declaration order.

This keeps the feature local to parsing and type checking.

## Diagnostics

Suggested diagnostics for the new surface:

- `Named labels are only allowed on struct and enum constructors; use positional arguments`
- `Constructor call cannot mix positional and labeled arguments`
- `Default-fill '...' is only valid in constructor calls`
- `Default-fill '...' must be the last constructor argument`
- `Default-fill '...' requires labeled constructor arguments or no preceding arguments`
- `Duplicate constructor label 'x'`
- `Unknown constructor label 'z' for type 'Point'`
- `Missing constructor field 'y'; provide 'y:' or use '...'`
- `Field 'y' omitted by '...', but type 'Foo' does not implement Default`
- `Cannot infer type parameter 'T' from default-filled field 'value'; specify type arguments or an expected type`
- `Trailing '...' is redundant because all constructor fields are already provided`

## Standard Library Guidance

### Good Candidates for Early `Default`

The first batch should be limited to types whose default value is obvious, cheap, and stable.

- Integer types
- Floating-point types
- `Bool`
- `Rune`
- `String`
- `Duration`
- `Option[T]`
- `List[T]`
- `Dict[K, V]`
- `Set[T]`
- `Deque[T]`
- `Queue[T]`
- `Stack[T]`

### Types That Should Probably Not Implement `Default` Initially

These types either have meaningful validation requirements, hidden resource ownership, or no universally obvious neutral value.

- `Date`
- `ClockTime`
- `DateTime`
- `File`
- socket types
- process types
- synchronization primitives with runtime state
- regex types
- `Result[T, E]`
- iterators

### API Design After Removing Function Labels

Removing function labels does reduce readability for some current APIs, especially these categories:

- static factory functions with many same-typed parameters
- validation constructors such as `Date.new(...)`
- role-heavy mutating methods such as `read(into, range)` and `compare_exchange(expected, desired)`

The recommendation is not to force every such API back into raw positional style.

Instead, std APIs should follow one of these patterns.

1. Use a nominal constructor when the operation is really data construction.
2. Use a small parameter object when a validating factory needs readable labels.
3. Use a builder when many optional knobs accumulate.
4. Keep positional calls for short, stable, high-frequency APIs.

Example:

```koral
type ClockTimeParts(hour Int, minute Int, second Int, nanosecond Int)

let t = ClockTime.from_parts(ClockTimeParts(hour: 1, minute: 2, ...))
```

This preserves readable labels at the data boundary without reintroducing function-level named arguments.

## Tradeoff Evaluation

### Is Giving Up Function Labels Worth It?

My answer is yes, if the language goal is a simpler and more intuitive core model.

Constructor labels are more valuable than function labels for Koral because:

- They align with the nominal data model.
- They make `x: value` read like field naming rather than call protocol.
- They do not need to infect `Func` types, lambdas, trait requirements, method matching, or higher-order calls.
- They give real value once reordering and `...` are supported.

By contrast, general function labels impose broader language rules and still leave awkward corners unless Koral commits to a much larger feature set.

### What Is Lost?

The loss is real.

Some APIs are more readable with function labels than with pure positional calls. This includes not only static factories, but also methods whose parameters carry semantic roles.

Examples in the current ecosystem include patterns like:

- `ClockTime.new_full(hour: ..., minute: ..., second: ..., nanosecond: ...)`
- `send_process_signal(signal: ..., to: ...)`
- `compare_exchange(expected: ..., desired: ...)`
- `read(into: ..., range: ...)`

Those call sites are readable today.

### Why the Trade Still Looks Good

The better question is not whether function labels are useful. They are.

The better question is whether they are useful enough to justify being a language-wide calling-convention feature.

For Koral, the answer still looks like no.

The reason is that data construction is the natural home for labels, while function labels are better treated as an API-style problem than as a core language rule.

If a library API truly needs labels for readability, a parameter object gives that readability back with much less language complexity:

```koral
type ReadSpec(into *mutable List[UInt8], range Range[UInt])
reader.read(ReadSpec(into: &mutable buf, range: 0..<n))
```

That approach is heavier than direct function labels, but the complexity is local to the API that needs it, instead of being paid by the entire language.

### Decision

If the design goal is:

- simpler syntax
- more intuitive use of `:`
- smaller parser and type-checker surface
- clearer separation between data construction and ordinary calls

then constructor labels plus `Default`-based `...` are more worth keeping than function labels.

If the design goal is instead to make ordinary stdlib calls read like Swift-style sentence fragments, then function labels remain valuable and should not be removed without a separate replacement.

This proposal takes the first path.

## Migration Strategy

### Language Migration

1. Remove `name: Type` from ordinary function and method parameter grammar.
2. Remove named-argument validation for ordinary calls.
3. Keep and strengthen labels only for struct and enum payload construction.
4. Add trailing `...` handling during constructor checking.
5. Add `Default` trait and default-fill constraints.

### Standard Library Migration

APIs should be split into three buckets.

1. Data constructors that can move directly to nominal constructor labels.
2. Validating factories that should take parameter objects or use different naming.
3. Short and obvious calls that should become positional.

Examples of likely migration shapes:

```koral
// Before
ClockTime.new_full(hour: h, minute: m, second: s, nanosecond: ns)

// After: validating factory with parameter object
ClockTime.from_parts(ClockTimeParts(hour: h, minute: m, second: s, nanosecond: ns))

// Before
send_process_signal(signal: 9, to: pid)

// After: positional
send_process_signal(9, pid)
```

### Compiler and Tooling Migration

The parser, type checker, bootstrap compiler, formatter, docs, and tests all need coordinated updates.

However, this proposal should still reduce long-term maintenance cost because the new label surface is narrower and more coherent than the current function named-parameter model.

## Future Extensions

These are intentionally postponed.

- automatic `Default` derivation for product types
- pattern-side `...`
- parameter-object sugar
- a distinct future syntax for labeled ordinary function calls, if Koral later decides they are still worth reintroducing

## Conclusion

This proposal changes the meaning of labels in Koral from a general call-site feature into a nominal construction feature.

That is a worthwhile simplification.

It keeps the most intuitive use of labels, makes `...` genuinely useful, and removes a large amount of low-yield language machinery from ordinary functions.

The main cost is reduced readability for some factories and role-heavy methods, but that cost is better handled by local API design tools than by preserving a general function-label system whose semantics remain awkward and only partially powerful.
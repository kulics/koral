# 标准库 API 设计约定

> **Status**：Implemented
> **范围**：`std` 的接收者形态、消耗语义、命名契约、trait 设计约定
> **用法**见 [`../guide/document.md`](../guide/document.md) 与 [`../api/std/`](../api/std/)；
> **本文只记为什么这样设计 API**。
> **`type` / `type mutable` 的语义**见 [`type-semantics.md`](type-semantics.md)。

## 摘要

`std` 的方法只有一种接收者形态：`self`。它是不可变还是可变接收者，**完全由类型声明决定**——
没有 `*self`、没有 auto-ref、没有 auto-deref。方法消耗不消耗接收者，是**公开契约**的一部分，
由方法名与签名表达，不由实现便利决定。

## 背景

设计标准库时每天要回答：这个方法该不该消耗 `self`？该返回新值还是就地改？
这些问题的答案如果跟着实现走，同一类类型会做出互相矛盾的 API。

所以把答案定成规则，让 API 由**类型语义**和**调用点的 ownership** 驱动。

## 非目标

- **`type` / `type mutable` 的语义本身** → [`type-semantics.md`](type-semantics.md)。
- **每个 API 的签名** → [`../api/std/`](../api/std/)（生成物）。
- **具体容器的实现** → `std/` 源码。

## 方案

原文出处：`../implementation/developer-guide.md`「Standard Library Receiver Design」（已迁出）。
When designing standard-library APIs, `self` is the only receiver form. Whether `self` acts as an immutable or mutable receiver depends entirely on the type declaration:

- For `type` (immutable types), `self` is an immutable receiver. Fields are all immutable and there is no shared-object identity.
- For `type mutable` (mutable types), `self` is a mutable receiver on the shared object. Fields can be mutated in place if declared `mutable`.

There is no `*self` or `*mutable self`. There is no auto-ref or auto-deref. The type declaration determines the receiver behavior.

> 📎 **接收者形态这一条在 `../guide/document.md` / `document-zh.md` 的「Method Receiver Forms」
> 与 `../guide/grammar.bnf` 的 `<method-first-param>` 注记里各有一处同义表述。改要四处同批改。**

Primary rule:

- On `type`, `self` is naturally suited for observation, derivation, and transformation that returns new values, since the receiver is immutable and there is no shared-object aliasing concern.
- On `type mutable`, `self` provides shared access to the mutable object. Methods that modify in place (such as `push` on `List`) and methods that observe (such as `count` on `List`) both use `self`; the difference is in what the method body does, not the receiver form.
- On either kind, `self` may semantically consume the receiver when the method is a terminal extraction, ownership conversion, or linear builder step.

### Default Receiver Choices

Use `self` on `type` when the call should leave the original value logically usable by the caller. Since `type` is immutable, all methods naturally preserve the caller's value.

Common cases on `type`:

- predicates such as `is_empty`, `contains`, `starts_with`
- accessors and getters such as `count`, `name`, `pattern`
- formatting and display such as `to_string`, `message`
- pure derived values such as `dir_name`, `base_name`, `components`
- view-producing methods that do not consume the source
- transformation methods that return new values, such as `trim`, `normalize`, `to_ascii_uppercase`

Use `self` on `type mutable` for both mutation and observation.

Common mutation cases on `type mutable`:

- container updates such as `push`, `insert`, `remove`, `clear`
- stateful cursor updates
- mutation APIs returning removed values, such as `pop` or `take_at`

Common observation cases on `type mutable`:

- accessors and getters such as `count`, `peek`, `is_empty`
- predicates and display methods

Use `self` on either kind of type when consuming the receiver is part of the API contract.

Common consumption cases:

- terminal extraction such as `unwrap`, `expect`, `into_list`
- transforming combinators on ownership-carrying enums such as `Option.map` and `Result.map`
- iterator adapters or terminal operations that must consume iteration state
- linear builders such as `Task.set_name(...).set_stack_size(...).spawn()`
- explicit ownership-conversion methods with `into_*` naming

Builder-style APIs need one extra distinction:

- keep `self` when the builder is intentionally modeled as a linear fluent pipeline whose chained calls conceptually move from one configuration stage to the next
- on `type mutable`, builders naturally support chaining via the shared handle, so methods that configure and return the same handle are idiomatic
- on `type`, a builder that needs repeated configuration should use a consuming `self` pipeline if the chaining behavior is part of the public contract

### Returned New Values Do Not Consume the Receiver

Returning a new value is not, by itself, a reason to consume the receiver.

On `type`, all methods naturally leave the original value usable because `type` is immutable. Transformation methods such as path manipulation, string trimming, and structural projections return new values while the original remains unchanged.

On `type mutable`, methods that return new values while preserving the shared object (such as `pop` returning a removed element) also do not consume the receiver.

Consume the receiver only when the API is intentionally framed as consuming or forwarding ownership, such as `into_*` methods or terminal combinators.

### Small Pure Value Types

For compact immutable value types, receiver design may prioritize value-style ergonomics over strict borrow minimality.

Examples include:

- `Duration`
- `Date`
- `ClockTime`
- `MonoTime`
- sometimes `DateTime` when treated as a compact timestamp value rather than a heavy handle
- compact address or identifier values such as `Ipv4Addr`, `Ipv6Addr`, `IpAddr`, and `SocketAddr`
- compact bitflag wrappers such as `RegexFlag`

For such types, it is acceptable to keep observation and pure derivation methods on `self` when all of the following are true:

- the type is cheap to copy relative to the surrounding API
- the methods conceptually behave like arithmetic or scalar queries
- the family already uses value receivers consistently
- borrowing would add signature noise without unlocking important mutation or aliasing guarantees

Do not apply this exception to heap-owning value types such as `String`, `Path`, containers, or other APIs where shared-object semantics materially improve reuse expectations for callers.

This exception can also cover "sum-of-small-values" enums and tiny wrappers whose payloads are still plain value data rather than handles or heap ownership. Network address values and regex flag bitmasks fit this category; JSON values, strings, paths, and collections generally do not.

### Handle Types and Interior Mutation

Some standard-library types are handles around shared mutable state, for example buffered readers, files, sockets, processes, or timers backed by OS resources. These are `type mutable` types.

For such handle types, `self` provides shared access to the handle, and methods that change underlying state (such as advancing a file cursor or buffering new data) model shared handle mutation, not direct value mutation of the outer type.

This pattern is inherent to `type mutable`. Do not generalize interior-mutation reasoning to `type` types such as containers, strings, or path values, which must remain semantically immutable.

### Borrowed Methods Implemented via Iteration

Do not let an iterator implementation detail force a method to appear consuming.

If a method is semantically observational or purely derived, its public API should reflect that, even when the easiest implementation strategy is to iterate.

Prefer the following order:

1. Implement the method directly with traversal over storage or fields.
2. If the type can cheaply create an iterator snapshot without semantically consuming the value, construct that iterator internally and keep the method observational.
3. Only expose a consuming method when iteration truly consumes unique state as part of the API contract.

This distinction matters because many iterators are consuming in the iterator sense while their source container is not consuming in the API sense. On `type mutable` containers, creating an iterator passes the shared handle and does not consume the container.

Examples:

- a `List` or `String` method may remain observational even if it creates an owned iterator object internally, because the iterator only snapshots shared storage plus cursor state
- a stream, generator, or one-shot parser should not expose observation methods that secretly consume its progression state

### Iterable as a Borrowed Protocol

`Iterator` itself is inherently consuming: `next(self)` advances the iterator's internal cursor and may exhaust the iteration.

`Iterable`, however, is usually better modeled as a borrowed-producing protocol: creating an iterator is typically an observation of the source, not a change to it.

For `type mutable` containers, `iterator(self)` naturally models this: the call passes the shared handle to the container, creates an iterator that snapshots the container's storage and cursor state, and the container itself remains reusable. The `type mutable` declaration ensures the container has shared-object identity, and the iterator is an independent cursor over that shared storage.

For `type` values (such as range-like values), `iterator(self)` is equally appropriate since `type` is inherently non-consuming.

Typical `Iterable` cases where the source remains reusable:

- containers such as `List`, `Set`, `Dict`, `Deque`, `Queue`, `Stack`, and `PriorityQueue` (all `type mutable`)
- range-like values where the range is a reusable description and the iterator carries the advancing cursor (typically `type`)

Typical consuming `Iterable`-like cases would be one-shot sources such as generators, streams, or parsers whose progression state lives in the source value itself.

This design also means observational methods such as set algebra should not be treated as consuming merely because they happen to call `iterator()`. If the source collection is `type mutable`, the public API naturally preserves the shared handle.

### Arithmetic Traits and Arithmetic-Like APIs

Do not equate "returns a new value" or "looks like an operator" with consuming ownership.

Core arithmetic traits such as `Add`, `Sub`, `Mul`, `Div`, `Rem`, and `Neg` describe pure value algebra and should generally stay value-based. They primarily model scalar algebra over small immutable values, and redesigning them would impose broad signature churn across numeric APIs for little semantic gain.

Use this distinction:

- arithmetic traits describe pure value algebra and may remain `self` / value-parameter based
- non-trait methods that merely resemble algebra should still choose receivers by the actual source type's ownership semantics

Apply that rule to API design as follows:

- for small pure value types such as `Duration`, `Date`, `ClockTime`, and `MonoTime`, arithmetic-style methods and nearby derived operations may stay on `self`
- for heavier values or handle-adjacent types such as `DateTime`, follow the type's own `type` or `type mutable` semantics when the method is observational or derived
- for heap-owning containers (typically `type mutable`), set algebra operations such as `union`, `intersection`, `difference`, and `symmetric_difference` follow the container's own semantics even though they are mathematically operator-like

`duration_to` should be classified by type semantics, not by name alone:

- on scalar-like time values (typically `type`), `duration_to(self, other)` is naturally value-style
- on heavier timestamp-like types, follow the type's own declaration semantics

Likewise, predicates such as `is_subset_of` and `is_superset_of` are observational set queries, not arithmetic consumption. They should follow the normal observation semantics for containers.

For non-receiver operands, stay pragmatic. Ordinary parameters do not get receiver adjustment, so the current language design naturally supports `self + value operand` as the right balance for APIs like set algebra and random generation helpers.

If implementing an observation method requires a local value copy to feed an iterator, that is acceptable when the copied value is just a cheap outer handle or immutable small value. Treat that as an implementation artifact, not as evidence that the method should be consuming.

When migrating existing methods to the new `type` / `type mutable` model, recheck two common implementation leftovers:

- branches that still pass or return the receiver by value when the method should preserve it
- helper or iterator constructors that still consume the receiver when they only need observation access

In both cases, the fix is often to adjust the implementation to work with the shared handle rather than consuming the value. This is a migration detail, not a reason to change the public API design.

If the implementation would require copying a large value or heap-owning structure solely to satisfy a consuming iterator API, prefer one of these instead:

- add a helper that traverses storage directly
- add a dedicated borrowed-view iterator type or borrowed-producing helper
- keep the method consuming only if the operation is genuinely consumption-oriented

The public API design should be driven by ownership semantics at the call site, not by the convenience of a specific iterator implementation.

### Trait Design Guidance

For new traits, the receiver semantics are determined by the implementing type's declaration:

- for `type` implementors, `self` provides immutable access suitable for observation traits
- for `type mutable` implementors, `self` provides shared mutable access suitable for mutation traits
- consuming traits use `self` on either kind of type when the method semantically consumes the receiver
- trait-object upcasting uses direct trait names and object safety instead of an `Object` marker trait
- weak capability is opt-in via `mutable` constraints and `?T`

Existing core traits are not fully uniform today. In particular, observation traits such as `ToString` and `Error` already follow borrow-oriented design, while `Eq`, `Ord`, and `Hash` remain value-receiver traits for historical reasons. Treat those core traits as legacy constraints unless the task is explicitly a wider trait redesign.

`Formattable` should currently be treated the same way: it remains rooted in scalar formatting and inherited widely across numeric types. Do not use its scalar-value design as evidence that unrelated derived or observational APIs should follow the same pattern.

### Naming Guidance

Receiver choice and method naming should reinforce each other:

- prefer `into_*` for consuming conversions and ownership-moving adapters
- prefer `to_*`, `as_*`, `with_*`, and predicate/getter names for observation or derivation
- avoid naming a borrowed method in a way that suggests linear consumption

### Review Checklist

Before adding or changing a method in `std/`, ask:

1. After this call, should the caller still expect to use the original receiver value? (Almost always yes; the caller retains the original.)
2. Is the receiver `type` or `type mutable`? (This determines whether `self` is immutable or mutable.)
3. Does the method name match the ownership behavior of the receiver and the method body?

If the type is `type`, all methods are observation or transformation by nature. If the type is `type mutable`, both mutation and observation methods use `self`; verify that the method body matches the stated intent. If the method semantically consumes the receiver, ensure that consumption is part of the public contract (e.g., `into_*` naming).


## 替代方案

**替代方案原文未记载。** 可反推但无取舍记录：

- **`*self` / `*mutable self` 接收者语法**——原文只说「不存在」，没记录是否考虑过。
- **auto-ref / auto-deref**——同上。
- **按方法名决定消耗**（而非由契约）——命名约定是**契约的表达**，不是判定依据；
  但没记录是否曾以名字为准。
- **`Eq`/`Ord`/`Hash` 用值接收者**是登记在案的遗留例外（见「Trait Design Guidance」），
  具体历史未记。

## 风险与未决

- **小纯值类型的豁免边界**——原文明令不得把豁免扩到堆持有类型，但没记录这条边界是怎么划的。
- **算术 trait 保持值语义的完整论证**——只有结论与半句理由（signature churn），无替代方案。
- **object safety 的判据**——见 [`traits-and-givens.md`](traits-and-givens.md)。

## 实施

无单独的实现记录文件。这些约定随 `std/` 的 API 一起落地；新增或修改 `std` API 时按
「Review Checklist」一节的三问自检。

## 同节内原本重复的两处

原文的「Small Pure Value Types」与「Arithmetic Traits」两节各说了一遍
Duration / Date / MonoTime 这类紧凑纯值类型的分类。**并成一处是本次的整理**，
两段原文都逐字保留在上面各自的小节里（未合并、未删改），只是此处记一笔以免后来者以为漏了。

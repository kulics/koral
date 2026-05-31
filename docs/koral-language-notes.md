# Koral Language Notes

## Block Expressions

Block expressions in Koral do **NOT** return the last expression's type (unlike Rust).
They always return `Void` unless a `yield` statement is used inside a branch expression.

```koral
// WRONG - returns Void
let x = { let a = 1; a }

// CORRECT - use yield inside branch expression
let x = if true then { yield 1 } else { yield 2 }
```

## Reference Creation

- `.ref` creates a stack borrow (control = NULL), does NOT allocate heap memory
- `box()` (from std/primitives.koral) creates a heap-allocated reference with ref counting
- `box()` is defined as: `let box[T Any](mut v T) mut ref T = { return v.ref }`
- For rvalues, `.ref` may require a local variable first: `let mut t = Foo(); t.ref`

## Function Naming

- User-defined `main()` conflicts with C standard `main` in codegen
- The codegen generates `int main(int argc, char** argv)` wrapper that calls user's `main`
- This causes C compilation errors due to duplicate `main` definitions

## Codegen Issues (Bootstrap)

- Generic method calls like `List[T].new()` and `list.push()` may generate `void` return type
- This is a bootstrap codegen bug, not present in Swift compiler

## Memory Management

- `__koral_retain(control)` increments reference count
- `__koral_release(control)` decrements reference count, frees when reaches 0
- `__koral_Control` has: strong_count, weak_count, ptr, dtor
- Stack borrows have control = NULL, no retain/release needed

## Intrinsic Functions

- `is_unique_mutable(r ptr ref T) Bool` — checks if ref's strong_count == 1
- `ref_count(r ptr ref T) UInt` — returns ref's strong_count
- Both take `ptr ref T` (raw pointer) to avoid incrementing ref count on call
- Call with `.ptr`: `is_unique_mutable(self.storage.ptr)`
- **Never** pass `mut ref` directly — it triggers retain, inflating strong_count

## COW Pattern (Copy-on-Write)

Dict, List, Deque, Set, String all use COW via `ensure_unique`:
```koral
private ensure_unique(self mut ref) Void = {
    if not is_unique_mutable(self.storage.ptr) then {
        // copy storage
    }
}
```
The `.ptr` is critical — without it, `is_unique_mutable` always returns false
because passing `self.storage` as `ref T` triggers retain.

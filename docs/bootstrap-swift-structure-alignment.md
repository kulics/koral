# Bootstrap-Swift Structure Alignment Baseline

## Current Status (2026-05-31)

Bootstrap compiler memory issue **resolved**. Root cause was `is_unique_mutable`/`ref_count`
intrinsic signatures using `ref T` instead of `ptr ref T`, causing COW containers to always copy.

### Measurements

| Test | Before | After |
|------|--------|-------|
| Dict 100k inserts | 3.6 GB | 13 MB |
| bootstrap hello.koral check | 16 GB | 1.9 MB |
| bootstrap escape_analysis check | ~16 GB | 1.9 MB |
| Swift full test suite | 432/454 | 434/454 |

### Key Fixes Applied

1. **`is_unique_mutable`/`ref_count` signatures**: `ref T` → `ptr ref T`
2. **All call sites**: `self.storage` → `self.storage.ptr`
3. **Swift codegen**: `controlExpression` handles ptr types with `->` access
4. **Bootstrap codegen**: `emit_is_unique`/`emit_ref_count` handle ptr types
5. **Trait hierarchy traversal**: Div/Mul/Rem via Integer inheritance
6. **MIR basic block ordering**: lower_while/lower_block predecessor save
7. **Variable naming**: DefId suffix for locals
8. **TypeVar/TraitObject drop**: included in type_needs_drop
9. **Deque ensure_capacity**: uniqueness check before copy

### Remaining Work

- Bootstrap `--emit-c` generates `void` for generic types (check path works)
- MIR `read[copy]` for mut ref field access through mut ref parameter
- Unifier dictionary reuse

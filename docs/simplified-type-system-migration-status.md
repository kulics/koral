# Simplified Type System Migration Status

Date: 2026-09-17

This document tracks the local implementation of `docs/rfc-simplified-type-system.md` and `docs/developer-guide.md`. No commit should be created until the user reviews the result.

## Ground Rules

- Migration order: Swift `compiler/`, `std/`, tests first; then test runner, samples, and toolchain; then bootstrap aligned to the Swift implementation.
- Compatibility shims are not allowed. Old managed-reference surface syntax and COW paths must be removed instead of preserved.
- Every completed phase must update this file with status, touched areas, validation, and remaining blockers.

## Design Constraints Confirmed

- Remove managed references: `*T`, `*mutable T`, `?*T`, `?*mutable T`, managed `&`, managed `&mutable`, `box()`, and managed dereference.
- Keep raw pointers: `*unsafe T`, `*unsafe mutable T`, `&unsafe`, `&unsafe mutable`, and raw pointer dereference.
- Add declaration-site mutability: `type A` and `type mutable B`; enum and aliases cannot be `type mutable`.
- Receiver syntax becomes only `self`; no `*self`, `*mutable self`, receiver auto-ref, or receiver auto-deref.
- Trait object surface types are direct trait names, not `*Trait` or `*mutable Trait`.
- Weak references use `?T` and require explicit `Weak` conformance; remove `upgrade_mutable` and `downgrade_mutable`.
- `Deref`, `not Deref`, blanket ref conformances, escape analysis, managed-reference allocation promotion, and COW uniqueness checks are removal targets.
- Standard library containers and stateful iterators become shared `type mutable` objects with explicit `clone()` for independent copies.

## Phase Plan

| Phase | Scope | Status | Validation |
|---|---|---|---|
| 0 | RFC/developer-guide scan and implementation anchors | Done | Local document created |
| 1 | Swift compiler surface model: AST/parser/type metadata for `type mutable`, `?T`, receiver `self`, and old syntax rejection | In progress | `swift build -c debug` plus focused parser/type cases |
| 2 | Swift compiler semantic/model cleanup: remove managed reference types, auto receiver adaptation, `Deref`, weak mutable split, and COW intrinsics | Not started | Focused semantic negative/positive cases |
| 3 | Swift MIR/codegen/runtime cleanup: remove managed-ref lowering/promoter paths while preserving runtime ARC as implementation detail | Not started | Focused build/run cases and generated C smoke checks |
| 4 | `std/` migration: type classifications, receiver signatures, weak API, Drop, containers, String/StringBuilder, no COW | Not started | Swift-hosted std/compiler cases |
| 5 | Tests migration: replace legacy managed-ref/COW/receiver-adaptation cases with new semantics | Not started | Shared runner against Swift compiler |
| 6 | Test runner, samples, and toolchain migration | Not started | Build/run affected tools and samples |
| 7 | Bootstrap full alignment using Swift implementation logic, adjusted for no COW containers | Not started | Host-built bootstrap runner and staged self-host validation |
| 8 | Final report for user review | Not started | Summary of changes, validations, and residual risks |

## Progress Log

- 2026-09-17: Read RFC and developer guide. Confirmed developer guide still documents old managed-reference and receiver rules, so migration must update implementation and documentation together rather than preserve old behavior.
- 2026-09-17: Located initial Swift compiler anchors: `Parser/AST.swift`, `Parser/ParserTypes.swift`, `Parser/ParserDeclarations.swift`, `Sema/Type.swift`, `Sema/TypeCheckerTypeResolution.swift`, `Sema/TypeCheckerExpressions.swift`, `Sema/TypeCheckerMethods.swift`, `MIR/MIR.swift`, `MIR/MIRReferenceAllocationPromoter.swift`, and `CodeGen/CodeGenMIR.swift`.

## Current Local Hypothesis

The smallest useful first implementation slice is to add nominal mutability metadata and parse `type mutable` while rejecting old managed receiver/type syntax at the parser boundary. This can be falsified cheaply by building the Swift compiler and adding/running a focused syntax case before deeper sema/MIR cleanup.

## Blockers

- None currently. The expected risk is broad downstream compile breakage once compatibility code is removed.
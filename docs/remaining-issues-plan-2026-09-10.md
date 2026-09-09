# Remaining Deep-Fix Plan (2026-09-10)

This document renumbers only the issues that are still not fully resolved after commit `b656b1cc` and the follow-up bootstrap hardening work that was validated locally.

## Closed Since The Original 12-Issue List

- Old `#1/#8`: bootstrap exhaustiveness now runs on the recursive pattern-space path.
- Old `#2`: recursive occurs-check fixed in both Swift and bootstrap.
- Old `#5`: trait inheritance cycle / duplicate-parent validation fixed.
- Old `#6`: nested lambda shadow-capture contamination fixed.
- Old `#10`: same-name trait and same-name generic helper binding across modules fixed.
- Old `#11`: bootstrap frontend diagnostics moved to structured, file-aware diagnostics.
- Old `#12` large parts: bootstrap sema panic paths were converted to diagnostics; several user-facing mono/driver crash paths were also downgraded to diagnostics.

## Remaining Issues (Renumbered)

### R1. Parser Acceptance Logic Is Still Distributed

Maps from old issue: `#3`

Current state:

- Parser diagnostics and several acceptance edge cases were cleaned up.
- The actual acceptance logic is still spread across:
  - `bootstrap/koralc/parser/core.koral`
  - `bootstrap/koralc/parser/core_expressions.koral`
  - `bootstrap/koralc/parser/core_precedence.koral`

Why this is still open:

- Expression-vs-type-vs-declaration admission is still controlled by multiple local predicates such as `is_type_start`, `should_continue_postfix_after_expression`, `is_expr_start_token`, and many ad hoc token checks.
- The current design still makes newline/ASI behavior, postfix continuation, generic application, and named-argument acceptance drift-prone.

Exit criteria:

- A single shared acceptance layer decides:
  - expression starts
  - type starts
  - postfix continuation eligibility
  - declaration-start classification
- Parser files stop duplicating local token-shape decisions.
- Existing parser regression buckets remain green.

Suggested implementation direction:

- Introduce a small shared parser classification module or a consolidated helper region in `core.koral`.
- Route `core_expressions` and `core_precedence` through that shared decision layer rather than re-checking token families independently.

### R2. Interpolation Is Not Yet A True Lexer-Level Sublanguage

Maps from old issue: `#4`

Current state:

- Error reporting for interpolation is now file-aware and structurally diagnostic.
- Bootstrap still lexes normal string bodies first, then reparses embedded expression source text via parser-side helper recursion.

Why this is still open:

- Interpolation still relies on parser-side embedded lex/parse (`parse_embedded_expression`) rather than a first-class lexer mode.
- Escape handling is duplicated across string processing helpers in the lexer.
- Embedded-expression spans and token ownership are still reconstructed rather than preserved at tokenization time.

Primary files:

- `bootstrap/koralc/lexer/scanner.koral`
- `bootstrap/koralc/parser/core_precedence.koral`

Exit criteria:

- String interpolation is tokenized through a dedicated lexer mode or equivalent structured token stream.
- Embedded expressions preserve source positions without reparsing opaque string fragments.
- Escape processing logic for string/interpolation stops being duplicated in two separate helper stacks.

### R3. Managed-Reference Lifetime / Escape Analysis Is Still Heuristic

Maps from old issue: `#7`

Current state:

- Many concrete regressions are covered and fixed.
- The implementation still relies on conservative summaries and heuristic lowering choices rather than a full CFG dataflow model.

Why this is still open:

- Borrow vs heap-owned managed-reference decisions still depend on local lowering heuristics, owner-shape checks, and summary propagation instead of a whole-function fixed-point analysis.
- Remaining edge cases are most likely in alias-heavy control flow, nested closures, and conditional ownership transfer.

Primary areas:

- `bootstrap/koralc/codegen/codegen_mir.koral`
- `bootstrap/koralc/mir/*`
- `bootstrap/koralc/sema/type_checker_expressions_lowering.koral`

Exit criteria:

- Ownership / escape decisions are computed from explicit CFG dataflow.
- Closure capture, branch merge, alias container store, and borrowed/managed transitions share one analysis model instead of several local heuristics.

### R4. One MIR-Lowering Invariant Panic Still Remains

Maps from old issue tail: `#12`

Current state:

- Remaining bootstrap pipeline panic is:
  - `bootstrap/koralc/mir/mir_function_builder.koral`
  - `panic("Unsupported generic reference expression reached MIR lowering")`

Why this is still open:

- This guard currently protects against a state the compiler still treats as impossible.
- A naive downgrade risks producing invalid MIR rather than a clean user-facing failure.

Exit criteria:

- Either upstream guarantees prove the state impossible and the invariant is removed by construction,
  or MIR lowering gains a conservative, diagnostic-producing fallback that does not generate invalid MIR.

### R5. Type-Equivalence / Canonicalization Still Needs A Full Audit

Maps from old issue tail: `#9`

Current state:

- Hot paths now treat concrete instantiated nominal types as equivalent to matching generic nominal forms where needed.
- Several active alias/canonicalization regressions were fixed.

Why this is still open:

- Equality and compatibility logic is still distributed across `same_expr_type`, call adaptation, method lookup, and mono/type-resolution fallback paths.
- The current fixes are sufficient for covered regressions, but not yet a proof that all nominal/generic/alias equality paths are unified.

Primary areas:

- `bootstrap/koralc/sema/type_checker.koral`
- `bootstrap/koralc/sema/type_checker_methods.koral`
- `bootstrap/koralc/sema/type_checker_expressions_static_calls.koral`
- `bootstrap/koralc/mono/mono_type_resolution.koral`

Exit criteria:

- One shared equivalence model covers:
  - concrete instantiated nominal vs generic nominal
  - alias-expanded vs direct nominal
  - wrapper/reference family compatibility where intended
- Existing compatibility checks stop relying on path-specific ad hoc comparisons.

## Recommended Execution Order

1. `R4` — smallest remaining hard crash surface; contained and safety-critical.
2. `R1` — reduces parser drift and simplifies later parser/interpolation work.
3. `R2` — easier once parser acceptance is centralized.
4. `R5` — broad audit after current hotspot fixes are stable.
5. `R3` — largest architectural item; likely requires a dedicated design pass.

## Current Validation Anchors

- Bootstrap full suite clean anchor:
  - `tests/compiler-cases_output/_reports/bootstrap-validation-2026-09-10-current-25.report.log`
- Swift full suite clean anchor for the last Swift-touching change set:
  - `tests/compiler-cases_output/_reports/swift-validation-2026-09-09-current-7.report.log`

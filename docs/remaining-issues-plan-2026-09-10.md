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

## Closed Since This Renumbered List

- `R1`: parser acceptance logic is now consolidated enough to close for the current backlog. The latest work pulled named-argument lookahead, range-bound starts, generic function/method instantiation diagnostics, control-statement terminator checks, and top-level declaration flag classification into shared parser helper layers on both compilers. The current shared suite is green end-to-end on both compilers, including the newly added parser regressions.
- `R4`: MIR-lowering invariant panic chain is resolved in the current local code state. Bootstrap parser/sema/mono/driver crash paths now route through diagnostics instead of unrecovered panics.

## Remaining Issues (Renumbered)

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

1. `R2` — now the next parser/frontend architecture item after `R1` closure.
2. `R5` — broad audit after the parser acceptance work has been stabilized.
3. `R3` — largest architectural item; likely requires a dedicated design pass.

## Current Validation Anchors

- Final local `R1` closure full-suite anchors:
  - `tests/compiler-cases_output/_reports/bootstrap-validation-2026-09-10-r1-final.report.log` (`575/575`)
  - `tests/compiler-cases_output/_reports/swift-validation-2026-09-10-r1-final.report.log` (`575/575`)
- Earlier clean parser-work anchors during the `R1` batch:
  - `tests/compiler-cases_output/_reports/bootstrap-validation-2026-09-10-r1-postfix-current-rerun.report.log`
  - `tests/compiler-cases_output/_reports/swift-validation-2026-09-10-r1-postfix-current.report.log`
- Earlier clean bootstrap anchors:
  - `tests/compiler-cases_output/_reports/bootstrap-validation-2026-09-10-current-21.report.log`
  - `tests/compiler-cases_output/_reports/bootstrap-validation-2026-09-10-current-25.report.log`
- Earlier clean Swift anchor before this `R1` parser batch:
  - `tests/compiler-cases_output/_reports/swift-validation-2026-09-09-current-7.report.log`

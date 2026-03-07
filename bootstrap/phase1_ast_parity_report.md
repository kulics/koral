# Bootstrap Phase1 AST Parity Report

This checklist tracks bootstrap `koralc` frontend parity against Swift `Parser/AST.swift`.

## Current Status

- Declaration-level shape: partially aligned.
- Using declaration rules: aligned for path validation and module-merge constraints.
- Diagnostics scaffolding: present, but AST-wide structured spans are not yet wired.
- Statement/Expression/Pattern taxonomy: not yet fully aligned.

## Newly Aligned In This Step

- `using` parser now enforces Swift-like constraints:
  - module merge (`...`) only allowed for `self` paths;
  - module merge cannot use explicit access modifier;
  - `self`/`super` paths require concrete item segments;
  - `super` may only appear in leading path segments;
  - batch import (`.*`) cannot be aliased.
- Statement-level span propagation started:
  - all `Statement` variants now carry a `SourceSpan` field;
  - parser records start/end spans (from first token to last consumed token).
- Expression-level span propagation started:
  - parser now wraps parsed expressions as `Expr.Spanned(expr, SourceSpan)`;
  - statement parsing and printer paths handle wrapped expressions.
- Statement parity improved:
  - dedicated `deptr` assignment statement node is now emitted by parser.
- Pattern/Match alignment improved:
  - introduced `PatternNode` in bootstrap AST;
  - `if/while/for/when` now carry typed patterns instead of raw string fields;
  - unified expression naming/syntax to `when ... in { ... }`.
- Literal alignment improved:
  - added `EmptyLiteral`, `CollectionLiteral`, and `MapLiteral` expression nodes.
- Declaration span migration completed:
  - all `Decl` variants now carry `SourceSpan`.
- Expression span migration completed through parser/printer pipeline:
  - parser now emits `Expr.Spanned` across expression construction paths (identifier/literal/unary/binary/call/control-flow/collection/map);
  - printer and statement plumbing preserve/display the migrated AST shape.

## Remaining High-Priority Gaps

1. Span propagation across AST nodes
- Swift AST carries `SourceSpan` on global/statement/expression/pattern nodes.
- Bootstrap now has declaration/statement/pattern spans and full expression span coverage via `Expr.Spanned`; remaining mismatch is mainly representation style (Swift uses per-variant span fields on many nodes).

2. Expression node parity
- Missing or merged variants compared with Swift model:
  - lambda/function literal node;
  - richer call classification (generic/static/qualified-call distinctions);
  - `float` / `rune` literal nodes;
  - explicit `self` node is still represented as identifier.

3. Pattern node family depth
- Bootstrap now has `PatternNode`, but parser currently only recognizes basic forms (`_`, bool, int, variable, simple union-case token) and falls back to broad variable mapping.
- Missing structured parsing for comparison/logical/struct patterns and nested union payload patterns.

4. Expression representation style
- Swift expression AST stores span directly on several concrete variants.
- Bootstrap uses uniform `Expr.Spanned` wrappers for full expression span coverage.

5. `UsingDeclaration.importedSymbol`
- Field exists and remains `None`, consistent with current Swift parser behavior.

## Recommended Next Order

1. Add node-level `span` to statement and expression variants (minimum viable first).
2. Add `SourceSpan` to global declaration nodes and parser construction sites.
3. Replace `Expr.Spanned` wrapper with per-variant expression spans where Swift uses explicit span-carrying nodes.
4. Deepen pattern parser (comparison/logical/union payload/struct patterns) and align call-family nodes.

# Swift Compiler MIR Design

This document defines the MIR layer planned for the Swift implementation of
`koralc`. The bootstrap compiler is intentionally out of scope for the first
implementation pass; once the Swift version stabilizes, the bootstrap compiler
should copy the same data model and lowering rules.

## Goals

MIR is the compiler's typed middle representation between monomorphization and
backend code generation. It exists to make the compiler easier to maintain and
to give later module-level compilation optimizations a stable representation to
work on.

The target pipeline is:

```text
parse -> module resolution -> sema/typed AST -> monomorphization
      -> MIR lowering -> MIR analyses/transforms -> backend emission
      -> clang/link
```

The first Swift milestone should introduce MIR as a real pipeline product and
validate it on every non-`check` compilation. Later milestones move logic out of
the C backend and into MIR until the backend becomes mostly a printer for an
already-lowered program.

Concrete goals:

- Keep the typed AST as the high-level semantic result, not as the backend IR.
- Lower expression-oriented Koral bodies into explicit function bodies with
  locals, places, basic blocks, branches, and cleanup boundaries.
- Move ownership decisions, temporary cleanup, escape summaries, branch result
  materialization, and pattern control flow out of C generation.
- Keep Koral's value semantics, managed references, pattern binding aliases,
  `yield`, `finally`, trait objects, and closure captures explicit enough that
  later optimizations can reason about them.
- Make module-level optimization possible by storing summaries and, later, MIR
  for compiled modules.

Non-goals for the first milestone:

- Do not redesign parsing, type checking, or module resolution.
- Do not change Koral surface syntax.
- Do not require the bootstrap compiler to support MIR immediately.
- Do not make MIR a C-specific representation; C lowering remains a backend
  concern.

## Current Swift State

The Swift compiler now lowers concrete monomorphized declarations into MIR and
the C backend consumes that MIR. `CodeGen` no longer stores or walks
`MonomorphizedProgram`, `TypedExpressionNode`, `TypedStatementNode`,
`TypedPattern`, or `TypeNode`. It still owns target C spelling, runtime ABI
helper emission, copy/drop helper names, vtable instance emission, native link
inputs, and the generated C `main` wrapper, but it does not re-lower language
semantics from the typed AST.

The current backend boundary is:

- MIR owns function bodies, globals, global initializer functions, scopes,
  branch result materialization, `yield`, `finally`, pattern CFG lowering,
  lambda construction, trait object ABI nodes, and reference allocation policy.
- MIR reference allocation has only `stackBorrow` and `heapOwned`. Escape-driven
  promotion is handled by `MIRReferenceAllocationPromoter`, not by CodeGen.
- MIR vtable globals carry concrete type, trait name, trait type arguments, and
  ordered method layout. CodeGenVtable no longer sorts trait declarations or
  resolves `TypeNode` for vtable signatures.
- Typed AST remains the semantic input to monomorphization and MIR lowering. New
  structured queries that describe typed-tree control-flow metadata should live
  with the typed AST, not inside MIRLowerer or CodeGen.

## Placement

MIR should be built after monomorphization, not before it.

Reasons:

- Koral uses generics heavily in the stdlib; backend work is simpler and more
  optimizable once generic functions and nominal layouts are concrete.
- Trait object vtable requests and receiver dispatch metadata are already
  collected by monomorphization.
- Module optimization can cache and compare concrete reachable functions without
  requiring a second generic IR design.

The typed AST remains the sema output. Monomorphization remains responsible for:

- Generic type/function instantiation.
- Resolving generic calls and static method calls that must become concrete.
- Producing concrete struct/enum declarations, function declarations, given
  methods, vtable requests, and receiver dispatch metadata.

MIR lowering is responsible for each concrete function or global initializer
body after those decisions are available.

## Typed AST Design Pressure Points

The current typed AST is good as a sema result, but MIR lowering has exposed a
few shapes that make conversion and later analysis harder. The Swift compiler
now keeps one small MIR-facing query in typed AST itself:

- `TypedYieldSummary` records every `yield` target in a typed subtree and the
  subset of targets owned by that expression/statement result. MIRLowerer uses
  this instead of keeping private duplicate traversals. Bootstrap should copy
  this idea early because it makes branch-expression lowering and cleanup joins
  much easier to audit.
- `TypedPattern` exposes binding-symbol and wildcard/conditionless-payload
  queries. MIRLowerer uses these instead of keeping private pattern tree walks
  for local declaration and simple-pattern decisions.

The remaining pressure points are follow-up design work, not CodeGen fallbacks:

- `whenStatement`/`whenExpression` and `TypedStatementMatchCase`/`TypedMatchCase`
  duplicate the same matching concept. A single typed match expression plus a
  statement wrapper would make MIR lowering, exhaustiveness metadata, and branch
  cleanup planning easier to share.
- Pattern bindings are currently stored as `(String, Bool, Type)` instead of
  typed binding symbols with stable `DefId`s, binding mode, and projection path.
  This forces later stages to reconstruct alias semantics and makes pattern
  scopes harder to reason about.
- `TypedPattern` stores source-like pattern syntax, but not a checked decision
  tree or reusable condition/binding plan. A post-sema `TypedPatternPlan` would
  let MIR lower `is`, `if is`, `while is`, and `when` through the same structure.
- `methodReference` is a typed expression even though it is usually only valid in
  call position. A resolved callee form that explicitly distinguishes unbound
  methods, bound closures, direct functions, trait dispatch, and generic
  placeholders would reduce special cases in monomorphization and MIR lowering.
- `genericCall` and `staticMethodCall` keep late-resolution information in the
  expression tree. Once monomorphization resolves them, a direct callee symbol
  plus instantiation metadata would be easier for MIR and escape analysis to
  consume.
- Some monomorphized calls can still expose generic-shaped callee or argument
  types, especially generic receiver methods with reference parameters. MIR can
  preserve these explicitly, but the cleaner long-term shape is a fully concrete
  call signature paired with any template-origin metadata needed for diagnostics.
- `referenceExpression` and `ptrExpression` do not record allocation/lifetime
  decisions. MIR currently has to infer stack borrow versus heap-owned reference
  construction; a later escape-allocation annotation pass could make this
  explicit before CodeGen.
- `yield` and `finally` are still statement nodes with side-channel target IDs.
  MIR lowers explicit branch-expression `yield` targets into result assignments
  and join edges, and expands scope-registered `finally` expressions on normal
  scope exits plus `return`, `break`, `continue`, and `yield` cleanup edges.
  `TypedYieldSummary` is the typed-tree bridge for this; future work should add
  similarly explicit typed summaries for pattern binding plans and cleanup
  sensitivity.
- `memberPath` stores a flat symbol path but not the projection semantics that
  matter to ownership, reference boundaries, and aliasing. A typed projection
  chain would be a better input for MIR place construction.

## Shape Of MIR

Koral MIR should be closer to Swift SIL and Go's typed IR than to LLVM IR. It
should keep high-level types, explicit places, and ownership actions. It should
not start as pure SSA. A mutable-local CFG is a better first fit because Koral
has explicit value semantics, addressable paths, lexical cleanup, and
language-level references. SSA can be added later as a transform for selected
values.

### Program

```swift
public struct MIRProgram {
  public let globals: [MIRGlobal]
  public let functions: [MIRFunction]
  public let context: CompilerContext
  public let staticMethodLookup: [String: DefId]
  public let traits: [String: TraitDeclInfo]
  public let receiverMethodDispatch: [DefId: ReceiverMethodDispatchInfo]
}
```

`MIRProgram` deliberately does not retain `MonomorphizedProgram`. If CodeGen
needs a global declaration, function body, static method lookup, receiver method
name, or vtable request, MIR must carry that fact explicitly. This is the most
important boundary for the bootstrap port: do not add a source-program escape
hatch to the backend.

### Globals

MIR preserves declarations separately from executable bodies:

- Foreign type declarations.
- Foreign struct declarations.
- Foreign functions and foreign globals.
- Struct and enum layout declarations.
- Global variables, whose initializer is either constant data or a MIR function
  fragment run from generated `main` initialization.
- Function declarations.
- Given methods.
- Vtable generation requests and trait metadata copied from monomorphization.
  These are explicit MIR globals keyed by concrete type, trait name, and trait
  type arguments. `MIRTraitVTable.methods` stores the ordered method layout with
  resolved parameter/return types and `selfByValue`, so a backend does not sort
  trait declarations or parse `TypeNode` while emitting vtables.

### Functions

```swift
public struct MIRFunction {
  public let identifier: Symbol
  public let parameters: [Symbol]
  public let returnType: Type
  public let kind: MIRFunctionKind
  public let entryBlock: MIRBlockID
  public var locals: [MIRLocal]
  public var blocks: [MIRBasicBlock]
}
```

There is no `sourceBody` migration bridge in `MIRFunction`. Source typed bodies
are consumed by `MIRLowerer` and are not exposed to CodeGen.

### Locals And Places

MIR needs to represent addressability directly:

```swift
public struct MIRLocal {
  public let id: MIRLocalID
  public let name: String
  public let type: Type
  public let mutability: MIRMutability
  public let storage: MIRStorage
}

public enum MIRPlace {
  case local(MIRLocalID)
  case global(DefId)
  case field(base: MIRPlace, field: Symbol)
  case deref(base: MIRValue, pointee: Type)
  case pointerElement(base: MIRValue, element: Type)
}
```

Places are the MIR version of lvalues. They are used for assignment, ref/ptr
formation, field access, drop targets, and pattern bindings. This should replace
backend-only string paths such as `patternBindingAliases` over time.

### Values And Operands

```swift
public enum MIRValue {
  case operand(MIROperand)
  case placeRead(MIRPlace, ownership: MIROwnershipUse)
  case binary(MIRBinaryOperation)
  case unary(MIRUnaryOperation)
  case call(MIRCall)
  case aggregate(MIRAggregate)
  case enumCase(MIREnumConstruction)
  case enumTag(MIREnumTag)
  case traitObjectConversion(MIRTraitObjectConversion)
  case traitMethodCall(MIRTraitMethodCall)
  case ref(MIRPlace, kind: MIRReferenceKind, allocation: MIRReferenceAllocation)
  case pointer(MIRPlace)
  case cast(MIROperand, to: Type)
  case intrinsic(MIRIntrinsic)
  case lambda(MIRLambda)
}

public enum MIROperand {
  case local(MIRLocalID)
  case constant(MIRConstant)
  case function(Symbol)
}

public enum MIRReferenceAllocation {
  case stackBorrow
  case heapOwned
}
```

`placeRead` is explicit because reading a place can mean copy, move, borrow, or
plain scalar load depending on type and use site. Reference allocation is also
explicit before CodeGen sees it; there is no unresolved allocation state.

### Statements And Terminators

```swift
public enum MIRStatement {
  case declare(MIRLocalID)
  case assign(MIRPlace, MIRValue)
  case drop(MIRPlace)
  case retain(MIRValue)
  case release(MIRValue)
  case evaluate(MIRValue)
  case scopeEnter(MIRScopeID)
  case scopeExit(MIRScopeID)
  case finallyRegister(MIRValue)
  case debugSource(SourceSpan)
}

public enum MIRTerminator {
  case goto(MIRBlockID)
  case branch(condition: MIROperand, then: MIRBlockID, else: MIRBlockID)
  case switchValue(MIROperand, cases: [MIRSwitchCase], default: MIRBlockID?)
  case `return`(MIROperand?)
  case unreachable
}
```

MIR function bodies should be self-contained at this layer. If a backend needs
to know a branch, cleanup, ref allocation, lambda, or trait-object operation, it
should be represented here instead of recovered from a typed expression.

## Koral-Specific Semantics MIR Must Model

### Expression-Oriented Control Flow

Koral `if` and `when` are expressions. MIR should lower them to explicit result
locals and branch blocks:

```text
result = uninit T
branch cond then_bb else_bb
then_bb:
  ...
  assign result, then_value
  goto join
else_bb:
  ...
  assign result, else_value
  goto join
join:
  use result
```

`yield` becomes an assignment to the current expression result local plus a scope
exit edge to the expression join block. The current MIR lowerer handles explicit
branch-expression yields in `if`, `if is`, and `when`, and includes registered
`finally` actions while emitting those scope exits.

C backend lifetime planning must be CFG-aware enough not to extend loop-body
temporaries to function-root lifetime. A local declared in a MIR scope should
stay scoped when all recorded uses occur while that scope is active; only values
genuinely used after the scope exit, such as branch result locals, should be
promoted to an outer cleanup boundary.

### Lexical Cleanup And `finally`

MIR lowering should build lexical scopes and cleanup stacks before backend
emission:

- Variables that need cleanup are registered in a MIR scope.
- Full-expression temporaries are registered in a temporary cleanup range and
  dropped at the end of the statement.
- `finally` is registered in the current scope and expanded on every scope exit.
- `return`, `break`, `continue`, and `yield` use cleanup edges computed by MIR.

The Swift backend has already removed `lifetimeScopeStack`, `deferScopeStack`,
and `yieldTargetStack`. Bootstrap should follow the same owner split: CodeGen
may emit C for MIR `scopeExit`/cleanup effects, but it should not maintain a
parallel lexical-scope model.

Bootstrap `check` should run the same type-checking body pipeline as build and
the Swift compiler. A separate "check without typed program" body pass diverges
from the Swift pipeline, keeps different ownership pressure on typed bodies, and
has already exposed runaway memory use during stdlib checking.

### Value Semantics And Ownership

MIR should use explicit ownership use kinds:

- `copy`: source remains valid; composite values call copy helpers or retain.
- `move`: source is consumed and unregistered from cleanup.
- `borrow`: source remains owned elsewhere; used for pattern subjects and ref
  formation.
- `take`: reads from raw memory and transfers ownership.

The current helper decisions in `CodeGen` such as `shouldCopyValue`,
`consumeCleanupRegisteredValueIfMoved`, `appendCopyAssignment`, and
`appendDropStatement` should migrate into MIR ownership lowering and an ABI
lowering helper that the backend calls.

### References, Pointers, And Escape Analysis

Koral has managed references (`ref T`, `mut ref T`), weak references, and raw
pointers (`ptr T`, `mut ptr T`). MIR should distinguish:

- A place borrow from an addressable local or field.
- An owned heap reference created for rvalues or escaping locals.
- A raw pointer formed from a place.
- A dereference place formed from a ref or pointer value.

Reference escape allocation is now a MIR analysis/transform because MIR knows
precise stores, returns, pointer writes, closure captures, and call edges. The
current Swift pass is `MIRReferenceAllocationPromoter`: it computes
interprocedural parameter summaries, separates stored-parameter escapes from
return-parameter dependencies, and promotes local ref construction from
`stackBorrow` to `heapOwned` only when needed.

Longer-term module summaries can expose the same facts in a serializable form:

```swift
public struct MIREscapeSummary {
  public let parameterStates: [ParameterEscapeState]
  public let escapedLocals: [MIRLocalID: EscapeResult]
}
```

Do not restore a typed-AST `GlobalEscapeAnalyzer` in CodeGen. During bootstrap
porting, temporary analysis code should live beside MIR lowering/verification so
it can be deleted or serialized without crossing the backend boundary.

### Pattern Matching

Pattern matching should lower into a pattern decision tree over MIR places.
Pattern-bound variables should become aliases to places first, not copied C
strings. A later ownership pass decides whether a binding needs materialization.
The current Swift MIR lowerer already handles scalar tests, enum tag tests,
binding-free `or`/`and` pattern conditions, and direct enum payload aliases such
as `.Some(v)` or `.Closed(start, end)` for simple `when`, `if is`, and `while is`
CFG lowering. More complex subpatterns, pattern combinators with bindings, and
cleanup-sensitive plans remain for the full decision-tree pass.

Pattern subjects are evaluated into a dedicated MIR temporary before tests and
payload bindings. If the subject expression is an lvalue, this preparation must
use `copy`, not `move`, even for parameters; source-level pattern tests do not
consume reusable locals. Rvalue subjects can still be moved into the temporary.

Important cases:

- Literal scalar tests.
- Enum tag tests and payload places.
- Struct and pair field places.
- Or/and/not pattern combinators.
- Variable binding aliases for `when`, `if is`, `while is`, and `is` checks.

Simple scalar and enum matches can still become switch terminators; complex
patterns can lower to chained test blocks.

### Loops

`while` lowers to condition, body, and exit blocks. `while is` lowers by
evaluating the subject each iteration, checking the pattern, binding aliases for
the body, and cleaning the subject scope on mismatch and after each iteration.

`for` should already be represented in typed AST through iterator calls or other
lowered constructs where possible. If high-level `for` remains visible in typed
AST, MIR should lower it to explicit iterator local, `next` call, pattern test,
body, and cleanup.

### Lambdas And Trait Objects

MIR should represent closure construction separately from C emission:

- Captured locals and capture kind.
- Environment allocation/layout request.
- Closure function symbol and call ABI.

Trait object conversion and trait method calls are explicit MIR values, not
typed-expression bridges. They carry the evaluated receiver/inner value, source
ownership (`copy` for lvalue conversion, `move` for rvalue conversion),
dynamic-call receiver and argument ownership, trait name, trait type arguments,
concrete type, method name/index, and result type. MIR globals carry the
corresponding vtable requests and ordered method layout. CodeGen consumes these
as ABI operations; it must not recover vtable inventory or signatures from
`MonomorphizedProgram` or trait AST declarations.

The MIR verifier treats the vtable inventory as an ABI contract: each trait
object conversion must have a matching vtable global keyed by concrete type,
trait name, and trait type arguments. It also uses `MIRTypeResolver` to check
that conversion sources are concrete references and dynamic trait receivers are
trait object references matching the node metadata. Dynamic trait calls preserve
trait type arguments directly on the MIR node, so a backend can name the
specialized vtable struct without asking the typed receiver expression for its
type. When resolving vtable method signature types during lowering, prefer
monomorphized global declarations over raw `CompilerContext.lookupDefId`; this
prevents unqualified names such as `String` from becoming invalid C forward
declarations like `struct String` instead of the generated `struct Std_String`.

## Lowering Rules

### Function Body Lowering

For each `TypedGlobalNode.globalFunction` and each concrete given method:

1. Create a `MIRFunction` with parameter locals in the entry scope.
2. Lower the body expression into a value or terminal control flow.
3. If the body type is not `Void` or `Never`, materialize the implicit return
   value using copy/move rules.
4. Emit cleanup for all live scopes.
5. Emit a return terminator.

### Expression Lowering

Expression lowering should return an `MIRExprResult`:

```swift
public struct MIRExprResult {
  public let type: Type
  public let category: ValueCategory
  public let operand: MIROperand?
  public let place: MIRPlace?
}
```

Lvalue expressions return a place. Rvalue expressions return an operand. When an
rvalue must live beyond the immediate instruction, lowering materializes a MIR
temporary local.

### Statement Lowering

Statement lowering should own full-expression cleanup:

- `let`: lower initializer, declare local, assign by copy/move, register local
  cleanup if needed, clean other temporaries.
- Pair destructuring: materialize pair, move or drop fields, avoid dropping the
  consumed pair aggregate.
- Assignment: lower lhs as place, rhs as value, materialize rhs first if the lhs
  needs overwrite drop, then drop old lhs and assign new value.
- Expression statement: evaluate, drop unused rvalue if needed, clean temps.
- `return`: lower value, move/copy to return temp, run cleanup edge, return.
- `break`/`continue`: run cleanup edge to the loop's exit or condition block.
- `finally`: register cleanup expression in the current scope.
- `yield`: assign enclosing expression result, run cleanup edge, branch to join.

## MIR Analyses And Transforms

Initial analyses:

- MIR verifier: block existence, terminators, local definitions, type agreement,
  reachable entry block, no unresolved generic types in lowered functions, and
  type-resolved ABI contracts for trait object conversions and dynamic trait
  calls.
- Function inventory: concrete functions, given methods, globals, trait/vtable
  metadata.
- Escape summaries: initially bridge the existing analyzer; later rewrite on MIR.

Near-term transforms:

- Cleanup insertion/elaboration.
- Pattern decision tree lowering.
- Copy/move/drop elaboration.
- Simple constant folding and unreachable block pruning.

Later module optimizations:

- Per-module MIR summaries for public functions and reachable private helpers.
- Cross-module dead declaration pruning based on reachable DefIds.
- Function body hashing for incremental rebuilds.
- Inline candidates for small functions where public ABI and ownership effects
  are stable.
- Serialized escape/effect summaries to avoid re-analyzing dependencies.

## Backend Boundary

The backend should eventually consume only MIR plus type/layout metadata.
Backend-owned responsibilities should be limited to:

- C type spelling and symbol spelling.
- Runtime ABI calls such as `__koral_retain`, `__koral_release`, closure helpers,
  vtable instances, and drop/copy helper names.
- Target-specific link arguments and generated C `main` wrapper.

Backend should not decide:

- Which branch owns an expression result.
- Which scopes need cleanup on a control-flow edge.
- Whether a reference source escapes.
- Whether a pattern binding is an alias or materialized local.
- Whether a source is copied or moved at a language level.

## Migration Plan

As of 2026-05-29, the Swift compiler is past the original MIR-only backend
cleanup milestone:

- `MIRProgram.source` and `MIRFunction.sourceBody` are gone.
- CodeGen emits functions from `MIRFunction` and globals from `MIRGlobal`.
- Old typed CodeGen files (`CodeGenExpressions.swift`, `CodeGenStatements.swift`,
  `CodeGenMemory.swift`, `CodeGenLambda.swift`, `EscapeAnalysis.swift`) are
  deleted.
- MIR owns global initializer functions, lambda values, trait object ABI nodes,
  vtable request layout, and ref allocation promotion.
- Full Swift compiler suite status for this boundary: `449/449` passed with the
  shared compiler runner.

The phase list below remains useful as a bootstrap implementation map, but the
Swift implementation should be treated as the source of truth for details.

### Phase 0: MIR Skeleton And Pipeline Validation

- Add `compiler/Sources/KoralCompiler/MIR/`.
- Define `MIRProgram`, `MIRGlobal`, `MIRFunction`, blocks, locals, statements,
  terminators, places, and operands.
- Add `MIRLowerer` that walks `MonomorphizedProgram` and creates a conservative
  MIR function/global inventory with entry/return blocks and explicit lowered
  body statements.
- Add `MIRVerifier` and run it from `Driver.performCompilation` after
  monomorphization and before C codegen.
- Keep current C codegen consuming `MonomorphizedProgram`.

This phase is intentionally low risk and makes MIR a real checked pipeline
artifact without changing runtime behavior.

### Phase 1: Structured Body Lowering

- Lower primitive literals, locals, arithmetic, calls, block expressions,
  variable declarations, assignment, return, if expressions, and while loops into
  explicit MIR.
- Add an optional MIR dump controlled by an environment flag such as
  `KORAL_DUMP_MIR=1`.
- Add a summary-only dump such as `KORAL_DUMP_MIR_STATS=1` that reports counts
  for blocks, locals, statements, values, calls, vtables, lambdas, trait ABI
  operations, and ref allocations. This keeps migration progress measurable
  without requiring a full MIR dump for large programs.
- Include the top MIR-codegen blocker functions in summary output so migration
  slices can target concrete functions instead of searching a full MIR dump.
- Lower concrete receiver method calls as ordinary MIR calls to the resolved
  method symbol with the receiver prepended to the argument list. Preserve only
  unresolved generic/yield-sensitive method calls as high-level MIR.
- Represent heap-owned rvalue reference construction as a structured `ref` from
  a materialized source local instead of a high-level reference value.
- Lower literal/comparison/enum-tag pattern tests, simple `when`, and simple
  `if is` / `while is` forms to MIR CFG. Direct enum payload variable aliases
  are represented as MIR enum-payload places. Binding-free `or`/`and` pattern
  combinators lower to logical MIR conditions. Complex combinators with
  bindings, deeper decision-tree sharing, and cleanup-sensitive pattern plans
  remain for the full pattern pass.
- Lower explicit branch-expression `yield` in `if`, `if is`, and `when` by
  writing the enclosing result local, emitting MIR scope exits, and branching to
  the expression join block.
- Register `finally` expressions on MIR scopes and expand them in LIFO order on
  normal scope exits plus `return`, `break`, `continue`, and `yield` cleanup
  edges.
- Current Swift backend status: MIR has no typed source-body bridge and CodeGen
  no longer reports MIR-codegen blockers for typed AST fallbacks. MIR stats
  should stay focused on real MIR structure and ABI work, not migration bridges.
- Add focused tests comparing MIR dumps for small cases.

### Phase 2: Cleanup And Ownership In MIR

- Move scope tracking and full-expression temporary cleanup into MIR lowering.
- Represent copy/move/drop as MIR operations.
- Have C codegen consume MIR for functions that are fully lowered.
- Do not add a typed-AST fallback in new backend code.

### Phase 3: Escape Analysis In MIR

- Reimplement global escape summaries on MIR call graph and store operations.
- Remove typed-AST pre-analysis from `CodeGen`.
- Keep stored-parameter and return-parameter ref summaries separate so identity
  reference returns do not over-promote mutable refs.

### Phase 4: Pattern, Finally, Lambda, Trait Objects

- Finish full pattern decision-tree lowering, including binding-bearing pattern
  combinators and cleanup-sensitive branch plans.
- Finish full copy/move/drop cleanup elaboration so MIR cleanup edges own both
  `finally` execution and value destruction before backend emission.
- Lower closure construction metadata into MIR.
- Keep trait object operations and vtable globals as structured MIR ABI inputs
  until backend ABI lowering is implemented.

### Phase 5: MIR-Only C Backend

- Remove typed-expression function body generation from C backend.
- Keep type declaration, copy/drop helper, vtable, and runtime ABI helpers in
  backend code.
- Remove migration bridge fields such as `MIRFunction.sourceBody` and any source
  program pointer on `MIRProgram`.

### Phase 6: Module Optimization

- Serialize MIR summaries for module dependencies.
- Cache reachable monomorphized functions and MIR summaries by DefId/body hash.
- Add cross-module dead code pruning and inline/effect summaries.

## Validation Strategy

Every phase should run at least:

```bash
cd compiler
swift build -c debug
cd ..
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8
```

Focused cases to watch while moving logic into MIR:

- `control_flow.koral`
- `return_break_continue.koral`
- `yield_basic.koral`
- `yield_advanced.koral`
- `finally_control_flow.koral`
- `when_switch_lowering.koral`
- `if_pattern_drop.koral`
- `while_pattern_drop.koral`
- `escape_analysis.koral`
- `inter_procedural_escape.koral`
- `lambda_env_drop.koral`
- `trait_object_basic.koral`
- `assignment_return_move_drop_regression.koral`
- `temp_full_expression_lifetime_matrix.koral` when present locally

For MIR-specific verification, add tests in small increments:

- Phase 0 verifier rejects malformed block graphs in Swift unit-style tests if a
  Swift test target is reintroduced.
- Phase 1 dump tests should use stable textual output and avoid DefId-sensitive
  names unless intentionally normalized.
- Integration cases should keep asserting program behavior, not C spelling.

## Development Guidelines

- Keep MIR definitions target-independent. Do not put C names or C snippets in
  MIR data structures.
- Keep `DefId`, `Symbol`, `Type`, and `CompilerContext` as the identity layer;
  do not invent parallel symbol identity.
- Prefer explicit operations over backend conventions. If C generation needs to
  know a cleanup edge, MIR should contain that edge.
- Preserve current diagnostics and behavior while migrating. MIR verifier errors
  are internal compiler errors unless they point to a user-facing semantic issue
  that sema failed to catch.
- Avoid migration bridges. If bootstrap needs one temporarily, keep it clearly
  named, prove it is not used by CodeGen, and delete it before declaring the
  backend MIR-only.
- Add new lowering coverage by feature cluster, not by arbitrary syntax files.
- When Swift and bootstrap diverge during this work, Swift is the source of truth
  until the MIR design is copied to bootstrap.

## Cross-Check Against Current Code

This design matches the current Swift implementation boundaries:

- `Driver.performCompilation` already has the correct insertion point after
  `Monomorphizer.monomorphize()` and before `CodeGen.generate()`.
- `TypeCheckerOutput` already centralizes typed program, generic templates,
  instantiation requests, and `CompilerContext`.
- `MIRLowerer` consumes `MonomorphizedProgram` and copies only backend-relevant
  metadata into `MIRProgram`: static method lookup, trait metadata, receiver
  method dispatch data, and explicit `MIRGlobal.traitVTable` entries.
- `TypedExpressionNode.valueCategory` already distinguishes lvalues from
  rvalues, which MIR lowering should preserve as places versus operands.
- `TypedYieldSummary` centralizes yield-target discovery for typed AST subtrees,
  keeping MIRLowerer focused on lowering decisions instead of owning generic
  typed-tree walks.
- `CodeGen` currently owns C spelling, runtime ABI helpers, C main generation,
  type helper emission, and vtable instance text. It should not regain
  `MonomorphizedProgram`, typed AST bodies, escape analysis, pattern aliases,
  lambda capture buffers, lifetime stacks, or defer/yield stacks.

## Bootstrap Alignment Log

### 2026-05-30 Stage 1 (MIR lowering parity pass)

Completed in bootstrap MIR lowering/builder:

- Aligned function lowering eligibility with Swift `shouldLowerFunction` logic:
  bootstrap now skips lowering functions whose symbol type still contains
  generic parameters.
- Aligned place-read ownership in MIR builder:
  `lower_value` and `lower_operand` now materialize place reads with `Copy`
  ownership, matching Swift MIRLowerer behavior.
- Aligned `return ref-lvalue` lowering:
  bootstrap now emits `MIRValue.Ref(..., HeapOwned)` when returning direct
  reference expressions over lvalues, matching Swift's explicit return path.

Validation notes:

- Rebuilt bootstrap compiler from source using Swift compiler after patch.
- Added operational memory guard requirement for local runs:
  all compile/check/build runs in this stage were executed with a hard kill when
  RSS exceeded 8GB.
- Current blocker remains in bootstrap semantic/type-check phase:
  `./bin/bootstrap/koralc check --package-config std/koral.json --target-module std`
  still crosses 8GB RSS and is force-killed by the guard before MIR lowering.

Next stage focus:

- Keep MIR/codegen alignment direction (no typed-AST fallback reintroduction).
- Debug and remove semantic-phase memory blow-up first, because it blocks all
  full-stdlib bootstrap MIR validation.
- After sema memory stabilization, rerun MIR regression cases and continue
  parity work for reference-allocation promotion and verifier checks.

### 2026-05-30 Stage 2 (sema memory differential pass)

Completed in bootstrap sema alignment work:

- Added iterative lowering guard for statement-level `if` condition rewriting,
  replacing recursive rewrite entry with bounded loop progression.
- Removed a loop-control hazard in recursive type cycle checking
  (`recursive_type_checker`) to avoid unstable traversal behavior.
- Added method callable symbol cache for synthesized non-private callable
  symbols to reduce repeated `DefId` allocation churn on identical signatures.
- Added method lookup caches in `TypeCheckerMethods` for both general method
  lookup and conformance method lookup, including miss caches to avoid repeated
  full-path re-resolution in hot loops.
- Aligned check-only sema mode with lower-retention behavior:
  `check_resolved_graph` now disables checked template body retention
  (`disable_checked_template_body_retention`) before checking loaded nodes.

Validation notes (all runs with hard RSS kill > 8GB):

- Bootstrap compiler rebuild from source remains successful.
- Latest guarded std check still fails memory guard in semantic phase:
  `./bin/bootstrap/koralc check --package-config std/koral.json --target-module std`
  peaks around 8.40 GB RSS and is killed before completion.
- Swift reference still does not reproduce this behavior under the same
  workload scale, so this remains a bootstrap-specific sema growth issue.

Current blocker after Stage 2:

- The dominant high-memory stack remains in bootstrap sema checking paths
  centered around `check_loaded_nodes -> check_decl -> check_statement_body_expr`
  with repeated `if`/method-signature resolution activity.

Next stage focus:

- Add narrow, low-overhead counters around statement/body re-check and method
  signature resolution fan-out to identify the first runaway multiplier.
- Continue Swift/bootstrap pass-order and state-retention parity checks in sema
  before touching MIR/codegen again.

### 2026-05-30 Stage 3 (check-only output retention cut)

Completed in bootstrap sema check path:

- Added check-only typed program suppression:
  `TypeChecker.disable_typed_program_emission()` and wiring from
  `check_resolved_graph` path.
- `check_resolved_graph` now runs with both:
  - checked-template-body retention disabled
  - typed-program emission disabled

Validation notes (with hard RSS kill > 8GB):

- Bootstrap rebuild remains successful after this change.
- std check still exceeds memory guard during semantic/type-check phase,
  with peak remaining around 8.4 GB RSS.

Conclusion from Stage 3:

- Retained output volume in check-only mode is not the primary driver of the
  runaway memory growth; root cause remains inside sema checking traversal/
  resolution behavior before check completion.

**Retrospective (2026-05-31 Stage 6):** The Stage 1-3 memory analysis was chasing
symptoms. The actual root cause was `is_unique_mutable`/`ref_count` intrinsic
signatures using `ref T` instead of `ptr ref T`, which caused COW containers to
always copy. Fixed in Stage 6. Bootstrap hello.koral RSS: 16 GB → 1.9 MB.

### 2026-05-31 Stage 4 (trait hierarchy + memory reduction pass)

Completed in bootstrap sema alignment work:

- Fixed trait hierarchy traversal in `has_explicit_trait_conformance_with_args`
  (`type_checker_visibility.koral`): when checking if a type satisfies a trait,
  the function now also checks if the type conforms to a child trait that extends
  the target. This resolves "Type does not explicitly implement trait" errors for
  `Div`, `Mul`, `Rem` on integer types caused by `Integer extends Div[Self] and
  Rem[Self]` not being traversed.
- Reduced extension method list initial capacity from 64 to 4 in
  `type_checker_templates.koral` (`upsert_extension_template`).

Validation notes:

- Bootstrap rebuild from source remains successful.
- Div/Mul/Rem trait conformance errors fully resolved.
- Remaining errors (json, time, io, rand, list) are pre-existing and unrelated.
- Memory measurements at this stage were misleading due to the COW bug
  (root cause found in Stage 6).

### 2026-05-31 Stage 6 (memory root cause fix)

Root cause: `is_unique_mutable` / `ref_count` intrinsic signatures used `ref T`,
causing argument passing to retain the ref. This inflated strong_count, making
`is_unique_mutable` always return false. Every Dict/List/Deque/Set/String COW
operation triggered a full copy.

Fix: changed signatures to `ptr ref T`, updated all call sites to use `.ptr`.
Bootstrap hello.koral RSS: 16 GB → 1.9 MB. Dict 100k inserts: 3.6 GB → 13 MB.

Additional fixes:
- Trait hierarchy traversal for conformance checking (Div/Mul/Rem via Integer)
- MIR basic block ordering (lower_while/lower_block predecessor save)
- Variable naming uniqueness (DefId suffix for locals)
- TypeVar/TraitObject drop completeness
- Deque ensure_capacity uniqueness check ordering

Remaining work:
- Bootstrap `--emit-c` generates `void` for generic types (check path works)
- MIR `read[copy]` for mut ref field access through mut ref parameter
- Unifier dictionary reuse
- Runtime alloc tracking code removed from koral_runtime.c (was debug-only)

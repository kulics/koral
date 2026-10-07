# Unified Compiler Test Suite

`tests/` is the only supported test entry for this repository.

- `tests/compiler-cases/`: shared Koral integration cases
- `tests/compiler-runner/`: shared Koral test runner package at `tests/compiler-runner/koral.json`
- `tests/compiler-cases_output/`: runner reports and temporary outputs

## Prepare compiler binaries

`compiler/` is the primary implementation; `compiler-reference/` is the **frozen** Swift compiler
(reference oracle + build seed + backup). The suite is gated on `compiler/` first. Note the runner's
CLI predates these directory names: `--compiler bootstrap` means the self-hosting compiler built
from `compiler/`, and `--compiler swift` means the frozen seed.

Build the frozen seed (release — debug is ~6x slower at generating C, see
`docs/implementation/developer-guide.md`):

```bash
cd compiler-reference
swift build -c release
cd ..
```

Build the compiler and the shared test runner **with the seed**. This is a trust boundary: if the
implementation under test built the harness, a codegen defect in it would corrupt the oracle.

```bash
compiler-reference/.build/release/koralc build --package-config compiler/koral.json --target-module koralc -o bin/compiler
compiler-reference/.build/release/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
```

## Parallel execution

The shared runner supports parallel execution with `-j <N>` or `-j=<N>`; the worker count is what
`-j` asks for, clamped to the number of cases.

Run against the primary implementation (the gate — this is the default, so `--compiler bootstrap`
may be omitted):

```bash
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc -j=8
```

Seed self-check — the frozen reference compiler:

```bash
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler-reference/.build/release/koralc -j=8
```

Run against a custom compiler binary:

```bash
./bin/compiler-test-runner/compiler_runner --compiler custom --compiler-bin <path-to-compiler> -j=8
```

Useful flags:

- `--cases <dir>`: override the case root, default `tests/compiler-cases`
- `--compiler <kind>`: `bootstrap` (default) | `swift` | `custom` | `differential`
- `--filter <substring>`: run only matching cases
- `--timeout <sec>`: per-case timeout, default `120`
- `--memory-limit <MB>`: post-exit peak RSS threshold, default `1024`; cases whose recorded peak RSS exceeds the limit are marked `memory_exceeded`
- `--report-file <path>`: override the stable summary log path
- `--compare-diagnostics`: with `--compiler differential`, also require the two compilers to say exactly the same thing — already the default, kept so existing invocations keep working

`--filter` uses plain substring matching only. It does not accept regular expressions, so focused semantic reruns should pass exact case-name substrings one-by-one.

## Cross-compiler oracle (`--compiler differential`)

Each of the modes above checks one compiler against the `// EXPECT` comments in
the case file — a hand-written oracle. This mode checks **the two compilers
against each other**. The seed is **frozen, not on death row**: it is the
standing reference oracle, and this is the cross-check that keeps the two honest.
It stays mandatory in CI.

```bash
./bin/compiler-test-runner/compiler_runner \
  --compiler differential \
  --swift-koralc compiler-reference/.build/release/koralc \
  --bootstrap-koralc bin/compiler/koralc \
  --timeout 60 -j 8
```

Every case is compiled and run under both compilers. They must agree, in order
of how damning the disagreement is:

| | must agree on | failure type |
|---|---|---|
| 1 | both accept the program, or both reject it | `diverge_accept_reject` |
| 2 | when accepted: program stdout, line for line, and exit code | `diverge_runtime` |
| 3 | when rejected: the diagnostic text, verbatim | `diverge_diagnostic` |

Layer 2 is **exact**, not the `// EXPECT` subsequence match: two compilers can
both satisfy "output contains `show` then `base`" and still print entirely
different things in between. Failures name the first line that differs and what
each side said, rather than just reporting that the outputs differ.

Layer 3 compares diagnostic text and is **on by default**. It used to be opt-in
while a backlog of divergences was open (210 of 566 cases as of 2026-10-03 —
span columns, the `1 error generated.` trailer, stage prefixes, and some genuine
wording differences). That backlog is closed: as of 2026-10-06 the two compilers
agree on diagnostic text for the whole 596-case corpus (596/596). A one-sided
wording drift now fails the gate instead of hiding behind a flag.

The generated artifacts are deliberately **not** compared. The two compilers
stamp DefIds into C symbol names under different numbering rules, so a textual
diff of the generated C would be pure noise; behaviour is the thing to hold them
to.

## Focused regression buckets

The shared suite remains flat under `tests/compiler-cases/`, but a few high-value semantic buckets are worth rerunning together when touching parser visibility, raw pointers, weak references, or `self` behavior.

### Access, visibility, and import discipline

Use this bucket when changing declaration parsing, package visibility, import rules, or generic template lookup.

- `access_modifier_order_error`
- `protected_method_visibility_error_test`
- `protected_public_method_same_package_test`
- `protected_public_method_cross_package_error_test`
- `module_private_method_access_error_test`
- `package_private_method_same_package_test`
- `package_private_method_cross_package_error_test`
- `protected_public_type_same_package_test`
- `public_signature_protected_public_type_error_test`
- `using_batch_with_named_import_error`
- `using_empty_import_list_error`
- `generic_template_requires_import_error_test`
- `generic_template_import_test`

### Identifier case discipline

Use this bucket when changing identifier parsing or naming-rule enforcement for types, enum constructors, variables, functions, fields, parameters, or module paths.

- `identifier_case_variable_error`
- `identifier_case_function_error`
- `identifier_case_field_error`
- `identifier_case_parameter_error`
- `identifier_case_type_error`
- `identifier_case_enum_case_decl_error`
- `identifier_case_enum_ctor_use_error`
- `identifier_case_pattern_enum_ctor_error`
- `identifier_case_module_error`

### ASI / newline continuation

Use this bucket when changing statement termination or line-join tokens.

- `newline_semicolon_continuation_ok`
- `newline_semicolon_grouped_expression_ok`
- `newline_semicolon_blankline_blocks_dot`
- `newline_semicolon_comment_blocks_infix`
- `newline_semicolon_comparison_blocks_error`

### Raw pointer and weak reference surface (`*unsafe T`, `?T`)

Use this bucket when changing raw-pointer or weak-reference syntax/semantics. Managed references (`*T`, `*mutable T`, `?*T`) and `box()` are removed; only `*unsafe T` / `*unsafe mutable T` and `?T` remain.

- `raw_sigils_basic_test`
- `raw_address_readonly_pointer_deref_error`
- `raw_address_of_literal_error`
- `raw_address_of_temporary_error`
- `raw_method_call_error_test`
- `pointer_test`
- `cast_pointer_int_uint`
- `deref_assignment_requires_reference_type`
- `unsafe_deref_or_return_non_option_result_error`
- `weak_sigils_basic_test`
- `upgrade_requires_weak_ref_error`

### Receiver and `self` semantics

Use this bucket when changing receiver syntax, `self` parameter passing, or auto-deref behaviour on generic parameters. Receiver syntax is `self` only — there is no `*self` / `*mutable self`, and no receiver auto-ref/auto-deref.

- `receiver_self_syntax_error`
- `receiver_amp_self_test`
- `generic_given_pointer_self_signature_regression`
- `generic_any_not_auto_deref_error`
- `mut_param_trait_signature_regression`
- `value_param_copy`

New work should add coverage directly under `tests/compiler-cases/` using the current surface: `self` receivers, `type` / `type mutable` declarations, `?T` weak references, and `*unsafe T` / `*unsafe mutable T` raw pointers.

## Rerun a bucket

Because `--filter` is substring-only, the most reliable workflow is to loop over exact case names.

```bash
cases=(
	raw_sigils_basic_test
	raw_address_readonly_pointer_deref_error
	raw_address_of_literal_error
	raw_address_of_temporary_error
	raw_method_call_error_test
	pointer_test
	weak_sigils_basic_test
	upgrade_requires_weak_ref_error
	receiver_self_syntax_error
	receiver_amp_self_test
	generic_any_not_auto_deref_error
)

for case_name in "${cases[@]}"; do
	./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/compiler/koralc --filter "$case_name"
done
```

Swap the compiler arguments to rerun the same bucket as a seed self-check:

```bash
./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler-reference/.build/release/koralc --filter "$case_name"
```

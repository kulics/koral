# Unified Compiler Test Suite

`tests/` is the only supported test entry for this repository.

- `tests/compiler-cases/`: shared Koral integration cases
- `tests/compiler-runner/`: shared Koral test runner package at `tests/compiler-runner/koral.json`
- `tests/compiler-cases_output/`: runner reports and temporary outputs

## Prepare compiler binaries

Build the Swift `koralc` first:

```bash
cd compiler
swift build -c debug
cd ..
```

Build the shared test runner:

```bash
compiler/.build/debug/koralc build --package-config tests/compiler-runner/koral.json --target-module compiler_runner -o bin/compiler-test-runner
```

If you want to test the bootstrap compiler, build its `koralc` entry too:

```bash
compiler/.build/debug/koralc build --package-config bootstrap/koral.json --target-module koralc -o bin/bootstrap
```

## Parallel execution

The shared runner supports parallel execution with `-j <N>` or `-j=<N>`.
For bootstrap runs, effective parallelism is currently capped at `6` workers for stability; larger requested values are reduced internally.

Run against the Swift compiler:

```bash
./bin/compiler-test-runner/compiler_runner.exe --compiler swift --swift-koralc compiler/.build/debug/koralc.exe -j=8
```

Run against the bootstrap compiler:

```bash
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe -j=8
```

Run against a custom compiler binary:

```bash
./bin/compiler-test-runner/compiler_runner.exe --compiler custom --compiler-bin <path-to-compiler> -j=8
```

Useful flags:

- `--cases <dir>`: override the case root, default `tests/compiler-cases`
- `--filter <substring>`: run only matching cases
- `--timeout <sec>`: per-case timeout, default `120`
- `--report-file <path>`: override the stable summary log path

`--filter` uses plain substring matching only. It does not accept regular expressions, so focused semantic reruns should pass exact case-name substrings one-by-one.

## Focused regression buckets

The shared suite remains flat under `tests/compiler-cases/`, but the recent compiler fixes added a few high-value semantic buckets that are worth rerunning together when touching parser visibility, escape analysis, `ref`, or `self` behavior.

### Access, visibility, and import discipline

Use this bucket when changing declaration parsing, package visibility, import rules, or generic template lookup.

- `access_modifier_order_error`
- `protected_method_visibility_error_test`
- `protected_public_method_same_package_test`
- `protected_public_method_cross_package_error_test`
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

### New reference surface (`*T`, `?*T`, `*unsafe T`)

Use this bucket when changing managed reference, weak reference, or raw-pointer syntax/semantics.

- `raw_deref_mutable_ref_readonly_pointer_error`
- `raw_address_readonly_pointer_deref_error`
- `implicit_mutable_ref_from_readonly_pointer_deref_error`
- `implicit_mutable_ref_from_immutable_value_error`
- `weakref_basic`
- `weakref_lifecycle`
- `weakref_struct`
- `mut_weakref_basic`
- `trait_object_weakref`
- `trait_object_mut_weakref_roundtrip`

### Escape analysis and managed reference promotion

Use this bucket when changing escape promotion, conditional branch merge logic, inter-procedural escape, or container store paths.

- `escape_alias_container_store_regression`
- `inter_procedural_escape`
- `inter_procedural_escape_recursive_ref_regression`
- `conditional_managed_ref_lambda_return`
- `escape_analysis`
- `escape_analysis_coverage`
- `explicit_ref_promotion`
- `box_escape_analysis`
- `builtin_subscript_ref_escape`
- `no_implicit_ref_promotion_error`
- `mut_ref_receiver_copy_field_escape_regression`
- `ref_escape_pattern_alias`

### Receiver syntax migration (`*self`, `*mutable self`)

Use this bucket when changing receiver auto-ref/auto-deref, managed receiver return paths, or U2 receiver syntax migration behavior.

- `raw_pointer_readonly_mut_receiver_error`
- `when_ref_in_private_fn`
- `mut_ref_method_dispatch_widening`
- `self_ref_receiver_temp_cleanup_unique_mutable`
- `self_mut_ref_rvalue_receiver_error`
- `value_semantics_self_ref_on_immutable_base_error`

Legacy receiver-surface cases have been removed from the active tree. New work should add coverage directly under `tests/compiler-cases/` using the U2 surface (`*self`, `*mutable self`, `&`, `&mutable`, `&unsafe`, `&unsafe mutable`, `*`).

## Rerun a bucket

Because `--filter` is substring-only, the most reliable workflow is to loop over exact case names.

```bash
cases=(
	escape_alias_container_store_regression
	inter_procedural_escape
	inter_procedural_escape_recursive_ref_regression
	conditional_managed_ref_lambda_return
	weakref_basic
	weakref_lifecycle
	weakref_struct
	mut_weakref_basic
	trait_object_weakref
	trait_object_mut_weakref_roundtrip
)

for case_name in "${cases[@]}"; do
	./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc --filter "$case_name"
done
```

Swap the compiler arguments to rerun the same bucket on bootstrap:

```bash
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc --filter "$case_name"
```

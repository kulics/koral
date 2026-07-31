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

### Explicit managed receiver semantics

Use this bucket when changing receiver adaptation, auto-ref rules, or `self ref Self` / `self ref mut Self` behavior.

- `managed_self_ref_mut_self_smoke`
- `no_auto_ref_managed_mut_receiver_error`
- `managed_self_ref_self_trait_generic_test`
- `managed_self_ref_mut_self_trait_generic_test`
- `no_auto_ref_managed_mut_receiver_generic_error`
- `generic_owner_managed_self_ref_smoke`
- `generic_owner_managed_self_ref_mut_smoke`
- `generic_owner_no_auto_ref_managed_mut_receiver_error`

### Escape analysis with lambda capture and storage

Use this bucket when changing borrow-first `.ref`, escape promotion, conditional branch merge logic, or closure capture/storage rules.

- `escape_branch_managed_ref_return`
- `conditional_borrowed_ref_lambda_capture_error`
- `conditional_managed_ref_lambda_return`
- `conditional_managed_refmut_lambda_list_store`

### Trait object safety for explicit managed receivers

Use this bucket when changing trait object formation, object-safety checks, or reference/weak-reference wrappers around trait objects.

- `managed_receiver_trait_object_safety_error`
- `managed_mut_receiver_trait_object_safety_error`

## Rerun a bucket

Because `--filter` is substring-only, the most reliable workflow is to loop over exact case names.

```bash
cases=(
	conditional_borrowed_ref_lambda_capture_error
	conditional_managed_ref_lambda_return
	conditional_managed_refmut_lambda_list_store
	managed_self_ref_self_trait_generic_test
	managed_self_ref_mut_self_trait_generic_test
	no_auto_ref_managed_mut_receiver_generic_error
	generic_owner_managed_self_ref_smoke
	generic_owner_managed_self_ref_mut_smoke
	generic_owner_no_auto_ref_managed_mut_receiver_error
	managed_receiver_trait_object_safety_error
	managed_mut_receiver_trait_object_safety_error
)

for case_name in "${cases[@]}"; do
	./bin/compiler-test-runner/compiler_runner --compiler swift --swift-koralc compiler/.build/debug/koralc --filter "$case_name"
done
```

Swap the compiler arguments to rerun the same bucket on bootstrap:

```bash
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc --filter "$case_name"
```

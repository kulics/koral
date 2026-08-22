# Bootstrap Status 2026-08-21

## Summary

- Current validated bootstrap full-suite baseline: `504/504` passed.
- Full-suite command in the current macOS workspace: `./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ./bin/bootstrap/koralc -j=8 --timeout 120 --report-file tests/compiler-cases_output/_reports/bootstrap-final-rerun-after-timeout-fix.log`
- Latest validated full-suite summary: `passed=504 failed=0 timed_out=0 infra_failed=0 duration_ms=437507`.
- The earlier `488/504` snapshot in this document has now been superseded by a fully green rerun in the current workspace.

## Continuation Revalidation

This continuation rechecked the previously documented unstable/failing area before the full rerun.

- Individually re-ran and passed: `random_xoshiro_test`, `result_void_test`, `regex_basic_test`, `datetime_basic`, `slice_spec_test`
- Individually re-ran and passed: `is_unique_mutable_matrix`, `deptr_assignment_unique_mutable_semantics`, `escape_analysis_coverage`, `inter_procedural_escape`, `inter_procedural_escape_recursive_ref_regression`, `escape_summary_return_only_identity_ref`
- Full bootstrap suite rerun then passed cleanly: `504/504`
- A later rerun briefly regressed to `496/504` due to false parallel timeouts in the shared runner, not compiler-case failures.
- `tests/compiler-runner/executor.koral` was then fixed to use per-command `MonoTime.now()` plus current-thread `proc.try_wait()` polling instead of a background watchdog tied to case-level start time.
- Rebuilt runner validation passed on the exact former timeout slice (`sync_channel_test`, `if_while_is_or_chain_regression`, `diagnostic_type_mismatch_line_1`, `or_return_basic`, `ref_deref_counter_loop`, `cast_numeric`, `string_methods`, `private_field_constructor_same_file`) at `8/8` with `-j=8`.
- After that runner fix, the full bootstrap suite returned to `504/504` with `timed_out=0`.

## Key Validated Regressions

These were re-run against `./bin/bootstrap/koralc` and passed in the current snapshot:

- `is_unique_mutable_matrix`
- `deptr_assignment_unique_mutable_semantics`
- `escape_analysis_coverage`
- `inter_procedural_escape`
- `inter_procedural_escape_recursive_ref_regression`
- `escape_summary_return_only_identity_ref`

## Main Effective Changes In This Snapshot

### Bootstrap MIR / escape analysis

- `bootstrap/koralc/mir/mir_lowerer.koral`
  - Escape summaries now distinguish `returning_parameter_indices` from `direct_reference_escaping_parameter_indices`.
  - Local alias propagation was added so both returning flow and direct escaping can trace parameter sources through locals.
  - Reference promotion now keeps stack-borrow refs for non-escaping local/temp bindings and forces heap-owned promotion only at true escape use-sites.
  - Call-argument promotion uses direct escaping summary data instead of conflating direct escaping with return-only propagation.

- `bootstrap/koralc/mir/mir_function_builder.koral`
  - Current snapshot includes the local branch-ref handling and the guarded `lower_value` path for generic-parameter cases that are part of the working tree state being preserved.

### Other tracked code currently preserved in the snapshot

The working tree also contains tracked effective changes outside the core bootstrap MIR files, and this snapshot preserves them as-is:

- `bootstrap/koralc/driver/run.koral`
- `bootstrap/koralc/mono/mono.koral`
- `bootstrap/koralc/mono/mono_type_resolution.koral`
- `compiler/Sources/KoralCompiler/Driver/Driver.swift`
- `std/koral_runtime.c`
- `std/proc/utils.koral`
- `tests/compiler-runner/cli.koral`
- `tests/compiler-runner/executor.koral`
- `tests/compiler-runner/model.koral`
- `tests/compiler-runner/reporter.koral`
- `tests/compiler-runner/scheduler.koral`

## Remaining Known State

- No currently reproduced failures remain in the active `504`-case bootstrap compiler suite.
- The previously listed failures (`random_xoshiro_test.koral`, `result_void_test.koral`, `regex_basic_test.koral`, `datetime_basic.koral`) were re-run individually in this continuation and now pass.
- The earlier unstable generated-C probe `slice_spec_test.koral` was also re-run and now passes in the current workspace.
- The transient `496/504` run was traced to runner timeout accounting rather than compiler miscompilation; the current rebuilt runner and compiler pair revalidate at `504/504`.
- The historical notes below about effective MIR/escape-analysis changes remain relevant as context for why this branch recovered.

## Working Tree Scope Captured By This Snapshot

`git diff --stat` at snapshot time:

- 13 tracked files changed
- 969 insertions
- 232 deletions

## Intentionally Excluded From Commit

The following local artifacts should stay out of version control and are intentionally excluded from the snapshot commit:

- `.copilot_tmp/`
- `test_output/`
- `test_run_output*.txt`
- `bootstrap/koralc/mir/mir_lowerer.koral.bak`
- `bench/` (current untracked local directory)

## Recommended Restart Point

If work resumes from this workspace state, start with the currently valid runner commands below:

```bash
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ./bin/bootstrap/koralc --filter "is_unique_mutable_matrix" -j=1 --timeout 120 --verbose
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ./bin/bootstrap/koralc --filter "deptr_assignment_unique_mutable_semantics" -j=1 --timeout 120 --verbose
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ./bin/bootstrap/koralc --filter "escape_analysis_coverage" -j=1 --timeout 120 --verbose
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ./bin/bootstrap/koralc --filter "inter_procedural_escape" -j=1 --timeout 120 --verbose
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ./bin/bootstrap/koralc --filter "escape_summary_return_only_identity_ref" -j=1 --timeout 120 --verbose
```

Then re-run the full suite:

```bash
./bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ./bin/bootstrap/koralc -j=8 --timeout 120 --report-file tests/compiler-cases_output/_reports/bootstrap-final-rerun-after-timeout-fix.log
```

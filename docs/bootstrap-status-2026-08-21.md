# Bootstrap Status 2026-08-21

## Summary

- Current validated bootstrap full-suite baseline: `488/504` passed.
- Full-suite command: `./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe -j=8 --timeout 120 --memory-limit 2048`
- Latest validated full-suite summary: `passed=488 failed=16 timed_out=0 memory_exceeded=0 infra_failed=0 duration_ms=1785090`.
- The largest functional win in this snapshot is that the earlier `memory_exceeded` class is gone in the validated full run.

## Key Validated Regressions

These were re-run against the freshly rebuilt `bin/bootstrap/koralc.exe` and passed in the current snapshot:

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

- There are still `16` failing cases in the last validated full bootstrap suite.
- The saved full-run log excerpt explicitly captured these remaining failures:
  - `random_xoshiro_test.koral`
  - `result_void_test.koral`
  - `regex_basic_test.koral`
  - `datetime_basic.koral`
- During intermediate investigation on this branch, there was also a separate unstable failure cluster involving corrupted generated C in some cases such as `slice_spec_test`, `stack_test`, and `checked_shift_invalid`. Those experiments were not kept as part of this stable snapshot and should be rechecked from this commit before further fixes.

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

If work resumes from this commit, start by re-running the validated key regressions first:

```bash
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe --filter "is_unique_mutable_matrix" -j=1 --timeout 120 --memory-limit 4096 --verbose
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe --filter "deptr_assignment_unique_mutable_semantics" -j=1 --timeout 120 --memory-limit 4096 --verbose
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe --filter "escape_analysis_coverage" -j=1 --timeout 120 --memory-limit 4096 --verbose
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe --filter "inter_procedural_escape" -j=1 --timeout 120 --memory-limit 4096 --verbose
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe --filter "escape_summary_return_only_identity_ref" -j=1 --timeout 120 --memory-limit 4096 --verbose
```

Then re-run the full suite:

```bash
./bin/compiler-test-runner/compiler_runner.exe --compiler bootstrap --bootstrap-koralc bin/bootstrap/koralc.exe -j=8 --timeout 120 --memory-limit 2048
```
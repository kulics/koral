# Bootstrap Parser Smoke Tests

This directory contains reusable Koral test inputs for the bootstrap phase-1 frontend.

## Files

- `main.koral`: Koral test runner entrypoint. Builds `bootstrap/koralc` and runs all AST cases.
- `cases/*.koral`: focused test cases grouped by feature area.
- `out/*.ast.txt`: generated AST outputs.

## Reverse Cases (Expected Errors)

Case files can include one or more expectations using comments:

```koral
// EXPECT-ERROR: some message fragment
```

When a case contains at least one `EXPECT-ERROR:` marker:

- The runner expects the compiler command to fail (non-zero exit).
- The runner scans combined stdout/stderr output.
- Each marker fragment must appear in output, otherwise the case fails.

## Run

From repository root:

```bash
# Run all cases
./bin/koralc run bootstrap/test/main.koral -o /tmp/bootstrap_test_runner

# Run a single case by name
./bin/koralc run bootstrap/test/main.koral -o /tmp/bootstrap_test_runner -- --case 00_declarations
./bin/koralc run bootstrap/test/main.koral -o /tmp/bootstrap_test_runner -- -c 08_match_and_literals
```

The runner compiles the bootstrap compiler, then runs the selected cases and writes AST outputs into `bootstrap/test/out/`.

## Case Names

| Name | File |
|------|------|
| `00_declarations` | `cases/00_declarations.koral` |
| `01_expressions` | `cases/01_expressions.koral` |
| `02_control_flow` | `cases/02_control_flow.koral` |
| `03_strings_and_calls` | `cases/03_strings_and_calls.koral` |
| `04_basic_test` | `cases/04_basic_test.koral` |
| `05_types_recursive` | `cases/05_types_recursive.koral` |
| `06_expected_errors` | `cases/06_expected_errors.koral` |
| `07_using_rules_error` | `cases/07_using_rules_error.koral` |
| `08_match_and_literals` | `cases/08_match_and_literals.koral` |

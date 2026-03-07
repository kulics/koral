# Bootstrap Parser Smoke Tests

This directory contains reusable Koral test inputs for the bootstrap phase-1 frontend.

## Files

- `main.koral`: Koral test runner entrypoint. Builds `bootstrap/koralc` and runs all AST cases.
- `cases/04_basic_test.koral`: one combined smoke file covering declarations, expressions, control-flow, and block statements.
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

This supports parser/diagnostics negative testing for future reverse cases.

## Run

From repository root:

```bash
./bin/koralc run bootstrap/test/main.koral -o /tmp/bootstrap_test_runner
```

The runner compiles the bootstrap compiler and writes AST outputs into `bootstrap/test/out/`.

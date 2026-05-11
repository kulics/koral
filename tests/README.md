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

# The Koral Programming Language

Koral is an open-source programming language focused on performance, readability, and practical cross-platform development.

This repository contains the compiler, standard library, formatter, language documentation, and sample projects.

> Status: Koral is in an experimental stage and is not yet production-ready.

## Highlights

- Modern, easy-to-scan syntax.
- Automatic memory management based on reference counting and ownership analysis.
- Generics and trait-based abstraction.
- Multi-paradigm support (imperative + functional style).
- C backend for broad platform compatibility.

## Repository Layout

- `compiler/` — Swift compiler project (`koralc`, `KoralCompiler`)
- `std/` — standard library modules and runtime C files
- `docs/` — language and developer documentation
- `fmt/` — formatter implementation and tests
- `samples/` — example projects

## Prerequisites

- Swift toolchain (for building `koralc`)
- A C compiler in `PATH` (`clang` recommended)

On Windows, ensure `clang.exe` is available from terminal:

```bash
clang --version
```

## Build from Source

```bash
cd compiler
swift build -c debug
```

## Run the Compiler

```bash
# Build (default command)
swift run koralc path/to/file.koral

# Build and run
swift run koralc run path/to/file.koral

# Emit C only
swift run koralc emit-c path/to/file.koral -o out
```

## Common Options

- `-o, --output <dir>`: output directory (default: input file directory)
- `--no-std`: compile without loading `std/std.koral`
- `--escape-analysis-report`: print escape analysis diagnostics

## Test

Run in `compiler/`:

```bash
swift build -c debug
swift test
```

## Documentation

- [Language Guide (English)](docs/document.md)
- [语言文档（中文）](docs/document-zh.md)
- [Compiler Developer Guide](docs/developer-guide.md)

## Standard Library Resolution (`KORAL_HOME`)

If `koralc` cannot find `std/std.koral` due to your working directory, set `KORAL_HOME` to the repository root.

```bash
# macOS / Linux
export KORAL_HOME=/path/to/koral

# Windows PowerShell
$env:KORAL_HOME = "C:\path\to\koral"
```

## Contributing

Issues and pull requests are welcome. If you change parser/type-checker/codegen behavior, please add or update integration test cases under `compiler/Tests/Cases/`.

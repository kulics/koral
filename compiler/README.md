# `compiler/` — the primary compiler implementation

This is the compiler written in Koral. **It is the implementation under development**: every
functional change to the language lands here first.

It cannot build itself from nothing. The frozen Swift compiler in `../compiler-reference/` is the
**seed** — it is what builds `bin/compiler/koralc` from these sources. That is the only reason the
seed is still on the critical path.

## Build it

```bash
# the seed (once, or after it changes)
cd ../compiler-reference && swift build -c release && cd ..

# this implementation, built BY the seed
../compiler-reference/.build/release/koralc build \
  --package-config koral.json --target-module koralc -o ../bin/compiler
```

**Trust boundary:** the test harness is also built by the seed, never by this implementation. If
the compiler under test built the thing meant to test it, a codegen defect here would corrupt the
oracle. A self-built next-stage binary is likewise never the default test harness — that path is
reserved for explicit self-hosting validation.

> The runner's `--compiler bootstrap` kind and `--bootstrap-koralc` flag mean **this**
> implementation (the self-hosting one, `bin/compiler/koralc`). The flag names predate the
> directory names and are stable API — see *Compiler roles* in the developer guide.

## Gate it

The primary suite gate is this implementation:

```bash
../bin/compiler-test-runner/compiler_runner --compiler bootstrap --bootstrap-koralc ../bin/compiler/koralc -j=8
```

Self-hosting validation (two rounds, fixed point, dangling-call scan) and the cross-compiler
differential gate live in [`../docs/implementation/developer-guide.md`](../docs/implementation/developer-guide.md) and
[`../tests/README.md`](../tests/README.md).

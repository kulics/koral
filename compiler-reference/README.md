# `compiler-reference/` — FROZEN

> **This directory is frozen. It is not a development target.**
>
> Language work goes to [`../compiler/`](../compiler/), which is the primary implementation.
> Changes here are exceptional seed/oracle repairs and should be reviewed as such.

This is the compiler written in Swift. It is kept for three reasons at once:

1. **Reference oracle** — the differential gate compiles every test case under both compilers and
   requires them to agree on accept/reject, program output, exit code, and diagnostic text. That
   cross-check catches one-sided drift even when both suites are green.
2. **Build seed** — it builds `bin/compiler/koralc` (and the shared test runner) from source.
   A fresh clone has no compiler; this is how you get the first one.
3. **Backup** — if the self-hosting chain breaks, this is the compiler that still works.

## When you may touch it

Only to keep the oracle honest — for example when `compiler/` deliberately changes language
behaviour and this reference must follow so the two can keep being compared. Ordinary language
work does **not** come here.

Deleting it would trade the strongest cross-check in the repo for the weakest: a self-host fixed
point proves a compiler is *stable under its own output*, not that it is *right*.

## Build it

```bash
swift build -c release --package-path compiler-reference   # from the repo root
# -> compiler-reference/.build/release/koralc
```

Use **release** for anything repeated — the debug build is ~6x slower at generating C.

## Trust boundary

The oracle and the test harness are built by **this** compiler, never by the implementation under
test. If the compiler under test built the harness, a codegen defect in it would corrupt the very
thing meant to catch it.

## See also

- [`../docs/developer-guide.md`](../docs/developer-guide.md) — *Compiler roles* and the trust boundary
- [`../tests/README.md`](../tests/README.md) — the differential oracle contract
- [`../docs/bootstrap-productization-plan.md`](../docs/bootstrap-productization-plan.md) — the
  dated appendix recording this role decision

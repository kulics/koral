# A/B instruments (not comparison cases)

Workloads here are **measurement instruments for same-session A/B of a
compiler change**, not rows of the cross-language table. They sit outside
`benchmarks/cases/` so `benchmarks/run.sh` does not pick them up: their
absolute wall time is dominated by hardware/scheduler physics (variance is
far above the comparison cases) and their cross-language ratio carries no
language signal. What they report reliably is the **delta between two Koral
builds measured back-to-back in one session**.

## The atomic / lock pair

`atomic_fetch_add/` + `lock_counter/` are one A/B cut in two rows: the same
8-thread x 1M shared-counter workload, once lock-free
(`AtomicInt.fetch_add`) and once behind a std `Mutex`. The claim the pair
instruments:

> a contended `fetch_add` must cost one atomic RMW per op -- no refcount
> traffic.

The lock row is the control (a delta that moves both rows is timing/thread
plumbing, not the atomic path) and the yardstick the atomic row does NOT
race: at 8 threads a single-line contended seq_cst RMW trails an adaptive
mutex on a tiny critical section even in bare C (measured 2.05x on this
machine). Read the pair as a delta instrument, never as "atomic must beat
lock".

**How to A/B a compiler change:**

    KORALC=/path/to/koralc-before benchmarks/ab/run.sh > /tmp/before.txt
    KORALC=/path/to/koralc-after  benchmarks/ab/run.sh > /tmp/after.txt

Both runs must happen back-to-back on an idle machine (same session), and
the two Koral rows are the only numbers to compare. Go/Swift/Rust builds are
provided as same-shape floor references, not as a scoreboard.

**The deterministic gates live in tests, not here.** What this pair measures
as wall time is pinned machine-independently by:

- `w12_atomic_retains=0 / w12_atomic_releases=0` -- the runtime RC window in
  `tests/runtime-cases/rc_counter_pin.koral` (every `fetch_add` call passes
  the receiver +0);
- the **atomic shape pin** in `scripts/verify.sh` -- the generated C of a
  `fetch_add` probe contains exactly one `__koral_atomic_fetch_add_iptr`
  call and zero retain/release/copy/drop traffic.

If a change to the borrowed-receiver analysis (`codegen_borrowed_self.koral`)
regresses the convention, those two gates fail before anyone reaches for a
stopwatch; this A/B tool exists to quantify the wall-time effect of changes
that pass the gates.

## History

2026-11-16, rule 5a atomic-argument carve-out (Apple M4 Pro, same-tree A/B,
interleaved, best of 5): `atomic_fetch_add` 716.8 ms -> 165.8 ms (**4.32x
faster**), `lock_counter` 96.9 -> 98.5 ms (flat, control). The after row
sits within 4.9% of bare C11 `atomic_fetch_add_explicit(seq_cst)` on the
same shape (158.1 ms) -- the pre-fix row paid a retain/release pair on the
shared handle per op (three contended atomics per increment). Full analysis
in `benchmarks/README.md` ("The atomic / lock pair A/B").

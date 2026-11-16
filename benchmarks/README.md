# Benchmarks

Cross-language runtime benchmarks for Koral's key types against Go, Swift and
Rust. Each case is the SAME workload (same algorithm, same input sizes, same
deterministic LCG) implemented idiomatically in all four languages, printing

    RESULT <checksum> <elapsed-ns>

The checksum guards that every language performed the same work — the runner
flags a row when they disagree.

The goal these numbers track: **Koral should not lag the mainstream languages
(Go, Swift) on their own workloads.** Rust's results are kept as a reference
ceiling — a hand-tuned, SIMD-first standard library is the bound, not the bar.

## Cases

| case | what it measures |
|---|---|
| list_sum | container growth + indexed iteration (5M ints) |
| struct_iter | list of small records, field access (5M pairs) |
| sort_ints | comparison sort, int keys (1M) |
| sort_strings | comparison sort, string keys (200k) |
| dict_lookup | hash map insert + lookup, String keys (500k) |
| set_membership | hash set insert + contains, Int keys (500k + 1M probes) |
| string_build | StringBuilder append throughput (300k small appends) |
| string_find | build 8MB text + pattern scan |
| regex_scan | capturing regex scan over a 5MB token stream (compile once, walk every match) |
| loop_pipeline | integer loop with branch and multiply (3.5M) |
| fib_recursive | call overhead baseline (fib 27) |

Concurrency A/B instruments live in `ab/`, not in this table -- they are
same-session delta tools for compiler changes, not cross-language rows (see
`ab/README.md`).

## Running

    benchmarks/run.sh            # build all four languages, best-of-3 table
    RUNS=5 benchmarks/run.sh     # more repetitions
    KORALC=path/to/koralc benchmarks/run.sh

Requirements: `go`, `swiftc`, `rustc`, and `bin/compiler/koralc` (built by
`scripts/verify.sh` step 2, or any koralc via KORALC=).

## The atomic / lock pair (in `ab/`, not a table row)

`ab/atomic_fetch_add` and `ab/lock_counter` are one A/B cut in two rows: the
same 8-thread x 1M shared-counter workload, once lock-free
(`AtomicInt.fetch_add`, `atomic.AddInt64`, `Atomic<Int64>.wrappingAdd`,
`AtomicI64::fetch_add`) and once behind a mutex. They are **instruments for
same-session A/B of a compiler change, not cross-language comparison rows**:
at 8 threads every language sits at the hardware floor, so the ratio column
carries no language signal (a single-line contended seq_cst RMW trails an
adaptive mutex on a tiny critical section even in bare C -- the atomic row
does not race the lock row). The claim the pair instruments:
**a contended `fetch_add` must cost one atomic RMW per op -- no refcount
traffic**. It cost three contended atomics while `AtomicInt`'s methods paid a
retain/release pair on the shared handle per op (the borrowed-receiver
analysis disqualified them over `&self.value`; rule 5a's atomic-argument
carve-out in `compiler/koralc/codegen/codegen_borrowed_self.koral` is what
puts them back on the +0 convention).

**The deterministic gates for that claim live in tests, not here** -- the
`w12_atomic_*` RC window in `tests/runtime-cases/rc_counter_pin.koral` and
the atomic shape pin in `scripts/verify.sh` (generated-C grep: exactly one
atomic call in the `fetch_add` body, zero refcount traffic, no call-site
copy). The A/B tool quantifies the wall-time effect of changes that already
pass those gates; see `ab/README.md` for the run recipe
(`KORALC=... benchmarks/ab/run.sh`).

Notes on fairness: arithmetic in every case fits signed 64-bit so no language
hits its overflow policy differently (Koral and Swift trap, Go and Rust wrap);
the LCG is reduced modulo 2^31 each step for the same reason. Each language
uses its standard library's idiomatic container and sort implementations —
that is the comparison being asked about. Specifically:

- **Optimization level**: every binary is built at its -O2 tier —
  `koralc --release` (clang -O2), `go build` (always on), `swiftc -O`,
  `rustc -C opt-level=2`.
- **Capacity init**: every container is pre-sized to its final element count
  up front (`with_capacity` / `reserveCapacity` / `make(..., n)` /
  `Vec::with_capacity`), so no language pays growth-rehash costs the others
  don't. `string_build` is the one case that deliberately starts from a
  16-byte seed in all four — the append-growth policy is what it measures.
- **Sort verification**: the sort cases assert the output really is sorted
  and fold an order-sensitive checksum of the result into the RESULT line,
  so a wrong or partial sort is visible in the cross-language checksum check.
- **Workload parity**: every case uses each language's idiomatic loops and
  search primitives (`for-in`/`range`/iterators, streaming regex matches),
  with no form chosen or reverted for performance. Two measured traits of
  the idioms themselves are worth knowing: Swift's `for i in 0..<n` over
  `Int64` costs ~29% over a while counter on a trivial body (the
  `loop_pipeline` row includes that cost), and Swift's `string_find` sits
  at its standard search API floor — `range(of:options:.literal)` runs the
  per-call scan at ~128ms where a hand-rolled byte scan reaches ~4ms, but
  the hand-rolled form is not the idiom being compared. (The builder cases end with `into_string()` — the zero-copy
  hand-over, the same shape as Go's `String()` — so no final-copy tax is
  timed inside the Koral window.)
- **The `rust` row of `regex_scan` is absent**: the case needs the `regex`
  crate and a bare `rustc` cannot resolve it.
- **Hash seeding**: Koral's table hashing draws a per-process seed (hash
  flooding immunity). It costs a few ns per operation and makes run-to-run
  numbers wobble; `KORAL_HASH_SEED=<n>` pins it for exact reproduction. The
  other languages' table hashes are unseeded — that immunity is a Koral
  feature being paid for, not a benchmark defect.
- **Day-to-day variance** on this machine reaches ~25% (core scheduling,
  thermals) with no code change. Cross-day readings need a same-session
  anchor; only same-day A/B comparisons should be read as deltas. **Cross-machine
  readings are not comparable at all** — a 2026-11-10 same-machine A/B of the
  ARC optimization round (pre/post worktrees, same toolchain, same session)
  moved every koral row within ±5% (fib −6%, dict_lookup −4%, string_find
  −5%), while the same code measured on a Windows x86 box reports entirely
  different ratios against Go/Swift than this table. The table is this
  machine's; treat the ratio column as machine-specific.

## Results

### The atomic / lock pair A/B (2026-11-16)

The rule 5a carve-out measured as a same-tree A/B: one frozen source snapshot,
one toggle (the carve-out neutralized = the exact pre-change analysis), both
compilers built back-to-back, the 8 benchmark binaries run interleaved, best
of 5, this machine (Apple M4 Pro, 8 worker threads).

| shape | before | after | delta |
|---|---|---|---|
| atomic_fetch_add (checksum 8M) | 716.8 ms | 165.8 ms | **4.32x faster** |
| lock_counter (checksum 8M) | 96.9 ms | 98.5 ms | unchanged (control) |

The retain/release pair the shared `AtomicInt` handle paid per op is gone
(`fetch_add` call sites pass the handle +0; the callee releases nothing --
visible in the generated C before/after), and after the fix the Koral row sits
on the hardware floor: the same 8 x 1M shape as bare C11
(`atomic_fetch_add_explicit(..., seq_cst)`) runs 158.1 ms on this machine,
the Koral after row 165.8 ms -- 4.9%, inside run-to-run spread. The residual
~1.7x against the lock counter is contention physics, not refcount: the bare
C11 pthread-mutex counter of the same shape runs 77.1 ms, i.e. even in C a
single-line contended seq_cst RMW at 8 threads trails an adaptive mutex on a
three-instruction critical section (2.05x). The `lock_counter` control row
being flat shows the delta is exactly the atomic path.

### Cross-language table

2026-11-15, this machine (Apple arm64), best of 5 runs, ms. The ratio column
is koral / best(Go, Swift): below 1.0 means Koral is faster than both.

| case | koral | go | swift | rust (ref) | vs best |
|---|---|---|---|---|---|
| string_find | 6.10 | 15.42 | 131.03 | 10.58 | **0.40x** |
| sort_ints | 38.25 | 59.75 | 82.80 | 13.73 | **0.64x** |
| string_build | 4.54 | 5.30 | 11.62 | 7.81 | **0.86x** |
| loop_pipeline | 1.25 | 1.90 | 1.37 | 1.34 | **0.91x** |
| sort_strings | 26.63 | 27.92 | 37.98 | 16.54 | **0.95x** |
| set_membership | 16.14 | 26.37 | 16.77 | 10.76 | **0.96x** |
| regex_scan | 51.18 | 195.18 | 49.59 | – | 1.03x |
| fib_recursive | 0.45 | 0.44 | 0.42 | 0.36 | 1.07x |
| list_sum | 5.32 | 4.78 | 6.06 | 4.21 | 1.11x |
| dict_lookup | 78.28 | 67.38 | 53.97 | 67.65 | 1.45x |
| struct_iter | 11.90 | 8.14 | 8.40 | 11.36 | 1.46x |

**Six cases beat both Go and Swift outright** -- string_find 0.40x,
sort_ints 0.64x, string_build 0.86x, loop_pipeline 0.91x, sort_strings
0.95x and set_membership 0.96x -- and regex_scan sits at the ICU level
within noise. The sub-millisecond cases (fib, loop_pipeline) drift
noticeably between sessions on this machine while the longer cases hold
steady -- the ratios for those two are parity claims, not score.

The 2026-11-14 ARC round (compare-position borrowing, subscript borrow
reads) moved the compare-heavy rows in a same-session A/B against the
previous commit: string_find −45%, sort_strings −18%, dict_lookup −4%;
everything else within ±3%, and the two Int-only cases (list_sum,
loop_pipeline) flat on interleaved re-runs. `string_build` climbed from
1.67x to 0.89x on the builder hot path plus the runtime's small-block
string cache (a ~14ns malloc+free pair per small string, taken to ~1ns of
slot reuse) and holds at 0.86x.

## Where the remaining gaps come from

- `dict_lookup` (1.45x to Swift): key construction, not the dictionary.
  The case builds `"k\(i)"` per operation -- interpolation plumbing plus
  digit fill against Swift's inline-buffered short strings at ~no cost.
  Measured with prebuilt keys, the dict operations themselves run at about
  Go's level (insert ~50ns, lookup ~60ns per op) but not Swift's (~50ns):
  Swift keeps keys inline in its entries. The small-block cache took the
  allocation tax out; the deeper fix is a small-string (SSO)
  representation (`{ bytes, len }` is already the shape it needs),
  deferred as a representation project. The probe compares were the other
  half of this row and the 2026-11-14 round took them out (93.0ms at the
  2026-11-08 reading, 81.8ms before the round, 78.3ms after).
- `struct_iter` (1.46x to both): the case measures construction plus
  iteration over 5M small records. The iteration form is each language's
  idiomatic one (Koral `for v in xs`, Go `range`, Swift `for-in`, Rust
  `for p in &xs`); Koral's for-in and indexed forms measure the same here
  (~1.7ms both), so the gap is the construction loop: the growth call in
  the loop body stops the C backend from holding the box fields across
  iterations and from vectorizing the fill. The fix is a loop-level refill
  transformation (growth guard hoisted out of the fast loop) -- a codegen
  project, deferred.
- `regex_scan` (1.03x to ICU): Swift's engine is ICU -- a SIMD literal
  scan over a heavily tuned backtracker. Koral's pure-language engine
  (`std/text/regex_engine.koral`) runs a required-literal prefilter, a
  budgeted backtracker with capture undo and quantified-atom run fusion,
  and a Pike-VM fallback for pathological shapes; it is 3.5x ahead of Go's
  pure-language NFA. The remaining room is per-op constant in the
  backtracker's step loop and a vectorized literal scan.
- The sort pair versus Rust (2.0x--2.8x) is the reference ceiling showing:
  driftsort's SIMD merge networks are vectorization beyond std-level code.
  Against the mainstream bar both sort cases are at or ahead --
  `sort_strings` crossed it with the 2026-11-14 compare-borrowing round
  (the per-comparison string copy+drop pair is gone; −18% same-session).

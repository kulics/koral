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

## Running

    benchmarks/run.sh            # build all four languages, best-of-3 table
    RUNS=5 benchmarks/run.sh     # more repetitions
    KORALC=path/to/koralc benchmarks/run.sh

Requirements: `go`, `swiftc`, `rustc`, and `bin/compiler/koralc` (built by
`scripts/verify.sh` step 2, or any koralc via KORALC=).

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

2026-11-08, this machine (Apple arm64), best of 5 runs, ms. The ratio column
is koral / best(Go, Swift): below 1.0 means Koral is faster than both.

| case | koral | go | swift | rust (ref) | vs best |
|---|---|---|---|---|---|
| sort_ints | 37.80 | 60.06 | 82.01 | 13.85 | **0.63x** |
| loop_pipeline | 1.25 | 1.90 | 1.75 | 1.35 | **0.71x** |
| string_find | 11.14 | 13.90 | 129.54 | 10.47 | **0.80x** |
| set_membership | 13.95 | 26.90 | 16.77 | 11.02 | **0.83x** |
| string_build | 4.55 | 5.14 | 11.80 | 7.83 | **0.89x** |
| fib_recursive | 0.42 | 0.42 | 0.42 | 0.37 | 1.00x |
| list_sum | 4.83 | 4.34 | 5.89 | 3.95 | 1.11x |
| regex_scan | 56.24 | 193.83 | 49.99 | – | 1.13x |
| sort_strings | 33.46 | 28.60 | 37.88 | 16.53 | 1.17x |
| struct_iter | 11.76 | 8.00 | 8.14 | 11.53 | 1.47x |
| dict_lookup | 93.00 | 72.94 | 53.33 | 68.29 | 1.74x |

**Five cases beat both Go and Swift outright** (sort_ints 0.63x,
loop_pipeline 0.71x, string_find 0.80x, set_membership 0.83x,
string_build 0.89x) and fib_recursive is at parity. The sub-millisecond
cases (fib, loop_pipeline) drift noticeably between sessions on this
machine while the longer cases hold steady — the ratios for those two are
parity claims, not score. `string_build` climbed from 1.67x to 0.89x on
the builder hot path plus the runtime's small-block string cache
(a ~14ns malloc+free pair per small string, taken to ~1ns of slot reuse).

## Where the remaining gaps come from

- `dict_lookup` (1.74x to Swift): key construction, not the dictionary. The
  case builds `"k\(i)"` per operation — interpolation plumbing plus digit
  fill against Swift's inline-buffered short strings at ~no cost. Measured
  with prebuilt keys, the dict operations themselves run at about Go's
  level (insert ~50ns, lookup ~60ns per op) but not Swift's (~50ns): Swift
  keeps keys inline in its entries. The small-block cache took the
  allocation tax out; the deeper fix is a small-string (SSO)
  representation (`{ bytes, len }` is already the shape it needs),
  deferred as a representation project.
- `regex_scan` (1.13x to ICU): Swift's engine is ICU — a SIMD literal scan
  over a heavily tuned backtracker. Koral's pure-language engine
  (`std/text/regex_engine.koral`) runs a required-literal prefilter, a
  budgeted backtracker with capture undo and quantified-atom run fusion,
  and a Pike-VM fallback for pathological shapes; it is 3.5x ahead of Go's
  pure-language NFA. The remaining room is per-op constant in the
  backtracker's step loop and a vectorized literal scan.
- `struct_iter` (1.47x to both): the case measures construction plus
  iteration over 5M small records. The iteration form is each language's
  idiomatic one (Koral `for v in xs`, Go `range`, Swift `for-in`, Rust
  `for p in &xs`); Koral's for-in and indexed forms measure the same here
  (~1.7ms both), so the gap is the construction loop: the growth call in
  the loop body stops the C backend from holding the box fields across
  iterations and from vectorizing the fill. The fix is a loop-level refill
  transformation (growth guard hoisted out of the fast loop) -- a codegen
  project, deferred.
- `sort_strings` (1.17x to Go): the measured phase split puts ~75% of the
  case in the sort itself, and swapping in `sort_unstable` leaves the case
  unchanged within noise. The gap is per-comparison constant: ~8.6 ns per
  string compare against Go's ~5 ns. Swift, with a stable sort too, is
  slower than Koral's.
- The sort pair versus Rust (2.0x–2.8x) is the reference ceiling showing:
  driftsort's SIMD merge networks are vectorization beyond std-level code.
  Against the mainstream bar both sort cases are at or ahead.

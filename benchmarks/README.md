# Benchmarks

Cross-language runtime benchmarks for Koral's key types against Go, Swift and
Rust. Each case is the SAME workload (same algorithm, same input sizes, same
deterministic LCG) implemented idiomatically in all four languages, printing

    RESULT <checksum> <elapsed-ns>

The checksum guards that every language performed the same work — the runner
flags a row when they disagree.

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

## Results

2026-11-05, this machine (Apple arm64), best of 5 runs, ms:

| case | koral | go | swift | rust | koral vs best |
|---|---|---|---|---|---|
| loop_pipeline | 1.23 | 1.89 | 1.39 | 1.32 | **1.00x** |
| set_membership | 11.46 | 25.31 | 15.30 | 9.85 | 1.16x |
| fib_recursive | 0.50 | 0.46 | 0.43 | 0.38 | 1.33x |
| string_find | 14.13 | 12.80 | 259.66 | 9.97 | 1.42x |
| struct_iter | 14.11 | 7.37 | 7.57 | 10.28 | 1.91x |
| string_build | 12.69 | 4.97 | 11.15 | 7.23 | 2.55x |
| sort_ints | 34.99 | 54.03 | 74.96 | 12.52 | 2.80x |
| list_sum | 11.31 | 4.07 | 5.41 | 3.97 | 2.85x |
| sort_strings | 45.01 | 25.70 | 34.36 | 15.35 | 2.93x |
| dict_lookup | 171.45 | 76.52 | 57.34 | 75.55 | 2.99x |

Raw compute (loop_pipeline, fib_recursive) is at parity with Go/Swift/Rust —
`loop_pipeline` is the fastest of the four here; Koral beats Go and Swift on
`sort_ints` and beats Swift on `string_find` by 18x. Rust is the pace-setter on the sort cases: its default `sort()` is a
*stable* sort (driftsort), like Koral's and Swift's — Go's `sort.Ints` is a
pattern-defeating quicksort without a stability guarantee, which is
unobservable on scalar keys. The remaining gap is sort implementation
engineering, not a stability shortcut.

`set_membership` measures 1.5M hash-table operations on sequential Int keys —
the identity hash's best case — so it shows the price of the Dict/Set hash
mixing: every hash runs through a splitmix64 finalizer so patterned keys
(multiples of the table size, aligned pointers) can't collapse a bucket, and
that costs a few ns per operation. The immunity is worth more than the
benchmark win; the pre-mixing table was 6.67ms here.

History: before the 2026-11-04 optimization pass the same cases ran at
list_sum 72ms (17x), struct_iter 76ms (9.6x), sort_ints 167ms (9.3x),
set_membership 21ms (2.1x). Two changes closed most of the gap:

1. **borrowed-self (compiler)**: a non-escaping-`self` analysis (Swift's
   "guaranteed self" / ARC retain-release pair elision) passes managed
   receivers at +0 for place-receiver calls — no retain/release pair per
   method call. Temporary receivers keep the owned convention (drop timing is
   observable through `Drop`). See `compiler/koralc/codegen/codegen_borrowed_self.koral`.
2. **buffered merge sort (std)**: one scratch buffer per sort, move-semantics
   element transfers (no RC traffic), insertion-sort runs, pointer-walk hot
   loops (`std/list.koral`).

Remaining gaps are documented follow-ups: dict_lookup (String-key hashing and
per-lookup temporaries), string_build (allocation-bound: to_string malloc plus
defaulted-argument glue), extending the borrowed convention to non-receiver
parameters, and container growth calls on the push hot path — a growth helper
inlined into `push` fattens it past the inliner threshold, so the loop pays a
call per element (phase-split measurement: list_sum push ≈ 11ms, read ≈ 1.4ms
and already vectorized; split the cold growth path out to recover it).

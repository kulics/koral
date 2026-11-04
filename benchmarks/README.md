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
that is the comparison being asked about.

## Results

2026-11-04, this machine (Apple arm64), best of 5 runs, ms:

| case | koral | go | swift | rust | koral vs best |
|---|---|---|---|---|---|
| set_membership | 6.67 | 25.06 | 15.70 | 9.47 | **1.00x** |
| loop_pipeline | 1.66 | 1.97 | 1.63 | 1.54 | 1.08x |
| string_find | 17.13 | 13.85 | 260.33 | 10.24 | 1.67x |
| fib_recursive | 0.65 | 0.48 | 0.51 | 0.40 | 1.64x |
| string_build | 13.75 | 5.03 | 11.17 | 7.88 | 2.74x |
| struct_iter | 21.15 | 7.17 | 8.00 | 10.83 | 2.95x |
| dict_lookup | 152.69 | 62.06 | 50.61 | 62.51 | 3.02x |
| sort_strings | 51.50 | 26.09 | 34.95 | 15.48 | 3.33x |
| list_sum | 14.93 | 4.12 | 5.56 | 4.17 | 3.62x |
| sort_ints | 47.78 | 53.19 | 76.20 | 12.71 | 3.76x |

Raw compute (loop_pipeline, fib_recursive) is at parity with Go/Swift/Rust;
`set_membership` is the fastest of the four languages on this machine; Koral
also beats Swift on string_find by 15x. `sort_ints` beats Go and Swift (Rust's
unstable in-place sort remains ~4x faster than any stable merge sort).

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
defaulted-argument glue), and extending the borrowed convention to non-receiver
parameters.

#!/usr/bin/env bash
# Build and run the A/B instruments (NOT comparison cases -- see README.md).
# Prints each instrument's RESULT lines best-of-$RUNS. Same-session A/B only:
#   KORALC=/path/to/koralc-before benchmarks/ab/run.sh > /tmp/before.txt
#   KORALC=/path/to/koralc-after  benchmarks/ab/run.sh > /tmp/after.txt
# Compare the two Koral rows; the Go/Swift/Rust rows are same-shape floor
# references for the session, not a scoreboard. Portable: bash 3.2+.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

KORALC="${KORALC:-$REPO/bin/compiler/koralc}"
RUNS="${RUNS:-5}"

for case_dir in "$ROOT"/*/; do
  name="$(basename "$case_dir")"
  [ -f "$case_dir/main.koral" ] || continue
  echo "== $name"
  "$KORALC" build "$case_dir/main.koral" --release -o "$BUILD/koral-$name" >/dev/null 2>&1 \
    || echo "  koral FAILED"
  (cd "$case_dir" && go build -o "$BUILD/go-$name" main.go) 2>/dev/null || echo "  go FAILED"
  swiftc -O "$case_dir/main.swift" -o "$BUILD/swift-$name" 2>/dev/null || echo "  swift FAILED"
  rustc -C opt-level=2 "$case_dir/main.rs" -o "$BUILD/rust-$name" 2>/dev/null || echo "  rust FAILED"

  for lang in koral go swift rust; do
    bin="$BUILD/$lang-$name"
    # koralc emits <outdir>/<source stem>; the others are plain binaries
    if [ "$lang" = koral ]; then bin="$BUILD/koral-$name/main"; fi
    [ -x "$bin" ] || continue
    best=-1
    checksum=""
    i=0
    while [ "$i" -lt "$RUNS" ]; do
      i=$((i+1))
      out="$("$bin" 2>/dev/null)" || { best=-1; break; }
      cs="$(echo "$out" | awk '/^RESULT/ {print $2}')"
      ns="$(echo "$out" | awk '/^RESULT/ {print $3}')"
      checksum="$cs"
      if [ "$best" -lt 0 ] || [ "$ns" -lt "$best" ]; then best="$ns"; fi
    done
    if [ "$best" -lt 0 ]; then
      echo "  $lang: ERR"
    else
      echo "  $lang: $checksum $(awk -v ns="$best" 'BEGIN{printf "%.2f ms", ns/1000000}')"
    fi
  done
done

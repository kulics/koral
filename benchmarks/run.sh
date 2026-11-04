#!/usr/bin/env bash
# Build every benchmark case in Koral/Go/Swift/Rust, run each 3x, report the
# best wall time per language as a markdown table. Portable: bash 3.2+.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

KORALC="${KORALC:-$REPO/bin/compiler/koralc}"
RUNS="${RUNS:-3}"

for case_dir in "$ROOT"/cases/*/; do
  name="$(basename "$case_dir")"
  echo "== build $name"
  "$KORALC" build "$case_dir/main.koral" -o "$BUILD/koral-$name" >/dev/null 2>&1 || echo "  koral FAILED"
  (cd "$case_dir" && go build -o "$BUILD/go-$name" main.go) 2>/dev/null || echo "  go FAILED"
  swiftc -O "$case_dir/main.swift" -o "$BUILD/swift-$name" 2>/dev/null || echo "  swift FAILED"
  rustc -O "$case_dir/main.rs" -o "$BUILD/rust-$name" 2>/dev/null || echo "  rust FAILED"
done

# best-of-$RUNS nanoseconds for one binary; prints "<checksum> <ns>"
run_case() {
  local bin="$1"
  local best=-1 checksum=""
  local i out cs ns
  i=0
  while [ "$i" -lt "$RUNS" ]; do
    i=$((i+1))
    out="$("$bin" 2>/dev/null)" || { echo "ERR 0"; return; }
    cs="$(echo "$out" | awk '/^RESULT/ {print $2}')"
    ns="$(echo "$out" | awk '/^RESULT/ {print $3}')"
    checksum="$cs"
    if [ "$best" -lt 0 ] || [ "$ns" -lt "$best" ]; then best="$ns"; fi
  done
  echo "$checksum $best"
}

fmt_ms() {
  if [ "$1" = "-" ] || [ -z "$1" ]; then echo "-"; else awk -v ns="$1" 'BEGIN{printf "%.2f ms", ns/1000000}'; fi
}
ratio_vs() {
  if [ "$1" = "-" ] || [ -z "$1" ]; then echo "-"; else awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2fx", a/b}'; fi
}

echo
echo "| case | koral | go | swift | rust | koral vs best |"
echo "|---|---|---|---|---|---|"
for case_dir in "$ROOT"/cases/*/; do
  name="$(basename "$case_dir")"
  koral_cs="-"; go_cs="-"; swift_cs="-"; rust_cs="-"
  koral_ns="-"; go_ns="-"; swift_ns="-"; rust_ns="-"
  for lang in koral go swift rust; do
    bin="$BUILD/$lang-$name"
    # koralc emits <outdir>/<source stem>; the others are plain binaries
    if [ "$lang" = koral ]; then bin="$BUILD/koral-$name/main"; fi
    [ -x "$bin" ] || continue
    res="$(run_case "$bin")"
    cs="${res%% *}"; ns="${res##* }"
    if [ "$lang" = koral ]; then koral_cs="$cs"; koral_ns="$ns"; fi
    if [ "$lang" = go ]; then go_cs="$cs"; go_ns="$ns"; fi
    if [ "$lang" = swift ]; then swift_cs="$cs"; swift_ns="$ns"; fi
    if [ "$lang" = rust ]; then rust_cs="$cs"; rust_ns="$ns"; fi
  done
  uniq="$(echo "$koral_cs $go_cs $swift_cs $rust_cs" | tr ' ' '\n' | grep -v '^-$' | grep -v '^$' | sort -u | wc -l | tr -d ' ')"
  warn=""
  [ "$uniq" != "1" ] && warn=" ⚠️checksum"
  best=-1
  for ns in $koral_ns $go_ns $swift_ns $rust_ns; do
    [ "$ns" = "-" ] && continue
    if [ "$best" -lt 0 ] || [ "$ns" -lt "$best" ]; then best="$ns"; fi
  done
  echo "| $name$warn | $(fmt_ms "$koral_ns") | $(fmt_ms "$go_ns") | $(fmt_ms "$swift_ns") | $(fmt_ms "$rust_ns") | $(ratio_vs "$koral_ns" "$best") |"
done
echo
echo "(best of $RUNS runs; lower is better; 'koral vs best' = koral-time / fastest-time)"

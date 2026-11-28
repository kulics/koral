#!/usr/bin/env bash
# slice 战役 P4 回归量具：同一份用例分别用「基线」与「现行」两套 koralc+std
# 构建，各跑 RUNS 次取最优墙钟，报告比值。门槛（docs/implementation/
# slice-design-implementation.md P4）：纯 push ≤ 1.05×、for-in 零回归、
# map/求和 ≤ 1.03×、s[i] vs xs[i] ≤ 1.03×（同构建内）、小列表足迹 +16～32MB。
#
# 用法：
#   BEFORE_KORALC=/path/before/koralc BEFORE_HOME=/path/before \
#   AFTER_KORALC=/path/after/koralc   AFTER_HOME=/path/after \
#   bash benchmarks/regression/run.sh
# 缺省 AFTER=本仓库 bin/compiler/koralc + 仓库根。
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

BEFORE_KORALC="${BEFORE_KORALC:-}"
BEFORE_HOME="${BEFORE_HOME:-}"
AFTER_KORALC="${AFTER_KORALC:-$REPO/bin/compiler/koralc}"
AFTER_HOME="${AFTER_HOME:-$REPO}"
RUNS="${RUNS:-3}"

build_one() {
  local koralc="$1" home="$2" case="$3" out="$4"
  KORAL_HOME="$home" "$koralc" build "$ROOT/$case/main.koral" --release -o "$out" \
    > /dev/null 2>&1 || echo "  build FAILED: $case ($koralc)"
}

run_best() {
  local bin="$1" best=-1 i out ns
  i=0
  while [ "$i" -lt "$RUNS" ]; do
    i=$((i+1))
    out="$("$bin" 2>/dev/null)" || { echo "-"; return; }
    ns="$(echo "$out" | awk '/^RESULT/ {print $3}' | head -1)"
    if [ -n "$ns" ] && { [ "$best" -lt 0 ] || [ "$ns" -lt "$best" ]; }; then best="$ns"; fi
  done
  echo "$best"
}

run_slice_best() {
  # index_walk 的第二条 RESULT（切片下标）。
  local bin="$1" best=-1 i out ns
  i=0
  while [ "$i" -lt "$RUNS" ]; do
    i=$((i+1))
    out="$("$bin" 2>/dev/null)" || { echo "-"; return; }
    ns="$(echo "$out" | awk '/^RESULT/ {print $3}' | sed -n 2p)"
    if [ -n "$ns" ] && { [ "$best" -lt 0 ] || [ "$ns" -lt "$best" ]; }; then best="$ns"; fi
  done
  echo "$best"
}

rss_kb() {
  local bin="$1"
  if [ "$(uname -s)" = "Darwin" ]; then
    /usr/bin/time -l "$bin" > /dev/null 2> "$BUILD/rss.txt"
    awk '/maximum resident set size/ {print int($1/1024)}' "$BUILD/rss.txt"
  else
    /usr/bin/time -v "$bin" > /dev/null 2> "$BUILD/rss.txt"
    awk -F': ' '/Maximum resident set size/ {print $2}' "$BUILD/rss.txt"
  fi
}

ratio() {
  awk -v a="$1" -v b="$2" 'BEGIN{ if (b == "-" || b == "" || b+0 == 0) printf "-"; else printf "%.3fx", a/b }'
}

CASES="list_push forin_sum map_sum footprint"
for case in $CASES; do
  echo "== build $case"
  if [ -n "$BEFORE_KORALC" ]; then
    build_one "$BEFORE_KORALC" "$BEFORE_HOME" "$case" "$BUILD/before-$case"
  fi
  build_one "$AFTER_KORALC" "$AFTER_HOME" "$case" "$BUILD/after-$case"
done
# index_walk 只有现行侧可建（基线无切片语法）；门槛是同构建内 s[i] vs xs[i]。
echo "== build index_walk (after only)"
build_one "$AFTER_KORALC" "$AFTER_HOME" "index_walk" "$BUILD/after-index_walk"

echo
echo "| case | metric | before | after | ratio |"
echo "|---|---|---|---|---|"
for case in list_push forin_sum map_sum; do
  b="-"; a="-"
  [ -n "$BEFORE_KORALC" ] && b="$(run_best "$BUILD/before-$case/main")"
  a="$(run_best "$BUILD/after-$case/main")"
  echo "| $case | ns | $b | $a | $(ratio "$b" "$a") |"
done

al="$(run_best "$BUILD/after-index_walk/main")"
as="$(run_slice_best "$BUILD/after-index_walk/main")"
echo "| index_walk (list, after) | ns | - | $al | - |"
echo "| index_walk (slice, after) | ns | - | $as | - |"
echo "| index_walk (slice/list in-build gate) | ratio | - | $(ratio "$as" "$al") | - |"

if [ -n "$BEFORE_KORALC" ]; then
  br="$(rss_kb "$BUILD/before-footprint/main")"
else
  br="-"
fi
ar="$(rss_kb "$BUILD/after-footprint/main")"
if [ "$br" = "-" ] || [ -z "$br" ]; then
  echo "| footprint | RSS KB | - | $ar | - |"
else
  echo "| footprint | RSS KB | $br | $ar | +$((ar - br)) KB |"
fi

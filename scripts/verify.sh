#!/usr/bin/env bash
# Run the full verification chain. Works on macOS, Linux and Windows (Git Bash).
#
# The chain is fixed-order and must not be reordered -- see
# docs/implementation/bootstrap-productization.md.
# Each step is a different kind of evidence; reordering weakens what the run
# proves.
#
# Windows notes:
#   * Run from Git Bash (or any bash with `cmp`, `grep`, `test`).
#   * Native Windows binaries append `.exe`; this script asks for the
#     extension rather than hardcoding a spelling. The test runner already
#     accepts both.
#   * Work files go under the repository, not `/tmp`, so a native Windows
#     tool sees a real directory.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ── platform shims ────────────────────────────────────────────────────────────
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) WINDOWS=1 ;;
  *) WINDOWS=0 ;;
esac

if [ "$WINDOWS" = "1" ]; then
  EXE=".exe"
  # koral_runtime.c pulls in Winsock/BCrypt/PSAPI; the drivers add these
  # themselves, but the hand-rolled clang lines below must too.
  WIN_LIBS="-lws2_32 -lbcrypt -lpsapi"
else
  EXE=""
  WIN_LIBS=""
fi

SEED="compiler-reference/.build/release/koralc$EXE"
BOOTSTRAP="bin/compiler/koralc$EXE"
RUNNER="bin/compiler-test-runner/compiler_runner$EXE"

# Work files live in the repo so every tool resolves them the same way.
WORK="$ROOT/.verify-work"
rm -rf "$WORK"
mkdir -p "$WORK"

say() { printf '\n=== %s ===\n' "$*"; }

# ── 0) build the frozen seed, then the test harness WITH the seed ─────────────
say "0. build frozen seed"
swift build -c release --package-path compiler-reference

if [ ! -f "$SEED" ]; then
  echo "error: seed binary not found at $SEED" >&2
  echo "       SwiftPM writes to .build/<triple>/release/; the release symlink may be missing" >&2
  # Fall back to the target-triple directory.
  TRIPLE_SEED="$(echo compiler-reference/.build/*/release/koralc$EXE 2>/dev/null | head -1)"
  if [ -n "$TRIPLE_SEED" ] && [ -f "$TRIPLE_SEED" ]; then
    SEED="$TRIPLE_SEED"
    echo "       using $SEED"
  else
    exit 1
  fi
fi

# Trust boundary: the harness is built by the frozen reference, never by the
# implementation under test.
say "0. build test harness (with the seed)"
"$SEED" build \
  --package-config tests/compiler-runner/koral.json \
  --target-module compiler_runner \
  -o bin/compiler-test-runner

# ── 1) seed self-check ────────────────────────────────────────────────────────
say "1. seed self-check"
"$RUNNER" \
  --compiler swift \
  --swift-koralc "$SEED" \
  --timeout 60 -j 8 \
  --report-file "$WORK/1-seed.log"

# ── 2-3) build bootstrap from the seed, then the main gate ────────────────────
say "2. seed -> stage1"
"$SEED" build \
  --package-config compiler/koral.json \
  --target-module koralc \
  -o bin/compiler

say "3. main gate"
"$RUNNER" \
  --compiler bootstrap \
  --bootstrap-koralc "$BOOTSTRAP" \
  --timeout 60 -j 8 \
  --report-file "$WORK/3-bootstrap.log"

# ── 4) self-host two rounds + fixed point + dangling scan ─────────────────────
say "4. self-host + fixed point"
"$BOOTSTRAP" emit-c \
  --package-config compiler/koral.json --target-module koralc -o "$WORK/s2"
clang "$WORK/s2/koralc.c" std/koral_runtime.c -I std -o "$WORK/s2/koralc$EXE" \
  -Wno-everything -O1 $WIN_LIBS

"$WORK/s2/koralc$EXE" emit-c \
  --package-config compiler/koral.json --target-module koralc -o "$WORK/s3"
clang "$WORK/s3/koralc.c" std/koral_runtime.c -I std -o "$WORK/s3/koralc$EXE" \
  -Wno-everything -O1 $WIN_LIBS

"$WORK/s3/koralc$EXE" emit-c \
  --package-config compiler/koral.json --target-module koralc -o "$WORK/s4"

cmp "$WORK/s3/koralc.c" "$WORK/s4/koralc.c"
echo "FIXED POINT"

# A line that is a bare `name();` is a declaration with no definition -- the
# compiler emitted a call it never resolved.
dangling=$(grep -cE '^[a-zA-Z_][a-zA-Z0-9_]*\(\);' "$WORK/s3/koralc.c" || true)
echo "dangling=${dangling}"
test "${dangling}" = "0"

# ── 4b. self-check memory pin ─────────────────────────────────────────────────
# Type-checking the compiler package must stay in the hundreds of MB. Pins the
# 2026-11-13 bootstrap leak: one instantiated body carrying two DefIds (the
# deferred re-instantiation used to re-mint), which split the borrowed-receiver
# convention -- each trapped call site copied its receiver into a callee that
# never released the copy, and this run peaked at 3.07GB with 35.4M leaked
# blocks. The limit is ~7x the healthy peak (212MB) and half the failure.
say "4b. self-check memory pin"
if [ "$WINDOWS" = "0" ] && [ -x /usr/bin/time ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    /usr/bin/time -l "$WORK/s3/koralc$EXE" check \
      --package-config compiler/koral.json --target-module koralc \
      > "$WORK/4b-check.log" 2> "$WORK/4b-time.txt"
    rss_bytes=$(awk '/maximum resident set size/ {print $1}' "$WORK/4b-time.txt")
    rss_kb=$((rss_bytes / 1024))
  else
    /usr/bin/time -v "$WORK/s3/koralc$EXE" check \
      --package-config compiler/koral.json --target-module koralc \
      > "$WORK/4b-check.log" 2> "$WORK/4b-time.txt"
    rss_kb=$(awk -F': ' '/Maximum resident set size/ {print $2}' "$WORK/4b-time.txt")
  fi
  echo "self-check peak RSS: ${rss_kb} KB"
  test -n "${rss_kb}" && test "${rss_kb}" -lt 1500000 || {
    echo "self-check memory pin failed: ${rss_kb} KB (limit 1500000 KB)" >&2
    exit 1; }
else
  echo "memory pin skipped (Windows or no /usr/bin/time)"
fi

# ── 5) stage2 suite ───────────────────────────────────────────────────────────
say "5. stage2 suite"
"$RUNNER" \
  --compiler bootstrap \
  --bootstrap-koralc "$WORK/s2/koralc$EXE" \
  --timeout 60 -j 8 \
  --report-file "$WORK/5-stage2.log"

# ── 6) the differential oracle ────────────────────────────────────────────────
# Compiles and runs every case under BOTH compilers and requires them to behave
# identically, diagnostic text included. A single-sided regression fails here
# even if each still passes its own suite against the hand-written `// EXPECT`
# comments.
say "6. differential oracle"
"$RUNNER" \
  --compiler differential \
  --swift-koralc "$SEED" \
  --bootstrap-koralc "$BOOTSTRAP" \
  --timeout 60 -j 8 \
  --report-file "$WORK/6-differential.log"

# ── runtime stress ────────────────────────────────────────────────────────────
# The differential cannot see runtime bugs: both compilers link the same
# std/koral_runtime.c. This stage pins the strong/weak lifetime protocol
# directly -- exactly-one-free under concurrent strong/weak release, the
# destructor window, immortal blocks -- via a tracked free that aborts on any
# double free, and pins the codegen/runtime init contract (a fresh block
# starts at strong = 1, weak = 1: the implicit weak) by grepping emitted C.
say "runtime stress"
if [ "$WINDOWS" = "1" ]; then RT_LIBS="$WIN_LIBS"; else RT_LIBS="-lm -lpthread"; fi
clang -c -Dfree=koral_test_free -I std std/koral_runtime.c \
  -o "$WORK/rt_track.o" -Wno-everything -O1
clang -I std tests/runtime-cases/refcount_release_race.c "$WORK/rt_track.o" \
  -o "$WORK/refcount_release_race$EXE" -Wno-everything -O1 $RT_LIBS
"$WORK/refcount_release_race$EXE"
echo "refcount protocol OK"

# The non-atomic RC family of determinately non-sendable objects
# (concurrency-design.md §RC 分流): same strong/weak protocol single-threaded
# -- exactly-one-free, weak upgrade/downgrade, the destructor window (retain
# inside drop must not resurrect), immortal sentinels -- pinned through the
# same tracked free.
clang -I std tests/runtime-cases/nonatomic_refcount_stress.c "$WORK/rt_track.o" \
  -o "$WORK/nonatomic_refcount_stress$EXE" -Wno-everything -O1 $RT_LIBS
"$WORK/nonatomic_refcount_stress$EXE"
echo "nonatomic refcount protocol OK"

# The non-reentrant short object lock of safe `type sendable mutable` objects
# (concurrency-design.md §对象锁语义, 2026-11-09 redesign): mutual exclusion
# across threads and a clean hand-off; the short-lock discipline never holds
# two locks, so there is no owner reentry to exercise.
clang -c -I std std/koral_runtime.c -o "$WORK/rt_plain.o" -Wno-everything -O1
clang -I std tests/runtime-cases/object_lock_stress.c "$WORK/rt_plain.o" \
  -o "$WORK/object_lock_stress$EXE" -Wno-everything -O1 $RT_LIBS
"$WORK/object_lock_stress$EXE"
echo "object lock protocol OK"

# The string slab region's atomic publication (thin-pointer-design.md
# §并发下的内存序): the region pointer / end are read on every block free from
# every thread, so the lazy init must publish them atomically -- a torn read
# misclassifies a region slot as a malloc block and free() aborts on the
# interior pointer. Races 8 threads through the region init and the free-path
# membership test. Built WITH TSan where clang has it (macOS/Linux): the
# pre-fix plain-pointer publication is caught deterministically as a data
# race by TSan but only probabilistically by behavior, so the sanitizer run
# is the pin. Windows clang has no TSan -- run the plain build there.
if [ "$WINDOWS" = "1" ]; then
  clang -I std tests/runtime-cases/str_region_race.c "$WORK/rt_plain.o" \
    -o "$WORK/str_region_race$EXE" -Wno-everything -O1 $RT_LIBS
else
  clang -c -I std -fsanitize=thread std/koral_runtime.c -o "$WORK/rt_tsan.o" \
    -Wno-everything -O1
  clang -I std -fsanitize=thread tests/runtime-cases/str_region_race.c \
    "$WORK/rt_tsan.o" -o "$WORK/str_region_race$EXE" -Wno-everything -O1 $RT_LIBS
fi
"$WORK/str_region_race$EXE"
echo "str region publication OK"

"$BOOTSTRAP" emit-c tests/runtime-cases/weak_init_probe.koral -o "$WORK/weak_init_probe"
probe_c="$WORK/weak_init_probe/weak_init_probe.c"
grep -q 'weak_count = 1' "$probe_c"
if grep -q 'weak_count = 0' "$probe_c"; then
  echo "error: emitted control blocks are missing the implicit weak" >&2
  exit 1
fi
echo "weak init contract OK"

# WP-3 RC count pins (concurrency-design.md P6): the ARC optimizations are
# koralc-side -- the frozen seed is the semantic referee and carries none --
# so the exact retain/release counts are pinned here against a bootstrap
# build, not in the shared suite (which needs identical output either way).
# The instrumentation is compiled out of every normal build (KORAL_RC_STATS),
# so this stage builds its own runtime with the define: emit the C and link it
# here, exactly like the runtime-stress cases above. Release-surface negative
# pin first: a normal runtime build must carry NO stats symbols at all.
clang -c -I std std/koral_runtime.c -o "$WORK/rt_release_check.o" -Wno-everything -O1
if grep -a -q '__koral_rc_stats' "$WORK/rt_release_check.o"; then
  echo "release surface leak: rc stats must not exist outside KORAL_RC_STATS" >&2
  exit 1
fi
echo "release surface OK"
"$BOOTSTRAP" emit-c tests/runtime-cases/rc_counter_pin.koral -o "$WORK/rc_counter_pin"
clang -I std -DKORAL_RC_STATS "$WORK/rc_counter_pin/rc_counter_pin.c" std/koral_runtime.c   -o "$WORK/rc_counter_pin/rc_counter_pin$EXE" -Wno-everything -O1 $RT_LIBS
"$WORK/rc_counter_pin/rc_counter_pin$EXE" > "$WORK/rc_counter_pin.out"
grep -q 'w1_alias_retains=0' "$WORK/rc_counter_pin.out" || {
  echo "rc counter pin failed: alias pair elimination" >&2; exit 1; }
grep -q 'w2_move_chain_retains=0' "$WORK/rc_counter_pin.out" || {
  echo "rc counter pin failed: move chain" >&2; exit 1; }
grep -q 'w3_multiread_retains=1' "$WORK/rc_counter_pin.out" || {
  echo "rc counter pin failed: multi-read last move" >&2; exit 1; }
grep -q 'w5_probe_move_releases=1' "$WORK/rc_counter_pin.out" || {
  echo "rc counter pin failed: move release side" >&2; exit 1; }
grep -q 'w6_probe_alias_releases=0' "$WORK/rc_counter_pin.out" || {
  echo "rc counter pin failed: alias release side" >&2; exit 1; }
grep -q 'w7_into_frozen_retains=0' "$WORK/rc_counter_pin.out" || {
  echo "rc counter pin failed: into_frozen is a hand-off, not a copy" >&2; exit 1; }
grep -q 'w8_init_memory_retains=2' "$WORK/rc_counter_pin.out" || {
  echo "rc counter pin failed: init_memory argument is a consuming use" >&2; exit 1; }
echo "rc counter pins OK"

# ── samples ───────────────────────────────────────────────────────────────────
say "samples"
mkdir -p bin/samples
"$BOOTSTRAP" build samples/expr-eval/expr_eval.koral -o bin/samples
"$BOOTSTRAP" build samples/cat/src/cat.koral -o bin/samples
"$BOOTSTRAP" build samples/sha256sum/src/sha256sum.koral -o bin/samples
"$BOOTSTRAP" build samples/grep/src/grep.koral -o bin/samples

echo "hello koral" > "$WORK/sample_in.txt"
"bin/samples/cat$EXE" "$WORK/sample_in.txt" | grep -q "hello koral"
"bin/samples/sha256sum$EXE" "$WORK/sample_in.txt" | grep -q "  "
printf '1+2*3\nquit\n' | "bin/samples/expr_eval$EXE" | grep -q "^> 7$"
printf 'apple\nbanana\n' | "bin/samples/grep$EXE" 'an' | grep -q "^banana$"
echo "samples OK"

# ── toolchain ─────────────────────────────────────────────────────────────────
say "toolchain"
"$BOOTSTRAP" build \
  --package-config toolchain/koralfmt/koral.json \
  --target-module koralfmt/test -o bin/koralfmt-test
"bin/koralfmt-test/koralfmt__test$EXE"

"$BOOTSTRAP" build \
  --package-config toolchain/doc/koral.json \
  --target-module koral_doc -o bin/toolchain-doc-gen
"bin/toolchain-doc-gen/koral_doc$EXE" --self-test
"bin/toolchain-doc-gen/koral_doc$EXE" --check

# ── project layout (koral lint) ──────────────────────────────────────────────
# Ownership of a `.koral` file is checked here, not in `koralc`: a file outside
# the target's closure is not being compiled, so the compiler has no opinion on
# it. Whether it was MEANT to be in the program is a question about the
# repository (design `module-design.md` §7).
say "project layout"
"$BOOTSTRAP" build \
  --package-config toolchain/koral/koral.json \
  --target-module koral -o bin/koral-tool
"$BOOTSTRAP" build \
  --package-config toolchain/koral/koral.json \
  --target-module koral/test -o bin/koral-tool-test
"bin/koral-tool-test/koral__test$EXE"

for pkg in \
  compiler \
  std \
  toolchain/koral \
  toolchain/koral-syntax \
  toolchain/koralfmt \
  toolchain/doc \
  tests/compiler-runner
do
  "bin/koral-tool/koral$EXE" lint "$pkg"
done
echo "project layout OK"

say "ALL GREEN"

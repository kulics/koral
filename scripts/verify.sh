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

# ── samples ───────────────────────────────────────────────────────────────────
say "samples"
mkdir -p bin/samples
"$BOOTSTRAP" build samples/expr-eval/expr_eval.koral -o bin/samples
"$BOOTSTRAP" build samples/cat/src/cat.koral -o bin/samples
"$BOOTSTRAP" build samples/sha256sum/src/sha256sum.koral -o bin/samples

echo "hello koral" > "$WORK/sample_in.txt"
"bin/samples/cat$EXE" "$WORK/sample_in.txt" | grep -q "hello koral"
"bin/samples/sha256sum$EXE" "$WORK/sample_in.txt" | grep -q "  "
printf '1+2*3\nquit\n' | "bin/samples/expr_eval$EXE" | grep -q "^> 7$"
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

// Pins the unified stack-overflow report (2026-11-13 batch). A runaway
// recursion used to die with a bare platform artifact -- SIGSEGV/SIGBUS on
// macOS, SIGSEGV on Linux, EXCEPTION_STACK_OVERFLOW (0xC00000FD) on Windows,
// and nothing printed. The runtime now reports one line, identically on
// every platform:
//
//     Panic: stack overflow
//
// and aborts. The request here is 1 byte (clamps to the 64KB floor), so
// ~256KB of recursion MUST overflow: were the request silently upgraded to
// the 8MB default the recursion would survive and this pin fails on "did not
// crash". Frames stay small on purpose -- on macOS a large frame runs
// __chkstk_darwin, which extends a thread's stack past its set size and
// swallows the overflow (see stack_contract_pin.c).
//
// Build (see the "stack contract pins" stage in scripts/verify.sh):
//   clang stack_overflow_pin.c std/koral_runtime.c -I std -o stack_overflow_pin

#include "koral_runtime.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

__attribute__((noinline)) static int eat(int depth, uintptr_t* marks) {
    char pad;
    if (marks != NULL) {
        marks[depth] = (uintptr_t)&pad;
    }
    if (depth <= 0) {
        return 1;
    }
    int r = eat(depth - 1, marks);
    pad = (char)r;
    return r;
}

static size_t measure_frame(void) {
    uintptr_t marks[2] = {0, 0};
    (void)eat(1, marks);
    return (size_t)(marks[1] - marks[0]);
}

static void overflow_body(void) {
    size_t frame = measure_frame();
    size_t depth = (frame > 0) ? ((size_t)(256 * 1024) / frame) : 1;
    (void)eat((int)depth, NULL);
    printf("survived\n");
    fflush(stdout);
}

int main(void) {
    uint8_t* handle = NULL;
    uint64_t tid = 0;
    struct __koral_Closure closure;
    closure.fn = (void*)overflow_body;
    closure.env = NULL;
    closure.drop = NULL;
    if (__koral_spawn_thread(&handle, &tid, closure, 1) != 0) {
        printf("spawn_failed\n");
        return 2;
    }
    __koral_thread_join(handle);
    printf("no_overflow\n");
    return 3;
}

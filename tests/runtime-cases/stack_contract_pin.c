// Pins the unified thread stack contract (2026-11-13 batch). The policy in
// std/koral_runtime.c:
//   * stack_size = 0 selects KORAL_DEFAULT_STACK_SIZE (8MB) on every
//     platform -- the probe eats ~4MB on a default-stack thread and requires
//     it to survive. macOS pthreads default to 512KB and would die; so would
//     any regression to a platform default.
//   * an explicit size is honored: a 32MB request eats ~12MB and survives.
//     Ignored (falling back to the 8MB default) it would die.
//   * a below-floor request clamps UP to KORAL_MIN_STACK_SIZE (64KB): a 1
//     byte request still carries 32KB of recursion. It must survive (the
//     companion stack_overflow_pin.c pins the other half: it must NOT carry
//     the default's 8MB either).
//
// Two disciplines make the byte budgets real:
//   * frames are SMALL (well under a page) and measured at runtime -- on
//     macOS a large frame runs __chkstk_darwin, which EXTENDS a thread's
//     stack past its set size (8000 4KB frames walked 32MB on a "76KB"
//     stack), so large frames cannot pin a stack size at all;
//   * a use after the recursive call keeps the recursion off the tail
//     position (-O1 must not turn it into a loop).
//
// Build (see the "stack contract pins" stage in scripts/verify.sh):
//   clang stack_contract_pin.c std/koral_runtime.c -I std -o stack_contract_pin

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

// The eater's own frame width: two recorded local addresses one call apart.
static size_t measure_frame(void) {
    uintptr_t marks[2] = {0, 0};
    (void)eat(1, marks);
    return (size_t)(marks[1] - marks[0]);
}

typedef struct {
    const char* label;
    size_t budget;
    uint64_t request;
} Probe;

static Probe g_current;

static void probe_body(void) {
    size_t frame = measure_frame();
    size_t depth = (frame > 0) ? (g_current.budget / frame) : 1;
    (void)eat((int)depth, NULL);
    printf("%s\n", g_current.label);
    fflush(stdout);
}

static void run_probe(const char* label, size_t budget, uint64_t request) {
    g_current.label = label;
    g_current.budget = budget;
    g_current.request = request;
    uint8_t* handle = NULL;
    uint64_t tid = 0;
    struct __koral_Closure closure;
    closure.fn = (void*)probe_body;
    closure.env = NULL;
    closure.drop = NULL;
    if (__koral_spawn_thread(&handle, &tid, closure, request) != 0) {
        printf("spawn_failed %s\n", label);
        fflush(stdout);
        return;
    }
    __koral_thread_join(handle);
}

int main(void) {
    // ~4MB: survives only on a default stack >= 4MB (the unified 8MB).
    run_probe("default_ok", 4u * 1024 * 1024, 0);
    // ~12MB: survives only when the 32MB request is honored (the 8MB
    // default would die).
    run_probe("big_ok", 12u * 1024 * 1024, 32u * 1024 * 1024);
    // ~32KB: survives only if the 1 byte request clamped UP to the 64KB
    // floor (not down into a crash).
    run_probe("clamp_ok", 32u * 1024, 1);
    printf("all_ok\n");
    return 0;
}

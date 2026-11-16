// Pins the Windows stack RESERVATION semantics (2026-11-16 batch). Without
// STACK_SIZE_PARAM_IS_A_RESERVATION, _beginthreadex's stack-size parameter is
// the COMMIT size: 8MB committed per thread times many threads exhausts the
// process commit limit long before any stack is actually used. With the flag
// the size is a reservation -- the pages commit only as the thread touches
// them -- so the same spawn pattern stays cheap.
//
// The discriminator is commit charge while N threads HOLD their stacks (each
// one parks on a flag after touching a little of its stack):
//
//   * reserved (fixed): N threads park with ~pages-touched commit each --
//     measured growth stays well under 32MB;
//   * committed (the bug): N x 8MB lands in the commit charge the moment the
//     threads are created -- 8 threads = 64MB+, over the bound.
//
// The commit measurement is Windows-only (GetProcessMemoryInfo); on POSIX the
// same flow must simply work -- spawn, park, release, join -- and reports
// `reserve_ok` on creation alone. N=8 threads at the 8MB default.
//
// Build (see the "stack contract pins" stage in scripts/verify.sh):
//   clang stack_reserve_pin.c std/koral_runtime.c -I std -o stack_reserve_pin

#include "koral_runtime.h"

#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#if defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#include <psapi.h>
#endif

#define THREADS 8

static atomic_int g_ready;
static atomic_int g_release;

__attribute__((noinline)) static void holder_body(void) {
    // Touch a little of this thread's stack (so the frame really lands in
    // the committed window we are measuring), announce readiness, then hold
    // the stack alive until the main thread releases everyone.
    volatile uintptr_t pad[32];
    for (int i = 0; i < 32; i++) {
        pad[i] = (uintptr_t)i;
    }
    atomic_fetch_add(&g_ready, 1);
    while (atomic_load(&g_release) == 0) {
        __koral_thread_yield();
    }
}

static size_t process_commit_bytes(void) {
#if defined(_WIN32) || defined(_WIN64)
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) {
        return (size_t)pmc.PagefileUsage;
    }
#endif
    return 0;
}

int main(void) {
    uint8_t* handles[THREADS];
    uint64_t tids[THREADS];
    struct __koral_Closure closure;
    closure.fn = (void*)holder_body;
    closure.env = NULL;
    closure.drop = NULL;

    size_t commit_before = process_commit_bytes();

    for (int i = 0; i < THREADS; i++) {
        handles[i] = NULL;
        tids[i] = 0;
        // The unified default (8MB) on each thread: the size that must be a
        // reservation, not a commit.
        if (__koral_spawn_thread(&handles[i], &tids[i], closure, 0) != 0) {
            printf("spawn_failed %d\n", i);
            return 1;
        }
    }

    // Every thread has announced itself: its stack exists and is held now.
    while (atomic_load(&g_ready) != THREADS) {
        __koral_thread_yield();
    }

    int ok = 1;
#if defined(_WIN32) || defined(_WIN64)
    size_t commit_after = process_commit_bytes();
    size_t growth = commit_after - commit_before;
    // 8 threads of truly-committed 8MB stacks = 64MB+ of growth; reserved
    // stacks grow the commit charge by what the holders touched only.
    if (growth >= (size_t)32 * 1024 * 1024) {
        printf("commit_fail growth=%llu\n", (unsigned long long)growth);
        ok = 0;
    }
#endif

    atomic_store(&g_release, 1);
    for (int i = 0; i < THREADS; i++) {
        if (__koral_thread_join(handles[i]) != 0) {
            printf("join_failed %d\n", i);
            ok = 0;
        }
    }

    if (!ok) {
        return 1;
    }
    printf("reserve_ok\n");
    printf("all_ok\n");
    return 0;
}

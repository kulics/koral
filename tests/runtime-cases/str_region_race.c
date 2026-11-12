// Pins the string slab region's atomic publication (thin-pointer-design.md
// §并发下的内存序): `__koral_str_region` / `__koral_str_region_end` are read by
// EVERY thread on EVERY block free (`__koral_str_in_region` decides whether a
// dead block is a region slot or a plain malloc block). With plain-pointer
// publication a reader can see the region pointer before the region end -- a
// region slot is then misclassified as a malloc block and handed to free(),
// which aborts on an interior pointer (or corrupts the heap silently).
//
// This races the lazy region init across 8 threads (all allocating from a
// fresh process state, released by a spin barrier) and then hammers
// small-block alloc/free; every free re-runs the membership test.
//
// Negative control: run against the pre-fix plain-pointer publication under
// `-fsanitize=thread`, ThreadSanitizer reports the region-pointer race
// deterministically (verified 2026-11-12: TSan abort, 1 warning); behaviorally
// the torn window is a few instructions wide and only lands probabilistically,
// which is why verify.sh builds THIS case with TSan where clang has it.
//
// The weak-release acquire fence (same doc section) has no deterministic
// single-process pin: it is load-bearing only under weak/strong release
// interleavings a fence-less build can miss. The exactly-once free protocol it
// participates in is pinned by refcount_release_race.c.
//
// Build (see the "runtime stress" stage in scripts/verify.sh):
//   clang -c std/koral_runtime.c -o rt.o
//   clang str_region_race.c rt.o -o race -lpthread

#include "koral_runtime.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

#define THREADS 8
#define ROUNDS 200000

// ---- spin barrier ----------------------------------------------------------
static _Atomic int g_arrived = 0;
static _Atomic int g_generation = 0;

static void barrier_wait(void) {
    int gen = atomic_load(&g_generation);
    if (atomic_fetch_add(&g_arrived, 1) + 1 == THREADS) {
        atomic_store(&g_arrived, 0);
        atomic_fetch_add(&g_generation, 1);
    } else {
        while (atomic_load(&g_generation) == gen) {
            __koral_thread_yield();
        }
    }
}

static void worker(void) {
    barrier_wait();
    for (int i = 0; i < ROUNDS; i++) {
        // Small blocks live in the slab region: the free path's region
        // membership test is what races.
        uintptr_t len = (uintptr_t)(i % 24);
        void* payload = __koral_string_alloc(len);
        if (!payload) {
            fprintf(stderr, "str_region_race: allocation failed\n");
            abort();
        }
        ((uint8_t*)payload)[0] = (uint8_t)i;
        __koral_release_value(payload, NULL);
    }
}

static void spawn(void (*fn)(void), uint8_t** out_handle) {
    struct __koral_Closure closure;
    closure.fn = (void*)fn;
    closure.env = NULL;
    closure.drop = NULL;
    uint64_t tid = 0;
    if (__koral_spawn_thread(out_handle, &tid, closure, 0) != 0) {
        fprintf(stderr, "str_region_race: spawn failed\n");
        abort();
    }
}

int main(void) {
    uint8_t* handles[THREADS];
    for (int t = 0; t < THREADS; t++) {
        spawn(worker, &handles[t]);
    }
    for (int t = 0; t < THREADS; t++) {
        __koral_thread_join(handles[t]);
    }
    printf("str region race OK\n");
    return 0;
}

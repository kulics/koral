// Pins the non-reentrant short object lock protocol (concurrency-design.md
// §对象锁语义, 2026-11-09 redesign): __koral_Lock must give mutual exclusion
// across threads and a clean hand-off after release. The lock has no owner
// tracking and no reentry -- the compiler's short-lock discipline guarantees
// at most one lock is held at a time (the RHS of an assignment is evaluated
// outside the lock, and each access takes and drops its own short lock), so a
// same-thread double acquire is a compiler-impossible event and deliberately
// not exercised here: it would spin forever by contract.
//
// Build (see the "runtime stress" stage in scripts/verify.sh):
//   clang -c std/koral_runtime.c -o rt.o
//   clang object_lock_stress.c rt.o -o lock_stress

#include "koral_runtime.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

#define THREADS 8
#define ROUNDS 200000

static struct __koral_Lock g_lock;
static _Atomic int g_guarded = 0;   // only touched under g_lock
static _Atomic int g_acquire_ok = 0;

// Every thread hammers the same counter under the lock: the critical section
// is a read-modify-write of one word, mirroring `c.hits = c.hits + 1` as two
// separate short-lock accesses in generated code (the read under one lock,
// the write under the next).
static void hammer(void* env) {
    (void)env;
    for (int i = 0; i < ROUNDS; i++) {
        __koral_lock_acquire(&g_lock);
        int v = atomic_load_explicit(&g_guarded, memory_order_relaxed);
        atomic_store_explicit(&g_guarded, v + 1, memory_order_relaxed);
        __koral_lock_release(&g_lock);
    }
}

// A fresh acquire/release pair after the lock was last released: the hand-off
// must hand the lock to a waiting or later thread without residue.
static void acquire_probe(void* env) {
    (void)env;
    __koral_lock_acquire(&g_lock);
    atomic_store(&g_acquire_ok, 1);
    __koral_lock_release(&g_lock);
}

int main(void) {
    __koral_lock_init(&g_lock);

    uint8_t* handles[THREADS];
    for (int t = 0; t < THREADS; t++) {
        uint64_t tid = 0;
        struct __koral_Closure closure;
        closure.fn = (void*)hammer;
        closure.env = NULL;
        closure.drop = NULL;
        if (__koral_spawn_thread(&handles[t], &tid, closure, 0) != 0) {
            fprintf(stderr, "spawn failed\n");
            return 1;
        }
    }
    for (int t = 0; t < THREADS; t++) {
        __koral_thread_join(handles[t]);
    }

    int expected = THREADS * ROUNDS;
    int got = atomic_load(&g_guarded);
    if (got != expected) {
        fprintf(stderr, "mutual exclusion violated: %d != %d\n", got, expected);
        return 1;
    }

    // Hand-off: a fresh thread must be able to acquire after every holder
    // released.
    uint8_t* handle = NULL;
    uint64_t tid = 0;
    struct __koral_Closure closure;
    closure.fn = (void*)acquire_probe;
    closure.env = NULL;
    closure.drop = NULL;
    atomic_store(&g_acquire_ok, 0);
    if (__koral_spawn_thread(&handle, &tid, closure, 0) != 0) {
        fprintf(stderr, "spawn failed\n");
        return 1;
    }
    __koral_thread_join(handle);
    if (atomic_load(&g_acquire_ok) != 1) {
        fprintf(stderr, "hand-off probe failed\n");
        return 1;
    }

    printf("object lock protocol OK\n");
    return 0;
}

// Pins the reentrant object lock protocol (concurrency-design.md §对象锁语义):
// __koral_Lock must give mutual exclusion across threads, reentry on the owner
// thread, and a clean hand-off after release. Critical sections are one field
// access or one assignment statement in generated code, so the fast path is a
// single CAS and this test hammers exactly that shape.
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
static _Atomic int g_reentry_ok = 0;

// Every thread hammers the same counter under the lock: the critical section
// is a read-modify-write of one word, mirroring `c.hits = c.hits + 1`.
static void hammer(void* env) {
    (void)env;
    for (int i = 0; i < ROUNDS; i++) {
        __koral_lock_acquire(&g_lock);
        int v = atomic_load_explicit(&g_guarded, memory_order_relaxed);
        // Reentrant acquire inside the critical section (self-assignment
        // evaluation shape: `c.f = <expr touching c>`).
        __koral_lock_acquire(&g_lock);
        atomic_store_explicit(&g_guarded, v + 1, memory_order_relaxed);
        __koral_lock_release(&g_lock);
        __koral_lock_release(&g_lock);
    }
}

// After all hammer threads are joined, the owner-thread reentry rules are
// checked once on the main thread: acquire/release pairs must nest.
static void reentry_probe(void* env) {
    (void)env;
    __koral_lock_acquire(&g_lock);
    __koral_lock_acquire(&g_lock);
    __koral_lock_acquire(&g_lock);
    atomic_store(&g_reentry_ok, 1);
    __koral_lock_release(&g_lock);
    __koral_lock_release(&g_lock);
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

    reentry_probe(NULL);
    if (atomic_load(&g_reentry_ok) != 1) {
        fprintf(stderr, "reentry probe failed\n");
        return 1;
    }

    // Hand-off: a fresh thread must be able to acquire after the main thread
    // released everything.
    uint8_t* handle = NULL;
    uint64_t tid = 0;
    struct __koral_Closure closure;
    closure.fn = (void*)reentry_probe;
    closure.env = NULL;
    closure.drop = NULL;
    atomic_store(&g_reentry_ok, 0);
    if (__koral_spawn_thread(&handle, &tid, closure, 0) != 0) {
        fprintf(stderr, "spawn failed\n");
        return 1;
    }
    __koral_thread_join(handle);
    if (atomic_load(&g_reentry_ok) != 1) {
        fprintf(stderr, "hand-off probe failed\n");
        return 1;
    }

    printf("object lock protocol OK\n");
    return 0;
}

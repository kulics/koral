// Pins the strong/weak lifetime protocol in std/koral_runtime.c: the free of a
// [Control | payload] block must happen exactly once, no matter how the last
// strong release and the last weak release interleave.
//
// The bug this exists for: both release paths used to decide the free by
// checking the OTHER counter, so one thread dropping the last strong ref and
// one dropping the last weak ref could both observe zero and both call free()
// (ASan: "attempting double-free"), and the weak path could free the block
// while the strong path was still running its destructor.
//
// Build (see the "runtime stress" stage in scripts/verify.sh):
//   clang -c -Dfree=koral_test_free std/koral_runtime.c -o rt.o
//   clang refcount_release_race.c rt.o -o race
// `-Dfree=koral_test_free` routes every free() inside the runtime TU through
// the tracker below, so a double free aborts the test on any platform,
// without sanitizers. Unregistered pointers (thread trampoline args, format
// buffers) pass straight through to libc.

#include "koral_runtime.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

// ---- tracked free -----------------------------------------------------------
// One live block at a time: rounds are joined before the next registration.

static void* g_block = NULL;
static _Atomic int g_frees = 0;

static void track_register(void* p) {
    g_block = p;
    atomic_store(&g_frees, 0);
}

// The renamed free() of the runtime TU. Registered blocks must be freed
// exactly once; anything else aborts.
void koral_test_free(void* p) {
    if (!p) return;
    if (p == g_block) {
        int n = atomic_fetch_add(&g_frees, 1) + 1;
        if (n > 1) {
            fprintf(stderr, "double-free detected: block freed %d times\n", n);
            abort();
        }
    }
    free(p);  // real libc free: this TU is compiled without the rename
}

static void expect_frees(int want, const char* what) {
    int got = atomic_load(&g_frees);
    if (got != want) {
        fprintf(stderr, "%s: expected %d free(s), got %d\n", what, want, got);
        abort();
    }
}

// ---- fixtures ---------------------------------------------------------------

// The block allocation mirrors what codegen emits: strong = 1 (the owner) and
// weak = 1 implicit + 1 per explicit weak handle. This fixture holds one
// explicit weak handle, so weak starts at 2.
static struct __koral_Control* alloc_block(void** out_payload) {
    struct __koral_Control* control =
        (struct __koral_Control*)malloc(sizeof(struct __koral_Control) + 8);
    if (!control) abort();
    atomic_store(&control->strong_count, 1);
    atomic_store(&control->weak_count, 2);
    *out_payload = (char*)control + sizeof(struct __koral_Control);
    return control;
}

// ---- 1. sequential orderings ------------------------------------------------

static void sequential_once(int strong_first) {
    void* payload = NULL;
    struct __koral_Control* control = alloc_block(&payload);
    track_register(control);
    if (strong_first) {
        __koral_release_value(payload, NULL);
        expect_frees(0, "block must outlive the explicit weak handle");
        __koral_weak_release(control);
    } else {
        __koral_weak_release(control);
        expect_frees(0, "block must outlive the strong owner");
        __koral_release_value(payload, NULL);
    }
    expect_frees(1, "sequential release");
}

// ---- 2/3. concurrent releases -----------------------------------------------

static _Atomic int g_ready;
static _Atomic int g_gate;
static void* g_payload;
static struct __koral_Control* g_control;

static void rendezvous(void) {
    atomic_fetch_add(&g_ready, 1);
    while (atomic_load(&g_gate) == 0) {
        __koral_thread_yield();
    }
}

static void strong_dropper(void) {
    rendezvous();
    __koral_release_value(g_payload, NULL);
}

// Destructor guard: destroying the payload of an already-freed block is the
// use-after-free half of the bug (the weak path freeing while the strong path
// is between "count hit zero" and "dtor runs").
static void guard_dtor(void* payload) {
    if (atomic_load(&g_frees) != 0) {
        fprintf(stderr, "destructor ran after the block was freed\n");
        abort();
    }
    ((char*)payload)[0] = 1;
}

static void strong_dropper_with_dtor(void) {
    rendezvous();
    __koral_release_value(g_payload, guard_dtor);
}

static void weak_dropper(void) {
    rendezvous();
    __koral_weak_release(g_control);
}

static void spawn(void (*fn)(void), uint8_t** out_handle) {
    struct __koral_Closure closure;
    closure.fn = (void*)fn;
    closure.env = NULL;
    closure.drop = NULL;
    uint64_t tid = 0;
    if (__koral_spawn_thread(out_handle, &tid, closure, 0) != 0) {
        fprintf(stderr, "spawn failed\n");
        abort();
    }
}

static void concurrent_round(void (*strong_fn)(void)) {
    g_control = alloc_block(&g_payload);
    track_register(g_control);
    atomic_store(&g_ready, 0);
    atomic_store(&g_gate, 0);

    uint8_t* h_strong = NULL;
    uint8_t* h_weak = NULL;
    spawn(strong_fn, &h_strong);
    spawn(weak_dropper, &h_weak);

    while (atomic_load(&g_ready) != 2) {
        __koral_thread_yield();
    }
    atomic_store(&g_gate, 1);

    __koral_thread_join(h_strong);
    __koral_thread_join(h_weak);
    expect_frees(1, "concurrent release");
}

// ---- 4. immortal blocks -----------------------------------------------------

static void immortal_round(void) {
    // A static-literal-style block: both counters are sentinels. The fixture
    // stands one up on the heap only so the tracker can watch it.
    struct __koral_Control* control =
        (struct __koral_Control*)malloc(sizeof(struct __koral_Control) + 8);
    if (!control) abort();
    atomic_store(&control->strong_count, KORAL_IMMORTAL_REFCOUNT);
    atomic_store(&control->weak_count, KORAL_IMMORTAL_REFCOUNT);
    void* payload = (char*)control + sizeof(struct __koral_Control);
    track_register(control);

    __koral_retain_value(payload);
    __koral_release_value(payload, NULL);
    // Two weak handles at once: a naive "free when the weak count hits zero"
    // protocol walks the sentinel -1 up to 1 and frees the block on the way
    // down. The immortal guard must keep every weak op a no-op.
    __koral_weak_retain(control);
    __koral_weak_retain(control);
    __koral_weak_release(control);
    __koral_weak_release(control);

    // Downgrade/upgrade round trip: upgrade must fail -- the immortal sentinel
    // is not a live count -- and the handle drop must free nothing.
    struct __koral_Ref strong;
    strong.ptr = payload;
    struct __koral_WeakRef weak = __koral_downgrade_ref(strong);
    int ok = 0;
    (void)__koral_upgrade_ref(weak, &ok);
    if (ok) {
        fprintf(stderr, "immortal upgrade unexpectedly succeeded\n");
        abort();
    }
    __koral_weak_release(weak.control);

    expect_frees(0, "immortal block must never be freed");
    free(control);
    g_block = NULL;
}

// ---- main -------------------------------------------------------------------

int main(void) {
    for (int i = 0; i < 100000; i++) {
        sequential_once(1);
        sequential_once(0);
    }
    for (int i = 0; i < 5000; i++) {
        concurrent_round(strong_dropper);
    }
    for (int i = 0; i < 2000; i++) {
        concurrent_round(strong_dropper_with_dtor);
    }
    for (int i = 0; i < 1000; i++) {
        immortal_round();
    }
    printf("refcount_release_race ok\n");
    return 0;
}

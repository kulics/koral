// Pins the NON-ATOMIC strong/weak lifetime protocol (concurrency-design.md
// §RC 分流): the `*_nonatomic` family in std/koral_runtime.c must behave
// exactly like the atomic one single-threaded -- exactly-one-free under every
// release ordering, weak upgrade/downgrade round trips, the destructor window
// (a retain inside drop must not resurrect the object), and the immortal
// sentinel (static literal blocks are never freed).
//
// The nonatomic family is only sound for objects that never race (statically
// non-sendable, thread-confined -- or under the `unsafe sendable` promise),
// so this probe runs entirely on one thread. What it pins is protocol parity
// with refcount_release_race.c: same RcBox free decision (the weak count's
// zero crossing), same sentinels.
//
// Build (see the "runtime stress" stage in scripts/verify.sh):
//   clang -c -Dfree=koral_test_free std/koral_runtime.c -o rt_track.o
//   clang nonatomic_refcount_stress.c rt_track.o -o stress
// `-Dfree=koral_test_free` routes every free() inside the runtime TU through
// the tracker below, so a double free aborts the test on any platform,
// without sanitizers. Unregistered pointers pass straight through to libc.

#include "koral_runtime.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

// ---- tracked free -----------------------------------------------------------
// One live block at a time: rounds clean up before the next registration.

static void* g_block = NULL;
static int g_frees = 0;

static void track_register(void* p) {
    g_block = p;
    g_frees = 0;
}

// The renamed free() of the runtime TU. Registered blocks must be freed
// exactly once; anything else aborts.
void koral_test_free(void* p) {
    if (!p) return;
    if (p == g_block) {
        g_frees += 1;
        if (g_frees > 1) {
            fprintf(stderr, "double-free detected: block freed %d times\n", g_frees);
            abort();
        }
    }
    free(p);  // real libc free: this TU is compiled without the rename
}

static void expect_frees(int want, const char* what) {
    if (g_frees != want) {
        fprintf(stderr, "%s: expected %d free(s), got %d\n", what, want, g_frees);
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
    control->strong_count = 1;
    control->weak_count = 2;
    *out_payload = (char*)control + sizeof(struct __koral_Control);
    return control;
}

static int g_dtor_calls = 0;

// Destructor-window guard: destroying the payload of an already-freed block
// is the use-after-free half of a broken protocol, and a retain/release inside
// drop must NOT resurrect the object (strong is the -2 sentinel there).
static void guard_dtor(void* payload) {
    g_dtor_calls += 1;
    if (g_frees != 0) {
        fprintf(stderr, "destructor ran after the block was freed\n");
        abort();
    }
    ((char*)payload)[0] = 1;
}

static void guard_dtor_reentrant(void* payload) {
    guard_dtor(payload);
    // Retain inside drop: no-op (strong == -2). If it bumped the count, the
    // trailing release below would re-enter the destructor -- recursion.
    __koral_retain_value_nonatomic(payload);
    // Release inside drop: no-op for the same reason.
    __koral_release_value_nonatomic(payload, guard_dtor_reentrant);
}

// ---- 1. sequential orderings ------------------------------------------------

static void sequential_once(int strong_first) {
    void* payload = NULL;
    struct __koral_Control* control = alloc_block(&payload);
    track_register(control);
    g_dtor_calls = 0;
    if (strong_first) {
        __koral_release_value_nonatomic(payload, guard_dtor);
        expect_frees(0, "block must outlive the explicit weak handle");
        __koral_weak_release_nonatomic(control);
    } else {
        __koral_weak_release_nonatomic(control);
        expect_frees(0, "block must outlive the strong owner");
        __koral_release_value_nonatomic(payload, guard_dtor);
    }
    expect_frees(1, "sequential release");
    if (g_dtor_calls != 1) {
        fprintf(stderr, "destructor ran %d times, expected 1\n", g_dtor_calls);
        abort();
    }
}

// ---- 2. weak upgrade/downgrade round trip -----------------------------------

static void upgrade_round(void) {
    void* payload = NULL;
    struct __koral_Control* control = alloc_block(&payload);
    track_register(control);
    g_dtor_calls = 0;

    struct __koral_Ref strong;
    strong.ptr = payload;
    struct __koral_WeakRef weak = __koral_downgrade_ref_nonatomic(strong);
    // Downgrade bumps the weak count (implicit + this one + the fixture's
    // explicit one). The block must not be freed by any of it.
    expect_frees(0, "downgrade");

    int ok = 0;
    struct __koral_Ref up = __koral_upgrade_ref_nonatomic(weak, &ok);
    if (!ok || up.ptr != payload) {
        fprintf(stderr, "upgrade of a live block must succeed\n");
        abort();
    }
    // Release the upgraded strong first: count 2 -> 1, no dtor.
    __koral_release_value_nonatomic(up.ptr, guard_dtor);
    if (g_dtor_calls != 0) {
        fprintf(stderr, "destructor ran while a strong handle lives\n");
        abort();
    }
    expect_frees(0, "owner still alive");

    // Release the owner: dtor once, block survives the explicit weak handles.
    __koral_release_value_nonatomic(payload, guard_dtor);
    if (g_dtor_calls != 1) {
        fprintf(stderr, "destructor ran %d times, expected 1\n", g_dtor_calls);
        abort();
    }
    expect_frees(0, "weak handles keep the block alive");

    // Upgrade after death must fail (strong is 0, not a live count).
    ok = 1;
    struct __koral_Ref dead = __koral_upgrade_ref_nonatomic(weak, &ok);
    if (ok || dead.ptr != NULL) {
        fprintf(stderr, "upgrade of a dead block must fail\n");
        abort();
    }

    // The two explicit weak handles (fixture + the downgrade) release the
    // block exactly once, in either order.
    __koral_weak_release_nonatomic(weak.control);
    expect_frees(0, "one weak handle left");
    __koral_weak_release_nonatomic(control);
    expect_frees(1, "weak zero crossing frees once");
}

// ---- 3. destructor window: no resurrection ---------------------------------

static void dtor_window_round(void) {
    void* payload = NULL;
    struct __koral_Control* control = alloc_block(&payload);
    track_register(control);
    g_dtor_calls = 0;

    struct __koral_Ref strong;
    strong.ptr = payload;
    struct __koral_WeakRef weak = __koral_downgrade_ref_nonatomic(strong);

    // The reentrant dtor retains and releases its own payload while the
    // strong count is the destroying sentinel: both must be no-ops, the dtor
    // must run exactly once, and the weak upgrade during the window must fail
    // (the object is not resurrectable).
    __koral_release_value_nonatomic(payload, guard_dtor_reentrant);
    if (g_dtor_calls != 1) {
        fprintf(stderr, "destructor ran %d times, expected 1 (resurrection?)\n",
                g_dtor_calls);
        abort();
    }
    expect_frees(0, "explicit weak keeps the block alive past the dtor");

    // Two explicit weak handles are alive (the fixture's + the downgrade's);
    // the block frees only when both are gone -- exactly once.
    __koral_weak_release_nonatomic(weak.control);
    expect_frees(0, "one explicit weak handle left");
    __koral_weak_release_nonatomic(control);
    expect_frees(1, "exactly one free after the dtor window");
}

// ---- 4. immortal blocks -----------------------------------------------------

static void immortal_round(void) {
    // A static-literal-style block: both counters are sentinels. The fixture
    // stands one up on the heap only so the tracker can watch it.
    struct __koral_Control* control =
        (struct __koral_Control*)malloc(sizeof(struct __koral_Control) + 8);
    if (!control) abort();
    control->strong_count = KORAL_IMMORTAL_REFCOUNT;
    control->weak_count = KORAL_IMMORTAL_REFCOUNT;
    void* payload = (char*)control + sizeof(struct __koral_Control);
    track_register(control);
    g_dtor_calls = 0;

    __koral_retain_value_nonatomic(payload);
    __koral_release_value_nonatomic(payload, guard_dtor);
    // Two weak handles at once: the immortal guard must keep every weak op a
    // no-op, so the sentinel -1 is never walked up to 1 and back to 0.
    __koral_weak_retain_nonatomic(control);
    __koral_weak_retain_nonatomic(control);
    __koral_weak_release_nonatomic(control);
    __koral_weak_release_nonatomic(control);

    // Downgrade/upgrade round trip: upgrade must fail -- the immortal sentinel
    // is not a live count -- and the handle drop must free nothing.
    struct __koral_Ref strong;
    strong.ptr = payload;
    struct __koral_WeakRef weak = __koral_downgrade_ref_nonatomic(strong);
    int ok = 0;
    (void)__koral_upgrade_ref_nonatomic(weak, &ok);
    if (ok) {
        fprintf(stderr, "immortal upgrade unexpectedly succeeded\n");
        abort();
    }
    __koral_weak_release_nonatomic(weak.control);

    if (g_dtor_calls != 0) {
        fprintf(stderr, "destructor ran on an immortal block\n");
        abort();
    }
    expect_frees(0, "immortal block must never be freed");
    free(control);
    g_block = NULL;
}

// ---- 5. closure env counts --------------------------------------------------

// The drop glue of a closure env owns the free (codegen emits
// `__koral_<env>_drop` ending in `free(raw_env)`). It routes through the
// tracker here so exactly-once is observable.
static void env_drop_glue(void* raw_env) {
    koral_test_free(raw_env);
}

static void closure_env_round(void) {
    // A closure env block starts at 1 (codegen emits `__refcount = 1`) and is
    // freed by the release that observes the zero crossing -- with drop glue
    // it runs the glue instead of a raw free. Both paths are pinned.
    void* env = malloc(16);
    if (!env) abort();
    track_register(env);
    *(intptr_t*)env = 1;
    struct __koral_Closure closure;
    closure.fn = NULL;
    closure.env = env;
    closure.drop = NULL;

    __koral_closure_retain_nonatomic(closure);
    __koral_closure_release_nonatomic(closure);
    expect_frees(0, "env outlives one balanced pair");
    __koral_closure_release_nonatomic(closure);
    expect_frees(1, "env freed exactly once at refcount zero");

    // With drop glue the zero-crossing release runs the glue, which owns the
    // free. The tracker still sees exactly one free.
    void* env2 = malloc(16);
    if (!env2) abort();
    track_register(env2);
    *(intptr_t*)env2 = 1;
    struct __koral_Closure closure2;
    closure2.fn = NULL;
    closure2.env = env2;
    closure2.drop = env_drop_glue;
    __koral_closure_retain_nonatomic(closure2);
    __koral_closure_release_nonatomic(closure2);
    expect_frees(0, "env outlives one balanced pair (glue path)");
    __koral_closure_release_nonatomic(closure2);
    expect_frees(1, "env freed exactly once via the drop glue");
}

// ---- main -------------------------------------------------------------------

int main(void) {
    for (int i = 0; i < 100000; i++) {
        sequential_once(1);
        sequential_once(0);
    }
    for (int i = 0; i < 100000; i++) {
        upgrade_round();
    }
    for (int i = 0; i < 100000; i++) {
        dtor_window_round();
    }
    for (int i = 0; i < 1000; i++) {
        immortal_round();
    }
    for (int i = 0; i < 100000; i++) {
        closure_env_round();
    }
    printf("nonatomic_refcount_stress ok\n");
    return 0;
}

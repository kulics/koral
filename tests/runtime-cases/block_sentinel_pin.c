// Pins the unified storage block (slice design) runtime contract:
//   [Control | len | cap | elements...]   24B header, element area at
//   block_start + align_up(24, elem_align), handle = payload (&len).
//
// What is pinned here:
//   1. the header ABI (Control 8B, len/cap at payload[0..1], element offset),
//   2. __koral_block_alloc init contract (strong = 1, weak = 1, len = 0),
//   3. the immortal empty block: strong = weak = -1, len = cap = 0, and every
//      RC/weak op on it is a no-op -- it must NEVER reach free().  Empty
//      owners/windows hold this block instead of NULL because release(NULL)
//      would compute NULL - sizeof(Control).
//   4. __koral_strong_count read-only observation (including the sentinels).
//
// The "growth/detach paths skip the len write on negative sentinels" rule is
// emitted-code discipline (empty blocks live in read-only memory), not
// runtime behavior; the C side only guarantees the constant never needs one.
//
// Build (see the "runtime stress" stage in scripts/verify.sh):
//   clang -c -Dfree=koral_test_free std/koral_runtime.c -o rt.o
//   clang block_sentinel_pin.c rt.o -o pin
// `-Dfree=koral_test_free` routes every free() inside the runtime TU through
// the tracker below, so a free of the immortal block aborts the test on any
// platform, without sanitizers.

#include "koral_runtime.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

// ---- tracked free -----------------------------------------------------------

static void* g_block = NULL;          // the one malloc'd block under test
static void* g_immortal = NULL;       // must never be freed
static _Atomic int g_frees = 0;

static void track_register(void* p) {
    g_block = p;
    atomic_store(&g_frees, 0);
}

void koral_test_free(void* p) {
    if (!p) return;
    if (p == g_immortal) {
        fprintf(stderr, "immortal empty block reached free()\n");
        abort();
    }
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

static void expect(int cond, const char* what) {
    if (!cond) {
        fprintf(stderr, "FAIL: %s\n", what);
        abort();
    }
}

// The block's dtor hook: counts invocations so the release call site's
// monomorphized dtor contract is exercised through the tracked free.
static _Atomic int g_dtor_calls = 0;
static void count_dtor(void* payload) {
    (void)payload;
    atomic_fetch_add(&g_dtor_calls, 1);
}

// ---- 1. header ABI ----------------------------------------------------------

static void pin_header_abi(void) {
    expect(sizeof(struct __koral_Control) == 8, "Control is 8B");
    // len/cap are the payload's first two words; the element area starts at
    // block_start + align_up(24, elem_align).
    uintptr_t shapes[4][3] = {
        { 8, 8, 8 }, { 1, 1, 1 }, { 3, 16, 8 }, { 5, 2, 2 },
    };
    for (int i = 0; i < 4; i++) {
        uint64_t cap = shapes[i][0];
        uint64_t esz = shapes[i][1];
        uint64_t eal = shapes[i][2];
        void* payload = __koral_block_alloc(cap, esz, eal);
        uintptr_t* words = (uintptr_t*)payload;
        expect(words[0] == 0, "len starts at 0");
        expect(words[1] == (uintptr_t)cap, "cap is stored");
        char* block = (char*)payload - sizeof(struct __koral_Control);
        uint64_t off = (24u + eal - 1u) & ~(eal - 1u);
        char* elem = block + off;
        expect((uintptr_t)elem % eal == 0, "element area is aligned");
        expect(elem >= (char*)payload + 16, "elements do not overlap len/cap");
        // Touch first and last slot: the allocation must cover them.
        elem[0] = 1;
        elem[(size_t)(cap * esz - 1)] = 2;
        g_immortal = NULL;
        track_register((char*)payload - sizeof(struct __koral_Control));
        __koral_release_value(payload, count_dtor);
        expect_frees(1, "layout probe block freed exactly once");
    }
}

// ---- 2. alloc init contract -------------------------------------------------

static void pin_alloc_init(void) {
    void* payload = __koral_block_alloc(4, 8, 8);
    expect(__koral_strong_count(payload) == 1, "fresh block strong == 1");
    // weak == 1 (implicit weak) is the codegen/runtime init contract, pinned
    // elsewhere by the emitted-C grep; read it here too via the control.
    struct __koral_Control* control = __koral_control_of(payload);
    expect(atomic_load(&control->weak_count) == 1, "fresh block weak == 1");
    int base = atomic_load(&g_dtor_calls);
    __koral_retain(control);
    expect(__koral_strong_count(payload) == 2, "retain bumps strong");
    __koral_release_value(payload, count_dtor);
    expect(__koral_strong_count(payload) == 1, "release drops strong");
    expect(atomic_load(&g_dtor_calls) == base, "dtor not run at strong 1");

    track_register(control);
    __koral_release_value(payload, count_dtor);
    expect(atomic_load(&g_dtor_calls) == base + 1, "dtor runs exactly once at RC-0");
    expect_frees(1, "block freed exactly once");
}

// ---- 3. immortal empty block ------------------------------------------------

static void pin_empty_block(void) {
    void* payload = __koral_empty_block();
    expect(payload != NULL, "empty block payload exists");
    struct __koral_Control* control = __koral_control_of(payload);
    g_immortal = control;
    expect(atomic_load(&control->strong_count) == KORAL_IMMORTAL_REFCOUNT,
           "empty block strong == -1");
    expect(atomic_load(&control->weak_count) == KORAL_IMMORTAL_REFCOUNT,
           "empty block weak == -1");
    uintptr_t* words = (uintptr_t*)payload;
    expect(words[0] == 0, "empty block len == 0");
    expect(words[1] == 0, "empty block cap == 0");
    expect(__koral_strong_count(payload) == KORAL_IMMORTAL_REFCOUNT,
           "strong_count observes the sentinel");

    // Every RC/weak op must be a no-op: counters unchanged, nothing freed.
    int base = atomic_load(&g_dtor_calls);
    __koral_retain(control);
    __koral_retain(control);
    __koral_release_value(payload, count_dtor);
    __koral_release_value(payload, count_dtor);
    __koral_weak_retain(control);
    __koral_weak_release(control);
    expect(atomic_load(&control->strong_count) == KORAL_IMMORTAL_REFCOUNT,
           "retain/release leave strong at -1");
    expect(atomic_load(&control->weak_count) == KORAL_IMMORTAL_REFCOUNT,
           "weak ops leave weak at -1");
    expect(atomic_load(&g_dtor_calls) == base, "dtor never runs for the empty block");

    // Weak upgrade of an immortal block fails (no resurrection path).
    struct __koral_WeakRef w = { control };
    int ok = 1;
    struct __koral_Ref r = __koral_upgrade_ref(w, &ok);
    (void)r;
    expect(ok == 0, "weak upgrade of the empty block fails");
    expect(atomic_load(&control->strong_count) == KORAL_IMMORTAL_REFCOUNT,
           "failed upgrade leaves strong at -1");

    // Same block returned every call (a single constant).
    expect(__koral_empty_block() == payload, "empty block is a single constant");
}

int main(void) {
    pin_header_abi();
    pin_alloc_init();
    pin_empty_block();
    printf("block sentinel pin OK\n");
    return 0;
}

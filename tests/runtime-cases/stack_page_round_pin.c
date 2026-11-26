// Pins POSIX page rounding of thread stack sizes (2026-11-16 batch). macOS
// thread creation fails outright when the requested stack size is not a page
// multiple -- pthread_attr_setstacksize returns EINVAL for a size that is not
// a 4KB multiple, and the spawn then fails -- so the runtime rounds the
// resolved size UP to the system page size (after clamping, so the 64KB
// floor stays >= 64KB). Measured on arm64 macOS: the OS then further rounds
// to 16KB and adds a 12KB guard, so a live thread reports
// round_up(request, 16KB) + 12KB through pthread_get_stacksize_np. The two
// probes cover both edges:
//
//   * 200000 bytes: above the floor, NOT a page multiple -- creation must
//     succeed (this is the regression: unrounded, setstacksize rejects it
//     and the spawn fails) and the thread must carry the rounded size, not
//     a silent fall back to the platform default;
//   * 12345 bytes: below the floor -- clamps up to 64KB first (already
//     page-aligned), then rounds; the thread must carry the floor, not
//     12345 and not a default.
//
// Each spawned thread reads its own real stack size, so the assertions pin
// what the OS actually granted. Bounds: resolved <= actual < 2x resolved --
// the lower bound catches a size that never landed, the upper bound catches
// a fall back to the macOS 512KB pthread default (or any platform default),
// which lands well above 2x. The exact byte multiple is NOT asserted: the
// OS layers its own rounding and guard on top of the request (see above).
// On Windows the size parameter is rounded to the 64KB allocation
// granularity by _beginthreadex itself, so the byte bounds are POSIX-only;
// the Windows path just asserts the spawns carry their threads (see
// stack_reserve_pin.c for the reservation half).
//
// Frames stay small on purpose -- on macOS a large frame runs
// __chkstk_darwin, which extends a thread's stack past its set size (see
// stack_contract_pin.c).
//
// Build (see the "stack contract pins" stage in scripts/verify.sh):
//   clang stack_page_round_pin.c std/koral_runtime.c -I std -o stack_page_round_pin

#include "koral_runtime.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if !defined(_WIN32) && !defined(_WIN64)
#include <pthread.h>
#include <limits.h>
#include <unistd.h>
#include <sys/wait.h>
#endif

static struct {
    const char* label;
    uint64_t request;
    size_t actual;
} g_current;

static size_t current_thread_stack_size(void) {
#if defined(_WIN32) || defined(_WIN64)
    return 0;
#elif defined(__APPLE__)
    return (size_t)pthread_get_stacksize_np(pthread_self());
#else
    size_t size = 0;
    pthread_attr_t attr;
    if (pthread_getattr_np(pthread_self(), &attr) == 0) {
        // glibc's pthread_attr_getstack dereferences BOTH out-params
        // unconditionally -- passing NULL for the base segfaults even when
        // only the size is wanted.
        void* base = NULL;
        (void)pthread_attr_getstack(&attr, &base, &size);
        pthread_attr_destroy(&attr);
    }
    return size;
#endif
}

__attribute__((noinline)) static void probe_body(void) {
    g_current.actual = current_thread_stack_size();
}

static int run_probe(const char* label, uint64_t request) {
    g_current.label = label;
    g_current.request = request;
    g_current.actual = 0;
    uint8_t* handle = NULL;
    uint64_t tid = 0;
    struct __koral_Closure closure;
    closure.fn = (void*)probe_body;
    closure.env = NULL;
    closure.drop = NULL;
    if (__koral_spawn_thread(&handle, &tid, closure, request) != 0) {
        printf("spawn_failed %s\n", label);
        return -1;
    }
    __koral_thread_join(handle);
    return 0;
}

int main(void) {
#if defined(_WIN32) || defined(_WIN64)
    // _beginthreadex rounds to the 64KB allocation granularity on its own;
    // byte-level bounds are POSIX-only. Creation must still carry the thread.
    if (run_probe("nonmultiple_ok", 200000) != 0) return 1;
    if (run_probe("clamp_ok", 12345) != 0) return 1;
    printf("all_ok\n");
    return 0;
#else
    long page_size = sysconf(_SC_PAGESIZE);
    uint64_t page = (page_size > 0) ? (uint64_t)page_size : 4096u;
    uint64_t floor = ((uint64_t)PTHREAD_STACK_MIN > (uint64_t)KORAL_MIN_STACK_SIZE)
                         ? (uint64_t)PTHREAD_STACK_MIN
                         : (uint64_t)KORAL_MIN_STACK_SIZE;

    struct {
        const char* label;
        uint64_t request;
    } probes[2] = {
        {"nonmultiple_ok", 200000},
        {"clamp_ok", 12345},
    };

    for (int i = 0; i < 2; i++) {
        // glibc recycles freed thread stacks across sizes: a later, smaller
        // request can land on an earlier, bigger block and then report THAT
        // block's size through getattr_np (measured: a 65536 request after a
        // 200704 thread reports 200704). Each probe therefore runs in its own
        // process, where its spawned thread is the first one ever created and
        // the measurement is of the thread's own stack.
        pid_t pid = fork();
        if (pid < 0) {
            printf("spawn_failed fork\n");
            return 1;
        }
        if (pid == 0) {
            int rc = 0;
            if (run_probe(probes[i].label, probes[i].request) != 0) {
                rc = 1;
            } else {
                uint64_t resolved = (probes[i].request < floor) ? floor : probes[i].request;
                uint64_t rem = resolved % page;
                if (rem != 0) {
                    resolved += page - rem;
                }
                uint64_t actual = (uint64_t)g_current.actual;
                // No exact byte equality and no page-multiple assertion: the
                // OS adds its own rounding and guard on top of what we request
                // (16KB round + 12KB guard on arm64 macOS). These two bounds
                // are the contract -- the request landed, and nothing silently
                // fell back to a bigger platform default.
                if (actual < resolved || actual >= 2 * resolved) {
                    printf("bounds_fail %s actual=%llu expected=%llu\n", probes[i].label,
                           (unsigned long long)actual, (unsigned long long)resolved);
                    rc = 1;
                }
            }
            exit(rc);
        }
        int status = 0;
        if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) ||
            WEXITSTATUS(status) != 0) {
            return 1;
        }
    }
    printf("all_ok\n");
    return 0;
#endif
}

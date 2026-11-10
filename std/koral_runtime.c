// Koral runtime helpers (platform shims)
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdatomic.h>
#include <ctype.h>
#include "koral_runtime.h"

typedef struct CFile CFile;

static int32_t __koral_argc_storage = 0;
static uint8_t** __koral_argv_storage = NULL;

void __koral_set_args(int32_t argc, uint8_t** argv) {
    __koral_argc_storage = argc;
    __koral_argv_storage = argv;
}

int32_t __koral_argc(void) {
    return __koral_argc_storage;
}

uint8_t** __koral_argv(void) {
    return __koral_argv_storage;
}

// ── 小块 String 缓存 ──────────────────────────────────────────────────────
// malloc+free 一对 ≈14ns，是小串（to_string、字典键、插值）的成本大头。
// __koral_string_alloc 的小块（64B 槽 = Control + StringPayload + ≤39B 尾巴）
// 改从一块预留区分槽复用；回收判定 = 地址区间成员（O(1) 免查表），RC 协议、
// 块布局与 ABI 全部原样。区外块（大字符串、其它受管类型）照旧 malloc/free。
// 槽分配：线程本地 freelist（单线程访问，无 ABA）+ 线程本地 slab（slab 从区
// 内全局 bump 原子划取）；死块头 8 字节（strong/weak 槽已死）串 freelist。
// 区是一次性 malloc（POSIX 上大块 mmap 按需分页，未触碰页不占 RSS）；耗尽
// 后回落 malloc。
#define KORAL_STR_SLOT 64
#define KORAL_STR_SLAB_BYTES ((uintptr_t)256 * KORAL_STR_SLOT)
#define KORAL_STR_REGION_BYTES ((uintptr_t)32 * 1024 * 1024)

static char* __koral_str_region = NULL;
static uintptr_t __koral_str_region_end = 0;
static _Atomic(uintptr_t) __koral_str_region_top = 0;

static _Thread_local void* __koral_str_freelist = NULL;
static _Thread_local char* __koral_str_slab_next = NULL;
static _Thread_local char* __koral_str_slab_end = NULL;

// 惰性建区：CAS 竞争者自旋等发布。发布序（top/end 先于 region 指针）保证
// 看见 region 的线程一定看得见区界。
static void __koral_str_region_init(void) {
    static _Atomic int state = 0;
    int expected = 0;
    if (atomic_compare_exchange_strong(&state, &expected, 1)) {
        char* region = (char*)malloc(KORAL_STR_REGION_BYTES);
        if (region) {
            __koral_str_region_end = (uintptr_t)region + KORAL_STR_REGION_BYTES;
            atomic_store(&__koral_str_region_top, (uintptr_t)region);
            atomic_thread_fence(memory_order_release);
            __koral_str_region = region;
        } else {
            atomic_store(&state, 2);
        }
    } else {
        while (atomic_load(&state) == 1 && !__koral_str_region) {
            /* spin until the winner publishes (or fails) */
        }
    }
}

static inline int __koral_str_in_region(const void* p) {
    return __koral_str_region
        && (const char*)p >= __koral_str_region
        && (const char*)p < (const char*)__koral_str_region_end;
}

static void* __koral_str_slot_alloc(void) {
    if (__koral_str_freelist) {
        void* slot = __koral_str_freelist;
        __koral_str_freelist = *(void**)slot;
        return slot;
    }
    if (__koral_str_slab_next == __koral_str_slab_end) {
        uintptr_t base = atomic_fetch_add(&__koral_str_region_top, KORAL_STR_SLAB_BYTES);
        if (base == 0 || base + KORAL_STR_SLAB_BYTES > __koral_str_region_end) {
            return NULL; /* 区耗尽/未建：回落 malloc */
        }
        __koral_str_slab_next = (char*)base;
        __koral_str_slab_end = (char*)base + KORAL_STR_SLAB_BYTES;
    }
    void* slot = __koral_str_slab_next;
    __koral_str_slab_next += KORAL_STR_SLOT;
    return slot;
}

// RC 协议的唯一 free 接缝（release_slow 与 weak_release 共用）：区内的块回
// 线程本地 freelist，其余照旧 free。
static void __koral_control_free(struct __koral_Control* control) {
    if (__koral_str_in_region(control)) {
        *(void**)control = __koral_str_freelist;
        __koral_str_freelist = control;
        return;
    }
    free(control);
}

// Defined further down with the other panic surfaces; declared here so the
// allocation paths can fail cleanly instead of dereferencing NULL.
static KORAL_NORETURN void __koral_panic_print(const char* msg, const char* loc);

// 单块 String 分配（见 koral_runtime.h 的声明注释）。计数初始化与 codegen 的
// 受管构造一致（strong=1 / weak=1，含隐式 weak）。
void* __koral_string_alloc(uintptr_t len) {
    // 长度溢出闸：`len` 走 unchecked 路径（foreign / unchecked 算术）进来时，
    // `overhead + len` 会回绕成小 need，随后 `tail[len] = 0` 越界写。先按最大
    // 开销收口再算 need——Koral 层的 `+` 自带溢出 panic，这里是 C 侧最后一道。
    const uintptr_t overhead =
        sizeof(struct __koral_Control) + sizeof(struct __koral_StringPayload) + 1;
    if (len > UINTPTR_MAX - overhead) {
        __koral_panic_print("string length overflow while allocating a string block", NULL);
    }
    uintptr_t need = overhead + len;
    struct __koral_Control* control = NULL;
    if (need <= KORAL_STR_SLOT) {
        if (!__koral_str_region) {
            __koral_str_region_init();
        }
        if (__koral_str_region) {
            control = (struct __koral_Control*)__koral_str_slot_alloc();
        }
    }
    if (control) {
        /* 区槽：零初始化计数由下面的显式赋值覆盖，字节尾不保证为零。 */
    } else {
        control = (struct __koral_Control*)malloc(need);
        if (control == NULL) {
            __koral_panic_print("out of memory while allocating a string block", NULL);
        }
    }
    control->strong_count = 1;
    control->weak_count = 1;
    struct __koral_StringPayload* payload =
        (struct __koral_StringPayload*)__koral_payload_of(control);
    uint8_t* tail = (uint8_t*)payload + sizeof(struct __koral_StringPayload);
    tail[len] = 0;
    payload->data = tail;
    payload->len = len;
    return payload;
}

int32_t __koral_memcmp(uint8_t* a, uint8_t* b, uintptr_t n) {
    return (int32_t)memcmp(a, b, (size_t)n);
}

// 慢路径：强引用归零后的析构与释放。快路径在 koral_runtime.h 里内联。
// dtor 由释放调用点单态化后传进来，头里不再存析构函数。
// ---- RC 观测计数（见 koral_runtime.h 的说明；发布面剔除）----
#ifdef KORAL_RC_STATS
int __koral_rc_stats_enabled = 0;
uint64_t __koral_rc_stats_retain_total = 0;
uint64_t __koral_rc_stats_release_total = 0;

void __koral_rc_stats_enable(void) {
    __koral_rc_stats_enabled = 1;
    __koral_rc_stats_retain_total = 0;
    __koral_rc_stats_release_total = 0;
}

uint64_t __koral_rc_stats_retains(void) {
    return __koral_rc_stats_retain_total;
}

uint64_t __koral_rc_stats_releases(void) {
    return __koral_rc_stats_release_total;
}
#endif

void __koral_release_slow(struct __koral_Control* control, __koral_Dtor dtor) {
    if (dtor) {
        // 析构期间对象处于「不可复活」状态：`drop(self)` 里的 `self` 是同一个
        // payload 的句柄，方法调用按值传接收者就会 retain 一次、在方法结束时
        // release 一次。若走正常计数，retain 会把 0 抬回 1，随后的 release
        // 又会以 prev == 1 重新进入本函数——析构递归。
        // `strong_count = -2`（destroying）：retain/release 不改符号（不会复活、
        // 不会重入），但**朝 -2 记账**（retain 减、release 加），weak 的 upgrade
        // 也要求 > 0。析构体结束后计数若不再是 -2，就是有句柄净逃出了 drop 体
        // （`self` 被存进别处）——报错，而不是放它变成悬垂指针。随后恢复 0。
        // 注意 immortal 哨兵是 -1，两个哨兵不共享：weak 操作只对 -1 早退，
        // 析构期间 weak 递减必须照常进行。
        atomic_store(&control->strong_count, KORAL_DESTROYING_REFCOUNT);
        dtor(__koral_payload_of(control));
        if (atomic_load(&control->strong_count) != KORAL_DESTROYING_REFCOUNT) {
            __koral_panic_print("self escaped a drop body", NULL);
        }
        atomic_store(&control->strong_count, 0);
    }
    // Merged layout: control block and payload are in the same allocation.
    // 「payload 还活着」持有的隐式 weak 在这里释放，且**必须**在 dtor 跑完
    // 之后——析构期间块不得被 free。free 的唯一判定点是 weak_count 到 0 的
    // 那次 fetch_sub（RcBox 协议）：强路径与弱路径都走同一判定，胜者恰好
    // 一个。早先「强看 weak、weak 看 strong」的互查是两个释放者，两线程并发
    // 各释放一个引用计数时双双看到 0，double free。
    // release 减量：发布 dtor 的写。胜者是本线程时直接 free；胜者是别的
    // weak_release 时，对方的 acquire fence 与这里同步（见 __koral_weak_release）。
    if (atomic_fetch_sub_explicit(&control->weak_count, 1, memory_order_release) == 1) {
        __koral_control_free(control);
    }
}

void __koral_weak_retain(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    if (atomic_load_explicit(&control->strong_count, memory_order_relaxed) == KORAL_IMMORTAL_REFCOUNT) return;
    atomic_fetch_add_explicit(&control->weak_count, 1, memory_order_relaxed);
}

void __koral_weak_release(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    if (atomic_load_explicit(&control->strong_count, memory_order_relaxed) == KORAL_IMMORTAL_REFCOUNT) return;
    // 唯一的 free 判定点：weak 计数（含隐式 +1）递减到 0 的这一方释放整块。
    // 不看 strong_count —— 互查会给出两个释放者（见 __koral_release_slow）。
    if (atomic_fetch_sub_explicit(&control->weak_count, 1, memory_order_release) == 1) {
        // 与析构线程的隐式 weak 释放（release 减量）同步：free 之前必须看得见
        // dtor 对 payload 的全部写。RMW 链构成 release sequence，这一道
        // acquire fence 把析构线程的写并入本线程。
        atomic_thread_fence(memory_order_acquire);
        __koral_control_free(control);
    }
}

void __koral_weakref_drop(void* raw_weak_ref) {
    if (!raw_weak_ref) return;
    struct __koral_WeakRef* weak_ref = (struct __koral_WeakRef*)raw_weak_ref;
    __koral_weak_release(weak_ref->control);
}

// 类型无关的 trait object 销毁：把 vtable 起始处转成 `__koral_VTableHeader`，
// 从那里取具体类型的 drop glue。这是头里去掉 dtor 之后，类型擦除场景唯一的析构入口。
void __koral_traitref_drop(void* raw_trait_ref) {
    if (!raw_trait_ref) return;
    struct __koral_TraitRef* ref = (struct __koral_TraitRef*)raw_trait_ref;
    if (!ref->ptr) return;
    __koral_Dtor destroy = NULL;
    if (ref->vtable) {
        destroy = ((const struct __koral_VTableHeader*)ref->vtable)->destroy;
    }
    __koral_release_value(ref->ptr, destroy);
}

struct __koral_WeakRef __koral_downgrade_ref(struct __koral_Ref r) {
    struct __koral_WeakRef w;
    w.control = r.ptr ? __koral_control_of(r.ptr) : NULL;
    if (w.control) {
        __koral_weak_retain(w.control);
    }
    return w;
}

struct __koral_Ref __koral_upgrade_ref(struct __koral_WeakRef w, int* success) {
    struct __koral_Ref r;
    r.ptr = NULL;
    *success = 0;

    if (!w.control) return r;

    struct __koral_Control* control = (struct __koral_Control*)w.control;
    int old_count = atomic_load_explicit(&control->strong_count, memory_order_relaxed);
    // immortal（-1）不是活计数：upgrade 一律失败（见
    // tests/runtime-cases/refcount_release_race.c 钉住的契约）。
    while (old_count > 0) {
        // acquire：成功升级要与「把计数减到 old_count 的那次 release」同步，
        // 保证 payload 的写对本线程可见。失败侧 relaxed 足够。
        if (atomic_compare_exchange_weak_explicit(
                &control->strong_count, &old_count, old_count + 1,
                memory_order_acquire, memory_order_relaxed)) {
            r.ptr = __koral_payload_of(control);
            *success = 1;
            return r;
        }
    }

    return r;
}

void __koral_closure_retain(struct __koral_Closure closure) {
    if (!closure.env) return;
    _Atomic intptr_t* refcount = (_Atomic intptr_t*)closure.env;
    atomic_fetch_add_explicit(refcount, 1, memory_order_relaxed);
}

void __koral_closure_release(struct __koral_Closure closure) {
    if (!closure.env) return;
    _Atomic intptr_t* refcount = (_Atomic intptr_t*)closure.env;
    intptr_t prev = atomic_fetch_sub_explicit(refcount, 1, memory_order_release);
    if (prev == 1) {
        // 与 control 层同协议：归零方补 acquire fence，再走析构/释放。
        atomic_thread_fence(memory_order_acquire);
        if (closure.drop) {
            closure.drop(closure.env);
        } else {
            free(closure.env);
        }
    }
}

void __koral_closure_drop(void* raw_closure) {
    if (!raw_closure) return;
    struct __koral_Closure* closure = (struct __koral_Closure*)raw_closure;
    __koral_closure_release(*closure);
}

// ── 非原子 RC 族（concurrency-design.md §RC 分流）────────────────────────────
//
// 与上面的原子族逐入口一一对应，计数改普通整数操作（经 `int*` 访问同一个
// `_Atomic int` 存储）。协议、哨兵、free 判定点完全一致；区别只在内存序：
// 单线程（或经 `unsafe sendable` 承诺自管同步的跨界）语义不变。一个块只由
// 一族碰——族由静态类型在 codegen 调用点决定，绝不混用。

// 慢路径：强引用归零后的析构与释放。与 __koral_release_slow 同协议
// （析构窗口 -2、隐式 weak 释放在 dtor 之后、free 只看 weak 的零穿越）。
void __koral_release_slow_nonatomic(struct __koral_Control* control, __koral_Dtor dtor) {
    if (dtor) {
        int* strong = (int*)&control->strong_count;
        *strong = KORAL_DESTROYING_REFCOUNT;
        dtor(__koral_payload_of(control));
        if (*strong != KORAL_DESTROYING_REFCOUNT) {
            __koral_panic_print("self escaped a drop body", NULL);
        }
        *strong = 0;
    }
    int* weak = (int*)&control->weak_count;
    int prev_weak = *weak;
    *weak = prev_weak - 1;
    if (prev_weak == 1) {
        free(control);
    }
}

void __koral_weak_retain_nonatomic(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    int* strong = (int*)&control->strong_count;
    if (*strong == KORAL_IMMORTAL_REFCOUNT) return;
    int* weak = (int*)&control->weak_count;
    *weak += 1;
}

void __koral_weak_release_nonatomic(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    int* strong = (int*)&control->strong_count;
    if (*strong == KORAL_IMMORTAL_REFCOUNT) return;
    // 唯一的 free 判定点：weak 计数递减到 0 的这一方释放整块（同原子族）。
    int* weak = (int*)&control->weak_count;
    int prev_weak = *weak;
    *weak = prev_weak - 1;
    if (prev_weak == 1) {
        free(control);
    }
}

void __koral_weakref_drop_nonatomic(void* raw_weak_ref) {
    if (!raw_weak_ref) return;
    struct __koral_WeakRef* weak_ref = (struct __koral_WeakRef*)raw_weak_ref;
    __koral_weak_release_nonatomic(weak_ref->control);
}

// 类型无关的 trait object 销毁（非原子族）：vtable 头里取具体类型的 drop glue。
void __koral_traitref_drop_nonatomic(void* raw_trait_ref) {
    if (!raw_trait_ref) return;
    struct __koral_TraitRef* ref = (struct __koral_TraitRef*)raw_trait_ref;
    if (!ref->ptr) return;
    __koral_Dtor destroy = NULL;
    if (ref->vtable) {
        destroy = ((const struct __koral_VTableHeader*)ref->vtable)->destroy;
    }
    __koral_release_value_nonatomic(ref->ptr, destroy);
}

struct __koral_WeakRef __koral_downgrade_ref_nonatomic(struct __koral_Ref r) {
    struct __koral_WeakRef w;
    w.control = r.ptr ? __koral_control_of(r.ptr) : NULL;
    if (w.control) {
        __koral_weak_retain_nonatomic(w.control);
    }
    return w;
}

struct __koral_Ref __koral_upgrade_ref_nonatomic(struct __koral_WeakRef w, int* success) {
    struct __koral_Ref r;
    r.ptr = NULL;
    *success = 0;

    if (!w.control) return r;

    struct __koral_Control* control = (struct __koral_Control*)w.control;
    int* strong = (int*)&control->strong_count;
    // immortal（-1）不是活计数：upgrade 一律失败（与原子族同契约）。
    // 非原子升级就是普通「查 > 0 再 +1」——单线程内与 CAS 循环语义相同。
    if (*strong > 0) {
        *strong += 1;
        r.ptr = __koral_payload_of(control);
        *success = 1;
    }
    return r;
}

void __koral_closure_retain_nonatomic(struct __koral_Closure closure) {
    if (!closure.env) return;
    intptr_t* refcount = (intptr_t*)closure.env;
    *refcount += 1;
}

void __koral_closure_release_nonatomic(struct __koral_Closure closure) {
    if (!closure.env) return;
    intptr_t* refcount = (intptr_t*)closure.env;
    intptr_t prev = *refcount;
    *refcount = prev - 1;
    if (prev == 1) {
        // 单线程归零方自己跑析构/释放，无需 fence（同协议、同 free 判定点）。
        if (closure.drop) {
            closure.drop(closure.env);
        } else {
            free(closure.env);
        }
    }
}

void __koral_closure_drop_nonatomic(void* raw_closure) {
    if (!raw_closure) return;
    struct __koral_Closure* closure = (struct __koral_Closure*)raw_closure;
    __koral_closure_release_nonatomic(*closure);
}

CFile* __koral_stdin(void) {
    return (CFile*)stdin;
}

CFile* __koral_stdout(void) {
    return (CFile*)stdout;
}

CFile* __koral_stderr(void) {
    return (CFile*)stderr;
}

// Every panic is terminal (this helper ends in abort): marked noreturn so
// the C backend stops treating a failed check as a memory clobber on the
// success path -- a call in the loop otherwise forces per-iteration reloads.
static KORAL_NORETURN void __koral_panic_print(const char* msg, const char* loc) {
    if (loc != NULL && loc[0] != '\0') {
        fprintf(stderr, "Panic: %s at %s\n", msg, loc);
    } else {
        fprintf(stderr, "Panic: %s\n", msg);
    }
    abort();
}

void __koral_panic_numeric_conversion_overflow(const char* loc) {
    __koral_panic_print("numeric conversion overflow", loc);
}

void __koral_panic_division_by_zero(const char* loc) {
    __koral_panic_print("division by zero", loc);
}

void __koral_panic_remainder_by_zero(const char* loc) {
    __koral_panic_print("remainder by zero", loc);
}

uint64_t __koral_wrapping_bits_from_f64(double v, unsigned width_bits, const char* loc) {
    if (!isfinite(v)) {
        __koral_panic_numeric_conversion_overflow(loc);
    }
    // fmod is exact in IEEE 754: the remainder of the value modulo 2^N is the
    // two's-complement low bits of the truncated integer. The C cast below
    // truncates the remaining fraction toward zero.
    double modulus = (width_bits >= 64)
        ? 18446744073709551616.0
        : (double)((uint64_t)1 << width_bits);
    double r = fmod(v, modulus);
    if (r < 0.0) {
        return 0ull - (uint64_t)(-r);
    }
    return (uint64_t)r;
}

void __koral_panic_overflow_add(const char* loc) {
    __koral_panic_print("integer overflow in addition", loc);
}

void __koral_panic_overflow_sub(const char* loc) {
    __koral_panic_print("integer overflow in subtraction", loc);
}

void __koral_panic_overflow_mul(const char* loc) {
    __koral_panic_print("integer overflow in multiplication", loc);
}

void __koral_panic_overflow_div(const char* loc) {
    __koral_panic_print("integer overflow in division", loc);
}

void __koral_panic_overflow_mod(const char* loc) {
    __koral_panic_print("integer overflow in modulo", loc);
}

void __koral_panic_overflow_neg(const char* loc) {
    __koral_panic_print("integer overflow in negation", loc);
}

void __koral_panic_overflow_shift(const char* loc) {
    __koral_panic_print("integer overflow in shift", loc);
}

uint8_t* __koral_format_float64(double value, uint8_t type_char, intptr_t precision, int alt_form) {
    // Grown on demand: a fixed-notation rendering of 1e308 needs ~320 integer
    // digits, and the caller may request any precision. snprintf is correctly
    // rounded for %f/%e/%g, which is the conversion contract this helper
    // exists to provide. The buffer is thread-local scratch; the Koral side
    // copies the result out immediately.
    static _Thread_local char* out_buf = NULL;
    static _Thread_local size_t out_cap = 0;
    static _Thread_local char fmt_buf[32];

    if (precision < 0) precision = 0;

    char tc = (char)type_char;
    if (tc != 'f' && tc != 'F' && tc != 'e' && tc != 'E' && tc != 'g' && tc != 'G') {
        tc = 'g';
    }

    if (alt_form) {
        snprintf(fmt_buf, sizeof(fmt_buf), "%%#.%d%c", (int)precision, tc);
    } else {
        snprintf(fmt_buf, sizeof(fmt_buf), "%%.%d%c", (int)precision, tc);
    }

    size_t need = (size_t)precision + 400;
    if (need + 1 > out_cap) {
        char* grown = (char*)realloc(out_buf, need + 1);
        if (!grown) {
            // Out of memory: keep the old buffer and let snprintf truncate
            // rather than crash the formatter.
            if (!out_buf) return (uint8_t*)"";
        } else {
            out_buf = grown;
            out_cap = need + 1;
        }
    }
    snprintf(out_buf, out_cap, fmt_buf, value);
    return (uint8_t*)out_buf;
}

// Correctly-rounded decimal -> double. The Koral side has already validated
// the syntax; strtod supplies the rounding (Clinger's algorithm in libc) that
// hand-rolled digit accumulation gets wrong. Strings are NUL-terminated.
double __koral_parse_float64(const uint8_t* cstr) {
    return strtod((const char*)cstr, NULL);
}

// Define Koral-side timespec layout (must match generated struct in C output)
struct KoralTimespec {
    int64_t tv_sec;
    int64_t tv_nsec;
};

#if defined(_WIN32) || defined(_WIN64)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <direct.h>
#include <io.h>
#include <fcntl.h>
#include <share.h>
#include <sys/stat.h>
#include <wchar.h>

int __koral_nanosleep(struct KoralTimespec *req, struct KoralTimespec *rem) {
    if (!req) return -1;
    // Convert to milliseconds (truncate nanoseconds)
    int64_t ms = req->tv_sec * 1000 + req->tv_nsec / 1000000;
    if (ms <= 0) return 0;
    Sleep((DWORD)ms);
    if (rem) {
        rem->tv_sec = 0;
        rem->tv_nsec = 0;
    }
    return 0;
}

#else
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>

int __koral_nanosleep(struct KoralTimespec *req, struct KoralTimespec *rem) {
    if (!req) { errno = EINVAL; return -1; }
    struct timespec r;
    r.tv_sec = (time_t)req->tv_sec;
    r.tv_nsec = (long)req->tv_nsec;
    struct timespec rem_ts;
    int res = nanosleep(&r, rem ? &rem_ts : NULL);
    if (rem && res == -1 && errno == EINTR) {
        // Convert remaining time back to Koral Timespec
        rem->tv_sec = (int64_t)rem_ts.tv_sec;
        rem->tv_nsec = (int64_t)rem_ts.tv_nsec;
    } else if (rem) {
        rem->tv_sec = 0;
        rem->tv_nsec = 0;
    }
    return res;
}

#endif

// ============================================================================
// Path helpers
// ============================================================================

// Translate to the separator the OS wants. Called at every syscall boundary;
// userland keeps the canonical '/' form (see __koral_normalize_path).
static void normalize_path_internal(const char* src, char* dst, size_t size) {
    size_t i = 0;
    while (src[i] && i < size - 1) {
#ifdef _WIN32
        dst[i] = (src[i] == '/') ? '\\' : src[i];
#else
        dst[i] = (src[i] == '\\') ? '/' : src[i];
#endif
        i++;
    }
    dst[i] = '\0';
}

#ifdef _WIN32
// The Win32 side of `last_error_message()`: a failing Win32 call records its
// code HERE, before any later Win32 call can clobber the thread's last-error
// slot; `__koral_last_error_text` (error-helpers section) renders it as text.
static _Thread_local DWORD s_win32_last_error = 0;

static void __koral_win_record_error(DWORD code) {
    if (code != 0) s_win32_last_error = code;
}

// Koral strings are UTF-8; the ANSI Win32/CRT entry points interpret bytes in
// the system codepage, so any non-ASCII path (CJK user profile, CJK project
// name) silently resolves to the wrong file. Every path-bearing call below goes
// through these and then uses the W-suffixed API. Callers free the result.
static wchar_t* __koral_utf8_to_wide(const char* s) {
    if (!s) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (n <= 0) {
        __koral_win_record_error(GetLastError());
        return NULL;
    }
    wchar_t* w = (wchar_t*)malloc((size_t)n * sizeof(wchar_t));
    if (!w) return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n) <= 0) {
        __koral_win_record_error(GetLastError());
        free(w);
        return NULL;
    }
    return w;
}

static char* __koral_wide_to_utf8(const wchar_t* w) {
    if (!w) return NULL;
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (n <= 0) {
        __koral_win_record_error(GetLastError());
        return NULL;
    }
    char* s = (char*)malloc((size_t)n);
    if (!s) return NULL;
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL) <= 0) {
        __koral_win_record_error(GetLastError());
        free(s);
        return NULL;
    }
    return s;
}
#endif

// Canonicalize a path in userland: unify separators to '/' and resolve "."
// and ".." components. The result is what Path.normalize() hands back, and it
// is the form every string comparison in the compilers may rely on -- which is
// why this deliberately does NOT flip to the platform separator.
//
// The result never grows: '.' and '..' only ever remove bytes, and separator
// unification is 1:1. Callers size the buffer to strlen(path) + 1.
int __koral_normalize_path(const char* path, char* buf, size_t size) {
    if (!path || !buf || size == 0) return 0;

    size_t len = strlen(path);
    if (len + 1 > size) len = size - 1;

    // Unify separators to '/'.
    for (size_t i = 0; i < len; i++) {
        buf[i] = (path[i] == '\\') ? '/' : path[i];
    }
    buf[len] = '\0';

    // Root prefix, kept verbatim: "C:/" or "/" / "//" (UNC). The drive form
    // must match Path.is_absolute exactly -- an ASCII letter before ':' AND a
    // separator after it -- otherwise "a:b/../x" normalizes as if "a:" were a
    // drive root and comes out "a:/x" instead of "x".
    int drive_letter = (buf[0] >= 'A' && buf[0] <= 'Z') || (buf[0] >= 'a' && buf[0] <= 'z');
    size_t root = 0;
    if (len >= 3 && buf[1] == ':' && buf[2] == '/' && drive_letter) {
        root = 3;
    } else if (len >= 1 && buf[0] == '/') {
        root = (len >= 2 && buf[1] == '/') ? 2 : 1;
    }

    // Rewrite components after the root in place. `out` is the end of the last
    // component kept so far (or of the root); it never runs ahead of the read
    // cursor because the output is never longer than the input.
    //
    // `regular` counts real components written above the root. A ".." pops one
    // of those; when there are none left, a relative path keeps the ".."
    // (there is nothing above it to cancel) and an absolute one drops it.
    size_t out = root;
    size_t i = root;
    size_t regular = 0;

    while (i < len) {
        while (i < len && buf[i] == '/') i++;
        if (i >= len) break;

        size_t cs = i;
        while (i < len && buf[i] != '/') i++;
        size_t cl = i - cs;

        if (cl == 1 && buf[cs] == '.') {
            continue;
        }

        if (cl == 2 && buf[cs] == '.' && buf[cs + 1] == '.') {
            if (regular > 0) {
                // Remove the last regular component. `out` ends up just past
                // the component before it, with its trailing separator dropped.
                size_t j = out - 1;
                while (j > root && buf[j] != '/') j--;
                out = (buf[j] == '/') ? j : root;
                regular--;
            } else if (root == 0) {
                // Relative path with nothing above: keep the "..".
                if (out > 0 && buf[out - 1] != '/') {
                    if (out + 1 < size) buf[out++] = '/';
                }
                if (out + 2 < size) {
                    buf[out++] = '.';
                    buf[out++] = '.';
                }
            }
            // Absolute path with nothing above: ".." cancels against the root,
            // so it is dropped.
            continue;
        }

        // Append a separator before the component unless we sit right after a
        // root that already ends in '/' (or this is the first thing written).
        if (out > 0 && buf[out - 1] != '/') {
            if (out + 1 < size) buf[out++] = '/';
        }
        if (out + cl < size) {
            memmove(buf + out, buf + cs, cl);
            out += cl;
        }
        regular++;
    }

    // Trailing separator on a non-root path is dropped ("a/b/" -> "a/b").
    while (out > root && out > 1 && buf[out - 1] == '/') out--;

    buf[out] = '\0';
    return (int)out;
}

char __koral_path_separator(void) {
#ifdef _WIN32
    return '\\';
#else
    return '/';
#endif
}

// The host os atom ('w'indows / 'l'inux / 'm'acos, 0 otherwise) -- the same
// closed vocabulary the `#if os("...")` conditions and the manifest `platform`
// overlays use (cffi-design.md §D/§E). One vocabulary, one resolver.
uint8_t __koral_host_os(void) {
#if defined(_WIN32) || defined(_WIN64)
    return 'w';
#elif defined(__APPLE__)
    return 'm';
#elif defined(__linux__)
    return 'l';
#else
    return 0;
#endif
}

// The host arch atom ('x'86_64 / 'a'arch64, 0 otherwise) -- what
// `#if arch("...")` conditions select against (cffi-design.md §D).
uint8_t __koral_host_arch(void) {
#if defined(__x86_64__) || defined(_M_X64)
    return 'x';
#elif defined(__aarch64__) || defined(_M_ARM64)
    return 'a';
#else
    return 0;
#endif
}

char __koral_path_list_separator(void) {
#ifdef _WIN32
    return ';';
#else
    return ':';
#endif
}

int __koral_path_exists(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    wchar_t* wpath = __koral_utf8_to_wide(normalized);
    if (!wpath) return 0;
    struct _stat st;
    int rc = _wstat(wpath, &st);
    free(wpath);
    return rc == 0 ? 1 : 0;
#else
    struct stat st;
    return stat(normalized, &st) == 0 ? 1 : 0;
#endif
}

// ============================================================================
// Directory helpers
// ============================================================================

#ifdef _WIN32
struct CDirHandle {
    HANDLE handle;
    WIN32_FIND_DATAW data;
    bool first;
};

struct CDirEntry {
    // UTF-8, converted from the wide name the OS reports. MAX_PATH wide
    // characters can expand to 3x that in UTF-8.
    char name[MAX_PATH * 3];
    DWORD attributes;
};
#else
struct CDirHandle {
    DIR* dir;
};

struct CDirEntry {
    struct dirent entry;
};
#endif

typedef struct CDirHandle CDirHandle;
typedef struct CDirEntry CDirEntry;

CDirHandle* __koral_opendir(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    CDirHandle* dir = (CDirHandle*)malloc(sizeof(CDirHandle));
    if (!dir) return NULL;

    wchar_t* wnormalized = __koral_utf8_to_wide(normalized);
    if (!wnormalized) {
        free(dir);
        return NULL;
    }

    wchar_t pattern[4096 + 3];
    _snwprintf_s(pattern, _countof(pattern), _TRUNCATE, L"%s\\*", wnormalized);
    free(wnormalized);

    dir->handle = FindFirstFileW(pattern, &dir->data);
    if (dir->handle == INVALID_HANDLE_VALUE) {
        free(dir);
        return NULL;
    }
    dir->first = true;
    return dir;
#else
    DIR* raw = opendir(normalized);
    if (!raw) return NULL;
    CDirHandle* dir = (CDirHandle*)malloc(sizeof(CDirHandle));
    if (!dir) {
        closedir(raw);
        return NULL;
    }
    dir->dir = raw;
    return dir;
#endif
}

// Fill a CDirEntry's UTF-8 name from the wide name the OS reported.
#ifdef _WIN32
static void __koral_fill_entry_name(CDirEntry* entry, const WIN32_FIND_DATAW* data) {
    char* utf8 = __koral_wide_to_utf8(data->cFileName);
    if (utf8) {
        strncpy(entry->name, utf8, sizeof(entry->name) - 1);
        entry->name[sizeof(entry->name) - 1] = '\0';
        free(utf8);
    } else {
        entry->name[0] = '\0';
    }
    entry->attributes = data->dwFileAttributes;
}
#endif

CDirEntry* __koral_readdir(CDirHandle* dir) {
#ifdef _WIN32
    static CDirEntry entry;
    if (dir->first) {
        dir->first = false;
        __koral_fill_entry_name(&entry, &dir->data);
        return &entry;
    }
    if (FindNextFileW(dir->handle, &dir->data)) {
        __koral_fill_entry_name(&entry, &dir->data);
        return &entry;
    }
    return NULL;
#else
    static CDirEntry entry;
    struct dirent* e = readdir(dir->dir);
    if (!e) return NULL;
    memcpy(&entry.entry, e, sizeof(struct dirent));
    return &entry;
#endif
}

int __koral_closedir(CDirHandle* dir) {
#ifdef _WIN32
    FindClose(dir->handle);
    free(dir);
    return 0;
#else
    int res = closedir(dir->dir);
    free(dir);
    return res;
#endif
}

const char* __koral_dirent_name(CDirEntry* entry) {
#ifdef _WIN32
    return entry->name;
#else
    return entry->entry.d_name;
#endif
}

int __koral_mkdir(const char* path, unsigned int mode) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    (void)mode;
    wchar_t* wpath = __koral_utf8_to_wide(normalized);
    if (!wpath) return -1;
    int rc = _wmkdir(wpath);
    free(wpath);
    return rc;
#else
    return mkdir(normalized, mode);
#endif
}

int __koral_rmdir(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    wchar_t* wpath = __koral_utf8_to_wide(normalized);
    if (!wpath) return -1;
    int rc = _wrmdir(wpath);
    free(wpath);
    return rc;
#else
    return rmdir(normalized);
#endif
}

char* __koral_getcwd(char* buf, size_t size) {
#ifdef _WIN32
    // _wgetcwd reports the platform spelling in UTF-16; hand back UTF-8 so the
    // rest of the runtime sees the same encoding as every other path.
    wchar_t wbuf[4096];
    if (!_wgetcwd(wbuf, (int)(sizeof(wbuf) / sizeof(wbuf[0])))) return NULL;
    char* utf8 = __koral_wide_to_utf8(wbuf);
    if (!utf8) return NULL;
    size_t n = strlen(utf8);
    if (n + 1 > size) {
        free(utf8);
        return NULL;
    }
    memcpy(buf, utf8, n + 1);
    free(utf8);
    return buf;
#else
    return getcwd(buf, size);
#endif
}

// ============================================================================
// Environment helpers
// ============================================================================

int __koral_setenv(const char* name, const char* value) {
#ifdef _WIN32
    return _putenv_s(name, value);
#else
    return setenv(name, value, 1);
#endif
}

// ============================================================================
// Error helpers
// ============================================================================

int* __koral_errno_ptr(void) {
#ifdef _WIN32
    return _errno();
#else
    return &errno;
#endif
}

const char* __koral_strerror(int errnum) {
    return strerror(errnum);
}

// The `last_error_message()` surface. Windows: prefer the recorded Win32 error
// rendered as text (the spawn/fs paths record it at the failing call); fall
// back to `strerror(errno)` for CRT failures. POSIX: errno is the only source.
// The record is one-shot -- after a read it clears, so a later read cannot
// repeat a stale Win32 story over a fresh errno.
#ifdef _WIN32
const uint8_t* __koral_last_error_text(void) {
    if (s_win32_last_error != 0) {
        DWORD code = s_win32_last_error;
        s_win32_last_error = 0;
        static _Thread_local char text[512];
        wchar_t wtext[256];
        DWORD n = FormatMessageW(
            FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            NULL, code, 0, wtext, (DWORD)(sizeof(wtext) / sizeof(wtext[0])), NULL);
        while (n > 0 && (wtext[n - 1] == L'\r' || wtext[n - 1] == L'\n')) {
            wtext[--n] = L'\0';
        }
        if (n > 0) {
            WideCharToMultiByte(CP_UTF8, 0, wtext, -1, text, (int)sizeof(text), NULL, NULL);
            text[sizeof(text) - 1] = '\0';
            return (const uint8_t*)text;
        }
    }
    return (const uint8_t*)strerror(errno);
}
#else
const uint8_t* __koral_last_error_text(void) {
    return (const uint8_t*)strerror(errno);
}
#endif

// ============================================================================
// Float bit conversions
// ============================================================================

uint32_t __koral_float32_to_bits(float value) {
    uint32_t bits = 0;
    memcpy(&bits, &value, sizeof(uint32_t));
    return bits;
}

float __koral_float32_from_bits(uint32_t bits) {
    float value = 0.0f;
    memcpy(&value, &bits, sizeof(uint32_t));
    return value;
}

uint64_t __koral_float64_to_bits(double value) {
    uint64_t bits = 0;
    memcpy(&bits, &value, sizeof(uint64_t));
    return bits;
}

double __koral_float64_from_bits(uint64_t bits) {
    double value = 0.0;
    memcpy(&value, &bits, sizeof(uint64_t));
    return value;
}

// ============================================================================
// File helpers (stdlib wrappers)
// ============================================================================

int32_t __koral_remove(const uint8_t* path) {
    return (int32_t)remove((const char*)path);
}

int32_t __koral_rename(const uint8_t* old_path, const uint8_t* new_path) {
    return (int32_t)rename((const char*)old_path, (const char*)new_path);
}

uint8_t* __koral_getenv(const uint8_t* name) {
    return (uint8_t*)getenv((const char*)name);
}

int32_t __koral_system(const uint8_t* command) {
    return (int32_t)system((const char*)command);
}

// ============================================================================
// Time helpers
// ============================================================================

void __koral_monotonic_now(int64_t* out_secs, int64_t* out_nanos) {
#if defined(_WIN32) || defined(_WIN64)
    LARGE_INTEGER freq, counter;
    if (QueryPerformanceFrequency(&freq) && QueryPerformanceCounter(&counter) && freq.QuadPart > 0) {
        *out_secs = counter.QuadPart / freq.QuadPart;
        *out_nanos = (int64_t)((counter.QuadPart % freq.QuadPart) * 1000000000LL / freq.QuadPart);
    } else {
        *out_secs = 0;
        *out_nanos = 0;
    }
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
        *out_secs = (int64_t)ts.tv_sec;
        *out_nanos = (int64_t)ts.tv_nsec;
    } else {
        *out_secs = 0;
        *out_nanos = 0;
    }
#endif
}

void __koral_wallclock_now(int64_t* out_secs, int64_t* out_nanos) {
#if defined(_WIN32) || defined(_WIN64)
    // Windows FILETIME epoch: 1601-01-01, Unix epoch: 1970-01-01
    // Difference: 11644473600 seconds = 116444736000000000 * 100ns
    static const int64_t EPOCH_DIFF = 116444736000000000LL;
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    int64_t ticks = ((int64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    ticks -= EPOCH_DIFF;
    *out_secs = ticks / 10000000LL;
    *out_nanos = (ticks % 10000000LL) * 100LL;
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
        *out_secs = (int64_t)ts.tv_sec;
        *out_nanos = (int64_t)ts.tv_nsec;
    } else {
        *out_secs = 0;
        *out_nanos = 0;
    }
#endif
}

void __koral_local_timezone_offset(int32_t* out_offset_secs) {
#if defined(_WIN32) || defined(_WIN64)
    TIME_ZONE_INFORMATION tzi;
    DWORD result = GetTimeZoneInformation(&tzi);
    if (result == TIME_ZONE_ID_INVALID) {
        *out_offset_secs = 0;
    } else {
        // Bias is in minutes, west-positive. We want east-positive seconds.
        int32_t bias = (int32_t)tzi.Bias;
        if (result == TIME_ZONE_ID_DAYLIGHT) {
            bias += (int32_t)tzi.DaylightBias;
        } else if (result == TIME_ZONE_ID_STANDARD) {
            bias += (int32_t)tzi.StandardBias;
        }
        *out_offset_secs = -bias * 60;
    }
#else
    time_t now = time(NULL);
    struct tm local;
    if (localtime_r(&now, &local) != NULL) {
        *out_offset_secs = (int32_t)local.tm_gmtoff;
    } else {
        *out_offset_secs = 0;
    }
#endif
}

int32_t __koral_local_timezone_name(char* buf, int32_t buf_size) {
    if (buf_size <= 0) return 0;
    buf[0] = '\0';

#if defined(_WIN32) || defined(_WIN64)
    TIME_ZONE_INFORMATION tzi;
    DWORD result = GetTimeZoneInformation(&tzi);
    if (result != TIME_ZONE_ID_INVALID) {
        // Convert wide string to narrow (ASCII subset)
        const WCHAR* src = (result == TIME_ZONE_ID_DAYLIGHT) ? tzi.DaylightName : tzi.StandardName;
        int i = 0;
        while (src[i] && i < buf_size - 1) {
            buf[i] = (char)(src[i] & 0x7F);
            i++;
        }
        buf[i] = '\0';
        return i;
    }
    return 0;
#else
    // Priority 1: $TZ environment variable
    const char* tz_env = getenv("TZ");
    if (tz_env && tz_env[0] != '\0') {
        // Skip leading ':' if present (POSIX convention)
        const char* name = tz_env;
        if (name[0] == ':') name++;
        // Check if it looks like an IANA name (contains '/')
        if (strchr(name, '/') != NULL) {
            int len = (int)strlen(name);
            if (len >= buf_size) len = buf_size - 1;
            memcpy(buf, name, len);
            buf[len] = '\0';
            return len;
        }
    }

    // Priority 2: readlink("/etc/localtime")
    char link_buf[256];
    ssize_t link_len = readlink("/etc/localtime", link_buf, sizeof(link_buf) - 1);
    if (link_len > 0) {
        link_buf[link_len] = '\0';
        // Look for "zoneinfo/" in the path
        const char* marker = strstr(link_buf, "zoneinfo/");
        if (marker) {
            const char* iana_name = marker + 9; // strlen("zoneinfo/") == 9
            int len = (int)strlen(iana_name);
            if (len >= buf_size) len = buf_size - 1;
            memcpy(buf, iana_name, len);
            buf[len] = '\0';
            return len;
        }
    }

    return 0;
#endif
}

// ============================================================================
// TZif parser (thread-safe, no global state modification)
// ============================================================================

#if !defined(_WIN32) && !defined(_WIN64)

// Zoneinfo search paths (same order as Go stdlib)
static const char* __koral_zoneinfo_dirs[] = {
    "/usr/share/zoneinfo/",
    "/usr/share/lib/zoneinfo/",
    "/usr/lib/locale/TZ/",
    "/etc/zoneinfo/",
    NULL
};

// Read a big-endian int32 from buffer
static int32_t tzif_read_be32(const uint8_t* p) {
    return (int32_t)(((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
                     ((uint32_t)p[2] << 8) | (uint32_t)p[3]);
}

// Read a big-endian int64 from buffer
static int64_t tzif_read_be64(const uint8_t* p) {
    return (int64_t)(((uint64_t)p[0] << 56) | ((uint64_t)p[1] << 48) |
                     ((uint64_t)p[2] << 40) | ((uint64_t)p[3] << 32) |
                     ((uint64_t)p[4] << 24) | ((uint64_t)p[5] << 16) |
                     ((uint64_t)p[6] << 8) | (uint64_t)p[7]);
}

// Query UTC offset at a given unix_secs from a TZif file.
// Returns 1 on success, 0 on failure.
static int tzif_query_offset(const char* filepath, int64_t unix_secs, int32_t* out_offset) {
    FILE* f = fopen(filepath, "rb");
    if (!f) return 0;

    // Read entire file (TZif files are typically < 4KB)
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    if (file_size <= 0 || file_size > 128 * 1024) { fclose(f); return 0; }
    fseek(f, 0, SEEK_SET);

    uint8_t* data = (uint8_t*)malloc((size_t)file_size);
    if (!data) { fclose(f); return 0; }
    if ((long)fread(data, 1, (size_t)file_size, f) != file_size) {
        free(data); fclose(f); return 0;
    }
    fclose(f);

    // Validate TZif magic "TZif"
    if (file_size < 44 || memcmp(data, "TZif", 4) != 0) {
        free(data); return 0;
    }

    // Read v1 header to skip v1 data block
    char version = (char)data[4]; // '2', '3', or '\0'
    int32_t v1_isutcnt  = tzif_read_be32(data + 20);
    int32_t v1_isstdcnt = tzif_read_be32(data + 24);
    int32_t v1_leapcnt  = tzif_read_be32(data + 28);
    int32_t v1_timecnt  = tzif_read_be32(data + 32);
    int32_t v1_typecnt  = tzif_read_be32(data + 36);
    int32_t v1_charcnt  = tzif_read_be32(data + 40);

    // v1 data block size: timecnt*4 + timecnt*1 + typecnt*6 + charcnt + leapcnt*8 + isstdcnt + isutcnt
    long v1_datasize = (long)v1_timecnt * 4 + (long)v1_timecnt +
                       (long)v1_typecnt * 6 + (long)v1_charcnt +
                       (long)v1_leapcnt * 8 + (long)v1_isstdcnt + (long)v1_isutcnt;

    // If v2 or v3, skip v1 and parse v2/v3 header
    if (version == '2' || version == '3') {
        long v2_header_offset = 44 + v1_datasize;
        if (v2_header_offset + 44 > file_size) { free(data); return 0; }

        // Validate v2 magic
        if (memcmp(data + v2_header_offset, "TZif", 4) != 0) { free(data); return 0; }

        int32_t v2_leapcnt  = tzif_read_be32(data + v2_header_offset + 28);
        int32_t v2_timecnt  = tzif_read_be32(data + v2_header_offset + 32);
        int32_t v2_typecnt  = tzif_read_be32(data + v2_header_offset + 36);
        int32_t v2_charcnt  = tzif_read_be32(data + v2_header_offset + 40);

        long v2_data_start = v2_header_offset + 44;

        // transition times: v2_timecnt * 8 bytes (int64)
        const uint8_t* trans_times = data + v2_data_start;
        // transition type indices: v2_timecnt * 1 byte
        const uint8_t* trans_types = trans_times + v2_timecnt * 8;
        // ttinfo structs: v2_typecnt * 6 bytes each (int32 utoff, uint8 dst, uint8 idx)
        const uint8_t* ttinfos = trans_types + v2_timecnt;

        // Bounds check
        long needed = v2_data_start + (long)v2_timecnt * 8 + (long)v2_timecnt +
                      (long)v2_typecnt * 6 + (long)v2_charcnt +
                      (long)v2_leapcnt * 12;
        if (needed > file_size) { free(data); return 0; }

        // Binary search for the transition
        int32_t lo = 0, hi = v2_timecnt;
        while (lo < hi) {
            int32_t mid = lo + (hi - lo) / 2;
            int64_t t = tzif_read_be64(trans_times + mid * 8);
            if (t <= unix_secs) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        uint8_t type_idx;
        if (lo == 0) {
            // Before all transitions: use first non-DST type, or type 0
            type_idx = 0;
            for (int32_t i = 0; i < v2_typecnt; i++) {
                if (ttinfos[i * 6 + 4] == 0) { // is_dst == 0
                    type_idx = (uint8_t)i;
                    break;
                }
            }
        } else {
            type_idx = trans_types[lo - 1];
        }

        if (type_idx >= (uint8_t)v2_typecnt) { free(data); return 0; }
        *out_offset = tzif_read_be32(ttinfos + type_idx * 6);
        free(data);
        return 1;
    }

    // v1 fallback: use 32-bit transition times
    {
        long v1_data_start = 44;
        const uint8_t* trans_times = data + v1_data_start;
        const uint8_t* trans_types = trans_times + v1_timecnt * 4;
        const uint8_t* ttinfos = trans_types + v1_timecnt;

        long needed = v1_data_start + (long)v1_timecnt * 4 + (long)v1_timecnt +
                      (long)v1_typecnt * 6 + (long)v1_charcnt;
        if (needed > file_size) { free(data); return 0; }

        int32_t lo = 0, hi = v1_timecnt;
        while (lo < hi) {
            int32_t mid = lo + (hi - lo) / 2;
            int64_t t = (int64_t)tzif_read_be32(trans_times + mid * 4);
            if (t <= unix_secs) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }

        uint8_t type_idx;
        if (lo == 0) {
            type_idx = 0;
            for (int32_t i = 0; i < v1_typecnt; i++) {
                if (ttinfos[i * 6 + 4] == 0) {
                    type_idx = (uint8_t)i;
                    break;
                }
            }
        } else {
            type_idx = trans_types[lo - 1];
        }

        if (type_idx >= (uint8_t)v1_typecnt) { free(data); return 0; }
        *out_offset = tzif_read_be32(ttinfos + type_idx * 6);
        free(data);
        return 1;
    }
}

// Build full path to zoneinfo file. Returns 1 if found, 0 if not.
static int tzif_find_file(const char* name, char* path_buf, size_t path_buf_size) {
    for (int i = 0; __koral_zoneinfo_dirs[i] != NULL; i++) {
        int n = snprintf(path_buf, path_buf_size, "%s%s", __koral_zoneinfo_dirs[i], name);
        if (n > 0 && (size_t)n < path_buf_size) {
            struct stat st;
            if (stat(path_buf, &st) == 0 && S_ISREG(st.st_mode)) {
                return 1;
            }
        }
    }
    return 0;
}

#endif // !_WIN32

#if defined(_WIN32) || defined(_WIN64)

// Windows named-timezone support rides the ICU that ships with Windows 10
// (icu.dll), loaded dynamically -- no SDK header, no import library, and a
// machine without it degrades to "unknown timezone" exactly like the
// zoneinfo-less state it replaces. ucal_open takes an IANA id, ucal_setMillis
// positions the calendar at a UTC instant, and ucal_get reports the zone and
// DST offsets that apply there (both in milliseconds).
typedef void* KoralUCalendar;
typedef int32_t KoralUError;
typedef KoralUCalendar (__cdecl *KoralUCalOpenFn)(const wchar_t*, int32_t, const char*, int, KoralUError*);
typedef void (__cdecl *KoralUCalCloseFn)(KoralUCalendar);
typedef void (__cdecl *KoralUCalSetMillisFn)(KoralUCalendar, double, KoralUError*);
typedef int32_t (__cdecl *KoralUCalGetFn)(KoralUCalendar, int, KoralUError*);
typedef int32_t (__cdecl *KoralUCalGetTzIdFn)(KoralUCalendar, wchar_t*, int32_t, KoralUError*);

typedef struct {
    KoralUCalOpenFn open;
    KoralUCalCloseFn close;
    KoralUCalSetMillisFn set_millis;
    KoralUCalGetFn get;
    KoralUCalGetTzIdFn get_tzid;
    int attempted;
    int available;
} KoralIcuApi;

static KoralIcuApi g_koral_icu;

#define KORAL_UCAL_ZONE_OFFSET 15
#define KORAL_UCAL_DST_OFFSET 16

static int koral_icu_load(void) {
    if (g_koral_icu.attempted) return g_koral_icu.available;
    g_koral_icu.attempted = 1;
    HMODULE m = LoadLibraryW(L"icu.dll");
    if (!m) return 0;
    g_koral_icu.open = (KoralUCalOpenFn)(void*)GetProcAddress(m, "ucal_open");
    g_koral_icu.close = (KoralUCalCloseFn)(void*)GetProcAddress(m, "ucal_close");
    g_koral_icu.set_millis = (KoralUCalSetMillisFn)(void*)GetProcAddress(m, "ucal_setMillis");
    g_koral_icu.get = (KoralUCalGetFn)(void*)GetProcAddress(m, "ucal_get");
    g_koral_icu.get_tzid = (KoralUCalGetTzIdFn)(void*)GetProcAddress(m, "ucal_getTimeZoneID");
    g_koral_icu.available = g_koral_icu.open && g_koral_icu.close
        && g_koral_icu.set_millis && g_koral_icu.get && g_koral_icu.get_tzid;
    return g_koral_icu.available;
}

/// Open `name` as an IANA zone, or NULL when the name does not resolve.
/// ucal_open FALLS BACK to the default zone for an unknown ID without
/// reporting an error, so the calendar's own ID is what proves the name.
static KoralUCalendar koral_icu_open_zone(const char* name) {
    if (!koral_icu_load()) return NULL;
    wchar_t* wname = __koral_utf8_to_wide(name);
    if (!wname) return NULL;
    KoralUError st = 0;
    KoralUCalendar cal = g_koral_icu.open(wname, -1, NULL, 0 /* UCAL_DEFAULT */, &st);
    if (st != 0 || !cal) {
        free(wname);
        if (cal) g_koral_icu.close(cal);
        return NULL;
    }
    wchar_t id[128];
    KoralUError st2 = 0;
    int32_t len = g_koral_icu.get_tzid(cal, id, 128, &st2);
    int ok = (st2 == 0 && len == (int32_t)wcslen(wname) && wcsncmp(id, wname, (size_t)len) == 0);
    free(wname);
    if (!ok) {
        g_koral_icu.close(cal);
        return NULL;
    }
    return cal;
}

#endif // _WIN32 named timezone helpers

int32_t __koral_timezone_name_exists(const char* name) {
#if defined(_WIN32) || defined(_WIN64)
    if (!name || name[0] == '\0') return 0;
    KoralUCalendar cal = koral_icu_open_zone(name);
    if (!cal) return 0;
    g_koral_icu.close(cal);
    return 1;
#else
    if (!name || name[0] == '\0') return 0;
    char path[512];
    return tzif_find_file(name, path, sizeof(path)) ? 1 : 0;
#endif
}

void __koral_timezone_offset_at(const char* name, int64_t unix_secs, int32_t* out_offset_secs) {
#if defined(_WIN32) || defined(_WIN64)
    if (!name || name[0] == '\0') {
        // Empty name means the local timezone.
        __koral_local_timezone_offset(out_offset_secs);
        return;
    }
    KoralUCalendar cal = koral_icu_open_zone(name);
    if (!cal) {
        *out_offset_secs = 0;
        return;
    }
    KoralUError st = 0;
    g_koral_icu.set_millis(cal, (double)unix_secs * 1000.0, &st);
    int32_t zone_off = g_koral_icu.get(cal, KORAL_UCAL_ZONE_OFFSET, &st);
    int32_t dst_off = g_koral_icu.get(cal, KORAL_UCAL_DST_OFFSET, &st);
    g_koral_icu.close(cal);
    *out_offset_secs = (st == 0) ? (zone_off + dst_off) / 1000 : 0;
#else
    *out_offset_secs = 0;

    if (!name || name[0] == '\0') {
        // Empty name means local timezone — use /etc/localtime
        if (tzif_query_offset("/etc/localtime", unix_secs, out_offset_secs)) {
            return;
        }
        // Fallback to localtime_r for local timezone
        time_t t = (time_t)unix_secs;
        struct tm local;
        if (localtime_r(&t, &local) != NULL) {
            *out_offset_secs = (int32_t)local.tm_gmtoff;
        }
        return;
    }

    // Named timezone: find and parse TZif file
    char path[512];
    if (tzif_find_file(name, path, sizeof(path))) {
        tzif_query_offset(path, unix_secs, out_offset_secs);
    }
#endif
}

// ============================================================================
// Math wrapper functions (Float64 / double)
// ============================================================================
double __koral_f64_sqrt(double x) { return sqrt(x); }
double __koral_f64_cbrt(double x) { return cbrt(x); }
double __koral_f64_pow(double x, double y) { return pow(x, y); }
double __koral_f64_hypot(double x, double y) { return hypot(x, y); }
double __koral_f64_exp(double x) { return exp(x); }
double __koral_f64_exp2(double x) { return exp2(x); }
double __koral_f64_expm1(double x) { return expm1(x); }
double __koral_f64_log(double x) { return log(x); }
double __koral_f64_log2(double x) { return log2(x); }
double __koral_f64_log10(double x) { return log10(x); }
double __koral_f64_log1p(double x) { return log1p(x); }
double __koral_f64_sin(double x) { return sin(x); }
double __koral_f64_cos(double x) { return cos(x); }
double __koral_f64_tan(double x) { return tan(x); }
double __koral_f64_asin(double x) { return asin(x); }
double __koral_f64_acos(double x) { return acos(x); }
double __koral_f64_atan(double x) { return atan(x); }
double __koral_f64_atan2(double y, double x) { return atan2(y, x); }
double __koral_f64_sinh(double x) { return sinh(x); }
double __koral_f64_cosh(double x) { return cosh(x); }
double __koral_f64_tanh(double x) { return tanh(x); }
double __koral_f64_asinh(double x) { return asinh(x); }
double __koral_f64_acosh(double x) { return acosh(x); }
double __koral_f64_atanh(double x) { return atanh(x); }
double __koral_f64_floor(double x) { return floor(x); }
double __koral_f64_ceil(double x) { return ceil(x); }
double __koral_f64_round(double x) { return round(x); }
double __koral_f64_trunc(double x) { return trunc(x); }
double __koral_f64_fabs(double x) { return fabs(x); }
double __koral_f64_copysign(double x, double y) { return copysign(x, y); }
double __koral_f64_fmod(double x, double y) { return fmod(x, y); }
double __koral_f64_fma(double x, double y, double z) { return fma(x, y, z); }
double __koral_f64_erf(double x) { return erf(x); }
double __koral_f64_erfc(double x) { return erfc(x); }
double __koral_f64_tgamma(double x) { return tgamma(x); }
double __koral_f64_lgamma(double x) { return lgamma(x); }

// ============================================================================
// Math wrapper functions (Float32 / float)
// ============================================================================
float __koral_f32_sqrt(float x) { return sqrtf(x); }
float __koral_f32_cbrt(float x) { return cbrtf(x); }
float __koral_f32_pow(float x, float y) { return powf(x, y); }
float __koral_f32_hypot(float x, float y) { return hypotf(x, y); }
float __koral_f32_exp(float x) { return expf(x); }
float __koral_f32_exp2(float x) { return exp2f(x); }
float __koral_f32_expm1(float x) { return expm1f(x); }
float __koral_f32_log(float x) { return logf(x); }
float __koral_f32_log2(float x) { return log2f(x); }
float __koral_f32_log10(float x) { return log10f(x); }
float __koral_f32_log1p(float x) { return log1pf(x); }
float __koral_f32_sin(float x) { return sinf(x); }
float __koral_f32_cos(float x) { return cosf(x); }
float __koral_f32_tan(float x) { return tanf(x); }
float __koral_f32_asin(float x) { return asinf(x); }
float __koral_f32_acos(float x) { return acosf(x); }
float __koral_f32_atan(float x) { return atanf(x); }
float __koral_f32_atan2(float y, float x) { return atan2f(y, x); }
float __koral_f32_sinh(float x) { return sinhf(x); }
float __koral_f32_cosh(float x) { return coshf(x); }
float __koral_f32_tanh(float x) { return tanhf(x); }
float __koral_f32_asinh(float x) { return asinhf(x); }
float __koral_f32_acosh(float x) { return acoshf(x); }
float __koral_f32_atanh(float x) { return atanhf(x); }
float __koral_f32_floor(float x) { return floorf(x); }
float __koral_f32_ceil(float x) { return ceilf(x); }
float __koral_f32_round(float x) { return roundf(x); }
float __koral_f32_trunc(float x) { return truncf(x); }
float __koral_f32_fabs(float x) { return fabsf(x); }
float __koral_f32_copysign(float x, float y) { return copysignf(x, y); }
float __koral_f32_fmod(float x, float y) { return fmodf(x, y); }
float __koral_f32_fma(float x, float y, float z) { return fmaf(x, y, z); }
float __koral_f32_erf(float x) { return erff(x); }
float __koral_f32_erfc(float x) { return erfcf(x); }
float __koral_f32_tgamma(float x) { return tgammaf(x); }
float __koral_f32_lgamma(float x) { return lgammaf(x); }

// ============================================================================
// Random: system entropy source
// ============================================================================

#if defined(_WIN32) || defined(_WIN64)

#include <bcrypt.h>
// Link with bcrypt.lib (MSVC) or -lbcrypt (MinGW)

int32_t __koral_random_fill(uint8_t* buf, int32_t len) {
    if (!buf || len <= 0) return -1;
    NTSTATUS status = BCryptGenRandom(NULL, buf, (ULONG)len,
                                      BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    return (status >= 0) ? 0 : -1;
}

#elif defined(__APPLE__)

#include <stdlib.h>

int32_t __koral_random_fill(uint8_t* buf, int32_t len) {
    if (!buf || len <= 0) return -1;
    arc4random_buf(buf, (size_t)len);
    return 0;
}

#else
// Linux / other POSIX

#include <sys/types.h>
#include <fcntl.h>

// Try getrandom() first (Linux 3.17+), fall back to /dev/urandom
#if defined(__linux__)
#include <sys/syscall.h>
#endif

static int __koral_random_fill_urandom(uint8_t* buf, int32_t len) {
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return -1;
    int32_t remaining = len;
    while (remaining > 0) {
        ssize_t n = read(fd, buf + (len - remaining), (size_t)remaining);
        if (n <= 0) {
            close(fd);
            return -1;
        }
        remaining -= (int32_t)n;
    }
    close(fd);
    return 0;
}

int32_t __koral_random_fill(uint8_t* buf, int32_t len) {
    if (!buf || len <= 0) return -1;
#if defined(__linux__) && defined(SYS_getrandom)
    int32_t remaining = len;
    while (remaining > 0) {
        long ret = syscall(SYS_getrandom, buf + (len - remaining),
                           (size_t)remaining, 0);
        if (ret < 0) {
            if (errno == EINTR) continue;
            if (errno == ENOSYS) {
                // getrandom not available, fall back to /dev/urandom
                return __koral_random_fill_urandom(buf, len);
            }
            return -1;
        }
        remaining -= (int32_t)ret;
    }
    return 0;
#else
    return __koral_random_fill_urandom(buf, len);
#endif
}

#endif


// ============================================================================
// OS module: File metadata, permissions, links, locking
// ============================================================================

// KoralStatResult must match the foreign type declared in Koral
typedef struct {
    int64_t  size;
    int32_t  file_type;         // 0=regular, 1=directory, 2=symlink, 3=other
    uint32_t permissions;       // Unix permission bits (low 9 bits)
    int64_t  modified_secs;
    int64_t  modified_nanos;
    int64_t  accessed_secs;
    int64_t  accessed_nanos;
    int64_t  created_secs;
    int64_t  created_nanos;
} KoralStatResult;

#if defined(_WIN32) || defined(_WIN64)

// --- Windows implementations ---

static void __koral_fill_stat_result(struct _stat64* st, KoralStatResult* out) {
    out->size = (int64_t)st->st_size;
    if (st->st_mode & _S_IFREG)      out->file_type = 0;
    else if (st->st_mode & _S_IFDIR)  out->file_type = 1;
    else                               out->file_type = 3;
    out->permissions = (uint32_t)(st->st_mode & 0777);
    out->modified_secs = (int64_t)st->st_mtime;
    out->modified_nanos = 0;
    out->accessed_secs = (int64_t)st->st_atime;
    out->accessed_nanos = 0;
    out->created_secs = (int64_t)st->st_ctime;
    out->created_nanos = 0;
}

// --- POSIX-style path walking for the Windows file APIs -------------------
//
// The Win32 path layer flattens `..` against the WRITTEN path before anything
// opens -- and so does the NT namespace underneath it -- so `link/../target`
// misses the symlink's target directory instead of walking out through it.
// The walk below resolves `.` and `..` the POSIX way (and follows symlinks
// for every component that has a successor) before the path is handed on.
// Only paths that actually carry a `..` component pay for it.
//
// A symlink TARGET is a name stored verbatim in the link and never goes
// through here; and the FINAL component of a path is left for the OS to
// resolve, so removing a symlink root removes the link, never its target.

/// Read a reparse point's stored target into `out` (wide, NUL-terminated).
/// Returns the length in WCHARs, or -1. The PrintName is the spelling the
/// writer saw; a relative link may leave it empty, in which case the
/// substitute name is the link text.
static int koral_win_readlink_w(const wchar_t* wpath, wchar_t* out, int out_cap) {
    HANDLE h = CreateFileW(wpath, GENERIC_READ,
                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           NULL, OPEN_EXISTING,
                           FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE) return -1;
    unsigned char raw[16384 + 64];
    DWORD returned = 0;
    if (!DeviceIoControl(h, FSCTL_GET_REPARSE_POINT, NULL, 0, raw, sizeof(raw), &returned, NULL)) {
        CloseHandle(h);
        return -1;
    }
    CloseHandle(h);
    if (returned < 16) return -1;
    DWORD tag = *(DWORD*)raw;
    USHORT sub_off = *(USHORT*)(raw + 8);
    USHORT sub_len = *(USHORT*)(raw + 10);
    USHORT print_off = *(USHORT*)(raw + 12);
    USHORT print_len = *(USHORT*)(raw + 14);
    if (tag != IO_REPARSE_TAG_SYMLINK && tag != IO_REPARSE_TAG_MOUNT_POINT) return -1;
    unsigned char* names_base = raw + 8 + (tag == IO_REPARSE_TAG_SYMLINK ? 12 : 8);
    const WCHAR* name = NULL;
    int name_wchars = 0;
    if (print_len > 0) {
        name = (const WCHAR*)(names_base + print_off);
        name_wchars = print_len / sizeof(WCHAR);
    } else if (sub_len > 0) {
        name = (const WCHAR*)(names_base + sub_off);
        name_wchars = sub_len / sizeof(WCHAR);
    } else {
        return -1;
    }
    if (name_wchars >= out_cap) return -1;
    memcpy(out, name, name_wchars * sizeof(WCHAR));
    out[name_wchars] = L'\0';
    for (wchar_t* q = out; *q; q++) {
        if (*q == L'\\') *q = L'/';
    }
    return name_wchars;
}

/// The root of an absolute path: `X:\`, `\\server\share\`, or the `\\?\`
/// spellings of those. Returns its length in WCHARs, or 0 when unrecognised.
static size_t koral_win_path_root_len(const wchar_t* abs) {
    const wchar_t* p = abs;
    if (p[0] == L'\\' && p[1] == L'\\' && p[2] == L'?' && p[3] == L'\\') {
        if (p[4] == L'U' && p[5] == L'N' && p[6] == L'C' && p[7] == L'\\') p += 8;
        else p += 4;
    }
    if (p[0] && p[1] == L':') {
        return (size_t)(p - abs) + 3;
    }
    if (p[0] == L'\\' && p[1] == L'\\') {
        const wchar_t* q = p + 2;
        while (*q && *q != L'\\') q++;
        if (*q) q++;
        while (*q && *q != L'\\') q++;
        if (*q) q++;
        return (size_t)(q - abs);
    }
    return 0;
}

static wchar_t* koral_win_wcsdup(const wchar_t* s) {
    size_t n = wcslen(s);
    wchar_t* out = (wchar_t*)malloc((n + 1) * sizeof(wchar_t));
    if (out) memcpy(out, s, (n + 1) * sizeof(wchar_t));
    return out;
}

/// Join `root` and the component stack back into one path.
static wchar_t* koral_win_join_path(const wchar_t* root, wchar_t** comps, size_t n) {
    size_t total = wcslen(root) + 1;
    for (size_t i = 0; i < n; i++) total += wcslen(comps[i]) + 1;
    wchar_t* out = (wchar_t*)malloc(total * sizeof(wchar_t));
    if (!out) return NULL;
    size_t len = wcslen(root);
    memcpy(out, root, len * sizeof(wchar_t));
    for (size_t i = 0; i < n; i++) {
        if (len > 0 && out[len - 1] != L'\\') out[len++] = L'\\';
        size_t cl = wcslen(comps[i]);
        memcpy(out + len, comps[i], (cl + 1) * sizeof(wchar_t));
        len += cl;
    }
    return out;
}

static wchar_t* koral_win_resolve_dots_budget(const wchar_t* abs, int budget);

static wchar_t* koral_win_resolve_dots_budget(const wchar_t* abs, int budget) {
    size_t root_len = koral_win_path_root_len(abs);
    if (root_len == 0) return koral_win_wcsdup(abs);

    wchar_t* root = (wchar_t*)malloc((root_len + 1) * sizeof(wchar_t));
    if (!root) return koral_win_wcsdup(abs);
    memcpy(root, abs, root_len * sizeof(wchar_t));
    root[root_len] = L'\0';

    // The stack owns every component it holds; `..` frees the top.
    size_t cap = wcslen(abs) + 2;
    wchar_t** stack = (wchar_t**)malloc(cap * sizeof(wchar_t*));
    if (!stack) { free(root); return koral_win_wcsdup(abs); }
    size_t st = 0;

    const wchar_t* c = abs + root_len;
    while (*c) {
        while (*c == L'\\') c++;
        if (!*c) break;
        const wchar_t* s = c;
        while (*c && *c != L'\\') c++;
        size_t clen = (size_t)(c - s);
        if (clen == 1 && s[0] == L'.') continue;
        wchar_t* comp = (wchar_t*)malloc((clen + 1) * sizeof(wchar_t));
        if (!comp) break;
        memcpy(comp, s, clen * sizeof(wchar_t));
        comp[clen] = L'\0';

        if (clen == 2 && comp[0] == L'.' && comp[1] == L'.') {
            if (st > 0) free(stack[--st]);
            free(comp);
            continue;
        }

        // Follow a symlink for every component that has a successor: `..`
        // after one must move to the parent of the link's TARGET.
        int has_successor = (*c != L'\0');
        if (has_successor && budget > 0) {
            stack[st] = comp;  // temporarily, to build the candidate
            wchar_t* candidate = koral_win_join_path(root, stack, st + 1);
            wchar_t target[2048];
            int is_link = candidate && koral_win_readlink_w(candidate, target, 2048) > 0;
            wchar_t* resolved = NULL;
            if (is_link) {
                {
                    // (kept as a bare block: the body below was the success
                    // arm of the readlink test, which `is_link` now carries)
                    for (wchar_t* q = target; *q; q++) {
                        if (*q == L'/') *q = L'\\';
                    }
                    wchar_t* abs_target = NULL;
                    if ((target[0] && target[1] == L':')
                        || (target[0] == L'\\' && target[1] == L'\\')) {
                        abs_target = koral_win_wcsdup(target);
                    } else {
                        wchar_t* dir = koral_win_join_path(root, stack, st);
                        size_t dl = dir ? wcslen(dir) : 0;
                        size_t tl = wcslen(target);
                        abs_target = (wchar_t*)malloc((dl + 1 + tl + 1) * sizeof(wchar_t));
                        if (abs_target && dir) {
                            memcpy(abs_target, dir, dl * sizeof(wchar_t));
                            abs_target[dl] = L'\\';
                            memcpy(abs_target + dl + 1, target, (tl + 1) * sizeof(wchar_t));
                        } else if (abs_target) {
                            abs_target[0] = L'\0';
                        }
                        free(dir);
                    }
                    if (abs_target) {
                        resolved = koral_win_resolve_dots_budget(abs_target, budget - 1);
                        free(abs_target);
                    }
                }
            }
            free(candidate);
            if (resolved) {
                // Splice the resolved location in place of the link: the
                // stack and root become the resolved path's own.
                size_t rroot = koral_win_path_root_len(resolved);
                for (size_t i = 0; i <= st; i++) free(stack[i]);  // includes comp
                st = 0;
                free(root);
                root = (wchar_t*)malloc((rroot + 1) * sizeof(wchar_t));
                if (root) {
                    memcpy(root, resolved, rroot * sizeof(wchar_t));
                    root[rroot] = L'\0';
                } else {
                    root = koral_win_wcsdup(L"");
                }
                const wchar_t* rc = resolved + rroot;
                while (*rc && st < cap) {
                    while (*rc == L'\\') rc++;
                    if (!*rc) break;
                    const wchar_t* rs = rc;
                    while (*rc && *rc != L'\\') rc++;
                    size_t rl = (size_t)(rc - rs);
                    wchar_t* rp = (wchar_t*)malloc((rl + 1) * sizeof(wchar_t));
                    if (!rp) break;
                    memcpy(rp, rs, rl * sizeof(wchar_t));
                    rp[rl] = L'\0';
                    stack[st++] = rp;
                }
                free(resolved);
                continue;
            }
        }
        stack[st++] = comp;
    }

    wchar_t* out = koral_win_join_path(root, stack, st);
    for (size_t i = 0; i < st; i++) free(stack[i]);
    free(stack);
    free(root);
    return out ? out : koral_win_wcsdup(abs);
}

static wchar_t* koral_win_resolve_dots(const wchar_t* abs) {
    return koral_win_resolve_dots_budget(abs, 40);
}

/// Route a filesystem path through the `\\?\` namespace UNNORMALIZED, with
/// `.`/`..` resolved POSIX-style first by the walk above. Forward slashes
/// become backslashes (the prefix takes them literally) and a relative path
/// is anchored at the current directory.
static wchar_t* __koral_win_widen_path(const char* path) {
    if (!path) return NULL;
    wchar_t* wpath = __koral_utf8_to_wide(path);
    if (!wpath) return NULL;
    for (wchar_t* p = wpath; *p; p++) {
        if (*p == L'/') *p = L'\\';
    }
    if (wpath[0] == L'\\' && wpath[1] == L'\\' && wpath[2] == L'?' && wpath[3] == L'\\') {
        return wpath;  // already namespaced
    }
    int rooted = (wpath[0] == L'\\' && wpath[1] == L'\\');
    int drive_abs = (wpath[1] == L':' && (wpath[2] == L'\\' || wpath[2] == L'\0'));
    wchar_t* joined = wpath;
    if (!(rooted || drive_abs)) {
        DWORD need = GetCurrentDirectoryW(0, NULL);
        if (need == 0) { free(wpath); return NULL; }
        wchar_t* cwd = (wchar_t*)malloc(need * sizeof(wchar_t));
        if (!cwd) { free(wpath); return NULL; }
        DWORD got = GetCurrentDirectoryW(need, cwd);
        if (got == 0 || got >= need) { free(cwd); free(wpath); return NULL; }
        size_t cl = wcslen(cwd), wl = wcslen(wpath);
        joined = (wchar_t*)malloc((cl + 1 + wl + 1) * sizeof(wchar_t));
        if (!joined) { free(cwd); free(wpath); return NULL; }
        memcpy(joined, cwd, cl * sizeof(wchar_t));
        joined[cl] = L'\\';
        memcpy(joined + cl + 1, wpath, (wl + 1) * sizeof(wchar_t));
        free(cwd);
        free(wpath);
    }
    // `..` needs the POSIX walk; a path without it passes straight through.
    {
        int has_dots = 0;
        const wchar_t* q = joined;
        while (*q) {
            while (*q == L'\\') q++;
            const wchar_t* cs = q;
            while (*q && *q != L'\\') q++;
            if ((size_t)(q - cs) == 2 && cs[0] == L'.' && cs[1] == L'.') {
                has_dots = 1;
                break;
            }
        }
        if (has_dots) {
            wchar_t* resolved = koral_win_resolve_dots(joined);
            if (resolved) {
                free(joined);
                joined = resolved;
            }
        }
    }
    const wchar_t* prefix = L"\\\\?\\";
    size_t skip = 0;
    if (joined[0] == L'\\' && joined[1] == L'\\') {
        prefix = L"\\\\?\\UNC\\";  // network: \\server\share -> \\?\UNC\server\share
        skip = 2;
    }
    size_t pl = wcslen(prefix), il = wcslen(joined);
    wchar_t* out = (wchar_t*)malloc((pl + il - skip + 1) * sizeof(wchar_t));
    if (!out) { free(joined); return NULL; }
    memcpy(out, prefix, pl * sizeof(wchar_t));
    memcpy(out + pl, joined + skip, (il - skip + 1) * sizeof(wchar_t));
    free(joined);
    return out;
}

int32_t __koral_stat(const uint8_t* path, KoralStatResult* out) {
    wchar_t* wpath = __koral_win_widen_path((const char*)path);
    if (!wpath) return -1;
    struct _stat64 st;
    int rc = _wstat64(wpath, &st);
    free(wpath);
    if (rc != 0) return -1;
    __koral_fill_stat_result(&st, out);
    return 0;
}

int32_t __koral_lstat(const uint8_t* path, KoralStatResult* out) {
    // Windows has no symlink-aware lstat; fall back to stat
    return __koral_stat(path, out);
}

int32_t __koral_fstat(int32_t fd, KoralStatResult* out) {
    struct _stat64 st;
    if (_fstat64(fd, &st) != 0) return -1;
    __koral_fill_stat_result(&st, out);
    return 0;
}

int32_t __koral_chmod(const uint8_t* path, uint32_t mode) {
    wchar_t* wpath = __koral_win_widen_path((const char*)path);
    if (!wpath) return -1;
    int rc = _wchmod(wpath, (int)(mode & 0777));
    free(wpath);
    return rc == 0 ? 0 : -1;
}

int32_t __koral_link(const uint8_t* src, const uint8_t* dst) {
    wchar_t* wsrc = __koral_win_widen_path((const char*)src);
    wchar_t* wdst = __koral_win_widen_path((const char*)dst);
    if (!wsrc || !wdst) {
        free(wsrc);
        free(wdst);
        return -1;
    }
    int rc = CreateHardLinkW(wdst, wsrc, NULL) ? 0 : -1;
    free(wsrc);
    free(wdst);
    return rc;
}

int32_t __koral_symlink(const uint8_t* src, const uint8_t* dst) {
    // The TARGET is stored verbatim in the link -- never widened. Only the
    // link's own location goes through path routing.
    wchar_t* wsrc = __koral_utf8_to_wide((const char*)src);
    wchar_t* wdst = __koral_win_widen_path((const char*)dst);
    if (!wsrc || !wdst) {
        free(wsrc);
        free(wdst);
        return -1;
    }
    // Windows cannot resolve a relative reparse target containing '/': the
    // target is stored with backslash separators, and __koral_readlink
    // converts them back to Koral's forward-slash spelling on the way out.
    for (wchar_t* q = wsrc; *q; q++) {
        if (*q == L'/') *q = L'\\';
    }
    DWORD flags = 0;
    // A non-absolute target is stored RELATIVE to the link's own directory,
    // exactly like POSIX symlink(2) -- which needs SYMLINK_FLAG_RELATIVE
    // (0x1); without it Windows resolves the target against the process CWD
    // and bakes that absolute path into the link. The directory probe below
    // therefore resolves a relative target against the link's directory too.
    int target_is_abs = (wsrc[0] && wsrc[1] == L':')
        || (wsrc[0] == L'\\' && wsrc[1] == L'\\');
    if (!target_is_abs) flags |= 0x1;
    wchar_t probe_buf[4096];
    const wchar_t* probe = wsrc;
    {
        size_t dl = 0;
        size_t tl = wcslen(wsrc);
        if (!target_is_abs) {
            dl = wcslen(wdst);
            while (dl > 0 && wdst[dl - 1] != L'\\') dl--;
        }
        if (dl + tl + 1 < 4096) {
            memcpy(probe_buf, wdst, dl * sizeof(wchar_t));
            memcpy(probe_buf + dl, wsrc, (tl + 1) * sizeof(wchar_t));
            for (wchar_t* q = probe_buf + dl; *q; q++) {
                if (*q == L'/') *q = L'\\';
            }
            probe = probe_buf;
        }
    }
    DWORD attrs = GetFileAttributesW(probe);
    if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY))
        flags = SYMBOLIC_LINK_FLAG_DIRECTORY | (flags & 0x1);
    // ALLOW_UNPRIVILEGED_CREATE (0x2) lets Developer Mode machines create
    // symlinks without elevation. Older systems reject the flag outright, so
    // retry without it before giving up.
    DWORD rc = CreateSymbolicLinkW(wdst, wsrc, flags | 0x2) ? 0 : (DWORD)-1;
    if (rc != 0) {
        rc = CreateSymbolicLinkW(wdst, wsrc, flags) ? 0 : (DWORD)-1;
    }
    free(wsrc);
    free(wdst);
    return rc;
}

int32_t __koral_readlink(const uint8_t* path, uint8_t* buf, uint64_t buf_size) {
    // The core reads the reparse target; a result equal to buf_size means it
    // did not fit and the caller retries with more room.
    wchar_t wtarget[2048];
    wchar_t* wpath = __koral_win_widen_path((const char*)path);
    if (!wpath) return -1;
    int wlen = koral_win_readlink_w(wpath, wtarget, 2048);
    free(wpath);
    if (wlen < 0) return -1;
    int needed = WideCharToMultiByte(CP_UTF8, 0, wtarget, wlen, NULL, 0, NULL, NULL);
    if (needed <= 0) return -1;
    if ((uint64_t)needed > buf_size) {
        WideCharToMultiByte(CP_UTF8, 0, wtarget, wlen, (char*)buf, (int)buf_size, NULL, NULL);
        return (int32_t)buf_size;
    }
    int written = WideCharToMultiByte(CP_UTF8, 0, wtarget, wlen, (char*)buf, (int)buf_size, NULL, NULL);
    return written > 0 ? written : -1;
}

int32_t __koral_truncate(const uint8_t* path, int64_t size) {
    wchar_t* wpath = __koral_win_widen_path((const char*)path);
    if (!wpath) return -1;
    HANDLE h = CreateFileW(wpath, GENERIC_WRITE, 0, NULL,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    free(wpath);
    if (h == INVALID_HANDLE_VALUE) return -1;
    LARGE_INTEGER li;
    li.QuadPart = size;
    if (!SetFilePointerEx(h, li, NULL, FILE_BEGIN) || !SetEndOfFile(h)) {
        CloseHandle(h);
        return -1;
    }
    CloseHandle(h);
    return 0;
}

int32_t __koral_fsync(int32_t fd) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    if (h == INVALID_HANDLE_VALUE) return -1;
    return FlushFileBuffers(h) ? 0 : -1;
}

int32_t __koral_flock(int32_t fd, int32_t operation) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    if (h == INVALID_HANDLE_VALUE) return -1;
    OVERLAPPED ov = {0};
    if (operation & 8) { // LOCK_UN
        return UnlockFileEx(h, 0, MAXDWORD, MAXDWORD, &ov) ? 0 : -1;
    }
    DWORD flags = 0;
    if (operation & 2) flags |= LOCKFILE_EXCLUSIVE_LOCK;   // LOCK_EX
    if (operation & 4) flags |= LOCKFILE_FAIL_IMMEDIATELY;  // LOCK_NB
    return LockFileEx(h, flags, 0, MAXDWORD, MAXDWORD, &ov) ? 0 : -1;
}

int32_t __koral_errno_is_wouldblock(void) {
    return (errno == EWOULDBLOCK || errno == EAGAIN) ? 1 : 0;
}

int32_t __koral_realpath(const uint8_t* path, uint8_t* buf, uint64_t size) {
    wchar_t* wpath = __koral_utf8_to_wide((const char*)path);
    if (!wpath) return -1;
    wchar_t wbuf[4096];
    DWORD cap = (DWORD)(sizeof(wbuf) / sizeof(wbuf[0]));
    DWORD len = GetFullPathNameW(wpath, cap, wbuf, NULL);
    free(wpath);
    if (len == 0 || len >= cap) return -1;
    char* utf8 = __koral_wide_to_utf8(wbuf);
    if (!utf8) return -1;
    size_t n = strlen(utf8);
    if (n + 1 > size) {
        free(utf8);
        return -1;
    }
    memcpy(buf, utf8, n + 1);
    free(utf8);
    return 0;
}

int32_t __koral_mkstemp(uint8_t* tmpl) {
    // Windows: use _mktemp_s + _open
    if (_mktemp_s((char*)tmpl, strlen((char*)tmpl) + 1) != 0) return -1;
    int fd;
    if (_sopen_s(&fd, (const char*)tmpl, _O_CREAT | _O_EXCL | _O_RDWR, _SH_DENYNO, _S_IREAD | _S_IWRITE) != 0)
        return -1;
    return (int32_t)fd;
}

int32_t __koral_dirent_type(void* entry) {
    CDirEntry* e = (CDirEntry*)entry;
    if (e->attributes & FILE_ATTRIBUTE_REPARSE_POINT) return 2; // symlink
    if (e->attributes & FILE_ATTRIBUTE_DIRECTORY) return 1;     // directory
    return 0; // regular file
}

int32_t __koral_unsetenv(const uint8_t* name) {
    return _putenv_s((const char*)name, "") == 0 ? 0 : -1;
}

uint8_t** __koral_environ(void) {
    return (uint8_t**)_environ;
}

uint64_t __koral_environ_count(void) {
    uint64_t count = 0;
    if (_environ) {
        while (_environ[count]) count++;
    }
    return count;
}

int32_t __koral_hostname(uint8_t* buf, uint64_t size) {
    DWORD sz = (DWORD)size;
    return GetComputerNameA((char*)buf, &sz) ? 0 : -1;
}

int32_t __koral_current_exe(uint8_t* buf, uint64_t size) {
    wchar_t wbuf[4096];
    DWORD cap = (DWORD)(sizeof(wbuf) / sizeof(wbuf[0]));
    DWORD len = GetModuleFileNameW(NULL, wbuf, cap);
    if (len == 0 || len >= cap) return -1;
    char* utf8 = __koral_wide_to_utf8(wbuf);
    if (!utf8) return -1;
    size_t n = strlen(utf8);
    if (n + 1 > size) {
        free(utf8);
        return -1;
    }
    memcpy(buf, utf8, n + 1);
    free(utf8);
    return 0;
}

int32_t __koral_open(const uint8_t* path, int32_t open_mode, uint32_t perm) {
    (void)perm;
    DWORD access = 0;
    DWORD creation = 0;
    int oflags = _O_BINARY;
    switch (open_mode) {
        case 0: access = GENERIC_READ; creation = OPEN_EXISTING; oflags |= _O_RDONLY; break;      // Read
        case 1: access = GENERIC_WRITE; creation = CREATE_ALWAYS; oflags |= _O_WRONLY; break;     // Write
        case 2: access = GENERIC_WRITE; creation = CREATE_NEW; oflags |= _O_WRONLY; break;        // Create
        case 3: access = GENERIC_WRITE; creation = OPEN_ALWAYS; oflags |= _O_WRONLY | _O_APPEND; break;  // Append
        case 4: access = GENERIC_READ | GENERIC_WRITE; creation = OPEN_EXISTING; oflags |= _O_RDWR; break;  // ReadWrite
        default: return -1;
    }
    wchar_t* wpath = __koral_win_widen_path((const char*)path);
    if (!wpath) return -1;
    // FILE_SHARE_DELETE is what gives unlink-while-open its POSIX meaning: a
    // removal may proceed against a file this process still holds open, and
    // the delete lands when the last handle closes. The CRT's opens share
    // only read/write and turn every such removal into a sharing violation.
    HANDLE h = CreateFileW(wpath, access,
                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           NULL, creation, FILE_ATTRIBUTE_NORMAL, NULL);
    free(wpath);
    if (h == INVALID_HANDLE_VALUE) return -1;
    int fd = _open_osfhandle((intptr_t)h, oflags);
    if (fd < 0) {
        CloseHandle(h);
        return -1;
    }
    return (int32_t)fd;
}

int64_t __koral_read(int32_t fd, uint8_t* buf, uint64_t count) {
    return (int64_t)_read(fd, buf, (unsigned int)count);
}

int64_t __koral_write(int32_t fd, const uint8_t* buf, uint64_t count) {
    return (int64_t)_write(fd, buf, (unsigned int)count);
}

int32_t __koral_isatty(int32_t fd) {
    return _isatty(fd) ? 1 : 0;
}

int32_t __koral_set_binary_mode(int32_t fd) {
    return _setmode(fd, _O_BINARY) == -1 ? -1 : 0;
}

int64_t __koral_lseek(int32_t fd, int64_t offset, int32_t whence) {
    return (int64_t)_lseeki64(fd, offset, whence);
}

int32_t __koral_close(int32_t fd) {
    return _close(fd);
}

int32_t __koral_chdir(const uint8_t* path) {
    wchar_t* wpath = __koral_win_widen_path((const char*)path);
    if (!wpath) return -1;
    int rc = _wchdir(wpath);
    free(wpath);
    return rc;
}

uint8_t* __koral_mkdtemp(uint8_t* tmpl) {
    // Windows: use _mktemp_s to generate unique name, then _mkdir
    if (_mktemp_s((char*)tmpl, strlen((char*)tmpl) + 1) != 0) return NULL;
    if (_mkdir((const char*)tmpl) != 0) return NULL;
    return tmpl;
}

#else

// --- POSIX implementations ---

#include <sys/file.h>
#include <fcntl.h>

static void __koral_fill_stat_result(struct stat* st, KoralStatResult* out) {
    out->size = (int64_t)st->st_size;
    if (S_ISREG(st->st_mode))       out->file_type = 0;
    else if (S_ISDIR(st->st_mode))   out->file_type = 1;
    else if (S_ISLNK(st->st_mode))   out->file_type = 2;
    else                              out->file_type = 3;
    out->permissions = (uint32_t)(st->st_mode & 0777);
#if defined(__APPLE__)
    out->modified_secs = (int64_t)st->st_mtimespec.tv_sec;
    out->modified_nanos = (int64_t)st->st_mtimespec.tv_nsec;
    out->accessed_secs = (int64_t)st->st_atimespec.tv_sec;
    out->accessed_nanos = (int64_t)st->st_atimespec.tv_nsec;
    out->created_secs = (int64_t)st->st_birthtimespec.tv_sec;
    out->created_nanos = (int64_t)st->st_birthtimespec.tv_nsec;
#else
    out->modified_secs = (int64_t)st->st_mtim.tv_sec;
    out->modified_nanos = (int64_t)st->st_mtim.tv_nsec;
    out->accessed_secs = (int64_t)st->st_atim.tv_sec;
    out->accessed_nanos = (int64_t)st->st_atim.tv_nsec;
    out->created_secs = 0;  // Linux doesn't reliably expose birth time
    out->created_nanos = 0;
#endif
}

int32_t __koral_stat(const uint8_t* path, KoralStatResult* out) {
    struct stat st;
    if (stat((const char*)path, &st) != 0) return -1;
    __koral_fill_stat_result(&st, out);
    return 0;
}

int32_t __koral_lstat(const uint8_t* path, KoralStatResult* out) {
    struct stat st;
    if (lstat((const char*)path, &st) != 0) return -1;
    __koral_fill_stat_result(&st, out);
    return 0;
}

int32_t __koral_fstat(int32_t fd, KoralStatResult* out) {
    struct stat st;
    if (fstat(fd, &st) != 0) return -1;
    __koral_fill_stat_result(&st, out);
    return 0;
}

int32_t __koral_chmod(const uint8_t* path, uint32_t mode) {
    return chmod((const char*)path, (mode_t)(mode & 0777)) == 0 ? 0 : -1;
}

int32_t __koral_link(const uint8_t* src, const uint8_t* dst) {
    return link((const char*)src, (const char*)dst) == 0 ? 0 : -1;
}

int32_t __koral_symlink(const uint8_t* src, const uint8_t* dst) {
    return symlink((const char*)src, (const char*)dst) == 0 ? 0 : -1;
}

int32_t __koral_readlink(const uint8_t* path, uint8_t* buf, uint64_t buf_size) {
    // Fill the whole buffer: a return of exactly buf_size is then the
    // unambiguous "target truncated" signal. The NUL only fits when the
    // target fit in the buffer.
    ssize_t len = readlink((const char*)path, (char*)buf, (size_t)buf_size);
    if (len < 0) return -1;
    if ((uint64_t)len < buf_size) buf[len] = '\0';
    return (int32_t)len;
}

int32_t __koral_truncate(const uint8_t* path, int64_t size) {
    return truncate((const char*)path, (off_t)size) == 0 ? 0 : -1;
}

int32_t __koral_fsync(int32_t fd) {
    return fsync(fd) == 0 ? 0 : -1;
}

int32_t __koral_flock(int32_t fd, int32_t operation) {
    int op = 0;
    if (operation & 1) op |= LOCK_SH;
    if (operation & 2) op |= LOCK_EX;
    if (operation & 4) op |= LOCK_NB;
    if (operation & 8) op |= LOCK_UN;
    return flock(fd, op) == 0 ? 0 : -1;
}

int32_t __koral_errno_is_wouldblock(void) {
    return (errno == EWOULDBLOCK || errno == EAGAIN) ? 1 : 0;
}

int32_t __koral_realpath(const uint8_t* path, uint8_t* buf, uint64_t size) {
    char resolved[4096];
    if (realpath((const char*)path, resolved) == NULL) return -1;
    size_t len = strlen(resolved);
    if (len >= size) return -1;
    memcpy(buf, resolved, len + 1);
    return 0;
}

int32_t __koral_mkstemp(uint8_t* tmpl) {
    return mkstemp((char*)tmpl);
}

int32_t __koral_dirent_type(void* entry) {
    CDirEntry* e = (CDirEntry*)entry;
    switch (e->entry.d_type) {
        case DT_REG:  return 0;
        case DT_DIR:  return 1;
        case DT_LNK:  return 2;
#ifdef DT_UNKNOWN
        // Filesystems without type reporting leave d_type unset; the caller
        // must lstat the entry instead of trusting a guess.
        case DT_UNKNOWN: return -1;
#endif
        default:      return 3;
    }
}

int32_t __koral_unsetenv(const uint8_t* name) {
    return unsetenv((const char*)name);
}

extern char** environ;

uint8_t** __koral_environ(void) {
    return (uint8_t**)environ;
}

uint64_t __koral_environ_count(void) {
    uint64_t count = 0;
    if (environ) {
        while (environ[count]) count++;
    }
    return count;
}

int32_t __koral_hostname(uint8_t* buf, uint64_t size) {
    return gethostname((char*)buf, (size_t)size) == 0 ? 0 : -1;
}

int32_t __koral_current_exe(uint8_t* buf, uint64_t size) {
#if defined(__linux__)
    ssize_t len = readlink("/proc/self/exe", (char*)buf, (size_t)size - 1);
    if (len < 0) return -1;
    buf[len] = '\0';
    return 0;
#elif defined(__APPLE__)
    // _NSGetExecutablePath requires <mach-o/dyld.h>
    extern int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
    uint32_t sz = (uint32_t)size;
    if (_NSGetExecutablePath((char*)buf, &sz) != 0) return -1;
    return 0;
#else
    (void)buf; (void)size;
    errno = ENOSYS;
    return -1;
#endif
}

int32_t __koral_open(const uint8_t* path, int32_t open_mode, uint32_t perm) {
    int flags;
    mode_t mode = (mode_t)perm;
    switch (open_mode) {
        case 0: flags = O_RDONLY; mode = 0; break;                              // Read
        case 1: flags = O_WRONLY | O_CREAT | O_TRUNC; break;                    // Write
        case 2: flags = O_WRONLY | O_CREAT | O_EXCL; break;                     // Create
        case 3: flags = O_WRONLY | O_CREAT | O_APPEND; break;                   // Append
        case 4: flags = O_RDWR; mode = 0; break;                                // ReadWrite
        default: return -1;
    }
    return open((const char*)path, flags, mode);
}

int64_t __koral_read(int32_t fd, uint8_t* buf, uint64_t count) {
    return (int64_t)read(fd, buf, (size_t)count);
}

int64_t __koral_write(int32_t fd, const uint8_t* buf, uint64_t count) {
    return (int64_t)write(fd, buf, (size_t)count);
}

int32_t __koral_isatty(int32_t fd) {
    return isatty(fd) ? 1 : 0;
}

int32_t __koral_set_binary_mode(int32_t fd) {
    (void)fd;
    return 0;
}

int64_t __koral_lseek(int32_t fd, int64_t offset, int32_t whence) {
    return (int64_t)lseek(fd, (off_t)offset, whence);
}

int32_t __koral_close(int32_t fd) {
    return close(fd);
}

int32_t __koral_chdir(const uint8_t* path) {
    return chdir((const char*)path);
}

uint8_t* __koral_mkdtemp(uint8_t* tmpl) {
    return (uint8_t*)mkdtemp((char*)tmpl);
}

#endif

// --- race-safe recursive tree removal -------------------------------------
//
// `remove_dir_all`'s contract: deletion may never escape the tree, even
// while another process renames directories or swaps them for symlinks
// mid-walk. The walk is therefore handle-relative and no-follow, and every
// child is identity-checked against the directory listing before it is
// touched. Root policy (a link root removes only the link; a missing path is
// an error) lives in std/os; what this adds is that the policy survives
// races. Returns 0 on success, -2 when the root is not a directory (it
// changed shape after std/os looked), -1 on any other failure.

#if defined(_WIN32) || defined(_WIN64)

/// Mark `h` for deletion with POSIX semantics: the name goes away at once
/// and the storage follows when the last handle closes. Plain
/// FileDispositionInfo keeps the entry visible until then, which leaves the
/// parent "not empty" whenever anything in the tree is still open -- exactly
/// the case the contract promises to handle (unlink-while-open).
static int koral_win_delete_on_close(HANDLE h) {
    struct {
        DWORD Flags;
    } dex;
    dex.Flags = 0x1 /* DELETE */ | 0x2 /* POSIX_SEMANTICS */;
    if (SetFileInformationByHandle(h, (FILE_INFO_BY_HANDLE_CLASS)21 /* FileDispositionInfoEx */,
                                   &dex, sizeof(dex))) {
        return 0;
    }
    FILE_DISPOSITION_INFO di;
    di.DeleteFile = TRUE;
    if (SetFileInformationByHandle(h, FileDispositionInfo, &di, sizeof(di))) return 0;
    return (GetLastError() == ERROR_FILE_NOT_FOUND) ? 0 : -1;
}

/// Open `wpath` for deletion and descent. FILE_LIST_DIRECTORY is what
/// directory enumeration needs and a plain file refuses that right, so the
/// file case falls back to the narrower access.
static HANDLE koral_win_open_for_remove(const wchar_t* wpath) {
    HANDLE h = CreateFileW(
        wpath, DELETE | SYNCHRONIZE | FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h == INVALID_HANDLE_VALUE && GetLastError() == ERROR_ACCESS_DENIED) {
        h = CreateFileW(
            wpath, DELETE | SYNCHRONIZE,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            NULL, OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    }
    return h;
}

static int koral_win_remove_tree(HANDLE dir, const wchar_t* dir_path, int budget) {
    if (budget <= 0) return -1;
    unsigned char buf[65536];
    BOOL ok = GetFileInformationByHandleEx(
        dir, (FILE_INFO_BY_HANDLE_CLASS)10 /* FileIdBothDirectoryInfo */,
        buf, sizeof(buf));
    while (ok) {
        FILE_ID_BOTH_DIR_INFO* info = (FILE_ID_BOTH_DIR_INFO*)buf;
        for (;;) {
            int name_wchars = (int)(info->FileNameLength / sizeof(WCHAR));
            int is_dot = (name_wchars == 1 && info->FileName[0] == L'.');
            int is_dotdot = (name_wchars == 2 && info->FileName[0] == L'.'
                             && info->FileName[1] == L'.');
            if (!is_dot && !is_dotdot) {
                size_t dl = wcslen(dir_path);
                wchar_t* child_path = (wchar_t*)malloc((dl + 1 + (size_t)name_wchars + 1) * sizeof(wchar_t));
                if (!child_path) return -1;
                memcpy(child_path, dir_path, dl * sizeof(wchar_t));
                child_path[dl] = L'\\';
                memcpy(child_path + dl + 1, info->FileName, (size_t)name_wchars * sizeof(WCHAR));
                child_path[dl + 1 + name_wchars] = L'\0';

                int rc = 0;
                HANDLE child = koral_win_open_for_remove(child_path);
                if (child == INVALID_HANDLE_VALUE) {
                    DWORD e = GetLastError();
                    if (e != ERROR_FILE_NOT_FOUND && e != ERROR_PATH_NOT_FOUND) rc = -1;
                } else {
                    BY_HANDLE_FILE_INFORMATION bh;
                    ULONGLONG listed_id = (ULONGLONG)info->FileId.QuadPart;
                    if (!GetFileInformationByHandle(child, &bh)) {
                        rc = -1;
                    } else if ((((ULONGLONG)bh.nFileIndexHigh << 32) | bh.nFileIndexLow) != listed_id) {
                        // The entry was swapped under us. Refuse to touch it:
                        // a wrong object must never be deleted.
                        rc = -1;
                    } else if (bh.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
                        // A link is deleted as a link, never descended.
                        if (koral_win_delete_on_close(child) != 0) rc = -1;
                    } else if (bh.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                        rc = koral_win_remove_tree(child, child_path, budget - 1);
                        if (rc == 0 && koral_win_delete_on_close(child) != 0) rc = -1;
                    } else {
                        if (koral_win_delete_on_close(child) != 0) rc = -1;
                    }
                    CloseHandle(child);
                }
                free(child_path);
                if (rc != 0) return -1;
            }
            if (info->NextEntryOffset == 0) break;
            info = (FILE_ID_BOTH_DIR_INFO*)((char*)info + info->NextEntryOffset);
        }
        ok = GetFileInformationByHandleEx(
            dir, (FILE_INFO_BY_HANDLE_CLASS)10, buf, sizeof(buf));
    }
    return (GetLastError() == ERROR_NO_MORE_FILES) ? 0 : -1;
}

int32_t __koral_remove_dir_all(const uint8_t* path) {
    wchar_t* wpath = __koral_win_widen_path((const char*)path);
    if (!wpath) return -1;
    HANDLE root = koral_win_open_for_remove(wpath);
    if (root == INVALID_HANDLE_VALUE) {
        free(wpath);
        return -1;
    }
    int rc = -1;
    BY_HANDLE_FILE_INFORMATION bh;
    if (GetFileInformationByHandle(root, &bh)) {
        if (bh.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
            // The root turned into a link after std/os looked: the contract
            // removes only the link.
            rc = koral_win_delete_on_close(root);
        } else if (!(bh.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
            rc = -2;
        } else {
            rc = koral_win_remove_tree(root, wpath, 1024);
            if (rc == 0 && koral_win_delete_on_close(root) != 0) rc = -1;
        }
    }
    CloseHandle(root);
    free(wpath);
    return rc;
}

#else

static int koral_remove_tree_at(int dirfd, int budget) {
    if (budget <= 0) {
        errno = ELOOP;
        return -1;
    }
    int scanfd = dup(dirfd);
    if (scanfd < 0) return -1;
    DIR* d = fdopendir(scanfd);
    if (!d) {
        close(scanfd);
        return -1;
    }
    struct dirent* e;
    while ((e = readdir(d)) != NULL) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        // O_NOFOLLOW refuses symlinks and O_DIRECTORY refuses files, so a
        // link or plain file falls through to unlink-as-itself below; a real
        // directory is descended through the fd we already hold.
        int child = openat(dirfd, e->d_name,
                           O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (child >= 0) {
            int rc = koral_remove_tree_at(child, budget - 1);
            close(child);
            if (rc != 0) {
                closedir(d);
                return -1;
            }
            if (unlinkat(dirfd, e->d_name, AT_REMOVEDIR) != 0 && errno != ENOENT) {
                closedir(d);
                return -1;
            }
        } else {
            if (unlinkat(dirfd, e->d_name, 0) != 0 && errno != ENOENT) {
                closedir(d);
                return -1;
            }
        }
    }
    closedir(d);
    return 0;
}

int32_t __koral_remove_dir_all(const uint8_t* path) {
    const char* p = (const char*)path;
    int root = open(p, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (root < 0) {
        // The root changed shape after std/os looked: a symlink is removed as
        // a link (the contract's root rule), a plain file is "not a
        // directory", and anything else is an error.
        struct stat st;
        if (lstat(p, &st) != 0) return -1;
        if (S_ISLNK(st.st_mode)) {
            return unlink(p) == 0 ? 0 : -1;
        }
        return S_ISDIR(st.st_mode) ? -1 : -2;
    }
    int rc = koral_remove_tree_at(root, 1024);
    close(root);
    if (rc != 0) return -1;
    // Remove the root itself by name. rmdir never follows a link, so a root
    // swapped to a symlink fails here instead of deleting its target; a root
    // already gone by someone else's hand is the goal met.
    if (rmdir(p) != 0 && errno != ENOENT) return -1;
    return 0;
}

#endif



// ============================================================================
// Subprocess management (std.command)
// ============================================================================

#if !defined(_WIN32) && !defined(_WIN64)
#include <spawn.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <signal.h>
#include <poll.h>
#if defined(__APPLE__)
#include <libproc.h>
#endif
#endif

typedef struct {
    uint32_t pid;
    int32_t  stdin_fd;
    int32_t  stdout_fd;
    int32_t  stderr_fd;
} KoralProcess;

// --- __koral_getpid ---

uint32_t __koral_getpid(void) {
#if defined(_WIN32) || defined(_WIN64)
    return (uint32_t)GetCurrentProcessId();
#else
    return (uint32_t)getpid();
#endif
}

// --- Pipe operations ---

int64_t __koral_pipe_read(int32_t fd, uint8_t* buf, uint64_t count) {
#if defined(_WIN32) || defined(_WIN64)
    return (int64_t)_read(fd, buf, (unsigned int)count);
#else
    return (int64_t)read(fd, buf, (size_t)count);
#endif
}

int64_t __koral_pipe_write(int32_t fd, const uint8_t* buf, uint64_t count) {
#if defined(_WIN32) || defined(_WIN64)
    return (int64_t)_write(fd, buf, (unsigned int)count);
#else
    return (int64_t)write(fd, buf, (size_t)count);
#endif
}

int32_t __koral_pipe_close(int32_t fd) {
#if defined(_WIN32) || defined(_WIN64)
    return _close(fd);
#else
    return close(fd);
#endif
}

// --- Signal / process queries ---

int32_t __koral_send_signal(uint32_t pid, int32_t signal) {
#if defined(_WIN32) || defined(_WIN64)
    // Windows: only support SIGTERM(15) and SIGKILL(9) via TerminateProcess
    if (signal == 9 || signal == 15) {
        HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, (DWORD)pid);
        if (h == NULL) return -1;
        BOOL ok = TerminateProcess(h, 1);
        CloseHandle(h);
        return ok ? 0 : -1;
    }
    errno = EINVAL;
    return -1;
#else
    return kill((pid_t)pid, signal) == 0 ? 0 : -1;
#endif
}

int32_t __koral_is_alive(uint32_t pid) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
    if (h == NULL) return 0;
    DWORD exit_code;
    BOOL ok = GetExitCodeProcess(h, &exit_code);
    CloseHandle(h);
    if (!ok) return 0;
    return (exit_code == STILL_ACTIVE) ? 1 : 0;
#else
    return (kill((pid_t)pid, 0) == 0) ? 1 : 0;
#endif
}

// --- __koral_process_working_set_bytes ---
// Returns the working set size (resident memory) of a process in bytes.
// Returns -1 on error (process not found, access denied, etc).

int64_t __koral_process_working_set_bytes(uint32_t pid) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, (DWORD)pid);
    if (h == NULL) return -1;
    PROCESS_MEMORY_COUNTERS pmc;
    BOOL ok = GetProcessMemoryInfo(h, &pmc, sizeof(pmc));
    CloseHandle(h);
    if (!ok) return -1;
    return (int64_t)pmc.WorkingSetSize;
#elif defined(__APPLE__)
    struct proc_taskinfo taskinfo;
    int size = proc_pidinfo((int)pid, PROC_PIDTASKINFO, 0, &taskinfo, (int)sizeof(taskinfo));
    if (size != (int)sizeof(taskinfo)) return -1;
    return (int64_t)taskinfo.pti_resident_size;
#else
    char path[64];
    snprintf(path, sizeof(path), "/proc/%u/status", pid);
    FILE* f = fopen(path, "r");
    if (!f) return -1;
    char line[256];
    int64_t rss_kb = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "VmRSS:", 6) == 0) {
            rss_kb = strtoll(line + 6, NULL, 10);
            break;
        }
    }
    fclose(f);
    return rss_kb > 0 ? rss_kb * 1024 : -1;
#endif
}

#if defined(__APPLE__)
// On macOS the test runner needs the memory footprint of the spawned process
// (typically the compiler or a test binary). Child helper processes (clang,
// ld) contribute relatively little compared to the root, and scanning the
// full process table on every 50 ms poll tick was both slow and error-prone
// (the old process-group scan could attribute unrelated processes to the
// measured tree). Reporting the root process RSS alone is accurate enough
// and avoids those failure modes.
static int64_t __koral_process_tree_working_set_bytes_macos(uint32_t root_pid) {
    return __koral_process_working_set_bytes(root_pid);
}
#endif

#if defined(__linux__)
static int __koral_linux_process_group_id(uint32_t pid, uint32_t* out_pgid) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%u/stat", pid);
    FILE* f = fopen(path, "r");
    if (!f) return -1;

    char line[4096];
    if (!fgets(line, sizeof(line), f)) {
        fclose(f);
        return -1;
    }
    fclose(f);

    char* closing_paren = strrchr(line, ')');
    if (!closing_paren) return -1;

    char state = 0;
    long ppid = 0;
    long pgid = 0;
    if (sscanf(closing_paren + 1, " %c %ld %ld", &state, &ppid, &pgid) != 3) {
        return -1;
    }
    if (pgid <= 0) return -1;

    *out_pgid = (uint32_t)pgid;
    return 0;
}

static int64_t __koral_process_group_working_set_bytes_linux(uint32_t root_pid) {
    DIR* dir = opendir("/proc");
    if (!dir) {
        return __koral_process_working_set_bytes(root_pid);
    }

    int64_t total = 0;
    struct dirent* entry;
    while ((entry = readdir(dir)) != NULL) {
        if (!isdigit((unsigned char)entry->d_name[0])) continue;

        uint32_t pid = (uint32_t)strtoul(entry->d_name, NULL, 10);
        if (pid == 0) continue;

        uint32_t pgid = 0;
        if (__koral_linux_process_group_id(pid, &pgid) != 0) continue;
        if (pgid != root_pid) continue;

        int64_t rss = __koral_process_working_set_bytes(pid);
        if (rss > 0) total += rss;
    }

    closedir(dir);
    if (total > 0) return total;
    return __koral_process_working_set_bytes(root_pid);
}
#endif


// --- __koral_process_tree_working_set_bytes ---
// Returns the total working set size of a process and all its descendants.
// This is needed because the test runner monitors the compiler process,
// but the compiler spawns child processes (like clang) that may consume
// significant memory independently.
#if defined(_WIN32) || defined(_WIN64)
static uint64_t __koral_filetime_ticks(FILETIME ft) {
    return ((uint64_t)ft.dwHighDateTime << 32) | (uint64_t)ft.dwLowDateTime;
}

static int __koral_process_creation_ticks(DWORD pid, uint64_t* out_ticks) {
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (h == NULL) return -1;

    FILETIME creation_time, exit_time, kernel_time, user_time;
    BOOL ok = GetProcessTimes(h, &creation_time, &exit_time, &kernel_time, &user_time);
    CloseHandle(h);
    if (!ok) return -1;

    *out_ticks = __koral_filetime_ticks(creation_time);
    return 0;
}
#endif

int64_t __koral_process_tree_working_set_bytes(uint32_t root_pid) {
#if defined(_WIN32) || defined(_WIN64)
    // First, get memory for the root process
    int64_t total = __koral_process_working_set_bytes(root_pid);
    if (total < 0) total = 0;

    uint64_t root_creation_ticks = 0;
    if (__koral_process_creation_ticks((DWORD)root_pid, &root_creation_ticks) != 0) {
        return total;
    }

    // Build a map of parent PID -> child PIDs using Toolhelp32
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return total;

    // Collect all processes
    typedef struct { DWORD pid; DWORD ppid; } ProcEntry;
    ProcEntry procs[4096];
    int count = 0;

    PROCESSENTRY32 pe;
    pe.dwSize = sizeof(pe);
    if (Process32First(snapshot, &pe)) {
        do {
            if (count < 4096) {
                procs[count].pid = pe.th32ProcessID;
                procs[count].ppid = pe.th32ParentProcessID;
                count++;
            }
        } while (Process32Next(snapshot, &pe));
    }

    CloseHandle(snapshot);

    typedef struct { uint32_t pid; uint64_t creation_ticks; } ProcQueueEntry;
    ProcQueueEntry queue[4096];
    int qhead = 0, qtail = 0;
    queue[qtail].pid = root_pid;
    queue[qtail].creation_ticks = root_creation_ticks;
    qtail++;

    while (qhead < qtail) {
        uint32_t current = queue[qhead].pid;
        uint64_t current_creation_ticks = queue[qhead].creation_ticks;
        qhead++;
        for (int i = 0; i < count; i++) {
            if (procs[i].ppid == current) {
                uint64_t child_creation_ticks = 0;
                if (__koral_process_creation_ticks(procs[i].pid, &child_creation_ticks) != 0) {
                    continue;
                }
                if (child_creation_ticks < current_creation_ticks) {
                    continue;
                }
                int64_t child_mem = __koral_process_working_set_bytes(procs[i].pid);
                if (child_mem > 0) total += child_mem;
                if (qtail < 4096) {
                    queue[qtail].pid = procs[i].pid;
                    queue[qtail].creation_ticks = child_creation_ticks;
                    qtail++;
                }
            }
        }
    }

    return total;
#elif defined(__APPLE__)
    // Walk the process tree rooted at root_pid so we capture the compiler
    // and any helper children (clang, ld, …) without scanning unrelated
    // processes that merely share a process-group id.
    return __koral_process_tree_working_set_bytes_macos(root_pid);
#elif defined(__linux__)
    return __koral_process_group_working_set_bytes_linux(root_pid);
#else
    // On other POSIX targets, fall back to the root process only.
    return __koral_process_working_set_bytes(root_pid);
#endif
}

int32_t __koral_kill_process_tree(uint32_t root_pid, int32_t signal) {
#if defined(_WIN32) || defined(_WIN64)
    return __koral_send_signal(root_pid, signal);
#else
    pid_t group_pid = (pid_t)root_pid;
    if (group_pid <= 0) {
        errno = EINVAL;
        return -1;
    }

    if (kill(-group_pid, signal) == 0) {
        return 0;
    }

    if (errno == ESRCH) {
        return kill(group_pid, signal) == 0 ? 0 : -1;
    }

    return -1;
#endif
}

// --- Wait operations ---

#if defined(_WIN32) || defined(_WIN64)

#define KORAL_PROCESS_HANDLE_CAPACITY 8192

typedef struct {
    DWORD pid;
    HANDLE handle;
} KoralProcessHandleEntry;

static SRWLOCK g_koral_process_handle_lock = SRWLOCK_INIT;
static KoralProcessHandleEntry g_koral_process_handles[KORAL_PROCESS_HANDLE_CAPACITY];

static int koral_process_handle_register(DWORD pid, HANDLE handle) {
    if (pid == 0 || handle == NULL) return 0;

    AcquireSRWLockExclusive(&g_koral_process_handle_lock);
    int empty_slot = -1;
    for (int i = 0; i < KORAL_PROCESS_HANDLE_CAPACITY; i++) {
        if (g_koral_process_handles[i].pid == pid) {
            if (g_koral_process_handles[i].handle != NULL) {
                CloseHandle(g_koral_process_handles[i].handle);
            }
            g_koral_process_handles[i].handle = handle;
            ReleaseSRWLockExclusive(&g_koral_process_handle_lock);
            return 1;
        }
        if (empty_slot < 0 && g_koral_process_handles[i].pid == 0) {
            empty_slot = i;
        }
    }

    if (empty_slot >= 0) {
        g_koral_process_handles[empty_slot].pid = pid;
        g_koral_process_handles[empty_slot].handle = handle;
        ReleaseSRWLockExclusive(&g_koral_process_handle_lock);
        return 1;
    }

    ReleaseSRWLockExclusive(&g_koral_process_handle_lock);
    return 0;
}

static HANDLE koral_process_handle_peek(DWORD pid) {
    if (pid == 0) return NULL;

    HANDLE result = NULL;
    AcquireSRWLockShared(&g_koral_process_handle_lock);
    for (int i = 0; i < KORAL_PROCESS_HANDLE_CAPACITY; i++) {
        if (g_koral_process_handles[i].pid == pid) {
            result = g_koral_process_handles[i].handle;
            break;
        }
    }
    ReleaseSRWLockShared(&g_koral_process_handle_lock);
    return result;
}

static HANDLE koral_process_handle_take(DWORD pid) {
    if (pid == 0) return NULL;

    HANDLE result = NULL;
    AcquireSRWLockExclusive(&g_koral_process_handle_lock);
    for (int i = 0; i < KORAL_PROCESS_HANDLE_CAPACITY; i++) {
        if (g_koral_process_handles[i].pid == pid) {
            result = g_koral_process_handles[i].handle;
            g_koral_process_handles[i].pid = 0;
            g_koral_process_handles[i].handle = NULL;
            break;
        }
    }
    ReleaseSRWLockExclusive(&g_koral_process_handle_lock);
    return result;
}

static void koral_process_handle_close(DWORD pid) {
    HANDLE h = koral_process_handle_take(pid);
    if (h != NULL) {
        CloseHandle(h);
    }
}

#endif

// Normalize ru_maxrss to bytes. The unit is platform-dependent:
// macOS reports bytes, Linux/BSD report kilobytes.
#if !defined(_WIN32) && !defined(_WIN64)
static uint64_t koral_maxrss_to_bytes(const struct rusage* ru) {
#if defined(__APPLE__) && defined(__MACH__)
    return (uint64_t)ru->ru_maxrss;            // macOS: already bytes
#else
    return (uint64_t)ru->ru_maxrss * 1024u;    // Linux/BSD: kilobytes
#endif
}
#endif

int32_t __koral_waitpid(uint32_t pid) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = koral_process_handle_take((DWORD)pid);
    if (h == NULL) {
        h = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)pid);
    }
    if (h == NULL) return -1;
    DWORD wait_result = WaitForSingleObject(h, INFINITE);
    CloseHandle(h);
    if (wait_result != WAIT_OBJECT_0) return -1;
    return 0;
#else
    int status;
    while (waitpid((pid_t)pid, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return 0;
#endif
}

int32_t __koral_waitpid_full(uint32_t pid, int32_t* exit_code, int32_t* signal_num, uint64_t* out_maxrss_bytes) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = koral_process_handle_take((DWORD)pid);
    if (h == NULL) {
        h = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_INFORMATION, FALSE, (DWORD)pid);
    }
    if (h == NULL) return -1;
    DWORD wait_result = WaitForSingleObject(h, INFINITE);
    if (wait_result != WAIT_OBJECT_0) {
        CloseHandle(h);
        return -1;
    }
    DWORD code;
    if (!GetExitCodeProcess(h, &code)) {
        CloseHandle(h);
        return -1;
    }
    if (out_maxrss_bytes != NULL) {
        PROCESS_MEMORY_COUNTERS pmc;
        if (GetProcessMemoryInfo(h, &pmc, sizeof(pmc))) {
            *out_maxrss_bytes = (uint64_t)pmc.PeakWorkingSetSize;
        } else {
            *out_maxrss_bytes = 0;
        }
    }
    CloseHandle(h);
    *exit_code = (int32_t)code;
    *signal_num = 0;
    return 0;
#else
    int status;
    struct rusage ru;
    while (wait4((pid_t)pid, &status, 0, &ru) < 0) {
        if (errno != EINTR) return -1;
    }
    if (WIFEXITED(status)) {
        *exit_code = (int32_t)WEXITSTATUS(status);
        *signal_num = 0;
    } else if (WIFSIGNALED(status)) {
        *exit_code = -1;
        *signal_num = (int32_t)WTERMSIG(status);
    } else {
        *exit_code = -1;
        *signal_num = 0;
    }
    if (out_maxrss_bytes != NULL) {
        *out_maxrss_bytes = koral_maxrss_to_bytes(&ru);
    }
    return 0;
#endif
}

int32_t __koral_try_waitpid(uint32_t pid, int32_t* exit_code, int32_t* signal_num, uint64_t* out_maxrss_bytes) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = koral_process_handle_peek((DWORD)pid);
    int using_registry_handle = (h != NULL);
    if (h == NULL) {
        h = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_INFORMATION, FALSE, (DWORD)pid);
    }
    if (h == NULL) return -1;

    DWORD wait_result = WaitForSingleObject(h, 0);
    if (wait_result == WAIT_TIMEOUT) {
        if (!using_registry_handle) {
            CloseHandle(h);
        }
        return 0;  // still running
    }
    if (wait_result != WAIT_OBJECT_0) {
        if (using_registry_handle) {
            koral_process_handle_close((DWORD)pid);
        } else {
            CloseHandle(h);
        }
        return -1;
    }

    DWORD code;
    if (!GetExitCodeProcess(h, &code)) {
        if (using_registry_handle) {
            koral_process_handle_close((DWORD)pid);
        } else {
            CloseHandle(h);
        }
        return -1;
    }

    if (out_maxrss_bytes != NULL) {
        PROCESS_MEMORY_COUNTERS pmc;
        if (GetProcessMemoryInfo(h, &pmc, sizeof(pmc))) {
            *out_maxrss_bytes = (uint64_t)pmc.PeakWorkingSetSize;
        } else {
            *out_maxrss_bytes = 0;
        }
    }

    if (using_registry_handle) {
        koral_process_handle_close((DWORD)pid);
    } else {
        CloseHandle(h);
    }

    *exit_code = (int32_t)code;
    *signal_num = 0;
    return 1;  // exited
#else
    int status;
    struct rusage ru;
    pid_t result = wait4((pid_t)pid, &status, WNOHANG, &ru);
    if (result < 0) return -1;
    if (result == 0) return 0;  // still running
    if (WIFEXITED(status)) {
        *exit_code = (int32_t)WEXITSTATUS(status);
        *signal_num = 0;
    } else if (WIFSIGNALED(status)) {
        *exit_code = -1;
        *signal_num = (int32_t)WTERMSIG(status);
    } else {
        *exit_code = -1;
        *signal_num = 0;
    }
    // wait4 only fills rusage when a child was actually reaped.
    if (out_maxrss_bytes != NULL) {
        *out_maxrss_bytes = koral_maxrss_to_bytes(&ru);
    }
    return 1;  // exited
#endif
}


// --- __koral_spawn ---

#if defined(_WIN32) || defined(_WIN64)

int32_t __koral_spawn(
    const uint8_t* program,
    const uint8_t** argv, int32_t argc,
    const uint8_t** envp, int32_t envc,
    const uint8_t* cwd,
    int32_t stdin_mode, int32_t stdout_mode, int32_t stderr_mode,
    int32_t stdin_fd_in, int32_t stdout_fd_in, int32_t stderr_fd_in,
    KoralProcess* out
) {
    HANDLE stdin_read = INVALID_HANDLE_VALUE, stdin_write = INVALID_HANDLE_VALUE;
    HANDLE stdout_read = INVALID_HANDLE_VALUE, stdout_write = INVALID_HANDLE_VALUE;
    HANDLE stderr_read = INVALID_HANDLE_VALUE, stderr_write = INVALID_HANDLE_VALUE;
    HANDLE stdin_file = INVALID_HANDLE_VALUE;
    HANDLE stdout_file = INVALID_HANDLE_VALUE;
    HANDLE stderr_file = INVALID_HANDLE_VALUE;
    SECURITY_ATTRIBUTES sa = { sizeof(SECURITY_ATTRIBUTES), NULL, TRUE };

    // Create pipes as needed
    if (stdin_mode == 1) {
        if (!CreatePipe(&stdin_read, &stdin_write, &sa, 0)) {
            __koral_win_record_error(GetLastError());
            return -1;
        }
        SetHandleInformation(stdin_write, HANDLE_FLAG_INHERIT, 0);
    }
    if (stdout_mode == 1) {
        if (!CreatePipe(&stdout_read, &stdout_write, &sa, 0)) {
            __koral_win_record_error(GetLastError());
            goto fail;
        }
        SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0);
    }
    if (stderr_mode == 1) {
        if (!CreatePipe(&stderr_read, &stderr_write, &sa, 0)) {
            __koral_win_record_error(GetLastError());
            goto fail;
        }
        SetHandleInformation(stderr_read, HANDLE_FLAG_INHERIT, 0);
    }
    // Mode 3: DuplicateHandle from the caller-provided CRT fd (inheritable copy)
    if (stdin_mode == 3) {
        HANDLE src = (HANDLE)_get_osfhandle(stdin_fd_in);
        if (src == INVALID_HANDLE_VALUE) goto fail;
        if (!DuplicateHandle(GetCurrentProcess(), src,
                             GetCurrentProcess(), &stdin_file,
                             0, TRUE, DUPLICATE_SAME_ACCESS)) {
            __koral_win_record_error(GetLastError());
            goto fail;
        }
    }
    if (stdout_mode == 3) {
        HANDLE src = (HANDLE)_get_osfhandle(stdout_fd_in);
        if (src == INVALID_HANDLE_VALUE) goto fail;
        if (!DuplicateHandle(GetCurrentProcess(), src,
                             GetCurrentProcess(), &stdout_file,
                             0, TRUE, DUPLICATE_SAME_ACCESS)) {
            __koral_win_record_error(GetLastError());
            goto fail;
        }
    }
    if (stderr_mode == 3) {
        HANDLE src = (HANDLE)_get_osfhandle(stderr_fd_in);
        if (src == INVALID_HANDLE_VALUE) goto fail;
        if (!DuplicateHandle(GetCurrentProcess(), src,
                             GetCurrentProcess(), &stderr_file,
                             0, TRUE, DUPLICATE_SAME_ACCESS)) {
            __koral_win_record_error(GetLastError());
            goto fail;
        }
    }

    // Build command line string as UTF-8 first, then widen it for
    // CreateProcessW. Args and paths can hold non-ASCII text. Every arg is
    // quoted, so CommandLineToArgvW rules apply: a run of N backslashes before
    // a quote becomes 2N+1 backslashes plus the quote, and before the closing
    // quote a run of N becomes 2N.
    char cmdline[32768];
    int pos = 0;
    for (int i = 0; i < argc && pos < 32700; i++) {
        if (i > 0) cmdline[pos++] = ' ';
        cmdline[pos++] = '"';
        const char* arg = (const char*)argv[i];
        int backslashes = 0;
        for (const char* p = arg; *p && pos < 32700; p++) {
            if (*p == '\\') {
                backslashes++;
                continue;
            }
            if (*p == '"') {
                for (int k = 0; k < 2 * backslashes + 1 && pos < 32700; k++) {
                    cmdline[pos++] = '\\';
                }
                backslashes = 0;
                cmdline[pos++] = '"';
                continue;
            }
            for (int k = 0; k < backslashes && pos < 32700; k++) {
                cmdline[pos++] = '\\';
            }
            backslashes = 0;
            cmdline[pos++] = *p;
        }
        for (int k = 0; k < 2 * backslashes && pos < 32700; k++) {
            cmdline[pos++] = '\\';
        }
        cmdline[pos++] = '"';
    }
    cmdline[pos] = '\0';

    wchar_t* wcmdline = __koral_utf8_to_wide(cmdline);
    if (!wcmdline) goto fail;
    wchar_t* wprogram = __koral_utf8_to_wide((const char*)program);
    if (!wprogram) {
        free(wcmdline);
        goto fail;
    }
    wchar_t* wwork_dir = NULL;
    if (cwd && cwd[0]) {
        wwork_dir = __koral_utf8_to_wide((const char*)cwd);
        if (!wwork_dir) {
            free(wcmdline);
            free(wprogram);
            goto fail;
        }
    }

    // Build the environment block as UTF-16, the form
    // CREATE_UNICODE_ENVIRONMENT declares. Each entry is `NAME=VALUE\0`, and
    // the block ends with an extra `\0`. envc < 0 means "inherit"; envc >= 0
    // passes the child's COMPLETE environment (envc == 0 => empty env block).
    wchar_t* env_block = NULL;
    if (envc >= 0) {
        // The block is a run of `NAME=VALUE\0` strings plus the block
        // terminator. An EMPTY environment is one empty string plus that
        // terminator -- two null characters; a single null makes
        // CreateProcessW reject the block outright.
        size_t total = (envc == 0) ? 2 : 1;  // trailing extra null(s)
        for (int i = 0; i < envc; i++) {
            wchar_t* wentry = __koral_utf8_to_wide((const char*)envp[i]);
            if (!wentry) {
                free(wcmdline);
                free(wprogram);
                free(wwork_dir);
                goto fail;
            }
            total += wcslen(wentry) + 1;
            free(wentry);
        }
        env_block = (wchar_t*)malloc(total * sizeof(wchar_t));
        if (!env_block) {
            free(wcmdline);
            free(wprogram);
            free(wwork_dir);
            goto fail;
        }
        wchar_t* p = env_block;
        for (int i = 0; i < envc; i++) {
            wchar_t* wentry = __koral_utf8_to_wide((const char*)envp[i]);
            if (!wentry) {
                free(env_block);
                free(wcmdline);
                free(wprogram);
                free(wwork_dir);
                goto fail;
            }
            size_t len = wcslen(wentry);
            memcpy(p, wentry, len * sizeof(wchar_t));
            p[len] = L'\0';
            p += len + 1;
            free(wentry);
        }
        *p = L'\0';
        if (envc == 0) {
            p[1] = L'\0';
        }
    }

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;

    // stdin
    if (stdin_mode == 1) si.hStdInput = stdin_read;
    else if (stdin_mode == 2) si.hStdInput = INVALID_HANDLE_VALUE;
    else if (stdin_mode == 3) si.hStdInput = stdin_file;
    else si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    // stdout
    if (stdout_mode == 1) si.hStdOutput = stdout_write;
    else if (stdout_mode == 2) si.hStdOutput = INVALID_HANDLE_VALUE;
    else if (stdout_mode == 3) si.hStdOutput = stdout_file;
    else si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);

    // stderr
    if (stderr_mode == 1) si.hStdError = stderr_write;
    else if (stderr_mode == 2) si.hStdError = INVALID_HANDLE_VALUE;
    else if (stderr_mode == 3) si.hStdError = stderr_file;
    else si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    memset(&pi, 0, sizeof(pi));
    // lpApplicationName stays NULL on purpose: the module name is the first
    // token of the command line, and only THAT spelling is searched against
    // the application directory, the system directories and PATH (and gets
    // `.exe` appended). Passing the bare name as lpApplicationName skips the
    // PATH search entirely, so `Command.new("sh")` could never work.
    BOOL ok = CreateProcessW(
        NULL, wcmdline, NULL, NULL, TRUE,
        env_block ? CREATE_UNICODE_ENVIRONMENT : 0,
        env_block, wwork_dir, &si, &pi
    );
    // Read the thread's last-error slot before the frees below can spend it.
    DWORD spawn_err = ok ? 0 : GetLastError();

    free(wcmdline);
    free(wprogram);
    free(wwork_dir);
    if (env_block) free(env_block);

    if (!ok) {
        __koral_win_record_error(spawn_err);
        goto fail;
    }

    // Close child-side handles
    if (stdin_read != INVALID_HANDLE_VALUE) CloseHandle(stdin_read);
    if (stdout_write != INVALID_HANDLE_VALUE) CloseHandle(stdout_write);
    if (stderr_write != INVALID_HANDLE_VALUE) CloseHandle(stderr_write);
    if (stdin_file != INVALID_HANDLE_VALUE) CloseHandle(stdin_file);
    if (stdout_file != INVALID_HANDLE_VALUE) CloseHandle(stdout_file);
    if (stderr_file != INVALID_HANDLE_VALUE) CloseHandle(stderr_file);
    CloseHandle(pi.hThread);

    out->pid = (uint32_t)pi.dwProcessId;
    out->stdin_fd = (stdin_mode == 1) ? _open_osfhandle((intptr_t)stdin_write, 0) : -1;
    out->stdout_fd = (stdout_mode == 1) ? _open_osfhandle((intptr_t)stdout_read, _O_RDONLY) : -1;
    out->stderr_fd = (stderr_mode == 1) ? _open_osfhandle((intptr_t)stderr_read, _O_RDONLY) : -1;

    // Keep child process handles keyed by pid to avoid OpenProcess(pid) races
    // when short-lived children exit before polling observes them.
    if (!koral_process_handle_register(pi.dwProcessId, pi.hProcess)) {
        CloseHandle(pi.hProcess);
    }

    return 0;

fail:
    if (stdin_read != INVALID_HANDLE_VALUE) CloseHandle(stdin_read);
    if (stdin_write != INVALID_HANDLE_VALUE) CloseHandle(stdin_write);
    if (stdout_read != INVALID_HANDLE_VALUE) CloseHandle(stdout_read);
    if (stdout_write != INVALID_HANDLE_VALUE) CloseHandle(stdout_write);
    if (stderr_read != INVALID_HANDLE_VALUE) CloseHandle(stderr_read);
    if (stderr_write != INVALID_HANDLE_VALUE) CloseHandle(stderr_write);
    if (stdin_file != INVALID_HANDLE_VALUE) CloseHandle(stdin_file);
    if (stdout_file != INVALID_HANDLE_VALUE) CloseHandle(stdout_file);
    if (stderr_file != INVALID_HANDLE_VALUE) CloseHandle(stderr_file);
    return -1;
}

#else  // POSIX

// Resolve a bare program name through the PATH the child will see, exactly the
// way execvp would, so an explicit environment block no longer disables PATH
// search. `envp` is the child's complete environment, or NULL to inherit the
// caller's. `cwd` (when set) is where relative PATH entries resolve against,
// because the fork+exec child chdir()s before exec. Returns a malloc'd path
// (with a '/' in it, so spawn never re-searches) or NULL with errno set.
static char* __koral_resolve_program(const char* program, char* const* envp, const char* cwd) {
    if (!program || !program[0]) {
        errno = ENOENT;
        return NULL;
    }
    if (strchr(program, '/')) {
        return strdup(program);
    }

    const char* path_val = NULL;
    if (envp) {
        for (int i = 0; envp[i]; i++) {
            if (strncmp(envp[i], "PATH=", 5) == 0) {
                path_val = envp[i] + 5;
                break;
            }
        }
    } else {
        path_val = getenv("PATH");
    }
    char default_path[256];
    if (!path_val) {
        // execvp with an unset PATH falls back to the system default.
#if defined(_CS_PATH)
        size_t n = confstr(_CS_PATH, default_path, sizeof(default_path));
        if (n == 0 || n > sizeof(default_path)) {
            strcpy(default_path, "/bin:/usr/bin");
        }
#else
        strcpy(default_path, "/bin:/usr/bin");
#endif
        path_val = default_path;
    }

    char candidate[4096];
    int saw_eacces = 0;
    const char* p = path_val;
    for (;;) {
        const char* sep = strchr(p, ':');
        int entry_len = sep ? (int)(sep - p) : (int)strlen(p);
        int n;
        if (entry_len == 0) {
            // An empty PATH entry means the current directory (the child's,
            // once cwd is applied).
            n = (cwd && cwd[0])
                ? snprintf(candidate, sizeof(candidate), "%s/%s", cwd, program)
                : snprintf(candidate, sizeof(candidate), "%s", program);
        } else if (p[0] == '/') {
            n = snprintf(candidate, sizeof(candidate), "%.*s/%s", entry_len, p, program);
        } else {
            n = (cwd && cwd[0])
                ? snprintf(candidate, sizeof(candidate), "%s/%.*s/%s", cwd, entry_len, p, program)
                : snprintf(candidate, sizeof(candidate), "%.*s/%s", entry_len, p, program);
        }
        if (n > 0 && n < (int)sizeof(candidate)) {
            struct stat st;
            if (stat(candidate, &st) == 0) {
                if (!S_ISDIR(st.st_mode) && access(candidate, X_OK) == 0) {
                    return strdup(candidate);
                }
                saw_eacces = 1;
            }
        }
        if (!sep) break;
        p = sep + 1;
    }
    errno = saw_eacces ? EACCES : ENOENT;
    return NULL;
}

int32_t __koral_spawn(
    const uint8_t* program,
    const uint8_t** argv, int32_t argc,
    const uint8_t** envp, int32_t envc,
    const uint8_t* cwd,
    int32_t stdin_mode, int32_t stdout_mode, int32_t stderr_mode,
    int32_t stdin_fd_in, int32_t stdout_fd_in, int32_t stderr_fd_in,
    KoralProcess* out
) {
    int stdin_pipe[2] = {-1, -1};
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    int stdin_file = -1;
    int stdout_file = -1;
    int stderr_file = -1;
    int null_fd = -1;

    // Create pipes as needed
    if (stdin_mode == 1) {
        if (pipe(stdin_pipe) < 0) return -1;
    }
    if (stdout_mode == 1) {
        if (pipe(stdout_pipe) < 0) goto fail;
    }
    if (stderr_mode == 1) {
        if (pipe(stderr_pipe) < 0) goto fail;
    }
    // Mode 3: dup the caller-provided fd (so C-side close won't affect the original)
    if (stdin_mode == 3) {
        stdin_file = dup(stdin_fd_in);
        if (stdin_file < 0) goto fail;
    }
    if (stdout_mode == 3) {
        stdout_file = dup(stdout_fd_in);
        if (stdout_file < 0) goto fail;
    }
    if (stderr_mode == 3) {
        stderr_file = dup(stderr_fd_in);
        if (stderr_file < 0) goto fail;
    }

    // Open /dev/null if any mode is Null(2)
    if (stdin_mode == 2 || stdout_mode == 2 || stderr_mode == 2) {
        null_fd = open("/dev/null", O_RDWR);
        if (null_fd < 0) goto fail;
    }

    // Build null-terminated argv array
    char** child_argv = (char**)malloc((argc + 1) * sizeof(char*));
    if (!child_argv) goto fail;
    for (int i = 0; i < argc; i++) {
        child_argv[i] = (char*)argv[i];
    }
    child_argv[argc] = NULL;

    // Build null-terminated envp array. envc < 0 means "inherit the caller's
    // environment" (envp ignored); envc >= 0 means envp holds the child's
    // COMPLETE environment, and envc == 0 means an explicitly empty one.
    char** child_envp = NULL;
    if (envc >= 0) {
        child_envp = (char**)malloc((envc + 1) * sizeof(char*));
        if (!child_envp) { free(child_argv); goto fail; }
        for (int i = 0; i < envc; i++) {
            child_envp[i] = (char*)envp[i];
        }
        child_envp[envc] = NULL;
    }

    // Check if cwd is set
    int use_cwd = (cwd && cwd[0]);

    // Resolve bare program names through the child's PATH up front: this keeps
    // exec semantics identical with and without an explicit environment.
    char* resolved_program =
        __koral_resolve_program((const char*)program, child_envp, use_cwd ? (const char*)cwd : NULL);
    if (!resolved_program) {
        free(child_argv);
        if (child_envp) free(child_envp);
        goto fail;
    }

    // Use fork+exec if cwd is set (posix_spawn_file_actions_addchdir_np
    // is not portable), otherwise use posix_spawn
    pid_t child_pid;
    int spawn_err = 0;

    if (use_cwd) {
        // fork+exec approach for cwd support. A CLOEXEC error pipe carries the
        // failing errno from chdir/exec back to the parent, so failures surface
        // as a spawn error instead of a fake exit code 127.
        int err_pipe[2] = {-1, -1};
        if (pipe(err_pipe) < 0) {
            spawn_err = errno;
            free(child_argv);
            if (child_envp) free(child_envp);
            free(resolved_program);
            goto fail;
        }
        if (fcntl(err_pipe[1], F_SETFD, FD_CLOEXEC) < 0) {
            spawn_err = errno;
            close(err_pipe[0]);
            close(err_pipe[1]);
            free(child_argv);
            if (child_envp) free(child_envp);
            free(resolved_program);
            goto fail;
        }

        child_pid = fork();
        if (child_pid < 0) {
            spawn_err = errno;
            close(err_pipe[0]);
            close(err_pipe[1]);
            free(child_argv);
            if (child_envp) free(child_envp);
            free(resolved_program);
            goto fail;
        }
        if (child_pid == 0) {
            // Child process
            int report_fd = err_pipe[1];
            close(err_pipe[0]);
            // Keep the report fd clear of the stdio descriptors the code below
            // rewires, in case the parent came in with one of them closed.
            if (report_fd >= 0 && report_fd <= STDERR_FILENO) {
                int high = fcntl(report_fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
                if (high >= 0) {
                    close(report_fd);
                    report_fd = high;
                }
            }
#define KORAL_SPAWN_CHILD_FAIL(errn) \
    do { int e_ = (errn); (void)!write(report_fd, &e_, sizeof(e_)); _exit(127); } while (0)
            if (setpgid(0, 0) < 0) KORAL_SPAWN_CHILD_FAIL(errno);
            if (chdir((const char*)cwd) < 0) KORAL_SPAWN_CHILD_FAIL(errno);

            // Set up stdin
            if (stdin_mode == 1) {
                dup2(stdin_pipe[0], STDIN_FILENO);
                close(stdin_pipe[0]);
                close(stdin_pipe[1]);
            } else if (stdin_mode == 2) {
                dup2(null_fd, STDIN_FILENO);
            } else if (stdin_mode == 3) {
                dup2(stdin_file, STDIN_FILENO);
                close(stdin_file);
            }

            // Set up stdout
            if (stdout_mode == 1) {
                dup2(stdout_pipe[1], STDOUT_FILENO);
                close(stdout_pipe[0]);
                close(stdout_pipe[1]);
            } else if (stdout_mode == 2) {
                dup2(null_fd, STDOUT_FILENO);
            } else if (stdout_mode == 3) {
                dup2(stdout_file, STDOUT_FILENO);
                close(stdout_file);
            }

            // Set up stderr
            if (stderr_mode == 1) {
                dup2(stderr_pipe[1], STDERR_FILENO);
                close(stderr_pipe[0]);
                close(stderr_pipe[1]);
            } else if (stderr_mode == 2) {
                dup2(null_fd, STDERR_FILENO);
            } else if (stderr_mode == 3) {
                dup2(stderr_file, STDERR_FILENO);
                close(stderr_file);
            }

            if (null_fd >= 0) close(null_fd);

            execve(resolved_program, child_argv, child_envp ? child_envp : environ);
            KORAL_SPAWN_CHILD_FAIL(errno);
#undef KORAL_SPAWN_CHILD_FAIL
        }

        // Parent: a child-side failure writes its errno before _exit; a clean
        // exec closes the pipe end (CLOEXEC) and read() returns 0.
        close(err_pipe[1]);
        int child_err = 0;
        ssize_t nread = read(err_pipe[0], &child_err, sizeof(child_err));
        close(err_pipe[0]);
        if (nread == (ssize_t)sizeof(child_err)) {
            spawn_err = child_err;
            waitpid(child_pid, NULL, 0);
            free(child_argv);
            if (child_envp) free(child_envp);
            free(resolved_program);
            goto fail;
        }
    } else {
        // posix_spawn approach (more efficient, no fork overhead)
        posix_spawn_file_actions_t actions;
        posix_spawnattr_t attr;
        posix_spawn_file_actions_init(&actions);
        posix_spawnattr_init(&attr);

        short spawn_flags = 0;
#if defined(POSIX_SPAWN_SETPGROUP)
        if (posix_spawnattr_setpgroup(&attr, 0) == 0) {
            spawn_flags |= POSIX_SPAWN_SETPGROUP;
        }
#endif
        if (spawn_flags != 0) {
            posix_spawnattr_setflags(&attr, spawn_flags);
        }

        // stdin
        if (stdin_mode == 1) {
            posix_spawn_file_actions_adddup2(&actions, stdin_pipe[0], STDIN_FILENO);
            posix_spawn_file_actions_addclose(&actions, stdin_pipe[0]);
            posix_spawn_file_actions_addclose(&actions, stdin_pipe[1]);
        } else if (stdin_mode == 2) {
            posix_spawn_file_actions_adddup2(&actions, null_fd, STDIN_FILENO);
        } else if (stdin_mode == 3) {
            posix_spawn_file_actions_adddup2(&actions, stdin_file, STDIN_FILENO);
            posix_spawn_file_actions_addclose(&actions, stdin_file);
        }

        // stdout
        if (stdout_mode == 1) {
            posix_spawn_file_actions_adddup2(&actions, stdout_pipe[1], STDOUT_FILENO);
            posix_spawn_file_actions_addclose(&actions, stdout_pipe[0]);
            posix_spawn_file_actions_addclose(&actions, stdout_pipe[1]);
        } else if (stdout_mode == 2) {
            posix_spawn_file_actions_adddup2(&actions, null_fd, STDOUT_FILENO);
        } else if (stdout_mode == 3) {
            posix_spawn_file_actions_adddup2(&actions, stdout_file, STDOUT_FILENO);
            posix_spawn_file_actions_addclose(&actions, stdout_file);
        }

        // stderr
        if (stderr_mode == 1) {
            posix_spawn_file_actions_adddup2(&actions, stderr_pipe[1], STDERR_FILENO);
            posix_spawn_file_actions_addclose(&actions, stderr_pipe[0]);
            posix_spawn_file_actions_addclose(&actions, stderr_pipe[1]);
        } else if (stderr_mode == 2) {
            posix_spawn_file_actions_adddup2(&actions, null_fd, STDERR_FILENO);
        } else if (stderr_mode == 3) {
            posix_spawn_file_actions_adddup2(&actions, stderr_file, STDERR_FILENO);
            posix_spawn_file_actions_addclose(&actions, stderr_file);
        }

        if (null_fd >= 0) {
            posix_spawn_file_actions_addclose(&actions, null_fd);
        }

        // resolved_program always contains a '/', so posix_spawn never
        // re-searches PATH and the resolution above is the single search site.
        spawn_err = posix_spawn(&child_pid, resolved_program, &actions, &attr,
                                child_argv, child_envp ? child_envp : environ);

        posix_spawn_file_actions_destroy(&actions);
        posix_spawnattr_destroy(&attr);
    }

    free(child_argv);
    if (child_envp) free(child_envp);
    free(resolved_program);

    if (spawn_err != 0) {
        errno = spawn_err;
        goto fail;
    }

    // Close child-side pipe ends in parent
    if (stdin_pipe[0] >= 0) close(stdin_pipe[0]);
    if (stdout_pipe[1] >= 0) close(stdout_pipe[1]);
    if (stderr_pipe[1] >= 0) close(stderr_pipe[1]);
    if (stdin_file >= 0) close(stdin_file);
    if (stdout_file >= 0) close(stdout_file);
    if (stderr_file >= 0) close(stderr_file);
    if (null_fd >= 0) close(null_fd);

    out->pid = (uint32_t)child_pid;
    out->stdin_fd = stdin_pipe[1];   // parent writes to stdin_pipe[1]
    out->stdout_fd = stdout_pipe[0]; // parent reads from stdout_pipe[0]
    out->stderr_fd = stderr_pipe[0]; // parent reads from stderr_pipe[0]

    return 0;

fail:
    if (stdin_pipe[0] >= 0) close(stdin_pipe[0]);
    if (stdin_pipe[1] >= 0) close(stdin_pipe[1]);
    if (stdout_pipe[0] >= 0) close(stdout_pipe[0]);
    if (stdout_pipe[1] >= 0) close(stdout_pipe[1]);
    if (stderr_pipe[0] >= 0) close(stderr_pipe[0]);
    if (stderr_pipe[1] >= 0) close(stderr_pipe[1]);
    if (stdin_file >= 0) close(stdin_file);
    if (stdout_file >= 0) close(stdout_file);
    if (stderr_file >= 0) close(stderr_file);
    if (null_fd >= 0) close(null_fd);
    return -1;
}

#endif  // _WIN32 / POSIX __koral_spawn


// --- __koral_read_all_pipes ---
// Reads all data from stdout_fd and stderr_fd concurrently.
// Allocates memory for output buffers (caller must free with free()).
// Returns 0 on success, -1 on error.

// Dynamic buffer helper for __koral_read_all_pipes
typedef struct {
    uint8_t* data;
    uint64_t len;
    uint64_t cap;
} DynBuf;

static void dynbuf_init(DynBuf* b) {
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

static int dynbuf_append(DynBuf* b, const uint8_t* src, uint64_t n) {
    if (n == 0) return 0;
    if (b->len + n > b->cap) {
        uint64_t new_cap = b->cap == 0 ? 4096 : b->cap;
        while (new_cap < b->len + n) new_cap *= 2;
        uint8_t* new_data = (uint8_t*)realloc(b->data, (size_t)new_cap);
        if (!new_data) return -1;
        b->data = new_data;
        b->cap = new_cap;
    }
    memcpy(b->data + b->len, src, (size_t)n);
    b->len += n;
    return 0;
}

#if defined(_WIN32) || defined(_WIN64)
typedef struct {
    int32_t fd;
    DynBuf* buf;
    int error;
} KoralPipeReadThreadCtx;

static DWORD WINAPI __koral_read_pipe_thread_win(LPVOID arg) {
    KoralPipeReadThreadCtx* ctx = (KoralPipeReadThreadCtx*)arg;
    uint8_t tmp[4096];

    while (1) {
        int64_t n = __koral_pipe_read(ctx->fd, tmp, sizeof(tmp));
        if (n < 0) {
            ctx->error = 1;
            return 1;
        }
        if (n == 0) {
            return 0;
        }
        if (dynbuf_append(ctx->buf, tmp, (uint64_t)n) < 0) {
            ctx->error = 1;
            return 1;
        }
    }
}
#endif

int32_t __koral_read_all_pipes(int32_t stdout_fd, int32_t stderr_fd,
                              uint8_t** out_stdout, uint64_t* out_stdout_len,
                              uint8_t** out_stderr, uint64_t* out_stderr_len) {
    DynBuf stdout_buf, stderr_buf;
    dynbuf_init(&stdout_buf);
    dynbuf_init(&stderr_buf);

    *out_stdout = NULL;
    *out_stdout_len = 0;
    *out_stderr = NULL;
    *out_stderr_len = 0;

    uint8_t tmp[4096];

    // If both fds are invalid, nothing to do
    if (stdout_fd < 0 && stderr_fd < 0) return 0;

    // If only one fd is valid, just read it sequentially
    if (stdout_fd < 0) {
        while (1) {
            int64_t n = __koral_pipe_read(stderr_fd, tmp, sizeof(tmp));
            if (n < 0) goto fail;
            if (n == 0) break;
            if (dynbuf_append(&stderr_buf, tmp, (uint64_t)n) < 0) goto fail;
        }
        goto done;
    }
    if (stderr_fd < 0) {
        while (1) {
            int64_t n = __koral_pipe_read(stdout_fd, tmp, sizeof(tmp));
            if (n < 0) goto fail;
            if (n == 0) break;
            if (dynbuf_append(&stdout_buf, tmp, (uint64_t)n) < 0) goto fail;
        }
        goto done;
    }

    // Both fds valid: use poll (POSIX) or sequential read (Windows)
#if defined(_WIN32) || defined(_WIN64)
    {
        KoralPipeReadThreadCtx stdout_ctx;
        KoralPipeReadThreadCtx stderr_ctx;
        stdout_ctx.fd = stdout_fd;
        stdout_ctx.buf = &stdout_buf;
        stdout_ctx.error = 0;
        stderr_ctx.fd = stderr_fd;
        stderr_ctx.buf = &stderr_buf;
        stderr_ctx.error = 0;

        HANDLE stdout_thread = CreateThread(NULL, 0, __koral_read_pipe_thread_win, &stdout_ctx, 0, NULL);
        if (stdout_thread == NULL) goto fail;

        HANDLE stderr_thread = CreateThread(NULL, 0, __koral_read_pipe_thread_win, &stderr_ctx, 0, NULL);
        if (stderr_thread == NULL) {
            WaitForSingleObject(stdout_thread, INFINITE);
            CloseHandle(stdout_thread);
            goto fail;
        }

        if (WaitForSingleObject(stdout_thread, INFINITE) != WAIT_OBJECT_0) {
            CloseHandle(stdout_thread);
            CloseHandle(stderr_thread);
            goto fail;
        }
        if (WaitForSingleObject(stderr_thread, INFINITE) != WAIT_OBJECT_0) {
            CloseHandle(stdout_thread);
            CloseHandle(stderr_thread);
            goto fail;
        }

        CloseHandle(stdout_thread);
        CloseHandle(stderr_thread);

        if (stdout_ctx.error || stderr_ctx.error) goto fail;
    }
#else
    {
        struct pollfd fds[2];
        int nfds = 2;
        int stdout_open = 1, stderr_open = 1;

        fds[0].fd = stdout_fd;
        fds[0].events = POLLIN;
        fds[1].fd = stderr_fd;
        fds[1].events = POLLIN;

        while (stdout_open || stderr_open) {
            if (!stdout_open) fds[0].fd = -1;
            if (!stderr_open) fds[1].fd = -1;

            int ret = poll(fds, nfds, -1);
            if (ret < 0) {
                if (errno == EINTR) continue;
                goto fail;
            }

            if (fds[0].revents & (POLLIN | POLLHUP)) {
                int64_t n = read(stdout_fd, tmp, sizeof(tmp));
                if (n < 0 && errno != EINTR) goto fail;
                if (n <= 0) {
                    stdout_open = 0;
                } else {
                    if (dynbuf_append(&stdout_buf, tmp, (uint64_t)n) < 0) goto fail;
                }
            }

            if (fds[1].revents & (POLLIN | POLLHUP)) {
                int64_t n = read(stderr_fd, tmp, sizeof(tmp));
                if (n < 0 && errno != EINTR) goto fail;
                if (n <= 0) {
                    stderr_open = 0;
                } else {
                    if (dynbuf_append(&stderr_buf, tmp, (uint64_t)n) < 0) goto fail;
                }
            }
        }
    }
#endif

done:
    *out_stdout = stdout_buf.data;
    *out_stdout_len = stdout_buf.len;
    *out_stderr = stderr_buf.data;
    *out_stderr_len = stderr_buf.len;
    return 0;

fail:
    if (stdout_buf.data) free(stdout_buf.data);
    if (stderr_buf.data) free(stderr_buf.data);
    return -1;
}

// ============================================================================
// Thread management (std.task)
// ============================================================================

#if !defined(_WIN32) && !defined(_WIN64)
#include <pthread.h>
#include <sched.h>
#include <unistd.h>
#endif

// Invoke a Koral closure: if env is NULL, call as void(*)(void); otherwise call as void(*)(void*).
static void __koral_closure_invoke(struct __koral_Closure* c) {
    if (c->env == NULL) {
        ((void(*)(void))(c->fn))();
    } else {
        ((void(*)(void*))(c->fn))(c->env);
    }
}

// --- Thread trampoline context ---

typedef struct {
    struct __koral_Closure closure;
} KoralThreadArgs;

#if defined(_WIN32) || defined(_WIN64)

// --- Windows thread trampoline ---
static DWORD WINAPI __koral_thread_trampoline_win(LPVOID arg) {
    KoralThreadArgs* args = (KoralThreadArgs*)arg;
    __koral_closure_invoke(&args->closure);
    __koral_closure_release(args->closure);
    free(args);
    return 0;
}

int32_t __koral_spawn_thread(uint8_t** out_handle, uint64_t* out_tid,
                            struct __koral_Closure closure, uint64_t stack_size) {
    KoralThreadArgs* args = (KoralThreadArgs*)malloc(sizeof(KoralThreadArgs));
    if (!args) return -1;
    args->closure = closure;
    __koral_closure_retain(args->closure);

    SIZE_T win_stack_size = (stack_size > 0) ? (SIZE_T)stack_size : 0;
    HANDLE h = CreateThread(NULL, win_stack_size, __koral_thread_trampoline_win, args, 0, NULL);
    if (h == NULL) {
        __koral_closure_release(args->closure);
        free(args);
        return -1;
    }
    *out_handle = (uint8_t*)h;
    *out_tid = (uint64_t)GetThreadId(h);
    return 0;
}

int32_t __koral_thread_join(uint8_t* handle) {
    // A thread waiting on itself would block forever: pthread_join reports
    // EDEADLK, but Windows has no equivalent, so ask the question first.
    // The handle stays open on failure so the join is retryable -- the same
    // contract the POSIX side has (it never closes the handle either).
    if (GetThreadId((HANDLE)handle) == GetCurrentThreadId()) {
        return -1;
    }
    DWORD result = WaitForSingleObject((HANDLE)handle, INFINITE);
    if (result != WAIT_OBJECT_0) {
        return -1;
    }
    CloseHandle((HANDLE)handle);
    return 0;
}

void __koral_thread_detach(uint8_t* handle) {
    CloseHandle((HANDLE)handle);
}

uint64_t __koral_thread_current_id(void) {
    return (uint64_t)GetCurrentThreadId();
}

void __koral_thread_yield(void) {
    SwitchToThread();
}

uint32_t __koral_hardware_concurrency(void) {
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return (uint32_t)si.dwNumberOfProcessors;
}

#else

// --- POSIX thread trampoline ---
static void* __koral_thread_trampoline_posix(void* arg) {
    KoralThreadArgs* args = (KoralThreadArgs*)arg;
    __koral_closure_invoke(&args->closure);
    __koral_closure_release(args->closure);
    free(args);
    return NULL;
}

int32_t __koral_spawn_thread(uint8_t** out_handle, uint64_t* out_tid,
                            struct __koral_Closure closure, uint64_t stack_size) {
    KoralThreadArgs* args = (KoralThreadArgs*)malloc(sizeof(KoralThreadArgs));
    if (!args) return -1;
    args->closure = closure;
    __koral_closure_retain(args->closure);

    pthread_attr_t attr;
    pthread_attr_t* attr_ptr = NULL;
    if (stack_size > 0) {
        pthread_attr_init(&attr);
        pthread_attr_setstacksize(&attr, (size_t)stack_size);
        attr_ptr = &attr;
    }

    pthread_t thread;
    int err = pthread_create(&thread, attr_ptr, __koral_thread_trampoline_posix, args);
    if (attr_ptr) {
        pthread_attr_destroy(&attr);
    }
    if (err != 0) {
        __koral_closure_release(args->closure);
        free(args);
        return -1;
    }
    *out_handle = (uint8_t*)thread;
    *out_tid = (uint64_t)thread;
    return 0;
}

int32_t __koral_thread_join(uint8_t* handle) {
    return pthread_join((pthread_t)handle, NULL) == 0 ? 0 : -1;
}

void __koral_thread_detach(uint8_t* handle) {
    pthread_detach((pthread_t)handle);
}

uint64_t __koral_thread_current_id(void) {
    return (uint64_t)pthread_self();
}

void __koral_thread_yield(void) {
    sched_yield();
}

uint32_t __koral_hardware_concurrency(void) {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return (n > 0) ? (uint32_t)n : 1;
}

#endif

// ============================================================================
// Short object lock (concurrency-design.md §对象锁语义)
// ============================================================================

void __koral_lock_init(struct __koral_Lock* lock) {
    atomic_store_explicit(&lock->held, 0, memory_order_relaxed);
    lock->reserved = 0;
}

void __koral_lock_acquire(struct __koral_Lock* lock) {
    for (;;) {
        uint32_t expected = 0;
        if (atomic_compare_exchange_weak_explicit(&lock->held, &expected, 1,
                memory_order_acquire, memory_order_relaxed)) {
            return;
        }
        // Contended: the critical section is one machine-level access, so
        // yielding out is cheaper than a futex round-trip here.
        __koral_thread_yield();
    }
}

void __koral_lock_release(struct __koral_Lock* lock) {
    atomic_store_explicit(&lock->held, 0, memory_order_release);
}

// ============================================================================
// Scalar slot atomics (concurrency-design.md §对象锁语义)
// ============================================================================
// Timer context management (std.task)
// ============================================================================

typedef struct {
    volatile int cancelled;
#if defined(_WIN32) || defined(_WIN64)
    HANDLE event;
#else
    pthread_mutex_t mutex;
    pthread_cond_t cond;
#endif
} KoralTimerContext;

#if defined(_WIN32) || defined(_WIN64)

void* __koral_timer_context_create(void) {
    KoralTimerContext* ctx = (KoralTimerContext*)malloc(sizeof(KoralTimerContext));
    if (!ctx) return NULL;
    ctx->cancelled = 0;
    ctx->event = CreateEventA(NULL, TRUE, FALSE, NULL);  // manual-reset, initially non-signaled
    if (ctx->event == NULL) {
        free(ctx);
        return NULL;
    }
    return (void*)ctx;
}

void __koral_timer_context_cancel(void* raw) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    InterlockedExchange((volatile LONG*)&ctx->cancelled, 1);
    SetEvent(ctx->event);
}

void __koral_timer_context_destroy(void* raw) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    CloseHandle(ctx->event);
    free(ctx);
}

int32_t __koral_timer_sleep(void* raw, int64_t secs, int64_t nanos) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    // Check if already cancelled before sleeping
    if (*(volatile int*)&ctx->cancelled) return 1;
    // Convert to milliseconds
    DWORD timeout_ms = (DWORD)(secs * 1000 + nanos / 1000000);
    DWORD result = WaitForSingleObject(ctx->event, timeout_ms);
    if (result == WAIT_OBJECT_0) {
        // Event was signaled (cancelled)
        return 1;
    }
    // WAIT_TIMEOUT or other: check cancelled flag in case of spurious wake
    if (*(volatile int*)&ctx->cancelled) return 1;
    return 0;
}

#else

void* __koral_timer_context_create(void) {
    KoralTimerContext* ctx = (KoralTimerContext*)malloc(sizeof(KoralTimerContext));
    if (!ctx) return NULL;
    ctx->cancelled = 0;
    if (pthread_mutex_init(&ctx->mutex, NULL) != 0) {
        free(ctx);
        return NULL;
    }
    if (pthread_cond_init(&ctx->cond, NULL) != 0) {
        pthread_mutex_destroy(&ctx->mutex);
        free(ctx);
        return NULL;
    }
    return (void*)ctx;
}

void __koral_timer_context_cancel(void* raw) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    __atomic_store_n(&ctx->cancelled, 1, __ATOMIC_RELEASE);
    pthread_mutex_lock(&ctx->mutex);
    pthread_cond_signal(&ctx->cond);
    pthread_mutex_unlock(&ctx->mutex);
}

void __koral_timer_context_destroy(void* raw) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    pthread_cond_destroy(&ctx->cond);
    pthread_mutex_destroy(&ctx->mutex);
    free(ctx);
}

int32_t __koral_timer_sleep(void* raw, int64_t secs, int64_t nanos) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    // Check if already cancelled before sleeping
    if (__atomic_load_n(&ctx->cancelled, __ATOMIC_ACQUIRE)) return 1;

    // Compute absolute timeout using CLOCK_REALTIME
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += (time_t)secs;
    ts.tv_nsec += (long)nanos;
    // Normalize: carry over nanoseconds to seconds
    if (ts.tv_nsec >= 1000000000L) {
        ts.tv_sec += ts.tv_nsec / 1000000000L;
        ts.tv_nsec = ts.tv_nsec % 1000000000L;
    }

    pthread_mutex_lock(&ctx->mutex);
    while (!__atomic_load_n(&ctx->cancelled, __ATOMIC_ACQUIRE)) {
        int rc = pthread_cond_timedwait(&ctx->cond, &ctx->mutex, &ts);
        if (rc == ETIMEDOUT) {
            // Timeout expired — slept the full duration
            pthread_mutex_unlock(&ctx->mutex);
            // Final check: might have been cancelled just before timeout
            if (__atomic_load_n(&ctx->cancelled, __ATOMIC_ACQUIRE)) return 1;
            return 0;
        }
        // Spurious wakeup or signal: loop back and re-check cancelled flag
    }
    pthread_mutex_unlock(&ctx->mutex);
    return 1;  // cancelled
}

#endif

// ============================================================================
// Sync primitives: Mutex, SharedMutex, Condvar, Atomics
// ============================================================================

// --- Condvar struct for POSIX (needs internal mutex + generation for shared mutex wait) ---
#if !defined(_WIN32) && !defined(_WIN64)

typedef struct {
    pthread_cond_t cond;
    pthread_mutex_t internal_mutex;  // for shared mutex wait
    volatile int generation;         // for shared mutex wait
} KoralCondvar;

#else

typedef struct {
    CONDITION_VARIABLE cv;
} KoralCondvar;

#endif

// ============================================================================
// Mutex
// ============================================================================

#if defined(_WIN32) || defined(_WIN64)

// SRWLOCK, not CRITICAL_SECTION: a CRITICAL_SECTION is recursive, so the same
// thread that already holds it can TryEnter it again and the call succeeds.
// That contradicts `Mutex.try_lock`, whose documented contract is "succeeds on
// an unheld lock, false when the lock is occupied" -- and it contradicts the
// POSIX side of this file, where a default `pthread_mutex_t` is non-recursive.
// `std_handle_types_are_mutable` asserts exactly this: after `m.lock()`, an
// alias's `try_lock()` must fail. SharedMutex already used SRWLOCK; Mutex now
// matches it (and so do the condvar waits below).
void* __koral_mutex_create(void) {
    SRWLOCK* lock = (SRWLOCK*)malloc(sizeof(SRWLOCK));
    if (!lock) return NULL;
    InitializeSRWLock(lock);
    return (void*)lock;
}

void __koral_mutex_destroy(void* mutex) {
    if (!mutex) return;
    // SRWLOCK needs no destroy
    free(mutex);
}

void __koral_mutex_lock(void* mutex) {
    AcquireSRWLockExclusive((SRWLOCK*)mutex);
}

int32_t __koral_mutex_try_lock(void* mutex) {
    return TryAcquireSRWLockExclusive((SRWLOCK*)mutex) ? 1 : 0;
}

void __koral_mutex_unlock(void* mutex) {
    ReleaseSRWLockExclusive((SRWLOCK*)mutex);
}

#else

void* __koral_mutex_create(void) {
    pthread_mutex_t* m = (pthread_mutex_t*)malloc(sizeof(pthread_mutex_t));
    if (!m) return NULL;
    if (pthread_mutex_init(m, NULL) != 0) {
        free(m);
        return NULL;
    }
    return (void*)m;
}

void __koral_mutex_destroy(void* mutex) {
    if (!mutex) return;
    pthread_mutex_destroy((pthread_mutex_t*)mutex);
    free(mutex);
}

void __koral_mutex_lock(void* mutex) {
    pthread_mutex_lock((pthread_mutex_t*)mutex);
}

int32_t __koral_mutex_try_lock(void* mutex) {
    return pthread_mutex_trylock((pthread_mutex_t*)mutex) == 0 ? 1 : 0;
}

void __koral_mutex_unlock(void* mutex) {
    pthread_mutex_unlock((pthread_mutex_t*)mutex);
}

#endif


// ============================================================================
// SharedMutex
// ============================================================================

#if defined(_WIN32) || defined(_WIN64)

void* __koral_shared_mutex_create(void) {
    SRWLOCK* lock = (SRWLOCK*)malloc(sizeof(SRWLOCK));
    if (!lock) return NULL;
    InitializeSRWLock(lock);
    return (void*)lock;
}

void __koral_shared_mutex_destroy(void* shared_mutex) {
    if (!shared_mutex) return;
    // SRWLOCK needs no destroy
    free(shared_mutex);
}

void __koral_shared_mutex_read_lock(void* shared_mutex) {
    AcquireSRWLockShared((SRWLOCK*)shared_mutex);
}

void __koral_shared_mutex_read_unlock(void* shared_mutex) {
    ReleaseSRWLockShared((SRWLOCK*)shared_mutex);
}

void __koral_shared_mutex_write_lock(void* shared_mutex) {
    AcquireSRWLockExclusive((SRWLOCK*)shared_mutex);
}

void __koral_shared_mutex_write_unlock(void* shared_mutex) {
    ReleaseSRWLockExclusive((SRWLOCK*)shared_mutex);
}

int32_t __koral_shared_mutex_try_read_lock(void* shared_mutex) {
    return TryAcquireSRWLockShared((SRWLOCK*)shared_mutex) ? 1 : 0;
}

int32_t __koral_shared_mutex_try_write_lock(void* shared_mutex) {
    return TryAcquireSRWLockExclusive((SRWLOCK*)shared_mutex) ? 1 : 0;
}

#else

void* __koral_shared_mutex_create(void) {
    pthread_rwlock_t* rw = (pthread_rwlock_t*)malloc(sizeof(pthread_rwlock_t));
    if (!rw) return NULL;
    pthread_rwlockattr_t attr;
    pthread_rwlockattr_init(&attr);
#ifdef PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP
    pthread_rwlockattr_setkind_np(&attr, PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP);
#endif
    if (pthread_rwlock_init(rw, &attr) != 0) {
        pthread_rwlockattr_destroy(&attr);
        free(rw);
        return NULL;
    }
    pthread_rwlockattr_destroy(&attr);
    return (void*)rw;
}

void __koral_shared_mutex_destroy(void* shared_mutex) {
    if (!shared_mutex) return;
    pthread_rwlock_destroy((pthread_rwlock_t*)shared_mutex);
    free(shared_mutex);
}

void __koral_shared_mutex_read_lock(void* shared_mutex) {
    pthread_rwlock_rdlock((pthread_rwlock_t*)shared_mutex);
}

void __koral_shared_mutex_read_unlock(void* shared_mutex) {
    pthread_rwlock_unlock((pthread_rwlock_t*)shared_mutex);
}

void __koral_shared_mutex_write_lock(void* shared_mutex) {
    pthread_rwlock_wrlock((pthread_rwlock_t*)shared_mutex);
}

void __koral_shared_mutex_write_unlock(void* shared_mutex) {
    pthread_rwlock_unlock((pthread_rwlock_t*)shared_mutex);
}

int32_t __koral_shared_mutex_try_read_lock(void* shared_mutex) {
    return pthread_rwlock_tryrdlock((pthread_rwlock_t*)shared_mutex) == 0 ? 1 : 0;
}

int32_t __koral_shared_mutex_try_write_lock(void* shared_mutex) {
    return pthread_rwlock_trywrlock((pthread_rwlock_t*)shared_mutex) == 0 ? 1 : 0;
}

#endif


// ============================================================================
// Condvar
// ============================================================================

#if defined(_WIN32) || defined(_WIN64)

void* __koral_condvar_create(void) {
    KoralCondvar* cv = (KoralCondvar*)malloc(sizeof(KoralCondvar));
    if (!cv) return NULL;
    InitializeConditionVariable(&cv->cv);
    return (void*)cv;
}

void __koral_condvar_destroy(void* raw) {
    if (!raw) return;
    // CONDITION_VARIABLE needs no destroy
    free(raw);
}

void __koral_condvar_wait(void* raw, void* mutex) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    // Mutex is an SRWLOCK (see __koral_mutex_create); 0 = exclusive mode.
    SleepConditionVariableSRW(&cv->cv, (SRWLOCK*)mutex, INFINITE, 0);
}

void __koral_condvar_signal(void* raw) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    WakeConditionVariable(&cv->cv);
}

void __koral_condvar_broadcast(void* raw) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    WakeAllConditionVariable(&cv->cv);
}

void __koral_condvar_wait_shared_mutex(void* raw, void* shared_mutex) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    // Last parameter 0 = exclusive mode (CONDITION_VARIABLE_LOCKMODE_SHARED not set)
    SleepConditionVariableSRW(&cv->cv, (SRWLOCK*)shared_mutex, INFINITE, 0);
}

#else

void* __koral_condvar_create(void) {
    KoralCondvar* cv = (KoralCondvar*)malloc(sizeof(KoralCondvar));
    if (!cv) return NULL;
    if (pthread_cond_init(&cv->cond, NULL) != 0) {
        free(cv);
        return NULL;
    }
    if (pthread_mutex_init(&cv->internal_mutex, NULL) != 0) {
        pthread_cond_destroy(&cv->cond);
        free(cv);
        return NULL;
    }
    cv->generation = 0;
    return (void*)cv;
}

void __koral_condvar_destroy(void* raw) {
    if (!raw) return;
    KoralCondvar* cv = (KoralCondvar*)raw;
    pthread_cond_destroy(&cv->cond);
    pthread_mutex_destroy(&cv->internal_mutex);
    free(cv);
}

void __koral_condvar_wait(void* raw, void* mutex) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    // Standard condvar wait with external mutex (pthread_mutex_t)
    pthread_cond_wait(&cv->cond, (pthread_mutex_t*)mutex);
}

void __koral_condvar_signal(void* raw) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    pthread_mutex_lock(&cv->internal_mutex);
    cv->generation++;
    pthread_cond_signal(&cv->cond);
    pthread_mutex_unlock(&cv->internal_mutex);
}

void __koral_condvar_broadcast(void* raw) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    pthread_mutex_lock(&cv->internal_mutex);
    cv->generation++;
    pthread_cond_broadcast(&cv->cond);
    pthread_mutex_unlock(&cv->internal_mutex);
}

void __koral_condvar_wait_shared_mutex(void* raw, void* shared_mutex) {
    KoralCondvar* cv = (KoralCondvar*)raw;
    // POSIX: pthread_cond_wait only works with pthread_mutex_t, not pthread_rwlock_t.
    // Use internal mutex + generation counter to avoid lost wakeups.
    pthread_mutex_lock(&cv->internal_mutex);
    int my_gen = cv->generation;
    // Release the write lock before waiting
    pthread_rwlock_unlock((pthread_rwlock_t*)shared_mutex);
    // Wait on internal cond+mutex until generation changes
    while (my_gen == cv->generation) {
        pthread_cond_wait(&cv->cond, &cv->internal_mutex);
    }
    pthread_mutex_unlock(&cv->internal_mutex);
    // Re-acquire the write lock
    pthread_rwlock_wrlock((pthread_rwlock_t*)shared_mutex);
}

#endif


// ============================================================================
// Socket module: Cross-platform socket operations (__koral_socket_*)
// ============================================================================

#if defined(_WIN32) || defined(_WIN64)

// winsock2.h and ws2tcpip.h already included at top of file

// Platform-specific socket constants
int32_t __koral_const_SOL_SOCKET(void) { return (int32_t)SOL_SOCKET; }
int32_t __koral_const_SO_REUSEADDR(void) { return (int32_t)SO_REUSEADDR; }
int32_t __koral_const_SO_BROADCAST(void) { return (int32_t)SO_BROADCAST; }
int32_t __koral_const_SO_RCVTIMEO(void) { return (int32_t)SO_RCVTIMEO; }
int32_t __koral_const_SO_SNDTIMEO(void) { return (int32_t)SO_SNDTIMEO; }
int32_t __koral_const_IPPROTO_TCP(void) { return (int32_t)IPPROTO_TCP; }
int32_t __koral_const_TCP_NODELAY(void) { return (int32_t)TCP_NODELAY; }
int32_t __koral_const_AF_INET(void) { return (int32_t)AF_INET; }
int32_t __koral_const_AF_INET6(void) { return (int32_t)AF_INET6; }
int32_t __koral_const_SOCK_STREAM(void) { return (int32_t)SOCK_STREAM; }
int32_t __koral_const_SOCK_DGRAM(void) { return (int32_t)SOCK_DGRAM; }

// Koral portable sockaddr format:
// - IPv4: 16 bytes  [0..1]=family(le), [2..3]=port(be), [4..7]=addr, rest=0
// - IPv6: 28 bytes  [0..1]=family(le), [2..3]=port(be), [4..7]=flow(be),
//                    [8..23]=addr, [24..27]=scope(be)
static int __koral_decode_sockaddr_portable(const uint8_t* addr, uint32_t addr_len,
                                           struct sockaddr_storage* out, socklen_t* out_len) {
    if (!addr || addr_len < 2 || !out || !out_len) {
        errno = EINVAL;
        return -1;
    }

    uint16_t family = (uint16_t)addr[0] | ((uint16_t)addr[1] << 8);
    memset(out, 0, sizeof(*out));

    if (family == (uint16_t)AF_INET) {
        if (addr_len < 8) {
            errno = EINVAL;
            return -1;
        }
        struct sockaddr_in* sa = (struct sockaddr_in*)out;
#if defined(__APPLE__)
        sa->sin_len = (uint8_t)sizeof(struct sockaddr_in);
#endif
        sa->sin_family = AF_INET;
        uint16_t port_host = ((uint16_t)addr[2] << 8) | (uint16_t)addr[3];
        sa->sin_port = htons(port_host);
        memcpy(&sa->sin_addr, addr + 4, 4);
        *out_len = (socklen_t)sizeof(struct sockaddr_in);
        return 0;
    }

    if (family == (uint16_t)AF_INET6) {
        if (addr_len < 24) {
            errno = EINVAL;
            return -1;
        }
        struct sockaddr_in6* sa6 = (struct sockaddr_in6*)out;
#if defined(__APPLE__)
        sa6->sin6_len = (uint8_t)sizeof(struct sockaddr_in6);
#endif
        sa6->sin6_family = AF_INET6;
        uint16_t port_host = ((uint16_t)addr[2] << 8) | (uint16_t)addr[3];
        sa6->sin6_port = htons(port_host);
        memcpy(&sa6->sin6_addr, addr + 8, 16);
        if (addr_len >= 28) {
            uint32_t scope_be = ((uint32_t)addr[24] << 24)
                              | ((uint32_t)addr[25] << 16)
                              | ((uint32_t)addr[26] << 8)
                              | (uint32_t)addr[27];
            sa6->sin6_scope_id = ntohl(scope_be);
        }
        *out_len = (socklen_t)sizeof(struct sockaddr_in6);
        return 0;
    }

    errno = EAFNOSUPPORT;
    return -1;
}

static int __koral_encode_sockaddr_portable(const struct sockaddr* sa, socklen_t sa_len,
                                           uint8_t* out, uint32_t* out_len) {
    if (!sa || !out_len) {
        errno = EINVAL;
        return -1;
    }

    if (sa->sa_family == AF_INET) {
        const struct sockaddr_in* in = (const struct sockaddr_in*)sa;
        uint32_t required = 16;
        if (*out_len < required || sa_len < (socklen_t)sizeof(struct sockaddr_in) || !out) {
            errno = EINVAL;
            return -1;
        }
        memset(out, 0, required);
        out[0] = (uint8_t)(AF_INET & 0xff);
        out[1] = (uint8_t)((AF_INET >> 8) & 0xff);
        uint16_t port_host = ntohs(in->sin_port);
        out[2] = (uint8_t)((port_host >> 8) & 0xff);
        out[3] = (uint8_t)(port_host & 0xff);
        memcpy(out + 4, &in->sin_addr, 4);
        *out_len = required;
        return 0;
    }

    if (sa->sa_family == AF_INET6) {
        const struct sockaddr_in6* in6 = (const struct sockaddr_in6*)sa;
        uint32_t required = 28;
        if (*out_len < required || sa_len < (socklen_t)sizeof(struct sockaddr_in6) || !out) {
            errno = EINVAL;
            return -1;
        }
        memset(out, 0, required);
        out[0] = (uint8_t)(AF_INET6 & 0xff);
        out[1] = (uint8_t)((AF_INET6 >> 8) & 0xff);
        uint16_t port_host = ntohs(in6->sin6_port);
        out[2] = (uint8_t)((port_host >> 8) & 0xff);
        out[3] = (uint8_t)(port_host & 0xff);
        memcpy(out + 8, &in6->sin6_addr, 16);
        uint32_t scope_be = htonl(in6->sin6_scope_id);
        out[24] = (uint8_t)((scope_be >> 24) & 0xff);
        out[25] = (uint8_t)((scope_be >> 16) & 0xff);
        out[26] = (uint8_t)((scope_be >> 8) & 0xff);
        out[27] = (uint8_t)(scope_be & 0xff);
        *out_len = required;
        return 0;
    }

    errno = EAFNOSUPPORT;
    return -1;
}

// Auto-init Winsock on first socket call
static INIT_ONCE koral_wsa_init_once = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK koral_wsa_init_func(PINIT_ONCE once, PVOID param, PVOID* ctx) {
    (void)once; (void)param; (void)ctx;
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    return TRUE;
}

static void koral_ensure_wsa(void) {
    InitOnceExecuteOnce(&koral_wsa_init_once, koral_wsa_init_func, NULL, NULL);
}

int64_t __koral_socket_create(int32_t domain, int32_t type, int32_t protocol) {
    koral_ensure_wsa();
    SOCKET s = socket(domain, type, protocol);
    if (s == INVALID_SOCKET) {
        errno = WSAGetLastError();
        return -1;
    }
    return (int64_t)s;
}

int32_t __koral_socket_close(int64_t fd) {
    if (closesocket((SOCKET)fd) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return 0;
}

int32_t __koral_socket_bind(int64_t fd, uint8_t* addr, uint32_t addr_len) {
    if (bind((SOCKET)fd, (const struct sockaddr*)addr, (int)addr_len) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return 0;
}

int32_t __koral_socket_listen(int64_t fd, int32_t backlog) {
    if (listen((SOCKET)fd, backlog) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return 0;
}

int64_t __koral_socket_accept(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    int alen = addr_len_out ? (int)*addr_len_out : 0;
    SOCKET s = accept((SOCKET)fd, (struct sockaddr*)addr_out, addr_len_out ? &alen : NULL);
    if (s == INVALID_SOCKET) {
        errno = WSAGetLastError();
        return -1;
    }
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return (int64_t)s;
}

int32_t __koral_socket_connect(int64_t fd, uint8_t* addr, uint32_t addr_len) {
    if (connect((SOCKET)fd, (const struct sockaddr*)addr, (int)addr_len) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return 0;
}

int64_t __koral_socket_send(int64_t fd, uint8_t* buf, uint64_t len, int32_t flags) {
    int n = send((SOCKET)fd, (const char*)buf, (int)len, flags);
    if (n == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return (int64_t)n;
}

int64_t __koral_socket_recv(int64_t fd, uint8_t* buf, uint64_t len, int32_t flags) {
    int n = recv((SOCKET)fd, (char*)buf, (int)len, flags);
    if (n == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return (int64_t)n;
}

int64_t __koral_socket_sendto(int64_t fd, uint8_t* buf, uint64_t len,
                            int32_t flags, uint8_t* addr, uint32_t addr_len) {
    int n = sendto((SOCKET)fd, (const char*)buf, (int)len, flags,
                   (const struct sockaddr*)addr, (int)addr_len);
    if (n == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return (int64_t)n;
}

int64_t __koral_socket_recvfrom(int64_t fd, uint8_t* buf, uint64_t len,
                              int32_t flags, uint8_t* addr_out, uint32_t* addr_len_out) {
    int alen = addr_len_out ? (int)*addr_len_out : 0;
    int n = recvfrom((SOCKET)fd, (char*)buf, (int)len, flags,
                     (struct sockaddr*)addr_out, addr_len_out ? &alen : NULL);
    if (n == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return (int64_t)n;
}

int32_t __koral_socket_shutdown(int64_t fd, int32_t how) {
    if (shutdown((SOCKET)fd, how) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return 0;
}

int32_t __koral_socket_setsockopt(int64_t fd, int32_t level, int32_t optname,
                                uint8_t* optval, uint32_t optlen) {
    if (setsockopt((SOCKET)fd, level, optname, (const char*)optval, (int)optlen) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    return 0;
}

int32_t __koral_socket_getsockopt(int64_t fd, int32_t level, int32_t optname,
                                uint8_t* optval, uint32_t* optlen) {
    int olen = optlen ? (int)*optlen : 0;
    if (getsockopt((SOCKET)fd, level, optname, (char*)optval, &olen) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    if (optlen) *optlen = (uint32_t)olen;
    return 0;
}

int32_t __koral_socket_getsockname(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    int alen = addr_len_out ? (int)*addr_len_out : 0;
    if (getsockname((SOCKET)fd, (struct sockaddr*)addr_out, &alen) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return 0;
}

int32_t __koral_socket_getpeername(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    int alen = addr_len_out ? (int)*addr_len_out : 0;
    if (getpeername((SOCKET)fd, (struct sockaddr*)addr_out, &alen) == SOCKET_ERROR) {
        errno = WSAGetLastError();
        return -1;
    }
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return 0;
}

#else  // POSIX

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>

// Platform-specific socket constants
int32_t __koral_const_SOL_SOCKET(void) { return (int32_t)SOL_SOCKET; }
int32_t __koral_const_SO_REUSEADDR(void) { return (int32_t)SO_REUSEADDR; }
int32_t __koral_const_SO_BROADCAST(void) { return (int32_t)SO_BROADCAST; }
int32_t __koral_const_SO_RCVTIMEO(void) { return (int32_t)SO_RCVTIMEO; }
int32_t __koral_const_SO_SNDTIMEO(void) { return (int32_t)SO_SNDTIMEO; }
int32_t __koral_const_IPPROTO_TCP(void) { return (int32_t)IPPROTO_TCP; }
int32_t __koral_const_TCP_NODELAY(void) { return (int32_t)TCP_NODELAY; }
int32_t __koral_const_AF_INET(void) { return (int32_t)AF_INET; }
int32_t __koral_const_AF_INET6(void) { return (int32_t)AF_INET6; }
int32_t __koral_const_SOCK_STREAM(void) { return (int32_t)SOCK_STREAM; }
int32_t __koral_const_SOCK_DGRAM(void) { return (int32_t)SOCK_DGRAM; }

// Koral portable sockaddr format:
// - IPv4: 16 bytes  [0..1]=family(le), [2..3]=port(be), [4..7]=addr, rest=0
// - IPv6: 28 bytes  [0..1]=family(le), [2..3]=port(be), [4..7]=flow(be),
//                    [8..23]=addr, [24..27]=scope(be)
static int __koral_decode_sockaddr_portable(const uint8_t* addr, uint32_t addr_len,
                                           struct sockaddr_storage* out, socklen_t* out_len) {
    if (!addr || addr_len < 2 || !out || !out_len) {
        errno = EINVAL;
        return -1;
    }

    uint16_t family = (uint16_t)addr[0] | ((uint16_t)addr[1] << 8);
    memset(out, 0, sizeof(*out));

    if (family == (uint16_t)AF_INET) {
        if (addr_len < 8) {
            errno = EINVAL;
            return -1;
        }
        struct sockaddr_in* sa = (struct sockaddr_in*)out;
#if defined(__APPLE__)
        sa->sin_len = (uint8_t)sizeof(struct sockaddr_in);
#endif
        sa->sin_family = AF_INET;
        uint16_t port_host = ((uint16_t)addr[2] << 8) | (uint16_t)addr[3];
        sa->sin_port = htons(port_host);
        memcpy(&sa->sin_addr, addr + 4, 4);
        *out_len = (socklen_t)sizeof(struct sockaddr_in);
        return 0;
    }

    if (family == (uint16_t)AF_INET6) {
        if (addr_len < 24) {
            errno = EINVAL;
            return -1;
        }
        struct sockaddr_in6* sa6 = (struct sockaddr_in6*)out;
#if defined(__APPLE__)
        sa6->sin6_len = (uint8_t)sizeof(struct sockaddr_in6);
#endif
        sa6->sin6_family = AF_INET6;
        uint16_t port_host = ((uint16_t)addr[2] << 8) | (uint16_t)addr[3];
        sa6->sin6_port = htons(port_host);
        memcpy(&sa6->sin6_addr, addr + 8, 16);
        if (addr_len >= 28) {
            uint32_t scope_be = ((uint32_t)addr[24] << 24)
                              | ((uint32_t)addr[25] << 16)
                              | ((uint32_t)addr[26] << 8)
                              | (uint32_t)addr[27];
            sa6->sin6_scope_id = ntohl(scope_be);
        }
        *out_len = (socklen_t)sizeof(struct sockaddr_in6);
        return 0;
    }

    errno = EAFNOSUPPORT;
    return -1;
}

static int __koral_encode_sockaddr_portable(const struct sockaddr* sa, socklen_t sa_len,
                                           uint8_t* out, uint32_t* out_len) {
    if (!sa || !out_len) {
        errno = EINVAL;
        return -1;
    }

    if (sa->sa_family == AF_INET) {
        const struct sockaddr_in* in = (const struct sockaddr_in*)sa;
        uint32_t required = 16;
        if (*out_len < required || sa_len < (socklen_t)sizeof(struct sockaddr_in) || !out) {
            errno = EINVAL;
            return -1;
        }
        memset(out, 0, required);
        out[0] = (uint8_t)(AF_INET & 0xff);
        out[1] = (uint8_t)((AF_INET >> 8) & 0xff);
        uint16_t port_host = ntohs(in->sin_port);
        out[2] = (uint8_t)((port_host >> 8) & 0xff);
        out[3] = (uint8_t)(port_host & 0xff);
        memcpy(out + 4, &in->sin_addr, 4);
        *out_len = required;
        return 0;
    }

    if (sa->sa_family == AF_INET6) {
        const struct sockaddr_in6* in6 = (const struct sockaddr_in6*)sa;
        uint32_t required = 28;
        if (*out_len < required || sa_len < (socklen_t)sizeof(struct sockaddr_in6) || !out) {
            errno = EINVAL;
            return -1;
        }
        memset(out, 0, required);
        out[0] = (uint8_t)(AF_INET6 & 0xff);
        out[1] = (uint8_t)((AF_INET6 >> 8) & 0xff);
        uint16_t port_host = ntohs(in6->sin6_port);
        out[2] = (uint8_t)((port_host >> 8) & 0xff);
        out[3] = (uint8_t)(port_host & 0xff);
        memcpy(out + 8, &in6->sin6_addr, 16);
        uint32_t scope_be = htonl(in6->sin6_scope_id);
        out[24] = (uint8_t)((scope_be >> 24) & 0xff);
        out[25] = (uint8_t)((scope_be >> 16) & 0xff);
        out[26] = (uint8_t)((scope_be >> 8) & 0xff);
        out[27] = (uint8_t)(scope_be & 0xff);
        *out_len = required;
        return 0;
    }

    errno = EAFNOSUPPORT;
    return -1;
}

int64_t __koral_socket_create(int32_t domain, int32_t type, int32_t protocol) {
    int s = socket(domain, type, protocol);
    if (s < 0) return -1;
    return (int64_t)s;
}

int32_t __koral_socket_close(int64_t fd) {
    return close((int)fd) == 0 ? 0 : -1;
}

int32_t __koral_socket_bind(int64_t fd, uint8_t* addr, uint32_t addr_len) {
    struct sockaddr_storage native_addr;
    socklen_t native_len = 0;
    if (__koral_decode_sockaddr_portable(addr, addr_len, &native_addr, &native_len) != 0) {
        return -1;
    }
    return bind((int)fd, (const struct sockaddr*)&native_addr, native_len) == 0 ? 0 : -1;
}

int32_t __koral_socket_listen(int64_t fd, int32_t backlog) {
    return listen((int)fd, backlog) == 0 ? 0 : -1;
}

int64_t __koral_socket_accept(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    struct sockaddr_storage native_addr;
    socklen_t alen = (socklen_t)sizeof(native_addr);
    int s = accept((int)fd, (struct sockaddr*)&native_addr, &alen);
    if (s < 0) return -1;
    if (addr_out && addr_len_out) {
        uint32_t cap = *addr_len_out;
        if (__koral_encode_sockaddr_portable((const struct sockaddr*)&native_addr, alen, addr_out, &cap) != 0) {
            close(s);
            return -1;
        }
        *addr_len_out = cap;
    }
    return (int64_t)s;
}

int32_t __koral_socket_connect(int64_t fd, uint8_t* addr, uint32_t addr_len) {
    struct sockaddr_storage native_addr;
    socklen_t native_len = 0;
    if (__koral_decode_sockaddr_portable(addr, addr_len, &native_addr, &native_len) != 0) {
        return -1;
    }
    return connect((int)fd, (const struct sockaddr*)&native_addr, native_len) == 0 ? 0 : -1;
}

int64_t __koral_socket_send(int64_t fd, uint8_t* buf, uint64_t len, int32_t flags) {
    ssize_t n = send((int)fd, buf, (size_t)len, flags);
    return (int64_t)n;
}

int64_t __koral_socket_recv(int64_t fd, uint8_t* buf, uint64_t len, int32_t flags) {
    ssize_t n = recv((int)fd, buf, (size_t)len, flags);
    return (int64_t)n;
}

int64_t __koral_socket_sendto(int64_t fd, uint8_t* buf, uint64_t len,
                            int32_t flags, uint8_t* addr, uint32_t addr_len) {
    struct sockaddr_storage native_addr;
    socklen_t native_len = 0;
    if (__koral_decode_sockaddr_portable(addr, addr_len, &native_addr, &native_len) != 0) {
        return -1;
    }
    ssize_t n = sendto((int)fd, buf, (size_t)len, flags,
                       (const struct sockaddr*)&native_addr, native_len);
    return (int64_t)n;
}

int64_t __koral_socket_recvfrom(int64_t fd, uint8_t* buf, uint64_t len,
                              int32_t flags, uint8_t* addr_out, uint32_t* addr_len_out) {
    struct sockaddr_storage native_addr;
    socklen_t alen = (socklen_t)sizeof(native_addr);
    ssize_t n = recvfrom((int)fd, buf, (size_t)len, flags,
                         (struct sockaddr*)&native_addr, &alen);
    if (n >= 0 && addr_out && addr_len_out) {
        uint32_t cap = *addr_len_out;
        if (__koral_encode_sockaddr_portable((const struct sockaddr*)&native_addr, alen, addr_out, &cap) != 0) {
            return -1;
        }
        *addr_len_out = cap;
    }
    return (int64_t)n;
}

int32_t __koral_socket_shutdown(int64_t fd, int32_t how) {
    if (shutdown((int)fd, how) == 0) {
        return 0;
    }
    if (errno == ENOTCONN) {
        return 0;
    }
    return -1;
}

int32_t __koral_socket_setsockopt(int64_t fd, int32_t level, int32_t optname,
                                uint8_t* optval, uint32_t optlen) {
    return setsockopt((int)fd, level, optname, optval, (socklen_t)optlen) == 0 ? 0 : -1;
}

int32_t __koral_socket_getsockopt(int64_t fd, int32_t level, int32_t optname,
                                uint8_t* optval, uint32_t* optlen) {
    socklen_t olen = optlen ? (socklen_t)*optlen : 0;
    if (getsockopt((int)fd, level, optname, optval, &olen) != 0) return -1;
    if (optlen) *optlen = (uint32_t)olen;
    return 0;
}

int32_t __koral_socket_getsockname(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    if (!addr_out || !addr_len_out) {
        errno = EINVAL;
        return -1;
    }
    struct sockaddr_storage native_addr;
    socklen_t alen = (socklen_t)sizeof(native_addr);
    if (getsockname((int)fd, (struct sockaddr*)&native_addr, &alen) != 0) return -1;
    uint32_t cap = *addr_len_out;
    if (__koral_encode_sockaddr_portable((const struct sockaddr*)&native_addr, alen, addr_out, &cap) != 0) {
        return -1;
    }
    *addr_len_out = cap;
    return 0;
}

int32_t __koral_socket_getpeername(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    if (!addr_out || !addr_len_out) {
        errno = EINVAL;
        return -1;
    }
    struct sockaddr_storage native_addr;
    socklen_t alen = (socklen_t)sizeof(native_addr);
    if (getpeername((int)fd, (struct sockaddr*)&native_addr, &alen) != 0) return -1;
    uint32_t cap = *addr_len_out;
    if (__koral_encode_sockaddr_portable((const struct sockaddr*)&native_addr, alen, addr_out, &cap) != 0) {
        return -1;
    }
    *addr_len_out = cap;
    return 0;
}

#endif  // _WIN32 || _WIN64

// ============================================================================
// Global-initializer support (accessor + state model)
// ============================================================================
// 每个全局自带动一次初始化（per-variable once），不再共用一把进程锁：认领走
// 状态字节的 CAS（0 -> 1），认领者跑初始化器，跑完以 release 发布 2。初始化器
// 跑在**无锁**状态下，所以它去碰别的全局、拿别的锁都不会形成锁序死锁。
// 同线程再入 = 初始化环：本线程的初始化栈认出名字，报
// `global initialization cycle: a -> b -> a`；他线程只是等发布，自旋让步
// （急切序在 main 体之前已把每个全局跑过一遍，这条等待路径基本不触发）。

void __koral_global_state_finish(uint8_t* state) {
    __atomic_store_n(state, 2, __ATOMIC_RELEASE);
}

// 认领初始化权：恰好一个调用者把 0 变成 1，输家走等待/环判定。
int32_t __koral_global_init_claim(uint8_t* state) {
    uint8_t expected = 0;
    return __atomic_compare_exchange_n(state, &expected, 1, 0, __ATOMIC_ACQ_REL,
                                       __ATOMIC_ACQUIRE) ? 1 : 0;
}

// The per-process hash seed. KORAL_HASH_SEED pins it (reproducible runs);
// otherwise the runtime draws one from the platform entropy source, once.
// Unseeded table hashing is invertible end to end: crafted keys map to
// chosen buckets and a table walk becomes a denial of service.
// The seed value lives at file scope so a tool can pin it before first
// use (see __koral_hash_seed_pin). Non-static on purpose: std's hash_mix
// reads it through a foreign global for a call-free hot path (see the
// header note on `__koral_hash_seed_value`).
uintptr_t __koral_hash_seed_value = 0;

void __koral_hash_seed_pin(uintptr_t v) {
    if (v == 0) v = (uintptr_t)0x9E3779B97F4A7C15ull;
    uintptr_t expected = 0;
    (void)__atomic_compare_exchange_n(
        &__koral_hash_seed_value, &expected, v, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
}

uintptr_t __koral_hash_seed(void) {
    uintptr_t* seed = &__koral_hash_seed_value;
    uintptr_t s = __atomic_load_n(seed, __ATOMIC_ACQUIRE);
    if (s != 0) return s;
    uintptr_t v = 0;
    const char* pinned = getenv("KORAL_HASH_SEED");
    if (pinned && pinned[0]) {
        for (const char* p = pinned; *p; p++) {
            if (*p >= '0' && *p <= '9') {
                v = v * 10 + (uintptr_t)(*p - '0');
            }
        }
    } else {
        __koral_random_fill((uint8_t*)&v, (int32_t)sizeof(v));
    }
    if (v == 0) v = (uintptr_t)0x9E3779B97F4A7C15ull;
    uintptr_t expected = 0;
    if (__atomic_compare_exchange_n(seed, &expected, v, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        return v;
    }
    return expected;
}

// 初始化链是**线程局部**的：初始化环是本线程的再入性质，跟别的线程无关。
// 旧实现把它挂在进程锁后面共享，锁去掉后必须随线程走。
static _Thread_local const char** __koral_global_init_stack = NULL;
static _Thread_local size_t __koral_global_init_depth = 0;
static _Thread_local size_t __koral_global_init_capacity = 0;

// 没抢到初始化权：本线程的初始化链里已有这个名字 => 环，报路径；
// 否则是别的线程在跑，自旋让步等它发布（state == 2，release）。
void __koral_global_init_wait_or_cycle(uint8_t* state, const char* name) {
    for (size_t i = 0; i < __koral_global_init_depth; i++) {
        if (strcmp(__koral_global_init_stack[i], name) == 0) {
            __koral_global_init_cycle(name);
        }
    }
    while (__atomic_load_n(state, __ATOMIC_ACQUIRE) != 2) {
        __koral_thread_yield();
    }
}

void __koral_global_init_push(const char* name) {
    if (__koral_global_init_depth == __koral_global_init_capacity) {
        size_t new_cap = __koral_global_init_capacity == 0 ? 16 : __koral_global_init_capacity * 2;
        const char** grown =
            (const char**)realloc((void*)__koral_global_init_stack, new_cap * sizeof(const char*));
        if (grown == NULL) {
            __koral_panic_print("out of memory while tracking global initialization", NULL);
        }
        __koral_global_init_stack = grown;
        __koral_global_init_capacity = new_cap;
    }
    __koral_global_init_stack[__koral_global_init_depth] = name;
    __koral_global_init_depth += 1;
}

void __koral_global_init_pop(void) {
    if (__koral_global_init_depth > 0) {
        __koral_global_init_depth -= 1;
    }
}

void __koral_global_init_cycle(const char* name) {
    size_t start = 0;
    for (size_t i = 0; i < __koral_global_init_depth; i++) {
        if (strcmp(__koral_global_init_stack[i], name) == 0) {
            start = i;
            break;
        }
    }
    size_t len = strlen("global initialization cycle: ") + strlen(name) + 1;
    for (size_t i = start; i < __koral_global_init_depth; i++) {
        len += strlen(__koral_global_init_stack[i]) + 4;
    }
    char* msg = (char*)malloc(len);
    if (msg == NULL) {
        __koral_panic_print("out of memory while reporting a global initialization cycle", NULL);
    }
    size_t off = (size_t)snprintf(msg, len, "global initialization cycle: ");
    for (size_t i = start; i < __koral_global_init_depth; i++) {
        off += (size_t)snprintf(msg + off, len - off, "%s -> ", __koral_global_init_stack[i]);
    }
    snprintf(msg + off, len - off, "%s", name);
    __koral_panic_print(msg, NULL);
}

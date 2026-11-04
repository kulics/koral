#ifndef KORAL_RUNTIME_H
#define KORAL_RUNTIME_H

#define KORAL_RUNTIME_ABI_VERSION 6

#include <stdatomic.h>
#include <stdint.h>
#include <limits.h>

#ifdef __cplusplus
extern "C" {
#endif

struct __koral_Ref {
    void* ptr;   // 指向目标值；所属 control 块在 ptr - 1
};

typedef void (*__koral_Dtor)(void*);

struct __koral_WeakRef {
    void* control;
};

struct __koral_TraitRef {
    void* ptr;          // 指向目标值；所属 control 块在 ptr - 1
    const void* vtable; // 静态 vtable 实例，第一个成员是 struct __koral_VTableHeader _Base
};

struct __koral_TraitWeakRef {
    void* control;
    const void* vtable;
};

struct __koral_Closure {
    void* fn;
    void* env;
    void (*drop)(void*);
};

// vtable 的公共前缀。每个 trait 的 vtable 结构体第一个成员必须是
// `struct __koral_VTableHeader _Base;`，于是 trait object 的类型擦除销毁可以
// 把 vtable 起始处直接转成本类型、取 `destroy`，而不用知道具体 trait。
// 对应 Swift 的 value witness table 被塞进 metadata 头的做法
// （但 Koral 的 trait object 一律装箱，不走扁平布局）。
//
// 字段名取 `_Base` 而不是 `base`：`base` 会和任何声明了 `base` 方法的 trait
// 撞出 duplicate member。`_Base` 落在 C 标识符转义区（`_` 开头 + 大写），
// Koral 方法名经转义后不可能落成这个名字。见 `escape_codegen_keyword`。
struct __koral_VTableHeader {
    __koral_Dtor destroy;
};

// Merged layout convention: the control block and payload are allocated as one
// contiguous block via a single malloc(sizeof(Control) + sizeof(T)).
// Memory: [ __koral_Control | payload data ... ]
//          ^                 ^
//          control           payload (= control + 1)
// The payload address is derivable from the control block and vice versa, so the
// control block does not store a back-pointer. Every handle stores the payload
// address; the owning control block is always at payload - 1.
//
// 头只有两个引用计数（8 字节）。析构函数**不**存在头里 —— drop glue 在释放
// 调用点单态化，由调用方作为 `__koral_Dtor` 传进来；类型擦除的场景（trait
// object）改走 vtable 的 base.destroy。这与 Rust `RcBox { strong, weak, value }`
// 同构：头里没有 dtor，drop glue 在 `Rc::drop::<T>` 处单态化。
//
// 强弱生命周期协议（RcBox 形状）：weak_count 含一个**隐式 +1** ——「payload
// 还活着」本身持有一个 weak，显式弱句柄各自再 +1（因此新分配的块 weak_count
// 从 1 起，由 codegen 发射）。free 只有一个判定点：weak_count 递减到 0 的那次
// fetch_sub 的胜者释放整块；强路径在析构完成后释放隐式 weak，从不直接 free。
// 两个计数器互查（强看 weak、weak 看 strong）会给出两个释放者，并发下 double
// free —— 判定必须收敛到单一计数器的零穿越。
struct __koral_Control {
    _Atomic int strong_count;
    _Atomic int weak_count;
};

// Payload <-> control conversion for the merged [Control | payload] layout.
#define __koral_payload_of(control) \
    ((void*)((char*)(control) + sizeof(struct __koral_Control)))
#define __koral_control_of(payload) \
    ((struct __koral_Control*)((char*)(payload) - sizeof(struct __koral_Control)))

void __koral_set_args(int32_t argc, uint8_t** argv);
void __koral_panic_numeric_conversion_overflow(const char* loc);
void __koral_panic_division_by_zero(const char* loc);
void __koral_panic_remainder_by_zero(const char* loc);

// Global-initializer support (accessor + state model): the generated accessor
// of a global serializes its slow path through a recursive lock, tracks the
// chain of initializers currently running, and panics on re-entrance with the
// cycle path. State values: 0 = uninitialized, 1 = initializing, 2 = done.
uint8_t __koral_global_state_ready(uint8_t* state);
void __koral_global_state_finish(uint8_t* state);
void __koral_global_init_lock(void);
void __koral_global_init_unlock(void);
void __koral_global_init_push(const char* name);
void __koral_global_init_pop(void);
void __koral_global_init_cycle(const char* name);

// Float -> wrapping-integer conversion (numeric-families design): step one is
// the domain check -- NaN and +-inf have no truncatable integer value and
// panic -- step two takes the truncated-toward-zero value's low `width_bits`
// bits in two's complement. Never panics after the domain step.
uint64_t __koral_wrapping_bits_from_f64(double v, unsigned width_bits, const char* loc);

int32_t __koral_spawn_thread(uint8_t** out_handle, uint64_t* out_tid,
                             struct __koral_Closure closure, uint64_t stack_size);
int32_t __koral_thread_join(uint8_t* handle);
void __koral_thread_detach(uint8_t* handle);
uint64_t __koral_thread_current_id(void);
void __koral_thread_yield(void);
uint32_t __koral_hardware_concurrency(void);

// ARC 快路径内联。
// Swift/LLVM 的 ARC 优化（`ARCOptimizer`、ARC contraction）能消掉冗余的
// retain/release 对，前提是优化器看得见这两个函数。原先它们是外部函数，
// 生成的 C 只能把每次引用计数都当成不透明调用——一对都消不掉，还多一层调用开销。
// 与 Swift 运行时的做法一致：快路径内联、慢路径（析构 + 释放）外联，
// 避免把每个调用点的体积撑大。
//
// Immortal（静态字面量）：control 块的 strong_count 为 -1，永不释放。
// 与 Swift 的 immortal object 同一做法，用来取代「control == NULL」哨兵。
// immortal 的 weak_count 同为哨兵值 -1；weak 操作读到 strong == -1 早退，
// 所以一次 downgrade/release 不会把静态块送进 free 路径。
#define KORAL_IMMORTAL_REFCOUNT (-1)

// 析构窗口哨兵（destroying）：强引用归零进入析构时把 strong_count 置 -2，
// 析构结束后恢复 0。retain/release 读到**任何**负数都早退（析构期间
// `drop(self)` 的 retain/release 是空操作，防析构递归），但 weak 操作只对
// immortal（-1）早退 —— 析构期间隐式 weak 仍在，weak 计数照常递减。
#define KORAL_DESTROYING_REFCOUNT (-2)

// 慢路径：强引用归零后调 dtor 销毁 payload，再释放「payload 存活」持有的
// 隐式 weak。free 由 weak_count 到 0 的唯一判定点决定（见 __koral_weak_release）。
void __koral_release_slow(struct __koral_Control* control, __koral_Dtor dtor);

// ---- control 层原语 ----
// 入参是 control 块指针。仅供 `_value` 包装和弱引用内部使用；
// 生成代码一律走下面的 `_value` 形式（瘦指针句柄保存的是 payload 地址）。
// 弱引用为什么走 control 而不是 payload：weak 存的是 control 地址，
// 因为 payload 可能已经销毁，weak 仍要能查 strong_count 判断能否 upgrade。
//
// 内存序（Swift/Rust 的 Arc 协议）：retain 是 relaxed 增量——它不发布任何
// 数据，只抬计数；release 是 release 减量——它发布「此前对 payload 的写」；
// 计数归零的一方在析构前补一道 acquire fence，与所有更早的 release 减量同步，
// 从而安全地读到各线程留下的 payload 状态。seq_cst 对这两个操作是纯开销。
static inline void __koral_retain(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    if (atomic_load_explicit(&control->strong_count, memory_order_relaxed) < 0) return;
    atomic_fetch_add_explicit(&control->strong_count, 1, memory_order_relaxed);
}

static inline void __koral_release(void* raw_control, __koral_Dtor dtor) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    if (atomic_load_explicit(&control->strong_count, memory_order_relaxed) < 0) return;
    int prev = atomic_fetch_sub_explicit(&control->strong_count, 1, memory_order_release);
    if (prev == 1) {
        atomic_thread_fence(memory_order_acquire);
        __koral_release_slow(control, dtor);
    }
}

// ---- 值层 API（生成代码用这一对）----
// 入参是 payload 指针，引用计数块固定在 ptr - 1。
// release 的 dtor 是「原地销毁该 payload」的 drop glue，在释放调用点单态化；
// 没有 drop glue 的类型传 NULL。trait object 传 vtable 的 base.destroy。
static inline void __koral_retain_value(void* payload) {
    if (!payload) return;
    __koral_retain(__koral_control_of(payload));
}
static inline void __koral_release_value(void* payload, __koral_Dtor dtor) {
    if (!payload) return;
    __koral_release(__koral_control_of(payload), dtor);
}

void __koral_weak_retain(void* raw_control);
void __koral_weak_release(void* raw_control);
// 「原地销毁一个 C 值」的可复用 drop glue。三者都与具体类型无关，
// 所以能直接当 __koral_Dtor 传给 __koral_release_value。
// 普通引用（struct __koral_Ref）的 drop 依赖内层类型，不是类型无关的，
// 因此不提供通用函数 —— 由 codegen 按内层类型单态化出 thunk。
void __koral_weakref_drop(void* raw_weak_ref);
void __koral_traitref_drop(void* raw_trait_ref);
void __koral_closure_drop(void* raw_closure);

struct __koral_WeakRef __koral_downgrade_ref(struct __koral_Ref r);
struct __koral_Ref __koral_upgrade_ref(struct __koral_WeakRef w, int* success);

void __koral_closure_retain(struct __koral_Closure closure);
void __koral_closure_release(struct __koral_Closure closure);
void __koral_closure_drop(void* raw_closure);

void __koral_panic_overflow_add(const char* loc);
void __koral_panic_overflow_sub(const char* loc);
void __koral_panic_overflow_mul(const char* loc);
void __koral_panic_overflow_div(const char* loc);
void __koral_panic_overflow_mod(const char* loc);
void __koral_panic_overflow_neg(const char* loc);
void __koral_panic_overflow_shift(const char* loc);
uint8_t* __koral_format_float64(double value, uint8_t type_char, intptr_t precision, int alt_form);

#ifdef __cplusplus
}
#endif

// ============================================================================
// Checked arithmetic: add, sub, mul for all 10 integer types
// ============================================================================

#if !defined(_MSC_VER)
// ---- GCC/Clang path using __builtin_*_overflow ----

#define KORAL_DEFINE_CHECKED_ADD(type, suffix) \
    static inline type koral_checked_add_##suffix(type a, type b, const char* loc) { \
        type result; \
        if (__builtin_add_overflow(a, b, &result)) { \
            __koral_panic_overflow_add(loc); \
        } \
        return result; \
    }

#define KORAL_DEFINE_CHECKED_SUB(type, suffix) \
    static inline type koral_checked_sub_##suffix(type a, type b, const char* loc) { \
        type result; \
        if (__builtin_sub_overflow(a, b, &result)) { \
            __koral_panic_overflow_sub(loc); \
        } \
        return result; \
    }

#define KORAL_DEFINE_CHECKED_MUL(type, suffix) \
    static inline type koral_checked_mul_##suffix(type a, type b, const char* loc) { \
        type result; \
        if (__builtin_mul_overflow(a, b, &result)) { \
            __koral_panic_overflow_mul(loc); \
        } \
        return result; \
    }

#else
// ---- MSVC fallback ----

#define KORAL_DEFINE_CHECKED_SIGNED_ADD(type, suffix, type_min, type_max) \
    static inline type koral_checked_add_##suffix(type a, type b, const char* loc) { \
        if ((b > 0 && a > (type_max) - b) || (b < 0 && a < (type_min) - b)) { \
            __koral_panic_overflow_add(loc); \
        } \
        return a + b; \
    }

#define KORAL_DEFINE_CHECKED_SIGNED_SUB(type, suffix, type_min, type_max) \
    static inline type koral_checked_sub_##suffix(type a, type b, const char* loc) { \
        if ((b < 0 && a > (type_max) + b) || (b > 0 && a < (type_min) + b)) { \
            __koral_panic_overflow_sub(loc); \
        } \
        return a - b; \
    }

#define KORAL_DEFINE_CHECKED_SIGNED_MUL_WIDE(type, suffix, wide_type, type_min, type_max) \
    static inline type koral_checked_mul_##suffix(type a, type b, const char* loc) { \
        wide_type result = (wide_type)a * (wide_type)b; \
        if (result > (wide_type)(type_max) || result < (wide_type)(type_min)) { \
            __koral_panic_overflow_mul(loc); \
        } \
        return (type)result; \
    }

#define KORAL_DEFINE_CHECKED_SIGNED_MUL_NARROW(type, suffix, type_min, type_max) \
    static inline type koral_checked_mul_##suffix(type a, type b, const char* loc) { \
        if (a > 0) { \
            if (b > 0) { \
                if (a > (type_max) / b) __koral_panic_overflow_mul(loc); \
            } else { \
                if (b < (type_min) / a) __koral_panic_overflow_mul(loc); \
            } \
        } else { \
            if (b > 0) { \
                if (a < (type_min) / b) __koral_panic_overflow_mul(loc); \
            } else { \
                if (a != 0 && b < (type_max) / a) __koral_panic_overflow_mul(loc); \
            } \
        } \
        return a * b; \
    }

#define KORAL_DEFINE_CHECKED_UNSIGNED_ADD(type, suffix, type_max) \
    static inline type koral_checked_add_##suffix(type a, type b, const char* loc) { \
        if (a > (type_max) - b) { \
            __koral_panic_overflow_add(loc); \
        } \
        return a + b; \
    }

#define KORAL_DEFINE_CHECKED_UNSIGNED_SUB(type, suffix) \
    static inline type koral_checked_sub_##suffix(type a, type b, const char* loc) { \
        if (a < b) { \
            __koral_panic_overflow_sub(loc); \
        } \
        return a - b; \
    }

#define KORAL_DEFINE_CHECKED_UNSIGNED_MUL(type, suffix, type_max) \
    static inline type koral_checked_mul_##suffix(type a, type b, const char* loc) { \
        if (a != 0 && b > (type_max) / a) { \
            __koral_panic_overflow_mul(loc); \
        } \
        return a * b; \
    }

#endif // !defined(_MSC_VER)

#if !defined(_MSC_VER)
KORAL_DEFINE_CHECKED_ADD(int8_t, i8)
KORAL_DEFINE_CHECKED_SUB(int8_t, i8)
KORAL_DEFINE_CHECKED_MUL(int8_t, i8)
KORAL_DEFINE_CHECKED_ADD(int16_t, i16)
KORAL_DEFINE_CHECKED_SUB(int16_t, i16)
KORAL_DEFINE_CHECKED_MUL(int16_t, i16)
KORAL_DEFINE_CHECKED_ADD(int32_t, i32)
KORAL_DEFINE_CHECKED_SUB(int32_t, i32)
KORAL_DEFINE_CHECKED_MUL(int32_t, i32)
KORAL_DEFINE_CHECKED_ADD(int64_t, i64)
KORAL_DEFINE_CHECKED_SUB(int64_t, i64)
KORAL_DEFINE_CHECKED_MUL(int64_t, i64)
KORAL_DEFINE_CHECKED_ADD(intptr_t, isize)
KORAL_DEFINE_CHECKED_SUB(intptr_t, isize)
KORAL_DEFINE_CHECKED_MUL(intptr_t, isize)
KORAL_DEFINE_CHECKED_ADD(uint8_t, u8)
KORAL_DEFINE_CHECKED_SUB(uint8_t, u8)
KORAL_DEFINE_CHECKED_MUL(uint8_t, u8)
KORAL_DEFINE_CHECKED_ADD(uint16_t, u16)
KORAL_DEFINE_CHECKED_SUB(uint16_t, u16)
KORAL_DEFINE_CHECKED_MUL(uint16_t, u16)
KORAL_DEFINE_CHECKED_ADD(uint32_t, u32)
KORAL_DEFINE_CHECKED_SUB(uint32_t, u32)
KORAL_DEFINE_CHECKED_MUL(uint32_t, u32)
KORAL_DEFINE_CHECKED_ADD(uint64_t, u64)
KORAL_DEFINE_CHECKED_SUB(uint64_t, u64)
KORAL_DEFINE_CHECKED_MUL(uint64_t, u64)
KORAL_DEFINE_CHECKED_ADD(uintptr_t, usize)
KORAL_DEFINE_CHECKED_SUB(uintptr_t, usize)
KORAL_DEFINE_CHECKED_MUL(uintptr_t, usize)
#else
KORAL_DEFINE_CHECKED_SIGNED_ADD(int8_t, i8, INT8_MIN, INT8_MAX)
KORAL_DEFINE_CHECKED_SIGNED_SUB(int8_t, i8, INT8_MIN, INT8_MAX)
KORAL_DEFINE_CHECKED_SIGNED_MUL_WIDE(int8_t, i8, int16_t, INT8_MIN, INT8_MAX)
KORAL_DEFINE_CHECKED_SIGNED_ADD(int16_t, i16, INT16_MIN, INT16_MAX)
KORAL_DEFINE_CHECKED_SIGNED_SUB(int16_t, i16, INT16_MIN, INT16_MAX)
KORAL_DEFINE_CHECKED_SIGNED_MUL_WIDE(int16_t, i16, int32_t, INT16_MIN, INT16_MAX)
KORAL_DEFINE_CHECKED_SIGNED_ADD(int32_t, i32, INT32_MIN, INT32_MAX)
KORAL_DEFINE_CHECKED_SIGNED_SUB(int32_t, i32, INT32_MIN, INT32_MAX)
KORAL_DEFINE_CHECKED_SIGNED_MUL_WIDE(int32_t, i32, int64_t, INT32_MIN, INT32_MAX)
KORAL_DEFINE_CHECKED_SIGNED_ADD(int64_t, i64, INT64_MIN, INT64_MAX)
KORAL_DEFINE_CHECKED_SIGNED_SUB(int64_t, i64, INT64_MIN, INT64_MAX)
KORAL_DEFINE_CHECKED_SIGNED_MUL_NARROW(int64_t, i64, INT64_MIN, INT64_MAX)
KORAL_DEFINE_CHECKED_SIGNED_ADD(intptr_t, isize, INTPTR_MIN, INTPTR_MAX)
KORAL_DEFINE_CHECKED_SIGNED_SUB(intptr_t, isize, INTPTR_MIN, INTPTR_MAX)
KORAL_DEFINE_CHECKED_SIGNED_MUL_NARROW(intptr_t, isize, INTPTR_MIN, INTPTR_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_ADD(uint8_t, u8, UINT8_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_SUB(uint8_t, u8)
KORAL_DEFINE_CHECKED_UNSIGNED_MUL(uint8_t, u8, UINT8_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_ADD(uint16_t, u16, UINT16_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_SUB(uint16_t, u16)
KORAL_DEFINE_CHECKED_UNSIGNED_MUL(uint16_t, u16, UINT16_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_ADD(uint32_t, u32, UINT32_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_SUB(uint32_t, u32)
KORAL_DEFINE_CHECKED_UNSIGNED_MUL(uint32_t, u32, UINT32_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_ADD(uint64_t, u64, UINT64_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_SUB(uint64_t, u64)
KORAL_DEFINE_CHECKED_UNSIGNED_MUL(uint64_t, u64, UINT64_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_ADD(uintptr_t, usize, UINTPTR_MAX)
KORAL_DEFINE_CHECKED_UNSIGNED_SUB(uintptr_t, usize)
KORAL_DEFINE_CHECKED_UNSIGNED_MUL(uintptr_t, usize, UINTPTR_MAX)
#endif

#define KORAL_DEFINE_CHECKED_SIGNED_DIV(type, suffix, type_min) \
    static inline type koral_checked_div_##suffix(type a, type b, const char* loc) { \
        if (b == 0) { \
            __koral_panic_division_by_zero(loc); \
        } \
        if (a == (type_min) && b == -1) { \
            __koral_panic_overflow_div(loc); \
        } \
        return a / b; \
    }

#define KORAL_DEFINE_CHECKED_SIGNED_MOD(type, suffix, type_min) \
    static inline type koral_checked_mod_##suffix(type a, type b, const char* loc) { \
        if (b == 0) { \
            __koral_panic_remainder_by_zero(loc); \
        } \
        if (a == (type_min) && b == -1) { \
            __koral_panic_overflow_mod(loc); \
        } \
        return a % b; \
    }

#define KORAL_DEFINE_CHECKED_UNSIGNED_DIV(type, suffix) \
    static inline type koral_checked_div_##suffix(type a, type b, const char* loc) { \
        if (b == 0) { \
            __koral_panic_division_by_zero(loc); \
        } \
        return a / b; \
    }

#define KORAL_DEFINE_CHECKED_UNSIGNED_MOD(type, suffix) \
    static inline type koral_checked_mod_##suffix(type a, type b, const char* loc) { \
        if (b == 0) { \
            __koral_panic_remainder_by_zero(loc); \
        } \
        return a % b; \
    }

KORAL_DEFINE_CHECKED_SIGNED_DIV(int8_t, i8, INT8_MIN)
KORAL_DEFINE_CHECKED_SIGNED_MOD(int8_t, i8, INT8_MIN)
KORAL_DEFINE_CHECKED_SIGNED_DIV(int16_t, i16, INT16_MIN)
KORAL_DEFINE_CHECKED_SIGNED_MOD(int16_t, i16, INT16_MIN)
KORAL_DEFINE_CHECKED_SIGNED_DIV(int32_t, i32, INT32_MIN)
KORAL_DEFINE_CHECKED_SIGNED_MOD(int32_t, i32, INT32_MIN)
KORAL_DEFINE_CHECKED_SIGNED_DIV(int64_t, i64, INT64_MIN)
KORAL_DEFINE_CHECKED_SIGNED_MOD(int64_t, i64, INT64_MIN)
KORAL_DEFINE_CHECKED_SIGNED_DIV(intptr_t, isize, INTPTR_MIN)
KORAL_DEFINE_CHECKED_SIGNED_MOD(intptr_t, isize, INTPTR_MIN)
KORAL_DEFINE_CHECKED_UNSIGNED_DIV(uint8_t, u8)
KORAL_DEFINE_CHECKED_UNSIGNED_MOD(uint8_t, u8)
KORAL_DEFINE_CHECKED_UNSIGNED_DIV(uint16_t, u16)
KORAL_DEFINE_CHECKED_UNSIGNED_MOD(uint16_t, u16)
KORAL_DEFINE_CHECKED_UNSIGNED_DIV(uint32_t, u32)
KORAL_DEFINE_CHECKED_UNSIGNED_MOD(uint32_t, u32)
KORAL_DEFINE_CHECKED_UNSIGNED_DIV(uint64_t, u64)
KORAL_DEFINE_CHECKED_UNSIGNED_MOD(uint64_t, u64)
KORAL_DEFINE_CHECKED_UNSIGNED_DIV(uintptr_t, usize)
KORAL_DEFINE_CHECKED_UNSIGNED_MOD(uintptr_t, usize)

#define KORAL_DEFINE_CHECKED_SIGNED_SHL(type, unsigned_type, suffix, bit_width) \
    static inline type koral_checked_shl_##suffix(type a, type b, const char* loc) { \
        if (b < 0 || b >= (bit_width)) { \
            __koral_panic_overflow_shift(loc); \
        } \
        return (type)((unsigned_type)a << b); \
    }

#define KORAL_DEFINE_CHECKED_SIGNED_SHR(type, suffix, bit_width) \
    static inline type koral_checked_shr_##suffix(type a, type b, const char* loc) { \
        if (b < 0 || b >= (bit_width)) { \
            __koral_panic_overflow_shift(loc); \
        } \
        return a >> b; \
    }

#define KORAL_DEFINE_CHECKED_UNSIGNED_SHL(type, suffix, bit_width) \
    static inline type koral_checked_shl_##suffix(type a, type b, const char* loc) { \
        if (b >= (bit_width)) { \
            __koral_panic_overflow_shift(loc); \
        } \
        return a << b; \
    }

#define KORAL_DEFINE_CHECKED_UNSIGNED_SHR(type, suffix, bit_width) \
    static inline type koral_checked_shr_##suffix(type a, type b, const char* loc) { \
        if (b >= (bit_width)) { \
            __koral_panic_overflow_shift(loc); \
        } \
        return a >> b; \
    }

KORAL_DEFINE_CHECKED_SIGNED_SHL(int8_t, uint8_t, i8, 8)
KORAL_DEFINE_CHECKED_SIGNED_SHR(int8_t, i8, 8)
KORAL_DEFINE_CHECKED_SIGNED_SHL(int16_t, uint16_t, i16, 16)
KORAL_DEFINE_CHECKED_SIGNED_SHR(int16_t, i16, 16)
KORAL_DEFINE_CHECKED_SIGNED_SHL(int32_t, uint32_t, i32, 32)
KORAL_DEFINE_CHECKED_SIGNED_SHR(int32_t, i32, 32)
KORAL_DEFINE_CHECKED_SIGNED_SHL(int64_t, uint64_t, i64, 64)
KORAL_DEFINE_CHECKED_SIGNED_SHR(int64_t, i64, 64)
KORAL_DEFINE_CHECKED_SIGNED_SHL(intptr_t, uintptr_t, isize, (int)(sizeof(intptr_t) * 8))
KORAL_DEFINE_CHECKED_SIGNED_SHR(intptr_t, isize, (int)(sizeof(intptr_t) * 8))
KORAL_DEFINE_CHECKED_UNSIGNED_SHL(uint8_t, u8, 8)
KORAL_DEFINE_CHECKED_UNSIGNED_SHR(uint8_t, u8, 8)
KORAL_DEFINE_CHECKED_UNSIGNED_SHL(uint16_t, u16, 16)
KORAL_DEFINE_CHECKED_UNSIGNED_SHR(uint16_t, u16, 16)
KORAL_DEFINE_CHECKED_UNSIGNED_SHL(uint32_t, u32, 32)
KORAL_DEFINE_CHECKED_UNSIGNED_SHR(uint32_t, u32, 32)
KORAL_DEFINE_CHECKED_UNSIGNED_SHL(uint64_t, u64, 64)
KORAL_DEFINE_CHECKED_UNSIGNED_SHR(uint64_t, u64, 64)
KORAL_DEFINE_CHECKED_UNSIGNED_SHL(uintptr_t, usize, (uintptr_t)(sizeof(uintptr_t) * 8))
KORAL_DEFINE_CHECKED_UNSIGNED_SHR(uintptr_t, usize, (uintptr_t)(sizeof(uintptr_t) * 8))

// Wrapping-family shifts: the amount is reduced modulo the width instead of
// panicking. A wrapped answer exists -- `WrappingInt8(1) << 9` masks 9 to 1
// and yields 2 -- so the family wraps; the plain family keeps the checked
// panic above. Both shift out bits are discarded the same way.
#define KORAL_DEFINE_WRAPPING_SIGNED_SHL(type, unsigned_type, suffix, bit_width) \
    static inline type koral_wrapping_shl_##suffix(type a, type b, const char* loc) { \
        return (type)((unsigned_type)a << (((unsigned_type)b) & (unsigned_type)((bit_width) - 1))); \
    }

#define KORAL_DEFINE_WRAPPING_UNSIGNED_SHL(type, unsigned_type, suffix, bit_width) \
    static inline type koral_wrapping_shl_##suffix(type a, type b, const char* loc) { \
        return (type)(a << (((unsigned_type)b) & (unsigned_type)((bit_width) - 1))); \
    }

#define KORAL_DEFINE_WRAPPING_SHR(type, unsigned_type, suffix, bit_width) \
    static inline type koral_wrapping_shr_##suffix(type a, type b, const char* loc) { \
        return (type)(a >> (((unsigned_type)b) & (unsigned_type)((bit_width) - 1))); \
    }

KORAL_DEFINE_WRAPPING_SIGNED_SHL(int8_t, uint8_t, i8, 8)
KORAL_DEFINE_WRAPPING_SHR(int8_t, uint8_t, i8, 8)
KORAL_DEFINE_WRAPPING_SIGNED_SHL(int16_t, uint16_t, i16, 16)
KORAL_DEFINE_WRAPPING_SHR(int16_t, uint16_t, i16, 16)
KORAL_DEFINE_WRAPPING_SIGNED_SHL(int32_t, uint32_t, i32, 32)
KORAL_DEFINE_WRAPPING_SHR(int32_t, uint32_t, i32, 32)
KORAL_DEFINE_WRAPPING_SIGNED_SHL(int64_t, uint64_t, i64, 64)
KORAL_DEFINE_WRAPPING_SHR(int64_t, uint64_t, i64, 64)
KORAL_DEFINE_WRAPPING_SIGNED_SHL(intptr_t, uintptr_t, isize, (int)(sizeof(intptr_t) * 8))
KORAL_DEFINE_WRAPPING_SHR(intptr_t, uintptr_t, isize, (int)(sizeof(intptr_t) * 8))
KORAL_DEFINE_WRAPPING_UNSIGNED_SHL(uint8_t, uint8_t, u8, 8)
KORAL_DEFINE_WRAPPING_SHR(uint8_t, uint8_t, u8, 8)
KORAL_DEFINE_WRAPPING_UNSIGNED_SHL(uint16_t, uint16_t, u16, 16)
KORAL_DEFINE_WRAPPING_SHR(uint16_t, uint16_t, u16, 16)
KORAL_DEFINE_WRAPPING_UNSIGNED_SHL(uint32_t, uint32_t, u32, 32)
KORAL_DEFINE_WRAPPING_SHR(uint32_t, uint32_t, u32, 32)
KORAL_DEFINE_WRAPPING_UNSIGNED_SHL(uint64_t, uint64_t, u64, 64)
KORAL_DEFINE_WRAPPING_SHR(uint64_t, uint64_t, u64, 64)
KORAL_DEFINE_WRAPPING_UNSIGNED_SHL(uintptr_t, uintptr_t, usize, (uintptr_t)(sizeof(uintptr_t) * 8))
KORAL_DEFINE_WRAPPING_SHR(uintptr_t, uintptr_t, usize, (uintptr_t)(sizeof(uintptr_t) * 8))

#define KORAL_DEFINE_CHECKED_NEG(type, suffix, type_min) \
    static inline type koral_checked_neg_##suffix(type a, const char* loc) { \
        if (a == (type_min)) { \
            __koral_panic_overflow_neg(loc); \
        } \
        return -a; \
    }

KORAL_DEFINE_CHECKED_NEG(int8_t, i8, INT8_MIN)
KORAL_DEFINE_CHECKED_NEG(int16_t, i16, INT16_MIN)
KORAL_DEFINE_CHECKED_NEG(int32_t, i32, INT32_MIN)
KORAL_DEFINE_CHECKED_NEG(int64_t, i64, INT64_MIN)
KORAL_DEFINE_CHECKED_NEG(intptr_t, isize, INTPTR_MIN)

#endif // KORAL_RUNTIME_H

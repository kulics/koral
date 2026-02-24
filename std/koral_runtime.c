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
#include "koral_runtime.h"

#if !defined(_WIN32) && !defined(_WIN64)
#include <regex.h>
#endif

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

void __koral_retain(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    atomic_fetch_add(&control->strong_count, 1);
}

void __koral_release(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    int prev = atomic_fetch_sub(&control->strong_count, 1);
    if (prev == 1) {
        if (control->dtor) {
            control->dtor(control->ptr);
        }
        free(control->ptr);
        int weak_prev = atomic_fetch_sub(&control->weak_count, 1);
        if (weak_prev == 1) {
            free(control);
        }
    }
}

void __koral_weak_retain(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    atomic_fetch_add(&control->weak_count, 1);
}

void __koral_weak_release(void* raw_control) {
    if (!raw_control) return;
    struct __koral_Control* control = (struct __koral_Control*)raw_control;
    int prev = atomic_fetch_sub(&control->weak_count, 1);
    if (prev == 1) {
        free(control);
    }
}

struct __koral_WeakRef __koral_downgrade_ref(struct __koral_Ref r) {
    struct __koral_WeakRef w;
    w.control = r.control;
    if (w.control) {
        __koral_weak_retain(w.control);
    }
    return w;
}

struct __koral_Ref __koral_upgrade_ref(struct __koral_WeakRef w, int* success) {
    struct __koral_Ref r;
    r.ptr = NULL;
    r.control = NULL;
    *success = 0;

    if (!w.control) return r;

    struct __koral_Control* control = (struct __koral_Control*)w.control;
    int old_count = atomic_load(&control->strong_count);
    while (old_count > 0) {
        if (atomic_compare_exchange_weak(&control->strong_count, &old_count, old_count + 1)) {
            r.ptr = control->ptr;
            r.control = w.control;
            *success = 1;
            return r;
        }
    }

    return r;
}

void __koral_closure_retain(struct __koral_Closure closure) {
    if (!closure.env) return;
    _Atomic intptr_t* refcount = (_Atomic intptr_t*)closure.env;
    atomic_fetch_add(refcount, 1);
}

void __koral_closure_release(struct __koral_Closure closure) {
    if (!closure.env) return;
    _Atomic intptr_t* refcount = (_Atomic intptr_t*)closure.env;
    intptr_t prev = atomic_fetch_sub(refcount, 1);
    if (prev == 1) {
        if (closure.drop) {
            closure.drop(closure.env);
        } else {
            free(closure.env);
        }
    }
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

void __koral_panic_float_cast_overflow(void) {
    fprintf(stderr, "Panic: float-to-int cast overflow\n");
    abort();
}

void __koral_panic_overflow_add(void) {
    fprintf(stderr, "Panic: integer overflow in addition\n");
    abort();
}

void __koral_panic_overflow_sub(void) {
    fprintf(stderr, "Panic: integer overflow in subtraction\n");
    abort();
}

void __koral_panic_overflow_mul(void) {
    fprintf(stderr, "Panic: integer overflow in multiplication\n");
    abort();
}

void __koral_panic_overflow_div(void) {
    fprintf(stderr, "Panic: integer overflow in division\n");
    abort();
}

void __koral_panic_overflow_mod(void) {
    fprintf(stderr, "Panic: integer overflow in modulo\n");
    abort();
}

void __koral_panic_overflow_neg(void) {
    fprintf(stderr, "Panic: integer overflow in negation\n");
    abort();
}

void __koral_panic_overflow_shift(void) {
    fprintf(stderr, "Panic: integer overflow in shift\n");
    abort();
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
#include <direct.h>
#include <io.h>
#include <fcntl.h>
#include <share.h>
#include <sys/stat.h>

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

int __koral_normalize_path(const char* path, char* buf, size_t size) {
    normalize_path_internal(path, buf, size);
    return (int)strlen(buf);
}

char __koral_path_separator(void) {
#ifdef _WIN32
    return '\\';
#else
    return '/';
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
    struct _stat st;
    return _stat(normalized, &st) == 0 ? 1 : 0;
#else
    struct stat st;
    return stat(normalized, &st) == 0 ? 1 : 0;
#endif
}

int __koral_is_file(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    struct _stat st;
    if (_stat(normalized, &st) != 0) return 0;
    return (st.st_mode & _S_IFREG) != 0 ? 1 : 0;
#else
    struct stat st;
    if (stat(normalized, &st) != 0) return 0;
    return S_ISREG(st.st_mode) ? 1 : 0;
#endif
}

int __koral_is_dir(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    struct _stat st;
    if (_stat(normalized, &st) != 0) return 0;
    return (st.st_mode & _S_IFDIR) != 0 ? 1 : 0;
#else
    struct stat st;
    if (stat(normalized, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
#endif
}

// ============================================================================
// Directory helpers
// ============================================================================

#ifdef _WIN32
struct CDirHandle {
    HANDLE handle;
    WIN32_FIND_DATAA data;
    bool first;
};

struct CDirEntry {
    char name[MAX_PATH];
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

    char pattern[MAX_PATH];
    snprintf(pattern, MAX_PATH, "%s\\*", normalized);

    dir->handle = FindFirstFileA(pattern, &dir->data);
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

CDirEntry* __koral_readdir(CDirHandle* dir) {
#ifdef _WIN32
    static CDirEntry entry;
    if (dir->first) {
        dir->first = false;
        strcpy(entry.name, dir->data.cFileName);
        entry.attributes = dir->data.dwFileAttributes;
        return &entry;
    }
    if (FindNextFileA(dir->handle, &dir->data)) {
        strcpy(entry.name, dir->data.cFileName);
        entry.attributes = dir->data.dwFileAttributes;
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
    return _mkdir(normalized);
#else
    return mkdir(normalized, mode);
#endif
}

int __koral_rmdir(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    return _rmdir(normalized);
#else
    return rmdir(normalized);
#endif
}

char* __koral_getcwd(char* buf, size_t size) {
#ifdef _WIN32
    return _getcwd(buf, (int)size);
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

int32_t __koral_timezone_name_exists(const char* name) {
#if defined(_WIN32) || defined(_WIN64)
    (void)name;
    return 0;
#else
    if (!name || name[0] == '\0') return 0;
    char path[512];
    return tzif_find_file(name, path, sizeof(path)) ? 1 : 0;
#endif
}

void __koral_timezone_offset_at(const char* name, int64_t unix_secs, int32_t* out_offset_secs) {
#if defined(_WIN32) || defined(_WIN64)
    (void)name;
    (void)unix_secs;
    // Windows: only support local timezone via GetTimeZoneInformation
    __koral_local_timezone_offset(out_offset_secs);
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
// Regex: POSIX regular expression support
// ============================================================================

#if !defined(_WIN32) && !defined(_WIN64)

int32_t __koral_regex_compile(const char* pattern, int32_t flags,
                            void** out_handle,
                            char* out_error_buf, int32_t error_buf_size,
                            int32_t* out_error_len) {
    regex_t* compiled = (regex_t*)malloc(sizeof(regex_t));
    if (!compiled) {
        const char* msg = "out of memory";
        int32_t msg_len = (int32_t)strlen(msg);
        if (msg_len > error_buf_size - 1) {
            msg_len = error_buf_size - 1;
        }
        memcpy(out_error_buf, msg, (size_t)msg_len);
        out_error_buf[msg_len] = '\0';
        *out_error_len = msg_len;
        return -1;
    }

    int rc = regcomp(compiled, pattern, flags | REG_EXTENDED);
    if (rc != 0) {
        size_t err_len = regerror(rc, compiled, out_error_buf, (size_t)error_buf_size);
        if (err_len > 0 && out_error_buf[err_len - 1] == '\0') {
            err_len--;
        }
        *out_error_len = (int32_t)err_len;
        regfree(compiled);
        free(compiled);
        return rc;
    }

    *out_handle = compiled;
    return 0;
}

int32_t __koral_regex_match(void* handle, const char* text, int32_t text_offset,
                          int32_t max_groups,
                          int32_t* out_starts, int32_t* out_ends) {
    regex_t* compiled = (regex_t*)handle;
    regmatch_t pmatch[max_groups];

    int rc = regexec(compiled, text + text_offset, (size_t)max_groups, pmatch, 0);
    if (rc != 0) {
        return 0;  // no match
    }

    int32_t matched = 0;
    for (int32_t i = 0; i < max_groups; i++) {
        if (pmatch[i].rm_so == -1) {
            out_starts[i] = -1;
            out_ends[i] = -1;
        } else {
            out_starts[i] = (int32_t)pmatch[i].rm_so + text_offset;
            out_ends[i] = (int32_t)pmatch[i].rm_eo + text_offset;
            matched = i + 1;
        }
    }

    return matched > 0 ? matched : 1;
}

void __koral_regex_free(void* handle) {
    regex_t* compiled = (regex_t*)handle;
    regfree(compiled);
    free(compiled);
}

#endif  // !_WIN32 && !_WIN64

// ============================================================================
// Windows: Minimal POSIX ERE regex implementation
// ============================================================================
#if defined(_WIN32) || defined(_WIN64)

// Regex node types for the NFA
enum {
    RE_LIT,      // literal character
    RE_DOT,      // .
    RE_CCLASS,   // [...]
    RE_NCCLASS,  // [^...]
    RE_BOL,      // ^
    RE_EOL,      // $
    RE_GROUP_S,  // ( start
    RE_GROUP_E,  // ) end
    RE_SPLIT,    // split (for |, *, +, ?)
    RE_JMP,      // unconditional jump
    RE_MATCH,    // match state
    RE_DIGIT,    // \d
    RE_NDIGIT,   // \D
    RE_WORD,     // \w
    RE_NWORD,    // \W
    RE_SPACE,    // \s
    RE_NSPACE,   // \S
};

typedef struct {
    int type;
    int ch;           // for RE_LIT
    int group;        // for RE_GROUP_S/E
    int x, y;         // for RE_SPLIT: x=primary, y=alt; for RE_JMP: x=target
    uint8_t cclass[32]; // bitmap for RE_CCLASS/RE_NCCLASS
} ReInst;

#define RE_MAX_INST 4096
#define RE_MAX_GROUPS 10

typedef struct {
    ReInst inst[RE_MAX_INST];
    int len;
    int ngroups;
    int flags;
    char error[256];
} ReCompiled;

// Forward declarations
static int re_compile_expr(ReCompiled* re, const char* p, int* pos, int plen);

static void cc_set(uint8_t* cc, int c) { cc[c >> 3] |= (1 << (c & 7)); }
static int cc_test(const uint8_t* cc, int c) { return (cc[c >> 3] >> (c & 7)) & 1; }

static int re_emit(ReCompiled* re, int type) {
    if (re->len >= RE_MAX_INST) return -1;
    memset(&re->inst[re->len], 0, sizeof(ReInst));
    re->inst[re->len].type = type;
    re->inst[re->len].x = -1;
    re->inst[re->len].y = -1;
    return re->len++;
}

static int is_digit(int c) { return c >= '0' && c <= '9'; }
static int is_word(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'; }
static int is_space(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }

static int re_parse_cclass(ReCompiled* re, const char* p, int* pos, int plen) {
    int negate = 0;
    int idx = re_emit(re, RE_CCLASS);
    if (idx < 0) return -1;
    if (*pos < plen && p[*pos] == '^') {
        negate = 1;
        re->inst[idx].type = RE_NCCLASS;
        (*pos)++;
    }
    memset(re->inst[idx].cclass, 0, 32);
    int first = 1;
    while (*pos < plen && (first || p[*pos] != ']')) {
        first = 0;
        int c = (unsigned char)p[*pos];
        (*pos)++;
        if (c == '\\' && *pos < plen) {
            c = (unsigned char)p[*pos];
            (*pos)++;
            switch (c) {
                case 'd': for (int i = '0'; i <= '9'; i++) cc_set(re->inst[idx].cclass, i); continue;
                case 'w': for (int i = 'a'; i <= 'z'; i++) cc_set(re->inst[idx].cclass, i);
                          for (int i = 'A'; i <= 'Z'; i++) cc_set(re->inst[idx].cclass, i);
                          for (int i = '0'; i <= '9'; i++) cc_set(re->inst[idx].cclass, i);
                          cc_set(re->inst[idx].cclass, '_'); continue;
                case 's': cc_set(re->inst[idx].cclass, ' '); cc_set(re->inst[idx].cclass, '\t');
                          cc_set(re->inst[idx].cclass, '\n'); cc_set(re->inst[idx].cclass, '\r');
                          cc_set(re->inst[idx].cclass, '\f'); cc_set(re->inst[idx].cclass, '\v'); continue;
                default: break; // literal escaped char
            }
        }
        // Check for range a-z
        if (*pos + 1 < plen && p[*pos] == '-' && p[*pos + 1] != ']') {
            (*pos)++;
            int c2 = (unsigned char)p[*pos];
            (*pos)++;
            if (c2 == '\\' && *pos < plen) { c2 = (unsigned char)p[*pos]; (*pos)++; }
            for (int i = c; i <= c2; i++) cc_set(re->inst[idx].cclass, i);
        } else {
            cc_set(re->inst[idx].cclass, c);
        }
    }
    if (*pos < plen && p[*pos] == ']') (*pos)++;
    else { snprintf(re->error, 256, "Unmatched ["); return -1; }
    return idx;
}

// Parse an atom: literal, dot, group, char class, escape
static int re_parse_atom(ReCompiled* re, const char* p, int* pos, int plen) {
    if (*pos >= plen) return -1;
    int c = (unsigned char)p[*pos];
    if (c == '(') {
        (*pos)++;
        int gn = re->ngroups++;
        int gs = re_emit(re, RE_GROUP_S);
        if (gs < 0) return -1;
        re->inst[gs].group = gn;
        if (re_compile_expr(re, p, pos, plen) < 0) return -1;
        if (*pos >= plen || p[*pos] != ')') {
            snprintf(re->error, 256, "Unmatched (");
            return -1;
        }
        (*pos)++;
        int ge = re_emit(re, RE_GROUP_E);
        if (ge < 0) return -1;
        re->inst[ge].group = gn;
        return gs;
    }
    if (c == '[') {
        (*pos)++;
        return re_parse_cclass(re, p, pos, plen);
    }
    if (c == '.') {
        (*pos)++;
        return re_emit(re, RE_DOT);
    }
    if (c == '^') {
        (*pos)++;
        return re_emit(re, RE_BOL);
    }
    if (c == '$') {
        (*pos)++;
        return re_emit(re, RE_EOL);
    }
    if (c == '\\' && *pos + 1 < plen) {
        (*pos)++;
        c = (unsigned char)p[*pos];
        (*pos)++;
        switch (c) {
            case 'd': return re_emit(re, RE_DIGIT);
            case 'D': return re_emit(re, RE_NDIGIT);
            case 'w': return re_emit(re, RE_WORD);
            case 'W': return re_emit(re, RE_NWORD);
            case 's': return re_emit(re, RE_SPACE);
            case 'S': return re_emit(re, RE_NSPACE);
            default: { int idx = re_emit(re, RE_LIT); if (idx >= 0) re->inst[idx].ch = c; return idx; }
        }
    }
    // Reject bare quantifiers
    if (c == '*' || c == '+' || c == '?' || c == '{') {
        snprintf(re->error, 256, "Invalid preceding regular expression");
        return -1;
    }
    if (c == ')' || c == '|') return -1; // not an atom
    (*pos)++;
    int idx = re_emit(re, RE_LIT);
    if (idx >= 0) {
        if ((re->flags & 2) && c >= 'A' && c <= 'Z') c += 32; // case insensitive: store lowercase
        re->inst[idx].ch = c;
    }
    return idx;
}

// Parse quantified atom: atom followed by *, +, ?, {n,m}
static int re_parse_quantified(ReCompiled* re, const char* p, int* pos, int plen) {
    int start = re->len;
    int r = re_parse_atom(re, p, pos, plen);
    if (r < 0) return r;
    if (*pos >= plen) return r;
    int c = (unsigned char)p[*pos];
    if (c == '*') {
        (*pos)++;
        // split -> atom -> jmp back to split
        int sp = re_emit(re, RE_SPLIT);
        if (sp < 0) return -1;
        // Move instructions: insert split before atom
        // Simpler: patch with jump
        // Actually, restructure: we need split at start, jmp at end
        // Let's use a different approach: 
        // We already emitted the atom at [start..re->len-1]
        // We need: SPLIT(atom, skip) at start, then atom, then JMP(start)
        // Shift instructions to make room for split at start
        for (int i = re->len - 1; i > start; i--) {
            re->inst[i] = re->inst[i - 1];
            // Fix group references if needed
        }
        re->len--; // remove the extra SPLIT we emitted
        // Insert split at start
        memset(&re->inst[start], 0, sizeof(ReInst));
        re->inst[start].type = RE_SPLIT;
        re->inst[start].x = start + 1;  // try atom
        re->inst[start].y = re->len + 1; // skip (will be set after jmp)
        // Add JMP back to split
        int jmp = re_emit(re, RE_JMP);
        if (jmp < 0) return -1;
        re->inst[jmp].x = start;
        re->inst[start].y = re->len; // skip to after jmp
        return start;
    }
    if (c == '+') {
        (*pos)++;
        // atom then split(atom, next)
        int sp = re_emit(re, RE_SPLIT);
        if (sp < 0) return -1;
        re->inst[sp].x = start;     // loop back
        re->inst[sp].y = re->len;   // continue
        return start;
    }
    if (c == '?') {
        (*pos)++;
        // split(atom, skip)
        for (int i = re->len; i > start; i--) {
            re->inst[i] = re->inst[i - 1];
        }
        re->len++;
        memset(&re->inst[start], 0, sizeof(ReInst));
        re->inst[start].type = RE_SPLIT;
        re->inst[start].x = start + 1;
        re->inst[start].y = re->len;
        return start;
    }
    if (c == '{') {
        // Parse {n}, {n,}, {n,m}
        (*pos)++;
        int n = 0, m = -1;
        while (*pos < plen && is_digit(p[*pos])) { n = n * 10 + (p[*pos] - '0'); (*pos)++; }
        if (*pos < plen && p[*pos] == ',') {
            (*pos)++;
            if (*pos < plen && p[*pos] != '}') {
                m = 0;
                while (*pos < plen && is_digit(p[*pos])) { m = m * 10 + (p[*pos] - '0'); (*pos)++; }
            } else {
                m = -1; // unbounded
            }
        } else {
            m = n; // exact
        }
        if (*pos < plen && p[*pos] == '}') (*pos)++;
        // For simplicity, we already have one copy of atom at [start..re->len)
        // We need n copies total for minimum, then optional copies for max
        int atom_len = re->len - start;
        // Duplicate atom (n-1) more times for minimum
        for (int i = 1; i < n; i++) {
            for (int j = 0; j < atom_len; j++) {
                if (re->len >= RE_MAX_INST) return -1;
                re->inst[re->len] = re->inst[start + j];
                re->len++;
            }
        }
        if (m == -1) {
            // {n,} = n copies + *
            int loop_start = re->len - atom_len;
            int sp = re_emit(re, RE_SPLIT);
            if (sp < 0) return -1;
            re->inst[sp].x = loop_start;
            re->inst[sp].y = re->len;
        } else if (m > n) {
            // {n,m} = n copies + (m-n) optional copies
            for (int i = n; i < m; i++) {
                int opt_start = re->len;
                int sp = re_emit(re, RE_SPLIT);
                if (sp < 0) return -1;
                re->inst[sp].x = sp + 1;
                for (int j = 0; j < atom_len; j++) {
                    if (re->len >= RE_MAX_INST) return -1;
                    re->inst[re->len] = re->inst[start + j];
                    re->len++;
                }
                re->inst[opt_start].y = re->len;
            }
        }
        return start;
    }
    return r;
}

// Parse concatenation: sequence of quantified atoms
static int re_parse_concat(ReCompiled* re, const char* p, int* pos, int plen) {
    int start = re->len;
    while (*pos < plen && p[*pos] != ')' && p[*pos] != '|') {
        if (re_parse_quantified(re, p, pos, plen) < 0) {
            if (re->error[0]) return -1;
            break;
        }
    }
    return start;
}

// Parse alternation: concat | concat | ...
static int re_compile_expr(ReCompiled* re, const char* p, int* pos, int plen) {
    int start = re->len;
    if (re_parse_concat(re, p, pos, plen) < 0 && re->error[0]) return -1;
    
    while (*pos < plen && p[*pos] == '|') {
        (*pos)++;
        // Insert split before first branch
        int first_end = re->len;
        int jmp_idx = re_emit(re, RE_JMP); // jump over second branch
        if (jmp_idx < 0) return -1;
        
        int second_start = re->len;
        if (re_parse_concat(re, p, pos, plen) < 0 && re->error[0]) return -1;
        
        // Now patch: insert SPLIT at start
        // Shift everything from start onwards by 1
        for (int i = re->len; i > start; i--) {
            re->inst[i] = re->inst[i - 1];
        }
        re->len++;
        memset(&re->inst[start], 0, sizeof(ReInst));
        re->inst[start].type = RE_SPLIT;
        re->inst[start].x = start + 1;           // first branch
        re->inst[start].y = second_start + 1;     // second branch (shifted by 1)
        
        // Fix the JMP target
        re->inst[jmp_idx + 1].x = re->len;        // jump to end (shifted by 1)
        
        start = re->len; // for chaining more alternations... actually we need to handle this differently
        // For simplicity, break after one alternation level
        // This handles a|b but not a|b|c correctly in all cases
        // Let's handle it by continuing the loop
    }
    return start;
}

static int re_match_char(ReInst* inst, int c, int flags) {
    int lc = c;
    if ((flags & 2) && c >= 'A' && c <= 'Z') lc = c + 32; // case insensitive
    switch (inst->type) {
        case RE_LIT: return lc == inst->ch;
        case RE_DOT: return c != '\n';
        case RE_DIGIT: return is_digit(c);
        case RE_NDIGIT: return !is_digit(c);
        case RE_WORD: return is_word(c);
        case RE_NWORD: return !is_word(c);
        case RE_SPACE: return is_space(c);
        case RE_NSPACE: return !is_space(c);
        case RE_CCLASS: return cc_test(inst->cclass, (flags & 2) ? lc : c);
        case RE_NCCLASS: return !cc_test(inst->cclass, (flags & 2) ? lc : c);
        default: return 0;
    }
}

// Recursive backtracking regex execution
static int re_bt(ReCompiled* re, const char* text, int tlen, int pc, int pos,
                 int32_t* groups) {
    while (pc < re->len) {
        ReInst* inst = &re->inst[pc];
        switch (inst->type) {
            case RE_MATCH:
                return 1;
            case RE_LIT:
                if (pos >= tlen) return 0;
                { int c = (unsigned char)text[pos];
                  if ((re->flags & 2) && c >= 'A' && c <= 'Z') c += 32;
                  if (c != inst->ch) return 0; }
                pos++; pc++; break;
            case RE_DOT:
                if (pos >= tlen || text[pos] == '\n') return 0;
                pos++; pc++; break;
            case RE_DIGIT:
                if (pos >= tlen || !is_digit((unsigned char)text[pos])) return 0;
                pos++; pc++; break;
            case RE_NDIGIT:
                if (pos >= tlen || is_digit((unsigned char)text[pos])) return 0;
                pos++; pc++; break;
            case RE_WORD:
                if (pos >= tlen || !is_word((unsigned char)text[pos])) return 0;
                pos++; pc++; break;
            case RE_NWORD:
                if (pos >= tlen || is_word((unsigned char)text[pos])) return 0;
                pos++; pc++; break;
            case RE_SPACE:
                if (pos >= tlen || !is_space((unsigned char)text[pos])) return 0;
                pos++; pc++; break;
            case RE_NSPACE:
                if (pos >= tlen || is_space((unsigned char)text[pos])) return 0;
                pos++; pc++; break;
            case RE_CCLASS:
                if (pos >= tlen) return 0;
                { int c = (unsigned char)text[pos];
                  if ((re->flags & 2) && c >= 'A' && c <= 'Z') c += 32;
                  if (!cc_test(inst->cclass, c)) return 0; }
                pos++; pc++; break;
            case RE_NCCLASS:
                if (pos >= tlen) return 0;
                { int c = (unsigned char)text[pos];
                  if ((re->flags & 2) && c >= 'A' && c <= 'Z') c += 32;
                  if (cc_test(inst->cclass, c)) return 0; }
                pos++; pc++; break;
            case RE_BOL:
                if (pos != 0 && !((re->flags & 4) && pos > 0 && text[pos - 1] == '\n')) return 0;
                pc++; break;
            case RE_EOL:
                if (pos != tlen && !((re->flags & 4) && text[pos] == '\n')) return 0;
                pc++; break;
            case RE_GROUP_S:
                if (inst->group < RE_MAX_GROUPS) {
                    int32_t old = groups[inst->group * 2];
                    groups[inst->group * 2] = pos;
                    if (re_bt(re, text, tlen, pc + 1, pos, groups)) return 1;
                    groups[inst->group * 2] = old;
                    return 0;
                }
                pc++; break;
            case RE_GROUP_E:
                if (inst->group < RE_MAX_GROUPS) {
                    int32_t old = groups[inst->group * 2 + 1];
                    groups[inst->group * 2 + 1] = pos;
                    if (re_bt(re, text, tlen, pc + 1, pos, groups)) return 1;
                    groups[inst->group * 2 + 1] = old;
                    return 0;
                }
                pc++; break;
            case RE_SPLIT:
                // Try primary branch first, then alternative
                if (re_bt(re, text, tlen, inst->x, pos, groups)) return 1;
                pc = inst->y; break;
            case RE_JMP:
                pc = inst->x; break;
            default:
                return 0;
        }
    }
    return 0;
}

static int re_exec(ReCompiled* re, const char* text, int text_offset, int max_groups,
                   int32_t* out_starts, int32_t* out_ends) {
    int tlen = (int)strlen(text);
    int32_t groups[RE_MAX_GROUPS * 2];
    
    for (int sp = text_offset; sp <= tlen; sp++) {
        for (int i = 0; i < RE_MAX_GROUPS * 2; i++) groups[i] = -1;
        
        if (re_bt(re, text, tlen, 0, sp, groups)) {
            int32_t mg = max_groups < RE_MAX_GROUPS ? max_groups : RE_MAX_GROUPS;
            int32_t result_count = 0;
            for (int32_t i = 0; i < mg; i++) {
                out_starts[i] = groups[i * 2];
                out_ends[i] = groups[i * 2 + 1];
                if (out_starts[i] >= 0) result_count = i + 1;
            }
            return result_count > 0 ? result_count : 1;
        }
    }
    
    return 0;
}

int32_t __koral_regex_compile(const char* pattern, int32_t flags,
                            void** out_handle,
                            char* out_error_buf, int32_t error_buf_size,
                            int32_t* out_error_len) {
    ReCompiled* re = (ReCompiled*)calloc(1, sizeof(ReCompiled));
    if (!re) {
        const char* msg = "out of memory";
        int32_t msg_len = (int32_t)strlen(msg);
        if (msg_len > error_buf_size - 1) msg_len = error_buf_size - 1;
        memcpy(out_error_buf, msg, (size_t)msg_len);
        *out_error_len = msg_len;
        return -1;
    }
    
    re->flags = flags;
    re->ngroups = 0;
    re->error[0] = '\0';
    
    int pos = 0;
    int plen = (int)strlen(pattern);
    
    // Start with group 0 (whole match)
    re->ngroups = 1;
    int gs = re_emit(re, RE_GROUP_S);
    re->inst[gs].group = 0;
    
    if (re_compile_expr(re, pattern, &pos, plen) < 0 && re->error[0]) {
        int32_t elen = (int32_t)strlen(re->error);
        if (elen > error_buf_size - 1) elen = error_buf_size - 1;
        memcpy(out_error_buf, re->error, (size_t)elen);
        *out_error_len = elen;
        free(re);
        return -1;
    }
    
    if (pos < plen) {
        // Unexpected characters remaining
        if (pattern[pos] == ')') {
            snprintf(re->error, 256, "Unmatched )");
        } else {
            snprintf(re->error, 256, "Unexpected character at position %d", pos);
        }
        int32_t elen = (int32_t)strlen(re->error);
        if (elen > error_buf_size - 1) elen = error_buf_size - 1;
        memcpy(out_error_buf, re->error, (size_t)elen);
        *out_error_len = elen;
        free(re);
        return -1;
    }
    
    int ge = re_emit(re, RE_GROUP_E);
    re->inst[ge].group = 0;
    re_emit(re, RE_MATCH);
    
    *out_handle = re;
    return 0;
}

int32_t __koral_regex_match(void* handle, const char* text, int32_t text_offset,
                          int32_t max_groups,
                          int32_t* out_starts, int32_t* out_ends) {
    ReCompiled* re = (ReCompiled*)handle;
    return re_exec(re, text, text_offset, max_groups, out_starts, out_ends);
}

void __koral_regex_free(void* handle) {
    free(handle);
}

#endif  // _WIN32 || _WIN64


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

int32_t __koral_stat(const uint8_t* path, KoralStatResult* out) {
    struct _stat64 st;
    if (_stat64((const char*)path, &st) != 0) return -1;
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
    return _chmod((const char*)path, (int)(mode & 0777)) == 0 ? 0 : -1;
}

int32_t __koral_link(const uint8_t* src, const uint8_t* dst) {
    return CreateHardLinkA((const char*)dst, (const char*)src, NULL) ? 0 : -1;
}

int32_t __koral_symlink(const uint8_t* src, const uint8_t* dst) {
    DWORD flags = 0;
    DWORD attrs = GetFileAttributesA((const char*)src);
    if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY))
        flags = SYMBOLIC_LINK_FLAG_DIRECTORY;
    return CreateSymbolicLinkA((const char*)dst, (const char*)src, flags) ? 0 : -1;
}

int32_t __koral_readlink(const uint8_t* path, uint8_t* buf, uint64_t buf_size) {
    (void)path; (void)buf; (void)buf_size;
    errno = ENOSYS;
    return -1;
}

int32_t __koral_truncate(const uint8_t* path, int64_t size) {
    HANDLE h = CreateFileA((const char*)path, GENERIC_WRITE, 0, NULL,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
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

int32_t __koral_is_symlink(const uint8_t* path) {
    DWORD attrs = GetFileAttributesA((const char*)path);
    if (attrs == INVALID_FILE_ATTRIBUTES) return 0;
    return (attrs & FILE_ATTRIBUTE_REPARSE_POINT) ? 1 : 0;
}

int32_t __koral_realpath(const uint8_t* path, uint8_t* buf, uint64_t size) {
    DWORD len = GetFullPathNameA((const char*)path, (DWORD)size, (char*)buf, NULL);
    if (len == 0 || len >= (DWORD)size) return -1;
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
    DWORD len = GetModuleFileNameA(NULL, (char*)buf, (DWORD)size);
    if (len == 0 || len >= (DWORD)size) return -1;
    return 0;
}

int32_t __koral_open(const uint8_t* path, int32_t open_mode, uint32_t perm) {
    int flags;
    int mode = _S_IREAD | _S_IWRITE;  // Windows only supports _S_IREAD/_S_IWRITE
    switch (open_mode) {
        case 0: flags = _O_RDONLY | _O_BINARY; break;                                              // Read
        case 1: flags = _O_WRONLY | _O_CREAT | _O_TRUNC | _O_BINARY; break;                        // Write
        case 2: flags = _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY; break;                         // Create
        case 3: flags = _O_WRONLY | _O_CREAT | _O_APPEND | _O_BINARY; break;                       // Append
        case 4: flags = _O_RDWR | _O_BINARY; break;                                                // ReadWrite
        default: return -1;
    }
    int fd;
    if (_sopen_s(&fd, (const char*)path, flags, _SH_DENYNO, mode) != 0)
        return -1;
    return (int32_t)fd;
}

int64_t __koral_read(int32_t fd, uint8_t* buf, uint64_t count) {
    return (int64_t)_read(fd, buf, (unsigned int)count);
}

int64_t __koral_write(int32_t fd, const uint8_t* buf, uint64_t count) {
    return (int64_t)_write(fd, buf, (unsigned int)count);
}

int64_t __koral_lseek(int32_t fd, int64_t offset, int32_t whence) {
    return (int64_t)_lseeki64(fd, offset, whence);
}

int32_t __koral_close(int32_t fd) {
    return _close(fd);
}

int32_t __koral_chdir(const uint8_t* path) {
    return _chdir((const char*)path);
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
    ssize_t len = readlink((const char*)path, (char*)buf, (size_t)buf_size - 1);
    if (len < 0) return -1;
    buf[len] = '\0';
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

int32_t __koral_is_symlink(const uint8_t* path) {
    struct stat st;
    if (lstat((const char*)path, &st) != 0) return 0;
    return S_ISLNK(st.st_mode) ? 1 : 0;
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


// ============================================================================
// Subprocess management (std.command)
// ============================================================================

#if !defined(_WIN32) && !defined(_WIN64)
#include <spawn.h>
#include <sys/wait.h>
#include <signal.h>
#include <poll.h>
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


// --- Wait operations ---

int32_t __koral_waitpid(uint32_t pid) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)pid);
    if (h == NULL) return -1;
    WaitForSingleObject(h, INFINITE);
    CloseHandle(h);
    return 0;
#else
    int status;
    while (waitpid((pid_t)pid, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return 0;
#endif
}

int32_t __koral_waitpid_full(uint32_t pid, int32_t* exit_code, int32_t* signal_num) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_INFORMATION, FALSE, (DWORD)pid);
    if (h == NULL) return -1;
    WaitForSingleObject(h, INFINITE);
    DWORD code;
    if (!GetExitCodeProcess(h, &code)) {
        CloseHandle(h);
        return -1;
    }
    CloseHandle(h);
    *exit_code = (int32_t)code;
    *signal_num = 0;
    return 0;
#else
    int status;
    while (waitpid((pid_t)pid, &status, 0) < 0) {
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
    return 0;
#endif
}

int32_t __koral_try_waitpid(uint32_t pid, int32_t* exit_code, int32_t* signal_num) {
#if defined(_WIN32) || defined(_WIN64)
    HANDLE h = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_INFORMATION, FALSE, (DWORD)pid);
    if (h == NULL) return -1;
    DWORD wait_result = WaitForSingleObject(h, 0);
    if (wait_result == WAIT_TIMEOUT) {
        CloseHandle(h);
        return 0;  // still running
    }
    if (wait_result != WAIT_OBJECT_0) {
        CloseHandle(h);
        return -1;
    }
    DWORD code;
    if (!GetExitCodeProcess(h, &code)) {
        CloseHandle(h);
        return -1;
    }
    CloseHandle(h);
    *exit_code = (int32_t)code;
    *signal_num = 0;
    return 1;  // exited
#else
    int status;
    pid_t result = waitpid((pid_t)pid, &status, WNOHANG);
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
    KoralProcess* out
) {
    HANDLE stdin_read = INVALID_HANDLE_VALUE, stdin_write = INVALID_HANDLE_VALUE;
    HANDLE stdout_read = INVALID_HANDLE_VALUE, stdout_write = INVALID_HANDLE_VALUE;
    HANDLE stderr_read = INVALID_HANDLE_VALUE, stderr_write = INVALID_HANDLE_VALUE;
    SECURITY_ATTRIBUTES sa = { sizeof(SECURITY_ATTRIBUTES), NULL, TRUE };

    // Create pipes as needed
    if (stdin_mode == 1) {
        if (!CreatePipe(&stdin_read, &stdin_write, &sa, 0)) return -1;
        SetHandleInformation(stdin_write, HANDLE_FLAG_INHERIT, 0);
    }
    if (stdout_mode == 1) {
        if (!CreatePipe(&stdout_read, &stdout_write, &sa, 0)) goto fail;
        SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0);
    }
    if (stderr_mode == 1) {
        if (!CreatePipe(&stderr_read, &stderr_write, &sa, 0)) goto fail;
        SetHandleInformation(stderr_read, HANDLE_FLAG_INHERIT, 0);
    }

    // Build command line string
    char cmdline[32768];
    int pos = 0;
    for (int i = 0; i < argc && pos < 32700; i++) {
        if (i > 0) cmdline[pos++] = ' ';
        cmdline[pos++] = '"';
        const char* arg = (const char*)argv[i];
        while (*arg && pos < 32700) {
            if (*arg == '"') cmdline[pos++] = '\\';
            cmdline[pos++] = *arg++;
        }
        cmdline[pos++] = '"';
    }
    cmdline[pos] = '\0';

    // Build environment block if needed
    char* env_block = NULL;
    if (envc > 0) {
        size_t total = 0;
        for (int i = 0; i < envc; i++) {
            total += strlen((const char*)envp[i]) + 1;
        }
        total += 1;  // double null terminator
        env_block = (char*)malloc(total);
        if (!env_block) goto fail;
        char* p = env_block;
        for (int i = 0; i < envc; i++) {
            size_t len = strlen((const char*)envp[i]);
            memcpy(p, envp[i], len);
            p[len] = '\0';
            p += len + 1;
        }
        *p = '\0';
    }

    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;

    // stdin
    if (stdin_mode == 1) si.hStdInput = stdin_read;
    else if (stdin_mode == 2) si.hStdInput = INVALID_HANDLE_VALUE;
    else si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    // stdout
    if (stdout_mode == 1) si.hStdOutput = stdout_write;
    else if (stdout_mode == 2) si.hStdOutput = INVALID_HANDLE_VALUE;
    else si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);

    // stderr
    if (stderr_mode == 1) si.hStdError = stderr_write;
    else if (stderr_mode == 2) si.hStdError = INVALID_HANDLE_VALUE;
    else si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    const char* work_dir = (cwd && cwd[0]) ? (const char*)cwd : NULL;

    memset(&pi, 0, sizeof(pi));
    BOOL ok = CreateProcessA(
        NULL, cmdline, NULL, NULL, TRUE,
        env_block ? CREATE_UNICODE_ENVIRONMENT : 0,
        env_block, work_dir, &si, &pi
    );

    if (env_block) free(env_block);

    if (!ok) goto fail;

    // Close child-side handles
    if (stdin_read != INVALID_HANDLE_VALUE) CloseHandle(stdin_read);
    if (stdout_write != INVALID_HANDLE_VALUE) CloseHandle(stdout_write);
    if (stderr_write != INVALID_HANDLE_VALUE) CloseHandle(stderr_write);
    CloseHandle(pi.hThread);

    out->pid = (uint32_t)pi.dwProcessId;
    out->stdin_fd = (stdin_mode == 1) ? _open_osfhandle((intptr_t)stdin_write, 0) : -1;
    out->stdout_fd = (stdout_mode == 1) ? _open_osfhandle((intptr_t)stdout_read, _O_RDONLY) : -1;
    out->stderr_fd = (stderr_mode == 1) ? _open_osfhandle((intptr_t)stderr_read, _O_RDONLY) : -1;

    // We need to keep the process handle for waitpid; store it... actually
    // Windows waitpid uses OpenProcess, so we can close this handle.
    CloseHandle(pi.hProcess);

    return 0;

fail:
    if (stdin_read != INVALID_HANDLE_VALUE) CloseHandle(stdin_read);
    if (stdin_write != INVALID_HANDLE_VALUE) CloseHandle(stdin_write);
    if (stdout_read != INVALID_HANDLE_VALUE) CloseHandle(stdout_read);
    if (stdout_write != INVALID_HANDLE_VALUE) CloseHandle(stdout_write);
    if (stderr_read != INVALID_HANDLE_VALUE) CloseHandle(stderr_read);
    if (stderr_write != INVALID_HANDLE_VALUE) CloseHandle(stderr_write);
    return -1;
}

#else  // POSIX

int32_t __koral_spawn(
    const uint8_t* program,
    const uint8_t** argv, int32_t argc,
    const uint8_t** envp, int32_t envc,
    const uint8_t* cwd,
    int32_t stdin_mode, int32_t stdout_mode, int32_t stderr_mode,
    KoralProcess* out
) {
    int stdin_pipe[2] = {-1, -1};
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
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

    // Build null-terminated envp array
    char** child_envp = NULL;
    if (envc > 0) {
        child_envp = (char**)malloc((envc + 1) * sizeof(char*));
        if (!child_envp) { free(child_argv); goto fail; }
        for (int i = 0; i < envc; i++) {
            child_envp[i] = (char*)envp[i];
        }
        child_envp[envc] = NULL;
    }

    // Check if cwd is set
    int use_cwd = (cwd && cwd[0]);

    // Use fork+exec if cwd is set (posix_spawn_file_actions_addchdir_np
    // is not portable), otherwise use posix_spawn
    pid_t child_pid;
    int spawn_err = 0;

    if (use_cwd) {
        // fork+exec approach for cwd support
        child_pid = fork();
        if (child_pid < 0) {
            spawn_err = errno;
            free(child_argv);
            if (child_envp) free(child_envp);
            goto fail;
        }
        if (child_pid == 0) {
            // Child process
            if (chdir((const char*)cwd) < 0) _exit(127);

            // Set up stdin
            if (stdin_mode == 1) {
                dup2(stdin_pipe[0], STDIN_FILENO);
                close(stdin_pipe[0]);
                close(stdin_pipe[1]);
            } else if (stdin_mode == 2) {
                dup2(null_fd, STDIN_FILENO);
            }

            // Set up stdout
            if (stdout_mode == 1) {
                dup2(stdout_pipe[1], STDOUT_FILENO);
                close(stdout_pipe[0]);
                close(stdout_pipe[1]);
            } else if (stdout_mode == 2) {
                dup2(null_fd, STDOUT_FILENO);
            }

            // Set up stderr
            if (stderr_mode == 1) {
                dup2(stderr_pipe[1], STDERR_FILENO);
                close(stderr_pipe[0]);
                close(stderr_pipe[1]);
            } else if (stderr_mode == 2) {
                dup2(null_fd, STDERR_FILENO);
            }

            if (null_fd >= 0) close(null_fd);

            if (child_envp) {
                execve((const char*)program, child_argv, child_envp);
            } else {
                execvp((const char*)program, child_argv);
            }
            _exit(127);
        }
    } else {
        // posix_spawn approach (more efficient, no fork overhead)
        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);

        // stdin
        if (stdin_mode == 1) {
            posix_spawn_file_actions_adddup2(&actions, stdin_pipe[0], STDIN_FILENO);
            posix_spawn_file_actions_addclose(&actions, stdin_pipe[0]);
            posix_spawn_file_actions_addclose(&actions, stdin_pipe[1]);
        } else if (stdin_mode == 2) {
            posix_spawn_file_actions_adddup2(&actions, null_fd, STDIN_FILENO);
        }

        // stdout
        if (stdout_mode == 1) {
            posix_spawn_file_actions_adddup2(&actions, stdout_pipe[1], STDOUT_FILENO);
            posix_spawn_file_actions_addclose(&actions, stdout_pipe[0]);
            posix_spawn_file_actions_addclose(&actions, stdout_pipe[1]);
        } else if (stdout_mode == 2) {
            posix_spawn_file_actions_adddup2(&actions, null_fd, STDOUT_FILENO);
        }

        // stderr
        if (stderr_mode == 1) {
            posix_spawn_file_actions_adddup2(&actions, stderr_pipe[1], STDERR_FILENO);
            posix_spawn_file_actions_addclose(&actions, stderr_pipe[0]);
            posix_spawn_file_actions_addclose(&actions, stderr_pipe[1]);
        } else if (stderr_mode == 2) {
            posix_spawn_file_actions_adddup2(&actions, null_fd, STDERR_FILENO);
        }

        if (null_fd >= 0) {
            posix_spawn_file_actions_addclose(&actions, null_fd);
        }

        if (child_envp) {
            spawn_err = posix_spawn(&child_pid, (const char*)program, &actions, NULL,
                                    child_argv, child_envp);
        } else {
            extern char** environ;
            spawn_err = posix_spawnp(&child_pid, (const char*)program, &actions, NULL,
                                     child_argv, environ);
        }

        posix_spawn_file_actions_destroy(&actions);
    }

    free(child_argv);
    if (child_envp) free(child_envp);

    if (spawn_err != 0) {
        errno = spawn_err;
        goto fail;
    }

    // Close child-side pipe ends in parent
    if (stdin_pipe[0] >= 0) close(stdin_pipe[0]);
    if (stdout_pipe[1] >= 0) close(stdout_pipe[1]);
    if (stderr_pipe[1] >= 0) close(stderr_pipe[1]);
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
    // Windows: read stdout first, then stderr (simple approach)
    while (1) {
        int64_t n = __koral_pipe_read(stdout_fd, tmp, sizeof(tmp));
        if (n < 0) goto fail;
        if (n == 0) break;
        if (dynbuf_append(&stdout_buf, tmp, (uint64_t)n) < 0) goto fail;
    }
    while (1) {
        int64_t n = __koral_pipe_read(stderr_fd, tmp, sizeof(tmp));
        if (n < 0) goto fail;
        if (n == 0) break;
        if (dynbuf_append(&stderr_buf, tmp, (uint64_t)n) < 0) goto fail;
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
    uint64_t* tid_ptr;       // pointer to out_tid (POSIX: written by new thread)
#if !defined(_WIN32) && !defined(_WIN64)
    volatile int tid_ready;  // atomic flag for POSIX synchronization
#endif
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
    args->tid_ptr = out_tid;

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
    DWORD result = WaitForSingleObject((HANDLE)handle, INFINITE);
    CloseHandle((HANDLE)handle);
    return (result == WAIT_OBJECT_0) ? 0 : -1;
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
    // Write thread ID before calling the closure so the parent can read it.
    *(args->tid_ptr) = (uint64_t)pthread_self();
    __atomic_store_n(&args->tid_ready, 1, __ATOMIC_RELEASE);
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
    args->tid_ptr = out_tid;
    args->tid_ready = 0;

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
    // Wait until the new thread has written its tid.
    while (!__atomic_load_n(&args->tid_ready, __ATOMIC_ACQUIRE)) {
        sched_yield();
    }
    *out_handle = (uint8_t*)thread;
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

int32_t __koral_timer_context_is_cancelled(void* raw) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    return (int32_t)(*(volatile int*)&ctx->cancelled);
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

int32_t __koral_timer_context_is_cancelled(void* raw) {
    KoralTimerContext* ctx = (KoralTimerContext*)raw;
    return (int32_t)__atomic_load_n(&ctx->cancelled, __ATOMIC_ACQUIRE);
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

void* __koral_mutex_create(void) {
    CRITICAL_SECTION* cs = (CRITICAL_SECTION*)malloc(sizeof(CRITICAL_SECTION));
    if (!cs) return NULL;
    InitializeCriticalSection(cs);
    return (void*)cs;
}

void __koral_mutex_destroy(void* mutex) {
    if (!mutex) return;
    DeleteCriticalSection((CRITICAL_SECTION*)mutex);
    free(mutex);
}

void __koral_mutex_lock(void* mutex) {
    EnterCriticalSection((CRITICAL_SECTION*)mutex);
}

int32_t __koral_mutex_try_lock(void* mutex) {
    return TryEnterCriticalSection((CRITICAL_SECTION*)mutex) ? 1 : 0;
}

void __koral_mutex_unlock(void* mutex) {
    LeaveCriticalSection((CRITICAL_SECTION*)mutex);
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
    SleepConditionVariableCS(&cv->cv, (CRITICAL_SECTION*)mutex, INFINITE);
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
// Atomic Operations
// ============================================================================

// --- i32 atomics (used by AtomicBool) ---

#if defined(_WIN32) || defined(_WIN64)

int32_t __koral_atomic_load_i32(int32_t* ptr) {
    // Read via InterlockedCompareExchange to get a seq_cst load
    return InterlockedCompareExchange((volatile LONG*)ptr, 0, 0);
}

void __koral_atomic_store_i32(int32_t* ptr, int32_t value) {
    InterlockedExchange((volatile LONG*)ptr, (LONG)value);
}

int32_t __koral_atomic_swap_i32(int32_t* ptr, int32_t value) {
    return (int32_t)InterlockedExchange((volatile LONG*)ptr, (LONG)value);
}

int32_t __koral_atomic_cas_i32(int32_t* ptr, int32_t expected, int32_t desired) {
    LONG old = InterlockedCompareExchange((volatile LONG*)ptr, (LONG)desired, (LONG)expected);
    return old == (LONG)expected ? 1 : 0;
}

#else

int32_t __koral_atomic_load_i32(int32_t* ptr) {
    return __atomic_load_n(ptr, __ATOMIC_SEQ_CST);
}

void __koral_atomic_store_i32(int32_t* ptr, int32_t value) {
    __atomic_store_n(ptr, value, __ATOMIC_SEQ_CST);
}

int32_t __koral_atomic_swap_i32(int32_t* ptr, int32_t value) {
    return __atomic_exchange_n(ptr, value, __ATOMIC_SEQ_CST);
}

int32_t __koral_atomic_cas_i32(int32_t* ptr, int32_t expected, int32_t desired) {
    return __atomic_compare_exchange_n(ptr, &expected, desired, 0,
                                       __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST) ? 1 : 0;
}

#endif

// --- intptr_t atomics (used by AtomicInt) ---

#if defined(_WIN32) || defined(_WIN64)

intptr_t __koral_atomic_load_iptr(intptr_t* ptr) {
#ifdef _WIN64
    return (intptr_t)InterlockedCompareExchange64((volatile LONG64*)ptr, 0, 0);
#else
    return (intptr_t)InterlockedCompareExchange((volatile LONG*)ptr, 0, 0);
#endif
}

void __koral_atomic_store_iptr(intptr_t* ptr, intptr_t value) {
#ifdef _WIN64
    InterlockedExchange64((volatile LONG64*)ptr, (LONG64)value);
#else
    InterlockedExchange((volatile LONG*)ptr, (LONG)value);
#endif
}

intptr_t __koral_atomic_swap_iptr(intptr_t* ptr, intptr_t value) {
#ifdef _WIN64
    return (intptr_t)InterlockedExchange64((volatile LONG64*)ptr, (LONG64)value);
#else
    return (intptr_t)InterlockedExchange((volatile LONG*)ptr, (LONG)value);
#endif
}

int32_t __koral_atomic_cas_iptr(intptr_t* ptr, intptr_t expected, intptr_t desired) {
#ifdef _WIN64
    LONG64 old = InterlockedCompareExchange64((volatile LONG64*)ptr, (LONG64)desired, (LONG64)expected);
    return old == (LONG64)expected ? 1 : 0;
#else
    LONG old = InterlockedCompareExchange((volatile LONG*)ptr, (LONG)desired, (LONG)expected);
    return old == (LONG)expected ? 1 : 0;
#endif
}

intptr_t __koral_atomic_fetch_add_iptr(intptr_t* ptr, intptr_t delta) {
#ifdef _WIN64
    return (intptr_t)InterlockedExchangeAdd64((volatile LONG64*)ptr, (LONG64)delta);
#else
    return (intptr_t)InterlockedExchangeAdd((volatile LONG*)ptr, (LONG)delta);
#endif
}

intptr_t __koral_atomic_fetch_sub_iptr(intptr_t* ptr, intptr_t delta) {
#ifdef _WIN64
    return (intptr_t)InterlockedExchangeAdd64((volatile LONG64*)ptr, -(LONG64)delta);
#else
    return (intptr_t)InterlockedExchangeAdd((volatile LONG*)ptr, -(LONG)delta);
#endif
}

#else

intptr_t __koral_atomic_load_iptr(intptr_t* ptr) {
    return __atomic_load_n(ptr, __ATOMIC_SEQ_CST);
}

void __koral_atomic_store_iptr(intptr_t* ptr, intptr_t value) {
    __atomic_store_n(ptr, value, __ATOMIC_SEQ_CST);
}

intptr_t __koral_atomic_swap_iptr(intptr_t* ptr, intptr_t value) {
    return __atomic_exchange_n(ptr, value, __ATOMIC_SEQ_CST);
}

int32_t __koral_atomic_cas_iptr(intptr_t* ptr, intptr_t expected, intptr_t desired) {
    return __atomic_compare_exchange_n(ptr, &expected, desired, 0,
                                       __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST) ? 1 : 0;
}

intptr_t __koral_atomic_fetch_add_iptr(intptr_t* ptr, intptr_t delta) {
    return __atomic_fetch_add(ptr, delta, __ATOMIC_SEQ_CST);
}

intptr_t __koral_atomic_fetch_sub_iptr(intptr_t* ptr, intptr_t delta) {
    return __atomic_fetch_sub(ptr, delta, __ATOMIC_SEQ_CST);
}

#endif

// --- uintptr_t atomics (used by AtomicUInt) ---

#if defined(_WIN32) || defined(_WIN64)

uintptr_t __koral_atomic_load_uptr(uintptr_t* ptr) {
#ifdef _WIN64
    return (uintptr_t)InterlockedCompareExchange64((volatile LONG64*)ptr, 0, 0);
#else
    return (uintptr_t)InterlockedCompareExchange((volatile LONG*)ptr, 0, 0);
#endif
}

void __koral_atomic_store_uptr(uintptr_t* ptr, uintptr_t value) {
#ifdef _WIN64
    InterlockedExchange64((volatile LONG64*)ptr, (LONG64)value);
#else
    InterlockedExchange((volatile LONG*)ptr, (LONG)value);
#endif
}

uintptr_t __koral_atomic_swap_uptr(uintptr_t* ptr, uintptr_t value) {
#ifdef _WIN64
    return (uintptr_t)InterlockedExchange64((volatile LONG64*)ptr, (LONG64)value);
#else
    return (uintptr_t)InterlockedExchange((volatile LONG*)ptr, (LONG)value);
#endif
}

int32_t __koral_atomic_cas_uptr(uintptr_t* ptr, uintptr_t expected, uintptr_t desired) {
#ifdef _WIN64
    LONG64 old = InterlockedCompareExchange64((volatile LONG64*)ptr, (LONG64)desired, (LONG64)expected);
    return old == (LONG64)expected ? 1 : 0;
#else
    LONG old = InterlockedCompareExchange((volatile LONG*)ptr, (LONG)desired, (LONG)expected);
    return old == (LONG)expected ? 1 : 0;
#endif
}

uintptr_t __koral_atomic_fetch_add_uptr(uintptr_t* ptr, uintptr_t delta) {
#ifdef _WIN64
    return (uintptr_t)InterlockedExchangeAdd64((volatile LONG64*)ptr, (LONG64)delta);
#else
    return (uintptr_t)InterlockedExchangeAdd((volatile LONG*)ptr, (LONG)delta);
#endif
}

uintptr_t __koral_atomic_fetch_sub_uptr(uintptr_t* ptr, uintptr_t delta) {
#ifdef _WIN64
    return (uintptr_t)InterlockedExchangeAdd64((volatile LONG64*)ptr, -(LONG64)delta);
#else
    return (uintptr_t)InterlockedExchangeAdd((volatile LONG*)ptr, -(LONG)delta);
#endif
}

#else

uintptr_t __koral_atomic_load_uptr(uintptr_t* ptr) {
    return __atomic_load_n(ptr, __ATOMIC_SEQ_CST);
}

void __koral_atomic_store_uptr(uintptr_t* ptr, uintptr_t value) {
    __atomic_store_n(ptr, value, __ATOMIC_SEQ_CST);
}

uintptr_t __koral_atomic_swap_uptr(uintptr_t* ptr, uintptr_t value) {
    return __atomic_exchange_n(ptr, value, __ATOMIC_SEQ_CST);
}

int32_t __koral_atomic_cas_uptr(uintptr_t* ptr, uintptr_t expected, uintptr_t desired) {
    return __atomic_compare_exchange_n(ptr, &expected, desired, 0,
                                       __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST) ? 1 : 0;
}

uintptr_t __koral_atomic_fetch_add_uptr(uintptr_t* ptr, uintptr_t delta) {
    return __atomic_fetch_add(ptr, delta, __ATOMIC_SEQ_CST);
}

uintptr_t __koral_atomic_fetch_sub_uptr(uintptr_t* ptr, uintptr_t delta) {
    return __atomic_fetch_sub(ptr, delta, __ATOMIC_SEQ_CST);
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

int64_t __koral_socket_create(int32_t domain, int32_t type, int32_t protocol) {
    int s = socket(domain, type, protocol);
    if (s < 0) return -1;
    return (int64_t)s;
}

int32_t __koral_socket_close(int64_t fd) {
    return close((int)fd) == 0 ? 0 : -1;
}

int32_t __koral_socket_bind(int64_t fd, uint8_t* addr, uint32_t addr_len) {
    return bind((int)fd, (const struct sockaddr*)addr, (socklen_t)addr_len) == 0 ? 0 : -1;
}

int32_t __koral_socket_listen(int64_t fd, int32_t backlog) {
    return listen((int)fd, backlog) == 0 ? 0 : -1;
}

int64_t __koral_socket_accept(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    socklen_t alen = addr_len_out ? (socklen_t)*addr_len_out : 0;
    int s = accept((int)fd, (struct sockaddr*)addr_out, addr_len_out ? &alen : NULL);
    if (s < 0) return -1;
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return (int64_t)s;
}

int32_t __koral_socket_connect(int64_t fd, uint8_t* addr, uint32_t addr_len) {
    return connect((int)fd, (const struct sockaddr*)addr, (socklen_t)addr_len) == 0 ? 0 : -1;
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
    ssize_t n = sendto((int)fd, buf, (size_t)len, flags,
                       (const struct sockaddr*)addr, (socklen_t)addr_len);
    return (int64_t)n;
}

int64_t __koral_socket_recvfrom(int64_t fd, uint8_t* buf, uint64_t len,
                              int32_t flags, uint8_t* addr_out, uint32_t* addr_len_out) {
    socklen_t alen = addr_len_out ? (socklen_t)*addr_len_out : 0;
    ssize_t n = recvfrom((int)fd, buf, (size_t)len, flags,
                         (struct sockaddr*)addr_out, addr_len_out ? &alen : NULL);
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return (int64_t)n;
}

int32_t __koral_socket_shutdown(int64_t fd, int32_t how) {
    return shutdown((int)fd, how) == 0 ? 0 : -1;
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
    socklen_t alen = addr_len_out ? (socklen_t)*addr_len_out : 0;
    if (getsockname((int)fd, (struct sockaddr*)addr_out, &alen) != 0) return -1;
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return 0;
}

int32_t __koral_socket_getpeername(int64_t fd, uint8_t* addr_out, uint32_t* addr_len_out) {
    socklen_t alen = addr_len_out ? (socklen_t)*addr_len_out : 0;
    if (getpeername((int)fd, (struct sockaddr*)addr_out, &alen) != 0) return -1;
    if (addr_len_out) *addr_len_out = (uint32_t)alen;
    return 0;
}

#endif  // _WIN32 || _WIN64

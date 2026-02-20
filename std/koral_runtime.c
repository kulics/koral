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

#if !defined(_WIN32) && !defined(_WIN64)
#include <regex.h>
#endif

typedef struct CFile CFile;

static int32_t koral_argc_storage = 0;
static uint8_t** koral_argv_storage = NULL;

void koral_set_args(int32_t argc, uint8_t** argv) {
    koral_argc_storage = argc;
    koral_argv_storage = argv;
}

int32_t koral_argc(void) {
    return koral_argc_storage;
}

uint8_t** koral_argv(void) {
    return koral_argv_storage;
}

CFile* koral_stdin(void) {
    return (CFile*)stdin;
}

CFile* koral_stdout(void) {
    return (CFile*)stdout;
}

CFile* koral_stderr(void) {
    return (CFile*)stderr;
}

void koral_panic_float_cast_overflow(void) {
    fprintf(stderr, "Panic: float-to-int cast overflow\n");
    abort();
}

void koral_panic_overflow_add(void) {
    fprintf(stderr, "Panic: integer overflow in addition\n");
    abort();
}

void koral_panic_overflow_sub(void) {
    fprintf(stderr, "Panic: integer overflow in subtraction\n");
    abort();
}

void koral_panic_overflow_mul(void) {
    fprintf(stderr, "Panic: integer overflow in multiplication\n");
    abort();
}

void koral_panic_overflow_div(void) {
    fprintf(stderr, "Panic: integer overflow in division\n");
    abort();
}

void koral_panic_overflow_mod(void) {
    fprintf(stderr, "Panic: integer overflow in modulo\n");
    abort();
}

void koral_panic_overflow_neg(void) {
    fprintf(stderr, "Panic: integer overflow in negation\n");
    abort();
}

void koral_panic_overflow_shift(void) {
    fprintf(stderr, "Panic: integer overflow in shift\n");
    abort();
}

// Define Koral-side timespec layout (must match generated struct in C output)
struct KoralTimespec {
    int64_t tv_sec;
    int64_t tv_nsec;
};

#if defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#include <direct.h>
#include <io.h>
#include <sys/stat.h>

int koral_nanosleep(struct KoralTimespec *req, struct KoralTimespec *rem) {
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

int koral_nanosleep(struct KoralTimespec *req, struct KoralTimespec *rem) {
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

int koral_normalize_path(const char* path, char* buf, size_t size) {
    normalize_path_internal(path, buf, size);
    return (int)strlen(buf);
}

char koral_path_separator(void) {
#ifdef _WIN32
    return '\\';
#else
    return '/';
#endif
}

int koral_path_exists(const char* path) {
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

int koral_is_file(const char* path) {
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

int koral_is_dir(const char* path) {
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

CDirHandle* koral_opendir(const char* path) {
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

CDirEntry* koral_readdir(CDirHandle* dir) {
#ifdef _WIN32
    static CDirEntry entry;
    if (dir->first) {
        dir->first = false;
        strcpy(entry.name, dir->data.cFileName);
        return &entry;
    }
    if (FindNextFileA(dir->handle, &dir->data)) {
        strcpy(entry.name, dir->data.cFileName);
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

int koral_closedir(CDirHandle* dir) {
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

const char* koral_dirent_name(CDirEntry* entry) {
#ifdef _WIN32
    return entry->name;
#else
    return entry->entry.d_name;
#endif
}

int koral_mkdir(const char* path, unsigned int mode) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    (void)mode;
    return _mkdir(normalized);
#else
    return mkdir(normalized, mode);
#endif
}

int koral_rmdir(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    return _rmdir(normalized);
#else
    return rmdir(normalized);
#endif
}

char* koral_getcwd(char* buf, size_t size) {
#ifdef _WIN32
    return _getcwd(buf, (int)size);
#else
    return getcwd(buf, size);
#endif
}

// ============================================================================
// Environment helpers
// ============================================================================

int koral_setenv(const char* name, const char* value) {
#ifdef _WIN32
    return _putenv_s(name, value);
#else
    return setenv(name, value, 1);
#endif
}

// ============================================================================
// Error helpers
// ============================================================================

int* koral_errno_ptr(void) {
#ifdef _WIN32
    return _errno();
#else
    return &errno;
#endif
}

const char* koral_strerror(int errnum) {
    return strerror(errnum);
}

// ============================================================================
// Float bit conversions
// ============================================================================

uint32_t koral_float32_to_bits(float value) {
    uint32_t bits = 0;
    memcpy(&bits, &value, sizeof(uint32_t));
    return bits;
}

float koral_float32_from_bits(uint32_t bits) {
    float value = 0.0f;
    memcpy(&value, &bits, sizeof(uint32_t));
    return value;
}

uint64_t koral_float64_to_bits(double value) {
    uint64_t bits = 0;
    memcpy(&bits, &value, sizeof(uint64_t));
    return bits;
}

double koral_float64_from_bits(uint64_t bits) {
    double value = 0.0;
    memcpy(&value, &bits, sizeof(uint64_t));
    return value;
}

// ============================================================================
// File helpers (stdlib wrappers)
// ============================================================================

int32_t koral_remove(const uint8_t* path) {
    return (int32_t)remove((const char*)path);
}

int32_t koral_rename(const uint8_t* old_path, const uint8_t* new_path) {
    return (int32_t)rename((const char*)old_path, (const char*)new_path);
}

uint8_t* koral_getenv(const uint8_t* name) {
    return (uint8_t*)getenv((const char*)name);
}

int32_t koral_system(const uint8_t* command) {
    return (int32_t)system((const char*)command);
}

// ============================================================================
// Time helpers
// ============================================================================

void koral_monotonic_now(int64_t* out_secs, int64_t* out_nanos) {
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

void koral_wallclock_now(int64_t* out_secs, int64_t* out_nanos) {
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

void koral_local_timezone_offset(int32_t* out_offset_secs) {
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

int32_t koral_local_timezone_name(char* buf, int32_t buf_size) {
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
static const char* koral_zoneinfo_dirs[] = {
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
    for (int i = 0; koral_zoneinfo_dirs[i] != NULL; i++) {
        int n = snprintf(path_buf, path_buf_size, "%s%s", koral_zoneinfo_dirs[i], name);
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

int32_t koral_timezone_name_exists(const char* name) {
#if defined(_WIN32) || defined(_WIN64)
    (void)name;
    return 0;
#else
    if (!name || name[0] == '\0') return 0;
    char path[512];
    return tzif_find_file(name, path, sizeof(path)) ? 1 : 0;
#endif
}

void koral_timezone_offset_at(const char* name, int64_t unix_secs, int32_t* out_offset_secs) {
#if defined(_WIN32) || defined(_WIN64)
    (void)name;
    (void)unix_secs;
    // Windows: only support local timezone via GetTimeZoneInformation
    koral_local_timezone_offset(out_offset_secs);
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
double koral_f64_sqrt(double x) { return sqrt(x); }
double koral_f64_cbrt(double x) { return cbrt(x); }
double koral_f64_pow(double x, double y) { return pow(x, y); }
double koral_f64_hypot(double x, double y) { return hypot(x, y); }
double koral_f64_exp(double x) { return exp(x); }
double koral_f64_exp2(double x) { return exp2(x); }
double koral_f64_expm1(double x) { return expm1(x); }
double koral_f64_log(double x) { return log(x); }
double koral_f64_log2(double x) { return log2(x); }
double koral_f64_log10(double x) { return log10(x); }
double koral_f64_log1p(double x) { return log1p(x); }
double koral_f64_sin(double x) { return sin(x); }
double koral_f64_cos(double x) { return cos(x); }
double koral_f64_tan(double x) { return tan(x); }
double koral_f64_asin(double x) { return asin(x); }
double koral_f64_acos(double x) { return acos(x); }
double koral_f64_atan(double x) { return atan(x); }
double koral_f64_atan2(double y, double x) { return atan2(y, x); }
double koral_f64_sinh(double x) { return sinh(x); }
double koral_f64_cosh(double x) { return cosh(x); }
double koral_f64_tanh(double x) { return tanh(x); }
double koral_f64_asinh(double x) { return asinh(x); }
double koral_f64_acosh(double x) { return acosh(x); }
double koral_f64_atanh(double x) { return atanh(x); }
double koral_f64_floor(double x) { return floor(x); }
double koral_f64_ceil(double x) { return ceil(x); }
double koral_f64_round(double x) { return round(x); }
double koral_f64_trunc(double x) { return trunc(x); }
double koral_f64_fabs(double x) { return fabs(x); }
double koral_f64_copysign(double x, double y) { return copysign(x, y); }
double koral_f64_fmod(double x, double y) { return fmod(x, y); }
double koral_f64_fma(double x, double y, double z) { return fma(x, y, z); }
double koral_f64_erf(double x) { return erf(x); }
double koral_f64_erfc(double x) { return erfc(x); }
double koral_f64_tgamma(double x) { return tgamma(x); }
double koral_f64_lgamma(double x) { return lgamma(x); }

// ============================================================================
// Math wrapper functions (Float32 / float)
// ============================================================================
float koral_f32_sqrt(float x) { return sqrtf(x); }
float koral_f32_cbrt(float x) { return cbrtf(x); }
float koral_f32_pow(float x, float y) { return powf(x, y); }
float koral_f32_hypot(float x, float y) { return hypotf(x, y); }
float koral_f32_exp(float x) { return expf(x); }
float koral_f32_exp2(float x) { return exp2f(x); }
float koral_f32_expm1(float x) { return expm1f(x); }
float koral_f32_log(float x) { return logf(x); }
float koral_f32_log2(float x) { return log2f(x); }
float koral_f32_log10(float x) { return log10f(x); }
float koral_f32_log1p(float x) { return log1pf(x); }
float koral_f32_sin(float x) { return sinf(x); }
float koral_f32_cos(float x) { return cosf(x); }
float koral_f32_tan(float x) { return tanf(x); }
float koral_f32_asin(float x) { return asinf(x); }
float koral_f32_acos(float x) { return acosf(x); }
float koral_f32_atan(float x) { return atanf(x); }
float koral_f32_atan2(float y, float x) { return atan2f(y, x); }
float koral_f32_sinh(float x) { return sinhf(x); }
float koral_f32_cosh(float x) { return coshf(x); }
float koral_f32_tanh(float x) { return tanhf(x); }
float koral_f32_asinh(float x) { return asinhf(x); }
float koral_f32_acosh(float x) { return acoshf(x); }
float koral_f32_atanh(float x) { return atanhf(x); }
float koral_f32_floor(float x) { return floorf(x); }
float koral_f32_ceil(float x) { return ceilf(x); }
float koral_f32_round(float x) { return roundf(x); }
float koral_f32_trunc(float x) { return truncf(x); }
float koral_f32_fabs(float x) { return fabsf(x); }
float koral_f32_copysign(float x, float y) { return copysignf(x, y); }
float koral_f32_fmod(float x, float y) { return fmodf(x, y); }
float koral_f32_fma(float x, float y, float z) { return fmaf(x, y, z); }
float koral_f32_erf(float x) { return erff(x); }
float koral_f32_erfc(float x) { return erfcf(x); }
float koral_f32_tgamma(float x) { return tgammaf(x); }
float koral_f32_lgamma(float x) { return lgammaf(x); }

// ============================================================================
// Random: system entropy source
// ============================================================================

#if defined(_WIN32) || defined(_WIN64)

#include <bcrypt.h>
// Link with bcrypt.lib (MSVC) or -lbcrypt (MinGW)

int32_t koral_random_fill(uint8_t* buf, int32_t len) {
    if (!buf || len <= 0) return -1;
    NTSTATUS status = BCryptGenRandom(NULL, buf, (ULONG)len,
                                      BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    return (status >= 0) ? 0 : -1;
}

#elif defined(__APPLE__)

#include <stdlib.h>

int32_t koral_random_fill(uint8_t* buf, int32_t len) {
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

static int koral_random_fill_urandom(uint8_t* buf, int32_t len) {
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

int32_t koral_random_fill(uint8_t* buf, int32_t len) {
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
                return koral_random_fill_urandom(buf, len);
            }
            return -1;
        }
        remaining -= (int32_t)ret;
    }
    return 0;
#else
    return koral_random_fill_urandom(buf, len);
#endif
}

#endif

// ============================================================================
// Regex: POSIX regular expression support
// ============================================================================

#if !defined(_WIN32) && !defined(_WIN64)

int32_t koral_regex_compile(const char* pattern, int32_t flags,
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

int32_t koral_regex_match(void* handle, const char* text, int32_t text_offset,
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

void koral_regex_free(void* handle) {
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

int32_t koral_regex_compile(const char* pattern, int32_t flags,
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

int32_t koral_regex_match(void* handle, const char* text, int32_t text_offset,
                          int32_t max_groups,
                          int32_t* out_starts, int32_t* out_ends) {
    ReCompiled* re = (ReCompiled*)handle;
    return re_exec(re, text, text_offset, max_groups, out_starts, out_ends);
}

void koral_regex_free(void* handle) {
    free(handle);
}

#endif  // _WIN32 || _WIN64


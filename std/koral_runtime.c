// Koral runtime helpers (platform shims)
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>

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

bool koral_path_exists(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    struct _stat st;
    return _stat(normalized, &st) == 0;
#else
    struct stat st;
    return stat(normalized, &st) == 0;
#endif
}

bool koral_is_file(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    struct _stat st;
    if (_stat(normalized, &st) != 0) return false;
    return (st.st_mode & _S_IFREG) != 0;
#else
    struct stat st;
    if (stat(normalized, &st) != 0) return false;
    return S_ISREG(st.st_mode);
#endif
}

bool koral_is_dir(const char* path) {
    char normalized[4096];
    normalize_path_internal(path, normalized, sizeof(normalized));
#ifdef _WIN32
    struct _stat st;
    if (_stat(normalized, &st) != 0) return false;
    return (st.st_mode & _S_IFDIR) != 0;
#else
    struct stat st;
    if (stat(normalized, &st) != 0) return false;
    return S_ISDIR(st.st_mode);
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

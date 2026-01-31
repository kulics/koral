// Koral runtime helpers (platform sleep shim)
#include <stdint.h>
#include <stdio.h>

// Define Koral-side timespec layout (must match generated struct in C output)
struct KoralTimespec {
    int64_t tv_sec;
    int64_t tv_nsec;
};

#if defined(_WIN32) || defined(_WIN64)
#include <windows.h>

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
#include <time.h>
#include <errno.h>

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

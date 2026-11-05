// Compiled together with the generated C via `modules.<key>.c_sources`
// (cffi-design.md §E). Calls back into Koral through the generated
// koral_exports.h: the export prototypes carry C names, not Koral names.
#include "koral_exports.h"

int32_t c_multiply(int32_t a, int32_t b) {
    return a * b;
}

int32_t c_call_export(int32_t x) {
    return koral_double(x) + 1;
}

int32_t c_read_flag(void) {
    return koral_flag;
}

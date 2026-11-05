// Declared under `platform.<os>.c_sources` for every os atom: whichever host
// runs this case, the overlay lookup must find and compile it.
#include <stdint.h>

int32_t c_add(int32_t a, int32_t b) {
    return a + b;
}

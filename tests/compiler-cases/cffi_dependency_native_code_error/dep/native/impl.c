/* A dependency's native code: the trust gate refuses this file at load
   time, before any C is compiled. */
int dep_native_marker(void) { return 1; }

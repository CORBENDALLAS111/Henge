#ifndef HENGE_PVG_RETRY_H
#define HENGE_PVG_RETRY_H
#include <stdint.h>
/* Failed immutable resources are retryable, but not on every draw in a frame.
   The delay saturates; no failure count permanently disables recovery. */
static inline double hv_pvg_retry_delay(uint32_t failures) {
    unsigned shift = failures > 1 ? failures - 1 : 0;
    if (shift > 7) shift = 7;
    double delay = 0.05 * (1u << shift);
    return delay > 4.0 ? 4.0 : delay;
}
#endif

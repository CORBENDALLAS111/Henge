#include "pvg_retry.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    assert(fabs(hv_pvg_retry_delay(1)-0.05)<1e-9);
    assert(fabs(hv_pvg_retry_delay(2)-0.1)<1e-9);
    double last=0;
    for(unsigned i=0;i<10000;i++) {
        double delay=hv_pvg_retry_delay(i);
        assert(isfinite(delay) && delay>=0.05 && delay<=4.0 && delay>=last);
        last=delay;
    }
    assert(hv_pvg_retry_delay(UINT32_MAX)==4.0);
    puts("PASS: failed GPU resource retry delay is finite, bounded and never disables retries");
}

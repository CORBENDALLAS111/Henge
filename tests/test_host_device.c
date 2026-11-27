#include "host_device.h"
#include <assert.h>
#include <limits.h>

static HvHostDeviceStatus sample(void) {
    return (HvHostDeviceStatus){.battery=57,.power=2,.thermal=1,.host_kind=1,
        .audio_route=16,.peripherals=3,.system_volume=.8,.brightness=.4,.vm_gain=1};
}
static void parser(void) {
    uint64_t s,r; int f; double v;
    const char *bad[]={"", "1 0 1", "1 0 1 .2 extra", "-1 0 1 .2", "0 0 1 .2", "1 2 1 .2",
        "1 -1 1 .2", "1 0 0 .2", "1 0 -1 .2", "1 0 1 nan", "1 0 1 inf", "1 0 1 1.1",
        "1 0 1 -.01", "18446744073709551616 0 1 .2", "1 0 18446744073709551616 .2"};
    for(size_t i=0;i<sizeof bad/sizeof *bad;i++) assert(!hv_device_command_parse(bad[i],strlen(bad[i]),&s,&f,&r,&v));
    char nul[]="1 0 1 .2\0secret",longer[128]; memset(longer,'1',sizeof longer);
    assert(!hv_device_command_parse(nul,sizeof nul-1,&s,&f,&r,&v));
    assert(!hv_device_command_parse(longer,sizeof longer,&s,&f,&r,&v));
    const char *good="18446744073709551615 1 18446744073709551615 0\n";
    assert(hv_device_command_parse(good,strlen(good),&s,&f,&r,&v));
    assert(s==UINT64_MAX && r==UINT64_MAX && f==1 && v==0);
}
int main(void) {
    parser(); HvHostDevice d={0}; HvHostDeviceStatus s=sample(); char json[1400];
    int field=-1; uint64_t revision=0; double value=0;
    assert(!hv_device_json(&d,json,sizeof json,10));
    assert(hv_device_request(&d,1,0,1,.5,10)==403);
    hv_device_begin(&d,41,1);
    assert(hv_device_request(&d,41,0,1,.5,10)==503);
    assert(hv_device_publish(&d,41,s,10));
    assert(!hv_device_publish(&d,42,s,10));
    s.battery=-1; assert(hv_device_publish(&d,41,s,10));
    s.battery=101; assert(!hv_device_publish(&d,41,s,10)); s=sample();
    s.brightness=NAN; assert(!hv_device_publish(&d,41,s,10)); s=sample();
    assert(hv_device_json(&d,json,sizeof json,10) && strstr(json,"\"battery\":-1") && strstr(json,"\"session\":\"41\""));
    assert(!hv_device_json(&d,json,8,10));
    assert(!hv_device_json(&d,json,sizeof json,14));
    assert(hv_device_request(&d,41,0,1,.5,14)==503);
    assert(hv_device_publish(&d,41,s,14)); // Expiry invalidates the old revisions.
    assert(hv_device_request(&d,41,0,1,.5,14)==409);
    assert(hv_device_request(&d,42,0,2,.5,14)==409);
    assert(hv_device_request(&d,41,0,2,NAN,14)==400);
    assert(hv_device_request(&d,41,0,2,.5,14)==202);
    assert(hv_device_request(&d,41,0,2,.8,14)==409); // Duplicate/retry.
    assert(hv_device_request(&d,41,0,3,.6,14)==202); // Coalesce, no intermediate apply.
    assert(hv_device_request(&d,41,1,2,0,14)==202); // Independent brightness channel.
    assert(hv_device_take(&d,41,&field,&revision,&value,14) && field==0 && revision==4 && value==.6);
    assert(hv_device_request(&d,41,0,4,.7,14)==202); // Arrives while the old value is being applied.
    assert(hv_device_ack(&d,41,0,4,.6));
    assert(d.pending[0].valid && d.pending[0].revision==5 && d.status.vm_gain==.6);
    assert(hv_device_take(&d,41,&field,&revision,&value,14) && field==0 && revision==5 && value==.7);
    assert(!hv_device_ack(&d,41,0,4,.6));
    assert(hv_device_ack(&d,41,0,5,.7));
    assert(hv_device_take(&d,41,&field,&revision,&value,14) && field==1 && value==0);
    assert(hv_device_ack(&d,41,1,revision,0));
    assert(!hv_device_take(&d,41,&field,&revision,&value,14));
    assert(hv_device_json(&d,json,sizeof json,14) && strstr(json,"\"vm_gain\":0.700000") && strstr(json,"\"pending\":0"));

    // A local change cancels even a command already taken by the host.
    assert(hv_device_request(&d,41,0,d.revision[0],.2,14)==202);
    assert(hv_device_take(&d,41,&field,&revision,&value,14));
    s=d.status; s.vm_gain=.9; assert(hv_device_publish(&d,41,s,15));
    assert(!hv_device_ack(&d,41,0,revision,.2) && !d.pending[0].valid);
    assert(hv_device_request(&d,41,0,d.revision[0],.1,15)==202);
    assert(!hv_device_take(&d,41,&field,&revision,&value,19));
    assert(hv_device_publish(&d,41,s,19)); // A stalled loop must never revive the old request.
    assert(!hv_device_take(&d,41,&field,&revision,&value,19));
    assert(!hv_device_publish(&d,41,s,18));
    hv_device_begin(&d,42,0); hv_device_stop(&d,41); // Old task cannot stop a replacement.
    assert(d.enabled && d.session==42 && !hv_device_publish(&d,41,s,20));
    assert(hv_device_publish(&d,42,s,20));
    assert(hv_device_request(&d,42,0,1,.2,20)==403);
    hv_device_stop(&d,42); assert(!d.enabled && !hv_device_json(&d,json,sizeof json,20));
    puts("PASS: host status, strict commands, CAS/coalescing, independent controls, expiry and session ownership");
}

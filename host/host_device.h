#ifndef HENGE_HOST_DEVICE_H
#define HENGE_HOST_DEVICE_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>

enum { HV_DEVICE_GAIN=0, HV_DEVICE_BRIGHTNESS=1, HV_DEVICE_CONTROL_COUNT=2 };
#define HV_DEVICE_FRESH 4.0
typedef struct {
    int32_t battery, power, low_power, thermal, external_display, host_kind;
    uint32_t audio_route, peripherals;
    double system_volume, brightness, vm_gain;
} HvHostDeviceStatus;
typedef struct { uint64_t revision; double value; int valid,taken; } HvDevicePending;
typedef struct {
    int enabled,controls,has_status;
    uint64_t session,revision[HV_DEVICE_CONTROL_COUNT];
    uint64_t inflight[HV_DEVICE_CONTROL_COUNT];
    double seen;
    HvHostDeviceStatus status;
    HvDevicePending pending[HV_DEVICE_CONTROL_COUNT];
} HvHostDevice;
static inline int hv_device_level(double v,int unknown) { return isfinite(v) && ((unknown && v==-1) || (v>=0 && v<=1)); }
static inline int hv_device_status_valid(HvHostDeviceStatus s) {
    return s.battery>=-1 && s.battery<=100 && s.power>=0 && s.power<=3 &&
        (s.low_power==0 || s.low_power==1) && s.thermal>=0 && s.thermal<=3 &&
        (s.external_display==0 || s.external_display==1) && s.host_kind>=0 && s.host_kind<=2 &&
        s.audio_route<=255 && s.peripherals<=7 && hv_device_level(s.system_volume,1) &&
        hv_device_level(s.brightness,1) && hv_device_level(s.vm_gain,0);
}
static inline double hv_device_value(const HvHostDevice *d,int field) { return field==HV_DEVICE_GAIN ? d->status.vm_gain : d->status.brightness; }
static inline int hv_device_fresh(const HvHostDevice *d,double now) {
    return d->enabled && d->has_status && isfinite(now) && now>=d->seen && now-d->seen<HV_DEVICE_FRESH;
}
static inline void hv_device_begin(HvHostDevice *d,uint64_t session,int controls) {
    memset(d,0,sizeof *d); d->session=session; d->enabled=session!=0; d->controls=!!controls;
    d->revision[0]=d->revision[1]=1;
}
static inline void hv_device_stop(HvHostDevice *d,uint64_t session) {
    if(d->session==session) hv_device_begin(d,0,0);
}
static inline int hv_device_publish(HvHostDevice *d,uint64_t session,HvHostDeviceStatus status,double now) {
    if(!d->enabled || !session || session!=d->session || !hv_device_status_valid(status) || !isfinite(now)) return 0;
    if(d->has_status && now<d->seen) return 0;
    // A foreground stall must not revive commands accepted before expiry.
    if(d->has_status && !hv_device_fresh(d,now)) for(int f=0;f<HV_DEVICE_CONTROL_COUNT;f++) {
        ++d->revision[f]; d->pending[f]=(HvDevicePending){0}; d->inflight[f]=0;
    }
    if(d->has_status) for(int f=0;f<HV_DEVICE_CONTROL_COUNT;f++) {
        double old=hv_device_value(d,f),next=f==HV_DEVICE_GAIN?status.vm_gain:status.brightness;
        if(fabs(old-next)>0.000001) { ++d->revision[f]; d->pending[f]=(HvDevicePending){0}; d->inflight[f]=0; }
    }
    d->status=status; d->seen=now; d->has_status=1; return 1;
}
/* Compare-and-set revisions prevent retries and queued guest commands from
   overwriting a newer host adjustment. Only the latest command per field lives. */
static inline int hv_device_request(HvHostDevice *d,uint64_t session,int field,uint64_t revision,double value,double now) {
    if(!d->enabled || !d->controls) return 403;
    if(!hv_device_fresh(d,now)) return 503;
    if(!session || session!=d->session || field<0 || field>=HV_DEVICE_CONTROL_COUNT) return 409;
    if(!hv_device_level(value,0)) return 400;
    if(hv_device_value(d,field)<0) return 403;
    if(revision!=d->revision[field]) return 409;
    uint64_t next=++d->revision[field];
    d->pending[field]=(HvDevicePending){next,value,1,0}; return 202;
}
static inline int hv_device_take(HvHostDevice *d,uint64_t session,int *field,uint64_t *revision,double *value,double now) {
    if(!session || d->session!=session || !d->controls || !hv_device_fresh(d,now)) return 0;
    for(int f=0;f<HV_DEVICE_CONTROL_COUNT;f++) if(d->pending[f].valid && !d->pending[f].taken && !d->inflight[f]) {
        d->pending[f].taken=1; d->inflight[f]=d->pending[f].revision;
        *field=f; *revision=d->pending[f].revision; *value=d->pending[f].value; return 1;
    }
    return 0;
}
static inline int hv_device_ack(HvHostDevice *d,uint64_t session,int field,uint64_t revision,double actual) {
    if(!d->enabled || session!=d->session || field<0 || field>=HV_DEVICE_CONTROL_COUNT || !hv_device_level(actual,1)) return 0;
    HvDevicePending *p=&d->pending[field];
    if(d->inflight[field]!=revision || !p->valid || revision>d->revision[field]) return 0;
    d->inflight[field]=0;
    if(field==HV_DEVICE_GAIN) d->status.vm_gain=actual<0?d->status.vm_gain:actual;
    else d->status.brightness=actual;
    if(p->revision==revision) *p=(HvDevicePending){0};
    return 1;
}
static inline int hv_device_command_parse(const char *p,size_t n,uint64_t *session,int *field,uint64_t *revision,double *value) {
    if(!p || !n || n>=128) return 0;
    char text[128],*tokens[4],*cursor=text;
    for(size_t i=0;i<n;i++) { if(!p[i]) return 0; text[i]=p[i]; } text[n]=0;
    for(int i=0;i<4;i++) {
        while(isspace((unsigned char)*cursor)) cursor++;
        if(!*cursor) return 0; tokens[i]=cursor;
        while(*cursor && !isspace((unsigned char)*cursor)) cursor++;
        if(*cursor) *cursor++=0;
    }
    while(isspace((unsigned char)*cursor)) cursor++;
    if(*cursor || !isdigit((unsigned char)tokens[0][0]) || !isdigit((unsigned char)tokens[2][0])) return 0;
    char *end; errno=0; unsigned long long s=strtoull(tokens[0],&end,10); if(errno || *end || !s) return 0;
    errno=0; long f=strtol(tokens[1],&end,10); if(errno || *end || f<0 || f>=HV_DEVICE_CONTROL_COUNT) return 0;
    errno=0; unsigned long long r=strtoull(tokens[2],&end,10); if(errno || *end || !r) return 0;
    errno=0; double v=strtod(tokens[3],&end); if(errno || *end || !hv_device_level(v,0)) return 0;
    *session=s; *field=(int)f; *revision=r; *value=v; return 1;
}
static inline int hv_device_json(const HvHostDevice *d,char *text,size_t capacity,double now) {
    if(!hv_device_fresh(d,now)) return 0;
    const HvHostDeviceStatus *s=&d->status;
    unsigned pending=(d->pending[0].valid?1:0)|(d->pending[1].valid?2:0);
    double gain=d->pending[0].valid?d->pending[0].value:s->vm_gain;
    double bright=d->pending[1].valid?d->pending[1].value:s->brightness;
    int n=snprintf(text,capacity,"{\"version\":1,\"session\":\"%llu\",\"battery\":%d,\"power\":%d,\"low_power\":%d,\"thermal\":%d,\"host_kind\":%d,\"external_display\":%d,\"audio_route\":%u,\"peripherals\":%u,\"system_volume\":%.6f,\"brightness\":%.6f,\"vm_gain\":%.6f,\"controls\":%d,\"gain_revision\":\"%llu\",\"brightness_revision\":\"%llu\",\"pending\":%u,\"gain_target\":%.6f,\"brightness_target\":%.6f}",
        (unsigned long long)d->session,s->battery,s->power,s->low_power,s->thermal,s->host_kind,s->external_display,s->audio_route,s->peripherals,
        s->system_volume,s->brightness,s->vm_gain,d->controls,(unsigned long long)d->revision[0],(unsigned long long)d->revision[1],pending,gain,bright);
    return n>0 && (size_t)n<capacity ? n : 0;
}
#endif

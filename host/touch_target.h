#ifndef HENGE_TOUCH_TARGET_H
#define HENGE_TOUCH_TARGET_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <errno.h>
#include <ctype.h>

enum { HV_TARGET_UNAVAILABLE=-2, HV_TARGET_PERMISSION=-1, HV_TARGET_UNKNOWN=0,
       HV_TARGET_DRAG=1, HV_TARGET_SCROLL=2 };
#define HV_TARGET_TIMEOUT 0.120

/* A single active finger, not a screen-content cache. Call under the share lock. */
typedef struct {
    uint64_t sequence, active;
    double x, y, requested;
    int enabled, ready, hint;
} HvTouchTarget;
static inline void hv_target_enable(HvTouchTarget *t, int enabled) {
    if (t->enabled != !!enabled) t->active=0;
    t->enabled=!!enabled;
}
static inline uint64_t hv_target_request(HvTouchTarget *t,double x,double y,double now) {
    t->active=0;
    if (!t->enabled || !isfinite(now) || !isfinite(x) || !isfinite(y) || x<0 || x>1 || y<0 || y>1) return 0;
    if (!++t->sequence) ++t->sequence;
    t->active=t->sequence; t->x=x; t->y=y; t->requested=now; t->ready=0;
    return t->active;
}
static inline int hv_target_answer(HvTouchTarget *t,uint64_t id,int hint,double now) {
    if (!t->enabled || !isfinite(now) || !id || id!=t->active || t->ready ||
        hint<HV_TARGET_PERMISSION || hint>HV_TARGET_SCROLL ||
        now<t->requested || now-t->requested>HV_TARGET_TIMEOUT) return 0;
    t->hint=hint; t->ready=1; return 1;
}
static inline int hv_target_result(const HvTouchTarget *t,uint64_t id,double now) {
    if (!t->enabled || !isfinite(now) || !id || id!=t->active || !t->ready || now<t->requested ||
        now-t->requested>HV_TARGET_TIMEOUT) return HV_TARGET_UNAVAILABLE;
    return t->hint;
}
static inline int hv_target_parse_answer(const char *p,size_t n,uint64_t *id,int *hint) {
    if (!p || n==0 || n>=80) return 0;
    char text[80],*end; unsigned long long value;
    for(size_t i=0;i<n;i++) { if(!p[i]) return 0; text[i]=p[i]; }
    text[n]=0;
    if(!isdigit((unsigned char)text[0])) return 0;
    errno=0; value=strtoull(text,&end,10);
    if(errno || !value || !isspace((unsigned char)*end)) return 0;
    while(isspace((unsigned char)*end)) end++;
    char *tail; errno=0; long h=strtol(end,&tail,10);
    if(errno || tail==end || h<HV_TARGET_PERMISSION || h>HV_TARGET_SCROLL) return 0;
    while(isspace((unsigned char)*tail)) tail++;
    if(*tail) return 0;
    *hint=(int)h;
    *id=(uint64_t)value; return 1;
}
#endif

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
enum { HV_OBJECT_UNKNOWN=0, HV_OBJECT_WINDOW=1, HV_OBJECT_RESIZE=2, HV_OBJECT_SCROLL=3,
       HV_OBJECT_SLIDER=4, HV_OBJECT_SCROLLBAR=5, HV_OBJECT_SPLITTER=6,
       HV_OBJECT_TEXT_FIELD=7, HV_OBJECT_TEXT_AREA=8, HV_OBJECT_BUTTON=9,
       HV_OBJECT_TOGGLE=10, HV_OBJECT_LINK=11, HV_OBJECT_ITEM=12, HV_OBJECT_TEXT=13 };
enum { HV_OBJECT_DRAG=1, HV_OBJECT_SCROLLABLE=2, HV_OBJECT_EDITABLE=4,
       HV_OBJECT_SELECTABLE=8, HV_OBJECT_PRESS=16, HV_OBJECT_DISABLED=32,
       HV_OBJECT_HORIZONTAL=64, HV_OBJECT_VERTICAL=128, HV_OBJECT_EDITABILITY_KNOWN=256 };
typedef struct { int kind; uint32_t capabilities; double x,y,width,height; } HvTouchObject;
static inline int hv_target_object_valid(HvTouchObject o) {
    if(o.kind<0 || o.kind>HV_OBJECT_TEXT || o.capabilities>511 ||
       !isfinite(o.x) || !isfinite(o.y) || !isfinite(o.width) || !isfinite(o.height) ||
       o.x<0 || o.y<0 || o.width<0 || o.height<0 || o.x+o.width>1.000000001 || o.y+o.height>1.000000001) return 0;
    uint32_t c=o.capabilities;
    if((c & (HV_OBJECT_EDITABLE|HV_OBJECT_EDITABILITY_KNOWN)) && o.kind!=HV_OBJECT_TEXT_FIELD && o.kind!=HV_OBJECT_TEXT_AREA) return 0;
    if((c & HV_OBJECT_EDITABLE) && !(c & HV_OBJECT_EDITABILITY_KNOWN)) return 0;
    if((c & HV_OBJECT_DISABLED) && (c & (HV_OBJECT_DRAG|HV_OBJECT_EDITABLE|HV_OBJECT_PRESS))) return 0;
    if((c & (HV_OBJECT_HORIZONTAL|HV_OBJECT_VERTICAL))==(HV_OBJECT_HORIZONTAL|HV_OBJECT_VERTICAL)) return 0;
    if((c & (HV_OBJECT_HORIZONTAL|HV_OBJECT_VERTICAL)) && o.kind!=HV_OBJECT_SLIDER && o.kind!=HV_OBJECT_SCROLLBAR && o.kind!=HV_OBJECT_SPLITTER) return 0;
    return 1;
}

/* A single active finger, not a screen-content cache. Call under the share lock. */
typedef struct {
    uint64_t sequence, active;
    double x, y, requested;
    int enabled, ready, hint;
    HvTouchObject object;
} HvTouchTarget;
static inline void hv_target_enable(HvTouchTarget *t, int enabled) {
    if (t->enabled != !!enabled) t->active=0;
    t->enabled=!!enabled;
}
static inline uint64_t hv_target_request(HvTouchTarget *t,double x,double y,double now) {
    t->active=0;
    if (!t->enabled || !isfinite(now) || !isfinite(x) || !isfinite(y) || x<0 || x>1 || y<0 || y>1) return 0;
    if (!++t->sequence) ++t->sequence;
    t->active=t->sequence; t->x=x; t->y=y; t->requested=now; t->ready=0; t->object=(HvTouchObject){0};
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
static inline int hv_target_answer_object(HvTouchTarget *t,uint64_t id,int hint,HvTouchObject object,double now) {
    if(!hv_target_object_valid(object) || !hv_target_answer(t,id,hint,now)) return 0;
    t->object=object; return 1;
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
/* V2 uses a separate endpoint; V1 remains the exact two-integer protocol. */
static inline int hv_target_parse_object(const char *p,size_t n,uint64_t *id,int *hint,HvTouchObject *object) {
    if(!p || !n || n>=240) return 0;
    char text[240],*fields[8],*cursor=text;
    for(size_t i=0;i<n;i++) { if(!p[i]) return 0; text[i]=p[i]; } text[n]=0;
    for(int i=0;i<8;i++) {
        while(isspace((unsigned char)*cursor)) cursor++;
        if(!*cursor) return 0;
        fields[i]=cursor;
        while(*cursor && !isspace((unsigned char)*cursor)) cursor++;
        if(*cursor) *cursor++=0;
    }
    while(isspace((unsigned char)*cursor)) cursor++;
    if(*cursor || !isdigit((unsigned char)fields[0][0])) return 0;
    char *end; errno=0; unsigned long long sequence=strtoull(fields[0],&end,10);
    if(errno || *end || !sequence) return 0;
    long values[3];
    for(int i=0;i<3;i++) { errno=0; values[i]=strtol(fields[i+1],&end,10); if(errno || *end || end==fields[i+1]) return 0; }
    if(values[0]<HV_TARGET_PERMISSION || values[0]>HV_TARGET_SCROLL || values[1]<0 || values[1]>HV_OBJECT_TEXT || values[2]<0 || values[2]>511) return 0;
    double geometry[4];
    for(int i=0;i<4;i++) { errno=0; geometry[i]=strtod(fields[i+4],&end); if(errno || *end || end==fields[i+4]) return 0; }
    HvTouchObject parsed={(int)values[1],(uint32_t)values[2],geometry[0],geometry[1],geometry[2],geometry[3]};
    if(!hv_target_object_valid(parsed)) return 0;
    *id=(uint64_t)sequence; *hint=(int)values[0]; *object=parsed; return 1;
}
#endif

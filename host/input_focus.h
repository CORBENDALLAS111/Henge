/* Metadata-only guest focus reports. Never carries text, labels or values. */
#ifndef HENGE_INPUT_FOCUS_H
#define HENGE_INPUT_FOCUS_H
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
typedef struct { int editable; double x,y,width,height; } HvInputFocus;
static inline int hv_input_focus_parse(const char *text, size_t length, HvInputFocus *out) {
    if (!text || !out || !length || length>=160 || memchr(text,0,length)) return 0;
    char copy[160], tail; HvInputFocus f;
    memcpy(copy,text,length); copy[length]=0;
    if (sscanf(copy,"%d %lf %lf %lf %lf %c",&f.editable,&f.x,&f.y,&f.width,&f.height,&tail)!=5 ||
        f.editable < -1 || f.editable > 1 || !isfinite(f.x) || !isfinite(f.y) ||
        !isfinite(f.width) || !isfinite(f.height) || f.x<0 || f.y<0 ||
        f.width<0 || f.height<0 || f.x+f.width>1.000001 || f.y+f.height>1.000001) return 0;
    *out=f; return 1;
}
#endif

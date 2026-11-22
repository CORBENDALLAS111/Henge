#ifndef HENGE_TOUCH_TARGET_POLICY_H
#define HENGE_TOUCH_TARGET_POLICY_H
#include "../host/touch_target.h"
#include <string.h>

/* Only role identifiers and boolean geometry/capability facts. No UI strings. */
static inline int hv_touch_role_hint(const char *const *roles,size_t count,
                                     int title,int resize_edge,int selectable_text) {
    if (!count || !roles[0]) return HV_TARGET_UNKNOWN;
    for(size_t i=0;i<count;i++) {
        const char *r=roles[i]; if(!r) continue;
        if(!strcmp(r,"AXSlider") || !strcmp(r,"AXScrollBar") || !strcmp(r,"AXSplitter") ||
           !strcmp(r,"AXGrowArea") || !strcmp(r,"AXHandle") || !strcmp(r,"AXDockItem")) return HV_TARGET_DRAG;
    }
    if(title || resize_edge || !strcmp(roles[0],"AXToolbar")) return HV_TARGET_DRAG;
    for(size_t i=0;i<count;i++) {
        if(roles[i] && (!strcmp(roles[i],"AXScrollArea") || !strcmp(roles[i],"AXWebArea"))) return HV_TARGET_SCROLL;
    }
    /* An editor inside a scroll area scrolls normally; tap-then-drag explicitly
       selects text there. Plain selectable text outside one can drag directly. */
    if(selectable_text) return HV_TARGET_DRAG;
    return HV_TARGET_UNKNOWN;
}
#endif

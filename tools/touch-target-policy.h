#ifndef HENGE_TOUCH_TARGET_POLICY_H
#define HENGE_TOUCH_TARGET_POLICY_H
#include "../host/touch_target.h"
#include <string.h>

/* Prefer an enclosing concrete control to its static-text/image children.
   Container roles are considered only if there is no more specific object. */
static inline int hv_touch_object_kind(const char *role) {
    if(!role) return HV_OBJECT_UNKNOWN;
    if(!strcmp(role,"AXSlider")) return HV_OBJECT_SLIDER;
    if(!strcmp(role,"AXScrollBar")) return HV_OBJECT_SCROLLBAR;
    if(!strcmp(role,"AXSplitter")) return HV_OBJECT_SPLITTER;
    if(!strcmp(role,"AXGrowArea") || !strcmp(role,"AXHandle")) return HV_OBJECT_RESIZE;
    if(!strcmp(role,"AXTextField") || !strcmp(role,"AXComboBox") || !strcmp(role,"AXSearchField")) return HV_OBJECT_TEXT_FIELD;
    if(!strcmp(role,"AXTextArea")) return HV_OBJECT_TEXT_AREA;
    if(!strcmp(role,"AXButton") || !strcmp(role,"AXPopUpButton") || !strcmp(role,"AXMenuButton")) return HV_OBJECT_BUTTON;
    if(!strcmp(role,"AXCheckBox") || !strcmp(role,"AXRadioButton") || !strcmp(role,"AXSwitch")) return HV_OBJECT_TOGGLE;
    if(!strcmp(role,"AXLink")) return HV_OBJECT_LINK;
    if(!strcmp(role,"AXDockItem") || !strcmp(role,"AXRow") || !strcmp(role,"AXCell")) return HV_OBJECT_ITEM;
    return HV_OBJECT_UNKNOWN;
}
static inline HvTouchObject hv_touch_object_policy(const char *const *roles,size_t count,
                int title,int resize_edge,int selectable,int editable,int enabled,int press,int orientation) {
    HvTouchObject o={0};
    if(!roles) count=0;
    for(size_t i=0;i<count;i++) { o.kind=hv_touch_object_kind(roles[i]); if(o.kind) break; }
    int scroll=0;
    for(size_t i=0;i<count;i++) if(roles[i] && (!strcmp(roles[i],"AXScrollArea") || !strcmp(roles[i],"AXWebArea"))) scroll=1;
    if(!o.kind && resize_edge) o.kind=HV_OBJECT_RESIZE;
    if(!o.kind && (title || (count && roles[0] && !strcmp(roles[0],"AXToolbar")))) o.kind=HV_OBJECT_WINDOW;
    if(!o.kind && scroll) o.kind=HV_OBJECT_SCROLL;
    if(!o.kind && selectable) o.kind=HV_OBJECT_TEXT;
    if(scroll) o.capabilities|=HV_OBJECT_SCROLLABLE;
    if(selectable) o.capabilities|=HV_OBJECT_SELECTABLE;
    if(!enabled) { o.capabilities|=HV_OBJECT_DISABLED; return o; }
    if(press) o.capabilities|=HV_OBJECT_PRESS;
    if(editable>=0 && (o.kind==HV_OBJECT_TEXT_FIELD || o.kind==HV_OBJECT_TEXT_AREA)) {
        o.capabilities|=HV_OBJECT_EDITABILITY_KNOWN;
        if(editable) o.capabilities|=HV_OBJECT_EDITABLE;
    }
    if(o.kind==HV_OBJECT_SLIDER || o.kind==HV_OBJECT_SCROLLBAR || o.kind==HV_OBJECT_SPLITTER ||
       o.kind==HV_OBJECT_RESIZE || o.kind==HV_OBJECT_WINDOW) o.capabilities|=HV_OBJECT_DRAG;
    if(o.kind==HV_OBJECT_SLIDER || o.kind==HV_OBJECT_SCROLLBAR || o.kind==HV_OBJECT_SPLITTER) {
        if(orientation==1) o.capabilities|=HV_OBJECT_HORIZONTAL;
        if(orientation==2) o.capabilities|=HV_OBJECT_VERTICAL;
    }
    return o;
}

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

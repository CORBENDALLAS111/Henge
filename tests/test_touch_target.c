#include "../host/touch_target.h"
#include "../tools/touch-target-policy.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>

int main(void) {
    HvTouchTarget t={0};
    assert(!hv_target_request(&t,.2,.3,10));
    hv_target_enable(&t,1);
    uint64_t a=hv_target_request(&t,.2,.3,10);
    assert(a && hv_target_result(&t,a,10)==HV_TARGET_UNAVAILABLE);
    assert(hv_target_answer(&t,a,HV_TARGET_DRAG,10.03));
    assert(!hv_target_answer(&t,a,HV_TARGET_SCROLL,10.04));
    assert(hv_target_result(&t,a,10.04)==HV_TARGET_DRAG);
    assert(hv_target_result(&t,a,10.13)==HV_TARGET_UNAVAILABLE);
    uint64_t b=hv_target_request(&t,.8,.9,11);
    assert(b>a && !hv_target_answer(&t,a,HV_TARGET_DRAG,11.01));
    assert(!hv_target_answer(&t,b,HV_TARGET_SCROLL,11.13));
    assert(!hv_target_answer(&t,b,3,11.01));
    assert(!hv_target_answer(&t,b,HV_TARGET_SCROLL,NAN));
    assert(hv_target_answer(&t,b,HV_TARGET_PERMISSION,11.05));
    hv_target_enable(&t,0); hv_target_enable(&t,1);
    assert(hv_target_result(&t,b,11.06)==HV_TARGET_UNAVAILABLE);
    assert(!hv_target_request(&t,NAN,.2,12));
    assert(!hv_target_request(&t,.2,1.01,12));
    assert(!hv_target_request(&t,.2,.2,NAN));
    uint64_t id; int hint;
    const char *bad[]={"", "-1 1", "0 1", "1 3", "1 -2", "1 nan", "1 1 title=private", "1", "1-1", "18446744073709551616 1"};
    for(size_t i=0;i<sizeof bad/sizeof *bad;i++) assert(!hv_target_parse_answer(bad[i],strlen(bad[i]),&id,&hint));
    assert(hv_target_parse_answer("42 -1\n",6,&id,&hint) && id==42 && hint==-1);
    assert(!hv_target_parse_answer("42 1\0x",6,&id,&hint));

    const char *slider[]={"AXSlider","AXScrollArea","AXWindow"};
    const char *document[]={"AXStaticText","AXWebArea","AXScrollArea","AXWindow"};
    const char *editor[]={"AXTextArea","AXScrollArea","AXWindow"};
    const char *text[]={"AXTextField","AXWindow"};
    const char *button[]={"AXButton","AXToolbar","AXWindow"};
    const char *toolbar[]={"AXToolbar","AXWindow"};
    const char *window[]={"AXWindow"};
    assert(hv_touch_role_hint(slider,3,0,0,0)==HV_TARGET_DRAG);
    assert(hv_touch_role_hint(document,4,0,0,1)==HV_TARGET_SCROLL);
    assert(hv_touch_role_hint(editor,3,0,0,1)==HV_TARGET_SCROLL);
    assert(hv_touch_role_hint(text,2,0,0,1)==HV_TARGET_DRAG);
    assert(hv_touch_role_hint(button,3,0,0,0)==HV_TARGET_UNKNOWN);
    assert(hv_touch_role_hint(toolbar,2,0,0,0)==HV_TARGET_DRAG);
    assert(hv_touch_role_hint(window,1,0,1,0)==HV_TARGET_DRAG);
    assert(hv_touch_role_hint(window,1,1,0,0)==HV_TARGET_DRAG);
    assert(hv_touch_role_hint(window,1,0,0,0)==HV_TARGET_UNKNOWN);
    assert(hv_touch_role_hint(NULL,0,0,0,0)==HV_TARGET_UNKNOWN);
    HvTouchObject o;
    assert(hv_target_parse_object("42 2 7 270 .1 .2 .3 .4",strlen("42 2 7 270 .1 .2 .3 .4"),&id,&hint,&o));
    assert(id==42 && hint==2 && o.kind==HV_OBJECT_TEXT_FIELD && o.capabilities==270 && o.width==.3);
    const char *bad_objects[]={"42 1 4 65 0 0 1 1 extra", "42 1 14 0 0 0 0 0", "42 1 4 512 0 0 1 1",
        "42 1 9 260 0 0 1 1", "42 1 7 4 0 0 1 1", "42 1 4 193 0 0 1 1", "42 1 1 64 0 0 1 1",
        "42 1 4 33 0 0 1 1", "42 1 4 1 .9 0 .2 1", "42 1 4 1 nan 0 1 1", "42 1 4 1 0 0 -1 1",
        "42 1 4 1 0 0 inf 1", "18446744073709551616 1 4 1 0 0 1 1", "42 1 4 1 0 0 1"};
    for(size_t i=0;i<sizeof bad_objects/sizeof *bad_objects;i++) assert(!hv_target_parse_object(bad_objects[i],strlen(bad_objects[i]),&id,&hint,&o));
    o=hv_touch_object_policy(slider,3,0,0,0,-1,1,0,1);
    assert(o.kind==HV_OBJECT_SLIDER && (o.capabilities & HV_OBJECT_DRAG) && (o.capabilities & HV_OBJECT_SCROLLABLE) && (o.capabilities & HV_OBJECT_HORIZONTAL));
    assert(hv_target_object_valid(o));
    o=hv_touch_object_policy(button,3,0,0,0,-1,1,1,0);
    assert(o.kind==HV_OBJECT_BUTTON && o.capabilities==HV_OBJECT_PRESS);
    o=hv_touch_object_policy(text,2,0,0,1,0,1,0,0);
    assert(o.kind==HV_OBJECT_TEXT_FIELD && (o.capabilities & HV_OBJECT_EDITABILITY_KNOWN) && !(o.capabilities & HV_OBJECT_EDITABLE));
    o=hv_touch_object_policy(text,2,0,0,1,-1,1,0,0);
    assert(!(o.capabilities & HV_OBJECT_EDITABILITY_KNOWN));
    o=hv_touch_object_policy(slider,3,0,0,0,-1,0,1,1);
    assert((o.capabilities & HV_OBJECT_DISABLED) && !(o.capabilities & (HV_OBJECT_DRAG|HV_OBJECT_PRESS)) && hv_target_object_valid(o));
    hv_target_enable(&t,1); uint64_t detail=hv_target_request(&t,.3,.4,20);
    o=(HvTouchObject){HV_OBJECT_SLIDER,HV_OBJECT_DRAG|HV_OBJECT_HORIZONTAL,.1,.2,.3,.4};
    assert(hv_target_answer_object(&t,detail,HV_TARGET_DRAG,o,20.03));
    assert(t.object.kind==HV_OBJECT_SLIDER && t.object.x==.1);
    assert(!hv_target_answer_object(&t,detail,HV_TARGET_SCROLL,(HvTouchObject){0},20.04));
    hv_target_request(&t,.4,.4,21); assert(t.object.kind==0 && t.object.capabilities==0);
    puts("PASS: target mailbox identity/deadline/permission/reset, strict metadata parser and AX role precedence");
}

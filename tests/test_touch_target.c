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
    puts("PASS: target mailbox identity/deadline/permission/reset, strict metadata parser and AX role precedence");
}

// Exercise the real macOS HID-to-desktop path when the runner permits virtual HID.
// A denied entitlement/event tap is an explicit skip, not proof of desktop clicks.
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hid/IOHIDUserDevice.h>
#import <IOKit/hid/IOHIDKeys.h>
#include "absolute_pen.h"
#include <assert.h>
#include <math.h>

static int left_down, left_up, right_down, right_up;
static CGPoint target;
static int wrong_position;
static CGEventRef observe(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *ctx) {
    (void)proxy; (void)ctx;
    if (type==kCGEventLeftMouseDown) left_down++;
    if (type==kCGEventLeftMouseUp) left_up++;
    if (type==kCGEventRightMouseDown) right_down++;
    if (type==kCGEventRightMouseUp) right_up++;
    if (type==kCGEventLeftMouseDown || type==kCGEventLeftMouseUp || type==kCGEventRightMouseDown || type==kCGEventRightMouseUp) {
        CGPoint p=CGEventGetLocation(event);
        if (fabs(p.x-target.x)>2 || fabs(p.y-target.y)>2) wrong_position++;
    }
    return event;
}
static void pump(double seconds) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,seconds,false); }
static void mouse(IOHIDUserDeviceRef device, unsigned buttons) {
    uint8_t r[HV_PEN_REPORT_LEN]; hv_pen_mouse_report(r,buttons);
    assert(IOHIDUserDeviceHandleReport(device,r,HV_PEN_MOUSE_REPORT_LEN)==kIOReturnSuccess);
    pump(0.09);
}
int main(void) { @autoreleasepool {
    CFMachPortRef tap=CGEventTapCreate(kCGHIDEventTap,kCGHeadInsertEventTap,kCGEventTapOptionListenOnly,
        CGEventMaskBit(kCGEventLeftMouseDown)|CGEventMaskBit(kCGEventLeftMouseUp)|CGEventMaskBit(kCGEventRightMouseDown)|CGEventMaskBit(kCGEventRightMouseUp),observe,NULL);
    if(!tap) { puts("SKIP: runner does not allow a desktop HID event tap (real-device acceptance remains required)"); return 77; }
    NSDictionary *properties=@{
        @kIOHIDReportDescriptorKey:[NSData dataWithBytes:hv_pen_descriptor length:sizeof hv_pen_descriptor],
        @kIOHIDVendorIDKey:@0x1209, @kIOHIDProductIDKey:@0x7ffe,
        @kIOHIDProductKey:@"Henge desktop click regression", @kIOHIDTransportKey:@"USB"
    };
    IOHIDUserDeviceRef device=IOHIDUserDeviceCreate(kCFAllocatorDefault,(__bridge CFDictionaryRef)properties);
    if(!device) { CFRelease(tap); puts("SKIP: runner does not allow IOHIDUserDevice (transport tests still run)"); return 77; }
    CFRunLoopSourceRef source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);
    CGEventTapEnable(tap,true); pump(1.5);
    uint8_t r[HV_PEN_REPORT_LEN]; hv_pen_report(r,16384,16384,0,0,0,0,HV_PEN_RANGE);
    assert(IOHIDUserDeviceHandleReport(device,r,sizeof r)==kIOReturnSuccess); pump(0.3);
    CGEventRef current=CGEventCreate(NULL); target=CGEventGetLocation(current); CFRelease(current);
    left_down=left_up=right_down=right_up=wrong_position=0;
    // Exactly the same location for all samples, with no pointer motion to rescue a click.
    mouse(device,1); mouse(device,0); mouse(device,1); mouse(device,0);
    mouse(device,2); mouse(device,0); pump(0.3);
    fprintf(stderr,"desktop HID: left=%d/%d right=%d/%d wrong-position=%d\n",left_down,left_up,right_down,right_up,wrong_position);
    assert(left_down==2 && left_up==2 && right_down==1 && right_up==1 && !wrong_position);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);
    CFRelease(source); CFRelease(tap); CFRelease(device);
    puts("PASS: actual macOS HID driver emitted stationary desktop left-double and secondary click edges");
    return 0;
} }

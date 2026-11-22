// Exercise the real macOS HID-to-desktop path when the runner permits virtual HID.
// A denied entitlement/event tap is an explicit skip, not proof of desktop clicks.
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/IOReturn.h>
#include <dlfcn.h>
#import <IOKit/hid/IOHIDKeys.h>
#include "absolute_pen.h"
#include <assert.h>
#include <math.h>

// These two test-only SPI signatures are from Apple's IOKitUser
// hid.subproj/IOHIDUserDevice.h. Current public SDKs omit that header; resolve
// symbols at runtime and explicitly skip if the system does not provide them.
// The iOS app never links or calls this test API.
typedef CFTypeRef IOHIDUserDeviceRef;
static IOHIDUserDeviceRef (*createDevice)(CFAllocatorRef, CFDictionaryRef);
static IOReturn (*handleReport)(IOHIDUserDeviceRef, const uint8_t *, CFIndex);

static int left_down, left_up, right_down, right_up;
static CGPoint target;
static int wrong_position;
static int tablet_points, eraser_proximity;
static double max_pressure, max_tilt, max_rotation;
static CGEventRef observe(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *ctx) {
    (void)proxy; (void)ctx;
    if (type==kCGEventTabletProximity && CGEventGetIntegerValueField(event,kCGTabletProximityEventEnterProximity) &&
        CGEventGetIntegerValueField(event,kCGTabletProximityEventPointerType)==3) eraser_proximity++;
    double pressure=CGEventGetDoubleValueField(event,kCGTabletEventPointPressure);
    if (pressure>0) {
        tablet_points++;
        max_pressure=fmax(max_pressure,pressure);
        max_tilt=fmax(max_tilt,fabs(CGEventGetDoubleValueField(event,kCGTabletEventTiltX)));
        max_rotation=fmax(max_rotation,fabs(CGEventGetDoubleValueField(event,kCGTabletEventRotation)));
    }
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
    assert(handleReport(device,r,HV_PEN_MOUSE_REPORT_LEN)==kIOReturnSuccess);
    pump(0.09);
}
int main(void) { @autoreleasepool {
    createDevice=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceCreate");
    handleReport=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceHandleReport");
    if(!createDevice || !handleReport) { puts("SKIP: runner does not expose virtual HID test APIs"); return 77; }
    CFMachPortRef tap=CGEventTapCreate(kCGHIDEventTap,kCGHeadInsertEventTap,kCGEventTapOptionListenOnly,
        CGEventMaskBit(kCGEventLeftMouseDown)|CGEventMaskBit(kCGEventLeftMouseUp)|CGEventMaskBit(kCGEventRightMouseDown)|CGEventMaskBit(kCGEventRightMouseUp)|
        CGEventMaskBit(kCGEventLeftMouseDragged)|CGEventMaskBit(kCGEventTabletPointer)|CGEventMaskBit(kCGEventTabletProximity),observe,NULL);
    if(!tap) { puts("SKIP: runner does not allow a desktop HID event tap (real-device acceptance remains required)"); return 77; }
    NSDictionary *properties=@{
        @kIOHIDReportDescriptorKey:[NSData dataWithBytes:hv_pen_descriptor length:sizeof hv_pen_descriptor],
        @kIOHIDVendorIDKey:@0x1209, @kIOHIDProductIDKey:@0x7ffe,
        @kIOHIDProductKey:@"Henge desktop click regression", @kIOHIDTransportKey:@"USB"
    };
    IOHIDUserDeviceRef device=createDevice(kCFAllocatorDefault,(__bridge CFDictionaryRef)properties);
    if(!device) { CFRelease(tap); puts("SKIP: runner does not allow IOHIDUserDevice (transport tests still run)"); return 77; }
    CFRunLoopSourceRef source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);
    CGEventTapEnable(tap,true); pump(1.5);
    uint8_t r[HV_PEN_REPORT_LEN]; hv_pen_report(r,16384,16384,0,0,0,0,HV_PEN_RANGE);
    assert(handleReport(device,r,sizeof r)==kIOReturnSuccess); pump(0.3);
    CGEventRef current=CGEventCreate(NULL); target=CGEventGetLocation(current); CFRelease(current);
    left_down=left_up=right_down=right_up=wrong_position=0;
    // Exactly the same location for all samples, with no pointer motion to rescue a click.
    mouse(device,1); mouse(device,0); mouse(device,1); mouse(device,0);
    mouse(device,2); mouse(device,0); pump(0.3);
    fprintf(stderr,"desktop HID: left=%d/%d right=%d/%d wrong-position=%d\n",left_down,left_up,right_down,right_up,wrong_position);
    assert(left_down==2 && left_up==2 && right_down==1 && right_up==1 && !wrong_position);
    // Exercise the production descriptor through the host's real tablet driver.
    for(int i=0;i<4;i++) {
        hv_pen_report(r,16384+i*100,16384,1000+i*900,3000,-4500,9000,HV_PEN_RANGE|HV_PEN_TIP);
        assert(handleReport(device,r,sizeof r)==kIOReturnSuccess); pump(0.09);
    }
    hv_pen_report(r,16684,16384,0,0,0,0,HV_PEN_RANGE);
    assert(handleReport(device,r,sizeof r)==kIOReturnSuccess); pump(0.09);
    hv_pen_report(r,16684,16384,0,0,0,0,0);
    assert(handleReport(device,r,sizeof r)==kIOReturnSuccess); pump(0.09);
    hv_pen_report(r,16684,16384,0,0,0,0,HV_PEN_RANGE|HV_PEN_INVERT);
    assert(handleReport(device,r,sizeof r)==kIOReturnSuccess); pump(0.2);
    fprintf(stderr,"tablet HID: points=%d pressure=%g tilt=%g rotation=%g eraser=%d\n",tablet_points,max_pressure,max_tilt,max_rotation,eraser_proximity);
    assert(tablet_points && max_pressure>0 && max_tilt>0 && max_rotation>0 && eraser_proximity);
    hv_pen_report(r,16684,16384,0,0,0,0,0);
    assert(handleReport(device,r,sizeof r)==kIOReturnSuccess); pump(0.09);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),source,kCFRunLoopDefaultMode);
    CFRelease(source); CFRelease(tap); CFRelease(device);
    puts("PASS: actual macOS HID driver emitted stationary desktop left-double and secondary click edges");
    return 0;
} }

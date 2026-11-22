// Runs inside macOS on a Henge virtual Mac, as a LaunchAgent. It keeps the clipboard in step with the device,
// and keeps the shared folder mounted. It talks to host/share.c at 10.0.2.4, which only exists inside Henge.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include "touch-target-policy.h"
#include <arpa/inet.h>
#include <math.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <time.h>

#define HOST "10.0.2.4"

static int send_all(int fd, const void *p, size_t n) {
    const char *c = p;
    while (n) {
        ssize_t w = send(fd, c, n, 0);
        if (w <= 0) return -1;
        c += w, n -= (size_t)w;
    }
    return 0;
}

// One request on its own connection. A plain socket: the server is ours, and URLSession refuses plain HTTP.
static NSData *request(NSString *method, NSString *path, NSData *body, int *status, unsigned long *seq) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    struct timeval timeout = {.tv_sec = 40};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(80)};
    inet_pton(AF_INET, HOST, &addr.sin_addr);
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        close(fd);
        return nil;
    }
    NSString *head = [NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: " HOST "\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", method, path,
                                                (unsigned long)body.length];
    const char *text = head.UTF8String;
    if (send_all(fd, text, strlen(text)) != 0 || (body.length && send_all(fd, body.bytes, body.length) != 0)) {
        close(fd);
        return nil;
    }
    NSMutableData *all = [NSMutableData data];
    char piece[16384];
    for (;;) {
        ssize_t got = recv(fd, piece, sizeof piece, 0);
        if (got <= 0) break;
        [all appendBytes:piece length:(NSUInteger)got];
    }
    close(fd);
    NSRange end = [all rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0 range:NSMakeRange(0, all.length)];
    if (end.location == NSNotFound) return nil;
    NSString *headers = [[NSString alloc] initWithData:[all subdataWithRange:NSMakeRange(0, end.location)] encoding:NSUTF8StringEncoding];
    if (sscanf(headers.UTF8String, "HTTP/1.1 %d", status) != 1) return nil;
    NSRange found = [headers rangeOfString:@"X-Henge-Seq: "];
    if (found.location != NSNotFound && seq) *seq = strtoul(headers.UTF8String + NSMaxRange(found), NULL, 10);
    NSUInteger start = NSMaxRange(end);
    return [all subdataWithRange:NSMakeRange(start, all.length - start)];
}

static NSInteger lastChange;

// The device's clipboard, as it changes. The server holds each request until there is something new.
static void followDevice(void) {
    unsigned long seq = 0;
    for (BOOL first = YES;; first = NO) {
        int status = 0;
        unsigned long now = seq;
        NSData *body = request(@"GET", [NSString stringWithFormat:@"/.henge/clipboard?since=%lu", first ? ULONG_MAX >> 1 : seq], nil, &status, &now);
        if (!body) {
            sleep(5);
            continue;
        }
        BOOL news = !first && status == 200 && now != seq;
        seq = now; // what the device had before this helper started isn't news
        if (!news) continue;
        NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        if (!text) continue;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSPasteboard *board = NSPasteboard.generalPasteboard;
            [board clearContents];
            [board setString:text forType:NSPasteboardTypeString];
            lastChange = board.changeCount;
        });
    }
}

// The Mac's clipboard goes to the device, unless the app that copied it marked it as secret.
static void checkClipboard(void) {
    NSPasteboard *board = NSPasteboard.generalPasteboard;
    if (board.changeCount == lastChange) return;
    lastChange = board.changeCount;
    if ([board.types containsObject:@"org.nspasteboard.ConcealedType"]) return;
    NSString *text = [board stringForType:NSPasteboardTypeString];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        request(@"PUT", @"/.henge/clipboard", data, &status, NULL);
    });
}

static NSString *mountPoint(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Henge"]; }

// The shared folder, at ~/Henge. mount_webdav needs an empty folder it owns, and is a no-op failure if it is mounted.
static void keepMounted(void) {
    NSString *point = mountPoint();
    [NSFileManager.defaultManager createDirectoryAtPath:point withIntermediateDirectories:YES attributes:nil error:NULL];
    struct stat folder, parent;
    if (stat(point.fileSystemRepresentation, &folder) != 0 || stat(NSHomeDirectory().fileSystemRepresentation, &parent) != 0) return;
    if (folder.st_dev != parent.st_dev) return; // already something else's volume: mounted
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/sbin/mount_webdav"];
    task.arguments = @[ @"-S", @"-v", @"Henge", @"http://" HOST "/", point ];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    [task launchAndReturnError:NULL];
}

// Opt-in accessibility reads roles and geometry only, never field values.
static BOOL focusBusy, focusPrompted;
static NSString *focusReport(void) {
    if (!AXIsProcessTrusted()) {
        if(!focusPrompted) {
            focusPrompted=YES;
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
        }
        return @"-1 0 0 0 0";
    }
    AXUIElementRef system=AXUIElementCreateSystemWide(); CFTypeRef item=NULL;
    AXError error=AXUIElementCopyAttributeValue(system,kAXFocusedUIElementAttribute,&item);
    CFRelease(system);
    if(error!=kAXErrorSuccess || !item) return @"0 0 0 0 0";
    CFTypeRef role=NULL, position=NULL, size=NULL;
    AXUIElementCopyAttributeValue((AXUIElementRef)item,kAXRoleAttribute,&role);
    BOOL editable=role && [@[ @"AXTextField", @"AXTextArea", @"AXComboBox", @"AXSearchField" ] containsObject:(__bridge id)role];
    CGPoint p=CGPointZero; CGSize z=CGSizeZero;
    if(editable) {
        AXUIElementCopyAttributeValue((AXUIElementRef)item,kAXPositionAttribute,&position);
        AXUIElementCopyAttributeValue((AXUIElementRef)item,kAXSizeAttribute,&size);
        if(position && CFGetTypeID(position)==AXValueGetTypeID() && AXValueGetType((AXValueRef)position)==kAXValueCGPointType)
            AXValueGetValue((AXValueRef)position,kAXValueCGPointType,&p);
        if(size && CFGetTypeID(size)==AXValueGetTypeID() && AXValueGetType((AXValueRef)size)==kAXValueCGSizeType)
            AXValueGetValue((AXValueRef)size,kAXValueCGSizeType,&z);
    }
    if(role)CFRelease(role); if(position)CFRelease(position); if(size)CFRelease(size); CFRelease(item);
    NSRect screen=NSScreen.screens.firstObject.frame;
    double w=MAX(screen.size.width,1),h=MAX(screen.size.height,1);
    double x=fmin(fmax(p.x/w,0),1),y=fmin(fmax(p.y/h,0),1);
    double width=fmin(fmax(z.width/w,0),1-x),height=fmin(fmax(z.height/h,0),1-y);
    return [NSString stringWithFormat:@"%d %.6f %.6f %.6f %.6f",editable?1:0,x,y,width,height];
}
static void checkFocus(void) {
    if(focusBusy) return;
    focusBusy=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        int status=0;
        NSData *config=request(@"GET",@"/.henge/input-settings",nil,&status,NULL);
        NSString *text=config ? [[NSString alloc] initWithData:config encoding:NSUTF8StringEncoding] : nil;
        if(status!=200 || ![text hasPrefix:@"enabled=1"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ focusBusy=NO; focusPrompted=NO; });
            return;
        }
        __block NSString *report;
        dispatch_sync(dispatch_get_main_queue(), ^{ report=focusReport(); });
        request(@"PUT",@"/.henge/focus",[report dataUsingEncoding:NSUTF8StringEncoding],&status,NULL);
        dispatch_async(dispatch_get_main_queue(), ^{ focusBusy=NO; });
    });
}

static double targetTime(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9;
}
static BOOL targetRect(AXUIElementRef element,CGRect *rect) {
    CFTypeRef position=NULL,size=NULL; CGPoint p=CGPointZero; CGSize z=CGSizeZero;
    AXError a=AXUIElementCopyAttributeValue(element,kAXPositionAttribute,&position);
    AXError b=AXUIElementCopyAttributeValue(element,kAXSizeAttribute,&size);
    BOOL ok=a==kAXErrorSuccess && b==kAXErrorSuccess && position && size &&
        CFGetTypeID(position)==AXValueGetTypeID() && CFGetTypeID(size)==AXValueGetTypeID() &&
        AXValueGetType((AXValueRef)position)==kAXValueCGPointType &&
        AXValueGetType((AXValueRef)size)==kAXValueCGSizeType &&
        AXValueGetValue((AXValueRef)position,kAXValueCGPointType,&p) &&
        AXValueGetValue((AXValueRef)size,kAXValueCGSizeType,&z) &&
        isfinite(p.x) && isfinite(p.y) && isfinite(z.width) && isfinite(z.height) && z.width>0 && z.height>0;
    if(position) CFRelease(position); if(size) CFRelease(size);
    if(ok) *rect=CGRectMake(p.x,p.y,z.width,z.height);
    return ok;
}

/* The normalized framebuffer point maps to the guest's main display in AX's
   top-left logical coordinate space, including Retina "Looks like" scaling.
   No pointer movement, AX actions, text, titles or field values are requested. */
static int targetHint(double x,double y) {
    if(!AXIsProcessTrusted()) return HV_TARGET_PERMISSION;
    CGRect screen=CGDisplayBounds(CGMainDisplayID());
    if(CGRectIsEmpty(screen)) return HV_TARGET_UNKNOWN;
    CGPoint point=CGPointMake(screen.origin.x+x*screen.size.width,screen.origin.y+y*screen.size.height);
    double deadline=targetTime()+0.080;
    AXUIElementRef system=AXUIElementCreateSystemWide(),item=NULL;
    AXUIElementSetMessagingTimeout(system,0.025f);
    AXError error=AXUIElementCopyElementAtPosition(system,(float)point.x,(float)point.y,&item);
    CFRelease(system);
    if(error!=kAXErrorSuccess || !item) { if(item) CFRelease(item); return HV_TARGET_UNKNOWN; }
    NSMutableArray *elements=[NSMutableArray array],*roles=[NSMutableArray array];
    BOOL title=NO,edge=NO,selectable=NO,complete=NO;
    for(int depth=0;item && depth<8 && targetTime()<deadline;depth++) {
        AXUIElementSetMessagingTimeout(item,0.025f);
        [elements addObject:CFBridgingRelease(item)]; item=NULL;
        AXUIElementRef current=(__bridge AXUIElementRef)elements.lastObject;
        CFTypeRef raw=NULL;
        if(AXUIElementCopyAttributeValue(current,kAXRoleAttribute,&raw)!=kAXErrorSuccess || !raw) break;
        if(CFGetTypeID(raw)!=CFStringGetTypeID()) { CFRelease(raw); break; }
        NSString *role=CFBridgingRelease(raw); [roles addObject:role];
        const char *names[8]; for(NSUInteger i=0;i<roles.count;i++) names[i]=[roles[i] UTF8String];
        int direct=hv_touch_role_hint(names,roles.count,0,0,0);
        if(direct!=HV_TARGET_UNKNOWN) return targetTime()<=deadline ? direct : HV_TARGET_UNKNOWN;
        if([role isEqualToString:@"AXWindow"]) {
            CFTypeRef label=NULL;
            if(AXUIElementCopyAttributeValue(current,kAXTitleUIElementAttribute,&label)==kAXErrorSuccess && label) {
                for(id element in elements) if(CFEqual((__bridge CFTypeRef)element,label)) title=YES;
                CFRelease(label);
            }
            if([roles.firstObject isEqualToString:@"AXWindow"]) {
                CGRect frame; Boolean resizable=false;
                if(targetRect(current,&frame) && CGRectContainsPoint(frame,point) &&
                   AXUIElementIsAttributeSettable(current,kAXSizeAttribute,&resizable)==kAXErrorSuccess && resizable) {
                    edge=point.x-CGRectGetMinX(frame)<=5 || CGRectGetMaxX(frame)-point.x<=5 ||
                         point.y-CGRectGetMinY(frame)<=5 || CGRectGetMaxY(frame)-point.y<=5;
                }
            }
            complete=YES; break;
        }
        if(depth==0 && [@[ @"AXTextField",@"AXTextArea",@"AXStaticText" ] containsObject:role]) {
            CFArrayRef attributes=NULL;
            if(AXUIElementCopyAttributeNames(current,&attributes)==kAXErrorSuccess && attributes) {
                selectable=[(__bridge NSArray *)attributes containsObject:(__bridge NSString *)kAXSelectedTextRangeAttribute];
                CFRelease(attributes);
            }
        }
        CFTypeRef parent=NULL;
        if(AXUIElementCopyAttributeValue(current,kAXParentAttribute,&parent)!=kAXErrorSuccess || !parent) { complete=YES; break; }
        if(CFGetTypeID(parent)!=AXUIElementGetTypeID()) { CFRelease(parent); break; }
        item=(AXUIElementRef)parent;
    }
    if(item) CFRelease(item);
    if(!complete || targetTime()>deadline) return HV_TARGET_UNKNOWN;
    const char *names[8]; for(NSUInteger i=0;i<roles.count;i++) names[i]=[roles[i] UTF8String];
    return hv_touch_role_hint(names,roles.count,title,edge,selectable);
}

/* Event-driven long poll on a separate queue. Slow or unsupported AX providers
   never block the agent's clipboard, focus reporter, or the host's UI thread. */
static void followTouchTargets(void) {
    unsigned long long since=0; BOOL prompted=NO;
    for(;;) { @autoreleasepool {
        int status=0;
        NSData *data=request(@"GET",[NSString stringWithFormat:@"/.henge/touch-target?since=%llu",since],nil,&status,NULL);
        if(status!=200 || data.length>100) { if(status==403) prompted=NO; if(status!=204) sleep(2); continue; }
        NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        unsigned long long id=0; double x=0,y=0; char extra;
        if(!text || sscanf(text.UTF8String,"%llu %lf %lf %c",&id,&x,&y,&extra)!=3 || !id ||
           !isfinite(x) || !isfinite(y) || x<0 || x>1 || y<0 || y>1) continue;
        since=id;
        int hint=targetHint(x,y);
        if(hint==HV_TARGET_PERMISSION && !prompted) {
            prompted=YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
            });
        }
        NSString *reply=[NSString stringWithFormat:@"%llu %d",id,hint];
        request(@"PUT",@"/.henge/touch-target",[reply dataUsingEncoding:NSUTF8StringEncoding],&status,NULL);
    } }
}

int main(void) {
    @autoreleasepool {
        lastChange = NSPasteboard.generalPasteboard.changeCount;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ followDevice(); });
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{ followTouchTargets(); });
        keepMounted();
        [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) { (void)timer; checkFocus(); }];
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { (void)timer; checkClipboard(); }];
        [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *timer) { (void)timer; keepMounted(); }];
        [NSRunLoop.mainRunLoop run];
    }
    return 0;
}

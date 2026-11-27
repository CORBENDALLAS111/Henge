#import <AppKit/AppKit.h>
#include "agent-http.h"
#include "../host/host_device.h"
#include <time.h>

static double deviceNow(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static NSDictionary *deviceReport(NSData *data) {
    if(!data || data.length>2048) return nil;
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(![value isKindOfClass:NSDictionary.class] || ![value[@"version"] isKindOfClass:NSNumber.class] || [value[@"version"] intValue]!=1) return nil;
    for(NSString *key in @[ @"session",@"gain_revision",@"brightness_revision" ]) if(![value[key] isKindOfClass:NSString.class]) return nil;
    for(NSString *key in @[ @"battery",@"power",@"low_power",@"thermal",@"host_kind",@"external_display",@"audio_route",@"peripherals",@"system_volume",@"brightness",@"vm_gain",@"controls",@"pending",@"gain_target",@"brightness_target" ])
        if(![value[key] isKindOfClass:NSNumber.class] || !isfinite([value[key] doubleValue])) return nil;
    return value;
}

@interface HengeDeviceSlider : NSSlider
@property(nonatomic) BOOL tracking;
@end
@implementation HengeDeviceSlider
- (void)mouseDown:(NSEvent *)event { self.tracking=YES; [super mouseDown:event]; self.tracking=NO; }
@end

@interface HengeDeviceMenu : NSObject
@property(nonatomic,strong) NSStatusItem *item;
@property(nonatomic,strong) NSDictionary *snapshot;
@property(nonatomic,strong) NSMenuItem *power,*route,*display,*thermal,*peripherals,*systemVolume,*permission,*result,*mute;
@property(nonatomic,strong) HengeDeviceSlider *gain,*brightness;
@property(nonatomic,strong) NSTextField *gainLabel,*brightnessLabel;
@property(nonatomic) BOOL polling,busy,supported;
@property(nonatomic) double seen,lastGain;
@end

@implementation HengeDeviceMenu
- (NSMenuItem *)line:(NSMenu *)menu text:(NSString *)text {
    NSMenuItem *line=[[NSMenuItem alloc] initWithTitle:text action:NULL keyEquivalent:@""];
    line.enabled=NO; [menu addItem:line]; return line;
}
- (NSMenuItem *)control:(NSMenu *)menu title:(NSString *)title slider:(HengeDeviceSlider **)slider label:(NSTextField **)label action:(SEL)action {
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,280,54)];
    NSTextField *text=[NSTextField labelWithString:title]; text.frame=NSMakeRect(18,31,248,17); text.font=[NSFont menuFontOfSize:12];
    HengeDeviceSlider *control=[[HengeDeviceSlider alloc] initWithFrame:NSMakeRect(18,7,244,22)];
    control.minValue=0; control.maxValue=1; control.continuous=NO; control.target=self; control.action=action;
    control.accessibilityLabel=title;
    [view addSubview:text]; [view addSubview:control];
    NSMenuItem *entry=[NSMenuItem new]; entry.view=view; [menu addItem:entry];
    *slider=control; *label=text; return entry;
}
- (instancetype)init {
    if(!(self=[super init])) return nil;
    _lastGain=1;
    _item=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _item.button.title=@"Henge"; _item.button.toolTip=@"iPhone/iPad status shared by Henge";
    NSMenu *menu=[[NSMenu alloc] initWithTitle:@"Henge device"];
    menu.autoenablesItems=NO;
    _power=[self line:menu text:@"Device status unavailable"];
    _route=[self line:menu text:@"Audio output: unavailable"];
    _display=[self line:menu text:@"Mac video output: unavailable"];
    _thermal=[self line:menu text:@"Power/thermal state: unavailable"];
    _peripherals=[self line:menu text:@"Host peripherals: unavailable"];
    _systemVolume=[self line:menu text:@"Device system volume: unavailable"];
    [menu addItem:NSMenuItem.separatorItem];
    HengeDeviceSlider *gain,*brightness; NSTextField *gainLabel,*brightnessLabel;
    [self control:menu title:@"Mac audio level (Henge)" slider:&gain label:&gainLabel action:@selector(gainChanged:)];
    [self control:menu title:@"Device screen brightness" slider:&brightness label:&brightnessLabel action:@selector(brightnessChanged:)];
    _gain=gain; _brightness=brightness; _gainLabel=gainLabel; _brightnessLabel=brightnessLabel;
    _mute=[[NSMenuItem alloc] initWithTitle:@"Mute Mac audio" action:@selector(toggleMute:) keyEquivalent:@""];
    _mute.target=self; [menu addItem:_mute];
    _permission=[self line:menu text:@"Enable guest controls in Henge, Device Integration"];
    _result=[self line:menu text:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [self line:menu text:@"Battery is host status; macOS power hardware is unchanged."];
    _item.menu=menu;
    __weak HengeDeviceMenu *weak=self;
    NSTimer *timer=[NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        (void)timer; HengeDeviceMenu *strong=weak; if(!strong) return;
        [strong update]; [strong poll];
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    [self update]; [self poll]; return self;
}
- (BOOL)live { return self.snapshot && self.seen>0 && deviceNow()-self.seen<6; }
- (void)poll {
    if(self.polling || self.busy) return;
    self.polling=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        int code=0; NSData *data=HengeAgentRequest(@"GET",@"/.henge/device-status",nil,&code,NULL,3);
        NSDictionary *report=code==200?deviceReport(data):nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.polling=NO;
            if(report) { self.snapshot=report; self.seen=deviceNow(); self.supported=YES; self.item.visible=YES; }
            else if(code==403 || code==503) { self.snapshot=nil; self.seen=0; }
            else if(code==404 && !self.supported) { self.item.visible=NO; }
            [self update];
        });
    });
}
- (void)update {
    BOOL live=[self live],allowed=live && [self.snapshot[@"controls"] boolValue] && !self.busy;
    self.gain.enabled=allowed; self.brightness.enabled=allowed && [self.snapshot[@"brightness"] doubleValue]>=0;
    self.mute.enabled=allowed;
    if(!live) {
        self.item.button.title=@"Henge · unavailable";
        self.power.title=@"Host status unavailable — open Henge on the device";
        self.route.title=@"Audio output: unavailable"; self.display.title=@"Mac video output: unavailable";
        self.thermal.title=@"Power/thermal state: unavailable"; self.peripherals.title=@"Host peripherals: unavailable";
        self.systemVolume.title=@"Device system volume: unavailable"; self.permission.title=@"Guest controls unavailable";
        return;
    }
    NSDictionary *s=self.snapshot;
    NSString *host=[s[@"host_kind"] intValue]==1?@"iPad":[s[@"host_kind"] intValue]==0?@"iPhone":@"Device";
    int battery=[s[@"battery"] intValue],power=[s[@"power"] intValue];
    NSString *charge=battery>=0?[NSString stringWithFormat:@"%d%%",battery]:@"Unknown";
    NSArray *states=@[ @"Power source unknown",@"On battery",@"Charging",@"Connected to power · full" ];
    self.power.title=[NSString stringWithFormat:@"%@ battery: %@ · %@",host,charge,states[MAX(0,MIN(power,3))]];
    self.item.button.title=[NSString stringWithFormat:@"%@ %@%@",host,battery>=0?charge:@"—",power>=2?@" ⚡":@""];
    uint32_t routes=[s[@"audio_route"] unsignedIntValue]; NSMutableArray *names=[NSMutableArray array];
    NSArray *routeNames=@[ @"Speaker",@"Receiver",@"Headphones/line",@"USB",@"Bluetooth",@"AirPlay",@"HDMI/DisplayPort",@"Other" ];
    for(int bit=0;bit<8;bit++) if(routes & (1u<<bit)) [names addObject:routeNames[bit]];
    self.route.title=[@"Audio output: " stringByAppendingString:(names.count?[names componentsJoinedByString:@", "]:@"None")];
    self.display.title=[s[@"external_display"] boolValue]?@"Mac video output: External display":@"Mac video output: Device screen";
    NSArray *heat=@[ @"Normal",@"Fair",@"Serious",@"Critical" ]; int thermal=[s[@"thermal"] intValue];
    self.thermal.title=[NSString stringWithFormat:@"Low Power Mode: %@ · Thermal: %@",[s[@"low_power"] boolValue]?@"On":@"Off",heat[MAX(0,MIN(thermal,3))]];
    unsigned peripherals=[s[@"peripherals"] unsignedIntValue];
    self.peripherals.title=[NSString stringWithFormat:@"Host keyboard %@ · mouse/trackpad %@ · controller %@",peripherals&1?@"✓":@"—",peripherals&2?@"✓":@"—",peripherals&4?@"✓":@"—"];
    double system=[s[@"system_volume"] doubleValue],gain=[s[@"gain_target"] doubleValue],brightness=[s[@"brightness_target"] doubleValue];
    self.systemVolume.title=system>=0?[NSString stringWithFormat:@"Device system volume: %.0f%% (read only)",system*100]:@"Device system volume: unavailable";
    if(gain>0) self.lastGain=gain;
    if(!self.gain.tracking && !self.busy) self.gain.doubleValue=gain;
    if(!self.brightness.tracking && !self.busy && brightness>=0) self.brightness.doubleValue=brightness;
    self.gainLabel.stringValue=[NSString stringWithFormat:@"Mac audio level (Henge): %.0f%%",gain*100];
    self.brightnessLabel.stringValue=brightness>=0?[NSString stringWithFormat:@"%@ screen brightness: %.0f%%",host,brightness*100]:@"Device screen brightness: unavailable";
    self.mute.title=gain>0?@"Mute Mac audio":@"Unmute Mac audio";
    self.permission.title=[s[@"controls"] boolValue]?@"Controls apply while Henge is active":@"Enable guest controls in Henge, Device Integration";
    if([s[@"pending"] intValue]) self.result.title=@"Applying device control…";
    else if([self.result.title isEqualToString:@"Applying device control…"]) self.result.title=@"";
}
- (void)gainChanged:(NSSlider *)sender { [self command:HV_DEVICE_GAIN value:sender.doubleValue]; }
- (void)brightnessChanged:(NSSlider *)sender { [self command:HV_DEVICE_BRIGHTNESS value:sender.doubleValue]; }
- (void)toggleMute:(id)sender { (void)sender; [self command:HV_DEVICE_GAIN value:[self.snapshot[@"gain_target"] doubleValue]>0?0:self.lastGain]; }
- (void)command:(int)field value:(double)value {
    if(![self live] || ![self.snapshot[@"controls"] boolValue] || self.busy || !hv_device_level(value,0)) return;
    NSString *revision=self.snapshot[field==HV_DEVICE_GAIN?@"gain_revision":@"brightness_revision"];
    NSString *body=[NSString stringWithFormat:@"%@ %d %@ %.6f",self.snapshot[@"session"],field,revision,value];
    self.busy=YES; self.result.title=@"Applying device control…"; [self update];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        int code=0,status=0;
        HengeAgentRequest(@"PUT",@"/.henge/device-control",[body dataUsingEncoding:NSUTF8StringEncoding],&code,NULL,3);
        NSData *data=HengeAgentRequest(@"GET",@"/.henge/device-status",nil,&status,NULL,3);
        NSDictionary *report=status==200?deviceReport(data):nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy=NO;
            if(report) { self.snapshot=report; self.seen=deviceNow(); }
            else { self.snapshot=nil; self.seen=0; }
            self.result.title=code==202?@"":code==409?@"Device changed; state refreshed. Try again.":@"Guest control unavailable; check Henge.";
            [self update];
        });
    });
}
@end

void HengeStartDeviceMenu(void) {
    static HengeDeviceMenu *menu;
    if(!menu) menu=[HengeDeviceMenu new];
}

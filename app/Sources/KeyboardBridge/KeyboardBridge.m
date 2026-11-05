#import "KeyboardBridge.h"
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

// Signatures verified against the installed CoreBrightness Objective-C runtime.
// All keyboard writes go through CoreBrightness. IORegistry is read-only.
@protocol NWKeyboardClient
- (NSArray *)copyKeyboardBacklightIDs;
- (BOOL)isKeyboardBuiltIn:(uint64_t)keyboard;
- (float)brightnessForKeyboard:(uint64_t)keyboard;
- (BOOL)isAutoBrightnessEnabledForKeyboard:(uint64_t)keyboard;
- (double)idleDimTimeForKeyboard:(uint64_t)keyboard;
- (BOOL)setBrightness:(float)value fadeSpeed:(int)milliseconds commit:(BOOL)commit forKeyboard:(uint64_t)keyboard;
- (BOOL)enableAutoBrightness:(BOOL)enabled forKeyboard:(uint64_t)keyboard;
@end
static id<NWKeyboardClient> client;
static uint64_t keyboardID;
static io_service_t pwm;

bool NWKeyboardOpen(void) {
    if (client) return true;
    if (!dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)) return false;
    Class cls = NSClassFromString(@"KeyboardBrightnessClient");
    if (!cls) return false;
    NSArray<NSString *> *selectors = @[@"copyKeyboardBacklightIDs", @"isKeyboardBuiltIn:", @"brightnessForKeyboard:", @"isAutoBrightnessEnabledForKeyboard:", @"idleDimTimeForKeyboard:", @"setBrightness:fadeSpeed:commit:forKeyboard:", @"enableAutoBrightness:forKeyboard:"];
    for (NSString *name in selectors) if (![cls instancesRespondToSelector:NSSelectorFromString(name)]) return false;
    @try {
        id<NWKeyboardClient> candidate = (id)[[cls alloc] init];
        for (NSNumber *number in [candidate copyKeyboardBacklightIDs]) {
            if (![number isKindOfClass:NSNumber.class]) continue;
            uint64_t identifier = number.unsignedLongLongValue;
            if ([candidate isKeyboardBuiltIn:identifier]) {
                float value = [candidate brightnessForKeyboard:identifier];
                double timeout = [candidate idleDimTimeForKeyboard:identifier];
                if (!isfinite(value) || value < 0 || value > 1 || !isfinite(timeout) || timeout < 0) continue;
                client = candidate; keyboardID = identifier;
                pwm = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("kbd-backlight"));
                return true;
            }
        }
    } @catch (NSException *exception) { return false; }
    return false;
}
uint64_t NWKeyboardID(void) { return keyboardID; }
float NWBrightness(void) { @try {return client ? [client brightnessForKeyboard:keyboardID] : NAN;} @catch(NSException *e) {return NAN;} }
bool NWAutoBrightness(void) { return client && [client isAutoBrightnessEnabledForKeyboard:keyboardID]; }
double NWIdleTimeout(void) { return client ? [client idleDimTimeForKeyboard:keyboardID] : NAN; }
bool NWSetBrightness(float value, int fade) {
    if (!client || !isfinite(value) || value < 0 || value > 1 || fade < 0 || fade > 5000) return false;
    @try { return [client setBrightness:value fadeSpeed:fade commit:NO forKeyboard:keyboardID]; } @catch(NSException *e) {return false;}
}
bool NWSetAutoBrightness(bool enabled) {
    if (!client) return false;
    @try { return [client enableAutoBrightness:enabled forKeyboard:keyboardID]; } @catch(NSException *e) {return false;}
}
static CFTypeRef property(CFStringRef key) {
    return pwm ? IORegistryEntryCreateCFProperty(pwm, key, kCFAllocatorDefault, 0) : NULL;
}
double NWPWMHigh(void) {
    CFTypeRef value = property(CFSTR("high-period")); double result = NAN;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberDoubleType, &result);
    if (value) CFRelease(value);
    return result;
}
bool NWPWMEnabled(void) {
    CFTypeRef value = property(CFSTR("enabled"));
    bool enabled = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
    if (value) CFRelease(value);
    return enabled;
}
bool NWPWMAvailable(void) { return isfinite(NWPWMHigh()); }
double NWIdleSeconds(void) { return CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType); }

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL (*orig_setCategory)(id, SEL, AVAudioSessionCategory, NSError **);
static BOOL (*orig_setCategoryWithOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setCategoryModeOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionMode, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setCategoryModeRouteSharingPolicyOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionMode, AVAudioSessionRouteSharingPolicy, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setMode)(id, SEL, AVAudioSessionMode, NSError **);
static BOOL (*orig_overrideOutputAudioPort)(id, SEL, AVAudioSessionPortOverride, NSError **);

static AVAudioSessionCategoryOptions fixOptions(AVAudioSessionCategory category, AVAudioSessionCategoryOptions options) {
    if ([category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        options |= (AVAudioSessionCategoryOptionAllowBluetooth |
                    AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                    AVAudioSessionCategoryOptionAllowAirPlay |
                    AVAudioSessionCategoryOptionDefaultToSpeaker);
    }
    return options;
}

static AVAudioSessionMode fixMode(AVAudioSessionMode mode) {
    if ([mode isEqualToString:AVAudioSessionModeVoiceChat] ||
        [mode isEqualToString:AVAudioSessionModeVideoChat] ||
        [mode isEqualToString:AVAudioSessionModeVoicePrompt]) {
        return AVAudioSessionModeDefault;
    }
    return mode;
}

static BOOL hook_setCategory(id self, SEL _cmd, AVAudioSessionCategory category, NSError **outError) {
    if ([category isEqualToString:AVAudioSessionCategoryPlayAndRecord] && orig_setCategoryWithOptions) {
        return orig_setCategoryWithOptions(self, @selector(setCategory:withOptions:error:), category, fixOptions(category, 0), outError);
    }
    if (orig_setCategory) {
        return orig_setCategory(self, _cmd, category, outError);
    }
    return YES;
}

static BOOL hook_setCategoryWithOptions(id self, SEL _cmd, AVAudioSessionCategory category, AVAudioSessionCategoryOptions options, NSError **outError) {
    if (orig_setCategoryWithOptions) {
        return orig_setCategoryWithOptions(self, _cmd, category, fixOptions(category, options), outError);
    }
    return YES;
}

static BOOL hook_setCategoryModeOptions(id self, SEL _cmd, AVAudioSessionCategory category, AVAudioSessionMode mode, AVAudioSessionCategoryOptions options, NSError **outError) {
    if (orig_setCategoryModeOptions) {
        return orig_setCategoryModeOptions(self, _cmd, category, fixMode(mode), fixOptions(category, options), outError);
    }
    return YES;
}

static BOOL hook_setCategoryModeRouteSharingPolicyOptions(id self, SEL _cmd, AVAudioSessionCategory category, AVAudioSessionMode mode, AVAudioSessionRouteSharingPolicy policy, AVAudioSessionCategoryOptions options, NSError **outError) {
    if (orig_setCategoryModeRouteSharingPolicyOptions) {
        return orig_setCategoryModeRouteSharingPolicyOptions(self, _cmd, category, fixMode(mode), policy, fixOptions(category, options), outError);
    }
    return YES;
}

static BOOL hook_setMode(id self, SEL _cmd, AVAudioSessionMode mode, NSError **outError) {
    if (orig_setMode) {
        return orig_setMode(self, _cmd, fixMode(mode), outError);
    }
    return YES;
}

static BOOL hook_overrideOutputAudioPort(id self, SEL _cmd, AVAudioSessionPortOverride portOverride, NSError **outError) {
    if (orig_overrideOutputAudioPort) {
        return orig_overrideOutputAudioPort(self, _cmd, portOverride, outError);
    }
    return YES;
}

__attribute__((constructor))
static void initAudioFix(void) {
    Class cls = [AVAudioSession class];
    if (!cls) return;

    Method m1 = class_getInstanceMethod(cls, @selector(setCategory:error:));
    if (m1) orig_setCategory = (void *)method_setImplementation(m1, (IMP)hook_setCategory);

    Method m2 = class_getInstanceMethod(cls, @selector(setCategory:withOptions:error:));
    if (m2) orig_setCategoryWithOptions = (void *)method_setImplementation(m2, (IMP)hook_setCategoryWithOptions);

    Method m3 = class_getInstanceMethod(cls, @selector(setCategory:mode:options:error:));
    if (m3) orig_setCategoryModeOptions = (void *)method_setImplementation(m3, (IMP)hook_setCategoryModeOptions);

    SEL sel4 = @selector(setCategory:mode:routeSharingPolicy:options:error:);
    Method m4 = class_getInstanceMethod(cls, sel4);
    if (m4) orig_setCategoryModeRouteSharingPolicyOptions = (void *)method_setImplementation(m4, (IMP)hook_setCategoryModeRouteSharingPolicyOptions);

    Method m5 = class_getInstanceMethod(cls, @selector(setMode:error:));
    if (m5) orig_setMode = (void *)method_setImplementation(m5, (IMP)hook_setMode);

    Method m6 = class_getInstanceMethod(cls, @selector(overrideOutputAudioPort:error:));
    if (m6) orig_overrideOutputAudioPort = (void *)method_setImplementation(m6, (IMP)hook_overrideOutputAudioPort);
}

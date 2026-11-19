#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL (*orig_setCategory)(id, SEL, AVAudioSessionCategory, NSError **);
static BOOL (*orig_setCategoryWithOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setCategoryModeOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionMode, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setCategoryModeRouteSharingPolicyOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionMode, AVAudioSessionRouteSharingPolicy, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setMode)(id, SEL, AVAudioSessionMode, NSError **);

static AVAudioSessionCategoryOptions fixOptions(AVAudioSessionCategory category, AVAudioSessionCategoryOptions options) {
    if ([category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        // Разрешаем качественное стерео A2DP (для Logitech G435)
        options |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
        // Отключаем телефонный режим HFP (с микрофоном), который крашил звук на G435
        options &= ~AVAudioSessionCategoryOptionAllowBluetooth;
        // Обязательно держим динамик телефона активным при отключении наушников
        options |= AVAudioSessionCategoryOptionDefaultToSpeaker;
        options |= AVAudioSessionCategoryOptionAllowAirPlay;
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

    // Уведомление
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class uiAppCls = NSClassFromString(@"UIApplication");
        Class alertCls = NSClassFromString(@"UIAlertController");
        Class actionCls = NSClassFromString(@"UIAlertAction");
        if (!uiAppCls || !alertCls || !actionCls) return;

        id app = ((id (*)(id, SEL))objc_msgSend)(uiAppCls, sel_registerName("sharedApplication"));
        if (!app) return;

        id window = ((id (*)(id, SEL))objc_msgSend)(app, sel_registerName("keyWindow"));
        if (!window) {
            id scenes = ((id (*)(id, SEL))objc_msgSend)(app, sel_registerName("connectedScenes"));
            for (id scene in scenes) {
                id windows = ((id (*)(id, SEL))objc_msgSend)(scene, sel_registerName("windows"));
                for (id w in windows) {
                    BOOL isKey = ((BOOL (*)(id, SEL))objc_msgSend)(w, sel_registerName("isKeyWindow"));
                    if (isKey) { window = w; break; }
                }
                if (window) break;
            }
        }
        if (!window) return;

        id root = ((id (*)(id, SEL))objc_msgSend)(window, sel_registerName("rootViewController"));
        while (root) {
            id presented = ((id (*)(id, SEL))objc_msgSend)(root, sel_registerName("presentedViewController"));
            if (!presented) break;
            root = presented;
        }
        if (!root) return;

        id alert = ((id (*)(id, SEL, id, id, NSInteger))objc_msgSend)(alertCls, 
            sel_registerName("alertControllerWithTitle:message:preferredStyle:"), 
            @"AudioFix G435", 
            @"Фикс применён! Стерео A2DP активно.", 
            1);

        id action = ((id (*)(id, SEL, id, NSInteger, id))objc_msgSend)(actionCls, 
            sel_registerName("actionWithTitle:style:handler:"), 
            @"OK", 
            0, 
            nil);

        ((void (*)(id, SEL, id))objc_msgSend)(alert, sel_registerName("addAction:"), action);
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(root, sel_registerName("presentViewController:animated:completion:"), alert, YES, nil);
    });
}

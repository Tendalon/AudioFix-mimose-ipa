#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// --- 1. AVAudioSession Hooks ---
static BOOL (*orig_setCategory)(id, SEL, AVAudioSessionCategory, NSError **);
static BOOL (*orig_setCategoryWithOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setCategoryModeOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionMode, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setCategoryModeRouteSharingPolicyOptions)(id, SEL, AVAudioSessionCategory, AVAudioSessionMode, AVAudioSessionRouteSharingPolicy, AVAudioSessionCategoryOptions, NSError **);
static BOOL (*orig_setMode)(id, SEL, AVAudioSessionMode, NSError **);

static AVAudioSessionCategoryOptions fixOptions(AVAudioSessionCategory category, AVAudioSessionCategoryOptions options) {
    options |= (AVAudioSessionCategoryOptionAllowBluetooth |
                AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                AVAudioSessionCategoryOptionAllowAirPlay |
                AVAudioSessionCategoryOptionDefaultToSpeaker);
    return options;
}

static BOOL hook_setCategory(id self, SEL _cmd, AVAudioSessionCategory category, NSError **outError) {
    if (orig_setCategoryWithOptions) {
        return orig_setCategoryWithOptions(self, @selector(setCategory:withOptions:error:), AVAudioSessionCategoryPlayback, fixOptions(AVAudioSessionCategoryPlayback, 0), outError);
    }
    if (orig_setCategory) {
        return orig_setCategory(self, _cmd, AVAudioSessionCategoryPlayback, outError);
    }
    return YES;
}

static BOOL hook_setCategoryWithOptions(id self, SEL _cmd, AVAudioSessionCategory category, AVAudioSessionCategoryOptions options, NSError **outError) {
    if (orig_setCategoryWithOptions) {
        return orig_setCategoryWithOptions(self, _cmd, AVAudioSessionCategoryPlayback, fixOptions(category, options), outError);
    }
    return YES;
}

static BOOL hook_setCategoryModeOptions(id self, SEL _cmd, AVAudioSessionCategory category, AVAudioSessionMode mode, AVAudioSessionCategoryOptions options, NSError **outError) {
    if (orig_setCategoryModeOptions) {
        return orig_setCategoryModeOptions(self, _cmd, AVAudioSessionCategoryPlayback, AVAudioSessionModeDefault, fixOptions(category, options), outError);
    }
    return YES;
}

static BOOL hook_setCategoryModeRouteSharingPolicyOptions(id self, SEL _cmd, AVAudioSessionCategory category, AVAudioSessionMode mode, AVAudioSessionRouteSharingPolicy policy, AVAudioSessionCategoryOptions options, NSError **outError) {
    if (orig_setCategoryModeRouteSharingPolicyOptions) {
        return orig_setCategoryModeRouteSharingPolicyOptions(self, _cmd, AVAudioSessionCategoryPlayback, AVAudioSessionModeDefault, policy, fixOptions(category, options), outError);
    }
    return YES;
}

static BOOL hook_setMode(id self, SEL _cmd, AVAudioSessionMode mode, NSError **outError) {
    if (orig_setMode) {
        return orig_setMode(self, _cmd, AVAudioSessionModeDefault, outError);
    }
    return YES;
}

// --- 2. MimoseEqualizer & AudioTap Hooks ---
// Блокируем кривой эквалайзер Мимозы, возвращая нативный звук Apple AVPlayer
static void hook_attachToItem(id self, SEL _cmd, id item) {
    NSLog(@"[AudioFix] MimoseEqualizer attachToItem blocked! Native audio will play.");
}

static void hook_setAudioTapProcessor(id self, SEL _cmd, void *tap) {
    NSLog(@"[AudioFix] setAudioTapProcessor blocked to prevent silence in headphones!");
}

__attribute__((constructor))
static void initAudioFix(void) {
    // 1. Хукаем аудиосессию
    Class audioSessionCls = [AVAudioSession class];
    if (audioSessionCls) {
        Method m1 = class_getInstanceMethod(audioSessionCls, @selector(setCategory:error:));
        if (m1) orig_setCategory = (void *)method_setImplementation(m1, (IMP)hook_setCategory);

        Method m2 = class_getInstanceMethod(audioSessionCls, @selector(setCategory:withOptions:error:));
        if (m2) orig_setCategoryWithOptions = (void *)method_setImplementation(m2, (IMP)hook_setCategoryWithOptions);

        Method m3 = class_getInstanceMethod(audioSessionCls, @selector(setCategory:mode:options:error:));
        if (m3) orig_setCategoryModeOptions = (void *)method_setImplementation(m3, (IMP)hook_setCategoryModeOptions);

        Method m4 = class_getInstanceMethod(audioSessionCls, @selector(setCategory:mode:routeSharingPolicy:options:error:));
        if (m4) orig_setCategoryModeRouteSharingPolicyOptions = (void *)method_setImplementation(m4, (IMP)hook_setCategoryModeRouteSharingPolicyOptions);

        Method m5 = class_getInstanceMethod(audioSessionCls, @selector(setMode:error:));
        if (m5) orig_setMode = (void *)method_setImplementation(m5, (IMP)hook_setMode);

        NSError *err = nil;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                         withOptions:(AVAudioSessionCategoryOptionAllowBluetooth |
                                                      AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                                      AVAudioSessionCategoryOptionAllowAirPlay)
                                               error:&err];
        [[AVAudioSession sharedInstance] setActive:YES error:&err];
    }

    // 2. Блокируем MimoseEqualizer
    Class eqCls = NSClassFromString(@"MimoseEqualizer");
    if (eqCls) {
        Method mAttach = class_getInstanceMethod(eqCls, @selector(attachToItem:));
        if (mAttach) {
            method_setImplementation(mAttach, (IMP)hook_attachToItem);
        }
    }

    // 3. Блокируем вызовы setAudioTapProcessor в AVFoundation
    Class mixInputCls = NSClassFromString(@"AVMutableAudioMixInputParameters");
    if (mixInputCls) {
        Method mTap = class_getInstanceMethod(mixInputCls, @selector(setAudioTapProcessor:));
        if (mTap) {
            method_setImplementation(mTap, (IMP)hook_setAudioTapProcessor);
        }
    }

    // 4. Всплывающее уведомление для визуального подтверждения
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
            }
        }
        if (!window) window = [UIApplication sharedApplication].keyWindow;
        UIViewController *root = window.rootViewController;
        while (root.presentedViewController) {
            root = root.presentedViewController;
        }
        if (root) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AudioFix" 
                                                                           message:@"Патч успешно применён!\nКривой эквалайзер обезврежен, звук в наушниках разблокирован." 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Отлично" style:UIAlertActionStyleDefault handler:nil]];
            [root presentViewController:alert animated:YES completion:nil];
        }
    });
}

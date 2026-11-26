#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Sparkle/Sparkle.h>

static void record(NSString *event) {
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Rasc Voice Update Probe"];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [root stringByAppendingPathComponent:@"events.txt"];
    NSString *line = [NSString stringWithFormat:@"build=%@ mic=%ld %@\n",
                       [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                       (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio], event];
    @synchronized (NSProcessInfo.processInfo) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

@interface Driver : SPUStandardUserDriver
@end

@implementation Driver
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state
                              reply:(void (^)(SPUUserUpdateChoice))reply {
    record(@"sparkle-found-update");
    reply(SPUUserUpdateChoiceInstall);
}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {
    record(@"sparkle-ready-to-relaunch");
    reply(SPUUserUpdateChoiceInstall);
}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack {
    record([NSString stringWithFormat:@"sparkle-error %@ %ld %@", error.domain, (long)error.code, error.localizedDescription]);
    ack();
}
@end

@interface Delegate : NSObject <NSApplicationDelegate>
@property (strong) SPUUpdater *updater;
@end

@implementation Delegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    record(@"launch");
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    if ([args containsObject:@"--request"]) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            record(granted ? @"permission-allowed" : @"permission-denied");
            dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        }];
        return;
    }
    if ([args containsObject:@"--upgrade"]) {
        Driver *driver = [[Driver alloc] initWithHostBundle:NSBundle.mainBundle delegate:nil];
        self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle
                                            applicationBundle:NSBundle.mainBundle userDriver:driver delegate:nil];
        NSError *error = nil;
        if (![self.updater startUpdater:&error]) {
            record([NSString stringWithFormat:@"sparkle-start-error %@ %ld", error.domain, (long)error.code]);
            [NSApp terminate:nil];
            return;
        }
        [self.updater checkForUpdates];
        return;
    }
    [NSApp terminate:nil];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        Delegate *delegate = [Delegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

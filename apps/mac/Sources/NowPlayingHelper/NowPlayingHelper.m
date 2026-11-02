// Now-playing helper. Since macOS 15.4, MediaRemote only answers Apple-signed processes, so Notch Island
// runs /usr/bin/perl, which loads this library and calls notchisland_nowplaying_run(). (osascript would be
// nicer, but as an arm64e platform binary it refuses non-Apple code.)
// Streams JSON lines on stdout and reads commands on stdin; stdin closing (Notch Island quit) ends it.
#import <Foundation/Foundation.h>
#import <dlfcn.h>

static void (*getInfo)(dispatch_queue_t, void (^)(NSDictionary *));
static void (*getClient)(dispatch_queue_t, void (^)(id));
static NSString *(*clientBundleID)(id);
static Boolean (*sendCommand)(int, NSDictionary *);
static void (*setElapsed)(double);
static dispatch_queue_t queue;
static NSString *lastArtTrack;

static void emit(void) {
    getInfo(queue, ^(NSDictionary *info) {
        getClient(queue, ^(id client) {
            NSMutableDictionary *o = [NSMutableDictionary dictionary];
            if (info.count) {
                id (^v)(NSString *) = ^id(NSString *k) { return info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:k]]; };
                o[@"title"] = v(@"Title") ?: @"";
                o[@"artist"] = v(@"Artist") ?: @"";
                o[@"album"] = v(@"Album") ?: @"";
                o[@"duration"] = v(@"Duration") ?: @0;
                o[@"elapsed"] = v(@"ElapsedTime") ?: @0;
                o[@"rate"] = v(@"PlaybackRate") ?: @0;
                o[@"ts"] = @(((NSDate *)v(@"Timestamp") ?: NSDate.date).timeIntervalSince1970);
                o[@"bundle"] = (client && clientBundleID ? clientBundleID(client) : nil) ?: @"";
                // Artwork once per track. Players often report a track without it for a moment
                // (on play/pause, skips), so a missing image is never sent as a change.
                NSData *art = v(@"ArtworkData");
                NSString *track = [NSString stringWithFormat:@"%@|%@|%@", o[@"title"], o[@"artist"], o[@"album"]];
                if (art.length && ![track isEqualToString:lastArtTrack]) {
                    lastArtTrack = track;
                    o[@"art"] = [art base64EncodedStringWithOptions:0];
                }
            }
            NSData *json = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
            fwrite(json.bytes, 1, json.length, stdout);
            fputc('\n', stdout);
            fflush(stdout);
        });
    });
}

@interface NotchIslandNowPlaying : NSObject
@end

@implementation NotchIslandNowPlaying
+ (void)run {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    getInfo = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getClient = dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    clientBundleID = dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    sendCommand = dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = dlsym(mr, "MRMediaRemoteSetElapsedTime");
    void (*registerForNotifications)(dispatch_queue_t) = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getClient || !registerForNotifications) exit(2);

    queue = dispatch_queue_create("notchisland.nowplaying", DISPATCH_QUEUE_SERIAL);
    registerForNotifications(queue);
    for (NSString *sym in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        NSString *__strong *name = (NSString *__strong *)dlsym(mr, sym.UTF8String);
        if (name) [NSNotificationCenter.defaultCenter addObserverForName:*name object:nil queue:nil
                                                              usingBlock:^(NSNotification *n) { emit(); }];
    }
    emit();

    // Commands, one per line: toggle | next | prev | seek <seconds>
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char line[128];
        double t;
        while (fgets(line, sizeof line, stdin)) {
            if (!strncmp(line, "toggle", 6)) sendCommand(2, nil);
            else if (!strncmp(line, "next", 4)) sendCommand(4, nil);
            else if (!strncmp(line, "prev", 4)) sendCommand(5, nil);
            else if (sscanf(line, "seek %lf", &t) == 1 && setElapsed) setElapsed(t);
        }
        exit(0);
    });

    [NSRunLoop.currentRunLoop addPort:NSMachPort.port forMode:NSDefaultRunLoopMode];
    [NSRunLoop.currentRunLoop run];
}
@end

// C entry point for hosts that can't message Objective-C (perl's DynaLoader)
void notchisland_nowplaying_run(void) { [NotchIslandNowPlaying run]; }

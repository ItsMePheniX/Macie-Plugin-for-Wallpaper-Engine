//
//  PerformanceMonitor.mm
//  MacieWallpaper - Performance Monitoring
//
//  Created on 2026-02-15.
//

#import "PerformanceMonitor.h"
#import "MacieDisplayIdentity.h"
#import "Constants.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

@interface PerformanceMonitor ()
@property (nonatomic, assign) BOOL isOnBattery;
@property (nonatomic, copy) NSSet<NSNumber *> *coveredDisplayIDs;
@property (nonatomic, strong) id powerSourceObserver;
@property (nonatomic, assign) CFRunLoopSourceRef powerRunLoopSource;
@property (nonatomic, assign) BOOL isMonitoring;
- (void)checkPowerSource;
@end

// C callback for power source changes
static void PowerSourceCallback(void *context) {
    PerformanceMonitor *monitor = (__bridge PerformanceMonitor *)context;
    [monitor checkPowerSource];
}

@implementation PerformanceMonitor

- (instancetype)init {
    self = [super init];
    if (self) {
        // Load settings from UserDefaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _pauseOnBattery = [defaults boolForKey:kDefaultsPauseOnBattery];
        _pauseOnFullscreen = [defaults boolForKey:kDefaultsPauseOnFullscreen];
        _isOnBattery = NO;
        _coveredDisplayIDs = [NSSet set];
        _isMonitoring = NO;
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Lifecycle

- (void)startMonitoring {
    if (self.isMonitoring) return;
    self.isMonitoring = YES;
    
    // Initial state check
    [self checkPowerSource];
    [self checkFullscreenState];
    
    // Set up power source monitoring
    self.powerRunLoopSource = IOPSNotificationCreateRunLoopSource(PowerSourceCallback, (__bridge void *)self);
    if (self.powerRunLoopSource) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), self.powerRunLoopSource, kCFRunLoopDefaultMode);
    }
    
    // Set up app activation monitoring for fullscreen detection
    [[NSWorkspace sharedWorkspace].notificationCenter addObserver:self
                                                         selector:@selector(activeAppDidChange:)
                                                             name:NSWorkspaceDidActivateApplicationNotification
                                                           object:nil];
    
    // Monitor window changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidChange:)
                                                 name:NSWindowDidEnterFullScreenNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidChange:)
                                                 name:NSWindowDidExitFullScreenNotification
                                               object:nil];
}

- (void)stopMonitoring {
    if (!self.isMonitoring) return;
    self.isMonitoring = NO;
    
    // Remove power source monitoring
    if (self.powerRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), self.powerRunLoopSource, kCFRunLoopDefaultMode);
        CFRelease(self.powerRunLoopSource);
        self.powerRunLoopSource = NULL;
    }
    
    // Remove observers
    [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Power Source Monitoring

- (void)checkPowerSource {
    CFTypeRef powerSourceInfo = IOPSCopyPowerSourcesInfo();
    if (!powerSourceInfo) {
        self.isOnBattery = NO;
        return;
    }
    
    CFStringRef powerSourceType = IOPSGetProvidingPowerSourceType(powerSourceInfo);
    BOOL wasOnBattery = self.isOnBattery;
    
    if (powerSourceType) {
        self.isOnBattery = CFStringCompare(powerSourceType, CFSTR(kIOPMBatteryPowerKey), 0) == kCFCompareEqualTo;
    } else {
        self.isOnBattery = NO;
    }
    
    CFRelease(powerSourceInfo);
    
    if (wasOnBattery != self.isOnBattery) {
        [self evaluatePlaybackState];
    }
}

#pragma mark - Fullscreen Detection

- (void)activeAppDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkFullscreenState];
    });
}

- (void)windowDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkFullscreenState];
    });
}

- (void)checkFullscreenState {
    NSSet<NSNumber *> *previous = self.coveredDisplayIDs;
    self.coveredDisplayIDs = [self detectCoveredDisplayIDs];

    if (![previous isEqualToSet:self.coveredDisplayIDs]) {
        [self evaluatePlaybackState];
    }
}

/// CoreGraphics window bounds and NSScreen frames do not share a coordinate space:
/// kCGWindowBounds has its origin at the top-left of the primary display and grows
/// downwards, while NSScreen.frame grows upwards from the bottom-left. Comparing sizes
/// alone sidesteps the flip but cannot say *which* screen a window covers, and attributing
/// one to a screen needs positions — so the screen is converted into CG's space.
static CGRect CGFrameForScreen(NSScreen *screen, CGFloat primaryHeight) {
    NSRect frame = screen.frame;
    return CGRectMake(frame.origin.x,
                      primaryHeight - frame.origin.y - frame.size.height,
                      frame.size.width,
                      frame.size.height);
}

- (NSSet<NSNumber *> *)detectCoveredDisplayIDs {
    // Walking every on-screen window is the expensive part of this class, and it runs on
    // every app activation. With the setting off nobody can act on the answer.
    if (!self.pauseOnFullscreen) return [NSSet set];

    NSRunningApplication *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (!frontmostApp) return [NSSet set];

    // Don't consider our own app as fullscreen
    if ([frontmostApp.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        return [NSSet set];
    }

    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (!screens.count) return [NSSet set];

    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!windowList) return [NSSet set];

    // screens[0] is the zero screen, whose origin is (0,0) in both spaces, so its height is
    // the one that defines the flip.
    const CGFloat primaryHeight = screens.firstObject.frame.size.height;
    const CGFloat tolerance = 10.0;
    pid_t pid = frontmostApp.processIdentifier;

    NSMutableSet<NSNumber *> *covered = [NSMutableSet set];

    CFIndex count = CFArrayGetCount(windowList);
    for (CFIndex i = 0; i < count; i++) {
        NSDictionary *windowInfo = (__bridge NSDictionary *)CFArrayGetValueAtIndex(windowList, i);

        NSNumber *windowPID = windowInfo[(NSString *)kCGWindowOwnerPID];
        if (windowPID.intValue != pid) continue;

        NSNumber *windowLayer = windowInfo[(NSString *)kCGWindowLayer];
        if (windowLayer.intValue != 0) continue; // Only check normal windows

        NSDictionary *boundsDict = windowInfo[(NSString *)kCGWindowBounds];
        if (!boundsDict) continue;

        CGRect bounds;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict, &bounds)) {
            continue;
        }

        for (NSScreen *screen in screens) {
            CGDirectDisplayID displayID = MacieDisplayIDForScreen(screen);
            if (displayID == kCGNullDirectDisplay) continue;
            if ([covered containsObject:@(displayID)]) continue;

            // Covered means this one window accounts for nearly the whole screen. An
            // intersection rather than a bare size comparison, so a fullscreen window on
            // the external display cannot be credited to the built-in one.
            CGRect screenFrame = CGFrameForScreen(screen, primaryHeight);
            CGRect overlap = CGRectIntersection(bounds, screenFrame);

            if (overlap.size.width >= screenFrame.size.width - tolerance &&
                overlap.size.height >= screenFrame.size.height - tolerance) {
                [covered addObject:@(displayID)];
            }
        }
    }

    CFRelease(windowList);
    return [covered copy];
}

#pragma mark - Playback State Evaluation

- (BOOL)shouldPausePlayback {
    // Battery is the only whole-machine reason to stop. Fullscreen is reported per display
    // by -performanceMonitorCoveredScreensChanged:, and folding it in here as well would
    // stop every display for a game running on one of them.
    return self.pauseOnBattery && self.isOnBattery;
}

- (void)evaluatePlaybackState {
    BOOL shouldPause = self.shouldPausePlayback;

    if ([self.delegate respondsToSelector:@selector(performanceMonitorShouldPausePlayback:reason:)]) {
        [self.delegate performanceMonitorShouldPausePlayback:shouldPause
                                                     reason:shouldPause ? @"On battery power" : @""];
    }

    if ([self.delegate respondsToSelector:@selector(performanceMonitorCoveredScreensChanged:)]) {
        [self.delegate performanceMonitorCoveredScreensChanged:self.coveredDisplayIDs];
    }
}

#pragma mark - Settings

- (void)setPauseOnBattery:(BOOL)pauseOnBattery {
    _pauseOnBattery = pauseOnBattery;
    [[NSUserDefaults standardUserDefaults] setBool:pauseOnBattery forKey:kDefaultsPauseOnBattery];
    [self evaluatePlaybackState];
}

- (void)setPauseOnFullscreen:(BOOL)pauseOnFullscreen {
    _pauseOnFullscreen = pauseOnFullscreen;
    [[NSUserDefaults standardUserDefaults] setBool:pauseOnFullscreen forKey:kDefaultsPauseOnFullscreen];

    // Detection is skipped entirely while the setting is off, so the covered set is stale
    // the moment it is switched on and has to be recomputed rather than merely re-sent.
    [self checkFullscreenState];
    [self evaluatePlaybackState];
}

@end

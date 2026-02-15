//
//  PerformanceMonitor.mm
//  MacieWallpaper - Performance Monitoring
//
//  Created on 2026-02-15.
//

#import "PerformanceMonitor.h"
#import "Constants.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

@interface PerformanceMonitor ()
@property (nonatomic, assign) BOOL isOnBattery;
@property (nonatomic, assign) BOOL isFrontmostAppFullscreen;
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
        _isFrontmostAppFullscreen = NO;
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
    BOOL wasFullscreen = self.isFrontmostAppFullscreen;
    self.isFrontmostAppFullscreen = [self detectFullscreenApp];
    
    if (wasFullscreen != self.isFrontmostAppFullscreen) {
        [self evaluatePlaybackState];
    }
}

- (BOOL)detectFullscreenApp {
    NSRunningApplication *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (!frontmostApp) return NO;
    
    // Don't consider our own app as fullscreen
    if ([frontmostApp.bundleIdentifier isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        return NO;
    }
    
    // Check if frontmost app has fullscreen windows
    pid_t pid = frontmostApp.processIdentifier;
    
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!windowList) return NO;
    
    BOOL isFullscreen = NO;
    NSScreen *mainScreen = [NSScreen mainScreen];
    NSRect screenFrame = mainScreen.frame;
    
    CFIndex count = CFArrayGetCount(windowList);
    for (CFIndex i = 0; i < count; i++) {
        NSDictionary *windowInfo = (__bridge NSDictionary *)CFArrayGetValueAtIndex(windowList, i);
        
        NSNumber *windowPID = windowInfo[(NSString *)kCGWindowOwnerPID];
        if (windowPID.intValue != pid) continue;
        
        NSNumber *windowLayer = windowInfo[(NSString *)kCGWindowLayer];
        if (windowLayer.intValue != 0) continue; // Only check normal windows
        
        // Get window bounds
        CGRect bounds;
        NSDictionary *boundsDict = windowInfo[(NSString *)kCGWindowBounds];
        if (boundsDict) {
            CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict, &bounds);
            
            // Check if window covers the entire screen (with some tolerance)
            CGFloat tolerance = 10.0;
            if (bounds.size.width >= screenFrame.size.width - tolerance &&
                bounds.size.height >= screenFrame.size.height - tolerance) {
                isFullscreen = YES;
                break;
            }
        }
    }
    
    CFRelease(windowList);
    return isFullscreen;
}

#pragma mark - Playback State Evaluation

- (BOOL)shouldPausePlayback {
    if (self.pauseOnBattery && self.isOnBattery) {
        return YES;
    }
    if (self.pauseOnFullscreen && self.isFrontmostAppFullscreen) {
        return YES;
    }
    return NO;
}

- (void)evaluatePlaybackState {
    BOOL shouldPause = self.shouldPausePlayback;
    NSString *reason = @"";
    
    if (shouldPause) {
        if (self.pauseOnBattery && self.isOnBattery) {
            reason = @"On battery power";
        } else if (self.pauseOnFullscreen && self.isFrontmostAppFullscreen) {
            reason = @"Fullscreen app detected";
        }
    }
    
    if ([self.delegate respondsToSelector:@selector(performanceMonitorShouldPausePlayback:reason:)]) {
        [self.delegate performanceMonitorShouldPausePlayback:shouldPause reason:reason];
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
    [self evaluatePlaybackState];
}

@end

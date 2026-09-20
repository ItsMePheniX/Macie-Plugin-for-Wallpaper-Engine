//
//  PerformanceMonitor.h
//  MacieWallpaper - Performance Monitoring
//
//  Created on 2026-02-15.
//

#import <Cocoa/Cocoa.h>

@protocol PerformanceMonitorDelegate <NSObject>

/// Battery power, which is a property of the machine and so stops every display.
- (void)performanceMonitorShouldPausePlayback:(BOOL)shouldPause reason:(NSString *)reason;

@optional
/// The displays now covered by a fullscreen app, as CGDirectDisplayIDs. A display absent
/// from the set is uncovered. Sent as its own callback rather than folded into the verdict
/// above because a fullscreen game on one monitor is no reason to stop the others.
- (void)performanceMonitorCoveredScreensChanged:(NSSet<NSNumber *> *)displayIDs;

@end

@interface PerformanceMonitor : NSObject

@property (nonatomic, weak) id<PerformanceMonitorDelegate> delegate;

// Settings
@property (nonatomic, assign) BOOL pauseOnBattery;
@property (nonatomic, assign) BOOL pauseOnFullscreen;

// State
@property (nonatomic, readonly) BOOL isOnBattery;
/// Displays wholly covered by the frontmost app's windows. Empty when pause-on-fullscreen
/// is off, so a caller can act on it without re-checking the setting.
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *coveredDisplayIDs;
/// Battery only. Fullscreen is reported per display and deliberately not folded in here.
@property (nonatomic, readonly) BOOL shouldPausePlayback;

// Lifecycle
- (void)startMonitoring;
- (void)stopMonitoring;

// Manual check
- (void)evaluatePlaybackState;

@end

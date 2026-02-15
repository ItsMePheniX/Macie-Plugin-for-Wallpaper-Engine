//
//  PerformanceMonitor.h
//  MacieWallpaper - Performance Monitoring
//
//  Created on 2026-02-15.
//

#import <Cocoa/Cocoa.h>

@protocol PerformanceMonitorDelegate <NSObject>
- (void)performanceMonitorShouldPausePlayback:(BOOL)shouldPause reason:(NSString *)reason;
@end

@interface PerformanceMonitor : NSObject

@property (nonatomic, weak) id<PerformanceMonitorDelegate> delegate;

// Settings
@property (nonatomic, assign) BOOL pauseOnBattery;
@property (nonatomic, assign) BOOL pauseOnFullscreen;

// State
@property (nonatomic, readonly) BOOL isOnBattery;
@property (nonatomic, readonly) BOOL isFrontmostAppFullscreen;
@property (nonatomic, readonly) BOOL shouldPausePlayback;

// Lifecycle
- (void)startMonitoring;
- (void)stopMonitoring;

// Manual check
- (void)evaluatePlaybackState;

@end

//
//  AppDelegate.h
//  MacieWallpaper
//
//  Created on 2026-02-14.
//

#import <Cocoa/Cocoa.h>
#import "AVVideoRenderer.h"
#import "PerformanceMonitor.h"

// Forward declaration — keeps C++ headers out of pure .m compilation units.
// AppDelegate.mm imports the full header directly.
@class MacieAssetManagerWrapper;
@class MainWindowController;
@class PreferencesWindowController;

@interface AppDelegate : NSObject <NSApplicationDelegate, PerformanceMonitorDelegate>

@property (strong, nonatomic) NSWindow *desktopWindow;
@property (strong, nonatomic) AVVideoRenderer *videoRenderer;
@property (strong, nonatomic) MainWindowController *galleryController;
@property (strong, nonatomic) PreferencesWindowController *preferencesController;
@property (strong, nonatomic) PerformanceMonitor *performanceMonitor;
@property (strong, nonatomic) MacieAssetManagerWrapper *assetManager;

- (BOOL)selectSteamappsFolder;
- (void)changeSteamappsLocation:(id)sender;
- (void)reloadWallpapers;

@end

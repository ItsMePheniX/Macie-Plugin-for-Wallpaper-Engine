//
//  AppDelegate.h
//  MacieWallpaper
//
//  Created on 2026-02-14.
//

#import <Cocoa/Cocoa.h>
#import "PerformanceMonitor.h"
#import "WallpaperDisplayManager.h"

// Forward declaration — keeps C++ headers out of pure .m compilation units.
// AppDelegate.mm imports the full header directly.
@class MacieAssetManagerWrapper;
@class MainWindowController;
@class WelcomeWindowController;

@interface AppDelegate : NSObject <NSApplicationDelegate, PerformanceMonitorDelegate>

/// Every attached display's wallpaper. Replaces the single desktop window and renderer
/// this class used to own, along with the screen-parameters observer that went with them.
@property (strong, nonatomic) WallpaperDisplayManager *displayManager;
@property (strong, nonatomic) MainWindowController *galleryController;
/// Held strongly for the duration of first-launch setup: NSWindow.windowController
/// is a weak reference, so nothing else keeps this alive while it is on screen.
@property (strong, nonatomic) WelcomeWindowController *welcomeController;
@property (strong, nonatomic) PerformanceMonitor *performanceMonitor;
@property (strong, nonatomic) MacieAssetManagerWrapper *assetManager;

- (BOOL)selectSteamappsFolder;
- (void)changeSteamappsLocation:(id)sender;
- (void)reloadWallpapers;

@end

//
//  MainWindowController.h
//  MacieWallpaper - Main Window Controller
//
//  Created on 2026-02-14.
//

#import <Cocoa/Cocoa.h>

// Forward declarations — keeps C++ headers out of pure .m compilation units.
// MainWindowController.mm imports the full headers directly.
@class MacieAssetManagerWrapper;
@class WallpaperDisplayManager;

@interface MainWindowController : NSWindowController <NSCollectionViewDelegate>

/// Called when the user changes the Steam path from the in-window preferences panel.
/// AppDelegate sets this to trigger a full wallpaper reload.
@property (copy, nonatomic, nullable) void (^onWallpapersReloadRequested)(void);

<<<<<<< HEAD
/// `manager` is required and already knows every attached display, so there is no
/// attach-it-later step: it outlives this window and exists before it. What it does not
/// have yet is the library, which arrives separately through -reloadFromAssetManager.
- (nonnull instancetype)initWithAssetManager:(nonnull MacieAssetManagerWrapper *)assetManager
                              displayManager:(nonnull WallpaperDisplayManager *)manager;

/// A display was plugged in, pulled out or reordered: rebuilds the target picker and
/// re-marks whatever the current target is now showing.
- (void)displaysChanged;

#pragma mark - Library scanning

// The scan runs on a background queue so the window can open immediately. These
// three calls are how AppDelegate drives the grid through it.

/// Puts the grid into its scanning state. Safe to call before the window is shown,
/// and safe to call again if a second scan starts.
- (void)beginScanProgress;

/// Feeds the scanning state new counts. `total` of 0 shows an indeterminate spinner.
- (void)updateScanProgress:(NSUInteger)scanned total:(NSUInteger)total;

/// Leaves the scanning state and rebuilds the gallery from the asset manager.
- (void)reloadFromAssetManager;
=======
- (nonnull instancetype)initWithAssetManager:(nonnull MacieAssetManagerWrapper *)assetManager
                               videoRenderer:(nonnull AVVideoRenderer *)renderer;
>>>>>>> origin/main

/// The app's settings live in this window's own sheet; the AppDelegate's Cmd+,
/// handler routes here rather than opening a second settings surface.
- (void)showSettingsSheet:(nullable id)sender;

#pragma mark - Menu actions

// The menu bar sends these with target nil so they travel the responder chain to
// whichever gallery window is in front. Declared here so the selectors AppDelegate
// installs are checkable rather than string-matched at runtime.

/// ⌘F — moves keyboard focus to the gallery's search field.
- (void)focusSearchField:(nullable id)sender;
/// ⌘] — applies the wallpaper after the current one in the visible order.
- (void)nextWallpaper:(nullable id)sender;
/// ⌘[ — applies the wallpaper before the current one in the visible order.
- (void)prevWallpaper:(nullable id)sender;
/// ⌘R — applies a random wallpaper from whatever the gallery is showing.
- (void)playRandomWallpaper:(nullable id)sender;
/// ⇧⌘M — mutes or unmutes the desktop wallpaper's audio.
- (void)toolbarToggleMute:(nullable id)sender;

@end

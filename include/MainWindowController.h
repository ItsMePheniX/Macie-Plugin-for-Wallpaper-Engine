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
@class AVVideoRenderer;

@interface MainWindowController : NSWindowController <NSCollectionViewDelegate>

/// Called when the user changes the Steam path from the in-window preferences panel.
/// AppDelegate sets this to trigger a full wallpaper reload.
@property (copy, nonatomic, nullable) void (^onWallpapersReloadRequested)(void);

- (nonnull instancetype)initWithAssetManager:(nonnull MacieAssetManagerWrapper *)assetManager
                               videoRenderer:(nonnull AVVideoRenderer *)renderer;

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

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

@end

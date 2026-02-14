//
//  AppDelegate.h
//  MacieWallpaper
//
//  Created on 2026-02-14.
//

#import <Cocoa/Cocoa.h>
#import "AVVideoRenderer.h"

@class MainWindowController;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong, nonatomic) NSWindow *desktopWindow;
@property (strong, nonatomic) AVVideoRenderer *videoRenderer;
@property (strong, nonatomic) MainWindowController *galleryController;
@property (nonatomic) void *assetManager; // Opaque pointer to C++ object

@end

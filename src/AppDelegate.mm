//
//  AppDelegate.m
//  MacieWallpaper
//
//  Created on 2026-02-14.
//

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "AssetManager.hpp"
#import <vector>

@implementation AppDelegate

- (Macie::AssetManager *)assetManagerCpp {
    return static_cast<Macie::AssetManager *>(self.assetManager);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"MacieWallpaper Started");
    NSLog(@"macOS Version: %@", [[NSProcessInfo processInfo] operatingSystemVersionString]);
    NSLog(@"");
    
    self.assetManager = new Macie::AssetManager();
    [self scanWallpaperEngineVideos];
    [self createDesktopWindow];
    [self playFirstAvailableVideo];
}

- (void)scanWallpaperEngineVideos {
    NSLog(@"Scanning for Wallpaper Engine videos...");
    
    std::string steamappsPath = "/Users/macie/steamapps";
    std::vector<Macie::WallpaperProject> wallpapers = [self assetManagerCpp]->scanWallpaperEngine(steamappsPath);
    
    NSLog(@"Found %lu video wallpapers", wallpapers.size());
    NSLog(@"");
}

- (void)createDesktopWindow {
    NSScreen *mainScreen = [NSScreen mainScreen];
    
    self.desktopWindow = [[NSWindow alloc] initWithContentRect:mainScreen.frame
                                                      styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    
    self.desktopWindow.backgroundColor = [NSColor clearColor];
    self.desktopWindow.opaque = NO;
    
    // Set window level below desktop icons
    self.desktopWindow.level = kCGDesktopWindowLevel - 1;
    
    self.desktopWindow.collectionBehavior = NSWindowCollectionBehaviorStationary |
                                             NSWindowCollectionBehaviorCanJoinAllSpaces |
                                             NSWindowCollectionBehaviorIgnoresCycle;
    
    self.desktopWindow.ignoresMouseEvents = YES;
    [self.desktopWindow orderBack:nil];
    
    NSLog(@"Desktop window created");
    NSLog(@"  Window Level: %ld", (long)self.desktopWindow.level);
    NSLog(@"  Frame: %@", NSStringFromRect(self.desktopWindow.frame));
    NSLog(@"");
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
}

- (void)playFirstAvailableVideo {
    std::vector<Macie::WallpaperProject> wallpapers = [self assetManagerCpp]->getVideoWallpapers();
    
    if (wallpapers.empty()) {
        NSLog(@"WARNING: No video wallpapers found");
        NSLog(@"  Check path: /Users/macie/steamapps/workshop/content/431960/");
        return;
    }
    
    Macie::WallpaperProject firstVideo = wallpapers[0];
    NSString *videoPath = [NSString stringWithUTF8String:firstVideo.videoFilePath.c_str()];
    NSString *title = [NSString stringWithUTF8String:firstVideo.title.c_str()];
    
    NSLog(@"Loading wallpaper: %@", title);
    NSLog(@"  Path: %@", videoPath);
    
    self.videoRenderer = [[AVVideoRenderer alloc] initWithWindow:self.desktopWindow];
    BOOL success = [self.videoRenderer loadAndPlayVideo:videoPath];
    
    if (success) {
        NSLog(@"Video wallpaper is now playing");
        NSLog(@"");
        NSLog(@"TIP: Desktop icons should still be clickable. Press Cmd+Q to quit.");
        [self showGallery];
    } else {
        NSLog(@"ERROR: Failed to load video wallpaper");
    }
    
    NSLog(@"");
}

- (void)showGallery {
    if (!self.galleryController) {
        self.galleryController = [[MainWindowController alloc] initWithAssetManager:self.assetManager
                                                                      videoRenderer:self.videoRenderer];
    }
    [self.galleryController showWindow:nil];
    [self.galleryController.window makeKeyAndOrderFront:nil];
    NSLog(@"Gallery window opened");
}

- (void)screenParametersChanged:(NSNotification *)notification {
    NSLog(@"Screen parameters changed - restoring window level");
    self.desktopWindow.level = kCGDesktopWindowLevel - 1;
    [self.desktopWindow orderBack:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    NSLog(@"MacieWallpaper Terminating");
    
    if (self.videoRenderer) {
        [self.videoRenderer stop];
        self.videoRenderer = nil;
    }
    
    if (self.desktopWindow) {
        [self.desktopWindow close];
        self.desktopWindow = nil;
    }
    
    if (self.assetManager) {
        delete [self assetManagerCpp];
        self.assetManager = nullptr;
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end

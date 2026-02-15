//
//  AppDelegate.mm
//  MacieWallpaper - Application Delegate
//
//  Created on 2026-02-14.
//

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "WelcomeWindowController.h"
#import "PreferencesWindowController.h"
#import "PerformanceMonitor.h"
#import "ThumbnailCache.h"
#import "AssetManager.hpp"
#import "Constants.h"
#import <vector>

@implementation AppDelegate

- (Macie::AssetManager *)assetManagerCpp {
    return static_cast<Macie::AssetManager *>(self.assetManager);
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"MacieWallpaper Started (macOS %@)", [[NSProcessInfo processInfo] operatingSystemVersionString]);
    
    self.assetManager = new Macie::AssetManager();
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedPath = [defaults stringForKey:@"steamappsPath"];
    
    if (!savedPath || ![[NSFileManager defaultManager] fileExistsAtPath:savedPath]) {
        NSLog(@"No valid steamapps path found. Showing welcome window...");
        
        WelcomeWindowController *welcomeController = [[WelcomeWindowController alloc] initWithCompletionHandler:^(NSString *selectedPath) {
            NSLog(@"User selected path: %@", selectedPath);
            [self scanWallpaperEngineVideos];
            [self createDesktopWindow];
            [self playFirstAvailableVideo];
            [self setupMenuBar];
            [self setupPerformanceMonitor];
        }];
        
        [welcomeController showWindow:nil];
        return;
    }
    
    [self scanWallpaperEngineVideos];
    [self createDesktopWindow];
    [self playFirstAvailableVideo];
    [self setupMenuBar];
    [self setupPerformanceMonitor];
}

- (void)scanWallpaperEngineVideos {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *steamappsPath = [defaults stringForKey:@"steamappsPath"];
    
    if (!steamappsPath) {
        NSLog(@"ERROR: No steamapps path configured");
        return;
    }
    
    std::string pathString = [steamappsPath UTF8String];
    std::vector<Macie::WallpaperProject> wallpapers = [self assetManagerCpp]->scanWallpaperEngine(pathString);
    
    NSLog(@"Found %lu video wallpapers", wallpapers.size());
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
}

- (void)playFirstAvailableVideo {
    std::vector<Macie::WallpaperProject> wallpapers = [self assetManagerCpp]->getVideoWallpapers();
    
    if (wallpapers.empty()) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *steamPath = [defaults stringForKey:@"steamappsPath"];
        NSLog(@"WARNING: No video wallpapers found");
        NSLog(@"  Check path: %@/workshop/content/431960/", steamPath ?: @"(not configured)");
        return;
    }
    
    Macie::WallpaperProject firstVideo = wallpapers[0];
    NSString *videoPath = [NSString stringWithUTF8String:firstVideo.videoFilePath.c_str()];
    NSString *title = [NSString stringWithUTF8String:firstVideo.title.c_str()];
    
    NSLog(@"Loading wallpaper: %@", title);
    
    self.videoRenderer = [[AVVideoRenderer alloc] initWithWindow:self.desktopWindow];
    BOOL success = [self.videoRenderer loadAndPlayVideo:videoPath];
    
    if (success) {
        // Restore mute state from previous session
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        BOOL hasStoredState = [defaults objectForKey:@"lastMuteState"] != nil;
        BOOL lastMuteState = hasStoredState ? [defaults boolForKey:@"lastMuteState"] : YES;
        
        if (!lastMuteState) {
            [self.videoRenderer unmute];
        }
        
        [self showGallery];
    } else {
        NSLog(@"ERROR: Failed to load video wallpaper");
    }
}

- (void)showGallery {
    if (!self.galleryController) {
        self.galleryController = [[MainWindowController alloc] initWithAssetManager:self.assetManager
                                                                      videoRenderer:self.videoRenderer];
    }
    [self.galleryController showWindow:nil];
    [self.galleryController.window makeKeyAndOrderFront:nil];
}

- (void)setupPerformanceMonitor {
    self.performanceMonitor = [[PerformanceMonitor alloc] init];
    self.performanceMonitor.delegate = self;
    [self.performanceMonitor startMonitoring];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(performanceSettingsChanged:)
                                                 name:@"PerformanceSettingsChanged"
                                               object:nil];
}

- (void)performanceSettingsChanged:(NSNotification *)notification {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.performanceMonitor.pauseOnBattery = [defaults boolForKey:kDefaultsPauseOnBattery];
    self.performanceMonitor.pauseOnFullscreen = [defaults boolForKey:kDefaultsPauseOnFullscreen];
    [self.performanceMonitor evaluatePlaybackState];
}

#pragma mark - PerformanceMonitorDelegate

- (void)performanceMonitorShouldPausePlayback:(BOOL)shouldPause reason:(NSString *)reason {
    if (shouldPause) {
        [self.videoRenderer pause];
    } else {
        [self.videoRenderer play];
    }
}

- (void)screenParametersChanged:(NSNotification *)notification {
    self.desktopWindow.level = kCGDesktopWindowLevel - 1;
    [self.desktopWindow orderBack:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Stop performance monitoring
    if (self.performanceMonitor) {
        [self.performanceMonitor stopMonitoring];
        self.performanceMonitor = nil;
    }
    
    // Remove notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
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

- (BOOL)selectSteamappsFolder {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Select Steamapps Folder";
    panel.message = @"Please locate your steamapps folder (usually in Steam installation directory)";
    panel.prompt = @"Select";
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = NO;
    
    if ([panel runModal] == NSModalResponseOK) {
        NSURL *selectedURL = panel.URL;
        NSString *selectedPath = selectedURL.path;
        
        NSString *workshopPath = [selectedPath stringByAppendingPathComponent:@"workshop/content/431960"];
        BOOL isDirectory;
        BOOL workshopExists = [[NSFileManager defaultManager] fileExistsAtPath:workshopPath isDirectory:&isDirectory];
        
        if (!workshopExists || !isDirectory) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Invalid Folder";
            alert.informativeText = @"Selected folder does not contain Wallpaper Engine workshop content.\n\nPlease select the 'steamapps' folder that contains: workshop/content/431960/";
            alert.alertStyle = NSAlertStyleWarning;
            [alert addButtonWithTitle:@"Try Again"];
            [alert addButtonWithTitle:@"Cancel"];
            
            NSModalResponse response = [alert runModal];
            if (response == NSAlertFirstButtonReturn) {
                return [self selectSteamappsFolder];
            }
            return NO;
        }
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:selectedPath forKey:@"steamappsPath"];
        [defaults synchronize];
        
        return YES;
    }
    
    return NO;
}

- (void)changeSteamappsLocation:(id)sender {
    if ([self selectSteamappsFolder]) {
        delete [self assetManagerCpp];
        self.assetManager = new Macie::AssetManager();
        
        [self scanWallpaperEngineVideos];
        
        if (self.galleryController) {
            [self.galleryController.window close];
            self.galleryController = nil;
        }
        
        [self playFirstAvailableVideo];
    }
}

- (void)setupMenuBar {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu) {
        mainMenu = [[NSMenu alloc] init];
        [NSApp setMainMenu:mainMenu];
    }
    
    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [appMenuItem setSubmenu:appMenu];
    
    [appMenu addItemWithTitle:@"Preferences..." 
                       action:@selector(showPreferences:) 
                keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Change Wallpaper Location..." 
                       action:@selector(changeSteamappsLocation:) 
                keyEquivalent:@"l"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit" 
                       action:@selector(terminate:) 
                keyEquivalent:@"q"];
    
    [mainMenu insertItem:appMenuItem atIndex:0];
}

- (void)showPreferences:(id)sender {
    if (!self.preferencesController) {
        self.preferencesController = [[PreferencesWindowController alloc] init];
        
        __weak typeof(self) weakSelf = self;
        self.preferencesController.onPathChanged = ^{
            [weakSelf reloadWallpapers];
        };
    }
    
    [self.preferencesController showWindow:nil];
    [self.preferencesController.window makeKeyAndOrderFront:nil];
}

- (void)reloadWallpapers {
    delete [self assetManagerCpp];
    self.assetManager = new Macie::AssetManager();
    
    [self scanWallpaperEngineVideos];
    
    if (self.galleryController) {
        [self.galleryController.window close];
        self.galleryController = nil;
    }
    
    [self playFirstAvailableVideo];
}

@end

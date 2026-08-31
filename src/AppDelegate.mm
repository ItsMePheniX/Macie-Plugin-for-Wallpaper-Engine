//
//  AppDelegate.mm
//  MacieWallpaper - Application Delegate
//
//  Created on 2026-02-14.
//

#import "AppDelegate.h"
#import "MainWindowController.h"
#import "WelcomeWindowController.h"
#import "PerformanceMonitor.h"
#import "MacieAssetManagerWrapper.h"
#import "LastWallpaperSnapshot.h"
#import "Constants.h"
#import <vector>

@interface AppDelegate ()

/// Bumped by every -beginWallpaperScan. Progress and results from a superseded scan
/// are dropped, so changing the Steam folder mid-scan cannot leave the gallery
/// showing the previous folder's library.
@property (assign, nonatomic) NSUInteger scanGeneration;
/// YES while a scan is running. The gallery may be built during one and has to enter
/// its scanning state rather than announcing an empty library.
@property (assign, nonatomic) BOOL scanInFlight;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSLog(@"MacieWallpaper Started (macOS %@)", [[NSProcessInfo processInfo] operatingSystemVersionString]);

    // The menu bar is built first so that Edit-menu shortcuts (copy/paste in the
    // search field) work regardless of which setup path runs below.
    [self setupMenuBar];

    self.assetManager = [[MacieAssetManagerWrapper alloc] init];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedPath = [defaults stringForKey:kDefaultsSteamappsPath];

    if (!savedPath || ![[NSFileManager defaultManager] fileExistsAtPath:savedPath]) {
        NSLog(@"No valid steamapps path found. Showing welcome window...");
        [self showWelcomeWindow];
        return;
    }

    [self startWithConfiguredPath];
}

/// Everything that needs a valid steamapps path. Shared by the normal launch
/// path and by first-launch completion.
///
/// Nothing here waits for the library. The desktop window, the previous session's
/// wallpaper and the gallery window are all on screen before the scan that used to
/// block them has finished — on a large library that was seconds of a bouncing Dock
/// icon and no window at all.
- (void)startWithConfiguredPath {
    [self createDesktopWindow];
    [self restoreLastWallpaperFromSnapshot];
    [self beginWallpaperScan];
    [self showGallery];
    [self setupPerformanceMonitor];
}

- (void)showWelcomeWindow {
    __weak typeof(self) weakSelf = self;

    // Retained by self.welcomeController: NSWindow.windowController is weak, so
    // without this the controller would deallocate before the user can click Browse.
    self.welcomeController = [[WelcomeWindowController alloc] initWithCompletionHandler:^(NSString *selectedPath) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSLog(@"User selected path: %@", selectedPath);
        strongSelf.welcomeController = nil;
        [strongSelf startWithConfiguredPath];
    }];

    [self.welcomeController showWindow:nil];
    [self.welcomeController.window makeKeyAndOrderFront:nil];
}

#pragma mark - Library scanning

/// Scans on a background queue and drives the gallery's progress state from it. The
/// window is already up by the time this runs, so a slow library reads as work in
/// progress instead of a hang.
- (void)beginWallpaperScan {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *steamappsPath = [defaults stringForKey:kDefaultsSteamappsPath];

    if (!steamappsPath) {
        NSLog(@"ERROR: No steamapps path configured");
        return;
    }

    self.scanGeneration++;
    const NSUInteger generation = self.scanGeneration;
    self.scanInFlight = YES;

    // Covers a rescan, where the gallery already exists. At launch it does not yet,
    // and -showGallery puts it into the scanning state as it builds it.
    [self.galleryController beginScanProgress];

    std::string pathString = [steamappsPath UTF8String];
    __weak AppDelegate *weakSelf = self;

    [self.assetManager scanWallpaperEngineAsync:pathString
        progress:^(NSUInteger scanned, NSUInteger total) {
            AppDelegate *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.scanGeneration != generation) return;
            [strongSelf.galleryController updateScanProgress:scanned total:total];
        }
        completion:^{
            AppDelegate *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.scanGeneration != generation) return;
            [strongSelf finishWallpaperScan];
        }];
}

- (void)finishWallpaperScan {
    self.scanInFlight = NO;

    // Playback is settled before the grid reloads: -reloadFromAssetManager reads the
    // playing wallpaper's id out of NSUserDefaults, so choosing a wallpaper after it
    // would leave the hero and the cards marking the wrong one.
    if (!self.videoRenderer || ![self playingWallpaperStillInstalled]) {
        [self playFirstAvailableVideo];
    }

    [self.galleryController reloadFromAssetManager];
}

/// Whether the wallpaper the app thinks is playing is still in the library. A folder
/// change or an unsubscribe can take it away underneath us.
- (BOOL)playingWallpaperStillInstalled {
    NSString *playingId = [[NSUserDefaults standardUserDefaults]
        stringForKey:kDefaultsLastWallpaperId];
    if (!playingId.length) return NO;

    std::string idString = [playingId UTF8String];
    return [self.assetManager getWallpaperById:idString].has_value();
}

/// Puts the previous session's wallpaper straight back on the desktop. The library
/// scan is what normally supplies a wallpaper's video path, which is why this used to
/// have to wait for it; the snapshot carries the path instead.
///
/// Leaves videoRenderer nil on any failure, which is the signal -finishWallpaperScan
/// uses to pick a wallpaper from the real library instead.
- (void)restoreLastWallpaperFromSnapshot {
    NSDictionary *snapshot = MacieLoadLastWallpaperSnapshot();
    NSString *path = snapshot[@"path"];
    if (!path.length) return;

    AVVideoRenderer *renderer = [[AVVideoRenderer alloc] initWithWindow:self.desktopWindow];
    if (![renderer loadAndPlayVideo:path]) {
        NSLog(@"Could not restore last wallpaper before scan: %@", path);
        return;
    }

    self.videoRenderer = renderer;
    [self restoreMuteState];
    NSLog(@"Restored last wallpaper before scan: %@", snapshot[@"title"]);
}

/// The renderer starts muted, so this only ever has to undo that. Shared by the
/// snapshot restore and the post-scan path so the two cannot drift.
- (void)restoreMuteState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasStoredState = [defaults objectForKey:kDefaultsLastMuteState] != nil;
    BOOL lastMuteState  = hasStoredState ? [defaults boolForKey:kDefaultsLastMuteState] : YES;

    if (!lastMuteState) [self.videoRenderer unmute];
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

/// Chooses and starts a wallpaper from the scanned library. Only reached when the
/// snapshot could not supply one — a first run, or a wallpaper that is no longer
/// installed.
- (void)playFirstAvailableVideo {
    std::vector<Macie::WallpaperProject> wallpapers = [self.assetManager getVideoWallpapers];

    if (wallpapers.empty()) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *steamPath = [defaults stringForKey:kDefaultsSteamappsPath];
        NSLog(@"WARNING: No video wallpapers found");
        NSLog(@"  Check path: %@/workshop/content/431960/", steamPath ?: @"(not configured)");
        return;
    }

    // Restore the wallpaper that was playing in the previous session.
    // Falls back to wallpapers[0] if no ID was saved or the saved ID is no longer present.
    Macie::WallpaperProject wallpaperToPlay = wallpapers[0];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedId = [defaults stringForKey:kDefaultsLastWallpaperId];

    if (savedId.length > 0) {
        std::string savedIdStr = [savedId UTF8String];
        auto found = [self.assetManager getWallpaperById:savedIdStr];
        if (found.has_value()) {
            wallpaperToPlay = found.value();
            NSLog(@"Restoring last wallpaper: %s", wallpaperToPlay.title.c_str());
        } else {
            NSLog(@"Last wallpaper ID '%@' not found in library, falling back to first", savedId);
        }
    }

    // stringWithUTF8String: returns nil on malformed bytes, and a nil in a dictionary
    // literal is fatal, so each one is defaulted.
    NSString *videoPath   = [NSString stringWithUTF8String:wallpaperToPlay.videoFilePath.c_str()] ?: @"";
    NSString *title       = [NSString stringWithUTF8String:wallpaperToPlay.title.c_str()]         ?: @"";
    NSString *wallpaperId = [NSString stringWithUTF8String:wallpaperToPlay.id.c_str()]            ?: @"";
    NSString *previewPath = [NSString stringWithUTF8String:wallpaperToPlay.previewPath.c_str()]   ?: @"";
    NSString *description = [NSString stringWithUTF8String:wallpaperToPlay.description.c_str()]   ?: @"";

    NSLog(@"Loading wallpaper: %@", title);

    // Reused when the snapshot restore already built one: a second renderer would
    // leave the first one's layer in the desktop window.
    if (!self.videoRenderer) {
        self.videoRenderer = [[AVVideoRenderer alloc] initWithWindow:self.desktopWindow];
    }
    BOOL success = [self.videoRenderer loadAndPlayVideo:videoPath];

    if (success) {
        // Record which wallpaper is now playing (covers the first-launch case where no ID was saved)
        [defaults setObject:wallpaperId forKey:kDefaultsLastWallpaperId];
        MacieSaveLastWallpaperSnapshot(@{
            @"id":          wallpaperId,
            @"title":       title,
            @"path":        videoPath,
            @"preview":     previewPath,
            @"description": description
        });

        [self restoreMuteState];

        // The gallery may have been built before a renderer existed.
        [self.galleryController attachVideoRenderer:self.videoRenderer];
    } else {
        NSLog(@"ERROR: Failed to load video wallpaper");
    }
}

- (void)showGallery {
    if (!self.galleryController) {
        self.galleryController = [[MainWindowController alloc] initWithAssetManager:self.assetManager
                                                                      videoRenderer:self.videoRenderer];

        // Typed callback — replaces the unsafe performSelector pattern
        __weak typeof(self) weakSelf = self;
        self.galleryController.onWallpapersReloadRequested = ^{
            [weakSelf reloadWallpapers];
        };

        // At launch the gallery is always built during a scan, and it has to report
        // that rather than announcing an empty library.
        if (self.scanInFlight) [self.galleryController beginScanProgress];
    }
    [self.galleryController showWindow:nil];
    [self.galleryController.window makeKeyAndOrderFront:nil];
}

/// Menu-action form of -showGallery. Menu items invoke their action with the item
/// as the argument, so the selector has to take a sender.
- (void)showGalleryWindow:(id)sender {
    [self showGallery];
}

- (void)setupPerformanceMonitor {
    self.performanceMonitor = [[PerformanceMonitor alloc] init];
    self.performanceMonitor.delegate = self;
    [self.performanceMonitor startMonitoring];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(performanceSettingsChanged:)
                                                 name:kNotificationPerformanceSettingsChanged
                                               object:nil];

    // Sleep/wake observers must be registered on the workspace notification center,
    // not NSNotificationCenter.defaultCenter.
    NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

    [workspaceCenter addObserver:self
                        selector:@selector(systemWillSleep:)
                            name:NSWorkspaceWillSleepNotification
                          object:nil];

    [workspaceCenter addObserver:self
                        selector:@selector(systemDidWake:)
                            name:NSWorkspaceDidWakeNotification
                          object:nil];
}

- (void)performanceSettingsChanged:(NSNotification *)notification {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.performanceMonitor.pauseOnBattery = [defaults boolForKey:kDefaultsPauseOnBattery];
    self.performanceMonitor.pauseOnFullscreen = [defaults boolForKey:kDefaultsPauseOnFullscreen];
    [self.performanceMonitor evaluatePlaybackState];
}

#pragma mark - Sleep / Wake

- (void)systemWillSleep:(NSNotification *)notification {
    // Pause immediately — sleep overrides all other playback state.
    if (self.videoRenderer) {
        NSLog(@"System going to sleep — pausing wallpaper");
        [self.videoRenderer pause];
    }
}

- (void)systemDidWake:(NSNotification *)notification {
    // Re-evaluate rather than blindly resuming — if pause-on-battery is on and the
    // Mac woke on battery power, the wallpaper should stay paused.
    if (self.videoRenderer && self.performanceMonitor) {
        NSLog(@"System woke — re-evaluating playback state");
        [self.performanceMonitor evaluatePlaybackState];
    }
}

#pragma mark - PerformanceMonitorDelegate

- (void)performanceMonitorShouldPausePlayback:(BOOL)shouldPause reason:(NSString *)reason {
    if (shouldPause) {
        [self.videoRenderer pause];
    } else {
        [self.videoRenderer play];
    }
}

/// The desktop window must track the screen it lives on: a resolution change or
/// a display swap leaves the old frame behind, showing the wallpaper at the wrong
/// size (or off-screen entirely).
- (void)screenParametersChanged:(NSNotification *)notification {
    NSScreen *mainScreen = [NSScreen mainScreen];
    if (!self.desktopWindow || !mainScreen) return;

    [self.desktopWindow setFrame:mainScreen.frame display:YES];
    self.desktopWindow.level = kCGDesktopWindowLevel - 1;
    [self.desktopWindow orderBack:nil];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Stop performance monitoring
    if (self.performanceMonitor) {
        [self.performanceMonitor stopMonitoring];
        self.performanceMonitor = nil;
    }

    // Remove observers from both notification centers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

    if (self.videoRenderer) {
        [self.videoRenderer stop];
        self.videoRenderer = nil;
    }

    if (self.desktopWindow) {
        [self.desktopWindow close];
        self.desktopWindow = nil;
    }

    // assetManager is a strong Obj-C property — ARC releases it automatically,
    // which triggers unique_ptr destructor inside MacieAssetManagerWrapper.
    self.assetManager = nil;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

/// Closing the gallery leaves the app running so the wallpaper keeps playing;
/// clicking the Dock icon has to be able to bring the window back.
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (flag) return YES;

    if (self.welcomeController) {
        [self.welcomeController.window makeKeyAndOrderFront:nil];
    } else if (self.videoRenderer) {
        [self showGallery];
    }
    return YES;
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

        NSString *workshopPath = [selectedPath stringByAppendingPathComponent:kWorkshopSubpath];
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
        [defaults setObject:selectedPath forKey:kDefaultsSteamappsPath];

        return YES;
    }

    return NO;
}

- (void)changeSteamappsLocation:(id)sender {
    if ([self selectSteamappsFolder]) {
        [self reloadWallpapers];
    }
}

- (void)reloadWallpapers {
    // Reached before setup ever ran: the user opened Cmd+, from the welcome window and
    // picked a folder there. There is nothing to reload, so this is a first start.
    if (!self.desktopWindow) {
        self.welcomeController = nil;
        [self startWithConfiguredPath];
        return;
    }

    // The asset manager is kept, not replaced: -adoptWallpapers swaps the whole list
    // at once so nothing from the previous folder can survive, and the gallery holds
    // its own reference to this instance. The wrapper drops a superseded scan's
    // results itself, so a second reload cannot be overtaken by the first.
    //
    // The window also stays open and re-enters its scanning state. Closing and
    // rebuilding it was only ever a way to force a reload.
    [self beginWallpaperScan];
}

#pragma mark - Menu Bar

- (void)setupMenuBar {
    // This app has no nib, so NSApp.mainMenu starts out nil and every menu —
    // including the standard Edit menu that gives the search field its
    // copy/paste/select-all shortcuts — has to be built by hand.
    NSMenu *mainMenu = [[NSMenu alloc] init];

    [mainMenu addItem:[self buildAppMenuItem]];
    [mainMenu addItem:[self buildEditMenuItem]];
    [mainMenu addItem:[self buildWallpaperMenuItem]];
    [mainMenu addItem:[self buildWindowMenuItem]];

    [NSApp setMainMenu:mainMenu];
}

- (NSMenuItem *)buildAppMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:kAppName];

    [menu addItemWithTitle:[NSString stringWithFormat:@"About %@", kAppName]
                    action:@selector(orderFrontStandardAboutPanel:)
             keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Settings..."
                    action:@selector(showPreferences:)
             keyEquivalent:@","];
    [menu addItemWithTitle:@"Change Wallpaper Location..."
                    action:@selector(changeSteamappsLocation:)
             keyEquivalent:@"l"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:[NSString stringWithFormat:@"Hide %@", kAppName]
                    action:@selector(hide:)
             keyEquivalent:@"h"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:[NSString stringWithFormat:@"Quit %@", kAppName]
                    action:@selector(terminate:)
             keyEquivalent:@"q"];

    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.submenu = menu;
    return item;
}

- (NSMenuItem *)buildEditMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Edit"];

    [menu addItemWithTitle:@"Undo"  action:@selector(undo:)  keyEquivalent:@"z"];
    NSMenuItem *redo = [menu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Cut"        action:@selector(cut:)        keyEquivalent:@"x"];
    [menu addItemWithTitle:@"Copy"       action:@selector(copy:)       keyEquivalent:@"c"];
    [menu addItemWithTitle:@"Paste"      action:@selector(paste:)      keyEquivalent:@"v"];
    [menu addItemWithTitle:@"Delete"     action:@selector(delete:)     keyEquivalent:@""];
    [menu addItemWithTitle:@"Select All" action:@selector(selectAll:)  keyEquivalent:@"a"];
    [menu addItem:[NSMenuItem separatorItem]];

    // Targets nil so it travels the responder chain to whichever gallery window is
    // in front, the same way the Wallpaper menu's items do.
    [[menu addItemWithTitle:@"Find"
                     action:@selector(focusSearchField:)
              keyEquivalent:@"f"] setTarget:nil];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    item.submenu = menu;
    return item;
}

/// Playback shortcuts. These target nil so they travel the responder chain and
/// reach MainWindowController while the gallery is the key window.
- (NSMenuItem *)buildWallpaperMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Wallpaper"];

    [[menu addItemWithTitle:@"Next Wallpaper"
                     action:@selector(nextWallpaper:)
              keyEquivalent:@"]"] setTarget:nil];
    [[menu addItemWithTitle:@"Previous Wallpaper"
                     action:@selector(prevWallpaper:)
              keyEquivalent:@"["] setTarget:nil];
    [[menu addItemWithTitle:@"Random Wallpaper"
                     action:@selector(playRandomWallpaper:)
              keyEquivalent:@"r"] setTarget:nil];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *mute = [menu addItemWithTitle:@"Toggle Mute"
                                       action:@selector(toolbarToggleMute:)
                                keyEquivalent:@"m"];
    mute.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    mute.target = nil;

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Wallpaper" action:NULL keyEquivalent:@""];
    item.submenu = menu;
    return item;
}

- (NSMenuItem *)buildWindowMenuItem {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Window"];

    [menu addItemWithTitle:@"Wallpaper Gallery"
                    action:@selector(showGalleryWindow:)
             keyEquivalent:@"0"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [menu addItemWithTitle:@"Zoom"     action:@selector(performZoom:)        keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Window" action:NULL keyEquivalent:@""];
    item.submenu = menu;

    [NSApp setWindowsMenu:menu];
    return item;
}

/// Cmd+, — the settings live in the gallery window's own sheet, so make sure the
/// gallery is on screen and hand off to it.
- (void)showPreferences:(id)sender {
    if (!self.galleryController && !self.videoRenderer) {
        // No library loaded yet, so there is no gallery to host the sheet — the
        // only setting that can meaningfully change at this point is the location.
        [self changeSteamappsLocation:sender];
        return;
    }

    [self showGallery];
    [self.galleryController showSettingsSheet:sender];
}

@end


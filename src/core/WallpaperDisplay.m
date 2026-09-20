//
//  WallpaperDisplay.m
//  MacieWallpaper - One screen's wallpaper
//
//  Created on 2026-09-01.
//

#import "WallpaperDisplay.h"
#import "MacieDisplayIdentity.h"

@interface WallpaperDisplay ()

@property (strong, nonatomic, nullable) NSWindow *window;
@property (strong, nonatomic, nullable) AVVideoRenderer *renderer;

@property (copy, nonatomic, nullable) NSString *displayKey;
@property (assign, nonatomic) CGDirectDisplayID displayID;
@property (copy, nonatomic) NSString *name;
@property (copy, nonatomic, nullable) NSString *wallpaperId;

/// The mute the user asked for, which is not always the mute in effect: a display that
/// carries no audio stays silent while still remembering what was requested, so handing
/// it the audio later does the right thing without being told twice.
@property (assign, nonatomic) BOOL desiredMute;

@property (assign, nonatomic) BOOL globallyPaused;
@property (assign, nonatomic) BOOL covered;

@end

@implementation WallpaperDisplay

- (instancetype)initWithScreen:(NSScreen *)screen {
    self = [super init];
    if (!self) return nil;

    _displayKey  = MacieDisplayKeyForScreen(screen);
    _displayID   = MacieDisplayIDForScreen(screen);
    _name        = MacieDisplayNameForScreen(screen);
    _desiredMute = YES;

    _window = [self buildWindowForScreen:screen];

    // Safe to build before there is anything to play: -initWithWindow: attaches no
    // layer, so an unused renderer leaves nothing behind in the window.
    _renderer = [[AVVideoRenderer alloc] initWithWindow:_window];

    return self;
}

/// Moved from AppDelegate -createDesktopWindow. The only change is that the frame comes
/// from the screen this display was handed rather than from mainScreen, which is "screen
/// with key window" and so followed the gallery around.
- (NSWindow *)buildWindowForScreen:(NSScreen *)screen {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:screen.frame
                                                  styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];

    window.backgroundColor = [NSColor clearColor];
    window.opaque = NO;

    // Below the desktop icons.
    window.level = kCGDesktopWindowLevel - 1;

    window.collectionBehavior = NSWindowCollectionBehaviorStationary |
                                NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorIgnoresCycle;

    window.ignoresMouseEvents = YES;
    [window orderBack:nil];

    return window;
}

#pragma mark - Wallpaper

- (BOOL)loadWallpaper:(NSDictionary *)video {
    if (!self.window || !self.renderer) return NO;

    NSString *path = video[@"path"];
    NSString *videoId = video[@"id"];
    if (![path isKindOfClass:[NSString class]] || !path.length) return NO;

    if (![self.renderer loadAndPlayVideo:path]) {
        NSLog(@"Display '%@' could not load wallpaper: %@", self.name, path);
        return NO;
    }

    self.wallpaperId = [videoId isKindOfClass:[NSString class]] ? videoId : nil;

    // Loading starts playback, which is wrong if this display is asleep or covered, and
    // the renderer's mute survives a load but this display's audio rights may not.
    [self applyAudio];
    [self applyPlayback];

    return YES;
}

- (void)followScreen:(NSScreen *)screen {
    if (!self.window) return;

    // A reconnect can renumber the display even though it is the same panel.
    self.displayID = MacieDisplayIDForScreen(screen);
    self.name      = MacieDisplayNameForScreen(screen);

    [self.window setFrame:screen.frame display:YES];

    // Re-asserted because a screen change can leave the window ordered above the
    // desktop icons again.
    self.window.level = kCGDesktopWindowLevel - 1;
    [self.window orderBack:nil];
}

- (void)teardown {
    [self.renderer stop];
    self.renderer = nil;

    [self.window close];
    self.window = nil;
}

#pragma mark - Audio

- (void)setCarriesAudio:(BOOL)carriesAudio {
    if (_carriesAudio == carriesAudio) return;
    _carriesAudio = carriesAudio;
    [self applyAudio];
}

- (void)setMuted:(BOOL)muted {
    self.desiredMute = muted;
    [self applyAudio];
}

- (BOOL)muted {
    return self.renderer ? self.renderer.muted : YES;
}

- (void)applyAudio {
    if (self.desiredMute || !self.carriesAudio) {
        [self.renderer mute];
    } else {
        [self.renderer unmute];
    }
}

#pragma mark - Playback

- (void)setGloballyPaused:(BOOL)paused {
    if (_globallyPaused == paused) return;
    _globallyPaused = paused;
    [self applyPlayback];
}

- (void)setCovered:(BOOL)covered {
    if (_covered == covered) return;
    _covered = covered;
    [self applyPlayback];
}

- (BOOL)paused {
    return self.globallyPaused || self.covered;
}

- (void)applyPlayback {
    if (!self.renderer || !self.wallpaperId) return;

    if (self.paused) {
        [self.renderer pause];
    } else {
        [self.renderer play];
    }
}

@end

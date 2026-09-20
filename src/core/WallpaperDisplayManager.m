//
//  WallpaperDisplayManager.m
//  MacieWallpaper - Every display's wallpaper
//
//  Created on 2026-09-01.
//

#import "WallpaperDisplayManager.h"
#import "WallpaperDisplay.h"
#import "MacieDisplayIdentity.h"
#import "LastWallpaperSnapshot.h"
#import "Constants.h"

/// Every display needs a key so it can appear in the picker, but a display that reports
/// no identity cannot have one that outlives the connection. Those get a runtime-only key
/// instead, which is never written to defaults — MacieSaveLastWallpaperSnapshot is passed
/// the display's real (nil) key and no-ops, so "not persistable" needs no special casing
/// anywhere else.
static NSString *EffectiveKey(WallpaperDisplay *display) {
    if (display.displayKey.length) return display.displayKey;
    return [NSString stringWithFormat:@"transient-%u", display.displayID];
}

@interface WallpaperDisplayManager ()

/// Screen order: index 0 is NSScreen.screens.firstObject, the primary.
@property (strong, nonatomic) NSMutableArray<WallpaperDisplay *> *displays;
/// Parallel to `displays`. Rebuilt whenever the set changes, because a name is only
/// ambiguous relative to the rest of the set.
@property (copy, nonatomic) NSArray<NSString *> *displayNames;

/// Effective key → the video dictionary on that display right now.
///
/// Not a cache of the snapshots: a transient display has no snapshot at all, and this is
/// the only thing that lets it survive a resolution change. It also gives the hero panel
/// a full video dictionary rather than a bare id.
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSDictionary *> *liveVideos;

@property (assign, nonatomic) BOOL muted;

@end

@implementation WallpaperDisplayManager

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _displays   = [NSMutableArray array];
    _liveVideos = [NSMutableDictionary dictionary];
    _muted      = YES;

    // No wallpapers are chosen here. -restoreFromSnapshots is a separate call so that the
    // caller controls when playback starts relative to the rest of launch.
    [self synchronizeWithScreens];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(screenParametersChanged:)
                                                name:NSApplicationDidChangeScreenParametersNotification
                                              object:nil];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - The set of displays

/// Brings `displays` in line with NSScreen.screens and returns the displays that were
/// added, which the caller has to give a wallpaper to. Existing displays are kept — and so
/// are their renderers, so a resolution change does not restart anyone's video.
- (NSArray<WallpaperDisplay *> *)synchronizeWithScreens {
    NSArray<NSScreen *> *screens = [NSScreen screens];

    NSMutableArray<WallpaperDisplay *> *ordered = [NSMutableArray arrayWithCapacity:screens.count];
    NSMutableArray<WallpaperDisplay *> *added   = [NSMutableArray array];
    NSMutableArray<WallpaperDisplay *> *surplus = [self.displays mutableCopy];

    for (NSScreen *screen in screens) {
        WallpaperDisplay *existing = [self displayInArray:surplus matchingScreen:screen];

        if (existing) {
            [surplus removeObject:existing];
            [existing followScreen:screen];
            [ordered addObject:existing];
            continue;
        }

        WallpaperDisplay *display = [[WallpaperDisplay alloc] initWithScreen:screen];
        [ordered addObject:display];
        [added addObject:display];
    }

    // Whatever is left was unplugged. Its snapshot stays in defaults on purpose: that is
    // what makes replugging restore the right wallpaper. The live entry does go, since a
    // transient key is only a display id and a later monitor could be handed the same one.
    for (WallpaperDisplay *display in surplus) {
        [self.liveVideos removeObjectForKey:EffectiveKey(display)];
        [display teardown];
    }

    self.displays = ordered;
    self.displayNames = MacieDisambiguateDisplayNames([ordered valueForKey:@"name"]);

    // Audio follows the primary, so a rearrangement that changes which display is first
    // moves the sound with it.
    for (NSUInteger i = 0; i < ordered.count; i++) {
        WallpaperDisplay *display = ordered[i];
        display.carriesAudio = (i == 0);
        [display setMuted:self.muted];
    }

    return added;
}

/// Matched on identity, not on the NSScreen object: AppKit hands out fresh NSScreen
/// instances after any screen change, so pointer comparison would rebuild everything.
- (nullable WallpaperDisplay *)displayInArray:(NSArray<WallpaperDisplay *> *)candidates
                               matchingScreen:(NSScreen *)screen {
    NSString *key = MacieDisplayKeyForScreen(screen);
    CGDirectDisplayID displayID = MacieDisplayIDForScreen(screen);

    for (WallpaperDisplay *display in candidates) {
        if (key.length && [display.displayKey isEqualToString:key]) return display;
        // A display with no identity can only be matched by its runtime id, so a
        // renumbered one is treated as new. That is the cost of reporting nothing.
        if (!key.length && !display.displayKey && display.displayID == displayID) return display;
    }
    return nil;
}

- (void)screenParametersChanged:(NSNotification *)notification {
    NSArray<WallpaperDisplay *> *added = [self synchronizeWithScreens];

    for (WallpaperDisplay *display in added) {
        [self giveStoredOrMirroredWallpaperTo:display];
    }

    if (self.onDisplaysChanged) self.onDisplaysChanged();
}

/// A display that has been seen before gets its own wallpaper back. One that has not
/// mirrors the primary, and that mirror is stored as its own assignment — so this happens
/// exactly once per display, and a later reconnect restores this wallpaper rather than
/// whatever the primary has moved on to.
- (void)giveStoredOrMirroredWallpaperTo:(WallpaperDisplay *)display {
    NSDictionary *own = MacieLoadLastWallpaperSnapshot(display.displayKey);
    if (own) {
        [self loadWallpaper:own onDisplay:display persist:NO];
        return;
    }

    NSDictionary *mirror = [self primaryWallpaper];
    if (!mirror) return;

    [self loadWallpaper:mirror onDisplay:display persist:YES];
}

/// What the primary is showing, preferring the live value: at launch the snapshot and the
/// live value agree, but after the user has applied something the live value is the truth.
- (nullable NSDictionary *)primaryWallpaper {
    WallpaperDisplay *primary = self.displays.firstObject;
    if (!primary) return nil;

    NSDictionary *live = self.liveVideos[EffectiveKey(primary)];
    return live ?: MacieLoadLastWallpaperSnapshot(primary.displayKey);
}

- (BOOL)loadWallpaper:(NSDictionary *)video
            onDisplay:(WallpaperDisplay *)display
              persist:(BOOL)persist {
    if (![display loadWallpaper:video]) return NO;

    self.liveVideos[EffectiveKey(display)] = video;
    if (persist) MacieSaveLastWallpaperSnapshot(video, display.displayKey);
    return YES;
}

#pragma mark - Queries

- (NSArray<NSString *> *)displayKeys {
    NSMutableArray<NSString *> *keys = [NSMutableArray arrayWithCapacity:self.displays.count];
    for (WallpaperDisplay *display in self.displays) [keys addObject:EffectiveKey(display)];
    return [keys copy];
}

- (NSString *)primaryDisplayKey {
    WallpaperDisplay *primary = self.displays.firstObject;
    return primary ? EffectiveKey(primary) : nil;
}

- (NSString *)nameForDisplayKey:(NSString *)key {
    NSUInteger index = [self indexOfDisplayKey:key];
    if (index == NSNotFound || index >= self.displayNames.count) return nil;
    return self.displayNames[index];
}

- (NSUInteger)indexOfDisplayKey:(NSString *)key {
    if (!key.length) return NSNotFound;

    for (NSUInteger i = 0; i < self.displays.count; i++) {
        if ([EffectiveKey(self.displays[i]) isEqualToString:key]) return i;
    }
    return NSNotFound;
}

/// A nil key means the primary display everywhere in this class, so that a caller with no
/// target selected does not have to know which display that is.
- (nullable WallpaperDisplay *)displayForKey:(nullable NSString *)key {
    if (!key.length) return self.displays.firstObject;

    NSUInteger index = [self indexOfDisplayKey:key];
    return index == NSNotFound ? nil : self.displays[index];
}

- (NSString *)wallpaperIdForDisplayKey:(NSString *)key {
    return [self displayForKey:key].wallpaperId;
}

- (NSDictionary *)wallpaperForDisplayKey:(NSString *)key {
    WallpaperDisplay *display = [self displayForKey:key];
    return display ? self.liveVideos[EffectiveKey(display)] : nil;
}

- (BOOL)assignmentsDiffer {
    if (self.displays.count < 2) return NO;

    NSString *first = self.displays.firstObject.wallpaperId;
    for (WallpaperDisplay *display in self.displays) {
        NSString *current = display.wallpaperId;
        // Compared including nil, so a display showing nothing counts as different rather
        // than as agreeing with everyone.
        if (first != current && ![first isEqualToString:current]) return YES;
    }
    return NO;
}

#pragma mark - Applying

- (BOOL)applyWallpaper:(NSDictionary *)video toDisplayKey:(NSString *)key {
    // A nil key is a broadcast, not the primary: this is the one place where the two mean
    // different things, because "All Displays" is a picker choice rather than a display.
    NSArray<WallpaperDisplay *> *targets = self.displays;
    if (key.length) {
        WallpaperDisplay *display = [self displayForKey:key];
        targets = display ? @[display] : @[];
    }

    BOOL any = NO;
    for (WallpaperDisplay *display in targets) {
        if ([self loadWallpaper:video onDisplay:display persist:YES]) any = YES;
    }
    return any;
}

#pragma mark - Launch and rescan

- (void)restoreFromSnapshots {
    WallpaperDisplay *primary = self.displays.firstObject;
    if (!primary) return;

    // Upgrades a single-display install's flat snapshot into this display's entry. Has to
    // run before anything is read, and does nothing on an install that has already moved.
    MacieMigrateLastWallpaperSnapshotIfNeeded(primary.displayKey);

    NSDictionary *primarySnapshot = MacieLoadLastWallpaperSnapshot(primary.displayKey);
    if (primarySnapshot) [self loadWallpaper:primarySnapshot onDisplay:primary persist:NO];

    // Every other display in one pass, now that there is something to mirror. A display
    // with no snapshot does not wait for the scan: the primary's snapshot is already here.
    for (WallpaperDisplay *display in self.displays) {
        if (display == primary) continue;
        [self giveStoredOrMirroredWallpaperTo:display];
    }

    [self restoreStoredMuteState];
}

- (void)reconcileWithLibrary:(NSArray<NSDictionary *> *)videos {
    WallpaperDisplay *primary = self.displays.firstObject;
    if (!primary || !videos.count) return;

    NSMutableDictionary<NSString *, NSDictionary *> *byId =
        [NSMutableDictionary dictionaryWithCapacity:videos.count];
    for (NSDictionary *video in videos) {
        NSString *videoId = video[@"id"];
        if ([videoId isKindOfClass:[NSString class]] && videoId.length) byId[videoId] = video;
    }

    // The primary settles first, because every other display may end up mirroring it.
    // Falling through to the first available video covers both a first run and a primary
    // whose wallpaper has been uninstalled.
    NSDictionary *primaryVideo = [self libraryVideoForDisplay:primary in:byId] ?: videos.firstObject;
    [self reconcileDisplay:primary to:primaryVideo];

    for (WallpaperDisplay *display in self.displays) {
        if (display == primary) continue;
        NSDictionary *video = [self libraryVideoForDisplay:display in:byId];
        if (!video) {
            NSLog(@"Display '%@' has no installed wallpaper of its own — mirroring the primary",
                  display.name);
            video = primaryVideo;
        }
        [self reconcileDisplay:display to:video];
    }
}

/// The library entry for whatever this display is assigned, or nil if that wallpaper is no
/// longer installed.
///
/// The stored id is consulted even when the display is playing nothing, because a snapshot
/// whose file was missing at launch — an unmounted volume, say — still names a wallpaper the
/// scan may well have just found.
- (nullable NSDictionary *)libraryVideoForDisplay:(WallpaperDisplay *)display
                                              in:(NSDictionary<NSString *, NSDictionary *> *)byId {
    NSString *assignedId = display.wallpaperId ?: MacieLoadAssignedWallpaperId(display.displayKey);
    if (!assignedId.length) return nil;
    return byId[assignedId];
}

/// Loads `video` only if it is not already what this display is showing. Reloading an
/// identical wallpaper would restart it from the first frame for no reason.
- (void)reconcileDisplay:(WallpaperDisplay *)display to:(NSDictionary *)video {
    NSString *videoId = video[@"id"];
    if ([display.wallpaperId isEqualToString:videoId]) {
        // Still the right wallpaper, but the scan may have found it at a new path, and the
        // snapshot carries more than the id.
        self.liveVideos[EffectiveKey(display)] = video;
        MacieSaveLastWallpaperSnapshot(video, display.displayKey);
        return;
    }

    [self loadWallpaper:video onDisplay:display persist:YES];
}

#pragma mark - Audio

- (void)setMuted:(BOOL)muted {
    _muted = muted;
    for (WallpaperDisplay *display in self.displays) [display setMuted:muted];
    [[NSUserDefaults standardUserDefaults] setBool:muted forKey:kDefaultsLastMuteState];
}

- (void)restoreStoredMuteState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL stored = [defaults objectForKey:kDefaultsLastMuteState] != nil
        ? [defaults boolForKey:kDefaultsLastMuteState]
        : YES;

    _muted = stored;
    for (WallpaperDisplay *display in self.displays) [display setMuted:stored];
}

#pragma mark - Pausing

- (void)pauseAll {
    for (WallpaperDisplay *display in self.displays) [display setGloballyPaused:YES];
}

- (void)resumeAll {
    for (WallpaperDisplay *display in self.displays) [display setGloballyPaused:NO];
}

- (void)setCoveredDisplayIDs:(NSSet<NSNumber *> *)displayIDs {
    for (WallpaperDisplay *display in self.displays) {
        [display setCovered:[displayIDs containsObject:@(display.displayID)]];
    }
}

#pragma mark - Shutdown

- (void)teardown {
    for (WallpaperDisplay *display in self.displays) [display teardown];
    [self.displays removeAllObjects];
    self.displayNames = @[];
}

@end

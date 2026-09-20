//
//  WallpaperDisplay.h
//  MacieWallpaper - One screen's wallpaper
//
//  Created on 2026-09-01.
//
//  A display owns the borderless window that sits under the desktop icons on one
//  screen, the renderer drawing into it, and the id of the wallpaper assigned to it.
//  It knows nothing about the other displays: composing them is WallpaperDisplayManager's
//  job.
//

#ifndef WallpaperDisplay_h
#define WallpaperDisplay_h

#import <Cocoa/Cocoa.h>
#import "AVVideoRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface WallpaperDisplay : NSObject

/// Stable across launches, or nil when the display reports no identity at all. A nil
/// key means the display runs normally but nothing about it can be remembered.
@property (copy, nonatomic, readonly, nullable) NSString *displayKey;
/// The runtime handle. Changes when the display reconnects, so never persist it.
@property (assign, nonatomic, readonly) CGDirectDisplayID displayID;
/// As shown in System Settings. Two identical monitors share a name; the manager
/// disambiguates them for the picker.
@property (copy, nonatomic, readonly) NSString *name;
/// The wallpaper on this display, or nil if nothing has loaded.
@property (copy, nonatomic, readonly, nullable) NSString *wallpaperId;

/// Only the primary display's renderer ever carries audio. When NO, the display ignores
/// -setMuted:NO entirely and stays silent no matter what the mute toggle says, so N
/// displays cannot become N overlapping soundtracks.
@property (assign, nonatomic) BOOL carriesAudio;

- (instancetype)initWithScreen:(NSScreen *)screen;

/// Starts `video` on this display. NO if the file will not play, in which case the
/// previous wallpaper and assignment are left alone.
- (BOOL)loadWallpaper:(NSDictionary *)video;

/// Re-frames the window after a resolution change or a rearrangement. Also re-adopts
/// the screen's display id, which a reconnect can renumber.
- (void)followScreen:(NSScreen *)screen;

/// Closes the window and stops the renderer. What was stored for this display is the
/// manager's business and is deliberately untouched, so replugging restores it.
- (void)teardown;

/// Silences this display, honouring `carriesAudio`. Reports what the renderer ended up
/// at, which is always YES for a display that carries no audio.
- (void)setMuted:(BOOL)muted;
@property (assign, nonatomic, readonly) BOOL muted;

/// Pause-on-battery and sleep: applies regardless of what any single display is doing.
- (void)setGloballyPaused:(BOOL)paused;
/// Pause-on-fullscreen: this display is covered by someone else's window.
- (void)setCovered:(BOOL)covered;
/// YES when either reason to pause applies. The two are tracked separately so that
/// waking the Mac does not start a display still hidden behind a fullscreen game, and
/// uncovering a display does not start it while the Mac is asleep.
@property (assign, nonatomic, readonly) BOOL paused;

@end

NS_ASSUME_NONNULL_END

#endif /* WallpaperDisplay_h */

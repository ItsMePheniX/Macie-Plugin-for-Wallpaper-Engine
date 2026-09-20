//
//  WallpaperDisplayManager.h
//  MacieWallpaper - Every display's wallpaper
//
//  Created on 2026-09-01.
//
//  Owns one WallpaperDisplay per attached screen and everything that has to reason about
//  the whole set: which display is primary, what is assigned to each of them, what to do
//  when one is plugged in or pulled out, and what to persist.
//
//  The gallery talks to this and never to a renderer, so "what is playing" has one
//  answer per display instead of one answer for the machine.
//

#ifndef WallpaperDisplayManager_h
#define WallpaperDisplayManager_h

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface WallpaperDisplayManager : NSObject

/// Screen order, primary first. Empty only when no screens are attached at all, which
/// happens on a closed-lid Mac with no external display.
@property (copy, nonatomic, readonly) NSArray<NSString *> *displayKeys;
@property (copy, nonatomic, readonly, nullable) NSString *primaryDisplayKey;

/// Called after displays are added, removed or reordered, so the target picker can be
/// rebuilt. Always on the main thread.
@property (copy, nonatomic, nullable) void (^onDisplaysChanged)(void);

/// The picker label for a display, with repeats disambiguated ("LG UltraFine (2)").
/// nil when `key` is not currently attached — which is how a remembered target is
/// checked for still being there.
- (nullable NSString *)nameForDisplayKey:(NSString *)key;

/// A nil key means every attached display. NO only if no display accepted the video at
/// all, which is the signal to raise the existing apply-failure alert once.
- (BOOL)applyWallpaper:(NSDictionary *)video toDisplayKey:(nullable NSString *)key;

/// A nil key means the primary display.
- (nullable NSString *)wallpaperIdForDisplayKey:(nullable NSString *)key;
/// The full video dictionary behind -wallpaperIdForDisplayKey:, for the hero panel. Known
/// from the moment a wallpaper is applied or restored, so the hero can be filled in
/// before the library scan finishes.
- (nullable NSDictionary *)wallpaperForDisplayKey:(nullable NSString *)key;
/// YES when the attached displays are not all showing the same wallpaper. Always NO with
/// a single display.
- (BOOL)assignmentsDiffer;

/// Launch: puts every display's remembered wallpaper back without waiting for the library
/// scan. A display with no snapshot of its own adopts the primary's, stored as its own
/// assignment so that the next reconnect restores this wallpaper rather than re-mirroring
/// a since-changed primary.
- (void)restoreFromSnapshots;

/// Post-scan: re-resolves each display's assignment against the real library, and mirrors
/// the primary onto any display whose wallpaper has been uninstalled. Also the first-run
/// path, where nothing was remembered and the primary takes the first available video.
- (void)reconcileWithLibrary:(NSArray<NSDictionary *> *)videos;

/// Audio lives on the primary display alone, so this is one setting rather than one per
/// display. Every other display stays silent whatever it says.
@property (assign, nonatomic, readonly) BOOL muted;
- (void)setMuted:(BOOL)muted;
/// Applies the mute remembered from the last session. Renderers start muted, so this only
/// ever has to undo that.
- (void)restoreStoredMuteState;

/// Sleep and pause-on-battery, which are properties of the machine.
- (void)pauseAll;
- (void)resumeAll;

/// Pause-on-fullscreen, which is a property of one screen. Displays absent from the set
/// are uncovered. Takes runtime display ids rather than keys because this manager is the
/// only thing that should hold the id-to-key mapping.
- (void)setCoveredDisplayIDs:(NSSet<NSNumber *> *)displayIDs;

/// Closes every window and stops every renderer. Stored assignments are kept.
- (void)teardown;

@end

NS_ASSUME_NONNULL_END

#endif /* WallpaperDisplayManager_h */

//
//  LastWallpaperSnapshot.h
//  MacieWallpaper - Restoring each display's wallpaper before a scan finishes
//
//  Created on 2026-08-31.
//
//  The library scan is what normally tells the app where a wallpaper's video file
//  lives, which is why playback used to have to wait for it. These snapshots carry
//  just enough of each display's wallpaper to start it immediately at launch.
//
//  Keyed by the stable display key from MacieDisplayIdentity, so a two-monitor setup
//  restores both panels rather than one.
//

#ifndef LastWallpaperSnapshot_h
#define LastWallpaperSnapshot_h

#import <Foundation/Foundation.h>

// Defined in a .m file but consumed from Objective-C++ translation units, so the
// declarations need C linkage or the C++ side looks for mangled symbols.
#if defined(__cplusplus)
extern "C" {
#endif

/// Persists the fields needed to restore `video` on `displayKey` at the next launch.
/// Pass a nil or empty `displayKey` for a display that has no stable identity — the
/// call becomes a no-op rather than corrupting another display's entry.
void MacieSaveLastWallpaperSnapshot(NSDictionary *_Nonnull video,
                                    NSString *_Nullable displayKey);

/// The saved snapshot for `displayKey`, or nil if nothing was saved, the entry is
/// malformed, or its video file is no longer on disk. A nil return means "cannot play
/// this right now", which is what the launch restore needs to know.
NSDictionary *_Nullable MacieLoadLastWallpaperSnapshot(NSString *_Nullable displayKey);

/// The wallpaper id remembered for `displayKey`, even when its video file is
/// currently missing. An unmounted external drive should not lose the assignment: the
/// post-scan reconcile re-resolves this id against the freshly scanned library.
NSString *_Nullable MacieLoadAssignedWallpaperId(NSString *_Nullable displayKey);

/// One-time upgrade from the single-display format, where the snapshot was one flat
/// dictionary and the playing id lived in kDefaultsLastWallpaperId. Adopts whatever
/// was there as `primaryDisplayKey`'s entry. Safe to call on every launch.
void MacieMigrateLastWallpaperSnapshotIfNeeded(NSString *_Nullable primaryDisplayKey);

#if defined(__cplusplus)
}   // extern "C"
#endif

#endif /* LastWallpaperSnapshot_h */

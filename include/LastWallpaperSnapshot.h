//
//  LastWallpaperSnapshot.h
//  MacieWallpaper - Restoring the last-played wallpaper before a scan finishes
//
//  Created on 2026-08-31.
//
//  The library scan is what tells the app where a wallpaper's video file lives, so
//  playback used to have to wait for it. These two functions keep just enough of
//  the last-played wallpaper in NSUserDefaults to start it again immediately: the
//  path for AVVideoRenderer, and the title, description and preview for the hero
//  panel.
//
//  It is a cache, never a source of truth. The loader validates that the video file
//  still exists, and the scan's results always replace it.
//

#ifndef LastWallpaperSnapshot_h
#define LastWallpaperSnapshot_h

#import <Foundation/Foundation.h>

// Both callers are Objective-C++ translation units and this compiles as C, so the
// declarations need C linkage or the link fails on mangled names.
#if defined(__cplusplus)
extern "C" {
#endif

/// Persists the fields needed to restore `video` at the next launch. A video
/// missing an id or a path is ignored rather than saved half-formed.
void MacieSaveLastWallpaperSnapshot(NSDictionary *video);

/// Returns the saved snapshot, or nil if nothing was saved or its video file is no
/// longer on disk. The result has the same keys `HeroPanelView` and
/// `AVVideoRenderer` read from a real library entry.
NSDictionary *MacieLoadLastWallpaperSnapshot(void);

#if defined(__cplusplus)
}
#endif

#endif /* LastWallpaperSnapshot_h */

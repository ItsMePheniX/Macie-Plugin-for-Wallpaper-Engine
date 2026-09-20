//
//  MacieDisplayIdentity.h
//  MacieWallpaper - Stable identity for a physical display
//
//  Created on 2026-09-01.
//
//  Turning an NSScreen into something that can be used as a dictionary key across
//  launches is harder than it looks: CGDirectDisplayID is reassigned when a display
//  reconnects, and NSScreen itself is a transient object. This is the only file that
//  knows how to do it.
//

#ifndef MacieDisplayIdentity_h
#define MacieDisplayIdentity_h

#import <Cocoa/Cocoa.h>

// Defined in a .m file but consumed from Objective-C++ translation units, so the
// declarations need C linkage or the C++ side looks for mangled symbols.
#if defined(__cplusplus)
extern "C" {
#endif

/// A key that survives reboots, cable swaps and moving the monitor to a different
/// port, suitable for persisting per-display preferences.
///
/// Returns nil when the display reports neither a UUID nor any of vendor, model or
/// serial. Callers must still show such a display — they just cannot remember
/// anything about it, and should substitute a runtime-only key.
NSString *_Nullable MacieDisplayKeyForScreen(NSScreen *_Nonnull screen);

/// The human-readable name for a display, as shown in System Settings. Two identical
/// monitors return the same string; disambiguating them is the caller's job, since
/// only the caller knows the whole set.
NSString *_Nonnull MacieDisplayNameForScreen(NSScreen *_Nonnull screen);

/// The runtime handle for a display. Valid only for this connection: do not persist
/// it, and do not compare it against a value from a previous launch.
CGDirectDisplayID MacieDisplayIDForScreen(NSScreen *_Nonnull screen);

/// Takes display names in screen order and appends an index to every repeat, so a
/// pair of identical monitors reads as "LG UltraFine" and "LG UltraFine (2)" rather
/// than as two indistinguishable menu items.
NSArray<NSString *> *_Nonnull MacieDisambiguateDisplayNames(NSArray<NSString *> *_Nonnull names);

#if defined(__cplusplus)
}   // extern "C"
#endif

#endif /* MacieDisplayIdentity_h */

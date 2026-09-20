# Multi-Monitor Support — Design

**Date:** 2026-09-01
**Status:** Approved, not yet implemented
**Checklist item:** Phase 6 — "Multi-monitor support (different wallpapers per screen)"

## The problem

A second display shows no wallpaper at all today.

`AppDelegate` owns exactly one `NSWindow *desktopWindow` and one
`AVVideoRenderer *videoRenderer`. `-createDesktopWindow` sizes that window to
`[NSScreen mainScreen].frame`, and `-screenParametersChanged:` resizes it to the same
thing. Nothing ever creates a second window, so every display except one shows the
macOS desktop background.

The window plumbing is the easy half. The harder half is that the gallery's whole
account of what is playing rests on one string:

- `MainWindowController.playingWallpaperId` — read by the hero panel
  (`-showInHero:`), by every card (`-isPlayingWallpaper`), by `-playbackOrder` for
  Next/Previous, and by Random.
- `kDefaultsLastWallpaperId` in `NSUserDefaults` — the persisted form of the same
  fact, read in three places and written by `-applyWallpaper:`.
- `kDefaultsLastWallpaperSnapshot` — one flat dictionary, the thing that makes
  launch fast (see `2026-08-31-async-scan-launch-progress-design.md`).

With N displays there are N answers to "what is playing", and the UI has to be able
to say which display it means.

There is also a latent bug to fix on the way through. The SDK is explicit:
`NSScreen.screens` is "All screens; first one is *zero* screen", while
`NSScreen.mainScreen` is "Screen with key window". Both `-createDesktopWindow` and
`-screenParametersChanged:` use `mainScreen`, so today, dragging the gallery window
onto a second display makes `mainScreen` return that display — and the next
screen-parameters change moves the desktop wallpaper window onto it.

## Decisions

| Question | Decision | Why |
|---|---|---|
| How does the user pick a display? | A target picker in the gallery toolbar | One piece of new state, one code path. Hidden when only one display is connected, so single-display use is untouched. |
| What does a never-seen display show? | Mirrors the primary display | Plugging in a monitor is never a black rectangle, and needs no configuration. |
| N simultaneous players — what about cost? | Pause per display when that display is covered | Fixes the existing main-screen-centric `pause-on-fullscreen` check as a side effect. |
| Where does audio go? | The primary display's renderer only; all others hard-muted | N unmuted players means N overlapping soundtracks. |
| What identifies a display across launches? | `CGDisplayCreateUUIDFromDisplayID` | Tied to the physical panel: survives reboots, cable swaps, and port changes. `CGDirectDisplayID` is reassigned on reconnect and is useless for persistence. |
| Is "All Displays" a stored value? | No — it is a broadcast target | Every display always has its own independent assignment. "All" writes the same id to each of them. |

## Architecture

Two new units. `AppDelegate` and `MainWindowController` both get smaller.

| Unit | Files | Responsibility | Depends on |
|---|---|---|---|
| `WallpaperDisplay` | `include/WallpaperDisplay.h`, `src/core/WallpaperDisplay.m` | One screen's worth of wallpaper: its display id, its borderless window, its `AVVideoRenderer`, the id of the wallpaper assigned to it. Knows how to follow its screen's frame and how to pause and resume itself. | `AVVideoRenderer`, AppKit |
| `WallpaperDisplayManager` | `include/WallpaperDisplayManager.h`, `src/core/WallpaperDisplayManager.m` | The set of `WallpaperDisplay`s. Screen connect and disconnect, stable identity, persistence, broadcast, and the queries the gallery needs. | `WallpaperDisplay`, `MacieDisplayIdentity`, `LastWallpaperSnapshot` |
| `MacieDisplayIdentity` | `include/MacieDisplayIdentity.h`, `src/core/MacieDisplayIdentity.m` | Turns an `NSScreen` into a stable persistence key and a human label. Nothing else. | ColorSync, AppKit |

Both new `.m` files are plain Objective-C. The manager trades in the same
`NSDictionary` video dictionaries the gallery already uses, so no C++ crosses into
either of them and neither has to become `.mm`.

`MacieDisplayIdentity` is separate from the manager on purpose: it is the one piece
with a hard dependency on ColorSync and the one piece with fallback logic worth
reading on its own.

### What leaves `AppDelegate`

Removed: `desktopWindow`, `videoRenderer`, `-createDesktopWindow`,
`-screenParametersChanged:`, `-restoreLastWallpaperFromSnapshot`, and the renderer
half of `-playFirstAvailableVideo`. Replaced by a single
`WallpaperDisplayManager *displayManager` property. Roughly 120 lines out of 612.

`-restoreMuteState`, sleep/wake, and `-performanceMonitorShouldPausePlayback:reason:`
all forward to the manager instead of touching a renderer.

### What changes in `MainWindowController`

- `AVVideoRenderer *videoRenderer` → `WallpaperDisplayManager *displayManager`.
  `-attachVideoRenderer:` becomes `-attachDisplayManager:`, keeping the async-launch
  arrangement where the gallery is built before playback exists.
- `NSString *playingWallpaperId` → a computed lookup scoped to the current target.
  The three reads of `kDefaultsLastWallpaperId` become manager queries.
- `-applyWallpaper:` keeps its role as the single funnel. It calls
  `-applyWallpaper:toDisplayKey:` with the current target instead of calling
  `loadAndPlayVideo:` directly; recents, favourites, and the hero all stay as they are.
- New: the target picker, and one extra line in the hero for the mixed state.

## Interfaces

### `MacieDisplayIdentity`

```objc
/// Stable across reboots, cable swaps and port changes. Returns nil when the display
/// reports neither a UUID nor a vendor/model/serial triple, in which case the caller
/// runs the display normally but does not persist anything for it.
NSString *_Nullable MacieDisplayKeyForScreen(NSScreen *screen);

/// The label shown in the target picker. Repeats are disambiguated by the caller,
/// which is the only place that knows the whole set.
NSString *MacieDisplayNameForScreen(NSScreen *screen);

/// The runtime handle. Valid only for this connection of this display.
CGDirectDisplayID MacieDisplayIDForScreen(NSScreen *screen);
```

Key derivation, in order: `CGDisplayCreateUUIDFromDisplayID` →
`CFUUIDCreateString`; failing that, `vendor-model-serial` from
`CGDisplayVendorNumber` / `CGDisplayModelNumber` / `CGDisplaySerialNumber`; failing
that (all three zero), `nil`.

### `WallpaperDisplay`

```objc
@interface WallpaperDisplay : NSObject

@property (readonly, copy, nullable) NSString *displayKey;   // nil = not persistable
@property (readonly) CGDirectDisplayID displayID;
@property (readonly, copy) NSString *name;
/// The wallpaper currently on this display, or nil if nothing loaded.
@property (readonly, copy, nullable) NSString *wallpaperId;
/// Only the primary display's renderer ever carries audio. When NO, the display
/// ignores unmute entirely and stays silent no matter what the mute toggle says.
@property (assign) BOOL carriesAudio;

- (instancetype)initWithScreen:(NSScreen *)screen;

- (BOOL)loadWallpaper:(NSDictionary *)video;
/// Re-frames the window after a resolution change or a rearrangement.
- (void)followScreen:(NSScreen *)screen;
/// Closes the window and stops the renderer. The stored assignment is the manager's
/// business and is not touched here.
- (void)teardown;

- (void)pause;
- (void)resume;
@property (readonly) BOOL paused;

@end
```

The window setup moves here verbatim from `-createDesktopWindow`: borderless,
`clearColor`, `opaque = NO`, `level = kCGDesktopWindowLevel - 1`,
`ignoresMouseEvents = YES`, the three collection behaviours, `orderBack:`. The only
change is that the frame comes from the screen it was handed rather than from
`mainScreen`.

### `WallpaperDisplayManager`

```objc
@interface WallpaperDisplayManager : NSObject

/// Screen order, primary first. Empty only if no screens are attached at all.
@property (readonly, copy) NSArray<NSString *> *displayKeys;
@property (readonly, copy, nullable) NSString *primaryDisplayKey;
- (NSString *)nameForDisplayKey:(NSString *)key;

/// A nil key means every connected display. Returns NO only if no display accepted
/// the video at all.
- (BOOL)applyWallpaper:(NSDictionary *)video toDisplayKey:(nullable NSString *)key;

/// A nil key means the primary display's wallpaper.
- (nullable NSString *)wallpaperIdForDisplayKey:(nullable NSString *)key;
/// YES when the connected displays are not all showing the same wallpaper.
- (BOOL)assignmentsDiffer;

/// Launch: puts every display's remembered wallpaper straight back, without waiting
/// for the library scan. A display with no snapshot of its own gets the primary's,
/// stored as its own assignment — there is nothing to wait for, the primary's
/// snapshot is already in hand.
- (void)restoreFromSnapshots;

/// Post-scan: drops assignments whose wallpaper is no longer in the scanned library
/// and mirrors the primary onto any display left without one.
- (void)reconcileWithLibrary:(NSArray<NSDictionary *> *)videos;

/// Audio and mute act on the primary display only.
@property (readonly) BOOL muted;
- (void)setMuted:(BOOL)muted;

/// Global stop, used for sleep and pause-on-battery.
- (void)pauseAll;
- (void)resumeAll;
/// Per-display, used for pause-on-fullscreen.
- (void)pauseDisplaysWithKeys:(NSSet<NSString *> *)keys;

@end
```

The manager registers for `NSApplicationDidChangeScreenParametersNotification`
itself — that observer moves out of `AppDelegate` entirely.

## Data flow

### Launch

```
applicationDidFinishLaunching
  └─ startWithConfiguredPath
       ├─ displayManager = [[WallpaperDisplayManager alloc] init]
       │     └─ builds one WallpaperDisplay per NSScreen.screens
       ├─ [displayManager restoreFromSnapshots]     ← every display, no scan needed
       ├─ beginWallpaperScan                        ← background, unchanged
       ├─ showGallery                               ← picker built from displayKeys
       └─ setupPerformanceMonitor

finishWallpaperScan
  ├─ [displayManager reconcileWithLibrary:videos]   ← replaces the old
  │                                                    playingWallpaperStillInstalled
  │                                                    / playFirstAvailableVideo pair
  └─ [galleryController reloadFromAssetManager]
```

The ordering constraint from the async-scan design still holds and for the same
reason: playback settles before the grid reloads, because the grid asks the manager
what is playing.

### Applying a wallpaper

```
card click / Return / context menu / hero Apply / Next / Prev / Random
  └─ MainWindowController -applyWallpaper:
       └─ [displayManager applyWallpaper:video toDisplayKey:self.currentTargetKey]
            ├─ nil key  → every connected display loads it, each stored under its key
            └─ one key  → that display only
       then, unchanged: recents, hero, mute button, sidebar badges, card refresh
```

### Connect and disconnect

```
NSApplicationDidChangeScreenParametersNotification
  └─ manager reconciles NSScreen.screens against its own set
       ├─ screen present, display present  → [display followScreen:screen]
       ├─ screen present, display absent   → new WallpaperDisplay
       │     ├─ key has a stored snapshot → restore it
       │     └─ key unknown               → mirror the primary, and store it as that
       │                                     display's own assignment, so the next
       │                                     replug restores this wallpaper rather
       │                                     than re-mirroring a since-changed primary
       ├─ display present, screen absent   → [display teardown], snapshot kept
       └─ primary changed → move audio to the new primary
```

Mirroring therefore happens exactly once per display, the first time it is ever seen.
From then on it has an independent assignment like any other display.

## Persistence

One key carries the per-display state, plus one for the picker:

```
kDefaultsLastWallpaperSnapshot  → { "<display-key>": {id,title,path,preview,description}, … }
kDefaultsWallpaperTarget        → "<display-key>" or absent for All Displays
```

The snapshot map is the *only* record of which wallpaper is on which display. There
is deliberately no separate display-key → wallpaper-id dictionary: the snapshot
already contains the id, and a second store of the same fact is the very thing this
design retires `kDefaultsLastWallpaperId` for.

Entries for disconnected displays are never pruned — that is exactly what makes
replugging a monitor restore the right wallpaper. The map grows by one entry per
display ever owned, which is not a size worth engineering against.

A display whose `MacieDisplayKeyForScreen` returns nil still needs a key to appear in
`displayKeys` and the picker, so the manager gives it a runtime-only key of the form
`transient-<displayID>`. Those keys are excluded from every read and write of the
snapshot map, which is what "not persistable" means in practice.

`LastWallpaperSnapshot` changes shape. Its two functions gain a display key:

```objc
void MacieSaveLastWallpaperSnapshot(NSDictionary *video, NSString *displayKey);
NSDictionary *_Nullable MacieLoadLastWallpaperSnapshot(NSString *displayKey);
/// Every stored snapshot, for the launch restore.
NSDictionary<NSString *, NSDictionary *> *MacieLoadAllLastWallpaperSnapshots(void);
```

The per-entry validation stays as it is: a snapshot is rejected unless it has a
non-empty `id` and `path` and its video file still exists, so an uninstalled
wallpaper cannot come back from the dead on any display.

### Migration

Existing installs have `kDefaultsLastWallpaperSnapshot` as the flat five-key
dictionary and `kDefaultsLastWallpaperId` as a bare string. The loader detects the
old shape by a top-level `path` key and adopts it, once, as the current primary
display's entry. `kDefaultsLastWallpaperId` is read for that same one-time migration
and then never written again: the per-display map becomes the single source of truth,
and keeping a parallel scalar would be two facts that can disagree.

## UI

**The target picker.** An `NSPopUpButton` in the gallery toolbar, placed left of the
trailing icon buttons in `-buildToolbar`. Items: "All Displays", a separator, then one
per screen in screen order. It is hidden outright when `displayKeys.count < 2`, so a
single-display user sees no change at all. The selection persists across launches in
`kDefaultsWallpaperTarget`, defaulting to "All Displays", and falls back to that
default when the remembered display is not connected.

**Mixed state.** When the target is "All Displays" and `-assignmentsDiffer` is YES,
there is no single answer to what is playing. The hero panel and the card badges
follow the primary display, and the hero shows one extra line — "Other displays
differ" — so the mismatch is visible instead of silently wrong. When the target is a
specific display, every part of the UI reflects that display exactly, which is
today's behaviour unchanged.

**Everything else.** Next, Previous, Random and Shuffle act on the current target,
broadcasting when it is "All Displays". The mute button keeps acting on the primary
renderer, because that is the only one carrying audio.

## Performance monitor

`PerformanceMonitorDelegate` currently reports a single verdict:

```objc
- (void)performanceMonitorShouldPausePlayback:(BOOL)shouldPause reason:(NSString *)reason;
```

Battery is genuinely global and keeps that path. Fullscreen is not: it happens on one
display. `-detectFullscreenApp` already walks `CGWindowListCopyWindowInfo`; it
compares each window's bounds against `[NSScreen mainScreen].frame` and returns one
`BOOL`. It changes to compare against every screen's frame and return the set of
covered screens, and the delegate gains a companion callback:

```objc
- (void)performanceMonitorCoveredScreensChanged:(NSSet<NSNumber *> *)displayIDs;
```

`AppDelegate` maps those display ids to keys and calls
`-pauseDisplaysWithKeys:`. A fullscreen game on the external display stops that
display's video and leaves the built-in animating.

The two reasons to pause are independent and must not clobber each other, so each
`WallpaperDisplay` tracks them separately and plays only when neither applies. A
global pause (sleep, or pause-on-battery) wins over everything: resuming from it must
not start a display that is still covered by a fullscreen app, and uncovering a
display must not start it while the machine is asleep.

## Error handling

| Case | Behaviour |
|---|---|
| Assigned video file gone for one display | That display mirrors the primary; logged |
| Primary's video gone | Falls through to the existing first-available choice |
| Assigned id no longer in the library after a rescan | Same, per display, inside `-reconcileWithLibrary:` |
| Renderer fails to load on one display | Other displays unaffected; that one shows the desktop background. A user-initiated apply still raises the existing `-presentApplyFailureForTitle:` alert, once, no matter how many displays were targeted |
| `MacieDisplayKeyForScreen` returns nil | Display gets a `transient-<displayID>` key: it appears in the picker and plays normally, but nothing is persisted for it and it re-mirrors the primary on every reconnect |
| Display disconnects mid-playback | Window and renderer torn down, stored assignment kept |
| All displays disconnect (clamshell) | Manager holds an empty set; `restoreFromSnapshots` and `applyWallpaper:` become no-ops until a screen returns |
| Remembered target display not connected at launch | Target falls back to "All Displays" |

## Testing

Real verification needs a second display.

**With a second display:**

1. Connect it — it mirrors the primary immediately, no configuration.
2. Target it in the picker, apply a different wallpaper — only that display changes.
3. Switch the target to "All Displays" — hero shows the primary's wallpaper plus
   "Other displays differ".
4. Apply with "All Displays" targeted — both displays change.
5. Unplug, replug — each display gets its own wallpaper back.
6. Quit and relaunch — both displays restore before the scan finishes.
7. Change the display arrangement in System Settings — both windows follow their
   screens, and the audio follows the new primary.
8. Fullscreen a video on one display — that display pauses, the other keeps playing.
9. Drag the gallery onto the second display, then change resolution — the wallpaper
   windows stay put (the `mainScreen` bug).
10. Unsubscribe the wallpaper assigned to the second display, rescan — it falls back
    to mirroring the primary rather than going black.

**With one display only:**

1. The target picker is not visible.
2. Launch restore, apply, Next/Prev/Random, mute, and the scan-progress state all
   behave exactly as before.
3. Migration: launch with an existing flat snapshot in defaults and confirm the
   current wallpaper comes back as the primary's, with no visible difference.
4. Close the lid on an external-only setup and reopen it.

## Out of scope

- Per-display playlists or rotation schedules.
- Different wallpapers per Space.
- Mirrored-display detection (macOS reports mirrored screens as one `NSScreen`, so
  this needs nothing, but it is untested).
- A visual display-arrangement picker. The toolbar dropdown is the whole UI.
- Per-display volume. Audio stays a single primary-display concern.
- Per-display performance profiles or quality settings.

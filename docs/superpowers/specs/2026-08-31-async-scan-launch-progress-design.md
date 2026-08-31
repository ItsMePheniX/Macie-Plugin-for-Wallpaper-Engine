# Async Workshop Scan and Launch Progress

**Date:** 2026-08-31
**Status:** design

## The problem

Nothing appears on screen until the Workshop scan finishes.

`AppDelegate -startWithConfiguredPath` runs four steps strictly in order:

```objc
[self scanWallpaperEngineVideos];   // blocking, main thread
[self createDesktopWindow];
[self playFirstAvailableVideo];     // this is what calls -showGallery
[self setupPerformanceMonitor];
```

The scan is `fs::directory_iterator` over `workshop/content/431960`, and for every
subscribed wallpaper it reads and parses a `project.json` and then stats the video
file and the preview file. That is roughly three filesystem round trips plus one
JSON parse per wallpaper, all on the main thread before the run loop gets a chance
to draw anything. A library of a few hundred wallpapers on a cold cache — or on an
external drive, which is where large Steam libraries usually live — is seconds of a
bouncing Dock icon and no window.

Two separate delays are hiding in there, and they deserve separate answers:

1. **The window is late.** The gallery cannot be built because
   `MainWindowController -initWithAssetManager:videoRenderer:` calls `-loadVideos`
   in its initializer, so it assumes a fully-populated asset manager at
   construction time.
2. **The wallpaper is late.** `-playFirstAvailableVideo` looks the saved
   `kDefaultsLastWallpaperId` up in the scan results to find its video path, so the
   desktop stays blank until the scan lands — even though the app played that exact
   file thirty seconds ago and nothing about it has changed.

This is also the thing that forced "scan progress UI" onto the out-of-scope list of
the earlier UI/QOL design: there was no scan to report progress from.

## What changes, in one sentence

The scan moves to a background queue and reports progress; the desktop window, the
wallpaper, and the gallery window all appear before it finishes.

## Decisions

### Progress is reported, but cards arrive in one batch

The grid does not stream cards in as folders are parsed. Incremental
`-insertItemsAtIndexPaths:` would fight the sort — every insert re-sorts, so cards
visibly jump between positions — and it would force the count label, the sidebar
badges, and the collection membership to recompute per batch. `self.videos` is
documented as "never mutated after `-loadVideos`" and the whole controller leans on
that.

What the user actually wants from "progress" is knowing the app is working and
roughly how far along it is. So: a determinate progress bar in the grid area with a
real `137 of 240` count, and a single populate at the end. The scan reports counts,
not items.

### The scan counts folders first so the bar is determinate

`scanWallpaperEngine` makes one cheap pass with `directory_iterator` counting
subdirectories, reports that as the total, then makes the real pass. Enumerating
directory entries is the cheap half; reading and parsing a `project.json` per folder
is the expensive half. Paying the enumeration twice buys an honest `137 of 240`
instead of a spinner that could mean anything.

If a folder appears or disappears between the two passes the counts disagree
slightly. The wrapper clamps `scanned` to `total`, so the bar cannot overshoot.

### The progress panel is delayed by 250 ms

Most libraries scan in well under a second, and flashing a progress panel for 80 ms
is worse than showing nothing. The gallery enters a quiet scanning state
immediately — grid empty, no message — and only reveals the progress panel if the
scan is still running 250 ms later. A fast scan never shows it.

This matters for a second reason: `-updateEmptyState`'s default branch currently
says *"No wallpapers found — point the app at the steamapps folder…"*, which is
exactly the wrong thing to say while a scan is in flight. The scanning state has to
be checked before that switch, and it has to cover the quiet window too.

### The last wallpaper is restored from a persisted snapshot, before the scan

`applyWallpaper:` already writes `kDefaultsLastWallpaperId`. It will also write a
small snapshot dictionary — `id`, `title`, `path`, `preview`, `description` — which
is everything the renderer needs to start playing and everything `HeroPanelView`
reads. All strings, so it is plist-safe.

At launch, if the snapshot's `path` still exists on disk, the app creates the
renderer and starts playback immediately. The scan's completion reconciles: if the
saved id is absent from the library, or no snapshot was usable, the existing
`-playFirstAvailableVideo` fallback picks a wallpaper.

This is the change the user will actually feel. Relaunching the app puts the
wallpaper back instantly instead of after a scan, and the hero panel can show the
correct title and its disk-cached thumbnail — `ThumbnailCache` is keyed by id, so
the thumbnail is available from the snapshot alone.

The snapshot is a cache, not a source of truth. It is validated (file exists) on
every read, and the scan result always wins.

### The scan stays synchronous in C++; the wrapper owns the concurrency

`Macie::AssetManager::scanWallpaperEngine` becomes a **static** function that takes
a progress callback and touches no member state. `MacieAssetManagerWrapper` gets the
async entry point and does the queue hopping. Two reasons:

- **No data race.** `AssetManager::wallpapers` is a member vector that
  `getVideoWallpapers()` and `getWallpaperById()` read. If a background scan wrote
  it while the main thread read it, that is undefined behaviour. With a static scan
  returning a vector by value, the background queue only touches locals, and a new
  `adoptWallpapers()` publishes the result on the main thread. The live instance is
  only ever touched from one thread.
- **The C++ layer stays a pure function of the filesystem**, which is the part worth
  testing later.

The old instance method and `AppDelegate -scanWallpaperEngineVideos` both disappear
rather than lingering as an unused synchronous path.

## Units

| Unit | Change |
|---|---|
| `AssetManager.hpp` / `.mm` | `scanWallpaperEngine` becomes static, gains a progress callback; new `adoptWallpapers`; `parseProjectJson` drops to a file-static helper |
| `MacieAssetManagerWrapper` | new `-scanWallpaperEngineAsync:progress:completion:`; old sync method removed |
| `LastWallpaperSnapshot.h` / `.m` | new: save and load the validated last-played snapshot |
| `GalleryEmptyStateView` | new `-showProgressTitle:subtitle:progress:total:`, updating one reused `NSProgressIndicator` in place |
| `MainWindowController` | nullable renderer + `-attachVideoRenderer:`; `-beginScanProgress`, `-updateScanProgress:total:`, `-reloadFromAssetManager`; snapshot fallback for the hero; `-updateEmptyState` learns the scanning state; writes the snapshot on apply |
| `AppDelegate` | reordered launch, snapshot restore, async scan orchestration, generation guard |
| `Constants.h` / `.m` | one new key, `kDefaultsLastWallpaperSnapshot` |
| `CMakeLists.txt` | the two new files |

### `AssetManager` (C++)

```cpp
using ScanProgressCallback = std::function<void(size_t scanned, size_t total)>;

/// Scans a steamapps directory. Pure with respect to this class — touches no
/// member state, so it is safe to call from any thread. onProgress is invoked on
/// the calling thread once per folder examined.
static std::vector<WallpaperProject> scanWallpaperEngine(
    const std::string& steamappsPath,
    const ScanProgressCallback& onProgress = nullptr);

/// Replaces the stored list. Call from the thread that owns this instance.
void adoptWallpapers(std::vector<WallpaperProject> scanned);
```

`onProgress` fires for every folder examined, including ones that are skipped
because they are scene or web wallpapers — the bar tracks work done, not results
found, otherwise it would stall on a library with many non-video items.
`<functional>` joins the header's includes.

### `MacieAssetManagerWrapper`

```objc
/// Scans off the main thread. progress and completion are both delivered on the
/// main queue; progress is throttled, completion fires exactly once. The results
/// are published into the owned AssetManager before completion runs, so
/// -getVideoWallpapers is ready by the time it is called.
- (void)scanWallpaperEngineAsync:(const std::string &)steamappsPath
                        progress:(nullable void (^)(NSUInteger scanned, NSUInteger total))progress
                      completion:(void (^)(void))completion;
```

The `const std::string &` is copied into the block before dispatch, so the caller's
string does not have to outlive the scan. The scan runs on
`DISPATCH_QUEUE_PRIORITY_UTILITY` — it is I/O bound and must not contend with the
video renderer's work.

Progress is throttled in the wrapper: forwarded when `scanned % 16 == 0` or on the
final item. A 2000-wallpaper library would otherwise queue 2000 main-thread hops to
move a progress bar 2000 times.

### `GalleryEmptyStateView`

```objc
/// Shows a progress panel. Pass total == 0 for an indeterminate spinner.
/// Repeated calls update the existing bar rather than rebuilding the panel.
- (void)showProgressTitle:(NSString *)title
                 subtitle:(NSString *)subtitle
                 progress:(NSUInteger)completed
                    total:(NSUInteger)total;
```

The `NSProgressIndicator` is created lazily on first use and hidden by
`-showSymbol:title:subtitle:`, so the two states cannot both be visible. The symbol
image view is hidden in the progress state for the same reason.

### `MainWindowController`

```objc
/// Puts the grid into its scanning state. Safe to call before the window is shown.
- (void)beginScanProgress;
/// Feeds the scanning state new counts.
- (void)updateScanProgress:(NSUInteger)scanned total:(NSUInteger)total;
/// Leaves the scanning state and rebuilds everything from the asset manager.
- (void)reloadFromAssetManager;
/// Supplies the renderer when it did not exist at construction time.
- (void)attachVideoRenderer:(AVVideoRenderer *)renderer;
```

`-initWithAssetManager:videoRenderer:` takes a **nullable** renderer. Messages to
nil are no-ops and `updateMuteButton` reads `self.videoRenderer.isMuted` as NO, so
the nil window is already survivable; the initializer's `nonnull` annotation is what
changes.

`-reloadFromAssetManager` is `-loadVideos` made public, with the scanning flags
cleared first. `-loadVideos` stays as the implementation and is still called from
`init`, where it correctly produces an empty grid.

Two internal flags: `scanning`, set by `-beginScanProgress` and cleared by
`-reloadFromAssetManager`; and `scanProgressVisible`, set by the 250 ms
`dispatch_after` if `scanning` is still YES. Each of the three methods ends by
calling `-updateEmptyState`, which is the one place that decides what the grid area
shows. `-beginScanProgress` is idempotent: calling it again during a scan just
schedules a second grace timer that finds the flag already set.

`-updateEmptyState` gains a branch ahead of everything else:

```objc
if (self.filteredVideos.count > 0) { self.emptyState.hidden = YES; return; }

if (self.scanning) {
    // Quiet until the 250 ms grace period expires: a scan that finishes in 80 ms
    // should not flash a progress panel.
    if (!self.scanProgressVisible) { self.emptyState.hidden = YES; return; }
    [self.emptyState showProgressTitle:@"Reading your wallpaper library"
                             subtitle:@"137 of 240 folders read"
                             progress:self.scanScanned
                                total:self.scanTotal];
    return;
}
```

`-loadVideos` still runs from `init`, before `-showGallery` has had a chance to call
`-beginScanProgress`, so for an instant it computes the wrong empty state. Both
happen inside one run-loop turn, so nothing is drawn in between and nothing reaches
the screen.

`playingWallpaperId` moves up into `init` — it is read from `NSUserDefaults`, needs
no library, and the hero has to resolve PLAYING correctly before the scan lands.

The hero's fallback, at the end of `-loadVideos`:

```objc
NSDictionary *playing = [self videoForId:self.playingWallpaperId];
// Before the scan lands there is no library to look in, but the snapshot of the
// last-played wallpaper is enough to fill the hero. Only when the library is
// genuinely empty — otherwise a deleted wallpaper would come back from the dead.
if (!playing && self.videos.count == 0) playing = MacieLoadLastWallpaperSnapshot();
[self showInHero:playing];
```

`applyWallpaper:` gains one line next to its existing `kDefaultsLastWallpaperId`
write: `MacieSaveLastWallpaperSnapshot(video);`.

### `LastWallpaperSnapshot`

Two free functions, in their own unit so the validation rule has one home. Declared
inside `extern "C"` guards — both consumers are Objective-C++ translation units and
the definitions compile as C, which is the same linkage trap `DesignSystem.h` and
`SidebarView.h` already work around.

```objc
/// Persists the fields needed to restore this wallpaper before a scan completes.
void MacieSaveLastWallpaperSnapshot(NSDictionary *video);
/// Returns the saved snapshot, or nil if none was saved or its video file is gone.
NSDictionary *MacieLoadLastWallpaperSnapshot(void);
```

Stored under one new `kDefaultsLastWallpaperSnapshot` key. The loader validates
`path` with `-fileExistsAtPath:` and returns nil on a miss, so an uninstalled
wallpaper cannot be restored.

### `AppDelegate`

```objc
- (void)startWithConfiguredPath {
    [self createDesktopWindow];             // cheap, needs no library
    [self restoreLastWallpaperFromSnapshot]; // may create the renderer and start playback
    [self beginWallpaperScan];               // async
    [self showGallery];                      // opens now, in the scanning state
    [self setupPerformanceMonitor];
}
```

`-showGallery` calls `-beginScanProgress` on the controller when a scan is in
flight, which covers both orderings: the gallery built before a scan starts, and a
gallery reopened during one.

`-restoreLastWallpaperFromSnapshot` restores the saved mute state exactly the way
`-playFirstAvailableVideo` does — unmuting when `kDefaultsLastMuteState` is stored
and false, defaulting to muted otherwise. Skipping that would make an early-restored
wallpaper come back with sound the user had turned off. The shared logic moves into
one `-restoreMuteState` helper so the two paths cannot drift.

`-beginWallpaperScan` increments a `scanGeneration` counter and captures it. Both
the progress and completion blocks return early if `self.scanGeneration` has moved
on, so a second scan started by a folder change cannot have its results overwritten
by the first one finishing late.

Completion:

```objc
[self.galleryController reloadFromAssetManager];

// First launch, or the snapshot pointed at something no longer installed.
if (!self.videoRenderer) [self playFirstAvailableVideo];
```

`-playFirstAvailableVideo` keeps its current job of choosing and starting a
wallpaper, minus the `-showGallery` call at its end — the gallery is already up by
the time it can run. It also writes the snapshot alongside the id it already
persists, and calls `-attachVideoRenderer:` so the gallery gets the renderer it was
constructed without.

`-reloadWallpapers` stops closing the gallery window. It keeps the asset manager
rather than replacing it — the gallery holds its own reference to the wrapper from
`-init`, so a replacement would leave the grid reading a stale instance, and
`-adoptWallpapers` already swaps the whole list at once so nothing from the previous
folder survives. Staleness is handled inside the wrapper's own generation guard,
which also covers the harder case of an older, slower scan finishing last. The
method calls `-beginScanProgress` on the existing controller and rescans; on
completion the grid reloads in place, and a wallpaper is only re-chosen if the
playing one is no longer in the library. Closing and rebuilding the window was only
ever a way to force a reload.

One guard sits in front of that: if there is no desktop window yet, the reload was
reached from Cmd+, in the welcome window, so there is nothing to reload and the
method runs `-startWithConfiguredPath` as a first start instead.

## Data flow

```
launch
 ├─ desktop window created                    (immediate)
 ├─ snapshot valid? → renderer + playback      (immediate)
 ├─ gallery window shown, scanning state       (immediate)
 └─ background queue
     ├─ count folders            → total
     ├─ parse each project.json  → progress (main queue, every 16th)
     └─ done
         ├─ adoptWallpapers                    (main queue)
         ├─ gallery -reloadFromAssetManager
         └─ no renderer yet? → -playFirstAvailableVideo
```

## Error handling

| Case | Behaviour |
|---|---|
| Workshop path missing | Scan returns empty; completion still runs; the existing "No wallpapers found" empty state appears with its pointer to Settings |
| Snapshot path gone | Loader returns nil; launch proceeds without early playback; the scan picks a wallpaper |
| Snapshot path present but unplayable | `loadAndPlayVideo:` fails, the renderer is released back to nil, and the scan's completion falls through to `-playFirstAvailableVideo` |
| Second scan during the first | Generation guard drops the stale progress and completion |
| Gallery closed mid-scan | The controller is retained by `AppDelegate`, so the reload still lands and the window is correct when reopened |
| Zero folders in the workshop directory | Total is 0, the progress panel never appears (it is delayed 250 ms and the scan ends immediately), and the empty state takes over |

## Testing

No automated test harness exists in this project, so this is a manual list.

- Launch with a large library on an external drive: the gallery window and the
  progress bar should appear immediately, and the bar should advance.
- Relaunch: the wallpaper should be on the desktop before the grid populates, and
  the hero should already name it as PLAYING with its thumbnail.
- Launch with a small library: no progress panel should flash.
- First launch through the welcome window: gallery opens empty and scanning, then
  populates and starts playing.
- Change Steam folder while running: the window stays open, re-enters the scanning
  state, and repopulates.
- Point at an invalid folder: the "No wallpapers found" state, not a stuck bar.
- Delete the last-played wallpaper from disk, then relaunch: no early playback, and
  the scan chooses a different wallpaper without an error dialog.
- Change the folder twice in quick succession: the grid matches the second folder.

## Out of scope

- Streaming cards into the grid as they are parsed
- Cancelling a scan in progress
- Watching the workshop directory for changes (FSEvents) and rescanning live
- Caching the scan result across launches to skip the scan entirely
- Multi-monitor support, which remains the separate piece of work it was

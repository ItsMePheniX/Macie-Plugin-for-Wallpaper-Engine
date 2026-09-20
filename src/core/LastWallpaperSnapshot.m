//
//  LastWallpaperSnapshot.m
//  MacieWallpaper - Restoring each display's wallpaper before a scan finishes
//
//  Created on 2026-08-31.
//

#import "LastWallpaperSnapshot.h"
#import "Constants.h"

/// Only these keys are stored. The derived search haystacks and the tag array are
/// rebuilt by the scan, and a snapshot that carried them would go stale.
static NSArray<NSString *> *SnapshotKeys(void) {
    return @[@"id", @"title", @"path", @"preview", @"description"];
}

/// The whole display-key → snapshot map, or nil. Not validated beyond its type: the
/// per-entry checks belong with the entry, since one corrupt display must not take the
/// others down with it.
static NSDictionary *StoredSnapshotMap(void) {
    return [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:kDefaultsLastWallpaperSnapshot];
}

/// YES if `stored` is the pre-multi-display format: one flat snapshot rather than a map
/// of them. A top-level string `path` is the tell — no display key can produce one,
/// since every key this app generates is prefixed with uuid-, hw- or transient-.
static BOOL IsFlatSnapshot(NSDictionary *stored) {
    return [stored[@"path"] isKindOfClass:[NSString class]];
}

static NSDictionary *_Nullable EntryForDisplayKey(NSString *displayKey) {
    if (!displayKey.length) return nil;

    NSDictionary *stored = StoredSnapshotMap();
    if (!stored || IsFlatSnapshot(stored)) return nil;

    NSDictionary *entry = stored[displayKey];
    return [entry isKindOfClass:[NSDictionary class]] ? entry : nil;
}

/// Keeps only the storable keys, and only those whose values are strings: a stray
/// object anywhere in the tree would make the whole defaults write fail.
static NSDictionary *SnapshotEntryFromVideo(NSDictionary *video) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    for (NSString *key in SnapshotKeys()) {
        NSString *value = video[key];
        if ([value isKindOfClass:[NSString class]]) entry[key] = value;
    }
    return [entry copy];
}

static void WriteEntry(NSDictionary *_Nullable entry, NSString *displayKey) {
    NSDictionary *stored = StoredSnapshotMap();

    // A flat snapshot is discarded rather than merged into: migration has either
    // already adopted it or decided it cannot be attributed to any display.
    NSMutableDictionary *map = (stored && !IsFlatSnapshot(stored))
        ? [stored mutableCopy]
        : [NSMutableDictionary dictionary];

    map[displayKey] = entry;
    [[NSUserDefaults standardUserDefaults] setObject:[map copy]
                                             forKey:kDefaultsLastWallpaperSnapshot];
}

void MacieSaveLastWallpaperSnapshot(NSDictionary *video, NSString *displayKey) {
    // A display with no stable identity has nowhere to store anything. Writing under a
    // placeholder key would hand its wallpaper to whichever display later claimed it.
    if (!displayKey.length) return;

    NSString *wallpaperId = video[@"id"];
    NSString *path        = video[@"path"];
    if (!wallpaperId.length || !path.length) return;

    WriteEntry(SnapshotEntryFromVideo(video), displayKey);
}

NSDictionary *MacieLoadLastWallpaperSnapshot(NSString *displayKey) {
    NSDictionary *entry = EntryForDisplayKey(displayKey);
    if (!entry) return nil;

    NSString *wallpaperId = entry[@"id"];
    NSString *path        = entry[@"path"];
    if (![wallpaperId isKindOfClass:[NSString class]] || !wallpaperId.length) return nil;
    if (![path isKindOfClass:[NSString class]] || !path.length) return nil;

    // An uninstalled wallpaper must not come back from the dead. The assignment itself
    // survives this — see MacieLoadAssignedWallpaperId — so a wallpaper on a volume
    // that happens to be unmounted is not forgotten, merely unplayable right now.
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

    // Filled out so callers can read the same keys they would from a library entry
    // without checking for nil on each one.
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in SnapshotKeys()) {
        NSString *value = entry[key];
        snapshot[key] = [value isKindOfClass:[NSString class]] ? value : @"";
    }
    snapshot[@"id"]   = wallpaperId;
    snapshot[@"path"] = path;

    return [snapshot copy];
}

NSString *MacieLoadAssignedWallpaperId(NSString *displayKey) {
    NSString *wallpaperId = EntryForDisplayKey(displayKey)[@"id"];
    if (![wallpaperId isKindOfClass:[NSString class]] || !wallpaperId.length) return nil;
    return wallpaperId;
}

void MacieMigrateLastWallpaperSnapshotIfNeeded(NSString *primaryDisplayKey) {
    // Nothing can be attributed without a persistable primary display. Leaving the old
    // value untouched means the migration is simply retried on a later launch, which is
    // better than throwing the user's wallpaper away.
    if (!primaryDisplayKey.length) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *stored = StoredSnapshotMap();

    if (stored && IsFlatSnapshot(stored)) {
        WriteEntry(SnapshotEntryFromVideo(stored), primaryDisplayKey);
        return;
    }

    // Installs from before snapshots existed have only the bare id. There is no path to
    // play from, so this cannot make launch fast, but recording the id keeps the
    // assignment: the post-scan reconcile resolves it against the scanned library.
    //
    // Writing the entry is what makes this run once — from here on the map answers for
    // this display. kDefaultsLastWallpaperId is deliberately left in place rather than
    // deleted; it is inert once the map has an entry, and removing a user's stored data
    // to tidy up is not worth the risk of getting the order wrong.
    if (EntryForDisplayKey(primaryDisplayKey)) return;

    NSString *legacyId = [defaults stringForKey:kDefaultsLastWallpaperId];
    if (!legacyId.length) return;

    WriteEntry(@{@"id": legacyId}, primaryDisplayKey);
}

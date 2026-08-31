//
//  LastWallpaperSnapshot.m
//  MacieWallpaper - Restoring the last-played wallpaper before a scan finishes
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

void MacieSaveLastWallpaperSnapshot(NSDictionary *video) {
    NSString *wallpaperId = video[@"id"];
    NSString *path        = video[@"path"];
    if (!wallpaperId.length || !path.length) return;

    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in SnapshotKeys()) {
        NSString *value = video[key];
        // Everything stored has to be a string: a stray object would make the whole
        // defaults write fail.
        if ([value isKindOfClass:[NSString class]]) snapshot[key] = value;
    }

    [[NSUserDefaults standardUserDefaults] setObject:[snapshot copy]
                                             forKey:kDefaultsLastWallpaperSnapshot];
}

NSDictionary *MacieLoadLastWallpaperSnapshot(void) {
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults]
        dictionaryForKey:kDefaultsLastWallpaperSnapshot];
    if (!stored) return nil;

    NSString *wallpaperId = stored[@"id"];
    NSString *path        = stored[@"path"];
    if (![wallpaperId isKindOfClass:[NSString class]] || !wallpaperId.length) return nil;
    if (![path isKindOfClass:[NSString class]] || !path.length) return nil;

    // An uninstalled wallpaper must not come back from the dead.
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

    // Filled out so callers can read the same keys they would from a library entry
    // without checking for nil on each one.
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in SnapshotKeys()) {
        NSString *value = stored[key];
        snapshot[key] = [value isKindOfClass:[NSString class]] ? value : @"";
    }
    snapshot[@"id"]   = wallpaperId;
    snapshot[@"path"] = path;

    return [snapshot copy];
}

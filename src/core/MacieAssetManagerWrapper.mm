//
//  MacieAssetManagerWrapper.mm
//  MacieWallpaper - Typed Objective-C++ Wrapper for AssetManager
//
//  Created on 2026-07-31.
//

#import "MacieAssetManagerWrapper.h"

@interface MacieAssetManagerWrapper () {
    std::unique_ptr<Macie::AssetManager> _assetManager;
}
@end

@implementation MacieAssetManagerWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        _assetManager = std::make_unique<Macie::AssetManager>();
    }
    return self;
}

- (Macie::AssetManager *)assetManager {
    return _assetManager.get();
}

- (std::vector<Macie::WallpaperProject>)scanWallpaperEngine:(const std::string &)steamappsPath {
    return _assetManager->scanWallpaperEngine(steamappsPath);
}

- (std::vector<Macie::WallpaperProject>)getVideoWallpapers {
    return _assetManager->getVideoWallpapers();
}

- (NSArray<NSDictionary *> *)videoWallpaperDictionaries {
    std::vector<Macie::WallpaperProject> wallpapers = _assetManager->getVideoWallpapers();

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:wallpapers.size()];
    for (const auto &w : wallpapers) {
        // stringWithUTF8String: returns nil on malformed bytes, and a nil value in a
        // dictionary literal is fatal — so each one is defaulted.
        NSString *wallpaperId = [NSString stringWithUTF8String:w.id.c_str()]            ?: @"";
        NSString *title       = [NSString stringWithUTF8String:w.title.c_str()]         ?: @"";
        NSString *path        = [NSString stringWithUTF8String:w.videoFilePath.c_str()] ?: @"";
        NSString *preview     = [NSString stringWithUTF8String:w.previewPath.c_str()]   ?: @"";
        NSString *description = [NSString stringWithUTF8String:w.description.c_str()]   ?: @"";

        NSMutableArray<NSString *> *tags = [NSMutableArray arrayWithCapacity:w.tags.size()];
        for (const auto &t : w.tags) {
            NSString *tag = [NSString stringWithUTF8String:t.c_str()];
            if (tag.length) [tags addObject:tag];
        }

        [result addObject:@{
            @"id":          wallpaperId,
            @"title":       title,
            @"path":        path,
            @"preview":     preview,
            @"description": description,
            @"tags":        [tags copy]
        }];
    }

    return [result copy];
}

- (std::optional<Macie::WallpaperProject>)getWallpaperById:(const std::string &)wallpaperId {
    return _assetManager->getWallpaperById(wallpaperId);
}

// unique_ptr destructor is called automatically by ARC dealloc — no manual cleanup needed.

@end

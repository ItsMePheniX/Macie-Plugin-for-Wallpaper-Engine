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

- (void)scanWallpaperEngineAsync:(const std::string &)steamappsPath
                        progress:(void (^)(NSUInteger scanned, NSUInteger total))progress
                      completion:(void (^)(void))completion {
    // Capture path by value so it outlives this stack frame on the background queue.
    std::string pathCopy = steamappsPath;

    // Keep a weak self so the block does not extend the wrapper's lifetime.
    __weak MacieAssetManagerWrapper *weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        MacieAssetManagerWrapper *strongSelf = weakSelf;
        if (!strongSelf) return;

        // Run the synchronous scan. The C++ layer populates its internal cache;
        // we do not need the return value here — callers use -videoWallpaperDictionaries.
        strongSelf->_assetManager->scanWallpaperEngine(pathCopy);

        // Report a single "done" progress tick so the UI spinner advances.
        NSUInteger total = (NSUInteger)strongSelf->_assetManager->getVideoWallpapers().size();
        if (progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progress(total, total);
            });
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

@end

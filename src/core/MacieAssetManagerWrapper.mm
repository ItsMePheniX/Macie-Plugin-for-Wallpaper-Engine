//
//  MacieAssetManagerWrapper.mm
//  MacieWallpaper - Typed Objective-C++ Wrapper for AssetManager
//
//  Created on 2026-07-31.
//

#import "MacieAssetManagerWrapper.h"

/// How many folders pass between progress reports. The bar moves a few pixels per
/// wallpaper at most, so reporting every one just floods the main queue.
static const size_t kProgressReportInterval = 16;

@interface MacieAssetManagerWrapper () {
    std::unique_ptr<Macie::AssetManager> _assetManager;
}

/// Bumped by every -scanWallpaperEngineAsync: call. A scan whose generation is no
/// longer current publishes nothing and reports nothing: changing the Steam folder
/// twice in quick succession must not let the first scan's results land last.
@property (assign, nonatomic) NSUInteger scanGeneration;

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

- (void)scanWallpaperEngineAsync:(const std::string &)steamappsPath
                        progress:(void (^)(NSUInteger scanned, NSUInteger total))progress
                      completion:(void (^)(void))completion {
    // Copied before dispatch: the caller's string does not have to outlive the scan.
    std::string path = steamappsPath;

    self.scanGeneration++;
    const NSUInteger generation = self.scanGeneration;

    // The scan is I/O bound and must not contend with the video renderer's work.
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);

    __weak MacieAssetManagerWrapper *weakSelf = self;
    dispatch_async(queue, ^{
        Macie::AssetManager::ScanProgressCallback onProgress = nullptr;
        if (progress) {
            onProgress = [progress, weakSelf, generation](size_t scanned, size_t total) {
                // Folders can appear between the counting pass and the parsing pass,
                // so clamp rather than letting the bar overshoot.
                size_t shown = (total > 0 && scanned > total) ? total : scanned;
                BOOL milestone = (shown % kProgressReportInterval == 0) || (shown == total);
                if (!milestone) return;

                dispatch_async(dispatch_get_main_queue(), ^{
                    MacieAssetManagerWrapper *strongSelf = weakSelf;
                    if (!strongSelf || strongSelf.scanGeneration != generation) return;
                    progress((NSUInteger)shown, (NSUInteger)total);
                });
            };
        }

        // Static and member-free, so nothing the main thread might be reading is
        // touched here. The results are published on the main queue below.
        std::vector<Macie::WallpaperProject> found =
            Macie::AssetManager::scanWallpaperEngine(path, onProgress);

        // __block so the vector can be moved into the main-queue block rather than
        // copied — a large library is a lot of strings.
        __block std::vector<Macie::WallpaperProject> results = std::move(found);
        dispatch_async(dispatch_get_main_queue(), ^{
            MacieAssetManagerWrapper *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.scanGeneration != generation) return;

            strongSelf.assetManager->adoptWallpapers(std::move(results));
            if (completion) completion();
        });
    });
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

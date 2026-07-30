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

// unique_ptr destructor is called automatically by ARC dealloc — no manual cleanup needed.

@end

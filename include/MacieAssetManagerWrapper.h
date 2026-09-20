//
//  MacieAssetManagerWrapper.h
//  MacieWallpaper - Typed Objective-C++ Wrapper for AssetManager
//
//  Owns a Macie::AssetManager via std::unique_ptr, eliminating all
//  manual new/delete calls and void* casting from the Obj-C layer.
//

#pragma once

#import <Foundation/Foundation.h>
#include "AssetManager.hpp"
#include <memory>

NS_ASSUME_NONNULL_BEGIN

@interface MacieAssetManagerWrapper : NSObject

/// Direct access to the owned C++ AssetManager.
@property (nonatomic, readonly) Macie::AssetManager *assetManager;

/// Scan a steamapps directory and return all video wallpapers found.
- (std::vector<Macie::WallpaperProject>)scanWallpaperEngine:(const std::string &)steamappsPath;

/// Return the cached list of video wallpapers from the last scan.
- (std::vector<Macie::WallpaperProject>)getVideoWallpapers;

/// The same list as plain dictionaries, keyed `id`, `title`, `path`, `preview`,
/// `description` and `tags`.
///
/// This is the one place a WallpaperProject becomes an Objective-C object, so that
/// everything downstream of the library — the display manager especially — can stay out of
/// Objective-C++ entirely. Callers that need derived fields add them on top.
- (NSArray<NSDictionary *> *)videoWallpaperDictionaries;

/// Find a specific wallpaper by its workshop folder ID.
/// Returns an empty optional if no wallpaper with that ID was found in the last scan.
- (std::optional<Macie::WallpaperProject>)getWallpaperById:(const std::string &)wallpaperId;

/// Asynchronously scan a steamapps directory.
/// `progress` is called on the main queue as folders are processed (scanned, total).
/// `completion` is called on the main queue when the scan finishes.
- (void)scanWallpaperEngineAsync:(const std::string &)steamappsPath
                        progress:(void (^)(NSUInteger scanned, NSUInteger total))progress
                      completion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END

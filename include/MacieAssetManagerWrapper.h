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

/// Scans a steamapps directory off the main thread.
///
/// `progress` and `completion` are both delivered on the main queue. Progress is
/// throttled — a large library would otherwise queue thousands of main-thread hops
/// to move one bar — and reports folders examined out of folders found, so it
/// advances even through wallpapers this app cannot use. `completion` fires exactly
/// once, after the results have been published, so -getVideoWallpapers is ready by
/// the time it runs.
- (void)scanWallpaperEngineAsync:(const std::string &)steamappsPath
                        progress:(nullable void (^)(NSUInteger scanned, NSUInteger total))progress
                      completion:(void (^)(void))completion;

/// Return the cached list of video wallpapers from the last scan.
- (std::vector<Macie::WallpaperProject>)getVideoWallpapers;

/// Find a specific wallpaper by its workshop folder ID.
/// Returns an empty optional if no wallpaper with that ID was found in the last scan.
- (std::optional<Macie::WallpaperProject>)getWallpaperById:(const std::string &)wallpaperId;

@end

NS_ASSUME_NONNULL_END

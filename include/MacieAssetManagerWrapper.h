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

/// Find a specific wallpaper by its workshop folder ID.
/// Returns an empty optional if no wallpaper with that ID was found in the last scan.
- (std::optional<Macie::WallpaperProject>)getWallpaperById:(const std::string &)wallpaperId;

@end

NS_ASSUME_NONNULL_END

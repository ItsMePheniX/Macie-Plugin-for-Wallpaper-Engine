//
//  WallpaperMetadataCache.h
//  MacieWallpaper - Video Metadata Cache
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolution, duration and file size for one wallpaper video.
@interface WallpaperMetadata : NSObject

@property (nonatomic, readonly) NSInteger      pixelWidth;
@property (nonatomic, readonly) NSInteger      pixelHeight;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) long long      fileSize;

/// Compact form for gallery cards, e.g. @"4K • 0:12".
@property (nonatomic, readonly) NSString *shortLabel;
/// Full form for the hero panel, e.g. @"3840 × 2160 • 0:12 • 24.3 MB".
@property (nonatomic, readonly) NSString *longLabel;

@end

/// Reads video metadata with AVFoundation and remembers it in memory and in a
/// plist, so scrolling the gallery never re-opens the same asset twice.
///
/// Entries are keyed by wallpaper ID and validated against the video's current
/// file size, so replacing a workshop item invalidates its entry automatically.
@interface WallpaperMetadataCache : NSObject

+ (instancetype)sharedCache;

/// Non-blocking lookup, safe from the main thread. Returns nil when the video
/// has not been inspected yet.
- (nullable WallpaperMetadata *)cachedMetadataForId:(NSString *)wallpaperId;

/// Loads metadata, reading the asset only when the cached entry is missing or
/// stale. `completion` is always called on the main queue.
- (void)metadataForWallpaperId:(NSString *)wallpaperId
                     videoPath:(NSString *)videoPath
                    completion:(void (^)(WallpaperMetadata * _Nullable metadata))completion;

/// Drops both the in-memory and on-disk entries.
- (void)clearCache;

@end

NS_ASSUME_NONNULL_END

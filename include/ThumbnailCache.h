//
//  ThumbnailCache.h
//  MacieWallpaper - Thumbnail Cache Manager
//
//  Created on 2026-02-15.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Two-layer thumbnail cache (NSCache in memory, PNG files on disk).
///
/// Generation is implemented entirely with ImageIO and AVFoundation, so every
/// method on this class is safe to call from a background queue. Nothing here
/// touches NSGraphicsContext or -[NSImage lockFocus], which are main-thread only.
@interface ThumbnailCache : NSObject

+ (instancetype)sharedCache;

/// Non-blocking lookup. Returns nil when nothing has been generated yet.
- (nullable NSImage *)cachedThumbnailForId:(NSString *)wallpaperId;

/// Returns a cached thumbnail or generates one, in this order:
///   1. the cache (memory, then disk)
///   2. `previewPath`, when supplied and readable
///   3. a `preview.*` file sitting next to the video
///   4. a frame grabbed one second into the video itself
///
/// Blocks while generating, so call it off the main thread.
- (nullable NSImage *)thumbnailForWallpaperId:(NSString *)wallpaperId
                                  previewPath:(nullable NSString *)previewPath
                                    videoPath:(nullable NSString *)videoPath;

// Cache management
- (void)clearCache;
- (NSUInteger)cacheSize;
- (NSString *)cachePath;

@end

NS_ASSUME_NONNULL_END

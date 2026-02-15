//
//  ThumbnailCache.h
//  MacieWallpaper - Thumbnail Cache Manager
//
//  Created on 2026-02-15.
//

#import <Cocoa/Cocoa.h>

@interface ThumbnailCache : NSObject

+ (instancetype)sharedCache;

// Cache operations
- (NSImage *)cachedThumbnailForId:(NSString *)wallpaperId;
- (void)cacheThumbnail:(NSImage *)image forId:(NSString *)wallpaperId;
- (NSImage *)thumbnailForVideoPath:(NSString *)videoPath wallpaperId:(NSString *)wallpaperId;
- (NSImage *)thumbnailForPreviewPath:(NSString *)previewPath wallpaperId:(NSString *)wallpaperId;

// Cache management
- (void)clearCache;
- (NSUInteger)cacheSize;
- (NSString *)cachePath;

// Background pre-generation
- (void)preGenerateThumbnailsForVideos:(NSArray<NSDictionary *> *)videos;

@end

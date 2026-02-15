//
//  ThumbnailCache.mm
//  MacieWallpaper - Thumbnail Cache Manager
//
//  Created on 2026-02-15.
//

#import "ThumbnailCache.h"
#import "Constants.h"
#import <AVFoundation/AVFoundation.h>

@interface ThumbnailCache ()
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, strong) NSCache *memoryCache;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@end

@implementation ThumbnailCache

+ (instancetype)sharedCache {
    static ThumbnailCache *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ThumbnailCache alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupCacheDirectory];
        self.memoryCache = [[NSCache alloc] init];
        self.memoryCache.countLimit = 100;
        self.cacheQueue = dispatch_queue_create("com.maciewallpaper.thumbnailcache", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)setupCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = paths.firstObject;
    self.cacheDirectory = [[cachesDir stringByAppendingPathComponent:kCacheDirectoryName]
                           stringByAppendingPathComponent:kThumbnailCacheSubdir];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:self.cacheDirectory]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:self.cacheDirectory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:&error];
    }
}

- (NSString *)cachePath {
    return self.cacheDirectory;
}

- (NSString *)cachePathForId:(NSString *)wallpaperId {
    return [self.cacheDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.png", wallpaperId]];
}

#pragma mark - Cache Operations

- (NSImage *)cachedThumbnailForId:(NSString *)wallpaperId {
    // Check memory cache first
    NSImage *cachedImage = [self.memoryCache objectForKey:wallpaperId];
    if (cachedImage) {
        return cachedImage;
    }
    
    // Check disk cache
    NSString *cachePath = [self cachePathForId:wallpaperId];
    if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:cachePath];
        if (image) {
            [self.memoryCache setObject:image forKey:wallpaperId];
            return image;
        }
    }
    
    return nil;
}

- (void)cacheThumbnail:(NSImage *)image forId:(NSString *)wallpaperId {
    if (!image || !wallpaperId) return;
    
    // Add to memory cache
    [self.memoryCache setObject:image forKey:wallpaperId];
    
    // Save to disk asynchronously
    dispatch_async(self.cacheQueue, ^{
        NSString *cachePath = [self cachePathForId:wallpaperId];
        NSData *imageData = [self pngDataFromImage:image];
        if (imageData) {
            [imageData writeToFile:cachePath atomically:YES];
        }
    });
}

- (NSData *)pngDataFromImage:(NSImage *)image {
    if (!image) return nil;
    
    NSBitmapImageRep *bitmapRep = nil;
    
    // Get bitmap representation
    for (NSImageRep *rep in image.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmapRep = (NSBitmapImageRep *)rep;
            break;
        }
    }
    
    if (!bitmapRep) {
        // Create bitmap representation from image
        NSSize size = image.size;
        bitmapRep = [[NSBitmapImageRep alloc]
                     initWithBitmapDataPlanes:NULL
                     pixelsWide:(NSInteger)size.width
                     pixelsHigh:(NSInteger)size.height
                     bitsPerSample:8
                     samplesPerPixel:4
                     hasAlpha:YES
                     isPlanar:NO
                     colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                     bitsPerPixel:0];
        
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmapRep];
        [NSGraphicsContext setCurrentContext:context];
        [image drawInRect:NSMakeRect(0, 0, size.width, size.height)
                 fromRect:NSZeroRect
                operation:NSCompositingOperationCopy
                 fraction:1.0];
        [NSGraphicsContext restoreGraphicsState];
    }
    
    return [bitmapRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

#pragma mark - Thumbnail Generation

- (NSImage *)thumbnailForVideoPath:(NSString *)videoPath wallpaperId:(NSString *)wallpaperId {
    // Check cache first
    NSImage *cached = [self cachedThumbnailForId:wallpaperId];
    if (cached) {
        return cached;
    }
    
    // Generate from video
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenerator.appliesPreferredTrackTransform = YES;
    imageGenerator.maximumSize = CGSizeMake(kThumbnailWidth * 2, kThumbnailHeight * 2);
    
    CMTime time = CMTimeMakeWithSeconds(1.0, 600);
    NSError *error = nil;
    CGImageRef cgImage = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:&error];
    
    if (error || !cgImage) {
        return nil;
    }
    
    NSImage *thumbnail = [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(kThumbnailWidth, kThumbnailHeight)];
    CGImageRelease(cgImage);
    
    // Cache the generated thumbnail
    [self cacheThumbnail:thumbnail forId:wallpaperId];
    
    return thumbnail;
}

- (NSImage *)thumbnailForPreviewPath:(NSString *)previewPath wallpaperId:(NSString *)wallpaperId {
    // Check cache first
    NSImage *cached = [self cachedThumbnailForId:wallpaperId];
    if (cached) {
        return cached;
    }
    
    // Load from preview image
    NSImage *preview = [[NSImage alloc] initWithContentsOfFile:previewPath];
    if (!preview) {
        return nil;
    }
    
    // Resize to thumbnail size
    NSImage *thumbnail = [[NSImage alloc] initWithSize:NSMakeSize(kThumbnailWidth, kThumbnailHeight)];
    [thumbnail lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [preview drawInRect:NSMakeRect(0, 0, kThumbnailWidth, kThumbnailHeight)
               fromRect:NSZeroRect
              operation:NSCompositingOperationCopy
               fraction:1.0];
    [thumbnail unlockFocus];
    
    // Cache the thumbnail
    [self cacheThumbnail:thumbnail forId:wallpaperId];
    
    return thumbnail;
}

#pragma mark - Background Pre-generation

- (void)preGenerateThumbnailsForVideos:(NSArray<NSDictionary *> *)videos {
    dispatch_async(self.cacheQueue, ^{
        NSInteger generated = 0;
        NSInteger skipped = 0;
        
        for (NSDictionary *video in videos) {
            NSString *wallpaperId = video[@"id"];
            NSString *videoPath = video[@"path"];
            
            // Skip if already cached
            if ([self cachedThumbnailForId:wallpaperId]) {
                skipped++;
                continue;
            }
            
            // Try to generate from preview.jpg first (faster)
            NSString *wallpaperDir = [videoPath stringByDeletingLastPathComponent];
            NSString *previewPath = [wallpaperDir stringByAppendingPathComponent:@"preview.jpg"];
            
            NSImage *thumbnail = nil;
            if ([[NSFileManager defaultManager] fileExistsAtPath:previewPath]) {
                thumbnail = [self thumbnailForPreviewPath:previewPath wallpaperId:wallpaperId];
            }
            
            // Fall back to video frame extraction
            if (!thumbnail && videoPath) {
                thumbnail = [self thumbnailForVideoPath:videoPath wallpaperId:wallpaperId];
            }
            
            if (thumbnail) {
                generated++;
            }
        }
    });
}

#pragma mark - Cache Management

- (void)clearCache {
    // Clear memory cache
    [self.memoryCache removeAllObjects];
    
    // Clear disk cache
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.cacheDirectory error:&error];
    
    if (error) {
        return;
    }
    
    NSInteger deleted = 0;
    for (NSString *file in files) {
        NSString *filePath = [self.cacheDirectory stringByAppendingPathComponent:file];
        if ([fileManager removeItemAtPath:filePath error:nil]) {
            deleted++;
        }
    }
}

- (NSUInteger)cacheSize {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.cacheDirectory error:&error];
    
    if (error) {
        return 0;
    }
    
    NSUInteger totalSize = 0;
    for (NSString *file in files) {
        NSString *filePath = [self.cacheDirectory stringByAppendingPathComponent:file];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:filePath error:nil];
        totalSize += [attributes fileSize];
    }
    
    return totalSize;
}

@end

//
//  ThumbnailCache.mm
//  MacieWallpaper - Thumbnail Cache Manager
//
//  Created on 2026-02-15.
//

#import "ThumbnailCache.h"
#import "Constants.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

/// Wallpaper Engine writes a preview image next to project.json, but the
/// extension varies and older items omit the "preview" key entirely.
static NSArray<NSString *> *FallbackPreviewNames(void) {
    return @[@"preview.jpg", @"preview.jpeg", @"preview.png", @"preview.gif"];
}

/// Longest edge we ask ImageIO / AVFoundation for. 2x the display size keeps
/// thumbnails crisp on Retina without caching full-resolution frames.
static CGFloat MaxThumbnailPixelSize(void) {
    return MAX(kThumbnailWidth, kThumbnailHeight) * 2.0;
}

/// Wraps a CGImage in an NSImage sized to its own pixel dimensions, so the
/// aspect ratio survives (the image views scale proportionally).
static NSImage *ImageFromCGImage(CGImageRef cgImage) {
    if (!cgImage) return nil;
    NSSize size = NSMakeSize(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    return [[NSImage alloc] initWithCGImage:cgImage size:size];
}

@interface ThumbnailCache ()
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *memoryCache;
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
        if (![fileManager createDirectoryAtPath:self.cacheDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&error]) {
            NSLog(@"ThumbnailCache: could not create cache directory: %@", error.localizedDescription);
        }
    }
}

- (NSString *)cachePath {
    return self.cacheDirectory;
}

- (NSString *)cachePathForId:(NSString *)wallpaperId {
    // IDs are workshop folder names, but sanitise anyway so a stray separator
    // can never send a write outside the cache directory.
    NSString *safeId = [[wallpaperId stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                        stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    return [self.cacheDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.png", safeId]];
}

#pragma mark - Cache Operations

- (NSImage *)cachedThumbnailForId:(NSString *)wallpaperId {
    if (wallpaperId.length == 0) return nil;

    NSImage *cachedImage = [self.memoryCache objectForKey:wallpaperId];
    if (cachedImage) {
        return cachedImage;
    }

    NSString *cachePath = [self cachePathForId:wallpaperId];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        return nil;
    }

    NSImage *image = [self loadImageFromFile:cachePath];
    if (image) {
        [self.memoryCache setObject:image forKey:wallpaperId];
    }
    return image;
}

/// Decodes an image file via ImageIO. Thread-safe, unlike drawing into an NSImage.
- (NSImage *)loadImageFromFile:(NSString *)path {
    CGImageSourceRef source = CGImageSourceCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!cgImage) return nil;

    NSImage *image = ImageFromCGImage(cgImage);
    CGImageRelease(cgImage);
    return image;
}

/// Encodes a CGImage to PNG on disk via ImageIO — no AppKit drawing involved.
- (BOOL)writeCGImage:(CGImageRef)cgImage toPath:(NSString *)path {
    if (!cgImage) return NO;

    // UTTypePNG rather than the kUTTypePNG constant, which is deprecated as of macOS 12.
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path],
        (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    if (!destination) return NO;

    CGImageDestinationAddImage(destination, cgImage, NULL);
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);

    if (!success) {
        NSLog(@"ThumbnailCache: failed to write thumbnail to %@", path);
    }
    return success;
}

/// Stores a generated thumbnail in memory immediately and on disk in the background.
- (void)cacheCGImage:(CGImageRef)cgImage image:(NSImage *)image forId:(NSString *)wallpaperId {
    if (!cgImage || !image || wallpaperId.length == 0) return;

    [self.memoryCache setObject:image forKey:wallpaperId];

    CGImageRetain(cgImage);
    dispatch_async(self.cacheQueue, ^{
        [self writeCGImage:cgImage toPath:[self cachePathForId:wallpaperId]];
        CGImageRelease(cgImage);
    });
}

#pragma mark - Thumbnail Generation

- (NSImage *)thumbnailForWallpaperId:(NSString *)wallpaperId
                         previewPath:(NSString *)previewPath
                           videoPath:(NSString *)videoPath {
    if (wallpaperId.length == 0) return nil;

    NSImage *cached = [self cachedThumbnailForId:wallpaperId];
    if (cached) {
        return cached;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];

    // 1. The preview declared in project.json.
    if (previewPath.length > 0 && [fileManager fileExistsAtPath:previewPath]) {
        NSImage *thumb = [self thumbnailFromImageFile:previewPath wallpaperId:wallpaperId];
        if (thumb) return thumb;
    }

    // 2. A preview.* file sitting next to the video.
    if (videoPath.length > 0) {
        NSString *dir = [videoPath stringByDeletingLastPathComponent];
        for (NSString *name in FallbackPreviewNames()) {
            NSString *candidate = [dir stringByAppendingPathComponent:name];
            if ([candidate isEqualToString:previewPath]) continue;   // already tried
            if (![fileManager fileExistsAtPath:candidate]) continue;

            NSImage *thumb = [self thumbnailFromImageFile:candidate wallpaperId:wallpaperId];
            if (thumb) return thumb;
        }

        // 3. Grab a frame from the video.
        return [self thumbnailFromVideoFile:videoPath wallpaperId:wallpaperId];
    }

    return nil;
}

/// Downsamples an image file straight from its ImageIO source — decodes only
/// what is needed and honours any EXIF orientation.
- (NSImage *)thumbnailFromImageFile:(NSString *)path wallpaperId:(NSString *)wallpaperId {
    CGImageSourceRef source = CGImageSourceCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;

    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform:    @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize:           @(MaxThumbnailPixelSize())
    };

    CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!cgImage) return nil;

    NSImage *thumbnail = ImageFromCGImage(cgImage);
    [self cacheCGImage:cgImage image:thumbnail forId:wallpaperId];
    CGImageRelease(cgImage);

    return thumbnail;
}

/// Extracts a single frame one second into the video.
- (NSImage *)thumbnailFromVideoFile:(NSString *)videoPath wallpaperId:(NSString *)wallpaperId {
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];

    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(MaxThumbnailPixelSize(), MaxThumbnailPixelSize());

    CMTime time = CMTimeMakeWithSeconds(1.0, 600);
    CGImageRef cgImage = NULL;

    if (@available(macOS 13.0, *)) {
        // The synchronous copyCGImageAtTime: is deprecated as of macOS 15, so use
        // the async generator and wait — this method is already off the main thread.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block CGImageRef generated = NULL;
        [generator generateCGImageAsynchronouslyForTime:time
                                     completionHandler:^(CGImageRef _Nullable image,
                                                         CMTime actualTime,
                                                         NSError * _Nullable error) {
            if (image) {
                generated = CGImageRetain(image);
            } else if (error) {
                NSLog(@"ThumbnailCache: frame extraction failed for %@: %@",
                      videoPath.lastPathComponent, error.localizedDescription);
            }
            dispatch_semaphore_signal(done);
        }];

        // Bounded wait so a stalled generator can never pin this thread forever.
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) != 0) {
            [generator cancelAllCGImageGeneration];
            return nil;
        }
        cgImage = generated;
    } else {
        NSError *error = nil;
        cgImage = [generator copyCGImageAtTime:time actualTime:NULL error:&error];
        if (error) {
            NSLog(@"ThumbnailCache: frame extraction failed for %@: %@",
                  videoPath.lastPathComponent, error.localizedDescription);
        }
    }

    if (!cgImage) return nil;

    NSImage *thumbnail = ImageFromCGImage(cgImage);
    [self cacheCGImage:cgImage image:thumbnail forId:wallpaperId];
    CGImageRelease(cgImage);

    return thumbnail;
}

#pragma mark - Cache Management

- (void)clearCache {
    [self.memoryCache removeAllObjects];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.cacheDirectory error:&error];
    if (error) {
        NSLog(@"ThumbnailCache: could not list cache directory: %@", error.localizedDescription);
        return;
    }

    for (NSString *file in files) {
        NSString *filePath = [self.cacheDirectory stringByAppendingPathComponent:file];
        [fileManager removeItemAtPath:filePath error:nil];
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
        totalSize += (NSUInteger)[attributes fileSize];
    }

    return totalSize;
}

@end

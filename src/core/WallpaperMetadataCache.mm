//
//  WallpaperMetadataCache.mm
//  MacieWallpaper - Video Metadata Cache
//

#import "WallpaperMetadataCache.h"
#import "Constants.h"
#import <AVFoundation/AVFoundation.h>

// Plist keys
static NSString * const kKeyWidth    = @"w";
static NSString * const kKeyHeight   = @"h";
static NSString * const kKeyDuration = @"d";
static NSString * const kKeyFileSize = @"s";

/// How long to wait after the last change before rewriting the plist, so that
/// scrolling a large library does not trigger one write per card.
static const NSTimeInterval kSaveDebounceInterval = 2.0;

// ---------------------------------------------------------------------------
#pragma mark - WallpaperMetadata

@interface WallpaperMetadata ()
- (instancetype)initWithWidth:(NSInteger)width
                       height:(NSInteger)height
                     duration:(NSTimeInterval)duration
                     fileSize:(long long)fileSize;
- (NSDictionary *)plistRepresentation;
+ (nullable WallpaperMetadata *)metadataFromPlistRepresentation:(id)plist;
@end

@implementation WallpaperMetadata

- (instancetype)initWithWidth:(NSInteger)width
                       height:(NSInteger)height
                     duration:(NSTimeInterval)duration
                     fileSize:(long long)fileSize {
    self = [super init];
    if (self) {
        _pixelWidth  = MAX(0, width);
        _pixelHeight = MAX(0, height);
        _duration    = (duration > 0 && isfinite(duration)) ? duration : 0;
        _fileSize    = MAX(0, fileSize);
    }
    return self;
}

- (NSDictionary *)plistRepresentation {
    return @{
        kKeyWidth:    @(self.pixelWidth),
        kKeyHeight:   @(self.pixelHeight),
        kKeyDuration: @(self.duration),
        kKeyFileSize: @(self.fileSize)
    };
}

+ (WallpaperMetadata *)metadataFromPlistRepresentation:(id)plist {
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *dict = (NSDictionary *)plist;

    NSNumber *width  = dict[kKeyWidth];
    NSNumber *height = dict[kKeyHeight];
    if (![width isKindOfClass:[NSNumber class]] || ![height isKindOfClass:[NSNumber class]]) {
        return nil;
    }

    return [[WallpaperMetadata alloc] initWithWidth:width.integerValue
                                             height:height.integerValue
                                           duration:[dict[kKeyDuration] doubleValue]
                                           fileSize:[dict[kKeyFileSize] longLongValue]];
}

#pragma mark Formatting

/// Marketing-style tier for the longer edge, falling back to "<height>p".
- (NSString *)resolutionTier {
    NSInteger longEdge  = MAX(self.pixelWidth, self.pixelHeight);
    NSInteger shortEdge = MIN(self.pixelWidth, self.pixelHeight);
    if (longEdge <= 0) return nil;

    if (longEdge >= 7680) return @"8K";
    if (longEdge >= 3840) return @"4K";
    if (longEdge >= 2560) return @"1440p";
    if (longEdge >= 1920) return @"1080p";
    if (longEdge >= 1280) return @"720p";
    return [NSString stringWithFormat:@"%ldp", (long)shortEdge];
}

- (NSString *)formattedDuration {
    if (self.duration <= 0) return nil;
    NSInteger total   = (NSInteger)llround(self.duration);
    NSInteger minutes = total / 60;
    NSInteger seconds = total % 60;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

- (NSString *)formattedFileSize {
    if (self.fileSize <= 0) return nil;
    return [NSByteCountFormatter stringFromByteCount:self.fileSize
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSString *)joinParts:(NSArray<NSString *> *)parts {
    NSMutableArray<NSString *> *present = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [present addObject:part];
    }
    return [present componentsJoinedByString:@" • "];
}

- (NSString *)shortLabel {
    return [self joinParts:@[[self resolutionTier] ?: @"", [self formattedDuration] ?: @""]];
}

- (NSString *)longLabel {
    NSString *resolution = (self.pixelWidth > 0 && self.pixelHeight > 0)
        ? [NSString stringWithFormat:@"%ld × %ld", (long)self.pixelWidth, (long)self.pixelHeight]
        : nil;
    return [self joinParts:@[resolution ?: @"",
                             [self formattedDuration] ?: @"",
                             [self formattedFileSize] ?: @""]];
}

@end

// ---------------------------------------------------------------------------
#pragma mark - WallpaperMetadataCache

@interface WallpaperMetadataCache ()
/// Serialises access to _entries / _pendingCompletions and to the plist.
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WallpaperMetadata *> *entries;
/// Requests already in flight, so the hero and its gallery card share one read.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *pendingCompletions;
@property (nonatomic, strong) NSString *storePath;
@property (nonatomic) BOOL saveScheduled;
@end

@implementation WallpaperMetadataCache

+ (instancetype)sharedCache {
    static WallpaperMetadataCache *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[WallpaperMetadataCache alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateQueue = dispatch_queue_create("com.maciewallpaper.metadatacache", DISPATCH_QUEUE_SERIAL);
        _entries = [NSMutableDictionary dictionary];
        _pendingCompletions = [NSMutableDictionary dictionary];
        [self setupStorePath];
        [self loadFromDisk];
    }
    return self;
}

- (void)setupStorePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *dir = [paths.firstObject stringByAppendingPathComponent:kCacheDirectoryName];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:dir]) {
        [fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    self.storePath = [dir stringByAppendingPathComponent:kMetadataCacheFileName];
}

#pragma mark - Persistence

- (void)loadFromDisk {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:self.storePath];
    if (![plist isKindOfClass:[NSDictionary class]]) return;

    [plist enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) return;
        WallpaperMetadata *metadata = [WallpaperMetadata metadataFromPlistRepresentation:value];
        if (metadata) self.entries[key] = metadata;
    }];
}

/// Must be called on stateQueue.
- (void)scheduleSaveLocked {
    if (self.saveScheduled) return;
    self.saveScheduled = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSaveDebounceInterval * NSEC_PER_SEC)),
                   self.stateQueue, ^{
        self.saveScheduled = NO;

        NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithCapacity:self.entries.count];
        [self.entries enumerateKeysAndObjectsUsingBlock:^(NSString *key, WallpaperMetadata *value, BOOL *stop) {
            plist[key] = [value plistRepresentation];
        }];

        if (![plist writeToFile:self.storePath atomically:YES]) {
            NSLog(@"WallpaperMetadataCache: could not write %@", self.storePath);
        }
    });
}

#pragma mark - Lookup

- (WallpaperMetadata *)cachedMetadataForId:(NSString *)wallpaperId {
    if (wallpaperId.length == 0) return nil;

    __block WallpaperMetadata *metadata = nil;
    dispatch_sync(self.stateQueue, ^{
        metadata = self.entries[wallpaperId];
    });
    return metadata;
}

- (void)metadataForWallpaperId:(NSString *)wallpaperId
                     videoPath:(NSString *)videoPath
                    completion:(void (^)(WallpaperMetadata *))completion {
    if (wallpaperId.length == 0 || videoPath.length == 0) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }

    dispatch_async(self.stateQueue, ^{
        long long fileSize = [self fileSizeAtPath:videoPath];

        // A cached entry is trusted only while the video's size still matches,
        // which catches workshop items that were updated in place.
        WallpaperMetadata *cached = self.entries[wallpaperId];
        if (cached && cached.fileSize == fileSize && fileSize > 0) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
            return;
        }

        // Join an in-flight read for the same wallpaper rather than starting another.
        NSMutableArray *waiting = self.pendingCompletions[wallpaperId];
        if (waiting) {
            if (completion) [waiting addObject:completion];
            return;
        }
        self.pendingCompletions[wallpaperId] = completion
            ? [NSMutableArray arrayWithObject:completion]
            : [NSMutableArray array];

        [self readAssetAtPath:videoPath fileSize:fileSize wallpaperId:wallpaperId];
    });
}

- (long long)fileSizeAtPath:(NSString *)path {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return attributes ? (long long)[attributes fileSize] : 0;
}

/// Reads the video track asynchronously, then publishes the result to every
/// completion block waiting on this wallpaper ID.
- (void)readAssetAtPath:(NSString *)videoPath
               fileSize:(long long)fileSize
            wallpaperId:(NSString *)wallpaperId {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:videoPath] options:nil];

    [asset loadTracksWithMediaType:AVMediaTypeVideo
                 completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        CGSize size = CGSizeZero;
        if (tracks.firstObject) {
            AVAssetTrack *track = tracks.firstObject;
            // Rotated videos report a natural size in pre-transform orientation.
            size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
            size = CGSizeMake(fabs(size.width), fabs(size.height));
        } else if (error) {
            NSLog(@"WallpaperMetadataCache: could not read %@: %@",
                  videoPath.lastPathComponent, error.localizedDescription);
        }

        NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
        WallpaperMetadata *metadata = [[WallpaperMetadata alloc]
            initWithWidth:(NSInteger)llround(size.width)
                   height:(NSInteger)llround(size.height)
                 duration:duration
                 fileSize:fileSize];

        [self publishMetadata:metadata forId:wallpaperId];
    }];
}

- (void)publishMetadata:(WallpaperMetadata *)metadata forId:(NSString *)wallpaperId {
    dispatch_async(self.stateQueue, ^{
        BOOL usable = (metadata.pixelWidth > 0 || metadata.duration > 0);
        if (usable) {
            self.entries[wallpaperId] = metadata;
            [self scheduleSaveLocked];
        }

        NSArray *waiting = self.pendingCompletions[wallpaperId];
        [self.pendingCompletions removeObjectForKey:wallpaperId];

        if (waiting.count == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void (^block)(WallpaperMetadata *) in waiting) {
                block(usable ? metadata : nil);
            }
        });
    });
}

#pragma mark - Cache Management

- (void)clearCache {
    dispatch_async(self.stateQueue, ^{
        [self.entries removeAllObjects];
        [[NSFileManager defaultManager] removeItemAtPath:self.storePath error:nil];
    });
}

@end

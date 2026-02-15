//
//  VideoCollectionItem.m
//  MacieWallpaper - Video Collection View Item
//
//  Created on 2026-02-14.
//

#import "VideoCollectionItem.h"
#import "ThumbnailCache.h"

@interface VideoCollectionItem ()
@property (nonatomic, strong) NSView *containerView;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@end

@implementation VideoCollectionItem

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 150)];
    view.wantsLayer = YES;
    
    // Container with rounded corners and shadow
    self.containerView = [[NSView alloc] initWithFrame:NSMakeRect(5, 5, 190, 140)];
    self.containerView.wantsLayer = YES;
    self.containerView.layer.cornerRadius = 12.0;
    self.containerView.layer.masksToBounds = NO;
    self.containerView.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.15 green:0.15 blue:0.17 alpha:1.0] CGColor];
    self.containerView.layer.shadowColor = [[NSColor blackColor] CGColor];
    self.containerView.layer.shadowOffset = CGSizeMake(0, -2);
    self.containerView.layer.shadowRadius = 6.0;
    self.containerView.layer.shadowOpacity = 0.3;
    [view addSubview:self.containerView];
    
    // Thumbnail image
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 36, 174, 96)];
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    imageView.image = [NSImage imageNamed:NSImageNameIconViewTemplate];
    imageView.wantsLayer = YES;
    imageView.layer.cornerRadius = 8.0;
    imageView.layer.masksToBounds = YES;
    imageView.layer.borderWidth = 0;
    [self.containerView addSubview:imageView];
    
    // Title label
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 8, 174, 22)];
    titleLabel.stringValue = @"Loading...";
    titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    titleLabel.textColor = [NSColor colorWithWhite:0.9 alpha:1.0];
    titleLabel.alignment = NSTextAlignmentCenter;
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.backgroundColor = [NSColor clearColor];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.containerView addSubview:titleLabel];
    
    self.textField = titleLabel;
    self.imageView = imageView;
    self.view = view;
    
    // Setup tracking area for hover effects
    [self setupTrackingArea];
}

- (void)setupTrackingArea {
    if (self.trackingArea) {
        [self.view removeTrackingArea:self.trackingArea];
    }
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.view.bounds
                                                     options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow)
                                                       owner:self
                                                    userInfo:nil];
    [self.view addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    if (!self.isSelected) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.15;
            self.containerView.animator.layer.transform = CATransform3DMakeScale(1.03, 1.03, 1.0);
            self.containerView.layer.shadowOpacity = 0.5;
        }];
    }
}

- (void)mouseExited:(NSEvent *)event {
    if (!self.isSelected) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.15;
            self.containerView.animator.layer.transform = CATransform3DIdentity;
            self.containerView.layer.shadowOpacity = 0.3;
        }];
    }
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        if (selected) {
            self.containerView.layer.borderWidth = 2.0;
            self.containerView.layer.borderColor = [[NSColor systemBlueColor] CGColor];
            self.containerView.animator.layer.transform = CATransform3DMakeScale(1.02, 1.02, 1.0);
            self.containerView.layer.shadowColor = [[NSColor systemBlueColor] CGColor];
            self.containerView.layer.shadowOpacity = 0.6;
        } else {
            self.containerView.layer.borderWidth = 0;
            self.containerView.animator.layer.transform = CATransform3DIdentity;
            self.containerView.layer.shadowColor = [[NSColor blackColor] CGColor];
            self.containerView.layer.shadowOpacity = 0.3;
        }
    }];
}

- (void)setVideoTitle:(NSString *)videoTitle {
    _videoTitle = videoTitle;
    self.textField.stringValue = videoTitle ?: @"Untitled";
}

- (void)configureWithVideoData:(NSDictionary *)videoData {
    self.videoID = videoData[@"id"];
    self.videoPath = videoData[@"path"];
    self.videoTitle = videoData[@"title"];
    
    // Reset state
    self.containerView.layer.transform = CATransform3DIdentity;
    
    // Load thumbnail from cache
    [self loadThumbnail];
}

- (void)loadThumbnail {
    if (!self.videoID || !self.videoPath) return;
    
    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    
    // Try to get cached thumbnail first (synchronous for cached items)
    NSImage *cachedImage = [cache cachedThumbnailForId:self.videoID];
    if (cachedImage) {
        self.imageView.image = cachedImage;
        return;
    }
    
    // Set placeholder
    self.imageView.image = [NSImage imageNamed:NSImageNameIconViewTemplate];
    
    // Generate thumbnail asynchronously
    NSString *videoPath = self.videoPath;
    NSString *videoID = self.videoID;
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Try preview.jpg first
        NSString *wallpaperDir = [videoPath stringByDeletingLastPathComponent];
        NSString *previewPath = [wallpaperDir stringByAppendingPathComponent:@"preview.jpg"];
        
        NSImage *thumbnail = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:previewPath]) {
            thumbnail = [cache thumbnailForPreviewPath:previewPath wallpaperId:videoID];
        }
        
        // Fall back to video frame extraction
        if (!thumbnail) {
            thumbnail = [cache thumbnailForVideoPath:videoPath wallpaperId:videoID];
        }
        
        if (thumbnail) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Verify this cell still represents the same video
                if ([weakSelf.videoID isEqualToString:videoID]) {
                    weakSelf.imageView.image = thumbnail;
                }
            });
        }
    });
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.imageView.image = [NSImage imageNamed:NSImageNameIconViewTemplate];
    self.textField.stringValue = @"Loading...";
    self.containerView.layer.transform = CATransform3DIdentity;
    self.containerView.layer.borderWidth = 0;
    self.containerView.layer.shadowColor = [[NSColor blackColor] CGColor];
    self.containerView.layer.shadowOpacity = 0.3;
}

@end

//
//  VideoCollectionItem.m
//  MacieWallpaper - Video Collection View Item (Premium redesign 2026-08-02)
//

#import "VideoCollectionItem.h"
#import "ThumbnailCache.h"
#import "Constants.h"

// Card dimensions used by MainWindowController's flow layout
static const CGFloat kCardWidth  = 195.0;
static const CGFloat kCardHeight = 160.0;
static const CGFloat kThumbHeight = 120.0;

@interface VideoCollectionItem ()
@property (nonatomic, strong) NSView        *containerView;
@property (nonatomic, strong) NSImageView   *thumbnailView;
@property (nonatomic, strong) NSTextField   *titleLabel;
@property (nonatomic, strong) NSTextField   *metaLabel;
@property (nonatomic, strong) NSButton      *favoriteButton;
@property (nonatomic, strong) NSView        *playingBadge;
@property (nonatomic, strong) NSView        *playOverlay;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@end

@implementation VideoCollectionItem

#pragma mark - View Setup

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kCardWidth, kCardHeight)];
    root.wantsLayer = YES;

    // Card container
    self.containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kCardWidth, kCardHeight)];
    self.containerView.wantsLayer = YES;
    self.containerView.layer.cornerRadius = 12.0;
    self.containerView.layer.masksToBounds = YES;
    self.containerView.layer.backgroundColor = [[NSColor colorWithRed:0.10 green:0.11 blue:0.13 alpha:1.0] CGColor];
    self.containerView.layer.borderWidth = 0;
    self.containerView.layer.borderColor = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:0.0] CGColor];
    [root addSubview:self.containerView];

    // Soft drop shadow (on the outer view so it isn't clipped)
    root.layer.shadowColor  = [[NSColor blackColor] CGColor];
    root.layer.shadowOffset = CGSizeMake(0, -3);
    root.layer.shadowRadius = 10.0;
    root.layer.shadowOpacity = 0.35;

    // Thumbnail fills the top portion of the card
    self.thumbnailView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, kCardHeight - kThumbHeight, kCardWidth, kThumbHeight)];
    self.thumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.thumbnailView.wantsLayer = YES;
    self.thumbnailView.layer.masksToBounds = YES;
    [self.containerView addSubview:self.thumbnailView];

    // Play overlay (dark tint + play circle, hidden until hover)
    self.playOverlay = [[NSView alloc] initWithFrame:self.thumbnailView.frame];
    self.playOverlay.wantsLayer = YES;
    self.playOverlay.layer.backgroundColor = [[NSColor colorWithWhite:0.0 alpha:0.45] CGColor];
    self.playOverlay.hidden = YES;
    [self.containerView addSubview:self.playOverlay];

    // Play circle icon
    NSImageView *playIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(
        (kCardWidth - 36) / 2.0,
        (kThumbHeight - 36) / 2.0,
        36, 36)];
    if (@available(macOS 11.0, *)) {
        playIcon.image = [NSImage imageWithSystemSymbolName:@"play.circle.fill"
                                   accessibilityDescription:nil];
        playIcon.contentTintColor = [NSColor whiteColor];
    }
    playIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self.playOverlay addSubview:playIcon];

    // Favorite heart button (top-right of thumbnail)
    self.favoriteButton = [[NSButton alloc] initWithFrame:NSMakeRect(kCardWidth - 32, kCardHeight - kThumbHeight + 6, 26, 26)];
    self.favoriteButton.bordered = NO;
    self.favoriteButton.bezelStyle = NSBezelStyleInline;
    self.favoriteButton.wantsLayer = YES;
    [self.favoriteButton setButtonType:NSButtonTypeToggle];
    [self updateFavoriteButtonAppearance];
    self.favoriteButton.target = self;
    self.favoriteButton.action = @selector(favoriteButtonClicked:);
    [self.containerView addSubview:self.favoriteButton];

    // PLAYING badge (top-left of thumbnail, hidden by default)
    self.playingBadge = [[NSView alloc] initWithFrame:NSMakeRect(8, kCardHeight - kThumbHeight + 6, 72, 20)];
    self.playingBadge.wantsLayer = YES;
    self.playingBadge.layer.backgroundColor = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0] CGColor];
    self.playingBadge.layer.cornerRadius = 10.0;
    self.playingBadge.hidden = YES;
    [self.containerView addSubview:self.playingBadge];

    // Badge dot + text
    NSView *badgeDot = [[NSView alloc] initWithFrame:NSMakeRect(7, 6, 8, 8)];
    badgeDot.wantsLayer = YES;
    badgeDot.layer.cornerRadius = 4.0;
    badgeDot.layer.backgroundColor = [[NSColor whiteColor] CGColor];
    [self.playingBadge addSubview:badgeDot];

    NSTextField *badgeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 3, 50, 14)];
    badgeLabel.stringValue = @"PLAYING";
    badgeLabel.font = [NSFont systemFontOfSize:9 weight:NSFontWeightBold];
    badgeLabel.textColor = [NSColor whiteColor];
    badgeLabel.editable = NO;
    badgeLabel.bordered = NO;
    badgeLabel.backgroundColor = [NSColor clearColor];
    [self.playingBadge addSubview:badgeLabel];

    // Bottom info area
    CGFloat infoY = 0;
    CGFloat infoH = kCardHeight - kThumbHeight;

    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, infoY + 22, kCardWidth - 20, 17)];
    self.titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    self.titleLabel.textColor = [NSColor whiteColor];
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.backgroundColor = [NSColor clearColor];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.containerView addSubview:self.titleLabel];

    self.metaLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, infoY + 6, kCardWidth - 20, 14)];
    self.metaLabel.font = [NSFont systemFontOfSize:10];
    self.metaLabel.textColor = [NSColor colorWithWhite:0.55 alpha:1.0];
    self.metaLabel.editable = NO;
    self.metaLabel.bordered = NO;
    self.metaLabel.backgroundColor = [NSColor clearColor];
    [self.containerView addSubview:self.metaLabel];

    self.textField = self.titleLabel;
    self.imageView = self.thumbnailView;
    self.view = root;

    [self setupTrackingArea];
}

#pragma mark - Tracking Area

- (void)setupTrackingArea {
    if (self.trackingArea) {
        [self.view removeTrackingArea:self.trackingArea];
    }
    self.trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.view.bounds
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow)
               owner:self
            userInfo:nil];
    [self.view addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    if (self.isPlayingWallpaper) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.15;
        self.containerView.animator.layer.transform = CATransform3DMakeScale(1.03, 1.03, 1.0);
        self.view.layer.shadowOpacity = 0.55;
    }];
    self.playOverlay.hidden = NO;
}

- (void)mouseExited:(NSEvent *)event {
    if (self.isPlayingWallpaper) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.15;
        self.containerView.animator.layer.transform = CATransform3DIdentity;
        self.view.layer.shadowOpacity = 0.35;
    }];
    self.playOverlay.hidden = YES;
}

#pragma mark - Selection

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self applyPlayingStyle:selected || self.isPlayingWallpaper];
}

- (void)applyPlayingStyle:(BOOL)playing {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.2;
        if (playing) {
            self.containerView.layer.borderWidth = 2.0;
            self.containerView.layer.borderColor = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0] CGColor];
            // Blue glow via shadow (outer view is not clipped)
            self.view.layer.shadowColor  = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0] CGColor];
            self.view.layer.shadowRadius = 14.0;
            self.view.layer.shadowOpacity = 0.6;
            self.playingBadge.hidden = NO;
            self.playOverlay.hidden  = YES;
        } else {
            self.containerView.layer.borderWidth = 0;
            self.containerView.layer.borderColor = [[NSColor clearColor] CGColor];
            self.view.layer.shadowColor  = [[NSColor blackColor] CGColor];
            self.view.layer.shadowRadius = 10.0;
            self.view.layer.shadowOpacity = 0.35;
            self.playingBadge.hidden = YES;
        }
    }];
}

#pragma mark - Configuration

- (void)configureWithVideoData:(NSDictionary *)videoData
                    isFavorite:(BOOL)favorite
                     isPlaying:(BOOL)playing {
    self.videoID    = videoData[@"id"];
    self.videoPath  = videoData[@"path"];
    self.videoTitle = videoData[@"title"] ?: @"Untitled";
    self.isFavorite = favorite;
    self.isPlayingWallpaper = playing;

    self.titleLabel.stringValue = self.videoTitle;
    self.metaLabel.stringValue  = @"4K";   // Resolution info — can be extended later
    self.containerView.layer.transform = CATransform3DIdentity;

    [self updateFavoriteButtonAppearance];
    [self applyPlayingStyle:playing];
    [self loadThumbnail];
}

- (void)configureWithVideoData:(NSDictionary *)videoData {
    [self configureWithVideoData:videoData isFavorite:NO isPlaying:NO];
}

- (void)setVideoTitle:(NSString *)videoTitle {
    _videoTitle = videoTitle;
    self.titleLabel.stringValue = videoTitle ?: @"Untitled";
}

- (void)setIsFavorite:(BOOL)isFavorite {
    _isFavorite = isFavorite;
    [self updateFavoriteButtonAppearance];
}

- (void)updateFavoriteButtonAppearance {
    if (@available(macOS 11.0, *)) {
        NSString *symbolName = self.isFavorite ? @"heart.fill" : @"heart";
        NSImage *img = [NSImage imageWithSystemSymbolName:symbolName
                                accessibilityDescription:nil];
        [self.favoriteButton setImage:img];
        self.favoriteButton.contentTintColor = self.isFavorite
            ? [NSColor systemPinkColor]
            : [NSColor colorWithWhite:0.7 alpha:1.0];
    }
    self.favoriteButton.state = self.isFavorite ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)favoriteButtonClicked:(NSButton *)sender {
    self.isFavorite = !self.isFavorite;
    [self updateFavoriteButtonAppearance];
    // Post notification so MainWindowController can persist the change
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"WallpaperFavoriteToggled"
                      object:self
                    userInfo:@{@"id": self.videoID ?: @"", @"favorite": @(self.isFavorite)}];
}

#pragma mark - Thumbnail Loading

- (void)loadThumbnail {
    if (!self.videoID || !self.videoPath) return;

    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSImage *cached = [cache cachedThumbnailForId:self.videoID];
    if (cached) {
        self.thumbnailView.image = cached;
        return;
    }

    self.thumbnailView.image = nil;

    NSString *videoPath = self.videoPath;
    NSString *videoID   = self.videoID;
    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *dir         = [videoPath stringByDeletingLastPathComponent];
        NSString *previewPath = [dir stringByAppendingPathComponent:@"preview.jpg"];

        NSImage *thumb = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:previewPath]) {
            thumb = [cache thumbnailForPreviewPath:previewPath wallpaperId:videoID];
        }
        if (!thumb) {
            thumb = [cache thumbnailForVideoPath:videoPath wallpaperId:videoID];
        }

        if (thumb) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([weakSelf.videoID isEqualToString:videoID]) {
                    weakSelf.thumbnailView.image = thumb;
                }
            });
        }
    });
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    self.thumbnailView.image = nil;
    self.titleLabel.stringValue = @"";
    self.metaLabel.stringValue  = @"";
    self.containerView.layer.transform = CATransform3DIdentity;
    self.containerView.layer.borderWidth = 0;
    self.view.layer.shadowColor   = [[NSColor blackColor] CGColor];
    self.view.layer.shadowRadius  = 10.0;
    self.view.layer.shadowOpacity = 0.35;
    self.playingBadge.hidden = YES;
    self.playOverlay.hidden  = YES;
    self.isFavorite = NO;
    self.isPlayingWallpaper = NO;
    [self updateFavoriteButtonAppearance];
}

@end

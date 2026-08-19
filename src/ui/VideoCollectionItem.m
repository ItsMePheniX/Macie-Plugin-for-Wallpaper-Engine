//
//  VideoCollectionItem.m
//  MacieWallpaper - Video Collection View Item
//
//  Rebuilt on the design system 2026-08-19.
//

#import "VideoCollectionItem.h"
#import "DesignSystem.h"
#import "ThumbnailCache.h"
#import "WallpaperMetadataCache.h"
#import "Constants.h"

const CGFloat kMacieCardWidth  = 195.0;
const CGFloat kMacieCardHeight = 160.0;

/// Height of the image region. The remaining 40pt is the text strip.
static const CGFloat kThumbHeight = 120.0;

/// One inset for everything on the card. Using the same value for the badge, the
/// heart and the title is what puts the badge's left edge on the title's left edge
/// instead of 2pt off it.
#define kCardInset kMacieSpaceS

@interface VideoCollectionItem ()
@property (nonatomic, strong) NSView         *containerView;
@property (nonatomic, strong) NSImageView    *thumbnailView;
@property (nonatomic, strong) NSImageView    *placeholderIcon;
@property (nonatomic, strong) NSTextField    *titleLabel;
@property (nonatomic, strong) NSTextField    *metaLabel;
@property (nonatomic, strong) NSButton       *favoriteButton;
@property (nonatomic, strong) NSView         *playingBadge;
@property (nonatomic, strong) NSView         *playOverlay;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
/// Declared preview image from project.json, when the wallpaper has one.
@property (nonatomic, copy)   NSString       *previewPath;
@end

@implementation VideoCollectionItem

#pragma mark - View Setup

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kMacieCardWidth, kMacieCardHeight)];
    root.wantsLayer = YES;

    // Card container
    self.containerView = [[NSView alloc] initWithFrame:root.bounds];
    self.containerView.wantsLayer = YES;
    self.containerView.layer.cornerRadius  = kMacieCardCornerRadius;
    self.containerView.layer.masksToBounds = YES;
    self.containerView.layer.backgroundColor = MacieElevatedSurfaceColor().CGColor;
    self.containerView.layer.borderWidth = 0;
    self.containerView.layer.borderColor = [NSColor clearColor].CGColor;
    [root addSubview:self.containerView];

    // Soft drop shadow (on the outer view so it isn't clipped)
    root.layer.shadowColor   = [NSColor blackColor].CGColor;
    root.layer.shadowOffset  = CGSizeMake(0, -3);
    root.layer.shadowRadius  = 10.0;
    root.layer.shadowOpacity = 0.35;

    // --- Image region -------------------------------------------------------
    // Unflipped coordinates: the thumbnail occupies the TOP of the card, so its
    // origin is the card height minus its own height.
    NSRect thumbRect = NSMakeRect(0, kMacieCardHeight - kThumbHeight,
                                  kMacieCardWidth, kThumbHeight);

    self.thumbnailView = [[NSImageView alloc] initWithFrame:thumbRect];
    self.thumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.thumbnailView.wantsLayer = YES;
    self.thumbnailView.layer.masksToBounds = YES;
    // A distinct fill, so a card that is still generating its thumbnail reads as
    // loading rather than as a card with a hole in it.
    self.thumbnailView.layer.backgroundColor = MacieBackgroundColor().CGColor;
    [self.containerView addSubview:self.thumbnailView];

    self.placeholderIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(
        (kMacieCardWidth - 26) / 2.0,
        thumbRect.origin.y + (kThumbHeight - 26) / 2.0,
        26, 26)];
    self.placeholderIcon.imageScaling = NSImageScaleProportionallyDown;
    if (@available(macOS 11.0, *)) {
        self.placeholderIcon.image = [NSImage imageWithSystemSymbolName:@"photo"
                                             accessibilityDescription:@"Loading preview"];
        self.placeholderIcon.contentTintColor = MacieTertiaryTextColor();
    }
    [self.containerView addSubview:self.placeholderIcon];

    // Play overlay (dark tint + play circle, hidden until hover)
    self.playOverlay = [[NSView alloc] initWithFrame:thumbRect];
    self.playOverlay.wantsLayer = YES;
    self.playOverlay.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.45].CGColor;
    self.playOverlay.hidden = YES;
    [self.containerView addSubview:self.playOverlay];

    NSImageView *playIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(
        (kMacieCardWidth - 36) / 2.0, (kThumbHeight - 36) / 2.0, 36, 36)];
    if (@available(macOS 11.0, *)) {
        playIcon.image = [NSImage imageWithSystemSymbolName:@"play.circle.fill"
                                   accessibilityDescription:nil];
        playIcon.contentTintColor = [NSColor whiteColor];
    }
    playIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self.playOverlay addSubview:playIcon];

    // --- Overlay controls ---------------------------------------------------
    // Top edge of the image, measured down from the top of the card. The previous
    // code wrote `kCardHeight - kThumbHeight + 6`, which in unflipped coordinates
    // is 6pt above the image's BOTTOM edge — both of these sat at the wrong end of
    // the thumbnail despite comments claiming otherwise.
    const CGFloat kHeartSize = 26.0;
    const CGFloat kBadgeH    = 20.0;

    self.favoriteButton = [[NSButton alloc] initWithFrame:NSMakeRect(
        kMacieCardWidth - kCardInset - kHeartSize,
        kMacieCardHeight - kCardInset - kHeartSize,
        kHeartSize, kHeartSize)];
    self.favoriteButton.bordered = NO;
    self.favoriteButton.bezelStyle = NSBezelStyleInline;
    self.favoriteButton.wantsLayer = YES;
    // A scrim behind the glyph; an untinted heart vanishes on a bright thumbnail.
    self.favoriteButton.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.35].CGColor;
    self.favoriteButton.layer.cornerRadius = kHeartSize / 2.0;
    [self.favoriteButton setButtonType:NSButtonTypeToggle];
    self.favoriteButton.target = self;
    self.favoriteButton.action = @selector(favoriteButtonClicked:);
    [self updateFavoriteButtonAppearance];
    [self.containerView addSubview:self.favoriteButton];

    // PLAYING badge, top-left of the image. Sized to its text rather than given a
    // fixed 72pt width that an 11pt label would overflow.
    NSTextField *badgeLabel = MacieLabel(@"PLAYING", MacieFontCaptionEmphasized(), [NSColor whiteColor]);
    CGFloat labelW = ceil([badgeLabel.stringValue sizeWithAttributes:
                           @{NSFontAttributeName: badgeLabel.font}].width);
    CGFloat labelH = ceil(badgeLabel.font.boundingRectForFont.size.height);
    const CGFloat kDotSize = 7.0;
    CGFloat badgeW = kMacieSpaceS + kDotSize + kMacieSpaceXS + labelW + kMacieSpaceS;

    self.playingBadge = [[NSView alloc] initWithFrame:NSMakeRect(
        kCardInset, kMacieCardHeight - kCardInset - kBadgeH, badgeW, kBadgeH)];
    self.playingBadge.wantsLayer = YES;
    self.playingBadge.layer.backgroundColor = MacieAccentColor().CGColor;
    self.playingBadge.layer.cornerRadius = kBadgeH / 2.0;
    self.playingBadge.hidden = YES;
    [self.containerView addSubview:self.playingBadge];

    NSView *badgeDot = [[NSView alloc] initWithFrame:NSMakeRect(
        kMacieSpaceS, (kBadgeH - kDotSize) / 2.0, kDotSize, kDotSize)];
    badgeDot.wantsLayer = YES;
    badgeDot.layer.cornerRadius = kDotSize / 2.0;
    badgeDot.layer.backgroundColor = [NSColor whiteColor].CGColor;
    [self.playingBadge addSubview:badgeDot];

    badgeLabel.frame = NSMakeRect(kMacieSpaceS + kDotSize + kMacieSpaceXS,
                                  (kBadgeH - labelH) / 2.0, labelW, labelH);
    [self.playingBadge addSubview:badgeLabel];

    // --- Text strip ---------------------------------------------------------
    // Two lines in a 40pt strip. The padding is derived so the space above the
    // title equals the space below the metadata; before, the title had 1pt of
    // headroom and the metadata had 6pt beneath it.
    CGFloat titleH = ceil(MacieFontBodyEmphasized().boundingRectForFont.size.height);
    CGFloat metaH  = ceil(MacieFontCaption().boundingRectForFont.size.height);
    CGFloat gap    = 2.0;
    CGFloat pad    = (kMacieCardHeight - kThumbHeight - titleH - metaH - gap) / 2.0;
    CGFloat textW  = kMacieCardWidth - 2 * kCardInset;

    self.titleLabel = MacieLabel(@"", MacieFontBodyEmphasized(), MaciePrimaryTextColor());
    self.titleLabel.frame = NSMakeRect(kCardInset, pad + metaH + gap, textW, titleH);
    [self.containerView addSubview:self.titleLabel];

    self.metaLabel = MacieLabel(@"", MacieFontCaption(), MacieSecondaryTextColor());
    self.metaLabel.frame = NSMakeRect(kCardInset, pad, textW, metaH);
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
             options:(NSTrackingMouseEnteredAndExited |
                      NSTrackingActiveInKeyWindow |
                      NSTrackingInVisibleRect)
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
    // Selection is now keyboard focus, not "this is on the desktop". The two are
    // drawn differently: focus gets a plain ring, the live wallpaper gets the
    // accent border, glow and badge.
    [self applyPlayingStyle:self.isPlayingWallpaper];
    [self applyFocusRing:(selected && !self.isPlayingWallpaper)];
}

- (void)applyFocusRing:(BOOL)focused {
    if (self.isPlayingWallpaper) return;
    self.containerView.layer.borderWidth = focused ? 2.0 : 0.0;
    self.containerView.layer.borderColor = focused
        ? [NSColor colorWithWhite:1.0 alpha:0.55].CGColor
        : [NSColor clearColor].CGColor;
}

- (void)applyPlayingStyle:(BOOL)playing {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.2;
        if (playing) {
            self.containerView.layer.borderWidth = 2.0;
            self.containerView.layer.borderColor = MacieAccentColor().CGColor;
            // Blue glow via shadow (outer view is not clipped)
            self.view.layer.shadowColor   = MacieAccentColor().CGColor;
            self.view.layer.shadowRadius  = 14.0;
            self.view.layer.shadowOpacity = 0.6;
            self.playingBadge.hidden = NO;
            self.playOverlay.hidden  = YES;
        } else {
            self.containerView.layer.borderWidth = 0;
            self.containerView.layer.borderColor = [NSColor clearColor].CGColor;
            self.view.layer.shadowColor   = [NSColor blackColor].CGColor;
            self.view.layer.shadowRadius  = 10.0;
            self.view.layer.shadowOpacity = 0.35;
            self.playingBadge.hidden = YES;
        }
    }];
}

#pragma mark - Configuration

- (void)configureWithVideoData:(NSDictionary *)videoData
                    isFavorite:(BOOL)favorite
                     isPlaying:(BOOL)playing {
    self.videoID     = videoData[@"id"];
    self.videoPath   = videoData[@"path"];
    self.videoTitle  = videoData[@"title"] ?: @"Untitled";
    self.previewPath = videoData[@"preview"];
    self.isFavorite  = favorite;
    self.isPlayingWallpaper = playing;

    self.titleLabel.stringValue = self.videoTitle;
    // The full title as a tooltip, because a card is too narrow for most of the
    // Workshop's titles and truncation used to be the end of the story.
    self.titleLabel.toolTip = self.videoTitle;
    self.containerView.layer.transform = CATransform3DIdentity;

    [self updateFavoriteButtonAppearance];
    [self applyPlayingStyle:playing];
    if (!playing) [self applyFocusRing:self.isSelected];
    [self loadMetadata];
    [self loadThumbnail];
}

- (void)configureWithVideoData:(NSDictionary *)videoData {
    [self configureWithVideoData:videoData isFavorite:NO isPlaying:NO];
}

- (void)setVideoTitle:(NSString *)videoTitle {
    _videoTitle = videoTitle;
    self.titleLabel.stringValue = videoTitle ?: @"Untitled";
    self.titleLabel.toolTip = videoTitle;
}

- (void)setIsFavorite:(BOOL)isFavorite {
    _isFavorite = isFavorite;
    [self updateFavoriteButtonAppearance];
}

- (void)setIsPlayingWallpaper:(BOOL)isPlayingWallpaper {
    _isPlayingWallpaper = isPlayingWallpaper;
    [self applyPlayingStyle:isPlayingWallpaper];
}

- (void)updateFavoriteButtonAppearance {
    if (@available(macOS 11.0, *)) {
        NSString *symbolName = self.isFavorite ? @"heart.fill" : @"heart";
        [self.favoriteButton setImage:[NSImage imageWithSystemSymbolName:symbolName
                                              accessibilityDescription:nil]];
        self.favoriteButton.contentTintColor = self.isFavorite
            ? [NSColor systemPinkColor]
            : [NSColor colorWithWhite:0.85 alpha:1.0];
    }
    self.favoriteButton.state   = self.isFavorite ? NSControlStateValueOn : NSControlStateValueOff;
    self.favoriteButton.toolTip = self.isFavorite ? @"Remove from Favorites" : @"Add to Favorites";
}

- (void)favoriteButtonClicked:(NSButton *)sender {
    self.isFavorite = !self.isFavorite;
    [self updateFavoriteButtonAppearance];
    // Post notification so MainWindowController can persist the change
    [[NSNotificationCenter defaultCenter]
        postNotificationName:kNotificationWallpaperFavoriteToggled
                      object:self
                    userInfo:@{@"id": self.videoID ?: @"", @"favorite": @(self.isFavorite)}];
}

#pragma mark - Metadata

/// Real resolution and duration, read from the video once and cached. Cards get
/// the compact form; a stale-ID check keeps a recycled cell from showing the
/// previous wallpaper's numbers.
- (void)loadMetadata {
    if (!self.videoID || !self.videoPath) {
        self.metaLabel.stringValue = @"";
        return;
    }

    WallpaperMetadataCache *cache = [WallpaperMetadataCache sharedCache];
    WallpaperMetadata *known = [cache cachedMetadataForId:self.videoID];
    if (known) {
        self.metaLabel.stringValue = known.shortLabel;
        return;
    }

    self.metaLabel.stringValue = @"";

    NSString *videoID = self.videoID;
    __weak typeof(self) weakSelf = self;
    [cache metadataForWallpaperId:videoID
                        videoPath:self.videoPath
                       completion:^(WallpaperMetadata *metadata) {
        if (!metadata) return;
        if (![weakSelf.videoID isEqualToString:videoID]) return;
        weakSelf.metaLabel.stringValue = metadata.shortLabel;
    }];
}

#pragma mark - Thumbnail Loading

- (void)loadThumbnail {
    if (!self.videoID || !self.videoPath) return;

    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSImage *cached = [cache cachedThumbnailForId:self.videoID];
    if (cached) {
        [self setThumbnailImage:cached];
        return;
    }

    [self setThumbnailImage:nil];

    NSString *videoPath   = self.videoPath;
    NSString *videoID     = self.videoID;
    NSString *previewPath = self.previewPath;
    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSImage *thumb = [cache thumbnailForWallpaperId:videoID
                                           previewPath:previewPath
                                             videoPath:videoPath];
        if (!thumb) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([weakSelf.videoID isEqualToString:videoID]) {
                [weakSelf setThumbnailImage:thumb];
            }
        });
    });
}

/// Single place that swaps the image, so the placeholder can never be left
/// showing over a loaded thumbnail or hidden over an empty one.
- (void)setThumbnailImage:(NSImage *)image {
    self.thumbnailView.image = image;
    self.placeholderIcon.hidden = (image != nil);
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    [self setThumbnailImage:nil];
    self.titleLabel.stringValue = @"";
    self.titleLabel.toolTip = nil;
    self.metaLabel.stringValue  = @"";
    self.previewPath = nil;
    self.containerView.layer.transform = CATransform3DIdentity;
    self.containerView.layer.borderWidth = 0;
    self.view.layer.shadowColor   = [NSColor blackColor].CGColor;
    self.view.layer.shadowRadius  = 10.0;
    self.view.layer.shadowOpacity = 0.35;
    self.playingBadge.hidden = YES;
    self.playOverlay.hidden  = YES;
    _isFavorite = NO;
    _isPlayingWallpaper = NO;
    [self updateFavoriteButtonAppearance];
}

@end

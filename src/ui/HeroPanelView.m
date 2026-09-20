//
//  HeroPanelView.m
//  MacieWallpaper - Featured wallpaper panel
//
//  Created on 2026-08-19.
//

#import "HeroPanelView.h"
#import "Constants.h"
#import "DesignSystem.h"
#import "ThumbnailCache.h"
#import "WallpaperMetadataCache.h"
#import <AVFoundation/AVFoundation.h>

/// Width of the floating information panel.
static const CGFloat kHeroPanelWidth = 400.0;
/// Width of the Apply button, which is only present while previewing.
static const CGFloat kHeroApplyWidth = 84.0;

@interface HeroPanelView ()

// Backing image and hover video
@property (strong, nonatomic) NSImageView    *thumbnailView;
@property (strong, nonatomic) NSView         *previewView;      // hosts AVPlayerLayer
@property (strong, nonatomic) AVPlayer       *previewPlayer;
@property (strong, nonatomic) AVPlayerLayer  *previewLayer;
@property (strong, nonatomic) NSTrackingArea *hoverArea;

// Information panel
@property (strong, nonatomic) NSVisualEffectView *infoPanel;
@property (strong, nonatomic) NSView             *badgeRow;
@property (strong, nonatomic) NSView             *stateDot;
@property (strong, nonatomic) NSTextField        *stateLabel;
@property (strong, nonatomic) NSTextField        *contextLabel;
@property (strong, nonatomic) NSTextField        *titleLabel;
@property (strong, nonatomic) NSTextField        *metaLabel;
@property (strong, nonatomic) NSTextField        *descLabel;
@property (strong, nonatomic) NSView             *actionRow;
@property (strong, nonatomic) NSButton           *applyButton;
@property (strong, nonatomic) NSButton           *favoriteButton;

// State
@property (strong, nonatomic) NSDictionary *wallpaper;
@property (assign, nonatomic) BOOL          isPreview;
@property (assign, nonatomic) BOOL          favorite;
/// Which display PLAYING refers to, and whether the others agree. Set by the host and
/// outlives any one wallpaper.
@property (copy, nonatomic)   NSString     *displayContextName;
@property (assign, nonatomic) BOOL          othersDiffer;

@end

@implementation HeroPanelView

#pragma mark - Construction

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor blackColor].CGColor;

        [self buildBackdrop];
        [self buildInfoPanel];
        [self resetHoverArea];
    }
    return self;
}

- (void)buildBackdrop {
    self.thumbnailView = [[NSImageView alloc] initWithFrame:self.bounds];
    self.thumbnailView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.thumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.thumbnailView.wantsLayer = YES;
    self.thumbnailView.layer.masksToBounds = YES;
    [self addSubview:self.thumbnailView];

    // A dedicated host for the AVPlayerLayer: AppKit will not wipe sublayers on a
    // plain NSView the way it does on a view that draws its own content.
    self.previewView = [[NSView alloc] initWithFrame:self.bounds];
    self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.previewView.wantsLayer = YES;
    self.previewView.alphaValue = 0.0;   // revealed once the video has frames
    [self addSubview:self.previewView];

    // Scrim under the info panel. The autoresizing mask is what keeps it spanning
    // the full width after a resize; a fixed frame leaves a widened window's right
    // side ungradiented.
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.bounds;
    gradient.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    gradient.colors = @[
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.75].CGColor
    ];
    gradient.startPoint = CGPointMake(0, 0.6);
    gradient.endPoint   = CGPointMake(0, 0.0);
    [self.layer addSublayer:gradient];
}

/// The panel's height is derived from the rows it contains, so a row cannot end up
/// clipped or leave dead space. Its left edge is kMacieContentInset — the same edge
/// as the search field, the gallery header and the grid's first column.
- (void)buildInfoPanel {
    CGFloat pad    = kMacieSpaceL;
    CGFloat innerW = kHeroPanelWidth - 2 * pad;

    CGFloat badgeRowH = 18.0;
    CGFloat titleH    = ceil(MacieFontTitle().boundingRectForFont.size.height);
    CGFloat captionH  = ceil(MacieFontCaption().boundingRectForFont.size.height);
    CGFloat descH     = 2 * captionH + 2;

    CGFloat panelH = pad
                   + badgeRowH + kMacieSpaceS
                   + titleH    + kMacieSpaceXS
                   + captionH  + kMacieSpaceS
                   + descH     + kMacieSpaceM
                   + kMacieControlHeight
                   + pad;

    self.infoPanel = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(
        kMacieContentInset, kMacieContentInset, kHeroPanelWidth, panelH)];
    self.infoPanel.material     = NSVisualEffectMaterialHUDWindow;
    self.infoPanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.infoPanel.state        = NSVisualEffectStateActive;
    self.infoPanel.wantsLayer   = YES;
    self.infoPanel.layer.cornerRadius  = kMacieCardCornerRadius;
    self.infoPanel.layer.masksToBounds = YES;
    [self addSubview:self.infoPanel];

    MacieVStack *stack = [[MacieVStack alloc] initWithTop:panelH - pad inset:pad width:innerW];

    // --- State badge: dot + word --------------------------------------------
    // PLAYING (accent) means this wallpaper is on the desktop; PREVIEW (amber)
    // means it is only being looked at. With more than one display attached, a
    // right-aligned line says which desktop is meant.
    NSView *badgeRow = [[NSView alloc] initWithFrame:NSZeroRect];
    self.badgeRow = badgeRow;
    [self.infoPanel addSubview:badgeRow];
    [stack addView:badgeRow height:badgeRowH followedByGap:kMacieSpaceS];

    const CGFloat dotSize = 8.0;
    self.stateDot = [[NSView alloc] initWithFrame:NSMakeRect(
        0, (badgeRowH - dotSize) / 2.0, dotSize, dotSize)];
    self.stateDot.wantsLayer = YES;
    self.stateDot.layer.cornerRadius = dotSize / 2.0;
    self.stateDot.layer.backgroundColor = MacieAccentColor().CGColor;
    [badgeRow addSubview:self.stateDot];

    CGFloat badgeLabelH = ceil(MacieFontCaptionEmphasized().boundingRectForFont.size.height);
    CGFloat badgeLabelX = dotSize + kMacieSpaceS;
    self.stateLabel = MacieLabel(@"", MacieFontCaptionEmphasized(), MacieAccentColor());
    self.stateLabel.frame = NSMakeRect(badgeLabelX, (badgeRowH - badgeLabelH) / 2.0,
                                       innerW - badgeLabelX, badgeLabelH);
    [badgeRow addSubview:self.stateLabel];

    self.contextLabel = MacieLabel(@"", MacieFontCaption(), MacieTertiaryTextColor());
    self.contextLabel.alignment = NSTextAlignmentRight;
    // Middle truncation rather than tail: a long monitor name must not be allowed to eat
    // "OTHERS DIFFER", which is the half that changes what PLAYING means.
    self.contextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.contextLabel.frame = NSMakeRect(badgeLabelX, (badgeRowH - badgeLabelH) / 2.0,
                                         innerW - badgeLabelX, badgeLabelH);
    [badgeRow addSubview:self.contextLabel];

    // --- Title / metadata / description -------------------------------------
    self.titleLabel = MacieLabel(@"", MacieFontTitle(), MaciePrimaryTextColor());
    [self.infoPanel addSubview:self.titleLabel];
    [stack addView:self.titleLabel height:titleH followedByGap:kMacieSpaceXS];

    self.metaLabel = MacieLabel(@"", MacieFontCaption(), MacieSecondaryTextColor());
    [self.infoPanel addSubview:self.metaLabel];
    [stack addView:self.metaLabel height:captionH followedByGap:kMacieSpaceS];

    self.descLabel = MacieLabel(@"", MacieFontCaption(), MacieTertiaryTextColor());
    self.descLabel.lineBreakMode      = NSLineBreakByWordWrapping;
    self.descLabel.usesSingleLineMode = NO;
    [self.infoPanel addSubview:self.descLabel];
    [stack addView:self.descLabel height:descH followedByGap:kMacieSpaceM];

    // --- Actions -------------------------------------------------------------
    self.actionRow = [[NSView alloc] initWithFrame:NSZeroRect];
    [self.infoPanel addSubview:self.actionRow];
    [stack addView:self.actionRow height:kMacieControlHeight];

    self.applyButton = MacieAccentButton(@"Apply", self, @selector(applyClicked:));
    self.applyButton.toolTip = @"Put this wallpaper on the desktop";
    [self.actionRow addSubview:self.applyButton];

    self.favoriteButton = MacieIconButton(@"heart", @"Add to Favorites",
                                          self, @selector(favoriteClicked:));
    [self.actionRow addSubview:self.favoriteButton];

    [self layoutActionRow];
}

/// Apply only exists in the preview state, so the row is laid out from whichever
/// buttons are actually present rather than leaving a hole where Apply was.
- (void)layoutActionRow {
    CGFloat x = 0;

    self.applyButton.hidden = !self.isPreview;
    if (self.isPreview) {
        self.applyButton.frame = NSMakeRect(0, 0, kHeroApplyWidth, kMacieControlHeight);
        x = kHeroApplyWidth + kMacieSpaceS;
    }
    self.favoriteButton.frame = NSMakeRect(x, 0, kMacieControlHeight, kMacieControlHeight);
}

/// The state word and the display line share one row, so the divide between them is
/// measured rather than fixed: PLAYING and NOTHING PLAYING are very different widths, and
/// the display name should have whatever is left.
- (void)layoutBadgeRow {
    CGFloat rowW = self.badgeRow.bounds.size.width;
    if (rowW <= 0) return;

    NSRect stateFrame = self.stateLabel.frame;
    CGFloat stateW = ceil([self.stateLabel.stringValue
        sizeWithAttributes:@{NSFontAttributeName: self.stateLabel.font}].width) + 2;
    stateW = MIN(stateW, rowW - stateFrame.origin.x);

    self.stateLabel.frame = NSMakeRect(stateFrame.origin.x, stateFrame.origin.y,
                                       stateW, stateFrame.size.height);

    CGFloat contextX = stateFrame.origin.x + stateW + kMacieSpaceS;
    self.contextLabel.frame = NSMakeRect(contextX, self.contextLabel.frame.origin.y,
                                         MAX(0.0, rowW - contextX),
                                         self.contextLabel.frame.size.height);
}

#pragma mark - Public API

- (void)showWallpaper:(NSDictionary *)video
            isPreview:(BOOL)preview
           isFavorite:(BOOL)favorite {
    if (!video) { [self showEmpty]; return; }

    // Whatever was hovering belongs to the previous wallpaper.
    [self stopVideoPreview];

    self.wallpaper = video;
    self.isPreview = preview;
    self.favorite  = favorite;

    NSColor *stateColor = preview ? MacieWarningColor() : MacieAccentColor();
    self.stateLabel.stringValue = preview ? @"PREVIEW" : @"PLAYING";
    self.stateLabel.textColor   = stateColor;
    self.stateDot.layer.backgroundColor = stateColor.CGColor;

    self.titleLabel.stringValue = video[@"title"] ?: @"";
    // The Workshop's titles routinely outrun 368pt, and truncation used to be the
    // end of the story.
    self.titleLabel.toolTip     = video[@"title"];
    self.descLabel.stringValue  = video[@"description"] ?: @"";

    [self layoutBadgeRow];
    [self layoutActionRow];
    [self updateFavoriteButton];
    [self loadMetadata:video];
    [self loadThumbnail:video];
}

- (void)showEmpty {
    [self stopVideoPreview];

    self.wallpaper = nil;
    self.isPreview = NO;
    self.favorite  = NO;

    self.stateLabel.stringValue = @"NOTHING PLAYING";
    self.stateLabel.textColor   = MacieTertiaryTextColor();
    self.stateDot.layer.backgroundColor = MacieTertiaryTextColor().CGColor;
    self.titleLabel.stringValue = @"No wallpaper";
    self.titleLabel.toolTip     = nil;
    self.metaLabel.stringValue  = @"";
    self.descLabel.stringValue  = @"";
    self.thumbnailView.image    = nil;

    [self layoutBadgeRow];
    [self layoutActionRow];
    [self updateFavoriteButton];
}

- (void)setDisplayContextName:(NSString *)name othersDiffer:(BOOL)differ {
    self.displayContextName = name;
    self.othersDiffer       = differ;
    [self updateContextLabel];
}

/// Uppercased to sit in the same typographic register as PLAYING beside it. "OTHERS DIFFER"
/// is the whole point of the line: without it, a hero marked PLAYING on a two-monitor Mac
/// reads as a claim about both desktops.
- (void)updateContextLabel {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:2];
    if (self.displayContextName.length) [parts addObject:self.displayContextName.uppercaseString];
    if (self.othersDiffer)              [parts addObject:@"OTHERS DIFFER"];

    self.contextLabel.stringValue = [parts componentsJoinedByString:@"  ·  "];
    // The row is narrow and monitor names are not, so the untruncated text stays reachable.
    if (!parts.count)            self.contextLabel.toolTip = nil;
    else if (self.othersDiffer)  self.contextLabel.toolTip = @"The other displays are showing different wallpapers";
    else                         self.contextLabel.toolTip = self.contextLabel.stringValue;

    [self layoutBadgeRow];
}

- (void)setFavorite:(BOOL)favorite {
    _favorite = favorite;
    [self updateFavoriteButton];
}

#pragma mark - Content loading

- (void)loadMetadata:(NSDictionary *)video {
    NSString *videoId   = video[@"id"];
    NSString *videoPath = video[@"path"];
    if (!videoId.length || !videoPath.length) {
        self.metaLabel.stringValue = @"";
        return;
    }

    WallpaperMetadataCache *cache = [WallpaperMetadataCache sharedCache];
    WallpaperMetadata *known = [cache cachedMetadataForId:videoId];
    self.metaLabel.stringValue = known ? known.longLabel : @"";
    if (known) return;

    __weak typeof(self) weakSelf = self;
    [cache metadataForWallpaperId:videoId
                        videoPath:videoPath
                       completion:^(WallpaperMetadata *metadata) {
        typeof(self) strongSelf = weakSelf;
        // Discard a late result if the panel has moved on to another wallpaper.
        if (!strongSelf || !metadata) return;
        if (![strongSelf.wallpaper[@"id"] isEqualToString:videoId]) return;
        strongSelf.metaLabel.stringValue = metadata.longLabel;
    }];
}

- (void)loadThumbnail:(NSDictionary *)video {
    NSString *videoId   = video[@"id"];
    NSString *videoPath = video[@"path"];
    NSString *preview   = video[@"preview"];
    if (!videoId.length) return;

    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSImage *cached = [cache cachedThumbnailForId:videoId];
    if (cached) {
        self.thumbnailView.image = cached;
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSImage *thumb = [cache thumbnailForWallpaperId:videoId
                                           previewPath:preview
                                             videoPath:videoPath];
        if (!thumb) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (![strongSelf.wallpaper[@"id"] isEqualToString:videoId]) return;
            strongSelf.thumbnailView.image = thumb;
        });
    });
}

- (void)updateFavoriteButton {
    BOOL hasWallpaper = ([self.wallpaper[@"id"] length] > 0);

    self.favoriteButton.enabled = hasWallpaper;
    if (@available(macOS 11.0, *)) {
        NSString *symbol = self.favorite ? @"heart.fill" : @"heart";
        [self.favoriteButton setImage:[NSImage imageWithSystemSymbolName:symbol
                                                accessibilityDescription:nil]];
    }
    self.favoriteButton.contentTintColor = self.favorite ? [NSColor systemPinkColor]
                                                         : MacieSecondaryTextColor();
    self.favoriteButton.toolTip = self.favorite ? @"Remove from Favorites"
                                                : @"Add to Favorites";
}

#pragma mark - Actions

- (void)applyClicked:(id)sender {
    // Apply is hidden outside the preview state, so there is nothing else it can mean.
    if (self.isPreview && self.wallpaper && self.onApplyRequested) {
        self.onApplyRequested(self.wallpaper);
    }
}

- (void)favoriteClicked:(id)sender {
    if (self.wallpaper && self.onFavoriteToggled) self.onFavoriteToggled(self.wallpaper);
}

#pragma mark - Hover video preview

- (void)resetHoverArea {
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];

    // NSTrackingInVisibleRect makes AppKit maintain the rect across resizes, so the
    // hover region cannot go stale when the window width changes.
    self.hoverArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited |
                      NSTrackingActiveInKeyWindow |
                      NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:self.hoverArea];
}

- (void)mouseEntered:(NSEvent *)event {
    if (event.trackingArea != self.hoverArea) return;
    [self startVideoPreview];
}

- (void)mouseExited:(NSEvent *)event {
    if (event.trackingArea != self.hoverArea) return;
    [self stopVideoPreview];
}

- (void)startVideoPreview {
    NSString *path = self.wallpaper[@"path"];
    if (!path.length) return;

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    player.muted = YES;
    self.previewPlayer = player;

    if (self.previewLayer) [self.previewLayer removeFromSuperlayer];
    self.previewLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.previewView.bounds;
    self.previewLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [self.previewView.layer addSublayer:self.previewLayer];

    // The thumbnail stays fully visible until the video actually has frames,
    // otherwise the hero flashes black on hover.
    self.thumbnailView.alphaValue = 1.0;
    self.previewView.alphaValue   = 0.0;

    [player play];

    [self.previewLayer addObserver:self
                       forKeyPath:@"readyForDisplay"
                          options:NSKeyValueObservingOptionNew
                          context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (![keyPath isEqualToString:@"readyForDisplay"]) return;
    if (![change[NSKeyValueChangeNewKey] boolValue]) return;

    // Remove the observer before dispatching, to avoid a double fire.
    @try { [self.previewLayer removeObserver:self forKeyPath:@"readyForDisplay"]; } @catch (...) {}

    AVPlayer *capturedPlayer = self.previewPlayer;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Bail if the pointer moved on — the user has already moused out.
        if (!capturedPlayer || capturedPlayer != self.previewPlayer) return;
        self.previewLayer.frame = self.previewView.bounds;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.25;
            self.previewView.animator.alphaValue   = 1.0;
            self.thumbnailView.animator.alphaValue = 0.0;
        } completionHandler:nil];
    });
}

- (void)stopVideoPreview {
    @try { [self.previewLayer removeObserver:self forKeyPath:@"readyForDisplay"]; } @catch (...) {}

    // Pause before dropping the reference; any queued observation bails on the
    // pointer mismatch once this is nil.
    [self.previewPlayer pause];
    self.previewPlayer = nil;

    self.thumbnailView.alphaValue = 1.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.2;
        self.previewView.animator.alphaValue = 0.0;
    } completionHandler:^{
        [self.previewLayer removeFromSuperlayer];
        self.previewLayer = nil;
    }];
}

- (void)dealloc {
    @try { [_previewLayer removeObserver:self forKeyPath:@"readyForDisplay"]; } @catch (...) {}
}

@end

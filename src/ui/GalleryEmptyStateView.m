//
//  GalleryEmptyStateView.m
//  MacieWallpaper - Empty-state placeholder for the wallpaper grid
//
//  Created on 2026-08-19.
//

#import "GalleryEmptyStateView.h"
#import "DesignSystem.h"

@implementation GalleryEmptyStateView {
    NSImageView         *_iconView;
    NSTextField         *_titleLabel;
    NSTextField         *_subtitleLabel;
    NSProgressIndicator *_progressBar;   // created on first use
    BOOL                 _showingProgress;
}

static const CGFloat kIconSize     = 44.0;
static const CGFloat kBlockWidth   = 360.0;
static const CGFloat kBarHeight    = 8.0;
static const CGFloat kSpinnerSize  = 28.0;

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.imageScaling = NSImageScaleProportionallyDown;
    _iconView.contentTintColor = MacieTertiaryTextColor();
    [self addSubview:_iconView];

    _titleLabel = MacieLabel(@"", MacieFontHeading(), MacieSecondaryTextColor());
    _titleLabel.alignment = NSTextAlignmentCenter;
    [self addSubview:_titleLabel];

    _subtitleLabel = MacieLabel(@"", MacieFontBody(), MacieTertiaryTextColor());
    _subtitleLabel.alignment = NSTextAlignmentCenter;
    _subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    // A wrapping label needs its cell told not to truncate to one line.
    _subtitleLabel.usesSingleLineMode = NO;
    _subtitleLabel.cell.wraps = YES;
    [self addSubview:_subtitleLabel];

    return self;
}

/// Centres the block on every resize, so the message stays put as the window and
/// the hero panel above it change size.
- (void)layout {
    [super layout];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat blockW = MIN(kBlockWidth, w - 2 * kMacieContentInset);
    CGFloat x = (w - blockW) / 2.0;

    // The progress bar occupies the same slot as the symbol, at its own height.
    BOOL indeterminate = _showingProgress && _progressBar.indeterminate;
    CGFloat leadH = kIconSize;
    if (_showingProgress) leadH = indeterminate ? kSpinnerSize : kBarHeight;

    CGFloat titleH    = ceil(_titleLabel.font.boundingRectForFont.size.height) + 2;
    CGFloat subtitleH = _subtitleLabel.stringValue.length ? 34.0 : 0.0;
    CGFloat totalH    = leadH + kMacieSpaceL + titleH +
                        (subtitleH ? kMacieSpaceXS + subtitleH : 0);

    // Sits slightly above true centre; a block centred in the scroll view reads
    // as low because the eye weights the hero panel above it.
    CGFloat top = (h + totalH) / 2.0 + kMacieSpaceXL;
    if (top > h) top = h;

    CGFloat y = top - leadH;
    if (_showingProgress) {
        _progressBar.frame = indeterminate
            ? NSMakeRect((w - kSpinnerSize) / 2.0, y, kSpinnerSize, kSpinnerSize)
            : NSMakeRect(x, y, blockW, kBarHeight);
    } else {
        _iconView.frame = NSMakeRect((w - kIconSize) / 2.0, y, kIconSize, kIconSize);
    }

    y -= kMacieSpaceL + titleH;
    _titleLabel.frame = NSMakeRect(x, y, blockW, titleH);

    if (subtitleH > 0) {
        y -= kMacieSpaceXS + subtitleH;
        _subtitleLabel.frame = NSMakeRect(x, y, blockW, subtitleH);
    } else {
        _subtitleLabel.frame = NSMakeRect(x, y, blockW, 0);
    }
}

- (void)showSymbol:(NSString *)symbolName
             title:(NSString *)title
          subtitle:(NSString *)subtitle {
    if (@available(macOS 11.0, *)) {
        _iconView.image = [NSImage imageWithSystemSymbolName:symbolName
                                   accessibilityDescription:title];
    }
    // The two lead-in states are mutually exclusive, so leaving the previous one
    // visible would stack a bar on top of a symbol.
    [_progressBar stopAnimation:nil];
    _progressBar.hidden = YES;
    _iconView.hidden    = NO;
    _showingProgress    = NO;

    _titleLabel.stringValue    = title ?: @"";
    _subtitleLabel.stringValue = subtitle ?: @"";
    self.hidden = NO;
    self.needsLayout = YES;
}

- (void)showProgressTitle:(NSString *)title
                 subtitle:(NSString *)subtitle
                 progress:(NSUInteger)completed
                    total:(NSUInteger)total {
    if (!_progressBar) {
        _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        _progressBar.minValue = 0.0;
        [self addSubview:_progressBar];
    }

    BOOL determinate = (total > 0);
    NSProgressIndicatorStyle wanted = determinate ? NSProgressIndicatorStyleBar
                                                  : NSProgressIndicatorStyleSpinning;

    // Reassigning the style restarts the animation, so only touch it on a real
    // change — this method runs on every progress report.
    if (!_showingProgress || _progressBar.style != wanted) {
        [_progressBar stopAnimation:nil];
        _progressBar.style        = wanted;
        _progressBar.indeterminate = !determinate;
        if (!determinate) [_progressBar startAnimation:nil];
    }

    if (determinate) {
        _progressBar.maxValue    = (double)total;
        _progressBar.doubleValue = (double)MIN(completed, total);
    }

    _iconView.hidden    = YES;
    _progressBar.hidden = NO;
    _showingProgress    = YES;

    _titleLabel.stringValue    = title ?: @"";
    _subtitleLabel.stringValue = subtitle ?: @"";
    self.hidden = NO;
    self.needsLayout = YES;
}

@end

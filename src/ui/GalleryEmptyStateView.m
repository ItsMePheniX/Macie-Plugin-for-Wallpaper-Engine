//
//  GalleryEmptyStateView.m
//  MacieWallpaper - Empty-state placeholder for the wallpaper grid
//
//  Created on 2026-08-19.
//

#import "GalleryEmptyStateView.h"
#import "DesignSystem.h"

@implementation GalleryEmptyStateView {
    NSImageView          *_iconView;
    NSTextField          *_titleLabel;
    NSTextField          *_subtitleLabel;
    NSProgressIndicator  *_progressIndicator; // shown during library scan
}

static const CGFloat kIconSize     = 44.0;
static const CGFloat kBlockWidth   = 360.0;

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

    CGFloat titleH    = ceil(_titleLabel.font.boundingRectForFont.size.height) + 2;
    CGFloat subtitleH = _subtitleLabel.stringValue.length ? 34.0 : 0.0;
    CGFloat totalH    = kIconSize + kMacieSpaceL + titleH +
                        (subtitleH ? kMacieSpaceXS + subtitleH : 0);

    // Sits slightly above true centre; a block centred in the scroll view reads
    // as low because the eye weights the hero panel above it.
    CGFloat top = (h + totalH) / 2.0 + kMacieSpaceXL;
    if (top > h) top = h;

    CGFloat y = top - kIconSize;
    NSRect iconFrame = NSMakeRect((w - kIconSize) / 2.0, y, kIconSize, kIconSize);
    _iconView.frame = iconFrame;
    if (_progressIndicator) {
        // Spinner sits in the same slot; size it to match the icon area
        CGFloat spinSize = 32.0;
        _progressIndicator.frame = NSMakeRect((w - spinSize) / 2.0,
                                              y + (kIconSize - spinSize) / 2.0,
                                              spinSize, spinSize);
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
    // Hide spinner if it was showing
    [_progressIndicator stopAnimation:nil];
    _progressIndicator.hidden = YES;
    _iconView.hidden = NO;

    if (@available(macOS 11.0, *)) {
        _iconView.image = [NSImage imageWithSystemSymbolName:symbolName
                                   accessibilityDescription:title];
    }
    _titleLabel.stringValue    = title ?: @"";
    _subtitleLabel.stringValue = subtitle ?: @"";
    self.hidden = NO;
    self.needsLayout = YES;
}

- (void)showProgressTitle:(NSString *)title
                 subtitle:(NSString *)subtitle
                 progress:(NSUInteger)progress
                    total:(NSUInteger)total {
    // Lazily create the spinner the first time it is needed
    if (!_progressIndicator) {
        _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        _progressIndicator.style = NSProgressIndicatorStyleSpinning;
        _progressIndicator.controlSize = NSControlSizeRegular;
        _progressIndicator.displayedWhenStopped = NO;
        [self addSubview:_progressIndicator];
    }

    // Position spinner where the icon normally lives (layout: centres on resize)
    _iconView.hidden = YES;
    _progressIndicator.hidden = NO;
    [_progressIndicator startAnimation:nil];

    _titleLabel.stringValue    = title ?: @"";
    _subtitleLabel.stringValue = subtitle ?: @"";
    self.hidden = NO;
    self.needsLayout = YES;
}

@end

//
//  GalleryEmptyStateView.m
//  MacieWallpaper - Empty-state placeholder for the wallpaper grid
//
//  Created on 2026-08-19.
//

#import "GalleryEmptyStateView.h"
#import "DesignSystem.h"

@implementation GalleryEmptyStateView {
    NSImageView *_iconView;
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
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
    _iconView.frame = NSMakeRect((w - kIconSize) / 2.0, y, kIconSize, kIconSize);

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
    _titleLabel.stringValue    = title ?: @"";
    _subtitleLabel.stringValue = subtitle ?: @"";
    self.hidden = NO;
    self.needsLayout = YES;
}

@end

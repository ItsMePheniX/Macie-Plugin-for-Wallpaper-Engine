//
//  DesignSystem.m
//  MacieWallpaper - Visual design tokens and view factories
//
//  Created on 2026-08-19.
//

#import "DesignSystem.h"

// ---------------------------------------------------------------------------
#pragma mark - Type scale

NSFont *MacieFontTitle(void) {
    return [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
}

NSFont *MacieFontHeading(void) {
    return [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
}

NSFont *MacieFontBodyEmphasized(void) {
    return [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
}

NSFont *MacieFontBody(void) {
    return [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
}

NSFont *MacieFontCaption(void) {
    return [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
}

NSFont *MacieFontCaptionEmphasized(void) {
    return [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
}

NSFont *MacieFontMonoCaption(void) {
    return [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
}

// ---------------------------------------------------------------------------
#pragma mark - Spacing grid

const CGFloat kMacieSpaceXS  =  4.0;
const CGFloat kMacieSpaceS   =  8.0;
const CGFloat kMacieSpaceM   = 12.0;
const CGFloat kMacieSpaceL   = 16.0;
const CGFloat kMacieSpaceXL  = 20.0;
const CGFloat kMacieSpaceXXL = 24.0;

const CGFloat kMacieContentInset = 20.0;
const CGFloat kMacieSidebarInset = 12.0;

const CGFloat kMacieRowHeight        = 30.0;
const CGFloat kMacieRowGutter        =  4.0;
const CGFloat kMacieControlHeight    = 28.0;
const CGFloat kMacieFieldHeight      = 30.0;
const CGFloat kMacieCornerRadius     =  7.0;
const CGFloat kMacieCardCornerRadius = 12.0;

// ---------------------------------------------------------------------------
#pragma mark - Palette

NSColor *MacieAccentColor(void) {
    return [NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0];
}

NSColor *MacieWarningColor(void) {
    return [NSColor colorWithRed:0.98 green:0.66 blue:0.24 alpha:1.0];
}

NSColor *MacieBackgroundColor(void) {
    return [NSColor colorWithRed:0.067 green:0.071 blue:0.094 alpha:1.0];
}

NSColor *MacieSurfaceColor(void) {
    return [NSColor colorWithRed:0.086 green:0.090 blue:0.114 alpha:1.0];
}

NSColor *MacieElevatedSurfaceColor(void) {
    return [NSColor colorWithRed:0.110 green:0.114 blue:0.137 alpha:1.0];
}

NSColor *MaciePrimaryTextColor(void) {
    return [NSColor colorWithWhite:0.96 alpha:1.0];
}

NSColor *MacieSecondaryTextColor(void) {
    return [NSColor colorWithWhite:0.66 alpha:1.0];
}

NSColor *MacieTertiaryTextColor(void) {
    return [NSColor colorWithWhite:0.46 alpha:1.0];
}

NSColor *MacieHairlineColor(void) {
    return [NSColor colorWithWhite:1.0 alpha:0.10];
}

// ---------------------------------------------------------------------------
#pragma mark - View factories

NSTextField *MacieLabel(NSString *text, NSFont *font, NSColor *color) {
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSZeroRect];
    f.stringValue      = text ?: @"";
    f.font             = font ?: MacieFontBody();
    f.textColor        = color ?: MaciePrimaryTextColor();
    f.editable         = NO;
    f.selectable       = NO;
    f.bordered         = NO;
    f.bezeled          = NO;
    f.drawsBackground  = NO;
    f.backgroundColor  = [NSColor clearColor];
    f.lineBreakMode    = NSLineBreakByTruncatingTail;
    return f;
}

/// Shared body for the two filled button styles. AppKit's own bezel does not
/// tint, so these are borderless buttons with a layer background and a
/// centre-aligned attributed title.
static NSButton *MacieFilledButton(NSString *title, NSColor *fill, id target, SEL action) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSZeroRect];
    b.bordered   = NO;
    b.wantsLayer = YES;
    b.layer.cornerRadius   = kMacieCornerRadius;
    b.layer.backgroundColor = fill.CGColor;
    [b setButtonType:NSButtonTypeMomentaryChange];

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentCenter;
    b.attributedTitle = [[NSAttributedString alloc] initWithString:(title ?: @"")
        attributes:@{
            NSFontAttributeName:            MacieFontBody(),
            NSForegroundColorAttributeName: [NSColor whiteColor],
            NSParagraphStyleAttributeName:  para
        }];

    b.target = target;
    b.action = action;
    return b;
}

NSButton *MacieAccentButton(NSString *title, id target, SEL action) {
    return MacieFilledButton(title, MacieAccentColor(), target, action);
}

NSButton *MacieSecondaryButton(NSString *title, id target, SEL action) {
    return MacieFilledButton(title, [NSColor colorWithWhite:1.0 alpha:0.14], target, action);
}

NSButton *MacieIconButton(NSString *symbolName, NSString *tooltip, id target, SEL action) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSZeroRect];
    b.bordered   = NO;
    b.wantsLayer = YES;
    b.layer.cornerRadius = 6.0;
    b.imagePosition = NSImageOnly;
    [b setButtonType:NSButtonTypeMomentaryChange];
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:symbolName
                                accessibilityDescription:tooltip];
        if (img) b.image = img;
    }
    b.contentTintColor = MacieSecondaryTextColor();
    b.toolTip = tooltip;
    b.target  = target;
    b.action  = action;
    return b;
}

void MacieApplyDarkAppearance(NSWindow *window) {
    // The palette above has no light-mode variants, so the appearance is pinned
    // rather than left to follow the system. Without this, a Mac in Light Mode
    // resolves AppKit's semantic colours to near-black against these dark
    // backgrounds and the text disappears.
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

// ---------------------------------------------------------------------------
#pragma mark - MacieVStack

@implementation MacieVStack {
    CGFloat _inset;
    CGFloat _width;
}

- (instancetype)initWithTop:(CGFloat)top inset:(CGFloat)inset width:(CGFloat)width {
    self = [super init];
    if (self) {
        _cursor = top;
        _inset  = inset;
        _width  = width;
    }
    return self;
}

- (NSRect)addView:(NSView *)view height:(CGFloat)height {
    // Unflipped coordinates: the cursor tracks the row's top edge, so the origin
    // is the cursor minus the row height.
    NSRect frame = NSMakeRect(_inset, _cursor - height, _width, height);
    view.frame = frame;
    _cursor -= height;
    return frame;
}

- (NSRect)addView:(NSView *)view height:(CGFloat)height followedByGap:(CGFloat)gap {
    NSRect frame = [self addView:view height:height];
    _cursor -= gap;
    return frame;
}

- (void)addGap:(CGFloat)gap {
    _cursor -= gap;
}

@end

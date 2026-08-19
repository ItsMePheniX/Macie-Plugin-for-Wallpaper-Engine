//
//  SidebarView.m
//  MacieWallpaper - Gallery sidebar
//
//  Created on 2026-08-19.
//

#import "SidebarView.h"
#import "DesignSystem.h"
#import "Constants.h"

NSArray<NSString *> *MacieCollectionNames(void) {
    return @[@"Anime", @"Nature", @"Cyberpunk", @"Space", @"Games", @"Movies"];
}

NSDictionary<NSString *, NSArray<NSString *> *> *MacieCollectionKeywords(void) {
    return @{
        @"Anime":      @[@"anime", @"manga", @"sakura", @"waifu", @"naruto", @"ghibli"],
        @"Nature":     @[@"nature", @"forest", @"ocean", @"mountain", @"lake", @"cabin",
                         @"wave", @"sky", @"beach", @"rain", @"snow", @"jungle"],
        @"Cyberpunk":  @[@"cyber", @"neon", @"punk", @"city", @"urban", @"drift",
                         @"rain city", @"alley"],
        @"Space":      @[@"space", @"star", @"galaxy", @"astronaut", @"cosmos",
                         @"planet", @"nebula", @"universe"],
        @"Games":      @[@"game", @"gaming", @"minecraft", @"fortnite", @"halo",
                         @"zelda", @"pixel", @"retro"],
        @"Movies":     @[@"movie", @"film", @"cinema", @"dune", @"blade runner",
                         @"marvel", @"dc", @"star wars"],
    };
}

// ---------------------------------------------------------------------------
#pragma mark - Row

/// One sidebar row: icon, label, optional trailing count.
///
/// This is a real view with real subviews at known x positions. The previous
/// implementation packed an icon into an NSTextAttachment inside a button's
/// attributed title, which could not be aligned with anything outside the button
/// and forced the selection code to rewrite the attributed string just to change
/// a text colour.
@interface MacieSidebarRow : NSView
@property (nonatomic, assign) MacieSidebarSection section;
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, assign, getter=isSelected) BOOL selected;
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, copy)   void (^onClick)(MacieSidebarSection section);
@end

@implementation MacieSidebarRow {
    NSTrackingArea *_tracking;
}

/// Icon column width. The label's left edge is this far right of the row's own
/// left edge, so every row's text starts at exactly the same x.
static const CGFloat kIconColumnWidth = 22.0;
static const CGFloat kCountColumnWidth = 34.0;

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.cornerRadius = kMacieCornerRadius;

    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:_iconView];

    _titleLabel = MacieLabel(@"", MacieFontBody(), MaciePrimaryTextColor());
    [self addSubview:_titleLabel];

    _countLabel = MacieLabel(@"", MacieFontCaption(), MacieTertiaryTextColor());
    _countLabel.alignment = NSTextAlignmentRight;
    [self addSubview:_countLabel];

    return self;
}

- (void)layout {
    [super layout];
    CGFloat h = self.bounds.size.height;
    CGFloat w = self.bounds.size.width;

    // Icon and text are both vertically centred on the row's midline, which is
    // what makes them share a baseline no matter what the row height is.
    _iconView.frame = NSMakeRect(kMacieSpaceS, (h - 15) / 2.0, 15, 15);

    CGFloat textX = kMacieSpaceS + kIconColumnWidth;
    CGFloat textW = w - textX - kCountColumnWidth - kMacieSpaceS;
    CGFloat lineH = ceil(_titleLabel.font.boundingRectForFont.size.height);
    _titleLabel.frame = NSMakeRect(textX, (h - lineH) / 2.0, MAX(textW, 0), lineH);

    CGFloat countH = ceil(_countLabel.font.boundingRectForFont.size.height);
    _countLabel.frame = NSMakeRect(w - kCountColumnWidth - kMacieSpaceS,
                                   (h - countH) / 2.0,
                                   kCountColumnWidth, countH);
}

- (void)setSymbolName:(NSString *)symbolName {
    if (@available(macOS 11.0, *)) {
        self.iconView.image = [NSImage imageWithSystemSymbolName:symbolName
                                       accessibilityDescription:nil];
    }
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    [self refreshAppearance];
}

- (void)setHovered:(BOOL)hovered {
    _hovered = hovered;
    [self refreshAppearance];
}

- (void)refreshAppearance {
    if (self.selected) {
        self.layer.backgroundColor = [MacieAccentColor() colorWithAlphaComponent:0.20].CGColor;
        self.titleLabel.textColor  = MacieAccentColor();
        self.iconView.contentTintColor = MacieAccentColor();
    } else {
        self.layer.backgroundColor = self.hovered
            ? [NSColor colorWithWhite:1.0 alpha:0.06].CGColor
            : [NSColor clearColor].CGColor;
        self.titleLabel.textColor = MaciePrimaryTextColor();
        self.iconView.contentTintColor = MacieSecondaryTextColor();
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                             options:(NSTrackingMouseEnteredAndExited |
                                                      NSTrackingActiveInKeyWindow |
                                                      NSTrackingInVisibleRect)
                                               owner:self
                                            userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; }
- (void)mouseExited:(NSEvent *)event  { self.hovered = NO; }

- (void)mouseDown:(NSEvent *)event {
    if (self.onClick) self.onClick(self.section);
}

@end

// ---------------------------------------------------------------------------
#pragma mark - SidebarView

@implementation SidebarView {
    NSMutableArray<MacieSidebarRow *> *_rows;
    MacieSidebarRow *_libraryRow;
    MacieSidebarRow *_favoritesRow;
    MacieSidebarRow *_recentRow;
    NSTextField     *_libraryFooterLabel;
    NSTextField     *_cacheFooterLabel;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _rows = [NSMutableArray array];

    self.material     = NSVisualEffectMaterialSidebar;
    self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.state        = NSVisualEffectStateActive;
    self.wantsLayer   = YES;
    self.autoresizingMask = NSViewHeightSizable;

    [self buildContents];
    return self;
}

- (void)buildContents {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    // Trailing hairline
    NSView *border = [[NSView alloc] initWithFrame:NSMakeRect(w - 1, 0, 1, h)];
    border.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    border.wantsLayer = YES;
    border.layer.backgroundColor = MacieHairlineColor().CGColor;
    [self addSubview:border];

    // Rows are inset from both edges, and every row's contents derive from that
    // one inset — which is what puts the logo text, row labels and section
    // headers on a single left edge.
    CGFloat rowX = kMacieSidebarInset - kMacieSpaceS; // row box overhangs so its
    CGFloat rowW = w - 2 * rowX;                      // 8pt interior padding lands
                                                      // text at kMacieSidebarInset

    // The window uses NSWindowStyleMaskFullSizeContentView, so content has to
    // start below the traffic lights.
    MacieVStack *stack = [[MacieVStack alloc] initWithTop:h - 46 inset:rowX width:rowW];

    [self addLogoRowToStack:stack];
    [stack addGap:kMacieSpaceL];

    [self addSectionHeader:@"LIBRARY" toStack:stack];

    _libraryRow   = [self addRow:@"Library"   symbol:@"house.fill"        section:MacieSidebarSectionLibrary   toStack:stack];
    _favoritesRow = [self addRow:@"Favorites" symbol:@"heart.fill"        section:MacieSidebarSectionFavorites toStack:stack];
    _recentRow    = [self addRow:@"Recent"    symbol:@"clock.fill"        section:MacieSidebarSectionRecent    toStack:stack];
                    [self addRow:@"Random"    symbol:@"shuffle"           section:MacieSidebarSectionRandom    toStack:stack];

    [self addDividerToStack:stack width:w];
    [self addSectionHeader:@"COLLECTIONS" toStack:stack];

    NSArray<NSString *> *names = MacieCollectionNames();
    for (NSUInteger i = 0; i < names.count; i++) {
        [self addRow:names[i]
              symbol:@"folder.fill"
             section:(MacieSidebarSection)(MacieSidebarSectionCollection + (NSInteger)i)
             toStack:stack];
    }

    [self addDividerToStack:stack width:w];
    [self addSectionHeader:@"SYSTEM" toStack:stack];

    [self addRow:@"Settings" symbol:@"gearshape.fill"   section:MacieSidebarSectionSettings toStack:stack];
    [self addRow:@"About"    symbol:@"info.circle.fill" section:MacieSidebarSectionAbout    toStack:stack];

    [self buildFooter];
    [self setSelectedSection:MacieSidebarSectionLibrary];
}

- (void)addLogoRowToStack:(MacieVStack *)stack {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.autoresizingMask = NSViewMinYMargin;
    [self addSubview:row];
    NSRect frame = [stack addView:row height:38];

    // The badge occupies the same icon column as every row below it, and the text
    // starts at the same x as every row label, so the logo block lines up with
    // the list rather than floating 12pt to its right as it did before.
    NSImageView *badge = [[NSImageView alloc] initWithFrame:NSMakeRect(kMacieSpaceS, 2, 34, 34)];
    badge.image = [NSImage imageNamed:NSImageNameApplicationIcon];
    badge.imageScaling = NSImageScaleProportionallyUpOrDown;
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = kMacieSpaceS;
    badge.layer.masksToBounds = YES;
    [row addSubview:badge];

    CGFloat textX = kMacieSpaceS + 34 + kMacieSpaceS;
    CGFloat textW = frame.size.width - textX - kMacieSpaceS;

    NSTextField *name = MacieLabel(kAppName, MacieFontHeading(), MaciePrimaryTextColor());
    name.frame = NSMakeRect(textX, 19, textW, 18);
    [row addSubview:name];

    NSTextField *ver = MacieLabel([NSString stringWithFormat:@"v%@", kAppVersion],
                                  MacieFontCaption(), MacieTertiaryTextColor());
    ver.frame = NSMakeRect(textX, 3, textW, 14);
    [row addSubview:ver];
}

- (void)addSectionHeader:(NSString *)text toStack:(MacieVStack *)stack {
    NSTextField *lbl = MacieLabel(text, MacieFontCaptionEmphasized(), MacieTertiaryTextColor());
    lbl.autoresizingMask = NSViewMinYMargin;
    [self addSubview:lbl];
    // Indented by the row's interior padding so the header aligns with row labels'
    // icon column, not with the row box edge.
    [stack addView:lbl height:18 followedByGap:kMacieSpaceXS];
    NSRect f = lbl.frame;
    lbl.frame = NSMakeRect(f.origin.x + kMacieSpaceS, f.origin.y,
                           f.size.width - kMacieSpaceS, f.size.height);
}

- (void)addDividerToStack:(MacieVStack *)stack width:(CGFloat)totalWidth {
    [stack addGap:kMacieSpaceS];
    NSView *div = [[NSView alloc] initWithFrame:NSZeroRect];
    div.autoresizingMask = NSViewMinYMargin;
    div.wantsLayer = YES;
    div.layer.backgroundColor = MacieHairlineColor().CGColor;
    [self addSubview:div];
    [stack addView:div height:1 followedByGap:kMacieSpaceM];
    // Inset the hairline to the text column so it reads as a list separator.
    NSRect f = div.frame;
    div.frame = NSMakeRect(kMacieSidebarInset, f.origin.y,
                           totalWidth - 2 * kMacieSidebarInset, 1);
}

- (MacieSidebarRow *)addRow:(NSString *)title
                     symbol:(NSString *)symbol
                    section:(MacieSidebarSection)section
                    toStack:(MacieVStack *)stack {
    MacieSidebarRow *row = [[MacieSidebarRow alloc] initWithFrame:NSZeroRect];
    row.autoresizingMask = NSViewMinYMargin;
    row.section = section;
    row.titleLabel.stringValue = title;
    [row setSymbolName:symbol];

    __weak typeof(self) weakSelf = self;
    row.onClick = ^(MacieSidebarSection s) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.onSectionSelected) strongSelf.onSectionSelected(s);
    };

    [self addSubview:row];
    [stack addView:row height:kMacieRowHeight followedByGap:kMacieRowGutter];
    [_rows addObject:row];
    return row;
}

/// Footer is laid out from the bottom edge with line heights that match the font,
/// rather than three hardcoded y values with 13pt boxes for 11pt text.
- (void)buildFooter {
    CGFloat w = self.bounds.size.width;
    CGFloat labelW = w - 2 * kMacieSidebarInset;
    CGFloat lineH  = ceil(MacieFontCaption().boundingRectForFont.size.height);
    CGFloat y = kMacieSpaceXL;

    _cacheFooterLabel = MacieLabel(@"", MacieFontMonoCaption(), MacieTertiaryTextColor());
    _cacheFooterLabel.frame = NSMakeRect(kMacieSidebarInset, y, labelW, lineH);
    _cacheFooterLabel.autoresizingMask = NSViewMaxYMargin;
    [self addSubview:_cacheFooterLabel];
    y += lineH + kMacieSpaceXS / 2.0;

    _libraryFooterLabel = MacieLabel(@"", MacieFontMonoCaption(), MacieTertiaryTextColor());
    _libraryFooterLabel.frame = NSMakeRect(kMacieSidebarInset, y, labelW, lineH);
    _libraryFooterLabel.autoresizingMask = NSViewMaxYMargin;
    [self addSubview:_libraryFooterLabel];
    y += lineH + kMacieSpaceS;

    NSTextField *hdr = MacieLabel(@"ON DISK", MacieFontCaptionEmphasized(), MacieTertiaryTextColor());
    hdr.frame = NSMakeRect(kMacieSidebarInset, y, labelW, lineH + 2);
    hdr.autoresizingMask = NSViewMaxYMargin;
    [self addSubview:hdr];
}

// ---------------------------------------------------------------------------
#pragma mark - Public API

- (void)setSelectedSection:(MacieSidebarSection)section {
    for (MacieSidebarRow *row in _rows) {
        row.selected = (row.section == section);
    }
}

- (void)setLibraryCount:(NSUInteger)library
         favoritesCount:(NSUInteger)favorites
            recentCount:(NSUInteger)recent {
    // An empty string rather than "0" — a zero badge is noise, and its absence
    // already says the section is empty.
    _libraryRow.countLabel.stringValue   = library   ? [NSString stringWithFormat:@"%lu", (unsigned long)library]   : @"";
    _favoritesRow.countLabel.stringValue = favorites ? [NSString stringWithFormat:@"%lu", (unsigned long)favorites] : @"";
    _recentRow.countLabel.stringValue    = recent    ? [NSString stringWithFormat:@"%lu", (unsigned long)recent]    : @"";
}

- (void)setLibraryText:(NSString *)libraryText cacheText:(NSString *)cacheText {
    _libraryFooterLabel.stringValue = libraryText ?: @"";
    _cacheFooterLabel.stringValue   = cacheText ?: @"";
}

@end

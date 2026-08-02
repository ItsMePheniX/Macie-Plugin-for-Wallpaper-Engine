//
//  MainWindowController.mm
//  MacieWallpaper - Main Window Controller (Premium UI rebuild 2026-08-02)
//
//  Functional logic (search, favorites persistence, launch-at-login, sleep/wake,
//  restore-last-wallpaper, mute state) preserved from prior implementation.
//  Only the visual layer has been replaced.
//

#import "MainWindowController.h"
#import "AVVideoRenderer.h"
#import "Constants.h"
#import "MacieAssetManagerWrapper.h"
#import "ThumbnailCache.h"
#import "VideoCollectionItem.h"
#import <AVFoundation/AVFoundation.h>
#import <ServiceManagement/ServiceManagement.h>
#import <vector>

// ---------------------------------------------------------------------------
#pragma mark - Collection keyword → category mapping

static NSDictionary<NSString *, NSArray<NSString *> *> *CollectionKeywords(void) {
    return @{
        @"Anime":      @[@"anime", @"manga", @"sakura", @"waifu", @"naruto", @"ghibli"],
        @"Nature":     @[@"nature", @"forest", @"ocean", @"mountain", @"lake", @"cabin",
                         @"wave", @"sky", @"beach", @"rain", @"snow", @"jungle"],
        @"Cyberpunk":  @[@"cyber", @"neon", @"punk", @"city", @"urban", @"drift",
                         @"rain city", @"alley", @"rain"],
        @"Space":      @[@"space", @"star", @"galaxy", @"astronaut", @"cosmos",
                         @"planet", @"nebula", @"universe"],
        @"Games":      @[@"game", @"gaming", @"minecraft", @"fortnite", @"halo",
                         @"zelda", @"pixel", @"retro"],
        @"Movies":     @[@"movie", @"film", @"cinema", @"dune", @"blade runner",
                         @"marvel", @"dc", @"star wars"],
    };
}

// Sidebar selection tags
typedef NS_ENUM(NSInteger, SidebarSection) {
    SidebarSectionLibrary    = 0,
    SidebarSectionFavorites  = 1,
    SidebarSectionRecent     = 2,
    SidebarSectionRandom     = 3,
    SidebarSectionCollection = 100, // + index
    SidebarSectionSettings   = 200,
};

// ---------------------------------------------------------------------------
#pragma mark - Class extension

@interface MainWindowController () <
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSSearchFieldDelegate
>

// Core
@property (strong, nonatomic) AVVideoRenderer          *videoRenderer;
@property (strong, nonatomic) MacieAssetManagerWrapper *assetManager;

// Data
/// Full unfiltered list — never mutated after loadVideos.
@property (strong, nonatomic) NSArray<NSDictionary *> *videos;
/// What the collection view currently shows (search + sidebar filtered).
@property (strong, nonatomic) NSArray<NSDictionary *> *filteredVideos;
/// IDs of favorited wallpapers, persisted to NSUserDefaults.
@property (strong, nonatomic) NSMutableSet<NSString *> *favoriteIds;
/// IDs of recently played wallpapers (most-recent first, capped at 20).
@property (strong, nonatomic) NSMutableArray<NSString *> *recentIds;
/// ID of the wallpaper currently playing on the desktop.
@property (strong, nonatomic) NSString *playingWallpaperId;
/// Active sidebar section (drives filteredVideos).
@property (assign, nonatomic) SidebarSection activeSidebarSection;
/// Active collection name when activeSidebarSection == SidebarSectionCollection.
@property (strong, nonatomic) NSString *activeCollectionName;

// Sidebar
@property (strong, nonatomic) NSVisualEffectView  *sidebarView;
@property (strong, nonatomic) NSButton            *librarySidebarButton;
@property (strong, nonatomic) NSButton            *favoritesSidebarButton;
@property (strong, nonatomic) NSButton            *recentSidebarButton;
@property (strong, nonatomic) NSButton            *randomSidebarButton;
@property (strong, nonatomic) NSMutableArray<NSButton *> *collectionButtons;
@property (strong, nonatomic) NSButton            *settingsSidebarButton;
@property (strong, nonatomic) NSTextField         *libraryCountLabel;
@property (strong, nonatomic) NSTextField         *favoritesCountLabel;
@property (strong, nonatomic) NSTextField         *recentCountLabel;
@property (strong, nonatomic) NSTextField         *storageValueLabel;
@property (strong, nonatomic) NSView              *storageProgressTrack;
@property (strong, nonatomic) NSView              *storageProgressFill;

// Toolbar
@property (strong, nonatomic) NSSearchField       *searchField;
@property (strong, nonatomic) NSButton            *muteToolbarButton;
@property (strong, nonatomic) NSButton            *shuffleButton;

// Hero
@property (strong, nonatomic) NSView              *heroContainer;
@property (strong, nonatomic) NSImageView         *heroThumbnailView;
@property (strong, nonatomic) AVPlayer            *heroPreviewPlayer;
@property (strong, nonatomic) AVPlayerLayer       *heroPreviewLayer;
@property (strong, nonatomic) NSTrackingArea      *heroTrackingArea;
@property (strong, nonatomic) NSTextField         *heroTitleLabel;
@property (strong, nonatomic) NSTextField         *heroMetaLabel;
@property (strong, nonatomic) NSTextField         *heroDescLabel;
@property (strong, nonatomic) NSView              *heroInfoPanel;
@property (strong, nonatomic) NSButton            *heroFavoriteButton;

// Gallery
@property (strong, nonatomic) NSCollectionView    *collectionView;
@property (strong, nonatomic) NSScrollView        *scrollView;
@property (strong, nonatomic) NSTextField         *galleryHeaderLabel;
@property (strong, nonatomic) NSTextField         *countLabel;
@property (strong, nonatomic) NSView              *contentArea;   // right of sidebar

// Mini player
@property (strong, nonatomic) NSVisualEffectView  *miniPlayerView;
@property (strong, nonatomic) NSImageView         *miniPlayerThumb;
@property (strong, nonatomic) NSTextField         *miniPlayerTitleLabel;
@property (strong, nonatomic) NSTextField         *miniPlayerMetaLabel;
@property (strong, nonatomic) NSButton            *miniPlayPauseButton;

// Preferences panel (sheet / popover)
@property (strong, nonatomic) NSTextField         *cacheSizeLabel;

@end

// ---------------------------------------------------------------------------
@implementation MainWindowController

#pragma mark - Init

- (instancetype)initWithAssetManager:(MacieAssetManagerWrapper *)assetManager
                       videoRenderer:(AVVideoRenderer *)renderer {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(100, 100, kMainWindowWidth, kMainWindowHeight)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskFullSizeContentView)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        self.assetManager = assetManager;
        self.videoRenderer = renderer;
        self.favoriteIds = [self loadFavoriteIds];
        self.recentIds   = [self loadRecentIds];
        self.activeSidebarSection = SidebarSectionLibrary;
        self.collectionButtons = [NSMutableArray array];

        [self setupWindow];
        [self loadVideos];
        [self setupFavoriteToggleObserver];
    }
    return self;
}

#pragma mark - Window Setup

- (void)setupWindow {
    NSWindow *w = self.window;
    w.title = @"";
    w.titlebarAppearsTransparent = YES;
    w.titleVisibility = NSWindowTitleHidden;
    w.movableByWindowBackground = YES;
    w.minSize = NSMakeSize(kMainWindowMinWidth, kMainWindowMinHeight);
    w.backgroundColor = [NSColor colorWithRed:0.067 green:0.071 blue:0.094 alpha:1.0];

    // Full-window vibrancy background
    NSVisualEffectView *bgEffect = [[NSVisualEffectView alloc]
        initWithFrame:w.contentView.bounds];
    bgEffect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    bgEffect.material  = NSVisualEffectMaterialUnderWindowBackground;
    bgEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bgEffect.state = NSVisualEffectStateActive;
    [w.contentView addSubview:bgEffect];

    [self buildSidebar];
    [self buildContentArea];
}

// ---------------------------------------------------------------------------
#pragma mark - Sidebar

- (void)buildSidebar {
    NSView *cv = self.window.contentView;
    CGFloat h  = cv.bounds.size.height;

    self.sidebarView = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, kSidebarWidth, h)];
    self.sidebarView.autoresizingMask = NSViewHeightSizable;
    self.sidebarView.material      = NSVisualEffectMaterialSidebar;
    self.sidebarView.blendingMode  = NSVisualEffectBlendingModeBehindWindow;
    self.sidebarView.state         = NSVisualEffectStateActive;
    self.sidebarView.wantsLayer    = YES;

    // Right border
    NSView *border = [[NSView alloc] initWithFrame:NSMakeRect(kSidebarWidth - 1, 0, 1, h)];
    border.autoresizingMask = NSViewHeightSizable;
    border.wantsLayer = YES;
    border.layer.backgroundColor = [[NSColor colorWithWhite:0.2 alpha:0.6] CGColor];
    [self.sidebarView addSubview:border];

    [cv addSubview:self.sidebarView];

    CGFloat sideW = kSidebarWidth - 16;
    CGFloat top   = h - 52;   // start below traffic lights

    // Logo row
    NSView *logoRow = [[NSView alloc] initWithFrame:NSMakeRect(8, top - 44, sideW, 44)];
    logoRow.autoresizingMask = NSViewMinYMargin;
    [self.sidebarView addSubview:logoRow];

    // "M" badge
    NSView *badge = [[NSView alloc] initWithFrame:NSMakeRect(0, 8, 32, 32)];
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 8.0;
    badge.layer.backgroundColor = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0] CGColor];
    NSTextField *badgeLetter = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 32, 22)];
    badgeLetter.stringValue = @"M";
    badgeLetter.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];
    badgeLetter.textColor = [NSColor whiteColor];
    badgeLetter.alignment = NSTextAlignmentCenter;
    badgeLetter.editable = NO; badgeLetter.bordered = NO;
    badgeLetter.backgroundColor = [NSColor clearColor];
    [badge addSubview:badgeLetter];
    [logoRow addSubview:badge];

    NSTextField *appName = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 18, 140, 18)];
    appName.stringValue = @"Macie";
    appName.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    appName.textColor = [NSColor labelColor];
    appName.editable = NO; appName.bordered = NO;
    appName.backgroundColor = [NSColor clearColor];
    [logoRow addSubview:appName];

    NSTextField *appVer = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 4, 140, 13)];
    appVer.stringValue = [NSString stringWithFormat:@"v%@", kAppVersion];
    appVer.font = [NSFont systemFontOfSize:10];
    appVer.textColor = [NSColor secondaryLabelColor];
    appVer.editable = NO; appVer.bordered = NO;
    appVer.backgroundColor = [NSColor clearColor];
    [logoRow addSubview:appVer];

    CGFloat cursor = top - 44 - 12;

    // LIBRARY section
    cursor = [self addSectionLabel:@"LIBRARY" y:cursor - 18];

    self.librarySidebarButton = [self sidebarButton:@"house.fill" title:@"Library" y:cursor - 32 tag:SidebarSectionLibrary];
    cursor -= 36;
    [self.sidebarView addSubview:self.librarySidebarButton];
    self.libraryCountLabel = [self badgeLabel:@"" x:kSidebarWidth - 40 y:cursor + 6];
    [self.sidebarView addSubview:self.libraryCountLabel];

    self.favoritesSidebarButton = [self sidebarButton:@"heart.fill" title:@"Favorites" y:cursor - 32 tag:SidebarSectionFavorites];
    cursor -= 36;
    [self.sidebarView addSubview:self.favoritesSidebarButton];
    self.favoritesCountLabel = [self badgeLabel:@"" x:kSidebarWidth - 40 y:cursor + 6];
    [self.sidebarView addSubview:self.favoritesCountLabel];

    self.recentSidebarButton = [self sidebarButton:@"clock.fill" title:@"Recent" y:cursor - 32 tag:SidebarSectionRecent];
    cursor -= 36;
    [self.sidebarView addSubview:self.recentSidebarButton];
    self.recentCountLabel = [self badgeLabel:@"" x:kSidebarWidth - 40 y:cursor + 6];
    [self.sidebarView addSubview:self.recentCountLabel];

    self.randomSidebarButton = [self sidebarButton:@"shuffle" title:@"Random" y:cursor - 32 tag:SidebarSectionRandom];
    cursor -= 36;
    [self.sidebarView addSubview:self.randomSidebarButton];

    // Divider
    cursor -= 8;
    [self addSidebarDivider:cursor];
    cursor -= 8;

    // COLLECTIONS section
    cursor = [self addSectionLabel:@"COLLECTIONS" y:cursor - 18];

    NSArray<NSString *> *collectionNames = @[@"Anime", @"Nature", @"Cyberpunk", @"Space", @"Games", @"Movies"];
    for (NSInteger i = 0; i < collectionNames.count; i++) {
        NSString *name = collectionNames[i];
        NSButton *btn = [self sidebarButton:@"folder.fill" title:name y:cursor - 32 tag:SidebarSectionCollection + i];
        cursor -= 36;
        [self.sidebarView addSubview:btn];
        [self.collectionButtons addObject:btn];
    }

    // Divider
    cursor -= 8;
    [self addSidebarDivider:cursor];
    cursor -= 8;

    // SYSTEM section
    cursor = [self addSectionLabel:@"SYSTEM" y:cursor - 18];

    self.settingsSidebarButton = [self sidebarButton:@"gearshape.fill" title:@"Settings" y:cursor - 32 tag:SidebarSectionSettings];
    cursor -= 36;
    [self.sidebarView addSubview:self.settingsSidebarButton];

    NSButton *perfBtn = [self sidebarButton:@"chart.bar.fill" title:@"Performance" y:cursor - 32 tag:SidebarSectionSettings + 1];
    cursor -= 36;
    [self.sidebarView addSubview:perfBtn];

    NSButton *aboutBtn = [self sidebarButton:@"info.circle.fill" title:@"About" y:cursor - 32 tag:SidebarSectionSettings + 2];
    cursor -= 36;
    [self.sidebarView addSubview:aboutBtn];

    // Storage bar (pinned to bottom)
    NSTextField *storeLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 56, 130, 13)];
    storeLbl.stringValue = @"Storage Used";
    storeLbl.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    storeLbl.textColor = [NSColor secondaryLabelColor];
    storeLbl.editable = NO; storeLbl.bordered = NO;
    storeLbl.backgroundColor = [NSColor clearColor];
    storeLbl.autoresizingMask = NSViewMaxYMargin;
    [self.sidebarView addSubview:storeLbl];

    self.storageValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 43, sideW - 4, 13)];
    self.storageValueLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    self.storageValueLabel.textColor = [NSColor secondaryLabelColor];
    self.storageValueLabel.editable = NO; self.storageValueLabel.bordered = NO;
    self.storageValueLabel.backgroundColor = [NSColor clearColor];
    self.storageValueLabel.autoresizingMask = NSViewMaxYMargin;
    [self.sidebarView addSubview:self.storageValueLabel];
    [self updateStorageLabel];

    // Progress track
    self.storageProgressTrack = [[NSView alloc] initWithFrame:NSMakeRect(12, 30, sideW - 8, 4)];
    self.storageProgressTrack.wantsLayer = YES;
    self.storageProgressTrack.layer.cornerRadius = 2.0;
    self.storageProgressTrack.layer.backgroundColor = [[NSColor colorWithWhite:0.3 alpha:0.4] CGColor];
    self.storageProgressTrack.autoresizingMask = NSViewMaxYMargin;
    [self.sidebarView addSubview:self.storageProgressTrack];

    self.storageProgressFill = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 30, 4)];
    self.storageProgressFill.wantsLayer = YES;
    self.storageProgressFill.layer.cornerRadius = 2.0;
    self.storageProgressFill.layer.backgroundColor = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0] CGColor];
    [self.storageProgressTrack addSubview:self.storageProgressFill];

    [self updateSidebarSelection];
}

// Sidebar helper — section label
- (CGFloat)addSectionLabel:(NSString *)text y:(CGFloat)y {
    NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(12, y, kSidebarWidth - 16, 13)];
    lbl.stringValue = text;
    lbl.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold];
    lbl.textColor = [NSColor tertiaryLabelColor];
    lbl.editable = NO; lbl.bordered = NO;
    lbl.backgroundColor = [NSColor clearColor];
    lbl.autoresizingMask = NSViewMinYMargin;
    [self.sidebarView addSubview:lbl];
    return y;
}

// Sidebar helper — thin divider
- (void)addSidebarDivider:(CGFloat)y {
    NSView *div = [[NSView alloc] initWithFrame:NSMakeRect(12, y, kSidebarWidth - 24, 1)];
    div.wantsLayer = YES;
    div.layer.backgroundColor = [[NSColor separatorColor] CGColor];
    div.autoresizingMask = NSViewMinYMargin;
    [self.sidebarView addSubview:div];
}

// Sidebar helper — icon + text button
- (NSButton *)sidebarButton:(NSString *)symbolName title:(NSString *)title y:(CGFloat)y tag:(NSInteger)tag {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(8, y, kSidebarWidth - 16, 30)];
    btn.bezelStyle = NSBezelStyleInline;
    btn.bordered = NO;
    btn.wantsLayer = YES;
    btn.layer.cornerRadius = 7.0;
    btn.tag = tag;
    btn.target = self;
    btn.action = @selector(sidebarButtonClicked:);
    btn.autoresizingMask = NSViewMinYMargin;

    // Build attributed title with icon + space + text
    NSMutableAttributedString *attrTitle = [[NSMutableAttributedString alloc] init];
    if (@available(macOS 11.0, *)) {
        NSImage *icon = [NSImage imageWithSystemSymbolName:symbolName
                                  accessibilityDescription:nil];
        NSTextAttachment *att = [[NSTextAttachment alloc] init];
        att.image = icon;
        att.bounds = CGRectMake(0, -2, 14, 14);
        NSAttributedString *iconStr = [NSAttributedString attributedStringWithAttachment:att];
        [attrTitle appendAttributedString:iconStr];
        [attrTitle appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
    }
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    [attrTitle appendAttributedString:[[NSAttributedString alloc] initWithString:title attributes:attrs]];
    [btn setAttributedTitle:attrTitle];
    btn.imagePosition = NSImageLeft;
    return btn;
}

// Sidebar helper — right-side count badge
- (NSTextField *)badgeLabel:(NSString *)text x:(CGFloat)x y:(CGFloat)y {
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 36, 18)];
    f.stringValue = text;
    f.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    f.textColor = [NSColor secondaryLabelColor];
    f.alignment = NSTextAlignmentRight;
    f.editable = NO; f.bordered = NO;
    f.backgroundColor = [NSColor clearColor];
    f.autoresizingMask = NSViewMinYMargin;
    return f;
}

// ---------------------------------------------------------------------------
#pragma mark - Content Area

- (void)buildContentArea {
    NSView *cv = self.window.contentView;
    CGFloat cw = cv.bounds.size.width - kSidebarWidth;
    CGFloat ch = cv.bounds.size.height;

    self.contentArea = [[NSView alloc] initWithFrame:NSMakeRect(kSidebarWidth, 0, cw, ch)];
    self.contentArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.contentArea.wantsLayer = YES;
    self.contentArea.layer.backgroundColor = [[NSColor colorWithRed:0.067 green:0.071 blue:0.094 alpha:1.0] CGColor];
    [cv addSubview:self.contentArea];

    [self buildToolbar];
    [self buildHeroSection];
    [self buildGallery];
    [self buildMiniPlayer];
}

// ---------------------------------------------------------------------------
#pragma mark - Toolbar

- (void)buildToolbar {
    CGFloat cw = self.contentArea.bounds.size.width;
    CGFloat ch = self.contentArea.bounds.size.height;

    NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, ch - kToolbarHeight, cw, kToolbarHeight)];
    toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = [[NSColor colorWithRed:0.067 green:0.071 blue:0.094 alpha:0.95] CGColor];

    // Bottom separator
    NSView *sep = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cw, 1)];
    sep.autoresizingMask = NSViewWidthSizable;
    sep.wantsLayer = YES;
    sep.layer.backgroundColor = [[NSColor colorWithWhite:0.2 alpha:0.4] CGColor];
    [toolbar addSubview:sep];

    // Search field
    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(16, 11, 340, 30)];
    self.searchField.placeholderString = @"Search wallpapers...";
    self.searchField.delegate = self;
    self.searchField.target   = self;
    self.searchField.action   = @selector(searchFieldChanged:);
    self.searchField.sendsSearchStringImmediately = YES;
    self.searchField.wantsLayer = YES;
    self.searchField.layer.cornerRadius = 8.0;
    [toolbar addSubview:self.searchField];

    // Right-side icon buttons
    CGFloat bx = cw - 16;
    NSArray<NSString *> *symbols = @[@"rectangle.grid.2x2", @"gearshape", @"speaker.wave.2", @"shuffle"];
    SEL actions[4] = {
        @selector(noop:),
        @selector(showSettingsSheet:),
        @selector(toolbarToggleMute:),
        @selector(toolbarShuffle:)
    };
    for (NSInteger i = 0; i < 4; i++) {
        NSButton *btn = [NSButton buttonWithImage:[NSImage new] target:self action:NULL];
        if (@available(macOS 11.0, *)) {
            NSImage *img = [NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:nil];
            [btn setImage:img];
        }
        if (i == 2) self.muteToolbarButton = btn;
        if (i == 3) self.shuffleButton = btn;
        btn.bordered = NO;
        btn.wantsLayer = YES;
        btn.layer.cornerRadius = 6.0;
        btn.contentTintColor = [NSColor secondaryLabelColor];
        btn.frame = NSMakeRect(bx - 32, 11, 28, 28);
        bx -= 36;
        btn.target = self;
        btn.action = actions[i];
        [toolbar addSubview:btn];
    }

    [self.contentArea addSubview:toolbar];
}

// ---------------------------------------------------------------------------
#pragma mark - Hero Section

- (void)buildHeroSection {
    CGFloat cw = self.contentArea.bounds.size.width;
    CGFloat ch = self.contentArea.bounds.size.height;
    CGFloat heroY = ch - kToolbarHeight - kHeroHeight;

    self.heroContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, heroY, cw, kHeroHeight)];
    self.heroContainer.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.heroContainer.wantsLayer = YES;
    self.heroContainer.layer.backgroundColor = [[NSColor blackColor] CGColor];
    [self.contentArea addSubview:self.heroContainer];

    // Thumbnail fills entire hero
    self.heroThumbnailView = [[NSImageView alloc] initWithFrame:self.heroContainer.bounds];
    self.heroThumbnailView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.heroThumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.heroThumbnailView.wantsLayer = YES;
    self.heroThumbnailView.layer.masksToBounds = YES;
    [self.heroContainer addSubview:self.heroThumbnailView];

    // Dark gradient overlay across bottom third
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = CGRectMake(0, 0, cw, kHeroHeight);
    gradient.colors = @[
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.75].CGColor
    ];
    gradient.startPoint = CGPointMake(0, 0.6);
    gradient.endPoint   = CGPointMake(0, 0.0);
    [self.heroContainer.layer addSublayer:gradient];

    // Frosted info panel bottom-left
    self.heroInfoPanel = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(20, 14, 380, 160)];
    ((NSVisualEffectView *)self.heroInfoPanel).material = NSVisualEffectMaterialHUDWindow;
    ((NSVisualEffectView *)self.heroInfoPanel).blendingMode = NSVisualEffectBlendingModeWithinWindow;
    ((NSVisualEffectView *)self.heroInfoPanel).state = NSVisualEffectStateActive;
    self.heroInfoPanel.wantsLayer = YES;
    self.heroInfoPanel.layer.cornerRadius = 14.0;
    self.heroInfoPanel.layer.masksToBounds = YES;
    [self.heroContainer addSubview:self.heroInfoPanel];

    // PLAYING indicator row
    NSView *playingRow = [[NSView alloc] initWithFrame:NSMakeRect(14, 130, 200, 16)];
    NSView *playDot = [[NSView alloc] initWithFrame:NSMakeRect(0, 4, 8, 8)];
    playDot.wantsLayer = YES;
    playDot.layer.cornerRadius = 4.0;
    playDot.layer.backgroundColor = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0] CGColor];
    [playingRow addSubview:playDot];
    NSTextField *playingText = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 0, 120, 16)];
    playingText.stringValue = @"PLAYING";
    playingText.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    playingText.textColor = [NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0];
    playingText.editable = NO; playingText.bordered = NO;
    playingText.backgroundColor = [NSColor clearColor];
    [playingRow addSubview:playingText];
    [self.heroInfoPanel addSubview:playingRow];

    // Title
    self.heroTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 95, 350, 32)];
    self.heroTitleLabel.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
    self.heroTitleLabel.textColor = [NSColor whiteColor];
    self.heroTitleLabel.editable = NO; self.heroTitleLabel.bordered = NO;
    self.heroTitleLabel.backgroundColor = [NSColor clearColor];
    self.heroTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.heroInfoPanel addSubview:self.heroTitleLabel];

    // Meta (resolution • duration • size)
    self.heroMetaLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 78, 350, 16)];
    self.heroMetaLabel.font = [NSFont systemFontOfSize:11];
    self.heroMetaLabel.textColor = [NSColor colorWithWhite:0.65 alpha:1.0];
    self.heroMetaLabel.editable = NO; self.heroMetaLabel.bordered = NO;
    self.heroMetaLabel.backgroundColor = [NSColor clearColor];
    [self.heroInfoPanel addSubview:self.heroMetaLabel];

    // Description
    self.heroDescLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 48, 350, 28)];
    self.heroDescLabel.font = [NSFont systemFontOfSize:11];
    self.heroDescLabel.textColor = [NSColor colorWithWhite:0.55 alpha:1.0];
    self.heroDescLabel.editable = NO; self.heroDescLabel.bordered = NO;
    self.heroDescLabel.backgroundColor = [NSColor clearColor];
    self.heroDescLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.heroInfoPanel addSubview:self.heroDescLabel];

    // Action buttons row
    CGFloat btnY = 12;
    // Apply button (blue)
    NSButton *applyBtn = [[NSButton alloc] initWithFrame:NSMakeRect(14, btnY, 80, 28)];
    applyBtn.title = @"Apply";
    applyBtn.bezelStyle = NSBezelStyleRounded;
    applyBtn.wantsLayer = YES;
    applyBtn.layer.cornerRadius = 7.0;
    applyBtn.layer.backgroundColor = [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0] CGColor];
    applyBtn.contentTintColor = [NSColor whiteColor];
    applyBtn.target = self; applyBtn.action = @selector(applyHeroWallpaper:);
    [self.heroInfoPanel addSubview:applyBtn];

    // Favorite
    self.heroFavoriteButton = [[NSButton alloc] initWithFrame:NSMakeRect(102, btnY, 28, 28)];
    self.heroFavoriteButton.bordered = NO;
    self.heroFavoriteButton.bezelStyle = NSBezelStyleInline;
    self.heroFavoriteButton.target = self;
    self.heroFavoriteButton.action = @selector(heroFavoriteClicked:);
    [self updateHeroFavoriteButton];
    [self.heroInfoPanel addSubview:self.heroFavoriteButton];

    // Info
    NSButton *infoBtn = [[NSButton alloc] initWithFrame:NSMakeRect(136, btnY, 28, 28)];
    infoBtn.bordered = NO;
    if (@available(macOS 11.0, *)) {
        [infoBtn setImage:[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil]];
    }
    infoBtn.contentTintColor = [NSColor secondaryLabelColor];
    infoBtn.target = self; infoBtn.action = @selector(noop:);
    [self.heroInfoPanel addSubview:infoBtn];

    // Random
    NSButton *randomBtn = [[NSButton alloc] initWithFrame:NSMakeRect(170, btnY, 90, 28)];
    randomBtn.title = @" Random";
    randomBtn.bezelStyle = NSBezelStyleRounded;
    randomBtn.wantsLayer = YES;
    randomBtn.layer.cornerRadius = 7.0;
    randomBtn.layer.backgroundColor = [[NSColor colorWithWhite:0.25 alpha:0.6] CGColor];
    randomBtn.contentTintColor = [NSColor whiteColor];
    randomBtn.target = self; randomBtn.action = @selector(playRandomWallpaper:);
    [self.heroInfoPanel addSubview:randomBtn];

    // Mouse tracking for hover video preview
    [self resetHeroTrackingArea];
}

- (void)resetHeroTrackingArea {
    if (self.heroTrackingArea) {
        [self.heroContainer removeTrackingArea:self.heroTrackingArea];
    }
    self.heroTrackingArea = [[NSTrackingArea alloc]
        initWithRect:self.heroContainer.bounds
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow)
               owner:self
            userInfo:nil];
    [self.heroContainer addTrackingArea:self.heroTrackingArea];
}

// Hero hover — play video preview on mouse enter
- (void)mouseEntered:(NSEvent *)event {
    if (event.trackingArea != self.heroTrackingArea) return;
    [self startHeroVideoPreview];
}

- (void)mouseExited:(NSEvent *)event {
    if (event.trackingArea != self.heroTrackingArea) return;
    [self stopHeroVideoPreview];
}

- (void)startHeroVideoPreview {
    NSString *wid = self.playingWallpaperId;
    if (!wid) return;
    NSPredicate *p = [NSPredicate predicateWithFormat:@"id == %@", wid];
    NSDictionary *vid = [[self.videos filteredArrayUsingPredicate:p] firstObject];
    if (!vid) return;

    NSURL *url = [NSURL fileURLWithPath:vid[@"path"]];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.heroPreviewPlayer = [AVPlayer playerWithPlayerItem:item];
    self.heroPreviewPlayer.muted = YES;

    if (!self.heroPreviewLayer) {
        self.heroPreviewLayer = [AVPlayerLayer playerLayerWithPlayer:self.heroPreviewPlayer];
        self.heroPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        self.heroPreviewLayer.frame = self.heroThumbnailView.bounds;
        self.heroPreviewLayer.opacity = 0.0;
        [self.heroThumbnailView.layer addSublayer:self.heroPreviewLayer];
    } else {
        self.heroPreviewLayer.player = self.heroPreviewPlayer;
    }
    self.heroPreviewLayer.frame = self.heroThumbnailView.bounds;

    [self.heroPreviewPlayer play];

    CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeIn.fromValue = @0.0;
    fadeIn.toValue   = @1.0;
    fadeIn.duration  = 0.3;
    self.heroPreviewLayer.opacity = 1.0;
    [self.heroPreviewLayer addAnimation:fadeIn forKey:@"fadeIn"];
}

- (void)stopHeroVideoPreview {
    [self.heroPreviewPlayer pause];
    CABasicAnimation *fadeOut = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeOut.fromValue = @1.0;
    fadeOut.toValue   = @0.0;
    fadeOut.duration  = 0.25;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        self.heroPreviewPlayer = nil;
    }];
    self.heroPreviewLayer.opacity = 0.0;
    [self.heroPreviewLayer addAnimation:fadeOut forKey:@"fadeOut"];
    [CATransaction commit];
}

// ---------------------------------------------------------------------------
#pragma mark - Gallery

- (void)buildGallery {
    CGFloat cw = self.contentArea.bounds.size.width;
    CGFloat ch = self.contentArea.bounds.size.height;
    CGFloat galleryTop = ch - kToolbarHeight - kHeroHeight - kGalleryHeaderHeight;
    CGFloat galleryH   = galleryTop - kMiniPlayerHeight;

    // Gallery header bar
    NSView *hdr = [[NSView alloc] initWithFrame:NSMakeRect(0, galleryTop, cw, kGalleryHeaderHeight)];
    hdr.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    hdr.wantsLayer = YES;
    hdr.layer.backgroundColor = [[NSColor colorWithRed:0.075 green:0.079 blue:0.102 alpha:1.0] CGColor];
    [self.contentArea addSubview:hdr];

    self.galleryHeaderLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 12, 220, 20)];
    self.galleryHeaderLabel.stringValue = @"All Wallpapers";
    self.galleryHeaderLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    self.galleryHeaderLabel.textColor = [NSColor labelColor];
    self.galleryHeaderLabel.editable = NO; self.galleryHeaderLabel.bordered = NO;
    self.galleryHeaderLabel.backgroundColor = [NSColor clearColor];
    [hdr addSubview:self.galleryHeaderLabel];

    self.countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(250, 14, 120, 16)];
    self.countLabel.stringValue = @"";
    self.countLabel.font = [NSFont systemFontOfSize:11];
    self.countLabel.textColor = [NSColor secondaryLabelColor];
    self.countLabel.editable = NO; self.countLabel.bordered = NO;
    self.countLabel.backgroundColor = [NSColor clearColor];
    [hdr addSubview:self.countLabel];

    // Collection view
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(195, 160);
    layout.minimumInteritemSpacing = 16;
    layout.minimumLineSpacing      = 16;
    layout.sectionInset = NSEdgeInsetsMake(16, 20, 16, 20);
    layout.scrollDirection = NSCollectionViewScrollDirectionVertical;

    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, cw, galleryH)];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate   = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColors = @[[NSColor colorWithRed:0.067 green:0.071 blue:0.094 alpha:1.0]];
    self.collectionView.selectable = YES;
    [self.collectionView registerClass:[VideoCollectionItem class] forItemWithIdentifier:@"VideoItem"];

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, kMiniPlayerHeight, cw, galleryH)];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.documentView  = self.collectionView;
    self.scrollView.hasVerticalScroller   = YES;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.drawsBackground = NO;
    [self.contentArea addSubview:self.scrollView];
}

// ---------------------------------------------------------------------------
#pragma mark - Mini Player

- (void)buildMiniPlayer {
    CGFloat cw = self.contentArea.bounds.size.width;

    self.miniPlayerView = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, cw, kMiniPlayerHeight)];
    self.miniPlayerView.autoresizingMask = NSViewWidthSizable;
    self.miniPlayerView.material    = NSVisualEffectMaterialHUDWindow;
    self.miniPlayerView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.miniPlayerView.state = NSVisualEffectStateActive;
    self.miniPlayerView.wantsLayer = YES;

    // Top border
    NSView *topBorder = [[NSView alloc] initWithFrame:NSMakeRect(0, kMiniPlayerHeight - 1, cw, 1)];
    topBorder.autoresizingMask = NSViewWidthSizable;
    topBorder.wantsLayer = YES;
    topBorder.layer.backgroundColor = [[NSColor colorWithWhite:0.25 alpha:0.5] CGColor];
    [self.miniPlayerView addSubview:topBorder];

    // Thumbnail
    self.miniPlayerThumb = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 10, 86, 55)];
    self.miniPlayerThumb.wantsLayer = YES;
    self.miniPlayerThumb.layer.cornerRadius = 6.0;
    self.miniPlayerThumb.layer.masksToBounds = YES;
    self.miniPlayerThumb.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self.miniPlayerView addSubview:self.miniPlayerThumb];

    // "Currently Playing" label
    NSTextField *nowPlaying = [[NSTextField alloc] initWithFrame:NSMakeRect(108, 42, 220, 12)];
    nowPlaying.stringValue = @"Currently Playing";
    nowPlaying.font = [NSFont systemFontOfSize:9.5];
    nowPlaying.textColor = [NSColor secondaryLabelColor];
    nowPlaying.editable = NO; nowPlaying.bordered = NO;
    nowPlaying.backgroundColor = [NSColor clearColor];
    [self.miniPlayerView addSubview:nowPlaying];

    self.miniPlayerTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(108, 26, 220, 17)];
    self.miniPlayerTitleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.miniPlayerTitleLabel.textColor = [NSColor labelColor];
    self.miniPlayerTitleLabel.editable = NO; self.miniPlayerTitleLabel.bordered = NO;
    self.miniPlayerTitleLabel.backgroundColor = [NSColor clearColor];
    self.miniPlayerTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.miniPlayerView addSubview:self.miniPlayerTitleLabel];

    self.miniPlayerMetaLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(108, 12, 220, 13)];
    self.miniPlayerMetaLabel.font = [NSFont systemFontOfSize:10];
    self.miniPlayerMetaLabel.textColor = [NSColor secondaryLabelColor];
    self.miniPlayerMetaLabel.editable = NO; self.miniPlayerMetaLabel.bordered = NO;
    self.miniPlayerMetaLabel.backgroundColor = [NSColor clearColor];
    [self.miniPlayerView addSubview:self.miniPlayerMetaLabel];

    // Playback controls (centered)
    CGFloat ctrlX = (cw - 120) / 2.0;
    NSArray<NSString *> *ctrlSymbols = @[@"backward.end.fill", @"pause.fill", @"forward.end.fill"];
    for (NSInteger i = 0; i < 3; i++) {
        NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(ctrlX + i * 40, 22, 32, 32)];
        b.bordered = NO;
        if (@available(macOS 11.0, *)) {
            [b setImage:[NSImage imageWithSystemSymbolName:ctrlSymbols[i] accessibilityDescription:nil]];
        }
        b.contentTintColor = [NSColor labelColor];
        if (i == 0) { b.target = self; b.action = @selector(prevWallpaper:); }
        if (i == 1) { self.miniPlayPauseButton = b; b.target = self; b.action = @selector(miniPlayPause:); }
        if (i == 2) { b.target = self; b.action = @selector(nextWallpaper:); }
        [self.miniPlayerView addSubview:b];
    }

    // Right controls: volume + shuffle
    CGFloat rvX = cw - 160;
    NSButton *volBtn = [[NSButton alloc] initWithFrame:NSMakeRect(rvX, 22, 26, 26)];
    volBtn.bordered = NO;
    if (@available(macOS 11.0, *)) {
        [volBtn setImage:[NSImage imageWithSystemSymbolName:@"speaker.wave.2" accessibilityDescription:nil]];
    }
    volBtn.contentTintColor = [NSColor secondaryLabelColor];
    volBtn.target = self; volBtn.action = @selector(toolbarToggleMute:);
    [self.miniPlayerView addSubview:volBtn];

    NSSlider *volSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(rvX + 30, 26, 80, 18)];
    volSlider.minValue = 0; volSlider.maxValue = 1; volSlider.doubleValue = 0.7;
    volSlider.target = self; volSlider.action = @selector(noop:);
    [self.miniPlayerView addSubview:volSlider];

    NSButton *shuffleBtn = [[NSButton alloc] initWithFrame:NSMakeRect(cw - 36, 22, 26, 26)];
    shuffleBtn.bordered = NO;
    shuffleBtn.autoresizingMask = NSViewMinXMargin;
    if (@available(macOS 11.0, *)) {
        [shuffleBtn setImage:[NSImage imageWithSystemSymbolName:@"shuffle" accessibilityDescription:nil]];
    }
    shuffleBtn.contentTintColor = [NSColor secondaryLabelColor];
    shuffleBtn.target = self; shuffleBtn.action = @selector(toolbarShuffle:);
    [self.miniPlayerView addSubview:shuffleBtn];

    [self.contentArea addSubview:self.miniPlayerView];
}

// ---------------------------------------------------------------------------
#pragma mark - Data Loading

- (void)loadVideos {
    std::vector<Macie::WallpaperProject> wallpapers = [self.assetManager getVideoWallpapers];

    NSMutableArray *arr = [NSMutableArray array];
    for (const auto &w : wallpapers) {
        [arr addObject:@{
            @"id":    [NSString stringWithUTF8String:w.id.c_str()],
            @"title": [NSString stringWithUTF8String:w.title.c_str()],
            @"path":  [NSString stringWithUTF8String:w.videoFilePath.c_str()]
        }];
    }

    self.videos = [arr copy];
    self.filteredVideos = self.videos;
    self.activeSidebarSection = SidebarSectionLibrary;
    [self.searchField setStringValue:@""];
    [self.collectionView reloadData];

    // Determine the currently playing wallpaper ID
    NSString *savedId = [[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsLastWallpaperId];
    self.playingWallpaperId = savedId;

    [self updateCountLabel];
    [self updateSidebarBadges];
    [self updateHeroForCurrentWallpaper];
    [self updateMiniPlayer];
}

// ---------------------------------------------------------------------------
#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.filteredVideos.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv
         itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    VideoCollectionItem *item = [cv makeItemWithIdentifier:@"VideoItem" forIndexPath:indexPath];
    NSDictionary *video = self.filteredVideos[indexPath.item];
    BOOL fav     = [self.favoriteIds containsObject:video[@"id"]];
    BOOL playing = [video[@"id"] isEqualToString:self.playingWallpaperId];
    [item configureWithVideoData:video isFavorite:fav isPlaying:playing];
    return item;
}

// ---------------------------------------------------------------------------
#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)cv didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *ip = indexPaths.anyObject;
    if (!ip) return;

    NSDictionary *video    = self.filteredVideos[ip.item];
    NSString *videoPath    = video[@"path"];
    NSString *videoTitle   = video[@"title"];
    NSString *videoId      = video[@"id"];

    BOOL wasMuted = self.videoRenderer.muted;
    BOOL success  = [self.videoRenderer loadAndPlayVideo:videoPath];

    if (success) {
        self.playingWallpaperId = videoId;

        // Persist last-played ID
        [[NSUserDefaults standardUserDefaults] setObject:videoId forKey:kDefaultsLastWallpaperId];

        // Track recent (most-recent first, max 20)
        [self.recentIds removeObject:videoId];
        [self.recentIds insertObject:videoId atIndex:0];
        while (self.recentIds.count > 20) [self.recentIds removeLastObject];
        [self saveRecentIds];

        if (wasMuted) [self.videoRenderer mute];
        [self updateHeroForWallpaper:video];
        [self updateMiniPlayer];
        [self.collectionView reloadData];
        [self updateSidebarBadges];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Search

- (void)updateCountLabel {
    if (self.filteredVideos.count == self.videos.count) {
        self.countLabel.stringValue = [NSString stringWithFormat:@"%lu wallpapers",
                                       (unsigned long)self.videos.count];
    } else {
        self.countLabel.stringValue = [NSString stringWithFormat:@"%lu of %lu",
                                       (unsigned long)self.filteredVideos.count,
                                       (unsigned long)self.videos.count];
    }
}

- (void)searchFieldChanged:(NSSearchField *)sender {
    [self applySearchFilter:sender.stringValue];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.searchField) {
        [self applySearchFilter:self.searchField.stringValue];
    }
}

- (void)applySearchFilter:(NSString *)query {
    NSArray *source = [self sourceArrayForCurrentSidebar];
    if (query.length == 0) {
        self.filteredVideos = source;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"title CONTAINS[cd] %@", query];
        self.filteredVideos = [source filteredArrayUsingPredicate:pred];
    }
    [self.collectionView reloadData];
    [self updateCountLabel];
}

/// Returns the subset of self.videos that the active sidebar section describes.
- (NSArray<NSDictionary *> *)sourceArrayForCurrentSidebar {
    switch (self.activeSidebarSection) {
        case SidebarSectionFavorites:
            return [self.videos filteredArrayUsingPredicate:
                [NSPredicate predicateWithFormat:@"id IN %@", self.favoriteIds]];
        case SidebarSectionRecent: {
            NSMutableArray *out = [NSMutableArray array];
            for (NSString *rid in self.recentIds) {
                for (NSDictionary *v in self.videos) {
                    if ([v[@"id"] isEqualToString:rid]) { [out addObject:v]; break; }
                }
            }
            return [out copy];
        }
        default:
            if (self.activeSidebarSection >= SidebarSectionCollection &&
                self.activeCollectionName) {
                NSArray<NSString *> *kws = CollectionKeywords()[self.activeCollectionName];
                NSMutableArray *out = [NSMutableArray array];
                for (NSDictionary *v in self.videos) {
                    NSString *lower = [v[@"title"] lowercaseString];
                    for (NSString *kw in kws) {
                        if ([lower containsString:kw]) { [out addObject:v]; break; }
                    }
                }
                return [out copy];
            }
            return self.videos;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Sidebar Actions

- (void)sidebarButtonClicked:(NSButton *)sender {
    NSInteger tag = sender.tag;

    if (tag == SidebarSectionRandom) {
        [self playRandomWallpaper:sender];
        return;
    }
    if (tag >= SidebarSectionSettings) {
        [self showSettingsSheet:sender];
        return;
    }

    self.activeSidebarSection = (SidebarSection)tag;

    if (tag >= SidebarSectionCollection) {
        NSInteger idx = tag - SidebarSectionCollection;
        NSArray<NSString *> *names = @[@"Anime", @"Nature", @"Cyberpunk", @"Space", @"Games", @"Movies"];
        if (idx < (NSInteger)names.count) {
            self.activeCollectionName = names[idx];
            self.galleryHeaderLabel.stringValue = names[idx];
        }
    } else {
        self.activeCollectionName = nil;
        NSArray<NSString *> *titles = @[@"Library", @"Favorites", @"Recent"];
        if (tag < (NSInteger)titles.count) {
            self.galleryHeaderLabel.stringValue = titles[tag];
        }
    }

    [self.searchField setStringValue:@""];
    self.filteredVideos = [self sourceArrayForCurrentSidebar];
    [self.collectionView reloadData];
    [self updateCountLabel];
    [self updateSidebarSelection];
}

- (void)updateSidebarSelection {
    NSArray<NSButton *> *all = [self allSidebarButtons];
    for (NSButton *btn in all) {
        BOOL active = (btn.tag == self.activeSidebarSection);
        btn.wantsLayer = YES;
        btn.layer.backgroundColor = active
            ? [[NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:0.2] CGColor]
            : [NSColor clearColor].CGColor;
        // Highlight text
        NSMutableAttributedString *title = [btn.attributedTitle mutableCopy];
        [title addAttribute:NSForegroundColorAttributeName
                      value:(active ? [NSColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0]
                                    : [NSColor labelColor])
                      range:NSMakeRange(0, title.length)];
        [btn setAttributedTitle:title];
    }
}

- (NSArray<NSButton *> *)allSidebarButtons {
    NSMutableArray *all = [NSMutableArray arrayWithObjects:
        self.librarySidebarButton, self.favoritesSidebarButton,
        self.recentSidebarButton, self.randomSidebarButton,
        self.settingsSidebarButton, nil];
    [all addObjectsFromArray:self.collectionButtons];
    return [all copy];
}

// ---------------------------------------------------------------------------
#pragma mark - Sidebar Badge Updates

- (void)updateSidebarBadges {
    self.libraryCountLabel.stringValue   = [NSString stringWithFormat:@"%lu", (unsigned long)self.videos.count];
    self.favoritesCountLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.favoriteIds.count];
    self.recentCountLabel.stringValue    = [NSString stringWithFormat:@"%lu", (unsigned long)self.recentIds.count];
}

- (void)updateStorageLabel {
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    long long total = [[attrs objectForKey:NSFileSystemSize] longLongValue];
    long long free  = [[attrs objectForKey:NSFileSystemFreeSize] longLongValue];
    long long used  = total - free;

    CGFloat usedGB  = used  / 1e9;
    CGFloat totalGB = total / 1e9;

    self.storageValueLabel.stringValue = [NSString stringWithFormat:@"%.1f GB / %.0f GB", usedGB, totalGB];

    CGFloat fillRatio = (total > 0) ? (CGFloat)used / (CGFloat)total : 0;
    CGFloat trackW = self.storageProgressTrack.bounds.size.width;
    self.storageProgressFill.frame = NSMakeRect(0, 0, trackW * fillRatio, 4);
}

// ---------------------------------------------------------------------------
#pragma mark - Hero Section Updates

- (void)updateHeroForCurrentWallpaper {
    if (!self.playingWallpaperId) { return; }
    NSPredicate *p = [NSPredicate predicateWithFormat:@"id == %@", self.playingWallpaperId];
    NSDictionary *vid = [[self.videos filteredArrayUsingPredicate:p] firstObject];
    if (vid) [self updateHeroForWallpaper:vid];
}

- (void)updateHeroForWallpaper:(NSDictionary *)video {
    self.heroTitleLabel.stringValue = video[@"title"] ?: @"";
    self.heroMetaLabel.stringValue  = @"4K • Video";
    self.heroDescLabel.stringValue  = @"";   // project.json description can be added later
    [self updateHeroFavoriteButton];

    // Load hero thumbnail asynchronously
    NSString *videoId   = video[@"id"];
    NSString *videoPath = video[@"path"];
    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSImage *cached = [cache cachedThumbnailForId:videoId];
    if (cached) {
        self.heroThumbnailView.image = cached;
        return;
    }
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *dir     = [videoPath stringByDeletingLastPathComponent];
        NSString *preview = [dir stringByAppendingPathComponent:@"preview.jpg"];
        NSImage *thumb = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:preview]) {
            thumb = [cache thumbnailForPreviewPath:preview wallpaperId:videoId];
        }
        if (!thumb) thumb = [cache thumbnailForVideoPath:videoPath wallpaperId:videoId];
        if (thumb) {
            dispatch_async(dispatch_get_main_queue(), ^{ ws.heroThumbnailView.image = thumb; });
        }
    });
}

- (void)updateHeroFavoriteButton {
    if (!self.heroFavoriteButton) return;
    BOOL fav = self.playingWallpaperId && [self.favoriteIds containsObject:self.playingWallpaperId];
    if (@available(macOS 11.0, *)) {
        NSString *sym = fav ? @"heart.fill" : @"heart";
        [self.heroFavoriteButton setImage:[NSImage imageWithSystemSymbolName:sym accessibilityDescription:nil]];
        self.heroFavoriteButton.contentTintColor = fav ? [NSColor systemPinkColor] : [NSColor secondaryLabelColor];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Mini Player Updates

- (void)updateMiniPlayer {
    if (!self.playingWallpaperId) return;
    NSPredicate *p = [NSPredicate predicateWithFormat:@"id == %@", self.playingWallpaperId];
    NSDictionary *vid = [[self.videos filteredArrayUsingPredicate:p] firstObject];
    if (!vid) return;

    self.miniPlayerTitleLabel.stringValue = vid[@"title"] ?: @"";
    self.miniPlayerMetaLabel.stringValue  = @"4K";

    NSString *vidId   = vid[@"id"];
    NSString *vidPath = vid[@"path"];
    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSImage *cached = [cache cachedThumbnailForId:vidId];
    if (cached) { self.miniPlayerThumb.image = cached; return; }

    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *dir     = [vidPath stringByDeletingLastPathComponent];
        NSString *preview = [dir stringByAppendingPathComponent:@"preview.jpg"];
        NSImage *thumb = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:preview]) {
            thumb = [cache thumbnailForPreviewPath:preview wallpaperId:vidId];
        }
        if (!thumb) thumb = [cache thumbnailForVideoPath:vidPath wallpaperId:vidId];
        if (thumb) dispatch_async(dispatch_get_main_queue(), ^{ ws.miniPlayerThumb.image = thumb; });
    });
}

// ---------------------------------------------------------------------------
#pragma mark - Favorites

- (NSMutableSet<NSString *> *)loadFavoriteIds {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kDefaultsFavoriteIds];
    return saved ? [NSMutableSet setWithArray:saved] : [NSMutableSet set];
}

- (void)saveFavoriteIds {
    [[NSUserDefaults standardUserDefaults]
        setObject:self.favoriteIds.allObjects forKey:kDefaultsFavoriteIds];
}

- (NSMutableArray<NSString *> *)loadRecentIds {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kDefaultsRecentIds];
    return saved ? [NSMutableArray arrayWithArray:saved] : [NSMutableArray array];
}

- (void)saveRecentIds {
    [[NSUserDefaults standardUserDefaults] setObject:self.recentIds forKey:kDefaultsRecentIds];
}

- (void)setupFavoriteToggleObserver {
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(wallpaperFavoriteToggled:)
               name:@"WallpaperFavoriteToggled"
             object:nil];
}

- (void)wallpaperFavoriteToggled:(NSNotification *)note {
    NSString *wid = note.userInfo[@"id"];
    BOOL fav = [note.userInfo[@"favorite"] boolValue];
    if (!wid.length) return;

    if (fav) {
        [self.favoriteIds addObject:wid];
    } else {
        [self.favoriteIds removeObject:wid];
    }
    [self saveFavoriteIds];
    [self updateSidebarBadges];
    if ([wid isEqualToString:self.playingWallpaperId]) {
        [self updateHeroFavoriteButton];
    }
}

- (void)heroFavoriteClicked:(NSButton *)sender {
    if (!self.playingWallpaperId) return;
    BOOL isFav = [self.favoriteIds containsObject:self.playingWallpaperId];
    if (isFav) {
        [self.favoriteIds removeObject:self.playingWallpaperId];
    } else {
        [self.favoriteIds addObject:self.playingWallpaperId];
    }
    [self saveFavoriteIds];
    [self updateHeroFavoriteButton];
    [self updateSidebarBadges];
    [self.collectionView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - Playback Controls

- (void)applyHeroWallpaper:(id)sender {
    // The playing wallpaper is already applied to the desktop.
    // This button can be used to re-apply if it was paused via performance monitor.
    [self.videoRenderer play];
}

- (void)playRandomWallpaper:(id)sender {
    if (self.videos.count == 0) return;
    NSUInteger idx = arc4random_uniform((uint32_t)self.videos.count);
    NSDictionary *video = self.videos[idx];
    BOOL wasMuted = self.videoRenderer.muted;
    BOOL success  = [self.videoRenderer loadAndPlayVideo:video[@"path"]];
    if (success) {
        self.playingWallpaperId = video[@"id"];
        [[NSUserDefaults standardUserDefaults] setObject:video[@"id"] forKey:kDefaultsLastWallpaperId];
        if (wasMuted) [self.videoRenderer mute];
        [self updateHeroForWallpaper:video];
        [self updateMiniPlayer];
        [self.collectionView reloadData];
    }
}

- (void)prevWallpaper:(id)sender {
    if (!self.playingWallpaperId || self.videos.count == 0) return;
    NSInteger cur = -1;
    for (NSInteger i = 0; i < (NSInteger)self.videos.count; i++) {
        if ([self.videos[i][@"id"] isEqualToString:self.playingWallpaperId]) { cur = i; break; }
    }
    NSInteger prev = (cur <= 0) ? (NSInteger)self.videos.count - 1 : cur - 1;
    NSDictionary *video = self.videos[prev];
    if ([self.videoRenderer loadAndPlayVideo:video[@"path"]]) {
        self.playingWallpaperId = video[@"id"];
        [[NSUserDefaults standardUserDefaults] setObject:video[@"id"] forKey:kDefaultsLastWallpaperId];
        [self updateHeroForWallpaper:video];
        [self updateMiniPlayer];
        [self.collectionView reloadData];
    }
}

- (void)nextWallpaper:(id)sender {
    if (!self.playingWallpaperId || self.videos.count == 0) return;
    NSInteger cur = -1;
    for (NSInteger i = 0; i < (NSInteger)self.videos.count; i++) {
        if ([self.videos[i][@"id"] isEqualToString:self.playingWallpaperId]) { cur = i; break; }
    }
    NSInteger next = (cur >= (NSInteger)self.videos.count - 1) ? 0 : cur + 1;
    NSDictionary *video = self.videos[next];
    if ([self.videoRenderer loadAndPlayVideo:video[@"path"]]) {
        self.playingWallpaperId = video[@"id"];
        [[NSUserDefaults standardUserDefaults] setObject:video[@"id"] forKey:kDefaultsLastWallpaperId];
        [self updateHeroForWallpaper:video];
        [self updateMiniPlayer];
        [self.collectionView reloadData];
    }
}

- (void)miniPlayPause:(id)sender {
    // Toggle between play/pause on the desktop renderer
    [self.videoRenderer play];   // AVVideoRenderer handles no-op if already playing
}

- (void)toolbarToggleMute:(id)sender {
    if (self.videoRenderer.muted) {
        [self.videoRenderer unmute];
    } else {
        [self.videoRenderer mute];
    }
    [[NSUserDefaults standardUserDefaults] setBool:self.videoRenderer.muted forKey:kDefaultsLastMuteState];
}

- (void)toolbarShuffle:(id)sender {
    [self playRandomWallpaper:sender];
}

// ---------------------------------------------------------------------------
#pragma mark - Settings Sheet

- (void)showSettingsSheet:(id)sender {
    NSWindow *sheet = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 480, 380)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    sheet.title = @"Settings";

    NSView *sv = sheet.contentView;
    sv.wantsLayer = YES;
    sv.layer.backgroundColor = [[NSColor colorWithRed:0.11 green:0.11 blue:0.13 alpha:1.0] CGColor];

    CGFloat lp = 24;
    CGFloat y  = 320;

    // Path
    NSTextField *pathHdr = [self settingsHeader:@"Wallpaper Location" y:y];
    [sv addSubview:pathHdr]; y -= 28;

    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    NSString *cur = [def stringForKey:kDefaultsSteamappsPath];
    NSTextField *pathVal = [[NSTextField alloc] initWithFrame:NSMakeRect(lp, y, 432, 22)];
    pathVal.stringValue = cur ?: @"Not configured";
    pathVal.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    pathVal.textColor = cur ? [NSColor systemGreenColor] : [NSColor systemRedColor];
    pathVal.editable = NO; pathVal.bordered = YES;
    pathVal.backgroundColor = [NSColor colorWithWhite:0.08 alpha:1.0];
    [sv addSubview:pathVal]; y -= 34;

    NSButton *changeBtn = [[NSButton alloc] initWithFrame:NSMakeRect(lp, y, 180, 26)];
    changeBtn.title = @"Change Steam Folder...";
    changeBtn.bezelStyle = NSBezelStyleRounded;
    changeBtn.target = self; changeBtn.action = @selector(changePathFromPreferences:);
    [sv addSubview:changeBtn]; y -= 44;

    // Performance
    NSTextField *perfHdr = [self settingsHeader:@"Performance" y:y];
    [sv addSubview:perfHdr]; y -= 28;

    NSButton *batCb = [[NSButton alloc] initWithFrame:NSMakeRect(lp, y, 400, 22)];
    [batCb setButtonType:NSButtonTypeSwitch];
    batCb.title = @"Pause wallpaper when on battery power";
    batCb.state = [def boolForKey:kDefaultsPauseOnBattery] ? NSControlStateValueOn : NSControlStateValueOff;
    batCb.target = self; batCb.action = @selector(pauseOnBatteryChanged:);
    [sv addSubview:batCb]; y -= 28;

    NSButton *fsCb = [[NSButton alloc] initWithFrame:NSMakeRect(lp, y, 400, 22)];
    [fsCb setButtonType:NSButtonTypeSwitch];
    fsCb.title = @"Pause wallpaper when apps are fullscreen";
    fsCb.state = [def boolForKey:kDefaultsPauseOnFullscreen] ? NSControlStateValueOn : NSControlStateValueOff;
    fsCb.target = self; fsCb.action = @selector(pauseOnFullscreenChanged:);
    [sv addSubview:fsCb]; y -= 44;

    // Cache
    NSTextField *cacheHdr = [self settingsHeader:@"Thumbnail Cache" y:y];
    [sv addSubview:cacheHdr]; y -= 28;

    self.cacheSizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(lp, y, 350, 18)];
    [self updateCacheSizeLabel];
    self.cacheSizeLabel.font = [NSFont systemFontOfSize:12];
    self.cacheSizeLabel.textColor = [NSColor secondaryLabelColor];
    self.cacheSizeLabel.editable = NO; self.cacheSizeLabel.bordered = NO;
    self.cacheSizeLabel.backgroundColor = [NSColor clearColor];
    [sv addSubview:self.cacheSizeLabel]; y -= 28;

    NSButton *clrBtn = [[NSButton alloc] initWithFrame:NSMakeRect(lp, y, 130, 26)];
    clrBtn.title = @"Clear Cache";
    clrBtn.bezelStyle = NSBezelStyleRounded;
    clrBtn.target = self; clrBtn.action = @selector(clearThumbnailCache:);
    [sv addSubview:clrBtn]; y -= 44;

    // Launch at login
    NSTextField *startHdr = [self settingsHeader:@"Startup" y:y];
    [sv addSubview:startHdr]; y -= 28;

    NSButton *loginCb = [[NSButton alloc] initWithFrame:NSMakeRect(lp, y, 380, 22)];
    [loginCb setButtonType:NSButtonTypeSwitch];
    loginCb.title = @"Launch MacieWallpaper at login";
    loginCb.state = [self isLaunchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    loginCb.target = self; loginCb.action = @selector(launchAtLoginChanged:);
    [sv addSubview:loginCb];

    // Close button
    NSButton *doneBtn = [[NSButton alloc] initWithFrame:NSMakeRect(390, 12, 70, 28)];
    doneBtn.title = @"Done";
    doneBtn.bezelStyle = NSBezelStyleRounded;
    doneBtn.keyEquivalent = @"\r";
    doneBtn.target = self; doneBtn.action = @selector(closeSettingsSheet:);
    [sv addSubview:doneBtn];

    [self.window beginSheet:sheet completionHandler:nil];
}

- (NSTextField *)settingsHeader:(NSString *)title y:(CGFloat)y {
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(24, y, 420, 18)];
    f.stringValue = title;
    f.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    f.textColor = [NSColor labelColor];
    f.editable = NO; f.bordered = NO;
    f.backgroundColor = [NSColor clearColor];
    return f;
}

- (void)closeSettingsSheet:(id)sender {
    [self.window endSheet:self.window.attachedSheet];
}

// ---------------------------------------------------------------------------
#pragma mark - Settings Actions (kept from prior implementation)

- (void)changePathFromPreferences:(id)sender {
    if (self.onWallpapersReloadRequested) self.onWallpapersReloadRequested();
}

- (void)pauseOnBatteryChanged:(id)sender {
    NSButton *cb = (NSButton *)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(cb.state == NSControlStateValueOn) forKey:kDefaultsPauseOnBattery];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PerformanceSettingsChanged" object:nil];
}

- (void)pauseOnFullscreenChanged:(id)sender {
    NSButton *cb = (NSButton *)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(cb.state == NSControlStateValueOn) forKey:kDefaultsPauseOnFullscreen];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PerformanceSettingsChanged" object:nil];
}

// ---------------------------------------------------------------------------
#pragma mark - Cache Management

- (void)updateCacheSizeLabel {
    if (!self.cacheSizeLabel) return;
    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSUInteger bytes = [cache cacheSize];
    NSString *sizeStr;
    if      (bytes < 1024)        sizeStr = [NSString stringWithFormat:@"%lu bytes", (unsigned long)bytes];
    else if (bytes < 1024*1024)   sizeStr = [NSString stringWithFormat:@"%.1f KB",   bytes / 1024.0];
    else                          sizeStr = [NSString stringWithFormat:@"%.1f MB",   bytes / (1024.0*1024.0)];
    self.cacheSizeLabel.stringValue = [NSString stringWithFormat:@"Cache size: %@", sizeStr];
}

- (void)clearThumbnailCache:(id)sender {
    [[ThumbnailCache sharedCache] clearCache];
    [self updateCacheSizeLabel];
    [self.collectionView reloadData];
}

// ---------------------------------------------------------------------------
#pragma mark - Launch at Login (kept from prior implementation)

- (BOOL)isLaunchAtLoginEnabled {
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (void)launchAtLoginChanged:(NSButton *)sender {
    if (@available(macOS 13.0, *)) {
        NSError *err = nil;
        BOOL enable = (sender.state == NSControlStateValueOn);
        if (enable) [[SMAppService mainAppService] registerAndReturnError:&err];
        else        [[SMAppService mainAppService] unregisterAndReturnError:&err];
        if (err) {
            sender.state = [self isLaunchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = enable ? @"Could Not Enable" : @"Could Not Disable";
            alert.informativeText = err.localizedDescription;
            [alert runModal];
        }
    } else {
        sender.state = NSControlStateValueOff;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - No-op placeholder

- (void)noop:(id)sender {}

// ---------------------------------------------------------------------------
#pragma mark - Dealloc

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

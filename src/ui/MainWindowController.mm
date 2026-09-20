//
//  MainWindowController.mm
//  MacieWallpaper - Main Window Controller
//
//  Rebuilt on the design system 2026-08-19.
//
//  The sidebar, the hero panel, the settings sheet and the gallery's empty state
//  now live in their own units. What is left here is this window's own layout —
//  toolbar, gallery — and the wallpaper logic that drives it: which wallpaper is
//  playing, what the gallery shows, and how every entry point reaches the desktop.
//  Every font, colour and spacing value comes from DesignSystem.h.
//

#import "MainWindowController.h"
#import "Constants.h"
#import "DesignSystem.h"
#import "GalleryEmptyStateView.h"
#import "HeroPanelView.h"
#import "MacieAssetManagerWrapper.h"
#import "SettingsSheetController.h"
#import "SidebarView.h"
#import "ThumbnailCache.h"
#import "VideoCollectionItem.h"
#import "WallpaperDisplayManager.h"
#import "WallpaperMetadataCache.h"

// ---------------------------------------------------------------------------
#pragma mark - Constants

/// How many entries the Recent section keeps.
static const NSUInteger kMaxRecentWallpapers = 20;

/// Width of the gallery header's sort control.
static const CGFloat kSortControlWidth = 156.0;

/// Width of the toolbar's display-target control. Wider than the sort control because
/// it holds monitor names, which are longer than "Recently Added".
static const CGFloat kTargetControlWidth = 190.0;

/// Gallery sort orders, persisted so the choice survives a relaunch.
///
/// Duration is deliberately absent: WallpaperMetadataCache fills in only as cards
/// scroll into view, so a duration sort would order the library by which cards the
/// user happened to look at.
typedef NS_ENUM(NSInteger, MacieGallerySort) {
    MacieGallerySortTitleAscending  = 0,
    MacieGallerySortTitleDescending = 1,
    MacieGallerySortNewestFirst     = 2,
    MacieGallerySortLargestFirst    = 3,
};

static NSArray<NSString *> *MacieSortTitles(void) {
    return @[@"Name (A–Z)", @"Name (Z–A)", @"Recently Added", @"Largest First"];
}

// ---------------------------------------------------------------------------
#pragma mark - Gallery collection view

/// Keystrokes the gallery reports upward.
typedef NS_ENUM(NSInteger, MacieGalleryKey) {
    MacieGalleryKeyActivate,   // Return — apply the focused wallpaper
    MacieGalleryKeyPreview,    // Space  — show it in the hero panel only
    MacieGalleryKeyCancel,     // Escape — drop focus and any preview
    MacieGalleryKeyLeft,
    MacieGalleryKeyRight,
    MacieGalleryKeyUp,
    MacieGalleryKeyDown,
};

/// Neither keystrokes nor right-clicks are reachable through
/// NSCollectionViewDelegate, so the grid is a small subclass that reports both as
/// blocks. All the policy stays in the controller; this is a pure input adapter.
@interface MacieGalleryView : NSCollectionView
/// Return YES to consume the key.
@property (nonatomic, copy) BOOL (^onKey)(MacieGalleryKey key);
/// `itemIndex` is -1 when the click missed every card.
@property (nonatomic, copy) NSMenu * (^onContextMenuForItem)(NSInteger itemIndex);
@end

@implementation MacieGalleryView

- (void)keyDown:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers;
    unichar c = chars.length ? [chars characterAtIndex:0] : 0;

    MacieGalleryKey key = MacieGalleryKeyActivate;
    BOOL recognized = YES;
    switch (c) {
        case NSCarriageReturnCharacter:
        case NSEnterCharacter:        key = MacieGalleryKeyActivate; break;
        case ' ':                     key = MacieGalleryKeyPreview;  break;
        case 0x1B:                    key = MacieGalleryKeyCancel;   break;  // Escape
        case NSLeftArrowFunctionKey:  key = MacieGalleryKeyLeft;     break;
        case NSRightArrowFunctionKey: key = MacieGalleryKeyRight;    break;
        case NSUpArrowFunctionKey:    key = MacieGalleryKeyUp;       break;
        case NSDownArrowFunctionKey:  key = MacieGalleryKeyDown;     break;
        default: recognized = NO; break;
    }

    // Arrow keys are handled here rather than left to NSCollectionView's own
    // navigation, because moving the focus ring and applying a wallpaper have to
    // stay separate actions — see -collectionView:didSelectItemsAtIndexPaths:.
    if (recognized && self.onKey && self.onKey(key)) return;
    [super keyDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (!self.onContextMenuForItem) return [super menuForEvent:event];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSIndexPath *indexPath = [self indexPathForItemAtPoint:point];
    return self.onContextMenuForItem(indexPath ? indexPath.item : -1);
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Class extension

@interface MainWindowController () <
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSSearchFieldDelegate
>

// Core
@property (strong, nonatomic) WallpaperDisplayManager  *displayManager;
@property (strong, nonatomic) MacieAssetManagerWrapper *assetManager;
@property (strong, nonatomic) SettingsSheetController  *settingsController;

/// Which display everything in this window acts on. nil means all of them — the picker's
/// first entry, and the only possible answer while a single display is attached.
@property (copy, nonatomic, nullable) NSString *currentTargetKey;

// Data
/// Full unfiltered list — never mutated after -loadVideos.
@property (strong, nonatomic) NSArray<NSDictionary *> *videos;
/// What the collection view currently shows (section + search + sort applied).
@property (strong, nonatomic) NSArray<NSDictionary *> *filteredVideos;
/// IDs of favorited wallpapers, persisted to NSUserDefaults.
@property (strong, nonatomic) NSMutableSet<NSString *> *favoriteIds;
/// IDs of recently played wallpapers (most-recent first, capped).
@property (strong, nonatomic) NSMutableArray<NSString *> *recentIds;
/// ID of the wallpaper playing on the current target. Derived, not stored: the display
/// manager is the only record of what is on which display, and a second copy here would be
/// wrong the moment the target changes or a monitor is unplugged.
@property (strong, nonatomic, readonly, nullable) NSString *playingWallpaperId;
/// Active sidebar section (drives filteredVideos).
@property (assign, nonatomic) MacieSidebarSection activeSection;
/// Active collection name when activeSection >= MacieSidebarSectionCollection.
@property (strong, nonatomic) NSString *activeCollectionName;
/// Gallery sort order, persisted.
@property (assign, nonatomic) MacieGallerySort sortOrder;
/// id → @{@"size": bytes, @"date": unix seconds}. Filled by the same background
/// pass that computes the sidebar's on-disk figures, so the size and date sorts
/// cost no additional file I/O.
@property (strong, nonatomic) NSDictionary<NSString *, NSDictionary *> *fileStats;

// Chrome
@property (strong, nonatomic) SidebarView         *sidebar;
@property (strong, nonatomic) NSView              *contentArea;
@property (strong, nonatomic) NSSearchField       *searchField;
@property (strong, nonatomic) NSPopUpButton       *targetPopup;
@property (strong, nonatomic) NSButton            *muteToolbarButton;

// Hero
@property (strong, nonatomic) HeroPanelView         *heroPanel;

// Gallery
@property (strong, nonatomic) MacieGalleryView      *collectionView;
@property (strong, nonatomic) NSScrollView          *scrollView;
@property (strong, nonatomic) GalleryEmptyStateView *emptyState;
@property (strong, nonatomic) NSTextField           *galleryHeaderLabel;
@property (strong, nonatomic) NSTextField           *countLabel;
@property (strong, nonatomic) NSPopUpButton         *sortPopup;

@end

// ---------------------------------------------------------------------------
@implementation MainWindowController

#pragma mark - Init

- (instancetype)initWithAssetManager:(MacieAssetManagerWrapper *)assetManager
                      displayManager:(WallpaperDisplayManager *)manager {
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
<<<<<<< HEAD
        _assetManager   = assetManager;
        _displayManager = manager;
        _favoriteIds    = [self loadFavoriteIds];
        _recentIds      = [self loadRecentIds];
        _activeSection  = MacieSidebarSectionLibrary;
        _fileStats      = @{};
        _sortOrder      = [self loadSortOrder];
        // Before -setupWindow, which builds the picker from it. The manager already knows
        // every attached display and what it is playing, so the hero can resolve the
        // restored wallpaper as PLAYING while the scan is still running.
        _currentTargetKey = [self restoredTargetKey];
=======
        _assetManager  = assetManager;
        _videoRenderer = renderer;
        _favoriteIds   = [self loadFavoriteIds];
        _recentIds     = [self loadRecentIds];
        _activeSection = MacieSidebarSectionLibrary;
        _fileStats     = @{};
        _sortOrder     = [self loadSortOrder];
>>>>>>> origin/main

        [self setupWindow];
        [self loadVideos];
        [self setupFavoriteToggleObserver];
    }
    return self;
}

<<<<<<< HEAD
/// The display the user last targeted, if it is still attached. A monitor unplugged since
/// the last session falls back to All Displays rather than to a picker entry that is not
/// there — and the stored key is left alone, so plugging it back in restores the choice.
- (NSString *)restoredTargetKey {
    NSString *stored = [[NSUserDefaults standardUserDefaults]
        stringForKey:kDefaultsWallpaperTarget];
    if (!stored.length) return nil;
    return [self.displayManager nameForDisplayKey:stored] ? stored : nil;
}

- (NSString *)playingWallpaperId {
    return [self.displayManager wallpaperIdForDisplayKey:self.currentTargetKey];
}

=======
>>>>>>> origin/main
- (MacieGallerySort)loadSortOrder {
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultsGallerySortOrder];
    if (saved < MacieGallerySortTitleAscending || saved > MacieGallerySortLargestFirst) {
        return MacieGallerySortTitleAscending;
    }
    return (MacieGallerySort)saved;
}

#pragma mark - Window Setup

- (void)setupWindow {
    NSWindow *w = self.window;
    w.title = kAppName;                 // hidden in the titlebar; names the Window menu entry
    w.titlebarAppearsTransparent = YES;
    w.titleVisibility = NSWindowTitleHidden;
    w.movableByWindowBackground = YES;
    w.minSize = NSMakeSize(kMainWindowMinWidth, kMainWindowMinHeight);
    w.backgroundColor = MacieBackgroundColor();
    // The palette is dark-only. Without this, a Mac set to Light Mode resolves
    // AppKit's semantic colours light and the text vanishes into these surfaces.
    MacieApplyDarkAppearance(w);

    NSVisualEffectView *bgEffect = [[NSVisualEffectView alloc] initWithFrame:w.contentView.bounds];
    bgEffect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    bgEffect.material     = NSVisualEffectMaterialUnderWindowBackground;
    bgEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bgEffect.state        = NSVisualEffectStateActive;
    [w.contentView addSubview:bgEffect];

    [self buildSidebar];
    [self buildContentArea];

    // Arrow keys should walk the grid the moment the window opens, so the gallery
    // is the initial responder rather than the search field.
    w.initialFirstResponder = self.collectionView;
}

// ---------------------------------------------------------------------------
#pragma mark - Sidebar

- (void)buildSidebar {
    NSView *cv = self.window.contentView;

    self.sidebar = [[SidebarView alloc]
        initWithFrame:NSMakeRect(0, 0, kSidebarWidth, cv.bounds.size.height)];

    __weak typeof(self) weakSelf = self;
    self.sidebar.onSectionSelected = ^(MacieSidebarSection section) {
        [weakSelf sidebarSectionSelected:section];
    };

    [cv addSubview:self.sidebar];
}

- (void)sidebarSectionSelected:(MacieSidebarSection)section {
    // Three rows are commands rather than filters; they never become the selection.
    if (section == MacieSidebarSectionRandom)   { [self playRandomWallpaper:nil];       return; }
    if (section == MacieSidebarSectionSettings) { [self showSettingsSheet:nil];         return; }
    if (section == MacieSidebarSectionAbout)    { [NSApp orderFrontStandardAboutPanel:nil]; return; }

    self.activeSection = section;

    if (section >= MacieSidebarSectionCollection && section < MacieSidebarSectionSettings) {
        NSUInteger idx = (NSUInteger)(section - MacieSidebarSectionCollection);
        NSArray<NSString *> *names = MacieCollectionNames();
        self.activeCollectionName = (idx < names.count) ? names[idx] : nil;
        self.galleryHeaderLabel.stringValue = self.activeCollectionName ?: @"Collection";
    } else {
        self.activeCollectionName = nil;
        if (section == MacieSidebarSectionFavorites)   self.galleryHeaderLabel.stringValue = @"Favorites";
        else if (section == MacieSidebarSectionRecent) self.galleryHeaderLabel.stringValue = @"Recent";
        else                                          self.galleryHeaderLabel.stringValue = @"All Wallpapers";
    }

    [self layoutGalleryHeader];
    self.searchField.stringValue = @"";
    [self.sidebar setSelectedSection:section];
    [self applyCurrentFilter];
}

- (void)updateSidebarBadges {
    [self.sidebar setLibraryCount:self.videos.count
                  favoritesCount:self.favoriteIds.count
                     recentCount:self.recentIds.count];
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
    self.contentArea.layer.backgroundColor = MacieBackgroundColor().CGColor;
    [cv addSubview:self.contentArea];

    [self buildToolbar];
    [self buildHeroSection];
    [self buildGallery];
}

// ---------------------------------------------------------------------------
#pragma mark - Toolbar

- (void)buildToolbar {
    CGFloat cw = self.contentArea.bounds.size.width;
    CGFloat ch = self.contentArea.bounds.size.height;

    NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, ch - kToolbarHeight, cw, kToolbarHeight)];
    toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = MacieBackgroundColor().CGColor;

    NSView *separator = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cw, 1)];
    separator.autoresizingMask = NSViewWidthSizable;
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = MacieHairlineColor().CGColor;
    [toolbar addSubview:separator];

    // The search field starts at the same left edge as the gallery header, the
    // hero panel and the grid's first column.
    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(
        kMacieContentInset, (kToolbarHeight - kMacieFieldHeight) / 2.0, 320, kMacieFieldHeight)];
    self.searchField.placeholderString = @"Search titles, descriptions and tags";
    self.searchField.font     = MacieFontBody();
    self.searchField.delegate = self;
    self.searchField.target   = self;
    self.searchField.action   = @selector(searchFieldChanged:);
    self.searchField.sendsSearchStringImmediately = YES;
    self.searchField.toolTip = @"Search wallpapers (⌘F)";
    [toolbar addSubview:self.searchField];

    // Trailing icon buttons. NSViewMinXMargin pins them to the right edge; without
    // it they keep their launch-width x and drift inward as the window widens.
    NSArray<NSString *> *symbols  = @[@"gearshape", @"speaker.wave.2", @"shuffle"];
    NSArray<NSString *> *tooltips = @[@"Settings (⌘,)",
                                      @"Mute / unmute wallpaper audio (⇧⌘M)",
                                      @"Play a random wallpaper (⌘R)"];
    SEL actions[3] = { @selector(showSettingsSheet:),
                       @selector(toolbarToggleMute:),
                       @selector(toolbarShuffle:) };

    CGFloat buttonY = (kToolbarHeight - kMacieControlHeight) / 2.0;
    for (NSUInteger i = 0; i < symbols.count; i++) {
        NSButton *btn = MacieIconButton(symbols[i], tooltips[i], self, actions[i]);
        CGFloat x = cw - kMacieContentInset
                  - (CGFloat)(i + 1) * kMacieControlHeight
                  - (CGFloat)i * kMacieSpaceS;
        btn.frame = NSMakeRect(x, buttonY, kMacieControlHeight, kMacieControlHeight);
        btn.autoresizingMask = NSViewMinXMargin;
        if (i == 1) self.muteToolbarButton = btn;
        [toolbar addSubview:btn];
    }

    // Left of the icon buttons, so the row reads target-then-actions. Hidden with a single
    // display — see -refreshTargetPopup — but built either way, because a monitor plugged
    // in later must not need the toolbar rebuilding.
    CGFloat trailingWidth = (CGFloat)symbols.count * kMacieControlHeight
                          + (CGFloat)(symbols.count - 1) * kMacieSpaceS;
    self.targetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(
        cw - kMacieContentInset - trailingWidth - kMacieSpaceM - kTargetControlWidth,
        (kToolbarHeight - kMacieControlHeight) / 2.0,
        kTargetControlWidth, kMacieControlHeight) pullsDown:NO];
    self.targetPopup.font   = MacieFontBody();
    self.targetPopup.target = self;
    self.targetPopup.action = @selector(targetChanged:);
    self.targetPopup.autoresizingMask = NSViewMinXMargin;
    self.targetPopup.toolTip = @"Choose which display the gallery applies wallpapers to";
    [toolbar addSubview:self.targetPopup];
    [self refreshTargetPopup];

    [self.contentArea addSubview:toolbar];
}

// ---------------------------------------------------------------------------
#pragma mark - Display target

/// Rebuilds the picker from the attached displays. Called at build time and again from
/// -displaysChanged, so its contents can never name a monitor that is not there.
- (void)refreshTargetPopup {
    if (!self.targetPopup) return;

    NSArray<NSString *> *keys = self.displayManager.displayKeys;

    // One display means every choice does the same thing, and a control that cannot change
    // anything is just clutter. The target stays nil in that case, which is what makes
    // -applyWallpaper: keep working unchanged on a single-display Mac.
    self.targetPopup.hidden = (keys.count < 2);

    [self.targetPopup removeAllItems];

    // Items are added through the menu rather than -addItemWithTitle:, which silently
    // replaces an existing item of the same name — two identical monitors would collapse
    // into one entry if their names had not been disambiguated first.
    [self.targetPopup.menu addItem:[[NSMenuItem alloc] initWithTitle:@"All Displays"
                                                             action:NULL
                                                      keyEquivalent:@""]];
    for (NSString *key in keys) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:([self.displayManager nameForDisplayKey:key] ?: key)
                   action:NULL
            keyEquivalent:@""];
        item.representedObject = key;
        [self.targetPopup.menu addItem:item];
    }

    NSUInteger index = self.currentTargetKey ? [keys indexOfObject:self.currentTargetKey]
                                            : NSNotFound;
    [self.targetPopup selectItemAtIndex:(index == NSNotFound ? 0 : (NSInteger)index + 1)];
}

- (void)targetChanged:(id)sender {
    NSString *key = self.targetPopup.selectedItem.representedObject;
    if (key == self.currentTargetKey || [key isEqualToString:self.currentTargetKey]) return;

    NSString *previousPlayingId = self.playingWallpaperId;
    self.currentTargetKey = key;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (key.length) [defaults setObject:key forKey:kDefaultsWallpaperTarget];
    else            [defaults removeObjectForKey:kDefaultsWallpaperTarget];

    [self retargetedFromWallpaperId:previousPlayingId];
}

- (void)displaysChanged {
    NSString *previousPlayingId = self.playingWallpaperId;

    // The targeted display may be the one that was just unplugged, in which case the
    // remembered key is kept but the selection falls back to All Displays.
    if (self.currentTargetKey && ![self.displayManager nameForDisplayKey:self.currentTargetKey]) {
        self.currentTargetKey = nil;
    }

    [self refreshTargetPopup];
    [self retargetedFromWallpaperId:previousPlayingId];
}

/// PLAYING is a fact about one display, so pointing this window at a different one changes
/// which card is marked and what the hero shows. Two cards at most, rather than a reload
/// that would throw away the scroll position and the focus ring.
- (void)retargetedFromWallpaperId:(NSString *)previousPlayingId {
    NSDictionary *playing = [self videoForId:self.playingWallpaperId]
        ?: [self.displayManager wallpaperForDisplayKey:self.currentTargetKey];

    [self showInHero:playing];
    [self refreshItemForWallpaperId:previousPlayingId];
    [self refreshItemForWallpaperId:self.playingWallpaperId];
}

// ---------------------------------------------------------------------------
#pragma mark - Hero Section

- (void)buildHeroSection {
    CGFloat cw = self.contentArea.bounds.size.width;
    CGFloat ch = self.contentArea.bounds.size.height;
    CGFloat heroY = ch - kToolbarHeight - kHeroHeight;

    self.heroPanel = [[HeroPanelView alloc] initWithFrame:NSMakeRect(0, heroY, cw, kHeroHeight)];
    self.heroPanel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

    __weak typeof(self) weakSelf = self;
    self.heroPanel.onApplyRequested = ^(NSDictionary *video) {
        [weakSelf applyWallpaper:video];
    };
    self.heroPanel.onFavoriteToggled = ^(NSDictionary *video) {
        typeof(self) strongSelf = weakSelf;
        NSString *wallpaperId = video[@"id"];
        if (!strongSelf || !wallpaperId.length) return;
        [strongSelf setFavorite:![strongSelf.favoriteIds containsObject:wallpaperId]
                 forWallpaperId:wallpaperId];
    };

    [self.contentArea addSubview:self.heroPanel];
}

/// Points the hero at a wallpaper, working out for itself whether that is the
/// playing one or a preview. Every hero update goes through here so the panel's
/// PLAYING/PREVIEW state cannot drift from what is actually on the desktop.
- (void)showInHero:(NSDictionary *)video {
    [self updateHeroDisplayContext];

    if (!video) { [self.heroPanel showEmpty]; return; }

    NSString *wallpaperId = video[@"id"];
    [self.heroPanel showWallpaper:video
                        isPreview:![wallpaperId isEqualToString:self.playingWallpaperId]
                       isFavorite:[self.favoriteIds containsObject:wallpaperId]];
}

/// PLAYING says nothing about *where* while more than one desktop exists, so the hero is
/// told which display it is describing and whether the rest of them agree.
- (void)updateHeroDisplayContext {
    if (self.displayManager.displayKeys.count < 2) {
        [self.heroPanel setDisplayContextName:nil othersDiffer:NO];
        return;
    }

    BOOL differ = [self.displayManager assignmentsDiffer];

    // With All Displays selected the hero shows the primary's wallpaper, so it is named
    // rather than claimed for every display — unless they really are all the same, which is
    // the one case where "All Displays" is the truthful label.
    NSString *name = @"All Displays";
    if (self.currentTargetKey) {
        name = [self.displayManager nameForDisplayKey:self.currentTargetKey] ?: @"";
    } else if (differ) {
        name = [self.displayManager nameForDisplayKey:self.displayManager.primaryDisplayKey] ?: @"";
    }

    [self.heroPanel setDisplayContextName:name othersDiffer:differ];
}

/// Returns the hero to the wallpaper that is actually playing. Escape does this.
- (void)cancelHeroPreview {
    if (!self.heroPanel.isPreview) return;
    [self showInHero:[self videoForId:self.playingWallpaperId]];
}

// ---------------------------------------------------------------------------
#pragma mark - Gallery

- (void)buildGallery {
    CGFloat cw = self.contentArea.bounds.size.width;
    CGFloat ch = self.contentArea.bounds.size.height;
    CGFloat headerY  = ch - kToolbarHeight - kHeroHeight - kGalleryHeaderHeight;
    CGFloat galleryH = headerY;   // the grid fills everything below the header

    // --- Header --------------------------------------------------------------
    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(0, headerY, cw, kGalleryHeaderHeight)];
    header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    header.wantsLayer = YES;
    header.layer.backgroundColor = MacieSurfaceColor().CGColor;
    [self.contentArea addSubview:header];

    CGFloat titleH   = ceil(MacieFontBodyEmphasized().boundingRectForFont.size.height);
    CGFloat captionH = ceil(MacieFontCaption().boundingRectForFont.size.height);

    self.galleryHeaderLabel = MacieLabel(@"All Wallpapers", MacieFontBodyEmphasized(),
                                         MaciePrimaryTextColor());
    self.galleryHeaderLabel.frame = NSMakeRect(kMacieContentInset,
                                               (kGalleryHeaderHeight - titleH) / 2.0,
                                               200, titleH);
    [header addSubview:self.galleryHeaderLabel];

    self.countLabel = MacieLabel(@"", MacieFontCaption(), MacieTertiaryTextColor());
    self.countLabel.frame = NSMakeRect(kMacieContentInset,
                                       (kGalleryHeaderHeight - captionH) / 2.0,
                                       220, captionH);
    [header addSubview:self.countLabel];

    self.sortPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(
        cw - kMacieContentInset - kSortControlWidth,
        (kGalleryHeaderHeight - kMacieControlHeight) / 2.0,
        kSortControlWidth, kMacieControlHeight) pullsDown:NO];
    [self.sortPopup addItemsWithTitles:MacieSortTitles()];
    [self.sortPopup selectItemAtIndex:self.sortOrder];
    self.sortPopup.font   = MacieFontBody();
    self.sortPopup.target = self;
    self.sortPopup.action = @selector(sortOrderChanged:);
    self.sortPopup.autoresizingMask = NSViewMinXMargin;
    [header addSubview:self.sortPopup];

    [self layoutGalleryHeader];
    [self updateSortControlEnabled];

    // --- Grid ----------------------------------------------------------------
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    // The item size comes from the card itself, so the two cannot disagree.
    layout.itemSize = NSMakeSize(kMacieCardWidth, kMacieCardHeight);
    layout.minimumInteritemSpacing = kMacieSpaceL;
    layout.minimumLineSpacing      = kMacieSpaceL;
    layout.sectionInset = NSEdgeInsetsMake(kMacieSpaceL, kMacieContentInset,
                                           kMacieSpaceXXL, kMacieContentInset);
    layout.scrollDirection = NSCollectionViewScrollDirectionVertical;

    self.collectionView = [[MacieGalleryView alloc] initWithFrame:NSMakeRect(0, 0, cw, galleryH)];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate   = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColors = @[MacieBackgroundColor()];
    self.collectionView.selectable = YES;
    [self.collectionView registerClass:[VideoCollectionItem class] forItemWithIdentifier:@"VideoItem"];

    __weak typeof(self) weakSelf = self;
    self.collectionView.onKey = ^BOOL(MacieGalleryKey key) {
        return [weakSelf handleGalleryKey:key];
    };
    self.collectionView.onContextMenuForItem = ^NSMenu *(NSInteger itemIndex) {
        return [weakSelf contextMenuForItemIndex:itemIndex];
    };

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, cw, galleryH)];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.documentView = self.collectionView;
    self.scrollView.hasVerticalScroller   = YES;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.drawsBackground = NO;
    [self.contentArea addSubview:self.scrollView];

    // --- Empty state ---------------------------------------------------------
    // A sibling on top of the scroll view rather than a subview of the document,
    // so it stays put instead of scrolling.
    self.emptyState = [[GalleryEmptyStateView alloc] initWithFrame:NSMakeRect(0, 0, cw, galleryH)];
    self.emptyState.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.emptyState.hidden = YES;
    [self.contentArea addSubview:self.emptyState];
}

/// Places the count immediately after the header title's measured width. The count
/// used to sit at a hardcoded x=250, which long collection names ran straight into.
- (void)layoutGalleryHeader {
    NSString *title = self.galleryHeaderLabel.stringValue ?: @"";
    CGFloat titleW = ceil([title sizeWithAttributes:
                           @{NSFontAttributeName: self.galleryHeaderLabel.font}].width) + 2;

    NSRect titleFrame = self.galleryHeaderLabel.frame;
    self.galleryHeaderLabel.frame = NSMakeRect(kMacieContentInset, titleFrame.origin.y,
                                               titleW, titleFrame.size.height);

    NSRect countFrame = self.countLabel.frame;
    self.countLabel.frame = NSMakeRect(kMacieContentInset + titleW + kMacieSpaceM,
                                       countFrame.origin.y, 220, countFrame.size.height);
}

- (void)updateCountLabel {
    NSUInteger shown = self.filteredVideos.count;
    NSUInteger total = self.videos.count;

    if (shown == total) {
        self.countLabel.stringValue = (total == 1)
            ? @"1 wallpaper"
            : [NSString stringWithFormat:@"%lu wallpapers", (unsigned long)total];
    } else {
        self.countLabel.stringValue = [NSString stringWithFormat:@"%lu of %lu",
                                       (unsigned long)shown, (unsigned long)total];
    }
}

/// Recent is ordered by when each wallpaper was last applied. Sorting it any other
/// way would destroy the only thing the section means, so the control is disabled
/// there rather than silently ignored.
- (void)updateSortControlEnabled {
    BOOL isRecent = (self.activeSection == MacieSidebarSectionRecent);
    self.sortPopup.enabled = !isRecent;
    self.sortPopup.toolTip = isRecent
        ? @"Recent is always ordered by when you last applied a wallpaper"
        : @"Sort the gallery";
}

/// An empty grid used to render as a blank void, which is indistinguishable from a
/// bug. Every way of emptying it now says which one happened and what to do.
- (void)updateEmptyState {
    if (self.filteredVideos.count > 0) {
        self.emptyState.hidden = YES;
        return;
    }

    NSString *query = [self.searchField.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (query.length > 0) {
        [self.emptyState showSymbol:@"magnifyingglass"
                              title:[NSString stringWithFormat:@"No matches for “%@”", query]
                           subtitle:@"Search covers titles, descriptions and Workshop tags. "
                                     "Try a shorter term, or clear the field to see everything again."];
        return;
    }

    switch (self.activeSection) {
        case MacieSidebarSectionFavorites:
            [self.emptyState showSymbol:@"heart"
                                  title:@"No favorites yet"
                               subtitle:@"Click the heart on any wallpaper — here or in the panel above — to keep it in this list."];
            break;
        case MacieSidebarSectionRecent:
            [self.emptyState showSymbol:@"clock"
                                  title:@"Nothing played yet"
                               subtitle:@"The last 20 wallpapers you apply will collect here, most recent first."];
            break;
        default:
            if (self.activeCollectionName) {
                [self.emptyState showSymbol:@"folder"
                                      title:[NSString stringWithFormat:@"Nothing in %@", self.activeCollectionName]
                                   subtitle:@"Collections match on a wallpaper's title and its Workshop tags, so an item with neither will only appear in Library."];
            } else {
                [self.emptyState showSymbol:@"photo.on.rectangle.angled"
                                      title:@"No wallpapers found"
                                   subtitle:@"Point the app at the steamapps folder that contains workshop/content/431960 — use Change Steam Folder in Settings."];
            }
            break;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Data Loading

- (void)loadVideos {
    // The library arrives as dictionaries: the wrapper is the one place a WallpaperProject
    // becomes an Objective-C object, and the display manager needs the same shape. What is
    // added here is only what the gallery itself needs.
    NSArray<NSDictionary *> *wallpapers = [self.assetManager videoWallpaperDictionaries];

    NSMutableArray<NSDictionary *> *loaded = [NSMutableArray arrayWithCapacity:wallpapers.count];
    for (NSDictionary *wallpaper in wallpapers) {
        NSString *title       = wallpaper[@"title"];
        NSString *description = wallpaper[@"description"];
        NSString *tagText     = [wallpaper[@"tags"] componentsJoinedByString:@" "];

        // Search runs on every keystroke and collection matching on every section
        // change, so both haystacks are lowercased once here instead of per pass.
        //
        // categoryText excludes the description on purpose: matching prose would
        // file everything whose blurb mentions "city" under Cyberpunk.
        NSMutableDictionary *entry = [wallpaper mutableCopy];
        entry[@"searchText"]   = [[NSString stringWithFormat:@"%@ %@ %@",
                                   title, description, tagText] lowercaseString];
        entry[@"categoryText"] = [[NSString stringWithFormat:@"%@ %@",
                                   title, tagText] lowercaseString];
        [loaded addObject:[entry copy]];
    }

    self.videos    = [loaded copy];
    self.fileStats = @{};

    self.activeSection        = MacieSidebarSectionLibrary;
    self.activeCollectionName = nil;
    self.galleryHeaderLabel.stringValue = @"All Wallpapers";
    [self layoutGalleryHeader];
    self.searchField.stringValue = @"";
    [self.sidebar setSelectedSection:MacieSidebarSectionLibrary];

    [self applyCurrentFilter];
    [self updateSidebarBadges];
    [self updateStorageLabels];
<<<<<<< HEAD

    NSDictionary *playing = [self videoForId:self.playingWallpaperId];
    // Before the scan lands there is no library to look in, but what the manager restored
    // from the last session's snapshot carries everything the hero needs. Only when the
    // library is genuinely empty — otherwise an uninstalled wallpaper would come back from
    // the dead after a scan that no longer lists it.
    if (!playing && self.videos.count == 0) {
        playing = [self.displayManager wallpaperForDisplayKey:self.currentTargetKey];
    }
    [self showInHero:playing];

=======
    [self showInHero:[self videoForId:self.playingWallpaperId]];
>>>>>>> origin/main
    [self updateMuteButton];
}

- (NSDictionary *)videoForId:(NSString *)wallpaperId {
    if (!wallpaperId.length) return nil;
    for (NSDictionary *video in self.videos) {
        if ([video[@"id"] isEqualToString:wallpaperId]) return video;
    }
    return nil;
}

- (NSUInteger)indexOfWallpaperId:(NSString *)wallpaperId
                         inArray:(NSArray<NSDictionary *> *)array {
    if (!wallpaperId.length) return NSNotFound;
    for (NSUInteger i = 0; i < array.count; i++) {
        if ([array[i][@"id"] isEqualToString:wallpaperId]) return i;
    }
    return NSNotFound;
}

// ---------------------------------------------------------------------------
#pragma mark - Filtering, Search and Sort

/// The one place the visible list is computed: section, then search, then sort.
/// Everything that changes what should be on screen calls this.
- (void)applyCurrentFilter {
    NSArray<NSDictionary *> *source = [self sourceArrayForActiveSection];

    NSString *query = [[self.searchField.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        lowercaseString];

    if (query.length > 0) {
        NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
        for (NSDictionary *video in source) {
            if ([video[@"searchText"] containsString:query]) [matches addObject:video];
        }
        source = matches;
    }

    self.filteredVideos = [self sortedVideos:source];

    [self.collectionView reloadData];
    [self updateCountLabel];
    [self updateSortControlEnabled];
    [self updateEmptyState];
}

/// The subset of self.videos that the active sidebar section describes.
- (NSArray<NSDictionary *> *)sourceArrayForActiveSection {
    switch (self.activeSection) {
        case MacieSidebarSectionFavorites:
            return [self.videos filteredArrayUsingPredicate:
                [NSPredicate predicateWithFormat:@"id IN %@", self.favoriteIds]];

        case MacieSidebarSectionRecent: {
            NSMutableArray<NSDictionary *> *ordered = [NSMutableArray array];
            for (NSString *recentId in self.recentIds) {
                NSDictionary *video = [self videoForId:recentId];
                if (video) [ordered addObject:video];
            }
            return [ordered copy];
        }

        default: {
            if (!self.activeCollectionName) return self.videos;

            NSArray<NSString *> *keywords = MacieCollectionKeywords()[self.activeCollectionName];
            NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
            for (NSDictionary *video in self.videos) {
                NSString *haystack = video[@"categoryText"];
                for (NSString *keyword in keywords) {
                    if ([haystack containsString:keyword]) { [matches addObject:video]; break; }
                }
            }
            return [matches copy];
        }
    }
}

- (NSArray<NSDictionary *> *)sortedVideos:(NSArray<NSDictionary *> *)input {
    if (self.activeSection == MacieSidebarSectionRecent) return input;

    NSDictionary<NSString *, NSDictionary *> *stats = self.fileStats;

    switch (self.sortOrder) {
        case MacieGallerySortTitleDescending:
            return [input sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [b[@"title"] localizedStandardCompare:a[@"title"]];
            }];

        case MacieGallerySortNewestFirst:
            // The background pass has not landed yet — leave the order alone rather
            // than sorting everything to a tie.
            if (stats.count == 0) return input;
            return [input sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                double da = [stats[a[@"id"]][@"date"] doubleValue];
                double db = [stats[b[@"id"]][@"date"] doubleValue];
                if (da == db) return [a[@"title"] localizedStandardCompare:b[@"title"]];
                return (da > db) ? NSOrderedAscending : NSOrderedDescending;
            }];

        case MacieGallerySortLargestFirst:
            if (stats.count == 0) return input;
            return [input sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                long long sa = [stats[a[@"id"]][@"size"] longLongValue];
                long long sb = [stats[b[@"id"]][@"size"] longLongValue];
                if (sa == sb) return [a[@"title"] localizedStandardCompare:b[@"title"]];
                return (sa > sb) ? NSOrderedAscending : NSOrderedDescending;
            }];

        case MacieGallerySortTitleAscending:
        default:
            return [input sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [a[@"title"] localizedStandardCompare:b[@"title"]];
            }];
    }
}

- (void)sortOrderChanged:(NSPopUpButton *)sender {
    self.sortOrder = (MacieGallerySort)sender.indexOfSelectedItem;
    [[NSUserDefaults standardUserDefaults] setInteger:self.sortOrder
                                              forKey:kDefaultsGallerySortOrder];
    [self applyCurrentFilter];
}

- (void)searchFieldChanged:(id)sender {
    [self applyCurrentFilter];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.searchField) [self applyCurrentFilter];
}

/// Escape clears the search and hands focus back to the grid; Return and Down move
/// into the results. Without these the search field is a place the keyboard gets
/// stuck.
- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)command {
    if (control != self.searchField) return NO;

    if (command == @selector(cancelOperation:)) {
        self.searchField.stringValue = @"";
        [self applyCurrentFilter];
        [self.window makeFirstResponder:self.collectionView];
        return YES;
    }
    if (command == @selector(insertNewline:) || command == @selector(moveDown:)) {
        [self.window makeFirstResponder:self.collectionView];
        [self focusGalleryItemAtIndex:0 scrollPosition:NSCollectionViewScrollPositionTop];
        return YES;
    }
    return NO;
}

/// ⌘F, routed from the Edit menu through the responder chain.
- (void)focusSearchField:(id)sender {
    [self.window makeFirstResponder:self.searchField];
}

// ---------------------------------------------------------------------------
#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.filteredVideos.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    VideoCollectionItem *item = [cv makeItemWithIdentifier:@"VideoItem" forIndexPath:indexPath];
    NSDictionary *video = self.filteredVideos[(NSUInteger)indexPath.item];
    BOOL favorite = [self.favoriteIds containsObject:video[@"id"]];
    BOOL playing  = [video[@"id"] isEqualToString:self.playingWallpaperId];
    [item configureWithVideoData:video isFavorite:favorite isPlaying:playing];
    return item;
}

// ---------------------------------------------------------------------------
#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)cv
didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath || indexPath.item >= (NSInteger)self.filteredVideos.count) return;

    // Selection and application used to be the same event, which made arrow-key
    // navigation impossible: walking the grid would reload the desktop video on
    // every keypress. A left click still applies immediately — anything else
    // (arrow keys, right click, programmatic focus) only moves the focus ring.
    NSEventType type = NSApp.currentEvent.type;
    if (type != NSEventTypeLeftMouseUp && type != NSEventTypeLeftMouseDown) return;

    [self applyWallpaper:self.filteredVideos[(NSUInteger)indexPath.item]];
}

// ---------------------------------------------------------------------------
#pragma mark - Keyboard Navigation

- (BOOL)handleGalleryKey:(MacieGalleryKey)key {
    switch (key) {
        case MacieGalleryKeyActivate: {
            NSDictionary *video = [self focusedVideo];
            if (!video) return NO;
            [self applyWallpaper:video];
            return YES;
        }
        case MacieGalleryKeyPreview: {
            NSDictionary *video = [self focusedVideo];
            if (!video) return NO;
            [self showInHero:video];
            return YES;
        }
        case MacieGalleryKeyCancel:
            [self clearGalleryFocus];
            [self cancelHeroPreview];
            return YES;
        case MacieGalleryKeyLeft:  return [self moveFocusBy:-1];
        case MacieGalleryKeyRight: return [self moveFocusBy:1];
        case MacieGalleryKeyUp:    return [self moveFocusBy:-(NSInteger)[self galleryColumnCount]];
        case MacieGalleryKeyDown:  return [self moveFocusBy:(NSInteger)[self galleryColumnCount]];
    }
    return NO;
}

/// How many cards the flow layout currently fits per row. Derived from the same
/// constants the layout was built with, so vertical arrow keys move exactly one row.
- (NSUInteger)galleryColumnCount {
    CGFloat available = self.scrollView.contentView.bounds.size.width - 2 * kMacieContentInset;
    NSInteger columns = (NSInteger)floor((available + kMacieSpaceL) / (kMacieCardWidth + kMacieSpaceL));
    return (NSUInteger)MAX(columns, (NSInteger)1);
}

- (NSDictionary *)focusedVideo {
    NSIndexPath *indexPath = self.collectionView.selectionIndexPaths.anyObject;
    if (!indexPath) return nil;
    if (indexPath.item < 0 || indexPath.item >= (NSInteger)self.filteredVideos.count) return nil;
    return self.filteredVideos[(NSUInteger)indexPath.item];
}

- (BOOL)moveFocusBy:(NSInteger)delta {
    NSInteger count = (NSInteger)self.filteredVideos.count;
    if (count == 0) return YES;   // consume the key rather than let AppKit beep

    NSIndexPath *current = self.collectionView.selectionIndexPaths.anyObject;
    NSInteger target;
    if (!current) {
        target = (delta > 0) ? 0 : count - 1;
    } else {
        target = current.item + delta;
        if (target < 0 || target >= count) return YES;   // stop at the edges
    }

    [self focusGalleryItemAtIndex:target
                   scrollPosition:NSCollectionViewScrollPositionNearestVerticalEdge];
    return YES;
}

- (void)focusGalleryItemAtIndex:(NSInteger)index
                 scrollPosition:(NSCollectionViewScrollPosition)position {
    [self clearGalleryFocus];
    if (index < 0 || index >= (NSInteger)self.filteredVideos.count) return;

    NSSet *selection = [NSSet setWithObject:[NSIndexPath indexPathForItem:index inSection:0]];
    // -selectItemsAtIndexPaths:scrollPosition: updates the items' own selected
    // state and scrolls in one step, and deliberately does not notify the delegate.
    [self.collectionView selectItemsAtIndexPaths:selection scrollPosition:position];
}

- (void)clearGalleryFocus {
    NSSet<NSIndexPath *> *current = self.collectionView.selectionIndexPaths;
    if (current.count) [self.collectionView deselectItemsAtIndexPaths:current];
}

// ---------------------------------------------------------------------------
#pragma mark - Context Menu

- (NSMenu *)contextMenuForItemIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.filteredVideos.count) return nil;
    NSDictionary *video = self.filteredVideos[(NSUInteger)index];

    // Move the focus ring to the card under the cursor, so the menu can never
    // appear to act on a wallpaper other than the one lit up.
    [self focusGalleryItemAtIndex:index scrollPosition:NSCollectionViewScrollPositionNone];

    BOOL favorite = [self.favoriteIds containsObject:video[@"id"]];
    BOOL playing  = [video[@"id"] isEqualToString:self.playingWallpaperId];

    NSMenu *menu = [[NSMenu alloc] init];
    // Enabled state is set explicitly below, so AppKit must not recompute it.
    menu.autoenablesItems = NO;

    NSMenuItem *apply = [menu addItemWithTitle:@"Set as Wallpaper"
                                        action:@selector(contextApply:)
                                 keyEquivalent:@""];
    apply.target = self;
    apply.representedObject = video;
    apply.enabled = !playing;

    NSMenuItem *preview = [menu addItemWithTitle:@"Show in Preview"
                                          action:@selector(contextPreview:)
                                   keyEquivalent:@""];
    preview.target = self;
    preview.representedObject = video;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fav = [menu addItemWithTitle:(favorite ? @"Remove from Favorites"
                                                       : @"Add to Favorites")
                                      action:@selector(contextToggleFavorite:)
                               keyEquivalent:@""];
    fav.target = self;
    fav.representedObject = video;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *reveal = [menu addItemWithTitle:@"Reveal in Finder"
                                         action:@selector(contextRevealInFinder:)
                                  keyEquivalent:@""];
    reveal.target = self;
    reveal.representedObject = video;

    NSMenuItem *copyTitle = [menu addItemWithTitle:@"Copy Title"
                                            action:@selector(contextCopyTitle:)
                                     keyEquivalent:@""];
    copyTitle.target = self;
    copyTitle.representedObject = video;

    return menu;
}

- (void)contextApply:(NSMenuItem *)sender {
    [self applyWallpaper:sender.representedObject];
}

- (void)contextPreview:(NSMenuItem *)sender {
    [self showInHero:sender.representedObject];
}

- (void)contextToggleFavorite:(NSMenuItem *)sender {
    NSDictionary *video = sender.representedObject;
    NSString *wallpaperId = video[@"id"];
    [self setFavorite:![self.favoriteIds containsObject:wallpaperId] forWallpaperId:wallpaperId];
}

- (void)contextRevealInFinder:(NSMenuItem *)sender {
    NSString *path = ((NSDictionary *)sender.representedObject)[@"path"];
    if (!path.length) return;
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (void)contextCopyTitle:(NSMenuItem *)sender {
    NSString *title = ((NSDictionary *)sender.representedObject)[@"title"] ?: @"";
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[title]];
}

// ---------------------------------------------------------------------------
#pragma mark - Targeted Item Updates

/// Redraws one card in place. Applying a wallpaper used to call -reloadData, which
/// rebuilt the entire grid — and reset its scroll position — to change two borders.
- (void)refreshItemForWallpaperId:(NSString *)wallpaperId {
    if (!wallpaperId.length) return;

    NSUInteger index = [self indexOfWallpaperId:wallpaperId inArray:self.filteredVideos];
    if (index == NSNotFound) return;

    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:(NSInteger)index inSection:0];
    VideoCollectionItem *item = (VideoCollectionItem *)[self.collectionView itemAtIndexPath:indexPath];
    // nil means the card is off-screen; it will be configured correctly from the
    // data source when it scrolls back in.
    if (!item) return;

    item.isFavorite         = [self.favoriteIds containsObject:wallpaperId];
    item.isPlayingWallpaper = [wallpaperId isEqualToString:self.playingWallpaperId];
}

// ---------------------------------------------------------------------------
#pragma mark - Storage Figures

/// Reports what this app is responsible for on disk: the wallpaper videos it plays
/// and the thumbnails it generated.
///
/// The background walk also records each file's size and creation date, which is
/// what the size and date sorts run on — so those sorts cost no extra file I/O.
- (void)updateStorageLabels {
    NSArray<NSDictionary *> *snapshot = self.videos;

    if (snapshot.count == 0) {
        [self.sidebar setLibraryText:@"No wallpapers" cacheText:[self cacheUsageText]];
        return;
    }

    [self.sidebar setLibraryText:[NSString stringWithFormat:@"%lu wallpapers",
                                  (unsigned long)snapshot.count]
                       cacheText:[self cacheUsageText]];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        long long total = 0;
        NSMutableDictionary<NSString *, NSDictionary *> *stats =
            [NSMutableDictionary dictionaryWithCapacity:snapshot.count];
        NSFileManager *fm = [NSFileManager defaultManager];

        for (NSDictionary *video in snapshot) {
            NSDictionary *attributes = [fm attributesOfItemAtPath:video[@"path"] error:nil];
            if (!attributes) continue;

            long long size = (long long)[attributes fileSize];
            total += size;

            NSDate *added = attributes[NSFileCreationDate] ?: attributes[NSFileModificationDate];
            stats[video[@"id"]] = @{ @"size": @(size),
                                     @"date": @(added.timeIntervalSince1970) };
        }

        NSString *sizeText = [NSByteCountFormatter stringFromByteCount:total
                                                           countStyle:NSByteCountFormatterCountStyleFile];

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            // A reload may have replaced the library while this was running.
            if (!strongSelf || strongSelf.videos != snapshot) return;

            strongSelf.fileStats = [stats copy];
            [strongSelf.sidebar setLibraryText:[NSString stringWithFormat:@"%lu videos · %@",
                                                (unsigned long)snapshot.count, sizeText]
                                     cacheText:[strongSelf cacheUsageText]];

            // The size and date sorts had nothing to order by until this moment.
            if (strongSelf.sortOrder == MacieGallerySortNewestFirst ||
                strongSelf.sortOrder == MacieGallerySortLargestFirst) {
                [strongSelf applyCurrentFilter];
            }
        });
    });
}

- (NSString *)cacheUsageText {
    NSUInteger bytes = [[ThumbnailCache sharedCache] cacheSize];
    NSString *sizeText = [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                                       countStyle:NSByteCountFormatterCountStyleFile];
    return [NSString stringWithFormat:@"%@ thumbnails", sizeText];
}

// ---------------------------------------------------------------------------
#pragma mark - Favorites

- (NSMutableSet<NSString *> *)loadFavoriteIds {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kDefaultsFavoriteIds];
    return saved ? [NSMutableSet setWithArray:saved] : [NSMutableSet set];
}

- (void)saveFavoriteIds {
    [[NSUserDefaults standardUserDefaults] setObject:self.favoriteIds.allObjects
                                             forKey:kDefaultsFavoriteIds];
}

- (NSMutableArray<NSString *> *)loadRecentIds {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kDefaultsRecentIds];
    return saved ? [NSMutableArray arrayWithArray:saved] : [NSMutableArray array];
}

- (void)saveRecentIds {
    [[NSUserDefaults standardUserDefaults] setObject:self.recentIds forKey:kDefaultsRecentIds];
}

- (void)setupFavoriteToggleObserver {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(wallpaperFavoriteToggled:)
                                                 name:kNotificationWallpaperFavoriteToggled
                                               object:nil];
}

/// Posted by a card's own heart button.
- (void)wallpaperFavoriteToggled:(NSNotification *)note {
    NSString *wallpaperId = note.userInfo[@"id"];
    if (!wallpaperId.length) return;
    [self setFavorite:[note.userInfo[@"favorite"] boolValue] forWallpaperId:wallpaperId];
}

/// The single path for a favorite change, so persistence, the badge, the card and
/// the hero panel cannot disagree about what is favorited.
- (void)setFavorite:(BOOL)favorite forWallpaperId:(NSString *)wallpaperId {
    if (!wallpaperId.length) return;

    if (favorite) [self.favoriteIds addObject:wallpaperId];
    else          [self.favoriteIds removeObject:wallpaperId];

    [self saveFavoriteIds];
    [self updateSidebarBadges];

    if ([wallpaperId isEqualToString:self.heroPanel.wallpaper[@"id"]]) {
        [self.heroPanel setFavorite:favorite];
    }

    // The Favorites section is defined by the set that just changed, so there the
    // grid has to be rebuilt rather than nudged.
    if (self.activeSection == MacieSidebarSectionFavorites) [self applyCurrentFilter];
    else                                                    [self refreshItemForWallpaperId:wallpaperId];
}

// ---------------------------------------------------------------------------
#pragma mark - Playback

/// The single path by which a wallpaper reaches the desktop. Every entry point —
/// gallery click, Return, the context menu, Random, Next/Prev, the hero's Apply —
/// routes through here so persistence, recents, the hero panel and the mute button
/// can never diverge.
///
/// Where it lands is whatever the toolbar's target says: one display, or all of them.
- (BOOL)applyWallpaper:(NSDictionary *)video {
    NSString *videoPath = video[@"path"];
    NSString *videoId   = video[@"id"];
    if (!videoPath.length || !videoId.length) return NO;

    // Read before the apply, because playingWallpaperId is a live query on the manager
    // rather than a stored value — afterwards it is already the new wallpaper.
    NSString *previousId = self.playingWallpaperId;

    // The manager persists each display's assignment itself, so nothing about which
    // wallpaper is where is written from here.
    if (![self.displayManager applyWallpaper:video toDisplayKey:self.currentTargetKey]) {
        NSLog(@"MainWindowController: failed to apply wallpaper %@", videoId);
        [self presentApplyFailureForTitle:video[@"title"]];
        return NO;
    }

<<<<<<< HEAD
=======
    NSString *previousId = self.playingWallpaperId;
    self.playingWallpaperId = videoId;
    [[NSUserDefaults standardUserDefaults] setObject:videoId forKey:kDefaultsLastWallpaperId];

>>>>>>> origin/main
    // Recents: most-recent first, capped.
    [self.recentIds removeObject:videoId];
    [self.recentIds insertObject:videoId atIndex:0];
    while (self.recentIds.count > kMaxRecentWallpapers) [self.recentIds removeLastObject];
    [self saveRecentIds];

    // Every renderer carries mute state across loads, so only the button needs bringing
    // back in sync. The target is already showing this wallpaper, so the hero resolves it
    // as PLAYING rather than PREVIEW.
    [self showInHero:video];
    [self updateMuteButton];
    [self updateSidebarBadges];

    // Two cards changed, so two cards are redrawn.
    [self refreshItemForWallpaperId:previousId];
    [self refreshItemForWallpaperId:videoId];

    // Recent is ordered by exactly what just happened.
    if (self.activeSection == MacieSidebarSectionRecent) [self applyCurrentFilter];

    return YES;
}

/// A failed apply used to print to the log and read as a dead click.
- (void)presentApplyFailureForTitle:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Could Not Play This Wallpaper";
    alert.informativeText = [NSString stringWithFormat:
        @"“%@” could not be loaded. Its video file may have been moved, or it may be "
         "in a format macOS cannot play.", title.length ? title : @"This wallpaper"];
    alert.alertStyle = NSAlertStyleWarning;

    if (self.window.isVisible) [alert beginSheetModalForWindow:self.window completionHandler:nil];
    else                       [alert runModal];
}

/// Next and Previous follow what the user is looking at. If the playing wallpaper
/// is not in the current filter there is no "next" relative to it, so the whole
/// library is used instead.
- (NSArray<NSDictionary *> *)playbackOrder {
    NSUInteger index = [self indexOfWallpaperId:self.playingWallpaperId inArray:self.filteredVideos];
    if (self.filteredVideos.count > 0 && index != NSNotFound) return self.filteredVideos;
    return self.videos;
}

- (void)nextWallpaper:(id)sender {
    NSArray<NSDictionary *> *order = [self playbackOrder];
    if (order.count == 0) return;
    NSUInteger current = [self indexOfWallpaperId:self.playingWallpaperId inArray:order];
    NSUInteger next = (current == NSNotFound || current + 1 >= order.count) ? 0 : current + 1;
    [self applyWallpaper:order[next]];
}

- (void)prevWallpaper:(id)sender {
    NSArray<NSDictionary *> *order = [self playbackOrder];
    if (order.count == 0) return;
    NSUInteger current = [self indexOfWallpaperId:self.playingWallpaperId inArray:order];
    NSUInteger previous = (current == NSNotFound || current == 0) ? order.count - 1 : current - 1;
    [self applyWallpaper:order[previous]];
}

- (void)playRandomWallpaper:(id)sender {
    // Random inside Favorites should pick a favorite: the visible set is the set
    // the user means. Falls back to the library when the view is too small to
    // choose from.
    NSArray<NSDictionary *> *pool = (self.filteredVideos.count > 1) ? self.filteredVideos : self.videos;
    if (pool.count == 0) return;
    if (pool.count == 1) { [self applyWallpaper:pool[0]]; return; }

    // Never pick the wallpaper that is already playing — a Random that changes
    // nothing looks like a broken button.
    NSUInteger current = [self indexOfWallpaperId:self.playingWallpaperId inArray:pool];
    NSUInteger index;
    do {
        index = arc4random_uniform((uint32_t)pool.count);
    } while (index == current);

    [self applyWallpaper:pool[index]];
}

- (void)toolbarShuffle:(id)sender {
    [self playRandomWallpaper:sender];
}

- (void)toolbarToggleMute:(id)sender {
    // One setting for the machine, not one per display: only the primary display's
    // wallpaper has audio. The manager persists the choice.
    [self.displayManager setMuted:!self.displayManager.muted];
    [self updateMuteButton];
}

- (void)updateMuteButton {
    if (!self.muteToolbarButton) return;

    BOOL muted = self.displayManager.muted;
    if (@available(macOS 11.0, *)) {
        NSString *symbol = muted ? @"speaker.slash.fill" : @"speaker.wave.2";
        [self.muteToolbarButton setImage:[NSImage imageWithSystemSymbolName:symbol
                                                  accessibilityDescription:nil]];
    }
    self.muteToolbarButton.contentTintColor = muted ? MacieAccentColor() : MacieSecondaryTextColor();
    self.muteToolbarButton.toolTip = muted ? @"Unmute wallpaper audio (⇧⌘M)"
                                           : @"Mute wallpaper audio (⇧⌘M)";
}

// ---------------------------------------------------------------------------
#pragma mark - Settings

- (void)showSettingsSheet:(id)sender {
    if (!self.settingsController) {
        self.settingsController = [[SettingsSheetController alloc] init];

        __weak typeof(self) weakSelf = self;
        self.settingsController.onPathChangeRequested = ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf.onWallpapersReloadRequested) strongSelf.onWallpapersReloadRequested();
        };
        self.settingsController.onCacheCleared = ^{
            [weakSelf thumbnailCacheCleared];
        };
    }
    [self.settingsController presentInWindow:self.window];
}

/// Every thumbnail on screen just became invalid, so this is the one case where a
/// full reload is the correct response. Re-showing the hero's wallpaper makes it
/// re-fetch its own thumbnail too.
- (void)thumbnailCacheCleared {
    [self updateStorageLabels];
    [self.collectionView reloadData];
    [self showInHero:self.heroPanel.wallpaper];
}

// ---------------------------------------------------------------------------
#pragma mark - Dealloc

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

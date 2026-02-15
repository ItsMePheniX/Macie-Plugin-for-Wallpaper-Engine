//
//  MainWindowController.mm
//  MacieWallpaper - Main Window Controller
//
//  Created on 2026-02-14.
//

#import "MainWindowController.h"
#import "VideoCollectionItem.h"
#import "AVVideoRenderer.h"
#import "AssetManager.hpp"
#import "Constants.h"
#import "ThumbnailCache.h"
#import <AVFoundation/AVFoundation.h>
#import <vector>

@interface MainWindowController () <NSCollectionViewDataSource>
@property (strong, nonatomic) NSCollectionView *collectionView;
@property (strong, nonatomic) NSScrollView *scrollView;
@property (strong, nonatomic) NSButton *muteButton;
@property (strong, nonatomic) NSTextField *countLabel;
@property (strong, nonatomic) AVVideoRenderer *videoRenderer;
@property (nonatomic) void *assetManager;
@property (strong, nonatomic) NSArray<NSDictionary *> *videos;
@property (strong, nonatomic) NSView *sidebar;
@property (strong, nonatomic) NSTextField *appTitleLabel;
@property (strong, nonatomic) NSTextField *versionLabel;
@property (strong, nonatomic) NSButton *allWallpapersButton;
@property (strong, nonatomic) NSButton *preferencesButton;
@property (strong, nonatomic) NSTextField *statsLabel;
@property (strong, nonatomic) NSView *mainContentArea;
@property (strong, nonatomic) NSView *galleryView;
@property (strong, nonatomic) NSView *preferencesView;
@property (strong, nonatomic) NSTextField *contentHeaderLabel;
@property (strong, nonatomic) NSTextField *cacheSizeLabel;
@end

@implementation MainWindowController

- (Macie::AssetManager *)assetManagerCpp {
    return static_cast<Macie::AssetManager *>(self.assetManager);
}

- (instancetype)initWithAssetManager:(void *)assetManager videoRenderer:(AVVideoRenderer *)renderer {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, kMainWindowWidth, kMainWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    
    self = [super initWithWindow:window];
    if (self) {
        self.assetManager = assetManager;
        self.videoRenderer = renderer;
        [self setupWindow];
        [self loadVideos];
    }
    return self;
}

- (void)setupWindow {
    self.window.title = kAppName;
    self.window.minSize = NSMakeSize(kMainWindowMinWidth, kMainWindowMinHeight);
    
    NSView *contentView = self.window.contentView;
    
    // Sidebar with dark theme
    self.sidebar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, contentView.bounds.size.height)];
    self.sidebar.autoresizingMask = NSViewHeightSizable;
    self.sidebar.wantsLayer = YES;
    self.sidebar.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.14 alpha:1.0] CGColor];
    [contentView addSubview:self.sidebar];
    
    // App Title
    self.appTitleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(15, contentView.bounds.size.height - 55, 190, 30)];
    self.appTitleLabel.stringValue = kAppName;
    self.appTitleLabel.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    self.appTitleLabel.textColor = [NSColor whiteColor];
    self.appTitleLabel.alignment = NSTextAlignmentLeft;
    self.appTitleLabel.editable = NO;
    self.appTitleLabel.bordered = NO;
    self.appTitleLabel.backgroundColor = [NSColor clearColor];
    self.appTitleLabel.autoresizingMask = NSViewMinYMargin;
    [self.sidebar addSubview:self.appTitleLabel];
    
    // Version Label
    self.versionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(15, contentView.bounds.size.height - 75, 190, 16)];
    self.versionLabel.stringValue = [NSString stringWithFormat:@"v%@", kAppVersion];
    self.versionLabel.font = [NSFont systemFontOfSize:11];
    self.versionLabel.textColor = [NSColor colorWithWhite:0.5 alpha:1.0];
    self.versionLabel.alignment = NSTextAlignmentLeft;
    self.versionLabel.editable = NO;
    self.versionLabel.bordered = NO;
    self.versionLabel.backgroundColor = [NSColor clearColor];
    self.versionLabel.autoresizingMask = NSViewMinYMargin;
    [self.sidebar addSubview:self.versionLabel];
    
    // Navigation Section
    NSView *navDivider = [[NSView alloc] initWithFrame:NSMakeRect(15, contentView.bounds.size.height - 95, 190, 1)];
    navDivider.wantsLayer = YES;
    navDivider.layer.backgroundColor = [[NSColor colorWithWhite:0.25 alpha:1.0] CGColor];
    navDivider.autoresizingMask = NSViewMinYMargin;
    [self.sidebar addSubview:navDivider];
    
    NSTextField *navLabel = [self createSectionLabel:@"NAVIGATION" yPos:contentView.bounds.size.height - 115];
    [self.sidebar addSubview:navLabel];
    
    // All Wallpapers Button
    self.allWallpapersButton = [self createMenuButton:@"All Wallpapers" 
                                                 yPos:contentView.bounds.size.height - 145
                                               action:@selector(showAllWallpapers:)
                                             selected:YES];
    [self.sidebar addSubview:self.allWallpapersButton];
    
    // Preferences Button
    self.preferencesButton = [self createMenuButton:@"Preferences" 
                                               yPos:contentView.bounds.size.height - 182
                                             action:@selector(openPreferences:)
                                           selected:NO];
    [self.sidebar addSubview:self.preferencesButton];
    
    // Now Playing Section
    NSView *statsDivider = [[NSView alloc] initWithFrame:NSMakeRect(15, 195, 190, 1)];
    statsDivider.wantsLayer = YES;
    statsDivider.layer.backgroundColor = [[NSColor colorWithWhite:0.25 alpha:1.0] CGColor];
    [self.sidebar addSubview:statsDivider];
    
    NSTextField *statsHeaderLabel = [self createSectionLabel:@"NOW PLAYING" yPos:170];
    [self.sidebar addSubview:statsHeaderLabel];
    
    self.statsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(15, 95, 190, 70)];
    self.statsLabel.stringValue = @"Loading...";
    self.statsLabel.font = [NSFont systemFontOfSize:12];
    self.statsLabel.textColor = [NSColor colorWithWhite:0.8 alpha:1.0];
    self.statsLabel.alignment = NSTextAlignmentLeft;
    self.statsLabel.editable = NO;
    self.statsLabel.bordered = NO;
    self.statsLabel.backgroundColor = [NSColor clearColor];
    self.statsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.sidebar addSubview:self.statsLabel];
    
    // Audio Control Section
    NSView *audioDivider = [[NSView alloc] initWithFrame:NSMakeRect(15, 80, 190, 1)];
    audioDivider.wantsLayer = YES;
    audioDivider.layer.backgroundColor = [[NSColor colorWithWhite:0.25 alpha:1.0] CGColor];
    [self.sidebar addSubview:audioDivider];
    
    NSTextField *audioLabel = [self createSectionLabel:@"AUDIO" yPos:55];
    [self.sidebar addSubview:audioLabel];
    
    self.muteButton = [[NSButton alloc] initWithFrame:NSMakeRect(15, 12, 190, 32)];
    [self.muteButton setButtonType:NSButtonTypeMomentaryPushIn];
    [self.muteButton setBezelStyle:NSBezelStyleRounded];
    self.muteButton.wantsLayer = YES;
    self.muteButton.layer.cornerRadius = 6;
    [self updateMuteButton];
    self.muteButton.target = self;
    self.muteButton.action = @selector(toggleMute:);
    [self.sidebar addSubview:self.muteButton];
    
    // Main content area header
    NSView *headerBar = [[NSView alloc] initWithFrame:NSMakeRect(kSidebarWidth, contentView.bounds.size.height - kHeaderHeight, contentView.bounds.size.width - kSidebarWidth, kHeaderHeight)];
    headerBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    headerBar.wantsLayer = YES;
    headerBar.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.12 alpha:1.0] CGColor];
    [contentView addSubview:headerBar];
    
    self.contentHeaderLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(25, 12, 400, 26)];
    self.contentHeaderLabel.stringValue = @"All Wallpapers";
    self.contentHeaderLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    self.contentHeaderLabel.textColor = [NSColor whiteColor];
    self.contentHeaderLabel.editable = NO;
    self.contentHeaderLabel.bordered = NO;
    self.contentHeaderLabel.backgroundColor = [NSColor clearColor];
    [headerBar addSubview:self.contentHeaderLabel];
    
    self.countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(headerBar.bounds.size.width - 150, 15, 130, 20)];
    self.countLabel.autoresizingMask = NSViewMinXMargin;
    self.countLabel.stringValue = @"Loading...";
    self.countLabel.alignment = NSTextAlignmentRight;
    self.countLabel.editable = NO;
    self.countLabel.bordered = NO;
    self.countLabel.backgroundColor = [NSColor clearColor];
    self.countLabel.textColor = [NSColor colorWithWhite:0.6 alpha:1.0];
    self.countLabel.font = [NSFont systemFontOfSize:13];
    [headerBar addSubview:self.countLabel];
    
    // Main content container
    self.mainContentArea = [[NSView alloc] initWithFrame:NSMakeRect(kSidebarWidth, 0, contentView.bounds.size.width - kSidebarWidth, contentView.bounds.size.height - kHeaderHeight)];
    self.mainContentArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:self.mainContentArea];
    
    // Setup different content views
    [self setupGalleryView];
    [self setupPreferencesView];
    
    // Show gallery view by default
    [self showGalleryView];
}

- (void)setupGalleryView {
    self.galleryView = [[NSView alloc] initWithFrame:self.mainContentArea.bounds];
    self.galleryView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(kThumbnailWidth, kThumbnailHeight);
    layout.sectionInset = NSEdgeInsetsMake(kGridSpacing, kGridSpacing + 5, kGridSpacing, kGridSpacing);
    layout.minimumInteritemSpacing = kGridSpacing;
    layout.minimumLineSpacing = kGridSpacing;
    
    self.collectionView = [[NSCollectionView alloc] initWithFrame:self.galleryView.bounds];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColors = @[[NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.12 alpha:1.0]];
    self.collectionView.selectable = YES;
    
    [self.collectionView registerClass:[VideoCollectionItem class] forItemWithIdentifier:@"VideoItem"];
    
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.galleryView.bounds];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.documentView = self.collectionView;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = NO;
    
    [self.galleryView addSubview:self.scrollView];
}

- (void)setupPreferencesView {
    self.preferencesView = [[NSView alloc] initWithFrame:self.mainContentArea.bounds];
    self.preferencesView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.preferencesView.wantsLayer = YES;
    self.preferencesView.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.12 alpha:1.0] CGColor];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat leftPadding = 15;
    
    // Path Section
    NSBox *pathSection = [[NSBox alloc] initWithFrame:NSMakeRect(30, self.preferencesView.bounds.size.height - 170, self.preferencesView.bounds.size.width - 60, 120)];
    pathSection.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    pathSection.title = @"Wallpaper Location";
    pathSection.titlePosition = NSAtTop;
    
    NSView *pathContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, pathSection.bounds.size.width - 20, 90)];
    
    NSTextField *currentPathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftPadding, 55, pathContent.bounds.size.width - leftPadding * 2, 18)];
    currentPathLabel.stringValue = @"Current Steam Folder:";
    currentPathLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    currentPathLabel.textColor = [NSColor colorWithWhite:0.85 alpha:1.0];
    currentPathLabel.editable = NO;
    currentPathLabel.bordered = NO;
    currentPathLabel.backgroundColor = [NSColor clearColor];
    [pathContent addSubview:currentPathLabel];
    
    NSString *currentPath = [defaults stringForKey:@"steamappsPath"];
    
    NSTextField *pathValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftPadding, 30, pathContent.bounds.size.width - leftPadding * 2, 22)];
    pathValueLabel.stringValue = currentPath ? currentPath : @"No path set";
    pathValueLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    pathValueLabel.textColor = currentPath ? [NSColor systemGreenColor] : [NSColor systemRedColor];
    pathValueLabel.editable = NO;
    pathValueLabel.bordered = NO;
    pathValueLabel.backgroundColor = [NSColor colorWithCalibratedRed:0.08 green:0.08 blue:0.09 alpha:1.0];
    pathValueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    pathValueLabel.drawsBackground = YES;
    pathValueLabel.autoresizingMask = NSViewWidthSizable;
    pathValueLabel.wantsLayer = YES;
    pathValueLabel.layer.cornerRadius = 4;
    [pathContent addSubview:pathValueLabel];
    
    NSButton *changePathButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftPadding, 2, 180, 24)];
    changePathButton.title = @"Change Steam Folder...";
    changePathButton.bezelStyle = NSBezelStyleRounded;
    changePathButton.target = self;
    changePathButton.action = @selector(changePathFromPreferences:);
    [pathContent addSubview:changePathButton];
    
    pathSection.contentView = pathContent;
    [self.preferencesView addSubview:pathSection];
    
    // Performance Section
    NSBox *perfSection = [[NSBox alloc] initWithFrame:NSMakeRect(30, self.preferencesView.bounds.size.height - 320, self.preferencesView.bounds.size.width - 60, 130)];
    perfSection.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    perfSection.title = @"Performance";
    perfSection.titlePosition = NSAtTop;
    
    NSView *perfContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, perfSection.bounds.size.width - 20, 100)];
    
    BOOL pauseOnBattery = [defaults boolForKey:kDefaultsPauseOnBattery];
    NSButton *batteryCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftPadding, 65, perfContent.bounds.size.width - leftPadding * 2, 20)];
    [batteryCheckbox setButtonType:NSButtonTypeSwitch];
    batteryCheckbox.title = @"Pause wallpaper when on battery power";
    batteryCheckbox.state = pauseOnBattery ? NSControlStateValueOn : NSControlStateValueOff;
    batteryCheckbox.target = self;
    batteryCheckbox.action = @selector(pauseOnBatteryChanged:);
    [perfContent addSubview:batteryCheckbox];
    
    BOOL pauseOnFullscreen = [defaults boolForKey:kDefaultsPauseOnFullscreen];
    NSButton *fullscreenCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftPadding, 40, perfContent.bounds.size.width - leftPadding * 2, 20)];
    [fullscreenCheckbox setButtonType:NSButtonTypeSwitch];
    fullscreenCheckbox.title = @"Pause wallpaper when apps are fullscreen";
    fullscreenCheckbox.state = pauseOnFullscreen ? NSControlStateValueOn : NSControlStateValueOff;
    fullscreenCheckbox.target = self;
    fullscreenCheckbox.action = @selector(pauseOnFullscreenChanged:);
    [perfContent addSubview:fullscreenCheckbox];
    
    NSTextField *perfHelpText = [[NSTextField alloc] initWithFrame:NSMakeRect(leftPadding, 5, perfContent.bounds.size.width - leftPadding * 2, 30)];
    perfHelpText.stringValue = @"These settings help conserve battery and reduce distractions during fullscreen activities like games or presentations.";
    perfHelpText.font = [NSFont systemFontOfSize:11];
    perfHelpText.textColor = [NSColor colorWithWhite:0.5 alpha:1.0];
    perfHelpText.editable = NO;
    perfHelpText.bordered = NO;
    perfHelpText.backgroundColor = [NSColor clearColor];
    perfHelpText.lineBreakMode = NSLineBreakByWordWrapping;
    [perfContent addSubview:perfHelpText];
    
    perfSection.contentView = perfContent;
    [self.preferencesView addSubview:perfSection];
    
    // Cache Section
    NSBox *cacheSection = [[NSBox alloc] initWithFrame:NSMakeRect(30, self.preferencesView.bounds.size.height - 430, self.preferencesView.bounds.size.width - 60, 90)];
    cacheSection.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    cacheSection.title = @"Thumbnail Cache";
    cacheSection.titlePosition = NSAtTop;
    
    NSView *cacheContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cacheSection.bounds.size.width - 20, 60)];
    
    self.cacheSizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftPadding, 32, cacheContent.bounds.size.width - leftPadding * 2, 18)];
    [self updateCacheSizeLabel];
    self.cacheSizeLabel.font = [NSFont systemFontOfSize:12];
    self.cacheSizeLabel.textColor = [NSColor colorWithWhite:0.6 alpha:1.0];
    self.cacheSizeLabel.editable = NO;
    self.cacheSizeLabel.bordered = NO;
    self.cacheSizeLabel.backgroundColor = [NSColor clearColor];
    [cacheContent addSubview:self.cacheSizeLabel];
    
    NSButton *clearCacheButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftPadding, 5, 130, 24)];
    clearCacheButton.title = @"Clear Cache";
    clearCacheButton.bezelStyle = NSBezelStyleRounded;
    clearCacheButton.target = self;
    clearCacheButton.action = @selector(clearThumbnailCache:);
    [cacheContent addSubview:clearCacheButton];
    
    cacheSection.contentView = cacheContent;
    [self.preferencesView addSubview:cacheSection];
}

- (void)showGalleryView {
    [self.preferencesView removeFromSuperview];
    if (!self.galleryView.superview) {
        [self.mainContentArea addSubview:self.galleryView];
    }
    self.contentHeaderLabel.stringValue = @"All Wallpapers";
    self.countLabel.hidden = NO;
    [self updateMenuButtonSelection:self.allWallpapersButton];
}

- (void)showPreferencesView {
    [self.galleryView removeFromSuperview];
    if (!self.preferencesView.superview) {
        [self.mainContentArea addSubview:self.preferencesView];
    }
    self.contentHeaderLabel.stringValue = @"Preferences";
    self.countLabel.hidden = YES;
    [self updateMenuButtonSelection:self.preferencesButton];
}

- (void)updateMenuButtonSelection:(NSButton *)selectedButton {
    // Reset all buttons
    self.allWallpapersButton.contentTintColor = [NSColor colorWithWhite:0.8 alpha:1.0];
    self.allWallpapersButton.wantsLayer = NO;
    self.allWallpapersButton.layer.backgroundColor = nil;
    
    self.preferencesButton.contentTintColor = [NSColor colorWithWhite:0.8 alpha:1.0];
    self.preferencesButton.wantsLayer = NO;
    self.preferencesButton.layer.backgroundColor = nil;
    
    // Highlight selected button
    selectedButton.contentTintColor = [NSColor whiteColor];
    selectedButton.wantsLayer = YES;
    selectedButton.layer.backgroundColor = [[NSColor colorWithWhite:0.25 alpha:1.0] CGColor];
    selectedButton.layer.cornerRadius = 6;
}

- (NSTextField *)createSectionLabel:(NSString *)title yPos:(CGFloat)yPos {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(15, yPos, 190, 16)];
    label.stringValue = title;
    label.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    label.textColor = [NSColor colorWithWhite:0.5 alpha:1.0];
    label.alignment = NSTextAlignmentLeft;
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.autoresizingMask = NSViewMinYMargin;
    return label;
}

- (NSButton *)createMenuButton:(NSString *)title yPos:(CGFloat)yPos action:(SEL)action selected:(BOOL)selected {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(10, yPos, 200, 32)];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.bordered = NO;
    button.alignment = NSTextAlignmentLeft;
    button.title = title;
    button.font = [NSFont systemFontOfSize:13];
    button.contentTintColor = selected ? [NSColor whiteColor] : [NSColor colorWithWhite:0.8 alpha:1.0];
    button.target = self;
    button.action = action;
    button.autoresizingMask = NSViewMinYMargin;
    
    if (selected) {
        button.wantsLayer = YES;
        button.layer.backgroundColor = [[NSColor colorWithWhite:0.25 alpha:1.0] CGColor];
        button.layer.cornerRadius = 6;
    }
    
    return button;
}

- (void)showAllWallpapers:(id)sender {
    [self showGalleryView];
}

- (void)openPreferences:(id)sender {
    [self showPreferencesView];
}

- (void)changePathFromPreferences:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Select Steamapps Folder";
    panel.message = @"Please locate your steamapps folder";
    panel.prompt = @"Select";
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = NO;
    
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *selectedURL = panel.URL;
            NSString *selectedPath = selectedURL.path;
            
            NSString *workshopPath = [selectedPath stringByAppendingPathComponent:kWorkshopSubpath];
            BOOL isDirectory;
            BOOL workshopExists = [[NSFileManager defaultManager] fileExistsAtPath:workshopPath isDirectory:&isDirectory];
            
            if (!workshopExists || !isDirectory) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Invalid Folder";
                alert.informativeText = @"Selected folder does not contain Wallpaper Engine workshop content.\\n\\nPlease select the 'steamapps' folder that contains:\\nworkshop/content/431960/";
                alert.alertStyle = NSAlertStyleWarning;
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
                return;
            }
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:selectedPath forKey:@"steamappsPath"];
            [defaults synchronize];
            
            // Trigger reload
            [[NSApp delegate] performSelector:@selector(reloadWallpapers)];
        }
    }];
}

#pragma mark - Performance Settings

- (void)pauseOnBatteryChanged:(id)sender {
    NSButton *checkbox = (NSButton *)sender;
    BOOL enabled = (checkbox.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDefaultsPauseOnBattery];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PerformanceSettingsChanged" object:nil];
}

- (void)pauseOnFullscreenChanged:(id)sender {
    NSButton *checkbox = (NSButton *)sender;
    BOOL enabled = (checkbox.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDefaultsPauseOnFullscreen];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PerformanceSettingsChanged" object:nil];
}

#pragma mark - Cache Management

- (void)updateCacheSizeLabel {
    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    NSUInteger sizeBytes = [cache cacheSize];
    
    NSString *sizeString;
    if (sizeBytes < 1024) {
        sizeString = [NSString stringWithFormat:@"%lu bytes", (unsigned long)sizeBytes];
    } else if (sizeBytes < 1024 * 1024) {
        sizeString = [NSString stringWithFormat:@"%.1f KB", sizeBytes / 1024.0];
    } else {
        sizeString = [NSString stringWithFormat:@"%.1f MB", sizeBytes / (1024.0 * 1024.0)];
    }
    
    self.cacheSizeLabel.stringValue = [NSString stringWithFormat:@"Cache size: %@", sizeString];
}

- (void)clearThumbnailCache:(id)sender {
    ThumbnailCache *cache = [ThumbnailCache sharedCache];
    [cache clearCache];
    [self updateCacheSizeLabel];
    [self.collectionView reloadData];
}

- (void)loadVideos {
    std::vector<Macie::WallpaperProject> wallpapers = [self assetManagerCpp]->getVideoWallpapers();
    
    NSMutableArray *videoArray = [NSMutableArray array];
    for (const auto& wallpaper : wallpapers) {
        [videoArray addObject:@{
            @"id": [NSString stringWithUTF8String:wallpaper.id.c_str()],
            @"title": [NSString stringWithUTF8String:wallpaper.title.c_str()],
            @"path": [NSString stringWithUTF8String:wallpaper.videoFilePath.c_str()]
        }];
    }
    
    self.videos = [videoArray copy];
    [self.collectionView reloadData];
    
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu videos", (unsigned long)self.videos.count];
    
    // Update statistics in sidebar
    NSString *statsText = [NSString stringWithFormat:@"Total Wallpapers: %lu\nCurrently Playing:\n%@",
                          (unsigned long)self.videos.count,
                          self.videos.count > 0 ? self.videos[0][@"title"] : @"None"];
    self.statsLabel.stringValue = statsText;
    
    // Initialize mute button state to match video renderer
    [self updateMuteButton];
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.videos.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    
    VideoCollectionItem *item = [collectionView makeItemWithIdentifier:@"VideoItem" forIndexPath:indexPath];
    
    NSDictionary *video = self.videos[indexPath.item];
    [item configureWithVideoData:video];
    
    return item;
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath) {
        NSDictionary *video = self.videos[indexPath.item];
        NSString *videoPath = video[@"path"];
        NSString *videoTitle = video[@"title"];
        
        // Remember current mute state before loading new video
        BOOL wasMuted = self.videoRenderer.muted;
        
        [self.videoRenderer loadAndPlayVideo:videoPath];
        
        // Reapply the mute state to the new video
        if (wasMuted) {
            [self.videoRenderer mute];
        }
        
        [self updateMuteButton];
        
        // Update statistics with currently playing wallpaper
        NSString *statsText = [NSString stringWithFormat:@"Total Wallpapers: %lu\nCurrently Playing:\n%@",
                              (unsigned long)self.videos.count,
                              videoTitle];
        self.statsLabel.stringValue = statsText;
    }
}

#pragma mark - Actions

- (void)toggleMute:(id)sender {
    if (self.videoRenderer.muted) {
        [self.videoRenderer unmute];
    } else {
        [self.videoRenderer mute];
    }
    
    // Save the mute state to persist between sessions
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.videoRenderer.muted forKey:@"lastMuteState"];
    [defaults synchronize];
    
    [self updateMuteButton];
}

- (void)updateMuteButton {
    if (self.videoRenderer.muted) {
        self.muteButton.title = @"Unmute";
    } else {
        self.muteButton.title = @"Mute";
    }
}

- (void)dealloc {
}

@end

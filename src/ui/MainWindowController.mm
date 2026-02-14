//
//  MainWindowController.m
//  MacieWallpaper - Main Window Controller
//
//  Created on 2026-02-14.
//

#import "MainWindowController.h"
#import "VideoCollectionItem.h"
#import "AVVideoRenderer.h"
#import "AssetManager.hpp"
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
@end

@implementation MainWindowController

- (Macie::AssetManager *)assetManagerCpp {
    return static_cast<Macie::AssetManager *>(self.assetManager);
}

- (instancetype)initWithAssetManager:(void *)assetManager videoRenderer:(AVVideoRenderer *)renderer {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 900, 600)
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
    self.window.title = @"Wallpaper Gallery";
    self.window.minSize = NSMakeSize(600, 400);
    
    NSView *contentView = self.window.contentView;
    
    NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, contentView.bounds.size.height - 50, contentView.bounds.size.width, 50)];
    toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
    
    self.muteButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 10, 120, 30)];
    [self.muteButton setButtonType:NSButtonTypeMomentaryPushIn];
    [self.muteButton setBezelStyle:NSBezelStyleRounded];
    [self updateMuteButton];
    self.muteButton.target = self;
    self.muteButton.action = @selector(toggleMute:);
    [toolbar addSubview:self.muteButton];
    
    self.countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - 220, 15, 200, 20)];
    self.countLabel.autoresizingMask = NSViewMinXMargin;
    self.countLabel.stringValue = @"Loading videos...";
    self.countLabel.alignment = NSTextAlignmentRight;
    self.countLabel.editable = NO;
    self.countLabel.bordered = NO;
    self.countLabel.backgroundColor = [NSColor clearColor];
    self.countLabel.textColor = [NSColor secondaryLabelColor];
    [toolbar addSubview:self.countLabel];
    
    [contentView addSubview:toolbar];
    
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(200, 150);
    layout.sectionInset = NSEdgeInsetsMake(20, 20, 20, 20);
    layout.minimumInteritemSpacing = 20;
    layout.minimumLineSpacing = 20;
    
    self.collectionView = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, contentView.bounds.size.width, contentView.bounds.size.height - 50)];
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColors = @[[NSColor controlBackgroundColor]];
    self.collectionView.selectable = YES;
    
    [self.collectionView registerClass:[VideoCollectionItem class] forItemWithIdentifier:@"VideoItem"];
    
    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, contentView.bounds.size.width, contentView.bounds.size.height - 50)];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.documentView = self.collectionView;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = NO;
    
    [contentView addSubview:self.scrollView];
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
    
    NSLog(@"Gallery: Loaded %lu videos", (unsigned long)self.videos.count);
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.videos.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    
    VideoCollectionItem *item = [collectionView makeItemWithIdentifier:@"VideoItem" forIndexPath:indexPath];
    
    NSDictionary *video = self.videos[indexPath.item];
    item.videoTitle = video[@"title"];
    item.videoPath = video[@"path"];
    item.videoID = video[@"id"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSImage *thumbnail = [self generateThumbnailForVideo:video[@"path"]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (thumbnail) {
                item.imageView.image = thumbnail;
            }
        });
    });
    
    return item;
}

- (NSImage *)generateThumbnailForVideo:(NSString *)videoPath {
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenerator.appliesPreferredTrackTransform = YES;
    imageGenerator.maximumSize = CGSizeMake(360, 270);
    
    CMTime time = CMTimeMakeWithSeconds(1.0, 600);
    NSError *error = nil;
    CGImageRef imageRef = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:&error];
    
    if (imageRef) {
        NSImage *thumbnail = [[NSImage alloc] initWithCGImage:imageRef size:NSZeroSize];
        CGImageRelease(imageRef);
        return thumbnail;
    }
    
    return nil;
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath) {
        NSDictionary *video = self.videos[indexPath.item];
        NSString *videoPath = video[@"path"];
        NSString *videoTitle = video[@"title"];
        
        NSLog(@"Selected video: %@", videoTitle);
        
        [self.videoRenderer loadAndPlayVideo:videoPath];
    }
}

#pragma mark - Actions

- (void)toggleMute:(id)sender {
    if (self.videoRenderer.muted) {
        [self.videoRenderer unmute];
    } else {
        [self.videoRenderer mute];
    }
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
    NSLog(@"MainWindowController: Deallocated");
}

@end

//
//  VideoCollectionItem.h
//  MacieWallpaper - Video Collection View Item
//
//  Created on 2026-02-14. Redesigned 2026-08-02. Rebuilt on the design system
//  2026-08-19.
//

#import <Cocoa/Cocoa.h>

/// Card geometry. Exported because the flow layout in MainWindowController has to
/// agree with it exactly; it previously carried its own copy of these numbers.
extern const CGFloat kMacieCardWidth;
extern const CGFloat kMacieCardHeight;

@interface VideoCollectionItem : NSCollectionViewItem

@property (nonatomic, strong) NSString *videoPath;
@property (nonatomic, strong) NSString *videoTitle;
@property (nonatomic, strong) NSString *videoID;
@property (nonatomic, assign) BOOL isFavorite;
@property (nonatomic, assign) BOOL isPlayingWallpaper;

- (void)configureWithVideoData:(NSDictionary *)videoData
                    isFavorite:(BOOL)favorite
                     isPlaying:(BOOL)playing;

// Legacy single-arg entry point kept so any remaining call sites compile.
- (void)configureWithVideoData:(NSDictionary *)videoData;

@end

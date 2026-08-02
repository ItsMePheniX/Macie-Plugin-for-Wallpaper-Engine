//
//  VideoCollectionItem.h
//  MacieWallpaper - Video Collection View Item
//
//  Created on 2026-02-14. Redesigned 2026-08-02.
//

#import <Cocoa/Cocoa.h>

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

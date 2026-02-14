//
//  VideoCollectionItem.h
//  MacieWallpaper - Video Collection View Item
//
//  Created on 2026-02-14.
//

#import <Cocoa/Cocoa.h>

@interface VideoCollectionItem : NSCollectionViewItem

@property (nonatomic, strong) NSString *videoPath;
@property (nonatomic, strong) NSString *videoTitle;
@property (nonatomic, strong) NSString *videoID;

@end

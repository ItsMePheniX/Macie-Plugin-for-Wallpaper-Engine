//
//  VideoCollectionItem.m
//  MacieWallpaper - Video Collection View Item
//
//  Created on 2026-02-14.
//

#import "VideoCollectionItem.h"

@implementation VideoCollectionItem

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 150)];
    
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 30, 180, 100)];
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    imageView.image = [NSImage imageNamed:NSImageNameIconViewTemplate];
    imageView.wantsLayer = YES;
    imageView.layer.cornerRadius = 8.0;
    imageView.layer.masksToBounds = YES;
    imageView.layer.borderWidth = 1.0;
    imageView.layer.borderColor = [[NSColor separatorColor] CGColor];
    [view addSubview:imageView];
    
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 5, 180, 20)];
    titleLabel.stringValue = @"Loading...";
    titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    titleLabel.textColor = [NSColor labelColor];
    titleLabel.alignment = NSTextAlignmentCenter;
    titleLabel.editable = NO;
    titleLabel.bordered = NO;
    titleLabel.backgroundColor = [NSColor clearColor];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [view addSubview:titleLabel];
    
    self.textField = titleLabel;
    self.imageView = imageView;
    self.view = view;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    
    if (selected) {
        self.view.layer.borderWidth = 3.0;
        self.view.layer.borderColor = [[NSColor systemBlueColor] CGColor];
    } else {
        self.view.layer.borderWidth = 0.0;
    }
}

- (void)setVideoTitle:(NSString *)videoTitle {
    _videoTitle = videoTitle;
    self.textField.stringValue = videoTitle ?: @"Untitled";
}

@end

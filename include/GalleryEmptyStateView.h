//
//  GalleryEmptyStateView.h
//  MacieWallpaper - Empty-state placeholder for the wallpaper grid
//
//  Created on 2026-08-19.
//
//  Shown whenever the grid has nothing to display. Previously an empty Favorites
//  list, an empty Recent list or a search with no matches all rendered as a blank
//  void, which is indistinguishable from a bug.
//

#ifndef GalleryEmptyStateView_h
#define GalleryEmptyStateView_h

#import <Cocoa/Cocoa.h>

@interface GalleryEmptyStateView : NSView

/// Sets the message and makes the view visible. `symbolName` is an SF Symbol.
- (void)showSymbol:(NSString *)symbolName
             title:(NSString *)title
          subtitle:(NSString *)subtitle;

/// Shows a progress-style state with an activity spinner instead of a symbol.
/// Pass `progress` = 0 and `total` = 0 before the scan knows how many folders;
/// once it does the subtitle reads "X of Y folders read".
- (void)showProgressTitle:(NSString *)title
                 subtitle:(NSString *)subtitle
                 progress:(NSUInteger)progress
                    total:(NSUInteger)total;

@end

#endif /* GalleryEmptyStateView_h */

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
//  It also hosts the launch scan's progress, which is the other thing an empty grid
//  can mean.
//

#ifndef GalleryEmptyStateView_h
#define GalleryEmptyStateView_h

#import <Cocoa/Cocoa.h>

@interface GalleryEmptyStateView : NSView

/// Sets the message and makes the view visible. `symbolName` is an SF Symbol.
- (void)showSymbol:(NSString *)symbolName
             title:(NSString *)title
          subtitle:(NSString *)subtitle;

/// Shows a progress bar instead of a symbol, and makes the view visible. Pass
/// `total` as 0 for an indeterminate spinner. Repeated calls move the existing bar
/// rather than rebuilding the panel, so this is safe to call on every update.
- (void)showProgressTitle:(NSString *)title
                 subtitle:(NSString *)subtitle
                 progress:(NSUInteger)completed
                    total:(NSUInteger)total;

@end

#endif /* GalleryEmptyStateView_h */

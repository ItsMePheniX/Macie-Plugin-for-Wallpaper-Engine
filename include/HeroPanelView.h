//
//  HeroPanelView.h
//  MacieWallpaper - Featured wallpaper panel
//
//  Created on 2026-08-19.
//
//  The banner across the top of the gallery: a thumbnail that plays a muted
//  preview on hover, and a floating panel naming the wallpaper.
//
//  It shows one of two states. PLAYING means the wallpaper is on the desktop.
//  PREVIEW means the user is only looking at it, and an Apply button appears to
//  commit it. The panel never touches the desktop itself — it reports the request
//  and the host decides.
//

#ifndef HeroPanelView_h
#define HeroPanelView_h

#import <Cocoa/Cocoa.h>

@interface HeroPanelView : NSView

/// Fired when Apply is clicked, which is only possible in the preview state.
@property (nonatomic, copy) void (^onApplyRequested)(NSDictionary *video);
/// Fired when the heart is clicked. The host owns the favorites set, so it decides
/// what the new state is and calls -setFavorite: back.
@property (nonatomic, copy) void (^onFavoriteToggled)(NSDictionary *video);

/// The wallpaper on display, or nil in the empty state.
@property (nonatomic, readonly) NSDictionary *wallpaper;
/// YES when the displayed wallpaper is not the one on the desktop.
@property (nonatomic, readonly) BOOL isPreview;

/// Shows a wallpaper. Pass `preview` NO for the one that is actually playing.
- (void)showWallpaper:(NSDictionary *)video
            isPreview:(BOOL)preview
           isFavorite:(BOOL)favorite;

/// Shows the "nothing playing" state.
- (void)showEmpty;

/// Recolours the heart without rebuilding anything else.
- (void)setFavorite:(BOOL)favorite;

@end

#endif /* HeroPanelView_h */

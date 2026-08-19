//
//  SettingsSheetController.h
//  MacieWallpaper - Settings sheet
//
//  Created on 2026-08-19.
//
//  Owns the settings sheet. It is built once and retained, rather than
//  reconstructed from ninety lines of inline control creation on every open, and
//  its sections are laid out with MacieVStack instead of a hardcoded y countdown.
//

#ifndef SettingsSheetController_h
#define SettingsSheetController_h

#import <Cocoa/Cocoa.h>

@interface SettingsSheetController : NSObject

/// The user asked to pick a different steamapps folder. The host owns the folder
/// picker and the library reload, so this only reports the intent.
@property (nonatomic, copy) void (^onPathChangeRequested)(void);
/// The thumbnail cache was cleared; the host refreshes anything showing its size.
@property (nonatomic, copy) void (^onCacheCleared)(void);

/// Presents the sheet on `hostWindow`, refreshing every control from current
/// state first. Safe to call when the sheet is already showing.
- (void)presentInWindow:(NSWindow *)hostWindow;

/// Re-reads the steamapps path and cache size into the sheet's labels. Called on
/// present, and by the host after a library reload.
- (void)refresh;

@end

#endif /* SettingsSheetController_h */

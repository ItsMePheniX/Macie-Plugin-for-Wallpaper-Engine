//
//  PreferencesWindowController.h
//  MacieWallpaper - Preferences Window
//
//  Created on 2026-02-15.
//

#import <Cocoa/Cocoa.h>

@interface PreferencesWindowController : NSWindowController

@property (nonatomic, copy) void (^onPathChanged)(void);

@end

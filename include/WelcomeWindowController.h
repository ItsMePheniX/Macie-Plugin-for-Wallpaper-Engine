//
//  WelcomeWindowController.h
//  MacieWallpaper - Welcome Window
//
//  Created on 2026-02-15.
//

#import <Cocoa/Cocoa.h>

@interface WelcomeWindowController : NSWindowController

@property (nonatomic, copy) void (^completionHandler)(NSString *selectedPath);

- (instancetype)initWithCompletionHandler:(void (^)(NSString *selectedPath))handler;

@end

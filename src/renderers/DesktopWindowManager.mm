//
//  DesktopWindowManager.mm
//  MacieWallpaper - Window Manager
//
//  Created on 2026-02-14.
//

#import "DesktopWindowManager.h"

@implementation DesktopWindowManager

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"DesktopWindowManager: Initialized");
    }
    return self;
}

- (void)dealloc {
    NSLog(@"DesktopWindowManager: Deallocated");
}

@end

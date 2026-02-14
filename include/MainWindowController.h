//
//  MainWindowController.h
//  MacieWallpaper - Main Window Controller
//
//  Created on 2026-02-14.
//

#import <Cocoa/Cocoa.h>
#import "AssetManager.hpp"

@class AVVideoRenderer;

@interface MainWindowController : NSWindowController <NSCollectionViewDelegate>

- (instancetype)initWithAssetManager:(void *)assetManager videoRenderer:(AVVideoRenderer *)renderer;

@end

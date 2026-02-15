//
//  Constants.h
//  MacieWallpaper - Application Constants
//
//  Created on 2026-02-15.
//

#ifndef Constants_h
#define Constants_h

// App Information
static NSString * const kAppName = @"MacieWallpaper";
static NSString * const kAppVersion = @"1.0.0";

// Steam Workshop Constants
static NSString * const kWallpaperEngineAppId = @"431960";
static NSString * const kWorkshopSubpath = @"workshop/content/431960";

// UserDefaults Keys
static NSString * const kDefaultsSteamappsPath = @"steamappsPath";
static NSString * const kDefaultsLastMuteState = @"lastMuteState";
static NSString * const kDefaultsLastWallpaperId = @"lastWallpaperId";
static NSString * const kDefaultsPauseOnBattery = @"pauseOnBattery";
static NSString * const kDefaultsPauseOnFullscreen = @"pauseOnFullscreen";

// Cache Settings
static NSString * const kCacheDirectoryName = @"MacieWallpaper";
static NSString * const kThumbnailCacheSubdir = @"thumbnails";

// UI Constants
static const CGFloat kSidebarWidth = 220.0;
static const CGFloat kHeaderHeight = 50.0;
static const CGFloat kThumbnailWidth = 200.0;
static const CGFloat kThumbnailHeight = 150.0;
static const CGFloat kGridSpacing = 20.0;

// Window Sizes
static const CGFloat kMainWindowWidth = 1000.0;
static const CGFloat kMainWindowHeight = 650.0;
static const CGFloat kMainWindowMinWidth = 800.0;
static const CGFloat kMainWindowMinHeight = 500.0;
static const CGFloat kWelcomeWindowWidth = 520.0;
static const CGFloat kWelcomeWindowHeight = 380.0;

#endif /* Constants_h */

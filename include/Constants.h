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
static NSString * const kDefaultsSteamappsPath    = @"steamappsPath";
static NSString * const kDefaultsLastMuteState    = @"lastMuteState";
static NSString * const kDefaultsLastWallpaperId  = @"lastWallpaperId";
static NSString * const kDefaultsPauseOnBattery   = @"pauseOnBattery";
static NSString * const kDefaultsPauseOnFullscreen = @"pauseOnFullscreen";
static NSString * const kDefaultsFavoriteIds      = @"favoriteWallpaperIds";
static NSString * const kDefaultsRecentIds        = @"recentWallpaperIds";

// Cache Settings
static NSString * const kCacheDirectoryName = @"MacieWallpaper";
static NSString * const kThumbnailCacheSubdir = @"thumbnails";

// Thumbnail constants used by ThumbnailCache
static const CGFloat kThumbnailWidth  = 200.0;
static const CGFloat kThumbnailHeight = 150.0;

// Window Sizes
static const CGFloat kMainWindowWidth     = 1280.0;
static const CGFloat kMainWindowHeight    = 800.0;
static const CGFloat kMainWindowMinWidth  = 1100.0;
static const CGFloat kMainWindowMinHeight = 720.0;
static const CGFloat kWelcomeWindowWidth  = 520.0;
static const CGFloat kWelcomeWindowHeight = 380.0;

// Layout
static const CGFloat kSidebarWidth        = 230.0;
static const CGFloat kToolbarHeight       = 52.0;
static const CGFloat kHeroHeight          = 280.0;
static const CGFloat kMiniPlayerHeight    = 75.0;
static const CGFloat kGalleryHeaderHeight = 44.0;

#endif /* Constants_h */

//
//  Constants.m
//  MacieWallpaper - Application Constants (definitions)
//
//  Single definition point for everything declared extern in Constants.h.
//

#import "Constants.h"

// App Information
NSString * const kAppName    = @"MacieWallpaper";
NSString * const kAppVersion = @"1.0.0";

// Steam Workshop Constants
NSString * const kWallpaperEngineAppId = @"431960";
NSString * const kWorkshopSubpath      = @"workshop/content/431960";

// UserDefaults Keys
NSString * const kDefaultsSteamappsPath     = @"steamappsPath";
NSString * const kDefaultsLastMuteState     = @"lastMuteState";
NSString * const kDefaultsLastWallpaperId   = @"lastWallpaperId";
NSString * const kDefaultsLastWallpaperSnapshot = @"lastWallpaperSnapshot";
NSString * const kDefaultsPauseOnBattery    = @"pauseOnBattery";
NSString * const kDefaultsPauseOnFullscreen = @"pauseOnFullscreen";
NSString * const kDefaultsFavoriteIds       = @"favoriteWallpaperIds";
NSString * const kDefaultsRecentIds         = @"recentWallpaperIds";
NSString * const kDefaultsGallerySortOrder  = @"gallerySortOrder";

// Notification names
NSString * const kNotificationPerformanceSettingsChanged = @"PerformanceSettingsChanged";
NSString * const kNotificationWallpaperFavoriteToggled   = @"WallpaperFavoriteToggled";

// Cache Settings
NSString * const kCacheDirectoryName    = @"MacieWallpaper";
NSString * const kThumbnailCacheSubdir  = @"thumbnails";
NSString * const kMetadataCacheFileName = @"metadata.plist";

// Thumbnail constants used by ThumbnailCache
const CGFloat kThumbnailWidth  = 200.0;
const CGFloat kThumbnailHeight = 150.0;

// Window Sizes
const CGFloat kMainWindowWidth     = 1280.0;
const CGFloat kMainWindowHeight    = 800.0;
const CGFloat kMainWindowMinWidth  = 1100.0;
const CGFloat kMainWindowMinHeight = 720.0;
const CGFloat kWelcomeWindowWidth  = 520.0;
const CGFloat kWelcomeWindowHeight = 380.0;

// Layout
const CGFloat kSidebarWidth        = 230.0;
const CGFloat kToolbarHeight       = 52.0;
const CGFloat kHeroHeight          = 280.0;
const CGFloat kGalleryHeaderHeight = 44.0;

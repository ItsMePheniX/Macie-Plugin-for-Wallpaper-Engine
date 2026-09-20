//
//  Constants.h
//  MacieWallpaper - Application Constants
//
//  Created on 2026-02-15.
//
//  Declarations only — the definitions live in src/core/Constants.m so every
//  translation unit shares one instance instead of getting a private copy.
//

#ifndef Constants_h
#define Constants_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// App Information
extern NSString * const kAppName;
extern NSString * const kAppVersion;

// Steam Workshop Constants
extern NSString * const kWallpaperEngineAppId;
extern NSString * const kWorkshopSubpath;

// UserDefaults Keys
extern NSString * const kDefaultsSteamappsPath;
extern NSString * const kDefaultsLastMuteState;
/// Superseded by the per-display snapshot map below, which records each display's
/// wallpaper id. Read once at launch to migrate installs that predate that map, and
/// never written again — two records of the same fact can disagree.
extern NSString * const kDefaultsLastWallpaperId;
<<<<<<< HEAD
/// Display key → snapshot of the wallpaper on that display, held so that every
/// display's playback and the hero panel can be restored at launch without waiting for
/// the library scan. Also the app's only record of which wallpaper is on which display.
extern NSString * const kDefaultsLastWallpaperSnapshot;
/// The display the gallery currently applies wallpapers to, or absent for all of them.
extern NSString * const kDefaultsWallpaperTarget;
=======
>>>>>>> origin/main
extern NSString * const kDefaultsPauseOnBattery;
extern NSString * const kDefaultsPauseOnFullscreen;
extern NSString * const kDefaultsFavoriteIds;
extern NSString * const kDefaultsRecentIds;
extern NSString * const kDefaultsGallerySortOrder;

// Notification names
extern NSString * const kNotificationPerformanceSettingsChanged;
extern NSString * const kNotificationWallpaperFavoriteToggled;

// Cache Settings
extern NSString * const kCacheDirectoryName;
extern NSString * const kThumbnailCacheSubdir;
extern NSString * const kMetadataCacheFileName;

// Thumbnail constants used by ThumbnailCache
extern const CGFloat kThumbnailWidth;
extern const CGFloat kThumbnailHeight;

// Window Sizes
extern const CGFloat kMainWindowWidth;
extern const CGFloat kMainWindowHeight;
extern const CGFloat kMainWindowMinWidth;
extern const CGFloat kMainWindowMinHeight;
extern const CGFloat kWelcomeWindowWidth;
extern const CGFloat kWelcomeWindowHeight;

// Layout
extern const CGFloat kSidebarWidth;
extern const CGFloat kToolbarHeight;
extern const CGFloat kHeroHeight;
extern const CGFloat kGalleryHeaderHeight;

#endif /* Constants_h */

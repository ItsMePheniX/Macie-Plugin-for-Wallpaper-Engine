//
//  SidebarView.h
//  MacieWallpaper - Gallery sidebar
//
//  Created on 2026-08-19.
//
//  Owns the sidebar's construction, selection state and badges. The host
//  controller talks to it through one callback and three setters, and no longer
//  holds eight sidebar outlets of its own.
//

#ifndef SidebarView_h
#define SidebarView_h

#import <Cocoa/Cocoa.h>

/// Sidebar row identities. Collection rows occupy
/// `MacieSidebarSectionCollection + index`.
typedef NS_ENUM(NSInteger, MacieSidebarSection) {
    MacieSidebarSectionLibrary    = 0,
    MacieSidebarSectionFavorites  = 1,
    MacieSidebarSectionRecent     = 2,
    MacieSidebarSectionRandom     = 3,
    MacieSidebarSectionCollection = 100, // + index
    MacieSidebarSectionSettings   = 200,
    MacieSidebarSectionAbout      = 201,
};

/// The keyword collections shown under COLLECTIONS, in display order.
/// C linkage: defined in SidebarView.m but consumed from MainWindowController.mm.
#if defined(__cplusplus)
extern "C" {
#endif
extern NSArray<NSString *> *MacieCollectionNames(void);
/// Title keywords that place a wallpaper in a collection.
extern NSDictionary<NSString *, NSArray<NSString *> *> *MacieCollectionKeywords(void);
#if defined(__cplusplus)
}
#endif

@interface SidebarView : NSVisualEffectView

/// Fired when the user clicks a row. Rows that are commands rather than filters
/// (Random, Settings, About) are reported the same way; the host decides what a
/// section means.
@property (nonatomic, copy) void (^onSectionSelected)(MacieSidebarSection section);

/// Moves the selection highlight. Pass the host's current section — commands like
/// Random never become the selection, so the host simply does not call this for them.
- (void)setSelectedSection:(MacieSidebarSection)section;

/// Right-hand counts on the Library / Favorites / Recent rows.
- (void)setLibraryCount:(NSUInteger)library
         favoritesCount:(NSUInteger)favorites
            recentCount:(NSUInteger)recent;

/// The two footer lines reporting what the app is responsible for on disk.
- (void)setLibraryText:(NSString *)libraryText cacheText:(NSString *)cacheText;

@end

#endif /* SidebarView_h */

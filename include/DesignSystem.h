//
//  DesignSystem.h
//  MacieWallpaper - Visual design tokens and view factories
//
//  Created on 2026-08-19.
//
//  The single source of visual truth. Every font size, spacing value, colour and
//  standard control in the UI comes from here, so the app cannot drift back into
//  the twelve-ad-hoc-font-sizes state it was in before.
//
//  No app logic and no state live in this file — it is tokens and factories only.
//

#ifndef DesignSystem_h
#define DesignSystem_h

#import <Cocoa/Cocoa.h>

// These are compiled as C (DesignSystem.m) but consumed from Objective-C++
// (MainWindowController.mm), so the declarations need C linkage — otherwise the
// C++ translation unit looks for mangled symbols that do not exist.
#if defined(__cplusplus)
extern "C" {
#endif

// ---------------------------------------------------------------------------
#pragma mark - Type scale

/// Five steps, derived from Apple's macOS text styles. Nothing is smaller than
/// 11pt, which is the smallest size Apple specifies for macOS interfaces; the
/// previous UI had 9pt and 9.5pt labels.
///
///   22 bold        hero title
///   15 semibold    app name, settings section headers
///   13 semibold    gallery header, card title
///   13 regular     sidebar rows, settings body
///   11 regular     metadata, counts, badges, descriptions
extern NSFont *MacieFontTitle(void);
extern NSFont *MacieFontHeading(void);
extern NSFont *MacieFontBodyEmphasized(void);
extern NSFont *MacieFontBody(void);
extern NSFont *MacieFontCaption(void);
extern NSFont *MacieFontCaptionEmphasized(void);
/// Tabular figures for the disk-usage footer, so the numbers do not jitter as
/// they update.
extern NSFont *MacieFontMonoCaption(void);

// ---------------------------------------------------------------------------
#pragma mark - Spacing grid

/// An 8pt grid. Frames are composed from these rather than typed as literals,
/// which is what actually keeps edges aligned across independent views.
extern const CGFloat kMacieSpaceXS;    //  4
extern const CGFloat kMacieSpaceS;     //  8
extern const CGFloat kMacieSpaceM;     // 12
extern const CGFloat kMacieSpaceL;     // 16
extern const CGFloat kMacieSpaceXL;    // 20
extern const CGFloat kMacieSpaceXXL;   // 24

/// Left/right margin for everything in the content region — search field,
/// gallery header, hero info panel, and the collection view's section inset.
/// Sharing one value is what puts them all on a single left edge.
extern const CGFloat kMacieContentInset;

/// Interior margin for the sidebar, which is a narrower region and so uses a
/// tighter inset than the content area.
extern const CGFloat kMacieSidebarInset;

/// Standard heights, so a row's box and its contents cannot disagree.
extern const CGFloat kMacieRowHeight;        // 30 — sidebar row
extern const CGFloat kMacieRowGutter;        //  4 — gap between sidebar rows
extern const CGFloat kMacieControlHeight;    // 28 — buttons
extern const CGFloat kMacieFieldHeight;      // 30 — text/search fields
extern const CGFloat kMacieCornerRadius;     //  7 — buttons, rows
extern const CGFloat kMacieCardCornerRadius; // 12 — cards, panels

// ---------------------------------------------------------------------------
#pragma mark - Palette

/// The accent blue. This value was typed out eight times across two files
/// before; it now has one definition.
extern NSColor *MacieAccentColor(void);
/// Used for the hero panel's PREVIEW state, to distinguish "looking at this" from
/// the accent-blue "this is on your desktop".
extern NSColor *MacieWarningColor(void);

/// Three surface levels, replacing four near-identical greys — two of which
/// differed only by 0.01 in the red channel.
extern NSColor *MacieBackgroundColor(void);          // window / gallery backdrop
extern NSColor *MacieSurfaceColor(void);             // gallery header bar
extern NSColor *MacieElevatedSurfaceColor(void);     // cards, settings sheet

extern NSColor *MaciePrimaryTextColor(void);
extern NSColor *MacieSecondaryTextColor(void);
extern NSColor *MacieTertiaryTextColor(void);
extern NSColor *MacieHairlineColor(void);

// ---------------------------------------------------------------------------
#pragma mark - View factories

/// A non-editable, borderless, transparent label. Replaces the five-line
/// `editable = NO; bordered = NO; backgroundColor = clearColor` incantation that
/// appeared twenty times.
extern NSTextField *MacieLabel(NSString *text, NSFont *font, NSColor *color);

/// Filled accent button — the primary action in a panel.
extern NSButton *MacieAccentButton(NSString *title, id target, SEL action);
/// Muted filled button — secondary actions.
extern NSButton *MacieSecondaryButton(NSString *title, id target, SEL action);
/// Borderless SF Symbol button, as used in the toolbar and on cards.
extern NSButton *MacieIconButton(NSString *symbolName, NSString *tooltip, id target, SEL action);

/// Applies the app's dark appearance to a window. The app has no light-mode
/// palette, so without this a Mac set to Light Mode resolves `labelColor` to
/// near-black against the hardcoded dark backgrounds.
extern void MacieApplyDarkAppearance(NSWindow *window);

#if defined(__cplusplus)
}   // extern "C"
#endif

// ---------------------------------------------------------------------------
#pragma mark - Vertical stacker

/// Lays views out top-down inside an unflipped superview, tracking the running y
/// so that inserting a row cannot silently shift everything below it. Replaces
/// the sidebar's `cursor -= 36` chain and the settings sheet's `y = 440` countdown.
@interface MacieVStack : NSObject

/// @param top    y-coordinate of the first row's top edge.
/// @param inset  left margin for rows added with -addView:height:.
/// @param width  width for rows added with -addView:height:.
- (instancetype)initWithTop:(CGFloat)top inset:(CGFloat)inset width:(CGFloat)width;

/// y-coordinate of the next row's top edge. Read this to place something the
/// stack does not manage, or to size a container to its contents.
@property (nonatomic, readonly) CGFloat cursor;

/// Frames `view` at the current cursor with the stack's inset and width, then
/// advances past it. Returns the frame that was applied.
- (NSRect)addView:(NSView *)view height:(CGFloat)height;

/// As -addView:height:, followed by an extra gap. Use for the last row of a group.
- (NSRect)addView:(NSView *)view height:(CGFloat)height followedByGap:(CGFloat)gap;

/// Advances the cursor without placing anything.
- (void)addGap:(CGFloat)gap;

@end

#endif /* DesignSystem_h */

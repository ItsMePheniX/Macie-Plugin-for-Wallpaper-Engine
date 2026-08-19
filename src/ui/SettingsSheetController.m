//
//  SettingsSheetController.m
//  MacieWallpaper - Settings sheet
//
//  Created on 2026-08-19.
//

#import "SettingsSheetController.h"
#import "DesignSystem.h"
#import "Constants.h"
#import "ThumbnailCache.h"
#import <ServiceManagement/ServiceManagement.h>

/// Sheet geometry. The height is derived from the laid-out content rather than
/// guessed, so a section can be added without leaving dead space at the bottom.
static const CGFloat kSheetWidth = 480.0;

@implementation SettingsSheetController {
    NSWindow    *_sheet;
    NSTextField *_pathLabel;
    NSTextField *_cacheSizeLabel;
    NSButton    *_batteryCheckbox;
    NSButton    *_fullscreenCheckbox;
    NSButton    *_loginCheckbox;
}

// ---------------------------------------------------------------------------
#pragma mark - Presentation

- (void)presentInWindow:(NSWindow *)hostWindow {
    if (!hostWindow) return;
    if (!_sheet) [self buildSheet];

    [self refresh];

    if (_sheet.sheetParent) return;   // already showing
    [hostWindow beginSheet:_sheet completionHandler:nil];
}

- (void)closeSheet:(id)sender {
    NSWindow *parent = _sheet.sheetParent;
    if (parent) [parent endSheet:_sheet];
}

// ---------------------------------------------------------------------------
#pragma mark - Construction

- (void)buildSheet {
    // Built at a provisional height, then resized to fit once the stack has laid
    // the content out.
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kSheetWidth, 600)
                                         styleMask:(NSWindowStyleMaskTitled |
                                                    NSWindowStyleMaskClosable)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _sheet.title = @"Settings";
    MacieApplyDarkAppearance(_sheet);

    NSView *content = _sheet.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = MacieElevatedSurfaceColor().CGColor;

    CGFloat inset  = kMacieSpaceXXL;
    CGFloat fieldW = kSheetWidth - 2 * inset;

    // Laid out from the top down. Because the stack reports its own cursor, the
    // window can be sized to the content instead of the content being squeezed
    // into a guessed window height.
    MacieVStack *stack = [[MacieVStack alloc] initWithTop:600 - kMacieSpaceXXL
                                                   inset:inset
                                                   width:fieldW];

    // --- Wallpaper location -------------------------------------------------
    [self addHeader:@"Wallpaper Location" toStack:stack inView:content];

    _pathLabel = MacieLabel(@"", MacieFontMonoCaption(), MacieSecondaryTextColor());
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.drawsBackground = YES;
    _pathLabel.backgroundColor = MacieBackgroundColor();
    _pathLabel.wantsLayer = YES;
    _pathLabel.layer.cornerRadius = 6.0;
    // A one-line field needs vertical padding to not look cramped against its
    // own background fill.
    [content addSubview:_pathLabel];
    [stack addView:_pathLabel height:26 followedByGap:kMacieSpaceM];

    NSButton *changeBtn = MacieSecondaryButton(@"Change Steam Folder…", self,
                                               @selector(changePathClicked:));
    [content addSubview:changeBtn];
    NSRect r = [stack addView:changeBtn height:kMacieControlHeight followedByGap:kMacieSpaceXXL];
    changeBtn.frame = NSMakeRect(r.origin.x, r.origin.y, 200, r.size.height);

    // --- Performance --------------------------------------------------------
    [self addHeader:@"Performance" toStack:stack inView:content];

    _batteryCheckbox = [self addCheckbox:@"Pause wallpaper when on battery power"
                                  action:@selector(pauseOnBatteryChanged:)
                                 toStack:stack
                                  inView:content];
    _fullscreenCheckbox = [self addCheckbox:@"Pause wallpaper when apps are fullscreen"
                                     action:@selector(pauseOnFullscreenChanged:)
                                    toStack:stack
                                     inView:content];
    [stack addGap:kMacieSpaceL];

    // --- Startup ------------------------------------------------------------
    [self addHeader:@"Startup" toStack:stack inView:content];

    _loginCheckbox = [self addCheckbox:[NSString stringWithFormat:@"Launch %@ at login", kAppName]
                                action:@selector(launchAtLoginChanged:)
                               toStack:stack
                                inView:content];
    if (@available(macOS 13.0, *)) {
        // supported
    } else {
        // SMAppService is the only launch-at-login API this app uses, and it is
        // macOS 13+. Below that the control would silently do nothing, so say so.
        _loginCheckbox.enabled = NO;
        _loginCheckbox.toolTip = @"Requires macOS 13 or later";
    }
    [stack addGap:kMacieSpaceL];

    // --- Thumbnail cache ----------------------------------------------------
    [self addHeader:@"Thumbnail Cache" toStack:stack inView:content];

    _cacheSizeLabel = MacieLabel(@"", MacieFontBody(), MacieSecondaryTextColor());
    [content addSubview:_cacheSizeLabel];
    [stack addView:_cacheSizeLabel height:18 followedByGap:kMacieSpaceM];

    NSButton *clearBtn = MacieSecondaryButton(@"Clear Cache", self,
                                              @selector(clearCacheClicked:));
    [content addSubview:clearBtn];
    NSRect cr = [stack addView:clearBtn height:kMacieControlHeight];
    clearBtn.frame = NSMakeRect(cr.origin.x, cr.origin.y, 140, cr.size.height);

    // --- Done ---------------------------------------------------------------
    // Everything above consumed `600 - stack.cursor`; the footer row adds its own
    // height plus symmetric margins, and the window is resized to the total.
    CGFloat contentBottom = stack.cursor;
    CGFloat footerH = kMacieControlHeight + 2 * kMacieSpaceXL;
    CGFloat used    = (600 - contentBottom) + footerH;

    NSButton *doneBtn = MacieAccentButton(@"Done", self, @selector(closeSheet:));
    doneBtn.keyEquivalent = @"\r";
    [content addSubview:doneBtn];

    // Resize to fit, then place the footer relative to the final height. Shifting
    // the content up by the same delta keeps the top margin at kMacieSpaceXXL.
    CGFloat finalH = used;
    CGFloat delta  = 600 - finalH;
    [_sheet setContentSize:NSMakeSize(kSheetWidth, finalH)];
    for (NSView *sub in content.subviews) {
        if (sub == doneBtn) continue;
        NSRect f = sub.frame;
        sub.frame = NSMakeRect(f.origin.x, f.origin.y - delta, f.size.width, f.size.height);
    }

    doneBtn.frame = NSMakeRect(kSheetWidth - kMacieSpaceXXL - 80, kMacieSpaceXL,
                               80, kMacieControlHeight);
}

- (void)addHeader:(NSString *)title toStack:(MacieVStack *)stack inView:(NSView *)parent {
    NSTextField *hdr = MacieLabel(title, MacieFontHeading(), MaciePrimaryTextColor());
    [parent addSubview:hdr];
    [stack addView:hdr height:20 followedByGap:kMacieSpaceS];
}

- (NSButton *)addCheckbox:(NSString *)title
                   action:(SEL)action
                  toStack:(MacieVStack *)stack
                   inView:(NSView *)parent {
    NSButton *cb = [[NSButton alloc] initWithFrame:NSZeroRect];
    [cb setButtonType:NSButtonTypeSwitch];
    cb.title  = title;
    cb.font   = MacieFontBody();
    cb.target = self;
    cb.action = action;
    [parent addSubview:cb];
    [stack addView:cb height:22 followedByGap:kMacieSpaceXS];
    return cb;
}

// ---------------------------------------------------------------------------
#pragma mark - State

- (void)refresh {
    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];

    NSString *path = [def stringForKey:kDefaultsSteamappsPath];
    _pathLabel.stringValue = path ?: @"Not configured";
    _pathLabel.textColor   = path ? MacieSecondaryTextColor() : [NSColor systemRedColor];

    _batteryCheckbox.state    = [def boolForKey:kDefaultsPauseOnBattery]    ? NSControlStateValueOn : NSControlStateValueOff;
    _fullscreenCheckbox.state = [def boolForKey:kDefaultsPauseOnFullscreen] ? NSControlStateValueOn : NSControlStateValueOff;
    _loginCheckbox.state      = [self isLaunchAtLoginEnabled]               ? NSControlStateValueOn : NSControlStateValueOff;

    [self updateCacheSizeLabel];
}

- (void)updateCacheSizeLabel {
    NSUInteger bytes = [[ThumbnailCache sharedCache] cacheSize];
    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                                      countStyle:NSByteCountFormatterCountStyleFile];
    _cacheSizeLabel.stringValue = [NSString stringWithFormat:@"%@ on disk", sizeStr];
}

// ---------------------------------------------------------------------------
#pragma mark - Actions

- (void)changePathClicked:(id)sender {
    if (self.onPathChangeRequested) self.onPathChangeRequested();
}

- (void)pauseOnBatteryChanged:(NSButton *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(sender.state == NSControlStateValueOn)
                                            forKey:kDefaultsPauseOnBattery];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationPerformanceSettingsChanged
                                                       object:nil];
}

- (void)pauseOnFullscreenChanged:(NSButton *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(sender.state == NSControlStateValueOn)
                                            forKey:kDefaultsPauseOnFullscreen];
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationPerformanceSettingsChanged
                                                       object:nil];
}

- (void)clearCacheClicked:(id)sender {
    [[ThumbnailCache sharedCache] clearCache];
    [self updateCacheSizeLabel];
    if (self.onCacheCleared) self.onCacheCleared();
}

- (BOOL)isLaunchAtLoginEnabled {
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (void)launchAtLoginChanged:(NSButton *)sender {
    if (@available(macOS 13.0, *)) {
        NSError *err = nil;
        BOOL enable = (sender.state == NSControlStateValueOn);
        if (enable) [[SMAppService mainAppService] registerAndReturnError:&err];
        else        [[SMAppService mainAppService] unregisterAndReturnError:&err];

        if (err) {
            // Put the control back where the system actually is, then explain.
            sender.state = [self isLaunchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = enable ? @"Could Not Enable Launch at Login"
                                       : @"Could Not Disable Launch at Login";
            alert.informativeText = err.localizedDescription;
            [alert beginSheetModalForWindow:_sheet completionHandler:nil];
        }
    } else {
        sender.state = NSControlStateValueOff;
    }
}

@end

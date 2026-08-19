//
//  WelcomeWindowController.m
//  MacieWallpaper - Welcome Window
//
//  Created on 2026-02-15.
//

#import "WelcomeWindowController.h"
#import "Constants.h"
#import "DesignSystem.h"

/// Height of a standard rounded push button.
static const CGFloat kWelcomeButtonHeight = 32.0;

@interface WelcomeWindowController ()
@property (strong, nonatomic) NSTextField *titleLabel;
@property (strong, nonatomic) NSTextField *messageLabel;
@property (strong, nonatomic) NSButton *browseButton;
@property (strong, nonatomic) NSButton *quitButton;
@property (strong, nonatomic) NSTextField *pathLabel;
@property (strong, nonatomic) NSString *selectedSteamappsPath;
@end

@implementation WelcomeWindowController

- (instancetype)initWithCompletionHandler:(void (^)(NSString *))handler {
    // Uses the shared window constants; this window used to be built at 500×350
    // while Constants declared 520×380 for it.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:
                            NSMakeRect(0, 0, kWelcomeWindowWidth, kWelcomeWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        self.completionHandler = handler;
        [self setupWindow];
    }
    return self;
}

- (void)setupWindow {
    self.window.title = [NSString stringWithFormat:@"Welcome to %@", kAppName];
    self.window.level = NSFloatingWindowLevel;
    // The gallery's palette is dark-only, so this window is pinned too rather than
    // letting the app open light and then turn dark.
    MacieApplyDarkAppearance(self.window);
    [self.window center];

    NSView *contentView = self.window.contentView;
    CGFloat contentW = contentView.bounds.size.width;
    CGFloat contentH = contentView.bounds.size.height;
    CGFloat inset    = kMacieSpaceXXL;
    CGFloat textW    = contentW - 2 * inset;

    // Row heights come from the fonts, so nothing is clipped and the gaps between
    // rows are the only vertical numbers in play.
    CGFloat titleH = ceil(MacieFontTitle().boundingRectForFont.size.height);
    CGFloat bodyH  = ceil(MacieFontBody().boundingRectForFont.size.height);
    CGFloat pathH  = ceil(MacieFontCaption().boundingRectForFont.size.height);
    CGFloat msgH   = 7 * bodyH;   // six lines of copy, plus one for the path wrapping

    // The buttons sit on the bottom edge; the text block is centred in what is left.
    CGFloat buttonRowTop = inset + kWelcomeButtonHeight;
    CGFloat blockH = titleH + kMacieSpaceL + msgH + kMacieSpaceL + pathH;
    CGFloat blockTop = buttonRowTop + (contentH - buttonRowTop + blockH) / 2.0;
    blockTop = MIN(blockTop, contentH - inset);

    MacieVStack *stack = [[MacieVStack alloc] initWithTop:blockTop inset:inset width:textW];

    self.titleLabel = MacieLabel([NSString stringWithFormat:@"Welcome to %@", kAppName],
                                 MacieFontTitle(), MaciePrimaryTextColor());
    self.titleLabel.alignment = NSTextAlignmentCenter;
    [contentView addSubview:self.titleLabel];
    [stack addView:self.titleLabel height:titleH followedByGap:kMacieSpaceL];

    self.messageLabel = MacieLabel(
        @"To get started, please select your Steam steamapps folder.\n\n"
         "This folder contains your Wallpaper Engine workshop content.\n\n"
         "Typical location:\n"
         "~/Library/Application Support/Steam/steamapps",
        MacieFontBody(), MacieSecondaryTextColor());
    self.messageLabel.alignment = NSTextAlignmentCenter;
    self.messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.messageLabel.usesSingleLineMode = NO;
    [contentView addSubview:self.messageLabel];
    [stack addView:self.messageLabel height:msgH followedByGap:kMacieSpaceL];

    self.pathLabel = MacieLabel(@"No folder selected", MacieFontCaption(), MacieTertiaryTextColor());
    self.pathLabel.alignment = NSTextAlignmentCenter;
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [contentView addSubview:self.pathLabel];
    [stack addView:self.pathLabel height:pathH];

    // Both buttons end on the same right inset as the copy above them, with the
    // default action rightmost. They used to be 150–350 and 360–460, which was
    // neither centred as a pair nor aligned with anything else.
    const CGFloat browseW = 224.0;
    const CGFloat quitW   = 90.0;
    CGFloat browseX = contentW - inset - browseW;
    CGFloat quitX   = browseX - kMacieSpaceM - quitW;

    self.quitButton = [[NSButton alloc] initWithFrame:
        NSMakeRect(quitX, inset, quitW, kWelcomeButtonHeight)];
    self.quitButton.title = @"Quit";
    self.quitButton.font = MacieFontBody();
    self.quitButton.bezelStyle = NSBezelStyleRounded;
    [self.quitButton setButtonType:NSButtonTypeMomentaryPushIn];
    self.quitButton.target = self;
    self.quitButton.action = @selector(quit:);
    [contentView addSubview:self.quitButton];

    self.browseButton = [[NSButton alloc] initWithFrame:
        NSMakeRect(browseX, inset, browseW, kWelcomeButtonHeight)];
    self.browseButton.title = @"Browse for Steamapps Folder";
    self.browseButton.font = MacieFontBody();
    self.browseButton.bezelStyle = NSBezelStyleRounded;
    self.browseButton.keyEquivalent = @"\r";
    [self.browseButton setButtonType:NSButtonTypeMomentaryPushIn];
    self.browseButton.target = self;
    self.browseButton.action = @selector(browseFolder:);
    [contentView addSubview:self.browseButton];
}

- (void)browseFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Select Steamapps Folder";
    panel.message = @"Please locate your steamapps folder";
    panel.prompt = @"Select";
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = NO;
    
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *selectedURL = panel.URL;
            NSString *selectedPath = selectedURL.path;
            
            NSString *workshopPath = [selectedPath stringByAppendingPathComponent:kWorkshopSubpath];
            BOOL isDirectory;
            BOOL workshopExists = [[NSFileManager defaultManager] fileExistsAtPath:workshopPath isDirectory:&isDirectory];
            
            if (!workshopExists || !isDirectory) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Invalid Folder";
                alert.informativeText = @"Selected folder does not contain Wallpaper Engine workshop content.\n\nPlease select the 'steamapps' folder that contains:\nworkshop/content/431960/";
                alert.alertStyle = NSAlertStyleWarning;
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
                return;
            }
            
            self.selectedSteamappsPath = selectedPath;
            self.pathLabel.stringValue = selectedPath;
            self.pathLabel.textColor = [NSColor systemGreenColor];
            self.browseButton.title = @"Continue";
            self.browseButton.action = @selector(continueWithSelection:);
        }
    }];
}

- (void)continueWithSelection:(id)sender {
    if (!self.selectedSteamappsPath || !self.completionHandler) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.selectedSteamappsPath forKey:kDefaultsSteamappsPath];

    // Keep a local strong reference and clear the property before invoking, so the
    // handler survives even if it releases the last reference to this controller.
    void (^handler)(NSString *) = self.completionHandler;
    self.completionHandler = nil;

    NSString *path = self.selectedSteamappsPath;
    [self.window close];
    handler(path);
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end

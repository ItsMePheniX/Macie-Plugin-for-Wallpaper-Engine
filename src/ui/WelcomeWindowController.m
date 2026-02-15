//
//  WelcomeWindowController.m
//  MacieWallpaper - Welcome Window
//
//  Created on 2026-02-15.
//

#import "WelcomeWindowController.h"
#import "Constants.h"

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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 350)
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
    [self.window center];
    
    NSView *contentView = self.window.contentView;
    
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(50, 260, 400, 40)];
    self.titleLabel.stringValue = [NSString stringWithFormat:@"Welcome to %@", kAppName];
    self.titleLabel.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
    self.titleLabel.textColor = [NSColor labelColor];
    self.titleLabel.alignment = NSTextAlignmentCenter;
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.backgroundColor = [NSColor clearColor];
    [contentView addSubview:self.titleLabel];
    
    self.messageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 140, 420, 100)];
    self.messageLabel.stringValue = @"To get started, please select your Steam steamapps folder.\n\nThis folder contains your Wallpaper Engine workshop content.\n\nTypical location:\n/Users/[username]/Library/Application Support/Steam/steamapps";
    self.messageLabel.font = [NSFont systemFontOfSize:13];
    self.messageLabel.textColor = [NSColor secondaryLabelColor];
    self.messageLabel.alignment = NSTextAlignmentCenter;
    self.messageLabel.editable = NO;
    self.messageLabel.bordered = NO;
    self.messageLabel.backgroundColor = [NSColor clearColor];
    self.messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [contentView addSubview:self.messageLabel];
    
    self.pathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 100, 420, 30)];
    self.pathLabel.stringValue = @"No folder selected";
    self.pathLabel.font = [NSFont systemFontOfSize:11];
    self.pathLabel.textColor = [NSColor tertiaryLabelColor];
    self.pathLabel.alignment = NSTextAlignmentCenter;
    self.pathLabel.editable = NO;
    self.pathLabel.bordered = NO;
    self.pathLabel.backgroundColor = [NSColor clearColor];
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [contentView addSubview:self.pathLabel];
    
    self.browseButton = [[NSButton alloc] initWithFrame:NSMakeRect(150, 50, 200, 32)];
    self.browseButton.title = @"Browse for Steamapps Folder";
    self.browseButton.bezelStyle = NSBezelStyleRounded;
    self.browseButton.keyEquivalent = @"\r";
    [self.browseButton setButtonType:NSButtonTypeMomentaryPushIn];
    self.browseButton.target = self;
    self.browseButton.action = @selector(browseFolder:);
    [contentView addSubview:self.browseButton];
    
    self.quitButton = [[NSButton alloc] initWithFrame:NSMakeRect(360, 50, 100, 32)];
    self.quitButton.title = @"Quit";
    self.quitButton.bezelStyle = NSBezelStyleRounded;
    [self.quitButton setButtonType:NSButtonTypeMomentaryPushIn];
    self.quitButton.target = self;
    self.quitButton.action = @selector(quit:);
    [contentView addSubview:self.quitButton];
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
    if (self.selectedSteamappsPath && self.completionHandler) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:self.selectedSteamappsPath forKey:kDefaultsSteamappsPath];
        [defaults synchronize];
        
        self.completionHandler(self.selectedSteamappsPath);
        [self.window close];
    }
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end

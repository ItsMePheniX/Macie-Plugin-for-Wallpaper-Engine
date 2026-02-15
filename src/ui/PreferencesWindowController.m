//
//  PreferencesWindowController.m
//  MacieWallpaper - Preferences Window
//
//  Created on 2026-02-15.
//

#import "PreferencesWindowController.h"

@interface PreferencesWindowController ()
@property (strong, nonatomic) NSTextField *titleLabel;
@property (strong, nonatomic) NSBox *pathSection;
@property (strong, nonatomic) NSTextField *currentPathLabel;
@property (strong, nonatomic) NSTextField *pathValueLabel;
@property (strong, nonatomic) NSButton *changePathButton;
@property (strong, nonatomic) NSButton *closeButton;
@end

@implementation PreferencesWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 550, 280)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    
    self = [super initWithWindow:window];
    if (self) {
        [self setupWindow];
    }
    return self;
}

- (void)setupWindow {
    self.window.title = @"Preferences";
    [self.window center];
    
    NSView *contentView = self.window.contentView;
    
    // Title
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 220, 510, 35)];
    self.titleLabel.stringValue = @"MacieWallpaper Preferences";
    self.titleLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    self.titleLabel.textColor = [NSColor labelColor];
    self.titleLabel.alignment = NSTextAlignmentLeft;
    self.titleLabel.editable = NO;
    self.titleLabel.bordered = NO;
    self.titleLabel.backgroundColor = [NSColor clearColor];
    [contentView addSubview:self.titleLabel];
    
    // Path Section
    self.pathSection = [[NSBox alloc] initWithFrame:NSMakeRect(20, 70, 510, 130)];
    self.pathSection.title = @"Wallpaper Location";
    self.pathSection.titlePosition = NSAtTop;
    
    NSView *pathContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 490, 100)];
    
    self.currentPathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 60, 470, 20)];
    self.currentPathLabel.stringValue = @"Current Steam Folder:";
    self.currentPathLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.currentPathLabel.textColor = [NSColor labelColor];
    self.currentPathLabel.editable = NO;
    self.currentPathLabel.bordered = NO;
    self.currentPathLabel.backgroundColor = [NSColor clearColor];
    [pathContent addSubview:self.currentPathLabel];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *currentPath = [defaults stringForKey:@"steamappsPath"];
    
    self.pathValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 30, 470, 25)];
    self.pathValueLabel.stringValue = currentPath ? currentPath : @"No path set";
    self.pathValueLabel.font = [NSFont systemFontOfSize:11];
    self.pathValueLabel.textColor = currentPath ? [NSColor systemGreenColor] : [NSColor systemRedColor];
    self.pathValueLabel.editable = NO;
    self.pathValueLabel.bordered = NO;
    self.pathValueLabel.backgroundColor = [NSColor controlBackgroundColor];
    self.pathValueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.pathValueLabel.drawsBackground = YES;
    [pathContent addSubview:self.pathValueLabel];
    
    self.changePathButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, 5, 200, 24)];
    self.changePathButton.title = @"Change Steam Folder...";
    self.changePathButton.bezelStyle = NSBezelStyleRounded;
    [self.changePathButton setButtonType:NSButtonTypeMomentaryPushIn];
    self.changePathButton.target = self;
    self.changePathButton.action = @selector(changePath:);
    [pathContent addSubview:self.changePathButton];
    
    self.pathSection.contentView = pathContent;
    [contentView addSubview:self.pathSection];
    
    // Close Button
    self.closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(440, 20, 90, 32)];
    self.closeButton.title = @"Close";
    self.closeButton.bezelStyle = NSBezelStyleRounded;
    self.closeButton.keyEquivalent = @"\r";
    [self.closeButton setButtonType:NSButtonTypeMomentaryPushIn];
    self.closeButton.target = self;
    self.closeButton.action = @selector(closeWindow:);
    [contentView addSubview:self.closeButton];
}

- (void)changePath:(id)sender {
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
            
            NSString *workshopPath = [selectedPath stringByAppendingPathComponent:@"workshop/content/431960"];
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
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:selectedPath forKey:@"steamappsPath"];
            [defaults synchronize];
            
            self.pathValueLabel.stringValue = selectedPath;
            self.pathValueLabel.textColor = [NSColor systemGreenColor];
            
            if (self.onPathChanged) {
                self.onPathChanged();
            }
        }
    }];
}

- (void)closeWindow:(id)sender {
    [self.window close];
}

@end

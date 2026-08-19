//
//  AVVideoRenderer.h
//  MacieWallpaper - Video Renderer
//
//  Created on 2026-02-14.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>

@interface AVVideoRenderer : NSObject

@property (strong, nonatomic, readonly) AVPlayer *player;
@property (strong, nonatomic, readonly) AVPlayerLayer *playerLayer;
/// Last non-zero volume, restored by -unmute. Set via -setVolume:.
@property (nonatomic, readonly) float volume;
/// Survives -loadAndPlayVideo:, so switching wallpapers keeps the audio state.
@property (nonatomic, readonly) BOOL muted;

- (instancetype)initWithWindow:(NSWindow *)window;
- (BOOL)loadAndPlayVideo:(NSString *)filePath;

- (void)play;
- (void)pause;
- (void)stop;

- (void)mute;
- (void)unmute;
- (void)setVolume:(float)volume;

- (BOOL)isPlaying;

@end

//
//  AVVideoRenderer.mm
//  MacieWallpaper - Video Renderer
//
//  Created on 2026-02-14.
//

#import "AVVideoRenderer.h"
#import <AVKit/AVKit.h>

@interface AVVideoRenderer ()
@property (weak, nonatomic) NSWindow *window;
@property (strong, nonatomic) AVQueuePlayer *queuePlayer;
@property (strong, nonatomic) AVPlayerItem *playerItem;
@end

@implementation AVVideoRenderer

- (instancetype)initWithWindow:(NSWindow *)window {
    self = [super init];
    if (self) {
        self.window = window;
        NSLog(@"AVVideoRenderer: Initialized with window");
    }
    return self;
}

- (BOOL)loadAndPlayVideo:(NSString *)filePath {
    NSLog(@"AVVideoRenderer: Loading video: %@", filePath);
    
    // Verify file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"  ERROR: Video file not found at path: %@", filePath);
        return NO;
    }
    
    // Create URL from file path
    NSURL *videoURL = [NSURL fileURLWithPath:filePath];
    
    // Clean up previous player if exists
    [self stop];
    
    // Create player item
    self.playerItem = [AVPlayerItem playerItemWithURL:videoURL];
    self.playerItem.preferredForwardBufferDuration = 2.0;
    
    self.queuePlayer = [[AVQueuePlayer alloc] initWithItems:@[self.playerItem]];
    
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.queuePlayer
                                            templateItem:self.playerItem];
    
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.queuePlayer];
    self.playerLayer.frame = self.window.contentView.bounds;
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.playerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    
    [self.window.contentView setWantsLayer:YES];
    [self.window.contentView.layer addSublayer:self.playerLayer];
    
    [self.queuePlayer play];
    
    self.queuePlayer.volume = 0.0;
    _volume = 0.0;
    _muted = YES;
    
    NSLog(@"AVVideoRenderer: Video loaded and playing");
    NSLog(@"  Resolution: %@", NSStringFromSize(self.playerItem.presentationSize));
    
    [self.playerItem addObserver:self
                      forKeyPath:@"status"
                         options:NSKeyValueObservingOptionNew
                         context:nil];
    
    return YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusFailed) {
            NSLog(@"  ERROR: Video playback failed: %@", item.error.localizedDescription);
        } else if (item.status == AVPlayerItemStatusReadyToPlay) {
            NSLog(@"   Video ready to play");
        }
    }
}

- (void)play {
    if (self.queuePlayer) {
        [self.queuePlayer play];
        NSLog(@"AVVideoRenderer: Playing");
    }
}

- (void)pause {
    if (self.queuePlayer) {
        [self.queuePlayer pause];
        NSLog(@"AVVideoRenderer: Paused");
    }
}

- (void)stop {
    if (self.queuePlayer) {
        [self.queuePlayer pause];
        
        if (self.playerItem) {
            [self.playerItem removeObserver:self forKeyPath:@"status"];
        }
        
        if (self.looper) {
            [self.looper disableLooping];
            self.looper = nil;
        }
        
        if (self.playerLayer) {
            [self.playerLayer removeFromSuperlayer];
            _playerLayer = nil;
        }
        
        self.queuePlayer = nil;
        self.playerItem = nil;
        
        NSLog(@"AVVideoRenderer: Stopped and cleaned up");
    }
}

- (BOOL)isPlaying {
    return self.queuePlayer && self.queuePlayer.rate > 0.0;
}

#pragma mark - Volume Controls

- (void)mute {
    _muted = YES;
    self.queuePlayer.volume = 0.0;
}

- (void)unmute {
    _muted = NO;
    self.queuePlayer.volume = _volume > 0 ? _volume : 0.5;
    if (_volume == 0) {
        _volume = 0.5;
    }
}

- (void)setVolume:(float)volume {
    _volume = MAX(0.0, MIN(1.0, volume));
    if (!_muted) {
        self.queuePlayer.volume = _volume;
    }
}

- (AVPlayer *)player {
    return self.queuePlayer;
}

- (void)dealloc {
    [self stop];
    NSLog(@"AVVideoRenderer: Deallocated");
}

@end

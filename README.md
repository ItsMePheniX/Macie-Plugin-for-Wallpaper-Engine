# Macie-Plugin-for-Wallpaper-Engine

> **Note**: This is a personal project built for my own use. Contributions, suggestions, and improvements from others are always appreciated!

A lightweight macOS desktop application that plays Wallpaper Engine videos as desktop wallpapers using native macOS frameworks. Features a modern dark-themed gallery interface for browsing and managing wallpapers.

## Project Overview

This application plays Wallpaper Engine video wallpapers directly on your macOS desktop, behind your desktop icons. Browse and select from your Wallpaper Engine library using an intuitive gallery interface with thumbnail previews, sidebar navigation, and performance optimizations.

## Architecture

### Technology Stack

- **Build System**: CMake 3.20+
- **Core Engine**: C++17
- **macOS Bridge**: Objective-C++
- **UI Layer**: Objective-C + AppKit (NSWindow, NSCollectionView)
- **Video Playback**: AVFoundation (hardware-accelerated)
- **Rendering**: AVPlayerLayer + QuartzCore
- **Frameworks**: Cocoa, AVFoundation, CoreMedia, Metal, QuartzCore, IOKit

## Current Features

### Implemented
- **Desktop Wallpaper Video Playback**: Seamless video looping behind desktop icons
- **Thumbnail Caching**: Memory + disk cache for fast loading (`~/Library/Caches/MacieWallpaper/thumbnails/`)
- **Performance Monitor**: Auto-pause on battery power or fullscreen apps (configurable)
- **Async Thumbnail Generation**: Non-blocking thumbnail extraction using AVAssetImageGenerator
- **Video Selection**: Click any thumbnail to instantly switch wallpapers
- **Audio Controls**: State-aware mute/unmute toggle (muted by default)
- **Wallpaper Engine Integration**: Automatic scanning of Steam Workshop directory
- **Welcome Window**: First-launch setup wizard for steamapps selection
- **In-Window Preferences**: Settings panel with path, performance, and cache options
- **Configurable Steam Path**: Folder picker to select steamapps location (saved in preferences)
- **Window Management**: Positioned at `kCGDesktopWindowLevel - 1` for proper layering
- **Mouse Passthrough**: Desktop icons remain fully clickable
- **Universal Binary**: Supports both Apple Silicon (ARM64) and Intel (x86_64)

### Video Playback Features
- AVFoundation-based renderer with hardware acceleration
- AVPlayerLooper for seamless, gap-free looping
- Efficient buffering (2 second forward buffer)
- Automatic video file validation
- Support for MP4, MOV, and all AVFoundation-compatible formats

### Performance Characteristics
- **CPU Usage**: ~2-5% during playback (hardware accelerated)
- **Memory**: ~150-200MB (including video buffers)
- **Startup Time**: <2 seconds (including workshop scan)
- **Video Switching**: Instant (<100ms)
- **Thumbnail Generation**: Async, non-blocking

## Technical Implementation

### 1. Desktop Window Management
- Borderless NSWindow positioned at `kCGDesktopWindowLevel - 1`
- Window level: -2147483624 (behind desktop icons, above desktop picture)
- Collection behavior: Stationary, all spaces, ignore cycle
- Mouse events: Passthrough enabled (`ignoresMouseEvents = YES`)
- Screen parameter monitoring for display changes

### 2. Video Rendering
- AVQueuePlayer with AVPlayerLooper for seamless looping
- AVPlayerLayer added to window's content view
- Video gravity: `AVLayerVideoGravityResizeAspectFill`
- Default state: Muted (volume = 0.0)
- Status monitoring via KVO on player item

### 3. Asset Management
- First launch shows welcome window to select steamapps directory
- Selected path saved to NSUserDefaults for persistence
- Validates folder contains `/workshop/content/431960/`
- Menu item to change location anytime (Cmd+L)
- Custom JSON parser for project.json files
- Filters for video-type wallpapers only
- Validates file existence before adding to collection
- Extracts: title, type, file path, preview, description

### 4. Thumbnail Caching
- Dual-layer cache: NSCache (memory) + disk storage (PNG files)
- Cache location: `~/Library/Caches/MacieWallpaper/thumbnails/`
- Memory cache limit: 100 items
- Async generation with GCD concurrent queue
- Prioritizes preview.jpg, falls back to video frame extraction
- Background pre-generation for all wallpapers

### 5. Performance Monitor
- Power source monitoring via IOPSNotificationCreateRunLoopSource
- Fullscreen app detection via CGWindowListCopyWindowInfo
- Configurable pause-on-battery option
- Configurable pause-on-fullscreen option
- Delegate pattern for playback control notifications

### 6. Gallery UI
- Dark-themed interface with sidebar navigation
- NSCollectionView with flow layout
- Wallpaper cards with hover animations (CATransform3D scale)
- Selection highlighting with blue border and glow
- Item size: 200x150 with 12px rounded corners
- Grid spacing: 20pt between items
- Resizable window (minimum 800x500, default 1000x650)

## Project Structure

```
Macie-Plugin-for-Wallpaper-Engine/
├── CMakeLists.txt              # Build configuration
├── include/                    # Header files
│   ├── AppDelegate.h
│   ├── AssetManager.hpp        # C++ asset management
│   ├── AVVideoRenderer.h
│   ├── ConfigManager.hpp       # Configuration (placeholder)
│   ├── Constants.h             # App constants and defaults
│   ├── DesktopWindowManager.h  # Window management (placeholder)
│   ├── MainWindowController.h
│   ├── PerformanceMonitor.h    # Battery/fullscreen detection
│   ├── PreferencesWindowController.h
│   ├── ThumbnailCache.h        # Thumbnail caching system
│   ├── VideoCollectionItem.h
│   ├── WallpaperEngine.hpp     # Core engine (placeholder)
│   └── WelcomeWindowController.h
├── src/
│   ├── main.m                  # Application entry point
│   ├── AppDelegate.mm          # App lifecycle management
│   ├── core/                   # C++ core engine
│   │   ├── AssetManager.cpp    # Workshop scanning, JSON parsing
│   │   ├── ConfigManager.cpp   # Configuration (placeholder)
│   │   ├── PerformanceMonitor.mm # Power source & fullscreen monitoring
│   │   ├── ThumbnailCache.mm   # Memory + disk thumbnail cache
│   │   └── WallpaperEngine.cpp # Core engine (placeholder)
│   ├── renderers/
│   │   ├── AVVideoRenderer.mm  # Video playback & looping
│   │   └── DesktopWindowManager.mm
│   └── ui/                     # User interface
│       ├── MainWindowController.mm  # Gallery window with sidebar
│       ├── PreferencesWindowController.m # Standalone preferences
│       ├── VideoCollectionItem.m    # Grid item with hover effects
│       └── WelcomeWindowController.m # First-launch wizard
└── build/                      # CMake build output
    └── MacieWallpaper.app
```

## Project Completion Checklist

### Phase 1: Core Foundation (COMPLETED)
- [x] CMake build system configuration
- [x] C++ core engine structure (AssetManager, WallpaperEngine, ConfigManager)
- [x] Objective-C++ bridge layer
- [x] Desktop window creation and positioning
- [x] Window level management (behind desktop icons)
- [x] Mouse passthrough for desktop icons
- [x] Universal binary support (ARM64 + x86_64)

### Phase 2: Video Playback (COMPLETED)
- [x] AVFoundation video renderer implementation
- [x] AVPlayerLooper for seamless looping
- [x] Video file validation
- [x] Hardware-accelerated playback
- [x] Volume and mute controls
- [x] Playback state management

### Phase 3: Wallpaper Engine Integration (COMPLETED)
- [x] Workshop directory scanning
- [x] project.json parser (custom lightweight parser)
- [x] Video metadata extraction (title, type, file path)
- [x] File existence validation
- [x] Type filtering (video wallpapers only)

### Phase 4: Gallery UI (COMPLETED)
- [x] Main window controller with NSCollectionView
- [x] Collection view flow layout
- [x] Video collection item UI components
- [x] Async thumbnail generation from videos
- [x] Thumbnail display in grid
- [x] Video selection handling
- [x] Mute/unmute button in toolbar
- [x] Video count display
- [x] Window resizing support

### Phase 5: Polish & Enhancement (COMPLETED)
- [x] README documentation
- [x] Configurable Steam path (via folder picker)
- [x] Path saved in NSUserDefaults preferences
- [x] Menu bar with "Change Wallpaper Location"
- [x] State-aware mute button (checks before toggling)
- [x] Persistent thumbnail cache (memory + disk)
- [x] Dark-themed UI with sidebar navigation
- [x] Welcome window for first-launch setup
- [x] In-window preferences panel
- [x] Hover animations on wallpaper cards
- [x] Performance monitor (battery/fullscreen detection)
- [ ] Launch at login option
- [ ] Additional keyboard shortcuts

### Phase 6: Advanced Features (May or may not do it)
- [ ] Multi-monitor support (different wallpapers per screen)
- [ ] Favorites and collections system
- [ ] Playlist mode with auto-rotation
- [ ] Time-based wallpaper switching
- [ ] Custom video import (drag and drop)
- [ ] Scene wallpaper support (3D/interactive)
- [ ] Performance profiles (quality presets)
- [ ] Video playback speed control
- [ ] Search and filter in gallery
- [ ] Custom video filters/effects


## Future Enhancements

Additional features under consideration:
- Favorites and collections system
- Search bar with filters (resolution, duration, tags)
- Preview panel with larger video playback
- iCloud settings sync
- Multi-monitor support with per-display wallpapers
- Sleep/wake event handling
- Launch at login option
- Playlist mode with scheduling

## Requirements

- **macOS**: 12.0+ (Monterey or later)
- **CMake**: 3.20 or higher
- **Xcode Command Line Tools**: For C/C++/Objective-C compilation
- **Wallpaper Engine**: Videos in Steam Workshop directory
- **Apple Developer Account**: Optional (for code signing)

### System Requirements
- **Architecture**: Apple Silicon (ARM64) or Intel (x86_64)
- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 100MB for app, plus space for Wallpaper Engine videos
- **Display**: Any resolution (tested on Retina displays, MBA(m4))

## Building from Source

```bash
# Clone repository
git clone https://github.com/ItsMePheniX/Macie-Plugin-for-Wallpaper-Engine.git
cd Macie-Plugin-for-Wallpaper-Engine

# Configure with CMake
cmake -S . -B build -G "Unix Makefiles"

# Build
cmake --build build

# Run
open build/MacieWallpaper.app
```

### VS Code Tasks (Pre-configured)

```bash
# Configure build
Cmd+Shift+P -> "Tasks: Run Task" -> "CMake: Configure"

# Build project (default: Cmd+Shift+B)
Cmd+Shift+P -> "Tasks: Run Build Task" -> "CMake: Build"

# Run application
Cmd+Shift+P -> "Tasks: Run Task" -> "Run App"

# Clean build
Cmd+Shift+P -> "Tasks: Run Task" -> "CMake: Clean"
```

## Usage

1. **First Launch**: Welcome window guides you to select your steamapps folder
   - Usually located at: `/Users/[username]/Library/Application Support/Steam/steamapps`
   - Or: `/Users/[username]/steamapps` (if you've moved Steam)
   - Must contain: `workshop/content/431960/` (Wallpaper Engine workshop)

2. **Automatic Scan**: App scans your Wallpaper Engine videos and caches thumbnails
3. **Gallery Opens**: Browse thumbnails in a dark-themed gallery with sidebar
4. **Select Wallpaper**: Click any thumbnail to set as wallpaper
5. **Audio Control**: Use the "Mute/Unmute" button in the sidebar
6. **Preferences**: Click "Preferences" in sidebar to access settings:
   - Change Steam folder location
   - Enable/disable pause on battery
   - Enable/disable pause when apps are fullscreen
   - Clear thumbnail cache
7. **Quit**: Press `Cmd+Q` or choose Quit from menu

## Known Limitations

- **Single Monitor**: Multi-monitor support not yet implemented
- **Video Types Only**: Only supports video wallpapers (no scenes or web types)
- **Basic JSON Parser**: Custom parser, not a full JSON library
- **No Playlist Mode**: Manual wallpaper selection required

## Troubleshooting

### No Videos Found
- Verify Wallpaper Engine is installed via Steam
- Check path: `/Users/[username]/steamapps/workshop/content/431960/`
- Ensure you have subscribed to video wallpapers in Workshop

### Window Not Behind Icons
- Check Console.app for window level messages
- Try restarting the application
- System may reset window level on display changes

### Video Not Playing
- Check video file format (MP4, MOV recommended)
- Verify file exists and is not corrupted
- Check Console.app for AVFoundation errors

### Build Errors
```bash
# Clean and rebuild
rm -rf build
cmake -S . -B build
cmake --build build
```

## Code Quality

- Zero compilation warnings
- CamelCase naming conventions enforced
- ARC (Automatic Reference Counting) enabled
- No deprecated API usage
- Clean codebase (minimal comments, no emojis)

## Design Decisions

### Why CMake over Xcode?
- **Cross-platform build system**: Works with any IDE
- **Command-line friendly**: Easy CI/CD integration
- **VS Code integration**: Full development without Xcode
- **Flexibility**: Easy to modify build configuration

### Why Objective-C++ over Swift?
- **Direct C++ integration**: No bridging overhead
- **Memory control**: More granular management
- **Mature tooling**: Well-established patterns
- **Performance**: No Swift runtime overhead

### Why AVFoundation?
- **Native framework**: No external dependencies
- **Hardware acceleration**: VideoToolbox integration
- **Codec support**: All formats out of the box
- **Efficiency**: Minimal CPU and battery impact

### Why Custom JSON Parser?
- **Simplicity**: Only need basic key-value extraction
- **No dependencies**: Avoid external libraries
- **Sufficient**: Works reliably for project.json structure
- **Lightweight**: Minimal code footprint


## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

### Development Setup
1. Fork the repository
2. Clone your fork
3. Create a feature branch
4. Make your changes
5. Test thoroughly
6. Submit a pull request


## License

See LICENSE file for details.
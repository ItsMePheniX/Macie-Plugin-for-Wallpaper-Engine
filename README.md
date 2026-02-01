# Macie-Plugin-for-Wallpaper-Engine

A lightweight macOS desktop application that plays Wallpaper Engine videos as desktop wallpapers using native macOS frameworks. Features a gallery-style GUI for browsing and managing wallpapers, with optional menu bar integration for quick access.

## Project Overview

This application provides a rich desktop GUI experience for browsing, previewing, and setting Wallpaper Engine videos as animated wallpapers on macOS. The main window features a sidebar navigation, thumbnail gallery grid, and large preview panel. An optional menu bar integration provides quick access when needed.

## Architecture

### Technology Stack

- **Core Engine**: C++
- **macOS Bridge**: Objective-C++
- **UI Layer**: Objective-C + AppKit
- **Video Playback**: AVFoundation (hardware-accelerated)
- **Rendering**: Metal (via CAMetalLayer) for GPU efficiency
- **Window Management**: AppKit (NSWindow, NSView)


## Technical Approach

### 1. Video Playback Engine
- **AVFoundation** for native video decoding
- Hardware-accelerated playback (VideoToolbox)
- Seamless looping with `AVPlayerLooper`
- Minimal CPU usage (~2-5%)

### 2. Desktop Integration
- Borderless `NSWindow` positioned behind desktop icons
- Use `CGWindowLevelForKey(kCGDesktopWindowLevelKey)` for proper layering
- Handles multi-monitor setups
- Survives screen wake/sleep/unlock

### 3. UI Components

**Primary GUI Application:**
- Main gallery window with video thumbnail grid (`NSCollectionView`)
- Sidebar navigation (Library, Favorites, Recent, Settings)
- Large preview panel with video playback
- Bottom toolbar: Play controls, Apply, Settings
- Search bar with filters (resolution, duration, tags)
- Dock icon for primary access

**Menu Bar (Optional Feature):**
- Status item for quick access when app is running
- Quick menu: Show Gallery, Pause/Resume, Current Wallpaper, Quit
- Can be disabled in preferences

### 4. Performance Optimizations
- Pause playback when on battery power (optional)
- CPU usage monitoring with auto-pause
- Thumbnail cache for fast gallery loading
- Lazy loading of video assets

## Core Features

### Phase 1 (MVP)
- [ ] Main gallery window with grid layout
- [ ] Sidebar navigation (Library, Favorites, Recent)
- [ ] Browse Wallpaper Engine video directory
- [ ] Video thumbnail generation
- [ ] Preview panel with playback
- [ ] Set video as wallpaper
- [ ] Seamless video looping
- [ ] Basic settings (pause on battery)

### Phase 2 (Enhancement)
- [ ] Menu bar integration (optional)
- [ ] Favorites & collections management
- [ ] Multi-monitor support (different videos per screen)
- [ ] Playlist mode (rotate wallpapers)
- [ ] Audio toggle
- [ ] Custom video import
- [ ] Keyboard shortcuts
- [ ] Drag & drop video files

### Phase 3 (Advanced)
- [ ] Time-based wallpaper switching
- [ ] Performance profiles (low/medium/high quality)
- [ ] iCloud sync for settings
- [ ] Launch at login

## Implementation Plan

### Step 1: Project Setup
- Create new Xcode project (macOS App template)
- Configure build settings for Objective-C++/C++ mix
- Add target for C++ static library (WallpaperCore)
- Link frameworks: AVFoundation, AppKit, Metal, CoreAnimation
- Setup XIB files for UI layouts
- Configure code signing

### Step 2: Core C++ Engine
- Implement `WallpaperEngine` class
- Asset scanning and management
- Configuration persistence (JSON/plist)

### Step 3: AVFoundation Renderer
- Create `AVVideoRenderer` with AVPlayer
- Implement looping mechanism
- Desktop window positioning (behind icons)

### Step 4: Main GUI
- Design main window layout in Interface Builder (.xib)
- Create MainWindow.xib with sidebar, gallery, and preview panels
- Implement MainWindowController with IBOutlets and IBActions
- Create SidebarViewController with navigation
- Build GalleryViewController with NSCollectionView
- Add PreviewPanelController with AVPlayerView
- Design toolbar and bottom controls in IB

### Step 5: Gallery Features
- Thumbnail generation pipeline (async)
- Collection view data source
- Search and filter implementation
- Thumbnail caching system

### Step 6: Optional Menu Bar
- Add MenuBarController (toggleable)
- Status item and menu
- Quick actions integration

### Step 7: Integration & Testing
- Bridge C++ and Objective-C components
- Multi-monitor testing
- Performance profiling
- Battery impact testing

## Technical Requirements

- **macOS**: 12.0+ (Monterey or later)
- **IDE**: Xcode 14.0+
- **Languages**: C++17, Objective-C/Objective-C++
- **Frameworks**: AVFoundation, AppKit, Metal, CoreAnimation
- **Apple Developer Account**: Required for code signing and notarization

## Design Decisions

### Why Xcode over VS Code?
- **Interface Builder**: Visual UI design with XIB files
- **Asset Catalog Management**: Easy icon and image management
- **Automatic Code Signing**: Seamless signing and notarization
- **Native Debugging**: Instruments, view debugger, memory graph
- **Proven Workflow**: Standard toolchain for macOS apps

### Why Objective-C++ over Swift?
- Direct access to C++ core engine
- No Swift/C++ bridging overhead
- More control over memory management
- And cuz i dont know Swift

### Why AVFoundation over alternatives?
- Native macOS framework (no dependencies)
- Hardware-accelerated (VideoToolbox)
- Supports all codecs out of the box
- Minimal CPU/battery impact
- Proven reliability

### Why GUI-First with Optional Menu Bar?
- **Primary GUI**: Rich visual browsing experience for wallpaper selection
- **Gallery Layout**: Better for previewing and comparing multiple videos
- **Full Control**: Complete access to all features in one window
- **Menu Bar**: Optional quick access without opening main window
- **Flexibility**: Users can choose their preferred interaction style


## Building

```bash
# Clone repository
git clone https://github.com/ItsMePheniX/Macie-Plugin-for-Wallpaper-Engine.git
cd Macie-Plugin-for-Wallpaper-Engine

# Open in Xcode
open MacieWallpaper.xcodeproj

# Build and run in Xcode
# Press ⌘ + R or Product > Run
```

### Xcode Setup

**Project Configuration:**
1. Open Xcode project
2. Select project in navigator
3. Go to "Signing & Capabilities"
4. Enable "Automatically manage signing"
5. Select your Team (Apple Developer account)

**Build Configuration:**
- **Deployment Target**: macOS 12.0
- **Supported Architectures**: arm64, x86_64 (Universal)
- **C++ Language Dialect**: C++17
- **Objective-C ARC**: Enabled

**Debugging:**
- Use Xcode's built-in debugger (⌘ + Y to toggle breakpoints)
- View hierarchy debugger for UI issues
- Instruments for performance profiling

## License

See LICENSE file for details.
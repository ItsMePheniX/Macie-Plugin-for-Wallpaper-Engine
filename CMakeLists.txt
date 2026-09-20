cmake_minimum_required(VERSION 3.20)

project(MacieWallpaper LANGUAGES C CXX)

# Set C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# macOS specific settings
set(CMAKE_OSX_DEPLOYMENT_TARGET 12.0)
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")  # Universal binary

# Use Objective-C/C++ compiler (clang)
set(CMAKE_C_COMPILER "/usr/bin/clang")
set(CMAKE_CXX_COMPILER "/usr/bin/clang++")

# Enable Objective-C and Objective-C++ compilation.
# -Wno-unused-parameter: AppKit delegate and target/action methods routinely ignore
# parameters they are required to declare, so the warning is noise here.
set(WARNING_FLAGS "-Wall -Wextra -Wno-unused-parameter")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fobjc-arc ${WARNING_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fobjc-arc ${WARNING_FLAGS}")

# Find required frameworks
find_library(COCOA_LIBRARY Cocoa REQUIRED)
find_library(AVFOUNDATION_LIBRARY AVFoundation REQUIRED)
find_library(COREMEDIA_LIBRARY CoreMedia REQUIRED)
find_library(METAL_LIBRARY Metal REQUIRED)
find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
find_library(IOKIT_LIBRARY IOKit REQUIRED)
find_library(SERVICEMANAGEMENT_LIBRARY ServiceManagement REQUIRED)
find_library(IMAGEIO_LIBRARY ImageIO REQUIRED)
# UniformTypeIdentifiers supplies UTTypePNG, used by ThumbnailCache to write PNGs
# without the deprecated kUTTypePNG constant.
find_library(UNIFORMTYPEIDENTIFIERS_LIBRARY UniformTypeIdentifiers REQUIRED)
# ColorSync supplies CGDisplayCreateUUIDFromDisplayID, which is how a monitor is
# identified across reconnects — CGDirectDisplayIDs are reassigned and cannot be stored.
find_library(COLORSYNC_LIBRARY ColorSync REQUIRED)

# Source files
set(SOURCES
    # Main app
    src/main.m
    src/AppDelegate.mm

    # Core
    src/core/Constants.m
<<<<<<< HEAD
    src/core/MacieDisplayIdentity.m         # stable per-monitor keys and display names
    src/core/LastWallpaperSnapshot.m        # display key -> last-played wallpaper, restored before the scan
    src/core/WallpaperDisplay.m             # one screen: its desktop window and renderer
    src/core/WallpaperDisplayManager.m      # every screen, and what to do as they come and go
=======
>>>>>>> origin/main
    src/core/AssetManager.mm               # Obj-C++: NSJSONSerialization behind a C++ API
    src/core/MacieAssetManagerWrapper.mm   # Typed Obj-C++ wrapper for AssetManager
    src/core/ThumbnailCache.mm
    src/core/WallpaperMetadataCache.mm
    src/core/PerformanceMonitor.mm

    # Renderers (Objective-C++)
    src/renderers/AVVideoRenderer.mm

    # UI (Objective-C)
    src/ui/DesignSystem.m                  # fonts, palette, spacing, control factories
    src/ui/MainWindowController.mm
    src/ui/SidebarView.m
    src/ui/HeroPanelView.m
    src/ui/GalleryEmptyStateView.m
    src/ui/SettingsSheetController.m
    src/ui/VideoCollectionItem.m
    src/ui/WelcomeWindowController.m

    # Resources
    resources/AppIcon.icns
)

# Header files
set(HEADERS
    include/AssetManager.hpp
    include/MacieAssetManagerWrapper.h
    include/AVVideoRenderer.h
    include/DesignSystem.h
    include/MainWindowController.h
    include/SidebarView.h
    include/HeroPanelView.h
    include/GalleryEmptyStateView.h
    include/SettingsSheetController.h
    include/VideoCollectionItem.h
    include/WelcomeWindowController.h
    include/AppDelegate.h
    include/Constants.h
<<<<<<< HEAD
    include/MacieDisplayIdentity.h
    include/LastWallpaperSnapshot.h
    include/WallpaperDisplay.h
    include/WallpaperDisplayManager.h
=======
>>>>>>> origin/main
    include/ThumbnailCache.h
    include/WallpaperMetadataCache.h
    include/PerformanceMonitor.h
)

# Create executable
add_executable(${PROJECT_NAME} MACOSX_BUNDLE ${SOURCES} ${HEADERS})

# Link frameworks
target_link_libraries(${PROJECT_NAME}
    PRIVATE
    ${COCOA_LIBRARY}
    ${AVFOUNDATION_LIBRARY}
    ${COREMEDIA_LIBRARY}
    ${METAL_LIBRARY}
    ${QUARTZCORE_LIBRARY}
    ${IOKIT_LIBRARY}
    ${SERVICEMANAGEMENT_LIBRARY}
    ${IMAGEIO_LIBRARY}
    ${UNIFORMTYPEIDENTIFIERS_LIBRARY}
    ${COLORSYNC_LIBRARY}
)

# Include directories
target_include_directories(${PROJECT_NAME}
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# macOS bundle settings
set_target_properties(${PROJECT_NAME} PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.macie.MacieWallpaper"
    MACOSX_BUNDLE_BUNDLE_NAME "MacieWallpaper"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0.0"
    MACOSX_BUNDLE_COPYRIGHT "Copyright © 2026. All rights reserved."
    MACOSX_BUNDLE_ICON_FILE "AppIcon"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
    XCODE_ATTRIBUTE_CODE_SIGN_REQUIRED "NO"
)

# Mark the icns as a bundle resource so CMake copies it into Contents/Resources
set_source_files_properties(resources/AppIcon.icns PROPERTIES
    MACOSX_PACKAGE_LOCATION "Resources"
)

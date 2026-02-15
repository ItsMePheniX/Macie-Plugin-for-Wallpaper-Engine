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

# Enable Objective-C and Objective-C++ compilation
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fobjc-arc")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fobjc-arc")

# Find required frameworks
find_library(COCOA_LIBRARY Cocoa REQUIRED)
find_library(AVFOUNDATION_LIBRARY AVFoundation REQUIRED)
find_library(COREMEDIA_LIBRARY CoreMedia REQUIRED)
find_library(METAL_LIBRARY Metal REQUIRED)
find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
find_library(IOKIT_LIBRARY IOKit REQUIRED)

# Source files
set(SOURCES
    # Main app
    src/main.m
    src/AppDelegate.mm
    
    # Core C++ engine
    src/core/WallpaperEngine.cpp
    src/core/AssetManager.cpp
    src/core/ConfigManager.cpp
    src/core/ThumbnailCache.mm
    src/core/PerformanceMonitor.mm
    
    # Renderers (Objective-C++)
    src/renderers/AVVideoRenderer.mm
    src/renderers/DesktopWindowManager.mm
    
    # UI (Objective-C)
    src/ui/MainWindowController.mm
    src/ui/VideoCollectionItem.m
    src/ui/WelcomeWindowController.m
    src/ui/PreferencesWindowController.m
)

# Header files
set(HEADERS
    include/WallpaperEngine.hpp
    include/AssetManager.hpp
    include/ConfigManager.hpp
    include/AVVideoRenderer.h
    include/DesktopWindowManager.h
    include/MainWindowController.h
    include/VideoCollectionItem.h
    include/WelcomeWindowController.h
    include/PreferencesWindowController.h
    include/AppDelegate.h
    include/Constants.h
    include/ThumbnailCache.h
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
    MACOSX_BUNDLE_BUNDLE_VERSION "0.0.1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.0.1"
    MACOSX_BUNDLE_COPYRIGHT "Copyright © 2026. All rights reserved."
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
    XCODE_ATTRIBUTE_CODE_SIGN_REQUIRED "NO"
)

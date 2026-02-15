//
//  WallpaperEngine.cpp
//  MacieWallpaper - Core Engine
//
//  Created on 2026-02-14.
//  Note: Placeholder for future scene/web wallpaper support
//

#include "WallpaperEngine.hpp"

namespace Macie {

WallpaperEngine::WallpaperEngine() : isInitialized(false) {
}

WallpaperEngine::~WallpaperEngine() {
}

void WallpaperEngine::initialize() {
    if (!isInitialized) {
        isInitialized = true;
    }
}

void WallpaperEngine::shutdown() {
    if (isInitialized) {
        isInitialized = false;
    }
}

} // namespace Macie

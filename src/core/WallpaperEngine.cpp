//
//  WallpaperEngine.cpp
//  MacieWallpaper - Core Engine
//
//  Created on 2026-02-14.
//

#include "WallpaperEngine.hpp"
#include <iostream>

namespace Macie {

WallpaperEngine::WallpaperEngine() : isInitialized(false) {
    std::cout << "WallpaperEngine: Constructor" << std::endl;
}

WallpaperEngine::~WallpaperEngine() {
    std::cout << "WallpaperEngine: Destructor" << std::endl;
}

void WallpaperEngine::initialize() {
    if (!isInitialized) {
        std::cout << "WallpaperEngine: Initializing..." << std::endl;
        isInitialized = true;
    }
}

void WallpaperEngine::shutdown() {
    if (isInitialized) {
        std::cout << "WallpaperEngine: Shutting down..." << std::endl;
        isInitialized = false;
    }
}

} // namespace Macie
